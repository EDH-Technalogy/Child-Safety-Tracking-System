import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/constants.dart';
import '../utils/session_token_store.dart';

class ApiService {
  final String baseUrl = ApiConfig.baseUrl;

  // Headers
  Map<String, String> get headers => {
        'Content-Type': 'application/json',
      };

  Future<Map<String, String>> _buildAuthHeaders() async {
    final prefs = await SharedPreferences.getInstance();
    final authToken = prefs.getString(AppConstants.tokenKey) ??
        SessionTokenStore.currentToken;

    return {
      'Content-Type': 'application/json',
      if (authToken != null && authToken.isNotEmpty)
        'Authorization': 'Bearer $authToken',
    };
  }

  Future<http.Response> _sendRequest(
    Future<http.Response> request,
    String action,
  ) async {
    try {
      return await request.timeout(
        const Duration(milliseconds: ApiConfig.connectionTimeout),
      );
    } on TimeoutException {
      throw Exception(
        'Request timed out while trying to $action. Backend URL: $baseUrl. ${ApiConfig.backendSetupHint}',
      );
    } catch (e) {
      final message = e.toString();
      if (e is http.ClientException ||
          message.contains('Failed to fetch') ||
          message.contains('XMLHttpRequest') ||
          message.contains('SocketException') ||
          message.contains('Connection refused')) {
        throw Exception(
          'Unable to reach backend server at $baseUrl. ${ApiConfig.backendSetupHint}',
        );
      }
      throw Exception('Failed to $action: $message');
    }
  }

  dynamic _decodeResponse(http.Response response, String action) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) {
        return <String, dynamic>{};
      }
      final decoded = jsonDecode(response.body);
      if (decoded == null) {
        return <String, dynamic>{};
      }
      return decoded;
    }

    String? extractedError;
    try {
      final body = jsonDecode(response.body);
      if (body is Map<String, dynamic>) {
        if (body['error'] != null) {
          extractedError = body['error'].toString();
        } else if (body['message'] != null) {
          extractedError = body['message'].toString();
        }
      }
    } catch (_) {
      // Fall through to raw response.
    }

    throw Exception(
      extractedError ??
          (response.body.isNotEmpty
              ? response.body
              : 'Failed to $action (HTTP ${response.statusCode})'),
    );
  }

  Map<String, dynamic> _normalizeAuthResponse(
    Map<String, dynamic> response, {
    required String successMessage,
  }) {
    final nestedUser = response['user'];
    if (nestedUser is Map) {
      return response;
    }

    final hasTopLevelUser = response['id'] != null ||
        response['email'] != null ||
        response['name'] != null;

    if (!hasTopLevelUser) {
      return response;
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
      if (response.containsKey(key)) {
        user[key] = response[key];
      }
    }

    return {
      'success': response['success'] ?? true,
      'message': response['message'] ?? successMessage,
      'user': user,
      'token': response['token'],
    };
  }

  // ==================== USER API ====================

  // Register
  Future<Map<String, dynamic>> register({
    required String fullName,
    required String email,
    required String password,
    required String confirmPassword,
  }) async {
    final payload = {
      'fullName': fullName.trim(),
      'email': email.trim(),
      'password': password,
      'confirmPassword': confirmPassword,
      'type': 'signup',
    };

    final response = await _sendRequest(
      http.post(
        Uri.parse('${ApiConfig.authBaseUrl}/send-otp'),
        headers: headers,
        body: jsonEncode(payload),
      ),
      'register',
    );

    final decoded = _decodeResponse(response, 'register');
    if (decoded is! Map) {
      throw Exception('Invalid response format');
    }

    return _normalizeAuthResponse(
      Map<String, dynamic>.from(decoded),
      successMessage: 'Registration successful',
    );
  }

  Future<Map<String, dynamic>> verifySignupOtp({
    required String email,
    required String otp,
  }) async {
    final response = await _sendRequest(
      http.post(
        Uri.parse('${ApiConfig.authBaseUrl}/verify-otp'),
        headers: headers,
        body: jsonEncode({
          'email': email.trim(),
          'otp': otp.trim(),
          'type': 'signup',
        }),
      ),
      'verify OTP',
    );

    final decoded = _decodeResponse(response, 'verify OTP');
    if (decoded is! Map) {
      throw Exception('Invalid response format');
    }

    return _normalizeAuthResponse(
      Map<String, dynamic>.from(decoded),
      successMessage: 'Email verified successfully',
    );
  }

  Future<Map<String, dynamic>> sendOtp({
    required String email,
    required String type,
  }) async {
    final response = await _sendRequest(
      http.post(
        Uri.parse('${ApiConfig.authBaseUrl}/send-otp'),
        headers: headers,
        body: jsonEncode({
          'email': email.trim(),
          'type': type,
        }),
      ),
      'send OTP',
    );

    return Map<String, dynamic>.from(_decodeResponse(response, 'send OTP'));
  }

  // Login
  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    final response = await _sendRequest(
      http.post(
        Uri.parse('$baseUrl${ApiConfig.users}/login'),
        headers: headers,
        body: jsonEncode({
          'email': email,
          'password': password,
        }),
      ),
      'login',
    );

    final decoded = _decodeResponse(response, 'login');
    if (decoded is! Map) {
      throw Exception('Invalid response format');
    }

    return _normalizeAuthResponse(
      Map<String, dynamic>.from(decoded),
      successMessage: 'Login successful',
    );
  }

  // Get Profile
  Future<Map<String, dynamic>> getProfile(String userId) async {
    final response = await _sendRequest(
      http.get(
        Uri.parse('$baseUrl${ApiConfig.users}/$userId'),
        headers: await _buildAuthHeaders(),
      ),
      'get profile',
    );

    return Map<String, dynamic>.from(_decodeResponse(response, 'get profile'));
  }

  // Update Profile
  Future<Map<String, dynamic>> updateProfile({
    required String userId,
    required String name,
    required String phone,
    String? email,
    String? photo,
  }) async {
    final payload = {
      'name': name.trim(),
      'phone': phone.trim(),
      if (email != null) 'email': email.trim(),
      if (photo != null) 'photo': photo,
    };

    if (kDebugMode) {
      debugPrint(
        '[ApiService.updateProfile] userId=$userId fields=${payload.keys.toList()} hasPhoto=${payload.containsKey('photo')}',
      );
    }

    final response = await _sendRequest(
      http.put(
        Uri.parse('$baseUrl${ApiConfig.users}/$userId'),
        headers: await _buildAuthHeaders(),
        body: jsonEncode(payload),
      ),
      'update profile',
    );

    if (kDebugMode) {
      debugPrint(
        '[ApiService.updateProfile] status=${response.statusCode} userId=$userId',
      );
    }

    return Map<String, dynamic>.from(
      _decodeResponse(response, 'update profile'),
    );
  }

  Future<Map<String, dynamic>> changePassword({
    required String userId,
    required String currentPassword,
    required String newPassword,
    required String confirmPassword,
  }) async {
    final payload = {
      'currentPassword': currentPassword,
      'newPassword': newPassword,
      'confirmPassword': confirmPassword,
    };

    if (kDebugMode) {
      debugPrint(
        '[ApiService.changePassword] userId=$userId fields=${payload.keys.toList()} passwordLengths=current:${currentPassword.length},new:${newPassword.length},confirm:${confirmPassword.length}',
      );
    }

    final response = await _sendRequest(
      http.patch(
        Uri.parse('$baseUrl${ApiConfig.users}/$userId/password'),
        headers: await _buildAuthHeaders(),
        body: jsonEncode(payload),
      ),
      'change password',
    );

    if (kDebugMode) {
      debugPrint(
        '[ApiService.changePassword] status=${response.statusCode} userId=$userId',
      );
    }

    return Map<String, dynamic>.from(
      _decodeResponse(response, 'change password'),
    );
  }

  // Request Password Reset
  Future<Map<String, dynamic>> requestPasswordReset(String email) async {
    final response = await _sendRequest(
      http.post(
        Uri.parse('${ApiConfig.authBaseUrl}/send-otp'),
        headers: headers,
        body: jsonEncode({
          'email': email.trim(),
          'type': 'forgot',
        }),
      ),
      'request password reset',
    );

    return Map<String, dynamic>.from(
      _decodeResponse(response, 'request password reset'),
    );
  }

  // Logout
  Future<Map<String, dynamic>> logout() async {
    final response = await _sendRequest(
      http.post(
        Uri.parse('$baseUrl${ApiConfig.users}/logout'),
        headers: await _buildAuthHeaders(),
      ),
      'logout',
    );

    return Map<String, dynamic>.from(_decodeResponse(response, 'logout'));
  }

  // Delete current account
  Future<Map<String, dynamic>> deleteAccount(String userId) async {
    final response = await _sendRequest(
      http.delete(
        Uri.parse('$baseUrl${ApiConfig.users}/$userId'),
        headers: await _buildAuthHeaders(),
      ),
      'delete account',
    );

    return Map<String, dynamic>.from(
      _decodeResponse(response, 'delete account'),
    );
  }

  // Verify OTP and Reset Password
  Future<Map<String, dynamic>> verifyOtpAndResetPassword({
    required String email,
    required String otp,
    required String newPassword,
  }) async {
    final response = await _sendRequest(
      http.post(
        Uri.parse('${ApiConfig.authBaseUrl}/verify-otp'),
        headers: headers,
        body: jsonEncode({
          'email': email.trim(),
          'otp': otp.trim(),
          'type': 'forgot',
          'newPassword': newPassword,
        }),
      ),
      'reset password',
    );

    return Map<String, dynamic>.from(
      _decodeResponse(response, 'reset password'),
    );
  }

  // ==================== CHILD API ====================

  // Add Child (with optional device registration)
  Future<Map<String, dynamic>> addChild({
    required String userId,
    required String name,
    required int age,
    String? photo,
    String? imei,
    String? simNumber,
    String? firmware,
  }) async {
    final payload = {
      'user_id': userId.trim(),
      'name': name,
      'age': age,
      if (photo != null) 'photo': photo,
      if (imei != null && imei.isNotEmpty) 'imei': imei,
      if (simNumber != null) 'sim_number': simNumber,
      if (firmware != null) 'firmware': firmware,
    };

    if (kDebugMode) {
      debugPrint(
        '[ApiService.addChild] userId=${userId.trim()} fields=${payload.keys.toList()} hasPhoto=${(photo ?? '').isNotEmpty} registerDevice=${(imei ?? '').trim().isNotEmpty}',
      );
    }

    final response = await _sendRequest(
      http.post(
        Uri.parse('$baseUrl${ApiConfig.children}/add'),
        headers: await _buildAuthHeaders(),
        body: jsonEncode(payload),
      ),
      'add child',
    );

    return Map<String, dynamic>.from(_decodeResponse(response, 'add child'));
  }

  // Get Children
  Future<List<dynamic>> getChildren(String userId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl${ApiConfig.children}/$userId'),
        headers: await _buildAuthHeaders(),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception(response.body);
      }
    } catch (e) {
      throw Exception('Failed to get children: $e');
    }
  }

  // Get Child By ID
  Future<Map<String, dynamic>> getChildById(String childId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl${ApiConfig.children}/child/$childId'),
        headers: await _buildAuthHeaders(),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception(response.body);
      }
    } catch (e) {
      throw Exception('Failed to get child: $e');
    }
  }

  // Update Child
  Future<Map<String, dynamic>> updateChild({
    required String childId,
    required String name,
    required int age,
    String? userId,
    String? photo,
    bool? registerDevice,
    String? deviceId,
    String? imei,
    String? simNumber,
    String? firmware,
  }) async {
    final payload = {
      if (userId != null && userId.trim().isNotEmpty) 'user_id': userId.trim(),
      'name': name,
      'age': age,
      if (photo != null) 'photo': photo,
      if (registerDevice != null) 'register_device': registerDevice,
      if (deviceId != null && deviceId.trim().isNotEmpty)
        'device_id': deviceId.trim(),
      if (imei != null && imei.trim().isNotEmpty) 'imei': imei.trim(),
      if (simNumber != null) 'sim_number': simNumber,
      if (firmware != null && firmware.trim().isNotEmpty)
        'firmware': firmware.trim(),
    };

    if (kDebugMode) {
      debugPrint(
        '[ApiService.updateChild] childId=$childId fields=${payload.keys.toList()} registerDevice=$registerDevice hasPhoto=${payload.containsKey('photo')}',
      );
    }

    final response = await _sendRequest(
      http.put(
        Uri.parse('$baseUrl${ApiConfig.children}/$childId'),
        headers: await _buildAuthHeaders(),
        body: jsonEncode(payload),
      ),
      'update child',
    );

    return Map<String, dynamic>.from(_decodeResponse(response, 'update child'));
  }

  // Remove Child
  Future<Map<String, dynamic>> removeChild(String childId) async {
    final response = await _sendRequest(
      http.delete(
        Uri.parse('$baseUrl${ApiConfig.children}/$childId'),
        headers: await _buildAuthHeaders(),
      ),
      'remove child',
    );

    return Map<String, dynamic>.from(_decodeResponse(response, 'remove child'));
  }

  // Get Child With Device
  Future<Map<String, dynamic>> getChildWithDevice(String childId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl${ApiConfig.children}/device/$childId'),
        headers: await _buildAuthHeaders(),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception(response.body);
      }
    } catch (e) {
      throw Exception('Failed to get child with device: $e');
    }
  }

  // ==================== DEVICE API ====================

  // Register Device
  Future<Map<String, dynamic>> registerDevice({
    required String childId,
    required String imei,
    String? simNumber,
    String? firmware,
  }) async {
    final response = await _sendRequest(
      http.post(
        Uri.parse('$baseUrl${ApiConfig.devices}/register'),
        headers: await _buildAuthHeaders(),
        body: jsonEncode({
          'child_id': childId,
          'imei': imei,
          if (simNumber != null) 'sim_number': simNumber,
          if (firmware != null) 'firmware': firmware,
        }),
      ),
      'register device',
    );

    return Map<String, dynamic>.from(
      _decodeResponse(response, 'register device'),
    );
  }

  // Deactivate Device
  Future<Map<String, dynamic>> deactivateDevice(String deviceId) async {
    final response = await _sendRequest(
      http.patch(
        Uri.parse('$baseUrl${ApiConfig.devices}/deactivate/$deviceId'),
        headers: await _buildAuthHeaders(),
      ),
      'deactivate device',
    );

    return Map<String, dynamic>.from(
      _decodeResponse(response, 'deactivate device'),
    );
  }

  // ==================== LOCATION API ====================

  // Send Live Location Update
  Future<Map<String, dynamic>> updateLocation({
    required String childId,
    required double latitude,
    required double longitude,
    double? speed,
    int? battery,
    String? locationText,
    String? source,
    int? recordedAt,
  }) async {
    try {
      final response = await _sendRequest(
        http.post(
          Uri.parse('$baseUrl${ApiConfig.locations}/update'),
          headers: await _buildAuthHeaders(),
          body: jsonEncode({
            'child_id': childId,
            'latitude': latitude,
            'longitude': longitude,
            if (speed != null) 'speed': speed,
            if (battery != null) 'battery': battery,
            if (locationText != null && locationText.isNotEmpty)
              'location_text': locationText,
            if (source != null && source.isNotEmpty) 'source': source,
            if (recordedAt != null) 'recorded_at': recordedAt,
            if (recordedAt != null) 'timestamp': recordedAt,
          }),
        ),
        'send live location update',
      );

      return Map<String, dynamic>.from(
        _decodeResponse(response, 'send live location update'),
      );
    } catch (e) {
      throw Exception('Failed to send live location update: $e');
    }
  }

  // Get Live Location
  Future<Map<String, dynamic>> getLiveLocation(String childId) async {
    try {
      final response = await _sendRequest(
        http.get(
          Uri.parse('$baseUrl${ApiConfig.locations}/live/$childId'),
          headers: await _buildAuthHeaders(),
        ),
        'get live location',
      );

      final decoded = _decodeResponse(response, 'get live location');
      if (decoded is! Map) {
        throw Exception('Invalid live location response format');
      }

      final body = Map<String, dynamic>.from(decoded);
      final data = body['data'];
      if (data is Map<String, dynamic>) {
        return data;
      }
      if (data is Map) {
        return Map<String, dynamic>.from(data);
      }
      return body;
    } catch (e) {
      throw Exception('Failed to get live location: $e');
    }
  }

  // Get Location History
  Future<List<dynamic>> getLocationHistory(String childId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl${ApiConfig.locations}/history/$childId'),
        headers: await _buildAuthHeaders(),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception(response.body);
      }
    } catch (e) {
      throw Exception('Failed to get location history: $e');
    }
  }

  // Get Location History By Date
  Future<List<dynamic>> getLocationHistoryByDate(
    String childId,
    String date, {
    int? timezoneOffsetMinutes,
  }) async {
    try {
      final uri = Uri.parse(
        '$baseUrl${ApiConfig.locations}/history/$childId/$date',
      ).replace(
        queryParameters: timezoneOffsetMinutes == null
            ? null
            : {
                'timezone_offset_minutes': timezoneOffsetMinutes.toString(),
              },
      );
      final response = await http.get(
        uri,
        headers: await _buildAuthHeaders(),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception(response.body);
      }
    } catch (e) {
      throw Exception('Failed to get location history by date: $e');
    }
  }

  // Get Route Data
  Future<Map<String, dynamic>> getRouteData(
    String childId,
    String date, {
    int? timezoneOffsetMinutes,
  }) async {
    try {
      final uri = Uri.parse(
        '$baseUrl${ApiConfig.locations}/route/$childId/$date',
      ).replace(
        queryParameters: timezoneOffsetMinutes == null
            ? null
            : {
                'timezone_offset_minutes': timezoneOffsetMinutes.toString(),
              },
      );
      final response = await http.get(
        uri,
        headers: await _buildAuthHeaders(),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception(response.body);
      }
    } catch (e) {
      throw Exception('Failed to get route data: $e');
    }
  }

  // ==================== ALERT API ====================

  // Send SOS Alert
  Future<Map<String, dynamic>> sendSosAlert({
    required String childId,
    double? latitude,
    double? longitude,
    String? locationText,
    String? message,
  }) async {
    try {
      final response = await _sendRequest(
        http.post(
          Uri.parse('$baseUrl${ApiConfig.alerts}/sos'),
          headers: await _buildAuthHeaders(),
          body: jsonEncode({
            'child_id': childId,
            if (latitude != null) 'latitude': latitude,
            if (longitude != null) 'longitude': longitude,
            if (locationText != null && locationText.isNotEmpty)
              'location_text': locationText,
            if (message != null && message.isNotEmpty) 'message': message,
          }),
        ),
        'send SOS alert',
      );

      return Map<String, dynamic>.from(
        _decodeResponse(response, 'send SOS alert'),
      );
    } catch (e) {
      throw Exception('Failed to send SOS alert: $e');
    }
  }

  // Get Alerts
  Future<List<dynamic>> getAlerts(String childId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl${ApiConfig.alerts}/$childId'),
        headers: await _buildAuthHeaders(),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception(response.body);
      }
    } catch (e) {
      throw Exception('Failed to get alerts: $e');
    }
  }

  // Mark Alert as Read
  Future<Map<String, dynamic>> markAlertAsRead(
    String alertId, {
    String? childId,
  }) async {
    try {
      final query = childId == null
          ? ''
          : '?child_id=${Uri.encodeQueryComponent(childId)}';
      final response = await http.patch(
        Uri.parse('$baseUrl${ApiConfig.alerts}/read/$alertId$query'),
        headers: await _buildAuthHeaders(),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception(response.body);
      }
    } catch (e) {
      throw Exception('Failed to mark alert as read: $e');
    }
  }

  // Mark All Alerts as Read
  Future<Map<String, dynamic>> markAllAlertsAsRead(String childId) async {
    try {
      final response = await http.patch(
        Uri.parse('$baseUrl${ApiConfig.alerts}/read-all/$childId'),
        headers: await _buildAuthHeaders(),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception(response.body);
      }
    } catch (e) {
      throw Exception('Failed to mark all alerts as read: $e');
    }
  }

  // Get Unread Alerts Count
  Future<Map<String, dynamic>> getUnreadAlertsCount(String childId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl${ApiConfig.alerts}/unread-count/$childId'),
        headers: await _buildAuthHeaders(),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception(response.body);
      }
    } catch (e) {
      throw Exception('Failed to get unread alerts count: $e');
    }
  }

  // Delete Alert
  Future<Map<String, dynamic>> deleteAlert(
    String alertId, {
    String? childId,
  }) async {
    try {
      final query = childId == null
          ? ''
          : '?child_id=${Uri.encodeQueryComponent(childId)}';
      final response = await http.delete(
        Uri.parse('$baseUrl${ApiConfig.alerts}/$alertId$query'),
        headers: await _buildAuthHeaders(),
      );

      if (response.statusCode == 200 || response.statusCode == 204) {
        if (response.body.trim().isEmpty) {
          return <String, dynamic>{};
        }
        return jsonDecode(response.body);
      } else {
        throw Exception(response.body);
      }
    } catch (e) {
      throw Exception('Failed to delete alert: $e');
    }
  }

  // ==================== GEOFENCE API ====================

  // Create Safe Zone
  Future<Map<String, dynamic>> createSafeZone({
    required String childId,
    required String userId,
    String? childName,
    required String name,
    required double latitude,
    required double longitude,
    int? radius,
    String? centerSource,
  }) async {
    try {
      final payload = {
        'child_id': childId,
        'user_id': userId,
        if (childName != null && childName.isNotEmpty) 'child_name': childName,
        'name': name,
        'latitude': latitude,
        'longitude': longitude,
        if (radius != null) 'radius': radius,
        if (centerSource != null && centerSource.isNotEmpty)
          'center_source': centerSource,
      };

      if (kDebugMode) {
        debugPrint('[ApiService.createSafeZone] payload=$payload');
      }

      final response = await http.post(
        Uri.parse('$baseUrl${ApiConfig.geofence}/safe-zone'),
        headers: await _buildAuthHeaders(),
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        return jsonDecode(response.body);
      } else {
        throw Exception(response.body);
      }
    } catch (e) {
      throw Exception('Failed to create safe zone: $e');
    }
  }

  // Get Safe Zones
  Future<List<dynamic>> getSafeZones(String childId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl${ApiConfig.geofence}/safe-zones/$childId'),
        headers: await _buildAuthHeaders(),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception(response.body);
      }
    } catch (e) {
      throw Exception('Failed to get safe zones: $e');
    }
  }

  // Get all authorized safe zones, optionally filtered by child name or ID
  Future<List<dynamic>> searchSafeZones({String? search}) async {
    try {
      final query = (search ?? '').trim();
      final uri = query.isEmpty
          ? Uri.parse('$baseUrl${ApiConfig.geofence}/safe-zones')
          : Uri.parse(
              '$baseUrl${ApiConfig.geofence}/safe-zones?search=${Uri.encodeQueryComponent(query)}',
            );

      final response = await http.get(
        uri,
        headers: await _buildAuthHeaders(),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception(response.body);
      }
    } catch (e) {
      throw Exception('Failed to search safe zones: $e');
    }
  }

  // Update Safe Zone
  Future<Map<String, dynamic>> updateSafeZone({
    required String zoneId,
    String? name,
    double? latitude,
    double? longitude,
    int? radius,
    String? status,
    String? childId,
    String? childName,
    String? centerSource,
  }) async {
    try {
      final payload = {
        if (name != null) 'name': name,
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
        if (radius != null) 'radius': radius,
        if (status != null) 'status': status,
        if (childId != null && childId.isNotEmpty) 'child_id': childId,
        if (childName != null && childName.isNotEmpty) 'child_name': childName,
        if (centerSource != null && centerSource.isNotEmpty)
          'center_source': centerSource,
      };

      if (kDebugMode) {
        debugPrint(
            '[ApiService.updateSafeZone] zoneId=$zoneId payload=$payload');
      }

      final response = await http.put(
        Uri.parse('$baseUrl${ApiConfig.geofence}/safe-zone/$zoneId'),
        headers: await _buildAuthHeaders(),
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception(response.body);
      }
    } catch (e) {
      throw Exception('Failed to update safe zone: $e');
    }
  }

  // Delete Safe Zone
  Future<Map<String, dynamic>> deleteSafeZone(String zoneId) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl${ApiConfig.geofence}/safe-zone/$zoneId'),
        headers: await _buildAuthHeaders(),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception(response.body);
      }
    } catch (e) {
      throw Exception('Failed to delete safe zone: $e');
    }
  }

  // Check Location in Safe Zone
  Future<Map<String, dynamic>> checkLocationInZone({
    required String childId,
    required double latitude,
    required double longitude,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl${ApiConfig.geofence}/check-location'),
        headers: await _buildAuthHeaders(),
        body: jsonEncode({
          'child_id': childId,
          'latitude': latitude,
          'longitude': longitude,
        }),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception(response.body);
      }
    } catch (e) {
      throw Exception('Failed to check location in zone: $e');
    }
  }

  // ==================== ACTIVITY LOG API ====================

  // Add Activity Log
  Future<Map<String, dynamic>> addActivityLog({
    required String childId,
    required String eventType,
    required String description,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl${ApiConfig.activities}/add'),
        headers: await _buildAuthHeaders(),
        body: jsonEncode({
          'child_id': childId,
          'event_type': eventType,
          'description': description,
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        return jsonDecode(response.body);
      } else {
        throw Exception(response.body);
      }
    } catch (e) {
      throw Exception('Failed to add activity log: $e');
    }
  }

  // Get Activity Logs
  Future<List<dynamic>> getActivityLogs(String childId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl${ApiConfig.activities}/$childId'),
        headers: await _buildAuthHeaders(),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception(response.body);
      }
    } catch (e) {
      throw Exception('Failed to get activity logs: $e');
    }
  }

  // ==================== SUMMARY API ====================

  // Get rolling last-24-hour summary
  Future<Map<String, dynamic>> getLast24HourSummary(String childId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl${ApiConfig.summaries}/last-24-hours/$childId'),
        headers: await _buildAuthHeaders(),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception(response.body);
      }
    } catch (e) {
      throw Exception('Failed to get last 24 hour summary: $e');
    }
  }

  // Get Today's Summary
  Future<Map<String, dynamic>> getTodaySummary(String childId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl${ApiConfig.summaries}/today/$childId'),
        headers: await _buildAuthHeaders(),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception(response.body);
      }
    } catch (e) {
      throw Exception('Failed to get today summary: $e');
    }
  }

  // Get Summary by Date
  Future<Map<String, dynamic>> getSummaryByDate(
      String childId, String date) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl${ApiConfig.summaries}/$childId/$date'),
        headers: await _buildAuthHeaders(),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception(response.body);
      }
    } catch (e) {
      throw Exception('Failed to get summary by date: $e');
    }
  }

  // Get Weekly Summary
  Future<Map<String, dynamic>> getWeeklySummary(String childId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl${ApiConfig.summaries}/weekly/$childId'),
        headers: await _buildAuthHeaders(),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception(response.body);
      }
    } catch (e) {
      throw Exception('Failed to get weekly summary: $e');
    }
  }

  // Get SOS Count
  Future<Map<String, dynamic>> getSosCount(String childId,
      {String? startDate, String? endDate}) async {
    try {
      var url = '$baseUrl${ApiConfig.summaries}/sos-count/$childId';
      if (startDate != null && endDate != null) {
        url += '?start_date=$startDate&end_date=$endDate';
      }

      final response = await http.get(
        Uri.parse(url),
        headers: await _buildAuthHeaders(),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception(response.body);
      }
    } catch (e) {
      throw Exception('Failed to get SOS count: $e');
    }
  }

  // Get Zone Exit Count
  Future<Map<String, dynamic>> getZoneExitCount(String childId,
      {String? startDate, String? endDate}) async {
    try {
      var url = '$baseUrl${ApiConfig.summaries}/zone-exit-count/$childId';
      if (startDate != null && endDate != null) {
        url += '?start_date=$startDate&end_date=$endDate';
      }

      final response = await http.get(
        Uri.parse(url),
        headers: await _buildAuthHeaders(),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception(response.body);
      }
    } catch (e) {
      throw Exception('Failed to get zone exit count: $e');
    }
  }

  // Generate Daily Summary
  Future<Map<String, dynamic>> generateDailySummary({
    required String childId,
    String? date,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl${ApiConfig.summaries}/generate'),
        headers: await _buildAuthHeaders(),
        body: jsonEncode({
          'child_id': childId,
          if (date != null) 'date': date,
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        return jsonDecode(response.body);
      } else {
        throw Exception(response.body);
      }
    } catch (e) {
      throw Exception('Failed to generate daily summary: $e');
    }
  }
}
