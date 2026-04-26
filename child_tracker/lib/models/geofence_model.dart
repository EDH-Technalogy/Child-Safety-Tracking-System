import '../utils/timestamp_utils.dart';

class GeofenceModel {
  final String id;
  final String childId;
  final String childName;
  final String userId;
  final String name;
  final double latitude;
  final double longitude;
  final int radius;
  final String status;
  final int createdAt;
  final int? updatedAt;

  GeofenceModel({
    required this.id,
    required this.childId,
    required this.childName,
    required this.userId,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.radius,
    required this.status,
    required this.createdAt,
    this.updatedAt,
  });

  factory GeofenceModel.fromJson(Map<String, dynamic> json) {
    return GeofenceModel(
      id: json['id'] ?? '',
      childId: json['child_id'] ?? '',
      childName: json['child_name'] ?? json['childName'] ?? '',
      userId: json['user_id'] ?? '',
      name: json['name'] ?? '',
      latitude: (json['latitude'] ?? 0).toDouble(),
      longitude: (json['longitude'] ?? 0).toDouble(),
      radius: json['radius'] ?? 100,
      status: json['status'] ?? 'active',
      createdAt:
          TimestampUtils.normalizeEpochMilliseconds(json['created_at']) ?? 0,
      updatedAt: TimestampUtils.normalizeEpochMilliseconds(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'child_id': childId,
      'child_name': childName,
      'user_id': userId,
      'name': name,
      'latitude': latitude,
      'longitude': longitude,
      'radius': radius,
      'status': status,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  bool get isActive => status == 'active';
}

class ZoneCheckResult {
  final bool inZone;
  final GeofenceModel? currentZone;
  final List<ZoneDistance> zones;

  ZoneCheckResult({
    required this.inZone,
    this.currentZone,
    required this.zones,
  });

  factory ZoneCheckResult.fromJson(Map<String, dynamic> json) {
    return ZoneCheckResult(
      inZone: json['in_zone'] ?? false,
      currentZone: json['current_zone'] != null
          ? GeofenceModel(
              id: json['current_zone']['id'] ?? '',
              childId: '',
              childName: '',
              userId: '',
              name: json['current_zone']['name'] ?? '',
              latitude: 0,
              longitude: 0,
              radius: 0,
              status: 'active',
              createdAt: 0,
            )
          : null,
      zones: (json['zones'] as List<dynamic>?)
              ?.map((e) => ZoneDistance.fromJson(e))
              .toList() ??
          [],
    );
  }
}

class ZoneDistance {
  final String id;
  final String name;
  final int distance;
  final bool inZone;

  ZoneDistance({
    required this.id,
    required this.name,
    required this.distance,
    required this.inZone,
  });

  factory ZoneDistance.fromJson(Map<String, dynamic> json) {
    return ZoneDistance(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      distance: json['distance'] ?? 0,
      inZone: json['in_zone'] ?? false,
    );
  }
}
