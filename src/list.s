.segment "COMMAND"
command_list:
 lda #0
 sta LIST_MIN
 sta LIST_MIN+1
 lda #$ff
 sta LIST_MAX
 lda #$f9
 sta LIST_MAX+1
 lda #1
 sta TOKEN_POS
 cmp TOKEN_LEN
 beq @start
 jsr token_peek
 cmp #6
 beq @range
 jsr list_bound
 lda VALUE
 sta LIST_MIN
 sta LIST_MAX
 lda VALUE+1
 sta LIST_MIN+1
 sta LIST_MAX+1
 lda TOKEN_POS
 cmp TOKEN_LEN
 beq @start
@range:
 lda #6
 jsr token_take
 cmp #6
 JNE list_syntax
 lda #$ff
 sta LIST_MAX
 lda #$f9
 sta LIST_MAX+1
 lda TOKEN_POS
 cmp TOKEN_LEN
 beq @start
 jsr list_bound
 lda VALUE
 sta LIST_MAX
 lda VALUE+1
 sta LIST_MAX+1
 lda TOKEN_POS
 cmp TOKEN_LEN
 JNE list_syntax
@start:
 lda #13
 jsr $ffd2
 lda PROGRAM_HEAD
 sta LIST_ANCHOR
 lda PROGRAM_HEAD+1
 sta LIST_ANCHOR+1
list_line:
 lda PENDING
 JNE ready
 jsr $ffe1
 JEQ ready
 lda LIST_ANCHOR
 cmp #<run_end
 bne @load
 lda LIST_ANCHOR+1
 cmp #>run_end
 JEQ ready
@load:
 lda LIST_ANCHOR
 sta WALK
 lda LIST_ANCHOR+1
 sta WALK+1
 ldy #3
 lda (WALK),y
 sta IO_A
 iny
 lda (WALK),y
 sta IO_X
 cmp LIST_MIN+1
 bcc @skip
 bne @upper
 lda IO_A
 cmp LIST_MIN
 bcc @skip
@upper:
 lda IO_X
 cmp LIST_MAX+1
 JCC @print
 JNE ready
 lda IO_A
 cmp LIST_MAX
 JCC @print
 JEQ @print
 jmp ready
@skip:
 jmp list_advance
@print:
 jsr print_source_line
 lda #13
 jsr $ffd2
 jmp list_advance
; Shared canonical detokenizer. The bank-3 editor captures CHROUT through its
; common-RAM vector. This returns one line without a terminating CR, so raw
; carriage returns inside strings/comments can be displayed as literal glyphs.
print_source_line:
 lda LIST_ANCHOR
 sta WALK
 lda LIST_ANCHOR+1
 sta WALK+1
 ldy #3
 lda (WALK),y
 sta IO_A
 iny
 lda (WALK),y
 sta IO_X
 jsr print_source_number
 lda #' '
 jsr $ffd2
 lda LIST_ANCHOR
 sta WALK
 lda LIST_ANCHOR+1
 sta WALK+1
 ldy #5
 lda (WALK),y
 sta PTR
 iny
 lda (WALK),y
 sta PTR+1
 ldy #0
 jsr read_ram
 sta TOKEN_LEN
 sta LIST_END
 ldx #0
@copy:
 iny
 jsr read_ram
 sta TOKENS,x
 inx
 cpx LIST_END
 bne @copy
 lda #0
 sta TOKEN_POS
 sta SCRATCH+43
 lda #$ff
 sta LIST_PREVIOUS
@token:
 lda TOKEN_POS
 cmp LIST_END
 JCS @next
 ldy TOKEN_POS
 lda TOKENS,y
 sta LIST_CURRENT
 jsr list_separator
 jsr list_data_spelling
 bcs @token
 jsr token_take
 cmp #$80
 JCS @name
 cmp #$19
 JEQ @name_extended
 cmp #$70
 bcs @small
 cmp #$10
 JEQ @byte
 cmp #$11
 JEQ @word
 cmp #$12
 JEQ @hex
 cmp #$13
 JEQ @quoted
 cmp #$13
 bcc @punctuation
 cmp #$1a
 JEQ @left_shift
 cmp #$1b
 JEQ @right_shift
 cmp #$1a
 JCC @raw
 cmp #$20
 JCS @keyword
@punctuation:
 cmp #0
 bne :+
 sta SCRATCH+43
:
 tax
 lda punctuation,x
 cpx #13
 bcs @compound
 jsr $ffd2
 jmp @space
@compound:
 lda #'<'
 cpx #14
 bne :+
 lda #'>'
:
 jsr $ffd2
 lda #'='
 cpx #15
 bne :+
 lda #'>'
:
 jsr $ffd2
 jmp @space
@left_shift:
 lda #'<'
 bne @shift
@right_shift:
 lda #'>'
@shift:
 pha
 jsr $ffd2
 pla
 jsr $ffd2
 jmp @space
@small:
 sec
 sbc #$70
 sta IO_A
 lda #0
 sta IO_X
 jsr print_source_number
 jmp @space
@byte:
 jsr token_take
 sta IO_A
 lda #0
 sta IO_X
 jsr print_source_number
 jmp @space
@word:
 jsr token_take
 sta IO_A
 jsr token_take
 sta IO_X
 jsr print_source_number
 jmp @space
@hex:
 jsr token_take
 pha
 jsr token_take
 pha
 lda #'$'
 jsr $ffd2
 pla
 jsr print_hex_byte
 pla
 jsr print_hex_byte
 jmp @space
@name:
 sec
 sbc #$80
 sta VALUE
 lda #0
 sta VALUE+1
 jmp @bind
@name_extended:
 jsr token_take
 sta VALUE
 jsr token_take
 sta VALUE+1
@bind:
 jsr bind_name
 ldy #8
 lda (WALK),y
 sta LIST_POS
 jsr name_bytes
 ldy #0
@name_char:
 tya
 pha
 lda (PTR2),y
 jsr $ffd2
 pla
 tay
 iny
 dec LIST_POS
 bne @name_char
 jmp @space
@quoted:
 lda #'"'
 jsr $ffd2
 jsr list_raw
 lda #'"'
 jsr $ffd2
 jmp @space
@raw:
 jsr list_raw
 jmp @token
@keyword:
 sta LEX_CODE
 cmp #$23
 bne :+
 lda #1
 sta SCRATCH+43
:
 lda LEX_CODE
 lda #<keyword_table
 sta PTR2
 lda #>keyword_table
 sta PTR2+1
@search:
 ldy #0
 lda (PTR2),y
 beq @next
 tay
 iny
 lda (PTR2),y
 cmp LEX_CODE
 beq @found
 ldy #0
 lda (PTR2),y
 clc
 adc #2
 clc
 adc PTR2
 sta PTR2
 bcc @search
 inc PTR2+1
 jmp @search
@found:
 ldy #0
 lda (PTR2),y
 sta LIST_POS
@kw_char:
 iny
 lda (PTR2),y
 tya
 pha
 lda (PTR2),y
 jsr $ffd2
 pla
 tay
 dec LIST_POS
 bne @kw_char
@space:
 jmp @token
@next:
 rts
list_advance:
 lda LIST_ANCHOR
 sta WALK
 lda LIST_ANCHOR+1
 sta WALK+1
 jsr next_line
 lda WALK
 sta LIST_ANCHOR
 lda WALK+1
 sta LIST_ANCHOR+1
 jmp list_line
list_separator:
 ; Prefix spacing keeps raw payload bytes intact and emits no trailing gap.
 lda LIST_PREVIOUS
 cmp #$ff
 beq @done
 cmp #3
 beq @done
 cmp #$44 ; TAB( and SPC( include their opening parenthesis.
 beq @done
 cmp #$47
 beq @done
 lda LIST_CURRENT
 cmp #1
 beq @done
 cmp #2
 beq @done
 cmp #4
 beq @done
 cmp #3
 bne @data_sign
 lda LIST_PREVIOUS
 cmp #$80
 bcs @done ; Array or DEF FN name followed by an argument list.
 cmp #$19
 beq @done
 cmp #$4d
 bcc @space
 cmp #$64
 bcc @done ; Builtin expression functions SGN through MID$.
@data_sign:
 lda SCRATCH+43
 beq @space
 lda LIST_PREVIOUS
 cmp #5
 beq @number
 cmp #6
 bne @space
@number:
 lda LIST_CURRENT
 cmp #$10
 bcc @space
 cmp #$13
 bcc @done
 cmp #$70
 bcc @space
 cmp #$80
 bcc @done
@space:
 lda #' '
 jsr $ffd2
@done:
 lda LIST_CURRENT
 sta LIST_PREVIOUS
 rts
list_raw:
 jsr token_take
 sta LIST_POS
@char:
 lda LIST_POS
 beq @done
 jsr token_take
 jsr $ffd2
 dec LIST_POS
 jmp @char
@done:
 rts
.segment "COMMAND"
print_hex_byte:
 pha
 lsr
 lsr
 lsr
 lsr
 jsr print_hex_digit
 pla
 and #15
print_hex_digit:
 cmp #10
 bcc :+
 clc
 adc #7
:
 clc
 adc #'0'
 jmp $ffd2
print_source_number_buffer:
 lda #<format_source
 sta gateway_call+1
 lda #>format_source
 sta gateway_call+2
 jmp call_ram
print_source_number:
 jsr print_source_number_buffer
 ldy #0
@digit:
 sty NUM_LENGTH
 lda NUM_BUFFER,y
 jsr $ffd2
 ldy NUM_LENGTH
 iny
 cpy COUNT
 bne @digit
 rts

.segment "COMPILER"
list_data_spelling:
 lda SCRATCH+43
 beq @no
 ldy TOKEN_POS
 lda TOKENS,y
 cmp #5
 beq @sign
 cmp #6
 bne @number
@sign:
 iny
 lda TOKENS,y
@number:
 cmp #$10
 beq @byte
 cmp #$11
 beq @word
 cmp #$12
 beq @word
 cmp #$70
 bcc @no
 cmp #$80
 bcs @no
 iny
 jmp @check
@word:
 iny
@byte:
 iny
 iny
@check:
 cpy TOKEN_LEN
 bcs @no
 lda TOKENS,y
 cmp #$16
 bne @no
 iny
 sty TOKEN_POS
 jsr list_raw
 sec
 rts
@no:
 clc
 rts

.segment "COMPILER"
list_bound:
 jsr parse_immediate
 bcs list_syntax
 lda VALUE+1
 cmp #$fa
 JCS command_quantity
 rts
list_syntax:
 lda #ERR_SYNTAX
 jmp command_error

; Editor navigation uses numeric positions, so NEW/LOAD/CLEAN cannot leave
; persistent viewport state pointing at freed anchors.
editor_find:
 jsr find_position
 lda SUCCESSOR
 ldx SUCCESSOR+1
 rts
editor_next:
 lda ED_ANCHOR
 sta WALK
 lda ED_ANCHOR+1
 sta WALK+1
 jsr next_line
 lda WALK
 ldx WALK+1
 rts
editor_previous:
 lda PROGRAM_HEAD
 sta WALK
 lda PROGRAM_HEAD+1
 sta WALK+1
 lda #0
 sta ED_NEXT
 sta ED_NEXT+1
@scan:
 lda WALK
 cmp ED_ANCHOR
 bne @advance
 lda WALK+1
 cmp ED_ANCHOR+1
 beq @done
@advance:
 lda WALK
 cmp #<run_end
 bne @save
 lda WALK+1
 cmp #>run_end
 beq @done
@save:
 lda WALK
 sta ED_NEXT
 lda WALK+1
 sta ED_NEXT+1
 jsr next_line
 jmp @scan
@done:
 lda ED_NEXT
 ldx ED_NEXT+1
 rts
