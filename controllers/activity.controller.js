const { firestore } = require("../firebase");
const {
  AUDIT_LOG_COLLECTION,
  mapLegacyActivityLog,
  normalizeAuditLogRecord,
} = require("../utils/audit-log");
const {
  createHttpError,
  getChildWithAccessOrThrow,
} = require("../utils/child-access");

function mapActivityResponseItem(record = {}) {
  const createdAt = record.timestamp || record.created_at || 0;
  const targetChildId =
    record.target?.child_id ||
    record.target?.id ||
    record.metadata?.childId ||
    record.metadata?.child_id ||
    null;

  return {
    id: record.id || null,
    child_id: targetChildId,
    event_type: record.eventType || record.event_type || "unknown_event",
    description: record.description || "",
    created_at: createdAt,
    title: record.title || record.eventType || record.event_type || "",
    status: record.status || record.result || "success",
    source: record.source || "backend",
  };
}

async function listLegacyActivityLogs(childId) {
  const snapshot = await firestore
    .collection("activity_logs")
    .where("child_id", "==", childId)
    .get();

  return snapshot.docs.map((doc) =>
    mapActivityResponseItem(mapLegacyActivityLog(doc.id, doc.data() || {}))
  );
}

async function listRelevantAuditLogs(childId) {
  const snapshot = await firestore
    .collection(AUDIT_LOG_COLLECTION)
    .where("metadata.childId", "==", childId)
    .get();

  return snapshot.docs
    .map((doc) => normalizeAuditLogRecord(doc.id, doc.data() || {}))
    .filter((entry) =>
      [
        "safe_zone_exit",
        "safe_zone_enter",
        "device_disconnected_auto",
        "device_reconnected_auto",
      ].includes(entry.eventType)
    )
    .map(mapActivityResponseItem);
}

exports.addLog = async (req, res, next) => {
  try {
    const childId = req.body.child_id?.toString().trim();
    const eventType = req.body.event_type?.toString().trim();
    const description = req.body.description?.toString().trim() || "";

    if (!childId) {
      throw createHttpError(400, "child_id is required");
    }

    if (!eventType) {
      throw createHttpError(400, "event_type is required");
    }

    await getChildWithAccessOrThrow(req, childId);

    const createdAt = Date.now();
    const docRef = await firestore.collection("activity_logs").add({
      child_id: childId,
      event_type: eventType,
      description,
      created_at: createdAt,
    });

    console.info("[activity.addLog]", {
      childId,
      eventType,
      createdAt,
      authId: req.auth?.id || null,
      role: req.auth?.role || null,
    });

    res.status(201).json({
      id: docRef.id,
      child_id: childId,
      event_type: eventType,
      description,
      created_at: createdAt,
      message: "Activity log saved",
    });
  } catch (error) {
    next(error);
  }
};

exports.getLogs = async (req, res, next) => {
  try {
    const childId = req.params.child_id?.toString().trim();
    await getChildWithAccessOrThrow(req, childId);

    const [legacyLogs, relevantAuditLogs] = await Promise.all([
      listLegacyActivityLogs(childId),
      listRelevantAuditLogs(childId),
    ]);

    const logs = [...legacyLogs, ...relevantAuditLogs].sort(
      (a, b) => (b.created_at || 0) - (a.created_at || 0)
    );

    console.info("[activity.getLogs]", {
      childId,
      authId: req.auth?.id || null,
      role: req.auth?.role || null,
      total: logs.length,
      legacyCount: legacyLogs.length,
      relevantAuditCount: relevantAuditLogs.length,
    });

    res.json(logs);
  } catch (error) {
    next(error);
  }
};
