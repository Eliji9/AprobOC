"! <p class="shorttext synchronized">Aprob. automática OC: Application Job</p>
"! Clase de ejecución del Application Job. Solo dispara el motor.
"! Se programa con el usuario ZJOBPROCESOS (perfil de administrador de workflow).
"! Prueba sin job: en ADT, abrir la clase y ejecutar con F9 (Run as ABAP Application
"! (Console)). Por defecto corre en modo prueba (no aprueba): ver gc_console_test_mode.
"! Para probar una sola OC, indicarla en gc_console_po.
CLASS zcl_mm_po_aut_job DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES if_apj_dt_exec_object.
    INTERFACES if_apj_rt_exec_object.
    INTERFACES if_oo_adt_classrun.

  PRIVATE SECTION.
    CONSTANTS gc_param_po   TYPE c LENGTH 8 VALUE 'S_EBELN'.

    "! Ejecución desde consola (F9): abap_true = solo evalúa; abap_false = aprueba.
    "! OJO: en modo real aprueba con el usuario que ejecuta, no con ZJOBPROCESOS.
    CONSTANTS gc_console_test_mode TYPE abap_bool VALUE abap_true.

    "! Ejecución desde consola (F9): OC a probar. Vacío = todas las OC en aprobación.
    CONSTANTS gc_console_po TYPE i_purchaseorderapi01-purchaseorder VALUE ''.

ENDCLASS.



CLASS zcl_mm_po_aut_job IMPLEMENTATION.

  METHOD if_apj_dt_exec_object~get_parameters.

    " Una o varias OC (valores individuales o intervalos). Vacío = todas.
    et_parameter_def = VALUE #(
      ( selname        = gc_param_po
        kind           = if_apj_dt_exec_object=>select_option
        datatype       = 'C'
        length         = 10
        param_text     = 'Orden de compra (vacío = todas)'
        changeable_ind = abap_true ) ).

  ENDMETHOD.


  METHOD if_apj_rt_exec_object~execute.

    DATA lt_po_range TYPE zif_mm_po_aut_engine=>tt_po_range.

    LOOP AT it_parameters INTO DATA(ls_param) WHERE selname = gc_param_po.
      APPEND VALUE #( sign   = ls_param-sign
                      option = ls_param-option
                      low    = |{ ls_param-low ALPHA = IN WIDTH = 10 }|
                      high   = COND #( WHEN ls_param-high IS NOT INITIAL
                                       THEN |{ ls_param-high ALPHA = IN WIDTH = 10 }| ) )
             TO lt_po_range.
    ENDLOOP.

    DATA(lo_engine) = CAST zif_mm_po_aut_engine( NEW zcl_mm_po_aut_engine( ) ).

    " El job siempre aprueba. El modo prueba solo existe en la consola (F9).
    lo_engine->process_pending( iv_test_mode       = abap_false
                                it_purchase_orders = lt_po_range ).

  ENDMETHOD.


  METHOD if_oo_adt_classrun~main.

    DATA lt_po_range TYPE zif_mm_po_aut_engine=>tt_po_range.

    IF gc_console_po IS NOT INITIAL.
      lt_po_range = VALUE #( ( sign = 'I' option = 'EQ'
                               low  = |{ gc_console_po ALPHA = IN WIDTH = 10 }| ) ).
    ENDIF.

    DATA(lo_engine) = CAST zif_mm_po_aut_engine( NEW zcl_mm_po_aut_engine( ) ).

    out->write( |Aprobación automática de OC – { COND string( WHEN gc_console_test_mode = abap_true
                                                               THEN `MODO PRUEBA (no aprueba)`
                                                               ELSE `MODO REAL (aprueba)` ) }| ).
    out->write( |Usuario: { cl_abap_context_info=>get_user_technical_name( ) }| ).
    out->write( |OC: { COND string( WHEN gc_console_po IS INITIAL THEN `todas` ELSE CONV string( gc_console_po ) ) }| ).

    DATA(lt_result) = lo_engine->process_pending( iv_test_mode       = gc_console_test_mode
                                                  it_purchase_orders = lt_po_range ).

    IF lt_result IS INITIAL.
      out->write( COND string(
        WHEN gc_console_po IS INITIAL
        THEN `No hay OC en aprobación para los grupos de compras parametrizados.`
        ELSE |La OC { gc_console_po } no está en aprobación o su grupo de compras no tiene rango activo.| ) ).
      RETURN.
    ENDIF.

    " Estados: AP aprobada · TS cumple (modo prueba) · OR fuera de rango · NR sin rango
    "          NT sin tarea · FF no se pudo reenviar · ER error
    out->write( lt_result ).

  ENDMETHOD.

ENDCLASS.
