import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:formosa/formosa.dart' as formosa;

import 'table_selector.dart';

/// The reference window's colours: a phrase that follows the theme, a word
/// that would not, a phrase that does not.
const Color kCompatible = Color(0xFF3AC73A);
const Color kCandidateIncompatible = Color(0xFFFFFF99);
const Color kIncompatible = Color(0xFFFF4040);

/// The grid's font sizes: never below [_kSmallestFont], never above
/// [_kLargestFont]; a row's text takes [_kRowFill] of its height.
const double _kSmallestFont = 4;
const double _kLargestFont = 14;
const double _kRowFill = 0.7;

/// Width of the panel beside the grid.
const double _kPanelWidth = 200;

/// The Table Selector tab: pick a theme's words on a grid by typing keys
/// shuffled anew for every word.
class TableTab extends StatefulWidget {
  const TableTab({
    super.key,
    required this.theme,
    required this.page,
  });

  final formosa.Theme theme;
  final Widget Function(Widget body, {bool themeEnabled}) page;

  @override
  State<TableTab> createState() => _TableTabState();
}

class _TableTabState extends State<TableTab> {
  late final TableSelector _selector = TableSelector(widget.theme);
  final FocusNode _grid = FocusNode(debugLabel: 'table-grid');
  final TextEditingController _keys = TextEditingController();
  bool _highlight = false;
  bool _customKeys = false;
  bool _copied = false;

  @override
  void didUpdateWidget(TableTab old) {
    super.didUpdateWidget(old);
    if (old.theme.name != widget.theme.name) {
      _selector.setTheme(widget.theme);
      _copied = false;
    }
  }

  @override
  void dispose() {
    _grid.dispose();
    _keys.dispose();
    super.dispose();
  }

  void _act(VoidCallback f) {
    setState(f);
    _grid.requestFocus();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || _selector.disabled) {
      return KeyEventResult.ignored;
    }
    final LogicalKeyboardKey k = event.logicalKey;
    final String? c = event.character;
    if (k == LogicalKeyboardKey.backspace) {
      setState(_selector.back);
    } else if (k == LogicalKeyboardKey.arrowLeft) {
      setState(() => _selector.stepWord(-1));
    } else if (k == LogicalKeyboardKey.arrowRight) {
      setState(() => _selector.stepWord(1));
    } else if (c != null &&
        _selector.caseless.contains(c) &&
        _selector.step != SelectorStep.paragraphDone) {
      setState(() => _selector.typed(c));
    } else if ((k == LogicalKeyboardKey.escape ||
            k == LogicalKeyboardKey.delete) &&
        _selector.step != SelectorStep.initial) {
      setState(_selector.restart);
    } else if ((k == LogicalKeyboardKey.enter ||
            k == LogicalKeyboardKey.numpadEnter ||
            k == LogicalKeyboardKey.space) &&
        _selector.step == SelectorStep.paragraphDone) {
      setState(_selector.confirm);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  Color get _validityColor => switch (_selector.validity) {
        Validity.compatible => kCompatible,
        Validity.candidateIncompatible => kCandidateIncompatible,
        Validity.incompatible => kIncompatible,
      };

  Widget _panel(BuildContext context) {
    final bool on = !_selector.disabled;
    final TableSelector s = _selector;
    return SizedBox(
      width: _kPanelWidth,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            OutlinedButton(
                onPressed: on ? () => _act(s.reset) : null,
                child: const Text('Reset')),
            const SizedBox(height: 6),
            OutlinedButton(
              onPressed: on && s.canGoBack ? () => _act(s.back) : null,
              child: const Text('Back (Backspace)'),
            ),
            const SizedBox(height: 6),
            Text(on ? s.positionLabel : ''),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(6),
              color: on ? _validityColor : null,
              child: Text(
                s.validity == Validity.incompatible
                    ? 'Incompatible phrase'
                    : 'Selected phrase so far is compatible',
                style: const TextStyle(color: Colors.black),
              ),
            ),
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('Show highlight'),
              value: _highlight,
              onChanged:
                  on ? (bool? v) => _act(() => _highlight = v ?? false) : null,
            ),
            const Text('Very careful with prying eyes',
                style: TextStyle(color: Colors.red)),
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('Use custom set of keys'),
              value: _customKeys,
              onChanged: on
                  ? (bool? v) => setState(() {
                        _customKeys = v ?? false;
                        if (!_customKeys) {
                          _keys.clear();
                          s.useKeys(kDefaultKeys);
                          _grid.requestFocus();
                        }
                      })
                  : null,
            ),
            TextField(
              controller: _keys,
              enabled: on && _customKeys,
              decoration: const InputDecoration(
                isDense: true,
                labelText: '$kGridSide keys',
              ),
              onChanged: (String typed) => setState(() {
                final String kept = s.defineKeys(typed);
                if (kept != typed) {
                  _keys.value = TextEditingValue(
                    text: kept,
                    selection: TextSelection.collapsed(offset: kept.length),
                  );
                }
                if (kept.length == kGridSide) _grid.requestFocus();
              }),
            ),
            const SizedBox(height: 6),
            FilledButton(
              onPressed: on && s.complete
                  ? () {
                      Clipboard.setData(ClipboardData(text: s.output));
                      _act(() => _copied = true);
                    }
                  : null,
              child: const Text('Generate Phrase'),
            ),
            if (_copied) const Text('Copied to clipboard'),
          ],
        ),
      ),
    );
  }

  Widget _table(BuildContext context) {
    final TableSelector s = _selector;
    if (s.disabled) {
      return const Center(
        child: Text('The Table Selector picks the words of a Formosa theme: '
            'BIP39 words have no sentences to follow.'),
      );
    }
    final List<String> words = s.words;
    final int rows = 1 + s.paragraphs * kGridSide;
    return LayoutBuilder(builder: (BuildContext context, BoxConstraints box) {
      final double rowHeight = box.maxHeight / rows;
      final double font =
          (rowHeight * _kRowFill).clamp(_kSmallestFont, _kLargestFont);
      final TextStyle style =
          TextStyle(fontSize: font, height: 1, color: Colors.black);
      Widget cell(String text, {Color? background}) => Container(
            height: rowHeight,
            color: background,
            alignment: Alignment.centerLeft,
            child: Text(text,
                style: style, maxLines: 1, overflow: TextOverflow.ellipsis),
          );
      final Color highlightColor = _validityColor;
      return Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: cell('')),
              for (int c = 0; c < kGridSide; c++)
                Expanded(child: cell(s.columnKeys[c])),
              Expanded(child: cell('')),
            ],
          ),
          for (int p = 0; p < s.paragraphs; p++)
            for (int l = 0; l < kGridSide; l++)
              Row(
                children: <Widget>[
                  Expanded(child: cell(s.paragraphKeys[p])),
                  for (int c = 0; c < kGridSide; c++)
                    Expanded(
                      child: () {
                        final int i = TableSelector.cellIndex(c, l, p);
                        if (i >= words.length) return cell('');
                        return cell(
                          '${s.cellKeys(i)}${words[i]}',
                          background: _highlight && s.highlighted(i)
                              ? highlightColor
                              : null,
                        );
                      }(),
                    ),
                  Expanded(child: cell(s.lineKeys[l])),
                ],
              ),
        ],
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return widget.page(
      Focus(
        focusNode: _grid,
        autofocus: true,
        onKeyEvent: _onKey,
        child: GestureDetector(
          onTap: _grid.requestFocus,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _panel(context),
              const SizedBox(width: 12),
              Expanded(
                  child:
                      ColoredBox(color: Colors.white, child: _table(context))),
            ],
          ),
        ),
      ),
      themeEnabled: _selector.themeChangeable,
    );
  }
}
