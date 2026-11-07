/// Formosa in the terminal — the reference implementation's `mnemonic.py`.
///
/// ```sh
/// dart run formosa THEME STRENGTH   # a new mnemonic: its password, then its sentences
/// dart run formosa THEME STRENGTH --digest HEX   # from a Dragon Dice digest
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

/// The option taking a Dragon Dice digest as the entropy.
const String kDigestOption = '--digest';

/// Strengths below this can be tabulated once cut from a digest: the rolls
/// should carry [kDiceMarginBits] more.
const int kUntabulableStrength = 128;
const int kDiceMarginBits = 8;

const int _kByteBits = 8;

const String _kUsageText = '''
Formosa: themed mnemonic sentences for passwords and BIP39 keys.

  formosa THEME STRENGTH   a new mnemonic of STRENGTH bits (32 to 256, by 32):
                           its password, then its sentences
  formosa THEME STRENGTH $kDigestOption HEX
                           the same from real dice: the first STRENGTH bits of
                           HEX, a Dragon Dice digest (dart run dragon_dice
                           hash, in dragon-dice/). Roll for STRENGTH bits, and
                           $kDiceMarginBits more below $kUntabulableStrength.
  formosa [HEX]            the BIP39 mnemonic of HEX (else of a line read)
  formosa themes           the themes available

The themes are read from \$$kThemesEnv, else from the package's themes/.''';

void main(List<String> args) {
  if (args.contains('--help') || args.contains('-h')) {
    stdout.writeln(_kUsageText);
    return;
  }
  args = List<String>.of(args);
  String? digest;
  final int option = args.indexOf(kDigestOption);
  if (option >= 0) {
    if (option + 1 >= args.length) {
      stderr.writeln('$kDigestOption takes the digest, in hex');
      exitCode = _kUsage;
      return;
    }
    digest = args[option + 1];
    args.removeRange(option, option + 2);
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
      if (digest == null) {
        stdout.writeln(m.formatMnemonic(m.generate(strength: strength)));
      } else {
        Mnemonic.checkStrength(strength);
        final Uint8List bytes = _fromHex(digest);
        if (bytes.length * _kByteBits < strength) {
          throw FormatException('The digest has fewer than $strength bits');
        }
        final Uint8List entropy =
            Uint8List.fromList(bytes.sublist(0, strength ~/ _kByteBits));
        stdout.writeln(m.formatMnemonic(m.toMnemonic(entropy)));
        entropy.fillRange(0, entropy.length, 0);
        bytes.fillRange(0, bytes.length, 0);
      }
    } else if (args.length <= 1 && digest == null) {
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
