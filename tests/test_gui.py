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

import os
import sys
import unittest
from pathlib import Path

# This prevents IDE from creating a cache file
sys.dont_write_bytecode = True

# The window needs no screen to be built, which lets these run on a headless machine
os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

# GUI_qt imports its own module as "mnemonic", the way it is started by run_formosa.sh
sys.path.insert(0, str(Path(__file__).parent.parent.absolute() / Path("src") / Path("mnemonic")))

try:
    from PyQt5.QtCore import Qt, QEvent
    from PyQt5.QtGui import QKeyEvent
    from PyQt5.QtWidgets import QApplication
    import GUI_qt
except ImportError as import_error:  # pragma: no cover - depends on the environment
    GUI_qt = None
    IMPORT_ERROR = import_error


@unittest.skipIf(GUI_qt is None, "PyQt5 is not installed")
class GuiTest(unittest.TestCase):
    application = None

    @classmethod
    def setUpClass(cls) -> None:
        cls.application = QApplication.instance() or QApplication([])

    def setUp(self) -> None:
        self.window = GUI_qt.QtFormosa()
        # Shown as main() does it, otherwise the widgets are never given a geometry
        #  and nothing about how they are placed can be measured
        self.window.show()
        self.tabs = self.window.table_widget
        self.generator = self.tabs.mnemonic_generator
        self.converter = self.tabs.theme_converter
        self.selector = self.tabs.table_selector

    def tearDown(self) -> None:
        self.window.close()

    def test_module_builds_no_window_on_import(self) -> None:
        """ Importing the module must not open a window, so it can be tested and reused"""
        self.assertTrue(hasattr(GUI_qt, "main"))

    def test_clipboard_stays_callable(self) -> None:
        """
            Copying used to assign the text over QApplication.clipboard,
            which copied nothing and made every later clipboard user raise TypeError
        """
        self.generator.last_text = "a mnemonic to copy"
        self.generator.copy_to_clipboard()
        self.assertEqual("a mnemonic to copy", QApplication.clipboard().text())

        # The Table Selector reaches for the clipboard as well and used to crash here
        self.tabs.tab_clicked(2)
        self.selector.set_base_theme("medieval_fantasy")
        self.selector.picked_passphrase = list(self.window.base_dict.natural_order)
        self.selector.output_phrases()

    def test_bip39_word_count_which_is_not_a_multiple_of_three(self) -> None:
        """ A typed word count with no matching entropy size used to abort the process"""
        self.generator.set_base_theme("BIP39")
        for typed_value in ("4", "7", "23"):
            with self.subTest(typed=typed_value):
                self.generator.select_phrases.lineEdit().setText(typed_value)
                self.generator.select_phrases.interpretText()
                self.generator.generate_text()
                self.assertEqual(0, self.generator.select_phrases.value() % 3)
                self.assertTrue(self.generator.last_text)

    def test_generate_every_theme_at_every_size(self) -> None:
        """ Every theme has to generate at each amount the selector offers"""
        for theme in self.window.themes:
            self.generator.set_base_theme(theme)
            selector = self.generator.select_phrases
            for amount in (selector.minimum(), selector.maximum()):
                with self.subTest(theme=theme, amount=amount):
                    selector.setValue(amount)
                    self.generator.clear_text()
                    self.generator.generate_text()
                    self.assertTrue(self.generator.last_text)

    def test_table_selector_accepts_words_of_any_length(self) -> None:
        """
            The grid trims a long word to fit, and the trimmed text used to be
            looked up in the theme, raising KeyError on the first long word picked
        """
        self.tabs.tab_clicked(2)
        for theme in ("medieval_fantasy", "cute_pets", "tourism"):
            with self.subTest(theme=theme):
                self.selector.set_base_theme(theme)
                words_dictionary = self.window.base_dict
                long_words = [word
                              for syntactic_word in words_dictionary.natural_order
                              for word in words_dictionary[syntactic_word].total_words
                              if len(word) > 12]
                self.assertTrue(long_words, "the theme is expected to hold a word longer than the grid")
                for word in long_words[:16]:
                    self.selector.picked_passphrase = []
                    self.selector.check_word_list(word)

    def test_table_selector_theme_without_restriction(self) -> None:
        """ A theme leading every word by "NONE" used to raise on the first key pressed"""
        self.tabs.tab_clicked(2)
        for theme in ("nationalities", "global", "medieval_fantasy_light"):
            with self.subTest(theme=theme):
                self.selector.set_base_theme(theme)
                self.selector.picked_passphrase = []
                for index in range(3):
                    key_char = self.selector.input_set_column[index]
                    self.selector.keyReleaseEvent(
                        QKeyEvent(QEvent.KeyRelease, ord(key_char.upper()), Qt.NoModifier, key_char))

    def test_theme_changed_in_another_tab(self) -> None:
        """
            The theme belongs to the window, so a tab which was left on an older one
            used to raise KeyError on the word it still remembered
        """
        self.tabs.tab_clicked(2)
        self.selector.set_base_theme("medieval_fantasy")
        self.selector.picked_passphrase = ["acolyte"]

        # changed from the Password Generator, without the Table Selector being told
        self.generator.set_base_theme("nationalities")
        self.assertEqual("nationalities", self.window.base_theme)

        self.selector.changed_show_highlight()
        self.selector.new_grid()
        self.selector.pick_word()
        self.selector.output_phrases()
        self.assertIn(self.selector.natural_word, self.window.base_dict.natural_order)

    # The smallest screen the window is expected to sit inside
    SMALL_SCREEN = (800, 600)

    def named_widgets(self, tab_index: int) -> list:
        """ The controls of a tab which the user is meant to be able to reach"""
        names = {
            0: ("run_button clip_button select_phrases check_case check_char check_number "
                "redo_button clear_button save_button text_box select_base_theme quit_button"),
            1: "base_mnemonic_box new_mnemonic_box convert_button select_new_theme select_base_theme quit_button",
            2: ("reset_button sel_valid_phrase_label highlight_checkbox warning_label use_custom_set "
                "custom_character_entry output_button grid_holder select_base_theme quit_button"),
        }[tab_index].split()
        tab = self.tabs.tab_control.widget(tab_index)
        return [(name, getattr(tab, name)) for name in names if hasattr(tab, name)]

    def test_window_fits_a_small_screen(self) -> None:
        """
            The Table Selector spanned its grid over 64 layout rows, and the spacing of
            those rows alone demanded more height than a small screen holds. The window
            could not shrink below it, so maximizing left the lower controls off screen
        """
        for index in range(3):
            self.tabs.tab_clicked(index)
        minimum = self.window.minimumSizeHint()
        self.assertLessEqual(minimum.width(), self.SMALL_SCREEN[0])
        self.assertLessEqual(minimum.height(), self.SMALL_SCREEN[1])

    def test_every_control_stays_inside_the_window(self) -> None:
        """ No control may sit past the window edge, at any size, theme or tab"""
        for size in (self.SMALL_SCREEN, (1024, 768), (1920, 1080)):
            self.window.resize(*size)
            for theme in ("BIP39", "medieval_fantasy", "nationalities"):
                for index in range(3):
                    self.tabs.tab_clicked(index)
                    self.tabs.tab_control.widget(index).set_base_theme(theme)
                    self.application.processEvents()
                    for name, widget in self.named_widgets(index):
                        if not widget.isVisibleTo(self.window):
                            continue
                        corner = widget.mapTo(self.window, widget.rect().bottomRight())
                        with self.subTest(size=size, theme=theme, tab=index, widget=name):
                            self.assertLessEqual(corner.x(), self.window.width())
                            self.assertLessEqual(corner.y(), self.window.height())

    def test_whole_table_is_read_without_scrolling(self) -> None:
        """
            Scrolling would tell a shoulder surfer which band of the table the word is in,
            which is what the shuffled column, line and paragraph keys are there to hide,
            so every cell of every table has to sit inside the view at any window size
        """
        self.tabs.tab_clicked(2)
        for size in (self.SMALL_SCREEN, (1024, 768), (1920, 1080)):
            self.window.resize(*size)
            for theme in ("medieval_fantasy", "finances", "nationalities"):
                self.selector.set_base_theme(theme)
                for syntactic_word in self.window.base_dict.natural_order:
                    self.selector.natural_word = syntactic_word
                    self.selector.new_grid()
                    self.application.processEvents()
                    holder = self.selector.grid_holder
                    labels = self.selector.current_words()
                    with self.subTest(size=size, theme=theme, word=syntactic_word):
                        self.assertTrue(labels)
                        for cell_index, label in enumerate(labels):
                            if not label.isVisibleTo(holder):
                                continue
                            corner = label.mapTo(holder, label.rect().bottomRight())
                            self.assertLessEqual(corner.y(), holder.height(),
                                                 f"cell {cell_index} falls below the table")
                            self.assertLessEqual(corner.x(), holder.width(),
                                                 f"cell {cell_index} falls past the table")

    def test_grid_labels_are_not_piled_up(self) -> None:
        """ Rebuilding the grid used to leave behind the labels which never reached the layout"""
        from PyQt5.QtWidgets import QLabel
        self.tabs.tab_clicked(2)
        self.selector.set_base_theme("medieval_fantasy")

        def label_amount() -> int:
            self.application.processEvents()
            return (len(self.selector.findChildren(QLabel))
                    + len(self.selector.grid_holder.findChildren(QLabel)))

        after_first_grid = label_amount()
        for _ in range(6):
            self.selector.new_grid()
        self.assertEqual(after_first_grid, label_amount())

    def type_custom_keys(self, keys: str) -> None:
        """ Type into the custom keys box one character at a time, as the widget does"""
        for each_character in keys:
            self.selector.custom_character_entry.keyPressEvent(
                QKeyEvent(QEvent.KeyPress, ord(each_character.upper()), Qt.NoModifier, each_character))
        self.application.processEvents()

    def pick_cell_by_its_keys(self, cell_index: int) -> str:
        """
            Read the keys written on a cell, press them, and return the word picked

        Parameters
        ----------
        cell_index : int
            The cell of the grid to pick

        Returns
        -------
        str
            The word which was stored, or an empty string when nothing was picked
        """
        already_picked = len(self.selector.picked_passphrase)
        written_keys = self.selector.current_words()[cell_index].text().split("-")[0]
        for each_key in written_keys:
            self.selector.keyReleaseEvent(
                QKeyEvent(QEvent.KeyRelease, ord(each_key.upper()), Qt.NoModifier, each_key))
        self.selector.keyReleaseEvent(
            QKeyEvent(QEvent.KeyRelease, Qt.Key_Return, Qt.NoModifier, "\r"))
        if len(self.selector.picked_passphrase) == already_picked:
            return ""
        return self.selector.picked_passphrase[-1]

    def test_keys_written_on_a_cell_pick_that_cell(self) -> None:
        """
            The keys printed on a cell are the ones which pick it, whichever set is in use

            A set holding a repeated key used to index the grid, so the keys read off a
            cell stored some other word, quietly putting a word never chosen in the phrase
        """
        self.tabs.tab_clicked(2)
        self.selector.set_base_theme("medieval_fantasy")
        self.selector.use_custom_set.setChecked(True)
        self.selector.enable_custom_keys_set()
        for keys in ("", "QWERTYUI", "12345678", "QWERTYUIQ", "QWERTYUIO"):
            self.selector.custom_character_entry.setText("")
            self.selector.define_key_list()
            self.type_custom_keys(keys)
            with self.subTest(keys=keys or "default"):
                self.assertEqual(self.selector.COLUMN_LINE_PARAGRAPH_SIZE,
                                 len(self.selector.input_character_set))
                self.assertEqual(len(set(self.selector.input_character_set)),
                                 len(self.selector.input_character_set))
                for cell_index in (0, 1, 9, 64, 100):
                    # Reset first, it puts the grid back on the opening syntactic word
                    self.selector.reset_selection()
                    words = self.window.base_dict[self.selector.natural_word].total_words
                    if cell_index >= len(self.selector.current_words()):
                        continue
                    self.assertEqual(words[cell_index], self.pick_cell_by_its_keys(cell_index))

    def test_custom_keys_box_shows_the_keys_in_use(self) -> None:
        """ What the box shows and what the grid is indexed by may never disagree"""
        self.tabs.tab_clicked(2)
        self.selector.set_base_theme("medieval_fantasy")
        self.selector.use_custom_set.setChecked(True)
        self.selector.enable_custom_keys_set()

        self.type_custom_keys("QWERTYUI")
        self.assertEqual("QWERTYUI", self.selector.custom_character_entry.text())
        self.assertEqual(list("QWERTYUI"), self.selector.input_character_set)

        # A repeated key, and a ninth one, are both refused rather than taken up
        self.type_custom_keys("Q")
        self.assertEqual("QWERTYUI", self.selector.custom_character_entry.text())
        self.assertEqual(list("QWERTYUI"), self.selector.input_character_set)
        self.type_custom_keys("O")
        self.assertEqual("QWERTYUI", self.selector.custom_character_entry.text())
        self.assertEqual(list("QWERTYUI"), self.selector.input_character_set)

        # Unticking used to leave the custom keys in force with the box emptied
        self.selector.use_custom_set.setChecked(False)
        self.selector.enable_custom_keys_set()
        self.assertEqual("", self.selector.custom_character_entry.text())
        self.assertEqual(list(self.selector.DEFAULT_KEYS), self.selector.input_character_set)

    def test_error_report_never_raises(self) -> None:
        """
            An error escaping the hook hands the process back to qFatal, which aborts
            it with nothing in the terminal but whatever Qt happened to print last
        """
        log = Path(GUI_qt.ERROR_LOG)
        before = log.stat().st_size if log.exists() else 0
        try:
            raise ValueError("a failure to report")
        except ValueError:
            details = sys.exc_info()
        # Reported as though a window were already up, which skips the modal box
        GUI_qt._reporting_error = True
        try:
            GUI_qt.excepthook(*details)
        finally:
            GUI_qt._reporting_error = False
        self.assertTrue(log.exists())
        written = log.read_text(encoding="utf-8")[before:]
        self.assertIn("a failure to report", written)
        self.assertIn("test_error_report_never_raises", written)

    def test_error_report_survives_a_broken_reporter(self) -> None:
        """ Even with the message box and the log unusable, the hook must not raise"""
        original_box, original_log = GUI_qt.QMessageBox, GUI_qt.ERROR_LOG

        class BrokenBox:
            @staticmethod
            def critical(*_args, **_kwargs):
                raise RuntimeError("no window manager")

        GUI_qt.QMessageBox = BrokenBox
        GUI_qt.ERROR_LOG = Path("/nowhere/that/exists/formosa.log")
        GUI_qt._last_reported = None
        try:
            raise KeyError("something to report")
        except KeyError:
            details = sys.exc_info()
        try:
            GUI_qt.excepthook(*details)
        finally:
            GUI_qt.QMessageBox, GUI_qt.ERROR_LOG = original_box, original_log
            GUI_qt._last_reported = None

    def test_phrase_amount_follows_a_theme_set_elsewhere(self) -> None:
        """
            The amount box used to keep offering the amounts of the theme it was set
            for, so a count picked under BIP39 asked a Formosa theme for an entropy
            far past the largest one there is
        """
        self.tabs.tab_clicked(0)
        self.generator.set_base_theme("BIP39")
        self.generator.select_phrases.setValue(24)

        # changed from the Table Selector, without the Password Generator being told
        self.selector.set_base_theme("medieval_fantasy")
        self.assertEqual("medieval_fantasy", self.window.base_theme)

        self.generator.generate_text()
        self.assertTrue(self.generator.last_text)
        self.assertLessEqual(self.generator.select_phrases.value(), 8)

    def press_key(self, key_code: int, text: str = "") -> None:
        """ Send a key release to the Table Selector, as the window would"""
        self.selector.keyReleaseEvent(QKeyEvent(QEvent.KeyRelease, key_code, Qt.NoModifier, text))

    def pick_first_cell(self) -> None:
        """ Pick the opening cell of the grid by the keys written on it"""
        for each_key in self.selector.current_words()[0].text().split("-")[0]:
            self.press_key(ord(each_key.upper()), each_key)
        self.press_key(Qt.Key_Return, "\r")

    def test_backspace_gives_up_the_word_picked_last(self) -> None:
        """ Backspace steps back through the words already picked"""
        self.tabs.tab_clicked(2)
        self.selector.set_base_theme("medieval_fantasy")
        natural_order = self.window.base_dict.natural_order

        for _ in range(3):
            self.pick_first_cell()
        self.assertEqual(3, len(self.selector.picked_passphrase))
        picked_before = list(self.selector.picked_passphrase)

        self.press_key(Qt.Key_Backspace)
        self.assertEqual(picked_before[:2], self.selector.picked_passphrase)
        # The grid goes back to the word the one given up was filling
        self.assertEqual(natural_order[2], self.selector.natural_word)

        self.press_key(Qt.Key_Backspace)
        self.assertEqual(picked_before[:1], self.selector.picked_passphrase)
        self.assertEqual(natural_order[1], self.selector.natural_word)

    def test_backspace_takes_back_a_part_typed_selection_first(self) -> None:
        """ A mistyped key costs one keystroke, not the word picked before it"""
        self.tabs.tab_clicked(2)
        self.selector.set_base_theme("medieval_fantasy")
        self.pick_first_cell()
        self.assertEqual(1, len(self.selector.picked_passphrase))

        written_keys = self.selector.current_words()[0].text().split("-")[0]
        self.press_key(ord(written_keys[0].upper()), written_keys[0])
        self.assertNotEqual(self.selector.states[0], self.selector.current_state)

        # First backspace clears the keys, leaving the picked word alone
        self.press_key(Qt.Key_Backspace)
        self.assertEqual(self.selector.states[0], self.selector.current_state)
        self.assertEqual(1, len(self.selector.picked_passphrase))

        # Only the second one gives up the word
        self.press_key(Qt.Key_Backspace)
        self.assertEqual([], self.selector.picked_passphrase)

    def test_back_button_matches_the_backspace_key(self) -> None:
        """ The button is the same action, for anyone not reaching for the keyboard"""
        self.tabs.tab_clicked(2)
        self.selector.set_base_theme("medieval_fantasy")
        for _ in range(2):
            self.pick_first_cell()
        self.selector.back_button.click()
        self.assertEqual(1, len(self.selector.picked_passphrase))
        self.selector.back_button.click()
        self.assertEqual([], self.selector.picked_passphrase)

        # Going back past the start is harmless and frees the theme again
        self.selector.back_button.click()
        self.assertEqual([], self.selector.picked_passphrase)
        self.assertEqual(self.window.base_dict.natural_order[0], self.selector.natural_word)
        self.assertTrue(self.selector.select_base_theme.isEnabled())

    def test_a_word_given_up_can_be_picked_again(self) -> None:
        """ Going back and forward again lands on a phrase of the right length"""
        self.tabs.tab_clicked(2)
        self.selector.set_base_theme("nationalities")
        phrase_length = len(self.window.base_dict.natural_order)
        for _ in range(phrase_length):
            self.pick_first_cell()
        self.assertTrue(self.selector.output_button.isEnabled())

        self.press_key(Qt.Key_Backspace)
        self.assertFalse(self.selector.output_button.isEnabled())
        self.pick_first_cell()
        self.assertEqual(phrase_length, len(self.selector.picked_passphrase))
        self.assertTrue(self.selector.output_button.isEnabled())

    def test_generate_is_offered_only_for_a_whole_phrase(self) -> None:
        """
            Changing theme enabled the whole panel, which switched Generate Phrase on
            with nothing picked at all
        """
        self.tabs.tab_clicked(2)
        for theme in ("medieval_fantasy", "nationalities", "finances"):
            with self.subTest(theme=theme):
                self.selector.set_base_theme(theme)
                self.assertEqual([], self.selector.picked_passphrase)
                self.assertFalse(self.selector.output_button.isEnabled())
                self.assertFalse(self.selector.back_button.isEnabled())

    def test_words_are_not_carried_across_a_theme_change(self) -> None:
        """ A phrase belongs to the theme whose lists it was picked from"""
        self.tabs.tab_clicked(2)
        self.selector.set_base_theme("medieval_fantasy")
        self.pick_first_cell()
        carried = list(self.selector.picked_passphrase)
        self.assertTrue(carried)

        self.selector.set_base_theme("nationalities")
        self.assertEqual([], self.selector.picked_passphrase)
        for each_word in carried:
            self.assertNotIn(each_word, self.selector.picked_passphrase)

    def test_grid_keys_come_from_an_unguessable_source(self) -> None:
        """
            The shuffle of the grid keys is the whole of what hides the chosen word
            from an onlooker, and every permutation it draws is shown on screen. Drawn
            from a Mersenne Twister, as it was, those permutations are a stream an
            observer can use to recover the generator state and predict the next ones
        """
        import random as stdlib_random
        self.assertIsInstance(GUI_qt.grid_random, stdlib_random.SystemRandom)
        self.assertNotIn("import random", Path(GUI_qt.__file__).read_text(encoding="utf-8"))

        # The keys really do move between grids
        self.tabs.tab_clicked(2)
        self.selector.set_base_theme("medieval_fantasy")
        seen = set()
        for _ in range(12):
            self.selector.new_grid()
            seen.add("".join(self.selector.input_set_column))
        self.assertGreater(len(seen), 1)

    def test_every_tab_is_ready_when_the_window_opens(self) -> None:
        """
            Only the first tab used to be set up when the window was built, so the
            others opened blank, with unlabelled buttons and an empty theme list, and
            filled themselves in at whatever moment they were first clicked
        """
        for index in range(self.tabs.tab_control.count()):
            tab = self.tabs.tab_control.widget(index)
            with self.subTest(tab=self.tabs.tab_control.tabText(index)):
                self.assertFalse(tab.set_config, "tab was left to configure itself later")
        self.assertEqual("Convert to theme", self.converter.convert_button.text())
        self.assertEqual(len(self.window.themes), self.converter.select_new_theme.count())
        self.assertEqual("Generate\nPhrase", self.selector.output_button.text())
        self.assertTrue(self.selector.current_words())

    def test_visiting_another_tab_keeps_the_phrase(self) -> None:
        """
            Every tab click calls set_base_theme with the theme already in force, so
            clearing the phrase there threw away a phrase merely by looking at another
            tab. Leaving it alone is not enough either: the grid used to be put back on
            the opening word, so the next pick filled the wrong slot of the phrase
        """
        self.tabs.tab_clicked(2)
        self.selector.set_base_theme("medieval_fantasy")
        natural_order = self.window.base_dict.natural_order
        for _ in range(2):
            self.pick_first_cell()
        picked = list(self.selector.picked_passphrase)
        self.assertEqual(2, len(picked))

        self.tabs.tab_clicked(0)
        self.tabs.tab_clicked(2)
        self.assertEqual(picked, self.selector.picked_passphrase)
        # and the grid is still on the slot the phrase has reached
        self.assertEqual(natural_order[2], self.selector.natural_word)

        self.pick_first_cell()
        self.assertEqual(3, len(self.selector.picked_passphrase))
        self.assertEqual(picked, self.selector.picked_passphrase[:2])

    def test_converter_reports_bad_input_without_raising(self) -> None:
        """ Whatever is typed in the converter has to end up as a message, never as a crash"""
        self.tabs.tab_clicked(1)
        self.converter.set_base_theme("medieval_fantasy")
        self.converter.set_new_theme("BIP39")
        good = GUI_qt.mnemonic.Mnemonic("medieval_fantasy").generate(128)
        for text in ("", "   ", "not a mnemonic at all", good, good + " extra", good.upper()):
            with self.subTest(text=text[:24]):
                self.converter.base_mnemonic_box.setText(text)
                self.converter.convert_theme()
                self.assertTrue(self.converter.new_mnemonic_box.toPlainText())


def __main__() -> None:
    unittest.main()


if __name__ == "__main__":
    __main__()
