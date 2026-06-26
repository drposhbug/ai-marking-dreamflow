import 'dart:convert';

class StudentClassLink {
  final String id;
  final String studentId;
  final String classId;
  final String subject;
  final DateTime? confirmedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  const StudentClassLink({required this.id, required this.studentId, required this.classId, required this.subject, required this.createdAt, required this.updatedAt, this.confirmedAt});

  StudentClassLink copyWith({String? id, String? studentId, String? classId, String? subject, DateTime? confirmedAt, DateTime? createdAt, DateTime? updatedAt}) => StudentClassLink(
    id: id ?? this.id,
    studentId: studentId ?? this.studentId,
    classId: classId ?? this.classId,
    subject: subject ?? this.subject,
    confirmedAt: confirmedAt ?? this.confirmedAt,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'student_id': studentId,
    'class_id': classId,
    'subject': subject,
    'confirmed_at': confirmedAt?.toIso8601String(),
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };

  factory StudentClassLink.fromJson(Map<String, dynamic> json) => StudentClassLink(
    id: json['id'] as String,
    studentId: (json['student_id'] as String?) ?? '',
    classId: (json['class_id'] as String?) ?? '',
    subject: (json['subject'] as String?) ?? '',
    confirmedAt: json['confirmed_at'] == null ? null : DateTime.tryParse(json['confirmed_at'].toString()),
    createdAt: DateTime.tryParse((json['created_at'] ?? '').toString()) ?? DateTime.now(),
    updatedAt: DateTime.tryParse((json['updated_at'] ?? '').toString()) ?? DateTime.now(),
  );

  static String encodeList(List<StudentClassLink> items) => jsonEncode(items.map((e) => e.toJson()).toList());
  static List<StudentClassLink> decodeList(String raw) {
    final arr = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    return arr.map(StudentClassLink.fromJson).toList();
  }
}
