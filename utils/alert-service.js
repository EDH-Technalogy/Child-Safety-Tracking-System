const { realtimeDB, firestore } = require("../firebase");
const { createHttpError, getChildOrThrow } = require("./child-access");
const { getTrackingContextForChild } = require("./live-tracking");
const { appendChildLog, normalizeLogType } = require("./child-logs");
const {
  createSystemActor,
  safeWriteAuditLogWithId,
} = require("./audit-log");

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

function buildAlertMessage({
  type,
  locationText,
  zoneName,
  batteryLevel,
  customMessage,
}) {
  const normalizedType = type?.toString().trim().toUpperCase();
  const safeLocationText = locationText || "an unknown location";

  if (customMessage?.toString().trim()) {
    return customMessage.toString().trim();
  }

  switch (normalizedType) {
    case "SOS":
      return `Emergency Alert: SOS button triggered from child device. Current location: ${safeLocationText}.`;
    case "OUT_ZONE":
    case "SAFE_ZONE_EXIT":
    case "ZONE_EXIT":
      return `Child out of Safe Zone. Current location: ${safeLocationText}.`;
    case "IN_ZONE":
    case "SAFE_ZONE_ENTER":
    case "ZONE_ENTER":
      return `Your child has returned to the configured safe zone and is currently located in ${safeLocationText}.`;
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

module.exports = {
  buildLocationText,
  buildAlertMessage,
  createAlertRecord,
  formatCoordinates,
};
