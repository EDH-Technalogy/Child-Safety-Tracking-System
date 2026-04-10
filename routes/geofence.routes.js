const router = require("express").Router();
const geofence = require("../controllers/geofence.controller");
const {
  requireAuthenticatedAccess,
  requireAdminAccess,
} = require("../middleware/auth");

// Create a new safe zone (Flutter calls: POST /api/geofence/safe-zone)
router.post("/safe-zone", requireAuthenticatedAccess, geofence.createSafeZone);

// Get all authorized safe zones, optionally filtered by child name/child id
router.get("/safe-zones", requireAuthenticatedAccess, geofence.searchSafeZones);

// Get all safe zones for a child (Flutter calls: GET /api/geofence/safe-zones/{childId})
router.get(
  "/safe-zones/:child_id",
  requireAuthenticatedAccess,
  geofence.getSafeZones
);

// Update a safe zone (Flutter calls: PUT /api/geofence/safe-zone/{zoneId})
router.put(
  "/safe-zone/:zone_id",
  requireAuthenticatedAccess,
  geofence.updateSafeZone
);

// Delete a safe zone (Flutter calls: DELETE /api/geofence/safe-zone/{zoneId})
router.delete(
  "/safe-zone/:zone_id",
  requireAuthenticatedAccess,
  geofence.deleteSafeZone
);

// Check if a location is in a safe zone (Flutter calls: POST /api/geofence/check-location)
router.post(
  "/check-location",
  requireAuthenticatedAccess,
  geofence.checkLocation
);

// Get default settings
router.get("/settings", requireAdminAccess, geofence.getDefaultSettings);

// Update default settings
router.put("/settings", requireAdminAccess, geofence.updateDefaultSettings);

module.exports = router;
