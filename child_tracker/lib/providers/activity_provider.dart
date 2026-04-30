import 'package:flutter/material.dart';

import '../models/child_activity_summary_model.dart';
import '../services/api_service.dart';

class ActivityProvider with ChangeNotifier {
  final ApiService _apiService = ApiService();

  List<Map<String, dynamic>> _activityLogs = [];
  Map<String, dynamic>? _todaySummary;
  Map<String, dynamic>? _weeklySummary;
  ChildActivitySummaryModel? _last24HourSummary;
  bool _isSummaryLoading = false;
  bool _isActivityLogsLoading = false;
  String? _error;
  String? _summaryError;
  String? _logsError;

  List<Map<String, dynamic>> get activityLogs => _activityLogs;
  Map<String, dynamic>? get todaySummary => _todaySummary;
  Map<String, dynamic>? get weeklySummary => _weeklySummary;
  ChildActivitySummaryModel? get last24HourSummary => _last24HourSummary;
  bool get isSummaryLoading => _isSummaryLoading;
  bool get isActivityLogsLoading => _isActivityLogsLoading;
  bool get isLoading => _isSummaryLoading || _isActivityLogsLoading;
  String? get error => _error;
  String? get summaryError => _summaryError;
  String? get logsError => _logsError;

  // Get Activity Logs
  Future<bool> getActivityLogs(String childId) async {
    _isActivityLogsLoading = true;
    _logsError = null;
    _error = _summaryError;
    notifyListeners();

    try {
      final response = await _apiService.getActivityLogs(childId);
      _activityLogs = List<Map<String, dynamic>>.from(response);
      _isActivityLogsLoading = false;
      _error = _summaryError;
      notifyListeners();
      return true;
    } catch (e) {
      _isActivityLogsLoading = false;
      _logsError = e.toString();
      _error = _logsError;
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
    _isActivityLogsLoading = true;
    _logsError = null;
    _error = _summaryError;
    notifyListeners();

    try {
      await _apiService.addActivityLog(
        childId: childId,
        eventType: eventType,
        description: description,
      );
      _isActivityLogsLoading = false;
      _error = _summaryError;
      notifyListeners();
      return true;
    } catch (e) {
      _isActivityLogsLoading = false;
      _logsError = e.toString();
      _error = _logsError;
      notifyListeners();
      return false;
    }
  }

  // Get rolling last-24-hour summary
  Future<bool> getLast24HourSummary(String childId) async {
    _isSummaryLoading = true;
    _summaryError = null;
    _error = _logsError;
    notifyListeners();

    try {
      final response = await _apiService.getLast24HourSummary(childId);
      _last24HourSummary = ChildActivitySummaryModel.fromJson(response);
      _isSummaryLoading = false;
      _error = _logsError;
      notifyListeners();
      return true;
    } catch (e) {
      _isSummaryLoading = false;
      _last24HourSummary = null;
      _summaryError = e.toString();
      _error = _summaryError;
      notifyListeners();
      return false;
    }
  }

  // Get Today's Summary
  Future<bool> getTodaySummary(String childId) async {
    _isSummaryLoading = true;
    _summaryError = null;
    _error = _logsError;
    notifyListeners();

    try {
      final response = await _apiService.getTodaySummary(childId);
      _todaySummary =
          response.isNotEmpty ? Map<String, dynamic>.from(response) : null;
      _isSummaryLoading = false;
      _error = _logsError;
      notifyListeners();
      return true;
    } catch (e) {
      _isSummaryLoading = false;
      _summaryError = e.toString();
      _error = _summaryError;
      notifyListeners();
      return false;
    }
  }

  // Get Weekly Summary
  Future<bool> getWeeklySummary(String childId) async {
    _isSummaryLoading = true;
    _summaryError = null;
    _error = _logsError;
    notifyListeners();

    try {
      final response = await _apiService.getWeeklySummary(childId);
      _weeklySummary = Map<String, dynamic>.from(response);
      _isSummaryLoading = false;
      _error = _logsError;
      notifyListeners();
      return true;
    } catch (e) {
      _isSummaryLoading = false;
      _summaryError = e.toString();
      _error = _summaryError;
      notifyListeners();
      return false;
    }
  }

  // Get Summary by Date
  Future<Map<String, dynamic>?> getSummaryByDate(
    String childId,
    String date,
  ) async {
    _isSummaryLoading = true;
    _summaryError = null;
    _error = _logsError;
    notifyListeners();

    try {
      final response = await _apiService.getSummaryByDate(childId, date);
      _isSummaryLoading = false;
      _error = _logsError;
      notifyListeners();
      return response.isNotEmpty ? response : null;
    } catch (e) {
      _isSummaryLoading = false;
      _summaryError = e.toString();
      _error = _summaryError;
      notifyListeners();
      return null;
    }
  }

  // Clear Error
  void clearError() {
    _error = null;
    _summaryError = null;
    _logsError = null;
    notifyListeners();
  }

  // Clear All Data
  void clearAll() {
    _activityLogs = [];
    _todaySummary = null;
    _weeklySummary = null;
    _last24HourSummary = null;
    _error = null;
    _summaryError = null;
    _logsError = null;
    notifyListeners();
  }
}
