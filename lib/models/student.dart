import 'dart:convert';

class Student {
  final String id;
  final String teacherId;
  final String classId;
  final String name;
  final String studentId;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Student({required this.id, required this.teacherId, required this.classId, required this.name, required this.studentId, required this.createdAt, required this.updatedAt, this.notes});

  Student copyWith({String? id, String? teacherId, String? classId, String? name, String? studentId, String? notes, DateTime? createdAt, DateTime? updatedAt}) => Student(
    id: id ?? this.id,
    teacherId: teacherId ?? this.teacherId,
    classId: classId ?? this.classId,
    name: name ?? this.name,
    studentId: studentId ?? this.studentId,
    notes: notes ?? this.notes,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'teacher_id': teacherId,
    'class_id': classId,
    'name': name,
    'student_id': studentId,
    'notes': notes,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };

  factory Student.fromJson(Map<String, dynamic> json) => Student(
    id: json['id'] as String,
    teacherId: (json['teacher_id'] as String?) ?? '',
    classId: (json['class_id'] as String?) ?? '',
    name: (json['name'] as String?) ?? '',
    studentId: (json['student_id'] as String?) ?? '',
    notes: json['notes'] as String?,
    createdAt: DateTime.tryParse((json['created_at'] ?? '').toString()) ?? DateTime.now(),
    updatedAt: DateTime.tryParse((json['updated_at'] ?? '').toString()) ?? DateTime.now(),
  );

  static String encodeList(List<Student> items) => jsonEncode(items.map((e) => e.toJson()).toList());
  static List<Student> decodeList(String raw) {
    final arr = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    return arr.map(Student.fromJson).toList();
  }
}
