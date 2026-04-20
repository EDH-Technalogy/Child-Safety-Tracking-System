const { firestore, realtimeDB } = require("../firebase");
const {
  buildAlertMessage,
  buildLocationText,
  createAlertRecord,
} = require("./alert-service");

const trackedDevices = new Map();
let devicesUnsubscribe = null;
let monitorInitialized = false;

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

function normalizeTrackingKey(rawValue) {
  const originalValue = rawValue?.toString().trim() || "";
  if (!originalValue) {
    return "";
  }

  const decodedValue = originalValue.replace(/~2F/gi, "/");
  const liveTrackingMatch = decodedValue.match(/live_tracking\/([^/?#]+)/i);
  if (liveTrackingMatch?.[1]) {
    return liveTrackingMatch[1].trim();
  }

  return originalValue;
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
  return (
    parseNumber(rawLocation?.recorded_at) ??
    parseNumber(rawLocation?.timestamp) ??
    Date.now()
  );
}

async function processLiveTrackingUpdate({
  childId,
  trackingKey,
  snapshotValue = undefined,
}) {
  if (!childId || !trackingKey) {
    return {
      processed: false,
      reason: "missing_child_or_tracking_key",
    };
  }

  const rawLocation =
    snapshotValue && typeof snapshotValue === "object"
      ? snapshotValue
      : (
          await realtimeDB.ref(`live_tracking/${trackingKey}/location`).once("value")
        ).val();

  const latitude = parseCoordinate(rawLocation, "latitude", "lat");
  const longitude = parseCoordinate(rawLocation, "longitude", "lng");

  console.info("[geofence-monitor.location]", {
    childId,
    trackingKey,
    rtdbPath: `/live_tracking/${trackingKey}/location`,
    rawLocation,
  });

  if (!isValidCoordinate(latitude, longitude)) {
    return {
      processed: false,
      reason: "invalid_coordinates",
    };
  }

  const locationSequence = extractLocationSequence(rawLocation);
  const locationText = buildLocationText({
    locationText: rawLocation.location_text,
    area: rawLocation.area,
    address: rawLocation.address,
    latitude,
    longitude,
  });

  const stateRef = realtimeDB.ref(`live_tracking/${childId}/geofence`);
  const previousStateSnapshot = await stateRef.once("value");
  const previousState = previousStateSnapshot.val() || {};

  if (
    Number.isFinite(Number(previousState.last_processed_sequence)) &&
    Number(previousState.last_processed_sequence) >= locationSequence
  ) {
    return {
      processed: false,
      reason: "already_processed",
      previousStatus: previousState.status || "unknown",
    };
  }

  const safeZoneSnap = await firestore
    .collection("safe_zones")
    .where("child_id", "==", childId)
    .where("status", "==", "active")
    .get();

  if (safeZoneSnap.empty) {
    await stateRef.set({
      status: "no_zone",
      last_location_text: locationText,
      latitude,
      longitude,
      last_processed_sequence: locationSequence,
      updated_at: Date.now(),
    });

    return {
      processed: true,
      previousStatus: previousState.status || "unknown",
      currentStatus: "no_zone",
      alertType: null,
    };
  }

  let insideZone = false;
  let matchedZone = null;
  let nearestZone = null;
  let nearestDistance = Number.POSITIVE_INFINITY;

  safeZoneSnap.forEach((doc) => {
    const zone = { id: doc.id, ...doc.data() };
    const distance = calculateDistance(
      latitude,
      longitude,
      Number(zone.latitude),
      Number(zone.longitude)
    );

    if (distance < nearestDistance) {
      nearestDistance = distance;
      nearestZone = zone;
    }

    if (!insideZone && distance <= Number(zone.radius || 0)) {
      insideZone = true;
      matchedZone = zone;
    }
  });

  const currentStatus = insideZone ? "inside" : "outside";
  const activeZone = matchedZone || nearestZone;
  const previousStatus = previousState.status || "unknown";

  await stateRef.set({
    status: currentStatus,
    zone_id: activeZone?.id || null,
    zone_name: activeZone?.name || null,
    last_location_text: locationText,
    latitude,
    longitude,
    distance_to_zone_meters:
      Number.isFinite(nearestDistance) ? Math.round(nearestDistance) : null,
    last_processed_sequence: locationSequence,
    updated_at: Date.now(),
  });

  let alertType = null;
  if (currentStatus === "outside" && previousStatus !== "outside") {
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

    await createAlertRecord({
      childId,
      type: alertType,
      zoneName: activeZone?.name || null,
      locationText,
      latitude,
      longitude,
      message,
      extraFields: {
        source: "live_geofence_monitor",
        tracking_key: trackingKey,
      },
    });
  }

  console.info("[geofence-monitor.transition]", {
    childId,
    trackingKey,
    previousStatus,
    currentStatus,
    activeZoneId: activeZone?.id || null,
    activeZoneName: activeZone?.name || null,
    nearestDistance:
      Number.isFinite(nearestDistance) ? Math.round(nearestDistance) : null,
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

function attachDeviceListener(deviceDoc) {
  const deviceData = deviceDoc.data() || {};
  const childId = deviceData.child_id?.toString().trim() || "";
  const trackingKey =
    normalizeTrackingKey(deviceData.imei) ||
    normalizeTrackingKey(deviceDoc.id) ||
    "";

  if (!childId || !trackingKey) {
    detachDeviceListener(deviceDoc.id);
    return;
  }

  const currentListener = trackedDevices.get(deviceDoc.id);
  if (
    currentListener &&
    currentListener.childId === childId &&
    currentListener.trackingKey === trackingKey
  ) {
    return;
  }

  detachDeviceListener(deviceDoc.id);

  const ref = realtimeDB.ref(`live_tracking/${trackingKey}/location`);
  const callback = (snapshot) => {
    processLiveTrackingUpdate({
      childId,
      trackingKey,
      snapshotValue: snapshot.val(),
    }).catch((error) => {
      console.error("[geofence-monitor.process] failed", {
        childId,
        trackingKey,
        reason: error.message,
      });
    });
  };

  ref.on("value", callback);
  trackedDevices.set(deviceDoc.id, {
    ref,
    callback,
    childId,
    trackingKey,
  });

  console.info("[geofence-monitor.attach]", {
    deviceId: deviceDoc.id,
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
  devicesUnsubscribe = firestore.collection("devices").onSnapshot(
    (snapshot) => {
      snapshot.docChanges().forEach((change) => {
        if (change.type === "removed") {
          detachDeviceListener(change.doc.id);
          return;
        }

        attachDeviceListener(change.doc);
      });
    },
    (error) => {
      console.error("[geofence-monitor.devices] failed", {
        reason: error.message,
      });
    }
  );

  console.info("[geofence-monitor.init] ready");
}

module.exports = {
  initLiveGeofenceMonitor,
  processLiveTrackingUpdate,
};
