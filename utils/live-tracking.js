const { firestore, realtimeDB } = require("../firebase");
const { normalizeEpochMillisecondsOrNull } = require("./live-timestamp");
const {
  normalizeTrackingKey: normalizeTrackingKeyOrThrow,
  tryNormalizeTrackingKey,
} = require("./tracking-key-normalizer");

const DEFAULT_ONLINE_THRESHOLD_MS = 60 * 1000;
const DEFAULT_DELAYED_THRESHOLD_MS = 180 * 1000;
const FUTURE_TIMESTAMP_TOLERANCE_MS = 30 * 1000;

function readPositiveIntegerEnv(name, fallback) {
  const value = Number(process.env[name]);
  return Number.isFinite(value) && value > 0 ? Math.round(value) : fallback;
}

function getDeviceStatusThresholds() {
  return {
    onlineThresholdMs: readPositiveIntegerEnv(
      "DEVICE_ONLINE_THRESHOLD_MS",
      DEFAULT_ONLINE_THRESHOLD_MS
    ),
    delayedThresholdMs: readPositiveIntegerEnv(
      "DEVICE_DELAYED_THRESHOLD_MS",
      DEFAULT_DELAYED_THRESHOLD_MS
    ),
  };
}

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

function maxTimestamp(...values) {
  const normalized = values.filter((value) => value !== null);
  return normalized.length > 0 ? Math.max(...normalized) : null;
}

function computeDeviceConnectivityStatus(rawTimestamp, now = Date.now()) {
  const latestTimestamp = normalizeEpochMillisecondsOrNull(rawTimestamp);
  const { onlineThresholdMs, delayedThresholdMs } = getDeviceStatusThresholds();

  if (latestTimestamp === null) {
    return {
      status: "no_data",
      reason: "missing_live_location_timestamp",
      latestTimestamp: null,
      ageMs: null,
      now,
      onlineThresholdMs,
      delayedThresholdMs,
    };
  }

  const rawAgeMs = now - latestTimestamp;
  if (rawAgeMs < -FUTURE_TIMESTAMP_TOLERANCE_MS) {
    return {
      status: "no_data",
      reason: "future_live_location_timestamp",
      latestTimestamp,
      ageMs: rawAgeMs,
      now,
      onlineThresholdMs,
      delayedThresholdMs,
    };
  }

  const ageMs = Math.max(0, rawAgeMs);

  if (ageMs <= onlineThresholdMs) {
    return {
      status: "online",
      reason: "recent_live_location",
      latestTimestamp,
      ageMs,
      now,
      onlineThresholdMs,
      delayedThresholdMs,
    };
  }

  if (ageMs <= delayedThresholdMs) {
    return {
      status: "delayed",
      reason: "live_location_delayed",
      latestTimestamp,
      ageMs,
      now,
      onlineThresholdMs,
      delayedThresholdMs,
    };
  }

  return {
    status: "offline",
    reason: "live_location_stale",
    latestTimestamp,
    ageMs,
    now,
    onlineThresholdMs,
    delayedThresholdMs,
  };
}

function normalizeTrackingKey(rawValue) {
  return tryNormalizeTrackingKey(rawValue);
}

async function getTrackingContextForChild(childId) {
  const normalizedChildId = childId?.toString().trim() || "";
  if (!normalizedChildId) {
    return null;
  }

  const registrySnapshot = await realtimeDB
    .ref(`device_registry_by_child/${normalizedChildId}`)
    .once("value");
  const registryData = registrySnapshot.val() || {};
  const registryTrackingKey = tryNormalizeTrackingKey(
    registryData.tracking_key || registryData.imei || registryData.device_id
  );

  if (registryTrackingKey) {
    const childDoc = await firestore
      .collection("children")
      .doc(normalizedChildId)
      .get();
    if (!childDoc.exists) {
      return null;
    }

    return {
      childId: normalizedChildId,
      childData: childDoc.data() || {},
      deviceDoc: null,
      deviceData: {
        child_id: normalizedChildId,
        imei: registryData.imei || "",
        tracking_key: registryTrackingKey,
        status: registryData.status || "offline",
      },
      trackingKey: registryTrackingKey,
    };
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
    tryNormalizeTrackingKey(deviceData.imei) ||
    tryNormalizeTrackingKey(deviceDoc?.id) ||
    "";

  return {
    childId: normalizedChildId,
    childData: childDoc.data() || {},
    deviceDoc,
    deviceData,
    trackingKey,
  };
}

function buildStatusMetadata({
  trackingNode,
  childNode,
  liveTimestamp,
  now = Date.now(),
}) {
  const trackingNodeMap = asMap(trackingNode);
  const childNodeMap = asMap(childNode);
  const statusNode = asMap(trackingNodeMap.status);
  const statusLastSeen =
    normalizeEpochMillisecondsOrNull(statusNode.lastSeen);
  const statusUpdatedAt =
    normalizeEpochMillisecondsOrNull(statusNode.updatedAt);
  const statusLastOfflineAt =
    normalizeEpochMillisecondsOrNull(statusNode.lastOfflineAt);
  const statusLastOnlineAt =
    normalizeEpochMillisecondsOrNull(statusNode.lastOnlineAt);
  const heartbeatTimestamp = maxTimestamp(
    statusLastSeen,
    statusUpdatedAt,
    liveTimestamp
  );
  const computedStatus = computeDeviceConnectivityStatus(heartbeatTimestamp, now);

  const connection =
    asMap(trackingNodeMap.connection).status !== undefined
      ? asMap(trackingNodeMap.connection)
      : asMap(childNodeMap.connection);
  const deviceStatus =
    asMap(trackingNodeMap.device_status).status !== undefined
      ? asMap(trackingNodeMap.device_status)
      : asMap(childNodeMap.device_status);
  const childStatus = asMap(childNodeMap.child_status);
  const explicitConnectionState =
    statusNode.connectionState?.toString().trim().toLowerCase() ||
    (statusNode.online === false
      ? "offline"
      : statusNode.online === true
        ? "online"
        : "");
  const hasFreshLiveLocation =
    liveTimestamp !== null &&
    computedStatus.latestTimestamp !== null &&
    liveTimestamp === computedStatus.latestTimestamp &&
    (computedStatus.status === "online" || computedStatus.status === "delayed");
  const staleOfflineFlag =
    explicitConnectionState === "offline" &&
    hasFreshLiveLocation &&
    (statusLastOfflineAt === null || liveTimestamp >= statusLastOfflineAt);
  const resolvedStatus = staleOfflineFlag
    ? computedStatus.status
    : explicitConnectionState === "offline"
      ? "offline"
      : computedStatus.status;

  const timestamps = [
    statusLastSeen,
    statusUpdatedAt,
    statusLastOfflineAt,
    statusLastOnlineAt,
    normalizeEpochMillisecondsOrNull(connection.updated_at),
    normalizeEpochMillisecondsOrNull(connection.time),
    normalizeEpochMillisecondsOrNull(deviceStatus.updated_at),
    normalizeEpochMillisecondsOrNull(childStatus.updated_at),
  ].filter((value) => value !== null);

  return {
    raw: {
      ...(Object.keys(statusNode).length > 0 ? { status: statusNode } : {}),
      ...(Object.keys(childStatus).length > 0 ? { child_status: childStatus } : {}),
      ...(Object.keys(deviceStatus).length > 0 ? { device_status: deviceStatus } : {}),
      ...(Object.keys(connection).length > 0 ? { connection } : {}),
    },
    latestStatus: resolvedStatus,
    rawLatestStatus:
      statusNode.connectionState?.toString().trim() ||
      statusNode.deviceStatus?.toString().trim() ||
      connection.status?.toString().trim() ||
      deviceStatus.status?.toString().trim() ||
      childStatus.status?.toString().trim() ||
      null,
    latestSignal:
      (staleOfflineFlag ? "fresh_live_location_overrode_stale_offline_flag" : null) ||
      computedStatus.reason ||
      connection.reason?.toString().trim() ||
      deviceStatus.reason?.toString().trim() ||
      null,
    latestTimestamp: computedStatus.latestTimestamp,
    latestStatusTimestamp: timestamps.length > 0 ? Math.max(...timestamps) : null,
    latestAgeMs: computedStatus.ageMs,
    now: computedStatus.now,
    statusReason: computedStatus.reason,
    onlineThresholdMs: computedStatus.onlineThresholdMs,
    delayedThresholdMs: computedStatus.delayedThresholdMs,
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
  const liveLocationTimestamp =
    normalizeEpochMillisecondsOrNull(rawLocation.recorded_at) ??
    normalizeEpochMillisecondsOrNull(rawLocation.timestamp);

  console.info("[live-tracking.raw-location]", {
    trackingKey,
    rtdbPath,
    rawLocation,
  });

  if (!isValidCoordinate(latitude, longitude)) {
    const statusMetadata = buildStatusMetadata({
      trackingNode: trackingSnapshot.val(),
      childNode: childSnapshot.val(),
      liveTimestamp: liveLocationTimestamp,
    });

    console.info("[live-tracking.status]", {
      childId: normalizedChildId,
      trackingKey,
      rawLiveTimestamp: liveLocationTimestamp,
      now: statusMetadata.now,
      ageMs: statusMetadata.latestAgeMs,
      status: statusMetadata.latestStatus,
      reason: statusMetadata.statusReason,
      hasValidLocation: false,
      onlineThresholdMs: statusMetadata.onlineThresholdMs,
      delayedThresholdMs: statusMetadata.delayedThresholdMs,
    });

    return {
      raw: statusMetadata.raw,
      trackingKey,
      rtdbPath,
      timestampInferred: false,
      location: null,
      latestStatus: statusMetadata.latestStatus,
      rawLatestStatus: statusMetadata.rawLatestStatus,
      latestSignal: statusMetadata.latestSignal,
      latestTimestamp: statusMetadata.latestTimestamp,
      latestStatusTimestamp: statusMetadata.latestStatusTimestamp,
      latestAgeMs: statusMetadata.latestAgeMs,
      statusReason: statusMetadata.statusReason,
      onlineThresholdMs: statusMetadata.onlineThresholdMs,
      delayedThresholdMs: statusMetadata.delayedThresholdMs,
      batteryLevel: null,
    };
  }

  const recordedAt = liveLocationTimestamp;

  const location = {
    latitude,
    longitude,
    speed: parseNumber(rawLocation.speed) || 0,
    battery: parseBattery(rawLocation.battery) || 0,
    recorded_at: recordedAt || 0,
  };

  if (rawLocation.location_text?.toString().trim()) {
    location.location_text = rawLocation.location_text.toString().trim();
  }

  const statusMetadata = buildStatusMetadata({
    trackingNode: trackingSnapshot.val(),
    childNode: childSnapshot.val(),
    liveTimestamp: recordedAt,
  });

  console.info("[live-tracking.status]", {
    childId: normalizedChildId,
    trackingKey,
    rawLiveTimestamp: recordedAt,
    now: statusMetadata.now,
    ageMs: statusMetadata.latestAgeMs,
    status: statusMetadata.latestStatus,
    reason: statusMetadata.statusReason,
    hasValidLocation: true,
    onlineThresholdMs: statusMetadata.onlineThresholdMs,
    delayedThresholdMs: statusMetadata.delayedThresholdMs,
  });

  return {
    raw: {
      ...statusMetadata.raw,
      location,
    },
    trackingKey,
    rtdbPath,
    timestampInferred:
      normalizeEpochMillisecondsOrNull(rawLocation.recorded_at) === null &&
      normalizeEpochMillisecondsOrNull(rawLocation.timestamp) === null,
    location,
    latestStatus: statusMetadata.latestStatus,
    rawLatestStatus: statusMetadata.rawLatestStatus,
    latestSignal: statusMetadata.latestSignal,
    latestTimestamp: statusMetadata.latestTimestamp,
    latestStatusTimestamp: statusMetadata.latestStatusTimestamp,
    latestAgeMs: statusMetadata.latestAgeMs,
    statusReason: statusMetadata.statusReason,
    onlineThresholdMs: statusMetadata.onlineThresholdMs,
    delayedThresholdMs: statusMetadata.delayedThresholdMs,
    batteryLevel: location.battery,
  };
}

module.exports = {
  computeDeviceConnectivityStatus,
  getTrackingContextForChild,
  getResolvedLiveTrackingSnapshot,
  getDeviceStatusThresholds,
  normalizeTrackingKey,
};
