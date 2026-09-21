;========================================================================
;ARCHIVO:      Practica1_ControlTemperatura.asm
;MICRO:        PIC18F4550 (XC8 pic-as)
;DESCRIPCIÓN:  SISTEMA DE CONTROL Y SUPERVISIÓN DE TEMPERATURA CON LM35,
;               ADC MUESTREADO POR Timer0 E INTERRUPCIONES INT0, INT1, INT2.
;========================================================================

#include <xc.inc>
;--- BITS DE CONFIGURACIÓN--
    CONFIG FOSC = INTOSCIO_EC  ; OSCILADOR INTERNO
    CONFIG WDT = OFF           ;WATCHDOS TIMER APAGADO 
    CONFIG LVP = OFF           ;PROGRAMACIÓN EN BAJO VOLTAJE APAGADA
    CONFIG PBADEN = OFF        ;PINES DE PORTB COMO DIGITALES
    CONFIG MCLRE = ON          ;PIN MCLR HABILITADO 
    CONFIG XINST = OFF         ;MODO DE INSTRUCCIONES EXTENDIDAS DESACTIVADO 
    
 ;========================================================================
 ; VARIABLES EN MEMORIA RAM 
 ;========================================================================
 PSECT udata_acs
 
    ;===== BANDERAS DE ESTADO (BOOLEANAS) ======
        ESTADO_ALARMA:     DS 1 ; 0 = APAGADA, 1 = ENCENDIDA (INT0)
        ESTADO_VENTILADOR: DS 1 ; 0 = APAGADO, 1 = ENCENDIDO (INT1)
        MODO_UNIDAD:       DS 1 ; 0 = °CELSIUS, 1 = °FAHRENHEIT (INT2)
    ;===== DATOS DEL ADC Y CONVERSIÓN ======
        VALOR_ADC_L:       DS 1 ; BYTE BAJO DE LA LECTURA DEL ADC
        VALOR_ADC_H:       DS 1 ; BYTE BAJO DE LA LECTURA DEL ADC
        TEMP_CELSIUS:      DS 1 ; VALOR CONVERTIDO EN °C
        TEMP_FAHRENHEIT:   DS 1 ; VALOR CONVERTIDO EN °F
	TEMP_MOSTRAR:      DS 1 ; VALOR PARA ENVIAR AL DISPLAY
    ;===== BCD PARA EL DISPLAY 7 SEGMENTOS ======
	DIGITO_DEC:	   DS 1 ; DECENAS (0-9) PARA EL DISPLAY 7 SEG
	DIGITO_UNID:	   DS 1 ; UNIDADES (0-9) PARA EL DISPLAY 7 SEG
    ;===== CONTADORES Y CONTROL DE TIEMPO ======
	CONTADOR_ADC:      DS 1 ; TEMPORIZADOR SECUNDARIO PARA LANZAR LA LECTURA
    ;===== CONTROL DE DISPLAY MULTIPLEXADOS ======
        DISP_SEL:          DS 1 ; BIT 0: 0 = UNIDADES (RD4), 1 = DECENAS (RD5)
    ;===== BANDERAS DE CONTROL GENERAL ======
        FLAG_NUEVO_DATO:   DS 1 ; BIT 0: 1 CUANDO ADC TIENE DATO LISTO NUEVO     
    ;===== VARIABLES TEMPORALES PARA OPERACIONES ======
        MATH_TEMP:         DS 1 ; VARIABLE TEMPORAL PARA OPERACIONES MATEMÁTICAS
    
 ;===============================================
 ; VECTOR DE RESET
 ;===============================================
PSECT resetVec, class=CODE, reloc=2
 ORG 0x0000
 GOTO Inicio 
 
 ;===============================================
 ; VECTOR DE INTERRUPCIÓN 
 ;===============================================
PSECT intVec, class=CODE, reloc=2
 ORG  0x0008
 GOTO Rutina_ISR      ;SALTA A LA RUTINA DE SERVICIO DE INTERRUPCIÓN
 
 ;===============================================
 ; PROGRAMA PRINCIPAL
 ;===============================================
 PSECT main_code, class=CODE, reloc=2
 
Inicio:
    ; ============================================================
    ; SECCIÓN 1: CONFIGURAR EL OSCILADOR INTERNO A 8MHz
    ; ============================================================

    MOVLW 01110010B         ; ICR= 111 (8Mz), SCS = 10 (INTERNO)
    MOVWF OSCCON, a           ; ESCRIBE W EN OSCCON 
   
    ;NOTA: FRECUENCIA DE INSTRUCCIÓN = 8MHz / 4 = 2MHz (CADA INSTRUCIÓn = 5us)
    
    ; ============================================================
    ; SECCIÓN 2: INICIALIZACIÓN DE VARIABLE RAM 
    ; ============================================================

    CLRF    ESTADO_ALARMA , a          ;CESTADO_ALARMA = 0 (ALARMA APAGADA)
    CLRF    ESTADO_VENTILADOR, a       ;ESTADO_VENTILADOR = 0 (VENTILADOR APAGADO)
    CLRF    MODO_UNIDAD, a            ;CONTADOR_ADC = 0
    CLRF    CONTADOR_ADC, a         ; CONDOR_DEBOUNCE = 0
    CLRF    DISP_SEL, a                ; DISP_SEL = 0 (EMPEZAR CON UNIDADES
    CLRF    FLAG_NUEVO_DATO,a          ; FLAG_NUEVO_DATO = 0 (NO HAY DATO LISTO)
    
    ; ============================================================
    ; SECCIÓN 3: CONFIGURACIÓN DE PUERTOS E/S (TRIS = TRisate)
    ; ============================================================

    ;PUERTO D: SALIDAS (DISPLAYS Y SELECTORES)
    CLRF    TRISD, a         ; TRISTD = 0x00 - PORTD COMO SALIDA (SALIDA BCD Y MULTIPLEXADO)
    CLRF    LATD, a          ; INICIALIZADOR SALIDAS EN 0 (TODOS LOS PINES EN BAJO)
    ;DESCRIPCIÓN DE PORTD.
    ;RDO_RD3: DATOS BCD PARA DECODIFICADOR 7 SEGMENTOS
    ;RD4: SELECTOR DISPLAY 1 (UNIDADES - ACTIVO EN ALTO
    ;RD5; SELECTOR DISPLAY 2 (DECENAS) - ACTIVO EN ALTO 
    
    ;PUERTOS E: SALIDAS (ALARMA Y VENTILADOR)
    BCF     TRISE, 0, a      ; RE0 COMO SALIDA (LED ALARMA) 
    BCF     LATE, 0, a       ; RE0 = 0 (LED APAGADO INICIALMENTE)
    BCF     TRISE, 1, a      ; RE1 COMO SALIDA (CONTROL VENTILADOR
    BCF     LATE, 1, a       ; RE1 = 0 (VENTILADOR APAGADO INICIALMENTE)
    
    ;PUERTO A: ENTRADA ANALÓGICA (SENSOR LM35)
    BSF TRISA,0,a          ;A0 COMO ENTRADA (TRIS = 1)
    ; RA0 ES ENTRADA ANALÓGICA DEL ADC, NO SE INICIALIZA LAT
    
    ;PUERTO B: ENTRADAS DIGITALES (PULSADORES PARA INTERRUPCIONES)
    BSF   TRISB, 0,a         ; RB0 COMO ENTRADA (PULSADORES INT0 - ALARMA)
    BSF   TRISB, 1, a        ; RB1 COMO ENTRADA (PULSADORES INT1 - VENTILADOR)
    BSF   TRISB, 2,a         ; RB2 COMO ENTRADA (PULSADORES INT2 - °C/°F)
    ; RB0, RB1, RB2 PUEDEN TENER PULL-UPS INTERNOS 
    
    ; ============================================================
    ; SECCIÓN 4: CONFIGURAR MÓDULO ADC
    ; ============================================================
    ; Analógico-Digital Converter: Convierte voltaje analógico a valor digital
    ; Entrada: RA0 conectado a sensor LM35
    ; Rango: 0 a 5V ? 0 a 1023 (10 bits) (SEGÚN CLAUDE)
    
    ; Registro ADCON1: Configurar pines analógicos vs digitales
    ; PCFG3:PCFG0 = 1110 ? AN0 (RA0) es analógico, resto digital
    ; VCFG1:VCFG0 = 00 ? Vref+ = VDD (5V), Vref- = VSS (0V)
    ; Valor: 0x0E = 00001110B (SEGÚN CLAUDE)


    MOVLW 0x0E           ; CARGA 0x0E (14 DECIMAL) EN W
    MOVWF ADCON1, a         ; ADCON1 = 0x0E (AN0 ANALÓGICO)
    
    ; Registro ADCON2: Configurar tiempo de conversión
    ; ADFM = 1 (bit 7): Resultado justificado a la DERECHA
    ;   - ADRESH contiene bits 9:2 del resultado
    ;   - ADRESL contiene bits 1:0 (en los bits más altos)
    ;   - Esto permite leer 8 bits significativos desde ADRESH directamente
    ; ACQT = 001 (bits 5:3): Tiempo de adquisición = 2 TAD
    ; ADCS = 010 (bits 2:0): Frecuencia ADC = FOSC/32
    ;   - Fosc/32 = 8MHz / 32 = 250 kHz (dentro del rango 200-400 kHz recomendado)
    ; Valor: 10001010B = 0x8A (SEGÚN CLAUDE)
    
    MOVLW 10001010B          ; CARGA 10001010B EN W
    MOVWF ADCON2, a          ; ADCON2 = 10001010B
 
    ; CÁLCULO DE TIEMPO DE CONVERSIÓN:
    ; TIEMPO TOTAL = (TIEMPO DE ADQUISICIÓN) + (12 x TADC)
    ; = (2 x 4us) + (12 x 4us) = 8us + 48us = 56us
    ; Frecuencia 0 1/56us = 17.8KHz conversiones por segundo
    
    ; Registro ADCON0: Seleccionar canal y activar ADC
    ; CH3:CH0 = 0000 ? Canal 0 (AN0 = RA0)
    ; GODONE = 0 ? ADC no activo (se dispara desde ISR_TMR0)
    ; ADON = 1 ? ADC habilitado
    ; Valor: 00000001B (SEGÚN CLAUDE)
    
    MOVLW 00000001B      ; CARGA 00000001B EN W
    MOVWF ADCON0, a      ; ADCON0 = 00000001B

    ; ============================================================ 
    ;SECCIÓN 5: CONFIGURAR EL TIMER0
    ; ============================================================
      
    ; Timer0: Temporizador que genera interrupciones periódicas
    ; Funciones:
    ; 1. Multiplexar displays 7 segmentos (cada ~8 ms)
    ; 2. Espaciar lecturas del ADC (cada ~160 ms)
    
    ; *** CORRECCIÓN IMPORTANTE (v1.1) ***
    ; Valor ANTERIOR (INCORRECTO): 11010101B
    ; Valor CORRECTO: 11000101B
    ; La diferencia está en el bit 6 (T08BIT):
    ;   - 1 = Modo 8 bits ? Máximo conteo = 256
    ;   - 0 = Modo 16 bits ? Máximo conteo = 65,536 (CORRECTA para este sistema)
    ; (SEGÚN CLAUDE)
    
    MOVLW   11010101B
    MOVWF   T0CON, a
    
    ; ; Desglose de T0CON = 11000101B:
    ; Bit 7 (TMR0ON) = 1: Timer encendido
    ; Bit 6 (T08BIT) = 1 (ORIGINAL INCORRECTO): Modo 8 bits
    ; Bit 6 (T08BIT) = 0 (CORRECCIÓN): Modo 16 bits ? USAR ESTO
    ; Bit 5 (TOCS) = 0: Reloj interno (Fosc/4)
    ; Bit 4 (TOSE) = 0: Incrementa en flanco ascendente
    ; Bit 3 (PSA) = 1: Prescaler habilitado
    ; Bits 2:0 (PS) = 101: Prescaler 1:64
    
    ; Cálculo del período:
    ; Frecuencia de incremento = (Fosc/4) / Prescaler
    ;                          = (8 MHz / 4) / 64
    ;                          = 2 MHz / 64
    ;                          = 31.25 kHz
    ; Período máximo (65,536 cuentas) = 65,536 / 31.25 kHz = 2.097 segundos
    
    ; Para interrupciones cada ~8 ms (para multiplexado):
    ; Cuentas = 8 ms × 31.25 kHz = 250
    ; Precarga = 65,536 - 250 = 65,286 = 0xFF06 (SEGÚN CLAUDE)
    
    ;PRECARGAR TMR0 PARA EMPEZAR CON 8 ms
    MOVLW 0xFF          ; BYTE ALTO EEL TIMER0
    MOVWF TMR0H, a      ; TMR0H = 0xFF
    MOVLW 0x06          ;Byte bajo del TImer0
    MOVWF TMR0L, a      ; TMR0L = 0x06
    ;AHORA MR0 = 0xFF06, DESBORDARÁ DESPUES DE 250 CUENTAS

    ; ============================================================
    ; SECCIÓN 6; CONFIGURACIÓN DE INTERRUPCIONES
    ; ============================================================

    ;REGISTRO INTCON2: CONFIGURAR INTERRUPCIONES EXTERNAS 
    BCF INTCON2, 7, a    ; RBPU = 0: Habilita pull-ups internos de PORTB
                         ; NECESARIO SI LOS PULSOS VAN A GND CON PULL-DOWN
    
    ;ESCOGE FLANCO DE SIPARO PARA LAS INTERRUPCIONES EXTERNAS
    BSF INTCON2, 6, a    ; INTEDG0 = 1 POR FLANCO ASCENDENTES (0-1)
    BSF INTCON2, 5, a
    BSF INTCON2, 4, a
    
    ; CONSULTAR PULSADORES POR SI VAN A VDD (PULSADORES A NIVEL ALTO)
    ; USAR EL FLANCO ASCENDENTE ()
    ; SI VAN A GND (PULSADORES A NIVEL BAJO
    ; CAMBIAR A FLACO DE BAJADA O DESCENDENTE (0) Y REVISAR LOS PULL-UPS
    
    ; LIMPIAR BANDERAS DE ITERRUPCIÓN ANTES DE HABILITARLAS
    ; LIMPIAR PARA EVITAR FALSAS INTERRUPCIONES 
    BCF  INTCON, 1, a     ; INT0IF = 0 (BANDERA DE INT0)
    BCF  INTCON3, 0, a    ; INT1IF = 0 (BANDERA DE INT1)
    BCF  INTCON3, 1, a    ; INT2IF = 0 (BANDERA DE INT0)
    BCF  INTCON, 2, a     ; TMR0IF = 0 (BANDERA DE TIMER0)
    BCF  PIR1, 6, a       ; AD0IF = 0 (BANDERA DE ADC TERMINADO)
    
    ;HABIITAR INTERRUPCIONES INDIVIDUALES
    BSF  INTCON,4, a    ; INT0IF = 1 (HABILITAR INT0)
    BCF  INTCON3, 3, a  ; INT1IF = 1 (HABILITAR INT1)
    BSF  INTCON3, 4, a  ; INT2IF = 1 (HABILITAR INT0)
    BSF  INTCON,2, a    ; TMR0IF = 1 (HABILITAR TIMER0)
    BSF  PIE1, 6, a     ; AD0IF = 1  (HABILITAR ADC)
    
    ;HABILITAR INTERRUPCIONES GLOBALES
    BSF  INTCON, 6, a   ; PEIE = 1 (PERIPHERAL INTERRUP ENABLE)
    ;                   PERMITE QUE LOS PERIFÉRICOS CAUSEN INTERRUPCIONES
    BSF  INTCON, 7, a   ; GIE = 1 (GLOBAL INTERRUPT ENABLE)
    ;                   PERMITE QUE CUALQUIER INTERRUPCIÓN EJECUTE
    
;===============================================
; BUCLE PRINCIPAL
;===============================================
; SE ESPERA QUE EN ESTE PROGRAMA PRICIPAL EL ADC ENTREGUE DATOS
; IENTRAS ESPERA, LAS INTERRUPCIONES OCURREN INDEPENDIENTEMENTE, ES DECIR, EN PARALELO
    
Loop_Principal:
        ; WAIT: ESPERAR A QUE EL ADC HAYA TOMADO UNA NUEVA LECTURA
        ; FLAG_NUEVO_DATO SE PONE A 1 EN ISR_ADX CUANDO LA CONVERSIÓN TERMINA
    
     BTFSS FLAG_NUEVO_DATO, 0, a ;FLAG_NUEVO_DATO BIT 0 =1?
     GOTO Loop_Principal          ; SI NO (ESTA EN 0), VUELVE A PREGUNTAR
                                  ; ESTO CREA UN BUCLE QUE ESPERA EL DATO
    BCF FLAG_NUEVO_DATO, 0, a     ;SI SE CUMPLE, SE LIMPIA LA BANDERA PARA LA SIGUIENTE LECTURA
    
    ; ============================================================
    ; SECCIÓN 1: CONVERTIR VALOR ADC A TEMPERATURA EN CELSIUS
    ; ============================================================
     
     ; Fórmula simplificada:
    ; El LM35 entrega 10 mV por °Celsius
    ; ADC de 10 bits con Vref = 5V:
    ;   1 LSB = 5V / 1024 ? 4.88 mV
    ;   Temp(°C) ? (Valor ADC × 5) / (1024 × 0.01) = Valor ADC / 2
    ;
    ; Aproximación usada aquí: Divides por 2 (desplazamiento a la derecha)
    
    ; Instrucción RRCF: Rotate Right through Carry
    ; Efecto: Divide el número por 2 (SEGÚN CLAUDE)
 
    BCF STATUS, 0, a 
    
    Rutina_ISR: