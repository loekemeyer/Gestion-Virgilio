# Insumos — relevamiento para la botonera de categorías (RI / EI)

Base para la idea **7917**: agrupar el listado plano del modal de **Recepción de
Insumos (RI)** y **Entrega de Insumos (EI)** en una botonera de categorías.

**Fuente**: catálogo `Insumos` (39 filas) + todo `Movimientos_Stock` con
`deposito = 'insumos'` (el modal suma los dos: catálogo + cualquier código con
saldo ≠ 0 aunque no esté en el catálogo). **Corte**: 2026-08-04.
**Total**: **108 códigos** distintos — **65 operativos** + **43 duplicados/basura**.

Saldos tomados de `vista_saldos_insumos_x_unidad` (separados por unidad; el saldo
único de `vista_saldos_stock` mezcla kg/Uni/Bolsas/MC — ver idea 7382).

---

## El problema hoy

El modal (`showInsumoModal` → `insRender`, `index.html`) lista los 108 códigos
**planos, ordenados por código**, y la única forma de llegar a uno es el buscador
de texto. Para el operario eso significa escribir bien "polipropileno" o acordarse
de que el fleje 121 × 1,20 es el código `22`. Cuatro de las seis familias tienen
un patrón de **ubicación** que ya las identifica sola:

| Patrón de `ubicacion` | Familia |
|---|---|
| `V01`–`V16`, `V21`/`V22`, `R01`–`R18` (racks de insumos) | Fleje y alambre |
| `AF*` + `Q34` | Plástico en bolsas |
| `942P`–`948P` (el código es la ubicación) | Partes inox |
| Letra + número suelto (`X20`, `W1`, `O1`, `N7`, `Y4`, `Y15`, `Z2`) | Importados / espirales |

Es decir: la categoría **se autoderiva** del dato que ya está cargado, no hace
falta reclasificar a mano los 65.

---

## Categorías propuestas (6 botones)

| # | Botón | Códigos | Unidad típica |
|---|---|---|---|
| 1 | 🧵 **Fleje y alambre** | 32 | kg |
| 2 | 🧪 **Plástico** | 9 | Bolsas |
| 3 | 🍴 **Partes inox** | 11 | Uni / MC |
| 4 | 🪵 **Mangos** | 3 | Uni |
| 5 | 🌀 **Espirales** | 2 | MC |
| 6 | 📦 **Cajas y embalaje** | 8 | Paquetes / Uni |
|   | 🗑 _A depurar_ (oculta) | 43 | — |

---

### 1 · 🧵 Fleje y alambre — 32 códigos · se miden en **kg** · racks `V*` / `R*`

Los nombres son la **medida** (ancho × espesor), por eso el buscador por texto no
ayuda: el operario busca "el fleje de 121" y tiene que saber que es el `22`.
Ordenarlos **por medida** dentro de la categoría, no por código.

| Cód | Medida | Ubic. | Saldo (kg) |
|---|---|---|---|
| `5` | 38 × 0,55 | R4At | 256 ⚠ |
| `19` | 13,6 × 0,8 | R6At | 144 |
| `2615` | 13,65 × 0,8 | V9 At | 123,45 |
| `20` | 11 × 0,9 | V9 Ad | 635,2 |
| `24` | 42 × 1,5 | V10 Ad | 630 |
| `4` | 46 × 2,1 | V9 At | 0 |
| `69` | 18,5 × 2,5 | V11 Ad | 253 |
| `2` | 65 × 1,25 | V9 Ad | 1.286 |
| `81` | 66 × 0,70 | R11Ad | 157 |
| `1645` | 70 × 0,80 | R11At | 366 |
| `62` | 75,5 × 2 | R1At | 164 |
| `25` | 76,5 × 2,8 | R7Ad | 0 |
| `10` | 77 × 1,25 | V1 At | 0 |
| `64` | 78 × 2,50 | R8Ad | 608 |
| `72` | 82,5 × 120 | R6At | 560 |
| `13` | 84 × 1,75 | V14 Ad | 365 |
| `41` | 84 × 1 | — | 469 |
| `94` | 84 × 1,5 | — | 1.077 |
| `74` | 0,8 × 64 | R7At | 161 |
| `17` | 95 × 1,4 | R14At | 412 |
| `63` | 96 × 2,00 | R11Ad | 266 |
| `93` | 1,0 × 121 | R9Ad | 296 |
| `45` | 117 × 0,8 | R14Ad | 148 |
| `22` | 121 × 1,20 | V2 Ad | 1.483,95 |
| `44` | 130 × 0,9 | R13At | 189 |
| `92` | 132 × 1,50 | V11 At | 1.220,2 |
| `2745` | 168 × 0,80 | V10 At | 196 |
| `7` | 60 × 2,10 | V12 At | 664 |
| `56` | 58,5 × 125 | R9At | 873 |
| `2565` | 500 × 250 | R8At | 117 |
| `46B` | Alambre p/ espiral 520 (2,75 × 6) | V5 At | 859 |
| `90` | Alambre p/ filtro / N° 16 | R16Ad | 472,5 |

⚠ `5` tiene 256 **kg** y −256 **Uni**: alguien cargó la entrada en kg y la salida
en Uni. Es un error de unidad, no de cantidad.

**Sub-botón sugerido**: separar los 2 **alambres** (`46B`, `90`) de los 30 **flejes** —
son cosas distintas para el operario aunque compartan el rack.

### 2 · 🧪 Plástico — 9 códigos · se miden en **Bolsas** · sector `AF*`

| Cód | Nombre | Ubic. | Saldo |
|---|---|---|---|
| `PP` | Polipropileno (2630) | AF7 | 151 Bolsas + 24 Uni ⚠ |
| `AI` | Alto impacto | AF14 | 10 Bolsas + 34 Uni ⚠ |
| `NR` | Nylon recuperado | AF20 | 24 Bolsas |
| `NV` | Nylon virgen | AF5 | 23 Bolsas |
| `EBA` | EBA | Q34 | 20 Bolsas |
| `ABS` | ABS | AF3 | 18 Bolsas |
| `PS` | Poliestireno (h555) | AF13 | 8 Bolsas |
| `PE` | Polietileno (if33) | AF10 | 7 Bolsas + 4 Uni ⚠ |
| `N25` | Nylon con carga al 25 | AF11 | 1 Bolsa |

⚠ `PP`, `AI` y `PE` arrastran saldo en **Uni** además de Bolsas: el chip de unidad
arrancó en "Uni" y nadie lo cambió. La botonera puede **fijar la unidad por
categoría** (Plástico ⇒ Bolsas) y que eso deje de pasar.

### 3 · 🍴 Partes inox — 11 códigos

| Cód | Nombre | Ubic. | Saldo |
|---|---|---|---|
| `2955` | Cuchilla 505 Ac Inox (505C) | X20 | 142.000 Uni |
| `2815` | Cabezal Importado (H201Lever) | O1 | 26.400 Uni |
| `1685` | Cremallera Doble Aleta (523C) | W1 | 6.000 Uni |
| `4626` | Mariposa Mgo Plano (CB01) | N7 | 2.950 Uni |
| `TENEDOR AC. INOX.` | Tenedor | — | 4.464 |
| `945P` | Parte Espátula Calada Ac. Inox | 945P | 3.024 |
| `943P` | Parte Cucharón Ac. Inox | 943P | 1.968 |
| `948P` | Parte Espumadera Ac. Inox | 948P | 1.440 |
| `942P` | Parte Cuchara Ac. Inox | 942P | 1.152 |
| `944P` | Parte Cuchara Fideos Ac. Inox | 944P | 432 |
| `1546903` | Vastidor cortaqueso | Y15 | 222 MC |

⚠ Los cinco `9__P` tienen el grueso del saldo en `(s/u)` (sin unidad) y **−2 MC /
−5 Uni** cada uno: el conteo entró sin unidad y después se descontó con MC/Uni.
Es el mismo bug que arregla fijar la unidad por categoría.

### 4 · 🪵 Mangos — 3 códigos

| Cód | Nombre | Saldo |
|---|---|---|
| `666` | Mango Pelador 505 Rojo | 27.000 |
| `4496` | Mango Pelador Ergonómico Negro | 8.750 |
| `967H` | Mango Bambú | 8.256 |

### 5 · 🌀 Espirales — 2 códigos · se miden en **MC**

| Cód | Nombre | Ubic. | Saldo |
|---|---|---|---|
| `2805` | Espiral (TN H201Part) — 2000 u/MC | Y4 | 63 MC |
| `007` | Espiral (Chef) — 500 u/MC | Z2 | 18 MC |

### 6 · 📦 Cajas y embalaje — 8 códigos

| Cód | Nombre | Saldo |
|---|---|---|
| `0127` | Caja Nº 22 | 768 |
| `0037` | Caja Nº 2 | 0 |
| `0087` | Caja Nº 10 | 0 |
| `0107` | Caja Nº 13 | 0 |
| `0137` | Caja Nº 27 | 0 |
| `0157` | Caja Nº 29 | 0 |
| `CAJAS·NUMERO 1` | Caja Nº 1 | 0 |
| `FLEJE PROLIPROPILENO·SUNCHOS 12 MM` | Sunchos 12 mm | 0 |

Las cajas en 0 no son basura: son el maestro de cajas, se van a usar. Conviene
**normalizarlas** al formato `01NN` y darles la unidad `Paquetes`.

---

## 🗑 A depurar — 43 códigos que hoy ensucian el listado

Ninguno debería aparecer en la botonera. Son de tres tipos:

**(a) El mismo insumo cargado dos veces** — con el formato viejo `sector·descripción`
y con el código real. El conteo del 31/07 dio de baja el formato viejo pero los
códigos quedaron:

`1060500` · `1062500` · `1071500` · `1262500` · `1266500` · `605` · `695` ·
`7711600` · `ALAMBRE LARGO·11` · `FLEJE ESPIRAL·1` · `FLEJE·11.00 X 0.90` ·
`FLEJE·91 X 1,75` · `FLEJES CHEF·1.00 X 121` · `FLEJES CHEF·1.00 X 84` ·
`FLEJES CHEF·1.50 X 132` · `FLEJES CHEF·1.50 X 84` · `FLEJES LOEKE·1,00 X 121` ·
`FLEJES LOEKE·1.00 X 84` · `FLEJES LOEKE·1.50 X 132` · `FLEJES LOEKEMEYER·1.50 X 84` ·
`942P·942P` · `943P·943P` · `944P·944P` · `945P·945P` · `948P·948P` · `505C` ·
`CB01` · `H201` · `H201 PART` · `ESPIRAL CHINO`

**(b) Saldos negativos imposibles** — salidas de insumos que nunca tuvieron entrada
(son de junio/julio, antes del conteo). **Hay que netearlos**, si no la botonera va
a mostrar stock negativo:

| Cód | Saldo | Contra qué código real |
|---|---|---|
| `505C·CUCHILLA CHINA` | −16.000 Uni y −6 MC | `2955` |
| `H201PART·ESPIRALES CHINO TIERRA NATIVA` | −14.000 Uni | `2805` |
| `035·CERNIDOR DE HARINA` | −1.440 Uni | — |
| `4600·ALTO IMPACTO` | −925 Kg | `AI` |
| `PP 2630·POLIPROPILENO` | −100 Kg y −800 Uni | `PP` |
| `18.5 X 1.9·FLEJE MANGO PLANO` | −738 Kg | `1060500` |
| `102E·ABRELATAS MARIPOSA` | −720 Uni | — |
| `439E·COLADOR DE PASTA METAL` | −480 Uni | — |
| `76,50 X 2.80·FLEJE SACATAPITA` | −340 Kg | `25` |
| `SPIRAL CHEF·ESPIRALES CHINO` | −3.000 Uni | `007` |
| `523C·CREMALLERA` | −30 MC | `1685` |
| `809E·CORTA PIZZA` | −192 Uni | — |
| `FLEJES LOEKEMEYER·0.80 X 64` | −6 Uni | `74` |

**(c) Sobrante de la migración** — `CAJAS·NUMERO 1` tiene 80 Paquetes y −80 `(s/u)`,
que netean a 0 pero se muestran como dos líneas.

---

## Qué se implementó (v7.05)

1. **`Insumos.categoria`** + **`Insumos.ubicacion`** (migración
   `insumos_categoria_y_ubicacion`). Los 108 códigos quedaron categorizados; los 43
   del grupo 🗑 con `categoria = 'depurar'`.
   ⚠ `sector` **no** se reusó para la ubicación: en la app `sector` no nulo significa
   "insumo sin código, identificado por sector + descripción" (se dibuja con 📍).
2. **Se cargaron al catálogo los 62 insumos que sólo existían como movimiento.** Esto
   arregla un bug de paso: el modal sólo agregaba los códigos fuera de catálogo si su
   saldo era **≠ 0**, así que un fleje que llegaba a 0 **desaparecía** y había que
   re-crearlo para poder recibirlo. `4`, `10` y `25` estaban exactamente así.
3. **Chips de categoría** arriba del buscador (`insRender` + `insSetCat`), con el
   conteo real de cada una. Chip y buscador son **alternativos**, no se combinan: tocar
   un chip limpia el buscador y escribir limpia el chip. Así el operario nunca cae en
   "0 resultados" por estar parado en la categoría equivocada, y buscando ve **todo**
   (incluso lo que está a depurar, con su etiqueta de categoría en la fila).
4. **Unidad por defecto por categoría** (`INS_CATS[].uni`) — Fleje ⇒ Kg, Plástico ⇒
   Bolsas, Espirales ⇒ MC, Cajas ⇒ Paquetes, resto ⇒ Uni. La idea 7382 sigue mandando:
   si el insumo ya tiene saldo en **una sola** unidad, gana esa. Además los chips de
   unidad de cada fila ahora **dedupean sin distinguir mayúsculas** (`Kg` y `kg` eran
   dos chips distintos = dos saldos del mismo insumo) y ofrecen las unidades en las que
   el insumo **ya tiene saldo**.
5. **Orden dentro de la categoría**: los flejes por **medida** (`_insMedida`), el resto
   por saldo descendente.
6. El **alta nace con categoría** (selector en el formulario, arranca en la del chip
   activo) y el movimiento guarda la **ubicación física** en vez del sector.

Test: `tests/ins-categorias.cjs`.

## ⏳ Lo que quedó pendiente

**Netear los 13 saldos negativos** de la tabla de arriba. No se tocó porque **cambia
saldos de stock** y eso es decisión del dueño, no del refactor de la pantalla: el
asiento de ajuste tiene que ir contra el código real (igual que el conteo del 31/07) y
alguien tiene que confirmar la equivalencia de cada par. Mientras tanto quedan detrás
del chip 🗑 con el aviso, fuera del listado por defecto — **no** desaparecidos, porque
esconder un saldo negativo no lo arregla.
