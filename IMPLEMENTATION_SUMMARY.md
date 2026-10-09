# Assembly BASIC implementation summary

The original design document was committed first as `9480026`. The project now contains a working native-code development cartridge, a reproducible build, source-file tools, automated tests, examples and synchronized design documentation. The full version-one release contract is **not yet complete**; the outstanding requirements are listed in [docs/IMPLEMENTATION_STATUS.md](docs/IMPLEMENTATION_STATUS.md) and design Appendix B.

## Firmware

The cartridge initializes the C64 explicitly and supplies its own editor, tokenizer, two-pass compiler and runtime. The compiler generates 6502 instructions on the target machine. It retains binary source tokens next to each exact-sized native body; seven-byte stable anchors and each body's final successor JMP support ordered editing, forward branches and LIST without relocation tables.

RUN hides cartridge and KERNAL ROM with the `$35` execution map. Fixed-address helpers execute in upper RAM. Common-RAM gateways provide KERNAL calls, IRQ/NMI handling, SYS/USR return recovery and source transport. The compressed runtime is restored at startup, RUN and CONT. Source and code can occupy cartridge and KERNAL shadow RAM.

Implemented language facilities include wrapping integer arithmetic, arithmetic shifts and word RND, signed formatting and comparisons, hexadecimal immediates, full identifier identity, strings, multidimensional numeric/string arrays, compiled DEF FN, IF/THEN/ELSE and ON, GOSUB, dynamic FOR/NEXT, DATA/READ/RESTORE, STOP/CONT, memory/device operations and clock access. Payloads allocate from the high end of free spans to preserve common RAM for stable anchors and bindings. A coalescing allocator and registered-root nonmoving string collector preserve stationary code and continuation PCs.

SAVE emits the design's source-only version-one container with dense referenced-name IDs and CRC. LOAD builds a second source graph, validates it and publishes it after completion; failures retain the old source. The host tools provide stricter format validation, canonical source exchange and a console executing the assembled cartridge through py65.

## Revision 0.5

The editor outputs the carriage return received from CHRIN through CHROUT before processing each submitted command, numbered line, deletion or blank line, so subsequent output and input start on the next screen line. Numbered entry and deletion resume input without READY. Recoverable lexical/compilation failures report a diagnostic immediately and retain the new source and a deferred error stub, including malformed DATA fields. LIST begins on a new line and accepts exact numbers, inclusive ranges and open endpoints.

ELSE binds to the nearest unmatched IF on the same physical line; arms can contain colon-separated statements or literal line targets. RND returns a full 16-bit word from a full-period LCG. Its first positive call seeds from the KERNAL clock; positive calls advance, zero repeats, and negative arguments reseed reproducibly.

The compiler supports arithmetic `<<` and `>>`, with shifts below addition and above comparisons. Counts are checked bytes, and counts ≥16 produce zero/sign fill. Literal power-of-two multiplication in either operand becomes a left shift. Power-of-two literal division becomes a biased arithmetic right shift, preserving signed truncation toward zero; redundant parentheses and unary plus on literals are accepted. The `$8000` divisor is signed -32768 and additionally negates the shifted quotient.

Direct CLEAN rebuilds dense anchor slabs and a dense referenced-name dictionary from a temporary source snapshot, remaps token IDs and recompiles all branches, cells, array/function records and native references. It keeps referenced missing targets, discards historical unreferenced slots/names, clears values and invalidates CONT. Allocation failures during snapshot or staged compilation retain the old source and release temporary allocations. This requires temporary headroom; it is not general sliding compaction of every allocation.

To fit these facilities in the standard 16 KiB cartridge, the compiler is now linked for a 6 KiB resident reservation at `$1400–$2BFF` and stored compressed alongside the runtime. Startup decompresses both fixed-address images. The raw user arena is 42 KiB and runtime ABI is 3; source containers remain version 1 with additive shift/ELSE/CLEAN token codes.

## Measured build and verification

The exact linked section sizes, ROM checksum and memory boundaries are recorded in [dist/size-report.json](dist/size-report.json). The 16,384-byte cartridge uses runtime ABI 3 at `$E400`, with a 7,162-byte runtime reservation, a 6,144-byte resident compiler reservation, 3,072-byte common workspace and 43,008-byte raw user arena. The runtime occupies 6,765 bytes before compression and 5,043 bytes in ROM; the compiler occupies 5,411 bytes and compresses to 3,806 bytes. Gateway code uses 392 bytes. ROM contents use 16,048 bytes, leaving 336 bytes of combined headroom.

Run `python3 tools/build.py` and `python3 tools/test.py` after the optional checksum-pinned local bootstrap. All 61 regression tests pass. The suite checks the VICE-compatible CRT packet layout and executes the native machine code to check word semantics, all word encodings, source round trips and corruption, randomized edits, array/function/string behavior, exact anchor/trailer layout, execution beneath ROM, map recovery, IRQ/NMI frames, clock setting, frozen continuations, source-load rollback and runtime refresh, resident compiler protection, screen Enter cursor advancement, ranged LIST, entry diagnostics, nested ELSE, deterministic RND, shift precedence/counts, signed power-of-two lowering, and CLEAN remapping/rollback at seven allocation points. A static runtime check rejects undocumented instructions and ordinary helper calls outside the copied runtime or declared low-RAM gateways.

[docs/measurements.json](docs/measurements.json) records reproducible instruction counts and line-layout measurements from the deterministic harness. The cold-NEW capacity scenario stores 690 lines of `<number> A=A+1`; line 691 fails safely with 46 free physical bytes remaining. Capacity depends on source, names, allocations and fragmentation. These are development measurements, not C64 timing or hardware speedup claims. The build was reproduced with checksum-pinned cc65 and py65 dependencies; the example programs were encoded, decoded, verified and executed through the native cartridge.

## Design synchronization and limits

The design is revision 0.5. Its memory map, fixed runtime addresses, compressed load image, actual interning and collection strategies, workspace and measured budgets match the implementation. Appendix B explicitly identifies incomplete release requirements. The original version-one goals remain visible instead of being silently removed.

The important unfinished areas are general arena compaction and allocator reservations; full INPUT/GET behavior; software-stack function activations; every target-side DATA_SPELLING validation rule; canonical target VERIFY for differently numbered dictionaries; graph/interrupt/failure hardening; and cycle-accurate, genuine-ROM, PAL/NTSC and real-device acceptance tests. The checked-in cartridge should be treated as a development artifact until these are completed.

The CRT packaging was corrected after a VICE compatibility report. The original two 8 KiB CHIP packets at `$8000` and `$A000` were accepted by CCS64, but VICE 3.7.1's generic loader treats a second packet as Ultimax ROM and rejects `$A000`. The updated CRT contains one contiguous 16 KiB packet at `$8000`. Its header and packet bytes match VICE 3.7.1 `cartconv -t normal` output except for the cartridge name, and conversion back to binary reproduces the original ROM exactly. Both `build` and `dist` images use the corrected packaging; revision 0.5 retains this VICE-compatible packet layout.
