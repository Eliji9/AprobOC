"! <p class="shorttext synchronized">Aprob. automática OC: Application Job</p>
"! Clase de ejecución del Application Job. Solo dispara el motor.
"! Se programa con el usuario ZJOBPROCESOS (perfil de administrador de workflow).
"! Prueba sin job: en ADT, abrir la clase y ejecutar con F9 (Run as ABAP Application
"! (Console)). Por defecto corre en modo prueba (no aprueba): ver gc_console_test_mode.
CLASS zcl_mm_po_aut_job DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES if_apj_dt_exec_object.
    INTERFACES if_apj_rt_exec_object.
    INTERFACES if_oo_adt_classrun.

  PRIVATE SECTION.
    CONSTANTS gc_param_test TYPE c LENGTH 8 VALUE 'P_TEST'.
    "! Ejecución desde consola (F9): abap_true = solo evalúa; abap_false = aprueba.
    "! OJO: en modo real aprueba con el usuario que ejecuta, no con ZJOBPROCESOS.
    CONSTANTS gc_console_test_mode TYPE abap_bool VALUE abap_true.

ENDCLASS.



CLASS zcl_mm_po_aut_job IMPLEMENTATION.

  METHOD if_apj_dt_exec_object~get_parameters.

    et_parameter_def = VALUE #(
      ( selname        = gc_param_test
        kind           = if_apj_dt_exec_object=>parameter
        datatype       = 'C'
        length         = 1
        param_text     = 'Modo prueba (no aprueba)'
        checkbox_ind   = abap_true
        changeable_ind = abap_true ) ).

    et_parameter_val = VALUE #(
      ( selname = gc_param_test
        kind    = if_apj_dt_exec_object=>parameter
        sign    = 'I'
        option  = 'EQ'
        low     = abap_false ) ).

  ENDMETHOD.


  METHOD if_apj_rt_exec_object~execute.

    DATA(lv_test_mode) = CONV abap_bool(
      VALUE #( it_parameters[ selname = gc_param_test ]-low OPTIONAL ) ).

    DATA(lo_engine) = CAST zif_mm_po_aut_engine( NEW zcl_mm_po_aut_engine( ) ).

    lo_engine->process_pending( iv_test_mode = lv_test_mode ).

  ENDMETHOD.


  METHOD if_oo_adt_classrun~main.

    DATA(lo_engine) = CAST zif_mm_po_aut_engine( NEW zcl_mm_po_aut_engine( ) ).

    out->write( |Aprobación automática de OC – { COND string( WHEN gc_console_test_mode = abap_true
                                                               THEN `MODO PRUEBA (no aprueba)`
                                                               ELSE `MODO REAL (aprueba)` ) }| ).
    out->write( |Usuario: { cl_abap_context_info=>get_user_technical_name( ) }| ).

    DATA(lt_result) = lo_engine->process_pending( iv_test_mode = gc_console_test_mode ).

    IF lt_result IS INITIAL.
      out->write( `No hay OC en aprobación para los grupos de compras parametrizados.` ).
      RETURN.
    ENDIF.

    " Estados: AP aprobada · TS cumple (modo prueba) · OR fuera de rango · NR sin rango
    "          NT sin tarea · FF no se pudo reenviar · ER error
    out->write( lt_result ).

  ENDMETHOD.

ENDCLASS.
