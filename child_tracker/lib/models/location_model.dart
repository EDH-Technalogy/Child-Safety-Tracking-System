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

  factory LocationModel.fromJson(Map<String, dynamic> json) {
    return LocationModel(
      id: json['id'] ?? '',
      childId: json['child_id'] ?? '',
      latitude: (json['latitude'] ?? 0).toDouble(),
      longitude: (json['longitude'] ?? 0).toDouble(),
      speed: (json['speed'] ?? 0).toDouble(),
      battery: json['battery'] ?? 0,
      recordedAt: json['recorded_at'] ?? 0,
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
  final int firstLocationTime;
  final int lastLocationTime;
  final int totalDistanceMeters;
  final String totalDistanceKm;
  final int locationCount;

  RouteDataModel({
    required this.coordinates,
    required this.firstLocationTime,
    required this.lastLocationTime,
    required this.totalDistanceMeters,
    required this.totalDistanceKm,
    required this.locationCount,
  });

  factory RouteDataModel.fromJson(Map<String, dynamic> json) {
    return RouteDataModel(
      coordinates: (json['coordinates'] as List<dynamic>?)
              ?.map((e) => CoordinateModel.fromJson(e))
              .toList() ??
          [],
      firstLocationTime: json['first_location_time'] ?? 0,
      lastLocationTime: json['last_location_time'] ?? 0,
      totalDistanceMeters: json['total_distance_meters'] ?? 0,
      totalDistanceKm: json['total_distance_km'] ?? '0',
      locationCount: json['location_count'] ?? 0,
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
      latitude: (json['latitude'] ?? 0).toDouble(),
      longitude: (json['longitude'] ?? 0).toDouble(),
      time: json['time'] ?? 0,
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
