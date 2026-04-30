const { firestore } = require("../firebase");
const { getChildWithAccessOrThrow } = require("../utils/child-access");
const {
  buildDateKey,
  listChildLocationHistory,
} = require("../utils/location-history");
const {
  readChildLogsBucket,
  readConnectionEventsBucket,
} = require("../utils/child-logs");
const {
  getTrackingContextForChild,
  getResolvedLiveTrackingSnapshot,
} = require("../utils/live-tracking");

const LAST_24_HOURS_MS = 24 * 60 * 60 * 1000;
// Ignore obvious GPS spikes that would imply implausible ground travel.
const MAX_REASONABLE_SPEED_MPS = 120;

async function listChildSummaryRecords(childId) {
  const snap = await firestore
    .collection("daily_summary")
    .where("child_id", "==", childId)
    .get();

  const summaries = [];
  snap.forEach((doc) => summaries.push({ id: doc.id, ...doc.data() }));
  return summaries;
}

async function listChildAlerts(childId) {
  const snap = await firestore
    .collection("alerts")
    .where("child_id", "==", childId)
    .get();

  const alerts = [];
  snap.forEach((doc) => alerts.push({ id: doc.id, ...doc.data() }));
  return alerts;
}

function isWithinWindow(timestamp, startTimestamp, endTimestamp) {
  return (
    Number.isFinite(Number(timestamp)) &&
    Number(timestamp) >= startTimestamp &&
    Number(timestamp) <= endTimestamp
  );
}

function normalizeConnectionState(value) {
  const normalized = value?.toString().trim().toLowerCase() || "";
  if (normalized === "offline" || normalized === "disconnected") {
    return "offline";
  }

  if (
    normalized === "online" ||
    normalized === "connected" ||
    normalized === "active" ||
    normalized === "delayed"
  ) {
    return "online";
  }

  return "unknown";
}

function uniqueDateKeys(...timestamps) {
  return [...new Set(timestamps.map((value) => buildDateKey(value)))];
}

function dedupeById(items = [], idResolver) {
  const seen = new Set();
  const deduped = [];

  items.forEach((item) => {
    const key = idResolver(item);
    if (!key || seen.has(key)) {
      return;
    }

    seen.add(key);
    deduped.push(item);
  });

  return deduped;
}

function calculateDistanceMeters(lat1, lon1, lat2, lon2) {
  const R = 6371000;
  const dLat = ((lat2 - lat1) * Math.PI) / 180;
  const dLon = ((lon2 - lon1) * Math.PI) / 180;
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos((lat1 * Math.PI) / 180) *
      Math.cos((lat2 * Math.PI) / 180) *
      Math.sin(dLon / 2) *
      Math.sin(dLon / 2);
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

function calculateDistanceKm(locations = []) {
  const sortedLocations = [...locations].sort(
    (a, b) => (a.recorded_at || 0) - (b.recorded_at || 0)
  );

  let totalMeters = 0;

  for (let index = 1; index < sortedLocations.length; index += 1) {
    const previous = sortedLocations[index - 1];
    const current = sortedLocations[index];
    const timeDeltaMs = (current.recorded_at || 0) - (previous.recorded_at || 0);

    if (timeDeltaMs <= 0) {
      continue;
    }

    const distanceMeters = calculateDistanceMeters(
      previous.latitude,
      previous.longitude,
      current.latitude,
      current.longitude
    );
    const speedMps = distanceMeters / (timeDeltaMs / 1000);
    if (speedMps > MAX_REASONABLE_SPEED_MPS) {
      continue;
    }

    totalMeters += distanceMeters;
  }

  return Number((totalMeters / 1000).toFixed(2));
}

async function loadLast24HourLocations(childId, dateKeys, startTimestamp, endTimestamp) {
  const locationBuckets = await Promise.all(
    dateKeys.map((dateKey) => listChildLocationHistory(childId, { dateKey }))
  );

  const locations = locationBuckets
    .flatMap((bucket) => bucket)
    .filter((entry) =>
      isWithinWindow(entry.recorded_at || entry.timestamp, startTimestamp, endTimestamp)
    )
    .sort((a, b) => (a.recorded_at || 0) - (b.recorded_at || 0));

  return dedupeById(
    locations,
    (entry) =>
      [
        entry.tracking_key || "",
        entry.recorded_at || 0,
        Number(entry.latitude || 0).toFixed(6),
        Number(entry.longitude || 0).toFixed(6),
      ].join("|")
  );
}

async function loadLast24HourChildLogs(childId, dateKeys, startTimestamp, endTimestamp) {
  const logBuckets = await Promise.all(
    dateKeys.map((dateKey) => readChildLogsBucket(childId, dateKey))
  );

  const logs = logBuckets
    .flatMap((bucket) => bucket)
    .filter((log) => isWithinWindow(log.timestamp, startTimestamp, endTimestamp));

  return dedupeById(
    logs,
    (log) => `${log.id || ""}|${log.type || ""}|${log.timestamp || 0}`
  );
}

async function loadLast24HourConnectionEvents(
  childId,
  dateKeys,
  startTimestamp,
  endTimestamp
) {
  const eventBuckets = await Promise.all(
    dateKeys.map((dateKey) => readConnectionEventsBucket(childId, dateKey))
  );

  const events = eventBuckets.flatMap((bucket) => bucket);
  return dedupeById(
    events.filter((event) => {
      if (event.type === "DEVICE_DISCONNECTED") {
        return isWithinWindow(
          event.metadata?.disconnectedAt ?? event.timestamp,
          startTimestamp,
          endTimestamp
        );
      }

      if (event.type === "DEVICE_RECONNECTED") {
        return isWithinWindow(
          event.metadata?.reconnectedAt ?? event.timestamp,
          startTimestamp,
          endTimestamp
        );
      }

      return isWithinWindow(event.timestamp, startTimestamp, endTimestamp);
    }),
    (event) => event.metadata?.eventId || event.id || `${event.type}|${event.timestamp || 0}`
  );
}

// Get Today's Summary
exports.today = async (req,res)=>{
  await getChildWithAccessOrThrow(req, req.params.child_id);
  const today=new Date().toISOString().slice(0,10);

  const snap = await firestore.collection("daily_summary")
    .where("child_id","==",req.params.child_id)
    .where("date","==",today)
    .get();

  if(snap.empty) return res.send({});

  res.send(snap.docs[0].data());
};

// Get Summary by Date
exports.getByDate = async (req,res)=>{
  const { child_id, date } = req.params;
  await getChildWithAccessOrThrow(req, child_id);

  const snap = await firestore.collection("daily_summary")
    .where("child_id","==",child_id)
    .where("date","==",date)
    .get();

  if(snap.empty) return res.send({});

  res.send(snap.docs[0].data());
};

// Get Weekly Summary
exports.weekly = async (req,res)=>{
  const { child_id } = req.params;
  await getChildWithAccessOrThrow(req, child_id);
  const today = new Date();
  const weekAgo = new Date(today.getTime() - 7 * 24 * 60 * 60 * 1000);

  const list = (await listChildSummaryRecords(child_id))
    .filter((day) => (day.date || "") >= weekAgo.toISOString().slice(0,10))
    .map(({ id, ...data }) => data)
    .sort((a, b) => String(b.date || "").localeCompare(String(a.date || "")));

  // Calculate totals
  let totalDistance = 0;
  let totalSosCount = 0;
  let totalZoneExitCount = 0;

  list.forEach(day => {
    totalDistance += parseFloat(day.total_distance_km || 0);
    totalSosCount += day.sos_count || 0;
    totalZoneExitCount += day.zone_exit_count || 0;
  });

  res.send({
    days: list,
    total_distance_km: totalDistance.toFixed(2),
    total_sos_count: totalSosCount,
    total_zone_exit_count: totalZoneExitCount,
    days_tracked: list.length
  });
};

exports.last24Hours = async (req, res, next) => {
  try {
    const childId = req.params.child_id?.toString().trim();
    const { childDoc } = await getChildWithAccessOrThrow(req, childId);
    const childData = childDoc.data() || {};
    const now = Date.now();
    const fromTime = now - LAST_24_HOURS_MS;
    const dateKeys = uniqueDateKeys(fromTime, now);

    const [trackingContext, liveSnapshot, locations, childLogs, connectionEvents] =
      await Promise.all([
        getTrackingContextForChild(childId),
        getResolvedLiveTrackingSnapshot(childId),
        loadLast24HourLocations(childId, dateKeys, fromTime, now),
        loadLast24HourChildLogs(childId, dateKeys, fromTime, now),
        loadLast24HourConnectionEvents(childId, dateKeys, fromTime, now),
      ]);

    const safeZoneExitCount = childLogs.filter(
      (log) => log.type === "GEOFENCE_BREACH"
    ).length;
    const safeZoneReturnCount = childLogs.filter(
      (log) => log.type === "GEOFENCE_RETURN"
    ).length;
    const deviceDisconnectCount =
      connectionEvents.filter((event) => event.type === "DEVICE_DISCONNECTED")
        .length ||
      childLogs.filter((log) => log.type === "DEVICE_DISCONNECTED").length;
    const deviceReconnectCount =
      connectionEvents.filter((event) => event.type === "DEVICE_RECONNECTED")
        .length ||
      childLogs.filter((log) => log.type === "DEVICE_RECONNECTED").length;

    const latestLocationFromWindow =
      locations.length > 0 ? locations[locations.length - 1].recorded_at : null;
    const liveLocationTimestamp =
      liveSnapshot?.location?.recorded_at || liveSnapshot?.location?.timestamp || null;
    const lastLocationUpdateAt =
      [liveLocationTimestamp, latestLocationFromWindow]
        .filter((value) => Number.isFinite(Number(value)))
        .sort((a, b) => Number(b) - Number(a))[0] ??
      liveSnapshot?.latestTimestamp ??
      null;

    res.json({
      childId,
      childName: childData.name?.toString().trim() || "",
      parentUserId: childData.user_id?.toString().trim() || "",
      trackingKey: trackingContext?.trackingKey?.toString().trim() || "",
      fromTime,
      toTime: now,
      distanceKm: calculateDistanceKm(locations),
      locationPointsCount: locations.length,
      safeZoneExitCount,
      safeZoneReturnCount,
      deviceDisconnectCount,
      deviceReconnectCount,
      lastLocationUpdateAt,
      currentConnectionState: normalizeConnectionState(liveSnapshot?.latestStatus),
      generatedAt: now,
    });
  } catch (error) {
    next(error);
  }
};

// Get SOS Count
exports.getSosCount = async (req,res)=>{
  const { child_id } = req.params;
  await getChildWithAccessOrThrow(req, child_id);
  const { start_date, end_date } = req.query;
  const alerts = (await listChildAlerts(child_id)).filter((alert) => {
    if (alert.type !== "SOS") {
      return false;
    }

    if (start_date && end_date) {
      const createdAt = alert.created_at || 0;
      const startTimestamp = new Date(start_date).getTime();
      const endTimestamp = new Date(end_date).getTime();
      return createdAt >= startTimestamp && createdAt <= endTimestamp;
    }

    return true;
  });

  res.send({ count: alerts.length });
};

// Get Zone Exit Count
exports.getZoneExitCount = async (req,res)=>{
  const { child_id } = req.params;
  await getChildWithAccessOrThrow(req, child_id);
  const { start_date, end_date } = req.query;
  const alerts = (await listChildAlerts(child_id)).filter((alert) => {
    if (!["OUT_ZONE", "SAFE_ZONE_EXIT", "ZONE_EXIT"].includes(alert.type)) {
      return false;
    }

    if (start_date && end_date) {
      const createdAt = alert.created_at || 0;
      const startTimestamp = new Date(start_date).getTime();
      const endTimestamp = new Date(end_date).getTime();
      return createdAt >= startTimestamp && createdAt <= endTimestamp;
    }

    return true;
  });

  res.send({ count: alerts.length });
};

// Generate Daily Summary
exports.generateDailySummary = async (req,res)=>{
  try {
    const { child_id, date } = req.body;
    await getChildWithAccessOrThrow(req, child_id);
    const targetDate = date || new Date().toISOString().slice(0,10);

    // Get locations for the day
    const startOfDay = new Date(targetDate);
    startOfDay.setHours(0,0,0,0);
    const endOfDay = new Date(targetDate);
    endOfDay.setHours(23,59,59,999);

    const locations = await listChildLocationHistory(child_id, {
      dateKey: buildDateKey(startOfDay.getTime()),
    });

    if (locations.length === 0) {
      return res.status(404).send("No locations found for this date");
    }

    // Calculate total distance
    let totalDistance = 0;
    for (let i = 1; i < locations.length; i++) {
      const prev = locations[i-1];
      const curr = locations[i];
      totalDistance += calculateDistance(prev.latitude, prev.longitude, curr.latitude, curr.longitude);
    }

    const alerts = await listChildAlerts(child_id);
    const sosCount = alerts.filter((alert) => {
      const createdAt = alert.created_at || 0;
      return (
        alert.type === "SOS" &&
        createdAt >= startOfDay.getTime() &&
        createdAt <= endOfDay.getTime()
      );
    }).length;
    const zoneExitCount = alerts.filter((alert) => {
      const createdAt = alert.created_at || 0;
      return (
        ["OUT_ZONE", "SAFE_ZONE_EXIT", "ZONE_EXIT"].includes(alert.type) &&
        createdAt >= startOfDay.getTime() &&
        createdAt <= endOfDay.getTime()
      );
    }).length;

    // Save summary
    const summary = await firestore.collection("daily_summary").add({
      child_id,
      date: targetDate,
      first_location_time: locations[0].recorded_at,
      last_location_time: locations[locations.length-1].recorded_at,
      total_distance_km: (totalDistance / 1000).toFixed(2),
      total_distance_meters: Math.round(totalDistance),
      location_count: locations.length,
      sos_count: sosCount,
      zone_exit_count: zoneExitCount,
      created_at: Date.now()
    });

    res.send({ summary_id: summary.id, message: "Daily summary generated" });
  } catch (error) {
    res.status(500).send(error.message);
  }
};

function calculateDistance(lat1, lon1, lat2, lon2) {
  return calculateDistanceMeters(lat1, lon1, lat2, lon2);
}
