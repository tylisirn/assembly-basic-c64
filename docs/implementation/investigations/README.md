# Debugging investigations

These records retain captured machine state, tested ROM fingerprints, reproduction steps and before/after evidence. Their dates, emulator versions and old/fixed comparisons identify the experiments; they do not impose migration steps on first-release users. Current behavior is summarized in [implementation status](../STATUS.md).

- [Startup mapping freeze](VICE_STARTUP_FREEZE.md), with [validation data](vice-startup-validation.json): CPU-port initialization order and genuine-ROM VICE smoke checks.
- [Silent SAVE failure](SAVE_FAILURE.md): transport/final DOS errors and recovered source/blob backup.
- [Void Runner collection pause](VOIDRUNNER_FREEZE.md), with [replay measurements](../voidrunner-collection.json): captured heap, collector cost and remaining latency.
- [Binary disk-load stall](BINARY_LOAD_FREEZE.md), with [validation data](binary-load-freeze-validation.json): unresolved snapshot stall and successful fresh transfers.

Paths under `debug/` refer to local, ignored inputs/logs and may not exist in a fresh checkout. Keep the recorded checksums and test conditions when extending an investigation.
