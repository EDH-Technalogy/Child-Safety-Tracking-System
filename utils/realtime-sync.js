const { realtimeDB } = require("../firebase");

async function syncRealtimeState(
  childId,
  { childStatus, deviceStatus, disabled, blocked, reason }
) {
  if (!childId) {
    return;
  }

  const updatedAt = Date.now();
  const updates = {};

  if (childStatus !== undefined) {
    updates[`live_tracking/${childId}/child_status`] = {
      status: childStatus,
      blocked: Boolean(blocked),
      updated_at: updatedAt,
    };
  }

  if (deviceStatus !== undefined) {
    updates[`live_tracking/${childId}/device_status`] = {
      status: deviceStatus,
      disabled: Boolean(disabled),
      blocked: Boolean(blocked),
      updated_at: updatedAt,
    };

    updates[`live_tracking/${childId}/connection`] = {
      status: deviceStatus,
      disabled: Boolean(disabled),
      blocked: Boolean(blocked),
      reason: reason || null,
      updated_at: updatedAt,
      time: updatedAt,
    };
  }

  if (Object.keys(updates).length === 0) {
    return;
  }

  await realtimeDB.ref().update(updates);
}

async function removeRealtimeState(childId) {
  if (!childId) {
    return;
  }

  await realtimeDB.ref(`live_tracking/${childId}`).remove();
}

module.exports = {
  syncRealtimeState,
  removeRealtimeState,
};
