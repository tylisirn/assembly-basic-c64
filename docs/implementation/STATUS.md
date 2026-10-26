# Implementation status and validation gaps

This record distinguishes current behavior from unimplemented work. The [language reference](../LANGUAGE_REFERENCE.md) defines public syntax and limits; the [design](../design/README.md) describes the current architecture. An item below is not implemented merely because it was once proposed.

## Implemented capabilities

| Area | Current implementation |
| --- | --- |
| Platform | 64 KiB/eight-bank Magic Desk ROM/CRT; fixed RAM compiler/runtime; bank-preserving ROM/RAM/KERNAL gateways; RAM interrupt vectors |
| Source and editing | Whole/full identifiers, decimal/hex word tokens, canonical ranged/breakable LIST, repairable malformed source, split screen editor with F3 jumps and F5 binary editing |
| Compilation | Bounded two-pass Pratt parser, documented native 6502 instructions, stable cells/anchors, IF/THEN/ELSE, literal power-of-two multiplication/division lowering |
| Values and control | Signed/unsigned wrapping words, arithmetic shifts, integer functions/RND, strings, multidimensional arrays, DATA/READ/RESTORE, DEF FN, GOSUB, FOR/NEXT, STOP/END/CONT |
| Memory | Address-ordered coalescing allocator, nonmoving collection, page reservations and stopped CLEAN rebuild |
| Devices | PRINT#/INPUT#/GET#/OPEN/CLOSE/CMD, ST, low-word TI, TI$ read/set, SYS/USR mapping recovery |
| Persistence | Native source and binary metadata/blob containers with CRC, staged LOAD, target VERIFY, stock BASIC PRG import, checked SAVE transport/final DOS status |
| Binary editing | Manual/BASIC reservations, SPR/BIN/ASM blobs, bounded hex editing, hires/multicolor sprites and hardware previews, per-sprite palettes and raw BIN exchange |

## Known limits and follow-up work

| Area | Limit or remaining work |
| --- | --- |
| Compiler | Expressions remain helper heavy; general constant folding and inline scalar arithmetic optimization are absent |
| Editing | Complete name-allocation rollback on failed edits and full graph-integrity preflight before every traversal are incomplete |
| Memory | No sliding arena compaction; fragmentation and temporary second-graph space can limit CLEAN/LOAD; collection can cause visible pauses |
| Functions | Eight guarded hardware-stack activations; the proposed software activation stack is not implemented |
| Input | INPUT/GET accept scalars only; custom prompts, full stock conversion/retry and missing/extra-field behavior remain incomplete |
| File validation | Target LOAD lacks every DATA_SPELLING equality/context check; the host validator is stricter |
| VERIFY | Target compares canonical current-program bytes, rather than canonicalizing arbitrary valid input dictionaries |
| Numeric/features | Floating/fixed point, remainder, stock PRG export, built-in assembler and additional hardware command sets are absent |
| Devices | Tape/RS-232 unsupported; broader real serial/device-status tests remain needed |
| Stress testing | Expand capacity/fragmentation corpus, allocation-failure injection, unusual mixed control-stack tests, unsupported-number diagnostics and stock-ROM differential coverage |
| Platform acceptance | Broader interrupt injection and warm recovery checks, cycle-accurate latency/speed comparisons, physical PAL/NTSC and real-device validation remain open |

Current memory/layout and runtime entry contracts are in [architecture](../design/architecture.md) and [banking](../design/banking.md), with linked usage in [build/size-report.json](../../build/size-report.json). Avoid maintaining copied size/count claims separately from their reports.

## Validation evidence

The automated [test harness](tests.md) executes actual assembled/native instructions in py65 with deterministic KERNAL stubs, checks container round trips and malformed inputs, replays a captured heap, enforces runtime dependencies/opcodes and checks cartridge layout. Counts and ROM fingerprints belong to `build/test-report.json` and packaged `dist/test-report.json`.

Optional supplied-ROM editor checks execute genuine 901227-03 KERNAL instructions with injected keyboard/device bytes and synthetic raster status. They add software integration evidence without modeling VIC/IEC timing. VICE startup smoke checks with genuine ROMs passed for C64 old PAL, C64 PAL, C64C PAL and C64 NTSC in Linux VICE 3.7.1. Windows GTK3VICE 3.10 retesting and physical-machine validation remain open. The [startup investigation](investigations/VICE_STARTUP_FREEZE.md) records the tested hashes/configurations and CPU-port initialization correction.

The [SAVE investigation](investigations/SAVE_FAILURE.md) records a VICE 2.4 reproduction, corrected transport/DOS reporting and a recovered program/blob round trip. The [binary-load investigation](investigations/BINARY_LOAD_FREEZE.md) records an unresolved captured serial-read stall: repeated fresh transfers succeed, and the evidence does not isolate a firmware or emulator defect.

User-reported VICE disk-load/gameplay validation exists for Void Runner. Collection completes but causes approximate 0.25–0.5 second game pauses and roughly one-second pauses in the maze workload. These estimates are separate from deterministic py65 measurements, and the report did not specify the emulator configuration or play duration. The [collection investigation](investigations/VOIDRUNNER_FREEZE.md) and [replay measurements](voidrunner-collection.json) retain the evidence and profiling directions.
