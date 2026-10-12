# Void Runner collection pause

The supplied VICE 2.4 snapshots `voidrunner-freeze1.vsf` and
`voidrunner-freeze2.vsf`, together with `monitor.log`, identify an exceptionally
slow garbage collection during BASIC line 1930:

```basic
1930 a$=a$+right$("000"+mid$(str$(sc),2),3):return
```

Both snapshots contain the original runtime image without overwritten bytes.
Their arena headers are valid, their free lists are sorted and acyclic, and
reserved sprite/native regions remain excluded. The collector's physical scan
advanced from `$64F9` to `$7265` between snapshots. Both snapshots have identical
user-arena bytes and produce the same revised collection result. The monitor's
repeated four-byte free-list nodes also advance; they do not form a cycle. The SID
continues playing its last configured waveform while BASIC makes no game updates.

The old collector checked every physical allocation against the entire free list
and all program roots, then searched the free list again when reclaiming garbage.
The captured heap has 1,636 physical blocks and 253 free-list nodes. These nested
traversals cause a very long pause even though the heap is intact. This is a
separate problem from the earlier `$C200` code-overwrite JAM fixed with RESERVE.

The revised collector sweeps the sorted free list alongside physical headers,
using previous/next cursors for constant-time insertion. It marks roots once per
2 KiB address window in a 256-byte bitmap overlaid on inactive lexer scratch at
`$0E00–$0EFF`. The payload's low byte selects a bitmap byte; its page within the
window selects one bit. Physical headers, pointers and native code stay in place,
full 16-bit allocation sizes remain available, and coalescing occurs after the
sweep. Runtime collection and stopped CLEAN collection occur outside active
lexing/compilation. No additional arena allocation is required.

Instruction-level replay of the first captured heap gives:

| Measurement | Old collector, remaining work at first halt | Revised collector, complete collection |
| --- | ---: | ---: |
| Instructions | 44,268,554 | 394,049 |
| CPU cycles | 137,980,792 | 1,269,981 |
| Resulting free blocks | 9 | 9 |
| Resulting free physical bytes | 5,651 | 5,651 |

The revised full collection uses approximately 109 times fewer CPU cycles than
just the old collector's remaining work. Its free list matches the completed old
collector exactly; every live allocation and both reserved game regions are
unchanged. These measurements use py65 without VIC/IRQ timing and do not claim
cycle-accurate VICE wall-clock latency. Collection still introduces a finite
pause, and fragmentation remains possible.

`tests/fixtures/voidrunner-heap.zlib` stores only the captured collector inputs:
language zero page, common roots/descriptor state and user-arena bytes. It omits
emulator modules, cartridge/runtime images and unrelated machine state. The
adjacent JSON records provenance, checksum and the baseline free list. Regression
tests compare the resulting heap, enforce an instruction/cycle ceiling, exercise
payloads crossing bitmap windows and sharing low bytes, empty free lists and
allocations larger than 32 KiB, and force automatic collection during 1,200 score
updates while preserving string arrays and compiled functions. The supplied raw
snapshots and monitor log remain in the user's untracked `debug` directory.

Run `python3 tools/measure_collection.py` to reproduce the captured-heap
measurement, or `python3 tools/measure.py` to refresh all measurements.

Use the rebuilt `dist/assembly-basic.crt` or `dist/assembly-basic.bin`, reset the
machine and reenter or LOAD the program. Old snapshots contain the old RAM
runtime and compiled helper addresses, so restoring one does not install this
fix. Source-only `.AB` files are recompiled on LOAD.

If another pause needs inspection in VICE 2.4, break into the monitor, record
`r` and `m 0043 004c`, briefly resume and break again, then repeat. `$43–$44` is
the physical sweep position. It should advance during collection. Use the new
build's `build/assembly-basic.lbl` to identify collector instruction addresses;
addresses from the previous ROM no longer identify the same routines. Screen
copy or a snapshot can capture the evidence; VICE 2.4 lacks the newer monitor
logging commands suggested earlier.

## Gameplay retest and remaining latency — 10 October 2026

Following the revision 0.6 Magic Desk conversion, the user reports successful
loading of Void Runner from disk into VICE, followed by running and playing the
game. Garbage collection completes, but periodically pauses gameplay for roughly
0.25–0.5 seconds. The following maze workload also runs, with collection pauses
of approximately one second:

```basic
10 PRINT CHR$(205 + (ABS(RND(1)) >> 14));:GOTO 10
```

These are user-observed estimates rather than instrumented timings; the VICE
version, timing configuration and test duration were not restated. They establish
successful disk-load/gameplay behavior for the retest, while collection latency
remains open. No collector change is made in response to this report yet.

The maze's CHR$ creates a fresh one-byte heap string every iteration, which PRINT
consumes immediately. This is a useful temporary-allocation stress workload even
with a very small source program. Future profiling should compare its allocation
count and collection phases with Void Runner. Candidate improvements include
avoiding transient strings in supported PRINT expressions and reducing worst
collection latency. Incremental collection needs a defined root/mutation
protocol; preserve stationary code, reservations and live descriptors throughout.
