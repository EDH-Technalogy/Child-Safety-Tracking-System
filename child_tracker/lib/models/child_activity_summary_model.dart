class ChildActivitySummaryModel {
  final String childId;
  final String childName;
  final String parentUserId;
  final String trackingKey;
  final DateTime fromTime;
  final DateTime toTime;
  final double distanceKm;
  final int locationPointsCount;
  final int safeZoneExitCount;
  final int safeZoneReturnCount;
  final int deviceDisconnectCount;
  final int deviceReconnectCount;
  final DateTime? lastLocationUpdateAt;
  final String currentConnectionState;
  final DateTime generatedAt;

  const ChildActivitySummaryModel({
    required this.childId,
    required this.childName,
    required this.parentUserId,
    required this.trackingKey,
    required this.fromTime,
    required this.toTime,
    required this.distanceKm,
    required this.locationPointsCount,
    required this.safeZoneExitCount,
    required this.safeZoneReturnCount,
    required this.deviceDisconnectCount,
    required this.deviceReconnectCount,
    required this.lastLocationUpdateAt,
    required this.currentConnectionState,
    required this.generatedAt,
  });

  factory ChildActivitySummaryModel.fromJson(Map<String, dynamic> json) {
    return ChildActivitySummaryModel(
      childId: (json['childId'] ?? '').toString(),
      childName: (json['childName'] ?? '').toString(),
      parentUserId: (json['parentUserId'] ?? '').toString(),
      trackingKey: (json['trackingKey'] ?? '').toString(),
      fromTime: _parseDateTime(json['fromTime']) ?? DateTime.now(),
      toTime: _parseDateTime(json['toTime']) ?? DateTime.now(),
      distanceKm: _parseDouble(json['distanceKm']),
      locationPointsCount: _parseInt(json['locationPointsCount']),
      safeZoneExitCount: _parseInt(json['safeZoneExitCount']),
      safeZoneReturnCount: _parseInt(json['safeZoneReturnCount']),
      deviceDisconnectCount: _parseInt(json['deviceDisconnectCount']),
      deviceReconnectCount: _parseInt(json['deviceReconnectCount']),
      lastLocationUpdateAt: _parseDateTime(json['lastLocationUpdateAt']),
      currentConnectionState: (json['currentConnectionState'] ?? 'unknown')
          .toString()
          .trim()
          .toLowerCase(),
      generatedAt: _parseDateTime(json['generatedAt']) ?? DateTime.now(),
    );
  }

  bool get hasRecordedActivity {
    return locationPointsCount > 0 ||
        safeZoneExitCount > 0 ||
        safeZoneReturnCount > 0 ||
        deviceDisconnectCount > 0 ||
        deviceReconnectCount > 0 ||
        distanceKm > 0;
  }

  static DateTime? _parseDateTime(Object? value) {
    final milliseconds = _parseEpochMilliseconds(value);
    if (milliseconds == null) {
      return null;
    }

    return DateTime.fromMillisecondsSinceEpoch(milliseconds).toLocal();
  }

  static int? _parseEpochMilliseconds(Object? value) {
    if (value is int) {
      return value > 0 ? value : null;
    }

    if (value is num) {
      final rounded = value.round();
      return rounded > 0 ? rounded : null;
    }

    final parsed = int.tryParse(value?.toString() ?? '');
    if (parsed == null || parsed <= 0) {
      return null;
    }

    return parsed;
  }

  static int _parseInt(Object? value) {
    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.round();
    }

    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static double _parseDouble(Object? value) {
    if (value is double) {
      return value;
    }

    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(value?.toString() ?? '') ?? 0;
  }
}
