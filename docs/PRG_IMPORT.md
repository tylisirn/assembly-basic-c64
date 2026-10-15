# Stock C64 BASIC PRG import

`LOAD "PROGRAM",8` accepts both the native `.AB` source container and stock C64
BASIC V2 PRG files. Detection uses the bytes in the file, not its extension.
Reads let Commodore DOS determine PRG/SEQ file type; SAVE continues to create
native sequential `.AB` containers. Imported source is compiled on the cartridge.
Empty programs replace the current program and clear the editor listing.

The importer accepts the standard little-endian load address `$0801`, followed
by linked BASIC line records and the final zero link. It verifies physical next
links, increasing line numbers in 0–63999, line terminators, supported stock token
codes, file status and the final end marker. This follows the original
[BASIC line-link format](https://github.com/mist64/c64rom/blob/master/basic/code1.s)
and [BASIC V2 token spellings](https://github.com/mist64/c64rom/blob/master/basic/token2.s).
The load address identifies the format; bytes are streamed through the source
converter rather than written over the cartridge's live workspace.

Stock keywords, operators and the two-token `GO TO` spelling are converted to
native source before tokenization. Embedded strings and REM/DATA fields retain
PETSCII bytes, including control glyphs and bytes that resemble keyword tokens.
Stock variables retain only their first two significant letters/digits, including
spaces ignored by stock BASIC: `LONGNAME` and `LOONEY` both become `LO`.
[Stock name significance](https://www.devili.iki.fi/Computers/Commodore/C64/Programmers_Reference/Chapter_1/page_007.html)
therefore survives conversion into the native language's full-name namespace.

Stock signed integer names require a separate namespace because native `%`
means unsigned. For example, stock `A%` becomes the signed native name `PRGINTA`,
while stock `A` and `A$` remain distinct. The prefix cannot collide with a stock
name normalized to at most two letters/digits. Numeric execution otherwise uses
the cartridge's existing wrapping 16-bit integer contract. This does not add
floating-point execution: fractional/exponent source and unsupported expressions
remain listable, editable source with the existing compiler/runtime diagnostics.

LOAD constructs a second source graph and publishes it only after validation.
Malformed or truncated files, invalid links/numbers/tokens, allocation failure,
or a converted line exceeding 255 text bytes roll back to the old program.
Native token lines also retain their 255-byte limit. Appended machine code or
resource bytes after the BASIC end marker are rejected rather than discarded;
relocated or extended-dialect programs are outside this importer. Imported
machine addresses and SYS/USR calls are not relocated.

After loading, use BASIC to inspect/edit the listing, RUN to execute supported
source, and SAVE to retain it in `.AB` format. Stock PRG export remains planned.
