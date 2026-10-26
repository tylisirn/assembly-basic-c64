# Cartridge screen editor

Enter `BASIC` in direct mode to open the editor. The upper 20 rows show the
program, row 20 shows the writing mode and shortcuts, and the bottom four rows
hold the current draft and direct-command output. `QUIT`, F7, and `RUN` clear
the screen and close the editor; RUN then executes the program. The selected
BASIC line number and first displayed line number survive closing and reopening.

| Key | Listing focus | Edit focus |
| --- | --- | --- |
| Cursor up/left | Previous BASIC line | Move text cursor |
| Cursor down/right | Next BASIC line | Move text cursor within the pane |
| Return | Copy selected source into the pane, cursor at its end | Submit current draft |
| `←` (PETSCII 95), left of 1 | Focus the edit pane | Discard the draft and focus the listing |
| Shift-DEL (INS) | — | Toggle INSERT / OVERWRITE |
| CTRL+2 | — | Toggle literal control entry |
| DEL | — | Delete the preceding character |
| HOME | — | Move to the start of the draft |
| F5 | Open binary/sprite editor | Open binary/sprite editor, retaining the draft |
| F3 | Go to a line number | Go to a line number, retaining the draft |
| F1 | Show help; any key returns | Show help; any key returns |
| F7 | Clear screen and quit | Clear screen and quit |

Wrapped source continues after the line-number column. Moving the selection
past the listing frame advances or backs up the viewport by five BASIC lines,
clamped at the program's ends. Only the selected line number is highlighted,
even while editing; source text and continuation rows remain in normal video.
Switching focus retains the line-number highlight.

Numbered submissions select the affected line and bring it into view; deletion selects the next surviving line,
or the preceding line when deleting the last one. The selected line and viewport track program changes, including NEW, LOAD and CLEAN.

F3 opens a `GO LINE` prompt in the status bar. Each digit immediately selects
the requested BASIC line, or the next higher line; requests beyond the program
select its last line. Enter or any non-digit closes the prompt without submitting
the edit pane. This includes F1/F7 while the prompt is open. The draft, text
cursor, focus and writing settings survive, including during keyboard INPUT.
Numbers are bounded to 0–63999; excess digits or overflow are ignored.

When a numbered submission or F3 jump selects an off-screen destination, the
viewport includes up to three preceding BASIC lines. Wrapped context can occupy
more than three screen rows; fewer predecessors are used if needed to keep the
destination visible. Near the program start, all available predecessors are
shown. An already visible destination does not scroll or redraw source text.

Numbered drafts add, replace, or delete program lines through the existing
on-machine tokenizer/compiler. Successful numbered submissions clear the edit
pane. A line number alone deletes that line. Failed submissions retain the draft,
show the error in the status row, and position the text cursor at the start of
the command that failed, accounting for any output scrolling. Recoverable
compilation errors still retain malformed source in the program, matching
ordinary direct entry. Correct the retained draft and submit it again.

Commands such as `PRINT 123`, LIST, SAVE, LOAD, and INPUT use the edit pane.
LIST polls RUN/STOP and pending breaks between source lines. LOAD also imports
[stock BASIC PRG files](PRG_IMPORT.md).
Output, wrapping, screen-clear controls, and scrolling stay within its four rows;
there is no READY prompt there. Keyboard INPUT uses the bounded pane editor;
file/device input and output continue through their original KERNAL vectors.
Cursor keys can revisit earlier commands or output still visible in the pane.
Wrapped rows remain one logical line; Return submits the logical line containing
the cursor. Editing an earlier line retains the surrounding screen contents.
Moving the cursor down from the last pane row does not scroll.

INSERT pushes subsequent characters right and uses the normal reverse cursor.
OVERWRITE replaces the character at the cursor and displays it in reverse black.
CTRL+2 toggles LITERAL independently of INSERT/OVERWRITE. The status bar shows
both settings. LITERAL enters PETSCII control bytes as visible quoted-style
glyphs and shows a cyan reverse L cursor. In LITERAL, cursor and HOME control codes become literal
characters. Return, DEL, INS, CTRL+2, F1, F7, and the `←` (PETSCII 95) focus key
retain their editor functions. Other PETSCII control bytes are ignored while
literal entry is off, including inside quotes. Literal entry follows the current insert/overwrite policy.

The visible draft can hold 160 PETSCII bytes, including its line number. A stored
line whose canonical spelling exceeds that capacity remains listable and is
rejected for copying with an explicit message, rather than being truncated and
accidentally replacing the original source. Output above a draft is scrolled
away as needed when typing wraps; moving the cursor alone never scrolls.

F5 opens the [binary/sprite editor](BINARY_EDITOR.md). Returning preserves pane
contents, focus and bookmarks, including during keyboard INPUT.
