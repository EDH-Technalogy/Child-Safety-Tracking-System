import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class AppColors {
  static const Color primaryColor = Color(0xFF2196F3);
  static const Color secondaryColor = Color(0xFFFF9800);
  static const Color backgroundColor = Color(0xFFF5F5F5);
  static const Color cardColor = Colors.white;
  static const Color textPrimary = Color(0xFF212121);
  static const Color textSecondary = Color(0xFF757575);
  static const Color successColor = Color(0xFF4CAF50);
  static const Color errorColor = Color(0xFFF44336);
  static const Color warningColor = Color(0xFFFF9800);
  static const Color infoColor = Color(0xFF2196F3);

  // Alert colors
  static const Color sosColor = Color(0xFFF44336);
  static const Color outZoneColor = Color(0xFFFF9800);
  static const Color inZoneColor = Color(0xFF4CAF50);
  static const Color lowBatteryColor = Color(0xFFFFEB3B);
  static const Color deviceOfflineColor = Color(0xFF9E9E9E);
}

class ApiConfig {
  static const String _envBaseUrl = String.fromEnvironment('API_BASE_URL');

  // Dynamic base URL for different platforms
  static String get baseUrl {
    if (_envBaseUrl.isNotEmpty) {
      return _envBaseUrl;
    }

    if (kIsWeb) {
      final scheme = Uri.base.scheme == 'https' ? 'https' : 'http';
      final requestedHost =
          Uri.base.host.isNotEmpty ? Uri.base.host : 'localhost';
      final host = requestedHost == 'localhost' ? '127.0.0.1' : requestedHost;
      return '$scheme://$host:3000/api'; // Flutter Web / LAN browser
    } else if (defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.200.196.92:3000/api'; // Physical Android device on LAN
    } else {
      return 'http://127.0.0.1:3000/api'; // Desktop / simulator fallback
    }
  }

  static String get backendSetupHint {
    if (kIsWeb) {
      return 'Start the backend on this computer and make sure port 3000 is reachable from the browser.';
    }

    if (defaultTargetPlatform == TargetPlatform.android) {
      return 'If you are using an Android emulator, keep the backend on your computer and use 10.0.2.2. If you are using a physical phone, run Flutter with --dart-define=API_BASE_URL=http://YOUR_COMPUTER_IP:3000/api.';
    }

    return 'Start the backend on this computer and make sure port 3000 is available.';
  }

  static String get authBaseUrl {
    final normalizedBaseUrl = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    if (normalizedBaseUrl.endsWith('/api')) {
      return normalizedBaseUrl.substring(0, normalizedBaseUrl.length - 4);
    }
    return normalizedBaseUrl;
  }

  // Endpoints
  static const String users = '/users';
  static const String children = '/children';
  static const String devices = '/devices';
  static const String locations = '/locations';
  static const String alerts = '/alerts';
  static const String geofence = '/geofence';
  static const String settings = '/settings';
  static const String summaries = '/summary';
  static const String activities = '/activity';

  // Timeouts
  static const int connectionTimeout = 30000;
  static const int receiveTimeout = 30000;
}

class AppConstants {
  static const String appName = 'Child Tracker';
  static const String appVersion = '1.0.0';
  static const String aboutAppName = 'Child Tracking & Safety App';
  static const String aboutDeveloperName = 'Child Tracker Development Team';
  static const String aboutCompanyName = 'Child Tracker';
  static const String aboutSupportEmail = 'support@childtracker.com';
  static const String aboutSupportPhone = '+000 000 0000';
  static const String aboutWebsite = 'www.childtracker.com';
  static const String aboutCopyrightText = '© 2026 All Rights Reserved.';

  static const String googleMapsApiKey =
      'AIzaSyBv8adVhfT-6wDSPZI3yPYeAgYbDxffm_0';
  static const String firebaseDatabaseUrl = String.fromEnvironment(
    'FIREBASE_DATABASE_URL',
    defaultValue: 'https://child-safety-tracking-default-rtdb.firebaseio.com',
  );

  // Storage keys
  static const String userIdKey = 'user_id';
  static const String userNameKey = 'user_name';
  static const String userEmailKey = 'user_email';
  static const String userPhoneKey = 'user_phone';
  static const String tokenKey = 'auth_token';
  static const String userRoleKey = 'user_role';

  // Default values
  static const int defaultSafeZoneRadius = 100; // meters
  static const int locationRefreshInterval = 30; // seconds
  static const int batteryAlertLevel = 20; // percentage

  // Default map position (used when no location is available)
  static const double defaultLatitude = 37.7749;
  static const double defaultLongitude = -122.4194;
  static const double defaultZoom = 15.0;
}
