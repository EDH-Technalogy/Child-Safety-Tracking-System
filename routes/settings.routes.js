const router = require("express").Router();
const settings = require("../controllers/settings.controller");
const {
  requireAdminAccess,
  requireAuthenticatedAccess,
} = require("../middleware/auth");

router.get("/", requireAuthenticatedAccess, settings.getSettings);
router.patch("/update", requireAdminAccess, settings.updateSettings);

module.exports = router;
