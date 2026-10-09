.segment "COMPILER"
; RESERVE is a stopped, top-level declaration of page-aligned literal address and byte count.
; Apply during sizing so source/code allocations cannot claim the user region.
compile_reserve:
 lda IF_COUNT
 JNE compile_recover
 jsr parse_immediate
 JCS compile_recover
 lda VALUE
 bne reserve_quantity
 sta RESERVE_START
 lda VALUE+1
 sta RESERVE_START+1
 lda #1
 jsr expect
 jsr parse_immediate
 JCS compile_recover
 lda VALUE
 bne reserve_quantity
 sta RESERVE_END
 lda VALUE+1
 beq reserve_quantity
 clc
 adc RESERVE_START+1
 sta RESERVE_END+1
 bcs reserve_quantity
 jsr token_peek
 beq @boundary ; colon
 cmp #$ff ; token_peek uses $ff at end
 JNE compile_recover
@boundary:
 lda EMIT_PASS
 bne @done
 jsr reserve_region
@done:
 clc
 rts
reserve_quantity:
 lda #ERR_QUANTITY
 jmp command_error
reserve_memory:
 lda #ERR_MEMORY
 jmp command_error
reserve_region:
 ; Require a wholly owned arena span; never reserve workspace, I/O or runtime.
 lda RESERVE_START+1
 cmp #>USER_BASE
 JCC reserve_quantity
 cmp #$d0
 bcc @lower
 cmp #$e0
 JCC reserve_quantity
 lda RESERVE_END+1
 cmp #$e4
 bcc @existing
 JNE reserve_quantity
 beq @existing
@lower:
 lda RESERVE_END+1
 cmp #$d0
 bcc @existing
 JNE reserve_quantity
@existing:
 ldx #0
@reservation:
 cpx RESERVE_COUNT
 beq @scan_setup
 lda RESERVATIONS,x
 cmp RESERVE_START+1
 bne @next_reservation
 lda RESERVATIONS+1,x
 cmp RESERVE_END+1
 JEQ @done
@next_reservation:
 inx
 inx
 bne @reservation
@scan_setup:
 cpx #16
 JCS reserve_memory
 lda #0
 sta PREV
 sta PREV+1
 lda FREE_HEAD
 sta WALK
 lda FREE_HEAD+1
 sta WALK+1
@scan:
 lda WALK
 ora WALK+1
 JEQ reserve_memory
 jsr ptr_from_walk
 ldy #0
 jsr read_word
 clc
 lda VALUE
 adc WALK
 sta RESERVE_BLOCK_END
 lda VALUE+1
 adc WALK+1
 sta RESERVE_BLOCK_END+1
 ; start >= free start, end <= free end, using unsigned comparisons.
 lda RESERVE_START
 cmp WALK
 lda RESERVE_START+1
 sbc WALK+1
 bcc @next
 lda RESERVE_BLOCK_END
 cmp RESERVE_END
 lda RESERVE_BLOCK_END+1
 sbc RESERVE_END+1
 bcs @found
@next:
 lda WALK
 sta PREV
 lda WALK+1
 sta PREV+1
 ldy #2
 jsr read_word
 lda VALUE
 sta WALK
 lda VALUE+1
 sta WALK+1
 jmp @scan
@found:
 ; Both remaining fragments must hold a free header (zero is allowed).
 sec
 lda RESERVE_START
 sbc WALK
 sta LEFT
 lda RESERVE_START+1
 sbc WALK+1
 sta LEFT+1
 bne @right
 lda LEFT
 beq @right
 cmp #4
 JCC reserve_quantity
@right:
 sec
 lda RESERVE_BLOCK_END
 sbc RESERVE_END
 sta RIGHT
 lda RESERVE_BLOCK_END+1
 sbc RESERVE_END+1
 sta RIGHT+1
 bne @split
 lda RIGHT
 beq @split
 cmp #4
 JCC reserve_quantity
@split:
 ldy #2
 jsr read_word
 lda VALUE
 sta RESERVE_NEXT
 lda VALUE+1
 sta RESERVE_NEXT+1
 lda RIGHT
 ora RIGHT+1
 beq @left
 lda RESERVE_END
 sta DEST
 lda RESERVE_END+1
 sta DEST+1
 ldy #0
 lda RIGHT
 sta (DEST),y
 iny
 lda RIGHT+1
 sta (DEST),y
 iny
 lda RESERVE_NEXT
 sta (DEST),y
 iny
 lda RESERVE_NEXT+1
 sta (DEST),y
 lda DEST
 sta RESERVE_NEXT
 lda DEST+1
 sta RESERVE_NEXT+1
@left:
 lda LEFT
 ora LEFT+1
 beq @unlink
 ldy #0
 lda LEFT
 sta (PTR),y
 iny
 lda LEFT+1
 sta (PTR),y
 lda WALK
 sta PREV
 lda WALK+1
 sta PREV+1
@unlink:
 lda PREV
 ora PREV+1
 beq @head
 ldy #2
 lda RESERVE_NEXT
 sta (PREV),y
 iny
 lda RESERVE_NEXT+1
 sta (PREV),y
 jmp @publish
@head:
 lda RESERVE_NEXT
 sta FREE_HEAD
 lda RESERVE_NEXT+1
 sta FREE_HEAD+1
@publish:
 ldx RESERVE_COUNT
 lda RESERVE_START+1
 sta RESERVATIONS,x
 lda RESERVE_END+1
 sta RESERVATIONS+1,x
 inx
 inx
 stx RESERVE_COUNT
@done:
 rts
