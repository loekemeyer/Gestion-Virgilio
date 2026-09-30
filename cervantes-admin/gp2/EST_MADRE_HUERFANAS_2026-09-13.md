# Las filas de `est_madre` que no son ningún artículo de GP2 (2026-09-13)

Sale de la pregunta del dueño: *"1 Cuales"*, sobre las filas de `GP2.est_madre` sin artículo.

## ⛔ Primero, lo que NO es un problema

El cruce correcto **no es** `est_madre.cod = articulo.codigo`. `v_consumo_demanda` lo hace así:

```sql
join "GP2".est_madre em
  on regexp_replace(em.cod, '^0+', '') = regexp_replace(a.codigo, '^0+', '')
```

O sea **ya normaliza el cero adelante**. La Est Madre escribe `31`, `26`, `27`, `34`, `66`, `57`,
`58`, `59`, `99`, `97`, `70`, `55`, `43`, `53`, `54`, `52` y GP2 los tiene como `031`, `026`, … —
son **16 códigos, 28.812 uni/mes** (el más grande es el **031 Filtro de Café, 15.144 uni/mes**, el
artículo de mayor demanda de la casa) y **el motor los cruza bien**. Medido: el consumo del
`A1B` (Cartón 031) da exactamente 15.144.

**Un `join` ingenuo por código los cuenta como huérfanos y da 234 en vez de 218.** Si alguna sesión
futura ve "234", es que usó el join equivocado.

## El número real: **186** filas (eran 218 antes del pelado de la L)

> **Actualizado el 2026-09-13 a la tarde.** Despues de la migracion
> `la_venta_con_L_de_chef_suma_al_articulo_de_loeke`, los 32 codigos con `L` que cruzan con un
> articulo de GP2 **ya no son huerfanos**: su demanda suma al codigo base. De 218 quedaron **186**.
> El desglose de abajo es el de las 218 originales.

## El desglose (sobre las 218 de antes del pelado de la L)

| # | Grupo | Códigos | uni/mes | Qué hacer |
|--:|---|--:|--:|---|
| 1 | `E` = importado | 88 | 40.619 | nada: se compran terminados |
| 2 | Compra a tercero (`Costos` col C = `3ro`) | 11 | 2.090 | nada |
| 3 | **Fabricado (`Costos` col C = `Fab`)** | **16** | **1.369** | **lo único que puede ser trabajo** |
| 4 | Discontinuo (hoja Cajas col H) | 4 | 15 | nada |
| 5 | No está en ninguna hoja de la planilla | 84 | 585 | nada: ni la planilla los conoce |
| 6 | En la planilla, sin fabricante | 20 | 144 | nada |

De los 40.619 uni/mes del grupo 1, ninguno se fabrica acá.

## Los 16 "Fab", que son los únicos que importan — y 13 ya están resueltos

| Cód | Descripción | uni/mes | Estado |
|---|---|--:|---|
| 515 | Batidor Resorte | 486 | `[usuario]` *"No hay chance que se venda 486 uni de 515"* (§4cw). **Sigue en `est_madre`**: si se quiso borrar, no se borró |
| 561 | Pinza Grande Alambre | 324 | grupo A de `ARTICULOS_FUERA_DE_GP2` (tallerista Pedernera) — **abierto** |
| 332 | Espátula A. Inox. | 136 | discontinuo `[usuario 13-09]`, reemplazado por los 94xE |
| 336 | Cucharón Ac. Inox. | 84 | ídem |
| 396 | Enrulador De Manteca | 80 | grupo A — **abierto** |
| 335 | Cuchara Calada Inox. | 64 | discontinuo `[usuario]` |
| 334 | Cuchara Salsera Inox | 52 | discontinuo (mismo bloque 332-337) |
| 337 | Pinche Ac. Inox. | 48 | discontinuo `[usuario]` |
| 333 | Espumadera Ac. Inox. | 28 | discontinuo (mismo bloque) |
| 548 | Pincel Pastelero | 24 | el pincel ya entró a GP2 como **590E / 890E / 590ES** (§4ct); el `548` es el código viejo de la planilla |
| 513L | Pelador Mgo Metálico | 18 | **variante `L`** del 513, que ya está en GP2 |
| 546L | Corta Queso mgo Lk | 14 | **variante `L`** del 546, que ya está |
| 520L | Sacac Tipo Mozo Crom | 9 | **variante `L`** del 520, que ya está |
| 586L | Pelador Mgo Ergo Imp | 1 | **variante `L`** del 586, que ya está |
| 505L | Pelador Mgo Plast Imp | 1 | **variante `L`** del 505, que ya está |
| 525 | Sac Cabo Madera | 0 | 0 uni/mes |

**RESUELTO el 2026-09-13** (`[usuario]`: *"Ya lo explique lo 1 en GV, busca"*). Los códigos con
sufijo `L` son **el mismo artículo vendido por Chef** (un cliente de LK que pide por la página de
Chef, o una entrega en Tierra del Fuego): `505 → 505L`. **No se dan de alta.** La regla completa está
en `loekemeyer/Gestion-Virgilio` (`CLAUDE.md` §396) y en CONOCIMIENTO §4dj. Y no son 5: en
`est_madre` hay **75 códigos con L**, de los cuales **32 cruzan con un artículo de GP2** y suman
**301 uni/mes que GP2 hoy no cuenta**, porque el motor pela el cero de adelante pero no la L.

**561 y 396: discontinuos** `[usuario 2026-09-13: "2 discontinuos, no se fabrican mas"]`. Ojo: se
siguen facturando del stock (561 = 246 cajas a 75 clientes en 12 meses, última 13-08-2026;
396 = 40 cajas a 20 clientes, última 17-08-2026). Ver CONOCIMIENTO §4dk.

## Por qué borrarlas no arregla ningún número

`recalcular_maximos_insumos()` llega al máximo por la **receta del artículo**. Una fila de
`est_madre` sin artículo no entra a ninguna receta, así que **no mueve ni un máximo**. Medido el
13-09 al borrar el 573: el md5 de todos los máximos de `inventario` quedó **idéntico**.

El daño de estas filas es de **lectura**, no de cálculo: alguien mira `proy_uni_mes` y cree que eso
se vende. Es exactamente lo que pasó con el 515.
