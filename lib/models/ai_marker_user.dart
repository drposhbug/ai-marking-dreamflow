import 'dart:convert';

class AiMarkerUser {
  final String id;
  final String email;
  final String name;
  final String school;
  final String title;
  final String? avatarUrl;
  final DateTime createdAt;
  final DateTime updatedAt;

  const AiMarkerUser({required this.id, required this.email, required this.name, required this.school, required this.title, required this.createdAt, required this.updatedAt, this.avatarUrl});

  AiMarkerUser copyWith({String? id, String? email, String? name, String? school, String? title, String? avatarUrl, DateTime? createdAt, DateTime? updatedAt}) => AiMarkerUser(
    id: id ?? this.id,
    email: email ?? this.email,
    name: name ?? this.name,
    school: school ?? this.school,
    title: title ?? this.title,
    avatarUrl: avatarUrl ?? this.avatarUrl,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'email': email,
    'name': name,
    'school': school,
    'title': title,
    'avatar_url': avatarUrl,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };

  factory AiMarkerUser.fromJson(Map<String, dynamic> json) => AiMarkerUser(
    id: json['id'] as String,
    email: json['email'] as String,
    name: (json['name'] as String?) ?? '',
    school: (json['school'] as String?) ?? '',
    title: (json['title'] as String?) ?? '',
    avatarUrl: json['avatar_url'] as String?,
    createdAt: DateTime.tryParse((json['created_at'] ?? '').toString()) ?? DateTime.now(),
    updatedAt: DateTime.tryParse((json['updated_at'] ?? '').toString()) ?? DateTime.now(),
  );

  static String encodeList(List<AiMarkerUser> items) => jsonEncode(items.map((e) => e.toJson()).toList());
  static List<AiMarkerUser> decodeList(String raw) {
    final arr = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    return arr.map(AiMarkerUser.fromJson).toList();
  }
}
