class UserModel {
  final String id;
  final String name;
  final String phone;
  final String email;
  final String? photo;
  final String role;
  final String status;
  final int createdAt;

  UserModel({
    required this.id,
    required this.name,
    required this.phone,
    required this.email,
    this.photo,
    required this.role,
    required this.status,
    required this.createdAt,
  });

  static int _parseTimestamp(dynamic value) {
    if (value is int) {
      return value;
    }

    if (value is double) {
      return value.round();
    }

    if (value is String) {
      return int.tryParse(value) ?? 0;
    }

    if (value is Map) {
      final timestampMap = Map<String, dynamic>.from(value);
      final seconds = timestampMap['_seconds'] ?? timestampMap['seconds'];
      final nanoseconds =
          timestampMap['_nanoseconds'] ?? timestampMap['nanoseconds'] ?? 0;

      final parsedSeconds = seconds is num
          ? seconds.toInt()
          : int.tryParse(seconds?.toString() ?? '');
      final parsedNanoseconds = nanoseconds is num
          ? nanoseconds.toInt()
          : int.tryParse(nanoseconds?.toString() ?? '');

      if (parsedSeconds != null) {
        return (parsedSeconds * 1000) + ((parsedNanoseconds ?? 0) ~/ 1000000);
      }
    }

    return 0;
  }

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      phone: (json['phone'] ?? '').toString(),
      email: (json['email'] ?? '').toString(),
      photo: json['photo']?.toString() ?? '',
      role: (json['role'] ?? 'user').toString(),
      status: (json['status'] ?? 'active').toString(),
      createdAt: _parseTimestamp(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'phone': phone,
      'email': email,
      'photo': photo,
      'role': role,
      'status': status,
      'created_at': createdAt,
    };
  }
}
