.segment "SERVICE_GATEWAY"
; Stable common-RAM entry stubs for banked ROM services.
restore_data:
 jsr bank_call
 .byte BANK_SERVICES,7
 .word rom_restore_data
 rts
read_number:
 jsr bank_call
 .byte BANK_SERVICES,7
 .word rom_read_number
 rts
read_string:
 jsr bank_call
 .byte BANK_SERVICES,7
 .word rom_read_string
 rts
activate_function:
 ; Preserve the original four inline operand bytes used by compiled DEF FN.
 sta FRAME_PC
 stx FRAME_PC+1
 pla
 sta SOURCE
 pla
 sta SOURCE+1
 jsr bank_call
 .byte BANK_SERVICES,7
 .word rom_activate_function
 jmp (ENTRY)
file_word:
 jsr bank_call
 .byte BANK_SERVICES,7
 .word rom_file_word
 rts
open_word:
 jsr bank_call
 .byte BANK_SERVICES,7
 .word rom_open_word
 rts
close_word:
 jsr bank_call
 .byte BANK_SERVICES,7
 .word rom_close_word
 rts
output_channel:
 jsr bank_call
 .byte BANK_SERVICES,7
 .word rom_output_channel
 rts
input_channel:
 jsr bank_call
 .byte BANK_SERVICES,7
 .word rom_input_channel
 rts
reset_channel:
 jsr bank_call
 .byte BANK_SERVICES,7
 .word rom_reset_channel
 rts
input_prompt:
 jsr bank_call
 .byte BANK_SERVICES,7
 .word rom_input_prompt
 rts
get_number:
 jsr bank_call
 .byte BANK_SERVICES,7
 .word rom_get_number
 rts
input_field:
 jsr bank_call
 .byte BANK_SERVICES,7
 .word rom_input_field
 rts

; CHROUT's RAM vector must enter common RAM before changing cartridge banks.
; Device output continues through the original KERNAL vector.
editor_output_gate:
 pha
 lda $9a
 cmp #3
 beq @screen
 pla
 jmp (ED_OLD_OUT)
@screen:
 pla
 php
 pha
 txa
 pha
 tya
 pha
 tsx
 lda $0103,x
 EDITOR_CALL editor_output
 pla
 tay
 pla
 tax
 pla
 plp
 rts
