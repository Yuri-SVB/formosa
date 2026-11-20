import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:formosa/formosa.dart' as formosa;
import 'package:formosa/io.dart';
import 'package:formosa_ui/formosa_ui.dart';

/// The Table Selector (Moon Cake) on its own, as another app embeds it.
void main() {
  final formosa.ThemeSet themes = loadThemes(Directory('../themes'));

  testWidgets('keys typed pick the word shown', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TableTab(
          theme: themes['copy_left'].theme,
          page: (Widget body, {bool themeEnabled = true}) => body,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Very careful with prying eyes'));
    await tester.pump();
    final Text cell = tester.widgetList<Text>(find.byType(Text)).firstWhere(
        (Text t) => (t.data ?? '').length > 4 && t.data![3] == '-');
    for (final String k in cell.data!.substring(0, 3).split('')) {
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
  });

  testWidgets('with onPhrase, the phrase goes to the host, not the clipboard',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    String? got;
    final formosa.Theme theme = themes['copy_left'].theme;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TableTab(
          theme: theme,
          page: (Widget body, {bool themeEnabled = true}) => body,
          onPhrase: (String p) => got = p,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Use phrase'), findsOneWidget);
    // Pick a whole sentence: each word by the keys of a cell shown.
    for (int w = 0; w < theme.wordsPerPhrase; w++) {
      final Text cell = tester.widgetList<Text>(find.byType(Text)).firstWhere(
          (Text t) => (t.data ?? '').length > 4 && t.data![3] == '-');
      for (final String k in cell.data!.substring(0, 3).split('')) {
        await tester.sendKeyEvent(
            k == ';'
                ? LogicalKeyboardKey.semicolon
                : LogicalKeyboardKey(k.toLowerCase().codeUnitAt(0)),
            character: k);
        await tester.pump();
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('Use phrase'));
    await tester.pump();
    expect(got, isNotNull);
    expect(got!.split(' '), hasLength(theme.wordsPerPhrase));
  });
}
