#!/usr/bin/env python3

import json
from pathlib import Path
from random import choice, seed

from src.mnemonic.mnemonic import Mnemonic


def process(mnemo, data, lst):
    code = mnemo.to_mnemonic(bytes.fromhex(data))
    seed = Mnemonic.to_seed(code, passphrase="TREZOR")
    xprv = Mnemonic.to_hd_master_key(seed)
    seed = seed.hex()
    print("input    : %s (%d bits)" % (data, len(data) * 4))
    print("mnemonic : %s (%d words)" % (code, len(code.split(" "))))
    print("seed     : %s (%d bits)" % (seed, len(seed) * 4))
    print("xprv     : %s" % xprv)
    print()
    lst.append((data, code, seed, xprv))


if __name__ == "__main__":
    # The vectors are shared with the Dart implementation, at the repository's root
    vectors_file = Path(__file__).absolute().parents[2] / "vectors.json"

    # BIP39's vectors are the standard's (python-mnemonic's): frozen, kept as they are
    with open(vectors_file) as f:
        out = {"BIP39": json.load(f)["BIP39"]}

    for theme in Mnemonic.find_themes():
        if theme == "BIP39":
            continue
        mnemo = Mnemonic(theme)
        out[theme] = []
        # Each theme its own random stream, so adding a theme leaves the others' vectors alone
        seed("%d:%s" % (1337, theme))

        # BIP39 is standardised for 128 to 256 bits; the other themes take 32 to 256
        lengths = range(16, 32 + 1, 8) if mnemo.is_bip39_theme else range(4, 32 + 1, 4)

        # Generate corner cases
        for length in lengths:
            for b in ["00", "7f", "80", "ff"]:
                process(mnemo, b * length, out[theme])

        # Generate random seeds
        for i in range(12):
            data = "".join(chr(choice(range(0, 256))) for _ in range(8 * (i % 3 + 2)))
            data = data.encode("latin1")
            process(mnemo, data.hex(), out[theme])

    with open(vectors_file, "w") as f:
        json.dump(
            out, f, sort_keys=True, indent=4, separators=(",", ": "), ensure_ascii=False
        )
        f.write("\n")
