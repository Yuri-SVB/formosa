import 'package:flutter/services.dart';
import 'package:formosa/formosa.dart';

/// Where the formosa package's themes are bundled.
const String kThemesAssets = 'packages/formosa/themes/';
const String _kJson = '.json';

/// The themes bundled with the app (the formosa package's themes/).
Future<ThemeSet> loadBundledThemes(AssetBundle bundle) async {
  final AssetManifest manifest =
      await AssetManifest.loadFromAssetBundle(bundle);
  final Map<String, String> texts = <String, String>{};
  for (final String asset in manifest.listAssets()) {
    if (!asset.startsWith(kThemesAssets) || !asset.endsWith(_kJson)) continue;
    final String name =
        asset.substring(kThemesAssets.length, asset.length - _kJson.length);
    if (name.contains('/')) continue;
    texts[name] = await bundle.loadString(asset);
  }
  if (texts.isEmpty) throw const ThemeNotFound('No theme was found');
  return ThemeSet.fromJson(texts);
}

/// The themes as the window lists them: BIP39 first, then the others.
List<String> windowOrder(ThemeSet themes) => <String>[
      if (themes.names.contains(kDefaultTheme)) kDefaultTheme,
      for (final String n in themes.names)
        if (n != kDefaultTheme) n,
    ];
