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

| Criterio | Opción 1 · Application Job en S/4 | Opción 2 · Agente Joule Studio |
|---|---|---|
| Clean core | ≈ 85 % (Tier 1 + Tier 2) | ≈ 90 % (Tier 1 + BTP) |
| Latencia de aprobación | 1–5 min | 5–15 min |
| Costo incremental | Ninguno | AI Units + licencias |
| Viabilidad | Alta | Media |

**Recomendación:** salir a productivo con la Opción 1 y dejar el agente Joule como
evolución (supervisor de excepciones y, si el cliente lo pide, aprobador). Ambas opciones
comparten la tabla de reglas, la clase de reglas, la tabla de control y la clase MIGO.

## Estado

- [ ] Prueba A/B de la decisión sobre `TS00800531` (`TASKPROCESSING` vs. `SAP_WAPI_DECISION_COMPLETE`)
- [ ] Mapeo de rangos de `ZMM_COD_PED` a niveles del Flexible Workflow (negocio)
- [ ] Firma de la clase MIGO y comportamiento de `COMMIT ENTITIES`
- [ ] Estado de `ZFMFI_CHECK_PO` (anticipo) y `ZMM_CREATE_COUPA_OC` (Coupa)
- [ ] Tipo de OC: materiales o servicios (lean services)
- [ ] Frecuencia mínima del Application Job y autorizaciones del usuario genérico

## Estructura prevista

```
src/            Objetos ABAP (abapGit), cuando inicie el desarrollo
docs/           Documentación de diseño y comparativo de opciones
```

---
Perceptio S.A.S. · Célula ABAP Cloud – Clean Core
