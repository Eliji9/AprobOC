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

## 3. Opción A – Condiciones estándar del Flexible Workflow (no implementable hoy)

1. En *Manage Workflows for Purchase Orders* se definen pasos con la condición estándar de monto
   neto de la OC, por moneda del documento.
2. Si ningún paso aplica, el workflow libera la OC automáticamente.
3. Los umbrales en moneda local se revisan periódicamente por la tasa de cambio.

- **Objetos:** ninguno; solo configuración (administrador del workflow).
- **Clean core:** 100 % estándar.
- **Limitación:** no evalúa en USD; requiere umbrales por moneda.
- **Bloqueo:** configuración congelada por pruebas integrales.

## 4. Opción B – Application Job aprobador (recomendada hoy)

1. El Flexible Workflow genera la tarea `TS00800531` según la configuración actual (sin cambios).
2. Un Application Job (cada 1–5 min, usuario genérico con perfil de administrador de workflow)
   busca las tareas abiertas y calcula el total en USD con la clase de reglas.
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

Clean core: ≈ 100 % con sustitución o API released; ≈ 85 % si se necesita el wrapper.
Ver la sección 7 para el mecanismo de aprobación.

## 6. Opción D – Agente Joule Studio vía Build Process Automation

1. Proceso programado en Build invoca un agente de Joule Studio.
2. Skills: buscar tareas (`TASKPROCESSING`), evaluar regla (servicio OData sobre
   `ZCL_MM_PO_APPROVAL_RULES`), aprobar (`Decision`).
3. La IA no decide montos ni rangos; la evaluación se hace siempre en S/4.

Mismo mecanismo de aprobación y mismo condicionante que la opción C (sección 7). Si el usuario
técnico no puede ser agente, se agrega `ZCL_MM_WF_DECISION_API` (Tier 2). Clean core ≈ 85–100 %.

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

## 9. Prueba de concepto de la decisión sobre `TS00800531` (DS4)

1. Crear 2 OC que entren a aprobación; ubicar los work items en SWI1 (estado READY).
2. **Prueba A (referencia):** `/IWFND/GW_CLIENT` con el usuario genérico →
   `TaskCollection` → `DecisionOptions` → `POST Decision`.
   - Si `TaskCollection` sale vacío, el usuario genérico no es agente de la tarea (comportamiento
     esperado). Repetir asignándolo como sustituto de un aprobador.
3. **Prueba B (wrapper):** `SAP_WAPI_DECISION_COMPLETE` con el usuario genérico.
4. Validar: OC liberada, `EKKO-PROCSTAT = '05'`, work item COMPLETED, historial de aprobación.
5. Si A libera y B no, depurar la Prueba A para identificar la lógica que debe envolver el wrapper.
