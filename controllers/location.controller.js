const { realtimeDB } = require("../firebase");
const {
  createHttpError,
  ensureCanWriteChildEvent,
  getChildWithAccessOrThrow,
} = require("../utils/child-access");
const {
  buildAlertMessage,
  buildLocationText,
  createAlertRecord,
} = require("../utils/alert-service");
const {
  getResolvedLiveTrackingSnapshot,
  getTrackingContextForChild,
} = require("../utils/live-tracking");
const { normalizeRealtimeLocationTimestamps } = require("../utils/live-timestamp");
const {
  appendLocationHistory,
  listChildLocationHistory,
  parseTimezoneOffsetMinutes,
} = require("../utils/location-history");
const { listChildLogs } = require("../utils/child-logs");

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

function parseClientTimezoneOffsetMinutes(value) {
  return parseTimezoneOffsetMinutes(value);
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

    const accessResult = await ensureCanWriteChildEvent(req, childId);

    const latitude = parseCoordinate(req.body.latitude, "latitude");
    const longitude = parseCoordinate(req.body.longitude, "longitude");
    validateCoordinates(latitude, longitude);

    const speed = parseOptionalNumber(req.body.speed, 0);
    const accuracy = parseOptionalNumber(req.body.accuracy, 0);
    const heading = parseOptionalNumber(req.body.heading, 0);
    const altitude = parseOptionalNumber(req.body.altitude, 0);
    const battery = Math.max(0, Math.round(parseOptionalNumber(req.body.battery, 0)));
    const recordedAt =
      normalizeRealtimeLocationTimestamps(
        {
          timestamp: req.body.timestamp,
          recorded_at: req.body.recorded_at,
        },
        Date.now()
      ).normalizedRecordedAt;
    const locationText = buildLocationText({
      locationText: req.body.location_text,
      area: req.body.area,
      address: req.body.address,
      latitude,
      longitude,
    });

    const trackingContext = await getTrackingContextForChild(childId);
    const trackingKey = trackingContext?.trackingKey || childId;
    const rtdbPath = `live_tracking/${trackingKey}/location`;
    const rawLivePayload = {
      latitude,
      longitude,
      speed,
      battery,
      location_text: locationText,
      accuracy,
      heading,
      altitude,
      source: req.body.source?.toString().trim() || "device",
      recorded_at: recordedAt,
      timestamp: recordedAt,
    };
    const { payload: livePayload, rawTimestamp, rawRecordedAt } =
      normalizeRealtimeLocationTimestamps(rawLivePayload, recordedAt);

    const statusPath = `live_tracking/${trackingKey}/status`;
    const network =
      req.body.network?.toString().trim() ||
      req.body.network_status?.toString().trim() ||
      req.body.signal?.toString().trim() ||
      "unknown";
    await realtimeDB.ref().update({
      [rtdbPath]: livePayload,
      [statusPath]: {
        online: true,
        lastSeen: livePayload.recorded_at,
        deviceStatus: "active",
        network,
        updatedAt: livePayload.recorded_at,
        child_id: childId,
        tracking_key: trackingKey,
      },
    });

    console.info("[location.updateLocation.rtdb-write]", {
      childId,
      accessMode: accessResult.mode,
      resolvedDeviceId: accessResult.deviceId || null,
      resolvedTrackingKey: trackingKey,
      rtdbPath: `/${rtdbPath}`,
      rawIncomingTimestamp: req.body.timestamp ?? null,
      rawIncomingRecordedAt: req.body.recorded_at ?? null,
      rawTimestamp,
      rawRecordedAt,
      normalizedTimestamp: livePayload.timestamp,
      normalizedRecordedAt: livePayload.recorded_at,
      statusPath: `/${statusPath}`,
      payload: livePayload,
      timestamp: recordedAt,
    });

    const historyResult = await appendLocationHistory({
      childId,
      trackingKey,
      latitude,
      longitude,
      speed,
      battery,
      locationText,
      accuracy,
      heading,
      altitude,
      source: livePayload.source,
      recordedAt,
    });

    console.info("[location.updateLocation]", {
      childId,
      latitude,
      longitude,
      battery,
      locationText,
      historyDateKey: historyResult.dateKey,
      historyTimestamp: historyResult.timestamp,
    });

    console.info("[location.updateLocation.geofence]", {
      childId,
      trackingKey,
      status: "delegated_to_live_geofence_monitor",
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
    res.set("Cache-Control", "no-store");

    const liveTracking = await getResolvedLiveTrackingSnapshot(childId);

    if (!liveTracking?.location) {
      const failurePayload = {
        success: false,
        message: "No live location found for the linked tracking device.",
      };

      console.info("[location.getLiveLocation]", {
        childId,
        trackingKey: liveTracking?.trackingKey || null,
        rtdbPath: liveTracking?.rtdbPath || null,
        finalResponse: failurePayload,
      });

      return res.status(404).json(failurePayload);
    }

    const successPayload = {
      success: true,
      data: {
        latitude: liveTracking.location.latitude,
        longitude: liveTracking.location.longitude,
        speed: liveTracking.location.speed,
        battery: liveTracking.location.battery,
        recorded_at: liveTracking.location.recorded_at,
        latest_timestamp: liveTracking.latestTimestamp,
        source_key: liveTracking.trackingKey,
        rtdb_path: liveTracking.rtdbPath,
        status: liveTracking.latestStatus,
        signal: liveTracking.latestSignal,
      },
    };

    console.info("[location.getLiveLocation]", {
      childId,
      trackingKey: liveTracking.trackingKey,
      rtdbPath: liveTracking.rtdbPath,
      rawLocationPayload: liveTracking.raw?.location || null,
      finalResponse: successPayload,
    });

    return res.json(successPayload);
  } catch (error) {
    next(error);
  }
};

exports.getHistory = async (req, res, next) => {
  try {
    const childId = req.params.child_id?.toString().trim();
    await getChildWithAccessOrThrow(req, childId);

    const history = await listChildLocationHistory(childId, {
      timezoneOffsetMinutes: parseClientTimezoneOffsetMinutes(
        req.query.timezone_offset_minutes ?? req.query.timezoneOffsetMinutes
      ),
    });
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

    const history = await listChildLocationHistory(childId, {
      dateKey: req.params.date?.toString().trim(),
      timezoneOffsetMinutes: parseClientTimezoneOffsetMinutes(
        req.query.timezone_offset_minutes ?? req.query.timezoneOffsetMinutes
      ),
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
    const dateKey = req.params.date?.toString().trim();
    const timezoneOffsetMinutes = parseClientTimezoneOffsetMinutes(
      req.query.timezone_offset_minutes ?? req.query.timezoneOffsetMinutes
    );

    const locations = (await listChildLocationHistory(childId, {
      dateKey,
      timezoneOffsetMinutes,
    }))
      .map(({ id, ...data }) => data);
    const historyLogs = await listChildLogs(childId, {
      dateKey,
      timezoneOffsetMinutes,
    });

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
      selected_date: dateKey,
      timezone_offset_minutes: timezoneOffsetMinutes,
      coordinates,
      first_location_time: locations.length > 0 ? locations[0].recorded_at : null,
      last_location_time:
        locations.length > 0
          ? locations[locations.length - 1].recorded_at
          : null,
      total_distance_meters: Math.round(totalDistance),
      total_distance_km: (totalDistance / 1000).toFixed(2),
      location_count: locations.length,
      event_count: historyLogs.length,
      logs: historyLogs,
    });
  } catch (error) {
    next(error);
  }
};
