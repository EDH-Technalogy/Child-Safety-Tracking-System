const router = require("express").Router();
const conn = require("../controllers/connection.controller");
const { attachOptionalAuth } = require("../middleware/auth");

router.post("/update", attachOptionalAuth, conn.updateConnection);

module.exports = router;
