# Formosa — the Python reference implementation

The implementation the BIP ([../bip.mediawiki](../bip.mediawiki)) refers to. It
reads the repository's themes ([../themes](../themes)) and is checked against
the same vectors ([../vectors.json](../vectors.json)) as the Dart
implementation at the repository's root, which is where the app now lives.

Run everything below from this folder (`python/`).

## The library and the terminal

Standard library only:

```console
python3 src/mnemonic/mnemonic.py theme cryptographic_strength   # e.g. sci-fi 160
python3 src/mnemonic/mnemonic.py HEX                            # BIP39 mnemonic of HEX
```

## The graphical interface (PyQt5)

```console
source venv_setup.sh                 # once: a virtual environment with the requirements
source envformosa/bin/activate
python3 src/mnemonic/GUI_qt.py
```

## Tests and tools

```console
python3 -m unittest tests.test_mnemonic tests.test_theme_verify
python3 -m tools.generate_vectors    # vectors of every theme; BIP39's stay frozen
cd tools && python3 theme_handler.py # builds ../themes/edit/main.json
```

An installed package (`pip install .`) carries the themes inside it; a
checkout reads them from `../themes`.
