const { firestore } = require("../firebase");
const {
  appendLocationHistory,
} = require("../utils/location-history");
const { getTrackingContextForChild } = require("../utils/live-tracking");

async function migrateLocationsHistory() {
  const snapshot = await firestore.collection("locations_history").get();
  let migratedCount = 0;
  let skippedCount = 0;

  for (const doc of snapshot.docs) {
    const data = doc.data() || {};
    const childId = data.child_id?.toString().trim() || "";
    const recordedAt = Number(data.recorded_at) || 0;

    if (!childId || recordedAt <= 0) {
      skippedCount += 1;
      continue;
    }

    const trackingContext = await getTrackingContextForChild(childId);
    const trackingKey =
      trackingContext?.trackingKey?.toString().trim() || childId;

    await appendLocationHistory({
      childId,
      trackingKey,
      latitude: data.latitude,
      longitude: data.longitude,
      speed: data.speed,
      battery: data.battery,
      locationText: data.location_text,
      accuracy: data.accuracy,
      heading: data.heading,
      altitude: data.altitude,
      recordedAt,
    });
    migratedCount += 1;
  }

  console.info("[migrate.locations_history_to_rtdb] complete", {
    totalDocuments: snapshot.size,
    migratedCount,
    skippedCount,
  });
}

migrateLocationsHistory()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("[migrate.locations_history_to_rtdb] failed", {
      reason: error.message,
    });
    process.exit(1);
  });
