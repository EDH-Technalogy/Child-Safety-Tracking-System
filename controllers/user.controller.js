const { firestore, realtimeDB } = require("../firebase");
const { createAuthToken, verifyAuthToken } = require("../utils/auth-token");
const {
  safeWriteAuditLog,
  inferSource,
  buildPerformedByFromRequest,
} = require("../utils/audit-log");

const VALID_USER_ROLES = new Set(["admin", "user"]);

function createHttpError(status, message) {
  const error = new Error(message);
  error.status = status;
  return error;
}

function normalizeStoredRole(role) {
  const normalizedRole = role ? role.toString().trim().toLowerCase() : "";
  return VALID_USER_ROLES.has(normalizedRole) ? normalizedRole : "user";
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
    created_at: userData.created_at || Date.now(),
  };
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
      password,
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

    // First try with 'password' field (new format)
    let snap = await firestore.collection("users")
      .where("email", "==", email)
      .where("password", "==", password)
      .get();

    // If not found, try with 'password_hash' field (old format for backwards compatibility)
    if (snap.empty) {
      snap = await firestore.collection("users")
        .where("email", "==", email)
        .where("password_hash", "==", password)
        .get();
    }

    if (snap.empty) {
      return res.status(401).json({ error: "Invalid credentials" });
    }

    const userData = snap.docs[0].data();
    const role = normalizeStoredRole(userData.role);
    
    // Check if user is blocked
    if (userData.status === "blocked") {
      return res.status(403).json({ error: "Account is blocked" });
    }

    const userResponse = buildUserResponse(snap.docs[0].id, userData);
    const token = createAuthToken({
        subjectId: snap.docs[0].id,
        role,
        subjectType: "user",
        email: userData.email,
      });

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
        entityId: snap.docs[0].id,
        title: "Admin login successful",
        description: `${userData.name || userData.email} signed in as admin.`,
        performedBy: {
          id: snap.docs[0].id,
          name: userData.name || null,
          email: userData.email || null,
          role,
          type: "user",
        },
        target: {
          id: snap.docs[0].id,
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
  } catch (e) {
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
    await firestore.collection("users").doc(req.params.id).delete();
    res.json({ message: "User deleted successfully" });
  } catch (e) {
    res.status(500).json({ error: e.message });
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
      password: newPassword
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
