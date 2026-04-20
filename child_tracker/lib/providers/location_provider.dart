import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../models/location_model.dart';
import 'package:geolocator/geolocator.dart';
import '../services/location_service.dart';

class LocationProvider with ChangeNotifier {
  final ApiService _apiService = ApiService();
  static const Duration _livePollingInterval = Duration(seconds: 2);

  LocationModel? _liveLocation;
  List<LocationModel> _locationHistory = [];
  RouteDataModel? _routeData;
  bool _isLoading = false;
  String? _error;
  Timer? _livePollingTimer;
  bool _isTracking = false;
  String? _trackingChildId;

  final LocationService _locationService = LocationService();
  bool _localTracking = false;

  bool get localTracking => _localTracking;

  LocationModel? get liveLocation => _liveLocation;
  List<LocationModel> get locationHistory => _locationHistory;
  RouteDataModel? get routeData => _routeData;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isTracking => _isTracking;
  String? get trackingChildId => _trackingChildId;

  Future<bool> getLiveLocation(String childId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    return _loadLiveLocationFromApi(childId);
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
    if (_isTracking && _trackingChildId == childId) {
      return;
    }

    stopLiveTracking();
    _trackingChildId = childId;
    _isTracking = true;
    _isLoading = true;
    _error = null;
    notifyListeners();

    unawaited(_startApiPolling(childId));
  }

  Future<void> _startApiPolling(String childId) async {
    await _loadLiveLocationFromApi(childId);
    if (_trackingChildId != childId) {
      return;
    }

    _cancelLivePolling();
    _livePollingTimer = Timer.periodic(_livePollingInterval, (_) {
      if (_trackingChildId != childId) {
        _cancelLivePolling();
        return;
      }

      unawaited(_loadLiveLocationFromApi(childId, keepLastKnownLocation: true));
    });
  }

  Future<bool> _loadLiveLocationFromApi(
    String childId, {
    bool keepLastKnownLocation = false,
  }) async {
    try {
      final response = await _apiService.getLiveLocation(childId);
      if (response.isEmpty) {
        if (!keepLastKnownLocation) {
          _liveLocation = null;
        }
        _isLoading = false;
        _error = 'No live location available right now.';
        notifyListeners();
        return false;
      }

      _liveLocation = LocationModel.fromJson({
        'id': '',
        'child_id': childId,
        ...response,
      });
      _isLoading = false;
      _error = null;
      notifyListeners();
      return true;
    } catch (apiError) {
      if (!keepLastKnownLocation) {
        _liveLocation = null;
      }
      _isLoading = false;
      _error = _formatError(apiError);
      notifyListeners();
      return false;
    }
  }

  void _cancelLivePolling() {
    _livePollingTimer?.cancel();
    _livePollingTimer = null;
  }

  String _formatError(Object? error) {
    final message =
        error?.toString().replaceFirst('Exception: ', '').trim() ?? '';
    if (message.isNotEmpty) {
      return message;
    }

    return 'Live tracking is temporarily unavailable.';
  }

  void stopLiveTracking() {
    _isTracking = false;
    _trackingChildId = null;
    _cancelLivePolling();
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
    _cancelLivePolling();
    stopLiveTracking();
    stopLocalTracking();
    _locationService.dispose();
    super.dispose();
  }
}
