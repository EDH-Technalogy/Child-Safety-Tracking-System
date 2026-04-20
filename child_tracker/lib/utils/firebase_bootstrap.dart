import 'package:firebase_core/firebase_core.dart';

class FirebaseBootstrap {
  static Future<void>? _initialization;

  static Future<void> ensureInitialized() {
    if (Firebase.apps.isNotEmpty) {
      return Future<void>.value();
    }

    _initialization ??= _initialize();
    return _initialization!;
  }

  static Future<void> _initialize() async {
    try {
      await Firebase.initializeApp();
    } on FirebaseException catch (error) {
      _initialization = null;
      throw StateError(_formatError(error));
    } catch (error) {
      _initialization = null;
      throw StateError(
        'Firebase live tracking is unavailable right now: $error',
      );
    }
  }

  static String _formatError(FirebaseException error) {
    final message = error.message?.trim() ?? '';
    final normalized = message.toLowerCase();

    if (normalized.contains('google-services') ||
        normalized.contains('google service-info') ||
        normalized.contains('default firebaseapp is not initialized') ||
        normalized.contains('no firebase app')) {
      return 'Firebase client configuration is missing for this app build.';
    }

    if (message.isNotEmpty) {
      return message;
    }

    return 'Firebase live tracking is unavailable right now.';
  }
}
