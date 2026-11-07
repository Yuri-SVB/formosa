import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../tool/theme_handler.dart';
import '../tool/verify_theme.dart';

void main() {
  test('the theme handler builds main.json as the reference does, byte for byte', () {
    final Directory dir = Directory.systemTemp.createTempSync('formosa-edit');
    addTearDown(() => dir.deleteSync(recursive: true));
    for (final String f in <String>[kStructureFile, kMatricesFile]) {
      File('$kEditDirectory/$f').copySync('${dir.path}/$f');
    }
    buildTheme(dir);
    expect(File('${dir.path}/$kOutputFile').readAsStringSync(),
        File('$kEditDirectory/$kOutputFile').readAsStringSync());
  });

  test('a theme written back reads as written', () {
    final String text = File('$kEditDirectory/$kOutputFile').readAsStringSync();
    expect(encodeTheme(jsonDecode(text) as Map<String, Object?>), text);
  });

  test('a word swap: the word replaced, its lists kept in order', () {
    final Directory dir = Directory.systemTemp.createTempSync('formosa-swap');
    addTearDown(() => dir.deleteSync(recursive: true));
    final String file = '${dir.path}/sci-fi.json';
    File('themes/sci-fi.json').copySync(file);
    wordSwap(file, 'augmented_reality', 'PLACE', 'admiral', 'WILDCARD', 'asteroid');
    final Map<String, Object?> t =
        jsonDecode(File(file).readAsStringSync()) as Map<String, Object?>;
    final List<String> list = (((t['WILDCARD']! as Map)['PLACE']! as Map)['MAPPING']!
            as Map)['admiral']
        .cast<String>();
    expect(list, contains('augmented_reality'));
    expect(list, isNot(contains('asteroid')));
    expect(list, List<String>.of(list)..sort());
    expect(() => verifyTheme(t, name: 'sci-fi'), returnsNormally);
    // A word that is not one of the theme's places is refused.
    expect(
        () => wordSwap(file, 'not_a_place', 'PLACE', 'admiral', 'WILDCARD', 'augmented_reality'),
        throwsA(isA<ConfigurationError>()));
  });

  group('verifier', () {
    final Map<String, Object?> fixture = jsonDecode(
            File('python/tests/theme_test/test_verifier.json').readAsStringSync())
        as Map<String, Object?>;
    final Map<String, Object?> ok = (fixture['main_test_ok']! as Map).cast<String, Object?>();

    test('a good theme passes', () {
      expect(() => verifyTheme(ok), returnsNormally);
    });

    for (final String key in fixture.keys.where((String k) => k != 'main_test_ok')) {
      test('$key fails', () {
        final Map<String, Object?> bad = Map<String, Object?>.of(ok)
          ..addAll((fixture[key]! as Map).cast<String, Object?>());
        expect(() => verifyTheme(bad), throwsA(isA<VerificationFailed>()));
      });
    }

    test('every theme passes', () {
      for (final FileSystemEntity f in Directory('themes').listSync()) {
        if (f is! File || !f.path.endsWith('.json')) continue;
        final String name = f.uri.pathSegments.last.replaceAll('.json', '');
        expect(
            () => verifyTheme(jsonDecode(f.readAsStringSync()) as Map<String, Object?>,
                name: name),
            returnsNormally,
            reason: name);
      }
    });
  });

  test('the terminal: a mnemonic from a Dragon Dice digest', () {
    const String digest =
        'c27639eb557b8258948d9cd8a65c706688e8feccc4f662252c186225a7c79cf7'
        '0824920ae00ee5ba62bc3065212edf12c063d97b8c55aae977387eb2ed0d10c0';
    final ProcessResult r = Process.runSync(
        Platform.resolvedExecutable, <String>['run', 'bin/formosa.dart', 'sci-fi', '32', '--digest', digest]);
    expect(r.exitCode, 0, reason: '${r.stderr}');
    expect((r.stdout as String).trim(),
        'enshdarejumo\nengineer shut_down dark_matter recorder jupiterian mothership');
  });
}
