import 'package:flutter_test/flutter_test.dart';
import 'package:marking_prokect_v2/services/csv_import.dart';
import 'package:marking_prokect_v2/services/import_run.dart';
import 'package:marking_prokect_v2/services/local_store.dart';

/// Importing a form's responses is the route that costs money: every written
/// question is a paid call across the whole class. So the rules these tests
/// hold to are about a teacher's credits and her dashboard, not about code:
///
///  * running the same file twice must never charge twice, and must never
///    leave two results sitting under one child's name;
///  * a run stopped half way — the bell goes, she backs out — must pick up
///    where it stopped rather than starting the whole class again;
///  * the count on screen must be the count of the work actually left.
class _MemoryStore implements LocalStore {
  final data = <String, String>{};
  final writes = <String, int>{};
  @override
  Future<String?> getString(String key) async => data[key];
  @override
  Future<void> setString(String key, String value) async {
    data[key] = value;
    writes[key] = (writes[key] ?? 0) + 1;
  }

  @override
  Future<void> clear() async => data.clear();
}

const _csv = 'Timestamp,Name,Capital of France,Why does ice float\n'
    '1/1,Ana Lopez,Paris,Ice is less dense than water because the molecules lock apart\n'
    '1/1,Ben Carter,Rome,It is lighter\n'
    '1/1,Cara Diaz,Paris,Water expands when it freezes so the solid sits on top\n';

ParsedSheet _sheet([String csv = _csv]) {
  final s = CsvImport.analyze(CsvImport.parse(csv));
  // Pin the column types so a test is never at the mercy of the guesser.
  s.questions.firstWhere((q) => q.header.startsWith('Capital'))
    ..kind = ImportColumnKind.multipleChoice
    ..correctAnswer = 'Paris'
    ..marks = 1;
  s.questions.firstWhere((q) => q.header.startsWith('Why'))
    ..kind = ImportColumnKind.shortAnswer
    ..marks = 2;
  return s;
}

/// Two written questions, for the cases about which question got paid for.
ParsedSheet _wide() {
  final s = CsvImport.analyze(CsvImport.parse('Name,Q1,Q2\n'
      'Ana,Because the cell wall holds it up,It travels as a wave\n'
      'Ben,It is soft,Light bends round the edge\n'));
  for (final q in s.questions) {
    q.kind = ImportColumnKind.shortAnswer;
    q.marks = 2;
  }
  return s;
}

/// Stands in for the AI and for the dashboard: records every paid call and
/// every result filed, so a test can assert on what a teacher would be
/// charged for and what would land under her students' names.
class _Run {
  final ImportCheckpoints checkpoints;
  final paid = <String>[];
  final prepared = <int>[];
  final filed = <int>[];
  final progress = <ImportProgress>[];
  bool stop = false;

  /// Stop the run once this many rows have been prepared (-1 = never).
  int stopAfterRows = -1;

  /// Stop the run once this many questions have been paid for (-1 = never).
  int stopAfterQuestions = -1;

  _Run(this.checkpoints);

  Future<ImportRunOutcome> call(ParsedSheet sheet) => runImport(
        sheet: sheet,
        questions: sheet.questions,
        importId: ImportCheckpoints.idFor(classId: 'c1', headers: sheet.headers),
        checkpoints: checkpoints,
        markQuestion: (q, rows) async {
          paid.add('${q.header}:${rows.join(",")}');
          if (stopAfterQuestions >= 0 && paid.length >= stopAfterQuestions) stop = true;
          return {for (final r in rows) r: ImportRowMark(q.marks, true, 'Good.')};
        },
        prepareRow: (row, marks) async {
          prepared.add(row);
          if (stopAfterRows >= 0 && prepared.length >= stopAfterRows) stop = true;
          return 'sub_$row';
        },
        fileRows: (rows) async => filed.addAll(rows),
        onProgress: progress.add,
        isStopped: () => stop,
      );
}

void main() {
  group('what makes two runs the same import', () {
    test('the same file into the same class is the same import', () {
      final a = ImportCheckpoints.idFor(classId: 'c1', headers: _sheet().headers);
      final b = ImportCheckpoints.idFor(classId: 'c1', headers: _sheet().headers);
      expect(a, b);
    });

    test('the same file into a different class is a different import', () {
      final a = ImportCheckpoints.idFor(classId: 'c1', headers: _sheet().headers);
      final b = ImportCheckpoints.idFor(classId: 'c2', headers: _sheet().headers);
      expect(a, isNot(b));
    });

    test('a different quiz is a different import', () {
      final a = ImportCheckpoints.idFor(classId: 'c1', headers: _sheet().headers);
      final b = ImportCheckpoints.idFor(classId: 'c1', headers: const ['Name', 'Photosynthesis']);
      expect(a, isNot(b));
    });

    test('two students who answered identically are still two students', () {
      // No name column, same answers: still two children, two results.
      final k1 = ImportCheckpoints.rowKeys([
        ['Paris', 'yes'],
        ['Paris', 'yes'],
      ]);
      expect(k1.first, isNot(k1.last));
    });

    test('a row keeps its key when later responses are appended', () {
      final first = ImportCheckpoints.rowKeys([
        ['Ana', 'Paris'],
        ['Ben', 'Rome'],
      ]);
      final later = ImportCheckpoints.rowKeys([
        ['Ana', 'Paris'],
        ['Ben', 'Rome'],
        ['Cara', 'Paris'],
      ]);
      expect(later.take(2), first);
    });
  });

  group('running the same import twice', () {
    test('the first run marks every question once and files every student', () async {
      final run = _Run(ImportCheckpoints(store: _MemoryStore()));
      final out = await run(_sheet());

      expect(run.paid, ['Why does ice float:0,1,2']);
      expect(run.filed, [0, 1, 2]);
      expect(out.saved, 3);
      expect(out.alreadySaved, 0);
    });

    test('the second run pays for nothing and files nobody twice', () async {
      final store = _MemoryStore();
      await _Run(ImportCheckpoints(store: store))(_sheet());

      final again = _Run(ImportCheckpoints(store: store));
      final out = await again(_sheet());

      expect(again.paid, isEmpty, reason: 'the marks were already bought');
      expect(again.filed, isEmpty, reason: 'these three already have a result');
      expect(out.saved, 0);
      expect(out.alreadySaved, 3);
    });

    test('re-exporting the sheet after three more replies marks only those three', () async {
      final store = _MemoryStore();
      await _Run(ImportCheckpoints(store: store))(_sheet());

      final fuller = _sheet('$_csv'
          '1/1,Dan Ellis,Paris,The solid form is less dense\n'
          '1/1,Eve Frost,London,Dunno\n');
      final again = _Run(ImportCheckpoints(store: store));
      final out = await again(fuller);

      expect(again.paid, ['Why does ice float:3,4']);
      expect(again.filed, [3, 4]);
      expect(out.saved, 2);
      expect(out.alreadySaved, 3);
    });

    test('changing one question buys that question again, and leaves the other alone', () async {
      final store = _MemoryStore();
      // Stopped before anything is filed, so the bought marks are all the
      // checkpoint is holding.
      final run = _Run(ImportCheckpoints(store: store))..stopAfterQuestions = 2;
      await run(_wide());
      expect(run.paid, ['Q1:0,1', 'Q2:0,1']);

      // The teacher decides the second one is worth five, not two.
      final second = _wide();
      second.questions.firstWhere((q) => q.header == 'Q2').marks = 5;
      final again = _Run(ImportCheckpoints(store: store));
      await again(second);

      expect(again.paid, ['Q2:0,1']);
    });
  });

  group('a run that was stopped half way', () {
    test('files the students it had ready and remembers them', () async {
      final store = _MemoryStore();
      final run = _Run(ImportCheckpoints(store: store))..stopAfterRows = 2;
      final out = await run(_sheet());

      expect(out.stopped, isTrue);
      expect(run.filed, [0, 1], reason: 'two were ready, so two are on the dashboard');
      expect(out.saved, 2);
    });

    test('resuming files only the rest, and pays nothing more', () async {
      final store = _MemoryStore();
      await (_Run(ImportCheckpoints(store: store))..stopAfterRows = 2)(_sheet());

      final resumed = _Run(ImportCheckpoints(store: store));
      final out = await resumed(_sheet());

      expect(resumed.paid, isEmpty, reason: 'those marks are already bought and kept');
      expect(resumed.filed, [2]);
      expect(out.saved, 1);
      expect(out.alreadySaved, 2);
    });

    test('marks bought before the stop are not bought again', () async {
      final store = _MemoryStore();
      // Stops the moment the one written question comes back, before saving.
      final run = _Run(ImportCheckpoints(store: store))..stopAfterQuestions = 1;
      await run(_sheet());
      expect(run.paid.length, 1);
      expect(run.filed, isEmpty);

      final resumed = _Run(ImportCheckpoints(store: store));
      await resumed(_sheet());
      expect(resumed.paid, isEmpty);
      expect(resumed.filed, [0, 1, 2]);
    });
  });

  group('the count on screen', () {
    test('counts questions from one while marking', () async {
      final run = _Run(ImportCheckpoints(store: _MemoryStore()));
      await run(_wide());

      final marking = run.progress.where((p) => p.phase == ImportPhase.marking).toList();
      expect(marking.map((p) => '${p.done}/${p.total}'), ['1/2', '2/2']);
      expect(marking.map((p) => p.question), ['Q1', 'Q2']);
    });

    test('counts the students it is actually saving, not the whole sheet', () async {
      final store = _MemoryStore();
      await (_Run(ImportCheckpoints(store: store))..stopAfterRows = 2)(_sheet());

      final resumed = _Run(ImportCheckpoints(store: store));
      await resumed(_sheet());

      final saving = resumed.progress.where((p) => p.phase == ImportPhase.saving).toList();
      // One student left, so it must say one — not "3 of 3" for work that is
      // already done, which is the lie that makes a teacher force-quit.
      expect(saving.map((p) => '${p.done}/${p.total}'), ['1/1']);
    });

    test('never sits on nothing: the saving phase is counted, not a bare label', () async {
      final run = _Run(ImportCheckpoints(store: _MemoryStore()));
      await run(_sheet());

      final saving = run.progress.where((p) => p.phase == ImportPhase.saving).toList();
      expect(saving.map((p) => '${p.done}/${p.total}'), ['1/3', '2/3', '3/3']);
    });
  });

  group('the checkpoint itself', () {
    test('a finished import keeps who was marked but drops the bought marks', () async {
      final store = _MemoryStore();
      final checkpoints = ImportCheckpoints(store: store);
      await _Run(checkpoints)(_sheet());

      final id = ImportCheckpoints.idFor(classId: 'c1', headers: _sheet().headers);
      final cp = await checkpoints.load(id);
      expect(cp.filed.length, 3);
      expect(cp.marks, isEmpty, reason: 'a finished import needs no marks kept on the phone');
    });

    test('forgetting an import lets a teacher deliberately mark it again', () async {
      final store = _MemoryStore();
      final checkpoints = ImportCheckpoints(store: store);
      await _Run(checkpoints)(_sheet());
      await checkpoints.forget(ImportCheckpoints.idFor(classId: 'c1', headers: _sheet().headers));

      final again = _Run(checkpoints);
      await again(_sheet());
      expect(again.filed, [0, 1, 2]);
    });

    test('old imports are dropped so a term of quizzes cannot fill the phone', () async {
      final store = _MemoryStore();
      final checkpoints = ImportCheckpoints(store: store);
      for (var i = 0; i < ImportCheckpoints.remembered + 5; i++) {
        await checkpoints.save(
          'import_$i',
          ImportCheckpoint(filed: {'r': 'sub_$i'}, marks: const {}),
        );
      }
      expect((await checkpoints.load('import_0')).filed, isEmpty);
      expect((await checkpoints.load('import_${ImportCheckpoints.remembered + 4}')).filed, isNotEmpty);
    });
  });

  group('one bad row', () {
    test('does not cost the rest of the class their marks', () async {
      final store = _MemoryStore();
      final checkpoints = ImportCheckpoints(store: store);
      final filed = <int>[];
      final out = await runImport(
        sheet: _sheet(),
        questions: _sheet().questions,
        importId: 'i1',
        checkpoints: checkpoints,
        markQuestion: (q, rows) async => {for (final r in rows) r: const ImportRowMark(1, true, '')},
        prepareRow: (row, marks) async {
          if (row == 1) throw Exception('roster write failed');
          return 'sub_$row';
        },
        fileRows: (rows) async => filed.addAll(rows),
      );

      expect(filed, [0, 2]);
      expect(out.saved, 2);
      expect(out.failed, 1);
    });
  });
}
