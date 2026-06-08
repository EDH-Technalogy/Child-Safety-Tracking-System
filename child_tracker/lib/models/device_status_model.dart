import '../utils/timestamp_utils.dart';

class DeviceStatusCardModel {
  final String childId;
  final String trackingKey;
  final String childName;
  final String deviceName;
  final String status;
  final double? latitude;
  final double? longitude;
  final String? placeName;
  final int timestamp;
  final int lastHeartbeatAt;
  final int updatedAt;
  final String formattedTime;
  final String source;

  const DeviceStatusCardModel({
    required this.childId,
    required this.trackingKey,
    required this.childName,
    required this.deviceName,
    required this.status,
    required this.latitude,
    required this.longitude,
    required this.placeName,
    required this.timestamp,
    required this.lastHeartbeatAt,
    required this.updatedAt,
    required this.formattedTime,
    required this.source,
  });

  bool get isOnline => status.trim().toLowerCase() == 'online';

  factory DeviceStatusCardModel.fromJson(Map<String, dynamic> json) {
    return DeviceStatusCardModel(
      childId: (json['child_id'] ?? '').toString(),
      trackingKey: (json['tracking_key'] ?? '').toString(),
      childName: (json['child_name'] ?? '').toString(),
      deviceName: (json['device_name'] ?? '').toString(),
      status: (json['status'] ?? 'unknown').toString(),
      latitude: _parseNullableDouble(json['latitude']),
      longitude: _parseNullableDouble(json['longitude']),
      placeName: json['place_name']?.toString(),
      timestamp:
          TimestampUtils.normalizeEpochMilliseconds(json['timestamp']) ?? 0,
      lastHeartbeatAt:
          TimestampUtils.normalizeEpochMilliseconds(json['last_heartbeat_at']) ??
              0,
      updatedAt:
          TimestampUtils.normalizeEpochMilliseconds(json['updated_at']) ?? 0,
      formattedTime: (json['formatted_time'] ?? '').toString(),
      source: (json['source'] ?? '').toString(),
    );
  }

  static double? _parseNullableDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(value?.toString() ?? '');
  }
}

class DeviceStatusLogModel {
  final String id;
  final String childId;
  final String trackingKey;
  final String childName;
  final String deviceName;
  final String status;
  final String statusName;
  final double? latitude;
  final double? longitude;
  final int timestamp;
  final String formattedTime;
  final String? placeName;
  final String source;

  const DeviceStatusLogModel({
    required this.id,
    required this.childId,
    required this.trackingKey,
    required this.childName,
    required this.deviceName,
    required this.status,
    required this.statusName,
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    required this.formattedTime,
    required this.placeName,
    required this.source,
  });

  bool get isOnline => status.trim().toLowerCase() == 'online';

  factory DeviceStatusLogModel.fromJson(Map<String, dynamic> json) {
    return DeviceStatusLogModel(
      id: (json['id'] ?? '').toString(),
      childId: (json['child_id'] ?? '').toString(),
      trackingKey: (json['tracking_key'] ?? '').toString(),
      childName: (json['child_name'] ?? '').toString(),
      deviceName: (json['device_name'] ?? '').toString(),
      status: (json['status'] ?? 'unknown').toString(),
      statusName: (json['status_name'] ?? json['status'] ?? 'Unknown').toString(),
      latitude: DeviceStatusCardModel._parseNullableDouble(json['latitude']),
      longitude: DeviceStatusCardModel._parseNullableDouble(json['longitude']),
      timestamp:
          TimestampUtils.normalizeEpochMilliseconds(json['timestamp']) ?? 0,
      formattedTime: (json['formatted_time'] ?? '').toString(),
      placeName: (json['place_name'] ?? json['address'])?.toString(),
      source: (json['source'] ?? '').toString(),
    );
  }
}
