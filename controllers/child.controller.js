const { firestore } = require("../firebase");
const {
  syncRealtimeState,
  removeRealtimeState,
} = require("../utils/realtime-sync");
const {
  safeWriteAuditLog,
  buildPerformedByFromRequest,
  inferSource,
  extractChangedFields,
} = require("../utils/audit-log");
const { getResolvedLiveTrackingSnapshot } = require("../utils/live-tracking");

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

  throw createHttpError(403, "You do not have permission to manage this child");
}

function ensureCanAccessChildRecord(req, childData = {}) {
  const ownerUserId = childData.user_id?.toString() || "";
  if (!ownerUserId) {
    throw createHttpError(400, "Child record is missing user_id");
  }

  ensureCanManageUserChildren(req, ownerUserId);
}

function buildChildTarget(childId, childData = {}) {
  return {
    id: childId || null,
    name: childData.name || null,
    user_id: childData.user_id || null,
    age: childData.age ?? null,
    status: childData.status || null,
  };
}

async function logChildEvent(req, entry, fallbackActor = null) {
  return safeWriteAuditLog({
    source: inferSource(req, "backend"),
    performedBy: buildPerformedByFromRequest(req, fallbackActor),
    ...entry,
  });
}

async function getChildOrThrow(childId) {
  const childRef = firestore.collection("children").doc(childId);
  const childDoc = await childRef.get();

  if (!childDoc.exists) {
    throw createHttpError(404, "Child not found");
  }

  return { childRef, childDoc };
}

async function resolveUserByIdentifier(rawIdentifier) {
  const identifier = rawIdentifier?.toString().trim();
  if (!identifier) {
    return null;
  }

  const directUserDoc = await firestore.collection("users").doc(identifier).get();
  if (directUserDoc.exists) {
    return {
      userDoc: directUserDoc,
      resolvedUserId: directUserDoc.id,
      matchedBy: "document_id",
    };
  }

  const phoneMatches = await firestore
    .collection("users")
    .where("phone", "==", identifier)
    .limit(2)
    .get();

  if (phoneMatches.size === 1) {
    return {
      userDoc: phoneMatches.docs[0],
      resolvedUserId: phoneMatches.docs[0].id,
      matchedBy: "phone",
    };
  }

  if (phoneMatches.size > 1) {
    throw createHttpError(
      400,
      "Multiple users matched the provided User ID"
    );
  }

  const emailMatches = await firestore
    .collection("users")
    .where("email", "==", identifier)
    .limit(2)
    .get();

  if (emailMatches.size === 1) {
    return {
      userDoc: emailMatches.docs[0],
      resolvedUserId: emailMatches.docs[0].id,
      matchedBy: "email",
    };
  }

  if (emailMatches.size > 1) {
    throw createHttpError(
      400,
      "Multiple users matched the provided User ID"
    );
  }

  return null;
}

async function getDeviceDocsForChild(childId) {
  return firestore.collection("devices").where("child_id", "==", childId).get();
}

async function setChildDeviceState(
  childId,
  {
    childStatus,
    deviceStatus,
    blocked = false,
    disabled = false,
    markDeviceDisabledByChildBlock = false,
  }
) {
  const deviceSnap = await getDeviceDocsForChild(childId);
  const updates = [];

  deviceSnap.forEach((doc) => {
    const payload = {
      updated_at: Date.now(),
    };

    if (deviceStatus !== undefined) {
      payload.status = deviceStatus;
    }

    if (markDeviceDisabledByChildBlock !== undefined) {
      payload.disabled_by_child_block = markDeviceDisabledByChildBlock;
    }

    updates.push(doc.ref.update(payload));
  });

  if (childStatus !== undefined) {
    await syncRealtimeState(childId, {
      childStatus,
      deviceStatus: deviceStatus ?? "offline",
      disabled,
      blocked,
      reason: blocked ? "child_blocked" : "child_status_updated",
    });
  } else if (deviceStatus !== undefined) {
    await syncRealtimeState(childId, {
      deviceStatus,
      disabled,
      blocked,
      reason: blocked ? "child_blocked" : "child_status_updated",
    });
  }

  await Promise.all(updates);
}

// ADD CHILD (with optional device registration)
exports.addChild = async (req, res, next) => {
  try {
    const { user_id, name, age, photo, imei, sim_number, firmware } = req.body;
    const requestedUserId = user_id?.toString().trim();

    if (!requestedUserId || !name || age === undefined || age === null) {
      throw createHttpError(400, "user_id, name, and age are required");
    }

    const parsedAge = Number(age);
    if (Number.isNaN(parsedAge) || parsedAge < 0 || parsedAge > 18) {
      throw createHttpError(400, "age must be a number between 0 and 18");
    }

    console.info("[child.addChild] resolving user", {
      requestedUserId,
      lookupCollection: "users",
    });

    const resolvedUser = await resolveUserByIdentifier(requestedUserId);
    if (!resolvedUser) {
      throw createHttpError(404, "User not found");
    }

    const { userDoc, resolvedUserId, matchedBy } = resolvedUser;
    const userData = userDoc.data();

    ensureCanManageUserChildren(req, resolvedUserId);

    console.info("[child.addChild] user resolved", {
      requestedUserId,
      resolvedUserId,
      matchedBy,
    });

    const fallbackActor = {
      id: resolvedUserId,
      name: userData.name || null,
      email: userData.email || null,
      role:
        userData.role && userData.role.toString().trim().toLowerCase() === "admin"
          ? "admin"
          : "user",
      type: "user",
    };

    if (imei && imei.trim() !== "") {
      const existingDevice = await firestore
        .collection("devices")
        .where("imei", "==", imei.trim())
        .get();

      if (!existingDevice.empty) {
        throw createHttpError(400, "Device with this IMEI already exists");
      }
    }

    const child = await firestore.collection("children").add({
      user_id: resolvedUserId,
      name,
      age: parsedAge,
      photo: photo || "",
      status: "active",
      created_at: Date.now(),
    });

    let deviceData = null;

    if (imei && imei.trim() !== "") {
      const device = await firestore.collection("devices").add({
        child_id: child.id,
        imei: imei.trim(),
        sim_number: sim_number || "",
        battery_level: 100,
        firmware_version: firmware || "1.0.0",
        status: "online",
        created_at: Date.now(),
      });

      deviceData = {
        id: device.id,
        child_id: child.id,
        imei: imei.trim(),
        sim_number: sim_number || "",
        battery_level: 100,
        firmware_version: firmware || "1.0.0",
        status: "online",
      };
    }

    await syncRealtimeState(child.id, {
      childStatus: "active",
      deviceStatus: deviceData ? "online" : "offline",
      disabled: !deviceData,
      blocked: false,
      reason: deviceData ? "child_and_device_created" : "child_created",
    });

    await logChildEvent(
      req,
      {
        eventType: "child_created",
        entityType: "child",
        entityId: child.id,
        title: "Child created",
        description: `${name} was added for user ${userData.name || userData.email || resolvedUserId}.`,
        target: buildChildTarget(child.id, {
          user_id: resolvedUserId,
          name,
          age: parsedAge,
          photo: photo || "",
          status: "active",
        }),
        status: "success",
        result: "success",
        metadata: {
          newValues: {
            user_id: resolvedUserId,
            name,
            age: parsedAge,
            photo: photo || "",
            status: "active",
          },
          changedFields: ["user_id", "name", "age", "photo", "status"],
          relatedIds: deviceData ? { deviceId: deviceData.id } : {},
        },
      },
      fallbackActor
    );

    console.info("[child.addChild] child created", {
      childId: child.id,
      userId: resolvedUserId,
      deviceId: deviceData?.id || null,
    });

    if (deviceData) {
      await logChildEvent(
        req,
        {
          eventType: "device_registered",
          entityType: "device",
          entityId: deviceData.id,
          title: "Device registered",
          description: `Device ${deviceData.imei} was registered for child ${name}.`,
          target: {
            id: deviceData.id,
            imei: deviceData.imei,
            child_id: child.id,
            sim_number: deviceData.sim_number,
            firmware_version: deviceData.firmware_version,
            status: deviceData.status,
          },
          status: "success",
          result: "success",
          metadata: {
            newValues: deviceData,
            changedFields: [
              "imei",
              "child_id",
              "sim_number",
              "firmware_version",
              "status",
            ],
          },
        },
        fallbackActor
      );
    }

    res.json({
      child_id: child.id,
      user_id: resolvedUserId,
      device: deviceData,
      message: deviceData
        ? "Child and device added successfully"
        : "Child added successfully",
    });
  } catch (error) {
    await logChildEvent(
      req,
      {
        eventType: "child_created",
        entityType: "child",
        entityId: null,
        title: "Child creation failed",
        description: `Failed to create child ${req.body?.name || ""}.`,
        target: buildChildTarget(null, req.body || {}),
        status: "failed",
        result: "failed",
        metadata: {
          reason: error.message,
          requestedDevice: req.body?.imei
            ? {
                imei: req.body.imei,
                sim_number: req.body.sim_number || "",
                firmware: req.body.firmware || "1.0.0",
              }
            : null,
        },
      },
      req.body?.user_id
        ? {
            id: req.body.user_id,
            role: "user",
            type: "user",
          }
        : null
    );
    next(error);
  }
};

// GET ALL CHILDREN (admin)
exports.getAllChildren = async (req, res, next) => {
  try {
    const snap = await firestore.collection("children").get();
    const list = [];
    snap.forEach((d) => list.push({ id: d.id, ...d.data() }));
    list.sort((a, b) => (b.created_at || 0) - (a.created_at || 0));
    res.json(list);
  } catch (error) {
    next(error);
  }
};

// GET USER CHILDREN
exports.getChildren = async (req, res, next) => {
  try {
    ensureCanManageUserChildren(req, req.params.user_id);

    const snap = await firestore
      .collection("children")
      .where("user_id", "==", req.params.user_id)
      .get();

    const list = [];
    snap.forEach((d) => list.push({ id: d.id, ...d.data() }));

    res.json(list);
  } catch (error) {
    next(error);
  }
};

// GET CHILD BY ID
exports.getChildById = async (req, res, next) => {
  try {
    const { childDoc } = await getChildOrThrow(req.params.child_id);
    ensureCanAccessChildRecord(req, childDoc.data());
    res.json({ id: childDoc.id, ...childDoc.data() });
  } catch (error) {
    next(error);
  }
};

// UPDATE CHILD
exports.updateChild = async (req, res, next) => {
  try {
    const { childRef, childDoc } = await getChildOrThrow(req.params.child_id);
    const currentChildData = childDoc.data();
    ensureCanAccessChildRecord(req, currentChildData);
    const updates = {};

    if (req.body.user_id !== undefined) {
      if (!req.body.user_id) {
        throw createHttpError(400, "user_id is required");
      }

      const resolvedUser = await resolveUserByIdentifier(req.body.user_id);
      if (!resolvedUser) {
        throw createHttpError(404, "User not found");
      }

      ensureCanManageUserChildren(req, resolvedUser.resolvedUserId);
      updates.user_id = resolvedUser.resolvedUserId;
    }

    if (req.body.name !== undefined) {
      updates.name = req.body.name;
    }

    if (req.body.age !== undefined) {
      const parsedAge = Number(req.body.age);
      if (Number.isNaN(parsedAge) || parsedAge < 0 || parsedAge > 18) {
        throw createHttpError(400, "age must be a number between 0 and 18");
      }
      updates.age = parsedAge;
    }

    if (req.body.photo !== undefined) {
      updates.photo = req.body.photo;
    }

    if (Object.keys(updates).length === 0) {
      throw createHttpError(400, "No child fields provided to update");
    }

    updates.updated_at = Date.now();

    await childRef.update(updates);

    const nextChildData = {
      ...currentChildData,
      ...updates,
    };

    await logChildEvent(req, {
      eventType: "child_updated",
      entityType: "child",
      entityId: req.params.child_id,
      title: "Child updated",
      description: `${nextChildData.name || "Child"} profile was updated.`,
      target: buildChildTarget(req.params.child_id, nextChildData),
      status: "success",
      result: "success",
      metadata: {
        oldValues: currentChildData,
        newValues: nextChildData,
        changedFields: extractChangedFields(currentChildData, nextChildData),
      },
    });

    res.json({ message: "Child updated successfully" });
  } catch (error) {
    await logChildEvent(req, {
      eventType: "child_updated",
      entityType: "child",
      entityId: req.params.child_id || null,
      title: "Child update failed",
      description: `Failed to update child ${req.params.child_id}.`,
      target: buildChildTarget(req.params.child_id || null, req.body || {}),
      status: "failed",
      result: "failed",
      metadata: {
        reason: error.message,
      },
    });
    next(error);
  }
};

// REMOVE CHILD
exports.removeChild = async (req, res, next) => {
  try {
    const { childRef, childDoc } = await getChildOrThrow(req.params.child_id);
    const childId = childDoc.id;
    const childData = childDoc.data();
    ensureCanAccessChildRecord(req, childData);
    const deviceSnap = await getDeviceDocsForChild(childId);
    const batch = firestore.batch();
    const relatedDeviceIds = [];

    batch.delete(childRef);
    deviceSnap.forEach((doc) => {
      relatedDeviceIds.push(doc.id);
      batch.delete(doc.ref);
    });
    await batch.commit();

    await removeRealtimeState(childId);

    await logChildEvent(req, {
      eventType: "child_deleted",
      entityType: "child",
      entityId: childId,
      title: "Child deleted",
      description: `${childData.name || "Child"} was deleted.`,
      target: buildChildTarget(childId, childData),
      status: "success",
      result: "success",
      metadata: {
        oldValues: childData,
        relatedIds: {
          deletedDeviceIds: relatedDeviceIds,
        },
      },
    });

    res.json({ message: "Child removed successfully" });
  } catch (error) {
    await logChildEvent(req, {
      eventType: "child_deleted",
      entityType: "child",
      entityId: req.params.child_id || null,
      title: "Child delete failed",
      description: `Failed to delete child ${req.params.child_id}.`,
      target: { id: req.params.child_id || null },
      status: "failed",
      result: "failed",
      metadata: {
        reason: error.message,
      },
    });
    next(error);
  }
};

// UPDATE CHILD STATUS
exports.updateChildStatus = async (req, res, next) => {
  try {
    const { status } = req.body;
    if (!status) {
      throw createHttpError(400, "status is required");
    }

    const { childRef, childDoc } = await getChildOrThrow(req.params.child_id);
    const currentChildData = childDoc.data();
    ensureCanAccessChildRecord(req, currentChildData);
    await childRef.update({
      status,
      updated_at: Date.now(),
    });

    await syncRealtimeState(req.params.child_id, {
      childStatus: status,
      deviceStatus: status === "active" ? "offline" : "offline",
      disabled: status !== "active",
      blocked: status === "blocked",
      reason: "child_status_updated",
    });

    await logChildEvent(req, {
      eventType:
        status === "active"
          ? "child_activated"
          : status === "blocked"
              ? "child_blocked"
              : "child_deactivated",
      entityType: "child",
      entityId: req.params.child_id,
      title: "Child status updated",
      description: `${currentChildData.name || "Child"} status changed to ${status}.`,
      target: buildChildTarget(req.params.child_id, {
        ...currentChildData,
        status,
      }),
      status: "success",
      result: "success",
      metadata: {
        oldValues: { status: currentChildData.status || null },
        newValues: { status },
        changedFields: ["status"],
      },
    });

    res.json({ message: "Child status updated successfully" });
  } catch (error) {
    await logChildEvent(req, {
      eventType: "child_status_updated",
      entityType: "child",
      entityId: req.params.child_id || null,
      title: "Child status update failed",
      description: `Failed to update child status for ${req.params.child_id}.`,
      target: { id: req.params.child_id || null },
      status: "failed",
      result: "failed",
      metadata: {
        reason: error.message,
        requestedStatus: req.body?.status || null,
      },
    });
    next(error);
  }
};

// GET CHILD WITH DEVICE INFO
exports.getChildWithDevice = async (req, res, next) => {
  try {
    const { childDoc } = await getChildOrThrow(req.params.child_id);
    ensureCanAccessChildRecord(req, childDoc.data());

    const deviceSnap = await firestore
      .collection("devices")
      .where("child_id", "==", req.params.child_id)
      .limit(1)
      .get();

    let deviceData = null;
    if (!deviceSnap.empty) {
      deviceData = { id: deviceSnap.docs[0].id, ...deviceSnap.docs[0].data() };
    }

    const liveTracking = await getResolvedLiveTrackingSnapshot(req.params.child_id);
    if (deviceData && liveTracking) {
      deviceData = {
        ...deviceData,
        battery_level:
          liveTracking.batteryLevel ?? deviceData.battery_level ?? 0,
        status: liveTracking.latestStatus || deviceData.status || "offline",
        latest_live_status: liveTracking.latestStatus || null,
        latest_signal: liveTracking.latestSignal || null,
        latest_timestamp: liveTracking.latestTimestamp || null,
        live_tracking_key: liveTracking.trackingKey || null,
        timestamp_inferred: liveTracking.timestampInferred || false,
        live_tracking: liveTracking.raw || null,
      };
    }

    res.json({
      child: { id: childDoc.id, ...childDoc.data() },
      device: deviceData,
    });
  } catch (error) {
    next(error);
  }
};

// BLOCK CHILD
exports.blockChild = async (req, res, next) => {
  try {
    const { childRef, childDoc } = await getChildOrThrow(req.params.child_id);
    const childData = childDoc.data();
    ensureCanAccessChildRecord(req, childData);
    await childRef.update({
      status: "blocked",
      blocked_by_admin: true,
      updated_at: Date.now(),
    });

    await setChildDeviceState(req.params.child_id, {
      childStatus: "blocked",
      deviceStatus: "offline",
      blocked: true,
      disabled: true,
      markDeviceDisabledByChildBlock: true,
    });

    await logChildEvent(req, {
      eventType: "child_blocked",
      entityType: "child",
      entityId: req.params.child_id,
      title: "Child blocked",
      description: `${childData.name || "Child"} was blocked.`,
      target: buildChildTarget(req.params.child_id, {
        ...childData,
        status: "blocked",
        blocked_by_admin: true,
      }),
      status: "success",
      result: "success",
      metadata: {
        oldValues: {
          status: childData.status || null,
          blocked_by_admin: childData.blocked_by_admin || false,
        },
        newValues: {
          status: "blocked",
          blocked_by_admin: true,
        },
        changedFields: ["status", "blocked_by_admin"],
      },
    });

    res.json({ message: "Child blocked successfully" });
  } catch (error) {
    await logChildEvent(req, {
      eventType: "child_blocked",
      entityType: "child",
      entityId: req.params.child_id || null,
      title: "Child block failed",
      description: `Failed to block child ${req.params.child_id}.`,
      target: { id: req.params.child_id || null },
      status: "failed",
      result: "failed",
      metadata: {
        reason: error.message,
      },
    });
    next(error);
  }
};

// UNBLOCK CHILD
exports.unblockChild = async (req, res, next) => {
  try {
    const { childRef, childDoc } = await getChildOrThrow(req.params.child_id);
    const childData = childDoc.data();
    ensureCanAccessChildRecord(req, childData);
    const nextStatus = childData.status === "blocked" ? "active" : childData.status;

    await childRef.update({
      status: nextStatus,
      blocked_by_admin: false,
      updated_at: Date.now(),
    });

    await setChildDeviceState(req.params.child_id, {
      childStatus: "active",
      deviceStatus: "offline",
      blocked: false,
      disabled: false,
      markDeviceDisabledByChildBlock: false,
    });

    await logChildEvent(req, {
      eventType: "child_unblocked",
      entityType: "child",
      entityId: req.params.child_id,
      title: "Child unblocked",
      description: `${childData.name || "Child"} was unblocked.`,
      target: buildChildTarget(req.params.child_id, {
        ...childData,
        status: nextStatus,
        blocked_by_admin: false,
      }),
      status: "success",
      result: "success",
      metadata: {
        oldValues: {
          status: childData.status || null,
          blocked_by_admin: childData.blocked_by_admin || false,
        },
        newValues: {
          status: nextStatus,
          blocked_by_admin: false,
        },
        changedFields: ["status", "blocked_by_admin"],
      },
    });

    res.json({ message: "Child unblocked successfully" });
  } catch (error) {
    await logChildEvent(req, {
      eventType: "child_unblocked",
      entityType: "child",
      entityId: req.params.child_id || null,
      title: "Child unblock failed",
      description: `Failed to unblock child ${req.params.child_id}.`,
      target: { id: req.params.child_id || null },
      status: "failed",
      result: "failed",
      metadata: {
        reason: error.message,
      },
    });
    next(error);
  }
};
