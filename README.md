# Assembly BASIC for the Commodore 64

A 64 KiB classic Magic Desk autostart cartridge with an on-machine tokenizer and two-pass native 6502 compiler. Numbered lines retain custom source tokens beside their generated machine code. RUN executes in RAM with cartridge and KERNAL ROM hidden; device services use a common-RAM bank gateway. No host compiler is required to enter or run BASIC programs on the C64.

This is a working development implementation of design revision 0.6, **not the completed version-one release**. [Implementation status](docs/IMPLEMENTATION_STATUS.md) lists the remaining language, validation and hardware work. The original revision 0.3 design is preserved in the first Git commit, `9480026`.

## Build and test

Python 3.10 or newer and cc65 (`ca65`, `ld65`) are required. The instruction tests additionally require py65 1.2.0. On Linux amd64, the optional bootstrap downloads checksum-pinned tools into the ignored `.tools` directory; it requires Internet access and `dpkg-deb`, but no administrator installation.

```sh
python3 tools/bootstrap.py
python3 tools/build.py
python3 tools/test.py
```

With an existing toolchain, use `python3 tools/build.py --toolchain /path/to/cc65/bin` and install `py65==1.2.0` into your Python environment. The build produces `build/assembly-basic.crt`, the raw 64 KiB `build/assembly-basic.bin`, assembler listing, linker map, labels, raw runtime/compiler images, and `build/size-report.json`. Checked-in development cartridge artifacts are in [dist](dist).

The CRT uses Magic Desk type 19 with eight 8 KiB CHIP packets at `$8000`, GAME high and EXROM low. VICE cartconv accepts it and converts it back to the identical ROM. In VICE, use “Attach CRT image” for the `.crt`. A raw `.bin` must be attached as Magic Desk; the former generic 16KB attachment setting no longer applies. For example, with VICE installed:

```sh
x64sc -cartcrt dist/assembly-basic.crt
```

The user has successfully loaded Void Runner from disk and played it in VICE with this conversion. Collection still causes visible pauses (roughly 0.25–0.5 seconds in the game and one second in the maze stress workload). Broader emulator acceptance and physical PAL/NTSC validation remain pending; see the [recorded validation and backlog](docs/IMPLEMENTATION_STATUS.md).

## Bank layout

Bank 0 contains the current command/editor code, bank 1 the raw compiler image and bank 2 the raw runtime image. Banks 3–7 reserve space for the improved editor/PRG conversion, 16.8 fixed-point and PRINT extensions, VIC/SID/sprite commands, resources and expansion. These planned features are not implemented yet; current integer semantics remain unchanged. See [the bank map and gateway contracts](docs/MAGIC_DESK_BANKS.md).

Firmware revision 0.6 changes runtime ABI to 4; source-container version remains 1. Hard-reset after attaching the new cartridge and reload/reenter source. Old snapshots retain the earlier runtime and native helper references.

## Use

At `READY.`, enter decimal numbered lines, then use RUN, LIST, CLEAN, NEW and the usual direct commands. Enter advances the screen cursor before processing each command or numbered line. Numbered entry and deletion resume input without another READY prompt. A tokenization or compilation failure prints an error while retaining the new line as repairable source. Enter a line number alone to delete it. Identifiers use their full spelling; write `PRINT A`, since `PRINTA` is a variable name. Integers wrap to 16 bits and display signed decimal. Hexadecimal constants preserve their radix in LIST.

```basic
10 VIDEO=$D000
20 POKE VIDEO+$21,1
30 PRINT VIDEO;PEEK(VIDEO+33)
40 END
RUN
```

Strings, multidimensional numeric/string arrays, DEF FN, GOSUB, FOR/NEXT, IF/THEN/ELSE, DATA/READ/RESTORE and STOP/CONT are implemented. `SAVE "PROGRAM.AB",8`, `LOAD "PROGRAM.AB",8` and `VERIFY "PROGRAM.AB",8` use the custom sequential source container, not stock tokenized PRG files. Tape and RS-232 transports are explicitly unsupported. LOAD stages a second program and preserves the old source on failure; `NEW` can free space before loading a large file.

`LIST 10` lists one line; `LIST 10-50` lists an inclusive range. `LIST -50` and `LIST 10-` accept open endpoints. LIST starts on a new screen line.

`IF condition THEN statements ELSE statements` selects one arm for the rest of the physical line. ELSE binds to the nearest unmatched IF; either arm can be a literal line target. `RND(n)` returns a random 16-bit word, displayed as a signed integer: positive arguments advance the generator, zero repeats the last word, and negative arguments reseed it reproducibly. The first positive call seeds from the KERNAL jiffy clock.

`<<` and `>>` are arithmetic shifts. Counts must be 0–255; left shifts wrap, right shifts preserve the sign, and counts of 16 or more yield zero or the right-shift sign fill. Shifts bind below addition and above comparisons. Literal power-of-two multiplication uses a left shift; division uses a biased right shift to retain truncation toward zero (`-5/2` is -2, while `-5>>1` is -3).

`CLEAN` is a stopped, direct command. It removes unreferenced anchor slots and symbols, fills new slabs densely, remaps name IDs and recompiles every line and native reference. It clears variable values and invalidates CONT. Rebuilding needs temporary space for a source snapshot and a second graph; allocation failure retains the old source. The Magic Desk cartridge uses runtime ABI 4, reserves 6 KiB at `$1400–$2BFF` for a compiler image copied at startup, and has a 42 KiB raw program arena.

`RESERVE address,bytes` declares RAM for graphics or machine code before the
compiler allocates it. Both arguments must be unsigned numeric literals aligned
to 256-byte pages; the nonzero range must lie within one user-arena span and be
entirely free. Up to eight regions are supported. Put declarations on the first
numbered line before entering/importing the rest of the program, or issue them
directly before loading it. They take effect during compilation, cannot appear
inside IF, and do not run again during RUN. Repeating identical bounds is harmless;
conflicting/live allocations fail without being overwritten. Reservations remain
through RUN, CLR, edits and CLEAN; NEW releases them. SAVE stores numbered
declarations, so LOAD reinstates them. Removing a declaration does not release
its region until NEW. Failed entry/import may retain a successfully declared
reservation. POKE and SYS still require the caller to respect memory ownership.

[Void Runner](examples/voidrunner.bas) uses this first line:

```basic
10 RESERVE $3C00,$200:RESERVE $C000,$300:CLR
```

Start with `NEW`, paste the updated program, and `RUN`, or load
[dist/examples/voidrunner.ab](dist/examples/voidrunner.ab) from a sequential file.
The sprite pages `$3C00–$3DFF` and native code/workspace `$C000–$C2FF` are excluded
from compilation, heap allocation and collection. `$C000` is otherwise user-arena
RAM, not implicit scratch space. Stock BASIC's `POKE 55/56` memory-top convention
does not apply because this language owns its own zero-page state.

The later gameplay freeze was traced to a long garbage-collection pause. The updated
collector uses windowed bitmap marking and an ordered free-list sweep; captured-heap
replay uses approximately 109 times fewer CPU cycles. See the
[investigation and retest instructions](docs/VOIDRUNNER_FREEZE.md). Reset with the
new cartridge and reload/reenter source; restoring an old snapshot restores its
old runtime too.

## Host source tools

The standard-library encoder/decoder exchanges numbered Latin-1/PETSCII source with version-one `.AB` files. Compilation still occurs in the cartridge. Set `PYTHONPATH=host` on Linux/macOS, or install the package with `python -m pip install -e .`.

```sh
PYTHONPATH=host python3 -m ab64 encode examples/hello.bas build/hello.ab
PYTHONPATH=host python3 -m ab64 decode build/hello.ab build/hello.bas
PYTHONPATH=host python3 -m ab64 verify build/hello.ab build/hello.ab
PYTHONPATH=host:.tools/py65 python3 -m ab64 run examples/hello.bas
PYTHONPATH=host:.tools/py65 python3 -m ab64 repl
```

`run` and `repl` execute the actual assembled cartridge and generated machine code using an instruction-level CPU and deterministic KERNAL stubs. They provide a development console, without modelling VIC timing, real IEC devices or a complete stock KERNAL.

## Project files

- [src](src): cartridge platform, editor, lexer, compiler, native runtime and source-file transport.
- [host/ab64](host/ab64): source vocabulary, strict container validator, command-line tools and CPU harness.
- [tests](tests): source-format, native execution, allocator, bank/interrupt and failure regression tests.
- [tools](tools): pinned bootstrap, reproducible build, runtime dependency check, measurement and design synchronization.
- [IMPLEMENTATION_SUMMARY.md](IMPLEMENTATION_SUMMARY.md): implementation report requested with the project.
- [Assembly_BASIC_C64_Design.docx](Assembly_BASIC_C64_Design.docx): synchronized design; Appendix B records implementation status and differences.

After changing the firmware, run the build and tests, then `python3 tools/measure.py` and `python3 tools/update_design.py` to refresh the measured documentation. Run `python3 tools/package.py` to publish matching ROM, CRT, ABI, example containers and validation metadata into `dist`. Before testing, copy the current build ROM/CRT into `dist` because cartridge-format tests check both locations.
