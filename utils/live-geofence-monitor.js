const { realtimeDB } = require("../firebase");
const {
  buildAlertMessage,
  buildLocationText,
  createAlertRecord,
} = require("./alert-service");
const {
  safeWriteAuditLog,
  createSystemActor,
} = require("./audit-log");
const {
  normalizeEpochMillisecondsOrNull,
  normalizeRealtimeLocationTimestamps,
} = require("./live-timestamp");
const { tryNormalizeTrackingKey } = require("./tracking-key-normalizer");

const trackedDevices = new Map();
const safeZoneCache = new Map();
let monitorInitialized = false;
let deviceRegistryRef = null;
let safeZonesRef = null;

function parseNumber(value) {
  const numericValue = Number(value);
  return Number.isFinite(numericValue) ? numericValue : null;
}

function parseCoordinate(payload, ...keys) {
  for (const key of keys) {
    const numericValue = parseNumber(payload?.[key]);
    if (numericValue !== null) {
      return numericValue;
    }
  }

  return null;
}

function isValidCoordinate(latitude, longitude) {
  return (
    latitude !== null &&
    longitude !== null &&
    latitude >= -90 &&
    latitude <= 90 &&
    longitude >= -180 &&
    longitude <= 180
  );
}

function calculateDistance(lat1, lon1, lat2, lon2) {
  const earthRadiusMeters = 6371000;
  const dLat = ((lat2 - lat1) * Math.PI) / 180;
  const dLon = ((lon2 - lon1) * Math.PI) / 180;
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos((lat1 * Math.PI) / 180) *
      Math.cos((lat2 * Math.PI) / 180) *
      Math.sin(dLon / 2) *
      Math.sin(dLon / 2);

  return earthRadiusMeters * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

function extractLocationSequence(rawLocation) {
  const timestamp = normalizeEpochMillisecondsOrNull(rawLocation?.timestamp);
  const recordedAt = normalizeEpochMillisecondsOrNull(rawLocation?.recorded_at);

  if (timestamp !== null && recordedAt !== null) {
    return Math.max(timestamp, recordedAt);
  }

  return timestamp ?? recordedAt ?? Date.now();
}

function buildLocationSignature(rawLocation, latitude, longitude) {
  return [
    latitude?.toFixed(6) ?? "",
    longitude?.toFixed(6) ?? "",
    rawLocation?.timestamp?.toString() ?? "",
    rawLocation?.recorded_at?.toString() ?? "",
    rawLocation?.speed?.toString() ?? "",
    rawLocation?.battery?.toString() ?? "",
  ].join("|");
}

function buildGeofenceTarget({
  childId,
  deviceId,
  trackingKey,
  zone,
}) {
  return {
    id: zone?.id || null,
    child_id: childId || null,
    device_id: deviceId || null,
    safe_zone_id: zone?.id || null,
    safe_zone_name: zone?.name || null,
    tracking_key: trackingKey || null,
  };
}

function normalizeSafeZone(zoneId, zoneData = {}) {
  const latitude = parseNumber(zoneData.latitude);
  const longitude = parseNumber(zoneData.longitude);
  const radius = parseNumber(zoneData.radius);
  const status = zoneData.status?.toString().trim().toLowerCase() || "active";

  if (
    !zoneId ||
    status !== "active" ||
    !isValidCoordinate(latitude, longitude) ||
    radius === null ||
    radius <= 0
  ) {
    return null;
  }

  return {
    id: zoneId.toString(),
    child_id: zoneData.child_id?.toString().trim() || "",
    user_id: zoneData.user_id?.toString().trim() || "",
    name: zoneData.name?.toString().trim() || "Safe Zone",
    latitude,
    longitude,
    radius,
    status: "active",
    updated_at: parseNumber(zoneData.updated_at) || Date.now(),
  };
}

function syncSafeZoneCache(childId, rawValue) {
  const normalizedChildId = childId?.toString().trim() || "";
  if (!normalizedChildId) {
    return [];
  }

  const zones = [];
  if (rawValue && typeof rawValue === "object") {
    Object.entries(rawValue).forEach(([zoneId, zoneData]) => {
      const normalizedZone = normalizeSafeZone(zoneId, zoneData);
      if (normalizedZone) {
        zones.push(normalizedZone);
      }
    });
  }

  safeZoneCache.set(normalizedChildId, zones);

  console.info("[geofence-monitor.safe-zone-cache]", {
    childId: normalizedChildId,
    zoneCount: zones.length,
    zoneIds: zones.map((zone) => zone.id),
  });

  return zones;
}

async function getActiveSafeZones(childId) {
  const normalizedChildId = childId?.toString().trim() || "";
  if (!normalizedChildId) {
    return [];
  }

  const cachedZones = safeZoneCache.get(normalizedChildId);
  if (cachedZones) {
    return cachedZones;
  }

  const snapshot = await realtimeDB
    .ref(`safe_zones/${normalizedChildId}`)
    .once("value");

  return syncSafeZoneCache(normalizedChildId, snapshot.val());
}

async function createGeofenceTransitionLog({
  childId,
  deviceId,
  trackingKey,
  zone,
  previousStatus,
  currentStatus,
  latitude,
  longitude,
  distanceFromCenter,
  locationText,
  eventType,
}) {
  const isExit = eventType === "safe_zone_exit";
  const zoneName = zone?.name || "Safe Zone";
  const radius = parseNumber(zone?.radius);
  const roundedDistance = Number.isFinite(distanceFromCenter)
    ? Math.round(distanceFromCenter)
    : null;
  const message = isExit
    ? `${zoneName} was exited at ${locationText}.`
    : `${zoneName} was re-entered at ${locationText}.`;

  return safeWriteAuditLog({
    eventType,
    entityType: "safe_zone",
    entityId: zone?.id || childId || null,
    title: isExit ? "Safe zone exit detected" : "Safe zone re-entry detected",
    description: message,
    performedBy: createSystemActor("Geofence Monitor"),
    target: buildGeofenceTarget({
      childId,
      deviceId,
      trackingKey,
      zone,
    }),
    status: "success",
    result: "success",
    source: "geofence",
    metadata: {
      childId,
      deviceId: deviceId || null,
      trackingKey,
      safeZoneId: zone?.id || null,
      safeZoneName: zone?.name || null,
      latitude,
      longitude,
      distanceFromCenter: roundedDistance,
      safeZoneRadius: radius,
      previousGeofenceState: previousStatus,
      currentGeofenceState: currentStatus,
      locationText,
    },
  });
}

async function syncZoneStates({
  childId,
  trackingKey,
  latitude,
  longitude,
  locationText,
  zones,
  checkedAt,
}) {
  const stateRef = realtimeDB.ref(`geofence_state/${childId}`);
  const previousStateSnapshot = await stateRef.once("value");
  const previousStates = previousStateSnapshot.val() || {};
  const updates = {};

  zones.forEach((zone) => {
    const distance = calculateDistance(
      latitude,
      longitude,
      zone.latitude,
      zone.longitude
    );
    const inside = distance <= zone.radius;
    const previousZoneState =
      previousStates[zone.id] && typeof previousStates[zone.id] === "object"
        ? previousStates[zone.id]
        : {};
    const previousInside = previousZoneState.inside === true;

    updates[`geofence_state/${childId}/${zone.id}`] = {
      inside,
      childId,
      zoneId: zone.id,
      zoneName: zone.name,
      trackingKey,
      distanceMeters: Math.round(distance),
      lastCheckedAt: checkedAt,
      lastLocationText: locationText,
      latitude,
      longitude,
      lastBreachAt:
        previousInside && !inside
          ? checkedAt
          : normalizeEpochMillisecondsOrNull(previousZoneState.lastBreachAt),
      lastReturnAt:
        !previousInside && inside
          ? checkedAt
          : normalizeEpochMillisecondsOrNull(previousZoneState.lastReturnAt),
    };
  });

  if (Object.keys(updates).length > 0) {
    await realtimeDB.ref().update(updates);
  }

  return previousStates;
}

async function processLiveTrackingUpdate({
  childId,
  trackingKey,
  deviceId = "",
  snapshotValue = undefined,
}) {
  if (!childId || !trackingKey) {
    return {
      processed: false,
      reason: "missing_child_or_tracking_key",
    };
  }

  const locationRef = realtimeDB.ref(`live_tracking/${trackingKey}/location`);
  let rawLocation =
    snapshotValue && typeof snapshotValue === "object"
      ? snapshotValue
      : (
          await locationRef.once("value")
        ).val();

  const hasLocationPayload =
    rawLocation &&
    typeof rawLocation === "object" &&
    Object.keys(rawLocation).length > 0;

  if (hasLocationPayload) {
    const timestampNormalization = normalizeRealtimeLocationTimestamps(
      rawLocation,
      Date.now()
    );

    if (timestampNormalization.changed) {
      await locationRef.update({
        timestamp: timestampNormalization.normalizedTimestamp,
        recorded_at: timestampNormalization.normalizedRecordedAt,
      });

      rawLocation = timestampNormalization.payload;

      console.info("[geofence-monitor.timestamp-normalized]", {
        childId,
        trackingKey,
        rtdbPath: `/live_tracking/${trackingKey}/location`,
        rawTimestamp: timestampNormalization.rawTimestamp ?? null,
        rawRecordedAt: timestampNormalization.rawRecordedAt ?? null,
        normalizedTimestamp: timestampNormalization.normalizedTimestamp,
        normalizedRecordedAt: timestampNormalization.normalizedRecordedAt,
      });
    }
  }

  const latitude = parseCoordinate(rawLocation, "latitude", "lat");
  const longitude = parseCoordinate(rawLocation, "longitude", "lng");

  console.info("[geofence-monitor.location]", {
    childId,
    trackingKey,
    deviceId: deviceId || null,
    rtdbPath: `/live_tracking/${trackingKey}/location`,
    rawLocation,
  });

  if (!isValidCoordinate(latitude, longitude)) {
    console.info("[geofence-monitor.skip]", {
      childId,
      trackingKey,
      reason: "invalid_coordinates",
      rawLocation,
    });

    return {
      processed: false,
      reason: "invalid_coordinates",
    };
  }

  const locationSequence = extractLocationSequence(rawLocation);
  const locationSignature = buildLocationSignature(
    rawLocation,
    latitude,
    longitude
  );
  const locationText = buildLocationText({
    locationText: rawLocation.location_text,
    area: rawLocation.area,
    address: rawLocation.address,
    latitude,
    longitude,
  });

  const legacyStateRef = realtimeDB.ref(`live_tracking/${childId}/geofence`);
  const previousStateSnapshot = await legacyStateRef.once("value");
  const previousState = previousStateSnapshot.val() || {};

  if (
    previousState.last_processed_signature?.toString().trim() ===
    locationSignature
  ) {
    console.info("[geofence-monitor.skip]", {
      childId,
      trackingKey,
      reason: "duplicate_location_signature",
      locationSequence,
      locationSignature,
    });

    return {
      processed: false,
      reason: "duplicate_location_signature",
      previousStatus: previousState.status || "unknown",
    };
  }

  const safeZones = await getActiveSafeZones(childId);

  console.info("[geofence-monitor.safe-zones]", {
    childId,
    trackingKey,
    source: "rtdb",
    zoneCount: safeZones.length,
    zones: safeZones.map((zone) => ({
      id: zone.id,
      name: zone.name,
      latitude: zone.latitude,
      longitude: zone.longitude,
      radius: zone.radius,
      status: zone.status,
    })),
  });

  if (safeZones.length === 0) {
    await legacyStateRef.set({
      status: "no_zone",
      last_location_text: locationText,
      latitude,
      longitude,
      last_processed_sequence: locationSequence,
      last_processed_signature: locationSignature,
      updated_at: Date.now(),
    });

    console.info("[geofence-monitor.skip]", {
      childId,
      trackingKey,
      reason: "no_active_safe_zone",
      latitude,
      longitude,
    });

    return {
      processed: true,
      previousStatus: previousState.status || "unknown",
      currentStatus: "no_zone",
      alertType: null,
    };
  }

  await syncZoneStates({
    childId,
    trackingKey,
    latitude,
    longitude,
    locationText,
    zones: safeZones,
    checkedAt: Date.now(),
  });

  let insideZone = false;
  let matchedZone = null;
  let nearestZone = null;
  let nearestDistance = Number.POSITIVE_INFINITY;

  safeZones.forEach((zone) => {
    const distance = calculateDistance(
      latitude,
      longitude,
      zone.latitude,
      zone.longitude
    );

    if (distance < nearestDistance) {
      nearestDistance = distance;
      nearestZone = zone;
    }

    if (!insideZone && distance <= zone.radius) {
      insideZone = true;
      matchedZone = zone;
    }
  });

  const currentStatus = insideZone ? "inside" : "outside";
  const activeZone = matchedZone || nearestZone;
  const previousStatus = previousState.status || "unknown";

  await legacyStateRef.set({
    status: currentStatus,
    zone_id: activeZone?.id || null,
    zone_name: activeZone?.name || null,
    last_location_text: locationText,
    latitude,
    longitude,
    distance_to_zone_meters:
      Number.isFinite(nearestDistance) ? Math.round(nearestDistance) : null,
    last_processed_sequence: locationSequence,
    last_processed_signature: locationSignature,
    updated_at: Date.now(),
  });

  let alertType = null;
  if (currentStatus === "outside" && previousStatus === "inside") {
    alertType = "OUT_ZONE";
  } else if (currentStatus === "inside" && previousStatus === "outside") {
    alertType = "IN_ZONE";
  }

  if (alertType) {
    const message = buildAlertMessage({
      type: alertType,
      zoneName: activeZone?.name || null,
      locationText,
    });

    const createdAlert = await createAlertRecord({
      childId,
      type: alertType,
      zoneName: activeZone?.name || null,
      locationText,
      latitude,
      longitude,
      message,
      extraFields: {
        source: "live_geofence_monitor",
        device_id: deviceId || null,
        tracking_key: trackingKey,
        event_key:
          alertType === "OUT_ZONE" ? "safe_zone_exit" : "safe_zone_enter",
      },
    });

    console.info("[geofence-monitor.alert-created]", {
      childId,
      deviceId: deviceId || null,
      trackingKey,
      alertId: createdAlert.alertId,
      alertType,
      previousStatus,
      currentStatus,
      zoneId: activeZone?.id || null,
      zoneName: activeZone?.name || null,
    });

    const createdLog = await createGeofenceTransitionLog({
      childId,
      deviceId,
      trackingKey,
      zone: activeZone,
      previousStatus,
      currentStatus,
      latitude,
      longitude,
      distanceFromCenter: nearestDistance,
      locationText,
      eventType:
        alertType === "OUT_ZONE" ? "safe_zone_exit" : "safe_zone_enter",
    });

    if (createdLog?.id) {
      console.info("[geofence-monitor.audit-log-created]", {
        childId,
        deviceId: deviceId || null,
        trackingKey,
        logId: createdLog.id,
        eventType:
          alertType === "OUT_ZONE" ? "safe_zone_exit" : "safe_zone_enter",
      });
    }
  } else {
    console.info("[geofence-monitor.alert-skipped]", {
      childId,
      trackingKey,
      previousStatus,
      currentStatus,
      reason:
        previousStatus === currentStatus
          ? "state_unchanged"
          : "no_alert_needed_for_state",
    });
  }

  console.info("[geofence-monitor.transition]", {
    childId,
    deviceId: deviceId || null,
    trackingKey,
    latitude,
    longitude,
    previousStatus,
    currentStatus,
    activeZoneId: activeZone?.id || null,
    activeZoneName: activeZone?.name || null,
    nearestDistance:
      Number.isFinite(nearestDistance) ? Math.round(nearestDistance) : null,
    radius: activeZone?.radius ?? null,
    insideZone,
    alertType,
  });

  return {
    processed: true,
    previousStatus,
    currentStatus,
    activeZoneId: activeZone?.id || null,
    activeZoneName: activeZone?.name || null,
    nearestDistance:
      Number.isFinite(nearestDistance) ? Math.round(nearestDistance) : null,
    alertType,
  };
}

function detachDeviceListener(deviceId) {
  const currentListener = trackedDevices.get(deviceId);
  if (!currentListener) {
    return;
  }

  currentListener.ref.off("value", currentListener.callback);
  trackedDevices.delete(deviceId);

  console.info("[geofence-monitor.detach]", {
    deviceId,
    trackingKey: currentListener.trackingKey,
    childId: currentListener.childId,
  });
}

function attachDeviceListener(deviceId, registryData = {}) {
  const normalizedDeviceId = deviceId?.toString().trim() || "";
  const childId = registryData.child_id?.toString().trim() || "";
  const trackingKey = tryNormalizeTrackingKey(
    registryData.tracking_key || registryData.imei || normalizedDeviceId
  );

  if (!normalizedDeviceId || !childId || !trackingKey) {
    detachDeviceListener(normalizedDeviceId);
    return;
  }

  const currentListener = trackedDevices.get(normalizedDeviceId);
  if (
    currentListener &&
    currentListener.childId === childId &&
    currentListener.trackingKey === trackingKey
  ) {
    return;
  }

  detachDeviceListener(normalizedDeviceId);

  const ref = realtimeDB.ref(`live_tracking/${trackingKey}/location`);
  const callback = (snapshot) => {
    processLiveTrackingUpdate({
      childId,
      trackingKey,
      deviceId: normalizedDeviceId,
      snapshotValue: snapshot.val(),
    }).catch((error) => {
      console.error("[geofence-monitor.process] failed", {
        deviceId: normalizedDeviceId,
        childId,
        trackingKey,
        reason: error.message,
      });
    });
  };

  ref.on("value", callback);
  trackedDevices.set(normalizedDeviceId, {
    ref,
    callback,
    childId,
    trackingKey,
  });

  console.info("[geofence-monitor.attach]", {
    deviceId: normalizedDeviceId,
    childId,
    trackingKey,
    rtdbPath: `/live_tracking/${trackingKey}/location`,
  });
}

function initLiveGeofenceMonitor() {
  if (monitorInitialized) {
    return;
  }

  monitorInitialized = true;
  deviceRegistryRef = realtimeDB.ref("device_registry");
  safeZonesRef = realtimeDB.ref("safe_zones");

  deviceRegistryRef.on("child_added", (snapshot) => {
    attachDeviceListener(snapshot.key, snapshot.val() || {});
  });
  deviceRegistryRef.on("child_changed", (snapshot) => {
    attachDeviceListener(snapshot.key, snapshot.val() || {});
  });
  deviceRegistryRef.on("child_removed", (snapshot) => {
    detachDeviceListener(snapshot.key);
  });

  safeZonesRef.on("child_added", (snapshot) => {
    syncSafeZoneCache(snapshot.key, snapshot.val());
  });
  safeZonesRef.on("child_changed", (snapshot) => {
    syncSafeZoneCache(snapshot.key, snapshot.val());
  });
  safeZonesRef.on("child_removed", (snapshot) => {
    safeZoneCache.delete(snapshot.key);
  });

  console.info("[geofence-monitor.init] ready", {
    deviceRegistryPath: "/device_registry",
    safeZonesPath: "/safe_zones",
  });
}

module.exports = {
  initLiveGeofenceMonitor,
  processLiveTrackingUpdate,
};
