# Por qué y cómo se refresca stocks_carga_rapida

> Movido de `CLAUDE.md` el 2026-10-13 (poda de reglas, pedido de Luis) para que no cargue en cada sesión.
> Es documentación operativa VIVA del módulo, no se resume: leer ENTERA antes de tocar este módulo.

## ⚠ REGLA (Thomas, 2026-09-22, v21.06): el refresco del stock se hace SOLO si algo cambió

Cron 55 refrescaba `vista_stock_procesada` **cada 2 minutos, siempre**: **1.770 s sobre una
ventana de 26,4 h = 7,4 % del tiempo total de la base**, para una matview de **367 filas /
216 kB**. Y sobre 7 días, sólo **277 de los 5.040 bloques** de 2 minutos tuvieron movimiento de
stock: el **94,5 % de los refrescos no cambiaba una sola fila**. Esa contención es la que daba
los `canceling statement due to statement timeout` de la Cuarentena (problema 492).

Hoy el cron llama a **`gv_refresh_stock_si_cambio()`**. Medido en vivo: **refresco 1.813 ms ·
chequeo que salta 12 ms (150×)**.

⚠⚠ **Y con esa primera versión el ahorro fue del 1,2 %, no del 94,5 % (v21.31).** La huella
contaba **escrituras**, y hay crons que reescriben tablas enteras sin cambiar nada: el **cron 81
`gv-reconciliar-aguardar` corre cada 2 minutos** —el mismo minuto que el 55— y toca
`Movimientos_Stock`. Medido: `PPP_Web_Base` 582.748 updates contra 372 inserts, `GV_UxB` 34.036
contra 0. El riesgo estaba escrito acá mismo como caso raro; **es el caso normal de esta base**,
y la medición de 5 minutos que lo dio por bueno cayó justo entre dos corridas del cron. Hoy las
5 tablas ruidosas llevan **firma de CONTENIDO** (`GV_Stock_Huella_Expr`, que es un `insert`, no
código): 60-74 ms de huella y **0 refrescos / 3 saltos = 100 % ahorrado** con el cron 81
corriendo en el medio. §3.mj.

⚠ **La frescura NO empeora.** El chequeo sigue corriendo cada 2 minutos: apenas se escribe un
movimiento, el refresco sale en la corrida siguiente. Lo único que se saca es el refresco que
no cambiaba nada.

⚠ **El árbol de dependencias se camina EN VIVO, no es una lista a mano.** La matview cuelga de
**23 tablas y 5 vistas**; se resuelve con `pg_rewrite`/`pg_depend`, así que una tabla nueva entra
sola (verificado 23 de 23, 11 ms). Una lista escrita a mano es el mismo pozo de los pases que
eligen fecha (v20.83), el `ref` compuesto (v20.72) y las 18 tablas del renombre (v20.88):
**siempre falta una**.

⚠ **La matview se excluye de su propia huella**, o su refresco cambiaría la huella y se
refrescaría para siempre. Y la comparación que manda es el **jsonb entero**, no clave por clave:
así una tabla que entra o sale del árbol también cuenta.

⚠ **FAIL-OPEN, al revés del guard de cuarentena (v20.95):** sin huella, se refresca. Un refresco
de más cuesta 2 s; una vista de stock vieja la mira un operario y le miente. Más el **piso de
frescura** (60 min).

⚠ **La huella cuenta ESCRITURAS, no contenido** (`pg_stat_user_tables`). Un `delete`+`insert`
con contenido idéntico dispara un refresco al pedo, y un reset de estadísticas fuerza uno: las
dos fallan hacia refrescar de más, nunca de menos.

⚠⚠ **Y lo que el stock gasta de verdad NO es esto.** Medido el 22/09: `vista_saldos_stock` se
lee **directo desde la app en 5 lugares** de `index.html` — **1.759 llamadas, 2.850 s**, contra
los **1.808 s** del refresco. Pedir **un solo código** (`clave=eq.438E`) cuesta lo mismo que
pedir todos (**769 ms**): `clave` es una expresión calculada, así que no hay índice que valga y
recorre las 67.242 filas y las ordena para devolver 0 (`Rows Removed by Filter: 496`). El
arreglo **NO es una columna nueva**: `clave` no existe en la tabla, pero `ckey` —la
normalización del código— es función pura de `cod_art` con funciones inmutables, así que alcanza
un **índice de EXPRESIÓN** (`mov_stock_ckey_idx`, 496 kB): sin columna, sin trigger, sin backfill
y sin reescribir una fila. Y como el índice sólo sirve si alguien filtra por esa expresión, va con
**`gv_saldos_por_clave(text[])`**: **687 ms → 7 ms** para un código, 69 ms para diez, con salida
verificada idéntica (496 = 496 filas, `EXCEPT ALL` 0 en las dos direcciones). v21.31, §3.mj.

⚠ **`work_mem` NO es el arreglo, se midió y se descartó.** Con 4 MB el orden se cae a disco
(`external merge Disk: 3.304 kB`); con 32 MB entra en memoria y el I/O temporal se va a 0 — pero
la consulta pasa de **769 ms a 751 ms**. Los 750 ms son el recorrido y el regex por fila, no el
orden. No volver a proponerlo para esto.

### ⚠⚠ Y `vista_stock_procesada` NO puede reemplazar a `vista_saldos_stock` (medido 23/09)

La tentación es obvia — la matview ya está calculada y las lecturas del universo entero de
`vista_saldos_stock` son hoy el mayor consumidor del stock: **cuatro formas de consulta, 3.524 s
sobre una ventana de 47,9 h = 2,0 % del tiempo de la base** (`stockFetchSaldos` 1.902 llamadas,
`_pppChkFetchSaldos` 254). **No se puede, y el número lo cierra:**

| | |
|---|---:|
| filas de `vista_saldos_stock` | 496 |
| filas de `vista_stock_procesada` | 367 |
| códigos que la matview NO tiene | **152** |
| …de esos, **con stock real** | **119** |
| …de esos, **insumos** | **101** |
| cajas de `terminado` que se perderían | **2.266** |

En las 344 filas comunes los números coinciden (**0 difieren**), así que la matview *parece*
equivalente mirando cualquier código de góndola. Y los módulos que llaman a `stockFetchSaldos`
son justamente MG, bajar racks, **insumos** y salida Cervantes. Sería el pozo de la v20.95:
**una fila que no sale no se distingue de un código que no existe.**

⚠⚠ **Y TAMPOCO se cachea `vista_saldos_stock` en una matview propia. RETIRADO**: lo propuse
el 23/09 y Thomas lo bajo el mismo dia — ***"todo el stock tiene que verse lo mas en vivo posible
siempre"***. Esa vista se recalcula en cada lectura a proposito (765 ms, 67.945 movimientos), y
`gv_saldos_por_clave` tampoco cachea nada: el indice acelera el recorrido, no lo evita. **El stock
no se cachea.** Si el 2,0 % molesta algún día, el camino es bajar CUÁNTO recorre (la idea de los
últimos 2 meses con el histórico por código a demanda), no congelarlo.

⚠ **El picking NO se repunta a `gv_saldos_por_clave`**, y no es olvido: son **44 llamadas y 35 s
sobre esos 3.524 s (1 %)**, contra tocar el camino caliente del operario. Lo sostiene el candado
invertido de `tests/stock-clave-indexada.cjs`.

⚠ **El `count=exact` que todavía aparece en `pg_stat_statements`** (887 llamadas pagando el doble:
1.925 ms contra 1.021 ms de la misma consulta sin él) **no está en el código**: lo sacó la v20.78.
Son celulares con el `index.html` viejo cacheado. Se muere solo; no hay nada que arreglar.

### ⚠ Cron 81 `gv-reconciliar-aguardar`: reescribe lo mismo cada 2 minutos, y se deja así

Su `on conflict … do update set delta = excluded.delta, legajo = excluded.legajo` **no tiene
`where`**, así que reescribe sus 10 filas cada corrida cambie o no el valor: 1.438 corridas /
278 s / 194 ms de media (peor 13.271 ms), y `Movimientos_Stock` con **10.719 updates contra 2.853
inserts, 11.847 tuplas muertas y `last_autovacuum` en null**.

**Era la causa de que la primera huella (por escrituras) ahorrara 1,2 % en vez de 94,5 %.** Con la
huella por CONTENIDO eso ya no importa, y **Thomas decidió el 23/09 dejar el cron 55 y el 81 como
están**. Lo que queda es el churn del libro de stock, que no molesta a nadie hoy. Si algún día se
toca, el arreglo es una línea (`where … is distinct from …`) — y toca una función que escribe en
`Movimientos_Stock`, o sea que lo autoriza el dueño.

### ⚠⚠ REGLA (Thomas, 2026-09-23, v21.48): la pantalla de Stocks NO lee la matview — lee `stocks_carga_rapida`

**Thomas, textual:** *"todo el stock tiene que verse lo mas en vivo posible siempre"*.

Al medirlo apareció que esa regla **no se estaba cumpliendo, y no por el cron 55**. El dato llega
a la pantalla por **tres saltos**, no uno:

| salto | quién | cada |
|---|---|---|
| `Movimientos_Stock` | el libro | **en vivo** |
| → `vista_stock_procesada` | cron 55 | 2 min, y sólo si cambió |
| → **`stocks_carga_rapida`** | **cron 57** | **5 min, siempre** |
| → pantalla Stocks | `supaFetchAllSafe` | al abrir |

**Atraso máximo: 7 minutos**, y los dos crons no están sincronizados — si el 57 corre justo antes
de que el 55 refresque, se pagan los 7 completos. Los 2 min del 55 eran el salto chico.

Desde la v21.48 **`gv_refresh_stock_si_cambio` reescribe `stocks_carga_rapida` en la MISMA corrida
en que refresca la matview**: la frescura baja a **2 min** y de paso el cron 57 deja de reescribirla
cuando no cambió nada (eran 580 corridas / 324 s / 559 ms por ventana de 47,9 h, con el mismo
94,5 % de corridas inútiles que ya se le había sacado al 55).

⚠ **El lock va con `pg_try_advisory_xact_lock`, NUNCA con el bloqueante.** El advisory **5768** lo
toman **TRES** jobs — el **57**, el **68** (`reconciliar-pipeline-stock`) y el **92**
(`gv-refrescar-articulo-empresa`, `*/15`) —: esperarlo ocuparía uno de los **SEIS** worker slots de
la instancia (`max_worker_processes = 6`, medido). Si no se consigue, no pasa nada — lo reescribe
el 57.

### ⚠⚠ Y ahí había una CARRERA: el 57 le ganaba el lock al 55 y leía la matview VIEJA (v21.57)

**Thomas, textual:** *"fijate que el 57 no lo este pisando"*. No lo estaba pisando siempre, pero
podía — y el registro lo muestra. Los tres arrancaban **en el mismo segundo**:

| minuto | cron 55 | cron 57 | cron 68 |
|---|---|---|---|
| **08:50** | 00.327 · **4.156 ms** | 00.343 · 1.175 ms | 00.389 · **6.529 ms** |
| 08:30 | 00.620 · 4.264 ms | 00.628 · 1.216 ms | 00.748 |
| 08:00 | 00.929 · 1.187 ms | 00.870 · **2.625 ms** | 01.102 |

`*/2` y `*/5` coinciden en los múltiplos de 10: **seis veces por hora**. En la corrida de las
**08:50** el 68 se quedó el lock 6,5 s y el 55 terminó su refresco a los 4,1 s: **no pudo
encadenar**. Cuando gana el 57, además, escribe `stocks_carga_rapida` desde la matview **vieja**.

⚠ **Y no es teórico:** `cron.job_run_details` tiene un **`job startup timeout` del propio cron 68**
el 22/09 a las 10:30 — uno de los dos minutos más cargados. El pozo de los seis worker slots ya
estaba mordiendo acá, no sólo en LK.

**El arreglo no toca la función: los desfasa.** El 55 corre **sólo en minutos PARES**, así que los
otros van a **IMPARES** y la carrera desaparece (el 55 dura 4,3 s en su peor caso: no cruza el
minuto).

| job | antes | ahora | minutos |
|---|---|---|---|
| 57 `refresh_stocks_carga_rapida` | `*/5` | **`3-59/6`** | 3,9,15,21,27,33,39,45,51,57 |
| 68 `reconciliar-pipeline-stock` | `*/10` | **`1-59/10`** | 1,11,21,31,41,51 |

> ⚠ **Cada 6 y cada 10, NO cada 5 ni cada 15.** La paridad se conserva sólo si el paso es PAR:
> `*/5` y `*/15` alternan par/impar por construcción, así que **un cron cada 5 o cada 15 minutos
> no puede quedar siempre impar**. Por eso el 57 pasó de 5 a 6 minutos, y por eso **el 92 no se
> movió**: sigue pisando al 55 en :00 y :30.

**Medido**, minutos por hora en que el 55 se encuentra el lock ocupado: **6 → 2**
(55 vs 57: **0** · 55 vs 68: **0** · 55 vs 92: 2). Y el pico por minuto bajó: **:00 de 19 a 17
jobs**, :30 de 17 a 15.

⚠ El 57 y el 68 **siguen chocando entre sí** 2 veces por hora (:21 y :51) y es **inevitable**
(paso 6 y paso 10, mcm 30). No molesta: el lock los serializa y ninguno lee una matview a medio
refrescar, porque el 55 no corre en impares.

⚠ **Costo aceptado:** `fc_sin_salida` y las descripciones pasan de 5 a **6 min**.

**Rollback, dos líneas:**
```sql
select cron.alter_job(57, schedule := '*/5 * * * *');
select cron.alter_job(68, schedule := '*/10 * * * *');
```

⚠ **FAIL-OPEN, y con el fallo A LA VISTA.** Si la derivada explota, la matview se refresca igual y
el motivo lo dice. **Probado rompiéndola a propósito** (`perform 1/0`) en transacción abortada:
`refrescada=true | motivo=piso de frescura (60 min) (carga_rapida fallo: division by zero)`.
Un tapón sin forma de enterarse es cambiar un error ruidoso por uno mudo (regla de Elías, v20.58).

⚠ **El cron 57 NO se apaga**: es la red del lock ocupado y del fallo. Bajarlo a `*/10` sería un
segundo paso y **no está hecho**.

⚠ **Lo que NO arregla:** si querés el stock *realmente* en vivo en esa pantalla, hay que sacarle a
`stocks_carga_rapida` la dependencia de la matview, y eso se paga con latencia al abrir (~765 ms
contra los 55 ms de hoy). Es otra conversación.

**Verificado corriéndolo** (23/09): `solo_medir` → no encadena · piso de frescura en 0 →
`"... + carga_rapida"`, 3.260 ms · `stocks_carga_rapida` **idéntica antes y después**
(367 filas, md5 `3000430e5cfbde71e8b995819a3ce21e`): el encadenado adelanta el dato, no lo cambia.
`sql/gv_stock_carga_rapida_encadenada_v2148.sql`, `tests/stock-carga-rapida-encadenada.cjs`, §3.mo.

**Chequeo:**
```sql
select * from public.gv_stock_refresh_salud;              -- estado='ok' y pct_ahorrado
select * from public.gv_refresh_stock_si_cambio(60,true); -- qué HARÍA, sin refrescar
```

**Rollback, una línea:**
```sql
select cron.alter_job(55, command := 'REFRESH MATERIALIZED VIEW CONCURRENTLY vista_stock_procesada');
```

`sql/gv_refresh_stock_si_cambio_v2105.sql`, `tests/stock-refresh-si-cambio.cjs`, §3.mi.


## ⚠⚠ REGLA (Luis, 2026-10-16, v31.62): Stocks EN VIVO — nada vuelve atrás, las pedidas sólo si cambió, realtime para el supervisor

**Luis:** *"arregla el cron, dale"* · *"el tema es evitar que se llegue a timeout porque tenga que ver tablas
completas, si se puede hacer que solo busque cambios, golazo"* · *"si la tabla se ve en realtime, aun mejor"*.

**Lo que se midió** (16/10, ajuste de conteo del 936E de 11 a 12 cajas en góndola):

| qué | cómo estaba | por qué |
|---|---|---|
| realtime de la pantalla | **no le llegaba a nadie logueado** | `stocks_carga_rapida` tenía SELECT sólo para `anon`; el supervisor escucha con `authenticated` (count = 0) |
| saldos | volvían atrás hasta 2 min (936E 12 → 11 → 12) | el cron 57 copiaba la matview sin refrescarla, pisando lo que el trigger ya había dejado bien |
| saldos de madrugada | viejos de 2:00 a 7:59 | el 55 no corre en esa franja y el 57 sí |
| cajas pedidas | ≤ 2 min | sólo viajaban por la matview |
| neto del tooltip | **lo de cuando se abrió Stocks** | `gv_stock_pedidas_neto` (0:01) se leía una vez |
| cada pasada del refresco | reescribía las 396 filas, y `fc_sin_salida` a 0 y de vuelta | ~800 eventos de realtime por pasada, una vez prendido |

**Lo que se hizo** (`sql/gv_stock_vivo_v3162.sql`, `tests/stock-vivo-v3162.cjs`):

1. **Política `auth_read_stocks_carga_rapida`** (SELECT para `authenticated`). `anon` ya leía todo: no abre nada.
2. **`refresh_stocks_carga_rapida` no pisa lo movido**: un código con un movimiento `creado` después del último
   refresco de la matview (`GV_Stock_Refresh_Estado.refrescado_en`) conserva lo del trigger. Probado en
   transacción abortada: +1 al 936E → trigger 13, matview 12, refresco nuevo deja **13** (el viejo dejaba 12).
3. **Escribe sólo las filas que cambian** (`IS DISTINCT FROM` en los dos UPDATE). Medido: sin cambios reales,
   **0 filas** escritas, 0,23 s.
4. **Pedidas "sólo si cambió"**: secuencia `gv_stock_pedidas_sucio_seq` (nextval no bloquea a nadie) que suben
   triggers `zz_gv_pedvivo*` en las 11 tablas de pedidos/tandas/cierres y en `Registros_Produccion_Virgilio`
   (sólo **TP y EP**: 151 tandas con PKC en 30 días, ninguna sin EP; 11 TP+EP por día contra 103 PKC).
   `PPP_Web_Base` se reescribe entera por sync (6,3 M updates): su UPDATE dispara sólo si cambia
   `np_label / articulo / cajas`. El job **`gv-stock-pedidas-vivo` (cada 30 s)** lee la secuencia: igual →
   sale en **0,005 s**; distinta → calcula `gv_stock_pedidas_neto` (0:01) y escribe en `stocks_carga_rapida`
   `cajas_pedidas` + las columnas `ped_*` **sólo de las filas que cambiaron**. Piso: 10 min. Lock 5768 con TRY.
5. **`cajas_pedidas` es del job mientras esté sano** (`GV_Stock_Pedidas_Estado.calculado_en` < 15 min); si se
   cae, el refresco vuelve a copiarla de la matview (fail-open).
6. **Importación** (`gv_importados_stock_dep`) lee las pedidas de `stocks_carga_rapida`: el mismo número y el
   mismo atraso que Stocks.
7. **Pantalla**: el UPDATE de realtime parchea la celda y el tooltip (`_stkPedNetoEntrada`) y redibuja **una vez
   por ráfaga** (600 ms). Si la carga trae `ped_vivo_en`, no se lee la vista del neto; el merge con la matview no
   pisa las pedidas vivas.

⚠ **La secuencia se arranca UNA vez** (`select nextval(...)`): recién creada, el primer `nextval` deja
`last_value` en 1 y el job no ve el cambio. Pasó al probarlo.

**Chequeo:**
```sql
select * from public."GV_Stock_Pedidas_Estado";        -- calculado_en reciente, saltos subiendo
select public.gv_stock_pedidas_vivo(true);               -- forzar un cálculo
```
**Rollback:** `select cron.unschedule('gv-stock-pedidas-vivo');` y reponer las definiciones de
`zz_backups."GV_Backup_funcdef_20261016_stockvivo"` (la tabla antes del cambio:
`zz_backups."GV_Backup_stocks_carga_rapida_20261016"`).
