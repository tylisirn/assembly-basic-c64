.segment "COMMAND"
; READ_WORD reads two bytes through the common-RAM shadow accessor.
read_word:
 jsr read_ram
 sta VALUE
 iny
 jsr read_ram
 sta VALUE+1
 dey
 rts
ptr_from_walk:
 lda WALK
 sta PTR
 lda WALK+1
 sta PTR+1
 rts
; Derive trailer from physical allocation end, never scan code bytes.
trailer:
 ldy #5
 lda (WALK),y
 sec
 sbc #2
 sta PTR
 iny
 lda (WALK),y
 sbc #0
 sta PTR+1
 ldy #0
 jsr read_word
 clc
 lda PTR
 adc VALUE
 sta PTR
 lda PTR+1
 adc VALUE+1
 sta PTR+1
 sec
 lda PTR
 sbc #3
 sta PTR
 lda PTR+1
 sbc #0
 sta PTR+1
 rts
next_line:
 jsr trailer
 ldy #0
 jsr read_ram
 cmp #$4c
 bne corrupt_program
 iny
 jsr read_word
 lda VALUE
 sta WALK
 lda VALUE+1
 sta WALK+1
 rts
corrupt_program:
 lda #ERR_SYNTAX
 jmp command_error
; Stable packed slabs: header2,next2,count1,35*7 =250 physical bytes.
find_anchor:
 lda SLAB_HEAD
 sta WALK
 lda SLAB_HEAD+1
 sta WALK+1
@slab:
 lda WALK
 ora WALK+1
 beq @new_slab
 ldy #2
 lda (WALK),y
 sta SLAB_USED
 clc
 lda WALK
 adc #3
 sta PTR2
 lda WALK+1
 adc #0
 sta PTR2+1
 ldx #0
@slot:
 cpx SLAB_USED
 beq @next_slab
 ldy #3
 lda (PTR2),y
 cmp LINE_NO
 bne @skip
 iny
 lda (PTR2),y
 cmp LINE_NO+1
 beq @found
@skip:
 clc
 lda PTR2
 adc #7
 sta PTR2
 bcc :+
 inc PTR2+1
:
 inx
 jmp @slot
@next_slab:
 ldy #0
 lda (WALK),y
 tax
 iny
 lda (WALK),y
 sta WALK+1
 stx WALK
 jmp @slab
@found:
 lda PTR2
 sta ANCHOR
 lda PTR2+1
 sta ANCHOR+1
 rts
@new_slab:
 lda SLAB_HEAD
 sta WALK
 lda SLAB_HEAD+1
 sta WALK+1
 lda WALK
 ora WALK+1
 beq @allocate
 ldy #2
 lda (WALK),y
 cmp #35
 bcc @new_slot
@allocate:
 lda #250
 ldx #0
 jsr command_alloc_common
 lda ALLOC_RESULT
 sta WALK
 lda ALLOC_RESULT+1
 sta WALK+1
 ldy #0
 lda SLAB_HEAD
 sta (WALK),y
 iny
 lda SLAB_HEAD+1
 sta (WALK),y
 iny
 lda #0
 sta (WALK),y
 lda WALK
 sta SLAB_HEAD
 lda WALK+1
 sta SLAB_HEAD+1
@new_slot:
 ldy #2
 lda (WALK),y
 sta SLAB_USED
 clc
 adc #1
 sta (WALK),y
 lda #0
 sta TMP+1
 lda SLAB_USED
 asl
 sta TMP
 asl
 clc
 adc TMP
 adc SLAB_USED ; count * 7
 sta TMP
 clc
 adc #3
 sta TMP
 clc
 lda WALK
 adc TMP
 sta ANCHOR
 lda WALK+1
 adc #0
 sta ANCHOR+1
 lda ANCHOR
 sta PTR
 lda ANCHOR+1
 sta PTR+1
 ldy #0
 lda #$4c
 sta (PTR),y
 iny
 lda #<undefined_line
 sta (PTR),y
 iny
 lda #>undefined_line
 sta (PTR),y
 iny
 lda LINE_NO
 sta (PTR),y
 iny
 lda LINE_NO+1
 sta (PTR),y
 iny
 lda #0
 sta (PTR),y
 iny
 sta (PTR),y
 rts
find_position:
 lda #0
 sta PREDECESSOR
 sta PREDECESSOR+1
 lda PROGRAM_HEAD
 sta WALK
 lda PROGRAM_HEAD+1
 sta WALK+1
@loop:
 lda WALK
 cmp #<run_end
 bne @compare
 lda WALK+1
 cmp #>run_end
 beq @done
@compare:
 ldy #4
 lda (WALK),y
 cmp LINE_NO+1
 bcc @advance
 bne @done
 dey
 lda (WALK),y
 cmp LINE_NO
 bcs @done
@advance:
 lda WALK
 sta PREDECESSOR
 lda WALK+1
 sta PREDECESSOR+1
 jsr next_line
 jmp @loop
@done:
 lda WALK
 sta SUCCESSOR
 lda WALK+1
 sta SUCCESSOR+1
 rts
invalidate:
 lda #0
 sta CONT_PC
 sta CONT_PC+1
 sta CONTROL_TOP
 sta CONTROL_TOP+1
 inc GENERATION
 bne :+
 inc GENERATION+1
:
 jmp clear_values
edit_line:
 jsr find_anchor
 jsr find_position
 lda ANCHOR
 sta PTR
 lda ANCHOR+1
 sta PTR+1
 ldy #5
 lda (PTR),y
 sta OLD_PAYLOAD
 iny
 lda (PTR),y
 sta OLD_PAYLOAD+1
 ora OLD_PAYLOAD
 beq @compile
 lda ANCHOR
 sta WALK
 lda ANCHOR+1
 sta WALK+1
 jsr next_line
 lda WALK
 sta SUCCESSOR
 lda WALK+1
 sta SUCCESSOR+1
@compile:
 jsr compile_payload
 jsr invalidate
 php
 sei
 jsr publish_anchor
 lda OLD_PAYLOAD
 ora OLD_PAYLOAD+1
 bne @published
 jsr patch_predecessor
@published:
 plp
 lda OLD_PAYLOAD
 sta PTR
 lda OLD_PAYLOAD+1
 sta PTR+1
 ora PTR
 beq @done
 jsr command_free
@done:
 rts
publish_anchor:
 lda ANCHOR
 sta PTR
 lda ANCHOR+1
 sta PTR+1
 ldy #0
 lda #$4c
 sta (PTR),y
 iny
 clc
 lda NEW_PAYLOAD
 adc TOKEN_LEN
 sta VALUE
 lda NEW_PAYLOAD+1
 adc #0
 sta VALUE+1
 inc VALUE
 bne :+
 inc VALUE+1
:
 lda VALUE
 sta (PTR),y
 iny
 lda VALUE+1
 sta (PTR),y
 ldy #5
 lda NEW_PAYLOAD
 sta (PTR),y
 iny
 lda NEW_PAYLOAD+1
 sta (PTR),y
 rts
patch_predecessor:
 lda PREDECESSOR
 ora PREDECESSOR+1
 beq @head
 lda PREDECESSOR
 sta WALK
 lda PREDECESSOR+1
 sta WALK+1
 jsr trailer
 ldy #1
 lda ANCHOR
 sta (PTR),y
 iny
 lda ANCHOR+1
 sta (PTR),y
 rts
@head:
 lda ANCHOR
 sta PROGRAM_HEAD
 lda ANCHOR+1
 sta PROGRAM_HEAD+1
 rts
delete_line:
 jsr find_position
 lda SUCCESSOR
 cmp #<run_end
 bne :+
 lda SUCCESSOR+1
 cmp #>run_end
 beq @done
:
 ldy #3
 lda (WALK),y
 cmp LINE_NO
 bne @done
 iny
 lda (WALK),y
 cmp LINE_NO+1
 bne @done
 lda WALK
 sta ANCHOR
 lda WALK+1
 sta ANCHOR+1
 ldy #5
 lda (WALK),y
 sta OLD_PAYLOAD
 iny
 lda (WALK),y
 sta OLD_PAYLOAD+1
 jsr next_line
 lda ANCHOR
 pha
 lda ANCHOR+1
 pha
 lda WALK
 sta ANCHOR
 lda WALK+1
 sta ANCHOR+1
 jsr invalidate
 php
 sei
 jsr patch_predecessor
 plp
 pla
 sta PTR+1
 pla
 sta PTR
 ldy #1
 lda #<undefined_line
 sta (PTR),y
 iny
 lda #>undefined_line
 sta (PTR),y
 ldy #5
 lda #0
 sta (PTR),y
 iny
 sta (PTR),y
 lda OLD_PAYLOAD
 sta PTR
 lda OLD_PAYLOAD+1
 sta PTR+1
 jsr command_free
@done:
 rts
; Dictionary records: next2,id2,descriptor4,length1,name[length].
; Full byte comparisons; cells bind directly to descriptor offset four.
intern_name:
 lda NAME_HEAD
 sta WALK
 lda NAME_HEAD+1
 sta WALK+1
@search:
 lda WALK
 ora WALK+1
 beq @new
 ldy #8
 lda (WALK),y
 cmp LEX_LEN
 bne @next
 jsr name_bytes
 ldx #0
 ldy #0
@compare:
 lda (PTR2),y
 cmp LEX_BUFFER,x
 bne @next
 inx
 iny
 cpx LEX_LEN
 bne @compare
 ldy #2
 lda (WALK),y
 sta VALUE
 iny
 lda (WALK),y
 sta VALUE+1
 rts
@next:
 ldy #0
 lda (WALK),y
 tax
 iny
 lda (WALK),y
 sta WALK+1
 stx WALK
 jmp @search
@new:
 lda NAME_COUNT
 cmp #$ff
 bne @capacity_ok
 lda NAME_COUNT+1
 cmp #$ff
 JEQ command_quantity
@capacity_ok:
 clc
 lda LEX_LEN
 adc #11
 ldx #0
 bcc :+
 inx
:
 jsr command_alloc_common
 lda ALLOC_RESULT
 sta WALK
 lda ALLOC_RESULT+1
 sta WALK+1
 ldy #0
 lda NAME_HEAD
 sta (WALK),y
 iny
 lda NAME_HEAD+1
 sta (WALK),y
 iny
 lda NAME_COUNT
 sta (WALK),y
 sta VALUE
 iny
 lda NAME_COUNT+1
 sta (WALK),y
 sta VALUE+1
 lda #0
 ldy #4
@zero:
 sta (WALK),y
 iny
 cpy #8
 bne @zero
 lda LEX_LEN
 sta (WALK),y
 jsr name_bytes
 ldx #0
 ldy #0
@name:
 lda LEX_BUFFER,x
 sta (PTR2),y
 iny
 inx
 cpx LEX_LEN
 bne @name
 lda WALK
 sta NAME_HEAD
 lda WALK+1
 sta NAME_HEAD+1
 inc NAME_COUNT
 bne :+
 inc NAME_COUNT+1
:
 rts
bind_name:
 ; VALUE holds name ID; return stable descriptor address in CELL.
 lda NAME_HEAD
 sta WALK
 lda NAME_HEAD+1
 sta WALK+1
@loop:
 lda WALK
 ora WALK+1
 JEQ corrupt_program
 ldy #2
 lda (WALK),y
 cmp VALUE
 bne @next
 iny
 lda (WALK),y
 cmp VALUE+1
 beq @found
@next:
 ldy #0
 lda (WALK),y
 tax
 iny
 lda (WALK),y
 sta WALK+1
 stx WALK
 jmp @loop
@found:
 clc
 lda WALK
 adc #4
 sta CELL
 lda WALK+1
 adc #0
 sta CELL+1
 jsr name_bytes
 ldy #8
 lda (WALK),y
 tay
 dey
 lda (PTR2),y
 cmp #'$'
 rts

bind_array:
 ; parse_name leaves VALUE=ID and Z set for a string suffix.
 php
 lda VALUE
 sta SCRATCH+20
 lda VALUE+1
 sta SCRATCH+21
 plp
 beq @string
 lda #0
 beq @numeric
@string:
 lda #1
@numeric:
 sta SCRATCH+22
 lda ARRAY_HEAD
 sta WALK
 lda ARRAY_HEAD+1
 sta WALK+1
@scan:
 lda WALK
 ora WALK+1
 beq @new
 ldy #2
 lda (WALK),y
 cmp SCRATCH+20
 bne @next
 iny
 lda (WALK),y
 cmp SCRATCH+21
 beq @found
@next:
 ldy #0
 lda (WALK),y
 tax
 iny
 lda (WALK),y
 sta WALK+1
 stx WALK
 jmp @scan
@new:
 lda #10
 ldx #0
 jsr command_alloc_common
 lda ALLOC_RESULT
 sta WALK
 lda ALLOC_RESULT+1
 sta WALK+1
 ldy #0
 lda ARRAY_HEAD
 sta (WALK),y
 iny
 lda ARRAY_HEAD+1
 sta (WALK),y
 iny
 lda SCRATCH+20
 sta (WALK),y
 iny
 lda SCRATCH+21
 sta (WALK),y
 iny
 lda #0
 sta (WALK),y
 iny
 sta (WALK),y
 iny
 sta (WALK),y
 iny
 lda SCRATCH+22
 sta (WALK),y
 lda WALK
 sta ARRAY_HEAD
 lda WALK+1
 sta ARRAY_HEAD+1
@found:
 lda WALK
 sta CELL
 lda WALK+1
 sta CELL+1
 rts
bind_function:
 lda VALUE
 sta SCRATCH+20
 lda VALUE+1
 sta SCRATCH+21
 lda FUNCTION_HEAD
 sta WALK
 lda FUNCTION_HEAD+1
 sta WALK+1
@search:
 lda WALK
 ora WALK+1
 beq @new
 ldy #2
 lda (WALK),y
 cmp SCRATCH+20
 bne @next
 iny
 lda (WALK),y
 cmp SCRATCH+21
 beq @found
@next:
 ldy #0
 lda (WALK),y
 tax
 iny
 lda (WALK),y
 sta WALK+1
 stx WALK
 jmp @search
@new:
 lda #10
 ldx #0
 jsr command_alloc_common
 lda ALLOC_RESULT
 sta WALK
 lda ALLOC_RESULT+1
 sta WALK+1
 ldy #0
 lda FUNCTION_HEAD
 sta (WALK),y
 iny
 lda FUNCTION_HEAD+1
 sta (WALK),y
 iny
 lda SCRATCH+20
 sta (WALK),y
 iny
 lda SCRATCH+21
 sta (WALK),y
 ldy #4
 lda #0
@zero:
 sta (WALK),y
 iny
 cpy #8
 bne @zero
 lda WALK
 sta FUNCTION_HEAD
 lda WALK+1
 sta FUNCTION_HEAD+1
@found:
 lda WALK
 sta FUNCTION_RECORD
 lda WALK+1
 sta FUNCTION_RECORD+1
 rts

.segment "COMMAND"
name_bytes:
 clc
 lda WALK
 adc #9
 sta PTR2
 lda WALK+1
 adc #0
 sta PTR2+1
 rts
