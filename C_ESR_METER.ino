/*
  C/ESR Meter

  Reimplementation of the Russian capacitance and ESR meter for electrolytic capacitors, 
  posted on "Pro-Radio" forum in 2006 by Gints Oleg (Гинц Олег) "GO".
  
  See https://github.com/latchdevel/C_ESR_METER

  Copyright (c) 2023-2024 Jorge Rivera. All right reserved.
  License GNU General Public License v3.0.
*/

#define MESSAGE "C/ESR Meter" // 11 chars max
#define VERSION "1.0"         //  3 chars max

#if !defined(__AVR_ATmega328P__)
  #error "Required any Arduino using Atmel ATMega328p MCU"
#endif

#if F_CPU != 16000000L
  #error "Required 16Mhz clock"
#endif

#include <EEPROM.h>             // Arduino EEPROM library included (v2.0)
                                // https://docs.arduino.cc/learn/built-in-libraries/eeprom

#include <Wire.h>               // Arduino Wire (I2C) library included (v1.0)
                                // https://www.arduino.cc/reference/en/language/functions/communication/wire/

#include <LiquidCrystal_I2C.h>  // LiquidCrystal Arduino library for I2C PCF8574 based LCD displays (v1.1.2)
                                // https://github.com/johnrickman/LiquidCrystal_I2C/tree/1.1.2

// Instance an I2C LCD display (16 columns x 2 rows) at PCF8574 address 0x27
LiquidCrystal_I2C lcd(0x27, 16, 2);

// --------------------- Hardware configuration ---------------------

// Define buzzer and auto-off settings
#define BUZZER           16               // Arduino pin for active buzzer output: 16 / A2 (PortC, bit 2)
#define BEEP_TIME        50               // Default beep duration in milliseconds
#define WARNING_OFF     120               // Seconds to auto off warning beep (approximately because Timer0/millis() stops during measurements)
#define AUTO_OFF        180               // Seconds to auto off (approximately because Timer0/millis() stops during measurements)
#define MILLIS_S       1000UL             // Millis per second to fix Timer0/millis() stops during measurements

// Define ADC settings
#define ADC_U330U33       0               // ADC channel for measure U330 and U33 (not Arduino pin)
#define ADC_VBATT         1               // ADC channel for measure battery voltage (not Arduino pin)
#define ADC_VREF_TYPE     0               // Set to REFS0 (1 for internal Vcc or 0 for external VREF like 4.096v or similar)
#define ADC_VREF_VALUE    4.070           // Voltage of external VREF in volts, should be measured as accurately as possible.
#define ADC_CLOCK       0b110             // ADC prescaler (ADCSRA) to 64 (110) for 250Khz (@16Mhz)

// Define battery settings
#define VBATT_FACTOR      3.74            // Battery sense voltage divisor factor = 1 + ( R5 / R6 )
#define VBATT_MIN         6.0             // Minimum voltage for normal boot, or stop booting due to "low power"
#if ADC_VREF_TYPE == 1                    // Internal Vcc as VREF
  #define ADC_VREF_VALUE  5.0             // Assume 5.0v
#endif 
#define VBATT_MAX         VBATT_FACTOR*ADC_VREF_VALUE  // Max voltage that can be measured

// --------------------- Hardware based parameters ---------------------

// Factor for ESR range 1 Ohm using "U330 / M_ESR_1"
#define M_ESR_1          599.0                        // (float) ADC value (0 to 1023) using 1 ohm range (U330) minus "Set to Zero" user calibration for a 1 ohm reference resistor

// Factor for ESR range 10 Ohm using "U33 / M_ESR_10"
#define M_ESR_10          79.0                        // (float) ADC value (0 to 1023) using 10 ohms range (U33) by 10 for a 10 ohms reference resistor

// ESR range selector based on U330average threshold value
#define U330threshold     950U                        // (unsigned short integer) ADC value (0 to 1023) using 1 ohm range (U330), threshold to switch to use 10 ohms range (U33)

// Factor for calculate Cx using "Cx = ticks_counter / M_Cx"
#define M_Cx              51.0                       // (float) Number of Timer1 ticks per microfarad

// Internal correction for Cx Timer1 ticks counter
#define add_Cx            1000U                       // (unsigned short integer) Ticks = counter + ( USR_1_Cx - add_Cx ) // Default 1000 (no correction).

// ESR threshold to apply ESR compensation to Cx measure
#define ESRthreshold      2.5                         // (float) ESR value above which ESR compensation is applied to Cx measure

// U33 Comp timeout from timer1count
#define COMP_TIMEOUT      80U                         // (unsigned short integer) Number of Timer1 overflows. (80+1) * 65535 ticks per overflow = 5308335 ticks / M_Cx (ticks per microfarad) = 110360 uF max measure.
                                                      // Timer1 overflow every 4.0959375 msecs. (80+1) * 4.0959375 = 327ms. Increasing this parameter, the Cx max measure will be higher, but it will also be slower.
// Number of ACD measures
#define ACD_MEASURES      20U                         // (unsigned short integer) Number of ADC readings to average in each ESR calculation.

// CX IIR digital filter (Infinite Impulse Response)  // Exponential Moving Average (EMA meaning)
#define ALPHA_Cx          0.5                         // (float) Initial smoothing factor from 0 (full filter) to 1 (no filter)

// Cx IIR digital filter auto hold 
#define Cx_MEASURES       10U                         // (unsigned short integer) Number of Cx IIR digital filter measures until "auto-hold" (0 for no auto-hold)

// ESR limit
#define ESRlimit          1022.9/M_ESR_10             // (float) Max measurable ESR when ADC reading is close to 1023 using 10 ohms range (U33)

// --------------------- I/O port config ---------------------

// Set Port B configuration
#define Port_B_Config      0b00111111  // Manage outputs to Cx and gain selector
// Port B bit equates          ||||||
#define Cap_Charge      0 //   |||||·- PB0     Cap_Charge      Output      Original PIC RC0 - Cap charge when LOW "C" (via Q1 BJT PNP, 10mA limited by Z1 TL431 & R3 180R)
#define Cap_Discharge   1 //   ||||·-- PB1     Cap_Discharge   Output      Original PIC RC1 - Cap discharge when HIGH "D" (via Q2 N-Channel MOSFET IRF530N)
#define ADC_Gain_U330   2 //   |||·--- PB2     ADC_Gain_U330   Output      Select ADC gain "G" (0 (default) for U33, 1 for U330, via AD620 Rg) to CD4066B CMOS quad analog switch
#define In_N_Gnd        3 //   ||·---- PB3     In_N_Gnd        Output      Original PIC RC3 - GND "R" (remote control) to CD4066B CMOS quad analog switch
#define In_P_Cx         4 //   |·----- PB4     In_P_Cx         Output      Original PIC RC4 - CX  "+"                  to CD4066B CMOS quad analog switch
#define In_N_Cx         5 //   ·------ PB5     In_N_Cx         Output      Original PIC RC5 - CX  "-"                  to CD4066B CMOS quad analog switch (Arduino pin D13 builtin LED)

// Define Port B states        -+RGDC
#define ESR_ready          0b00110011   // Discharge, "+" and "-" Remote control on Cx
#define ESR_start          0b00110100   // Charge,    "+" and "-" Remote control on Cx, ADC gain "G" to U330
#define Cap_ready          0b00011011   // Discharge, "-" Remote control to ground, "+" to Cx
#define Cap_start          0b00011000   // Charge,    "-" Remote control to ground, "+" to Cx
#define Cap_start2         0b00110000   // Charge,    "-" Remote control on Cx,     "+" on Cx

// Set Port D configuration
#define Port_D_Config      0b10000000  // Manage inputs from LM393 comparator and user buttons
// Port D bit equates        ||||||||
//                      0    |||||||·- PD0        UART RX
//                      1    ||||||·-- PD1        UART TX
#define Comp_Up         2 // |||||·--- PD2/INT0   Comp_Up           Input       LOW when ADC (gain U33) > 2.0 v
#define Comp_Low        3 // ||||·---- PD3/INT1   Comp_Low          Input       LOW when ADC (gain U33) > 1.0 v
#define Menu_Button     4 // |||·----- PD4        Menu_Button       Input       "On/Off/Menu/Set" button pressed when LOW
#define Plus_Button     5 // ||·------ PD5        Plus_Button       Input       "(+) Plus" button pressed when LOW
#define Minus_Button    6 // |·------- RD6        Minus_Button      Input       "(-) Minus" button pressed when LOW
#define Power_Off       7 // ·-------- PD7        Power_Off         Output      Set to 1 for battery power or 0 for (auto) power off

// Inputs from external LM393 comparator
#define Comp_Up_HIGH    bit_is_set(PIND, Comp_Up)         // True while ADC (gain U33) < 2.0 v
#define Comp_Low_HIGH   bit_is_set(PIND, Comp_Low)        // True while ADC (gain U33) < 1.0 v

// Define input buttons
#define BUTTON_MENU     bit_is_clear(PIND, Menu_Button)   // True while button (MENU) is pressed
#define BUTTON_PLUS     bit_is_clear(PIND, Plus_Button)   // True while button (PLUS) is pressed
#define BUTTON_MINUS    bit_is_clear(PIND, Minus_Button)  // True while button (MINUS) is pressed

// Define Power ON/OFF
#define Set_Power_On    bitSet(PORTD, Power_Off)          // Set "Power On" status, keeping to HIGH the Power_Off output
#define Set_Power_Off   bitClear(PORTD, Power_Off)        // Set "Power Off" status, turn off battery power

// --------------------- LCD SYMBOLS ---------------------

#define SKIP  (byte)0                     // LCD custom char to skip address 0x00
#define OMEGA (byte)1                     // LCD custom char for Omega "Ω" character for Ohms
#define MU    (byte)2                     // LCD custom char for Mu "µ" character for prefix micro
#define BELL  (byte)3                     // LCD custom char for Bell character
#define LOCK  (byte)4                     // LCD custom char for Lock character

// LCD custom char at address 0x00, defined only to skip '\0'
byte skip[8] = {0};

// Omega "Ω" character for Ohms, better than LCD CGROM 0xF4 character
byte omega[8] = {
  0b00000000,0b00001110,0b00010001,0b00010001,0b00010001,0b00001010,0b00011011,0b00000000
};

// Mu "µ" character for prefix micro, better than LCD CGROM 0xE4 character
byte mu[8] = {
  0b00000000,0b00000000,0b00010010,0b00010010,0b00010010,0b00011110,0b00010001,0b00010000
};

// Bell character
byte bell[8] = {
  0b00000100,0b00001110,0b00001110,0b00001110,0b00011111,0b00000000,0b00000100,0b00000000
};

// Lock character
byte lock[8] = {
  0b00001110,0b00010001,0b00010001,0b00011111,0b00011011,0b00011011,0b00011111,0b00000000
};

// --------------------- EEPROM OFFSETS ---------------------

#define U0_ESR_1_EEPROM_OFFSET            0x00
#define U0_ESR_10_EEPROM_OFFSET           0x04
#define USR_1_EEPROM_OFFSET               0x08
#define USR_10_EEPROM_OFFSET              0x0C
#define USR_Cx_EEPROM_OFFSET              0x10
#define USR_1_Cx_EEPROM_OFFSET            0x14
#define ESR_METER_FLAG_EEPROM_OFFSET      0x18
#define ESR_METER_FLAG              "ESRMETER"

// Timeouts values
#define NO_TIMEOUT  0  // No timeout
#define TIMEOUT_CX0 1  // Cx_0 Wait until Cx is discharged
#define TIMEOUT_CX2 2  // Cx_2 Wait until U33 > 1.0v (Comp_Low)
#define TIMEOUT_CX3 3  // Cx_3 Wait until U33 > 2.0v (Comp_Up)
#define TIMEOUT_CX4 4  // User configuration for USR_1_Cx too low

// --------------------- Global vars ---------------------

uint8_t volatile timer1count_Cx2;         // Timer1 Cx2 overflow counter, volatile mandatory
uint8_t volatile timer1count_Cx3;         // Timer1 Cx3 overflow counter, volatile mandatory

uint16_t U330;                            // Raw ACD value for U330  (range 1 Ohm)
uint16_t U33;                             // Raw ACD value for U33  (range 10 Ohm)

float U330average         = 0;            // Average of ACD values for U330 (range 1 Ohm)
float U33average          = 0;            // Average of ACD values for U33 (range 10 Ohm)
uint32_t CxTicks;                         // Cx Timer1 total ticks (if not timeout)

uint32_t WarningOffTimer  = 0;            // Millis to auto-off warning beep (0 to disable)
uint32_t AutoOffTimer     = 0;            // Millis to auto-off (0 to disable)

bool ESR_RAW_VALUES       = false;        // Flag to clear raw values from second line

float CxAlpha             = ALPHA_Cx;     // Cx IIR digital filter's exponential smoothing factor
float CxFiltered          = 0;            // Filtered output value of Cx

// --------------------- EEPROM stored user calibration parameters ---------------------

// User correction for "Set to Zero" ESR range 1 Ohm using "ESR = (U330 - U0_ESR_1) / M_ESR_1"
uint16_t U0_ESR_1         = 0;            // Default 0 (no correction)

// User correction for "Set to Zero" ESR range 10 Ohms using "ESR = (U33 - U0_ESR_10) / M_ESR_10"
uint16_t U0_ESR_10        = 0;            // Default 0 (no correction)

// User correction factor for ESR range 1 Ohm using "ESR = ESR * USR_1"
float USR_1               = 1.000;        // Default 1.000 (no correction)

// User correction factor for ESR range 10 Ohm using "ESR = ESR * USR_10"
float USR_10              = 1.000;        // Default 1.000 (no correction)

// User correction factor for Cx "Cx = Cx * USR_Cx"
float USR_Cx              = 1.000;        // Default 1.000 (no correction)

// User correction for absolute value of Cx Timer1 ticks count using "counter + ( USR_1_Cx - add_Cx )"
uint16_t USR_1_Cx         = 1000;         // Default 1000 - add_Cx (1000) = 0 (no correction)

// --------------------- Prototypes ---------------------

struct false_type { static constexpr bool value = false; };
struct true_type  { static constexpr bool value = true;  };

template<class T> struct is_float         : false_type  {};
template<>        struct is_float<float>  : true_type   {};
template<>        struct is_float<float&> : true_type   {};

void beep(uint16_t duration = BEEP_TIME, byte pin = BUZZER);
float adc_vbatt(byte channel = ADC_VBATT);

void adc_meter(byte channel = ADC_U330U33);
float getESR(uint16_t U330range = U330threshold);

uint8_t cx_meter(float esr = 0);
float getCx(float esr = 0);

// --------------------- Meter Functions ---------------------

// Read ADC channel to measure battery voltage
// Returns the battery voltage in float format
float adc_vbatt(byte channel) {

  float ADCaverage;

  uint16_t ADCsum = 0;

  noInterrupts();
    // Select ADC channel
    ADMUX = ADMUX & 0xF0;  // Clear MUX3-MUX0
    ADMUX |= channel;      // Select ADC channel for Vbatt
  interrupts();

  // Delay for ADC MUX change
  delayMicroseconds(250);

  // Discard first conversion
  bitSet(ADCSRA, ADSC);               // Begin ADC conversion
  while (bit_is_set(ADCSRA, ADSC));   // Wait until ADC conversion finish

  // Read ADC ACD_MEASURES times and average them
  for (uint8_t i = ACD_MEASURES; i != 0; i--) {
    noInterrupts();
      // Read ADC
      bitSet(ADCSRA, ADSC);               // Begin ADC conversion
      while (bit_is_set(ADCSRA, ADSC));   // Wait until ADC conversion finish
      ADCsum = ADCsum + ADCW;
    interrupts();
  }

  // Calculate ADC average
  ADCaverage = float(ADCsum / float(ACD_MEASURES));

  // Return calculated battery voltage
  return float(((ADCaverage / 1024.0) * ADC_VREF_VALUE) * VBATT_FACTOR);

}

// Read ADC for U330 and U33 and average them to global vars:
// U330, U33, U330average and U33average
void adc_meter(byte channel) {

  uint16_t U330sum = 0;
  uint16_t U33sum = 0;

  noInterrupts();
    // Select ADC channel for U330U33 as input to ADC
    ADMUX = ADMUX & 0xF0;  // Clear MUX3-MUX0
    ADMUX |= channel;      // Select ADC channel for U330/U33
  interrupts();

  // Delay for ADC MUX change
  delayMicroseconds(250);

  // Read ADC ACD_MEASURES times and average them
  for (uint8_t i = ACD_MEASURES; i != 0; i--) {
    
    noInterrupts();
      // Select ADC gain to U330 (1 Ohm range)
      bitSet(PORTB, ADC_Gain_U330);

      // Delay for CD4066B switch
      __builtin_avr_delay_cycles(4);

      // ESR_measure
      PORTB = ESR_start;                  // incl. charge, "+" and "-" remote control on Cx, ADC gain "G" to U330 (1 Ohm range)

      // Delay 3.6us (18 cycles PIC@20Mhz) for the end of the transition processes - PICK UP!!!
      //__builtin_avr_delay_cycles(58);   //  58 cycles AVR@16Mhz = 58 * 62.5ns = 3.625us
      __builtin_avr_delay_cycles(160);    // 160 cycles = 10uS (10mA R3=180R)  

      bitClear(PORTB, In_P_Cx);           // bcf PORTC, In_P_Cx (turn off C1 from Cx)

      __builtin_avr_delay_cycles(3);      // expected delay 200ns  // On a 16MHz ATmega328P, system cycle is 62.5 nanoseconds.

      bitSet(PORTB, Cap_Charge);          // bsf PORTC, Cap_Charge   (off Isar)

      // Discard first conversion
      bitSet(ADCSRA, ADSC);               // Begin ADC conversion
      while (bit_is_set(ADCSRA, ADSC));   // Wait until ADC conversion finish

      // ADC read U330 (1 Ohm range)
      bitSet(ADCSRA, ADSC);               // Begin ADC conversion
      while (bit_is_set(ADCSRA, ADSC));   // Wait until ADC conversion finish

      // Save ADC word takes care of how to read ADCL and ADCH.
      U330 = ADCW;

      // Select ADC gain to U33 (10 Ohms range)
      bitClear(PORTB, ADC_Gain_U330);

      // Delay for CD4066B switch
      __builtin_avr_delay_cycles(4);

      // Discard first conversion
      bitSet(ADCSRA, ADSC);               // Begin ADC conversion
      while (bit_is_set(ADCSRA, ADSC));   // Wait until ADC conversion finish

      // ADC read U33 (10 Ohms range)
      bitSet(ADCSRA, ADSC);               // Begin ADC conversion
      while (bit_is_set(ADCSRA, ADSC));   // Wait until ADC conversion finish

      // Save ADC word takes care of how to read ADCL and ADCH.
      U33 = ADCW;

      // ADC_End
      PORTB = Cap_ready;  // Cx discharge, "-" remote control to ground, "+" to Cx
    interrupts();

    U330sum = U330sum + U330;
    U33sum = U33sum + U33;

    delay(1); // Required delay to ensure discharge of C1 and C2

  }
  
  // Calculate averages
  U330average = float(U330sum / float(ACD_MEASURES));
  U33average = float(U33sum / float(ACD_MEASURES));

  // Save averages to uint16_t truncated values
  U330 = round(U330average);
  U33 = round(U33average);

}

// Get ESR measure from global vars "U330average" or "U33average" depends on range
// Use of internal hardware-based factor and user calibration correction factors
// Parameter U330range to select 1 Ohm range (U330) or 10 Ohms range (U33)
// Returns ESR value in Ohms (Ω) in float format
// A negative ESR value indicates a "Set to Zero" compensation overload
float getESR(uint16_t U330range) {

  float ESR = 0.0;

  // Read ADC to U330average and U33average
  adc_meter();

  // Select ESR range
  if (U330average < U330range) {

    // ESR range 1 Ohm using U330 average value
    ESR = (U330average - U0_ESR_1) / M_ESR_1;
    
    // Apply user correction factor for ESR range 1 Ohm
    ESR = ESR * USR_1;

  } else {

    // ESR range 10 Ohms using U33 average value
    ESR = (U33average - U0_ESR_10) / M_ESR_10;

    // Apply user correction factor for ESR range 10 Ohms
    ESR = ESR * USR_10;

  }

  return ESR;

}

// Timer1 overflow Interrupt Service Routine (ISR)
// Called whenever TCNT1 (16 bits register) overflows
// Depends on system clock and prescaler settings
// Overflow interrupt every 4095.9375us (4.0959375ms)
ISR(TIMER1_OVF_vect) {
  if (Comp_Low_HIGH) {  // Waiting for Cx2
    timer1count_Cx2++;
    if (timer1count_Cx2 == COMP_TIMEOUT) {
      TCCR1B = 0;  // Stop Timer1
    }
  } else {  //Waiting for Cx3
    timer1count_Cx3++;
    if (timer1count_Cx3 == COMP_TIMEOUT) {
      TCCR1B = 0;  // Stop Timer1
    }
  }
}

// Cx measure
// Receives ESR measure to check if it applies ESR compensation to Cx measure
// Results to global var "timer1count" and "TCNT1" register
// Return 0 if ok, or greater than 0 on any timeout
uint8_t cx_meter(float esr) {

  // Cx_init
  uint32_t initial = millis();
  uint32_t timeout = initial + 1000;  // One second for Cx_0 discharge timeout

  // Discharge, "-" Remote control to ground,  "+" to Cx
  PORTB = Cap_ready;

  // Cx_0 Wait until Cx is discharged (U33 < 1.0v) or timeout 1
  while (not Comp_Low_HIGH) {
    if (millis() > timeout) {
      //Cx_end
      PORTB = Cap_ready;
      return TIMEOUT_CX0;
    }
  }

  // Additional delay to ensure Cx is discharged
  delayMicroseconds(400);

  noInterrupts();
    // Save Timer0 settings
    byte savedTCCR0B = TCCR0B;

    // Disable Timer0 (delay(), millis() and micros() Arduino functions also)
     TCCR0B = 0;

    // Start Timer1 no prescaler (1:1) at 16Mhz ticks every 62.5ns
    // Overflow interrupt every 65535 ticks (4095.9375us = 4.0959375ms)
    bitSet(TCCR1B, CS10);

    // The bit TOV1 is set (one) when an overflow occurs in Timer/Counter1.
    // Alternatively, TOV1 is cleared by writing a logic one to the flag.
    // Clear Timer1 overflow interrupt flags
    bitSet(TIFR1, TOV1);

    // Enable Timer1 overflow interrupt ISR(TIMER1_OVF_vect)
    bitSet(TIMSK1, TOIE1);

    // Initialize Timer1 overflow counters
    timer1count_Cx2 = 0;
    timer1count_Cx3 = 0;

    // Check if apply ESR compensation to Cx measure
    // Original if U330 >= 0x300 (768) (1 Ohm approx) Cx is measured with ESR compensation
    if (esr > ESRthreshold) {          // ESR value above which ESR compensation is applied to Cx measure
      PORTB = Cap_start2;
      // Original delay 3.6us (18 cycles PIC@20Mhz) for the end of the transition processes - PICK UP!!!
      // Direct conversion __builtin_avr_delay_cycles(58);
      __builtin_avr_delay_cycles(58);  // 58 cycles AVR@16Mhz = 58 * 62.5ns = 3.625us
      bitClear(PORTB, In_N_Cx);        // bcf   PORTC,In_N_Cx   //  turn off the "-" remote control input from Cx
    } else {
      // Cx_1
      PORTB = Cap_start;
    }
  interrupts();

  // Cx_2 Comp_Low --> wait until U33 > 1.0v and restart Timer1 counter or timeout 2
  //---------------------------------------------------------------------------------------
  while (Comp_Low_HIGH and TCCR1B) {}

  // Initialize Timer1 counter
  TCNT1 = 0;

  // Cx_3 Comp_Up --> wait until U33 > 2.0v and stop Timer1 or timeout 3
  //---------------------------------------------------------------------------------------
  while (Comp_Up_HIGH and TCCR1B) {}

  // Stop Timer1 if not timeout
  TCCR1B = 0;

  noInterrupts();
    // Disable Timer1 overflow interrupt
    bitClear(TIMSK1, TOIE1);

    // The bit TOV1 is set (one) when an overflow occurs in Timer/Counter1.
    // Alternatively, TOV1 is cleared by writing a logic one to the flag.
    // Clear Timer1 overflow interrupt flags
    bitSet(TIFR1, TOV1);

    // Restore Timer0 settings
    TCCR0B = savedTCCR0B;
  interrupts();

  // Cx_end
  PORTB = Cap_ready;

  // Checking for any timeout and return timeout code
  if (timer1count_Cx2 >= COMP_TIMEOUT) return TIMEOUT_CX2;
  if (timer1count_Cx3 >= COMP_TIMEOUT) return TIMEOUT_CX3;

  return NO_TIMEOUT;

}

// Get Cx measure
// Receives ESR measure to passthrough it to Cx meter function
// Returns Cx (µF) or any negative value when timeout
float getCx(float esr) {

  float Cx = 0;

  // Read Cx measure
  uint8_t resultCx = cx_meter(esr);

  // Checking for any timeout
  if (resultCx == NO_TIMEOUT) {

    // Get ticks number and store to global var
    CxTicks = (timer1count_Cx3 * 65535) + TCNT1;

    // Apply user correction for absolute value of Cx Timer1 ticks count
    int32_t cx_ticks = CxTicks + int(USR_1_Cx - add_Cx);

    if (cx_ticks > 0){
      // Calculate Cx capacitance
      Cx = cx_ticks / M_Cx;

      // Apply User correction factor for Cx
      Cx = Cx * USR_Cx;

    } else {
      // User configuration for USR_1_Cx too low
      Cx = TIMEOUT_CX4 * -1;
    }
  } else {
    // On any timeout return negative value
    Cx = resultCx * -1;

    // Set ticks to 0
    CxTicks = 0;
  }

  return Cx;

}

// ----------------- Calibration Functions -----------------

// Set and store to EEPROM user calibration values for ESR
template<typename T>
void calibrateESR(const char* message, T& value, uint16_t eeprom_offset, uint16_t range = U330threshold) {

  char buffer[8] = { 0 };
  float esr = 0.0;

  T eeprom_value = value;
  T step;

  // Step based on variable type
  if (is_float<T>::value) {
    step = 0.001;  // float
  } else {
    step = 1;  // no float assume integer
  }

  // Set accel settings
  uint8_t const   accel_factor =  9;
  uint8_t         accel        =  accel_factor;
  uint32_t        initial_time;

  // Display message
  lcd.clear();
  lcd.setCursor(0, 0);
  lcd.print(message);

  while (!BUTTON_MENU) {

    if (BUTTON_PLUS and !BUTTON_MINUS) {
      value = value + step;
    } else if (BUTTON_MINUS and !BUTTON_PLUS) {
      if (value > 0 ){
        value = value - step;
      }
    }

    // Read ESR in forced range
    esr = getESR(range);

    // Display value
    if (is_float<T>::value) {
      dtostrf(value, 5, 3, buffer);
    } else {
      snprintf(buffer, sizeof(buffer) - 1, "%04u", uint16_t(value));
    }
    lcd.setCursor(0, 1);
    lcd.print(buffer);

    // Display ESR in range
    dtostrf(esr, 6, 3, buffer);
    lcd.setCursor(8, 1);
    lcd.print(buffer);
    lcd.print(F(" \1"));   // " Ω" Omega

    // Apply accel
    initial_time = millis() + ( accel * accel_factor );

    while ( ((BUTTON_PLUS or BUTTON_MINUS) and (millis() <= (initial_time))) ){
      // Wait for release button or delay finished
    }

    if (BUTTON_PLUS or BUTTON_MINUS){
      if (accel > 0) accel--;
    } else {
        accel = accel_factor;
    }

  }

  while (BUTTON_MENU) delay(10);  // Wait until the button is released

  if (eeprom_value != value) {
    lcd.setCursor(0, 1);
    lcd.print(F("Saved!"));
    EEPROM.put(eeprom_offset, value);
    delay(2000);
  } else {
    // Do nothing
  }
}

// Set and store to EEPROM user calibration values for Cx
template<typename T>
void calibrateCx(const char* message, T& value, uint16_t eeprom_offset) {

  char buffer[16] = { 0 };
  float Cx = 0.0;

  T eeprom_value = value;
  T step;

  // Step based on variable type
  if (is_float<T>::value) {
    step = 0.001;  // float
  } else {
    step = 1;  // no float assume integer
  }

  // Set accel settings
  uint8_t   const accel_factor =  9;
  uint8_t         accel        =  accel_factor;
  uint32_t        initial_time;

  // Display message
  lcd.clear();
  lcd.setCursor(0, 0);
  lcd.print(message);
  while (!BUTTON_MENU) {

    if (BUTTON_PLUS and !BUTTON_MINUS) {
      value = value + step;
    } else if (BUTTON_MINUS and !BUTTON_PLUS) {
      if (value > 0 ){
        value = value - step;
      }
    }

    // Read Cx
    Cx = getCx(getESR());

    // Display value based on variable type
    if (is_float<T>::value) {
      dtostrf(value, 5, 3, buffer);                                   // "1.000"  //  5 chars
    } else {
      snprintf(buffer, sizeof(buffer) - 1, "%04u ", uint16_t(value)); // "1000 "  //  5 chars
    }
    // Display value
    lcd.setCursor(0, 1);
    lcd.print(buffer);

    // Display measure
    lcd.setCursor(6, 1);                                                          //  1 char skip
    if (Cx > 0) {  // If not timeout
      // Set decimal point based on Cx value
      if (Cx < 1) {
        dtostrf(Cx, 7, 5, buffer);  // "0.12345"                                  //  7 chars
      } else if (Cx < 10) {
        dtostrf(Cx, 7, 4, buffer);  // " 1.0000"                                  //  7 chars
      } else if (Cx < 100) {
        dtostrf(Cx, 7, 3, buffer);  // " 10.000"                                  //  7 chars
      } else if (Cx < 1000) {
        dtostrf(Cx, 7, 2, buffer);  // " 100.00"                                  //  7 chars
      } else if (Cx < 10000) {
        dtostrf(Cx, 7, 1, buffer);  // " 1000.0"                                  //  7 chars
      } else {
        dtostrf(Cx, 7, 0, buffer);  // " 100000"                                  //  7 chars
      }
      // Display Cx
      lcd.print(buffer);
      lcd.print(" \2F");  // " µF" Mu (micro) Farad                               //  3 chars
    } else {  // if timeout display timeout code                              
      snprintf(buffer, sizeof(buffer) - 1, " timeout %01u", uint16_t(Cx * -1));   // 10 chars
      lcd.print(buffer);
    }

    // Apply accel
    initial_time = millis() + ( accel * accel_factor );

    while ( ((BUTTON_PLUS or BUTTON_MINUS) and (millis() <= (initial_time))) ){
      // Wait for release button or delay finished
    }

    if (BUTTON_PLUS or BUTTON_MINUS){
      if (accel > 0) accel--;
    } else {
        accel = accel_factor ;
    }

  }

  while (BUTTON_MENU) delay(10);  // Wait until the button is released

  if (eeprom_value != value) {
    lcd.setCursor(0, 1);
    lcd.print(F("Saved!"));
    EEPROM.put(eeprom_offset, value);
    delay(2000);
  } else {
    // Do nothing
  }
}

// -------------------- Display Functions ------------------

// Display ESR (Ω) Ohms normal "ESR run mode"
void display_ESR(LiquidCrystal_I2C lcd, float ESR, float ESRol = ESRlimit) {

  char buffer[8] = { 0 };

  // Avoid display "-0.000 Ω"
  if ((ESR <= -0.00010) and (ESR > -0.0010)){
      ESR = 0;
  }

  // Avoid display a negative ESR when a non-electrolytic capacitor pushes ADC to zero
  if ((U330 == 0) and (CxTicks > 0 )){
      ESR = 0;
  }

  // Set decimal point based on ESR value
  if (ESR < 10.0) {
    dtostrf(ESR, 6, 3, buffer);     // "-0.123"  // 6 chars
  } else if (ESR < ESRol) {
    dtostrf(ESR, 6, 2, buffer);     // " 12.34"  // 6 chars
  } else {            
    buffer[0] = '>';                // ">"       // 1 char
    dtostrf(ESRol, 5, 2, buffer+1); //   "12.34" // 5 chars  
  }

  // Display ESR value Ω
  lcd.setCursor(0, 1);              // Display to LCD second line
  lcd.print(F("ESR "));             // 4 chars    
  lcd.print(buffer);                // 6 chars
  lcd.print(F(" \1 ")); // " Ω "    // 3 chars (1 char padding)

                                    // 1........0.....6 //
                                    // ESR.-0.123.Ω.OFF // 4-3 (OFF) padding
                                    // ESR..0.123.Ω.OFF // 4-3 (OFF) padding
                                    // ESR..12.34.Ω.OFF // 4-3 (OFF) padding
                                    // ESR.>12.34.Ω.OFF // 4-3 (OFF) padding
}

// Display Cx (µF) microfarad normal "Cx run mode"
void display_Cx(LiquidCrystal_I2C lcd, float Cx) {

  char buffer[8] = { 0 };

  // Set decimal point based on Cx value
  if (Cx < 1) {
    snprintf(buffer, sizeof(buffer)-1, "<1.000"); // 6 chars
  } else if (Cx < 10) {
    dtostrf(Cx, 6, 3, buffer);      //  " 1.000"  // 6 chars
  } else if (Cx < 100) {
    dtostrf(Cx, 6, 2, buffer);      //  " 10.00"  // 6 chars
  } else if (Cx < 1000) {
    dtostrf(Cx, 6, 1, buffer);      //  " 100.0"  // 6 chars
  } else {
    dtostrf(Cx, 6, 0, buffer);      //  "  1000"  // 6 chars
                                    //  " 10000"  // 6 chars
                                    //  "100000"  // 6 chars
  }

  // Display Cx value µF
  lcd.setCursor(0, 0);              // Display to LCD first line
  lcd.print(F(" Cx "));             // 4 chars
  lcd.print(buffer);                // 6 chars
  lcd.print(F(" \2F  "));// " µF  " // 5 chars (2 chars padding)

                                    // 1........0.....6 //
                                    // .Cx.<1.000.uF..B // 3-1 (BELL) padding
                                    // .Cx..1.123.uF..B // 3-1 (BELL) padding
                                    // .Cx..12.34.uF..B // 3-1 (BELL) padding
                                    // .Cx..123.4.uF..B // 3-1 (BELL) padding
                                    // .Cx..12345.uF..B // 3-1 (BELL) padding
                                    // .Cx.123456.uF..B // 3-1 (BELL) padding
}

// Display raw values of ADC measures from global vars U330 and U33 in "ESR test mode"
void display_ESR_raw(LiquidCrystal_I2C lcd) {

  char buffer[6] = { 0 };

  lcd.setCursor(0, 1);

  // Display U330 for 1 Ohm range
  lcd.print(F("1\1="));  // "1Ω=" Omega 
  snprintf(buffer, sizeof(buffer) - 1, "%04u", U330);
  lcd.print(buffer);

  // Display U33 for 10 Ohms range
  lcd.print(F(" 10\1=")); // " 10Ω=" Omega
  snprintf(buffer, sizeof(buffer) - 1, "%04u", U33);
  lcd.print(buffer);
}

// Display Cx raw ticks counter from global var CxTicks in "Cx test mode"
void display_Cx_raw(LiquidCrystal_I2C lcd) {

  char buffer[20] = { 0 };

  snprintf(buffer, sizeof(buffer) - 1, " Cx %09lu  ", CxTicks); // 15 chars

                                     // 1........0.....6 //
                                     // .Cx.123456789..B // 3-1 padding

  lcd.setCursor(0, 0);
  lcd.print(buffer);
}

// -------------------- EEPROM Functions ------------------

// Read user calibration values from EEPROM
// or writes default calibration values in first use
void initEEPROM(void) {

  String flag = String(ESR_METER_FLAG);
  String flag_read = String("");
  char c = '\0';

  // Try to read ESR_METER_FLAG from EEPROM
  for (uint16_t i = 0; i < flag.length(); i++) {
    c = EEPROM.read(ESR_METER_FLAG_EEPROM_OFFSET + i);
    flag_read += c;
  }

  if (flag == flag_read) {  // Read user settings from EEPROM
    EEPROM.get(U0_ESR_1_EEPROM_OFFSET, U0_ESR_1);
    EEPROM.get(U0_ESR_10_EEPROM_OFFSET, U0_ESR_10);
    EEPROM.get(USR_1_EEPROM_OFFSET, USR_1);
    EEPROM.get(USR_10_EEPROM_OFFSET, USR_10);
    EEPROM.get(USR_Cx_EEPROM_OFFSET, USR_Cx);
    EEPROM.get(USR_1_Cx_EEPROM_OFFSET, USR_1_Cx);

  } else {  // Write default calibration values to EEPROM
    EEPROM.put(U0_ESR_1_EEPROM_OFFSET, U0_ESR_1);
    EEPROM.put(U0_ESR_10_EEPROM_OFFSET, U0_ESR_10);
    EEPROM.put(USR_1_EEPROM_OFFSET, USR_1);
    EEPROM.put(USR_10_EEPROM_OFFSET, USR_10);
    EEPROM.put(USR_Cx_EEPROM_OFFSET, USR_Cx);
    EEPROM.put(USR_1_Cx_EEPROM_OFFSET, USR_1_Cx);

    // Write ESR_METER_FLAG to EEPROM
    for (uint16_t i = 0; i < flag.length(); i++) {
      EEPROM.write(ESR_METER_FLAG_EEPROM_OFFSET + i, flag[i]);
    }
  }
}

// beep for "duration" milliseconds
void beep(uint16_t duration, byte pin) {
  digitalWrite(pin, HIGH);
  delay(duration);
  digitalWrite(pin, LOW);
}

// ---------------- Arduino Setup Function -----------------

void setup() {
  noInterrupts();
    // Setup Port D to manage inputs from LM393 comparator and user buttons, and output power on.
    DDRD = Port_D_Config;

    // Set "Power On", keeping to HIGH the POWER_OFF output (USB DEBUG) forces battery power if present
    Set_Power_On;

    // Setup Port B to manage Cx outputs
    DDRB = Port_B_Config;

    // Set initial Port D status
    PORTB = ESR_ready;

    // Set Timer1 to normal mode
    TCCR1A = 0;
    TCCR1B = 0;

    // Set ADC prescaler clock
    ADCSRA = ADCSRA & 0xF8;  // Clear ADPS2-ADPS0
    ADCSRA |= ADC_CLOCK;     // Set ADC prescaler clock
    __builtin_avr_delay_cycles(4);

    // Select ADC reference
    bitClear(ADMUX, REFS1);
    bitWrite(ADMUX, REFS0, ADC_VREF_TYPE);
    __builtin_avr_delay_cycles(4);

    // Enable ADC module
    bitSet(ADCSRA, ADEN);
    __builtin_avr_delay_cycles(4);
  interrupts();

  // Buzzer setup
  pinMode(BUZZER, OUTPUT);
  digitalWrite(BUZZER, LOW);

  // Initial beep
  beep();

  // Get battery voltage (Arduino Vin) or USB power
  float vbatt = adc_vbatt();

  // USB Serial debug output
  Serial.begin(115200);
  Serial.println(F("\nBooting " MESSAGE " v" VERSION));

  // Init LCD
  lcd.init();
  lcd.createChar(SKIP,  skip);    // Skip address 0x00
  lcd.createChar(OMEGA, omega);   // "Ω" Omega      \1
  lcd.createChar(MU,    mu);      // "µ" Mu (micro) \2
  lcd.createChar(BELL,  bell);    // bell           \3
  lcd.createChar(LOCK,  lock);    // lock           \4
  lcd.backlight();
  lcd.clear();

  // Display message and version on first line
  lcd.print(MESSAGE);   // 11 chars max
  lcd.print(F(" v"));   //  2 chars
  lcd.print(VERSION);   //  3 chars max

  // Display battery voltage on second line
  lcd.setCursor(0, 1);

  if (vbatt < VBATT_MIN) {  // Maybe USB powered

    // Wait while power is low
    lcd.print(F("Low power: "));     // 11 chars
    lcd.print(vbatt);     //  "1.23" //  4 chars
    lcd.print("v");                  //  1 char

    // Debug battery info
    Serial.print(F("Low power: "));
    Serial.print(vbatt);
    Serial.println(F("v detected!"));
    
    delay(2000);

    // Power Off (disconnect battery)
    Set_Power_Off;

    // Wait to power off
    delay(100);

    // If still here it's because of USB power

    while (vbatt < VBATT_MIN){
      // battery voltage on second line
      lcd.setCursor(11, 1);
      lcd.print(vbatt);
      lcd.print("v");

      // Debug warning
      Serial.print(F("USB power: "));
      Serial.print(vbatt);
      Serial.println("v");

      // Delay between measures
      delay(1000);

      // Get battery voltage
      vbatt = adc_vbatt();
    }

    // Set "Power On" (reconnect battery)
    Set_Power_On;

    // Clear LCD second line
    lcd.setCursor(0, 1);
    lcd.print(F("                "));
    lcd.setCursor(0, 1);

    // Power on warning
    beep();
  }
    
  // Display battery voltage on second line
  lcd.print(F("Battery: "));

  if (vbatt < VBATT_MAX) {
    lcd.print(vbatt);
  } else {
    lcd.print(">");
    lcd.print(VBATT_MAX);
  }
  lcd.print("v");

  // Debug battery info
  Serial.print(F("Battery: "));
  Serial.print(vbatt);
  Serial.println("v");

  // Init EEPROM
  // Read user calibration values from EEPROM
  // or writes default calibration values in first use
  initEEPROM();
  
  // Serial debug info
  Serial.println(F("\nHardware configuration:"));
  Serial.println(F("-----------------------------"));
  Serial.print(F("ADC_VREF_VALUE:       ")); Serial.println(ADC_VREF_VALUE,3);
  Serial.print(F("VBATT_FACTOR:         ")); Serial.println(VBATT_FACTOR,3);
  Serial.print(F("VBATT_MIN:            ")); Serial.print(VBATT_MIN,3);
  Serial.print(F("v (max: ")); Serial.print(VBATT_MAX,2); Serial.println(F("v)"));

  Serial.println(F("\nHardware based parameters:"));
  Serial.println(F("-----------------------------"));
  Serial.print(F("M_ESR_1:              ")); Serial.println(M_ESR_1);
  Serial.print(F("M_ESR_10:             ")); Serial.print(M_ESR_10); Serial.print(F(" (ESR limit: "));Serial.print(ESRlimit,2); Serial.println(F(" ohms)"));
  Serial.print(F("U330threshold:        ")); Serial.println(U330threshold);
  Serial.print(F("M_Cx:                 ")); Serial.println(M_Cx);
  Serial.print(F("add_Cx:               ")); Serial.println(add_Cx);
  Serial.print(F("ACD_MEASURES:         ")); Serial.println(ACD_MEASURES);
  Serial.print(F("COMP_TIMEOUT:         ")); Serial.print(COMP_TIMEOUT); 
  Serial.print(F(" ("));
  Serial.print(uint16_t(COMP_TIMEOUT*4.0959375));
  Serial.print(F(" msecs) Cx max: "));
  Serial.print(uint32_t(((COMP_TIMEOUT*65535)+65535)/M_Cx));
  Serial.println(F(" uF"));

  Serial.println(F("\nUser calibration settings:"));
  Serial.println(F("-----------------------------"));
  Serial.print(F("ESR factor 1 ohm:     ")); Serial.println(USR_1,3);
  Serial.print(F("ESR factor 10 ohms:   ")); Serial.println(USR_10,3);
  Serial.print(F("Cx factor:            ")); Serial.println(USR_Cx,3);
  Serial.print(F("Cx counter:           ")); Serial.println(USR_1_Cx);
  Serial.print(F("ESR set zero 1 ohm:   ")); Serial.println(U0_ESR_1);
  Serial.print(F("ESR set zero 10 ohms: ")); Serial.println(U0_ESR_10);
  Serial.println();

  // Delay to show version message and battery voltage
  delay(2000);

  // Check if "On/Off/Menu/Set" button is pressed to enter in "Calibration Menu"
  if (BUTTON_MENU) {
    lcd.clear();
    lcd.setCursor(0, 0);
    lcd.print(F("Calibration Menu"));
    lcd.setCursor(0, 1);
    lcd.print(F(" button release "));
    while (BUTTON_MENU) delay(1);  // Wait until the button is released

    // Setting user correction factor for ESR range 1 Ohm (USR_1) U330
    calibrateESR("ESR factor 1\1", USR_1, USR_1_EEPROM_OFFSET, 1024);  // >1023 to force range 1 Ohm (using U330 value)

    // Setting user correction factor for ESR range 10 Ohms (USR_10) U33
    calibrateESR("ESR factor 10\1", USR_10, USR_10_EEPROM_OFFSET, 0);  // 0 to force range 10 Ohms (using U33 value)

    // Setting user correction factor for Cx
    calibrateCx("Cx factor", USR_Cx, USR_Cx_EEPROM_OFFSET);

    // Setting user correction for absolute value of Cx Timer1 ticks count
    calibrateCx("Cx counter", USR_1_Cx, USR_1_Cx_EEPROM_OFFSET);

    // Setting user correction for "Set to Zero" ESR range 1 Ohm using U0_ESR_1
    calibrateESR("ESR set zero 1\1", U0_ESR_1, U0_ESR_1_EEPROM_OFFSET, 1024);  // >1023 to force range 1 Ohm (using U330 value)

    // Setting user correction for "Set to Zero" ESR range 10 Ohms using U0_ESR_10
    calibrateESR("ESR set zero 10\1", U0_ESR_10, U0_ESR_10_EEPROM_OFFSET, 0);  // 0 to force range 10 Ohms (using U33 value)

    // Exit calibration menu warning
    beep();
  }
  lcd.clear();

  Serial.print(F("Auto power off warning timer: ")); Serial.print(WARNING_OFF); Serial.println(F(" secs (approx)"));
  Serial.print(F("Auto power off timer:         ")); Serial.print(AUTO_OFF); Serial.println(F(" secs (approx)"));

  // Set auto-off timers
  WarningOffTimer = millis() + (WARNING_OFF * MILLIS_S);
  AutoOffTimer = millis() + (AUTO_OFF * MILLIS_S);

}

// ---------------- Arduino Loop Function -----------------

void loop() {

  // Checking for "On/Off/Menu/Set" button pressed to clear warning or power off or manual remeasure
  if (BUTTON_MENU and !BUTTON_MINUS and AutoOffTimer != 0) {

    // Clears Cx filtered measure  to force the Cx measurement to restart
    CxFiltered=0;

    // If after 150 ms the button is still pressed, the power off countdown begins.
    delay(150);
    if (BUTTON_MENU){
      beep(25);

      // Countdown to power off
      uint8_t  countdown    = 9;                          // From 9 to 0 total 10 steps 
      uint16_t pressedTime  = 3000;                       // Milliseconds that the button must be pressed
      uint16_t step         = pressedTime/10;
      uint32_t pressed      = millis() + pressedTime;

      // Long press (pressedTime ms) to power off
      while (BUTTON_MENU and (millis() < pressed)){

        // Countdown update check
        if (millis() > (pressed-pressedTime)){

          // Display countdown to upper right corner
          lcd.setCursor(15, 0);
          lcd.print(countdown);

          // Update countdown
          pressedTime = pressedTime-step;
          countdown--;

        }

        // Display "OFF" to lower right corner
        lcd.setCursor(13, 1);
        lcd.print(F("OFF"));
      }

      // If "On/Off/Menu/Set" button still pressed, then it "turns off"
      if (BUTTON_MENU) {

        beep(25);

        lcd.clear();
        lcd.setCursor(0, 1);
        lcd.print(F(" button release "));

        // Wait until the button is released
        while (BUTTON_MENU) {}

        // Power Off
        Set_Power_Off;

        // Wait to power off
        delay(100);

        // If still here it's because of USB power

        // Set "Power On", keeping to HIGH the POWER_OFF output (USB DEBUG) forces battery power if present
        Set_Power_On;

        // Beep warning
        beep(25);

        // Clear "button release" message
        lcd.clear();

        // Force max unsigned long to enable manual power-off
        AutoOffTimer = -1;

      } else {  // Sort press to clear warning

        // Clear "OFF" to lower right corner
        lcd.setCursor(13, 1);
        lcd.print(F("   "));

        // Clear countdown or bell char to upper right corner
        lcd.setCursor(15, 0);
        lcd.print(" ");

      }

      // Check for "lock" status
      #pragma GCC diagnostic push
      #pragma GCC diagnostic ignored "-Wsign-compare"
      if (AutoOffTimer == -1){
      #pragma GCC diagnostic pop
        // Re-display "lock char" to upper right corner
        lcd.setCursor(15, 0);        
        lcd.write(LOCK);
      }else{
        // Reset auto-off timers
        WarningOffTimer = millis() + (WARNING_OFF * MILLIS_S);
        AutoOffTimer = millis() + (AUTO_OFF * MILLIS_S);
      }
    }
  }

  // Checking for auto-off warning beep
  if ((WarningOffTimer > 0) and (millis() > WarningOffTimer)) {

    // Disable auto-off warning beep
    WarningOffTimer = 0;

    // Display "bell char" to upper right corner
    lcd.setCursor(15, 0);
    lcd.write(BELL);

    // Warning beep
    beep(100);
  }

  // Checking for auto-off
  if ((AutoOffTimer > 0) and (millis() > AutoOffTimer)) {

    // Disable auto-off
    AutoOffTimer = 0;

    // Power off beep
    beep(250);

    // Power Off
    Set_Power_Off;

    // Wait to power off
    delay(100);

    // If still here it's because of USB power

    // Set "Power On", keeping to HIGH the POWER_OFF output (USB DEBUG) forces battery power if present
    Set_Power_On;

    // Force max unsigned long to enable manual power-off
    AutoOffTimer = -1;

    // Display "lock char" to upper right corner
    lcd.setCursor(15, 0);
    lcd.write(LOCK);

  }

  // Display ESR on second line of LCD (normal or test mode)
  // Get ERS measure
  float esr = getESR();

  // Checking for (-) minus button pressed
  if (BUTTON_MINUS) {
    // Display raw U330 and U33 values "ESR test mode"
    display_ESR_raw(lcd);

    // Serial debug info for ESR measures
    Serial.print(F("ESR:"));Serial.print(esr,4);Serial.print(",");
    Serial.print(F("U330:"));Serial.print(U330);Serial.print(",");
    Serial.print(F("U33:"));Serial.print(U33);Serial.print(",");
    Serial.print(F("U330average:"));Serial.print(U330average);Serial.print(",");
    Serial.print(F("U33average:"));Serial.print(U33average);Serial.println();

    // Set flag to clear raw values from second line after
    if (not ESR_RAW_VALUES){
      ESR_RAW_VALUES = true;
    } 

    // Checking for "On/Off/Menu/Set" button pressed to "Set to Zero"
    if (BUTTON_MENU) {
      if ((U0_ESR_1 != U330) or (U0_ESR_10 != U33)) {
        // Set user correction for "Set to Zero" ESR range 1 Ohm (U330)
        U0_ESR_1 = U330;

        // Set user correction for "Set to Zero" ESR range 10 Ohm (U33)
        U0_ESR_10 = U33;

        // Save to EEPROM
        EEPROM.put(U0_ESR_1_EEPROM_OFFSET, U0_ESR_1);
        EEPROM.put(U0_ESR_10_EEPROM_OFFSET, U0_ESR_10);

        lcd.setCursor(0, 0);                // First line
        lcd.print(F("     Saved!    "));    // 15 chars
        delay(2000);
        lcd.setCursor(0, 0);                // First line
        lcd.print(F("               "));    // Clear 15 chars
      } else {
        lcd.setCursor(0, 0);                // First line
        lcd.print(F("      Done!    "));    // 15 chars
        delay(2000);
        lcd.setCursor(0, 0);                // First line
        lcd.print(F("               "));    // Clear 15 chars
      }
    }
  } else {

    // Clears ESR raw values if any
    if (ESR_RAW_VALUES){
      ESR_RAW_VALUES = false;
      lcd.setCursor(0, 1);                  // Second line
      lcd.print(F("                "));     // 16 chars
    }

    // Display ESR measure "normal run mode"
    display_ESR(lcd, esr);
  }

  // Display Cx on first line of LCD
  // If ESR < ESRlimit display Cx (normal or test mode)
  if (esr < ESRlimit) {

    // Delay to ensure Cx discharged
    delay(25);

    // Get calculated Cx measure
    float Cx = getCx(esr);

    if (Cx > 0) {
      // Apply IIR digital filter

      // Set initial value and exponential smoothing factor
      if ((CxFiltered > Cx*1.2) or (CxFiltered < Cx*(0.8))) {   // if Cx value difference > 20% from previous value, assume Cx as new measurement
        CxFiltered = Cx;
        CxAlpha=ALPHA_Cx;
      }else{
        if ((CxAlpha > 0.000) and (Cx_MEASURES > 0)){           // Stop adjusting after Cx_MEASURES measurements "auto-hold"
            CxAlpha = CxAlpha - float(ALPHA_Cx/Cx_MEASURES);
            if (CxAlpha <= 0.000){
              CxAlpha = 0;
              beep(5);                                          // "auto-hold" beep
            }
        }
      }

      // Get Exponential Moving Average as Cx filtered
      CxFiltered = (CxAlpha * Cx) + ((1 - CxAlpha) * CxFiltered);

    } else {
      // Force next Cx value as new measurement
      CxFiltered = 0;
    }

    // Checking for (+) plus button pressed
    if (BUTTON_PLUS) {
      // Display raw "Cx test mode"
      if (Cx > 0) {
        display_Cx_raw(lcd);                // First line
      } else {
        lcd.setCursor(0, 0);                // First line
        lcd.print(F(" Cx timeout "));       // 12 chars
        lcd.print(int(Cx * -1));            //  1 char
        lcd.print(F("  "));                 //  2 chars (3-1 chars padding)
      }

      // Serial debug info for raw Cx measures
      Serial.print(F("CxTicks:"));Serial.print(CxTicks);Serial.print(",");
      Serial.print(F("CxRaw:"));Serial.print(Cx,3);Serial.print(",");
      Serial.print(F("CxFiltered:"));Serial.print(CxFiltered,3);Serial.println();

    } else {
      // Display normal "Cx run mode"
      if (Cx > 0) {
        // If not timeout display Cx filtered measure
        display_Cx(lcd, CxFiltered);           // First line

      } else {
        // If timeout display "Auto" message
        lcd.setCursor(0, 0);                   // First line
        lcd.print(F(" Cx \x7E Auto \x7F   ")); // 15 chars (4-1 chars padding)
      }
    }
  } else {
  
    // Force next Cx value as new measurement
    CxFiltered = 0;

    // Skip Cx measure if ESR > ESRlimit
    lcd.setCursor(0, 0);                        // First line
    lcd.print(F(" Cx \x7E Skip \x7F   "));      // 15 chars (4-1 chars padding)
  }

  // Get battery voltage (Arduino Vin) or USB power
  float vbatt = adc_vbatt();

  // Check battery voltage
  if (vbatt < VBATT_MIN) { 

    beep(250);

    // Set LCD second line
    lcd.clear();
    lcd.setCursor(0, 1);

    // Display low battery warning
    lcd.print(F("Low power: "));  // 11 chars
    lcd.print(vbatt); //  "1.23"  //  4 chars
    lcd.print("v");               //  1 char

    // Debug battery info
    Serial.print(F("Low power: "));
    Serial.print(vbatt);
    Serial.println(F("v detected!"));
    
    delay(2000);

    // Power Off
    Set_Power_Off;

    // Wait to power off
    delay(100);

    // If still here it's because of USB power

    // Set LCD first line
    lcd.setCursor(0, 0);
    lcd.print(F("Rebooting...."));  

    // Debug info
    Serial.println(F("Rebooting...."));
    delay(2000);

    // System restart
    asm("jmp 0x0000");   
  }
}
