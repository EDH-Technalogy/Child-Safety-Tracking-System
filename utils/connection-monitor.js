const { realtimeDB } = require("../firebase");
const {
  getConnectionMonitorConfig,
  recordDeviceDisconnected,
} = require("./connection-events");
const { normalizeEpochMillisecondsOrNull } = require("./live-timestamp");
const { tryNormalizeTrackingKey } = require("./tracking-key-normalizer");
const { getTrackingContextForChild } = require("./live-tracking");
const { upsertDeviceStatusCard } = require("./device-status");

let monitorIntervalHandle = null;
let sweepInProgress = false;

function asMap(value) {
  return value && typeof value === "object" ? value : {};
}

function resolveLastSeen(status = {}, location = {}) {
  return (
    normalizeEpochMillisecondsOrNull(status.lastSeen) ??
    normalizeEpochMillisecondsOrNull(location.timestamp) ??
    normalizeEpochMillisecondsOrNull(location.recorded_at)
  );
}

function normalizeTrackedDevices(rawRegistry = {}) {
  const devices = [];
  const seenTrackingKeys = new Set();

  for (const registryEntry of Object.values(asMap(rawRegistry))) {
    const entry = asMap(registryEntry);
    const trackingKey = tryNormalizeTrackingKey(
      entry.tracking_key || entry.imei || entry.device_id
    );
    const childId = entry.child_id?.toString().trim() || "";
    if (!trackingKey || !childId || seenTrackingKeys.has(trackingKey)) {
      continue;
    }

    if (Boolean(entry.is_disabled) || Boolean(entry.disabled_by_child_block)) {
      continue;
    }

    seenTrackingKeys.add(trackingKey);
    devices.push({
      childId,
      trackingKey,
      parentUserId: entry.user_id?.toString().trim() || "",
    });
  }

  return devices;
}

async function evaluateTrackedDevice(device) {
  const { offlineThresholdMs } = getConnectionMonitorConfig();
  const statusRef = realtimeDB.ref(`live_tracking/${device.trackingKey}/status`);
  const locationRef = realtimeDB.ref(`live_tracking/${device.trackingKey}/location`);
  const [statusSnapshot, locationSnapshot] = await Promise.all([
    statusRef.once("value"),
    locationRef.once("value"),
  ]);

  const status = asMap(statusSnapshot.val());
  const location = asMap(locationSnapshot.val());
  const lastSeen = resolveLastSeen(status, location);
  const now = Date.now();

  if (lastSeen === null || now - lastSeen <= offlineThresholdMs) {
    return false;
  }

  let transitionContext = null;
  const transactionResult = await statusRef.transaction((currentValue) => {
    const currentStatus = asMap(currentValue);
    const currentLastSeen = resolveLastSeen(currentStatus, location) ?? lastSeen;
    const currentConnectionState =
      currentStatus.connectionState?.toString().trim().toLowerCase() || "";

    if (
      currentLastSeen === null ||
      now - currentLastSeen <= offlineThresholdMs ||
      currentConnectionState === "offline"
    ) {
      transitionContext = null;
      return currentValue;
    }

    transitionContext = {
      previousLastSeen: currentLastSeen,
      previousConnectionState:
        currentConnectionState || (currentStatus.online === true ? "online" : "unknown"),
      childId:
        currentStatus.child_id?.toString().trim() || device.childId,
      trackingKey:
        currentStatus.tracking_key?.toString().trim() || device.trackingKey,
      parentUserId: device.parentUserId,
      lastKnownLat:
        Number.isFinite(Number(location.latitude)) ? Number(location.latitude) : null,
      lastKnownLng:
        Number.isFinite(Number(location.longitude)) ? Number(location.longitude) : null,
      lastKnownAccuracy:
        Number.isFinite(Number(location.accuracy)) ? Number(location.accuracy) : null,
      lastKnownTimestamp:
        normalizeEpochMillisecondsOrNull(location.timestamp) ??
        normalizeEpochMillisecondsOrNull(location.recorded_at),
      lastKnownAddress: location.location_text?.toString().trim() || null,
    };

    return {
      ...currentStatus,
      online: false,
      connectionState: "offline",
      lastOfflineAt: now,
      lastSeen: currentLastSeen,
      lastKnownLat: transitionContext.lastKnownLat,
      lastKnownLng: transitionContext.lastKnownLng,
      lastKnownAccuracy: transitionContext.lastKnownAccuracy,
      lastKnownTimestamp: transitionContext.lastKnownTimestamp,
      lastKnownAddress: transitionContext.lastKnownAddress,
      deviceStatus: "offline",
      updatedAt: now,
      child_id: transitionContext.childId,
      tracking_key: transitionContext.trackingKey,
    };
  });

  if (!transactionResult.committed || !transitionContext) {
    return false;
  }

  await recordDeviceDisconnected({
    childId: transitionContext.childId,
    trackingKey: transitionContext.trackingKey,
    parentUserId: transitionContext.parentUserId,
    disconnectedAt: now,
    previousLastSeen: transitionContext.previousLastSeen,
    lastKnownLat: transitionContext.lastKnownLat,
    lastKnownLng: transitionContext.lastKnownLng,
    lastKnownAccuracy: transitionContext.lastKnownAccuracy,
    lastKnownTimestamp: transitionContext.lastKnownTimestamp,
    lastKnownAddress: transitionContext.lastKnownAddress,
    offlineThresholdMs,
    source: "connection_monitor",
  });

  const trackingContext = await getTrackingContextForChild(
    transitionContext.childId
  );
  await upsertDeviceStatusCard({
    childId: transitionContext.childId,
    trackingKey: transitionContext.trackingKey,
    childName: trackingContext?.childData?.name?.toString().trim() || "",
    deviceName:
      trackingContext?.deviceData?.name?.toString().trim() ||
      trackingContext?.deviceData?.imei?.toString().trim() ||
      transitionContext.trackingKey,
    status: "offline",
    latitude: transitionContext.lastKnownLat,
    longitude: transitionContext.lastKnownLng,
    timestamp: now,
    heartbeatAt: transitionContext.previousLastSeen,
    placeName: transitionContext.lastKnownAddress,
    source: "connection_monitor",
    writeTransitionLog: true,
    previousStatusHint: transitionContext.previousConnectionState,
  });

  console.info("[connection-monitor.offline-transition]", {
    childId: transitionContext.childId,
    trackingKey: transitionContext.trackingKey,
    lastSeen: transitionContext.previousLastSeen,
    disconnectedAt: now,
    offlineThresholdMs,
  });

  return true;
}

async function runConnectionMonitorSweep() {
  if (sweepInProgress) {
    return;
  }

  sweepInProgress = true;
  try {
    const registrySnapshot = await realtimeDB.ref("device_registry").once("value");
    const devices = normalizeTrackedDevices(registrySnapshot.val());
    let transitions = 0;

    for (const device of devices) {
      const transitioned = await evaluateTrackedDevice(device);
      if (transitioned) {
        transitions += 1;
      }
    }

    console.info("[connection-monitor.sweep]", {
      devicesChecked: devices.length,
      transitions,
    });
  } catch (error) {
    console.error("[connection-monitor.sweep] failed", {
      reason: error.message,
    });
  } finally {
    sweepInProgress = false;
  }
}

function initConnectionMonitor() {
  if (monitorIntervalHandle) {
    return monitorIntervalHandle;
  }

  const { monitorIntervalMs, offlineThresholdMs } = getConnectionMonitorConfig();
  console.info("[connection-monitor.init]", {
    monitorIntervalMs,
    offlineThresholdMs,
  });

  // Run an initial pass so stale devices are corrected without waiting a full interval.
  void runConnectionMonitorSweep();

  monitorIntervalHandle = setInterval(() => {
    void runConnectionMonitorSweep();
  }, monitorIntervalMs);

  return monitorIntervalHandle;
}

function stopConnectionMonitor() {
  if (!monitorIntervalHandle) {
    return;
  }

  clearInterval(monitorIntervalHandle);
  monitorIntervalHandle = null;
}

module.exports = {
  initConnectionMonitor,
  runConnectionMonitorSweep,
  stopConnectionMonitor,
};
