# Magic Desk cartridge architecture — revision 0.9

The cartridge is 64 KiB, divided into eight 8 KiB banks mapped at `$8000–$9FFF`. The CRT declares classic Magic Desk type 19, EXROM=0, GAME=1, with one CHIP packet per bank. The raw binary concatenates banks 0 through 7. The format follows the [VICE cartridge specification](https://vice-emu.sourceforge.io/vice_17.html); VICE 3.7.1 cartconv accepts it and reproduces the binary exactly. This is the classic C64 format, rather than Magic Desk 16K or Magic Desk 128.

| Bank | Current contents | Used / available bytes | Extension role |
| --- | --- | --- | --- |
| 0 | Autostart, command editor, tokenizer, LIST, source transport, gateway load image | 7,302 / 8,192 | Command dispatch and shared entry points |
| 1 | Raw resident compiler load image | 6,057 / 8,192 | Compiler and native emitter growth |
| 2 | Raw RAM execution runtime load image | 7,011 / 8,192 | Existing integer/string/array/control helpers |
| 3 | Recovery header; otherwise erased | 9 / 8,192 | Improved editor and stock BASIC PRG import/export |
| 4 | Recovery header; otherwise erased | 9 / 8,192 | 16.8 fixed-point helpers and improved PRINT |
| 5 | Recovery header; otherwise erased | 9 / 8,192 | Sprite, VIC and SID commands |
| 6 | Recovery header; otherwise erased | 9 / 8,192 | Numeric tables, fonts and optional resources |
| 7 | Recovery header; otherwise erased | 9 / 8,192 | Expansion and diagnostics |

The reserved roles guide future allocation; they do not add new language features in this revision. Total linked ROM use is 20,415 bytes, leaving 45,121 bytes across the eight banks. Spare space in different banks is not interchangeable without changing placement or adding a bank call. In particular, the compiler's RAM reservation has only 96 unused bytes and the runtime's has 160; additional ROM capacity does not enlarge those reservations.

## Maps and bank ownership

Command execution uses `$01` low bits 7: bank 0 at `$8000`, stock BASIC ROM at `$A000`, I/O and KERNAL visible. BASIC ROM is visible but the language does not call its routines. Generated native code uses low bits 5: cartridge/BASIC/KERNAL hidden, I/O visible. This retains writable shadow RAM and the existing program arena. Writes beneath visible ROM reach underlying RAM.

The bank latch at `$DE00` is write-only. Firmware records its current bank at `$0BE3` (`CART_BANK`), outside user allocation. Every firmware bank selection updates both locations. Do not infer the latch from a read of `$DE00`. I/O must be visible when writing the latch. Native user code that selects a different bank must update the shadow too if it expects interrupted banked operations to resume that bank; SYS/USR normalize the bank to zero on return.

Ordinary ROM calls stay in bank 0. All instructions that select another bank and their return paths execute from the common-RAM gateway at `$0800`. `copy_bank_image` masks IRQs, exposes I/O and ROML, selects its source bank, copies a raw fixed-address image, restores the original bank and complete `$01`, and restores interrupt flags. It consumes SOURCE/DEST/COUNT. Cold start copies bank 2's runtime to `$E400–$FFF9` and bank 1's compiler to `$1400–$2BFF`. RUN and CONT refresh the runtime from bank 2 before executing native code. There is no decompressor or instruction relocation.

KERNAL and IRQ gateways preserve the interrupted bank, temporarily select bank 0 for ROM service/recovery paths and restore it before returning. NMI handling stays in common RAM and preserves the selected bank. READY, source transport and SYS/USR returns establish bank 0 after exposing I/O. The first nine bytes of every bank contain the CBM80 signature and cold/warm vectors; auxiliary-bank vectors reach common-RAM recovery helpers installed at boot. Hardware reset starts in bank 0.

Firmware keeps the cartridge enabled and hides ROM through `$01`; it never writes `$80` to disable the cartridge. Some [Magic Desk hardware variants](https://github.com/msolajic/c64-magic-desk-1024k) latch disable until hardware reset. User code must leave the cartridge enabled and preserve the gateway, runtime, compiler, vectors and language state.

## Future banked routines

The current banking primitive copies images; it is not a general cross-bank function-call ABI. Before moving compiler or execution helpers to ROM, add explicit common-RAM call/return gates, argument/result conventions, nested bank restoration and interrupt tests. Keep the allocator, collection, active control state and native return addresses in stable RAM. A ROM-bank routine must never select another bank while executing instructions in `$8000–$9FFF`.

Moving compiler work out of `$1400–$2BFF` could recover RAM, but requires auditing its calls into bank 0 and scratch ownership. Adding fixed-point values changes cell/array/expression layouts and arithmetic semantics; publish a new ABI and recompile all source then. Existing version-one `.AB` source files remain authoritative; stock PRG conversion is still planned. Editor/PRG routines can use bank 3, numeric/PRINT routines bank 4 and hardware command compilation tables bank 5, while execution helpers are placed deliberately in RAM or reached through defined bank gates.

Runtime ABI is now **5** because numeric expression/array typing and runtime helper addresses changed. Source/container version remains **1**, and revision 0.7 adds unsigned `%` words and a typed, program-safe FRE() result to the existing language. Hard-reset with the new cartridge and reload/reenter source; old snapshots contain the previous ROM, gateway and compiled helper references.

## Validation

Automated tests cover eight-bank CRT parsing, latch mirrors and PLA visibility, exact startup copies, bank/port/flag restoration, IRQ and NMI frames during banked work, KERNAL calls, SYS/USR map changes and auxiliary-bank warm recovery. The complete existing language suite also runs, including Void Runner gameplay and collection replay. The py65 harness uses deterministic KERNAL stubs; cartconv validation checks the file format. The user reports successful disk loading and gameplay of Void Runner in VICE after this conversion. Visible collection pauses remain a performance backlog item. Broader genuine-ROM/cycle-accurate acceptance and physical-machine execution remain release work. See [the validation record](IMPLEMENTATION_STATUS.md).
