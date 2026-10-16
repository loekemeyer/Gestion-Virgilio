# Crons: colisiones de worker slots, cómo agregar uno

> Movido de `CLAUDE.md` el 2026-10-13 (poda de reglas, pedido de Luis) para que no cargue en cada sesión.
> Es documentación operativa VIVA del módulo, no se resume: leer ENTERA antes de tocar este módulo.

## ⚠ REGLA (Luis, 2026-10-06, v27.17): ANTES DE CREAR O MOVER UN CRON, mirar `gv_cron_colisiones`

**La instancia tiene 6 worker slots.** Cuando varios crons disparan el mismo minuto se agotan, y
el que no consigue slot corta con `job startup timeout` —no sólo él, cualquier consulta de ese
momento—. Fue la causa de fondo del 504 del armado del 06/10 (LK ahogada 10:40–12:40 UTC): el
watchdog cada 1 min y cuatro `*/10` amontonados en el minuto :00 (9 jobs contra 6 slots). Acomodar
minutos a mano no escala: cada cron nuevo vuelve a ser una adivinanza.

> **Al crear o mover un cron (en LK o en Gestión), PRIMERO se consulta `gv_cron_colisiones`** y se
> elige un minuto con pocos jobs y **ningún pesado**. NUNCA minuto redondo (:00, :30): ahí se
> amontonan los `*/10`, `*/15`, `*/30` y los de hora fija.

```sql
select minuto, jobs, pesados, detalle from public.gv_cron_colisiones;   -- mapa por minuto (pesados con *)
select jobid, jobname, schedule, avg_s, max_s, pesado from public.gv_cron_agenda order by avg_s desc nulls last;
```

Las tres prácticas, en orden de impacto:

1. **Un cron pesado NO se solapa consigo mismo.** Es lo que agota los slots: un job lento que
   sigue disparando se apila (el watchdog de 748 s llegó a ~12 instancias). Se envuelve el
   **command** del cron en un `DO` con `pg_try_advisory_xact_lock(hashtext('cron:<fn>')::bigint)`
   — si una corrida anterior sigue viva, la nueva se saltea. **No se toca el cuerpo de la
   función**; el lock se libera solo al terminar la transacción. Aplicado el 06/10 a los 5 pesados
   de LK (63, 39, 48, 41, 66).
2. **El minuto por FÓRMULA, no a dedo.** Un `*/10` en el offset `jobid % 10` (o cualquier minuto
   impar libre que muestre la vista) no cae con otro `*/10`. Así un cron nuevo se ubica solo sin
   romper a los demás.
3. **Medir, no adivinar.** La vista es la foto; se mira antes de agregar, no después de que se cae.

⚠ `gv_cron_colisiones` cuenta sólo los crons que corren **cada hora** (campo de hora `*`), que son
los del riesgo sostenido; los reportes de hora fija van en `gv_cron_agenda`. **Las dos vistas viven
en LK y en Gestión** (`sql/gv_cron_colisiones_antisolape_v2716.sql`). No subir la instancia (Luis,
28/09): el amontonamiento vuelve igual.

⚠ **Y hay ALARMA automática, no sólo el mapa** (Thomas, 06/10): cron **78 `gv-cron-slots-alarma`** de
LK (`1-59/5`, do-block con anti-solape) avisa al grupo de infra cuando **3+ jobs fallan con `job
startup timeout` o `statement timeout` en 6 min** — o sea cuando la base se queda sin worker slots,
en la cara inicial del episodio, no 2 h después. Dedup por hora. `sql/gv_cron_slots_alarma_20261006_LK.sql`.
Cubre lo que `gv_cron_colisiones` no: nadie tiene que mirar la tabla. **Falta el espejo en Gestión**
(GV tuvo 0 choques en 3 días, va después). Medido el 06/10: el incidente NO fue el bug de un cron
(39/48 corren 7-11 s normal; el 353 s era histórico) sino **contención general de la base de LK** con
el watchdog 63 de amplificador (sus ticks murieron con statement timeout de 6-12 min); el fix fue el
anti-solape + watchdog a 2 min. Las queries del incidente se perdieron (`pg_stat_statements` se
reseteó 12:44 UTC, ~cuando se cortó — quizás un restart de la base).

⚠ **Y se BAJÓ el gasto sostenido de LK (06/10, Thomas), no sólo la alarma** — los 3 syncs cruzados que
corrían cada 5 min eran el grueso. `sql/gv_lk_syncs_bajar_gasto_20261006_LK.sql`:
1. **Cadencia 5 → 15 min** en `sync-pedidos-match` (job 24, `9-59/15`) y `sync-reingresos` (job 39,
   `14-59/15`); minutos elegidos con `gv_cron_colisiones` (0 pesados, no se pisan).
2. **«Sólo si cambió»** (patrón `gv_refresh_stock_si_cambio`, FAIL-OPEN) en el COMMAND de cada cron,
   como do-block (no se edita ninguna función): pedidos con huella LOCAL barata (0,5 ms, orders +
   chef_orders_cache, ventana 21 días — un pedido nuevo o cambio de estado siempre la mueve; red de
   seguridad el job 70 cada hora); reingresos con hash de CONTENIDO de las 4 fuentes sobre el FDW a GV
   (~1,6 s; lo caro es que GV computa `v_lk_reingresos`). Las huellas en `app_settings['huella_sync_*']`.
3. ⚠ **El latido de la cache de precios de Chef se separó a su propio cron** (jobid 79
   `lk-item-precio-heartbeat`, `3-59/5`): `sync_reingresos_virgilio` llamaba al final a
   `sync_web_ocultos_virgilio`, que SIEMPRE corre `refrescar_item_precio_cache()` (~3,8 s) — y Pablo
   (06/10) dejó anotado que esa reconstrucción es lo ÚNICO que refresca `item_precio_cache` para los
   productos de Chef (FDW, sin trigger local). Gatear reingresos lo habría matado, y el paso 1 ya lo
   había bajado de 5 a 15 min sin querer. El cron nuevo corre `sync_web_ocultos_virgilio()` cada 5 min
   en los minutos viejos de reingresos (que ya cargaban ese trabajo): restaura la cadencia de Pablo sin
   tocar su función. **Ese latido (3,8 s × 12/h ≈ 54 s/h) pasa a ser el mayor gasto sostenido y queda
   AISLADO**: gatearlo necesita una huella de la fuente Chef (que paga el piso de ~2,4 s del FDW) o bajar
   su cadencia — decisión de Pablo.
4. **Chef (`sincronizar-chef-orders`, job 48) NO se gatea**: su costo es el piso de ~2,4 s de abrir el
   FDW a Chef (otra org/región), que una huella pagaría igual, y la copia alimenta el padrón y los
   pedidos de Chef del armado — un skip sacaría pedidos de la PPP. Queda en 10 min.
   Medido: ~204 → ~82 s/h en estos objetos (~60% menos). Marcadores internos de las funciones sin tocar.

⚠⚠ **Y el latido del punto 3 pasó de POLL CIEGO a EVENTO (06/10, Thomas, v27.18 — gasto ~49 → casi
nada, y el cambio se ve AL TOQUE).** El punto 3 dejaba el latido de precios de Chef / on-off web en un
poll de 5 min porque lo que aplica vive en OTRAS bases (Chef por FDW, GV por FDW) y un trigger local de
LK no lo puede ver. Pero los que CAMBIAN esas bases sí pueden avisarle a LK, así que ahora avisan:
- **RPC `public.web_ocultos_poke(p_rebuild)` en LK** (anon): marca `app_settings['web_ocultos_dirty']` y
  reconstruye `sync_web_ocultos_virgilio()` en el acto, con guard de 20 s + advisory lock (imposible
  martillarla). El **job 79 queda GATEADO**: cada 5 min reconstruye sólo si `dirty > done` o cada 30 min
  de backstop — ~0 cuando no cambió nada. **No se tocó `sync_web_ocultos_virgilio`** (la de Pablo): sólo se
  decide CUÁNDO corre.
- **on/off web (Gestión)**: `importacion.js` `pedImpWebVisible` → `_impPokeWebOcultos()` pokea
  `web_ocultos_poke` de LK (patrón de `_impSyncPaginas`, debounce 800 ms). El switch «Web» ya no espera 5 min.
- **precios de Chef**: TRIGGER en la base de Chef sobre `products` (after update of list_price, statement-level)
  que hace `net.http_post` a `web_ocultos_poke`. **Vive en el proyecto de Chef, se corre a mano** (está
  comentado en el .sql; esta sesión no tiene MCP sobre Chef). Hasta correrlo, Chef lo cubre el backstop de 30 min.
- **precios de LK**: nadie pokea — `products`/`loke_products`/`item_precios` YA reconstruyen por su trigger
  (`tg_item_precio_*`), así que para LK la cache siempre fue event-driven.
`sql/gv_web_ocultos_poke_20261006_LK.sql` (RPC + gate + el trigger de Chef para copiar y pegar, con rollback).

> **Horario (v31.39, 16/10):** los jobs 34, 55, 68, 81 y 109 corren sólo de 5:00 a 22:59 BsAs (`0,1,8-23` en UTC). No hay actividad de 23:00 a 4:59. El 25 queda 24 h por `watchdog_syncs_externos` (umbral 30 min).
