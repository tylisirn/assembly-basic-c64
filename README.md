# Assembly BASIC for the Commodore 64

A standard 16 KiB autostart cartridge with an on-machine tokenizer and two-pass native 6502 compiler. Numbered lines retain custom source tokens beside their generated machine code. RUN executes in RAM with cartridge and KERNAL ROM hidden; device services use a common-RAM bank gateway. No host compiler is required to enter or run BASIC programs on the C64.

This is a working development implementation of design revision 0.4, **not the completed version-one release**. [Implementation status](docs/IMPLEMENTATION_STATUS.md) lists the remaining language, validation and hardware work. The original revision 0.3 design is preserved in the first Git commit, `9480026`.

## Build and test

Python 3.10 or newer and cc65 (`ca65`, `ld65`) are required. The instruction tests additionally require py65 1.2.0. On Linux amd64, the optional bootstrap downloads checksum-pinned tools into the ignored `.tools` directory; it requires Internet access and `dpkg-deb`, but no administrator installation.

```sh
python3 tools/bootstrap.py
python3 tools/build.py
python3 tools/test.py
```

With an existing toolchain, use `python3 tools/build.py --toolchain /path/to/cc65/bin` and install `py65==1.2.0` into your Python environment. The build produces `build/assembly-basic.crt`, the raw 16 KiB `build/assembly-basic.bin`, assembler listing, linker map, labels, raw and compressed runtime images, and `build/size-report.json`. Checked-in development cartridge artifacts are in [dist](dist).

The CRT is a standard type-zero cartridge with two 8 KiB CHIP packets and both GAME and EXROM low. Load it as a cartridge in a C64 emulator. For example, with VICE installed:

```sh
x64sc -cartcrt dist/assembly-basic.crt
```

VICE and physical PAL/NTSC machine validation remain pending; see the status document before treating this as a hardware release.

## Use

At `READY.`, enter decimal numbered lines, then use RUN, LIST, NEW and the usual direct commands. Enter a line number alone to delete it. Identifiers use their full spelling; write `PRINT A`, since `PRINTA` is a variable name. Integers wrap to 16 bits and display signed decimal. Hexadecimal constants preserve their radix in LIST.

```basic
10 VIDEO=$D000
20 POKE VIDEO+$21,1
30 PRINT VIDEO;PEEK(VIDEO+33)
40 END
RUN
```

Strings, multidimensional numeric/string arrays, DEF FN, GOSUB, FOR/NEXT, IF/GOTO, DATA/READ/RESTORE and STOP/CONT are implemented. `SAVE "PROGRAM.AB",8`, `LOAD "PROGRAM.AB",8` and `VERIFY "PROGRAM.AB",8` use the custom sequential source container, not stock tokenized PRG files. Tape and RS-232 transports are explicitly unsupported. LOAD stages a second program and preserves the old source on failure; `NEW` can free space before loading a large file.

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

After changing the firmware, run the build and tests, then `python3 tools/measure.py` and `python3 tools/update_design.py` to refresh the measured documentation. Copy the validated ROM, CRT and size report into `dist` when publishing a new development artifact.
