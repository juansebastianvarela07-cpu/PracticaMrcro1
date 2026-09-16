;=========================================================
; ARCHIVO:      Vumetro_ADC_XC8.asm
; MICRO:        PIC18F4550 (XC8 pic-as)
; DESCRIPCIÓN:  Lectura del canal AN0 (RA0) con el ADC. 
;               El valor convierte a un vúmetro de 8 LEDs 
;               en el Puerto D.
;=========================================================

    #include <xc.inc>

    ; --- BITS DE CONFIGURACIÓN ---
    CONFIG  FOSC = INTOSCIO_EC   ; Oscilador interno
    CONFIG  WDT = OFF            ; Watchdog Timer apagado
    CONFIG  LVP = OFF            ; Programación en bajo voltaje apagada
    CONFIG  PBADEN = OFF         ; Pines de PORTB como digitales
    CONFIG  MCLRE = ON           ; ¡IMPORTANTE! Pin MCLR habilitado (Requiere 5V en Pin 1)

    ;===============================================
    ; Vector de Reset
    ;===============================================
    PSECT resetVec, class=CODE, reloc=2
    ORG     0x00
    GOTO    Inicio

    ;===============================================
    ; Programa Principal
    ;===============================================
    PSECT main_code, class=CODE, reloc=2

Inicio:
    ; 1. Configurar oscilador interno a 8 MHz
    MOVLW   01110010B            ; IRCF = 111 (8 MHz), SCS = 10 (Oscilador interno)
    MOVWF   OSCCON, c

    ; 2. Configuración de Entradas y Salidas
    CLRF    TRISD, c             ; Todo el Puerto D como salida (LEDs)
    CLRF    LATD, c              ; Iniciar salidas en 0 (Buena práctica usar LAT en PIC18)
    BSF     TRISA, 0, c          ; RA0 como entrada (Potenciómetro)

    ; 3. Configuración del Módulo ADC
    MOVLW   0x0E                 ; 00001110: AN0 como análogo, resto digitales. Vref = VDD/VSS
    MOVWF   ADCON1, c

    ; ADFM=0 (Izquierda), ACQT=100 (4 TAD), ADCS=010 (FOSC/32)
    MOVLW   00010010B     
    MOVWF   ADCON2, c

    ; CHS3:CHS0 = 0000 (AN0), ADON = 1
    MOVLW   00000001B     
    MOVWF   ADCON0, c

Loop_ADC:
    ; 4. Iniciar la conversión A/D
    BSF     ADCON0, 1, c         ; Poner en 1 el bit GO/DONE (Bit 1 del registro ADCON0)

Wait_ADC:
    BTFSC   ADCON0, 1, c         ; Monitorear el bit GO/DONE hasta que el hardware lo ponga en 0
    GOTO    Wait_ADC

    ; 5. Lógica de Umbrales (Comparación con ADC)
    ; Se resta W a ADRESH. Si ADRESH >= W, el bit Carry (Bit 0 de STATUS) es 1.
    MOVLW   224
    SUBWF   ADRESH, W, c
    BTFSC   STATUS, 0, c
    GOTO    Leds_8

    MOVLW   192
    SUBWF   ADRESH, W, c
    BTFSC   STATUS, 0, c
    GOTO    Leds_7

    MOVLW   160
    SUBWF   ADRESH, W, c
    BTFSC   STATUS, 0, c
    GOTO    Leds_6

    MOVLW   128
    SUBWF   ADRESH, W, c
    BTFSC   STATUS, 0, c
    GOTO    Leds_5

    MOVLW   96
    SUBWF   ADRESH, W, c
    BTFSC   STATUS, 0, c
    GOTO    Leds_4

    MOVLW   64
    SUBWF   ADRESH, W, c
    BTFSC   STATUS, 0, c
    GOTO    Leds_3

    MOVLW   32
    SUBWF   ADRESH, W, c
    BTFSC   STATUS, 0, c
    GOTO    Leds_2

    MOVLW   10                   ; Margen de ruido
    SUBWF   ADRESH, W, c
    BTFSC   STATUS, 0, c
    GOTO    Leds_1

Leds_0:
    MOVLW   00000000B
    GOTO    Actualizar_Puerto
Leds_1:
    MOVLW   00000001B
    GOTO    Actualizar_Puerto
Leds_2:
    MOVLW   00000011B
    GOTO    Actualizar_Puerto
Leds_3:
    MOVLW   00000111B
    GOTO    Actualizar_Puerto
Leds_4:
    MOVLW   00001111B
    GOTO    Actualizar_Puerto
Leds_5:
    MOVLW   00011111B
    GOTO    Actualizar_Puerto
Leds_6:
    MOVLW   00111111B
    GOTO    Actualizar_Puerto
Leds_7:
    MOVLW   01111111B
    GOTO    Actualizar_Puerto
Leds_8:
    MOVLW   11111111B

Actualizar_Puerto:
    MOVWF   LATD, c              ; Escribir el patrón de bits en los Latch del Puerto D
    GOTO    Loop_ADC             ; Nueva conversión ininterrumpida

    END