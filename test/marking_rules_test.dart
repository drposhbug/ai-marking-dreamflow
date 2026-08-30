import 'package:flutter_test/flutter_test.dart';
import 'package:marking_prokect_v2/models/grading_preset.dart';
import 'package:marking_prokect_v2/services/local_store.dart';
import 'package:marking_prokect_v2/services/marking_rules.dart';
import 'package:marking_prokect_v2/services/presets_service.dart';

/// Stands in for shared_preferences so a teacher's corrections can be
/// written and read back without a platform channel.
class _MemoryStore implements LocalStore {
  final Map<String, String> values = {};

  @override
  Future<String?> getString(String key) async => values[key];

  @override
  Future<void> setString(String key, String value) async => values[key] = value;

  @override
  Future<void> clear() async => values.clear();
}

/// The teacher who marks thirty papers and takes the same mark back on
/// every one of them is teaching the marker something. These tests are
/// about the line between noticing that and putting words in her mouth.
///
/// The rule they hold to: a correction is a fact about one paper until it
/// has happened on three, and nothing is remembered that she has not read
/// and agreed to.
void main() {
  const spellingDocked = MarkCorrection(oldMark: 2, newMark: 3, oldNote: 'Spelling errors in the answer', newNote: 'Spelling errors in the answer');

  group('reading what the correction was about', () {
    test('giving a mark back where the note blamed spelling forgives spelling', () {
      final signals = MarkingRules.signalsIn(spellingDocked);
      expect(signals, contains(const MarkingSignal(RuleKind.forgive, 'spelling')));
    });

    test('rewriting the note to drop the complaint forgives it too', () {
      // She left the mark alone but took the nag out — she does not want
      // that held against the child.
      final signals = MarkingRules.signalsIn(const MarkCorrection(
        oldMark: 2,
        newMark: 2,
        oldNote: 'Missing units on the final answer',
        newNote: 'Good method here',
      ));
      expect(signals, contains(const MarkingSignal(RuleKind.forgive, 'units')));
    });

    test('clearing the note entirely is tidying, not forgiveness', () {
      // An empty box says nothing about how she wants it marked.
      final signals = MarkingRules.signalsIn(const MarkCorrection(
        oldMark: 2,
        newMark: 2,
        oldNote: 'Missing units on the final answer',
        newNote: '   ',
      ));
      expect(signals, isEmpty);
    });

    test('taking a mark off and saying why enforces that thing', () {
      final signals = MarkingRules.signalsIn(const MarkCorrection(
        oldMark: 3,
        newMark: 2,
        oldNote: 'Correct',
        newNote: 'No units on the answer',
      ));
      expect(signals, contains(const MarkingSignal(RuleKind.enforce, 'units')));
    });

    test('turning a half mark into a whole one is about half marks', () {
      final signals = MarkingRules.signalsIn(const MarkCorrection(oldMark: 0.5, newMark: 1));
      expect(signals, contains(const MarkingSignal(RuleKind.wholeMarks, '')));
    });

    test('a correction with no subject in it says nothing', () {
      final signals = MarkingRules.signalsIn(const MarkCorrection(oldMark: 2, newMark: 3, oldNote: 'Wrong', newNote: 'Wrong'));
      expect(signals, isEmpty);
    });

    test('a word that merely contains a topic is not that topic', () {
      // "united" is not "units"; "determine" is not a terminology complaint.
      final signals = MarkingRules.signalsIn(const MarkCorrection(
        oldMark: 2,
        newMark: 3,
        oldNote: 'Could not determine the united states answer',
        newNote: 'Could not determine the united states answer',
      ));
      expect(signals, isEmpty);
    });

    test('the suggested wording is a sentence a teacher would recognise', () {
      const s = MarkingSignal(RuleKind.forgive, 'spelling');
      expect(s.suggestedRule.toLowerCase(), contains('spelling'));
      expect(s.suggestedRule.trim(), isNotEmpty);
      expect(s.headline.trim(), isNotEmpty);
    });
  });

  group('how many papers before it asks', () {
    late MarkingRuleMemory memory;

    setUp(() async {
      memory = MarkingRuleMemory(store: _MemoryStore());
      await memory.load();
    });

    Future<RuleOffer?> see(String paperId, {String presetId = 'p1', int rules = 0}) => memory.noteCorrection(
          presetId: presetId,
          paperId: paperId,
          correction: spellingDocked,
          rulesOnScheme: rules,
        );

    test('one paper is a one-off, and nothing is offered', () async {
      expect(await see('paper-1'), isNull);
    });

    test('two papers could still be two odd students', () async {
      await see('paper-1');
      expect(await see('paper-2'), isNull);
    });

    test('the third paper is a pattern, and it asks', () async {
      await see('paper-1');
      await see('paper-2');
      final offer = await see('paper-3');
      expect(offer, isNotNull);
      expect(offer!.signal, const MarkingSignal(RuleKind.forgive, 'spelling'));
      expect(offer.suggestedText.toLowerCase(), contains('spelling'));
    });

    test('correcting the same paper three times is still one paper', () async {
      await see('paper-1');
      await see('paper-1');
      expect(await see('paper-1'), isNull);
    });

    test('it does not ask twice about something already asked', () async {
      await see('paper-1');
      await see('paper-2');
      expect(await see('paper-3'), isNotNull);
      expect(await see('paper-4'), isNull);
    });

    test('what it has counted survives the app being closed', () async {
      final store = _MemoryStore();
      final first = MarkingRuleMemory(store: store);
      await first.load();
      await first.noteCorrection(presetId: 'p1', paperId: 'paper-1', correction: spellingDocked, rulesOnScheme: 0);
      await first.noteCorrection(presetId: 'p1', paperId: 'paper-2', correction: spellingDocked, rulesOnScheme: 0);

      final reopened = MarkingRuleMemory(store: store);
      await reopened.load();
      final offer = await reopened.noteCorrection(presetId: 'p1', paperId: 'paper-3', correction: spellingDocked, rulesOnScheme: 0);
      expect(offer, isNotNull);
    });
  });

  group('saying no', () {
    late MarkingRuleMemory memory;
    const signal = MarkingSignal(RuleKind.forgive, 'spelling');

    setUp(() async {
      memory = MarkingRuleMemory(store: _MemoryStore());
      await memory.load();
    });

    Future<RuleOffer?> see(String paperId) => memory.noteCorrection(
          presetId: 'p1',
          paperId: paperId,
          correction: spellingDocked,
          rulesOnScheme: 0,
        );

    test('a declined suggestion is not stored', () async {
      await see('paper-1');
      await see('paper-2');
      await see('paper-3');
      await memory.declineOffer(presetId: 'p1', signal: signal);

      final presets = PresetsService(store: _MemoryStore());
      expect(presets.rulesFor('p1'), isEmpty);
    });

    test('a declined suggestion is not thrown straight back at her', () async {
      await see('paper-1');
      await see('paper-2');
      await see('paper-3');
      await memory.declineOffer(presetId: 'p1', signal: signal);
      expect(await see('paper-4'), isNull);
      expect(await see('paper-5'), isNull);
    });

    test('it may ask once more after another three papers', () async {
      for (final p in ['paper-1', 'paper-2', 'paper-3']) {
        await see(p);
      }
      await memory.declineOffer(presetId: 'p1', signal: signal);
      await see('paper-4');
      await see('paper-5');
      expect(await see('paper-6'), isNotNull);
    });

    test('no twice means no for good', () async {
      for (final p in ['paper-1', 'paper-2', 'paper-3']) {
        await see(p);
      }
      await memory.declineOffer(presetId: 'p1', signal: signal);
      await see('paper-4');
      await see('paper-5');
      await see('paper-6');
      await memory.declineOffer(presetId: 'p1', signal: signal);
      for (final p in ['paper-7', 'paper-8', 'paper-9', 'paper-10', 'paper-11', 'paper-12']) {
        expect(await see(p), isNull);
      }
    });
  });

  group('which scheme it belongs to', () {
    test('the same correction on two schemes is two separate counts', () async {
      final memory = MarkingRuleMemory(store: _MemoryStore());
      await memory.load();
      await memory.noteCorrection(presetId: 'physics', paperId: 'a', correction: spellingDocked, rulesOnScheme: 0);
      await memory.noteCorrection(presetId: 'physics', paperId: 'b', correction: spellingDocked, rulesOnScheme: 0);
      final offer = await memory.noteCorrection(presetId: 'essays', paperId: 'c', correction: spellingDocked, rulesOnScheme: 0);
      expect(offer, isNull, reason: 'two physics papers and one essay is not a pattern on either');
    });

    test('a rule saved on one scheme does not follow the teacher to another', () async {
      final presets = PresetsService(store: _MemoryStore());
      await presets.addRule(presetId: 'physics', text: 'Do not take marks off for spelling.', signalKey: 'forgive:spelling');
      expect(presets.rulesFor('physics'), hasLength(1));
      expect(presets.rulesFor('essays'), isEmpty);
      expect(presets.ruleInstructions('essays'), isEmpty);
    });

    test('a saved rule reaches the marker as a plain instruction', () async {
      final presets = PresetsService(store: _MemoryStore());
      await presets.addRule(presetId: 'physics', text: 'Do not take marks off for spelling.', signalKey: 'forgive:spelling');
      expect(presets.ruleInstructions('physics'), ['Do not take marks off for spelling.']);
    });

    test('rules survive the app being closed', () async {
      final store = _MemoryStore();
      final first = PresetsService(store: store);
      await first.addRule(presetId: 'physics', text: 'Do not take marks off for spelling.', signalKey: 'forgive:spelling');

      final reopened = PresetsService(store: store);
      await reopened.loadRules();
      expect(reopened.ruleInstructions('physics'), ['Do not take marks off for spelling.']);
    });

    test('the teacher can delete one later', () async {
      final presets = PresetsService(store: _MemoryStore());
      await presets.addRule(presetId: 'physics', text: 'Do not take marks off for spelling.', signalKey: 'forgive:spelling');
      final rule = presets.rulesFor('physics').single;
      await presets.removeRule(presetId: 'physics', ruleId: rule.id);
      expect(presets.rulesFor('physics'), isEmpty);
    });
  });

  group('the cap', () {
    test('a scheme remembers at most eight corrections', () async {
      final presets = PresetsService(store: _MemoryStore());
      for (var i = 0; i < GradingPreset.maxRulesPerPreset; i++) {
        expect(await presets.addRule(presetId: 'physics', text: 'Rule $i', signalKey: 'forgive:t$i'), isTrue);
      }
      expect(presets.rulesFor('physics'), hasLength(GradingPreset.maxRulesPerPreset));

      final ninth = await presets.addRule(presetId: 'physics', text: 'One too many', signalKey: 'forgive:extra');
      expect(ninth, isFalse, reason: 'nothing the teacher approved is quietly dropped to make room');
      expect(presets.rulesFor('physics'), hasLength(GradingPreset.maxRulesPerPreset));
      expect(presets.ruleInstructions('physics'), isNot(contains('One too many')));
    });

    test('at the cap she is told the scheme is full instead of being ignored', () async {
      final memory = MarkingRuleMemory(store: _MemoryStore());
      await memory.load();
      RuleOffer? offer;
      for (final p in ['paper-1', 'paper-2', 'paper-3']) {
        offer = await memory.noteCorrection(
          presetId: 'p1',
          paperId: p,
          correction: spellingDocked,
          rulesOnScheme: GradingPreset.maxRulesPerPreset,
        );
      }
      expect(offer, isNotNull);
      expect(offer!.schemeIsFull, isTrue);
    });

    test('an accepted rule is never offered again', () async {
      final memory = MarkingRuleMemory(store: _MemoryStore());
      await memory.load();
      for (final p in ['paper-1', 'paper-2', 'paper-3']) {
        await memory.noteCorrection(presetId: 'p1', paperId: p, correction: spellingDocked, rulesOnScheme: 0);
      }
      await memory.acceptOffer(presetId: 'p1', signal: const MarkingSignal(RuleKind.forgive, 'spelling'));
      for (final p in ['paper-4', 'paper-5', 'paper-6', 'paper-7']) {
        expect(await memory.noteCorrection(presetId: 'p1', paperId: p, correction: spellingDocked, rulesOnScheme: 1), isNull);
      }
    });

    test('what it counts does not grow without limit', () async {
      final store = _MemoryStore();
      final memory = MarkingRuleMemory(store: store);
      await memory.load();
      for (var i = 0; i < 200; i++) {
        await memory.noteCorrection(presetId: 'p1', paperId: 'paper-$i', correction: spellingDocked, rulesOnScheme: 0);
      }
      // One tally per signal, and the papers behind it are not hoarded.
      expect(memory.papersRemembered(presetId: 'p1', signal: const MarkingSignal(RuleKind.forgive, 'spelling')),
          lessThanOrEqualTo(MarkingRuleMemory.maxPapersPerSignal));
    });
  });
}
