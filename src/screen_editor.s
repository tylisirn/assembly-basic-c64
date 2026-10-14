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
 bne @no
 inx
 iny
 cpy #4
 bne @quit
 lda #2
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
 sta ED_HELP
 sta ED_SUBMITTED
 sta ED_CURSOR_ON
 sta ED_INPUT_READY
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
 jsr editor_listing
 lda ED_TEMP
 beq @success
 lda #0
 sta ED_START
 jsr editor_draw_text
 lda #39
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
 lda ED_CHAR
 cmp #$88 ; F7
 JEQ @quit
 lda ED_HELP
 beq @normal
 jsr editor_help_off
 jmp editor_read
@normal:
 lda ED_CHAR
 cmp #$85 ; F1
 bne @focus
 jsr editor_help_on
 jmp editor_wait
@focus:
 cmp #$5f ; C64 left-arrow key
 bne @pane
 lda ED_FOCUS
 eor #1
 sta ED_FOCUS
 bne @focused
 jsr editor_clear_pane
@focused:
 jsr editor_listing
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
 cmp #$94 ; shift-DEL cycles the three writing modes
 bne @motion
 inc ED_MODE
 lda ED_MODE
 cmp #3
 bcc @mode
 lda #0
 sta ED_MODE
@mode:
 jsr editor_status
 jmp editor_read
@motion:
 cmp #$14
 JEQ editor_delete
 ldx ED_MODE
 cpx #2
 beq @type
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
 lda ED_MODE
 cmp #2
 beq @type
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
 lda ED_CURSOR
 beq @done
 dec ED_CURSOR
@done:
 jmp editor_read
editor_right:
 lda ED_CURSOR
 clc
 adc ED_START
 cmp #159
 bcs @done
 inc ED_CURSOR
@done:
 jmp editor_read
editor_up:
 lda ED_CURSOR
 cmp #40
 bcc @done
 sec
 sbc #40
 sta ED_CURSOR
@done:
 jmp editor_read
editor_down:
 lda ED_CURSOR
 clc
 adc ED_START
 cmp #120
 bcs @done
 lda ED_CURSOR
 clc
 adc #40
 sta ED_CURSOR
@done:
 jmp editor_read

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
editor_erase_pane:
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
 ; Retain earlier direct output above ED_START, repaint the current draft below.
 ldx ED_START
@clear:
 lda #' '
 sta $0748,x
 lda #14
 sta $db48,x
 inx
 cpx #160
 bcc @clear
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
 cpx #2
 bne @normal
 lda #$8c ; reverse L in cyan
@normal:
 sta (ED_PTR),y
 lda #14
 cpx #0
 beq @color
 lda #0
 cpx #1
 beq @color
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
 cmp #4
 JEQ editor_error_char
 lda ED_CODE
 cmp #13
 JEQ editor_output_cr
 cmp #147
 beq @clear
 cmp #$13
 beq @home
 cmp #$14
 beq @delete
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
 bcc @done
 jsr editor_scroll_pane
 lda #120
 sta ED_OUT
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
 rts
editor_scroll_pane:
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
 beq @newline
@literal:
 lda ED_ROW
 cmp #20
 bcs @advance
 tax
 lda editor_rows_lo,x
 sta ED_PTR
 lda editor_rows_hi,x
 sta ED_PTR+1
 lda ED_PTR
 sta ED_CPTR
 lda ED_PTR+1
 clc
 adc #$d4
 sta ED_CPTR+1
 lda ED_CODE
 jsr editor_screen_code
 ldx ED_HIGHLIGHT
 beq :+
 ora #$80
:
 ldy ED_COL
 sta (ED_PTR),y
 lda #14
 sta (ED_CPTR),y
@advance:
 inc ED_COL
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
editor_listing:
 ; Normalize numeric bookmarks against the current graph after every mutation.
 jsr editor_find_selected
 jsr editor_is_end
 bne @selected
 lda PROGRAM_HEAD
 sta ED_ANCHOR
 lda PROGRAM_HEAD+1
 sta ED_ANCHOR+1
@selected:
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
 lda ED_SEEN
 bne @done
 jsr editor_find_selected
 jsr editor_is_end
 beq @done
 lda ED_SELECTED
 sta ED_TOP
 lda ED_SELECTED+1
 sta ED_TOP+1
 jsr editor_paint_listing
@done:
 lda #0
 sta ED_ROUTE
 sta ED_HIGHLIGHT
 lda #14
 sta ED_COLOR
 rts
editor_paint_listing:
 lda #0
 sta ED_ROW
 sta ED_COL
 sta ED_SEEN
 jsr editor_clear_listing
 jsr editor_find_top
@line:
 jsr editor_is_end
 beq @done
 lda ED_ROW
 cmp #20
 bcs @done
 jsr editor_anchor_number
 stx ED_LAST
 sta ED_LAST+1
 lda #0
 sta ED_HIGHLIGHT
 sta ED_INDENT
 lda ED_LAST
 cmp ED_SELECTED
 bne @print
 lda ED_LAST+1
 cmp ED_SELECTED+1
 bne @print
 lda #1
 sta ED_SEEN
 lda ED_FOCUS
 bne @print
 lda #1
 sta ED_HIGHLIGHT
@print:
 lda ED_ANCHOR
 sta LIST_ANCHOR
 lda ED_ANCHOR+1
 sta LIST_ANCHOR+1
 lda #1
 sta ED_ROUTE
 COMMAND_CALL print_source_line
 lda ED_COL
 beq @advanced
 inc ED_ROW
 lda #0
 sta ED_COL
@advanced:
 COMMAND_CALL editor_next
 sta ED_ANCHOR
 stx ED_ANCHOR+1
 jmp @line
@done:
 rts
editor_clear_listing:
 ldx #0
@pages:
 lda #' '
 sta $0400,x
 sta $0500,x
 sta $0600,x
 lda #14
 sta $d800,x
 sta $d900,x
 sta $da00,x
 inx
 bne @pages
 ldx #31
@tail:
 lda #' '
 sta $0700,x
 lda #14
 sta $db00,x
 dex
 bpl @tail
 rts

editor_select_next:
 jsr editor_find_selected
 jsr editor_is_end
 beq @done
 COMMAND_CALL editor_next
 sta ED_ANCHOR
 stx ED_ANCHOR+1
 jsr editor_is_end
 beq @done
 jsr editor_anchor_number
 stx ED_SELECTED
 sta ED_SELECTED+1
 cmp ED_LAST+1
 bcc @paint
 bne @scroll
 cpx ED_LAST
 bcc @paint
 beq @paint
@scroll:
 jsr editor_find_top
 lda #5
 sta ED_STEPS
@five:
 COMMAND_CALL editor_next
 sta ED_NEXT
 stx ED_NEXT+1
 cmp #<run_end
 bne @accept
 cpx #>run_end
 beq @scrolled
@accept:
 lda ED_NEXT
 sta ED_ANCHOR
 lda ED_NEXT+1
 sta ED_ANCHOR+1
 dec ED_STEPS
 bne @five
@scrolled:
 jsr editor_anchor_number
 stx ED_TOP
 sta ED_TOP+1
@paint:
 jsr editor_listing
@done:
 rts
editor_select_previous:
 jsr editor_find_selected
 jsr editor_is_end
 beq @done
 COMMAND_CALL editor_previous
 sta ED_ANCHOR
 stx ED_ANCHOR+1
 ora ED_ANCHOR+1
 beq @done
 jsr editor_anchor_number
 stx ED_SELECTED
 sta ED_SELECTED+1
 cmp ED_TOP+1
 bcc @scroll
 bne @paint
 cpx ED_TOP
 bcs @paint
@scroll:
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
 jsr editor_anchor_number
 stx ED_TOP
 sta ED_TOP+1
@paint:
 jsr editor_listing
@done:
 rts

editor_copy_line:
 jsr editor_find_selected
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
 jsr editor_listing
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
editor_modes_lo: .byte <editor_insert_text,<editor_overwrite_text,<editor_literal_text
editor_modes_hi: .byte >editor_insert_text,>editor_overwrite_text,>editor_literal_text
editor_key_label: .byte "F1 HELP F7 QUIT "

editor_pane_message:
 sta ED_PTR
 stx ED_PTR+1
 ldy #0
@char:
 lda (ED_PTR),y
 beq @done
 tya
 pha
 jsr editor_output
 pla
 tay
 iny
 bne @char
@done:
 rts
editor_help_on:
 ldx #0
@save:
 lda $0748,x
 sta ED_HELP_SCREEN,x
 lda $db48,x
 sta ED_HELP_COLORS,x
 inx
 cpx #160
 bne @save
 lda #1
 sta ED_HELP
 lda #3
 sta ED_ROUTE
 lda #0
 sta ED_ROW
 sta ED_COL
 sta ED_INDENT
 sta ED_HIGHLIGHT
 jsr editor_clear_listing
 lda #<editor_help_text
 sta ED_PTR
 lda #>editor_help_text
 sta ED_PTR+1
 ; Save the text pointer on the hardware stack around the screen writer.
 ldy #0
@char:
 lda (ED_PTR),y
 beq @done
 sta ED_CHAR
 lda ED_PTR
 pha
 lda ED_PTR+1
 pha
 tya
 pha
 lda ED_CHAR
 jsr editor_output
 pla
 tay
 pla
 sta ED_PTR+1
 pla
 sta ED_PTR
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
 jsr editor_listing
 jsr editor_status
 ldx #0
@restore:
 lda ED_HELP_SCREEN,x
 sta $0748,x
 lda ED_HELP_COLORS,x
 sta $db48,x
 inx
 cpx #160
 bne @restore
 rts
editor_help_text:
 .byte "ASSEMBLY BASIC SCREEN EDITOR",13,13
 .byte "CURSOR KEYS  SELECT / MOVE TEXT",13
 .byte "RETURN       COPY LINE / SUBMIT",13
 .byte "LEFT ARROW   SWITCH LIST / EDIT",13
 .byte "SHIFT-DEL    INSERT/OVERWRITE/LITERAL",13
 .byte "DEL          DELETE PREVIOUS CHARACTER",13
 .byte "HOME         START OF EDIT LINE",13
 .byte "F1           HELP",13
 .byte "F7 / QUIT    CLEAR SCREEN AND EXIT",13
 .byte "RUN          EXIT AND RUN PROGRAM",13,13
 .byte "ENTER A NUMBERED LINE TO ADD OR CHANGE.",13
 .byte "A LINE NUMBER ALONE DELETES THAT LINE.",13
 .byte "DIRECT COMMANDS PRINT IN THE LOWER PANE.",13
 .byte "LEFT ARROW TO LIST DISCARDS THE DRAFT.",13
 .byte "LITERAL TYPES CONTROL CODES AS GLYPHS.",13
 .byte "BASIC REOPENS AT YOUR LAST POSITION.",13,13
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
 lda #0
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
@normal:
 lda ED_CHAR
 cmp #$85
 bne @enter
 jsr editor_help_on
 jmp editor_input_wait
@enter:
 cmp #13
 JEQ @complete
 cmp #$94
 bne @delete
 inc ED_MODE
 lda ED_MODE
 cmp #3
 bcc @status
 lda #0
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
 ldx ED_MODE
 cpx #2
 beq @type
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
 lda ED_CURSOR
 beq @again
 dec ED_CURSOR
 jmp @again
@right:
 lda ED_CURSOR
 clc
 adc ED_START
 cmp #159
 bcs @again
 inc ED_CURSOR
 jmp @again
@up:
 lda ED_CURSOR
 cmp #40
 bcc @again
 sec
 sbc #40
 sta ED_CURSOR
 jmp @again
@down:
 lda ED_CURSOR
 clc
 adc ED_START
 cmp #120
 bcs @again
 lda ED_CURSOR
 clc
 adc #40
 sta ED_CURSOR
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
