# Silent SAVE failure — 25 October 2026

`SAVE "VOID4.AB",8` returned to READY while the drive error light blinked and no
file appeared. `debug/save-fail.vsf` contains the complete program and the same
cartridge as the investigated revision 0.16 build.

## Cause and captured evidence

The 1541 RAM contains `74,DRIVE NOT READY,18,00`; the C64 KERNAL status at `$90`
is `$80`, indicating device-not-present during serial communication. The staged
filename is correctly `VOID4.AB,S,W`. The snapshot does not establish why the
emulated drive could not read its disk at track 18, sector 0. A temporary copy
of the supplied `assembly-basic.d64` accepts the same save after fresh device
initialization, so the filename and program are not the cause.

The cartridge's source SAVE path checked OPEN/CHKOUT carry, but ignored write
status and returned without reading DOS status after CLOSE. Serial errors can
be recorded in `$90` without setting carry, and DOS can reject an otherwise
accepted stream. Consequently READY alone was not evidence of a saved file.

## Firmware correction

- Check OPEN, CHKOUT, every output byte and data-channel CLOSE for transport
  failure, and report `?DEVICE ERROR` instead of silently continuing.
- After closing a saved file, read a bounded, complete DOS status response and
  require success code `00`. This also detects file-exists, write-protected and
  disk-full errors that need not appear as transport failures.
- Query status using TALK/TKSA/ACPTR/UNTALK on secondary 15. This uses no extra
  logical file and sends no CLOSE-15 command that could close other user files.
  These are the stock [KERNAL serial routines](https://github.com/mist64/c64rom/blob/master/kernal/serial4.0.s).
- Free the temporary dense-name map and restore channels on a failed save.
  Program source and binary contents remain available to retry.

No replacement command or automatic overwrite was introduced. A partial or
unclosed file can remain after a failed physical write; a reported failure
must not be treated as a complete backup.

## Validation and recovered program

The original cartridge was extracted from the supplied snapshot. With the
snapshot's program graph, reservations and binary data restored after fresh
cartridge initialization, VICE 2.4 with true 1541 emulation and no mounted disk
reproduced the original READY-only result and `$90=$80`. The patched cartridge
reports `?DEVICE ERROR` for the same condition.

With a temporary copy of the original disk attached, the recovered program
saved as a closed SEQ file named `VOID4.AB`. Its 5,671-byte source container
passes host format/CRC validation and contains 213 lines, two reservations and
seven blobs. Each blob's data matches its captured RAM bytes exactly. Its
SHA-256 is `dd88f1c46e23d532050e0b9d5efcd29376318a0975d958b72c0197458eb608f7`.
The target also recompiles this backup on LOAD, restores all seven blobs, and
reproduces exactly the same file on SAVE. Genuine-KERNAL editor and binary
editor integration checks pass with the corrected firmware.

The standalone file and a separate disk image containing it are retained at:

- `debug/save-recovery/void4.ab`
- `debug/save-recovery/assembly-basic-recovered.d64`

The supplied snapshot and original disk image were not modified. Regression
tests in `tests/test_save_errors.py` cover transport failures at OPEN, channel
selection, first/later writes and CLOSE; DOS errors; malformed, absent and
truncated status responses; bus cleanup; retry; and source preservation.

Use the rebuilt cartridge after a hard reset. Restoring the old snapshot also
restores its old cartridge and RAM helpers. Reattach a readable, writable disk
image to drive 8 before retrying SAVE. The recovered `.AB` can be loaded directly
from the separate recovery disk image.
