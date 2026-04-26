const { firestore } = require("../firebase");
const { verifyAuthToken } = require("../utils/auth-token");
const {
  findFallbackAdminById,
  toSafeAdmin,
} = require("../utils/local-auth-fallback");

function createHttpError(status, message) {
  const error = new Error(message);
  error.status = status;
  return error;
}

function getBearerToken(req) {
  const authorization = req.headers.authorization || "";

  if (!authorization.startsWith("Bearer ")) {
    return null;
  }

  return authorization.slice("Bearer ".length).trim();
}

async function resolveCurrentAuthState(payload) {
  if (payload.type === "admin") {
    const fallbackAdmin = toSafeAdmin(findFallbackAdminById(payload.sub));
    if (fallbackAdmin) {
      return {
        id: fallbackAdmin.id,
        email: fallbackAdmin.email || payload.email || "",
        name: fallbackAdmin.name || "",
        role: "admin",
        type: "admin",
        source: "local_auth_fallback",
      };
    }

    const adminDoc = await firestore.collection("admins").doc(payload.sub).get();

    if (!adminDoc.exists) {
      throw createHttpError(401, "Admin session is no longer valid");
    }

    const adminData = adminDoc.data();
    if (adminData.status !== "active") {
      throw createHttpError(403, "Admin account is not active");
    }

    return {
      id: adminDoc.id,
      email: adminData.email || payload.email || "",
      name: adminData.name || "",
      role: adminData.role || "admin",
      type: "admin",
    };
  }

  if (payload.type === "user") {
    const userDoc = await firestore.collection("users").doc(payload.sub).get();

    if (!userDoc.exists) {
      throw createHttpError(401, "User session is no longer valid");
    }

    const userData = userDoc.data();
    if (userData.status === "blocked") {
      throw createHttpError(403, "Account is blocked");
    }

    return {
      id: userDoc.id,
      email: userData.email || payload.email || "",
      name: userData.name || "",
      role: userData.role === "admin" ? "admin" : "user",
      type: "user",
    };
  }

  throw createHttpError(401, "Unsupported session type");
}

async function authenticateRequest(req) {
  const token = getBearerToken(req);
  if (!token) {
    throw createHttpError(401, "Authorization token is required");
  }

  const payload = verifyAuthToken(token);
  return resolveCurrentAuthState(payload);
}

async function requireAuthenticatedAccess(req, res, next) {
  try {
    req.auth = await authenticateRequest(req);
    next();
  } catch (error) {
    next(
      error.status
        ? error
        : createHttpError(401, error.message || "Invalid authorization token")
    );
  }
}

async function attachOptionalAuth(req, res, next) {
  try {
    const token = getBearerToken(req);
    if (!token) {
      req.auth = null;
      return next();
    }

    req.auth = await authenticateRequest(req);
    return next();
  } catch (error) {
    next(
      error.status
        ? error
        : createHttpError(401, error.message || "Invalid authorization token")
    );
  }
}

async function requireAdminAccess(req, res, next) {
  try {
    const authState = await authenticateRequest(req);

    if (authState.role !== "admin") {
      throw createHttpError(403, "Admin access required");
    }

    req.auth = authState;
    next();
  } catch (error) {
    next(
      error.status
        ? error
        : createHttpError(401, error.message || "Invalid authorization token")
    );
  }
}

async function allowBootstrapOrAdminAccess(req, res, next) {
  try {
    const existingAdmins = await firestore.collection("admins").limit(1).get();

    if (existingAdmins.empty) {
      return next();
    }

    return requireAdminAccess(req, res, next);
  } catch (error) {
    next(
      error.status
        ? error
        : createHttpError(500, error.message || "Authorization failed")
    );
  }
}

module.exports = {
  attachOptionalAuth,
  requireAuthenticatedAccess,
  requireAdminAccess,
  allowBootstrapOrAdminAccess,
};
