# Development and implementation

This directory contains build instructions, implementation constraints, validation records and debugging evidence. Programming documentation is in [docs](../README.md); architecture and file specifications are in [design](../design/README.md).

- [Current status and gaps](STATUS.md)
- [Test coverage and validation tools](tests.md)
- [Editor implementation](EDITORS.md)
- [Debugging investigations](investigations/README.md)
- [Instruction/capacity measurements](measurements.json), [collection replay](voidrunner-collection.json) and [editor scroll measurements](editor-scroll-measurements.json)

## Build

Python 3.10 or newer and cc65 (`ca65`, `ld65`) are required. Instruction-level tests also require py65 1.2.0. On Linux amd64, the optional bootstrap downloads checksum-pinned tools into the ignored `.tools` directory. It requires Internet access and `dpkg-deb`, without an administrator installation.

Run from the repository root:

```sh
python3 tools/bootstrap.py
python3 tools/build.py
```

With an existing toolchain, use `python3 tools/build.py --toolchain /path/to/cc65/bin` and install `py65==1.2.0` into the active Python environment.

Outputs include `build/assembly-basic.crt`, the raw `build/assembly-basic.bin`, assembler listing, linker map/labels, runtime/compiler images and `build/size-report.json`. Attach the CRT in VICE; attach a raw BIN explicitly as Magic Desk. The [banking design](../design/banking.md) documents the image format and service contracts.

## Test

Cartridge-format tests check both build and dist. After a firmware change, copy the current ROM/CRT before running the suite:

```sh
cp build/assembly-basic.bin dist/assembly-basic.bin
cp build/assembly-basic.crt dist/assembly-basic.crt
python3 tools/test.py
```

The harness checks runtime dependencies/opcodes before unittest discovery, then writes `build/test-report.json`. See the [test guide](tests.md) for targeted runs, genuine-ROM software checks and the limits of instruction-level validation. Keep firmware and its test report matched; a green result for another ROM hash is not current evidence.

## Documentation and packaging

Edit user guides in `docs/`, design specifications in `docs/design/`, and implementation notes here. Describe current behavior directly; use Git for change history. Keep old/new comparisons only when needed to interpret a debugging record or benchmark. File-format numbers and runtime ABI identifiers are technical contracts, independent of release history.

After firmware changes and passing tests:

```sh
python3 tools/measure.py
python3 tools/update_design.py
python3 tools/package.py
```

`measure.py` records instruction/capacity and captured-heap replay data here. `update_design.py` rebuilds the design DOCX and text export from current design Markdown plus the linked size report. It preserves Word styles and package resources and records document/source hashes in [design-sync.json](design-sync.json). Edit the Markdown sources, then regenerate the exports; editing a generated copy does not update those sources. Documentation-only changes require regeneration but do not require new firmware measurements.

`package.py` requires matching ROM, tests, measurements and design hashes before copying cartridge artifacts, ABI metadata, example containers and available matching ROM-validation reports into `dist/`. It writes checksums to `dist/manifest.json`. Packaging does not establish physical-machine or cycle-accurate acceptance.

## Source layout

| Directory | Role |
| --- | --- |
| [src](../../src) | Cartridge platform, editors, lexer/compiler, runtime and file transport |
| [host/ab64](../../host/ab64) | Vocabulary, container validator, CLI and CPU harness |
| [tests](../../tests) | Host, native execution, memory/banking and failure regressions |
| [tools](../../tools) | Bootstrap/build, validation, measurements, design generation and packaging |
| [examples](../../examples) | Numbered BASIC examples |
| [dist](../../dist) | Packaged cartridge artifacts and example containers |

The generated reports identify their ROM hashes and environments. Test module names retained for source continuity do not define public release versions.
