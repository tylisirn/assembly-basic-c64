.segment "BINARY_EDITOR"
.macro BE_TEXT label
 lda #<label
 ldx #>label
 jsr be_puts
.endmacro
be_open:
 cmp #2
 beq :+
 lda ED_ACTIVE
:
 sta BE_CALLER
 lda #1
 sta BE_UI_ACTIVE
 lda $cc
 sta BE_OLD_CC
 lda #1
 sta $cc
 lda #0
 sta $cf
 sta BE_MODE
 sta BE_TOP
 sta BE_TOP+1
 sta BE_FLAGS
 sta BE_RES_SEL
 lda #$ff
 sta BE_BLOB_SEL
 ldx #$2e
@vic:
 lda $d000,x
 sta BE_VIC,x
 dex
 bpl @vic
 lda $dd00
 sta BE_VIC+$30
 ldx #7
@pointers:
 lda $07f8,x
 sta BE_VIC+$31,x
 dex
 bpl @pointers
 lda BE_CALLER
 beq @screen
 ldx #0
@pane:
 lda $0748,x
 sta BE_PANE,x
 lda $db48,x
 sta BE_PANE+160,x
 inx
 cpx #160
 bne @pane
@screen:
 lda $dd00
 ora #3
 sta $dd00
 lda #$14
 sta $d018
 lda #$1b
 sta $d011
 lda #8
 sta $d016
 lda #14
 sta $d020
 lda #6
 sta $d021
 lda #0
 sta $d015
 jsr be_first_res
 jmp be_render
be_restore_selection:
 lda BE_FLAGS
 and #1
 beq @done
 lda BE_OLD_COLOR
 sta BE_RES_SEL
 lda BE_FLAGS
 and #$fe
 sta BE_FLAGS
@done:
 rts
be_first_res:
 lda #0
 sta BE_RES_SEL
@next:
 lda BE_RES_SEL
 STORAGE_CALL be_res_used
 bne @done
 inc BE_RES_SEL
 lda BE_RES_SEL
 cmp #8
 bne @next
 lda #$ff
 sta BE_RES_SEL
@done:
 rts
be_render:
 jsr be_restore_selection
 lda BE_FLAGS
 JMI be_exit
 lda BE_MODE
 cmp #2
 JEQ be_hex_draw
 cmp #3
 JEQ be_sprite_draw
 jsr be_list_draw
 jmp be_wait
be_wait:
 lda PENDING
 JNE be_exit
 jsr $ffe4
 cmp #0
 beq be_wait
 sta BE_CHAR
 cmp #$88
 JEQ be_exit
 cmp #95
 JEQ be_back
 lda BE_MODE
 cmp #2
 JEQ be_hex_key
 cmp #3
 JEQ be_sprite_key
 lda BE_CHAR
 cmp #$91
 JEQ be_select_up
 cmp #$11
 JEQ be_select_down
 cmp #13
 JEQ be_enter
 cmp #$14
 JEQ be_delete
 jsr be_upper
 cmp #'N'
 JEQ be_new
 cmp #'R'
 JEQ be_resize
 cmp #'C'
 JEQ be_change_type
 cmp #'S'
 JEQ be_save
 cmp #'L'
 JEQ be_load
 jmp be_wait
be_exit:
 lda #0
 sta BE_UI_ACTIVE
 sta PENDING
 ldx #$2e
@vic:
 cpx #$12
 bcc @write
 cpx #$15
 bcc @next
 cpx #$19
 beq @next
 cpx #$1e
 beq @next
 cpx #$1f
 beq @next
@write:
 lda BE_VIC,x
 sta $d000,x
@next:
 dex
 bpl @vic
 lda BE_VIC+$30
 sta $dd00
 ldx #7
@pointers:
 lda BE_VIC+$31,x
 sta $07f8,x
 dex
 bpl @pointers
 lda BE_CALLER
 beq @stock
 cmp #2
 bne @basic
 ldx #0
@input:
 lda BE_INPUT_BACKUP,x
 sta INPUT_BUFFER,x
 inx
 cpx #160
 bne @input
@basic:
 EDITOR_CALL editor_binary_restore
 ldx #0
@pane:
 lda BE_PANE,x
 sta $0748,x
 lda BE_PANE+160,x
 sta $db48,x
 inx
 cpx #160
 bne @pane
 jmp @cursor
@stock:
 jsr be_clear
@cursor:
 lda BE_OLD_CC
 sta $cc
 rts
be_back:
 lda BE_MODE
 beq be_exit
 cmp #1
 bne @blobs
 lda #0
 sta BE_MODE
 jmp @reset
@blobs:
 lda #1
 sta BE_MODE
 lda #0
 sta $d015
@reset:
 lda #0
 sta BE_TOP
 sta BE_TOP+1
 jmp be_render
be_upper:
 cmp #'a'
 bcc @done
 cmp #'z'+1
 bcs @done
 and #$df
@done:
 rts
be_clear:
 ldx #0
 lda #32
@chars:
 sta $0400,x
 sta $0500,x
 sta $0600,x
 inx
 bne @chars
 ldx #0
@tail:
 sta $0700,x
 inx
 cpx #232
 bne @tail
 ldx #0
 lda #14
@colors:
 sta $d800,x
 sta $d900,x
 sta $da00,x
 inx
 bne @colors
 ldx #0
@color_tail:
 sta $db00,x
 inx
 cpx #232
 bne @color_tail
 lda #0
 sta BE_ROW
 sta BE_COL
 sta BE_REVERSE
 lda #14
 sta BE_COLOR
 rts
be_putc:
 pha
 txa
 pha
 tya
 pha
 tsx
 lda $0103,x
 cmp #13
 beq @newline
 jsr be_code
 ora BE_REVERSE
 pha
 ldx BE_ROW
 cpx #25
 bcs @skip
 lda be_rows_lo,x
 sta ED_PTR
 lda be_rows_hi,x
 sta ED_PTR+1
 clc
 adc #$d4
 sta ED_CPTR+1
 lda ED_PTR
 sta ED_CPTR
 ldy BE_COL
 cpy #40
 bcs @skip
 pla
 sta (ED_PTR),y
 lda BE_COLOR
 sta (ED_CPTR),y
 jmp @advance
@skip:
 pla
@advance:
 inc BE_COL
 jmp @return
@newline:
 inc BE_ROW
 lda #0
 sta BE_COL
@return:
 pla
 tay
 pla
 tax
 pla
 rts
be_code:
 cmp #32
 bcc @control
 cmp #$80
 bcc @low
 cmp #$a0
 bcc @high
 cmp #$ff
 beq @pi
 and #$7f
 rts
@low:
 cmp #$60
 bcc @ascii
 and #$5f
 rts
@ascii:
 and #$3f
 rts
@control:
 ora #$80
 rts
@high:
 and #$1f
 ora #$c0
 rts
@pi:
 lda #$5e
 rts
be_puts:
 sta PTR2
 stx PTR2+1
 ldy #0
@char:
 lda (PTR2),y
 beq @done
 jsr be_putc
 iny
 bne @char
 inc PTR2+1
 jmp @char
@done:
 rts
be_hex_digit:
 and #15
 cmp #10
 bcc :+
 adc #6
:
 adc #'0'
 jmp be_putc
be_hex_byte:
 pha
 lsr
 lsr
 lsr
 lsr
 jsr be_hex_digit
 pla
 jmp be_hex_digit
be_address:
 lda #'$'
 jsr be_putc
 lda BE_NUMBER+1
 jsr be_hex_byte
 lda BE_NUMBER
 jmp be_hex_byte
be_decimal:
 lda BE_NUMBER
 ldx BE_NUMBER+1
 COMMAND_CALL print_source_number_buffer
 ldx #0
@digit:
 lda NUM_BUFFER,x
 jsr be_putc
 inx
 cpx COUNT
 bcc @digit
 rts
be_print_range:
 lda BE_RANGE
 sta BE_NUMBER
 lda BE_RANGE+1
 sta BE_NUMBER+1
 jsr be_address
 BE_TEXT be_dash
 sec
 lda BE_END
 sbc #1
 sta BE_NUMBER
 lda BE_END+1
 sbc #0
 sta BE_NUMBER+1
 jmp be_address
be_print_size:
 lda BE_SIZE
 sta BE_NUMBER
 lda BE_SIZE+1
 sta BE_NUMBER+1
 jsr be_decimal
 BE_TEXT be_open_hex
 jsr be_address
 BE_TEXT be_bytes
 rts
be_list_line:
 lda BE_LINE
 cmp BE_TOP
 bcc @hide
 sec
 sbc BE_TOP
 cmp #19
 bcs @hide
 clc
 adc #1
 sta BE_ROW
 bne @col
@hide:
 lda #25
 sta BE_ROW
@col:
 lda #0
 sta BE_COL
 rts
be_line_end:
 lda BE_REVERSE
 beq @done
@fill:
 lda BE_COL
 cmp #40
 bcs @done
 lda #' '
 jsr be_putc
 jmp @fill
@done:
 lda #0
 sta BE_REVERSE
 inc BE_LINE
 rts
be_list_draw:
 jsr be_clear
 BE_TEXT be_res_title
 lda #0
 sta BE_LINE
 sta BE_INDEX
 lda #$ff
 sta BE_SELECTED_ROW
@res:
 lda BE_INDEX
 STORAGE_CALL be_res_used
 JEQ @next_res
 lda BE_INDEX
 STORAGE_CALL be_get_res
 jsr be_list_line
 lda BE_MODE
 bne @header
 lda BE_INDEX
 cmp BE_RES_SEL
 bne @header
 lda BE_LINE
 sta BE_SELECTED_ROW
 lda #$80
 sta BE_REVERSE
@header:
 lda BE_RANGE
 sta BE_NUMBER
 lda BE_RANGE+1
 sta BE_NUMBER+1
 jsr be_address
 BE_TEXT be_colon
 jsr be_print_size
 lda BE_INDEX
 STORAGE_CALL be_bit
 and BE_BASIC
 beq :+
 BE_TEXT be_basic_label
:
 jsr be_line_end
 lda #0
 sta BE_MATCH
@blob:
 lda BE_MATCH
 STORAGE_CALL be_blob_used
 JEQ @next_blob
 lda BE_MATCH
 STORAGE_CALL be_get_blob
 lda BE_RECORD
 cmp BE_INDEX
 JNE @next_blob
 jsr be_list_line
 lda BE_MODE
 cmp #1
 bne @blob_text
 lda BE_MATCH
 cmp BE_BLOB_SEL
 bne @blob_text
 lda BE_LINE
 sta BE_SELECTED_ROW
 lda #$80
 sta BE_REVERSE
@blob_text:
 BE_TEXT be_indent
 jsr be_record_range
 jsr be_print_range
 lda #' '
 jsr be_putc
 jsr be_type_text
 lda BE_RECORD+5
 and #$7f
 cmp #1
 beq @sprite
 lda #' '
 jsr be_putc
 jsr be_print_size
 jmp @blob_end
@sprite:
 lda BE_RECORD+5
 bmi @multi
 BE_TEXT be_hires
 jmp @swatches
@multi:
 BE_TEXT be_multicolor
@swatches:
 lda #35
 sta BE_COL
 jsr be_swatches
@blob_end:
 jsr be_line_end
@next_blob:
 inc BE_MATCH
 lda BE_MATCH
 cmp #16
 JNE @blob
 lda BE_INDEX
 STORAGE_CALL be_get_res
 jsr be_list_line
 sec
 lda BE_END
 sbc #1
 sta BE_NUMBER
 lda BE_END+1
 sbc #0
 sta BE_NUMBER+1
 jsr be_address
 jsr be_line_end
 inc BE_LINE
@next_res:
 inc BE_INDEX
 lda BE_INDEX
 cmp #8
 JNE @res
 lda BE_SELECTED_ROW
 cmp #$ff
 beq @status
 cmp BE_TOP
 bcc @above
 sec
 sbc BE_TOP
 cmp #19
 bcc @status
 sec
 lda BE_SELECTED_ROW
 sbc #18
 sta BE_TOP
 jmp be_list_draw
@above:
 sta BE_TOP
 jmp be_list_draw
@status:
 lda #20
 sta BE_ROW
 lda #0
 sta BE_COL
 lda BE_MODE
 bne @blob_status
 lda BE_RES_SEL
 cmp #8
 bcs @keys
 STORAGE_CALL be_get_res
 BE_TEXT be_res_status
 jsr be_print_range
 jmp @keys
@blob_status:
 lda BE_BLOB_SEL
 cmp #16
 bcs @keys
 STORAGE_CALL be_get_blob
 jsr be_record_range
 jsr be_type_text
 lda #' '
 jsr be_putc
 jsr be_print_range
@keys:
 lda #22
 sta BE_ROW
 lda #0
 sta BE_COL
 lda BE_MODE
 bne @blob_keys
 BE_TEXT be_res_keys
 rts
@blob_keys:
 BE_TEXT be_blob_keys
 rts
be_record_range:
 lda BE_RECORD+1
 sta BE_RANGE
 lda BE_RECORD+2
 sta BE_RANGE+1
 lda BE_RECORD+3
 sta BE_SIZE
 lda BE_RECORD+4
 sta BE_SIZE+1
 clc
 lda BE_RANGE
 adc BE_SIZE
 sta BE_END
 lda BE_RANGE+1
 adc BE_SIZE+1
 sta BE_END+1
 rts
be_type_text:
 lda BE_RECORD+5
 and #$7f
 tax
 lda be_types_lo,x
 pha
 lda be_types_hi,x
 tax
 pla
 jmp be_puts
be_swatches:
 lda BE_RECORD+6
 and #15
 sta BE_COLOR
 jsr be_solid
 lda BE_RECORD+6
 lsr
 lsr
 lsr
 lsr
 sta BE_COLOR
 jsr be_solid
 lda BE_RECORD+5
 bpl @done
 lda BE_RECORD+7
 and #15
 sta BE_COLOR
 jsr be_solid
 lda BE_RECORD+7
 lsr
 lsr
 lsr
 lsr
 sta BE_COLOR
 jsr be_solid
@done:
 lda #14
 sta BE_COLOR
 rts
be_select_up:
 lda #$ff
 sta BE_LIMIT
 jmp be_select
be_select_down:
 lda #1
 sta BE_LIMIT
be_select:
 lda BE_MODE
 beq @res
 lda BE_BLOB_SEL
 cmp #16
 bcs @done
 sta BE_INDEX
@blob_step:
 clc
 lda BE_INDEX
 adc BE_LIMIT
 sta BE_INDEX
 cmp #16
 bcs @done
 STORAGE_CALL be_blob_used
 beq @blob_step
 lda BE_INDEX
 STORAGE_CALL be_get_blob
 lda BE_RECORD
 cmp BE_RES_SEL
 bne @blob_step
 lda BE_INDEX
 sta BE_BLOB_SEL
 jmp be_render
@res:
 lda BE_RES_SEL
 cmp #8
 bcs @done
 sta BE_INDEX
@res_step:
 clc
 lda BE_INDEX
 adc BE_LIMIT
 sta BE_INDEX
 cmp #8
 bcs @done
 STORAGE_CALL be_res_used
 beq @res_step
 lda BE_INDEX
 sta BE_RES_SEL
 jmp be_render
@done:
 jmp be_wait
be_enter:
 lda BE_MODE
 bne @edit
 lda BE_RES_SEL
 cmp #8
 JCS be_wait
 lda #1
 sta BE_MODE
 lda #0
 sta BE_TOP
 sta BE_INDEX
 lda #$ff
 sta BE_BLOB_SEL
@first:
 lda BE_INDEX
 STORAGE_CALL be_blob_used
 beq @next
 lda BE_INDEX
 STORAGE_CALL be_get_blob
 lda BE_RECORD
 cmp BE_RES_SEL
 bne @next
 lda BE_INDEX
 sta BE_BLOB_SEL
 jmp be_render
@next:
 inc BE_INDEX
 lda BE_INDEX
 cmp #16
 bne @first
 jmp be_render
@edit:
 lda BE_BLOB_SEL
 cmp #16
 JCS be_wait
 STORAGE_CALL be_get_blob
 lda #0
 sta BE_TOP
 sta BE_TOP+1
 sta BE_POS
 sta BE_POS+1
 sta BE_X
 sta BE_Y
 sta BE_NIBBLE
 lda BE_RECORD+5
 and #$7f
 cmp #1
 bne @hex
 lda #3
 sta BE_MODE
 jmp be_render
@hex:
 lda #2
 sta BE_MODE
 jmp be_render
be_new:
 lda BE_MODE
 bne @blob
 lda BE_RES_SEL
 sta BE_OLD_COLOR
 STORAGE_CALL be_free_res_slot
 JCS be_operation_error
 lda BE_FLAGS
 ora #1
 sta BE_FLAGS
 jmp be_res_bounds_prompt
@blob:
 lda BE_RES_SEL
 cmp #8
 JCS be_wait
 jsr be_type_prompt
 JCS be_render
 sta BE_RECORD+5
 cmp #1
 bne @size
 lda #64
 sta BE_PROPOSED
 lda #0
 sta BE_PROPOSED+1
 beq @create
@size:
 lda #<be_size_prompt
 ldx #>be_size_prompt
 jsr be_prompt_number
 JCS be_render
 lda BE_NUMBER
 sta BE_PROPOSED
 lda BE_NUMBER+1
 sta BE_PROPOSED+1
@create:
 STORAGE_CALL be_new_blob
 JCS be_operation_error
 jmp be_render
be_res_bounds_prompt:
 lda #<be_start_prompt
 ldx #>be_start_prompt
 jsr be_prompt_number
 JCS be_render
 lda BE_NUMBER
 sta BE_PROPOSED
 lda BE_NUMBER+1
 sta BE_PROPOSED+1
 lda #<be_size_prompt
 ldx #>be_size_prompt
 jsr be_prompt_number
 JCS be_render
 lda BE_NUMBER
 sta BE_SIZE
 lda BE_NUMBER+1
 sta BE_SIZE+1
 lda BE_PROPOSED
 sta BE_RANGE
 lda BE_PROPOSED+1
 sta BE_RANGE+1
 STORAGE_CALL be_reserve_exact
 JCS be_operation_error
 lda BE_FLAGS
 and #$fe
 sta BE_FLAGS
 jmp be_render
be_resize:
 lda BE_MODE
 bne @blob
 lda BE_RES_SEL
 cmp #8
 JCS be_wait
 STORAGE_CALL be_bit
 and BE_BASIC
 JEQ be_res_bounds_prompt
 lda #<be_read_only
 ldx #>be_read_only
 jmp be_notice
@blob:
 lda BE_BLOB_SEL
 cmp #16
 JCS be_wait
 STORAGE_CALL be_get_blob
 lda #<be_start_prompt
 ldx #>be_start_prompt
 jsr be_prompt_number
 JCS be_render
 lda BE_NUMBER
 sta BE_RECORD+1
 lda BE_NUMBER+1
 sta BE_RECORD+2
 lda #<be_size_prompt
 ldx #>be_size_prompt
 jsr be_prompt_number
 JCS be_render
 lda BE_NUMBER
 sta BE_RECORD+3
 lda BE_NUMBER+1
 sta BE_RECORD+4
 STORAGE_CALL be_validate_blob
 JCS be_operation_error
 STORAGE_CALL be_set_blob
 jmp be_render
be_change_type:
 lda BE_BLOB_SEL
 cmp #16
 JCS be_wait
 lda BE_MODE
 JEQ be_wait
 lda BE_BLOB_SEL
 STORAGE_CALL be_get_blob
 jsr be_type_prompt
 JCS be_render
 sta BE_RECORD+5
 cmp #1
 bne @check
 lda #64
 sta BE_RECORD+3
 lda #0
 sta BE_RECORD+4
@check:
 STORAGE_CALL be_validate_blob
 JCS be_operation_error
 STORAGE_CALL be_set_blob
 jmp be_render
be_delete:
 lda BE_MODE
 bne @blob
 lda BE_RES_SEL
 cmp #8
 JCS be_wait
 lda #0
 sta BE_INDEX
@check:
 lda BE_INDEX
 STORAGE_CALL be_blob_used
 beq @next
 lda BE_INDEX
 STORAGE_CALL be_get_blob
 lda BE_RECORD
 cmp BE_RES_SEL
 beq @confirm
@next:
 inc BE_INDEX
 lda BE_INDEX
 cmp #16
 bne @check
 jmp @remove
@confirm:
 lda #<be_delete_prompt
 ldx #>be_delete_prompt
 jsr be_prompt_label
 jsr be_modal_key
 jsr be_upper
 cmp #'Y'
 JNE be_render
@remove:
 STORAGE_CALL be_delete_res
 jsr be_first_res
 jmp be_render
@blob:
 lda BE_BLOB_SEL
 cmp #16
 JCS be_wait
 STORAGE_CALL be_delete_blob
 lda #0
 sta BE_MODE
 jmp be_enter
be_save:
 lda #'W'
 bne be_transfer
be_load:
 lda #'R'
be_transfer:
 sta BE_FILE_OP
 lda BE_MODE
 bne @blob
 lda BE_RES_SEL
 cmp #8
 JCS be_wait
 STORAGE_CALL be_get_res
 jmp @prompt
@blob:
 lda BE_BLOB_SEL
 cmp #16
 JCS be_wait
 STORAGE_CALL be_get_blob
 jsr be_record_range
@prompt:
 lda #<be_file_prompt
 ldx #>be_file_prompt
 jsr be_prompt_text
 JCS be_render
 STORAGE_CALL be_transfer_bytes
 JCS be_operation_error
 jmp be_render
be_operation_error:
 sta BE_ERROR
 cmp #ERR_DATA
 bne @range
 lda #<be_file_error
 ldx #>be_file_error
 jmp be_notice
@range:
 lda #<be_range_error
 ldx #>be_range_error
 jmp be_notice
be_notice:
 pha
 txa
 pha
 jsr be_restore_selection
 jsr be_render_scene
 pla
 tax
 pla
 jsr be_prompt_label
 jmp be_wait
be_render_scene:
 lda BE_MODE
 cmp #2
 JEQ be_hex_draw_scene
 cmp #3
 JEQ be_sprite_draw_scene
 jmp be_list_draw

; Shared bounded prompts. Numeric values accept decimal or a $ hexadecimal prefix.
be_prompt_number:
 pha
 lda #1
 sta BE_PROMPT_KIND
 pla
 bne be_prompt
be_prompt_text:
 pha
 lda #0
 sta BE_PROMPT_KIND
 pla
be_prompt:
 sta BE_STRING
 stx BE_STRING+1
 lda #0
 sta BE_PROMPT_LEN
 jsr be_prompt_redraw
be_prompt_wait:
 jsr $ffe4
 cmp #0
 beq be_prompt_wait
 cmp #$88
 beq @exit
 cmp #95
 beq @cancel
 cmp #13
 beq @submit
 cmp #$14
 beq @delete
 cmp #32
 bcc be_prompt_wait
 ldx BE_PROMPT_LEN
 cpx #51
 bcs be_prompt_wait
 sta BE_INPUT,x
 inc BE_PROMPT_LEN
 jsr be_prompt_redraw
 jmp be_prompt_wait
@delete:
 lda BE_PROMPT_LEN
 beq be_prompt_wait
 dec BE_PROMPT_LEN
 jsr be_prompt_redraw
 jmp be_prompt_wait
@submit:
 lda BE_PROMPT_LEN
 beq be_prompt_wait
 ldx BE_PROMPT_LEN
 lda #0
 sta BE_INPUT,x
 lda BE_PROMPT_KIND
 beq @ok
 jsr be_parse_number
 bcs be_prompt_wait
@ok:
 clc
 rts
@exit:
 lda #$80
 sta BE_FLAGS
@cancel:
 sec
 rts
be_prompt_label:
 sta BE_STRING
 stx BE_STRING+1
 lda #22
 sta BE_ROW
@clear:
 lda #0
 sta BE_COL
@line:
 lda #' '
 jsr be_putc
 lda BE_COL
 cmp #40
 bcc @line
 inc BE_ROW
 lda BE_ROW
 cmp #25
 bcc @clear
 lda #23
 sta BE_ROW
 lda #0
 sta BE_COL
 lda BE_STRING
 ldx BE_STRING+1
 jmp be_puts
be_prompt_redraw:
 lda BE_STRING
 ldx BE_STRING+1
 jsr be_prompt_label
 lda #24
 sta BE_ROW
 lda #0
 sta BE_COL
 ldx #0
 lda BE_PROMPT_LEN
 cmp #39
 bcc @text
 sec
 sbc #39
 tax
@text:
 cpx BE_PROMPT_LEN
 beq @cursor
 lda BE_INPUT,x
 jsr be_putc
 inx
 bne @text
@cursor:
 lda #$80
 sta BE_REVERSE
 lda #' '
 jsr be_putc
 lda #0
 sta BE_REVERSE
 rts
be_modal_key:
 jsr $ffe4
 cmp #0
 beq be_modal_key
 cmp #$88
 bne @done
 lda #$80
 sta BE_FLAGS
 lda #95
@done:
 rts
be_type_prompt:
 lda #<be_type_question
 ldx #>be_type_question
 jsr be_prompt_label
 jsr be_modal_key
 jsr be_upper
 cmp #'S'
 beq @sprite
 cmp #'B'
 beq @binary
 cmp #'A'
 beq @asm
 sec
 rts
@sprite:
 lda #1
 clc
 rts
@binary:
 lda #0
 clc
 rts
@asm:
 lda #2
 clc
 rts
be_parse_number:
 lda #0
 sta BE_NUMBER
 sta BE_NUMBER+1
 ldx #0
 lda #10
 sta BE_LIMIT
 lda BE_INPUT
 cmp #'$'
 bne @loop
 lda #16
 sta BE_LIMIT
 inx
 cpx BE_PROMPT_LEN
 beq @bad
@loop:
 lda BE_INPUT,x
 jsr be_upper
 cmp #'0'
 bcc @bad
 cmp #'9'+1
 bcc @digit
 cmp #'A'
 bcc @bad
 cmp #'F'+1
 bcs @bad
 sec
 sbc #7
@digit:
 sec
 sbc #'0'
 cmp BE_LIMIT
 bcs @bad
 sta BE_TEMP
 ; Multiply with overflow detection; at most sixteen additions per digit.
 lda BE_NUMBER
 sta LEFT
 lda BE_NUMBER+1
 sta LEFT+1
 lda #0
 sta BE_NUMBER
 sta BE_NUMBER+1
 ldy BE_LIMIT
@multiply:
 clc
 lda BE_NUMBER
 adc LEFT
 sta BE_NUMBER
 lda BE_NUMBER+1
 adc LEFT+1
 sta BE_NUMBER+1
 bcs @bad
 dey
 bne @multiply
 clc
 lda BE_NUMBER
 adc BE_TEMP
 sta BE_NUMBER
 lda BE_NUMBER+1
 adc #0
 sta BE_NUMBER+1
 bcs @bad
 inx
 cpx BE_PROMPT_LEN
 bne @loop
 clc
 rts
@bad:
 sec
 rts

be_res_title: .byte "RESERVATIONS",0
be_res_status: .byte "RESERVATION ",0
be_colon: .byte " : ",0
be_indent: .byte "  ",0
be_dash: .byte " - ",0
be_open_hex: .byte " (",0
be_bytes: .byte ") BYTES",0
be_basic_label: .byte " (BASIC)",0
be_hires: .byte " HIRES",0
be_multicolor: .byte " MULTICOLOR",0
be_type_bin: .byte "BIN",0
be_type_spr: .byte "SPR",0
be_type_asm: .byte "ASM",0
be_types_lo: .byte <be_type_bin,<be_type_spr,<be_type_asm
be_types_hi: .byte >be_type_bin,>be_type_spr,>be_type_asm
be_res_keys:
 .byte "N NEW RESERVATION DEL REMOVE RESERVATION",13
 .byte "R RESIZE RESERVATION RET EDIT BLOBS",13
 .byte "S SAVE BYTES L LOAD BYTES F7 EXIT",0
be_blob_keys:
 .byte "N NEW BLOB DEL REMOVE BLOB",13
 .byte "R RESIZE C CHANGE TYPE ",95," BACK",13
 .byte "S SAVE L LOAD RET EDIT BLOB F7 EXIT",0
be_start_prompt: .byte "START ADDRESS ($HEX OR DECIMAL)",0
be_size_prompt: .byte "SIZE IN BYTES ($HEX OR DECIMAL)",0
be_file_prompt: .byte "FILENAME (.BIN)  /  ",95," CANCEL",0
be_type_question: .byte "TYPE: S SPRITE  B BINARY  A ASM",0
be_delete_prompt: .byte "DELETE RESERVATION AND BLOBS? Y/N",0
be_file_error: .byte "FILE I/O ERROR",0
be_range_error: .byte "INVALID RANGE / OVERLAP / OUT OF MEMORY",0
be_read_only: .byte "BASIC RESERVATION BOUNDS ARE READ ONLY",0
be_prompt_start_setup: .byte 0
be_rows_lo:
 .repeat 25,I
 .byte <($0400+I*40)
 .endrepeat
be_rows_hi:
 .repeat 25,I
 .byte >($0400+I*40)
 .endrepeat

be_read_byte:
 lda BE_ADDR
 sta PTR
 lda BE_ADDR+1
 sta PTR+1
 ldy #0
 jmp read_ram
be_write_byte:
 pha
 lda BE_ADDR
 sta PTR
 lda BE_ADDR+1
 sta PTR+1
 ldy #0
 pla
 sta (PTR),y
 rts
be_at_position:
 clc
 lda BE_RANGE
 adc BE_POS
 sta BE_ADDR
 lda BE_RANGE+1
 adc BE_POS+1
 sta BE_ADDR+1
 rts
be_fill:
 lda BE_RANGE
 sta BE_ADDR
 lda BE_RANGE+1
 sta BE_ADDR+1
 lda BE_SIZE
 sta BE_COUNT
 lda BE_SIZE+1
 sta BE_COUNT+1
@byte:
 lda BE_COUNT
 ora BE_COUNT+1
 beq @done
 lda BE_PIXEL
 jsr be_write_byte
 inc BE_ADDR
 bne :+
 inc BE_ADDR+1
:
 lda BE_COUNT
 bne :+
 dec BE_COUNT+1
:
 dec BE_COUNT
 jmp @byte
@done:
 rts
be_hex_draw:
 jsr be_hex_draw_scene
 jmp be_wait
be_hex_draw_scene:
 jsr be_clear
 lda BE_BLOB_SEL
 STORAGE_CALL be_get_blob
 jsr be_record_range
 lda BE_POS
 cmp BE_SIZE
 lda BE_POS+1
 sbc BE_SIZE+1
 bcc @view
 sec
 lda BE_SIZE
 sbc #1
 sta BE_POS
 lda BE_SIZE+1
 sbc #0
 sta BE_POS+1
@view:
 lda BE_POS
 cmp BE_TOP
 lda BE_POS+1
 sbc BE_TOP+1
 bcc @top
 clc
 lda BE_TOP
 adc #160
 sta LEFT
 lda BE_TOP+1
 adc #0
 sta LEFT+1
 lda BE_POS
 cmp LEFT
 lda BE_POS+1
 sbc LEFT+1
 bcc @header
 sec
 lda BE_POS
 and #$f8
 sbc #152
 sta BE_TOP
 lda BE_POS+1
 sbc #0
 sta BE_TOP+1
 jmp @header
@top:
 lda BE_POS
 and #$f8
 sta BE_TOP
 lda BE_POS+1
 sta BE_TOP+1
@header:
 jsr be_print_range
 lda #' '
 jsr be_putc
 jsr be_type_text
 lda #' '
 jsr be_putc
 jsr be_print_size
 lda BE_TOP
 sta BE_WORK+10
 lda BE_TOP+1
 sta BE_WORK+11
 lda #0
 sta BE_INDEX
@row:
 lda BE_INDEX
 clc
 adc #2
 sta BE_ROW
 lda #0
 sta BE_COL
 clc
 lda BE_RANGE
 adc BE_WORK+10
 sta BE_NUMBER
 lda BE_RANGE+1
 adc BE_WORK+11
 sta BE_NUMBER+1
 jsr be_address
 lda #0
 sta BE_MATCH
@cell:
 lda BE_WORK+10
 cmp BE_SIZE
 lda BE_WORK+11
 sbc BE_SIZE+1
 bcs @empty
 clc
 lda BE_RANGE
 adc BE_WORK+10
 sta BE_ADDR
 lda BE_RANGE+1
 adc BE_WORK+11
 sta BE_ADDR+1
 jsr be_read_byte
 sta BE_WORK+12
 lda #0
 sta BE_REVERSE
 lda BE_POS
 cmp BE_WORK+10
 bne @hex
 lda BE_POS+1
 cmp BE_WORK+11
 bne @hex
 lda #$80
 sta BE_REVERSE
@hex:
 lda BE_MATCH
 asl
 clc
 adc BE_MATCH
 adc #7
 sta BE_COL
 lda BE_WORK+12
 jsr be_hex_byte
 lda BE_MATCH
 clc
 adc #32
 sta BE_COL
 lda BE_WORK+12
 cmp #32
 bcc @period
 cmp #$80
 bcc @ascii
 cmp #$a0
 bcs @ascii
@period:
 lda #'.'
@ascii:
 jsr be_putc
 lda #0
 sta BE_REVERSE
@empty:
 inc BE_WORK+10
 bne :+
 inc BE_WORK+11
:
 inc BE_MATCH
 lda BE_MATCH
 cmp #8
 JNE @cell
 inc BE_INDEX
 lda BE_INDEX
 cmp #20
 JNE @row
 lda #23
 sta BE_ROW
 lda #0
 sta BE_COL
 jsr be_at_position
 lda BE_ADDR
 sta BE_NUMBER
 lda BE_ADDR+1
 sta BE_NUMBER+1
 jsr be_address
 jsr be_read_byte
 sta BE_WORK+12
 lda #0
 sta BE_WORK+13
 clc
 lda BE_POS
 adc #1
 sta LEFT
 lda BE_POS+1
 adc #0
 sta LEFT+1
 lda LEFT
 cmp BE_SIZE
 lda LEFT+1
 sbc BE_SIZE+1
 bcs @footer
 inc BE_ADDR
 bne :+
 inc BE_ADDR+1
:
 jsr be_read_byte
 sta BE_WORK+13
@footer:
 BE_TEXT be_two_spaces
 lda #'$'
 jsr be_putc
 lda BE_WORK+12
 jsr be_hex_byte
 BE_TEXT be_paren
 lda BE_WORK+12
 sta BE_NUMBER
 lda #0
 sta BE_NUMBER+1
 jsr be_decimal
 BE_TEXT be_word_gap
 lda BE_WORK+12
 sta BE_NUMBER
 lda BE_WORK+13
 sta BE_NUMBER+1
 jsr be_address
 BE_TEXT be_paren
 jsr be_decimal
 lda #')'
 jsr be_putc
 lda #24
 sta BE_ROW
 lda #0
 sta BE_COL
 BE_TEXT be_hex_keys
 rts
be_hex_key:
 lda BE_CHAR
 cmp #$9d
 JEQ @left
 cmp #$1d
 JEQ @right
 cmp #$91
 JEQ @up
 cmp #$11
 JEQ @down
 cmp #13
 JEQ @right
 cmp #' '
 JEQ @right
 cmp #','
 JEQ @right
 jsr be_upper
 cmp #'S'
 JEQ be_save
 cmp #'L'
 JEQ be_load
 cmp #'I'
 JEQ be_hex_init
 cmp #'T'
 JEQ be_change_type
 jsr be_hex_value
 JCS be_wait
 sta BE_PIXEL
 lda BE_NIBBLE
 cmp #1
 bne @first
 jsr be_at_position
 jsr be_read_byte
 asl
 asl
 asl
 asl
 ora BE_PIXEL
 sta BE_PIXEL
 inc BE_NIBBLE
 jmp @write
@first:
 lda #1
 sta BE_NIBBLE
@write:
 jsr be_at_position
 lda BE_PIXEL
 jsr be_write_byte
 jmp be_render
@left:
 lda BE_POS
 ora BE_POS+1
 JEQ be_wait
 lda BE_POS
 bne :+
 dec BE_POS+1
:
 dec BE_POS
 jmp @moved
@up:
 lda BE_POS+1
 bne :+
 lda BE_POS
 cmp #8
 JCC be_wait
:
 sec
 lda BE_POS
 sbc #8
 sta BE_POS
 lda BE_POS+1
 sbc #0
 sta BE_POS+1
 jmp @moved
@right:
 lda #1
 bne @advance
@down:
 lda #8
@advance:
 clc
 adc BE_POS
 sta LEFT
 lda BE_POS+1
 adc #0
 sta LEFT+1
 lda LEFT
 cmp BE_SIZE
 lda LEFT+1
 sbc BE_SIZE+1
 JCS be_wait
 lda LEFT
 sta BE_POS
 lda LEFT+1
 sta BE_POS+1
@moved:
 lda #0
 sta BE_NIBBLE
 jmp be_render
be_hex_value:
 cmp #'0'
 bcc @bad
 cmp #'9'+1
 bcc @digit
 cmp #'A'
 bcc @bad
 cmp #'F'+1
 bcs @bad
 sec
 sbc #7
@digit:
 sec
 sbc #'0'
 clc
 rts
@bad:
 sec
 rts
be_hex_init:
 lda #<be_value_prompt
 ldx #>be_value_prompt
 jsr be_prompt_number
 JCS be_render
 lda BE_NUMBER+1
 JNE be_operation_error
 lda BE_NUMBER
 sta BE_PIXEL
 jsr be_fill
 jmp be_render
be_two_spaces: .byte "  ",0
be_paren: .byte " (",0
be_word_gap: .byte ")  ",0
be_hex_keys: .byte "S SAVE L LOAD I INIT T TYPE ",95," BACK",0
be_value_prompt: .byte "INITIALIZE TO BYTE VALUE ($HEX/DEC)",0

be_sprite_draw:
 jsr be_sprite_draw_scene
 jmp be_wait
be_sprite_draw_scene:
 jsr be_clear
 lda BE_BLOB_SEL
 STORAGE_CALL be_get_blob
 jsr be_record_range
 lda #29
 sta BE_COL
 BE_TEXT be_1x
 lda #35
 sta BE_COL
 BE_TEXT be_2x
 lda #0
 sta BE_ROW
 lda #11
 sta BE_COL
 lda BE_RECORD+5
 bpl :+
 lda #20
 sta BE_COL
:
 lda #'1'
 jsr be_putc
 lda BE_RECORD+5
 bmi :+
 lda #21
 sta BE_COL
 lda #'2'
 jsr be_putc
:
 lda #1
 jsr be_sprite_ruler
 lda #23
 jsr be_sprite_ruler
@grid:
 lda #0
 sta BE_INDEX
@row:
 lda BE_INDEX
 clc
 adc #2
 sta BE_ROW
 lda #0
 sta BE_COL
 lda BE_INDEX
 clc
 adc #1
 sta BE_NUMBER
 lda #0
 sta BE_NUMBER+1
 jsr be_decimal
 lda #2
 sta BE_COL
 lda #0
 sta BE_MATCH
@pixel:
 jsr be_pixel_get
 jsr be_pixel_color
 sta BE_COLOR
 jsr be_solid
 lda BE_RECORD+5
 bpl :+
 jsr be_solid
:
 inc BE_MATCH
 lda BE_MATCH
 cmp #12
 bcc @pixel
 lda BE_RECORD+5
 bmi @next_row
 lda BE_MATCH
 cmp #24
 bcc @pixel
@next_row:
 lda #14
 sta BE_COLOR
 inc BE_INDEX
 lda BE_INDEX
 cmp #21
 bne @row
 ; Solid character backgrounds make transparent preview pixels use this
 ; sprite's own background color, independently of the editor background.
 lda BE_RECORD+6
 and #15
 sta BE_COLOR
 lda #2
 sta BE_INDEX
@preview_row:
 lda BE_INDEX
 sta BE_ROW
 lda #34
 sta BE_COL
 ldx #6
@preview:
 jsr be_solid
 dex
 bne @preview
 lda BE_INDEX
 cmp #5
 bcs @preview_next
 lda #28
 sta BE_COL
 ldx #3
@small:
 jsr be_solid
 dex
 bne @small
@preview_next:
 inc BE_INDEX
 lda BE_INDEX
 cmp #8
 bne @preview_row
 lda #14
 sta BE_COLOR
 lda #10
 sta BE_ROW
 lda #28
 sta BE_COL
 BE_TEXT be_sprite_name
 lda BE_RANGE
 sta BE_NUMBER
 lda BE_RANGE+1
 sta BE_NUMBER+1
 jsr be_address
 lda #11
 sta BE_ROW
 lda #28
 sta BE_COL
 lda BE_RECORD+5
 bmi @multi
 BE_TEXT be_type_hires
 jmp @legend
@multi:
 BE_TEXT be_type_multi
@legend:
 lda #13
 sta BE_ROW
 lda #28
 sta BE_COL
 BE_TEXT be_bg_key
 lda BE_RECORD+6
 and #15
 jsr be_panel_swatch
 lda #14
 sta BE_ROW
 lda #28
 sta BE_COL
 BE_TEXT be_sp_key
 lda BE_RECORD+6
 lsr
 lsr
 lsr
 lsr
 jsr be_panel_swatch
 lda BE_RECORD+5
 bpl @byte64
 lda #15
 sta BE_ROW
 lda #28
 sta BE_COL
 BE_TEXT be_c1_key
 lda BE_RECORD+7
 and #15
 jsr be_panel_swatch
 lda #16
 sta BE_ROW
 lda #28
 sta BE_COL
 BE_TEXT be_c2_key
 lda BE_RECORD+7
 lsr
 lsr
 lsr
 lsr
 jsr be_panel_swatch
@byte64:
 lda #18
 sta BE_ROW
 lda #28
 sta BE_COL
 BE_TEXT be_byte64_key
 clc
 lda BE_RANGE
 adc #63
 sta BE_ADDR
 lda BE_RANGE+1
 adc #0
 sta BE_ADDR+1
 jsr be_read_byte
 jsr be_hex_byte
 lda #19
 sta BE_ROW
 lda #28
 sta BE_COL
 BE_TEXT be_colors_key
 lda #20
 sta BE_ROW
 lda #28
 sta BE_COL
 BE_TEXT be_type_key
 lda #21
 sta BE_ROW
 lda #28
 sta BE_COL
 BE_TEXT be_init_key
 lda #22
 sta BE_ROW
 lda #28
 sta BE_COL
 BE_TEXT be_save_key
 lda #23
 sta BE_ROW
 lda #28
 sta BE_COL
 BE_TEXT be_load_key
 lda #24
 sta BE_ROW
 lda #28
 sta BE_COL
 BE_TEXT be_back_key
 jsr be_sprite_hardware
 rts
be_sprite_ruler:
 sta BE_ROW
 lda #2
 sta BE_COL
 lda BE_RECORD+5
 bmi @multi
 BE_TEXT be_ruler_hires
 rts
@multi:
 BE_TEXT be_ruler_multi
 rts
be_ruler_hires: .byte "123456789012345678901234",0
be_ruler_multi: .byte "1.2.3.4.5.6.7.8.9.0.1.2.",0
be_solid:
 lda BE_REVERSE
 pha
 lda #$80
 sta BE_REVERSE
 lda #' '
 jsr be_putc
 pla
 sta BE_REVERSE
 rts
be_panel_swatch:
 sta BE_COLOR
 lda #39
 sta BE_COL
 jsr be_solid
 lda #14
 sta BE_COLOR
 rts
be_pixel_address:
 ; BE_INDEX=row, BE_MATCH=logical pixel. Result address and shift.
 lda BE_INDEX
 asl
 clc
 adc BE_INDEX
 sta BE_WORK+16
 lda BE_MATCH
 lsr
 lsr
 ldx BE_RECORD+5
 bmi :+
 lsr
:
 clc
 adc BE_WORK+16
 clc
 adc BE_RANGE
 sta BE_ADDR
 lda BE_RANGE+1
 adc #0
 sta BE_ADDR+1
 lda BE_MATCH
 ldx BE_RECORD+5
 bmi @multi
 and #7
 eor #7
 sta BE_WORK+17
 lda #1
 rts
@multi:
 and #3
 asl
 eor #6
 sta BE_WORK+17
 lda #3
 rts
be_pixel_get:
 jsr be_pixel_address
 sta BE_WORK+18
 jsr be_read_byte
 ldx BE_WORK+17
 beq @mask
@shift:
 lsr
 dex
 bne @shift
@mask:
 and BE_WORK+18
 rts
be_pixel_color:
 cmp #0
 beq @bg
 ldx BE_RECORD+5
 bpl @sp
 cmp #2
 beq @sp
 cmp #1
 beq @c1
 lda BE_RECORD+7
 jmp @high
@c1:
 lda BE_RECORD+7
 and #15
 rts
@sp:
 lda BE_RECORD+6
@high:
 lsr
 lsr
 lsr
 lsr
 rts
@bg:
 lda BE_RECORD+6
 and #15
 rts
be_sprite_hardware:
 ldy #0
@data:
 tya
 clc
 adc BE_RANGE
 sta PTR
 lda BE_RANGE+1
 adc #0
 sta PTR+1
 tya
 pha
 ldy #0
 jsr read_ram
 sta BE_TEMP
 pla
 tay
 lda BE_TEMP
 sta $0c00,y
 iny
 cpy #64
 bne @data
 ldx #63
@cursor:
 lda BE_RECORD+5
 bmi @wide
 lda be_cursor_black,x
 sta $0c40,x
 lda be_cursor_white,x
 sta $0c80,x
 jmp @next
@wide:
 lda be_cursor_wide_black,x
 sta $0c40,x
 lda be_cursor_wide_white,x
 sta $0c80,x
@next:
 dex
 bpl @cursor
 lda #$31
 sta $07f8
 lda #$32
 sta $07f9
 lda #$30
 sta $07fa
 sta $07fb
 lda #248
 sta $d004
 lda #40
 sta $d006
 lda #66
 sta $d005
 sta $d007
 lda #8
 sta $d010
 sta $d017
 sta $d01d
 lda #0
 sta $d01b
 sta $d01c
 lda BE_RECORD+5
 bpl :+
 lda #12
 sta $d01c
:
 lda #0
 sta $d027
 lda #1
 sta $d028
 lda BE_RECORD+6
 lsr
 lsr
 lsr
 lsr
 sta $d029
 sta $d02a
 lda BE_RECORD+7
 and #15
 sta $d025
 lda BE_RECORD+7
 lsr
 lsr
 lsr
 lsr
 sta $d026
 lda #15
 sta $d015
be_sprite_cursor:
 lda BE_X
 ldx BE_RECORD+5
 bpl :+
 asl
:
 asl
 asl
 asl
 clc
 adc #40
 sta $d000
 sta $d002
 lda BE_Y
 asl
 asl
 asl
 clc
 adc #66
 sta $d001
 sta $d003
 rts
be_sprite_key:
 lda BE_CHAR
 cmp #$9d
 beq @left
 cmp #$1d
 beq @right
 cmp #$91
 JEQ @up
 cmp #$11
 JEQ @down
 cmp #'1'
 JCC @commands
 cmp #'5'
 JCS @commands
 sec
 sbc #'1'
 sta BE_PIXEL
 lda BE_RECORD+5
 bmi @paint
 lda BE_PIXEL
 cmp #2
 JCS be_wait
@paint:
 jsr be_encode_color
 sta BE_PIXEL
 lda BE_X
 sta BE_MATCH
 lda BE_Y
 sta BE_INDEX
 jsr be_pixel_address
 ldx BE_WORK+17
 sta BE_WORK+18
 lda BE_PIXEL
@mask:
 cpx #0
 beq @write
 asl BE_WORK+18
 asl
 dex
 bne @mask
@write:
 sta BE_WORK+19
 jsr be_read_byte
 sta BE_TEMP
 lda BE_WORK+18
 eor #$ff
 and BE_TEMP
 ora BE_WORK+19
 jsr be_write_byte
 jmp be_render
@left:
 lda BE_X
 beq @cursor
 dec BE_X
 jmp @cursor
@right:
 lda #23
 ldx BE_RECORD+5
 bpl :+
 lda #11
:
 cmp BE_X
 beq @cursor
 inc BE_X
 jmp @cursor
@up:
 lda BE_Y
 beq @cursor
 dec BE_Y
 jmp @cursor
@down:
 lda BE_Y
 cmp #20
 beq @cursor
 inc BE_Y
@cursor:
 jsr be_sprite_cursor
 jmp be_wait
@commands:
 jsr be_upper
 cmp #'S'
 JEQ be_save
 cmp #'L'
 JEQ be_load
 cmp #'C'
 JEQ be_choose_color
 cmp #'I'
 JEQ be_sprite_init
 cmp #'B'
 JEQ be_byte64
 cmp #'T'
 JNE be_wait
 lda BE_RECORD+5
 eor #$80
 sta BE_RECORD+5
 bmi @narrow
 asl BE_X
 jmp @type
@narrow:
 lsr BE_X
@type:
 STORAGE_CALL be_set_blob
 jmp be_render
be_encode_color:
 ; Keyboard 1=background,2=sprite,3=common1,4=common2.
 lda BE_PIXEL
 ldx BE_RECORD+5
 bpl @done
 cmp #1
 bne :+
 lda #2
 rts
:
 cmp #2
 bne @done
 lda #1
@done:
 rts
be_sprite_init:
 lda #<be_init_prompt
 ldx #>be_init_prompt
 jsr be_prompt_label
 jsr be_modal_key
 cmp #'1'
 JCC be_render
 cmp #'5'
 JCS be_render
 sec
 sbc #'1'
 sta BE_PIXEL
 lda BE_RECORD+5
 bmi @multi
 lda BE_PIXEL
 cmp #2
 JCS be_render
 beq @multi
 cmp #0
 beq @fill
 lda #$ff
 bne @fill
@multi:
 jsr be_encode_color
 tax
 lda be_repeat_pixels,x
@fill:
 sta BE_PIXEL
 lda #63
 sta BE_SIZE
 lda #0
 sta BE_SIZE+1
 jsr be_fill
 jmp be_render
be_byte64:
 lda #<be_byte_prompt
 ldx #>be_byte_prompt
 jsr be_prompt_number
 JCS be_render
 lda BE_NUMBER+1
 JNE be_operation_error
 clc
 lda BE_RANGE
 adc #63
 sta BE_ADDR
 lda BE_RANGE+1
 adc #0
 sta BE_ADDR+1
 lda BE_NUMBER
 jsr be_write_byte
 jmp be_render
be_choose_color:
 lda #<be_color_prompt
 ldx #>be_color_prompt
 jsr be_prompt_label
 jsr be_modal_key
 cmp #'1'
 JCC be_render
 cmp #'5'
 JCS be_render
 sec
 sbc #'1'
 sta BE_PROMPT_KIND
 lda BE_RECORD+5
 bmi @get
 lda BE_PROMPT_KIND
 cmp #2
 JCS be_render
@get:
 jsr be_color_get
 sta BE_PIXEL
 jsr be_palette
be_color_wait:
 jsr $ffe4
 cmp #0
 beq be_color_wait
 cmp #95
 JEQ be_render
 cmp #$88
 beq @exit
 cmp #13
 beq @commit
 cmp #$9d
 beq @left
 cmp #$1d
 beq @right
 jsr be_upper
 jsr be_hex_value
 bcs be_color_wait
 sta BE_PIXEL
 jmp @show
@left:
 dec BE_PIXEL
 jmp @show
@right:
 inc BE_PIXEL
@show:
 lda BE_PIXEL
 and #15
 sta BE_PIXEL
 jsr be_palette
 jmp be_color_wait
@commit:
 lda BE_PROMPT_KIND
 lsr
 tax
 lda BE_PROMPT_KIND
 and #1
 beq @low
 lda BE_PIXEL
 asl
 asl
 asl
 asl
 sta BE_TEMP
 lda BE_RECORD+6,x
 and #15
 ora BE_TEMP
 jmp @store
@low:
 lda BE_RECORD+6,x
 and #$f0
 ora BE_PIXEL
@store:
 sta BE_RECORD+6,x
 STORAGE_CALL be_set_blob
 jmp be_render
@exit:
 lda #$80
 sta BE_FLAGS
 jmp be_exit
be_color_get:
 lda BE_PROMPT_KIND
 lsr
 tax
 lda BE_PROMPT_KIND
 and #1
 bne @high
 lda BE_RECORD+6,x
 and #15
 rts
@high:
 lda BE_RECORD+6,x
 lsr
 lsr
 lsr
 lsr
 rts
be_palette:
 lda #23
 sta BE_ROW
 lda #0
 sta BE_COL
 BE_TEXT be_set_color
 lda #10
 sta BE_COL
 ldx #0
@digit:
 lda #0
 sta BE_REVERSE
 cpx BE_PIXEL
 bne :+
 lda #$80
 sta BE_REVERSE
:
 txa
 jsr be_hex_digit
 inx
 cpx #16
 bne @digit
 lda #24
 sta BE_ROW
 lda #10
 sta BE_COL
 ldx #0
@swatch:
 stx BE_COLOR
 jsr be_solid
 inx
 cpx #16
 bne @swatch
 lda #14
 sta BE_COLOR
 lda #0
 sta BE_REVERSE
 rts
be_1x: .byte "1X",0
be_2x: .byte "2X",0
be_sprite_name: .byte "SPR ",0
be_type_hires: .byte "HIRES",0
be_type_multi: .byte "MULTICOLOR",0
be_bg_key: .byte "1 BG COLOR",0
be_sp_key: .byte "2 SP COLOR",0
be_c1_key: .byte "3 C1 COLOR",0
be_c2_key: .byte "4 C2 COLOR",0
be_byte64_key: .byte "B BYTE64:$",0
be_colors_key: .byte "C SET COLORS",0
be_type_key: .byte "T TYPE",0
be_init_key: .byte "I INITIALIZE",0
be_save_key: .byte "S SAVE BYTES",0
be_load_key: .byte "L LOAD BYTES",0
be_back_key: .byte 95," BACK",0
be_init_prompt: .byte "INITIAL COLOR: 1 BG 2 SP 3 C1 4 C2",0
be_byte_prompt: .byte "UNUSED BYTE 64 ($HEX OR DECIMAL)",0
be_color_prompt: .byte "COLOR DEFINITION 1/2/3/4",0
be_set_color: .byte "SET COLOR ",0
be_repeat_pixels: .byte $00,$55,$aa,$ff
.include "binary_cursors.inc"
