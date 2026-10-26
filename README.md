# Assembly BASIC for the Commodore 64

A BASIC cartridge that compiles programs to native 6502 machine code on the C64. Enter, edit, save and run programs without a host compiler. It includes a split screen source editor and a binary/sprite editor.

## Getting started

Attach [dist/assembly-basic.crt](dist/assembly-basic.crt) as a cartridge in VICE and start the C64:

```sh
x64sc -cartcrt dist/assembly-basic.crt
```

To build your own cartridge, see the [build and development guide](docs/implementation/README.md).

## Use

At `READY.`, enter numbered BASIC lines and use `RUN`, `LIST`, `NEW` and the usual direct commands. Enter a line number alone to delete it. `BASIC` opens the [source editor](docs/SCREEN_EDITOR.md); `SPRDEF` or F5 in that editor opens the [binary/sprite editor](docs/BINARY_EDITOR.md).

For programmers familiar with C64 BASIC V2, the main differences are:

- All numbers are 16-bit integers. Unsuffixed variables are signed (-32768–32767); `%` variables are unsigned (0–65535). Arithmetic wraps, division truncates, and assignment preserves all 16 bits. There is no floating point.
- Nonnegative literals are unsigned; negative literals are signed. Mixed signed/unsigned arithmetic uses signed interpretation. A literal directly combined with a typed expression adopts its type when representable; evaluation is independent of the assignment destination.
- Full identifiers are significant and case insensitive. Keywords require boundaries: write `PRINT SCORE`, since `PRINTSCORE` is a variable name.
- `$` introduces hexadecimal literals, for example `$D000`. `<<` and `>>` add left and arithmetic right shifts.
- `SAVE` writes native `.AB` program files. `LOAD` accepts `.AB` files and imports [stock BASIC PRGs](docs/PRG_IMPORT.md). Stock PRG export is unavailable.

Custom keywords and commands:

| Keyword | Purpose |
| --- | --- |
| `ELSE` | Alternate arm of an `IF`, on the same physical line |
| `RESERVE address,bytes` | Protect RAM for graphics or machine code before entering/loading the rest of a program |
| `BLOAD filename,drive,address[,bytes]` | Load raw bytes into memory, stopping at EOF or the optional byte limit |
| `BSAVE filename,drive,address,bytes` | Save exactly the specified memory bytes without a header or metadata |
| `CLEAN` | Rebuild source storage, clear values and invalidate `CONT`; direct mode only |
| `BASIC` | Open the source editor; direct mode only |
| `SPRDEF` | Open the binary/sprite editor; direct mode only |
| `QUIT` | Close the source editor |

Keywords with changed behavior:

| Keyword | Difference from C64 BASIC V2 |
| --- | --- |
| `RND(n)` | Returns a signed 16-bit word; positive advances, zero repeats, negative reseeds |
| `FRE()` / `FRE(n)` | Collects garbage and returns an unsigned free-byte count; the optional numeric argument is ignored |
| `INT`, `ABS`, `SGN`, `STR$`, `VAL`, `^` | Operate on integers under the signed/unsigned rules; `VAL` accepts hexadecimal, and negative powers are unsupported |
| `FOR`, `NEXT` | Support unsigned loop variables and terminate on unsigned wrap/underflow |
| `TI` | Returns the signed low 16 bits of the jiffy clock; `TI$` retains the six-digit clock form |
| `PEEK`, `POKE`, `SYS`, `USR` | Run with RAM beneath ROM visible and hardware I/O accessible; `USR` passes and returns an integer in A/X |
| `SAVE`, `LOAD`, `VERIFY` | Use native program persistence; loading replaces the program and returns to `READY.` |
| `INPUT`, `INPUT#`, `GET`, `GET#` | Accept scalar targets only; custom `INPUT` prompts and full stock retry/field handling are unavailable |

Unsupported keywords/functions are `SQR`, `LOG`, `EXP`, `COS`, `SIN`, `TAN`, `ATN`, `π` and native `GO TO` (use `GOTO`). Fractional/scientific literals, fixed point, a remainder operator, tape and RS-232 transport are also unsupported.

The [language reference](docs/LANGUAGE_REFERENCE.md) documents the complete supported syntax, integer rules, commands and limits.

```basic
10 VIDEO%=$D000
20 POKE VIDEO%+$21,1
30 PRINT "BACKGROUND:";PEEK(VIDEO%+$21)
40 END
RUN
```

See the [user documentation](docs/README.md), [example programs](examples) and [host source tools](docs/HOST_TOOLS.md) for more. Contributors can start with the [implementation guide](docs/implementation/README.md) and [design documentation](docs/design/README.md).
