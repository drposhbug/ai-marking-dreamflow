import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:marking_prokect_v2/models/grading_preset.dart';
import 'package:marking_prokect_v2/services/local_store.dart';

/// One captured page of a multi-page scan.
class ScannedPage {
  final Uint8List bytes;
  final String fileName;
  const ScannedPage({required this.bytes, required this.fileName});
}

class GradingDraft {
  final Uint8List? imageBytes;
  final String? imageFileName;

  /// All scanned pages, in order. [imageBytes] mirrors the first page so
  /// existing single-image consumers (AI grading) keep working.
  final List<ScannedPage> pages;
  final String? detectedSubject;
  final String? detectedStudentName;
  final double? detectedMaxScore;

  final String? studentId;
  final String? classId;
  final String? presetId;

  final GradingMode mode;
  final Map<String, bool> criteria;
  final int harshness;

  /// Grade level (1–13) whose expectations the AI marks against.
  final int gradeLevel;
  final String notes;
  final bool oneTimeOverride;

  /// When true, the app will attempt to pick the best marking scheme after
  /// the scan step (based on the scanned image).
  final bool autoDetectScheme;

  /// Cloud-saved answer key selected for the next grade ('' = none).
  final String answerKeyId;
  final String answerKeyName;

  const GradingDraft({
    required this.mode,
    required this.criteria,
    required this.harshness,
    this.gradeLevel = 6,
    required this.notes,
    required this.oneTimeOverride,
    required this.autoDetectScheme,
    this.answerKeyId = '',
    this.answerKeyName = '',
    this.pages = const [],
    this.imageBytes,
    this.imageFileName,
    this.detectedSubject,
    this.detectedStudentName,
    this.detectedMaxScore,
    this.studentId,
    this.classId,
    this.presetId,
  });

  GradingDraft copyWith({
    List<ScannedPage>? pages,
    Uint8List? imageBytes,
    String? imageFileName,
    String? detectedSubject,
    String? detectedStudentName,
    double? detectedMaxScore,
    String? studentId,
    String? classId,
    String? presetId,
    GradingMode? mode,
    Map<String, bool>? criteria,
    int? harshness,
    int? gradeLevel,
    String? notes,
    bool? oneTimeOverride,
    bool? autoDetectScheme,
    String? answerKeyId,
    String? answerKeyName,
  }) => GradingDraft(
    answerKeyId: answerKeyId ?? this.answerKeyId,
    answerKeyName: answerKeyName ?? this.answerKeyName,
    pages: pages ?? this.pages,
    imageBytes: imageBytes ?? this.imageBytes,
    imageFileName: imageFileName ?? this.imageFileName,
    detectedSubject: detectedSubject ?? this.detectedSubject,
    detectedStudentName: detectedStudentName ?? this.detectedStudentName,
    detectedMaxScore: detectedMaxScore ?? this.detectedMaxScore,
    studentId: studentId ?? this.studentId,
    classId: classId ?? this.classId,
    presetId: presetId ?? this.presetId,
    mode: mode ?? this.mode,
    criteria: criteria ?? this.criteria,
    harshness: harshness ?? this.harshness,
    gradeLevel: gradeLevel ?? this.gradeLevel,
    notes: notes ?? this.notes,
    oneTimeOverride: oneTimeOverride ?? this.oneTimeOverride,
    autoDetectScheme: autoDetectScheme ?? this.autoDetectScheme,
  );

  static GradingDraft initial() => GradingDraft(
    mode: GradingMode.homework,
    criteria: const <String, bool>{},
    harshness: 5,
    notes: '',
    oneTimeOverride: true,
    autoDetectScheme: true,
  );
}

class AppState extends ChangeNotifier {
  static const _kThemeModeKey = 'ai_marker.theme_mode.v1';

  final LocalStore _store;

  GradingDraft _draft = GradingDraft.initial();
  GradingDraft get draft => _draft;

  ThemeMode _themeMode = ThemeMode.light;
  ThemeMode get themeMode => _themeMode;

  GradingMode _defaultMode = GradingMode.homework;
  GradingMode get defaultMode => _defaultMode;

  int _defaultHarshness = 5;
  int get defaultHarshness => _defaultHarshness;

  /// Curriculum region id (see lib/data/curriculum_regions.dart); '' = unset.
  String _region = '';
  String get region => _region;

  /// The school the teacher teaches at (asked during onboarding).
  String _school = '';
  String get school => _school;

  /// Standing corrections the teacher has given about how the AI should mark
  /// ("teach the AI"). Sent with every grade so the AI follows them.
  List<String> _markingFeedback = const [];
  List<String> get markingFeedback => _markingFeedback;

  AppState({LocalStore? store}) : _store = store ?? const LocalStore();

  String _defaultModeKey(String teacherId) => 'ai_marker.default_mode.v1.$teacherId';
  String _defaultHarshnessKey(String teacherId) => 'ai_marker.default_harshness.v1.$teacherId';
  String _regionKey(String teacherId) => 'ai_marker.region.v1.$teacherId';
  String _schoolKey(String teacherId) => 'ai_marker.school.v1.$teacherId';
  String _markingFeedbackKey(String teacherId) => 'ai_marker.marking_feedback.v1.$teacherId';

  Future<void> initForUser({required String teacherId}) async {
    try {
      await initTheme();

      final rawMode = await _store.getString(_defaultModeKey(teacherId));
      if (rawMode != null && rawMode.isNotEmpty) {
        _defaultMode = GradingMode.values.firstWhere((e) => e.name == rawMode, orElse: () => GradingMode.testQuiz);
      }

      final rawHarshness = await _store.getString(_defaultHarshnessKey(teacherId));
      final harshness = int.tryParse((rawHarshness ?? '').trim());
      if (harshness != null) _defaultHarshness = harshness.clamp(1, 10);

      final rawRegion = await _store.getString(_regionKey(teacherId));
      if (rawRegion != null && rawRegion.isNotEmpty) _region = rawRegion;

      final rawSchool = await _store.getString(_schoolKey(teacherId));
      if (rawSchool != null && rawSchool.isNotEmpty) _school = rawSchool;

      final rawFeedback = await _store.getString(_markingFeedbackKey(teacherId));
      if (rawFeedback != null && rawFeedback.isNotEmpty) {
        _markingFeedback = (jsonDecode(rawFeedback) as List).whereType<String>().toList(growable: false);
      }

      _draft = _draft.copyWith(mode: _defaultMode, harshness: _defaultHarshness);
      notifyListeners();
    } catch (e) {
      debugPrint('AppState.initForUser failed: $e');
    }
  }

  Future<void> initTheme() async {
    try {
      final rawTheme = await _store.getString(_kThemeModeKey);
      if (rawTheme == 'dark') _themeMode = ThemeMode.dark;
      if (rawTheme == 'light') _themeMode = ThemeMode.light;
    } catch (e) {
      debugPrint('AppState.initTheme failed: $e');
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    try {
      await _store.setString(_kThemeModeKey, mode == ThemeMode.dark ? 'dark' : 'light');
    } catch (e) {
      debugPrint('AppState.setThemeMode failed: $e');
    }
  }

  Future<void> setDefaultMode({required String teacherId, required GradingMode mode}) async {
    _defaultMode = mode;
    _draft = _draft.copyWith(mode: mode);
    notifyListeners();
    await _store.setString(_defaultModeKey(teacherId), mode.name);
  }

  Future<void> setDefaultHarshness({required String teacherId, required int harshness}) async {
    final v = harshness.clamp(1, 10);
    _defaultHarshness = v;
    _draft = _draft.copyWith(harshness: v);
    notifyListeners();
    await _store.setString(_defaultHarshnessKey(teacherId), v.toString());
  }

  void resetDraft() {
    _draft = GradingDraft.initial().copyWith(mode: _defaultMode, harshness: _defaultHarshness);
    notifyListeners();
  }

  void setMode(GradingMode mode, {Map<String, bool>? criteria, int? harshness}) {
    _draft = _draft.copyWith(mode: mode, criteria: criteria ?? _draft.criteria, harshness: harshness ?? _draft.harshness);
    notifyListeners();
  }

  void setImageBytes({required Uint8List bytes, String? fileName}) {
    _draft = _draft.copyWith(
      imageBytes: bytes,
      imageFileName: fileName,
      pages: [ScannedPage(bytes: bytes, fileName: fileName ?? 'scan.jpg')],
    );
    notifyListeners();
  }

  void setPages(List<ScannedPage> pages) {
    if (pages.isEmpty) return;
    _draft = _draft.copyWith(
      pages: List.unmodifiable(pages),
      imageBytes: pages.first.bytes,
      imageFileName: pages.first.fileName,
    );
    notifyListeners();
  }

  void replacePage(int index, ScannedPage page) {
    if (index < 0 || index >= _draft.pages.length) return;
    final pages = [..._draft.pages];
    pages[index] = page;
    setPages(pages);
  }

  void removePage(int index) {
    if (index < 0 || index >= _draft.pages.length) return;
    final pages = [..._draft.pages]..removeAt(index);
    if (pages.isEmpty) {
      clearImage();
    } else {
      setPages(pages);
    }
  }

  void clearImage() {
    // copyWith(imageBytes: null) would keep the old bytes, so rebuild the
    // draft explicitly with the image fields dropped.
    _draft = GradingDraft(
      mode: _draft.mode,
      criteria: _draft.criteria,
      harshness: _draft.harshness,
      gradeLevel: _draft.gradeLevel,
      notes: _draft.notes,
      oneTimeOverride: _draft.oneTimeOverride,
      autoDetectScheme: _draft.autoDetectScheme,
      answerKeyId: _draft.answerKeyId,
      answerKeyName: _draft.answerKeyName,
      detectedSubject: _draft.detectedSubject,
      detectedStudentName: _draft.detectedStudentName,
      detectedMaxScore: _draft.detectedMaxScore,
      studentId: _draft.studentId,
      classId: _draft.classId,
      presetId: _draft.presetId,
    );
    notifyListeners();
  }

  /// After a scan is queued for marking: clear the pages and the per-student
  /// bits, but KEEP everything the teacher set up for the batch — class,
  /// grade level, answer key, criteria, notes — so they can scan the next
  /// student's paper straight away.
  void prepareNextScan() {
    _draft = GradingDraft(
      mode: _draft.mode,
      criteria: _draft.criteria,
      harshness: _draft.harshness,
      gradeLevel: _draft.gradeLevel,
      notes: _draft.notes,
      oneTimeOverride: _draft.oneTimeOverride,
      autoDetectScheme: _draft.autoDetectScheme,
      answerKeyId: _draft.answerKeyId,
      answerKeyName: _draft.answerKeyName,
      classId: _draft.classId,
      presetId: _draft.presetId,
    );
    notifyListeners();
  }

  void setDetections({String? subject, String? studentName, double? maxScore}) {
    _draft = _draft.copyWith(detectedSubject: subject, detectedStudentName: studentName, detectedMaxScore: maxScore);
    notifyListeners();
  }

  void setStudentClassPreset({String? studentId, String? classId, String? presetId}) {
    _draft = _draft.copyWith(studentId: studentId, classId: classId, presetId: presetId);
    notifyListeners();
  }

  void setCriteria(Map<String, bool> criteria) {
    _draft = _draft.copyWith(criteria: criteria);
    notifyListeners();
  }

  void setHarshness(int harshness) {
    _draft = _draft.copyWith(harshness: harshness);
    notifyListeners();
  }

  void setGradeLevel(int gradeLevel) {
    _draft = _draft.copyWith(gradeLevel: gradeLevel.clamp(1, 13));
    notifyListeners();
  }

  Future<void> setRegion({required String teacherId, required String regionId}) async {
    _region = regionId;
    notifyListeners();
    await _store.setString(_regionKey(teacherId), regionId);
  }

  Future<void> setSchool({required String teacherId, required String school}) async {
    _school = school.trim();
    notifyListeners();
    await _store.setString(_schoolKey(teacherId), _school);
  }

  Future<void> addMarkingFeedback({required String teacherId, required String feedback}) async {
    final text = feedback.trim();
    if (text.isEmpty) return;
    _markingFeedback = List.unmodifiable([..._markingFeedback, text]);
    notifyListeners();
    await _store.setString(_markingFeedbackKey(teacherId), jsonEncode(_markingFeedback));
  }

  Future<void> removeMarkingFeedbackAt({required String teacherId, required int index}) async {
    if (index < 0 || index >= _markingFeedback.length) return;
    final next = [..._markingFeedback]..removeAt(index);
    _markingFeedback = List.unmodifiable(next);
    notifyListeners();
    await _store.setString(_markingFeedbackKey(teacherId), jsonEncode(_markingFeedback));
  }

  void setNotes(String notes) {
    _draft = _draft.copyWith(notes: notes);
    notifyListeners();
  }

  void setOneTimeOverride(bool value) {
    _draft = _draft.copyWith(oneTimeOverride: value);
    notifyListeners();
  }

  void setAutoDetectScheme(bool value) {
    _draft = _draft.copyWith(autoDetectScheme: value);
    notifyListeners();
  }

  void setAnswerKey({String? id, String? name}) {
    _draft = _draft.copyWith(answerKeyId: id ?? '', answerKeyName: name ?? '');
    notifyListeners();
  }
}
