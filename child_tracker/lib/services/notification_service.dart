// Simple notification service without plugin to avoid API issues. Uses system channel if needed.

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationService {
  bool _enabled = false;

  Future<void> init() async {}

  Future<void> enable() async {
    _enabled = true;
  }

  Future<void> disable() async {
    _enabled = false;
  }

  bool get enabled => _enabled;

  Future<void> sendNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!_enabled) return;
    // Use print for demo - replace with Snackbar or dialog in production
    debugPrint('NOTIFICATION: $title - $body');
  }

  Future<String> _localeCode() async {
    final prefs = await SharedPreferences.getInstance();
    var localeCode = prefs.getString('app_locale') ?? 'en';
    if (localeCode == 'dr' || localeCode == 'prs') {
      localeCode = 'fa';
    }
    return localeCode;
  }

  String _localizedNotificationTitle(String localeCode, String key) {
    const titles = <String, Map<String, String>>{
      'test': {
        'en': 'Test Notification',
        'ps': 'د خبرتیا ازموینه',
        'fa': 'اعلان آزمایشی',
      },
      'location': {
        'en': 'Location Updated',
        'ps': 'ځای تازه شو',
        'fa': 'موقعیت به‌روزرسانی شد',
      },
    };

    return titles[key]?[localeCode] ?? titles[key]?['en'] ?? '';
  }

  String _localizedNotificationBody(
    String localeCode,
    String key, {
    double? lat,
    double? lon,
  }) {
    switch (key) {
      case 'test':
        const bodies = <String, String>{
          'en': 'Notifications are working!',
          'ps': 'خبرتیاوې سم کار کوي!',
          'fa': 'اعلان‌ها درست کار می‌کنند!',
        };
        return bodies[localeCode] ?? bodies['en']!;
      case 'location':
        switch (localeCode) {
          case 'ps':
            return 'عرض البلد: $lat، طول البلد: $lon';
          case 'fa':
            return 'عرض جغرافیایی: $lat، طول جغرافیایی: $lon';
          default:
            return 'Lat: $lat, Lon: $lon';
        }
      default:
        return '';
    }
  }

  Future<void> sendTestNotification() async {
    final localeCode = await _localeCode();
    await sendNotification(
      title: _localizedNotificationTitle(localeCode, 'test'),
      body: _localizedNotificationBody(localeCode, 'test'),
    );
  }

  Future<void> sendLocationUpdateNotification(double lat, double lon) async {
    final localeCode = await _localeCode();
    await sendNotification(
      title: _localizedNotificationTitle(localeCode, 'location'),
      body: _localizedNotificationBody(
        localeCode,
        'location',
        lat: lat,
        lon: lon,
      ),
    );
  }

  Future<void> cancelAll() async {}

  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();
}
