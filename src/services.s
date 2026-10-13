.segment "SERVICES"
; Cold execution services in Magic Desk bank 2; shared state remains in RAM.
rom_restore_data:
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
 RAM_CALL runtime_error
 rts
:
 lda DATA_LINE
 sta PTR
 lda DATA_LINE+1
 sta PTR+1
 ldy #5
 jsr read_ram
 sta DATA_TOKEN_PTR
 iny
 jsr read_ram
 sta DATA_TOKEN_PTR+1
 lda DATA_TOKEN_PTR
 sta PTR
 lda DATA_TOKEN_PTR+1
 sta PTR+1
 ldy #0
 jsr read_ram
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
 jsr read_ram
 sec
 sbc #2
 sta PTR2
 iny
 jsr read_ram
 sbc #0
 sta PTR2+1
 lda PTR2
 sta PTR
 lda PTR2+1
 sta PTR+1
 ldy #0
 jsr read_ram
 clc
 adc PTR2
 sta TMP
 iny
 jsr read_ram
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
 jsr read_ram
 sta DATA_LINE
 iny
 jsr read_ram
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
 jsr read_ram
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
 RAM_CALL runtime_error
 rts
rom_read_number:
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
 RAM_CALL push_number
 rts
@positive:
 lda FRAME_LIMIT
 ldx FRAME_LIMIT+1
 RAM_CALL push_number
 rts
@text:
 RAM_CALL push_string
 RAM_CALL val_word
 rts
rom_read_string:
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
 RAM_CALL format_unsigned
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
 RAM_CALL copy_string
 RAM_CALL push_string
 rts
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
 RAM_CALL copy_string
 RAM_CALL push_string
 rts
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
rom_activate_function:
 ; The RAM stub consumed the native return PC and saved entry A/X in FRAME_PC.
 lda SOURCE
 sta PTR
 lda SOURCE+1
 sta PTR+1
 ldy #1
 jsr read_ram
 sta PTR2
 iny
 jsr read_ram
 sta PTR2+1
 iny
 jsr read_ram
 sta TMP
 iny
 jsr read_ram
 sta TMP+1
 lda PTR2
 sta PTR
 lda PTR2+1
 sta PTR+1
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
 rts
rom_file_word:
 sta FILE_OPERATION
 RAM_CALL byte_quantity
 sta FILE_DEVICE
 cmp #3
 bcs :+
 RAM_CALL unsupported_word
 rts
:
 RAM_CALL pop_string
 lda STRING_LENGTH
 sta FILE_NAME_LEN
 lda STRING_PTR
 sta PTR
 lda STRING_PTR+1
 sta PTR+1
 ldy #0
@stage:
 cpy FILE_NAME_LEN
 beq @ready
 jsr read_ram
 sta BRIDGE,y
 iny
 bne @stage
@ready:
 jmp file_entry

rom_open_word:
 RAM_CALL pop_string
 lda STRING_LENGTH
 sta FILE_NAME_LEN
 lda STRING_PTR
 sta PTR
 lda STRING_PTR+1
 sta PTR+1
 ldy #0
@name:
 cpy FILE_NAME_LEN
 beq @arguments
 jsr read_ram
 sta BRIDGE,y
 iny
 bne @name
@arguments:
 RAM_CALL byte_quantity
 sta DEVICE_SECONDARY
 RAM_CALL byte_quantity
 sta DEVICE_NUMBER
 cmp #1
 JEQ rom_unsupported
 cmp #2
 JEQ rom_unsupported
 RAM_CALL byte_quantity
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
 RAM_CALL runtime_error
 rts
device_ok:
 rts
rom_close_word:
 RAM_CALL byte_quantity
 pha
 lda #<$ffc3
 sta service_call+1
 lda #>$ffc3
 sta service_call+2
 pla
 jmp kernal_gate
rom_output_channel:
 lda #<$ffc9
 bne select_channel
rom_input_channel:
 lda #<$ffc6
select_channel:
 pha
 RAM_CALL byte_quantity
 tax
 pla
 sta service_call+1
 lda #>$ffc6
 sta service_call+2
 jsr kernal_gate
 bcs device_error
 rts
rom_reset_channel:
 lda #<$ffcc
 sta service_call+1
 lda #>$ffcc
 sta service_call+2
 jmp kernal_gate
rom_input_prompt:
 lda #'?'
 RAM_CALL char_out
 lda #' '
 RAM_CALL char_out
 rts
rom_get_number:
 RAM_CALL pop_string
 lda STRING_LENGTH
 beq @empty
 lda STRING_PTR
 sta PTR
 lda STRING_PTR+1
 sta PTR+1
 ldy #0
 jsr read_ram
 cmp #'0'
 bcc @invalid
 cmp #'9'+1
 bcs @invalid
 sec
 sbc #'0'
@empty:
 ldx #0
 RAM_CALL push_number
 rts
@invalid:
 lda #ERR_QUANTITY
 RAM_CALL runtime_error
 rts
rom_input_field:
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
 RAM_CALL copy_string
 RAM_CALL push_string
 rts
@too_long:
 lda #ERR_STRING
 RAM_CALL runtime_error
 rts


rom_unsupported:
 RAM_CALL unsupported_word
 rts
