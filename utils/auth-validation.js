const PASSWORD_VALIDATION_ERROR =
  "Password must be at least 8 characters and include letters, numbers, and special characters";
const GMAIL_VALIDATION_ERROR = "Only Gmail addresses are allowed";
const passwordRegex = /^(?=.*[A-Za-z])(?=.*\d)(?=.*[@$!%*#?&]).{8,}$/;
const emailRegex = /^[^\s@]+@gmail\.com$/i;

function createHttpError(status, message) {
  const error = new Error(message);
  error.status = status;
  return error;
}

function normalizeEmail(email) {
  return email?.toString().trim().toLowerCase() || "";
}

function validateGmailEmail(email) {
  const normalizedEmail = normalizeEmail(email);
  if (!emailRegex.test(normalizedEmail)) {
    throw createHttpError(400, GMAIL_VALIDATION_ERROR);
  }
  return normalizedEmail;
}

function validateStrongPassword(password) {
  const normalizedPassword = password?.toString() || "";
  if (!passwordRegex.test(normalizedPassword)) {
    throw createHttpError(400, PASSWORD_VALIDATION_ERROR);
  }
}

module.exports = {
  GMAIL_VALIDATION_ERROR,
  PASSWORD_VALIDATION_ERROR,
  createHttpError,
  emailRegex,
  normalizeEmail,
  passwordRegex,
  validateGmailEmail,
  validateStrongPassword,
};
