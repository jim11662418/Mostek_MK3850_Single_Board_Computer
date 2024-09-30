            page 0        ;  suppress page headings in listing file
            cpu MK3850
;=========================================================================
; Monitor firmware for the MK3850 Single Board Computer.
;
; Requires the use of a terminal emulator connected to the SBC
; set for 9600 bps, 8 data bits, no parity, 1 stop bit.
;
; functions:
;  - display main memory
;  - examine/modify main memory
;  - download Intel hex file
;  - input from an I/O port
;  - jump to main memory address
;  - output to an I/O port
;  - display scratchpad memory
;  - display uptime
;  - examine/modify scratchpad memory
;
; assemble with Macro Assembler AS V1.42 http://john.ccac.rwth-aachen.de:8000/as/
;=========================================================================
            include "bitfuncs.inc" 

; constants
ESCAPE      equ 1BH
ENTER       equ 0DH

; VT100 Escape sequences
CLS         equ "\e[2J\e[H"   ; clear screen and home cursor
SGR0        equ "\e[0m"       ; turn off character attributes
SGR1        equ "\e[1m"       ; turn bold mode on
SGR2        equ "\e[2m"       ; turn low intensity mode on
SGR4        equ "\e[4m"       ; turn underline mode on
SGR5        equ "\e[5m"       ; turn blinking mode on
SGR7        equ "\e[7m"       ; turn reverse video on

; port addresses
serialport  equ 00H           ; 3850 CPU port 0
LEDport     equ 01H           ; 3850 CPU port 1
intVectorHi equ 0CH           ; 3853 SMI interrupt vector address upper byte
intVectorLo equ 0DH           ; 3853 SMI interrupt vector address lower byte
intControl  equ 0EH           ; 3853 SMI interrupt control port
timer       equ 0FH           ; 3853 SMI timer port

; registers
bitcount    equ 01H
saveA       equ 02H
saveIS      equ 03H
hexbyte     equ 04H
number      equ 04H
errors      equ 04H
portaddr    equ 05H
bytecnt     equ 05H
checksum    equ 05H
digit       equ 05H
zeroflag    equ 06H
portval     equ 06H
linecnt     equ 06H
recordlen   equ 06H
rxbuffer    equ 07H
txbuffer    equ 08H

; scratchpad RAM addresses
intCounter  equ 38H
seconds     equ 39H
minutes     equ 3AH
hours       equ 3BH

; executable RAM addresses
patch       equ 0FF80H

            org 0000H
;=======================================================================
; reset vector
;=======================================================================
init:       clr
            outs LEDport      ; turn off yellow LEDs
            outs serialport   ; set serial input and output lines high (idle or MARK)

            li intCounter
            lr IS,A
            li 254
            lr I,A            ; preset interrupt counter
            clr
            lr I,A            ; reset seconds
            lr I,A            ; reset minutes
            lr I,A            ; reset hours

            ; from p.3-62 of the Fairchild "Microprocessor Products Data Book":
            ; "Even though the SMI interrupt address vector is programmable, bit 7 is still set
            ; to 0 for a timer interrupt, or to 1 for an external interrupt."
            li hi(timerisr)
            outs intVectorHi  ; interrupt address vector upper byte    
            li lo(timerisr)
            outs intVectorLo  ; interrupt address vector lower byte
            li 0FEH           ; 254 counts to interrupt (from Table 3 on p.3-42 of Fairchild Microprocessor Products Data Book)
            outs timer        ; timer/counter port
            li 03H            ; enable timer interrupt
            outs intControl   ; interrupt control port
            ei
            
;=======================================================================
; monitor starts here
;=======================================================================            
monitor:    dci titletxt
            pi putstr         ; print the title
monitor1:   dci menutxt
            pi putstr         ; print the menu
monitor2:   dci prompttxt
            pi putstr         ; print the input prompt
monitor3:   ins serialport    ; loop here until there is a character available at the serial port
            bp monitor3
            pi getc1          ; get the command character waiting at the serial port
            lr A,rxbuffer     ; retrieve the character from the rx buffer
            ci 'a'-1
            bc monitor4       ; branch if character is < 'a'
            ci 'z'
            bnc monitor4      ; branch if character is > 'z'
            ai -20H           ; else, subtract 20H to convert lowercase to uppercase
            lr rxbuffer,A     ; save the command in 'rxbuffer'

monitor4:   dci cmdtable
monitor5:   lr A,rxbuffer     ; get the command from the rx buffer
            cm                ; compare the command from the rx buffer to the entry from the table, increment DC
            bz monitor6       ; branch if a match found
            lm                ; load hi byte of address. increment DC
            lm                ; load lo byte of address. increment DC
            lm                ; load next command from the table
            ci 0              ; is it zero?
            bz monitor1       ; end of table found. go display menu
            li -1
            adc               ; else decrement DC
            br monitor5       ; go try the next table entry

monitor6:   lm                ; load hi byte of address from 'cmdtable' into A, increment DC
            lr QU,A           ; load hi byte of address from A into QU
            lm                ; load lo byte of address from 'cmdtable' into A
            lr QL,A           ; load lo byte of address from A into QL
            lr P0,Q           ; jump to address from 'cmdtable'

cmdtable    db 'D'
            dw display
            db 'E'
            dw examine
            db 'H'
            dw dnload
            db 'I'
            dw input
            db 'J'
            dw jump
            db 'O'
            dw output
            db 'S'
            dw scratch            
            db 'U'
            dw uptime
            db 'X'
            dw xamine
            db ':'
            dw dnload
            db 0              ; end of table

            org 0100H         ; interrupt vector
;--------------------------------------------------------------------------
; timer interrupt service routine:
; 1. save Status Register, Accumulator and ISAR
; 2. decrement interrupt counter.
; 3. when interrupt counter reaches zero, update seconds, minutes, hours and flash the LEDs.
; 4. restore ISAR, Accumulator and Status Register.
; 5. return from interrupt.
;--------------------------------------------------------------------------
; interrupts occur every 500 nSec * 254 counts * 31 (every 3.937 mSec)
timerisr:   lr J,W            ; save status
            lr saveA,A        ; save accumulator
            lr A,IS
            lr saveIS,A       ; save ISAR

            li intCounter
            lr IS,A
            ds S              ; decrement interrupt counter
            bnz timerisr2
            li 254
            lr I,A            ; preset the interrupt counter

; 3.937 mSec * 254 counts = 999,998 mSec
            lr A,S            ; load seconds
            inc               ; increment seconds
            lr S,A
            ci 60             ; 60 seconds?
            bnz timerisr1     ; branch if not yet 60 seconds
            clr
            lr I,A            ; reset seconds

            lr A,S            ; load minutes
            inc               ; increment minutes
            lr S,A
            ci 60             ; 60 seconds?
            bnz timerisr1     ; branch if not yet 60 minutes
            clr
            lr I,A            ; reset minutes

            lr A,S            ; load hours
            inc               ; increment hours
            lr S,A

; flash the LEDs connected to port 1 each second to show visually that it's working
timerisr1:  ins LEDport
            inc
            outs LEDport      ; flash the LEDs every second

; restore registers and exit isr
timerisr2:  lr A,saveIS
            lr IS,A           ; restore ISAR
            lr A,saveA        ; restore accumulator
            lr W,J            ; restore status register
            ei                ; re-enable interrupts
            pop               ; return from interrupt
            
;=======================================================================
; print the uptime as HH:MM:SS
;=======================================================================
uptime:     pi newline
            pi newline

            li hours          ; address of 'hours' in scratchpad RAM
            lr IS,A
            lr A,D
            lr number,A
            pi printtime      ; print the hours
            li ':'
            lr txbuffer,A
            pi putc           ; print ':'

            lr A,D
            lr number,A
            pi printtime      ; print the minutes
            li ':'
            lr txbuffer,A
            pi putc           ; print ':'

            lr A,S
            lr number,A
            pi printtime      ; print the seconds

            pi newline
            jmp monitor2
            
;=======================================================================
; display the contents of one page of memory in hex and ASCII
;=======================================================================
display:    dci addresstxt
            pi putstr         ; print the string  to prompt for RAM address
            pi get4hex        ; get the starting address
            bnc display1      ; branch if not ESCAPE
            jmp monitor2      ; else, return to menu

display1:   dci columntxt
            pi putstr
            lr DC,H           ; move the address from the 'get4hex' function into DC
            li 16
            lr linecnt,A      ; 16 lines

; print the address at the start of the line
display2:   lr H,DC           ; save DC in H
            lr A,HU           ; load HU into A
            lr hexbyte,A      ; save it in 'hexbyte' for the 'print2hex' function
            pi print2hex      ; print the most significant byte of the address
            lr A,HL           ; load HL into A
            lr hexbyte,A      ; save it in 'hexbyte' for the 'print2hex' function
            pi print2hex      ; print the least significant byte of the address
            li '-'
            lr txbuffer,A
            pi putc           ; print '-' between address and first byte

; print 16 hex bytes
            li 16
            lr bytecnt,A      ; 16 hex bytes on a line
display3:   lm                ; load the byte from memory into A, increment DC
            lr hexbyte,A      ; save it in 'hexbyte' for the 'print2hex' function
            pi print2hex      ; print the data byte at that address
            pi space          ; print a space between bytes
            ds bytecnt
            bnz display3      ; loop until all 16 bytes are printed

; print 16 ascii characters
            lr DC,H           ; recall the address from H
            li 16
            lr bytecnt,A      ; 16 characters on a line
display4:   lm                ; load the byte from memory into A, increment A
            ci 7FH
            bnc display5      ; branch if character is > 7FH
            ci 1FH
            bnc display6      ; branch if character is > 1FH
display5:   li '.'            ; print '.' for bytes 00-1FH and 7H-FFH
display6:   lr txbuffer,A     ; store the character in 'txbuffer' for the 'putc' function
            pi putc           ; print the character
            ds bytecnt
            bnz display4      ; loop until all 16 characters are printed

; finished with this line
            pi newline
            ds linecnt
            bnz display2      ; loop until all 16 lines are printedgo do next line
            pi newline        ; start on a new line
            jmp monitor2

;=======================================================================
; examine/modify memory contents.
; 1. prompt for a memory address.
; 2. display the contents of that memory address
; 3. wait for entry of a new value to be stored at that memory address.
; 4. ENTER key leaves memory unchanged, increments to next memory address.
; 5. ESCAPE key exits.
;=======================================================================
examine:    dci addresstxt
            pi putstr         ; print the string  to prompt for RAM address
            pi get4hex        ; get the RAM address
            bnc examine2      ; branch if not ESCAPE key
            jmp monitor2      ; else, return to monitor
examine2:   pi newline
            lr DC,H           ; move the address from the 'get4hex' function into DC

; print the address
examine3:   lr H,DC           ; save DC in H
            lr A,HU           ; load HU into A
            lr hexbyte,A      ; save it in 'hexbyte' for the 'print2hex' function
            pi print2hex      ; print the most significant byte of the address
            lr A,HL           ; load HL into A
            lr hexbyte,A      ; save it in 'hexbyte' for the 'print2hex' function
            pi print2hex      ; print the least significant byte of the address
            pi space

; get the byte from memory
            lr H,DC           ; save DC in H
            lm                ; load the byte from memory into A, increment DC
            lr hexbyte,A      ; save it in 'hexbyte' for the 'print2hex' function
            pi print2hex      ; print the data byte at that address
            pi space          ; print a space
            lr DC,H           ; restore DC

; get a new value to store in memory
            pi get2hex        ; get a new new data byte
            lr A,rxbuffer     ; load the byte from the 'get2hex' function into A
            bnc examine4      ; branch if the byte from 'het2hex' is not a control character
            ci ENTER          ; was the input ENTER?
            lr A,hexbyte      ; recall the original value stored at this memory address
            bz examine4       ; branch if the input was ENTER
            jmp monitor2      ; if not ENTER, the input must have been ESCAPE so return to monitor

; store the byte in memory
examine4:   st                ; store the byte in RAM, increment DC
            pi newline
            br examine3

;=======================================================================
; Download Intel HEX file into Executable RAM.
; A record (line of text) consists of six fields that appear in order from left to right:
;   1. Start code, one character, an ASCII colon ':'.
;   2. Byte count, two hex digits, indicating the number of bytes in the data field.
;   3. Address, four hex digits, representing the 16-bit beginning memory address offset of the data.
;   4. Record type, two hex digits (00=data, 01=end of file), defining the meaning of the data field.
;   5. Data, a sequence of n bytes of data, represented by 2n hex digits.
;   6. Checksum, two hex digits, a computed value (starting with the byte count) used to verify record data.
;------------------------------------------------------------------------
; waits for the start of record character ':'. ESCAPE returns to menu
; '.' is printed for each record that is downloaded successfully with no checksum errors.
; 'E' is printed for each record where a checksum error occurs.
;
; when the download is complete, if there are no checksum errors,
; jump to the address contained in the last record.
;
; Note: when using Teraterm to "send" a hex file, make sure that Teraterm
; is configured for a transmit delay of 1 msec/char and 10 msec/line.
;=======================================================================
dnload:     clr
            lr errors,A       ; clear the checksum error count
            lr A,rxbuffer     ; retrieve the command from 'rxbuffer'
            ci ':'            ; was the command that invoked this function ':'?
            bz dnload3        ; if so, the start character was already received. skip ahead
            dci waitingtxt
            pi putstr         ; else, prompt for the HEX download
dnload1:    ins serialport    ; loop here until there is a character available at the serial port
            bp dnload1
            pi getc1          ; get the character waiting at the serial port
            lr A,rxbuffer     ; retrieve the character from the rx buffer
            ci ESCAPE         ; is it ESCAPE?
            bnz dnload2       ; not escape, continue below
            jmp monitor2      ; jump back to the menu if ESCAPE

dnload2:    ci ':'            ; is the character the start of record character ':'?
            bnz dnload1       ; if not, go back for another character

; start of record character ':' has been received, now get the record length
dnload3:    pi getbyte        ; get the record length
            lr A,rxbuffer
            ci 0              ; is the record length zero?
            bz dnload6        ; branch if the record length is zero (last record)
            lr recordlen,A    ; else, save the record length
            lr checksum,A     ; add it to the checksum

; get the address hi byte
            pi getbyte
            lr A,rxbuffer
            lr HU,A
            as checksum
            lr checksum,A

; get the address lo byte
            pi getbyte
            lr A,rxbuffer
            lr HL,A
            as checksum
            lr checksum,A
            lr DC,H           ; load the record address into DC

; get the record type
            pi getbyte        ; get the record type
            lr A,rxbuffer
            as checksum
            lr checksum,A

; download and store data bytes...
dnload4:    pi getbyte        ; get a data byte
            lr A,rxbuffer
            st                ; store the data byte in memory [DC]. increment DC
            as checksum
            lr checksum,A
            ds recordlen
            bnz dnload4       ; loop back until all data bytes for this record have been received

; since the record's checksum byte is the two's complement and therefore the additive inverse
; of the data checksum, the verification process can be reduced to summing all decoded byte
; values, including the record's checksum, and verifying that the LSB of the sum is zero.
            pi getbyte        ; get the record's checksum
            lr A,rxbuffer
            as checksum
            li '.'
            bz dnload5        ; zero means checksum OK
            lr A,errors
            inc
            lr errors,A       ; else, increment checksum error count
            li 'E'
dnload5:    lr txbuffer,A
            pi putc           ; print 'E' for 'error'
            br dnload1        ; go back for the next record

; last record
dnload6:    pi getbyte        ; get the last record address most significant byte
            lr A,rxbuffer
            lr HU,A           ; save the most significant byte of the last record's address in HU
            pi getbyte        ; get the last record address least significant byte
            lr A,rxbuffer
            lr HL,A           ; save the least significant byte of the last record's address in HL
            pi getbyte        ; get the last record type
            pi getbyte        ; get the last record checksum
dnload7:    ins serialport    ; loop here until there is a character available at the serial port
            bp dnload7
            pi getc1          ; get the last carriage return
            li '.'
            lr txbuffer,A
            pi putc           ; echo the carriage return
            pi newline

            clr
            lr zeroflag,A     ; clear 'zeroflag'. leading zeros will be suppressed
            pi printdec       ; print the number of checksum errors
            dci cksumerrtxt
            pi putstr         ; print "Checksum errors"

            lr A,number       ; recall the checksum error count
            ci 0
            bz dnload8        ; if there were zero checksum errors, jump to the address in the last record
            jmp monitor2      ; else, return to monitor

dnload8:    lr DC,H           ; move the address from the last record now in H to DC
            lr Q,DC           ; move the address in DC to Q
            lr P0,Q           ; move the address in Q to the program counter (jump to the address in Q)

;=======================================================================
; display the value input from an I/O port
;=======================================================================
input:      dci portaddrtxt
            pi putstr         ; print the string  to prompt for port address
input1:     pi get2hex        ; get the port address
            lr A,rxbuffer
            ni 0FH            ; mask all but bits 0-3 (valid port addresses are 00-0FH)
            lr portaddr,A     ; save the port address
            bnc input2        ; branch if the input was not ESCAPE or ENTER
            ci ESCAPE         ; was the input ESCAPE?
            bnz input1        ; go back for another input if not
            jmp monitor2      ; else, return to menu

; store code in executable RAM which, when executed, inputs from 'portaddr' and saves A in 'portval'
input2:     dci portvaltxt
            pi putstr         ; print'Port value: "
            dci patch         ; address in 'executable' RAM
            li 0A0H           ; 'INS' opcode
            as portaddr       ; combine the 'INS' opcode with the port address in 'portaddr'
            st                ; save in 'executable' RAM, increment DC
            li 50H+portval    ; 'LR portval,A' opcode
            st                ; save in 'executable' RAM, increment DC
            li 29H            ; 'JMP' opcode
            st                ; save in 'executable' RAM, increment DC
            li hi(input3)     ; hi byte of 'input3' address
            st                ; save in 'executable' RAM, increment DC
            li lo(input3)     ; lo byte of 'input3' address
            st                ; save in 'executable' RAM, increment DC
            jmp patch         ; jump to address in executable RAM

input3:     lr A,portval      ; code in executable RAM jumps back here, retrieve the input byte
            lr hexbyte,A      ; save it in 'hexbyte' for the 'print2hex' function
            pi print2hex      ; print the input byte
            pi newline        ; newline
            jmp monitor2      ; return to menu

;=======================================================================
; output a value to an I/O port
;=======================================================================
output:     dci portaddrtxt
            pi putstr         ; print the string  to prompt for port address
output1:    pi get2hex        ; get the port address
            lr A,rxbuffer
            ni 0FH            ; mask all but bits 0-3 (valid port addresses are 00-0FH)
            lr portaddr,A     ; save the port address
            bnc output2       ; branch if the input was not ESCAPE or ENTER
            ci ESCAPE         ; is the input ESCAPE?
            bnz output1       ; if not, go back for more input
            jmp monitor2      ; return to menu if ESCAPE

output2:    dci portvaltxt
            pi putstr         ; prompt for output value
output3:    pi get2hex        ; get the byte to be output
            lr A,rxbuffer
            lr portval,A      ; save the byte to be output
            bnc output5       ; branch if the input was not ENTER or ESCAPE
            ci ESCAPE         ; is the input ESCAPE?
            bnz output3       ; if not, go back for more input
output4:    jmp monitor2      ; else, exit to the menu

; store code in executable RAM which, when executed, outputs 'portval' to 'portaddr'
output5:    dci patch         ; address in 'executable' RAM
            li 40H+portval    ; 'LR A,portval' opcode
            st                ; save in 'executable' RAM, increment DC
            li 0B0H           ; 'OUTS' opcode
            as portaddr       ; combine the 'OUTS' opcode with the port address in 'portaddr'
            st                ; save in 'executable' RAM, increment DC
            li 29H            ; 'JMP' opcode
            st                ; save in 'executable' RAM, increment DC
            li hi(output4)    ; hi byte of 'output4' address
            st                ; save in 'executable' RAM, increment DC
            li lo(output4)    ; lo byte of 'output4' address
            st                ; save in 'executable' RAM, increment DC
            jmp patch         ; jump to address in executable RAM

;=======================================================================
; jump to an address in memory
;=======================================================================
jump:       dci addresstxt
            pi putstr         ; print the string  to prompt for an address
            pi get4hex        ; get an address into H
            bnc jump1         ; branch if not ESCAPE
            jmp monitor2      ; else, return to menu

jump1:      pi newline
            lr DC,H           ; load the address from the 'get4hex' function now in H to DC
            lr Q,DC           ; load the address in DC to Q
            lr P0,Q           ; load the address in Q to the program counter (efectively, jump to the address in Q)

;=======================================================================
; display the contents of Scratchpad RAM in hex and ASCII
;=======================================================================
scratch:    pi newline
            pi newline
            lis 8
            lr linecnt,A      ; 8 lines
            clr
            lr IS,A

; print the address at the start of the line
scratch1:   lr A,IS           ; ISAR
            lr hexbyte,A      ; save it in 'hexbyte' for the 'print2hex' function
            pi print2hex      ; print the scratchpad RAM address
            li '-'
            lr txbuffer,A
            pi putc           ; print '-'

; print 8 hex bytes
            lis 8
            lr bytecnt,A      ; 8 hex bytes on a line
            lr A,IS
            lr HL,A           ; save IS in HL
scratch2:   lr A,I            ; load the byte from scratchpad RAM into A, increment ISAR
            lr hexbyte,A      ; save it in 'hexbyte' for the 'print2hex' function
            pi print2hex      ; print the data byte at that address
            pi space
            ds bytecnt
            bnz scratch2      ; branch back until 8 bytes have been printed

; print 8 ASCII characters
            lr A,HL
            lr IS,A           ; restore IS
            lis 8
            lr bytecnt,A      ; 16 characters on a line
scratch4:   lr A,I            ; load the byte from scratchpad RAM into A, increment ISAR
            ci 7FH
            bnc scratch5      ; branch if character is > 7FH
            ci 1FH
            bnc scratch6      ; branch if character is > 1FH
scratch5:   li '.'
scratch6:   lr txbuffer,A     ; store the character in 'txbuffer' for the 'putc' function
            pi putc           ; print the character
            ds bytecnt
            bnz scratch4      ; branch back until 8 characters have been printed
            pi newline        ; finished with this line

; increment ISAR to next data buffer
            lr A,IS
            ai 08H            ; next data buffer
            lr IS,A
            lisl 0            ; reset ISAR to the beginning of the data buffer
            ds linecnt
            bnz scratch1      ; branch back until all 8 data buffers have been printed
            jmp monitor2      ; back to the menu

;=======================================================================
; examine/modify Scratchpad RAM contents.
; 1. prompt for a Scratchpad RAM address.
; 2. display the contents of that Scratchpad RAM address.
; 3. wait for entry of a new value to be stored at that Scratchpad RAM address.
; 4. ENTER key leaves Scratchpad RAM unchanged, increments to next Scratchpad RAM address.
; 5. ESCAPE key exits.
;
; CAUTION: modifying Scratchpad Memory locations 00-0FH will likely crash the monitor!
;=======================================================================
xamine:     dci addresstxt
            pi putstr         ; print the string  to prompt for scratchpad RAM address
            pi get2hex        ; get the scratchpad RAM address
            bnc xamine1       ; branch if not ESCAPE key
            jmp monitor2      ; else, return to monitor

xamine1:    pi newline
            lr A,rxbuffer
            lr IS,A           ; move the address from the 'get2hex' function into ISAR

; print the address
xamine2:    lr A,IS           ; load the scratchpad RAM address in ISAR into A
            lr hexbyte,A      ; save it in 'hexbyte' for the 'print2hex' function
            pi print2hex      ; print the address
            pi space

; get the byte from scratchpad RAM
            lr A,S            ; load the byte from scratchpad RAM into A, do not increment or decrement IS
            lr hexbyte,A      ; save it in 'hexbyte' for the 'print2hex' function
            pi print2hex      ; print the data byte at that address
            pi space          ; print a space

; get a new value to store in memory
            pi get2hex        ; get a new data byte
            lr A,rxbuffer     ; load the byte from the 'get2hex' function into A
            bnc xamine3       ; branch if the byte from 'get2hex' is not a control character
            ci ENTER          ; was the input ENTER?
            lr A,S            ; recall the original value stored at this memory address
            bz xamine3        ; branch if the input was ENTER
            jmp monitor2      ; if not ENTER, the input must have been ESCAPE so return to monitor

; store the byte in memory
xamine3:    lr I,A            ; store the byte in scratchpad RAM, increment IS
            pi newline
            lr A,IS
            ni 07H            ; have we reached the end of the data buffer?
            bnz xamine2       ; if not, go do next scratchpad RAM address
; increment ISAR to next data buffer
            lr A,IS
            ai 08H            ; next data buffer
            lr IS,A
            lisl 0            ; reset ISAR to the beginning of the next data buffer
            br xamine2        ; go do next scratchpad RAM address

;------------------------------------------------------------------------
; get 2 hex digits (00-FF) from the serial port. do not echo.
; returns with the 8 bit binary number in 'rxbuffer'.
; this is a first level subroutine which calls a second level subroutine 'get1hex'.
;------------------------------------------------------------------------
getbyte:    lr K,P
            lr A,KU
            lr QU,A
            lr A,KL
            lr QL,A

; get the first hex digit
getbyte1:   pi get1hex        ; get the first hex digit
            lr A,rxbuffer     ; retrieve the character
getbyte3:   sl 4              ; shift into the most significant nibble position
            lr number,A       ; save the first digit as the most significant nibble temporarily in 'number'

; get the second hex digit
getbyte4:   pi get1hex        ; get the second hex digit

; combine the two digits into an 8 bit binary number saved in 'rxbuffer'
getbyte5:   lr A,number       ; recall the most significant nibble from 'number'
            xs rxbuffer       ; combine with the least significant nibble previously received
            lr rxbuffer,A     ; save in 'rxbuffer'
getbyte6:   lr P0,Q           ; return from first level subroutine

;------------------------------------------------------------------------
; get four hex digits (0000-FFFF) from the serial port. echo valid hex digits.
; returns with carry set if ESCAPE key, else returns with the the 16 bit number
; in linkage register H (scratchpad RAM registers 0AH and 0BH).
; this is a first level subroutine which calls second level subroutines 'get1hex' and 'print1hex'.
;
; NOTE: it is not necessary to enter leading zeros. i.e.
;   1<ENTER> returns 0001
;  12<ENTER> returns 0012
; 123<ENTER> returns 0123
;------------------------------------------------------------------------
get4hex:    lr K,P
            lr A,KU
            lr QU,A
            lr A,KL
            lr QL,A

; get the first character...
get4hex1:   pi get1hex        ; get the first hex digit into 'rxbuffer'
            bnc get4hex3      ; branch if not ESCAPE or ENTER
            lr A,rxbuffer     ; load the first hex digit from the get1hex function
            ci ESCAPE         ; is it ESCAPE?
            bz get4hex8       ; branch if ESCAPE
            br get4hex1       ; else, go back if ENTER

; the first character was a valid hex digit
get4hex3:   lr A,rxbuffer
            lr hexbyte,A
            pi print1hex      ; echo the digit
            lr A,rxbuffer
            sl 4              ; shift the first digit into into the most significant nibble position
            lr HU,A           ; save the first digit as the most significant nibble in HU

; get the second character...
            pi get1hex        ; get the second hex digit
            bnc get4hex4      ; branch if not ESCAPE or ENTER
            lr A,rxbuffer
            ci ESCAPE         ; is it ESCAPE?
            bz get4hex8       ; branch if ESCAPE

; the second character is 'ENTER'...
            lr A,HU           ; retrieve the most significant nibble entered previously from HU
            sr 4              ; shift it from the most into the least significant nibble position
            lr HL,A           ; save in HL
            clr
            lr HU,A           ; clear HU
            br get4hex7       ; exit the function

; the second character is a valid hex digit
get4hex4:   lr A,rxbuffer
            lr hexbyte,A
            pi print1hex      ; echo the digit
            lr A,HU           ; recall the most significant nibble entered previously
            xs rxbuffer       ; combine with the least significant nibble from the get1hex function
            lr HU,A           ; save as the most significant byte in HU

; get the third character...
            pi get1hex        ; get the third hex digit into 'rxbuffer'
            bnc get4hex5      ; branch if not ENTER or ESCAPE
            lr A,rxbuffer
            ci ESCAPE         ; is it ESCAPE?
            bz get4hex8       ; branch if ESCAPE

; the third character is 'ENTER'
            lr A,HU           ; else recall the most significant byte
            lr HL,A           ; save it as the least significant byte
            clr
            lr HU,A           ; clear the most significant byte
            br get4hex7       ; exit the function

; the third character is a valid hex digit
get4hex5:   lr A,rxbuffer
            lr hexbyte,A
            pi print1hex      ; echo the digit
            lr A,rxbuffer     ; get the third digit from the rx buffer
            sl 4              ; shift the third digit to the most significant nibble porition
            lr HL,A           ; save in HL

; get the fourth character...
            pi get1hex        ; get the fourth digit into 'rxbuffer'
            bnc get4hex6      ; branch if not WNTER OR ESCAPE
            lr A,rxbuffer
            ci ESCAPE         ; is it ESCAPE?
            bz get4hex8       ; branch if ESCAPE

;; the fourth character is 'ENTER'
            lr A,HL           ; else, retrieve the most significant nibble entered previously from HL
            sr 4              ; shift into the least significant nibble position
            lr HL,A           ; save in HL
            lr A,HU           ; recall the first and second digits entered
            sl 4              ; shift the second digit to the most significant nibble position
            xs HL             ; combine the second and third digits entered to make HL
            lr HL,A           ; save it as HL
            lr A,HU           ; recall the first two digits entered
            sr 4              ; shift the first digit to the most signoficant nibble position
            lr HU,A           ; save it in HU
            br get4hex7       ; exit the function

; the fourth character is a valid hex digit
get4hex6:   lr A,rxbuffer
            lr hexbyte,A
            pi print1hex      ; echo the digit
            lr A,HL           ; retrieve the third hex digit
            xs rxbuffer       ; combine with the fourth digit
            lr HL,A           ; save it in HL

; clear carry and return with the four bytes in HU and HL
get4hex7:   com               ; clear carry
            lr P0,Q           ; return from first level subroutine

; ESCAPE was entered. set carry and return
get4hex8:   li 0FFH
            inc               ; set the carry bit if ESCAPE entered as first character
            lr P0,Q           ; return from first level subroutine

;------------------------------------------------------------------------
; get 2 hex digits (00-FF) from the serial port. echo valid hex digits.
; returns with carry set if ESCAPE or ENTER key, else returns with the
; eight bit binary number in 'rxbuffer'.
; this is a first level subroutine which calls second level subroutines 'get1hex' and 'print1hex'.
;
; NOTE: it is not necessary to enter a leading zero. i.e.
; 1<ENTER> returns 01
; 2<ENTER> returns 02
; ...
; F<ENTER> returns 0F
;------------------------------------------------------------------------
get2hex:    lr K,P
            lr A,KU
            lr QU,A
            lr A,KL
            lr QL,A

; get the character...
get2hex1:   pi get1hex        ; get the first hex digit
            lr A,rxbuffer     ; retrieve the character
            bnc get2hex3      ; branch if the first digit was not a control character
            ci ESCAPE         ; is it ESCAPE?
            bz get2hex2       ; set carry and exit if ESCAPE key
            ci ENTER          ; is it ENTER?
            bz get2hex2       ; set carry and exit if ENTER key
            bnz get2hex1      ; go back if any other control character except ESCAPE or ENTER

; exit the function with carry set to indicate first character was a control character
get2hex2:   li 0FFH
            inc               ; else, set the carry bit to indicate control character
            lr P0,Q           ; restore the return address from Q

; the first character is a valid hex digit
get2hex3:   lr A,rxbuffer
            lr hexbyte,A
            pi print1hex      ; echo the digit
            lr A,rxbuffer
            sl 4              ; shift into the most significant nibble position
            lr HL,A           ; save the first digit as the most significant nibble in HL

; get the second character...
get2hex4:   pi get1hex        ; get the second hex digit
            lr A,rxbuffer
            bnc get2hex5      ; branch if not a control character
            ci ESCAPE         ; is it ESCAPE?
            bz get2hex2       ; branch exit the function if the control character is ESCAPE
            ci ENTER          ; is it ENTER?
            bnz get2hex4      ; go back if any other control character except ESCAPE or ENTER
            lr A,HL           ; the second character was ENTER, retrieve the most significant nibble entered previously from HL
            sr 4              ; shift into the least significant nibble position
            lr rxbuffer,A     ; save in rxbuffer
            br get2hex6       ; exit the function

; the second character was a valid hex digit. combine the two hex digits into one byte and save in 'rxbuffer'
get2hex5:   lr A,rxbuffer
            lr hexbyte,A
            pi print1hex      ; echo the digit
            lr A,HL           ; recall the most significant nibble entered previously
            xs rxbuffer       ; combine with the least significant nibble from the get1hex function
            lr rxbuffer,A     ; save in rxbuffer

; exit the function with carry cleared
get2hex6:   com               ; clear carry
            lr P0,Q           ; return from first level subroutine

;------------------------------------------------------------------------
; prints (to the serial port) the contents of 'hexbyte' as 2 hexadecimal digits.
; this is a first level subroutine which calls a second level subroutine 'print1hex'.
;------------------------------------------------------------------------
print2hex:  lr K,P
            lr A,KU
            lr QU,A
            lr A,KL
            lr QL,A
            lr A,hexbyte      ; retrieve the byte from 'hexbyte'
            lr rxbuffer,A     ; save temporarily in the rx buffer
            sr 4              ; shift the 4 most significant bits to the 4 least significant position
            lr hexbyte,A
            pi print1hex      ; print the most significant hex digit
            lr A,rxbuffer
            lr hexbyte,A
            pi print1hex      ; print the least significant digit
            lr P0,Q           ; return from first level subroutine

;.........................................................................
; get 1 hex digit (0-9,A-F) from the serial port.
; returns with carry set if ESCAPE or ENTER key , else returns with carry
; cleared and the 4 bit binary number saved in 'rxbuffer'.
; this is a second level subroutine called by a first level subroutine.
; this subroutine calls a third level subroutine 'getc'.
;------------------------------------------------------------------------
get1hex:    lr K,P
get1hex1:   ins serialport    ; loop here until there is a character available at the serial port
            bp get1hex1
            pi getc1          ; get the character waiting at the serial port
            lr A,rxbuffer     ; retrieve the character from the rx buffer

; check for control characters (ESCAPE or ENTER)
            ci ESCAPE
            bz get1hex2       ; branch if ESCAPE
            ci ENTER
            bz get1hex2       ; branch if ENTER
            ci ' '-1
            bnc get1hex3      ; branch if not control character
            br get1hex1       ; any other control key, branch back for another character

; exit function with carry set to indicate a control character (ESCAPE or ENTER)
get1hex2:   li 0FFH
            inc               ; set the carry bit to indicate control character
            pk                ; return from second level subroutine

; not a control character. convert lower case to upper case
get1hex3:   ci 'a'-1
            bc get1hex4       ; branch if character is < 'a'
            ci 'z'
            bnc get1hex4      ; branch if character is > 'z'
            ai -20H           ; else, subtract 20H to convert lowercase to uppercase

; check for valid hex digt (0-9, A-F)
get1hex4:   ci '0'-1
            bc get1hex1       ; branch back for another if the character is < '0' (invalid hex character)
            ci 'F'
            bnc get1hex1      ; branch back for another if the character is > 'F' (invalid hex character)
            ci ':'-1
            bc get1hex5       ; branch if the character is < ':' (the character is valid hex 0-9)
            ci 'A'-1
            bc get1hex1       ; branch back for another if the character is < 'A' (invalid hex character)

; valid hex digit was entered. convert from ASCII character to binary number and save in 'rxbuffer'
get1hex5:   ci 'A'-1
            bc get1hex6       ; branch if the character < 'A' (character is 0-9)
            ai -07H           ; else, subtract 07H
get1hex6:   ai -30H           ; subtract 30H to convert from ASCII to binary
            lr rxbuffer,A     ; save the nibble in the receive buffer

; clear carry and exit function
            com               ; clear the carry bit
get1hex7:   pk                ; return from second level subroutine

;------------------------------------------------------------------------
; prints (to the serial port) the contents of 'hexbyte' as a hexadecimal digit.
; this is a second level subroutine called by a first level subroutine.
; this subroutine calls a third level subroutine 'putc'.
;------------------------------------------------------------------------
print1hex:  lr K,P
            lr A,hexbyte      ; retrieve the byte
            sl 4              ; shift left
            sr 4              ; then shift right to remove the 4 most significant bits
            ai 30H            ; add 30H to convert from binary to ASCII
            ci '9'            ; compare to ASCII '9'
            bp print1hex1     ; branch if '0'-'9'
            ai 07H            ; else add 7 to convert to ASCII 'A' to 'F'
print1hex1: lr txbuffer,A     ; put it into the transmit buffer
            pi putc           ; print the least significant hex digit
            pk                ; return from second level subroutine

;------------------------------------------------------------------------
; prints (to the serial port) the contents of 'number' as a 3
; digit decimal number. leading zeros are suppressed.
; this is a second level subroutine called by a first level subroutine.
; this subroutine calls a third level subroutine 'putc'.
;------------------------------------------------------------------------
printdec:   lr K,P
            clr
            lr zeroflag,A
            li '0'-1
            lr digit,A        ; initialize 'digit'
; hundreds digit
printdec1:  lr A,digit
            inc
            lr digit,A        ; increment 'digit' for each time 100 can be subtracted from the number
            lr A,number       ; load the number
            ai -100           ; subtract 100
            lr number,A       ; save in 'number'
            bc printdec1      ; if there's no underflow, go back and subtract 100 from the number again
            ai 100            ; else, add 100 back to the number to correct the underflow
            lr number,A       ; save in 'number'
            lr A,digit        ; recall the hundreds digit
            ci '0'            ; is the hundreds digit '0'?
            bnz printdec2     ; if not, print the hundreds digit
            lr A,zeroflag     ; else, check the zero flag
            ci 0              ; is the zero flag zero?
            bz printdec3      ; if so, skip the hundreds digit and go to the tens digit
printdec2:  lr A,digit
            lr txbuffer,A     ; else, save the hundreds digit in the tx buffer
            pi putc           ; print the hundreds digit
            ds zeroflag       ; set the zero flag (all subsequent zeros will be printed)
printdec3:  li '0'-1
            lr digit,A        ; initialize 'digit'
; tens digit
printdec4:  lr A,digit
            inc
            lr digit,A        ; increment 'digit' for each time 10 can be subtracted from the number
            lr A,number       ; recall from 'number'
            ai -10            ; subtract 10
            lr number,A       ; save in 'number'
            bc printdec4      ; if there's no underflow, go back and subtract 10 from the number again
            ai 10             ; else add 10 back to the number to correct the underflow
            lr number,A       ; save in 'number'
            lr A,digit        ; recall the ten's digit
            ci '0'            ; is the tens digit zero?
            bnz printdec5     ; if not, go print the tens digit
            lr A,zeroflag     ; else, check the zero flag
            ci 0              ; is the flag zero?
            bz printdec6      ; if so, skip the tens digit and print the units digit
printdec5:  lr A,digit        ; else recall the tens digit
            lr txbuffer,A     ; save it in the tx buffer
            pi putc           ; print the tens digit

; units digit
printdec6:  lr A,number       ; what remains in 'number' after subtracting hundreds and tens is the units
            ai 30H            ; convert to ASCII
            lr txbuffer,A     ; save it in the tx buffer
            pi putc           ; print the units digit
            pk                ; return from second level subroutine

;------------------------------------------------------------------------
; prints (to the serial port) the contents of 'number' as a 2 digit decimal number.
; this is a second level subroutine called by a first level subroutine.
; this subroutine calls a third level subroutine 'putc'.
;------------------------------------------------------------------------
printtime:  lr K,P
            li '0'-1
            lr digit,A        ; initialize 'digit'
printtime1: lr A,digit
            inc
            lr digit,A        ; increment 'digit' for each time 10 can be subtracted from the number
            lr A,number       ; recall from 'number'
            ai -10            ; subtract 10
            lr number,A       ; save in 'number'
            bc printtime1     ; if there's no underflow, go back and subtract 10 from the number again
            ai 10             ; else add 10 back to the number to correct the underflow
            lr number,A       ; save in 'number'
            lr A,digit        ; else recall the tens digit
            lr txbuffer,A     ; save it in the tx buffer
            pi putc           ; print the tens digit
            lr A,number       ; what remains in 'number' after subtracting hundreds and tens is the units
            ai 30H            ; convert to ASCII
            lr txbuffer,A     ; save it in the tx buffer
            pi putc           ; print the units digit
            pk                ; return from second level subroutine

;-----------------------------------------------------------------------------------
; print the zero-terminated string whose first character is addressed by DC.
; this is a second level subroutine called by a first level subroutine.
; this subroutine calls a third level subroutine 'putc'.
;-----------------------------------------------------------------------------------
putstr:     lr K,P
putstr1:    lm                ; load the character addressed by DC and increment DC
            ci 0              ; is the character zero (end of string)?
            bnz putstr2       ; branch if not the end of the string
            pk                ; return from second level subroutine

putstr2:    lr txbuffer,A     ; put the character into the tx buffer
            pi putc           ; print the character
            br putstr1        ; go back for the next character

;-----------------------------------------------------------------------------------
; print (to the serial port) carriage return followed by linefeed.
; this is a second level subroutine called by a first level subroutine.
; this subroutine calls a third level subroutine 'putc'.
;-----------------------------------------------------------------------------------
newline:    lr K,P
            lis 0DH           ; carriage return
            lr txbuffer,A     ; put it into the tx buffer
            pi putc           ; print the carriage return
            lis 0AH           ; line feed
            lr txbuffer,A     ; put it in the tx buffer
            pi putc           ; print line feed
            pk                ; return from second level subroutine

;-----------------------------------------------------------------------------------
; print (to the serial port) a space.
; this is a second level subroutine called by a first level subroutine.
; this subroutine calls a third level subroutine 'putc'.
;-----------------------------------------------------------------------------------
space:      lr K,P
            li ' '            ; space character
            lr txbuffer,A     ; put it into the tx buffer
            pi putc           ; print the carriage return
            pk                ; return from second level subroutine

;-----------------------------------------------------------------------------------
; receives the character from the serial port. saves the character in 'rxbuffer'. 
; this is a third level subroutine called by a second level subroutines. 
; must disable interrupts. if this subroutine is interrupted, the return address is lost!
;-----------------------------------------------------------------------------------
getc:       ins serialport    ; wait for the start bit
            bp getc
getc1:      di                ; disable interrupts
            lis 8
            lr bitcount,A
            li 242
            inc
            bnz $-1
getc2:      lr A,rxbuffer     ; get 8 data bits
            sr 1
            lr rxbuffer,A
            ins serialport    ; read the serial input
            ins serialport
            com
            ni 80H
            as rxbuffer
            lr rxbuffer,A
            li 249
            inc
            bnz $-1
            nop
            ds bitcount
            bnz getc2
            li 246
            inc
            bnz $-1
            ei
            pop                  ; return from third level subroutine

;-----------------------------------------------------------------------------------
; transmit the character in 'txbuffer' out through the serial port.
; this is a third level subroutine called by a second level subroutines. 
; must disable interrupts. if this subroutine is interrupted, the return address is lost!
;-----------------------------------------------------------------------------------
putc:       di                ; disable interrupts
            lis 8
            lr bitcount,A
            li 01H
            outs serialport   ; send the start bit
            outs serialport
            outs serialport
            li 247
            inc
            bnz $-1
putc1:      lr A,txbuffer     ; send 8 data bits
            com
            ni 01H
            outs serialport
            li 248
            inc
            bnz $-1
            lr A,txbuffer
            sr 1
            lr txbuffer,A
            ds bitcount
            bnz putc1
            lr A,bitcount
            nop
            nop
            nop
            outs serialport   ; send the stop bit
            li 252
            inc
            bnz $-1
            ei
            pop               ; return from third level subroutine

titletxt    db CLS
            db "3850 SBC Serial Mini-Monitor\r"
            db "Assembled on ",DATE," at ",TIME,0
menutxt     db "\r\r"
            db "D - Display main memory\r"
            db "E - Examine/modify main memory\r"
            db "H - download intel Hex file\r"
            db "I - Input from port\r"
            db "J - Jump to address\r"
            db "O - Output to port\r"
            db "S - display Scratchpad RAM\r"
            db "U - display Uptime\r"
            db "X - display/eXamine scratchpad RAM",0
prompttxt   db "\r\r>> ",0
addresstxt  db "\r\rAddress: ",0
columntxt   db "\r\r     ",SGR4,"00 01 02 03 04 05 06 07 08 09 0A 0B 0C 0D 0E 0F\r",SGR0,0
waitingtxt  db "\r\rWaiting for HEX download...\r\r",0
cksumerrtxt db " Checksum errors\r",0
portaddrtxt db "\r\rPort address: ",0
portvaltxt  db "\rPort value: ",0

            end