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
    ;====== PATRON PARA LOS DISPLAYS =======
        PATRON_DEC:        DS 1 ; LEDS DE LAS DECENAS DECODIFICADOS
        PATRON_UNID:       DS 1 ; LEDS DE LAS UNIDADES DECODIFICADOS
    ;===== BANDERAS DE CONTROL GENERAL ======
        FLAG_LEER_ADC:     DS 1 ; BIT 0: 1 CUANDO ADC TIENE DATO LISTO NUEVO     
    ;===== VARIABLES TEMPORALES PARA OPERACIONES ======
        MATH_TEMP:         DS 1 ; VARIABLE TEMPORAL PARA OPERACIONES MATEMÁTICAS
    ;===== DELAYS PARA LOS DISPLAYS =======
        DELAY1:            DS 1 ;VARIABLE PARA EL MICRO RETARDO DEL DISPLAY
        DELAY2:            DS 1;V ARIABLE PARA EL MICRO RETARDO DEL DISPLAY
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
 GOTO Rutina_ISR      ;SALTA A LAS INTERRUPCIONES
 
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
    CLRF    MODO_UNIDAD, a             ;CONTADOR_ADC = 0
    CLRF    FLAG_LEER_ADC,a            ; FLAG_LEER_ADC = 0 
    CLRF    PATRON_DEC, a              ; PATRON_DEC = 0 
    CLRF    PATRON_UNID, a             ; PATRON_UNID = 0
   
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
    
    ; PUERTO C: SALIDAS DE HABILITADORES DISPLAY
    BCF     TRISC, 0, a          ; RC0 (PIN 15) SALIDA DE TRANSISTOR DECENAAS
    BCF     TRISC, 1, a          ; RC1 (PIN 16 SALIDA PARA TRANSISTOR UNIDADES
    BCF     LATC, 1, a
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
   


    MOVLW 0x0E           ; CARGA 0x0E (14 DECIMAL) EN W
    MOVWF ADCON1, a         ; ADCON1 = 0x0E (AN0 ANALÓGICO)
    
    
    MOVLW 10100010B          ; CARGA 10100010B EN W
    MOVWF ADCON2, a          ; ADCON2 = 10100010B
 

    MOVLW 00000001B      ; CARGA 00000001B EN W
    MOVWF ADCON0, a      ; ADCON0 = 00000001B

    ; ============================================================ 
    ;SECCIÓN 5: CONFIGURAR EL TIMER0
    ; ============================================================
      
    MOVLW 10000101B      
    MOVWF T0CON,a 

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
 
    
    ;HABIITAR INTERRUPCIONES INDIVIDUALES
    BSF  INTCON,4, a    ; INT0IF = 1 (HABILITAR INT0)
    BCF  INTCON3, 3, a  ; INT1IF = 1 (HABILITAR INT1)
    BSF  INTCON3, 4, a  ; INT2IF = 1 (HABILITAR INT0)
    BSF  INTCON,2, a    ; TMR0IF = 1 (HABILITAR TIMER0)
 
    
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
    ;===== MULTIPLEXADO RAPIDO EN EL BUCLE ======
    ; APAGAR LOS DISPLAYS
    
    BCF    LATC, 0, a
    BCF    LATC, 1, a
    
    ;ENCENDER UNIDADES
    MOVFF  PATRON_UNID, LATD     ;CARGAR LOS LED DE UNIDADES
    BSF    LATC, 1, a            ; ACTIVAR TRANSISTOR UNIDADES
    CALL   RETARDO_MUX           ; ESPERAR UNOS MILESEGUNDOS
    BCF    LATC, 1, a            ; APAGAR UNIDADES
    
    ; ENCENDER DECENAS
    MOVFF  PATRON_DEC, LATD      ;CARGAR LOS LED DE DECENAS
    BSF    LATC, 0, a            ; ACTIVAR TRANSISTOR DECENAS
    CALL   RETARDO_MUX           ; ESPERAR UNOS MILESEGUNDOS
    BCF    LATC, 0, a            ; APAGAR UNIDADES
    
    ;==== FIN DEL MULTIPLEXADO =======
    
    ;REVISAR SI EL TIMER0 DIO LA ORDEN AL SENSOR
    BTFSS FLAG_LEER_ADC, 0, a
    GOTO Loop_Principal         ; SI NO HAY ORDEN SEGUIR MULTPLLEXADO
    
   
    ; INICIAR CONVERSION ADC
    BSF  ADCON0, 1, a
Esperar_ADC:
    BTFSC  ADCON0, 1, a
    GOTO   Esperar_ADC
    
    MOVFF   ADRESL, VALOR_ADC_L
    MOVFF   ADRESH, VALOR_ADC_H
    
    ; CONVERTIR A CELSIUS 
    BCF     STATUS, 0, a
    RRCF    VALOR_ADC_H, F, a
    RRCF    VALOR_ADC_L, W, a
    MOVWF   TEMP_CELSIUS, a
    
Seleccionar_Celsius:
    MOVF    TEMP_CELSIUS, W, a
    MOVWF   TEMP_MOSTRAR, a
    GOTO    DESCOMPONER_BCD
    
Calcular_Fahrenheit:
    MOVF    TEMP_CELSIUS, W, a
    MULLW   9
    MOVFF   PRODL, MATH_TEMP
    MOVFF   PRODH, VALOR_ADC_H
    CLRF    TEMP_FAHRENHEIT, a
    
RESTAR_5:
    MOVLW   5 
    SUBWF   MATH_TEMP, F, a
    MOVLW   0
    SUBWF   VALOR_ADC_H, F, a
    BNC     FIN_DIV5
    INCF    TEMP_FAHRENHEIT, F, a
    GOTO    RESTAR_5
    
FIN_DIV5:
    MOVLW   32
    ADDWF   TEMP_FAHRENHEIT, W, a
    MOVWF   TEMP_MOSTRAR, a
    
DESCOMPONER_BCD:
    ;SEPARAR DECENAS Y UNIDADES 
    MOVF    TEMP_MOSTRAR, W, a
    CLRF    DIGITO_DEC, a
BUCLE_RESTAR_10:
    MOVLW   10
    SUBWF   TEMP_MOSTRAR, W, a
    BNC     FIN_BCD
    MOVWF   TEMP_MOSTRAR, a
    INCF    DIGITO_DEC, F, a
    GOTO    BUCLE_RESTAR_10
    
FIN_BCD:
    MOVF    TEMP_MOSTRAR, W , a 
    MOVWF   DIGITO_UNID, a
    
    ; TRADUCIR A NÚMEROS
    MOVFF   DIGITO_UNID, MATH_TEMP
    CALL    DECODIFICADOR_7SEG
    MOVWF   PATRON_DEC, a
    
    GOTO    Loop_Principal
    
    ;FALTA AÑADIR LOS COMETARIOS A TODO ESTO
    
;===============================================
; SUBRUTINA DE MICRO RETARDO PARA EL MULTIPLEXADO
;===============================================
   
RETARDO_MUX:
    MOVLW   2.4901
    MOVWF   DELAY1, a
LOOP_M1:
    MOVLW   166
    MOVWF   DELAY2, a
LOOP_M2:
    DECFSZ  DELAY2, F, c
    GOTO    LOOP_M2
    DECFSZ  DELAY1, F, c
    GOTO    LOOP_M1
    RETURN

;================================================
; RUTINA DE INTERRUPCIONES
;================================================

Rutina_ISR:
    BTFSC   INTCON, 1, a
    GOTO    ISR_INT0
    BTFSC   INTCON3, 0, a
    GOTO    ISR_INT1
    BTFSC   INTCON3, 1, a
    GOTO    ISR_INT2
    BTFSC   INTCON, 2, a
    GOTO    ISR_TMR0
    RETFIE  1
    
ISR_INT0:
    BCF     INTCON, 1, a
    BTG     ESTADO_ALARMA, 0 , a
    BTG     LATE, 0 , a
    RETFIE  1
ISR_INT1:
    BCF     INTCON3, 0, a
    BTG     ESTADO_VENTILADOR, 0 , a
    BTG     LATE, 1 , a
    RETFIE  1
ISR_INT2:
    BCF     INTCON3, 1, a
    BTG     MODO_UNIDAD, 0 , a
    RETFIE  1    
ISR_TMR0:
    ; EL TIMER0 AVISA QUE ES HORA DE LEER EL SENSOR 
    BCF     INTCON, 2, a
    BTG     FLAG_LEER_ADC, 0 , a
    RETFIE  1   

;===============================================
; DECODIFICADOR 7 SEGMENTOS
;===============================================
DECODIFICADOR_7SEG:
    MOVLW   0
    SUBWF   MATH_TEMP, W, a
    BTFSC   STATUS, 2, a
    RETLW   00111111B
    
    MOVLW   1
    SUBWF   MATH_TEMP, W, a
    BTFSC   STATUS, 2, a
    RETLW   00000110B
    
    MOVLW   2
    SUBWF   MATH_TEMP, W, a
    BTFSC   STATUS, 2, a
    RETLW   01011011B
  
    MOVLW   3
    SUBWF   MATH_TEMP, W, a
    BTFSC   STATUS, 2, a
    RETLW   01001111B
  
    MOVLW   4
    SUBWF   MATH_TEMP, W, a
    BTFSC   STATUS, 2, a
    RETLW   01100110B
  
    MOVLW   5
    SUBWF   MATH_TEMP, W, a
    BTFSC   STATUS, 2, a
    RETLW   01101101B
  
    MOVLW   6
    SUBWF   MATH_TEMP, W, a
    BTFSC   STATUS, 2, a
    RETLW   01111101B
    
    MOVLW   7
    SUBWF   MATH_TEMP, W, a
    BTFSC   STATUS, 2, a
    RETLW   00000111B
  
    MOVLW   8
    SUBWF   MATH_TEMP, W, a
    BTFSC   STATUS, 2, a
    RETLW   01111111B
  
    MOVLW   9
    SUBWF   MATH_TEMP, W, a
    BTFSC   STATUS, 2, a
    RETLW   01101111B
  
    RETLW   00000000B
    
    END
  
  
  
  
  
   
    
    
    
 

    
   
    
  