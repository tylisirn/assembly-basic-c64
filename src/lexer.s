.segment "COMMAND"
input_peek:
 ldx INPUT_POS
 lda INPUT_BUFFER,x
 rts
input_take:
 jsr input_peek
 inc INPUT_POS
 rts
skip_spaces:
 jsr input_peek
 cmp #' '
 beq @take
 cmp #9
 bne @done
@take:
 inc INPUT_POS
 jmp skip_spaces
@done:
 rts
uppercase:
 cmp #'a'
 bcc @done
 cmp #'z'+1
 bcs @done
 and #$df
@done:
 rts
is_letter:
 jsr uppercase
 cmp #'A'
 bcc @no
 cmp #'Z'+1
 bcs @no
 sec
 rts
@no:
 clc
 rts
is_digit:
 cmp #'0'
 bcc @no
 cmp #'9'+1
 bcs @no
 sec
 rts
@no:
 clc
 rts
read_decimal:
 lda #0
 sta VALUE
 sta VALUE+1
@loop:
 jsr input_peek
 jsr is_digit
 bcc @done
 sec
 sbc #'0'
 sta SCRATCH+4
 lda VALUE+1
 cmp #$19
 bcc @multiply
 bne @overflow
 lda VALUE
 cmp #$99
 bcc @multiply
 bne @overflow
 lda SCRATCH+4
 cmp #6
 bcs @overflow
@multiply:
 lda VALUE
 sta TMP
 lda VALUE+1
 sta TMP+1
 asl VALUE
 rol VALUE+1
 asl VALUE
 rol VALUE+1
 clc
 lda VALUE
 adc TMP
 sta VALUE
 lda VALUE+1
 adc TMP+1
 sta VALUE+1
 asl VALUE
 rol VALUE+1
 clc
 lda VALUE
 adc SCRATCH+4
 sta VALUE
 bcc :+
 inc VALUE+1
:
 inc INPUT_POS
 jmp @loop
@done:
 clc
 rts
@overflow:
 sec
 rts
add_token:
 ldx TOKEN_LEN
 cpx #255
 JEQ command_quantity
 sta TOKENS,x
 inc TOKEN_LEN
 rts
add_word:
 lda VALUE
 jsr add_token
 lda VALUE+1
 jmp add_token
add_immediate:
 lda IS_HEX
 beq @decimal
 lda #$12
 jsr add_token
 jmp add_word
@decimal:
 lda VALUE+1
 bne @word
 lda VALUE
 cmp #16
 bcs @byte
 clc
 adc #$70
 jmp add_token
@byte:
 lda #$10
 jsr add_token
 lda VALUE
 jmp add_token
@word:
 lda #$11
 jsr add_token
 jmp add_word
add_raw:
 ; code A, length LEX_LEN, bytes LEX_BUFFER
 jsr add_token
 lda LEX_LEN
 jsr add_token
 ldy #0
@loop:
 cpy LEX_LEN
 beq @done
 lda LEX_BUFFER,y
 jsr add_token
 iny
 jmp @loop
@done:
 rts
tokenize_input:
 lda #0
 sta TOKEN_LEN
@loop:
 jsr skip_spaces
 lda INPUT_POS
 cmp INPUT_LEN
 JEQ @done
 jsr input_peek
 cmp #'"'
 JEQ @string
 cmp #'?'
 JEQ @print
 cmp #'$'
 JEQ @hex
 jsr is_digit
 JCS @decimal
 jsr is_letter
 JCS @name
 jsr input_take
 ldx #0
@punct:
 cmp punctuation,x
 beq @found_punct
 inx
 cpx #13
 bne @punct
 sta LEX_BUFFER
 lda #1
 sta LEX_LEN
 lda #$18
 jsr add_raw
 jmp @loop
@found_punct:
 stx LEX_CODE
 cpx #10
 bcc @plain_punct
 jsr input_peek
 cmp #'='
 beq @equal_pair
 cmp #'<'
 beq @less_pair
 cmp #'>'
 bne @plain_punct
 lda LEX_CODE
 cmp #12
 beq @right_shift
 cmp #11
 bne @plain_punct
 lda #15
 bne @pair
@right_shift:
 lda #$1b
 bne @pair
@less_pair:
 lda LEX_CODE
 cmp #11
 beq @left_shift
 cmp #12
 beq @not_equal
 cmp #10
 bne @plain_punct
 lda #13
 bne @pair
@left_shift:
 lda #$1a
 bne @pair
@not_equal:
 lda #15
 bne @pair
@equal_pair:
 lda LEX_CODE
 cmp #11
 beq @le
 cmp #12
 bne @plain_punct
 lda #14
 bne @pair
@le:
 lda #13
@pair:
 inc INPUT_POS
 jsr add_token
 jmp @loop
@plain_punct:
 lda LEX_CODE
 jsr add_token
 jmp @loop
@print:
 inc INPUT_POS
 lda #$39
 jsr add_token
 jmp @loop
@string:
 inc INPUT_POS
 lda #0
 sta LEX_LEN
@string_loop:
 lda INPUT_POS
 cmp INPUT_LEN
 beq @string_done
 jsr input_take
 cmp #'"'
 beq @string_done
 ldx LEX_LEN
 sta LEX_BUFFER,x
 inc LEX_LEN
 jmp @string_loop
@string_done:
 lda #$13
 jsr add_raw
 jmp @loop
@decimal:
 lda INPUT_POS
 sta SCRATCH+5
 lda #0
 sta IS_HEX
 jsr read_decimal
 bcs @bad_number
 jsr input_peek
 cmp #'.'
 beq @bad_number
 cmp #'E'
 beq @bad_number
 cmp #'e'
 beq @bad_number
 jsr is_letter
 bcs @bad_number
 jsr add_immediate
 jmp @loop
@hex:
 lda INPUT_POS
 sta SCRATCH+5
 inc INPUT_POS
 lda #1
 sta IS_HEX
 lda #0
 sta VALUE
 sta VALUE+1
 sta LEX_LEN
@hex_loop:
 jsr input_peek
 jsr uppercase
 jsr hex_digit
 bcc @hex_done
 pha
 lda LEX_LEN
 cmp #4
 pla
 bcs @bad_number
 asl VALUE
 rol VALUE+1
 asl VALUE
 rol VALUE+1
 asl VALUE
 rol VALUE+1
 asl VALUE
 rol VALUE+1
 ora VALUE
 sta VALUE
 inc LEX_LEN
 inc INPUT_POS
 jmp @hex_loop
@hex_done:
 lda LEX_LEN
 beq @bad_number
 jsr input_peek
 jsr is_letter
 bcs @bad_number
 jsr add_immediate
 jmp @loop
@bad_number:
 ldx SCRATCH+5
 lda #0
 sta LEX_LEN
@bad_copy:
 lda INPUT_BUFFER,x
 beq @bad_done
 cmp #' '
 beq @bad_done
 cmp #':'
 beq @bad_done
 cmp #','
 beq @bad_done
 cmp #';'
 beq @bad_done
 cmp #')'
 beq @bad_done
 ldy LEX_LEN
 sta LEX_BUFFER,y
 inc LEX_LEN
 inx
 jmp @bad_copy
@bad_done:
 stx INPUT_POS
 lda #$17
 jsr add_raw
 jmp @loop
@name:
 lda #0
 sta LEX_LEN
 sta ABBREVIATED
@name_loop:
 jsr input_take
 jsr uppercase
 ldx LEX_LEN
 sta LEX_BUFFER,x
 inc LEX_LEN
 jsr input_peek
 jsr is_letter
 bcs @name_loop
 jsr input_peek
 jsr is_digit
 bcs @name_loop
 jsr input_peek
 cmp #$c1
 bcc @normal_suffix
 cmp #$db
 bcs @normal_suffix
 jsr input_take
 and #$7f
 ldx LEX_LEN
 sta LEX_BUFFER,x
 inc LEX_LEN
 lda #1
 sta ABBREVIATED
@normal_suffix:
 jsr input_peek
 cmp #'$'
 beq @suffix
 cmp #'%'
 bne @keyword
@suffix:
 jsr input_take
 ldx LEX_LEN
 sta LEX_BUFFER,x
 inc LEX_LEN
@keyword:
 lda ABBREVIATED
 beq @lookup
 jsr input_peek
 jsr is_letter
 bcs @invalid_abbreviation
 jsr input_peek
 jsr is_digit
 bcs @invalid_abbreviation
@lookup:
 jsr find_keyword
 JCC @identifier
 lda LEX_CODE
 cmp #$39
 beq @hash
 cmp #$25
 beq @hash
 cmp #$41
 bne @emit_keyword
@hash:
 jsr input_peek
 cmp #'#'
 bne @emit_keyword
 inc INPUT_POS
 lda LEX_CODE
 cmp #$39
 bne :+
 lda #$38
 bne @set_code
:
 cmp #$25
 bne :+
 lda #$24
 bne @set_code
:
 lda #$42
@set_code:
 sta LEX_CODE
 jmp @emit_keyword
@invalid_abbreviation:
 lda #$18
 jsr add_raw
 jmp @loop
@emit_keyword:
 lda LEX_CODE
 cmp #$38
 beq @keyword_hash
 cmp #$24
 beq @keyword_hash
 cmp #$42
 beq @keyword_hash
 cmp #$44
 beq @keyword_parenthesis
 cmp #$47
 bne @keyword_code
 jmp @keyword_parenthesis
@keyword_hash:
 jsr input_peek
 cmp #'#'
 bne @keyword_code
 inc INPUT_POS
 jmp @keyword_code
@keyword_parenthesis:
 jsr input_peek
 cmp #'('
 bne @keyword_code
 inc INPUT_POS
@keyword_code:
 lda LEX_CODE
 jsr add_token
 cmp #$2f
 bne @not_rem
 jsr input_peek
 cmp #' '
 bne :+
 inc INPUT_POS
:
 lda #0
 sta LEX_LEN
@rem_loop:
 lda INPUT_POS
 cmp INPUT_LEN
 beq @rem_done
 jsr input_take
 ldx LEX_LEN
 sta LEX_BUFFER,x
 inc LEX_LEN
 jmp @rem_loop
@rem_done:
 lda #$14
 jsr add_raw
 jmp @done
@not_rem:
 cmp #$23
 bne :+
 jsr lex_data
:
 jmp @loop
@identifier:
 ; TAB/SPC have reserved punctuation forms.
 lda LEX_LEN
 cmp #3
 bne @intern
 jsr input_peek
 cmp #'('
 bne @intern
 lda LEX_BUFFER
 cmp #'T'
 bne @spc
 lda LEX_BUFFER+1
 cmp #'A'
 bne @intern
 lda LEX_BUFFER+2
 cmp #'B'
 bne @intern
 lda #$44
 bne @emit_tab
@spc:
 cmp #'S'
 bne @intern
 lda LEX_BUFFER+1
 cmp #'P'
 bne @intern
 lda LEX_BUFFER+2
 cmp #'C'
 bne @intern
 lda #$47
@emit_tab:
 inc INPUT_POS
 jsr add_token
 jmp @loop
@intern:
 jsr intern_name
 lda VALUE+1
 bne @extended
 lda VALUE
 cmp #128
 bcs @extended
 ora #$80
 jsr add_token
 jmp @loop
@extended:
 lda #$19
 jsr add_token
 jsr add_word
 jmp @loop
@done:
 rts
.segment "COMPILER"
hex_digit:
 cmp #'0'
 bcc @no
 cmp #'9'+1
 bcc @decimal
 cmp #'A'
 bcc @no
 cmp #'F'+1
 bcs @no
 sec
 sbc #'A'-10
 sec
 rts
@decimal:
 sec
 sbc #'0'
 sec
 rts
@no:
 clc
 rts
.segment "COMMAND"
find_keyword:
 lda #<keyword_table
 sta PTR2
 lda #>keyword_table
 sta PTR2+1
@loop:
 ldy #0
 lda (PTR2),y
 beq @no
 ldx ABBREVIATED
 beq @exact
 cmp LEX_LEN
 bcc @skip
 tay
 lda (PTR2),y
 cmp #'#'
 beq @punctuated
 cmp #'('
 bne @abbreviation_ready
@punctuated:
 sta LEX_CODE
 jsr input_peek
 cmp LEX_CODE
 bne @skip
@abbreviation_ready:
 ldy #0
 jmp @compare_start
@exact:
 cmp LEX_LEN
 bne @skip
@compare_start:
 ldx #0
@compare:
 iny
 lda (PTR2),y
 cmp LEX_BUFFER,x
 bne @skip
 inx
 cpx LEX_LEN
 bne @compare
 ldy #0
 lda (PTR2),y
 tay
 iny
 lda (PTR2),y
 sta LEX_CODE
 sec
 rts
@skip:
 ldy #0
 lda (PTR2),y
 clc
 adc #2
 clc
 adc PTR2
 sta PTR2
 bcc :+
 inc PTR2+1
:
 jmp @loop
@no:
 clc
 rts
punctuation: .byte ":,;()+-*/^=<>"
.include "keywords.inc"

lex_data:
@field:
 jsr skip_spaces
 lda #0
 sta LEX_LEN
 sta SCRATCH+24
@gather:
 lda INPUT_POS
 cmp INPUT_LEN
 beq @trim
 jsr input_peek
 cmp #'"'
 bne @delimiter
 lda SCRATCH+24
 eor #1
 sta SCRATCH+24
 jsr input_peek
@delimiter:
 ldx SCRATCH+24
 bne @store
 cmp #','
 beq @trim
 cmp #':'
 beq @trim
@store:
 jsr input_take
 ldx LEX_LEN
 sta LEX_BUFFER,x
 inc LEX_LEN
 jmp @gather
@trim:
 ldx LEX_LEN
 beq @classify
@trailing:
 lda LEX_BUFFER-1,x
 cmp #' '
 bne @trimmed
 dex
 bne @trailing
@trimmed:
 stx LEX_LEN
@classify:
 jsr lex_data_field
 jsr input_peek
 cmp #','
 bne @done
 inc INPUT_POS
 lda #1
 jsr add_token
 jmp @field
@done:
 rts
lex_data_field:
 lda LEX_LEN
 beq @text
 lda LEX_BUFFER
 cmp #'"'
 beq @quoted
 lda #0
 sta SCRATCH+24
 sta IS_HEX
 sta VALUE
 sta VALUE+1
 ldx #0
 lda LEX_BUFFER
 cmp #'+'
 beq @sign
 cmp #'-'
 bne @radix
@sign:
 sta SCRATCH+24
 inx
@radix:
 lda LEX_BUFFER,x
 cmp #'$'
 bne @decimal_start
 inc IS_HEX
 inx
@decimal_start:
 stx SCRATCH+27
 lda LEX_BUFFER,x
 jsr is_digit
 bcs @digits
 lda IS_HEX
 bne @digits
 lda LEX_BUFFER,x
 cmp #'.'
 JEQ @invalid
@text:
 lda #$15
 jmp add_raw
@quoted:
 ldx #0
@shift:
 lda LEX_BUFFER+1,x
 sta LEX_BUFFER,x
 inx
 cpx LEX_LEN
 bne @shift
 dec LEX_LEN
 ldx LEX_LEN
 beq @quoted_done
 lda LEX_BUFFER-1,x
 cmp #'"'
 bne @quoted_done
 dec LEX_LEN
@quoted_done:
 lda #$13
 jmp add_raw
@digits:
 cpx LEX_LEN
 JEQ @number
 lda LEX_BUFFER,x
 jsr uppercase
 lda IS_HEX
 beq @decimal
 lda LEX_BUFFER,x
 jsr uppercase
 jsr hex_digit
 bcc @invalid
 pha
 txa
 sec
 sbc SCRATCH+27
 cmp #4
 pla
 bcs @invalid
 asl VALUE
 rol VALUE+1
 asl VALUE
 rol VALUE+1
 asl VALUE
 rol VALUE+1
 asl VALUE
 rol VALUE+1
 ora VALUE
 sta VALUE
 jmp @next_digit
@decimal:
 lda LEX_BUFFER,x
 jsr is_digit
 bcc @invalid
 sec
 sbc #'0'
 sta TMP
 lda VALUE+1
 cmp #$19
 bcc @multiply
 bne @invalid
 lda VALUE
 cmp #$99
 bcc @multiply
 bne @invalid
 lda TMP
 cmp #6
 bcs @invalid
@multiply:
 lda VALUE
 sta LEFT
 lda VALUE+1
 sta LEFT+1
 asl VALUE
 rol VALUE+1
 asl VALUE
 rol VALUE+1
 clc
 lda VALUE
 adc LEFT
 sta VALUE
 lda VALUE+1
 adc LEFT+1
 sta VALUE+1
 asl VALUE
 rol VALUE+1
 clc
 lda VALUE
 adc TMP
 sta VALUE
 bcc @next_digit
 inc VALUE+1
@next_digit:
 inx
 jmp @digits
@invalid:
 lda #$17
 jmp add_raw
@number:
 cpx SCRATCH+27
 beq @invalid
 lda SCRATCH+24
 beq @unsigned
 cmp #'-'
 bne :+
 lda #6
 bne @sign_token
:
 lda #5
@sign_token:
 jsr add_token
@unsigned:
 lda VALUE
 sta SCRATCH+25
 lda VALUE+1
 sta SCRATCH+26
 jsr add_immediate
 ; Build canonical unsigned source spelling, optional adjacent unary sign.
 lda #0
 sta SCRATCH+28
 lda SCRATCH+24
 beq @format
 sta BRIDGE
 inc SCRATCH+28
@format:
 lda IS_HEX
 bne @hex_format
 lda SCRATCH+25
 sta IO_A
 lda SCRATCH+26
 sta IO_X
 lda #<format_source
 sta gateway_call+1
 lda #>format_source
 sta gateway_call+2
 jsr call_ram
 ldy #0
 ldx SCRATCH+28
@decimal_copy:
 lda NUM_BUFFER,y
 sta BRIDGE,x
 inx
 iny
 cpy COUNT
 bne @decimal_copy
 stx SCRATCH+28
 jmp @compare
@hex_format:
 ldx SCRATCH+28
 lda #'$'
 sta BRIDGE,x
 inx
 lda SCRATCH+26
 jsr data_hex_byte
 lda SCRATCH+25
 jsr data_hex_byte
 stx SCRATCH+28
@compare:
 lda SCRATCH+28
 cmp LEX_LEN
 bne @spelling
 ldx #0
@compare_byte:
 lda BRIDGE,x
 cmp LEX_BUFFER,x
 bne @spelling
 inx
 cpx LEX_LEN
 bne @compare_byte
 rts
@spelling:
 lda #$16
 jmp add_raw
data_hex_byte:
 pha
 lsr
 lsr
 lsr
 lsr
 jsr data_hex_digit
 pla
 and #15
data_hex_digit:
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
