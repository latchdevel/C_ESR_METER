;=======ESR.ASM===================================08/may/04==
        list    p=16f876
        radix   hex
        ERRORLEVEL  -302    ;SUPPRESS BANK SELECTION MESSAGES
;------------------------------------------------------------
;     cpu equates (memory map)
indf		equ     0x00
tmr0		equ     0x01
status		equ     0x03
fsr		equ     0x04
porta		equ     0x05
portb		equ     0x06
portc		equ     0x07
intcon		equ     0x0b
adc_hi		equ	0x1e
adcon0		equ	0x1f
count1		equ     0x20
count2		equ     0x21
count3		equ     0x22
tick_lo		equ     0x23
tick_mid	equ     0x24
tick_hi		equ     0x25
t_tim		equ	0x26
t_lo		equ	0x27
t_mid		equ	0x28
t_hi		equ	0x29
rel_tmr		equ	0x2a
rel_lo		equ	0x2b
rel_mid		equ	0x2c
rel_hi		equ	0x2d
safe_w		equ	0x2e
safe_s		equ     0x2f
disp_u		equ	0x30
disp_1		equ	0x40
flags		equ     0x50
keys		equ     0x51
scratch		equ     0x52
temp		equ	0x53
ii		equ	0x54
cnt		equ	0x55
acc		equ	0x56
bcd		equ	0x5b
ascii		equ	0x60
ptr_bcd		equ	0x6a
ptr_asc		equ	0x6b
accx		equ	0x6c
option_reg	equ     0x81
trisa 		equ     0x85
trisb		equ     0x86
trisc		equ     0x87
adc_lo		equ	0x9e
adcon1		equ	0x9f
ACCaLO		equ	accx+0
ACCaMID		equ	accx+1
ACCaHI		equ	accx+2
ACCbLO		equ	accx+3
ACCbMID		equ	accx+4
ACCbHI		equ	accx+5
ACCcLO		equ	accx+6
ACCcMID		equ	accx+7
ACCcHI		equ	accx+8
ACCdLO		equ	accx+9
ACCdMID		equ	accx+0x0a
ACCdHI		equ	accx+0x0b
;
;------------------------------------------------------------
;     bit equates
w	equ	0
f	equ	1
c	equ	0
dc	equ	1
z	equ	2
rp0	equ	5
;
;@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
;
;     Port Configuration Words
Port_A_Config	equ b'00001011'
;/NA/NA/3K3/5mA/Vref/50mA/An1/An0/
;
;      Port A bit equates
An0  equ 0
An1  equ 1
i50  equ 2
i5   equ 4
R3k  equ 5
;
;
Port_B_Config	equ b'10101100'
;/NU/backlight/CompIn/CapDis/Prog/Key/lcdDC/lcdEn/
;
;       Port B bit equates
lcdEn  equ 0
lcdDc  equ 1
key    equ 2
Capdis equ 4
CompIn equ 5
Blight equ 6
;
;
Port_C_Config	equ	b'00000000'
;/All outputs for LCD data/
;
;
;@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
;------------------------------------------------------------
		;
 org 0x000	;  Device Reset
 b start	;
;
;------------------------------------------------------------
;
      org             0x004	; *** Interrupt ***
;
   	 movwf   safe_w         ;save w
   	 swapf   status,w       ;swap status, w
   	 movwf   safe_s         ;save status  
; 	 incf    tick_lo,f      ;increment first
;  	 btfsc   status,z
 	 incf    tick_mid,f     ;increment second
   	 btfsc   status,z
  	 incfsz  tick_hi,f      ;increment third
 	 goto    tick_out
	 b timeout	    ;Time Out!
tick_out swapf  safe_s,w    ;fetch status, reswap nibbles
	movwf   status      ;restore status
	swapf   safe_w,f    ;swap nibbles in preparation
	swapf   safe_w,w    ;for the swap restoration of w
	bcf     intcon,2    ;clear interrupt flag
	retfie              ;return from interrupt
;
;
;------------------------------------------------------------
;
start
;
;		INITIALISE PORTS
;
        bsf      status,rp0  ;switch to bank 1
        movlw	Port_A_Config
        movwf	trisa
        movlw	Port_B_Config
        movwf	trisb
        movlw	Port_C_Config
        movwf	trisc

;		Initialise Analogue to Digital Converter

        movlw	0xf5	   ;2 ana in & Vref+ & left just
	movwf	adcon1
        bcf     status,rp0 ;switch back to bank 0
        movlw   0xfe 	   ;all outputs inactive
        movwf   portb
	movlw	0xff
        movwf   porta
        movwf   portc
	movlw	0xc3
	movwf	adcon0	   ; setup ADC for single ch input
	call	timer_init ;start timer
        call    del_5      ;allow lcd time to initialize
        call    initlcd    ;initialize display
	call	cap
	call	esr
	call	disp32	   ;initial message in display
	b circle
;
;
;------------------------------------------------------------
; Create Text messages to be shown on the display
;------------------------------------------------------------
;
msg  movlw     'F'
     movwf     0x30
     movlw     'a'
     movwf     0x31
     movlw     'r'
     movwf     0x32
     movlw     'a'
     movwf     0x33
     movlw     'd'
     movwf     0x34
     movlw     ' '
     movwf     0x35
     movlw     'E'
     movwf     0x36
     movlw     'S'
     movwf     0x37
     movlw     'R'
     movwf     0x38
     movlw     ' '
     movwf     0x39
     movlw     'M'
     movwf     0x3a
     movlw     'e'
     movwf     0x3b
     movlw     't'
     movwf     0x3c
     movlw     'e'
     movwf     0x3d
     movlw     'r'
     movwf     0x3e
     movlw     ':'
     movwf     0x3f
     return
;
;------------------------------------------------------------
;
nam1 movlw     'A'
     movwf     0x40
     movlw     'n'
     movwf     0x41
     movlw     'u'
     movwf     0x42
     movlw     'r'
     movwf     0x43
     movlw     'o'
     movwf     0x44
     movlw     'o'
     movwf     0x45
     movlw     'p'
     movwf     0x46
     movlw     ' '
     movwf     0x47
     movlw     'J'
     movwf     0x48
     movlw     'o'
     movwf     0x49
     movlw     'y'
     movwf     0x4a
     movlw     ' '
     movwf     0x4b
     movlw     ' '
     movwf     0x4c
     movlw     ' '
     movwf     0x4d
     movwf     0x4e
     movwf     0x4f
     return
;
;------------------------------------------------------------
;
nam2 movlw     'J'
     movwf     0x40
     movlw     'o'
     movwf     0x41
     movlw     's'
     movwf     0x42
     movlw     'e'
     movwf     0x43
     movlw     ' '
     movwf     0x44
     movlw     'G'
     movwf     0x45
     movlw     'e'
     movwf     0x46
     movlw     'o'
     movwf     0x47
     movlw     'r'
     movwf     0x48
     movlw     'g'
     movwf     0x49
     movlw     'e'
     movwf     0x4a
     return
;
;------------------------------------------------------------
;
nam3 movlw     'K'
     movwf     0x40
     movlw     'h'
     movwf     0x41
     movlw     'a'
     movwf     0x42
     movlw     'd'
     movwf     0x43
     movlw     'a'
     movwf     0x44
     movlw     'r'
     movwf     0x45
     movlw     ' '
     movwf     0x46
     movlw     'A'
     movwf     0x47
     movlw     ' '
     movwf     0x48
     movlw     'N'
     movwf     0x49
     movlw     ' '
     movwf     0x4a
     return
;
;------------------------------------------------------------
;
nam4 movlw     'P'
     movwf     0x40
     movlw     'r'
     movwf     0x41
     movlw     'a'
     movwf     0x42
     movlw     'v'
     movwf     0x43
     movlw     'e'
     movwf     0x44
     movlw     'e'
     movwf     0x45
     movlw     'n'
     movwf     0x46
     movlw     'r'
     movwf     0x47
     movlw     'a'
     movwf     0x48
     movlw     'j'
     movwf     0x49
     movlw     'M'
     movwf     0x4b
     movlw     'R'
     movwf     0x4d
     return
;
;------------------------------------------------------------
;
cap  movlw     'C'
     movwf     0x30
     movlw     'a'
     movwf     0x31
     movlw     'p'
     movwf     0x32
     movlw     ' '
     movwf     0x33
     movlw     '='
     movwf     0x34
     movlw     ' '
     movwf     0x35
     movwf     0x3d
     movlw     '0'
     movwf     0x36
     movwf     0x37
     movwf     0x38
     movwf     0x39
     movwf     0x3a
     movwf     0x3b
     movwf     0x3c
     movlw     0xe4 ;micro
     movwf     0x3e
     movlw     'F'
     movwf     0x3f
     return
;
;____________________________________________________________
;
esr  movlw     'E'
     movwf     0x40
     movlw     'S'
     movwf     0x41
     movlw     'R'
     movwf     0x42
     movlw     ' '
     movwf     0x43
     movlw     '='
     movwf     0x44
     movlw     ' '
     movwf     0x45
     movlw     '0'
     movwf     0x46
     movlw     '0'
     movwf     0x47
     movlw     '0'
     movwf     0x48
     movlw     ' '
     movwf     0x49
     movlw     0xf4 ;ohm
     movwf     0x4a
     movlw     ' '
     movwf     0x4b
     movlw     ' '
     movwf     0x4c
     movlw     ' '
     movwf     0x4d
     return
;------------------------------------------------------------
;
e_err	movlw	't'
	movwf	0x46
	movlw	'o'
	movwf	0x47
	movlw	'o'
	movwf	0x48
	movlw	' '
	movwf	0x49
	movlw	'h'
	movwf	0x4a
	movlw	'i'
	movwf	0x4b
	movlw	'g'
	movwf	0x4c
	movlw	'h'
	movwf	0x4d
	b disp32
;
;------------------------------------------------------------
;
c_err	movlw	'L'
	movwf	0x36
	movlw	'e'
	movwf	0x37
	movlw	'a'
	movwf	0x38
	movlw	'k'
	movwf	0x39
	movlw	'y'
	movwf	0x3a
	movlw	' '
	movwf	0x3b
	movwf	0x3c
	movwf	0x3d
	movwf	0x3e
	movwf	0x3f
	return	
;
;____________________________________________________________
;
timer_init
	bcf	intcon,2 ;clear tmr0 int flag
	bsf     intcon,7 ;enable global interrupts
	bsf     intcon,5 ;enable tmr0 int
	clrf    tmr0	 ;clear timer
 	movlw   option_reg ;Work around the OPTION
	movwf   fsr 	 ;warning
	movlw   0x58	 ;set up timer. no presc 
	movwf   indf	 ;pullups enabled on B port
	clrf    tmr0	 ;start timer
	return		 ;return to calling routine
;
;------------------------------------------------------------
;
credits call    msg     ;create message in display RAM
	call    nam1
        call    disp32  ;send 32 characters to display
	call 	wait
	call	nam2
	call 	disp32
	call 	wait
	call	nam3
	call	disp32
	call	wait
	call	nam4
	call	disp32
	call	wait
  goto   credits        ;keep doing it
;
;------------------------------------------------------------
;
initlcd bcf    portb,lcdEn     	;E line low
     bcf       portb,lcdDc     	;RS line low, set up for control
     call      del_125   	;delay 125 microseconds
     movlw     0x3f        	;8-bit, 5X7
     movwf     portc      	;0011 1111
     call      pulse    	;pulse and delay
     call      del_125     	;delay 125 microseconds
     movlw     0x3f       	;8-bit, 5X7
     movwf     portc      	;0011 1111
     call      pulse       	;pulse and delay
     call      del_125   	;delay 125 microseconds
     movlw     0x3f       	;8-bit, 5X7
     movwf     portc      	;0011 1111
     call      pulse      	;pulse and delay
     call      del_125    	;delay 125 microseconds
     movlw     0x3f       	;8-bit, 5X7
     movwf     portc   		;0011 1111
     call      pulse     	;pulse and delay
     movlw     0x0f      	;display on
     movwf     portc     	;0000 1111
     call      pulse
     movlw     0x06		;increment mode, no display shift
     movwf     portc      	;0000 0110
     call      pulse
     call      del_5      	;delay 5 milliseconds - required
     return               	;before sending data
;
;------------------------------------------------------------
;
disp32 bcf     portb,lcdEn   ;E line low
     bcf       portb,lcdDc   ;RS line low, set up for control
     call      del_125       ;delay 125 microseconds
     movlw     0x80          ;control word = address first half
     movwf     portc
     call      pulse         ;pulse and delay
     bsf       portb,lcdDc   ;RS=1, set up for data
     call      del_125       ;delay 125 microseconds
     movlw     0x30          ;initialze file select register
     movwf     fsr
getchar movf   0x00,w        ;get character from display RAM
;                             location pointed to by file select
;                             register
     movwf     portc
     call      pulse         ;send data to display
     movlw     0x3f          ;16th character sent?
     subwf     fsr,w         ;subtract w from fsr
     btfsc     status,z      ;test z flag
     goto      half          ;set up for last 16 characters
     movlw     0xb0          ;test number
     addwf     fsr,w
     btfsc     status,c      ;test Carry flag
     return                  ;32 characters sent to lcd
     incf     fsr,f          ;move to next character location
     goto     getchar
half bcf     portb,lcdDc     ;RS=0, set up for control
     call     del_125        ;delay 125 microseconds
     movlw     0xa8          ;control word = address second half
     movwf     portc
     call     pulse          ;pulse and delay
     bsf     portb,lcdDc     ;RS=1, set up for data
     incf     fsr,f          ;increment file select register to
;                            ;select next character
     call     del_125        ;delay 125 microseconds
     goto     getchar
;
;------------------------------------------------------------
;
del_20	movlw 0x06	;approx 6x3 cycles
	movwf count1	;for 20 microsecond delay
	goto	repeat	;for ADC operation
;------------------------------------------------------------
del_125 movlw 0x2a      ;approx 42x3 cycles (decimal)
     movwf     count1   ;load counter
repeat decfsz  count1,f ;decrement counter
     goto     repeat    ;not 0
     return             ;counter 0, ends delay
;
;------------------------------------------------------------
;
delay
        movlw	0xff
	b get
del_5 movlw   0x29      ;decimal 40
get  movwf    count2    ;to counter
del6 call    del_125    ;delay 125 microseconds
     decfsz   count2,f  ;do it 40 times = 5 milliseconds
     goto     del6
     return             ;counter 0, ends delay
;
;------------------------------------------------------------
;
pulse  bsf  portb,lcdEn ;pulse E line
     nop                ;delay
     bcf     portb,lcdEn
     call     del_125   ;delay 125 microseconds
     return
;
;------------------------------------------------------------
;  Wait between flashing names
;
wait
	movlw	0x60
	movwf	count3  ; delay 64*5 mS
again	call    del_5
	decfsz  count3,f
	goto    again
	return
;
;-----------------------------------------------------------
;       Toggle Backlight
backlit
 btfsc	portb,Blight
 goto	setb
 bsf	portb,Blight
 return
setb bcf portb,Blight
 return
;
;------------------------------------------------------------
;	Clear interrupt count area
zero	movlw   0x80
        movwf	tick_hi
	clrf	tick_lo
	clrf	tick_mid
	clrf	tmr0
	return
;
;------------------------------------------------------------
;	Clear accumulator
zeroacc	clrf	acc+0
	clrf	acc+1
	clrf	acc+2
	clrf	acc+3
	return
;
;------------------------------------------------------------
;
inc     	;increment accumulator and check keypress

        clrf    portc   ;zeroes into the C port
        btfss   portb,key
        b       debnce
nokey	incfsz	acc+0,f
	return
	incfsz	acc+1,f
	return
	incf	acc+2,f
        movlw   0xf0
        andwf   acc+2,w
        btfsc   status,z
        return        
 	b timeout	;Accumulator Overflow.
debnce  
        clrw
        movwf scratch
ssdel   decfsz scratch,f
        b ssdel
        btfsc portb,key
        return
                        ;/0-Credits/1-Backlight/2-OFF/
        movlw 0xfb
        movwf portc
        btfss portb,key ;Check if OFF key pressed
        sleep
        movlw 0xfe
        movwf portc
        btfss portb,key ;Check if Credits key
        b credits
        call backlit
        b wait

        
;
;------------------------------------------------------------
;	Value calculation
;
calcu	movlw	0x38
	movwf	fsr
	call 	initasc
loop6	decf	t_tim,f
	btfss	status,z
	goto	loop7
	return
	movf	t_lo,f
	btfsc	status,z
	return
	decf	t_lo,f
	goto	loop6
loop7	movlw	0x38
	movwf	fsr
	call 	incasc
	goto 	loop6
;
;------------------------------------------------------------
;
calc	call 	b2bcd
	call	bcd2asc
	return
;
;------------------------------------------------------------
;	Initialise fsr area to ascii zero
initasc	movlw   0x03
	movwf	temp
	movlw	'0'
loop5	movwf	indf
	decf	fsr,f
	decfsz	temp,f
	goto loop5
	return
;
;------------------------------------------------------------
;	Increment fsr area in ascii
incasc	movlw 0x03
	movwf	temp
loop4	incf	indf,f
	movlw	0xc6	; test for over nine
	addwf	indf,w;
	btfss	status,c
	return
	movlw	'0'
	movwf	indf
	decf	fsr,f
	decfsz	temp,f
	goto 	loop4
	bsf	flags,2	;notify overflow
	return
;
;____________________________________________________________
;
conv	bcf	status,c  ;convert bin in w to asc
	incf	scratch,f
loop8	decfsz	scratch,f
	goto	loop9
	return
loop9	movlw	0x48
	movwf	fsr	
	call 	incasc
	goto	loop8
;
;____________________________________________________________
;%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
;____________________________________________________________
;
; Convert 32-bit binary number at  into a bcd number
; at . Uses Mike Keitz's procedure for handling bcd
; adjust; Modified Microchip AN526 for 32-bits.
;
b2bcd 	movlw 0x18	; 24-bits
	movwf	ii	; make cycle counter
	clrf	bcd+0	; clear result area
	clrf	bcd+1
	clrf	bcd+2
;	clrf	bcd+3
;	clrf	bcd+4
b2bcd2	movlw	bcd	; make pointer
	movwf	fsr
	movlw	3
	movwf	cnt
;
; Mike's routine:
;
b2bcd3	movlw	0x33
	addwf	0,f	; add to both nybbles
	btfsc	0,3	; test if low result > 7
	andlw	0xf0	; low result >7 so take the 3 out
	btfsc	0,7	; test if high result > 7
	andlw	0x0f	; high result > 7 so ok
	subwf	0,f	; any results <= 7, subtract back
	incf	fsr,f	; point to next
	decfsz	cnt,f
	goto	b2bcd3
	rlf	acc+0,f	; get another bit
	rlf	acc+1,f
 	rlf	acc+2,f
;	rlf	acc+3,f
	rlf	bcd+0,f	; put it into bcd
	rlf	bcd+1,f
	rlf	bcd+2,f
;	rlf	bcd+3,f
;	rlf	bcd+4,f
	decfsz	ii,f	; all done?
	goto	b2bcd2	; no, loop
	return
;
;------------------------------------------------------------
; Unpack BCD data into ASCII coded string for display
bcd2asc movlw 	3		;three bcd bytes
	movwf	ii		;byte counter
	movlw	bcd		;start of BCD, LSD first
	movwf	ptr_bcd
	movlw	0x32 + 0x09	;destination + length of result
	movwf	ptr_asc
loopz	movf	ptr_bcd,w
	movwf	fsr		;get next couple of digits
	movf	indf,w	;into temp
	movwf	temp
	movf	ptr_asc,w
	movwf	fsr
	movf	temp,w
	andlw	0x0f	;lower digit
	iorlw	0x30
	movwf	indf	;store
	decf	fsr,f	;higher digit
	swapf	temp,w
	andlw	0x0f
	iorlw	0x30
	movwf	indf
	incf	ptr_bcd,f
	decf	ptr_asc,f
	decf	ptr_asc,f
        decfsz  ii,f
	goto	loopz
	return
;______________________________________________________________
;
;	Measure ESR
;
testesr
	bsf	portb,Capdis	;discharge
	movlw	0xc3
	movwf	adcon0		;turn adc ON
	call	esr
	call	delay		;time for discharging
	bcf	portb,Capdis
	bcf	porta,i5	;turn 5mA on
	call	del_20
	movlw	0xc7
	movwf	adcon0		;start conversion
	call 	del_20		;wait for conversion
	movlw	0xff
	movwf	porta	        ;turn 5mA off
	movlw	0x48
	movwf	fsr
        call 	initasc	
	bsf     status,rp0      ;switch to bank 1
	movf	adc_lo,w	;get result
	bcf     status,rp0      ;switch to bank 0
	movwf	scratch
	movf	adc_hi,f
	bnz	e_err
	addlw	0xe7    	;test if too small
	bnc	testesrh
	call	conv
	b 	disp32
;
;____________________________________________________________
;	Measure ESR - hi current range
;
testesrh 
	bsf	portb,Capdis	;discharge
	movlw	0xc3
	movwf	adcon0		;turn adc ON
	call	esr
	call	delay		;time for discharging
	bcf	portb,Capdis	;stop discharge
	bcf 	porta,i50	;turn 50mA on
	call	del_20
	movlw	0xc7
	movwf	adcon0		;start conversion
	call 	del_20		;wait for conversion
	bsf	porta,i50	;turn 50mA off
	movlw	0x48
	movwf	fsr
	call 	initasc	
	bsf     status,rp0     ;switch to bank 1
	movf	adc_lo,w	;get result
	bcf     status,rp0     ;switch to bank 0
	movwf	scratch
	call 	conv		;convert result
e_ten   movf	0x48,w
	movwf	0x49
	movlw	'.'
	movwf	0x48
	b       disp32		;display result
;
;____________________________________________________________
;		Measure Value of Capacitance - low ramge
;
captestl	
	bsf	porta,R3k	;turn 3k3 off
	bsf	portb,Capdis	;discharge capacitor
        call    delay
	bcf 	portb,Capdis	;start charging capacitor
	call	zeroacc		;clear counts
loop	btfss	portb,CompIn    ;wait for high
	goto	loop
        movlw   0x85
        movwf   scratch         ;delay to adjust zero
zeroadj decfsz  scratch,f       
        b       zeroadj
loop2	btfss   portb,CompIn	;wait for low again
	goto    charged
        call	inc	        ;increment accumulator
	nop
nex2	goto	nex3
nex3	goto	nex4
nex4	goto	nex5
nex5	goto    loop2
charged
	call	calc
	bsf	portb,Capdis    ;discharge capacitor
	bsf	porta,R3k	;turn resistor off
	movf	0x3b,w
	movwf	0x3c
	movf	0x3a,w
	movwf	0x3b
	movf	0x39,w
	movwf	0x3a
	movf	0x38,w
	movwf	0x39
	movf	0x37,w
	movwf	0x38
	movlw	'.'
	movwf	0x37		
	b disp32
;
;____________________________________________________________
;		Measure Value of Capacitance - high range
;
captesth
        call    cap
	bsf	portb,Capdis	;discharge capacitor
	call 	delay		;wait for it to really discharge
	bcf 	portb,Capdis	;start charging capacitor
	call	zeroacc		;clear counts
	bcf	porta,R3k	;turn 3k3 on
looph   btfss	portb,CompIn	;wait for high
	goto	looph
loop2h	btfss   portb,CompIn	;wait for low again
	goto    over
	goto	ntex1
ntex1	goto	ntex2
ntex2	goto	ntex3
ntex3	goto	ntex4
ntex4	goto	ntex5
ntex5	b	ntex6
ntex6	b	ntex7
ntex7	call	inc	        ;increment accumulator
	goto    loop2h
over
	movf	acc+2,f		;check nonzero
	bnz	notyet
	movf	acc+1,f		;check < 1024
	bnz     notyet
        movf    acc,w
        andlw   0x80
	bz      captestl        ;low value of cap
				;so measure at low
				;range
notyet	call	calc
	bsf	portb,Capdis	;discharge capacitor
	bsf	porta,R3k	;turn resistor off
	movf	0x3b,w
	movwf	0x3c
	movf	0x3a,w
	movwf	0x3b
	movlw	'.'
	movwf	0x3a		
	call    disp32
        b       wait
;
;____________________________________________________________
;
timeout
        call timer_init
        call c_err
        call disp32
circle  ;;            *******   Main Routine   ********
	call zero
	call testesr
	call zero
	call captesth
        call check
	goto circle
;------------------------------------------------------------
wrok          ;Write OK on display
        movlw   'O'
        movwf   0x4e
        movlw   'K'
        movwf   0x4f
        return
;
;------------------------------------------------------------
wrng          ;Write NG on display
        movlw   'N'
        movwf   0x4e
        movlw   'G'
        movwf   0x4f
        return
;
;------------------------------------------------------------
check                     ;Check whether ESR is within range
        movlw   ' '
        movwf   0x4e
        movwf   0x4f      ;clear earlier message
        movlw   '.'       ;Check for correct range
        xorwf   0x3a,w
        btfss   status,z 
        return 
;                       ;check for cap values
        movlw 0x36
        movwf fsr
        movf  indf,w
        addlw 0 - '0'
        bnz   more100   ; >1000
        incf  fsr,f
        movf  indf,w
        addlw 0 - '0'
        bnz   more100   ; >100
        incf  fsr,f
        movf  indf,w
        addlw 0 - '0'
        bnz   more10    ; >10
        incf  fsr,f
        movf  indf,w
        addlw 0 - '0'
        bnz   moreone   ; >1
        return
        
more100 ; If cap > 100 then ESR < 1
        movlw '.'
        xorwf 0x48,w
        bnz   wrng
        movlw '0'
        xorwf 0x47,w
        bnz   wrng
        movlw '0'
        xorwf 0x46,w
        bnz   wrng
        goto  wrok
more10  ; If cap > 10 then ESR < 5
        movlw '.'
        xorwf 0x48,w
        bnz   wrng
        movlw 0xcb
        addwf 0x47,w
        bc    wrng
        movlw '0'
        xorwf 0x46,w
        bnz   wrng
        goto  wrok
moreone ; If cap > 1 then ESR < 10
        movlw '.'
        xorwf 0x48,w
        bnz   wrng
        movlw '0'
        xorwf 0x46,w
        bnz   wrng
        goto  wrok
        
;
;------------------------------------------------------------
;
     end
;------------------------------------------------------------
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;============================================================
