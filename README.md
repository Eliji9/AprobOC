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
| Regla | Rangos de monto por código de liberación (`ZMM_COD_PED`) | Rangos de monto por nivel de aprobación |
| Ejecutor | Usuario genérico creador del job | Según la opción elegida |

**Alcance:** solo la aprobación automática. Los procesos post-liberación (Coupa, anticipo,
MIGO) quedan fuera de alcance por ahora.

**Restricciones:**
- Los BAdIs del Flexible Workflow los gestiona otro equipo; solo la opción A depende de ellos.
- La configuración del Flexible Workflow está congelada por pruebas integrales, sin fecha de fin.

## Opciones evaluadas

| Criterio | A · Flexible Workflow con BAdIs | B · Job S/4 | C · Build + tabla de decisión | D · Agente Joule |
|---|---|---|---|---|
| Disponible hoy | No (config congelada) | Sí | Sí | Sí, con licencias |
| Toca el workflow | BAdIs + configuración | No | No | No |
| Clean core | ≈ 95 % | ≈ 80 % | ≈ 85 % | ≈ 85 % |
| Acceso a la tarea | No aplica | Wrapper (reenvía y decide) | Servicio OData + wrapper de B | Servicio OData + wrapper de B |
| Regla de monto | Sí (vía BAdI) | Sí | Sí | Sí |
| Latencia | Inmediata | 1–5 min | 5–15 min | 5–15 min |
| Costo adicional | Ninguno | Ninguno | Ninguno (licencia disponible) | Licencias + AI Units |
| Viabilidad | Alta, bloqueada | Alta | Media | Media–baja |

## Estado

Fase actual: **análisis y diseño de solución, pruebas de concepto**. No se construyen aún objetos
productivos; los programas de `poc/` son desechables ($TMP, solo DS4).

### Pruebas de concepto

| ID | Opción | Prueba | Estado |
|---|---|---|---|
| C2 | C, D | Servicio OData que expone lo validado en B (listar + aprobar) | Cubierta por B |
| C3 | C, D | Proceso programado en Build: frecuencia, tabla de decisión y acción con CSRF | Pendiente |
| D2 | D | Joule Studio y agente con 3 skills | Pendiente |
| D3 | D | Disparo desatendido desde proceso programado | Pendiente |
| D4 | D | Medir pasos por corrida y por OC (AI Units) | Pendiente |
| D5 | D | Determinismo de la decisión del agente | Pendiente |

## Estructura prevista

```
src/            Objetos ABAP (abapGit), cuando inicie el desarrollo
docs/           Documentación de diseño y comparativo de opciones
```
