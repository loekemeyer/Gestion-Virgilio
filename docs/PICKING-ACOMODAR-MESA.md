# Acomodar en la mesa después del picking — ¿el tiempo sigue a las cajas, a las NP o a las mesas?

**Luis, 03/10/2026:** *"desde que agarran la última caja del picking hasta que lo terminan y el tiempo desde terminarlo
hasta agarrar una nueva tarea, ese tiempo es el que le dedican a acomodar en la mesa las cajas que pickearon. Si hay mesa
disponible las ponen en la mesa; si no, las dejan en el carro y tardan menos. Y si un artículo tiene 50 cajas y va a un
solo cliente, no las ponen en la mesa: quedan en el carro o en el pallet. Lanzá a un agente que analice las últimas dos
semanas para ver si encuentra alguna correlación."*

Definición usada en los dos análisis: **cierre** = minutos entre el último PKC y el TP · **cola** = minutos entre el TP y
el inicio de la próxima tarea registrada del mismo legajo ese día (la misma regla de la cola de `gv_monitor_horas_operario_dia`,
v26.43) · **acomodar = cierre + cola**. Sólo lectura, nada escrito.

## 1. Dos semanas (19/09 al 03/10), desde la base — el agente

72 TP reales (sin los 4 TP copiados por movimiento de pedido, el TP cargado por SQL de E95A y el primer TP de E49A, que no
tiene PKC propios); 68 con cola medible. Acomodar suma **329 min contra 2.156 de picking EP→TP: 15 %**. Mediana **3,2 min**,
media 4,8, p90 11,3, máximo 20,0. Cierre mediana 1,3 · cola mediana 1,2. La «siguiente tarea» es EP 31 veces, AP 10, MG 8,
TAP 5, AT 4, FJ 3, PB 2, PC 2, RT 2.

| variable | Spearman con acomodar | con cierre | con cola |
|---|---|---|---|
| cajas de la tanda | 0,10 (p 0,43) | 0,02 | 0,07 |
| NP | **0,26 (p 0,03)** | 0,19 | 0,20 |
| clientes | 0,12 | 0,06 | 0,17 |
| cajas por línea | −0,10 | −0,22 (p 0,07) | −0,06 |
| línea más grande | 0,05 | −0,14 | 0,05 |
| líneas | 0,25 (p 0,04) | 0,28 (p 0,02) | 0,20 |
| mesas ocupadas (tandas con TP y sin TAP en ese instante) | 0,01 | −0,01 | 0,09 |

Regresión acomodar ~ cajas + NP + mesas (n = 66): **R² 0,008**; cajas −0,001 min por caja (p 0,66), NP +0,15 min (p 0,58),
mesas +0,14 min (p 0,70). Por grupos: 1 NP mediana 2,3 min (n 38) · 2+ NP 6,1 (n 28) · ≤ 10 líneas 2,1 · 11-30 3,6 · > 30 4,1.
Por mesas ocupadas, sin tendencia (0 → 3,3 · 3 → 6,4 · 7 → 1,9). Por operario: Moncayo (56 tandas) mediana 2,7 · Entrevista
(5) 8,4 · Tevez (3) 11,6 · Cartaya (3) 3,3.

«Pallet entero a un solo cliente» (1 NP, ≤ 6 líneas, ≥ 60 cajas): 5 tandas, 834 cajas — E35A 102 cj → 3,2 min · E29B 60 → 1,6 ·
E46B 75 → 7,0 · E78A 167 (un solo código) → 8,4 (toda cola) · E54A 430 → 1,1. Por caja: < 50 cajas 0,175 min/caja · 50-249
0,055 · ≥ 250 0,008.

**Veredicto del agente:** (a) cajas: no se sostiene (F33A, 908 cajas, acomoda en 1,3 min; F06A, 2 cajas, en 8,2). (b) NP: débil
(la única con señal, y es la misma señal que las líneas, rho 0,82 entre sí). (c) cajas por línea / línea más grande: el signo va
al revés y es chico — compatible con «el pallet queda en el carro», no alcanza para afirmarlo. (d) mesas ocupadas: no se
sostiene; la predicción «sin mesa tardan menos» exigiría correlación negativa y no la hay. (e) operario: es lo que más pesa.
Toda la hipótesis junta explica el 0,8 % del tiempo de acomodar; los casos largos (E50A 22,8 · F36A 20,0 · E62A 17,7 · E29F 15,2
· E17B 14,6 · E64A 13,1) no comparten cajas, NP ni mesas.

## 2. Sesenta días (04/08 al 02/10), sobre las 340 tandas de la calibración D17

321 tandas con cola «sig» ≤ 120 min. Acomodar mediana **5,7 min, 30 % del picking puro**; últimas dos semanas 3,0. Spearman
acomodar ~ cajas **+0,19**, ~ líneas +0,28, ~ cajas por línea −0,03, ~ línea más grande +0,08.

| cajas de la tanda | tandas | acomodar mediana | por caja |
|---|---|---|---|
| 0-30 | 61 | 4,0 min | 0,329 min |
| 30-80 | 97 | 6,1 | 0,126 |
| 80-150 | 76 | 6,4 | 0,057 |
| 150-400 | 66 | 6,4 | 0,030 |
| 400 o más | 21 | 7,5 | 0,012 |

Desde 30 cajas es un fijo de ~6 min por tanda. Pallet entero (1 línea, ≥ 50 cajas: D71A 333, D51A 208, E78A 167, E29B 60):
acomodar **1,3 min**. Por operario: 104 3,1 min · 277 5,2 · 122 5,7 · 504 **8,8** (49 % de su picking). **47 tandas con más de
15 min se llevan 1.249 de los 2.753 min** de acomodar (D52C 119 min de cola, D60E 46, D40D 43, E01C 38): eso no es mesa.

## 3. Lo que dice y lo que no

- **Se sostiene:** acomodar NO crece con las cajas (0,33 → 0,012 min por caja); el pallet entero no se desarma en la mesa.
- **No se sostiene:** que la mesa ocupada haga tardar menos (ni más). Y la NP suma poco (0,15 min por NP).
- **Lo que manda es el operario**, no la tanda: por eso la cola se le cobra al picking de cada uno (v26.43) y entra al puntaje
  por índice, no por m³.
- **No se puede medir hoy** dónde quedaron las cajas (mesa / carro / pallet) ni cuántas mesas hay. Para cerrarlo hace falta
  que el celular lo pregunte al dar el TP, o la cámara de las mesas de armado: plan en espera en `docs/PLAN-CAMARAS-MESAS.md`
  (Luis, 05/10).

Script del agente: `scratchpad/acomodar.py` de la sesión (Spearman con rangos promedio, OLS por ecuaciones normales); el de 60
días usa `docs/picking-d17/d17_tandas_dificultad.json` y los `d17_feat` de la calibración.
