.segment "COMMAND"
; Sequential source transport. Native filename bytes have been staged in BRIDGE.
file_command:
 jsr $ffcc
 lda FILE_NAME_LEN
 cmp #252
 JCS file_fail
 tax
 lda #','
 sta BRIDGE,x
 inx
 lda #'S'
 sta BRIDGE,x
 inx
 lda #','
 sta BRIDGE,x
 inx
 lda FILE_OPERATION
 cmp #$34
 bne :+
 lda #'W'
 bne @suffix
:
 lda #'R'
@suffix:
 sta BRIDGE,x
 inx
 txa
 ldx #<BRIDGE
 ldy #>BRIDGE
 jsr $ffbd
 lda #1
 ldx FILE_DEVICE
 ldy #2
 jsr $ffba
 jsr $ffc0
 JCS file_fail
 lda FILE_OPERATION
 cmp #$34
 beq @save
 ldx #1
 jsr $ffc6
 JCS file_fail
 cmp #$33
 lda FILE_OPERATION
 cmp #$33
 JEQ file_load
 lda #1
 sta FILE_MODE
 jmp serialize_source
@save:
 ldx #1
 jsr $ffc9
 JCS file_fail
 lda #0
 sta FILE_MODE
serialize_source:
 jsr export_map
 lda #$ff
 sta FILE_CRC
 sta FILE_CRC+1
 ldx #0
@header:
 lda source_header,x
 jsr file_put
 inx
 cpx #10
 bne @header
 lda FILE_COUNT
 jsr file_put
 lda FILE_COUNT+1
 jsr file_put
 lda #0
 sta FILE_ID
 sta FILE_ID+1
@dictionary:
 lda FILE_ID
 cmp NAME_COUNT
 bne @name
 lda FILE_ID+1
 cmp NAME_COUNT+1
 beq @lines
@name:
 jsr map_pointer
 ldy #0
 jsr read_word
 lda VALUE+1
 cmp #$ff
 beq @advance_name
 lda FILE_ID
 sta VALUE
 lda FILE_ID+1
 sta VALUE+1
 jsr bind_name
 ldy #8
 lda (WALK),y
 sta LEX_LEN
 jsr file_put
 jsr name_bytes
 ldy #0
@name_byte:
 lda (PTR2),y
 jsr file_put
 iny
 dec LEX_LEN
 bne @name_byte
@advance_name:
 inc FILE_ID
 bne @dictionary
 inc FILE_ID+1
 jmp @dictionary
@lines:
 lda PROGRAM_HEAD
 sta FILE_ANCHOR
 lda PROGRAM_HEAD+1
 sta FILE_ANCHOR+1
@line:
 lda FILE_ANCHOR
 cmp #<run_end
 bne @live
 lda FILE_ANCHOR+1
 cmp #>run_end
 JEQ @marker
@live:
 jsr file_tokens
 lda FILE_ANCHOR
 sta WALK
 lda FILE_ANCHOR+1
 sta WALK+1
 ldy #3
 lda (WALK),y
 jsr file_put
 iny
 lda (WALK),y
 jsr file_put
 ; Rewrite into LEX_BUFFER with dense name IDs; payload bytes are copied verbatim.
 lda #0
 sta TOKEN_POS
 sta LEX_LEN
@remap:
 lda TOKEN_POS
 cmp TOKEN_LEN
 beq @record
 jsr token_peek
 cmp #$80
 bcs @direct_name
 cmp #$19
 beq @extended_name
 lda TOKEN_POS
 sta SCRATCH+36
 jsr skip_token
 ldx SCRATCH+36
@copy_token:
 lda TOKENS,x
 ldy LEX_LEN
 sta LEX_BUFFER,y
 inc LEX_LEN
 inx
 cpx TOKEN_POS
 bne @copy_token
 jmp @remap
@direct_name:
 jsr token_take
 sec
 sbc #$80
 sta FILE_ID
 lda #0
 sta FILE_ID+1
 jmp @mapped_name
@extended_name:
 inc TOKEN_POS
 jsr token_take
 sta FILE_ID
 jsr token_take
 sta FILE_ID+1
@mapped_name:
 jsr map_pointer
 ldy #0
 jsr read_word
 ldx LEX_LEN
 lda VALUE+1
 bne @wide
 lda VALUE
 cmp #128
 bcs @wide
 ora #$80
 sta LEX_BUFFER,x
 inc LEX_LEN
 jmp @remap
@wide:
 lda #$19
 sta LEX_BUFFER,x
 inx
 lda VALUE
 sta LEX_BUFFER,x
 inx
 lda VALUE+1
 sta LEX_BUFFER,x
 inx
 stx LEX_LEN
 jmp @remap
@record:
 lda LEX_LEN
 jsr file_put
 ldx #0
@tokens:
 lda LEX_BUFFER,x
 jsr file_put
 inx
 cpx LEX_LEN
 bne @tokens
 lda FILE_ANCHOR
 sta WALK
 lda FILE_ANCHOR+1
 sta WALK+1
 jsr next_line
 lda WALK
 sta FILE_ANCHOR
 lda WALK+1
 sta FILE_ANCHOR+1
 jmp @line
@marker:
 lda #$ff
 jsr file_put
 lda #$ff
 jsr file_put
 lda FILE_CRC
 jsr transport_put
 lda FILE_CRC+1
 jsr transport_put
 lda FILE_MAP
 sta PTR
 lda FILE_MAP+1
 sta PTR+1
 jsr command_free
 lda #0
 sta FILE_MAP
 sta FILE_MAP+1
 lda MEM_IO
 beq file_close
 rts
file_close:
 lda MEM_IO
 JNE clean_complete
 jsr $ffcc
 lda #1
 jsr $ffc3
 rts
file_fail:
 lda MEM_IO
 JNE clean_fail
 jsr $ffcc
 lda #1
 jsr $ffc3
 lda #ERR_SYNTAX
 jmp command_error
source_header: .byte "AB64SRC",0,1,0
file_put:
 sta FILE_BYTE
 txa
 pha
 tya
 pha
 lda FILE_BYTE
 jsr crc_byte
 lda FILE_BYTE
 jsr transport_put
 pla
 tay
 pla
 tax
 rts
transport_put:
 ldx MEM_IO
 JNE memory_put
 ldx FILE_MODE
 bne @verify
 jmp $ffd2
@verify:
 sta FILE_BYTE
 jsr $ffcf
 cmp FILE_BYTE
 bne file_fail
 rts
.segment "COMPILER"
crc_byte:
 eor FILE_CRC+1
 sta FILE_CRC+1
 ldx #8
@bit:
 asl FILE_CRC
 rol FILE_CRC+1
 bcc @next
 lda FILE_CRC
 eor #$21
 sta FILE_CRC
 lda FILE_CRC+1
 eor #$10
 sta FILE_CRC+1
@next:
 dex
 bne @bit
 rts
map_pointer:
 lda FILE_ID
 asl
 sta TMP
 lda FILE_ID+1
 rol
 sta TMP+1
 clc
 lda FILE_MAP
 adc TMP
 sta PTR
 lda FILE_MAP+1
 adc TMP+1
 sta PTR+1
 rts
.segment "COMMAND"
export_map:
 lda NAME_COUNT
 asl
 sta SIZE
 lda NAME_COUNT+1
 rol
 sta SIZE+1
 bcs file_fail
 clc
 lda SIZE
 adc #2
 pha
 lda SIZE+1
 adc #0
 tax
 pla
 jsr command_alloc
 lda ALLOC_RESULT
 sta FILE_MAP
 sta DEST
 lda ALLOC_RESULT+1
 sta FILE_MAP+1
 sta DEST+1
 lda NAME_COUNT
 asl
 sta COUNT
 lda NAME_COUNT+1
 rol
 sta COUNT+1
 ldy #0
@clear:
 lda COUNT
 ora COUNT+1
 beq @scan
 lda #$ff
 sta (DEST),y
 inc DEST
 bne :+
 inc DEST+1
:
 lda COUNT
 bne :+
 dec COUNT+1
:
 dec COUNT
 jmp @clear
@scan:
 lda PROGRAM_HEAD
 sta FILE_ANCHOR
 lda PROGRAM_HEAD+1
 sta FILE_ANCHOR+1
@line:
 lda FILE_ANCHOR
 cmp #<run_end
 bne @live
 lda FILE_ANCHOR+1
 cmp #>run_end
 beq @assign
@live:
 jsr file_tokens
 lda #0
 sta TOKEN_POS
@token:
 lda TOKEN_POS
 cmp TOKEN_LEN
 beq @next_line
 jsr token_peek
 cmp #$80
 bcs @direct
 cmp #$19
 beq @extended
 jsr skip_token
 jmp @token
@direct:
 jsr token_take
 sec
 sbc #$80
 sta FILE_ID
 lda #0
 sta FILE_ID+1
 jmp @mark
@extended:
 inc TOKEN_POS
 jsr token_take
 sta FILE_ID
 jsr token_take
 sta FILE_ID+1
@mark:
 jsr map_pointer
 ldy #0
 lda #0
 sta (PTR),y
 iny
 sta (PTR),y
 jmp @token
@next_line:
 lda FILE_ANCHOR
 sta WALK
 lda FILE_ANCHOR+1
 sta WALK+1
 jsr next_line
 lda WALK
 sta FILE_ANCHOR
 lda WALK+1
 sta FILE_ANCHOR+1
 jmp @line
@assign:
 lda #0
 sta FILE_COUNT
 sta FILE_COUNT+1
 sta FILE_ID
 sta FILE_ID+1
@id:
 lda FILE_ID
 cmp NAME_COUNT
 bne @entry
 lda FILE_ID+1
 cmp NAME_COUNT+1
 beq @done
@entry:
 jsr map_pointer
 ldy #0
 jsr read_word
 lda VALUE+1
 cmp #$ff
 beq @advance
 lda FILE_COUNT
 sta (PTR),y
 iny
 lda FILE_COUNT+1
 sta (PTR),y
 inc FILE_COUNT
 bne @advance
 inc FILE_COUNT+1
@advance:
 inc FILE_ID
 bne @id
 inc FILE_ID+1
 jmp @id
@done:
 rts
.segment "COMPILER"
file_tokens:
 lda FILE_ANCHOR
 sta WALK
 lda FILE_ANCHOR+1
 sta WALK+1
 ldy #5
 lda (WALK),y
 sta PTR
 iny
 lda (WALK),y
 sta PTR+1
 ldy #0
 jsr read_ram
 sta TOKEN_LEN
 ldx #0
@copy:
 iny
 jsr read_ram
 sta TOKENS,x
 inx
 cpx TOKEN_LEN
 bne @copy
 rts
file_get:
 lda $90
 and #$40
 JNE load_fail
 jsr transport_get
 sta FILE_BYTE
 txa
 pha
 tya
 pha
 lda FILE_BYTE
 jsr crc_byte
 pla
 tay
 pla
 tax
 lda FILE_BYTE
 rts
; LOAD builds a second graph with the old graph still allocated.
.segment "COMPILER"
file_load:
 lda NAME_COUNT
 sta LOAD_OLD+14
 lda NAME_COUNT+1
 sta LOAD_OLD+15
 lda #1
 sta LOADING
 ldx #0
@save_state:
 lda STATE,x
 sta LOAD_OLD,x
 inx
 cpx #10
 bne @save_state
 lda FUNCTION_HEAD
 sta LOAD_OLD+10
 lda FUNCTION_HEAD+1
 sta LOAD_OLD+11
 lda ARRAY_HEAD
 sta LOAD_OLD+12
 lda ARRAY_HEAD+1
 sta LOAD_OLD+13
 lda #0
 sta NAME_HEAD
 sta NAME_HEAD+1
 sta NAME_COUNT
 sta NAME_COUNT+1
 sta SLAB_HEAD
 sta SLAB_HEAD+1
 sta ARRAY_HEAD
 sta ARRAY_HEAD+1
 sta FUNCTION_HEAD
 sta FUNCTION_HEAD+1
 lda #<run_end
 sta PROGRAM_HEAD
 lda #>run_end
 sta PROGRAM_HEAD+1
 lda #$ff
 sta FILE_CRC
 sta FILE_CRC+1
 ldx #0
@header:
 jsr file_get
 cmp source_header,x
 JNE load_fail
 inx
 cpx #10
 bne @header
 jsr file_get
 sta FILE_COUNT
 jsr file_get
 sta FILE_COUNT+1
@name:
 lda NAME_COUNT
 cmp FILE_COUNT
 bne @get_name
 lda NAME_COUNT+1
 cmp FILE_COUNT+1
 beq @records
@get_name:
 jsr file_get
 sta LEX_LEN
 JEQ load_fail
 ldx #0
@name_byte:
 jsr file_get
 sta LEX_BUFFER,x
 inx
 cpx LEX_LEN
 bne @name_byte
 jsr validate_name
 jsr intern_name
 lda VALUE
 clc
 adc #1
 sta TMP
 lda VALUE+1
 adc #0
 sta TMP+1
 lda TMP
 cmp NAME_COUNT
 JNE load_fail
 lda TMP+1
 cmp NAME_COUNT+1
 JNE load_fail
 jmp @name
@records:
 lda #0
 sta FILE_ANCHOR
 sta FILE_ANCHOR+1
@line:
 jsr file_get
 sta LINE_NO
 jsr file_get
 sta LINE_NO+1
 cmp #$ff
 bne @number
 lda LINE_NO
 cmp #$ff
 beq @crc
@number:
 lda LINE_NO+1
 cmp #$fa
 bcs load_fail
 lda FILE_ANCHOR
 ora FILE_ANCHOR+1
 beq @tokens
 lda FILE_ANCHOR
 sta WALK
 lda FILE_ANCHOR+1
 sta WALK+1
 ldy #4
 lda (WALK),y
 cmp LINE_NO+1
 bcc @tokens
 bne load_fail
 dey
 lda (WALK),y
 cmp LINE_NO
 bcs load_fail
@tokens:
 jsr file_get
 sta TOKEN_LEN
 beq load_fail
 ldx #0
@token:
 jsr file_get
 sta TOKENS,x
 inx
 cpx TOKEN_LEN
 bne @token
 jsr validate_tokens
 jsr edit_line
 lda ANCHOR
 sta FILE_ANCHOR
 lda ANCHOR+1
 sta FILE_ANCHOR+1
 jmp @line
@crc:
 jsr transport_get
 cmp FILE_CRC
 bne load_fail
 jsr transport_get
 cmp FILE_CRC+1
 bne load_fail
 lda $90
 and #$40
 beq load_fail
 ; New graph is valid; release old graph and keep the allocator's merged free list.
 lda #0
 sta LOADING
 sta CONT_PC
 sta CONT_PC+1
 jsr release_old_graph
 jsr file_close
 jmp ready
load_fail:
 lda #0
 sta LOADING
 ; Rollback source heads. Full staged-graph reclamation is performed first.
 jsr release_live_graph
 ldx #2
@restore:
 lda LOAD_OLD,x
 sta STATE,x
 inx
 cpx #10
 bne @restore
 lda LOAD_OLD+14
 sta NAME_COUNT
 lda LOAD_OLD+15
 sta NAME_COUNT+1
 lda LOAD_OLD+10
 sta FUNCTION_HEAD
 lda LOAD_OLD+11
 sta FUNCTION_HEAD+1
 lda LOAD_OLD+12
 sta ARRAY_HEAD
 lda LOAD_OLD+13
 sta ARRAY_HEAD+1
 jmp file_fail
release_old_graph:
 ; Swap heads, destroy old graph, then restore newly validated heads.
 ldx #2
@swap:
 lda STATE,x
 tay
 lda LOAD_OLD,x
 sta STATE,x
 tya
 sta LOAD_OLD,x
 inx
 cpx #10
 bne @swap
 jsr release_live_graph
 ldx #2
@new:
 lda LOAD_OLD,x
 sta STATE,x
 inx
 cpx #10
 bne @new
 rts
release_live_graph:
 lda PROGRAM_HEAD
 sta FILE_ANCHOR
 lda PROGRAM_HEAD+1
 sta FILE_ANCHOR+1
@line:
 lda FILE_ANCHOR
 cmp #<run_end
 bne @free_line
 lda FILE_ANCHOR+1
 cmp #>run_end
 beq @names
@free_line:
 lda FILE_ANCHOR
 sta WALK
 lda FILE_ANCHOR+1
 sta WALK+1
 jsr next_line
 lda WALK
 sta FILE_NEXT
 lda WALK+1
 sta FILE_NEXT+1
 lda FILE_ANCHOR
 sta WALK
 lda FILE_ANCHOR+1
 sta WALK+1
 ldy #5
 lda (WALK),y
 sta PTR
 iny
 lda (WALK),y
 sta PTR+1
 jsr command_free
 lda FILE_NEXT
 sta FILE_ANCHOR
 lda FILE_NEXT+1
 sta FILE_ANCHOR+1
 jmp @line
@names:
 lda NAME_HEAD
 sta FILE_ANCHOR
 lda NAME_HEAD+1
 sta FILE_ANCHOR+1
 jsr free_record_chain
 lda SLAB_HEAD
 sta FILE_ANCHOR
 lda SLAB_HEAD+1
 sta FILE_ANCHOR+1
 jmp free_record_chain
free_record_chain:
 lda FILE_ANCHOR
 ora FILE_ANCHOR+1
 beq @done
 lda FILE_ANCHOR
 sta PTR
 lda FILE_ANCHOR+1
 sta PTR+1
 ldy #0
 lda (PTR),y
 sta FILE_NEXT
 iny
 lda (PTR),y
 sta FILE_NEXT+1
 jsr command_free
 lda FILE_NEXT
 sta FILE_ANCHOR
 lda FILE_NEXT+1
 sta FILE_ANCHOR+1
 jmp free_record_chain
@done:
 rts
.segment "COMMAND"
validate_tokens:
 lda #0
 sta TOKEN_POS
 sta SCRATCH+41
@token:
 lda TOKEN_POS
 cmp TOKEN_LEN
 JEQ @done
 JCS load_fail
 jsr token_peek
 cmp #$80
 JCS @direct
 cmp #$70
 JCS @small
 cmp #$6b
 JCS load_fail
 cmp #$20
 bcs @keyword
 cmp #$1a
 JEQ @small
 cmp #$1b
 JEQ @small
 cmp #$1c
 JCS load_fail
 cmp #$19
 JEQ @extended
 cmp #$10
 JCC @small
 JEQ @byte
 cmp #$11
 JEQ @word
 cmp #$12
 JEQ @word
 sta SCRATCH+42
 cmp #$14
 JEQ load_fail
 cmp #$15
 beq @data_only
 cmp #$16
 beq @data_only
 jmp @raw
@data_only:
 lda SCRATCH+41
 JEQ load_fail
@raw:
 inc TOKEN_POS
 lda #1
 jsr token_need
 jsr token_take
 bne @raw_length
 lda SCRATCH+42
 cmp #$16
 JCS load_fail
 lda #0 ; empty STRING/DATA_TEXT: keep the payload length, not its token code
@raw_length:
 jsr token_need
 clc
 adc TOKEN_POS
 sta TOKEN_POS
 jmp @token
@keyword:
 cmp #$23
 bne @rem
 lda #1
 sta SCRATCH+41
 jmp @small
@rem:
 cmp #$2f
 JNE @small
 inc TOKEN_POS
 lda #2
 jsr token_need
 jsr token_take
 cmp #$14
 JNE load_fail
 jsr token_take
 clc
 adc TOKEN_POS
 JCS load_fail
 cmp TOKEN_LEN
 JNE load_fail
 sta TOKEN_POS
 jmp @token
@byte:
 inc TOKEN_POS
 lda #1
 jsr token_need
 jsr token_take
 cmp #16
 JCC load_fail
 jmp @token
@word:
 lda #3
 jsr token_need
 jsr token_take
 cmp #$12
 beq @hex
 jsr token_take
 jsr token_take
 cmp #0
 JEQ load_fail
 jmp @token
@hex:
 inc TOKEN_POS
 inc TOKEN_POS
 jmp @token
@direct:
 jsr token_take
 sec
 sbc #$80
 sta VALUE
 lda #0
 sta VALUE+1
 jmp @name
@extended:
 lda #3
 jsr token_need
 inc TOKEN_POS
 jsr token_take
 sta VALUE
 jsr token_take
 sta VALUE+1
 bne @name
 lda VALUE
 cmp #128
 JCC load_fail
@name:
 lda VALUE+1
 cmp NAME_COUNT+1
 JCC @token
 JNE load_fail
 lda VALUE
 cmp NAME_COUNT
 JCS load_fail
 jmp @token
@small:
 cmp #0
 bne :+
 sta SCRATCH+41
:
 inc TOKEN_POS
 jmp @token
@done:
 rts

.segment "COMPILER"
validate_name:
 ldx #0
@byte:
 lda LEX_BUFFER,x
 cmp #'A'
 bcc @digit
 cmp #'Z'+1
 bcc @next
@digit:
 cpx #0
 JEQ load_fail
 cmp #'0'
 bcc @suffix
 cmp #'9'+1
 bcc @next
@suffix:
 cmp #'$'
 beq @last
 cmp #'%'
 JNE load_fail
@last:
 inx
 cpx LEX_LEN
 JNE load_fail
 jmp @reserved
@next:
 inx
 cpx LEX_LEN
 bne @byte
@reserved:
 lda #0
 sta ABBREVIATED
 jsr find_keyword
 JCS load_fail
 rts

.segment "COMMAND"
token_need:
 pha
 clc
 adc TOKEN_POS
 JCS load_fail
 cmp TOKEN_LEN
 bcc @ok
 JNE load_fail
@ok:
 pla
 rts
