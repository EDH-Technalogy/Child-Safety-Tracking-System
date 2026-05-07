const gmailValidationError = 'Only Gmail addresses are allowed';
const strongPasswordValidationError =
    'Password must be at least 8 characters and include letters, numbers, and special characters';
const fullNameValidationError =
    'Name must be at least 2 characters long';
const otpValidationError = 'OTP must be 6 digits';
const imeiValidationError = 'IMEI must be at least 8 characters';

final gmailEmailRegex = RegExp(r'^[^\s@]+@gmail\.com$', caseSensitive: false);
final strongPasswordRegex =
    RegExp(r'^(?=.*[A-Za-z])(?=.*\d)(?=.*[@$!%*#?&]).{8,}$');
final otpRegex = RegExp(r'^\d{6}$');

String? validateRequiredInput(
  String? value, {
  required String requiredMessage,
}) {
  if ((value?.trim() ?? '').isEmpty) {
    return requiredMessage;
  }
  return null;
}

String? validateGmailEmailInput(
  String? value, {
  String requiredMessage = 'Email is required',
  String invalidMessage = gmailValidationError,
}) {
  final email = value?.trim() ?? '';
  if (email.isEmpty) {
    return requiredMessage;
  }
  if (!gmailEmailRegex.hasMatch(email)) {
    return invalidMessage;
  }
  return null;
}

String? validateStrongPasswordInput(
  String? value, {
  String requiredMessage = 'Password is required',
  String invalidMessage = strongPasswordValidationError,
}) {
  final password = value ?? '';
  if (password.isEmpty) {
    return requiredMessage;
  }
  if (!strongPasswordRegex.hasMatch(password)) {
    return invalidMessage;
  }
  return null;
}

String? validateFullNameInput(
  String? value, {
  String requiredMessage = 'Name is required',
  String invalidMessage = fullNameValidationError,
}) {
  final name = value?.trim() ?? '';
  if (name.isEmpty) {
    return requiredMessage;
  }
  if (name.length < 2) {
    return invalidMessage;
  }
  return null;
}

String? validateOtpInput(
  String? value, {
  String requiredMessage = 'OTP is required',
  String invalidMessage = otpValidationError,
}) {
  final otp = value?.trim() ?? '';
  if (otp.isEmpty) {
    return requiredMessage;
  }
  if (!otpRegex.hasMatch(otp)) {
    return invalidMessage;
  }
  return null;
}

String? validateAgeInput(
  String? value, {
  String requiredMessage = 'Age is required',
  String invalidMessage = 'Please enter a valid age (0-18)',
}) {
  final raw = value?.trim() ?? '';
  if (raw.isEmpty) {
    return requiredMessage;
  }
  final age = int.tryParse(raw);
  if (age == null || age < 0 || age > 18) {
    return invalidMessage;
  }
  return null;
}

String? validateImeiInput(
  String? value, {
  String requiredMessage = 'IMEI is required',
  String invalidMessage = imeiValidationError,
}) {
  final imei = value?.trim() ?? '';
  if (imei.isEmpty) {
    return requiredMessage;
  }
  if (imei.length < 8) {
    return invalidMessage;
  }
  return null;
}
