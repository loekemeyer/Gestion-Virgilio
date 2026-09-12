# Diferencias Excel del usuario ↔ GP2 (audit por rubro)

Lista viva. Se va llenando a medida que revisamos cada rubro de Recepción de Insumos,
cruzando el Excel de conteo del usuario contra GP2. **Para consultar todo junto y decidir.**
Nada se aplica hasta que el usuario confirme. Cada ítem: qué dice GP2, qué dice el Excel, la duda.

> Recordatorio de fuentes: la **medida de los flejes vive en GP2** (`GP2.fleje_detalle`,
> `n_fleje` + `medida_mm`, la que muestra la web vía `recepcion_bundle`). El Excel del usuario es
> la fuente de verdad del negocio. La "casa del vecino" (`public.*`) solo para huecos.

---

## RUBRO: FLEJES (sector 5) + ALAMBRE (sector 13)
Excel: `Conteo_Gral_FLEJES_y_Alambre_VACIO.xls`. GP2: 56 flejes, 48 completos.

### A resolver (con duda para el usuario)

1. **Fleje 49 "Bisagra"** — medida 40 x 0,45.
   - GP2 (`IF12`): `discontinuo`, **sin proveedor**, **sin detalle/medida**, 0 recetas/rutas.
   - Excel (hoja *Listado Flejes*): **ACTIVO**, medida **40 x 0,45**, kg_x_uni ~0,0044 (Stock CD), consumo ~40/mes.
   - Proveedor: **NO figura en el Excel** — el 49 solo está en hojas sin columna de proveedor (Listado, Stock CD, Consumo); en las que traen proveedor (Pedido/FLEJES/Med Prov) no aparece. La medida 40 x 0,45 = idéntica al **fleje 27 "Virola Sacaf/Bisagra" (Basconia)** → apunta a Basconia (inferencia).
   - **DUDA:** ¿el 49 "Bisagra" es un fleje aparte del 27, o son lo mismo (duplicado)?
     - Aparte → cargar Basconia + medida 40 x 0,45 + sacar discontinuo.
     - Mismo que 27 → borrar el 49.

2. **Fleje 45 (`IF5`, código F5) = Pinza Ensalada** — GP2 **sin medida** en `fleje_detalle`.
   - GP2: id 199, "Fleje N° 45", código **F5**, proveedor **Aperam**, `medida_mm` = **null**.
   - Excel (cruzando por **código**, no por N°): F5 / cód 0145 = **Pinza Ensalada / Espumadera Inox, 117 x 0,8, Aperam** (hojas *Pedido Flejes*, *Stock Fleje Virgilio*, *Conteo Cervantes*).
   - **NO había contradicción** (corrijo la versión anterior): el 117x0,8 y el 123x0,8 son **dos flejes distintos** que la hoja *FLEJES* renumera:
     - Pinza Ensalada 117x0,8 = **F5 / N°45** operativas, pero *FLEJES* la llama **N°36**.
     - Cuchara Inox 123x0,8 = **F6 / N°43**, pero *FLEJES* la llama **N°45**.
   - **✅ HECHO (2026-09-08):** cargada `medida_mm = '117 x 0,8'` en `GP2.fleje_detalle` (componente 199). La pantalla ya la muestra.

3. **IE13 "Cremallera"** (proveedor GP2 = Importado) — GP2 **sin detalle**.
   - Excel: "Cremallera Espumante", medida **74,5 x 1,25** (JL Metales / Materiales San Roque).
   - Ojo: en el Excel el **fleje 80** se usa para DOS cosas — "C/Queso Alambre" (Ø4 x 380, Brawin) y "Cremallera Espumante" (74,5 x 1,25). Numeración pisada.
   - **DUDA:** ¿la cremallera lleva N° de fleje y medida 74,5 x 1,25? ¿proveedor real (Importado / JL Metales / San Roque)?

### Dato firme (listo para cargar cuando el usuario diga)

4. **IC3V** (Fleje 90 largo, Charcas) — GP2 **sin detalle**. Firme: **fleje 90 = N°16, Altrak** (igual que IC3, que sí lo tiene).
5. **FLEJE90_BRUTO** (Altrak) — GP2 **sin detalle**. Firme: **fleje 90 = N°16**.

### Estructural (no es un fleje puntual)

6. **CHAPA430** — GP2 sin detalle. Es **chapa** (1250×2500×0,8), no un fleje clásico. ¿Le cargamos medida igual o queda sin N°?
7. **El Excel tiene 86 N° de fleje; GP2 tiene 56.** Los ~30 de más son **casi todos el bloque de JL Metales** (PP Ajo, Aletas Cortas, Pinza Parrillera, Cuerpo Espumante, Descarozador Aceituna, Sacapizzero…) + materiales pendientes. **DUDA:** ¿son flejes NUEVOS a dar de alta, o JL Metales como **proveedor alternativo** de flejes que ya existen?
8. **Numeración inconsistente entre hojas del Excel y GP2** — el mismo material tiene distinto N° según la hoja (ej. "Arandela Chica Afila" = fleje 17 en una hoja, 11 en otra). Por eso el cruce por N° tiene ruido; conviene cruzar también por descripción + medida.

---

## RUBRO: PARTES PLÁSTICAS + BOLSAS (materia prima, sector 14)
Excel: `Conteo_y_Pedido_Sector_Plastico_VACIO.xls`, hojas **«Relev y OP Bolsas Plast VACIO»**
(el pedido) y **«Consumo x Cod Articulo»** (426 filas, de donde sale el consumo por material).
GP2: 12 materiales en sector 14, 48 partes plásticas con `material_id`, 189 artículos.
Cruce del 2026-09-11.

### 0. Las dos fórmulas — por qué los máximos NO coinciden ni pueden coincidir

| | Excel | GP2 (`recalcular_maximo_material`) |
|---|---|---|
| Horizonte resinas | **4 meses** de consumo | **2,5 meses** (`ubicacion.meses_stock`) |
| Horizonte Master Bach | **6 meses** | 2 % del máximo de plástico (≡ 2,5 meses) |
| Desperdicio | +4 % (ya dentro del `KG x Material + Scrp`) | +4 % (`inyeccion_desperdicio_pct`) |
| Redondeo | ninguno (kg con decimales) | hacia arriba a **bolsa entera de 25 kg** |
| Base de demanda | hojas «Est Madre LK/CH 10-25», 484 códigos, 287.308 uni/mes | `GP2.est_madre` (act. 2026-09-09), 405 códigos, 268.120 uni/mes |

Las dos fórmulas están **bien armadas por dentro** (verifiqué el Excel celda por celda: `Max 4 Mes
KG` = `Cons Mes KG` × 4 exacto en los 8 materiales, y × 6 en los 4 Master Bach). La diferencia de
horizonte sola explica un factor 1,6. **Hay que elegir uno de los dos** — hoy conviven.

Dato de capacidad: el máximo del Excel son **282 bolsas ≈ 19 pallets**; el de GP2, **161 bolsas ≈
11 pallets**. El tope físico de Virgilio son 20 pallets × 15 = 300 bolsas. Los 4 meses **entran**,
pero dejan 1 pallet de aire.

### 1. Máximo, material por material (kg)

| Cód | Material | Cons/mes Excel | Cons/mes GP2 | Máx Excel (4m) | Máx GP2 (2,5m) |
|---|---|---:|---:|---:|---:|
| 2405 | PP 2630 | 1.071,36 | 785,63 | 4.285,45 | 1.975 |
| 2465 | Alto Impacto AI 4600 | 272,95 | 424,34 | 1.091,81 | 1.075 |
| 2455 | ABS GP 22 | 112,40 | 85,15 | 449,59 | 225 |
| 2505 | Nylon Recuperado | 107,21 | 74,97 | 428,84 | 200 |
| 2425 | PS HF 555 | 71,18 | 67,94 | 284,71 | 175 |
| 2485 | Nylon c/Carga 25 % | 56,28 | 50,91 | 225,14 | 150 |
| 2435 | PE Baja 7147 | 17,42 | 16,43 | 69,69 | 50 |
| 2475 | Nylon Virgen | 6,29 | 5,78 | 25,17 | 25 |
| 1615 | Santo Prene 8211-35 | 2,70 | **0** (no existe) | **0** | — |
| 0265 | Master Bach Rojo | 11,96 | — | 71,77 | 50 |
| 0235 | Master Bach Blanco | 10,74 | — | 64,43 | 50 |
| 2595 | Master Bach Azul | 5,82 | — | 34,94 | 25 |
| 0255 | Master Bach Negro | 2,54 | — | 15,21 | 25 |
| | **Total resinas** | **1.717,80** | **1.511,15** | **6.860,40** | **3.875** |

### 2. Los dos errores reales (uno de cada lado)

**a) El Excel cobra DOS VECES la resina del mango del pelapapas.** `[Seguro]`
Las filas `C1A` «Mango 505 P/Calar.» y `C2A` «Mango 505 Calados.» son el **mismo artículo 505**,
las **mismas 30.000 uni/mes** y los **mismos 0,0054 kg**, y las dos suman a la columna PP:
168,48 + 168,48. Igual con `C1B`/`C2B` en el artículo 123 (11,996 + 11,996). El mango se inyecta
una vez y después Ester lo cala — el calado no come resina nueva. GP2 lo modela bien
(`PC2` «Mgo Pelapapa 505 Sin Calar (Ester lo cala → PC1A)», una sola vez).
→ **El Excel infla el PP en 180,48 kg/mes = 721,92 kg en el máximo (17 % del máximo de PP,
29 bolsas).**

**b) GP2 cuenta el Afila Caladas al doble y no cuenta el Cilindro Corta Queso — y los dos
errores casi se compensan.** `[Probable]`
- `PEP4` «Afila Caladas» está en la receta con **cantidad 1** por artículo (504, 114, 097);
  el Excel usa **`Uni x Art` = 0,5** en los tres. Con 0,5: 424,34 → **212,17 kg/mes**.
- El **cilindro plástico del Corta Queso** (Excel `B1`, AI, 0,007533 kg, arts 546 y 809) **no
  existe en GP2**: vive dentro de `C13` «Corta Queso Bastidor c/Cilindro», que es sector
  *procesado*, **sin `material_id` y sin `kg_x_uni`** → aporta 0 kg de AI. Real: **+60,32 kg/mes**
  (7.700 uni × 0,007533 × 1,04).
- 212,17 + 60,32 = **272,49** contra los **272,95** del Excel. Cierra con 0,46 kg de diferencia:
  confirma las dos cosas a la vez.
→ Hoy el máximo de AI (1.075 kg) parece correcto **por casualidad**. Corrigiendo las dos puntas,
a 2,5 meses debería ser ~700 kg.

### 3. Qué falta en el programa

| # | Qué falta | Material | kg/mes | Dónde |
|---|---|---|---:|---|
| 1 | **Cilindro Corta Queso** — `C13` sin `material_id` ni `kg_x_uni` | AI | 66,56 | arts 546 + 809 |
| 2 | **Art 186 «Pelador Mgo Ergo Loke»** — no existe como artículo; `PEP1` está sólo en el 099 | PP | 31,92 | — |
| 3 | **Art 809 «Corta Queso» CH** — no existe (mango chef + ojal + inserto) | PP | 22,70 | — |
| 4 | **Arts 332-337, 396** (espátula/espumadera/cucharón/cuchara/tenedor/enrulador Ac. Inox LK) | ABS+PP | 25,60 | capuchón + mango |
| 5 | **Arts 630-636, 864** (línea Chef Ac. Inox) | PP | 5,92 | mango chef + ojal + inserto |
| 6 | **`PA3` Muñeco Antiderrame** — existe pero sin material ni peso; **el material «Santo Prene 8211-35» no existe en GP2** | Santo Prene | 2,70 | art 299 |
| | **Total** | | **155,40** | |

Nota sobre el Santo Prene: el propio Excel tampoco lo pide — el renglón Simko va en **0** (`% Ocup`
0 %, `Max 6 Mes` 0), aunque la hoja de consumo sí le carga 2,70 kg/mes. Uno de los dos está mal.

**Recetas incompletas** (no pesan hoy porque la Est Madre CH de GP2 está casi en 0, pero el
máximo queda corto si Chef vuelve a producir): `PA19` Mangos Chef en 13 artículos contra 21 del
Excel · `PC6` Ojales en 4 contra 19 · `PB6` Inser. Neg. Espat en 2 contra 11 · `PB8B` Inser. Neg.
Batidor en 2 contra 4 (faltan 856 y 857).

**GP2 tiene 5 partes que el Excel no cuenta**: `PA4B` Mango Cuch Untar Rojo (19,89 kg/mes PP),
`PA5B` Mango Cuch Untar Chef (3,33), `PA9` Capuchón Mariposa 512 (5,94 PE, el Excel lo llama
`A11`), `PB5` Manguito Abrelat. Negro (0,15), `PV8B` Corta Torta Chef (0).

### 4. Pesos (`kg_x_uni`) que no coinciden

| Parte | Excel | GP2 | Δ |
|---|---:|---:|---:|
| `PC8` Cachas Azules | 0,016 | 0,023 | **+44 %** |
| `PC7` Inserto Neg. Canelones | 0,003717 | 0,005 | +35 % |
| `PB6` Inser. Neg. Espat | 0,003767 | 0,005 | +33 % |
| `PA18B` Capuchón Espátula | 0,0021 | 0,00175 | −17 % |
| `PA9` Capuchón Mariposa 512 | 0,003817 | 0,0035 | −8 % |
| `PC10` Mango LK Espátula | 0,01605 | 0,015 | −6,5 % |
| `PC11` Mangos ф 8 | 0,01575 | 0,015 | −4,8 % |
| `PA19` Mangos Chef | 0,013075 | 0,0137 | +4,8 % |

Al volumen del Excel, `PC10` solo son 15,9 kg/mes de PP de diferencia y `PC8` 7,4 kg.

### A decidir

1. **Horizonte del máximo: 4 meses o 2,5.** Hoy el Excel y el programa dicen cosas distintas.
2. **¿El Afila Caladas es 0,5 por artículo (un inyectado rinde 2) o 1?** De eso dependen 375 kg
   del máximo de Alto Impacto (15 bolsas).
3. **Los 17 artículos del punto 3** — darlos de alta en GP2, o confirmar que están discontinuados
   y sacarlos del Excel.

---

<!-- Próximos rubros: Cajas, Cartones, Remaches, Bombillas, Garage -->
