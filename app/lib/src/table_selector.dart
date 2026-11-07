/// The Table Selector's logic: a theme's words laid out in a grid whose rows
/// and columns are named by keys shuffled anew for every word, picked by
/// typing three keys — so that onlookers learn nothing from the keys typed.
/// The port of the reference window's `TableSelectorTab`, without its widgets.
library;

import 'dart:math' as math;

import 'package:formosa/formosa.dart';

/// Keys per column, line and paragraph of the grid: 8 × 8 × 8 cells.
const int kGridSide = 8;

/// The default keys: the home row.
const List<String> kDefaultKeys = <String>[
  'A',
  'S',
  'D',
  'F',
  'J',
  'K',
  'L',
  ';'
];

/// Cells a grid holds.
const int kGridCells = kGridSide * kGridSide * kGridSide;

/// Where a selection stands: no key typed, then the column's, the
/// paragraph's and the line's.
enum SelectorStep { initial, columnDone, lineDone, paragraphDone }

/// What the phrase picked so far looks like.
enum Validity {
  /// Every word follows the theme.
  compatible,

  /// The word under the keys typed does not follow the words before it.
  candidateIncompatible,

  /// A word picked does not follow the theme.
  incompatible,
}

/// The cells to highlight: from [begin] to [end] (inclusive), every [step].
typedef Highlight = ({int begin, int end, int step});

/// The selector's state.
class TableSelector {
  TableSelector(this._theme, {math.Random? random})
      : _random = random ?? math.Random.secure() {
    newGrid();
  }

  Theme _theme;
  final math.Random _random;

  /// The keys the grid is named by.
  List<String> keys = List<String>.of(kDefaultKeys);

  /// The words picked, in natural order, sentence after sentence.
  final List<String> picked = <String>[];

  /// The word being picked or reviewed.
  int cursor = 0;

  SelectorStep step = SelectorStep.initial;

  /// The index chosen at each step (column, paragraph, line);
  /// [kGridSide] when none.
  final Map<SelectorStep, int> selected = <SelectorStep, int>{
    for (final SelectorStep s in SelectorStep.values) s: kGridSide,
  };

  bool validPhrase = true;
  Validity validity = Validity.compatible;

  /// The cells to highlight now, or null for none.
  Highlight? highlight;

  late List<String> caseless;
  late List<String> columnKeys;
  late List<String> lineKeys;
  late List<String> paragraphKeys;
  late Map<SelectorStep, List<String>> _permutation;

  Theme get theme => _theme;

  /// A BIP39 word list: its words have no sentence to be picked in.
  bool get disabled => _theme.name.startsWith(kDefaultTheme);

  List<String> get naturalOrder => _theme.naturalOrder;

  /// The syntactic word at the cursor.
  String get naturalWord =>
      naturalOrder.isEmpty ? '' : naturalOrder[cursor % naturalOrder.length];

  /// The words in the grid: the syntactic word's, as many as fit.
  List<String> get words {
    if (naturalWord.isEmpty) return const <String>[];
    final List<String> all = _theme.word(naturalWord).totalWords;
    return all.sublist(0, math.min(all.length, kGridCells));
  }

  /// Paragraphs shown: as many as the words fill, at most [kGridSide].
  int get paragraphs {
    const int paragraphSize = kGridSide * kGridSide;
    final int n =
        (math.max(words.length, 1) + paragraphSize - 1) ~/ paragraphSize;
    return math.min(kGridSide, n);
  }

  /// A new theme: what was picked, if anything, goes.
  void setTheme(Theme theme) {
    final bool changed = theme.name != _theme.name;
    _theme = theme;
    if (changed) {
      picked.clear();
      validPhrase = true;
    }
    setCursor(cursor);
    step = SelectorStep.initial;
    newGrid();
    _setValidity();
  }

  /// The theme can be changed: nothing picked yet.
  bool get themeChangeable => picked.isEmpty;

  void setCursor(int position) {
    cursor = math.max(0, math.min(position, picked.length));
  }

  /// "Word 2 of 6", or "Phrase 2, word 3 of 6", and the syntactic word.
  String get positionLabel {
    if (naturalOrder.isEmpty) return '';
    final int length = naturalOrder.length;
    final int place = cursor % length;
    final int before = cursor ~/ length;
    final String where = before == 0
        ? 'Word ${place + 1} of $length'
        : 'Phrase ${before + 1}, word ${place + 1} of $length';
    final String named = naturalOrder[place].replaceAll('_', ' ').toLowerCase();
    return '$where\n${named[0].toUpperCase()}${named.substring(1)}';
  }

  /// Shuffle the keys anew.
  void newGrid() {
    List<String> shuffled() => List<String>.of(keys)..shuffle(_random);
    List<String> withSwapped(List<String> k) =>
        <String>[...k, ...k.map(_swapCase)];
    caseless = withSwapped(shuffled());
    columnKeys = withSwapped(shuffled());
    lineKeys = withSwapped(shuffled());
    paragraphKeys = withSwapped(shuffled());
    _permutation = <SelectorStep, List<String>>{
      SelectorStep.initial: caseless,
      SelectorStep.columnDone: columnKeys,
      SelectorStep.lineDone: paragraphKeys,
      SelectorStep.paragraphDone: lineKeys,
    };
    highlight = null;
  }

  /// The keys naming cell [index]: its column's, paragraph's and line's.
  String cellKeys(int index) => '${columnKeys[index % kGridSide]}'
      '${paragraphKeys[index ~/ (kGridSide * kGridSide)]}'
      '${lineKeys[(index ~/ kGridSide) % kGridSide]}-';

  /// The cell of [column], [line] and [paragraph].
  static int cellIndex(int column, int line, int paragraph) =>
      column + kGridSide * kGridSide * paragraph + kGridSide * line;

  /// The keys typed into the custom set: upper case, each once, at most
  /// [kGridSide]; the set is used once it is whole. Returns the text kept.
  String defineKeys(String typed) {
    final List<String> chosen = <String>[];
    for (final String c in typed.toUpperCase().split('')) {
      if (!chosen.contains(c) && chosen.length < kGridSide) chosen.add(c);
    }
    useKeys(chosen.length == kGridSide ? chosen : kDefaultKeys);
    return chosen.join();
  }

  void useKeys(List<String> set) {
    if (_sameList(set, keys)) return;
    keys = List<String>.of(set);
    newGrid();
  }

  /// A key typed: the next step of the selection, if it is one of the keys.
  /// Returns whether it was taken.
  bool typed(String key) {
    if (disabled ||
        step == SelectorStep.paragraphDone ||
        !caseless.contains(key)) {
      return false;
    }
    step = SelectorStep.values[step.index + 1];
    final int at = _permutation[step]!.indexOf(key);
    selected[step] = at % kGridSide;
    _delineate(at);
    return true;
  }

  /// Esc or Delete: start the selection over.
  void restart() {
    if (disabled || step == SelectorStep.initial) return;
    step = SelectorStep.initial;
    _setValidity();
    _delineate(0);
  }

  /// Enter or Space: pick the word under the three keys typed.
  void confirm() {
    if (disabled || step != SelectorStep.paragraphDone) return;
    if (validity == Validity.candidateIncompatible) validPhrase = false;
    _pick();
  }

  /// Backspace: cancel the keys typed, else undo the last word.
  void back() {
    if (disabled) return;
    if (step != SelectorStep.initial) {
      step = SelectorStep.initial;
      _resetSelected();
      _setValidity();
      _delineate(0);
      return;
    }
    undoLastWord();
  }

  /// Left or right: review another word picked (or the next to pick).
  void stepWord(int by) {
    if (disabled) return;
    final int reachable = picked.length + 1;
    setCursor((cursor + by) % reachable);
    step = SelectorStep.initial;
    _resetSelected();
    newGrid();
    checkWordList();
  }

  bool undoLastWord() {
    if (picked.isEmpty) return false;
    picked.removeLast();
    setCursor(picked.length);
    step = SelectorStep.initial;
    _resetSelected();
    validPhrase = phraseFollowsTheme();
    newGrid();
    checkWordList();
    return true;
  }

  void reset() {
    picked.clear();
    setCursor(0);
    step = SelectorStep.initial;
    validPhrase = true;
    _setValidity();
    _resetSelected();
    newGrid();
  }

  /// Whole sentences picked: the phrase can be put out.
  bool get complete =>
      picked.isNotEmpty && picked.length % naturalOrder.length == 0;

  bool get canGoBack => picked.isNotEmpty || step != SelectorStep.initial;

  /// The phrase picked, sentence after sentence, as the reference copies it.
  String get output {
    final int n = naturalOrder.length;
    return <String>[
      for (int i = 0; i < picked.length ~/ n; i++)
        '${picked.sublist(n * i, n * (i + 1)).join(' ')} ',
    ].join();
  }

  void _resetSelected() {
    for (final SelectorStep s in SelectorStep.values) {
      selected[s] = kGridSide;
    }
  }

  void _pick() {
    final int column = selected[SelectorStep.columnDone]!;
    final int paragraph = selected[SelectorStep.lineDone]!;
    final int line = selected[SelectorStep.paragraphDone]!;
    final int index = cellIndex(column, line, paragraph);
    final List<String> list = _theme.word(naturalWord).totalWords;
    step = SelectorStep.initial;
    if (index < list.length) {
      if (cursor < picked.length) {
        picked[cursor] = list[index];
      } else {
        picked.add(list[index]);
      }
      _delineate(0);
      _resetSelected();
      setCursor(cursor + 1);
      validPhrase = phraseFollowsTheme();
      newGrid();
      _setValidity();
    } else {
      _delineate(0);
      _resetSelected();
    }
  }

  /// Whether every word picked follows its leading word, sentence by
  /// sentence.
  bool phraseFollowsTheme() {
    final List<String> order = naturalOrder;
    if (order.isEmpty) return true;
    for (int at = 0; at < picked.length; at++) {
      final String key = order[at % order.length];
      final String ledBy = _theme.word(key).ledBy;
      if (!order.contains(ledBy)) continue;
      final int start = (at ~/ order.length) * order.length;
      final int leader = order.indexOf(ledBy) + start;
      if (leader >= picked.length) continue;
      final List<String>? list = _theme.ledByMapping(key)[picked[leader]];
      if (list == null || !list.contains(picked[at])) return false;
    }
    return true;
  }

  /// Check the words up to the cursor, and [word] after them if given.
  void checkWordList([String? word]) {
    final List<String> check = <String>[
      ...picked.take(cursor),
      if (word != null) word
    ];
    bool state = true;
    final List<String> order = naturalOrder;
    final List<String> filling = _theme.fillingOrder;
    final int shift = (check.length ~/ order.length) * order.length;
    final int size = check.length % order.length;
    final bool hasWord = word != null && word.isNotEmpty;
    if (!((!hasWord && size != 0) || (hasWord && size != 1))) {
      _setValidity(state: state);
      return;
    }
    for (final String key in filling.skip(1).take(math.max(0, size - 1))) {
      if (!filling.take(size).every(order.take(size).contains)) continue;
      final String ledBy = _theme.word(key).ledBy;
      if (!order.contains(ledBy)) continue;
      final int leader = order.indexOf(ledBy) + shift;
      final int at = _theme.naturalIndex(key) + shift;
      if (math.max(leader, at) >= check.length) continue;
      final List<String> list =
          _theme.word(ledBy).mapping(key)[check[leader]] ?? const <String>[];
      if (!list.contains(check[at])) state = false;
    }
    _setValidity(state: state);
  }

  void _setValidity({bool state = true}) {
    if (!validPhrase) {
      validity = Validity.incompatible;
    } else if (!state) {
      validity = Validity.candidateIncompatible;
    } else {
      validity = Validity.compatible;
    }
  }

  void _delineate(int index) {
    final int n = words.length;
    final int i = index % kGridSide;
    switch (step) {
      case SelectorStep.initial:
        highlight = null;
      case SelectorStep.columnDone:
        highlight = (begin: i, end: n, step: kGridSide);
      case SelectorStep.lineDone:
        final int column = selected[SelectorStep.columnDone]!;
        final int begin = kGridSide * kGridSide * i + column;
        highlight = (
          begin: begin,
          end: begin + kGridSide * (kGridSide - 1),
          step: kGridSide
        );
      case SelectorStep.paragraphDone:
        final int column = selected[SelectorStep.columnDone]!;
        final int paragraph = selected[SelectorStep.lineDone]!;
        final int begin =
            column + kGridSide * i + kGridSide * kGridSide * paragraph;
        highlight = (begin: begin, end: begin, step: 1);
        final List<String> all = _theme.word(naturalWord).totalWords;
        if (begin < math.min(n, all.length)) checkWordList(all[begin]);
    }
  }

  /// Whether cell [index] is highlighted now.
  bool highlighted(int index) {
    final Highlight? h = highlight;
    if (h == null || index < h.begin || index > h.end) return false;
    return (index - h.begin) % h.step == 0;
  }
}

String _swapCase(String c) {
  final String up = c.toUpperCase();
  return up == c ? c.toLowerCase() : up;
}

bool _sameList(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
