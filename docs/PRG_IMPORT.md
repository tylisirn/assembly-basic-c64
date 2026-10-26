# Stock C64 BASIC PRG import

`LOAD "PROGRAM",8` accepts both the native `.AB` source container and stock C64
BASIC V2 PRG files. Detection uses the bytes in the file, not its extension.
Reads let Commodore DOS determine PRG/SEQ file type; SAVE continues to create
native sequential `.AB` containers. Imported source is compiled on the cartridge.
Empty programs replace the current program and clear the editor listing.

The PRG must use the standard BASIC load address `$0801` and valid linked
BASIC V2 lines. Appended machine-code payloads, relocated programs and extended
dialects are unsupported. [Format and validation details](design/source_format.md#stock-basic-prg-import)
are documented separately.

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

LOAD validates and compiles the incoming source before replacing the program.
Malformed or truncated files, invalid links/numbers/tokens, allocation failure,
or a converted line exceeding 255 text bytes roll back to the old program.
Native token lines also retain their 255-byte limit. Appended machine code or
resource bytes after the BASIC end marker are rejected rather than discarded;
relocated or extended-dialect programs are outside this importer. Imported
machine addresses and SYS/USR calls are not relocated.

After loading, use BASIC to inspect/edit the listing, RUN to execute supported
source, and SAVE to retain it in `.AB` format. Stock PRG export is unavailable. See the [language reference](LANGUAGE_REFERENCE.md)
for execution differences and supported keywords.
