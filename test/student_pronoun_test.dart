import 'package:flutter_test/flutter_test.dart';
import 'package:marking_prokect_v2/models/student.dart';

/// The pronoun a teacher picks for a report comment lives on the student,
/// and students sync as a whole JSON blob. Both directions matter: a new
/// field must survive the round trip, and a student saved before the field
/// existed must still load.
void main() {
  Student make({String? pronoun}) => Student(
        id: 's1',
        teacherId: 't1',
        classId: 'c1',
        name: 'Ana Ruiz',
        studentId: '2201',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
        pronoun: pronoun,
      );

  test('a pronoun survives the round trip to storage', () {
    final back = Student.fromJson(make(pronoun: 'she').toJson());
    expect(back.pronoun, 'she');
  });

  test('a student saved before the field existed still loads', () {
    final legacy = make().toJson()..remove('pronoun');
    expect(Student.fromJson(legacy).pronoun, isNull);
  });

  test('no pronoun set is not a guess — it stays null', () {
    // The screen turns null into they/them. The record must not claim the
    // teacher chose something they never chose.
    expect(Student.fromJson(make().toJson()).pronoun, isNull);
  });

  test('copyWith keeps the pronoun when other fields change', () {
    expect(make(pronoun: 'he').copyWith(name: 'Ana R').pronoun, 'he');
  });
}
