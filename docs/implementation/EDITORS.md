# Editor implementation and validation

User controls are documented in the [source editor guide](../SCREEN_EDITOR.md) and
[binary/sprite editor guide](../BINARY_EDITOR.md). [Editor design](../design/editors.md)
defines state ownership and persistence.

## Source editor

The UI lives in Magic Desk bank 3 and shares bank 0's canonical LIST formatter.
The common-RAM CHROUT hook preserves registers, flags and user zero-page
pointers. Hooks are restored on exit. Editor text occupies `$0A60–$0AFF`, and
persistent state occupies `$03CC–$03FF`, outside the program arena and compiler,
collector, and runtime scratch. `$FB–$FE` are borrowed as screen pointers while
editing. The row map and scroll work occupy `$0F80–$0FDF`, the unused upper
half of the existing 32-entry expression-stack page. Help saves the 800 listing
characters in inactive TOKENS, LEX_BUFFER and BRIDGE buffers plus `$0FE0–$0FFF`;
it restores those characters without reformatting the program or touching color
RAM. The draft, INPUT command backup and frozen control stack remain intact.

Build and run the full suite with `python3 tools/build.py` and
`python3 tools/test.py`. Optional validation with a user-supplied stock KERNAL
and character ROM also produces a rendered preview:

```sh
python3 tools/check_editor_rom.py --rom-dir /path/to/VICE/C64 \
    --preview build/editor-preview.png
```

This runs actual 901227-03 RESTOR/CINT/GETIN/CHRIN/CHROUT instructions in py65,
with injected keyboard bytes and synthetic raster registers. It is a software
integration check, not cycle-accurate VIC/IEC or physical-machine acceptance.

The [scroll measurements](editor-scroll-measurements.json) record a specific
software benchmark and its baseline, with the ROM/commit provenance in that
record. They are instruction/write measurements rather than hardware timings.

## Binary/sprite editor

Scenes are composed one row at a time and compared with screen and color RAM;
only changed cells are written, without clearing the screen between updates.
Visible hex navigation updates the old/new byte cells and the value footer.
Sprite painting updates just its enlarged pixel and the preview data byte; cursor
motion and palette selection leave the rest of the screen intact. Prompts also
update only changed cells and restore their covered rows when dismissed.

ROM bank 4 contains the UI and bank 5 the metadata/reservation/file services.
The existing bank-call gateway restores bank, mapping and interrupt state.
Persistent metadata occupies `$0200–$0258` and `$02A7–$02FF`, leaving KERNAL file
tables and keyboard state intact. These ranges are firmware-owned. Transient
buffers use existing inactive workspace, preserving the BASIC draft and frozen
control stack. VIC registers and sprite pointers are restored on exit.

The sprite organization follows the original Commodore documentation:
[24×21 sprite geometry](https://www.devili.iki.fi/Computers/Commodore/C64/Programmers_Reference/Chapter_3/page_131.html)
and [63 pixel bytes, multicolor pairs and pointers](https://www.devili.iki.fi/Computers/Commodore/C64/Programmers_Reference/Chapter_3/page_133.html).

Run the regression suite with `python3 tools/test.py`. For supplied stock ROMs:

```sh
python3 tools/check_binary_editor_rom.py --rom-dir /path/to/VICE/C64 \
    --previews build/binary-previews
```

This executes genuine KERNAL keyboard/display instructions with injected device
bytes and renders character/sprite state for review. It does not replace
cycle-accurate VIC/IEC or physical-machine validation.
