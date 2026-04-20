import 'dart:async';

import 'package:flutter/material.dart';

import '../models/child_model.dart';
import '../models/live_tracking_model.dart';
import '../models/location_model.dart';
import '../services/device_live_tracking_service.dart';

class DeviceLiveTrackingProvider with ChangeNotifier {
  final DeviceLiveTrackingService _service = DeviceLiveTrackingService();

  StreamSubscription<LiveTrackingModel>? _trackingSubscription;
  DeviceModel? _device;
  ChildModel? _child;
  LiveTrackingModel? _liveTracking;
  bool _hasSearched = false;
  bool _isLoading = false;
  bool _isListening = false;
  String? _error;

  DeviceModel? get device => _device;
  ChildModel? get child => _child;
  LiveTrackingModel? get liveTracking => _liveTracking;
  LocationModel? get liveLocation => _liveTracking?.location;
  bool get hasSearched => _hasSearched;
  bool get isLoading => _isLoading;
  bool get isListening => _isListening;
  String? get error => _error;
  bool get hasSelection => _device != null && _child != null;

  Future<bool> trackDeviceById(String rawDeviceId) async {
    _hasSearched = true;
    _isLoading = true;
    _isListening = false;
    _error = null;
    _liveTracking = null;
    _device = null;
    _child = null;
    notifyListeners();

    await _trackingSubscription?.cancel();
    _trackingSubscription = null;

    try {
      final result = await _service.lookupDevice(rawDeviceId);
      _device = result.device;
      _child = result.child;

      _trackingSubscription = _service
          .watchResolvedChildLiveTracking(
            childId: result.child.id,
            device: result.device,
            childCreatedAt: result.child.createdAt,
          )
          .listen(_handleTrackingUpdate, onError: _handleTrackingError);

      _isLoading = false;
      _isListening = true;
      notifyListeners();
      return true;
    } catch (error) {
      _isLoading = false;
      _isListening = false;
      _error = _formatError(error);
      notifyListeners();
      return false;
    }
  }

  Future<void> clearTracking() async {
    await _trackingSubscription?.cancel();
    _trackingSubscription = null;
    _device = null;
    _child = null;
    _liveTracking = null;
    _hasSearched = false;
    _isLoading = false;
    _isListening = false;
    _error = null;
    notifyListeners();
  }

  void _handleTrackingUpdate(LiveTrackingModel tracking) {
    _liveTracking = tracking.hasLiveData ? tracking : null;
    _error = null;
    _isLoading = false;
    _isListening = true;
    notifyListeners();
  }

  void _handleTrackingError(Object error) {
    _isListening = false;
    _error = _formatError(error);
    notifyListeners();
  }

  String _formatError(Object error) {
    final message = error.toString().replaceFirst('Bad state: ', '').trim();
    if (message.isNotEmpty) {
      return message;
    }

    return 'Unable to load live tracking right now.';
  }

  @override
  void dispose() {
    _trackingSubscription?.cancel();
    super.dispose();
  }
}
