.segment "GATEWAY"
; All instructions that alter $01 and all mapped service return PCs live here.
; Runtime may select a KERNAL vector by patching service_call+1/+2.
bank_call:
 ; The caller's descriptor is read in its original map, before any bank write.
 ; Only setup/return use shared scratch; each live call owns its stack frame.
 php
 sei
 cld ; Descriptor/return-address arithmetic is binary even for SYS callers.
 sta IO_A
 stx IO_X
 sty IO_Y
 pla
 sta IO_STATUS
 pla
 sta bank_descriptor+1
 pla
 sta bank_descriptor+2
 clc
 lda bank_descriptor+1
 adc #4
 sta IO_MAP
 lda bank_descriptor+2
 adc #0
 pha
 lda IO_MAP
 pha
 lda IO_STATUS
 pha
 lda PORT
 pha
 lda CART_BANK
 pha
 ldy #2
 jsr bank_descriptor
 sta GATE_FLAGS
 ldy #3
 jsr bank_descriptor
 sec
 sbc #1
 sta IO_MAP
 iny
 jsr bank_descriptor
 sbc #0
 sta bank_target+1
 lda IO_MAP
 sta bank_target
 ldy #1
 jsr bank_descriptor
 sta IO_MAP
 lda PORT
 ora #7
 sta PORT
 lda IO_MAP
 cmp #$ff
 beq @bank_ready
 sta CART_BANK
 sta CART_REGISTER
@bank_ready:
 lda PORT
 and #$f8
 ora GATE_FLAGS
 sta PORT
 ; Stack an RTS target, avoiding a mutable dispatch operand after IRQ enable.
 lda #>(bank_return-1)
 pha
 lda #<(bank_return-1)
 pha
 lda bank_target+1
 pha
 lda bank_target
 pha
 lda IO_STATUS
 and #$f7
 pha
 lda IO_A
 ldx IO_X
 ldy IO_Y
 plp
 rts
bank_descriptor:
 lda $ffff,y
 rts
bank_target:
 .word 0 ; Target minus one, staged only while IRQs are masked.
bank_return:
 php
 sei
 sta IO_A
 stx IO_X
 sty IO_Y
 pla
 sta IO_STATUS
 lda PORT
 ora #7
 sta PORT
 pla
 sta CART_BANK
 sta CART_REGISTER
 pla
 sta PORT
 pla
 and #4
 sta GATE_FLAGS
 lda IO_STATUS
 and #$f3
 ora GATE_FLAGS
 pha
 lda IO_A
 ldx IO_X
 ldy IO_Y
 plp
 rts

kernal_gate:
 jsr bank_call
 .byte BANK_COMMAND,7
 .word service_call
 rts
service_call:
 jmp $ffd2
; Read a byte from shadow RAM without returning into hidden cartridge code.
read_ram:
 php
 sei
 lda PORT
 and #7
 pha
 lda PORT
 and #$f8
 ora #5
 sta PORT
 lda (PTR),y
 sta STATE+151
 pla
 sta IO_MAP
 lda PORT
 and #$f8
 ora IO_MAP
 sta PORT
 plp
 lda STATE+151
 rts
; Call a RAM helper from command ROM; callee address is gateway_call operand.
call_ram:
 lda IO_A
 ldx IO_X
 RAM_CALL gateway_call
 sta IO_A
 stx IO_X
 rts
gateway_call:
 jmp alloc
run_entry:
 sei
 lda PORT
 and #$f8
 ora #5
 sta PORT
 lda #0
 sta EXPR_TOP
 cld
 cli
 jmp (ENTRY)
enter_ready:
 sei
 lda PORT
 ora #7
 sta PORT
 jsr select_command_bank
 lda #0
 sta RUNNING
 cld
 cli
 jmp ready
; IRQ: retain the original hardware frame, synthesize a KERNAL return frame.
ram_irq:
 pha
 txa
 pha
 tya
 pha
 tsx
 lda $0104,x ; hardware P: BRK is bit 4
 and #$10
 bne @brk
 lda PORT
 and #7
 pha
 lda CART_BANK
 pha
 lda PORT
 ora #7
 sta PORT
 jsr select_command_bank
 lda #>irq_complete
 pha
 lda #<irq_complete
 pha
 lda #$24 ; I set, D/BRK clear
 pha
 lda #0 ; register values immaterial to stock housekeeping
 pha
 pha
 pha
 jmp ($0314)
@brk:
 lda #1
 sta PENDING
 pla
 tay
 pla
 tax
 pla
 rti
irq_complete:
 pla
 sta CART_BANK
 sta CART_REGISTER
 pla
 sta IO_MAP
 lda PORT
 and #$f8
 ora IO_MAP
 sta PORT
 pla
 tay
 pla
 tax
 pla
 rti
ram_nmi:
 pha
 txa
 pha
 tya
 pha
 lda $dd0d
 lda #1
 sta PENDING
 pla
 tay
 pla
 tax
 pla
 rti
kernal_nmi:
 ; Stock $fe43 reaches $0318 before saving registers (raw hardware frame).
 jmp ram_nmi
sys_return:
 sei
 lda PORT
 and #$f8
 ora #5
 sta PORT
 jsr select_command_bank
 cld
 cli
 rts
file_entry:
 jsr bank_call
 .byte BANK_COMMAND,7
 .word file_command
 rts

sys_gateway:
 lda $030f
 pha
 plp
 lda $030c
 ldx $030d
 ldy $030e
sys_call:
 jsr $ffff
 sta $030c
 stx $030d
 sty $030e
 php
 pla
 sta $030f
 jmp sys_return
usr_gateway:
 sta IO_A
 lda $0311
 sta usr_call+1
 lda $0312
 sta usr_call+2
 lda IO_A
usr_call:
 jsr $ffff
 sta IO_A
 stx IO_X
 sei
 lda PORT
 and #$f8
 ora #5
 sta PORT
 jsr select_command_bank
 cld
 cli
 lda IO_A
 ldx IO_X
 rts

; These routines must remain in common RAM: selecting a bank replaces $8000.
select_command_bank:
 lda #BANK_COMMAND
 sta CART_BANK
 sta CART_REGISTER
 rts
bank_cold:
 sei
 jsr recovery_map
 jmp cold_start
bank_warm:
 sei
 jsr recovery_map
 jmp cartridge_warm
recovery_map:
 lda PORT
 ora #7
 sta PORT
 jmp select_command_bank

; A = source bank; SOURCE/DEST/COUNT describe its raw fixed-address image.
; Preserve bank, full $01 and interrupt flags before returning to the caller.
copy_bank_image:
 ; Reuse the call ABI for map/bank ownership; the copy itself masks IRQs.
 php
 sei
 sta copy_bank_descriptor
 jsr bank_call
copy_bank_descriptor:
 .byte 0,7
 .word copy_image_ram
 plp
 rts
copy_image_ram:
 ldy #0
@loop:
 lda COUNT
 ora COUNT+1
 beq @done
 lda (SOURCE),y
 sta (DEST),y
 inc SOURCE
 bne :+
 inc SOURCE+1
:
 inc DEST
 bne :+
 inc DEST+1
:
 lda COUNT
 bne :+
 dec COUNT+1
:
 dec COUNT
 jmp @loop
@done:
 rts

; Keyboard CHRIN uses the bounded editor during a direct INPUT statement.
; Files and redirected devices retain the original KERNAL input vector.
editor_input_gate:
 lda $99
 beq @keyboard
 jmp (ED_OLD_IN)
@keyboard:
 EDITOR_CALL editor_chrin
 rts
