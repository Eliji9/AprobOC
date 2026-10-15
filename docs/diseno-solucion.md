# Diseño de solución – Aprobación automática de OC

## 1. Análisis del programa ECC `ZMM_APR_PED_BOT`

Método `cl_apr->m_process_data`, para cada OC pendiente (`gt_ekko`):

1. Calcula el siguiente código de liberación: `strlen( frgzu ) + 1` sobre `T16FS-FRGC1..8`.
2. Busca el código en `ZMM_COD_PED` (rangos `valfrom` / `valto`).
3. Suma `menge * netpr` por posición convertido a USD (`CONVERT_TO_LOCAL_CURRENCY`, fecha `sy-datum`).
4. Si el total está en el rango: `BAPI_PO_RELEASE` → `WAIT UP TO 5 SECONDS` → post-liberación.
5. Repite con el siguiente código hasta terminar la estrategia.

Post-liberación en ECC (**fuera de alcance por ahora**): `ZMM_CREATE_COUPA_OC` y
`zcl_mm_gen->m_eval_migo` (SolPed en `ZMM_SERV_MULTI` → `ZMIGO_PEND_SERV`; si no, anticipo
`ZFMFI_CHECK_PO` y MIGO `ZFMMM_MIGO_CREATE`).

### Hallazgos que no se migran tal cual

- `netpr` no se divide entre `PEINH` (unidad de precio).
- Montos en tipo `f` (punto flotante).
- No filtra posiciones borradas (`LOEKZ`) en el cálculo del total.
- Moneda USD fija y tasa con `sy-datum`.
- `WAIT UP TO` y `STARTING NEW TASK` no permitidos en ABAP Cloud.
- `BAPI_PO_RELEASE` no tiene contrato C1 (verificado en ADT, sistema DS4) y no aplica a Flexible Workflow.

## 2. Alcance y restricciones

- Solo aprobación automática; la post-liberación queda fuera por ahora.
- No se usan BAdIs del Flexible Workflow.
- La configuración del Flexible Workflow está congelada por pruebas integrales, sin fecha de fin.

## 3. Opción A – Flexible Workflow con condiciones por BAdI (no implementable hoy)

Las condiciones necesarias (monto en USD y campos adicionales) no existen como condiciones
estándar; se agregan con los BAdIs `SWF_WORKFLOW_CONDITION_DEF` / `SWF_WORKFLOW_CONDITION_EVAL`.

1. El otro equipo implementa los BAdIs; la evaluación del monto USD puede llamar a una clase de reglas.
2. En *Manage Workflows for Purchase Orders* se configuran los pasos por nivel con esas condiciones.
3. Si ningún paso aplica, el workflow libera la OC automáticamente, sin aprobador técnico.

- **Clean core:** 100 % (BAdIs released Tier 1 + configuración estándar, sin Tier 2 ni 3).
- **Bloqueo:** BAdIs a cargo de otro equipo y configuración congelada por pruebas integrales.

## 4. Opción B – Application Job aprobador (recomendada hoy)

1. El Flexible Workflow genera la tarea `TS00800531` según la configuración actual (sin cambios).
2. Un Application Job (cada 1–5 min, usuario genérico con perfil de administrador de workflow)
   busca las tareas abiertas y calcula el total en USD con la clase de reglas.
   Búsqueda de pendientes (definida 15-10-2026): primero las OC "En proc. autorización" con la CDS
   released `I_PurchaseOrderAPI01` (Tier 1, incluye monto y moneda); solo para las que cumplen la regla,
   el wrapper Tier 2 busca su work item `TS00800531` abierto y el nivel (tareas completadas + 1).
3. Si cumple el rango del nivel, el wrapper Tier 2 reenvía la tarea al usuario genérico (si no es
   agente) y la aprueba; si no cumple, queda manual.
4. Registra OC, nivel, monto USD y rango en el Application Log (`CL_BALI_LOG`).

| Objeto | Tipo | Tier |
|---|---|---|
| `ZMM_PO_APPR_RULE` | Tabla BD + Business Configuration Maintenance Object | 1 |
| `ZCL_MM_PO_APPROVAL_RULES` | Clase ABAP (total USD con `PEINH`, sin borrados, tasa vigente; rango) | 1 |
| `ZCL_MM_PO_APPR_JOB` | Clase de Application Job + catálogo + plantilla | 1 |
| `ZCL_MM_WF_DECISION_API` | Clase wrapper (buscar tareas, reenviar y aprobar), paquete Standard ABAP | 2 · C1 |

Fuentes de datos released: `I_PurchaseOrderAPI01`, `I_PurchaseOrderItemAPI01`.

Definiciones (15-10-2026):

- **Usuario del job:** `ZJOBPROCESOS` (en calidad), con perfil de administrador de workflow. Nunca crea OC.
- **Multinivel:** habrá OC con más de un nivel de aprobación. El nivel de cada tarea pendiente se
  determina como *número de tareas `TS00800531` ya completadas en la misma instancia del workflow
  (`WS00800238`) + 1*. Si la OC cambia, el workflow se reinicia (nueva instancia) y el conteo vuelve a 1.
- **Ciclo por nivel:** cada corrida aprueba solo el nivel pendiente si el total USD está en el rango de
  ese nivel; el siguiente nivel lo toma la corrida siguiente (equivalente al `WHILE` de ECC).

## 5. Opción C – SAP Build Process Automation con tabla de decisión

1. Proceso programado en Build (cada 5–15 min) lee tareas pendientes con `TASKPROCESSING`.
2. Obtiene el total en USD de la OC con un servicio OData custom de S/4.
3. Evalúa nivel y monto contra una tabla de decisión de Build que mantiene el negocio.
4. Si cumple, aprueba con `Decision` vía destino y usuario técnico.

| Objeto | Tipo | Tier |
|---|---|---|
| `ZR_MM_PO_TOTAL_USD` | CDS + servicio OData (total en USD) | 1 |
| `TASKPROCESSING` | Servicio estándar de My Inbox | Estándar |
| Proceso, tabla de decisión, destino, Actions | SAP Build Process Automation | BTP |
| `ZR_MM_PO_APPROVE` | Servicio RAP con acción "aprobar" (solo si no se usa sustitución) | 1 |
| `ZCL_MM_WF_DECISION_API` | Clase wrapper (solo si no se usa sustitución) | 2 · C1 |

Clean core: ≈ 85 % (reutiliza el wrapper Tier 2 de la opción B a través del servicio OData).
Ver la sección 7 para el mecanismo de aprobación.

## 6. Opción D – Agente Joule Studio vía Build Process Automation

1. Proceso programado en Build invoca un agente de Joule Studio.
2. Skills: buscar tareas (`TASKPROCESSING`), evaluar regla (servicio OData sobre
   `ZCL_MM_PO_APPROVAL_RULES`), aprobar (`Decision`).
3. La IA no decide montos ni rangos; la evaluación se hace siempre en S/4.

Mismo mecanismo de aprobación y mismo condicionante que la opción C (sección 7). Si el usuario
técnico no puede ser agente, se agrega `ZCL_MM_WF_DECISION_API` (Tier 2). Clean core ≈ 85 %.

Costo estimado (agente Standard, 0,01 AI Units por paso): cada 15 min ≈ 58 AI Units/mes solo en
revisar; cada 5 min ≈ 173; más ≈ 0,04 por OC aprobada. Confirmar con el AI Unit Estimator.

## 7. Cómo aprueban las opciones C y D

Ambas llaman desde BTP, con un destino y un usuario técnico, al mismo servicio que usa My Inbox:

```
BTP (Build) ──destino──► S/4: /sap/opu/odata/IWPGW/TASKPROCESSING;mo;v=2
                             1. GET  TaskCollection   → tareas READY de TS00800531
                             2. GET  DecisionOptions  → clave de "Aprobar"
                             3. POST Decision         → aprueba con comentario
```

- Conexión: destino BTP hacia S/4 (Cloud Connector o conexión privada de RISE; confirmar con Basis).
- Autenticación: usuario técnico (básica u OAuth); sin principal propagation porque es desatendido.
- El POST de `Decision` requiere token CSRF; las Actions de Build lo obtienen si se configuran.
- El historial de la OC muestra al usuario técnico como aprobador, con el comentario enviado.
- En C lo orquesta un proceso con pasos fijos; en D, un agente con tres skills (buscar, evaluar, aprobar).

### Punto crítico: acceso a la tarea

`TASKPROCESSING` es el inbox del usuario conectado: `TaskCollection` solo devuelve las tareas
donde ese usuario es agente. Un administrador no ve tareas ajenas por esta vía, y la configuración
del workflow está congelada.

| Camino | Cómo | Impacto |
|---|---|---|
| Sustitución | Cada aprobador define al usuario técnico como su sustituto | Sin código; depende de cada aprobador y de auditoría · ≈ 100 % |
| Servicio custom en S/4 | Acción RAP "aprobar" que reenvía la tarea al usuario técnico y decide | Usa el wrapper Tier 2 de la opción B · ≈ 85 % |
| API released de work items | Verificar en Business Accelerator Hub si el release la ofrece | La mejor vía si existe; por confirmar |

## 8. Recomendación

1. **Ahora:** opción B, tras la prueba de concepto.
2. **Al terminar las pruebas integrales:** evaluar migrar a la opción A si el negocio acepta
   umbrales por moneda; se retiran el job y el wrapper.
3. **Alternativa:** opción C si el negocio quiere mantener los rangos en BTP y tiene licencia de Build.

## 9. Resultado de la prueba de concepto (DS4, 15-10-2026)

**Se puede aprobar.** Las OC 1100000502 (175,15 USD) y 1100000503 (19.750,00 USD) quedaron
**Autorizado** por un usuario que no era el aprobador original:

1. `SAP_WAPI_FORWARD_WORKITEM` reenvía el work item al usuario que ejecuta (RC 0, estado SELECTED).
2. `TASKPROCESSING` → `POST Decision` con `SAP__Origin='LOCAL_TGW'`, `DecisionKey='0001'` (Autorizar,
   POSITIVE). `0002` = Rechazar (NEGATIVE).
3. Work item → finalizado; OC → Autorizado, aprobador = usuario que ejecutó.

Hallazgos:

- `SAP_WAPI_DECISION_READ/COMPLETE` **no sirven**: la tarea `TS00800531` no es una decisión clásica
  ("no es decisión del usuario").
- `TASKPROCESSING` sin reenvío devuelve `/IWWRK/WF_ODC/004 – No tiene acceso al elemento`: solo
  opera tareas donde el usuario es agente.
- El ID correcto es el del **paso de diálogo** (`TS00800531`), no el del workflow padre (`WS00800238`).
- Las opciones de decisión del Flexible Workflow se configuran por escenario (`WS00800238`), no por tarea.
- **Agentes excluidos:** el reenvío falla con "El responsable US … está excluido del tratamiento del
  work item" (RC 2) cuando el usuario está excluido de la tarea; por ejemplo, si es el creador de la OC
  (control de segregación de funciones del workflow). El reenvío no salta esta exclusión. Implicación:
  el usuario genérico del job **nunca** debe crear OC, y el job debe registrar esas OC como excepción
  y dejarlas para aprobación manual.

Cadena de llamadas de la aprobación (pila del debugger):

| Nivel | Objeto | Rol |
|---|---|---|
| 30–31 | `/IWPGW/CL_TGW_EDP_TASK` → `ACTION_DECISION` | Servicio `TASKPROCESSING` |
| 33 | **`/IWWRK/WF_TGW_TASK_DET_ACTION`** | Punto de entrada en el backend |
| 34 | `/IWWRK/CL_TGW_RFC_HANDLER` → `WF_TGW_TASK_DET_ACTION` | Handler |
| 35–37 | `/IWWRK/CL_WF_UPDATE_WORKITEM` → `EXECUTE_OPERATION` / `OPERATION_DECISION` / `CUST_BADI_BEFORE_UPDATE` | Framework de decisión |
| 38 | `CL_MM_PUR_PO_APPR_ACTIONS_BADI` → `BEFORE_UPDATE` | Lógica estándar MM de aprobación de OC |
| 39 | `CL_MM_PUR_WF_OBJECT` → `SET_WORKITEM_EXECUTED` | MM registra el resultado |
| 40 | `SAP_WAPI_WORKITEM_COMPLETE` | Cierre técnico |

Firma de `/IWWRK/WF_TGW_TASK_DET_ACTION`: `IV_INSTANCE_ID` (SWW_WIID), `IV_ACTION_NAME` (STRING),
`IV_DECISION_KEY` (SWR_DECIKEY), `IV_FORWARD_USR_ID` (SYUNAME), `IV_LANGUAGE` (SPRAS),
`IV_COMMENTS` (STRING), `IS_RESUBMISSION`, `IV_REASON_CODE`; salida `EV_ERROR_FLAG`, `ET_RETURN`
(BAPIRETTAB), `ES_WI_ROOT_DETAIL`, `ET_RETURN_USERS`.

**Prueba de concepto 2 (validada, 15-10-2026):** el programa `poc/ZTEST_WF_TGW_APPROVE.abap` aprobó
el work item 47037 (OC 1100000508, 19.750,00 USD) sin HTTP ni My Inbox:
`SAP_WAPI_FORWARD_WORKITEM` (RC 0) → `/IWWRK/WF_TGW_TASK_DET_ACTION` con `IV_ACTION_NAME = 'Decision'`,
`IV_DECISION_KEY = '0001'` → `COMMIT WORK AND WAIT`. Resultado: work item COMPLETED y OC **Autorizado**.

**Implicación para el wrapper (opción B):** reenviar con `SAP_WAPI_FORWARD_WORKITEM` y aprobar con
`/IWWRK/WF_TGW_TASK_DET_ACTION`, que ejecuta toda la lógica estándar de MM. Pendiente PoC 2:
validar la llamada directa (programa `poc/ZTEST_WF_TGW_APPROVE.abap`) con `IV_ACTION_NAME = 'Decision'` (valor capturado en el debugger, sensible a mayúsculas; `EXEC` devuelve "La operación no existe").

## 10. Procedimiento de la prueba de concepto (DS4)

1. Crear 2 OC que entren a aprobación; ubicar los work items en SWI1 (estado READY).
2. **Prueba A (referencia):** `/IWFND/GW_CLIENT` con el usuario genérico →
   `TaskCollection` → `DecisionOptions` → `POST Decision`.
   - Si `TaskCollection` sale vacío, el usuario genérico no es agente de la tarea (comportamiento
     esperado). Repetir asignándolo como sustituto de un aprobador.
3. **Prueba B (wrapper):** `SAP_WAPI_DECISION_COMPLETE` con el usuario genérico.
4. Validar: OC liberada, `EKKO-PROCSTAT = '05'`, work item COMPLETED, historial de aprobación.
5. Si A libera y B no, depurar la Prueba A para identificar la lógica que debe envolver el wrapper.
