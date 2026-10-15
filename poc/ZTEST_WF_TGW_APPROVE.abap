*&---------------------------------------------------------------------*
*& Report ZTEST_WF_TGW_APPROVE
*&---------------------------------------------------------------------*
*& Prueba de concepto 2: aprobar una tarea de Flexible Workflow de OC
*& (TS00800531) llamando directamente la función del backend que usa
*& My Inbox, sin pasar por HTTP / TASKPROCESSING.
*&
*& Cadena validada en el debugger (PoC 1):
*&   TASKPROCESSING -> /IWWRK/WF_TGW_TASK_DET_ACTION
*&     -> /IWWRK/CL_WF_UPDATE_WORKITEM->OPERATION_DECISION
*&     -> CL_MM_PUR_PO_APPR_ACTIONS_BADI (BEFORE_UPDATE)
*&     -> CL_MM_PUR_WF_OBJECT->SET_WORKITEM_EXECUTED
*&     -> SAP_WAPI_WORKITEM_COMPLETE
*&
*& SOLO PARA DS4. Programa desechable en Standard ABAP (SE38, $TMP).
*&---------------------------------------------------------------------*
REPORT ztest_wf_tgw_approve.

PARAMETERS: p_wi     TYPE sww_wiid OBLIGATORY,
            p_key    TYPE swr_decikey DEFAULT '0001',
            p_act    TYPE string LOWER CASE DEFAULT 'DECISION',
            p_coment TYPE string LOWER CASE DEFAULT 'Aprobacion automatica PoC',
            p_fwd    AS CHECKBOX DEFAULT 'X',
            p_test   AS CHECKBOX DEFAULT 'X'.

DATA: gv_rc       TYPE sy-subrc,
      gs_status   TYPE swr_wistat,
      gt_msg      TYPE STANDARD TABLE OF swr_messag,
      gt_mstruc   TYPE STANDARD TABLE OF swr_mstruc,
      gv_error    TYPE /iwwrk/wf_flag,
      gt_return   TYPE bapirettab.

START-OF-SELECTION.

  "--- 1. Validar el work item -------------------------------------------
  SELECT SINGLE wi_id, wi_stat, wi_rh_task, wi_text, wi_aagent
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
         / 'Agente    :', gs_wi-wi_aagent,
         / 'Texto     :', gs_wi-wi_text,
         / 'Usuario   :', sy-uname.
  ULINE.

  IF gs_wi-wi_rh_task <> 'TS00800531'.
    WRITE: / 'ERROR: el work item no es de la tarea TS00800531. Se detiene.'.
    RETURN.
  ENDIF.

  IF gs_wi-wi_stat <> 'READY' AND gs_wi-wi_stat <> 'SELECTED'.
    WRITE: / 'ERROR: el work item no está pendiente. Se detiene.'.
    RETURN.
  ENDIF.

  IF p_test = abap_true.
    WRITE: / 'Modo prueba: no se reenvía ni se aprueba.',
           / 'Desmarque "Modo prueba" para ejecutar.'.
    RETURN.
  ENDIF.

  "--- 2. Reenviar al usuario que ejecuta (si no es el agente) -----------
  IF p_fwd = abap_true AND gs_wi-wi_aagent <> sy-uname.
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

    WRITE: / 'Reenvío. Return code:', gv_rc, ' Nuevo estado:', gs_status-status.
    IF gv_rc <> 0.
      LOOP AT gt_msg INTO DATA(gs_msg).
        WRITE: / gs_msg-line.
      ENDLOOP.
      RETURN.
    ENDIF.
    ULINE.
  ENDIF.

  "--- 3. Aprobar con la misma función que usa My Inbox ------------------
  CALL FUNCTION '/IWWRK/WF_TGW_TASK_DET_ACTION'
    EXPORTING
      iv_instance_id   = p_wi
      iv_action_name   = p_act
      iv_decision_key  = p_key
      iv_forward_usr_id = space
      iv_language      = sy-langu
      iv_comments      = p_coment
    IMPORTING
      ev_error_flag    = gv_error
      et_return        = gt_return.

  IF gv_error IS INITIAL.
    COMMIT WORK AND WAIT.
    WRITE: / 'Aprobación ejecutada sin error.'.
  ELSE.
    ROLLBACK WORK.
    WRITE: / 'ERROR en la aprobación (rollback ejecutado).'.
  ENDIF.

  LOOP AT gt_return INTO DATA(gs_ret).
    WRITE: / gs_ret-type, gs_ret-id, gs_ret-number, gs_ret-message.
  ENDLOOP.

  "--- 4. Estado final del work item -------------------------------------
  SELECT SINGLE wi_stat FROM swwwihead WHERE wi_id = @p_wi INTO @DATA(gv_stat).
  ULINE.
  WRITE: / 'Estado final del work item:', gv_stat.
