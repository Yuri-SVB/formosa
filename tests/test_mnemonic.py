#!/usr/bin/env python3
#
# Permission is hereby granted, free of charge, to any person obtaining a copy of
# this software and associated documentation files (the "Software"), to deal in
# the Software without restriction, including without limitation the rights to
# use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
# of the Software, and to permit persons to whom the Software is furnished to do
# so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
# WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
# CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#

import json
import random
import unittest
import sys
from pathlib import Path
from src.mnemonic.mnemonic import Mnemonic

# This prevents IDE from creating a cache file
sys.dont_write_bytecode = True


class MnemonicTest(unittest.TestCase):
    def _check_list(self, theme: str, vectors: list[str]) -> None:
        mnemo = Mnemonic(theme)
        for v in vectors:
            code = mnemo.to_mnemonic(bytes.fromhex(v[0]))
            seed = Mnemonic.to_seed(code, passphrase="TREZOR")
            xprv = Mnemonic.to_hd_master_key(seed)
            self.assertIs(mnemo.check(v[1]), True)
            self.assertEqual(v[1], code)
            self.assertEqual(v[2], seed.hex())
            self.assertEqual(v[3], xprv)

    def test_vectors(self) -> None:
        vectors_file = Path(__file__).parent.parent.absolute() / Path("vectors.json")
        with open(vectors_file, "r") as f:
            vectors = json.load(f)
        for theme in vectors.keys():
            self._check_list(theme, vectors[theme])

    def test_failed_checksum(self) -> None:
        code = (
            "bless cloud wheel regular tiny venue bird web grief security dignity zoo"
        )
        mnemo = Mnemonic("BIP39")
        self.assertFalse(mnemo.check(code))

    def test_detection(self) -> None:
        self.assertEqual("BIP39", Mnemonic.detect_theme("security"))

        with self.assertRaises(Exception):
            Mnemonic.detect_theme(
                "jaguar xxxxxxx"
            )  # Unrecognized in any known language

        with self.assertRaises(Exception):
            Mnemonic.detect_theme(
                "jaguar jaguar"
            )  # Ambiguous after examining all words

        self.assertEqual("BIP39", Mnemonic.detect_theme("jaguar security"))
        self.assertEqual("BIP39_french", Mnemonic.detect_theme("jaguar aboyer"))

    def test_utf8_nfkd(self) -> None:
        # The same sentence in various UTF-8 forms
        words_nfkd = "Pr\u030ci\u0301s\u030cerne\u030c z\u030clut\u030couc\u030cky\u0301 ku\u030an\u030c u\u0301pe\u030cl d\u030ca\u0301belske\u0301 o\u0301dy za\u0301ker\u030cny\u0301 uc\u030cen\u030c be\u030cz\u030ci\u0301 pode\u0301l zo\u0301ny u\u0301lu\u030a"
        words_nfc = "P\u0159\xed\u0161ern\u011b \u017elu\u0165ou\u010dk\xfd k\u016f\u0148 \xfap\u011bl \u010f\xe1belsk\xe9 \xf3dy z\xe1ke\u0159n\xfd u\u010de\u0148 b\u011b\u017e\xed pod\xe9l z\xf3ny \xfal\u016f"
        words_nfkc = "P\u0159\xed\u0161ern\u011b \u017elu\u0165ou\u010dk\xfd k\u016f\u0148 \xfap\u011bl \u010f\xe1belsk\xe9 \xf3dy z\xe1ke\u0159n\xfd u\u010de\u0148 b\u011b\u017e\xed pod\xe9l z\xf3ny \xfal\u016f"
        words_nfd = "Pr\u030ci\u0301s\u030cerne\u030c z\u030clut\u030couc\u030cky\u0301 ku\u030an\u030c u\u0301pe\u030cl d\u030ca\u0301belske\u0301 o\u0301dy za\u0301ker\u030cny\u0301 uc\u030cen\u030c be\u030cz\u030ci\u0301 pode\u0301l zo\u0301ny u\u0301lu\u030a"

        passphrase_nfkd = (
            "Neuve\u030cr\u030citelne\u030c bezpec\u030cne\u0301 hesli\u0301c\u030cko"
        )
        passphrase_nfc = "Neuv\u011b\u0159iteln\u011b bezpe\u010dn\xe9 hesl\xed\u010dko"
        passphrase_nfkc = (
            "Neuv\u011b\u0159iteln\u011b bezpe\u010dn\xe9 hesl\xed\u010dko"
        )
        passphrase_nfd = (
            "Neuve\u030cr\u030citelne\u030c bezpec\u030cne\u0301 hesli\u0301c\u030cko"
        )

        seed_nfkd = Mnemonic.to_seed(words_nfkd, passphrase_nfkd)
        seed_nfc = Mnemonic.to_seed(words_nfc, passphrase_nfc)
        seed_nfkc = Mnemonic.to_seed(words_nfkc, passphrase_nfkc)
        seed_nfd = Mnemonic.to_seed(words_nfd, passphrase_nfd)

        self.assertEqual(seed_nfkd, seed_nfc)
        self.assertEqual(seed_nfkd, seed_nfkc)
        self.assertEqual(seed_nfkd, seed_nfd)

    def test_to_entropy(self) -> None:
        data = [bytes(random.getrandbits(8) for _ in range(32)) for _ in range(1024)]
        data.append(b"Lorem ipsum dolor sit amet amet.")
        m = Mnemonic("BIP39")
        for d in data:
            self.assertEqual(m.to_entropy(m.to_mnemonic(d).split()), d)

    def test_expand_word(self) -> None:
        m = Mnemonic("BIP39")
        self.assertEqual("", m.expand_word(""))
        self.assertEqual(" ", m.expand_word(" "))
        self.assertEqual("access", m.expand_word("access"))  # word in list
        self.assertEqual(
            "access", m.expand_word("acce")
        )  # unique prefix expanded to word in list
        self.assertEqual("acb", m.expand_word("acb"))  # not found at all
        self.assertEqual("acc", m.expand_word("acc"))  # multi-prefix match
        self.assertEqual("act", m.expand_word("act"))  # exact three letter match
        self.assertEqual(
            "action", m.expand_word("acti")
        )  # unique prefix expanded to word in list

    def test_expand(self) -> None:
        m = Mnemonic("BIP39")
        self.assertEqual("access", m.expand("access"))
        self.assertEqual(
            "access access acb acc act action", m.expand("access acce acb acc act acti")
        )


class FormosaRegressionTest(unittest.TestCase):
    """ Cover the failures which used to reach the user as a wrong result or a crash"""

    ENTROPIES = [
        "00000000000000000000000000000000",
        "7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f",
        "ffffffffffffffffffffffffffffffff",
        "f585c11aec520db57dd353c69554b21a89b20fb0650966fa0a9d6f74fd989d8f",
    ]

    def test_seed_is_the_same_in_every_theme(self) -> None:
        """
            The standard derives the seed from the equivalent BIP39 mnemonic,
            so the same entropy has to give the same seed whichever theme wrote it down
        """
        for entropy_hex in self.ENTROPIES:
            entropy = bytes.fromhex(entropy_hex)
            expected = Mnemonic.to_seed(Mnemonic("BIP39").to_mnemonic(entropy), "TREZOR")
            for theme in Mnemonic.find_themes():
                # BIP39 wordlists of other languages hash their own words, as BIP39 defines
                if theme.startswith(Mnemonic.DEFAULT_THEME):
                    continue
                with self.subTest(theme=theme, entropy=entropy_hex):
                    code = Mnemonic(theme).to_mnemonic(entropy)
                    self.assertEqual(expected, Mnemonic.to_seed(code, "TREZOR"))

    def test_seed_of_theme_sharing_every_word(self) -> None:
        """ Themes holding the same words are told apart by the checksum instead of raising"""
        mnemo = Mnemonic("medieval_fantasy_light")
        for _ in range(32):
            code = mnemo.generate(128)
            self.assertEqual(64, len(Mnemonic.to_seed(code)))

    def test_generate_rejects_unusable_strength(self) -> None:
        """ A strength which cannot be encoded is refused instead of failing further down"""
        mnemo = Mnemonic("BIP39")
        for strength in (0, 31, 100, 264, 300):
            with self.subTest(strength=strength):
                with self.assertRaises(ValueError):
                    mnemo.generate(strength)
        for strength in (32, 64, 128, 256):
            with self.subTest(strength=strength):
                self.assertTrue(mnemo.check(mnemo.generate(strength)))

    def test_every_theme_round_trips(self) -> None:
        """ Entropy, checksum and the password of the first letters survive every theme"""
        for theme in Mnemonic.find_themes():
            mnemo = Mnemonic(theme)
            for entropy_hex in self.ENTROPIES:
                with self.subTest(theme=theme, entropy=entropy_hex):
                    entropy = bytes.fromhex(entropy_hex)
                    code = mnemo.to_mnemonic(entropy)
                    self.assertNotIn("  ", code)
                    self.assertTrue(mnemo.check(code))
                    self.assertEqual(entropy, bytes(mnemo.to_entropy(code)))
                    self.assertEqual(code, mnemo.expand(code))
                    password = mnemo.format_mnemonic(code).splitlines()[0]
                    self.assertEqual(code, mnemo.expand_password(password))

    def test_words_hold_no_space(self) -> None:
        """ A word holding a space breaks a mnemonic, which is split on spaces"""
        for theme in Mnemonic.find_themes():
            with self.subTest(theme=theme):
                spaced = [word for word in Mnemonic(theme).wordlist if " " in word]
                self.assertEqual([], spaced)

    def test_every_mapped_word_is_addressable(self) -> None:
        """ A list longer than its bit length holds words the encoder can never emit"""
        for theme in Mnemonic.find_themes():
            words_dictionary = Mnemonic(theme).words_dictionary
            for syntactic_word in words_dictionary.filling_order:
                if syntactic_word in words_dictionary.prime_syntactic_leads:
                    continue
                addressable = 2 ** words_dictionary[syntactic_word].bit_length
                mapping = words_dictionary.get_lead_mapping(syntactic_word)
                for lead, words in mapping.items():
                    with self.subTest(theme=theme, syntactic_word=syntactic_word, lead=lead):
                        self.assertEqual(addressable, len(words))


def __main__() -> None:
    unittest.main()


if __name__ == "__main__":
    __main__()
