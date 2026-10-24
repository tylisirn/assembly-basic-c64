; Assembly BASIC ABI 7: fixed RAM entry points, documented NMOS instructions.
PORT = $01
PTR = $02
PTR2 = $04
TMP = $06
LEFT = $08
RIGHT = $0a
VALUE = $0c
COUNT = $0e
DEST = $10
SOURCE = $12
SIZE = $14
PREV = $16
WALK = $18
CPTR = $1a

; Banked-service entry stubs; copied after KERNAL RAMTAS clears page 3.
FUTURE_RAM_START = $0334
FUTURE_RAM_END = $0400 ; exclusive
FUTURE_RAM_BYTES = FUTURE_RAM_END-FUTURE_RAM_START ; 204 bytes

STATE = $0b00
FREE_HEAD = STATE
NAME_HEAD = STATE+2
NAME_COUNT = $28
SLAB_HEAD = STATE+6
PROGRAM_HEAD = STATE+8
CURRENT_LINE = STATE+10
CURRENT_OFFSET = STATE+12
PENDING = $77
EXPR_TOP = $40
CONTROL_TOP = $41
GENERATION = STATE+17
CONT_PC = STATE+19
CONT_GEN = STATE+21
ENTRY = STATE+23
ERROR_CODE = $75
SAVED_SP = STATE+26
LINE_NO = STATE+27
ANCHOR = STATE+29
SUCCESSOR = STATE+31
PREDECESSOR = STATE+33
OLD_PAYLOAD = STATE+35
TOKEN_LEN = $1d
TOKEN_POS = $1c
INPUT_POS = $1e
INPUT_LEN = $1f
EMIT_PASS = $21
CODE_SIZE = STATE+42
CODE_PTR = $22
NEW_PAYLOAD = STATE+46
TARGET = STATE+48
CELL = $24
LEX_LEN = $20
LEX_CODE = STATE+53
IS_HEX = $27
COMMAND = $74
DIRECT_PAYLOAD = STATE+56
DIRECT_ANCHOR = STATE+58 ; seven bytes
SLAB_USED = STATE+65
PARSE_DEPTH = $26
OP_STACK = STATE+67 ; 32 saved precedence operators
PRINT_LAST = $2a
IF_PATCH = STATE+100
SCRATCH = $13c0
RUNNING = $76
IO_MAP = $56
IO_STATUS = $57
IO_A = $58
IO_X = $59
IO_Y = $5a
ALLOC_RESULT = $5b
LIST_ANCHOR = STATE+118
LIST_END = STATE+120
LIST_POS = STATE+122
LIST_PREVIOUS = STATE+123
NUM_BUFFER = STATE+124 ; 6 digits
NUM_LENGTH = $63
NUM_SIGN = $64
FRAME_CELL = $32
FRAME_LIMIT = $34
FRAME_STEP = $36
FRAME_PC = $30
SELECTOR = $3f
DATA_LINE = STATE+141
DATA_POS = $4d
READ_TYPE = $51
STRING_LENGTH = $38
STRING_PTR = $39
STRING_DEST = $3b
STRING_CELL = $3d
INPUT_BUFFER = $0c00
TOKENS = $0d00
LEX_BUFFER = $0e00
EXPR_STACK = $0f00
CONTROL_STACK = $1000
; Language zero page $02-$78 replaces stock BASIC scratch; KERNAL owns $90-$ff.
; $1200-$13ff: staged string/input/transport bytes.
BRIDGE = $1200

ERR_SYNTAX = 1
ERR_QUANTITY = 2
ERR_MEMORY = 3
ERR_DIVZERO = 4
ERR_UNDEFINED = 5
ERR_RETURN = 6
ERR_NEXT = 7
ERR_TYPE = 8
ERR_CONT = 9
ERR_UNSUPPORTED = 10
ERR_STACK = 11
ERR_STRING = 12
ERR_DATA = 13

.macro JEQ label
 bne *+5
 jmp label
.endmacro
.macro JNE label
 beq *+5
 jmp label
.endmacro
.macro JCC label
 bcs *+5
 jmp label
.endmacro
.macro JCS label
 bcc *+5
 jmp label
.endmacro
.macro JMI label
 bpl *+5
 jmp label
.endmacro
.macro JPL label
 bmi *+5
 jmp label
.endmacro
ARRAY_HEAD = STATE+152
ARRAY_RECORD = $2e
ARRAY_DIMS = $2b
ARRAY_TYPE = $2c
ARRAY_INDEX = $2d
FROZEN_TOP = $54
IF_COUNT = STATE+162
ARRAY_SCRATCH = $13e0
DATA_ACTIVE = $50
DATA_TOKEN_PTR = $52
DATA_LIMIT = $4e
DATA_SIGN = $4f
FUNCTION_HEAD = STATE+168
FUNCTION_RECORD = STATE+170
FUNCTION_PARAMETER = STATE+172
FUNCTION_PATCH = STATE+174
COMPILER_SP = STATE+176
FILE_OPERATION = STATE+177
FILE_DEVICE = STATE+178
FILE_NAME_LEN = $6f
FILE_MAP = $70
FILE_ID = $5d
FILE_COUNT = $5f
FILE_CRC = $61
FILE_BYTE = $72
FILE_MODE = $73
FILE_ANCHOR = STATE+190
FILE_NEXT = STATE+192
LOAD_OLD = $1300

LOADING = $65
GATE_FLAGS = $66
GC_SCAN = $43
GC_NEXT = $45
GC_CAND = $47
GC_BUSY = $49
GC_INDEX = $4a
GC_END = $4b
DEVICE_LOGICAL = $6b
DEVICE_NUMBER = $6c
DEVICE_SECONDARY = $6d
INPUT_KIND = $6e
CLOCK_VALUE = $68
FN_DEPTH = $67
ABBREVIATED = $78

USER_BASE = $2c00
COMPILE_ERROR = STATE+194
IF_PENDING = STATE+195
RANDOM_STATE = STATE+196
LIST_MIN = STATE+198
LIST_MAX = STATE+200
MEM_IO = STATE+202
CLEAN_BUFFER = STATE+203
CLEAN_PTR = STATE+205
CLEAN_SIZE = STATE+207
RANDOM_READY = STATE+209

; Reservation bounds live outside user RAM, so graphics/ML may overwrite all bytes.
RESERVE_COUNT = STATE+210 ; table byte count, at most eight page ranges
RESERVATIONS = STATE+211 ; eight [start page,end page) byte pairs
RESERVE_START = STATE+243
RESERVE_END = STATE+245
RESERVE_BLOCK_END = STATE+247
RESERVE_NEXT = STATE+249

; Runtime collection borrows lexer scratch; no lexer is active at GC boundaries.
GC_MARKS = LEX_BUFFER ; 2048 possible payload starts, one bit each
GC_PAGE = SIZE ; Cached high byte rounded down to a 2-KiB window.
; Allocating string helpers recompute SIZE after collection.
GC_FREE_PREV = PREV
GC_FREE_NEXT = WALK

; Classic Magic Desk: eight 8-KiB ROM banks; select while executing in common RAM.
CART_REGISTER = $de00
CART_BANK = STATE+227 ; Software shadow of the write-only bank register.
BANK_COMMAND = 0
BANK_COMPILER = 1
BANK_RUNTIME = 2
BANK_SERVICES = 2

; Inline descriptor: JSR bank_call; bank byte, map byte, target word.
; $ff retains the current bank. Calls return A/X/Y and result flags, with the
; caller's complete port, bank and interrupt mask restored; decimal is cleared.
.macro RAM_CALL target
 jsr bank_call
 .byte $ff,5
 .word target
.endmacro

; Expression tags: signed=0, string=1, unsigned=$80.
NUM_TYPE = STATE+228
NAME_KIND = STATE+229

; LIST formatting state, inactive during lexing and native execution.
LIST_CURRENT = STATE+230

; Split editor workspace stays outside the arena and all compiler/runtime scratch.
BANK_EDITOR = 3
ED_TEXT = $0a60 ; 160 PETSCII bytes, reserved at the end of the common gateway.
ED_STATE = $03cc ; 52 bytes after the service/output stubs, cleared by RAMTAS.
ED_ACTIVE = ED_STATE
ED_FOCUS = ED_STATE+1 ; 0 listing, 1 edit pane
ED_MODE = ED_STATE+2 ; 0 insert, 1 overwrite, 2 literal
ED_SELECTED = ED_STATE+3 ; persistent BASIC line number
ED_TOP = ED_STATE+5 ; persistent first displayed BASIC line number
ED_LAST = ED_STATE+7
ED_ANCHOR = ED_STATE+9
ED_NEXT = ED_STATE+11
ED_OLD_OUT = ED_STATE+13
ED_LEN = ED_STATE+15
ED_CURSOR = ED_STATE+16 ; index in ED_TEXT
ED_START = ED_STATE+17 ; physical offset of draft in the four-row pane
ED_OUT = ED_STATE+18 ; physical output offset, 0..159
ED_ROUTE = ED_STATE+19 ; 0 output, 1 listing, 2 copy, 3 help, 4 error, 5 measure
ED_ROW = ED_STATE+20
ED_COL = ED_STATE+21
ED_INDENT = ED_STATE+22
ED_HIGHLIGHT = ED_STATE+23
ED_SEEN = ED_STATE+24
ED_SUBMITTED = ED_STATE+25 ; 1 numbered, 2 direct
ED_CHAR = ED_STATE+26
ED_CODE = ED_STATE+27
ED_COLOR = ED_STATE+28
ED_HELP = ED_STATE+29
ED_COPY_FULL = ED_STATE+30
ED_BLINK = ED_STATE+31
ED_CURSOR_ON = ED_STATE+32
ED_UNDER = ED_STATE+33
ED_UNDER_COLOR = ED_STATE+34
ED_TEMP = ED_STATE+35
ED_SAVE = ED_STATE+36 ; two-byte temporary line number
ED_STEPS = ED_STATE+38
ED_OLD_IN = ED_STATE+39
ED_INPUT_LEN = ED_STATE+41
ED_INPUT_POS = ED_STATE+42
ED_INPUT_READY = ED_STATE+43
ED_SAVE_LEN = ED_STATE+44
ED_SAVE_CURSOR = ED_STATE+45
ED_SAVE_START = ED_STATE+46
ED_VIEW_VALID = ED_STATE+47
ED_VIEW_GEN = ED_STATE+48 ; cached source generation
ED_SELECTED_ROW = ED_STATE+50 ; $ff when the selection is outside the viewport
ED_SKIP = ED_STATE+51 ; first row written by an incremental render
; The expression stack has 32 four-byte entries, leaving its upper 128 bytes
; unused by native execution and GC. The row map and scroll work use 96 bytes.
ED_ROWS_LO = EXPR_STACK+128 ; 20 logical-line start anchors; continuations = 0
ED_ROWS_HI = ED_ROWS_LO+20
ED_SELECTED_ANCHOR = ED_ROWS_HI+20
ED_OLD_TOP = ED_SELECTED_ANCHOR+2
ED_LIMIT = ED_OLD_TOP+2 ; exclusive last row written by an incremental render
ED_DELTA = ED_LIMIT+1
ED_RETAIN = ED_DELTA+1
ED_MOVE_ROW = ED_RETAIN+1
ED_LINE_START = ED_MOVE_ROW+1
ED_SCAN_ROW = ED_LINE_START+1
ED_HIGHLIGHT_MASK = ED_SCAN_ROW+1
ED_LITERAL = ED_HIGHLIGHT_MASK+1
ED_PAINT_LEN = ED_LITERAL+1
ED_DRAFT_START = ED_PAINT_LEN+1
ED_AFFECTED = ED_DRAFT_START+1 ; word; $ff high means no valid numbered submission
ED_LINKS = ED_AFFECTED+2 ; four row continuation flags
ED_TARGET = ED_LINKS+4
ED_FIRST = ED_TARGET+1
ED_END = ED_FIRST+1
ED_SAVE_PAINT = ED_END+1
ED_GOTO = ED_SAVE_PAINT+1
ED_GOTO_NO = ED_GOTO+1 ; word
ED_GOTO_LEN = ED_GOTO_NO+2
ED_CONTEXT_ROWS = ED_GOTO_LEN+1
ED_HELP_TAIL = EXPR_STACK+224 ; final 32 bytes of an 800-byte listing snapshot
.assert ED_CONTEXT_ROWS < ED_HELP_TAIL, error, "Editor row workspace overflow"
.assert ED_HELP_TAIL+32 = CONTROL_STACK, error, "Editor overlaps control stack"
ED_PTR = $fb ; KERNAL's free user zero-page pointers; no language scratch borrowed
ED_CPTR = $fd
ED_HELP_SCREEN = LEX_BUFFER ; INPUT staging borrows this only before allocation
.macro EDITOR_CALL target
 jsr bank_call
 .byte BANK_EDITOR,7
 .word target
.endmacro
.macro COMMAND_CALL target
 jsr bank_call
 .byte BANK_COMMAND,7
 .word target
.endmacro

; PRG conversion is synchronous inside staged LOAD. Compiler scratch begins at
; $13C0; the old graph's saved heads occupy $1300-$130F.
PRG_ADDRESS = LOAD_OLD+16
PRG_NEXT = PRG_ADDRESS+2
PRG_LAST = PRG_NEXT+2
PRG_HAVE_LINE = PRG_LAST+2
PRG_MODE = PRG_HAVE_LINE+1 ; 0 normal, 1 quote, 2 REM, 3 DATA, 4 quoted DATA
PRG_IDENT = PRG_MODE+1 ; 0 boundary, 1/2 significant name bytes, 3 number
PRG_CHAR = PRG_IDENT+1
PRG_GO = PRG_CHAR+1
PRG_NAME_START = PRG_GO+1
.assert PRG_NAME_START < SCRATCH, error, "PRG state overlaps compiler scratch"

; Binary editor metadata uses stock BASIC's unused input buffer and the unused
; page-2 tail. KERNAL file tables ($0259-$0276) and keyboard state stay intact.
BANK_BINARY = 4
BANK_BINARY_STORE = 5
BE_RES = $0200 ; 8 exact [start,end) word pairs
BE_ACTIVE = $0220 ; logical reservation bitset
BE_BASIC = $0221 ; BASIC-owned/immutable bounds bitset
BE_FILE_RES_COUNT = $0222 ; imported v2 prefix count
BE_OCCUPIED = $0223 ; 16 blob slots, two bitset bytes
BE_MAGIC = $0225
BE_BLOBS0 = $0228 ; first six eight-byte records, ends before KERNAL file tables
BE_BLOBS1 = $02a7 ; final ten records, ends $02f6
; Blob: reservation byte,start word,size word,type/multicolor byte,packed colors2.
BE_UI_ACTIVE = $02f7
BE_CALLER = $02f8 ; 0 direct,1 BASIC,2 suspended keyboard INPUT
BE_BACKUP = $02f9 ; temporary LOAD metadata/filename backup pointer
BE_STAGE = $02fb ; reserved for transaction bookkeeping
BE_VERSION = $02fd
BE_LOADING = $02fe
BE_ERROR = $02ff

; Transient workspace is only used while compiler and native execution wait.
BE_INPUT = $0e00 ; 64-byte numeric/filename prompt
BE_STATE = $0e40
BE_MODE = BE_STATE ; 0 reservations,1 blobs,2 hex,3 sprite
BE_RES_SEL = BE_STATE+1
BE_BLOB_SEL = BE_STATE+2
BE_CHAR = BE_STATE+3
BE_X = BE_STATE+4
BE_Y = BE_STATE+5
BE_COL = BE_STATE+6
BE_ROW = BE_STATE+7
BE_COLOR = BE_STATE+8
BE_REVERSE = BE_STATE+9
BE_TOP = BE_STATE+10 ; list first physical row, or hex byte offset word
BE_POS = BE_STATE+12 ; selected byte offset word
BE_RANGE = BE_STATE+14 ; current operation start word
BE_SIZE = BE_STATE+16 ; current operation byte count word
BE_END = BE_STATE+18 ; current operation exclusive end word
BE_NUMBER = BE_STATE+20 ; parsed or formatted word
BE_TEMP = BE_STATE+22
BE_INDEX = BE_STATE+23
BE_LIMIT = BE_STATE+24
BE_PTR_SAVE = BE_STATE+25 ; word
BE_PROMPT_LEN = BE_STATE+27
BE_NIBBLE = BE_STATE+28
BE_PIXEL = BE_STATE+29
BE_COUNT = BE_STATE+30 ; word
BE_ADDR = BE_STATE+32 ; word
BE_STRING = BE_STATE+34 ; word
BE_SELECTED_ROW = BE_STATE+36
BE_LINE = BE_STATE+37
BE_PROMPT_KIND = BE_STATE+38
BE_OLD_COLOR = BE_STATE+39
BE_OLD_CC = BE_STATE+40
BE_FLAGS = BE_STATE+41
BE_FILE_LEN = BE_STATE+42
BE_FILE_OP = BE_STATE+43
BE_SCAN = BE_STATE+44
BE_MATCH = BE_STATE+45
BE_RES_MAP = BE_STATE+46 ; eight dense export IDs
BE_RES_COUNT = BE_STATE+54
BE_BLOB_COUNT = BE_STATE+55
BE_WORK = BE_STATE+56 ; 32-byte storage/reservation scratch
BE_RECORD = BE_STATE+88 ; eight-byte blob record buffer
BE_PROPOSED = BE_STATE+96 ; proposed [start,end), reservation and type
BE_VIC = $0f00 ; saved VIC registers and CIA2 bank; $0f80 row map untouched
BE_PANE = $1200 ; 160 screen cells plus 160 colors, safe while waiting for GETIN
BE_LOAD_META = $0f00 ; 169-byte LOAD backup; invalidate listing row cache first
BE_LOAD_NAME = $0c00 ; native v2 loader does not tokenize text
BE_LOAD_NAME_LEN = $02fb
BE_LOAD_DEVICE = $02fc
BE_INPUT_BACKUP = $0d60 ; suspended CHRIN command backup restored before LIST work
.macro BINARY_CALL target
 jsr bank_call
 .byte BANK_BINARY,7
 .word target
.endmacro
.macro STORAGE_CALL target
 jsr bank_call
 .byte BANK_BINARY_STORE,7
 .word target
.endmacro
