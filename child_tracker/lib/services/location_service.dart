import 'dart:async';

import 'package:geolocator/geolocator.dart';

import 'notification_service.dart';

class LocationService {
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  StreamSubscription<Position>? _positionStream;
  bool _trackingEnabled = false;
  final NotificationService _notificationService = NotificationService();

  Future<bool> requestLocationPermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return false;
    }

    return true;
  }

  Future<bool> startTracking({
    required Function(Position) onLocationUpdate,
  }) async {
    if (_trackingEnabled) {
      return true;
    }

    final hasPermission = await requestLocationPermission();
    if (!hasPermission) {
      return false;
    }

    _trackingEnabled = true;
    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    ).listen((Position position) {
      onLocationUpdate(position);
      _notificationService.sendLocationUpdateNotification(
        position.latitude,
        position.longitude,
      );
    });

    return true;
  }

  Future<void> stopTracking() async {
    _trackingEnabled = false;
    await _positionStream?.cancel();
    _positionStream = null;
  }

  bool get isTracking => _trackingEnabled;

  Future<Position?> getCurrentLocation() async {
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
    } catch (e) {
      return null;
    }
  }

  void dispose() {
    stopTracking();
  }
}
