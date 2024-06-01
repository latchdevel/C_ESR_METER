# Bill Of Materials for "C/ESR Meter"

**Board revision v1.0.7 (Jun 2024)**

## Resistors

| Quantity | References (1% 1/4 watt 400mil) |    Value | Comments |
|:--------:|:--------------------------------|---------:|:---------|
|     1    | R1                              |    1500R | AD620 gain "33" (default 10Ω range). Theoretical 1543.75Ω. If R1=1500R --> G=31.9
|     1    | R2                              |      75R | AD620 gain "330", (1Ω range). Depends on $R_{on}$ of CD4066B at 5v which should be measured. If R2=75R and (CD4066B $R_{on} @5v$)=92R --> G=337
|     1    | R3                              |     180R | Capacitor charge current limiter to 10mA. $I_o = \frac{V_{ref} - V_{be}}{ R_s } = \frac{2.5v - 0.7v}{ 180Ω } = \frac{1.8v}{ 180Ω } = 0.01A = 10mA$ 
|     2    | R4, R24                         |     560R | ADC and Z1 current limiters, any approximate value will work fine.
|     1    | R5                              |     270k | Together with R6 they form a voltage divider to measure the battery level. Their ratio must be defined in the source code: `#define VBATT_FACTOR 3.7 // = 1+(R5/R6) = 1+(270k/100k) = 1+(2.7) = 3.7`
|     7    | R6, R16, R17, R18, R19, R20, R23|     100k | R6 together with R5 form a voltage divider, see R5. The others are pull-up and pul-down resistors, any approximate value will work fine.
|     2    | R7, R26                         |      20k | They are part of the voltage dividers for voltage references.
|     1    | R25                             |      12k | It is part of the voltage dividers for voltage references.
|     7    | R8, R9, R10, R12, R13, R14, R15 |      10k | R8 and R9 are part of the voltage dividers for voltage references. The others are pull-up and current limiters, any approximate value will work fine.
|     3    | R11, R21, R22                   |     100R | MOSFET current limiters, any approximate value will work fine.

## Capacitors

| Quantity | References                      |    Value | Comments |
|:--------:|:--------------------------------|---------:|:---------|
|     2    | C1, C2                          |    4.7nF | Non-polarized polyester capacitors
|     1    | C3                              |    220uF | Negative voltage filter, polarized electrolytic capacitor (16v) from 100uF it will be fine.
|     1    | C4                              |     10uF | Charge-Pump capacitor, polarized electrolytic capacitor (16v)
|     1    | C8                              |     22uF | $V_{in}$ capacitor, polarized electrolytic capacitor (50v)
|     3    | C5, C6, C7                      |    4.7uF | Voltage dividers load capacitance are required, from 1uF to 10uF, polarized electrolytic capacitors (16v)
|     6    | C9, C10, C11, C12, C13, C14     |    100nF | Noise filters, non-polarized ceramic capacitors should be close to the device (within 5 mm of the pin)

## Diodes

| Quantity | References                      |    Value | Comments |
|:--------:|:--------------------------------|---------:|:---------|
|     2    | D1, D2                          |   1n5819 | (400mil) Low drop power Schottky rectifier diode
|     3    | D3, D4, D5                      |   1n4148 | (300mil) General purpose small signal high-speed switching diode
|     1    | D6                              |    BAT49 | (300mil) Very low turn-on voltage small signal Schottky diode (Vf=180mV)

## Transistors

| Quantity | References                      |    Value | Comments |
|:--------:|:--------------------------------|---------:|:---------|
|     1    | Q1                              |   BC557B | TO-92  BJT PNP like as BC557A, BC558, 2N3609 (EBC pinout warning), etc.
|     1    | Q2                              |  IRF530N | TO-220 MOSFET N-Channel like as IRF520, IRF540, IRLZ44N or similar.
|     2    | Q3, Q4                          | IRFU5305 | TO-251 MOSFET P-Channel low $RDS_{on}$
|     2    | Q5, Q6                          |   2N7000 | TO-92  MOSFET N-Channel general purpose

## Integrated circuits

| Quantity | References                      |    Value | Comments |
|:--------:|:--------------------------------|---------:|:---------|
|     2    | Z1, Z2                          |    TL431 | TO-92  Adjustable precision voltage reference ($V_{ref}=2.5v$)
|     1    | U1                              |    AD620 | DIP-8  Low cost, high accuracy instrumentation amplifier (INA129 gain equation compatible)
|     1    | U2                              |  CD4066B | DIP-14 Quad bilateral analog switch, CMOS device type “4066” compatible such as HEF4066, HCF4066, 74HC4066, M74HC4066, MC14066, MAX4066, etc. $R_{on} @5v$ must be measured to add to R2.
|     1    | U3                              |    LM393 | DIP-8  Dual independent low offset voltage precision comparators
|     1    | U4                              | ICL7660A | DIP-8  Switched-Capacitor voltage converter (Intersil/Renesas)


## Miscellaneous

| Quantity | References                                       | Comments |
|:--------:|:-------------------------------------------------|:---------|
|     1    | LCD display 16x02 (5v) HD44780 or similar        |
|     1    | LCD I2C adapter (PCF8574)                        |
|     1    | Active buzzer 5v (12 mm) (7.6mm pitch)           |
|     3    | Button SPST (normal open) 12mm                   | 
|     4    | Header connector 2-Pin JST male (2.54mm pitch)   | Optional
|     1    | Header connector 4-Pin JST male (2.54mm pitch)   | Optional
|     1    | Terminal block connector 4-Pin (5mm pitch)       | Optional
|     1    | Enclosure Bahar BDC30001-A                       | Optional