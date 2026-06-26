import 'dart:convert';

class TeacherClass {
  final String id;
  final String teacherId;
  final String name;
  final String subject;
  final String period;
  final String? room;
  final DateTime createdAt;
  final DateTime updatedAt;

  const TeacherClass({required this.id, required this.teacherId, required this.name, required this.subject, required this.period, required this.createdAt, required this.updatedAt, this.room});

  TeacherClass copyWith({String? id, String? teacherId, String? name, String? subject, String? period, String? room, DateTime? createdAt, DateTime? updatedAt}) => TeacherClass(
    id: id ?? this.id,
    teacherId: teacherId ?? this.teacherId,
    name: name ?? this.name,
    subject: subject ?? this.subject,
    period: period ?? this.period,
    room: room ?? this.room,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'teacher_id': teacherId,
    'name': name,
    'subject': subject,
    'period': period,
    'room': room,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };

  factory TeacherClass.fromJson(Map<String, dynamic> json) => TeacherClass(
    id: json['id'] as String,
    teacherId: (json['teacher_id'] as String?) ?? '',
    name: (json['name'] as String?) ?? '',
    subject: (json['subject'] as String?) ?? '',
    period: (json['period'] as String?) ?? '',
    room: json['room'] as String?,
    createdAt: DateTime.tryParse((json['created_at'] ?? '').toString()) ?? DateTime.now(),
    updatedAt: DateTime.tryParse((json['updated_at'] ?? '').toString()) ?? DateTime.now(),
  );

  static String encodeList(List<TeacherClass> items) => jsonEncode(items.map((e) => e.toJson()).toList());
  static List<TeacherClass> decodeList(String raw) {
    final arr = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    return arr.map(TeacherClass.fromJson).toList();
  }
}
