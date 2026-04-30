import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/constants.dart';
import '../utils/session_token_store.dart';

class AdminApiService {
  final String baseUrl = ApiConfig.baseUrl;
  final String? token;

  AdminApiService({this.token});

  Future<Map<String, String>> _buildHeaders() async {
    final prefs = await SharedPreferences.getInstance();
    final authToken = token ??
        prefs.getString(AppConstants.tokenKey) ??
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
      throw Exception('Request timed out while trying to $action');
    } catch (e) {
      final message = e.toString();
      if (e is http.ClientException ||
          message.contains('Failed to fetch') ||
          message.contains('XMLHttpRequest') ||
          message.contains('SocketException') ||
          message.contains('Connection refused')) {
        throw Exception(
          'Unable to reach backend server. Check API URL, backend server, and CORS settings.',
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

    throw Exception(_extractError(response, action));
  }

  String _extractError(http.Response response, String action) {
    try {
      final body = jsonDecode(response.body);
      if (body is Map<String, dynamic> && body['error'] != null) {
        return body['error'].toString();
      }
    } catch (_) {
      // Fall through to raw body.
    }

    if (response.body.isNotEmpty) {
      return response.body;
    }

    return 'Failed to $action (HTTP ${response.statusCode})';
  }

  // ==================== ADMIN AUTHENTICATION ====================

  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    final response = await _sendRequest(
      http.post(
        Uri.parse('$baseUrl/admin/login'),
        headers: await _buildHeaders(),
        body: jsonEncode({
          'email': email,
          'password': password,
        }),
      ),
      'login as admin',
    );
    return Map<String, dynamic>.from(
        _decodeResponse(response, 'login as admin'));
  }

  Future<Map<String, dynamic>> logout() async {
    final response = await _sendRequest(
      http.post(
        Uri.parse('$baseUrl/admin/logout'),
        headers: await _buildHeaders(),
      ),
      'logout as admin',
    );
    return Map<String, dynamic>.from(
      _decodeResponse(response, 'logout as admin'),
    );
  }

  Future<Map<String, dynamic>> getAdminProfile() async {
    final response = await _sendRequest(
      http.get(
        Uri.parse('$baseUrl/admin/profile'),
        headers: await _buildHeaders(),
      ),
      'get admin profile',
    );
    return Map<String, dynamic>.from(
      _decodeResponse(response, 'get admin profile'),
    );
  }

  Future<Map<String, dynamic>> updateAdminProfile({
    required String name,
    required String email,
    String? phone,
    String? username,
    String? photo,
  }) async {
    final payload = {
      'name': name,
      'email': email,
      'phone': phone ?? '',
      'username': username ?? '',
      if (photo != null) 'photo': photo,
    };

    if (kDebugMode) {
      debugPrint(
        '[AdminApiService.updateAdminProfile] fields=${payload.keys.toList()} email=$email',
      );
    }

    final response = await _sendRequest(
      http.patch(
        Uri.parse('$baseUrl/admin/profile'),
        headers: await _buildHeaders(),
        body: jsonEncode(payload),
      ),
      'update admin profile',
    );
    return Map<String, dynamic>.from(
      _decodeResponse(response, 'update admin profile'),
    );
  }

  Future<Map<String, dynamic>> updateAdminPhoto(String photo) async {
    final payload = {
      'photo': photo,
    };

    if (kDebugMode) {
      debugPrint(
        '[AdminApiService.updateAdminPhoto] hasPhoto=${photo.isNotEmpty}',
      );
    }

    final response = await _sendRequest(
      http.patch(
        Uri.parse('$baseUrl/admin/profile'),
        headers: await _buildHeaders(),
        body: jsonEncode(payload),
      ),
      'update admin photo',
    );
    return Map<String, dynamic>.from(
      _decodeResponse(response, 'update admin photo'),
    );
  }

  Future<Map<String, dynamic>> createAdmin({
    required String name,
    required String email,
    required String password,
    String? role,
  }) async {
    final response = await _sendRequest(
      http.post(
        Uri.parse('$baseUrl/admin/create-admin'),
        headers: await _buildHeaders(),
        body: jsonEncode({
          'name': name,
          'email': email,
          'password': password,
          if (role != null) 'role': role,
        }),
      ),
      'create admin',
    );
    return Map<String, dynamic>.from(_decodeResponse(response, 'create admin'));
  }

  // ==================== SYSTEM STATS ====================

  Future<Map<String, dynamic>> getSystemStats() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/admin/stats/system'),
        headers: await _buildHeaders(),
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
      throw Exception('Failed to get system stats: $e');
    }
  }

  Future<Map<String, dynamic>> getTotalActiveUsers() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/admin/stats/active-users'),
        headers: await _buildHeaders(),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception(response.body);
      }
    } catch (e) {
      throw Exception('Failed to get active users: $e');
    }
  }

  Future<Map<String, dynamic>> getTotalDevices() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/admin/stats/total-devices'),
        headers: await _buildHeaders(),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception(response.body);
      }
    } catch (e) {
      throw Exception('Failed to get total devices: $e');
    }
  }

  Future<Map<String, dynamic>> getActiveDevices() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/admin/stats/active-devices'),
        headers: await _buildHeaders(),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception(response.body);
      }
    } catch (e) {
      throw Exception('Failed to get active devices: $e');
    }
  }

  Future<Map<String, dynamic>> getDailyActiveDevices({String? date}) async {
    try {
      var url = '$baseUrl/admin/stats/daily-active-devices';
      if (date != null) {
        url += '/$date';
      }
      final response = await http.get(
        Uri.parse(url),
        headers: await _buildHeaders(),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception(response.body);
      }
    } catch (e) {
      throw Exception('Failed to get daily active devices: $e');
    }
  }

  // ==================== USER MANAGEMENT ====================

  Future<List<dynamic>> getAllUsers() async {
    final response = await _sendRequest(
      http.get(
        Uri.parse('$baseUrl/admin/users'),
        headers: await _buildHeaders(),
      ),
      'get users',
    );
    return List<dynamic>.from(_decodeResponse(response, 'get users'));
  }

  Future<Map<String, dynamic>> blockUser(String userId) async {
    final response = await _sendRequest(
      http.patch(
        Uri.parse('$baseUrl/admin/blockUser/$userId'),
        headers: await _buildHeaders(),
      ),
      'block user',
    );
    return Map<String, dynamic>.from(_decodeResponse(response, 'block user'));
  }

  Future<Map<String, dynamic>> unblockUser(String userId) async {
    final response = await _sendRequest(
      http.patch(
        Uri.parse('$baseUrl/admin/unblockUser/$userId'),
        headers: await _buildHeaders(),
      ),
      'unblock user',
    );
    return Map<String, dynamic>.from(_decodeResponse(response, 'unblock user'));
  }

  Future<Map<String, dynamic>> deleteUser(String userId) async {
    final response = await _sendRequest(
      http.delete(
        Uri.parse('$baseUrl/admin/users/$userId'),
        headers: await _buildHeaders(),
      ),
      'delete user',
    );
    return Map<String, dynamic>.from(_decodeResponse(response, 'delete user'));
  }

  Future<Map<String, dynamic>> updateUser({
    required String userId,
    required String name,
    required String phone,
    String? email,
    String? role,
    String? photo,
  }) async {
    final payload = {
      'name': name,
      'phone': phone,
      if (email != null) 'email': email,
      if (role != null) 'role': role,
      if (photo != null) 'photo': photo,
    };

    if (kDebugMode) {
      debugPrint(
        '[AdminApiService.updateUser] userId=$userId fields=${payload.keys.toList()} role=${payload['role']}',
      );
    }

    final response = await _sendRequest(
      http.patch(
        Uri.parse('$baseUrl/admin/users/$userId'),
        headers: await _buildHeaders(),
        body: jsonEncode(payload),
      ),
      'update user',
    );
    return Map<String, dynamic>.from(_decodeResponse(response, 'update user'));
  }

  Future<Map<String, dynamic>> createUser({
    required String name,
    required String phone,
    required String email,
    required String password,
    String role = 'user',
    String? photo,
  }) async {
    final response = await _sendRequest(
      http.post(
        Uri.parse('$baseUrl/admin/users'),
        headers: await _buildHeaders(),
        body: jsonEncode({
          'name': name,
          'phone': phone,
          'email': email,
          'password': password,
          'role': role,
          if (photo != null) 'photo': photo,
        }),
      ),
      'create user',
    );
    return Map<String, dynamic>.from(_decodeResponse(response, 'create user'));
  }

  // ==================== DEVICE MANAGEMENT ====================

  Future<List<dynamic>> getAllDevices() async {
    final response = await _sendRequest(
      http.get(
        Uri.parse('$baseUrl/admin/devices'),
        headers: await _buildHeaders(),
      ),
      'get devices',
    );
    return List<dynamic>.from(_decodeResponse(response, 'get devices'));
  }

  Future<Map<String, dynamic>> createDevice({
    required String childId,
    required String imei,
    String? simNumber,
    String? firmware,
  }) async {
    final response = await _sendRequest(
      http.post(
        Uri.parse('$baseUrl${ApiConfig.devices}/register'),
        headers: await _buildHeaders(),
        body: jsonEncode({
          'child_id': childId,
          'imei': imei,
          if (simNumber != null && simNumber.isNotEmpty)
            'sim_number': simNumber,
          if (firmware != null && firmware.isNotEmpty) 'firmware': firmware,
        }),
      ),
      'create device',
    );
    return Map<String, dynamic>.from(
        _decodeResponse(response, 'create device'));
  }

  Future<Map<String, dynamic>> deactivateDevice(String deviceId) async {
    final response = await _sendRequest(
      http.patch(
        Uri.parse('$baseUrl/admin/deviceOff/$deviceId'),
        headers: await _buildHeaders(),
      ),
      'deactivate device',
    );
    return Map<String, dynamic>.from(
      _decodeResponse(response, 'deactivate device'),
    );
  }

  Future<Map<String, dynamic>> activateDevice(String deviceId) async {
    final response = await _sendRequest(
      http.patch(
        Uri.parse('$baseUrl/admin/deviceOn/$deviceId'),
        headers: await _buildHeaders(),
      ),
      'activate device',
    );
    return Map<String, dynamic>.from(
      _decodeResponse(response, 'activate device'),
    );
  }

  Future<Map<String, dynamic>> deleteDevice(String deviceId) async {
    final response = await _sendRequest(
      http.delete(
        Uri.parse('$baseUrl/admin/devices/$deviceId'),
        headers: await _buildHeaders(),
      ),
      'delete device',
    );
    return Map<String, dynamic>.from(
        _decodeResponse(response, 'delete device'));
  }

  Future<Map<String, dynamic>> updateDevice({
    required String deviceId,
    String? childId,
    String? imei,
    String? simNumber,
    String? firmware,
  }) async {
    final response = await _sendRequest(
      http.patch(
        Uri.parse('$baseUrl/admin/devices/$deviceId'),
        headers: await _buildHeaders(),
        body: jsonEncode({
          if (childId != null) 'child_id': childId,
          if (imei != null) 'imei': imei,
          if (simNumber != null) 'sim_number': simNumber,
          if (firmware != null) 'firmware_version': firmware,
        }),
      ),
      'update device',
    );
    return Map<String, dynamic>.from(
        _decodeResponse(response, 'update device'));
  }

  // ==================== SYSTEM LOGS ====================

  Future<List<dynamic>> getSystemLogs({int limit = 100}) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/admin/logs?limit=$limit'),
        headers: await _buildHeaders(),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception(response.body);
      }
    } catch (e) {
      throw Exception('Failed to get system logs: $e');
    }
  }

  Future<Map<String, dynamic>> deleteSystemLog({
    required String logId,
    required String collection,
  }) async {
    if (kDebugMode) {
      debugPrint(
        '[AdminApiService.deleteSystemLog] DELETE $baseUrl/admin/logs/$logId?collection=$collection',
      );
    }
    final response = await _sendRequest(
      http.delete(
        Uri.parse(
          '$baseUrl/admin/logs/$logId?collection=${Uri.encodeQueryComponent(collection)}',
        ),
        headers: await _buildHeaders(),
      ),
      'delete system log',
    );
    return Map<String, dynamic>.from(
      _decodeResponse(response, 'delete system log'),
    );
  }

  Future<Map<String, dynamic>> deleteAllSystemLogs() async {
    if (kDebugMode) {
      debugPrint(
          '[AdminApiService.deleteAllSystemLogs] DELETE $baseUrl/admin/logs');
    }
    final response = await _sendRequest(
      http.delete(
        Uri.parse('$baseUrl/admin/logs'),
        headers: await _buildHeaders(),
      ),
      'delete all system logs',
    );
    return Map<String, dynamic>.from(
      _decodeResponse(response, 'delete all system logs'),
    );
  }

  // ==================== CHILDREN MANAGEMENT ====================

  Future<List<dynamic>> getAllChildren() async {
    final response = await _sendRequest(
      http.get(
        Uri.parse('$baseUrl/admin/children'),
        headers: await _buildHeaders(),
      ),
      'get children',
    );
    return List<dynamic>.from(_decodeResponse(response, 'get children'));
  }

  Future<Map<String, dynamic>> getChildWithDevice(String childId) async {
    final response = await _sendRequest(
      http.get(
        Uri.parse('$baseUrl/children/device/$childId'),
        headers: await _buildHeaders(),
      ),
      'get child with device',
    );
    return Map<String, dynamic>.from(
      _decodeResponse(response, 'get child with device'),
    );
  }

  Future<Map<String, dynamic>> deleteChild(String childId) async {
    final response = await _sendRequest(
      http.delete(
        Uri.parse('$baseUrl/admin/children/$childId'),
        headers: await _buildHeaders(),
      ),
      'delete child',
    );
    return Map<String, dynamic>.from(_decodeResponse(response, 'delete child'));
  }

  Future<Map<String, dynamic>> updateChild({
    required String childId,
    required String name,
    required int age,
    String? userId,
    String? photo,
  }) async {
    final response = await _sendRequest(
      http.put(
        Uri.parse('$baseUrl/admin/children/$childId'),
        headers: await _buildHeaders(),
        body: jsonEncode({
          if (userId != null) 'user_id': userId,
          'name': name,
          'age': age,
          if (photo != null) 'photo': photo,
        }),
      ),
      'update child',
    );
    return Map<String, dynamic>.from(_decodeResponse(response, 'update child'));
  }

  Future<Map<String, dynamic>> blockChild(String childId) async {
    final response = await _sendRequest(
      http.patch(
        Uri.parse('$baseUrl/admin/children/block/$childId'),
        headers: await _buildHeaders(),
      ),
      'block child',
    );
    return Map<String, dynamic>.from(_decodeResponse(response, 'block child'));
  }

  Future<Map<String, dynamic>> unblockChild(String childId) async {
    final response = await _sendRequest(
      http.patch(
        Uri.parse('$baseUrl/admin/children/unblock/$childId'),
        headers: await _buildHeaders(),
      ),
      'unblock child',
    );
    return Map<String, dynamic>.from(
        _decodeResponse(response, 'unblock child'));
  }

  // ==================== ALERTS MANAGEMENT ====================

  Future<List<dynamic>> getAllAlerts() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/admin/alerts'),
        headers: await _buildHeaders(),
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

  Future<Map<String, dynamic>> deleteAlert(String alertId) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/admin/alerts/$alertId'),
        headers: await _buildHeaders(),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception(response.body);
      }
    } catch (e) {
      throw Exception('Failed to delete alert: $e');
    }
  }
}
