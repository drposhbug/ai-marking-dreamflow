import 'dart:convert';

enum GradingMode { homework, testQuiz, labReport, englishEssay }

/// One correction a teacher agreed to have remembered for a scheme.
///
/// It is stored in her own words — she reads and can edit the sentence
/// before it is kept — and it travels with every future mark on that scheme
/// as a plain instruction. Nothing about a rule is inferred at marking time;
/// what she approved is what the marker is told.
class MarkingRule {
  final String id;

  /// The instruction as the teacher left it.
  final String text;

  /// Which repeated correction produced it (see MarkingSignal.key). Kept so
  /// deleting a rule can also clear the tally that suggested it, instead of
  /// the same question coming back a week later.
  final String signalKey;

  final DateTime createdAt;

  const MarkingRule({required this.id, required this.text, required this.signalKey, required this.createdAt});

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'signal_key': signalKey,
        'created_at': createdAt.toIso8601String(),
      };

  factory MarkingRule.fromJson(Map<String, dynamic> j) => MarkingRule(
        id: (j['id'] ?? '').toString(),
        text: (j['text'] ?? '').toString(),
        signalKey: (j['signal_key'] ?? '').toString(),
        createdAt: DateTime.tryParse((j['created_at'] ?? '').toString()) ?? DateTime.now(),
      );
}

class GradingPreset {
  /// Hard-coded IDs for the built-in schemes that ship with the app.
  ///
  /// These are intentionally stable so we can store local overrides
  /// (e.g., when a signed-out teacher tweaks a default scheme).
  static const String builtInHomeworkId = 'default_homework';
  static const String builtInTestId = 'default_test_quiz';
  static const String builtInLabId = 'default_lab_report';
  static const String builtInEnglishId = 'default_english_essay';

  static final DateTime _builtInTimestamp = DateTime(2025, 1, 1);

  static const Set<String> builtInIds = {builtInHomeworkId, builtInTestId, builtInLabId, builtInEnglishId};

  /// A scheme remembers at most this many of the teacher's corrections.
  ///
  /// Eight is about as many standing instructions as a teacher can still
  /// read back and recognise as hers. It also has to share the marking
  /// request with the general "teach the marker" corrections she may have
  /// saved in Settings — the server keeps the first twenty instructions and
  /// drops the rest, so a scheme's rules go first and leave room for those.
  ///
  /// At the cap nothing is silently evicted: she is told the scheme is full
  /// and asked to delete one.
  static const int maxRulesPerPreset = 8;

  /// The 4 default schemes are embedded in the app and do not require
  /// Supabase connectivity or authentication to load.
  static final List<GradingPreset> builtInDefaults = [
    GradingPreset(
      id: builtInHomeworkId,
      teacherId: '',
      classId: '',
      name: 'Homework Completion',
      gradingMode: GradingMode.homework,
      criteria: const {
        'Attempted all questions': true,
        'Working shown': true,
        'Effort evident': true,
        'Neatness': true,
      },
      harshness: 5,
      notes: 'Check all questions attempted. Do not penalize wrong answers.',
      isDefault: true,
      createdAt: _builtInTimestamp,
      updatedAt: _builtInTimestamp,
    ),
    GradingPreset(
      id: builtInTestId,
      teacherId: '',
      classId: '',
      name: 'Test / Quiz Marking',
      gradingMode: GradingMode.testQuiz,
      criteria: const {
        'Correct answers': true,
        'Working shown': true,
        'Units and labels': true,
        'Significant figures': true,
        'Correct formula': true,
        'Neatness': true,
        'Diagrams labeled': true,
      },
      harshness: 5,
      notes: 'Grade on correct answers and working. Penalize missing units.',
      isDefault: true,
      createdAt: _builtInTimestamp,
      updatedAt: _builtInTimestamp,
    ),
    GradingPreset(
      id: builtInLabId,
      teacherId: '',
      classId: '',
      name: 'Lab Report Marking',
      gradingMode: GradingMode.labReport,
      criteria: const {
        'Hypothesis stated': true,
        'Method clear': true,
        'Results table complete': true,
        'Diagrams labeled': true,
        'Units correct': true,
        'Conclusion references data': true,
        'Error analysis included': true,
      },
      harshness: 5,
      notes: 'Check all sections present. Conclusion must reference actual data.',
      isDefault: true,
      createdAt: _builtInTimestamp,
      updatedAt: _builtInTimestamp,
    ),
    GradingPreset(
      id: builtInEnglishId,
      teacherId: '',
      classId: '',
      name: 'English / Essay Marking',
      gradingMode: GradingMode.englishEssay,
      criteria: const {
        'Structure clear': true,
        'Argument quality': true,
        'Grammar and spelling': true,
        'Vocabulary range': true,
        'Evidence cited': true,
        'Introduction present': true,
        'Conclusion present': true,
      },
      harshness: 5,
      notes: 'Grade on argument strength. Check evidence is cited properly.',
      isDefault: true,
      createdAt: _builtInTimestamp,
      updatedAt: _builtInTimestamp,
    ),
  ];

  final String id;
  final String teacherId;
  final String classId;
  final String name;
  final GradingMode gradingMode;
  /// Criteria keys are the human-readable criteria labels.
  /// Values are always non-null booleans.
  final Map<String, bool> criteria;
  final int harshness; // 1-10
  final String notes;
  final bool isDefault;
  final DateTime createdAt;
  final DateTime updatedAt;

  const GradingPreset({required this.id, required this.teacherId, required this.classId, required this.name, required this.gradingMode, required this.criteria, required this.harshness, required this.isDefault, required this.createdAt, required this.updatedAt, required this.notes});

  bool get isBuiltInDefault => teacherId.trim().isEmpty && classId.trim().isEmpty && builtInIds.contains(id);

  GradingPreset copyWith({String? id, String? teacherId, String? classId, String? name, GradingMode? gradingMode, Map<String, bool>? criteria, int? harshness, String? notes, bool? isDefault, DateTime? createdAt, DateTime? updatedAt}) => GradingPreset(
    id: id ?? this.id,
    teacherId: teacherId ?? this.teacherId,
    classId: classId ?? this.classId,
    name: name ?? this.name,
    gradingMode: gradingMode ?? this.gradingMode,
    criteria: criteria ?? this.criteria,
    harshness: harshness ?? this.harshness,
    notes: notes ?? this.notes,
    isDefault: isDefault ?? this.isDefault,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  static Map<String, bool> _parseCriteria(dynamic raw) {
    // Supabase JSON columns can come back as Map, or (rarely) as a JSON string.
    dynamic v = raw;
    if (v is String) {
      try {
        v = jsonDecode(v);
      } catch (_) {
        v = null;
      }
    }

    final map = v is Map ? v : const <dynamic, dynamic>{};
    final out = <String, bool>{};
    for (final entry in map.entries) {
      final key = (entry.key ?? '').toString().trim();
      if (key.isEmpty) continue;
      // Treat any non-true value as false to avoid `Null is not a subtype of bool`.
      out[key] = entry.value == true;
    }
    return out;
  }

  /// JSON used both for local storage and Supabase rows.
  ///
  /// Note: for "global" schemes we store `class_id` as NULL in Supabase,
  /// so we omit it when [classId] is empty.
  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'id': id,
      'teacher_id': teacherId,
      'name': name,
      'grading_mode': gradingMode.name,
      'criteria': criteria,
      'harshness': harshness,
      'notes': notes,
      'is_default': isDefault,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
    if (classId.trim().isNotEmpty) map['class_id'] = classId;
    return map;
  }

  factory GradingPreset.fromJson(Map<String, dynamic> json) => GradingPreset(
    id: (json['id'] ?? '').toString(),
    teacherId: (json['teacher_id'] ?? '').toString(),
    classId: (json['class_id'] ?? '').toString(),
    name: (json['name'] ?? '').toString(),
    gradingMode: GradingMode.values.firstWhere((e) => e.name == (json['grading_mode'] ?? 'homework'), orElse: () => GradingMode.homework),
    criteria: _parseCriteria(json['criteria'] ?? const {}),
    harshness: (json['harshness'] as num?)?.toInt() ?? 5,
    notes: (json['notes'] ?? '').toString(),
    isDefault: (json['is_default'] as bool?) ?? false,
    createdAt: DateTime.tryParse((json['created_at'] ?? '').toString()) ?? DateTime.now(),
    updatedAt: DateTime.tryParse((json['updated_at'] ?? '').toString()) ?? DateTime.now(),
  );

  static String encodeList(List<GradingPreset> items) => jsonEncode(items.map((e) => e.toJson()).toList());
  static List<GradingPreset> decodeList(String raw) {
    final arr = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    return arr.map(GradingPreset.fromJson).toList();
  }
}
