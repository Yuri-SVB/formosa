import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:unorm_dart/unorm_dart.dart' as unorm;

import 'theme.dart';

/// The BIP39 themes' name prefix, and the default theme.
const String kDefaultTheme = 'BIP39';

/// Strengths, in bits: multiples of [kStrengthStep] from [kMinStrength] to
/// [kMaxStrength].
const int kMinStrength = 32;
const int kMaxStrength = 256;
const int kStrengthStep = 32;

/// Checksum: one bit per [kStrengthStep] bits of entropy.
const int _kBitsPerChecksumBit = kStrengthStep + 1;

/// Letters of each word in a password: BIP39 words share up to 4.
const int _kBip39PasswordLetters = 4;
const int _kThemePasswordLetters = 2;

/// Filler of a word shorter than a password's letters.
const String _kPad = '-';

const int _kBitsPerByte = 8;

/// The NFKD form of [s], as BIP39 compares and hashes words.
String nfkd(String s) => unorm.nfkd(s);

/// The NFC form of [s]: an accented letter is one letter.
String nfc(String s) => unorm.nfc(s);

/// Mnemonics of one theme: encoding, decoding, checking, completing — the
/// port of the reference implementation's `Mnemonic`.
class Mnemonic {
  Mnemonic(this.theme);

  final Theme theme;

  String get name => theme.name;

  /// A BIP39 word list rather than a Formosa theme.
  bool get isBip39Theme => name.startsWith(kDefaultTheme);

  /// Japanese is joined by the ideographic space.
  String get delimiter => name == 'BIP39_japanese' ? '　' : ' ';

  List<String> get wordlist => theme.wordlist;

  /// A new mnemonic of [strength] bits from [random] (the system's secure
  /// generator by default).
  String generate({int strength = 128, math.Random? random}) {
    checkStrength(strength);
    final math.Random rng = random ?? math.Random.secure();
    final Uint8List data = Uint8List(strength ~/ _kBitsPerByte);
    for (int i = 0; i < data.length; i++) {
      data[i] = rng.nextInt(1 << _kBitsPerByte);
    }
    final String out = toMnemonic(data);
    data.fillRange(0, data.length, 0);
    return out;
  }

  /// Throws an [ArgumentError] unless [strength] can be encoded.
  static void checkStrength(int strength) {
    if (strength % kStrengthStep != 0 ||
        strength < kMinStrength ||
        strength > kMaxStrength) {
      throw ArgumentError('Strength should be between $kMinStrength and '
          '$kMaxStrength and a multiple of $kStrengthStep, but it is '
          '$strength.');
    }
  }

  /// The mnemonic of [data] (a whole number of 4-byte words): its bits, then
  /// the first bit of its SHA-256 per 32 of them.
  String toMnemonic(List<int> data) {
    const int multiple = kStrengthStep ~/ _kBitsPerByte;
    if (data.length % multiple != 0) {
      throw FormatException('Number of bytes should be multiple of $multiple, '
          'but it is ${data.length}.');
    }
    final List<int> bits = <int>[
      ..._bits(data),
      ..._bits(sha256.convert(data).bytes)
          .take(data.length * _kBitsPerByte ~/ kStrengthStep),
    ];
    return theme.sentencesFromBits(bits).join(delimiter);
  }

  /// The entropy [words] encode. Throws a [FormatException] when they are not
  /// whole sentences of this theme or fail the checksum.
  Uint8List toEntropy(Object words) {
    final List<String> list = Theme.normalizeMnemonic(words);
    if (list.length % theme.wordsPerPhrase != 0) {
      throw FormatException('The number of words must be a multiple of '
          '${theme.wordsPerPhrase}, but it is ${list.length}');
    }
    final List<int> bits = _indexBits(list);
    final int checksumBits = bits.length ~/ _kBitsPerChecksumBit;
    final int entropyBits = bits.length - checksumBits;
    final Uint8List entropy = Uint8List(entropyBits ~/ _kBitsPerByte);
    for (int i = 0; i < entropy.length; i++) {
      for (int b = 0; b < _kBitsPerByte; b++) {
        entropy[i] |= bits[i * _kBitsPerByte + b] << (_kBitsPerByte - 1 - b);
      }
    }
    final List<int> hash = _bits(sha256.convert(entropy).bytes);
    bool valid = true;
    for (int i = 0; i < checksumBits; i++) {
      valid &= bits[entropyBits + i] == hash[i];
    }
    if (!valid) throw const FormatException('Failed checksum.');
    return entropy;
  }

  /// Whether [mnemonic] is a whole mnemonic of this theme, of a strength it
  /// can have, with a good checksum.
  bool check(Object mnemonic) {
    final String text =
        mnemonic is String ? mnemonic : (mnemonic as List<String>).join(' ');
    final List<String> words = nfkd(text).split(' ');
    final int bpp = theme.bitsPerPhrase;
    final int wpp = theme.wordsPerPhrase;
    final List<int> valid = <int>[
      for (int ent = kMinStrength; ent <= kMaxStrength; ent += kStrengthStep)
        (ent + ent ~/ kStrengthStep) ~/ bpp * wpp,
    ];
    if (!valid.contains(words.length)) return false;
    try {
      toEntropy(words);
      return true;
    } on FormatException {
      return false;
    }
  }

  /// The bits of each word's index, sentence after sentence.
  List<int> _indexBits(List<String> words) {
    final List<int> indexes = theme.phraseIndexes(words);
    final List<int> lengths = theme.bitsFillSequence;
    return <int>[
      for (int i = 0; i < indexes.length; i++)
        for (int b = lengths[i % lengths.length] - 1; b >= 0; b--)
          (indexes[i] >> b) & 1,
    ];
  }

  /// The first [n] letters of [word] (NFC, so an accented letter is one),
  /// or the word and [_kPad] when it is shorter.
  static String firstLetters(String word, int n) {
    final List<int> letters = nfc(word).runes.toList();
    return letters.length >= n
        ? String.fromCharCodes(letters.take(n))
        : '${String.fromCharCodes(letters)}$_kPad';
  }

  /// Letters of each word in this theme's password.
  int get passwordLetters =>
      isBip39Theme ? _kBip39PasswordLetters : _kThemePasswordLetters;

  /// The password (the first letters of every word) on the first line, then
  /// each sentence on its own line.
  String formatMnemonic(Object mnemonic) {
    final List<String> words = Theme.normalizeMnemonic(mnemonic);
    final int n = passwordLetters;
    final int size = theme.wordsPerPhrase;
    return <String>[
      words.map((String w) => firstLetters(w, n)).join(),
      for (int p = 0; p < words.length ~/ size; p++)
        words.sublist(size * p, size * (p + 1)).join(' '),
    ].join('\n');
  }

  /// [prefix] completed to the one word of [list] (this theme's words by
  /// default) it starts, compared in NFC; else [prefix] as it is.
  String expandWord(String prefix, [List<String>? list]) {
    final List<String> words = list ?? wordlist;
    if (words.contains(prefix)) return prefix;
    final String composed = nfc(prefix);
    final List<String> matches = <String>[
      for (final String w in words)
        if (nfc(w).startsWith(composed)) w,
    ];
    return matches.length == 1 ? matches.single : prefix;
  }

  /// Every word of [mnemonic] completed as far as it is unambiguous; in a
  /// themed mnemonic, each from the list its sentence allows.
  String expand(Object mnemonic) {
    final String text =
        mnemonic is String ? mnemonic : (mnemonic as List<String>).join(' ');
    final List<String> words = nfkd(text).split(' ');
    if (isBip39Theme) return words.map(expandWord).join(' ');
    return _expandSentences(words);
  }

  String _expandSentences(List<String> words) {
    final Theme t = theme;
    final List<String> out = <String>[];
    final Set<String> leading = <String>{
      for (final (String lead, String _) in t.restrictionSequence) lead,
    };
    for (final List<String> phrase in t.sentences(words)) {
      final List<String> expanded = List<String>.filled(t.wordsPerPhrase, '');
      final List<(String, String)> pairs = t.restrictionPairs(phrase);
      for (int i = 0; i < pairs.length; i++) {
        final (String lead, String led) = t.restrictionSequence[i];
        final (String leadWord, String ledWord) = pairs[i];
        if (t.primeLeads.contains(lead)) {
          expanded[t.naturalIndex(lead)] =
              expandWord(leadWord, t.word(lead).totalWords);
        }
        final Map<String, List<String>> mapping = t.ledByMapping(led);
        final String leader = expanded[t.ledByIndex(led)];
        expanded[t.naturalIndex(led)] = mapping.containsKey(leader)
            ? expandWord(ledWord, mapping[leader])
            : ledWord;
      }
      // Prime leads that lead nothing: completed from their whole lists.
      for (final String lead in t.primeLeads) {
        if (leading.contains(lead)) continue;
        final int at = t.naturalIndex(lead);
        expanded[at] = expandWord(phrase[at], t.word(lead).totalWords);
      }
      out.addAll(expanded);
    }
    return out.join(' ');
  }

  /// The mnemonic recovered from its [password], as far as it is
  /// unambiguous; the password as it is when its length cannot be one.
  String expandPassword(String password) {
    final int n = passwordLetters;
    final List<int> letters = nfc(password).runes.toList();
    if (letters.length % n != 0) return password;
    final List<String> prefixes = <String>[
      for (int i = 0; i < letters.length; i += n)
        letters[i + n - 1] == _kPad.codeUnitAt(0)
            ? String.fromCharCodes(letters.sublist(i, i + n - 1))
            : String.fromCharCodes(letters.sublist(i, i + n)),
    ];
    return expand(prefixes.join(' '));
  }
}

/// [bytes] as bits, most significant first.
List<int> _bits(List<int> bytes) => <int>[
      for (final int b in bytes)
        for (int i = _kBitsPerByte - 1; i >= 0; i--) (b >> i) & 1,
    ];
