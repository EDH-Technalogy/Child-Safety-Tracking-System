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

  DeviceModel({
    required this.id,
    required this.childId,
    required this.imei,
    required this.simNumber,
    required this.batteryLevel,
    required this.firmwareVersion,
    required this.status,
  });

  factory DeviceModel.fromJson(Map<String, dynamic> json) {
    return DeviceModel(
      id: json['id'] ?? '',
      childId: json['child_id'] ?? '',
      imei: json['imei'] ?? '',
      simNumber: json['sim_number'] ?? '',
      batteryLevel: json['battery_level'] ?? 0,
      firmwareVersion: json['firmware_version'] ?? '',
      status: json['status'] ?? 'offline',
    );
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
    };
  }
}
