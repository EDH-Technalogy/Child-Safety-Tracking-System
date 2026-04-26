const { realtimeDB, firestore } = require("../firebase");
const { createHttpError, getChildOrThrow } = require("./child-access");
const { getTrackingContextForChild } = require("./live-tracking");
const { appendChildLog, normalizeLogType } = require("./child-logs");

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
  extraFields = {},
}) {
  const normalizedType = type?.toString().trim().toUpperCase();
  if (!childId || !normalizedType) {
    throw createHttpError(400, "childId and type are required");
  }

  const { childDoc } = await getChildOrThrow(childId);
  const childData = childDoc.data() || {};
  const time = Date.now();

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
    status: "unread",
    ...extraFields,
  };

  const alertDoc = firestore.collection("alerts").doc();
  const alertId = alertDoc.id;
  const livePayload = {
    alert_id: alertId,
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
    status: "unread",
    ...extraFields,
  };
  const adminLivePayload = {
    ...livePayload,
    parent_user_id: childData.user_id || "",
  };
  const realtimeUpdates = {
    [`alerts_by_child/${childId}/${alertId}`]: livePayload,
    [`admin_alerts/${alertId}`]: adminLivePayload,
    [`alerts_live/${childId}`]: livePayload,
  };

  if (childData.user_id?.toString().trim()) {
    realtimeUpdates[`alerts/${childData.user_id}/${alertId}`] = livePayload;
  }

  await alertDoc.set(alertPayload);
  await realtimeDB.ref().update(realtimeUpdates);

  const trackingContext = await getTrackingContextForChild(childId);
  const resolvedTrackingKey =
    extraFields.tracking_key?.toString().trim() ||
    trackingContext?.trackingKey ||
    "";
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
      alertId,
      zoneName,
      locationText,
      latitude: alertPayload.latitude,
      longitude: alertPayload.longitude,
      batteryLevel,
      originalType: normalizedType,
    },
  });

  console.info("[alerts.createAlertRecord]", {
    childId,
    userId: childData.user_id || "",
    type: normalizedType,
    alertId,
    livePath: childData.user_id
      ? `/alerts/${childData.user_id}/${alertId}`
      : `/alerts_by_child/${childId}/${alertId}`,
    adminLivePath: `/admin_alerts/${alertId}`,
    zoneName,
    locationText,
  });

  return {
    alertId,
    time,
    alertData: alertPayload,
    childData,
  };
}

module.exports = {
  buildLocationText,
  buildAlertMessage,
  createAlertRecord,
  formatCoordinates,
};
