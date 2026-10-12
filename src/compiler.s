.segment "COMPILER"
emit:
 pha
 lda EMIT_PASS
 beq @count
 lda CODE_PTR
 sta DEST
 lda CODE_PTR+1
 sta DEST+1
 ldy #0
 pla
 sta (DEST),y
 jmp @increment
@count:
 pla
@increment:
 inc CODE_PTR
 bne :+
 inc CODE_PTR+1
:
 rts
emit_word:
 lda VALUE
 jsr emit
 lda VALUE+1
 jmp emit
emit_call:
 ; A/X fixed helper address.
 sta VALUE
 stx VALUE+1
 cmp #<unsupported_word
 bne @supported
 cpx #>unsupported_word
 bne @supported
 lda #ERR_UNSUPPORTED
 sta COMPILE_ERROR
@supported:
 lda #$20
 jsr emit
 jmp emit_word
emit_jump:
 sta VALUE
 stx VALUE+1
 lda #$4c
 jsr emit
 jmp emit_word
emit_ax:
 ; VALUE word -> LDA #lo / LDX #hi.
 lda #$a9
 jsr emit
 lda VALUE
 jsr emit
 lda #$a2
 jsr emit
 lda VALUE+1
 jmp emit
emit_context:
 lda #$a9
 jsr emit
 lda ANCHOR
 jsr emit
 lda #$8d
 jsr emit
 lda #<CURRENT_LINE
 jsr emit
 lda #>CURRENT_LINE
 jsr emit
 lda #$a9
 jsr emit
 lda ANCHOR+1
 jsr emit
 lda #$8d
 jsr emit
 lda #<(CURRENT_LINE+1)
 jsr emit
 lda #>(CURRENT_LINE+1)
 jsr emit
 lda #$a9
 jsr emit
 lda TOKEN_POS
 jsr emit
 lda #$8d
 jsr emit
 lda #<CURRENT_OFFSET
 jsr emit
 lda #>CURRENT_OFFSET
 jsr emit
 lda #<poll_break
 ldx #>poll_break
 jmp emit_call
compile_payload:
 lda #0
 sta COMPILE_ERROR
 sta TOKEN_POS
@validate_lexemes:
 lda TOKEN_POS
 cmp TOKEN_LEN
 bcs @size
 jsr token_peek
 cmp #$17
 beq @numeric_error
 cmp #$18
 bne @advance
 lda #ERR_SYNTAX
 bne @diagnostic
@numeric_error:
 lda #ERR_QUANTITY
@diagnostic:
 sta COMPILE_ERROR
@advance:
 jsr skip_token
 jmp @validate_lexemes
@size:
 lda #0
 sta EMIT_PASS
 sta CODE_PTR
 sta CODE_PTR+1
 jsr compile_body
 lda CODE_PTR
 sta CODE_SIZE
 lda CODE_PTR+1
 sta CODE_SIZE+1
 clc
 lda CODE_SIZE
 adc TOKEN_LEN
 sta SIZE
 lda CODE_SIZE+1
 adc #0
 sta SIZE+1
 clc
 lda SIZE
 adc #3
 tax
 lda SIZE+1
 adc #0
 tay
 txa
 pha
 tya
 tax
 pla
 jsr command_alloc
 lda ALLOC_RESULT
 sta NEW_PAYLOAD
 sta DEST
 lda ALLOC_RESULT+1
 sta NEW_PAYLOAD+1
 sta DEST+1
 ldy #0
 lda TOKEN_LEN
 sta (DEST),y
 ldx #0
@copy:
 iny
 lda TOKENS,x
 sta (DEST),y
 inx
 cpx TOKEN_LEN
 bne @copy
 clc
 lda NEW_PAYLOAD
 adc TOKEN_LEN
 sta CODE_PTR
 lda NEW_PAYLOAD+1
 adc #0
 sta CODE_PTR+1
 inc CODE_PTR
 bne :+
 inc CODE_PTR+1
:
 lda #1
 sta EMIT_PASS
 jsr compile_body
 rts
compile_body:
 tsx
 stx COMPILER_SP
 lda #0
 sta IF_COUNT
 sta IF_PENDING
 sta TOKEN_POS
 sta PARSE_DEPTH
 sta IF_PATCH
 sta IF_PATCH+1
@statement:
 jsr emit_context
 jsr compile_statement
@after_statement:
 bcs @trailer
 lda TOKEN_POS
 cmp TOKEN_LEN
 bcs @trailer
 jsr token_peek
 cmp #$68
 beq @else
 cmp #0
 bne @syntax
 inc TOKEN_POS
 jmp @statement
@else:
 inc TOKEN_POS
 jsr compile_else
 jmp @after_statement
@syntax:
 lda #ERR_SYNTAX
 jsr emit_trap
@trailer:
 jmp compile_tail
compile_recover:
 lda #ERR_SYNTAX
compile_abort:
 ldx COMPILER_SP
 txs
 jsr emit_trap
compile_tail:
 lda EMIT_PASS
 beq @emit_tail
 ldx #0
@patch:
 cpx IF_COUNT
 beq @emit_tail
 lda LEX_BUFFER+128,x
 sta DEST
 inx
 lda LEX_BUFFER+128,x
 sta DEST+1
 inx
 ldy #0
 lda CODE_PTR
 sta (DEST),y
 iny
 lda CODE_PTR+1
 sta (DEST),y
 jmp @patch
@emit_tail:
 lda SUCCESSOR
 ldx SUCCESSOR+1
 jmp emit_jump
emit_trap:
 sta COMPILE_ERROR
 pha
 lda #$a9
 jsr emit
 pla
 jsr emit
 lda #<runtime_error
 ldx #>runtime_error
 jsr emit_call
 sec
 rts
token_peek:
 ldx TOKEN_POS
 cpx TOKEN_LEN
 bcs @end
 lda TOKENS,x
 rts
@end:
 lda #$ff
 rts
token_take:
 jsr token_peek
 inc TOKEN_POS
 ora #0
 rts
expect:
 sta SCRATCH+6
 jsr token_take
 cmp SCRATCH+6
 beq :+
 jmp compile_recover
:
 rts
parse_immediate:
 jsr token_take
 cmp #$70
 bcc @extended
 cmp #$80
 bcs @bad
 sec
 sbc #$70
 sta VALUE
 lda #0
 sta VALUE+1
 clc
 rts
@extended:
 cmp #$10
 beq @byte
 cmp #$11
 beq @word
 cmp #$12
 beq @word
@bad:
 sec
 rts
@byte:
 jsr token_take
 sta VALUE
 lda #0
 sta VALUE+1
 clc
 rts
@word:
 jsr token_take
 sta VALUE
 jsr token_take
 sta VALUE+1
 clc
 rts
parse_name:
 jsr token_take
 cmp #$19
 beq @extended
 cmp #$80
 bcc @bad
 sec
 sbc #$80
 sta VALUE
 lda #0
 sta VALUE+1
 jmp bind_name
@extended:
 jsr token_take
 sta VALUE
 jsr token_take
 sta VALUE+1
 jmp bind_name
@bad:
 jmp compile_recover
parse_target:
 jsr token_peek
 cmp #$12
 beq @bad
 jsr parse_immediate
 bcs @bad
 lda VALUE+1
 cmp #$fa
 bcs @bad
 lda LINE_NO
 pha
 lda LINE_NO+1
 pha
 lda ANCHOR
 pha
 lda ANCHOR+1
 pha
 lda VALUE
 sta LINE_NO
 lda VALUE+1
 sta LINE_NO+1
 jsr find_anchor
 lda ANCHOR
 sta TARGET
 lda ANCHOR+1
 sta TARGET+1
 pla
 sta ANCHOR+1
 pla
 sta ANCHOR
 pla
 sta LINE_NO+1
 pla
 sta LINE_NO
 rts
@bad:
 jmp compile_recover
compile_statement:
 jsr token_peek
 cmp #$28 ; LET
 bne :+
 inc TOKEN_POS
 jmp compile_assignment
:
 cmp #$80
 JCS compile_assignment
 cmp #$19
 JEQ compile_assignment
 jsr token_take
 cmp #$39
 JEQ compile_print
 cmp #$6a
 JEQ compile_reserve
 cmp #$37
 JEQ compile_poke
 cmp #$29
 JEQ compile_goto
 cmp #$2d
 JEQ compile_gosub
 cmp #$2e
 JEQ compile_return
 cmp #$2b
 JEQ compile_if
 cmp #$68
 JEQ compile_else
 cmp #$20
 JEQ compile_end
 cmp #$30
 JEQ compile_stop
 cmp #$2f
 JEQ compile_rem
 cmp #$23
 JEQ compile_data
 cmp #$3e
 JEQ compile_sys
 cmp #$21
 JEQ compile_for
 cmp #$22
 JEQ compile_next
 cmp #$32
 JEQ compile_wait
 cmp #$3c
 JEQ compile_clr
 cmp #$26
 JEQ compile_dim
 cmp #$31
 JEQ compile_on
 cmp #$27
 JEQ compile_read
 cmp #$2c
 JEQ compile_restore
 cmp #$36
 JEQ compile_def
 cmp #$33
 JEQ compile_file
 cmp #$34
 JEQ compile_file
 cmp #$35
 JEQ compile_file
 cmp #$3f
 JEQ compile_open
 cmp #$40
 JEQ compile_close
 cmp #$38
 JEQ compile_print_channel
 cmp #$3d
 JEQ compile_cmd
 cmp #$25
 JEQ compile_input
 cmp #$24
 JEQ compile_input_channel
 cmp #$41
 JEQ compile_get
 cmp #$42
 JEQ compile_get_channel
 cmp #$66
 JEQ compile_set_time
 lda #ERR_UNSUPPORTED
 jmp emit_trap
compile_assignment:
 jsr parse_name
 php
 jsr token_peek
 cmp #3
 beq @array
 plp
 php
 lda CELL
 pha
 lda CELL+1
 pha
 lda #10
 jsr expect
 lda #0
 jsr expression
 pla
 sta VALUE+1
 pla
 sta VALUE
 jsr emit_ax
 plp
 beq @string
 lda #<store_number
 ldx #>store_number
 jsr emit_call
 clc
 rts
@string:
 lda #<store_string
 ldx #>store_string
 jsr emit_call
 clc
 rts
@array:
 plp
 jsr bind_array
 lda CELL
 pha
 lda CELL+1
 pha
 jsr parse_subscripts
 lda ARRAY_DIMS
 pha
 lda #10
 jsr expect
 lda #0
 jsr expression
 pla
 sta VALUE
 lda #0
 sta VALUE+1
 jsr emit_ax
 lda #<push_number
 ldx #>push_number
 jsr emit_call
 pla
 sta VALUE+1
 pla
 sta VALUE
 jsr emit_ax
 lda #<array_store
 ldx #>array_store
 jsr emit_call
 clc
 rts
compile_poke:
 lda #0
 jsr expression
 lda #1
 jsr expect
 lda #0
 jsr expression
 lda #<poke_word
 ldx #>poke_word
 jsr emit_call
 clc
 rts
compile_sys:
 lda #0
 jsr expression
 lda #<sys_word
 ldx #>sys_word
 jsr emit_call
 clc
 rts
compile_wait:
 lda #0
 jsr expression
 lda #1
 jsr expect
 lda #0
 jsr expression
 jsr token_peek
 cmp #1
 bne @zero
 inc TOKEN_POS
 lda #0
 jsr expression
 jmp @call
@zero:
 lda #0
 sta VALUE
 sta VALUE+1
 jsr emit_ax
 lda #<push_number
 ldx #>push_number
 jsr emit_call
@call:
 lda #<wait_word
 ldx #>wait_word
 jsr emit_call
 clc
 rts
compile_goto:
 jsr parse_target
 lda TARGET
 ldx TARGET+1
 jsr emit_jump
 clc
 rts
compile_gosub:
 jsr parse_target
 lda TARGET
 sta VALUE
 lda TARGET+1
 sta VALUE+1
 jsr emit_ax
 lda #<gosub_word
 ldx #>gosub_word
 jsr emit_call
 jsr emit_context
 clc
 rts
compile_return:
 lda #<return_word
 ldx #>return_word
 jsr emit_jump
 clc
 rts
compile_end:
 lda #<stop_end
 ldx #>stop_end
 jsr emit_call
 clc
 rts
compile_stop:
 lda #<stop_word
 ldx #>stop_word
 jsr emit_call
 jsr emit_context
 clc
 rts
compile_rem:
 lda TOKEN_LEN
 sta TOKEN_POS
 clc
 rts
compile_data:
@skip:
 jsr token_peek
 cmp #0
 beq @done
 lda TOKEN_POS
 cmp TOKEN_LEN
 bcs @done
 jsr skip_token
 jmp @skip
@done:
 clc
 rts
skip_token:
 jsr token_take
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
 jsr token_take
 clc
 adc TOKEN_POS
 sta TOKEN_POS
 rts
@two:
 inc TOKEN_POS
@one:
 inc TOKEN_POS
@done:
 rts
compile_if:
 lda #0
 jsr expression
 jsr token_take
 cmp #$48
 beq @then
 cmp #$29
 beq @goto
 lda #ERR_SYNTAX
 jmp emit_trap
@then:
 jsr emit_if_test
 jmp conditional_body
@goto:
 jsr emit_if_test
 jmp compile_goto
conditional_body:
 jsr token_peek
 cmp #$70
 bcc @decimal
 cmp #$80
 JCC compile_goto
 jmp compile_statement
@decimal:
 cmp #$10
 JEQ compile_goto
 cmp #$11
 JEQ compile_goto
 jmp compile_statement
compile_else:
 ldx IF_PENDING
 beq @bad
 dex
 stx IF_PENDING
 lda LEX_BUFFER+64,x
 pha
 lda #$4c
 jsr emit
 lda CODE_PTR
 sta IF_PATCH
 lda CODE_PTR+1
 sta IF_PATCH+1
 lda #0
 jsr emit
 lda #0
 jsr emit
 pla
 tax
 lda EMIT_PASS
 beq @replace
 lda LEX_BUFFER+128,x
 sta DEST
 lda LEX_BUFFER+129,x
 sta DEST+1
 ldy #0
 lda CODE_PTR
 sta (DEST),y
 iny
 lda CODE_PTR+1
 sta (DEST),y
@replace:
 lda IF_PATCH
 sta LEX_BUFFER+128,x
 lda IF_PATCH+1
 sta LEX_BUFFER+129,x
 jmp conditional_body
@bad:
 lda #ERR_SYNTAX
 jmp emit_trap
emit_if_test:
 ldx IF_PENDING
 cpx #32
 bcs @complex
 lda IF_COUNT
 cmp #128
 bcs @complex
 lda #<pop_number
 ldx #>pop_number
 jsr emit_call
 lda #$86
 jsr emit
 lda #RIGHT+1
 jsr emit
 lda #$05
 jsr emit
 lda #RIGHT+1
 jsr emit
 lda #$d0
 jsr emit
 lda #3
 jsr emit
 lda #$4c
 jsr emit
 ldx IF_PENDING
 lda IF_COUNT
 sta LEX_BUFFER+64,x
 inc IF_PENDING
 tax
 lda CODE_PTR
 sta LEX_BUFFER+128,x
 inx
 lda CODE_PTR+1
 sta LEX_BUFFER+128,x
 inx
 stx IF_COUNT
 lda #0
 jsr emit
 lda #0
 jmp emit
@complex:
 lda #ERR_STACK
 jmp compile_abort
compile_print:
 lda #0
 sta PRINT_LAST
@item:
 jsr token_peek
 cmp #$68
 beq @done
 cmp #0
 beq @done
 lda TOKEN_POS
 cmp TOKEN_LEN
 bcs @done
 jsr token_peek
 cmp #1
 beq @comma
 cmp #2
 beq @semi
 lda #0
 jsr expression
 lda #<print_value
 ldx #>print_value
 jsr emit_call
 lda #0
 sta PRINT_LAST
 jmp @item
@comma:
 inc TOKEN_POS
 lda #<print_comma
 ldx #>print_comma
 jsr emit_call
 lda #1
 sta PRINT_LAST
 jmp @item
@semi:
 inc TOKEN_POS
 lda #1
 sta PRINT_LAST
 jmp @item
@done:
 lda PRINT_LAST
 bne @return
 lda #<print_newline
 ldx #>print_newline
 jsr emit_call
@return:
 clc
 rts
compile_clr:
 lda #<clear_runtime
 ldx #>clear_runtime
 jsr emit_call
 clc
 rts
compile_for:
 jsr parse_name
 beq @type
 lda CELL
 pha
 lda CELL+1
 pha
 lda #10
 jsr expect
 lda #0
 jsr expression
 lda #$45
 jsr expect
 lda #0
 jsr expression
 jsr token_peek
 cmp #$4a
 bne @step_one
 inc TOKEN_POS
 lda #0
 jsr expression
 jmp @call
@step_one:
 lda #1
 sta VALUE
 lda #0
 sta VALUE+1
 jsr emit_ax
 lda #<push_number
 ldx #>push_number
 jsr emit_call
@call:
 pla
 sta VALUE+1
 pla
 sta VALUE
 jsr emit_ax
 lda #<for_word
 ldx #>for_word
 jsr emit_call
 jsr emit_context
 clc
 rts
@type:
 lda #ERR_TYPE
 jmp emit_trap
compile_next:
 jsr token_peek
 cmp #$80
 bcs @named
 cmp #$19
 beq @named
 lda #0
 sta VALUE
 sta VALUE+1
 jmp @call
@named:
 jsr parse_name
 lda CELL
 sta VALUE
 lda CELL+1
 sta VALUE+1
@call:
 jsr emit_ax
 lda #<next_word
 ldx #>next_word
 jsr emit_call
 jsr token_peek
 cmp #1
 bne @done
 inc TOKEN_POS
 jmp compile_next
@done:
 clc
 rts
; Pratt precedence parser. Min/op locals indexed by PARSE_DEPTH in LEX_BUFFER.
expression:
 ldx PARSE_DEPTH
 cpx #32
 bcc :+
 lda #ERR_STACK
 jmp emit_trap
:
 sta LEX_BUFFER,x
 inc PARSE_DEPTH
 jsr optimize_left_power
 bcs @operator
 jsr primary
@operator:
 jsr token_peek
 jsr precedence
 bcc @done
 ldx PARSE_DEPTH
 dex
 cmp LEX_BUFFER,x
 bcc @done
 sta LEX_BUFFER+32,x
 jsr token_take
 ldx PARSE_DEPTH
 dex
 sta OP_STACK,x
 jsr optimize_power
 bcs @operator
 ldx PARSE_DEPTH
 dex
 lda LEX_BUFFER+32,x
 clc
 adc #1 ; BASIC binary operators, including power, associate left.
 jsr expression
 ldx PARSE_DEPTH
 dex
 lda OP_STACK,x
 jsr emit_operator
 jmp @operator
@done:
 dec PARSE_DEPTH
 rts
parse_constant:
 ; Recognize a binary immediate with optional redundant parentheses/unary plus.
 lda #0
 sta SCRATCH+45
@open:
 jsr token_peek
 cmp #5
 beq @plus
 cmp #3
 bne @number
 inc SCRATCH+45
@plus:
 inc TOKEN_POS
 jmp @open
@number:
 jsr parse_immediate
 bcs @done
@close:
 lda SCRATCH+45
 beq @ok
 jsr token_take
 cmp #4
 bne @bad
 dec SCRATCH+45
 jmp @close
@ok:
 clc
@done:
 rts
@bad:
 sec
 rts
optimize_left_power:
 ldx PARSE_DEPTH
 dex
 lda LEX_BUFFER,x
 cmp #8
 bcs @no
 lda TOKEN_POS
 pha
 jsr parse_constant
 bcs @restore
 jsr token_peek
 cmp #7
 bne @restore
 lda VALUE
 ora VALUE+1
 beq @restore
 lda #0
 sta SCRATCH+44
@bit:
 lsr VALUE+1
 ror VALUE
 bcs @one
 inc SCRATCH+44
 jmp @bit
@one:
 lda VALUE
 ora VALUE+1
 bne @restore
 pla
 inc TOKEN_POS
 lda SCRATCH+44
 pha
 lda #8
 jsr expression
 pla
 sta VALUE
 lda #0
 sta VALUE+1
 jsr emit_ax
 lda #<push_number
 ldx #>push_number
 jsr emit_call
 lda #<shift_left_word
 ldx #>shift_left_word
 jsr emit_call
 sec
 rts
@restore:
 pla
 sta TOKEN_POS
@no:
 clc
 rts
optimize_power:
 ; Only fold a complete literal RHS: a tighter operator must remain in Pratt.
 lda OP_STACK,x
 cmp #7
 beq @try
 cmp #8
 bne @no
@try:
 lda TOKEN_POS
 pha
 jsr parse_constant
 bcs @restore
 lda VALUE
 ora VALUE+1
 beq @restore
 lda #0
 sta SCRATCH+44
@bit:
 lsr VALUE+1
 ror VALUE
 bcs @one
 inc SCRATCH+44
 jmp @bit
@one:
 lda VALUE
 ora VALUE+1
 bne @restore
 jsr token_peek
 jsr precedence
 bcc @fold
 ldx PARSE_DEPTH
 dex
 cmp LEX_BUFFER+32,x
 beq @fold
 bcs @restore
@fold:
 pla
 lda SCRATCH+44
 sta VALUE
 lda #0
 sta VALUE+1
 jsr emit_ax
 lda #<push_number
 ldx #>push_number
 jsr emit_call
 ldx PARSE_DEPTH
 dex
 lda OP_STACK,x
 cmp #7
 beq @multiply
 lda SCRATCH+44
 cmp #15
 beq @negative_divisor
 lda #<divide_power_word
 ldx #>divide_power_word
 bne @emit
@negative_divisor:
 lda #<divide_negative_power_word
 ldx #>divide_negative_power_word
 bne @emit
@multiply:
 lda #<shift_left_word
 ldx #>shift_left_word
@emit:
 jsr emit_call
 sec
 rts
@restore:
 pla
 sta TOKEN_POS
@no:
 clc
 rts
precedence:
 cmp #$1a
 beq @shift
 cmp #$1b
 beq @shift
 cmp #$4c
 beq @or
 cmp #$4b
 beq @and
 cmp #10
 bcc @arithmetic
 cmp #16
 bcc @compare
 clc
 rts
@arithmetic:
 cmp #5
 beq @add
 cmp #6
 beq @add
 cmp #7
 beq @multiply
 cmp #8
 beq @multiply
 cmp #9
 beq @power
 clc
 rts
@or: lda #1
 sec
 rts
@and: lda #2
 sec
 rts
@compare: lda #4
 sec
 rts
@shift: lda #5
 sec
 rts
@add: lda #6
 sec
 rts
@multiply: lda #7
 sec
 rts
@power: lda #9
 sec
 rts
primary:
 lda TOKEN_POS
 cmp TOKEN_LEN
 JCS compile_recover
 jsr token_peek
 cmp #5
 JEQ @plus
 cmp #6
 JEQ @minus
 cmp #$49
 JEQ @not
 cmp #3
 JEQ @paren
 cmp #$13
 JEQ @string
 cmp #$80
 JCS @name
 cmp #$19
 JEQ @name
 cmp #$10
 bcc @function
 cmp #$13
 JCC @number
 cmp #$1a
 JCC @bad_literal
 cmp #$70
 bcc @function
 cmp #$80
 JCC @number
@function:
 jsr token_peek
 cmp #$44
 JEQ compile_tab
 cmp #$47
 JEQ compile_spc
 cmp #$61
 JEQ compile_substring
 cmp #$62
 JEQ compile_substring
 cmp #$63
 JEQ compile_substring
 cmp #$46
 JEQ compile_fn
 jsr token_take
 sta SCRATCH+7
 cmp #$4d
 JCC @bad
 cmp #$64
 bcs @special
 pha
 lda #3
 jsr expect
 lda SCRATCH+7
 cmp #$51 ; FRE accepts both FRE() and the compatible FRE(argument).
 bne @argument
 jsr token_peek
 cmp #4
 bne @argument
 inc TOKEN_POS
 pla
 lda #<fre_collect_word
 ldx #>fre_collect_word
 jmp emit_call
@argument:
 lda #0
 jsr expression
 lda #4
 jsr expect
 pla
 sec
 sbc #$4d
 asl
 tax
 lda function_table,x
 pha
 lda function_table+1,x
 tax
 pla
 jmp emit_call
@special:
 cmp #$64
 beq @status
 cmp #$65
 beq @time
 cmp #$66
 beq @time_string
 jmp @bad
@status:
 lda #<status_word
 ldx #>status_word
 jmp emit_call
@time:
 lda #<time_word
 ldx #>time_word
 jmp emit_call
@time_string:
 lda #<time_string_word
 ldx #>time_string_word
 jmp emit_call
@plus:
 inc TOKEN_POS
 lda #8
 jmp expression
@minus:
 inc TOKEN_POS
 lda #8
 jsr expression
 lda #<negate_word
 ldx #>negate_word
 jmp emit_call
@not:
 inc TOKEN_POS
 lda #3
 jsr expression
 lda #<not_word
 ldx #>not_word
 jmp emit_call
@paren:
 inc TOKEN_POS
 lda #0
 jsr expression
 lda #4
 jmp expect
@number:
 jsr parse_immediate
 jsr emit_ax
 lda #<push_number
 ldx #>push_number
 jmp emit_call
@name:
 jsr parse_name
 php
 jsr token_peek
 cmp #3
 beq @array
 plp
 beq @string_name
 lda #$ad
 jsr emit
 lda CELL
 sta VALUE
 lda CELL+1
 sta VALUE+1
 jsr emit_word
 lda #$ae
 jsr emit
 inc VALUE
 bne :+
 inc VALUE+1
:
 jsr emit_word
 lda NAME_KIND
 beq @signed_name
 lda #<push_unsigned
 ldx #>push_unsigned
 jmp emit_call
@signed_name:
 lda #<push_number
 ldx #>push_number
 jmp emit_call
@array:
 plp
 jsr bind_array
 lda CELL
 pha
 lda CELL+1
 pha
 jsr parse_subscripts
 lda ARRAY_DIMS
 sta VALUE
 lda #0
 sta VALUE+1
 jsr emit_ax
 lda #<push_number
 ldx #>push_number
 jsr emit_call
 pla
 sta VALUE+1
 pla
 sta VALUE
 jsr emit_ax
 lda #<array_load
 ldx #>array_load
 jmp emit_call
@string_name:
 lda CELL
 sta VALUE
 lda CELL+1
 sta VALUE+1
 jsr emit_ax
 lda #<load_string
 ldx #>load_string
 jmp emit_call
@string:
 inc TOKEN_POS
 lda TOKEN_POS
 pha
 jsr token_take
 clc
 adc TOKEN_POS
 sta TOKEN_POS
 pla
 clc
 adc NEW_PAYLOAD
 sta VALUE
 lda NEW_PAYLOAD+1
 adc #0
 sta VALUE+1
 inc VALUE ; payload+1+token length-byte offset
 bne :+
 inc VALUE+1
:
 jsr emit_ax
 lda #<push_literal
 ldx #>push_literal
 jmp emit_call
@bad_literal:
 jsr skip_token
 lda #ERR_QUANTITY
 jmp emit_trap
@bad:
 lda #ERR_UNSUPPORTED
 jmp emit_trap
emit_operator:
 cmp #$1a
 beq @left
 cmp #$1b
 beq @right
 cmp #$4b
 beq @and
 cmp #$4c
 beq @or
 sec
 sbc #5
 asl
 tax
 lda operator_table,x
 pha
 lda operator_table+1,x
 tax
 pla
 jmp emit_call
@and:
 lda #<and_word
 ldx #>and_word
 jmp emit_call
@or:
 lda #<or_word
 ldx #>or_word
 jmp emit_call
@left:
 lda #<shift_left_word
 ldx #>shift_left_word
 jmp emit_call
@right:
 lda #<shift_right_word
 ldx #>shift_right_word
 jmp emit_call
operator_table:
.word add_word_runtime, subtract_word, multiply_word, divide_word, power_word
.word equal_word, less_word, greater_word, le_word, ge_word, ne_word
function_table:
.word sgn_word,int_word,abs_word,usr_word,fre_word,pos_word
.word unsupported_word,rnd_word,unsupported_word,unsupported_word
.word unsupported_word,unsupported_word,unsupported_word,unsupported_word
.word peek_word,len_word,str_word,val_word,asc_word,chr_word
.word unsupported_word,unsupported_word,unsupported_word

.segment "COMPILER"
compile_dim:
 jsr parse_name
 jsr bind_array
 lda CELL
 pha
 lda CELL+1
 pha
 jsr parse_subscripts
 lda ARRAY_DIMS
 sta VALUE
 lda #0
 sta VALUE+1
 jsr emit_ax
 lda #<push_number
 ldx #>push_number
 jsr emit_call
 pla
 sta VALUE+1
 pla
 sta VALUE
 jsr emit_ax
 lda #<dim_array
 ldx #>dim_array
 jsr emit_call
 jsr token_peek
 cmp #1
 bne @done
 inc TOKEN_POS
 jmp compile_dim
@done:
 clc
 rts
parse_subscripts:
 lda #3
 jsr expect
 lda #0
 pha
@dimension:
 lda #0
 jsr expression
 pla
 clc
 adc #1
 cmp #9
 bcc :+
 lda #ERR_QUANTITY
 jmp command_error
:
 pha
 jsr token_peek
 cmp #1
 bne @end
 inc TOKEN_POS
 jmp @dimension
@end:
 lda #4
 jsr expect
 pla
 sta ARRAY_DIMS
 rts
compile_on:
 lda #0
 jsr expression
 lda #<on_selector
 ldx #>on_selector
 jsr emit_call
 jsr token_take
 cmp #$29
 beq @goto
 cmp #$2d
 beq @gosub
 lda #ERR_SYNTAX
 jmp emit_trap
@goto:
 lda #0
 beq @start
@gosub:
 lda #1
@start:
 pha
 lda #1
 pha
@target:
 jsr parse_target
 lda #$ad
 jsr emit
 lda #<SELECTOR
 jsr emit
 lda #>SELECTOR
 jsr emit
 lda #$c9
 jsr emit
 pla
 pha
 jsr emit
 lda #$d0
 jsr emit
 pla
 sta SCRATCH+23
 pla
 pha
 cmp #0
 beq @jump
 lda #7
 jsr emit
 lda TARGET
 sta VALUE
 lda TARGET+1
 sta VALUE+1
 jsr emit_ax
 lda #<gosub_word
 ldx #>gosub_word
 jsr emit_call
 jmp @next
@jump:
 lda #3
 jsr emit
 lda TARGET
 ldx TARGET+1
 jsr emit_jump
@next:
 lda SCRATCH+23
 clc
 adc #1
 pha
 jsr token_peek
 cmp #1
 bne @done
 inc TOKEN_POS
 jmp @target
@done:
 pla
 pla
 jsr emit_context
 clc
 rts

compile_read:
 jsr parse_name
 php
 jsr token_peek
 cmp #3
 JEQ compile_read_array
 plp
 php
 lda CELL
 sta SCRATCH+30
 lda CELL+1
 sta SCRATCH+31
 plp
 beq @string
 lda #<read_number
 ldx #>read_number
 jsr emit_call
 lda SCRATCH+30
 sta VALUE
 lda SCRATCH+31
 sta VALUE+1
 jsr emit_ax
 lda #<store_number
 ldx #>store_number
 jsr emit_call
 jmp @next
@string:
 lda #<read_string
 ldx #>read_string
 jsr emit_call
 lda SCRATCH+30
 sta VALUE
 lda SCRATCH+31
 sta VALUE+1
 jsr emit_ax
 lda #<store_string
 ldx #>store_string
 jsr emit_call
@next:
 jsr token_peek
 cmp #1
 bne @done
 inc TOKEN_POS
 jmp compile_read
@done:
 clc
 rts
compile_restore:
 lda #<restore_data
 ldx #>restore_data
 jsr emit_call
 clc
 rts

compile_def:
 lda #$46
 jsr expect
 jsr parse_name
 JEQ @type
 jsr bind_function
 lda FUNCTION_RECORD
 pha
 lda FUNCTION_RECORD+1
 pha
 lda #3
 jsr expect
 jsr parse_name
 JEQ @type
 lda CELL
 sta FUNCTION_PARAMETER
 lda CELL+1
 sta FUNCTION_PARAMETER+1
 lda #4
 jsr expect
 lda #10
 jsr expect
 pla
 sta FUNCTION_RECORD+1
 pla
 sta FUNCTION_RECORD
 ; Definition: publish native entry and parameter cell, then jump over body.
 lda #$a9
 jsr emit
 clc
 lda CODE_PTR
 adc #0
 sta SCRATCH+32
 lda CODE_PTR+1
 adc #0
 sta SCRATCH+33
 lda SCRATCH+32
 jsr emit
 lda #$a2
 jsr emit
 lda SCRATCH+33
 jsr emit
 lda #<activate_function
 ldx #>activate_function
 jsr emit_call
 lda FUNCTION_RECORD
 jsr emit
 lda FUNCTION_RECORD+1
 jsr emit
 lda FUNCTION_PARAMETER
 jsr emit
 lda FUNCTION_PARAMETER+1
 jsr emit
 lda #$4c
 jsr emit
 lda CODE_PTR
 sta FUNCTION_PATCH
 lda CODE_PTR+1
 sta FUNCTION_PATCH+1
 lda #0
 jsr emit
 lda #0
 jsr emit
 ; Patch activation entry to this exact native function entry.
 lda EMIT_PASS
 beq @expression
 sec
 lda FUNCTION_PATCH
 sbc #11
 sta DEST
 lda FUNCTION_PATCH+1
 sbc #0
 sta DEST+1
 ldy #0
 lda CODE_PTR
 sta (DEST),y
 iny
 iny
 lda CODE_PTR+1
 sta (DEST),y
@expression:
 lda #0
 jsr expression
 lda #<pop_number
 ldx #>pop_number
 jsr emit_call
 lda #$60
 jsr emit
 lda EMIT_PASS
 beq @done
 lda FUNCTION_PATCH
 sta DEST
 lda FUNCTION_PATCH+1
 sta DEST+1
 ldy #0
 lda CODE_PTR
 sta (DEST),y
 iny
 lda CODE_PTR+1
 sta (DEST),y
@done:
 clc
 rts
@type:
 lda #ERR_TYPE
 jmp emit_trap
.segment "COMMAND"
compile_fn:
 inc TOKEN_POS
 jsr parse_name
 lda NAME_KIND
 pha
 jsr bind_function
 lda FUNCTION_RECORD
 pha
 lda FUNCTION_RECORD+1
 pha
 lda #3
 jsr expect
 lda #0
 jsr expression
 lda #4
 jsr expect
 pla
 sta VALUE+1
 pla
 sta VALUE
 jsr emit_ax
 pla
 beq @signed
 lda #<fn_unsigned_word
 ldx #>fn_unsigned_word
 jmp emit_call
@signed:
 lda #<fn_word
 ldx #>fn_word
 jmp emit_call
.segment "COMPILER"
compile_tab:
 inc TOKEN_POS
 lda #0
 jsr expression
 lda #4
 jsr expect
 lda #<tab_word
 ldx #>tab_word
 jmp emit_call
compile_spc:
 inc TOKEN_POS
 lda #0
 jsr expression
 lda #4
 jsr expect
 lda #<spc_word
 ldx #>spc_word
 jmp emit_call
compile_substring:
 jsr token_take
 pha
 lda #3
 jsr expect
 lda #0
 jsr expression
 lda #1
 jsr expect
 lda #0
 jsr expression
 pla
 pha
 cmp #$63
 bne @close
 jsr token_peek
 cmp #1
 bne @default
 inc TOKEN_POS
 lda #0
 jsr expression
 jmp @close
@default:
 lda #255
 sta VALUE
 lda #0
 sta VALUE+1
 jsr emit_ax
 lda #<push_number
 ldx #>push_number
 jsr emit_call
@close:
 lda #4
 jsr expect
 pla
 cmp #$61
 beq @left
 cmp #$62
 beq @right
 lda #<mid_word
 ldx #>mid_word
 jmp emit_call
@left:
 lda #<left_word
 ldx #>left_word
 jmp emit_call
@right:
 lda #<right_word
 ldx #>right_word
 jmp emit_call

compile_file:
 pha
 lda #0
 jsr expression
 jsr token_peek
 cmp #1
 bne @default
 inc TOKEN_POS
 lda #0
 jsr expression
 jmp @operation
@default:
 lda #8
 sta VALUE
 lda #0
 sta VALUE+1
 jsr emit_ax
 lda #<push_number
 ldx #>push_number
 jsr emit_call
@operation:
 lda #$a9
 jsr emit
 pla
 jsr emit
 lda #<file_word
 ldx #>file_word
 jsr emit_call
 clc
 rts

compile_open:
 lda #0
 jsr expression
 lda #1
 jsr open_numeric_arg
 lda #0
 jsr open_numeric_arg
 jsr token_peek
 cmp #1
 bne @empty
 inc TOKEN_POS
 lda #0
 jsr expression
 jmp @call
@empty:
 lda #<empty_string
 ldx #>empty_string
 jsr emit_call
@call:
 lda #<open_word
 ldx #>open_word
 jsr emit_call
 clc
 rts
open_numeric_arg:
 pha
 jsr token_peek
 cmp #1
 bne @default
 pla
 inc TOKEN_POS
 lda #0
 jmp expression
@default:
 pla
 sta VALUE
 lda #0
 sta VALUE+1
 jsr emit_ax
 lda #<push_number
 ldx #>push_number
 jmp emit_call
compile_close:
 lda #0
 jsr expression
 lda #<close_word
 ldx #>close_word
 jsr emit_call
 clc
 rts
compile_print_channel:
 lda #0
 jsr expression
 lda #1
 jsr expect
 lda #<output_channel
 ldx #>output_channel
 jsr emit_call
 jsr compile_print
 lda #<reset_channel
 ldx #>reset_channel
 jsr emit_call
 clc
 rts
compile_cmd:
 lda #0
 jsr expression
 lda #<output_channel
 ldx #>output_channel
 jsr emit_call
 jsr token_peek
 cmp #1
 bne @done
 inc TOKEN_POS
 jmp compile_print
@done:
 clc
 rts
compile_input_channel:
 lda #0
 jsr expression
 lda #1
 jsr expect
 lda #<input_channel
 ldx #>input_channel
 jsr emit_call
 lda #0
 jsr compile_input_vars
 lda #<reset_channel
 ldx #>reset_channel
 jsr emit_call
 clc
 rts
compile_get_channel:
 lda #0
 jsr expression
 lda #1
 jsr expect
 lda #<input_channel
 ldx #>input_channel
 jsr emit_call
 lda #1
 jsr compile_input_vars
 lda #<reset_channel
 ldx #>reset_channel
 jsr emit_call
 clc
 rts
compile_input:
 lda #<input_prompt
 ldx #>input_prompt
 jsr emit_call
 lda #0
 jsr compile_input_vars
 clc
 rts
compile_get:
 lda #1
 jsr compile_input_vars
 clc
 rts
compile_input_vars:
 ; caller A selects character GET versus delimited INPUT.
 sta INPUT_KIND
@variable:
 lda INPUT_KIND
 pha
 jsr parse_name
 php
 lda CELL
 pha
 lda CELL+1
 pha
 lda #$a9
 jsr emit
 lda INPUT_KIND
 jsr emit
 lda #<input_field
 ldx #>input_field
 jsr emit_call
 pla
 sta SCRATCH+31
 pla
 sta SCRATCH+30
 plp
 php
 beq @string
 lda INPUT_KIND
 beq @input_number
 lda #<get_number
 ldx #>get_number
 bne @convert_number
@input_number:
 lda #<val_word
 ldx #>val_word
@convert_number:
 jsr emit_call
@string:
 lda SCRATCH+30
 sta VALUE
 lda SCRATCH+31
 sta VALUE+1
 jsr emit_ax
 plp
 beq @store_string
 lda #<store_number
 ldx #>store_number
 jsr emit_call
 jmp @next
@store_string:
 lda #<store_string
 ldx #>store_string
 jsr emit_call
@next:
 pla
 sta INPUT_KIND
 jsr token_peek
 cmp #1
 bne @done
 inc TOKEN_POS
 jmp @variable
@done:
 rts

compile_set_time:
 lda #10
 jsr expect
 lda #0
 jsr expression
 lda #<set_time_word
 ldx #>set_time_word
 jsr emit_call
 clc
 rts

compile_read_array:
 plp
 jsr bind_array
 lda CELL
 pha
 lda CELL+1
 pha
 jsr parse_subscripts
 lda ARRAY_DIMS
 pha
 ; Find the saved array record below the count using the hardware stack.
 tsx
 lda $0102,x
 sta WALK+1
 lda $0103,x
 sta WALK
 ldy #7
 lda (WALK),y
 and #1
 beq @number
 lda #<read_string
 ldx #>read_string
 jmp @read
@number:
 lda #<read_number
 ldx #>read_number
@read:
 jsr emit_call
 pla
 sta VALUE
 lda #0
 sta VALUE+1
 jsr emit_ax
 lda #<push_number
 ldx #>push_number
 jsr emit_call
 pla
 sta VALUE+1
 pla
 sta VALUE
 jsr emit_ax
 lda #<array_store
 ldx #>array_store
 jsr emit_call
 jsr token_peek
 cmp #1
 bne @done
 inc TOKEN_POS
 jmp compile_read
@done:
 clc
 rts
