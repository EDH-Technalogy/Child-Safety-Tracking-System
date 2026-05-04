function isPlainObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function normalizeId(value) {
  return value?.toString().trim() || "";
}

function normalizeType(value) {
  return normalizeId(value).toUpperCase();
}

function normalizeEpochMilliseconds(value, fallback = 0) {
  if (value === undefined || value === null || value === "") {
    return fallback;
  }

  if (typeof value === "number" && Number.isFinite(value)) {
    return value;
  }

  if (typeof value === "string") {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : fallback;
  }

  if (typeof value?.toMillis === "function") {
    return value.toMillis();
  }

  if (typeof value?._seconds === "number") {
    const nanoseconds =
      typeof value._nanoseconds === "number" ? value._nanoseconds : 0;
    return value._seconds * 1000 + Math.floor(nanoseconds / 1000000);
  }

  if (typeof value?.seconds === "number") {
    const nanoseconds =
      typeof value.nanoseconds === "number" ? value.nanoseconds : 0;
    return value.seconds * 1000 + Math.floor(nanoseconds / 1000000);
  }

  return fallback;
}

const SAFE_ZONE_ALERT_TYPES = new Set([
  "SAFE_ZONE",
  "OUT_ZONE",
  "IN_ZONE",
  "ZONE_EXIT",
  "ZONE_ENTER",
  "ZONE_ENTRY",
  "SAFE_ZONE_EXIT",
  "SAFE_ZONE_ENTER",
]);

function looksLikeSingleAlertPayload(value) {
  if (!isPlainObject(value)) {
    return false;
  }

  return (
    Object.prototype.hasOwnProperty.call(value, "message") ||
    Object.prototype.hasOwnProperty.call(value, "type") ||
    Object.prototype.hasOwnProperty.call(value, "timestamp") ||
    Object.prototype.hasOwnProperty.call(value, "created_at") ||
    Object.prototype.hasOwnProperty.call(value, "alert_id") ||
    Object.prototype.hasOwnProperty.call(value, "isRead") ||
    Object.prototype.hasOwnProperty.call(value, "is_read")
  );
}

function isSafeZoneAlert(alert = {}) {
  const type = normalizeType(alert.original_type || alert.type);
  if (SAFE_ZONE_ALERT_TYPES.has(type)) {
    return true;
  }

  const message = normalizeId(alert.message).toLowerCase();
  return message.includes("safe zone") || message.includes("geofence");
}

function isSosAlert(alert = {}) {
  const type = normalizeType(alert.original_type || alert.type);
  if (type === "SOS") {
    return true;
  }

  const message = normalizeId(alert.message).toLowerCase();
  return message.includes("sos") || message.includes("emergency alert");
}

function alertCategory(alert = {}, source = "") {
  if (isSosAlert(alert)) {
    return "SOS";
  }

  if (isSafeZoneAlert(alert)) {
    return "SAFE_ZONE";
  }

  const type = normalizeType(alert.type);
  if (!type && source === "admin_alerts") {
    return "SAFE_ZONE";
  }

  return type || "ALERT";
}

function alertTimestamp(alert = {}) {
  return (
    normalizeEpochMilliseconds(alert.created_at) ||
    normalizeEpochMilliseconds(alert.timestamp) ||
    normalizeEpochMilliseconds(alert.createdAt) ||
    0
  );
}

function normalizeAlert(alert, source, fallbackId = "") {
  const data = isPlainObject(alert) ? alert : {};
  const id = normalizeId(data.alert_id || data.id || fallbackId);
  if (!id) {
    return null;
  }

  const originalType = normalizeType(data.original_type || data.type);
  const category = alertCategory(
    {
      ...data,
      original_type: originalType,
      type: originalType,
    },
    source
  );
  const type = originalType || category;
  const timestamp = alertTimestamp(data);
  const userId = normalizeId(
    data.userId || data.user_id || data.parentUserId || data.parent_user_id
  );
  const childId = normalizeId(data.childId || data.child_id);
  const isRead =
    data.is_read === true ||
    data.isRead === true ||
    normalizeId(data.status).toLowerCase() === "read";
  const status = isRead ? "read" : "unread";

  return {
    ...data,
    id,
    alert_id: id,
    source,
    source_id: `${source}:${id}`,
    composite_id: `${source}:${id}`,
    type,
    original_type: originalType || type,
    alertCategory: category,
    alert_category: category,
    message: normalizeId(data.message),
    timestamp,
    created_at: timestamp,
    userId,
    user_id: userId,
    childId,
    child_id: childId,
    child_name: normalizeId(data.child_name || data.childName),
    status,
    is_read: isRead,
    isRead,
  };
}

function collectAlertsFromRealtimeValue(
  rawValue,
  source,
  { childIdFallback = "", includeNested = false } = {}
) {
  if (!isPlainObject(rawValue)) {
    return [];
  }

  const alerts = [];
  Object.entries(rawValue).forEach(([key, value]) => {
    if (looksLikeSingleAlertPayload(value)) {
      const normalized = normalizeAlert(
        {
          ...value,
          child_id: value.child_id || childIdFallback,
        },
        source,
        key
      );
      if (normalized) {
        alerts.push(normalized);
      }
      return;
    }

    if (!includeNested || !isPlainObject(value)) {
      return;
    }

    Object.entries(value).forEach(([nestedKey, nestedValue]) => {
      if (!looksLikeSingleAlertPayload(nestedValue)) {
        return;
      }

      const normalized = normalizeAlert(
        {
          ...nestedValue,
          child_id: nestedValue.child_id || key || childIdFallback,
        },
        source,
        nestedKey
      );
      if (normalized) {
        alerts.push(normalized);
      }
    });
  });

  return alerts;
}

function alertPriority(alert = {}) {
  if (alert.source === "admin_alerts" && alert.alert_category === "SAFE_ZONE") {
    return 50;
  }

  if (alert.source === "alerts_live" && alert.alert_category === "SOS") {
    return 50;
  }

  if (alert.source === "admin_alerts" || alert.source === "alerts_live") {
    return 40;
  }

  if (alert.source === "alerts_by_child") {
    return 30;
  }

  return 10;
}

function mergeNormalizedAlerts(alerts = []) {
  const merged = new Map();

  alerts.filter(Boolean).forEach((alert) => {
    const key = `${alert.child_id || ""}:${alert.id}`;
    const existing = merged.get(key);

    if (!existing || alertPriority(alert) >= alertPriority(existing)) {
      merged.set(key, {
        ...alert,
        sources: [
          ...new Set([...(existing?.sources || []), alert.source].filter(Boolean)),
        ],
      });
      return;
    }

    existing.sources = [
      ...new Set([...(existing.sources || []), alert.source].filter(Boolean)),
    ];
  });

  return Array.from(merged.values()).sort(
    (a, b) => Number(b.timestamp || b.created_at || 0) -
      Number(a.timestamp || a.created_at || 0)
  );
}

function isUnreadAlert(alert = {}) {
  return (
    alert.is_read !== true &&
    alert.isRead !== true &&
    normalizeId(alert.status).toLowerCase() !== "read"
  );
}

module.exports = {
  SAFE_ZONE_ALERT_TYPES,
  alertTimestamp,
  collectAlertsFromRealtimeValue,
  isSafeZoneAlert,
  isSosAlert,
  isUnreadAlert,
  looksLikeSingleAlertPayload,
  mergeNormalizedAlerts,
  normalizeAlert,
  normalizeEpochMilliseconds,
};
