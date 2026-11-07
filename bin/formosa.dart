/// Formosa in the terminal — the reference implementation's `mnemonic.py`.
///
/// ```sh
/// dart run formosa THEME STRENGTH   # a new mnemonic: its password, then its sentences
/// dart run formosa [HEX]            # the BIP39 mnemonic of HEX (else of a line read)
/// dart run formosa themes           # the themes
/// ```
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:formosa/formosa.dart';
import 'package:formosa/io.dart';

/// Exit codes: BSD sysexits.
const int _kUsage = 64;
const int _kData = 65;

/// Where to read the themes from instead of the package's own folder.
const String kThemesEnv = 'FORMOSA_THEMES';

const String _kUsageText = '''
Formosa: themed mnemonic sentences for passwords and BIP39 keys.

  formosa THEME STRENGTH   a new mnemonic of STRENGTH bits (32 to 256, by 32):
                           its password, then its sentences
  formosa [HEX]            the BIP39 mnemonic of HEX (else of a line read)
  formosa themes           the themes available

The themes are read from \$$kThemesEnv, else from the package's themes/.''';

void main(List<String> args) {
  if (args.contains('--help') || args.contains('-h')) {
    stdout.writeln(_kUsageText);
    return;
  }
  final String? folder = Platform.environment[kThemesEnv];
  final ThemeSet themes =
      loadThemes(folder == null ? packageThemes() : Directory(folder));
  try {
    if (args.length == 1 && args.first == 'themes') {
      themes.names.forEach(stdout.writeln);
    } else if (args.length == 2) {
      final Mnemonic m = themes[args[0]];
      final int? strength = int.tryParse(args[1]);
      if (strength == null) throw ArgumentError('STRENGTH is a number of bits');
      stdout.writeln(m.formatMnemonic(m.generate(strength: strength)));
    } else if (args.length <= 1) {
      final String hex =
          args.isEmpty ? (stdin.readLineSync() ?? '').trim() : args.first;
      stdout.writeln(themes[kDefaultTheme].toMnemonic(_fromHex(hex)));
    } else {
      stderr.writeln(_kUsageText);
      exitCode = _kUsage;
    }
  } on ThemeNotFound catch (e) {
    stderr.writeln('${e.message}. Themes: ${themes.names.join(', ')}');
    exitCode = _kUsage;
  } on ArgumentError catch (e) {
    stderr.writeln(e.message);
    exitCode = _kUsage;
  } on FormatException catch (e) {
    stderr.writeln(e.message);
    exitCode = _kData;
  }
}

Uint8List _fromHex(String hex) {
  if (hex.length.isOdd || !RegExp(r'^[0-9a-fA-F]*$').hasMatch(hex)) {
    throw const FormatException('HEX is an even number of hex digits');
  }
  return Uint8List.fromList(<int>[
    for (int i = 0; i < hex.length; i += 2)
      int.parse(hex.substring(i, i + 2), radix: 16),
  ]);
}
