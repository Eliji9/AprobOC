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

    "! Objeto / subobjeto del Application Log (crear en ADT: New > Application Log Object)
    CONSTANTS gc_log_object    TYPE c LENGTH 20 VALUE 'ZMM_PO_AUT'.
    CONSTANTS gc_log_subobject TYPE c LENGTH 20 VALUE 'APROB'.

    "! Registra en el log del Application Job una línea por OC procesada
    METHODS write_log
      IMPORTING it_result   TYPE zif_mm_po_aut_engine=>tt_result
                it_po_range TYPE zif_mm_po_aut_engine=>tt_po_range.

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
    DATA(lt_result) = lo_engine->process_pending( iv_test_mode       = abap_false
                                                  it_purchase_orders = lt_po_range ).

    write_log( it_result   = lt_result
               it_po_range = lt_po_range ).

  ENDMETHOD.


  METHOD write_log.

    TRY.
        DATA(lo_log) = cl_bali_log=>create_with_header(
          cl_bali_header_setter=>create( object      = gc_log_object
                                         subobject   = gc_log_subobject
                                         external_id = |Aprob. automática OC| ) ).

        " Cabecera: usuario y filtro, para saber con qué se ejecutó
        lo_log->add_item( cl_bali_free_text_setter=>create(
          severity = if_bali_constants=>c_severity_information
          text     = |Usuario { cl_abap_context_info=>get_user_technical_name( ) } · | &&
                     |OC: { COND string( WHEN it_po_range IS INITIAL THEN `todas`
                                         ELSE |{ lines( it_po_range ) } filtro(s)| ) } · | &&
                     |OC encontradas: { lines( it_result ) }| ) ).

        IF it_result IS INITIAL.
          lo_log->add_item( cl_bali_free_text_setter=>create(
            severity = if_bali_constants=>c_severity_warning
            text     = `Ninguna OC en aprobación visible para el usuario en grupos con rango activo` ) ).
        ENDIF.

        " Una línea por OC: estado AP = éxito; OR/PH = aviso; NT/FF/ER = error
        LOOP AT it_result INTO DATA(ls_res).
          DATA(lv_severity) = SWITCH #( ls_res-status
            WHEN zif_mm_po_aut_engine=>gc_status-approved      THEN if_bali_constants=>c_severity_status
            WHEN zif_mm_po_aut_engine=>gc_status-out_of_range
              OR zif_mm_po_aut_engine=>gc_status-has_hierarchy
              OR zif_mm_po_aut_engine=>gc_status-no_rule       THEN if_bali_constants=>c_severity_warning
            ELSE if_bali_constants=>c_severity_error ).

          lo_log->add_item( cl_bali_free_text_setter=>create(
            severity = lv_severity
            text     = CONV #( |OC { ls_res-purchase_order } · { ls_res-purchasing_group } · | &&
                               |{ ls_res-total_amount DECIMALS = 2 } { ls_res-currency } · | &&
                               |WI { ls_res-workitem_id ALPHA = OUT } niv. { ls_res-approval_level } · | &&
                               |{ ls_res-status } { ls_res-message }| ) ) ).
        ENDLOOP.

        cl_bali_log_db=>get_instance( )->save_log( log                        = lo_log
                                                   assign_to_current_appl_job = abap_true ).

      CATCH cx_bali_runtime.
        " El log no debe detener el job
    ENDTRY.

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
    "          PH material con jerarquía · NT sin tarea · FF no se pudo reenviar · ER error
    out->write( lt_result ).

  ENDMETHOD.

ENDCLASS.
