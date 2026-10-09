.segment "COMPILER"
; Stopped transactional rebuild through the canonical source serializer/loader.
; MEM_IO: 0 device, 1 count, 2 write snapshot, 3 read snapshot.
command_clean:
 lda TOKEN_LEN
 cmp #1
 JNE list_syntax
 lda #0
 sta CLEAN_BUFFER
 sta CLEAN_BUFFER+1
 sta CLEAN_SIZE
 sta CLEAN_SIZE+1
 sta FILE_MAP
 sta FILE_MAP+1
 jsr clean_collect
 lda #1
 sta MEM_IO
 jsr serialize_source
 clc
 lda CLEAN_SIZE
 adc #2
 pha
 lda CLEAN_SIZE+1
 adc #0
 tax
 pla
 jsr command_alloc
 lda ALLOC_RESULT
 sta CLEAN_BUFFER
 sta CLEAN_PTR
 lda ALLOC_RESULT+1
 sta CLEAN_BUFFER+1
 sta CLEAN_PTR+1
 lda #2
 sta MEM_IO
 jsr serialize_source
 lda CLEAN_BUFFER
 sta CLEAN_PTR
 lda CLEAN_BUFFER+1
 sta CLEAN_PTR+1
 lda #0
 sta $90
 lda #3
 sta MEM_IO
 jmp file_load
memory_put:
 sta FILE_BYTE
 lda MEM_IO
 cmp #1
 bne @write
 inc CLEAN_SIZE
 bne @done
 inc CLEAN_SIZE+1
@done:
 rts
@write:
 tya
 pha
 lda CLEAN_PTR
 sta DEST
 lda CLEAN_PTR+1
 sta DEST+1
 ldy #0
 lda FILE_BYTE
 sta (DEST),y
 jsr clean_increment
 pla
 tay
 rts
transport_get:
 lda MEM_IO
 cmp #3
 beq @memory
 jmp $ffcf
@memory:
 tya
 pha
 lda CLEAN_PTR
 sta PTR
 lda CLEAN_PTR+1
 sta PTR+1
 ldy #0
 jsr read_ram
 sta FILE_BYTE
 jsr clean_increment
 sec
 lda CLEAN_PTR
 sbc CLEAN_BUFFER
 sta TMP
 lda CLEAN_PTR+1
 sbc CLEAN_BUFFER+1
 cmp CLEAN_SIZE+1
 bne @return
 lda TMP
 cmp CLEAN_SIZE
 bne @return
 lda #$40
 sta $90
@return:
 pla
 tay
 lda FILE_BYTE
 rts
clean_increment:
 inc CLEAN_PTR
 bne :+
 inc CLEAN_PTR+1
:
 rts
clean_complete:
 lda #0
 sta CONTROL_TOP
 sta CONTROL_TOP+1
 sta FROZEN_TOP
 sta FROZEN_TOP+1
 sta CONT_PC
 sta CONT_PC+1
 sta EXPR_TOP
 sta STRING_PTR
 sta STRING_PTR+1
 sta STRING_CELL
 sta STRING_CELL+1
 sta FRAME_STEP
 sta FRAME_STEP+1
 sta DIRECT_PAYLOAD
 sta DIRECT_PAYLOAD+1
 jsr clear_values
 jsr clean_release
 jmp clean_collect
clean_release:
 lda CLEAN_BUFFER
 sta PTR
 lda CLEAN_BUFFER+1
 sta PTR+1
 ora PTR
 beq @map
 jsr command_free
@map:
 lda FILE_MAP
 sta PTR
 lda FILE_MAP+1
 sta PTR+1
 ora PTR
 beq @done
 jsr command_free
@done:
 lda #0
 sta CLEAN_BUFFER
 sta CLEAN_BUFFER+1
 sta FILE_MAP
 sta FILE_MAP+1
 sta MEM_IO
 rts
clean_fail:
 jsr clean_release
 jsr clean_collect
 lda ERROR_CODE
 bne :+
 lda #ERR_SYNTAX
:
 sta ERROR_CODE
 jmp ready
clean_collect:
 lda #<collect
 sta gateway_call+1
 lda #>collect
 sta gateway_call+2
 jmp call_ram
