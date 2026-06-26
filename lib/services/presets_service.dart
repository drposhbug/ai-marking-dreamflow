import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:marking_prokect_v2/models/grading_preset.dart';
import 'package:marking_prokect_v2/services/id_factory.dart';
import 'package:marking_prokect_v2/services/local_store.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PresetsService extends ChangeNotifier {
  static const _kKey = 'ai_marker.presets';
  static const _kSeedPrefix = 'ai_marker.default_presets_seeded.v1.';
  static const _kBuiltInOverridesKey = 'ai_marker.builtin_scheme_overrides.v1';
  final LocalStore _store;

  SupabaseClient? get _client {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  bool get _supabaseReady => _client != null;

  List<GradingPreset> _presets = const [];
  List<GradingPreset> get presets => _presets;

  Map<String, GradingPreset> _builtInOverrides = const {};
  bool _builtInOverridesLoaded = false;

  /// Built-in schemes with any local overrides applied.
  List<GradingPreset> get builtInSchemes {
    final overrides = _builtInOverrides;
    return GradingPreset.builtInDefaults
        .map((p) => overrides[p.id] ?? p)
        .toList(growable: false);
  }

  PresetsService({LocalStore? store}) : _store = store ?? const LocalStore() {
    Future.microtask(_loadBuiltInOverrides);
  }

  Future<void> _loadBuiltInOverrides() async {
    if (_builtInOverridesLoaded) return;
    try {
      final raw = await _store.getString(_kBuiltInOverridesKey);
      if (raw == null || raw.isEmpty) {
        _builtInOverrides = const {};
      } else {
        final decoded = (jsonDecode(raw) as Map).cast<String, dynamic>();
        final out = <String, GradingPreset>{};
        for (final entry in decoded.entries) {
          if (entry.key.trim().isEmpty) continue;
          if (!GradingPreset.builtInIds.contains(entry.key)) continue;
          final v = entry.value;
          if (v is Map) {
            out[entry.key] = GradingPreset.fromJson(v.cast<String, dynamic>());
          }
        }
        _builtInOverrides = out;
      }
    } catch (e) {
      debugPrint('PresetsService._loadBuiltInOverrides failed: $e');
      _builtInOverrides = const {};
    } finally {
      _builtInOverridesLoaded = true;
      notifyListeners();
    }
  }

  Future<void> _persistBuiltInOverrides() async {
    try {
      final map = <String, dynamic>{for (final e in _builtInOverrides.entries) e.key: e.value.toJson()};
      await _store.setString(_kBuiltInOverridesKey, jsonEncode(map));
    } catch (e) {
      debugPrint('PresetsService._persistBuiltInOverrides failed: $e');
    }
  }

  Future<void> init({required String teacherId, required List<String> classIds}) async {
    try {
      // Load cached state first (keeps app usable offline).
      final raw = await _store.getString(_kKey);
      if (raw != null && raw.isNotEmpty) {
        _presets = GradingPreset.decodeList(raw);
      }

      // Pull latest teacher-created schemes from Supabase if possible.
      await refreshCustomSchemesFromSupabase(teacherId: teacherId);

      // Ensure each class gets the 4 default presets once (local/offline behavior).
      final added = await _ensureDefaultPresetsForClasses(teacherId: teacherId, classIds: classIds);
      if (added) await _persist();

    } catch (e) {
      debugPrint('PresetsService.init failed: $e');
      _presets = _seed(teacherId, classIds);
    } finally {
      notifyListeners();
    }
  }

  /// Loads teacher-created global schemes (where class_id is NULL) from Supabase
  /// and merges them into local state.
  ///
  /// Built-in defaults are never fetched from Supabase.
  Future<void> refreshCustomSchemesFromSupabase({required String teacherId}) async {
    if (!_supabaseReady) return;
    try {
      final response = await _client!.from('presets').select().eq('teacher_id', teacherId).filter('class_id', 'is', null);
      final rows = (response as List?) ?? [];
      final remoteAll = rows.whereType<Map>().map((e) => GradingPreset.fromJson(e.cast<String, dynamic>())).toList();
      // Defensive: if someone inserted built-in IDs into Supabase, ignore them.
      final remote = remoteAll.where((p) => !GradingPreset.builtInIds.contains(p.id)).toList();
      final localNonGlobal = _presets.where((p) => p.classId.trim().isNotEmpty).toList();
      _presets = [...remote, ...localNonGlobal];
      await _persist();
    } catch (e) {
      debugPrint('PresetsService.refreshCustomSchemesFromSupabase failed: $e');
    }
  }

  /// Teacher-created schemes (global, class_id is empty).
  ///
  /// For UI purposes, combine [builtInSchemes] with this list.
  List<GradingPreset> customGlobalSchemes({required String teacherId}) => _presets.where((p) => p.teacherId == teacherId && p.classId.trim().isEmpty).toList();

  Future<void> upsertBuiltInOverride(GradingPreset preset) async {
    if (!preset.isBuiltInDefault) return;
    _builtInOverrides = {..._builtInOverrides, preset.id: preset.copyWith(updatedAt: DateTime.now())};
    await _persistBuiltInOverrides();
    notifyListeners();
  }

  Future<void> resetBuiltInOverride(String presetId) async {
    if (!GradingPreset.builtInIds.contains(presetId)) return;
    if (!_builtInOverrides.containsKey(presetId)) return;
    final next = {..._builtInOverrides};
    next.remove(presetId);
    _builtInOverrides = next;
    await _persistBuiltInOverrides();
    notifyListeners();
  }

  Future<bool> _ensureDefaultPresetsForClasses({required String teacherId, required List<String> classIds}) async {
    var changed = false;
    for (final classId in classIds) {
      final seedKey = '$_kSeedPrefix$teacherId.$classId';
      final alreadySeeded = (await _store.getString(seedKey)) == '1';
      if (alreadySeeded) continue;

      final now = DateTime.now();
      final existingForClass = _presets.where((p) => p.teacherId == teacherId && p.classId == classId).toList();

      // Only create a default for a mode if the class has no presets for that mode yet.
      bool hasMode(GradingMode mode) => existingForClass.any((p) => p.gradingMode == mode);

      final toAdd = <GradingPreset>[];

      if (!hasMode(GradingMode.homework)) {
        toAdd.add(_buildDefaultHomeworkCompletion(teacherId: teacherId, classId: classId, now: now));
      }
      if (!hasMode(GradingMode.testQuiz)) {
        toAdd.add(_buildDefaultTestQuizMarking(teacherId: teacherId, classId: classId, now: now));
      }
      if (!hasMode(GradingMode.labReport)) {
        toAdd.add(_buildDefaultLabReportMarking(teacherId: teacherId, classId: classId, now: now));
      }
      if (!hasMode(GradingMode.englishEssay)) {
        toAdd.add(_buildDefaultEnglishEssayMarking(teacherId: teacherId, classId: classId, now: now));
      }

      if (toAdd.isNotEmpty) {
        _presets = [...toAdd, ..._presets];
        changed = true;
      }

      // Mark class as seeded so deleted defaults don't reappear on next login.
      await _store.setString(seedKey, '1');
    }
    return changed;
  }

  GradingPreset _buildDefaultHomeworkCompletion({required String teacherId, required String classId, required DateTime now}) => GradingPreset(
    id: 'p_${IdFactory.newId()}',
    teacherId: teacherId,
    classId: classId,
    name: 'HOMEWORK COMPLETION',
    gradingMode: GradingMode.homework,
    criteria: {
      'Attempted all questions': true,
      'Working shown': true,
      'Effort evident': true,
      'Neatness': true,
    },
    harshness: 5,
    notes: 'Check that all questions were attempted and effort is visible. Do not penalize for wrong answers.',
    isDefault: true,
    createdAt: now,
    updatedAt: now,
  );

  GradingPreset _buildDefaultTestQuizMarking({required String teacherId, required String classId, required DateTime now}) => GradingPreset(
    id: 'p_${IdFactory.newId()}',
    teacherId: teacherId,
    classId: classId,
    name: 'TEST / QUIZ MARKING',
    gradingMode: GradingMode.testQuiz,
    criteria: {
      'Correct answers': true,
      'Working shown': true,
      'Units and labels': true,
      'Significant figures': true,
      'Correct formula used': true,
      'Neatness': true,
      'Diagrams labeled': true,
    },
    harshness: 5,
    notes: 'Grade based on correct answers and working shown. Penalize missing units and sig figs.',
    isDefault: true,
    createdAt: now,
    updatedAt: now,
  );

  GradingPreset _buildDefaultLabReportMarking({required String teacherId, required String classId, required DateTime now}) => GradingPreset(
    id: 'p_${IdFactory.newId()}',
    teacherId: teacherId,
    classId: classId,
    name: 'LAB REPORT MARKING',
    gradingMode: GradingMode.labReport,
    criteria: {
      'Hypothesis stated': true,
      'Method clear': true,
      'Results table complete': true,
      'Diagrams labeled': true,
      'Units correct': true,
      'Conclusion references data': true,
      'Error analysis included': true,
    },
    harshness: 5,
    notes: 'Check all sections are present and conclusion references actual data collected.',
    isDefault: true,
    createdAt: now,
    updatedAt: now,
  );

  GradingPreset _buildDefaultEnglishEssayMarking({required String teacherId, required String classId, required DateTime now}) => GradingPreset(
    id: 'p_${IdFactory.newId()}',
    teacherId: teacherId,
    classId: classId,
    name: 'ENGLISH / ESSAY MARKING',
    gradingMode: GradingMode.englishEssay,
    criteria: {
      'Structure clear': true,
      'Argument quality': true,
      'Grammar and spelling': true,
      'Vocabulary': true,
    },
    harshness: 5,
    notes: '',
    isDefault: true,
    createdAt: now,
    updatedAt: now,
  );

  List<GradingPreset> byClass(String classId) => _presets.where((p) => p.classId == classId).toList();

  GradingPreset? defaultForClass(String classId, {GradingMode? mode}) {
    final candidates = _presets.where((p) => p.classId == classId && (mode == null || p.gradingMode == mode)).toList();
    final picked = candidates.cast<GradingPreset?>().firstWhere((p) => p?.isDefault == true, orElse: () => null);
    return picked ?? (candidates.isEmpty ? null : candidates.first);
  }

  GradingPreset? getById(String id) {
    final builtIn = builtInSchemes.cast<GradingPreset?>().firstWhere((p) => p?.id == id, orElse: () => null);
    if (builtIn != null) return builtIn;
    return _presets.cast<GradingPreset?>().firstWhere((p) => p?.id == id, orElse: () => null);
  }

  Future<GradingPreset> create({required String teacherId, required String classId, required String name, required GradingMode mode, required Map<String, bool> criteria, required int harshness, required String? notes}) async {
    final now = DateTime.now();
    final created = GradingPreset(id: 'p_${IdFactory.newId()}', teacherId: teacherId, classId: classId, name: name, gradingMode: mode, criteria: criteria, harshness: harshness.clamp(1, 10), notes: notes ?? '', isDefault: false, createdAt: now, updatedAt: now);
    _presets = [created, ..._presets];
    await _persist();
    notifyListeners();

    if (_supabaseReady) {
      try {
        await _client!.from('presets').insert(created.toJson());
      } catch (e) {
        debugPrint('PresetsService.create Supabase insert failed: $e');
      }
    }

    return created;
  }

  Future<void> setDefault({required String presetId, required bool isDefault}) async {
    final preset = getById(presetId);
    if (preset == null) return;

    _presets = _presets.map((p) {
      if (p.classId == preset.classId && p.gradingMode == preset.gradingMode) {
        if (p.id == presetId) return p.copyWith(isDefault: isDefault, updatedAt: DateTime.now());
        return isDefault ? p.copyWith(isDefault: false, updatedAt: DateTime.now()) : p;
      }
      return p;
    }).toList();
    await _persist();
    notifyListeners();
  }

  Future<void> updatePreset(GradingPreset updated) async {
    if (updated.isBuiltInDefault) {
      await upsertBuiltInOverride(updated);
      return;
    }
    _presets = _presets.map((p) => p.id == updated.id ? updated.copyWith(updatedAt: DateTime.now()) : p).toList();
    await _persist();
    notifyListeners();

    if (_supabaseReady) {
      try {
        await _client!.from('presets').update(updated.copyWith(updatedAt: DateTime.now()).toJson()).eq('id', updated.id);
      } catch (e) {
        debugPrint('PresetsService.updatePreset Supabase update failed: $e');
      }
    }
  }

  Future<void> delete(String presetId) async {
    final preset = getById(presetId);
    if (preset?.isBuiltInDefault == true) {
      await resetBuiltInOverride(presetId);
      return;
    }
    _presets = _presets.where((p) => p.id != presetId).toList();
    await _persist();
    notifyListeners();

    if (_supabaseReady) {
      try {
        await _client!.from('presets').delete().eq('id', presetId);
      } catch (e) {
        debugPrint('PresetsService.delete Supabase delete failed: $e');
      }
    }

  }

  Future<void> updateHarshness({required String presetId, required int harshness}) async {
    final preset = getById(presetId);
    if (preset == null) return;
    await updatePreset(preset.copyWith(harshness: harshness.clamp(1, 10)));
  }

  Future<GradingPreset?> duplicate({required String presetId, String? teacherIdOverride, String? classIdOverride}) async {
    final preset = getById(presetId);
    if (preset == null) return null;
    final now = DateTime.now();
    final copy = preset.copyWith(
      id: 'p_${IdFactory.newId()}',
      teacherId: (teacherIdOverride ?? preset.teacherId).trim(),
      classId: classIdOverride ?? preset.classId,
      name: '${preset.name} (Copy)',
      isDefault: false,
      createdAt: now,
      updatedAt: now,
    );
    _presets = [copy, ..._presets];
    await _persist();
    notifyListeners();
    if (_supabaseReady) {
      try {
        await _client!.from('presets').insert(copy.toJson());
      } catch (e) {
        debugPrint('PresetsService.duplicate Supabase insert failed: $e');
      }
    }
    return copy;
  }

  Future<void> _persist() async => _store.setString(_kKey, GradingPreset.encodeList(_presets));

  List<GradingPreset> _seed(String teacherId, List<String> classIds) {
    if (classIds.isEmpty) return const [];
    final now = DateTime.now();
    String pick(int i) => classIds[i % classIds.length];

    return [
      GradingPreset(
        id: 'p_${IdFactory.newId()}',
        teacherId: teacherId,
        classId: pick(0),
        name: 'Strict Exam Grading',
        gradingMode: GradingMode.testQuiz,
        criteria: _defaultCriteria(GradingMode.testQuiz),
        harshness: 8,
        notes: 'Used for final assessments',
        isDefault: true,
        createdAt: now,
        updatedAt: now,
      ),
      GradingPreset(
        id: 'p_${IdFactory.newId()}',
        teacherId: teacherId,
        classId: pick(0),
        name: 'Homework Review',
        gradingMode: GradingMode.homework,
        criteria: _defaultCriteria(GradingMode.homework),
        harshness: 3,
        notes: 'Lenient grading for practice',
        isDefault: true,
        createdAt: now,
        updatedAt: now,
      ),
      GradingPreset(
        id: 'p_${IdFactory.newId()}',
        teacherId: teacherId,
        classId: pick(1),
        name: 'Lab Report Fast',
        gradingMode: GradingMode.labReport,
        criteria: _defaultCriteria(GradingMode.labReport),
        harshness: 5,
        notes: 'Formatting + conclusion focus',
        isDefault: true,
        createdAt: now,
        updatedAt: now,
      ),
      GradingPreset(
        id: 'p_${IdFactory.newId()}',
        teacherId: teacherId,
        classId: pick(3),
        name: 'Essay Banding',
        gradingMode: GradingMode.englishEssay,
        criteria: _defaultCriteria(GradingMode.englishEssay),
        harshness: 6,
        notes: 'Band-based feedback',
        isDefault: true,
        createdAt: now,
        updatedAt: now,
      ),
    ];
  }

  static Map<String, bool> _defaultCriteria(GradingMode mode) {
    final list = switch (mode) {
      GradingMode.homework => ['Attempted all questions', 'Working shown', 'Effort evident', 'Neatness'],
      GradingMode.testQuiz => ['Correct answers', 'Working shown', 'Units and labels', 'Significant figures', 'Correct formula', 'Neatness', 'Diagrams labeled'],
      GradingMode.labReport => ['Hypothesis stated', 'Method clear', 'Results table complete', 'Diagrams labeled', 'Units correct', 'Conclusion references data', 'Error analysis included'],
      GradingMode.englishEssay => ['Structure clear', 'Argument quality', 'Grammar and spelling', 'Vocabulary range', 'Evidence cited', 'Introduction present', 'Conclusion present'],
    };

    return {for (final item in list) item: true};
  }

  static List<String> criteriaLabels(GradingMode mode) => _defaultCriteria(mode).keys.toList();
}
