const { admin, firestore } = require("../firebase");

const AUDIT_LOG_COLLECTION = "audit_logs";
const SENSITIVE_KEY_PATTERN =
  /(password|token|secret|authorization|cookie|otp|private.?key|credential)/i;

function sanitizeAuditValue(value, depth = 0) {
  if (value === undefined) {
    return undefined;
  }

  if (value === null || typeof value === "number" || typeof value === "boolean") {
    return value;
  }

  if (typeof value === "string") {
    return value.length > 1000 ? `${value.slice(0, 997)}...` : value;
  }

  if (depth > 5) {
    return "[Max depth reached]";
  }

  if (Array.isArray(value)) {
    return value
      .map((item) => sanitizeAuditValue(item, depth + 1))
      .filter((item) => item !== undefined);
  }

  if (typeof value === "object") {
    const sanitized = {};

    for (const [key, childValue] of Object.entries(value)) {
      if (SENSITIVE_KEY_PATTERN.test(key)) {
        continue;
      }

      const normalizedValue = sanitizeAuditValue(childValue, depth + 1);
      if (normalizedValue !== undefined) {
        sanitized[key] = normalizedValue;
      }
    }

    return sanitized;
  }

  return String(value);
}

function extractChangedFields(oldValues = {}, newValues = {}) {
  const sanitizedOldValues = sanitizeAuditValue(oldValues) || {};
  const sanitizedNewValues = sanitizeAuditValue(newValues) || {};
  const keys = new Set([
    ...Object.keys(sanitizedOldValues),
    ...Object.keys(sanitizedNewValues),
  ]);

  return [...keys].filter((key) => {
    return (
      JSON.stringify(sanitizedOldValues[key]) !==
      JSON.stringify(sanitizedNewValues[key])
    );
  });
}

function inferSource(req, fallback = "backend") {
  const url = req?.originalUrl || "";

  if (url.startsWith("/api/admin")) {
    return "admin_panel";
  }

  if (url.startsWith("/api/users") || url.startsWith("/api/children")) {
    return "mobile_app";
  }

  if (url.startsWith("/api")) {
    return "backend";
  }

  return fallback;
}

function buildPerformedByFromRequest(req, fallback = null) {
  if (req?.auth) {
    return sanitizeAuditValue({
      id: req.auth.id || null,
      name: req.auth.name || null,
      email: req.auth.email || null,
      role: req.auth.role || null,
      type: req.auth.type || null,
    });
  }

  return sanitizeAuditValue(fallback);
}

function createSystemActor(name = "System") {
  return {
    id: "system",
    name,
    role: "system",
    type: "system",
  };
}

function normalizeAuditLogRecord(id, data = {}) {
  const timestamp = data.timestamp || data.created_at || 0;

  return {
    id,
    eventType: data.eventType || data.event_type || "unknown_event",
    entityType: data.entityType || data.entity_type || "system",
    entityId: data.entityId || data.entity_id || null,
    title: data.title || data.eventType || data.event_type || "Audit Event",
    description: data.description || "",
    performedBy: sanitizeAuditValue(data.performedBy || data.performed_by) || null,
    target: sanitizeAuditValue(data.target) || null,
    status: data.status || data.result || "success",
    result: data.result || data.status || "success",
    timestamp,
    source: data.source || "backend",
    metadata: sanitizeAuditValue(data.metadata) || {},
  };
}

function mapLegacyActivityLog(id, data = {}) {
  return normalizeAuditLogRecord(id, {
    eventType: data.event_type || "legacy_event",
    entityType: data.child_id ? "child" : "system",
    entityId: data.child_id || data.user_id || data.device_id || null,
    title: data.event_type || "Legacy Activity",
    description: data.description || "",
    status: "success",
    source: "legacy",
    timestamp: data.created_at || 0,
    metadata: sanitizeAuditValue({
      legacy: true,
      child_id: data.child_id,
      user_id: data.user_id,
      device_id: data.device_id,
    }),
    target: data.child_id ? { id: data.child_id } : null,
  });
}

async function writeAuditLog({
  eventType,
  entityType,
  entityId = null,
  title,
  description,
  performedBy = null,
  target = null,
  status = "success",
  result,
  source = "backend",
  metadata = {},
}) {
  const timestamp = Date.now();
  const payload = {
    eventType,
    entityType,
    entityId,
    title,
    description,
    performedBy: sanitizeAuditValue(performedBy) || null,
    target: sanitizeAuditValue(target) || null,
    status,
    result: result || status,
    timestamp,
    created_at: timestamp,
    source,
    metadata: sanitizeAuditValue(metadata) || {},
    serverTimestamp: admin.firestore.FieldValue.serverTimestamp(),
  };

  const docRef = await firestore.collection(AUDIT_LOG_COLLECTION).add(payload);
  return {
    id: docRef.id,
    ...payload,
  };
}

async function safeWriteAuditLog(entry) {
  try {
    return await writeAuditLog(entry);
  } catch (error) {
    console.error("[AUDIT_LOG_ERROR]", error.message || error);
    return null;
  }
}

module.exports = {
  AUDIT_LOG_COLLECTION,
  sanitizeAuditValue,
  extractChangedFields,
  inferSource,
  buildPerformedByFromRequest,
  createSystemActor,
  normalizeAuditLogRecord,
  mapLegacyActivityLog,
  writeAuditLog,
  safeWriteAuditLog,
};
