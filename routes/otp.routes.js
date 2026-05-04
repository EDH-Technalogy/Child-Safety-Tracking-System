const router = require("express").Router();
const rateLimit = require("express-rate-limit");
const otp = require("../controllers/otp.controller");

const otpRateLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: 5,
  standardHeaders: true,
  legacyHeaders: false,
  message: {
    error: "Too many OTP requests, please try again later",
    message: "Too many OTP requests, please try again later",
  },
});

router.post("/send-otp", otpRateLimiter, otp.sendOtp);
router.post("/verify-otp", otpRateLimiter, otp.verifyOtp);
router.post("/auth/send-otp", otpRateLimiter, otp.sendOtp);
router.post("/auth/verify-otp", otpRateLimiter, otp.verifyOtp);
router.post(
  "/auth/signup",
  otpRateLimiter,
  (req, _res, next) => {
    req.body = {
      ...(req.body || {}),
      type: "signup",
    };
    next();
  },
  otp.sendOtp
);

module.exports = router;
