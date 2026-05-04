import 'package:flutter/foundation.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class SocialAuthService {
  static const String _googleClientId =
      String.fromEnvironment('GOOGLE_CLIENT_ID');
  static const String _googleServerClientId =
      String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');
  static const String _facebookAppId =
      String.fromEnvironment('FACEBOOK_APP_ID');
  static const String _facebookGraphVersion = String.fromEnvironment(
    'FACEBOOK_GRAPH_VERSION',
    defaultValue: 'v24.0',
  );

  bool _googleInitialized = false;
  bool _facebookWebInitialized = false;

  GoogleSignIn get _googleSignIn => GoogleSignIn.instance;

  Stream<GoogleSignInAuthenticationEvent> get googleAuthenticationEvents =>
      _googleSignIn.authenticationEvents;

  Future<void> initializeGoogle() async {
    await _ensureGoogleInitialized();
  }

  Future<void> _ensureGoogleInitialized() async {
    if (_googleInitialized) {
      return;
    }

    await _googleSignIn.initialize(
      clientId: _googleClientId.isEmpty ? null : _googleClientId,
      serverClientId:
          _googleServerClientId.isEmpty ? null : _googleServerClientId,
    );
    _googleInitialized = true;
  }

  Future<void> _ensureFacebookInitialized() async {
    if (!kIsWeb || _facebookWebInitialized || _facebookAppId.isEmpty) {
      return;
    }

    await FacebookAuth.instance.webAndDesktopInitialize(
      appId: _facebookAppId,
      cookie: true,
      xfbml: true,
      version: _facebookGraphVersion,
    );
    _facebookWebInitialized = true;
  }

  Future<String?> signInWithGoogle() async {
    await _ensureGoogleInitialized();

    if (!_googleSignIn.supportsAuthenticate()) {
      throw Exception('Google sign-in is not supported on this platform');
    }

    try {
      final account = await _googleSignIn.authenticate();
      return googleIdTokenForAccount(account);
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled) {
        return null;
      }

      throw Exception(error.description ?? 'Google sign-in failed');
    }
  }

  String googleIdTokenForAccount(GoogleSignInAccount account) {
    final idToken = account.authentication.idToken;
    if (idToken == null || idToken.isEmpty) {
      throw Exception(
        'Google sign-in did not return an ID token. Configure GOOGLE_SERVER_CLIENT_ID for this app.',
      );
    }
    return idToken;
  }

  Future<String?> signInWithFacebook() async {
    await _ensureFacebookInitialized();

    final result = await FacebookAuth.instance.login(
      permissions: const ['email', 'public_profile'],
      loginTracking: LoginTracking.enabled,
    );

    switch (result.status) {
      case LoginStatus.success:
        final token = result.accessToken?.tokenString ?? '';
        if (token.isEmpty) {
          throw Exception('Facebook sign-in did not return an access token');
        }
        return token;
      case LoginStatus.cancelled:
        return null;
      case LoginStatus.operationInProgress:
        throw Exception('Facebook sign-in is already in progress');
      case LoginStatus.failed:
        throw Exception(result.message ?? 'Facebook sign-in failed');
    }
  }

  Future<void> signOutAll() async {
    await Future.wait([
      _safeGoogleSignOut(),
      _safeFacebookSignOut(),
    ]);
  }

  Future<void> _safeGoogleSignOut() async {
    try {
      await _ensureGoogleInitialized();
      await _googleSignIn.signOut();
    } catch (_) {
      // Local app session cleanup must still continue if provider logout fails.
    }
  }

  Future<void> _safeFacebookSignOut() async {
    try {
      await _ensureFacebookInitialized();
      await FacebookAuth.instance.logOut();
    } catch (_) {
      // Local app session cleanup must still continue if provider logout fails.
    }
  }
}
