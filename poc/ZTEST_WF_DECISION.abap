*&---------------------------------------------------------------------*
*& Report ZTEST_WF_DECISION
*&---------------------------------------------------------------------*
*& Prueba de concepto: aprobar por programa una tarea de Flexible
*& Workflow de OC (TS00800531).
*&
*& SOLO PARA DS4. Programa desechable en Standard ABAP (SE38).
*& No transportar: es para validar el mecanismo del wrapper Tier 2.
*&
*& Modos:
*&   1. Leer     -> estado del work item y opciones de decisión
*&   2. Reenviar -> reenvía el work item al usuario que ejecuta
*&                  (si no es agente de la tarea)
*&   3. Aprobar  -> ejecuta la decisión con la clave indicada
*&---------------------------------------------------------------------*
REPORT ztest_wf_decision.

PARAMETERS: p_wi     TYPE sww_wiid OBLIGATORY,
            p_key(4) TYPE n DEFAULT '0001'.

SELECTION-SCREEN SKIP.
PARAMETERS: r_read RADIOBUTTON GROUP mode DEFAULT 'X',
            r_fwd  RADIOBUTTON GROUP mode,
            r_appr RADIOBUTTON GROUP mode.

DATA: gv_rc      TYPE sy-subrc,
      gs_status  TYPE swr_wistat,
      gt_msg     TYPE STANDARD TABLE OF swr_messag,
      gt_mstruc  TYPE STANDARD TABLE OF swr_mstruc,
      gt_alts    TYPE STANDARD TABLE OF swr_decialts.

START-OF-SELECTION.

  " Estado actual del work item
  SELECT SINGLE wi_id, wi_stat, wi_rh_task, wi_text
    FROM swwwihead
    WHERE wi_id = @p_wi
    INTO @DATA(gs_wi).

  IF sy-subrc <> 0.
    WRITE: / 'Work item no encontrado:', p_wi.
    RETURN.
  ENDIF.

  WRITE: / 'Work item :', gs_wi-wi_id,
         / 'Tarea     :', gs_wi-wi_rh_task,
         / 'Estado    :', gs_wi-wi_stat,
         / 'Texto     :', gs_wi-wi_text,
         / 'Usuario   :', sy-uname.
  ULINE.

  CASE abap_true.

    WHEN r_read.
      CALL FUNCTION 'SAP_WAPI_DECISION_READ'
        EXPORTING
          workitem_id    = p_wi
          language       = sy-langu
          user           = sy-uname
        IMPORTING
          return_code    = gv_rc
        TABLES
          alternatives   = gt_alts
          message_lines  = gt_msg
          message_struct = gt_mstruc.

      WRITE: / 'Lectura de decisiones. Return code:', gv_rc.
      LOOP AT gt_alts INTO DATA(gs_alt).
        WRITE: / 'Clave:', gs_alt-altkey, ' Texto:', gs_alt-alttext.
      ENDLOOP.

    WHEN r_fwd.
      CALL FUNCTION 'SAP_WAPI_FORWARD_WORKITEM'
        EXPORTING
          workitem_id    = p_wi
          user_id        = sy-uname
          language       = sy-langu
          do_commit      = abap_true
        IMPORTING
          return_code    = gv_rc
          new_status     = gs_status
        TABLES
          message_lines  = gt_msg
          message_struct = gt_mstruc.

      WRITE: / 'Reenvío. Return code:', gv_rc,
             / 'Nuevo estado:', gs_status-status.

    WHEN r_appr.
      CALL FUNCTION 'SAP_WAPI_DECISION_COMPLETE'
        EXPORTING
          workitem_id    = p_wi
          language       = sy-langu
          user           = sy-uname
          decision_key   = p_key
          do_commit      = abap_true
        IMPORTING
          return_code    = gv_rc
          new_status     = gs_status
        TABLES
          message_lines  = gt_msg
          message_struct = gt_mstruc.

      WRITE: / 'Aprobación. Return code:', gv_rc,
             / 'Nuevo estado:', gs_status-status.

  ENDCASE.

  " Mensajes devueltos por la WAPI
  IF gt_msg IS NOT INITIAL.
    ULINE.
    WRITE: / 'Mensajes:'.
    LOOP AT gt_msg INTO DATA(gs_msg).
      WRITE: / gs_msg-line.
    ENDLOOP.
  ENDIF.
