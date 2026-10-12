# Diseño de solución – Aprobación automática de OC

## 1. Análisis del programa ECC `ZMM_APR_PED_BOT`

Método `cl_apr->m_process_data`, para cada OC pendiente (`gt_ekko`):

1. Calcula el siguiente código de liberación: `strlen( frgzu ) + 1` sobre `T16FS-FRGC1..8`.
2. Busca el código en `ZMM_COD_PED` (rangos `valfrom` / `valto`).
3. Suma `menge * netpr` por posición convertido a USD (`CONVERT_TO_LOCAL_CURRENCY`, fecha `sy-datum`).
4. Si el total está en el rango: `BAPI_PO_RELEASE` → `WAIT UP TO 5 SECONDS` →
   `ZMM_CREATE_COUPA_OC` (`STARTING NEW TASK`) → `zcl_mm_gen->m_eval_migo`.
5. Repite con el siguiente código hasta terminar la estrategia.

`zcl_mm_gen->m_eval_migo`:

1. `WAIT UP TO 5 SECONDS`, lee la SolPed (`EBAN`) y la cabecera (`EKKO`).
2. Si `procstat = '05'`:
   - SolPed en `ZMM_SERV_MULTI` con `zcant_proc > 2` → inserta en `ZMIGO_PEND_SERV`.
   - Si no: lee posiciones no borradas, anticipo `ZFMFI_CHECK_PO` (`STARTING NEW TASK`),
     MIGO `ZFMMM_MIGO_CREATE`.

### Hallazgos que no se migran tal cual

- `netpr` no se divide entre `PEINH` (unidad de precio).
- Montos en tipo `f` (punto flotante).
- No filtra posiciones borradas (`LOEKZ`) en el cálculo del total.
- Moneda USD fija y tasa con `sy-datum`.
- `WAIT UP TO` y `STARTING NEW TASK` no permitidos en ABAP Cloud.
- `BAPI_PO_RELEASE` no tiene contrato C1 (verificado en ADT, sistema DS4) y no aplica a Flexible Workflow.

## 2. Opción 1 – Application Job en S/4 (recomendada)

### Flujo

1. **Flexible Workflow (sin cambios):** la OC entra a aprobación según la configuración actual.
2. **Job – Fase 1 (aprobar):** busca tareas `TS00800531` abiertas, evalúa la regla de monto USD
   por nivel y aprueba con el wrapper Tier 2. Registra la OC en la tabla de control.
3. **Job – Fase 2 (post-liberación):** las OC aprobadas por el bot que ya están liberadas
   (estado `05`) pasan a servicios múltiples, anticipo, Coupa y MIGO.
   - La Fase 2 lee de la tabla de control porque el estado de la OC se actualiza de forma
     asíncrona tras la última aprobación. Reemplaza los `WAIT UP TO 5 SECONDS`.
   - Igual que en ECC, solo se procesan las OC aprobadas por el bot.

### Objetos

| Objeto | Tipo | Tier |
|---|---|---|
| `ZMM_PO_APPR_RULE` | Tabla BD + Business Configuration Maintenance Object | 1 |
| `ZMM_PO_APPR_CTRL` | Tabla BD (control, idempotencia y auditoría) | 1 |
| `ZCL_MM_PO_APPROVAL_RULES` | Clase ABAP (total USD con `PEINH`, sin borrados, tasa vigente; evaluación de rango) | 1 |
| `ZCL_MM_PO_APPR_JOB` | Clase ABAP (`IF_APJ_DT_EXEC_OBJECT`, `IF_APJ_RT_EXEC_OBJECT`) | 1 |
| Catálogo y plantilla del job | Application Job Catalog Entry / Template | 1 |
| Clase MIGO existente | Reutilizada (ABAP Cloud) | 1 |
| `ZCL_MM_WF_DECISION_API` | Clase wrapper (buscar tareas y aprobar), paquete Standard ABAP | 2 · C1 |
| Wrapper anticipo | Solo si `ZFMFI_CHECK_PO` sigue siendo clásica | 2 · C1 |

### Fuentes de datos released

| ECC | S/4 |
|---|---|
| `EBAN` | `I_PurchaseRequisitionItemAPI01` |
| `EKKO` | `I_PurchaseOrderAPI01` |
| `EKPO` | `I_PurchaseOrderItemAPI01` |

## 3. Opción 2 – Agente Joule Studio vía SAP Build Process Automation

1. Proceso programado en Process Automation (cada 5–15 min) invoca el agente.
2. Skills del agente: buscar tareas pendientes (`TASKPROCESSING`), evaluar regla (servicio OData
   custom que expone `ZCL_MM_PO_APPROVAL_RULES`), aprobar (`Decision`).
3. La post-liberación sigue en un Application Job en S/4.

**Regla clave:** el modelo de IA no decide montos ni rangos; la evaluación se hace siempre en S/4.

Costo estimado (agente Standard, 0,01 AI Units por paso): cada 15 min ≈ 58 AI Units/mes solo en
revisar; cada 1 min ≈ 860; más ≈ 0,04 por OC aprobada. Confirmar con el AI Unit Estimator.

## 4. Opción 3 – BAdIs de Flexible Workflow + job de MIGO

### Flujo

1. **BAdI de condición (otro equipo):** `SWF_WORKFLOW_CONDITION_DEF/EVAL` define la condición
   custom "Monto USD fuera del rango automático del nivel N", que llama a
   `ZCL_MM_PO_APPROVAL_RULES`.
2. **Flexible Workflow estándar:** cada paso solo se activa si se cumple la condición. Si ningún
   paso aplica, el workflow libera la OC automáticamente, sin aprobador técnico.
3. **Application Job (cada 1–5 min):** toma las OC liberadas y no procesadas que cumplen el
   criterio de MIGO automática y ejecuta servicios múltiples, anticipo, Coupa y MIGO.

### Objetos

| Objeto | Tipo | Tier |
|---|---|---|
| `ZMM_PO_APPR_RULE` | Tabla BD + Business Configuration Maintenance Object | 1 |
| `ZMM_PO_APPR_CTRL` | Tabla BD (control, idempotencia y auditoría) | 1 |
| `ZCL_MM_PO_APPROVAL_RULES` | Clase ABAP, usada por el BAdI | 1 |
| Implementación BAdI | `SWF_WORKFLOW_CONDITION_DEF/EVAL` (otro equipo) | 1 |
| `ZCL_MM_PO_POSTREL_JOB` + catálogo + plantilla | Application Job | 1 |
| Clase MIGO existente | Reutilizada (ABAP Cloud) | 1 |
| Wrapper anticipo | Solo si `ZFMFI_CHECK_PO` sigue siendo clásica | 2 · C1 |

### Puntos a definir

- **Mapeo de rangos:** en ECC el bot liberaba si el monto estaba dentro del rango del código;
  en Flexible Workflow el paso se activa cuando el monto está fuera del rango automático.
- **Criterio de MIGO automática:** el job no sabe si la OC se liberó sola o la aprobó una persona.
  Opciones: aplicar la misma regla de monto, o revisar si la OC tuvo pasos de aprobación manuales.
- Si la OC cambia, el workflow se reinicia y la condición se vuelve a evaluar.

### Transición desde la Opción 1

Al activar los BAdIs se desactiva la fase de aprobación del job y se retira
`ZCL_MM_WF_DECISION_API`. La clase de reglas, la tabla de control, el job de MIGO y la clase
MIGO se mantienen sin cambios.

## 5. Prueba de la decisión sobre `TS00800531` (DS4)

1. Crear 2 OC que entren a aprobación; ubicar los work items en SWI1 (estado READY).
2. **Prueba A (referencia):** `/IWFND/GW_CLIENT` con el usuario genérico →
   `TaskCollection` → `DecisionOptions` → `POST Decision`.
3. **Prueba B (wrapper):** `SAP_WAPI_DECISION_COMPLETE` con el usuario genérico.
4. Validar: OC liberada, `EKKO-PROCSTAT = '05'`, work item COMPLETED, historial de aprobación.
5. Si A libera y B no, depurar la Prueba A para identificar la lógica que debe envolver el wrapper.
