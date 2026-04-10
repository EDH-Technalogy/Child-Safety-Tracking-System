class AlertModel {
  final String id;
  final String childId;
  final String childName;
  final String type;
  final String message;
  final int createdAt;
  final bool isRead;
  final String? zoneName;
  final String? locationText;
  final double? latitude;
  final double? longitude;

  AlertModel({
    required this.id,
    required this.childId,
    required this.childName,
    required this.type,
    required this.message,
    required this.createdAt,
    required this.isRead,
    this.zoneName,
    this.locationText,
    this.latitude,
    this.longitude,
  });

  factory AlertModel.fromJson(Map<String, dynamic> json) {
    final status = (json['status'] ?? '').toString().toLowerCase();
    return AlertModel(
      id: (json['id'] ?? '').toString(),
      childId: (json['child_id'] ?? '').toString(),
      childName: (json['child_name'] ?? '').toString(),
      type: (json['type'] ?? '').toString(),
      message: (json['message'] ?? '').toString(),
      createdAt: json['created_at'] is int
          ? json['created_at'] as int
          : int.tryParse((json['created_at'] ?? '').toString()) ?? 0,
      isRead: json['is_read'] == true || status == 'read',
      zoneName: json['zone_name']?.toString(),
      locationText: json['location_text']?.toString(),
      latitude: json['latitude'] is num
          ? (json['latitude'] as num).toDouble()
          : double.tryParse((json['latitude'] ?? '').toString()),
      longitude: json['longitude'] is num
          ? (json['longitude'] as num).toDouble()
          : double.tryParse((json['longitude'] ?? '').toString()),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'child_id': childId,
      'child_name': childName,
      'type': type,
      'message': message,
      'created_at': createdAt,
      'is_read': isRead,
      'zone_name': zoneName,
      'location_text': locationText,
      'latitude': latitude,
      'longitude': longitude,
    };
  }
}
