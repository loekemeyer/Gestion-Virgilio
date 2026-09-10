# Qué stock falta contar para que la OC sirva (2026-09-08)

El gatillo de reposición (idea 7273, `Compras/OC_GP2.html` v1.21.0) compara el stock contra
`inventario.minimo`. Hoy casi no recorta nada, y la razón es una sola: **el stock está en cero**.
Esta es la lista de qué hay que contar, ordenada por lo que ahorra.

**Cómo se sacó el universo**: leyendo `GP2.oc_bundle` (`prosrc`), no inventando el criterio.
No es `estado_compra='compra'` — es `_es_sector_insumo(sector_id)` (o proveedor Charcas/Eclipse,
o proveedor que exista en `proveedor_insumo`) **con `estado_compra IS NULL`**, sacando lo que
produce un PS. El stock/mínimo/máximo salen de la fila de `inventario` que elige el `LATERAL`
del bundle (prioriza la ubicación del sector). Valorizado a TC 1530.

## El titular

| | |
|---|--:|
| Insumos que la OC pide | **236** |
| Con stock > 0 | 30 (12,7 %) |
| **En stock 0** | **205 (86,9 %)** |
| Plata que la OC propondría hoy solo por los que están en 0 | **ARS 251.293.300** |

## 1. Contar estos 40 códigos = 85 % de la plata

Los 40 primeros suman ~ARS 213 M de los 251 M. **26 de los 40 son flejes.**

Top 10 (la lista completa la sacó la consulta del informe; el orden es `sugerido × precio`):

| # | Cód | Descripción | Sector | Proveedor | Sugerido | ARS |
|--:|---|---|---|---|--:|--:|
| 1 | IE11 | Fleje N° 30 | Fleje | Brawin | 5.162 kg | 19.033.843 |
| 2 | IC7 | Fleje N° 2 | Fleje | Basconia | 3.094 kg | 17.041.752 |
| 3 | IF2 | Fleje N° 10 | Fleje | Basconia | 2.846 kg | 14.021.104 |
| 4 | IB3 | Fleje N° 6 | Fleje | Basconia | 2.576 kg | 13.321.526 |
| 5 | IA2 | Fleje N° 1 | Fleje | Basconia | 2.192 kg | 11.335.709 |
| 6 | IF3 | Fleje N° 22 | Fleje | Basconia | 2.000 kg | 9.853.200 |
| 7 | PC10 | Mango LK Espátula | Plástico | Pat Bet Plast | 53.112 uni | 9.612.741 |
| 8 | IB1 | Fleje N° 20 | Fleje | Basconia | 1.709 kg | 8.837.923 |
| 9 | IB6 | Fleje N° 24 | Fleje | Basconia | 1.535 kg | 7.562.331 |
| 10 | PC2 | Mgo Pelapapa 505 s/calar | Plástico | Pat Bet Plast | 112.736 uni | 7.109.132 |

## 2. Por sector: por dónde empezar

| Sector | Ubicación | Insumos | Con stock | **En 0** | ARS en 0 |
|---|---|--:|--:|--:|--:|
| Cartón | Sector Cartón | 96 | 10 | **86** | 33.854.076 |
| Fleje | Sector Fleje | 51 | 2 | **48** | **153.261.079** |
| Plástico | Sector Plástico | 41 | 6 | **35** | 33.816.524 |
| Remache | Sector Remache | 19 | 2 | **17** | 5.394.349 |
| Caja | Sector Caja | 12 | 5 | **7** | 8.855.911 |
| Bombilla | Sector Bombilla | 9 | 2 | **7** | 6.334.191 |
| Garage | Sector Garage | 3 | 0 | **3** | 8.832.160 |
| Procesado | (Plástico / Procesado) | 3 | 1 | **2** | 945.009 |

**Si el criterio es plata: Fleje.** 48 líneas y el 61 % del total.
**Si el criterio es cerrar el módulo: Cartón.** 86 líneas, pero pesa 13 %.

## 3. Lo que hay que corregir en la base (no es contar, es config)

**`ubicacion.meses_minimo` mal en 4 sectores** — rompe 52 de las 53 líneas con `mínimo ≥ máximo`.
Mientras esté así, esas líneas caen en `sin-gatillo` y se piden como antes:

| Sector | meses_mínimo | meses_stock | Rotos |
|---|--:|--:|--:|
| Plástico | 4 | 4 | 31 |
| Remache | 4 | 4 | 15 |
| Bombilla | 4 | 3 | 4 |
| Procesado (en Sector Plástico) | 2 | 1 | 2 |

Cartón y Fleje (4 vs 6) están **sanos**: 0 rotos sobre 136 líneas.

**9 líneas con `mínimo > máximo` cargadas a mano** (la peor forma: el gatillo dispara siempre):
PEP3, LLF8, PA10, A9, BOM8, BOM12, PA19, W8, EP10. `A9` (Caja N°22) es la única fuera de los
4 sectores mal parametrizados — ahí el mínimo se cargó a mano contra la fórmula.

**31 insumos sin máximo Y sin consumo**: la OC no los va a pedir **nunca**, tengas el stock que
tengas (`sugerido = 0` siempre). Los llamativos son `IE4` (Fleje N° 31, mínimo 108.000 sin
máximo), `IE5` (Fleje N° 32, mínimo 36.000) y `O6A` (Cartón 809, mínimo 5.184): tienen mínimo
cargado y el máximo quedó vacío.

## Orden sugerido

1. Contar los **40 códigos** del top (85 % de la plata; 26 son flejes).
2. Contar **Cartón** completo (86 códigos, la mayor cantidad de líneas).
3. Corregir **`meses_minimo`** de Plástico, Remache, Bombilla y Procesado.
4. Revisar las **9 líneas** con mínimo > máximo.
5. Decidir qué hacer con los **31 sin máximo** (hoy son invisibles para la OC).
