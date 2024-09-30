            PAGE 0               ;  suppress page headings in ASW listing file
            cpu MK3850

;========================================================================
; serial communications demos for the MK3850 SBC.
; N-8-1 at 9600 bps. uses port0.0 to transmit. port0.7 to receive.
; with a 2MHz crystal, at 9600 bps one bit time is 104.17 µsec or 52 cycles.
;========================================================================
            
serialport  equ 00H 
ledport     equ 01H           

; scratchpad RAM
bitcount    equ 06H
txdata      equ 07H        ; transmit buffer in scratchpad RAM
rxdata      equ 07H        ; receive buffer in scratchpad RAM
testchar    equ 08H

            org 0000H
            
            clr
            outs ledport
            outs serialport


            
; test the 'putc' function by printing all the printable characters 20-7EH
tst_putc:   li 1FH
            lr testchar,A
tst_putc1:  lr A,testchar
            inc
            ci 126
            bnz tst_putc2
            li 0DH
            lr txdata,A
            pi putc
            li 1FH
            lr testchar,A
            br tst_putc1
            
tst_putc2:  lr testchar,A
            lr txdata,A            
            pi putc
            br tst_putc1

; test the 'getce' function            
tst_getce:  pi getce
            pi putc        ; echo what we received
            br tst_getce
            
; test the 'getc' function            
tst_getc:   pi getc
            pi putc        ; echo what we received
            br tst_getc
            
;-----------------------------------------------------------------------------------
; waits for a character from the serial port. does not echo. saves character in 'rxdata'
;-----------------------------------------------------------------------------------         
getc:       lis 8
            lr bitcount,A
                              ; cycles
getc1:      ins serialport    ; 2      wait for the start bit
            bp getc1          ; 3
            li 242            ; 65     wait 1 bit time
            inc
            bnz $-1
getc2:      lr A,rxdata       ; 1      get 8 data bits      
            sr 1              ; 1
            lr rxdata,A       ; 1
            
            ins serialport    ; 2      read the serial input
            ins serialport    ; 2
            com               ; 1
            ni 80H            ; 2.5
            as rxdata         ; 1
            lr rxdata,A       ; 1
            li 249            ; 33.5
            inc
            bnz $-1
            nop               ; 1
            ds bitcount       ; 1.5
            bnz getc2         ; 3.5
            li 246            ; 47     wait 1 bit time for the stop bit
            inc
            bnz $-1
            pop
            
;-----------------------------------------------------------------------------------
; waits for a character from the serial port. echos the character bit by bit.
; saves character in 'rxdata'
;-----------------------------------------------------------------------------------
getce:      lis 8
            lr bitcount,A
                              ; cycles   
getce1:     ins serialport    ; 2
            bp getce1         ; 3
            
            li 253            ; 15.5   wait 1/2 bit time
            inc
            bnz $-1            
            li 01H            ; 2.5
            outs serialport   ; 2      send the start bit
            nop               ; 1
            nop               ; 1
            li 248            ; 38     wait 1 bit time
            inc
            bnz $-1            
getce2:     lr A,rxdata       ; 1      get 8 data bits      
            sr 1              ; 1
            lr rxdata,A       ; 1
            
            ins serialport    ; 2      read the serial input
            sr 4              ; 1
            sr 1              ; 1
            sr 1              ; 1
            sr 1              ; 1
            outs serialport   ; 2      echo the bit
            sl 1              ; 1
            sl 1              ; 1
            sl 1              ; 1
            sl 4              ; 1
            com               ; 1
            ni 80H            ; 2.5
            as rxdata         ; 1
            lr rxdata,A       ; 1
            nop               ; 1
            nop               ; 1
            li 251            ; 24.5
            inc
            bnz $-1                   
            ds bitcount       ; 1.5
            bnz getce2        ; 3.5

            li 255            ; 6.5
            inc
            bnz $-1
            nop               ; 1
            li 00H            ; 2.5
            outs serialport   ; 2      send stop bit
            li 240            ; 74     wait 1.5 bit time
            inc
            bnz $-1
            pop

;-----------------------------------------------------------------------------------
; transmit the character in 'txdata' through the serial port
;-----------------------------------------------------------------------------------
putc:       lis 8
            lr bitcount,A
            li 01H
                              ; cycles
            outs serialport   ; 2      send the start bit
            outs serialport   ; 2
            outs serialport   ; 2
            li 247            ; 42.5
            inc
            bnz $-1
putc1:      lr A,txdata       ; 1      send 8 data bits
            com               ; 1
            ni 01H            ; 2.5
            outs serialport   ; 2
            li 248            ; 38
            inc
            bnz $-1
            lr A,txdata       ; 1
            sr 1              ; 1
            lr txdata,A       ; 1
            ds bitcount       ; 1.5
            bnz putc1         ; 3.5
            lr A,bitcount     ; 1
            nop               ; 1   
            nop               ; 1
            nop               ; 1
            outs serialport   ; 2      send the stop bit
            li 247            ; 47     wait 1 bit time
            inc
            bnz $-1
            pop

            end