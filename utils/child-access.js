const { firestore } = require("../firebase");
const { normalizeTrackingKey } = require("./live-tracking");

function createHttpError(status, message) {
  const error = new Error(message);
  error.status = status;
  return error;
}

function ensureAuthenticated(req) {
  if (!req.auth) {
    throw createHttpError(401, "Authorization token is required");
  }
}

function isAdminRequest(req) {
  return req.auth?.role === "admin";
}

function logOwnershipValidation(req, targetUserId, result, reason) {
  console.info("[child-access.ownership]", {
    method: req.method,
    path: req.originalUrl || req.path,
    role: req.auth?.role || "anonymous",
    authType: req.auth?.type || null,
    authId: req.auth?.id || null,
    targetUserId: targetUserId || null,
    result,
    reason,
  });
}

function ensureCanManageUserChildren(req, targetUserId) {
  ensureAuthenticated(req);

  if (isAdminRequest(req)) {
    logOwnershipValidation(req, targetUserId, "allowed", "admin");
    return;
  }

  if (req.auth?.type === "user" && req.auth.id === targetUserId) {
    logOwnershipValidation(req, targetUserId, "allowed", "owner");
    return;
  }

  logOwnershipValidation(req, targetUserId, "denied", "not_owner");
  throw createHttpError(403, "You do not have permission to access this child");
}

function ensureCanAccessChildRecord(req, childData = {}) {
  const ownerUserId = childData.user_id?.toString().trim() || "";

  if (!ownerUserId) {
    logOwnershipValidation(req, ownerUserId, "denied", "missing_owner");
    throw createHttpError(400, "Child record is missing user_id");
  }

  ensureCanManageUserChildren(req, ownerUserId);
}

async function getChildOrThrow(childId) {
  const childRef = firestore.collection("children").doc(childId);
  const childDoc = await childRef.get();

  if (!childDoc.exists) {
    throw createHttpError(404, "Child not found");
  }

  return { childRef, childDoc };
}

async function getChildWithAccessOrThrow(req, childId) {
  const { childRef, childDoc } = await getChildOrThrow(childId);
  ensureCanAccessChildRecord(req, childDoc.data());
  return { childRef, childDoc };
}

async function getLinkedDeviceForChild(childId) {
  const snap = await firestore
    .collection("devices")
    .where("child_id", "==", childId)
    .limit(1)
    .get();

  if (snap.empty) {
    return null;
  }

  return {
    deviceDoc: snap.docs[0],
    deviceData: snap.docs[0].data() || {},
  };
}

function normalizeDeviceIdentifier(value) {
  const normalized = value?.toString().trim() || "";
  if (!normalized) {
    return "";
  }

  return normalizeTrackingKey(normalized).trim();
}

function collectChildEventDeviceIdentifiers(req) {
  const values = [
    req.body?.device_id,
    req.body?.deviceId,
    req.body?.imei,
    req.body?.tracking_key,
    req.body?.trackingKey,
    req.query?.device_id,
    req.query?.deviceId,
    req.query?.imei,
    req.query?.tracking_key,
    req.query?.trackingKey,
  ];

  return [...new Set(values.map(normalizeDeviceIdentifier).filter(Boolean))];
}

function logChildEventWriteValidation(req, childId, result, reason, metadata = {}) {
  console.info("[child-access.write]", {
    method: req.method,
    path: req.originalUrl || req.path,
    childId: childId || null,
    role: req.auth?.role || "anonymous",
    authType: req.auth?.type || null,
    authId: req.auth?.id || null,
    result,
    reason,
    ...metadata,
  });
}

async function ensureCanWriteChildEvent(req, childId, { requireAuth = false } = {}) {
  const normalizedChildId = childId?.toString().trim() || "";
  if (!normalizedChildId) {
    throw createHttpError(400, "child_id is required");
  }

  if (req.auth) {
    await getChildWithAccessOrThrow(req, normalizedChildId);
    logChildEventWriteValidation(req, normalizedChildId, "allowed", "authenticated");
    return {
      mode: "authenticated",
      childId: normalizedChildId,
    };
  }

  if (requireAuth) {
    logChildEventWriteValidation(req, normalizedChildId, "denied", "missing_auth");
    throw createHttpError(401, "Authorization token is required");
  }

  const linkedDevice = await getLinkedDeviceForChild(normalizedChildId);
  if (!linkedDevice) {
    logChildEventWriteValidation(
      req,
      normalizedChildId,
      "denied",
      "missing_linked_device"
    );
    throw createHttpError(403, "No linked device found for this child");
  }

  const providedIdentifiers = collectChildEventDeviceIdentifiers(req);
  const linkedIdentifiers = new Set(
    [
      normalizeDeviceIdentifier(linkedDevice.deviceDoc.id),
      normalizeDeviceIdentifier(linkedDevice.deviceData.imei),
    ].filter(Boolean)
  );

  const matchedIdentifier =
    providedIdentifiers.find((value) => linkedIdentifiers.has(value)) || null;

  if (!matchedIdentifier) {
    logChildEventWriteValidation(
      req,
      normalizedChildId,
      "denied",
      "linked_device_identifier_required",
      {
        providedIdentifierCount: providedIdentifiers.length,
      }
    );
    throw createHttpError(
      403,
      "A valid linked device identifier is required for this child event"
    );
  }

  logChildEventWriteValidation(
    req,
    normalizedChildId,
    "allowed",
    "linked_device_identifier",
    {
      deviceId: linkedDevice.deviceDoc.id,
      matchedIdentifier,
    }
  );

  return {
    mode: "linked_device_identifier",
    childId: normalizedChildId,
    deviceId: linkedDevice.deviceDoc.id,
  };
}

module.exports = {
  createHttpError,
  ensureAuthenticated,
  isAdminRequest,
  logOwnershipValidation,
  ensureCanManageUserChildren,
  ensureCanAccessChildRecord,
  ensureCanWriteChildEvent,
  getChildOrThrow,
  getChildWithAccessOrThrow,
  getLinkedDeviceForChild,
};
