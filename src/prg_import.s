.segment "SCREEN_EDITOR"
; Stock BASIC V2 PRG input streams through KERNAL CHRIN, never into live C64
; memory. LOAD already owns a fresh staged graph and retains its rollback heads.
prg_import:
 lda #1
 sta PRG_ADDRESS
 lda #8
 sta PRG_ADDRESS+1
 lda #0
 sta PRG_HAVE_LINE
@line:
 jsr prg_get
 sta PRG_NEXT
 jsr prg_get
 sta PRG_NEXT+1
 ora PRG_NEXT
 JEQ @end
 jsr prg_get
 sta LINE_NO
 jsr prg_get
 sta LINE_NO+1
 cmp #$fa
 JCS prg_fail
 lda PRG_HAVE_LINE
 beq @number
 lda LINE_NO+1
 cmp PRG_LAST+1
 JCC prg_fail
 bne @number
 lda LINE_NO
 cmp PRG_LAST
 JCC prg_fail
 JEQ prg_fail
@number:
 lda LINE_NO
 sta PRG_LAST
 lda LINE_NO+1
 sta PRG_LAST+1
 lda #0
 sta INPUT_LEN
 sta PRG_MODE
 sta PRG_IDENT
 sta PRG_GO
@byte:
 jsr prg_get
 JEQ @converted
 sta PRG_CHAR
 lda PRG_MODE
 beq @normal
 cmp #2
 JEQ @raw
 cmp #1
 bne @data
 lda PRG_CHAR
 cmp #'"'
 JNE @raw
 lda #0
 sta PRG_MODE
 beq @raw
@data:
 lda PRG_CHAR
 cmp #'"'
 bne @colon
 lda PRG_MODE
 eor #7 ; DATA 3 <-> quoted DATA 4
 sta PRG_MODE
 jmp @raw
@colon:
 cmp #':'
 JNE @raw
 lda PRG_MODE
 cmp #3
 JNE @raw
 lda #0
 sta PRG_MODE
@raw:
 lda PRG_CHAR
 jsr prg_put
 jmp @byte
@normal:
 lda PRG_CHAR
 cmp #' '
 beq @byte
 lda PRG_GO
 beq @character
 lda PRG_CHAR
 cmp #$a4 ; GO TO is two stock tokens
 JNE prg_fail
 lda #0
 sta PRG_GO
 beq @byte
@character:
 lda PRG_CHAR
 cmp #'"'
 bne @token
 lda #1
 sta PRG_MODE
 lda #0
 sta PRG_IDENT
 beq @raw
@token:
 cmp #$80
 JCS @keyword
 cmp #'A'
 bcc @digit
 cmp #'Z'+1
 bcc @letter
@digit:
 cmp #'0'
 bcc @punctuation
 cmp #'9'+1
 bcs @punctuation
 lda PRG_IDENT
 bne @name_byte
 lda #3 ; number/exponent text is kept for the native numeric lexer
 sta PRG_IDENT
 JNE @raw
@letter:
 lda PRG_IDENT
 bne @name_byte
 lda INPUT_LEN
 sta PRG_NAME_START
 lda #1
 sta PRG_IDENT
 JNE @raw
@name_byte:
 cmp #2
 JEQ @byte ; stock names use only the first two letters/digits
 cmp #1
 JNE @raw
 inc PRG_IDENT
 JNE @raw
@punctuation:
 cmp #'#'
 bne @integer
 ; GET# is GET followed by an ASCII # in stock BASIC. Keep it adjacent
 ; for the native keyword lexer even when the PRG contains intervening spaces.
 ldx INPUT_LEN
 beq @boundary
 dex
 lda INPUT_BUFFER,x
 cmp #' '
 bne @boundary
 dec INPUT_LEN
 jmp @boundary
@integer:
 cmp #'%'
 bne @boundary
 lda PRG_IDENT
 beq @boundary
 cmp #3
 beq @boundary
 ; Stock % variables are signed, unlike native unsigned %. Give them a
 ; distinct long signed name; no normalized stock name can have this prefix.
 jsr prg_integer_name
 lda #0
 sta PRG_IDENT
 jmp @byte
@boundary:
 lda #0
 sta PRG_IDENT
 jmp @raw
@keyword:
 lda #0
 sta PRG_IDENT
 lda PRG_CHAR
 cmp #$ff ; retain unsupported PI as an explicit repairable glyph
 JEQ @raw
 cmp #$cc
 JCS prg_fail
 cmp #$aa
 bcc @word
 cmp #$af
 bcc @operator
 cmp #$b1
 bcc @word
 cmp #$b4
 bcc @operator
@word:
 lda #' '
 jsr prg_put
@operator:
 lda PRG_CHAR
 sec
 sbc #$80
 tax
 lda prg_words_lo,x
 sta ED_PTR
 lda prg_words_hi,x
 sta ED_PTR+1
 ldy #0
@spelling:
 lda (ED_PTR),y
 beq @spelled
 jsr prg_put
 iny
 bne @spelling
@spelled:
 lda PRG_CHAR
 cmp #$8f
 bne @data_token
 lda #2
 sta PRG_MODE
@data_token:
 cmp #$83
 bne @go_token
 lda #3
 sta PRG_MODE
@go_token:
 cmp #$cb
 bne @separator
 lda #1
 sta PRG_GO
@separator:
 lda PRG_CHAR
 cmp #$aa
 bcc @space
 cmp #$af
 bcc @again
 cmp #$b1
 bcc @space
 cmp #$b4
 bcc @again
@space:
 lda #' '
 jsr prg_put
@again:
 jmp @byte
@converted:
 lda PRG_GO
 JNE prg_fail
 lda PRG_ADDRESS
 cmp PRG_NEXT
 JNE prg_fail
 lda PRG_ADDRESS+1
 cmp PRG_NEXT+1
 JNE prg_fail
 lda INPUT_LEN
 JEQ prg_fail
 tax
 lda #0
 sta INPUT_BUFFER,x
 sta INPUT_POS
 COMMAND_CALL tokenize_input
 COMMAND_CALL edit_line
 lda #1
 sta PRG_HAVE_LINE
 jmp @line
@end:
 lda $90
 cmp #$40 ; trailing machine code/resources are not a BASIC source program
 JNE prg_fail
 rts

prg_get:
 lda $90
 JNE prg_fail ; EOF or a device error before the requested byte
 lda PRG_ADDRESS+1
 cmp #$a0
 JCS prg_fail
 jsr $ffcf
 pha
 lda $90
 and #$bf
 JNE prg_fail
 inc PRG_ADDRESS
 bne :+
 inc PRG_ADDRESS+1
:
 pla
 rts
prg_put:
 ldx INPUT_LEN
 cpx #255
 JCS prg_fail
 sta INPUT_BUFFER,x
 inc INPUT_LEN
 rts
prg_integer_name:
 lda INPUT_LEN
 cmp #250
 JCS prg_fail
 tax
@shift:
 dex
 lda INPUT_BUFFER,x
 sta INPUT_BUFFER+6,x
 cpx PRG_NAME_START
 bne @shift
 ldx PRG_NAME_START
 ldy #0
@prefix:
 lda prg_integer_prefix,y
 sta INPUT_BUFFER,x
 inx
 iny
 cpy #6
 bne @prefix
 clc
 lda INPUT_LEN
 adc #6
 sta INPUT_LEN
 rts
prg_integer_prefix: .byte "PRGINT"
prg_fail:
 lda #ERR_SYNTAX
 COMMAND_CALL command_error
 ; command_error abandons the gate stack via READY after staged rollback.

.include "prg_keywords.inc"
