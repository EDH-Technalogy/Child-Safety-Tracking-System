const router = require("express").Router();
const settings = require("../controllers/settings.controller");

router.get("/", settings.getSettings);
router.patch("/update", settings.updateSettings);

module.exports = router;
