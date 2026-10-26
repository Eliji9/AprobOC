# Objetos de la opción B – Motor + Application Job

Código fuente para crear en ADT (copiar y pegar). No es un repositorio abapGit:
las tablas, el objeto de mantenimiento y el job se crean con los asistentes de ADT.

## Paquetes

| Paquete | Versión de lenguaje | Contenido |
|---|---|---|
| `ZMM_PO_AUT` | ABAP for Cloud Development | Tabla de rangos, motor, excepción y job |
| `ZMM_PO_AUT_T2` | Standard ABAP | Wrapper Tier 2 (interfaz + clase liberadas C1) |

## Objetos

| # | Objeto | Tipo | Paquete | Archivo |
|---|---|---|---|---|
| 1 | `ZMM_PO_AUT_RNG` | Tabla de BD (customizing, clase C) | `ZMM_PO_AUT` | `zmm_po_aut/zmm_po_aut_rng.tabl.ddls` |
| 2 | Objetos de mantenimiento | Generados (ver paso 3) | `ZMM_PO_AUT` | — |
| 3 | `ZIF_MM_WF_DECISION` | Interfaz, liberada C1 | `ZMM_PO_AUT_T2` | `zmm_po_aut_t2/zif_mm_wf_decision.intf.abap` |
| 4 | `ZCL_MM_WF_DECISION` | Clase wrapper, liberada C1 | `ZMM_PO_AUT_T2` | `zmm_po_aut_t2/zcl_mm_wf_decision.clas.abap` |
| 5 | `ZCX_MM_PO_AUT_ERROR` | Clase de excepción | `ZMM_PO_AUT` | `zmm_po_aut/zcx_mm_po_aut_error.clas.abap` |
| 6 | `ZIF_MM_PO_AUT_ENGINE` | Interfaz del motor | `ZMM_PO_AUT` | `zmm_po_aut/zif_mm_po_aut_engine.intf.abap` |
| 7 | `ZCL_MM_PO_AUT_ENGINE` | Clase del motor | `ZMM_PO_AUT` | `zmm_po_aut/zcl_mm_po_aut_engine.clas.abap` |
| 8 | `ZCL_MM_PO_AUT_JOB` | Clase del Application Job | `ZMM_PO_AUT` | `zmm_po_aut/zcl_mm_po_aut_job.clas.abap` |
| 9 | `ZMM_PO_AUT_JOB_CAT` | Application Job Catalog Entry | `ZMM_PO_AUT` | — (asistente) |
| 10 | `ZMM_PO_AUT_JOB_TMPL` | Application Job Template | `ZMM_PO_AUT` | — (asistente) |

En stand-by: tabla de solicitantes (`ZMM_PO_AUT_SOL`, reemplazo del set `ZMM_SOL_PED`),
hasta confirmar si se usará.

## Orden de creación

1. **Paquetes** `ZMM_PO_AUT` (ABAP Cloud) y `ZMM_PO_AUT_T2` (Standard ABAP).
2. **Tabla `ZMM_PO_AUT_RNG`**: nueva tabla de BD en `ZMM_PO_AUT` y pegar el DDL.
3. **Mantenimiento de rangos**: clic derecho sobre la tabla → *Generate ABAP Repository Objects*
   → *Business Configuration Maintenance Object*. Genera las CDS, el behavior, el servicio y el
   objeto de mantenimiento (`ZMM_PO_AUT_RNG_MO`). Publicar el binding. El negocio mantiene los
   rangos desde la app *Custom Business Configurations*.
4. **Wrapper** (en `ZMM_PO_AUT_T2`): crear `ZIF_MM_WF_DECISION` y `ZCL_MM_WF_DECISION`, activar y
   liberar **ambos** con contrato **C1 – Use System-Internally / Use in Cloud Development**
   (pestaña *API State* en ADT).
5. **Excepción, interfaz y motor** (en `ZMM_PO_AUT`): `ZCX_MM_PO_AUT_ERROR`,
   `ZIF_MM_PO_AUT_ENGINE`, `ZCL_MM_PO_AUT_ENGINE`.
6. **Job**: `ZCL_MM_PO_AUT_JOB`; luego *New → Application Job Catalog Entry* (`ZMM_PO_AUT_JOB_CAT`,
   clase `ZCL_MM_PO_AUT_JOB`) y *Application Job Template* (`ZMM_PO_AUT_JOB_TMPL`).
7. **ATC** con la variante de ABAP Cloud sobre `ZMM_PO_AUT`: sin errores.
8. **Programar el job** desde *Application Jobs* con el usuario `ZJOBPROCESOS` y la frecuencia
   definida. Primera corrida con *Modo prueba* marcado.

## Regla de negocio

- Una fila por **grupo de compras** con `monto desde`, `monto hasta`, moneda (USD) y `activo`.
- Si el total de la OC (convertido a la moneda del rango, tasa del día) está dentro del rango,
  el motor aprueba la tarea abierta. Aplica igual a todos los niveles: en OC multinivel, cada
  ejecución aprueba un nivel y la siguiente toma el siguiente.
- Si no cumple, la OC queda para aprobación manual.

Datos actuales en ECC (`ZMM_COD_PED`) para migrar:

| Grupo de compras | Desde | Hasta | Moneda |
|---|---|---|---|
| A63 | 0,00 | 5.000,00 | USD |
| GBG | 0,00 | 5.000,00 | USD |
| GBO | 1,00 | 30.000,00 | USD |

## Validaciones en DS4 (26-10-2026)

| Punto | Resultado |
|---|---|
| Relación tarea → OC | Confirmado: `SWW_WI2OBJ` del WI 47037 → `CATID = CL`, `TYPEID = CL_MM_PUR_WF_OBJECT_PO`, `INSTID = 1100000508`. El wrapper filtra por ese tipo para ignorar anexos (`BO` / `SOFM`) |
| OC en aprobación | Confirmado: OC 1100000509 "En proc. autorización" → `EKKO-PROCSTAT = 03` |
| Conversión de moneda | Confirmada la firma de `CL_EXCHANGE_RATES=>CONVERT_TO_LOCAL_CURRENCY` (`DATE`, `FOREIGN_AMOUNT`, `FOREIGN_CURRENCY`, `LOCAL_CURRENCY` → `LOCAL_AMOUNT`) |
| Agente excluido | Validado en la PoC: el reenvío falla y la OC queda con estado `FF` |
| Falla de aprobación después del reenvío | Pendiente de definir cómo devolver la tarea a su aprobador |
