import 'package:flutter/foundation.dart';
import '../services/notification_service.dart';

class NotificationProvider with ChangeNotifier {
  final NotificationService _notificationService = NotificationService();
  bool _enabled = false;
  bool _isInitialized = false;

  bool get enabled => _enabled;
  bool get isInitialized => _isInitialized;

  Future<void> init() async {
    await _notificationService.init();
    _enabled = _notificationService.enabled;
    _isInitialized = true;
    notifyListeners();
  }

  Future<void> loadEnabledState() async {
    if (!_isInitialized) {
      await init();
    }
    _enabled = _notificationService.enabled;
    notifyListeners();
  }

  Future<void> setEnabled(bool value) async {
    if (value) {
      await _notificationService.enable();
    } else {
      await _notificationService.disable();
    }
    _enabled = value;
    notifyListeners();
  }

  Future<void> sendTestNotification() async {
    await _notificationService.sendTestNotification();
  }
}
