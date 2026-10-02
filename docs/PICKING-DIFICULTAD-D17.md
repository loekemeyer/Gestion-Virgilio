# Tamaño y dificultad de una tanda de picking — esquema «Blackjack», con la cola

Datos: 340 tandas de picking de Virgilio, 60 días al 02/10/2026 (04/08 al 02/10), un picker por tanda, legajos de prueba afuera. El tiempo que se modela es el picking más la cola: desde que se abre el picking (EP) hasta que se cierra (TP), sin pausas declaradas (baño, comida, limpieza) y sin huecos de más de 5 minutos entre dos confirmaciones, **más los minutos sin registro que siguen al TP hasta la próxima tarea** (regla de Luis del 02/10: quien cierra el picking antes de acomodar las cajas en la mesa no se beneficia). Esa cola entra **topeada a 30 minutos** por tanda; el porqué está en (d). Los números salen de un ajuste reproducible (`d17_final/esquema_final_cola.py`); los costos por altura están ordenados y acotados por las medianas medidas en los mismos 60 días, porque las 340 tandas solas no alcanzan para separarlos de la parada.

Qué cambió contra el esquema anterior (sobre el picking puro, `d17_v3_netosh/`): la cola se suma al tiempo que se compara, y lo que se sumó cayó casi todo en el fijo por tanda y algo en la parada; las alturas quedaron donde estaban. Lo que no cambió: cajas topeadas a 30 por línea, arranque proporcional hasta 5 líneas y dificultad sin el arranque, las tres correcciones que verificaron los revisores de la corrida anterior.

## (a) Puntos por altura

1 punto = una línea de piso en las góndolas B a Ñ = 13 segundos. Lo que cuesta cada línea es por SACAR UNA CAJA de ahí; las cajas de más se cobran aparte.

| de dónde sale | A y P (5 alturas) | B a Ñ (4 alturas) |
|---|---|---|
| piso (1.ª) | 1,5 pts · 18 s | 1,0 pt · 13 s |
| 2.ª | 1,5 pts · 18 s | 1,5 pts · 21 s |
| 3.ª | 1,5 pts · 18 s | 1,5 pts · 21 s (escalera) |
| 4.ª | 4,0 pts · 51 s (escalera) | 2,5 pts · 35 s (escalera) |
| 5.ª | 5,5 pts · 72 s (escalera) | — |

| qué más se cobra | puntos | segundos |
|---|---|---|
| código con stock 0 en góndola al empezar (va, no encuentra; 111 de 130 líneas vuelven cortas) | 5,5 | 70 |
| línea fuera de góndola (racks, excedente, sin sector) | 2,5 | 35 |
| cada parada (módulo; el par enfrentado A-B, G-E, F-D, H-J, L-M es UNA) | 1,5 | 19 |
| cada 10 cajas (una línea cuenta hasta 30 cajas: el pallet entero no se pickea de a una) | 3,0 | 38 |
| arranque de la tanda: 5,5 pts por línea hasta 5 líneas | hasta 27,5 | hasta 341 |
| fijo por tanda (cerrar, acomodar en la mesa, pasar a lo siguiente: es la cola) | 11,0 | 142 |

Leído como Blackjack: una parada vale como 1,5 líneas de piso, una línea de la 5.ª de A como 5,5, una de la 4.ª de B a Ñ como 2,5; 10 cajas valen 3,0; cerrar la tanda vale 11,0. En minutos: puntos × 0,213. El esquema redondeado reproduce los minutos del ajuste con el mismo R² (0,538).

Tres cosas que hay que saber de esta tabla:

- Los costos de piso, 2.ª y 3.ª no los midieron las 340 tandas: paradas y líneas van casi juntas (correlación 0,965) y sin un ancla el ajuste pone todas las líneas bajas en 0 y carga todo en la parada (sin ancla: parada 33 s, piso 0, A5 175 s). El ancla son las medianas de segundos entre confirmaciones medidas en 60 días (piso 16 s, 2.ª 20-23, 3.ª 26, 4.ª 37-50, 5.ª 64). El dato sólo mueve de ahí lo que puede: A5 sube a 72 s, A2-A3 bajan a 18 (iguales al piso de A), R2 y R3 quedan en 21 y 21. Es una decisión explícita, no una medición; sin alturas el modelo predice igual (en (e)).
- La 3.ª de B a Ñ lleva escalera por regla y acá cuesta lo mismo que la 2.ª (21 s): el dato no ve la escalera de la 3.ª. Lo mismo A1 (18 s) por encima de R1 (13).
- «Sin dato de stock» (MX) y «fuera de góndola» (F) no tienen ancla y sueltos salen con intervalo bootstrap desde 0 (en las corridas anteriores MX fue de 50 a 102 s según el target). Los dos revisores pidieron atarlos: MX = 2 veces la 4.ª de B a Ñ (70 s: ir, buscar, no encontrar, volver) y F = la 4.ª de B a Ñ (35 s); es el promedio de lo que recomendó cada uno (MX 1,2 y 1,0 min; F 0,5 y 0,6). Atarlos cuesta 0,8 milésimas de R².

## (b) Tamaño y dificultad

**Tamaño** = minutos esperados para el operario promedio, cola incluida: fijo 2,37 min + arranque 1,14 por línea hasta 5 líneas + 0,32 min por parada + 0,063 min por caja (cada línea cuenta hasta 30) + la suma de los puntos por línea de la tabla. Reemplaza al m³ en el ritmo: **ritmo = tamaño ÷ tiempo real**, con el tiempo real = picking + cola topeada (1,00 = el promedio de estos 60 días; 1,20 = un 20 % más rápido).

**Dificultad** = (tamaño − fijo − arranque) ÷ cajas reales, en minutos por caja. Se saca el fijo y el arranque porque con ellos adentro una tanda de 1 línea y 2 cajas daba más de 2 min/caja y salía Pajosa siendo trivial (lo marcaron los revisores de las dos corridas); la cola es tiempo de tanda, no de caja, y va en el fijo. Niveles por terciles de las 338 tandas: **Fácil ≤ 0,181 · Normal ≤ 0,348 · Pajosa > 0,348** min/caja (113 / 112 / 113 tandas; sin cajas = Pajosa). Contra la corrida anterior los umbrales suben de 0,168 / 0,326 porque la parada quedó más cara.

Lo que la dificultad así definida mide, hay que decirlo: correlación de rangos con las cajas de la tanda −0,69 y con la fracción de líneas con escalera 0,20. Una tanda con muchas cajas por línea es Fácil casi siempre, con pocas es Pajosa casi siempre, y la altura corre la aguja poco. Si lo que se quiere es «qué tan pajosa es la tanda por el recorrido y la altura», el denominador tendría que ser líneas y no cajas: por línea los terciles serían 0,79 / 1,01 min/línea y el nivel deja de seguir a las cajas (correlación con cajas por línea 0,90, con la escalera −0,06). Es decisión de Luis (al final).

Ejemplo de pocas paradas con cajas altas, que queda Fácil como pedía Luis:

**E25A** (legajo 277, 16/09): 1 parada, 1 línea (A1 0 · A2 0 · A3 0 · A4 0 · A5 1 · R1 0 · R2 0 · R3 0 · R4 0 · MX 0 · F 0), 20 cajas reales (20 con tope), 0,092 m³. Fijo y arranque 3,5 min + paradas 0,3 + cajas 1,3 + alturas 1,2 = **tamaño 6,3 min**. Dificultad (6,3 − 3,5) ÷ 20 = **0,139 min/caja → Fácil**. Tiempo real 4,5 min (picking 4,2 + cola 0,3): ritmo 1,41 (tamaño ÷ real), contra 1,23 m³/h.

Ejemplo de Pajosa típica (10 líneas o más, dificultad cerca de la mediana de las Pajosas y tiempo real cerca del esperado):

**D22F** (legajo 122, 13/08): 22 paradas, 29 líneas (A1 3 · A2 2 · A3 0 · A4 0 · A5 0 · R1 6 · R2 9 · R3 3 · R4 2 · MX 1 · F 3), 51 cajas reales (51 con tope), 0,281 m³. Fijo y arranque 8,1 min + paradas 7,1 + cajas 3,2 + alturas 11,1 = **tamaño 29,4 min**. Dificultad (29,4 − 8,1) ÷ 51 = **0,418 min/caja → Pajosa**. Tiempo real 29,3 min (picking 17,7 + cola 11,6): ritmo 1,00 (tamaño ÷ real), contra 0,58 m³/h.

Todas las tandas de 1 o 2 paradas con alguna línea con escalera:

| tanda | par. | líneas | c/esc. | cajas | tamaño min | min/caja | nivel | real min |
|---|---|---|---|---|---|---|---|---|
| E29B | 2 | 2 | 1 | 60 | 9,1 | 0,074 | Fácil | 5,3 |
| D69I | 1 | 1 | 1 | 20 | 5,7 | 0,108 | Fácil | 4,8 |
| E25A | 1 | 1 | 1 | 20 | 6,3 | 0,139 | Fácil | 4,5 |
| D46G | 1 | 1 | 1 | 8 | 4,7 | 0,147 | Fácil | 7,0 |
| D50C | 2 | 5 | 1 | 18 | 12,1 | 0,227 | Normal | 12,3 |
| E08A | 2 | 2 | 1 | 5 | 6,4 | 0,350 | Pajosa | 4,1 |
| D09E | 2 | 2 | 1 | 4 | 6,5 | 0,456 | Pajosa | 9,5 |
| D47E | 2 | 2 | 1 | 4 | 6,1 | 0,364 | Pajosa | 14,1 |
| D47F | 2 | 2 | 1 | 3 | 7,3 | 0,896 | Pajosa | 3,6 |
| D47J | 2 | 2 | 1 | 3 | 6,3 | 0,542 | Pajosa | 1,0 |
| D41C | 1 | 1 | 1 | 2 | 4,3 | 0,399 | Pajosa | 8,8 |
| F06A | 2 | 2 | 2 | 2 | 7,0 | 1,161 | Pajosa | 9,5 |
| F02A | 2 | 3 | 1 | 1 | 7,6 | 1,849 | Pajosa | 1,2 |
| F04A | 1 | 1 | 1 | 1 | 4,2 | 0,736 | Pajosa | 2,4 |

Las que quedan Pajosa tienen entre 1 y 5 cajas: con pocas cajas cada parada y cada línea con escalera pesa mucho por caja, y eso es lo que el cociente mide. Ejemplo sintético: 1 parada, 4 líneas en la 5.ª de A, 40 cajas → tamaño 14,5 min, 0,191 min/caja → Normal.

Cómo cambia el ritmo medido en tamaño en vez de m³: en las dos tandas de arriba, por m³/h E25A hace 1,23 y D22F 0,58 m³/h (la primera parece 2,1 veces más rápida); por tamaño ÷ real son 1,41 contra 1,00: el m³ no ve las 22 paradas ni las 5 líneas con escalera de la segunda, ni los 12 min de cola que ahora se le cobran. Por operario (tabla en (f)): por m³/h el orden es 104 > 122 > 277 > 504 y por tamaño 104 > 277 > 122 > 504; por m³/h el primero hace 2,7 veces lo del último, por tamaño 1,8 veces. El m³ premia a quien lleva pallets enteros de pocos códigos; el tamaño cobra las paradas, la altura y la cola.

## (c) La altura cuando el artículo ocupa varias celdas

Altura dentro del módulo = ((celda − 1) mód alto) + 1, con la 1 abajo; A y P tienen 5 alturas, B a Ñ tienen 4; escalera en A y P desde la 4.ª y en las demás desde la 3.ª. Un código con celdas en una sola altura tiene altura conocida (2.938 líneas en las 338 tandas). Para un código con celdas en varias alturas la app no registra de qué celda salió la caja, así que se infiere con la regla de Luis: stock de góndola del código al abrir el picking contra la capacidad en cajas de cada celda, apilando el stock de arriba hacia abajo; la línea toma la altura MÁS BAJA que seguro tiene stock. Con 4 alturas de 100 cajas y 300 de stock, seguro hay en la 2.ª → 2.ª. Stock mayor que la capacidad total → piso. Es una cota a favor del operario: si había en el piso, la línea costó menos de lo asignado. Stock 0 o sin dato → clase MX (130 líneas, 111 de ellas cortas: el operario fue y no estaba).

Resultado: 4.583 líneas con altura inferida, 2.938 conocidas, 130 MX y 687 fuera de góndola. Por clase, conocidas / inferidas: A1 68/516 · A2 61/217 · A3 27/23 · A4 94/19 · A5 267/0 · R1 619/1.362 · R2 695/1.003 · R3 506/1.017 · R4 601/426. A5 es toda conocida y A1 casi toda inferida: dentro de una clase casi no hay con qué comparar.

Cómo cayeron los artículos grandes (líneas por altura asignada): 505 → R1 121, R2 105 · 501 → A1 150, A2 59 · 513 → R1 123, R2 79 · 504 → A1 161, A2 35 · 506 → A1 61, A2 112, A3 13 · 586 → R3 74, R4 45 · 544 → MX 1, R3 33, R4 105 · 510 → R2 2, R3 86, R4 19.

Prueba de que la inferida se comporta como la conocida: (1) un coeficiente extra por línea inferida, con todo lo demás en el modelo, da −7,6 s por línea con intervalo bootstrap −38 a 23 s: incluye el 0, pero el intervalo es más ancho que lo que cuesta una línea de piso, así que no prueba igualdad, sólo que no hay un sesgo grande. (2) Lo que sí la sostiene para el uso que importa: ajustando sólo con la mitad de tandas menos inferida (170 tandas, fracción ≤ 0,57) y prediciendo la otra mitad (168 tandas), el sesgo es −0,26 min sobre 27,2 reales (−1,0 %), con error menor que el del modelo completo (12,3 min), y los costos por altura salen parecidos en las dos mitades (A1 18/18 s · A5 71/66 · R1 14/15 · R4 36/36). Los revisores de esta corrida lo midieron por su lado con el mismo resultado: en B a Ñ, donde está el grueso de las inferidas, la inferida sale unos 4 s por línea más cara que la conocida, que es la dirección que se espera de una cota «la más baja que seguro tiene stock», y dentro del ruido. Vale para el tamaño y para el índice por operario; si cada altura cuesta lo mismo conocida que inferida lo va a decir el registro por paso.

## (d) La cola

La cola de una tanda son los minutos sin ningún registro entre su TP y la próxima tarea registrada del operario («sig», 323 tandas), o hasta la hora de salida si no hubo nada más («cap», 3); vale 0 si al cerrar ya tenía otro tramo abierto («cubierta», 14). Cuánto pesa: mediana 1,7 min, media 7,3, p90 11,0, p95 18,3; en total es el 19 % del picking puro. Cuatro tandas pasan de una hora: D40F (legajo 237) 519 min «cap» · D67D (legajo 600) 320 min «cap» · E37F (legajo 277) 196 min «sig» · D52C (legajo 504) 119 min «sig».

Las dos «cap» de horas (D40F: 5 líneas, 28 cajas, 10 min de picking y 8,6 h de cola; D67D: 36 líneas, 70 min de picking y 5,3 h de cola) son **outliers explícitos**: un operario que no registró nada más ese día no estuvo 8 horas acomodando 28 cajas. Con ellas adentro y la cola cruda el ajuste se rompe (R² 0,133, error 38 min, el fijo sube a 12 min). Quedan fuera del ajuste y en la lista de tandas van marcadas; su índice con la cola cruda sería 0,02 y 0,12.

Por qué el tope: la cola no depende de nada de la tanda. Regresada sola contra paradas, cajas y alturas explica el 5 % de su variación (correlación con paradas 0,14, con cajas 0,09, con líneas 0,13): es un fijo por tanda con mucho ruido, y es sobre todo un hábito del operario (122 8 % · 104 16 % · 277 26 % · 504 27 % de su picking puro). Sumada cruda al tiempo, le carga a la parada +0,18 min que son dos tandas con cola «sig» de 2 y 3 horas (E37F, D52C), y baja el R² de 0,55 a 0,42 sin mover las alturas: eso midieron los tres modelos y los dos revisores. Topeada a 30 min toca 7 de las 338 tandas, cuesta lo mismo en validación que cualquier otra forma de meterla (error contra el tiempo crudo 17,9 min; cola cruda 18,0; tope 60 17,9; picking puro más un fijo 17,9) y deja un esquema que todavía explica el picking (R² 0,538 contra 0,406 con la cola cruda).

A quién se le cargó, comparando con el mismo modelo ajustado sobre el picking puro de las mismas 338 tandas: de los 1.337 min de cola topeada, el fijo por tanda se lleva 739 (55 %: 0,19 → 2,37 min), la parada 424 (32 %: 15 → 19 s por parada), el arranque 90 y la caja 92; las alturas no se mueven (A5 74 → 72 s, R4 36 → 35 s). Lo que va a la parada no es de dos tandas: sin E37F y D52C la parada queda en 19 s. Con tope 60 en vez de 30 el fijo más arranque baja a 7,81 min y la parada sube a 21 s; el resto, igual.

## (e) Qué tan bien predice

| | R² | error típico (RMSE) | validación cruzada 10-fold | sin un operario (LOO) |
|---|---|---|---|---|
| esquema final (picking + cola topeada 30) | 0,538 | 13,2 min | 13,5 min | 14,5 min |
| el mismo esquema sobre el picking puro (corrida anterior) | 0,585 | 11,4 min | 11,7 min | 12,4 min |
| reajuste sobre picking + cola cruda (los tres modelos) | 0,419 | 17,8 min | 18,2 min | 19,0 min |
| sólo fijo + arranque + parada + cajas (sin alturas) | 0,532 | — | 13,5 min | — |
| modelo previo v26.25 (1,1 + 48 s/parada + 7 s/caja + 59 s/escalera) | −0,144 | 20,8 min | — | — |

Contra el tiempo con la cola cruda, cualquiera de las variantes predice con ±18 min; ese error no es del modelo, es de la cola, que ninguna variable del picking predice. El esquema final explica la mitad de la variación del picking + cola topeada con un error típico de ±13 min por tanda (mediana de tiempo real 27 min): el índice sirve para la suma de decenas de tandas, no para una suelta. El error está en las colas: E65A 99 reales contra 30 esperados · D49A 121 reales contra 53 esperados · D19C 90 reales contra 35 esperados · D24A 105 reales contra 53 esperados. El previo aplicado tal cual predice 8,2 min de más por tanda: sus 7 s por caja son 1,9 veces los 3,8 s que ajustan acá (fue medido contra otro target). Las alturas no mejoran la predicción contra «fijo + arranque + parada + cajas» (13,5 vs 13,5 min): lo que aportan es que el reparto entre parada, línea y altura tenga sentido y se pueda leer. Real ÷ esperado por tramo de líneas: 1-3 0,99 · 4-9 0,79 · 10-19 1,01 · 20-39 1,07 · 40+ 0,97 — las tandas de 4-9 líneas siguen saliendo sobrepredichas.

## (f) Índice por operario

Índice = suma de tamaños ÷ suma de tiempos reales (picking + cola topeada) de sus tandas. **1,00 = el promedio; más de 1 = más rápido**. La columna «picking puro» es el mismo índice sin la cola (corrida anterior, mismas 338 tandas) y «10-40 líneas» repite la cuenta sólo con tandas de ese tamaño, para comparar con el mismo mix. «Cola» es cuánto pesa su cola sobre su picking puro. Con menos de 10 tandas el número no se publica.

| legajo | nombre | tandas | cajas | cola | m³/h | índice | picking puro | 10-40 líneas |
|---|---|---|---|---|---|---|---|---|
| 104 | J. Moncayo «J. Colombia» | 85 | 12.707 | 16 % | 2,37 | 1,39 | 1,39 | 1,33 |
| 277 | J. Cartaya «Jhonny» | 81 | 10.020 | 26 % | 1,33 | 1,04 | 1,06 | 1,03 |
| 122 | Villalba | 98 | 12.075 | 8 % | 1,37 | 1,02 | 0,96 | 1,02 |
| 504 | Latronico | 51 | 5.384 | 27 % | 0,87 | 0,76 | 0,80 | 0,69 |
| 237 | F. Ortiz | 8 | 1.057 | 27 % | 1,65 | 0,96 (no vale: 8 tandas) | 1,00 | 0,74 |
| 8 | Farias | 3 | 721 | 138 % | 12,24 | 0,94 (no vale: 3 tandas) | 1,53 | — |
| 600 | (Entrevista) | 5 | 441 | 6 % | 0,78 | 0,70 (no vale: 5 tandas) | 0,64 | 0,65 |
| 94 | Tevez | 7 | 1.306 | 20 % | 0,52 | 0,55 (no vale: 7 tandas) | 0,59 | 0,44 |

(La consigna decía «104 Cartaya»; el padrón que se usó acá dice 104 J. Moncayo «J. Colombia» y 277 J. Cartaya «Jhonny».) La cola mueve el índice como pide la regla: 122, que cierra el TP con la tanda acomodada (cola 8 %), sube de 0,96 a 1,02; 277 y 504, con cola de un cuarto de su picking, bajan. Sacando cada operario del ajuste y prediciéndolo con los demás, los lentos siguen saliendo lentos y 104 rápido: el índice mide al operario, no el mix de tandas. 237 y 600 tienen una tanda menos que en la corrida anterior (los dos outliers).

## (g) Riesgos

- La cola sin tope rompe el índice: dos tandas «cap» valen 5 y 8 horas y una «sig» de 3 horas (E37F) mueve el índice de 60 días del 277 de 1,05 a 0,97. El tope de 30 min y que «cap» no corra hasta la hora de salida tienen que vivir en la regla de la base, no sólo acá.
- Los costos de piso, 2.ª y 3.ª vienen del ancla de medianas, no de estas tandas; el dato no distingue una parada de una línea, no ve la escalera de la 3.ª en B a Ñ, y MX y F están atados por decisión.
- El nivel de dificultad con cajas en el denominador ordena por cajas (correlación −0,69), no por altura; y el índice individual con menos de 10 tandas (8, 94, 237, 600) no se sostiene (sin un operario, el error del 94 es de 39 min por tanda).

## (h) Lo que falta medir

El registro por paso que arranca el lunes 05/10 (`GV_Picking_Paso_Evento`: mostrado, ok, faltan, sin stock, adelante, atrás) da el tiempo de cada línea por separado, y con eso se mide de verdad lo que acá está anclado: cuánto cuesta la parada contra la línea, el piso contra la 2.ª y la escalera de la 3.ª en B a Ñ, cuánto tarda un código con stock 0 (MX) y uno fuera de góndola (F), si la altura inferida cuesta lo mismo que la conocida por clase, y cuánto de la cola es acomodar en la mesa y cuánto es no registrar. Para que eso se pueda medir sin inferir hace falta cambiar la app en dos lugares: que el picking registre la CELDA de la que se sacó la caja (hoy sólo el código) y que el guardado a góndola registre en qué celda se puso; con los dos la altura deja de ser una cota y los costos por altura se recalculan con dato propio. Mientras tanto, el tope de 30 cajas por línea, el arranque hasta 5 líneas y el tope de la cola conviene fijarlos también en la app, que es donde se va a calcular el tamaño.
