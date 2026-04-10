import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../models/alert_model.dart';

class AlertProvider with ChangeNotifier {
  final ApiService _apiService = ApiService();
  
  List<AlertModel> _alerts = [];
  int _unreadCount = 0;
  bool _isLoading = false;
  String? _error;

  List<AlertModel> get alerts => _alerts;
  int get unreadCount => _unreadCount;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<bool> loadAlerts(String childId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _apiService.getAlerts(childId);
      _alerts = response.map((json) => AlertModel.fromJson(json)).toList();
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

  Future<bool> getUnreadCount(String childId) async {
    try {
      final response = await _apiService.getUnreadAlertsCount(childId);
      _unreadCount = response['count'] ?? 0;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> markAsRead(String alertId, String childId) async {
    try {
      await _apiService.markAlertAsRead(alertId);
      await loadAlerts(childId);
      await getUnreadCount(childId);
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> markAllAsRead(String childId) async {
    try {
      await _apiService.markAllAlertsAsRead(childId);
      await loadAlerts(childId);
      await getUnreadCount(childId);
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  void clearAlerts() {
    _alerts = [];
    _unreadCount = 0;
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
