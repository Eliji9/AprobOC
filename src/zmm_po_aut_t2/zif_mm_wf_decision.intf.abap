"! <p class="shorttext synchronized">Aprob. automática OC: decisión de workflow (Tier 2)</p>
"! Contrato del wrapper Tier 2. Se libera con contrato C1 (Use in Cloud Development)
"! para que el motor ABAP Cloud lo consuma. Solo usa tipos básicos, porque los
"! elementos de datos del workflow (SWW_WIID, etc.) no están liberados.
INTERFACE zif_mm_wf_decision
  PUBLIC.

  TYPES ty_workitem_id    TYPE n LENGTH 12.
  TYPES ty_purchase_order TYPE c LENGTH 10.
  TYPES tt_purchase_order TYPE STANDARD TABLE OF ty_purchase_order WITH EMPTY KEY.

  TYPES:
    BEGIN OF ty_task,
      workitem_id    TYPE ty_workitem_id,
      purchase_order TYPE ty_purchase_order,
      approval_level TYPE i,
    END OF ty_task.
  TYPES tt_task TYPE STANDARD TABLE OF ty_task WITH EMPTY KEY.

  CONSTANTS:
    BEGIN OF gc_result,
      approved       TYPE c LENGTH 1 VALUE 'A',
      forward_failed TYPE c LENGTH 1 VALUE 'F',
      error          TYPE c LENGTH 1 VALUE 'E',
    END OF gc_result.

  TYPES:
    BEGIN OF ty_result,
      result  TYPE c LENGTH 1,
      message TYPE string,
    END OF ty_result.

  "! Tareas de aprobación de OC (TS00800531) abiertas para las OC indicadas.
  "! approval_level = tareas TS00800531 completadas en la misma instancia + 1.
  METHODS get_open_tasks
    IMPORTING it_purchase_orders TYPE tt_purchase_order
    RETURNING VALUE(rt_tasks)    TYPE tt_task.

  "! Reenvía la tarea al usuario que ejecuta (si no es el agente) y la aprueba
  "! con la misma lógica de My Inbox. Hace COMMIT / ROLLBACK por tarea.
  METHODS approve
    IMPORTING iv_workitem_id   TYPE ty_workitem_id
              iv_comment       TYPE string
    RETURNING VALUE(rs_result) TYPE ty_result.

ENDINTERFACE.
