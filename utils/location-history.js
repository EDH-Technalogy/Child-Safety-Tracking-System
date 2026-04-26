const { realtimeDB } = require("../firebase");
const { normalizeEpochMillisecondsOrNull } = require("./live-timestamp");
const { getTrackingContextForChild } = require("./live-tracking");

const DAY_IN_MILLISECONDS = 24 * 60 * 60 * 1000;

function normalizeHistoryTimestamp(value) {
  return normalizeEpochMillisecondsOrNull(value) || Date.now();
}

function buildDateKey(timestamp) {
  return new Date(timestamp).toISOString().slice(0, 10);
}

function parseTimezoneOffsetMinutes(value) {
  const numericValue = Number(value);
  return Number.isFinite(numericValue) ? Math.round(numericValue) : 0;
}

function parseDateKey(dateKey) {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(
    dateKey?.toString().trim() || ""
  );
  if (!match) {
    return null;
  }

  return {
    year: Number(match[1]),
    month: Number(match[2]),
    day: Number(match[3]),
  };
}

function buildDateWindow(dateKey, timezoneOffsetMinutes = 0) {
  const parsedDate = parseDateKey(dateKey);
  if (!parsedDate) {
    return null;
  }

  const offsetMinutes = parseTimezoneOffsetMinutes(timezoneOffsetMinutes);
  const utcStartTimestamp =
    Date.UTC(parsedDate.year, parsedDate.month - 1, parsedDate.day) -
    offsetMinutes * 60 * 1000;
  const utcEndTimestamp = utcStartTimestamp + DAY_IN_MILLISECONDS - 1;

  return {
    dateKey: dateKey.toString().trim(),
    timezoneOffsetMinutes: offsetMinutes,
    startTimestamp: utcStartTimestamp,
    endTimestamp: utcEndTimestamp,
    bucketKeys: [...new Set([buildDateKey(utcStartTimestamp), buildDateKey(utcEndTimestamp)])],
  };
}

function isValidCoordinate(latitude, longitude) {
  return (
    Number.isFinite(latitude) &&
    Number.isFinite(longitude) &&
    latitude >= -90 &&
    latitude <= 90 &&
    longitude >= -180 &&
    longitude <= 180
  );
}

function buildLocationHistoryEntry({
  childId,
  trackingKey,
  latitude,
  longitude,
  speed = 0,
  battery = 0,
  locationText = null,
  accuracy = null,
  heading = null,
  altitude = null,
  source = "device",
  recordedAt = Date.now(),
}) {
  const timestamp = normalizeHistoryTimestamp(recordedAt);
  const normalizedLatitude = Number(latitude);
  const normalizedLongitude = Number(longitude);

  return {
    child_id: childId,
    tracking_key: trackingKey || childId,
    latitude: Number.isFinite(normalizedLatitude) ? normalizedLatitude : 0,
    longitude: Number.isFinite(normalizedLongitude) ? normalizedLongitude : 0,
    lat: Number.isFinite(normalizedLatitude) ? normalizedLatitude : 0,
    lng: Number.isFinite(normalizedLongitude) ? normalizedLongitude : 0,
    speed: Number(speed) || 0,
    battery: Math.max(0, Math.round(Number(battery) || 0)),
    location_text: locationText?.toString().trim() || null,
    accuracy: Number.isFinite(Number(accuracy)) ? Number(accuracy) : null,
    heading: Number.isFinite(Number(heading)) ? Number(heading) : null,
    altitude: Number.isFinite(Number(altitude)) ? Number(altitude) : null,
    source: source?.toString().trim() || "device",
    created_at: timestamp,
    recorded_at: timestamp,
    timestamp,
  };
}

async function appendLocationHistory(payload) {
  const normalizedChildId = payload.childId?.toString().trim() || "";
  const historyKey =
    payload.trackingKey?.toString().trim() || normalizedChildId;

  if (!normalizedChildId || !historyKey) {
    throw new Error("childId and trackingKey are required for location history");
  }

  const entry = buildLocationHistoryEntry({
    ...payload,
    childId: normalizedChildId,
    trackingKey: historyKey,
  });
  const dateKey = buildDateKey(entry.recorded_at);
  const timestampKey = entry.recorded_at.toString();

  await realtimeDB.ref().update({
    [`location_history/${historyKey}/${dateKey}/${timestampKey}`]: entry,
    [`location_daily_index/${dateKey}/${normalizedChildId}/${timestampKey}`]: true,
  });

  return {
    dateKey,
    timestamp: entry.recorded_at,
    historyKey,
    entry,
  };
}

function normalizeHistoryEntry(id, rawValue = {}, historyKey = "", childId = "") {
  const source = rawValue && typeof rawValue === "object" ? rawValue : {};
  const latitude = Number(source.latitude ?? source.lat);
  const longitude = Number(source.longitude ?? source.lng);
  const recordedAt =
    normalizeEpochMillisecondsOrNull(source.recorded_at) ??
    normalizeEpochMillisecondsOrNull(source.timestamp);

  if (!isValidCoordinate(latitude, longitude) || recordedAt === null) {
    return null;
  }

  return {
    id,
    child_id: source.child_id?.toString().trim() || childId,
    tracking_key: source.tracking_key?.toString().trim() || historyKey,
    latitude,
    longitude,
    lat: latitude,
    lng: longitude,
    speed: Number(source.speed) || 0,
    battery: Math.max(0, Math.round(Number(source.battery) || 0)),
    location_text: source.location_text?.toString().trim() || null,
    accuracy: Number.isFinite(Number(source.accuracy))
      ? Number(source.accuracy)
      : null,
    heading: Number.isFinite(Number(source.heading))
      ? Number(source.heading)
      : null,
    altitude: Number.isFinite(Number(source.altitude))
      ? Number(source.altitude)
      : null,
    source: source.source?.toString().trim() || "device",
    created_at:
      normalizeEpochMillisecondsOrNull(source.created_at) ?? recordedAt,
    recorded_at: recordedAt,
    timestamp: recordedAt,
  };
}

function collectHistoryEntries(rawValue, historyKey = "", childId = "") {
  const history = [];
  if (!rawValue || typeof rawValue !== "object") {
    return history;
  }

  for (const [id, data] of Object.entries(rawValue)) {
    const normalizedEntry = normalizeHistoryEntry(id, data, historyKey, childId);
    if (normalizedEntry) {
      history.push(normalizedEntry);
    }
  }

  return history;
}

function dedupeHistoryEntries(entries = []) {
  const seen = new Set();
  const deduped = [];

  for (const entry of entries) {
    const key = [
      entry.tracking_key || "",
      entry.recorded_at || 0,
      Number(entry.latitude || 0).toFixed(6),
      Number(entry.longitude || 0).toFixed(6),
    ].join("|");

    if (seen.has(key)) {
      continue;
    }

    seen.add(key);
    deduped.push(entry);
  }

  deduped.sort((a, b) => (a.recorded_at || 0) - (b.recorded_at || 0));
  return deduped;
}

async function resolveHistoryKeysForChild(childId) {
  const normalizedChildId = childId?.toString().trim() || "";
  if (!normalizedChildId) {
    return [];
  }

  const trackingContext = await getTrackingContextForChild(normalizedChildId);
  const historyKeys = [
    trackingContext?.trackingKey?.toString().trim() || "",
    normalizedChildId,
  ].filter(Boolean);

  return [...new Set(historyKeys)];
}

async function readHistoryBucket(historyKey, bucketKey, childId = "") {
  const snapshot = await realtimeDB
    .ref(`location_history/${historyKey}/${bucketKey}`)
    .once("value");

  return collectHistoryEntries(snapshot.val(), historyKey, childId);
}

async function listChildLocationHistory(
  childId,
  { dateKey = null, limit = null, timezoneOffsetMinutes = 0 } = {}
) {
  const normalizedChildId = childId?.toString().trim() || "";
  if (!normalizedChildId) {
    return [];
  }

  const historyKeys = await resolveHistoryKeysForChild(normalizedChildId);
  if (historyKeys.length === 0) {
    return [];
  }

  const entries = [];

  if (dateKey) {
    const window = buildDateWindow(dateKey, timezoneOffsetMinutes);
    if (!window) {
      return [];
    }

    const bucketReads = [];
    for (const historyKey of historyKeys) {
      for (const bucketKey of window.bucketKeys) {
        bucketReads.push(readHistoryBucket(historyKey, bucketKey, normalizedChildId));
      }
    }

    const bucketResults = await Promise.all(bucketReads);
    bucketResults.forEach((result) => entries.push(...result));

    const filteredEntries = entries.filter((entry) => {
      const timestamp = entry.recorded_at || 0;
      return (
        timestamp >= window.startTimestamp && timestamp <= window.endTimestamp
      );
    });

    const dedupedFilteredEntries = dedupeHistoryEntries(filteredEntries);
    if (!limit || dedupedFilteredEntries.length <= limit) {
      return dedupedFilteredEntries;
    }

    return dedupedFilteredEntries.slice(
      dedupedFilteredEntries.length - limit
    );
  }

  for (const historyKey of historyKeys) {
    const snapshot = await realtimeDB.ref(`location_history/${historyKey}`).once("value");
    const rawValue = snapshot.val() || {};
    for (const dayEntries of Object.values(rawValue)) {
      entries.push(...collectHistoryEntries(dayEntries, historyKey, normalizedChildId));
    }
  }

  const dedupedEntries = dedupeHistoryEntries(entries);
  if (!limit || dedupedEntries.length <= limit) {
    return dedupedEntries;
  }

  return dedupedEntries.slice(dedupedEntries.length - limit);
}

async function getDailyLocationIndexStats(dateKey) {
  const normalizedDateKey = dateKey?.toString().trim() || buildDateKey(Date.now());
  const snapshot = await realtimeDB
    .ref(`location_daily_index/${normalizedDateKey}`)
    .once("value");
  const rawValue = snapshot.val() || {};
  const childIds = Object.keys(rawValue);
  let totalLocationUpdates = 0;

  childIds.forEach((childId) => {
    const childEntries = rawValue[childId];
    if (childEntries && typeof childEntries === "object") {
      totalLocationUpdates += Object.keys(childEntries).length;
    }
  });

  return {
    date: normalizedDateKey,
    activeDevicesCount: childIds.length,
    totalLocationUpdates,
  };
}

module.exports = {
  appendLocationHistory,
  buildDateKey,
  buildDateWindow,
  buildLocationHistoryEntry,
  getDailyLocationIndexStats,
  listChildLocationHistory,
  normalizeHistoryTimestamp,
  parseTimezoneOffsetMinutes,
  resolveHistoryKeysForChild,
};
