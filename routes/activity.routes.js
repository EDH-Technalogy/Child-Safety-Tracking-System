const router = require("express").Router();
const log = require("../controllers/activity.controller");

router.post("/add", log.addLog);
router.get("/:child_id", log.getLogs);

module.exports = router;
