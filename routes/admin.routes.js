const router = require("express").Router();
const admin = require("../controllers/admin.controller");
const child = require("../controllers/child.controller");
const device = require("../controllers/device.controller");
const {
  requireAdminAccess,
  allowBootstrapOrAdminAccess,
} = require("../middleware/auth");

// Admin Authentication
router.post("/login", admin.adminLogin);
router.post("/create-admin", allowBootstrapOrAdminAccess, admin.createAdmin);
router.use(requireAdminAccess);
router.post("/logout", admin.adminLogout);
router.get("/profile", admin.getAdminProfile);
router.put("/profile", admin.updateAdminProfile);
router.patch("/profile", admin.updateAdminProfile);
router.get("/admins", admin.getAllAdmins);
router.delete("/admins/:id", admin.deleteAdmin);

// User Management
router.get("/users", admin.getAllUsers);
router.post("/users", admin.createUser);
router.put("/users/:id", admin.updateUser);
router.patch("/users/:id", admin.updateUser);
router.put("/blockUser/:id", admin.blockUser);
router.patch("/blockUser/:id", admin.blockUser);
router.put("/unblockUser/:id", admin.unblockUser);
router.patch("/unblockUser/:id", admin.unblockUser);
router.delete("/users/:id", admin.deleteUser);

// Device Management
router.get("/devices", device.getAllDevices);
router.post("/devices", device.registerDevice);
router.put("/devices/:id", device.updateDevice);
router.patch("/devices/:id", device.updateDevice);
router.put("/deviceOff/:id", device.deactivate);
router.patch("/deviceOff/:id", device.deactivate);
router.put("/deviceOn/:id", device.activate);
router.patch("/deviceOn/:id", device.activate);
router.delete("/devices/:id", device.deleteDevice);

// Statistics
router.get("/stats/active-users", admin.getTotalActiveUsers);
router.get("/stats/total-devices", admin.getTotalDevices);
router.get("/stats/active-devices", admin.getActiveDevices);
router.get("/stats/daily-active-devices/:date", admin.dailyActiveDevices);
router.get("/stats/daily-active-devices", admin.dailyActiveDevices);
router.get("/stats/system", admin.getSystemStats);

// Children Management
router.get("/children", child.getAllChildren);
router.post("/children", child.addChild);
router.put("/children/:child_id", child.updateChild);
router.patch("/children/:child_id", child.updateChild);
router.patch("/children/:child_id/status", child.updateChildStatus);
router.put("/children/block/:child_id", child.blockChild);
router.patch("/children/block/:child_id", child.blockChild);
router.put("/children/unblock/:child_id", child.unblockChild);
router.patch("/children/unblock/:child_id", child.unblockChild);
router.delete("/children/:child_id", child.removeChild);

// Alerts Management
router.get("/alerts", admin.getAllAlerts);
router.delete("/alerts/:id", admin.deleteAlert);

  // System
  router.get("/logs", admin.getSystemLogs);
  router.delete("/logs", admin.deleteAllSystemLogs);
  router.delete("/logs/:id", admin.deleteSystemLog);
  router.get("/firmware-versions", admin.getFirmwareVersions);

  module.exports = router;
