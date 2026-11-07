import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:formosa/formosa.dart';
import 'package:formosa/io.dart';
import 'package:test/test.dart';

String _hex(List<int> b) =>
    b.map((int x) => x.toRadixString(16).padLeft(2, '0')).join();

Uint8List _bytes(String hex) => Uint8List.fromList(<int>[
      for (int i = 0; i < hex.length; i += 2)
        int.parse(hex.substring(i, i + 2), radix: 16),
    ]);

void main() {
  final ThemeSet themes = loadThemes(packageThemes());

  group('vectors (shared with the Python reference)', () {
    final Map<String, Object?> vectors =
        jsonDecode(File('vectors.json').readAsStringSync()) as Map<String, Object?>;
    for (final String theme in vectors.keys) {
      test(theme, () {
        final Mnemonic m = themes[theme];
        for (final Object? v in vectors[theme]! as List<Object?>) {
          final List<String> row = (v! as List<Object?>).cast<String>();
          final String code = m.toMnemonic(_bytes(row[0]));
          expect(code, row[1]);
          expect(m.check(row[1]), isTrue);
          expect(_hex(m.toEntropy(code)), row[0]);
          final Uint8List seed = themes.toSeed(code, passphrase: 'TREZOR');
          expect(_hex(seed), row[2]);
          expect(hdMasterKey(seed), row[3]);
        }
      });
    }
  });

  test('every theme in the vectors', () {
    final Map<String, Object?> vectors =
        jsonDecode(File('vectors.json').readAsStringSync()) as Map<String, Object?>;
    expect(vectors.keys.toSet(), themes.names.toSet());
  });

  test('failed checksum', () {
    expect(
        themes['BIP39'].check(
            'bless cloud wheel regular tiny venue bird web grief security dignity zoo'),
        isFalse);
  });

  test('detection', () {
    expect(themes.detectTheme('security'), 'BIP39');
    expect(() => themes.detectTheme('jaguar xxxxxxx'), throwsA(isA<ThemeNotFound>()));
    expect(() => themes.detectTheme('jaguar jaguar'), throwsA(isA<ThemeAmbiguous>()));
    expect(themes.detectTheme('jaguar security'), 'BIP39');
    expect(themes.detectTheme('jaguar aboyer'), 'BIP39_french');
  });

  test('UTF-8 normal forms give one seed', () {
    const String wordsNfkd =
        'Příšerně žluťoučký kůň úpěl ďábelské ódy zákeřný učeň běží podél zóny úlů';
    const String wordsNfc =
        'Př\xedšerně žluťoučk\xfd kůň \xfapěl ď\xe1belsk\xe9 \xf3dy z\xe1keřn\xfd učeň běž\xed pod\xe9l z\xf3ny \xfalů';
    const String passNfkd =
        'Neuvěřitelně bezpečné heslíčko';
    const String passNfc = 'Neuvěřitelně bezpečn\xe9 hesl\xedčko';
    expect(themes.toSeed(wordsNfkd, passphrase: passNfkd),
        themes.toSeed(wordsNfc, passphrase: passNfc));
  });

  test('to entropy and back', () {
    final math.Random rng = math.Random(1);
    final Mnemonic m = themes['BIP39'];
    for (int i = 0; i < 256; i++) {
      final Uint8List d = Uint8List.fromList(
          List<int>.generate(32, (_) => rng.nextInt(256)));
      expect(m.toEntropy(m.toMnemonic(d).split(' ')), d);
    }
    final Uint8List lorem = Uint8List.fromList(utf8.encode('Lorem ipsum dolor sit amet amet.'));
    expect(m.toEntropy(m.toMnemonic(lorem)), lorem);
  });

  test('expand a word', () {
    final Mnemonic m = themes['BIP39'];
    expect(m.expandWord(''), '');
    expect(m.expandWord(' '), ' ');
    expect(m.expandWord('access'), 'access');
    expect(m.expandWord('acce'), 'access');
    expect(m.expandWord('acb'), 'acb');
    expect(m.expandWord('acc'), 'acc');
    expect(m.expandWord('act'), 'act');
    expect(m.expandWord('acti'), 'action');
    expect(m.expand('access'), 'access');
    expect(m.expand('access acce acb acc act acti'),
        'access access acb acc act action');
  });

  const List<String> entropies = <String>[
    '00000000000000000000000000000000',
    '7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f',
    'ffffffffffffffffffffffffffffffff',
    'f585c11aec520db57dd353c69554b21a89b20fb0650966fa0a9d6f74fd989d8f',
  ];

  test('the seed is the same in every theme', () {
    for (final String e in entropies) {
      final Uint8List expected = themes.toSeed(
          themes['BIP39'].toMnemonic(_bytes(e)), passphrase: 'TREZOR');
      for (final String theme in themes.names) {
        if (theme.startsWith(kDefaultTheme)) continue;
        expect(themes.toSeed(themes[theme].toMnemonic(_bytes(e)), passphrase: 'TREZOR'),
            expected, reason: '$theme $e');
      }
    }
  });

  test('themes sharing every word are told apart by the checksum', () {
    final Mnemonic m = themes['medieval_fantasy_light'];
    for (int i = 0; i < 32; i++) {
      expect(themes.toSeed(m.generate()), hasLength(kSeedBytes));
    }
  });

  test('a strength that cannot be encoded is refused', () {
    final Mnemonic m = themes['BIP39'];
    for (final int s in <int>[0, 31, 100, 264, 300]) {
      expect(() => m.generate(strength: s), throwsArgumentError);
    }
    for (final int s in <int>[32, 64, 128, 256]) {
      expect(m.check(m.generate(strength: s)), isTrue);
    }
  });

  test('every theme round-trips: entropy, checksum, completion, password', () {
    for (final String theme in themes.names) {
      final Mnemonic m = themes[theme];
      for (final String e in entropies) {
        final String code = m.toMnemonic(_bytes(e));
        expect(code, isNot(contains('  ')));
        expect(m.check(code), isTrue, reason: theme);
        expect(_hex(m.toEntropy(code)), e);
        expect(m.expand(code), code);
        final String password = m.formatMnemonic(code).split('\n').first;
        expect(m.expandPassword(password), code, reason: '$theme $password');
      }
    }
  });

  test('words hold no space', () {
    for (final String theme in themes.names) {
      expect(themes[theme].wordlist.where((String w) => w.contains(' ')), isEmpty);
    }
  });

  test('every mapped word is addressable', () {
    for (final String name in themes.names) {
      final Theme t = themes[name].theme;
      for (final String key in t.fillingOrder) {
        if (t.primeLeads.contains(key)) continue;
        final int addressable = 1 << t.word(key).bitLength;
        for (final List<String> words in t.ledByMapping(key).values) {
          expect(words, hasLength(addressable), reason: '$name $key');
        }
      }
    }
  });

  test('theme conversion keeps the entropy', () {
    final String code = themes['sci-fi'].toMnemonic(_bytes(entropies[3]));
    final String converted = themes.convertTheme(code, 'tourism');
    expect(themes.detectTheme(converted), 'tourism');
    expect(_hex(themes['tourism'].toEntropy(converted)), entropies[3]);
  });
}
