"! <p class="shorttext synchronized">Aprob. automática OC: decisión de workflow (Tier 2)</p>
"! Wrapper Tier 2 (paquete con versión de lenguaje Standard ABAP).
"! Encapsula los objetos no liberados del Flexible Workflow:
"!   - Tablas SWWWIHEAD / SWW_WI2OBJ (búsqueda de la tarea y del nivel)
"!   - SAP_WAPI_FORWARD_WORKITEM (reenvío al usuario del job)
"!   - /IWWRK/WF_TGW_TASK_DET_ACTION (decisión, misma lógica que My Inbox)
"! Validado en DS4 (PoC 15-10-2026): IV_ACTION_NAME = 'Decision', clave '0001'.
"! Liberar la clase y la interfaz con contrato C1.
CLASS zcl_mm_wf_decision DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES zif_mm_wf_decision.

  PRIVATE SECTION.
    CONSTANTS gc_task          TYPE swwwihead-wi_rh_task VALUE 'TS00800531'.
    CONSTANTS gc_action        TYPE string               VALUE `Decision`.
    CONSTANTS gc_decision_key  TYPE swr_decikey          VALUE '0001'.
    CONSTANTS gc_po_catid      TYPE sww_wi2obj-catid     VALUE 'CL'.
    CONSTANTS gc_po_typeid     TYPE sww_wi2obj-typeid    VALUE 'CL_MM_PUR_WF_OBJECT_PO'.

    METHODS forward
      IMPORTING iv_workitem_id   TYPE sww_wiid
                iv_user          TYPE syuname
      EXPORTING ev_return_code   TYPE sysubrc
                ev_message       TYPE string.

ENDCLASS.



CLASS zcl_mm_wf_decision IMPLEMENTATION.

  METHOD zif_mm_wf_decision~get_open_tasks.

    DATA lr_instid TYPE RANGE OF sww_wi2obj-instid.

    IF it_purchase_orders IS INITIAL.
      RETURN.
    ENDIF.

    lr_instid = VALUE #( FOR lv_po IN it_purchase_orders
                         ( sign = 'I' option = 'EQ' low = lv_po ) ).

    " Tareas TS00800531 abiertas y su OC. Validado en DS4 (SWW_WI2OBJ, WI 47037):
    " CATID = 'CL', TYPEID = 'CL_MM_PUR_WF_OBJECT_PO', INSTID = número de OC.
    " El filtro por tipo excluye los objetos de anexos (BO / SOFM).
    SELECT DISTINCT h~wi_id, h~top_wi_id, o~instid
      FROM swwwihead AS h
      INNER JOIN sww_wi2obj AS o ON o~wi_id = h~wi_id
      WHERE h~wi_rh_task = @gc_task
        AND h~wi_stat    IN ( 'READY', 'SELECTED', 'STARTED' )
        AND o~catid      = @gc_po_catid
        AND o~typeid     = @gc_po_typeid
        AND o~instid     IN @lr_instid
        AND o~removed    = @space
      INTO TABLE @DATA(lt_open).

    IF lt_open IS INITIAL.
      RETURN.
    ENDIF.

    " Nivel = tareas de aprobación ya completadas en la misma instancia + 1
    DATA lr_top TYPE RANGE OF swwwihead-top_wi_id.
    lr_top = VALUE #( FOR ls_o IN lt_open ( sign = 'I' option = 'EQ' low = ls_o-top_wi_id ) ).
    SORT lr_top BY low.
    DELETE ADJACENT DUPLICATES FROM lr_top COMPARING low.

    SELECT top_wi_id, COUNT(*) AS done
      FROM swwwihead
      WHERE top_wi_id  IN @lr_top
        AND wi_rh_task = @gc_task
        AND wi_stat    = 'COMPLETED'
      GROUP BY top_wi_id
      INTO TABLE @DATA(lt_done).

    LOOP AT lt_open INTO DATA(ls_open).
      DATA(lv_done) = VALUE #( lt_done[ top_wi_id = ls_open-top_wi_id ]-done OPTIONAL ).
      APPEND VALUE #( workitem_id    = ls_open-wi_id
                      purchase_order = ls_open-instid(10)
                      approval_level = lv_done + 1 ) TO rt_tasks.
    ENDLOOP.

  ENDMETHOD.


  METHOD zif_mm_wf_decision~approve.

    DATA lv_wi_id      TYPE sww_wiid.
    DATA lv_error      TYPE /iwwrk/wf_flag.
    DATA lt_return     TYPE bapirettab.
    DATA lv_forwarded  TYPE abap_bool.

    lv_wi_id = iv_workitem_id.

    SELECT SINGLE wi_stat, wi_aagent
      FROM swwwihead
      WHERE wi_id = @lv_wi_id
      INTO @DATA(ls_wi).

    IF sy-subrc <> 0
       OR ( ls_wi-wi_stat <> 'READY' AND ls_wi-wi_stat <> 'SELECTED' AND ls_wi-wi_stat <> 'STARTED' ).
      rs_result = VALUE #( result  = zif_mm_wf_decision=>gc_result-error
                           message = |Work item { lv_wi_id ALPHA = OUT } no está pendiente| ).
      RETURN.
    ENDIF.

    " 1. Reenviar al usuario del job si todavía no es el agente.
    "    Falla (RC 2) si el usuario está excluido, p. ej. si es el creador de la OC.
    IF ls_wi-wi_aagent <> sy-uname.
      forward( EXPORTING iv_workitem_id = lv_wi_id
                         iv_user        = sy-uname
               IMPORTING ev_return_code = DATA(lv_rc)
                         ev_message     = DATA(lv_fwd_msg) ).
      IF lv_rc <> 0.
        rs_result = VALUE #( result  = zif_mm_wf_decision=>gc_result-forward_failed
                             message = lv_fwd_msg ).
        RETURN.
      ENDIF.
      lv_forwarded = abap_true.
    ENDIF.

    " 2. Decisión "Autorizar" con la misma función que usa My Inbox
    CALL FUNCTION '/IWWRK/WF_TGW_TASK_DET_ACTION'
      EXPORTING
        iv_instance_id    = lv_wi_id
        iv_action_name    = gc_action
        iv_decision_key   = gc_decision_key
        iv_forward_usr_id = space
        iv_language       = sy-langu
        iv_comments       = iv_comment
      IMPORTING
        ev_error_flag     = lv_error
        et_return         = lt_return.

    IF lv_error IS INITIAL.
      COMMIT WORK AND WAIT.
      rs_result = VALUE #( result = zif_mm_wf_decision=>gc_result-approved ).
      RETURN.
    ENDIF.

    ROLLBACK WORK.
    rs_result = VALUE #( result  = zif_mm_wf_decision=>gc_result-error
                         message = VALUE #( lt_return[ type = 'E' ]-message
                                            DEFAULT VALUE #( lt_return[ 1 ]-message OPTIONAL ) ) ).

    " 3. Si se reenvió y la aprobación falló, devolver la tarea al agente original.
    "    Si la tarea no tenía agente (estaba en el pool de aprobadores), queda
    "    a nombre del usuario del job: se informa para revisión manual.
    IF lv_forwarded = abap_true.
      IF ls_wi-wi_aagent IS NOT INITIAL.
        forward( EXPORTING iv_workitem_id = lv_wi_id
                           iv_user        = ls_wi-wi_aagent
                 IMPORTING ev_return_code = lv_rc ).
      ELSE.
        rs_result-message = |{ rs_result-message } (tarea quedó a nombre de { sy-uname }: revisar)|.
      ENDIF.
    ENDIF.

  ENDMETHOD.


  METHOD forward.

    DATA lt_msg    TYPE STANDARD TABLE OF swr_messag.
    DATA lt_mstruc TYPE STANDARD TABLE OF swr_mstruc.

    CALL FUNCTION 'SAP_WAPI_FORWARD_WORKITEM'
      EXPORTING
        workitem_id    = iv_workitem_id
        user_id        = iv_user
        language       = sy-langu
        do_commit      = abap_true
      IMPORTING
        return_code    = ev_return_code
      TABLES
        message_lines  = lt_msg
        message_struct = lt_mstruc.

    ev_message = VALUE #( lt_msg[ 1 ]-line OPTIONAL ).

  ENDMETHOD.

ENDCLASS.
