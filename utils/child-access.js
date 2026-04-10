const { firestore } = require("../firebase");

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

function ensureCanManageUserChildren(req, targetUserId) {
  ensureAuthenticated(req);

  if (isAdminRequest(req)) {
    return;
  }

  if (req.auth?.type === "user" && req.auth.id === targetUserId) {
    return;
  }

  throw createHttpError(403, "You do not have permission to access this child");
}

function ensureCanAccessChildRecord(req, childData = {}) {
  const ownerUserId = childData.user_id?.toString().trim() || "";

  if (!ownerUserId) {
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

module.exports = {
  createHttpError,
  ensureAuthenticated,
  isAdminRequest,
  ensureCanManageUserChildren,
  ensureCanAccessChildRecord,
  getChildOrThrow,
  getChildWithAccessOrThrow,
};
