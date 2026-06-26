import 'dart:convert';

import 'package:marking_prokect_v2/models/grading_preset.dart';

enum TriageStatus { graded, needsReview, unableToGrade }

class Submission {
  final String id;
  final String teacherId;
  final String studentId;
  final String classId;
  final String presetId;
  final String subject;
  final GradingMode gradingMode;
  final double score;
  final double maxScore;
  final String feedback;
  final TriageStatus triageStatus;
  final bool overrideUsed;
  final String? imageUrl;
  final List<String> triageFlags;
  final int confidence; // 0-100
  final DateTime createdAt;
  final DateTime updatedAt;

  const Submission({required this.id, required this.teacherId, required this.studentId, required this.classId, required this.presetId, required this.subject, required this.gradingMode, required this.score, required this.maxScore, required this.feedback, required this.triageStatus, required this.overrideUsed, required this.triageFlags, required this.confidence, required this.createdAt, required this.updatedAt, this.imageUrl});

  Submission copyWith({String? id, String? teacherId, String? studentId, String? classId, String? presetId, String? subject, GradingMode? gradingMode, double? score, double? maxScore, String? feedback, TriageStatus? triageStatus, bool? overrideUsed, String? imageUrl, List<String>? triageFlags, int? confidence, DateTime? createdAt, DateTime? updatedAt}) => Submission(
    id: id ?? this.id,
    teacherId: teacherId ?? this.teacherId,
    studentId: studentId ?? this.studentId,
    classId: classId ?? this.classId,
    presetId: presetId ?? this.presetId,
    subject: subject ?? this.subject,
    gradingMode: gradingMode ?? this.gradingMode,
    score: score ?? this.score,
    maxScore: maxScore ?? this.maxScore,
    feedback: feedback ?? this.feedback,
    triageStatus: triageStatus ?? this.triageStatus,
    overrideUsed: overrideUsed ?? this.overrideUsed,
    imageUrl: imageUrl ?? this.imageUrl,
    triageFlags: triageFlags ?? this.triageFlags,
    confidence: confidence ?? this.confidence,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'teacher_id': teacherId,
    'student_id': studentId,
    'class_id': classId,
    'preset_id': presetId,
    'subject': subject,
    'grading_mode': gradingMode.name,
    'score': score,
    'max_score': maxScore,
    'feedback': feedback,
    'triage_status': triageStatus.name,
    'override_used': overrideUsed,
    'image_url': imageUrl,
    'triage_flags': triageFlags,
    'confidence': confidence,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };

  factory Submission.fromJson(Map<String, dynamic> json) => Submission(
    id: json['id'] as String,
    teacherId: (json['teacher_id'] as String?) ?? '',
    studentId: (json['student_id'] as String?) ?? '',
    classId: (json['class_id'] as String?) ?? '',
    presetId: (json['preset_id'] as String?) ?? '',
    subject: (json['subject'] as String?) ?? '',
    gradingMode: GradingMode.values.firstWhere((e) => e.name == (json['grading_mode'] ?? 'homework'), orElse: () => GradingMode.homework),
    score: (json['score'] as num?)?.toDouble() ?? 0,
    maxScore: (json['max_score'] as num?)?.toDouble() ?? 0,
    feedback: (json['feedback'] as String?) ?? '',
    triageStatus: TriageStatus.values.firstWhere((e) => e.name == (json['triage_status'] ?? 'graded'), orElse: () => TriageStatus.graded),
    overrideUsed: (json['override_used'] as bool?) ?? false,
    imageUrl: json['image_url'] as String?,
    triageFlags: (json['triage_flags'] as List?)?.map((e) => e.toString()).toList() ?? const [],
    confidence: (json['confidence'] as num?)?.toInt() ?? 90,
    createdAt: DateTime.tryParse((json['created_at'] ?? '').toString()) ?? DateTime.now(),
    updatedAt: DateTime.tryParse((json['updated_at'] ?? '').toString()) ?? DateTime.now(),
  );

  static String encodeList(List<Submission> items) => jsonEncode(items.map((e) => e.toJson()).toList());
  static List<Submission> decodeList(String raw) {
    final arr = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    return arr.map(Submission.fromJson).toList();
  }
}
