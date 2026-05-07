const { admin, firestore, realtimeDB } = require("../firebase");
const {
  buildLocationText,
  createAlertRecord,
} = require("./alert-service");
const { getChildOrThrow } = require("./child-access");
const {
  createSystemActor,
  safeWriteAuditLogWithId,
} = require("./audit-log");

let isInitialized = false;
let rootChildAddedHandler = null;
let rootChildChangedHandler = null;
let rootChildRemovedHandler = null;
let rootListenerStartedAt = 0;
const knownRootFlatAlertIds = new Set();

const childAlertListeners = new Map();
const inflightAlerts = new Set();

function normalizeChildId(value) {
  return value?.toString().trim() || "";
}

function normalizeAlertId(value) {
  return value?.toString().trim() || "";
}

function parseTimestamp(value) {
  if (typeof value === "number" && Number.isFinite(value)) {
    return Math.round(value);
  }

  if (typeof value === "string") {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? Math.round(parsed) : 0;
  }

  return 0;
}

function isRecentEnough(timestamp, startedAt, windowMs = 5000) {
  return timestamp > 0 && timestamp >= startedAt - windowMs;
}

function extractMessage(payload = {}) {
  return payload.message?.toString().trim() || "";
}

function isPlainObject(value) {
  return value && typeof value === "object" && !Array.isArray(value);
}

function looksLikeSingleAlertPayload(value) {
  if (!isPlainObject(value)) {
    return false;
  }

  return (
    Object.prototype.hasOwnProperty.call(value, "message") ||
    Object.prototype.hasOwnProperty.call(value, "timestamp") ||
    Object.prototype.hasOwnProperty.call(value, "created_at") ||
    Object.prototype.hasOwnProperty.call(value, "isRead") ||
    Object.prototype.hasOwnProperty.call(value, "is_read")
  );
}

function normalizeAlertType(payload = {}, message = "") {
  const rawType =
    payload.type ||
    payload.alert_type ||
    payload.alertType ||
    payload.event_type ||
    payload.eventType ||
    payload.event_key ||
    payload.eventKey ||
    "";
  const normalized = rawType.toString().trim().toUpperCase();

  switch (normalized) {
    case "SOS":
    case "SOS_ALERT":
    case "EMERGENCY":
      return "SOS";
    case "OUT_ZONE":
    case "SAFE_ZONE_EXIT":
    case "ZONE_EXIT":
    case "SAFE_ZONE_BREACH":
    case "GEOFENCE_EXIT":
      return "OUT_ZONE";
    case "IN_ZONE":
    case "SAFE_ZONE_ENTER":
    case "ZONE_ENTER":
    case "SAFE_ZONE_RETURN":
    case "GEOFENCE_ENTER":
      return "IN_ZONE";
    default:
      break;
  }

  const normalizedMessage = message.toLowerCase();
  if (
    normalizedMessage.includes("returned") ||
    normalizedMessage.includes("entered") ||
    normalizedMessage.includes("inside") ||
    normalizedMessage.includes("within") ||
    normalizedMessage.includes("back in safe zone")
  ) {
    return "IN_ZONE";
  }
  if (
    normalizedMessage.includes("safe zone") ||
    normalizedMessage.includes("geofence") ||
    normalizedMessage.includes("breach") ||
    normalizedMessage.includes("left")
  ) {
    return "OUT_ZONE";
  }

  return "SOS";
}

function alertTitle(type) {
  switch (type) {
    case "OUT_ZONE":
      return "Safe Zone Alert";
    case "IN_ZONE":
      return "Safe Zone Return";
    case "SOS":
    default:
      return "SOS Alert";
  }
}

async function logFlatRootAlert(snapshot) {
  const alertId = normalizeAlertId(snapshot.key);
  const payload = snapshot.val();
  if (!alertId || !looksLikeSingleAlertPayload(payload)) {
    return;
  }

  const data = isPlainObject(payload) ? payload : {};
  const message = extractMessage(data);
  const alertType = normalizeAlertType(data, message);
  const createdAt = parseTimestamp(data.timestamp || data.created_at) || Date.now();

  await safeWriteAuditLogWithId(`alert_received_${alertId}_${createdAt}`, {
    eventType: "alert_received",
    entityType: "alert",
    entityId: alertId,
    userId: data.user_id || data.parent_user_id || "",
    childId: data.child_id || "",
    alertId,
    title: `${alertType} alert received`,
    description: message || alertTitle(alertType),
    performedBy: createSystemActor("Alert System"),
    target: {
      id: alertId,
      type: "alerts_live",
    },
    status: "success",
    source: "alerts_live",
    metadata: {
      alertId,
      alertType,
      message,
      timestamp: createdAt,
      rtdbPath: `alerts_live/${alertId}`,
      raw: data,
    },
  });
}

function normalizeInitialStatus(payload = {}) {
  return payload.isRead === true ? "read" : "unread";
}

function normalizeTrackingIdentifier(value) {
  return value?.toString().trim() || "";
}

async function resolveChildIdForFlatIngress(payload = {}, fallbackIdentifier = "") {
  const explicitChildId = normalizeChildId(payload.child_id || payload.childId);
  if (explicitChildId) {
    return explicitChildId;
  }

  const trackingKey = normalizeTrackingIdentifier(
    payload.tracking_key ||
      payload.trackingKey ||
      payload.imei ||
      payload.device_id ||
      payload.deviceId ||
      fallbackIdentifier
  );

  if (!trackingKey) {
    return "";
  }

  const registrySnapshot = await realtimeDB
    .ref(`device_registry_by_tracking_key/${trackingKey}`)
    .once("value");
  const registryData = registrySnapshot.val() || {};
  const registryChildId = normalizeChildId(registryData.child_id);
  if (registryChildId) {
    return registryChildId;
  }

  const deviceSnapshot = await realtimeDB
    .ref(`device_registry/${trackingKey}`)
    .once("value");
  const deviceData = deviceSnapshot.val() || {};
  return normalizeChildId(deviceData.child_id);
}

function isMirroredFlatAlertPayload(payload = {}, alertId = "") {
  return (
    normalizeAlertId(payload.alert_id) === normalizeAlertId(alertId) &&
    Boolean(normalizeChildId(payload.child_id || payload.childId)) &&
    Boolean(payload.user_id || payload.parent_user_id) &&
    Boolean(payload.status || payload.isRead === true || payload.is_read === true)
  );
}

async function updateIngressStatus(snapshot, fields = {}) {
  const updates = {
    updated_at: Date.now(),
    ...fields,
  };
  await snapshot.ref.update(updates);
}

async function lookupParentNotificationTokens(userId) {
  const normalizedUserId = userId?.toString().trim() || "";
  if (!normalizedUserId) {
    return [];
  }

  const userDoc = await firestore.collection("users").doc(normalizedUserId).get();
  if (!userDoc.exists) {
    return [];
  }

  const userData = userDoc.data() || {};
  const candidate =
    userData.fcm_tokens ||
    userData.fcmTokens ||
    userData.notification_tokens ||
    userData.notificationTokens ||
    [];

  if (Array.isArray(candidate)) {
    return candidate
      .map((value) => value?.toString().trim() || "")
      .filter(Boolean);
  }

  if (typeof candidate === "string" && candidate.trim().length > 0) {
    return [candidate.trim()];
  }

  return [];
}

async function sendOptionalAlertPush({ userId, childId, childName, type, message }) {
  const tokens = await lookupParentNotificationTokens(userId);
  if (tokens.length === 0) {
    return;
  }

  try {
    const multicastMessage = {
      tokens,
      notification: {
        title: alertTitle(type),
        body: message,
      },
      data: {
        type: type || "SOS",
        childId: childId || "",
        childName: childName || "",
      },
      android: {
        priority: "high",
      },
      apns: {
        payload: {
          aps: {
            sound: "default",
          },
        },
      },
    };

    const response = await admin.messaging().sendEachForMulticast(
      multicastMessage
    );

    console.info("[sos-alert-live-listener.fcm]", {
      userId,
      childId,
      type,
      tokenCount: tokens.length,
      successCount: response.successCount,
      failureCount: response.failureCount,
    });
  } catch (error) {
    console.error("[sos-alert-live-listener.fcm] failed", {
      userId,
      childId,
      reason: error.message,
    });
  }
}

async function processSosIngressAlert(childId, snapshot) {
  const normalizedChildId = normalizeChildId(childId);
  const alertId = normalizeAlertId(snapshot.key);
  if (!normalizedChildId || !alertId) {
    return;
  }

  const inflightKey = `${normalizedChildId}:${alertId}`;
  if (inflightAlerts.has(inflightKey)) {
    return;
  }

  inflightAlerts.add(inflightKey);

  try {
    const snapshotValue = snapshot.val();
    const payload =
      snapshotValue && typeof snapshotValue === "object" ? snapshotValue : {};

    if (
      payload.processed_at ||
      payload.rejected_at ||
      payload.source_live_ingress === true ||
      payload.ingress_alert_id ||
      payload.server_status === "processed" ||
      payload.server_status === "rejected"
    ) {
      return;
    }

    const message = extractMessage(payload);
    if (!message) {
      await updateIngressStatus(snapshot, {
        rejected_at: Date.now(),
        server_status: "rejected",
        server_error: "SOS message is required",
      });
      return;
    }

    const alertType = normalizeAlertType(payload, message);
    const latitude = payload.latitude ?? payload.lat ?? null;
    const longitude = payload.longitude ?? payload.lng ?? payload.lon ?? null;
    const locationText = buildLocationText({
      locationText: payload.location_text || payload.location || payload.address,
      area: payload.area,
      address: payload.address,
      latitude,
      longitude,
    });
    const zoneName =
      payload.zone_name?.toString().trim() ||
      payload.safe_zone?.toString().trim() ||
      payload.safeZone?.toString().trim() ||
      null;

    if (
      payload.child_id != null &&
      normalizeChildId(payload.child_id) != normalizedChildId
    ) {
      await updateIngressStatus(snapshot, {
        rejected_at: Date.now(),
        server_status: "rejected",
        server_error: "child_id does not match ingress path",
      });
      return;
    }

    const { childDoc } = await getChildOrThrow(normalizedChildId);
    const childData = childDoc.data() || {};
    const createdAt = parseTimestamp(payload.timestamp || payload.created_at) || Date.now();

    const createdAlert = await createAlertRecord({
      childId: normalizedChildId,
      type: alertType,
      message,
      zoneName,
      locationText,
      latitude,
      longitude,
      alertId,
      createdAt,
      initialStatus: normalizeInitialStatus(payload),
      extraFields: {
        source_live_ingress: true,
        ingress_alert_id: alertId,
        event_key:
          payload.event_key?.toString().trim() ||
          payload.eventKey?.toString().trim() ||
          "",
        tracking_key:
          payload.trackingKey?.toString().trim() ||
          payload.tracking_key?.toString().trim() ||
          "",
        device_timestamp: createdAt,
      },
    });

    await updateIngressStatus(snapshot, {
      processed_at: Date.now(),
      server_status: "processed",
      persisted_alert_id: createdAlert.alertId,
      child_id: normalizedChildId,
      type: alertType,
      created_at: createdAt,
      isRead: payload.isRead === true,
    });

    await sendOptionalAlertPush({
      userId: childData.user_id || "",
      childId: normalizedChildId,
      childName: childData.name || "",
      type: alertType,
      message,
    });

    console.info("[sos-alert-live-listener.processed]", {
      childId: normalizedChildId,
      alertId,
      type: alertType,
      persistedAlertId: createdAlert.alertId,
      duplicate: createdAlert.alreadyExists === true,
    });
  } catch (error) {
    console.error("[sos-alert-live-listener.process] failed", {
      childId: normalizedChildId,
      alertId,
      reason: error.message,
    });

    try {
      await updateIngressStatus(snapshot, {
        rejected_at: Date.now(),
        server_status: "rejected",
        server_error: error.message,
      });
    } catch (updateError) {
      console.error("[sos-alert-live-listener.process] reject-update failed", {
        childId: normalizedChildId,
        alertId,
        reason: updateError.message,
      });
    }
  } finally {
    inflightAlerts.delete(inflightKey);
  }
}

async function processFlatRootIngressAlert(snapshot, { isNewEvent = false } = {}) {
  const alertId = normalizeAlertId(snapshot.key);
  const payload = snapshot.val();
  if (!alertId || !looksLikeSingleAlertPayload(payload)) {
    return;
  }

  const data = isPlainObject(payload) ? payload : {};
  if (
    data.processed_at ||
    data.rejected_at ||
    data.server_status === "processed" ||
    data.server_status === "rejected" ||
    data.source_live_ingress === true ||
    data.ingress_alert_id ||
    isMirroredFlatAlertPayload(data, alertId)
  ) {
    return;
  }

  const createdAt = parseTimestamp(data.timestamp || data.created_at);
  if (!isRecentEnough(createdAt, rootListenerStartedAt)) {
    knownRootFlatAlertIds.add(alertId);
    console.info("[sos-alert-live-listener.flat] ignored stale flat alert", {
      alertId,
      path: `/alerts_live/${alertId}`,
      createdAt,
      rootListenerStartedAt,
    });
    return;
  }

  const resolvedChildId = await resolveChildIdForFlatIngress(data, alertId);
  if (!resolvedChildId) {
    console.info("[sos-alert-live-listener.flat] unresolved child", {
      alertId,
      path: `/alerts_live/${alertId}`,
      hasChildId: Boolean(normalizeChildId(data.child_id || data.childId)),
      hasTrackingKey: Boolean(
        normalizeTrackingIdentifier(
          data.tracking_key ||
            data.trackingKey ||
            data.imei ||
            data.device_id ||
            data.deviceId
        )
      ),
    });
    return;
  }

  await processSosIngressAlert(resolvedChildId, snapshot);
}

async function attachChildListener(childId) {
  const normalizedChildId = normalizeChildId(childId);
  if (!normalizedChildId || childAlertListeners.has(normalizedChildId)) {
    return;
  }

  const ref = realtimeDB.ref(`alerts_live/${normalizedChildId}`);
  const initialSnapshot = await ref.once("value");
  const knownIds = new Set();
  const initialData = initialSnapshot.val() || {};
  Object.entries(initialData).forEach(([alertId, payload]) => {
    if (looksLikeSingleAlertPayload(payload)) {
      knownIds.add(normalizeAlertId(alertId));
    }
  });
  const listenerStartedAt = Date.now();
  const handler = (snapshot) => {
    const alertId = normalizeAlertId(snapshot.key);
    if (knownIds.has(alertId)) {
      return;
    }

    const payload = snapshot.val();
    const createdAt = parseTimestamp(payload?.timestamp || payload?.created_at);
    if (!isRecentEnough(createdAt, listenerStartedAt)) {
      knownIds.add(alertId);
      console.info("[sos-alert-live-listener.child] ignored stale child alert", {
        childId: normalizedChildId,
        alertId,
        createdAt,
        listenerStartedAt,
      });
      return;
    }

    void processSosIngressAlert(normalizedChildId, snapshot);
  };

  ref.on("child_added", handler);
  childAlertListeners.set(normalizedChildId, {
    ref,
    handler,
    knownIds,
    listenerStartedAt,
  });

  console.info("[sos-alert-live-listener.attach]", {
    childId: normalizedChildId,
    path: `/alerts_live/${normalizedChildId}`,
    knownCount: knownIds.size,
  });
}

function detachChildListener(childId) {
  const normalizedChildId = normalizeChildId(childId);
  const entry = childAlertListeners.get(normalizedChildId);
  if (!entry) {
    return;
  }

  entry.ref.off("child_added", entry.handler);
  childAlertListeners.delete(normalizedChildId);
}

async function initSosAlertLiveListener() {
  if (isInitialized) {
    return;
  }

  isInitialized = true;
  const rootRef = realtimeDB.ref("alerts_live");
  const initialRootSnapshot = await rootRef.once("value");
  const initialRootData = initialRootSnapshot.val() || {};
  knownRootFlatAlertIds.clear();
  Object.entries(initialRootData).forEach(([alertId, payload]) => {
    if (looksLikeSingleAlertPayload(payload)) {
      knownRootFlatAlertIds.add(normalizeAlertId(alertId));
    }
  });
  rootListenerStartedAt = Date.now();

  rootChildAddedHandler = (snapshot) => {
    const alertId = normalizeAlertId(snapshot.key);
    if (knownRootFlatAlertIds.has(alertId)) {
      return;
    }
    void logFlatRootAlert(snapshot);
    void processFlatRootIngressAlert(snapshot, { isNewEvent: true });
    console.info("[sos-alert-live-listener] direct Flutter path only", {
      key: alertId,
      path: `/alerts_live/${snapshot.key}`,
      isFlatAlert: looksLikeSingleAlertPayload(snapshot.val()),
    });
  };

  rootChildChangedHandler = (snapshot) => {
    const alertId = normalizeAlertId(snapshot.key);
    void logFlatRootAlert(snapshot);
    void processFlatRootIngressAlert(snapshot, { isNewEvent: false });
    console.info("[sos-alert-live-listener] direct Flutter path changed", {
      key: alertId,
      path: `/alerts_live/${snapshot.key}`,
      isFlatAlert: looksLikeSingleAlertPayload(snapshot.val()),
    });
  };

  rootChildRemovedHandler = (snapshot) => {
    const childId = normalizeChildId(snapshot.key);
    if (!childId) {
      return;
    }
    detachChildListener(childId);
  };

  rootRef.on("child_added", rootChildAddedHandler);
  rootRef.on("child_changed", rootChildChangedHandler);
  rootRef.on("child_removed", rootChildRemovedHandler);

  console.info("[sos-alert-live-listener] initialized path=/alerts_live", {
    knownRootFlatAlerts: knownRootFlatAlertIds.size,
    rootListenerStartedAt,
  });
}

module.exports = {
  initSosAlertLiveListener,
};
