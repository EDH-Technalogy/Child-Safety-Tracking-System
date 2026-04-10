const { realtimeDB, firestore } = require("../firebase");
const {
  createHttpError,
  getChildOrThrow,
  getChildWithAccessOrThrow,
} = require("../utils/child-access");
const {
  buildAlertMessage,
  buildLocationText,
  createAlertRecord,
} = require("../utils/alert-service");

const SOS_ALERT_COOLDOWN_MS = 60000;

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

function parseCoordinate(value, fieldName) {
  const numericValue = Number(value);

  if (!Number.isFinite(numericValue)) {
    throw createHttpError(400, `${fieldName} must be a valid number`);
  }

  return numericValue;
}

function validateCoordinates(latitude, longitude) {
  if (latitude < -90 || latitude > 90) {
    throw createHttpError(400, "latitude must be between -90 and 90");
  }

  if (longitude < -180 || longitude > 180) {
    throw createHttpError(400, "longitude must be between -180 and 180");
  }
}

function parseOptionalNumber(value, fallbackValue = 0) {
  const numericValue = Number(value);
  return Number.isFinite(numericValue) ? numericValue : fallbackValue;
}

function parseBooleanFlag(...values) {
  return values.some((value) => {
    if (value === true || value === 1) {
      return true;
    }

    const normalizedValue = value?.toString().trim().toLowerCase();
    return normalizedValue === "true" || normalizedValue === "1";
  });
}

async function listChildLocationHistory(childId) {
  const snap = await firestore
    .collection("locations_history")
    .where("child_id", "==", childId)
    .get();

  const history = [];
  snap.forEach((doc) => history.push({ id: doc.id, ...doc.data() }));
  history.sort((a, b) => (a.recorded_at || 0) - (b.recorded_at || 0));

  return history;
}

async function evaluateSafeZoneTransition({
  childId,
  latitude,
  longitude,
  locationText,
}) {
  const safeZoneSnap = await firestore
    .collection("safe_zones")
    .where("child_id", "==", childId)
    .where("status", "==", "active")
    .get();

  const stateRef = realtimeDB.ref(`live_tracking/${childId}/geofence`);
  const previousStateSnapshot = await stateRef.once("value");
  const previousState = previousStateSnapshot.val() || {};

  if (safeZoneSnap.empty) {
    await stateRef.set({
      status: "no_zone",
      last_location_text: locationText,
      latitude,
      longitude,
      updated_at: Date.now(),
    });
    return {
      previousStatus: previousState.status || "unknown",
      currentStatus: "no_zone",
      activeZoneId: null,
      activeZoneName: null,
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

  await stateRef.set({
    status: currentStatus,
    zone_id: activeZone?.id || null,
    zone_name: activeZone?.name || null,
    last_location_text: locationText,
    latitude,
    longitude,
    updated_at: Date.now(),
  });

  const previousStatus = previousState.status || "unknown";

  console.info("[location.evaluateSafeZone]", {
    childId,
    latitude,
    longitude,
    previousStatus,
    currentStatus,
    activeZoneId: activeZone?.id || null,
    activeZoneName: activeZone?.name || null,
  });

  if (previousStatus === "inside" && currentStatus === "outside") {
    await createAlertRecord({
      childId,
      type: "OUT_ZONE",
      zoneName: activeZone?.name || null,
      locationText,
      latitude,
      longitude,
      message: buildAlertMessage({
        type: "OUT_ZONE",
        zoneName: activeZone?.name || null,
        locationText,
      }),
    });
  }

  if (previousStatus === "outside" && currentStatus === "inside") {
    await createAlertRecord({
      childId,
      type: "IN_ZONE",
      zoneName: matchedZone?.name || null,
      locationText,
      latitude,
      longitude,
      message: buildAlertMessage({
        type: "IN_ZONE",
        zoneName: matchedZone?.name || null,
        locationText,
      }),
    });
  }

  return {
    previousStatus,
    currentStatus,
    activeZoneId: activeZone?.id || null,
    activeZoneName: activeZone?.name || null,
  };
}

async function handleSosTrigger({
  childId,
  latitude,
  longitude,
  locationText,
}) {
  const sosStateRef = realtimeDB.ref(`live_tracking/${childId}/sos_state`);
  const sosStateSnapshot = await sosStateRef.once("value");
  const sosState = sosStateSnapshot.val() || {};
  const now = Date.now();

  if (
    sosState.last_alert_at &&
    now - Number(sosState.last_alert_at) < SOS_ALERT_COOLDOWN_MS
  ) {
    await sosStateRef.update({
      updated_at: now,
      last_location_text: locationText,
      latitude,
      longitude,
    });

    console.info("[location.handleSosTrigger] skipped duplicate", {
      childId,
      lastAlertAt: sosState.last_alert_at,
    });

    return;
  }

  await createAlertRecord({
    childId,
    type: "SOS",
    locationText,
    latitude,
    longitude,
    message: buildAlertMessage({
      type: "SOS",
      locationText,
    }),
  });

  await sosStateRef.set({
    last_alert_at: now,
    last_location_text: locationText,
    latitude,
    longitude,
    updated_at: now,
  });

  console.info("[location.handleSosTrigger] alert created", {
    childId,
    locationText,
  });
}

exports.updateLocation = async (req, res, next) => {
  try {
    const childId = req.body.child_id?.toString().trim();
    if (!childId) {
      throw createHttpError(400, "child_id is required");
    }

    await getChildOrThrow(childId);

    const latitude = parseCoordinate(req.body.latitude, "latitude");
    const longitude = parseCoordinate(req.body.longitude, "longitude");
    validateCoordinates(latitude, longitude);

    const speed = parseOptionalNumber(req.body.speed, 0);
    const battery = Math.max(0, Math.round(parseOptionalNumber(req.body.battery, 0)));
    const recordedAt = Date.now();
    const locationText = buildLocationText({
      locationText: req.body.location_text,
      area: req.body.area,
      address: req.body.address,
      latitude,
      longitude,
    });

    await realtimeDB.ref(`live_tracking/${childId}/location`).set({
      latitude,
      longitude,
      speed,
      battery,
      location_text: locationText,
      recorded_at: recordedAt,
    });

    await firestore.collection("locations_history").add({
      child_id: childId,
      latitude,
      longitude,
      speed,
      battery,
      location_text: locationText,
      recorded_at: recordedAt,
    });

    console.info("[location.updateLocation]", {
      childId,
      latitude,
      longitude,
      battery,
      locationText,
    });

    await evaluateSafeZoneTransition({
      childId,
      latitude,
      longitude,
      locationText,
    });

    const sosTriggered = parseBooleanFlag(
      req.body.sos,
      req.body.is_sos,
      req.body.emergency
    );

    if (sosTriggered) {
      await handleSosTrigger({
        childId,
        latitude,
        longitude,
        locationText,
      });
    }

    res.json({ message: "Location Updated Successfully" });
  } catch (error) {
    next(error);
  }
};

exports.getLiveLocation = async (req, res, next) => {
  try {
    const childId = req.params.child_id?.toString().trim();
    await getChildWithAccessOrThrow(req, childId);

    const snapshot = await realtimeDB
      .ref(`live_tracking/${childId}/location`)
      .once("value");

    res.json(snapshot.val() || {});
  } catch (error) {
    next(error);
  }
};

exports.getHistory = async (req, res, next) => {
  try {
    const childId = req.params.child_id?.toString().trim();
    await getChildWithAccessOrThrow(req, childId);

    const history = await listChildLocationHistory(childId);
    const recentHistory = history.reverse().slice(0, 100);

    res.json(recentHistory);
  } catch (error) {
    next(error);
  }
};

exports.getHistoryByDate = async (req, res, next) => {
  try {
    const childId = req.params.child_id?.toString().trim();
    await getChildWithAccessOrThrow(req, childId);

    const startDate = new Date(req.params.date);
    startDate.setHours(0, 0, 0, 0);
    const endDate = new Date(req.params.date);
    endDate.setHours(23, 59, 59, 999);

    const history = (await listChildLocationHistory(childId)).filter((entry) => {
      const recordedAt = entry.recorded_at || 0;
      return (
        recordedAt >= startDate.getTime() && recordedAt <= endDate.getTime()
      );
    });

    res.json(history);
  } catch (error) {
    next(error);
  }
};

exports.getRouteData = async (req, res, next) => {
  try {
    const childId = req.params.child_id?.toString().trim();
    await getChildWithAccessOrThrow(req, childId);

    const startDate = new Date(req.params.date);
    startDate.setHours(0, 0, 0, 0);
    const endDate = new Date(req.params.date);
    endDate.setHours(23, 59, 59, 999);

    const locations = (await listChildLocationHistory(childId))
      .filter((entry) => {
        const recordedAt = entry.recorded_at || 0;
        return (
          recordedAt >= startDate.getTime() && recordedAt <= endDate.getTime()
        );
      })
      .map(({ id, ...data }) => data);

    const coordinates = [];
    let totalDistance = 0;

    for (let index = 0; index < locations.length; index += 1) {
      const location = locations[index];
      coordinates.push({
        latitude: location.latitude,
        longitude: location.longitude,
        time: location.recorded_at,
      });

      if (index > 0) {
        totalDistance += calculateDistance(
          locations[index - 1].latitude,
          locations[index - 1].longitude,
          location.latitude,
          location.longitude
        );
      }
    }

    res.json({
      coordinates,
      first_location_time: locations.length > 0 ? locations[0].recorded_at : null,
      last_location_time:
        locations.length > 0
          ? locations[locations.length - 1].recorded_at
          : null,
      total_distance_meters: Math.round(totalDistance),
      total_distance_km: (totalDistance / 1000).toFixed(2),
      location_count: locations.length,
    });
  } catch (error) {
    next(error);
  }
};
