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
| Clean core | 100 % estándar | ≈ 80 % | ≈ 85 % | ≈ 85 % |
| Acceso a la tarea | No aplica | Wrapper (reenvía y decide) | Servicio OData + wrapper de B | Servicio OData + wrapper de B |
| Regla en USD | No, por moneda | Sí | Sí | Sí |
| Latencia | Inmediata | 1–5 min | 5–15 min | 5–15 min |
| Costo adicional | Ninguno | Ninguno | Licencia Build | Licencias + AI Units |
| Viabilidad | Alta, bloqueada | Alta | Media | Media–baja |

**Recomendación:** salir con la **opción B** y dejar la **A** como destino cuando se libere la
configuración del workflow (si el negocio acepta umbrales por moneda). La **C** es alternativa
si el negocio quiere mantener los rangos en BTP y ya tiene licencia de Build.

## Estado

Fase actual: **análisis y diseño de solución, pruebas de concepto**. No se construyen aún objetos
productivos; los programas de `poc/` son desechables ($TMP, solo DS4).

### Pruebas de concepto

| ID | Opción | Prueba | Estado |
|---|---|---|---|
| C1 | C, D | Destino BTP → DS4 (Cloud Connector / RISE) y GET a un servicio de S/4 desde BTP | Pendiente |
| C2 | C, D | Servicio OData de prueba: tareas pendientes + acción "aprobar" que reutiliza reenvío + decisión | Pendiente |
| C3 | C, D | Proceso programado en Build: frecuencia, tabla de decisión y acción con CSRF | Pendiente |
| C4 | C, D | Licencia y subaccount de Build Process Automation | Pendiente |
| D2 | D | Joule Studio y agente con 3 skills | Pendiente |
| D3 | D | Disparo desatendido desde proceso programado | Pendiente |
| D4 | D | Medir pasos por corrida y por OC (AI Units) | Pendiente |
| D5 | D | Determinismo de la decisión del agente | Pendiente |
| A1 | A | Condiciones disponibles en *Manage Workflows for Purchase Orders* (solo lectura) | Pendiente |
| A2–A3 | A | Liberación automática y multinivel en sandbox | Bloqueada |
| X1 | Todas | Mapeo de rangos de `ZMM_COD_PED` a niveles | Pendiente |
| X2 | Todas | ¿Una tarea por nivel o aprobadores en paralelo? | Pendiente |
| X3 | B, C, D | Auditoría acepta aprobación por usuario técnico | Pendiente |
| X4 | A | ¿Umbrales por moneda en lugar de USD? | Pendiente |

## Estructura prevista

```
src/            Objetos ABAP (abapGit), cuando inicie el desarrollo
docs/           Documentación de diseño y comparativo de opciones
```
