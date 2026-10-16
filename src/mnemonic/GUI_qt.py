from PyQt5.QtWidgets import (QMainWindow, QApplication, QWidget, QTabWidget, QLabel, QPushButton, QComboBox,
                             QSpinBox, QLineEdit, QTextEdit, QVBoxLayout, QGridLayout, QCheckBox, QMessageBox,
                             QSizePolicy, QShortcut)
from PyQt5.QtGui import QFont, QFontMetrics, QKeyEvent, QFocusEvent, QKeySequence
from PyQt5.QtCore import Qt
import mnemonic
import secrets
import sys
import traceback
from pathlib import Path

# This prevents IDE from creating a cache file
sys.dont_write_bytecode = True

ERROR_LOG = Path.home() / Path(".formosa_error.log")
# The shuffle of the grid keys is the whole of what hides the chosen word from someone
#  watching the keys pressed, and every permutation it draws is shown on screen for that
#  watcher to read. The default random module is a Mersenne Twister, whose internal state
#  can be reconstructed from the output it has already given, so the keys are drawn from
#  the system entropy source instead, which gives an observer nothing to extrapolate from
grid_random = secrets.SystemRandom()
# An error raised while reporting an error must not start the reporting over again
_reporting_error = False
# The last error shown, so one which repeats is written down rather than shown again
_last_reported = None


def excepthook(exception_type, exception_value, exception_traceback):
    """
        Report an unhandled error instead of letting it escape a slot

        PyQt5 calls qFatal(), which aborts the process, whenever a Python exception
         propagates out of a signal handler. Installing a hook of our own keeps the
         window alive and tells the user what went wrong rather than vanishing on them.

        Nothing here is allowed to raise. An error escaping this hook would hand the
         process back to qFatal, which is the very abort the hook is here to prevent,
         and would leave the terminal with no trace of what actually went wrong.
    """
    global _reporting_error, _last_reported
    report = "".join(traceback.format_exception(exception_type, exception_value, exception_traceback))
    try:
        sys.stderr.write(report)
        sys.stderr.flush()
    except Exception:
        pass
    try:
        # Kept on disk as well, since the window is often started without a terminal
        with open(ERROR_LOG, "a", encoding="utf-8") as error_file:
            error_file.write(report)
    except Exception:
        pass
    if _reporting_error:
        # Already showing one, a second window on top of it would only hide the first
        return
    same_error = (exception_type.__name__, str(exception_value))
    if same_error == _last_reported:
        # A window manager resizing a window sends events in a stream, so the same
        #  error can arrive over and over. It is written down, but shown only once
        return
    _last_reported = same_error
    _reporting_error = True
    try:
        if QApplication.instance() is not None:
            QMessageBox.critical(None, "Formosa", "Something went wrong:\n\n%s: %s\n\nWritten to %s"
                                 % (exception_type.__name__, exception_value, ERROR_LOG))
    except Exception:
        pass
    finally:
        _reporting_error = False


class BaseTab(QWidget):
    def __init__(self, parent: 'QtFormosa'):
        super().__init__(parent)
        self.parent = parent

        # General tab variables
        self.set_config = True
        self.base_theme = self.parent.base_theme
        self.main_layout = QVBoxLayout()
        self.tab_layout = QGridLayout()

        # Widgets instantiation
        self.select_base_theme = QComboBox(self)
        self.select_base_theme.addItems(self.parent.themes)
        self.select_base_theme.setCurrentText(self.base_theme)
        self.select_base_theme.currentTextChanged.connect(self.set_base_theme)
        self.quit_button = QPushButton(self)
        self.quit_button.setText("Exit")
        self.quit_button.clicked.connect(self.close_application)

        self.set_layout()

    @property
    def is_bip39_theme(self) -> bool:
        """ Evaluates whether the theme chosen is from BIP39 or not"""
        # Read from the parent, which every tab shares, so a theme picked in another tab
        #  is never answered from a copy left behind on this one
        is_bip39 = self.parent.base_theme.startswith(self.parent.DEFAULT_THEME)
        return is_bip39

    def set_layout(self):
        """ Place the tab containers of the widgets"""
        self.main_layout.addWidget(self.select_base_theme)
        self.main_layout.addLayout(self.tab_layout)
        self.main_layout.addWidget(self.quit_button)

        self.setLayout(self.main_layout)

    def init_configuration(self):
        """
            Common base method to initialize the tab configuration of all tabs with config_tab() method
            Do the configuration only once by setting the config variable to False for each of the tabs instances
        """
        if not self.set_config:
            # Do it only once
            return
        self.config_tab()
        self.set_config = False

    def config_tab(self):
        """ Overloaded in each tab, set up the widgets"""
        pass

    def set_tab_layout(self):
        """ Overloaded in each tab, place the widgets"""
        pass

    def set_base_theme(self, theme_chosen: str):
        """
            Set the current base theme

        Parameters
        ----------
        theme_chosen : str
            The theme to be set, must be one of found themes in .json files
        """
        self.parent.set_base_theme(theme_chosen)
        self.base_theme = theme_chosen
        self.select_base_theme.setCurrentText(theme_chosen)

    def close_application(self):
        """ Close the parent which exit the application. Bye, come again!"""
        self.parent.close()


class MnemonicGeneratorTab(BaseTab):
    def __init__(self, parent: 'QtFormosa'):
        super().__init__(parent)
        self.parent = parent

        # General tab variables
        self.last_text = ""
        self.password_lines = []
        self.last_n_phrases = 0

        # Widgets instantiation
        self.text_box = QTextEdit(self)
        self.run_button = QPushButton(self)
        self.clip_button = QPushButton(self)
        self.redo_button = QPushButton(self)
        self.clear_button = QPushButton(self)
        self.select_phrases = QSpinBox(self)
        self.check_number = QCheckBox(self)
        self.check_char = QCheckBox(self)
        self.check_case = QCheckBox(self)
        self.save_button = QPushButton(self)
        self.save_msg = QLabel(self)
        self.copy_msg = QLabel(self)
        self.enable_checkboxes()

    def config_tab(self):
        """ Set up widgets, config texts, commands and variables """
        self.run_button.setText("Run!")
        self.run_button.clicked.connect(self.generate_text)
        self.clip_button.setText("Copy")
        self.clip_button.clicked.connect(self.copy_to_clipboard)
        self.redo_button.setText("Redo")
        self.redo_button.clicked.connect(self.recover_text)
        self.clear_button.setText("Clear")
        self.clear_button.clicked.connect(self.clear_text)
        self.check_case.setText("Include Uppercase")
        self.check_case.clicked.connect(self.insert_swap_case)
        self.check_number.setText("Include Number")
        self.check_number.clicked.connect(self.insert_number)
        self.check_char.setText("Include Special Character")
        self.check_char.clicked.connect(self.insert_spc_char)
        self.save_button.setText("Save")
        self.save_button.clicked.connect(self.save_file)
        self.copy_msg.setText("Copied to clipboard")
        self.copy_msg.hide()
        self.save_msg.setText("Saved to \'output.txt\'")
        self.save_msg.hide()

        self.config_phrases_selector()
        self.set_tab_layout()

    def set_tab_layout(self):
        """ Place the widgets in the window tab"""
        self.text_box.setGeometry(0, 0, 20, 75)
        self.tab_layout.addWidget(self.run_button, 0, 0)
        self.tab_layout.addWidget(self.clip_button, 1, 0)
        self.tab_layout.addWidget(self.text_box, 0, 4, 10, 5)
        self.tab_layout.addWidget(self.select_phrases, 2, 0)
        self.tab_layout.addWidget(self.check_case, 3, 0)
        self.tab_layout.addWidget(self.check_char, 4, 0)
        self.tab_layout.addWidget(self.check_number, 5, 0)
        self.tab_layout.addWidget(self.redo_button, 6, 0)
        self.tab_layout.addWidget(self.clear_button, 7, 0)
        self.tab_layout.addWidget(self.save_button, 8, 0)
        self.tab_layout.addWidget(QLabel(), 0, 1)
        self.tab_layout.addWidget(self.copy_msg, 1, 1)
        self.tab_layout.addWidget(self.save_msg, 8, 1)

    def set_base_theme(self, theme_chosen: str):
        """
            Set the current base theme

        Parameters
        ----------
        theme_chosen : str
            The theme to be set, must e one of found themes in .json files
        """
        super().set_base_theme(theme_chosen)
        self.config_phrases_selector()
        self.enable_checkboxes()

    def phrases_range(self) -> tuple:
        """
            The least and the most phrases the theme in force is able to encode

        Returns
        -------
        tuple
            The smallest and the largest amount of phrases which can be generated
        """
        return (3, 24) if self.is_bip39_theme else (1, 8)

    def config_phrases_selector(self):
        """ Set the correct values to be selected while generating random phrases"""
        min_phrases, max_phrases = self.phrases_range()
        self.select_phrases.setRange(min_phrases, max_phrases)
        self.select_phrases.setSingleStep(min_phrases)
        self.select_phrases.setValue(min_phrases)
        self.select_phrases.setWrapping(True)

    def selected_phrases(self) -> int:
        """
            The amount of phrases to generate, snapped to a value the theme can encode

            The spin box only steps in valid amounts, but a typed value is not snapped by Qt,
             and a BIP39 word count which is not a multiple of 3 has no matching entropy size

        Returns
        -------
        int
            The amount of phrases which the current theme is able to generate
        """
        min_phrases, max_phrases = self.phrases_range()
        if (self.select_phrases.minimum(), self.select_phrases.maximum()) != (min_phrases, max_phrases):
            # The theme belongs to the window and can be changed from any tab, which
            #  leaves this box offering the amounts of the theme it was last set for
            self.select_phrases.setRange(min_phrases, max_phrases)
            self.select_phrases.setSingleStep(min_phrases)
        phrase_size = self.select_phrases.value()
        if self.is_bip39_theme:
            # Every 3 BIP39 words encode 32 bits of entropy, so partial groups cannot be built
            phrase_size = max(min_phrases, phrase_size - phrase_size % 3)
        if phrase_size != self.select_phrases.value():
            self.select_phrases.setValue(phrase_size)
        return phrase_size

    def enable_checkboxes(self, enable: bool = True):
        """
            Enable or disable the password checkboxes all together

        Parameters
        ----------
        enable : bool
            Enable or disable the checkboxes
        """
        self.check_case.setEnabled(enable)
        self.check_char.setEnabled(enable)
        self.check_number.setEnabled(enable)

    def generate_text(self):
        """ Call generate_format which build a mnemonic phrase in Formosa standard then updates displayed text"""
        self.save_msg.hide()
        phrase_size = self.selected_phrases()
        strength = 32*phrase_size//3 if self.is_bip39_theme else 32 * phrase_size
        words = self.parent.base_mnemonic.generate(strength)
        text = self.parent.base_mnemonic.format_mnemonic(words)+"\n"
        self.last_text = self.last_text + text
        # Keep the password lines
        password_position = self.password_lines[-1] + self.last_n_phrases + 1 if self.password_lines else 0
        self.password_lines.append(password_position)
        self.last_n_phrases = phrase_size

        self.update_text()
        self.change_password()

    def change_password(self):
        """ Change characters in passwords all together"""
        if self.check_number.isChecked():
            self.insert_number()
        if self.check_char.isChecked():
            self.insert_spc_char()
        if self.check_case.isChecked():
            self.insert_swap_case()

    def update_text(self):
        """ Insert text in the box of Mnemonic Generator tab"""
        self.text_box.setText(self.last_text)
        self.copy_to_clipboard()
        self.copy_msg.show()

    def copy_to_clipboard(self):
        """ Copy the generated phrases to clipboard"""
        # Assigning to QApplication.clipboard replaces the method with a string,
        #  which silently copies nothing and breaks every later clipboard user
        QApplication.clipboard().setText(self.last_text)

    def recover_text(self):
        """ Recover an edited text in the text box to its former self in the Mnemonic Generator tab"""
        self.text_box.clear()
        self.text_box.setText(self.last_text)

    def clear_text(self):
        """ Clear out the text box, copy label and save label in the Mnemonic Generator tab"""
        self.enable_checkboxes()
        self.save_msg.hide()
        self.copy_msg.hide()
        self.text_box.clear()
        self.last_text = ""
        self.password_lines = []

    def save_file(self):
        """ Save the generated phrases to output.txt file"""
        with open("output.txt", "w", encoding="utf-8") as output_file:
            output_file.write(self.last_text)
        self.save_msg.show()

    def insert_number(self):
        """ Change an ordinary character to a number"""
        to_replace = ["a", "b", "e", "g", "i", "o", "q", "s", "t"]
        replace_by = ["4", "8", "3", "6", "1", "0", "9", "5", "7"]
        self.insert_character(to_replace, replace_by, self.check_number.isChecked())

    def insert_spc_char(self):
        """ Change an ordinary character to a special character"""
        to_replace = ["a", "c", "e", "h", "j", "l", "s", "t", "z"]
        replace_by = ["@", "¢", "&", "#", "!", "£", "$", "+", "%"]
        self.insert_character(to_replace, replace_by, self.check_char.isChecked())

    def insert_swap_case(self):
        """ Swap the case of a character"""
        to_replace = list(map(chr, range(97, 123)))
        replace_by = [each_char.swapcase() for each_char in to_replace]
        self.insert_character(to_replace, replace_by, self.check_case.isChecked())

    def insert_character(self, to_replace: list, replace_by: list, check_box_var: bool):
        """
            Find out if the text in the texbox is written as natural or edited
            and calls method replace_characters() with correct order of lists

        Parameters
        ----------
        to_replace : list
            The list of characters to be removed
        replace_by : list
            The list of characters to be inserted
        check_box_var : bool
            This variable tells if the word is written as natural, or it is already edited
        """
        array_criteria = any([each_char in self.last_text for each_char in to_replace])
        if array_criteria:
            replacement_order = (replace_by, to_replace) if check_box_var else (to_replace, replace_by)
            self.replace_characters(replacement_order[0], replacement_order[1], not check_box_var)
        self.update_text()

    def replace_characters(self, insert: list[str], remove: list[str], checkbox_selected: bool = False):
        """
            Replace in the password a character by another character

        Parameters
        ----------
        insert : list[str]
            The list of characters to be inserted
        remove : list[str]
            The list of characters to be removed
        checkbox_selected : bool
            Indicate the respective checkbox selection, it prevents a changed character to be stuck
        """
        lines = self.last_text.splitlines(False)
        for line_index in self.password_lines:
            if not 0 <= line_index < len(lines):
                # The bookkeeping drifted, most likely because the text box was edited by hand
                continue
            password_line = lines[line_index]
            character_index = [remove.index(each_char) for each_char in list(password_line) if each_char in remove]
            changed_character = [each_char for each_char in list(password_line) if each_char in insert]

            if not character_index:
                continue

            remove_char = remove[character_index[0]]
            insert_char = insert[character_index[0]]

            # If there is a changed character then skip it, preventing it to get stuck
            if changed_character and not checkbox_selected:
                if password_line.index(changed_character[0]) < password_line.index(remove_char):
                    continue
            new_line = password_line.replace(remove_char, insert_char, 1)
            self.last_text = self.last_text.replace(password_line, new_line)


class ThemeConverterTab(BaseTab):
    def __init__(self, parent: 'QtFormosa'):
        super().__init__(parent)
        self.parent = parent

        # General tab variables
        self.new_theme = self.parent.base_theme
        self.new_mnemonic = self.parent.base_mnemonic

        # Widgets instantiation
        self.select_new_theme = QComboBox(self)
        self.base_mnemonic_box = QTextEdit(self)
        self.new_mnemonic_box = QTextEdit(self)
        self.convert_button = QPushButton(self)

    def config_tab(self):
        """ Set up widgets, config texts, commands and variables"""
        self.set_new_theme(self.parent.base_theme)

        self.convert_button.setText("Convert to theme")
        self.convert_button.clicked.connect(self.convert_theme)
        self.select_new_theme.addItems(self.parent.themes)
        self.select_new_theme.setCurrentText(self.new_theme)
        self.select_new_theme.currentTextChanged.connect(self.set_new_theme)

        self.set_tab_layout()

    def set_tab_layout(self):
        """ Place the widgets in the window tab"""
        self.base_mnemonic_box.setGeometry(0, 0, 20, 75)
        self.new_mnemonic_box.setGeometry(0, 0, 20, 75)
        self.tab_layout.addWidget(self.base_mnemonic_box, 1, 0)
        self.tab_layout.addWidget(self.new_mnemonic_box, 1, 4)
        self.tab_layout.addWidget(self.convert_button, 4, 0)
        self.tab_layout.addWidget(self.select_new_theme, 4, 4)

    def set_new_theme(self, theme_chosen):
        """ Config the new theme to the phrases be converted to"""
        self.new_theme = theme_chosen
        self.new_mnemonic = mnemonic.Mnemonic(theme_chosen)

    def convert_theme(self):
        """ Converts a seed phrase in Formosa standard from a theme to another also in Formosa standard"""
        mnemonic_words = self.base_mnemonic_box.toPlainText().replace("\n", " ").split(" ")
        mnemonic_words = [each_word for each_word in mnemonic_words if each_word]
        if not len(mnemonic_words):
            self.new_mnemonic_box.clear()
            self.new_mnemonic_box.setText("Empty Input")
            return
        self.new_mnemonic_box.clear()
        phrase_size = self.parent.base_mnemonic.words_dictionary.words_per_phrase
        display_text = ""
        n = 4 if self.is_bip39_theme else 2
        try:
            new_mnemonic_words = self.new_mnemonic.convert_theme(mnemonic_words, self.new_theme, self.base_theme)
            new_mnemonic_words = self.new_mnemonic.format_mnemonic(new_mnemonic_words)
            display_text = new_mnemonic_words
        except (ValueError, KeyError) as first_error:
            try:
                try_words = mnemonic_words[1:]
                new_mnemonic_words = self.new_mnemonic.convert_theme(try_words, self.new_theme, self.base_theme)
                new_mnemonic_words = self.new_mnemonic.format_mnemonic(new_mnemonic_words)
                display_text = new_mnemonic_words
            except Exception as error:
                if len(mnemonic_words) % phrase_size == 1 and len(mnemonic_words[0]) == n * len(mnemonic_words[1:]):
                    display_text = "{}".format(error)
                else:
                    display_text = "{}".format(first_error)
        except Exception as unexpected_error:
            display_text = "Something unexpected went wrong\n{}".format(unexpected_error)
        finally:
            self.new_mnemonic_box.setText(display_text)


class TableSelectorTab(BaseTab):
    COLUMN_LINE_PARAGRAPH_SIZE = 8
    DEFAULT_KEYS = ("A", "S", "D", "F", "J", "K", "L", ";")
    # The table is never scrolled, so the writing is what gives way when room runs short
    SMALLEST_GRID_FONT = 4
    LARGEST_GRID_FONT = 14
    # Writing smaller than this to keep a long word whole is a bad bargain, the words of
    #  a list are already told apart by their first two letters
    COMFORTABLE_GRID_FONT = 7
    PREFERRED_WORD_LETTERS = 10
    MINIMUM_WORD_LETTERS = 6

    class QHighlightCheckBox(QCheckBox):
        def __init__(self, parent: 'TableSelectorTab'):
            super().__init__(parent)
            self.parent = parent

        def focusInEvent(self, e: QFocusEvent) -> None:
            """ Change focus to parent"""
            super().focusInEvent(e)
            self.parent.setFocus()

    class QKeysCheckBox(QCheckBox):
        def __init__(self, parent: 'TableSelectorTab'):
            super().__init__(parent)
            self.parent = parent

        def focusInEvent(self, e: QFocusEvent) -> None:
            """ Change focus to custom characters input"""
            super().focusInEvent(e)
            self.parent.custom_character_entry.setFocus()

    class QKeysLineEdit(QLineEdit):
        def __init__(self, parent: 'TableSelectorTab'):
            super().__init__(parent)
            self.parent = parent

        def keyPressEvent(self, a0: QKeyEvent) -> None:
            """ Set grid indexes when key is pressed"""
            super().keyPressEvent(a0)
            self.parent.define_key_list()

        def change_focus(self):
            """ Change focus to parent"""
            self.parent.setFocus()

    class QResetPushButton(QPushButton):
        def __init__(self, parent: 'TableSelectorTab'):
            super().__init__(parent)
            self.parent = parent

        def focusInEvent(self, e: QFocusEvent) -> None:
            """ Change focus to parent"""
            super().focusInEvent(e)
            self.parent.setFocus()

    def __init__(self, parent: 'QtFormosa'):
        super().__init__(parent)

        # General tab variables
        self.font = QFont('Times', 7)
        self.check_color = "#3AC73A"
        self.defaultbg = ""
        self.valid_phrase = True
        self.words_dictionary = {}
        self.natural_word = self.parent.base_dict.natural_order[0]
        self.object_dict = {}
        self.column_objects = []
        self.line_objects = []
        self.paragraph_objects = []
        self.input_character_set = list(self.DEFAULT_KEYS)
        self.input_set_caseless = []
        self.input_set_column = []
        self.input_set_line = []
        self.input_set_paragraph = []
        self.picked_passphrase = []
        # Which word of the phrase the grid is standing on
        self.word_cursor = 0
        self.panel_widgets = []
        # The states represent what was the last defined dimension
        self.states = ("initial", "column_done", "line_done", "paragraph_done")
        self.current_state = self.states[0]
        self.selected_indexes = {key: self.COLUMN_LINE_PARAGRAPH_SIZE for key in self.states}
        self.permutation_map = {"initial": self.input_set_column,
                                "column_done": self.input_set_line,
                                "line_done": self.input_set_paragraph,
                                "paragraph_done": self.input_set_caseless}

        # Widgets instantiation
        self.reset_button = self.QResetPushButton(self)
        # Same class as Reset, so clicking it hands focus back to the grid and the
        #  keys keep working without the user having to click the table again
        self.back_button = self.QResetPushButton(self)
        self.word_position_label = QLabel(self)
        self.sel_valid_phrase_label = QLabel(self)
        self.highlight_checkbox = self.QHighlightCheckBox(self)
        self.warning_label = QLabel(self)
        self.use_custom_set = self.QKeysCheckBox(self)
        self.custom_character_entry = self.QKeysLineEdit(self)
        self.output_button = QPushButton(self)
        self.grid_frame_selector = QGridLayout()
        self.grid_holder = QWidget(self)
        self.grid_holder.setLayout(self.grid_frame_selector)
        # The font size and word length the grid was last fitted with
        self.grid_fit = ()
        self.resizing = False
        self.panel_max_width = 0
        self.panel_widgets = [self.reset_button, self.back_button,
                              self.word_position_label, self.sel_valid_phrase_label,
                              self.highlight_checkbox, self.warning_label,
                              self.use_custom_set, self.custom_character_entry, self.output_button]
        [each_widget.setEnabled(False) for each_widget in self.panel_widgets]

        self.define_key_list()

    def current_words(self) -> list:
        """
            The labels of the syntactic word the grid is showing

            The theme can be changed from any tab, so the word being shown is checked
             against the theme in force and the selection restarts when it went stale,
             which used to raise KeyError as soon as the grid was touched again

        Returns
        -------
        list
            The labels currently held for the syntactic word being selected
        """
        natural_order = self.parent.base_dict.natural_order
        if self.natural_word not in natural_order:
            self.picked_passphrase = []
            self.set_word_cursor(0)
        return self.object_dict.get(self.natural_word, [])

    def set_word_cursor(self, position: int):
        """
            Stand the grid on a given word of the phrase

        Parameters
        ----------
        position : int
            Which word of the phrase to stand on, held within the words there are
        """
        natural_order = self.parent.base_dict.natural_order
        if not natural_order:
            self.natural_word = ""
            return
        # Only as far as the word being filled, never past the end of the phrase
        self.word_cursor = max(0, min(position, len(self.picked_passphrase)))
        self.natural_word = natural_order[self.word_cursor % len(natural_order)]
        self.update_word_position()

    def update_word_position(self):
        """
            Say which word of the phrase the grid is standing on

            The arrows move the grid about without the words on it saying where it
             went, so the place is written out beside the compatibility of the phrase
        """
        natural_order = self.parent.base_dict.natural_order
        if not natural_order:
            self.word_position_label.setText("")
            return
        phrase_length = len(natural_order)
        place_in_phrase = self.word_cursor % phrase_length
        phrases_before = self.word_cursor // phrase_length
        place = "Word %d of %d" % (place_in_phrase + 1, phrase_length)
        if phrases_before:
            # Only once a phrase has been finished is there more than one to tell apart
            place = "Phrase %d, word %d of %d" % (phrases_before + 1, place_in_phrase + 1, phrase_length)
        # The grid shows the words of a syntactic word without ever naming it
        named = natural_order[place_in_phrase].replace("_", " ").capitalize()
        self.word_position_label.setText("%s\n%s" % (place, named))

    def step_word(self, step: int):
        """
            Move the grid a word along the phrase, coming round again at either end

            Only the words already picked can be reached, and the one being filled
             after them, so moving on never skips a word which was never given

        Parameters
        ----------
        step : int
            How many words to move, negative to move back
        """
        if self.is_bip39_theme:
            return
        a = self.COLUMN_LINE_PARAGRAPH_SIZE
        # Every word picked, and the one being filled after the last of them
        reachable = len(self.picked_passphrase) + 1
        self.set_word_cursor((self.word_cursor + step) % reachable)
        self.current_state = self.states[0]
        [self.selected_indexes.update({each_key: a}) for each_key in self.selected_indexes.keys()]
        self.new_grid()
        self.check_word_list()
        self.update_action_buttons()

    def phrase_follows_theme(self) -> bool:
        """
            Whether every word picked is one the word leading it allows

        Returns
        -------
        bool
            Whether the phrase so far reads as the theme permits
        """
        themed_dict = self.parent.base_dict
        natural_order = themed_dict.natural_order
        if not natural_order:
            return True
        for position, each_word in enumerate(self.picked_passphrase):
            syntactic_word = natural_order[position % len(natural_order)]
            led_by = themed_dict[syntactic_word].led_by
            # A word standing on its own has nothing to disagree with
            if led_by not in natural_order:
                continue
            sentence_start = (position // len(natural_order)) * len(natural_order)
            led_by_position = natural_order.index(led_by) + sentence_start
            if led_by_position >= len(self.picked_passphrase):
                continue
            mapping = themed_dict[led_by][syntactic_word].mapping
            if each_word not in mapping.get(self.picked_passphrase[led_by_position], []):
                return False
        return True

    def clear_grid(self):
        """ Clear grid variables and widgets"""
        # Every label built for the previous grid is dropped, not only the ones which
        #  reached the layout, otherwise the cells left out of it pile up as hidden
        #  children of the tab on each of the many rebuilds a session goes through
        previous_labels = (self.column_objects + self.line_objects + self.paragraph_objects
                           + [each_label for each_list in self.object_dict.values()
                              for each_label in each_list])

        self.column_objects = []
        self.line_objects = []
        self.paragraph_objects = []

        self.object_dict = {}
        [self.object_dict.update({each_word: []})
         for each_word in self.parent.base_dict.natural_order]

        for i in reversed(range(self.grid_frame_selector.count())):
            self.grid_frame_selector.takeAt(i)
        for each_label in previous_labels:
            each_label.setParent(None)
            each_label.deleteLater()

    def config_tab(self):
        """ Set up widgets, config texts, commands and variables"""
        self.highlight_checkbox.setText("Show\nHighlight")
        self.highlight_checkbox.clicked.connect(self.changed_show_highlight)
        self.reset_button.setText("Reset")
        self.reset_button.clicked.connect(self.reset_selection)
        self.back_button.setText("Back\n(Backspace)")
        self.back_button.clicked.connect(self.go_back)
        valid_message = "Selected phrase\nso far is compatible"
        self.sel_valid_phrase_label.setText(valid_message)
        self.sel_valid_phrase_label.setStyleSheet("background-color: " + self.check_color)
        warning_message = "Very careful\nwith prying eyes"
        self.warning_label.setText('<font color="red"> ' + warning_message + '</font>')
        self.use_custom_set.setText("Use custom\nset of keys")
        self.use_custom_set.clicked.connect(self.enable_custom_keys_set)
        self.output_button.setText("Generate\nPhrase")
        self.output_button.clicked.connect(self.output_phrases)
        self.output_button.setEnabled(False)
        self.update_word_position()

        self.new_grid()
        self.set_tab_layout()

    def set_tab_layout(self):
        """ Place the widgets in the window tab"""
        # Position each widget to next row
        [self.tab_layout.addWidget(each_widget, self.panel_widgets.index(each_widget), 0)
         for each_widget in self.panel_widgets]

        # The whole table has to be read without scrolling: a shoulder surfer who sees
        #  the user scroll learns which band of the table the word sits in, which is
        #  exactly what the shuffled column, line and paragraph keys are there to hide
        self.grid_frame_selector.setSpacing(1)
        self.grid_frame_selector.setContentsMargins(0, 0, 0, 0)
        self.grid_holder.setSizePolicy(QSizePolicy.Ignored, QSizePolicy.Ignored)
        # Spanning the rows of the panel, not one row per grid cell, otherwise the spacing
        #  of the empty rows alone sets a minimum height taller than the screen
        spare_row = len(self.panel_widgets)
        self.tab_layout.addWidget(self.grid_holder, 0, 2, spare_row + 1, 1)
        # The panel keeps its buttons at their own height at the top of the column,
        #  and the empty row below it takes the height left over
        self.tab_layout.setRowStretch(spare_row, 1)
        # The panel keeps its width and the grid takes whatever room is left
        self.tab_layout.setColumnStretch(0, 0)
        self.tab_layout.setColumnStretch(2, 1)
        self.update_panel_width()

    def update_panel_width(self):
        """ Keep the panel to a third of the window, following it as it is resized"""
        max_width = max(self.parent.width()//3, 1)
        if max_width == self.panel_max_width:
            # Setting it again would lay out the tab once more and call this back
            return
        self.panel_max_width = max_width
        [each_widget.setMaximumWidth(max_width) for each_widget in self.panel_widgets]

    def resizeEvent(self, event):
        """ Follow the window size, as the panel width and the grid are a share of it"""
        super().resizeEvent(event)
        # The base class lays the tab out while this one is still being built,
        #  so the panel is only measured once its widgets are in place
        if not getattr(self, "panel_widgets", None) or self.resizing:
            return
        # Fitting the grid lays the tab out again, and a window manager resizing a
        #  window sends a stream of these, so one pass is never re-entered by another
        self.resizing = True
        try:
            self.update_panel_width()
            self.fit_grid_to_view()
        finally:
            self.resizing = False

    def displayed_paragraphs(self, words_amount: int) -> int:
        """
            How many paragraphs of the grid the words of a syntactic word reach

        Parameters
        ----------
        words_amount : int
            The amount of words to be shown in the grid

        Returns
        -------
        int
            The amount of paragraphs needed, never more than the grid holds
        """
        a = self.COLUMN_LINE_PARAGRAPH_SIZE
        paragraph_size = a * a
        # Rounded up, so a list which fills its paragraphs exactly does not open an empty one
        paragraphs = (max(words_amount, 1) + paragraph_size - 1) // paragraph_size
        return min(a, paragraphs)

    def fit_grid_to_view(self):
        """
            Size the words of the grid so the whole table is read in a single view

            The table must never scroll, so instead of the view following the words,
             the words are fitted to the view: the font is taken down until every row
             fits the height available and every word is cut to the width of its column
        """
        current_objects = self.current_words()
        if not current_objects or self.is_bip39_theme:
            return
        a = self.COLUMN_LINE_PARAGRAPH_SIZE
        total_words = self.parent.base_dict[self.natural_word].total_words
        # A header row of column keys, then one row per line of every paragraph shown
        rows = 1 + self.displayed_paragraphs(len(current_objects)) * a
        # The word columns, the paragraph key column and the line key column
        columns = a + 2
        spacing = self.grid_frame_selector.spacing()
        # Measured after the layout is settled, otherwise the size read here is the one
        #  the grid had before the theme, the window or the panel last changed
        self.layout().activate()
        available = self.grid_holder.size()
        row_height = (available.height() - spacing * rows) // rows
        usable_width = available.width() - spacing * columns
        if row_height < 1 or usable_width < 1:
            return

        longest_word = max((len(each_word) for each_word in total_words[:len(current_objects)]), default=1)
        font_size, letters = self.grid_writing(row_height, usable_width, longest_word)
        if (self.natural_word, font_size, letters) == self.grid_fit:
            # Writing the same thing again would lay the tab out once more and call this back
            return
        self.grid_fit = (self.natural_word, font_size, letters)

        grid_font = QFont("Times", font_size)
        metrics = QFontMetrics(grid_font)
        for each_object in self.column_objects + self.line_objects + self.paragraph_objects:
            each_object.setFont(grid_font)
        for cell_index, each_object in enumerate(current_objects):
            each_object.setFont(grid_font)
            if cell_index < len(total_words):
                # Cut against the room the cell was actually given, rather than against
                #  a guess at it, so no word is left clipped in the middle of a letter
                each_object.setText(
                    self._get_text(total_words, cell_index, metrics, each_object.width()))

    def grid_writing(self, row_height: int, usable_width: int, longest_word: int) -> tuple:
        """
            The writing which shows the most of the table within the room it is given

            Keeping every word whole is preferred, but only while the writing stays
             comfortable to read. A single long word is not allowed to shrink the whole
             table, since the words of a list are told apart by their first two letters

        Parameters
        ----------
        row_height : int
            The height available to a single row of the grid
        usable_width : int
            The width available to a whole row of the grid
        longest_word : int
            The length of the longest word which has to be shown

        Returns
        -------
        tuple
            The point size to write the grid with and how many letters of a word it shows
        """
        a = self.COLUMN_LINE_PARAGRAPH_SIZE
        smallest = None
        recognisable = None
        good_part = None
        whole_words = None
        for each_size in range(self.SMALLEST_GRID_FONT, self.LARGEST_GRID_FONT + 1):
            metrics = QFontMetrics(QFont("Times", each_size))
            if metrics.height() > row_height:
                break
            # The paragraph and the line key columns hold a single character each
            word_column = (usable_width - 2 * metrics.horizontalAdvance("W")) // a
            letters = self.fitting_word_length(metrics, word_column)
            if smallest is None:
                smallest = (each_size, letters)
            if letters >= self.MINIMUM_WORD_LETTERS:
                recognisable = (each_size, letters)
            if letters >= self.PREFERRED_WORD_LETTERS:
                good_part = (each_size, letters)
            if letters >= longest_word:
                whole_words = (each_size, letters)
        # Whole words in comfortable writing, else the largest writing showing a good
        #  part of the word, else the largest one showing enough of it to be recognised
        if whole_words is not None and whole_words[0] >= self.COMFORTABLE_GRID_FONT:
            return whole_words
        if good_part is not None and good_part[0] >= self.COMFORTABLE_GRID_FONT:
            return good_part
        return recognisable or good_part or whole_words or smallest or (self.SMALLEST_GRID_FONT, 1)

    @staticmethod
    def fitting_word_length(metrics: QFontMetrics, column_width: int) -> int:
        """
            How many letters of a word fit a column, once the keys prefixing it are placed

        Parameters
        ----------
        metrics : QFontMetrics
            The measurements of the font the grid is written with
        column_width : int
            The width available to a single word column of the grid

        Returns
        -------
        int
            The amount of letters of the word which fit the column
        """
        # The three keys and the hyphen are always shown, they are what is typed
        prefix_width = metrics.horizontalAdvance("WWW-")
        letter_width = max(metrics.horizontalAdvance("n"), 1)
        return max(1, (column_width - prefix_width) // letter_width)

    def set_base_theme(self, theme_chosen):
        """
            Set the current base theme, enabling or not each widget on the panel according to theme chosen

        Parameters
        ----------
        theme_chosen : str
            The theme to be set, must e one of found themes in .json files
        """
        # Asked before the base class records the new one, and only a real change
        #  discards the phrase: every tab click calls this with the theme already in
        #  force, and visiting the tab must not throw away a phrase being built
        theme_changed = theme_chosen != self.base_theme
        super().set_base_theme(theme_chosen)
        state = self.is_bip39_theme
        [each_widget.setEnabled(not state) for each_widget in self.panel_widgets]
        if theme_changed:
            # A phrase is built out of one theme's lists, so words picked under the
            #  theme being left cannot be carried into the new one and written out
            self.picked_passphrase = []
            self.valid_phrase = True
        # Held within the phrase rather than set back to its opening word, which used
        #  to put the grid out of step with a phrase already part way built
        self.set_word_cursor(self.word_cursor)
        self.current_state = self.states[0]
        # The theme may only be changed while no word of a phrase is being held
        self.select_base_theme.setEnabled(not self.picked_passphrase)
        self.new_grid()
        self.set_validation_colored_msg()
        # Enabling the whole panel above has just overridden what these two say about
        #  the phrase, so they are asked again rather than left reading wrongly
        self.update_action_buttons()
        self.setFocus()

    def init_label_objects(self):
        """ Configure the objects in the grid of the Table Selector tab, all labels must initialize hidden"""
        a = self.COLUMN_LINE_PARAGRAPH_SIZE
        words_dictionary = self.parent.base_dict
        syntactic_word_list = words_dictionary.natural_order

        # Clear grid widgets
        self.clear_grid()

        # Write the characters in column, line and paragraph indexes
        self.column_objects = [QLabel(parent=self, text=self.input_set_column[column])
                               for column in range(a)]
        # Index line is get by repeating 0 to 'a' for 'a' times, e.g. [0, ...7, 0, ...7, 0, ...7]
        self.line_objects = [QLabel(parent=self, text=self.input_set_line[line])
                             for paragraph in range(a) for line in range(a)]
        # Index line is get by repeating 0 'a' times to 'a', e.g. [0, 0, ..., 1, 1, ..., 7, 7]
        self.paragraph_objects = [QLabel(parent=self, text=self.input_set_paragraph[paragraph])
                                  for paragraph in range(a) for line in range(a)]

        # The cell index counts the columns of a line, then the lines of a paragraph,
        #  so a label lands at the same position in the list as its word in the theme
        for each_syntactic_word in syntactic_word_list:
            total_words = words_dictionary[each_syntactic_word].total_words
            self.object_dict[each_syntactic_word] = [
                QLabel(parent=self, text=self._get_text(total_words, cell_index))
                for cell_index in range(min(len(total_words), a * a * a))]

        for each_object in (self.column_objects + self.line_objects + self.paragraph_objects
                            + [each_label for each_list in self.object_dict.values()
                               for each_label in each_list]):
            each_object.setFont(self.font)
            # The grid takes the room the window leaves it and the words are fitted into
            #  it, rather than the labels asking for room and pushing the window outwards
            each_object.setSizePolicy(QSizePolicy.Ignored, QSizePolicy.Ignored)
            each_object.setMinimumSize(0, 0)
            each_object.hide()

    def new_grid(self):
        """ Call the sequence to create and show a new words grid in the Table Selector tab"""
        self.randomize_character_set()
        self.init_label_objects()
        self.allocate_grid()
        # The labels are new, so the last fit says nothing about them
        self.grid_fit = ()
        self.fit_grid_to_view()

    def enable_custom_keys_set(self):
        """ Enable the use of custom keys in the Table Selector tab"""
        if self.use_custom_set.isChecked():
            self.custom_character_entry.setEnabled(True)
        else:
            self.custom_character_entry.setEnabled(False)
            self.custom_character_entry.setText("")
            # Unticking used to leave the custom keys in force, with nothing on screen
            #  saying so and the box emptied of the only record of what they were
            self.input_character_set = list(self.DEFAULT_KEYS)
            self.new_grid()

    def define_key_list(self):
        """
            Set the keys used as index of the grid in the Table Selector tab

            The box is held to the keys which are really in use: a repeated key is
             dropped and anything past the eighth is refused, so a key read off the
             grid always picks the cell it is written on
        """
        typed_characters = self.custom_character_entry.text().upper()
        chosen_keys = []
        for each_character in typed_characters:
            if each_character not in chosen_keys and len(chosen_keys) < self.COLUMN_LINE_PARAGRAPH_SIZE:
                chosen_keys.append(each_character)
        if "".join(chosen_keys) != typed_characters:
            self.custom_character_entry.setText("".join(chosen_keys))

        # A set short of a key cannot index the grid, so the default keys stay in use
        complete_set = len(chosen_keys) == self.COLUMN_LINE_PARAGRAPH_SIZE
        self.use_key_set(chosen_keys if complete_set else self.DEFAULT_KEYS)
        if complete_set:
            self.custom_character_entry.change_focus()

    def use_key_set(self, key_set):
        """
            Take up a set of keys to index the grid with

        Parameters
        ----------
        key_set : list
            The keys the columns, lines and paragraphs of the grid are indexed by
        """
        if list(key_set) == list(self.input_character_set):
            return
        self.input_character_set = list(key_set)
        self.new_grid()

    def randomize_character_set(self):
        """ Randomize the indexes of the grid independently of each other in the Table Selector tab"""
        # Copied before shuffling, otherwise the set the user typed is permuted
        #  in place and there is no longer a record of what was asked for
        input_chars = list(self.input_character_set)
        grid_random.shuffle(input_chars)
        self.input_set_caseless = input_chars + list([each_char.swapcase() for each_char in input_chars])
        column_char_set = input_chars.copy()
        grid_random.shuffle(column_char_set)
        self.input_set_column = column_char_set + list([each_char.swapcase() for each_char in column_char_set])
        line_char_set = input_chars.copy()
        grid_random.shuffle(line_char_set)
        self.input_set_line = line_char_set + list([each_char.swapcase() for each_char in line_char_set])
        paragraph_char_set = input_chars.copy()
        grid_random.shuffle(paragraph_char_set)
        self.input_set_paragraph = paragraph_char_set + list([each_char.swapcase() for each_char in paragraph_char_set])
        self.permutation_map.update({self.states[0]: self.input_set_caseless})
        self.permutation_map.update({self.states[1]: self.input_set_column})
        self.permutation_map.update({self.states[2]: self.input_set_paragraph})
        self.permutation_map.update({self.states[3]: self.input_set_line})

    def _get_text(self, word_list: list[str], cell_index: int,
                  metrics: QFontMetrics = None, cell_width: int = 0):
        """
            Build up the string to be displayed in the word Label

        Parameters
        ----------
        word_list : list[str]
            The total words of the current displayed grid
        cell_index : int
            Index of the cell in the grid, which is the index of its word in the list
        metrics : QFontMetrics
            The measurements of the font the grid is written with
        cell_width : int
            The room the whole cell has, the word is written whole when it is zero

        Returns
        -------
            The string ready to be displayed
        """
        a = self.COLUMN_LINE_PARAGRAPH_SIZE
        column_index = str(self.input_set_column[cell_index % a])
        line_index = str(self.input_set_line[(cell_index // a) % a])
        paragraph_index = str(self.input_set_paragraph[cell_index // (a * a)])
        # The three keys and the hyphen are always shown, they are what is typed
        keys = column_index + paragraph_index + line_index + "-"
        word = str(word_list[cell_index])
        if metrics is not None and cell_width > 0:
            # Elided by Qt, which marks the cut so a trimmed word is never
            #  mistaken for a whole one and never spills over its column
            word = metrics.elidedText(word, Qt.ElideRight,
                                      cell_width - metrics.horizontalAdvance(keys))
        return keys + word

    def _cell_idx(self, column: int, line: int, paragraph: int):
        """
            Convert the index of a position in the grid to the index of position in the total words

        Parameters
        ----------
        column : int
            Index of column
        line : int
            Index of line
        paragraph : int
            Index of paragraph

        Returns
        -------
            The index of a list of total words of the given grid position
        """
        a = self.COLUMN_LINE_PARAGRAPH_SIZE
        return column + a*a*paragraph + a*line

    def _line_idx(self, line: int, paragraph: int):
        """
            Convert a given line and paragraph position in the grid to its row

        Parameters
        ----------
        line : int
        paragraph : int

        Returns
        -------
            The index of the row corresponding to its line and paragraph
        """
        a = self.COLUMN_LINE_PARAGRAPH_SIZE
        return line + a*paragraph

    def allocate_grid(self, row_init: int = 1, col_init: int = 1):
        """
            Allocate the grid objects in the grid accordingly to each index in the Table Selector tab

        Parameters
        ----------
        row_init : int
            Initial position of objects in the row
        col_init : int
            Initial position of objects in the column
        """
        if self.is_bip39_theme:
            # The grid does not support BIP39 theme, as the "phrase" is one word long and the total words doesn't fit
            return

        current_objects = self.current_words()
        a = self.COLUMN_LINE_PARAGRAPH_SIZE

        # Add aligned widgets to the grid and reveal them
        for paragraph in range(self.displayed_paragraphs(len(current_objects))):
            for line in range(a):
                line_widget = self.line_objects[self._line_idx(line, paragraph)]
                paragraph_widget = self.paragraph_objects[self._line_idx(line, paragraph)]
                self.grid_frame_selector.addWidget(line_widget,
                                                   self._line_idx(line, paragraph) + row_init, a + 2*col_init)
                self.grid_frame_selector.addWidget(paragraph_widget, self._line_idx(line, paragraph) + row_init, 0)

                line_widget.setAlignment(Qt.AlignTop)
                line_widget.show()
                paragraph_widget.setAlignment(Qt.AlignTop)
                paragraph_widget.show()

                for column in range(a):
                    self.grid_frame_selector.addWidget(self.column_objects[column],
                                                       0, col_init + 1 + column)
                    self.column_objects[column].setAlignment(Qt.AlignTop)
                    self.column_objects[column].show()

                    if len(current_objects) > self._cell_idx(column, line, paragraph):
                        word_widget = current_objects[self._cell_idx(column, line, paragraph)]
                        self.grid_frame_selector.addWidget(word_widget,
                                                           self._line_idx(line, paragraph) + 1, col_init + 1 + column)
                        word_widget.setAlignment(Qt.AlignLeft)
                        word_widget.show()

    def keyReleaseEvent(self, event: 'QKeyEvent'):
        """
            Select words and commands in the Table Selector tab

        Parameters
        ----------
        event : 'QKeyEvent'
            It is the key pressed
        """
        redo_set_keys = [Qt.Key_Escape, Qt.Key_Delete]
        if self.is_bip39_theme:
            # The grid does not support BIP39, so there is nothing on screen to select from
            return
        if event.key() == Qt.Key_Backspace:
            self.go_back()

        elif event.key() == Qt.Key_Left:
            self.step_word(-1)

        elif event.key() == Qt.Key_Right:
            self.step_word(1)

        elif event.text() in self.input_set_caseless and self.current_state != self.states[-1]:

            self.current_state = self.states[self.states.index(self.current_state) + 1]
            self.selected_indexes[self.current_state] = \
                self.permutation_map[self.current_state].index(event.text()) \
                % self.COLUMN_LINE_PARAGRAPH_SIZE

            char_index = self.permutation_map[self.current_state].index(event.text())
            self.delineate_cells(char_index)
            self.update_action_buttons()

        elif (event.key() in redo_set_keys) and self.current_state != self.states[0]:
            self.current_state = self.states[0]
            char_index = 0
            self.set_validation_colored_msg()
            self.delineate_cells(char_index)
            self.update_action_buttons()

        elif (event.key() == Qt.Key_Enter or event.key() == Qt.Key_Return or event.key() == Qt.Key_Space) and \
                self.current_state == self.states[-1]:
            if self.check_color == "#FFFF99":
                self.valid_phrase = False
            self.pick_word()

    def changed_show_highlight(self):
        """ Show or hide the background of the selected words in the Table Selector tab"""
        if self.highlight_checkbox.isChecked():
            char_index = self.selected_indexes[self.current_state]
            self.delineate_cells(char_index)
        else:
            [[each_label.setStyleSheet(self.defaultbg) for each_label in self.object_dict[each_syntactic_word]]
             for each_syntactic_word in self.object_dict.keys()]

    def reset_selection(self):
        """ Reset the variables and words which were selected so far in the Table Selector tab"""
        self.picked_passphrase = []
        self.set_word_cursor(0)
        self.current_state = self.states[0]
        self.valid_phrase = True
        self.set_validation_colored_msg()

        [self.selected_indexes.update({each_key: self.COLUMN_LINE_PARAGRAPH_SIZE})
         for each_key in self.selected_indexes.keys()]
        self.select_base_theme.setEnabled(True)

        [[each_label.setStyleSheet(self.defaultbg) for each_label in self.object_dict[each_syntactic_word]]
         for each_syntactic_word in self.object_dict.keys()]
        self.new_grid()
        self.update_action_buttons()

    def update_action_buttons(self):
        """
            Offer only the actions the phrase so far allows, in the Table Selector tab

            Generate Phrase is offered once whole phrases are picked, and Back once
             there is a word, or a part typed set of keys, left to give up
        """
        phrase_len = len(self.parent.base_dict.natural_order)
        complete = (len(self.picked_passphrase) % phrase_len == 0) and len(self.picked_passphrase) > 0
        self.output_button.setEnabled(complete)
        self.back_button.setEnabled(bool(self.picked_passphrase) or self.current_state != self.states[0])

    def output_phrases(self):
        """ Print the phrases with the selected words in the Table Selector tab"""
        phrase_len = len(self.parent.base_dict.natural_order)
        if (len(self.picked_passphrase) % phrase_len == 0) and len(self.picked_passphrase) > 0:
            output_phrases = ""
            for i in range(len(self.picked_passphrase)):
                print(self.picked_passphrase[i][0:2], end="")
            print("")
            for i in range(len(self.picked_passphrase) // phrase_len):
                phrase = " ".join(self.picked_passphrase[phrase_len * i:phrase_len * (i + 1)])
                output_phrases += phrase + " "
                print(phrase)
            QApplication.clipboard().setText(output_phrases)

    def check_word_list(self, word=None):
        """
            Check if the phrase so far follows the words list
            according to theme dictionary in the Table Selector tab

        Parameters
        ----------
        word :
            This is the word selected that is get from the grid,
            it can None as not the whole grid is filled with words
            also not all steps are evaluated
            because the filling order is not the same as natural order
        """
        # Up to where the grid stands, so a word being weighed in the middle of a
        #  phrase is judged against the words leading it rather than the whole phrase
        checklist = self.picked_passphrase[:self.word_cursor].copy()
        if word is not None:
            checklist.append(word)
        state = True
        themed_dict = self.parent.base_dict
        natural_order = themed_dict.natural_order
        filling_order = themed_dict.filling_order
        # The number of complete phrases
        phrases_shift = (len(checklist) // len(natural_order)) * len(natural_order)
        check_size = len(checklist) % len(natural_order)

        # If no word is selected and the size isn't zero
        #  or a word is selected and the size isn't one
        #  then it keep going, else it returns
        if not ((not word and check_size != 0) or (word and check_size != 1)):
            self.set_validation_colored_msg(state)
            return
        for filling_order_word in filling_order[1:check_size]:
            if not all(value in natural_order[:check_size] for value in filling_order[:check_size]):
                continue
            led_by = themed_dict[filling_order_word].led_by
            # A theme where every word stands on its own, such as "nationalities",
            #  leads its words by "NONE" and has no restriction left to check
            if led_by not in natural_order:
                continue
            led_by_index = natural_order.index(led_by) + phrases_shift
            natural_index = themed_dict.natural_index(filling_order_word) + phrases_shift
            if max(led_by_index, natural_index) >= len(checklist):
                continue
            word_mapping = themed_dict[led_by][filling_order_word].mapping
            led_by_word = checklist[led_by_index]
            # A leading word outside the mapping already makes the phrase incompatible
            state = False if checklist[natural_index] not in word_mapping.get(led_by_word, []) else state

        self.set_validation_colored_msg(state)

    def set_validation_colored_msg(self, state=True):
        """
            Warn with a yellow background when the
            word selected doesn't follow the list in the theme dictionary and if it is not yet confirmed as selected
            but keep the background red if it was selected outside the rules before in the Table Selector tab

        Parameters
        ----------
        state : bool
            This is the state of the selected word, if it follows or not the list in the theme dictionary
        """
        valid_message = "Incompatible phrase"
        if not self.valid_phrase:
            # Inadequate phrase
            # #FF4040 is Red
            self.check_color = "#FF4040"
            self.sel_valid_phrase_label.setText(valid_message)
            self.sel_valid_phrase_label.setStyleSheet("background-color: " + self.check_color)
        elif not state:
            # Adequate phrase about to become inadequate
            # #FFFF99 is Yellow
            self.check_color = "#FFFF99"
        else:
            # Adequate phrase
            # #3AC73A is Green
            valid_message = "Selected phrase\nso far is compatible"
            self.check_color = "#3AC73A"
            self.sel_valid_phrase_label.setText(valid_message)
            self.sel_valid_phrase_label.setStyleSheet("background-color: " + self.check_color)

    def delineate_cells(self, index: int):
        """
            Specify which words should be highlighted accordingly with words selected in the Table Selector tab

        Parameters
        ----------
        index : int
            This is the index of column, or paragraph or line selected which will highlighted
        """
        current_objects = self.current_words()
        a = self.COLUMN_LINE_PARAGRAPH_SIZE
        index = index % a
        begin = index
        end = len(current_objects)
        step = a

        if self.current_state == self.states[0]:
            step = 1
            begin = index
            end = len(current_objects)

        elif self.current_state == self.states[1]:
            begin = index
            end = len(current_objects)

        elif self.current_state == self.states[2]:
            column = self.selected_indexes[self.states[1]]
            begin = (a * a) * index + column
            end = (a * a) * index + column + a * (a - 1)

        elif self.current_state == self.states[3]:
            column = self.selected_indexes[self.states[1]]
            line = self.selected_indexes[self.states[2]]
            begin = column + a * index + (a * a) * line
            end = begin
            # The labels are built in cell index order, so they line up with the total words,
            #  which must be read from the theme because the labels show trimmed words
            total_words = self.parent.base_dict[self.natural_word].total_words
            if begin < min(len(current_objects), len(total_words)):
                self.check_word_list(total_words[begin])
        color = self.defaultbg if self.current_state == self.states[0] else self.check_color
        self.fill_bg_color(color, begin, end, step)

    def fill_bg_color(self, color: str, begin: int, end: int, step: int):
        """
            Highlight the background of the selected set of words in the Table Selector tab

        Parameters
        ----------
        color : str
            This is the color which the background is highlighted
        begin : int
            This is the initial index to highlight words
        end : int
            This is the end to highlight the words
        step : int
            This is the step which maps the selected serialized objects to a grid layout
        """
        current_objects = self.current_words()
        if self.highlight_checkbox.isChecked():
            [each_label.setStyleSheet("background-color: " + color)
             for each_label in current_objects[begin:end + 1:step]]
            [each_label.setStyleSheet(self.defaultbg) for each_label in current_objects
             if (each_label not in current_objects[begin:end + 1:step])]
        else:
            begin = 0
            [each_label.setStyleSheet(self.defaultbg) for each_label in current_objects
             if (each_label not in current_objects[begin:end + 1:step])]

    def pick_word(self):
        """ Store the selection when a word is selected in the Table Selector tab"""
        a = self.COLUMN_LINE_PARAGRAPH_SIZE
        # Asked first so the word being selected is checked against the theme in force
        self.current_words()
        column = self.selected_indexes[self.states[1]]
        line = self.selected_indexes[self.states[2]]
        paragraph = self.selected_indexes[self.states[3]]
        word_index = self._cell_idx(column, paragraph, line)
        words_list = self.parent.base_dict[self.natural_word].total_words
        self.current_state = self.states[0]
        char_index = 0
        if word_index < len(words_list):

            self.select_base_theme.setEnabled(False)
            if self.word_cursor < len(self.picked_passphrase):
                # Standing on a word already picked, so it is swapped for the new one
                #  and the words after it are left as they are
                self.picked_passphrase[self.word_cursor] = words_list[word_index]
            else:
                self.picked_passphrase.append(words_list[word_index])
            self.delineate_cells(char_index)
            [self.selected_indexes.update({each_key: a}) for each_key in self.selected_indexes.keys()]

            self.set_word_cursor(self.word_cursor + 1)
            # Swapping a word in the middle can leave a word after it one its new
            #  leader does not allow, so the whole phrase is weighed again
            self.valid_phrase = self.phrase_follows_theme()
            self.new_grid()
            self.set_validation_colored_msg()
        else:
            self.delineate_cells(char_index)
            [self.selected_indexes.update({each_key: a}) for each_key in self.selected_indexes.keys()]

        self.update_action_buttons()

    def go_back(self):
        """
            Step back one move in the Table Selector tab

            Backspace behaves as it does in a text box, taking back the smallest thing
             behind it: a part typed set of keys is taken back first, so a mistyped key
             costs one keystroke, and only when nothing is being typed does it give up
             the word picked before it
        """
        if self.is_bip39_theme:
            return
        if self.current_state != self.states[0]:
            self.cancel_selection()
            return
        self.undo_last_word()

    def cancel_selection(self):
        """ Take back the keys typed so far, leaving the words already picked alone"""
        a = self.COLUMN_LINE_PARAGRAPH_SIZE
        self.current_state = self.states[0]
        [self.selected_indexes.update({each_key: a}) for each_key in self.selected_indexes.keys()]
        self.set_validation_colored_msg()
        self.delineate_cells(0)
        self.update_action_buttons()

    def undo_last_word(self) -> bool:
        """
            Give up the word picked last and put the grid back on the word it filled

        Returns
        -------
        bool
            Whether there was a word to give up
        """
        a = self.COLUMN_LINE_PARAGRAPH_SIZE
        if not self.picked_passphrase:
            return False
        self.picked_passphrase.pop()
        # Read from how many words are held rather than stepped backwards, so the grid
        #  cannot be left out of step with the phrase however it was arrived at
        self.set_word_cursor(len(self.picked_passphrase))
        self.current_state = self.states[0]
        [self.selected_indexes.update({each_key: a}) for each_key in self.selected_indexes.keys()]
        if not self.picked_passphrase:
            # Nothing is held any more, so the theme is free to be changed again
            self.select_base_theme.setEnabled(True)
        # The phrase was perhaps marked incompatible by the very word being given up,
        #  so the warning is worked out again from the words which are left
        self.valid_phrase = self.phrase_follows_theme()
        self.new_grid()
        self.check_word_list()
        self.update_action_buttons()
        return True

    def change_highlight_var(self):
        """ Switch the variable of the highlight checkbox """
        self.highlight_checkbox.setEnabled(not self.highlight_checkbox.isChecked())
        self.changed_show_highlight()


class QtFormosa(QMainWindow):
    DEFAULT_THEME = "BIP39"

    def __init__(self, parent=None):
        super(QtFormosa, self).__init__(parent)
        self.setWindowTitle("Formosa Application")
        # Opening at a fixed size puts the lower buttons under the edge of a smaller
        #  screen, so the preferred size is kept within the room the screen gives
        preferred_width, preferred_height = 1024, 600
        available = QApplication.primaryScreen().availableGeometry() \
            if QApplication.primaryScreen() is not None else None
        if available is not None:
            preferred_width = min(preferred_width, available.width())
            preferred_height = min(preferred_height, available.height())
        self.resize(preferred_width, preferred_height)

        self.themes = self.sorted_themes()
        self.base_theme = self.themes[0]
        # Reading and parsing a theme file costs milliseconds and the grid asks for it
        #  on every keystroke, so each theme is built once and kept
        self._mnemonic_cache = {}

        self.table_widget = FeaturesTabs(self)
        self.setCentralWidget(self.table_widget)

        # Held on the window: a shortcut is offered before the key reaches whichever
        #  widget has the focus, which is what lets these come round again at the ends
        #  where the plain tab widget would simply stop at the first and the last
        self.previous_tab_shortcut = QShortcut(QKeySequence("Ctrl+PgUp"), self)
        self.previous_tab_shortcut.activated.connect(self.table_widget.show_previous_tab)
        self.next_tab_shortcut = QShortcut(QKeySequence("Ctrl+PgDown"), self)
        self.next_tab_shortcut.activated.connect(self.table_widget.show_next_tab)

    def sorted_themes(self) -> tuple[str]:
        """
            Find all themes in json files
            All .json files in the themes directory are considered themes,
            force the default theme as the first element

        Returns
        -------
        tuple[str]
            Return a tuple of themes, the first element is the default theme and rest is sorted
        """
        themes = list(mnemonic.Mnemonic.find_themes())
        if not themes:
            raise mnemonic.ThemeNotFound("No theme .json file was found in %s"
                                         % mnemonic.Mnemonic.themes_directory())
        if self.DEFAULT_THEME in themes:
            themes.remove(self.DEFAULT_THEME)
            themes.insert(0, self.DEFAULT_THEME)
        return tuple(themes)

    def set_base_theme(self, theme_chosen: str):
        """
            Set the current base theme

        Parameters
        ----------
        theme_chosen : str
            The theme to be set, must e one of found themes in .json files
        """
        self.base_theme = theme_chosen

    @property
    def base_mnemonic(self) -> mnemonic.Mnemonic:
        """ Return the base Mnemonic object"""
        if self.base_theme not in self._mnemonic_cache:
            self._mnemonic_cache[self.base_theme] = mnemonic.Mnemonic(self.base_theme)
        return self._mnemonic_cache[self.base_theme]

    @property
    def base_dict(self) -> mnemonic.ThemeDict:
        """ Return the base theme dictionary"""
        return self.base_mnemonic.words_dictionary


class FeaturesTabs(QWidget):
    def __init__(self, parent: QtFormosa):
        super(QWidget, self).__init__(parent)
        self.parent = parent
        layout = QVBoxLayout(self)

        self.tab_control = QTabWidget()
        self.mnemonic_generator = MnemonicGeneratorTab(parent)
        self.address_converter = QWidget(self)
        self.theme_converter = ThemeConverterTab(parent)
        self.table_selector = TableSelectorTab(parent)
        self.swapper = QWidget(self)

        self.tab00 = "Password Generator"
        self.tab01 = "Theme Converter"
        self.tab02 = "Table Selector"
        self.tab03 = "Word Swapper"

        self.tab_control.addTab(self.mnemonic_generator, self.tab00)
        self.tab_control.addTab(self.theme_converter, self.tab01)
        self.tab_control.addTab(self.table_selector, self.tab02)

        # Every tab is set up as the window is built. Only the first one used to be,
        #  so the others opened blank, with unlabelled buttons and an empty theme list,
        #  and filled themselves in at whatever moment they were first clicked
        for each_index in range(self.tab_control.count()):
            self.tab_control.widget(each_index).init_configuration()
        # Answering the change of tab rather than the click on it, so a tab reached by
        #  the keyboard is brought up to date the same as one reached by the tab bar
        self.tab_control.currentChanged.connect(self.tab_shown)

        layout.addWidget(self.tab_control)
        self.setLayout(layout)

    def tab_clicked(self, tab_index):
        """
            Show a given tab

        Parameters
        ----------
        tab_index : int
            The tab to show
        """
        self.tab_control.setCurrentIndex(tab_index)
        # Changing the index tells the tab itself, but says nothing when the tab asked
        #  for is the one already showing, so it is told here as well
        self.tab_shown(self.tab_control.currentIndex())

    def tab_shown(self, tab_index):
        """
            Bring a tab up to date as it is shown, however it was reached

        Parameters
        ----------
        tab_index : int
            The tab being shown
        """
        tab = self.tab_control.widget(tab_index)
        if tab is None:
            return
        tab.init_configuration()
        # Read from the window, which every tab shares, rather than from the tab being
        #  left, which holds no more than its own copy of it
        tab.set_base_theme(self.parent.base_theme)

    def show_next_tab(self):
        """ Show the tab after this one, the first one following the last"""
        self.step_tab(1)

    def show_previous_tab(self):
        """ Show the tab before this one, the last one preceding the first"""
        self.step_tab(-1)

    def step_tab(self, step: int):
        """
            Move a given number of tabs along, coming round again at either end

        Parameters
        ----------
        step : int
            How many tabs to move, negative to move backwards
        """
        tab_amount = self.tab_control.count()
        if not tab_amount:
            return
        self.tab_clicked((self.tab_control.currentIndex() + step) % tab_amount)


def main() -> int:
    """ Start the Formosa application"""
    # Installed before any widget exists so no error can abort the process unreported
    sys.excepthook = excepthook
    app = QApplication(sys.argv)
    window = QtFormosa()
    window.show()
    return app.exec_()


if __name__ == "__main__":
    sys.exit(main())
