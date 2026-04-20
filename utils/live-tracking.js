const { firestore, realtimeDB } = require("../firebase");

function parseNumber(value) {
  const numericValue = Number(value);
  return Number.isFinite(numericValue) ? numericValue : null;
}

function parseCoordinateValue(rawLocation, ...keys) {
  for (const key of keys) {
    const value = parseNumber(rawLocation[key]);
    if (value !== null) {
      return value;
    }
  }

  return null;
}

function parseBattery(value) {
  const numericValue = parseNumber(value);
  return numericValue === null ? null : Math.max(0, Math.round(numericValue));
}

function normalizeTimestamp(value) {
  const numericValue = parseNumber(value);
  if (numericValue === null || numericValue <= 0) {
    return null;
  }

  if (numericValue >= 1e12) {
    return Math.round(numericValue);
  }

  if (numericValue >= 1e9) {
    return Math.round(numericValue * 1000);
  }

  return null;
}

function isValidCoordinate(latitude, longitude) {
  return (
    latitude !== null &&
    longitude !== null &&
    latitude >= -90 &&
    latitude <= 90 &&
    longitude >= -180 &&
    longitude <= 180
  );
}

function asMap(value) {
  return value && typeof value === "object" ? value : {};
}

function normalizeTrackingKey(rawValue) {
  const originalValue = rawValue?.toString().trim() || "";
  if (!originalValue) {
    return "";
  }

  const decodedValue = originalValue.replace(/~2F/gi, "/");
  const liveTrackingMatch = decodedValue.match(/live_tracking\/([^/?#]+)/i);
  if (liveTrackingMatch?.[1]) {
    return liveTrackingMatch[1].trim();
  }

  return originalValue;
}

async function getTrackingContextForChild(childId) {
  const normalizedChildId = childId?.toString().trim() || "";
  if (!normalizedChildId) {
    return null;
  }

  const childDoc = await firestore.collection("children").doc(normalizedChildId).get();
  if (!childDoc.exists) {
    return null;
  }

  const deviceSnap = await firestore
    .collection("devices")
    .where("child_id", "==", normalizedChildId)
    .limit(1)
    .get();

  const deviceDoc = deviceSnap.docs[0] || null;
  const deviceData = deviceDoc?.data() || {};
  const trackingKey =
    normalizeTrackingKey(deviceData.imei) || normalizeTrackingKey(deviceDoc?.id) || "";

  return {
    childId: normalizedChildId,
    childData: childDoc.data() || {},
    deviceDoc,
    deviceData,
    trackingKey,
  };
}

function buildStatusMetadata({ trackingNode, childNode }) {
  const trackingNodeMap = asMap(trackingNode);
  const childNodeMap = asMap(childNode);

  const connection =
    asMap(trackingNodeMap.connection).status !== undefined
      ? asMap(trackingNodeMap.connection)
      : asMap(childNodeMap.connection);
  const deviceStatus =
    asMap(trackingNodeMap.device_status).status !== undefined
      ? asMap(trackingNodeMap.device_status)
      : asMap(childNodeMap.device_status);
  const childStatus = asMap(childNodeMap.child_status);

  const timestamps = [
    normalizeTimestamp(connection.updated_at),
    normalizeTimestamp(connection.time),
    normalizeTimestamp(deviceStatus.updated_at),
    normalizeTimestamp(childStatus.updated_at),
  ].filter((value) => value !== null);

  return {
    raw: {
      ...(Object.keys(childStatus).length > 0 ? { child_status: childStatus } : {}),
      ...(Object.keys(deviceStatus).length > 0 ? { device_status: deviceStatus } : {}),
      ...(Object.keys(connection).length > 0 ? { connection } : {}),
    },
    latestStatus:
      connection.status?.toString().trim() ||
      deviceStatus.status?.toString().trim() ||
      childStatus.status?.toString().trim() ||
      null,
    latestSignal:
      connection.reason?.toString().trim() ||
      deviceStatus.reason?.toString().trim() ||
      null,
    latestTimestamp: timestamps.length > 0 ? Math.max(...timestamps) : null,
  };
}

async function getResolvedLiveTrackingSnapshot(childId) {
  const trackingContext = await getTrackingContextForChild(childId);
  if (!trackingContext || !trackingContext.trackingKey) {
    return null;
  }

  const { trackingKey, childId: normalizedChildId } = trackingContext;
  const rtdbPath = `/live_tracking/${trackingKey}/location`;

  console.info("[live-tracking.resolve]", {
    childId: normalizedChildId,
    trackingKey,
    rtdbPath,
  });

  const [locationSnapshot, trackingSnapshot, childSnapshot] = await Promise.all([
    realtimeDB.ref(`live_tracking/${trackingKey}/location`).once("value"),
    realtimeDB.ref(`live_tracking/${trackingKey}`).once("value"),
    realtimeDB.ref(`live_tracking/${normalizedChildId}`).once("value"),
  ]);

  const rawLocation = asMap(locationSnapshot.val());
  const latitude = parseCoordinateValue(rawLocation, "latitude", "lat");
  const longitude = parseCoordinateValue(rawLocation, "longitude", "lng");

  console.info("[live-tracking.raw-location]", {
    trackingKey,
    rtdbPath,
    rawLocation,
  });

  if (!isValidCoordinate(latitude, longitude)) {
    const statusMetadata = buildStatusMetadata({
      trackingNode: trackingSnapshot.val(),
      childNode: childSnapshot.val(),
    });

    return {
      raw: statusMetadata.raw,
      trackingKey,
      rtdbPath,
      timestampInferred: false,
      location: null,
      latestStatus: statusMetadata.latestStatus,
      latestSignal: statusMetadata.latestSignal,
      latestTimestamp: statusMetadata.latestTimestamp,
      batteryLevel: null,
    };
  }

  const recordedAt =
    normalizeTimestamp(rawLocation.recorded_at) ??
    normalizeTimestamp(rawLocation.timestamp) ??
    Date.now();

  const location = {
    latitude,
    longitude,
    speed: parseNumber(rawLocation.speed) || 0,
    battery: parseBattery(rawLocation.battery) || 0,
    recorded_at: recordedAt,
  };

  if (rawLocation.location_text?.toString().trim()) {
    location.location_text = rawLocation.location_text.toString().trim();
  }

  const statusMetadata = buildStatusMetadata({
    trackingNode: trackingSnapshot.val(),
    childNode: childSnapshot.val(),
  });

  return {
    raw: {
      ...statusMetadata.raw,
      location,
    },
    trackingKey,
    rtdbPath,
    timestampInferred:
      normalizeTimestamp(rawLocation.recorded_at) === null &&
      normalizeTimestamp(rawLocation.timestamp) === null,
    location,
    latestStatus: statusMetadata.latestStatus,
    latestSignal: statusMetadata.latestSignal,
    latestTimestamp:
      Math.max(
        recordedAt,
        statusMetadata.latestTimestamp || 0,
      ) || recordedAt,
    batteryLevel: location.battery,
  };
}

module.exports = {
  getResolvedLiveTrackingSnapshot,
};
