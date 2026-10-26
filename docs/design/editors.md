# Editor design

The [source editor](../SCREEN_EDITOR.md) and [binary/sprite editor](../BINARY_EDITOR.md) guides define user interaction. This document defines shared state and persistence constraints; implementation workspaces and ROM checks are recorded in [editor implementation](../implementation/EDITORS.md).

## Source editor

The screen has 20 listing rows, one status row and four draft/output rows. Selected-line and viewport bookmarks are numeric line numbers, resolved against the current graph after edits, NEW, LOAD or CLEAN. No bookmark retains a freed source pointer. Wrapped source aligns after its line-number column, and off-screen jumps include preceding source context when it fits.

Only line-number cells are highlighted. A cached row map supports selection changes without detokenizing source. Scrolling shifts overlapping character rows and formats exposed rows, including clipped continuations; listing color RAM stays in place. Source generations invalidate cached anchors. Refresh compares screen codes, and commands without source mutations skip listing refresh. Help saves/restores characters instead of regenerating source.

The four-row pane is both a draft editor and bounded direct-output/keyboard-INPUT surface. Wrapped rows form logical lines, and earlier visible commands can be revisited. A failed submission retains its draft and returns the cursor to the logical command start. Successful numbered submissions update selection and clear the draft. A canonical line longer than 160 bytes is rejected for copying, never truncated into a replacement.

Insert/overwrite policy and literal-control entry are independent state. F3 line navigation, help and F5 binary editing preserve the draft, cursor, focus and INPUT state. Runtime control frames and the command backup must remain intact. Closing restores KERNAL input/output hooks; file/device channels retain KERNAL routing.

## Reservations and blobs

The binary editor has eight logical reservation slots and sixteen blob slots. BASIC RESERVE declarations have locked bounds; manual reservations have byte-granular bounds inside an allocator span. All containing pages are protected before publication. Existing live allocations and firmware ranges cannot be claimed.

A blob has reservation ownership, start, size and type BIN/SPR/ASM. Bounds must remain inside its reservation and must not overlap another blob. SPR is exactly 64 bytes: 63 pixel bytes and an independently editable unused byte. ASM is a label displayed through the hex editor; no assembler is implemented.

Bounds/type/palette changes reinterpret existing bytes. They do not initialize, copy or relocate content. Initialization requires an explicit action. Deleting/moving metadata retains page exclusions until NEW; surviving logical reservations can reuse protected pages. SAVE/NEW/LOAD consolidates page claims to surviving reservations. CLEAN and collection preserve metadata and protected bytes.

## Rendering and hardware state

Binary scenes compose one row at a time and compare against character/color RAM. Navigation and prompts write only changed cells. Hex views show eight bounded bytes per row and never read a word beyond the blob's final byte. Sprite pixels use character cells, with one cell per hires pixel or two per multicolor pixel.

Hardware sprites supply 1X/2X previews and two complementary hatched hires cursor sprites. The sprite's background fills the preview panel. Each sprite retains its own background, sprite and two common colors plus its hires/multicolor mode. Painting updates the corresponding data byte and previews. Toggling mode does not transform pixel bytes. VIC registers and sprite pointers are restored on exit.

## Persistence

Raw BIN exchange is a sequential stream of exactly the selected reservation/blob bytes, with no load address, length prefix or metadata. A short load leaves the remainder unchanged; a long load stops at the extent boundary.

The compiled BASIC statements BLOAD and BSAVE use the same raw byte format, with an explicit drive and memory address. BLOAD accepts an optional byte limit; BSAVE requires a count. Their filenames are used exactly as supplied, while editor prompts add `.BIN` when there is no extension.

Native program files save logical reservations, ownership, blob bounds/types, palettes and exact blob bytes. Unassigned bytes inside reservations are excluded. Reservation descriptors precede source compilation so allocations cannot consume incoming binary pages. LOAD validates source/metadata/data before a second streaming pass restores bytes, avoiding a blob-sized staging buffer. Validation failure preserves old state; second-pass device failure can leave already restored bytes changed. See [source format](source_format.md) for binary layouts and checks.
