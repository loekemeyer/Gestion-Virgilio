# Propuesta: armado de tandas por CERCANÍA REAL, no por tabla de conversión

**Pedido de Luis, 2026-09-16.** Seguimiento: Luis (Planify 3590) y Tomás González (Planify 3591).
Es una **propuesta**: no se aplicó nada. Todo lo medido abajo sale de la base el 16/09/2026.

---

## 1. Cómo se decide hoy dónde va un pedido

Es una cadena de traducciones, cada una con su tabla cargada a mano:

```
dirección/barrio ──► Zonas_Barrios (145 filas) ──────────────► "Zona 3 - CABA Oeste"
                 ──► GV_Barrios_Sector (109) ────────────────► sector "E"
sector           ──► GV_Sectores (14) ─────────────────────► camión "Capital"
zona (si no hay sector) ──► CASE 1,2,3=Capital · 4=Sur · 5=Oeste · 6,7=Norte
¿pueden ir juntos? ──► GV_Sectores_Vecinos (27 pares) + GV_Barrios_Pares (23 pares)
```

**~318 filas de tabla para responder una pregunta que es de distancia.** Ninguna de esas tablas
sabe dónde queda la parada.

**Y la base SÍ lo sabe:** `GV_Geo_Cliente` tiene **1.031 direcciones con lat/lng**, y el **94,1 %**
de las paradas programadas de los últimos 45 días (223 de 237) resuelven punto. Ese dato hoy se usa
**sólo** para el aviso de jornada del front (`_pppJornadaCam`): **el armado no lo mira nunca**
(0 funciones y 0 vistas de armado referencian `GV_Geo_Cliente`).

O sea: **armamos con una tabla de barrios y después medimos el resultado con kilómetros reales.**
Los dos criterios no son el mismo, y por eso el armado no puede mejorar lo que el aviso marca mal.

---

## 2. Qué sale mal — medido, no opinado

Ventana: programación viva de los últimos 45 días + 10 hacia adelante (web + ISIS, sin Krikos).
**88 tandas · 237 paradas · 12 días.**

| Síntoma | Medición |
|---|---|
| Tandas de **una sola parada** | **61 de 88** (web sin súper: 24 de 43) |
| m³ promedio por tanda | **0,704** (web: **0,620**) contra tope 1,00 y mínimo deseable 0,60 |
| Tandas con **diámetro > 5 km** | 11 · con **> 10 km**: 3 · **máximo 13,2 km** |
| Paradas que **no tienen sector** (caen al fallback `~grupo de zona`) | 12 |
| Tandas que mezclan más de un sector | 12 |
| Pares de tandas del **mismo día y mismo camión** a **≤ 3 km** que suman **≤ 1 m³** | **14** (4 de ellos a menos de 600 m) |

**Camión-día flacos** (un fletero entero para casi nada):

| día | camión | tandas | paradas | m³ |
|---|---|---:|---:|---:|
| 16/09 | Capital | 1 | 1 | 0,238 |
| 17/09 | GBA Norte | 2 | 2 | 0,319 |
| 21/09 | GBA Norte | 1 | 1 | 0,325 |
| 14/09 | GBA Sur | 1 | 1 | 1,184 |
| 09/09 | GBA Oeste | 1 | 2 | 0,523 |

Es exactamente lo que ya había cazado el informe de jornada del 13/09 (*"E20A es un fletero entero
para una parada"*), pero pasa **todas las semanas** y nadie lo mira hasta que el día explota.

**Y el centinela ya está en rojo hoy:** `gv_ppp_tanda_camion_mezclado` devuelve **una fila**:
`D69F` del 21/09, con Jazquel (Zona 2, Capital) y Cosentino / González Pellegrini (Zona 5, GBA
Oeste) en la **misma tanda**.

**Un caso más, de la misma familia que ya se tapó cuatro veces:** `gv_ppp_web_camion` **no consulta
`GV_Supers`**. El 21/09, Dorinka (E11B) sale etiquetada como camión *GBA Oeste*, igual que E20A y
E20B, que son clientes comunes. A nivel **tanda** la regla del dueño se respeta (cada uno en la
suya); a nivel **camión** quedan bajo la misma etiqueta. El centinela `gv_ppp_super_mezclado` no lo
ve porque define "camión" como **los 3 primeros caracteres del código de tanda** (`E11` ≠ `E20`),
no como la etiqueta geográfica. Dos definiciones distintas de "camión" conviviendo.

---

## 3. La distinción que hay que hacer antes de tocar nada

> **La tanda es la unidad de PICKING. El viaje es la unidad de LOGÍSTICA.**

Dos tandas de 0,3 m³ a 300 m una de otra (E12O / E12Q, 21/09) **no son un problema de reparto**:
las dos van en el mismo camión y el fletero hace las dos paradas igual. Son un problema de picking
(dos armados en vez de uno).

Lo que **sí** cuesta plata es:
1. Mandar un camión a GBA Norte por **una parada de 0,3 m³** porque ese pedido cayó ese día.
2. Que una tanda tenga paradas a 13 km (dos puntas del recorrido en el mismo armado).
3. Que un día junte cuatro viajes "solos" y no entre en 2 fleteros (el mié 16/09: **22,7 h**).

**Conclusión: la optimización geográfica se juega en QUÉ DÍA se entrega cada pedido, no en cómo se
parte el picking.** Hoy el día se elige por cupo de m³ + anticipación mínima, y el único criterio
geográfico (`gv_ppp_web_dia_camion`) compara **el número de zona**, que no dice nada de si el camión
pasa cerca: "Zona 5" es Ramos Mejía y también Luján, a 60 km.

---

## 4. El cambio propuesto

Siete reglas. Todas con interruptor en `PPP_Web_Config`, todas reversibles, ninguna borra las tablas
actuales.

### R1 · Punto obligatorio, con cascada y sin inventar

`gv_ppp_web_punto(cod, direccion, barrio, zona)` → lat/lng + `precision`:

1. `GV_Geo_Cliente` por dirección exacta → `exacta`
2. `PPP_Geo` por dirección → `exacta`
3. `GV_Geo_Cliente` por código (la más usada) → `cliente`
4. centroide del barrio (de los puntos ya geocodificados de ese barrio) → `barrio`
5. sin punto → `null`

**Sin punto no se arma solo:** el pedido queda en *A Programar* con el motivo `sin_ubicacion`, o —si
`geo_fallback_tabla = 1`— cae al sistema de sectores de hoy. Nunca se adivina: hoy Cencosud viaja
con 0 km y el día se subestima ~2,7 h.

### R2 · Compatibilidad = distancia, no tabla

`gv_ppp_web_compat` pasa a: dos paradas pueden ir en la misma tanda si

- `dist(a,b) ≤ radio_tanda_km` **y**
- el **diámetro** de la tanda resultante ≤ `tanda_diam_max_km`.

`GV_Barrios_Pares` **queda como override en los dos sentidos**: `permitido = false` prohíbe
aunque la distancia dé (*"Norte y Sur de Capital nunca juntos"*) y `permitido = true` fuerza
aunque no dé (*"Boedo pega con Pompeya por Av. Sáenz"* — son 3,3 km entre centroides, ver §12).
`GV_Sectores_Vecinos` queda **sólo como veto**. Lo que se retira es el uso **positivo del
sector**: hoy dos
paradas a 400 m en sectores que nadie cargó como vecinos **no se juntan**, y dos paradas a 11 km en
sectores marcados vecinos **sí**. Medido sobre los centroides de sector: los pares "vecinos" van de
2,6 a **11,4 km**, y los "no vecinos" arrancan en **5,9 km** — la tabla y la distancia no coinciden.

Valores de arranque propuestos: `radio_tanda_km = 3,5` en CABA y `5,0` en GBA (`radio_tanda_km_gba`),
`tanda_diam_max_km = 6,0`.

### R3 · El camión deja de ser la llave y pasa a ser el resultado

Hoy el camión se calcula por `CASE` sobre el número de zona y decide todo. Propuesta: la tanda se
arma por cercanía y **el camión es la etiqueta del clúster** (la del sector/zona del centroide, para
la pantalla y para el reuso del código `LETRA+NN`). "Una tanda = un camión" deja de necesitar guard:
sale por construcción, porque un clúster de 6 km de diámetro no tiene dos camiones. El caso D69F
(Jazquel en dos camiones) no puede volver a existir.

**Y `gv_ppp_web_camion` pasa a consultar `GV_Supers` primero** (súper → camión `Super`), que es lo
que le faltó en las cuatro correcciones anteriores.

### R4 · Cerrar la tanda por m³, cerrar el DÍA por horas de ruta

Llevar la fórmula del front al backend: `gv_ppp_ruta_horas(puntos[])` = recorrido depósito →
paradas → depósito por vecino más cercano, × `jornada_factor_ruta` (1,35) ÷ `jornada_km_h` (28) +
`jornada_min_parada` (15′) por parada. **Es la misma fórmula que ya corre en `_pppJornadaCam`**: hoy
vive sólo en JavaScript y sólo avisa después de que el día está armado.

Con eso, el armado deja de agregar una parada a un día cuando
`horas(camión, día) + parada > jornada_horas_max` (8 h) o cuando el día ya tiene
`jornada_camiones × jornada_horas_max` horas totales. Esa parada se va al día siguiente que dé.
**El mié 16/09 (22,7 h para 2 fleteros) no habría pasado el guard.**

### R5 · El día se elige por dónde pasa el camión, no por el número de zona

`gv_ppp_web_dia_camion` cambia el criterio: en vez de *"¿hay una tanda con el mismo número de
zona?"*, **"¿hay un camión ese día cuyo centroide está a ≤ `radio_dia_km` (arranque: 8 km en CABA,
15 km en GBA) de esta parada, y le entran las horas?"**. Ese es el cambio que convierte al armado en
optimización logística de verdad: un pedido de Pilar espera al día en que ya va el camión a Pilar, en
vez de fabricar un viaje propio de 112 km.

Techo: no se puede posponer más allá de `dia_espera_max_habiles` (arranque: 3 días hábiles después
del mínimo). Un pedido nunca queda esperando "el camión que nunca llega".

### R6 · El orden de la tanda es el orden de la ruta

Una vez que el backend calcula el recorrido (R4), **la tanda se ordena por orden de parada** y la
carga del camión sale al revés (la última parada se carga primero). Hoy el orden dentro de la tanda
es el que quedó. Esto no cambia ninguna regla: es la salida de algo que ya se calculó.

### R7 · Centinelas, o no se sabe si mejoró

Tres vistas nuevas, del mismo estilo que `gv_ppp_tanda_camion_mezclado`:

- `gv_ppp_tanda_dispersion` — diámetro en km por tanda; vacía = ninguna pasa `tanda_diam_max_km`.
- `gv_ppp_camion_jornada` — horas estimadas por camión-día y por fletero; avisa > 8 h **antes** del día.
- `gv_ppp_fusion_perdida` — pares de tandas del mismo día/camión a ≤ radio que quedaron separadas.

---

## 5. Lo que NO se toca (guardarraíles)

Ninguna regla del dueño se negocia; el cambio es **cómo se calcula la cercanía**, no qué está
permitido:

| Regla | Sigue igual |
|---|---|
| El súper no se junta con clientes (v14.23) | sí — y además `gv_ppp_web_camion` empieza a mirar `GV_Supers` |
| Súper va solo en su tanda; excepción `auto_super` (INC, v19.13) | sí |
| Un cliente, un día — pero la tanda **se parte por camión** (Luis, v18.87) | sí (R3 lo hace por construcción) |
| Una tanda no sale en dos días (v18.92) | sí |
| Web no se mezcla con ISIS (v14.12) | sí |
| Tope de mezcla 1,00 m³ · mínimo deseable 0,60 · cliente > 1 m³ va solo | sí |
| Cupo diario = pickers × 3 m³ | sí — R4 le suma el techo de horas, no lo reemplaza |
| Anticipación mínima 4 días hábiles | sí |
| Zonas automáticas (`zonas_automaticas`) y zonas manuales con camión (`zonas_manuales_con_camion`) | sí |
| Norte y Sur de Capital nunca juntos | sí — por distancia (13 km) **y** por el veto de `GV_Barrios_Pares` |
| No se toca una tanda que un operario ya empezó | sí |
| "En el chat los nombres, en la app los códigos" (v14.00) | sí |

---

## 6. Parámetros nuevos (`PPP_Web_Config`)

| clave | arranque | qué hace |
|---|---:|---|
| `geo_armado_activo` | 0 → 1 | interruptor maestro. 0 = sistema de sectores de hoy, sin cambios |
| `geo_fallback_tabla` | 1 | parada sin punto: 1 = cae a sectores · 0 = queda en A Programar |
| `radio_tanda_km` | 3,5 | radio para juntar dos paradas (CABA) — lo fija el par Boedo/Pompeya, §12 |
| `radio_tanda_km_gba` | 5,0 | ídem fuera de CABA |
| `tanda_diam_max_km` | 6,0 | diámetro máximo de una tanda |
| `radio_dia_km` | 8,0 | distancia al centroide del camión del día para engancharse (R5) |
| `dia_espera_max_habiles` | 3 | cuánto se puede posponer esperando camión |
| `ruta_horas_guard` | 1 | 1 = el armado respeta el techo de 8 h por camión-día |

---

## 7. Cómo se aplica (y cómo se prueba)

1. **Sombra (no cambia nada).** Se crean `gv_ppp_web_punto`, `gv_ppp_ruta_horas` y las tres vistas
   de R7, y se corre el armador **en una transacción abortada** con `p_filas` reales de los últimos
   45 días, con `geo_armado_activo` en 0 y en 1. Se compara: tandas, m³/tanda, diámetro, horas/día,
   paradas por camión-día. **Sin esa corrida no se prende nada**: la lección de v18.87 es que
   *"un cambio de regla de armado no está probado hasta que se corre el armador"* — las tres puertas
   del súper parecían cerradas leyendo el código.
2. **Una zona primero.** Prender para Zona 1 y 2 (las automáticas de hoy) una semana, con las
   vistas centinela miradas todos los días. GBA después.
3. **Rollback:** `geo_armado_activo = 0`. Las tablas de sectores siguen enteras y la función vieja
   queda como `gv_ppp_web_compat_tabla`.
4. Cada paso se anota en `docs/SUPABASE-GESTION-VIRGILIO.md` con la medición que lo prueba.

---

## 8. Cuánto gana — SIMULADO sobre la programación real

No es una estimación de escritorio: se corrió el algoritmo sobre las **139 paradas reales** de la
ventana (12 días, sin Retira), con la **misma fórmula de horas del front** (recorrido por vecino
más cercano desde Virgilio 2788, × 1,35, ÷ 28 km/h, + 15′ por parada) y los mismos topes
(8 h por viaje, 6 m³ por camión, 2 fleteros, súper en viaje propio).

| escenario | viajes | km | horas | fletero-días | días que no entran en 2 fleteros |
|---|---:|---:|---:|---:|---:|
| **Hoy** (camión = prefijo de tanda, que es como agrupa el front) | 35 | 1.829 | 100,6 | **20** | **1** (mié 16) |
| **A** · reclusterizar por cercanía, mismo día | 29 | 1.560 | 90,7 | 18 | 0 |
| **B** · A + mover el pedido hasta 3 días hábiles (R5) | **27** | **1.520** | **89,3** | **17** | 0 |

**−23 % viajes · −17 % km · −11 % horas · −15 % fletero-días**, y el día que hoy se pasa
(mié 16) deja de pasarse.

El día más claro es el **viernes 11/09**:

```
hoy : 6 viajes → 2,4h · 1,9h · 1,8h · 1,4h · 1,3h · 1,2h   (10,0 h de camión, 4 paradas + 3 + 1 + 2 + 1 + 1)
prop: 1 viaje  → 12 paradas, 4,26 m³, 5,7 h
```

Otros dos: **17/09** pasa de 3 viajes (5,7 + 3,0 + 1,4 h) a 2 (8,0 + 1,4 h); **09/09** pasa de
4 viajes a 2 (6,9 h con 7 paradas + 1,8 h con 3).

**Lo que la simulación NO prueba, y hay que decirlo:**

1. **Agrupé paradas, no tandas.** En el resultado, **9 de 80 tandas quedan repartidas entre dos
   viajes** — eso rompería la carga del camión. En el sistema real las dos cosas se arman en la
   misma pasada (la tanda nace dentro de un viaje), así que la ganancia real es **algo menor**
   que ese −23 %.
2. **Sólo 2 paradas se movieron de día** en toda la ventana: la mayoría de los días ya tiene
   camión propio. R5 rinde cuando hay poco volumen por zona, que es exactamente el caso de GBA
   Norte y GBA Oeste.
3. Los "viajes" de 0,2 h que aparecen en la propuesta son **paradas sin ubicación** (Retira
   aparte): quedan sueltas porque no se pueden agrupar por distancia. Es el argumento de R1.
4. La simulación no vuelve a pickear nada: reordena reparto. El picking sólo mejora si además se
   arma la tanda con el mismo criterio (R2).

**Otras ganancias que no están en la tabla:**

- **Menos mantenimiento**: 318 filas de tablas geográficas pasan a ~25 (sólo los vetos).
- **El día se detecta antes de que explote**: el techo de horas entra al armado, no al aviso.
- **Deja de existir la familia de bugs "súper con zona numérica"**: manda el padrón, no la etiqueta.

**Lo que NO arregla:** las tandas que vienen armadas de ISIS (45 de 88 en la ventana; ahí está el
caso Dapelo, un mismo cliente partido en D67G/L/M el 15/09 a 300 m). Eso lo decide quien tipea en
ISIS, no Gestión.

El script de la simulación está en la sesión (no en el repo); se reproduce bajando las paradas
con la consulta de la §2 y corriendo el mismo `nearest neighbor` que `_pppJornadaCam`.

---

## 9. Lo que hay que decidir (Thomas / Luis)

Son tres números, no reglas. Se arranca con los valores propuestos si nadie dice otra cosa:

1. **Radio para juntar** (3,5 km CABA / 5 km GBA). ¿Un cliente de Flores y uno de Caballito a 2,5 km
   son la misma tanda, aunque sean barrios distintos? Con menos de 3,5 se rompe un par que ya
   había marcado el dueño (Boedo/Pompeya, 3,3 km).
2. **Cuánto se puede posponer un pedido esperando que vaya el camión a esa zona** (3 días hábiles
   sobre la anticipación mínima). Es el único cambio que el cliente puede notar.
3. **Si el techo de 8 h retiene** (`ruta_horas_guard`) o sólo avisa. Retener cambia la fecha de
   entrega; avisar deja la decisión en el supervisor.

---

## 10. El algoritmo, paso a paso

Reemplaza el bloque `if v_sect then … end if` de `ppp_web_armar_tandas` (el que hoy usa
`camion` + `_open` + `gv_ppp_web_compat`). El resto de la función —los filtros de súper, zona
automática, cupo, el `insert` final— **no se toca**.

```
PARA CADA corrida (empresa, fecha):
  0. filas = lo de siempre (sin tanda, sin súper salvo auto_super, zona automática, dentro del cupo)
  1. cada fila recibe PUNTO = gv_ppp_web_punto(cod, direccion, barrio, zona)
     sin punto y geo_fallback_tabla=0 → se aparta, motivo 'sin_ubicacion' (queda en A Programar)

  2. AGRUPAR POR CLIENTE, y dentro del cliente POR CERCANÍA:
     un cliente con sucursales a más de radio_tanda_km entre sí ya se parte
     (es la regla de Luis v18.87, pero medida en km y no por etiqueta de camión)

  3. SEMILLA DEL VIAJE: el grupo-cliente cuyo punto está MÁS LEJOS del depósito.
     (Empezar por el lejano es lo que evita el viaje "solo" del final: lo que está
      cerca siempre encuentra con quién juntarse, lo lejano no.)

  4. CRECER EL VIAJE: agregar el grupo-cliente más cercano al viaje mientras
        · distancia al punto más cercano del viaje ≤ radio_tanda_km (o _gba)
        · m³ del viaje + grupo ≤ camion_m3_tope (6)
        · horas(viaje + grupo) ≤ jornada_horas_max (8)
        · ningún par (barrio_a, barrio_b) con permitido=false en GV_Barrios_Pares
        · ninguno es súper (el súper abre su propio viaje y no admite a nadie)
     si nada entra → cerrar el viaje y volver al paso 3 con lo que queda

  5. PARTIR EL VIAJE EN TANDAS (picking): dentro del viaje, recorrer las paradas EN EL ORDEN
     DE LA RUTA y cortar cada vez que se acumula tanda_m3_max_mezcla (1,00);
     un cliente nunca se parte entre dos tandas del mismo viaje;
     un cliente que solo pasa 1,00 m³ se lleva su tanda entera.
     ⇒ así una tanda NUNCA queda repartida entre dos camiones, y el orden de carga
       sale del mismo cálculo.

  6. CÓDIGO: el viaje toma un número de camión (LETRA+NN) — reusando el del día si ya
     existe uno cuyo centroide está a ≤ radio_dia_km — y cada tanda su letra final.

  7. GUARD DE DÍA: si el día ya tiene jornada_camiones × jornada_horas_max horas comprometidas,
     el viaje entero se pospone al próximo día hábil con cupo (hasta dia_espera_max_habiles);
     si ahí tampoco entra, queda en A Programar con motivo 'sin_jornada'.
```

**Por qué "semilla = el más lejano"** y no el más cercano: probado al revés en la simulación,
el algoritmo arma primero un viaje compacto en CABA y deja al de Pilar solo — que es el
problema que se quiere resolver. Con el lejano de semilla, Pilar arrastra a todo lo que le queda
de camino.

---

## 11. Qué se toca en la base (contrato)

**Funciones nuevas** (prefijo `gv_`, `security_invoker` donde corresponda, `EXECUTE` revocado a
`anon` salvo las que llame el front):

| función | devuelve | para qué |
|---|---|---|
| `gv_ppp_web_punto(cod, direccion, barrio, zona)` | `(lat, lng, precision)` | R1 |
| `gv_km(lat1, lng1, lat2, lng2)` | `numeric` (haversine, `immutable`) | base de todo |
| `gv_ppp_ruta_orden(puntos jsonb)` | `jsonb` (orden de paradas) | vecino más cercano desde el depósito |
| `gv_ppp_ruta_horas(puntos jsonb)` | `(km, horas, paradas)` | R4 — misma fórmula que `_pppJornadaCam` |
| `gv_ppp_web_compat_geo(a jsonb, b jsonb)` | `boolean` | R2, con el veto de `GV_Barrios_Pares` |

**Funciones que cambian** (las tres con la versión vieja preservada como `_tabla` / `_v1887`,
que es el rollback):

- `ppp_web_armar_tandas` — el bloque de agrupación (§10). El resto igual.
- `gv_ppp_web_camion` — **primero** `GV_Supers` → `'Super'`; después sector; después el `CASE`.
- `gv_ppp_web_dia_camion` — criterio por distancia al centroide en vez de número de zona.

**Tablas nuevas**: ninguna. `GV_Sectores*` y `GV_Barrios_Pares` **se conservan** (la primera
para la etiqueta de camión y el orden, la segunda como veto).

**Depósito**: hoy la coordenada de Virgilio 2788 vive en `PPP_Geo` con
`dir_key = '__deposito_virgilio_2788__'` (-34,6158 / -58,5252), puesta por el front. El backend
la va a necesitar: conviene **fijarla en `PPP_Web_Config`** (`deposito_lat` / `deposito_lng`) en
vez de depender de una fila que escribió un navegador.

---

## 12. Casos de prueba (los que tienen que pasar antes de prender)

Todos se corren con `ppp_web_armar_tandas` **de verdad**, con `p_filas` armado a mano, dentro de
una transacción que termina en `rollback`:

| # | caso | resultado esperado |
|---|---|---|
| 1 | Dorinka (súper, `Zona 5 - GBA Oeste`) + 2 clientes comunes de Zona 5, mismo día | 3 viajes: el súper solo, los clientes juntos. `gv_ppp_super_mezclado` vacía |
| 2 | Jazquel con 8 NP en Balvanera + 1 en Ciudadela | 2 tandas, 2 viajes, **mismo día**. `gv_ppp_tanda_camion_mezclado` vacía |
| 3 | Un cliente de Belgrano/Núñez + uno de Lugano (**10 a 12 km** medidos entre centroides) | nunca en la misma tanda ni en el mismo viaje |
| 4 | Boedo + Pompeya (**3,3 km** entre centroides; sectores F y A) | **sí** en la misma tanda — ver la nota de abajo, es el caso que fija el radio |
| 5 | Un pedido de Pilar solo, con otro de Pilar 2 días hábiles después | los dos el mismo día, un viaje |
| 6 | Un cliente con 1,4 m³ | tanda propia, no se parte, no arrastra a nadie |
| 7 | Una parada sin geocodificar | queda en A Programar con `sin_ubicacion` (o cae a sectores si `geo_fallback_tabla=1`) |
| 8 | Un día que ya tiene 15 h de camión comprometidas | el viaje nuevo se pospone; nada queda sin motivo |
| 9 | Una tanda que un operario ya empezó (EP/TP/…) | no se toca, no recibe nada |
| 10 | Krikos / Retira / Expo | fuera del armado, como hoy |

⚠ **El caso 4 es el que calibra el radio, y con 3,0 km NO pasa.** Medido sobre los centroides
reales de `GV_Geo_Cliente`: Boedo–Pompeya **3,3 km**, Boedo–Parque Patricios **3,8 km** — o sea
que el par que el dueño marcó a mano como permitido (*"Boedo pega con Pompeya por Av. Sáenz"*)
queda afuera de un radio de 3,0. Dos consecuencias:

1. **El radio de CABA arranca en 3,5 km, no en 3,0** (y hay que mirar el caso Parque Patricios).
2. **`GV_Barrios_Pares` conserva sus DOS sentidos**, no sólo el veto: `permitido = false`
   prohíbe aunque la distancia dé, y `permitido = true` **fuerza** aunque la distancia no dé. Es
   la única forma de que una regla escrita a mano por el dueño sobreviva a un umbral numérico.

(La distancia real se mide entre **paradas**, no entre barrios: un cliente de Boedo sobre Sáenz y
uno de Pompeya pueden estar a 800 m. Los 3,3 km son el promedio del barrio, que es el peor caso.)

Y el barrido de regresión: correr los **12 días de la ventana** con el armador nuevo y comparar
contra lo que hay hoy (tandas, m³, diámetro, horas/día), que es lo que hizo la simulación de §8
pero con la función real.

---

## 13. Qué puede salir mal

| riesgo | cómo se acota |
|---|---|
| Una coordenada mal geocodificada arrastra un viaje entero | `gv_geo_incoherente` ya existe; sumar el guard de "punto fuera de AMBA" y `precision` en la vista de dispersión |
| El radio en km no traduce bien el tiempo real (Riachuelo, vías, autopistas) | el guard de verdad es **horas**, no km: R4. El radio sólo agrupa |
| Posponer un pedido molesta a un cliente | `dia_espera_max_habiles` y, sobre todo, la decisión 2 de §9. Nunca se pospone un pedido con fecha pactada (súper / `GV_Pedido_Horario`) |
| El armado se vuelve más lento (el cron corre cada 5 min) | el cálculo es sobre ≤ 40 paradas por corrida; `gv_km` es `immutable` y la ruta es O(n²) con n chico. Medir igual: hoy la corrida entera son 8,0 s |
| Alguien toca las tablas de sectores esperando que sigan mandando | quedan como veto y etiqueta; hay que decirlo en `docs/SUPABASE-GESTION-VIRGILIO.md` y en `GUIA-PROYECTO.md` el mismo día |
| Se pierde el `security_invoker` al reemplazar una vista | el chequeo del `CLAUDE.md`, sí o sí, después de cada `create or replace view` |
