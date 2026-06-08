const { admin, firestore } = require("../firebase");

function normalizeTokenList(value) {
  if (Array.isArray(value)) {
    return value
      .map((item) => item?.toString().trim() || "")
      .filter(Boolean);
  }

  if (typeof value === "string" && value.trim()) {
    return [value.trim()];
  }

  return [];
}

function alertTitle(type) {
  switch ((type || "").toString().trim().toUpperCase()) {
    case "OUT_ZONE":
    case "SAFE_ZONE_EXIT":
    case "ZONE_EXIT":
      return "Safe Zone Alert";
    case "IN_ZONE":
    case "SAFE_ZONE_ENTER":
    case "ZONE_ENTER":
      return "Safe Zone Return";
    case "SOS":
      return "SOS Alert";
    default:
      return "Child Alert";
  }
}

function isCriticalAlert(type) {
  switch ((type || "").toString().trim().toUpperCase()) {
    case "OUT_ZONE":
    case "SAFE_ZONE_EXIT":
    case "ZONE_EXIT":
    case "IN_ZONE":
    case "SAFE_ZONE_ENTER":
    case "ZONE_ENTER":
    case "SOS":
      return true;
    default:
      return false;
  }
}

async function lookupUserNotificationTokens(userId) {
  const normalizedUserId = userId?.toString().trim() || "";
  if (!normalizedUserId) {
    return [];
  }

  const userDoc = await firestore.collection("users").doc(normalizedUserId).get();
  if (!userDoc.exists) {
    return [];
  }

  const userData = userDoc.data() || {};
  return normalizeTokenList(
    userData.fcm_tokens ||
      userData.fcmTokens ||
      userData.notification_tokens ||
      userData.notificationTokens
  );
}

async function removeInvalidTokens(userId, tokens, response) {
  const invalidTokens = [];

  response.responses.forEach((item, index) => {
    if (item.success) {
      return;
    }

    const code = item.error?.code || "";
    if (
      code === "messaging/invalid-registration-token" ||
      code === "messaging/registration-token-not-registered"
    ) {
      invalidTokens.push(tokens[index]);
    }
  });

  if (invalidTokens.length === 0) {
    return;
  }

  try {
    const userRef = firestore.collection("users").doc(userId);
    const userDoc = await userRef.get();
    if (!userDoc.exists) {
      return;
    }

    const userData = userDoc.data() || {};
    const existingTokens = await lookupUserNotificationTokens(userId);
    const nextTokens = existingTokens.filter(
      (token) => !invalidTokens.includes(token)
    );

    await userRef.update({
      fcm_tokens: nextTokens,
      updated_at: Date.now(),
    });
  } catch (error) {
    console.error("[push.removeInvalidTokens] failed", {
      userId,
      reason: error.message,
    });
  }
}

async function sendAlertPush({
  userId,
  childId,
  childName,
  alertId,
  type,
  message,
}) {
  const tokens = await lookupUserNotificationTokens(userId);
  if (tokens.length === 0 || !isCriticalAlert(type)) {
    return;
  }

  const normalizedType = type.toString().trim().toUpperCase();
  try {
    const multicastMessage = {
      tokens,
      data: {
        alertId: alertId || "",
        type: normalizedType,
        childId: childId || "",
        childName: childName || "",
        body: message || "",
        title: alertTitle(normalizedType),
      },
      android: {
        priority: "high",
      },
      apns: {
        headers: {
          "apns-priority": "10",
        },
        payload: {
          aps: {
            contentAvailable: true,
          },
        },
      },
    };

    const response = await admin.messaging().sendEachForMulticast(
      multicastMessage
    );

    await removeInvalidTokens(userId, tokens, response);

    console.info("[push.sendAlertPush] completed", {
      userId,
      childId,
      alertId,
      type: normalizedType,
      tokenCount: tokens.length,
      successCount: response.successCount,
      failureCount: response.failureCount,
    });
  } catch (error) {
    console.error("[push.sendAlertPush] failed", {
      userId,
      childId,
      alertId,
      type: normalizedType,
      reason: error.message,
    });
  }
}

module.exports = {
  sendAlertPush,
};
