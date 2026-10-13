# AprobOC – Aprobación automática de órdenes de compra

Migración a **S/4HANA Cloud Private Edition** (ABAP Cloud / Clean Core) del job de ECC
`ZMM_APR_PED_BOT`, que libera automáticamente las órdenes de compra pendientes según
rangos de monto.

- Comparativo visual de opciones: [`docs/index.html`](docs/index.html)
- Diseño de la solución: [`docs/diseno-solucion.md`](docs/diseno-solucion.md)

## Contexto

| Tema | ECC (actual) | S/4HANA Private (objetivo) |
|---|---|---|
| Liberación | Estrategia clásica (`T16FS`) + `BAPI_PO_RELEASE` | Flexible Workflow (tarea `TS00800531`) |
| Regla | Rangos de monto en USD por código de liberación (`ZMM_COD_PED`) | Rangos de monto por nivel de aprobación |
| Ejecutor | Usuario genérico creador del job | Según la opción elegida |

**Alcance:** solo la aprobación automática. Los procesos post-liberación (Coupa, anticipo,
MIGO) quedan fuera de alcance por ahora.

**Restricciones:**
- No se usan BAdIs del Flexible Workflow.
- La configuración del Flexible Workflow está congelada por pruebas integrales, sin fecha de fin.

## Opciones evaluadas (sin BAdIs)

| Criterio | A · Config estándar WF | B · Job S/4 | C · Build + tabla de decisión | D · Agente Joule |
|---|---|---|---|---|
| Disponible hoy | No (config congelada) | Sí | Sí, con licencia | Sí, con licencias |
| Toca el workflow | Configuración | No | No | No |
| Clean core | 100 % estándar | ≈ 80 % | ≈ 100 % | ≈ 100 % |
| Regla en USD | No, por moneda | Sí | Sí | Sí |
| Latencia | Inmediata | 1–5 min | 5–15 min | 5–15 min |
| Costo adicional | Ninguno | Ninguno | Licencia Build | Licencias + AI Units |
| Viabilidad | Alta, bloqueada | Alta | Media | Media–baja |

**Recomendación:** salir con la **opción B** y dejar la **A** como destino cuando se libere la
configuración del workflow (si el negocio acepta umbrales por moneda). La **C** es alternativa
si el negocio quiere mantener los rangos en BTP y ya tiene licencia de Build.

## Estado

- [ ] Prueba de concepto de la decisión sobre `TS00800531` (`TASKPROCESSING` vs. `SAP_WAPI_DECISION_COMPLETE`) — B, C, D
- [ ] Mapeo de rangos de `ZMM_COD_PED` a niveles del Flexible Workflow (negocio) — todas
- [ ] Frecuencia mínima del Application Job y autorizaciones del usuario genérico — B
- [ ] Licencia y subaccount de SAP Build Process Automation — C, D
- [ ] Fecha estimada de fin de las pruebas integrales del workflow — A
- [ ] ¿El negocio acepta umbrales por moneda en lugar de USD? — A

## Estructura prevista

```
src/            Objetos ABAP (abapGit), cuando inicie el desarrollo
docs/           Documentación de diseño y comparativo de opciones
```
