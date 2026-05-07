class ChildModel {
  final String id;
  final String userId;
  final String name;
  final int age;
  final String photo;
  final String status;
  final int createdAt;
  final DeviceModel? device;

  ChildModel({
    required this.id,
    required this.userId,
    required this.name,
    required this.age,
    required this.photo,
    required this.status,
    required this.createdAt,
    this.device,
  });

  static String resolvePhotoFromJson(Map<String, dynamic> json) {
    for (final key in const [
      'photo',
      'photoUrl',
      'profileImage',
      'profile_image',
      'avatar',
      'image',
      'image_url',
    ]) {
      final value = json[key]?.toString().trim() ?? '';
      if (value.isNotEmpty) {
        return value;
      }
    }

    return '';
  }

  static int _parseInt(dynamic value) {
    if (value is int) {
      return value;
    }

    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  factory ChildModel.fromJson(Map<String, dynamic> json) {
    return ChildModel(
      id: (json['id'] ?? '').toString(),
      userId: (json['user_id'] ?? json['userId'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      age: _parseInt(json['age']),
      photo: resolvePhotoFromJson(json),
      status: (json['status'] ?? 'active').toString(),
      createdAt: _parseInt(json['created_at'] ?? json['createdAt']),
      device: json['device'] is Map<String, dynamic>
          ? DeviceModel.fromJson(json['device'])
          : json['device'] is Map
              ? DeviceModel.fromJson(
                  Map<String, dynamic>.from(json['device'] as Map),
                )
              : null,
    );
  }

  ChildModel copyWith({
    String? id,
    String? userId,
    String? name,
    int? age,
    String? photo,
    String? status,
    int? createdAt,
    DeviceModel? device,
    bool clearDevice = false,
  }) {
    return ChildModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      age: age ?? this.age,
      photo: photo ?? this.photo,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      device: clearDevice ? null : (device ?? this.device),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'name': name,
      'age': age,
      'photo': photo,
      'status': status,
      'created_at': createdAt,
      'device': device?.toJson(),
    };
  }
}

class DeviceModel {
  final String id;
  final String childId;
  final String imei;
  final String simNumber;
  final int batteryLevel;
  final String firmwareVersion;
  final String status;
  final String latestLiveStatus;
  final String rawLiveStatus;
  final String latestSignal;
  final int latestTimestamp;
  final int latestAgeMs;
  final String liveTrackingKey;
  final bool timestampInferred;
  final String statusReason;
  final int onlineThresholdMs;
  final int delayedThresholdMs;

  DeviceModel({
    required this.id,
    required this.childId,
    required this.imei,
    required this.simNumber,
    required this.batteryLevel,
    required this.firmwareVersion,
    required this.status,
    this.latestLiveStatus = '',
    this.rawLiveStatus = '',
    this.latestSignal = '',
    this.latestTimestamp = 0,
    this.latestAgeMs = 0,
    this.liveTrackingKey = '',
    this.timestampInferred = false,
    this.statusReason = '',
    this.onlineThresholdMs = 0,
    this.delayedThresholdMs = 0,
  });

  factory DeviceModel.fromJson(Map<String, dynamic> json) {
    final resolvedStatus =
        (json['latest_live_status'] ?? json['status'] ?? 'offline').toString();

    return DeviceModel(
      id: (json['id'] ?? '').toString(),
      childId: (json['child_id'] ?? '').toString(),
      imei: (json['imei'] ?? '').toString(),
      simNumber: (json['sim_number'] ?? '').toString(),
      batteryLevel: ChildModel._parseInt(json['battery_level']),
      firmwareVersion: (json['firmware_version'] ?? '').toString(),
      status: resolvedStatus,
      latestLiveStatus: (json['latest_live_status'] ?? '').toString(),
      rawLiveStatus: (json['raw_live_status'] ?? '').toString(),
      latestSignal: (json['latest_signal'] ?? '').toString(),
      latestTimestamp: ChildModel._parseInt(json['latest_timestamp']),
      latestAgeMs: ChildModel._parseInt(json['latest_age_ms']),
      liveTrackingKey: (json['live_tracking_key'] ?? '').toString(),
      timestampInferred: _parseBool(json['timestamp_inferred']),
      statusReason: (json['status_reason'] ?? '').toString(),
      onlineThresholdMs: ChildModel._parseInt(json['online_threshold_ms']),
      delayedThresholdMs: ChildModel._parseInt(json['delayed_threshold_ms']),
    );
  }

  bool get isOnline => status.trim().toLowerCase() == 'online';

  bool get hasLiveTimestamp => latestTimestamp > 0;

  static bool _parseBool(dynamic value) {
    if (value is bool) {
      return value;
    }

    if (value is num) {
      return value != 0;
    }

    final normalized = value?.toString().trim().toLowerCase() ?? '';
    return normalized == 'true' || normalized == '1';
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'child_id': childId,
      'imei': imei,
      'sim_number': simNumber,
      'battery_level': batteryLevel,
      'firmware_version': firmwareVersion,
      'status': status,
      'latest_live_status': latestLiveStatus,
      'raw_live_status': rawLiveStatus,
      'latest_signal': latestSignal,
      'latest_timestamp': latestTimestamp,
      'latest_age_ms': latestAgeMs,
      'live_tracking_key': liveTrackingKey,
      'timestamp_inferred': timestampInferred,
      'status_reason': statusReason,
      'online_threshold_ms': onlineThresholdMs,
      'delayed_threshold_ms': delayedThresholdMs,
    };
  }
}
