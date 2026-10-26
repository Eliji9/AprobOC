"! <p class="shorttext synchronized">Aprob. automática OC: motor</p>
"! Motor de aprobación automática de OC (ABAP Cloud, Tier 1).
"! 1. OC "En proc. autorización" de grupos de compras con rango activo
"! 2. Total de la OC convertido a la moneda del rango
"! 3. Si el total está en el rango: tarea abierta y aprobación (wrapper Tier 2)
CLASS zcl_mm_po_aut_engine DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES zif_mm_po_aut_engine.

    "! @parameter io_wf_decision | Inyección para pruebas unitarias (por defecto, el wrapper real)
    METHODS constructor
      IMPORTING io_wf_decision TYPE REF TO zif_mm_wf_decision OPTIONAL.

  PRIVATE SECTION.
    " Estado de procesamiento de la OC "En aprobación" (EKKO-PROCSTAT)
    CONSTANTS gc_procstat_in_approval TYPE c LENGTH 2 VALUE '03'.

    TYPES:
      BEGIN OF ty_po,
        purchase_order   TYPE i_purchaseorderapi01-purchaseorder,
        purchasing_group TYPE i_purchaseorderapi01-purchasinggroup,
        currency         TYPE i_purchaseorderapi01-documentcurrency,
      END OF ty_po.
    TYPES tt_po   TYPE STANDARD TABLE OF ty_po WITH EMPTY KEY.
    TYPES tt_rule TYPE HASHED TABLE OF zmm_po_aut_rng WITH UNIQUE KEY purchasing_group.

    DATA mo_wf_decision TYPE REF TO zif_mm_wf_decision.

    METHODS get_rules
      RETURNING VALUE(rt_rule) TYPE tt_rule.

    METHODS get_pending_orders
      IMPORTING it_purchase_orders TYPE zif_mm_po_aut_engine=>tt_po_range
      RETURNING VALUE(rt_po)       TYPE tt_po.

    METHODS get_order_total
      IMPORTING iv_purchase_order TYPE i_purchaseorderapi01-purchaseorder
                iv_currency       TYPE i_purchaseorderapi01-documentcurrency
                iv_target_curr    TYPE zmm_po_aut_rng-currency
      RETURNING VALUE(rv_total)   TYPE decfloat34
      RAISING   zcx_mm_po_aut_error.

ENDCLASS.



CLASS zcl_mm_po_aut_engine IMPLEMENTATION.

  METHOD constructor.
    mo_wf_decision = COND #( WHEN io_wf_decision IS BOUND THEN io_wf_decision
                             ELSE NEW zcl_mm_wf_decision( ) ).
  ENDMETHOD.


  METHOD zif_mm_po_aut_engine~process_pending.

    DATA lt_candidates TYPE zif_mm_wf_decision=>tt_purchase_order.

    DATA(lt_rules) = get_rules( ).
    IF lt_rules IS INITIAL.
      RETURN.
    ENDIF.

    " 1. Evaluar el rango de cada OC en aprobación
    LOOP AT get_pending_orders( it_purchase_orders ) INTO DATA(ls_po).

      APPEND VALUE #( purchase_order   = ls_po-purchase_order
                      purchasing_group = ls_po-purchasing_group ) TO rt_result
             ASSIGNING FIELD-SYMBOL(<ls_res>).

      READ TABLE lt_rules WITH TABLE KEY purchasing_group = ls_po-purchasing_group
           INTO DATA(ls_rule).
      IF sy-subrc <> 0.
        <ls_res>-status = zif_mm_po_aut_engine=>gc_status-no_rule.
        CONTINUE.
      ENDIF.

      TRY.
          <ls_res>-total_amount = get_order_total( iv_purchase_order = ls_po-purchase_order
                                                   iv_currency       = ls_po-currency
                                                   iv_target_curr    = ls_rule-currency ).
          <ls_res>-currency = ls_rule-currency.
        CATCH zcx_mm_po_aut_error INTO DATA(lx_error).
          <ls_res>-status  = zif_mm_po_aut_engine=>gc_status-error.
          <ls_res>-message = lx_error->get_text( ).
          CONTINUE.
      ENDTRY.

      IF <ls_res>-total_amount BETWEEN ls_rule-amount_from AND ls_rule-amount_to.
        APPEND ls_po-purchase_order TO lt_candidates.
      ELSE.
        <ls_res>-status = zif_mm_po_aut_engine=>gc_status-out_of_range.
      ENDIF.

    ENDLOOP.

    IF lt_candidates IS INITIAL.
      RETURN.
    ENDIF.

    " 2. Tareas abiertas de las OC que cumplen la regla
    DATA(lt_tasks) = mo_wf_decision->get_open_tasks( lt_candidates ).

    " 3. Aprobar la tarea abierta (un nivel por OC y por ejecución)
    LOOP AT rt_result ASSIGNING <ls_res> WHERE status IS INITIAL.

      READ TABLE lt_tasks WITH KEY purchase_order = <ls_res>-purchase_order
           INTO DATA(ls_task).
      IF sy-subrc <> 0.
        <ls_res>-status = zif_mm_po_aut_engine=>gc_status-no_task.
        CONTINUE.
      ENDIF.

      <ls_res>-workitem_id    = ls_task-workitem_id.
      <ls_res>-approval_level = ls_task-approval_level.

      IF iv_test_mode = abap_true.
        <ls_res>-status = zif_mm_po_aut_engine=>gc_status-test_ok.
        CONTINUE.
      ENDIF.

      DATA(ls_decision) = mo_wf_decision->approve(
        iv_workitem_id = ls_task-workitem_id
        iv_comment     = |Aprobación automática nivel { ls_task-approval_level }: | &&
                         |{ <ls_res>-total_amount NUMBER = USER } { <ls_res>-currency } dentro del rango| ).

      <ls_res>-message = ls_decision-message.
      <ls_res>-status  = SWITCH #( ls_decision-result
                           WHEN zif_mm_wf_decision=>gc_result-approved       THEN zif_mm_po_aut_engine=>gc_status-approved
                           WHEN zif_mm_wf_decision=>gc_result-forward_failed THEN zif_mm_po_aut_engine=>gc_status-forward_failed
                           ELSE zif_mm_po_aut_engine=>gc_status-error ).
    ENDLOOP.

  ENDMETHOD.


  METHOD get_rules.
    SELECT * FROM zmm_po_aut_rng
      WHERE is_active = @abap_true
      INTO TABLE @rt_rule.
  ENDMETHOD.


  METHOD get_pending_orders.
    " Solo OC de grupos de compras con rango activo.
    " Rango de OC vacío = todas (IN con rango vacío no filtra).
    SELECT po~PurchaseOrder    AS purchase_order,
           po~PurchasingGroup  AS purchasing_group,
           po~DocumentCurrency AS currency
      FROM i_purchaseorderapi01 AS po
      INNER JOIN zmm_po_aut_rng AS rng
        ON  rng~purchasing_group = po~PurchasingGroup
        AND rng~is_active        = @abap_true
      WHERE po~PurchasingProcessingStatus = @gc_procstat_in_approval
        AND po~PurchaseOrder              IN @it_purchase_orders
      INTO CORRESPONDING FIELDS OF TABLE @rt_po.
  ENDMETHOD.


  METHOD get_order_total.

    DATA lv_amount_doc  TYPE p LENGTH 16 DECIMALS 2.
    DATA lv_amount_conv TYPE p LENGTH 16 DECIMALS 2.

    " Posiciones no borradas. Valor = cantidad × precio neto / unidad de precio
    " (corrige el cálculo de ECC, que no consideraba la unidad de precio).
    SELECT OrderQuantity, NetPriceAmount, NetPriceQuantity
      FROM i_purchaseorderitemapi01
      WHERE PurchaseOrder                  = @iv_purchase_order
        AND PurchasingDocumentDeletionCode = @space
      INTO TABLE @DATA(lt_items).

    LOOP AT lt_items INTO DATA(ls_item).
      DATA(lv_price_unit) = COND decfloat34( WHEN ls_item-NetPriceQuantity > 0
                                             THEN ls_item-NetPriceQuantity ELSE 1 ).
      rv_total += ls_item-OrderQuantity * ls_item-NetPriceAmount / lv_price_unit.
    ENDLOOP.

    IF iv_currency = iv_target_curr.
      RETURN.
    ENDIF.

    " Conversión con la tasa del día de ejecución (igual que ECC).
    " Validar en ADT la firma de la API liberada de conversión de moneda.
    lv_amount_doc = rv_total.
    TRY.
        cl_exchange_rates=>convert_to_local_currency(
          EXPORTING date             = cl_abap_context_info=>get_system_date( )
                    foreign_amount   = lv_amount_doc
                    foreign_currency = iv_currency
                    local_currency   = iv_target_curr
          IMPORTING local_amount     = lv_amount_conv ).
        rv_total = lv_amount_conv.
      CATCH cx_exchange_rates INTO DATA(lx_rates).
        RAISE EXCEPTION NEW zcx_mm_po_aut_error(
          iv_text  = |OC { iv_purchase_order }: no se pudo convertir { iv_currency } a { iv_target_curr }|
          previous = lx_rates ).
    ENDTRY.

  ENDMETHOD.

ENDCLASS.
