.segment "SCREEN_EDITOR"
; Bank 3 owns screen rendering and GETIN editing. All cross-bank calls use the
; common-RAM gate. No persistent editor data is stored in compiler/GC scratch.
editor_check_command:
 ldx INPUT_POS
 ldy #0
@basic:
 lda INPUT_BUFFER,x
 and #$df
 cmp editor_basic_word,y
 bne @quit_start
 inx
 iny
 cpy #5
 bne @basic
 lda #1
 bne @tail
@quit_start:
 ldx INPUT_POS
 ldy #0
@quit:
 lda INPUT_BUFFER,x
 and #$df
 cmp editor_quit_word,y
 bne @sprite_start
 inx
 iny
 cpy #4
 bne @quit
 lda #2
 bne @tail
@sprite_start:
 ldx INPUT_POS
 ldy #0
@sprite:
 lda INPUT_BUFFER,x
 and #$df
 cmp editor_sprite_word,y
 bne @no
 inx
 iny
 cpy #6
 bne @sprite
 lda #3
@tail:
 pha
@space:
 cpx INPUT_LEN
 beq @yes
 lda INPUT_BUFFER,x
 cmp #' '
 beq @take
 cmp #9
 bne @bad
@take:
 inx
 bne @space
@bad:
 pla
@no:
 lda #0
 rts
@yes:
 pla
 rts
editor_basic_word: .byte "BASIC"
editor_quit_word: .byte "QUIT"
editor_sprite_word: .byte "SPRDEF"

editor_open:
 lda ED_ACTIVE
 bne @installed
 lda $0326
 sta ED_OLD_OUT
 lda $0327
 sta ED_OLD_OUT+1
 lda $0324
 sta ED_OLD_IN
 lda $0325
 sta ED_OLD_IN+1
 sei
 lda #<editor_output_gate
 sta $0326
 lda #>editor_output_gate
 sta $0327
 lda #<editor_input_gate
 sta $0324
 lda #>editor_input_gate
 sta $0325
 cli
 lda #1
 sta ED_ACTIVE
@installed:
 lda #1
 sta $cc ; disable the stock IRQ cursor; the split editor draws its own
 lda #0
 sta $cf
 sta ED_FOCUS
 sta ED_MODE
 sta ED_LITERAL
 sta ED_GOTO
 sta ED_HELP
 sta ED_SUBMITTED
 sta ED_CURSOR_ON
 sta ED_INPUT_READY
 lda ED_VIEW_VALID
 bne @screen_ready
 lda #$ff
 sta ED_SELECTED_ROW
 jsr editor_listing_colors
@screen_ready:
 jsr editor_clear_pane
 jsr editor_listing
 jmp editor_status

editor_close:
 lda ED_ACTIVE
 beq @done
 jsr editor_hide_cursor
 jsr editor_clear_listing
 jsr editor_clear_pane
 ldx #39
@clear_status:
 lda #' '
 sta $0720,x
 lda #14
 sta $db20,x
 dex
 bpl @clear_status
 sei
 lda ED_OLD_OUT
 sta $0326
 lda ED_OLD_OUT+1
 sta $0327
 lda ED_OLD_IN
 sta $0324
 lda ED_OLD_IN+1
 sta $0325
 lda #0
 sta ED_ACTIVE
 sta ED_HELP
 sta ED_SUBMITTED
 sta ED_INPUT_READY
 sta ED_VIEW_VALID
 sta $cf
 lda #1
 sta $cc ; stock CHRIN enables blinking when it begins keyboard input
 cli
 lda #147
 jsr $ffd2
@done:
 rts

; Main command paths call this after numbered entry and after direct execution.
; A is the error code. The draft remains intact until success is known.
editor_finish:
 sta ED_TEMP
 lda #0
 sta ED_INPUT_READY
 jsr editor_hide_cursor
 jsr editor_select_submitted
 jsr editor_listing
 lda ED_TEMP
 beq @success
 lda ED_DRAFT_START
 sta ED_START
 lda #0
 sta ED_PAINT_LEN
 jsr editor_draw_text
 lda #0
 sta ED_CURSOR
 lda #1
 sta ED_FOCUS
 jmp @done
@success:
 lda ED_SUBMITTED
 cmp #1
 beq @clear
 cmp #2
 bne @done
 lda #0
 sta ED_LEN
 sta ED_PAINT_LEN
 sta ED_CURSOR
 lda ED_OUT
 sta ED_START
 jmp @done
@clear:
 jsr editor_clear_pane
@done:
 lda #0
 sta ED_SUBMITTED
 jsr editor_status
 lda ED_TEMP
 beq @return
 lda #4
 sta ED_ROUTE ; diagnostics replace the status bar, preserving all draft rows
 lda #0
 sta ED_COL
@return:
 rts

editor_read:
 lda #0
 sta ED_ROUTE
 jsr editor_show_cursor
editor_wait:
 ; GETIN leaves IRQ keyboard scanning active. Cursor motion never calls CHRIN
 ; or the stock scrolling editor, so it cannot leave either frame.
 lda PENDING
 JNE @quit
 lda $a2
 eor ED_BLINK
 and #$10
 beq @key
 lda $a2
 sta ED_BLINK
 lda ED_CURSOR_ON
 beq @show
 jsr editor_hide_cursor
 jmp @key
@show:
 jsr editor_show_cursor
@key:
 jsr $ffe4
 cmp #0
 beq editor_wait
 sta ED_CHAR
 jsr editor_hide_cursor
 lda ED_GOTO
 beq @dispatch
 jsr editor_goto_key
 jmp editor_read
@dispatch:
 lda ED_CHAR
 cmp #$88 ; F7
 JEQ @quit
 lda ED_HELP
 beq @normal
 jsr editor_help_off
 jmp editor_read
@normal:
 lda ED_CHAR
 cmp #$87
 bne @go
 lda #1
 BINARY_CALL be_open
 jmp editor_read
@go:
 cmp #$86
 bne @help
 jsr editor_begin_goto
 jmp editor_read
@help:
 cmp #$85 ; F1
 bne @focus
 jsr editor_help_on
 jmp editor_wait
@focus:
 cmp #95 ; ← focus key (PETSCII 95)
 bne @pane
 lda ED_FOCUS
 eor #1
 sta ED_FOCUS
 bne @focused
 jsr editor_clear_pane
@focused:
 jsr editor_line_cursor
 jsr editor_status
 jmp editor_read
@pane:
 lda ED_FOCUS
 bne @edit
 lda ED_CHAR
 cmp #13
 beq @copy
 cmp #$91
 JEQ @up
 cmp #$9d
 JEQ @up
 cmp #$11
 beq @down
 cmp #$1d
 beq @down
 jmp editor_read
@up:
 jsr editor_select_previous
 jmp editor_read
@down:
 jsr editor_select_next
 jmp editor_read
@copy:
 jsr editor_copy_line
 jmp editor_read
@edit:
 lda ED_CHAR
 cmp #13
 JEQ editor_submit
 cmp #5 ; CTRL+2 toggles literal independently of insertion policy
 bne @insert
 lda ED_LITERAL
 eor #1
 sta ED_LITERAL
 jmp @mode
@insert:
 cmp #$94
 bne @motion
 lda ED_MODE
 eor #1
 sta ED_MODE
@mode:
 jsr editor_status
 jmp editor_read
@motion:
 cmp #$14
 JEQ editor_delete
 ldx ED_LITERAL
 bne @type
 cmp #$9d
 JEQ editor_left
 cmp #$1d
 JEQ editor_right
 cmp #$91
 JEQ editor_up
 cmp #$11
 JEQ editor_down
 cmp #$13 ; HOME stays within the edit frame
 bne @printable
 lda #0
 sta ED_CURSOR
 jmp editor_read
@printable:
 lda ED_LITERAL
 bne @type
 lda ED_CHAR
 cmp #32
 bcc @ignore
 cmp #$80
 bcc @type
 cmp #$a0
 bcs @type
@ignore:
 jmp editor_read
@type:
 jsr editor_type
 jmp editor_read
@quit:
 lda #'Q'
 sta INPUT_BUFFER
 lda #'U'
 sta INPUT_BUFFER+1
 lda #'I'
 sta INPUT_BUFFER+2
 lda #'T'
 sta INPUT_BUFFER+3
 lda #4
 sta INPUT_LEN
 rts

editor_submit:
 lda ED_START
 sta ED_DRAFT_START
 lda #$ff
 sta ED_AFFECTED+1
 lda ED_LEN
 sta INPUT_LEN
 ldx #0
@copy:
 cpx ED_LEN
 beq @kind
 lda ED_TEXT,x
 sta INPUT_BUFFER,x
 inx
 bne @copy
@kind:
 lda #0
 sta INPUT_BUFFER,x
 ldx #0
@spaces:
 cpx ED_LEN
 beq @empty
 lda ED_TEXT,x
 cmp #' '
 bne @classify
 inx
 bne @spaces
@classify:
 lda #2
 sta ED_SUBMITTED
 lda ED_TEXT,x
 cmp #'0'
 bcc @direct
 cmp #'9'+1
 bcs @direct
 lda #1
 sta ED_SUBMITTED
 rts
@direct:
 ; Start command output beneath the last physical row of the submitted draft.
 clc
 lda ED_START
 adc ED_LEN
 sec
 sbc #1
 sta ED_OUT
 cmp #160
 bcc :+
 lda #159
 sta ED_OUT
:
 lda #13
 jsr editor_output
 rts
@empty:
 jsr editor_clear_pane
 rts

editor_left:
 jsr editor_absolute
 beq @done
 sec
 sbc #1
 jsr editor_seek
@done:
 jmp editor_read
editor_right:
 jsr editor_absolute
 cmp #159
 bcs @done
 clc
 adc #1
 jsr editor_seek
@done:
 jmp editor_read
editor_up:
 jsr editor_absolute
 cmp #40
 bcc @done
 sec
 sbc #40
 jsr editor_seek
@done:
 jmp editor_read
editor_down:
 jsr editor_absolute
 cmp #120
 bcs @done
 clc
 adc #40
 jsr editor_seek
@done:
 jmp editor_read

editor_absolute:
 lda ED_CURSOR
 clc
 adc ED_START
 rts
editor_row_index:
 ldx #0
@row:
 cmp #40
 bcc @done
 sec
 sbc #40
 inx
 bne @row
@done:
 rts

; Select the visible logical screen line containing absolute pane cell A.
; Continuation rows belong to their first row; hard newlines remain separate.
editor_seek:
 sta ED_TARGET
 cmp ED_START
 bcc @history
 sec
 sbc ED_START
 cmp ED_LEN
 bcc @current
 jsr editor_row_index
 stx ED_END
 lda ED_LEN
 beq :+
 sec
 sbc #1
:
 jsr editor_row_index
 cpx ED_END
 bcc @history
@current:
 lda ED_TARGET
 sec
 sbc ED_START
 sta ED_CURSOR
 rts
@history:
 lda ED_TARGET
 jsr editor_row_index
@first:
 lda ED_LINKS,x
 beq @found
 dex
 bpl @first
@found:
 lda editor_pane_rows,x
 sta ED_FIRST
 inx
@last:
 cpx #4
 beq @end
 lda ED_LINKS,x
 beq @end
 inx
 bne @last
@end:
 lda editor_pane_rows,x
 sta ED_END
 ldx ED_FIRST
 ldy #0
@copy:
 lda $0748,x
 ; Invert the quoted-style control glyphs as well as normal screen codes.
 cmp #$80
 bcc @normal
 cmp #$a0
 bcc @control
 cmp #$c0
 bcc @reverse
 cmp #$e0
 bcc @high_control
@normal:
 cmp #$20
 bcc @letter
 cmp #$40
 bcc @store
 cmp #$60
 bcc @graphic
 and #$7f
 ora #$80
 bne @store
@letter:
 ora #$40
 bne @store
@graphic:
 cmp #$5e
 bne :+
 lda #$ff
 bne @store
:
 ora #$80
 bne @store
@control:
 and #$1f
 jmp @store
@reverse:
 and #$7f
 bne @store
@high_control:
 and #$1f
 ora #$80
@store:
 sta ED_TEXT,y
 iny
 inx
 cpx ED_END
 bcc @copy
@trim:
 cpy #0
 beq @empty
 dey
 lda ED_TEXT,y
 cmp #' '
 beq @trim
 iny
 bne @length
@empty:
 ldy #0
@length:
 sty ED_LEN
 sty ED_PAINT_LEN
 lda ED_FIRST
 sta ED_START
 jmp @current
editor_pane_rows: .byte 0,40,80,120,160

editor_delete:
 lda ED_CURSOR
 beq @done
 dec ED_CURSOR
 ldx ED_CURSOR
 cpx ED_LEN
 bcs @draw
@shift:
 lda ED_TEXT+1,x
 sta ED_TEXT,x
 inx
 cpx ED_LEN
 bcc @shift
 dec ED_LEN
@draw:
 jsr editor_draw_text
@done:
 jmp editor_read

editor_type:
 ; Fill cursor-created gaps with spaces, then insert or overwrite PETSCII.
 lda ED_CURSOR
 cmp ED_LEN
 bcc @inside
 ldx ED_LEN
@gap:
 cpx ED_CURSOR
 beq @extend
 lda #' '
 sta ED_TEXT,x
 inx
 bne @gap
@extend:
 inx
 stx ED_LEN
 jmp @write
@inside:
 lda ED_MODE
 cmp #1
 beq @write
 lda ED_LEN
 clc
 adc ED_START
 cmp #160
 bcc @insert
 lda ED_START
 cmp #40
 bcc @full
 jsr editor_scroll_pane
 sec
 lda ED_START
 sbc #40
 sta ED_START
@insert:
 ldx ED_LEN
@push:
 cpx ED_CURSOR
 beq @inserted
 lda ED_TEXT-1,x
 sta ED_TEXT,x
 dex
 bne @push
@inserted:
 inc ED_LEN
@write:
 ldx ED_CURSOR
 lda ED_CHAR
 sta ED_TEXT,x
 lda ED_CURSOR
 clc
 adc ED_START
 cmp #159
 bcc @advance
 lda ED_START
 cmp #40
 bcc @draw
 jsr editor_scroll_pane
 sec
 lda ED_START
 sbc #40
 sta ED_START
@advance:
 inc ED_CURSOR
@draw:
 jsr editor_draw_text
@full:
 rts

editor_clear_pane:
 lda #0
 sta ED_LEN
 sta ED_CURSOR
 sta ED_START
 sta ED_OUT
 sta ED_PAINT_LEN
editor_erase_pane:
 lda #0
 ldx #3
@links:
 sta ED_LINKS,x
 dex
 bpl @links
 lda #<$0748
 sta ED_PTR
 lda #>$0748
 sta ED_PTR+1
 lda #<$db48
 sta ED_CPTR
 lda #>$db48
 sta ED_CPTR+1
 ldy #0
@clear:
 lda #' '
 sta (ED_PTR),y
 lda #14
 sta (ED_CPTR),y
 iny
 cpy #160
 bne @clear
 rts

editor_draw_text:
 ; Clear only this draft's old extent, retaining other visible screen lines.
 ldy ED_PAINT_LEN
 lda ED_LEN
 cmp ED_PAINT_LEN
 bcc :+
 tay
:
 sty ED_END
 lda ED_START
 jsr editor_row_index
 lda #0
 sta ED_LINKS,x
 lda ED_END
 beq @extent
 sec
 sbc #1
 clc
 adc ED_START
 jsr editor_row_index
 stx ED_FIRST
 lda ED_START
 jsr editor_row_index
 lda #0
@unlink:
 sta ED_LINKS,x
 cpx ED_FIRST
 beq @extent
 inx
 bne @unlink
@extent:
 ldy ED_END
 ldx ED_START
@clear:
 cpy #0
 beq @paint
 cpx #160
 bcs @paint
 lda #' '
 sta $0748,x
 lda #14
 sta $db48,x
 inx
 dey
 jmp @clear
@paint:
 lda ED_LEN
 sta ED_PAINT_LEN
 lda ED_START
 jsr editor_row_index
 lda #0
 sta ED_LINKS,x
 ldx #0
@char:
 cpx ED_LEN
 beq @done
 txa
 pha
 clc
 adc ED_START
 tay
 lda ED_TEXT,x
 jsr editor_screen_code
 sta $0748,y
 lda #14
 sta $db48,y
 tya
 cmp ED_START
 beq :+
 jsr editor_row_index
 cpx #0
 beq :+
 cmp #0
 bne :+
 lda #1
 sta ED_LINKS,x
:
 pla
 tax
 inx
 bne @char
@done:
 rts

editor_cursor_address:
 clc
 lda ED_CURSOR
 adc ED_START
 clc
 adc #<$0748
 sta ED_PTR
 lda #>$0748
 adc #0
 sta ED_PTR+1
 lda ED_PTR
 sta ED_CPTR
 lda ED_PTR+1
 clc
 adc #$d4
 sta ED_CPTR+1
 rts
editor_show_cursor:
 lda ED_FOCUS
 beq @done
 lda ED_HELP
 bne @done
 jsr editor_cursor_address
 ldy #0
 lda (ED_PTR),y
 sta ED_UNDER
 lda (ED_CPTR),y
 sta ED_UNDER_COLOR
 lda ED_UNDER
 eor #$80
 ldx ED_MODE
 cpx #1
 bne :+
 lda ED_UNDER
 ora #$80
:
 ldx ED_LITERAL
 beq @normal
 lda #$8c ; reverse L in cyan
@normal:
 sta (ED_PTR),y
 lda #14
 ldx ED_LITERAL
 bne @literal_color
 ldx ED_MODE
 beq @color
 lda #0
 beq @color
@literal_color:
 lda #3
@color:
 sta (ED_CPTR),y
 lda #1
 sta ED_CURSOR_ON
@done:
 rts
editor_hide_cursor:
 lda ED_CURSOR_ON
 beq @done
 jsr editor_cursor_address
 ldy #0
 lda ED_UNDER
 sta (ED_PTR),y
 lda ED_UNDER_COLOR
 sta (ED_CPTR),y
 lda #0
 sta ED_CURSOR_ON
@done:
 rts

; Convert PETSCII without executing controls. Control glyphs use the same
; reverse screen-code representation as the stock quoted editor.
editor_screen_code:
 cmp #32
 bcc @control
 cmp #$80
 bcc @low
 cmp #$a0
 bcc @high_control
 cmp #$c0
 bcc @upper
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
@upper:
 and #$7f
 rts
@control:
 ora #$80
 rts
@high_control:
 and #$1f
 ora #$c0
 rts
@pi:
 lda #$5e
 rts

; The CHROUT vector enters here through the common-RAM output gate. All state
; and indirect pointers are editor-owned; LIST's language pointers survive.
editor_output:
 pha
 lda ED_PTR
 pha
 lda ED_PTR+1
 pha
 lda ED_CPTR
 pha
 lda ED_CPTR+1
 pha
 tsx
 lda $0105,x
 jsr editor_output_impl
 pla
 sta ED_CPTR+1
 pla
 sta ED_CPTR
 pla
 sta ED_PTR+1
 pla
 sta ED_PTR
 pla
 rts
editor_output_impl:
 sta ED_CODE
 lda ED_ROUTE
 cmp #2
 JEQ editor_capture
 cmp #1
 JEQ editor_listing_char
 cmp #3
 JEQ editor_listing_char
 cmp #5
 JEQ editor_listing_char
 cmp #4
 JEQ editor_error_char
 lda ED_CODE
 cmp #13
 JEQ editor_output_cr
 cmp #147
 JEQ @clear
 cmp #$13
 JEQ @home
 cmp #$14
 JEQ @delete
 cmp #$1d
 JEQ @right
 cmp #$9d
 JEQ @left
 cmp #$11
 JEQ editor_output_cr
 cmp #$91
 JEQ @up
 cmp #$12
 JEQ @reverse
 cmp #$92
 JEQ @normal
 ; Standard PRINT controls affect only the pane, including colors and quotes.
 ldx #15
@color:
 cmp editor_color_codes,x
 JEQ @set_color
 dex
 bpl @color
 lda ED_CODE
 cmp #32
 bcc @done
 cmp #$80
 bcc @print
 cmp #$a0
 bcc @done
@print:
 jsr editor_screen_code
 ldx ED_HIGHLIGHT
 beq :+
 ora #$80
:
 ldx ED_OUT
 sta $0748,x
 lda ED_COLOR
 sta $db48,x
 inc ED_OUT
 lda ED_OUT
 cmp #160
 bcc @wrap
 jsr editor_scroll_pane
 lda #120
 sta ED_OUT
@wrap:
 lda ED_OUT
 jsr editor_row_index
 cmp #0
 bne @done
 lda #1
 sta ED_LINKS,x
@done:
 rts
@clear:
 jsr editor_erase_pane
 lda #0
 sta ED_OUT
 rts
@home:
 lda #0
 sta ED_OUT
 rts
@delete:
 lda ED_OUT
 beq @done
 dec ED_OUT
 ldx ED_OUT
 lda #' '
 sta $0748,x
 rts
@right:
 lda ED_OUT
 cmp #159
 beq @done
 inc ED_OUT
 rts
@left:
 lda ED_OUT
 beq @done
 dec ED_OUT
 rts
@up:
 lda ED_OUT
 cmp #40
 bcc @done
 sec
 sbc #40
 sta ED_OUT
 rts
@reverse:
 lda #1
 sta ED_HIGHLIGHT
 rts
@normal:
 lda #0
 sta ED_HIGHLIGHT
 rts
@set_color:
 stx ED_COLOR
 rts
editor_output_cr:
 lda ED_OUT
@row:
 cmp #40
 bcc @remainder
 sec
 sbc #40
 bcs @row
@remainder:
 sta ED_CODE
 sec
 lda ED_OUT
 sbc ED_CODE
 clc
 adc #40
 cmp #160
 bcc @set
 jsr editor_scroll_pane
 lda #120
@set:
 sta ED_OUT
 jsr editor_row_index
 lda #0
 sta ED_LINKS,x
 rts
editor_scroll_pane:
 lda ED_LINKS+2
 sta ED_LINKS+1
 lda ED_LINKS+3
 sta ED_LINKS+2
 lda #0
 sta ED_LINKS
 sta ED_LINKS+3
 lda ED_DRAFT_START
 sec
 sbc #40
 bcs :+
 lda #0
:
 sta ED_DRAFT_START
 ldx #0
@move:
 lda $0770,x
 sta $0748,x
 lda $db70,x
 sta $db48,x
 inx
 cpx #120
 bne @move
@clear:
 lda #' '
 sta $0748,x
 lda #14
 sta $db48,x
 inx
 cpx #160
 bne @clear
 rts
editor_color_codes: .byte $90,$05,$1c,$9f,$9c,$1e,$1f,$9e,$81,$95,$96,$97,$98,$99,$9a,$9b

editor_error_char:
 lda ED_CODE
 cmp #13
 beq @done
 ldy ED_COL
 cpy #40
 bcs @done
 jsr editor_screen_code
 ora #$80
 sta $0720,y
 inc ED_COL
@done:
 rts

editor_capture:
 lda ED_CODE
 cmp #13
 beq @done
 ldx ED_LEN
 cpx #160
 bcs @full
 sta ED_TEXT,x
 inc ED_LEN
 rts
@full:
 lda #1
 sta ED_COPY_FULL
@done:
 rts

editor_listing_char:
 lda ED_ROUTE
 cmp #3
 bne @literal
 lda ED_CODE
 cmp #13
 JEQ @newline
@literal:
 lda ED_ROUTE
 cmp #5
 beq @advance ; count physical rows without touching screen or row metadata
 lda ED_ROW
 cmp ED_SKIP
 bcc @advance
 cmp ED_LIMIT
 bcs @advance
 tax
 lda editor_rows_lo,x
 sta ED_PTR
 lda editor_rows_hi,x
 sta ED_PTR+1
 lda ED_ROUTE
 cmp #1
 bne @glyph
 ; Continuation indentation must replace any old line-number cells.
 lda ED_COL
 cmp ED_INDENT
 bne @glyph
 lda ED_ROWS_LO,x
 ora ED_ROWS_HI,x
 bne @glyph
 ldy #0
@indent:
 cpy ED_INDENT
 beq @glyph
 lda (ED_PTR),y
 cmp #' '
 beq :+
 lda #' '
 sta (ED_PTR),y
:
 iny
 bne @indent
@glyph:
 lda ED_CODE
 jsr editor_screen_code
 ; Keep the number cursor visible during differential source refreshes too.
 ldx ED_ROUTE
 cpx #1
 bne @compare
 ldx ED_INDENT
 bne @compare
 ldx ED_ANCHOR
 cpx ED_SELECTED_ANCHOR
 bne @compare
 ldx ED_ANCHOR+1
 cpx ED_SELECTED_ANCHOR+1
 bne @compare
 cmp #'0'
 bcc @compare
 cmp #'9'+1
 bcs @compare
 ora #$80
@compare:
 ldy ED_COL
 cmp (ED_PTR),y
 beq @advance
 sta (ED_PTR),y
@advance:
 inc ED_COL
 lda ED_ROUTE
 cmp #3
 beq @wrap ; help has hard newlines and uses the full screen width
 lda ED_INDENT
 bne @wrap
 lda ED_CODE
 cmp #' '
 bne @wrap
 lda ED_COL
 sta ED_INDENT
@wrap:
 lda ED_COL
 cmp #40
 bcc @done
 lda ED_INDENT
 sta ED_COL
 lda ED_ROW
 cmp #$ff
 beq @done
 inc ED_ROW
 lda ED_ROUTE
 cmp #1
 bne @done
 lda ED_ROW
 cmp ED_SKIP
 bcc @done
 cmp ED_LIMIT
 bcs @done
 tax
 lda #0
 sta ED_ROWS_LO,x
 sta ED_ROWS_HI,x
@done:
 rts
@newline:
 lda #0
 sta ED_COL
 lda ED_ROW
 cmp #$ff
 beq @done
 inc ED_ROW
 rts

editor_anchor_number:
 lda ED_ANCHOR
 sta ED_PTR
 lda ED_ANCHOR+1
 sta ED_PTR+1
 ldy #3
 lda (ED_PTR),y
 tax
 iny
 lda (ED_PTR),y
 rts ; A high, X low; anchors live in common RAM
editor_is_end:
 lda ED_ANCHOR
 cmp #<run_end
 bne @no
 lda ED_ANCHOR+1
 cmp #>run_end
@no:
 rts
editor_find_top:
 lda ED_TOP
 sta LINE_NO
 lda ED_TOP+1
 sta LINE_NO+1
 COMMAND_CALL editor_find
 sta ED_ANCHOR
 stx ED_ANCHOR+1
 jsr editor_is_end
 bne @done
 lda PROGRAM_HEAD
 sta ED_ANCHOR
 lda PROGRAM_HEAD+1
 sta ED_ANCHOR+1
@done:
 rts
editor_find_selected:
 lda ED_SELECTED
 sta LINE_NO
 lda ED_SELECTED+1
 sta LINE_NO+1
 COMMAND_CALL editor_find
 sta ED_ANCHOR
 stx ED_ANCHOR+1
 rts
editor_cached_selected:
 lda ED_SELECTED_ANCHOR
 sta ED_ANCHOR
 lda ED_SELECTED_ANCHOR+1
 sta ED_ANCHOR+1
 rts
editor_select_submitted:
 lda ED_SUBMITTED
 cmp #1
 bne @done
 lda ED_AFFECTED+1
 cmp #$ff
 beq @done
 lda ED_AFFECTED
 cmp ED_SELECTED
 bne @select
 lda ED_AFFECTED+1
 cmp ED_SELECTED+1
 beq @done
@select:
 jsr editor_cursor_off
 lda ED_AFFECTED
 sta ED_SELECTED
 lda ED_AFFECTED+1
 sta ED_SELECTED+1
 lda GENERATION
 cmp ED_VIEW_GEN
 bne @invalidate
 lda GENERATION+1
 cmp ED_VIEW_GEN+1
 bne @invalidate
 jsr editor_find_selected
 jsr editor_is_end
 beq @invalidate
 jsr editor_move_selection
 jsr editor_locate_selection
 cmp #$ff
 bne @done
@invalidate:
 lda #0
 sta ED_VIEW_VALID
@done:
 rts

editor_listing:
 ; Source commands that leave the program alone must not redraw the viewport.
 lda ED_VIEW_VALID
 beq @changed
 lda GENERATION
 cmp ED_VIEW_GEN
 bne @changed
 lda GENERATION+1
 cmp ED_VIEW_GEN+1
 bne @changed
 jmp editor_line_cursor
@changed:
 ; Resolve numeric bookmarks only when the source graph may have changed.
 jsr editor_find_selected
 jsr editor_is_end
 bne @selected
 ; Deleting the final line selects its predecessor, if one survives.
 COMMAND_CALL editor_previous
 sta ED_ANCHOR
 stx ED_ANCHOR+1
 ora ED_ANCHOR+1
 bne @selected
 lda PROGRAM_HEAD
 sta ED_ANCHOR
 lda PROGRAM_HEAD+1
 sta ED_ANCHOR+1
@selected:
 lda ED_ANCHOR
 sta ED_SELECTED_ANCHOR
 lda ED_ANCHOR+1
 sta ED_SELECTED_ANCHOR+1
 jsr editor_is_end
 beq @top
 jsr editor_anchor_number
 stx ED_SELECTED
 sta ED_SELECTED+1
@top:
 jsr editor_find_top
 jsr editor_is_end
 beq @paint
 jsr editor_anchor_number
 stx ED_TOP
 sta ED_TOP+1
@paint:
 jsr editor_paint_listing
 lda ED_SELECTED_ROW
 cmp #$ff
 bne @done
 jsr editor_find_selected
 jsr editor_is_end
 beq @done
 jsr editor_reveal_selection
@done:
 lda GENERATION
 sta ED_VIEW_GEN
 lda GENERATION+1
 sta ED_VIEW_GEN+1
 lda #1
 sta ED_VIEW_VALID
 jmp editor_line_cursor

editor_reveal_selection:
 ; Keep up to three preceding BASIC lines, but never hide the destination
 ; behind a context line taller than the frame. Reuse screen rows when possible.
 jsr editor_find_top
 lda ED_ANCHOR
 sta ED_OLD_TOP
 lda ED_ANCHOR+1
 sta ED_OLD_TOP+1
 jsr editor_cached_selected
 lda #0
 sta ED_CONTEXT_ROWS
 lda #3
 sta ED_STEPS
@previous:
 lda ED_ANCHOR
 sta ED_SAVE
 lda ED_ANCHOR+1
 sta ED_SAVE+1
 COMMAND_CALL editor_previous
 sta ED_ANCHOR
 stx ED_ANCHOR+1
 ora ED_ANCHOR+1
 beq @restore
 lda ED_ANCHOR
 sta LIST_ANCHOR
 lda ED_ANCHOR+1
 sta LIST_ANCHOR+1
 lda #0
 sta ED_ROW
 lda #5
 sta ED_ROUTE
 jsr editor_render_line
 clc
 lda ED_ROW
 adc ED_CONTEXT_ROWS
 bcs @restore
 cmp #20
 bcs @restore
 sta ED_CONTEXT_ROWS
 dec ED_STEPS
 bne @previous
 beq @scroll
@restore:
 lda ED_SAVE
 sta ED_ANCHOR
 lda ED_SAVE+1
 sta ED_ANCHOR+1
@scroll:
 lda #0
 sta ED_ROUTE
 jsr editor_anchor_number
 cmp ED_TOP+1
 bcc @down
 bne @up
 cpx ED_TOP
 bcc @down
@up:
 jmp editor_scroll_up
@down:
 jmp editor_scroll_down

; F3 is an incremental numeric search. Any non-digit ends the prompt without
; submitting a pane draft; its focus, cursor, literal setting and bytes survive.
editor_binary_restore:
 jsr editor_listing_colors
 jsr editor_paint_listing
 jsr editor_line_cursor
 jmp editor_status

editor_begin_goto:
 lda #1
 sta ED_GOTO
 lda #0
 sta ED_GOTO_LEN
 sta ED_GOTO_NO
 sta ED_GOTO_NO+1
 jmp editor_goto_prompt

editor_goto_key:
 lda ED_CHAR
 cmp #'0'
 JCC @cancel
 cmp #'9'+1
 JCS @cancel
 lda ED_GOTO_LEN
 cmp #5
 JCS @prompt
 sec
 lda ED_CHAR
 sbc #'0'
 sta ED_TARGET
 lda ED_GOTO_NO+1
 cmp #25
 JCS @prompt
 lda ED_GOTO_NO
 sta ED_SAVE
 lda ED_GOTO_NO+1
 sta ED_SAVE+1
 asl ED_SAVE
 rol ED_SAVE+1
 asl ED_SAVE
 rol ED_SAVE+1
 clc
 lda ED_SAVE
 adc ED_GOTO_NO
 sta ED_SAVE
 lda ED_SAVE+1
 adc ED_GOTO_NO+1
 sta ED_SAVE+1
 asl ED_SAVE
 rol ED_SAVE+1
 clc
 lda ED_SAVE
 adc ED_TARGET
 tax
 lda ED_SAVE+1
 adc #0
 cmp #$fa
 JCS @prompt
 stx ED_GOTO_NO
 sta ED_GOTO_NO+1
 inc ED_GOTO_LEN
 lda ED_GOTO_NO
 sta LINE_NO
 lda ED_GOTO_NO+1
 sta LINE_NO+1
 ; Resolve without disturbing either the source graph or the old highlight.
 COMMAND_CALL editor_find
 sta ED_ANCHOR
 stx ED_ANCHOR+1
 jsr editor_is_end
 bne @found
 COMMAND_CALL editor_previous
 sta ED_ANCHOR
 stx ED_ANCHOR+1
 ora ED_ANCHOR+1
 beq @prompt
@found:
 lda ED_ANCHOR
 cmp ED_SELECTED_ANCHOR
 bne @move
 lda ED_ANCHOR+1
 cmp ED_SELECTED_ANCHOR+1
 beq @prompt
@move:
 jsr editor_move_selection
 jsr editor_locate_selection
 cmp #$ff
 bne @highlight
 jsr editor_reveal_selection
@highlight:
 jsr editor_line_cursor
@prompt:
 jmp editor_goto_prompt
@cancel:
 lda #0
 sta ED_GOTO
 jmp editor_status
editor_goto_prompt:
 jsr editor_status
 ldx #39
@clear:
 lda #' '|$80
 sta $0720,x
 dex
 bpl @clear
 ldx #0
@label:
 lda editor_goto_label,x
 jsr editor_screen_code
 ora #$80
 sta $0720,x
 inx
 cpx #8
 bne @label
 lda ED_GOTO_LEN
 beq @done
 ; Decimal formatting uses compiler scratch, never the edit draft buffers.
 lda ED_GOTO_NO
 ldx ED_GOTO_NO+1
 COMMAND_CALL print_source_number_buffer
 ldx #0
@digits:
 lda NUM_BUFFER,x
 ora #$80
 sta $0728,x
 inx
 cpx COUNT
 bcc @digits
@done:
 rts
editor_goto_label: .byte "GO LINE "

editor_paint_listing:
 lda #0
 sta ED_ROUTE
 sta ED_SKIP
 sta ED_ROW
 ldx #19
@map:
 sta ED_ROWS_LO,x
 sta ED_ROWS_HI,x
 dex
 bpl @map
 lda #20
 sta ED_LIMIT
 jsr editor_find_top
 jsr editor_render_rows
 jmp editor_reindex

; Render into [ED_SKIP,ED_LIMIT), keeping all other screen cells intact. Rows
; copied by scrolling are retained even when their last logical line is clipped.
editor_render_rows:
@line:
 jsr editor_is_end
 beq @clear
 lda ED_ROW
 cmp ED_LIMIT
 bcs @done
 tax
 lda ED_ANCHOR
 sta ED_ROWS_LO,x
 sta LIST_ANCHOR
 lda ED_ANCHOR+1
 sta ED_ROWS_HI,x
 sta LIST_ANCHOR+1
 jsr editor_render_line
 COMMAND_CALL editor_next
 sta ED_ANCHOR
 stx ED_ANCHOR+1
 jmp @line
@clear:
 lda ED_ROW
 cmp ED_LIMIT
 bcs @done
 tax
 lda #0
 sta ED_ROWS_LO,x
 sta ED_ROWS_HI,x
 sta ED_COL
 jsr editor_blank_row
 inc ED_ROW
 jmp @clear
@done:
 lda #0
 sta ED_ROUTE
 rts

editor_render_line:
 lda ED_ROW
 sta ED_LINE_START
 lda #0
 sta ED_INDENT
 sta ED_COL
 lda ED_ROUTE
 cmp #5
 beq @format
 lda #1
 sta ED_ROUTE
@format:
 COMMAND_CALL print_source_line
 ; An exact right-edge ending already advanced to the next physical row.
 lda ED_ROW
 cmp ED_LINE_START
 beq @finish
 lda ED_COL
 cmp ED_INDENT
 bne @finish
 lda #0
 sta ED_COL
 rts
@finish:
 lda ED_ROUTE
 cmp #5
 beq @advance
 jsr editor_blank_row
@advance:
 lda ED_ROW
 cmp #$ff
 beq @done
 inc ED_ROW
@done:
 rts

; Pad only cells whose displayed characters actually differ. Color RAM is
; initialized once on entry and is never rewritten or moved by listing updates.
editor_blank_row:
 lda ED_ROW
 cmp ED_SKIP
 bcc @done
 cmp ED_LIMIT
 bcs @done
 tax
 lda editor_rows_lo,x
 sta ED_PTR
 lda editor_rows_hi,x
 sta ED_PTR+1
 ldy ED_COL
@blank:
 cpy #40
 bcs @done
 lda (ED_PTR),y
 cmp #' '
 beq :+
 lda #' '
 sta (ED_PTR),y
:
 iny
 bne @blank
@done:
 rts

editor_reindex:
 lda #$ff
 sta ED_SELECTED_ROW
 lda #0
 sta ED_LAST
 sta ED_LAST+1
 ldx #0
@row:
 stx ED_SCAN_ROW
 lda ED_ROWS_LO,x
 sta ED_PTR
 lda ED_ROWS_HI,x
 sta ED_PTR+1
 ora ED_PTR
 beq @next
 lda ED_PTR
 cmp ED_SELECTED_ANCHOR
 bne @number
 lda ED_PTR+1
 cmp ED_SELECTED_ANCHOR+1
 bne @number
 stx ED_SELECTED_ROW
@number:
 ldy #3
 lda (ED_PTR),y
 sta ED_LAST
 iny
 lda (ED_PTR),y
 sta ED_LAST+1
@next:
 ldx ED_SCAN_ROW
 inx
 cpx #20
 bne @row
 rts

editor_cursor_off:
 lda #0
 beq editor_cursor_mask
editor_line_cursor:
 lda #$80
editor_cursor_mask:
 sta ED_HIGHLIGHT_MASK
 ldx ED_SELECTED_ROW
 cpx #20
 bcs @done
 lda editor_rows_lo,x
 sta ED_PTR
 lda editor_rows_hi,x
 sta ED_PTR+1
 ldy #0
@digit:
 lda (ED_PTR),y
 and #$7f
 cmp #'0'
 bcc @done
 cmp #'9'+1
 bcs @done
 ora ED_HIGHLIGHT_MASK
 cmp (ED_PTR),y
 beq :+
 sta (ED_PTR),y
:
 iny
 cpy #5
 bcc @digit
@done:
 rts

editor_listing_colors:
 ldx #0
 lda #14
@pages:
 sta $d800,x
 sta $d900,x
 sta $da00,x
 inx
 bne @pages
 ldx #31
@tail:
 sta $db00,x
 dex
 bpl @tail
 rts

editor_clear_listing:
 lda #0
 sta ED_ROW
 sta ED_COL
 sta ED_SKIP
 lda #20
 sta ED_LIMIT
@row:
 jsr editor_blank_row
 inc ED_ROW
 lda ED_ROW
 cmp #20
 bcc @row
 rts

editor_select_next:
 jsr editor_cached_selected
 jsr editor_is_end
 beq @done
 ldx ED_SELECTED_ROW
@visible:
 inx
 cpx #20
 bcs @linked
 lda ED_ROWS_LO,x
 ora ED_ROWS_HI,x
 beq @visible
 lda ED_ROWS_LO,x
 sta ED_ANCHOR
 lda ED_ROWS_HI,x
 sta ED_ANCHOR+1
 jmp @selected
@linked:
 COMMAND_CALL editor_next
 sta ED_ANCHOR
 stx ED_ANCHOR+1
 jsr editor_is_end
 beq @done
@selected:
 jsr editor_move_selection
 jsr editor_locate_selection
 cmp #$ff
 bne @cursor
 ; Advance at most five BASIC lines, without passing the new selection.
 jsr editor_find_top
 lda #5
 sta ED_STEPS
@five:
 lda ED_ANCHOR
 cmp ED_SELECTED_ANCHOR
 bne @next
 lda ED_ANCHOR+1
 cmp ED_SELECTED_ANCHOR+1
 beq @scrolled
@next:
 COMMAND_CALL editor_next
 sta ED_ANCHOR
 stx ED_ANCHOR+1
 dec ED_STEPS
 bne @five
@scrolled:
 jsr editor_scroll_up
@cursor:
 jsr editor_line_cursor
@done:
 rts

editor_select_previous:
 jsr editor_cached_selected
 jsr editor_is_end
 beq @done
 ldx ED_SELECTED_ROW
@visible:
 dex
 bmi @linked
 lda ED_ROWS_LO,x
 ora ED_ROWS_HI,x
 beq @visible
 lda ED_ROWS_LO,x
 sta ED_ANCHOR
 lda ED_ROWS_HI,x
 sta ED_ANCHOR+1
 jmp @selected
@linked:
 COMMAND_CALL editor_previous
 sta ED_ANCHOR
 stx ED_ANCHOR+1
 ora ED_ANCHOR+1
 beq @done
@selected:
 jsr editor_move_selection
 jsr editor_locate_selection
 cmp #$ff
 bne @cursor
 lda ED_ROWS_LO
 sta ED_OLD_TOP
 lda ED_ROWS_HI
 sta ED_OLD_TOP+1
 jsr editor_find_top
 lda #5
 sta ED_STEPS
@five:
 COMMAND_CALL editor_previous
 sta ED_NEXT
 stx ED_NEXT+1
 ora ED_NEXT+1
 beq @scrolled
 lda ED_NEXT
 sta ED_ANCHOR
 lda ED_NEXT+1
 sta ED_ANCHOR+1
 dec ED_STEPS
 bne @five
@scrolled:
 jsr editor_scroll_down
@cursor:
 jsr editor_line_cursor
@done:
 rts

editor_move_selection:
 ; Remove only the old number's reverse bits before changing numeric bookmarks.
 lda ED_ANCHOR
 pha
 lda ED_ANCHOR+1
 pha
 jsr editor_cursor_off
 pla
 sta ED_ANCHOR+1
 pla
 sta ED_ANCHOR
 lda ED_ANCHOR
 sta ED_SELECTED_ANCHOR
 lda ED_ANCHOR+1
 sta ED_SELECTED_ANCHOR+1
 jsr editor_anchor_number
 stx ED_SELECTED
 sta ED_SELECTED+1
 rts

editor_locate_selection:
 ldx #0
@row:
 lda ED_ROWS_LO,x
 cmp ED_SELECTED_ANCHOR
 bne @next
 lda ED_ROWS_HI,x
 cmp ED_SELECTED_ANCHOR+1
 beq @found
@next:
 inx
 cpx #20
 bne @row
 ldx #$ff
@found:
 stx ED_SELECTED_ROW
 txa
 rts

editor_scroll_up:
 jsr editor_anchor_number
 stx ED_TOP
 sta ED_TOP+1
 ldx #0
@offset:
 lda ED_ROWS_LO,x
 cmp ED_ANCHOR
 bne @next
 lda ED_ROWS_HI,x
 cmp ED_ANCHOR+1
 beq @overlap
@next:
 inx
 cpx #20
 bne @offset
 ; No retained rows when a preceding long line fills the whole frame.
 jmp editor_paint_listing
@overlap:
 stx ED_DELTA
 stx ED_MOVE_ROW
 lda #20
 sec
 sbc ED_DELTA
 sta ED_RETAIN
@move:
 ldx ED_MOVE_ROW
 lda editor_rows_lo,x
 sta ED_PTR
 lda editor_rows_hi,x
 sta ED_PTR+1
 txa
 sec
 sbc ED_DELTA
 tax
 lda editor_rows_lo,x
 sta ED_CPTR
 lda editor_rows_hi,x
 sta ED_CPTR+1
 ldy #0
@chars:
 lda (ED_PTR),y
 sta (ED_CPTR),y
 iny
 cpy #40
 bne @chars
 ldy ED_MOVE_ROW
 lda ED_ROWS_LO,y
 sta ED_ROWS_LO,x
 lda ED_ROWS_HI,y
 sta ED_ROWS_HI,x
 inc ED_MOVE_ROW
 lda ED_MOVE_ROW
 cmp #20
 bcc @move
 ldx ED_RETAIN
 lda #0
@map:
 sta ED_ROWS_LO,x
 sta ED_ROWS_HI,x
 inx
 cpx #20
 bcc @map
 ; Resume the last retained logical line, skipping its already displayed rows.
 ldx ED_RETAIN
@last:
 dex
 lda ED_ROWS_LO,x
 ora ED_ROWS_HI,x
 beq @last
 lda ED_ROWS_LO,x
 sta ED_ANCHOR
 lda ED_ROWS_HI,x
 sta ED_ANCHOR+1
 stx ED_ROW
 lda ED_RETAIN
 sta ED_SKIP
 lda #20
 sta ED_LIMIT
 lda #0
 sta ED_ROUTE
 jsr editor_render_rows
 jmp editor_reindex

editor_scroll_down:
 jsr editor_anchor_number
 stx ED_TOP
 sta ED_TOP+1
 ; Measure only the new prefix, so wrapped BASIC lines shift the correct rows.
 lda #0
 sta ED_ROW
@measure:
 lda ED_ANCHOR
 cmp ED_OLD_TOP
 bne @line
 lda ED_ANCHOR+1
 cmp ED_OLD_TOP+1
 beq @measured
@line:
 lda ED_ANCHOR
 sta LIST_ANCHOR
 lda ED_ANCHOR+1
 sta LIST_ANCHOR+1
 lda #5
 sta ED_ROUTE
 jsr editor_render_line
 lda ED_ROW
 cmp #20
 bcs @replace
 COMMAND_CALL editor_next
 sta ED_ANCHOR
 stx ED_ANCHOR+1
 jmp @measure
@replace:
 lda #0
 sta ED_ROUTE
 jmp editor_paint_listing
@measured:
 lda ED_ROW
 sta ED_DELTA
 lda #19
 sec
 sbc ED_DELTA
 sta ED_MOVE_ROW
@move:
 ldx ED_MOVE_ROW
 lda editor_rows_lo,x
 sta ED_PTR
 lda editor_rows_hi,x
 sta ED_PTR+1
 txa
 clc
 adc ED_DELTA
 tax
 lda editor_rows_lo,x
 sta ED_CPTR
 lda editor_rows_hi,x
 sta ED_CPTR+1
 ldy #39
@chars:
 lda (ED_PTR),y
 sta (ED_CPTR),y
 dey
 bpl @chars
 ldy ED_MOVE_ROW
 lda ED_ROWS_LO,y
 sta ED_ROWS_LO,x
 lda ED_ROWS_HI,y
 sta ED_ROWS_HI,x
 dec ED_MOVE_ROW
 bpl @move
 ldx #0
 lda #0
@map:
 sta ED_ROWS_LO,x
 sta ED_ROWS_HI,x
 inx
 cpx ED_DELTA
 bcc @map
 lda ED_DELTA
 sta ED_LIMIT
 lda #0
 sta ED_SKIP
 sta ED_ROW
 sta ED_ROUTE
 jsr editor_find_top
 jsr editor_render_rows
 lda #20
 sta ED_LIMIT
 jmp editor_reindex

editor_copy_line:
 jsr editor_cached_selected
 jsr editor_is_end
 beq @done
 jsr editor_clear_pane
 lda #0
 sta ED_COPY_FULL
 lda #2
 sta ED_ROUTE
 lda ED_ANCHOR
 sta LIST_ANCHOR
 lda ED_ANCHOR+1
 sta LIST_ANCHOR+1
 COMMAND_CALL print_source_line
 lda #0
 sta ED_ROUTE
 lda #1
 sta ED_FOCUS
 lda ED_COPY_FULL
 beq @copied
 ; Never turn an overlong stored line into a silently truncated replacement.
 jsr editor_clear_pane
 lda #<editor_long_text
 ldx #>editor_long_text
 jsr editor_pane_message
 lda ED_OUT
 sta ED_START
 jmp @refresh
@copied:
 lda ED_LEN
 cmp #160
 bcc :+
 lda #159
:
 sta ED_CURSOR
 jsr editor_draw_text
@refresh:
 jsr editor_line_cursor
 jsr editor_status
@done:
 rts
editor_long_text: .byte "?LINE EXCEEDS 160 CHARACTERS",13,0

editor_status:
 ldx #39
@clear:
 lda #' '|$80
 sta $0720,x
 lda #14
 sta $db20,x
 dex
 bpl @clear
 ldx ED_MODE
 lda editor_modes_lo,x
 sta ED_PTR
 lda editor_modes_hi,x
 sta ED_PTR+1
 ldy #0
@mode:
 lda (ED_PTR),y
 beq @keys
 jsr editor_screen_code
 ora #$80
 sta $0721,y
 iny
 bne @mode
@keys:
 lda ED_LITERAL
 beq @shortcuts
 ldx #0
@literal:
 lda editor_literal_text,x
 beq @shortcuts
 jsr editor_screen_code
 ora #$80
 sta $072c,x
 inx
 bne @literal
@shortcuts:
 ldx #0
@label:
 lda editor_key_label,x
 jsr editor_screen_code
 ora #$80
 sta $0739,x
 inx
 cpx #15
 bne @label
 rts
editor_insert_text: .byte "INSERT",0
editor_overwrite_text: .byte "OVERWRITE",0
editor_literal_text: .byte "LITERAL",0
editor_modes_lo: .byte <editor_insert_text,<editor_overwrite_text
editor_modes_hi: .byte >editor_insert_text,>editor_overwrite_text
editor_key_label: .byte "F1? F3# F5B F7X"

editor_pane_message:
 sta ED_PTR
 stx ED_PTR+1
 ldy #0
@char:
 lda (ED_PTR),y
 beq @done
 sta ED_CHAR
 tya
 pha
 lda ED_CHAR
 jsr editor_output
 pla
 tay
 iny
 bne @char
@done:
 rts
editor_help_on:
 ; Preserve the listing as characters, so returning from help never detokenizes
 ; source or disturbs a suspended INPUT. These buffers are inactive while GETIN
 ; waits: TOKENS, LEX_BUFFER, BRIDGE (before the first INPUT field byte), and the
 ; unused expression-stack tail. INPUT_BUFFER's saved command stays intact.
 ldx #0
@save:
 lda $0400,x
 sta TOKENS,x
 lda $0500,x
 sta LEX_BUFFER,x
 lda $0600,x
 sta BRIDGE,x
 inx
 bne @save
 ldx #31
@tail:
 lda $0700,x
 sta ED_HELP_TAIL,x
 dex
 bpl @tail
 lda #1
 sta ED_HELP
 jsr editor_clear_listing
 lda #3
 sta ED_ROUTE
 lda #0
 sta ED_ROW
 sta ED_COL
 sta ED_INDENT
 sta ED_HIGHLIGHT
 lda #<editor_help_text
 sta ED_PTR
 lda #>editor_help_text
 sta ED_PTR+1
 ldy #0
@char:
 lda (ED_PTR),y
 beq @done
 sta ED_CHAR
 tya
 pha
 lda ED_CHAR
 jsr editor_output
 pla
 tay
 iny
 bne @char
 inc ED_PTR+1
 jmp @char
@done:
 lda #0
 sta ED_ROUTE
 rts
editor_help_off:
 lda #0
 sta ED_HELP
 ldx #0
@restore:
 lda TOKENS,x
 cmp $0400,x
 beq :+
 sta $0400,x
:
 lda LEX_BUFFER,x
 cmp $0500,x
 beq :+
 sta $0500,x
:
 lda BRIDGE,x
 cmp $0600,x
 beq :+
 sta $0600,x
:
 inx
 bne @restore
 ldx #31
@tail:
 lda ED_HELP_TAIL,x
 cmp $0700,x
 beq :+
 sta $0700,x
:
 dex
 bpl @tail
 jmp editor_status

editor_help_text:
 .byte "ASSEMBLY BASIC SCREEN EDITOR",13,13
 .byte "CURSOR KEYS  SELECT / MOVE TEXT",13
 .byte "RETURN       COPY LINE / SUBMIT",13
 .byte 95,"            SWITCH LIST / EDIT",13
 .byte "SHIFT-DEL    INSERT / OVERWRITE",13
 .byte "CTRL+2       TOGGLE LITERAL",13
 .byte "DEL          DELETE PREVIOUS CHARACTER",13
 .byte "HOME         START OF EDIT LINE",13
 .byte "F1 HELP  F3 GO LINE  F5 BINARY  F7 QUIT",13
 .byte "F3: TYPE NUMBER; OTHER KEYS FINISH.",13
 .byte "RUN          EXIT AND RUN PROGRAM",13,13
 .byte "ENTER A NUMBERED LINE TO ADD OR CHANGE.",13
 .byte "A LINE NUMBER ALONE DELETES THAT LINE.",13
 .byte "DIRECT COMMANDS USE THE LOWER PANE.",13
 .byte 95," TO LIST DISCARDS THE DRAFT.",13
 .byte "LITERAL TYPES CONTROL CODES AS GLYPHS.",13
 .byte "BASIC REOPENS AT YOUR LAST POSITION.",13
 .byte "PRESS ANY KEY TO RETURN",0
editor_rows_lo:
 .repeat 20, I
 .byte <($0400+I*40)
 .endrepeat
editor_rows_hi:
 .repeat 20, I
 .byte >($0400+I*40)
 .endrepeat

; A direct INPUT collects a complete bounded screen line, then returns its
; PETSCII bytes to CHRIN one at a time. Comma-separated fields survive runtime
; allocation/GC because the completed input lives in INPUT_BUFFER. The pending
; command draft is backed up only while GETIN is waiting, with no lexer or GC.
editor_chrin:
 txa
 pha
 tya
 pha
 lda ED_INPUT_READY
 JNE editor_input_buffered
 ldx #0
@save_draft:
 lda ED_TEXT,x
 sta INPUT_BUFFER,x
 inx
 cpx #160
 bne @save_draft
 lda ED_LEN
 sta ED_SAVE_LEN
 lda ED_CURSOR
 sta ED_SAVE_CURSOR
 lda ED_START
 sta ED_SAVE_START
 lda ED_PAINT_LEN
 sta ED_SAVE_PAINT
 lda #0
 sta ED_PAINT_LEN
 sta ED_LEN
 sta ED_CURSOR
 lda ED_OUT
 sta ED_START
 jsr editor_show_cursor
editor_input_wait:
 lda PENDING
 JNE editor_input_quit
 jsr $ffe4
 cmp #0
 beq editor_input_wait
 sta ED_CHAR
 jsr editor_hide_cursor
 lda ED_GOTO
 bne @go_key
 lda ED_CHAR
 cmp #$88
 JEQ editor_input_quit
 lda ED_HELP
 beq @normal
 lda STRING_LENGTH
 pha
 lda SELECTOR
 pha
 lda INPUT_KIND
 pha
 jsr editor_help_off
 pla
 sta INPUT_KIND
 pla
 sta SELECTOR
 pla
 sta STRING_LENGTH
 jmp @again
@go_key:
 lda STRING_LENGTH
 pha
 lda SELECTOR
 pha
 lda INPUT_KIND
 pha
 jsr editor_goto_key
 pla
 sta INPUT_KIND
 pla
 sta SELECTOR
 pla
 sta STRING_LENGTH
 jmp @again
@normal:
 lda ED_CHAR
 cmp #$87
 bne @go
 lda STRING_LENGTH
 pha
 lda SELECTOR
 pha
 lda INPUT_KIND
 pha
 ldx #0
@binary_backup:
 lda INPUT_BUFFER,x
 sta BE_INPUT_BACKUP,x
 inx
 cpx #160
 bne @binary_backup
 lda #2
 BINARY_CALL be_open
 pla
 sta INPUT_KIND
 pla
 sta SELECTOR
 pla
 sta STRING_LENGTH
 jmp @again
@go:
 cmp #$86
 bne @help
 jsr editor_begin_goto
 jmp @again
@help:
 cmp #$85
 bne @enter
 jsr editor_help_on
 jmp editor_input_wait
@enter:
 cmp #13
 JEQ @complete
 cmp #5
 bne @insert
 lda ED_LITERAL
 eor #1
 sta ED_LITERAL
 jmp @status
@insert:
 cmp #$94
 bne @delete
 lda ED_MODE
 eor #1
 sta ED_MODE
@status:
 jsr editor_status
 jmp @again
@delete:
 cmp #$14
 bne @literal
 lda ED_CURSOR
 beq @again
 dec ED_CURSOR
 ldx ED_CURSOR
 cpx ED_LEN
 bcs @draw
@shift:
 lda ED_TEXT+1,x
 sta ED_TEXT,x
 inx
 cpx ED_LEN
 bcc @shift
 dec ED_LEN
@draw:
 jsr editor_draw_text
 jmp @again
@literal:
 ldx ED_LITERAL
 bne @type
 cmp #$9d
 beq @left
 cmp #$1d
 beq @right
 cmp #$91
 beq @up
 cmp #$11
 beq @down
 cmp #$13
 beq @home
 cmp #32
 bcc @again
 cmp #$80
 bcc @type
 cmp #$a0
 bcc @again
@type:
 jsr editor_type
@again:
 jsr editor_show_cursor
 jmp editor_input_wait
@home:
 lda #0
 sta ED_CURSOR
 beq @again
@left:
 jsr editor_absolute
 beq @again
 sec
 sbc #1
 jsr editor_seek
 jmp @again
@right:
 jsr editor_absolute
 cmp #159
 bcs @again
 clc
 adc #1
 jsr editor_seek
 jmp @again
@up:
 jsr editor_absolute
 cmp #40
 bcc @again
 sec
 sbc #40
 jsr editor_seek
 jmp @again
@down:
 jsr editor_absolute
 cmp #120
 bcs @again
 clc
 adc #40
 jsr editor_seek
 jmp @again
@complete:
 lda ED_LEN
 sta ED_INPUT_LEN
 ldx #0
@save_input:
 cpx ED_LEN
 beq @newline
 lda ED_TEXT,x
 sta ED_HELP_SCREEN,x
 inx
 bne @save_input
@newline:
 lda #13
 sta ED_HELP_SCREEN,x
 lda ED_START
 clc
 adc ED_LEN
 cmp #160
 bcc :+
 lda #159
:
 sta ED_OUT
 lda ED_LEN
 beq :+
 dec ED_OUT
:
 lda #13
 jsr editor_output
 ldx #0
@restore_draft:
 lda INPUT_BUFFER,x
 sta ED_TEXT,x
 inx
 cpx #160
 bne @restore_draft
 ldx #0
@publish_input:
 lda ED_HELP_SCREEN,x
 sta INPUT_BUFFER,x
 cpx ED_INPUT_LEN
 beq @ready
 inx
 bne @publish_input
@ready:
 lda ED_SAVE_LEN
 sta ED_LEN
 lda ED_SAVE_CURSOR
 sta ED_CURSOR
 lda ED_SAVE_START
 sta ED_START
 lda ED_SAVE_PAINT
 sta ED_PAINT_LEN
 lda #0
 sta ED_INPUT_POS
 lda #1
 sta ED_INPUT_READY
editor_input_buffered:
 ldx ED_INPUT_POS
 lda INPUT_BUFFER,x
 inc ED_INPUT_POS
 cmp #13
 bne @return
 ldx #0
 stx ED_INPUT_READY
@return:
 sta ED_CHAR
 pla
 tay
 pla
 tax
 lda ED_CHAR
 clc
 rts
editor_input_quit:
 COMMAND_CALL command_quit
