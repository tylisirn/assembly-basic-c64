# Host source tools

The Python tools exchange numbered Latin-1/PETSCII source and native `.AB` program files. Compilation occurs in the cartridge. Python 3.10 or newer is required; encoding, decoding and verification use only the standard library.

Run these commands from the repository root. Set `PYTHONPATH=host` on Linux/macOS, or install the package with `python3 -m pip install -e .` and use `ab64` directly.

```sh
PYTHONPATH=host python3 -m ab64 encode examples/hello.bas build/hello.ab
PYTHONPATH=host python3 -m ab64 decode build/hello.ab build/hello.bas
PYTHONPATH=host python3 -m ab64 verify build/hello.ab build/hello.ab
```

`encode` accepts decimal numbered lines in 0–63999. Blank lines are ignored; a bare line number deletes a previously supplied line of that number. It writes a native program container, ready to transfer to a C64 sequential file. `decode` emits a canonical listing. `verify` validates both containers and compares their canonical serialization, returning a nonzero exit status for differences or invalid files.

Text contains only BASIC source. Decoding and re-encoding a program loses binary editor metadata and blob contents; retain the `.AB` file or save individual `.BIN` files when those bytes are needed. The Python `ab64.container` API preserves binary sections through `dumps(*loads(data))` using its `ProgramLines`, `Reservation` and `Blob` objects. See the [file format specification](design/source_format.md).

## Instruction-level console

After [building the cartridge](implementation/README.md), install py65 1.2.0 or use the local bootstrap's copy:

```sh
PYTHONPATH=host:.tools/py65 python3 -m ab64 run examples/hello.bas
PYTHONPATH=host:.tools/py65 python3 -m ab64 repl
```

`run` accepts numbered text or an `.AB` file. `repl` opens a direct-command console. Both execute the assembled cartridge and its generated native code with deterministic KERNAL stubs. They provide instruction-level development tools; VIC timing, real IEC devices and a complete stock KERNAL require an emulator or C64.
