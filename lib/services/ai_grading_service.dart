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

  // The raw image bytes captured from the camera/gallery (first page).
  final Uint8List imageBytes;

  // All pages of the submission, in order. When set, every page is sent
  // to the grader; otherwise only [imageBytes] is sent.
  final List<Uint8List>? pageImages;

  // If stored in your DB, pass the student's grade level (1–13).
  // If null, the edge function will try to detect it from the image.
  final int? studentGrade;

  // Grade level (1–12) whose curriculum expectations the AI marks against —
  // set by the teacher with the grade slider on the grading context screen.
  final int? gradeLevel;

  // Curriculum region id (e.g. 'ca-on', 'us-fl') — anchors marking to the
  // teacher's provincial/state curriculum. See lib/data/curriculum_regions.dart.
  final String? region;

  // Standing corrections the teacher has given about how the AI should mark
  // ("teach the AI") — the AI applies them on every grade.
  final List<String>? teacherFeedback;

  // Teacher override for grading format after the result is shown.
  // Pass 'levels' or 'percentage' to re-call with a forced format.
  final String? formatOverride;

  // Student name to show on the result (reference only, not graded on).
  final String? studentName;

  // Cloud-saved answer key to mark against (extracted once, reused —
  // grading only pays for the key's compact text, not re-analysis).
  final String? answerKeyId;

  // When true, the AI also transcribes the pages into rawText. Off by
  // default — transcription is the largest output-token cost and nothing
  // in the app currently displays it.
  final bool includeTranscription;

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
    this.pageImages,
    this.notes,
    this.studentGrade,
    this.gradeLevel,
    this.region,
    this.teacherFeedback,
    this.formatOverride,
    this.studentName,
    this.answerKeyId,
    this.includeTranscription = false,
  });
}

// ---------- Roster entry (read off a photographed attendance sheet) ----------

class RosterEntry {
  final String name;
  final String? studentId;

  const RosterEntry({required this.name, this.studentId});
}

// ---------- Generated plan (lesson plan / assignment / quiz) ----------

class GeneratedPlan {
  final String title;
  final String content;

  const GeneratedPlan({required this.title, required this.content});
}

// ---------- Region candidate (inferred from the school name) ----------

class RegionCandidate {
  final String regionId;
  final String label; // curriculum label, e.g. "Ontario, Canada"
  final String place; // human place, e.g. "Toronto, Ontario"

  const RegionCandidate({required this.regionId, required this.label, required this.place});
}

// ---------- Account profile (cloud-saved, restored on sign-in) ----------

class CloudProfile {
  final String name;
  final String school;
  final String region;
  final List<String> markingFeedback;

  const CloudProfile({required this.name, required this.school, required this.region, required this.markingFeedback});

  /// A completed profile means onboarding already ran on some device.
  bool get isComplete => name.isNotEmpty && school.isNotEmpty;
}

// ---------- Answer key summary (cloud-saved) ----------

class AnswerKeySummary {
  final String id;
  final String name;
  final String? subject;
  final double? totalMarks;

  const AnswerKeySummary({required this.id, required this.name, this.subject, this.totalMarks});
}

// ---------- Annotation (one mark drawn on the image) ----------

class QuestionAnnotation {
  final String questionLabel; // e.g. "Q1"
  final String earnedMark;   // e.g. "2"
  final String outOfMark;    // e.g. "/4"
  final bool correct;
  final String feedback;     // short inline note
  final int pageIndex;       // which scanned page this mark belongs to (0-based)
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
    this.pageIndex = 0,
  });

  factory QuestionAnnotation.fromJson(Map<String, dynamic> j) {
    return QuestionAnnotation(
      questionLabel: (j['questionLabel'] ?? '').toString(),
      earnedMark: (j['earnedMark'] ?? '').toString(),
      outOfMark: (j['outOfMark'] ?? '').toString(),
      correct: j['correct'] == true,
      feedback: (j['feedback'] ?? '').toString(),
      pageIndex: (j['pageIndex'] as num?)?.toInt() ?? 0,
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

  // The student's name as read off the paper (null when none visible).
  final String? studentNameOnPaper;

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
    this.studentNameOnPaper,
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
  AiGradeResult withFormat(String newFormat) => copyWith(gradingFormat: newFormat);

  /// Copy with selected fields replaced — used for teacher overrides.
  AiGradeResult copyWith({
    String? gradingFormat,
    double? percentage,
    String? percentageDisplay,
    int? level,
    bool clearLevel = false,
    String? levelDisplay,
    double? rawScore,
    double? maxScore,
    List<QuestionAnnotation>? annotations,
  }) {
    return AiGradeResult(
      detectedSubject: detectedSubject,
      detectedGrade: detectedGrade,
      provider: provider,
      studentNameOnPaper: studentNameOnPaper,
      gradingFormat: gradingFormat ?? this.gradingFormat,
      percentage: percentage ?? this.percentage,
      percentageDisplay: percentageDisplay ?? this.percentageDisplay,
      level: clearLevel ? null : (level ?? this.level),
      levelDisplay: levelDisplay ?? this.levelDisplay,
      rawScore: rawScore ?? this.rawScore,
      maxScore: maxScore ?? this.maxScore,
      summary: summary,
      strengths: strengths,
      improvements: improvements,
      criteriaBreakdown: criteriaBreakdown,
      annotations: annotations ?? this.annotations,
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

  /// Generates a classroom-ready lesson plan, assignment, quiz, or worksheet.
  Future<GeneratedPlan> generatePlan({
    required String topic,
    required String kind,
    int? gradeLevel,
    String? subject,
    String? region,
  }) async {
    final client = Supabase.instance.client;
    final res = await client.functions.invoke(
      'MARKING-PROCESS',
      body: {
        'action': 'plan',
        'topic': topic,
        'kind': kind,
        if (gradeLevel != null) 'gradeLevel': gradeLevel,
        if (subject != null && subject.isNotEmpty) 'subject': subject,
        if (region != null && region.isNotEmpty) 'region': region,
      },
    );
    final data = res.data;
    if (data is Map && data['content'] != null) {
      return GeneratedPlan(
        title: (data['title'] ?? 'Untitled plan').toString(),
        content: (data['content'] ?? '').toString(),
      );
    }
    throw Exception('Planning failed: $data');
  }

  /// Autocomplete suggestions while the teacher types their school's name.
  Future<List<String>> suggestSchools({required String query}) async {
    final client = Supabase.instance.client;
    final res = await client.functions.invoke(
      'MARKING-PROCESS',
      body: {'action': 'suggest_schools', 'query': query},
    );
    final data = res.data;
    if (data is Map && data['schools'] is List) {
      return (data['schools'] as List).whereType<String>().where((s) => s.trim().isNotEmpty).toList(growable: false);
    }
    return const [];
  }

  /// Infers the curriculum region from the school's name. One candidate when
  /// the AI is confident; several when the name exists in multiple regions
  /// (the UI then shows the place in brackets for the teacher to pick).
  Future<List<RegionCandidate>> inferRegion({required String school}) async {
    final client = Supabase.instance.client;
    final res = await client.functions.invoke(
      'MARKING-PROCESS',
      body: {'action': 'infer_region', 'school': school},
    );
    final data = res.data;
    if (data is Map && data['candidates'] is List) {
      return (data['candidates'] as List)
          .whereType<Map>()
          .map((c) => RegionCandidate(
                regionId: (c['regionId'] ?? '').toString(),
                label: (c['label'] ?? '').toString(),
                place: (c['place'] ?? '').toString(),
              ))
          .where((c) => c.regionId.isNotEmpty)
          .toList(growable: false);
    }
    throw Exception('Region inference failed: $data');
  }

  /// Saves the teacher's account profile (name, school, region, marking
  /// preferences) to the cloud so signing in on any device restores it.
  Future<void> saveProfile({
    required String teacherId,
    String? email,
    String? name,
    String? school,
    String? region,
    List<String>? markingFeedback,
  }) async {
    final client = Supabase.instance.client;
    await client.functions.invoke('MARKING-PROCESS', body: {
      'action': 'save_profile',
      'teacherId': teacherId,
      if (email != null) 'email': email,
      if (name != null) 'name': name,
      if (school != null) 'school': school,
      if (region != null) 'region': region,
      if (markingFeedback != null) 'markingFeedback': markingFeedback,
    });
  }

  /// The account's saved profile, or null when it has never been saved.
  Future<CloudProfile?> getProfile({required String teacherId}) async {
    final client = Supabase.instance.client;
    final res = await client.functions.invoke(
      'MARKING-PROCESS',
      body: {'action': 'get_profile', 'teacherId': teacherId},
    );
    final data = res.data;
    if (data is Map && data['profile'] is Map) {
      final p = data['profile'] as Map;
      return CloudProfile(
        name: (p['name'] ?? '').toString().trim(),
        school: (p['school'] ?? '').toString().trim(),
        region: (p['region'] ?? '').toString().trim(),
        markingFeedback: p['marking_feedback'] is List
            ? (p['marking_feedback'] as List).map((e) => e.toString()).where((s) => s.trim().isNotEmpty).toList(growable: false)
            : const [],
      );
    }
    return null;
  }

  /// Reads student names (and IDs when shown) off photos of an attendance
  /// sheet or class roster — used by onboarding to auto-populate a class.
  Future<List<RosterEntry>> extractRoster({required List<Uint8List> pages}) async {
    final client = Supabase.instance.client;
    final res = await client.functions.invoke(
      'MARKING-PROCESS',
      body: {
        'action': 'extract_roster',
        'imagesBase64': pages.map(base64Encode).toList(growable: false),
        'mediaType': 'image/jpeg',
      },
    );
    final data = res.data;
    if (data is Map && data['students'] is List) {
      return (data['students'] as List)
          .whereType<Map>()
          .map((m) {
            final id = (m['studentId'] ?? '').toString().trim();
            return RosterEntry(
              name: (m['name'] ?? '').toString().trim(),
              studentId: id.isEmpty ? null : id,
            );
          })
          .where((e) => e.name.isNotEmpty)
          .toList(growable: false);
    }
    throw Exception('Roster extraction failed: $data');
  }

  /// Scans of a teacher's answer key → structured key stored in the cloud.
  /// Costs AI tokens once; every later grade reuses the stored key text.
  Future<AnswerKeySummary> extractAnswerKey({required String teacherId, required List<Uint8List> pages}) async {
    final client = Supabase.instance.client;
    final res = await client.functions.invoke(
      'MARKING-PROCESS',
      body: {
        'action': 'extract_key',
        'teacherId': teacherId,
        'imagesBase64': pages.map(base64Encode).toList(growable: false),
        'mediaType': 'image/jpeg',
      },
    );
    final data = res.data;
    if (data is Map && data['id'] != null) {
      final map = data.cast<String, dynamic>();
      return AnswerKeySummary(
        id: map['id'].toString(),
        name: (map['name'] ?? 'Answer key').toString(),
        subject: map['subject']?.toString(),
        totalMarks: (map['totalMarks'] as num?)?.toDouble(),
      );
    }
    throw Exception('Answer key extraction failed: $data');
  }

  /// Lists the teacher's cloud-saved answer keys, newest first.
  Future<List<AnswerKeySummary>> listAnswerKeys({required String teacherId}) async {
    final client = Supabase.instance.client;
    final res = await client.functions.invoke(
      'MARKING-PROCESS',
      body: {'action': 'list_keys', 'teacherId': teacherId},
    );
    final data = res.data;
    if (data is Map && data['keys'] is List) {
      return (data['keys'] as List)
          .whereType<Map>()
          .map((k) => AnswerKeySummary(
                id: (k['id'] ?? '').toString(),
                name: (k['name'] ?? 'Answer key').toString(),
                subject: k['subject']?.toString(),
                totalMarks: (k['total_marks'] as num?)?.toDouble(),
              ))
          .where((k) => k.id.isNotEmpty)
          .toList(growable: false);
    }
    return const [];
  }

  /// Grade a submission by sending the image to the grade-submission edge function.
  Future<AiGradeResult> grade(AiGradeRequest req) async {
    final enabledCriteria = req.criteria.entries
        .where((e) => e.value == true)
        .map((e) => {'name': e.key})
        .toList(growable: false);

    final pages = (req.pageImages == null || req.pageImages!.isEmpty)
        ? <Uint8List>[req.imageBytes]
        : req.pageImages!;

    try {
      final client = Supabase.instance.client;
      final res = await client.functions.invoke(
      'MARKING-PROCESS',
        body: {
          'imagesBase64': pages.map(base64Encode).toList(growable: false),
          'mediaType': 'image/jpeg',
          'mode': req.mode.name,
          'maxScore': _maxScoreForMode(req.mode),
          'criteria': enabledCriteria,
          'harshness': req.harshness.clamp(1, 10),
          'studentName': req.studentName,
          'studentGrade': req.studentGrade,
          if (req.gradeLevel != null) 'expectationGrade': req.gradeLevel,
          if (req.region != null && req.region!.isNotEmpty) 'region': req.region,
          if (req.teacherFeedback != null && req.teacherFeedback!.isNotEmpty) 'teacherFeedback': req.teacherFeedback,
          if (req.formatOverride != null) 'formatOverride': req.formatOverride,
          if (req.answerKeyId != null) 'answerKeyId': req.answerKeyId,
          if (req.includeTranscription) 'includeTranscription': true,
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

    final paperName = map['studentNameOnPaper']?.toString().trim();

    return AiGradeResult(
      detectedSubject: (map['detectedSubject'] ?? map['subject'] ?? '').toString(),
      detectedGrade: (map['detectedGrade'] as num?)?.toInt(),
      provider: (map['provider'] ?? 'unknown').toString(),
      studentNameOnPaper: (paperName == null || paperName.isEmpty) ? null : paperName,
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
