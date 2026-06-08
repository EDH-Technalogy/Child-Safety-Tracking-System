const { realtimeDB, firestore } = require("../firebase");
const { createHttpError, getChildOrThrow } = require("./child-access");
const { getTrackingContextForChild } = require("./live-tracking");
const { appendChildLog, normalizeLogType } = require("./child-logs");
const {
  createSystemActor,
  safeWriteAuditLogWithId,
} = require("./audit-log");
const { sendAlertPush } = require("./push-notification-service");

function isFiniteNumber(value) {
  return Number.isFinite(Number(value));
}

function formatCoordinates(latitude, longitude) {
  if (!isFiniteNumber(latitude) || !isFiniteNumber(longitude)) {
    return "an unknown location";
  }

  return `${Number(latitude).toFixed(5)}, ${Number(longitude).toFixed(5)}`;
}

function buildLocationText({
  locationText,
  area,
  address,
  latitude,
  longitude,
}) {
  const explicitText =
    locationText?.toString().trim() ||
    area?.toString().trim() ||
    address?.toString().trim();

  if (explicitText) {
    return explicitText;
  }

  return formatCoordinates(latitude, longitude);
}

function formatAlertTimestamp(timestamp = Date.now()) {
  const date = new Date(timestamp);
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  const hours = String(date.getHours()).padStart(2, "0");
  const minutes = String(date.getMinutes()).padStart(2, "0");
  const seconds = String(date.getSeconds()).padStart(2, "0");
  return `${year}-${month}-${day} ${hours}:${minutes}:${seconds}`;
}

function buildAlertMessage({
  type,
  locationText,
  zoneName,
  batteryLevel,
  customMessage,
}) {
  const normalizedType = type?.toString().trim().toUpperCase();
  const safeLocationText = locationText || "an unknown location";
  const timestampText = formatAlertTimestamp();

  if (customMessage?.toString().trim()) {
    return customMessage.toString().trim();
  }

  switch (normalizedType) {
    case "SOS":
      return `Emergency Alert: SOS button triggered from child device. Current location: ${safeLocationText}.`;
    case "OUT_ZONE":
    case "SAFE_ZONE_EXIT":
    case "ZONE_EXIT":
      return `Child out of Safe Zone at ${timestampText}. Current location: ${safeLocationText}.`;
    case "IN_ZONE":
    case "SAFE_ZONE_ENTER":
    case "ZONE_ENTER":
      return `Your child returned to the safe zone at ${timestampText}. Current location: ${safeLocationText}.`;
    case "LOW_BATTERY":
      return `Low battery alert! Battery level: ${batteryLevel ?? "Unknown"}%`;
    case "DEVICE_OFF":
      return "Device has been turned off!";
    case "DEVICE_ONLINE":
      return "Device is now online!";
    case "DEVICE_DISCONNECTED":
      return "Device disconnected automatically after no recent updates.";
    case "DEVICE_RECONNECTED":
      return "Device reconnected automatically.";
    default:
      return `${normalizedType || "ALERT"} event detected near ${safeLocationText}.`;
  }
}

async function createAlertRecord({
  childId,
  type,
  message,
  zoneName = null,
  locationText = null,
  latitude = null,
  longitude = null,
  batteryLevel = null,
  alertId = null,
  createdAt = null,
  initialStatus = "unread",
  extraFields = {},
  writeChildLog = true,
}) {
  const normalizedType = type?.toString().trim().toUpperCase();
  if (!childId || !normalizedType) {
    throw createHttpError(400, "childId and type are required");
  }

  const { childDoc } = await getChildOrThrow(childId);
  const childData = childDoc.data() || {};
  const time = Number.isFinite(Number(createdAt))
    ? Number(createdAt)
    : Date.now();
  const normalizedStatus =
    initialStatus?.toString().trim().toLowerCase() === "read"
      ? "read"
      : "unread";
  const dedupeState = await resolveRecentAlertDuplicate({
    childId,
    type: normalizedType,
    zoneName,
    message,
    extraFields,
    createdAt: time,
  });
  if (dedupeState.shouldReuse) {
    return {
      alertId: dedupeState.alertId,
      time: dedupeState.createdAt,
      alertData: dedupeState.alertData,
      childData,
      alreadyExists: true,
    };
  }

  const alertPayload = {
    child_id: childId,
    user_id: childData.user_id || "",
    child_name: childData.name || "",
    type: normalizedType,
    message,
    location_text: locationText,
    zone_name: zoneName,
    latitude: isFiniteNumber(latitude) ? Number(latitude) : null,
    longitude: isFiniteNumber(longitude) ? Number(longitude) : null,
    battery_level: batteryLevel,
    created_at: time,
    timestamp: time,
    status: normalizedStatus,
    is_read: normalizedStatus === "read",
    isRead: normalizedStatus === "read",
    ...extraFields,
  };

  const alertDoc = alertId
    ? firestore.collection("alerts").doc(alertId)
    : firestore.collection("alerts").doc();
  const resolvedAlertId = alertDoc.id;
  const existingAlertDoc = await alertDoc.get();
  const alreadyExists = existingAlertDoc.exists;

  const livePayload = {
    alert_id: resolvedAlertId,
    child_id: childId,
    user_id: childData.user_id || "",
    child_name: childData.name || "",
    type: normalizedType,
    message,
    location_text: locationText,
    zone_name: zoneName,
    latitude: alertPayload.latitude,
    longitude: alertPayload.longitude,
    battery_level: batteryLevel,
    created_at: time,
    timestamp: time,
    status: normalizedStatus,
    is_read: normalizedStatus === "read",
    isRead: normalizedStatus === "read",
    ...extraFields,
  };
  const adminLivePayload = {
    ...livePayload,
    parent_user_id: childData.user_id || "",
  };
  const realtimeUpdates = {
    [`alerts_by_child/${childId}/${resolvedAlertId}`]: livePayload,
    [`alerts_live/${childId}/${resolvedAlertId}`]: livePayload,
    [`admin_alerts/${resolvedAlertId}`]: adminLivePayload,
  };

  if (childData.user_id?.toString().trim()) {
    realtimeUpdates[`alerts/${childData.user_id}/${resolvedAlertId}`] =
      livePayload;
  }

  if (!alreadyExists) {
    await alertDoc.set(alertPayload);
  }
  await realtimeDB.ref().update(realtimeUpdates);
  await persistAlertDedupeState({
    childId,
    type: normalizedType,
    zoneName,
    message,
    extraFields,
    alertId: resolvedAlertId,
    createdAt: time,
  });

  if (!alreadyExists) {
    const trackingContext = await getTrackingContextForChild(childId);
    const resolvedTrackingKey =
      extraFields.tracking_key?.toString().trim() ||
      trackingContext?.trackingKey ||
      "";

    if (writeChildLog) {
      const normalizedLogType = normalizeLogType(normalizedType);
      await appendChildLog({
        childId,
        trackingKey: resolvedTrackingKey,
        parentUserId: childData.user_id || "",
        type: normalizedLogType,
        message,
        timestamp: time,
        metadata: {
          source: "alert_service",
          alertId: resolvedAlertId,
          zoneName,
          locationText,
          latitude: alertPayload.latitude,
          longitude: alertPayload.longitude,
          batteryLevel,
          originalType: normalizedType,
        },
      });
    }

    await safeWriteAuditLogWithId(`alert_received_${resolvedAlertId}`, {
      eventType: "alert_received",
      entityType: "alert",
      entityId: resolvedAlertId,
      userId: childData.user_id || "",
      childId,
      alertId: resolvedAlertId,
      title: `${normalizedType} alert received`,
      description: message,
      performedBy: createSystemActor("Alert System"),
      target: {
        id: childId,
        child_id: childId,
        name: childData.name || "",
        type: "child",
      },
      status: "success",
      source: "alert_service",
      metadata: {
        alertId: resolvedAlertId,
        childId,
        parentUserId: childData.user_id || "",
        alertType: normalizedType,
        zoneName,
        locationText,
        latitude: alertPayload.latitude,
        longitude: alertPayload.longitude,
        batteryLevel,
        trackingKey: resolvedTrackingKey,
        realtimePath: `admin_alerts/${resolvedAlertId}`,
      },
    });

    await sendAlertPush({
      userId: childData.user_id || "",
      childId,
      childName: childData.name || "",
      alertId: resolvedAlertId,
      type: normalizedType,
      message,
    });
  }

  console.info("[alerts.createAlertRecord]", {
    childId,
    userId: childData.user_id || "",
    type: normalizedType,
    alertId: resolvedAlertId,
    duplicate: alreadyExists,
    livePath: childData.user_id
      ? `/alerts/${childData.user_id}/${resolvedAlertId}`
      : `/alerts_by_child/${childId}/${resolvedAlertId}`,
    adminLivePath: `/admin_alerts/${resolvedAlertId}`,
    zoneName,
    locationText,
  });

  return {
    alertId: resolvedAlertId,
    time,
    alertData: alreadyExists ? existingAlertDoc.data() || alertPayload : alertPayload,
    childData,
    alreadyExists,
  };
}

function normalizeDedupeValue(value) {
  return value?.toString().trim().toLowerCase() || "";
}

function buildAlertDedupeKey({ type, zoneName, extraFields = {} }) {
  const normalizedType = normalizeDedupeValue(type).toUpperCase();
  const eventKey = normalizeDedupeValue(
    extraFields.event_key || extraFields.eventKey
  );
  const deviceTimestamp = normalizeDedupeValue(
    extraFields.device_timestamp || extraFields.deviceTimestamp
  );
  const trackingKey = normalizeDedupeValue(
    extraFields.tracking_key || extraFields.trackingKey
  );
  const safeZoneId = normalizeDedupeValue(
    extraFields.safe_zone_id || extraFields.safeZoneId
  );
  const normalizedZoneName = normalizeDedupeValue(zoneName);

  if (normalizedType === "SOS") {
    if (eventKey) {
      return `sos|${eventKey}`;
    }

    if (deviceTimestamp) {
      return `sos|${deviceTimestamp}`;
    }

    if (trackingKey) {
      return `sos|${trackingKey}`;
    }

    return "sos";
  }

  if (
    normalizedType === "IN_ZONE" ||
    normalizedType === "OUT_ZONE" ||
    normalizedType === "ZONE_ENTER" ||
    normalizedType === "ZONE_EXIT" ||
    normalizedType === "SAFE_ZONE_ENTER" ||
    normalizedType === "SAFE_ZONE_EXIT"
  ) {
    return [
      eventKey || normalizedType,
      safeZoneId || normalizedZoneName || "unknown_zone",
    ].join("|");
  }

  return "";
}

async function resolveRecentAlertDuplicate({
  childId,
  type,
  zoneName,
  message,
  extraFields = {},
  createdAt,
}) {
  const dedupeKey = buildAlertDedupeKey({ type, zoneName, extraFields });
  if (!dedupeKey) {
    return { shouldReuse: false };
  }

  const dedupeWindowMs = type === "SOS" ? 60000 : 90000;
  const ref = realtimeDB.ref(`alert_dedupe/${childId}/${dedupeKey}`);
  const snapshot = await ref.once("value");
  const state = snapshot.val() || {};
  const lastCreatedAt = Number(state.created_at || 0);
  const sameMessage =
    normalizeDedupeValue(state.message) === normalizeDedupeValue(message);
  const shouldRequireSameMessage = type === "SOS";

  if (
    state.alert_id &&
    lastCreatedAt > 0 &&
    createdAt - lastCreatedAt < dedupeWindowMs &&
    (!shouldRequireSameMessage || sameMessage)
  ) {
    return {
      shouldReuse: true,
      alertId: state.alert_id.toString(),
      createdAt: lastCreatedAt,
      alertData: {
        child_id: childId,
        type,
        zone_name: zoneName,
        message,
        created_at: lastCreatedAt,
      },
    };
  }

  return { shouldReuse: false };
}

async function persistAlertDedupeState({
  childId,
  type,
  zoneName,
  message,
  extraFields = {},
  alertId,
  createdAt,
}) {
  const dedupeKey = buildAlertDedupeKey({ type, zoneName, extraFields });
  if (!dedupeKey) {
    return;
  }

  await realtimeDB.ref(`alert_dedupe/${childId}/${dedupeKey}`).set({
    alert_id: alertId,
    type,
    zone_name: zoneName || null,
    message,
    created_at: createdAt,
    updated_at: Date.now(),
  });
}

module.exports = {
  buildLocationText,
  buildAlertMessage,
  createAlertRecord,
  formatCoordinates,
};
