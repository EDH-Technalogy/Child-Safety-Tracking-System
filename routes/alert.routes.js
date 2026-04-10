const router = require("express").Router();
const alert = require("../controllers/alert.controller");
const { requireAuthenticatedAccess } = require("../middleware/auth");

// Send Alert (SOS / OUT_ZONE / LOW_BATTERY)
router.post("/send", alert.sendAlert);
router.post("/sos", alert.sosAlert);

// Get Child Alerts (Flutter calls: /api/alerts/{childId})
router.get("/:child_id", requireAuthenticatedAccess, alert.getAlerts);

// Mark Alert as Read (Flutter calls: /api/alerts/read/{alertId})
router.patch("/read/:alert_id", requireAuthenticatedAccess, alert.markAsRead);

// Mark All Alerts as Read (Flutter calls: /api/alerts/read-all/{childId})
router.patch(
  "/read-all/:child_id",
  requireAuthenticatedAccess,
  alert.markAllAsRead
);

// Get Unread Alerts Count (Flutter calls: /api/alerts/unread-count/{childId})
router.get(
  "/unread-count/:child_id",
  requireAuthenticatedAccess,
  alert.getUnreadCount
);

// Low Battery Alert
router.post("/low-battery", alert.lowBatteryAlert);

// Device Off Alert
router.post("/device-off", alert.deviceOffAlert);

// Device Online Alert
router.post("/device-online", alert.deviceOnlineAlert);

// Safe Zone Exit Alert
router.post("/zone-exit", alert.safeZoneExitAlert);

// Safe Zone Enter Alert
router.post("/zone-enter", alert.safeZoneEnterAlert);

module.exports = router;
