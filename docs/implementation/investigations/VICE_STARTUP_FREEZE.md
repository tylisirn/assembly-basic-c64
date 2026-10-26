# Cartridge startup freeze — 25 October 2026

The startup failure reported with GTK3VICE-3.10-win64 is caused by the
cartridge's CPU-port initialization order. The corrected cartridge is
`dist/assembly-basic.crt`. Attach it and power-cycle the emulated C64. Restoring
`debug/vice-3.10-freeze.vsf` restores its original faulty cartridge as well.

## Captured evidence and cause

The supplied snapshot contains the same 64 KiB ROM as the previous build, SHA-256
`d9b781054f3e3079857bb0d8cca5914044b2c24a96963a05de5e2d9b5ef4f912`.
Its CPU is at `$0008`, with stack pointer `$16`, CPU-port direction `$07` and
data latch `$00`. The screen and firmware RAM images still contain power-on
patterns. Startup has failed before KERNAL initialization and image copying.

KERNAL checks the CBM80 signature and jumps through `$8000` before calling
`IOINIT`. At reset, both the 6510 port's direction register and data latch are
zero. Pull-ups on the input pins keep LORAM, HIRAM and CHAREN high, exposing
the cartridge, KERNAL and I/O. These reset semantics are explicit in
[VICE's CPU-port implementation](https://github.com/VICE-Team/svn-mirror/blob/main/vice/src/c64/c64pla.c);
the [stock KERNAL reset sequence](https://github.com/mist64/c64rom/blob/master/kernal/init.s)
dispatches the cartridge before initialization.

The old cartridge enables output bits 0–2 by writing `$07` to `$00` at
`$8012`, while the data latch is still zero. All three mapping signals become
low. At the next instruction, `$8014`, ROML and KERNAL are hidden and the CPU
fetches uninitialized RAM. The subsequent stray instructions and BRK loop
account for the frozen display. This does not depend on PAL/NTSC timing or the
selected VIC model, and it also reproduces in VICE 3.7.1.

## Correction and regression coverage

Cold start now updates `$01` first, then enables the direction bits in `$00`.
Both updates preserve the upper bits. The remainder of initialization, ROM
size, RAM layout and runtime ABI 7 retain their existing contracts.

The instruction harness now derives the three mapping signals from both the
data latch and direction register, with input pull-ups. Previously it modeled
only the data latch and started with initialized port values, missing this
failure. Two banking regressions cover the reset mapping, cartridge/I/O
visibility when outputs are enabled, and a complete cold boot plus `PRINT 7`
from zeroed port registers. The original snapshot ROM fails that boot case;
the patched ROM passes.

## Emulator validation

Linux x64sc **VICE 3.7.1**, using actual C64 ROMs, reproduces the original
cartridge's mapping failure at `$8014` and passes the corrected startup on:

| Configuration | VICE model | Patched result |
| --- | --- | --- |
| C64 old PAL, KERNAL revision 2 | `c64old` | Banner, READY, `PRINT 7`, READY |
| C64 PAL, KERNAL revision 3 | `c64` | Banner, READY, `PRINT 7`, READY |
| C64C PAL, KERNAL revision 3 | `c64c` | Banner, READY, `PRINT 7`, READY |
| C64 NTSC, KERNAL revision 3 | `ntsc` | Banner, READY, `PRINT 7`, READY |

The smoke checks start through the normal KERNAL reset vector, without
initializing the CPU port from the monitor. Only the command's keyboard bytes
are injected into the KERNAL buffer after READY. The
[machine-readable record](vice-startup-validation.json) identifies the
snapshot and both ROMs; detailed logs remain in `debug/vice-startup/`.
The existing genuine-KERNAL editor and binary-editor integration checks also
pass with the patched cartridge.

GTK3VICE **3.10 on Windows has not been executed in this environment**;
the supplied 3.10 snapshot and local 3.10 source establish the same reset
condition. Retest the rebuilt CRT in that installation after a power cycle.
Physical-machine validation remains open.
