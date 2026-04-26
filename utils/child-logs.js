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
  message,
  timestamp = Date.now(),
  metadata = {},
}) {
  const normalizedTimestamp = normalizeLogTimestamp(timestamp);
  const normalizedType = normalizeLogType(type);

  return {
    type: normalizedType,
    childId: childId?.toString().trim() || "",
    trackingKey: trackingKey?.toString().trim() || "",
    parentUserId: parentUserId?.toString().trim() || "",
    message: message?.toString().trim() || normalizedType,
    timestamp: normalizedTimestamp,
    createdAt: normalizedTimestamp,
    metadata: metadata && typeof metadata === "object" ? metadata : {},
  };
}

async function appendChildLog({
  childId,
  trackingKey = "",
  parentUserId = "",
  type,
  message,
  timestamp = Date.now(),
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
    message,
    timestamp,
    metadata,
  });
  const dateKey = buildDateKey(entry.timestamp);
  const childLogsRef = realtimeDB.ref(`child_logs/${normalizedChildId}/${dateKey}`);
  const resolvedLogId = logId?.toString().trim() || childLogsRef.push().key;

  await childLogsRef.child(resolvedLogId).set({
    id: resolvedLogId,
    ...entry,
  });

  return {
    id: resolvedLogId,
    dateKey,
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
    message: source.message?.toString().trim() || "",
    timestamp,
    createdAt:
      normalizeEpochMillisecondsOrNull(source.createdAt) ??
      normalizeEpochMillisecondsOrNull(source.created_at) ??
      timestamp,
    metadata: source.metadata && typeof source.metadata === "object"
      ? source.metadata
      : {},
  };
}

function dedupeChildLogs(logs = []) {
  const seen = new Set();
  const deduped = [];

  for (const log of logs) {
    const dedupeKey = [
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
    message: data.message?.toString().trim() || type,
    timestamp:
      normalizeEpochMillisecondsOrNull(data.created_at) ?? Date.now(),
    createdAt:
      normalizeEpochMillisecondsOrNull(data.created_at) ?? Date.now(),
    metadata: {
      source: "alerts_collection",
      locationText: data.location_text || null,
      zoneName: data.zone_name || null,
      batteryLevel: data.battery_level ?? null,
      originalType: data.type || null,
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
    message:
      type === "DEVICE_ONLINE"
        ? "Device connection restored."
        : type === "DEVICE_OFFLINE"
          ? "Device connection lost."
          : `Device status changed to ${status}.`,
    timestamp:
      normalizeEpochMillisecondsOrNull(data.event_time) ??
      normalizeEpochMillisecondsOrNull(data.created_at) ??
      Date.now(),
    createdAt:
      normalizeEpochMillisecondsOrNull(data.created_at) ??
      normalizeEpochMillisecondsOrNull(data.event_time) ??
      Date.now(),
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
    message: data.description?.toString().trim() || type,
    timestamp:
      normalizeEpochMillisecondsOrNull(data.created_at) ?? Date.now(),
    createdAt:
      normalizeEpochMillisecondsOrNull(data.created_at) ?? Date.now(),
    metadata: {
      source: "activity_logs_collection",
      originalType: data.event_type || null,
    },
  };
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
  const liveLogs = bucketResults
    .expand((logs) => logs)
    .where(
      (log) =>
        log.timestamp >= window.startTimestamp &&
        log.timestamp <= window.endTimestamp
    )
    .toList();

  const legacyLogs = await listLegacyLogsForChild(normalizedChildId, window);
  return dedupeChildLogs([...liveLogs, ...legacyLogs]);
}

module.exports = {
  appendChildLog,
  buildChildLogEntry,
  listChildLogs,
  normalizeLogType,
};
