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
 STORAGE_CALL be_mark_basic
 bcc @done
 jmp command_error
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
 STORAGE_CALL be_reserve_pages
 bcc @done
 jmp command_error
@done:
 rts
