const { firestore } = require("../firebase");
const { getChildWithAccessOrThrow } = require("../utils/child-access");

async function listChildSummaryRecords(childId) {
  const snap = await firestore
    .collection("daily_summary")
    .where("child_id", "==", childId)
    .get();

  const summaries = [];
  snap.forEach((doc) => summaries.push({ id: doc.id, ...doc.data() }));
  return summaries;
}

async function listChildLocations(childId) {
  const snap = await firestore
    .collection("locations_history")
    .where("child_id", "==", childId)
    .get();

  const locations = [];
  snap.forEach((doc) => locations.push({ id: doc.id, ...doc.data() }));
  locations.sort((a, b) => (a.recorded_at || 0) - (b.recorded_at || 0));

  return locations;
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
    if (alert.type !== "OUT_ZONE") {
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

    const locations = (await listChildLocations(child_id)).filter((location) => {
      const recordedAt = location.recorded_at || 0;
      return recordedAt >= startOfDay.getTime() && recordedAt <= endOfDay.getTime();
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
        alert.type === "OUT_ZONE" &&
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
  const R = 6371000;
  const dLat = (lat2 - lat1) * Math.PI / 180;
  const dLon = (lon2 - lon1) * Math.PI / 180;
  const a = Math.sin(dLat/2) * Math.sin(dLat/2) + Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) * Math.sin(dLon/2) * Math.sin(dLon/2);
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a));
}
