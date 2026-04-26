import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/child_model.dart';
import '../models/live_tracking_model.dart';
import 'api_service.dart';
import '../utils/constants.dart';
import '../utils/firebase_bootstrap.dart';

class DeviceLookupResult {
  final DeviceModel device;
  final ChildModel child;

  const DeviceLookupResult({
    required this.device,
    required this.child,
  });
}

class DeviceLiveTrackingService {
  final ApiService _apiService = ApiService();

  String _normalizeTrackingKey(String rawValue) {
    final originalValue = rawValue.trim();
    if (originalValue.isEmpty) {
      return '';
    }

    final decodedValue =
        originalValue.replaceAll(RegExp(r'~2F', caseSensitive: false), '/');
    final match = RegExp(r'live_tracking/([^/?#]+)', caseSensitive: false)
        .firstMatch(decodedValue);
    if (match != null) {
      final normalized = match.group(1)?.trim() ?? '';
      if (normalized.isNotEmpty) {
        return normalized;
      }
    }

    return originalValue;
  }

  String resolveRealtimeTrackingKey(DeviceModel device) {
    final imeiKey = _normalizeTrackingKey(device.imei);
    if (imeiKey.isNotEmpty) {
      return imeiKey;
    }

    final documentKey = _normalizeTrackingKey(device.id);
    if (documentKey.isNotEmpty) {
      return documentKey;
    }

    throw StateError(
      'The linked device is missing a valid Firebase Realtime Database tracking ID.',
    );
  }

  Future<DeviceLookupResult> resolveChildTracking(String childId) async {
    final normalizedChildId = childId.trim();
    if (normalizedChildId.isEmpty) {
      throw StateError('Child ID is required.');
    }

    final response = await _apiService.getChildWithDevice(normalizedChildId);
    final childPayload = response['child'];
    if (childPayload is! Map) {
      throw StateError('The linked child record could not be found.');
    }

    final childData = Map<String, dynamic>.from(childPayload);
    final devicePayload = response['device'];
    final resolvedDevice = devicePayload is Map
        ? DeviceModel.fromJson(Map<String, dynamic>.from(devicePayload))
        : DeviceModel(
            id: '',
            childId: normalizedChildId,
            imei: '',
            simNumber: '',
            batteryLevel: 0,
            firmwareVersion: '',
            status: 'no_data',
          );

    if (kDebugMode) {
      debugPrint(
        '[DeviceLiveTrackingService.resolveChildTracking] childId=$normalizedChildId roleScopedBackend=true resolvedDevice=${resolvedDevice.id} trackingKey=${resolvedDevice.liveTrackingKey}',
      );
    }

    final resolvedChild = ChildModel.fromJson({
      ...childData,
      'device': resolvedDevice.toJson(),
    });

    return DeviceLookupResult(
      device: resolvedDevice,
      child: resolvedChild,
    );
  }

  Future<DeviceLookupResult> lookupDevice(String rawDeviceId) async {
    final deviceId = rawDeviceId.trim();
    if (deviceId.isEmpty) {
      throw StateError('Device ID is required.');
    }

    await FirebaseBootstrap.ensureInitialized();

    try {
      final deviceSnapshot = await _resolveDeviceSnapshot(deviceId);
      if (deviceSnapshot == null || deviceSnapshot.data() == null) {
        throw StateError('No device found for the entered Device ID.');
      }

      final deviceData = deviceSnapshot.data()!;
      final childId = (deviceData['child_id'] ?? '').toString().trim();
      if (childId.isEmpty) {
        throw StateError('The selected device is not linked to a child.');
      }

      final childSnapshot = await FirebaseFirestore.instance
          .collection('children')
          .doc(childId)
          .get();

      if (!childSnapshot.exists || childSnapshot.data() == null) {
        throw StateError('The linked child record could not be found.');
      }

      await _ensureAuthorizedChildAccess(childSnapshot.data()!);

      final resolvedDevice = _toDeviceModel(deviceSnapshot);
      final resolvedChild = ChildModel.fromJson({
        'id': childSnapshot.id,
        ...childSnapshot.data()!,
        'device': resolvedDevice.toJson(),
      });

      return DeviceLookupResult(
        device: resolvedDevice,
        child: resolvedChild,
      );
    } on FirebaseException catch (error) {
      throw StateError(_formatFirebaseError(error));
    }
  }

  Future<LiveTrackingModel> getResolvedChildLiveTracking({
    required String childId,
    required DeviceModel device,
  }) async {
    await FirebaseBootstrap.ensureInitialized();

    try {
      final trackingKey = resolveRealtimeTrackingKey(device);
      final rtdbPath = 'live_tracking/$trackingKey/location';
      if (kDebugMode) {
        debugPrint(
          '[DeviceLiveTrackingService.get] childId=$childId trackingKey=$trackingKey rtdbPath=/$rtdbPath',
        );
      }
      final database = FirebaseDatabase.instanceFor(
        app: Firebase.app(),
        databaseURL: AppConstants.firebaseDatabaseUrl,
      );
      final snapshot = await database.ref(rtdbPath).get();

      return _buildLiveTracking(
        childId: childId,
        rawLocation: snapshot.value,
      );
    } on FirebaseException catch (error) {
      throw StateError(_formatFirebaseError(error));
    }
  }

  Stream<LiveTrackingModel> watchResolvedChildLiveTracking({
    required String childId,
    required DeviceModel device,
    int? childCreatedAt,
  }) {
    final controller = StreamController<LiveTrackingModel>();

    () async {
      try {
        await FirebaseBootstrap.ensureInitialized();
        final trackingKey = resolveRealtimeTrackingKey(device);
        final rtdbPath = 'live_tracking/$trackingKey/location';
        if (kDebugMode) {
          debugPrint(
            '[DeviceLiveTrackingService.watch] connected childId=$childId trackingKey=$trackingKey rtdbPath=/$rtdbPath',
          );
        }
        final database = FirebaseDatabase.instanceFor(
          app: Firebase.app(),
          databaseURL: AppConstants.firebaseDatabaseUrl,
        );

        final subscription = database.ref(rtdbPath).onValue.listen(
          (event) {
            if (kDebugMode) {
              debugPrint(
                '[DeviceLiveTrackingService.watch] snapshot childId=$childId trackingKey=$trackingKey raw=${event.snapshot.value}',
              );
            }
            controller.add(
              _buildLiveTracking(
                childId: childId,
                rawLocation: event.snapshot.value,
              ),
            );
          },
          onError: (error) {
            if (kDebugMode) {
              debugPrint(
                '[DeviceLiveTrackingService.watch] error childId=$childId trackingKey=$trackingKey error=$error',
              );
            }
            if (error is FirebaseException) {
              controller.addError(StateError(_formatFirebaseError(error)));
              return;
            }

            controller.addError(error);
          },
        );

        controller.onCancel = () async {
          await subscription.cancel();
        };
      } catch (error) {
        controller.addError(error);
        await controller.close();
      }
    }();

    return controller.stream;
  }

  DeviceModel _toDeviceModel(
    DocumentSnapshot<Map<String, dynamic>> deviceSnapshot,
  ) {
    final data = deviceSnapshot.data() ?? const <String, dynamic>{};
    return DeviceModel.fromJson({
      'id': deviceSnapshot.id,
      ...data,
      'status': _safeStoredConnectivityStatus(data['status']),
      'imei': _normalizeTrackingKey((data['imei'] ?? '').toString()),
    });
  }

  String _safeStoredConnectivityStatus(Object? rawStatus) {
    final status = rawStatus?.toString().trim().toLowerCase() ?? '';
    if (status.isEmpty || status == 'online') {
      return 'no_data';
    }

    return status;
  }

  LiveTrackingModel _buildLiveTracking({
    required String childId,
    required Object? rawLocation,
  }) {
    final locationData = _asMap(rawLocation);
    final latitude = _parseCoordinate(locationData, 'latitude', 'lat');
    final longitude = _parseCoordinate(locationData, 'longitude', 'lng');
    if (!_isValidCoordinate(latitude, longitude)) {
      if (kDebugMode) {
        debugPrint(
          '[DeviceLiveTrackingService.parse] ignored invalid location childId=$childId raw=$rawLocation',
        );
      }
      return const LiveTrackingModel();
    }

    final recordedAt = _normalizeTimestamp(
          locationData['recorded_at'],
        ) ??
        _normalizeTimestamp(locationData['timestamp']) ??
        0;

    return LiveTrackingModel.fromRealtimeDatabase(
      childId,
      {
        'location': {
          ...locationData,
          'latitude': latitude,
          'longitude': longitude,
          'recorded_at': recordedAt,
        },
      },
    );
  }

  double? _parseCoordinate(
      Map<String, dynamic> payload, String primaryKey, String fallbackKey) {
    final primaryValue = _parseDouble(payload[primaryKey]);
    if (primaryValue != null) {
      return primaryValue;
    }

    return _parseDouble(payload[fallbackKey]);
  }

  double? _parseDouble(Object? value) {
    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(value?.toString() ?? '');
  }

  int? _normalizeTimestamp(Object? value) {
    final numericValue = _parseDouble(value);
    if (numericValue == null || numericValue <= 0) {
      return null;
    }

    if (numericValue >= 1000000000000) {
      return numericValue.round();
    }

    if (numericValue >= 1000000000) {
      return (numericValue * 1000).round();
    }

    return null;
  }

  bool _isValidCoordinate(double? latitude, double? longitude) {
    return latitude != null &&
        longitude != null &&
        latitude >= -90 &&
        latitude <= 90 &&
        longitude >= -180 &&
        longitude <= 180;
  }

  String _formatFirebaseError(FirebaseException error) {
    switch (error.code) {
      case 'permission-denied':
        return 'Firebase denied access to the requested live tracking data.';
      case 'unavailable':
        return 'Firebase live tracking is temporarily unavailable.';
      default:
        return error.message?.trim().isNotEmpty == true
            ? error.message!.trim()
            : 'Failed to load live tracking data from Firebase.';
    }
  }

  Future<DocumentSnapshot<Map<String, dynamic>>?> _resolveDeviceSnapshot(
    String deviceId,
  ) async {
    final devices = FirebaseFirestore.instance.collection('devices');
    final normalizedDeviceId = _normalizeTrackingKey(deviceId);
    final directSnapshot = await devices.doc(deviceId).get();
    if (directSnapshot.exists) {
      return directSnapshot;
    }

    if (normalizedDeviceId != deviceId) {
      final normalizedDirectSnapshot =
          await devices.doc(normalizedDeviceId).get();
      if (normalizedDirectSnapshot.exists) {
        return normalizedDirectSnapshot;
      }
    }

    final imeiMatches =
        await devices.where('imei', isEqualTo: deviceId).limit(2).get();
    if (imeiMatches.size > 1) {
      throw StateError('Multiple devices matched the entered Device ID.');
    }

    if (imeiMatches.docs.isNotEmpty) {
      return imeiMatches.docs.first;
    }

    if (normalizedDeviceId != deviceId) {
      final normalizedImeiMatches = await devices
          .where('imei', isEqualTo: normalizedDeviceId)
          .limit(2)
          .get();
      if (normalizedImeiMatches.size > 1) {
        throw StateError('Multiple devices matched the entered Device ID.');
      }

      if (normalizedImeiMatches.docs.isNotEmpty) {
        return normalizedImeiMatches.docs.first;
      }
    }

    final allDevices = await devices.get();
    for (final candidate in allDevices.docs) {
      final data = candidate.data();
      final candidateImei = _normalizeTrackingKey(
        (data['imei'] ?? '').toString(),
      );
      if (candidateImei == normalizedDeviceId ||
          candidate.id == normalizedDeviceId) {
        return candidate;
      }
    }

    return null;
  }

  Future<void> _ensureAuthorizedChildAccess(
    Map<String, dynamic> childData,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final currentRole =
        (prefs.getString(AppConstants.userRoleKey) ?? '').trim().toLowerCase();
    if (currentRole == 'admin') {
      return;
    }

    final currentUserId =
        (prefs.getString(AppConstants.userIdKey) ?? '').trim();
    final ownerUserId = (childData['user_id'] ?? '').toString().trim();
    if (currentUserId.isEmpty ||
        ownerUserId.isEmpty ||
        currentUserId != ownerUserId) {
      throw StateError('You do not have permission to access this device.');
    }
  }

  Map<String, dynamic> _asMap(Object? rawValue) {
    if (rawValue is Map<String, dynamic>) {
      return rawValue;
    }

    if (rawValue is Map) {
      return rawValue.map(
        (key, value) => MapEntry(key.toString(), value),
      );
    }

    return const <String, dynamic>{};
  }
}
