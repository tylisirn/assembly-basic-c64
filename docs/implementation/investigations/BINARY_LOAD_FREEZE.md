# VRASM.BIN disk-load freeze — 24 October 2026

The supplied VICE 2.4 snapshot confirms a stalled disk read. Its trigger remains
unresolved: fresh loads from the supplied disk image succeed in both VICE 2.4
and VICE 3.7.1. No firmware change is justified by the current evidence.

## Captured state

The CPU is at `$EE33` in the stock KERNAL serial receive routine; the screenshot
shows `$EE3A` in the same polling loop. This loop waits for serial clock activity
or the CIA1 timer-B end-of-information timeout. The selected ASM blob occupies
`$C000–$C108`, inclusive, with size `$0109` (265 bytes).

The transfer's next write address is `$C108` and its remaining count is one.
RAM at `$C000–$C107` matches the first 264 supplied file bytes exactly. The final
file byte is `$60`; it has not yet reached the blob. KERNAL status `$90` is zero,
so the loader has not received an EOF or error indication. It is still inside
CHRIN, before its own status and bounds checks can run. The captured cartridge
matches the build tested in this investigation byte for byte.

`debug/assembly-basic.d64` has a closed SEQ entry named `VRASM.BIN`. Its sector
chain is track 15/sector 1 followed by track 15/sector 11. The final sector link
is `(0,12)`, giving 254 + 11 = 265 payload bytes. Extracting the chain produces
exactly `debug/vrasm.bin`; neither an unexpected PRG header nor a truncated file
explains this capture.

## Checks performed

VICE 2.4 x64sc was run with the genuine 901227-03 C64 KERNAL, the 1541
325302-01/901229-05 drive ROM, true 1541 emulation, ROM traps disabled and the
original disk image attached. After fresh cartridge initialization, the captured
metadata, language scratch and editor state were restored, including the ASM
blob selection. The filename was supplied through the KERNAL keyboard queue,
and the editor's actual load entry called the banked transfer routine.

Ten successive loads each returned to `be_wait` in the binary editor with count
zero and next address `$C109`. All 265 loaded bytes were exported through the
monitor and compared with the supplied binary after every load; all ten matched.
A separate transfer using the original disk also completed in VICE 3.7.1.

These tests reproduce the selected blob and file transfer, but not the entire
sequence of actions before the freeze. The captured mid-transfer state also
retains serial, drive and timer state; replaying it is not equivalent to opening
the file again. An exploratory timer restart during snapshot replay produced
EOF plus a read timeout and did not establish a reliable recovery procedure.
The evidence does not establish an emulator defect or a firmware defect.

Checksums, exact inputs, test configuration and limitations are recorded in
[the validation record](binary-load-freeze-validation.json). Local monitor logs
are retained under `debug/load-freeze-investigation/`; the supplied binary,
snapshot and disk image were not modified. Firmware and packaged cartridges
remain unchanged.

## Next reproduction

Keep the original freeze snapshot. Hard-reset the C64, reload the program or
recreate its reservations/blobs, and retry the load from the original disk.
If the freeze returns, save another snapshot immediately **before** submitting
the filename as well as one after the freeze. The earlier snapshot should allow
the complete OPEN/CHKIN/read sequence to be replayed with the same preceding
machine state. Record any earlier RUN, SYS, OPEN/CMD, or monitor activity.

Do not use the captured blob as executable code yet: its final byte was not
loaded. A successful fresh load restores the complete 265-byte file.
