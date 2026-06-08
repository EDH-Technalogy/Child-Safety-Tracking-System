const { firestore, realtimeDB } = require("../firebase");
const { normalizeEpochMillisecondsOrNull } = require("./live-timestamp");
const {
  reverseGeocodeCoordinates,
  buildFallbackPlaceName,
} = require("./reverse-geocode");

const KABUL_TIME_ZONE = "Asia/Kabul";
const STATUS_CARD_MIN_WRITE_INTERVAL_MS = 60 * 1000;

function normalizeTimestamp(value, fallback = Date.now()) {
  return normalizeEpochMillisecondsOrNull(value) || fallback;
}

function normalizeCoordinate(value) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function normalizeStatus(value) {
  const normalized = value?.toString().trim().toLowerCase() || "unknown";
  if (["online", "connected", "active"].includes(normalized)) {
    return "online";
  }

  if (["offline", "disconnected", "inactive", "device_off"].includes(normalized)) {
    return "offline";
  }

  return normalized;
}

function buildStatusName(status) {
  const normalizedStatus = normalizeStatus(status);
  if (normalizedStatus === "online") {
    return "Online";
  }

  if (normalizedStatus === "offline") {
    return "Offline";
  }

  return normalizedStatus
    ? normalizedStatus.charAt(0).toUpperCase() + normalizedStatus.slice(1)
    : "Unknown";
}

function formatKabulDateTime(timestamp) {
  const date = new Date(normalizeTimestamp(timestamp));
  const formatter = new Intl.DateTimeFormat("en-CA", {
    timeZone: KABUL_TIME_ZONE,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hour12: true,
  });

  const parts = formatter.formatToParts(date);
  const byType = Object.fromEntries(
    parts.filter((part) => part.type !== "literal").map((part) => [part.type, part.value])
  );
  const normalizedDayPeriod = (byType.dayPeriod || "")
    .replace(/\./g, "")
    .toUpperCase();

  return `${byType.year}-${byType.month}-${byType.day} ${byType.hour}:${byType.minute}:${byType.second} ${normalizedDayPeriod}`.trim();
}

function shouldWriteStatusCard(previous = {}, nextPayload = {}, statusChanged = false) {
  if (statusChanged) {
    return true;
  }

  const previousChildName = previous.child_name?.toString().trim() || "";
  const nextChildName = nextPayload.child_name?.toString().trim() || "";
  if (previousChildName !== nextChildName) {
    return true;
  }

  const previousDeviceName = previous.device_name?.toString().trim() || "";
  const nextDeviceName = nextPayload.device_name?.toString().trim() || "";
  if (previousDeviceName !== nextDeviceName) {
    return true;
  }

  const previousLatitude = normalizeCoordinate(previous.latitude);
  const previousLongitude = normalizeCoordinate(previous.longitude);
  const nextLatitude = normalizeCoordinate(nextPayload.latitude);
  const nextLongitude = normalizeCoordinate(nextPayload.longitude);
  const hadPreviousCoordinates =
    previousLatitude !== null && previousLongitude !== null;
  const hasNextCoordinates = nextLatitude !== null && nextLongitude !== null;
  if (!hadPreviousCoordinates && hasNextCoordinates) {
    return true;
  }

  const previousPlaceName = previous.place_name?.toString().trim() || null;
  const nextPlaceName = nextPayload.place_name?.toString().trim() || null;
  if (previousPlaceName === null && nextPlaceName !== null) {
    return true;
  }

  const previousHeartbeatAt = normalizeTimestamp(previous.last_heartbeat_at, 0);
  const nextHeartbeatAt = normalizeTimestamp(nextPayload.last_heartbeat_at, 0);
  if (nextHeartbeatAt - previousHeartbeatAt >= STATUS_CARD_MIN_WRITE_INTERVAL_MS) {
    return true;
  }

  const previousTimestamp = normalizeTimestamp(previous.timestamp, 0);
  const nextTimestamp = normalizeTimestamp(nextPayload.timestamp, 0);
  return nextTimestamp - previousTimestamp >= STATUS_CARD_MIN_WRITE_INTERVAL_MS;
}

async function resolvePlaceName({
  explicitPlaceName,
  latitude,
  longitude,
  fallbackPlaceName = null,
}) {
  const normalizedExplicit = explicitPlaceName?.toString().trim() || "";
  if (normalizedExplicit) {
    return normalizedExplicit;
  }

  const normalizedFallback = fallbackPlaceName?.toString().trim() || "";
  if (normalizedFallback) {
    return normalizedFallback;
  }

  if (latitude === null || longitude === null) {
    return null;
  }

  return (
    (await reverseGeocodeCoordinates(latitude, longitude)) ||
    buildFallbackPlaceName(latitude, longitude)
  );
}

async function appendDeviceStatusLog({
  childId,
  trackingKey,
  deviceName,
  childName,
  status,
  latitude,
  longitude,
  timestamp,
  placeName,
  source,
}) {
  const normalizedChildId = childId?.toString().trim() || "";
  if (!normalizedChildId) {
    throw new Error("childId is required for device status log");
  }

  const normalizedTimestamp = normalizeTimestamp(timestamp);
  const normalizedStatus = normalizeStatus(status);
  const logRef = realtimeDB.ref(`device_status_logs/${normalizedChildId}`).push();
  const payload = {
    id: logRef.key,
    child_id: normalizedChildId,
    tracking_key: trackingKey?.toString().trim() || normalizedChildId,
    device_name: deviceName?.toString().trim() || childName?.toString().trim() || "Device",
    child_name: childName?.toString().trim() || "",
    status: normalizedStatus,
    status_name: buildStatusName(normalizedStatus),
    latitude,
    longitude,
    address: placeName?.toString().trim() || null,
    timestamp: normalizedTimestamp,
    formatted_time: formatKabulDateTime(normalizedTimestamp),
    place_name: placeName?.toString().trim() || null,
    source: source?.toString().trim() || "system",
    created_at: Date.now(),
  };

  await logRef.set(payload);
  return payload;
}

async function upsertDeviceStatusCard({
  childId,
  trackingKey,
  childName,
  deviceName,
  status,
  latitude = null,
  longitude = null,
  timestamp = Date.now(),
  heartbeatAt = null,
  placeName = null,
  source = "system",
  writeTransitionLog = true,
  previousStatusHint = null,
}) {
  const normalizedChildId = childId?.toString().trim() || "";
  const normalizedTrackingKey = trackingKey?.toString().trim() || normalizedChildId;
  if (!normalizedChildId || !normalizedTrackingKey) {
    throw new Error("childId and trackingKey are required for device status");
  }

  const normalizedStatus = normalizeStatus(status);
  const normalizedTimestamp = normalizeTimestamp(timestamp);
  const normalizedHeartbeatAt = normalizeTimestamp(
    heartbeatAt,
    normalizedTimestamp
  );
  const historySnapshot = await realtimeDB
    .ref(`device_status_logs/${normalizedChildId}`)
    .limitToFirst(1)
    .once("value");
  const hasExistingHistory = historySnapshot.val() !== null;
  const normalizedLatitude = normalizeCoordinate(latitude);
  const normalizedLongitude = normalizeCoordinate(longitude);
  const resolvedPlaceName = await resolvePlaceName({
    explicitPlaceName: placeName,
    latitude: normalizedLatitude,
    longitude: normalizedLongitude,
  });
  const docRef = firestore.collection("device_status_cards").doc(normalizedChildId);

  let transitionInfo = null;
  await firestore.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(docRef);
    const previous = snapshot.exists ? snapshot.data() || {} : {};
    const previousStatus = normalizeStatus(previous.status);
    const historyPreviousStatus =
      previousStatusHint === null || previousStatusHint === undefined
        ? previousStatus
        : normalizeStatus(previousStatusHint);
    const shouldTrackInHistory =
      normalizedStatus === "online" || normalizedStatus === "offline";
    const statusChanged =
      !snapshot.exists || previousStatus !== normalizedStatus;
    const historyStatusChanged =
      !snapshot.exists || historyPreviousStatus !== normalizedStatus;

    const nextPayload = {
      child_id: normalizedChildId,
      tracking_key: normalizedTrackingKey,
      child_name:
        childName?.toString().trim() ||
        previous.child_name?.toString().trim() ||
        "",
      device_name:
        deviceName?.toString().trim() ||
        previous.device_name?.toString().trim() ||
        childName?.toString().trim() ||
        normalizedTrackingKey,
      status: normalizedStatus,
      latitude:
        normalizedLatitude ?? normalizeCoordinate(previous.latitude),
      longitude:
        normalizedLongitude ?? normalizeCoordinate(previous.longitude),
      place_name:
        resolvedPlaceName ||
        previous.place_name?.toString().trim() ||
        null,
      timestamp: normalizedTimestamp,
      formatted_time: formatKabulDateTime(normalizedTimestamp),
      last_heartbeat_at: normalizedHeartbeatAt,
      status_updated_at: statusChanged
        ? normalizedTimestamp
        : normalizeTimestamp(previous.status_updated_at, normalizedTimestamp),
      updated_at: Date.now(),
      source: source?.toString().trim() || "system",
    };

    if (normalizedStatus === "online") {
      nextPayload.last_online_at = normalizedTimestamp;
      nextPayload.last_offline_at =
        normalizeTimestamp(previous.last_offline_at, 0) || null;
    } else if (normalizedStatus === "offline") {
      nextPayload.last_offline_at = normalizedTimestamp;
      nextPayload.last_online_at =
        normalizeTimestamp(previous.last_online_at, 0) || null;
    }

    const shouldWriteCard =
      !snapshot.exists ||
      shouldWriteStatusCard(previous, nextPayload, statusChanged);

    if (shouldWriteCard && snapshot.exists) {
      transaction.set(docRef, nextPayload, { merge: true });
    } else if (shouldWriteCard) {
      transaction.set(docRef, {
        ...nextPayload,
        created_at: Date.now(),
      });
    }

    transitionInfo = {
      shouldLog: Boolean(
        writeTransitionLog &&
          shouldTrackInHistory &&
          (!hasExistingHistory || historyStatusChanged)
      ),
      previousStatus: snapshot.exists ? historyPreviousStatus : null,
      currentPayload: shouldWriteCard ? nextPayload : previous,
      logPayload: nextPayload,
      statusChanged,
      cardUpdated: shouldWriteCard,
    };
  });

  if (transitionInfo?.shouldLog) {
    await appendDeviceStatusLog({
      childId: normalizedChildId,
      trackingKey: normalizedTrackingKey,
      deviceName:
        transitionInfo.logPayload.device_name,
      childName: transitionInfo.logPayload.child_name,
      status: transitionInfo.logPayload.status,
      latitude: transitionInfo.logPayload.latitude,
      longitude: transitionInfo.logPayload.longitude,
      timestamp: normalizedTimestamp,
      placeName: transitionInfo.logPayload.place_name,
      source,
    });
  }

  return {
    previousStatus: transitionInfo?.previousStatus || null,
    statusChanged: Boolean(transitionInfo?.statusChanged),
    cardUpdated: Boolean(transitionInfo?.cardUpdated),
    current: transitionInfo?.currentPayload || null,
  };
}

module.exports = {
  formatKabulDateTime,
  normalizeStatus,
  appendDeviceStatusLog,
  buildStatusName,
  upsertDeviceStatusCard,
};
