.segment "GATEWAY"
; All instructions that alter $01 and all mapped service return PCs live here.
; Runtime may select a KERNAL vector by patching service_call+1/+2.
kernal_gate:
 sta IO_A
 stx IO_X
 sty IO_Y
 php
 pla
 sta IO_STATUS
 sta GATE_FLAGS
 sei
 lda CART_BANK
 pha
 lda PORT
 and #7
 sta IO_MAP
 lda PORT
 ora #7
 sta PORT
 jsr select_command_bank
 lda IO_STATUS
 pha
 plp
 lda IO_A
 ldx IO_X
 ldy IO_Y
service_call:
 jsr $ffd2
 sta IO_A
 stx IO_X
 sty IO_Y
 php
 pla
 sta IO_STATUS
 sei
 pla
 sta CART_BANK
 sta CART_REGISTER
 lda PORT
 and #$f8
 ora IO_MAP
 sta PORT
 lda IO_STATUS
 and #$f3
 sta IO_STATUS
 lda GATE_FLAGS
 and #4
 ora IO_STATUS
 pha
 lda IO_A
 ldx IO_X
 ldy IO_Y
 plp
 cld
 rts
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
 lda STATE+151
 plp
 rts
; Call a RAM helper from command ROM; callee address is gateway_call operand.
call_ram:
 php
 sei
 lda PORT
 and #7
 pha
 lda PORT
 and #$f8
 ora #5
 sta PORT
 lda IO_A
 ldx IO_X
 cli
gateway_call:
 jsr alloc
 sta IO_A
 stx IO_X
 sei
 pla
 sta IO_MAP
 lda PORT
 and #$f8
 ora IO_MAP
 sta PORT
 plp
 lda IO_A
 ldx IO_X
 rts
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
 sei
 lda PORT
 ora #7
 sta PORT
 jsr select_command_bank
 cld
 cli
 jsr file_command
 sei
 lda PORT
 and #$f8
 ora #5
 sta PORT
 cld
 cli
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
 php
 sei
 pha
 lda PORT
 pha
 lda CART_BANK
 pha
 lda PORT
 ora #7
 sta PORT
 tsx
 lda $0103,x
 sta CART_BANK
 sta CART_REGISTER
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
 pla
 sta CART_BANK
 sta CART_REGISTER
 pla
 sta PORT
 pla
 plp
 rts
