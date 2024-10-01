                  page 0                      ; suppress page headings in listing file
                  include "bitfuncs.inc"
                  cpu MK3850
;==================================================================================
; tiny BASIC for the F8 - Jerry D. Fox - Dr. Dobbs #39 Oct 1979
; 
; modified for DASM - 6/28/2012 www.seanriddle.com
; modified for SBCF8 - 11/10/2020 Tetsuya Suzuki
; modified for the AS macro assembler (http: //john.ccac.rwth-aachen.de: 8000/as/) - Jim Loos 09/23/2024
; serial I/O functions for tiny BASIC by Jim Loos 09/23/2024
; mini-monitor (BASIC 'MON' command) by Jim Loos 09/23/2024
;==================================================================================

romtop            equ 00000H                  ; start of EPROM
ramtop            equ 08000H                  ; start of RAM

; registers used by serial I/O functions
bitcnt            equ 00H                     ; number of bits to send/receive
txdata            equ 01H                     ; character to be transmitted
rxdata            equ 01H                     ; received character

; VT100 Escape sequences
CLS               equ "\e[2J\e[H"            ; clear screen and home cursor
SGR0              equ "\e[0m"                ; turn off character attributes
SGR1              equ "\e[1m"                ; turn bold mode on
SGR2              equ "\e[2m"                ; turn low intensity mode on
SGR4              equ "\e[4m"                ; turn underline mode on
SGR5              equ "\e[5m"                ; turn blinking mode on
SGR7              equ "\e[7m"                ; turn reverse video on

                  org romtop
                  
; cold start
cstart:           clr                         
                  outs ledport                ; turn off yellow LEDs
                  outs serialport             ; set serial input and output lines high (idle or MARK)

                  dci tinybasictxt
                  pi putstr                   ; print "tiny BASIC for the MK3850 SBC..."

                  ; rnd initialize
                  dci ranpnt                  ; rnd pointer
                  clr                         ; clear A
                  st                          ; write
                  st                          ; write

                  jmp newt                    ; go setup TXTU

                  ; R3 = format number
                  ; R4 = current character being processed
                  ; R5 is a flag for strings
                  ; R9 is the status save reg
                  
                  ; scratch storage
                  ; 26-27 TXTU    unfilled text addr
                  ; 30-31 currnt  current TBP
                  ; 32-33 skinp   save input stack
                  ; 34-35 skgos   save gosub stack
                  
                  ; save order top-down
                  ; 36-37 lopvar  loop variable
                  ; 40-41 loppt   text pointer
                  ; 42-43 lopln   line number
                  ; 44-45 lopinc  increment
                  ; 46-47 loplmt  limit
                  ; 52-53 temp pointer for read-data
                  ; 50-51 restore pointer for read-dat

start:            dci stack                   ; setup
                  lr Q,DC                     ; stack reg Q
                  clr                         ; zero
                  lisl 7                      ; scratch
st1:              lisu 3                      ; area
                  lr S,A                      ; 30-37
                  lisu 5                      ; and
                  lr D,A                      ; 50-57
                  br7 st1                     ; 30-37
                  lr 5,A                      ; clear string flag for direct
                  lisu 2                      ; reset ISAR
                  pi ttcr                     ; CR,LF
                  lr 8,A                      ; set for prtstg
                  dci prompt                  ; output
                  pi prtstg                   ; prompt
st2:              li '>'                      ; load
                  lr txdata,A                 ; prompt character
                  pi getln                    ; get a line
                  lr H,DC                     ; save eol
                  lr A,HL                     ; low order
                  lr 6,A                      ; byte in R6
                  dci buff                    ; start of line
                  pi tstnum                   ; see if a number
                  ds 1                        ; number?
                  bnz st3                     ; branch if a number
                  lr H,DC                     ; save TBP
                  jmp direct                  ; a command
                  
st3:              li lo(-2)                   ; backup DC
                  adc                         ; to hex line #
                  pi pushdc                   ; save bol
                  lr A,I                      ; store
                  st                          ; hex
                  lr A,D                      ; line
                  st                          ; number
                  lr A,HL                     ; low order byte
                  com                         ; of begin
                  inc                         ; make it -
                  as 6                        ; save #
                  lr 6,A                      ; of chars
                  pi fndln                    ; find line #
                  pi pushdc                   ; save addr
                  xdc                         ; in DC1 also
                  lr DC,H                     ; save in DC0 also
                  lisl 6                      ; put TXTU
                  pi pushsr                   ; on the stack top
                  ; at this point DC0=DC1=found line add
                  bz fline                    ; branch if found line
                  bnc nline                   ; branch if past TXTU
                  br insert                   ; branch if between 2 lines

                  ; delete line pointed to by DC1
                  ; move H thru TXTU up
                  ; DC0=line following found line
                  ; DC1=found line
fline:            lm                          ; get past
                  lm                          ; line #
                  pi fndnxt                   ; find next line *from* in DC0
                  pi mvup                     ; delete the line
                  ; DC1 has the updated TXTU addr (76)
                  xdc                         ; has updated TXTU
                  lr H,DC                     ; into H
                  lisl 6                      ; set ISAR to TXTU
                  lr A,HU                     ; new
                  lr I,A                      ; TXTU
                  lr A,HL                     ; addr
                  lr D,A                      ; in TXTU
                  pi poprt                    ; clear old TXTU
                  pi pushsr                   ; new TXTU on the stack top
                  ; insert between 2 lines
insert:           lr A,6                      ; load line length
                  ci 3                        ; any text?
                  bz start                    ; no just delete
                  ; move TXTU(DC0) thru found line(stack
                  ; top) to TXTU+R4 (DC1)
                  pi txck                     ; update TXTU
                  xdc                         ; setup the move
                  pi mvdown                   ; move down
                  br st4                      ; move in new line
                  
                  ; new line
nline:            pi txck                     ; update TXTU
                  ; move in new line
                  ; setup DC0 and DC1 for new line move
st4:              pi pulldc                   ; *to* found line
                  xdc                         ; in DC1
                  pi pulldc                   ; *from* found line
st5:              lm                          ; load a byte
                  xdc                         ; switch DC
                  st                          ; store it
                  xdc                         ; reset DC
                  ds 6                        ; dec byte count
                  bnz st5                     ; branch if more
                  jmp st2                     ; next record

                  ; this routine exits with
                  ; DC0=new TXTU, DC1=old TXTU
                  ; see if txt area is left
                  ; if room update TXTU by R4
txck:             lr K,P                      ; save return
                  pi pulldc                   ; get TXTU
                  xdc                         ; save TXTU in DC1
                  dci txte                    ; text end addr
                  pi pushdc                   ; on the stack
                  xdc                         ; put
                  lr H,DC                     ; TXTU
                  xdc                         ; in
                  lr DC,H                     ; both DC0 and DC1
                  lr A,6                      ; update TXTU
                  adc                         ; with new line length
                  lr H,DC                     ; new TXTU in 10-11
                  lisl 6                      ; TXTU ISAR addr
                  lr A,HU                     ; store
                  lr I,A                      ; new
                  lr A,HL                     ; TXTU
                  lr D,A                      ; in 26-27
                  pi comt                     ; compare txte-TXTU
                  bc txc1                     ; branch if more room
                  jmp asorry                  ; no more room
                  
txc1:             pk                          ; return

                  ; output contents of accum
                  ; input a line
getln:            lr K,P                      ; save return
                  pi pushrt                   ; push it
                  li 72                       ; buffer
                  lr 8,A                      ; length
                  lr A,txdata                 ; load lead character
get1:             dci buff                    ; buffer addr
get2:             lr txdata,A                 ; output
                  pi tty0                     ; the byte
                  pi ttyi                     ; get a character
                  ni 7FH                      ; turn parity off
                  ci 7FH                      ; rubout?
                  bz get3                     ; branch if yes
                  ci 08H                      ; backspace?
                  bnz get4                    ; branch if not
                  ; backup DC0 to delete a char
get3:             li lo(-1)                   ; backup
                  adc                         ; DC0
                  lr A,8                      ; adjust
                  inc                         ; the
                  lr 8,A                      ; counter
                  li 08H                      ; set backspace
;                 lr H,DC                     ; echo
;                 lm                          ; the last
;                 lr DC,H                     ; character
                  br get2                     ; dont store
                  
get4:             ci 7DH                      ; delete line?
                  bnz get5                    ; branch if not alt-mode
                  pi ttcr                     ; output CR,LF
                  li 5EH                      ; and up arrow
                  br get1                     ; and start over
                  
get5:             ci 0AH                      ; LF?
                  bz get2                     ; ignore it
                  ci 0                        ; null?
                  bz get2                     ; ignore it
                  st                          ; store in buff
                  ds 8                        ; check buff room
                  bz get3                     ; branch if no more room
                  ci 0DH                      ; CR?
                  bnz get2                    ; branch if not cr
                  pi ttcr                     ; output CR,LF
                  jmp pullrt                  ; return

                  ; if TXTU=present DC then stop looking
                  ; this routing looks for a line number
                  ; the line number is in scratch 20-21
                  ; CC=0 found line, CC=+ past a number,
                  ; CC=- past end of text
                  ; for a fndl entry DC points to line number
fndln:            dci txtb                    ; load begin of text addr
fndl:             lr K,P                      ; save return
fnd1:             lisl 6                      ; set ISAR to TXTU
                  pi pushdc                   ; put present TBP on the stack
                  pi comt                     ; addr-TXTU skip lr H,DC and LISL 0
                  bnc fnd2                    ; branch if not the end
                  clr                         ; set
                  lr 9,A                      ; status
                  lr W,J                      ; to no carry
fndr:             pk                          ; return
fnd2:             lisl 4                      ; put the
                  lm                          ; text
                  lr I,A                      ; number
                  lm                          ; on
                  lr D,A                      ; the
                  pi pushsr+1                 ; stack
                  pi comx                     ; text-input
                  bc fndr                     ; branch if past or equal
                  lm                          ; get past
                  lm                          ; line number
                  br fnd4                     ; look for next line

                  ; DC must be set past line # for this entr
fndnxt:           lr K,P                      ; save return
fnd4:             lm                          ; load next char
                  ci 0DH                      ; CR?
                  bnz fnd4                    ; branch if not
                  br fnd1                     ; keep looking

                  ; DC points to line to print
prtln:            lr K,P                      ; save
                  pi pushrt                   ; return
                  lisl 0                      ; set ISAR
                  lm                          ; load
                  lr I,A                      ; the
                  lm                          ; number
                  lr I,A                      ; into 20-21
                  lis 4                       ; set number
                  lr 3,A                      ; of chars to print
                  pi prtnum                   ; convert and print
                  pi pblk                     ; print a blank
                  clr                         ; set end char
                  lr 8,A                      ; to zero
                  pi prtstg                   ; print a string
                  jmp pullrt                  ; return

                  ; print until match of R4
                  ; or a CR is found
prtstg:           lr K,P                      ; save
                  pi pushrt                   ; return
prt1:             lm                          ; load a char
                  lr 4,A                      ; save char
                  lr txdata,A                 ; save the character in the tx buffer
                  xs 8                        ; see if a match
                  bz prt2                     ; return if a match
                  pi tty0                     ; output a char
                  lr A,4                      ; did we output
                  ci 0DH                      ; a CR?
                  bnz prt1                    ; branch if not
prt2:             jmp pullrt                  ; return

                  ; print number in R20-21
prtnum:           lr K,P                      ; save return
                  pi pushrt                   ; addr on the stack
                  ; routine to convert hex to decimal
                  ; hex number must be in scratch 20-21
                  ; changes scratch 22-23 and 24-25
                  pi chksgn                   ; check sign
                  lisl 2                      ; set scratch
                  clr                         ; 22-23
                  lr I,A                      ; to
                  lis 10                      ; decimal
                  lr D,A                      ; 10
                  pi pushsr                   ; put a 10 on the stack
                  lr A,3                      ; save
                  lr 4,A                      ; format #
xcv1:             pi divide                   ; divide by 10
                  pi push20                   ; save digit(remainder)
                  lisl 4                      ; move the
                  pi pushsr                   ; result
                  pi pull20                   ; to 20-21
                  ds 4                        ; dec digit counter
                  lr A,I                      ; see if
                  xs S                        ; exclusive or and
                  as D                        ; add to check for zero
                  bnz xcv1                    ; branch if more
xcv2:             ds 4                        ; need to pad blanks?
                  bm xcv3                     ; branch if we dont
                  pi pblk                     ; print a blank
                  br xcv2                     ; see if we need more blanks
                  
xcv3:             lr A,8                      ; output
                  br xcv5                     ; the sign
                  
xcv4:             pi pullsr                   ; get a digit
                  ci 10                       ; last one?
                  bz xcv6                     ; branch if last
                  oi 30H                      ; ASCII
xcv5:             lr txdata,A                 ; output reg
                  pi tty0                     ; output
                  br xcv4                     ; another
                  
xcv6:             jmp pullrt                  ; return

                  ; output a blank
pblk:             li ' '                      ; load a blank
                  lr txdata,A                 ; output reg
                  jmp tty0                    ; go print

                  ; check for ' or " type string
                  ; R8 has the present byte
                  ; CC=0 for a drop thru return
qstring:          lr K,P                      ; save
                  pi pushrt                   ; return
                  lr A,4                      ; get char
                  ci '\''                     ; string?
                  bnz qst4                    ; not ' maybe "
qst1:             lr 8,A                      ; load end char
                  lm                          ; get past it
                  pi prtstg                   ; print string
qst2:             pi poprt                    ; pull return into 12-13
                  lr A,4                      ; was the last a CR
                  ci 0DH                      ; CR?
                  bnz qst3                    ; branch if not CR
                  jmp rnxl                    ; run next line
                  
qst3:             pi char                     ; get next char
                  xs 4                        ; set CC=0 for drop thru return
                  pk                          ; return
                  
qst4:             ci '"'                      ; string?
                  bz qst1                     ; go load end char
qst5:             ci 5FH                      ; a back arrow
                  bnz qst6                    ; branch if not
                  lis 0DH                     ; output just a CR
                  lr txdata,A                 ; output reg
                  pi tty1                     ; output the CR
                  lm                          ; get past <
                  br qst2                     ; go drop thru return
                  
qst6:             jmp pullrt                  ; return and branch

                  ; see if variable or array
                  ; if so put addr in DC1, TBP in DC0
testvl:           lr A,4                      ; load character
                  ai 0C0H                     ; subtract @
                  bm tvr                      ; branch if not a variable
                  lr J,W                      ; save status
                  lr 2,A                      ; save variable
                  ci 26                       ; a-z?
                  bm tvr                      ; branch if not
                  lr K,P                      ; save
                  pi pushrt                   ; return
                  pi skip                     ; inc DC and get next char
                  ci '$'                      ; a string?
                  bnz tvs                     ; branch not a string
                  lr A,9                      ; save status
                  lr 5,A                      ; set as string
                  pi skip                     ; get next character
tvs:              lr W,J                      ; restore status
                  bnz tv1                     ; branch if a variable
                  pi parn                     ; (should be next)
                  pi mv2021                   ; move 20-21 to 22-23
                  pi addd                     ; double index
                  bp tvt                      ; branch if not too big

                  ; may be @(-index)
                  lr A,5                      ; change status
                  com                         ; of the
                  inc                         ; previous
                  lr 5,A                      ; string just in case
                  lr A,I                      ; see if
                  inc                         ; lt -255
                  bnz tve                     ; branch if not
                  lr A,D                      ; make
                  com                         ; low
                  inc                         ; positive
                  ci 52                       ; @(-index) past z?
                  bp tv2                      ; branch if it isnt
tve:              jmp qhow                    ; error

tvt:              xdc                         ; save TBP
                  dci varbgn                  ; begin of array
                  lr H,DC                     ; into 10-11
                  pi mv2021                   ; move 2*index into 22-23
                  lr A,HU                     ; so we
                  lr I,A                      ; can
                  lr A,HL                     ; put begin
                  lr D,A                      ; in 20-21
                  pi subd                     ; varbgn-index
                  lisl 6                      ; put TXTU
                  pi pushsr                   ; on the stack
                  pi comp                     ; TXTU-@ (index)
                  bnc tvd                     ; branch if room left
                  xdc                         ; get TBP
qsorry:           pi pushdc                   ; save TBP
asorry:           dci sorry                   
                  jmp error                   ; process error
                  
tvd:              sr 1                        ; make status+CR 0
                  pi pushsr                   ; move var addr
                  pi pulldc                   ; to DC
                  br tv3                      ; go return

                  ; A-Z variable
tv1:              lr A,2                      ; load variable
                  sl 1                        ; var index*2
tv2:              xdc                         ; save TBP
                  dci varbgn                  ; get
                  adc                         ; variable addr
tv3:              xdc                         ; DC0=TBP, DC1=var addr
                  jmp pullrt
                  
tvr:              pop                         ; fast return

                  ; test an item pointed to by DC
                  ; the number and (20-21) will contain
                  ; the hex conversion of it
                  ; if R1=0 not a number
tstnum:           lr K,P                      ; save return
                  lisl 0                      ; set ISAR
                  clr                         ; zero
                  lr I,A                      ; lead
                  lr D,A                      ; bytes
                  inc                         ; set R1 for no number
                  lr 1,A                      ; and digit counter
ts1:              pi char                     ; get next char
                  ci 2FH                      ; see
                  bp ts2                      ; if
                  ci 39H                      ; a
                  bp ts3                      ; decimal
ts2:              pk                          ; return

ts3:              sl 4                        ; strip
                  sr 4                        ; ascii
                  lr 2,A                      ; save the digit
                  ds 1                        ; set R1 for a number found
                  pi mv2021                   ; move 20-21 to 22-23
                  clr                         ; zero R20
                  lr I,A                      ; and
                  lr S,A                      ; R21
                  lis 10                      ; multiply
                  lr 7,A                      ; existing digits
                  pi mult                     ; by 10
                  lisl 1                      ; now
                  lr A,S                      ; add
                  as 2                        ; the
                  lr D,A                      ; new
                  lr A,S                      ; digit
                  lnk                         ; to the
                  lr S,A                      ; accumulated result
                  lm                          ; skip this byte
                  bp ts1                      ; branch if no overflow

qhow:             pi pushdc                   ; save TBP
ahow:             dci how                     
                  jmp error

                  ; DC1 must point to table
                  ; DC0 points to word
                  ; reg H points to DC0
direct:           dci tab1                    ; command table
exec:             xdc                         ; in DC1
                  lr DC,H                     ; DC0=tiny basic pointer(TBP)
                  li lo(-1)                   ; set R1
                  lr 1,A                      ; to -1
ex1:              lm                          ; load from tb line
                  xdc                         ; get table addr
                  ci '.'                      ; period?
                  bz ex3                      ; branch if yes
                  cm                          ; compare
                  xdc                         ; put TBP back in DC0
                  bz ex1                      ; branch if a match
                  ; here no match
                  lr A,1                      ; backup
                  adc                         ; TBP
                  xdc                         ; and get the
                  adc                         ; last accessed
                  lm                          ; table byte
                  ns 1                        ; an addr?
                  bm ex4                      ; branch if it was
                  ; look for addr
ex2:              lm                          ; load
                  ns 1                        ; an addr?
                  bp ex2                      ; branch if not
                  lm                          ; get low byte
                  br exec                     ; restore word addr
                  
                  ; found a period
ex3:              lm                          ; load next char
                  ns 1                        ; an addr?
                  bp ex3                      ; branch if not
ex4:              sl 1                        ; turn sign
                  sr 1                        ; bit off
                  lr KU,A                     ; save hi order
                  lm                          ; load
                  lr KL,A                     ; low order
                  xdc                         ; get tb pointer in DC0
                  pk                          ; call routine
                  
                  ; skinp in 32-33
inperr:           lisl 2                      ; setup skinp ISAR
                  lr A,I                      ; restore
                  lr QU,A                     ; the
                  lr A,D                      ; old
                  lr QL,A                     ; stack
                  pi pull20                   ; restore currnt
                  lisu 2                      ; reset ISAR
                  pi pulldc                   ; clear stack
                  pi pulldc                   ; get original TBP
                  
input:            pi pushdc                   ; save TBP in case of error
ip1:              pi char                     ; get next char
                  pi qstring                  ; see if a string
                  bnz ip2                     ; branch not a string
                  pi testvl                   ; variable?
                  bm ip4                      ; branch if not
                  br ip3                      ; branch if a variable
                  
                  ; here not a string
ip2:              pi pushdc                   ; save TBP for prtstg
                  pi testvl                   ; variable?
                  bp $+5                      ; branch if a car
                  jmp qwhat                   ; error
                  
                  lr H,DC                     ; save TBP
                  lm                          ; save
                  lr 7,A                      ; this byte
                  clr                         ; and
                  lr DC,H                     ; store
                  st                          ; a zero
                  lr 8,A                      ; for end of string
                  pi pulldc                   ; get TBP
                  pi prtstg                   ; print string
                  li lo(-1)                   ; backup
                  adc                         ; DC
                  lr H,DC                     ; save TBP
                  lr A,7                      ; and restore
                  st                          ; char
                  lr DC,H                     ; restore TBP
                  ; here an input variable
ip3:              pi pushdc                   ; save TBP
                  lisu 3                      ; save
                  pi push20                   ; currnt
                  li lo(-1)                   ; set currnt
                  lr S,A                      ; to minus
                  lisl 2                      ; ISAR for skinp
                  lr A,QU                     ; save
                  lr I,A                      ; the
                  lr A,QL                     ; stack
                  lr I,A                      ; pointer
                  lisu 2                      ; reset ISAR
                  xdc                         ; save
                  pi pushdc                   ; variable addr
                  ; prompt for input
                  li ':'                      ; prompt
                  lr txdata,A                 ; char
                  pi getln                    ; get a line
                  dci buff                    ; input addr
                  lr A,5                      ; setup
                  lr 9,A                      ; string
                  lr W,J                      ; status
                  bm ipx                      ; branch if not a string
                  pi pulldc                   ; get var addr
                  pi buftov                   ; move buf to var
                  br ips                      ; continue
                  
ipx:              pi expr                     ; evaluate expr
                  pi pulldc                   ; get var addr
                  lr A,I                      ; store the value
                  st                          ; into
                  lr A,D                      ; the
                  st                          ; variable
ips:              lisu 3                      ; restore
                  pi pullsr                   ; currnt
                  lisu 2                      ; restore
                  pi pulldc                   ; TBP
ip4:              pi poprt                    ; clear stack
                  pi ignbk                    ; get next char
                  ci ','                      ; comma?
                  bz input                    ; branch if more

                  ; see if proper end
fini:             li lo(-1)                   ; backup
                  adc                         ; TBP
fin:              pi finish                   ; finish
                  jmp qwhat                   ; return here is an error

                  ; here if no let
deflt:            pi ignbk                    ; get next char
                  ci 0DH                      ; an empty line
                  bnz $+5                     ; branch not empty
                  jmp rnxl                    ; it's OK, get next line
                  
                  lr DC,H                     ; restore TBP
let:              pi setval                   ; get variable
                  lr A,4                      ; restore char
                  ci ','                      ; comma?
                  lm                          ; get past this char
                  bz let                      ; do it again
                  br fini                     ; finish up

                  ; print a string or number
                  ; R3 is the format number
print:            lis 6                       ; set
                  lr 3,A                      ; digit counter
                  pi ignbk                    ; get next char
                  ci ';'                      ; ';' multiple record?
                  bnz pr1                     ; branch if not
                  pi ttcr                     ; just a CR,LF
                  jmp rsml                    ; run same line
                  
pr1:              ci 0DH                      ; CR?
                  bnz pr2                     ; branch if not CR
                  pi ttcr                     ; just CR,LF
                  jmp rnxl                    ; run next line
                  
pr2:              ci '#'                      ; format change?
                  bnz pr3                     ; branch if not
                  pi expr                     ; evaluate format
                  lisl 1                      ; get format out
                  lr A,I                      ; of 20-21
                  lr 3,A                      ; into R3
                  ds 3                        ; adjust format
                  br pr4                      ; check for comma
                  
pr3:              li lo(-1)                   ; backup
                  adc                         ; TBP
                  pi qstring                  ; see if a string
                  bnz pr6                     ; branch if not a string

                  ; drops thru if string or back
pr4:              lr A,4                      ; load char
                  ci ','                      ; comma?
                  bnz pr5                     ; branch if not comma
                  lm                          ; get past comma
                  pi finish                   ; go finish up line
                  br pr2                      ; continue
                  
pr5:              pi ttcr                     ; list end so CR,LF
                  jmp fin                     ; finish up

pr6:              pi expr                     ; evaluate expression
                  ; see if a string (600)
                  lr A,5                      ; get string flag
                  lr 9,A                      ; into
                  lr W,J                      ; status reg
                  bm pr7                      ; branch if not string
                  ds 5                        ; clear string flag
                  xdc                         ; save TBP
                  dci buff                    ; addr of string
                  clr                         ; get string
                  lr 8,A                      ; terminator
                  pi prtstg                   ; go print string
                  xdc                         ; restore TBP
                  br pr8                      ; continue
                  
pr7:              pi prtnum                   ; print the number
pr8:              pi char                     ; get next char
                  br pr4                      ; look for comma

gosub:            pi save                     ; save for parameters
                  pi expr                     ; evaluate expr
                  pi pushdc                   ; save TBP
                  pi fndln                    ; find target line
                  bz gos1                     ; branch if found
                  jmp ahow                    ; error
                  
gos1:             lisu 3                      ; set
                  pi push20                   ; save currnt
                  lisl 4                      ; save
                  pi pushsr                   ; skgos
                  lr A,QU                     ; put stack
                  lr I,A                      ; pointer
                  lr A,QL                     ; into
                  lr I,A                      ; skgos
                  clr                         ; zero
                  lr I,A                      ; lopvar
                  lr I,A                      ; in scratch
                  jmp rtsl                    ; run the line
                  
return:           pi endcr                    ; look for CR
                  lisu 3                      ; set ISAR
                  lisl 4                      ; to skgos
                  lr A,I                      ; load hi
                  xs S                        ; exclusive or and
                  as D                        ; and add to check for 0
                  bnz ret1                    ; branch if not
                  jmp qwhat                   ; didnt exist
                  
ret1:             lr A,I                      ; load
                  lr QU,A                     ; stack pointer
                  lr A,D                      ; from
                  lr QL,A                     ; skgos
                  pi pullsr                   ; load old skgos
                  pi pull20                   ; load currnt
                  pi pulldc                   ; restore TBP
                  xdc                         ; save DC
                  pi restor                   ; go restore
                  xdc                         ; restore TBP
                  pi fin                      ; finish up
                  
what:             db "WHAT?"                  
                  db 0DH
how:              db "HOW?"                   
                  db 0DH
                  ; 3E6-3FF used by FAIRBUG
sorry:            db "SORRY"                  
                  db 0DH
                  db " FAIRBUG USES"
                  db "3E6-3FF"
                  db "9ABCDEF"
                  
                  ; LIST (CR) lists all saved lines
                  ; LIST n (CR) from n down
                  ; LIST n,# (CR) will list
                  ; # lines from n down
list:             pi tstnum                   ; see if a number
                  ds 1                        ; was it?
                  bz lis4                     ; branch if it was not
                  lr A,4                      ; see if the
                  ci ','                      ; next one is a comma
                  bnz lis4                    ; branch if it isnt
                  pi pushsr                   ; save the line #
                  pi skip                     ; get the next char
                  pi tstnum                   ; and the next number
                  ds 1                        ; was it a number
                  bnz lis1                    ; branch if it was
                  jmp qwhat                   ; else error
                  
lis1:             lr A,S                      ; is the
                  as i                        ; num of lines gt 255
                  bz lis3                     ; branch if it isnt
lis2:             jmp qhow                    ; else error

lis3:             lr A,S                      ; load the
                  lr 6,A                      ; number of lines to print
                  as D                        ; see if zero
                  bz lis2                     ; error if it is
                  pi pullsr                   ; restore begin line #
                  lis 1                       ; set list flag for n,#
                  br lis5                     ; to list #,n
                  
lis4:             clr                         ; set list flag
lis5:             lr 5,A                      ; to no n
                  pi endcr                    ; get past CR
                  pi fndln                    ; find a line
                  bnc lis7                    ; branch if past TXTU
lis6:             pi prtln                    ; print a line
                  pi fndl                     ; get next line
                  bnc lis7                    ; branch if past TXTU
                  lr A,5                      ; see if looping
                  as 5                        ; on n
                  bz lis6                     ; branch if not
                  ds 6                        ; dec n
                  bnz lis6                    ; and loop
lis7:             jmp start                   ; go prompt
                  
                  ; clear text area
new:              pi endcr                    ; clear text line
newt:             dci txtb                    ; begin addr
                  lr H,DC                     ; in 10-11
                  lisu 2                      ; set ISAR for initial entry
                  lisl 6                      ; set ISAR to TXTU
                  lr A,HU                     ; reset
                  lr I,A                      ; to
                  lr A,HL                     ; the beginning
                  lr D,A                      ; of text area
                  jmp start                   ; restart
                  
stop:             pi endcr                    ; find CR
                  jmp start                   ; restart
                  
                  ; if true run same line
                  ; if not true run next line
if:               pi expr                     ; evaluate the expression
                  lr A,I                      ; see if
                  xs S                        ; exclusive or and
                  as D                        ; add to check for zero
                  bz rem                      ; branch if it is
                  jmp rsml                    ; run same line
                  
                  ; remark is a false if
rem:              pi fndnxt                   ; find the next line
                  bnc if1                     ; branch past the end
                  jmp rtsl                    ; run next line
                  
if1:              jmp start                   ; no more text
                  
                  ; for var=expr to expr skip expr
for:              pi save                     ; save for variable
                  pi setval                   ; get variable
                  li lo(-2)                   ; backup
                  xdc                         ; DC1
                  adc                         ; to get var addr
                  pi pushdc                   ; on the stack
                  xdc                         ; restore TBP
                  lisu 3                      ; put variable
                  lisl 6                      ; addr into
                  pi pullsr                   ; lopvar
                  lisu 2                      ; reset ISAR
                  dci tab5                    ; go look
                  jmp exec                    ; for 'to'
                  
fr1:              pi expr                     ; evaluate limit
                  pi push20                   ; loplmt(46-47) on stack
                  dci tab6                    ; go look
                  jmp exec                    ; for 'step'
                  
fr2:              pi expr                     ; evaluate increment
                  br fr4                      ; branch around default of 1
                  
fr3:              clr                         ; no 'skip', set
                  lr I,A                      ; increment
                  inc                         ; to
                  lr D,A                      ; one
fr4:              pi push20                   ; lopinc(44-45)
                  lisu 3                      ; use currnt
                  pi push20                   ; as lopln(42-43)
                  pi pushdc                   ; and TBP as loppt(40-41)
                  lr DC,Q                     ; stack addr in dc
                  pi refor                    ; put them all in scratch
                  lisu 3                      ; set ISAR for lopvar
                  lr DC,Q                     ; save
                  xdc                         ; original stack addr
                  lr DC,Q                     ; reset DC0
fr5:              lr H,DC                     ; temp save
                  lr Q,DC                     ; new stack addr
                  lm                          ; see if
                  om                          ; the end
                  bnz fr6                     ; branch if not
                  xdc                         ; restore original
                  br fr8                      ; stack addr
                  
fr6:              lisl 6                      ; set ISAR for lopvar
                  pi comt                     ; compare to lcpvar
                  lis 10                      ; go down to
                  adc                         ; the next level
                  bnz fr5                     ; branch if found
                  li lo(-1)                   ; get
                  adc                         ; from addr
                  xdc                         ; restore original stack addr
                  lr Q,DC                     ; put
                  pi pushdc                   ; on the stack top
                  xdc                         ; put
                  lr H,DC                     ; from
                  xdc                         ; in both
                  lr DC,H                     ; DC0 and DC1
                  lis 10                      ; to addr is
                  adc                         ; from+10
                  xdc                         ; in DC1
                  pi mvdown                   ; move the stack down 10 bytes worth
                  lr DC,H                     ; restore
fr8:              lr Q,DC                     ; stack addr
                  lisu 4                      ; restore
                  pi push20                   ; TBP by using
                  pi pulldc                   ; loppt
                  lisu 2                      ; reset ISAR
                  jmp fin                     ; finish up
                  
                  ; next var
next:             pi char                     ; get next char
                  pi testvl                   ; test variable
                  xdc                         ; car addr in DC0
                  bp $+6                      ; branch around error jump
nx0:              xdc                         ; restore TBP
                  jmp qwhat                   ; error
                  
                  pi pushdc                   ; put var addr(lopvar)
                  pi pull20                   ; into 20-21
nx1:              lisu 3                      ; set ISAR
                  lisl 6                      ; to lopvar
                  lr A,I                      ; see
                  as S                        ; if
                  xs D                        ; its zero
                  bz nx0                      ; branch if zero an error
                  pi pushsr                   ; put lopvar
                  lisu 2                      ; on the stack top
                  pi comp                     ; compare next variable
                  bz nx2                      ; to lopvar & b if eq
                  pi restor                   ; restore next level
                  br nx1                      ; keep looking
                  
                  ; need to add lopinc to the
                  ; variable lopvar points to
nx2:              pi save+1                   ; put everything back skip xdc
                  xdc                         ; save TBP
                  pi push20                   ; get addr of
                  pi pulldc                   ; lopvar in DC
                  lr H,DC                     ; save lopvar addr
                  lm                          ; put
                  lr I,A                      ; value
                  lm                          ; of lopvar
                  lr I,A                      ; in 20-21
                  lr DC,Q                     ; save
                  lis 6                       ; setup
                  adc                         ; temp stack
                  lr Q,DC                     ; to get lopinc(44-45)
                  pi pullsr+1                 ; into 22-23 (skip lr H,DC)
                  pi addd                     ; index=index+lopinc
                  lr A,I                      ; store
                  st                          ; the
                  lr A,D                      ; incremented
                  st                          ; lopvar
                  pi comx                     ; compare(limit-index)
                  lr DC,Q                     ; save the
                  lr H,DC                     ; original stack addr
                  bz nx4                      ; branch if not done
                  
                  ; here assuming lopinc is +, it could
                  ; be - so both gt and lt must be checked
                  ; backup temp Q by 4 bytes to lopinc
                  li lo(-4)                   ; reset temp stack
                  adc                         ; to lopinc
                  clr                         ; see
                  om                          ; if minus
                  bm nx3                      ; branch if negative inc
                  lr W,J                      ; restore status
                  bm nx5                      ; + inc, br if done(-)
                  br nx4                      ; not done
                  
nx3:              lr W,J                      ; restore status
                  bp nx5                      ;- inc, br if done(+)
                  ; still looping, set currnt=lopvar
                  ; and DC0=loppt the new TBP-
nx4:              lr DC,Q                     ; reset
                  li lo(-8)                   ; stack
                  adc                         ; to point
                  lr Q,DC                     ; to loppt(40-41)
                  lr DC,H                     ; save
                  xdc                         ; original stack in DC1
                  pi pulldc                   ; get TBP=loppt
                  lisu 3                      ; set
                  pi pull20                   ; currnt=lopln
                  lisu 2                      ; reset ISAR
                  xdc                         ; reset
                  lr Q,DC                     ; stack pointer
                  br nx6                      ; go finish line
                  
nx5:              lr DC,H                     ; reset original
                  lr Q,DC                     ; stack
                  pi restor                   ; get next for-next level
nx6:              xdc                         ; restore TBP
                  jmp fin                     ; finish up
                  
                  ; read A,B$,@(i),@$(i)
read:             pi char                     ; get next char
                  pi testvl                   ; a variable?
                  pi pushdc                   ; save TBP
                  bp $+5
rea1:             jmp awhat                   ; error

                  lisu 5                      ; set ISAR
                  lisl 2                      ; to temp pointer
                  lr A,I                      ; get present
                  lr HU,A                     ; data
                  lr A,D                      ; addr
                  lr HL,A                     ; into
                  lr DC,H                     ; DC0
                  lisu 2                      ; reset ISAR
                  pi rdata                    ; process data item
                  pi char                     ; get next char
                  ci ','                      ; see if a comma
                  bz rea2                     ; branch if it is
                  ci 0DH                      ; CR?
                  bnz rea1                    ; error if not
rea2:             pi skip                     ; get past , or CR
                  lisu 5                      ; setup
                  lisl 2                      ; temp pointer
                  lr H,DC                     ; store
                  lr A,HU                     ; the
                  lr I,A                      ; present
                  lr A,HL                     ; data
                  lr D,A                      ; pointer
                  lisu 2                      ; reset ISAR
                  pi pulldc                   ; restore TBP
                  pi ignbk                    ; was last char
                  ci ','                      ; a comma?
                  bz read                     ; branch if more
                  jmp fini                    ; finish up
                  
                  ; DATA n,'STRING',expr
data:             lr H,DC                     ; save TBP
                  lisu 5                      ; save TBP
                  lisl 0                      ; to data pointer
                  lr A,I                      ; see if
                  xs S                        ; zero by
                  as D                        ; xor and adding
                  bnz dat1                    ; branch if not zero
                  lr A,HU                     ; setup
                  lr I,A                      ; permanent
                  lr A,HL                     ; dat
                  lr I,A                      ; pointer
                  lr A,HU                     ; and the
                  lr I,A                      ; temp
                  lr A,HL                     ; pointer
                  lr I,A                      ; as well
dat1:             lisu 2                      ; reset ISAR
                  lr DC,H                     ; restore TBP
                  jmp rem                     ; run the next line
                  
                  ; reset data pointer
restore:          lisu 5                      ; set ISAR
                  pi mv2021                   ; reset the pointer
                  lisu 2                      ; reset ISAR
                  jmp fin                     ; finish up
                  
                  ; find the line number and goto i
goto:             pi expr                     ; evaluate the expression
                  pi pushdc                   ; save DC in case of error
                  pi endcr                    ; find CR
                  pi fndln                    ; find the line
                  bnz go1                     ; branch if not found
                  pi poprt                    ; clear the stack
                  br rtsl                     ; run the line
                  
go1:              jmp ahow                    ; process error
                  
run:              pi endcr                    ; find CR
                  dci txtb                    ; begin of text addr
                  ; run the next line
rnxl:             lisl 0                      ; set scratch
                  clr                         ; 20-21
                  lr I,A                      ; the line number
                  lr D,A                      ; to zero
                  pi fndl                     ; find next line
                  bc rtsl                     ; branch if not past TXTU
                  jmp start                   ; restart
                  
                  ; save current line addr
rtsl:             lisu 3                      ; get
                  lisl 0                      ; vale of
                  lr A,HU                     ; currnt
                  lr I,A                      ; store
                  lr A,HL                     ; new
                  lr D,A                      ; line number
                  lisu 2                      ; reset ISAR
                  lr DC,H                     ; get past
                  lm                          ; line number
                  lm                          ; line number
                  ; run the same line
rsml:             lr H,DC                     ; put line addr in H
                  clr                         ; clear
                  lr 5,A                      ; string flag
                  dci tab2                    ; tb commands table
                  jmp exec                    ; go process
                  
                  ; finish up the line
finish:           lr K,P                      ; save return
                  pi ignbk                    ; get next char
                  ci ';'                      ; multiple statement?
                  bz rsml                     ; yes run same line
                  ci 0DH                      ; CR?
                  bz rnxl                     ; yes run next line
                  pk                          ; return
                  
                  ; evaluate an expression
expr:             lr K,P                      ; save
                  pi pushrt                   ; return
                  pi expr2                    ; get 1st expression
                  pi push20                   ; save 1st expr
expr1:            lr H,DC                     ; save TBP
                  dci tab8                    ; relational operator table
                  jmp exec                    ; go see if we have op
                  
xp11:             pi xp18                     ; ">="
                  bc _true                    ; branch true
                  br _false                   ; set false=0
                  
xp12:             pi xp18                     ; "#"
                  bnz _true                   ; branch true
                  br _false                   ; set_false=0
                  
xp13:             pi xp18                     ; ">"
                  bz _false                   ; set false=0
                  bc _true                    ; branch true
                  br _false                   ; set false=0
                  
xp14:             pi xp18                     ; "<="
                  bnc _true                   ; branch true
                  bz _true                    ; branch true
                  br _false                   ; set false=0
                  
xp15:             pi xp18                     ; "="
                  bz _true                    ; branch true
                  br _false                   ; set false=0
                  
xp16:             pi xp18                     ; "<"
                  bnc _true                   ; b_true
_false:           ds D                        ; set R21=0
_true:            jmp pullrt                  ; return

                  ; not a relational operator
xp17:             pi pullsr                   ; get 1st expression
                  jmp pullrt                  ; return
                  
                  ; get 2nd expr and compare
xp18:             lr K,P                      ; save
                  pi pushrt                   ; return
                  clr                         ; clear
                  lr 5,A                      ; string flag
                  pi expr2                    ; get 2nd expr
                  pi poprt                    ; pop return into K
                  ; if the 2 items have the same sign
                  ; leave as iS, but if the sign is
                  ; different exchange the stack and ISAR
                  lr DC,Q                     ; stack addr
                  lr A,S                      ; load hi byte
                  xm                          ; xor them
                  lr DC,H                     ; restore TBP
                  bp xp19                     ; branch if the same sign
                  pi mv2021                   ; move 2nd expr to 22-23
                  pi pullsr                   ; stack (1st expr) into 20-21
                  lisl 2                      ; 2nd expr
                  pi pushsr                   ; onto stack top
xp19:             pi comp                     ; compare 1st and 2nd expr
                  clr                         ; set
                  lr I,A                      ; 20-21=1
                  inc                         ; for
                  lr S,A                      ; true and set LISL 1
                  lr W,J                      ; restore status
                  pk                          ; return
                  
                  ; DC must contain TBP
expr2:            lr K,P                      ; save
                  pi pushrt                   ; return
                  lisl 0                      ; set ISAR
                  pi char                     ; get next character
                  ci '-'                      ; minus?
                  bnz xp21                    ; branch if not
                  clr                         ; set
                  lr I,A                      ; first
                  lr D,A                      ; expr=0
                  br xp26                     ; treat like subtract
                  
xp21:             ci '+'                      ; plus?
                  bnz xp22                    ; branch if not
                  pi skip                     ; inc DC and get next char
xp22:             pi expr3                    ; process first exp
xp23:             lr A,4                      ; load the char
                  lisl 0                      ; reset to 20-21
                  ci '+'                      ; add?
                  bnz xp25                    ; branch if not
                  pi pushsr                   ; save first expr
                  pi skip                     ; inc DC and get next char
                  pi expr3                    ; process 2nd expr
xp24:             lisl 2                      ; get 1st
                  pi pullsr                   ; expr into 22-23
                  lr A,S                      ; load hi
                  lisl 0                      ; set to other hi
                  xs S                        ; exclusive or
                  lr J,W                      ; save status of signs
                  pi addd                     ; add
                  lr W,J                      ; restore status
                  bm xp23                     ; branch if signs differ
                  lr A,S                      ; signs the same
                  lisl 2                      ; so must be result
                  xs S                        ; equal?
                  bp xp23                     ; branch if they are
                  jmp qhow                    ; process error
                  
xp25:             ci '-'                      ; minus?
                  bz xp26                     ; branch if minus
                  jmp xp45                    ; return
                  
xp26:             pi pushsr                   ; save first expr
                  pi skip                     ; inc DC and get next char
                  pi expr3                    ; get 2nd expr
                  pi chgsgn                   ; change sign
                  br xp24                     ; go add
                  
expr3:            lr K,P                      ; save
                  pi pushrt                   ; return
                  pi expr4                    ; get first expr
xp30:             lr A,4                      ; load the char
xp31:             ci '*'                      ; multiply?
                  bnz xp34                    ; branch if not
                  pi push20                   ; save 1st expr
                  pi skip                     ; inc DC and get next char
                  pi expr4                    ; get end expr
                  pi chksgn                   ; check sign
                  lr A,8                      ; save
                  lr 2,A                      ; the sign
                  pi exch                     ; exchange stack and 20-21
                  pi chksgn                   ; check the sign
                  li 0FFH                     ; see if
                  ns 6                        ; hi gt 255
                  bz xp32                     ; branch le 255
                  ; number in 20-21 gt 255
                  li 0FFH                     ; see if
                  ns S                        ; this gt 255 (1122)
                  bnz xp33                    ; branch if gt 255(overflow will occur) (1123)
                  pi exch                     ; switch so small in r7-8
xp32:             pi mv2021                   ; move 20-21 to 22-23
                  clr                         ; zero
                  lr I,A                      ; 20-21
                  lr D,A                      ; for a mult
                  pi mtply                    ; go multiply
                  pi poprt                    ; clear stack
                  bp xp35                     ; take care of signs
xp33:             jmp qhow                    ; process error

xp34:             ci '/'                      ; divide?
                  bz $+5                      ; branch if /
                  jmp xp45                    ; go return
                  
                  pi push20                   ; save 1st expr
                  pi skip                     ; inc DC and get next char
                  pi expr4                    ; get 2nd expr
                  pi chksgn                   ; check sign of 2nd
                  lr A,8                      ; save
                  lr 2,A                      ; sign
                  pi exch                     ; switch first into scratch
                  pi chksgn                   ; check sign of 1st expr
                  lisl 2                      ; put 2nd
                  pi pullsr                   ; expression in 22-23
                  lr A,I                      ; see if
                  xs S                        ; exclusive or and
                  as D                        ; add to check for zero
                  bz xp33                     ; branch if we are
                  pi divide                   ; go divide
                  pi pushsr                   ; move
                  pi pull20                   ; result in 20-21
                  ; adjust sign of result
xp35:             clr                         ; see if
                  as S                        ; result is +
                  bm xp33                     ; branch if it isnt
                  lr A,2                      ; see if
                  as 8                        ; signs differ
                  bz xp30                     ; branch if 2 +'s
                  ci '-'                      ; is just one a -
                  bnz xp30                    ; branch if 2 -'s
                  pi chgsgn                   ; change the sign
                  br xp30                     ; continue
                  
                  ; evaluate the input
expr4:            lr K,P                      ; save
                  pi pushrt                   ; return
                  lr H,DC                     ; save TBP
                  dci tab4                    ; function table
                  jmp exec                    ; go look
                  
xp40:             pi testvl                   ; test the value
                  bm xp44                     ; branch if not a var
                  ; check for a string
                  lisl 0                      ; set ISAR
                  lr A,5                      ; get
                  lr 9,A                      ; string
                  lr W,J                      ; flag
                  bm xp43                     ; branch if not a string
                  
                  ; process string
                  pi pushdc                   ; save TBP
                  dci buff                    ; to addr
                  xdc                         ; restore var addr
                  lr H,DC                     ; save var addr
                  clr                         ; zero accum
                  lr W,J                      ; get status
                  bnz $+5                     ; branch if a-z
                  lm                          ; adjust array loc
                  li lo(-2)                   ; get var
                  lr 1,A                      ; into R1
                  li 72                       ; setup max
                  lr 2,A                      ; digit counter
xp41:             ds 2                        ; check length
                  bnz $+5                     ; branch if not too long
                  jmp ahow                    ; error
                  
                  lm                          ; load a char
                  xdc                         ; get buff addr
                  st                          ; store char
                  ni 80H                      ; last char?
                  bnz xp42                    ; branch if last
                  xdc                         ; reset var addr
                  lr A,1                      ; adjust
                  adc                         ; var addr
                  br xp41                     ; continue
                  
xp42:             clr                         ; mark end of string
                  st                          ; of the string
                  pi slen                     ; store length
                  lr DC,H                     ; restore
                  xdc                         ; var addr
                  lr DC,H                     ; var addr
                  lm                          ; load
                  lr I,A                      ; the
                  lm                          ; 1st and 2nd chars
                  ni 7FH                      ; insure high
                  lr I,A                      ; bit is off
                  pi pulldc                   ; restore TBP
                  br xp45                     ; go return
                  
xp43:             xdc                         ; get var addr
                  lm                          ; load the
                  lr I,A                      ; value of
                  lm                          ; the variable
                  lr D,A                      ; into 20-21 lisl 0
                  xdc                         ; restore TBP
                  br xp45                     ; return
                  
xp44:             pi tstnum                   ; see if a number
                  ds 1                        ; number?
                  bz par1                     ; branch if not a number
xp45:             jmp pullrt                  ; return
                  
parn:             lr K,P                      ; save
                  pi pushrt                   ; return
par1:             pi ignbk                    ; get next char
                  ci '('                      ; left hand paren?
                  bnz qwhat                   ; branch if not
                  pi expr                     ; evaluate expression
                  lr A,4                      ; restore character
                  ci ')'                      ; closing paren?
                  bnz qwhat                   ; branch if not found
                  pi skip                     ; inc DC and get next char
                  jmp pullrt                  ; return
                  
qwhat:            pi pushdc                   ; save TBP
awhat:            dci what                    ; what message
error:            pi prtstg                   ; print "WHAT?", "HOW?", or "SORRY"
                  pi pulldc                   ; get TBP
                  li lo(-1)                   ; get
                  adc                         ; pointer to char
                  lr H,DC                     ; in error
                  lm                          ; save
                  lr 5,A                      ; the char
                  clr                         ; put
                  lr DC,H                     ; a zero
                  st                          ; there
                  lisu 3                      ; get currnt
                  lisl 0                      ; in scratch 30
                  lr A,S                      ; see
                  as S                        ; if a minus
                  bp $+5                      ; branch if ge 0
                  jmp inperr                  ; redo input
                  
                  lr A,I                      ; see
                  xs S                        ; exclusive or and
                  as D                        ; add to check for zero
                  bnz $+5                     ; branch if not 0
                  jmp start                   ; restart
                  
                  pi pushsr                   ; value
                  pi pulldc                   ; of currnt in DC
                  lisu 2                      ; reset scratch
                  pi prtln                    ; print the line
                  li lo(-1)                   ; ipto the 0
                  adc                         ; adjust DC
                  lr A,5                      ; put the
                  st                          ; char back
                  li '?'                      ; output
                  lr txdata,A                 ; A
                  pi tty0                     ; ?
                  pi prtstg                   ; print rest of the line
                  jmp start                   ; restart
                  
                  ; find end of line
endcr:            lr K,P                      ; save return
                  pi ignbk                    ; get next char
                  ci 0DH                      ; is it a CR?
                  bnz qwhat                   ; branch if not
                  pk                          ; return
                  
                  ; process a read
rdata:            lr K,P                      ; save return
                  pi pushrt
                  br setrh                    ; process read-data
                  
                  ; stores the right hand
                  ; expression in the variable
setval:           lr K,P                      ; save
                  pi pushrt                   ; return
                  pi char                     ; get next char
                  pi testvl                   ; test the variable
                  bm qwhat                    ; branch if not there
                  pi ignbk                    ; get next char
                  ci '='                      ; get past equal
                  bnz qwhat                   ; branch not there
setrh:            lr A,5                      ; save 1st string flag
                  lr 6,A                      ; in R6
                  clr                         ; clear
                  lr 5,A                      ; string flag
                  xdc                         ; save
                  pi pushdc                   ; variable addr
                  xdc                         ; TBP back in DC0
                  pi expr                     ; evaluate expression
                  xdc                         ; save TBP and get rh var addr
                  pi pulldc                   ; get lh var addr
                  ; string?
                  lr A,5                      ; load
                  lr 9,A                      ; rh
                  lr W,J                      ; string flag
                  lr A,6                      ; load
                  lr 9,A                      ; lh string flag
                  bm set3                     ; branch if rh not a string
                  lr 5,A                      ; save lh string flag
                  lr W,J                      ; and check its status
                  bp set2                     ; branch if a string
set1:             xdc                         ; get TBP
                  jmp qwhat                   ; error
                  
set2:             xdc                         ; save
                  pi pushdc                   ; TBP
                  xdc                         ; get var addr
                  pi buftov                   ; move the string
                  pi pulldc                   ; restore TBP
                  br setr                     ; return
                  
set3:             lr W,J                      ; get lh string flag
                  bp set1                     ; error if a string
set4:             lr A,I                      ; store
                  st                          ; value
                  lr A,D                      ; in
                  st                          ; variable
                  xdc                         ; restore TBP
setr:             jmp pullrt                  ; return
                  
                  ; check sign of number in 20-21
                  ; R8=0 for + and '-' for -
chksgn:           lisl 0                      ; ISAR to 20
                  clr                         ; zero
                  lr 8,A                      ; zero for +
                  as S                        ; add hi order byte
                  bp chg2                     ; branch if 0 or -
chgsgn:           lisl 1                      ; load low
                  lr A,S                      ; order
                  com                         ; two's
                  inc                         ; complement
                  lr D,A                      ; backin 21
                  lr J,W                      ; save status
                  lr A,S                      ; load hi
                  com                         ; complement
                  lr W,J                      ; restore status
                  bnc chg1                    ; branch if no adjust
                  inc                         ; adjust if no carry
chg1:             lr S,A                      ; save in r20
                  li '-'                      ; load a minus
                  lr 8,A                      ; into r8
chg2:             pop                         ; return
                  
                  ; scratch (20-21)-(20-21)-(22-23)
subd:             lisl 3                      ; set ISAR
                  lr A,S                      ; load
                  com                         ; make it
                  inc                         ; a minus
                  lisl 1                      ; get other low order
                  as S                        ; add it
                  lr J,W                      ; save status
                  lr I,A                      ; save 21 minus 23
                  lr A,D                      ; load hi order
                  com                         ; complement
                  lr W,J                      ; restore carry status
                  bnc ncs                     ; branch if there was a carry
                  inc                         ; make 2's complement if no carry
ncs:              lisl 0                      ; set to hi order
                  as S                        ; add hi order
                  lr S,A                      ; save it and set lisl 0
                  pop                         ; return
                  
                  ; scratch (20-21)=(20-21)+(22-23)
                  ; mult is an additional entry
                  ; scratch (20-21)-(22-23)*R3
                  ; 20-21 should be zero for a mult entry
mtply:            clr                         ; check for
                  as 7                        ; a zero
                  br mul1                     ; multiplier (1383)
                  
addd:             lis 1                       ; for add
                  lr 7,A                      ; for add entry override mult
mult:             lisl 3                      ; set ISAR
                  lr A,S                      ; load 23
                  lisl 1                      ; add
                  as S                        ; 21 to it
                  lr I,A                      ; save
                  lr A,D                      ; load 22
                  lnk                         ; add carry
                  lisl 0                      ; add
                  as S                        ; 20
                  lr S,A                      ; save new 20
                  ds 7                        ; dec multiplier
mul1:             bnz mult                    ; branch if a multiply
                  clr                         ; reset
                  as S                        ; status
                  pop                         ; return with LISL 0
                  
                  ; divide scratch (20-21) by (22-23)
                  ; result in scratch (24-25)
                  ; remainder in scratch (20-21)
divide:           lr K,P                      ; save return
                  pi pushrt                   ; save return
                  pi push20                   ; save 20-21
                  lr A,I                      ; set
                  lr D,A                      ; 21=20
                  clr                         ; set
                  lr S,A                      ; 20=0
                  pi dv1                      ; do 1st pass
                  lr A,1                      ; set
                  lr S,A                      ; scratch 24=1st digit
                  lisl 1                      ; save
                  lr A,D                      ; 21
                  lr 1,A                      ; in R1
                  pi pullsr                   ; restore (20-21)
                  lr A,1                      ; setup remainder
                  lr S,A                      ; in 20
                  br dv2                      ; branch around entry
                  
dv1:              lr K,P                      ; save return
                  pi pushrt                   ; push return
dv2:              li lo(-1)                   ; set
                  lr 1,A                      ; digit counter-1
dv3:              lr A,1                      ; load and
                  inc                         ; increment
                  lr 1,A                      ; digit
                  pi subd                     ; subtract
                  bp dv3                      ; branch if not lt 0
                  pi addd                     ; adjust for past zero
                  lisl 5                      ; load low
                  lr A,1                      ; order result into
                  lr D,A                      ; scratch 25 and LISL 24
                  jmp pullrt                  ; return
                  
                  ; compare stack top to scratch 20-21
                  ; stack top < 20-21 use bnc(-)
                  ; stack top = 20-21 use bz
                  ; stack top > 20-21 use bz and then bcc+
                  ; pulls value off of stack
comp:             lr H,DC                     ; save dc
comx:             lisl 0                      ; get low ISAR
comt:             lr DC,Q                     ; get stack pointer
                  lr A,I                      ; load hi order byte
                  cm                          ; stack hi - 20
                  bnz com1                    ; branch if not equal
                  lr A,D                      ; load low
                  cm                          ; stack low-21
com1:             lr J,W                      ; save status
                  lr DC,Q                     ; load stack addr
                  lm                          ; take last item
                  lm                          ; off of the stack
                  lr Q,DC                     ; save new pointer
                  lr DC,H                     ; restore dc
                  lisl 0                      ; reset ISAR
                  pop                         ; return
                  
skip:             lm                          ; skip this byte
char:             lr H,DC                     ; save dc
                  lm                          ; get next char
                  ci ' '                      ; blank?
                  bz char                     ; branch if a blank
                  lr 4,A                      ; get last dc
                  lr DC,H                     ; get DC0 of loaded byte
                  pop                         ; return
                  
                  ; find next non blank char starting at DC
ignbk:            lr H,DC                     ; save TBP
ign1:             lm                          ; load a char (1470)
                  ci ' '                      ; see if a blank (1471)
                  bz ign1                     ; branch if a blank
                  lr 4,A                      ; save character
                  pop                         ; return with char in accum
                  
                  ; exchange top of stack & ISAR
                  ; r7-8 also set to scratch value
exch:             lisl 0                      ; set ISAR
                  lr K,P                      ; save return
                  lr A,I                      ; hi
                  lr 6,A                      ; in R6
                  lr A,D                      ; low
                  lr 7,A                      ; in R7
                  pi pullsr                   ; put stack in scratch
                  lisu 0                      ; now
                  lisl 6                      ; put
                  pi pushsr                   ; scratch on the stack
                  lisu 2                      ; reset
                  lisl 0                      ; ISAR
                  pk                          ; return
                  
                  ; move 20-21 to 22-23
mv2021:           lisl 0                      ; set ISAR
                  lr A,I                      ; load 20
                  lisl 2                      ; set to 22
                  lr D,A                      ; into 22
                  lr A,I                      ; load 21
                  lisl 3                      ; set to 23
                  lr I,A                      ; into 23
                  lisl 0                      ; reset ISAR
                  pop                         ; return

                  ; move data from hi to low core
                  ; DC1=addr+1 of last byte stored
mvup:             lr H,DC                     ; save from
                  lr DC,Q                     ; get stack addr
                  lr A,HU                     ; compare
                  cm                          ; hi byte
                  bnz mv1                     ; branch if not eq
                  lr A,HL                     ; compare low
                  cm                          ; byte
                  bz mv2                      ; branch if the end
mv1:              lr DC,H                     ; restore from
                  lm                          ; load a byte
                  xdc                         ; get to
                  st                          ; store it
                  xdc                         ; restore from
                  br mvup                     ; get next byte
                  
mv2:              pop                         ; return
                  
                  ; DC0=from, DC1=to, stack end=top
                  ; the top of the stack is compared
                  ; to the 'from' addr after each move.
                  ; move data from low to hi core
                  ; H will have the addr of the last byte
                  ; that was moved
mvdown:           lr H,DC                     ; save DC
                  lr DC,Q                     ; stack top addr
                  lr A,HU                     ; compare
                  cm                          ; 1st byte
                  bnz mvd1                    ; branch if not equal
                  lr A,HL                     ; compare
                  cm                          ; 2nd byte
mvd1:             lr J,W                      ; save status
                  lr DC,H                     ; restore present from
                  lm                          ; load a byte
                  xdc                         ; get to
                  st                          ; store
                  li lo(-2)                   ; adjust
                  adc                         ; to
                  xdc                         ; adjust
                  adc                         ; from
                  lr W,J                      ; restore status
                  bnz mvdown                  ; branch if not the end
                  pop                         ; return
                  
                  ; move a string from buff to the
                  ; variable addr.  DC0=var addr
                  ; TBP is on the stack
buftov:           lr K,P                      ; save return
                  clr                         ; zero accum
                  lr W,J                      ; get status
                  bnz bu0                     ; branch if a-z
                  lm                          ; adjust array addr
                  lisl 6                      ; set ISAR to @ type
                  pi pushsr                   ; put TXTU on the stack
                  li lo(-2)                   ; get var
bu0:              lr 7,A                      ; adjust (1557)
                  xdc                         ; save var addr (1558)
                  bz bu1                      ; branch if @
                  dci strlgh                  ; put the
                  pi pushdc                   ; end addr of
bu1:              pi pull20                   ; a-z in 20-21
                  lis 0DH                     ; set CR as
                  lr 1,A                      ; the terminator
                  dci buff                    ; get the
                  pi char                     ; first char
                  li 72                       ; setup
                  lr 2,A                      ; length counter
bu2:              lm                          ; load a char
                  lr 6,A                      ; save it
                  xs 1                        ; (CR)?
                  xdc                         ; get var addr
                  bz bu7                      ; branch if end of string
                  clr                         ; see if
                  as 6                        ; a nul end
                  bz bu7                      ; was used
                  pi pushdc                   ; put addr on stack
                  pi comt                     ; tatu-@ or strlgh-(a-z)
                  lr A,5                      ; var type
                  lr 9,A                      ; into R9
                  bnc bu5                     ; branch if compare was -
                  ; if @ we are ok
                  lr W,J                      ; var type
                  bnz bu4                     ; branch if a-z, an error
                  br bu6                      ; continue
                  
                  ; if a-z we are ok
bu5:              lr W,J                      ; var type
                  bz bu4                      ; branch if @, an error
bu6:              lr A,6                      ; restore char
                  sl 1                        ; make sure
                  sr 1                        ; no _false end
                  lr 8,A                      ; save the char
                  lr H,DC                     ; and the addr
                  st                          ; store char
                  lr A,7                      ; adjust
                  adc                         ; var addr
                  xdc                         ; restore from
                  ds 2                        ; check string length
                  bnz bu2                     ; branch if more room
bu4:              jmp ahow                    ; no more room

bu7:              lr A,8                      ; restore last char
                  lr DC,H                     ; and its addr
                  oi 80H                      ; of string
                  st                          ; flag
                  lr A,2                      ; see if
                  sr 1                        ; the string
                  sl 1                        ; length is
                  xs 2                        ; odd or even
                  bz bu8                      ; branch if even
                  lr A,7                      ; adjust
                  adc                         ; var addr
                  lr A,8                      ; load the last char
                  st                          ; odd,fill the word
bu8:              pi slen                     ; get the length
                  pk                          ; return
                  
                  ; R2 has a decremented counter
                  ; complement it and add start le
slen:             lr A,2                      ; make
                  com                         ; counter
                  inc                         ; negative
                  ai 72                       ; add original length
                  dci strlgh                  ; store
                  st                          ; length
                  pop                         ; return
                  
                  ; scratch 36-37 lopvar goes on
save:             xdc                         ; save TBP
                  lr K,P                      ; save return
                  dci skend                   ; stack limit addr
                  pi pushdc                   ; save end of stack
                  lisu 1                      ; set ISAR
                  lisl 6                      ; to Q regs
                  pi comt                     ; skip LISL 0
                  bm sav1                     ; branch if room left
                  xdc                         ; get TBP
                  jmp qsorry                  ; process error
                  
sav1:             lisu 3                      ; setup ISAR
                  lisl 6                      ; set ro lopva
                  lr A,I                      ; loop variable addr
                  xs S                        ; xor and add
                  as D                        ; to check for zero
                  bz sav3                     ; branch if zero
                  lr DC,Q                     ; get stack addr(1644)
                  li lo(-8)                   ; make room(1645)
                  adc                         ; for 4 items on the stack
                  lr Q,DC                     ; save stack
                  lisu 4                      ; save the rest
                  lisl 0                      ; of the variables
                  lis 8                       ; setup
                  lr 1,A                      ; loop
sav2:             lr A,I                      ; save
                  st                          ; for variables
                  ds 1                        ; dec counter
                  bnz sav2                    ; loop if not done
                  lisu 3                      ; put
                  lisl 6                      ; lopvar on
sav3:             pi pushsr                   ; on the stack top
                  xdc                         ; restore TBP
                  lisu 2                      ; restore ISAR
                  pk                          ; return
                  
                  ; restore for variables
                  ; lopvar is on the stack top
restor:           lisu 3                      ; set
                  lisl 6                      ; ISAR
                  lr DC,Q                     ; get stack pointer
                  lm                          ; restore
                  lr I,A                      ; lopvar
                  lm                          ; from
                  lr D,A                      ; stack top
                  xs S                        ; xor and
                  as S                        ; add to see if zero
                  bz res2                     ; branch if zero
refor:            lisu 4                      ; set
                  lisl 0                      ; ISAR
                  lis 8                       ; setup
                  lr 1,A                      ; loop
res1:             lm                          ; load
                  lr I,A                      ; loop variables
                  ds 1                        ; dec counter
                  bnz res1                    ; loop if not done
res2:             lr Q,DC                     ; restore stack
                  lisu 2                      ; reset ISAR
                  pop                         ; return

                  ; push DC on to stack
pushdc:           lr H,DC                     ; save current DC
                  lr DC,Q                     ; stack pointer
                  li lo(-2)                   ; the stack pointer
                  adc                         ; 2 bytes
                  lr Q,DC                     ; save stack pointer
                  lr A,HU                     ; save
                  st                          ; hi
                  lr A,HL                     ; save
                  st                          ; low
                  lr DC,H                     ; restore DC
                  pop                         ; return

                  ; pull DC from stack
pulldc:           lr DC,Q                     ; back up
                  lm                          ; load
                  lr HU,A                     ; hi
                  lm                          ; low
                  lr HL,A                     ; load
                  lr Q,DC                     ; save new pointer
                  lr DC,H                     ; into DC
                  pop                         ; return

                  ; save 2 scratch bytes on the stack
                  ; lisl remains the same
push20:           lisl 0                      ; special entry for 20-21
pushsr:           lr H,DC                     ; save DC
                  lr DC,Q                     ; get stack pointer
                  li lo(-2)                   ; back up two
                  adc                         ; bytes
                  lr Q,DC                     ; save stack pointer
                  lr A,I                      ; load 1st byte
                  st                          ; save it
                  lr A,D                      ; load 2nd byte
                  st                          ; save
                  lr DC,H                     ; restore DC
                  pop                         ; return
                  
                  ; pull 2 bytes from stack into scratch
                  ; lisl remains the same
pull20:           lisl 0                      ; special entry for 20-21
pullsr:           lr H,DC                     ; save DC
                  lr DC,Q                     ; load stack pointer
                  lm                          ; load
                  lr I,A                      ; into scratch
                  lm                          ; load 2nd
                  lr D,A                      ; into scratch
                  lr Q,DC                     ; save pointer
                  lr DC,H                     ; restore DC
                  pop                         ; return
                  
                  ; save return (KU-KL) on stack
                  ; calling format is
                  ; lr K,P
                  ; pi pushrt
pushrt:           lr H,DC                     ; save DC
                  lr DC,Q                     ; get stack pointer
                  li lo(-2)                   ; back up 2
                  adc                         ; bytes to last entry
                  lr Q,DC                     ; save pointer
                  lr A,KU                     ; store
                  st                          ; high
                  lr A,KL                     ; store
                  st                          ; low
                  lr DC,H                     ; restore DC
                  pop                         ; return
                  
                  ; pull return from stack and return
                  ; to the addr that was pulled from the
                  ; stack with a pk
pullrt:           lr H,DC                     ; save DC
                  lr DC,Q                     ; get stack pointer
                  lm                          ; load hi
                  lr KU,A                     ; order into KU
                  lm                          ; load low
                  lr KL,A                     ; order into KL
                  lr Q,DC                     ; save updated pointer
                  lr DC,H                     ; restore DC
                  pk                          ; return to pulled return addr

                  ; pulls return off stack into K
poprt:            lr H,DC                     ; save DC
                  lr DC,Q                     ; get stack pointer
                  lm                          ; load
                  lr KU,A                     ; the
                  lm                          ; return
                  lr KL,A                     ; addr
                  lr Q,DC                     ; restore it
                  lr DC,H                     ; restore DC
                  pop                         ; return

                  ; call a user routine
usr:              pi expr                     ; get addr
                  pi pushdc                   ; save TBP
                  ; called routine should save return
                  lr A,I                      ; load hi call byte
                  lr KU,A                     ; into KU
                  lr A,D                      ; low call byte
                  lr KL,A                     ; into KL
                  pk                          ; call the routine
                  
                  pi pulldc                   ; restore TBP
                  jmp fin                     ; finish up

                  ; put a value in memory
                  ; poke addr,value
poke:             pi expr                     ; get poke addr
                  pi push20                   ; save it
                  pi ignbk                    ; get next char
                  ci ','                      ; comma?
                  bnz pok1                    ; branch if not a comma
                  pi expr                     ; get next expr
                  xdc                         ; save TBP
                  pi pulldc                   ; get poke addr into DC
                  lisl 1                      ; store
                  lr A,D                      ; the
                  st                          ; value (2nd byte of the word)
                  xdc                         ; restore TBP
                  jmp fin                     ; finish up
                  
pok1:             jmp qwhat                   ; error
                  
                  
                  ; output a value 0-255 to port 1 which controls the LEDs
                  ; syntax: PORT1 = value
port1:            pi ignbk                    ; get the next character
                  ci '='                      ; is it equals sign?
                  bnz port1a                  ; branch if not equals sign
                  pi expr                     ; else, get the value to output to the LED port
                  pi pushdc                   ; save the TBP
                  lr A,I                      ; load the hi byte of the value to be output to the LED port
                  ci 0                        ; is the hi byte zero?
                  bnz port1a                  ; branch if the value to be output to the LED port is greater than 255
                  lr A,D                      ; else, load the low byte of the value to be output to the LED port
                  outs ledport                ; output the low byte of the value to the LED port
                  pi pulldc                   ; restore the TBP
                  jmp fin                     ; finish up

port1a:           clr
                  lr 8,A                      ; clear R8
                  jmp qwhat                  
                  
                  ; process 'literal'
                  ; put into buff and 1st 2 chars in
apost:            li '\''                     ; setup
                  br aq1                      ; the
                  
quote:            li '"'                      ; literal
aq1:              lr 1,A                      ; end char
                  xdc                         ; save TBP
                  dci buff                    ; get target
                  li 72                       ; get
                  lr 2,A                      ; max length
aq2:              xdc                         ; get TBP
                  lm                          ; load a char(1818)
                  xdc                         ; get present buff addr
                  lr H,DC                     ; save present buff addr
                  st                          ; store char
                  xs 1                        ; last one?
                  bz aq3                      ; branch if it is
                  ds 2                        ; room left?
                  br aq2                      ; continue
                  
aq3:              lr DC,H                     ; a zero terminator
                  st                          ; to mark end of string
                  dci buff                    ; put the
                  lisl 0                      ; first
                  lm                          ; and
                  lr 4,A                      ; second
                  lr I,A                      ; chars
                  lm                          ; in
aq4:              lr S,A                      ; 20-21
                  xs 1                        ; was there just
                  lr A,4                      ; one char?
                  bz aq4                      ; if only 1 repeat it in 21
                  lisl 0                      ; reset ISAR
                  pi slen                     ; setup string length
                  lis 1                       ; set status
                  lr 5,A                      ; to string
                  xdc                         ; restore TBP
                  pi char                     ; get next char
                  jmp pullrt                  ; return

                  ; get string length of variable
                  ; if the arg=0 get last length
len:              pi parn                     ; evaluate arg
                  xdc                         ; save TBP, get var addr
                  clr                         ; zero hi
                  lr 5,A                      ; zero string flag
                  lr I,A                      ; byte
                  dci strlgh                  ; put the
                  lm                          ; string length
                  lr D,A                      ; into 20-21
                  xdc                         ; restore TBP
                  jmp pullrt                  ; return

                  ; absolute value
abs:              pi parn                     ; abs(expr)
                  pi chksgn                   ; check sign
                  lr A,S                      ; see if
                  ci 80H                      ;-32768
                  bz jmphow                   ; branch if it is
                  jmp pullrt                  ; return

                  ; random number
rnd:              pi parn                     ; rnd(expr)
                  lr A,S                      ; expr
                  as S                        ; must be plus
                  bm jmphow                   ; branch if -
                  lr A,I                      ; see if zero
                  xs S                        ; by xoring
                  as D                        ; and adding
                  bz jmphow                   ; branch if zero
                  pi pushsr                   ; save expr
                  xdc                         ; and TBP
                  dci ranpnt                  ; get last addr
                  pi pushdc                   ; on the stack
                  lm                          ; load contents
                  lr HU,A                     ; save hi addr
                  lr I,A                      ; of
                  lm                          ; random memory
                  lr HL,A                     ; save low addr
                  lr D,A                      ; into 20-21
                  pi comx                     ; skip lr H,DC
                  bc rn1                      ; branch if not last addr
                  dci start                   ; wrap around addr
rn1:              lm                          ; put
                  lr I,A                      ; content of
                  lm                          ; addr in ranpnt
                  lr I,A                      ; into 20-21
                  lr H,DC                     ; new ranpnt addr addr
                  dci ranpnt                  ; get target
                  lr A,HU                     ; store
                  st                          ; it
                  lr A,HL                     ; in
                  st                          ; ranpnt
                  pi pullsr                   ; arg into 22-23
                  pi chksgn                   ; check sign of random number
                  pi divide                   ; rannum/input #
                  lisl 1                      ; add
                  lr A,S                      ; one
                  inc                         ; to the
                  lr D,A                      ; remainder(1905)
                  lr A,S                      ; add in
                  lnk                         ; any
                  lr S,A                      ; carry
                  xdc                         ; restore TBP
                  jmp pullrt                  ; return

                  ; val=PEEK(addr)
                  ; set val to the byte at addr
peek:             pi parn                     ; go get addr in 20-21
                  xdc                         ; save TBP
                  lr A,I                      ; load
                  lr HU,A                     ; peek
                  lr A,S                      ; addr
                  lr HL,A                     ; into
                  lr DC,H                     ; DC
                  lm                          ; load byte
                  lr D,A                      ; into 21
                  clr                         ; zero
                  lr S,A                      ; 20
                  xdc                         ; restore TBP
                  jmp pullrt                  ; return

                  ; TAB(x) space over to column x
tab:              pi parn                     ; evaluate the expression
                  lr A,I                      ; see if
                  xs S                        ; zero by xor
                  as S                        ; and adding
                  bz jmphow                   ; branch if zero an error
                  lr A,D                      ; load the number of blanks to print
                  lr 8,A                      ; into rp
ta1:              pi pblk                     ; print a blank
                  ds 8                        ; dec loop counter
                  bnz ta1                     ; branch if more
                  clr                         ; setup dummy
                  br ch1                      ; string for print
                  
jmphow:           jmp qhow                    ; error

                  ; CHR(x) output ASCII code x
chr:              pi expr                     ; get ascii
                  lisl 1                      ; code
                  lr A,D                      ; into
ch1:              lr H,DC                     ; save TBP
                  dci buff                    ; buff
                  st                          ; and
                  clr                         ; mark
                  st                          ; end
                  inc                         ; and
                  lr 5,A                      ; set string flag
                  lr DC,H                     ; restore TBP
                  jmp pullrt                  ; return
                  
h8000:            equ 8000H                   
tab1:             equ $                       ; direct commands
                  db "LIST"
                  dw list+h8000
                  db "NEW"
                  dw new+h8000
                  db "RUN"
                  dw run+h8000
                  db "MON"
                  dw mon+h8000
tab2:             equ $                       ; direct/statement
                  db "LET"
                  dw let+h8000
                  db "IF"
                  dw if+h8000
                  db "GOTO"
                  dw goto+h8000
                  db "FOR"
                  dw for+h8000
                  db "NEXT"
                  dw next+h8000
                  db "GOSUB"
                  dw gosub+h8000
                  db "RETURN"
                  dw return+h8000
                  db "PRINT"
                  dw print+h8000
                  db "INPUT"
                  dw input+h8000
                  db "THEN"
                  dw goto+h8000               ; process like goto
                  db "REM"                    ; (1992)
                  dw rem+h8000                ; (1993)
                  db "READ"
                  dw read+h8000
                  db "DATA"
                  dw data+h8000
                  db "USR"                    ; user called routine
                  dw usr+h8000
                  db "POKE"                   ; POKE x,y
                  dw poke+h8000
                  db "PORT1"
                  dw port1+h8000               ; OUT x,y
                  db "RESTORE"
                  dw restore+h8000
                  db "STOP"
                  dw stop+h8000
                  dw deflt+h8000
tab4:             equ $                       ; functions
                  db "RND"                    ; RND(x)
                  dw rnd+h8000
                  db "ABS"                    ; ABS(x)
                  dw abs+h8000
                  db "PEEK"                   ; PEEK in to core
                  dw peek+h8000
                  db "LEN"                    ; get the string length
                  dw len+h8000
                  db '\''                     ; 'literal'
                  dw apost+h8000
                  db '"'                      ; "literal"
                  dw quote+h8000
                  db "TAB"                    ; TAB(x)
                  dw tab+h8000
                  db "CHR"                    ; CHR(x)
                  dw chr+h8000
                  dw xp40+h8000
tab5:             equ $                       ; 'TO' in 'FOR'
                  db "TO"
                  dw fr1+h8000
                  dw qwhat+h8000
tab6:             equ $                       ; 'STEP' in 'FOR'
                  db "STEP"
                  dw fr2+h8000
                  dw fr3+h8000
tab8:             equ $                       ; relational operators
                  db ">="                     ; greater than or equal to
                  dw xp11+h8000
                  db "#"                      ; not equal to
                  dw xp12+h8000
                  db ">"                      ; greater than
                  dw xp13+h8000
                  db "="                      ; equal
                  dw xp15+h8000
                  db "<="                     ; less than or equal to
                  dw xp14+h8000
                  db "<"                      ; less than
                  dw xp16+h8000
                  dw xp17+h8000
                  
prompt:           db "READY"                  
                  db 0DH

tty0              lr A,1                      ; output byte in A
                  ci 0DH                      ; is it CR?
                  bz ttcr                     ; branch if yes

; output a character to the serial port
tty1:             lr H,DC                     ; save current DC
                  lr DC,Q                     ; stack pointer
                  li lo(-2)                   ; the stack pointer
                  adc                         ; 2 bytes
                  lr Q,DC                     ; save stack pointer
                  lr A,HU                     ; save
                  st                          ; hi
                  lr A,HL                     ; save
                  st                          ; low
                  lr DC,H                     ; restore DC

ltty1:
putchar:          lis 8                       
                  lr bitcnt,A
                  li 01H
                  outs serialport             ; send the start bit
                  outs serialport
                  outs serialport
                  li 247                      ; wait 1 bit time
                  inc
                  bnz $-1

putchar1:         lr A,txdata                 ; send 8 data bits
                  com
                  ni 01H
                  outs serialport
                  li 248
                  inc
                  bnz $-1
                  lr A,txdata
                  sr 1
                  lr txdata,A
                  ds bitcnt
                  bnz putchar1

                  lr A,bitcnt
                  nop
                  nop
                  nop
                  outs serialport             ; send the stop bit
                  li 252
                  inc
                  bnz $-1

                  lr DC,Q                     ; back up
                  lm                          ; load
                  lr HU,A                     ; hi
                  lm                          ; low
                  lr HL,A                     ; load
                  lr Q,DC                     ; save new pointer
                  lr DC,H                     ; into DC
                  pop                         ; return

; input a character from the serial port
ttyi:             lr H,DC                     ; save current DC
                  lr DC,Q                     ; stack pointer
                  li lo(-2)                   ; the stack pointer
                  adc                         ; 2 bytes
                  lr Q,DC                     ; save stack pointer
                  lr A,HU                     ; save
                  st                          ; hi
                  lr A,HL                     ; save
                  st                          ; low
                  lr DC,H                     ; restore DC

tyi1:
getchar:          ins serialport              ; wait for the start bit
                  bp getchar
                  lis 8
                  lr bitcnt,A
                  li 242
                  inc
                  bnz $-1

; get 8 data bits
getchar1:         lr A,rxdata                 
                  sr 1
                  lr rxdata,A
                  ins serialport              ; read the serial input
                  ins serialport
                  com
                  ni 80H
                  as rxdata
                  lr rxdata,A
                  li 249
                  inc
                  bnz $-1
                  nop
                  ds bitcnt
                  bnz getchar1
                  li 246
                  inc
                  bnz $-1

                  lr DC,Q                     ; back up
                  lm                          ; load
                  lr HU,A                     ; hi
                  lm                          ; low
                  lr HL,A                     ; load
                  lr Q,DC                     ; save new pointer
                  lr DC,H                     ; ino DC

                  lr A,1                      ; load lead character
                  ci 'a'-1                    ; if a-z
                  bc tyi2
                  ci 'z'
                  bnc tyi2
                  ni 0DFH                     ; convert to upper case
                  lr rxdata,A                 ; replace character in buffer
tyi2:             pop                         ; return

; output CR,LF to the serial port
ttcr:             lr K,P                      ; save return address
                  lis 0DH                     ; load CR in A
                  lr txdata,A                 ; store in transmit buffer
                  pi tty1                     ; call tty1
                  lis 0AH                     ; load LF in A
                  lr txdata,A                 ; store transmit buffer
                  pi tty1                     ; call tty1
                  pk                          ; return

mon               jmp 1000H                   

tinybasictxt      db CLS                      
                  db "tiny BASIC for the MK3850\r"
                  db "Assembled on ",DATE," at ",TIME,"\r\n",0

                  org ramtop
ranpnt:           equ $                       ; random number pointer
                  org ranpnt+2                ; random number pointer
txtb:             equ $                       ; begin of text area
                  org 0F002H                  ; change in multiples of 256 bytes
txte              equ $                       ; end of text area
varbgn:           equ $                       ; @(0) location
                  org varbgn+54
strlgh:           equ $                       ; string length
                  org strlgh+1
buff:             equ $                       ; buffer for 72 input bytes
                  org buff+73
skend:            equ 0FE80H                  ; end of stack
stack:            equ 0FF00H                  ; begin of stack
;---------------- end of tiny BASIC ---------------------------------------

;=========================================================================
; Monitor for the 3850 Single Board Computer.
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
;=========================================================================

; constants
ESCAPE            equ 1BH                     
ENTER             equ 0DH                     

; port addresses
serialport        equ 00H
ledport           equ 01H

; scratchpad RAM registers
bitcount          equ 00H                     
saveA             equ 02H                     
saveIS            equ 03H                     
hexbyte           equ 04H                     
number            equ 04H                     
errors            equ 04H                     
portaddr          equ 05H                     
bytecnt           equ 05H                     
checksum          equ 05H                     
digit             equ 05H                     
zeroflag          equ 06H                     
portval           equ 06H                     
linecnt           equ 06H                     
recordlen         equ 06H                     
rxbuffer          equ 07H                     
txbuffer          equ 08H                     

; executable RAM addresses
patch             equ 0FE00H                  

                  org 1000H
;=======================================================================
; monitor (invoked by BASIC 'MON' command) starts here
;=======================================================================
                  clr
                  outs serialport             ; turn off yellow LEDs
                  outs ledport                ; set serial input and output lines high (idle or MARK)
                  
monitor:          dci titletxt                
                  pi putstr                   ; print the title
monitor1:         dci menutxt                 
                  pi putstr                   ; print the menu
monitor2:         dci prompttxt               
                  pi putstr                   ; print the input prompt
monitor3:         pi getc                     ; get the command character from the serial port
                  lr A,rxbuffer               ; retrieve the character from the rx buffer
                  ci 'a'-1
                  bc monitor4                 ; branch if character is < 'a'
                  ci 'z'
                  bnc monitor4                ; branch if character is > 'z'
                  ai -20H                     ; else, subtract 20H to convert lowercase to uppercase
                  lr rxbuffer,A               ; save the command in 'rxbuffer'

monitor4:         dci cmdtable                
monitor5:         lr A,rxbuffer               ; get the command from the rx buffer
                  cm                          ; compare the command from the rx buffer to the entry from the table, increment DC
                  bz monitor6                 ; branch if a match found
                  lm                          ; load hi byte of address. increment DC
                  lm                          ; load lo byte of address. increment DC
                  lm                          ; load next command from the table
                  ci 0                        ; is it zero?
                  bz monitor1                 ; end of table found. go display menu
                  li -1
                  adc                         ; else decrement DC
                  br monitor5                 ; go try the next table entry

monitor6:         lm                          ; load hi byte of address from 'cmdtable' into A, increment DC
                  lr QU,A                     ; load hi byte of address from A into QU
                  lm                          ; load lo byte of address from 'cmdtable' into A
                  lr QL,A                     ; load lo byte of address from A into QL
                  lr P0,Q                     ; jump to address from 'cmdtable'

cmdtable          db 'B'                      
                  dw return2BASIC
                  db 'D'
                  dw display
                  db 'E'
                  dw examine
                  db 'H'
                  dw dnload
                  db 'I'
                  dw portinput
                  db 'J'
                  dw jump
                  db 'O'
                  dw portoutput
                  db 'S'
                  dw scratch
                  db 'X'
                  dw xamine
                  db ':'
                  dw dnload
                  db 0                        ; end of table
                  
;=======================================================================
; return to the tiny BASIC interpreter
;=======================================================================
return2BASIC:     dci clearscrntxt            ; clear screen              
                  pi putstr                 
                  jmp start

;=======================================================================
; display the contents of one page of memory in hex and ASCII
;=======================================================================
display:          dci addresstxt              
                  pi putstr                   ; print the string  to prompt for RAM address
                  pi get4hex                  ; get the starting address
                  bnc display1                ; branch if not ESCAPE
                  jmp monitor2                ; else, return to menu

display1:         dci column2txt               
                  pi putstr
                  lr A,HL
                  ni 0F0H                     ; address starts on an even boundry
                  lr HL,A
                  lr DC,H                     ; move the address from the 'get4hex' function into DC
                  li 16
                  lr linecnt,A                ; 16 lines

; print the address at the start of the line
display2:         lr H,DC                     ; save DC in H
                  lr A,HU                     ; load HU into A
                  lr hexbyte,A                ; save it in 'hexbyte' for the 'print2hex' function
                  pi print2hex                ; print the most significant byte of the address
                  lr A,HL                     ; load HL into A
                  lr hexbyte,A                ; save it in 'hexbyte' for the 'print2hex' function
                  pi print2hex                ; print the least significant byte of the address
                  li '-'
                  lr txbuffer,A                 
                  pi putc                     ; print '-' between address and first byte

; print 16 hex bytes
                  li 16
                  lr bytecnt,A                ; 16 hex bytes on a line
display3:         lm                          ; load the byte from memory into A, increment DC
                  lr hexbyte,A                ; save it in 'hexbyte' for the 'print2hex' function
                  pi print2hex                ; print the data byte at that address
                  pi space                    ; print a space between bytes
                  ds bytecnt
                  bnz display3                ; loop until all 16 bytes are printed

; print 16 ascii characters
                  lr DC,H                     ; recall the address from H
                  li 16
                  lr bytecnt,A                ; 16 characters on a line
display4:         lm                          ; load the byte from memory into A, increment A
                  ci 7FH
                  bnc display5                ; branch if character is > 7FH
                  ci 1FH
                  bnc display6                ; branch if character is > 1FH
display5:         li '.'                      ; print '.' for bytes 00-1FH and 7H-FFH
display6:         lr txbuffer,A               ; store the character in 'txbuffer' for the 'putc' function
                  pi putc                     ; print the character
                  ds bytecnt
                  bnz display4                ; loop until all 16 characters are printed

; finished with this line
                  pi newline
                  ds linecnt
                  bnz display2                ; loop until all 16 lines are printedgo do next line
                  pi newline                  ; start on a new line
                  jmp monitor2

;=======================================================================
; examine/modify memory contents.
; 1. prompt for a memory address.
; 2. display the contents of that memory address
; 3. wait for entry of a new value to be stored at that memory address.
; 4. ENTER key leaves memory unchanged, increments to next memory address.
; 5. ESCAPE key exits.
;=======================================================================
examine:          dci addresstxt              
                  pi putstr                   ; print the string  to prompt for RAM address
                  pi get4hex                  ; get the RAM address
                  bnc examine2                ; branch if not ESCAPE key
                  jmp monitor2                ; else, return to monitor
examine2:         pi newline                  
                  lr DC,H                     ; move the address from the 'get4hex' function into DC

; print the address
examine3:         lr H,DC                     ; save DC in H
                  lr A,HU                     ; load HU into A
                  lr hexbyte,A                ; save it in 'hexbyte' for the 'print2hex' function
                  pi print2hex                ; print the most significant byte of the address
                  lr A,HL                     ; load HL into A
                  lr hexbyte,A                ; save it in 'hexbyte' for the 'print2hex' function
                  pi print2hex                ; print the least significant byte of the address
                  pi space

; get the byte from memory
                  lr H,DC                     ; save DC in H
                  lm                          ; load the byte from memory into A, increment DC
                  lr hexbyte,A                ; save it in 'hexbyte' for the 'print2hex' function
                  pi print2hex                ; print the data byte at that address
                  pi space                    ; print a space
                  lr DC,H                     ; restore DC

; get a new value to store in memory
                  pi get2hex                  ; get a new new data byte
                  lr A,rxbuffer               ; load the byte from the 'get2hex' function into A
                  bnc examine4                ; branch if the byte from 'het2hex' is not a control character
                  ci ENTER                    ; was the input ENTER?
                  lr A,hexbyte                ; recall the original value stored at this memory address
                  bz examine4                 ; branch if the input was ENTER
                  jmp monitor2                ; if not ENTER, the input must have been ESCAPE so return to monitor

; store the byte in memory
examine4:         st                          ; store the byte in RAM, increment DC
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
; Note:  when using Teraterm to "send" a hex file, make sure that Teraterm
; is configured for a transmit delay of 1 msec/char and 10 msec/line.
;=======================================================================
dnload:           clr                         
                  lr errors,A                 ; clear the checksum error count
                  lr A,rxbuffer               ; retrieve the command from 'rxbuffer'
                  ci ':'                      ; was the command that invoked this function ':'?
                  bz dnload3                  ; if so, the start character was already received. skip ahead
                  dci waitingtxt
                  pi putstr                   ; else, prompt for the HEX download
dnload1:          pi getc                     ; get a character from the serial port
                  lr A,rxbuffer               ; retrieve the character from the rx buffer
                  ci ESCAPE                   ; is it ESCAPE?
                  bnz dnload2                 ; not escape, continue below
                  jmp monitor2                ; jump back to the menu if ESCAPE

dnload2:          ci ':'                      ; is the character the start of record character ':'?
                  bnz dnload1                 ; if not, go back for another character

; start of record character ':' has been received, now get the record length
dnload3:          pi getbyte                  ; get the record length
                  lr A,rxbuffer
                  ci 0                        ; is the record length zero?
                  bz dnload6                  ; branch if the record length is zero (last record)
                  lr recordlen,A              ; else, save the record length
                  lr checksum,A               ; add it to the checksum

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
                  lr DC,H                     ; load the record address into DC

; get the record type
                  pi getbyte                  ; get the record type
                  lr A,rxbuffer
                  as checksum
                  lr checksum,A

; download and store data bytes...
dnload4:          pi getbyte                  ; get a data byte
                  lr A,rxbuffer
                  st                          ; store the data byte in memory [DC]. increment DC
                  as checksum
                  lr checksum,A
                  ds recordlen
                  bnz dnload4                 ; loop back until all data bytes for this record have been received

; since the record's checksum byte is the two's complement and therefore the additive inverse
; of the data checksum, the verification process can be reduced to summing all decoded byte
; values, including the record's checksum, and verifying that the LSB of the sum is zero.
                  pi getbyte                  ; get the record's checksum
                  lr A,rxbuffer
                  as checksum
                  li '.'
                  bz dnload5                  ; zero means checksum OK
                  lr A,errors
                  inc
                  lr errors,A                 ; else, increment checksum error count
                  li 'E'
dnload5:          lr txbuffer,A               
                  pi putc                     ; print 'E' for 'error'
                  br dnload1                  ; go back for the next record

; last record
dnload6:          pi getbyte                  ; get the last record address most significant byte
                  lr A,rxbuffer
                  lr HU,A                     ; save the most significant byte of the last record's address in HU
                  pi getbyte                  ; get the last record address least significant byte
                  lr A,rxbuffer
                  lr HL,A                     ; save the least significant byte of the last record's address in HL
                  pi getbyte                  ; get the last record type
                  pi getbyte                  ; get the last record checksum
dnload7:          pi getc                     ; get the last carriage return
                  li '.'
                  lr txbuffer,A
                  pi putc                     ; echo the carriage return
                  pi newline

                  clr
                  lr zeroflag,A               ; clear 'zeroflag'. leading zeros will be suppressed
                  pi printdec                 ; print the number of checksum errors
                  dci cksumerrtxt
                  pi putstr                   ; print "Checksum errors"

                  lr A,number                 ; recall the checksum error count
                  ci 0
                  bz dnload8                  ; if there were zero checksum errors, jump to the address in the last record
                  jmp monitor2                ; else, return to monitor

dnload8:          lr DC,H                     ; move the address from the last record now in H to DC
                  lr Q,DC                     ; move the address in DC to Q
                  lr P0,Q                     ; move the address in Q to the program counter (jump to the address in Q)

;=======================================================================
; display the value input from an I/O port
;=======================================================================
portinput:        dci portaddrtxt             
                  pi putstr                   ; print the string  to prompt for port address
portinput1:       pi get2hex                  ; get the port address
                  lr A,rxbuffer
                  ni 0FH                      ; mask all but bits 0-3 (valid port addresses are 00-0FH)
                  lr portaddr,A               ; save as the port address
                  bnc portinput2              ; branch if the input was not ESCAPE or ENTER
                  ci ESCAPE                   ; was the input ESCAPE?
                  bnz portinput1              ; go back for another input if not
                  jmp monitor2                ; else, return to menu

; store code in executable RAM which, when executed, inputs from 'portaddr' and saves A in 'portval'
portinput2:       dci portvaltxt              
                  pi putstr                   ; print'Port value:  "
                  dci patch                   ; address in 'executable' RAM
                  li 0A0H                     ; 'INS' opcode
                  as portaddr                 ; combine the 'INS' opcode with the port address in 'portaddr'
                  st                          ; save in 'executable' RAM, increment DC
                  li 50H+portval              ; 'LR portval,A' opcode
                  st                          ; save in 'executable' RAM, increment DC
                  li 29H                      ; 'JMP' opcode
                  st                          ; save in 'executable' RAM, increment DC
                  li hi(portinput3)           ; hi byte of 'portinput3' address
                  st                          ; save in 'executable' RAM, increment DC
                  li lo(portinput3)           ; lo byte of 'portinput3' address
                  st                          ; save in 'executable' RAM, increment DC
                  jmp patch                   ; jump to address in executable RAM

portinput3:       lr A,portval                ; code in executable RAM jumps back here, retrieve the input byte
                  lr hexbyte,A                ; save it in 'hexbyte' for the 'print2hex' function
                  pi print2hex                ; print the input byte
                  pi newline                  ; newline
                  jmp monitor2                ; return to menu

;=======================================================================
; output a value to an I/O port
;=======================================================================
portoutput:       dci portaddrtxt             
                  pi putstr                   ; print the string  to prompt for port address
portoutput1:      pi get2hex                  ; get the port address
                  lr A,rxbuffer
                  ni 0FH                      ; mask all but bits 0-3 (valid port addresses are 00-0FH)
                  lr portaddr,A               ; save as the port address
                  bnc portoutput2             ; branch if the input was not ESCAPE or ENTER
                  ci ESCAPE                   ; is the input ESCAPE?
                  bnz portoutput1             ; if not, go back for more input
                  jmp monitor2                ; return to menu if ESCAPE

portoutput2:      dci portvaltxt              
                  pi putstr                   ; prompt for portoutput value
portoutput3:      pi get2hex                  ; get the byte to be portoutput
                  lr A,rxbuffer
                  lr portval,A                ; save the byte to be portoutput
                  bnc portoutput5             ; branch if the input was not ENTER or ESCAPE
                  ci ESCAPE                   ; is the input ESCAPE?
                  bnz portoutput3             ; if not, go back for more input
portoutput4:      jmp monitor2                ; else, exit to the menu

; store code in executable RAM which, when executed, portoutputs 'portval' to 'portaddr'
portoutput5:      dci patch                   ; address in 'executable' RAM
                  li 40H+portval              ; 'LR A,portval' opcode
                  st                          ; save in 'executable' RAM, increment DC
                  li 0B0H                     ; 'OUTS' opcode
                  as portaddr                 ; combine the 'OUTS' opcode with the port address in 'portaddr'
                  st                          ; save in 'executable' RAM, increment DC
                  li 29H                      ; 'JMP' opcode
                  st                          ; save in 'executable' RAM, increment DC
                  li hi(portoutput4)          ; hi byte of 'portoutput4' address
                  st                          ; save in 'executable' RAM, increment DC
                  li lo(portoutput4)          ; lo byte of 'portoutput4' address
                  st                          ; save in 'executable' RAM, increment DC
                  jmp patch                   ; jump to address in executable RAM

;=======================================================================
; jump to an address in memory
;=======================================================================
jump:             dci addresstxt              
                  pi putstr                   ; print the string  to prompt for an address
                  pi get4hex                  ; get an address into H
                  bnc jump1                   ; branch if not ESCAPE
                  jmp monitor2                ; else, return to menu

jump1:            pi newline                  
                  lr DC,H                     ; load the address from the 'get4hex' function now in H to DC
                  lr Q,DC                     ; load the address in DC to Q
                  lr P0,Q                     ; load the address in Q to the program counter (efectively, jump to the address in Q)

;=======================================================================
; display the contents of Scratchpad RAM in hex and ASCII
;=======================================================================
scratch:          dci column1txt
                  pi putstr
                  lis 8
                  lr linecnt,A                ; 8 lines
                  clr
                  lr IS,A

; print the address at the start of the line
scratch1:         lr A,IS                     ; ISAR
                  lr hexbyte,A                ; save it in 'hexbyte' for the 'print2hex' function
                  pi print2hex                ; print the scratchpad RAM address
                  li '-'
                  lr txbuffer,A
                  pi putc                     ; print '-'

; print 8 hex bytes
                  lis 8
                  lr bytecnt,A                ; 8 hex bytes on a line
                  lr A,IS
                  lr HL,A                     ; save IS in HL
scratch2:         lr A,I                      ; load the byte from scratchpad RAM into A, increment ISAR
                  lr hexbyte,A                ; save it in 'hexbyte' for the 'print2hex' function
                  pi print2hex                ; print the data byte at that address
                  pi space
                  ds bytecnt
                  bnz scratch2                ; branch back until 8 bytes have been printed

; print 8 ASCII characters
                  lr A,HL
                  lr IS,A                     ; restore IS
                  lis 8
                  lr bytecnt,A                ; 16 characters on a line
scratch4:         lr A,I                      ; load the byte from scratchpad RAM into A, increment ISAR
                  ci 7FH
                  bnc scratch5                ; branch if character is > 7FH
                  ci 1FH
                  bnc scratch6                ; branch if character is > 1FH
scratch5:         li '.'                      
scratch6:         lr txbuffer,A               ; store the character in 'txbuffer' for the 'putc' function
                  pi putc                     ; print the character
                  ds bytecnt
                  bnz scratch4                ; branch back until 8 characters have been printed
                  pi newline                  ; finished with this line

; increment ISAR to next data buffer
                  lr A,IS
                  ai 08H                      ; next data buffer
                  lr IS,A
                  lisl 0                      ; reset ISAR to the beginning of the data buffer
                  ds linecnt
                  bnz scratch1                ; branch back until all 8 data buffers have been printed
                  jmp monitor2                ; back to the menu

;=======================================================================
; examine/modify Scratchpad RAM contents.
; 1. prompt for a Scratchpad RAM address.
; 2. display the contents of that Scratchpad RAM address.
; 3. wait for entry of a new value to be stored at that Scratchpad RAM address.
; 4. ENTER key leaves Scratchpad RAM unchanged, increments to next Scratchpad RAM address.
; 5. ESCAPE key exits.
; 
; CAUTION:  modifying Scratchpad Memory locations 00-0FH will likely crash the monitor!
;=======================================================================
xamine:           dci addresstxt              
                  pi putstr                   ; print the string  to prompt for scratchpad RAM address
                  pi get2hex                  ; get the scratchpad RAM address
                  bnc xamine1                 ; branch if not ESCAPE key
                  jmp monitor2                ; else, return to monitor

xamine1:          pi newline                  
                  lr A,rxbuffer
                  lr IS,A                     ; move the address from the 'get2hex' function into ISAR

; print the address
xamine2:          lr A,IS                     ; load the scratchpad RAM address in ISAR into A
                  lr hexbyte,A                ; save it in 'hexbyte' for the 'print2hex' function
                  pi print2hex                ; print the address
                  pi space

; get the byte from scratchpad RAM
                  lr A,S                      ; load the byte from scratchpad RAM into A, do not increment or decrement IS
                  lr hexbyte,A                ; save it in 'hexbyte' for the 'print2hex' function
                  pi print2hex                ; print the data byte at that address
                  pi space                    ; print a space

; get a new value to store in memory
                  pi get2hex                  ; get a new data byte
                  lr A,rxbuffer               ; load the byte from the 'get2hex' function into A
                  bnc xamine3                 ; branch if the byte from 'get2hex' is not a control character
                  ci ENTER                    ; was the input ENTER?
                  lr A,S                      ; recall the original value stored at this memory address
                  bz xamine3                  ; branch if the input was ENTER
                  jmp monitor2                ; if not ENTER, the input must have been ESCAPE so return to monitor

; store the byte in memory
xamine3:          lr I,A                      ; store the byte in scratchpad RAM, increment IS
                  pi newline
                  lr A,IS
                  ni 07H                      ; have we reached the end of the data buffer?
                  bnz xamine2                 ; if not, go do next scratchpad RAM address
; increment ISAR to next data buffer
                  lr A,IS
                  ai 08H                      ; next data buffer
                  lr IS,A
                  lisl 0                      ; reset ISAR to the beginning of the next data buffer
                  br xamine2                  ; go do next scratchpad RAM address

;------------------------------------------------------------------------
; get 2 hex digits (00-FF) from the serial port. do not echo.
; returns with the 8 bit binary number in 'rxbuffer'.
; this is a first level subroutine which calls a second level subroutine 'get1hex'.
;------------------------------------------------------------------------
getbyte:          lr K,P                      
                  lr A,KU
                  lr QU,A
                  lr A,KL
                  lr QL,A

; get the first hex digit
getbyte1:         pi get1hex                  ; get the first hex digit
                  lr A,rxbuffer               ; retrieve the character
getbyte3:         sl 4                        ; shift into the most significant nibble position
                  lr txbuffer,A               ; save the first digit as the most significant nibble temporarily in the tx buffer

; get the second hex digit
getbyte4:         pi get1hex                  ; get the second hex digit

; combine the two digits into an 8 bit binary number saved in 'rxbuffer'
getbyte5:         lr A,txbuffer               ; recall the most significant nibble from the tx buffer
                  xs rxbuffer                 ; combine with the least significant nibble previously received
                  lr rxbuffer,A               ; save in 'rxbuffer'
getbyte6:         lr P0,Q                     ; return from first level subroutine

;------------------------------------------------------------------------
; get four hex digits (0000-FFFF) from the serial port. echo valid hex digits.
; returns with carry set if ESCAPE key, else returns with the the 16 bit number
; in linkage register H (scratchpad RAM registers 0AH and 0BH).
; this is a first level subroutine which calls second level subroutines 'get1hex' and 'print1hex'.
; 
; NOTE:  it is not necessary to enter leading zeros. i.e.
;   1<ENTER> returns 0001
;  12<ENTER> returns 0012
; 123<ENTER> returns 0123
;------------------------------------------------------------------------
get4hex:          lr K,P                      
                  lr A,KU
                  lr QU,A
                  lr A,KL
                  lr QL,A

; get the first character...
get4hex1:         pi get1hex                  ; get the first hex digit into 'rxbuffer'
                  bnc get4hex3                ; branch if not ESCAPE or ENTER
                  lr A,rxbuffer               ; load the first hex digit from the get1hex function
                  ci ESCAPE                   ; is it ESCAPE?
                  bz get4hex8                 ; branch if ESCAPE
                  br get4hex1                 ; else, go back if ENTER

; the first character was a valid hex digit
get4hex3:         lr A,rxbuffer               
                  lr hexbyte,A
                  pi print1hex                ; echo the digit
                  lr A,rxbuffer
                  sl 4                        ; shift the first digit into into the most significant nibble position
                  lr HU,A                     ; save the first digit as the most significant nibble in HU

; get the second character...
                  pi get1hex                  ; get the second hex digit
                  bnc get4hex4                ; branch if not ESCAPE or ENTER
                  lr A,rxbuffer
                  ci ESCAPE                   ; is it ESCAPE?
                  bz get4hex8                 ; branch if ESCAPE

; the second character is 'ENTER'...
                  lr A,HU                     ; retrieve the most significant nibble entered previously from HU
                  sr 4                        ; shift it from the most into the least significant nibble position
                  lr HL,A                     ; save in HL
                  clr
                  lr HU,A                     ; clear HU
                  br get4hex7                 ; exit the function

; the second character is a valid hex digit
get4hex4:         lr A,rxbuffer               
                  lr hexbyte,A
                  pi print1hex                ; echo the digit
                  lr A,HU                     ; recall the most significant nibble entered previously
                  xs rxbuffer                 ; combine with the least significant nibble from the get1hex function
                  lr HU,A                     ; save as the most significant byte in HU

; get the third character...
                  pi get1hex                  ; get the third hex digit into 'rxbuffer'
                  bnc get4hex5                ; branch if not ENTER or ESCAPE
                  lr A,rxbuffer
                  ci ESCAPE                   ; is it ESCAPE?
                  bz get4hex8                 ; branch if ESCAPE

; the third character is 'ENTER'
                  lr A,HU                     ; else recall the most significant byte
                  lr HL,A                     ; save it as the least significant byte
                  clr
                  lr HU,A                     ; clear the most significant byte
                  br get4hex7                 ; exit the function

; the third character is a valid hex digit
get4hex5:         lr A,rxbuffer               
                  lr hexbyte,A
                  pi print1hex                ; echo the digit
                  lr A,rxbuffer               ; get the third digit from the rx buffer
                  sl 4                        ; shift the third digit to the most significant nibble porition
                  lr HL,A                     ; save in HL

; get the fourth character...
                  pi get1hex                  ; get the fourth digit into 'rxbuffer'
                  bnc get4hex6                ; branch if not WNTER OR ESCAPE
                  lr A,rxbuffer
                  ci ESCAPE                   ; is it ESCAPE?
                  bz get4hex8                 ; branch if ESCAPE

; ; the fourth character is 'ENTER'
                  lr A,HL                     ; else, retrieve the most significant nibble entered previously from HL
                  sr 4                        ; shift into the least significant nibble position
                  lr HL,A                     ; save in HL
                  lr A,HU                     ; recall the first and second digits entered
                  sl 4                        ; shift the second digit to the most significant nibble position
                  xs HL                       ; combine the second and third digits entered to make HL
                  lr HL,A                     ; save it as HL
                  lr A,HU                     ; recall the first two digits entered
                  sr 4                        ; shift the first digit to the most signoficant nibble position
                  lr HU,A                     ; save it in HU
                  br get4hex7                 ; exit the function

; the fourth character is a valid hex digit
get4hex6:         lr A,rxbuffer               
                  lr hexbyte,A
                  pi print1hex                ; echo the digit
                  lr A,HL                     ; retrieve the third hex digit
                  xs rxbuffer                 ; combine with the fourth digit
                  lr HL,A                     ; save it in HL

; clear carry and return with the four bytes in HU and HL
get4hex7:         com                         ; clear carry
                  lr P0,Q                     ; return from first level subroutine

; ESCAPE was entered. set carry and return
get4hex8:         li 0FFH                     
                  inc                         ; set the carry bit if ESCAPE entered as first character
                  lr P0,Q                     ; return from first level subroutine

;------------------------------------------------------------------------
; get 2 hex digits (00-FF) from the serial port. echo valid hex digits.
; returns with carry set if ESCAPE or ENTER key, else returns with the
; eight bit binary number in 'rxbuffer'.
; this is a first level subroutine which calls second level subroutines 'get1hex' and 'print1hex'.
; 
; NOTE:  it is not necessary to enter a leading zero. i.e.
; 1<ENTER> returns 01
; 2<ENTER> returns 02
; ...
; F<ENTER> returns 0F
;------------------------------------------------------------------------
get2hex:          lr K,P                      
                  lr A,KU
                  lr QU,A
                  lr A,KL
                  lr QL,A

; get the character...
get2hex1:         pi get1hex                  ; get the first hex digit
                  lr A,rxbuffer               ; retrieve the character
                  bnc get2hex3                ; branch if the first digit was not a control character
                  ci ESCAPE                   ; is it ESCAPE?
                  bz get2hex2                 ; set carry and exit if ESCAPE key
                  ci ENTER                    ; is it ENTER?
                  bz get2hex2                 ; set carry and exit if ENTER key
                  bnz get2hex1                ; go back if any other control character except ESCAPE or ENTER

; exit the function with carry set to indicate first character was a control character
get2hex2:         li 0FFH                     
                  inc                         ; else, set the carry bit to indicate control character
                  lr P0,Q                     ; restore the return address from Q

; the first character is a valid hex digit
get2hex3:         lr A,rxbuffer               
                  lr hexbyte,A
                  pi print1hex                ; echo the digit
                  lr A,rxbuffer
                  sl 4                        ; shift into the most significant nibble position
                  lr HL,A                     ; save the first digit as the most significant nibble in HL

; get the second character...
get2hex4:         pi get1hex                  ; get the second hex digit
                  lr A,rxbuffer
                  bnc get2hex5                ; branch if not a control character
                  ci ESCAPE                   ; is it ESCAPE?
                  bz get2hex2                 ; branch exit the function if the control character is ESCAPE
                  ci ENTER                    ; is it ENTER?
                  bnz get2hex4                ; go back if any other control character except ESCAPE or ENTER
                  lr A,HL                     ; the second character was ENTER, retrieve the most significant nibble entered previously from HL
                  sr 4                        ; shift into the least significant nibble position
                  lr rxbuffer,A               ; save in rxbuffer
                  br get2hex6                 ; exit the function

; the second character was a valid hex digit. combine the two hex digits into one byte and save in 'rxbuffer'
get2hex5:         lr A,rxbuffer               
                  lr hexbyte,A
                  pi print1hex                ; echo the digit
                  lr A,HL                     ; recall the most significant nibble entered previously
                  xs rxbuffer                 ; combine with the least significant nibble from the get1hex function
                  lr rxbuffer,A               ; save in rxbuffer

; exit the function with carry cleared
get2hex6:         com                         ; clear carry
                  lr P0,Q                     ; return from first level subroutine

;------------------------------------------------------------------------
; prints (to the serial port) the contents of 'hexbyte' as 2 hexadecimal digits.
; this is a first level subroutine which calls a second level subroutine 'print1hex'.
;------------------------------------------------------------------------
print2hex:        lr K,P                      
                  lr A,KU
                  lr QU,A
                  lr A,KL
                  lr QL,A
                  lr A,hexbyte                ; retrieve the byte from 'hexbyte'
                  lr rxbuffer,A               ; save temporarily in the rx buffer
                  sr 4                        ; shift the 4 most significant bits to the 4 least significant position
                  lr hexbyte,A
                  pi print1hex                ; print the most significant hex digit
                  lr A,rxbuffer
                  lr hexbyte,A
                  pi print1hex                ; print the least significant digit
                  lr P0,Q                     ; return from first level subroutine

;------------------------------------------------------------------------
; get 1 hex digit (0-9,A-F) from the serial port.
; returns with carry set if ESCAPE or ENTER key , else returns with carry
; cleared and the 4 bit binary number saved in 'rxbuffer'.
; this is a second level subroutine called by a first level subroutine.
; this subroutine calls a third level subroutine 'getc'.
;------------------------------------------------------------------------
get1hex:          lr K,P                      
get1hex1:         pi getc                     ; get a character from the serial port
                  lr A,rxbuffer               ; retrieve the character from the rx buffer

; check for control characters (ESCAPE or ENTER)
                  ci ESCAPE
                  bz get1hex2                 ; branch if ESCAPE
                  ci ENTER
                  bz get1hex2                 ; branch if ENTER
                  ci ' '-1
                  bnc get1hex3                ; branch if not control character
                  br get1hex1                 ; any other control key, branch back for another character

; exit function with carry set to indicate a control character (ESCAPE or ENTER)
get1hex2:         li 0FFH                     
                  inc                         ; set the carry bit to indicate control character
                  pk                          ; return from second level subroutine

; not a control character. convert lower case to upper case
get1hex3:         ci 'a'-1                    
                  bc get1hex4                 ; branch if character is < 'a'
                  ci 'z'
                  bnc get1hex4                ; branch if character is > 'z'
                  ai -20H                     ; else, subtract 20H to convert lowercase to uppercase

; check for valid hex digt (0-9, A-F)
get1hex4:         ci '0'-1                    
                  bc get1hex1                 ; branch back for another if the character is < '0' (invalid hex character)
                  ci 'F'
                  bnc get1hex1                ; branch back for another if the character is > 'F' (invalid hex character)
                  ci ':'-1
                  bc get1hex5                 ; branch if the character is < ':' (the character is valid hex 0-9)
                  ci 'A'-1
                  bc get1hex1                 ; branch back for another if the character is < 'A' (invalid hex character)

; valid hex digit was entered. convert from ASCII character to binary number and save in 'rxbuffer'
get1hex5:         ci 'A'-1                    
                  bc get1hex6                 ; branch if the character < 'A' (character is 0-9)
                  ai -07H                     ; else, subtract 07H
get1hex6:         ai -30H                     ; subtract 30H to convert from ASCII to binary
                  lr rxbuffer,A               ; save the nibble in the receive buffer

; clear carry and exit function
                  com                         ; clear the carry bit
get1hex7:         pk                          ; return from second level subroutine

;------------------------------------------------------------------------
; prints (to the serial port) the contents of 'hexbyte' as a hexadecimal digit.
; this is a second level subroutine called by a first level subroutine.
; this subroutine calls a third level subroutine 'putc'.
;------------------------------------------------------------------------
print1hex:        lr K,P                      
                  lr A,hexbyte                ; retrieve the byte
                  sl 4                        ; shift left
                  sr 4                        ; then shift right to remove the 4 most significant bits
                  ai 30H                      ; add 30H to convert from binary to ASCII
                  ci '9'                      ; compare to ASCII '9'
                  bp print1hex1               ; branch if '0'-'9'
                  ai 07H                      ; else add 7 to convert to ASCII 'A' to 'F'
print1hex1:       lr txbuffer,A               ; put it into the transmit buffer
                  pi putc                     ; print the least significant hex digit
                  pk                          ; return from second level subroutine

;------------------------------------------------------------------------
; prints (to the serial port) the contents of 'number' as a 3
; digit decimal number. leading zeros are suppressed.
; this is a second level subroutine called by a first level subroutine.
; this subroutine calls a third level subroutine 'putc'.
;------------------------------------------------------------------------
printdec:         lr K,P                      
                  clr
                  lr zeroflag,A
                  li '0'-1
                  lr digit,A                  ; initialize 'digit'
; hundreds digit
printdec1:        lr A,digit                  
                  inc
                  lr digit,A                  ; increment 'digit' for each time 100 can be subtracted from the number
                  lr A,number                 ; load the number
                  ai -100                     ; subtract 100
                  lr number,A                 ; save in 'number'
                  bc printdec1                ; if there's no underflow, go back and subtract 100 from the number again
                  ai 100                      ; else, add 100 back to the number to correct the underflow
                  lr number,A                 ; save in 'number'
                  lr A,digit                  ; recall the hundreds digit
                  ci '0'                      ; is the hundreds digit '0'?
                  bnz printdec2               ; if not, print the hundreds digit
                  lr A,zeroflag               ; else, check the zero flag
                  ci 0                        ; is the flag zero?
                  bz printdec3                ; if so, skip the hundreds digit and go to the tens digit
printdec2:        lr A,digit                  
                  lr txbuffer,A               ; else, put the hundreds digit in the tx buffer
                  pi putc                     ; print the hundreds digit
                  ds zeroflag                 ; set the zero flag (all subsequent zeros will be printed)
printdec3:        li '0'-1                    
                  lr digit,A                  ; initialize 'digit'
; tens digit
printdec4:        lr A,digit                  
                  inc
                  lr digit,A                  ; increment 'digit' for each time 10 can be subtracted from the number
                  lr A,number                 ; recall from 'number'
                  ai -10                      ; subtract 10
                  lr number,A                 ; save in 'number'
                  bc printdec4                ; if there's no underflow, go back and subtract 10 from the number again
                  ai 10                       ; else add 10 back to the number to correct the underflow
                  lr number,A                 ; save in 'number'
                  lr A,digit                  ; recall the ten's digit
                  ci '0'                      ; is the tens digit zero?
                  bnz printdec5               ; if not, go print the tens digit
                  lr A,zeroflag               ; else, check the zero flag
                  ci 0                        ; is the flag zero?
                  bz printdec6                ; if so, skip the tens digit and print the units digit
printdec5:        lr A,digit                  ; else recall the tens digit
                  lr txbuffer,A               ; put it in the tx buffer
                  pi putc                     ; print the tens digit

; units digit
printdec6:        lr A,number                 ; what remains in 'number' after subtracting hundreds and tens is the units
                  ai 30H                      ; convert to ASCII
                  lr txbuffer,A               ; put it in the tx buffer
                  pi putc                     ; print the units digit
                  pk                          ; return from second level subroutine

;-----------------------------------------------------------------------------------
; print (to the serial port) the zero-terminated string whose first character is addressed by DC.
; this is a second level subroutine called by a first level subroutine.
; this subroutine calls a third level subroutine 'putc'.
;-----------------------------------------------------------------------------------
putstr:           lr K,P                      
putstr1:          lm                          ; load the character addressed by DC and increment DC
                  ci 0                        ; is the character zero (end of string)?
                  bnz putstr2                 ; branch if not the end of the string
                  pk                          ; return from second level subroutine

putstr2:          lr txbuffer,A               ; put the character into the tx buffer
                  pi putc                     ; print the character
                  br putstr1                  ; go back for the next character

;-----------------------------------------------------------------------------------
; print (to the serial port) carriage return followed by linefeed.
; this is a second level subroutine called by a first level subroutine.
; this subroutine calls a third level subroutine 'putc'.
;-----------------------------------------------------------------------------------
newline:          lr K,P                      
                  lis 0DH                     ; carriage return
                  lr txbuffer,A               ; put it into the tx buffer
                  pi putc                     ; print the carriage return
                  lis 0AH                     ; line feed
                  lr txbuffer,A               ; put it in the tx buffer
                  pi putc                     ; print line feed
                  pk                          ; return from second level subroutine

;-----------------------------------------------------------------------------------
; print (to the serial port) a space.
; this is a second level subroutine called by a first level subroutine.
; this subroutine calls a third level subroutine 'putc'.
;-----------------------------------------------------------------------------------
space:            lr K,P                      
                  li ' '                      ; space character
                  lr txbuffer,A               ; put it into the tx buffer
                  pi putc                     ; print the carriage return
                  pk                          ; return from second level subroutine

;-----------------------------------------------------------------------------------
; waits for a character from the serial port. saves the character in 'rxbuffer'. 
; this is a third level subroutine called by second level subroutines. 
;-----------------------------------------------------------------------------------
getc:             ins serialport              ; wait for the start bit
                  bp getc
                  lis 8
                  lr bitcount,A
                  li 242                      ; wait 1.5 bit time
                  inc
                  bnz $-1
getc1:            lr A,rxbuffer               ; get 8 data bits
                  sr 1
                  lr rxbuffer,A
                  ins serialport              ; read the serial input
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
                  bnz getc1
                  li 246                      ; wait for the stop bit
                  inc
                  bnz $-1
                  pop                         ; return from third level subroutine

;-----------------------------------------------------------------------------------
; transmit the character in 'txbuffer' out through the serial port.
; this is a third level subroutine called by second level subroutines. 
;-----------------------------------------------------------------------------------
putc:             lis 8                       
                  lr bitcount,A
                  li 01H
                  outs serialport             ; send the start bit
                  outs serialport
                  outs serialport
                  li 247
                  inc
                  bnz $-1
putc1:            lr A,txbuffer               ; send 8 data bits
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
                  outs serialport             ; send the stop bit
                  li 252
                  inc
                  bnz $-1
                  pop                         ; return from third level subroutine

titletxt          db CLS                      
                  db "MK3850 Mini-Monitor\r"
                  db "Assembled on ",DATE," at ",TIME,0
menutxt           db "\r\r"                   
                  db "B - return to BASIC\r"
                  db "D - Display main memory\r"
                  db "E - Examine/modify main memory\r"
                  db "H - download intel Hex file\r"
                  db "I - Input from port\r"
                  db "J - Jump to address\r"
                  db "O - Output to port\r"
                  db "S - display Scratchpad RAM\r"
                  db "X - display/eXamine scratchpad RAM",0
prompttxt         db "\r\r>> ",0              
addresstxt        db "\r\rAddress: ",0        
column1txt        db "\r\r   ",SGR4,"00 01 02 03 04 05 06 07\r",SGR0,0
column2txt        db "\r\r     ",SGR4,"00 01 02 03 04 05 06 07 08 09 0A 0B 0C 0D 0E 0F\r",SGR0,0
waitingtxt        db "\r\rWaiting for HEX download...\r\r",0
cksumerrtxt       db " Checksum errors\r",0   
portaddrtxt       db "\r\rPort address: ",0   
portvaltxt        db "\rPort value: ",0       
clearscrntxt      db CLS,0
                  end
