import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../models/location_model.dart';
import '../services/api_service.dart';
import '../services/device_live_tracking_service.dart';
import '../services/location_service.dart';

class LocationProvider with ChangeNotifier {
  final ApiService _apiService = ApiService();
  final DeviceLiveTrackingService _liveTrackingService =
      DeviceLiveTrackingService();
  final LocationService _locationService = LocationService();

  static const Duration _markerAnimationDuration = Duration(milliseconds: 900);
  static const Duration _markerAnimationTick = Duration(milliseconds: 45);
  static const double _snapAnimationThresholdMeters = 2500;

  LocationModel? _liveLocation;
  List<LocationModel> _locationHistory = [];
  RouteDataModel? _routeData;
  bool _isLoading = false;
  String? _error;
  StreamSubscription? _liveTrackingSubscription;
  Timer? _markerAnimationTimer;
  bool _isTracking = false;
  bool _isAnimatingLiveLocation = false;
  String? _trackingChildId;
  String? _localTrackingChildId;

  bool _localTracking = false;

  bool get localTracking => _localTracking;
  LocationModel? get liveLocation => _liveLocation;
  List<LocationModel> get locationHistory => _locationHistory;
  RouteDataModel? get routeData => _routeData;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isTracking => _isTracking;
  bool get isAnimatingLiveLocation => _isAnimatingLiveLocation;
  String? get trackingChildId => _trackingChildId;

  Future<bool> getLiveLocation(String childId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final context = await _liveTrackingService.resolveChildTracking(childId);
      final tracking = await _liveTrackingService.getResolvedChildLiveTracking(
        childId: context.child.id,
        device: context.device,
      );
      final nextLocation = tracking.location;
      if (!_isValidLocation(nextLocation)) {
        _liveLocation = null;
        _isLoading = false;
        _error = 'No live location available right now.';
        notifyListeners();
        return false;
      }

      _setLiveLocationImmediately(nextLocation!);
      return true;
    } catch (error) {
      _liveLocation = null;
      _isLoading = false;
      _error = _formatError(error);
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

  Future<bool> getLocationHistoryByDate(
    String childId,
    String date, {
    int? timezoneOffsetMinutes,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _apiService.getLocationHistoryByDate(
        childId,
        date,
        timezoneOffsetMinutes: timezoneOffsetMinutes,
      );
      _locationHistory =
          response.map((json) => LocationModel.fromJson(json)).toList();
      _routeData = null;
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _locationHistory = [];
      _routeData = null;
      _isLoading = false;
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> getRouteData(
    String childId,
    String date, {
    int? timezoneOffsetMinutes,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _apiService.getRouteData(
        childId,
        date,
        timezoneOffsetMinutes: timezoneOffsetMinutes,
      );
      _routeData = RouteDataModel.fromJson(response);
      _locationHistory = _routeData!.coordinates
          .map(
            (coordinate) => LocationModel(
              id: '',
              childId: childId,
              latitude: coordinate.latitude,
              longitude: coordinate.longitude,
              speed: 0,
              battery: 0,
              recordedAt: coordinate.time,
            ),
          )
          .toList();
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _routeData = null;
      _locationHistory = [];
      _isLoading = false;
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  void startLiveTracking(String childId, {int intervalSeconds = 30}) {
    final normalizedChildId = childId.trim();
    if (normalizedChildId.isEmpty) {
      return;
    }

    if (_isTracking &&
        _trackingChildId == normalizedChildId &&
        _liveTrackingSubscription != null) {
      return;
    }

    stopLiveTracking(clearLocation: false);
    _trackingChildId = normalizedChildId;
    _isTracking = true;
    _isLoading = true;
    _error = null;
    notifyListeners();

    unawaited(_startRealtimeTracking(normalizedChildId));
  }

  Future<void> _startRealtimeTracking(String childId) async {
    try {
      final context = await _liveTrackingService.resolveChildTracking(childId);
      if (_trackingChildId != childId) {
        return;
      }

      final trackingKey =
          _liveTrackingService.resolveRealtimeTrackingKey(context.device);
      debugPrint(
        '[LocationProvider.stream] subscribing childId=$childId trackingKey=$trackingKey rtdbPath=/live_tracking/$trackingKey/location',
      );

      await _liveTrackingSubscription?.cancel();
      _liveTrackingSubscription = _liveTrackingService
          .watchResolvedChildLiveTracking(
        childId: context.child.id,
        device: context.device,
      )
          .listen(
        (tracking) {
          if (_trackingChildId != childId) {
            return;
          }

          final nextLocation = tracking.location;
          if (!_isValidLocation(nextLocation)) {
            if (_liveLocation == null) {
              _error = 'No live location available right now.';
            }
            _isLoading = false;
            notifyListeners();
            return;
          }

          debugPrint(
            '[LocationProvider.stream] update childId=$childId lat=${nextLocation!.latitude} lng=${nextLocation.longitude} recordedAt=${nextLocation.recordedAt}',
          );
          _handleRealtimeLocation(nextLocation);
        },
        onError: (error) {
          if (_trackingChildId != childId) {
            return;
          }

          debugPrint('[LocationProvider.stream] error childId=$childId $error');
          _isLoading = false;
          _error = _formatError(error);
          notifyListeners();
        },
        onDone: () {
          if (_trackingChildId != childId) {
            return;
          }

          debugPrint('[LocationProvider.stream] closed childId=$childId');
          _isTracking = false;
          notifyListeners();
        },
      );
    } catch (error) {
      if (_trackingChildId != childId) {
        return;
      }

      debugPrint('[LocationProvider.stream] failed childId=$childId $error');
      _isLoading = false;
      _error = _formatError(error);
      notifyListeners();
    }
  }

  void _handleRealtimeLocation(LocationModel nextLocation) {
    final currentLocation = _liveLocation;
    if (!_isValidLocation(currentLocation)) {
      _setLiveLocationImmediately(nextLocation);
      return;
    }

    final distance = Geolocator.distanceBetween(
      currentLocation!.latitude,
      currentLocation.longitude,
      nextLocation.latitude,
      nextLocation.longitude,
    );

    if (distance >= _snapAnimationThresholdMeters) {
      _setLiveLocationImmediately(nextLocation);
      return;
    }

    _animateLiveLocation(currentLocation, nextLocation);
  }

  void _setLiveLocationImmediately(LocationModel nextLocation) {
    _cancelMarkerAnimation();
    _liveLocation = nextLocation;
    _isLoading = false;
    _error = null;
    notifyListeners();
  }

  void _animateLiveLocation(LocationModel from, LocationModel to) {
    _cancelMarkerAnimation();
    _isAnimatingLiveLocation = true;
    final startedAt = DateTime.now();

    _markerAnimationTimer = Timer.periodic(_markerAnimationTick, (timer) {
      final elapsed = DateTime.now().difference(startedAt);
      final rawProgress =
          elapsed.inMilliseconds / _markerAnimationDuration.inMilliseconds;
      final progress = rawProgress.clamp(0.0, 1.0).toDouble();
      final easedProgress = Curves.easeInOut.transform(progress);

      _liveLocation = _interpolateLocation(from, to, easedProgress);
      _isLoading = false;
      _error = null;

      if (progress >= 1.0) {
        _liveLocation = to;
        _isAnimatingLiveLocation = false;
        timer.cancel();
        _markerAnimationTimer = null;
      }

      notifyListeners();
    });
  }

  LocationModel _interpolateLocation(
    LocationModel from,
    LocationModel to,
    double progress,
  ) {
    final latitude = from.latitude + ((to.latitude - from.latitude) * progress);
    final longitude =
        from.longitude + ((to.longitude - from.longitude) * progress);

    return LocationModel(
      id: to.id,
      childId: to.childId,
      latitude: latitude,
      longitude: longitude,
      speed: to.speed,
      battery: to.battery,
      recordedAt: to.recordedAt,
    );
  }

  bool _isValidLocation(LocationModel? location) {
    if (location == null) {
      return false;
    }

    return location.latitude >= -90 &&
        location.latitude <= 90 &&
        location.longitude >= -180 &&
        location.longitude <= 180;
  }

  void _cancelMarkerAnimation() {
    _markerAnimationTimer?.cancel();
    _markerAnimationTimer = null;
    _isAnimatingLiveLocation = false;
  }

  String _formatError(Object? error) {
    final message =
        error?.toString().replaceFirst('Exception: ', '').trim() ?? '';
    if (message.isNotEmpty) {
      return message;
    }

    return 'Live tracking is temporarily unavailable.';
  }

  void stopLiveTracking({bool clearLocation = false}) {
    _isTracking = false;
    _trackingChildId = null;
    _liveTrackingSubscription?.cancel();
    _liveTrackingSubscription = null;
    _cancelMarkerAnimation();
    if (clearLocation) {
      _liveLocation = null;
    }
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
    final normalizedChildId = childId.trim();
    if (normalizedChildId.isEmpty) {
      _error = 'Select a child before starting location tracking.';
      notifyListeners();
      return;
    }

    if (_localTracking &&
        _localTrackingChildId == normalizedChildId &&
        _locationService.isTracking) {
      return;
    }

    if (_locationService.isTracking) {
      await _locationService.stopTracking();
    }

    _localTracking = true;
    _localTrackingChildId = normalizedChildId;
    _error = null;
    notifyListeners();
    final started = await _locationService.startTracking(
        onLocationUpdate: (Position position) {
      final location = LocationModel(
        id: '',
        childId: normalizedChildId,
        latitude: position.latitude,
        longitude: position.longitude,
        speed: position.speed,
        battery: 0,
        recordedAt: position.timestamp.millisecondsSinceEpoch,
      );
      _liveLocation = location;
      notifyListeners();

      unawaited(_uploadLocalTrackingLocation(location));
    });

    if (!started) {
      _localTracking = false;
      _localTrackingChildId = null;
      _error = 'Location permission is required to start live tracking.';
      notifyListeners();
    }
  }

  Future<void> stopLocalTracking() async {
    _localTracking = false;
    _localTrackingChildId = null;
    await _locationService.stopTracking();
    notifyListeners();
  }

  Future<bool> sendSosForChild(
    String childId, {
    String? message,
  }) async {
    final normalizedChildId = childId.trim();
    if (normalizedChildId.isEmpty) {
      _error = 'Select a child before sending SOS.';
      notifyListeners();
      return false;
    }

    try {
      LocationModel? location = _liveLocation;
      if (location == null || location.childId != normalizedChildId) {
        final currentPosition = await _locationService.getCurrentLocation();
        if (currentPosition != null) {
          location = LocationModel(
            id: '',
            childId: normalizedChildId,
            latitude: currentPosition.latitude,
            longitude: currentPosition.longitude,
            speed: currentPosition.speed,
            battery: 0,
            recordedAt: currentPosition.timestamp.millisecondsSinceEpoch,
          );
          _liveLocation = location;
          notifyListeners();
        }
      }

      await _apiService.sendSosAlert(
        childId: normalizedChildId,
        latitude: location?.latitude,
        longitude: location?.longitude,
        message: message,
      );

      _error = null;
      notifyListeners();
      return true;
    } catch (error) {
      _error = _formatError(error);
      notifyListeners();
      return false;
    }
  }

  Future<void> _uploadLocalTrackingLocation(LocationModel location) async {
    try {
      await _apiService.updateLocation(
        childId: location.childId,
        latitude: location.latitude,
        longitude: location.longitude,
        speed: location.speed,
        battery: location.battery,
        source: 'mobile_app',
        recordedAt: location.recordedAt,
      );
    } catch (error) {
      _error = _formatError(error);
      notifyListeners();
      debugPrint(
        '[LocationProvider.localTracking] upload failed childId=${location.childId} error=$error',
      );
    }
  }

  @override
  void dispose() {
    stopLiveTracking(clearLocation: false);
    stopLocalTracking();
    _locationService.dispose();
    super.dispose();
  }
}
