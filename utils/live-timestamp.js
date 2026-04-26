const MIN_EPOCH_MILLISECONDS = 1000000000000;
const MIN_EPOCH_SECONDS = 1000000000;

function parseNumber(value) {
  const numericValue = Number(value);
  return Number.isFinite(numericValue) ? numericValue : null;
}

function normalizeEpochMillisecondsOrNull(value) {
  const numericValue = parseNumber(value);
  if (numericValue === null || numericValue <= 0) {
    return null;
  }

  if (numericValue >= MIN_EPOCH_MILLISECONDS) {
    return Math.round(numericValue);
  }

  if (numericValue >= MIN_EPOCH_SECONDS) {
    return Math.round(numericValue * 1000);
  }

  return null;
}

function normalizeEpochMilliseconds(value, fallback = Date.now()) {
  return normalizeEpochMillisecondsOrNull(value) ?? fallback;
}

function normalizeRealtimeLocationTimestamps(rawLocation, fallback = Date.now()) {
  const location =
    rawLocation && typeof rawLocation === "object" ? { ...rawLocation } : {};
  const normalizedTimestamp =
    normalizeEpochMillisecondsOrNull(location.timestamp) ??
    normalizeEpochMillisecondsOrNull(location.recorded_at) ??
    fallback;
  const normalizedRecordedAt =
    normalizeEpochMillisecondsOrNull(location.recorded_at) ??
    normalizeEpochMillisecondsOrNull(location.timestamp) ??
    normalizedTimestamp;

  const payload = {
    ...location,
    timestamp: normalizedTimestamp,
    recorded_at: normalizedRecordedAt,
  };

  return {
    payload,
    changed:
      location.timestamp !== payload.timestamp ||
      location.recorded_at !== payload.recorded_at,
    rawTimestamp: location.timestamp,
    rawRecordedAt: location.recorded_at,
    normalizedTimestamp,
    normalizedRecordedAt,
  };
}

module.exports = {
  MIN_EPOCH_MILLISECONDS,
  normalizeEpochMilliseconds,
  normalizeEpochMillisecondsOrNull,
  normalizeRealtimeLocationTimestamps,
};
