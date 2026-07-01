import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:marking_prokect_v2/models/grading_preset.dart';
import 'package:marking_prokect_v2/models/submission.dart';
import 'package:marking_prokect_v2/services/id_factory.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ---------- Request ----------

class AiGradeRequest {
  final String teacherId;
  final String studentId;
  final String classId;
  final String presetId;
  final String subject;
  final GradingMode mode;
  final Map<String, bool> criteria;
  final int harshness;
  final String? notes;
  final bool overrideUsed;

  // The raw image bytes captured from the camera/gallery.
  final Uint8List imageBytes;

  // If stored in your DB, pass the student's grade level (1–12).
  // If null, the edge function will try to detect it from the image.
  final int? studentGrade;

  // Teacher override for grading format after the result is shown.
  // Pass 'levels' or 'percentage' to re-call with a forced format.
  final String? formatOverride;

  // Student name to show on the result (reference only, not graded on).
  final String? studentName;

  const AiGradeRequest({
    required this.teacherId,
    required this.studentId,
    required this.classId,
    required this.presetId,
    required this.subject,
    required this.mode,
    required this.criteria,
    required this.harshness,
    required this.overrideUsed,
    required this.imageBytes,
    this.notes,
    this.studentGrade,
    this.formatOverride,
    this.studentName,
  });
}

// ---------- Annotation (one mark drawn on the image) ----------

class QuestionAnnotation {
  final String questionLabel; // e.g. "Q1"
  final String earnedMark;   // e.g. "2"
  final String outOfMark;    // e.g. "/4"
  final bool correct;
  final String feedback;     // short inline note
  final double positionTop;  // 0.0–1.0 fraction of image height
  final double positionLeft; // 0.0–1.0 fraction of image width

  const QuestionAnnotation({
    required this.questionLabel,
    required this.earnedMark,
    required this.outOfMark,
    required this.correct,
    required this.feedback,
    required this.positionTop,
    required this.positionLeft,
  });

  factory QuestionAnnotation.fromJson(Map<String, dynamic> j) {
    return QuestionAnnotation(
      questionLabel: (j['questionLabel'] ?? '').toString(),
      earnedMark: (j['earnedMark'] ?? '').toString(),
      outOfMark: (j['outOfMark'] ?? '').toString(),
      correct: j['correct'] == true,
      feedback: (j['feedback'] ?? '').toString(),
      positionTop: (j['positionTop'] as num?)?.toDouble() ?? 0.0,
      positionLeft: (j['positionLeft'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

// ---------- Criterion breakdown ----------

class CriterionResult {
  final String name;
  final double score;
  final double maxScore;
  final int? level; // null when using percentage format
  final String feedback;

  const CriterionResult({
    required this.name,
    required this.score,
    required this.maxScore,
    required this.feedback,
    this.level,
  });

  factory CriterionResult.fromJson(Map<String, dynamic> j) {
    return CriterionResult(
      name: (j['name'] ?? '').toString(),
      score: (j['score'] as num?)?.toDouble() ?? 0,
      maxScore: (j['maxScore'] as num?)?.toDouble() ?? 0,
      level: (j['level'] as num?)?.toInt(),
      feedback: (j['feedback'] ?? '').toString(),
    );
  }
}

// ---------- Full result ----------

class AiGradeResult {
  // Routing info (useful for debugging / showing teacher which AI graded)
  final String detectedSubject;
  final int? detectedGrade;
  final String provider; // "claude" | "gemini" | "openai"

  // Grading format decided by the function
  final String gradingFormat; // "levels" | "percentage"

  // Score in BOTH formats — Flutter shows the right one, toggle uses the other
  final double percentage;
  final String percentageDisplay; // e.g. "74%"
  final int? level;               // 1–4 or null
  final String? levelDisplay;     // e.g. "Level 3 (70–79%)"

  final double rawScore;
  final double maxScore;

  // Feedback shown as text on screen (NOT drawn on the image)
  final String summary;
  final List<String> strengths;
  final List<String> improvements;
  final List<CriterionResult> criteriaBreakdown;

  // Annotations to draw ON the image in Flutter
  final List<QuestionAnnotation> annotations;

  // Raw transcribed text from the page
  final String rawText;

  // Legacy fields kept so the rest of the app doesn't break
  final int confidence;
  final List<String> flags;
  final TriageStatus triageStatus;

  const AiGradeResult({
    required this.detectedSubject,
    required this.detectedGrade,
    required this.provider,
    required this.gradingFormat,
    required this.percentage,
    required this.percentageDisplay,
    required this.level,
    required this.levelDisplay,
    required this.rawScore,
    required this.maxScore,
    required this.summary,
    required this.strengths,
    required this.improvements,
    required this.criteriaBreakdown,
    required this.annotations,
    required this.rawText,
    required this.confidence,
    required this.flags,
    required this.triageStatus,
  });

  // Convenience: the score to display given the current format.
  String get primaryDisplay => gradingFormat == 'levels' ? (levelDisplay ?? percentageDisplay) : percentageDisplay;

  // Legacy score field used by toSubmission / result_screen
  double get score => rawScore;

  // Returns a copy with the format flipped (for the teacher toggle).
  AiGradeResult withFormat(String newFormat) {
    return AiGradeResult(
      detectedSubject: detectedSubject,
      detectedGrade: detectedGrade,
      provider: provider,
      gradingFormat: newFormat,
      percentage: percentage,
      percentageDisplay: percentageDisplay,
      level: level,
      levelDisplay: levelDisplay,
      rawScore: rawScore,
      maxScore: maxScore,
      summary: summary,
      strengths: strengths,
      improvements: improvements,
      criteriaBreakdown: criteriaBreakdown,
      annotations: annotations,
      rawText: rawText,
      confidence: confidence,
      flags: flags,
      triageStatus: triageStatus,
    );
  }
}

// ---------- Service ----------

class AiGradingService {
  /// Detect the best marking scheme for a scanned image.
  Future<String?> detectScheme({
    required Uint8List imageBytes,
    required GradingMode mode,
    required List<GradingPreset> schemes,
  }) async {
    try {
      final client = Supabase.instance.client;
      final res = await client.functions.invoke(
        'detect_scheme',
        body: {
          'image_base64': base64Encode(imageBytes),
          'mode': mode.name,
          'schemes': schemes
              .map((s) => {
                    'id': s.id,
                    'name': s.name,
                    'grading_mode': s.gradingMode.name,
                    'criteria': s.criteria.keys.toList(),
                  })
              .toList(growable: false),
        },
      );
      final data = res.data;
      if (data is Map) {
        final map = data.cast<String, dynamic>();
        final id = (map['preset_id'] ?? map['scheme_id'] ?? map['id'] ?? '').toString().trim();
        if (id.isNotEmpty) return id;
      }
    } catch (e) {
      debugPrint('AiGradingService.detectScheme fallback: $e');
    }
    final fallback = schemes.cast<GradingPreset?>().firstWhere(
      (s) => s?.gradingMode == mode,
      orElse: () => null,
    );
    return fallback?.id;
  }

  /// Grade a submission by sending the image to the grade-submission edge function.
  Future<AiGradeResult> grade(AiGradeRequest req) async {
    final enabledCriteria = req.criteria.entries
        .where((e) => e.value == true)
        .map((e) => {'name': e.key})
        .toList(growable: false);

    try {
      final client = Supabase.instance.client;
      final res = await client.functions.invoke(
      'MARKING-PROCESS',
        body: {
          'imageBase64': base64Encode(req.imageBytes),
          'mediaType': 'image/jpeg',
          'mode': req.mode.name,
          'maxScore': _maxScoreForMode(req.mode),
          'criteria': enabledCriteria,
          'harshness': req.harshness.clamp(1, 10),
          'studentName': req.studentName,
          'studentGrade': req.studentGrade,
          if (req.formatOverride != null) 'formatOverride': req.formatOverride,
        },
      );

      final data = res.data;
      if (data is Map) {
        return _parseResponse(data.cast<String, dynamic>(), req);
      }
      throw Exception('Unexpected response shape: $data');
    } catch (e) {
      debugPrint('AiGradingService.grade error: $e');
      rethrow;
    }
  }

  AiGradeResult _parseResponse(Map<String, dynamic> map, AiGradeRequest req) {
    final percentage = (map['percentage'] as num?)?.toDouble() ?? 0;
    final rawScore = (map['rawScore'] as num?)?.toDouble() ?? 0;
    final maxScore = (map['maxScore'] as num?)?.toDouble() ?? _maxScoreForMode(req.mode).toDouble();
    final level = (map['level'] as num?)?.toInt();
    final gradingFormat = (map['gradingFormat'] ?? 'percentage').toString();

    // Confidence: use percentage as a proxy if not provided
    final confidence = (percentage.clamp(50, 99)).toInt();
    final triageStatus = confidence >= 70 ? TriageStatus.graded : TriageStatus.needsReview;

    final annotations = (map['annotations'] as List? ?? [])
        .whereType<Map>()
        .map((a) => QuestionAnnotation.fromJson(a.cast<String, dynamic>()))
        .toList();

    final criteriaBreakdown = (map['criteriaBreakdown'] as List? ?? [])
        .whereType<Map>()
        .map((c) => CriterionResult.fromJson(c.cast<String, dynamic>()))
        .toList();

    return AiGradeResult(
      detectedSubject: (map['detectedSubject'] ?? map['subject'] ?? '').toString(),
      detectedGrade: (map['detectedGrade'] as num?)?.toInt(),
      provider: (map['provider'] ?? 'unknown').toString(),
      gradingFormat: gradingFormat,
      percentage: percentage,
      percentageDisplay: (map['percentageDisplay'] ?? '${percentage.round()}%').toString(),
      level: level,
      levelDisplay: map['levelDisplay']?.toString(),
      rawScore: rawScore,
      maxScore: maxScore,
      summary: (map['summary'] ?? '').toString(),
      strengths: (map['strengths'] as List?)?.whereType<String>().toList() ?? [],
      improvements: (map['improvements'] as List?)?.whereType<String>().toList() ?? [],
      criteriaBreakdown: criteriaBreakdown,
      annotations: annotations,
      rawText: (map['rawText'] ?? '').toString(),
      confidence: confidence,
      flags: [],
      triageStatus: triageStatus,
    );
  }

  int _maxScoreForMode(GradingMode mode) {
    switch (mode) {
      case GradingMode.homework:
        return 100;
      case GradingMode.testQuiz:
        return 25;
      case GradingMode.labReport:
        return 40;
      case GradingMode.englishEssay:
        return 25;
    }
  }

  Submission toSubmission({
    required AiGradeRequest req,
    required AiGradeResult res,
    String? imageUrl,
  }) {
    final now = DateTime.now();
    return Submission(
      id: 'sub_${IdFactory.newId()}',
      teacherId: req.teacherId,
      studentId: req.studentId,
      classId: req.classId,
      presetId: req.presetId,
      subject: req.subject,
      gradingMode: req.mode,
      score: res.rawScore,
      maxScore: res.maxScore,
      feedback: res.summary,
      triageStatus: res.triageStatus,
      overrideUsed: req.overrideUsed,
      triageFlags: res.flags,
      confidence: res.confidence,
      imageUrl: imageUrl,
      createdAt: now,
      updatedAt: now,
    );
  }
}
