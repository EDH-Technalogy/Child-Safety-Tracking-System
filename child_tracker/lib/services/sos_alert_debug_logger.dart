// ignore_for_file: avoid_print

import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';

import '../utils/constants.dart';
import '../utils/firebase_bootstrap.dart';
import 'realtime_database_auth_service.dart';

class SOSAlertDebugLogger {
  static StreamSubscription<DatabaseEvent>? _subscription;
  static bool _isStarting = false;

  static Future<void> start() async {
    if (_subscription != null || _isStarting) {
      return;
    }

    _isStarting = true;
    print('🚨 DEBUG: Listening to alerts_live...');

    try {
      await FirebaseBootstrap.ensureInitialized();
      await RealtimeDatabaseAuthService.ensureSignedIn();

      final database = FirebaseDatabase.instanceFor(
        app: Firebase.app(),
        databaseURL: AppConstants.firebaseDatabaseUrl,
      );
      final ref = database.ref('alerts_live');

      _subscription = ref.onChildAdded.listen(
        (event) {
          final rawData = event.snapshot.value;

          if (rawData is! Map) {
            print('❌ No data received');
            print('Alert ID: ${event.snapshot.key}');
            print('Raw Data: $rawData');
            return;
          }

          final data = rawData.map(
            (key, value) => MapEntry(key.toString(), value),
          );
          final message = data['message'];
          final timestamp = data['timestamp'];

          print('=================================');
          print('🚨 NEW SOS ALERT RECEIVED');
          print('Alert ID: ${event.snapshot.key}');
          print('Message: $message');
          print('Timestamp: $timestamp');
          print('Raw Data: $data');
          print('=================================');
        },
        onError: (Object error) {
          print('❌ DEBUG: alerts_live listener error');
          print('Error: $error');
          final subscription = _subscription;
          _subscription = null;
          if (subscription != null) {
            unawaited(subscription.cancel());
          }
        },
      );
    } catch (error) {
      print('❌ DEBUG: Failed to start alerts_live listener');
      print('Error: $error');
    } finally {
      _isStarting = false;
    }
  }

  static Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    _isStarting = false;
  }
}
