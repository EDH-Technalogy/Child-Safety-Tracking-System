import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/constants.dart';
import '../utils/firebase_bootstrap.dart';
import '../utils/session_token_store.dart';

class RealtimeDatabaseAuthService {
  static Future<void>? _signInFuture;

  static Future<void> ensureSignedIn() {
    _signInFuture ??= _signIn();
    return _signInFuture!;
  }

  static void invalidateCachedSignIn() {
    _signInFuture = null;
  }

  static Future<void> reset() async {
    _signInFuture = null;
    try {
      await FirebaseAuth.instance.signOut();
    } catch (error) {
      debugPrint('[RealtimeDatabaseAuthService.reset] signOut failed: $error');
    }
  }

  static Future<void> _signIn() async {
    try {
      await FirebaseBootstrap.ensureInitialized();

      final prefs = await SharedPreferences.getInstance();
      final appToken = prefs.getString(AppConstants.tokenKey) ??
          SessionTokenStore.currentToken;
      final expectedUid = prefs.getString(AppConstants.userIdKey) ?? '';

      if (appToken == null || appToken.isEmpty || expectedUid.isEmpty) {
        _signInFuture = null;
        return;
      }

      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser?.uid == expectedUid) {
        return;
      }

      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}${ApiConfig.users}/firebase-token'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $appToken',
        },
      ).timeout(const Duration(milliseconds: ApiConfig.connectionTimeout));

      if (response.statusCode != 200) {
        throw StateError('Failed to authenticate realtime alerts');
      }

      final payload = jsonDecode(response.body);
      final firebaseToken = payload is Map ? payload['token']?.toString() : null;
      if (firebaseToken == null || firebaseToken.isEmpty) {
        throw StateError('Realtime alert token was empty');
      }

      if (currentUser != null && currentUser.uid != expectedUid) {
        await FirebaseAuth.instance.signOut();
      }

      await FirebaseAuth.instance.signInWithCustomToken(firebaseToken);
      debugPrint(
        '[RealtimeDatabaseAuthService] signed in uid=$expectedUid',
      );
    } catch (error) {
      _signInFuture = null;
      rethrow;
    }
  }
}
