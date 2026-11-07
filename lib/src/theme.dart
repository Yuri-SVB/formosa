/// A Formosa theme: the syntactic words of its sentences, the order they are
/// filled in and the order they are spoken in, and their word lists — the
/// port of the reference implementation's `ThemeDict`.
///
/// A sentence's words are chosen in the *filling order*: the first word of a
/// sentence (a *prime* lead) from its whole list, each later one from the list
/// the word that leads it maps to. They are written in the *natural order*.
library;

/// A theme's keys.
abstract final class ThemeKey {
  static const String fillingOrder = 'FILLING_ORDER';
  static const String naturalOrder = 'NATURAL_ORDER';
  static const String leads = 'LEADS';
  static const String ledBy = 'LED_BY';
  static const String totalList = 'TOTAL_LIST';
  static const String image = 'IMAGE';
  static const String mapping = 'MAPPING';
  static const String bitLength = 'BIT_LENGTH';

  /// The [ledBy] of a word led by none.
  static const String none = 'NONE';
}

/// One syntactic word of a theme (a subject, a verb, …).
class SyntacticWord {
  SyntacticWord(this.name, this._json);

  final String name;
  final Map<String, Object?> _json;

  /// Bits that choose this word in its list.
  int get bitLength => (_json[ThemeKey.bitLength] as int?) ?? 0;

  /// The syntactic word that leads this one, [ThemeKey.none] for a prime
  /// lead.
  String get ledBy => (_json[ThemeKey.ledBy] as String?) ?? '';

  /// The syntactic words this one leads.
  List<String> get leads => _strings(_json[ThemeKey.leads]);

  /// Every word of this syntactic word.
  List<String> get totalWords => _strings(_json[ThemeKey.totalList]);

  /// For [led], a syntactic word this one leads: the list of [led]'s words
  /// each of this one's words maps to.
  Map<String, List<String>> mapping(String led) {
    final Object? relation = _json[led];
    if (relation is! Map) return const <String, List<String>>{};
    final Object? mapping = relation[ThemeKey.mapping];
    if (mapping is! Map) return const <String, List<String>>{};
    return <String, List<String>>{
      for (final MapEntry<Object?, Object?> e in mapping.entries)
        e.key as String: _strings(e.value),
    };
  }
}

List<String> _strings(Object? list) =>
    list is List ? List<String>.unmodifiable(list.cast<String>()) : const <String>[];

/// A theme, read from its JSON.
class Theme {
  Theme(this.name, Map<String, Object?> json)
      : _json = json,
        fillingOrder = _strings(json[ThemeKey.fillingOrder]),
        naturalOrder = _strings(json[ThemeKey.naturalOrder]) {
    if (fillingOrder.length != naturalOrder.length) {
      throw const FormatException('The theme is malformed');
    }
    for (int i = 0; i < naturalOrder.length; i++) {
      _natural[naturalOrder[i]] = i;
    }
    for (final String key in fillingOrder) {
      _words[key] = word(key);
    }
    primeLeads = <String>[
      for (final String key in fillingOrder)
        if (_words[key]!.ledBy == ThemeKey.none) key,
    ];
    restrictionSequence = <(String, String)>[
      for (final String key in fillingOrder)
        for (final String led in _words[key]!.leads) (key, led),
    ];
    restrictionIndexes = <(int, int)>[
      for (final (String lead, String led) in restrictionSequence)
        (naturalIndex(lead), naturalIndex(led)),
    ];
    _mappings = <String, Map<String, List<String>>>{
      for (final String key in fillingOrder)
        if (!primeLeads.contains(key)) key: word(_words[key]!.ledBy).mapping(key),
    };
    _pairMappings = <Map<String, List<String>>>[
      for (final (String lead, String led) in restrictionSequence)
        word(lead).mapping(led),
    ];
  }

  final String name;
  final Map<String, Object?> _json;

  /// The order a sentence's words are chosen in.
  final List<String> fillingOrder;

  /// The order a sentence's words are written in.
  final List<String> naturalOrder;

  final Map<String, int> _natural = <String, int>{};
  final Map<String, SyntacticWord> _words = <String, SyntacticWord>{};
  late final Map<String, Map<String, List<String>>> _mappings;

  /// The mapping of each pair of [restrictionSequence].
  late final List<Map<String, List<String>>> _pairMappings;

  /// Syntactic words led by none: chosen from their whole lists.
  late final List<String> primeLeads;

  /// Every (lead, led) pair, in filling order.
  late final List<(String, String)> restrictionSequence;

  /// [restrictionSequence] as natural indexes.
  late final List<(int, int)> restrictionIndexes;

  /// The syntactic word [key].
  SyntacticWord word(String key) {
    final Object? json = _json[key];
    if (json is! Map<String, Object?>) {
      throw FormatException('No syntactic word $key in theme $name');
    }
    return _words[key] ?? SyntacticWord(key, json);
  }

  /// Bits a sentence carries.
  late final int bitsPerPhrase = <int>[
    for (final String key in fillingOrder) _words[key]!.bitLength,
  ].fold(0, (int a, int b) => a + b);

  /// The bit length of each word, in filling order.
  late final List<int> bitsFillSequence = <int>[
    for (final String key in fillingOrder) _words[key]!.bitLength,
  ];

  /// Words in a sentence.
  int get wordsPerPhrase => fillingOrder.length;

  /// Every word of the theme, once, in filling order.
  late final List<String> wordlist = <String>{
    for (final String key in fillingOrder)
      if (_json.containsKey(key)) ..._words[key]!.totalWords,
  }.toList(growable: false);

  /// Where [key] is written in a sentence.
  int naturalIndex(String key) {
    final int? i = _natural[key];
    if (i == null) throw FormatException('No syntactic word $key in theme $name');
    return i;
  }

  /// Where [key] is chosen in a sentence.
  int fillIndex(String key) => fillingOrder.indexOf(key);

  /// For each natural position, its filling position's natural index — the
  /// natural index of each word in filling order.
  late final List<int> naturalMap = <int>[
    for (final String key in fillingOrder) naturalIndex(key),
  ];

  /// The words of [sentence] (natural order) paired as in
  /// [restrictionSequence].
  List<(String, String)> restrictionPairs(List<String> sentence) => <(String, String)>[
        for (final (int lead, int led) in restrictionIndexes)
          (sentence[lead], sentence[led]),
      ];

  /// The list [key]'s word of [sentence] is chosen from: its whole list for a
  /// prime lead, else the list its leading word maps to.
  List<String> leadList(String key, List<String> sentence) {
    if (primeLeads.contains(key)) return _words[key]!.totalWords;
    final String leading = sentence[ledByIndex(key)];
    final List<String>? list = _mappings[key]![leading];
    if (list == null) {
      throw FormatException('No $key words follow the word given');
    }
    return list;
  }

  /// The natural index of the syntactic word leading [key].
  int ledByIndex(String key) => naturalIndex(_words[key]!.ledBy);

  /// The words of [key] each word of its leading syntactic word maps to.
  Map<String, List<String>> ledByMapping(String key) =>
      _mappings[key] ?? const <String, List<String>>{};

  /// The words of a mnemonic: a string split on single spaces, or a list.
  static List<String> normalizeMnemonic(Object mnemonic) => mnemonic is String
      ? mnemonic.split(' ')
      : List<String>.of(mnemonic as List<String>);

  /// Each word's index in its list, in natural order. Throws a
  /// [FormatException] when a word is not where the sentence puts it.
  List<int> naturalIndexes(Object sentence) {
    final List<String> words = normalizeMnemonic(sentence);
    if (words.length != wordsPerPhrase) {
      throw FormatException('The number of words in sentence must be '
          '$wordsPerPhrase, but it is ${words.length}');
    }
    final List<int> indexes = List<int>.filled(words.length, 0);
    int indexIn(List<String> list, String word) {
      final int i = list.indexOf(word);
      if (i < 0) throw FormatException('${word.isEmpty ? 'A blank' : 'A'} word is not in its list');
      return i;
    }

    for (final String key in primeLeads) {
      final int at = naturalIndex(key);
      indexes[at] = indexIn(_words[key]!.totalWords, words[at]);
    }
    final List<(String, String)> pairs = restrictionPairs(words);
    for (int i = 0; i < restrictionSequence.length; i++) {
      final (String _, String led) = restrictionSequence[i];
      final (String leadWord, String ledWord) = pairs[i];
      final List<String>? list = _pairMappings[i][leadWord];
      if (list == null) throw const FormatException('A word leads no list');
      indexes[naturalIndex(led)] = indexIn(list, ledWord);
    }
    return indexes;
  }

  /// Each word's index in its list, in filling order.
  List<int> fillingIndexes(Object sentence) {
    final List<int> natural = naturalIndexes(sentence);
    return <int>[for (final int i in naturalMap) natural[i]];
  }

  /// Whole sentences in [mnemonic].
  int phraseAmount(Object mnemonic) =>
      normalizeMnemonic(mnemonic).length ~/ wordsPerPhrase;

  /// [mnemonic]'s whole sentences.
  List<List<String>> sentences(Object mnemonic) {
    final List<String> words = normalizeMnemonic(mnemonic);
    return <List<String>>[
      for (int p = 0; p < phraseAmount(words); p++)
        words.sublist(wordsPerPhrase * p, wordsPerPhrase * (p + 1)),
    ];
  }

  /// Every word's index in its list, sentence by sentence, in filling order.
  List<int> phraseIndexes(Object mnemonic) => <int>[
        for (final List<String> s in sentences(mnemonic)) ...fillingIndexes(s),
      ];

  /// The sentence [bits] (one per entry, `0` or `1`) choose, in natural
  /// order.
  List<String> assembleSentence(List<int> bits) {
    int at = 0;
    final List<String> sentence = List<String>.filled(fillingOrder.length, '');
    for (final String key in fillingOrder) {
      final int length = _words[key]!.bitLength;
      int index = 0;
      for (int i = 0; i < length; i++) {
        index = (index << 1) | bits[at + i];
      }
      at += length;
      sentence[naturalIndex(key)] = leadList(key, sentence)[index];
    }
    return sentence;
  }

  /// The words [bits] choose, sentence after sentence.
  List<String> sentencesFromBits(List<int> bits) => <String>[
        for (int p = 0; p < bits.length ~/ bitsPerPhrase; p++)
          ...assembleSentence(
              bits.sublist(bitsPerPhrase * p, bitsPerPhrase * (p + 1))),
      ];
}
