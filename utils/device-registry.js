const { realtimeDB } = require("../firebase");
const { tryNormalizeTrackingKey } = require("./tracking-key-normalizer");

function buildDeviceRegistryPayload(deviceId, deviceData = {}) {
  const normalizedDeviceId = deviceId?.toString().trim() || "";
  const childId = deviceData.child_id?.toString().trim() || "";
  const trackingKey =
    tryNormalizeTrackingKey(deviceData.tracking_key) ||
    tryNormalizeTrackingKey(deviceData.imei) ||
    tryNormalizeTrackingKey(normalizedDeviceId);

  if (!normalizedDeviceId || !childId || !trackingKey) {
    return null;
  }

  const updatedAt =
    Number(deviceData.updated_at) ||
    Number(deviceData.created_at) ||
    Date.now();

  return {
    device_id: normalizedDeviceId,
    child_id: childId,
    user_id: deviceData.user_id?.toString().trim() || "",
    imei: deviceData.imei?.toString().trim() || "",
    tracking_key: trackingKey,
    status: deviceData.status?.toString().trim() || "offline",
    is_disabled: Boolean(deviceData.is_disabled),
    disabled_by_child_block: Boolean(deviceData.disabled_by_child_block),
    created_at: Number(deviceData.created_at) || updatedAt,
    updated_at: updatedAt,
  };
}

async function upsertDeviceRegistry(deviceId, deviceData = {}) {
  let mergedDeviceData = { ...deviceData };
  const needsExistingContext =
    !mergedDeviceData.child_id ||
    !mergedDeviceData.user_id ||
    !(
      tryNormalizeTrackingKey(mergedDeviceData.tracking_key) ||
      tryNormalizeTrackingKey(mergedDeviceData.imei) ||
      tryNormalizeTrackingKey(deviceId)
    );

  if (needsExistingContext) {
    const existingSnapshot = await realtimeDB
      .ref(`device_registry/${deviceId}`)
      .once("value");
    const existingData = existingSnapshot.val();
    if (existingData && typeof existingData === "object") {
      mergedDeviceData = {
        ...existingData,
        ...mergedDeviceData,
      };
    }
  }

  const payload = buildDeviceRegistryPayload(deviceId, mergedDeviceData);
  if (!payload) {
    return null;
  }

  await realtimeDB.ref().update({
    [`device_registry/${payload.device_id}`]: payload,
    [`device_registry_by_child/${payload.child_id}`]: payload,
    [`device_registry_by_tracking_key/${payload.tracking_key}`]: payload,
  });

  return payload;
}

async function removeDeviceRegistry(deviceId, { childId = null } = {}) {
  const normalizedDeviceId = deviceId?.toString().trim() || "";
  if (!normalizedDeviceId) {
    return;
  }

  const snapshot = await realtimeDB
    .ref(`device_registry/${normalizedDeviceId}`)
    .once("value");
  const existingPayload = snapshot.val() || {};
  let resolvedChildId = childId?.toString().trim() || "";
  const resolvedTrackingKey =
    existingPayload.tracking_key?.toString().trim() || "";
  if (!resolvedChildId) {
    resolvedChildId = existingPayload.child_id?.toString().trim() || "";
  }

  const updates = {
    [`device_registry/${normalizedDeviceId}`]: null,
  };

  if (resolvedChildId) {
    updates[`device_registry_by_child/${resolvedChildId}`] = null;
  }
  if (resolvedTrackingKey) {
    updates[`device_registry_by_tracking_key/${resolvedTrackingKey}`] = null;
  }

  await realtimeDB.ref().update(updates);
}

module.exports = {
  buildDeviceRegistryPayload,
  upsertDeviceRegistry,
  removeDeviceRegistry,
};
