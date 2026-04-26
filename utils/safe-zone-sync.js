const { realtimeDB } = require("../firebase");

function buildSafeZoneMirrorPayload(zoneId, zoneData = {}) {
  const childId = zoneData.child_id?.toString().trim() || "";
  if (!zoneId || !childId) {
    return null;
  }

  return {
    id: zoneId.toString(),
    child_id: childId,
    child_name: zoneData.child_name?.toString().trim() || "",
    user_id: zoneData.user_id?.toString().trim() || "",
    name: zoneData.name?.toString().trim() || "",
    latitude: Number(zoneData.latitude) || 0,
    longitude: Number(zoneData.longitude) || 0,
    radius: Number(zoneData.radius) || 0,
    status: zoneData.status?.toString().trim() || "active",
    created_at: Number(zoneData.created_at) || Date.now(),
    updated_at:
      Number(zoneData.updated_at) ||
      Number(zoneData.created_at) ||
      Date.now(),
  };
}

async function upsertSafeZoneMirror(zoneId, zoneData = {}) {
  const payload = buildSafeZoneMirrorPayload(zoneId, zoneData);
  if (!payload) {
    return null;
  }

  await realtimeDB
    .ref(`safe_zones/${payload.child_id}/${payload.id}`)
    .set(payload);

  return payload;
}

async function removeSafeZoneMirror(zoneId, { childId = "" } = {}) {
  const normalizedZoneId = zoneId?.toString().trim() || "";
  const normalizedChildId = childId?.toString().trim() || "";
  if (!normalizedZoneId || !normalizedChildId) {
    return;
  }

  await realtimeDB
    .ref(`safe_zones/${normalizedChildId}/${normalizedZoneId}`)
    .remove();
}

module.exports = {
  buildSafeZoneMirrorPayload,
  upsertSafeZoneMirror,
  removeSafeZoneMirror,
};
