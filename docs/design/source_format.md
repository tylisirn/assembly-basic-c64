# Source tokens and program file formats

Authoritative BASIC source is a compact, byte-counted token stream with a separate full-name dictionary. Native machine code, addresses, values and line anchors are regenerated rather than serialized. The host implementations are [tokens.py](../../host/ab64/tokens.py) and [container.py](../../host/ab64/container.py). This specification covers both supported container formats; their numbers describe file layouts, not firmware releases.

All words are unsigned little-endian fields unless stated otherwise. A line has 1–255 token bytes. Payload bytes are data, never recursively decoded; zero is not an end-of-line marker.

## Token code space

| Code | Meaning |
| --- | --- |
| `$00–$0F` | Punctuation/operators in order: `: , ; ( ) + - * / ^ = < > <= >= <>` |
| `$10` DEC8 | One value byte, canonical for decimal 16–255 |
| `$11` DEC16 | Word value, canonical for decimal 256–65535 |
| `$12` HEX16 | Word value, 0–65535; LIST preserves radix as four hex digits |
| `$13` STRING | Length byte and PETSCII bytes, without quote delimiters; empty is valid |
| `$14` REMTEXT | Length byte and raw remainder; must follow REM and end the line |
| `$15` DATA_TEXT | Length byte and unquoted DATA field; empty is valid |
| `$16` DATA_SPELLING | Length byte and original trimmed numeric DATA spelling |
| `$17` NUMTEXT | Length byte and unsupported numeric spelling retained for diagnostics/listing |
| `$18` BADTEXT | Length byte and malformed source retained for repair |
| `$19` NAME16 | Word name ID, canonical for IDs 128–65534 |
| `$1A`, `$1B` | `<<`, `>>` |
| `$1C–$1F` | Reserved; invalid |
| `$20–$6C` | Keywords in the table below |
| `$6D–$6F` | Reserved; invalid |
| `$70–$7F` | Decimal magnitude 0–15, value = code minus `$70` |
| `$80–$FF` | Name ID 0–127, ID = code minus `$80` |

Raw payload lengths are unsigned bytes. NUMTEXT, BADTEXT and DATA_SPELLING require nonzero length. STRING excludes a literal quote byte; runtime quotes can be constructed with CHR$(34). Other raw payload bytes can include NUL and token-valued bytes where their context permits. All prefixes and payload bytes count toward the line budget.

Decimal leading zeros outside DATA disappear. Signs remain separate operator tokens. Oversized/malformed numbers are retained as diagnostic forms rather than wrapped into valid literals. An accepted end-of-line unterminated string becomes a STRING whose closing quote is supplied by LIST.

DATA_TEXT is valid only inside DATA and cannot contain quotes, commas, colons or line endings. Numeric fields use optional sign plus a binary magnitude, optionally followed by DATA_SPELLING when the trimmed input differs from canonical expansion. Its sign, radix and magnitude must agree with the encoded field. Thus `DATA 001` can yield `"001"` when READ into a string without storing numeric text for ordinary arithmetic. NUMTEXT allows unsupported numeric fields to remain text-readable. A colon outside a payload ends DATA. REM must be followed by exactly one REMTEXT containing the rest of the physical line.

## Keyword assignments

Keyword spellings are exact whole-identifier matches. TAB( and SPC( include their opening parenthesis in the keyword code; other functions use a separate `$03`. Floating-point functions and π have reserved spellings/codes but are unsupported when evaluated. BASIC, SPRDEF and QUIT are command/editor entry words, outside this stored-token vocabulary.

| Code | Keyword | Code | Keyword |
| --- | --- | --- | --- |
| `$20` | `END` | `$46` | `FN` |
| `$21` | `FOR` | `$47` | `SPC(` |
| `$22` | `NEXT` | `$48` | `THEN` |
| `$23` | `DATA` | `$49` | `NOT` |
| `$24` | `INPUT#` | `$4A` | `STEP` |
| `$25` | `INPUT` | `$4B` | `AND` |
| `$26` | `DIM` | `$4C` | `OR` |
| `$27` | `READ` | `$4D` | `SGN` |
| `$28` | `LET` | `$4E` | `INT` |
| `$29` | `GOTO` | `$4F` | `ABS` |
| `$2A` | `RUN` | `$50` | `USR` |
| `$2B` | `IF` | `$51` | `FRE` |
| `$2C` | `RESTORE` | `$52` | `POS` |
| `$2D` | `GOSUB` | `$53` | `SQR` |
| `$2E` | `RETURN` | `$54` | `RND` |
| `$2F` | `REM` | `$55` | `LOG` |
| `$30` | `STOP` | `$56` | `EXP` |
| `$31` | `ON` | `$57` | `COS` |
| `$32` | `WAIT` | `$58` | `SIN` |
| `$33` | `LOAD` | `$59` | `TAN` |
| `$34` | `SAVE` | `$5A` | `ATN` |
| `$35` | `VERIFY` | `$5B` | `PEEK` |
| `$36` | `DEF` | `$5C` | `LEN` |
| `$37` | `POKE` | `$5D` | `STR$` |
| `$38` | `PRINT#` | `$5E` | `VAL` |
| `$39` | `PRINT` | `$5F` | `ASC` |
| `$3A` | `CONT` | `$60` | `CHR$` |
| `$3B` | `LIST` | `$61` | `LEFT$` |
| `$3C` | `CLR` | `$62` | `RIGHT$` |
| `$3D` | `CMD` | `$63` | `MID$` |
| `$3E` | `SYS` | `$64` | `ST` |
| `$3F` | `OPEN` | `$65` | `TI` |
| `$40` | `CLOSE` | `$66` | `TI$` |
| `$41` | `GET` | `$67` | `π` |
| `$42` | `GET#` | `$68` | `ELSE` |
| `$43` | `NEW` | `$69` | `CLEAN` |
| `$44` | `TAB(` | `$6A` | `RESERVE` |
| `$45` | `TO` | `$6B` | `BLOAD` |
|  |  | `$6C` | `BSAVE` |

## Name dictionary

Names are unique uppercase spellings of 1–255 bytes: letter, letters/digits, optional final `%` or `$`. Reject exact keywords and special variables, duplicates and ID `$FFFF`. The dictionary count is a word, with IDs 0–65534. Scalars, arrays and functions resolve their separate bindings from spelling IDs; A and A() can share a spelling ID while having different storage.

SAVE exports only referenced names, remapped densely in ascending original-ID order. An export ID cannot exceed its original ID, so remapping cannot widen a valid line beyond 255 bytes. LOAD constructs a fresh dictionary before compiling source; no pointers arrive from the file.

## Native container common structure

The magic is eight bytes `41 42 36 34 53 52 43 00`, or ASCII `AB64SRC` followed by zero. It is followed by a format byte (1 or 2) and flags byte (zero). Neither format has a C64 load-address prefix.

| Shared source section | Encoding |
| --- | --- |
| Name count | Word N |
| Dictionary | N records: length byte, then uppercase name bytes |
| Lines | Strictly increasing line number word 0–63999, token-length byte T, then exactly T token bytes |
| End of source | Word `$FFFF`, without length or tokens |

## Format 1: source only

The complete file is magic, format/flags `1,0`, shared source section, and CRC word. The empty file has zero names, no line records and the end marker. EOF must immediately follow the CRC.

## Format 2: source with binary metadata

The complete file is magic, format/flags `2,0`, reservation section, shared source section, blob section, and CRC word. Descriptors come before compilation so incoming binary pages are protected before source allocation.

| Reservation section | Encoding |
| --- | --- |
| Count | Byte, 0–8 |
| Each descriptor | Start word, size word, BASIC-owner flag byte (0 or 1) |

Ranges must be nonempty, nonoverlapping, entirely inside one user-arena span, and within the 16-bit address space. BASIC-owned reservations require page-aligned start and size. Manual reservations may be byte granular; their containing pages are allocator exclusions.

| Blob section | Encoding |
| --- | --- |
| Count | Byte, 0–16 |
| Each descriptor | Reservation index byte, start word, size word, type/mode byte, two packed palette bytes |
| Each payload | Exactly size raw bytes immediately after its descriptor |

Type/mode low bits are 0=BIN, 1=SPR, 2=ASM, with bit 7 marking multicolor. Other bits are invalid. Multicolor is valid only for SPR; a sprite has exactly 64 bytes. Each blob must fit its reservation and not overlap another blob. In the first palette byte, the low nibble is background and high nibble is sprite color; the second stores common colors 1 and 2 in low/high nibbles. Each color is 0–15. Unassigned reservation bytes are excluded from the file.

## CRC and validation

Both formats finish with CRC-16/CCITT-FALSE over every preceding file byte, including the source end marker and any binary sections. Parameters: polynomial `$1021`, initial `$FFFF`, no reflection, final XOR zero; CRC is low byte first. Reject trailing bytes.

Validate magic/flags/version, dictionary identity, sorted line records, bounded payload lengths, minimal decimal/name encodings, ID references, raw-token context, DATA spelling equality, binary metadata bounds and CRC. Structural validity is separate from language syntax: a safe source stream may compile to a reached syntax/unsupported-feature trap.

The host validator implements the complete canonical token checks. The target loader does not yet enforce every DATA_SPELLING equality/context check; see [implementation gaps](../implementation/STATUS.md). Target VERIFY compares canonical serialization of the current program with file bytes rather than canonicalizing an arbitrary file's dictionary. Host verification canonicalizes both inputs.

## Staged loading and transport

Source transport uses bounded sequential KERNAL channels, never an unrestricted KERNAL LOAD into the arena. LOAD builds and compiles a second graph, publishes only after validation, and returns to READY. Source/allocation/CRC failure retains the old graph. Temporary space for both graphs is required. Successfully processed RESERVE declarations can remain protected after a failed import.

`BLOAD filename,drive,address[,bytes]` and `BSAVE filename,drive,address,bytes` exchange raw sequential bytes in the editor's BIN format, without a header or metadata. They are ordinary compiled statements and retain program execution after success. BLOAD stops at EOF or its optional count; BSAVE writes exactly its required count. They validate arguments before opening the transport, reject bounded ranges past `$FFFF`, and never wrap an unlimited load into zero page. BSAVE checks final DOS status after closing the data channel. Neither statement changes reservations or blob metadata.

Format 2 validates the complete file before reopening it to restore blob bytes in a second streaming pass. Keep the file unchanged and available until completion. A second-pass I/O failure can change some already restored bytes; there is no blob-sized rollback buffer. SAVE checks OPEN/output/CLOSE transport status and final DOS status before reporting success, and releases temporary export storage on error.

## Stock BASIC PRG import

LOAD also detects the little-endian PRG address `$0801` and converts stock BASIC V2 linked lines into native source. It verifies physical next links, increasing valid line numbers, terminators, token codes and the final zero link. Malformed, oversized/truncated files and appended machine-code payloads are rejected without replacing the old source.

Stock tokens and GO TO become native spellings before tokenization. Strings and REM/DATA preserve raw PETSCII. The converter preserves stock two-character variable identity, including ignored spaces; stock signed `%` names become signed names prefixed PRGINT because native `%` means unsigned. Floating-point source remains subject to the integer language contract. SAVE writes native containers, not PRGs. User-facing conversion rules are in [PRG import](../PRG_IMPORT.md).
