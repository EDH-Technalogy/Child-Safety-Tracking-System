const otpService = require("../services/otp.service");

function sendJsonError(res, error) {
  const message = error.message || "OTP request failed";
  return res.status(error.status || 500).json({
    error: message,
    message,
  });
}

exports.sendOtp = async (req, res) => {
  try {
    const result = await otpService.sendOtp(req.body || {});
    res.json(result);
  } catch (error) {
    sendJsonError(res, error);
  }
};

exports.verifyOtp = async (req, res) => {
  try {
    const result = await otpService.verifyOtp(req.body || {});
    res.json(result);
  } catch (error) {
    sendJsonError(res, error);
  }
};
