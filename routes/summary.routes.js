const router = require("express").Router();
const summary = require("../controllers/summary.controller");
const { requireAuthenticatedAccess } = require("../middleware/auth");

router.use(requireAuthenticatedAccess);

// Get Today's Summary
router.get("/today/:child_id", summary.today);

// Get Summary by Date
router.get("/:child_id/:date", summary.getByDate);

// Get Weekly Summary
router.get("/weekly/:child_id", summary.weekly);

// Get SOS Count
router.get("/sos-count/:child_id", summary.getSosCount);

// Get Zone Exit Count
router.get("/zone-exit-count/:child_id", summary.getZoneExitCount);

// Generate Daily Summary
router.post("/generate", summary.generateDailySummary);

module.exports = router;
