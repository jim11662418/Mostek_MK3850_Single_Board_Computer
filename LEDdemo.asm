            PAGE 0               ;  suppress page headings in ASW listing file
            cpu MK3850
;========================================================================
; a simple application used to demonstrate the hex file download function
;========================================================================

; port address
serialport  equ 00H 
LEDport     equ 01H    

; scratchpad RAM
delaycnt    equ 07H              ; scratchpad RAM
loopcnt     equ 08H              ; scratchpad RAM

            org 8000H

; since the outputs of port 4 are open drain, writing '1' to a port 4 output port pin
; results in a '0' at that output port pin. the cathodes of the LEDs are connected to
; the output pins of port 4, therefore, outputing '1' pulls the cathode low and turns
; the LED on. outputing '0' turns the LED off.

start:      clr
            outs LEDport
            outs serialport

loop:       ins LEDport
            inc
            outs LEDport         ; output A to port 0
            li 100
            lr delaycnt,A
            pi delay             ; delay 100*10 mSec
            br loop

;------------------------------------------------------------------------
; delay = 10 mSec times the number in 'delaycnt'
;------------------------------------------------------------------------
delay:      clr                  ;   1 cycle
            lr loopcnt,A         ;   2 cycles
            
delay1:     in 0FFH              ;     4 cycles
            in 0FFH              ;     4 cycles
            in 0FFH              ;     4 cycles
            in 0FFH              ;     4 cycles            
            nop                  ;     1 cycles
            ds loopcnt           ;     1.5 cycles
            bnz delay1           ;     3.5 cycles
            
            ds delaycnt          ;   1.5 cycles
            bnz delay            ;   3.5 cycles
            
            pop                  ; 2 cycles

            end start
