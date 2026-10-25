# Magic Desk cartridge architecture — revision 0.16

The cartridge is 64 KiB, divided into eight 8 KiB banks mapped at `$8000–$9FFF`. The CRT declares classic Magic Desk type 19, EXROM=0, GAME=1, with one CHIP packet per bank. The raw binary concatenates banks 0 through 7. The format follows the [VICE cartridge specification](https://vice-emu.sourceforge.io/vice_17.html); VICE 3.7.1 cartconv accepts it and reproduces the binary exactly. This is the classic C64 format, rather than Magic Desk 16K or Magic Desk 128.

| Bank | Current contents | Used / available bytes | Extension role |
| --- | --- | --- | --- |
| 0 | Autostart, command editor, tokenizer, LIST, source transport, gateway load image | 8,000 / 8,192 | Command dispatch and shared entry points |
| 1 | Raw resident compiler load image | 5,712 / 8,192 | Compiler and native emitter growth |
| 2 | Raw runtime load image and banked execution services | 7,213 / 8,192 | RAM helpers plus DATA, DEF FN activation and device/input services |
| 3 | Split screen editor, PRG importer and recovery header | 7,290 / 8,192 | Screen UI and stock BASIC PRG import; remaining space for PRG export |
| 4 | Binary/sprite editor UI and recovery header | 7,466 / 8,192 | Binary/sprite editor |
| 5 | Binary metadata, reservation and persistence services | 3,316 / 8,192 | Reservation and binary file services |
| 6 | Recovery header; otherwise erased | 9 / 8,192 | Numeric tables, fonts and optional resources |
| 7 | Recovery header; otherwise erased | 9 / 8,192 | Expansion and diagnostics |

The editor and stock BASIC PRG importer are implemented in bank 3. Banks 4/5 implement the binary/sprite UI and metadata services. The remaining reserved roles guide future allocation; they do not add their planned language features. Total linked ROM use is 39,015 bytes, leaving 26,521 bytes across the eight banks. Spare space in different banks is not interchangeable without changing placement or adding a bank call. In particular, the compiler's RAM reservation has only 441 unused bytes and the runtime's has 1,240; additional ROM capacity does not enlarge those reservations.

## Maps and bank ownership

Command execution uses `$01` low bits 7: bank 0 at `$8000`, stock BASIC ROM at `$A000`, I/O and KERNAL visible. BASIC ROM is visible but the language does not call its routines. Generated native code uses low bits 5: cartridge/BASIC/KERNAL hidden, I/O visible. This retains writable shadow RAM and the existing program arena. Writes beneath visible ROM reach underlying RAM.

The bank latch at `$DE00` is write-only. Firmware records its current bank at `$0BE3` (`CART_BANK`), outside user allocation. Every firmware bank selection updates both locations. Do not infer the latch from a read of `$DE00`. I/O must be visible when writing the latch. Native user code that selects a different bank must update the shadow too if it expects interrupted banked operations to resume that bank; SYS/USR normalize the bank to zero on return.

Command dispatch, source formatting and transport run in bank 0, the split screen UI runs in bank 3, and cold execution services run in bank 2. The editor calls existing command/compiler routines through bank_call and hooks KERNAL input/output through common RAM. All instructions that select another bank and their return paths execute from the common-RAM gateway at `$0800`. `copy_bank_image` uses the shared `bank_call` ABI with IRQs masked for the copy, restores the original bank, complete `$01` and flags, and consumes SOURCE/DEST/COUNT. Cold start copies the gateway and service entry stubs after KERNAL initialization, then bank 2's runtime to `$E400–$FFF9` and bank 1's compiler to `$1400–$2BFF`. RUN and CONT refresh only the RAM runtime image; bank-2 services execute directly from ROM. There is no decompressor or instruction relocation.

KERNAL and IRQ gateways preserve the interrupted bank, temporarily select bank 0 for ROM service/recovery paths and restore it before returning. NMI handling stays in common RAM and preserves the selected bank. READY, source transport and SYS/USR returns establish bank 0 after exposing I/O. The first nine bytes of every bank contain the CBM80 signature and cold/warm vectors; auxiliary-bank vectors reach common-RAM recovery helpers installed at boot. Hardware reset starts in bank 0.

Firmware keeps the cartridge enabled and hides ROM through `$01`; it never writes `$80` to disable the cartridge. Some [Magic Desk hardware variants](https://github.com/msolajic/c64-magic-desk-1024k) latch disable until hardware reset. User code must leave the cartridge enabled and preserve the gateway, runtime, compiler, vectors and language state.

## Common service entry stubs and remaining reservation

`$0334–$03FF` is a 204-byte firmware-owned common-RAM region, outside the user arena and BASIC `RESERVE` ranges. It now holds **152 bytes** of `SERVICE_GATEWAY` entry stubs, including the screen-output hook, followed by **52 bytes** of editor state at `$03CC–$03FF`. The main gateway holds **593 code bytes**, including the keyboard-input hook, and reserves `$0A60–$0AFF` for the **160-byte** editor draft. The cached row map uses `$0F80–$0FDF`, and the help snapshot tail uses `$0FE0–$0FFF`, above the existing 32 four-byte expression-stack entries. No user-arena bytes are added or removed. The linker restricts code to its own spans so it cannot overlap these buffers. The linker names the stub region `FUTURE`; `src/memory.inc` declares `FUTURE_RAM_START` and exclusive `FUTURE_RAM_END`.

| Range | Stock C64 use | Reclaimed bytes |
| --- | --- | --- |
| `$0334–$033B` | Unused | 8 |
| `$033C–$03FB` | Cassette buffer, reclaimed because tape transport is unsupported | 192 |
| `$03FC–$03FF` | Unused | 4 |

KERNAL CBM80 dispatch precedes `IOINIT`. Cold start must set mapping bits 0–2
in `$01` before making them outputs in `$00`: the reset data latch is zero,
and enabling its outputs first hides the executing cartridge and KERNAL.
See the [startup freeze investigation](VICE_STARTUP_FREEZE.md).

Cold start installs the stubs after KERNAL initialization: `RAMTAS` clears all of page 3. Preserve KERNAL vectors through `$0333` and keep tape transport unsupported while its buffer is repurposed. User machine code must preserve this firmware-owned range. The stock [KERNAL declarations](https://github.com/mist64/c64rom/blob/master/kernal/declare.s) identify the cassette buffer; the [initialization source](https://github.com/mist64/c64rom/blob/master/kernal/init.s) records page-3 clearing.

## Banked-service call ABI

Runtime ABI **7** adds `bank_call`, a common-RAM call gate. A call contains four inline descriptor bytes immediately after its JSR:

```asm
jsr bank_call
.byte BANK_SERVICES,7 ; bank 0..7, or $ff to retain the current bank; port low bits 5 or 7
.word rom_read_number ; little-endian target address
; execution resumes here
```

Arguments are A/X/Y and the service's documented common-RAM state. The gate reads the descriptor in the caller's original mapping, advances the return PC over the descriptor, and saves the complete `$01`, software bank shadow and caller flags on that call's hardware-stack frame. Setup and return mask IRQs; the callee receives the caller's interrupt mask with decimal mode clear. Each active call adds five stack bytes compared with an ordinary JSR, plus service/helper locals. Arguments and results do not depend on a shared saved frame.

The result is A/X/Y and the callee's N/Z/C/V flags. Return restores the original bank, complete `$01` and caller interrupt mask, and clears decimal mode. The target and return addresses are stacked before IRQs are reenabled, so nested ROM calls, RAM callbacks and KERNAL calls can reuse dispatch scratch safely. The NMI handler records pending aborts without calling services or changing dispatch scratch. No ROM instruction switches banks or hides its own continuation.

The gate clobbers IO_A, IO_X, IO_Y, IO_STATUS, IO_MAP, GATE_FLAGS and its dispatch staging bytes; it does not borrow the language's indirect pointers. Each service documents or follows its existing helper-state clobbers. Descriptor bytes must be visible in the caller's mapping and use the valid bank/map values above. Descriptor and return-address arithmetic is binary even when a SYS caller arrives with decimal mode set.

`kernal_gate`, `call_ram`, `file_entry` and `copy_bank_image` use this ABI; image copying additionally keeps IRQs masked and restores the original flags. SYS/USR retain their dedicated register/return contracts and normalize bank 0 plus the execution mapping. The small `read_ram` accessor remains a direct common-RAM byte reader to avoid full dispatch overhead during source scans.

The migrated bank-2 services implement DATA traversal, READ conversions, RESTORE, DEF FN definition activation, file-operation staging, OPEN/CLOSE/channel selection, INPUT prompting/field acquisition and GET conversion. Shadow source, filenames and definition operands are read through `read_ram`; writes reach underlying RAM. Shared number/string/stack helpers are reached through `RAM_CALL` descriptors with bank `$ff`, map 5. Allocator/collector, expression/control state and hot DEF FN calls remain in RAM. The activation stub consumes the original native return address before dispatch, preserving the compiler's four inline definition operands; it resumes the native skip jump only after restoring the RAM mapping.

Nonreturning errors enter the existing RAM error/READY path, establish bank 0 and reset the hardware stack. LOAD retains its existing return-to-READY behavior. Normal blocking input leaves IRQs enabled and restores each bank frame after the KERNAL service returns.

| Component | Used / reserved bytes |
| --- | --- |
| High RAM runtime at `$E400` | 5,922 / 7,162 |
| Common gateway at `$0800` | 593 code + 160 text / 768 |
| Service entry stubs at `$0334` | 152 code + 52 state / 204 |
| Bank-2 ROM services | 1,282 / bank's remaining ROM |

The ABI 7 service migration shrank the high runtime by **1,115 bytes**, increasing its headroom from 125 to **1,240 bytes**. Relative to the earlier runtime, the gateway and stubs now occupy 55 and 152 additional bytes respectively, so resident firmware code in RAM remains **908 bytes** smaller. The editor also uses 212 bytes of buffers in existing firmware reservations. Existing RAM reservations and the 43,008-byte arena retain their bounds; this change creates implementation headroom rather than adding user-arena bytes.

Bank 2 has 979 ROM bytes free with both images present. Filling all 1,240 bytes of runtime RAM headroom would require shifting some ROM services to another bank; the descriptor ABI already supports that placement change.

## Future banked routines

The call ABI now supports moving additional cold helpers to ROM. Each migration must declare arguments, results, shadow reads, RAM callbacks, error behavior and stack use. Keep the allocator, collection, active control state and native return addresses in stable RAM. ROM helpers must enter common RAM before selecting a different bank.

Moving compiler work out of `$1400–$2BFF` could recover RAM, but requires auditing its calls into bank 0 and scratch ownership. Adding fixed-point values changes cell/array/expression layouts and arithmetic semantics; publish a new ABI and recompile all source then. Existing version-one `.AB` source files remain authoritative; stock PRG import is implemented and export is still planned. The editor uses bank 3; planned PRG export routines can share its spare space, planned numeric/PRINT and hardware extensions can use banks 6/7, while execution helpers are placed deliberately in RAM or reached through defined bank gates.

Runtime ABI is now **7** because helper entry addresses and the banked-service contract changed. Source-only containers remain **1**; binary metadata uses **2**. Both load. Hard-reset with the new cartridge and reload/reenter source; old snapshots contain the earlier ROM, gateways and compiled helper references.

## Validation

Automated tests cover nested ROM/RAM/KERNAL service calls, IRQ/NMI injection at nested transition boundaries, blocking input, shadow DATA/DEF FN operands, page-3 stub installation, eight-bank CRT parsing, latch mirrors and PLA visibility, exact startup copies, bank/port/flag restoration, IRQ and NMI frames during banked work, KERNAL calls, SYS/USR map changes and auxiliary-bank warm recovery. The complete existing language suite also runs, including Void Runner gameplay and collection replay. The py65 harness uses deterministic KERNAL stubs; independent cartridge tests validate the current eight-bank CRT format. Earlier cartconv and user-reported VICE disk-load/gameplay validation applied to the revision 0.6 Magic Desk conversion. The editor has additional software integration checks with actual 901227-03 KERNAL initialization, keyboard, input and output instructions. Keyboard bytes and raster status are injected in py65; this adds no VIC/IEC timing evidence. Fresh VICE/genuine-ROM gameplay remains open. Visible collection pauses remain a performance backlog item. Broader genuine-ROM/cycle-accurate acceptance and physical-machine execution remain release work. See [the validation record](IMPLEMENTATION_STATUS.md).
