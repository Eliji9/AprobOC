"! <p class="shorttext synchronized">Aprob. automática OC: motor</p>
"! Contrato del motor. Lo consume el Application Job (opción B) y, si en el
"! futuro se requiere, un servicio OData para BTP (opciones C y D).
INTERFACE zif_mm_po_aut_engine
  PUBLIC.

  CONSTANTS:
    BEGIN OF gc_status,
      approved       TYPE c LENGTH 2 VALUE 'AP',  " Aprobada
      test_ok        TYPE c LENGTH 2 VALUE 'TS',  " Cumple la regla (modo prueba, no se aprueba)
      out_of_range   TYPE c LENGTH 2 VALUE 'OR',  " Monto fuera del rango: queda manual
      no_rule        TYPE c LENGTH 2 VALUE 'NR',  " Sin rango para el grupo de compras
      no_task        TYPE c LENGTH 2 VALUE 'NT',  " Sin tarea de aprobación abierta
      forward_failed TYPE c LENGTH 2 VALUE 'FF',  " No se pudo reenviar (p. ej. agente excluido)
      error          TYPE c LENGTH 2 VALUE 'ER',  " Error al calcular o aprobar
    END OF gc_status.

  TYPES:
    BEGIN OF ty_result,
      purchase_order   TYPE i_purchaseorderapi01-purchaseorder,
      purchasing_group TYPE i_purchaseorderapi01-purchasinggroup,
      total_amount     TYPE decfloat34,
      currency         TYPE zmm_po_aut_rng-currency,
      workitem_id      TYPE zif_mm_wf_decision=>ty_workitem_id,
      approval_level   TYPE i,
      status           TYPE c LENGTH 2,
      message          TYPE string,
    END OF ty_result.
  TYPES tt_result TYPE STANDARD TABLE OF ty_result WITH EMPTY KEY.
  TYPES tt_po_range TYPE RANGE OF i_purchaseorderapi01-purchaseorder.

  "! Busca las OC en aprobación, evalúa el rango de su grupo de compras y
  "! aprueba la tarea abierta de las que cumplen. Una tarea (nivel) por OC y
  "! por ejecución; el siguiente nivel lo toma la ejecución siguiente.
  "! @parameter iv_test_mode       | Evalúa sin reenviar ni aprobar
  "! @parameter it_purchase_orders | Opcional: limita a estas OC (vacío = todas)
  METHODS process_pending
    IMPORTING iv_test_mode       TYPE abap_bool DEFAULT abap_false
              it_purchase_orders TYPE tt_po_range OPTIONAL
    RETURNING VALUE(rt_result)   TYPE tt_result.

ENDINTERFACE.
