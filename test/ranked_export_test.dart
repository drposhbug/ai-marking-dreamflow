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

/// A ranked results sheet for a multiple-choice contest, the way a teacher
/// would make one by hand.
void main() {
  test('ties share a rank and the next rank skips', () {
    final lines = GradebookExport.rankedCsv([row('Ryan Y', 50), row('Alan Xiao', 50), row('Raymond Lu', 49)]).trim().split('\n');
    expect(lines[0], 'Rank,Student,Score,Percent,Questions wrong,Notes');
    expect(lines[1], '1,Alan Xiao,50,100%,—,');
    expect(lines[2], '1,Ryan Y,50,100%,—,');
    expect(lines[3], startsWith('3,Raymond Lu,49,98%'));
  });

  test('blanks and double marks are called out, flags become notes', () {
    final csv = GradebookExport.rankedCsv([
      row('Liam Parsotam', 47,
          wrong: const [WrongAnswer('1'), WrongAnswer('32', 'blank'), WrongAnswer('41')], flags: const ['Student # hard to read']),
    ]);
    expect(csv, contains('"1, 32 (blank), 41",Student # hard to read'));
  });

  test('the same wrong answers on 3+ questions are flagged both ways', () {
    const choices = ['1:2', '12:4', '38:1', '47:3', '7:2'];
    final csv = GradebookExport.rankedCsv([
      row('Sophie Zarobyan', 45, choices: choices),
      row('Clinton Kwong', 45, choices: choices),
      row('Arian Kasen Chi', 45, choices: const ['1:3', '4:1', '32:2']),
    ]);
    expect(csv, contains('Same wrong answers as Sophie Zarobyan'));
    expect(csv, contains('Same wrong answers as Clinton Kwong'));
    expect(RegExp('Same wrong').allMatches(csv).length, 2);
  });

  test('a tie across the cutoff needs a tiebreak; one inside it does not', () {
    final rows = [
      for (var i = 0; i < 49; i++) row('Student $i', 50.0 - i / 100),
      row('Benjamin', 40),
      row('Owen', 40),
      row('Neil Lekhi', 40),
    ];
    final csv = GradebookExport.rankedCsv(rows, cutoff: 50);
    expect(RegExp('TIED FOR 50TH – tiebreak needed').allMatches(csv).length, 3);
    expect(GradebookExport.rankedCsv(rows, cutoff: 60), isNot(contains('TIED')));
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
