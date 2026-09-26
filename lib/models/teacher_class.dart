import 'dart:convert';

class TeacherClass {
  final String id;
  final String teacherId;
  final String name;
  final String subject;
  final String period;
  final String? room;

  /// Grade level (1–13) of the class — the AI marks at this grade's
  /// expectations automatically when the class is selected before scanning.
  final int? gradeLevel;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// The class as a teacher reads it. A class that names itself from its
  /// subject and period ("Science 2") already carries the period, so
  /// "name · period" read "Science 2 · 2"; the period is only added when the
  /// name doesn't already end with it.
  String get label {
    final p = period.trim();
    final n = name.trim();
    if (p.isEmpty || n.toLowerCase().endsWith(p.toLowerCase())) return n;
    return '$n · $p';
  }

  /// "Period 2" for a bare number, the period as typed otherwise ("P2",
  /// "Block A") — a lone "2" beside "Science 2" read as a typo.
  String get periodLabel {
    final p = period.trim();
    return RegExp(r'^[0-9]+$').hasMatch(p) ? 'Period $p' : p;
  }

  const TeacherClass({required this.id, required this.teacherId, required this.name, required this.subject, required this.period, required this.createdAt, required this.updatedAt, this.room, this.gradeLevel});

  TeacherClass copyWith({String? id, String? teacherId, String? name, String? subject, String? period, String? room, int? gradeLevel, DateTime? createdAt, DateTime? updatedAt}) => TeacherClass(
    id: id ?? this.id,
    teacherId: teacherId ?? this.teacherId,
    name: name ?? this.name,
    subject: subject ?? this.subject,
    period: period ?? this.period,
    room: room ?? this.room,
    gradeLevel: gradeLevel ?? this.gradeLevel,
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
    'grade_level': gradeLevel,
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
    gradeLevel: (json['grade_level'] as num?)?.toInt(),
    createdAt: DateTime.tryParse((json['created_at'] ?? '').toString()) ?? DateTime.now(),
    updatedAt: DateTime.tryParse((json['updated_at'] ?? '').toString()) ?? DateTime.now(),
  );

  static String encodeList(List<TeacherClass> items) => jsonEncode(items.map((e) => e.toJson()).toList());
  static List<TeacherClass> decodeList(String raw) {
    final arr = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    return arr.map(TeacherClass.fromJson).toList();
  }
}
