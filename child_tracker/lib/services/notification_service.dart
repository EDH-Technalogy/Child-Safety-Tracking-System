import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app_badger/flutter_app_badger.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationService {
  static const String _notificationKey = 'notification_enabled';
  static const String _generalChannelId = 'child_tracker_general_v2';
  static const String _generalChannelName = 'General Notifications';
  static const String _generalChannelDescription =
      'Standard app notifications for child tracking updates.';
  static const String _safeZoneChannelId = 'safe_zone_alarm_v3';
  static const String _safeZoneChannelName = 'Safe Zone Alarm Alerts';
  static const String _safeZoneChannelDescription =
      'Audible alerts for safe zone exits and other critical child events.';
  static const String _safeZoneAlarmSoundName = 'safe_zone_alarm';

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
        final linuxSettings = LinuxInitializationSettings(
          defaultActionName: 'Open',
          defaultSound: ThemeLinuxSound('message'),
        );
        const windowsSettings = WindowsInitializationSettings(
          appName: 'Child Tracker',
          appUserModelId: 'ChildTracker.App',
          guid: 'c3e3b9a9-7e34-4c5f-a8bb-3d5e7fd9c2a1',
        );

        final initializationSettings = InitializationSettings(
          android: androidSettings,
          iOS: darwinSettings,
          macOS: darwinSettings,
          linux: linuxSettings,
          windows: windowsSettings,
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
            _generalChannelId,
            _generalChannelName,
            description: _generalChannelDescription,
            importance: Importance.high,
            playSound: true,
            audioAttributesUsage: AudioAttributesUsage.notification,
          ),
        );
        await androidImplementation?.createNotificationChannel(
          AndroidNotificationChannel(
            _safeZoneChannelId,
            _safeZoneChannelName,
            description: _safeZoneChannelDescription,
            importance: Importance.max,
            playSound: true,
            sound: RawResourceAndroidNotificationSound(_safeZoneAlarmSoundName),
            enableVibration: true,
            vibrationPattern: Int64List.fromList(<int>[
              0,
              450,
              220,
              450,
              220,
              700,
            ]),
            audioAttributesUsage: AudioAttributesUsage.alarm,
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

  Future<void> updateAppIconBadge(int count) async {
    if (kIsWeb) {
      return;
    }

    try {
      final supported = await FlutterAppBadger.isAppBadgeSupported();
      if (!supported) {
        return;
      }

      if (count <= 0) {
        await FlutterAppBadger.removeBadge();
        return;
      }

      await FlutterAppBadger.updateBadgeCount(count);
    } catch (error) {
      debugPrint(
        '[NotificationService.updateAppIconBadge] skipped count=$count error=$error',
      );
    }
  }

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

    final androidDetails = playAlertTone
        ? AndroidNotificationDetails(
            _safeZoneChannelId,
            _safeZoneChannelName,
            channelDescription: _safeZoneChannelDescription,
            importance: Importance.max,
            priority: Priority.max,
            playSound: true,
            sound: const RawResourceAndroidNotificationSound(
              _safeZoneAlarmSoundName,
            ),
            styleInformation: BigTextStyleInformation(body),
            enableVibration: true,
            visibility: NotificationVisibility.public,
            ticker: title,
            channelShowBadge: true,
            fullScreenIntent: true,
            autoCancel: true,
            vibrationPattern: Int64List.fromList(<int>[
              0,
              450,
              220,
              450,
              220,
              700,
            ]),
            category: AndroidNotificationCategory.alarm,
            audioAttributesUsage: AudioAttributesUsage.alarm,
          )
        : AndroidNotificationDetails(
            _generalChannelId,
            _generalChannelName,
            channelDescription: _generalChannelDescription,
            importance: Importance.high,
            priority: Priority.high,
            playSound: true,
            styleInformation: BigTextStyleInformation(body),
            visibility: NotificationVisibility.public,
            ticker: title,
            channelShowBadge: true,
            autoCancel: true,
            category: AndroidNotificationCategory.message,
            audioAttributesUsage: AudioAttributesUsage.notification,
          );
    const darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      interruptionLevel: InterruptionLevel.timeSensitive,
    );
    final linuxDetails = LinuxNotificationDetails(
      category: LinuxNotificationCategory.deviceError,
      urgency: playAlertTone
          ? LinuxNotificationUrgency.critical
          : LinuxNotificationUrgency.normal,
      sound:
          playAlertTone ? ThemeLinuxSound('alarm') : ThemeLinuxSound('message'),
      resident: playAlertTone,
    );
    final windowsDetails = playAlertTone
        ? WindowsNotificationDetails(
            scenario: WindowsNotificationScenario.alarm,
            duration: WindowsNotificationDuration.long,
            audio: WindowsNotificationAudio.preset(
              sound: WindowsNotificationSound.alarm1,
            ),
          )
        : WindowsNotificationDetails(
            audio: WindowsNotificationAudio.preset(
              sound: WindowsNotificationSound.defaultSound,
            ),
          );

    try {
      await _notificationsPlugin.show(
        id: notificationId,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(
          android: androidDetails,
          iOS: darwinDetails,
          macOS: darwinDetails,
          linux: linuxDetails,
          windows: windowsDetails,
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
      'sos': {
        'en': 'SOS Alert',
        'ps': 'د SOS بیړنۍ خبرتیا',
        'fa': 'هشدار اضطراری SOS',
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
      case 'sos':
        switch (localeCode) {
          case 'ps':
            return '${childName ?? "ستاسو ماشوم"} د مرستې بیړنی SOS خبرتیا لېږلې ده.';
          case 'fa':
            return '${childName ?? "کودک شما"} هشدار اضطراری SOS ارسال کرده است.';
          default:
            return '${childName ?? "Your child"} triggered an emergency SOS alert.';
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

  Future<void> sendSafeZoneEnterAlert({
    required String alertId,
    String? childName,
    required String body,
    String? payload,
  }) async {
    final normalizedBody = body.trim();
    await sendNotification(
      title: 'Safe Zone Return',
      body: normalizedBody.isNotEmpty
          ? normalizedBody
          : '${childName ?? "Your child"} returned to the safe zone.',
      payload: payload,
      dedupeKey: alertId,
      playAlertTone: true,
    );
  }

  Future<void> sendSosAlert({
    required String alertId,
    String? childName,
    String? body,
    String? payload,
  }) async {
    final localeCode = await _localeCode();
    final normalizedBody = (body ?? '').trim();
    final shouldUseLocalizedBody = normalizedBody.isEmpty ||
        normalizedBody == 'Child is in danger!' ||
        normalizedBody ==
            'Emergency Alert: SOS button triggered from child device.';

    await sendNotification(
      title: _localizedNotificationTitle(localeCode, 'sos'),
      body: shouldUseLocalizedBody
          ? _localizedNotificationBody(
              localeCode,
              'sos',
              childName: childName,
            )
          : normalizedBody,
      payload: payload,
      dedupeKey: alertId,
      playAlertTone: true,
    );

    // Extra alarm bursts for SOS urgency (complements the notification sound)
    await _playUrgentAlarmBursts();
  }

  Future<void> _playUrgentAlarmBursts() async {
    for (int i = 0; i < 3; i++) {
      try {
        await SystemSound.play(SystemSoundType.alert);
      } catch (_) {
        // Silently ignored — SystemSound may be unsupported on web
      }
      if (i < 2) {
        await Future.delayed(const Duration(milliseconds: 400));
      }
    }
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
