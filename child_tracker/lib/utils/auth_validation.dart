const gmailValidationError = 'Only Gmail addresses are allowed';
const strongPasswordValidationError =
    'Password must be at least 8 characters and include letters, numbers, and special characters';

final gmailEmailRegex = RegExp(r'^[^\s@]+@gmail\.com$', caseSensitive: false);
final strongPasswordRegex =
    RegExp(r'^(?=.*[A-Za-z])(?=.*\d)(?=.*[@$!%*#?&]).{8,}$');

String? validateGmailEmailInput(
  String? value, {
  String requiredMessage = 'Email is required',
}) {
  final email = value?.trim() ?? '';
  if (email.isEmpty) {
    return requiredMessage;
  }
  if (!gmailEmailRegex.hasMatch(email)) {
    return gmailValidationError;
  }
  return null;
}

String? validateStrongPasswordInput(
  String? value, {
  String requiredMessage = 'Password is required',
}) {
  final password = value ?? '';
  if (password.isEmpty) {
    return requiredMessage;
  }
  if (!strongPasswordRegex.hasMatch(password)) {
    return strongPasswordValidationError;
  }
  return null;
}
