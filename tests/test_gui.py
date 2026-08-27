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
                "custom_character_entry output_button grid_scroll_area select_base_theme quit_button"),
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

    def test_words_grid_scrolls_instead_of_growing_the_window(self) -> None:
        """ A theme with more words than the screen shows must scroll, not resize the window"""
        self.tabs.tab_clicked(2)
        self.selector.set_base_theme("medieval_fantasy")
        self.window.resize(*self.SMALL_SCREEN)
        self.application.processEvents()
        self.assertLessEqual(self.selector.grid_scroll_area.height(), self.window.height())
        self.assertTrue(self.selector.grid_scroll_area.widgetResizable())

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
