import 'package:flutter/material.dart';
import '../services/api_service.dart';

class ActivityProvider with ChangeNotifier {
  final ApiService _apiService = ApiService();

  List<Map<String, dynamic>> _activityLogs = [];
  Map<String, dynamic>? _todaySummary;
  Map<String, dynamic>? _weeklySummary;
  bool _isLoading = false;
  String? _error;

  List<Map<String, dynamic>> get activityLogs => _activityLogs;
  Map<String, dynamic>? get todaySummary => _todaySummary;
  Map<String, dynamic>? get weeklySummary => _weeklySummary;
  bool get isLoading => _isLoading;
  String? get error => _error;

  // Get Activity Logs
  Future<bool> getActivityLogs(String childId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _apiService.getActivityLogs(childId);
      _activityLogs = List<Map<String, dynamic>>.from(response);
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _isLoading = false;
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  // Add Activity Log
  Future<bool> addActivityLog({
    required String childId,
    required String eventType,
    required String description,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await _apiService.addActivityLog(
        childId: childId,
        eventType: eventType,
        description: description,
      );
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _isLoading = false;
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  // Get Today's Summary
  Future<bool> getTodaySummary(String childId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _apiService.getTodaySummary(childId);
      _todaySummary =
          response.isNotEmpty ? Map<String, dynamic>.from(response) : null;
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _isLoading = false;
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  // Get Weekly Summary
  Future<bool> getWeeklySummary(String childId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _apiService.getWeeklySummary(childId);
      _weeklySummary = Map<String, dynamic>.from(response);
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _isLoading = false;
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  // Get Summary by Date
  Future<Map<String, dynamic>?> getSummaryByDate(
      String childId, String date) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _apiService.getSummaryByDate(childId, date);
      _isLoading = false;
      notifyListeners();
      return response.isNotEmpty ? response : null;
    } catch (e) {
      _isLoading = false;
      _error = e.toString();
      notifyListeners();
      return null;
    }
  }

  // Clear Error
  void clearError() {
    _error = null;
    notifyListeners();
  }

  // Clear All Data
  void clearAll() {
    _activityLogs = [];
    _todaySummary = null;
    _weeklySummary = null;
    _error = null;
    notifyListeners();
  }
}
