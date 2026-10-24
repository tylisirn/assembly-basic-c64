# Binary and sprite editor

Press F5 in the BASIC editor, or enter the direct command `SPRDEF`. The editor
starts at the reservation list. F7 exits; `←` (PETSCII 95) goes back one level.
The border is the standard light blue and the character-mode background is dark
blue. Returning with F5 preserves the BASIC draft, output pane, focus and listing
bookmarks. F5 is also available while collecting keyboard INPUT.

## Reservations and blobs

Cursor up/down selects a reservation. Return enters its blob list; Return on a
blob opens its editor. SPR opens the sprite view; BIN and ASM open the hex view.
ASM is a type label reserved for a future assembler.

| Key | Reservation selection | Blob selection |
| --- | --- | --- |
| N | Enter start address and byte count | Choose S=SPR, B=BIN or A=ASM; enter size for BIN/ASM |
| R | Redefine start and size for a manual reservation | Redefine the selected blob's start and size |
| DEL | Delete; confirm Y/N if it contains blobs | Remove the blob metadata |
| C | — | Change blob type |
| S / L | Save/load the reservation's bytes | Save/load the blob's bytes |
| Return | Select its blobs | Open the appropriate editor |
| `←` (PETSCII 95) | Exit | Return to reservations |

Numeric prompts accept decimal or `$`-prefixed hexadecimal. `←` cancels a prompt;
F7 exits. New blobs use the first available space in their reservation. A sprite
always occupies 64 bytes. Types, bounds and colors change how bytes are interpreted;
these operations do not initialize, relocate or copy the data. Resizing rejects
bounds that exclude existing blobs. Blob bounds must fit their reservation and
must not overlap another blob.

`RESERVE` declarations create entries marked `(BASIC)`. Their bounds are read
only in this editor; blobs can be created, moved and edited inside them. Manual
reservations accept byte-granular bounds within the existing user arena. Their
containing pages are excluded from source, code, heap allocation and collection;
firmware, I/O and runtime memory cannot be reserved. Occupied allocator pages are
rejected, preserving the current program.

There are eight logical reservation slots and sixteen blob slots. The existing
allocator supports eight page ranges. Deleted or moved ranges remain protected
until NEW, so removing metadata does not overwrite bytes with allocator headers.
Their protected pages can be reused by other editor reservations. NEW clears all
metadata and releases the page exclusions. SAVE/NEW/LOAD also consolidates page
claims to the surviving logical reservations.

## Hex view

The view shows eight bytes per row: an address, hex values, and PETSCII text.
Controls are displayed as periods. Cursor keys stay within the blob and scroll
the viewport as needed. Type one or two hex digits to change the selected byte;
space, comma or Return advances to the next byte. Typing alone does not advance.

The bottom line shows the selected address, byte hex/decimal value, and the
little-endian word formed with the next byte. At the final byte the high byte is
zero; the editor never reads outside the blob. I fills the complete blob with a
prompted byte value. T changes its metadata type while keeping the hex view open.
S/L exchange bytes, and `←` returns to blob selection.

## Sprite view

The enlarged 24×21 view uses one character per hires pixel, or two characters
per multicolor pixel. Top/bottom column rulers and left row rulers surround it.
The 1X and 2X previews use hardware sprites. Two complementary hires hardware
sprites create the black/white hatched cursor outline, widened for multicolor.
The preview's transparent pixels show the sprite's own background color.

| Key | Action |
| --- | --- |
| Cursor keys | Move within the 24×21 or 12×21 logical pixels |
| 1 | Background: value 0 / multicolor bits 00 |
| 2 | Sprite color: hires 1 / multicolor bits 10 |
| 3 | Multicolor common color 1: bits 01 |
| 4 | Multicolor common color 2: bits 11 |
| C | Choose a color definition, then select 0–F in the palette |
| T | Toggle hires/multicolor interpretation without changing bytes |
| I | Initialize the 63 pixel bytes to a chosen color number |
| B | Set the unused 64th byte; its value is shown in the legend |
| S / L | Save/load all 64 bytes |
| `←` | Return to blob selection |

Hires hides the common-color commands. In the palette, left/right moves the
selection, hex keys select a color directly, Return commits, and `←` cancels.
Each sprite retains its own four palette definitions and multicolor flag.
Initializing sprite pixels preserves byte 64; the B command edits it explicitly.

## Files and program persistence

S/L prompt for a filename of up to 51 characters. `.BIN` is added when no extension is supplied. Disk
operations use device 8 and a sequential byte stream. There is no load address,
length prefix or metadata in a `.BIN`. Save writes the exact selected extent.
Load stops at the end of the file or the selected extent; short files leave the
remaining memory unchanged and long files never write past the boundary.

BASIC SAVE uses source-container version 2 when binary metadata is present;
source-only files remain byte-identical version 1. Both versions can be loaded.
Version 2 saves reservations, BASIC/manual ownership, blob bounds/types, each
sprite's colors/mode, and the exact bytes in every blob. Unassigned reservation
bytes are not included. All sections participate in the file CRC.

The v2 byte layout is the eight-byte `AB64SRC`/zero magic, version/flags `2,0`,
a one-byte reservation count and five-byte reservation descriptors (start word,
size word, BASIC flag), followed by the unchanged v1 dictionary and line records.
After the `FFFF` line marker comes a one-byte blob count. Each blob has an
eight-byte descriptor (reservation index, start word, size word, type/multicolor
flags, two packed palette bytes) and its raw data. The final two bytes are the
CRC-16/CCITT-FALSE. Words are little-endian. Reservation descriptors precede
compilation so even low-arena blob pages are protected before any source allocation.

LOAD stages source and metadata and validates the complete stream before writing
blob bytes. It then reopens the validated file and restores data without needing
an additional blob-sized RAM buffer; keep the file available and unchanged until
LOAD finishes. CRC/truncation errors in validation preserve the old source,
metadata and blob bytes. An I/O failure during the second pass can leave already
restored bytes changed. As with existing staged source loads, NEW before loading
can help when the old program occupies pages required by the incoming program.
CLEAN and garbage collection preserve the metadata and protected bytes.

The host `ab64.container` codec retains metadata on its `ProgramLines` mapping,
so `dumps(*loads(data))` preserves the binary sections. `Reservation` and `Blob`
objects allow creating v2 files on the host. Text decoding exports BASIC source
only; use `.AB` or individual `.BIN` files to retain binary content.

## Implementation and validation

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
