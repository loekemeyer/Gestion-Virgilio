# Relevamiento de lugares del depósito — 2026-09-11

Guía de lectura de **`relevamiento-lugares-deposito-20260911.xlsx`**, que está al lado de este
archivo. Escrita el **2026-09-14** con lo que dictó Luis.

---

## ⚠ LO PRIMERO: la planilla NO es la verdad de hoy

**Esto ya se trabajó, y las correcciones que salieron de ahí quedaron en el CÓDIGO y en la BASE,
no en el Excel.** La planilla quedó congelada en el día que se recorrió el depósito.

> Luis, 14/09: *"no la tomes como una revelación… ya la laburamos antes y se hicieron
> correcciones que quedaron en el código pero no en el excel"*.

O sea: **si la planilla y `GV_Lugar` / `GV_Lugar_Item` se contradicen, manda la base.** La planilla
sirve para entender *por qué* algo quedó como quedó, no para volver a decidirlo. Un par de casos
concretos, para que no se vuelvan a discutir:

| Lugar | Qué dice la planilla | Qué quedó, y por qué |
|---|---|---|
| **Ñ53** | `439E`, estado COINCIDEN, empresa `CH ⚠ LOKE` | **Es la góndola de CHEF del 439E.** Luis, 14/09: *"poné la Ñ53 al 439E de CH"*. Deja sin efecto una nota del 11/09 que decía "LOKE y libre". Cierra el **problema 88** (las 8 cajas de `439E CH` tenían stock y ningún lugar). |
| **M34 · M35 · M36** | `630, 631, 632` / `633, 634, 635` / `613, 636, 637, 858` | Van **con E** los cinco que tienen par: `630E`, `631E`, `634E`, `635E`, `636E`. Luis, 14/09: *"claramente relevaron esos sin la E, agregásela"*. El código con E es el que tiene nombre real en el maestro (Cucharón, Espumadera, Cuchara calada, Espátula lisa, Espátula); el pelado no tiene descripción. `632`, `633`, `613`, `637` y `858` no tienen par y quedan como están. |
| **Ñ53 · Ñ54** | empresa `LOKE` | Hoy `LOKE` no existe como empresa: *"Loke es línea de LK, no empresa aparte"* (Luis, 11/09). Ñ54 quedó LK; Ñ53 pasó a CH por lo de arriba. |

---

## Cómo está armada

Tres hojas:

- **`A resolver`** — 70 lugares donde las tablas viejas NO coincidían sobre qué hay ahí.
- **`Todos los lugares`** — los 880, con su estado: **739 COINCIDEN · 71 LIBRE · 38 conflictos de
  artículo · 32 de insumo**.
- **`Cómo leerlo`** — la consigna que se le dio a quien lo recorrió.

La columna que importa es la **U, amarilla: "¿QUÉ HAY REALMENTE?"**. La completó **quien caminó el
depósito**, y sólo en la hoja `A resolver`: **41 lugares contestados de 70**.

Los **29 sin contestar** son casi todos los **racks de insumos** (`R##AD/AT`, `V##AD/AT`), que
estaban excluidos a propósito, más `G06`, `L01`, `L02`, `L03` y `L04`.

Las columnas "…según" (qué tabla decía cada versión) están **ocultas** en el Excel. Se muestran
desde Formato → Mostrar columnas.

## ⚠ La celda U2 (A62) dice `355.06599999999997` y eso es un error de tipeo

**Son DOS códigos, no un número.** Se escribió `355, 066` —o sea el 355 **y** el 066— y Excel lo
tomó como decimal porque quien relevó usó un `.` en vez de la coma.

Y el 355 tampoco es: **va `335`**, que es lo que ya tiene `GV_Lugar_Item` (`335` + `066`).
Confirmado por Luis el 14/09. **A62 no hay que tocarla.**

Si alguna vez se automatiza la lectura de esa columna, **hay que leerla como texto**, nunca como
número, y revisar a mano cualquier celda que traiga un punto decimal.

---

## Para qué sigue sirviendo

Es la **única fuente que dice qué vio una persona parada delante de la góndola**. Sirve para:

- **Cerrar divergencias del problema 84.** De las 35 celdas donde el mapa y `Capacidad_Sector` no
  coinciden, la planilla contesta las 35. El patrón dominante: la **capacidad quedó pegada al
  código viejo y el mapa al nuevo** (`E10` 225→**312**, `F49` 574→**574E**, `G13` 823→**509**,
  `G15` 509→**256**, `J44` 335→**599E**, `M10` 702→**702E**, `C10` 071→**547**,
  `C02` 601E→**510T+581T**). No hay que elegir quién manda: hay que mover el `cajas_max`.
- **Descartar filas viejas de `Planimetria`.** Los códigos que alguien cargó ahí el 11/09 a las
  16:07–16:13 (231, 232, 233, 537, 567, 989E, 992E, 997E, 998E) apuntan a celdas que el recorrido
  ya había dado ocupadas por otra cosa: `G06`=208, `G07`/`G08`=355, `H60`=592E, `C01`=547,
  `A65`=396+556. **La única libre es `A60`**, y ahí sí entran 989E y 992E.

## Cómo volver a leerlo sin Excel

No hay `openpyxl` en el contenedor y el proxy no deja instalarlo. Un `.xlsx` es un ZIP con XML:
`xl/sharedStrings.xml` + `xl/worksheets/sheet*.xml`, y las celdas con `t="s"` son índices contra
la lista de strings compartidos. Con `zipfile` + `xml.etree` alcanza.
