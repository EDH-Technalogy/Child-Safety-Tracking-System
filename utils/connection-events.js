const { realtimeDB } = require("../firebase");
const { appendChildLog } = require("./child-logs");
const { createAlertRecord, formatCoordinates } = require("./alert-service");
const { safeWriteAuditLog, createSystemActor } = require("./audit-log");
const { getTrackingContextForChild } = require("./live-tracking");
const { normalizeEpochMillisecondsOrNull } = require("./live-timestamp");
const { buildDateKey } = require("./location-history");

const DEFAULT_DEVICE_OFFLINE_THRESHOLD_MS = 30 * 1000;
const DEFAULT_DEVICE_MONITOR_INTERVAL_MS = 30 * 1000;

function readPositiveIntegerEnv(name, fallback) {
  const value = Number(process.env[name]);
  return Number.isFinite(value) && value > 0 ? Math.round(value) : fallback;
}

function getConnectionMonitorConfig() {
  return {
    offlineThresholdMs: readPositiveIntegerEnv(
      "DEVICE_OFFLINE_THRESHOLD_MS",
      DEFAULT_DEVICE_OFFLINE_THRESHOLD_MS
    ),
    monitorIntervalMs: readPositiveIntegerEnv(
      "DEVICE_MONITOR_INTERVAL_MS",
      DEFAULT_DEVICE_MONITOR_INTERVAL_MS
    ),
  };
}

function normalizeNumberOrNull(value) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function normalizeTimestampOrNull(value) {
  return normalizeEpochMillisecondsOrNull(value);
}

function resolveLocationText(address, latitude, longitude) {
  const explicitText = address?.toString().trim() || "";
  if (explicitText) {
    return explicitText;
  }

  if (
    Number.isFinite(Number(latitude)) &&
    Number.isFinite(Number(longitude))
  ) {
    return formatCoordinates(latitude, longitude);
  }

  return null;
}

function buildOfflineDurationLabel(durationMs) {
  const normalizedDurationMs = Number(durationMs);
  if (!Number.isFinite(normalizedDurationMs) || normalizedDurationMs <= 0) {
    return null;
  }

  const totalSeconds = Math.max(1, Math.round(normalizedDurationMs / 1000));
  const hours = Math.floor(totalSeconds / 3600);
  const minutes = Math.floor((totalSeconds % 3600) / 60);
  const seconds = totalSeconds % 60;
  const parts = [];

  if (hours > 0) {
    parts.push(`${hours}h`);
  }
  if (minutes > 0) {
    parts.push(`${minutes}m`);
  }
  if (seconds > 0 && hours === 0) {
    parts.push(`${seconds}s`);
  }

  return parts.join(" ") || "0s";
}

async function resolveParentUserId(childId, parentUserId = "") {
  const normalizedParentUserId = parentUserId?.toString().trim() || "";
  if (normalizedParentUserId) {
    return normalizedParentUserId;
  }

  const trackingContext = await getTrackingContextForChild(childId);
  return trackingContext?.childData?.user_id?.toString().trim() || "";
}

async function appendConnectionEvent({
  type,
  childId,
  trackingKey,
  parentUserId = "",
  title,
  message,
  disconnectedAt = null,
  reconnectedAt = null,
  durationOfflineMs = null,
  lastKnownLat = null,
  lastKnownLng = null,
  lastKnownAccuracy = null,
  lastKnownTimestamp = null,
  lastKnownAddress = null,
  reconnectedLat = null,
  reconnectedLng = null,
  reconnectedAccuracy = null,
  reconnectedTimestamp = null,
  reconnectedAddress = null,
  metadata = {},
  eventId = null,
  createdAt = Date.now(),
}) {
  const normalizedChildId = childId?.toString().trim() || "";
  const normalizedTrackingKey = trackingKey?.toString().trim() || "";
  if (!normalizedChildId || !normalizedTrackingKey) {
    throw new Error("childId and trackingKey are required for connection events");
  }

  const normalizedCreatedAt = normalizeTimestampOrNull(createdAt) || Date.now();
  const normalizedType = type?.toString().trim().toUpperCase() || "DEVICE_STATUS";
  const dateKey = buildDateKey(normalizedCreatedAt);
  const connectionEventsRef = realtimeDB.ref(
    `connection_events/${normalizedChildId}/${dateKey}`
  );
  const resolvedEventId =
    eventId?.toString().trim() || connectionEventsRef.push().key;
  const resolvedParentUserId = await resolveParentUserId(
    normalizedChildId,
    parentUserId
  );

  const eventPayload = {
    eventId: resolvedEventId,
    title: title?.toString().trim() || normalizedType,
    type: normalizedType,
    childId: normalizedChildId,
    trackingKey: normalizedTrackingKey,
    parentUserId: resolvedParentUserId,
    disconnectedAt: normalizeTimestampOrNull(disconnectedAt),
    reconnectedAt: normalizeTimestampOrNull(reconnectedAt),
    durationOfflineMs: normalizeNumberOrNull(durationOfflineMs),
    lastKnownLat: normalizeNumberOrNull(lastKnownLat),
    lastKnownLng: normalizeNumberOrNull(lastKnownLng),
    lastKnownAccuracy: normalizeNumberOrNull(lastKnownAccuracy),
    lastKnownTimestamp: normalizeTimestampOrNull(lastKnownTimestamp),
    lastKnownAddress: lastKnownAddress?.toString().trim() || null,
    reconnectedLat: normalizeNumberOrNull(reconnectedLat),
    reconnectedLng: normalizeNumberOrNull(reconnectedLng),
    reconnectedAccuracy: normalizeNumberOrNull(reconnectedAccuracy),
    reconnectedTimestamp: normalizeTimestampOrNull(reconnectedTimestamp),
    reconnectedAddress: reconnectedAddress?.toString().trim() || null,
    message: message?.toString().trim() || normalizedType,
    dateKey,
    createdAt: normalizedCreatedAt,
    metadata: metadata && typeof metadata === "object" ? metadata : {},
  };

  await connectionEventsRef.child(resolvedEventId).set(eventPayload);

  return {
    id: resolvedEventId,
    dateKey,
    event: eventPayload,
  };
}

async function recordDeviceDisconnected({
  childId,
  trackingKey,
  parentUserId = "",
  disconnectedAt = Date.now(),
  previousLastSeen = null,
  lastKnownLat = null,
  lastKnownLng = null,
  lastKnownAccuracy = null,
  lastKnownTimestamp = null,
  lastKnownAddress = null,
  offlineThresholdMs,
  source = "connection_monitor",
}) {
  const { offlineThresholdMs: resolvedThresholdMs } = getConnectionMonitorConfig();
  const effectiveThresholdMs =
    normalizeNumberOrNull(offlineThresholdMs) || resolvedThresholdMs;
  const normalizedDisconnectedAt =
    normalizeTimestampOrNull(disconnectedAt) || Date.now();
  const resolvedParentUserId = await resolveParentUserId(childId, parentUserId);
  const message = `Device disconnected automatically after no updates for ${Math.round(
    effectiveThresholdMs / 60000
  )} minutes.`;
  const locationText = resolveLocationText(
    lastKnownAddress,
    lastKnownLat,
    lastKnownLng
  );
  const eventResult = await appendConnectionEvent({
    type: "DEVICE_DISCONNECTED",
    childId,
    trackingKey,
    parentUserId: resolvedParentUserId,
    title: "Device disconnected",
    message,
    disconnectedAt: normalizedDisconnectedAt,
    lastKnownLat,
    lastKnownLng,
    lastKnownAccuracy,
    lastKnownTimestamp,
    lastKnownAddress,
    metadata: {
      offlineThresholdMs: effectiveThresholdMs,
      previousLastSeen: normalizeTimestampOrNull(previousLastSeen),
      reason: "NO_RECENT_LOCATION_UPDATE",
      source,
    },
    createdAt: normalizedDisconnectedAt,
  });

  await appendChildLog({
    childId,
    trackingKey,
    parentUserId: resolvedParentUserId,
    type: "DEVICE_DISCONNECTED",
    title: "Device disconnected",
    message,
    latitude: lastKnownLat,
    longitude: lastKnownLng,
    accuracy: lastKnownAccuracy,
    timestamp: normalizedDisconnectedAt,
    dateKey: eventResult.dateKey,
    metadata: {
      source,
      lastKnownTimestamp: normalizeTimestampOrNull(lastKnownTimestamp),
      lastKnownAddress: lastKnownAddress?.toString().trim() || null,
      offlineThresholdMs: effectiveThresholdMs,
      previousLastSeen: normalizeTimestampOrNull(previousLastSeen),
      reason: "NO_RECENT_LOCATION_UPDATE",
      eventId: eventResult.id,
    },
  });

  await createAlertRecord({
    childId,
    type: "DEVICE_DISCONNECTED",
    message: `Your child's device disconnected after no updates for ${Math.round(
      effectiveThresholdMs / 60000
    )} minutes.`,
    locationText,
    latitude: lastKnownLat,
    longitude: lastKnownLng,
    extraFields: {
      tracking_key: trackingKey,
      accuracy: normalizeNumberOrNull(lastKnownAccuracy),
      timestamp: normalizedDisconnectedAt,
      date_key: eventResult.dateKey,
      disconnected_at: normalizedDisconnectedAt,
      last_known_timestamp: normalizeTimestampOrNull(lastKnownTimestamp),
      last_known_address: lastKnownAddress?.toString().trim() || null,
      connection_event_id: eventResult.id,
    },
    writeChildLog: false,
  });

  await safeWriteAuditLog({
    eventType: "device_disconnected_auto",
    entityType: "device",
    entityId: trackingKey,
    title: "Device disconnected",
    description: message,
    performedBy: createSystemActor("Connection Monitor"),
    target: {
      child_id: childId,
      tracking_key: trackingKey,
      parent_user_id: resolvedParentUserId,
    },
    source,
    metadata: {
      childId,
      trackingKey,
      parentUserId: resolvedParentUserId,
      disconnectedAt: normalizedDisconnectedAt,
      previousLastSeen: normalizeTimestampOrNull(previousLastSeen),
      lastKnownLat: normalizeNumberOrNull(lastKnownLat),
      lastKnownLng: normalizeNumberOrNull(lastKnownLng),
      lastKnownAccuracy: normalizeNumberOrNull(lastKnownAccuracy),
      lastKnownTimestamp: normalizeTimestampOrNull(lastKnownTimestamp),
      lastKnownAddress: lastKnownAddress?.toString().trim() || null,
      offlineThresholdMs: effectiveThresholdMs,
    },
  });

  return eventResult;
}

async function recordDeviceReconnected({
  childId,
  trackingKey,
  parentUserId = "",
  reconnectedAt = Date.now(),
  disconnectedAt = null,
  lastKnownLat = null,
  lastKnownLng = null,
  lastKnownAccuracy = null,
  lastKnownTimestamp = null,
  lastKnownAddress = null,
  reconnectedLat = null,
  reconnectedLng = null,
  reconnectedAccuracy = null,
  reconnectedTimestamp = null,
  reconnectedAddress = null,
  source = "location_update",
}) {
  const normalizedReconnectedAt =
    normalizeTimestampOrNull(reconnectedAt) || Date.now();
  const normalizedDisconnectedAt = normalizeTimestampOrNull(disconnectedAt);
  const durationOfflineMs =
    normalizedDisconnectedAt !== null
      ? Math.max(0, normalizedReconnectedAt - normalizedDisconnectedAt)
      : null;
  const resolvedParentUserId = await resolveParentUserId(childId, parentUserId);
  const message = "Device reconnected automatically.";
  const locationText = resolveLocationText(
    reconnectedAddress,
    reconnectedLat,
    reconnectedLng
  );
  const eventResult = await appendConnectionEvent({
    type: "DEVICE_RECONNECTED",
    childId,
    trackingKey,
    parentUserId: resolvedParentUserId,
    title: "Device reconnected",
    message,
    disconnectedAt: normalizedDisconnectedAt,
    reconnectedAt: normalizedReconnectedAt,
    durationOfflineMs,
    lastKnownLat,
    lastKnownLng,
    lastKnownAccuracy,
    lastKnownTimestamp,
    lastKnownAddress,
    reconnectedLat,
    reconnectedLng,
    reconnectedAccuracy,
    reconnectedTimestamp,
    reconnectedAddress,
    metadata: {
      previousOfflineAt: normalizedDisconnectedAt,
      durationOfflineMs,
      reason: "LOCATION_UPDATE_RECEIVED_AFTER_OFFLINE",
      offlineDurationLabel: buildOfflineDurationLabel(durationOfflineMs),
      source,
    },
    createdAt: normalizedReconnectedAt,
  });

  await appendChildLog({
    childId,
    trackingKey,
    parentUserId: resolvedParentUserId,
    type: "DEVICE_RECONNECTED",
    title: "Device reconnected",
    message,
    latitude: reconnectedLat,
    longitude: reconnectedLng,
    accuracy: reconnectedAccuracy,
    timestamp: normalizedReconnectedAt,
    dateKey: eventResult.dateKey,
    metadata: {
      source,
      disconnectedAt: normalizedDisconnectedAt,
      durationOfflineMs,
      offlineDurationLabel: buildOfflineDurationLabel(durationOfflineMs),
      reconnectedTimestamp: normalizeTimestampOrNull(reconnectedTimestamp),
      reconnectedAddress: reconnectedAddress?.toString().trim() || null,
      lastKnownTimestamp: normalizeTimestampOrNull(lastKnownTimestamp),
      lastKnownAddress: lastKnownAddress?.toString().trim() || null,
      eventId: eventResult.id,
    },
  });

  await createAlertRecord({
    childId,
    type: "DEVICE_RECONNECTED",
    message: "Your child's device is online again.",
    locationText,
    latitude: reconnectedLat,
    longitude: reconnectedLng,
    extraFields: {
      tracking_key: trackingKey,
      accuracy: normalizeNumberOrNull(reconnectedAccuracy),
      timestamp: normalizedReconnectedAt,
      date_key: eventResult.dateKey,
      disconnected_at: normalizedDisconnectedAt,
      reconnected_at: normalizedReconnectedAt,
      duration_offline_ms: durationOfflineMs,
      connection_event_id: eventResult.id,
    },
    writeChildLog: false,
  });

  await safeWriteAuditLog({
    eventType: "device_reconnected_auto",
    entityType: "device",
    entityId: trackingKey,
    title: "Device reconnected",
    description: durationOfflineMs
      ? `Device reconnected automatically after being offline for ${buildOfflineDurationLabel(
          durationOfflineMs
        )}.`
      : message,
    performedBy: createSystemActor("Location Update"),
    target: {
      child_id: childId,
      tracking_key: trackingKey,
      parent_user_id: resolvedParentUserId,
    },
    source,
    metadata: {
      childId,
      trackingKey,
      parentUserId: resolvedParentUserId,
      disconnectedAt: normalizedDisconnectedAt,
      reconnectedAt: normalizedReconnectedAt,
      durationOfflineMs,
      lastKnownLat: normalizeNumberOrNull(lastKnownLat),
      lastKnownLng: normalizeNumberOrNull(lastKnownLng),
      lastKnownAccuracy: normalizeNumberOrNull(lastKnownAccuracy),
      lastKnownTimestamp: normalizeTimestampOrNull(lastKnownTimestamp),
      lastKnownAddress: lastKnownAddress?.toString().trim() || null,
      reconnectedLat: normalizeNumberOrNull(reconnectedLat),
      reconnectedLng: normalizeNumberOrNull(reconnectedLng),
      reconnectedAccuracy: normalizeNumberOrNull(reconnectedAccuracy),
      reconnectedTimestamp: normalizeTimestampOrNull(reconnectedTimestamp),
      reconnectedAddress: reconnectedAddress?.toString().trim() || null,
    },
  });

  return eventResult;
}

module.exports = {
  DEFAULT_DEVICE_MONITOR_INTERVAL_MS,
  DEFAULT_DEVICE_OFFLINE_THRESHOLD_MS,
  appendConnectionEvent,
  getConnectionMonitorConfig,
  recordDeviceDisconnected,
  recordDeviceReconnected,
  resolveLocationText,
};
