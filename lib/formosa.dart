/// Formosa: themed mnemonic sentences for passwords and BIP39-compatible
/// deterministic keys (bip.mediawiki). Pure Dart, no I/O: themes come in as
/// JSON ([ThemeSet.fromJson]); `package:formosa/io.dart` reads a folder.
library;

export 'src/keys.dart' show base58Encode, hdMasterKey, kSeedBytes;
export 'src/mnemonic.dart';
export 'src/theme.dart';
export 'src/theme_set.dart';
