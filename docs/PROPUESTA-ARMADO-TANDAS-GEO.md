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

`GV_Sectores_Vecinos` y `GV_Barrios_Pares` **quedan, pero sólo como veto**: un par con
`permitido = false` prohíbe aunque la distancia dé (así sobrevive *"Norte y Sur de Capital nunca
juntos"* y cualquier excepción futura del dueño). Lo que se retira es el uso **positivo**: hoy dos
paradas a 400 m en sectores que nadie cargó como vecinos **no se juntan**, y dos paradas a 11 km en
sectores marcados vecinos **sí**. Medido sobre los centroides de sector: los pares "vecinos" van de
2,6 a **11,4 km**, y los "no vecinos" arrancan en **5,9 km** — la tabla y la distancia no coinciden.

Valores de arranque propuestos: `radio_tanda_km = 3,0` en CABA y `5,0` en GBA (`radio_tanda_km_gba`),
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
| `radio_tanda_km` | 3,0 | radio para juntar dos paradas (CABA) |
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

## 8. Lo que gana (honesto)

- **Menos viajes flacos**: R5 es el que mueve la aguja. Los 5 camión-día de arriba (1-2 paradas) son
  ~1 fletero-día por semana tirado.
- **Menos tandas**: los 14 pares fusionables de la ventana son picking, no km — mejora de armado,
  no de reparto.
- **Menos mantenimiento**: 318 filas de tablas geográficas pasan a ser ~25 (sólo los vetos).
- **El día se detecta antes de que explote**: el techo de horas entra al armado, no al aviso.
- **Deja de existir la familia de bugs "súper con zona numérica"**: el padrón manda, no la etiqueta.

**Lo que NO arregla:** las tandas que vienen armadas de ISIS (45 de 88 en la ventana; ahí está el
caso Dapelo, un mismo cliente partido en D67G/L/M el 15/09 a 300 m). Eso lo decide quien tipea en
ISIS, no Gestión.

---

## 9. Lo que hay que decidir (Thomas / Luis)

Son tres números, no reglas. Se arranca con los valores propuestos si nadie dice otra cosa:

1. **Radio para juntar** (3 km CABA / 5 km GBA). ¿Un cliente de Flores y uno de Caballito a 2,5 km
   son la misma tanda, aunque sean barrios distintos?
2. **Cuánto se puede posponer un pedido esperando que vaya el camión a esa zona** (3 días hábiles
   sobre la anticipación mínima). Es el único cambio que el cliente puede notar.
3. **Si el techo de 8 h retiene** (`ruta_horas_guard`) o sólo avisa. Retener cambia la fecha de
   entrega; avisar deja la decisión en el supervisor.
