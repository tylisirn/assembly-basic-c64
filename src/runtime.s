.segment "RUNTIME"
; RAM-only coalescing allocator. Request physical bytes A/X, result payload.
alloc_common:
 sta IO_A
 lda #1
 sta SCRATCH+8
 lda IO_A
 jmp alloc_start
alloc:
 sta IO_A
 lda #0
 sta SCRATCH+8
 lda IO_A
alloc_start:
 sta SIZE
 stx SIZE+1
 lda #0
 sta ALLOC_RESULT
 sta ALLOC_RESULT+1
 sta PREV
 sta PREV+1
 lda SIZE+1
 bne :+
 lda SIZE
 cmp #4
 bcs :+
 lda #4
 sta SIZE
:
 lda FREE_HEAD
 sta WALK
 lda FREE_HEAD+1
 sta WALK+1
@scan:
 lda WALK
 ora WALK+1
 JEQ @fail
 lda SCRATCH+8
 beq @size
 lda WALK+1
 cmp #$80
 JCS @next
@size:
 ldy #0
 lda (WALK),y
 sec
 sbc SIZE
 sta TMP
 iny
 lda (WALK),y
 sbc SIZE+1
 sta TMP+1
 JCC @next
 lda TMP+1
 bne @split
 lda TMP
 beq @whole
 cmp #4
 JCC @next ; exact-sized payloads may not absorb 1..3 trailing bytes
@split:
 lda SCRATCH+8
 bne @split_common
 ; Movable objects use the high end, preserving low RAM for stable bindings.
 clc
 lda WALK
 adc TMP
 sta PTR2
 lda WALK+1
 adc TMP+1
 sta PTR2+1
 ldy #0
 lda TMP
 sta (WALK),y
 iny
 lda TMP+1
 sta (WALK),y
 lda PTR2
 sta WALK
 lda PTR2+1
 sta WALK+1
 jmp @publish
@split_common:
 clc
 lda WALK
 adc SIZE
 sta PTR2
 lda WALK+1
 adc SIZE+1
 sta PTR2+1
 lda SCRATCH+8
 beq :+
 lda PTR2+1
 cmp #$80
 bcc :+
 JNE @next
 lda PTR2
 bne @next
:
 ldy #0
 lda TMP
 sta (PTR2),y
 iny
 lda TMP+1
 sta (PTR2),y
 ldy #2
 lda (WALK),y
 sta (PTR2),y
 iny
 lda (WALK),y
 sta (PTR2),y
 lda PTR2
 sta VALUE
 lda PTR2+1
 sta VALUE+1
 jmp @unlink
@whole:
 lda SCRATCH+8
 beq @whole_ready
 clc
 lda WALK
 adc SIZE
 sta TMP
 lda WALK+1
 adc SIZE+1
 cmp #$80
 bcc @whole_ready
 bne @next
 lda TMP
 bne @next
@whole_ready:
 ldy #2
 lda (WALK),y
 sta VALUE
 iny
 lda (WALK),y
 sta VALUE+1
@unlink:
 lda PREV
 ora PREV+1
 beq @head
 ldy #2
 lda VALUE
 sta (PREV),y
 iny
 lda VALUE+1
 sta (PREV),y
 jmp @publish
@head:
 lda VALUE
 sta FREE_HEAD
 lda VALUE+1
 sta FREE_HEAD+1
@publish:
 ldy #0
 lda SIZE
 sta (WALK),y
 iny
 lda SIZE+1
 sta (WALK),y
 clc
 lda WALK
 adc #2
 sta ALLOC_RESULT
 lda WALK+1
 adc #0
 sta ALLOC_RESULT+1
 rts
@next:
 lda WALK
 sta PREV
 lda WALK+1
 sta PREV+1
 ldy #2
 lda (WALK),y
 tax
 iny
 lda (WALK),y
 sta WALK+1
 stx WALK
 jmp @scan
@fail:
 rts
free_block:
 sec
 lda PTR
 sbc #2
 sta PTR
 lda PTR+1
 sbc #0
 sta PTR+1
 lda #0
 sta PREV
 sta PREV+1
 lda FREE_HEAD
 sta WALK
 lda FREE_HEAD+1
 sta WALK+1
@locate:
 lda WALK
 ora WALK+1
 beq @insert
 lda WALK+1
 cmp PTR+1
 bcc @advance
 bne @insert
 lda WALK
 cmp PTR
 bcs @insert
@advance:
 lda WALK
 sta PREV
 lda WALK+1
 sta PREV+1
 ldy #2
 lda (WALK),y
 tax
 iny
 lda (WALK),y
 sta WALK+1
 stx WALK
 jmp @locate
@insert:
gc_free_insert = * ; Collector supplies header PTR and sorted PREV/WALK cursors.
 ldy #2
 lda WALK
 sta (PTR),y
 iny
 lda WALK+1
 sta (PTR),y
 lda PREV
 ora PREV+1
 beq @head
 ldy #2
 lda PTR
 sta (PREV),y
 iny
 lda PTR+1
 sta (PREV),y
 jmp @merge_next
@head:
 lda PTR
 sta FREE_HEAD
 lda PTR+1
 sta FREE_HEAD+1
@merge_next:
 lda GC_BUSY
 bne @done
 jsr coalesce
 lda PREV
 ora PREV+1
 beq @done
 lda PREV
 sta PTR
 lda PREV+1
 sta PTR+1
 jsr coalesce
@done:
 rts
coalesce:
 ldy #0
 lda (PTR),y
 clc
 adc PTR
 sta TMP
 iny
 lda (PTR),y
 adc PTR+1
 sta TMP+1
 iny
 lda (PTR),y
 sta PTR2
 iny
 lda (PTR),y
 sta PTR2+1
 cmp TMP+1
 bne @done
 lda PTR2
 cmp TMP
 bne @done
 lda PTR2
 ora PTR2+1
 beq @done
 ldy #0
 lda (PTR),y
 clc
 adc (PTR2),y
 sta (PTR),y
 iny
 lda (PTR),y
 adc (PTR2),y
 sta (PTR),y
 ldy #2
 lda (PTR2),y
 sta (PTR),y
 iny
 lda (PTR2),y
 sta (PTR),y
 sec
 rts
@done:
 clc
 rts
.include "collect.s"

runtime_error:
 sta ERROR_CODE
 lda #0
 sta FN_DEPTH
 lda #0
 sta CONT_PC
 sta CONT_PC+1
 sta EXPR_TOP
 sta CONTROL_TOP
 sta CONTROL_TOP+1
 jmp enter_ready
undefined_line:
 lda #ERR_UNDEFINED
 jmp runtime_error
unsupported_word:
 lda #ERR_UNSUPPORTED
 jmp runtime_error
poll_break:
 lda PENDING
 bne @abort
 ; KERNAL STOP is called through a banked low-RAM service gateway.
 lda #<$ffe1
 sta service_call+1
 lda #>$ffe1
 sta service_call+2
 jsr kernal_gate
 beq @abort
 rts
@abort:
 lda #0
 sta CONT_PC
 sta CONT_PC+1
 jmp enter_ready
push_number:
 sta RIGHT
 stx RIGHT+1
 lda EXPR_TOP
 cmp #32
 bcc :+
 lda #ERR_STACK
 jmp runtime_error
:
 asl
 asl
 tay
 lda #0
 sta EXPR_STACK,y
 iny
 sta EXPR_STACK,y
 iny
 lda RIGHT
 sta EXPR_STACK,y
 iny
 lda RIGHT+1
 sta EXPR_STACK,y
 inc EXPR_TOP
 rts
pop_number:
 lda EXPR_TOP
 bne :+
 lda #ERR_SYNTAX
 jmp runtime_error
:
 dec EXPR_TOP
 lda EXPR_TOP
 asl
 asl
 tay
 lda EXPR_STACK,y
 beq :+
 lda #ERR_TYPE
 jmp runtime_error
:
 lda EXPR_STACK+2,y
 ldx EXPR_STACK+3,y
 rts
binary_operands:
 jsr pop_number
 sta RIGHT
 stx RIGHT+1
 jsr pop_number
 sta LEFT
 stx LEFT+1
 rts
add_word_runtime:
 lda EXPR_TOP
 sec
 sbc #1
 asl
 asl
 tay
 lda EXPR_STACK,y
 JNE concat_string
 jsr binary_operands
 clc
 lda LEFT
 adc RIGHT
 pha
 lda LEFT+1
 adc RIGHT+1
 tax
 pla
 jmp push_number
subtract_word:
 jsr binary_operands
 sec
 lda LEFT
 sbc RIGHT
 pha
 lda LEFT+1
 sbc RIGHT+1
 tax
 pla
 jmp push_number
negate_word:
 jsr pop_number
 sta RIGHT
 stx RIGHT+1
 sec
 lda #0
 sbc RIGHT
 pha
 lda #0
 sbc RIGHT+1
 tax
 pla
 jmp push_number
not_word:
 jsr pop_number
 eor #$ff
 pha
 txa
 eor #$ff
 tax
 pla
 jmp push_number
and_word:
 jsr binary_operands
 lda LEFT+1
 and RIGHT+1
 tax
 lda LEFT
 and RIGHT
 jmp push_number
or_word:
 jsr binary_operands
 lda LEFT+1
 ora RIGHT+1
 tax
 lda LEFT
 ora RIGHT
 jmp push_number
rnd_word:
 jsr pop_number
 sta VALUE
 stx VALUE+1
 ora VALUE+1
 beq @last
 txa
 bpl @positive
 sta RANDOM_STATE+1
 ; Negative arguments reseed with their complete two's-complement word.
 lda VALUE
 sta RANDOM_STATE
 lda #1
 sta RANDOM_READY
 bne @advance
@positive:
 lda RANDOM_READY
 bne @advance
 lda #<$ffde
 sta service_call+1
 lda #>$ffde
 sta service_call+2
 jsr kernal_gate
 sta RANDOM_STATE
 stx RANDOM_STATE+1
 inc RANDOM_READY
@advance:
 lda RANDOM_STATE
 sta LEFT
 lda RANDOM_STATE+1
 sta LEFT+1
 lda #$55
 sta RIGHT
 lda #$62
 sta RIGHT+1
 jsr multiply_ax
 clc
 adc #$19
 sta RANDOM_STATE
 txa
 adc #$36
 sta RANDOM_STATE+1
@last:
 lda RANDOM_STATE
 ldx RANDOM_STATE+1
 jmp push_number
shift_left_word:
 jsr binary_operands
 lda #0
 beq shift_mode
shift_right_word:
 jsr binary_operands
 lda #1
shift_mode:
 sta NUM_SIGN
 lda RIGHT+1
 beq :+
 lda #ERR_QUANTITY
 jmp runtime_error
:
 ldy RIGHT
 cpy #16
 bcc shift_loop
 ldy #16
shift_loop:
 cpy #0
 beq shift_result
 lda NUM_SIGN
 bne @right
 asl LEFT
 rol LEFT+1
 jmp @next
@right:
 lda LEFT+1
 cmp #$80
 ror LEFT+1
 ror LEFT
@next:
 dey
 bne shift_loop
shift_result:
 lda LEFT
 ldx LEFT+1
 jmp push_number
; Constant power-of-two word divisors become biased arithmetic right shifts.
divide_negative_power_word:
 jsr divide_power_word
 jmp negate_word
divide_power_word:
 jsr binary_operands
 lda LEFT+1
 bpl @shift
 lda #$ff
 sta VALUE
 sta VALUE+1
 ldy RIGHT
@mask:
 cpy #0
 beq @bias
 asl VALUE
 rol VALUE+1
 dey
 bne @mask
@bias:
 lda VALUE
 eor #$ff
 clc
 adc LEFT
 sta LEFT
 lda VALUE+1
 eor #$ff
 adc LEFT+1
 sta LEFT+1
@shift:
 lda #1
 jmp shift_mode
multiply_word:
 jsr binary_operands
 jsr multiply_ax
 jmp push_number
multiply_ax:
 lda #0
 sta VALUE
 sta VALUE+1
 ldy #16
@loop:
 lsr RIGHT+1
 ror RIGHT
 bcc @shift
 clc
 lda VALUE
 adc LEFT
 sta VALUE
 lda VALUE+1
 adc LEFT+1
 sta VALUE+1
@shift:
 asl LEFT
 rol LEFT+1
 dey
 bne @loop
 lda VALUE
 ldx VALUE+1
 rts
divide_word:
 jsr binary_operands
 lda RIGHT
 ora RIGHT+1
 bne :+
 lda #ERR_DIVZERO
 jmp runtime_error
:
 lda LEFT+1
 eor RIGHT+1
 and #$80
 sta NUM_SIGN
 lda LEFT+1
 bpl @right
 sec
 lda #0
 sbc LEFT
 sta LEFT
 lda #0
 sbc LEFT+1
 sta LEFT+1
@right:
 lda RIGHT+1
 bpl @divide
 sec
 lda #0
 sbc RIGHT
 sta RIGHT
 lda #0
 sbc RIGHT+1
 sta RIGHT+1
@divide:
 lda #0
 sta VALUE
 sta VALUE+1
 ldx #16
@loop:
 asl LEFT
 rol LEFT+1
 rol VALUE
 rol VALUE+1
 sec
 lda VALUE
 sbc RIGHT
 tay
 lda VALUE+1
 sbc RIGHT+1
 bcc @next
 sta VALUE+1
 sty VALUE
 inc LEFT
@next:
 dex
 bne @loop
 lda NUM_SIGN
 beq @positive
 sec
 lda #0
 sbc LEFT
 pha
 lda #0
 sbc LEFT+1
 tax
 pla
 jmp push_number
@positive:
 lda LEFT
 ldx LEFT+1
 jmp push_number
power_word:
 jsr binary_operands
 lda RIGHT+1
 bmi @bad
 lda RIGHT
 sta FRAME_LIMIT
 lda RIGHT+1
 sta FRAME_LIMIT+1
 lda LEFT
 sta FRAME_STEP
 lda LEFT+1
 sta FRAME_STEP+1
 lda #1
 sta FRAME_CELL
 lda #0
 sta FRAME_CELL+1
@loop:
 lda FRAME_LIMIT
 ora FRAME_LIMIT+1
 beq @done
 lda FRAME_LIMIT
 and #1
 beq @square
 lda FRAME_CELL
 sta LEFT
 lda FRAME_CELL+1
 sta LEFT+1
 lda FRAME_STEP
 sta RIGHT
 lda FRAME_STEP+1
 sta RIGHT+1
 jsr multiply_ax
 sta FRAME_CELL
 stx FRAME_CELL+1
@square:
 lsr FRAME_LIMIT+1
 ror FRAME_LIMIT
 lda FRAME_LIMIT
 ora FRAME_LIMIT+1
 beq @done
 lda FRAME_STEP
 sta LEFT
 sta RIGHT
 lda FRAME_STEP+1
 sta LEFT+1
 sta RIGHT+1
 jsr multiply_ax
 sta FRAME_STEP
 stx FRAME_STEP+1
 jmp @loop
@done:
 lda FRAME_CELL
 ldx FRAME_CELL+1
 jmp push_number
@bad:
 lda #ERR_QUANTITY
 jmp runtime_error
; Signed comparisons: compare high bytes after biasing bit7.
compare_numbers:
 lda EXPR_TOP
 sec
 sbc #1
 asl
 asl
 tay
 lda EXPR_STACK,y
 JNE compare_strings
 jsr binary_operands
 lda LEFT+1
 eor #$80
 sta TMP
 lda RIGHT+1
 eor #$80
 sta TMP+1
 lda TMP
 cmp TMP+1
 bne @done
 lda LEFT
 cmp RIGHT
@done:
 rts
equal_word:
 jsr compare_numbers
 beq true_word
 bne false_word
ne_word:
 jsr compare_numbers
 bne true_word
 beq false_word
less_word:
 jsr compare_numbers
 bcc true_word
 bcs false_word
greater_word:
 jsr compare_numbers
 beq false_word
 bcs true_word
 bcc false_word
le_word:
 jsr compare_numbers
 beq true_word
 bcc true_word
 bcs false_word
ge_word:
 jsr compare_numbers
 bcs true_word
false_word:
 lda #0
 tax
 jmp push_number
true_word:
 lda #$ff
 tax
 jmp push_number
int_word:
 jsr pop_number
 jmp push_number
abs_word:
 jsr int_word
 lda EXPR_TOP
 sec
 sbc #1
 asl
 asl
 tay
 lda EXPR_STACK+3,y
 bpl @done
 jmp negate_word
@done:
 rts
sgn_word:
 jsr pop_number
 stx RIGHT+1
 ora RIGHT+1
 beq false_word
 txa
 bmi true_word
 lda #1
 ldx #0
 jmp push_number
store_number:
 sta STRING_CELL
 stx STRING_CELL+1
 jsr pop_number
 sta RIGHT
 stx RIGHT+1
 lda STRING_CELL
 sta PTR
 lda STRING_CELL+1
 sta PTR+1
 ldy #0
 lda RIGHT
 sta (PTR),y
 iny
 lda RIGHT+1
 sta (PTR),y
 rts
byte_quantity:
 jsr pop_number
 cpx #0
 beq :+
 lda #ERR_QUANTITY
 jmp runtime_error
:
 rts
poke_word:
 jsr byte_quantity
 sta STRING_LENGTH
 jsr pop_number
 sta PTR
 stx PTR+1
 ldy #0
 lda STRING_LENGTH
 sta (PTR),y
 rts
peek_word:
 jsr pop_number
 sta PTR
 stx PTR+1
 ldy #0
 lda (PTR),y
 ldx #0
 jmp push_number
wait_word:
 jsr byte_quantity
 sta SELECTOR
 jsr byte_quantity
 sta STRING_LENGTH
 jsr pop_number
 sta STRING_PTR
 stx STRING_PTR+1
@loop:
 jsr poll_break
 lda STRING_PTR
 sta PTR
 lda STRING_PTR+1
 sta PTR+1
 ldy #0
 lda (PTR),y
 eor SELECTOR
 and STRING_LENGTH
 beq @loop
 rts
sys_word:
 jsr pop_number
 sta sys_call+1
 stx sys_call+2
 jmp sys_gateway
fre_word:
 jsr pop_number
 jsr collect
 lda #0
 sta FRAME_LIMIT
 sta FRAME_LIMIT+1
 lda FREE_HEAD
 sta WALK
 lda FREE_HEAD+1
 sta WALK+1
@loop:
 lda WALK
 ora WALK+1
 beq @done
 ldy #0
 lda (WALK),y
 clc
 adc FRAME_LIMIT
 sta FRAME_LIMIT
 iny
 lda (WALK),y
 adc FRAME_LIMIT+1
 sta FRAME_LIMIT+1
 iny
 lda (WALK),y
 tax
 iny
 lda (WALK),y
 sta WALK+1
 stx WALK
 jmp @loop
@done:
 lda FRAME_LIMIT
 ldx FRAME_LIMIT+1
 jmp push_number
pos_word:
 jsr pop_number
 lda $d3
 ldx #0
 jmp push_number
status_word:
 lda $90
 ldx #0
 jmp push_number
time_word:
 lda #<$ffde
 sta service_call+1
 lda #>$ffde
 sta service_call+2
 jsr kernal_gate
 jmp push_number
char_out:
 pha
 lda #<$ffd2
 sta service_call+1
 lda #>$ffd2
 sta service_call+2
 pla
 jmp kernal_gate
print_newline:
 lda #13
 jmp char_out
print_comma:
 lda $d3
@loop:
 cmp #30
 bcc @space
 jmp print_newline
@space:
 lda #' '
 jsr char_out
 lda $d3
 cmp #10
 beq @done
 cmp #20
 beq @done
 cmp #30
 bne @loop
@done:
 rts
print_value:
 lda EXPR_TOP
 sec
 sbc #1
 asl
 asl
 tay
 lda EXPR_STACK,y
 JNE print_string
 jsr pop_number
 jsr format_signed
 lda NUM_SIGN
 beq @positive
 lda #'-'
 jsr char_out
 jmp @digits
@positive:
 lda #' '
 jsr char_out
@digits:
 ldy #0
@loop:
 sty NUM_LENGTH
 lda NUM_BUFFER,y
 jsr char_out
 ldy NUM_LENGTH
 iny
 cpy COUNT
 bne @loop
 lda #' '
 jmp char_out
format_signed:
 sta LEFT
 stx LEFT+1
 lda #0
 sta NUM_SIGN
 txa
 bpl format_unsigned
 lda #1
 sta NUM_SIGN
 sec
 lda #0
 sbc LEFT
 sta LEFT
 lda #0
 sbc LEFT+1
 sta LEFT+1
format_unsigned:
 lda #0
 sta COUNT
 sta SCRATCH+9
 ldx #0
@digit:
 lda #0
 sta SCRATCH+10
@subtract:
 sec
 lda LEFT
 sbc powers_lo,x
 tay
 lda LEFT+1
 sbc powers_hi,x
 bcc @store
 sta LEFT+1
 sty LEFT
 inc SCRATCH+10
 jmp @subtract
@store:
 lda SCRATCH+10
 bne @nonzero
 lda SCRATCH+9
 bne @nonzero
 cpx #4
 bne @next
@nonzero:
 inc SCRATCH+9
 lda SCRATCH+10
 clc
 adc #'0'
 ldy COUNT
 sta NUM_BUFFER,y
 inc COUNT
@next:
 inx
 cpx #5
 bne @digit
 rts
powers_lo: .byte <10000,<1000,<100,<10,<1
powers_hi: .byte >10000,>1000,>100,>10,>1
; Strings: immutable owned payloads, descriptors rooted in stack/scalars.
load_string:
 sta PTR
 stx PTR+1
 ldy #0
 lda (PTR),y
 sta STRING_LENGTH
 iny
 lda (PTR),y
 sta STRING_PTR
 iny
 lda (PTR),y
 sta STRING_PTR+1
 jmp push_string
push_string:
 lda EXPR_TOP
 cmp #32
 bcc :+
 lda #ERR_STACK
 jmp runtime_error
:
 asl
 asl
 tay
 lda #1
 sta EXPR_STACK,y
 lda STRING_LENGTH
 sta EXPR_STACK+1,y
 lda STRING_PTR
 sta EXPR_STACK+2,y
 lda STRING_PTR+1
 sta EXPR_STACK+3,y
 inc EXPR_TOP
 rts
pop_string:
 lda EXPR_TOP
 bne :+
 lda #ERR_SYNTAX
 jmp runtime_error
:
 dec EXPR_TOP
 lda EXPR_TOP
 asl
 asl
 tay
 lda EXPR_STACK,y
 bne :+
 lda #ERR_TYPE
 jmp runtime_error
:
 lda EXPR_STACK+1,y
 sta STRING_LENGTH
 lda EXPR_STACK+2,y
 sta STRING_PTR
 lda EXPR_STACK+3,y
 sta STRING_PTR+1
 rts
string_allocate:
 lda STRING_LENGTH
 bne @nonempty
 sta STRING_DEST
 sta STRING_DEST+1
 rts
@nonempty:
 lda STRING_LENGTH
 clc
 adc #2
 ldx #0
 bcc :+
 inx
:
 jsr alloc
 lda ALLOC_RESULT
 ora ALLOC_RESULT+1
 bne @allocated
 jsr collect
 lda STRING_LENGTH
 clc
 adc #2
 ldx #0
 bcc :+
 inx
:
 jsr alloc
 lda ALLOC_RESULT
 ora ALLOC_RESULT+1
 bne @allocated
 lda #ERR_MEMORY
 jmp runtime_error
@allocated:
 lda ALLOC_RESULT
 sta STRING_DEST
 lda ALLOC_RESULT+1
 sta STRING_DEST+1
 rts
push_literal:
 sta STRING_PTR
 stx STRING_PTR+1
 sta PTR
 stx PTR+1
 ldy #0
 lda (PTR),y
 sta STRING_LENGTH
 inc STRING_PTR
 bne :+
 inc STRING_PTR+1
:
 jsr copy_string
 jmp push_string
copy_string:
 jsr string_allocate
 lda STRING_PTR
 sta SOURCE
 lda STRING_PTR+1
 sta SOURCE+1
 lda STRING_DEST
 sta DEST
 lda STRING_DEST+1
 sta DEST+1
 ldy #0
@copy:
 cpy STRING_LENGTH
 beq @done
 lda (SOURCE),y
 sta (DEST),y
 iny
 bne @copy
@done:
 lda STRING_DEST
 sta STRING_PTR
 lda STRING_DEST+1
 sta STRING_PTR+1
 rts
store_string:
 sta STRING_CELL
 stx STRING_CELL+1
 jsr pop_string
 lda STRING_CELL
 sta PTR
 lda STRING_CELL+1
 sta PTR+1
 ldy #0
 lda STRING_LENGTH
 sta (PTR),y
 iny
 lda STRING_PTR
 sta (PTR),y
 iny
 lda STRING_PTR+1
 sta (PTR),y
 iny
 lda #1
 sta (PTR),y
 rts
print_string:
 jsr pop_string
 ldy #0
@loop:
 cpy STRING_LENGTH
 beq @done
 sty NUM_LENGTH
 lda STRING_PTR
 sta PTR
 lda STRING_PTR+1
 sta PTR+1
 lda (PTR),y
 jsr char_out
 ldy NUM_LENGTH
 iny
 bne @loop
@done:
 rts
concat_string:
 jsr pop_string
 lda STRING_LENGTH
 sta FRAME_LIMIT
 lda STRING_PTR
 sta FRAME_STEP
 lda STRING_PTR+1
 sta FRAME_STEP+1
 jsr pop_string
 lda STRING_LENGTH
 sta FRAME_CELL
 clc
 adc FRAME_LIMIT
 bcc :+
 lda #ERR_STRING
 jmp runtime_error
:
 sta STRING_LENGTH
 lda STRING_PTR
 sta STRING_CELL
 lda STRING_PTR+1
 sta STRING_CELL+1
 jsr string_allocate
 lda STRING_DEST
 sta DEST
 lda STRING_DEST+1
 sta DEST+1
 lda STRING_CELL
 sta SOURCE
 lda STRING_CELL+1
 sta SOURCE+1
 ldy #0
@left:
 cpy FRAME_CELL
 beq @right
 lda (SOURCE),y
 sta (DEST),y
 iny
 jmp @left
@right:
 clc
 lda DEST
 adc FRAME_CELL
 sta DEST
 bcc :+
 inc DEST+1
:
 lda FRAME_STEP
 sta SOURCE
 lda FRAME_STEP+1
 sta SOURCE+1
 ldy #0
@right_copy:
 cpy FRAME_LIMIT
 beq @done
 lda (SOURCE),y
 sta (DEST),y
 iny
 jmp @right_copy
@done:
 lda STRING_DEST
 sta STRING_PTR
 lda STRING_DEST+1
 sta STRING_PTR+1
 jmp push_string
len_word:
 jsr pop_string
 lda STRING_LENGTH
 ldx #0
 jmp push_number
asc_word:
 jsr pop_string
 lda STRING_LENGTH
 bne :+
 lda #ERR_QUANTITY
 jmp runtime_error
:
 lda STRING_PTR
 sta PTR
 lda STRING_PTR+1
 sta PTR+1
 ldy #0
 lda (PTR),y
 ldx #0
 jmp push_number
chr_word:
 jsr byte_quantity
 sta BRIDGE
 lda #1
 sta STRING_LENGTH
 lda #<BRIDGE
 sta STRING_PTR
 lda #>BRIDGE
 sta STRING_PTR+1
 jsr copy_string
 jmp push_string
str_word:
 jsr pop_number
 jsr format_signed
 lda NUM_SIGN
 beq @positive
 lda #'-'
 bne @first
@positive:
 lda #' '
@first:
 sta BRIDGE
 ldx #0
@copy:
 lda NUM_BUFFER,x
 sta BRIDGE+1,x
 inx
 cpx COUNT
 bne @copy
 inx
 stx STRING_LENGTH
 lda #<BRIDGE
 sta STRING_PTR
 lda #>BRIDGE
 sta STRING_PTR+1
 jsr copy_string
 jmp push_string
val_word:
 ; Shared word decoder works in native RAM. No floating fallback.
 jsr pop_string
 lda STRING_PTR
 sta SOURCE
 lda STRING_PTR+1
 sta SOURCE+1
 lda #0
 sta LEFT
 sta LEFT+1
 sta NUM_SIGN
 ldy #0
@spaces:
 cpy STRING_LENGTH
 JEQ @done
 lda (SOURCE),y
 cmp #' '
 bne @sign
 iny
 jmp @spaces
@sign:
 cmp #'-'
 bne @plus
 inc NUM_SIGN
 iny
 jmp @radix
@plus:
 cmp #'+'
 bne @radix
 iny
@radix:
 cpy STRING_LENGTH
 JEQ @done
 lda (SOURCE),y
 cmp #'$'
 beq @hex
@decimal:
 cpy STRING_LENGTH
 JEQ @done
 lda (SOURCE),y
 cmp #'0'
 bcc @continuation
 cmp #'9'+1
 bcs @continuation
 sec
 sbc #'0'
 sta TMP
 lda LEFT+1
 cmp #$19
 bcc @mult
 JNE @bad
 lda LEFT
 cmp #$99
 bcc @mult
 JNE @bad
 lda TMP
 cmp #6
 JCS @bad
@mult:
 lda LEFT
 sta VALUE
 lda LEFT+1
 sta VALUE+1
 asl LEFT
 rol LEFT+1
 asl LEFT
 rol LEFT+1
 clc
 lda LEFT
 adc VALUE
 sta LEFT
 lda LEFT+1
 adc VALUE+1
 sta LEFT+1
 asl LEFT
 rol LEFT+1
 clc
 lda LEFT
 adc TMP
 sta LEFT
 bcc :+
 inc LEFT+1
:
 iny
 jmp @decimal
@continuation:
 cmp #'.'
 beq @bad
 cmp #'E'
 beq @bad
 cmp #'e'
 beq @bad
 jmp @done
@hex:
 iny
 lda #0
 sta NUM_LENGTH
@hex_loop:
 cpy STRING_LENGTH
 beq @hex_done
 lda (SOURCE),y
 cmp #'a'
 bcc :+
 cmp #'f'+1
 bcs :+
 and #$df
:
 cmp #'0'
 bcc @hex_done
 cmp #'9'+1
 bcc @hex_dec
 cmp #'A'
 bcc @bad
 cmp #'F'+1
 bcs @bad
 sec
 sbc #'A'-10
 jmp @hex_value
@hex_dec:
 sec
 sbc #'0'
@hex_value:
 pha
 lda NUM_LENGTH
 cmp #4
 pla
 bcs @bad
 asl LEFT
 rol LEFT+1
 asl LEFT
 rol LEFT+1
 asl LEFT
 rol LEFT+1
 asl LEFT
 rol LEFT+1
 ora LEFT
 sta LEFT
 inc NUM_LENGTH
 iny
 jmp @hex_loop
@hex_done:
 lda NUM_LENGTH
 beq @bad
@done:
 lda NUM_SIGN
 beq @positive
 sec
 lda #0
 sbc LEFT
 pha
 lda #0
 sbc LEFT+1
 tax
 pla
 jmp push_number
@positive:
 lda LEFT
 ldx LEFT+1
 jmp push_number
@bad:
 lda #ERR_QUANTITY
 jmp runtime_error
; Tagged raw-PC software control stack; GOSUB3 and FOR9.
control_pointer:
 clc
 lda #<CONTROL_STACK
 adc CONTROL_TOP
 sta CPTR
 lda #>CONTROL_STACK
 adc CONTROL_TOP+1
 sta CPTR+1
 rts
check_control:
 clc
 adc CONTROL_TOP
 sta TMP
 lda CONTROL_TOP+1
 adc #0
 cmp #2
 bcc @ok
 bne @bad
 lda TMP
 beq @ok
@bad:
 lda #ERR_MEMORY
 jmp runtime_error
@ok:
 rts
gosub_word:
 sta ENTRY
 stx ENTRY+1
 pla
 clc
 adc #1
 sta FRAME_PC
 pla
 adc #0
 sta FRAME_PC+1
 lda #3
 jsr check_control
 jsr control_pointer
 ldy #0
 lda #1
 sta (CPTR),y
 iny
 lda FRAME_PC
 sta (CPTR),y
 iny
 lda FRAME_PC+1
 sta (CPTR),y
 clc
 lda CONTROL_TOP
 adc #3
 sta CONTROL_TOP
 bcc :+
 inc CONTROL_TOP+1
:
 jmp (ENTRY)
return_word:
 jsr find_frame
 cmp #0
 beq @missing
 cmp #1
 beq @return
 lda CONTROL_TOP
 ora CONTROL_TOP+1
 bne return_word
@missing:
 lda #ERR_RETURN
 jmp runtime_error
@return:
 ldy #1
 lda (CPTR),y
 sta ENTRY
 iny
 lda (CPTR),y
 sta ENTRY+1
 jmp (ENTRY)
find_frame:
 lda RUNNING
 bne @scan_start
 lda CONTROL_TOP
 cmp FROZEN_TOP
 bne @scan_start
 lda CONTROL_TOP+1
 cmp FROZEN_TOP+1
 bne @scan_start
 lda #0
 rts
@scan_start:
 ; Scan bottom-up to locate the final complete tagged frame.
 lda #0
 sta TMP
 sta TMP+1
@scan:
 lda TMP
 cmp CONTROL_TOP
 bne @frame
 lda TMP+1
 cmp CONTROL_TOP+1
 beq @last
@frame:
 clc
 lda #<CONTROL_STACK
 adc TMP
 sta CPTR
 lda #>CONTROL_STACK
 adc TMP+1
 sta CPTR+1
 lda TMP
 sta FRAME_PC
 lda TMP+1
 sta FRAME_PC+1
 ldy #0
 lda (CPTR),y
 cmp #1
 beq @gosub
 lda #9
 bne @advance
@gosub:
 lda #3
@advance:
 clc
 adc TMP
 sta TMP
 bcc @scan
 inc TMP+1
 jmp @scan
@last:
 lda CONTROL_TOP
 ora CONTROL_TOP+1
 bne :+
 lda #0
 rts
:
 lda FRAME_PC
 sta CONTROL_TOP
 lda FRAME_PC+1
 sta CONTROL_TOP+1
 ldy #0
 lda (CPTR),y
 rts
for_word:
 sta FRAME_CELL
 stx FRAME_CELL+1
 pla
 clc
 adc #1
 sta FRAME_PC
 pla
 adc #0
 sta FRAME_PC+1
 jsr pop_number
 sta FRAME_STEP
 stx FRAME_STEP+1
 jsr pop_number
 sta FRAME_LIMIT
 stx FRAME_LIMIT+1
 jsr pop_number
 sta RIGHT
 stx RIGHT+1
 lda FRAME_CELL
 sta PTR
 lda FRAME_CELL+1
 sta PTR+1
 ldy #0
 lda RIGHT
 sta (PTR),y
 iny
 lda RIGHT+1
 sta (PTR),y
 jsr discard_reused_for
 lda #9
 jsr check_control
 jsr control_pointer
 ldy #0
 lda #2
 sta (CPTR),y
 iny
 lda FRAME_CELL
 sta (CPTR),y
 iny
 lda FRAME_CELL+1
 sta (CPTR),y
 iny
 lda FRAME_LIMIT
 sta (CPTR),y
 iny
 lda FRAME_LIMIT+1
 sta (CPTR),y
 iny
 lda FRAME_STEP
 sta (CPTR),y
 iny
 lda FRAME_STEP+1
 sta (CPTR),y
 iny
 lda FRAME_PC
 sta (CPTR),y
 iny
 lda FRAME_PC+1
 sta (CPTR),y
 clc
 lda CONTROL_TOP
 adc #9
 sta CONTROL_TOP
 bcc :+
 inc CONTROL_TOP+1
:
 jmp (FRAME_PC)
discard_reused_for:
 ; Replace a matching loop in the current subroutine; preserve unrelated frames.
 lda FRAME_PC
 pha
 lda FRAME_PC+1
 pha
 lda CONTROL_TOP
 sta PREV
 lda CONTROL_TOP+1
 sta PREV+1
@search:
 jsr find_frame
 cmp #2
 bne @retain
 ldy #1
 lda (CPTR),y
 cmp FRAME_CELL
 bne @search
 iny
 lda (CPTR),y
 cmp FRAME_CELL+1
 bne @search
 jmp @done
@retain:
 lda PREV
 sta CONTROL_TOP
 lda PREV+1
 sta CONTROL_TOP+1
@done:
 pla
 sta FRAME_PC+1
 pla
 sta FRAME_PC
 rts
next_word:
 sta STRING_CELL
 stx STRING_CELL+1
 pla
 clc
 adc #1
 sta STRING_DEST
 pla
 adc #0
 sta STRING_DEST+1
@find:
 jsr find_frame
 cmp #2
 JNE @bad
 ldy #1
 lda (CPTR),y
 sta PTR
 iny
 lda (CPTR),y
 sta PTR+1
 lda STRING_CELL
 ora STRING_CELL+1
 beq @matched
 lda PTR
 cmp STRING_CELL
 bne @find
 lda PTR+1
 cmp STRING_CELL+1
 bne @find
@matched:
 ldy #3
 lda (CPTR),y
 sta RIGHT
 iny
 lda (CPTR),y
 sta RIGHT+1
 iny
 lda (CPTR),y
 sta FRAME_STEP
 iny
 lda (CPTR),y
 sta FRAME_STEP+1
 iny
 lda (CPTR),y
 sta ENTRY
 iny
 lda (CPTR),y
 sta ENTRY+1
 ldy #0
 clc
 lda (PTR),y
 adc FRAME_STEP
 sta (PTR),y
 sta LEFT
 iny
 lda (PTR),y
 adc FRAME_STEP+1
 sta (PTR),y
 sta LEFT+1
 eor #$80
 sta TMP
 lda RIGHT+1
 eor #$80
 sta TMP+1
 lda TMP
 cmp TMP+1
 bne @direction
 lda LEFT
 cmp RIGHT
@direction:
 php
 lda FRAME_STEP+1
 bmi @negative
 plp
 bcc @continue
 beq @continue
 jmp @done
@negative:
 plp
 bcs @continue
@done:
 jmp (STRING_DEST)
@continue:
 clc
 lda CONTROL_TOP
 adc #9
 sta CONTROL_TOP
 bcc :+
 inc CONTROL_TOP+1
:
 jmp (ENTRY)
@bad:
 lda #ERR_NEXT
 jmp runtime_error
stop_word:
 lda #1
 sta COMMAND
 jmp suspend
stop_end:
 lda #0
 sta COMMAND
suspend:
 lda RUNNING
 bne @program
 lda #0
 sta CONT_PC
 sta CONT_PC+1
 jmp enter_ready
@program:
 lda CONTROL_TOP
 sta FROZEN_TOP
 lda CONTROL_TOP+1
 sta FROZEN_TOP+1
 pla
 clc
 adc #1
 sta CONT_PC
 pla
 adc #0
 sta CONT_PC+1
 lda GENERATION
 sta CONT_GEN
 lda GENERATION+1
 sta CONT_GEN+1
 jmp enter_ready
run_end:
 lda #<run_end
 sta CONT_PC
 lda #>run_end
 sta CONT_PC+1
 lda GENERATION
 sta CONT_GEN
 lda GENERATION+1
 sta CONT_GEN+1
 jmp enter_ready
direct_done:
 lda FROZEN_TOP
 sta CONTROL_TOP
 lda FROZEN_TOP+1
 sta CONTROL_TOP+1
 lda DIRECT_PAYLOAD
 sta PTR
 lda DIRECT_PAYLOAD+1
 sta PTR+1
 ora PTR
 beq @done
 jsr free_block
 lda #0
 sta DIRECT_PAYLOAD
 sta DIRECT_PAYLOAD+1
@done:
 jmp enter_ready
clear_runtime:
 lda NAME_HEAD
 sta WALK
 lda NAME_HEAD+1
 sta WALK+1
@loop:
 lda WALK
 ora WALK+1
 beq @arrays
 ldy #4
 lda #0
@clear:
 sta (WALK),y
 iny
 cpy #8
 bne @clear
 ldy #0
 lda (WALK),y
 tax
 iny
 lda (WALK),y
 sta WALK+1
 stx WALK
 jmp @loop
@arrays:
 lda ARRAY_HEAD
 sta WALK
 lda ARRAY_HEAD+1
 sta WALK+1
@array:
 lda WALK
 ora WALK+1
 beq @functions
 ldy #4
 lda #0
 sta (WALK),y
 iny
 sta (WALK),y
 iny
 sta (WALK),y
 jsr clear_next
 jmp @array
@functions:
 lda FUNCTION_HEAD
 sta WALK
 lda FUNCTION_HEAD+1
 sta WALK+1
@function:
 lda WALK
 ora WALK+1
 beq @done
 ldy #4
 lda #0
 sta (WALK),y
 iny
 sta (WALK),y
 jsr clear_next
 jmp @function
@done:
 rts
clear_next:
 ldy #0
 lda (WALK),y
 tax
 iny
 lda (WALK),y
 sta WALK+1
 stx WALK
 rts
runtime_stamp:
.byte "AB64",4

format_source:
 sta LEFT
 stx LEFT+1
 jmp format_unsigned
on_selector:
 jsr byte_quantity
 sta SELECTOR
 rts
; Array descriptors: next2,ID2,payload2,dimension count,type (0 numeric,1 string).
; Payload: inclusive bounds word[dimensions], then row-major typed elements.
array_setup:
 sta ARRAY_RECORD
 stx ARRAY_RECORD+1
 jsr byte_quantity
 cmp #0
 beq array_bad
 cmp #9
 bcs array_bad
 sta ARRAY_DIMS
 lda ARRAY_RECORD
 sta PTR
 lda ARRAY_RECORD+1
 sta PTR+1
 ldy #7
 lda (PTR),y
 sta ARRAY_TYPE
 lda ARRAY_DIMS
 asl
 sta ARRAY_INDEX
@bounds:
 jsr pop_number
 cpx #$80
 bcs array_bad
 dec ARRAY_INDEX
 dec ARRAY_INDEX
 ldy ARRAY_INDEX
 sta ARRAY_SCRATCH,y
 txa
 sta ARRAY_SCRATCH+1,y
 lda ARRAY_INDEX
 bne @bounds
 rts
array_bad:
 lda #ERR_QUANTITY
 jmp runtime_error
dim_array:
 jsr array_setup
 lda ARRAY_RECORD
 sta PTR
 lda ARRAY_RECORD+1
 sta PTR+1
 ldy #4
 lda (PTR),y
 iny
 ora (PTR),y
 bne array_bad
 jmp allocate_array
allocate_array:
 lda #1
 sta FRAME_LIMIT
 lda #0
 sta FRAME_LIMIT+1
 sta ARRAY_INDEX
@product:
 ldy ARRAY_INDEX
 clc
 lda ARRAY_SCRATCH,y
 adc #1
 sta RIGHT
 lda ARRAY_SCRATCH+1,y
 adc #0
 sta RIGHT+1
 lda FRAME_LIMIT
 sta LEFT
 lda FRAME_LIMIT+1
 sta LEFT+1
 ; Wider checked repeated-doubling product: reject a high-word carry.
 lda #0
 sta VALUE
 sta VALUE+1
 ldx #16
@multiply:
 lsr RIGHT+1
 ror RIGHT
 bcc @shift
 clc
 lda VALUE
 adc LEFT
 sta VALUE
 lda VALUE+1
 adc LEFT+1
 sta VALUE+1
 bcs array_bad
@shift:
 dex
 beq @result
 asl LEFT
 rol LEFT+1
 bcc @multiply
 lda RIGHT
 ora RIGHT+1
 bne array_bad
@result:
 lda VALUE
 sta FRAME_LIMIT
 lda VALUE+1
 sta FRAME_LIMIT+1
 inc ARRAY_INDEX
 inc ARRAY_INDEX
 lda ARRAY_DIMS
 asl
 cmp ARRAY_INDEX
 bne @product
 asl FRAME_LIMIT
 rol FRAME_LIMIT+1
 JCS array_bad
 lda ARRAY_TYPE
 beq @size
 asl FRAME_LIMIT
 rol FRAME_LIMIT+1
 JCS array_bad
@size:
 lda ARRAY_DIMS
 asl
 clc
 adc #2
 clc
 adc FRAME_LIMIT
 pha
 lda FRAME_LIMIT+1
 adc #0
 tax
 pla
 JCS array_bad
 jsr alloc
 lda ALLOC_RESULT
 ora ALLOC_RESULT+1
 bne :+
 lda #ERR_MEMORY
 jmp runtime_error
:
 lda ARRAY_RECORD
 sta PTR
 lda ARRAY_RECORD+1
 sta PTR+1
 ldy #4
 lda ALLOC_RESULT
 sta (PTR),y
 sta DEST
 iny
 lda ALLOC_RESULT+1
 sta (PTR),y
 sta DEST+1
 iny
 lda ARRAY_DIMS
 sta (PTR),y
 ldy #0
 lda ARRAY_DIMS
 asl
 sta COUNT
@copy:
 lda ARRAY_SCRATCH,y
 sta (DEST),y
 iny
 cpy COUNT
 bne @copy
 clc
 lda DEST
 adc COUNT
 sta DEST
 bcc :+
 inc DEST+1
:
 lda FRAME_LIMIT
 sta COUNT
 lda FRAME_LIMIT+1
 sta COUNT+1
 ldy #0
 lda #0
@zero:
 pha
 lda COUNT
 ora COUNT+1
 beq @done
 pla
 sta (DEST),y
 inc DEST
 bne :+
 inc DEST+1
:
 lda COUNT
 bne :+
 dec COUNT+1
:
 dec COUNT
 lda #0
 jmp @zero
@done:
 pla
 rts
array_address:
 lda ARRAY_RECORD
 sta PTR
 lda ARRAY_RECORD+1
 sta PTR+1
 ldy #4
 lda (PTR),y
 sta STRING_DEST
 iny
 lda (PTR),y
 sta STRING_DEST+1
 ora STRING_DEST
 bne @exists
 ; Default dimension 10, retain user indices while constructing default bounds.
 lda ARRAY_DIMS
 asl
 tay
@save_indices:
 dey
 lda ARRAY_SCRATCH,y
 sta BRIDGE+256,y
 tya
 bne @save_indices
 ldy #0
@defaults:
 lda #10
 sta ARRAY_SCRATCH,y
 iny
 lda #0
 sta ARRAY_SCRATCH,y
 iny
 tya
 lsr
 cmp ARRAY_DIMS
 bne @defaults
 jsr allocate_array
 lda ARRAY_DIMS
 asl
 tay
@restore_indices:
 dey
 lda BRIDGE+256,y
 sta ARRAY_SCRATCH,y
 tya
 bne @restore_indices
 jmp array_address
@exists:
 iny
 lda (PTR),y
 cmp ARRAY_DIMS
 JNE array_bad
 lda STRING_DEST
 sta SOURCE
 lda STRING_DEST+1
 sta SOURCE+1
 lda #0
 sta FRAME_LIMIT
 sta FRAME_LIMIT+1
 sta ARRAY_INDEX
@dimension:
 ldy ARRAY_INDEX
 lda ARRAY_SCRATCH+1,y
 cmp (SOURCE),y ; compare high separately below
 iny
 lda ARRAY_SCRATCH,y
 cmp (SOURCE),y
 bcc @within
 JNE array_bad
 dey
 lda ARRAY_SCRATCH,y
 cmp (SOURCE),y
 bcc @within_low
 JNE array_bad
@within_low:
 iny
@within:
 dey
 lda (SOURCE),y
 clc
 adc #1
 sta RIGHT
 iny
 lda (SOURCE),y
 adc #0
 sta RIGHT+1
 lda FRAME_LIMIT
 sta LEFT
 lda FRAME_LIMIT+1
 sta LEFT+1
 jsr multiply_ax
 ldy ARRAY_INDEX
 clc
 adc ARRAY_SCRATCH,y
 sta FRAME_LIMIT
 txa
 adc ARRAY_SCRATCH+1,y
 sta FRAME_LIMIT+1
 inc ARRAY_INDEX
 inc ARRAY_INDEX
 lda ARRAY_DIMS
 asl
 cmp ARRAY_INDEX
 bne @dimension
 asl FRAME_LIMIT
 rol FRAME_LIMIT+1
 lda ARRAY_TYPE
 beq :+
 asl FRAME_LIMIT
 rol FRAME_LIMIT+1
:
 lda ARRAY_DIMS
 asl
 clc
 adc FRAME_LIMIT
 sta FRAME_LIMIT
 bcc :+
 inc FRAME_LIMIT+1
:
 clc
 lda STRING_DEST
 adc FRAME_LIMIT
 sta STRING_CELL
 lda STRING_DEST+1
 adc FRAME_LIMIT+1
 sta STRING_CELL+1
 rts
array_load:
 jsr array_setup
 jsr array_address
 lda STRING_CELL
 sta PTR
 lda STRING_CELL+1
 sta PTR+1
 lda ARRAY_TYPE
 bne @string
 ldy #0
 lda (PTR),y
 pha
 iny
 lda (PTR),y
 tax
 pla
 jmp push_number
@string:
 lda STRING_CELL
 ldx STRING_CELL+1
 jmp load_string
array_store:
 sta ARRAY_RECORD
 stx ARRAY_RECORD+1
 jsr byte_quantity
 sta ARRAY_DIMS
 ; RHS is above subscripts: save its typed value before consuming indices.
 lda EXPR_TOP
 sec
 sbc #1
 asl
 asl
 tax
 ldy #0
@save_rhs:
 lda EXPR_STACK,x
 sta BRIDGE+272,y
 inx
 iny
 cpy #4
 bne @save_rhs
 dec EXPR_TOP
 lda ARRAY_DIMS
 ldx #0
 jsr push_number
 lda ARRAY_RECORD
 ldx ARRAY_RECORD+1
 jsr array_setup
 jsr array_address
 lda EXPR_TOP
 asl
 asl
 tax
 ldy #0
@restore_rhs:
 lda BRIDGE+272,y
 sta EXPR_STACK,x
 inx
 iny
 cpy #4
 bne @restore_rhs
 inc EXPR_TOP
 lda ARRAY_TYPE
 bne @string
 lda STRING_CELL
 ldx STRING_CELL+1
 jmp store_number
@string:
 lda STRING_CELL
 ldx STRING_CELL+1
 jmp store_string
restore_data:
 lda #0
 sta DATA_LINE
 sta DATA_LINE+1
 sta DATA_POS
 sta DATA_ACTIVE
 rts
data_prepare:
 lda DATA_LINE
 ora DATA_LINE+1
 bne @base
 lda PROGRAM_HEAD
 sta DATA_LINE
 lda PROGRAM_HEAD+1
 sta DATA_LINE+1
 lda #0
 sta DATA_POS
 sta DATA_ACTIVE
@base:
 lda DATA_LINE
 cmp #<run_end
 bne :+
 lda DATA_LINE+1
 cmp #>run_end
 bne :+
 lda #ERR_DATA
 jmp runtime_error
:
 lda DATA_LINE
 sta PTR
 lda DATA_LINE+1
 sta PTR+1
 ldy #5
 lda (PTR),y
 sta DATA_TOKEN_PTR
 iny
 lda (PTR),y
 sta DATA_TOKEN_PTR+1
 lda DATA_TOKEN_PTR
 sta PTR
 lda DATA_TOKEN_PTR+1
 sta PTR+1
 ldy #0
 lda (PTR),y
 sta DATA_LIMIT
 inc DATA_TOKEN_PTR
 bne :+
 inc DATA_TOKEN_PTR+1
:
 rts
data_next_line:
 lda DATA_LINE
 sta PTR
 lda DATA_LINE+1
 sta PTR+1
 ldy #5
 lda (PTR),y
 sec
 sbc #2
 sta PTR2
 iny
 lda (PTR),y
 sbc #0
 sta PTR2+1
 ldy #0
 lda (PTR2),y
 clc
 adc PTR2
 sta TMP
 iny
 lda (PTR2),y
 adc PTR2+1
 sta TMP+1
 sec
 lda TMP
 sbc #2 ; final JMP's operand starts at block end-2
 sta PTR
 lda TMP+1
 sbc #0
 sta PTR+1
 ldy #0
 lda (PTR),y
 sta DATA_LINE
 iny
 lda (PTR),y
 sta DATA_LINE+1
 lda #0
 sta DATA_POS
 sta DATA_ACTIVE
 jmp data_prepare
data_peek:
 lda DATA_TOKEN_PTR
 sta PTR
 lda DATA_TOKEN_PTR+1
 sta PTR+1
 ldy DATA_POS
 lda (PTR),y
 rts
data_take:
 jsr data_peek
 inc DATA_POS
 rts
data_skip:
 jsr data_take
 cmp #$10
 beq @one
 cmp #$11
 beq @two
 cmp #$12
 beq @two
 cmp #$19
 beq @two
 cmp #$13
 bcc @done
 cmp #$19
 bcs @done
 jsr data_take
 clc
 adc DATA_POS
 sta DATA_POS
 rts
@two:
 inc DATA_POS
@one:
 inc DATA_POS
@done:
 rts
data_field:
 jsr data_prepare
@search:
 lda DATA_POS
 cmp DATA_LIMIT
 bcc @token
 jsr data_next_line
 jmp @search
@token:
 jsr data_peek
 cmp #$23
 beq @data
 cmp #0
 beq @colon
 lda DATA_ACTIVE
 bne @field
 jsr data_skip
 jmp @search
@colon:
 lda #0
 sta DATA_ACTIVE
 inc DATA_POS
 jmp @search
@data:
 lda #1
 sta DATA_ACTIVE
 inc DATA_POS
 jmp @search
@field:
 jsr data_peek
 cmp #1
 bne @value
 inc DATA_POS
 jmp @search
@value:
 lda #0
 sta DATA_SIGN
 sta IS_HEX
 jsr data_peek
 cmp #5
 bne @minus
 lda #2
 sta DATA_SIGN
 jmp @plus
@minus:
 cmp #6
 bne @body
 lda #1
 sta DATA_SIGN
@plus:
 inc DATA_POS
@body:
 jsr data_take
 cmp #$10
 beq @byte
 cmp #$11
 beq @word
 cmp #$12
 beq @word
 cmp #$70
 bcc @raw
 cmp #$80
 bcs @bad
 sec
 sbc #$70
 sta FRAME_LIMIT
 lda #0
 sta FRAME_LIMIT+1
 jmp @numeric
@byte:
 jsr data_take
 sta FRAME_LIMIT
 lda #0
 sta FRAME_LIMIT+1
 jmp @numeric
@word:
 sta IS_HEX
 jsr data_take
 sta FRAME_LIMIT
 jsr data_take
 sta FRAME_LIMIT+1
@numeric:
 ; Optional original field spelling is a string source, not numeric authority.
 lda #0
 sta READ_TYPE
 lda DATA_POS
 cmp DATA_LIMIT
 bcs @done
 jsr data_peek
 cmp #$16
 bne @done
 inc DATA_POS
 jsr data_take
 sta STRING_LENGTH
 clc
 lda DATA_TOKEN_PTR
 adc DATA_POS
 sta STRING_PTR
 lda DATA_TOKEN_PTR+1
 adc #0
 sta STRING_PTR+1
 clc
 lda DATA_POS
 adc STRING_LENGTH
 sta DATA_POS
 lda #1
 sta READ_TYPE
@done:
 rts
@raw:
 cmp #$13
 beq @text
 cmp #$15
 beq @text
 cmp #$17
 bne @bad
@text:
 jsr data_take
 sta STRING_LENGTH
 clc
 lda DATA_TOKEN_PTR
 adc DATA_POS
 sta STRING_PTR
 lda DATA_TOKEN_PTR+1
 adc #0
 sta STRING_PTR+1
 clc
 lda DATA_POS
 adc STRING_LENGTH
 sta DATA_POS
 lda #2
 sta READ_TYPE
 rts
@bad:
 lda #ERR_SYNTAX
 jmp runtime_error
read_number:
 jsr data_field
 lda READ_TYPE
 cmp #2
 beq @text
 lda DATA_SIGN
 cmp #1
 bne @positive
 sec
 lda #0
 sbc FRAME_LIMIT
 pha
 lda #0
 sbc FRAME_LIMIT+1
 tax
 pla
 jmp push_number
@positive:
 lda FRAME_LIMIT
 ldx FRAME_LIMIT+1
 jmp push_number
@text:
 jsr push_string
 jmp val_word
read_string:
 jsr data_field
 lda READ_TYPE
 bne @copy
 lda IS_HEX
 cmp #$12
 beq read_hex_string
 lda FRAME_LIMIT
 sta LEFT
 lda FRAME_LIMIT+1
 sta LEFT+1
 jsr format_unsigned
 ldx #0
 lda DATA_SIGN
 beq @digits
 lda #'-'
 ldy DATA_SIGN
 cpy #2
 bne :+
 lda #'+'
:
 sta BRIDGE
 inx
@digits:
 ldy #0
@digit:
 lda NUM_BUFFER,y
 sta BRIDGE,x
 inx
 iny
 cpy COUNT
 bne @digit
 stx STRING_LENGTH
 lda #<BRIDGE
 sta STRING_PTR
 lda #>BRIDGE
 sta STRING_PTR+1
@copy:
 jsr copy_string
 jmp push_string
read_hex_string:
 ldx #0
 lda DATA_SIGN
 beq @prefix
 cmp #2
 beq @plus
 lda #'-'
 bne @sign
@plus:
 lda #'+'
@sign:
 sta BRIDGE,x
 inx
@prefix:
 lda #'$'
 sta BRIDGE,x
 inx
 lda FRAME_LIMIT+1
 jsr runtime_hex_byte
 lda FRAME_LIMIT
 jsr runtime_hex_byte
 stx STRING_LENGTH
 lda #<BRIDGE
 sta STRING_PTR
 lda #>BRIDGE
 sta STRING_PTR+1
 jsr copy_string
 jmp push_string
runtime_hex_byte:
 pha
 lsr
 lsr
 lsr
 lsr
 jsr runtime_hex_digit
 pla
 and #15
runtime_hex_digit:
 cmp #10
 bcc :+
 clc
 adc #7
:
 clc
 adc #'0'
 sta BRIDGE,x
 inx
 rts
activate_function:
 ; Inline operands following JSR: record word, parameter-cell word.
 sta FRAME_PC
 stx FRAME_PC+1
 pla
 sta SOURCE
 pla
 sta SOURCE+1
 ldy #1
 lda (SOURCE),y
 sta PTR
 iny
 lda (SOURCE),y
 sta PTR+1
 iny
 lda (SOURCE),y
 sta TMP
 iny
 lda (SOURCE),y
 sta TMP+1
 ldy #4
 lda FRAME_PC
 sta (PTR),y
 iny
 lda FRAME_PC+1
 sta (PTR),y
 iny
 lda TMP
 sta (PTR),y
 iny
 lda TMP+1
 sta (PTR),y
 clc
 lda SOURCE
 adc #5
 sta ENTRY
 lda SOURCE+1
 adc #0
 sta ENTRY+1
 jmp (ENTRY)
fn_word:
 pha
 lda FN_DEPTH
 cmp #8
 bcc :+
 lda #ERR_STACK
 jmp runtime_error
:
 inc FN_DEPTH
 pla
 sta PTR
 stx PTR+1
 ldy #4
 lda (PTR),y
 sta fn_dispatch+1
 iny
 lda (PTR),y
 sta fn_dispatch+2
 ora fn_dispatch+1
 beq fn_undefined
 iny
 lda (PTR),y
 sta STRING_CELL
 iny
 lda (PTR),y
 sta STRING_CELL+1
 jsr pop_number
 sta RIGHT
 stx RIGHT+1
 lda STRING_CELL
 sta PTR
 lda STRING_CELL+1
 sta PTR+1
 ldy #0
 lda (PTR),y
 pha
 iny
 lda (PTR),y
 pha
 lda PTR
 pha
 lda PTR+1
 pha
 ldy #0
 lda RIGHT
 sta (PTR),y
 iny
 lda RIGHT+1
 sta (PTR),y
fn_dispatch:
 jsr $ffff
 dec FN_DEPTH
 sta RIGHT
 stx RIGHT+1
 pla
 sta PTR+1
 pla
 sta PTR
 pla
 ldy #1
 sta (PTR),y
 pla
 dey
 sta (PTR),y
 lda RIGHT
 ldx RIGHT+1
 jmp push_number
fn_undefined:
 lda #ERR_UNDEFINED
 jmp runtime_error

compare_strings:
 jsr pop_string
 lda STRING_PTR
 sta FRAME_STEP
 lda STRING_PTR+1
 sta FRAME_STEP+1
 lda STRING_LENGTH
 sta FRAME_LIMIT
 jsr pop_string
 lda STRING_PTR
 sta SOURCE
 lda STRING_PTR+1
 sta SOURCE+1
 lda FRAME_STEP
 sta DEST
 lda FRAME_STEP+1
 sta DEST+1
 ldy #0
@loop:
 cpy STRING_LENGTH
 beq @length
 cpy FRAME_LIMIT
 beq @length
 lda (SOURCE),y
 cmp (DEST),y
 bne @done
 iny
 bne @loop
@length:
 lda STRING_LENGTH
 cmp FRAME_LIMIT
@done:
 rts
left_word:
 jsr byte_quantity
 sta SELECTOR
 jsr pop_string
 lda SELECTOR
 cmp STRING_LENGTH
 bcs substring_copy
 sta STRING_LENGTH
 jmp substring_copy
right_word:
 jsr byte_quantity
 sta SELECTOR
 jsr pop_string
 lda STRING_LENGTH
 cmp SELECTOR
 bcc substring_copy
 sec
 sbc SELECTOR
 clc
 adc STRING_PTR
 sta STRING_PTR
 bcc :+
 inc STRING_PTR+1
:
 lda SELECTOR
 sta STRING_LENGTH
 jmp substring_copy
mid_word:
 jsr byte_quantity
 sta FRAME_LIMIT
 jsr byte_quantity
 cmp #0
 bne :+
 lda #ERR_QUANTITY
 jmp runtime_error
:
 sec
 sbc #1
 sta SELECTOR
 jsr pop_string
 lda SELECTOR
 cmp STRING_LENGTH
 bcc @within
 lda #0
 sta STRING_LENGTH
 jmp substring_copy
@within:
 lda STRING_LENGTH
 sec
 sbc SELECTOR
 cmp FRAME_LIMIT
 bcc :+
 lda FRAME_LIMIT
:
 sta STRING_LENGTH
 clc
 lda STRING_PTR
 adc SELECTOR
 sta STRING_PTR
 bcc substring_copy
 inc STRING_PTR+1
substring_copy:
 jsr copy_string
 jmp push_string
spc_word:
 jsr byte_quantity
 sta SELECTOR
@loop:
 lda SELECTOR
 beq @done
 lda #' '
 jsr char_out
 dec SELECTOR
 jmp @loop
@done:
 lda #0
 sta STRING_LENGTH
 sta STRING_PTR
 sta STRING_PTR+1
 jmp push_string
tab_word:
 jsr byte_quantity
 sta SELECTOR
 cmp $d3
 bcs :+
 jsr print_newline
:
 lda SELECTOR
 sec
 sbc $d3
 ldx #0
 jsr push_number
 jmp spc_word
usr_word:
 jsr pop_number
 jsr usr_gateway
 jmp push_number
time_string_word:
 lda #<$ffde
 sta service_call+1
 lda #>$ffde
 sta service_call+2
 jsr kernal_gate
 ; Divide 24-bit jiffies by 60, then format HHMMSS into bridge RAM.
 sta FRAME_LIMIT
 stx FRAME_STEP
 sty FRAME_STEP+1
 lda #0
 sta FRAME_CELL
 sta FRAME_CELL+1
 sta SCRATCH+35
@seconds:
 lda FRAME_STEP+1
 ora FRAME_STEP
 bne @subtract
 lda FRAME_LIMIT
 cmp #60
 bcc @format
@subtract:
 sec
 lda FRAME_LIMIT
 sbc #60
 sta FRAME_LIMIT
 lda FRAME_STEP
 sbc #0
 sta FRAME_STEP
 lda FRAME_STEP+1
 sbc #0
 sta FRAME_STEP+1
 inc FRAME_CELL
 bne @seconds
 inc FRAME_CELL+1
 bne @seconds
 inc SCRATCH+35
 jmp @seconds
@format:
 lda #0
 sta FRAME_LIMIT
 sta FRAME_LIMIT+1
@hours:
 sec
 lda FRAME_CELL
 sbc #<3600
 tay
 lda FRAME_CELL+1
 sbc #>3600
 pha
 lda SCRATCH+35
 sbc #0
 bcc @hours_done
 sta SCRATCH+35
 pla
 sty FRAME_CELL
 sta FRAME_CELL+1
 inc FRAME_LIMIT
 jmp @hours
@hours_done:
 pla
@minutes:
 lda FRAME_CELL+1
 bne @minute_sub
 lda FRAME_CELL
 cmp #60
 bcc @write
@minute_sub:
 sec
 lda FRAME_CELL
 sbc #60
 sta FRAME_CELL
 lda FRAME_CELL+1
 sbc #0
 sta FRAME_CELL+1
 inc FRAME_LIMIT+1
 jmp @minutes
@write:
 ldx #0
 lda FRAME_LIMIT
 jsr time_digits
 lda FRAME_LIMIT+1
 jsr time_digits
 lda FRAME_CELL
 jsr time_digits
 lda #6
 sta STRING_LENGTH
 lda #<BRIDGE
 sta STRING_PTR
 lda #>BRIDGE
 sta STRING_PTR+1
 jsr copy_string
 jmp push_string
time_digits:
 ldy #'0'
@tens:
 cmp #10
 bcc @ones
 sec
 sbc #10
 iny
 jmp @tens
@ones:
 clc
 adc #'0'
 sta BRIDGE+1,x
 tya
 sta BRIDGE,x
 inx
 inx
 rts
file_word:
 sta FILE_OPERATION
 jsr byte_quantity
 sta FILE_DEVICE
 cmp #3
 bcs :+
 jmp unsupported_word
:
 jsr pop_string
 lda STRING_LENGTH
 sta FILE_NAME_LEN
 lda STRING_PTR
 sta SOURCE
 lda STRING_PTR+1
 sta SOURCE+1
 ldy #0
@stage:
 cpy FILE_NAME_LEN
 beq @ready
 lda (SOURCE),y
 sta BRIDGE,y
 iny
 bne @stage
@ready:
 jmp file_entry

open_word:
 jsr pop_string
 lda STRING_LENGTH
 sta FILE_NAME_LEN
 lda STRING_PTR
 sta SOURCE
 lda STRING_PTR+1
 sta SOURCE+1
 ldy #0
@name:
 cpy FILE_NAME_LEN
 beq @arguments
 lda (SOURCE),y
 sta BRIDGE,y
 iny
 bne @name
@arguments:
 jsr byte_quantity
 sta DEVICE_SECONDARY
 jsr byte_quantity
 sta DEVICE_NUMBER
 cmp #1
 JEQ unsupported_word
 cmp #2
 JEQ unsupported_word
 jsr byte_quantity
 sta DEVICE_LOGICAL
 lda #<$ffbd
 sta service_call+1
 lda #>$ffbd
 sta service_call+2
 lda FILE_NAME_LEN
 ldx #<BRIDGE
 ldy #>BRIDGE
 jsr kernal_gate
 lda #<$ffba
 sta service_call+1
 lda DEVICE_LOGICAL
 ldx DEVICE_NUMBER
 ldy DEVICE_SECONDARY
 jsr kernal_gate
 lda #<$ffc0
 sta service_call+1
 jsr kernal_gate
 bcc device_ok
device_error:
 lda #ERR_SYNTAX
 jmp runtime_error
device_ok:
 rts
close_word:
 jsr byte_quantity
 pha
 lda #<$ffc3
 sta service_call+1
 lda #>$ffc3
 sta service_call+2
 pla
 jmp kernal_gate
output_channel:
 lda #<$ffc9
 bne select_channel
input_channel:
 lda #<$ffc6
select_channel:
 pha
 jsr byte_quantity
 tax
 pla
 sta service_call+1
 lda #>$ffc6
 sta service_call+2
 jsr kernal_gate
 bcs device_error
 rts
reset_channel:
 lda #<$ffcc
 sta service_call+1
 lda #>$ffcc
 sta service_call+2
 jmp kernal_gate
input_prompt:
 lda #'?'
 jsr char_out
 lda #' '
 jmp char_out
get_number:
 jsr pop_string
 lda STRING_LENGTH
 beq @empty
 lda STRING_PTR
 sta PTR
 lda STRING_PTR+1
 sta PTR+1
 ldy #0
 lda (PTR),y
 cmp #'0'
 bcc @invalid
 cmp #'9'+1
 bcs @invalid
 sec
 sbc #'0'
@empty:
 ldx #0
 jmp push_number
@invalid:
 lda #ERR_QUANTITY
 jmp runtime_error
input_field:
 sta INPUT_KIND
 lda #0
 sta STRING_LENGTH
 sta SELECTOR
@character:
 lda INPUT_KIND
 beq @input
 lda #<$ffe4
 bne @service
@input:
 lda #<$ffcf
@service:
 sta service_call+1
 lda #>$ffcf
 sta service_call+2
 jsr kernal_gate
 cmp #'"'
 bne @delimiter
 lda SELECTOR
 eor #1
 sta SELECTOR
 jmp @character
@delimiter:
 ldx INPUT_KIND
 bne @get
 cmp #13
 beq @done
 ldx SELECTOR
 bne @store
 cmp #','
 beq @done
@store:
 ldx STRING_LENGTH
 cpx #255
 bcs @too_long
 sta BRIDGE,x
 inc STRING_LENGTH
 jmp @character
@get:
 cmp #0
 beq @done
 sta BRIDGE
 inc STRING_LENGTH
@done:
 lda #<BRIDGE
 sta STRING_PTR
 lda #>BRIDGE
 sta STRING_PTR+1
 jsr copy_string
 jmp push_string
@too_long:
 lda #ERR_STRING
 jmp runtime_error

set_time_word:
 jsr pop_string
 lda STRING_LENGTH
 cmp #6
 JNE array_bad
 lda STRING_PTR
 sta SOURCE
 lda STRING_PTR+1
 sta SOURCE+1
 lda #0
 sta CLOCK_VALUE
 sta CLOCK_VALUE+1
 sta CLOCK_VALUE+2
 sta SELECTOR
 ldy #0
@pair:
 lda (SOURCE),y
 jsr clock_digit
 sta TMP
 asl
 asl
 clc
 adc TMP
 asl
 sta TMP
 iny
 lda (SOURCE),y
 jsr clock_digit
 clc
 adc TMP
 ldx SELECTOR
 cpx #0
 bne @minutes
 cmp #24
 JCS array_bad
@minutes:
 cmp #60
 JCS array_bad
 sta NUM_LENGTH
 iny
@add:
 lda NUM_LENGTH
 beq @next
 clc
 lda CLOCK_VALUE
 adc clock_low,x
 sta CLOCK_VALUE
 lda CLOCK_VALUE+1
 adc clock_mid,x
 sta CLOCK_VALUE+1
 lda CLOCK_VALUE+2
 adc clock_high,x
 sta CLOCK_VALUE+2
 dec NUM_LENGTH
 jmp @add
@next:
 inc SELECTOR
 lda SELECTOR
 cmp #3
 bne @pair
 lda #<$ffdb
 sta service_call+1
 lda #>$ffdb
 sta service_call+2
 lda CLOCK_VALUE
 ldx CLOCK_VALUE+1
 ldy CLOCK_VALUE+2
 jmp kernal_gate
clock_digit:
 cmp #'0'
 JCC array_bad
 cmp #'9'+1
 JCS array_bad
 sec
 sbc #'0'
 rts
clock_low: .byte <216000,<3600,<60
clock_mid: .byte <(216000>>8),<(3600>>8),<(60>>8)
clock_high: .byte <(216000>>16),<(3600>>16),<(60>>16)

empty_string:
 lda #0
 sta STRING_LENGTH
 sta STRING_PTR
 sta STRING_PTR+1
 jmp push_string
