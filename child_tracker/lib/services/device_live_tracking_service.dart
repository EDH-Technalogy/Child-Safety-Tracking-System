import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/child_model.dart';
import '../models/live_tracking_model.dart';
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

    await FirebaseBootstrap.ensureInitialized();

    try {
      final childSnapshot = await FirebaseFirestore.instance
          .collection('children')
          .doc(normalizedChildId)
          .get();

      if (!childSnapshot.exists || childSnapshot.data() == null) {
        throw StateError('The linked child record could not be found.');
      }

      final childData = childSnapshot.data()!;
      await _ensureAuthorizedChildAccess(childData);

      final deviceSnapshot = await FirebaseFirestore.instance
          .collection('devices')
          .where('child_id', isEqualTo: normalizedChildId)
          .limit(1)
          .get();

      final resolvedDevice = deviceSnapshot.docs.isEmpty
          ? DeviceModel(
              id: '',
              childId: normalizedChildId,
              imei: '',
              simNumber: '',
              batteryLevel: 0,
              firmwareVersion: '',
              status: 'offline',
            )
          : _toDeviceModel(deviceSnapshot.docs.first);

      final resolvedChild = ChildModel.fromJson({
        'id': childSnapshot.id,
        ...childData,
        if (deviceSnapshot.docs.isNotEmpty) 'device': resolvedDevice.toJson(),
      });

      return DeviceLookupResult(
        device: resolvedDevice,
        child: resolvedChild,
      );
    } on FirebaseException catch (error) {
      throw StateError(_formatFirebaseError(error));
    }
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
      final database = FirebaseDatabase.instanceFor(
        app: Firebase.app(),
        databaseURL: AppConstants.firebaseDatabaseUrl,
      );
      final snapshot =
          await database.ref('live_tracking/$trackingKey/location').get();

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
        final database = FirebaseDatabase.instanceFor(
          app: Firebase.app(),
          databaseURL: AppConstants.firebaseDatabaseUrl,
        );

        final subscription =
            database.ref('live_tracking/$trackingKey/location').onValue.listen(
          (event) {
            controller.add(
              _buildLiveTracking(
                childId: childId,
                rawLocation: event.snapshot.value,
              ),
            );
          },
          onError: (error) {
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
      'imei': _normalizeTrackingKey((data['imei'] ?? '').toString()),
    });
  }

  LiveTrackingModel _buildLiveTracking({
    required String childId,
    required Object? rawLocation,
  }) {
    return LiveTrackingModel.fromRealtimeDatabase(
      childId,
      {
        'location': _asMap(rawLocation),
      },
    );
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
