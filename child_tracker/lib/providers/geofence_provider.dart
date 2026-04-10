import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../models/geofence_model.dart';

class GeofenceProvider with ChangeNotifier {
  final ApiService _apiService = ApiService();
  
  List<GeofenceModel> _safeZones = [];
  ZoneCheckResult? _zoneCheckResult;
  bool _isLoading = false;
  String? _error;

  List<GeofenceModel> get safeZones => _safeZones;
  ZoneCheckResult? get zoneCheckResult => _zoneCheckResult;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<bool> loadSafeZones(String childId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _apiService.getSafeZones(childId);
      _safeZones = response.map((json) => GeofenceModel.fromJson(json)).toList();
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

  Future<bool> loadAccessibleSafeZones({String search = ''}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _apiService.searchSafeZones(search: search);
      _safeZones =
          response.map((json) => GeofenceModel.fromJson(json)).toList();
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

  Future<bool> createSafeZone({
    required String childId,
    required String userId,
    String? childName,
    required String name,
    required double latitude,
    required double longitude,
    int? radius,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await _apiService.createSafeZone(
        childId: childId,
        userId: userId,
        childName: childName,
        name: name,
        latitude: latitude,
        longitude: longitude,
        radius: radius,
      );
      
      // Reload safe zones
      await loadSafeZones(childId);
      return true;
    } catch (e) {
      _isLoading = false;
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> updateSafeZone({
    required String zoneId,
    String? name,
    double? latitude,
    double? longitude,
    int? radius,
    String? status,
    String? childId,
    String? childName,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await _apiService.updateSafeZone(
        zoneId: zoneId,
        name: name,
        latitude: latitude,
        longitude: longitude,
        radius: radius,
        status: status,
        childId: childId,
        childName: childName,
      );
      
      if (childId != null && childId.isNotEmpty) {
        await loadSafeZones(childId);
      } else {
        await loadAccessibleSafeZones();
      }
      return true;
    } catch (e) {
      _isLoading = false;
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteSafeZone(String zoneId, {String? childId}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await _apiService.deleteSafeZone(zoneId);
      
      if (childId != null && childId.isNotEmpty) {
        await loadSafeZones(childId);
      } else {
        await loadAccessibleSafeZones();
      }
      return true;
    } catch (e) {
      _isLoading = false;
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> checkLocationInZone({
    required String childId,
    required double latitude,
    required double longitude,
  }) async {
    try {
      final response = await _apiService.checkLocationInZone(
        childId: childId,
        latitude: latitude,
        longitude: longitude,
      );
      _zoneCheckResult = ZoneCheckResult.fromJson(response);
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  void clearSafeZones() {
    _safeZones = [];
    _zoneCheckResult = null;
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
