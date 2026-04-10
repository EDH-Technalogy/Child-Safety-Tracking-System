import 'package:flutter/foundation.dart';
import '../services/settings_service.dart';

class SettingsProvider with ChangeNotifier {
  final SettingsService _settingsService = SettingsService();
  bool _notificationEnabled = false;
  bool _locationTrackingEnabled = false;
  bool _isLoading = false;

  bool get notificationEnabled => _notificationEnabled;
  bool get locationTrackingEnabled => _locationTrackingEnabled;
  bool get isLoading => _isLoading;

  Future<void> loadSettings() async {
    _isLoading = true;
    notifyListeners();

    final settings = await _settingsService.getAllSettings();
    _notificationEnabled = settings['notifications']!;
    _locationTrackingEnabled = settings['locationTracking']!;
    _isLoading = false;
    notifyListeners();
  }

  Future<void> setNotificationEnabled(bool value) async {
    _notificationEnabled = value;
    await _settingsService.setNotificationEnabled(value);
    notifyListeners();
  }

  Future<void> setLocationTrackingEnabled(bool value) async {
    _locationTrackingEnabled = value;
    await _settingsService.setLocationTrackingEnabled(value);
    notifyListeners();
  }
}
