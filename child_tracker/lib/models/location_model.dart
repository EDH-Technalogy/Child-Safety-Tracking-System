import '../utils/timestamp_utils.dart';

class LocationModel {
  final String id;
  final String childId;
  final double latitude;
  final double longitude;
  final double speed;
  final int battery;
  final int recordedAt;

  LocationModel({
    required this.id,
    required this.childId,
    required this.latitude,
    required this.longitude,
    required this.speed,
    required this.battery,
    required this.recordedAt,
  });

  static double _parseDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  static int _parseInt(dynamic value) {
    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.round();
    }

    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  factory LocationModel.fromJson(Map<String, dynamic> json) {
    return LocationModel(
      id: (json['id'] ?? '').toString(),
      childId: (json['child_id'] ?? '').toString(),
      latitude: _parseDouble(json['latitude']),
      longitude: _parseDouble(json['longitude']),
      speed: _parseDouble(json['speed']),
      battery: _parseInt(json['battery']),
      recordedAt:
          TimestampUtils.normalizeEpochMilliseconds(json['recorded_at']) ??
              TimestampUtils.normalizeEpochMilliseconds(json['timestamp']) ??
              0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'child_id': childId,
      'latitude': latitude,
      'longitude': longitude,
      'speed': speed,
      'battery': battery,
      'recorded_at': recordedAt,
    };
  }
}

class RouteDataModel {
  final List<CoordinateModel> coordinates;
  final List<HistoryEventModel> logs;
  final int firstLocationTime;
  final int lastLocationTime;
  final int totalDistanceMeters;
  final String totalDistanceKm;
  final int locationCount;
  final int eventCount;

  RouteDataModel({
    required this.coordinates,
    required this.logs,
    required this.firstLocationTime,
    required this.lastLocationTime,
    required this.totalDistanceMeters,
    required this.totalDistanceKm,
    required this.locationCount,
    required this.eventCount,
  });

  bool get hasAnyHistory => coordinates.isNotEmpty || logs.isNotEmpty;

  factory RouteDataModel.fromJson(Map<String, dynamic> json) {
    return RouteDataModel(
      coordinates: (json['coordinates'] as List<dynamic>?)
              ?.map((e) => CoordinateModel.fromJson(e))
              .toList() ??
          [],
      logs: (json['logs'] as List<dynamic>?)
              ?.map((e) => HistoryEventModel.fromJson(
                    e is Map<String, dynamic>
                        ? e
                        : Map<String, dynamic>.from(e as Map),
                  ))
              .toList() ??
          [],
      firstLocationTime: TimestampUtils.normalizeEpochMilliseconds(
              json['first_location_time']) ??
          0,
      lastLocationTime: TimestampUtils.normalizeEpochMilliseconds(
              json['last_location_time']) ??
          0,
      totalDistanceMeters:
          LocationModel._parseInt(json['total_distance_meters']),
      totalDistanceKm: json['total_distance_km'] ?? '0',
      locationCount: LocationModel._parseInt(json['location_count']),
      eventCount: LocationModel._parseInt(json['event_count']),
    );
  }
}

class CoordinateModel {
  final double latitude;
  final double longitude;
  final int time;

  CoordinateModel({
    required this.latitude,
    required this.longitude,
    required this.time,
  });

  factory CoordinateModel.fromJson(Map<String, dynamic> json) {
    return CoordinateModel(
      latitude: LocationModel._parseDouble(json['latitude'] ?? json['lat']),
      longitude: LocationModel._parseDouble(json['longitude'] ?? json['lng']),
      time: TimestampUtils.normalizeEpochMilliseconds(json['time']) ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'latitude': latitude,
      'longitude': longitude,
      'time': time,
    };
  }
}

class HistoryEventModel {
  final String id;
  final String type;
  final String childId;
  final String trackingKey;
  final String parentUserId;
  final String title;
  final String message;
  final double? latitude;
  final double? longitude;
  final double? accuracy;
  final int timestamp;
  final int createdAt;
  final String dateKey;
  final Map<String, dynamic> metadata;

  const HistoryEventModel({
    required this.id,
    required this.type,
    required this.childId,
    required this.trackingKey,
    required this.parentUserId,
    required this.title,
    required this.message,
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.timestamp,
    required this.createdAt,
    required this.dateKey,
    required this.metadata,
  });

  factory HistoryEventModel.fromJson(Map<String, dynamic> json) {
    final metadata = json['metadata'] is Map<String, dynamic>
        ? Map<String, dynamic>.from(json['metadata'] as Map<String, dynamic>)
        : json['metadata'] is Map
            ? Map<String, dynamic>.from(json['metadata'] as Map)
            : <String, dynamic>{};
    return HistoryEventModel(
      id: (json['id'] ?? '').toString(),
      type: (json['type'] ?? '').toString(),
      childId: (json['childId'] ?? json['child_id'] ?? '').toString(),
      trackingKey:
          (json['trackingKey'] ?? json['tracking_key'] ?? '').toString(),
      parentUserId:
          (json['parentUserId'] ?? json['parent_user_id'] ?? '').toString(),
      title: (json['title'] ?? json['eventTitle'] ?? json['type'] ?? '')
          .toString(),
      message: (json['message'] ?? '').toString(),
      latitude: _parseNullableDouble(
        json['latitude'] ??
            json['lat'] ??
            metadata['reconnectedLat'] ??
            metadata['lastKnownLat'],
      ),
      longitude: _parseNullableDouble(
        json['longitude'] ??
            json['lng'] ??
            metadata['reconnectedLng'] ??
            metadata['lastKnownLng'],
      ),
      accuracy: _parseNullableDouble(
        json['accuracy'] ??
            metadata['reconnectedAccuracy'] ??
            metadata['lastKnownAccuracy'],
      ),
      timestamp: TimestampUtils.normalizeEpochMilliseconds(
            json['timestamp'] ?? json['createdAt'] ?? json['created_at'],
          ) ??
          0,
      createdAt: TimestampUtils.normalizeEpochMilliseconds(
            json['createdAt'] ?? json['created_at'] ?? json['timestamp'],
          ) ??
          0,
      dateKey: (json['dateKey'] ?? json['date_key'] ?? '').toString(),
      metadata: metadata,
    );
  }

  static double? _parseNullableDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(value?.toString() ?? '');
  }
}
