const router = require("express").Router();
const conn = require("../controllers/connection.controller");

router.post("/update", conn.updateConnection);

module.exports = router;
