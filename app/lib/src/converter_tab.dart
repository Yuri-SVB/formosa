import 'package:flutter/material.dart';
import 'package:formosa/formosa.dart';

/// [words] (of theme [base]) in theme [target], formatted; else why not —
/// as the reference window does it, which also tries the words without the
/// first, in case it is a password line.
String convertForDisplay(
    ThemeSet themes, List<String> words, String base, String target) {
  if (words.isEmpty) return 'Empty Input';
  final Mnemonic from = themes[base];
  final Mnemonic to = themes[target];
  String convert(List<String> w) =>
      to.formatMnemonic(themes.convertTheme(w, target, currentTheme: base));
  try {
    return convert(words);
  } on FormatException catch (first) {
    try {
      return convert(words.sublist(1));
    } on Object catch (error) {
      final int phrase = from.theme.wordsPerPhrase;
      final bool passwordFirst = words.length % phrase == 1 &&
          words.first.length == from.passwordLetters * (words.length - 1);
      return passwordFirst ? _message(error) : first.message;
    }
  } on Object catch (unexpected) {
    return 'Something unexpected went wrong\n${_message(unexpected)}';
  }
}

String _message(Object e) => e is FormatException ? e.message : '$e';

/// The Theme Converter: a mnemonic in the chosen theme, written in another.
class ConverterTab extends StatefulWidget {
  const ConverterTab({
    super.key,
    required this.themes,
    required this.order,
    required this.base,
  });

  final ThemeSet themes;
  final List<String> order;

  /// The theme the mnemonic given is in.
  final String base;

  @override
  State<ConverterTab> createState() => _ConverterTabState();
}

class _ConverterTabState extends State<ConverterTab> {
  final TextEditingController _input = TextEditingController();
  final TextEditingController _output = TextEditingController();
  late String _target = widget.base;

  @override
  void dispose() {
    _input.dispose();
    _output.dispose();
    super.dispose();
  }

  void _convert() {
    final List<String> words = _input.text
        .replaceAll('\n', ' ')
        .split(' ')
        .where((String w) => w.isNotEmpty)
        .toList();
    setState(() => _output.text =
        convertForDisplay(widget.themes, words, widget.base, _target));
  }

  Widget _box(TextEditingController c, String label) => TextField(
        controller: c,
        maxLines: null,
        expands: true,
        textAlignVertical: TextAlignVertical.top,
        decoration: InputDecoration(
          border: const OutlineInputBorder(),
          labelText: label,
          alignLabelWithHint: true,
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(child: _box(_input, 'Mnemonic in ${widget.base}')),
              const SizedBox(width: 12),
              Expanded(child: _box(_output, 'In $_target')),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            Expanded(
              child: FilledButton(
                onPressed: _convert,
                child: const Text('Convert to theme'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButton<String>(
                value: _target,
                isExpanded: true,
                items: <DropdownMenuItem<String>>[
                  for (final String n in widget.order)
                    DropdownMenuItem<String>(value: n, child: Text(n)),
                ],
                onChanged: (String? n) =>
                    setState(() => _target = n ?? _target),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
