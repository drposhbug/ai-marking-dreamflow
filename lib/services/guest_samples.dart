import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:marking_prokect_v2/models/grading_preset.dart';
import 'package:marking_prokect_v2/services/ai_grading_service.dart';
import 'package:marking_prokect_v2/services/classes_service.dart';
import 'package:marking_prokect_v2/services/grading_queue_service.dart';
import 'package:marking_prokect_v2/services/local_store.dart';
import 'package:marking_prokect_v2/services/students_service.dart';
import 'package:marking_prokect_v2/services/submissions_service.dart';

/// One sample paper: who wrote it, what it is, and the bundled page.
class GuestSample {
  final String student;
  final String studentCode;
  final String subject;
  final int gradeLevel;
  final String asset;
  const GuestSample(this.student, this.studentCode, this.subject, this.gradeLevel, this.asset);
}

/// Fictional students, each paper with a couple of real mistakes in it.
const guestSamples = [
  GuestSample('Jordan Patel', 'S-1001', 'Math', 9, 'assets/samples/grade9-math-quiz.png'),
  GuestSample('Maya Chen', 'S-1002', 'History', 10, 'assets/samples/grade10-history.png'),
  GuestSample('Alex Morgan', 'S-1003', 'Chemistry', 11, 'assets/samples/grade11-chemistry.png'),
];

/// A guest arrives to an empty app, and an empty app shows nothing of what
/// it does. So the first time a guest account opens the home screen it gets
/// real work in it: a sample class with three students, and their three
/// papers marked through the ordinary queue. Nothing here is faked — the
/// results come back from the real marker, and marking each keyless paper
/// leaves a learned answer key behind, so Recent submissions, Classes and
/// Answer keys all fill the way they would for a teacher.
///
/// It costs the guest's own free-trial credit (about a third of it), which
/// is the honest price of three real marks and still leaves room to try
/// their own paper. Runs once per guest account.
class GuestSamples {
  static String _doneKey(String teacherId) => 'guest_samples_seeded.$teacherId';

  static Future<bool> alreadySeeded(String teacherId) async =>
      (await const LocalStore().getString(_doneKey(teacherId))) == '1';

  static Future<void> seed({
    required String teacherId,
    required ClassesService classes,
    required StudentsService students,
    required SubmissionsService submissions,
    required GradingQueueService queue,
  }) async {
    if (await alreadySeeded(teacherId)) return;
    // Marked before the work starts, so a second home-screen build while
    // the first is still running cannot queue the papers twice.
    await const LocalStore().setString(_doneKey(teacherId), '1');
    try {
      final cls = await classes.create(
        teacherId: teacherId,
        name: 'Sample class',
        subject: 'Mixed',
        period: 'Period 2',
      );
      for (final s in guestSamples) {
        final student = await students.create(
          teacherId: teacherId,
          classId: cls.id,
          name: s.student,
          studentId: s.studentCode,
          notes: 'Sample student (fictional)',
        );
        final bytes = (await rootBundle.load(s.asset)).buffer.asUint8List();
        queue.enqueue(
          req: AiGradeRequest(
            teacherId: teacherId,
            studentId: student.id,
            classId: cls.id,
            presetId: GradingPreset.builtInTestId,
            subject: s.subject,
            mode: GradingMode.testQuiz,
            criteria: const {},
            harshness: 5,
            notes: null,
            overrideUsed: false,
            imageBytes: bytes,
            pageImages: [bytes],
            studentName: s.student,
            studentGrade: null,
            gradeLevel: s.gradeLevel,
            region: 'ca-on',
          ),
          pages: [bytes],
          students: students,
          submissions: submissions,
          label: s.student,
          notifyLearnedKey: false,
        );
      }
    } catch (e) {
      debugPrint('GuestSamples.seed failed: $e');
    }
  }
}
