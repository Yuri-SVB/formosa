/// Formosa's themes read from a folder of `<name>.json` files.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'formosa.dart';

/// The themes in [dir]: every `<name>.json` in it, read on first use.
ThemeSet loadThemes(Directory dir) {
  final Map<String, File> files = <String, File>{
    for (final FileSystemEntity e in dir.listSync())
      if (e is File && e.path.endsWith(_kJson))
        _stem(e.path): e,
  };
  return ThemeSet(
    files.keys,
    (String name) => Theme(
        name, jsonDecode(files[name]!.readAsStringSync()) as Map<String, Object?>),
  );
}

const String _kJson = '.json';

String _stem(String path) {
  final String file = path.split(Platform.pathSeparator).last;
  return file.substring(0, file.length - _kJson.length);
}

/// This package's own `themes/` folder (the repository's), found from where
/// the package is.
Directory packageThemes() {
  final Uri? lib =
      Isolate.resolvePackageUriSync(Uri.parse('package:formosa/formosa.dart'));
  if (lib == null) throw StateError('package:formosa is not resolvable');
  return Directory.fromUri(lib.resolve('../themes/'));
}
