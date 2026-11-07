/// The Password Generator's text: every mnemonic generated so far, each its
/// password line then its sentences, and the tweaks of the password lines —
/// the port of the reference window's `MnemonicGeneratorTab`.
library;

/// A tweak of the passwords: each swaps one letter of a password line for its
/// look-alike, and back.
enum Tweak {
  /// A letter for a digit.
  number(<String>['a', 'b', 'e', 'g', 'i', 'o', 'q', 's', 't'],
      <String>['4', '8', '3', '6', '1', '0', '9', '5', '7']),

  /// A letter for a special character.
  special(<String>['a', 'c', 'e', 'h', 'j', 'l', 's', 't', 'z'],
      <String>['@', '¢', '&', '#', '!', '£', r'$', '+', '%']),

  /// A letter for its capital.
  upper(_lower, _upper);

  const Tweak(this.letters, this.marks);

  /// The letters replaced, and what replaces each.
  final List<String> letters;
  final List<String> marks;
}

const List<String> _lower = <String>[
  'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', //
  'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z',
];
const List<String> _upper = <String>[
  'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', //
  'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z',
];

/// Phrases a mnemonic may have: BIP39 counts words, by threes; a theme,
/// sentences.
const int kBip39MinPhrases = 3;
const int kBip39MaxPhrases = 24;
const int kThemeMinPhrases = 1;
const int kThemeMaxPhrases = 8;

/// Bits of entropy per sentence of a theme, and per three BIP39 words.
const int kBitsPerPhrase = 32;

/// The phrases selectable for a theme: (min, max), the step being min.
(int, int) phrasesRange({required bool bip39}) => bip39
    ? (kBip39MinPhrases, kBip39MaxPhrases)
    : (kThemeMinPhrases, kThemeMaxPhrases);

/// The strength of [phrases] phrases.
int strengthOf(int phrases, {required bool bip39}) => bip39
    ? kBitsPerPhrase * phrases ~/ kBip39MinPhrases
    : kBitsPerPhrase * phrases;

/// The generator's text.
class GeneratorText {
  /// Everything generated, as shown and copied.
  String text = '';

  /// The line of each mnemonic's password.
  final List<int> passwordLines = <int>[];
  int _lastPhrases = 0;

  /// Append a mnemonic [formatted] (its password line, then [phrases]
  /// lines), then apply the tweaks [on].
  void add(String formatted, int phrases, Set<Tweak> on) {
    text = '$text$formatted\n';
    passwordLines
        .add(passwordLines.isEmpty ? 0 : passwordLines.last + _lastPhrases + 1);
    _lastPhrases = phrases;
    for (final Tweak t in Tweak.values) {
      if (on.contains(t)) apply(t, on: true);
    }
  }

  void clear() {
    text = '';
    passwordLines.clear();
  }

  /// Apply [tweak] to every password line ([on]), or undo it.
  void apply(Tweak tweak, {required bool on}) {
    if (!tweak.letters.any(text.contains)) return;
    final List<String> insert = on ? tweak.marks : tweak.letters;
    final List<String> remove = on ? tweak.letters : tweak.marks;
    _replace(insert, remove, undoing: !on);
  }

  void _replace(List<String> insert, List<String> remove,
      {required bool undoing}) {
    final List<String> lines = text.split('\n');
    for (final int at in passwordLines) {
      if (at < 0 || at >= lines.length) continue;
      final String password = lines[at];
      final List<String> chars = password.split('');
      final List<int> removable = <int>[
        for (final String c in chars)
          if (remove.contains(c)) remove.indexOf(c),
      ];
      final List<String> changed = <String>[
        for (final String c in chars)
          if (insert.contains(c)) c,
      ];
      if (removable.isEmpty) continue;
      final String gone = remove[removable.first];
      final String put = insert[removable.first];
      // Already tweaked before its first letter: leave it.
      if (changed.isNotEmpty &&
          !undoing &&
          password.indexOf(changed.first) < password.indexOf(gone)) {
        continue;
      }
      final String replaced = password.replaceFirst(gone, put);
      text = text.replaceAll(password, replaced);
    }
  }
}
