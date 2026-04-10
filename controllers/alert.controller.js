const { firestore } = require("../firebase");
const {
  safeWriteAuditLog,
  buildPerformedByFromRequest,
  inferSource,
  createSystemActor,
} = require("../utils/audit-log");
const {
  createHttpError,
  getChildWithAccessOrThrow,
} = require("../utils/child-access");
const {
  buildAlertMessage,
  buildLocationText,
  createAlertRecord,
} = require("../utils/alert-service");

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

  if (type === "OUT_ZONE") {
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

exports.sendAlert = async (req, res) => {
  const childId = req.body.child_id?.toString().trim();
  const type = req.body.type?.toString().trim().toUpperCase();

  try {
    if (!childId || !type) {
      throw createHttpError(400, "child_id and type are required");
    }

    const locationText = buildLocationText({
      locationText: req.body.location_text,
      area: req.body.area,
      address: req.body.address,
      latitude: req.body.latitude,
      longitude: req.body.longitude,
    });

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

    const locationText = buildLocationText({
      locationText: req.body.location_text,
      area: req.body.area,
      address: req.body.address,
      latitude: req.body.latitude,
      longitude: req.body.longitude,
    });

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

    const snap = await firestore
      .collection("alerts")
      .where("child_id", "==", childId)
      .get();

    const alerts = [];
    snap.forEach((doc) => alerts.push({ id: doc.id, ...doc.data() }));
    alerts.sort((a, b) => (b.created_at || 0) - (a.created_at || 0));
    res.json(alerts);
  } catch (error) {
    next(error);
  }
};

exports.markAsRead = async (req, res, next) => {
  try {
    const { alertRef, alertDoc } = await getAlertOrThrow(req.params.alert_id);
    const alertData = alertDoc.data() || {};

    await getChildWithAccessOrThrow(req, alertData.child_id);

    await alertRef.update({
      status: "read",
      updated_at: Date.now(),
    });

    await logAlertEvent(req, {
      eventType: "alert_acknowledged",
      entityType: "alert",
      entityId: req.params.alert_id,
      title: "Alert acknowledged",
      description: `Alert ${alertData.type || req.params.alert_id} was marked as read.`,
      target: buildAlertTarget(req.params.alert_id, {
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

    const snap = await firestore
      .collection("alerts")
      .where("child_id", "==", childId)
      .get();

    const unreadCount = snap.docs.filter(
      (doc) => (doc.data().status || "unread") === "unread"
    ).length;

    res.json({ count: unreadCount });
  } catch (error) {
    next(error);
  }
};

exports.markAllAsRead = async (req, res, next) => {
  try {
    const childId = req.params.child_id?.toString().trim();
    await getChildWithAccessOrThrow(req, childId);

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
        updated_at: Date.now(),
      });
    });
    await batch.commit();

    await logAlertEvent(req, {
      eventType: "alert_acknowledged",
      entityType: "alert",
      entityId: null,
      title: "Alerts acknowledged",
      description: `${unreadDocs.length} alerts were marked as read for child ${childId}.`,
      target: buildAlertTarget(null, {
        child_id: childId,
        status: "read",
      }),
      status: "success",
      result: "success",
      metadata: {
        child_id: childId,
        affectedCount: unreadDocs.length,
        relatedIds: {
          alertIds: unreadDocs.map((doc) => doc.id),
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
