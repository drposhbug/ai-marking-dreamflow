import 'package:flutter_test/flutter_test.dart';
import 'package:marking_prokect_v2/services/gradebook_export.dart';

MarkRow row(String name, double score, {List<WrongAnswer> wrong = const [], List<String> choices = const [], List<String> flags = const []}) =>
    MarkRow(
      studentName: name,
      studentCode: '',
      score: score,
      maxScore: 50,
      markedAt: DateTime(2026, 10, 7),
      feedback: '',
      wrong: wrong,
      wrongChoices: choices,
      flags: flags,
    );

/// A results sheet for a multiple-choice test that sorts and filters by
/// percentage, the way a teacher would make one by hand.
void main() {
  test('best first, with percent and percentile as plain numbers and a band', () {
    final lines = GradebookExport.resultsCsv([row('Raymond Lu', 49), row('Ryan Y', 50), row('Alan Xiao', 50), row('Owen', 40)])
        .trim()
        .split('\n');
    expect(lines[0], 'Student,Score,Percent,Percentile,Band,Questions wrong,Notes');
    expect(lines[1], 'Alan Xiao,50,100,75,90–100,—,'); // 2 below, 2 tied: (2 + 1) / 4
    expect(lines[2], 'Ryan Y,50,100,75,90–100,—,');
    expect(lines[3], 'Raymond Lu,49,98,38,90–100,—,');
    expect(lines[4], 'Owen,40,80,13,80–89,—,');
  });

  test('bands are 10 points wide, with everything under 50 together', () {
    expect([100, 90, 89, 72, 50, 49, 0].map(GradebookExport.band), ['90–100', '90–100', '80–89', '70–79', '50–59', 'Below 50', 'Below 50']);
  });

  test('blanks and double marks are called out, flags become notes', () {
    final csv = GradebookExport.resultsCsv([
      row('Liam Parsotam', 47,
          wrong: const [WrongAnswer('1'), WrongAnswer('32', 'blank'), WrongAnswer('41')], flags: const ['Student # hard to read']),
    ]);
    expect(csv, contains('"1, 32 (blank), 41",Student # hard to read'));
  });

  test('the same wrong answers on 3+ questions are flagged both ways', () {
    const choices = ['1:2', '12:4', '38:1', '47:3', '7:2'];
    final csv = GradebookExport.resultsCsv([
      row('Sophie Zarobyan', 45, choices: choices),
      row('Clinton Kwong', 45, choices: choices),
      row('Arian Kasen Chi', 45, choices: const ['1:3', '4:1', '32:2']),
    ]);
    expect(csv, contains('Same wrong answers as Sophie Zarobyan'));
    expect(csv, contains('Same wrong answers as Clinton Kwong'));
    expect(RegExp('Same wrong').allMatches(csv).length, 2);
  });

  test('wrong answers come from the saved marking result', () {
    final (wrong, choices) = GradebookExport.wrongAnswers({
      'annotations': [
        {'questionLabel': 'Q12', 'correct': false, 'chosenOption': 3, 'feedback': ''},
        {'questionLabel': 'Q2', 'correct': true, 'chosenOption': 1},
        {'questionLabel': 'Q36', 'correct': false, 'chosenOption': 0, 'feedback': 'More than one bubble filled.'},
        {'questionLabel': 'Q19', 'correct': false, 'chosenOption': 0, 'feedback': 'No answer given.'},
        // A Google Form answer: no bubble to read, and not blank either.
        {'questionLabel': 'Q4', 'correct': false, 'feedback': 'Correct answer: B'},
      ],
    });
    expect(wrong.map((w) => '$w'), ['4', '12', '19 (blank)', '36 (double)']);
    expect(choices, ['12:3']);
  });
}
