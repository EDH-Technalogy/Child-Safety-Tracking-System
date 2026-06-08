import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/constants.dart';
import '../utils/firebase_bootstrap.dart';
import 'api_service.dart';
import 'notification_service.dart';

class FcmService {
  FcmService._internal();

  static final FcmService _instance = FcmService._internal();
  factory FcmService() => _instance;

  final ApiService _apiService = ApiService();
  final NotificationService _notificationService = NotificationService();

  bool _initialized = false;
  StreamSubscription<RemoteMessage>? _foregroundSubscription;
  StreamSubscription<RemoteMessage>? _messageOpenedAppSubscription;
  StreamSubscription<String>? _tokenRefreshSubscription;
  bool _initialMessageHandled = false;

  FirebaseMessaging get _messaging => FirebaseMessaging.instance;

  Future<void> init() async {
    if (_initialized || kIsWeb) {
      return;
    }

    await FirebaseBootstrap.ensureInitialized();
    await _notificationService.init();

    try {
      await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
    } catch (error) {
      debugPrint('[FcmService.init] permission request failed: $error');
    }

    await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
      alert: false,
      badge: false,
      sound: false,
    );

    _foregroundSubscription ??= FirebaseMessaging.onMessage.listen((message) {
      debugPrint(
        '[FcmService.onMessage] type=${message.data['type']} alertId=${message.data['alertId']}',
      );
      unawaited(_notificationService.showRemoteMessage(message));
    });

    _messageOpenedAppSubscription ??=
        FirebaseMessaging.onMessageOpenedApp.listen((message) {
      final payload = _payloadFromMessage(message);
      debugPrint(
        '[FcmService.onMessageOpenedApp] type=${message.data['type']} payload=$payload',
      );
      NotificationNavigationService.handleNotificationPayload(payload);
    });

    if (!_initialMessageHandled) {
      _initialMessageHandled = true;
      try {
        final initialMessage = await _messaging.getInitialMessage();
        if (initialMessage != null) {
          final payload = _payloadFromMessage(initialMessage);
          debugPrint(
            '[FcmService.getInitialMessage] type=${initialMessage.data['type']} payload=$payload',
          );
          NotificationNavigationService.handleNotificationPayload(payload);
        }
      } catch (error) {
        debugPrint('[FcmService.getInitialMessage] failed: $error');
      }
    }

    _tokenRefreshSubscription ??=
        _messaging.onTokenRefresh.listen((token) async {
      final prefs = await SharedPreferences.getInstance();
      final userId = (prefs.getString(AppConstants.userIdKey) ?? '').trim();
      final role = (prefs.getString(AppConstants.userRoleKey) ?? '').trim();
      if (userId.isEmpty || role == 'admin') {
        return;
      }

      await _registerToken(userId: userId, token: token);
    });

    _initialized = true;
  }

  Future<void> syncForAuthenticatedUser({
    required String userId,
    required String role,
  }) async {
    if (userId.trim().isEmpty || role.trim().toLowerCase() == 'admin') {
      return;
    }

    await init();

    try {
      final token = await _messaging.getToken();
      if (token == null || token.trim().isEmpty) {
        debugPrint('[FcmService.sync] skipped empty token');
        return;
      }

      await _registerToken(userId: userId, token: token);
    } catch (error) {
      debugPrint('[FcmService.sync] failed: $error');
    }
  }

  Future<void> unregisterForUser({
    required String userId,
    required String role,
  }) async {
    if (kIsWeb || userId.trim().isEmpty || role.trim().toLowerCase() == 'admin') {
      return;
    }

    try {
      await FirebaseBootstrap.ensureInitialized();
      final token = await _messaging.getToken();
      if (token == null || token.trim().isEmpty) {
        return;
      }

      await _apiService.unregisterFcmToken(userId: userId, token: token);
    } catch (error) {
      debugPrint('[FcmService.unregister] failed: $error');
    }
  }

  Future<void> _registerToken({
    required String userId,
    required String token,
  }) async {
    await _apiService.registerFcmToken(
      userId: userId,
      token: token,
    );
    debugPrint('[FcmService.register] token synced for userId=$userId');
  }

  String? _payloadFromMessage(RemoteMessage message) {
    final type = (message.data['type'] ?? '').toString().trim().toUpperCase();
    if (!NotificationService.supportsRemoteAlertType(type)) {
      return null;
    }

    final childId = (message.data['childId'] ?? '').toString().trim();
    final alertId = (message.data['alertId'] ?? '').toString().trim();
    if (childId.isEmpty || alertId.isEmpty) {
      return null;
    }

    return 'alert:$childId:$alertId';
  }
}
