const { realtimeDB, firestore } = require("../firebase");
const {
  createHttpError,
  ensureCanWriteChildEvent,
} = require("../utils/child-access");
const { getTrackingContextForChild } = require("../utils/live-tracking");
const { appendChildLog } = require("../utils/child-logs");

function parseOptionalCoordinate(value) {
  const number = Number(value);
  return Number.isFinite(number) ? number : null;
}

function mapConnectionStatusToHistoryType(status) {
  const normalizedStatus = status?.toString().trim().toLowerCase() || "";
  if (["online", "connected", "active"].includes(normalizedStatus)) {
    return "DEVICE_ONLINE";
  }

  if (["offline", "disconnected", "inactive", "device_off"].includes(normalizedStatus)) {
    return "DEVICE_OFFLINE";
  }

  return "DEVICE_STATUS";
}

exports.updateConnection = async (req, res, next) => {
  try {
    const childId = req.body.child_id?.toString().trim();
    const status = req.body.status?.toString().trim() || "unknown";

    if (!childId) {
      throw createHttpError(400, "child_id is required");
    }

    const accessResult = await ensureCanWriteChildEvent(req, childId);
    const time = Date.now();
    const trackingContext = await getTrackingContextForChild(childId);
    const trackingKey = trackingContext?.trackingKey || childId;
    const rtdbPath = `live_tracking/${trackingKey}/connection`;
    const latitude = parseOptionalCoordinate(req.body.lat ?? req.body.latitude);
    const longitude = parseOptionalCoordinate(req.body.lng ?? req.body.longitude);
    const previousConnectionSnapshot = await realtimeDB.ref(rtdbPath).once("value");
    const previousConnection = previousConnectionSnapshot.val() || {};
    const previousStatus = previousConnection.status?.toString().trim() || "";
    const historyType = mapConnectionStatusToHistoryType(status);
    const connectionState =
      historyType === "DEVICE_ONLINE"
        ? "online"
        : historyType === "DEVICE_OFFLINE"
          ? "offline"
          : "unknown";

    await realtimeDB.ref().update({
      [rtdbPath]: {
        status,
        time,
        updated_at: time,
        tracking_key: trackingKey,
        child_id: childId,
      },
      [`live_tracking/${trackingKey}/status`]: {
        online: historyType === "DEVICE_ONLINE",
        connectionState,
        lastSeen: time,
        ...(connectionState === "online" ? { lastOnlineAt: time } : {}),
        ...(connectionState === "offline" ? { lastOfflineAt: time } : {}),
        deviceStatus: status,
        network: req.body.network?.toString().trim() || "unknown",
        updatedAt: time,
        tracking_key: trackingKey,
        child_id: childId,
      },
    });

    if (previousStatus !== status) {
      await firestore.collection("connection_logs").add({
        child_id: childId,
        status,
        latitude,
        longitude,
        tracking_key: trackingKey,
        previous_status: previousStatus || null,
        event_time: time,
        created_at: time,
      });

      await appendChildLog({
        childId,
        trackingKey,
        parentUserId:
          trackingContext?.childData?.user_id?.toString().trim() || "",
        type: historyType,
        message:
          historyType === "DEVICE_ONLINE"
            ? "Device connection restored."
            : historyType === "DEVICE_OFFLINE"
              ? "Device connection lost."
              : `Device status changed to ${status}.`,
        timestamp: time,
        metadata: {
          source: "connection_update",
          previousStatus: previousStatus || null,
          status,
          latitude,
          longitude,
        },
      });
    }

    console.info("[connection.update]", {
      childId,
      trackingKey,
      rtdbPath: `/${rtdbPath}`,
      status,
      previousStatus: previousStatus || null,
      loggedTransition: previousStatus !== status,
      accessMode: accessResult.mode,
      deviceId: accessResult.deviceId || null,
      authId: req.auth?.id || null,
      role: req.auth?.role || null,
    });

    res.json({ message: "Connection saved" });
  } catch (error) {
    next(error);
  }
};
