import 'dart:convert';
import 'dart:typed_data';

import 'keys.dart';
import 'mnemonic.dart';
import 'theme.dart';

/// No theme holds a word given.
class ThemeNotFound implements Exception {
  const ThemeNotFound(this.message);

  final String message;

  @override
  String toString() => 'ThemeNotFound: $message';
}

/// More than one theme holds every word given.
class ThemeAmbiguous implements Exception {
  const ThemeAmbiguous(this.message, this.themes);

  final String message;

  /// The themes that hold every word, sorted.
  final List<String> themes;

  @override
  String toString() => 'ThemeAmbiguous: $message';
}

/// Every theme available, read on first use — where the reference
/// implementation looks into its themes folder.
class ThemeSet {
  /// Themes by name, each read by [load] the first time it is asked for.
  ThemeSet(Iterable<String> names, this._load)
      : names = List<String>.unmodifiable(names.toList()..sort());

  /// Themes from their JSON texts, by name.
  factory ThemeSet.fromJson(Map<String, String> texts) => ThemeSet(
        texts.keys,
        (String name) => Theme(
            name, jsonDecode(texts[name]!) as Map<String, Object?>),
      );

  /// The themes' names, sorted.
  final List<String> names;
  final Theme Function(String name) _load;
  final Map<String, Mnemonic> _mnemonics = <String, Mnemonic>{};
  final Map<String, Set<String>> _wordsets = <String, Set<String>>{};

  /// The mnemonics of theme [name]. Throws a [ThemeNotFound] for a theme
  /// not in the set.
  Mnemonic operator [](String name) {
    if (!names.contains(name)) throw ThemeNotFound('Theme $name not found');
    return _mnemonics[name] ??= Mnemonic(_load(name));
  }

  Set<String> _words(String name) =>
      _wordsets[name] ??= this[name].wordlist.toSet();

  /// The one theme holding every word of [code]. Throws a [ThemeNotFound]
  /// when none does, a [ThemeAmbiguous] when several do.
  String detectTheme(Object code) {
    final String text = code is String ? code : (code as List<String>).join(' ');
    Set<String> possible = names.toSet();
    for (final String word in nfkd(text).split(RegExp(r'\s+'))) {
      if (word.isEmpty) continue;
      possible = <String>{
        for (final String t in possible)
          if (_words(t).contains(word)) t,
      };
      if (possible.isEmpty) {
        throw ThemeNotFound("Theme unrecognized for '$word'");
      }
    }
    if (possible.length == 1) return possible.single;
    final List<String> sorted = possible.toList()..sort();
    throw ThemeAmbiguous('Theme ambiguous between ${sorted.join(', ')}', sorted);
  }

  /// The theme of the whole mnemonic [code]: themes sharing every word are
  /// told apart by the checksum.
  String resolveTheme(Object code) {
    try {
      return detectTheme(code);
    } on ThemeAmbiguous catch (ambiguity) {
      final List<String> checked = <String>[
        for (final String t in ambiguity.themes)
          if (checksOut(t, code)) t,
      ];
      if (checked.length == 1) return checked.single;
      rethrow;
    }
  }

  /// Whether [code] is a whole mnemonic of [theme] with a good checksum.
  bool checksOut(String theme, Object code) {
    try {
      return this[theme].check(code);
    } on Object {
      return false;
    }
  }

  /// [mnemonic] in [newTheme], the same entropy; its theme is detected
  /// unless [currentTheme] is given.
  String convertTheme(Object mnemonic, String newTheme, {String? currentTheme}) {
    final Mnemonic target = this[newTheme];
    final List<String> words = Theme.normalizeMnemonic(mnemonic);
    final String current = currentTheme ?? detectTheme(words);
    final Uint8List entropy = this[current].toEntropy(words);
    final String out = target.toMnemonic(entropy);
    entropy.fillRange(0, entropy.length, 0);
    return out;
  }

  /// The 64-byte seed of [mnemonic] and [passphrase]: a mnemonic of any
  /// Formosa theme is first converted to its BIP39 equivalent, so the same
  /// entropy gives the same seed, keys and addresses in every theme.
  Uint8List toSeed(Object mnemonic, {String passphrase = ''}) {
    String text =
        mnemonic is String ? mnemonic : (mnemonic as List<String>).join(' ');
    try {
      final String theme = resolveTheme(text);
      if (!theme.startsWith(kDefaultTheme)) {
        text = convertTheme(text, kDefaultTheme, currentTheme: theme);
      }
    } on ThemeNotFound {
      // Words outside every theme are hashed as given, as BIP39 does.
    }
    return pbkdf2HmacSha512(
      utf8.encode(nfkd(text)),
      utf8.encode('mnemonic${nfkd(passphrase)}'),
      kPbkdf2Rounds,
    );
  }
}
