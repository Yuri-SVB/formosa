/// Checks that a theme follows the Formosa standard — the port of the
/// reference implementation's `Verifier` (tests/test_theme_verify.py).
///
/// ```sh
/// dart run tool/verify_theme.dart [THEME.json ...]   # every theme by default
/// ```
library;

import 'dart:convert';
import 'dart:io';

import 'package:formosa/formosa.dart';

/// A theme that breaks the standard.
class VerificationFailed implements Exception {
  VerificationFailed(this.message);

  final String message;

  @override
  String toString() => 'VerificationFailed: $message';
}

typedef Json = Map<String, Object?>;

/// The themes folder checked by default.
const String kThemesDirectory = 'themes';

void main(List<String> args) {
  final List<File> files = args.isEmpty
      ? (Directory(kThemesDirectory)
              .listSync()
              .whereType<File>()
              .where((File f) => f.path.endsWith('.json'))
              .toList()
            ..sort((File a, File b) => a.path.compareTo(b.path)))
      : args.map(File.new).toList();
  for (final File f in files) {
    final String name = f.uri.pathSegments.last.replaceAll('.json', '');
    try {
      verifyTheme(jsonDecode(f.readAsStringSync()) as Json, name: name);
      stdout.writeln('$name: ok');
    } on VerificationFailed catch (e) {
      stdout.writeln('$name: ${e.message}');
      exitCode = 1;
    }
  }
}

List<String> _list(Object? v) => v is List ? v.cast<String>() : const <String>[];
Json _dict(Object? v) => v is Map ? v.cast<String, Object?>() : const <String, Object?>{};

/// Throws a [VerificationFailed] where [theme] breaks the standard.
void verifyTheme(Json theme, {String name = ''}) {
  final bool bip39 = name.startsWith(kDefaultTheme);
  final List<String> filling = _list(theme[ThemeKey.fillingOrder]);
  Json dict(String key) => _dict(theme[key]);
  List<String> leadsOf(String key) => _list(dict(key)[ThemeKey.leads]);
  List<String> totalOf(String key) => _list(dict(key)[ThemeKey.totalList]);
  int bitsOf(String key) => (dict(key)[ThemeKey.bitLength] as int?) ?? 0;
  final List<String> primes = <String>[
    for (final String w in filling)
      if (dict(w)[ThemeKey.ledBy] == ThemeKey.none) w,
  ];

  for (final String word in filling) {
    String restriction = '';
    Json led() => _dict(dict(word)[restriction]);
    Map<String, List<String>> mapping() => <String, List<String>>{
          for (final MapEntry<String, Object?> e in _dict(led()[ThemeKey.mapping]).entries)
            e.key: _list(e.value),
        };

    void unicity(List<String> list) {
      final int n = bip39 ? 4 : 2;
      final Set<String> unique = <String>{
        for (final String w in list) Mnemonic.firstLetters(w, n),
      };
      if (unique.length != list.length && list.isNotEmpty) {
        throw VerificationFailed('The list of ${restriction.toLowerCase()}s in '
            'the ${word.toLowerCase()} has no unicity.');
      }
    }

    void generalUnicity() {
      if (primes.contains(word)) unicity(totalOf(word));
      for (final List<String> list in mapping().values) {
        unicity(list);
      }
    }

    void spaceInTotals() {
      if (totalOf(word).join().contains(' ')) {
        throw VerificationFailed('Space character found in ${word.toLowerCase()}');
      }
    }

    void spaceInSublist(String key) {
      if (mapping()[key]!.join().contains(' ')) {
        throw VerificationFailed(
            'Space character found in sublist of ${word.toLowerCase()} $key');
      }
    }

    // Filling sequence.
    final String restrictBy = (dict(word)[ThemeKey.ledBy] as String?) ?? '';
    if (restrictBy != ThemeKey.none) {
      if (!filling.contains(restrictBy) || !filling.contains(word)) {
        throw VerificationFailed('The filling order list is incomplete.');
      }
      if (filling.indexOf(restrictBy) >= filling.indexOf(word)) {
        throw VerificationFailed('List sequence has inconsistent restriction '
            'order for $restrictBy and $word.');
      }
    }
    // Restriction sequence.
    for (final String r in leadsOf(word)) {
      for (final String next in leadsOf(r)) {
        if (filling.indexOf(r) >= filling.indexOf(next)) {
          throw VerificationFailed(
              'List sequence inconsistent restriction order for $word.');
        }
      }
    }
    // Enough words.
    final int addressable = 1 << bitsOf(word);
    if (totalOf(word).length < addressable) {
      throw VerificationFailed('The total words of ${word.toLowerCase()} are '
          'not enough for the theme, it should have $addressable words but it '
          'has ${totalOf(word).length} words.');
    }
    spaceInTotals();

    for (final String r in leadsOf(word)) {
      restriction = r;
      // Every word of the image leads lists of its own.
      final List<Iterable<String>> nextKeys = <Iterable<String>>[
        for (final String nr in leadsOf(r)) _dict(_dict(dict(r)[nr])[ThemeKey.mapping]).keys,
      ];
      for (final String w in _list(led()[ThemeKey.image])) {
        for (final Iterable<String> keys in nextKeys) {
          if (!keys.contains(w)) {
            throw VerificationFailed('A word from the image list of $r led by '
                '$word is not contained in the mapping keys list');
          }
        }
      }
      // Every key is a word of this one.
      if (!mapping().keys.every(totalOf(word).contains)) {
        throw VerificationFailed('All keys should be listed in totals, but it '
            'is not, a key in dictionary of $r is not in total of $word keys.');
      }
      // Enough keys.
      if (mapping().length < addressable) {
        throw VerificationFailed('The dictionary of $word should contain '
            '$addressable keys words in $r list, but it contains '
            '${mapping().length} keys words.');
      }
      // Each list: whole, of words of the led one, without spaces.
      final int lineLength = 1 << bitsOf(r);
      for (final MapEntry<String, List<String>> e in mapping().entries) {
        final int size = e.value.toSet().length;
        if (size != lineLength) {
          throw VerificationFailed('Key ${e.key}, in $r restriction, should '
              'contain $lineLength words, but it contains $size words.');
        }
        if (e.value.any((String w) => !totalOf(r).contains(w))) {
          throw VerificationFailed('A word from $word dictionary is not found '
              'in list of total words in $r.');
        }
        spaceInSublist(e.key);
      }
      generalUnicity();
      // No spaces anywhere.
      spaceInTotals();
      final bool spaceInImage = _list(led()[ThemeKey.image]).join().contains(' ');
      final bool spaceInKeys = mapping().keys.join().contains(' ');
      if (spaceInImage || spaceInKeys) {
        throw VerificationFailed('Space character found in ${word.toLowerCase()}');
      }
      for (final String key in mapping().keys) {
        spaceInSublist(key);
      }
      generalUnicity();
    }
  }
}
