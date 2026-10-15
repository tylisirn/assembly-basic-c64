.setcpu "6502"
.include "memory.inc"
.import __GATEWAY_LOAD__, __GATEWAY_RUN__, __GATEWAY_SIZE__
.import __SERVICE_GATEWAY_LOAD__, __SERVICE_GATEWAY_RUN__, __SERVICE_GATEWAY_SIZE__
.import __COMPILER_LOAD__, __COMPILER_RUN__, __COMPILER_SIZE__
.import __RUNTIME_LOAD__, __RUNTIME_RUN__, __RUNTIME_SIZE__
.segment "HEADER"
.word cold_start, cartridge_warm
.byte $c3,$c2,$cd,$38,$30
.segment "COMMAND"
cold_start:
 sei
 cld
 ldx #$ff
 txs
 lda $00
 ora #7
 sta $00
 lda PORT
 ora #7
 sta PORT
 jsr $fda3 ; IOINIT
 jsr $fd50 ; RAMTAS
 jsr $fd15 ; RESTOR
 jsr $ff5b ; CINT
 sei
 lda #<__GATEWAY_LOAD__
 sta SOURCE
 lda #>__GATEWAY_LOAD__
 sta SOURCE+1
 lda #<__GATEWAY_RUN__
 sta DEST
 lda #>__GATEWAY_RUN__
 sta DEST+1
 lda #<__GATEWAY_SIZE__
 sta COUNT
 lda #>__GATEWAY_SIZE__
 sta COUNT+1
 jsr copy_image
 lda #<__SERVICE_GATEWAY_LOAD__
 sta SOURCE
 lda #>__SERVICE_GATEWAY_LOAD__
 sta SOURCE+1
 lda #<__SERVICE_GATEWAY_RUN__
 sta DEST
 lda #>__SERVICE_GATEWAY_RUN__
 sta DEST+1
 lda #<__SERVICE_GATEWAY_SIZE__
 sta COUNT
 lda #>__SERVICE_GATEWAY_SIZE__
 sta COUNT+1
 jsr copy_image
 jsr select_command_bank
 jsr load_runtime
 jsr load_compiler
 lda #<ram_nmi
 sta $fffa
 lda #>ram_nmi
 sta $fffb
 lda #<cold_start
 sta $fffc
 lda #>cold_start
 sta $fffd
 lda #<ram_irq
 sta $fffe
 lda #>ram_irq
 sta $ffff
 lda #<kernal_nmi
 sta $0318
 lda #>kernal_nmi
 sta $0319
 lda #0
 ldx #0
@clear:
 sta STATE,x
 inx
 bne @clear
 ldx #2
@clear_zero_page:
 sta $00,x
 inx
 cpx #$79
 bne @clear_zero_page
 jsr new_program
 lda #<banner
 ldx #>banner
 jsr rom_puts
 cli
warm_ready:
 cld
 ldx #$ff
 txs
 lda #0
 sta ERROR_CODE
 jmp ready
cartridge_warm:
 ; KERNAL cartridge NMI transfer has abandoned its original frame.
 sei
 lda PORT
 ora #7
 sta PORT
 jsr select_command_bank
 jmp warm_ready
copy_image:
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
rom_puts:
 sta PTR
 stx PTR+1
 ldy #0
@loop:
 lda (PTR),y
 beq @done
 sty NUM_LENGTH
 jsr $ffd2
 ldy NUM_LENGTH
 iny
 bne @loop
@done:
 rts
ready:
 ldx #$ff
 txs
 cld
 jsr $ffcc
 lda ED_ACTIVE
 bne @prompt
 lda ERROR_CODE
 beq @prompt
 jsr report_error
@prompt:
 lda ED_ACTIVE
 beq @stock
 lda ERROR_CODE
 EDITOR_CALL editor_finish
 lda ERROR_CODE
 beq @editor_input
 jsr report_error
@editor_input:
 lda #0
 sta ERROR_CODE
 sta PENDING
 jmp input_loop
@stock:
 lda #0
 sta ERROR_CODE
 sta PENDING
 lda #<ready_text
 ldx #>ready_text
 jsr rom_puts
input_loop:
 lda ED_ACTIVE
 beq @stock_read
 EDITOR_CALL editor_read
 jmp submit_input
@stock_read:
 lda #0
 sta INPUT_LEN
@read:
 jsr $ffcf
 cmp #13
 beq @line
 ldx INPUT_LEN
 cpx #80
 bcs @read
 sta INPUT_BUFFER,x
 inc INPUT_LEN
 jmp @read
@line:
 ; CHRIN returns the editor CR; send it to CHROUT before parsing/output.
 jsr $ffd2
submit_input:
 lda #0
 sta ERROR_CODE
 ldx INPUT_LEN
 lda #0
 sta INPUT_BUFFER,x
 sta INPUT_POS
 lda INPUT_LEN
 beq input_loop
 jsr skip_spaces
 jsr input_peek
 cmp #'0'
 bcc direct_command
 cmp #'9'+1
 bcs direct_command
 jsr read_decimal
 lda VALUE
 sta LINE_NO
 lda VALUE+1
 sta LINE_NO+1
 cmp #$fa
 bcs command_quantity
 lda LINE_NO
 sta ED_AFFECTED
 lda LINE_NO+1
 sta ED_AFFECTED+1
 jsr skip_spaces
 lda INPUT_POS
 cmp INPUT_LEN
 beq @delete
 jsr tokenize_input
 jsr edit_line
 lda COMPILE_ERROR
 beq @submitted
 sta ERROR_CODE
 lda ED_ACTIVE
 bne @submitted
 lda ERROR_CODE
 jsr report_error
@submitted:
 lda ED_ACTIVE
 beq @again
 lda ERROR_CODE
 EDITOR_CALL editor_finish
 lda ERROR_CODE
 beq @again
 jsr report_error
 lda #0
 sta ERROR_CODE
@again:
 jmp input_loop
@delete:
 jsr delete_line
 jmp @submitted
command_quantity:
 lda #ERR_QUANTITY
 jmp command_error
direct_command:
 EDITOR_CALL editor_check_command
 cmp #1
 JEQ command_basic
 cmp #2
 JEQ command_quit
 jsr tokenize_input
 ; Command-only statements are dispatched while stopped in ROM.
 lda TOKENS
 cmp #$2a
 beq command_run
 cmp #$3b
 JEQ command_list
 cmp #$43
 JEQ command_new
 cmp #$3a
 JEQ command_cont
 cmp #$3c
 JEQ command_clear
 cmp #$69
 JEQ command_clean
 lda #$ff
 sta LINE_NO
 sta LINE_NO+1
 lda #<DIRECT_ANCHOR
 sta ANCHOR
 lda #>DIRECT_ANCHOR
 sta ANCHOR+1
 lda #<direct_done
 sta SUCCESSOR
 lda #>direct_done
 sta SUCCESSOR+1
 jsr compile_payload
 lda NEW_PAYLOAD
 sta DIRECT_PAYLOAD
 lda NEW_PAYLOAD+1
 sta DIRECT_PAYLOAD+1
 jsr publish_anchor
 lda ANCHOR
 sta ENTRY
 lda ANCHOR+1
 sta ENTRY+1
 jmp run_entry
command_run:
 EDITOR_CALL editor_close
 jsr load_runtime
 jsr clear_values
 lda #0
 sta CONT_PC
 sta CONT_PC+1
 sta CONTROL_TOP
 sta CONTROL_TOP+1
 sta FROZEN_TOP
 sta FROZEN_TOP+1
 sta DATA_LINE
 sta DATA_LINE+1
 lda PROGRAM_HEAD
 sta ENTRY
 lda PROGRAM_HEAD+1
 sta ENTRY+1
 lda TOKEN_LEN
 cmp #1
 beq @go
 lda #1
 sta TOKEN_POS
 jsr parse_target
 lda TARGET
 sta ENTRY
 lda TARGET+1
 sta ENTRY+1
@go:
 lda #1
 sta RUNNING
 jmp run_entry
command_basic:
 EDITOR_CALL editor_open
 jmp input_loop
command_quit:
 EDITOR_CALL editor_close
 jmp ready
command_cont:
 lda CONT_PC
 ora CONT_PC+1
 beq @bad
 lda CONT_GEN
 cmp GENERATION
 bne @bad
 lda CONT_GEN+1
 cmp GENERATION+1
 bne @bad
 jsr load_runtime
 lda CONT_PC
 sta ENTRY
 lda CONT_PC+1
 sta ENTRY+1
 lda #0
 sta FROZEN_TOP
 sta FROZEN_TOP+1
 lda #1
 sta RUNNING
 jmp run_entry
@bad:
 lda #ERR_CONT
 jmp command_error
command_new:
 jsr new_program
 jmp ready
command_clear:
 jsr clear_values
 jmp ready
command_error:
 sta ERROR_CODE
 lda LOADING
 JNE load_fail
 lda MEM_IO
 JNE clean_fail
 jmp ready
.segment "COMMAND"
banner: .byte 147,"ASSEMBLY BASIC 0.15",13,0
ready_text: .byte 13,"READY.",13,0
error_table:
.word e_syntax,e_syntax,e_quantity,e_memory,e_divzero,e_undefined,e_return,e_next,e_type,e_cont,e_unsupported,e_stack,e_string,e_data
e_syntax: .byte "SYNTAX ERROR",0
e_quantity: .byte "ILLEGAL QUANTITY",0
e_memory: .byte "OUT OF MEMORY",0
e_divzero: .byte "DIVISION BY ZERO",0
e_undefined: .byte "UNDEF'D STATEMENT",0
e_return: .byte "RETURN WITHOUT GOSUB",0
e_next: .byte "NEXT WITHOUT FOR",0
e_type: .byte "TYPE MISMATCH",0
e_cont: .byte "CAN'T CONTINUE",0
e_unsupported: .byte "UNSUPPORTED FEATURE",0
e_stack: .byte "FORMULA TOO COMPLEX",0
e_string: .byte "STRING TOO LONG",0
e_data: .byte "OUT OF DATA",0
.include "gateway.s"
.include "editor.s"
.include "lexer.s"
.include "compiler.s"
.include "list.s"
.include "files.s"
.include "clean.s"
.segment "COMPILER"
new_program:
 lda #0
 sta RESERVE_COUNT
 sta NAME_HEAD
 sta NAME_HEAD+1
 sta ARRAY_HEAD
 sta ARRAY_HEAD+1
 sta FUNCTION_HEAD
 sta FUNCTION_HEAD+1
 sta FROZEN_TOP
 sta FROZEN_TOP+1
 sta NAME_COUNT
 sta NAME_COUNT+1
 sta SLAB_HEAD
 sta SLAB_HEAD+1
 sta CONT_PC
 sta CONT_PC+1
 sta DIRECT_PAYLOAD
 sta DIRECT_PAYLOAD+1
 lda #<run_end
 sta PROGRAM_HEAD
 lda #>run_end
 sta PROGRAM_HEAD+1
 lda #<USER_BASE
 sta FREE_HEAD
 lda #>USER_BASE
 sta FREE_HEAD+1
 lda #$00
 sta USER_BASE
 lda #>($d000-USER_BASE)
 sta USER_BASE+1
 lda #$00
 sta USER_BASE+2
 lda #$e0
 sta USER_BASE+3
 lda #$00
 sta $e000
 lda #$04
 sta $e001
 lda #0
 sta $e002
 sta $e003
 inc GENERATION
 bne :+
 inc GENERATION+1
:
 rts
clear_values:
 lda #<clear_runtime
 sta gateway_call+1
 lda #>clear_runtime
 sta gateway_call+2
 jmp call_ram

; Stopped command helpers share the resident compiler image in bank 1.
.segment "COMPILER"
report_error:
 pha
 lda #'?'
 jsr $ffd2
 pla
 asl
 tax
 lda error_table,x
 sta SCRATCH
 lda error_table+1,x
 tax
 lda SCRATCH
 jsr rom_puts
 lda #13
 jsr $ffd2
 rts
command_alloc_common:
 sta IO_A
 stx IO_X
 lda #<alloc_common
 sta gateway_call+1
 lda #>alloc_common
 sta gateway_call+2
 jsr call_ram
 jmp check_alloc
command_alloc:
 sta IO_A
 stx IO_X
 lda #<alloc
 sta gateway_call+1
 lda #>alloc
 sta gateway_call+2
 jsr call_ram
check_alloc:
 lda ALLOC_RESULT
 ora ALLOC_RESULT+1
 bne :+
 lda #ERR_MEMORY
 jmp command_error
:
 rts
command_free:
 lda #<free_block
 sta gateway_call+1
 lda #>free_block
 sta gateway_call+2
 jmp call_ram

.include "reserve.s"
.include "runtime.s"
.include "services.s"
.include "service_gateway.s"
.include "screen_editor.s"
.include "prg_import.s"

; Every auxiliary bank has a recovery header pointing into common RAM. This
; lets KERNAL cartridge NMI dispatch recover even during a banked image copy.
.repeat 7, I
.segment .sprintf("HEADER%d", I+1)
.word bank_cold, bank_warm
.byte $c3,$c2,$cd,$38,$30
.endrepeat
.segment "COMMAND"
load_compiler:
 lda #<__COMPILER_LOAD__
 sta SOURCE
 lda #>__COMPILER_LOAD__
 sta SOURCE+1
 lda #<__COMPILER_RUN__
 sta DEST
 lda #>__COMPILER_RUN__
 sta DEST+1
 lda #<__COMPILER_SIZE__
 sta COUNT
 lda #>__COMPILER_SIZE__
 sta COUNT+1
 lda #BANK_COMPILER
 jmp copy_bank_image
load_runtime:
 lda #<__RUNTIME_LOAD__
 sta SOURCE
 lda #>__RUNTIME_LOAD__
 sta SOURCE+1
 lda #<__RUNTIME_RUN__
 sta DEST
 lda #>__RUNTIME_RUN__
 sta DEST+1
 lda #<__RUNTIME_SIZE__
 sta COUNT
 lda #>__RUNTIME_SIZE__
 sta COUNT+1
 lda #BANK_RUNTIME
 jmp copy_bank_image
