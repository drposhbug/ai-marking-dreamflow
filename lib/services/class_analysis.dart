import 'package:marking_prokect_v2/models/submission.dart';

/// One class set: the papers a teacher marked together.
///
/// Nothing records a "batch id" on a marked paper, and adding one would
/// mean a schema change for something the timestamps already say: a class
/// set lands as a run of papers for the same class and the same test,
/// minutes apart. Two tests marked a week apart are two sets; two subjects
/// marked the same afternoon are two sets.
class MarkedSet {
  final String classId;
  final String subject;
  final String presetId;

  /// When the last paper in the set finished — what a teacher recognises
  /// the set by ("the one I did on Friday").
  final DateTime markedAt;

  /// Marking order, oldest first.
  final List<Submission> papers;

  const MarkedSet({
    required this.classId,
    required this.subject,
    required this.presetId,
    required this.markedAt,
    required this.papers,
  });

  /// Stable across rebuilds so a screen can remember which set was open.
  String get id => papers.isEmpty ? '$classId|$presetId' : papers.last.id;
}

/// How one question went across the whole class.
///
/// Every count here is deliberately separate rather than folded into one
/// "wrong" number, because the three ways a paper can fail to show full
/// marks mean three different things to a teacher: a mark was lost, the
/// marker refused to judge it, or the question never appeared on that
/// paper at all.
class QuestionInsight {
  /// As the marker wrote it — "Q4", "Thinking 2", "Grammar".
  final String label;

  /// Ontario's Knowledge / Thinking / Communication / Application category,
  /// when the label names one. Null rather than a guess.
  final String? category;

  /// Papers in the set, including those this question never appeared on.
  final int papers;

  /// Papers where this question carried a real mark.
  final int attempted;

  /// Of those, papers that scored every available mark.
  final int fullMarks;

  /// Papers that scored something but not everything.
  final int partial;

  /// Papers flagged "requires teacher marking" — excluded from every
  /// percentage below. A question the AI refused to judge is not a question
  /// the class got wrong.
  final int teacherMarked;

  /// Papers where this question never appeared — a skipped last page, a
  /// photo that cut off. Not counted as wrong.
  final int notSeen;

  /// What the question is out of, as printed on most of the papers.
  final double outOf;

  /// Mean marks earned, out of [outOf].
  final double averageMark;

  /// Mean of each paper's percentage on this question.
  final int averagePercent;

  /// Share of papers that scored every mark.
  final int percentCorrect;

  /// The marker note that came up most often on papers that lost marks,
  /// in the wording of the first paper it appeared on.
  final String commonError;
  final int commonErrorCount;

  /// Multiple choice: the option position wrong answers landed on most.
  final int? commonWrongOption;
  final int commonWrongOptionCount;

  /// Who lost marks here and who didn't, by student id (or by submission
  /// id for a paper not yet linked to a student).
  final List<String> missedBy;
  final List<String> gotBy;

  const QuestionInsight({
    required this.label,
    required this.category,
    required this.papers,
    required this.attempted,
    required this.fullMarks,
    required this.partial,
    required this.teacherMarked,
    required this.notSeen,
    required this.outOf,
    required this.averageMark,
    required this.averagePercent,
    required this.percentCorrect,
    required this.commonError,
    required this.commonErrorCount,
    required this.commonWrongOption,
    required this.commonWrongOptionCount,
    required this.missedBy,
    required this.gotBy,
  });

  /// Whether any paper carried a mark for this question. False for a
  /// question every paper left to the teacher — where a percentage would
  /// be a number invented out of nothing.
  bool get hasMarks => attempted > 0;

  /// Papers that lost at least one mark.
  int get missed => attempted - fullMarks;

  /// The one line a teacher reads under the question on the summary.
  String get whatWentWrong {
    if (!hasMarks) {
      return teacherMarked > 0
          ? 'Every paper here needs teacher marking.'
          : 'No marks recorded for this question.';
    }
    if (commonErrorCount >= 2) return commonError;
    if (commonWrongOption != null) return 'Most wrong answers picked option $commonWrongOption.';
    if (commonError.isNotEmpty) return commonError;
    if (missed == 0) return 'The whole class had this one.';
    return 'Marks came off across the class with no single repeated slip.';
  }

  /// A short paragraph the teacher can use or ignore.
  ///
  /// Written here rather than asked for, on purpose. The teacher is owed a
  /// suggestion grounded in the numbers on this page and nothing else, and
  /// an AI call per weak question would put a price on opening a screen
  /// that is meant to be free to look at.
  ///
  /// Empty when there is nothing to reteach — a question the class had, or
  /// one only the teacher can mark.
  String get reteach {
    if (!hasMarks || missed == 0) return '';
    final parts = <String>[];
    final blank = attempted - fullMarks - partial;
    final wipeout = missed == attempted && averagePercent <= 10;

    if (wipeout) {
      parts.add('Nobody got $label: all $attempted paper${attempted == 1 ? '' : 's'} lost every mark.');
    } else {
      parts.add('$missed of $attempted paper${attempted == 1 ? '' : 's'} lost marks on $label, averaging $averagePercent%.');
    }

    // Part marks everywhere is a different lesson from blanks everywhere:
    // one class knows the method and stops short, the other never started.
    if (!wipeout && partial * 2 >= attempted && averagePercent >= 40) {
      parts.add('The method is mostly there — marks come off at the finish, not the setup.');
    } else if (!wipeout && blank * 2 >= attempted && averagePercent < 40) {
      parts.add('Most of them had no way into it at all.');
    }

    if (commonErrorCount >= 2) {
      parts.add('The same slip came up on $commonErrorCount papers: "$commonError".');
    } else if (commonWrongOptionCount >= 2) {
      parts.add('$commonWrongOptionCount of the wrong answers went to option $commonWrongOption — that distractor is doing the teaching.');
    }

    final missRate = attempted == 0 ? 0.0 : missed / attempted;
    if (wipeout) {
      parts.add('Before reteaching, read the question back to yourself: when nobody scores, the wording or the marking key is worth ruling out first.');
    } else if (missRate >= 0.5) {
      parts.add('Worth a full reteach: work one example at the board, stop at the step they lost, then let them complete it in pairs.');
    } else if (missRate >= 0.25) {
      parts.add('Split the room: pair someone who had it with someone who didn\'t and have them talk the step through.');
    } else {
      parts.add('Small enough for a pull-aside — $missed student${missed == 1 ? '' : 's'}, five minutes while the rest start the next task.');
    }

    final tail = _categoryAdvice[category];
    if (tail != null) parts.add(tail);

    return parts.join(' ');
  }

  static const Map<String, String> _categoryAdvice = {
    'Knowledge': 'Knowledge marks come back fastest from a short recall drill at the start of next lesson.',
    'Thinking': 'Thinking marks need the reasoning said out loud, not another worked answer.',
    'Communication': 'Communication marks come back by putting a full-credit answer beside a bare one and asking what the difference is worth.',
    'Application': 'Application marks come back from a second context, not a second copy of the same question.',
  };
}

/// The whole class set, reduced to what a teacher can act on.
class ClassInsight {
  final int papers;

  /// Worst first — the order a teacher reads this in.
  final List<QuestionInsight> questions;

  /// Mean of each paper's overall percentage. Null when nothing in the set
  /// carried a mark, because an average of no marks is 0%, and 0% reads as
  /// a class that failed.
  final int? averagePercent;

  /// Students in the set, by the same key [QuestionInsight.missedBy] uses.
  final List<String> studentKeys;

  const ClassInsight({
    required this.papers,
    required this.questions,
    required this.averagePercent,
    required this.studentKeys,
  });

  /// Questions worth the teacher's next ten minutes.
  List<QuestionInsight> get weakest => questions
      .where((q) => q.hasMarks && q.missed > 0 && q.averagePercent < ClassAnalysis.weakBelowPercent)
      .toList(growable: false);

  /// Questions that need marks entering by hand before the percentages
  /// above are the whole story.
  List<QuestionInsight> get awaitingTeacher =>
      questions.where((q) => q.teacherMarked > 0).toList(growable: false);
}

/// What one student's paper looks like against the rest of the class.
class StudentGaps {
  final String studentKey;

  /// Questions this student lost marks on that most of the class got.
  final List<QuestionInsight> missedWhatClassGot;

  /// Questions this student got that most of the class missed.
  final List<QuestionInsight> gotWhatClassMissed;

  const StudentGaps({
    required this.studentKey,
    required this.missedWhatClassGot,
    required this.gotWhatClassMissed,
  });

  bool get isEmpty => missedWhatClassGot.isEmpty && gotWhatClassMissed.isEmpty;
}

/// Turns a marked class set into what the CLASS got wrong.
///
/// A teacher who has just marked thirty papers already knows each student's
/// score — the app handed them over one at a time. What they cannot get
/// from thirty result screens is the thing that decides Monday's lesson:
/// which question the room fell over on, and why.
///
/// Everything here is derived from marks that already exist. No new tables,
/// and no marking call — the per-question detail came back with each paper
/// and has been sitting in the saved result ever since. Opening this screen
/// costs nothing, which is what makes it safe to open every time.
class ClassAnalysis {
  /// Papers this far apart were two sittings, not one class set.
  static const Duration setGap = Duration(hours: 6);

  /// A question below this is worth reteaching.
  static const int weakBelowPercent = 70;

  /// What counts as "most of the class" for the per-student comparison.
  static const int mostOfClassPercent = 60;

  static const List<String> ktcaCategories = ['Knowledge', 'Thinking', 'Communication', 'Application'];

  /// The class sets marked for [classId], newest first.
  ///
  /// Papers that could not be graded are left out: their score is a
  /// placeholder, and a placeholder averaged into a class statistic is a
  /// bad photograph turned into a bad lesson plan.
  static List<MarkedSet> setsFor({
    required List<Submission> submissions,
    required String classId,
    Duration apart = setGap,
  }) {
    final mine = submissions
        .where((s) => s.classId == classId && s.triageStatus != TriageStatus.unableToGrade)
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    // Same class, same test, same marking style — then split wherever the
    // gap says the teacher put the stack down and came back another day.
    final byTest = <String, List<Submission>>{};
    for (final s in mine) {
      (byTest['${s.presetId}|${s.subject}|${s.gradingMode.name}'] ??= <Submission>[]).add(s);
    }

    final sets = <MarkedSet>[];
    for (final run in byTest.values) {
      var current = <Submission>[];
      for (final s in run) {
        if (current.isNotEmpty && s.createdAt.difference(current.last.createdAt) > apart) {
          sets.add(_setOf(current));
          current = <Submission>[];
        }
        current.add(s);
      }
      if (current.isNotEmpty) sets.add(_setOf(current));
    }

    sets.sort((a, b) => b.markedAt.compareTo(a.markedAt));
    return sets;
  }

  static MarkedSet _setOf(List<Submission> papers) => MarkedSet(
        classId: papers.first.classId,
        subject: papers.first.subject,
        presetId: papers.first.presetId,
        markedAt: papers.last.createdAt,
        papers: List.unmodifiable(papers),
      );

  /// How a paper is identified across the analysis. The student when the
  /// paper is linked to one, the paper itself when it isn't — an unlinked
  /// paper still counts towards the class, it just can't be looked up.
  static String keyOf(Submission s) => s.studentId.isEmpty ? s.id : s.studentId;

  /// Aggregates a class set into per-question results.
  static ClassInsight analyse(List<Submission> papers) {
    if (papers.isEmpty) {
      return const ClassInsight(papers: 0, questions: [], averagePercent: null, studentKeys: []);
    }

    final keys = papers.map(keyOf).toList(growable: false);
    final tallies = <String, _Tally>{};
    var sawQuestions = false;

    for (final paper in papers) {
      final key = keyOf(paper);
      final result = paper.resultJson ?? const <String, dynamic>{};
      for (final raw in (result['annotations'] as List? ?? const []).whereType<Map>()) {
        final a = raw.cast<String, dynamic>();
        final label = (a['questionLabel'] ?? '').toString().trim();
        if (label.isEmpty) continue;

        final earnedText = (a['earnedMark'] ?? '').toString().trim();
        final outText = (a['outOfMark'] ?? '').toString().trim();

        // Writing error marks carry no marks of their own — the deduction
        // happens once in the section score. Counted as questions they
        // would fill the top of the ranking with 0% rows that are really
        // one apostrophe each.
        if (earnedText.isEmpty && outText.isEmpty) continue;

        sawQuestions = true;
        final tally = tallies.putIfAbsent(_key(label), () => _Tally(papers.length))..sawLabel(label);

        // "?" is the marker refusing to judge, not the class getting it
        // wrong. It stays out of every percentage.
        if (earnedText == '?') {
          tally.teacherMarked++;
          continue;
        }

        var out = _num(outText) ?? 0;
        var earned = _num(earnedText) ?? 0;
        if (out <= 0) {
          // No printed marks on this question — fall back to the marker's
          // right/wrong call rather than dropping the question.
          out = 1;
          earned = a['correct'] == true ? 1 : 0;
        }
        tally.add(
          key: key,
          earned: earned.clamp(0, out).toDouble(),
          outOf: out,
          note: (a['feedback'] ?? '').toString().trim(),
          chosenOption: (a['chosenOption'] as num?)?.toInt() ?? 0,
        );
      }
    }

    // An essay set has no numbered questions — the marks live in the rubric
    // sections instead. Ranking those is the same question a teacher is
    // asking, so it beats showing them an empty screen.
    if (!sawQuestions) {
      for (final paper in papers) {
        final key = keyOf(paper);
        final result = paper.resultJson ?? const <String, dynamic>{};
        for (final raw in (result['criteriaBreakdown'] as List? ?? const []).whereType<Map>()) {
          final c = raw.cast<String, dynamic>();
          final name = (c['name'] ?? '').toString().trim();
          final max = (c['maxScore'] as num?)?.toDouble() ?? 0;
          if (name.isEmpty || max <= 0) continue;
          final tally = tallies.putIfAbsent(_key(name), () => _Tally(papers.length))..sawLabel(name);
          tally.add(
            key: key,
            earned: ((c['score'] as num?)?.toDouble() ?? 0).clamp(0, max).toDouble(),
            outOf: max,
            note: (c['feedback'] ?? '').toString().trim(),
            chosenOption: 0,
          );
        }
      }
    }

    final questions = tallies.values.map((t) => t.build()).toList()
      ..sort((a, b) {
        // Worst first. A question nobody's marks touched sits at the end —
        // it isn't better or worse, there is simply nothing to rank it by.
        if (a.hasMarks != b.hasMarks) return a.hasMarks ? -1 : 1;
        final byScore = a.averagePercent.compareTo(b.averagePercent);
        if (byScore != 0) return byScore;
        final byCount = b.attempted.compareTo(a.attempted);
        if (byCount != 0) return byCount;
        return _labelOrder(a.label, b.label);
      });

    final scored = papers.where((p) => p.maxScore > 0).toList(growable: false);
    final average = scored.isEmpty
        ? null
        : (scored.map((p) => p.score / p.maxScore * 100).reduce((a, b) => a + b) / scored.length).round();

    return ClassInsight(
      papers: papers.length,
      questions: List.unmodifiable(questions),
      averagePercent: average,
      studentKeys: List.unmodifiable(keys),
    );
  }

  /// Where one student sits against the rest of the class.
  ///
  /// Only questions the student's own paper actually carried a mark for —
  /// a question that never appeared on their pages says nothing about them.
  static StudentGaps gapsFor(ClassInsight insight, String studentKey) {
    final missed = <QuestionInsight>[];
    final got = <QuestionInsight>[];
    for (final q in insight.questions) {
      if (!q.hasMarks) continue;
      if (q.missedBy.contains(studentKey)) {
        if (q.percentCorrect >= mostOfClassPercent) missed.add(q);
      } else if (q.gotBy.contains(studentKey)) {
        if (q.percentCorrect <= 100 - mostOfClassPercent) got.add(q);
      }
    }
    return StudentGaps(
      studentKey: studentKey,
      missedWhatClassGot: List.unmodifiable(missed),
      gotWhatClassMissed: List.unmodifiable(got),
    );
  }

  /// The KTCA category a label names, or null.
  ///
  /// Marking writes "Knowledge 1" / "Thinking 2" on every annotation inside
  /// an Ontario category section, so the category is already on the page —
  /// it never has to be inferred from the wording of the question.
  static String? categoryOf(String label) {
    final l = label.trim().toLowerCase();
    for (final c in ktcaCategories) {
      final name = c.toLowerCase();
      if (l == name || l.startsWith('$name ')) return c;
    }
    return null;
  }

  /// "Q3", "Question 3" and "q 3" are one question. A teacher whose class
  /// analysis lists the same question three times will not trust the rest
  /// of the numbers on the screen.
  static String _key(String label) {
    final flat = label.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
    return flat.replaceFirst(RegExp(r'^(?:question|q)\s*(?=\d)'), '');
  }

  static double? _num(String s) => double.tryParse(s.replaceAll(RegExp(r'[^0-9.]'), ''));

  /// Paper order for questions that tie: Q2 before Q10, Thinking before Q2
  /// only if that's where the alphabet puts it.
  static int _labelOrder(String a, String b) {
    final na = _leadingNumber(a);
    final nb = _leadingNumber(b);
    if (na != null && nb != null && na != nb) return na.compareTo(nb);
    return a.toLowerCase().compareTo(b.toLowerCase());
  }

  static int? _leadingNumber(String label) {
    final m = RegExp(r'(\d+)').firstMatch(label);
    return m == null ? null : int.tryParse(m.group(1)!);
  }
}

/// One question's running totals while the set is being walked.
class _Tally {
  _Tally(this.papers);

  final int papers;
  final Map<String, int> _labels = {};
  final List<String> _labelOrder = [];
  final List<double> _percents = [];
  final List<double> _earned = [];
  final Map<double, int> _outOfSeen = {};
  final Map<String, _Note> _notes = {};
  final Map<int, int> _wrongOptions = {};
  final List<String> missedBy = [];
  final List<String> gotBy = [];
  int fullMarks = 0;
  int partial = 0;
  int teacherMarked = 0;

  void sawLabel(String label) {
    if (!_labels.containsKey(label)) _labelOrder.add(label);
    _labels[label] = (_labels[label] ?? 0) + 1;
  }

  void add({
    required String key,
    required double earned,
    required double outOf,
    required String note,
    required int chosenOption,
  }) {
    _percents.add(earned / outOf * 100);
    _earned.add(earned);
    _outOfSeen[outOf] = (_outOfSeen[outOf] ?? 0) + 1;

    final full = earned >= outOf;
    if (full) {
      fullMarks++;
      gotBy.add(key);
      return;
    }
    if (earned > 0) partial++;
    missedBy.add(key);

    if (note.isNotEmpty) {
      final n = _notes.putIfAbsent(_noteKey(note), () => _Note(note));
      n.count++;
    }
    if (chosenOption > 0) {
      _wrongOptions[chosenOption] = (_wrongOptions[chosenOption] ?? 0) + 1;
    }
  }

  QuestionInsight build() {
    final label = _mostCommon(_labels, _labelOrder) ?? '';
    final attempted = _percents.length;
    final outOf = _outOfSeen.isEmpty
        ? 0.0
        : (_outOfSeen.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first.key;

    final topNote = _notes.values.isEmpty
        ? null
        : (_notes.values.toList()..sort((a, b) => b.count.compareTo(a.count))).first;
    final topOption = _wrongOptions.isEmpty
        ? null
        : (_wrongOptions.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first;

    return QuestionInsight(
      label: label,
      category: ClassAnalysis.categoryOf(label),
      papers: papers,
      attempted: attempted,
      fullMarks: fullMarks,
      partial: partial,
      teacherMarked: teacherMarked,
      notSeen: (papers - attempted - teacherMarked).clamp(0, papers),
      outOf: outOf,
      averageMark: attempted == 0 ? 0 : _earned.reduce((a, b) => a + b) / attempted,
      averagePercent: attempted == 0 ? 0 : (_percents.reduce((a, b) => a + b) / attempted).round(),
      percentCorrect: attempted == 0 ? 0 : (fullMarks / attempted * 100).round(),
      commonError: topNote?.text ?? '',
      commonErrorCount: topNote?.count ?? 0,
      commonWrongOption: topOption?.key,
      commonWrongOptionCount: topOption?.value ?? 0,
      missedBy: List.unmodifiable(missedBy),
      gotBy: List.unmodifiable(gotBy),
    );
  }

  /// Most frequent, first seen winning a tie — so the label a teacher sees
  /// is the one written on most of the papers, not whichever hashed first.
  static String? _mostCommon(Map<String, int> counts, List<String> order) {
    String? best;
    var bestCount = 0;
    for (final label in order) {
      final n = counts[label] ?? 0;
      if (n > bestCount) {
        best = label;
        bestCount = n;
      }
    }
    return best;
  }

  /// "Forgot to convert cm to m" and "forgot to convert cm to m." are the
  /// same slip. The wording the teacher sees stays as the marker wrote it.
  static String _noteKey(String note) => note
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim();
}

class _Note {
  _Note(this.text);
  final String text;
  int count = 0;
}
