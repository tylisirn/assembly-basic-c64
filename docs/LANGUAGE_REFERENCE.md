# Assembly BASIC language reference

This reference describes the implemented language for programmers familiar with Commodore 64 BASIC V2. [Editor controls](SCREEN_EDITOR.md), [sprite/binary editing](BINARY_EDITOR.md), [PRG conversion](PRG_IMPORT.md) and [host tools](HOST_TOOLS.md) have separate guides.

## Source, names and values

Programs contain decimal numbered lines in 0–63999. Separate statements with `:`. Entering an existing line number replaces it; entering the number alone deletes it. Direct statements run immediately. Numbered edits clear variable values and suspended execution. A compilation error can leave the submitted line stored for `LIST` and repair; an allocation failure preserves its previous contents.

Identifiers start with a letter, continue with letters or digits, and optionally end with `%` or `$`. Every character is significant; comparison is case insensitive. `SCORE` and `SCORETOTAL` are distinct, as are `A`, `A%` and `A$`. Scalars and arrays with the same spelling have separate storage. Unassigned numeric values are zero and strings are empty.

The lexer recognizes whole keywords. Write `PRINT A`, `GOTO 30`, `DEF FN DOUBLE(X)=X*2` and `FN DOUBLE(3)`; `PRINTA` and `GOTO30` are identifiers. `?` abbreviates `PRINT`; standalone shifted-letter keyword abbreviations are accepted. `PRINT#`, `INPUT#`, `GET#`, `TAB(` and `SPC(` retain their punctuation forms. Spaces before function parentheses are allowed. The host tokenizer additionally accepts period abbreviations.

| Form | Meaning |
| --- | --- |
| `TOTAL` | Signed 16-bit integer, -32768–32767 |
| `TOTAL%` | Unsigned 16-bit integer, 0–65535 |
| `NAME$` | PETSCII string, up to 255 bytes |
| `123`, `$D000` | Decimal or hexadecimal word literal, magnitude 0–65535 |
| `-123`, `-$000D` | Unary minus applied to a literal; a signed negative literal |
| `"HELLO"` | String literal; use `CHR$(34)` to construct a quote byte |

Array elements, function parameters and function results use the type indicated by their name. There are no floating-point or fixed-point types. Fractional and scientific notation are unsupported. A literal magnitude above 65535 is rejected rather than wrapped. Hexadecimal values keep their radix in listings and appear with four digits, such as `$000D`.

Outside strings, comments and DATA fields, `LIST` normalizes spacing and spelling: `?a+0001` becomes `PRINT A + 1`. Function and array parentheses are compact: `MID$(S$, 1, 2)`. String/comment bytes and significant DATA spelling are retained.

## Integer evaluation

Arithmetic retains the low 16 bits after every operation. Assignment and numeric parameter/result passing preserve the word; the destination supplies its interpretation. Evaluating an expression never takes its type from the destination.

- Nonnegative literals, including zero, are unsigned. Negative literals are signed.
- A naked literal directly combined with a typed expression adopts that type if representable. An already computed subexpression retains its own type.
- Two unsigned operands produce unsigned arithmetic. Any mixed signed/unsigned operation uses signed interpretation of both words and produces a signed result.
- Comparisons produce signed `-1` for true and `0` for false. String comparisons use PETSCII byte ordering.
- Signed division truncates toward zero. Division by zero is an error. `-32768/-1` wraps to -32768.
- Unary `NOT` and negation of a computed value preserve its numeric type. A negative literal is signed: `-4` is -4, while `-(2+2)` is unsigned 65532.

```basic
PRINT 20000+20000       : REM 40000
A=20000+20000:PRINT A   : REM -25536
U%=65535:S=U%:PRINT S   : REM -1
PRINT 4-5;(4-5)/2       : REM 65535 AND 32767
D=2:PRINT U%/2;U%/D     : REM 32767 AND 0
```

The [integer design specification](design/integer_arithmetic.md) gives the complete local typing rules and boundary examples.

## Operators and precedence

Precedence is highest first. Operators at a shared level associate left to right, including exponentiation: `2^3^2` is 64.

| Level | Operators | Behavior |
| --- | --- | --- |
| 1 | `^` | Integer exponentiation; a negative exponent is an illegal quantity; `0^0` is 1 |
| 2 | Unary `+`, `-` | Power binds first, so `-2^2` is -4 |
| 3 | `*`, `/` | Wrapping multiplication and integer division |
| 4 | `+`, `-` | Wrapping addition/subtraction; `+` also concatenates two strings |
| 5 | `<<`, `>>` | Wrapping left shift and arithmetic right shift |
| 6 | `=`, `<>`, `<`, `>`, `<=`, `>=` | Numeric or string comparison |
| 7 | `NOT` | Bitwise complement |
| 8 | `AND` | Bitwise AND |
| 9 | `OR` | Bitwise OR |

Parentheses group expressions. Logical operands are evaluated eagerly. Shift counts must be 0–255; a count of 16 or more yields zero for a left shift and sign fill for a right shift. `>>` preserves bit 15 even on unsigned words: `$FFFF>>1` is unsigned 65535. Division and shifting differ for negative odd values: `-5/2` is -2; `-5>>1` is -3.

## Program and editor commands

| Syntax | Behavior |
| --- | --- |
| `RUN [line]` | Clear values, arrays, active function definitions, DATA position and suspended control state; execute from the beginning or the exact requested line |
| `LIST [line]` | List all source, or one line; RUN/STOP interrupts the listing |
| `LIST low-high` | List an inclusive range; either endpoint can be omitted; reversed bounds list nothing |
| `NEW` | Delete the program, values, binary metadata and reservations |
| `CLR` | Clear values, array allocations, function activation and execution state while keeping source and reservations |
| `CONT` | Resume a saved program continuation with its values and control frames |
| `CLEAN` | Rebuild source storage and bindings, clearing values and `CONT`; requires temporary free memory; direct mode only |
| `BASIC` | Open the split screen source editor; direct mode only |
| `SPRDEF` | Open the binary/sprite editor; direct mode only |
| `QUIT` | Close the source editor |

`RUN`, `LIST`, `NEW` and `CONT` are direct commands. `STOP`, `END` and a safe program RUN/STOP break preserve a continuation; `END` omits the BREAK message. Program edits, `NEW`, `LOAD`, `CLR`, `CLEAN`, a runtime error or an NMI abort invalidate it. Blocking input/device operations may abort without a resumable continuation. Direct commands cannot consume a suspended program's `FOR` or `GOSUB` frames.

## Statements and control flow

| Syntax | Behavior |
| --- | --- |
| `[LET] variable=expression` | Assign to a scalar or array element; preserve the word for numeric destinations |
| `IF condition THEN statements [ELSE statements]` | Choose an arm for the rest of the physical line; zero is false; `ELSE` binds to the nearest unmatched `IF` |
| `IF condition THEN line [ELSE line]` | Use literal decimal line targets as either arm; `IF condition GOTO line` is also accepted |
| `GOTO line` | Jump to a literal decimal line number |
| `GOSUB line` / `RETURN` | Call a numbered subroutine and return to the following statement |
| `ON selector GOTO line,...` | Select a target using 1-based indexing; zero or a selector above the list falls through |
| `ON selector GOSUB line,...` | Select a subroutine using the same rule; selector must be 0–255 |
| `FOR variable=start TO limit [STEP step]` | Initialize a numeric scalar loop; evaluate start, limit and step once; default step is 1 |
| `NEXT [variable[,variable...]]` | Advance the active loop(s); unsigned loops detect wrap/underflow at 65535/0 |
| `STOP` / `END` | Stop execution with a saved continuation |
| `REM text` | Preserve the remainder of the physical line as a comment |

`FOR` executes its body once before the first `NEXT` test, even when its initial value is beyond the limit. The loop variable's declared signedness determines limit comparison; STEP supplies a signed direction. STEP zero and signed boundary wrap can produce nonterminating loops. `NEXT` and `RETURN` use dynamic control frames. Line targets are decimal numbers in 0–63999; computed targets are unsupported. Native source uses `GOTO`; the stock `GO TO` spelling is supported only by PRG import.

```basic
10 FOR COUNT%=1 TO 3
20 IF COUNT%=2 THEN PRINT "TWO" ELSE PRINT COUNT%
30 NEXT COUNT%
40 END
```

## Arrays, DATA and user functions

| Syntax | Behavior |
| --- | --- |
| `DIM A(upper,...),S$(upper,...)` | Allocate numeric/string arrays with zero-based, inclusive bounds; up to eight dimensions |
| `DATA field,...` | Store numeric, quoted or unquoted fields; performs no work when execution passes it |
| `READ variable,...` | Consume DATA into scalars or array elements in program order |
| `RESTORE` | Reset DATA reading to the beginning of the program |
| `DEF FN name(parameter)=expression` | Activate a compiled numeric function with one numeric scalar parameter |
| `FN name(argument)` | Call an activated function; preserve the parameter's previous value |

Array subscripts and bounds must be nonnegative and fit available memory. An undimensioned array gets an upper bound of 10 in each used dimension. Redimensioning is an error. Scalars and arrays of the same name remain separate.

Numeric DATA follows the word rules. String READ preserves numeric field spelling, so `DATA 001,$D000` followed by `READ A$,B$` gives `"001"` and `"$D000"`. Unsupported numeric DATA can be retained as text and read into a string; using it numerically raises an error. `RESTORE line` is unsupported.

A function's name declares its result type and its parameter declares its argument type. Its definition must execute before a call. Recursion is bounded to eight active calls. String parameters/results and multiple parameters are unsupported. Use a separator between `FN` and the full function name.

```basic
10 DIM VALUES%(2):DATA 001,$FFFF
20 READ LABEL$,VALUES%(1)
30 DEF FN HALF%(VALUE%)=VALUE%/2
40 PRINT LABEL$;FN HALF%(VALUES%(1))
```

## Numeric functions and special variables

| Form | Result and limits |
| --- | --- |
| `ABS(n)` | Absolute value preserving the operand type; signed `ABS(-32768)` wraps to -32768 |
| `SGN(n)` | Signed -1/0/1; an unsigned nonzero operand gives 1 |
| `INT(n)` | The unchanged integer, preserving its type |
| `RND(n)` | Signed random word, -32768–32767; positive advances, zero repeats, negative reseeds reproducibly |
| `FRE()` / `FRE(n)` | Garbage collect/coalesce and return an unsigned total free-byte count; optional numeric expression is evaluated and ignored |
| `PEEK(address)` | Read a byte at an unsigned 16-bit address; result is signed 0–255 |
| `POS(n)` | Signed current output cursor column; numeric argument is evaluated and ignored |
| `USR(n)` | Call the vector at `$0311–$0312` with the integer in A/X (low/high); return a signed word from A/X |
| `ST` | KERNAL device status byte, read only |
| `TI` | Signed low 16 bits of the KERNAL jiffy clock, read only |
| `TI$` | Six-digit `HHMMSS` clock string; assign a valid time string to set the clock |

`RND` seeds its first positive call from the jiffy clock. `RND(0)` before any generation returns zero. An unsigned nonzero argument counts as positive. The generator advances by `(25173*state+13849) mod 65536`. It returns word values instead of stock BASIC's fractional result.

`FRE` preserves live values, arrays, source, reservations and a suspended continuation. Its result includes free-block headers and sums all free blocks; fragmentation can prevent an allocation smaller than that total. `CLEAN` performs a separate rebuild that clears values.

## Strings and conversion

Strings contain up to 255 PETSCII bytes, including embedded zero bytes at runtime. Concatenation beyond 255 bytes raises `STRING TOO LONG`.

| Form | Behavior |
| --- | --- |
| `LEN(s$)` | Signed byte length |
| `LEFT$(s$,count)` | Leftmost bytes; count 0–255, clipped to the string's length |
| `RIGHT$(s$,count)` | Rightmost bytes with the same bounds |
| `MID$(s$,start[,count])` | Substring from 1-based start 1–255; optional count 0–255; a start beyond the string returns empty |
| `ASC(s$)` | Signed PETSCII value of the first byte; empty string is an error |
| `CHR$(n)` | One-byte string; argument must be 0–255 |
| `STR$(n)` | Decimal representation using the expression's signedness and BASIC positive-number padding |
| `VAL(s$)` | Signed word parsed from an optional sign and decimal or `$`-prefixed hexadecimal magnitude |

`VAL` accepts leading spaces and integer magnitudes up to 65535. Decimal fractions/scientific notation and oversized magnitudes raise an error; there is no floating-point conversion. A parsed word above 32767 is returned with signed interpretation. There is no `MID$` assignment form.

## Screen and device I/O

| Syntax | Behavior |
| --- | --- |
| `PRINT [expression[;expression...]]` | Output values; `;` joins items, `,` advances print zones; trailing separators suppress the newline |
| `TAB(column)` / `SPC(count)` | PRINT formatting, with byte arguments 0–255 |
| `INPUT variable,...` | Read comma-delimited keyboard input into scalar numeric/string targets |
| `GET variable,...` | Read individual characters into scalar targets without waiting |
| `OPEN logical[,device[,secondary[,filename]]]` | Open a KERNAL channel; logical/device/secondary values are checked bytes |
| `CLOSE logical` | Close a logical file |
| `PRINT# logical,...` | Output to an open logical file |
| `INPUT# logical,variable,...` | Read fields from a logical file into scalar targets |
| `GET# logical,variable,...` | Read individual characters from a logical file |
| `CMD logical[,expression...]` | Select an output channel and optionally print to it |

Keyboard INPUT prints `? `. Numeric INPUT uses integer conversion. GET into a numeric target accepts a decimal digit, returns zero for no character, and rejects other characters. Custom `INPUT "PROMPT";A`, array targets for INPUT/GET, and complete stock BASIC retry/missing/extra-field behavior are unsupported. Use `PRINT` for custom prompts and `READ` for DATA array targets.

`OPEN` defaults to device 1 when omitted, which is unsupported; supply a supported device explicitly, for example `OPEN 2,8,2,"DATA,S,W"`. Tape (device 1) and RS-232 (device 2) transports are unavailable. Real device behavior depends on the KERNAL and attached device; inspect `ST` as appropriate.

## Program files

```basic
SAVE "PROGRAM.AB",8
LOAD "PROGRAM.AB",8
VERIFY "PROGRAM.AB",8
```

Each command accepts `filename[,device[,secondary]]`. Device defaults to 8. The optional secondary is evaluated once and checked as a byte; it does not choose a load address or change the native sequential format. Malformed argument lists are rejected before opening a file.

`SAVE` writes source, reservations, binary editor metadata and the exact contents of each blob. Variables, native compiled code and unassigned reservation bytes are not saved. It reports `DEVICE ERROR` for transport errors and unsuccessful final DOS status, including file-exists, disk-full and write-protect errors. Existing files are not overwritten automatically.

`LOAD` recognizes native `.AB` files and stock BASIC V2 PRGs from their contents. Source is compiled on the cartridge. Loading replaces the program and returns to `READY.`, including a LOAD executed inside a program; it does not chain execution. See [PRG import](PRG_IMPORT.md) for conversion limits.

Native LOAD stages and validates the program before publication, preserving the old program on validation failure. Binary blobs are restored by rereading the validated file: keep it available and unchanged until LOAD finishes. An I/O failure in that second pass can leave some blob bytes changed. A large load may require `NEW` first to free space; that explicitly discards the old program.

Target `VERIFY` compares the file against the current program's canonical serialized bytes. A structurally valid file with a differently arranged name dictionary can therefore differ. The [host verifier](HOST_TOOLS.md) canonicalizes both input files.

Raw `.BIN` exchange belongs to the [binary/sprite editor](BINARY_EDITOR.md); it has no load-address prefix. Native SAVE cannot export a stock BASIC PRG.

## Hardware and reserved memory

| Syntax | Behavior |
| --- | --- |
| `POKE address,value` | Write a byte, with address 0–65535 and value 0–255 |
| `WAIT address,mask[,xor]` | Wait until `(PEEK(address) XOR xor) AND mask` is nonzero; mask/xor are bytes, default xor is zero |
| `SYS address` | Call machine code at an unsigned word address using registers at `$030C–$030F` |
| `RESERVE address,bytes` | Protect a nonempty, page-aligned range before source/code/heap allocations occupy it |

BASIC execution exposes RAM beneath cartridge/BASIC/KERNAL ROM and hardware I/O at `$D000–$DFFF`. Thus `PEEK` at a ROM address reads RAM, and stock BASIC ROM entry points do not provide a compatible machine-code API. SYS/USR code must return normally and preserve firmware, vectors and allocated program memory. Stock memory-top POKEs at 55/56 do not configure this allocator.

`RESERVE` accepts unsigned numeric literals aligned to 256-byte pages. The range must be entirely free and within `$2C00–$CFFF` or `$E000–$E3FF`, with at most eight protected ranges. It is processed during compilation, cannot appear inside IF, and does no work during RUN. Declare ranges first, normally on the first numbered line, before entering/importing the rest of the program:

```basic
10 RESERVE $3C00,$200:RESERVE $C000,$300:CLR
```

Repeating identical bounds is harmless. Conflicting/occupied ranges fail without overwriting allocations. RUN, CLR, edits and CLEAN preserve reservations; NEW releases them. Removing a declaration does not release its range, and a failed submission/import can retain a successfully processed declaration. SAVE/LOAD preserve both direct and numbered reservations. The binary editor also supports manual byte-granular reservations.

## Limits and unsupported features

| Resource | Limit |
| --- | --- |
| Line number | 0–63999, decimal |
| Stored line | 255 token bytes; expanded text may be longer |
| Ordinary command entry | 80 PETSCII characters |
| Split editor draft | 160 PETSCII bytes including the line number |
| Identifier | Up to 255 bytes in imported source, subject to the input route's line limit |
| String | 255 bytes |
| Array | Eight dimensions; total allocation must fit available memory |
| Expression nesting | 32 levels |
| Nested IF / per-line IF patches | 32 / 64 |
| Active FN calls | Eight |
| Binary editor | Eight reservations, sixteen blobs |

Recognized but unsupported numeric keywords/functions are `SQR`, `LOG`, `EXP`, `COS`, `SIN`, `TAN`, `ATN` and `π`. Their source can be retained/listed, but evaluating them raises an unsupported-feature error. No fractional/scientific literals, fixed-point values, remainder operator, stock PRG export, tape transport, RS-232 transport or built-in assembler is available. `ASM` in the binary editor is a blob type opened in the hex view.

Additional BASIC dialect keywords (such as `DO`, `LOOP`, `WHILE`, `WEND` and graphics/sound command sets) are not part of this vocabulary. Use the ordinary C64 hardware registers through PEEK/POKE or reserved machine code.

## Errors

Errors use a `?` prefix. Stored source that fails compilation can remain available for LIST and correction. Runtime errors return to the prompt and invalidate CONT.

| Message | Meaning |
| --- | --- |
| `SYNTAX ERROR` | Malformed source, arguments or program-file structure |
| `ILLEGAL QUANTITY` | A literal, count, address-related argument or other checked quantity is outside its allowed range |
| `OUT OF MEMORY` | No suitable allocation or required temporary staging space is available |
| `DIVISION BY ZERO` | Integer divisor is zero |
| `UNDEF'D STATEMENT` | A line target is absent or a function has no active definition |
| `RETURN WITHOUT GOSUB` | No matching subroutine frame |
| `NEXT WITHOUT FOR` | No matching loop frame |
| `TYPE MISMATCH` | String and numeric uses are incompatible |
| `CAN'T CONTINUE` | No valid saved continuation |
| `UNSUPPORTED FEATURE` | An unsupported operation, numeric form or transport was reached |
| `FORMULA TOO COMPLEX` | A parser, expression, control-stack or function-depth bound was exceeded |
| `STRING TOO LONG` | A string result would exceed 255 bytes |
| `OUT OF DATA` | READ exhausted the available DATA fields |
| `DEVICE ERROR` | A device operation or final SAVE status failed |
