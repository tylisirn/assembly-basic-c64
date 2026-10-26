.segment "BINARY_STORAGE"
; BLOAD/BSAVE use the editor's raw sequential format. FILE_ID is the current
; address, FILE_COUNT the remaining length; operation $eb means EOF-bounded.
binary_file_command:
 lda FILE_NAME_LEN
 beq @syntax
 cmp #252
 bcs @syntax
 lda FILE_OPERATION
 bmi @name
 ; Reject a bounded transfer that would wrap past $ffff. Ending at $10000
 ; is valid, including a zero-byte operation at any address.
 clc
 lda FILE_ID
 adc FILE_COUNT
 sta TMP
 lda FILE_ID+1
 adc FILE_COUNT+1
 bcc @name
 ora TMP
 beq @name
 lda #ERR_QUANTITY
 RAM_CALL runtime_error
@syntax:
 lda #ERR_SYNTAX
 RAM_CALL runtime_error
@name:
 ldx FILE_NAME_LEN
 lda #','
 sta BRIDGE,x
 inx
 lda #'S'
 sta BRIDGE,x
 inx
 lda #','
 sta BRIDGE,x
 inx
 lda #'R'
 ldy FILE_OPERATION
 cpy #$6c
 bne :+
 lda #'W'
:
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
 lda #0
 sta FILE_MODE ; pending error, retained across CLRCHN/CLOSE
 jsr $ffcc
 jsr $ffc0
 JCS binary_file_error
 lda $90
 JNE binary_file_error
 lda FILE_OPERATION
 cmp #$6c
 beq @output
 ldx #1
 jsr $ffc6
 JCS binary_file_error
 jmp @read
@output:
 ldx #1
 jsr $ffc9
 JCS binary_file_error
 lda $90
 JNE binary_file_error
@write:
 lda FILE_COUNT
 ora FILE_COUNT+1
 JEQ binary_file_close
 jsr binary_file_pointer
 jsr read_ram
 jsr $ffd2
 JCS binary_file_error
 lda $90
 JNE binary_file_error
 jsr binary_file_advance
 jmp @write
@read:
 lda $90
 and #$bf ; EOF can accompany the last valid byte, even an empty file.
 JNE binary_file_error
 lda $90
 and #$40
 JNE binary_file_close
 bit FILE_OPERATION
 bmi @byte
 lda FILE_COUNT
 ora FILE_COUNT+1
 JEQ binary_file_close
@byte:
 jsr $ffcf
 pha
 lda $90
 and #$bf
 bne @read_error
 jsr binary_file_pointer
 pla
 sta (PTR),y ; writes RAM under ROM, with hardware I/O exposed
 jsr binary_file_advance
 lda FILE_ID
 ora FILE_ID+1
 bne @read
 ; Never wrap an unbounded read into zero page. EOF at $ffff is valid.
 lda $90
 and #$40
 bne binary_file_close
 bit FILE_OPERATION
 bpl @read
 lda #ERR_QUANTITY
 sta FILE_MODE
 jmp binary_file_close
@read_error:
 pla
binary_file_error:
 lda #ERR_DEVICE
 sta FILE_MODE
binary_file_close:
 jsr $ffcc
 lda #1
 jsr $ffc3
 lda $90
 and #$bf
 beq :+
 lda #ERR_DEVICE
 sta FILE_MODE
:
 lda FILE_MODE
 bne @error
 lda FILE_OPERATION
 cmp #$6c
 bne @done
 jsr file_save_status
 bcc @done
 lda #ERR_DEVICE
@error:
 RAM_CALL runtime_error
@done:
 rts
binary_file_pointer:
 lda FILE_ID
 sta PTR
 lda FILE_ID+1
 sta PTR+1
 ldy #0
 rts
binary_file_advance:
 inc FILE_ID
 bne :+
 inc FILE_ID+1
:
 lda FILE_COUNT
 bne :+
 dec FILE_COUNT+1
:
 dec FILE_COUNT
 rts

; Check a source SAVE only after closing its data channel, which flushes the
; last buffered byte and commits the directory entry. TALK directly to status
; secondary 15: no extra logical file or CLOSE-15 side effects on user files.
file_save_status:
 lda #1
 sta BE_ERROR
 lda FILE_DEVICE
 jsr $ffb4
 lda $90
 bne @close
 lda #$6f
 jsr $ff96
 lda $90
 bne @close
 lda #0
 sta BE_INDEX
@read:
 lda $90
 and #$40
 bne @close
 jsr $ffa5
 sta BE_TEMP
 lda $90
 and #$bf
 bne @close
 ldx BE_INDEX
 cpx #2
 bcs @tail
 lda BE_TEMP
 cmp #'0'
 bne @close
@tail:
 inc BE_INDEX
 lda BE_TEMP
 cmp #13
 beq @ok
 lda BE_INDEX
 cmp #64
 bcc @read
 bcs @close
@ok:
 lda #0
 sta BE_ERROR
@close:
 jsr $ffab
 lda $90
 and #$bf
 ora BE_ERROR
 beq @success
 sec
 rts
@success:
 clc
 rts

be_reset:
 lda #0
 ldx #88
@first:
 sta $0200,x
 dex
 bpl @first
 ldx #88
@second:
 sta $02a7,x
 dex
 bpl @second
 lda #$b6
 sta BE_MAGIC
 rts
be_bit:
 and #7
 tax
 lda be_bits,x
 rts
be_bits: .byte 1,2,4,8,16,32,64,128
be_res_used:
 jsr be_bit
 and BE_ACTIVE
 rts
be_blob_used:
 pha
 jsr be_bit
 sta BE_TEMP
 pla
 lsr
 lsr
 lsr
 tax
 lda BE_OCCUPIED,x
 and BE_TEMP
 rts
be_blob_pointer:
 cmp #6
 bcs @upper
 asl
 asl
 asl
 clc
 adc #<BE_BLOBS0
 sta ED_PTR
 lda #>BE_BLOBS0
 adc #0
 sta ED_PTR+1
 rts
@upper:
 sec
 sbc #6
 asl
 asl
 asl
 clc
 adc #<BE_BLOBS1
 sta ED_PTR
 lda #>BE_BLOBS1
 adc #0
 sta ED_PTR+1
 rts
be_get_blob:
 jsr be_blob_pointer
 ldy #7
@copy:
 lda (ED_PTR),y
 sta BE_RECORD,y
 dey
 bpl @copy
 rts
be_set_blob:
 lda BE_BLOB_SEL
 jsr be_blob_pointer
 ldy #7
@copy:
 lda BE_RECORD,y
 sta (ED_PTR),y
 dey
 bpl @copy
 lda BE_BLOB_SEL
 jsr be_bit
 sta BE_TEMP
 lda BE_BLOB_SEL
 lsr
 lsr
 lsr
 tax
 lda BE_OCCUPIED,x
 ora BE_TEMP
 sta BE_OCCUPIED,x
 rts
be_delete_blob:
 lda BE_BLOB_SEL
 jsr be_bit
 eor #$ff
 sta BE_TEMP
 lda BE_BLOB_SEL
 lsr
 lsr
 lsr
 tax
 lda BE_OCCUPIED,x
 and BE_TEMP
 sta BE_OCCUPIED,x
 rts
be_get_res:
 asl
 asl
 tax
 lda BE_RES,x
 sta BE_RANGE
 lda BE_RES+1,x
 sta BE_RANGE+1
 lda BE_RES+2,x
 sta BE_END
 lda BE_RES+3,x
 sta BE_END+1
 sec
 lda BE_END
 sbc BE_RANGE
 sta BE_SIZE
 lda BE_END+1
 sbc BE_RANGE+1
 sta BE_SIZE+1
 rts
be_store_res:
 lda BE_RES_SEL
 asl
 asl
 tax
 lda BE_RANGE
 sta BE_RES,x
 lda BE_RANGE+1
 sta BE_RES+1,x
 lda BE_END
 sta BE_RES+2,x
 lda BE_END+1
 sta BE_RES+3,x
 lda BE_RES_SEL
 jsr be_bit
 ora BE_ACTIVE
 sta BE_ACTIVE
 lda #0
 clc
 rts
be_free_res_slot:
 ldy #0
@slot:
 tya
 jsr be_res_used
 beq @found
 iny
 cpy #8
 bne @slot
 jmp be_claim_memory
@found:
 sty BE_RES_SEL
 clc
 rts
be_mark_basic:
 ; Called by the compiler after a successful page RESERVE declaration.
 lda RESERVE_START
 sta BE_RANGE
 lda RESERVE_START+1
 sta BE_RANGE+1
 lda RESERVE_END
 sta BE_END
 lda RESERVE_END+1
 sta BE_END+1
 ldy #0
@exact:
 tya
 asl
 asl
 tax
 lda BE_RES,x
 cmp BE_RANGE
 bne @next
 lda BE_RES+1,x
 cmp BE_RANGE+1
 bne @next
 lda BE_RES+2,x
 cmp BE_END
 bne @next
 lda BE_RES+3,x
 cmp BE_END+1
 beq @found
@next:
 iny
 cpy #8
 bne @exact
 jsr be_free_res_slot
 bcs @return
 jsr be_res_overlap
 bcs @return
 jmp @mark
@found:
 sty BE_RES_SEL
@mark:
 lda BE_RES_SEL
 jsr be_bit
 ora BE_BASIC
 sta BE_BASIC
 jsr be_store_res
@return:
 rts
be_check_range:
 lda BE_SIZE
 ora BE_SIZE+1
 JEQ be_claim_quantity
 clc
 lda BE_RANGE
 adc BE_SIZE
 sta BE_END
 lda BE_RANGE+1
 adc BE_SIZE+1
 sta BE_END+1
 JCS be_claim_quantity
 lda BE_RANGE+1
 cmp #>USER_BASE
 JCC be_claim_quantity
 cmp #$d0
 bcc @lower
 cmp #$e0
 JCC be_claim_quantity
 lda BE_END+1
 cmp #$e4
 bcc @ok
 bne @bad
 lda BE_END
 beq @ok
@bad:
 jmp be_claim_quantity
@lower:
 lda BE_END+1
 cmp #$d0
 bcc @ok
 bne @bad
 lda BE_END
 bne @bad
@ok:
 clc
 rts
be_res_overlap:
 ldy #0
@res:
 cpy BE_RES_SEL
 beq @next
 tya
 jsr be_res_used
 beq @next
 tya
 asl
 asl
 tax
 ; overlap iff proposed start < old end and old start < proposed end
 lda BE_RANGE
 cmp BE_RES+2,x
 lda BE_RANGE+1
 sbc BE_RES+3,x
 bcs @next
 lda BE_RES,x
 cmp BE_END
 lda BE_RES+1,x
 sbc BE_END+1
 JCC be_claim_memory
@next:
 iny
 cpy #8
 bne @res
 clc
 rts
be_reserve_exact:
 jsr be_check_range
 bcs @done
 jsr be_res_overlap
 bcs @done
 ; All existing blobs must still fit after moving/resizing a reservation.
 lda #0
 sta BE_SCAN
@blob:
 lda BE_SCAN
 jsr be_blob_used
 beq @next
 lda BE_SCAN
 jsr be_blob_pointer
 ldy #0
 lda (ED_PTR),y
 cmp BE_RES_SEL
 bne @next
 iny
 lda (ED_PTR),y
 cmp BE_RANGE
 iny
 lda (ED_PTR),y
 sbc BE_RANGE+1
 JCC be_claim_quantity
 lda (ED_PTR),y
 sta RIGHT+1
 dey
 lda (ED_PTR),y
 sta RIGHT
 ldy #3
 clc
 lda (ED_PTR),y
 adc RIGHT
 sta RIGHT
 iny
 lda (ED_PTR),y
 adc RIGHT+1
 sta RIGHT+1
 JCS be_claim_quantity
 lda BE_END
 cmp RIGHT
 lda BE_END+1
 sbc RIGHT+1
 JCC be_claim_quantity
@next:
 inc BE_SCAN
 lda BE_SCAN
 cmp #16
 bne @blob
 jsr be_claim_exact_pages
 bcs @done
 lda BE_RES_SEL
 jsr be_bit
 eor #$ff
 and BE_BASIC
 sta BE_BASIC
 jsr be_store_res
@done:
 rts
be_page_owned:
 ldx #0
@range:
 cpx RESERVE_COUNT
 beq @no
 lda BE_WORK
 cmp RESERVATIONS,x
 bcc @next
 cmp RESERVATIONS+1,x
 bcc @yes
@next:
 inx
 inx
 bne @range
@yes:
 sec
 rts
@no:
 clc
 rts
be_claim_exact_pages:
 lda BE_RANGE+1
 sta BE_WORK
 lda BE_END+1
 ldx BE_END
 beq :+
 clc
 adc #1
:
 sta BE_WORK+1
@page:
 lda BE_WORK
 cmp BE_WORK+1
 beq @done
 jsr be_page_owned
 bcc @run
 inc BE_WORK
 bne @page
@run:
 lda BE_WORK
 sta BE_WORK+2
@extend:
 inc BE_WORK
 lda BE_WORK
 cmp BE_WORK+1
 beq @claim
 jsr be_page_owned
 bcc @extend
@claim:
 lda #0
 sta RESERVE_START
 sta RESERVE_END
 lda BE_WORK+2
 sta RESERVE_START+1
 lda BE_WORK
 sta RESERVE_END+1
 jsr be_reserve_pages
 bcs @return
 jmp @page
@done:
 lda #0
 clc
@return:
 rts
be_delete_res:
 lda #0
 sta BE_SCAN
@blobs:
 lda BE_SCAN
 jsr be_blob_used
 beq @next
 lda BE_SCAN
 jsr be_blob_pointer
 ldy #0
 lda (ED_PTR),y
 cmp BE_RES_SEL
 bne @next
 lda BE_SCAN
 sta BE_BLOB_SEL
 jsr be_delete_blob
@next:
 inc BE_SCAN
 lda BE_SCAN
 cmp #16
 bne @blobs
 lda BE_RES_SEL
 jsr be_bit
 eor #$ff
 and BE_ACTIVE
 sta BE_ACTIVE
 rts
be_validate_blob:
 lda BE_RECORD
 cmp #8
 JCS be_claim_quantity
 jsr be_res_used
 JEQ be_claim_quantity
 lda BE_RECORD
 jsr be_get_res
 lda BE_RANGE
 sta BE_WORK+4
 lda BE_RANGE+1
 sta BE_WORK+5
 lda BE_END
 sta BE_WORK+6
 lda BE_END+1
 sta BE_WORK+7
 lda BE_RECORD+1
 sta BE_RANGE
 lda BE_RECORD+2
 sta BE_RANGE+1
 lda BE_RECORD+3
 sta BE_SIZE
 lda BE_RECORD+4
 sta BE_SIZE+1
 jsr be_check_range
 JCS @done
 lda BE_RECORD+5
 and #$7f
 cmp #3
 JCS be_claim_quantity
 cmp #1
 beq @sprite_size
 lda BE_RECORD+5
 JMI be_claim_quantity
 jmp @bounds
@sprite_size:
 lda BE_SIZE+1
 JNE be_claim_quantity
 lda BE_SIZE
 cmp #64
 JNE be_claim_quantity
@bounds:
 lda BE_RANGE
 cmp BE_WORK+4
 lda BE_RANGE+1
 sbc BE_WORK+5
 JCC be_claim_quantity
 lda BE_WORK+6
 cmp BE_END
 lda BE_WORK+7
 sbc BE_END+1
 JCC be_claim_quantity
 lda #0
 sta BE_SCAN
@other:
 lda BE_SCAN
 cmp BE_BLOB_SEL
 beq @next
 jsr be_blob_used
 beq @next
 lda BE_SCAN
 jsr be_blob_pointer
 ldy #1
 lda (ED_PTR),y
 sta LEFT
 iny
 lda (ED_PTR),y
 sta LEFT+1
 iny
 clc
 lda (ED_PTR),y
 adc LEFT
 sta RIGHT
 iny
 lda (ED_PTR),y
 adc LEFT+1
 sta RIGHT+1
 lda BE_RANGE
 cmp RIGHT
 lda BE_RANGE+1
 sbc RIGHT+1
 bcs @next
 lda LEFT
 cmp BE_END
 lda LEFT+1
 sbc BE_END+1
 JCC be_claim_memory
@next:
 inc BE_SCAN
 lda BE_SCAN
 cmp #16
 bne @other
 clc
@done:
 rts
be_new_blob:
 lda BE_RECORD+5
 sta BE_WORK+8
 lda BE_RES_SEL
 jsr be_get_res
 lda BE_END
 sta BE_WORK+6
 lda BE_END+1
 sta BE_WORK+7
 ; Desired size is passed in BE_PROPOSED, separate from the parent extent.
 lda BE_PROPOSED
 sta BE_SIZE
 lda BE_PROPOSED+1
 sta BE_SIZE+1
@candidate:
 jsr be_check_range
 JCS @done
 lda BE_WORK+6
 cmp BE_END
 lda BE_WORK+7
 sbc BE_END+1
 JCC be_claim_memory
 lda #0
 sta BE_SCAN
@overlap:
 lda BE_SCAN
 jsr be_blob_used
 beq @next
 lda BE_SCAN
 jsr be_blob_pointer
 ldy #0
 lda (ED_PTR),y
 cmp BE_RES_SEL
 bne @next
 iny
 lda (ED_PTR),y
 sta LEFT
 iny
 lda (ED_PTR),y
 sta LEFT+1
 iny
 clc
 lda (ED_PTR),y
 adc LEFT
 sta RIGHT
 iny
 lda (ED_PTR),y
 adc LEFT+1
 sta RIGHT+1
 lda BE_RANGE
 cmp RIGHT
 lda BE_RANGE+1
 sbc RIGHT+1
 bcs @next
 lda LEFT
 cmp BE_END
 lda LEFT+1
 sbc BE_END+1
 bcs @next
 lda RIGHT
 sta BE_RANGE
 lda RIGHT+1
 sta BE_RANGE+1
 jmp @candidate
@next:
 inc BE_SCAN
 lda BE_SCAN
 cmp #16
 bne @overlap
 lda #0
 sta BE_SCAN
@slot:
 lda BE_SCAN
 jsr be_blob_used
 beq @found
 inc BE_SCAN
 lda BE_SCAN
 cmp #16
 bne @slot
 jmp be_claim_memory
@found:
 lda BE_SCAN
 sta BE_BLOB_SEL
 lda BE_RES_SEL
 sta BE_RECORD
 lda BE_RANGE
 sta BE_RECORD+1
 lda BE_RANGE+1
 sta BE_RECORD+2
 lda BE_SIZE
 sta BE_RECORD+3
 lda BE_SIZE+1
 sta BE_RECORD+4
 lda BE_WORK+8
 sta BE_RECORD+5
 lda #$70
 sta BE_RECORD+6
 lda #$91
 sta BE_RECORD+7
 jsr be_set_blob
 clc
@done:
 rts
be_claim_quantity:
 lda #ERR_QUANTITY
 sec
 rts
be_claim_memory:
 lda #ERR_MEMORY
 sec
 rts
be_reserve_pages:
 ; Require a wholly owned arena span; never reserve workspace, I/O or runtime.
 lda RESERVE_START+1
 cmp #>USER_BASE
 JCC be_claim_quantity
 cmp #$d0
 bcc @lower
 cmp #$e0
 JCC be_claim_quantity
 lda RESERVE_END+1
 cmp #$e4
 bcc @existing
 JNE be_claim_quantity
 beq @existing
@lower:
 lda RESERVE_END+1
 cmp #$d0
 bcc @existing
 JNE be_claim_quantity
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
 JCS be_claim_memory
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
 JEQ be_claim_memory
 COMMAND_CALL ptr_from_walk
 ldy #0
 COMMAND_CALL read_word
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
 COMMAND_CALL read_word
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
 JCC be_claim_quantity
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
 JCC be_claim_quantity
@split:
 ldy #2
 COMMAND_CALL read_word
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
 lda #0
 clc
 rts

; Sequential .BIN exchange writes only the chosen range, without metadata.
be_transfer_bytes:
 lda #0
 sta BE_ERROR
 lda BE_RANGE
 sta BE_ADDR
 lda BE_RANGE+1
 sta BE_ADDR+1
 lda BE_SIZE
 sta BE_COUNT
 lda BE_SIZE+1
 sta BE_COUNT+1
 ldx #0
@dot:
 cpx BE_PROMPT_LEN
 beq @extension
 lda BE_INPUT,x
 cmp #'.'
 beq @suffix
 inx
 bne @dot
@extension:
 ldx BE_PROMPT_LEN
 lda #'.'
 sta BE_INPUT,x
 inx
 lda #'B'
 sta BE_INPUT,x
 inx
 lda #'I'
 sta BE_INPUT,x
 inx
 lda #'N'
 sta BE_INPUT,x
 inx
 stx BE_PROMPT_LEN
@suffix:
 ldx BE_PROMPT_LEN
 lda #','
 sta BE_INPUT,x
 inx
 lda #'S'
 sta BE_INPUT,x
 inx
 lda #','
 sta BE_INPUT,x
 inx
 lda BE_FILE_OP
 sta BE_INPUT,x
 inx
 stx BE_FILE_LEN
 txa
 ldx #<BE_INPUT
 ldy #>BE_INPUT
 jsr $ffbd
 lda #240
 ldx #8
 ldy #2
 jsr $ffba
 jsr $ffc0
 bcs @error
 lda BE_FILE_OP
 cmp #'W'
 beq @write_channel
 ldx #240
 jsr $ffc6
 bcs @error
 jmp @read
@write_channel:
 ldx #240
 jsr $ffc9
 bcs @error
@write:
 lda BE_COUNT
 ora BE_COUNT+1
 beq @close
 lda BE_ADDR
 sta PTR
 lda BE_ADDR+1
 sta PTR+1
 ldy #0
 jsr read_ram
 jsr $ffd2
 lda $90
 bne @error
 jsr be_transfer_advance
 jmp @write
@read:
 lda BE_COUNT
 ora BE_COUNT+1
 beq @close
 lda $90
 and #$40
 bne @close
 jsr $ffcf
 pha
 lda $90
 and #$bf
 bne @read_error
 lda BE_ADDR
 sta PTR
 lda BE_ADDR+1
 sta PTR+1
 ldy #0
 pla
 sta (PTR),y
 jsr be_transfer_advance
 jmp @read
@read_error:
 pla
@error:
 lda #ERR_DATA
 sta BE_ERROR
@close:
 jsr $ffcc
 lda #240
 jsr $ffc3
 lda BE_ERROR
 beq @ok
 sec
 rts
@ok:
 clc
 rts
be_transfer_advance:
 inc BE_ADDR
 bne :+
 inc BE_ADDR+1
:
 lda BE_COUNT
 bne :+
 dec BE_COUNT+1
:
 dec BE_COUNT
 rts

; Native source v2 puts reservation descriptors before the dictionary and
; typed blobs after its $FFFF marker. Plain source and CLEAN snapshots retain byte-identical v1 files.
be_save_version:
 lda #1
 sta BE_VERSION
 lda MEM_IO
 bne @done
 lda BE_ACTIVE
 beq @done
 inc BE_VERSION
@done:
 rts
be_write_reservations:
 lda BE_VERSION
 cmp #2
 JNE @done
 lda #0
 sta BE_RES_COUNT
 sta BE_INDEX
@map:
 lda BE_INDEX
 jsr be_res_used
 beq @next
 ldx BE_INDEX
 lda BE_RES_COUNT
 sta BE_RES_MAP,x
 inc BE_RES_COUNT
@next:
 inc BE_INDEX
 lda BE_INDEX
 cmp #8
 bne @map
 lda BE_RES_COUNT
 COMMAND_CALL file_put
 lda #0
 sta BE_INDEX
@res:
 lda BE_INDEX
 jsr be_res_used
 beq @res_next
 lda BE_INDEX
 jsr be_get_res
 lda BE_RANGE
 COMMAND_CALL file_put
 lda BE_RANGE+1
 COMMAND_CALL file_put
 lda BE_SIZE
 COMMAND_CALL file_put
 lda BE_SIZE+1
 COMMAND_CALL file_put
 lda BE_INDEX
 jsr be_bit
 and BE_BASIC
 beq :+
 lda #1
:
 COMMAND_CALL file_put
@res_next:
 inc BE_INDEX
 lda BE_INDEX
 cmp #8
 bne @res
@done:
 rts
be_write_metadata:
 lda BE_VERSION
 cmp #2
 JNE @done
 lda #0
 sta BE_BLOB_COUNT
 sta BE_INDEX
@count:
 lda BE_INDEX
 jsr be_blob_used
 beq :+
 inc BE_BLOB_COUNT
:
 inc BE_INDEX
 lda BE_INDEX
 cmp #16
 bne @count
 lda BE_BLOB_COUNT
 COMMAND_CALL file_put
 lda #0
 sta BE_INDEX
@blob:
 lda BE_INDEX
 jsr be_blob_used
 beq @blob_next
 lda BE_INDEX
 jsr be_get_blob
 ldx BE_RECORD
 lda BE_RES_MAP,x
 COMMAND_CALL file_put
 ldy #1
@record:
 lda BE_RECORD,y
 COMMAND_CALL file_put
 iny
 cpy #8
 bne @record
 lda BE_RECORD+1
 sta BE_ADDR
 lda BE_RECORD+2
 sta BE_ADDR+1
 lda BE_RECORD+3
 sta BE_COUNT
 lda BE_RECORD+4
 sta BE_COUNT+1
@data:
 lda BE_COUNT
 ora BE_COUNT+1
 beq @blob_next
 lda BE_ADDR
 sta PTR
 lda BE_ADDR+1
 sta PTR+1
 ldy #0
 jsr read_ram
 COMMAND_CALL file_put
 jsr be_transfer_advance
 jmp @data
@blob_next:
 inc BE_INDEX
 lda BE_INDEX
 cmp #16
 bne @blob
@done:
 rts
be_clear_metadata:
 lda #0
 ldx #88
@first:
 sta $0200,x
 dex
 bpl @first
 ldx #79
@second:
 sta $02a7,x
 dex
 bpl @second
 lda #$b6
 sta BE_MAGIC
 rts
be_load_begin:
 lda MEM_IO
 bne @done
 lda #0
 sta BE_LOADING
 sta BE_VERSION
 sta ED_VIEW_VALID
 ldx #0
@first:
 lda $0200,x
 sta BE_LOAD_META,x
 inx
 cpx #89
 bne @first
 ldx #0
@second:
 lda $02a7,x
 sta BE_LOAD_META+89,x
 inx
 cpx #80
 bne @second
 lda FILE_NAME_LEN
 sta BE_LOAD_NAME_LEN
 lda FILE_DEVICE
 sta BE_LOAD_DEVICE
 ldx #0
@name:
 cpx FILE_NAME_LEN
 beq @clear
 lda BRIDGE,x
 sta BE_LOAD_NAME,x
 inx
 bne @name
@clear:
 jsr be_clear_metadata
 lda #1
 sta BE_LOADING
@done:
 rts
be_load_rollback:
 lda MEM_IO
 bne @done
 lda BE_LOADING
 beq @done
 ldx #0
@first:
 lda BE_LOAD_META,x
 sta $0200,x
 inx
 cpx #89
 bne @first
 ldx #0
@second:
 lda BE_LOAD_META+89,x
 sta $02a7,x
 inx
 cpx #80
 bne @second
 jmp be_release_backup
@done:
 rts
be_release_backup:
 lda #0
 sta BE_LOADING
@done:
 rts
be_read_reservations:
 lda BE_VERSION
 cmp #2
 JNE @done
 COMMAND_CALL file_get
 cmp #9
 JCS be_bad_file
 sta BE_RES_COUNT
 sta BE_FILE_RES_COUNT
 lda #0
 sta BE_RES_SEL
@res:
 lda BE_RES_SEL
 cmp BE_RES_COUNT
 beq @blobs
 COMMAND_CALL file_get
 sta BE_RANGE
 COMMAND_CALL file_get
 sta BE_RANGE+1
 COMMAND_CALL file_get
 sta BE_SIZE
 COMMAND_CALL file_get
 sta BE_SIZE+1
 COMMAND_CALL file_get
 cmp #2
 JCS be_bad_file
 sta BE_WORK+25
 cmp #0
 beq @claim
 lda BE_RANGE
 ora BE_SIZE
 JNE be_bad_file
@claim:
 jsr be_reserve_exact
 JCS be_load_claim_error
 lda BE_WORK+25
 beq @next
 lda BE_RES_SEL
 jsr be_bit
 ora BE_BASIC
 sta BE_BASIC
@next:
 inc BE_RES_SEL
 bne @res
@blobs:
 rts
@done:
 rts
be_read_metadata:
 lda BE_VERSION
 cmp #2
 JNE @done
@blobs:
 COMMAND_CALL file_get
 cmp #17
 JCS be_bad_file
 sta BE_BLOB_COUNT
 lda #0
 sta BE_BLOB_SEL
@blob:
 lda BE_BLOB_SEL
 cmp BE_BLOB_COUNT
 beq @done
 ldy #0
@record:
 COMMAND_CALL file_get
 sta BE_RECORD,y
 iny
 cpy #8
 bne @record
 lda BE_RECORD
 cmp BE_FILE_RES_COUNT
 JCS be_bad_file
 jsr be_validate_blob
 JCS be_load_claim_error
 jsr be_set_blob
 lda BE_RECORD+3
 sta BE_COUNT
 lda BE_RECORD+4
 sta BE_COUNT+1
 jsr be_skip_data
 inc BE_BLOB_SEL
 jmp @blob
@done:
 rts
be_skip_data:
 lda BE_COUNT
 ora BE_COUNT+1
 beq @done
 COMMAND_CALL file_get
 lda BE_COUNT
 bne :+
 dec BE_COUNT+1
:
 dec BE_COUNT
 jmp be_skip_data
@done:
 rts
be_skip_small:
 sta BE_COUNT
 lda #0
 sta BE_COUNT+1
 jmp be_skip_data
be_load_claim_error:
 COMMAND_CALL command_error
be_bad_file:
 lda #ERR_SYNTAX
 COMMAND_CALL command_error

be_load_finish:
 lda MEM_IO
 JNE @done
 lda BE_VERSION
 cmp #2
 JNE @release
 ; Re-read a validated source stream to restore bytes without requiring a
 ; second arena-sized buffer. Metadata/CRC are checked again before completion.
 lda FILE_CRC
 sta BE_WORK+22
 lda FILE_CRC+1
 sta BE_WORK+23
 jsr $ffcc
 lda #1
 jsr $ffc3
 lda BE_LOAD_NAME_LEN
 ldx #<BE_LOAD_NAME
 ldy #>BE_LOAD_NAME
 jsr $ffbd
 lda #1
 ldx BE_LOAD_DEVICE
 ldy #2
 jsr $ffba
 jsr $ffc0
 JCS be_bad_file
 ldx #1
 jsr $ffc6
 JCS be_bad_file
 lda #$ff
 sta FILE_CRC
 sta FILE_CRC+1
 lda #10
 jsr be_skip_small
 COMMAND_CALL file_get
 cmp BE_FILE_RES_COUNT
 JNE be_bad_file
 lda #0
 sta BE_RES_SEL
@res:
 lda BE_RES_SEL
 cmp BE_FILE_RES_COUNT
 beq @dictionary
 lda BE_RES_SEL
 jsr be_get_res
 COMMAND_CALL file_get
 cmp BE_RANGE
 JNE be_bad_file
 COMMAND_CALL file_get
 cmp BE_RANGE+1
 JNE be_bad_file
 COMMAND_CALL file_get
 cmp BE_SIZE
 JNE be_bad_file
 COMMAND_CALL file_get
 cmp BE_SIZE+1
 JNE be_bad_file
 COMMAND_CALL file_get
 sta BE_TEMP
 lda BE_RES_SEL
 jsr be_bit
 and BE_BASIC
 beq :+
 lda #1
:
 cmp BE_TEMP
 JNE be_bad_file
 inc BE_RES_SEL
 jmp @res
@dictionary:
 COMMAND_CALL file_get
 sta BE_WORK+20
 COMMAND_CALL file_get
 sta BE_WORK+21
@names:
 lda BE_WORK+20
 ora BE_WORK+21
 beq @lines
 COMMAND_CALL file_get
 jsr be_skip_small
 lda BE_WORK+20
 bne :+
 dec BE_WORK+21
:
 dec BE_WORK+20
 jmp @names
@lines:
 COMMAND_CALL file_get
 sta BE_TEMP
 COMMAND_CALL file_get
 cmp #$ff
 bne @tokens
 lda BE_TEMP
 cmp #$ff
 beq @blobs
@tokens:
 COMMAND_CALL file_get
 jsr be_skip_small
 jmp @lines
@blobs:
 COMMAND_CALL file_get
 cmp BE_BLOB_COUNT
 JNE be_bad_file
 lda #0
 sta BE_BLOB_SEL
@blob:
 lda BE_BLOB_SEL
 cmp BE_BLOB_COUNT
 beq @crc
 jsr be_get_blob
 ldy #0
@record:
 COMMAND_CALL file_get
 cmp BE_RECORD,y
 JNE be_bad_file
 iny
 cpy #8
 bne @record
 lda BE_RECORD+1
 sta BE_ADDR
 lda BE_RECORD+2
 sta BE_ADDR+1
 lda BE_RECORD+3
 sta BE_COUNT
 lda BE_RECORD+4
 sta BE_COUNT+1
@data:
 lda BE_COUNT
 ora BE_COUNT+1
 beq @next_blob
 COMMAND_CALL file_get
 pha
 lda BE_ADDR
 sta PTR
 lda BE_ADDR+1
 sta PTR+1
 ldy #0
 pla
 sta (PTR),y
 jsr be_transfer_advance
 jmp @data
@next_blob:
 inc BE_BLOB_SEL
 jmp @blob
@crc:
 lda FILE_CRC
 cmp BE_WORK+22
 JNE be_bad_file
 lda FILE_CRC+1
 cmp BE_WORK+23
 JNE be_bad_file
 COMMAND_CALL file_crc_get
 cmp FILE_CRC
 JNE be_bad_file
 COMMAND_CALL file_crc_get
 cmp FILE_CRC+1
 JNE be_bad_file
@release:
 jsr be_release_backup
@done:
 rts
