const { firestore, realtimeDB } = require("../firebase");
const { syncRealtimeState } = require("../utils/realtime-sync");
const { createAuthToken } = require("../utils/auth-token");
const {
  findFallbackAdminByCredentials,
  isFirestoreQuotaError,
  toSafeAdmin,
} = require("../utils/local-auth-fallback");
const {
  safeWriteAuditLog,
  buildPerformedByFromRequest,
  inferSource,
  extractChangedFields,
  mapLegacyActivityLog,
  normalizeAuditLogRecord,
} = require("../utils/audit-log");
const {
  getResolvedLiveTrackingSnapshot,
} = require("../utils/live-tracking");
const {
  getDailyLocationIndexStats,
} = require("../utils/location-history");

const VALID_USER_ROLES = new Set(["admin", "user"]);

function createHttpError(status, message) {
  const error = new Error(message);
  error.status = status;
  return error;
}

function normalizeUserRole(role, defaultRole = "user") {
  if (role === undefined || role === null || role === "") {
    return defaultRole;
  }

  const normalizedRole = role.toString().trim().toLowerCase();
  if (!VALID_USER_ROLES.has(normalizedRole)) {
    throw createHttpError(400, "role must be one of: admin, user");
  }

  return normalizedRole;
}

function buildUserTarget(userId, userData = {}) {
  return {
    id: userId || null,
    name: userData.name || null,
    email: userData.email || null,
    role:
      userData.role && userData.role.toString().trim().toLowerCase() === "admin"
        ? "admin"
        : "user",
    status: userData.status || null,
  };
}

function buildAdminResponse(adminId, adminData = {}) {
  return {
    id: adminId,
    name: adminData.name || "",
    email: adminData.email || "",
    phone: adminData.phone || "",
    username: adminData.username || "",
    photo: adminData.photo || "",
    role: adminData.role || "admin",
    status: adminData.status || "active",
    created_at: normalizeTimestampValue(adminData.created_at, 0),
    updated_at: normalizeTimestampValue(adminData.updated_at, null),
  };
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

async function countRealtimeOnlineDevices() {
  const devicesSnap = await firestore.collection("devices").get();
  const statuses = await Promise.all(
    devicesSnap.docs.map(async (deviceDoc) => {
      const childId = deviceDoc.data()?.child_id?.toString().trim() || "";
      if (!childId) {
        return false;
      }

      try {
        const liveSnapshot = await getResolvedLiveTrackingSnapshot(childId);
        return liveSnapshot?.latestStatus === "online";
      } catch (error) {
        console.warn("[admin.countRealtimeOnlineDevices] skipped", {
          deviceId: deviceDoc.id,
          childId,
          reason: error.message,
        });
        return false;
      }
    })
  );
  const activeDevices = statuses.filter(Boolean).length;

  return {
    activeDevices,
    totalDevices: devicesSnap.size,
  };
}

async function logAdminAudit(req, entry) {
  return safeWriteAuditLog({
    source: inferSource(req, "admin_panel"),
    performedBy: buildPerformedByFromRequest(req),
    ...entry,
  });
}

async function logAdminFailure(req, entry, error) {
  return logAdminAudit(req, {
    status: "failed",
    result: "failed",
    metadata: {
      ...(entry.metadata || {}),
      error: error?.message || String(error),
    },
    ...entry,
  });
}

async function getUserOrThrow(userId) {
  const userRef = firestore.collection("users").doc(userId);
  const userDoc = await userRef.get();

  if (!userDoc.exists) {
    throw createHttpError(404, "User not found");
  }

  return { userRef, userDoc };
}

async function getAdminOrThrow(adminId) {
  const adminRef = firestore.collection("admins").doc(adminId);
  const adminDoc = await adminRef.get();

  if (!adminDoc.exists) {
    throw createHttpError(404, "Admin not found");
  }

  return { adminRef, adminDoc };
}

async function getCurrentAdminSubjectOrThrow(authState) {
  if (authState?.source === "local_auth_fallback") {
    const fallbackAdmin = {
      id: authState.id,
      name: authState.name || "Admin",
      email: authState.email || "",
      phone: authState.phone || "",
      photo: authState.photo || "",
      role: "admin",
      status: "active",
      created_at: Date.now(),
    };

    return {
      subjectRef: null,
      subjectDoc: {
        id: fallbackAdmin.id,
        data: () => fallbackAdmin,
      },
      collectionName: "local_auth_fallback",
      entityType: "admin",
    };
  }

  if (authState?.type === "admin") {
    const { adminRef, adminDoc } = await getAdminOrThrow(authState.id);
    return {
      subjectRef: adminRef,
      subjectDoc: adminDoc,
      collectionName: "admins",
      entityType: "admin",
    };
  }

  const { userRef, userDoc } = await getUserOrThrow(authState?.id);
  const userData = userDoc.data();

  if (normalizeUserRole(userData.role, "user") !== "admin") {
    throw createHttpError(403, "Admin access required");
  }

  return {
    subjectRef: userRef,
    subjectDoc: userDoc,
    collectionName: "users",
    entityType: "user",
  };
}

function buildFallbackAdminLoginPayload(admin) {
  return {
    ...buildAdminResponse(admin.id, admin),
    token: createAuthToken({
      subjectId: admin.id,
      role: "admin",
      subjectType: "admin",
      email: admin.email,
    }),
    message: "Admin login successful",
    auth_provider: "local_auth_fallback",
  };
}

async function tryFallbackAdminLogin(req, res, reason) {
  const admin = toSafeAdmin(
    findFallbackAdminByCredentials(req.body?.email, req.body?.password)
  );

  if (!admin) {
    return false;
  }

  console.warn("[admin.login.fallback]", {
    email: admin.email,
    reason,
  });

  res.json(buildFallbackAdminLoginPayload(admin));
  return true;
}

async function syncUserAccessState(userId, shouldBlock) {
  const childSnap = await firestore
    .collection("children")
    .where("user_id", "==", userId)
    .get();

  const childUpdates = [];
  const deviceUpdates = [];
  const realtimeUpdates = [];
  const updatedAt = Date.now();

  for (const childDoc of childSnap.docs) {
    const childData = childDoc.data();
    const childPayload = {
      updated_at: updatedAt,
    };
    let nextChildStatus = childData.status || "active";
    let shouldSyncChild = false;

    if (shouldBlock) {
      childPayload.status = "blocked";
      childPayload.blocked_by_user = true;
      nextChildStatus = "blocked";
      shouldSyncChild = true;
    } else if (childData.blocked_by_user === true) {
      childPayload.status = "active";
      childPayload.blocked_by_user = false;
      nextChildStatus = "active";
      shouldSyncChild = true;
    }

    if (shouldSyncChild) {
      childUpdates.push(childDoc.ref.update(childPayload));
    }

    const deviceSnap = await firestore
      .collection("devices")
      .where("child_id", "==", childDoc.id)
      .get();
    let shouldSyncDevice = shouldBlock;

    deviceSnap.forEach((deviceDoc) => {
      const deviceData = deviceDoc.data();
      if (!shouldBlock && deviceData.disabled_by_user_block !== true) {
        return;
      }

      const devicePayload = {
        status: "offline",
        updated_at: updatedAt,
      };

      if (shouldBlock) {
        devicePayload.disabled_by_user_block = true;
      } else if (deviceData.disabled_by_user_block === true) {
        devicePayload.disabled_by_user_block = false;
      }

      shouldSyncDevice = true;
      deviceUpdates.push(deviceDoc.ref.update(devicePayload));
    });

    if (shouldSyncChild || shouldSyncDevice) {
      realtimeUpdates.push(
        syncRealtimeState(childDoc.id, {
          childStatus: nextChildStatus,
          deviceStatus: "offline",
          disabled: shouldBlock,
          blocked: nextChildStatus === "blocked",
          reason: shouldBlock ? "user_blocked" : "user_unblocked",
        })
      );
    }
  }

  await Promise.all([...childUpdates, ...deviceUpdates, ...realtimeUpdates]);
}

// ==================== ADMIN AUTHENTICATION ====================

// Admin Login
exports.adminLogin = async (req, res) => {
  try {
    const { email, password } = req.body;

    if (!email || !password) {
      await safeWriteAuditLog({
        eventType: "admin_login",
        entityType: "auth",
        entityId: null,
        title: "Admin login failed",
        description: "Admin login failed because email or password was missing.",
        performedBy: {
          email: email || null,
          role: "admin",
          type: "admin",
        },
        target: {
          email: email || null,
        },
        status: "failed",
        result: "failed",
        source: inferSource(req, "admin_panel"),
        metadata: {
          reason: "missing_credentials",
        },
      });
      return res.status(400).json({ error: "Email and password are required" });
    }

    // Check in admins collection
    const adminsSnapshot = await firestore
      .collection("admins")
      .where("email", "==", email)
      .where("password", "==", password)
      .where("status", "==", "active")
      .get();

    if (adminsSnapshot.empty) {
      await safeWriteAuditLog({
        eventType: "admin_login",
        entityType: "auth",
        entityId: null,
        title: "Admin login failed",
        description: `Admin login failed for ${email}.`,
        performedBy: {
          email,
          role: "admin",
          type: "admin",
        },
        target: {
          email,
        },
        status: "failed",
        result: "failed",
        source: inferSource(req, "admin_panel"),
        metadata: {
          reason: "invalid_credentials",
        },
      });
      return res.status(401).json({ error: "Invalid admin credentials" });
    }

    const adminData = adminsSnapshot.docs[0].data();
    const role = adminData.role || "admin";
    
    // Return admin info (excluding password)
    res.json({
      ...buildAdminResponse(adminsSnapshot.docs[0].id, adminData),
      token: createAuthToken({
        subjectId: adminsSnapshot.docs[0].id,
        role,
        subjectType: "admin",
        email: adminData.email,
      }),
      message: "Admin login successful"
    });

    await safeWriteAuditLog({
      eventType: "admin_login",
      entityType: "auth",
      entityId: adminsSnapshot.docs[0].id,
      title: "Admin login successful",
      description: `${adminData.name || adminData.email} signed in to the admin panel.`,
      performedBy: {
        id: adminsSnapshot.docs[0].id,
        name: adminData.name || null,
        email: adminData.email || email,
        role,
        type: "admin",
      },
      target: {
        id: adminsSnapshot.docs[0].id,
        name: adminData.name || null,
        email: adminData.email || email,
      },
      status: "success",
      result: "success",
      source: inferSource(req, "admin_panel"),
      metadata: {
        authProvider: "admins_collection",
      },
    });
  } catch (error) {
    if (
      isFirestoreQuotaError(error) &&
      (await tryFallbackAdminLogin(req, res, error.message))
    ) {
      return;
    }

    await safeWriteAuditLog({
      eventType: "admin_login",
      entityType: "auth",
      entityId: null,
      title: "Admin login failed",
      description: `Admin login failed for ${req.body?.email || "unknown user"}.`,
      performedBy: {
        email: req.body?.email || null,
        role: "admin",
        type: "admin",
      },
      target: {
        email: req.body?.email || null,
      },
      status: "failed",
      result: "failed",
      source: inferSource(req, "admin_panel"),
      metadata: {
        reason: error.message,
      },
    });
    res.status(500).json({ error: error.message });
  }
};

exports.adminLogout = async (req, res, next) => {
  try {
    await logAdminAudit(req, {
      eventType: "admin_logout",
      entityType: "auth",
      entityId: req.auth?.id || null,
      title: "Admin logout",
      description: `${req.auth?.name || req.auth?.email || "Admin"} logged out.`,
      target: {
        id: req.auth?.id || null,
        name: req.auth?.name || null,
        email: req.auth?.email || null,
      },
      status: "success",
      result: "success",
      metadata: {
        authProvider: req.auth?.type || "admin",
      },
    });

    res.json({ message: "Admin logged out successfully" });
  } catch (error) {
    next(error);
  }
};

exports.getAdminProfile = async (req, res, next) => {
  try {
    if (req.auth?.source === "local_auth_fallback") {
      return res.json(
        buildAdminResponse(req.auth.id, {
          name: req.auth.name || "Admin",
          email: req.auth.email || "",
          phone: req.auth.phone || "",
          photo: req.auth.photo || "",
          role: "admin",
          status: "active",
          created_at: Date.now(),
        })
      );
    }

    const { subjectDoc, collectionName } = await getCurrentAdminSubjectOrThrow(
      req.auth
    );

    console.info("[admin.getAdminProfile] request", {
      authId: req.auth?.id,
      authType: req.auth?.type,
      collectionName,
    });

    res.json(buildAdminResponse(subjectDoc.id, subjectDoc.data()));
  } catch (error) {
    next(error);
  }
};

exports.updateAdminProfile = async (req, res, next) => {
  try {
    const {
      subjectRef,
      subjectDoc,
      collectionName,
      entityType,
    } = await getCurrentAdminSubjectOrThrow(req.auth);
    const currentAdminData = subjectDoc.data();
    const updates = {
      updated_at: Date.now(),
    };

    if (req.body.name !== undefined) {
      const name = req.body.name.toString().trim();
      if (!name) {
        throw createHttpError(400, "name is required");
      }
      updates.name = name;
    }

    if (req.body.email !== undefined) {
      const email = req.body.email.toString().trim();
      if (!email) {
        throw createHttpError(400, "email is required");
      }

      const existingAdmin = await firestore
        .collection(collectionName)
        .where("email", "==", email)
        .get();

      const duplicateExists = existingAdmin.docs.some(
        (doc) => doc.id !== req.auth.id
      );

      if (duplicateExists) {
        throw createHttpError(400, "Admin with this email already exists");
      }

      updates.email = email;
    }

    if (req.body.phone !== undefined) {
      updates.phone = req.body.phone.toString().trim();
    }

    if (req.body.username !== undefined) {
      updates.username = req.body.username.toString().trim();
    }

    if (req.body.photo !== undefined) {
      updates.photo = req.body.photo ? req.body.photo.toString().trim() : "";
    }

    if (Object.keys(updates).length === 1) {
      throw createHttpError(400, "No admin profile fields provided to update");
    }

    console.info("[admin.updateAdminProfile] request", {
      adminId: req.auth.id,
      authType: req.auth?.type,
      collectionName,
      fields: Object.keys(updates),
    });

    await subjectRef.update(updates);

    const nextAdminData = {
      ...currentAdminData,
      ...updates,
    };

    await logAdminAudit(req, {
      eventType: "admin_profile_updated",
      entityType,
      entityId: req.auth.id,
      title: "Admin profile updated",
      description: `${nextAdminData.name || nextAdminData.email || "Admin"} updated their account profile.`,
      target: {
        id: req.auth.id,
        name: nextAdminData.name || null,
        email: nextAdminData.email || null,
        role: nextAdminData.role || "admin",
      },
      status: "success",
      result: "success",
      metadata: {
        sourceCollection: collectionName,
        oldValues: buildAdminResponse(req.auth.id, currentAdminData),
        newValues: buildAdminResponse(req.auth.id, nextAdminData),
        changedFields: extractChangedFields(currentAdminData, nextAdminData),
      },
    });

    res.json(buildAdminResponse(req.auth.id, nextAdminData));
  } catch (error) {
    next(error);
  }
};

// Create Admin (for initial setup)
exports.createAdmin = async (req, res) => {
  try {
    const { name, email, password, role } = req.body;

    if (!name || !email || !password) {
      return res.status(400).json({ error: "Name, email, and password are required" });
    }

    // Check if admin already exists
    const existingAdmin = await firestore
      .collection("admins")
      .where("email", "==", email)
      .get();

    if (!existingAdmin.empty) {
      return res.status(400).json({ error: "Admin with this email already exists" });
    }

    const admin = await firestore.collection("admins").add({
      name,
      email,
      password, // In production, hash this password!
      role: role || "admin",
      status: "active",
      created_at: Date.now()
    });

    res.json({ 
      admin_id: admin.id, 
      message: "Admin created successfully"
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};

// Get All Admins
exports.getAllAdmins = async (req, res) => {
  try {
    const snap = await firestore.collection("admins").get();
    const list = [];
    snap.forEach(d => {
      const data = d.data();
      // Don't return passwords
      delete data.password;
      list.push({id: d.id, ...data});
    });
    res.json(list);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};

// Delete Admin
exports.deleteAdmin = async (req, res) => {
  try {
    await firestore.collection("admins").doc(req.params.id).delete();
    res.json({ message: "Admin deleted successfully" });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};

// Get All Users
exports.getAllUsers = async (req, res, next) => {
  try {
    const snap = await firestore.collection("users").get();
    const list = [];
    snap.forEach((d) => {
      const data = d.data();
      delete data.password;
      delete data.password_hash;
      list.push({
        id: d.id,
        ...data,
        role:
          data.role && data.role.toString().trim().toLowerCase() === "admin"
            ? "admin"
            : "user",
      });
    });
    list.sort((a, b) => (b.created_at || 0) - (a.created_at || 0));
    res.json(list);
  } catch (error) {
    next(error);
  }
};

// Block User
exports.blockUser = async (req, res, next) => {
  try {
    const { userRef, userDoc } = await getUserOrThrow(req.params.id);
    const userData = userDoc.data();
    await userRef.update({
      status: "blocked",
      updated_at: Date.now(),
    });
    await syncUserAccessState(req.params.id, true);

    await logAdminAudit(req, {
      eventType: "user_blocked",
      entityType: "user",
      entityId: req.params.id,
      title: "User blocked",
      description: `${userData.name || userData.email || "User"} was blocked.`,
      target: buildUserTarget(req.params.id, {
        ...userData,
        status: "blocked",
      }),
      status: "success",
      result: "success",
      metadata: {
        oldValues: { status: userData.status || "active" },
        newValues: { status: "blocked" },
        changedFields: ["status"],
      },
    });

    res.json({ message: "User blocked successfully" });
  } catch (error) {
    await logAdminFailure(
      req,
      {
        eventType: "user_blocked",
        entityType: "user",
        entityId: req.params.id || null,
        title: "User block failed",
        description: `Failed to block user ${req.params.id}.`,
        target: { id: req.params.id || null },
      },
      error
    );
    next(error);
  }
};

// Unblock User
exports.unblockUser = async (req, res, next) => {
  try {
    const { userRef, userDoc } = await getUserOrThrow(req.params.id);
    const userData = userDoc.data();
    await userRef.update({
      status: "active",
      updated_at: Date.now(),
    });
    await syncUserAccessState(req.params.id, false);

    await logAdminAudit(req, {
      eventType: "user_unblocked",
      entityType: "user",
      entityId: req.params.id,
      title: "User unblocked",
      description: `${userData.name || userData.email || "User"} was unblocked.`,
      target: buildUserTarget(req.params.id, {
        ...userData,
        status: "active",
      }),
      status: "success",
      result: "success",
      metadata: {
        oldValues: { status: userData.status || "blocked" },
        newValues: { status: "active" },
        changedFields: ["status"],
      },
    });

    res.json({ message: "User unblocked successfully" });
  } catch (error) {
    await logAdminFailure(
      req,
      {
        eventType: "user_unblocked",
        entityType: "user",
        entityId: req.params.id || null,
        title: "User unblock failed",
        description: `Failed to unblock user ${req.params.id}.`,
        target: { id: req.params.id || null },
      },
      error
    );
    next(error);
  }
};

// Device Deactivate
exports.deviceDeactivate = async (req,res)=>{
  await firestore.collection("devices").doc(req.params.id)
  .update({status:"offline"});
  res.json({ message: "Device disabled successfully" });
};

// Get All Devices
exports.getAllDevices = async (req,res)=>{
  const snap = await firestore.collection("devices").get();
  const list = [];
  snap.forEach(d => list.push({id: d.id, ...d.data()}));
  res.json(list);
};

// Get Total Active Users
exports.getTotalActiveUsers = async (req,res)=>{
  const snap = await firestore.collection("users")
    .where("status", "==", "active")
    .get();
  res.json({ count: snap.size });
};

// Get Total Devices
exports.getTotalDevices = async (req,res)=>{
  const snap = await firestore.collection("devices").get();
  res.json({ count: snap.size });
};

// Get Total Active Devices
exports.getActiveDevices = async (req,res)=>{
  const { activeDevices } = await countRealtimeOnlineDevices();
  res.json({ count: activeDevices });
};

// Get Daily Active Devices Report (legacy)
exports.getDailyActiveDevicesReport = async (req,res)=>{
  try {
    const { date } = req.params;
    const targetDate = date || new Date().toISOString().slice(0, 10);
    const stats = await getDailyLocationIndexStats(targetDate);

    res.json({
      date: targetDate,
      active_devices_count: stats.activeDevicesCount,
      total_location_updates: stats.totalLocationUpdates
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};

// Daily Active Devices
exports.dailyActiveDevices = async (req, res) => {
  try {
    const date = req.params.date || new Date().toISOString().slice(0, 10);
    const stats = await getDailyLocationIndexStats(date);

    res.json({
      date: date,
      active_devices_count: stats.activeDevicesCount,
      total_location_updates: stats.totalLocationUpdates
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};

// Get System Logs
exports.getSystemLogs = async (req,res)=>{
  try {
    const { limit } = req.query;
    const logLimit = parseInt(limit) || 100;

    const [auditSnap, activityLogsSnap, legacySnap] = await Promise.all([
      firestore
        .collection("audit_logs")
        .orderBy("timestamp", "desc")
        .limit(logLimit)
        .get(),
      firestore
        .collection("activity_logs")
        .orderBy("created_at", "desc")
        .limit(logLimit)
        .get(),
      firestore
        .collection("activity_log")
        .orderBy("created_at", "desc")
        .limit(logLimit)
        .get(),
    ]);

    const logs = [];
    auditSnap.forEach((doc) => {
      logs.push({
        ...normalizeAuditLogRecord(doc.id, doc.data()),
        logCollection: "audit_logs",
      });
    });
    activityLogsSnap.forEach((doc) => {
      logs.push({
        ...mapLegacyActivityLog(doc.id, doc.data()),
        logCollection: "activity_logs",
      });
    });
    legacySnap.forEach((doc) => {
      logs.push({
        ...mapLegacyActivityLog(doc.id, doc.data()),
        logCollection: "activity_log",
      });
    });

    logs.sort((a, b) => (b.timestamp || 0) - (a.timestamp || 0));
    res.json(logs.slice(0, logLimit));
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};

async function deleteCollectionDocuments(collectionName, batchSize = 400) {
  let deletedCount = 0;

  while (true) {
    const snap = await firestore.collection(collectionName).limit(batchSize).get();
    if (snap.empty) {
      return deletedCount;
    }

    const batch = firestore.batch();
    snap.docs.forEach((doc) => {
      batch.delete(doc.ref);
    });
    await batch.commit();
    deletedCount += snap.size;
  }
}

exports.deleteSystemLog = async (req, res) => {
  try {
    const requestedCollection = req.query.collection?.toString();
    const allowedCollections = ["audit_logs", "activity_logs", "activity_log"];
    const collectionsToCheck =
      requestedCollection && allowedCollections.includes(requestedCollection)
        ? [requestedCollection]
        : allowedCollections;

    console.info("[admin.deleteSystemLog] request", {
      id: req.params.id,
      requestedCollection,
      collectionsToCheck,
    });

    for (const collectionName of collectionsToCheck) {
      const logRef = firestore.collection(collectionName).doc(req.params.id);
      const logDoc = await logRef.get();

      console.info("[admin.deleteSystemLog] lookup", {
        id: req.params.id,
        collection: collectionName,
        exists: logDoc.exists,
      });

      if (!logDoc.exists) {
        continue;
      }

      await logRef.delete();
      console.info("[admin.deleteSystemLog] deleted", {
        id: req.params.id,
        collection: collectionName,
      });
      return res.json({
        message: "System log deleted successfully",
        id: req.params.id,
        collection: collectionName,
      });
    }

    throw createHttpError(404, "System log not found");
  } catch (error) {
    res.status(error.status || 500).json({ error: error.message });
  }
};

exports.deleteAllSystemLogs = async (req, res) => {
  try {
    const [deletedAuditLogs, deletedActivityLogs, deletedLegacyLogs] = await Promise.all([
      deleteCollectionDocuments("audit_logs"),
      deleteCollectionDocuments("activity_logs"),
      deleteCollectionDocuments("activity_log"),
    ]);

    console.info("[admin.deleteAllSystemLogs] deleted", {
      audit_logs: deletedAuditLogs,
      activity_logs: deletedActivityLogs,
      activity_log: deletedLegacyLogs,
      total: deletedAuditLogs + deletedActivityLogs + deletedLegacyLogs,
    });

    res.json({
      message: "All system logs deleted successfully",
      deleted: {
        audit_logs: deletedAuditLogs,
        activity_logs: deletedActivityLogs,
        activity_log: deletedLegacyLogs,
        total: deletedAuditLogs + deletedActivityLogs + deletedLegacyLogs,
      },
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};

// Get Firmware Versions
exports.getFirmwareVersions = async (req,res)=>{
  try {
    const snap = await firestore.collection("devices").get();
    
    const versions = {};
    snap.forEach(d => {
      const fw = d.data().firmware_version;
      if (fw) {
        versions[fw] = (versions[fw] || 0) + 1;
      }
    });
    
    res.json(versions);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};

// Get System Statistics
exports.getSystemStats = async (req,res)=>{
  try {
    const usersSnap = await firestore.collection("users").get();
    const activeUsersSnap = await firestore.collection("users")
      .where("status", "==", "active")
      .get();
    
    const { totalDevices, activeDevices } = await countRealtimeOnlineDevices();
    
    const childrenSnap = await firestore.collection("children").get();
    const alertsSnap = await firestore.collection("alerts").get();
    
    res.json({
      total_users: usersSnap.size,
      active_users: activeUsersSnap.size,
      total_devices: totalDevices,
      active_devices: activeDevices,
      total_children: childrenSnap.size,
      total_alerts: alertsSnap.size
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};

// ==================== CREATE USER ====================
exports.createUser = async (req, res, next) => {
  try {
    const { name, phone, email, password, photo } = req.body;
    const role = normalizeUserRole(req.body.role, "user");

    if (!name || !phone || !email || !password) {
      throw createHttpError(400, "name, phone, email, and password are required");
    }
    
    // Check if user already exists
    const existingUser = await firestore.collection("users")
      .where("email", "==", email)
      .get();
    
    if (!existingUser.empty) {
      throw createHttpError(400, "User with this email already exists");
    }
    
    const user = await firestore.collection("users").add({
      name,
      phone,
      email,
      password,
      photo: photo ? photo.toString().trim() : "",
      role,
      status: "active",
      created_at: Date.now()
    });

    await logAdminAudit(req, {
      eventType: "user_created",
      entityType: "user",
      entityId: user.id,
      title: "User created",
      description: `${name} was created as ${role}.`,
      target: buildUserTarget(user.id, {
        name,
        phone,
        email,
        role,
        status: "active",
      }),
      status: "success",
      result: "success",
      metadata: {
        newValues: {
          name,
          phone,
          email,
          photo: photo ? photo.toString().trim() : "",
          role,
          status: "active",
        },
        changedFields: ["name", "phone", "email", "photo", "role", "status"],
      },
    });
    
    res.json({ user_id: user.id, message: "User created successfully" });
  } catch (error) {
    await logAdminFailure(
      req,
      {
        eventType: "user_created",
        entityType: "user",
        entityId: null,
        title: "User creation failed",
        description: `Failed to create user ${req.body?.email || req.body?.name || ""}.`,
        target: buildUserTarget(null, req.body || {}),
      },
      error
    );
    next(error);
  }
};

// ==================== UPDATE USER ====================
exports.updateUser = async (req, res, next) => {
  try {
    const { name, phone, email } = req.body;

    const { userRef, userDoc } = await getUserOrThrow(req.params.id);
    const currentUserData = userDoc.data();
    const targetPath = userRef.path;
    const updates = {
      updated_at: Date.now(),
    };

    if (name !== undefined) updates.name = name;
    if (phone !== undefined) updates.phone = phone;
    if (email !== undefined) {
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

    if (req.body.role !== undefined) {
      console.info("[admin.updateUser] role received", {
        userId: req.params.id,
        path: targetPath,
        role: req.body.role,
      });
      updates.role = normalizeUserRole(req.body.role, "user");
    }

    if (req.body.role !== undefined) {
      console.info("[admin.updateUser] firestore update payload", {
        userId: req.params.id,
        path: targetPath,
        fields: Object.keys(updates),
        role: updates.role,
      });
    }

    if (req.body.photo !== undefined) {
      updates.photo = req.body.photo ? req.body.photo.toString().trim() : "";
      console.info("[admin.updateUser] photo received", {
        userId: req.params.id,
        hasPhoto: updates.photo.length > 0,
      });
    }

    await userRef.update(updates);

    const nextUserData = {
      ...currentUserData,
      ...updates,
    };

    if (req.body.role !== undefined) {
      console.info("[admin.updateUser] update complete", {
        userId: req.params.id,
        path: targetPath,
        role: nextUserData.role || currentUserData.role || "user",
      });
    }

    const changedFields = extractChangedFields(currentUserData, nextUserData);

    await logAdminAudit(req, {
      eventType: "user_updated",
      entityType: "user",
      entityId: req.params.id,
      title: "User updated",
      description: `${nextUserData.name || nextUserData.email || "User"} was updated.`,
      target: buildUserTarget(req.params.id, nextUserData),
      status: "success",
      result: "success",
      metadata: {
        oldValues: currentUserData,
        newValues: nextUserData,
        changedFields,
      },
    });

    if (
      updates.role !== undefined &&
      (currentUserData.role || "user") !== updates.role
    ) {
      await logAdminAudit(req, {
        eventType: "role_changed",
        entityType: "user",
        entityId: req.params.id,
        title: "User role changed",
        description: `${nextUserData.name || nextUserData.email || "User"} role changed from ${(currentUserData.role || "user")} to ${updates.role}.`,
        target: buildUserTarget(req.params.id, nextUserData),
        status: "success",
        result: "success",
        metadata: {
          oldValues: { role: currentUserData.role || "user" },
          newValues: { role: updates.role },
          changedFields: ["role"],
        },
      });
    }
    
    res.json({ message: "User updated successfully" });
  } catch (error) {
    await logAdminFailure(
      req,
      {
        eventType: "user_updated",
        entityType: "user",
        entityId: req.params.id || null,
        title: "User update failed",
        description: `Failed to update user ${req.params.id}.`,
        target: {
          id: req.params.id || null,
          email: req.body?.email || null,
          name: req.body?.name || null,
        },
      },
      error
    );
    next(error);
  }
};

// ==================== DELETE USER ====================
exports.deleteUser = async (req, res, next) => {
  try {
    const { userRef, userDoc } = await getUserOrThrow(req.params.id);
    const userData = userDoc.data();
    await userRef.delete();

    await logAdminAudit(req, {
      eventType: "user_deleted",
      entityType: "user",
      entityId: req.params.id,
      title: "User deleted",
      description: `${userData.name || userData.email || "User"} was deleted.`,
      target: buildUserTarget(req.params.id, userData),
      status: "success",
      result: "success",
      metadata: {
        oldValues: userData,
      },
    });

    res.json({ message: "User deleted successfully" });
  } catch (error) {
    await logAdminFailure(
      req,
      {
        eventType: "user_deleted",
        entityType: "user",
        entityId: req.params.id || null,
        title: "User delete failed",
        description: `Failed to delete user ${req.params.id}.`,
        target: { id: req.params.id || null },
      },
      error
    );
    next(error);
  }
};

// ==================== UPDATE DEVICE ====================
exports.updateDevice = async (req, res) => {
  try {
    const { imei, sim_number, firmware_version } = req.body;
    
    const updateData = {};
    if (imei) updateData.imei = imei;
    if (sim_number) updateData.sim_number = sim_number;
    if (firmware_version) updateData.firmware_version = firmware_version;
    updateData.updated_at = Date.now();
    
    await firestore.collection("devices").doc(req.params.id).update(updateData);
    
    res.json({ message: "Device updated successfully" });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};

// ==================== ACTIVATE DEVICE ====================
exports.deviceActivate = async (req, res) => {
  try {
    await firestore.collection("devices").doc(req.params.id)
    .update({ status: "online", updated_at: Date.now() });
    res.json({ message: "Device activated successfully" });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};

// ==================== DELETE DEVICE ====================
exports.deleteDevice = async (req, res) => {
  try {
    await firestore.collection("devices").doc(req.params.id).delete();
    res.json({ message: "Device deleted successfully" });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};

// ==================== GET ALL CHILDREN ====================
exports.getAllChildren = async (req, res) => {
  try {
    const snap = await firestore.collection("children").get();
    const list = [];
    snap.forEach(d => list.push({ id: d.id, ...d.data() }));
    res.json(list);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};

// ==================== DELETE CHILD ====================
exports.deleteChild = async (req, res) => {
  try {
    await firestore.collection("children").doc(req.params.id).delete();
    res.json({ message: "Child deleted successfully" });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};

// ==================== GET ALL ALERTS ====================
exports.getAllAlerts = async (req, res) => {
  try {
    const snap = await firestore.collection("alerts")
      .orderBy("created_at", "desc")
      .get();
    const listById = new Map();
    snap.forEach(d => listById.set(d.id, { id: d.id, ...d.data() }));

    const adminAlertsSnapshot = await realtimeDB.ref("admin_alerts").once("value");
    const adminAlerts = adminAlertsSnapshot.val() || {};
    Object.entries(adminAlerts).forEach(([id, value]) => {
      if (value && typeof value === "object" && !listById.has(id)) {
        listById.set(id, { id, ...value });
      }
    });

    const list = Array.from(listById.values()).sort(
      (a, b) => Number(b.created_at || b.timestamp || 0) -
        Number(a.created_at || a.timestamp || 0)
    );
    res.json(list);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};

// ==================== DELETE ALERT ====================
exports.deleteAlert = async (req, res) => {
  try {
    const alertId = req.params.id?.toString().trim();
    if (!alertId) {
      throw createHttpError(400, "Alert id is required");
    }

    const alertRef = firestore.collection("alerts").doc(alertId);
    const alertDoc = await alertRef.get();
    const adminAlertSnapshot = await realtimeDB
      .ref(`admin_alerts/${alertId}`)
      .once("value");

    if (!alertDoc.exists && !adminAlertSnapshot.exists()) {
      return res.json({ message: "Alert already deleted" });
    }

    const alertData = alertDoc.exists
      ? alertDoc.data()
      : adminAlertSnapshot.val() || {};
    if (alertDoc.exists) {
      await alertRef.delete();
    }
    const realtimeAlertUpdates = {
      [`admin_alerts/${alertId}`]: null,
    };
    if (alertData.user_id) {
      realtimeAlertUpdates[`alerts/${alertData.user_id}/${alertId}`] = null;
    }
    if (alertData.child_id) {
      realtimeAlertUpdates[
        `alerts_by_child/${alertData.child_id}/${alertId}`
      ] = null;
      realtimeAlertUpdates[`alerts_live/${alertData.child_id}/${alertId}`] =
        null;
    }
    await realtimeDB.ref().update(realtimeAlertUpdates);

    await logAdminAudit(req, {
      eventType: "alert_resolved",
      entityType: "alert",
      entityId: alertId,
      title: "Alert resolved",
      description: `Alert ${alertData.type || "alert"} was resolved and removed.`,
      target: {
        id: alertId,
        child_id: alertData.child_id || null,
        type: alertData.type || null,
      },
      status: "success",
      result: "success",
      metadata: {
        oldValues: alertData,
      },
    });

    res.json({ message: "Alert deleted successfully" });
  } catch (error) {
    await logAdminFailure(
      req,
      {
        eventType: "alert_resolved",
        entityType: "alert",
        entityId: req.params.id || null,
        title: "Alert resolve failed",
        description: `Failed to resolve alert ${req.params.id}.`,
        target: { id: req.params.id || null },
      },
      error
    );
    res.status(500).json({ error: error.message });
  }
};
