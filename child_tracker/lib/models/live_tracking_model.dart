import 'location_model.dart';
import '../utils/timestamp_utils.dart';

class LiveTrackingModel {
  static const int onlineThresholdMs = 60 * 1000;
  static const int delayedThresholdMs = 180 * 1000;
  static const int futureTimestampToleranceMs = 30 * 1000;

  final LocationModel? location;
  final LiveTrackingStatusModel? childStatus;
  final LiveTrackingStatusModel? deviceStatus;
  final LiveTrackingStatusModel? connection;

  const LiveTrackingModel({
    this.location,
    this.childStatus,
    this.deviceStatus,
    this.connection,
  });

  factory LiveTrackingModel.fromRealtimeDatabase(
    String childId,
    Object? rawValue,
  ) {
    final data = _asMap(rawValue);
    final locationData = _asMap(data['location']);

    return LiveTrackingModel(
      location: locationData.isEmpty
          ? null
          : LocationModel.fromJson({
              'id': '',
              'child_id': childId,
              ...locationData,
            }),
      childStatus: LiveTrackingStatusModel.fromRaw(data['child_status']),
      deviceStatus: LiveTrackingStatusModel.fromRaw(data['device_status']),
      connection: LiveTrackingStatusModel.fromRaw(data['connection']),
    );
  }

  bool get hasLiveData =>
      location != null ||
      childStatus != null ||
      deviceStatus != null ||
      connection != null;

  int? get latestTimestamp {
    final timestamps = <int>[
      if ((location?.recordedAt ?? 0) > 0) location!.recordedAt,
      if ((connection?.time ?? 0) > 0) connection!.time,
      if ((connection?.updatedAt ?? 0) > 0) connection!.updatedAt,
      if ((deviceStatus?.updatedAt ?? 0) > 0) deviceStatus!.updatedAt,
      if ((childStatus?.updatedAt ?? 0) > 0) childStatus!.updatedAt,
    ];

    if (timestamps.isEmpty) {
      return null;
    }

    timestamps.sort();
    return timestamps.last;
  }

  int? get latestLiveLocationTimestamp {
    final timestamp = location?.recordedAt ?? 0;
    return timestamp > 0 ? timestamp : null;
  }

  String get effectiveDeviceStatus {
    final liveTimestamp = latestLiveLocationTimestamp;
    if (liveTimestamp == null) {
      return 'no_data';
    }

    final ageMs = DateTime.now().millisecondsSinceEpoch - liveTimestamp;
    if (ageMs < -futureTimestampToleranceMs) {
      return 'no_data';
    }

    if (ageMs <= onlineThresholdMs) {
      return 'online';
    }

    if (ageMs <= delayedThresholdMs) {
      return 'delayed';
    }

    return 'offline';
  }

  static Map<String, dynamic> _asMap(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }

    if (value is Map) {
      return value.map(
        (key, entryValue) => MapEntry(key.toString(), entryValue),
      );
    }

    return const <String, dynamic>{};
  }
}

class LiveTrackingStatusModel {
  final String status;
  final bool blocked;
  final bool disabled;
  final int updatedAt;
  final int time;
  final String reason;

  const LiveTrackingStatusModel({
    required this.status,
    required this.blocked,
    required this.disabled,
    required this.updatedAt,
    required this.time,
    required this.reason,
  });

  static LiveTrackingStatusModel? fromRaw(Object? rawValue) {
    final data = LiveTrackingModel._asMap(rawValue);
    if (data.isEmpty) {
      return null;
    }

    return LiveTrackingStatusModel(
      status: (data['status'] ?? '').toString(),
      blocked: _parseBool(data['blocked']),
      disabled: _parseBool(data['disabled']),
      updatedAt:
          TimestampUtils.normalizeEpochMilliseconds(data['updated_at']) ?? 0,
      time: TimestampUtils.normalizeEpochMilliseconds(data['time']) ?? 0,
      reason: (data['reason'] ?? '').toString(),
    );
  }

  static bool _parseBool(Object? value) {
    if (value is bool) {
      return value;
    }

    if (value is num) {
      return value != 0;
    }

    final normalized = value?.toString().trim().toLowerCase() ?? '';
    return normalized == 'true' || normalized == '1';
  }
}
