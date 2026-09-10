# Hernández Julio (ximpa) — qué recibe y qué devuelve (2026-09-09)

Proveedor de servicio **1149 - Hernandez Julio (ximpa)**, encabezado de su bloque en la planilla:
*"Serigrafia (una pasada)"*. Lista vigente 23/06/2026.

## 1. Lo que GP2 ya tiene cableado — 10 pasos con precio

Se compra la pieza **en blanco**, va a Julio, y **la que vuelve** es la que va al tallerista.

| Recibe | Devuelve | Qué es | $ | Artículos |
|---|---|---|--:|---|
| `A1` | `A4` | Mgo Plano 501 Serig | 19 | 501 |
| `B4B` | `B7` | Cpo Sacacorcho CH Serig | 19 | 730, 731 |
| `C2` | `C1` | Abrelata Pie Uña Serig | 18 | 500 |
| `PA10B` | `PA10` | Capuchón ⌀8 | 19 | 315 |
| `PA13B` | `PA13` | Capuchón Batidor LK | 19 | 515 |
| `PA18B` | `PA18` | Capuchón Espátula LK | 19 | 116, 542, 543, 546, 559, 562, 587 |
| `PA4B` | `PA4` | Mango Cuch Untar Rojo | 19 | 551 |
| `PA5B` | `PA5` | Mango Cuch Untar Chef | 19 | 878 |
| `PC15AB` | `PC15A` | Cuerpo doble aleta LK | 24 | 523 |
| `PEP2` | `PEP3` | Mango Pelador LK 586 | 24 | 586 |

**Metal**: A4, B7, C1. **Plástico**: los otros 7 (todos cargados el 08 y 09/09/2026).

## 2. Un paso SIN precio — el 499 está subcosteado

| Recibe | Devuelve | Artículo | Problema |
|---|---|---|---|
| `B12` | `Z22` (Llavero Pie) | 499 | tiene el paso de Julio pero **no tiene precio cargado** |

La hoja Tratamientos marca el 499 con serigrafía **$24** en "Cuerpo pie". Falta confirmar si ese
es el precio de este paso — en la lista de Julio no hay ningún ítem que diga "llavero".

## 3. Ítems de la lista de Julio que NO están asignados a ninguna pieza

| Cod | Ítem | $ | Última compra | Estado |
|---|---|--:|---|---|
| 1406 | Cuerpo Mariposa Uña Serigrafiado | 19 | 02/11/2023 | sin asignar |
| 1466 | Capuchón 10 Mm Serigrafiado | 19 | 03/05/2024 | sin asignar |
| 1496 | Manguito PP Plásticos Serigrafiado | 24 | 28/02/2025 | **el usuario dijo que NO va en ninguno** (09/09/2026) |
| 1536 | Capuchón Pela Pica Ajo R. Chica | 24 | 19/05/2025 | sin asignar |
| 1566 | Tapa Cucaracha Serigrafiado | 24 | 16/03/2026 | sin asignar |
| 1576 | Patitas | 24 | 21/04/2026 | sin asignar |
| 1586 | Serigrafiado Cuchara de Cocina | 28 | 21/04/2026 | sin asignar |
| 505 | PELADOR 505 | 67 | 21/05/2026 | **el usuario dijo que NO va** (08/09/2026) |
| 586 | PELADPR 586 | 67 | 21/05/2026 | sin explicar — el 586 usa el mango de $24, no este |

**Ojo con el 1406 "Cuerpo Mariposa Uña Serigrafiado"**: en GP2 existe `A8` "Cuerpo Uña CH
**Serigr.**", pero su paso lo hace **Jade a $127** (pintado), no Julio. El nombre dice serigrafía
y el proceso cargado es otro — o falta el paso de Julio además del de Jade, o el nombre miente.

## 4. Las que quedaron cerradas SIN serigrafía [usuario 2026-09-09: "no va en ninguno"]

`PC13` (701) · `PC14` (501) · `PB5` (101) — los tres manguitos abrelata.
`PC15B` (723) · `PEP1` (099) — CERRADOS el 2026-09-09: el usuario confirmó que los plásticos que
se lleva Ximpa son sólo los 7 en blanco (PA4B, PA5B, PA10B, PA13B, PA18B, PC15AB, PEP2), así que
estos dos **no llevan serigrafía**.

## Cómo se leyó esto

- La lista de Julio sale de `GP2.planilla_fila`, hoja `Lista de Precios`, **bloque**
  `1149 - Hernandez Julio (ximpa)` — el proveedor es el **título del bloque**, no el `cod_prov`
  de las columnas [usuario 2026-09-08].
- **La columna `Serigrafiado` de la hoja Tratamientos NO es la lista completa**: cubre 64 de los
  100 artículos, y ni el 551 ni el 878 figuran ahí aunque sí llevan serigrafía. Sirve para
  confirmar, nunca para descartar.
