const { firestore } = require("../firebase");
const {
  syncRealtimeState,
  removeRealtimeState,
} = require("../utils/realtime-sync");
const {
  removeDeviceRegistry,
  upsertDeviceRegistry,
} = require("../utils/device-registry");
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

function logOwnershipValidation(req, targetUserId, result, reason) {
  console.info("[child.ownership]", {
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

function hasOwnBodyField(body, field) {
  return Object.prototype.hasOwnProperty.call(body || {}, field);
}

function hasDeviceUpdateInstruction(body = {}) {
  return [
    "register_device",
    "device_id",
    "imei",
    "sim_number",
    "firmware",
    "firmware_version",
  ].some((field) => hasOwnBodyField(body, field));
}

function parseBooleanFlag(value) {
  if (typeof value === "boolean") {
    return value;
  }

  if (typeof value === "number") {
    return value !== 0;
  }

  if (typeof value === "string") {
    return ["true", "1", "yes", "on"].includes(
      value.trim().toLowerCase()
    );
  }

  return Boolean(value);
}

async function getDeviceForChild(childId, requestedDeviceId = null) {
  const normalizedDeviceId = requestedDeviceId?.toString().trim() || "";

  if (normalizedDeviceId) {
    const deviceRef = firestore.collection("devices").doc(normalizedDeviceId);
    const deviceDoc = await deviceRef.get();

    if (!deviceDoc.exists) {
      throw createHttpError(404, "Device not found");
    }

    const deviceData = deviceDoc.data() || {};
    if (deviceData.child_id !== childId) {
      throw createHttpError(403, "Device is not linked to this child");
    }

    return { deviceRef, deviceDoc, deviceData };
  }

  const snap = await firestore
    .collection("devices")
    .where("child_id", "==", childId)
    .limit(1)
    .get();

  if (snap.empty) {
    return null;
  }

  return {
    deviceRef: snap.docs[0].ref,
    deviceDoc: snap.docs[0],
    deviceData: snap.docs[0].data() || {},
  };
}

async function getSafeResolvedLiveTrackingSnapshot(childId) {
  try {
    return await getResolvedLiveTrackingSnapshot(childId);
  } catch (error) {
    console.warn("[child.deviceStatus] live tracking lookup failed", {
      childId,
      error: error.message,
    });
    return null;
  }
}

function buildDeviceDataWithLiveStatus(childId, deviceData, liveTracking) {
  if (!deviceData) {
    return null;
  }

  const status = liveTracking?.latestStatus || "no_data";
  const statusReason = liveTracking?.statusReason || "missing_live_tracking";
  const now = liveTracking?.now || Date.now();

  console.info("[child.deviceStatus] computed", {
    childId,
    deviceId: deviceData.id || null,
    trackingKey: liveTracking?.trackingKey || null,
    rawLiveTimestamp: liveTracking?.latestTimestamp || null,
    now,
    ageMs: liveTracking?.latestAgeMs ?? null,
    status,
    reason: statusReason,
    rawLiveStatus: liveTracking?.rawLatestStatus || deviceData.status || null,
  });

  return {
    ...deviceData,
    battery_level: liveTracking?.batteryLevel ?? deviceData.battery_level ?? 0,
    status,
    latest_live_status: status,
    raw_live_status: liveTracking?.rawLatestStatus || deviceData.status || null,
    latest_signal: liveTracking?.latestSignal || statusReason,
    latest_timestamp: liveTracking?.latestTimestamp || null,
    latest_status_timestamp: liveTracking?.latestStatusTimestamp || null,
    latest_age_ms: liveTracking?.latestAgeMs ?? null,
    live_tracking_key: liveTracking?.trackingKey || null,
    timestamp_inferred: liveTracking?.timestampInferred || false,
    status_reason: statusReason,
    online_threshold_ms: liveTracking?.onlineThresholdMs || null,
    delayed_threshold_ms: liveTracking?.delayedThresholdMs || null,
    live_tracking: liveTracking?.raw || null,
  };
}

async function getDeviceDataWithLiveStatusForChild(childId) {
  const existingDevice = await getDeviceForChild(childId);
  if (!existingDevice) {
    console.info("[child.deviceStatus] no device linked", {
      childId,
      status: "no_data",
      reason: "missing_device",
    });
    return null;
  }

  const liveTracking = await getSafeResolvedLiveTrackingSnapshot(childId);
  return buildDeviceDataWithLiveStatus(
    childId,
    {
      id: existingDevice.deviceDoc.id,
      ...existingDevice.deviceData,
    },
    liveTracking
  );
}

async function ensureDeviceImeiIsAvailable(imei, existingDeviceId = null) {
  const duplicateImei = await firestore
    .collection("devices")
    .where("imei", "==", imei)
    .get();

  const duplicateExists = duplicateImei.docs.some(
    (doc) => doc.id !== existingDeviceId
  );

  if (duplicateExists) {
    throw createHttpError(400, "Device with this IMEI already exists");
  }
}

async function applyDeviceUpdateForChild(req, childId, childData = {}) {
  if (!hasDeviceUpdateInstruction(req.body)) {
    return { changed: false, deviceData: null };
  }

  const existingDevice = await getDeviceForChild(childId, req.body.device_id);
  const shouldRegister = hasOwnBodyField(req.body, "register_device")
    ? parseBooleanFlag(req.body.register_device)
    : true;
  const role = isAdminRequest(req) ? "admin" : "user";

  console.info("[child.updateChild.device] request", {
    role,
    authId: req.auth?.id || null,
    childId,
    existingDeviceId: existingDevice?.deviceDoc.id || null,
    registerDevice: shouldRegister,
  });

  if (!shouldRegister) {
    if (!existingDevice) {
      return { changed: false, deviceData: null };
    }

    await existingDevice.deviceRef.delete();
    await removeDeviceRegistry(existingDevice.deviceDoc.id, {
      childId,
    });
    await syncRealtimeState(childId, {
      childStatus: childData.status || "active",
      deviceStatus: "offline",
      disabled: true,
      blocked: childData.status === "blocked",
      reason: "device_deleted_from_child_form",
    });

    const deletedDeviceData = {
      id: existingDevice.deviceDoc.id,
      ...existingDevice.deviceData,
    };

    await logChildEvent(req, {
      eventType: "device_deleted",
      entityType: "device",
      entityId: existingDevice.deviceDoc.id,
      title: "Device deleted",
      description: `Device ${existingDevice.deviceData.imei || existingDevice.deviceDoc.id} was removed from ${childData.name || "child"}.`,
      target: {
        id: existingDevice.deviceDoc.id,
        imei: existingDevice.deviceData.imei || null,
        child_id: childId,
        sim_number: existingDevice.deviceData.sim_number || null,
        firmware_version: existingDevice.deviceData.firmware_version || null,
        status: existingDevice.deviceData.status || null,
      },
      status: "success",
      result: "success",
      metadata: {
        oldValues: deletedDeviceData,
      },
    });

    return { changed: true, deviceData: null };
  }

  const nextImei =
    req.body.imei?.toString().trim() || existingDevice?.deviceData.imei || "";
  if (!nextImei) {
    throw createHttpError(400, "imei is required when registering a device");
  }

  await ensureDeviceImeiIsAvailable(
    nextImei,
    existingDevice?.deviceDoc.id || null
  );

  const nextDeviceData = {
    child_id: childId,
    imei: nextImei,
    sim_number: hasOwnBodyField(req.body, "sim_number")
      ? req.body.sim_number || ""
      : existingDevice?.deviceData.sim_number || "",
    firmware_version:
      req.body.firmware?.toString().trim() ||
      req.body.firmware_version?.toString().trim() ||
      existingDevice?.deviceData.firmware_version ||
      "1.0.0",
    updated_at: Date.now(),
  };

  if (existingDevice) {
    await existingDevice.deviceRef.update(nextDeviceData);
    await upsertDeviceRegistry(existingDevice.deviceDoc.id, {
      ...existingDevice.deviceData,
      ...nextDeviceData,
      user_id: childData.user_id || "",
    });

    const mergedDeviceData = {
      ...existingDevice.deviceData,
      ...nextDeviceData,
    };

    await logChildEvent(req, {
      eventType: "device_updated",
      entityType: "device",
      entityId: existingDevice.deviceDoc.id,
      title: "Device updated",
      description: `Device ${nextImei} was updated for ${childData.name || "child"}.`,
      target: {
        id: existingDevice.deviceDoc.id,
        ...mergedDeviceData,
      },
      status: "success",
      result: "success",
      metadata: {
        oldValues: existingDevice.deviceData,
        newValues: mergedDeviceData,
        changedFields: extractChangedFields(
          existingDevice.deviceData,
          mergedDeviceData
        ),
      },
    });

    return {
      changed: true,
      deviceData: {
        id: existingDevice.deviceDoc.id,
        ...mergedDeviceData,
      },
    };
  }

  const createdDeviceData = {
    ...nextDeviceData,
    battery_level: 100,
    status: "offline",
    created_at: Date.now(),
  };
  delete createdDeviceData.updated_at;

  const device = await firestore.collection("devices").add(createdDeviceData);
  await upsertDeviceRegistry(device.id, {
    ...createdDeviceData,
    user_id: childData.user_id || "",
  });
  await syncRealtimeState(childId, {
    childStatus: childData.status || "active",
    deviceStatus: "offline",
    disabled: false,
    blocked: childData.status === "blocked",
    reason: "device_registered_from_child_form_waiting_for_live_data",
  });

  const responseDeviceData = {
    id: device.id,
    ...createdDeviceData,
  };

  await logChildEvent(req, {
    eventType: "device_registered",
    entityType: "device",
    entityId: device.id,
    title: "Device registered",
    description: `Device ${nextImei} was registered for ${childData.name || "child"}.`,
    target: responseDeviceData,
    status: "success",
    result: "success",
    metadata: {
      newValues: responseDeviceData,
      changedFields: [
        "child_id",
        "imei",
        "sim_number",
        "firmware_version",
        "status",
      ],
    },
  });

  return { changed: true, deviceData: responseDeviceData };
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
  const registryUpdates = [];

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
    registryUpdates.push(
      upsertDeviceRegistry(doc.id, {
        ...doc.data(),
        ...payload,
        user_id: doc.data()?.user_id || "",
      })
    );
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

  await Promise.all([...updates, ...registryUpdates]);
}

// ADD CHILD (with optional device registration)
exports.addChild = async (req, res, next) => {
  try {
    const { user_id, name, age, photo, imei, sim_number, firmware } = req.body;
    const requestedUserId = user_id?.toString().trim();
    const isAdmin = isAdminRequest(req);
    const effectiveUserIdentifier = isAdmin ? requestedUserId : req.auth?.id;

    console.info("[child.addChild] request", {
      role: isAdmin ? "admin" : req.auth?.role || "user",
      authId: req.auth?.id || null,
      requestedUserId: requestedUserId || null,
      effectiveUserIdentifier: effectiveUserIdentifier || null,
      mode: "add",
      hasPhoto: Boolean(photo),
      registerDevice: Boolean(imei && imei.trim() !== ""),
    });

    if (!isAdmin && requestedUserId && requestedUserId !== req.auth?.id) {
      logOwnershipValidation(
        req,
        requestedUserId,
        "denied",
        "manual_parent_assignment"
      );
      throw createHttpError(
        403,
        "You cannot assign a child to another parent"
      );
    }

    if (!effectiveUserIdentifier || !name || age === undefined || age === null) {
      throw createHttpError(
        400,
        isAdmin
          ? "user_id, name, and age are required"
          : "name and age are required"
      );
    }

    const parsedAge = Number(age);
    if (Number.isNaN(parsedAge) || parsedAge < 0 || parsedAge > 18) {
      throw createHttpError(400, "age must be a number between 0 and 18");
    }

    console.info("[child.addChild] resolving user", {
      requestedUserId: requestedUserId || null,
      effectiveUserIdentifier,
      lookupCollection: "users",
    });

    const resolvedUser = await resolveUserByIdentifier(effectiveUserIdentifier);
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
      const createdDeviceAt = Date.now();
      const createdDeviceData = {
        child_id: child.id,
        imei: imei.trim(),
        sim_number: sim_number || "",
        battery_level: 100,
        firmware_version: firmware || "1.0.0",
        status: "offline",
        created_at: createdDeviceAt,
      };
      const device = await firestore.collection("devices").add(createdDeviceData);
      await upsertDeviceRegistry(device.id, {
        ...createdDeviceData,
        user_id: resolvedUserId,
      });

      deviceData = {
        id: device.id,
        ...createdDeviceData,
      };
    }

    await syncRealtimeState(child.id, {
      childStatus: "active",
      deviceStatus: "offline",
      disabled: !deviceData,
      blocked: false,
      reason: deviceData
        ? "child_and_device_created_waiting_for_live_data"
        : "child_created",
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
      req.auth?.id
        ? {
            id: req.auth.id,
            role: req.auth.role || req.auth.type || "user",
            type: req.auth.type || "user",
          }
        : req.body?.user_id
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

    const list = await Promise.all(
      snap.docs.map(async (d) => ({
        id: d.id,
        ...d.data(),
        device: await getDeviceDataWithLiveStatusForChild(d.id),
      }))
    );

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
    const isAdmin = isAdminRequest(req);
    const hasDeviceInstruction = hasDeviceUpdateInstruction(req.body);

    console.info("[child.updateChild] request", {
      role: isAdmin ? "admin" : req.auth?.role || "user",
      authId: req.auth?.id || null,
      childId: req.params.child_id,
      ownerUserId: currentChildData.user_id || null,
      requestedUserId:
        req.body.user_id !== undefined ? req.body.user_id || null : null,
      mode: "edit",
      hasDeviceInstruction,
      registerDevice:
        req.body.register_device !== undefined
          ? parseBooleanFlag(req.body.register_device)
          : null,
    });

    if (req.body.user_id !== undefined) {
      if (!req.body.user_id) {
        throw createHttpError(400, "user_id is required");
      }

      if (!isAdmin) {
        if (req.body.user_id.toString().trim() !== req.auth?.id) {
          logOwnershipValidation(
            req,
            req.body.user_id.toString().trim(),
            "denied",
            "manual_parent_assignment"
          );
          throw createHttpError(
            403,
            "You cannot assign a child to another parent"
          );
        }

        console.info("[child.updateChild] ignored user_id from owner request", {
          childId: req.params.child_id,
          authId: req.auth?.id || null,
        });
      } else {
        const resolvedUser = await resolveUserByIdentifier(req.body.user_id);
        if (!resolvedUser) {
          throw createHttpError(404, "User not found");
        }

        ensureCanManageUserChildren(req, resolvedUser.resolvedUserId);
        updates.user_id = resolvedUser.resolvedUserId;
      }
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

    if (Object.keys(updates).length === 0 && !hasDeviceInstruction) {
      throw createHttpError(400, "No child fields provided to update");
    }

    if (Object.keys(updates).length > 0) {
      updates.updated_at = Date.now();

      await childRef.update(updates);
    }

    const nextChildData = {
      ...currentChildData,
      ...updates,
    };

    const deviceUpdate = await applyDeviceUpdateForChild(
      req,
      req.params.child_id,
      nextChildData
    );

    if (Object.keys(updates).length > 0) {
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
          deviceChanged: deviceUpdate.changed,
        },
      });
    }

    res.json({
      message: "Child updated successfully",
      device: deviceUpdate.deviceData,
    });
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
    await Promise.all(
      relatedDeviceIds.map((deviceId) =>
        removeDeviceRegistry(deviceId, {
          childId,
        })
      )
    );

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

    const deviceData = await getDeviceDataWithLiveStatusForChild(
      req.params.child_id
    );

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
