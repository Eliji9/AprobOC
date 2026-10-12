# AprobOC – Aprobación automática de órdenes de compra

Migración a **S/4HANA Cloud Private Edition** (ABAP Cloud / Clean Core) del job de ECC
`ZMM_APR_PED_BOT`, que libera automáticamente las órdenes de compra pendientes según
rangos de monto y luego ejecuta anticipo, integración con Coupa y MIGO.

- Comparativo visual de opciones: [`docs/index.html`](docs/index.html)
- Diseño de la solución: [`docs/diseno-solucion.md`](docs/diseno-solucion.md)

## Contexto

| Tema | ECC (actual) | S/4HANA Private (objetivo) |
|---|---|---|
| Liberación | Estrategia clásica (`T16FS`) + `BAPI_PO_RELEASE` | Flexible Workflow (tarea `TS00800531`) |
| Regla | Rangos de monto en USD por código de liberación (`ZMM_COD_PED`) | Rangos de monto en USD por nivel de aprobación |
| Ejecutor | Usuario genérico creador del job | Usuario genérico con perfil de administrador de workflow |
| Post-liberación | `ZCL_MM_GEN->m_eval_migo`, `ZMM_CREATE_COUPA_OC` | Clase MIGO existente (ABAP Cloud) + anticipo + Coupa |

**Restricción:** no se modifica la configuración ni los BAdIs del Flexible Workflow
(los gestiona otro equipo).

## Opciones evaluadas

| Criterio | Opción 1 · Job en S/4 | Opción 2 · Agente Joule | Opción 3 · BAdI + job MIGO |
|---|---|---|---|
| Quién libera | Usuario genérico admin. | Agente con usuario genérico | Workflow estándar |
| Clean core | ≈ 85 % (T1 + T2) | ≈ 90 % (T1 + BTP) | ≈ 95 % (T1) |
| Latencia de liberación | 1–5 min | 5–15 min | Inmediata |
| Costo incremental | Ninguno | AI Units + licencias | Ninguno |
| Dependencias | Ninguna | BTP, Joule, licencias | Equipo de BAdIs (meses) |
| Viabilidad | Alta | Media | Alta, a mediano plazo |

**Recomendación:** usar la Opción 1 como puente hacia la Opción 3.

1. **Go-live:** Opción 1 (el job aprueba y crea la MIGO).
2. **Cuando el otro equipo libere los BAdIs:** Opción 3. Se desactiva la fase de aprobación
   del job y se retira el wrapper de decisión; el job de MIGO sigue igual.
3. **Opcional:** agente Joule como supervisor de excepciones.

Las tres opciones comparten la tabla de reglas, la clase de reglas, la tabla de control y
la clase MIGO, así que ningún cambio de fase implica rehacer lo construido.

## Estado

- [ ] Prueba A/B de la decisión sobre `TS00800531` (`TASKPROCESSING` vs. `SAP_WAPI_DECISION_COMPLETE`)
- [ ] Mapeo de rangos de `ZMM_COD_PED` a niveles del Flexible Workflow (negocio)
- [ ] Firma de la clase MIGO y comportamiento de `COMMIT ENTITIES`
- [ ] Estado de `ZFMFI_CHECK_PO` (anticipo) y `ZMM_CREATE_COUPA_OC` (Coupa)
- [ ] Tipo de OC: materiales o servicios (lean services)
- [ ] Frecuencia mínima del Application Job y autorizaciones del usuario genérico
- [ ] Opción 3: fecha de los BAdIs del otro equipo y acuerdo para que llamen a `ZCL_MM_PO_APPROVAL_RULES`
- [ ] Opción 3: criterio para decidir qué OC liberadas llevan MIGO automática

## Estructura prevista

```
src/            Objetos ABAP (abapGit), cuando inicie el desarrollo
docs/           Documentación de diseño y comparativo de opciones
```
