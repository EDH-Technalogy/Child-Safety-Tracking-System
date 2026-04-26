const { firestore } = require("../firebase");
const { upsertDeviceRegistry } = require("./device-registry");
const { upsertSafeZoneMirror } = require("./safe-zone-sync");

async function syncRealtimeMirrorsFromFirestore() {
  const [childrenSnap, devicesSnap, safeZonesSnap] = await Promise.all([
    firestore.collection("children").get(),
    firestore.collection("devices").get(),
    firestore.collection("safe_zones").get(),
  ]);
  const childOwners = new Map(
    childrenSnap.docs.map((doc) => [doc.id, doc.data()?.user_id || ""])
  );

  let mirroredDevices = 0;
  let mirroredSafeZones = 0;

  for (const deviceDoc of devicesSnap.docs) {
    const deviceData = deviceDoc.data() || {};
    const mirrored = await upsertDeviceRegistry(deviceDoc.id, {
      ...deviceData,
      user_id: childOwners.get(deviceData.child_id) || deviceData.user_id || "",
    });
    if (mirrored) {
      mirroredDevices += 1;
    }
  }

  for (const zoneDoc of safeZonesSnap.docs) {
    const mirrored = await upsertSafeZoneMirror(zoneDoc.id, zoneDoc.data());
    if (mirrored) {
      mirroredSafeZones += 1;
    }
  }

  console.info("[realtime-bootstrap.sync]", {
    mirroredDevices,
    mirroredSafeZones,
  });

  return {
    mirroredDevices,
    mirroredSafeZones,
  };
}

module.exports = {
  syncRealtimeMirrorsFromFirestore,
};
