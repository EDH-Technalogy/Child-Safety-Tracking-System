const router = require("express").Router();
const user = require("../controllers/user.controller");
const {
  requireAdminAccess,
  requireAuthenticatedAccess,
} = require("../middleware/auth");

// Authentication routes
router.post("/register", user.register);
router.post("/login", user.login);
router.post("/verify-otp", user.verifyOtp);
router.post("/social-login", user.socialLogin);
router.post("/logout", user.logout);

// Password reset routes (Flutter calls these endpoints)
router.post("/request-password-reset", user.requestPasswordReset);
router.post("/verify-otp-reset", user.verifyOtpAndResetPassword);

// Firebase custom token for Realtime Database listeners
router.get("/firebase-token", requireAuthenticatedAccess, user.getFirebaseToken);
router.post("/:id/fcm-token", requireAuthenticatedAccess, user.registerFcmToken);
router.delete("/:id/fcm-token", requireAuthenticatedAccess, user.unregisterFcmToken);

// Profile routes (Flutter calls: /api/users/{userId})
router.get("/:id", requireAuthenticatedAccess, user.getProfile);
router.put("/:id", requireAuthenticatedAccess, user.updateProfile);
router.patch("/:id/password", requireAuthenticatedAccess, user.changePassword);

// User management routes
router.patch("/block/:id", requireAdminAccess, user.blockUser);
router.patch("/unblock/:id", requireAdminAccess, user.unblockUser);
router.delete("/:id", requireAuthenticatedAccess, user.deleteUser);
router.post("/test-user", requireAdminAccess, user.createTestUser);  // TEMP: Create test user

module.exports = router;
