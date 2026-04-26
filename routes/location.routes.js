const router = require("express").Router();
const location = require("../controllers/location.controller");
const {
  attachOptionalAuth,
  requireAuthenticatedAccess,
} = require("../middleware/auth");

// Update Live Location
router.post("/update", attachOptionalAuth, location.updateLocation);

// Get Live Location
router.get("/live/:child_id", requireAuthenticatedAccess, location.getLiveLocation);

// Get Location History (all)
router.get("/history/:child_id", requireAuthenticatedAccess, location.getHistory);

// Get Location History by Date
router.get(
  "/history/:child_id/:date",
  requireAuthenticatedAccess,
  location.getHistoryByDate
);

// Get Route Line Data (for drawing route on map)
router.get(
  "/route/:child_id/:date",
  requireAuthenticatedAccess,
  location.getRouteData
);

module.exports = router;
