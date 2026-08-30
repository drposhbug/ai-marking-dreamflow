/// Turns a pasted block of names into a class list.
///
/// Typing thirty names is where a teacher gives up on setting the app up,
/// so the fastest path in is the one they already have: a list they can
/// copy from anywhere — Classroom, a spreadsheet, an email, a register —
/// pasted in whole.
///
/// Everything here is offline, instant and free. Nothing is sent anywhere.
class RosterPaste {
  /// Rows that are a header or a spreadsheet artefact rather than a child.
  static final _notAName = RegExp(
    r'^(name|student|students|full\s*name|student\s*name|first\s*name|last\s*name|surname|'
    r'email|email\s*address|no|#|number|id|student\s*id|class|total|average|mean)$',
    caseSensitive: false,
  );

  /// A leading list marker: "1.", "12)", "-", "*", "•".
  static final _leadingBullet = RegExp(r'^\s*(?:\d{1,3}\s*[.)\]]|[-*•·])\s+');

  /// Trailing junk a copy-paste drags along: a student number, a mark, an
  /// email in brackets. Kept conservative — a real name is never dropped to
  /// make a line tidier.
  static final _trailingEmail = RegExp(r'\s*[<(\[]?[\w.+-]+@[\w.-]+\.\w+[>)\]]?\s*$');

  /// Splits a pasted block into candidate lines.
  ///
  /// Newlines are the normal case. A single line holding several names
  /// separated by commas is handled too — but only when it cannot be a
  /// "Last, First" name, because those are commas that must be kept.
  static List<String> splitLines(String raw) {
    final text = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final lines = text.split(RegExp(r'[\n\t;]'));
    final kept = lines.where((l) => l.trim().isNotEmpty).toList(growable: false);
    if (kept.length > 1) return kept;

    // One line only. "Ana Ruiz, Ben Cole, Cara Diaz" is three students;
    // "Ruiz, Ana" and "Ruiz, Ana, Jr" are one. What separates them is
    // whether every part is itself a full name — counting the commas is
    // not enough, and getting it wrong turns one child into three.
    final one = kept.isEmpty ? '' : kept.first;
    final parts = one.split(',').map((p) => p.trim()).where((p) => p.isNotEmpty).toList(growable: false);
    if (parts.length >= 2 && parts.every((p) => p.contains(' '))) return parts;
    return kept;
  }

  /// Cleans one line down to a name, or returns null if it is not one.
  static String? cleanName(String line) {
    var s = line.trim();
    if (s.isEmpty) return null;
    s = s.replaceFirst(_leadingBullet, '');
    s = s.replaceFirst(_trailingEmail, '');
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    // Strip wrapping quotes a spreadsheet copy can leave behind.
    if (s.length > 1 && ((s.startsWith('"') && s.endsWith('"')) || (s.startsWith("'") && s.endsWith("'")))) {
      s = s.substring(1, s.length - 1).trim();
    }
    if (s.isEmpty) return null;
    if (_notAName.hasMatch(s)) return null;
    // A row that is only digits, punctuation or a mark is not a child.
    if (!RegExp(r'[A-Za-zÀ-ɏ]').hasMatch(s)) return null;

    // "Ruiz, Ana" -> "Ana Ruiz". Only when there is exactly one comma and
    // both sides have something in them; anything else is left alone,
    // because a mangled name is worse than an unusual one.
    final comma = s.split(',');
    if (comma.length == 2) {
      final last = comma[0].trim();
      final first = comma[1].trim();
      if (last.isNotEmpty && first.isNotEmpty) s = '$first $last';
    }
    return s.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Parses a pasted block into names, in the order pasted, with blanks,
  /// headers and repeats removed.
  ///
  /// Duplicates are matched case- and spacing-insensitively so "ana ruiz"
  /// and "Ana  Ruiz" are one child, and the first spelling is the one kept.
  static List<String> parse(String raw) {
    final seen = <String>{};
    final out = <String>[];
    for (final line in splitLines(raw)) {
      final name = cleanName(line);
      if (name == null) continue;
      if (!seen.add(name.toLowerCase())) continue;
      out.add(name);
    }
    return List.unmodifiable(out);
  }

  /// Names in [pasted] that the class already has, matched the same
  /// forgiving way. Shown to the teacher so a second paste tops a class up
  /// instead of doubling it.
  static List<String> alreadyPresent(List<String> pasted, Iterable<String> existing) {
    final have = existing.map((e) => e.trim().toLowerCase()).toSet();
    return pasted.where((n) => have.contains(n.toLowerCase())).toList(growable: false);
  }

  /// A short student code from a name's initials, kept unique against
  /// [taken]. Mirrors what the single-student sheet does, without its
  /// clock-based suffix.
  static String codeFor(String name, Set<String> taken) {
    final initials = name
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase())
        .join();
    final base = initials.isEmpty ? 'S' : initials;
    var n = 1;
    var code = '$base$n';
    while (taken.contains(code)) {
      n++;
      code = '$base$n';
    }
    taken.add(code);
    return code;
  }
}
