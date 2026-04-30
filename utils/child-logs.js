const { firestore, realtimeDB } = require("../firebase");
const { normalizeEpochMillisecondsOrNull } = require("./live-timestamp");
const { buildDateKey, buildDateWindow } = require("./location-history");

function normalizeLogTimestamp(value) {
  return normalizeEpochMillisecondsOrNull(value) || Date.now();
}

function normalizeLogType(type) {
  const normalizedType = type?.toString().trim().toUpperCase() || "INFO";

  switch (normalizedType) {
    case "OUT_ZONE":
    case "SAFE_ZONE_EXIT":
    case "ZONE_EXIT":
      return "GEOFENCE_BREACH";
    case "IN_ZONE":
    case "SAFE_ZONE_ENTER":
    case "ZONE_ENTER":
      return "GEOFENCE_RETURN";
    case "DEVICE_OFF":
      return "DEVICE_OFFLINE";
    case "LOW_BATTERY":
      return "BATTERY_LOW";
    default:
      return normalizedType;
  }
}

function buildChildLogEntry({
  childId,
  trackingKey = "",
  parentUserId = "",
  type,
  title = "",
  message,
  latitude = null,
  longitude = null,
  accuracy = null,
  timestamp = Date.now(),
  dateKey = "",
  metadata = {},
}) {
  const normalizedTimestamp = normalizeLogTimestamp(timestamp);
  const normalizedType = normalizeLogType(type);

  return {
    type: normalizedType,
    childId: childId?.toString().trim() || "",
    trackingKey: trackingKey?.toString().trim() || "",
    parentUserId: parentUserId?.toString().trim() || "",
    title: title?.toString().trim() || normalizedType,
    message: message?.toString().trim() || normalizedType,
    latitude: Number.isFinite(Number(latitude)) ? Number(latitude) : null,
    longitude: Number.isFinite(Number(longitude)) ? Number(longitude) : null,
    lat: Number.isFinite(Number(latitude)) ? Number(latitude) : null,
    lng: Number.isFinite(Number(longitude)) ? Number(longitude) : null,
    accuracy: Number.isFinite(Number(accuracy)) ? Number(accuracy) : null,
    timestamp: normalizedTimestamp,
    createdAt: normalizedTimestamp,
    dateKey: dateKey?.toString().trim() || buildDateKey(normalizedTimestamp),
    metadata: metadata && typeof metadata === "object" ? metadata : {},
  };
}

async function appendChildLog({
  childId,
  trackingKey = "",
  parentUserId = "",
  type,
  title = "",
  message,
  latitude = null,
  longitude = null,
  accuracy = null,
  timestamp = Date.now(),
  dateKey = "",
  metadata = {},
  logId = null,
}) {
  const normalizedChildId = childId?.toString().trim() || "";
  if (!normalizedChildId) {
    throw new Error("childId is required for child log");
  }

  const entry = buildChildLogEntry({
    childId: normalizedChildId,
    trackingKey,
    parentUserId,
    type,
    title,
    message,
    latitude,
    longitude,
    accuracy,
    timestamp,
    dateKey,
    metadata,
  });
  const resolvedDateKey = entry.dateKey || buildDateKey(entry.timestamp);
  const childLogsRef = realtimeDB.ref(
    `child_logs/${normalizedChildId}/${resolvedDateKey}`
  );
  const resolvedLogId = logId?.toString().trim() || childLogsRef.push().key;

  await childLogsRef.child(resolvedLogId).set({
    id: resolvedLogId,
    ...entry,
  });

  return {
    id: resolvedLogId,
    dateKey: resolvedDateKey,
    entry,
  };
}

function normalizeChildLog(id, rawValue = {}, childId = "") {
  const source = rawValue && typeof rawValue === "object" ? rawValue : {};
  const timestamp =
    normalizeEpochMillisecondsOrNull(source.timestamp) ??
    normalizeEpochMillisecondsOrNull(source.createdAt) ??
    normalizeEpochMillisecondsOrNull(source.created_at);

  if (!timestamp) {
    return null;
  }

  return {
    id: (source.id ?? id ?? "").toString(),
    type: normalizeLogType(source.type),
    childId: source.childId?.toString().trim() || childId,
    trackingKey: source.trackingKey?.toString().trim() || "",
    parentUserId: source.parentUserId?.toString().trim() || "",
    title:
      source.title?.toString().trim() ||
      normalizeLogType(source.type),
    message: source.message?.toString().trim() || "",
    latitude: Number.isFinite(Number(source.latitude ?? source.lat))
      ? Number(source.latitude ?? source.lat)
      : null,
    longitude: Number.isFinite(Number(source.longitude ?? source.lng))
      ? Number(source.longitude ?? source.lng)
      : null,
    accuracy: Number.isFinite(Number(source.accuracy))
      ? Number(source.accuracy)
      : null,
    timestamp,
    createdAt:
      normalizeEpochMillisecondsOrNull(source.createdAt) ??
      normalizeEpochMillisecondsOrNull(source.created_at) ??
      timestamp,
    dateKey:
      source.dateKey?.toString().trim() || buildDateKey(timestamp),
    metadata: source.metadata && typeof source.metadata === "object"
      ? source.metadata
      : {},
  };
}

function dedupeChildLogs(logs = []) {
  const seen = new Set();
  const deduped = [];

  for (const log of logs) {
    const transitionEventId =
      log.metadata?.eventId ||
      log.metadata?.connectionEventId ||
      null;
    const dedupeKey = transitionEventId
      ? `connection-event:${transitionEventId}`
      : [
          log.type || "",
          log.timestamp || 0,
          log.message || "",
          log.childId || "",
        ].join("|");

    if (seen.has(dedupeKey)) {
      continue;
    }

    seen.add(dedupeKey);
    deduped.push(log);
  }

  deduped.sort((a, b) => (b.timestamp || 0) - (a.timestamp || 0));
  return deduped;
}

async function readChildLogsBucket(childId, bucketKey) {
  const snapshot = await realtimeDB
    .ref(`child_logs/${childId}/${bucketKey}`)
    .once("value");
  const logs = [];
  const rawValue = snapshot.val() || {};

  for (const [id, data] of Object.entries(rawValue)) {
    const normalizedLog = normalizeChildLog(id, data, childId);
    if (normalizedLog) {
      logs.push(normalizedLog);
    }
  }

  return logs;
}

function isStatusOnline(status) {
  const normalizedStatus = status?.toString().trim().toLowerCase() || "";
  return ["online", "connected", "active"].includes(normalizedStatus);
}

function isStatusOffline(status) {
  const normalizedStatus = status?.toString().trim().toLowerCase() || "";
  return ["offline", "disconnected", "device_off", "inactive"].includes(
    normalizedStatus
  );
}

function buildLegacyLogFromAlert(docId, data = {}) {
  const type = normalizeLogType(data.type);
  return {
    id: docId,
    type,
    childId: data.child_id?.toString().trim() || "",
    trackingKey: data.tracking_key?.toString().trim() || "",
    parentUserId: data.user_id?.toString().trim() || "",
    title: type,
    message: data.message?.toString().trim() || type,
    latitude: Number.isFinite(Number(data.latitude)) ? Number(data.latitude) : null,
    longitude: Number.isFinite(Number(data.longitude)) ? Number(data.longitude) : null,
    accuracy: Number.isFinite(Number(data.accuracy))
      ? Number(data.accuracy)
      : null,
    timestamp:
      normalizeEpochMillisecondsOrNull(data.created_at) ?? Date.now(),
    createdAt:
      normalizeEpochMillisecondsOrNull(data.created_at) ?? Date.now(),
    dateKey: buildDateKey(
      normalizeEpochMillisecondsOrNull(data.created_at) ?? Date.now()
    ),
    metadata: {
      source: "alerts_collection",
      locationText: data.location_text || null,
      zoneName: data.zone_name || null,
      batteryLevel: data.battery_level ?? null,
      originalType: data.type || null,
      connectionEventId: data.connection_event_id || null,
    },
  };
}

function buildLegacyLogFromConnection(docId, data = {}) {
  const status = data.status?.toString().trim() || "unknown";
  const type = isStatusOnline(status)
    ? "DEVICE_ONLINE"
    : isStatusOffline(status)
      ? "DEVICE_OFFLINE"
      : "DEVICE_STATUS";

  return {
    id: docId,
    type,
    childId: data.child_id?.toString().trim() || "",
    trackingKey: data.tracking_key?.toString().trim() || "",
    parentUserId: "",
    title:
      type === "DEVICE_ONLINE"
        ? "Device reconnected"
        : type === "DEVICE_OFFLINE"
          ? "Device disconnected"
          : "Device status",
    message:
      type === "DEVICE_ONLINE"
        ? "Device connection restored."
        : type === "DEVICE_OFFLINE"
          ? "Device connection lost."
          : `Device status changed to ${status}.`,
    latitude: Number.isFinite(Number(data.latitude)) ? Number(data.latitude) : null,
    longitude: Number.isFinite(Number(data.longitude)) ? Number(data.longitude) : null,
    accuracy: null,
    timestamp:
      normalizeEpochMillisecondsOrNull(data.event_time) ??
      normalizeEpochMillisecondsOrNull(data.created_at) ??
      Date.now(),
    createdAt:
      normalizeEpochMillisecondsOrNull(data.created_at) ??
      normalizeEpochMillisecondsOrNull(data.event_time) ??
      Date.now(),
    dateKey: buildDateKey(
      normalizeEpochMillisecondsOrNull(data.event_time) ??
        normalizeEpochMillisecondsOrNull(data.created_at) ??
        Date.now()
    ),
    metadata: {
      source: "connection_logs_collection",
      previousStatus: data.previous_status || null,
      status,
      latitude: data.latitude ?? null,
      longitude: data.longitude ?? null,
    },
  };
}

function buildLegacyLogFromActivity(docId, data = {}) {
  const type = normalizeLogType(data.event_type);

  return {
    id: docId,
    type,
    childId: data.child_id?.toString().trim() || "",
    trackingKey: "",
    parentUserId: "",
    title: type,
    message: data.description?.toString().trim() || type,
    latitude: null,
    longitude: null,
    accuracy: null,
    timestamp:
      normalizeEpochMillisecondsOrNull(data.created_at) ?? Date.now(),
    createdAt:
      normalizeEpochMillisecondsOrNull(data.created_at) ?? Date.now(),
    dateKey: buildDateKey(
      normalizeEpochMillisecondsOrNull(data.created_at) ?? Date.now()
    ),
    metadata: {
      source: "activity_logs_collection",
      originalType: data.event_type || null,
    },
  };
}

function normalizeConnectionEvent(id, rawValue = {}, childId = "") {
  const source = rawValue && typeof rawValue === "object" ? rawValue : {};
  const timestamp =
    normalizeEpochMillisecondsOrNull(source.createdAt) ??
    normalizeEpochMillisecondsOrNull(source.reconnectedAt) ??
    normalizeEpochMillisecondsOrNull(source.disconnectedAt) ??
    normalizeEpochMillisecondsOrNull(source.timestamp);

  if (!timestamp) {
    return null;
  }

  const type = normalizeLogType(source.type);
  const reconnectedLat = Number(source.reconnectedLat);
  const reconnectedLng = Number(source.reconnectedLng);
  const lastKnownLat = Number(source.lastKnownLat);
  const lastKnownLng = Number(source.lastKnownLng);

  return {
    id: (source.eventId ?? source.id ?? id ?? "").toString(),
    type,
    childId: source.childId?.toString().trim() || childId,
    trackingKey: source.trackingKey?.toString().trim() || "",
    parentUserId: source.parentUserId?.toString().trim() || "",
    title:
      source.title?.toString().trim() ||
      (type === "DEVICE_RECONNECTED"
        ? "Device reconnected"
        : type === "DEVICE_DISCONNECTED"
          ? "Device disconnected"
          : type),
    message: source.message?.toString().trim() || type,
    latitude:
      Number.isFinite(reconnectedLat) && Number.isFinite(reconnectedLng)
        ? reconnectedLat
        : Number.isFinite(lastKnownLat) && Number.isFinite(lastKnownLng)
          ? lastKnownLat
          : null,
    longitude:
      Number.isFinite(reconnectedLat) && Number.isFinite(reconnectedLng)
        ? reconnectedLng
        : Number.isFinite(lastKnownLat) && Number.isFinite(lastKnownLng)
          ? lastKnownLng
          : null,
    accuracy:
      Number.isFinite(Number(source.reconnectedAccuracy))
        ? Number(source.reconnectedAccuracy)
        : Number.isFinite(Number(source.lastKnownAccuracy))
          ? Number(source.lastKnownAccuracy)
          : null,
    timestamp,
    createdAt:
      normalizeEpochMillisecondsOrNull(source.createdAt) ?? timestamp,
    dateKey:
      source.dateKey?.toString().trim() || buildDateKey(timestamp),
    metadata: {
      source: "connection_events",
      eventId: (source.eventId ?? source.id ?? id ?? "").toString(),
      disconnectedAt:
        normalizeEpochMillisecondsOrNull(source.disconnectedAt),
      reconnectedAt:
        normalizeEpochMillisecondsOrNull(source.reconnectedAt),
      durationOfflineMs:
        Number.isFinite(Number(source.durationOfflineMs))
          ? Number(source.durationOfflineMs)
          : null,
      lastKnownLat: Number.isFinite(lastKnownLat) ? lastKnownLat : null,
      lastKnownLng: Number.isFinite(lastKnownLng) ? lastKnownLng : null,
      lastKnownAccuracy: Number.isFinite(Number(source.lastKnownAccuracy))
        ? Number(source.lastKnownAccuracy)
        : null,
      lastKnownTimestamp:
        normalizeEpochMillisecondsOrNull(source.lastKnownTimestamp),
      lastKnownAddress: source.lastKnownAddress?.toString().trim() || null,
      reconnectedLat: Number.isFinite(reconnectedLat) ? reconnectedLat : null,
      reconnectedLng: Number.isFinite(reconnectedLng) ? reconnectedLng : null,
      reconnectedAccuracy: Number.isFinite(Number(source.reconnectedAccuracy))
        ? Number(source.reconnectedAccuracy)
        : null,
      reconnectedTimestamp:
        normalizeEpochMillisecondsOrNull(source.reconnectedTimestamp),
      reconnectedAddress:
        source.reconnectedAddress?.toString().trim() || null,
      ...(source.metadata && typeof source.metadata === "object"
        ? source.metadata
        : {}),
    },
  };
}

async function readConnectionEventsBucket(childId, bucketKey) {
  const snapshot = await realtimeDB
    .ref(`connection_events/${childId}/${bucketKey}`)
    .once("value");
  const events = [];
  const rawValue = snapshot.val() || {};

  for (const [id, data] of Object.entries(rawValue)) {
    const normalizedEvent = normalizeConnectionEvent(id, data, childId);
    if (normalizedEvent) {
      events.push(normalizedEvent);
    }
  }

  return events;
}

async function listLegacyLogsForChild(childId, window) {
  const [alertsSnapshot, connectionSnapshot, activitySnapshot] = await Promise.all([
    firestore.collection("alerts").where("child_id", "==", childId).get(),
    firestore.collection("connection_logs").where("child_id", "==", childId).get(),
    firestore.collection("activity_logs").where("child_id", "==", childId).get(),
  ]);

  const logs = [];

  alertsSnapshot.forEach((doc) => {
    const log = buildLegacyLogFromAlert(doc.id, doc.data() || {});
    if (
      log.timestamp >= window.startTimestamp &&
      log.timestamp <= window.endTimestamp
    ) {
      logs.push(log);
    }
  });

  connectionSnapshot.forEach((doc) => {
    const log = buildLegacyLogFromConnection(doc.id, doc.data() || {});
    if (
      log.timestamp >= window.startTimestamp &&
      log.timestamp <= window.endTimestamp
    ) {
      logs.push(log);
    }
  });

  activitySnapshot.forEach((doc) => {
    const log = buildLegacyLogFromActivity(doc.id, doc.data() || {});
    if (
      log.timestamp >= window.startTimestamp &&
      log.timestamp <= window.endTimestamp
    ) {
      logs.push(log);
    }
  });

  return logs;
}

async function listChildLogs(
  childId,
  { dateKey = null, timezoneOffsetMinutes = 0 } = {}
) {
  const normalizedChildId = childId?.toString().trim() || "";
  if (!normalizedChildId) {
    return [];
  }

  const effectiveDateKey =
    dateKey?.toString().trim() || buildDateKey(Date.now());
  const window = buildDateWindow(effectiveDateKey, timezoneOffsetMinutes);
  if (!window) {
    return [];
  }

  const bucketResults = await Promise.all(
    window.bucketKeys.map((bucketKey) =>
      readChildLogsBucket(normalizedChildId, bucketKey)
    )
  );
  const connectionBucketResults = await Promise.all(
    window.bucketKeys.map((bucketKey) =>
      readConnectionEventsBucket(normalizedChildId, bucketKey)
    )
  );
  const liveLogs = bucketResults
    .flatMap((logs) => logs)
    .filter(
      (log) =>
        log.timestamp >= window.startTimestamp &&
        log.timestamp <= window.endTimestamp
    );
  const connectionEvents = connectionBucketResults
    .flatMap((logs) => logs)
    .filter(
      (log) =>
        log.timestamp >= window.startTimestamp &&
        log.timestamp <= window.endTimestamp
    );

  const legacyLogs = await listLegacyLogsForChild(normalizedChildId, window);
  return dedupeChildLogs([...connectionEvents, ...liveLogs, ...legacyLogs]);
}

module.exports = {
  appendChildLog,
  buildChildLogEntry,
  listChildLogs,
  normalizeLogType,
  readChildLogsBucket,
  readConnectionEventsBucket,
};
