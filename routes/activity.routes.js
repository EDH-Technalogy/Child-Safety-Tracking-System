const router = require("express").Router();
const log = require("../controllers/activity.controller");
const { requireAuthenticatedAccess } = require("../middleware/auth");

router.post("/add", log.addLog);
router.get("/:child_id", requireAuthenticatedAccess, log.getLogs);

module.exports = router;
