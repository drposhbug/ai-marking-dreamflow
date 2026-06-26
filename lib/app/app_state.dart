import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:marking_prokect_v2/models/grading_preset.dart';
import 'package:marking_prokect_v2/services/local_store.dart';

class GradingDraft {
  final Uint8List? imageBytes;
  final String? imageFileName;
  final String? detectedSubject;
  final String? detectedStudentName;
  final double? detectedMaxScore;

  final String? studentId;
  final String? classId;
  final String? presetId;

  final GradingMode mode;
  final Map<String, bool> criteria;
  final int harshness;
  final String notes;
  final bool oneTimeOverride;

  /// When true, the app will attempt to pick the best marking scheme after
  /// the scan step (based on the scanned image).
  final bool autoDetectScheme;

  const GradingDraft({
    required this.mode,
    required this.criteria,
    required this.harshness,
    required this.notes,
    required this.oneTimeOverride,
    required this.autoDetectScheme,
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
    String? notes,
    bool? oneTimeOverride,
    bool? autoDetectScheme,
  }) => GradingDraft(
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

  AppState({LocalStore? store}) : _store = store ?? const LocalStore();

  String _defaultModeKey(String teacherId) => 'ai_marker.default_mode.v1.$teacherId';
  String _defaultHarshnessKey(String teacherId) => 'ai_marker.default_harshness.v1.$teacherId';

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
    _draft = _draft.copyWith(imageBytes: bytes, imageFileName: fileName);
    notifyListeners();
  }

  void clearImage() {
    _draft = _draft.copyWith(imageBytes: null, imageFileName: null);
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
}
