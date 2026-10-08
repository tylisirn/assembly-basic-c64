# Implementation status — design revision 0.4

The implemented cartridge is a development build. The revision 0.3 version-one contract remains the release target. Updating the design records actual choices and unfinished requirements; it does not waive those requirements or assert release acceptance.

| Area | Implemented behavior | Remaining work |
| --- | --- | --- |
| Platform | Standard 16 KiB ROM/CRT, explicit KERNAL initialization, fixed RAM runtime, common gateways, RAM hardware vectors, separate raw/KERNAL NMI entry shapes, synthetic IRQ return frame | Cycle-accurate VICE, stock ROM integration, exhaustive interrupt injection, physical PAL and NTSC validation, warm-recovery contracts |
| Editing and storage | Seven-byte stable anchors in 250-byte slabs, exact adjacent tokens/native bodies, final successor JMP, sorted insertion/replacement/deletion, tombstones, coalescing allocator with payloads allocated from the high end, staged failed edits | Stopped payload compaction/rebuild, explicit graphics/machine-code reservations, full graph-integrity preflight before every traversal, complete name-allocation rollback on failed edits |
| Source | Custom Appendix A vocabulary, binary words and hexadecimal radix, whole/full identifiers up to 255 imported bytes, shifted-letter abbreviations, raw comments/strings/DATA, dense export dictionary | Exact firmware LIST whitespace normalization and every malformed text-recovery case; host period abbreviations are an extra host convenience |
| Compilation | Bounded two-pass Pratt parser, real 6502 machine code, stable scalar cells, native branch/line linkage, false IF skips physical line, context and deferred error stubs | Helper-heavy expression code lacks the proposed inline scalar arithmetic optimizations; no stock-ROM differential corpus yet |
| Integer operations | Wrapped 16-bit arithmetic, signed division/comparison/formatting, eager logical operators, precedence, checked byte/address and allocation quantities, integer VAL | Full INPUT conversion/retry compatibility and unsupported numeric diagnostic corpus |
| Control | GOTO, ON GOTO/GOSUB, GOSUB/RETURN, dynamic FOR/NEXT including variable reuse, STOP/END/CONT, frozen stack boundary and edit invalidation | Stock-ROM differential tests for unusual mixed control-stack cases |
| Strings and arrays | Immutable heap strings, concatenation/slicing/conversion, numeric/string arrays, checked bounds/products, eight dimensions, READ array targets, registered-root collection | Broader failure injection and automatic collection/fragmentation stress under IRQ/VIC activity |
| Functions | Full-name DEF FN, compiled expression bodies, stable parameter cells restored after calls, guarded recursion | Activations use a bounded hardware stack with depth limit eight; move them to the designed tagged software activation stack and audit interrupt headroom |
| Devices and clocks | PRINT#/INPUT#/GET#/OPEN/CLOSE/CMD, staged filenames, SYS/USR map recovery, ST, low-word TI, six-digit TI$ read/set | INPUT and GET accept scalar targets only; custom INPUT prompts, line retry, missing/extra-field handling, real serial/device-status tests |
| Persistence | Source-only SAVE, CRC, dense referenced-name IDs, bounded sequential LOAD with second-graph publication and failure rollback, target VERIFY | Target VERIFY compares canonical output bytes rather than canonicalizing arbitrary valid file dictionaries; target loader lacks every DATA_SPELLING equality/context check in Appendix A; host validator is stricter |
| Release evidence | Automated instruction-level regression suite, all 65,536 word round trips in both radices, malformed-container fuzzing, runtime dependency/opcode and size gates | Capacity/fragmentation workload corpus, cycle-accurate latency and speedup comparison, PAL/NTSC and real-device release checklist |

## Recorded architectural decisions

- Stable anchors/bindings allocate from the low end of free spans; payloads and runtime heap objects allocate from the high end, preserving common RAM for future anchor slabs. Common allocations are checked against the `$8000` boundary even for whole free blocks.
- Runtime ABI **2** reserves `$E400–$FFF9` (7,162 bytes); `$FFFA–$FFFF` holds hardware vectors. The allocator spans `[$1400,$D000)` and `[$E000,$E400)`, totaling 49,152 raw bytes. This uses the design's permitted lower-base adjustment.
- The fixed-address runtime is linked separately and stored as a deterministic LZSS load image in the cartridge. Cold start, RUN and CONT decompress the same image without moving user code. The link output proves its RAM addresses; no runtime relocation is assumed.
- String collection is **nonmoving mark-and-sweep**, followed by free-list coalescing, rather than the proposed compacting collector. Roots include line/slab/name/binding objects, arrays, functions, direct code, descriptors, expression temporaries and live helper string pointers. It avoids descriptor pointer rewriting but can leave fragmented free space.
- Name interning compares complete normalized spellings through a linked dictionary. It preserves full identity but has linear compilation lookup rather than hash buckets. Scalar references bind stable cells at compile time.
- Language zero page is `$02–$78`; KERNAL service state uses `$90–$FF`. Common workspace is `$0800–$13FF`. A supported stock KERNAL audit remains a release requirement.
- Runtime ABI and source-container version are separate. Source files remain version **1**, magic `AB64SRC\0`, little-endian fields and CRC-16/CCITT-FALSE. Host validation is authoritative for the complete Appendix A structural and canonical checks currently implemented.

## Releasing version one

Resolve the remaining behavior above, then execute the original section 14 acceptance corpus with genuine KERNAL ROMs, a cycle-accurate emulator, and PAL/NTSC machines. Include every bank-transition interrupt boundary, hardware stack maximum, allocation-failure site and source corruption boundary. Publish measured capacity, startup/copy latency and representative native speedups with normal VIC/IRQ activity. The current harness results cannot substitute for that evidence.
