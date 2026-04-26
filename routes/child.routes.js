const router = require("express").Router();
const child = require("../controllers/child.controller");
const {
  requireAdminAccess,
  requireAuthenticatedAccess,
} = require("../middleware/auth");

router.use(requireAuthenticatedAccess);

// Add a new child
router.post("/add", child.addChild);

// Get all children for a user (Flutter calls: /api/children/{userId})
router.get("/:user_id", child.getChildren);

// Get a specific child by ID (Flutter calls: /api/children/child/{childId})
router.get("/child/:child_id", child.getChildById);

// Update child details (Flutter calls: /api/children/{childId})
router.put("/:child_id", child.updateChild);

// Remove a child (Flutter calls: /api/children/{childId})
router.delete("/:child_id", child.removeChild);

// Update child status (active/inactive)
router.patch("/:child_id/status", child.updateChildStatus);

// Get child with device info (Flutter calls: /api/children/device/{childId})
router.get("/device/:child_id", child.getChildWithDevice);

// Block child
router.patch("/block/:child_id", requireAdminAccess, child.blockChild);

// Unblock child
router.patch("/unblock/:child_id", requireAdminAccess, child.unblockChild);

module.exports = router;
