import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:formosa/formosa.dart' show Mnemonic;
import 'package:path_provider/path_provider.dart';

import 'generator.dart';

/// The file Save writes, in the app's documents folder. Plain text: the
/// mnemonics in it are secrets.
const String kOutputFile = 'formosa-output.txt';

/// The Password Generator: mnemonics of the chosen size, their passwords
/// tweaked if asked, gathered in one text.
class GeneratorTab extends StatefulWidget {
  const GeneratorTab({super.key, required this.mnemonic});

  final Mnemonic mnemonic;

  @override
  State<GeneratorTab> createState() => _GeneratorTabState();
}

class _GeneratorTabState extends State<GeneratorTab> {
  final GeneratorText _text = GeneratorText();
  final TextEditingController _box = TextEditingController();
  final Set<Tweak> _tweaks = <Tweak>{};
  late int _phrases = _range.$1;
  bool _copied = false;
  String? _saved;

  bool get _bip39 => widget.mnemonic.isBip39Theme;
  (int, int) get _range => phrasesRange(bip39: _bip39);

  @override
  void didUpdateWidget(GeneratorTab old) {
    super.didUpdateWidget(old);
    if (old.mnemonic.name != widget.mnemonic.name) {
      _phrases = _range.$1;
    }
  }

  @override
  void dispose() {
    _box.dispose();
    super.dispose();
  }

  void _show() {
    _box.text = _text.text;
    Clipboard.setData(ClipboardData(text: _text.text));
    _copied = true;
  }

  void _run() {
    _append(widget.mnemonic
        .generate(strength: strengthOf(_phrases, bip39: _bip39)));
  }

  void _append(String words) {
    setState(() {
      _saved = null;
      _text.add(widget.mnemonic.formatMnemonic(words), _phrases, _tweaks);
      _show();
    });
  }

  void _toggle(Tweak t, bool on) {
    setState(() {
      on ? _tweaks.add(t) : _tweaks.remove(t);
      _text.apply(t, on: on);
      _show();
    });
  }

  /// One step of the phrases, wrapping around like the reference's spin box.
  void _stepPhrases(int by) {
    final (int min, int max) = _range;
    setState(() {
      int next = _phrases + by * min;
      if (next > max) next = min;
      if (next < min) next = max;
      _phrases = next;
    });
  }

  Future<void> _save() async {
    final Directory dir = await getApplicationDocumentsDirectory();
    final File out = File('${dir.path}${Platform.pathSeparator}$kOutputFile');
    await out.writeAsString(_text.text);
    if (mounted) setState(() => _saved = out.path);
  }

  @override
  Widget build(BuildContext context) {
    final TextStyle? note = Theme.of(context).textTheme.bodySmall;
    const Map<Tweak, String> names = <Tweak, String>{
      Tweak.upper: 'Include Uppercase',
      Tweak.special: 'Include Special Character',
      Tweak.number: 'Include Number',
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SizedBox(
          width: 260,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                FilledButton(onPressed: _run, child: const Text('Run!')),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: _text.text));
                    setState(() => _copied = true);
                  },
                  child: const Text('Copy'),
                ),
                if (_copied) Text('Copied to clipboard', style: note),
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    IconButton(
                      tooltip: 'Fewer',
                      onPressed: () => _stepPhrases(-1),
                      icon: const Icon(Icons.remove),
                    ),
                    Expanded(
                      child: Text(
                        '$_phrases ${_bip39 ? 'words' : 'phrases'}',
                        textAlign: TextAlign.center,
                      ),
                    ),
                    IconButton(
                      tooltip: 'More',
                      onPressed: () => _stepPhrases(1),
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
                for (final MapEntry<Tweak, String> e in names.entries)
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(e.value),
                    value: _tweaks.contains(e.key),
                    onChanged: (bool? on) => _toggle(e.key, on ?? false),
                  ),
                OutlinedButton(
                  onPressed: () => setState(() => _box.text = _text.text),
                  child: const Text('Redo'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () => setState(() {
                    _text.clear();
                    _box.clear();
                    _copied = false;
                    _saved = null;
                  }),
                  child: const Text('Clear'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(onPressed: _save, child: const Text('Save')),
                if (_saved != null) Text('Saved to $_saved', style: note),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: TextField(
            controller: _box,
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            style: const TextStyle(fontFamily: 'monospace'),
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
        ),
      ],
    );
  }
}
