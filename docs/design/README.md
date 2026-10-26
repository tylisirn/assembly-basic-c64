# Design documentation

These documents describe the current implementation. Proposed extensions and validation gaps belong in the [implementation status](../implementation/STATUS.md); they are not language guarantees.

- [Architecture](architecture.md): compilation, memory ownership, line representation, bindings, control flow and collection.
- [Banking and service contracts](banking.md): cartridge organization, startup, mapping and calls across ROM/RAM/KERNAL boundaries.
- [Integer arithmetic](integer_arithmetic.md): signedness, literal context, evaluation and wrapping.
- [Source and file formats](source_format.md): token vocabulary, native containers, validation and PRG import.
- [Editors](editors.md): UI state, memory reservations, binary blobs and persistence contracts.

The [Word document](Assembly_BASIC_C64_Design.docx) and [plain-text export](Assembly_BASIC_C64_Design.txt) are generated from these Markdown specifications plus the measured linked build. Edit Markdown and run `python3 tools/update_design.py`; the [development guide](../implementation/README.md#documentation-and-packaging) describes the required build/test inputs. The generated copies contain the same current design, without a separate revision history.

For programming syntax and compatibility limits, use the [language reference](../LANGUAGE_REFERENCE.md).
