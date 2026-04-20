const { firestore, realtimeDB } = require("../firebase");
const { syncRealtimeState } = require("../utils/realtime-sync");
const {
  getChildOrThrow,
  getChildWithAccessOrThrow,
  isAdminRequest,
} = require("../utils/child-access");
const {
  safeWriteAuditLog,
  buildPerformedByFromRequest,
  inferSource,
  extractChangedFields,
  createSystemActor,
} = require("../utils/audit-log");
const { getResolvedLiveTrackingSnapshot } = require("../utils/live-tracking");

function createHttpError(status, message) {
  const error = new Error(message);
  error.status = status;
  return error;
}

function buildDeviceTarget(deviceId, deviceData = {}) {
  return {
    id: deviceId || null,
    imei: deviceData.imei || null,
    child_id: deviceData.child_id || null,
    sim_number: deviceData.sim_number || null,
    firmware_version: deviceData.firmware_version || null,
    status: deviceData.status || null,
  };
}

function buildDeviceActor(req, fallback = null) {
  return buildPerformedByFromRequest(req, fallback);
}

async function logDeviceEvent(req, entry, fallbackActor = null) {
  return safeWriteAuditLog({
    source: inferSource(req, "backend"),
    performedBy: buildDeviceActor(req, fallbackActor),
    ...entry,
  });
}

async function getDeviceOrThrow(deviceId) {
  const deviceRef = firestore.collection("devices").doc(deviceId);
  const deviceDoc = await deviceRef.get();

  if (!deviceDoc.exists) {
    throw createHttpError(404, "Device not found");
  }

  return { deviceRef, deviceDoc };
}

async function getLiveTrackingSnapshot(childId) {
  try {
    return await getResolvedLiveTrackingSnapshot(childId);
  } catch (_) {
    return null;
  }
}

async function getDeviceWithAccessOrThrow(req, deviceId) {
  const { deviceRef, deviceDoc } = await getDeviceOrThrow(deviceId);
  const deviceData = deviceDoc.data() || {};
  const childId = deviceData.child_id?.toString().trim() || "";

  if (!childId) {
    throw createHttpError(400, "Device record is missing child_id");
  }

  const { childDoc } = await getChildWithAccessOrThrow(req, childId);

  return {
    deviceRef,
    deviceDoc,
    deviceData,
    childDoc,
    childData: childDoc.data() || {},
  };
}

async function buildDeviceResponse(
  deviceDoc,
  { childDoc = null, childData = null, liveSnapshot = null } = {}
) {
  const deviceData = deviceDoc.data() || {};
  const resolvedChildData = childData || {};
  const resolvedLiveSnapshot =
    liveSnapshot ||
    (deviceData.child_id ? await getLiveTrackingSnapshot(deviceData.child_id) : null);

  return {
    id: deviceDoc.id,
    ...deviceData,
    battery_level:
      resolvedLiveSnapshot?.batteryLevel ?? deviceData.battery_level ?? 0,
    child: childDoc
      ? {
          id: childDoc.id,
          name: resolvedChildData.name || "",
          user_id: resolvedChildData.user_id || "",
          status: resolvedChildData.status || "active",
        }
      : null,
    child_name: resolvedChildData.name || "",
    user_id: resolvedChildData.user_id || "",
    latest_live_status: resolvedLiveSnapshot?.latestStatus || null,
    latest_signal: resolvedLiveSnapshot?.latestSignal || null,
    latest_timestamp: resolvedLiveSnapshot?.latestTimestamp || null,
    live_tracking_key: resolvedLiveSnapshot?.trackingKey || null,
    timestamp_inferred: resolvedLiveSnapshot?.timestampInferred || false,
    live_tracking: resolvedLiveSnapshot?.raw || null,
  };
}

async function listAccessibleChildrenById(req) {
  const childSnap = isAdminRequest(req)
    ? await firestore.collection("children").get()
    : await firestore
        .collection("children")
        .where("user_id", "==", req.auth?.id || "")
        .get();

  return new Map(childSnap.docs.map((doc) => [doc.id, doc]));
}

// Register a new device
exports.registerDevice = async (req, res, next) => {
  try {
    const { child_id, imei, sim_number, firmware } = req.body;

    if (!isAdminRequest(req)) {
      throw createHttpError(403, "Admin access required");
    }

    if (!child_id || !imei) {
      throw createHttpError(400, "child_id and imei are required");
    }

    const { childDoc } = await getChildOrThrow(child_id);

    // Check if IMEI already exists
    const existingDevice = await firestore
      .collection("devices")
      .where("imei", "==", imei)
      .get();

    if (!existingDevice.empty) {
      throw createHttpError(400, "Device with this IMEI already exists");
    }

    const device = await firestore.collection("devices").add({
      child_id,
      imei,
      sim_number: sim_number || "",
      battery_level: 100,
      firmware_version: firmware || "1.0.0",
      status: "online",
      created_at: Date.now()
    });

    await syncRealtimeState(child_id, {
      childStatus: childDoc.data().status || "active",
      deviceStatus: "online",
      disabled: false,
      blocked: false,
      reason: "device_registered",
    });

    await logDeviceEvent(
      req,
      {
        eventType: "device_registered",
        entityType: "device",
        entityId: device.id,
        title: "Device registered",
        description: `Device ${imei} was registered for child ${child_id}.`,
        target: buildDeviceTarget(device.id, {
          child_id,
          imei,
          sim_number: sim_number || "",
          firmware_version: firmware || "1.0.0",
          status: "online",
        }),
        status: "success",
        result: "success",
        metadata: {
          newValues: {
            child_id,
            imei,
            sim_number: sim_number || "",
            firmware_version: firmware || "1.0.0",
            status: "online",
          },
          changedFields: [
            "child_id",
            "imei",
            "sim_number",
            "firmware_version",
            "status",
          ],
        },
      },
      createSystemActor("System")
    );

    res.json({ device_id: device.id, message: "Device registered successfully" });
  } catch (error) {
    await logDeviceEvent(
      req,
      {
        eventType: "device_registered",
        entityType: "device",
        entityId: null,
        title: "Device registration failed",
        description: `Failed to register device ${req.body?.imei || ""}.`,
        target: buildDeviceTarget(null, req.body || {}),
        status: "failed",
        result: "failed",
        metadata: {
          reason: error.message,
        },
      },
      createSystemActor("System")
    );
    next(error);
  }
};

// Get device by ID
exports.getDeviceById = async (req, res, next) => {
  try {
    const { deviceDoc, childDoc, childData } = await getDeviceWithAccessOrThrow(
      req,
      req.params.id
    );

    res.json(
      await buildDeviceResponse(deviceDoc, {
        childDoc,
        childData,
      })
    );
  } catch (error) {
    next(error);
  }
};

// Update device info
exports.updateDevice = async (req, res, next) => {
  try {
    if (!isAdminRequest(req)) {
      throw createHttpError(403, "Admin access required");
    }

    const { child_id, imei, sim_number, firmware_version } = req.body;

    const { deviceRef, deviceDoc } = await getDeviceOrThrow(req.params.id);
    const currentDeviceData = deviceDoc.data() || {};

    const updateData = {};
    if (child_id !== undefined && child_id !== "") {
      await getChildOrThrow(child_id);

      updateData.child_id = child_id;
    }
    if (imei !== undefined && imei !== "") {
      const duplicateImei = await firestore
        .collection("devices")
        .where("imei", "==", imei)
        .get();

      const duplicateExists = duplicateImei.docs.some(
        (doc) => doc.id !== req.params.id
      );

      if (duplicateExists) {
        throw createHttpError(400, "Device with this IMEI already exists");
      }

      updateData.imei = imei;
    }
    if (sim_number !== undefined) updateData.sim_number = sim_number;
    if (firmware_version !== undefined)
      updateData.firmware_version = firmware_version;
    updateData.updated_at = Date.now();

    await deviceRef.update(updateData);

    const nextDeviceData = {
      ...currentDeviceData,
      ...updateData,
    };

    await logDeviceEvent(req, {
      eventType: "device_updated",
      entityType: "device",
      entityId: req.params.id,
      title: "Device updated",
      description: `Device ${nextDeviceData.imei || req.params.id} was updated.`,
      target: buildDeviceTarget(req.params.id, nextDeviceData),
      status: "success",
      result: "success",
      metadata: {
        oldValues: currentDeviceData,
        newValues: nextDeviceData,
        changedFields: extractChangedFields(currentDeviceData, nextDeviceData),
      },
    });
    
    res.json({ message: "Device updated successfully" });
  } catch (error) {
    await logDeviceEvent(req, {
      eventType: "device_updated",
      entityType: "device",
      entityId: req.params.id || null,
      title: "Device update failed",
      description: `Failed to update device ${req.params.id}.`,
      target: buildDeviceTarget(req.params.id || null, req.body || {}),
      status: "failed",
      result: "failed",
      metadata: {
        reason: error.message,
      },
    });
    next(error);
  }
};

// Deactivate device
exports.deactivate = async (req, res, next) => {
  try {
    if (!isAdminRequest(req)) {
      throw createHttpError(403, "Admin access required");
    }

    const { deviceRef, deviceDoc } = await getDeviceOrThrow(req.params.id);
    const deviceData = deviceDoc.data() || {};
    await deviceRef.update({
      status: "offline",
      is_disabled: true,
      updated_at: Date.now(),
    });

    await syncRealtimeState(deviceData.child_id, {
      deviceStatus: "offline",
      disabled: true,
      blocked: false,
      reason: "device_deactivated",
    });

    await logDeviceEvent(req, {
      eventType: "device_deactivated",
      entityType: "device",
      entityId: req.params.id,
      title: "Device deactivated",
      description: `Device ${deviceData.imei || req.params.id} was deactivated.`,
      target: buildDeviceTarget(req.params.id, {
        ...deviceData,
        status: "offline",
        is_disabled: true,
      }),
      status: "success",
      result: "success",
      metadata: {
        oldValues: {
          status: deviceData.status || null,
          is_disabled: deviceData.is_disabled || false,
        },
        newValues: {
          status: "offline",
          is_disabled: true,
        },
        changedFields: ["status", "is_disabled"],
      },
    });

    res.json({ message: "Device deactivated successfully" });
  } catch (error) {
    await logDeviceEvent(req, {
      eventType: "device_deactivated",
      entityType: "device",
      entityId: req.params.id || null,
      title: "Device deactivation failed",
      description: `Failed to deactivate device ${req.params.id}.`,
      target: { id: req.params.id || null },
      status: "failed",
      result: "failed",
      metadata: {
        reason: error.message,
      },
    });
    next(error);
  }
};

// Activate device
exports.activate = async (req, res, next) => {
  try {
    if (!isAdminRequest(req)) {
      throw createHttpError(403, "Admin access required");
    }

    const { deviceRef, deviceDoc } = await getDeviceOrThrow(req.params.id);
    const deviceData = deviceDoc.data() || {};
    await deviceRef.update({
      status: "online",
      is_disabled: false,
      updated_at: Date.now(),
    });

    await syncRealtimeState(deviceData.child_id, {
      deviceStatus: "online",
      disabled: false,
      blocked: false,
      reason: "device_activated",
    });

    await logDeviceEvent(req, {
      eventType: "device_activated",
      entityType: "device",
      entityId: req.params.id,
      title: "Device activated",
      description: `Device ${deviceData.imei || req.params.id} was activated.`,
      target: buildDeviceTarget(req.params.id, {
        ...deviceData,
        status: "online",
        is_disabled: false,
      }),
      status: "success",
      result: "success",
      metadata: {
        oldValues: {
          status: deviceData.status || null,
          is_disabled: deviceData.is_disabled || false,
        },
        newValues: {
          status: "online",
          is_disabled: false,
        },
        changedFields: ["status", "is_disabled"],
      },
    });

    res.json({ message: "Device activated successfully" });
  } catch (error) {
    await logDeviceEvent(req, {
      eventType: "device_activated",
      entityType: "device",
      entityId: req.params.id || null,
      title: "Device activation failed",
      description: `Failed to activate device ${req.params.id}.`,
      target: { id: req.params.id || null },
      status: "failed",
      result: "failed",
      metadata: {
        reason: error.message,
      },
    });
    next(error);
  }
};

// Delete device
exports.deleteDevice = async (req, res, next) => {
  try {
    if (!isAdminRequest(req)) {
      throw createHttpError(403, "Admin access required");
    }

    const { deviceRef, deviceDoc } = await getDeviceOrThrow(req.params.id);
    const deviceData = deviceDoc.data() || {};
    await deviceRef.delete();

    await syncRealtimeState(deviceData.child_id, {
      deviceStatus: "offline",
      disabled: true,
      blocked: false,
      reason: "device_deleted",
    });

    await logDeviceEvent(req, {
      eventType: "device_deleted",
      entityType: "device",
      entityId: req.params.id,
      title: "Device deleted",
      description: `Device ${deviceData.imei || req.params.id} was deleted.`,
      target: buildDeviceTarget(req.params.id, deviceData),
      status: "success",
      result: "success",
      metadata: {
        oldValues: deviceData,
      },
    });

    res.json({ message: "Device deleted successfully" });
  } catch (error) {
    await logDeviceEvent(req, {
      eventType: "device_deleted",
      entityType: "device",
      entityId: req.params.id || null,
      title: "Device delete failed",
      description: `Failed to delete device ${req.params.id}.`,
      target: { id: req.params.id || null },
      status: "failed",
      result: "failed",
      metadata: {
        reason: error.message,
      },
    });
    next(error);
  }
};

// Get all accessible devices
exports.getAllDevices = async (req, res, next) => {
  try {
    const childDocsById = await listAccessibleChildrenById(req);
    const snap = await firestore.collection("devices").get();
    const list = await Promise.all(
      snap.docs
        .filter((doc) => {
          const childId = doc.data()?.child_id?.toString().trim() || "";
          return childDocsById.has(childId);
        })
        .map(async (doc) => {
          const childDoc = childDocsById.get(doc.data()?.child_id?.toString().trim() || "");
          const childData = childDoc?.data() || {};
          const liveSnapshot = await getLiveTrackingSnapshot(
            doc.data()?.child_id?.toString().trim() || ""
          );

          return buildDeviceResponse(doc, {
            childDoc,
            childData,
            liveSnapshot,
          });
        })
    );

    list.sort((a, b) => (b.created_at || 0) - (a.created_at || 0));
    res.json(list);
  } catch (error) {
    next(error);
  }
};

// Get device by child ID
exports.getDeviceByChildId = async (req, res, next) => {
  try {
    const { childDoc } = await getChildWithAccessOrThrow(req, req.params.child_id);
    const snap = await firestore.collection("devices")
      .where("child_id", "==", req.params.child_id)
      .limit(1)
      .get();
    
    if (snap.empty) {
      throw createHttpError(404, "Device not found for this child");
    }

    res.json(
      await buildDeviceResponse(snap.docs[0], {
        childDoc,
        childData: childDoc.data() || {},
      })
    );
  } catch (error) {
    next(error);
  }
};
