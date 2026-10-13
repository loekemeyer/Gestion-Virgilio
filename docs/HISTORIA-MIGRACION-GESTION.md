# Historia: la migración de Producción Virgilio a Gestión Virgilio (sept 2026)

> Movido de `CLAUDE.md` el 2026-10-13 (poda de reglas, pedido de Luis) para que no cargue en cada sesión.
> Es documentación operativa VIVA del módulo, no se resume: leer ENTERA antes de tocar este módulo.

## ⚠⚠⚠ CUANDO GESTIÓN TOMA CONTROL Y SE VUELVE LA VERSIÓN QUE USAMOS, SEGUIR CON LA NUMERACIÓN QUE DEJÓ VIRGILIO

**Estado desde el 2026-09-04 (viernes, a la noche): la numeración está PRENDIDA
(`numeracion_activa = 1`), el cron de tandas (jobid 71) activo, y las tandas con prefijo `GV-`
hasta el sábado 05/09, cuando el dueño lo hizo sacar (`tanda_prefijo = ''` → `E01A`).** Decisión del dueño: prender **sólo Virgilio**, sin tocar LK — el mail de
las 12:30 (`procesar-pedidos-web`) siguió andando hasta el **sábado 2026-09-05 a las 13:50 ART,
cuando el dueño lo hizo apagar** (crons 7 y 10 de LK en `active=false`, v12.94). Último envío a
ISIS: sábado 12:30, pedidos 1340..1349. **⚠ Cambio del sábado a la noche (v13.15): el dueño dijo
"el lunes van a empezar a usar GV, no más PV" → el mail del sábado se IGNORA y GV programa también
los 1340..1349** (`PPP_Web_Config.excluir_enviados_a_isis = 0`; no cargar ese mail en ISIS, quedarían
dobles). **Desde el lunes 2026-09-07 los operarios usan Gestión.** **⚠ v13.22 (sábado a la noche): ANTICIPACIÓN
MÍNIMA de 4 días hábiles** (`PPP_Web_Config.dias_anticipacion_min`, `gv_ppp_web_dia_minimo()`): el lunes
los operarios sólo arman lo que ISIS dejó (mar 8 / mié 9 / jue 10); lo que Gestión programe cae recién el
**viernes 11** en adelante (job 00:01 vía cron 71 con `{"fecha": …}`, intradía, "A Programar"). Poner en 0
para volver a hoy/mañana. §3.af. **El lunes 07/09 es Día del Metalúrgico: no hábil** (`GV_Dias_No_Habiles`,
§3.ag); primer día real con Gestión = martes 08. **Cupo diario = pickers típicos × 3 m³ (hoy 6), contando
ISIS + web** (`gv_ppp_web_cupo`, idea 6220, v13.23, §3.ah; `cupo_por_dotacion = 0` → 5 fijo). **v13.67 (lun 07/09 01:30): los crons 71 y 73 de Virgilio estuvieron apagados desde el 06/09 20:40 (otro chat) hasta que `ppp_web_armar_tandas` v7 hizo que la tanda ACUMULE entre corridas hasta 0,80 m³ (`sql/ppp_web_armar_tandas_v7_acumula.sql`, §3.av); están PRENDIDOS de nuevo.** **El cron de Chef quedó APAGADO el domingo 2026-09-06** (proyecto nkhzocgdpwtgrmwleihr, jobs 1
`procesar-pedidos-web` y 2 `retry-procesar-pedidos` en `active=false`, lo corrió el dueño; v13.31).
Último mail de Chef: sábado 05/09 12:30, pedido 217; el del viernes llevó el 216. **Ninguno de los dos
se carga en ISIS: 216 ya es E02A (vie 11) y 217 es E06A (lun 14).** Para volver a prenderlo:
`cron.alter_job(1, active := true)` y `(2, …)` en Chef. **Dueño 07/09: "no, dejalo apagado"** (Gestión programa Chef; si se prende, compras tipea dobles). **Cron 76 `gv-alerta-sin-eventos`** (lun–vie 10:30 ART, v13.72): día hábil sin eventos de operarios → Telegram.
Detalle, medición y rollback en `docs/SUPABASE-GESTION-VIRGILIO.md` §3.l y §3.p.

- **NP** → **v13.70 (2026-09-07): la NP web es un CONTADOR propio, un número por bloque, SIN sufijo** (dueño:
  *"el pedido tiene que ser único; no 1540-1, 1540-2; guardá el ID de la página pero que sea otro número; LK y 4
  dígitos"*): `LK 0001`, `LK 0002`… / `CH 0001`… (`gv_ppp_web_np_asignar` con lock, `PPP_Web_NP_Seed`, índice único
  `(empresa, np)`). El pedido de la página (`order_id`) queda guardado como referencia y se muestra "web LK 1350"
  hasta que se programa (ahí se asigna la NP). Un pedido de 4 bloques = 4 NP distintas. Deshace v12.92 (NP = nº de
  pedido con sufijo `-2`); `sql/gv_np_contador_v1370.sql`, §3.aw. Se
  programa por el job de las 00:01 para zona 1, 2 y 3 (`zonas_automaticas = '1,2,3'` desde v13.07)
  y a mano en "A Programar" para el resto.
  **Desde el 2026-09-05 además hay armado INTRADÍA** (idea 7317, cron jobid 73 — **cada 5 min
  desde el 15/09**, `*/5 9-23 * * *` UTC = 06:00–20:55 ART; antes cada 15 min lun–vie
  07:00–18:45 —, Edge Function v14 con `{"intradia": true}`): cuando lo pendiente de
  las zonas automáticas suma ≥ 0,80 m³ se arma ya, para hoy si es antes de las 12:00 y hay cupo, si no
  para el próximo hábil con cupo (`gv_ppp_web_proximo_dia_entrega`). §3.x de la doc de Supabase.
  **v13.47 (domingo 06/09, dueño: *"mandá directo a Programación si ya está, no más en A Programar"*):
  cada corrida programa TODO lo que tiene día previsible** — zonas automáticas en cascada de días con
  cupo, zonas manuales (4/5/6/7) al día en que ya hay camión a la zona (`gv_ppp_web_armar_pendientes`,
  §3.ao); el intradía corre todos los días 06:00–20:45 y el umbral está en 0,001. En A Programar quedan
  sólo Retira, Súper, sin zona y sin camión previsto. **v13.69: A Programar = pedidos | días; se arrastra el pedido DIRECTO al día, sin botones de tanda LK/Chef** (la planilla v13.61 se borró: al dueño no le gustó; la columna de tandas sin fecha sólo aparece si quedó alguna vieja). Soltar un pedido en un día arma la tanda con código automático y la programa (`aprGenerarTanda`; se descarta si falla: **ninguna tanda queda sin fecha**). **La PPP entra entera en una pantalla** (`pppFitPantalla`, zoom automático, sin scroll interno). Tandas numeradas como Producción (E01A, E02A…). **v13.60: camión = LETRA+NN y se REUSA por día y etiqueta** (Capital / GBA Sur / GBA Oeste / GBA Norte): una tanda nueva entra al camión que ya va ese día, aunque sea de ISIS (E01F, D68G); camión nuevo sólo si no hay. `sql/gv_ppp_web_camion_del_dia.sql`, §3.at. Ese día además se corrió la semana un día hábil (lun 7 feriado, nada armado; súper quedan) — backup `sql/backups/reprogramacion_20260906_pre_v1360.sql`.
  **Y las tandas se arman por CERCANÍA REAL** (v13.07, §3.y): sectores + vecinos en `GV_Sectores`,
  `GV_Barrios_Sector`, `GV_Sectores_Vecinos`, `GV_Barrios_Pares` (`sql/gv_sectores.sql`); Núñez
  nunca con Lugano, Barracas sí con Constitución o Avellaneda. Interruptor
  `PPP_Web_Config.sectores_activos` (0 = regla vieja por grupo de zona). Probar sin escribir:
  `gv_ppp_web_armar_simular(...)`.
  Regla del dueño: *"cuando Gestión tome control, va a asignarle la numeración
  nuestra a los pedidos que estén pendientes y a los que vayan cayendo"*. **Pendiente =
  pedido de la página con fecha ≥ `gestion_desde` (2026-09-03, piso) que Producción/ISIS no
  tenga** (v13.15). Con `excluir_enviados_a_isis = 1` además se excluye lo que salió por el mail
  (`enviado_a_compras`; era la regla de convivencia, v12.94); desde el sábado 05/09 a la noche
  está en 0 porque el lunes nadie usa Producción. La regla vive en UNA RPC de Virgilio, `gv_pedidos_web_excluidos`, que
  llaman el job y "A Programar"; los feeds de LK son crudos. Motivos: `enviado_a_isis`,
  `anterior_al_cambio`, `en_produccion`. **Bloques**: de a 18 (LK) / 15 (Chef) SEGUIDOS en el
  orden del carrito, igual que ISIS (v12.94; antes serpentina por m³).
  `pwebNumerar()` —la que numeraba todo al abrir una pantalla— quedó inalcanzable desde v12.82.
- **Tandas** → **codificación histórica `LETRA+NN+LETRA`** desde el sábado 2026-09-05 (dueño:
  *"sacá el prefijo GV-"*; `tanda_prefijo = ''`). `ppp_web_proxima_letra()` retoma desde la
  última letra de Producción (D71A) → la primera tanda de Gestión es **`E01A`**. Hasta ese día
  el prefijo era `GV-` para no pisarse con Producción; para volver: `valor_texto = 'GV-'`.
- **Canilla del espejo de ISIS: ABIERTA de nuevo desde el domingo 2026-09-06 (v13.51).** Gestión lee las
  vistas **`gv_ppp_programacion_diaria` / `gv_ppp_base_pedidos` / `gv_ppp_entregados_meta`**
  (`sql/gv_espejo_corte.sql`), que con `PPP_Web_Config.espejo_np_corte_lk/_chef = null` devuelven todo lo
  que ISIS numere (ISIS sigue cargando pedidos propios, ej. 98704 Salvetti D60G). Lo que NO debe verse
  (una NP de ISIS que duplica un pedido web ya programado por Gestión) se oculta **fila por fila** con
  `GV_PPP_Prog_Override.oculto = true` (`sql/gv_ppp_prog_override.sql`); las tres vistas y
  `gv_pedidos_web_excluidos` la saltean. Al 06/09 hay 10 ocultas: 98696–98703 y 44620/44621, el mail del
  sábado que se cargó en ISIS igual. La misma tabla sirve para **pisar tanda/fecha** de una NP de ISIS sin
  tocar la tabla compartida (44619 Chango Mas → E07A, v13.50). Estuvo cerrada del 05/09 al 06/09 (v12.90,
  corte 98694/44619); para cerrarla otra vez: `update public."PPP_Web_Config" set valor = 98704 where clave =
  'espejo_np_corte_lk'` (y 44621 en `_chef`). Detalle §3.m, §3.ap y §3.aq de `docs/SUPABASE-GESTION-VIRGILIO.md`.

**Para apagarlo (mismo día, todo reversible):**

```sql
-- en VIRGILIO (hrxfctzncixxqmpfhskv)
update public."PPP_Web_Config" set valor = 0 where clave = 'numeracion_activa';
select cron.alter_job(71, active := false);
```

**Hecho el sábado 2026-09-05: las tandas siguen la codificación histórica** (`tanda_prefijo = ''`;
`ppp_web_proxima_letra()` retomó desde la última letra que dejó Producción, D71A → `E01A`).
Para volver al prefijo de convivencia:

```sql
update public."PPP_Web_Config" set valor_texto = 'GV-' where clave = 'tanda_prefijo';
```

**La NP web es el número de pedido de la página** (v12.92): `LK 1350`, `LK 1350-2` (bloque 2),
`CH 0217`. Sin choque con Producción, cuyas NP son de 5 dígitos desde 44361 y sin prefijo. La
etiqueta la arma **`gv_ppp_web_np_label(empresa, np, np_idx)`** en el backend — prefijo +
espacio + 4 dígitos + `-bloque` si el bloque es > 1; el front (`pwebNpLabel`) y la Edge
Function (`npLabel`) la duplican sólo como optimización de UX. Historia del 2026-09-05: se
pasó de 5 a 4 dígitos (v12.91) y de contador propio a número de pedido (v12.92), las dos
veces antes de numerar el primero.

Con el prefijo vacío, `ppp_web_armar_tandas` vuelve sola a la codificación histórica
`LETRA+NN+LETRA` y `ppp_web_proxima_letra()` **retoma desde la última letra que dejó
Virgilio** (mira las dos tablas). No hay que tocar código ni redeployar nada.

Detalle y pruebas: `docs/SUPABASE-GESTION-VIRGILIO.md` §3.e y §3.f, `sql/ppp_web_tandas.sql`
y `sql/gv_tandas_diarias.sql`.
