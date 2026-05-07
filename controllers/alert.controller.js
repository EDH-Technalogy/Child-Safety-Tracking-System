const { firestore, realtimeDB } = require("../firebase");
const {
  safeWriteAuditLog,
  buildPerformedByFromRequest,
  inferSource,
  createSystemActor,
} = require("../utils/audit-log");
const {
  createHttpError,
  ensureCanWriteChildEvent,
  getChildWithAccessOrThrow,
} = require("../utils/child-access");
const {
  buildAlertMessage,
  buildLocationText,
  createAlertRecord,
} = require("../utils/alert-service");
const {
  collectAlertsFromRealtimeValue,
  isSafeZoneAlert,
  isUnreadAlert,
  mergeNormalizedAlerts,
  normalizeAlert,
} = require("../utils/alert-normalizer");

const SOS_ALERT_COOLDOWN_MS = 60000;

function buildAlertTarget(alertId, alertData = {}) {
  return {
    id: alertId || null,
    child_id: alertData.child_id || null,
    type: alertData.type || null,
    status: alertData.status || null,
  };
}

async function logAlertEvent(req, entry, fallbackActor = null) {
  return safeWriteAuditLog({
    source: inferSource(req, "backend"),
    performedBy: buildPerformedByFromRequest(req, fallbackActor),
    ...entry,
  });
}

async function getAlertOrThrow(alertId) {
  const alertRef = firestore.collection("alerts").doc(alertId);
  const alertDoc = await alertRef.get();

  if (!alertDoc.exists) {
    throw createHttpError(404, "Alert not found");
  }

  return { alertRef, alertDoc };
}

function normalizeId(value) {
  return value?.toString().trim() || "";
}

function parseAlertTimestamp(value) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? Math.round(parsed) : 0;
}

function requestChildId(req) {
  return normalizeId(req.query?.child_id || req.body?.child_id);
}

async function skipDuplicateSosIfRecent({
  childId,
  locationText = "",
  latitude = null,
  longitude = null,
}) {
  const sosStateRef = realtimeDB.ref(`live_tracking/${childId}/sos_state`);
  const sosStateSnapshot = await sosStateRef.once("value");
  const sosState = sosStateSnapshot.val() || {};
  const now = Date.now();
  const lastAlertAt = parseAlertTimestamp(sosState.last_alert_at);

  if (lastAlertAt > 0 && now - lastAlertAt < SOS_ALERT_COOLDOWN_MS) {
    await sosStateRef.update({
      updated_at: now,
      last_location_text: locationText,
      latitude,
      longitude,
    });

    return {
      skipped: true,
      lastAlertAt,
    };
  }

  await sosStateRef.set({
    last_alert_at: now,
    last_location_text: locationText,
    latitude,
    longitude,
    updated_at: now,
  });

  return {
    skipped: false,
    lastAlertAt: now,
  };
}

function realtimeAlertMirrorUpdates(alertId, alertData = {}, childData = {}, value) {
  const childId = normalizeId(alertData.child_id || childData.id);
  const userId = normalizeId(alertData.user_id || childData.user_id);
  const updates = {};

  if (userId) {
    updates[`alerts/${userId}/${alertId}`] = value;
  }
  if (childId) {
    updates[`alerts_by_child/${childId}/${alertId}`] = value;
    updates[`alerts_live/${childId}/${alertId}`] = value;
  }
  updates[`alerts_live/${alertId}`] = value;
  updates[`admin_alerts/${alertId}`] = value;

  return updates;
}

async function resolveAlertMutationContext(req, alertId, { allowMissing = false } = {}) {
  const normalizedAlertId = normalizeId(alertId);
  if (!normalizedAlertId) {
    throw createHttpError(400, "alert_id is required");
  }

  const alertRef = firestore.collection("alerts").doc(normalizedAlertId);
  const alertDoc = await alertRef.get();

  if (alertDoc.exists) {
    const alertData = alertDoc.data() || {};
    const { childDoc } = await getChildWithAccessOrThrow(req, alertData.child_id);
    return {
      alertId: normalizedAlertId,
      alertRef,
      alertDoc,
      alertData,
      childData: {
        id: childDoc.id,
        ...(childDoc.data() || {}),
      },
      existsInFirestore: true,
      existsInRealtime: true,
    };
  }

  let childId = requestChildId(req);
  let adminAlertSnapshot = null;
  let adminAlertData = null;
  if (!childId) {
    adminAlertSnapshot = await realtimeDB
      .ref(`admin_alerts/${normalizedAlertId}`)
      .once("value");
    adminAlertData = adminAlertSnapshot.val();
    childId = normalizeId(adminAlertData?.child_id || adminAlertData?.childId);
  }

  if (!childId) {
    if (allowMissing) {
      return {
        alertId: normalizedAlertId,
        alertRef,
        alertDoc: null,
        alertData: {},
        childData: {},
        existsInFirestore: false,
        existsInRealtime: false,
      };
    }
    throw createHttpError(404, "Alert not found");
  }

  const { childDoc } = await getChildWithAccessOrThrow(req, childId);

  // Try alerts_by_child first (backend-mirrored alerts)
  let liveSnapshot = await realtimeDB
    .ref(`alerts_by_child/${childId}/${normalizedAlertId}`)
    .once("value");
  let liveData = liveSnapshot.val();

  // Fallback: check alerts_live (device-pushed RTDB-only alerts)
  if (!liveSnapshot.exists()) {
    liveSnapshot = await realtimeDB
      .ref(`alerts_live/${childId}/${normalizedAlertId}`)
      .once("value");
    liveData = liveSnapshot.val();
  }
  let sourceFlatLive = false;
  if (!liveSnapshot.exists()) {
    liveSnapshot = await realtimeDB
      .ref(`alerts_live/${normalizedAlertId}`)
      .once("value");
    liveData = liveSnapshot.val();
    sourceFlatLive = liveSnapshot.exists();
  }
  let sourceAdminAlert = false;
  if (!liveSnapshot.exists()) {
    if (!adminAlertSnapshot) {
      adminAlertSnapshot = await realtimeDB
        .ref(`admin_alerts/${normalizedAlertId}`)
        .once("value");
      adminAlertData = adminAlertSnapshot.val();
    }
    liveSnapshot = adminAlertSnapshot;
    liveData = adminAlertData;
    sourceAdminAlert = liveSnapshot.exists();
  }

  if (!liveSnapshot.exists() && !allowMissing) {
    throw createHttpError(404, "Alert not found");
  }

  return {
    alertId: normalizedAlertId,
    alertRef,
    alertDoc: null,
    alertData: liveData && typeof liveData === "object"
      ? {
          ...liveData,
          child_id: liveData.child_id || childId,
          user_id: liveData.user_id || childDoc.data()?.user_id || "",
          source_flat_live: sourceFlatLive,
          source_admin_alert: sourceAdminAlert,
        }
      : {
          child_id: childId,
          user_id: childDoc.data()?.user_id || "",
          source_flat_live: sourceFlatLive,
          source_admin_alert: sourceAdminAlert,
        },
    childData: {
      id: childDoc.id,
      ...(childDoc.data() || {}),
    },
    existsInFirestore: false,
    existsInRealtime: liveSnapshot.exists(),
  };
}

async function syncRealtimeAlertStatus(alertId, alertData = {}, status = "read") {
  const childId = alertData.child_id?.toString().trim() || "";
  const userId = alertData.user_id?.toString().trim() || "";
  const updates = {};
  const isRead = status === "read";
  const shouldUpdateChildMirrors = alertData.source_admin_alert !== true;

  if (userId && shouldUpdateChildMirrors) {
    updates[`alerts/${userId}/${alertId}/status`] = status;
    updates[`alerts/${userId}/${alertId}/is_read`] = isRead;
    updates[`alerts/${userId}/${alertId}/isRead`] = isRead;
  }
  if (childId && shouldUpdateChildMirrors) {
    updates[`alerts_by_child/${childId}/${alertId}/status`] = status;
    updates[`alerts_by_child/${childId}/${alertId}/is_read`] = isRead;
    updates[`alerts_by_child/${childId}/${alertId}/isRead`] = isRead;
    updates[`alerts_live/${childId}/${alertId}/status`] = status;
    updates[`alerts_live/${childId}/${alertId}/is_read`] = isRead;
    updates[`alerts_live/${childId}/${alertId}/isRead`] = isRead;
  }
  if (alertData.source_flat_live === true) {
    updates[`alerts_live/${alertId}/status`] = status;
    updates[`alerts_live/${alertId}/is_read`] = isRead;
    updates[`alerts_live/${alertId}/isRead`] = isRead;
  }
  updates[`admin_alerts/${alertId}/status`] = status;
  updates[`admin_alerts/${alertId}/is_read`] = isRead;
  updates[`admin_alerts/${alertId}/isRead`] = isRead;

  if (Object.keys(updates).length > 0) {
    await realtimeDB.ref().update(updates);
  }
}

function isAlertForChild(alert, childId) {
  return normalizeId(alert.child_id || alert.childId) === childId;
}

function isMirroredFlatRootAlert(alert = {}) {
  const alertId = normalizeId(alert.alert_id || alert.id);
  const childId = normalizeId(alert.child_id || alert.childId);
  const hasMirrorFields =
    normalizeId(alert.user_id || alert.parent_user_id) !== "" &&
    (normalizeId(alert.status) !== "" ||
      alert.is_read === true ||
      alert.isRead === true);

  return alertId !== "" && childId !== "" && hasMirrorFields;
}

async function listFirestoreAlertsForChild(childId) {
  const snap = await firestore
    .collection("alerts")
    .where("child_id", "==", childId)
    .get();

  return snap.docs
    .map((doc) => normalizeAlert({ id: doc.id, ...doc.data() }, "firestore_alerts"))
    .filter(Boolean);
}

async function listRealtimeSosAlertsForChild(childId) {
  const [childLiveSnapshot, flatLiveSnapshot] = await Promise.all([
    realtimeDB.ref(`alerts_live/${childId}`).once("value"),
    realtimeDB
      .ref("alerts_live")
      .orderByChild("child_id")
      .equalTo(childId)
      .once("value"),
  ]);

  const childScopedAlerts = collectAlertsFromRealtimeValue(
    childLiveSnapshot.val(),
    "alerts_live",
    {
      childIdFallback: childId,
    }
  ).filter((alert) => isAlertForChild(alert, childId));

  const flatRootAlerts = collectAlertsFromRealtimeValue(
    flatLiveSnapshot.val(),
    "alerts_live"
  ).filter(
    (alert) =>
      isAlertForChild(alert, childId) &&
      !isMirroredFlatRootAlert(alert) &&
      isSosAlert(alert)
  );

  return [...childScopedAlerts, ...flatRootAlerts];
}

async function listRealtimeSafeZoneAlertsForChild(childId) {
  const adminAlertsSnapshot = await realtimeDB
    .ref("admin_alerts")
    .orderByChild("child_id")
    .equalTo(childId)
    .once("value");

  return collectAlertsFromRealtimeValue(
    adminAlertsSnapshot.val(),
    "admin_alerts"
  ).filter((alert) => isAlertForChild(alert, childId) && isSafeZoneAlert(alert));
}

async function listMergedAlertsForChild(childId) {
  const [firestoreAlerts, sosAlerts, safeZoneAlerts] = await Promise.all([
    listFirestoreAlertsForChild(childId),
    listRealtimeSosAlertsForChild(childId),
    listRealtimeSafeZoneAlertsForChild(childId),
  ]);

  const allAlerts = [
    ...sosAlerts,
    ...safeZoneAlerts,
    ...firestoreAlerts,
  ];

  return mergeNormalizedAlerts(allAlerts);
}

async function createAndLogAlert(
  req,
  {
    childId,
    type,
    zoneName = null,
    locationText = null,
    latitude = null,
    longitude = null,
    batteryLevel = null,
    customMessage = null,
    extraFields = {},
  }
) {
  const message = buildAlertMessage({
    type,
    zoneName,
    locationText,
    batteryLevel,
    customMessage,
  });

  const createdAlert = await createAlertRecord({
    childId,
    type,
    message,
    zoneName,
    locationText,
    latitude,
    longitude,
    batteryLevel,
    extraFields,
  });

  await logAlertEvent(
    req,
    {
      eventType: "alert_received",
      entityType: "alert",
      entityId: createdAlert.alertId,
      userId: createdAlert.childData?.user_id || "",
      childId,
      alertId: createdAlert.alertId,
      title: `Alert received: ${type}`,
      description: message,
      target: buildAlertTarget(createdAlert.alertId, {
        child_id: childId,
        type,
        status: "unread",
      }),
      status: "success",
      result: "success",
      metadata: {
        newValues: createdAlert.alertData,
      },
    },
    createSystemActor("Alert Service")
  );

  if (["OUT_ZONE", "SAFE_ZONE_EXIT", "ZONE_EXIT"].includes(type)) {
    await updateDailySummaryCounter(childId, "zone_exit_count");
  }

  if (type === "SOS") {
    await updateDailySummaryCounter(childId, "sos_count");
  }

  return {
    alertId: createdAlert.alertId,
    message,
  };
}

async function updateDailySummaryCounter(childId, fieldName) {
  try {
    const today = new Date().toISOString().slice(0, 10);
    const snap = await firestore
      .collection("daily_summary")
      .where("child_id", "==", childId)
      .where("date", "==", today)
      .limit(1)
      .get();

    if (snap.empty) {
      return;
    }

    const doc = snap.docs[0];
    const currentValue = Number(doc.data()?.[fieldName] || 0);
    await doc.ref.update({ [fieldName]: currentValue + 1 });
  } catch (error) {
    console.error("[alerts.updateDailySummaryCounter] failed", {
      childId,
      fieldName,
      reason: error.message,
    });
  }
}

async function authorizeAlertWrite(req, childId) {
  const accessResult = await ensureCanWriteChildEvent(req, childId);
  console.info("[alerts.write-access]", {
    childId,
    type: req.body?.type || null,
    accessMode: accessResult.mode,
    deviceId: accessResult.deviceId || null,
    authId: req.auth?.id || null,
    role: req.auth?.role || null,
  });

  return accessResult;
}

exports.sendAlert = async (req, res) => {
  const childId = req.body.child_id?.toString().trim();
  const type = req.body.type?.toString().trim().toUpperCase();

  try {
    if (!childId || !type) {
      throw createHttpError(400, "child_id and type are required");
    }

    await authorizeAlertWrite(req, childId);

    const locationText = buildLocationText({
      locationText: req.body.location_text,
      area: req.body.area,
      address: req.body.address,
      latitude: req.body.latitude,
      longitude: req.body.longitude,
    });

    if (type === "SOS") {
      const sosCheck = await skipDuplicateSosIfRecent({
        childId,
        locationText,
        latitude: req.body.latitude,
        longitude: req.body.longitude,
      });
      if (sosCheck.skipped) {
        return res.json({
          alert_id: null,
          message: "Duplicate SOS ignored",
          skipped: true,
        });
      }
    }

    const result = await createAndLogAlert(req, {
      childId,
      type,
      zoneName: req.body.zone_name || null,
      locationText,
      latitude: req.body.latitude,
      longitude: req.body.longitude,
      batteryLevel: req.body.battery_level,
      customMessage: req.body.message,
    });

    res.json({ alert_id: result.alertId, message: "Alert Sent" });
  } catch (error) {
    await logAlertEvent(
      req,
      {
        eventType: "alert_received",
        entityType: "alert",
        entityId: null,
        title: "Alert receive failed",
        description: req.body?.message || "Failed to save alert.",
        target: buildAlertTarget(null, req.body || {}),
        status: "failed",
        result: "failed",
        metadata: {
          reason: error.message,
        },
      },
      createSystemActor("Alert Service")
    );
    res.status(error.status || 500).json({ error: error.message });
  }
};

exports.sosAlert = async (req, res) => {
  try {
    const childId = req.body.child_id?.toString().trim();
    if (!childId) {
      throw createHttpError(400, "child_id is required");
    }

    await authorizeAlertWrite(req, childId);

    const locationText = buildLocationText({
      locationText: req.body.location_text,
      area: req.body.area,
      address: req.body.address,
      latitude: req.body.latitude,
      longitude: req.body.longitude,
    });

    const sosCheck = await skipDuplicateSosIfRecent({
      childId,
      locationText,
      latitude: req.body.latitude,
      longitude: req.body.longitude,
    });
    if (sosCheck.skipped) {
      return res.json({
        alert_id: null,
        message: "Duplicate SOS ignored",
        skipped: true,
      });
    }

    const result = await createAndLogAlert(req, {
      childId,
      type: "SOS",
      locationText,
      latitude: req.body.latitude,
      longitude: req.body.longitude,
      customMessage: req.body.message,
    });

    res.json({ alert_id: result.alertId, message: "SOS alert sent" });
  } catch (error) {
    res.status(error.status || 500).json({ error: error.message });
  }
};

exports.getAlerts = async (req, res, next) => {
  try {
    const childId = req.params.child_id?.toString().trim();
    await getChildWithAccessOrThrow(req, childId);

    const alerts = await listMergedAlertsForChild(childId);
    res.json(alerts);
  } catch (error) {
    next(error);
  }
};

exports.markAsRead = async (req, res, next) => {
  try {
    const {
      alertId,
      alertRef,
      alertData,
      existsInFirestore,
    } = await resolveAlertMutationContext(req, req.params.alert_id);

    if (existsInFirestore) {
      await alertRef.update({
        status: "read",
        is_read: true,
        isRead: true,
        updated_at: Date.now(),
      });
    }
    await syncRealtimeAlertStatus(alertId, alertData, "read");

    await logAlertEvent(req, {
      eventType: "alert_acknowledged",
      entityType: "alert",
      entityId: alertId,
      userId: alertData.user_id || "",
      childId: alertData.child_id || "",
      alertId,
      title: "Alert acknowledged",
      description: `Alert ${alertData.type || alertId} was marked as read.`,
      target: buildAlertTarget(alertId, {
        ...alertData,
        status: "read",
      }),
      status: "success",
      result: "success",
      metadata: {
        oldValues: { status: alertData.status || "unread" },
        newValues: { status: "read" },
        changedFields: ["status"],
      },
    });

    res.json({ message: "Alert marked as read" });
  } catch (error) {
    await logAlertEvent(req, {
      eventType: "alert_acknowledged",
      entityType: "alert",
      entityId: req.params.alert_id || null,
      title: "Alert acknowledge failed",
      description: `Failed to mark alert ${req.params.alert_id} as read.`,
      target: { id: req.params.alert_id || null },
      status: "failed",
      result: "failed",
      metadata: {
        reason: error.message,
      },
    });
    next(error);
  }
};

exports.lowBatteryAlert = async (req, res) => {
  try {
    const childId = req.body.child_id?.toString().trim();
    if (!childId) {
      throw createHttpError(400, "child_id is required");
    }

    await authorizeAlertWrite(req, childId);

    const result = await createAndLogAlert(req, {
      childId,
      type: "LOW_BATTERY",
      batteryLevel: req.body.battery_level,
    });

    res.json({ alert_id: result.alertId, message: "Low battery alert sent" });
  } catch (error) {
    res.status(error.status || 500).json({ error: error.message });
  }
};

exports.deviceOffAlert = async (req, res) => {
  try {
    const childId = req.body.child_id?.toString().trim();
    if (!childId) {
      throw createHttpError(400, "child_id is required");
    }

    await authorizeAlertWrite(req, childId);

    const result = await createAndLogAlert(req, {
      childId,
      type: "DEVICE_OFF",
    });

    res.json({ alert_id: result.alertId, message: "Device off alert sent" });
  } catch (error) {
    res.status(error.status || 500).json({ error: error.message });
  }
};

exports.deviceOnlineAlert = async (req, res) => {
  try {
    const childId = req.body.child_id?.toString().trim();
    if (!childId) {
      throw createHttpError(400, "child_id is required");
    }

    await authorizeAlertWrite(req, childId);

    const result = await createAndLogAlert(req, {
      childId,
      type: "DEVICE_ONLINE",
    });

    res.json({ alert_id: result.alertId, message: "Device online alert sent" });
  } catch (error) {
    res.status(error.status || 500).json({ error: error.message });
  }
};

exports.safeZoneExitAlert = async (req, res) => {
  try {
    const childId = req.body.child_id?.toString().trim();
    if (!childId) {
      throw createHttpError(400, "child_id is required");
    }

    await authorizeAlertWrite(req, childId);

    const locationText = buildLocationText({
      locationText: req.body.location_text,
      area: req.body.area,
      address: req.body.address,
      latitude: req.body.latitude,
      longitude: req.body.longitude,
    });

    const result = await createAndLogAlert(req, {
      childId,
      type: "OUT_ZONE",
      zoneName: req.body.zone_name || null,
      locationText,
      latitude: req.body.latitude,
      longitude: req.body.longitude,
    });

    res.json({ alert_id: result.alertId, message: "Safe zone exit alert sent" });
  } catch (error) {
    res.status(error.status || 500).json({ error: error.message });
  }
};

exports.safeZoneEnterAlert = async (req, res) => {
  try {
    const childId = req.body.child_id?.toString().trim();
    if (!childId) {
      throw createHttpError(400, "child_id is required");
    }

    await authorizeAlertWrite(req, childId);

    const locationText = buildLocationText({
      locationText: req.body.location_text,
      area: req.body.area,
      address: req.body.address,
      latitude: req.body.latitude,
      longitude: req.body.longitude,
    });

    const result = await createAndLogAlert(req, {
      childId,
      type: "IN_ZONE",
      zoneName: req.body.zone_name || null,
      locationText,
      latitude: req.body.latitude,
      longitude: req.body.longitude,
    });

    res.json({ alert_id: result.alertId, message: "Safe zone enter alert sent" });
  } catch (error) {
    res.status(error.status || 500).json({ error: error.message });
  }
};

exports.getUnreadCount = async (req, res, next) => {
  try {
    const childId = req.params.child_id?.toString().trim();
    await getChildWithAccessOrThrow(req, childId);

    const alerts = await listMergedAlertsForChild(childId);
    const unreadCount = alerts.filter(isUnreadAlert).length;

    res.json({ count: unreadCount });
  } catch (error) {
    next(error);
  }
};

exports.markAllAsRead = async (req, res, next) => {
  try {
    const childId = req.params.child_id?.toString().trim();
    const { childDoc } = await getChildWithAccessOrThrow(req, childId);
    const childData = childDoc.data() || {};

    const snap = await firestore
      .collection("alerts")
      .where("child_id", "==", childId)
      .get();

    const batch = firestore.batch();
    const unreadDocs = snap.docs.filter(
      (doc) => (doc.data().status || "unread") === "unread"
    );
    unreadDocs.forEach((doc) => {
      batch.update(doc.ref, {
        status: "read",
        is_read: true,
        isRead: true,
        updated_at: Date.now(),
      });
    });
    if (unreadDocs.length > 0) {
      await batch.commit();
    }

    const realtimeUpdates = {};
    const affectedAlertIds = new Set(unreadDocs.map((doc) => doc.id));

    unreadDocs.forEach((doc) => {
      const alertData = doc.data() || {};
      const userId =
        alertData.user_id?.toString().trim() ||
        childData.user_id?.toString().trim() ||
        "";
      if (userId) {
        realtimeUpdates[`alerts/${userId}/${doc.id}/status`] = "read";
        realtimeUpdates[`alerts/${userId}/${doc.id}/is_read`] = true;
        realtimeUpdates[`alerts/${userId}/${doc.id}/isRead`] = true;
      }
      realtimeUpdates[`alerts_by_child/${childId}/${doc.id}/status`] = "read";
      realtimeUpdates[`alerts_by_child/${childId}/${doc.id}/is_read`] = true;
      realtimeUpdates[`alerts_by_child/${childId}/${doc.id}/isRead`] = true;
      realtimeUpdates[`alerts_live/${childId}/${doc.id}/status`] = "read";
      realtimeUpdates[`alerts_live/${childId}/${doc.id}/is_read`] = true;
      realtimeUpdates[`alerts_live/${childId}/${doc.id}/isRead`] = true;
      realtimeUpdates[`admin_alerts/${doc.id}/status`] = "read";
      realtimeUpdates[`admin_alerts/${doc.id}/is_read`] = true;
      realtimeUpdates[`admin_alerts/${doc.id}/isRead`] = true;
    });

    const liveSnapshot = await realtimeDB.ref(`alerts_live/${childId}`).once("value");
    const liveAlerts = liveSnapshot.val() || {};
    Object.entries(liveAlerts).forEach(([alertId, rawAlert]) => {
      const alertData = rawAlert && typeof rawAlert === "object" ? rawAlert : {};
      const isUnread =
        alertData.is_read !== true &&
        alertData.isRead !== true &&
        (alertData.status || "unread") !== "read";
      if (!isUnread) {
        return;
      }

      affectedAlertIds.add(alertId);
      const userId =
        alertData.user_id?.toString().trim() ||
        childData.user_id?.toString().trim() ||
        "";
      if (userId) {
        realtimeUpdates[`alerts/${userId}/${alertId}/status`] = "read";
        realtimeUpdates[`alerts/${userId}/${alertId}/is_read`] = true;
        realtimeUpdates[`alerts/${userId}/${alertId}/isRead`] = true;
      }
      realtimeUpdates[`alerts_by_child/${childId}/${alertId}/status`] = "read";
      realtimeUpdates[`alerts_by_child/${childId}/${alertId}/is_read`] = true;
      realtimeUpdates[`alerts_by_child/${childId}/${alertId}/isRead`] = true;
      realtimeUpdates[`alerts_live/${childId}/${alertId}/status`] = "read";
      realtimeUpdates[`alerts_live/${childId}/${alertId}/is_read`] = true;
      realtimeUpdates[`alerts_live/${childId}/${alertId}/isRead`] = true;
      realtimeUpdates[`admin_alerts/${alertId}/status`] = "read";
      realtimeUpdates[`admin_alerts/${alertId}/is_read`] = true;
      realtimeUpdates[`admin_alerts/${alertId}/isRead`] = true;
    });

    const adminAlertsSnapshot = await realtimeDB
      .ref("admin_alerts")
      .orderByChild("child_id")
      .equalTo(childId)
      .once("value");
    const adminAlerts = adminAlertsSnapshot.val() || {};
    Object.entries(adminAlerts).forEach(([alertId, rawAlert]) => {
      const alertData = rawAlert && typeof rawAlert === "object" ? rawAlert : {};
      const isUnread =
        alertData.is_read !== true &&
        alertData.isRead !== true &&
        (alertData.status || "unread") !== "read";
      if (!isUnread) {
        return;
      }

      affectedAlertIds.add(alertId);
      realtimeUpdates[`admin_alerts/${alertId}/status`] = "read";
      realtimeUpdates[`admin_alerts/${alertId}/is_read`] = true;
      realtimeUpdates[`admin_alerts/${alertId}/isRead`] = true;
    });

    if (Object.keys(realtimeUpdates).length > 0) {
      await realtimeDB.ref().update(realtimeUpdates);
    }

    await logAlertEvent(req, {
      eventType: "alert_acknowledged",
      entityType: "alert",
      entityId: null,
      userId: childData.user_id || "",
      childId,
      title: "Alerts acknowledged",
      description: `${affectedAlertIds.size} alerts were marked as read for child ${childId}.`,
      target: buildAlertTarget(null, {
        child_id: childId,
        status: "read",
      }),
      status: "success",
      result: "success",
      metadata: {
        child_id: childId,
        affectedCount: affectedAlertIds.size,
        relatedIds: {
          alertIds: Array.from(affectedAlertIds),
        },
      },
    });

    res.json({ message: "All alerts marked as read" });
  } catch (error) {
    await logAlertEvent(req, {
      eventType: "alert_acknowledged",
      entityType: "alert",
      entityId: null,
      title: "Alert acknowledge failed",
      description: `Failed to mark all alerts as read for child ${req.params.child_id}.`,
      target: { child_id: req.params.child_id || null },
      status: "failed",
      result: "failed",
      metadata: {
        reason: error.message,
      },
    });
    next(error);
  }
};

exports.deleteAlert = async (req, res, next) => {
  try {
    const {
      alertId,
      alertRef,
      alertData,
      childData,
      existsInFirestore,
      existsInRealtime,
    } = await resolveAlertMutationContext(req, req.params.alert_id, {
      allowMissing: true,
    });

    if (!existsInFirestore && !existsInRealtime && !alertData.child_id) {
      throw createHttpError(404, "Alert not found");
    }

    if (existsInFirestore) {
      await alertRef.delete();
    }

    const realtimeUpdates = realtimeAlertMirrorUpdates(
      alertId,
      alertData,
      childData,
      null
    );
    if (Object.keys(realtimeUpdates).length > 0) {
      await realtimeDB.ref().update(realtimeUpdates);
    }

    await logAlertEvent(req, {
      eventType: "alert_deleted",
      entityType: "alert",
      entityId: alertId,
      userId: alertData.user_id || childData.user_id || "",
      childId: alertData.child_id || childData.id || "",
      alertId,
      title: "Alert deleted",
      description: `Alert ${alertData.type || alertId} was deleted.`,
      target: buildAlertTarget(alertId, alertData),
      status: "success",
      result: "success",
      metadata: {
        oldValues: alertData,
      },
    });

    res.json({ message: "Alert deleted successfully" });
  } catch (error) {
    await logAlertEvent(req, {
      eventType: "alert_deleted",
      entityType: "alert",
      entityId: req.params.alert_id || null,
      title: "Alert delete failed",
      description: `Failed to delete alert ${req.params.alert_id}.`,
      target: { id: req.params.alert_id || null },
      status: "failed",
      result: "failed",
      metadata: {
        reason: error.message,
      },
    });
    next(error);
  }
};
