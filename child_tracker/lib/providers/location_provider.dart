import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../models/location_model.dart';
import 'package:geolocator/geolocator.dart';
import '../services/location_service.dart';

class LocationProvider with ChangeNotifier {
  final ApiService _apiService = ApiService();

  LocationModel? _liveLocation;
  List<LocationModel> _locationHistory = [];
  RouteDataModel? _routeData;
  bool _isLoading = false;
  String? _error;
  Timer? _refreshTimer;
  bool _isTracking = false;

  final LocationService _locationService = LocationService();
  bool _localTracking = false;

  bool get localTracking => _localTracking;

  LocationModel? get liveLocation => _liveLocation;
  List<LocationModel> get locationHistory => _locationHistory;
  RouteDataModel? get routeData => _routeData;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isTracking => _isTracking;

  Future<bool> getLiveLocation(String childId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _apiService.getLiveLocation(childId);
      _liveLocation = LocationModel(
        id: '',
        childId: childId,
        latitude: (response['latitude'] ?? 0).toDouble(),
        longitude: (response['longitude'] ?? 0).toDouble(),
        speed: (response['speed'] ?? 0).toDouble(),
        battery: response['battery'] ?? 0,
        recordedAt: response['recorded_at'] ?? 0,
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

  Future<bool> getLocationHistory(String childId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _apiService.getLocationHistory(childId);
      _locationHistory =
          response.map((json) => LocationModel.fromJson(json)).toList();
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

  Future<bool> getLocationHistoryByDate(String childId, String date) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response =
          await _apiService.getLocationHistoryByDate(childId, date);
      _locationHistory =
          response.map((json) => LocationModel.fromJson(json)).toList();
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

  Future<bool> getRouteData(String childId, String date) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _apiService.getRouteData(childId, date);
      _routeData = RouteDataModel.fromJson(response);
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

  void startLiveTracking(String childId, {int intervalSeconds = 30}) {
    if (_isTracking) return;

    _isTracking = true;
    _refreshTimer = Timer.periodic(
      Duration(seconds: intervalSeconds),
      (_) => getLiveLocation(childId),
    );
    notifyListeners();
  }

  void stopLiveTracking() {
    _isTracking = false;
    _refreshTimer?.cancel();
    _refreshTimer = null;
    notifyListeners();
  }

  void clearLocationHistory() {
    _locationHistory = [];
    _routeData = null;
    notifyListeners();
  }

  void clearLiveLocation() {
    _liveLocation = null;
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  Future<void> startLocalTracking(String childId) async {
    _localTracking = true;
    notifyListeners();
    await _locationService.startTracking(onLocationUpdate: (Position position) {
      _liveLocation = LocationModel(
        id: '',
        childId: childId,
        latitude: position.latitude,
        longitude: position.longitude,
        speed: position.speed,
        battery: 0,
        recordedAt: position.timestamp.millisecondsSinceEpoch,
      );
      notifyListeners();
    });
  }

  Future<void> stopLocalTracking() async {
    _localTracking = false;
    await _locationService.stopTracking();
    notifyListeners();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    stopLiveTracking();
    stopLocalTracking();
    _locationService.dispose();
    super.dispose();
  }
}
