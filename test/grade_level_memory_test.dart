import 'package:flutter_test/flutter_test.dart';
import 'package:marking_prokect_v2/app/app_state.dart';
import 'package:marking_prokect_v2/services/local_store.dart';

class _MemoryStore implements LocalStore {
  final Map<String, String> values = {};

  @override
  Future<String?> getString(String key) async => values[key];

  @override
  Future<void> setString(String key, String value) async => values[key] = value;

  @override
  Future<void> clear() async => values.clear();
}

/// The grade a teacher picks on the slider sticks — across papers and
/// across sign-ins — unless the paper belongs to a class with its own grade.
void main() {
  test('a picked grade is remembered at the next sign-in', () async {
    final store = _MemoryStore();
    final first = AppState(store: store);
    await first.initForUser(teacherId: 't1');
    await first.rememberGradeLevel(12);

    final next = AppState(store: store);
    await next.initForUser(teacherId: 't1');
    expect(next.draft.gradeLevel, 12);
  });

  test('another account does not inherit it', () async {
    final store = _MemoryStore();
    final a = AppState(store: store);
    await a.initForUser(teacherId: 't1');
    await a.rememberGradeLevel(12);

    final b = AppState(store: store);
    await b.initForUser(teacherId: 't2');
    expect(b.draft.gradeLevel, isNot(12));
  });

  test("a sample paper's grade is for that paper only; a class keeps its own", () async {
    final app = AppState(store: _MemoryStore());
    await app.initForUser(teacherId: 't1');
    await app.rememberGradeLevel(12);

    app.setGradeLevel(9); // e.g. the Grade 9 sample paper
    app.prepareNextScan();
    expect(app.draft.gradeLevel, 12);

    app.setStudentClassPreset(classId: 'c1');
    app.setGradeLevel(7); // the class's own grade
    app.prepareNextScan();
    expect(app.draft.gradeLevel, 7);
  });
}
