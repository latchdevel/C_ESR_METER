;
;  Russian capacitance and ESR meter for electrolytic capacitors
;  Измеритель емкости и ESR электролитических конденсаторов (https://pro-radio.online/measure/3288/)
;      C/ESR meter (метр)
;
;  Autor (Автор)     Gints Oleg (Гинц Олег) http://www.rlc-esr.ru/index.php/ru/izmeritel-s-i-esr
;  Version (Версия)  1.01
;  Date (Дата)       20/04/2007
;
;  The program uses fragments of the FLC meter code (В программе использованы фрагменты кода измерителя FLC)
;  Alexander Buevsky, Minsk, Bielorrusia (Александра Буевского, г.Минск, Беларусь)
;  
;  Program update (Доработка программы) Misyuta Gennady (Мисюта Геннадий)
;  Version (Версия)  1.17
;  Date (Дата)       18/10/2019
;   - added battery charge indicator
;   - added correction constant for the minimum capacitance of the capacitor
;   - added ESR and Cx software filters for more stable display readings
;
; Microchip Assembler (MPASM) languaje, not MPLAB XC8 PIC Assembler (pic-as)
; Added english comments to mains sections by Jorge Rivera in June 2023
; See https://github.com/latchdevel/C_ESR_METER
;
; MICROCONTROLLER PIC16F876A OUTPUTS ASSIGNMENT (НАЗНАЧЕНИЕ ВЫВОДОВ КОНТРОЛЛЕРА PIC16F876A)
;*******************************************************************************************
; PIN  *  NAME                          * FUNCTION (НОГА * ИМЯ * НАЗНАЧЕНИЕ)
;*******************************************************************************************

;  1   *  MCLR/Vpp                      * Reset (Сброс)
;  2   *  RA0/AN0                       * ADC to measure U330 (выход ДУ) (Ку=330)
;  3   *  RA1/AN1                       * ADC to measure U33 (выход ДУ) (Ку=33)
;  4   *  RA2/AN2/Vref-                 * Button key Menu/Set Кн. Set coeff./Set "0"
;  5   *  RA3/AN3/Vref+                 * ADC to battery voltage monitoring (Контроль напряжения батареи) v1.17
;  6   *  RA4/T0CKI                     * Button key + (plus/test) Кн.+/Test
;  7   *  RA5/AN4/SS                    * Button key - (minus) Кн.-
;  8   *  Vss                           * GND
;  9   *  OSC1/CLKIN                    * Quartz 20 MHz (Кварц 20 МГц)
; 10   *  OSC2/CLKOUT                   * Quartz 20 MHz (Кварц 20 МГц)
; 11   *  RC0/T1OSO/T1CKI               * Charge Cx I=10mA (charge when LOW) (Заряд Сх)
; 12   *  RC1/T1OSI/CCP2                * Discharge Cx (Разряд Сх)
; 13   *  RC2/CCP1                      * Upper charging level comparator Cx (LOW if U33>2.0v) (Компаратор верхнего уровня зарядки Сх)
; 14   *  RC3/SCK/SCL                   * In_N_Gnd "-" to the ground "R" remote control (вх."-" на землю)
; 15   *  RC4/SDI/SDA                   * In_P_Cx "+" to Сх
; 16   *  RC5/SDO                       * In_N_Cx "-" to Сх
; 17   *  RC6/TX/CK                     * Lower charge level comparator Cx (LOW if U33>1.0v) (Компаратор нижнего уровня зарядки Сх)
; 18   *  RC7/RX/DT                     * Unused
; 19   *  Vss                           * +5V
; 20   *  Vdd                           * GND
; 21   *  RB0/INT                       * LCD_D4
; 22   *  RB1                           * LCD_D5
; 23   *  RB2                           * LCD_D6
; 24   *  RB3/PGM                       * LCD_D7
; 25   *  RB4                           * LCD_R/S
; 26   *  RB5                           * LCD_E
; 27   *  RB6/PGC                       * Unused
; 28   *  RB7/PGD                       * Unused

;****************************************************************************************

    list    p=PIC16F876a
    #include P16F876a.inc    ;20.000 MHz
    __CONFIG _CP_OFF & _BODEN_OFF & _HS_OSC & _WRT_OFF & _WDT_OFF & _PWRTE_ON & _DEBUG_OFF & _CPD_OFF & _LVP_OFF

Port_A_Config   equ b'11111111'         ;ADCs and button keys (all inputs)
;Port A bit equates     ||||||
;                       |||||·- RA0     ADC to measure U330
;                       ||||·-- RA1     ADC to measure U33
Kn_Set          equ 2;  |||·--- RA2     Button key Menu/Set
;                       ||·---- RA3     ADC to measure battery voltage (v1.17)
Kn_Plus         equ 4;  |·----- RA4     Button key + (plus/test)
Kn_Minus        equ 5;  ·------ RA5     Button key - (minus)

Port_B_Config   equ b'11000000'         ;Display LCD 16x2 (4-bit mode outputs)
;Port B bit equates   ||||||||
;                     |||||||·- RB0     LCD Data bit 4      
;                     ||||||·-- RB1     LCD Data bit 5
;                     |||||·--- RB2     LCD Data bit 6
;                     ||||·---- RB3     LCD Data bit 7
;                     |||·----- RB4     LCD Register Select (R/S)
LCD_E           equ 5;||·------ RB5     LCD Enable (E)
;                     |·------- RB6     (unused)
;                     ·-------- RB7     (unused)    

Port_C_Config   equ b'11000100'         ;Manage outpus to Cap and inputs from external LM393 comparator
;Port C bit equates   ||||||||
Cap_Charge      equ 0;|||||||·- RC0     Cap_Charge      Output      Cap charge when LOW "C"
Cap_Discharge   equ 1;||||||·-- RC1     Cap_Discharge   Output      Cap discharge when HIGH "D"
Comp_Up         equ 2;|||||·--- RC2     Comp_Up         Input       LOW if U33 > 2.0v
In_N_Gnd        equ 3;||||·---- RC3     In_N_Gnd        Output      RC3-GND- "R" (remote control)
In_P_Cx         equ 4;|||·----- RC4     In_P_Cx         Output      RC4-CX "+"
In_N_Cx         equ 5;||·------ RC5     In_N_Cx         Output      RC5-CX "-"
Comp_Low        equ 6;|·------- RC6     Comp_Low        Input       LOW if U33 > 1.0v
;                     ·-------- RC7     (unused)        Input       (unused) 

;Port C cap states      -+R DC
ESR_ready       equ b'00110011'         ;Discharge, "+" and "-" Remote control on Cx           (вкл. разряд, "+" и "-" ДУ на Cx)
ESR_start       equ b'00110000'         ;Charge,    "+" and "-" Remote control on Cx           (вкл. заряд, "+" и "-" ДУ на Cx)
Cap_ready       equ b'00011011'         ;Discharge, "-" Remote control to ground,  "+" to Cx   (вкл. разряд, "-" ДУ на землю, "+" на Cx)
Cap_start       equ b'00011000'         ;Charge,    "-" Remote control to ground,  "+" to Cx   (вкл. заряд, "-" ДУ на землю, "+" на Cx)
Cap_start2      equ b'00110000'         ;Charge,    "-" Remote control on Cx,      "+" on Cx   (вкл. заряд, "-" ДУ на Cx, "+" на Cx)

;Register bits flags (биты регистра)
TIMEOUT         equ 0                   ;for the allotted time, the measurements did not wait for the end of the charge
                                        ;за отведенное время измерения не дождались окончания заряда
INSIGZERO       equ 1                   ;leading zeros (незначащие нули)
POINT           equ 2                   ;decimal point (десятичная точка)
DISCHARGE       equ 3                   ;value check. digits when outputting (проверку знач. разрядов при выводе)
CHECK10OM       equ 4                   ;check 10 ohm (10 Ом)
SAVECONST       equ 5                   ;constant change flag (флаг изменения константы)

;Register bits Flag_Key (биты регистра)
STARTSETKEY     equ 0                   ;flag for pressing the SET button in constant mode (флаг нажатия SET кнопки в режиме констант)

_BAT_MAX        equ 3
_BAT_1          equ 4
_BAT_2          equ 5
_BAT_3          equ 6
_BAT_MIN        equ 7

Max_Count       equ .50                 ;maximum number (1 byte, max 256) of TMR0 overflows when counting
                                        ;count step - 0.2 µs, 65536*0.2=13107.2 µs - one overflow
                                        ;or at I=10mA 15 counts/uF 65536/15=4369 uF - one overflow
                                        ;Let Cx max=150000uF, 150000/4369=34
                                        ;Taking into account the charge time to the lower limit, the constant must be doubled

                                        ;максимальное число (1 байт, не более 256) переполнений TMR0 при счете
                                        ;шаг счета - 0.2 мкс, 65536*0.2=13107.2 мкс - одно переполнение
                                        ;или при I=10mA 15 отсчетов/мкФ 65536/15=4369 мкф - одно переполнение
                                        ;Пусть Сх мах=150000мкФ, 150000/4369=34
                                        ;Учитывая время заряда до нижней границы константу надо удвоить

KEY_FAST        equ .3                  ;time of the pressed button to switch to the fast counting mode, seconds
                                        ;время нажатой кнопки для перехода в быстрый режим счёта, секунд

;****************************************************************************************

    cblock    0x35      ;0x20-0x34 for FLOATING POINT LIBRARY "math16.inc" (fp24.a16)

        U330_L                          ;0x35 Output voltage DU, Ku=330, low byte (Напряжение с выхода ДУ, Ку=330, младший байт)
        U330_H                          ;0x36 Output voltage DU, Ku=330, high byte (Напряжение с выхода ДУ, Ку=330, старший байт)
        U33_L                           ;0x37 Output voltage DU, Ku=33, low byte (Напряжение с выхода ДУ, Ку=33, младший байт)
        U33_H                           ;0x38 Output voltage DU, Ku=33, high byte (Напряжение с выхода ДУ, Ку=33, старший байт)
        TMR1_Count                      ;0x39 Overflow counter TMR1 (Счетчик переполнений TMR1)
        TMR0_Count                      ;0x3A Overflow counter TMR0 (Счетчик переполнений TMR0)
        Max_ADC_Count                   ;0x3B ADC overshoot counter>=0x300 with multiple ESR measurements (Счетчик превышений АЦП>=0x300 при многократном измерении ESR)
        Key_Press_Time                  ;0x3C button hold time counter (счётчик времени удержания нажатой кнопки)
        Bat_sign                        ;0x3D current battery icon on the display (текущий значёк заряда батареи на дисплее)
        Flags                           ;0x3E
        Flag_Key                        ;0x3F flag buttons (флаг кнопок)

        ;Data blocks (Блоки данных)
        Dly0                            ;0x40 Stores 3 bytes of data for the delay count
        Dly1                            ;0x41 Dly0 is the least significant byte
        Dly2                            ;0x42 while Dly3 is the most significant byte

        Temp                            ;0x43                
        Temp1                           ;0x44
        Temp2                           ;0x45
        Temp3                           ;0x46
        Temp4                           ;0x47
 
        Count1                          ;0x48
        Count2                          ;0x49

        T0                              ;0x4A
        T1                              ;0x4B

        ;Data blocks (Блоки данных)
        T2                              ;0x4C high byte (Старший байт)
        T3                              ;0x4D
        T4                              ;0x4E
        T5                              ;0x4F low byte (Младший байт)

        AX                              ;0x50 high byte
        A0                              ;0x51
        A1                              ;0x52
        A2                              ;0x53 low byte

        A3                              ;0x54
        A4                              ;0x55
        A5                              ;0x56

        BCD0                            ;0x57 low byte
        BCD1                            ;0x58
        BCD2                            ;0x59
        BCD3                            ;0x5A
        BCD4                            ;0x5B high byte

        EE_ADR                          ;0x5C auxiliary cell for working with EEPROM (вспомогательная ячейка для работы с EEPROM)
        EE_DATA                         ;0x5D
        NZ                              ;0x5E number of significant digits when displayed on the indicator (число значащих разрядов при выводе на индикатор)
        NC                              ;0x5F constant number (номер константы)
        Const_ADR                       ;0x60 address of constant in EEPROM (адрес константы в EEPROM)

        Index_Buf_Cx                    ;0x61 pointer to the address of the oldest dimension in the buffer Buf_Cx (указатель на адрес самого старого измерение в буфере Buf_Cx)
        Buf_Cx_1 :3                     ;0x62 0x63 0x64 capacitance measurement buffer (буфер измерения ёмкости)
        Buf_Cx_2 :3                     ;0x65 0x66 0x67 
        Buf_Cx_3 :3                     ;0x68 0x69 0x6A 

    endc

;for filter Cx constants (для фильтра Cx константы)
BUF_Cx_COUNT_MAX    equ 3               ;number of measurements in buffer Buf_Cx (количество измерений в буфере Buf_Cx)
BUF_CX_END          equ Buf_Cx_1+(BUF_Cx_COUNT_MAX*3)

;for ESR filter constants and variables (для фильтра ESR константы и переменные)
FILTER_CYCLE_MAX    equ 4               ;number of median filter cycles (power-of-2 multiple) (количество циклов медианного фильтра (кратно степени 2))
Filter_cycle        equ Temp1

BUF_COUNT_MAX       equ 5               ;the size of each of the median filter buffers (размер каждого из буферов медианного фильтра)
Buf_Count           equ Temp2

BUF_START_U330      equ 0x20
BUF_START_U33       equ 0x2A
MEDIAN_U330         equ BUF_START_U330+BUF_COUNT_MAX
MEDIAN_U33          equ BUF_START_U33+BUF_COUNT_MAX

;copies of registers upon entering the interrupt (available from any bank 0x70...0x7F) (копии регистров при входе в прерывание (доступны из любого банка 0x70...0x7F))
    cblock    0x7F-3
        W_TEMP                          ;save context on interrupts (сохранение контекста при прерываниях)
        STATUS_TEMP
        PCLATH_TEMP
    endc
;=========================
;    MACROS (МАКРОСЫ)
;=========================
bank0    macro
    bcf    STATUS, RP0
    endm

;----------------------------------------------------------------
bank1    macro
    bsf    STATUS, RP0
    endm

;----------------------------------------------------------------
Dly24    MACRO    DLY
;Take the delay value argument from the macro, precalculate
;the required 3 RAM values and load the The RAM values Dly2,Dly1
;and Dly0.
    banksel Dly0
    movlw  DLY & H'FF'
    movwf  Dly0
    movlw  DLY >>D'08' & H'FF'
    movwf  Dly1
    movlw  DLY >>D'16' & H'FF'
    movwf  Dly2
;Bytes are shifted and anded by the assembler to make user
;calculations easier.
    endm

;==========================

    ORG    0x2100        ; EEPROM area (Область EEPROM)
;Data           ; Address in EEPROM (Данные     ; Адрес    в EEPROM)

;correction factors for: (корректирующие коэффициенты для)
USR_1           DE 0x00, 0x00, 0x03, 0xE8       ; 1000 - limit 1 ohm (предела 1 Ом)
USR_10          DE 0x00, 0x00, 0x03, 0xE8       ; 1000 - limit 10 ohm (предела 10 Ом)

USR_Cx          DE 0x00, 0x00, 0x03, 0xE8       ; 1000 - capacitance measurements (измерения емкости)
USR_1_Cx        DE 0x00, 0x00, 0x03, 0xE8       ; 1000 - capacitance measurements 1uF (измерения емкости 1 мкф)

;numbers in FLOATING POINT LIBRARY format
U0_ESR_1        DE 0x81, 0x40, 0x00, 0x00       ; 6 - "0" at the limit of 1 ohm (на пределе 1 Ом)
U0_ESR_10       DE 0x7F, 0x00, 0x00, 0x00       ; 1 - "0" at the limit of 10 ohm (на пределе 10 Ом)

;multipliers for calculations: (множители для расчето)
M_ESR_1         DE 0x75, 0x40, 0x30, 0x0C       ; 1/682      = 0x7540300C -> 0.00146627  (0.001466275659824047) in Microchip 24-bit format (в формате Microchip 24-bit)
M_ESR_10        DE 0x78, 0x74, 0x89, 0x8D       ; 1/67       = 0x7874898D -> 0.0149253   (0.014925373134328358) in Microchip 24-bit format (в формате Microchip 24-bit)
M_Cx            DE 0x74, 0x2E, 0xC3, 0x3E       ; 1/(15*100) = 0x742EC33E -> 0.000666666 (0.000666666666666666) in Microchip 24-bit format (в формате Microchip 24-bit)
                ;coarse correction for, for example, 10000uF (коррекция грубая для, например, 10000 мкф)

add_Cx          DE 0x88, 0x7A, 0x00, 0x00       ; 1000 Correction accurate for 1uF in Microchip 24-bit format (коррекция точная для 1 мкф) (в формате Microchip 24-bit)

;==========================
    org    0x700        ; last 256 bytes of page 1 of program memory (последние 256 байт 1-й страницы памяти программ)
Table    addwf    PCL,F
omega   dt    b'00000000'   ;omega sign "Ω" character (знак омега)
        dt    b'00001110'
        dt    b'00010001'
        dt    b'00010001'
        dt    b'00010001'
        dt    b'00001010'
        dt    b'00011011'
        dt    b'00000000'

mu      dt    b'00000000'   ;mu sign "μ" character for prefix micro, which represents one millionth, or 10E−6.
        dt    b'00000000'
        dt    b'00010010'
        dt    b'00010010'
        dt    b'00010010'
        dt    b'00011110'
        dt    b'00010001'
        dt    b'00010000'

bat_max dt    b'00000000'   ;sign batt max (знак макс. бат.)
        dt    b'00001110'
        dt    b'00011111'
        dt    b'00011111'
        dt    b'00011111'
        dt    b'00011111'
        dt    b'00011111'
        dt    b'00000000'

bat_1   dt    b'00000000'   ;sign batt (знак бат.)
        dt    b'00001110'
        dt    b'00010001'
        dt    b'00011111'
        dt    b'00011111'
        dt    b'00011111'
        dt    b'00011111'
        dt    b'00000000'

bat_2   dt    b'00000000'   ;sign batt (знак бат.)
        dt    b'00001110'
        dt    b'00010001'
        dt    b'00010001'
        dt    b'00011111'
        dt    b'00011111'
        dt    b'00011111'
        dt    b'00000000'

bat_3   dt    b'00000000'   ;sign batt (знак бат.)
        dt    b'00001110'
        dt    b'00010001'
        dt    b'00010001'
        dt    b'00010001'
        dt    b'00011111'
        dt    b'00011111'
        dt    b'00000000'

bat_min dt    b'00000000'   ;sign batt (знак бат.)
        dt    b'00001110'
        dt    b'00010001'
        dt    b'00010001'
        dt    b'00010001'
        dt    b'00010001'
        dt    b'00011111'
        dt    b'00000000'

_Const      dt "Coeff. for",0
_ESR        dt "ESR",0
_Cx         dt " Cx ",0
_Time_out   dt " Cx ---",0
_1_ohm      dt " 1 ",1,0
_10_ohm     dt " 10 ",1,0
_tst_1      dt "1",1,"=",0
_tst_10     dt " 10",1,"=",0
_write_U0   dt "U0 ---> EEPROM     ",0
;_ready     dt "It is ready!",0
_save_const dt "Save Constant",0
_1_Cx       dt " C min",0

;*******************************************************************************
;  PROGRAM START (НАЧАЛО   ПРОГРАММЫ)
;*******************************************************************************
    org    0x00
    nop            ;for MPLAB-ICD2
    goto    init
;------------------ Interrupt ------------------
    org    0x004

save_context
    movwf   W_TEMP              ;save W
    swapf   STATUS,W            ;swap STATUS, W
    clrf    STATUS
    movwf   STATUS_TEMP         ;save status
    movf    PCLATH,W
    movwf   PCLATH_TEMP         ;save PCLFTH
    bank0
TMR0_INT
    btfss   INTCON,T0IF         ;TMR0 overflow? 
    goto    TMR1_INT            ;if not overflow jump to TMR1_INT

    bcf     INTCON,T0IF         ;clear interrupt flag
    decfsz  TMR0_Count          ;Decrement TMR0_Count and skip if zero
    goto    restore_context
    goto    Time_out            ;TMR0_Count=0
TMR1_INT
    btfss   PIR1,TMR1IF
    goto    restore_context
    bcf     PIR1, TMR1IF        ;clear the timer overflow flag (очищаем флаг переполнения таймера)
    incfsz  TMR1_Count,F
    goto    restore_context
Time_out
    bcf    T1CON, TMR1ON        ;stop TMR1 (остановить TMR1)
    bcf    INTCON,GIE           ;disable interrupts (запрещаем прерывания)
    bsf    Flags,TIMEOUT        ;Time out 
                                ;for the allotted time, the measurements did not wait for the end of the charge
                                ;за отведенное время измерения не дождались окончания заряда
    clrf   TMR1_Count

restore_context
    movf    PCLATH_TEMP,W
    movwf   PCLATH
    swapf   STATUS_TEMP,W       ;fetch status, reswap nibbles
    movwf   STATUS              ;restore status
    swapf   W_TEMP,F            ;swap nibbles in preparation
    swapf   W_TEMP,W            ;for the swap restoration of w
    retfie                      ;return from interrupt

;-----------------------------------------------
init
    bank0
    clrf    Flags
    clrf    Flag_Key
    clrf    INTCON
    clrf    PCLATH
    clrf    PORTA
    clrf    PORTB
    movlw   ESR_ready           ;incl. discharge, "+" and "-" remote control on Cx (вкл. разряд, "+" и "-" ДУ на Сх)
    movwf   PORTC

    bank1
    movlw   Port_A_Config
    movwf   TRISA

; ADC initialization (инициализация АЦП)
    movlw   b'10000100'         ;right justify, Vdd, Vss, AN0, AN1, AN3 (правое выравнивание, Vdd, Vss, AN0, AN1, AN3)
    movwf   ADCON1

    movlw   Port_B_Config
    movwf   TRISB
    movlw   Port_C_Config
    movwf   TRISC

; LCD initialization to 4-bit mode (Инициализация LCD в 4-х битный режим)
InitLCD
    call    Delay_5_ms
    call    Delay_5_ms
    call    Delay_5_ms          ;pause 15 ms after power on (пауза 15 мс после вкл питания)
    bank0
    movlw   3
    movwf   Count1
    movwf   PORTB
SetLoop
    bsf     PORTB,LCD_E         ;send 0x30 command 3 times to initialize LCD (для инициализации LCD 3 раза посылается команда 0x30)
    nop
    nop
    nop
    bcf     PORTB,LCD_E
    call    Delay_5_ms
    decfsz  Count1,f
    goto    SetLoop

    movlw   2                   ;4-x битный
    movwf   PORTB
    call    Send
    movlw   28                  ;4-х битный, 2 строки, 5х7
    call    CmdLCD
    movlw   0C                  ;Включить дисплей
    call    CmdLCD
    movlw   6
    call    CmdLCD
    call    Load_ZG             ;Загрузить символы мю и омега
    call    ClrDSP              ;Очистить дисплей
;--------------------------------------------------
    clrf    Key_Press_Time
    btfsc   PORTA, Kn_Set       ;was the SET button pressed when the power was turned on? (кнопка SET нажата при включении питания?)
    goto    Main
;------------ режим установки констант ------------
    movlw    3
    movwf    NC
Const_Loop

C_Kn_Set
    btfsc   PORTA, Kn_Set
    goto    C_Kn_Set_open       ;waiting for the SET button to be released (ждем отпускания кнопки SET)
    btfsc   Flag_Key,STARTSETKEY
    goto    C_Kn_Set
  ;первоначальный момент нажатия кнопки SET
    bsf     Flag_Key,STARTSETKEY
    btfsc   Flags,SAVECONST     ;флаг изменения константы
    goto    C_Kn_Set_save       ;константа изменилась, надо сохранить
  ;выбор следующей константы
    ; incf      NC,w
    ; xorlw     b'00000011'
    ; btfss     STATUS,Z
    ; xorlw     b'00000011'     ;максимально 3 константы
    ; movwf     NC

    incf    NC,f
    btfsc   NC,2
    bcf     NC,2                ;максимально 4 константы
    goto    c_1
C_Kn_Set_save
    call    Save_Const          ;константа изменилась, надо сохранить
    call    ClrDSP
    movlw   LOW _save_const     ;сообщение на дисплее
    call    Read_String
    call    Delay_1_sec
    goto    c_1
C_Kn_Set_open
    bcf     Flag_Key,STARTSETKEY

C_Kn_Plus
    movlw   KEY_FAST*2
    movwf   Key_Press_Time      ;начальная установка времени нажатой кнопки
C_Kn_Plus_L1
    btfsc   PORTA, Kn_Plus
    goto    C_Kn_Minus
    call    IncB
    goto    C_Kn_Plus_L1

C_Kn_Minus
    movlw   KEY_FAST*2
    movwf   Key_Press_Time      ;начальная установка времени нажатой кнопки
C_Kn_Minus_L1
    btfsc   PORTA, Kn_Minus
    goto    Const_Loop
    call    DecB
    goto    C_Kn_Minus_L1
    goto    Const_Loop
;-------------------------------------------------------
c_1
    bcf    Flags,SAVECONST      ;Очищаем флаг изменения константы
    call    ClrDSP              ;Очистить дисплей
    movlw   LOW _Const
    call    Read_String
    movlw   HIGH $
    movwf   PCLATH
    movf    NC,W
    addwf   PCL,F               ;табличный переход
    goto    const_1_ohm         ;+0
    goto    const_10_ohm        ;+1
    goto    const_Cx            ;+2
    goto    const_1_Cx          ;+3
c_2
    call    ShowX
    goto    Const_Loop
;-------------------------------------------------------
const_1_ohm
    movlw   LOW USR_1
    movwf   Const_ADR
    call    EEPROM_To_B
    movlw   LOW _1_ohm
    call    Read_String
    goto    c_2
;-------------------------------------------------------
const_10_ohm
    movlw   LOW USR_10
    movwf   Const_ADR
    call    EEPROM_To_B
    movlw   LOW _10_ohm
    call    Read_String
    goto    c_2
;-------------------------------------------------------
const_1_Cx
    movlw   LOW USR_1_Cx
    movwf   Const_ADR
    call    EEPROM_To_B
    movlw   LOW _1_Cx
    call    Read_String
    goto    c_2
;-------------------------------------------------------
const_Cx
    movlw   LOW USR_Cx
    movwf   Const_ADR
    call    EEPROM_To_B
    movlw   LOW _Cx
    call    Read_String
    goto    c_2

;===========================================================
Main
    call    TMR1_init
    call    TMR0_init           ;TMR0 to prevent freezes when measuring capacitance 
                                ;TMR0 для предотвращения зависаний при измерении емкости

    call    Cx_clear            ;clear Cx buffer (очистить буфер Cx)

;------------
ESR_measure
    clrf    U330_H
    clrf    U330_L
    clrf    U33_H
    clrf    U33_L
    clrf    Max_ADC_Count
    movlw   FILTER_CYCLE_MAX
    movwf   Filter_cycle
    
    btfsc   PORTA, Kn_Plus      ;if the plus button is pressed (если нажата кнопка 'плюс')
    goto    ADC_Start
    
;------------  ESR measurement without filtering, directly from the ADC (измерение ESR без фильтрации, прямо с АЦП)
    movlw   ESR_start           ;incl. charge, "+" and "-" remote control on Cx (вкл. заряд, "+" и "-" ДУ на Сх)
    movwf   PORTC

    movlw   0x4                 ;Delay 3.6 ms (18 cycles) for the end of the transition processes - PICK UP!!!
    call    Delay_go            ;Задержка 3.6мкс (18 циклов) для окончания перех.процессов - ПОДОБРАТЬ!!!

    bcf     PORTC, In_P_Cx      ;turn off Szap from Cx (отключаем Сзап от Сх)
    nop                         ;delay one op (4 cycles @20Mhz 200ns)
    bsf     PORTC, Cap_Charge   ;off Isar. (выкл. Iзар.)
    
    call    ADC_U330
    movf    ADRESH,w
    movwf   U330_H
    bank1
    movf    ADRESL,W
    bank0
    movwf   U330_L    
    
    call    ADC_U33    
    movlw   Cap_ready           ;incl. discharge, "-" remote control to ground, "+" to Cx (вкл. разряд, "-" ДУ на землю, "+" на Сх)
    movwf   PORTC
    movf    ADRESH,w
    movwf   U33_H
    bank1
    movf    ADRESL,W
    bank0
    movwf   U33_L

    goto    ADC_End
;------------ 
    
ADC_Start  
    movlw   BUF_COUNT_MAX
    movwf   Buf_Count
    
    ;clear buffers U330 and U33 (очистить буферы U330 и U33)
    movlw   .20    
    movwf   Temp
    movlw   BUF_START_U330+.20    
    movwf   FSR
ADC_Clear
    decf    FSR,f
    clrf    INDF
    decfsz  Temp,f
    goto    ADC_Clear
    
;------------ ESR measurement (Измерение ESR) ------------
ADC_Loop
    movlw   ESR_start           ;incl. charge, "+" and "-" remote control on Cx (вкл. заряд, "+" и "-" ДУ на Сх)
    movwf   PORTC

    movlw   0x4                 ;Delay 3.6 ms (18 cycles) for the end of the transition processes - PICK UP!!!
                                ;Задержка 3.6мкс (18 циклов) для окончания перех.процессов - ПОДОБРАТЬ!!!
    call    Delay_go

    bcf     PORTC, In_P_Cx      ;turn off Szap from Cx (отключаем Сзап от Сх)
    nop                         ;delay one op (4 cycles @20Mhz 200ns)
    bsf     PORTC, Cap_Charge   ;off Isar. (выкл. Iзар.)

;------------
    ;collect ADC measurement data (собираем данные измерений АЦП)
    call    ADC_U330
    ;save the measurement result to the beginning of the buffer (сохраняем результат измерений в начало буфера)
    movlw   BUF_START_U330
    movwf   FSR
    movf    ADRESH,w
    movwf   INDF
    incf    FSR,f
    bank1
    movf    ADRESL,W
    bank0
    movwf   INDF

    call    ADC_U33    
    movlw   Cap_ready           ;incl. discharge, "-" remote control to ground, "+" to Cx (вкл. разряд, "-" ДУ на землю, "+" на Сх)
    movwf   PORTC
    ;save the measurement result to the beginning of the buffer (сохраняем результат измерений в начало буфера)
    movlw   BUF_START_U33
    movwf   FSR
    movf    ADRESH,w
    movwf   INDF
    incf    FSR,f
    bank1
    movf    ADRESL,W
    bank0
    movwf   INDF

    ;buffer sorting U330 (сортировка буфера U330)
    movlw   BUF_START_U330
    call    Buf_Sorting

    ;buffer sorting U330 (сортировка буфера U33)
    movlw   BUF_START_U33
    call    Buf_Sorting

    call    Delay_200_us
    call    Delay_200_us

    ;make several measurements to fill and sort buffers U330 and U33
    ;делаем несколько измерений для заполнения и сортировки буферов U330 и U33
    decfsz  Buf_Count,f
    goto    ADC_Loop


    ;add all U330 measurements to the median (складываем все измерения U330 с медианой)
    movlw   LOW MEDIAN_U330
    movwf   FSR
    movf    INDF,w              ;INDF(LOW MEDIAN_U330)
    decf    FSR,f
    addwf   U330_L,f
    movf    INDF,w              ;INDF(HIGH MEDIAN_U330)
    btfsc   STATUS,C
    incfsz  INDF,w              ;INDF(HIGH MEDIAN_U330)
    addwf   U330_H,f
    

    ;add all U33 measurements to the median (складываем все измерения U33 с медианой)
    movlw   LOW MEDIAN_U33
    movwf   FSR
    movf    INDF,w              ;INDF(LOW MEDIAN_U33)
    decf    FSR,f
    addwf   U33_L,f
    movf    INDF,w              ;INDF(HIGH MEDIAN_U33)
    btfsc   STATUS,C
    incfsz  INDF,w              ;INDF(HIGH MEDIAN_U33)
    addwf   U33_H,f

    decfsz  Filter_cycle,f
    goto    ADC_Start

ADC_ROUND_U330      ; unused label
;------------
    ;find the average for U330 and round the result (находим среднее для U330 и округление результата)
    bcf    STATUS,C
    movlw  b'11110000'
    andwf  U330_L,f
    rrf    U330_H,f             ;divide by 2 (делим на 2)
    rrf    U330_L,f
    rrf    U330_H,f             ;divide by 4 (делим на 4)
    rrf    U330_L,f
    btfss  STATUS,C
    goto   ADC_ROUND_U33
    incf   U330_H,f             ;rounding, +1 to U330 (округление, +1 к U330)
    incfsz U330_L,f
    decf   U330_H,f
ADC_ROUND_U33
    ;find the average for U33 and round the result (находим среднее для U33 и округление результата)
    bcf    STATUS,C
    movlw  b'11110000'
    andwf  U33_L,f
    rrf    U33_H,f              ;divide by 2 (делим на 2)
    rrf    U33_L,f
    rrf    U33_H,f              ;divide by 2 (делим на 4)
    rrf    U33_L,f
    btfss  STATUS,C
    goto   ADC_End
    incf   U33_H,f              ;rounding, +1 to U33 (округление, +1 к U33)
    incfsz U33_L,f
    decf   U33_H,f
ADC_End

;------------ If ESR>10 ohm, no capacitance measurement -----------------
;------------ Если ESR>10 Ом, измерение емкости не выполняем ------------
    clrf    Flags
;                               ; "Reparando de todo" Youtube channel force Cx measurement. 
;    movlw   0x03
;    subwf   U33_H,W            ;if ADC readings>=0x300 (768) (если показания АЦП>=0x300 (768))
;    btfss   STATUS,C
;    goto    Cx_start           ;switch to capacitance measurement (переход на измерение емкости)
;    bsf     Flags,TIMEOUT      ;raise the Time Out flag (взводим флаг Time Out)
;    goto    Cx_end


;------------ Skip capacitance measurement for ESR DEBUG 
;    goto    Disp_ESR

;------------ Capacitor capacitance measurement ---------
;------------ Измерение емкости конденсатора ------------
Cx_start
    movlw   Cap_ready           ;incl. discharge, "-" remote control to ground, "+" to Cx (вкл. разряд, "-" ДУ на землю, "+" на Сх)
    movwf   PORTC

  ;reset timers to initial state (сбросить таймеры в исходное состояние)
    clrf    TMR0
    movlw   Max_Count           ;.50  maximum number of TMR0 overflows when counting       
    movwf   TMR0_Count          ;initial value of overflow counter TMR0 (начальное значение счетчика переполнений TMR0)
    clrf    TMR1L
    clrf    TMR1H
    clrf    TMR1_Count
    bsf     INTCON,GIE          ;enable interrupts (разрешить прерывания)

Cx_0
    btfsc   Flags,TIMEOUT       ;checking the Time Out flag (проверка флага Time Out)
    goto    Cx_end
    btfss   PORTC, Comp_Low     ;1 - Cx is discharged (Comp_Low = 1 -> U33 < 1.0v) (1 - Cx разрядился)
    goto    Cx_0                ;wait again 200 µs (ждем снова 200 мкс)
    call    Delay_200_us        ;delay to be sure (для надежности еще задержка)
    call    Delay_200_us

    movlw   0x03
    subwf   U330_H,W            ;if ADC readings>=0x300 (768) (если показания АЦП>=0x300 (768))
    btfss   STATUS,C            ;those. ESR>1 Ohm, capacitance is measured with ESR compensation (т.е. ESR>1 Ом, емкость измеряем с компенсацией ESR)
    goto    Cx_1

    movlw   Cap_start2          ;incl. charge, "-" RC on Cx, "+" on (вкл. заряд, "-" ДУ на Cx, "+" на Сх)
    movwf   PORTC
    movlw   0x4                 ;Delay 3.6 us (18 cycles) for charge C on the "-" input of the remote control (Задержка 3.6мкс (18 циклов) для заряда С на "-" входе ДУ)
    call    Delay_go
    bcf     PORTC,In_N_Cx       ;turn off the "-" remote control input from Cxx (отключаем "-" вход ДУ от Сх)
    goto    Cx_2

Cx_1
    movlw   Cap_start           ;incluido carga, "-" control remoto a tierra, "+" a Cx (вкл. заряд, "-" ДУ на землю, "+" на Сх)
    movwf   PORTC

Cx_2                            ;wait until U33 > 1.0v and start timer-1
    btfsc   Flags,TIMEOUT       ;checking the Time Out flag (проверка флага Time Out)
    goto    Cx_end
    btfsc   PORTC, Comp_Low     ;0 - Cx charged to the lower limit (U33 > 1.0v) (0 - Cx зарядился до нижней границы)
    goto    Cx_2
    bsf     T1CON, TMR1ON       ;start timer TMR1 (запускаем таймер TMR1)

Cx_3                            ;wait until U33 > 2.0v and stop timer-1
    btfss   PORTC,Comp_Up       ;0 - Cx charged to the upper limit (U33 > 2.0v) (0 - Cx зарядился до верхней границы)
    bcf     T1CON, TMR1ON       ;stop TMR1 (остановить TMR1)
    btfss   PORTC,Comp_Up       ;0 - Cx charged to the upper limit (U33 > 2.0v) (0 - Cx зарядился до верхней границы)
    bcf     T1CON, TMR1ON       ;stop TMR1 (остановить TMR1)
    btfss   PORTC,Comp_Up       ;0 - Cx charged to the upper limit (U33 > 2.0v) (0 - Cx зарядился до верхней границы)
    bcf     T1CON, TMR1ON       ;stop TMR1 (остановить TMR1)
    btfss   PORTC,Comp_Up       ;0 - Cx charged to the upper limit (U33 > 2.0v) (0 - Cx зарядился до верхней границы)
    bcf     T1CON, TMR1ON       ;stop TMR1 (остановить TMR1)
    btfss   PORTC,Comp_Up       ;0 - Cx charged to the upper limit (U33 > 2.0v) (0 - Cx зарядился до верхней границы)
    bcf     T1CON, TMR1ON       ;stop TMR1(остановить TMR1)

    btfsc   Flags,TIMEOUT       ;Comprobación de la bandera de tiempo de espera (проверка флага Time Out)
    goto    Cx_end
    btfsc   PORTC,Comp_Up       ;0 - Cx charged to the upper limit (U33 > 2.0v) (0 - Cx зарядился до верхней границы)
    goto    Cx_3
    bcf     T1CON, TMR1ON       ;stop TMR1 (остановить TMR1)

;--------------------------------------------------------
Cx_end
    bcf     INTCON,GIE          ;disable interrupts (запрещаем прерывания)
    movlw   Cap_ready           ;discharge, "-" remote control to ground, "+" to Cx (вкл. разряд, "-" ДУ на землю, "+" на Сх)
    movwf   PORTC
    
;--------------------------------------------------------
;We display the result on the indicator (Выводим результат на индикатор)
    call    ClrDSP              ;clear display (Очистить дисплей)

    btfss   Flags,TIMEOUT       ;Checking for timeout flag
    goto    Disp_Cx             ;If not timeout jump tp display Cx

    movlw   LOW _Time_out       ;If timeout flag is set
    call    Read_String         ;show Cx --- timeout
    call    Cx_clear            ;clear Cx buffer (очистить буфер Cx)
    goto    Disp_ESR            ;skip display Cx, jump to display ESR
    
;--------------------------------------------------------
Disp_Cx
    ;load new measurement data into median filter Cx, removing oldest measurement
    ;загрузить новые данные измерений в медианный фильтр Cx, удалив самое старое измерение
    movf    Index_Buf_Cx,w
    movwf   FSR
    movf    TMR1_Count,w
    movwf   INDF
    incf    FSR,f
    movf    TMR1H,w
    movwf   INDF
    incf    FSR,f
    movf    TMR1L,w
    movwf   INDF
    
    ;move the pointer to the next old buffer element (перевести указатель следующий старый элемент буфера)
    movlw    .3                 ;bytes in one dimension (байт в одном измерении)
    addwf    Index_Buf_Cx,f
    movlw    BUF_CX_END
    subwf    Index_Buf_Cx,w
    movlw    Buf_Cx_1    
    btfsc    STATUS,C
    movwf    Index_Buf_Cx       ;pointer to the beginning of the buffer (it is looped) (указатель на начало буфера (он закольцован))
    
    ;sort and filter result back to TMR1_Count, TMR1H, TMR1L (сортировка и результат фильтра назад в TMR1_Count, TMR1H, TMR1L)
    call    Buf_Sorting_Cx

;------------
    movlw   LOW _Cx
    call    Read_String

    movlw   LOW USR_1_Cx
    call    EEPROM_To_A         ;A = USR_1_Cx
    call    FLO2424             ;Integer to float conversion  --> A = float(A)   
    movlw   LOW add_Cx      
    call    EEPROM_To_B         ;B = add_Cx 
    call    FPS24               ;A = A - B --> A = float(USR_1_Cx) - add_Cx
    call    BEQUA               ;B = A     --> B = float(USR_1_Cx) - add_Cx

    clrf    AEXP                ;A = TMR1_Count, TMR1H, TMR1L
    movf    TMR1_Count,W
    movwf   AARGB0
    movf    TMR1H,W
    movwf   AARGB1
    movf    TMR1L,W
    movwf   AARGB2

    btfsc   PORTA, Kn_Plus      ;If the plus button is pressed, then the test output
    goto    Calc_Cx         

    call    BCD                 ;Если нажата кнопка плюс, то тестовый вывод
    movlw   BCD4                ;timer without processing (таймера без обработки)
    call    Disp_Full
    goto    Disp_ESR

Calc_Cx
    call    FLO2424             ;Integer to float conversion A = float(A)  --> A = integer(AARGB0, AARGB1, AARGB2)
    call    FPA24               ;A = A + B
                                ;A = float(integer(TMR1_Count,TMR1H,TMR1L)) + float(USR_1_Cx) - add_Cx
    
    movlw   low M_Cx
    call    EEPROM_To_B         ;B = M_Cx
    call    FPM24               ;A = A * B
                                ;A = (float(integer(TMR1_Count,TMR1H,TMR1L)) + float(USR_1_Cx) - add_Cx) * M_Cx
    movlw   low USR_Cx 
    call    X_To_B              ;review needed
    

    ;round up (округлить)
    movlw   0x7E
    movwf   BEXP
    movlw   0x00
    movwf   BARGB0
    movlw   0x00
    movwf   BARGB1              ; B = 0.5
    bcf     FPFLAGS,RND
    call    FPA24               ; A = A + 0.5 (Round)
    call    INT2424             ; Float to INT rounded to nearest whole number (Float в INT c округлением до ближайшего целого числа)

    clrf    AEXP
    call    BCD
    bsf     Flags,INSIGZERO     ;do not display leading zeros (не выводить лидирующие нули)
    movlw   3
    movwf   NZ                  ;number of significant digits, the rest will be 0 (число значащих разрядов, остальные будут 0)
    bsf     Flags,DISCHARGE     ;enable value checking. discharges at output (включить проверку знач. разрядов при выводе)

    movlw   BCD3
    call    DispBCD
    movlw   BCD3                ;показания увеличены в 10 раз,
    call    DispBCD             ;здесь сотни тысяч мкФ

    movlw   BCD2                ;десятки тысяч мкФ
    call    DispBCD
    movlw   BCD2                ;тысячи мкФ
    call    DispBCD

  ; если впереди были одни нули, разделитель не выводим
    btfsc   Flags,INSIGZERO
    goto    next_1
    movlw   " "                 ;разделитель тысяч
    call    CharLCD
next_1
    movlw   BCD1                ;сотни мкФ
    call    DispBCD
    btfsc   Flags,INSIGZERO     ;до сотен небыло значащих цифр,
    bsf     Flags,POINT         ;будем выводить десятые доли мкФ
    movlw   BCD1                ;десятки мкФ
    call    DispBCD

    bcf     Flags,INSIGZERO     ;проверка на =0 не нужна, выводим все подряд
    movlw   BCD0                ;единицы мкФ
    call    DispBCD

    btfss   Flags,POINT         ;нужен ли вывод десятичной точки
    goto    next_2              ;нет
    bcf     Flags,POINT         ;да
    call    DispDot             ;десятичная точка
    movlw   BCD0                ;десятые мкФ
    call    DispBCD
next_2
    call    DispSP
    movlw   2                   ;код мю
    call    CharLCD
    movlw   "F"
    call    CharLCD

;----------------------------

Disp_ESR
    btfss   PORTA, Kn_Plus      ;if the plus button is pressed (если нажата кнопка 'плюс')
    goto    tst_ESR             ;ESR measurement without filtering, directly from the ADC (измерение ESR без фильтрации, прямо с АЦП)

    bcf     Flags,CHECK10OM     ;clear flag more than 10 ohms (сброс флага больше 10 Ом)
    movlw   0x03
    subwf   U330_H,W            ;if ADC readings>=0x0300 (768) (если показания АЦП>=0x300 (768))
    ;btfsc   STATUS,C           ;check the second channel (10 Ohm) (проверяем второй канал (10 Ом))

                                ;if ADC readings>=0x0377 (880) check the second channel (10 Ohm) 
    btfss   STATUS,C           
    goto    chk_10 
    
    movlw   0x70
    subwf   U330_L,W
    btfsc   STATUS,C
    goto    chk_10

;Channel 1 ohm (Канал 1 Ом)
    call    ClrA
    movf    U330_H,W            ;amplifier Ku=330, limit 1 ohm (усилитель Ку=330, предел 1 Ом)
    movwf   AARGB0
    movf    U330_L,W
    movwf   AARGB1
    call    FLO1624             ;to 24 bit floating point

    movlw   low U0_ESR_1
    call    EEPROM_To_B
    call    FPS24               ; A = (A - EEPROM_U0_ESR_1) subtract zero offset (вычитаем смещение нуля)

    movlw   low M_ESR_1
    call    EEPROM_To_B
    call    FPM24               ; A = (A * EEPROM_M_ESR_1)

    movlw   low USR_1
    call    X_To_B
    goto    ESR_to_LCD

chk_10
    movlw   0x03
    subwf   U33_H,W             ;if ADC readings>=0x0300 (768) (если показания АЦП>=0x300 (768))
    btfsc   STATUS,C
    bsf     Flags,CHECK10OM     ;set flag more than 10 ohm (больше 10 Ом)

;channel 10 Ohm (канал 10 Ом)
    call    ClrA
    movf    U33_H,W             ;amplifier Ku=33, limit 10 Ohm (усилитель Ку=33, предел 10 Ом)
    movwf   AARGB0
    movf    U33_L,W
    movwf   AARGB1
    call    FLO1624             ;to 24 bit floating point
    movlw   low U0_ESR_10
    call    EEPROM_To_B
    call    FPS24               ;A = (A - EEPROM_U0_ESR_10) - subtract zero offset (вычитаем смещение нуля)
    movlw   low M_ESR_10
    call    EEPROM_To_B
    call    FPM24               ;A = (A * EEPROM_M_ESR_10)
    movlw   low USR_10
    call    X_To_B

ESR_to_LCD
    call    SecLine
    movlw   LOW _ESR
    call    Read_String

    btfss   Flags,CHECK10OM     ;if set flag >10 ohm? Skip if Set
    goto    next_3              ;if not set flag --> goto next_3 (Display " " space)

    movlw    ">"                ;if set flag --> Display ">" Greater-than sign
    call    CharLCD
    goto    next_4
next_3
    call    DispSP              ;display " " space

next_4
    movlw   0x80
    andwf   AARGB0,W            ;highlight the "-" sign (выделяем знак "-")
    btfsc   STATUS,Z
    goto    next_5              ;result > 0 (результат > 0)
    call    ClrA                ;result < 0 output only zeros (результат < 0, выводим одни нули)
    goto    next_6
next_5
    ;round up (округлить)

    movlw   0x7E                ;float 0.5 = "0x7E, 0x00, 0x00" in Microchip 24-bit format
    movwf   BEXP
    movlw   0x00
    movwf   BARGB0
    movlw   0x00
    movwf   BARGB1              ;B = 0.5
    bcf     FPFLAGS,RND
    call    FPA24               ;A = (A + 0.5) (Round)
                                ;Output 24 bit floating point sum in AEXP, AARGB0, AARGB1
    call    INT2424             ;Float to INT rounded to nearest whole number
                                ;Float в INT c округлением до ближайшего целого числа
                                ;Result in AARG (Результат в AARG)
                                ;Output: 24 bit 2's complement integer right justified in AARGB0, AARGB1, AARGB2
next_6
    bcf     Flags,DISCHARGE     ;turn off validation. digits when outputting (выключить проверку знач. разрядов при выводе)
    bsf     Flags,INSIGZERO     ;do not display leading zeros (не выводить лидирующие нули)
    clrf    AEXP
    call    BCD

    movlw   BCD2
    call    DispBCD

    movlw   BCD2
    call    DispBCD             ;display tens of ohms digit (десятки Ом)

    bcf     Flags,INSIGZERO     ;check for =0 is not needed, we output everything in a row (проверка на =0 не нужна, выводим все подряд)

    movlw   BCD1                ;display ohm units digit (единицы Ом)
    call    DispBCD

    call    DispDot             ;display "." decimal point.
    
    movlw   BCD1
    call    DispBCD

    movlw   BCD0
    call    DispBCD
    
    movlw   BCD0
    call    DispBCD

    call    DispSP              ;display " " space
    movlw   0x01                ;display "Ω" ohm sign (знак ом)
    call    CharLCD

end_disp
    bsf     PORTC,Cap_Discharge ;incl. rank Cx (вкл. разряд Сх)

    btfsc   PORTA,Kn_Plus
    call    DispUbat            ;battery icon is displayed (отображаем значёк заряда батареи)

    call    Delay_05_sec

    bcf     PORTC,Cap_Discharge ;off rank Cx (выкл. разряд Сх)

    goto    ESR_measure

;For testing - ADC output without processing (Для тестирования - вывод АЦП без обработки)
;2 channels at once (1 and 10 Ohm) (сразу 2-х каналов (1 и 10 Ом))
tst_ESR
    call    SecLine

  ;канал 1 Ом
    movlw   LOW _tst_1
    call    Read_String
    call    ClrA
    movf    U330_H,W            ;усилитель Ку=330, предел 1 Ом
    movwf   AARGB1
    movf    U330_L,W
    movwf   AARGB2
    call    BCD
    movlw   BCD1
    call    Disp_Full

  ;канал 10 Ом
    movlw   LOW _tst_10
    call    Read_String
    call    ClrA
    movf    U33_H,W             ;усилитель Ку=33, предел 10 Ом
    movwf   AARGB1
    movf    U33_L,W
    movwf   AARGB2
    call    BCD
    movlw   BCD1
    call    Disp_Full
    btfsc   PORTA, Kn_Set       ;проверка кнопки установки нуля
    goto    tst_Kn_Set_open

    btfsc   Flag_Key,STARTSETKEY
    goto    end_disp            ;ждем отпускания кнопки SET
  ;первоначальный момент нажатия кнопки SET
    bsf     Flag_Key,STARTSETKEY
    goto    tst_save
tst_Kn_Set_open
    bcf     Flag_Key,STARTSETKEY
    goto    end_disp
tst_save
  ;Сохранение U0 в EEPROM ------------------------
    call    CursorHome
    movlw   LOW _write_U0
    call    Read_String

  ;U0 для l Ом
    call    ClrA
    movf    U330_H,W            ;усилитель Ку=330, предел 1 Ом
    movwf   AARGB0
    movf    U330_L,W
    movwf   AARGB1
    call    FLO1624             ;to 24 bit floating point
    call    BEQUA
    movlw   LOW U0_ESR_1
    movwf   Const_ADR
    call    Save_Const

  ;U0 для l0 Ом
    call    ClrA
    movf    U33_H,W             ;усилитель Ку=33, предел 10 Ом
    movwf   AARGB0
    movf    U33_L,W
    movwf   AARGB1
    call    FLO1624             ;to 24 bit floating point
    call    BEQUA
    movlw   LOW U0_ESR_10
    movwf   Const_ADR
    call    Save_Const

    call    Delay_1_sec
    call    ClrDSP
    movlw   LOW _save_const     ;старое сообщение _ready
    call    Read_String
    call    Delay_1_sec
    goto    end_disp
    
;------------------------- Buffer Sorting Cx -------------------------
;сортировка пузырьком, один проход 
;Выход: медиана в TMR1_Count, TMR1H, TMR1L
Buf_Sorting_Cx    
    ;сравнить 1 и 2 число
    call    Buf_Cx_Comp_1_2
    btfsc   STATUS,Z
    goto    Buf_Sort_Median_2   ;1=2
    btfsc   STATUS,C
    goto    Buf_Sort_L1         ;1<2    
    ;1>2
    ;сравнить 1 и 3 число
    call    Buf_Cx_Comp_1_3
    btfss   STATUS,Z
    btfsc   STATUS,C
    goto    Buf_Sort_Median_1   ;1<3, 1=3
    ;1>3
    ;сравнить 2 и 3 число
    call    Buf_Cx_Comp_2_3
    btfss   STATUS,Z
    btfsc   STATUS,C
    goto    Buf_Sort_Median_3   ;2<3        
    goto    Buf_Sort_Median_2   ;2>3
Buf_Sort_L1    ;1<2
    ;сравнить 2 и 3 число
    call    Buf_Cx_Comp_2_3
    btfss   STATUS,Z
    btfsc   STATUS,C
    goto    Buf_Sort_Median_2   ;2<3, 2=3
    goto    Buf_Sort_Median_3   ;2>3
    
Buf_Sort_Median_1    
    ;1 - медиана
    movlw   Buf_Cx_1
    movwf   FSR
    goto    Buf_Sort_Copy
    
Buf_Sort_Median_2
    ;2 - медиана
    movlw   Buf_Cx_2
    movwf   FSR
    goto    Buf_Sort_Copy
    
Buf_Sort_Median_3
    ;3 - медиана
    movlw   Buf_Cx_3
    movwf   FSR
    goto    Buf_Sort_Copy
    
Buf_Sort_Copy    
    movf    INDF,w
    movwf   TMR1_Count
    incf    FSR,f
    movf    INDF,w
    movwf   TMR1H
    incf    FSR,f
    movf    INDF,w
    movwf   TMR1L    
    return
    
;-------------------------
Buf_Cx_Comp_1_2
    movlw   Buf_Cx_1
    movwf   FSR
    call    Buf_Cx_Temp
    movlw   Buf_Cx_2
    movwf   FSR
    goto    Buf_Cx_Compare
    
Buf_Cx_Comp_1_3
    movlw   Buf_Cx_1
    movwf   FSR
    call    Buf_Cx_Temp
    movlw   Buf_Cx_3
    movwf   FSR
    goto    Buf_Cx_Compare    
    
Buf_Cx_Comp_2_3
    movlw   Buf_Cx_2
    movwf   FSR
    call    Buf_Cx_Temp
    movlw   Buf_Cx_3
    movwf   FSR
    goto    Buf_Cx_Compare
    
;-------------------------
Buf_Cx_Temp    
    movf    INDF,w
    movwf   Temp+0
    incf    FSR,f    
    movf    INDF,w
    movwf   Temp+1
    incf    FSR,f    
    movf    INDF,w
    movwf   Temp+2
    return

;-------------------------
Buf_Cx_Compare
    ;сравнить старшие байты
    movf    Temp+0,w    
    subwf   INDF,w       
    btfss   STATUS,Z
    return       

    ;сравнить средние байты
    incf    FSR,f    
    movf    Temp+1,w    
    subwf   INDF,w        
    btfss   STATUS,Z
    return       

    ;сравнить младшие байты
    incf    FSR,f    
    movf    Temp+2,w    
    subwf   INDF,w 
    return
    
;------------------------- Clear Buffer Cx -------------------------
;очистить буфер Cx
Cx_clear
    movlw   Buf_Cx_1
    movwf   Index_Buf_Cx
    movwf   FSR
    movlw   BUF_Cx_COUNT_MAX*3
    movwf   Temp
Cx_clear_L1
    incf    FSR,f
    clrf    INDF
    decfsz  Temp,f
    goto    Cx_clear_L1
    return

;------------------------- Buffer Sorting ESR -------------------------
;сортировка пузырьком, один проход 
;отсортировать буфер (в его начале - новое измерение АЦП)
;Вход: W - начало буфера
Buf_Sorting
    movwf   FSR
    movlw   BUF_COUNT_MAX-1
    movwf   Temp
Buf_Sort_start
    ;сравнение двух чисел    
    movf    INDF,w              ;INDF(Prev_H)
    incf    FSR,f
    incf    FSR,f
    subwf   INDF,w              ;INDF(Next_H)
    btfss   STATUS,C
    goto    Buf_Sort_swap2
    btfss   STATUS,Z
    goto    Buf_Sort_Wait1    
    ;Prev_H = Next_H
    incf    FSR,f
    movf    INDF,w              ;INDF(Next_L)
    decf    FSR,f
    decf    FSR,f
    subwf   INDF,w              ;INDF(Prev_L)
    btfss   STATUS,C
    goto    Buf_Sort_Wait2
    decf    FSR,f    
Buf_Sort_swap1
    ;Prev_HL > Next_HL 
    ;числа расположены не правильно, обмен
    ;Prev_HL <--> Next_HL    
    movf    INDF,w              ;INDF(Prev_H)
    incf    FSR,f
    incf    FSR,f
    xorwf   INDF,w              ;INDF(Next_H)
    xorwf   INDF,f              ;INDF(Next_H)
    xorwf   INDF,w              ;INDF(Next_H)
    decf    FSR,f
    decf    FSR,f
    movwf   INDF                ;INDF(Prev_H)
    
    incf    FSR,f    
    movf    INDF,w              ;INDF(Prev_L)
    incf    FSR,f
    incf    FSR,f
    xorwf   INDF,w              ;INDF(Next_L)
    xorwf   INDF,f              ;INDF(Next_L)
    xorwf   INDF,w              ;INDF(Next_L)
    decf    FSR,f
    decf    FSR,f
    movwf   INDF                ;INDF(Prev_L)
    incf    FSR,f               ;подготовка к новому циклу сравнения        
    
    decfsz  Temp,f
    goto    Buf_Sort_start
    return

;-------------------------
Buf_Sort_swap2
    decf    FSR,f        
    decf    FSR,f        
    nop
    nop
    nop
    nop
    nop
    goto    Buf_Sort_swap1
    
;-------------------------
Buf_Sort_Wait1    ;при любом ветвлении время выполнения подпрограммы одинаково
    incf    FSR,f
    nop
    nop
    nop
    nop    
    nop
    nop
Buf_Sort_Wait2    
    decf    FSR,f
    movlw   0x03
    call    Delay_go
    nop        
Buf_Sort_Wait3    
    movlw   0x08
    call    Delay_go
    nop
    nop
    decfsz  Temp,f
    goto    Buf_Sort_Wait3    
    return
    
;------------------------- Copy ADC Buffer -------------------------
;Copy current ADC measurement to buffer (копировать текущее измерение АЦП в буфер)
Copy_ADC_Buf
    addwf   Buf_Count,w
    movwf   FSR
    movf    ADRESH,W
    movwf   INDF
    decf    FSR,f
    bank1
    movf    ADRESL,W
    bank0
    movwf   INDF
    return

;------------------------- ADC_U330 -------------------------
;We measure the voltage from the output of the differential amplifier with Ku=330
;Измеряем напряжение с выхода диф.усилителя с Ку=330
ADC_U330
    movlw   b'10000001'         ;Fosc/32, channel 0, ADC module incl (Fosc/32, канал 0, модуль АЦП вкл)
    movwf   ADCON0
    movlw   0x21                ;Delay 20 µs (Задержка 20 мкс)
    movwf   Dly0
    decfsz  Dly0,F
    goto    $-1
    bsf     ADCON0,GO           ;start analog to digital conversion (начать аналого-цифровое преобразование)
    btfsc   ADCON0,GO
    goto    $-1                 ;waiting for the end of the conversion (ждем окончания преобразования)
    bcf     ADCON0,ADON         ;turn off the ADC (выключить АЦП)
    return
;------------------------- ADC_U33 -------------------------
;We measure the voltage from the output of the differential amplifier with Ku=33
;Измеряем напряжение с выхода диф.усилителя с Ку=33
ADC_U33
    movlw   b'10001001'         ;Fosc/32, channel 1, ADC module incl (Fosc/32, канал 1, модуль АЦП вкл)
    movwf   ADCON0
    movlw   0x21                ;Delay 20 µs (Задержка 20 мкс)
    movwf   Dly0
    decfsz  Dly0,F
    goto    $-1
    bsf     ADCON0,GO           ;start analog to digital conversion (начать аналого-цифровое преобразование)
    btfsc   ADCON0,GO
    goto    $-1                 ;waiting for the end of the conversion (ждем окончания преобразования)
    bcf     ADCON0,ADON         ;turn off the ADC (выключить АЦП)
    return
;------------------------- TMR1 -------------------------
;TMR1 timer initialization, count step = 0.2 µs
;Инициализация таймера TMR1, шаг счета = 0.2 мкс
TMR1_init
  bank1
    bsf     PIE1, TMR1IE        ;enable interrupt from TMR1 overflow (разрешить прерывания от TMR1)
  bank0
    clrf    TMR1L
    clrf    TMR1H
    clrf    TMR1_Count
    bcf     PIR1, TMR1IF
    movlw   b'00000000'         ;1:1-Fosc/4, TMR1-off (1:1-Fosc/4, TMR1-выкл)
    movwf   T1CON
    bcf     INTCON,GIE
    bsf     INTCON,PEIE
    return

;------------------------- TMR0 -------------------------
;Timer initialization TMR0, count step = 0.2 µs
;Инициализация таймера TMR0, шаг счета = 0.2 мкс
TMR0_init
    movlw   Max_Count
    movwf   TMR0_Count          ;initial value of overflow counter TMR0 (начальное значение счетчика переполнений TMR0)
    clrf    TMR0                ;clear timer
    movlw   OPTION_REG          ;work around the OPTION
    movwf   FSR                 ;address OPTION_REG -> FSR
    movlw   b'00000111'         ;set up timer. 1:256 presc
    movwf   INDF

    clrf    TMR0
    bcf     INTCON,T0IF         ;clear tmr0 int flag
    bsf     INTCON,T0IE         ;enable TMR0 int
    bcf     INTCON,GIE          ;global interrupts
    return

;------------------------- DispUbat ---------------------------------------------;
;отображаем значёк на дисплее
DispUbat
    call    Ubat                ;измерение заряда батареи

    movlw   0x8F                ;позиция символа на дисплее - 1 строка 16 знакоместо
    call    CmdLCD
    movf    Bat_sign,w          ;текущий значёк заряда батареи
    call    CharLCD
    return

;------------------------- Ubat ---------------------------------------------;
;Измеряем напряжение батареи
;Bat_sign - сохраняем текущий значёк заряда батареи
Ubat
    bank1
    movlw   b'00000100'         ;левое выравнивание, Vdd, Vss, AN0, AN1, AN3
    movwf   ADCON1
    bank0

    movlw   b'10011001'         ;Fosc/32, канал AN3, модуль АЦП вкл.
    movwf   ADCON0
    movlw   0x42                ;Задержка 40 мкс
    movwf   Dly0
    decfsz  Dly0,F
    goto    $-1
    bsf     ADCON0,GO           ;начать аналого-цифровое преобразование
    btfsc   ADCON0,GO
    goto    $-1                 ;ждем окончания преобразования
    bcf     ADCON0,ADON         ;выключить АЦП
    bank1
    movlw   b'10000100'         ;правое выравнивание, Vdd, Vss, AN0, AN1, AN3
    movwf   ADCON1
    bank0

Ubat_Min
    movlw   .106                ;если значение АЦП выше .128, знак Bat max.
    subwf   ADRESH,W
    btfsc   STATUS,C
    goto    Ubat_3              ;Ubat >= 7v
    movlw   _BAT_MIN            ;Ubat < 7v
    movwf   Bat_sign
    return
Ubat_3
    movlw   .113
    subwf   ADRESH,W
    btfsc   STATUS,C
    goto    Ubat_2              ;Ubat >= 7.5v
    movlw   _BAT_3              ;Ubat < 7.5v
    movwf   Bat_sign
    return
Ubat_2
    movlw   .121
    subwf   ADRESH,W
    btfsc   STATUS,C
    goto    Ubat_1              ;Ubat >= 8v
    movlw   _BAT_2              ;Ubat < 8v
    movwf   Bat_sign
    return
Ubat_1
    movlw   .128
    subwf   ADRESH,W
    movlw   _BAT_1              ;Ubat < 8.5v
    btfsc   STATUS,C
    movlw   _BAT_MAX            ;Ubat >= 8.5v
    movwf   Bat_sign
    return

;------------------------- Delay -------------------------
;  Подпрограммы пауз
Delay_3_sec                     ;Пауза 3 сек
  Dly24     D'937499'           ; 3/(4/20000000)/16=937500-1=937499
    goto    DoDly24

Delay_2_sec                     ;Пауза 2 сек
  Dly24     D'624999'           ; 2/(4/20000000)/16=625000-1=624999
    goto    DoDly24

Delay_1_sec                     ;Пауза 1 сек
  Dly24     D'312499'           ; 1/(4/20000000)/16=312500-1=312499
    goto    DoDly24

Delay_05_sec                    ;Пауза 0.5 сек
  Dly24     D'156249'           ; 0.5/(4/20000000)/16=156250-1=156249
    goto    DoDly24

Delay_01_sec                    ;Пауза 0.1 сек
  Dly24     D'31249'            ; 0.1/(4/20000000)/16=31250-1=31249
    goto    DoDly24

Delay_5_ms                      ;Пауза 5 мс
  Dly24     D'1562'             ; 0.005/(4/20000000)/16=1562.5=1562
    goto    DoDly24

Delay_200_us                    ;Пауза 200 мкс
  Dly24     D'62'               ; 0.0002/(4/20000000)/16=62.5=62
    goto    DoDly24

DoDly24                         ;16 Tcy per loop
    movlw   H'FF'               ;Start with -1 in W
    addwf   Dly0,F              ;LSB decrement
    btfsc   STATUS,C            ;was the carry flag set?
    clrw                        ;If so, 0 is put in W
    addwf   Dly1,F              ;Else, we continue.
    btfsc   STATUS,C
    clrw                        ;0 in W
    addwf   Dly2,F
    btfsc   STATUS,C
    clrw                        ;0 in W
    iorwf   Dly0,W              ;Inclusive-OR all variables
    iorwf   Dly1,W              ;together to see if we have reached
    iorwf   Dly2,W              ;0 on all of them.
    btfss   STATUS,Z            ;Test if result of Inclusive-OR's is 0
    goto    DoDly24
    return

Delay_20_us
    movlw   0x1F                ;Задержка 20 мкс
Delay_go
    movwf   Dly0
    decfsz  Dly0,F
    goto    $-1
    nop
    nop
    return

;---------------------- LCD ---------------------
;   Перевод указателя  на второй символ второй строки
SecLine
    movlw   0xC0

;  Загрузка команды
CmdLCD
    movwf   Temp4
;  bcf    _RS
    swapf   Temp4, W
    andlw   0x0F
    movwf   PORTB
    bsf     PORTB,LCD_E
    nop
    nop
    nop
    bcf     PORTB,LCD_E
    movf    Temp4, W
    andlw   0x0F
    movwf   PORTB
    bsf     PORTB,LCD_E
    nop
    nop
    nop
    bcf     PORTB,LCD_E
;  clrf     PORTB
    call    Delay_200_us
    return


;  Перекодировка в ASCII и вывод
NumLCD
    andlw   0x0F                ;маска
    iorlw   0x30                ;ASCII
;  Вывод ASCII символа
CharLCD
    movwf   Temp4

SendLCD
    swapf   Temp4, W
    andlw   0x0F
    iorlw   b'00010000'         ;RS=1
    movwf   PORTB
    bsf     PORTB,LCD_E
    nop
    nop
    nop
    bcf     PORTB,LCD_E
    movf    Temp4, W
    andlw   0x0F
    iorlw   b'00010000'         ;RS=1
    movwf   PORTB

Send    
    bsf     PORTB,LCD_E
    nop
    nop
    nop
    bcf     PORTB,LCD_E
    clrf    PORTB
    call    Delay_200_us
    return

CursorHome
    movlw   0x02                ;Дисплей в исходное состояние
    goto    LongSend

ClrDSP
    movlw   1                   ;Очистка дисплея

LongSend
    call    CmdLCD
    goto    Delay_5_ms

DispDot
    movlw   "."
    goto    CharLCD

Disp0
    movlw   "0"
    goto    CharLCD

DispSP
    movlw   " "
    goto    CharLCD

;-----------------------------------------------------------
;Чтение строки из таблицы и вывод на LCD
Read_String
    movwf   Count1
    decf    Count1,F            ;коррекция начального смещения
    movlw   HIGH Table
    movwf   PCLATH

get_next_s
    movf    Count1,W
    call    Table
    andlw   0xFF                ;проверка на конец строки
    btfsc   STATUS, Z
    return
    call    CharLCD
    incf    Count1,F
    goto    get_next_s

;---------------------- Load CGRAM LCD ---------------------
;загрузить символы в знакогенератор
Load_ZG
    movlw   b'01001000'         ;AC in CGRAM=8
    call    CmdLCD
    movlw   HIGH Table
    movwf   PCLATH
    movlw   .7 *.8              ;7 знаков по 8 байт
    movwf   Count1
    movlw   LOW  (omega-1)      ;@latchdevel fix
    movwf   Count2              ;смещение в таблице

get_s
    call    Table               ;получить символ из таблицы
    call    CharLCD
    incf    Count2,F
    movf    Count2,W
    decfsz  Count1,F
    goto    get_s
    return

;----------------------------------------------------------
;вывод из переданного в W адреса блока BCD0...4
;на индикатор
Disp_Full
    movwf   FSR                 ;адрес ячейки для вывода на LCD

next_byte
    swapf   INDF,W
    call    NumLCD
    movf    INDF,W
    call    NumLCD
  ;проверим, добрались ли мы до BCD0
    movlw   BCD0
    subwf   FSR,W
    btfsc   STATUS,Z
    return
    decf    FSR,F
    goto    next_byte

;---------------------- BCD to LCD ---------------------
;Вывод разряда и подготовка к выводу следующего
DispBCD
    movwf   FSR
NextNibble
    swapf   INDF,F
    movf    INDF,W
    btfss   Flags,INSIGZERO     ;1 - не выводить лидирующие нули
    goto    chk_NZ
    andlw   0x0F
    btfsc   STATUS,Z
    return                      ;пропуск вывода
    bcf     Flags,INSIGZERO     ;эту и все посдедующие цифры выводим

chk_NZ
    btfss   Flags,DISCHARGE     ;1- выводить только NZ разрядов, остальные - 0
    goto    NumLCD
    movf    NZ,F
    btfsc   STATUS,Z            ;счетчик=0?
    goto    Disp0               ;да, выводим 0
    decf    NZ,F                ;нет, выводим то что есть
    call    NumLCD
    return

;---------------------- BCD ---------------------
;Перекодировка значения из двоичного в десятичный формат
BCD
    movlw   0x20
    movwf   T1
    clrf    BCD0
    clrf    BCD1
    clrf    BCD2
    clrf    BCD3
    clrf    BCD4

BcdLoop 
    rlf    AARGB2, F
    rlf    AARGB1, F
    rlf    AARGB0, F
    rlf    AEXP, F

    rlf    BCD0, F
    rlf    BCD1, F
    rlf    BCD2, F
    rlf    BCD3, F
    rlf    BCD4, F
    decfsz T1, F
    goto   Adjust
    return

Adjust
    movlw   .5
    movwf   Count2

    movlw   BCD0
    movwf   FSR
    goto    ADloop+1

ADloop    
    incf    FSR, F
    call    Adjbcd
    decfsz  Count2, F
    goto    ADloop
    goto    BcdLoop

Adjbcd
    movlw   0x03
    addwf   INDF, W
    movwf   T0
    btfsc   T0, 3
    movwf   INDF
    movlw   0x30
    addwf   INDF, W
    movwf   T0
    btfsc   T0, 7
    movwf   INDF
    return

;-------------------------------------------------------
;  Копирование "по назначению" блока (4 байта) данных
; Temp1 = адрес получателя - указывается старший адрес блока
; Temp2 = адрес источника - указывается старший адрес блока

;CEQUA    movlw  CX             ;C=A
Copy_From_A
    movwf   Temp1               ;Xw=A
    movlw   AEXP
    movwf   Temp2
    goto    Copy

BEQUA
    movlw   AEXP                ;B=A

Copy_To_B
    movwf   Temp2               ;B=Xw
    movlw   BEXP
    goto    Copy_B

;AEQUF    movlw  FX             ;A=F
Copy_To_A
    movwf   Temp2               ;A=Xw
    movlw   AEXP

Copy_B
    movwf   Temp1

Copy
    movlw   4                   ;Объём блока
    movwf   Count1

Copy_Loop
    movf    Temp2, W
    movwf   FSR
    movf    INDF, W
    movwf   Temp3
    movf    Temp1, W
    movwf   FSR
    movf    Temp3, W
    movwf   INDF
    decf    Temp1, F            ;двигаемся в сторону уменьшения
    decf    Temp2, F            ;адресов
    decfsz  Count1, F
    goto    Copy_Loop
    return

;-------------------------------------------------------
X_To_B
    call    EEPROM_To_B         ;Loading the X factor (Загрузка коэффициента X)
    call    ASwapB
    call    FLO2424
    call    FPM24
    return

ASwapB
    movlw   T5
    call    Copy_From_A
    movlw   BEXP
    call    Copy_To_A
    movlw   T5
    call    Copy_To_B
    return
;-------------------------------------------------------
;  Cleaning blocks A and B (Очистка блоков А и В)
ClrB
    movlw   BEXP                ;Block B cleaning (Очистка блока В)
    goto    ClrA+1

ClrA
    movlw   AEXP                ;Block A cleaning (Очистка блока А)
    movwf   FSR
    movlw   4                   ;Block volume (Объем блока)
    movwf   Count1

ClrLoop
    clrf    INDF                ;Cleaning cycle (Цикл очистки)
    decf    FSR, F              ;Reduce the address (уменьшаем адрес)
    decfsz  Count1, F
    goto    ClrLoop
    return
;-------------------------------------------------------
;  Read data from EEPROM to block A (Чтение данных из EEPROM в блок A)
EEPROM_To_A
    movwf   EE_ADR              ;We save the address of the EEPROM cell (Сохраняем адрес ячейки EEPROM)
    movlw   AEXP
    goto    EEPROM_To_L1
;  Read data from EEPROM to block B (Чтение данных из EEPROM в блок B)
EEPROM_To_B
    movwf   EE_ADR              ;We save the address of the EEPROM cell (Сохраняем адрес ячейки EEPROM)
    movlw   BEXP
EEPROM_To_L1
    movwf   FSR
    movlw   4                   ;Block volume (Объем блока)
    movwf   Count1
EE_read_loop
    call    ReadEEPROM
    banksel BEXP
    movwf   INDF
    incf    EE_ADR, F
    decf    FSR, F
    decfsz  Count1, F
    goto    EE_read_loop
    return

;  Read EEPROM (Чтение EEPROM)
ReadEEPROM
    movf    EE_ADR,W
    banksel EEADR               ;bank 2 (банк 2)
    movwf   EEADR               ;адрес ячейки EEPROM
    banksel EECON1              ;bank 3 (банк 3)
    bcf     EECON1,EEPGD        ;select EEPROM (выбрать EEPROM)
    bsf     EECON1,RD           ;initialize reading (инициализровать чтение)
    banksel EEDATA              ;bank 2 (банк 2)
    movf    EEDATA,W            ;W = EEDATA
    return

;-------------------------------------------------------
;  Запись блока BARG в EEPROM
; Адрес в EEPROM задается в Const_ADR
Save_Const
    movf    Const_ADR,W
    movwf   EE_ADR
    movlw   BEXP
    movwf   FSR
    movlw   4                   ;Объем блока
    movwf   Count1
EE_write_loop
    movf    INDF,W
    movwf   EE_DATA
    call    WriteEEPROM
    banksel BEXP
    incf    EE_ADR, F
    decf    FSR, F
    decfsz  Count1, F
    goto    EE_write_loop
    return

;  Запись EEPROM
WriteEEPROM
    banksel EECON1              ;банк3
    btfsc   EECON1,WR
    goto    $-1
    banksel EE_ADR
    movf    EE_ADR,W
    banksel EEADR               ;банк2
    movwf   EEADR
    banksel EE_DATA
    movf    EE_DATA,W
    banksel EEDATA              ;банк2
    movwf   EEDATA
    banksel EECON1              ;банк3
    bcf     EECON1,EEPGD
    bsf     EECON1,WREN
    movlw   0x55
    movwf   EECON2
    movlw   0xAA
    movwf   EECON2
    bsf     EECON1,WR
    nop
    bcf     EECON1,WREN
    return
;-------------------------------------------------------
;  Инкрементирование полублока B
IncB
    bsf     Flags,SAVECONST     ;устанавливаем флаг изменения константы
    incf    BARGB2, F
    btfsc   STATUS, Z
    incf    BARGB1, F
    goto    ShowX

;  Декрементирование полублока B
DecB
    bsf    Flags,SAVECONST      ;устанавливаем флаг изменения константы
    movf    BARGB2, F
    btfsc   STATUS, Z
    decf    BARGB1, F
    decf    BARGB2, F

ShowX
    movlw   BEXP
    call    Copy_To_A

    call    BCD
    call    SecLine
    movlw   BCD1
    call    DispBCD
    call    DispDot
    movlw   BCD1
    call    DispBCD
    movlw   BCD0
    call    DispBCD
    movlw   BCD0
    call    DispBCD

    movf    Key_Press_Time,f    ;проверить время нажатой кнопки
    btfss   STATUS,Z
    goto    ShowX_L1
    call    Delay_01_sec        ;быстрый режим счёта
    return
ShowX_L1
    decf    Key_Press_Time,f
    call    Delay_05_sec
    return

;=======================================================
;  PIC16 24 BIT FLOATING POINT LIBRARY

    #define P16_MAP1 0
    #define P16_MAP2 1          ; Use "math16.inc" memory map 1, from 0x20 to 0x34 for FLOATING POINT LIBRARY
    include "math16.inc"        ; https://raw.githubusercontent.com/latchdevel/AN575/master/ASM/MATH16.INC
    include "fp24.a16"          ; https://raw.githubusercontent.com/latchdevel/AN575/master/ASM/FP24.A16

    END
