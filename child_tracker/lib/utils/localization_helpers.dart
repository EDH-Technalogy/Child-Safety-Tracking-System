import 'package:flutter/widgets.dart';

import '../l10n/app_localizations.dart';

extension BuildContextL10n on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this)!;
}

String localizeErrorMessage(AppLocalizations l10n, Object error) {
  final raw = error.toString().replaceFirst('Exception: ', '').trim();
  return localizeRawMessage(l10n, raw);
}

String localizeRawMessage(AppLocalizations l10n, String raw) {
  final message = raw.trim();
  if (message.isEmpty) {
    return l10n.error;
  }

  const exactMessages = <String, String>{
    'User not found': 'userNotFound',
    'Admin not found': 'adminNotFound',
    'Email and password are required': 'emailPasswordRequired',
    'Invalid credentials': 'invalidCredentials',
    'Invalid admin credentials': 'invalidCredentials',
    'Account is blocked': 'accountBlocked',
    'Email not found': 'emailNotFound',
    'OTP expired': 'otpExpired',
    'Invalid OTP': 'invalidOtp',
    'Invalid request': 'invalidRequest',
    'Alert not found': 'alertNotFound',
    'Login failed': 'loginFailed',
    'Registration failed': 'registrationFailed',
  };

  final exactKey = exactMessages[message];
  if (exactKey != null) {
    return _localizedGetter(l10n, exactKey);
  }

  if (message.startsWith('Request timed out')) {
    return l10n.requestTimedOut;
  }

  if (message.startsWith('Unable to reach backend server')) {
    return l10n.backendUnavailable;
  }

  if (message.startsWith('Failed to get alerts')) {
    return l10n.failedToLoadAlerts;
  }

  if (message.startsWith('Failed to request password reset')) {
    return l10n.failedToSendOtp;
  }

  if (message.startsWith('Failed to reset password')) {
    return l10n.failedToResetPassword;
  }

  if (message.startsWith('Failed to get system logs')) {
    return l10n.failedToLoadSystemLogs;
  }

  if (message.startsWith('Failed to get devices')) {
    return l10n.failedToLoadDevices;
  }

  if (message.startsWith('Failed to get children')) {
    return l10n.failedToLoadChildren;
  }

  if (message.startsWith('Failed to get users')) {
    return l10n.failedToLoadUsers;
  }

  if (message.startsWith('Failed to get admin profile') ||
      message.startsWith('Failed to get profile')) {
    return l10n.failedToLoadProfile;
  }

  if (message.startsWith('Failed to update profile') ||
      message.startsWith('Failed to update admin profile')) {
    return l10n.failedToUpdateProfile;
  }

  if (message == 'Current password is incorrect') {
    return l10n.invalidCredentials;
  }

  if (message == 'New password must be at least 6 characters') {
    return l10n.passwordMinSix;
  }

  if (message == 'Passwords do not match') {
    return l10n.passwordsDoNotMatch;
  }

  if (message.startsWith('currentPassword') && message.contains('required')) {
    return l10n.passwordRequired;
  }

  if (message.startsWith('Failed to delete alert')) {
    return l10n.failedToDeleteAlert;
  }

  if (message.startsWith('Failed to delete system log')) {
    return l10n.failedToDeleteLog;
  }

  if (message.startsWith('Failed to create safe zone')) {
    return l10n.failedToCreateSafeZone;
  }

  if (message.startsWith('Failed to update safe zone')) {
    return l10n.failedToUpdateSafeZone;
  }

  if (message
      .startsWith('Emergency Alert: SOS button triggered from child device')) {
    return l10n.sos;
  }

  if (message.startsWith('Child out of Safe Zone')) {
    return l10n.childOutOfSafeZone;
  }

  if (message
      .startsWith('Your child has returned to the configured safe zone')) {
    return l10n.childBackInSafeZone;
  }

  if (message.startsWith('Low battery alert! Battery level:')) {
    final level = message.split(':').last.trim();
    return '${l10n.lowBattery}: $level';
  }

  if (message == 'Device has been turned off!') {
    return l10n.deviceOffline;
  }

  if (message == 'Device is now online!') {
    return l10n.deviceOnline;
  }

  return message;
}

String localizeStatusLabel(AppLocalizations l10n, String? value) {
  switch ((value ?? '').trim().toLowerCase()) {
    case 'active':
      return l10n.active;
    case 'blocked':
      return l10n.blocked;
    case 'online':
      return l10n.online;
    case 'delayed':
    case 'weak_connection':
      return l10n.deviceOffline;
    case 'offline':
    case 'disconnected':
      return l10n.offline;
    case 'no_data':
    case 'no_recent_data':
    case 'missing_live_tracking':
      return l10n.noData;
    default:
      return l10n.unknown;
  }
}

String localizeRoleLabel(AppLocalizations l10n, String? value) {
  switch ((value ?? '').trim().toLowerCase()) {
    case 'admin':
      return l10n.admin;
    case 'user':
      return l10n.user;
    default:
      return l10n.unknown;
  }
}

String localizeAlertTypeLabel(AppLocalizations l10n, String? value) {
  switch ((value ?? '').trim().toUpperCase()) {
    case 'SOS':
      return l10n.sos;
    case 'LOCATION_UPDATE':
      return l10n.location;
    case 'OUT_ZONE':
    case 'ZONE_EXIT':
    case 'SAFE_ZONE_EXIT':
      return l10n.childOutOfSafeZone;
    case 'IN_ZONE':
    case 'ZONE_ENTRY':
    case 'SAFE_ZONE_ENTER':
      return l10n.childBackInSafeZone;
    case 'LOW_BATTERY':
      return l10n.lowBattery;
    case 'DEVICE_OFF':
    case 'DEVICE_OFFLINE':
      return l10n.deviceOffline;
    case 'DEVICE_ONLINE':
      return l10n.deviceOnline;
    default:
      return (value ?? '').trim().isEmpty ? l10n.unknown : value!.toString();
  }
}

String _localizedGetter(AppLocalizations l10n, String key) {
  switch (key) {
    case 'userNotFound':
      return l10n.userNotFound;
    case 'adminNotFound':
      return l10n.adminNotFound;
    case 'emailPasswordRequired':
      return l10n.emailPasswordRequired;
    case 'invalidCredentials':
      return l10n.invalidCredentials;
    case 'accountBlocked':
      return l10n.accountBlocked;
    case 'emailNotFound':
      return l10n.emailNotFound;
    case 'otpExpired':
      return l10n.otpExpired;
    case 'invalidOtp':
      return l10n.invalidOtp;
    case 'invalidRequest':
      return l10n.invalidRequest;
    case 'alertNotFound':
      return l10n.alertNotFound;
    case 'loginFailed':
      return l10n.loginFailed;
    case 'registrationFailed':
      return l10n.registrationFailed;
    default:
      return l10n.error;
  }
}
