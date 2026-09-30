# Lo que la Est Madre pide y GP2 no tiene (2026-09-13)

Salió de verificar que **todos los artículos ya están despiezados** (190/190 con receta). La Est
Madre tiene **405 códigos**; **185 cruzan** con un artículo de GP2 y explican el **82,5 % de la
demanda proyectada** (208.073 de 252.170 uni/mes). Este archivo es el otro pedazo: **los 220
códigos que no cruzan**, 44.097 uni/mes.

Se parten en dos, y sólo el primer grupo es trabajo:

| Grupo | Códigos | uni/mes | % de la demanda total | Qué es |
|---|---:|---:|---:|---|
| **A. Los que faltan de verdad** | **23** | **2.460** | **1,0 %** | Un tallerista los entrega. Se producen o se envasan acá. |
| B. Reventa e importado | 179 | 39.982 | 15,8 % | Se compran terminados y listos para vender. |
| C. Discontinuados / no se venden más | 15 | 460 | 0,2 % | Reemplazados por otro artículo, o vendidos una sola vez. |

> **Corregido tres veces el 2026-09-13.** Arrancó en **46 códigos / 10.504 uni/mes** y quedó en
> **23 / 2.460**. Se fueron: 438E, 437E, 566E y 584E (importados listos, −6.351), los cubiertos
> inox 332-337 y 630-637 (discontinuados, −425), 838E y 877E (son otros códigos de artículos que
> ya se compran, −45), 55215 (no se vende más, −35) y **los tres del pincel — 590E, 890E y 590ES
> (−1.195) —, que ya NO faltan: se dieron de alta en la base** (CONOCIMIENTO §4ct).
> **De los 2.460 que quedan, 1.038 son coladores que también se van a importar en poco tiempo**:
> el trabajo estable son ~1.400 uni/mes, y el más grande es el 565 Pinza De Hielo (534).

**El criterio de corte no es el volumen, es si alguien los fabrica**: un código sin despiece y sin
tallerista no tiene nada que modelar en GP2 aunque venda mucho.

---

## A. Los 23 que faltan de verdad

`partes` = cuántas líneas tiene su despiece en `public."Despiece x Articulo"` (0 = el vecino sabe
quién lo entrega pero tampoco lo despieza). `tallerista` sale de `public."Articulos Virgilio X
Tallerista"`; recordar que **«Carlos» del vecino es Alex Escalante en GP2** (CONOCIMIENTO §4).

| Cód | Artículo | uni/mes | Tallerista | partes |
|---|---|---:|---|---:|
| 565 | Pinza De Hielo | 534 | Manfer | 1 |
| 110 | Colador N°8 Loke — *José López, sólo le damos el cartón* | 384 | Lopez Jose | 1 |
| 561 | Pinza Grande LK | 324 | Pedernera | 2 |
| 111 | Colador N°10 Loke — *José López, sólo le damos el cartón* | 296 | Lopez Jose | 1 |
| 112 | Ø 16 Env. Loke — *el 16 no lleva nuestro cartón* | 160 | Lopez Jose | 0 |
| 113 | Colador N°20 Loke — *el 20 no lleva nuestro cartón* | 160 | Garcia | 0 |
| 323 | Rallador Cilíndrico Chico | 124 | Garcia | 2 |
| 439E | Colador Pasta | 122 | Garcia | 2 |
| 509 | Paleta Batidora | 104 | Carlos | 0 |
| 574 | Corta Queso Alambre | 88 | Lucho | 4 |
| 396 | Enrulador De Manteca | 80 | — | 2 |
| 440E | Colador Extensible | 36 | Garcia | 2 |
| 548 | Pincel Pastelero | 24 | Log/Fabr | 2 |
| 839 | Rallador Chocolate/Limón 14 cm | 10 | Garcia | 0 |
| 852 | Pinza De Hielo 14 cm | 7 | Manfer | 1 |
| 977 | Platos Individuales Pizza x 6 | 2 | Log/Fabr | 0 |
| 801 | Pinza Grande CH | 2 | Pedernera | 2 |
| 809 | Corta Queso Alambre Chef | 1 | — | 5 |
| 710 | Enrulador Manteca | 1 | Carlos | 2 |
| 456 | Espátula Lisa Nylon c/Mango | 1 | Log/Fabr | 0 |
| 717 | Cuchillo De Untar Acrílico x4 | 0 | Log/Fabr | 0 |
| 613 | Cuchara Calada 1 Pieza Ac. Inox | 0 | Carlos | 0 |
| 747 | Bombilla Coco Hexagonal | 0 | Log/Fabr | 0 |

**Cómo se lee esta tabla para decidir:**

- **El primero es el 565 Pinza De Hielo** (534 uni/mes, el 22 % del grupo). El que era primero,
  el 590E, **ya no está en esta lista: se dio de alta** junto con el 890E y el 590ES
  (CONOCIMIENTO §4ct).
- **Los coladores están de salida** `[usuario 2026-09-13, textual]`: *"Coladores, ahora pasan a ser
  importados dentro de muy poco, pero por ahora las hace Jose Lopez y entrega. Solo le damos el
  carton de cada uno (salvo 16 y 20cm de Chef y Loeke)"*. O sea: **de los coladores lo único que
  pone GP2 es el cartón**, y ni eso en los de 16 y 20 cm. Son 1.038 uni/mes (110, 111, 112, 113,
  439E, 440E) que **en poco tiempo pasan al grupo B**. **Recomendación: no modelarlos.** Además
  **José López no existe como tallerista en GP2** (los 13 cargados son Danica García, Alex
  Escalante, Fábrica, Cavallero, Lucho, Martín Cornejo, Maspoli, Gentile, Carlos Aguirre, IJUPA,
  Pettofrezza, Tierra Nativa y Blist-Pack), así que darlos de alta obliga a crear el tallerista
  para algo que se va a discontinuar solo.
- **`439E` Colador Pasta NO tiene nada que ver con el `441`** `[usuario 2026-09-13, textual: "439E
  no tiene nada que cer con 441"]`. **Queda sin efecto** la suposición anterior de que era el `441`
  Colador de Pasta Plástico (`GRJ25`) con otro código de venta: son dos artículos distintos. El
  439E sigue en el grupo A y le vale la recomendación de los coladores — no modelarlo, se va.
- **El bloque de Carlos (332-337, 630-637, 613, 710)** son los cubiertos de acero inox: 16 códigos
  que suman 426 uni/mes, casi todos con despiece cargado en el vecino (3 a 7 partes). Es el grupo
  más barato de migrar porque la receta ya existe del otro lado — **y ojo: GP2 ya tiene los
  941E-948E, que son cubiertos inox del mismo estilo**, así que hay componentes reusables.
- **Los `CH`** (630-637, 801, 809) son los mismos artículos de la línea Chef. Mismo despiece,
  distinto código de venta.
- **55215 (Palo de Amasar 40 cm, Tierra Nativa)** es el mismo producto que el **232** que GP2 ya
  tiene: acá el trabajo no es dar de alta un artículo, es decidir si es un alias.
- **838E y 877E no tienen ni descripción** en el vecino, pero el dueño ya los identificó: son otros
  códigos de artículos que se compran (ver grupo C). Ninguno de los dos es trabajo.

## El circuito del pincel — HECHO, ya no es trabajo pendiente

`[usuario 2026-09-13, textual]` *"590E se stockea en Virgilio en cajas x600uni, que se le mandan a
garcia para que las envase"*. Un solo insumo a granel que sale como **tres artículos**, y lo que
los separa no es la pieza sino el envase.

**Se dio de alta el 2026-09-13 y está verificado contra la base.** Los tres artículos (`590E` id
229, `890E` id 230, `590ES` id 231), los tres componentes (`PINCEL590` id 910 en Sector Plástico
con inventario en Virgilio, `CART590` id 911 y `CART890` id 912 en Sector Cartón), las recetas y
las **8 rutas** con el tallerista **Danica García (id 1)**. **El detalle completo está en
CONOCIMIENTO §4ct** — no repetirlo acá.

**Quedan dos cabos sueltos**, los dos esperando al dueño: **tres precios sin cargar**
(`PINCEL590`, `CART590` y `CART890`, no sólo el pincel — por eso los tres artículos dan $166,86,
que es el costo de la caja sola), y la **posición de estantería** de los dos cartones, que es de
donde sale su código definitivo (`CART###` es provisorio). Los dos cartones ya tienen **formato
Huevo**, marca (LOEKE / CHEF) y proveedor Pol `[usuario 2026-09-13]` — eran los únicos de la casa
sin formato, y sin eso la OC no les aplicaba los múltiplos.

## El cartón ya cargado del 574 y del 809

De los 152 cartones de GP2 con número en la descripción, **147 números son un código de artículo**.
Tres de las cinco excepciones son cartones de artículos que **GP2 no tiene**: `C1B` = Cartón 574,
`O6A` = Cartón 809 e `I3B` = Cartón 119. **El 574 y el 809 están en la tabla de arriba**: para esos
dos el cartón ya existe, lo que falta es el artículo. Mirarlo antes de darlos de alta desde cero.

## Lo que se importa y ya viene listo para vender

`[usuario 2026-09-13, textual]` *"438E es importado a partir de ahora y esta listo para la reventa.
Lo mismo 437E, 566E y 584E"*. **Los cuatro salen del grupo A**: no se fabrican ni se envasan acá.

**La única excepción es transitoria y del 584E**: quedan **1.200 unidades en Virgilio** que se le
mandan a García **para que las reenvase de cajas de 60 a cajas x6**, y esas cajas x6 **no son cajas
del sistema**. Es un trabajo puntual sobre stock viejo, no el circuito nuevo — pero mientras dure,
ese consumo de cajas no se puede registrar en GP2 sin dar de alta ese formato.

## C. Discontinuados y códigos que son otra cosa (2026-09-13)

`[usuario 2026-09-13, textual]` *"332/7 y 630/7 son discontinuos. Se reemplazaron por 941/8E"*.

- **Los 14 cubiertos de acero inox salen de la lista**: `332`, `333`, `334`, `335`, `336`, `337`
  (línea LK) y `630`, `631`, `632`, `633`, `634`, `635`, `636`, `637` (línea Chef), 425 uni/mes.
  **Los reemplazan los `941E`-`948E`, que GP2 YA TIENE** con su receta y su ruta. Era el bloque que
  este mismo archivo proponía migrar por barato: **ya está hecho, por otro camino.**
  > Ojo al pasar: GP2 tiene 941E, 942E, 943E, 944E, 945E, 946E y **948E**, y **el `947E` no existe**
  > `[usuario 2026-09-13, textual: "947E no"]`. El juego está completo: **no falta ninguno**.
- **`838E` es el `323E` con otro cartón** `[usuario 2026-09-13, textual: "838E=323E con otro carton,
  no 323 (sin E)"]` — el Rallador Mini de Chef; lo único que los separa es el cartón. Y **`877E` es
  el corta pizza, el mismo que el `809E` de Loeke** `[usuario]`. Los dos van al grupo B: ya se
  compran. **El `323` (sin E) Rallador Cilíndrico Chico es OTRA COSA**, sigue en el grupo A.
- **`55215`** (Palo de Amasar 40 cm, Tierra Nativa): *"se entrego solo una vez… y no se va a volver
  a vender"* `[usuario]`. Fuera. **Deja sin efecto la nota anterior** de que era un alias del 232.

## B. Los 179 de reventa e importado (39.982 uni/mes)

No hay nada que despiezar: se compran terminados. Se reparten así:

| | Códigos | uni/mes |
|---|---:|---:|
| Terminados en **E** — la línea importada (incluye 438E, 437E, 566E, 584E, 838E y 877E desde hoy; sin el 890E, que se fue al grupo A) | 83 | 38.992 |
| Terminados en **L** — los mismos, vendidos por Chef | 75 | 435 |
| Otros | 21 | 555 |

Los de más volumen, por si alguno no fuera reventa y haya que revisarlo: 529E Sacacorchos Doble
Impulso Acero (3.708), 102E Abrelatas Mariposa (3.108), 582E Salero 90 ml (2.828), 598E Pelador
Negro Dentado (2.328), 525E Sacacorcho Cabo de Madera (1.368), 809E Corta Pizza 6 cm (1.358), 816E
Pelador V (1.314), 106E Sacacorchos Doble Impulso Inox (948), 589E Pelador Mango Acrílico (860),
522E Sacacorcho Doble Aleta Premium (782). Las familias son sacacorchos, ralladores, peladores,
cortadores, pinzas y los utensilios de nylon/silicona con mango de madera o bambú (931E-937E,
951E-958E, 969E-971E, 981E-985E).

**Los 75 códigos con `L` suman 435 uni/mes entre todos**: son códigos de venta por Chef de esa
misma mercadería, no artículos distintos. No justifican trabajo propio.

---

**Consulta que regenera todo esto** (schema GP2; `public` se lee sólo para saber si el vecino lo
despieza o quién lo entrega, que es exactamente el uso permitido por la Regla 0):

```sql
with faltan as (
  select em.cod, em.proy_uni_mes from "GP2".est_madre em
   where not exists (select 1 from "GP2".articulo a
                      where regexp_replace(a.codigo,'^0+','') = regexp_replace(em.cod,'^0+','')))
select f.cod, round(f.proy_uni_mes) uni_mes,
       coalesce((select max(d."ARTICULO") from public."Despiece x Articulo" d where d."COD" = f.cod),
                (select max(av."Desc") from public."Articulos Virgilio X Tallerista" av where av."Cod_Art" = f.cod)) nombre,
       (select count(*) from public."Despiece x Articulo" d where d."COD" = f.cod) partes,
       (select string_agg(distinct av."Tallerista", ', ') from public."Articulos Virgilio X Tallerista" av
         where av."Cod_Art" = f.cod) talleristas
  from faltan f order by f.proy_uni_mes desc;
```


---

## Los tres del cruce contra loekemeyer.com — cerrados el 2026-09-13

`[usuario 2026-09-13]`: **573 y 517 son discontinuos**, no se dan de alta. Con eso los tres quedan
resueltos y ninguno entra a GP2:

| Cód | Artículo | Despiece | Por qué no entra |
|---|---|---|---|
| 573 | Bombilla Color Metalizado | **completo** (hoja Bombillas: caño 135 + resorte + niquelado + tapón + anodizado + corte = $578,98, con tiempos) | discontinuo. Sigue en `est_madre` con 52 uni/mes |
| 517 | Pinza Gastronómica | **completo** (Materiales Loeke: 2 flejes `517D` + tallerista GUILLE; Remaches: SR1+SR2+SR3) | discontinuo |
| 556 | Sacayerba | **no tiene** — la planilla lo costea sólo como envase (`Fab` con `E='xx'`) | sin despiece en ningún lado |

**Que un artículo tenga despiece en la planilla no lo hace vivo.** La planilla guarda el despiece de
cosas que ya no se venden, igual que la Est Madre arrastra discontinuados (§4cw). Ver CONOCIMIENTO §4de.


---

## Grupo A recalculado con las VENTAS REALES (2026-09-13)

Hasta ahora el grupo A se ordenaba por `est_madre.proy_uni_mes`, que es una **proyección**. Con
`public.sales_lines` (proyecto `kwkclwhmoygunqmlegrg`, facturas desde 2020) se puede ordenar por lo
que **realmente se facturó**. `uni/mes vendidas` = `cajas de 12 meses ÷ 12 × uxb`.

**Los 23 tienen ventas en los últimos 12 meses. Ninguno está muerto.**

| Cód | Artículo | Est Madre | **Vendidas** | Clientes | Última venta | Est Madre vs real |
|---|---|--:|--:|--:|---|---|
| 110 | Colador N°8 Loke | 384 | **705** | 2 | 2026-08-25 | 1,8× más |
| 565 | Pinza De Hielo | 534 | 431 | **121** | 2026-08-31 | ok |
| 574 | Corta Queso Alambre | 88 | **319** | 41 | 2026-08-17 | **3,6× más** |
| 111 | Colador N°10 Loke | 296 | 296 | 1 | 2025-10-17 | exacto |
| 561 | Pinza Grande LK | 324 | 246 | 75 | 2026-08-13 | *discontinuado* |
| 323 | Rallador Cilíndrico Chico | 124 | **217** | 71 | 2026-06-18 | 1,8× más |
| 112 | Ø 16 Env. Loke | 160 | 160 | 1 | 2025-10-17 | exacto |
| 113 | Colador N°20 Loke | 160 | 160 | 1 | 2025-10-17 | exacto |
| 839 | Rallador Chocolate/Limón | 10 | **114** | 20 | 2026-08-20 | **11× más** |
| 439E | Colador Pasta | 122 | 95 | 59 | 2026-08-27 | ok |
| 852 | Pinza De Hielo 14 cm | 7 | **80** | 22 | 2026-08-20 | **11× más** |
| 509 | Paleta Batidora | 104 | 53 | 19 | 2026-08-25 | la mitad |
| 396 | Enrulador De Manteca | 80 | 40 | 20 | 2026-08-17 | *discontinuado* |
| 440E | Colador Extensible | 36 | 32 | 53 | 2026-08-24 | ok |
| 801 | Pinza Grande CH | 2 | **16** | 11 | 2026-07-03 | **8× más** |
| 456 | Espátula Lisa Nylon | 1 | **14** | 8 | 2026-07-03 | **14× más** |
| 710 | Enrulador Manteca | 1 | **13** | 6 | 2026-07-06 | **13× más** |
| 548 | Pincel Pastelero | 24 | 12 | 2 | 2026-05-08 | ya entró como 590E/890E |
| 977 | Platos Individuales Pizza | 2 | **11** | 2 | 2026-06-03 | 5× más |
| 809 | Corta Queso Alambre Chef | 1 | **8** | 1 | 2026-08-06 | 8× más |
| 747 | Bombilla Coco Hexagonal | 0 | 6 | 2 | 2026-01-28 | la Est Madre decía 0 |
| 717 | Cuchillo De Untar x4 | 0 | 2 | 1 | 2026-01-27 | ídem |
| 613 | Cuchara Calada 1 Pieza | 0 | 1 | 1 | 2026-01-28 | ídem |

**Total real: ~3.030 uni/mes**, contra los 2.460 que daba la Est Madre. Sacando el **561** y el
**396**, que el dueño dio por discontinuados el 13-09 (*"no se fabrican más"*, aunque se siguen
facturando del stock): **~2.744 uni/mes en 21 códigos**.

### ⚠ Lo que esto cambia: la Est Madre SUBESTIMA la cola

Los que la Est Madre pone en **0, 1 o 2 uni/mes** son los que más se equivoca: `456` (14×), `710`
(13×), `839` y `852` (11×), `801` y `809` (8×), `977` (5×), y `747`/`717`/`613` que marca en **0**
aunque tienen facturas de 2026. **Justamente los que se venían descartando por chicos.**
El caso mas caro es el **574 Corta Queso Alambre**: la Est Madre le da 88 uni/mes y vendió el
equivalente a **319**, a **41 clientes**, con factura del 17-08-2026 — es el **tercero** de la
lista por venta real y figuraba décimo.

**Regla: para priorizar qué modelar, ordenar por `sales_lines`, no por `est_madre`.** La proyección
sirve para el máximo de stock (es lo que consume el motor); para decidir qué vale la pena, manda lo
facturado.


### 574 Corta Queso Alambre: sale de la lista (2026-09-13)

`[usuario 2026-09-13, textual: *"574 ya no se fabrica mas, es importado"*]`. Era el **tercero por
venta real** (319 cajas a 41 clientes, factura del 17-08-2026) y el que este archivo acababa de
ascender — **pero esas ventas son de un producto importado, no de uno que fabriquemos.** No hay nada
que modelar: **sale del grupo A.**

Con el 574 fuera, mas el **561** y el **396** (discontinuados el mismo dia), el grupo A queda en
**20 códigos ≈ 2.425 uni/mes** y el mas grande vuelve a ser el **565 Pinza De Hielo** (431 cajas,
121 clientes).

**Leccion, que es la misma de §4dl al reves:** `sales_lines` dice que algo **se vende**, no que
**lo fabriquemos**. Un importado vende igual. Para decidir si hay trabajo hacen falta las dos cosas:
que se venda **y** que salga de casa.
