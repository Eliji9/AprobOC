# AprobOC – Aprobación automática de órdenes de compra

Migración a **S/4HANA Cloud Private Edition** (ABAP Cloud / Clean Core) del job de ECC
`ZMM_APR_PED_BOT`, que libera automáticamente las órdenes de compra pendientes según
rangos de monto.

- Comparativo técnico de opciones: [`docs/index.html`](docs/index.html)
- Presentación visual para el equipo funcional: [`docs/presentacion.html`](docs/presentacion.html)
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

**Núcleo común en S/4 (B, C y D):** toda la lógica del job vive en una clase de S/4
(`ZCL_MM_PO_APPR_PROCESS`): busca las OC en aprobación con `I_PurchaseOrderAPI01`, evalúa la
tabla de reglas `ZMM_PO_APPR_RULE` y aprueba con el wrapper Tier 2 `ZCL_MM_WF_DECISION_API`
(búsqueda de work item y nivel, reenvío a `ZJOBPROCESOS` y decisión). En C y D se expone con
un servicio OData. Clean core del núcleo: Tier 1 + 1 wrapper Tier 2, 0 % Tier 3.

| Criterio | A · BAdIs del workflow | B · Job S/4 | C · Build | D · Agente Joule |
|---|---|---|---|---|
| Disponible hoy | No (bloqueada) | Sí | Sí | Sí, con Joule |
| Toca el workflow | BAdIs + configuración | No | No | No |
| Núcleo en S/4 | BAdI + regla | Común | Común + servicio | Común + servicio |
| Clean core en S/4 | 100 % Tier 1 + estándar | Tier 1 + 1 wrapper T2 | Igual que B | Igual que B |
| Disparador | El workflow | Application Job | Proceso de Build | Agente Joule |
| Componentes adicionales | Ninguno | Ninguno | Proceso + Action + destino | Agente + proceso + destino |
| Latencia | Inmediata | Frecuencia del job | Disparador + BTP → S/4 | Como C + agente |
| Costo adicional | Ninguno | Ninguno | Ninguno | AI Units por corrida |
| Viabilidad | Alta, bloqueada | Alta | Media | Media–baja |

## Estado

Fase actual: **análisis y diseño de solución, pruebas de concepto**. No se construyen aún objetos
productivos; los programas de `poc/` son desechables ($TMP, solo DS4).

### Pruebas de concepto

| ID | Opción | Prueba | Estado |
|---|---|---|---|
| C2 | C, D | Servicio OData que expone la clase del núcleo | Cubierta por B |
| C3 | C, D | Proceso programado en Build que llama a "procesar pendientes" | Pendiente |
| D2 | D | Joule Studio y agente con 3 skills | Pendiente |
| D3 | D | Disparo desatendido desde proceso programado | Pendiente |
| D4 | D | Medir pasos por corrida y por OC (AI Units) | Pendiente |
| D5 | D | Determinismo de la decisión del agente | Pendiente |

## Estructura prevista

```
src/            Objetos ABAP (abapGit), cuando inicie el desarrollo
docs/           Documentación de diseño y comparativo de opciones
```
