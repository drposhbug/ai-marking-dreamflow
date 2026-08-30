/// Running an imported sheet of responses, in a way that survives being
/// interrupted.
///
/// This is the route that costs a teacher money: every written question is a
/// paid call across the whole class. Without a checkpoint, the bell going
/// mid-import means she backs out, tries again later, and pays a second time
/// for marks she already bought — and every child ends up with two results.
///
/// So each paid answer and each filed result is written down as it happens,
/// under an id derived from the file and the class. Running the same file
/// again resumes; running it after three more students replied marks only
/// those three.
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:marking_prokect_v2/services/csv_import.dart';
import 'package:marking_prokect_v2/services/local_store.dart';

/// One question's mark for one student's row.
class ImportRowMark {
  final double score;
  final bool correct;
  final String feedback;
  const ImportRowMark(this.score, this.correct, this.feedback);

  Map<String, dynamic> toJson() => {'s': score, 'c': correct, 'f': feedback};

  factory ImportRowMark.fromJson(Map<String, dynamic> json) => ImportRowMark(
        (json['s'] as num?)?.toDouble() ?? 0,
        json['c'] == true,
        (json['f'] ?? '').toString(),
      );
}

/// Which half of the run the count on screen belongs to.
enum ImportPhase { marking, saving }

/// Where the run has got to, counted from one so a teacher never watches a
/// "0 of 30" that looks stuck.
class ImportProgress {
  final ImportPhase phase;
  final int done;
  final int total;

  /// The question being marked, while [phase] is [ImportPhase.marking].
  final String? question;

  const ImportProgress({required this.phase, required this.done, required this.total, this.question});
}

/// How far one import got: who has already been filed, and which marks have
/// already been paid for.
class ImportCheckpoint {
  /// Row key → the id of the result already filed for that response.
  final Map<String, String> filed;

  /// Question key → row key → the mark that was bought for it. Dropped once
  /// the whole sheet is filed: after that, the row keys alone are enough.
  final Map<String, Map<String, ImportRowMark>> marks;

  ImportCheckpoint({Map<String, String>? filed, Map<String, Map<String, ImportRowMark>>? marks})
      : filed = {...?filed},
        marks = {for (final e in (marks ?? const {}).entries) e.key: {...e.value}};
}

/// The record of which imports have been run, kept on the phone.
class ImportCheckpoints {
  static const _kKey = 'ai_marker.import.checkpoints';

  /// Imports kept before the oldest is forgotten. A finished one holds only
  /// short row keys, so a term of weekly quizzes is a few kilobytes.
  static const int remembered = 20;

  final LocalStore _store;

  const ImportCheckpoints({LocalStore? store}) : _store = store ?? const LocalStore();

  /// What makes two runs "the same import": the class the responses are being
  /// filed into, and the sheet's own column headers.
  ///
  /// Not the file name — a teacher's downloads folder is full of
  /// "Form Responses 1.csv" — and not the rows, which grow every time another
  /// student replies. The headers are the quiz itself, so re-downloading the
  /// same form an hour later still lands on the same import.
  static String idFor({required String classId, required List<String> headers}) =>
      'imp_${_stableHash('$classId${headers.join('')}')}';

  /// One key per response row, from everything that row says.
  ///
  /// Content, not position: a re-export with three more replies must not
  /// shift everybody's key by three and re-mark the whole class. Two rows
  /// that read identically are still two children, so the second one carries
  /// an occurrence number.
  static List<String> rowKeys(List<List<String>> rows) {
    final seen = <String, int>{};
    final keys = <String>[];
    for (final row in rows) {
      final base = _stableHash(row.join(''));
      final n = (seen[base] ?? 0) + 1;
      seen[base] = n;
      keys.add(n == 1 ? base : '$base#$n');
    }
    return keys;
  }

  /// What a paid mark was bought for. If the teacher changes the question —
  /// its type, what it is out of, the model answer — the old marks no longer
  /// answer the question being asked, so they are bought again.
  static String questionKey(ImportColumn q) =>
      '${q.index}|${q.kind.name}|${q.marks}|${_stableHash(q.keyAnswer.trim())}';

  Future<Map<String, dynamic>> _all() async {
    try {
      final raw = await _store.getString(_kKey);
      if (raw == null || raw.isEmpty) return {};
      final decoded = jsonDecode(raw);
      return decoded is Map ? decoded.cast<String, dynamic>() : {};
    } catch (e) {
      // Worst case the teacher is offered the "already marked" question one
      // time too few — never a reason to block marking.
      debugPrint('Import checkpoints unreadable — starting fresh: $e');
      return {};
    }
  }

  Future<ImportCheckpoint> load(String importId) async {
    final entry = (await _all())[importId];
    if (entry is! Map) return ImportCheckpoint();
    final filed = <String, String>{};
    for (final e in (entry['filed'] as Map? ?? const {}).entries) {
      filed[e.key.toString()] = e.value.toString();
    }
    final marks = <String, Map<String, ImportRowMark>>{};
    for (final q in (entry['marks'] as Map? ?? const {}).entries) {
      if (q.value is! Map) continue;
      marks[q.key.toString()] = {
        for (final r in (q.value as Map).entries)
          if (r.value is Map) r.key.toString(): ImportRowMark.fromJson((r.value as Map).cast<String, dynamic>()),
      };
    }
    return ImportCheckpoint(filed: filed, marks: marks);
  }

  Future<void> save(String importId, ImportCheckpoint checkpoint) async {
    final all = await _all();
    // A counter rather than a clock: thirty rows can be filed inside the same
    // millisecond, and the oldest import has to be the one that goes.
    var next = 0;
    for (final v in all.values) {
      if (v is Map) next = math.max(next, (v['n'] as num?)?.toInt() ?? 0);
    }
    all[importId] = {
      'n': next + 1,
      'at': DateTime.now().toIso8601String(),
      'filed': checkpoint.filed,
      if (checkpoint.marks.isNotEmpty)
        'marks': {
          for (final q in checkpoint.marks.entries)
            q.key: {for (final r in q.value.entries) r.key: r.value.toJson()},
        },
    };
    if (all.length > remembered) {
      final oldestFirst = all.keys.toList()
        ..sort((a, b) => _order(all[a]).compareTo(_order(all[b])));
      for (final k in oldestFirst.take(all.length - remembered)) {
        all.remove(k);
      }
    }
    await _store.setString(_kKey, jsonEncode(all));
  }

  /// Wipes what we know about an import, so a teacher who deliberately asks
  /// to mark a file again gets a clean run.
  Future<void> forget(String importId) async {
    final all = await _all();
    if (all.remove(importId) == null) return;
    await _store.setString(_kKey, jsonEncode(all));
  }

  static int _order(Object? entry) => entry is Map ? ((entry['n'] as num?)?.toInt() ?? 0) : 0;
}

/// Marks one question for exactly [rows] — the paid call.
typedef ImportQuestionMarker = Future<Map<int, ImportRowMark>> Function(ImportColumn question, List<int> rows);

/// Builds one student's result (roster, class link, the result itself) and
/// hands back the id it will be filed under.
typedef ImportRowPreparer = Future<String> Function(int row, Map<int, ImportRowMark> marks);

/// Writes everything prepared so far, in one go.
typedef ImportRowsFiler = Future<void> Function(List<int> rows);

/// What a run did, in the terms a teacher would ask about.
class ImportRunOutcome {
  final int saved;
  final int alreadySaved;
  final int failed;
  final bool stopped;
  const ImportRunOutcome({this.saved = 0, this.alreadySaved = 0, this.failed = 0, this.stopped = false});
}

/// Marks a sheet of responses and files the results, skipping anything this
/// import has already done.
///
/// The order matters for the teacher's credits: rows that already have a
/// result are dropped first, so a resumed run neither asks the AI about them
/// nor pays for them. Marks are written down the moment they come back, and
/// results are filed in one write at the end, so stopping leaves either a
/// student marked and saved or not started — never half of one.
Future<ImportRunOutcome> runImport({
  required ParsedSheet sheet,
  required List<ImportColumn> questions,
  required String importId,
  required ImportCheckpoints checkpoints,
  required ImportQuestionMarker markQuestion,
  required ImportRowPreparer prepareRow,
  required ImportRowsFiler fileRows,
  void Function(ImportProgress progress)? onProgress,
  bool Function()? isStopped,
}) async {
  final keys = ImportCheckpoints.rowKeys(sheet.rows);
  final checkpoint = await checkpoints.load(importId);
  final pending = <int>[
    for (var r = 0; r < sheet.rows.length; r++)
      if (!checkpoint.filed.containsKey(keys[r])) r,
  ];
  final alreadySaved = sheet.rows.length - pending.length;
  if (pending.isEmpty) return ImportRunOutcome(alreadySaved: alreadySaved);

  final included = questions.where((q) => q.kind != ImportColumnKind.skip).toList();
  final marks = {for (final r in pending) r: <int, ImportRowMark>{}};

  // Multiple choice: free, on the phone, and recomputed every run rather than
  // stored — it costs nothing, so there is nothing to save by remembering it.
  for (final q in included.where((q) => q.kind == ImportColumnKind.multipleChoice)) {
    for (final r in pending) {
      final answer = q.index < sheet.rows[r].length ? sheet.rows[r][q.index].trim() : '';
      final correct = CsvImport.mcCorrect(answer, q.correctAnswer);
      marks[r]![q.index] = ImportRowMark(
        correct ? q.marks : 0,
        correct,
        answer.isEmpty ? 'No answer given.' : (correct ? 'Correct.' : 'Correct answer: ${q.correctAnswer}'),
      );
    }
  }

  // Written answers: one call per question, and only for the students who
  // still need one.
  var stopped = false;
  final written = included.where((q) => q.kind != ImportColumnKind.multipleChoice).toList();
  for (var w = 0; w < written.length; w++) {
    final q = written[w];
    onProgress?.call(ImportProgress(phase: ImportPhase.marking, done: w + 1, total: written.length, question: q.header));
    final qKey = ImportCheckpoints.questionKey(q);
    final bought = Map<String, ImportRowMark>.from(checkpoint.marks[qKey] ?? const {});
    final missing = [for (final r in pending) if (!bought.containsKey(keys[r])) r];
    if (missing.isNotEmpty) {
      // Checked before the call, so stopping saves the next minute of work
      // rather than the next second of it.
      if (isStopped?.call() ?? false) {
        stopped = true;
        break;
      }
      final got = await markQuestion(q, missing);
      for (final r in missing) {
        bought[keys[r]] = got[r] ?? const ImportRowMark(0, false, '');
      }
      // Written down straight away: these are paid for, and an interruption
      // one question later must not throw them away.
      checkpoint.marks[qKey] = bought;
      await checkpoints.save(importId, checkpoint);
    }
    for (final r in pending) {
      marks[r]![q.index] = bought[keys[r]] ?? const ImportRowMark(0, false, '');
    }
  }

  if (stopped || (isStopped?.call() ?? false)) {
    return ImportRunOutcome(alreadySaved: alreadySaved, stopped: true);
  }

  final prepared = <int>[];
  final filed = <String, String>{};
  var failed = 0;
  for (var i = 0; i < pending.length; i++) {
    if (isStopped?.call() ?? false) {
      stopped = true;
      break;
    }
    final r = pending[i];
    onProgress?.call(ImportProgress(phase: ImportPhase.saving, done: i + 1, total: pending.length));
    try {
      filed[keys[r]] = await prepareRow(r, marks[r]!);
      prepared.add(r);
    } catch (e) {
      // One row the roster refused must never cost the other twenty-nine
      // their marks.
      debugPrint('Filing row $r of the import failed: $e');
      failed++;
    }
  }

  if (prepared.isNotEmpty) {
    await fileRows(prepared);
    checkpoint.filed.addAll(filed);
    // Nothing left to come back for, so the bought marks can go and the
    // checkpoint shrinks to the row keys that stop a second charge.
    if (!stopped && checkpoint.filed.length >= sheet.rows.length) checkpoint.marks.clear();
    await checkpoints.save(importId, checkpoint);
  }

  return ImportRunOutcome(saved: prepared.length, alreadySaved: alreadySaved, failed: failed, stopped: stopped);
}

/// A hash that means the same thing on every phone and every launch, so a
/// checkpoint written last Tuesday still lines up today.
///
/// Two 32-bit FNV-1a passes, multiplied in halves — on the web build an int
/// is a double, and a plain 32-bit multiply would quietly lose its low bits
/// and start matching rows that are not the same row.
String _stableHash(String value) {
  final bytes = utf8.encode(value);
  return _fnv1a(bytes, 0x811c9dc5).toRadixString(16).padLeft(8, '0') +
      _fnv1a(bytes, 0x01000193).toRadixString(16).padLeft(8, '0');
}

int _fnv1a(List<int> bytes, int seed) {
  const prime = 16777619;
  var h = seed;
  for (final b in bytes) {
    h ^= b;
    final lo = h & 0xFFFF;
    final hi = (h >> 16) & 0xFFFF;
    h = ((lo * prime) + (((hi * prime) & 0xFFFF) << 16)) & 0xFFFFFFFF;
  }
  return h;
}
