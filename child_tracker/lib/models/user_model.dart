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

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      phone: json['phone'] ?? '',
      email: json['email'] ?? '',
      photo: json['photo'] ?? '',
      role: json['role'] ?? 'user',
      status: json['status'] ?? 'active',
      createdAt: json['created_at'] ?? 0,
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
