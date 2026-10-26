"! <p class="shorttext synchronized">Aprob. automática OC: Application Job</p>
"! Clase de ejecución del Application Job. Solo dispara el motor.
"! Se programa con el usuario ZJOBPROCESOS (perfil de administrador de workflow).
CLASS zcl_mm_po_aut_job DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES if_apj_dt_exec_object.
    INTERFACES if_apj_rt_exec_object.

  PRIVATE SECTION.
    CONSTANTS gc_param_test TYPE c LENGTH 8 VALUE 'P_TEST'.

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

ENDCLASS.
