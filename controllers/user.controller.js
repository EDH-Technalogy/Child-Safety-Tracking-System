const crypto = require("crypto");
const { admin, firestore, realtimeDB } = require("../firebase");
const { createAuthToken, verifyAuthToken } = require("../utils/auth-token");
const {
  findFallbackAdminByCredentials,
  isFirestoreQuotaError,
  toSafeAdmin,
} = require("../utils/local-auth-fallback");
const {
  safeWriteAuditLog,
  inferSource,
  buildPerformedByFromRequest,
} = require("../utils/audit-log");

const VALID_USER_ROLES = new Set(["admin", "user"]);
const PASSWORD_HASH_PREFIX = "pbkdf2_sha256";
const PASSWORD_HASH_ITERATIONS = 120000;
const PASSWORD_HASH_KEY_LENGTH = 32;
const PASSWORD_HASH_DIGEST = "sha256";

function createHttpError(status, message) {
  const error = new Error(message);
  error.status = status;
  return error;
}

function normalizeStoredRole(role) {
  const normalizedRole = role ? role.toString().trim().toLowerCase() : "";
  return VALID_USER_ROLES.has(normalizedRole) ? normalizedRole : "user";
}

function hashPassword(password) {
  const normalizedPassword = password?.toString() || "";
  const salt = crypto.randomBytes(16).toString("hex");
  const hash = crypto
    .pbkdf2Sync(
      normalizedPassword,
      salt,
      PASSWORD_HASH_ITERATIONS,
      PASSWORD_HASH_KEY_LENGTH,
      PASSWORD_HASH_DIGEST
    )
    .toString("hex");

  return `${PASSWORD_HASH_PREFIX}$${PASSWORD_HASH_ITERATIONS}$${salt}$${hash}`;
}

function timingSafeStringEquals(left, right) {
  const leftBuffer = Buffer.from(left || "");
  const rightBuffer = Buffer.from(right || "");

  return (
    leftBuffer.length === rightBuffer.length &&
    crypto.timingSafeEqual(leftBuffer, rightBuffer)
  );
}

function verifyPassword(password, storedPasswordValue) {
  const normalizedPassword = password?.toString() || "";
  const storedValue = storedPasswordValue?.toString() || "";

  if (!normalizedPassword || !storedValue) {
    return false;
  }

  const parts = storedValue.split("$");
  if (parts.length === 4 && parts[0] === PASSWORD_HASH_PREFIX) {
    const iterations = Number(parts[1]);
    const salt = parts[2];
    const expectedHash = parts[3];

    if (!Number.isFinite(iterations) || !salt || !expectedHash) {
      return false;
    }

    const actualHash = crypto
      .pbkdf2Sync(
        normalizedPassword,
        salt,
        iterations,
        PASSWORD_HASH_KEY_LENGTH,
        PASSWORD_HASH_DIGEST
      )
      .toString("hex");

    return timingSafeStringEquals(actualHash, expectedHash);
  }

  // Backward compatibility for existing plaintext user records.
  return timingSafeStringEquals(normalizedPassword, storedValue);
}

function verifyUserPassword(password, userData = {}) {
  return (
    verifyPassword(password, userData.password_hash) ||
    verifyPassword(password, userData.password)
  );
}

async function logUserAudit(entry) {
  return safeWriteAuditLog(entry);
}

function buildUserResponse(userId, userData = {}) {
  return {
    id: userId,
    name: userData.name || "",
    phone: userData.phone || "",
    email: userData.email || "",
    photo: userData.photo || "",
    role: normalizeStoredRole(userData.role),
    status: userData.status || "active",
    created_at: normalizeTimestampValue(userData.created_at, Date.now()),
  };
}

function buildAdminLoginResponse(adminId, adminData = {}) {
  return {
    id: adminId,
    name: adminData.name || "",
    phone: adminData.phone || "",
    email: adminData.email || "",
    photo: adminData.photo || "",
    role: "admin",
    status: adminData.status || "active",
    created_at: normalizeTimestampValue(adminData.created_at, Date.now()),
  };
}

function buildFallbackAdminLoginPayload(admin) {
  return {
    success: true,
    message: "Login successful",
    user: buildAdminLoginResponse(admin.id, admin),
    token: createAuthToken({
      subjectId: admin.id,
      role: "admin",
      subjectType: "admin",
      email: admin.email,
    }),
    auth_provider: "local_auth_fallback",
  };
}

function tryFallbackAdminLogin(req, res, reason) {
  const admin = toSafeAdmin(
    findFallbackAdminByCredentials(req.body?.email, req.body?.password)
  );

  if (!admin) {
    return false;
  }

  console.warn("[user.login.fallback-admin]", {
    email: admin.email,
    reason,
  });

  res.json(buildFallbackAdminLoginPayload(admin));
  return true;
}

function normalizeTimestampValue(value, fallback = 0) {
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

function ensureCanManageUserRecord(req, targetUserId) {
  if (!req.auth) {
    throw createHttpError(401, "Authorization token is required");
  }

  if (req.auth.role === "admin") {
    return;
  }

  if (req.auth.type === "user" && req.auth.id === targetUserId) {
    return;
  }

  throw createHttpError(403, "You do not have permission to access this user");
}

exports.getFirebaseToken = async (req, res, next) => {
  try {
    if (!req.auth?.id) {
      throw createHttpError(401, "Authorization token is required");
    }

    const role = req.auth.role === "admin" ? "admin" : "user";
    const firebaseToken = await admin.auth().createCustomToken(req.auth.id, {
      role,
      type: req.auth.type || role,
      email: req.auth.email || "",
    });

    res.json({
      token: firebaseToken,
      uid: req.auth.id,
      role,
    });
  } catch (error) {
    next(error);
  }
};

// REGISTER
exports.register = async (req, res) => {
  try {
    const { name, phone, email, password } = req.body;

    if (!name || !phone || !email || !password) {
      return res.status(400).json({ error: "Name, phone, email, and password are required" });
    }

    // Check if email already exists
    const existingUser = await firestore.collection("users")
      .where("email", "==", email)
      .get();

    if (!existingUser.empty) {
      await logUserAudit({
        eventType: "user_created",
        entityType: "user",
        entityId: null,
        title: "User registration failed",
        description: `Registration failed for ${email}.`,
        performedBy: {
          email: email || null,
          role: "user",
          type: "user",
        },
        target: {
          email: email || null,
          name: name || null,
        },
        status: "failed",
        result: "failed",
        source: inferSource(req, "mobile_app"),
        metadata: {
          reason: "email_already_registered",
        },
      });
      return res.status(400).json({ error: "Email already registered" });
    }

    const createdAt = Date.now();
    const storedUser = {
      name,
      phone,
      email,
      password_hash: hashPassword(password),
      role: "user",
      status: "active",
      created_at: createdAt,
    };

    const user = await firestore.collection("users").add(storedUser);
    const userResponse = buildUserResponse(user.id, storedUser);
    const token = createAuthToken({
      subjectId: user.id,
      role: userResponse.role,
      subjectType: "user",
      email: userResponse.email,
    });

    await logUserAudit({
      eventType: "user_created",
      entityType: "user",
      entityId: user.id,
      title: "User registered",
      description: `${name} registered a new account.`,
      performedBy: {
        id: user.id,
        name: name || null,
        email: email || null,
        role: "user",
        type: "user",
      },
      target: {
        id: user.id,
        name: name || null,
        email: email || null,
        role: "user",
      },
      status: "success",
      result: "success",
      source: inferSource(req, "mobile_app"),
      metadata: {
        newValues: {
          name,
          phone,
          email,
          role: "user",
          status: "active",
        },
      },
    });

    res.status(201).json({
      success: true,
      message: "User created successfully",
      user: userResponse,
      token,
    });
  } catch (e) {
    await logUserAudit({
      eventType: "user_created",
      entityType: "user",
      entityId: null,
      title: "User registration failed",
      description: `Registration failed for ${req.body?.email || "unknown user"}.`,
      performedBy: {
        email: req.body?.email || null,
        role: "user",
        type: "user",
      },
      target: {
        email: req.body?.email || null,
        name: req.body?.name || null,
      },
      status: "failed",
      result: "failed",
      source: inferSource(req, "mobile_app"),
      metadata: {
        reason: e.message,
      },
    });
    res.status(500).json({ error: e.message });
  }
};

// LOGIN
exports.login = async (req, res) => {
  try {
    const { email, password } = req.body;

    if (!email || !password) {
      return res.status(400).json({ error: "Email and password are required" });
    }

    const snap = await firestore
      .collection("users")
      .where("email", "==", email)
      .limit(2)
      .get();

    const matchingUserDoc = snap.docs.find((doc) =>
      verifyUserPassword(password, doc.data())
    );

    if (matchingUserDoc) {
      const userData = matchingUserDoc.data();
      const role = normalizeStoredRole(userData.role);

      if (userData.status === "blocked") {
        return res.status(403).json({ error: "Account is blocked" });
      }

      const userResponse = buildUserResponse(matchingUserDoc.id, userData);
      const token = createAuthToken({
        subjectId: matchingUserDoc.id,
        role,
        subjectType: "user",
        email: userData.email,
      });

      if (!userData.password_hash || !userData.password_hash.startsWith(PASSWORD_HASH_PREFIX)) {
        await matchingUserDoc.ref.update({
          password_hash: hashPassword(password),
          password: admin.firestore.FieldValue.delete(),
          updated_at: Date.now(),
        });
      }

      res.json({
        success: true,
        message: "Login successful",
        user: userResponse,
        token,
      });

      if (role === "admin") {
        await logUserAudit({
          eventType: "admin_login",
          entityType: "auth",
          entityId: matchingUserDoc.id,
          title: "Admin login successful",
          description: `${userData.name || userData.email} signed in as admin.`,
          performedBy: {
            id: matchingUserDoc.id,
            name: userData.name || null,
            email: userData.email || null,
            role,
            type: "user",
          },
          target: {
            id: matchingUserDoc.id,
            name: userData.name || null,
            email: userData.email || null,
          },
          status: "success",
          result: "success",
          source: inferSource(req, "mobile_app"),
          metadata: {
            authProvider: "users_collection",
          },
        });
      }

      return;
    }

    const adminSnap = await firestore
      .collection("admins")
      .where("email", "==", email)
      .where("password", "==", password)
      .get();

    if (adminSnap.empty) {
      return res.status(401).json({ error: "Invalid credentials" });
    }

    const adminData = adminSnap.docs[0].data();
    if (adminData.status !== "active") {
      return res.status(403).json({ error: "Admin account is not active" });
    }

    const adminResponse = buildAdminLoginResponse(adminSnap.docs[0].id, adminData);
    const adminToken = createAuthToken({
      subjectId: adminSnap.docs[0].id,
      role: "admin",
      subjectType: "admin",
      email: adminData.email,
    });

    res.json({
      success: true,
      message: "Login successful",
      user: adminResponse,
      token: adminToken,
    });

    await logUserAudit({
      eventType: "admin_login",
      entityType: "auth",
      entityId: adminSnap.docs[0].id,
      title: "Admin login successful",
      description: `${adminData.name || adminData.email} signed in as admin.`,
      performedBy: {
        id: adminSnap.docs[0].id,
        name: adminData.name || null,
        email: adminData.email || null,
        role: "admin",
        type: "admin",
      },
      target: {
        id: adminSnap.docs[0].id,
        name: adminData.name || null,
        email: adminData.email || null,
      },
      status: "success",
      result: "success",
      source: inferSource(req, "mobile_app"),
      metadata: {
        authProvider: "admins_collection_via_user_login",
      },
    });
  } catch (e) {
    if (isFirestoreQuotaError(e) && tryFallbackAdminLogin(req, res, e.message)) {
      return;
    }

    console.error('LOGIN ERROR:', e);
    res.status(500).json({ error: e.message });
  }
};

// LOGOUT
exports.logout = async (req, res) => {
  try {
    const authorization = req.headers.authorization || "";
    if (authorization.startsWith("Bearer ")) {
      try {
        const payload = verifyAuthToken(
          authorization.slice("Bearer ".length).trim()
        );

        if (payload.role === "admin") {
          const performedBy =
            req.auth ||
            {
              id: payload.sub || null,
              email: payload.email || null,
              role: payload.role || "admin",
              type: payload.type || "user",
            };

          await logUserAudit({
            eventType: "admin_logout",
            entityType: "auth",
            entityId: payload.sub || null,
            title: "Admin logout",
            description: `${performedBy.name || performedBy.email || "Admin"} logged out.`,
            performedBy: buildPerformedByFromRequest({ auth: performedBy }, performedBy),
            target: {
              id: payload.sub || null,
              email: payload.email || null,
            },
            status: "success",
            result: "success",
            source: inferSource(req, "mobile_app"),
            metadata: {
              authProvider: payload.type || "user",
            },
          });
        }
      } catch (_) {
        // Ignore invalid token during logout.
      }
    }

    res.json({ message: "Logged out successfully" });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
};

// DELETE USER
exports.deleteUser = async (req, res) => {
  try {
    ensureCanManageUserRecord(req, req.params.id);

    const userRef = firestore.collection("users").doc(req.params.id);
    const userDoc = await userRef.get();

    if (!userDoc.exists) {
      throw createHttpError(404, "User not found");
    }

    await userRef.delete();
    res.json({ message: "User deleted successfully" });
  } catch (e) {
    res.status(e.status || 500).json({ error: e.message });
  }
};

// REQUEST PASSWORD RESET (Generate OTP)
exports.requestPasswordReset = async (req, res) => {
  try {
    const { email } = req.body;

    const snap = await firestore.collection("users")
      .where("email", "==", email)
      .get();

    if (snap.empty) {
      return res.status(404).json({ error: "Email not found" });
    }

    // Generate 6-digit OTP
    const otp = Math.floor(100000 + Math.random() * 900000).toString();
    const otpExpiry = Date.now() + 10 * 60 * 1000; // 10 minutes

    await firestore.collection("password_resets").doc(email).set({
      email,
      otp,
      otpExpiry,
      created_at: Date.now()
    });

    // In production, send OTP via SMS/email - not in response!
    res.json({ message: "OTP sent successfully", otp: otp });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
};

// VERIFY OTP AND RESET PASSWORD
exports.verifyOtpAndResetPassword = async (req, res) => {
  try {
    const { email, otp, newPassword } = req.body;

    const doc = await firestore.collection("password_resets").doc(email).get();

    if (!doc.exists) {
      return res.status(400).json({ error: "Invalid request" });
    }

    const data = doc.data();

    if (Date.now() > data.otpExpiry) {
      return res.status(400).json({ error: "OTP expired" });
    }

    if (data.otp !== otp) {
      return res.status(400).json({ error: "Invalid OTP" });
    }

    const userSnap = await firestore.collection("users")
      .where("email", "==", email)
      .get();

    if (userSnap.empty) {
      return res.status(404).json({ error: "User not found" });
    }

    await firestore.collection("users").doc(userSnap.docs[0].id).update({
      password_hash: hashPassword(newPassword),
      password: admin.firestore.FieldValue.delete(),
      updated_at: Date.now(),
    });

    await firestore.collection("password_resets").doc(email).delete();

    res.json({ message: "Password reset successfully" });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
};

// BLOCK USER
exports.blockUser = async (req, res) => {
  try {
    await firestore.collection("users").doc(req.params.id)
      .update({ status: "blocked" });
    res.json({ message: "User blocked successfully" });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
};

// UNBLOCK USER
exports.unblockUser = async (req, res) => {
  try {
    await firestore.collection("users").doc(req.params.id)
      .update({ status: "active" });
    res.json({ message: "User unblocked successfully" });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
};

// GET USER PROFILE
exports.getProfile = async (req, res) => {
  try {
    ensureCanManageUserRecord(req, req.params.id);

    const doc = await firestore.collection("users").doc(req.params.id).get();
    
    if (!doc.exists) {
      return res.status(404).json({ error: "User not found" });
    }

    const userData = doc.data();
    res.json(buildUserResponse(doc.id, userData));
  } catch (e) {
    res.status(e.status || 500).json({ error: e.message });
  }
};

// CHANGE CURRENT USER PASSWORD
exports.changePassword = async (req, res) => {
  try {
    ensureCanManageUserRecord(req, req.params.id);

    const currentPassword =
      req.body.current_password ??
      req.body.currentPassword ??
      req.body.old_password ??
      req.body.oldPassword;
    const newPassword = req.body.new_password ?? req.body.newPassword;
    const confirmPassword =
      req.body.confirm_password ?? req.body.confirmPassword ?? newPassword;

    console.info("[user.changePassword] request", {
      actorId: req.auth?.id || null,
      actorRole: req.auth?.role || null,
      targetUserId: req.params.id,
      hasCurrentPassword: Boolean(currentPassword),
      hasNewPassword: Boolean(newPassword),
      hasConfirmPassword: Boolean(confirmPassword),
    });

    if (!currentPassword || !newPassword || !confirmPassword) {
      throw createHttpError(
        400,
        "currentPassword, newPassword, and confirmPassword are required"
      );
    }

    if (newPassword.toString().length < 6) {
      throw createHttpError(
        400,
        "New password must be at least 6 characters"
      );
    }

    if (newPassword.toString() !== confirmPassword.toString()) {
      throw createHttpError(400, "Passwords do not match");
    }

    const userRef = firestore.collection("users").doc(req.params.id);
    const userDoc = await userRef.get();

    if (!userDoc.exists) {
      throw createHttpError(404, "User not found");
    }

    const userData = userDoc.data();
    if (!verifyUserPassword(currentPassword, userData)) {
      console.warn("[user.changePassword] current password rejected", {
        actorId: req.auth?.id || null,
        targetUserId: req.params.id,
      });
      throw createHttpError(401, "Current password is incorrect");
    }

    await userRef.update({
      password_hash: hashPassword(newPassword),
      password: admin.firestore.FieldValue.delete(),
      updated_at: Date.now(),
    });

    console.info("[user.changePassword] success", {
      actorId: req.auth?.id || null,
      targetUserId: req.params.id,
    });

    res.json({ message: "Password changed successfully" });
  } catch (e) {
    console.warn("[user.changePassword] failed", {
      actorId: req.auth?.id || null,
      targetUserId: req.params.id,
      status: e.status || 500,
      reason: e.message,
    });
    res.status(e.status || 500).json({ error: e.message });
  }
};

// TEST USER CREATION - Temporary endpoint
exports.createTestUser = async (req, res) => {
  try {
    const testUser = {
      name: "Test User",
      phone: "+1234567890", 
      email: "test@example.com",
      password: "password123",
      status: "active",
      created_at: Date.now()
    };

    // Check if exists
    const existing = await firestore.collection("users")
      .where("email", "==", testUser.email).get();
    
    if (!existing.empty) {
      return res.status(400).json({ error: "Test user already exists" });
    }

    const userRef = await firestore.collection("users").add(testUser);
    console.log("Test user created:", userRef.id);
    
    res.json({ id: userRef.id, message: "Test user created successfully", user: testUser });
  } catch (e) {
    console.error("Test user creation failed:", e);
    res.status(500).json({ error: e.message });
  }
};

// UPDATE USER PROFILE
exports.updateProfile = async (req, res) => {
  try {
    ensureCanManageUserRecord(req, req.params.id);

    const userRef = firestore.collection("users").doc(req.params.id);
    const userDoc = await userRef.get();

    if (!userDoc.exists) {
      throw createHttpError(404, "User not found");
    }

    const currentUserData = userDoc.data();
    const updates = {};

    if (req.body.name !== undefined) {
      const name = req.body.name.toString().trim();
      if (!name) {
        throw createHttpError(400, "name is required");
      }
      updates.name = name;
    }

    if (req.body.phone !== undefined) {
      updates.phone = req.body.phone.toString().trim();
    }

    if (req.body.email !== undefined) {
      const email = req.body.email.toString().trim();
      if (!email) {
        throw createHttpError(400, "email is required");
      }

      const existingUser = await firestore
        .collection("users")
        .where("email", "==", email)
        .get();

      const duplicateExists = existingUser.docs.some(
        (doc) => doc.id !== req.params.id
      );

      if (duplicateExists) {
        throw createHttpError(400, "User with this email already exists");
      }

      updates.email = email;
    }

    if (req.body.photo !== undefined) {
      updates.photo = req.body.photo ? req.body.photo.toString().trim() : "";
    }

    if (Object.keys(updates).length === 0) {
      throw createHttpError(400, "No profile fields provided to update");
    }

    updates.updated_at = Date.now();

    console.info("[user.updateProfile] request", {
      actorId: req.auth?.id || null,
      actorRole: req.auth?.role || null,
      targetUserId: req.params.id,
      fields: Object.keys(updates),
      hasPhoto: req.body.photo !== undefined,
    });

    await userRef.update(updates);

    const nextUserData = {
      ...currentUserData,
      ...updates,
    };

    res.json(buildUserResponse(req.params.id, nextUserData));
  } catch (e) {
    res.status(e.status || 500).json({ error: e.message });
  }
};
