import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationService {
  static const String _notificationKey = 'notification_enabled';
  static const String _safeZoneChannelId = 'safe_zone_alerts';
  static const String _safeZoneChannelName = 'Safe Zone Alerts';
  static const String _safeZoneChannelDescription =
      'Audible alerts for safe zone exits and other critical child events.';

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();
  final Set<String> _playedAlertIds = <String>{};

  bool _enabled = true;
  bool _isInitialized = false;

  Future<void> init() async {
    if (_isInitialized) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_notificationKey) ?? true;

    if (!kIsWeb) {
      try {
        const androidSettings =
            AndroidInitializationSettings('@mipmap/ic_launcher');
        const darwinSettings = DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
        );

        const initializationSettings = InitializationSettings(
          android: androidSettings,
          iOS: darwinSettings,
          macOS: darwinSettings,
        );

        await _notificationsPlugin.initialize(
          settings: initializationSettings,
        );

        final androidImplementation =
            _notificationsPlugin.resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>();
        await androidImplementation?.requestNotificationsPermission();
        await androidImplementation?.createNotificationChannel(
          const AndroidNotificationChannel(
            _safeZoneChannelId,
            _safeZoneChannelName,
            description: _safeZoneChannelDescription,
            importance: Importance.max,
            playSound: true,
          ),
        );

        final iosImplementation =
            _notificationsPlugin.resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin>();
        await iosImplementation?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );

        final macOsImplementation =
            _notificationsPlugin.resolvePlatformSpecificImplementation<
                MacOSFlutterLocalNotificationsPlugin>();
        await macOsImplementation?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
      } catch (error) {
        debugPrint(
          '[NotificationService.init] plugin initialization skipped: $error',
        );
      }
    }

    _isInitialized = true;
    debugPrint(
      '[NotificationService.init] initialized enabled=$_enabled web=$kIsWeb',
    );
  }

  Future<void> _persistEnabledState(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_notificationKey, value);
  }

  Future<void> enable() async {
    _enabled = true;
    await _persistEnabledState(true);
    debugPrint('[NotificationService.enable] notifications enabled');
  }

  Future<void> disable() async {
    _enabled = false;
    await _persistEnabledState(false);
    debugPrint('[NotificationService.disable] notifications disabled');
  }

  bool get enabled => _enabled;

  Future<void> sendNotification({
    required String title,
    required String body,
    String? payload,
    String? dedupeKey,
    bool playAlertTone = false,
  }) async {
    await init();

    if (!_enabled) {
      debugPrint(
        '[NotificationService.sendNotification] skipped disabled title=$title',
      );
      return;
    }

    if (dedupeKey != null && !_playedAlertIds.add(dedupeKey)) {
      debugPrint(
        '[NotificationService.sendNotification] skipped duplicate key=$dedupeKey',
      );
      return;
    }

    if (playAlertTone) {
      try {
        await SystemSound.play(SystemSoundType.alert);
      } catch (error) {
        debugPrint(
          '[NotificationService.sendNotification] system sound failed: $error',
        );
      }
    }

    if (kIsWeb) {
      debugPrint(
        '[NotificationService.sendNotification] web fallback title=$title body=$body',
      );
      return;
    }

    final notificationId = dedupeKey == null
        ? DateTime.now().millisecondsSinceEpoch ~/ 1000
        : dedupeKey.hashCode & 0x7fffffff;

    const androidDetails = AndroidNotificationDetails(
      _safeZoneChannelId,
      _safeZoneChannelName,
      channelDescription: _safeZoneChannelDescription,
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      category: AndroidNotificationCategory.alarm,
    );
    const darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      interruptionLevel: InterruptionLevel.timeSensitive,
    );

    try {
      await _notificationsPlugin.show(
        id: notificationId,
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(
          android: androidDetails,
          iOS: darwinDetails,
          macOS: darwinDetails,
        ),
        payload: payload,
      );
    } catch (error) {
      debugPrint(
        '[NotificationService.sendNotification] local notification failed: $error',
      );
    }

    debugPrint(
      '[NotificationService.sendNotification] delivered id=$notificationId key=$dedupeKey title=$title',
    );
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
      'safe_zone_exit': {
        'en': 'Safe Zone Exit',
        'ps': 'له خوندي سیمې وتل',
        'fa': 'خروج از منطقه امن',
      },
    };

    return titles[key]?[localeCode] ?? titles[key]?['en'] ?? '';
  }

  String _localizedNotificationBody(
    String localeCode,
    String key, {
    double? lat,
    double? lon,
    String? childName,
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
      case 'safe_zone_exit':
        switch (localeCode) {
          case 'ps':
            return '${childName ?? "ستاسو ماشوم"} له خوندي سیمې څخه بهر شو.';
          case 'fa':
            return '${childName ?? "کودک شما"} از منطقه امن خارج شد.';
          default:
            return '${childName ?? "Your child"} left the safe zone.';
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

  Future<void> sendSafeZoneExitAlert({
    required String alertId,
    String? childName,
    required String body,
    String? payload,
  }) async {
    final localeCode = await _localeCode();
    await sendNotification(
      title: _localizedNotificationTitle(localeCode, 'safe_zone_exit'),
      body: body.isNotEmpty
          ? body
          : _localizedNotificationBody(
              localeCode,
              'safe_zone_exit',
              childName: childName,
            ),
      payload: payload,
      dedupeKey: alertId,
      playAlertTone: true,
    );
  }

  Future<void> cancelAll() async {
    if (!kIsWeb) {
      await _notificationsPlugin.cancelAll();
    }
  }

  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();
}
