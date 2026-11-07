import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:formosa/formosa.dart';

import 'src/converter_tab.dart';
import 'src/generator_tab.dart';
import 'src/table_tab.dart';
import 'src/themes.dart';

/// Where unexpected errors are written, as the reference window does.
String get errorLog =>
    '${Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '.'}'
    '${Platform.pathSeparator}.formosa_error.log';

final GlobalKey<ScaffoldMessengerState> _messenger =
    GlobalKey<ScaffoldMessengerState>();

void main() {
  // An error is reported, written down and survived: the window stays.
  void report(Object error, StackTrace? stack) {
    try {
      File(errorLog)
          .writeAsStringSync('$error\n$stack\n', mode: FileMode.append);
    } on Object {
      // Nothing more to do: the error is still shown.
    }
    _messenger.currentState?.showSnackBar(SnackBar(
      content: Text('Something went wrong: $error\nWritten to $errorLog'),
    ));
  }

  FlutterError.onError = (FlutterErrorDetails d) {
    FlutterError.presentError(d);
    report(d.exception, d.stack);
  };
  runZonedGuarded(() => runApp(const FormosaApp()), report);
}

class FormosaApp extends StatelessWidget {
  const FormosaApp({super.key, this.themes});

  /// The themes to use instead of the bundled ones (tests).
  final ThemeSet? themes;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Formosa',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: _messenger,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.teal),
      home: themes != null
          ? FormosaWindow(themes: themes!)
          : FutureBuilder<ThemeSet>(
              future: loadBundledThemes(rootBundle),
              builder: (BuildContext context, AsyncSnapshot<ThemeSet> s) {
                if (s.hasError) {
                  return Scaffold(body: Center(child: Text('${s.error}')));
                }
                if (!s.hasData) {
                  return const Scaffold(
                      body: Center(child: CircularProgressIndicator()));
                }
                return FormosaWindow(themes: s.data!);
              },
            ),
    );
  }
}

/// The window: the three tabs, sharing one theme.
class FormosaWindow extends StatefulWidget {
  const FormosaWindow({super.key, required this.themes});

  final ThemeSet themes;

  @override
  State<FormosaWindow> createState() => _FormosaWindowState();
}

class _FormosaWindowState extends State<FormosaWindow>
    with SingleTickerProviderStateMixin {
  late final List<String> _order = windowOrder(widget.themes);
  late String _theme = _order.first;
  late final TabController _tabs = TabController(length: 3, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _setTheme(String name) => setState(() => _theme = name);

  void _stepTab(int by) => _tabs.animateTo((_tabs.index + by) % _tabs.length);

  /// The theme chooser each tab shows on top; [enabled] false freezes it.
  Widget _themeChooser({bool enabled = true}) => DropdownButton<String>(
        value: _theme,
        isExpanded: true,
        items: <DropdownMenuItem<String>>[
          for (final String n in _order)
            DropdownMenuItem<String>(value: n, child: Text(n)),
        ],
        onChanged: enabled ? (String? n) => _setTheme(n ?? _theme) : null,
      );

  Widget _page(Widget body, {bool themeEnabled = true}) => Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _themeChooser(enabled: themeEnabled),
            const SizedBox(height: 8),
            Expanded(child: body),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                  onPressed: () => exit(0), child: const Text('Exit')),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final Mnemonic mnemonic = widget.themes[_theme];
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.pageUp, control: true): () =>
            _stepTab(-1),
        const SingleActivator(LogicalKeyboardKey.pageDown, control: true): () =>
            _stepTab(1),
      },
      // A focus of the window's own, so the shortcuts work before anything
      // else has the focus.
      child: Focus(
        autofocus: true,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Formosa'),
            bottom: TabBar(
              controller: _tabs,
              tabs: const <Widget>[
                Tab(text: 'Password Generator'),
                Tab(text: 'Theme Converter'),
                Tab(text: 'Table Selector'),
              ],
            ),
          ),
          body: TabBarView(
            controller: _tabs,
            physics: const NeverScrollableScrollPhysics(),
            children: <Widget>[
              _page(GeneratorTab(mnemonic: mnemonic)),
              _page(ConverterTab(
                  themes: widget.themes, order: _order, base: _theme)),
              TableTab(theme: mnemonic.theme, page: _page),
            ],
          ),
        ),
      ),
    );
  }
}
