.segment "RUNTIME"
; Precise nonmoving mark-and-sweep. All object ownership is in roots, not headers.
; Sweep visits physical blocks and releases unreachable string allocations.
collect:
 lda #$ff
 sta GC_PAGE
 lda #0
 sta GC_FREE_PREV
 sta GC_FREE_PREV+1
 sta GC_SCAN
 lda FREE_HEAD
 sta GC_FREE_NEXT
 lda FREE_HEAD+1
 sta GC_FREE_NEXT+1
 lda #1
 sta GC_BUSY
 lda #>USER_BASE
 sta GC_SCAN+1
@block:
 lda GC_SCAN+1
 cmp #$d0
 bcc @visit
 cmp #$e0
 bcs @upper
 ; Valid physical blocks end exactly at $D000; the low byte is zero.
 lda #$e0
 sta GC_SCAN+1
@upper:
 lda GC_SCAN+1
 cmp #$e4
 JCS @merge
@visit:
 ; Reservations contain arbitrary bytes, never allocator headers.
 ldx #0
@reserved:
 cpx RESERVE_COUNT
 beq @allocation
 lda GC_SCAN
 bne @next_reserved
 lda GC_SCAN+1
 cmp RESERVATIONS,x
 bne @next_reserved
 lda RESERVATIONS+1,x
 sta GC_SCAN+1
 jmp @block
@next_reserved:
 inx
 inx
 bne @reserved
@allocation:
 lda GC_SCAN
 sta PTR
 clc
 adc #2
 sta GC_CAND
 lda GC_SCAN+1
 sta PTR+1
 adc #0
 sta GC_CAND+1
 ldy #0
 lda (PTR),y
 clc
 adc GC_SCAN
 sta GC_NEXT
 iny
 lda (PTR),y
 adc GC_SCAN+1
 sta GC_NEXT+1
 ; Walk existing free blocks once alongside the physical sweep. Their links
 ; stay sorted while unreachable blocks are inserted using the previous cursor.
 lda GC_SCAN
 cmp GC_FREE_NEXT
 bne @live_candidate
 lda GC_SCAN+1
 cmp GC_FREE_NEXT+1
 bne @live_candidate
 ldy #2
 lda (PTR),y
 sta GC_FREE_NEXT
 iny
 lda (PTR),y
 sta GC_FREE_NEXT+1
 jmp @free_previous
@live_candidate:
 ; Mark all roots once per 2-KiB window, not once per allocation.
 lda GC_CAND+1
 and #$f8
 cmp GC_PAGE
 beq @marked
 sta GC_PAGE
 lda #0
 ldx #0
@clear_marks:
 sta GC_MARKS,x
 inx
 bne @clear_marks
 jsr gc_roots
@marked:
 ldy GC_CAND
 lda GC_CAND+1
 and #7
 tax
 lda GC_MARKS,y
 and gc_bits,x
 bne @next
 ; Reuse the allocator's insertion tail with sorted PREV/WALK cursors.
 ; GC_BUSY defers coalescing so future physical headers remain intact.
 jsr gc_free_insert
@free_previous:
 lda GC_SCAN
 sta GC_FREE_PREV
 lda GC_SCAN+1
 sta GC_FREE_PREV+1
@next:
 lda GC_NEXT
 sta GC_SCAN
 lda GC_NEXT+1
 sta GC_SCAN+1
 jmp @block
@merge:
 lda #0
 sta GC_BUSY
 lda FREE_HEAD
 sta PTR
 lda FREE_HEAD+1
 sta PTR+1
@coalesce:
 lda PTR
 ora PTR+1
 beq @done
 jsr coalesce
 bcs @coalesce
 ldy #2
 lda (PTR),y
 tax
 iny
 lda (PTR),y
 sta PTR+1
 stx PTR
 jmp @coalesce
@done:
 rts
gc_mark:
 ; Each byte covers eight possible payload starts sharing their low byte.
 ; Preserve the root enumerator's Y; X contains the incoming high byte.
 sta TMP
 txa
 eor GC_PAGE
 cmp #8
 bcs @done
 tax
 sty TMP+1
 ldy TMP
 lda gc_bits,x
 ora GC_MARKS,y
 sta GC_MARKS,y
 ldy TMP+1
@done:
 rts
gc_bits:
.byte $01,$02,$04,$08,$10,$20,$40,$80
gc_roots:
@temporaries:
 lda DIRECT_PAYLOAD
 ldx DIRECT_PAYLOAD+1
 jsr gc_mark
 lda STRING_PTR
 ldx STRING_PTR+1
 jsr gc_mark
 lda FRAME_STEP
 ldx FRAME_STEP+1
 jsr gc_mark
 lda STRING_CELL
 ldx STRING_CELL+1
 jsr gc_mark
 lda EXPR_TOP
 asl
 asl
 sta GC_INDEX
 ldy #0
@stack:
 cpy GC_INDEX
 beq @names
 lda EXPR_STACK,y
 cmp #1
 bne @stack_next
 lda EXPR_STACK+2,y
 ldx EXPR_STACK+3,y
 jsr gc_mark
@stack_next:
 iny
 iny
 iny
 iny
 jmp @stack
@names:
 lda NAME_HEAD
 sta SOURCE
 lda NAME_HEAD+1
 sta SOURCE+1
@name:
 lda SOURCE
 ldx SOURCE+1
 jsr gc_mark
 lda SOURCE
 ora SOURCE+1
 beq @slabs
 ldy #6
 lda (SOURCE),y
 tax
 dey
 lda (SOURCE),y
 jsr gc_mark
 jsr gc_record_next
 jmp @name
@slabs:
 lda SLAB_HEAD
 sta SOURCE
 lda SLAB_HEAD+1
 sta SOURCE+1
@slab:
 lda SOURCE
 ldx SOURCE+1
 jsr gc_mark
 lda SOURCE
 ora SOURCE+1
 beq @arrays
 ldy #2
 lda (SOURCE),y
 sta GC_INDEX
 clc
 lda SOURCE
 adc #3
 sta CPTR
 lda SOURCE+1
 adc #0
 sta CPTR+1
@anchor:
 lda GC_INDEX
 beq @next_slab
 ldy #6
 lda (CPTR),y
 tax
 dey
 lda (CPTR),y
 jsr gc_mark
 clc
 lda CPTR
 adc #7
 sta CPTR
 bcc :+
 inc CPTR+1
:
 dec GC_INDEX
 jmp @anchor
@next_slab:
 jsr gc_record_next
 jmp @slab
@arrays:
 lda ARRAY_HEAD
 sta SOURCE
 lda ARRAY_HEAD+1
 sta SOURCE+1
@array:
 lda SOURCE
 ldx SOURCE+1
 jsr gc_mark
 lda SOURCE
 ora SOURCE+1
 beq @functions
 ldy #4
 lda (SOURCE),y
 sta CPTR
 iny
 lda (SOURCE),y
 sta CPTR+1
 tax
 lda CPTR
 jsr gc_mark
 lda CPTR
 ora CPTR+1
 beq @next_array
 ldy #7
 lda (SOURCE),y
 and #1
 beq @next_array
 lda CPTR
 sec
 sbc #2
 sta PTR2
 lda CPTR+1
 sbc #0
 sta PTR2+1
 ldy #0
 lda (PTR2),y
 clc
 adc PTR2
 sta GC_END
 iny
 lda (PTR2),y
 adc PTR2+1
 sta GC_END+1
 ldy #6
 lda (SOURCE),y
 asl
 clc
 adc CPTR
 sta CPTR
 bcc :+
 inc CPTR+1
:
@element:
 lda CPTR
 cmp GC_END
 bne @descriptor
 lda CPTR+1
 cmp GC_END+1
 beq @next_array
@descriptor:
 ldy #2
 lda (CPTR),y
 tax
 dey
 lda (CPTR),y
 jsr gc_mark
 clc
 lda CPTR
 adc #4
 sta CPTR
 bcc :+
 inc CPTR+1
:
 jmp @element
@next_array:
 jsr gc_record_next
 jmp @array
@functions:
 lda FUNCTION_HEAD
 sta SOURCE
 lda FUNCTION_HEAD+1
 sta SOURCE+1
@function:
 lda SOURCE
 ldx SOURCE+1
 jsr gc_mark
 lda SOURCE
 ora SOURCE+1
 beq @garbage
 jsr gc_record_next
 jmp @function
@garbage:
 rts
gc_record_next:
 ldy #0
 lda (SOURCE),y
 tax
 iny
 lda (SOURCE),y
 sta SOURCE+1
 stx SOURCE
 rts
