# Test coverage and validation

Run from the repository root after [building and synchronizing the cartridge artifacts](README.md#test):

```sh
python3 tools/test.py
```

The [harness](../../tools/test.py) uses unittest discovery over `tests/test*.py`, adding `host/`, `tests/` and `.tools/py65/` to its import path. Before discovery, [check_runtime.py](../../tools/check_runtime.py) checks documented opcodes, static dependency closures, allowed calls/memory references, bank-call descriptors and instruction boundaries. A preflight failure stops the suite.

Native tests execute assembled cartridge code and generated instructions with deterministic KERNAL stubs. Cartridge-format tests inspect both build and dist images. Subtests, word sweeps and fuzz loops belong to their parent methods. The harness writes `build/test-report.json` with counts, failures/errors/skips, checked runtime instructions, ROM SHA-256 and environment, and exits nonzero on failure. Use that report for run counts rather than a static inventory.

## Coverage by module

| Module | Coverage |
| --- | --- |
| [test_banking.py](../../tests/test_banking.py) | PLA visibility, reset mapping, startup copies, bank/port preservation and interrupts |
| [test_binary_editor.py](../../tests/test_binary_editor.py) | Reservations/blobs, hex and sprite workflows, rendering, BIN/native persistence and failures |
| [test_binary_files.py](../../tests/test_binary_files.py) | BLOAD/BSAVE raw bytes, EOF/count bounds, shadow RAM/I/O, compiled source round trips, argument validation and transport/DOS failures |
| [test_cartridge.py](../../tests/test_cartridge.py) | Magic Desk CRT headers, bank packets and exact ROM reconstruction in build/dist |
| [test_cli.py](../../tests/test_cli.py) | Native console exit status and output handling |
| [test_collection.py](../../tests/test_collection.py) | Captured-heap replay/cycle budget, bitmap boundaries and automatic collection roots |
| [test_design_formatting.py](../../tests/test_design_formatting.py) | Editable Word structure, links, code, ordered lists and scalar notation |
| [test_editor.py](../../tests/test_editor.py) | Command/split editor editing, focus, modes, help, navigation, redraw and INPUT state |
| [test_file_arguments.py](../../tests/test_file_arguments.py) | Optional secondary, evaluation order, boundaries and rejection before I/O |
| [test_formatting.py](../../tests/test_formatting.py) | Host/target canonical listing, TAB/SPC, abbreviations and identifier boundaries |
| [test_integer_design.py](../../tests/test_integer_design.py) | Literal context, destination-independent typing and arithmetic lowering |
| [test_list_break.py](../../tests/test_list_break.py) | RUN/STOP and pending-break cancellation in both editors |
| [test_native.py](../../tests/test_native.py) | Compiler/runtime arithmetic, native bodies, line edits, strings and control flow |
| [test_platform.py](../../tests/test_platform.py) | Shadow RAM, clocks, arrays/functions, devices, control stacks and failed loads/edits |
| [test_prg.py](../../tests/test_prg.py) | Stock token/name conversion, raw PETSCII, malformed files and staged rollback |
| [test_reserve.py](../../tests/test_reserve.py) | Protected RAM, lifetime/conflicts, native gameplay and source imports |
| [test_revision05.py](../../tests/test_revision05.py) | Command submission, LIST, ELSE, RND, shifts, CLEAN and source round trips |
| [test_save_errors.py](../../tests/test_save_errors.py) | Transport/DOS failures, status parsing, cleanup, retry and source preservation |
| [test_services.py](../../tests/test_services.py) | Nested bank calls, registers/flags/stack, interrupt boundaries and shadow operands |
| [test_source.py](../../tests/test_source.py) | Host tokenizer/container validation, literal round trips and malformed-input fuzzing |
| [test_unsigned.py](../../tests/test_unsigned.py) | Words, mixing, functions, arrays, loops, FRE and long imported names |

`test_revision05.py` retains its existing source name; it tests current semantics, not a separate supported firmware version. Use unittest to run a focused module, for example:

```sh
PYTHONPATH=host:tests:.tools/py65 python3 -m unittest discover -s tests -p 'test_design_formatting.py' -v
```

## Supplied-ROM software checks

Provide your own supported stock ROMs:

```sh
python3 tools/check_editor_rom.py --rom-dir /path/to/VICE/C64 --preview build/editor-preview.png
python3 tools/check_binary_editor_rom.py --rom-dir /path/to/VICE/C64 --previews build/binary-previews
```

These execute genuine KERNAL initialization/keyboard/display instructions with injected input and synthetic hardware registers, and can render previews. Matching passed reports are included by the packager when available. See [editor implementation](EDITORS.md).

## Measurements and acceptance

`python3 tools/measure.py` records deterministic instruction/capacity workloads and invokes captured-heap collection measurement. `python3 tools/measure_collection.py` reruns the heap replay alone. Reports include ROM hashes and methodology; historical benchmark baselines remain labeled as such.

Instruction tests and supplied-ROM software checks do not model VIC bus stealing, real IEC devices or physical-machine timing. The [status record](STATUS.md) and [investigations](investigations/README.md) identify VICE smoke checks, user gameplay evidence and remaining cycle-accurate/PAL/NTSC validation.
