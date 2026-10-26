# Cartridge and compiler architecture

Assembly BASIC is an on-machine tokenizer and native 6502 compiler. Retained custom source tokens support LIST, editing and recompilation; execution follows generated instructions rather than dispatching statement tokens. The cartridge supplies its own integer arithmetic, arrays, strings and BASIC-level device adapters. It does not call the stock BASIC evaluator.

## Execution and memory ownership

The 64 KiB Magic Desk cartridge has eight 8 KiB banks. Commands and source transport execute in ROM. A compiler image is copied to fixed RAM at cold start; hot execution helpers also have a fixed RAM image. Cold execution services use explicit banked calls. See [banking](banking.md) for transitions and interrupt contracts.

| Address range | Owner |
| --- | --- |
| `$0000–$0001` | 6510 direction and mapping port |
| `$0002–$0078` | Language zero-page state |
| `$0090–$00FF` | KERNAL service state; preserve according to each service |
| `$0100–$01FF` | Bounded hardware stack |
| `$0200–$0258`, `$02A7–$02FF` | Binary editor metadata; intervening KERNAL tables remain available |
| `$0334–$03FF` | Common service entry stubs and editor state |
| `$0400–$07FF` | Screen RAM and sprite pointers |
| `$0800–$13FF` | Language workspace, gateways, scratch and software stacks |
| `$1400–$2BFF` | Resident compiler, excluded from allocation |
| `$2C00–$7FFF` | Common user arena; stable anchors and bindings must fit here |
| `$8000–$CFFF` | User arena, including RAM beneath cartridge/BASIC ROM |
| `$D000–$DFFF` | Hardware I/O; underlying RAM excluded from allocation |
| `$E000–$E3FF` | User arena beneath KERNAL |
| `$E400–$FFF9` | Fixed RAM runtime |
| `$FFFA–$FFFF` | RAM hardware vectors |

The two user spans are `[$2C00,$D000)` and `[$E000,$E400)`: 43,008 raw bytes before source, code, objects and headers. User graphics/machine code must declare reservations before allocations occupy those bytes. Stock BASIC memory-top POKEs do not configure this arena. Exact linked sizes are in [build/size-report.json](../../build/size-report.json), and generated design exports include its tables.

## Allocation and collection

Allocated blocks have a two-byte little-endian physical size including the header. Free blocks contain size and next-free pointer in four bytes; every physical allocation is at least four bytes. The free list is address ordered and coalesces adjacent blocks. Stable/common objects allocate from the low end; source/code and heap payloads allocate from the high end to preserve common space.

The collector is nonmoving mark-and-sweep. It marks registered roots once per 2 KiB address window using a 256-byte bitmap in inactive scratch at `$0E00–$0EFF`, then sweeps physical headers alongside monotonic free-list cursors and coalesces. Roots include slabs, names, bindings, live line payloads, arrays/functions, direct code, descriptors, expression temporaries and helper string roots. Collection occurs outside active lexing/compilation and skips reserved ranges. It never moves native code or rewrites pointers. Fragmentation can prevent an allocation despite sufficient total free bytes.

`FRE` runs collection while preserving live values and continuations. Direct `CLEAN` instead serializes referenced source to temporary RAM, builds a second graph with dense names/anchor slabs, recompiles every reference, publishes it and clears values/continuations. Failure retains the old source. CLEAN needs temporary headroom and does not promise general sliding compaction.

## Stable lines and native linkage

A stable anchor is seven bytes. Branch targets use its address, so replacing a line does not invalidate other native branches.

| Anchor offset | Bytes | Meaning |
| --- | --- | --- |
| 0 | 1 | `$4C`, absolute JMP opcode |
| 1 | 2 | Native body address, or the undefined-line helper |
| 3 | 2 | Decimal line number, 0–63999 |
| 5 | 2 | Payload pointer; zero for an unresolved/deleted line |

Anchors occupy 35-slot slabs: two-byte allocation header, two-byte slab link, one-byte used count and 245 slot bytes, totaling 250 bytes. Deleted/forward-reference slots persist until NEW or CLEAN.

Each live line has one exact-sized source/code allocation:

| Location | Meaning |
| --- | --- |
| `payload-2` | Physical allocation size word |
| `payload` | Token-stream length T, 1–255 |
| `payload+1` | T authoritative source-token bytes |
| `payload+1+T` | Native body, also the anchor's JMP destination |
| `block end-3` | Final `$4C` and next-live-anchor word, or RUN_END |

The trailer operand doubles as the sorted source-list successor. Insertion patches the predecessor trailer (or global head); replacement retains the anchor and successor; deletion unlinks the payload and points the anchor at undefined-line handling. No persistent relocation, incoming-reference or statement-entry table is stored. Source scans beneath ROM use a common-RAM accessor.

## Tokenization and compilation

Full uppercase identifiers are interned in a linked dictionary with a one-byte spelling length and 16-bit ID. Native scalar references bind stable cells at compile time; runtime expression evaluation does not search names. Scalars, arrays and functions have their own binding kinds. See [source format](source_format.md) and [integer arithmetic](integer_arithmetic.md).

A bounded Pratt parser runs sizing and emission passes over the retained tokens. It emits documented NMOS 6502 instructions, native branches and helper calls. Most expression operations use helpers; the illustrative inline-scalar optimizations sometimes associated with native compilers are not implemented. Literal power-of-two multiplication/division uses shifts, with signed-division bias preserving truncation toward zero. General constant folding is not implemented. Long conditional branches use an inverse short branch over an absolute JMP.

A numbered edit stages tokens, bindings, forward anchors and its new payload before publishing pointer/link changes in a short critical section. Recoverable malformed/unsupported source remains listable and gets a deferred runtime trap; resource failure retains the previous payload. Complete name-allocation rollback is a known gap. Edits clear values and invalidate CONT before replacing native PCs.

## Runtime values and control state

Numeric cells/elements are two-byte words. Expression values distinguish signed, unsigned and string types. String descriptors contain a byte length, payload pointer and ownership/root flags. Immutable strings may share payloads; concatenation and substrings allocate new values, and lasting literals/assignments use heap-owned storage. Allocating helpers must register temporary pointers before collection.

Array records hold stable bounds/type metadata and a payload pointer. Numeric elements use two bytes, string descriptors four. Dimension products and offsets are checked before narrowing to word addresses. Arrays have inclusive bounds, up to eight dimensions, and an implicit upper bound of 10 when first used without DIM.

GOSUB and FOR use a separate 512-byte tagged software stack. A GOSUB frame is three bytes (tag and continuation PC); a FOR frame is nine (tag, cell, limit, signed step and PC). RETURN/NEXT search dynamic frames. Suspended programs freeze their control frames below the direct-command stack boundary. STOP/END/CONT preserve native PCs only while the program generation is unchanged.

DEF FN stores compiled expression code inside its line allocation, skipped by normal fall-through. Executing the definition activates its stable record. Calls save/restore the numeric parameter, with at most eight active calls on the guarded hardware stack. This is the implemented activation mechanism; a software function-activation stack is not present.

DATA cursors keep a line anchor and byte token offset and scan typed source fields through trailer links. RESTORE resets the cursor. READ converts values according to the destination and preserved field spelling.

## Native and error boundaries

Integer helpers use A/X for low/high bytes; A/X/Y and arithmetic flags are caller-clobbered unless a helper declares otherwise. Values and temporary string roots use the registered expression stack. Statement/continuation entries establish CURRENT_LINE context and poll for breaks. Decimal mode is clear at language boundaries. Native execution uses the RAM/I/O map; KERNAL calls use common-RAM gates.

RUN clears values/stacks/definitions/DATA state and refreshes the fixed runtime, then jumps to the first or requested anchor. It does not recompile valid lines. Errors return through common RAM to the command reporter, restore channels/stack baseline and invalidate continuation. LOAD uses staged publication and returns to READY rather than continuing the calling program. Detailed persistence invariants are in [source format](source_format.md).
