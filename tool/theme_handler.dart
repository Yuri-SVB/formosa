/// Builds a theme from its authoring files, and swaps words in a theme — the
/// port of the reference implementation's `tools/theme_handler.py`, which it
/// matches byte for byte.
///
/// ```sh
/// dart run tool/theme_handler.dart [DIR]
///     DIR/Data.json (the structure) and DIR/Data.txt (the matrices, tab
///     separated) → DIR/main.json; DIR is themes/edit by default.
/// dart run tool/theme_handler.dart FILE REPLACE_BY SYNTACTIC_REPLACE_BY \
///     REPLACE_IN SYNTACTIC_REPLACE_IN TO_BE_REPLACED [COPY_FROM]
///     Swap a word in the theme FILE.
/// ```
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';

/// A theme that cannot be built or edited as asked.
class ConfigurationError implements Exception {
  ConfigurationError(this.message);

  final String message;

  @override
  String toString() => 'ConfigurationError: $message';
}

typedef Json = Map<String, Object?>;

/// The default authoring folder: the repository's themes/edit.
const String kEditDirectory = 'themes/edit';
const String kStructureFile = 'Data.json';
const String kMatricesFile = 'Data.txt';
const String kOutputFile = 'main.json';

/// Arguments of a word swap, without and with its optional COPY_FROM.
const int _kSwapArgs = 6;
const int _kSwapArgsWithCopy = 7;

/// Tie-breakers added to each adequacy, as the reference does: a small bump,
/// less for later rows, so equal adequacies keep their order.
const double _kAdequacyBump = 1e-4;
const double _kRowStep = 1e-7;

/// Letters compared for collisions: Formosa's passwords take two per word.
const int _kCollisionLetters = 2;

/// Bytes a character may take in the version hash: the reference appends
/// each character's code to a byte array, so only single bytes fit.
const int _kMaxByte = 0xff;

void main(List<String> args) {
  if (args.length <= 1) {
    buildTheme(Directory(args.isEmpty ? kEditDirectory : args.first));
  } else if (args.length == _kSwapArgs || args.length == _kSwapArgsWithCopy) {
    wordSwap(args[0], args[1], args[2], args[3], args[4], args[5],
        copyFrom: args.length == _kSwapArgsWithCopy ? args[6] : null);
  } else {
    stderr.writeln('Usage: theme_handler.dart [DIR] | FILE REPLACE_BY '
        'SYNTACTIC_REPLACE_BY REPLACE_IN SYNTACTIC_REPLACE_IN TO_BE_REPLACED '
        '[COPY_FROM]');
    exitCode = 64;
  }
}

/// Build `main.json` in [dir] from its `Data.json` and `Data.txt`.
void buildTheme(Directory dir) {
  final Json main = jsonDecode(
      File('${dir.path}/$kStructureFile').readAsStringSync()) as Json;
  final List<String> rows = LineSplitter.split(
          File('${dir.path}/$kMatricesFile').readAsStringSync())
      .map((String l) => l.trim())
      .toList();
  final Json built = buildFromData(main, rows);
  File('${dir.path}/$kOutputFile').writeAsStringSync(encodeTheme(built));
}

/// The theme [main] (Data.json) completed by the matrices [rows] (Data.txt,
/// each line trimmed), with its version hash.
Json buildFromData(Json main, List<String> rows) {
  final (List<int> starts, List<int> ends, List<int> relations) =
      _headerIndexes(main, rows);
  final (
    List<List<String>> words,
    List<List<String>> relationMatrices,
    List<List<String>> pairs,
  ) = _splitMatrices(rows, starts, ends, relations);
  final (
    List<List<List<double>>> adequacy,
    List<List<String>> columns,
    List<List<String>> dataRows,
  ) = _matrixProduct(words, relationMatrices);
  List<List<List<String>>> adequate = _mostAdequate(adequacy, dataRows);
  adequate = _removeCollisions(adequate);
  adequate = _sortAdequate(main, adequate, pairs);
  _updateDictionary(main, adequate, pairs, columns);
  final Json version = main['VERSION'] as Json;
  version['SHA256_CONDENSED_FULL'] =
      sha256.convert(_bytes(_serialize(main))).toString();
  return main;
}

(List<int>, List<int>, List<int>) _headerIndexes(Json main, List<String> rows) {
  final List<int> starts = <int>[];
  final List<int> relations = <int>[];
  for (final String word in (main['FILLING_ORDER'] as List).cast<String>()) {
    for (final String row in rows) {
      final int at = rows.indexOf(row);
      if (row.contains(word) &&
          !starts.contains(at) &&
          !starts.contains(at - 1)) {
        starts.add(at);
        if (row.split(' ').length == 2) relations.add(at);
      }
    }
  }
  final List<int> ends = <int>[for (final int s in starts) s - 1];
  ends[0] = rows.length - 1;
  starts.sort();
  ends.sort();
  relations.sort();
  return (starts, ends, relations);
}

(List<List<String>>, List<List<String>>, List<List<String>>) _splitMatrices(
    List<String> rows, List<int> starts, List<int> ends, List<int> relations) {
  if (starts.length != ends.length) {
    throw FormatException('Number of start indexes "${starts.length}" is '
        'different of end indexes "${ends.length}"');
  }
  if (relations.length != (starts.length - 1) ~/ 2) {
    throw FormatException('Number of relation indexes "${relations.length}" '
        'is different of "${(starts.length - 1) ~/ 2}"');
  }
  final List<String> heads = <String>[
    for (final int s in starts) rows[s].split('\t').first,
  ];
  List<String> block(int i) => rows.sublist(starts[i], ends[i]);
  return (
    <List<String>>[
      for (int i = 0; i < starts.length; i++)
        if (heads[i].split(' ').length == 1) block(i),
    ],
    <List<String>>[
      for (int i = 0; i < starts.length; i++)
        if (heads[i].split(' ').length == 2) block(i),
    ],
    <List<String>>[
      for (final int r in relations)
        () {
          final List<String> pair = rows[r].split(' ');
          pair[1] = pair[1].split('\t').first;
          return pair;
        }(),
    ],
  );
}

/// Python's `float()` of a cell.
double _float(String s) => double.parse(s.trim());

/// Python's `zip(a, b)`: as long as the shorter.
int _zipLength(List<Object?> a, List<Object?> b) => math.min(a.length, b.length);

/// Python's `zip(*m)`: the columns of [m], as many as its shortest row.
List<List<T>> _columns<T>(List<List<T>> m) {
  if (m.isEmpty) return <List<T>>[];
  final int n = m.map((List<T> r) => r.length).reduce(math.min);
  return <List<T>>[
    for (int c = 0; c < n; c++) <T>[for (final List<T> r in m) r[c]],
  ];
}

/// Python's `sum(float(a) * float(b) for a, b in zip(a, b))`: a cell is
/// read only where it is used, as the reference reads it.
double _dot(List<Object> a, List<Object> b) {
  double value(Object v) => v is double ? v : _float(v as String);
  double sum = 0;
  for (int i = 0; i < _zipLength(a, b); i++) {
    sum += value(a[i]) * value(b[i]);
  }
  return sum;
}

/// A matrix's cells, as text: its rows after the header, their cells after
/// the row's name.
List<List<String>> _cells(List<String> matrix) => <List<String>>[
      for (final String row in matrix.skip(1)) row.split('\t').skip(1).toList(),
    ];

(List<List<List<double>>>, List<List<String>>, List<List<String>>)
    _matrixProduct(List<List<String>> words, List<List<String>> relations) {
  if (words.length < relations.length) {
    throw FormatException('Number of words matrices "${words.length}" is less '
        'than relation matrices "${relations.length}",');
  }
  final List<List<List<double>>> adequacy = <List<List<double>>>[];
  final List<List<String>> columns = <List<String>>[];
  final List<List<String>> dataRows = <List<String>>[];
  final List<String> order = <String>[
    for (final List<String> m in words) m.first.split('\t').first,
  ];
  for (final List<String> relation in relations) {
    final List<String> head = relation.first.split(' ');
    final List<String> wordsMatrix = words[order.indexOf(head[0])];
    final List<String> nextMatrix =
        words[order.indexOf(head[1].split('\t').first)];
    final List<List<String>> x = _cells(wordsMatrix);
    final List<List<String>> yColumns = _columns(_cells(relation));
    List<List<double>> product = <List<double>>[
      for (final List<String> row in x)
        <double>[for (final List<String> col in yColumns) _dot(row, col)],
    ];
    // The reference transposes the next matrix, then zips its columns: its
    // rows again.
    final List<List<String>> z = _columns(_columns(_cells(nextMatrix)));
    product = <List<double>>[
      for (final List<double> row in product)
        <double>[for (final List<String> col in z) _dot(row, col)],
    ];
    product = <List<double>>[
      for (final List<double> col in product)
        <double>[
          for (int r = 0; r < col.length; r++)
            col[r] + _kAdequacyBump - r * _kRowStep,
        ],
    ];
    columns.add(<String>[for (final String r in wordsMatrix) r.split('\t').first]);
    dataRows.add(<String>[for (final String r in nextMatrix) r.split('\t').first]);
    adequacy.add(product);
  }
  return (adequacy, columns, dataRows);
}

List<List<List<String>>> _mostAdequate(
    List<List<List<double>>> adequacy, List<List<String>> dataRows) {
  if (adequacy.length != dataRows.length) {
    throw FormatException('Number of adequacy matrices "${adequacy.length}" '
        'is different than data rows "${dataRows.length}",');
  }
  return <List<List<String>>>[
    for (int i = 0; i < adequacy.length; i++)
      <List<String>>[
        for (final List<double> col in adequacy[i])
          () {
            final List<double> sorted = List<double>.of(col)
              ..sort((double a, double b) => b.compareTo(a));
            return <String>[
              for (final double v in sorted) dataRows[i][col.indexOf(v) + 1],
            ];
          }(),
      ],
  ];
}

/// The first [n] characters of [s] (code points, as Python slices).
String _head(String s, int n) => String.fromCharCodes(s.runes.take(n));

List<List<List<String>>> _removeCollisions(List<List<List<String>>> matrices) =>
    <List<List<String>>>[
      for (final List<List<String>> matrix in matrices)
        <List<String>>[
          for (final List<String> col in matrix)
            () {
              final List<String> out = List<String>.of(col);
              final List<String> seen = <String>[];
              for (final String word in col) {
                final String first = _head(word, _kCollisionLetters);
                if (seen.contains(first)) {
                  out.add(out.removeAt(out.indexOf(word)));
                }
                seen.add(first);
              }
              return out;
            }(),
        ],
    ];

/// Python's string order: by code point.
int _pyCompare(String a, String b) {
  final List<int> x = a.runes.toList();
  final List<int> y = b.runes.toList();
  for (int i = 0; i < math.min(x.length, y.length); i++) {
    if (x[i] != y[i]) return x[i].compareTo(y[i]);
  }
  return x.length.compareTo(y.length);
}

List<List<List<String>>> _sortAdequate(
    Json main, List<List<List<String>>> matrices, List<List<String>> pairs) {
  if (matrices.length != pairs.length) {
    throw FormatException('Number of adequate matrices ${matrices.length} is '
        'different than the relation pairs ${pairs.length}');
  }
  return <List<List<String>>>[
    for (int i = 0; i < matrices.length; i++)
      <List<String>>[
        for (final List<String> col in matrices[i])
          col.take(1 << ((main[pairs[i][1]] as Json)['BIT_LENGTH'] as int)).toList()
            ..sort((String a, String b) => _pyCompare(b, a)),
      ],
  ];
}

void _updateDictionary(Json main, List<List<List<String>>> matrices,
    List<List<String>> pairs, List<List<String>> columns) {
  if (matrices.length != columns.length) {
    throw FormatException('Number of non-conflicted matrices '
        '"${matrices.length}" is different than data columns '
        '"${columns.length}",');
  }
  if (matrices.length != pairs.length) {
    throw FormatException('Number of non-conflicted matrices '
        '"${matrices.length}" is different than the relation_pairs '
        '"${pairs.length}",');
  }
  final List<String> heads = <String>[for (final List<String> c in columns) c.first];
  for (int i = 0; i < matrices.length; i++) {
    final String lead = pairs[i][0];
    final String led = pairs[i][1];
    final List<List<String>> matrix = matrices[i];
    final Json leadDict = main[lead] as Json;
    if (!leadDict.containsKey(led)) {
      leadDict[led] = <String, Object?>{'IMAGE': <String>[], 'MAPPING': <String, Object?>{}};
    }
    final List<Object?> leads = leadDict['LEADS'] as List<Object?>;
    if (!leads.contains(led)) leads.add(led);
    final List<String> image = <String>{
      for (final List<String> row in matrix) ...row,
    }.toList()
      ..sort(_pyCompare);
    (leadDict[led] as Json)['IMAGE'] = image;
    final List<String> column = columns[heads.indexOf(pairs[i][0])];
    leadDict['TOTAL_LIST'] = column.sublist(1);
    final Json ledDict = main[led] as Json;
    if ((ledDict['LEADS'] as List<Object?>).isEmpty) ledDict['TOTAL_LIST'] = image;
    final Json mapping = <String, Object?>{};
    for (int c = 0; c < matrix.length; c++) {
      matrix[c].sort(_pyCompare);
      mapping[column[c + 1]] = matrix[c];
    }
    (leadDict[led] as Json)['MAPPING'] = mapping;
  }
}

/// The reference's serialisation of a theme for its version: every key and
/// value in order, VERSION left out.
String _serialize(Json dict) {
  final StringBuffer out = StringBuffer();
  for (final MapEntry<String, Object?> e in dict.entries) {
    if (e.key == 'VERSION') continue;
    out.write(e.key);
    final Object? v = e.value;
    if (v is Map) {
      out.write(_serialize(v.cast<String, Object?>()));
    } else if (v is List) {
      out.write(v.cast<String>().join());
    } else if (v is int || v is String) {
      out.write(v);
    }
  }
  return out.toString();
}

List<int> _bytes(String s) => <int>[
      for (final int c in s.runes)
        if (utf8.encode(String.fromCharCode(c)).length == 1 && c <= _kMaxByte)
          c
        else
          throw FormatException('A character beyond a byte: U+${c.toRadixString(16)}'),
    ];

/// [theme] as the reference writes it: 4-space indents, sorted keys,
/// non-ASCII escaped.
String encodeTheme(Json theme) {
  Object? sorted(Object? v) => v is Map
      ? <String, Object?>{
          for (final String k in (v.keys.cast<String>().toList()..sort(_pyCompare)))
            k: sorted(v[k]),
        }
      : v is List
          ? v.map(sorted).toList()
          : v;
  final String text = const JsonEncoder.withIndent('    ').convert(sorted(theme));
  final StringBuffer out = StringBuffer();
  for (final int unit in text.codeUnits) {
    if (unit > 0x7f) {
      out.write('\\u${unit.toRadixString(16).padLeft(4, '0')}');
    } else {
      out.writeCharCode(unit);
    }
  }
  return out.toString();
}

/// Replace [toBeReplaced] by [replaceBy] in the [syntacticReplaceBy] list led
/// by [replaceIn] (a [syntacticReplaceIn] word; `NONE` for its whole list)
/// of the theme [file]; a new word may borrow the lists of [copyFrom].
void wordSwap(String file, String replaceBy, String syntacticReplaceBy,
    String replaceIn, String syntacticReplaceIn, String toBeReplaced,
    {String? copyFrom}) {
  final Json theme = jsonDecode(File(file).readAsStringSync()) as Json;
  final Json by = theme[syntacticReplaceBy] as Json;
  final List<String> byLeads = (by['LEADS'] as List).cast<String>();
  final List<Object?> total = by['TOTAL_LIST'] as List<Object?>;
  // As the reference: whether each relation entry (IMAGE, MAPPING) lacks the
  // word as a key.
  final List<bool> missingKey = <bool>[
    for (final String r in byLeads) !(by[r] as Json).containsKey(replaceBy),
  ];
  if ((!total.contains(replaceBy) ||
          !(missingKey.any((bool b) => b) || byLeads.isEmpty)) &&
      copyFrom == null) {
    throw ConfigurationError(
        'The key "$replaceBy" does not exist in the lists of "$syntacticReplaceBy"');
  }
  if (total.contains(replaceBy) &&
      (missingKey.every((bool b) => b) || byLeads.isEmpty) &&
      copyFrom != null) {
    throw ConfigurationError(
        'The key "$replaceBy" already exist in the lists of "$syntacticReplaceBy"');
  }
  final List<Object?> words = syntacticReplaceIn != 'NONE'
      ? (((theme[syntacticReplaceIn] as Json)[syntacticReplaceBy] as Json)['MAPPING']
          as Json)[replaceIn] as List<Object?>
      : total;
  final String firstLetters = <String>[
    for (final Object? w in words) _head(w! as String, _kCollisionLetters),
  ].join(' ');
  final String wordFirst = _head(replaceBy, _kCollisionLetters);
  final String replacedFirst = _head(toBeReplaced, _kCollisionLetters);
  const int stride = _kCollisionLetters + 1; // two letters and a space
  if (firstLetters.contains(wordFirst) && wordFirst != replacedFirst) {
    final int at = firstLetters.indexOf(wordFirst) ~/ stride;
    throw ConfigurationError('Collision "$replaceBy" with "${words[at]}"');
  }
  final int at = words.indexOf(toBeReplaced);
  if (at < 0) {
    throw ConfigurationError('"$toBeReplaced" is not in the list');
  }
  if (syntacticReplaceIn != 'NONE') {
    final Json relation =
        (theme[syntacticReplaceIn] as Json)[syntacticReplaceBy] as Json;
    final List<Object?> image = relation['IMAGE'] as List<Object?>;
    final List<Object?> list = (relation['MAPPING'] as Json)[replaceIn] as List<Object?>;
    list[at] = replaceBy;
    list.sort((Object? a, Object? b) => _pyCompare(a! as String, b! as String));
    if (!image.contains(replaceBy)) {
      image
        ..add(replaceBy)
        ..sort((Object? a, Object? b) => _pyCompare(a! as String, b! as String));
    }
  }
  if (!total.contains(replaceBy)) {
    total
      ..add(replaceBy)
      ..sort((Object? a, Object? b) => _pyCompare(a! as String, b! as String));
  }
  if (copyFrom != null) {
    for (final String r in byLeads) {
      final Json mapping = (by[r] as Json)['MAPPING'] as Json;
      mapping[replaceBy] = mapping[copyFrom];
    }
  }
  File(file).writeAsStringSync(encodeTheme(theme));
  stdout.writeln('$toBeReplaced substituted by $replaceBy'
      '${syntacticReplaceIn != 'NONE' ? ' at $syntacticReplaceIn' : ''}'
      '${copyFrom != null ? ' borrowed dependencies from $copyFrom' : ''}');
}
