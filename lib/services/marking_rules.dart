import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:marking_prokect_v2/models/grading_preset.dart';
import 'package:marking_prokect_v2/services/local_store.dart';

/// Turning a teacher's repeated corrections into a marking rule she agrees to.
///
/// A teacher who puts a mark back for spelling on paper one does it again on
/// paper two, and on all thirty, and then on next term's set. Today every one
/// of those corrections is thrown away the moment she closes the result. This
/// watches for the same correction happening on paper after paper and — only
/// then — asks whether she wants the marker to do it her way from now on.
///
/// Nothing here calls the AI. The rule text is written from a small table of
/// marking topics the app already knows about, so noticing a pattern and
/// wording it costs nothing per mark.

/// One question's mark and note, before and after the teacher touched it.
@immutable
class MarkCorrection {
  final double? oldMark;
  final double? newMark;
  final String oldNote;
  final String newNote;

  const MarkCorrection({this.oldMark, this.newMark, this.oldNote = '', this.newNote = ''});
}

/// What kind of thing the teacher was correcting.
enum RuleKind {
  /// She gave the mark back, or took the complaint out: she does not want
  /// this held against the child.
  forgive,

  /// She took a mark off and said why: she wants this enforced.
  enforce,

  /// She turned a half mark into a whole one.
  wholeMarks,
}

/// A repeated correction, named in the app's own vocabulary.
@immutable
class MarkingSignal {
  final RuleKind kind;

  /// A key from [MarkingRules.topics] — empty for [RuleKind.wholeMarks],
  /// which is not about any one part of the work.
  final String topic;

  const MarkingSignal(this.kind, this.topic);

  /// Stable across app versions: it is written into the teacher's saved
  /// rules and into the tally of what has been asked already.
  String get key => topic.isEmpty ? kind.name : '${kind.name}:$topic';

  static MarkingSignal? fromKey(String key) {
    final parts = key.split(':');
    final kind = RuleKind.values.cast<RuleKind?>().firstWhere((k) => k?.name == parts.first, orElse: () => null);
    if (kind == null) return null;
    return MarkingSignal(kind, parts.length > 1 ? parts[1] : '');
  }

  /// The question the teacher is asked, in the dialog title.
  String get headline {
    if (kind == RuleKind.wholeMarks) return 'Stop giving half marks?';
    final label = MarkingRules.topics[topic]?.label ?? topic;
    return kind == RuleKind.forgive ? 'Stop taking marks off for $label?' : 'Always take marks off for $label?';
  }

  /// The sentence the marker will be given — shown to the teacher first, and
  /// editable, because it is going to be spoken in her name.
  String get suggestedRule {
    if (kind == RuleKind.wholeMarks) {
      return 'Score every question in whole marks — never award 0.25, 0.5 or 0.75.';
    }
    final t = MarkingRules.topics[topic];
    if (t == null) return '';
    return kind == RuleKind.forgive ? t.forgive : t.enforce;
  }

  @override
  bool operator ==(Object other) => other is MarkingSignal && other.kind == kind && other.topic == topic;

  @override
  int get hashCode => Object.hash(kind, topic);

  @override
  String toString() => 'MarkingSignal($key)';
}

/// A marking topic the app can name, and how a teacher would say it.
@immutable
class MarkingTopic {
  final String label;
  final List<String> words;
  final String forgive;
  final String enforce;

  const MarkingTopic({required this.label, required this.words, required this.forgive, required this.enforce});
}

/// Reads one correction and says what, if anything, it was about.
class MarkingRules {
  /// Three different papers before anything is offered.
  ///
  /// One correction is usually about that student — a name misread, a
  /// question they answered oddly — and acting on it would be putting words
  /// in the teacher's mouth. Two could still be two unusual papers. By the
  /// third the teacher has paid for the same correction three times, and
  /// asking her once is cheaper for her than letting her do it a fourth.
  static const int papersBeforeOffer = 3;

  /// The parts of marking the app can name. Anything outside this table is
  /// left alone: a rule we cannot word in plain English is a rule we should
  /// not be inventing.
  static const Map<String, MarkingTopic> topics = {
    'spelling': MarkingTopic(
      label: 'spelling',
      words: ['spelling', 'spelt', 'spelled', 'misspelt', 'misspelled', 'misspelling'],
      forgive: 'Do not take marks off for spelling.',
      enforce: 'Take a mark off when subject words are spelled wrong.',
    ),
    'units': MarkingTopic(
      label: 'missing units',
      words: ['unit', 'units'],
      forgive: 'Do not take marks off for missing or wrong units.',
      enforce: 'Take a mark off when units are missing or wrong.',
    ),
    'sigfigs': MarkingTopic(
      label: 'significant figures',
      words: ['sig fig', 'sig figs', 'significant figure', 'significant figures', 'decimal place', 'decimal places', 'rounding', 'rounded'],
      forgive: 'Do not take marks off for significant figures or rounding.',
      enforce: 'Take a mark off for the wrong number of significant figures or for rounding badly.',
    ),
    'working': MarkingTopic(
      label: 'working not shown',
      words: ['working', 'workings', 'method', 'steps'],
      forgive: 'Do not take marks off when the working is not shown, as long as the answer is right.',
      enforce: 'Take marks off when the working or method is not shown.',
    ),
    'neatness': MarkingTopic(
      label: 'neatness',
      words: ['neat', 'neatness', 'untidy', 'messy', 'handwriting', 'presentation', 'legible', 'illegible'],
      forgive: 'Do not take marks off for neatness, presentation or handwriting.',
      enforce: 'Take marks off for untidy or hard-to-read work.',
    ),
    'grammar': MarkingTopic(
      label: 'grammar and punctuation',
      words: ['grammar', 'grammatical', 'punctuation', 'apostrophe', 'capitalisation', 'capitalization'],
      forgive: 'Do not take marks off for grammar or punctuation.',
      enforce: 'Take marks off for grammar and punctuation errors.',
    ),
    'labels': MarkingTopic(
      label: 'unlabelled diagrams',
      words: ['label', 'labels', 'labelled', 'labeled', 'unlabelled', 'unlabeled'],
      forgive: 'Do not take marks off when a diagram or axis is unlabelled.',
      enforce: 'Take a mark off when diagrams and axes are not labelled.',
    ),
    'notation': MarkingTopic(
      label: 'notation',
      words: ['notation', 'formatting', 'layout'],
      forgive: 'Do not take marks off for notation or how an answer is laid out.',
      enforce: 'Take a mark off for incorrect notation.',
    ),
    'wording': MarkingTopic(
      label: 'wording',
      words: ['terminology', 'wording', 'phrasing'],
      forgive: 'Do not take marks off for wording, as long as the meaning is right.',
      enforce: 'Take a mark off when the correct subject terminology is not used.',
    ),
  };

  /// True when [text] talks about [topic]. Whole words only — "united" is
  /// not a complaint about units, and "determine" is not about terminology.
  static bool mentions(String text, String topic) {
    final t = topics[topic];
    if (t == null) return false;
    final lower = text.toLowerCase();
    for (final w in t.words) {
      if (RegExp('(?<![a-z])${RegExp.escape(w)}(?![a-z])').hasMatch(lower)) return true;
    }
    return false;
  }

  /// What this one correction was about. Usually nothing.
  static List<MarkingSignal> signalsIn(MarkCorrection c) {
    final out = <MarkingSignal>[];
    final oldMark = c.oldMark;
    final newMark = c.newMark;
    final oldNote = c.oldNote;
    final newNote = c.newNote;

    if (oldMark != null && newMark != null && oldMark != newMark && oldMark % 1 != 0 && newMark % 1 == 0) {
      out.add(const MarkingSignal(RuleKind.wholeMarks, ''));
    }

    final markWentUp = oldMark != null && newMark != null && newMark > oldMark;
    final markWentDown = oldMark != null && newMark != null && newMark < oldMark;
    final markHeld = oldMark != null && newMark != null && newMark == oldMark;
    // An emptied note is tidying up, not a marking decision — she may just
    // not want a comment printed on the page. Only a rewritten note counts.
    final noteRewritten = newNote.trim().isNotEmpty;

    for (final topic in topics.keys) {
      final inOld = mentions(oldNote, topic);
      final inNew = mentions(newNote, topic);

      if (inOld && (markWentUp || (markHeld && noteRewritten && !inNew))) {
        out.add(MarkingSignal(RuleKind.forgive, topic));
      } else if (inNew && !inOld && markWentDown) {
        out.add(MarkingSignal(RuleKind.enforce, topic));
      }
    }

    return out;
  }
}

/// A suggestion put to the teacher: what would be remembered, in words she
/// can edit, and whether the scheme has room for it.
@immutable
class RuleOffer {
  final MarkingSignal signal;
  final String suggestedText;

  /// The scheme already holds [maxRulesPerPreset] rules. The teacher is told
  /// so and pointed at the list, rather than having an older rule she agreed
  /// to quietly dropped to make room.
  final bool schemeIsFull;

  const RuleOffer({required this.signal, required this.suggestedText, required this.schemeIsFull});
}

/// How often each correction has come up on each scheme, and what has
/// already been asked. Kept on the device — this is a record of a teacher's
/// own habits and there is no reason to ship it anywhere.
class MarkingRuleMemory {
  static const _kKey = 'ai_marker.marking_rule_tallies.v1';

  /// A tally only ever needs to know it has reached the threshold again, so
  /// it keeps the last few paper ids rather than every paper ever marked.
  static const int maxPapersPerSignal = 12;

  /// Two noes is a no. After the second decline the same suggestion is never
  /// raised on that scheme again.
  static const int maxDeclines = 2;

  final LocalStore _store;
  MarkingRuleMemory({LocalStore? store}) : _store = store ?? const LocalStore();

  /// presetId -> signal key -> tally
  Map<String, Map<String, _Tally>> _tallies = {};
  Future<void>? _loading;

  /// Loads once, however many callers ask. Two reads racing would let the
  /// slower one put an empty tally back over a correction just counted.
  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final raw = await _store.getString(_kKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = (jsonDecode(raw) as Map).cast<String, dynamic>();
        final out = <String, Map<String, _Tally>>{};
        for (final preset in decoded.entries) {
          final inner = preset.value;
          if (inner is! Map) continue;
          final signals = <String, _Tally>{};
          for (final s in inner.entries) {
            final v = s.value;
            if (v is Map) signals['${s.key}'] = _Tally.fromJson(v.cast<String, dynamic>());
          }
          out[preset.key] = signals;
        }
        _tallies = out;
      }
    } catch (e) {
      debugPrint('MarkingRuleMemory.load failed: $e');
      _tallies = {};
    }
  }

  Future<void> _persist() async {
    try {
      final map = <String, dynamic>{
        for (final p in _tallies.entries) p.key: {for (final s in p.value.entries) s.key: s.value.toJson()},
      };
      await _store.setString(_kKey, jsonEncode(map));
    } catch (e) {
      debugPrint('MarkingRuleMemory._persist failed: $e');
    }
  }

  int papersRemembered({required String presetId, required MarkingSignal signal}) =>
      _tallies[presetId]?[signal.key]?.papers.length ?? 0;

  /// Records one correction against one paper and says whether it is time to
  /// ask the teacher about it. Returns null nearly every time — which is the
  /// point.
  Future<RuleOffer?> noteCorrection({
    required String presetId,
    required String paperId,
    required MarkCorrection correction,
    required int rulesOnScheme,
  }) async {
    // A rule with no scheme to belong to would apply to everything the
    // teacher ever marks, which is not what she is being asked.
    if (presetId.trim().isEmpty || paperId.trim().isEmpty) return null;
    await load();

    final signals = MarkingRules.signalsIn(correction);
    if (signals.isEmpty) return null;

    RuleOffer? offer;
    var changed = false;
    final forPreset = {...(_tallies[presetId] ?? const <String, _Tally>{})};

    for (final signal in signals) {
      final tally = forPreset[signal.key] ?? const _Tally();
      // The same paper corrected five times is still one paper. This is what
      // stops one unusual script from manufacturing a rule.
      if (tally.papers.contains(paperId)) continue;

      final papers = [...tally.papers, paperId];
      final next = tally.copyWith(
        papers: papers.length > maxPapersPerSignal ? papers.sublist(papers.length - maxPapersPerSignal) : papers,
        seen: tally.seen + 1,
      );
      forPreset[signal.key] = next;
      changed = true;

      if (offer != null) continue;
      if (next.accepted) continue;
      if (next.declines >= maxDeclines) continue;
      // After a no, the same suggestion has to earn its way back: another
      // three papers before it is raised again, and only once more.
      if (next.seen < next.mutedUntil) continue;
      if (next.seen < MarkingRules.papersBeforeOffer) continue;

      offer = RuleOffer(
        signal: signal,
        suggestedText: signal.suggestedRule,
        schemeIsFull: rulesOnScheme >= GradingPreset.maxRulesPerPreset,
      );
      // Asked now — do not raise it again on the next paper whatever she says.
      forPreset[signal.key] = next.copyWith(mutedUntil: next.seen + MarkingRules.papersBeforeOffer);
    }

    if (changed) {
      _tallies = {..._tallies, presetId: forPreset};
      await _persist();
    }
    return offer;
  }

  /// She said no. Nothing is stored, and the counter that decides when to
  /// ask again is pushed out.
  Future<void> declineOffer({required String presetId, required MarkingSignal signal}) async {
    await load();
    final forPreset = {...(_tallies[presetId] ?? const <String, _Tally>{})};
    final tally = forPreset[signal.key] ?? const _Tally();
    forPreset[signal.key] = tally.copyWith(
      declines: tally.declines + 1,
      mutedUntil: tally.seen + MarkingRules.papersBeforeOffer,
    );
    _tallies = {..._tallies, presetId: forPreset};
    await _persist();
  }

  /// She said yes. The scheme holds the rule now, so there is nothing left
  /// to ask about.
  Future<void> acceptOffer({required String presetId, required MarkingSignal signal}) async {
    await load();
    final forPreset = {...(_tallies[presetId] ?? const <String, _Tally>{})};
    final tally = forPreset[signal.key] ?? const _Tally();
    forPreset[signal.key] = tally.copyWith(accepted: true);
    _tallies = {..._tallies, presetId: forPreset};
    await _persist();
  }

  /// She deleted the rule from the scheme. The tally is cleared with it, so
  /// deleting a rule is not a decision that quietly comes back next week.
  Future<void> forget({required String presetId, required String signalKey}) async {
    await load();
    final forPreset = {...(_tallies[presetId] ?? const <String, _Tally>{})};
    if (forPreset.remove(signalKey) == null) return;
    _tallies = {..._tallies, presetId: forPreset};
    await _persist();
  }
}

@immutable
class _Tally {
  final List<String> papers;
  final int seen;
  final int declines;
  final int mutedUntil;
  final bool accepted;

  const _Tally({this.papers = const [], this.seen = 0, this.declines = 0, this.mutedUntil = 0, this.accepted = false});

  _Tally copyWith({List<String>? papers, int? seen, int? declines, int? mutedUntil, bool? accepted}) => _Tally(
        papers: papers ?? this.papers,
        seen: seen ?? this.seen,
        declines: declines ?? this.declines,
        mutedUntil: mutedUntil ?? this.mutedUntil,
        accepted: accepted ?? this.accepted,
      );

  Map<String, dynamic> toJson() => {
        'papers': papers,
        'seen': seen,
        'declines': declines,
        'mutedUntil': mutedUntil,
        'accepted': accepted,
      };

  factory _Tally.fromJson(Map<String, dynamic> j) => _Tally(
        papers: (j['papers'] as List?)?.map((e) => '$e').toList(growable: false) ?? const [],
        seen: (j['seen'] as num?)?.toInt() ?? 0,
        declines: (j['declines'] as num?)?.toInt() ?? 0,
        mutedUntil: (j['mutedUntil'] as num?)?.toInt() ?? 0,
        accepted: j['accepted'] == true,
      );
}
