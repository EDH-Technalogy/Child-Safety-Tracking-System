import 'package:shared_preferences/shared_preferences.dart';

class SettingsService {
  static const String _notificationKey = 'notification_enabled';
  static const String _locationTrackingKey = 'location_tracking_enabled';

  static final SettingsService _instance = SettingsService._internal();
  factory SettingsService() => _instance;
  SettingsService._internal();

  Future<bool> getNotificationEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_notificationKey) ?? false;
  }

  Future<void> setNotificationEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_notificationKey, value);
  }

  Future<bool> getLocationTrackingEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_locationTrackingKey) ?? false;
  }

  Future<void> setLocationTrackingEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_locationTrackingKey, value);
  }

  // Batch load all settings
  Future<Map<String, bool>> getAllSettings() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'notifications': prefs.getBool(_notificationKey) ?? false,
      'locationTracking': prefs.getBool(_locationTrackingKey) ?? false,
    };
  }
}
