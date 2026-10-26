# Integer signedness and arithmetic

### 1. Numeric types

| Variable syntax | Type | Range |
|---|---|---:|
| `A` | Signed 16-bit integer | −32768 to 32767 |
| `A%` | Unsigned 16-bit integer | 0 to 65535 |

Both integer types use a 16-bit word. Signed values use two’s-complement interpretation.

For a word \(w\):

- Unsigned value: \(w\).
- Signed value: \(w\) when \(w < 32768\), otherwise \(w - 65536\).

Changing integer signedness preserves the word. It does not perform range checking.

### 2. Evaluation and destination conversion are separate

Evaluate an expression according to its operands and operators. The destination must not influence earlier arithmetic.

After evaluation, the destination consumes or converts the result:

| Consumer | Treatment of integer result |
|---|---|
| Signed integer variable | Preserve the word; interpret as signed |
| Unsigned integer variable | Preserve the word; interpret as unsigned |
| `PRINT` | Print according to the expression’s result type |
| `POKE` address argument | Consume the word as an unsigned address |

Thus:

```basic
PRINT 20000 + 20000   : REM Prints 40000
A = 20000 + 20000     : REM A becomes -25536
A% = 20000 + 20000    : REM A% becomes 40000

PRINT -5 + 4          : REM Prints -1
A% = -5 + 4           : REM A% becomes 65535
```

The arithmetic result is identical regardless of destination. Only its final interpretation changes.

### 3. Integer literals

**Constant-only arithmetic**

In expressions containing only integer constants:

- Nonnegative constants, including zero, are unsigned.
- Negative constants are signed.
- Operators follow the normal mixed arithmetic rules.
- Result signedness follows operand types, not the mathematical sign of the answer.

Examples:

```basic
PRINT 4 - 5          : REM Unsigned 65535
PRINT -5 + 4         : REM Signed -1
PRINT 20000 + 20000  : REM Unsigned 40000
```

**Contextual naked literals**

When directly combined with a typed variable expression, a naked literal adopts that expression’s type if its value is representable in that type.

| Literal value | Permitted interpretation |
|---|---|
| 0 through 32767 | Signed or unsigned, according to context |
| 32768 through 65535 | Unsigned |
| −32768 through −1 | Signed |

Examples:

```basic
N% + 2      : REM 2 adopts unsigned
N + 2       : REM 2 adopts signed
N + 40000   : REM 40000 remains unsigned; mixed arithmetic applies
N% + -2     : REM -2 remains signed; mixed arithmetic applies
```

The signed negative constant `-32768` must be recognized before independently typing its magnitude `32768`.

### 4. Context is local to each operation

Resolve literal context according to the expression tree, respecting precedence and associativity. Later operands must not retroactively change an earlier operation.

```basic
A% / 2 + B
```

Evaluate as:

1. `2` adopts unsigned from `A%`.
2. Perform unsigned division.
3. Combine that unsigned result with signed `B`.
4. The addition has a signed result.

For:

```basic
A% + B + 2
```

evaluate as:

1. `A% + B` produces a signed result.
2. `2` adopts signed from that result.
3. Perform signed addition.

An evaluated constant subexpression has its own type and is no longer an adaptable naked literal:

```basic
N% + (4 - 5)
```

Here, `4 - 5` independently produces unsigned `65535`.

Parentheses around a literal alone preserve contextual typing: `N% + (2)` behaves like `N% + 2`.

### 5. Mixed integer arithmetic

Use the following type rule for binary integer arithmetic:

| Left operand | Right operand | Operation and result type |
|---|---|---|
| Signed | Signed | Signed |
| Unsigned | Unsigned | Unsigned |
| Signed | Unsigned | Signed |
| Unsigned | Signed | Signed |

For mixed operations, reinterpret the unsigned operand’s existing word as signed before performing sign-sensitive arithmetic. No wider intermediate or range check is implied.

Consequences:

```basic
A% = 40000
B = 2

PRINT A% / 2    : REM Unsigned division: 20000
PRINT A% / B    : REM Signed division: -12768

B = -2
PRINT A% / B    : REM Signed division: 12768
```

The last expression does not produce mathematical `-20000`: signed interpretation changes unsigned `40000` into signed `-25536`.

### 6. Arithmetic width and overflow

Integer addition, subtraction, and multiplication retain the low 16 bits of the result. Overflow wraps for both signed and unsigned arithmetic.

The result’s type determines how those bits are subsequently interpreted.

Implementation may share routines for:

- Signed and unsigned addition.
- Signed and unsigned subtraction.
- Multiplication that returns only the low 16 bits.

Signedness remains significant for division, ordering comparisons and printing.

Division must select its signed or unsigned implementation after operand types have been resolved.

### 7. Constant folding

Constant folding, if and where implemented, must reproduce the specified typed, 16-bit evaluation at every operation.

A folder may use wider host arithmetic internally, but it must:

1. Apply the language’s operand interpretations.
2. Perform the operation.
3. Retain the specified 16-bit result.
4. Preserve the operation’s result type.

It must not infer signedness from the final mathematical value or postpone all wrapping until the end.

For example:

```basic
PRINT (4 - 5) / 2
```

must evaluate as unsigned `65535 / 2`, producing `32767`. Folding it through mathematical `-1 / 2` would change its behavior.

### 8. Implementation constraints

Numeric cells and array elements occupy two bytes. Expression tags are signed 0, string 1 and unsigned $80. These rules apply to both native source-container formats; binary metadata does not change numeric evaluation.

Representable naked literals beside signed operands can retain their default unsigned tag internally: the mixed signed rule gives exactly the same operand interpretation and result type as adopting signed. This requires no extra runtime provenance and does not allow context to change an already evaluated operation. Positive constants never inherit the assignment destination's type.

Negative literal prefixes, including `-32768` and `-(2)`, produce signed words. Unary minus on computed expressions and declared values preserves their type: `-(2+2)` is unsigned 65532, whereas `-4` is signed -4. Power retains its existing precedence; `-2^2` is signed -4, while `-(2^2)` negates the already evaluated unsigned subexpression and produces unsigned 65532. `NOT` preserves numeric type; comparisons produce signed -1 or 0. Numeric functions keep their established declared result types (for example, VAL and RND are signed; FRE is unsigned; INT and ABS preserve the argument type).

Literal power-of-two multiplication uses wrapping left shifts. Signed division uses biased arithmetic right shifts to preserve truncation toward zero; unsigned division uses zero-fill shifts. Literal `$8000` is unsigned 32768, interpreted as signed -32768 only in mixed signed division. General constant folding is not implemented; the same per-operation rules constrain the existing strength reductions.

There is no fixed-point type or remainder operator. Explicit `>>` uses arithmetic sign fill for both integer types. See the [language reference](../LANGUAGE_REFERENCE.md#operators-and-precedence) for precedence, count bounds and division behavior.
