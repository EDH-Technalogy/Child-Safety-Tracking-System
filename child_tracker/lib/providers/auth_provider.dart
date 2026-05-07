import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/admin_api_service.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';
import '../services/realtime_database_auth_service.dart';
import '../models/user_model.dart';
import '../utils/constants.dart';
import '../utils/session_token_store.dart';

class AuthProvider with ChangeNotifier {
  static const String _sessionUserStorageKey = 'user';

  final ApiService _apiService = ApiService();
  final AdminApiService _adminApiService = AdminApiService();
  final NotificationService _notificationService = NotificationService();

  UserModel? _user;
  String? _error;
  bool _isLoading = false;
  Future<bool>? _sessionRestoreFuture;

  UserModel? get user => _user;
  String? get error => _error;
  bool get isLoading => _isLoading;
  bool get isLoggedIn => _user != null;
  bool get isAdmin => _user?.role == 'admin';
  String? get sessionToken => SessionTokenStore.currentToken;

  AuthProvider();

  String _formatError(Object error) {
    final message = error.toString();
    return message.startsWith('Exception: ')
        ? message.substring('Exception: '.length)
        : message;
  }

  Map<String, dynamic>? _extractUserData(Map<String, dynamic> result) {
    final nestedUser = result['user'];
    if (nestedUser is Map) {
      return Map<String, dynamic>.from(nestedUser);
    }

    final hasTopLevelUser = result['id'] != null ||
        result['email'] != null ||
        result['name'] != null;

    if (!hasTopLevelUser) {
      return null;
    }

    final user = <String, dynamic>{};
    for (final key in [
      'id',
      'name',
      'phone',
      'email',
      'photo',
      'role',
      'status',
      'created_at',
    ]) {
      if (result.containsKey(key)) {
        user[key] = result[key];
      }
    }

    return user;
  }

  bool _isInvalidCredentialsError(Object error) {
    final message = _formatError(error).toLowerCase();
    return message.contains('invalid credentials') ||
        message.contains('invalid admin credentials');
  }

  Map<String, dynamic> _normalizeAdminSessionData(
    Map<String, dynamic> response, {
    required String fallbackEmail,
  }) {
    return {
      'id': response['id']?.toString() ?? '',
      'name': response['name']?.toString() ?? 'Admin',
      'email': response['email']?.toString() ?? fallbackEmail,
      'phone': response['phone']?.toString() ?? '',
      'photo': response['photo']?.toString() ?? '',
      'role': response['role']?.toString() ?? 'admin',
      'status': response['status']?.toString() ?? 'active',
      'created_at': response['created_at'] ?? 0,
    };
  }

  Future<void> _persistSession(
    SharedPreferences prefs,
    Map<String, dynamic> userData,
    String token,
  ) async {
    await prefs.setString(_sessionUserStorageKey, jsonEncode(userData));
    await prefs.setString(AppConstants.tokenKey, token);
    await prefs.setString(
        AppConstants.userIdKey, userData['id']?.toString() ?? '');
    await prefs.setString(
        AppConstants.userNameKey, userData['name']?.toString() ?? '');
    await prefs.setString(
        AppConstants.userEmailKey, userData['email']?.toString() ?? '');
    await prefs.setString(
        AppConstants.userPhoneKey, userData['phone']?.toString() ?? '');
    await prefs.setString(
        AppConstants.userRoleKey, userData['role']?.toString() ?? 'user');
  }

  Future<void> _clearPersistedSession([SharedPreferences? prefs]) async {
    final preferences = prefs ?? await SharedPreferences.getInstance();

    for (final key in [
      _sessionUserStorageKey,
      AppConstants.tokenKey,
      AppConstants.userIdKey,
      AppConstants.userNameKey,
      AppConstants.userEmailKey,
      AppConstants.userPhoneKey,
      AppConstants.userRoleKey,
    ]) {
      await preferences.remove(key);
    }

    _user = null;
    _error = null;
    SessionTokenStore.clear();
    await _notificationService.updateAppIconBadge(0);
    await RealtimeDatabaseAuthService.reset();
  }

  bool _shouldInvalidatePersistedSession(String message) {
    final normalizedMessage = message.trim();
    if (normalizedMessage.isEmpty) {
      return false;
    }

    for (final marker in [
      'Authorization token is required',
      'Invalid authorization token',
      'User session is no longer valid',
      'Admin session is no longer valid',
      'User not found',
      'Admin not found',
      'Admin access required',
      'You do not have permission to access this user',
      'Account is blocked',
      'Admin account is not active',
      'Token expired',
      'Invalid token signature',
      'Invalid token format',
      'Missing token',
    ]) {
      if (normalizedMessage.contains(marker)) {
        return true;
      }
    }

    return false;
  }

  Map<String, dynamic>? _readStoredUserData(SharedPreferences prefs) {
    final userJson = prefs.getString(_sessionUserStorageKey);
    if (userJson != null && userJson.isNotEmpty) {
      try {
        final decoded = jsonDecode(userJson);
        if (decoded is Map<String, dynamic>) {
          return decoded;
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint(
            '[AuthProvider._readStoredUserData] Failed to decode stored user: $e',
          );
        }
      }
    }

    final storedUserId = prefs.getString(AppConstants.userIdKey) ?? '';
    final storedRole = prefs.getString(AppConstants.userRoleKey) ?? '';
    final storedEmail = prefs.getString(AppConstants.userEmailKey) ?? '';
    final storedName = prefs.getString(AppConstants.userNameKey) ?? '';
    final storedPhone = prefs.getString(AppConstants.userPhoneKey) ?? '';

    if (storedUserId.isEmpty && storedEmail.isEmpty) {
      return null;
    }

    return {
      'id': storedUserId,
      'name': storedName,
      'phone': storedPhone,
      'email': storedEmail,
      'photo': '',
      'role': storedRole.isNotEmpty ? storedRole : 'user',
      'status': 'active',
      'created_at': 0,
    };
  }

  Future<Map<String, dynamic>> _validateStoredSession(
      UserModel storedUser) async {
    if (storedUser.role == 'admin') {
      return _adminApiService.getAdminProfile();
    }

    return _apiService.getProfile(storedUser.id);
  }

  Future<void> setAuthenticatedSession({
    required Map<String, dynamic> userData,
    required String token,
  }) async {
    final normalizedToken =
        token.isNotEmpty ? token : (SessionTokenStore.currentToken ?? '');
    final prefs = await SharedPreferences.getInstance();
    await _persistSession(prefs, userData, normalizedToken);
    _user = UserModel.fromJson(userData);
    _error = null;
    SessionTokenStore.currentToken =
        normalizedToken.isNotEmpty ? normalizedToken : null;
    RealtimeDatabaseAuthService.invalidateCachedSignIn();

    if (kDebugMode) {
      debugPrint(
        '[AuthProvider.setAuthenticatedSession] Saved session for userId=${_user?.id} role=${_user?.role}',
      );
    }

    notifyListeners();
  }

  Future<void> syncSessionUserData(Map<String, dynamic> userData) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(AppConstants.tokenKey) ?? '';
    await setAuthenticatedSession(userData: userData, token: token);
  }

  void previewCurrentUserPhoto(String? photo) {
    if (_user == null) {
      return;
    }

    _user = UserModel(
      id: _user!.id,
      name: _user!.name,
      phone: _user!.phone,
      email: _user!.email,
      photo: photo ?? '',
      role: _user!.role,
      status: _user!.status,
      createdAt: _user!.createdAt,
    );
    notifyListeners();
  }

  Future<bool> initializeSession() async {
    if (_sessionRestoreFuture != null) {
      return _sessionRestoreFuture!;
    }

    _sessionRestoreFuture = _restoreSession();
    try {
      return await _sessionRestoreFuture!;
    } finally {
      _sessionRestoreFuture = null;
    }
  }

  Future<bool> _restoreSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(AppConstants.tokenKey) ?? '';
      SessionTokenStore.currentToken = token.isNotEmpty ? token : null;
      final storedUserData = _readStoredUserData(prefs);

      if (storedUserData == null || token.isEmpty) {
        await _clearPersistedSession(prefs);
        if (kDebugMode) {
          debugPrint(
            '[AuthProvider.initializeSession] No persisted auth session found.',
          );
        }
        notifyListeners();
        return false;
      }

      _user = UserModel.fromJson(storedUserData);
      if ((_user?.id ?? '').isEmpty) {
        await _clearPersistedSession(prefs);

        if (kDebugMode) {
          debugPrint(
            '[AuthProvider.initializeSession] Cleared incomplete persisted session.',
          );
        }

        notifyListeners();
        return false;
      }

      if (kDebugMode) {
        debugPrint(
          '[AuthProvider.initializeSession] Restored cached session for userId=${_user?.id} role=${_user?.role}',
        );
      }

      notifyListeners();

      try {
        final validatedUserData = await _validateStoredSession(_user!);
        await _persistSession(prefs, validatedUserData, token);
        _user = UserModel.fromJson(validatedUserData);
        _error = null;

        if (kDebugMode) {
          debugPrint(
            '[AuthProvider.initializeSession] Session validated for userId=${_user?.id} role=${_user?.role}',
          );
        }

        notifyListeners();
        return true;
      } catch (e) {
        final message = _formatError(e);

        if (_shouldInvalidatePersistedSession(message)) {
          await _clearPersistedSession(prefs);

          if (kDebugMode) {
            debugPrint(
              '[AuthProvider.initializeSession] Cleared invalid session: $message',
            );
          }

          notifyListeners();
          return false;
        }

        if (kDebugMode) {
          debugPrint(
            '[AuthProvider.initializeSession] Session validation unavailable, using cached session: $message',
          );
        }

        _error = null;
        notifyListeners();
        return _user != null;
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[AuthProvider.initializeSession] Failed: $e');
      }
    }

    return false;
  }

  Future<void> checkLoginStatus() async {
    await initializeSession();
  }

  Future<bool> login({
    required String email,
    required String password,
  }) async {
    _setLoading(true);
    _error = null;

    try {
      late final Map<String, dynamic> result;

      try {
        result = await _apiService.login(email: email, password: password);
      } catch (error) {
        if (!_isInvalidCredentialsError(error)) {
          rethrow;
        }

        final adminResult = await _adminApiService.login(
          email: email,
          password: password,
        );

        await setAuthenticatedSession(
          userData: _normalizeAdminSessionData(
            adminResult,
            fallbackEmail: email,
          ),
          token: adminResult['token']?.toString() ?? '',
        );
        return true;
      }

      if (result['success'] == false) {
        _error = result['message'] ?? "Login failed";
        return false;
      }

      final userData = _extractUserData(result);
      if (userData == null) {
        _error = "No user data in response";
        return false;
      }

      await setAuthenticatedSession(
        userData: userData,
        token: result['token']?.toString() ?? '',
      );
      return true;
    } catch (e) {
      _error = _formatError(e);
      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<bool> register({
    required String fullName,
    required String email,
    required String password,
    required String confirmPassword,
  }) async {
    _setLoading(true);
    _error = null;

    try {
      final result = await _apiService.register(
        fullName: fullName,
        email: email,
        password: password,
        confirmPassword: confirmPassword,
      );

      if (result['success'] == false) {
        _error = result['message'] ?? "Registration failed";
        return false;
      }

      return true;
    } catch (e) {
      _error = _formatError(e);
      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<bool> verifySignupOtp({
    required String email,
    required String otp,
  }) async {
    _setLoading(true);
    _error = null;

    try {
      final result = await _apiService.verifySignupOtp(
        email: email,
        otp: otp,
      );

      if (result['success'] == false) {
        _error = result['message'] ?? "OTP verification failed";
        return false;
      }

      final userData = _extractUserData(result);
      if (userData == null) {
        _error = "No user data in response";
        return false;
      }

      await setAuthenticatedSession(
        userData: userData,
        token: result['token']?.toString() ?? '',
      );
      return true;
    } catch (e) {
      _error = _formatError(e);
      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<bool> resendSignupOtp(String email) async {
    _setLoading(true);
    _error = null;

    try {
      await _apiService.sendOtp(email: email, type: 'signup');
      return true;
    } catch (e) {
      _error = _formatError(e);
      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<bool> updateProfile({
    required String name,
    required String phone,
    String? email,
    String? photo,
  }) async {
    if (_user == null) return false;

    if (kDebugMode) {
      debugPrint(
        '[AuthProvider.updateProfile] userId=${_user!.id} role=${_user!.role} fields=${[
          'name',
          'phone',
          if (email != null) 'email',
          if (photo != null) 'photo',
        ]}',
      );
    }

    _setLoading(true);
    _error = null;

    try {
      final result = isAdmin
          ? await _adminApiService.updateAdminProfile(
              name: name,
              email: email ?? _user!.email,
              phone: phone,
              photo: photo,
            )
          : await _apiService.updateProfile(
              userId: _user!.id,
              name: name,
              phone: phone,
              email: email ?? _user!.email,
              photo: photo,
            );

      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(AppConstants.tokenKey) ??
          SessionTokenStore.currentToken ??
          '';
      await setAuthenticatedSession(userData: result, token: token);
      return true;
    } catch (e) {
      _error = _formatError(e);

      if (_shouldInvalidatePersistedSession(_error!)) {
        await _clearPersistedSession();
        notifyListeners();
      }

      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<bool> changePassword({
    required String currentPassword,
    required String newPassword,
    required String confirmPassword,
  }) async {
    if (_user == null) return false;

    if (kDebugMode) {
      debugPrint(
        '[AuthProvider.changePassword] userId=${_user!.id} role=${_user!.role} passwordLengths=current:${currentPassword.length},new:${newPassword.length},confirm:${confirmPassword.length}',
      );
    }

    _setLoading(true);
    _error = null;

    try {
      await _apiService.changePassword(
        userId: _user!.id,
        currentPassword: currentPassword,
        newPassword: newPassword,
        confirmPassword: confirmPassword,
      );
      return true;
    } catch (e) {
      _error = _formatError(e);

      if (_shouldInvalidatePersistedSession(_error!)) {
        await _clearPersistedSession();
        notifyListeners();
      }

      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<bool> deleteCurrentAccount() async {
    if (_user == null) return false;

    _setLoading(true);
    _error = null;

    try {
      await _apiService.deleteAccount(_user!.id);
      await _clearPersistedSession();
      notifyListeners();
      return true;
    } catch (e) {
      _error = _formatError(e);

      if (_shouldInvalidatePersistedSession(_error!)) {
        await _clearPersistedSession();
        notifyListeners();
      }

      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> getProfile() async {
    if (_user == null) return;

    try {
      final result = isAdmin
          ? await _adminApiService.getAdminProfile()
          : await _apiService.getProfile(_user!.id);
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(AppConstants.tokenKey) ??
          SessionTokenStore.currentToken ??
          '';
      await setAuthenticatedSession(userData: result, token: token);
    } catch (e) {
      _error = _formatError(e);

      if (_shouldInvalidatePersistedSession(_error!)) {
        await _clearPersistedSession();
        notifyListeners();
      }
    }
  }

  Future<bool> requestPasswordReset(String email) async {
    _setLoading(true);
    _error = null;

    try {
      await _apiService.requestPasswordReset(email);
      return true;
    } catch (e) {
      _error = _formatError(e);
      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<bool> verifyOtpAndResetPassword({
    required String email,
    required String otp,
    required String newPassword,
  }) async {
    _setLoading(true);
    _error = null;

    try {
      await _apiService.verifyOtpAndResetPassword(
        email: email,
        otp: otp,
        newPassword: newPassword,
      );
      return true;
    } catch (e) {
      _error = _formatError(e);
      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> logout() async {
    if (kDebugMode) {
      debugPrint(
        '[AuthProvider.logout] Clearing session for userId=${_user?.id} role=${_user?.role}',
      );
    }

    try {
      if (_user != null) {
        if (isAdmin) {
          await _adminApiService.logout().timeout(const Duration(seconds: 2));
        } else {
          await _apiService.logout().timeout(const Duration(seconds: 2));
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          '[AuthProvider.logout] Backend logout skipped: ${_formatError(e)}',
        );
      }
    }

    await _clearPersistedSession();

    if (kDebugMode) {
      debugPrint('[AuthProvider.logout] Session cleared');
    }

    notifyListeners();
  }

  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }
}
