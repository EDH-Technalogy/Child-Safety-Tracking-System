const router = require("express").Router();
const device = require("../controllers/device.controller");
const { requireAuthenticatedAccess } = require("../middleware/auth");

router.use(requireAuthenticatedAccess);

// Register a new device
router.post("/register", device.registerDevice);

// Get device by ID (Flutter calls: /api/devices/{deviceId})
router.get("/:id", device.getDeviceById);

// Update device info (Flutter calls: PUT /api/devices/{deviceId})
router.put("/:id", device.updateDevice);

// Deactivate device (Flutter calls: PATCH /api/devices/deactivate/{deviceId})
router.put("/deactivate/:id", device.deactivate);
router.patch("/deactivate/:id", device.deactivate);

// Activate device (Flutter calls: PATCH /api/devices/activate/{deviceId})
router.put("/activate/:id", device.activate);
router.patch("/activate/:id", device.activate);

// Delete device (Flutter calls: DELETE /api/devices/{deviceId})
router.delete("/:id", device.deleteDevice);

// Get all devices (for admin)
router.get("/", device.getAllDevices);

// Get device by child ID (Flutter calls: /api/devices/child/{childId})
router.get("/child/:child_id", device.getDeviceByChildId);

module.exports = router;
