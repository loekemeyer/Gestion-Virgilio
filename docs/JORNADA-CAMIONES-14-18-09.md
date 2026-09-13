# Jornada de camiones 14–18/09/2026 — recálculo con las correcciones de datos aplicadas EN EL ANÁLISIS

**v16.72 · 2026-09-13.** Nada de esto está en la base: es la programación real del 14 al 18/09 (55 NP de
ISIS vía `gv_ppp_programacion_diaria` + 78 de la página vía `PPP_Web_Programacion`, 133 filas) pasada
por la **misma fórmula del front** (`_pppCamiones` → `_pppJornadaCam` → `_pppComputeErrors`, corridas
en `index.html` con Playwright), con las correcciones de `sql/PENDIENTE-jornada-datos-20260913.sql`
aplicadas **hipotéticamente**: Matiz (97889) en Zona 4, Cencosud ubicado, y las 4 direcciones web que
se copian de `PPP_Geo`. Y un segundo escenario con E11A (Luján) en la kangoo
(`sql/PENDIENTE-vehiculo-propio-20260913.sql`).

## Criterio

Un **camión = un viaje** depósito (Virgilio 2788) → paradas → depósito. Horas = km del recorrido
óptimo × 1,35 ÷ 28 km/h + 15′ por parada (`PPP_Web_Config`: `jornada_factor_ruta`, `jornada_km_h`,
`jornada_min_parada`). Tope **8 h** por viaje y por fletero-día; **`jornada_camiones = 2`** fleteros.
**Súper va solo** (Coto, Cencosud y Matiz — está en la lista de súper del front). **Retira no viaja.**
**Dirección repetida en dos tandas = una parada** (las 4 NP de Dapelo en Corrientes 3864 son una
bajada). Las rutas son las del front: *Sur / Centro / Oeste* (Zonas 1–4) y *Norte* (Zonas 5–7): no se
mezclan en un viaje. Un fletero puede hacer **dos vueltas** el mismo día si suman ≤ 8 h.

"Recomendado" = juntar en un viaje todas las tandas de la misma ruta del día mientras el recorrido
recalculado no pase de 8 h (se prueba de la más larga a la más corta); después, repartir los viajes en
fleteros de 8 h.

⚠ **NO hay capacidad de camión en m³ en ninguna tabla** (ni `PPP_Web_Config`, ni columna `gv_*`, ni
tabla `GV_*`): el único tope que existe es de horas. Los **9,25 m³ de Matiz** (NP 97889, un solo
pedido) no se pueden validar contra nada — si el camión no los lleva, hoy el sistema no lo sabe.

## Resultado por día

| día | como lo ve la vista hoy | horas / fletero (÷2) | aviso | recomendado (viajes) | fleteros |
|---|---|---:|---|---|---:|
| lun 14 | 4 camiones: D67 (11 tandas, 16 paradas, 52 km, 5,9 h) · D68 (3,1 h) · E01 (1,5 h) · E20 (1,3 h) = 11,8 h | 5,9 | no | **1 viaje** D67+D68+E01: 19 paradas, 89 km, **7,9 h** · E20A aparte (1 parada, 1,3 h — sumada pasa de 8) | **2** |
| mar 15 | 4: D68 (Zona 4, 117 km, 5,4 h) · E01 (3,2 h) · E03 (3,3 h) · **Coto E16A** (súper, 2,1 h) = 14,1 h · E19A Retira | 7,0 | no | D68B/C/D/H/J + E03B/C/D/E: 12 paradas, 127 km, **7,5 h** · E01B/C/E/F: 6 paradas, 48 km, 3,2 h · Coto solo 2,1 h | **2** (7,5 h · 3,2 h + 2,1 h en dos vueltas) |
| mié 16 | 6: D69 (5,4 h) · **E11A Luján (152 km, 5,7 h)** · E15 (1,4 h) · E17 Pilar (112 km, 4,5 h) · **Matiz D71A** (súper, 2,8 h) · **Cencosud D72A** (súper, 2,9 h) = **22,7 h** | **11,3** | **sí** | E11A+E17A+E15A: 5 paradas, 168 km, **7,3 h** · D69B–G: 9 paradas, 88 km, 5,4 h · Matiz 2,8 h · Cencosud 2,9 h | **3** (7,3 · 5,4 · 5,7) |
| mié 16 **con Luján en la kangoo** | 5 camiones = 17,0 h | **8,5** | **sí** | D69B–G + E15A: 11 paradas, 89 km, **5,9 h** · E17A Pilar: 2 paradas, 112 km, 4,5 h · Cencosud 2,9 h · Matiz 2,8 h | **3** (5,9 · 4,5 + 2,9 · 2,8) + kangoo |
| jue 17 | 2: E03 (1,9 h) · E12 (16 paradas, 5,5 h) = 7,4 h | 3,7 | no | **1 viaje** E03A+E12C–H: 18 paradas (2 sin ubicación), 47 km, **6,2 h** | **1** |
| vie 18 | 1: E12A (4 paradas, 39 km, 2,4 h) | 1,2 | no | 1 viaje, 2,4 h | **1** |

### Lo que sale de la tabla

1. **El único día que no entra es el miércoles 16**, y no lo arregla sola la kangoo: sin Luján siguen
   siendo 17,0 h de camión para 2 fleteros (8,5 h cada uno), porque **tres de los cuatro viajes son
   "solos"** (Matiz, Cencosud y Pilar 112 km) y no se pueden juntar. Se necesitan **3 fleteros** el
   16/09 o mover uno de estos:
   - **Matiz D71A (2,8 h, 9,25 m³) → jueves 17** (el jueves tiene un solo viaje de 6,2 h y el otro
     fletero libre): el 16 queda en 5,9 h + (4,5 h Pilar + 2,9 h Cencosud en dos vueltas = 7,4 h)
     → **entra con 2 fleteros**. Es una NP de ISIS con fecha 16/09: se mueve con
     `gv_ppp_tanda_mover` / override de fecha, si Thomas lo decide.
   - Cencosud D72A no conviene moverlo: es una OC de súper con fecha pactada.
   - E17A (Pilar, web) no tiene otro camión Norte esa semana al que sumarse.
2. **Lunes 14: E20A (Schell, 0,06 m³, exp. Azul Ferre 1455) es un fletero entero para una parada.**
   La misma dirección se visita el **martes 15** (E03C, El Bazar de la Economía, "Exp. Azul — Ferre
   1455"): pasando E20A al martes el lunes queda con **1 fletero** (7,9 h) y el martes no cambia
   (misma parada, +15′ nada — el viaje 1 pasa a 7,75 h).
3. **Martes 15 entra con 2** pero uno hace dos vueltas (clientes 3,2 h y después Coto 2,1 h).
4. Con las dos movidas (Matiz → jue, E20A → mar) la semana pasa de **9 fletero-días a 7** y ningún
   día avisa.

## Lo que cambian (y lo que NO) las correcciones de datos

- **Matiz zona 2 → 4**: no cambia el reparto de camiones. Matiz está en la lista de súper del front
  (`pppEsSuper` por cód), así que va en camión solo con cualquier zona; y Zona 2 y Zona 4 caen en la
  misma ruta (Sur/Centro/Oeste). Lo que corrige es el aviso "ZONA?" del panel, la etiqueta del camión
  y lo que lean `gv_ppp_web_camion_del_dia` / `gv_ppp_super_mezclado` (que miran la zona).
- **Cencosud ubicado**: hoy su viaje cuenta la parada (15′) pero **0 km** — el 16/09 se está
  subestimando en ~2,7 h. Con una ubicación aproximada (Panamericana a la altura de Tortuguitas,
  ±2 km, ver el PENDIENTE) el viaje da 75 km / 2,9 h. Como va solo, la aproximación no mueve la
  cantidad de camiones; sí mueve las horas del día.
- **Las 4 direcciones web copiadas de PPP_Geo** (Coto, Bazar Mandarin LK, Gastronomía González,
  Maravillas de Concepción): tres ya caían al paracaídas por cód y acertaban; **Bazar Mandarin LK
  (2447) caía en Clapera (Chef 2447, Rabanal 2866)** — el mismo número de cliente en las dos
  empresas — 2,5 km al sur. No cambia camiones; cambia el orden de carga.
- **Siguen sin ubicación**: Perez Zarate (4036, "Alem 385-Córdoba": es la dirección del cliente en
  Córdoba, falta el expreso) y Del Plastic (1996, "Taabre 1240" = Tabaré, typo). Cuentan la parada
  sin km: el jueves está **corto**, no largo.

## Cómo se calculó

Script de sesión (no está en el repo) que abre `index.html` headless, carga `_pppGeo` con las
ubicaciones reales de `GV_Geo_Cliente` / `PPP_Geo` resueltas con la misma prioridad que `_pppGeoDe`,
arma los pedidos como los arma `pppLoad` (np, cod, dirección, barrio, zona, tanda, fecha) y llama a
`_pppCamiones`, `_pppJornadaCam` y `_pppComputeErrors` sin tocar la fórmula. Los "viajes" recomendados
son la unión de camiones de la misma ruta recalculada con `_pppJornadaCam` (así la dirección repetida
cuenta una vez). Config leída de `PPP_Web_Config` el 13/09: camiones 2, factor 1,35, 8 h, 28 km/h,
15′ (coinciden con los defaults de `_pppJorCfg`).
