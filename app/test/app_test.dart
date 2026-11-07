import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:formosa/formosa.dart' as formosa;
import 'package:formosa/io.dart';
import 'package:formosa_app/main.dart';
import 'package:formosa_app/src/converter_tab.dart';
import 'package:formosa_app/src/generator.dart';
import 'package:formosa_app/src/table_selector.dart';
import 'package:formosa_app/src/themes.dart';

void main() {
  final formosa.ThemeSet themes = loadThemes(Directory('../themes'));
  formosa.Theme theme(String name) => themes[name].theme;

  group('generator', () {
    test('every theme at every size', () {
      for (final String name in themes.names) {
        final formosa.Mnemonic m = themes[name];
        final (int min, int max) = phrasesRange(bip39: m.isBip39Theme);
        for (int p = min; p <= max; p += min) {
          final String code =
              m.generate(strength: strengthOf(p, bip39: m.isBip39Theme));
          expect(m.check(code), isTrue, reason: '$name $p');
        }
      }
    });

    test('tweaks change one letter of each password, and change back', () {
      final GeneratorText g = GeneratorText();
      final formosa.Mnemonic m = themes['sci-fi'];
      for (int i = 0; i < 3; i++) {
        g.add(m.formatMnemonic(m.generate(strength: 64)), 2, <Tweak>{});
      }
      final List<String> before = g.text.split('\n');
      g.apply(Tweak.number, on: true);
      g.apply(Tweak.upper, on: true);
      final List<String> after = g.text.split('\n');
      for (final int line in g.passwordLines) {
        int changed = 0;
        for (int i = 0; i < before[line].length; i++) {
          if (before[line][i] != after[line][i]) changed++;
        }
        expect(changed, inInclusiveRange(1, 2), reason: before[line]);
      }
      g.apply(Tweak.upper, on: false);
      g.apply(Tweak.number, on: false);
      expect(g.text.split('\n'), before);
    });

    test('a password line is found after mnemonics of any size', () {
      final GeneratorText g = GeneratorText();
      final formosa.Mnemonic bip = themes['BIP39'];
      g.add(bip.formatMnemonic(bip.generate(strength: 128)), 12, <Tweak>{});
      g.add(bip.formatMnemonic(bip.generate(strength: 64)), 6, <Tweak>{});
      expect(g.passwordLines, <int>[0, 13]);
    });
  });

  group('converter', () {
    test('bad input is reported, not thrown', () {
      for (final List<String> words in <List<String>>[
        <String>[],
        <String>['nonsense'],
        <String>['a', 'b', 'c', 'd', 'e', 'f'],
      ]) {
        expect(() => convertForDisplay(themes, words, 'sci-fi', 'tourism'),
            returnsNormally);
      }
      expect(convertForDisplay(themes, <String>[], 'sci-fi', 'tourism'),
          'Empty Input');
    });

    test('a mnemonic with its password line first converts', () {
      final formosa.Mnemonic m = themes['sci-fi'];
      final String code = m.generate(strength: 64);
      final List<String> lines = m.formatMnemonic(code).split('\n');
      final List<String> words =
          lines.join(' ').split(' ').where((String w) => w.isNotEmpty).toList();
      final String out = convertForDisplay(themes, words, 'sci-fi', 'tourism');
      final String converted = themes.convertTheme(code, 'tourism');
      expect(out, themes['tourism'].formatMnemonic(converted));
    });
  });

  group('table selector', () {
    /// Type the keys written on cell [i], then confirm.
    void pick(TableSelector s, int i) {
      final String keys = s.cellKeys(i);
      for (final String k in keys.substring(0, keys.length - 1).split('')) {
        expect(s.typed(k), isTrue);
      }
      s.confirm();
    }

    test('the keys written on a cell pick that cell', () {
      final math.Random rng = math.Random(1);
      for (final String name
          in themes.names.where((String n) => !n.startsWith('BIP39'))) {
        final TableSelector s = TableSelector(theme(name), random: rng);
        for (int w = 0; w < s.naturalOrder.length; w++) {
          final List<String> words = s.words;
          final int i = rng.nextInt(words.length);
          pick(s, i);
          expect(s.picked.last, words[i], reason: name);
        }
        expect(s.complete, isTrue);
      }
    });

    test('backspace takes back the keys typed first, then the word picked last',
        () {
      final TableSelector s = TableSelector(theme('sci-fi'));
      pick(s, 3);
      expect(s.picked, hasLength(1));
      s.typed(s.cellKeys(0)[0]);
      s.back();
      expect(s.step, SelectorStep.initial);
      expect(s.picked, hasLength(1));
      s.back();
      expect(s.picked, isEmpty);
      expect(s.canGoBack, isFalse);
    });

    test('a whole phrase only can be put out', () {
      final TableSelector s = TableSelector(theme('sci-fi'));
      for (int w = 0; w < s.naturalOrder.length; w++) {
        expect(s.complete, isFalse);
        pick(s, 0);
      }
      expect(s.complete, isTrue);
      expect(s.output, '${s.picked.join(' ')} ');
    });

    test('arrows walk the phrase, wrap, and never pass the next word', () {
      final TableSelector s = TableSelector(theme('sci-fi'));
      pick(s, 0);
      pick(s, 0);
      expect(s.cursor, 2);
      s.stepWord(1);
      expect(s.cursor, 0, reason: 'wraps');
      s.stepWord(-1);
      expect(s.cursor, 2, reason: 'wraps back to the next word to pick');
    });

    test(
        'picking in the middle swaps only that word; a broken chain is flagged',
        () {
      final TableSelector s = TableSelector(theme('sci-fi'));
      for (int w = 0; w < 3; w++) {
        pick(s, 0);
      }
      final List<String> before = List<String>.of(s.picked);
      s.stepWord(1); // round to the first word
      expect(s.cursor, 0);
      pick(s, 5);
      expect(s.picked.sublist(1), before.sublist(1));
      // Whether the old chain still holds depends on the theme's lists.
      expect(s.validPhrase, s.phraseFollowsTheme());
      // Undoing the words restores a compatible phrase.
      while (s.picked.isNotEmpty) {
        s.undoLastWord();
      }
      expect(s.validity, Validity.compatible);
    });

    test('a theme change carries no words over', () {
      final TableSelector s = TableSelector(theme('sci-fi'));
      pick(s, 0);
      expect(s.themeChangeable, isFalse);
      s.setTheme(theme('tourism'));
      expect(s.picked, isEmpty);
      expect(s.themeChangeable, isTrue);
    });

    test('custom keys: eight different ones, else the defaults', () {
      final TableSelector s = TableSelector(theme('sci-fi'));
      expect(s.defineKeys('qwqerty'), 'QWERTY');
      expect(s.keys, kDefaultKeys);
      expect(s.defineKeys('qwertyuiop'), 'QWERTYUI');
      expect(s.keys, 'QWERTYUI'.split(''));
      pick(s, 9);
      expect(s.picked, hasLength(1));
    });

    test('BIP39 has no table', () {
      final TableSelector s = TableSelector(theme('BIP39'));
      expect(s.disabled, isTrue);
      expect(s.typed(s.caseless.first), isFalse);
    });

    test('the word position says where the grid stands', () {
      final TableSelector s = TableSelector(theme('sci-fi'));
      expect(s.positionLabel, 'Word 1 of 6\nSubject');
      for (int w = 0; w < 7; w++) {
        pick(s, 0);
      }
      expect(s.positionLabel, startsWith('Phrase 2, word 2 of 6'));
    });
  });

  group('window', () {
    Future<void> open(WidgetTester tester,
        {Size size = const Size(1024, 600)}) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(FormosaApp(themes: themes));
      await tester.pumpAndSettle();
    }

    testWidgets('the themes are bundled with the app',
        (WidgetTester tester) async {
      final formosa.ThemeSet bundled =
          (await tester.runAsync(() => loadBundledThemes(rootBundle)))!;
      expect(bundled.names, themes.names);
    });

    testWidgets('three tabs; Ctrl+PageDown and Ctrl+PageUp cycle them',
        (WidgetTester tester) async {
      await open(tester);
      expect(find.text('Run!'), findsOneWidget);
      Future<void> chord(LogicalKeyboardKey key) async {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(key);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();
      }

      await chord(LogicalKeyboardKey.pageDown);
      expect(find.text('Convert to theme'), findsOneWidget);
      await chord(LogicalKeyboardKey.pageDown);
      expect(find.text('Generate Phrase'), findsOneWidget);
      await chord(LogicalKeyboardKey.pageDown);
      expect(find.text('Run!'), findsOneWidget, reason: 'round again');
      await chord(LogicalKeyboardKey.pageUp);
      expect(find.text('Generate Phrase'), findsOneWidget);
    });

    testWidgets('Run! generates a mnemonic in the chosen theme',
        (WidgetTester tester) async {
      await open(tester);
      await tester.tap(find.text('Run!'));
      await tester.pump();
      final TextField box =
          tester.widget<TextField>(find.byType(TextField).last);
      final List<String> lines = box.controller!.text.trim().split('\n');
      expect(themes['BIP39'].check(lines.skip(1).join(' ')), isTrue);
    });

    testWidgets('the window fits a small screen', (WidgetTester tester) async {
      await open(tester, size: const Size(800, 500));
      for (int t = 0; t < 3; t++) {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('the table: keys typed pick the word shown',
        (WidgetTester tester) async {
      await open(tester);
      await tester.tap(find.text('Table Selector'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('BIP39').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('copy_left').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Very careful with prying eyes'));
      await tester.pump();
      // Find a cell on screen and type its keys.
      final Text cell = tester.widgetList<Text>(find.byType(Text)).firstWhere(
          (Text t) => (t.data ?? '').length > 4 && t.data![3] == '-');
      final String keys = cell.data!.substring(0, 3);
      final String word = cell.data!.substring(4);
      for (final String k in keys.split('')) {
        await tester.sendKeyEvent(
            k == ';'
                ? LogicalKeyboardKey.semicolon
                : LogicalKeyboardKey(k.toLowerCase().codeUnitAt(0)),
            character: k);
        await tester.pump();
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.textContaining('Word 2 of'), findsOneWidget);
      expect(word, isNotEmpty);
    });
  });
}
