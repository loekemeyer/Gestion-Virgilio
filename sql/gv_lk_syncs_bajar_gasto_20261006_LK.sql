-- ============================================================================
-- BAJAR EL GASTO DE LOS SYNCS CRUZADOS  ·  LK (kwkclwhmoygunqmlegrg)  ·  2026-10-06 (Thomas)
-- ----------------------------------------------------------------------------
-- QUÉ: el 06/10 LK se saturó (worker slots) y el armado de Gestión murió 2 h. La
--      alarma (gv-cron-slots-alarma, ver sql/gv_cron_slots_alarma_20261006_LK.sql) es
--      el aviso; esto BAJA el gasto real para que no llegue a dispararse. El gasto
--      sostenido de LK venía de 3 syncs cruzados que corrían cada 5 min. En una
--      instancia chica con I/O frío cada corrida cuesta de más.
--
-- CÓMO (todo por `select cron.alter_job/schedule(...)`, sin DDL que cuelgue el MCP):
--
--  1) CADENCIA 5 → 15 min en los dos pesados:
--       - job 24 sync-pedidos-match-virgilio : 1-59/5  → 9-59/15  (9,24,39,54)
--       - job 39 sync-reingresos-virgilio     : 3-59/5  → 14-59/15 (14,29,44,59)
--     Minutos elegidos con public.gv_cron_colisiones: 0 pesados, no se pisan entre
--     sí ni con sincronizar-chef-orders (2,12,22,32,42,52). Solo esto ya baja de 12
--     a 4 corridas/hora cada uno.
--
--  2) "SÓLO SI CAMBIÓ" (patrón de gv_refresh_stock_si_cambio, FAIL-OPEN) en el COMMAND
--     de cada cron, como do-block (no se edita ninguna función):
--
--     job 24 (pedidos-match): huella LOCAL y barata (0,5 ms, index scan) de lo que
--       alimenta v_pedidos_match — orders LK + chef_orders_cache, ventana 21 días:
--       count, max(id), max(created_at) y sum(hashtext(status||enviado_a_compras_at)).
--       Un pedido NUEVO o un cambio de estado SIEMPRE mueve la huella. Si no cambió,
--       no corre el sync (ni el de vendedor_avisos, que es derivado). Red de seguridad:
--       gv-pedidos-match-viejos (jobid 70, cada hora :37) resincroniza igual, así que
--       una edición cosmética que no mueva la huella (p.ej. observaciones) se corrige
--       en ≤ 1 h. La huella vive en public.app_settings['huella_sync_pedidos_match'].
--
--     job 39 (reingresos): huella de CONTENIDO de las 4 fuentes sobre el FDW a GV
--       (~1,6 s; lo caro es que GV computa v_lk_reingresos, 1,3 s — solo 104+17 filas
--       viajan): sum(hashtext(cod||sin_stock||reingreso_est)) de v_lk/v_ch_reingresos,
--       v_lk_config['entrega_estimada_global'] y content-hash de v_lk_dias_habiles.
--       Cualquier cambio de fecha/stock/feriado mueve la huella. Si no cambió, no
--       corre el sync (11 s). Blast radius bajo: una huella que falle solo deja un
--       cartel de reingreso viejo en la web, nunca un pedido fuera de la PPP. La huella
--       vive en public.app_settings['huella_sync_reingresos'].
--
--  3) ⚠ LATIDO DE LA CACHE DE PRECIOS DE CHEF — se SEPARÓ a su propio cron.
--     sync_reingresos_virgilio llamaba al final a sync_web_ocultos_virgilio, que SIEMPRE
--     corre refrescar_item_precio_cache() (~3,8 s). Pablo (06/10) dejó anotado que esa
--     reconstrucción es LO ÚNICO que mantiene fresca item_precio_cache para los productos
--     de Chef (leídos por FDW, sin trigger local). Gatear reingresos lo habría matado, y
--     bajarlo a 15 min (paso 1) ya lo había ralentizado de 5 a 15 min sin querer.
--     Por eso va en un cron propio (jobid 79 'lk-item-precio-heartbeat', 3-59/5 = los
--     minutos que reingresos usaba antes, que ya cargaban ese trabajo), que corre
--     sync_web_ocultos_virgilio() cada 5 min. Restaura exactamente la cadencia de Pablo.
--     NO se editó ninguna función: cuando reingresos SÍ dispara, re-corre web_ocultos una
--     vez de más (idempotente, ~1-4 veces/hora).
--
-- CHEF (job 48 sincronizar-chef-orders) — NO se gatea, a propósito. Su costo es el piso
--     de ~2,4 s de ABRIR la conexión FDW al proyecto de Chef (otra org/región); una huella
--     pagaría ese piso igual, así que ahorraría poco, y la copia alimenta el padrón y los
--     pedidos de Chef que el armado necesita: un skip equivocado saca pedidos de Chef de la
--     PPP. Queda en 10 min como estaba.
--
-- MEDICIÓN (por hora, estos objetos):
--     antes:  pedidos 12×~6s=72s + reingresos 12×11s=132s                  = ~204 s/h
--     después: pedidos 4×(skip/6s) ~12s + latido 12×~4,5s=54s +
--              reingresos 4×(1,6s/11s) ~16s                                 = ~82 s/h  (~60% menos)
--     El latido (54 s/h) pasa a ser el mayor gasto sostenido y queda AISLADO y visible.
--
-- ROLLBACK:
--   select cron.alter_job(24, schedule := '1-59/5 * * * *',
--     command := 'select public.sync_pedidos_match_virgilio(); select public.sync_vendedor_avisos_virgilio();');
--   select cron.alter_job(39, schedule := '3-59/5 * * * *',
--     command := $$do $g$ begin if pg_try_advisory_xact_lock(hashtext('cron:sync_reingresos_virgilio')::bigint)
--                  then perform public.sync_reingresos_virgilio(); end if; end $g$;$$);
--   select cron.unschedule('lk-item-precio-heartbeat');
--   delete from public.app_settings where key in ('huella_sync_pedidos_match','huella_sync_reingresos');
--
-- CHEQUEO:
--   select jobid, jobname, schedule from cron.job where jobid in (24,39,48) or jobname='lk-item-precio-heartbeat';
--   select key, value from public.app_settings where key like 'huella_sync_%';
--   select * from public.gv_cron_colisiones order by minuto;   -- el mapa ya no tiene reingresos cada 5 min
-- ============================================================================

-- 1) cadencias (ver gv_cron_colisiones antes de mover de nuevo)
select cron.alter_job(24, schedule := '9-59/15 * * * *');
select cron.alter_job(39, schedule := '14-59/15 * * * *');

-- 2a) gate pedidos-match (huella local, ~0,5 ms; FAIL-OPEN)
select cron.alter_job(24, command := $cmd$
do $g$
declare v_h text; v_prev text;
begin
  if not pg_try_advisory_xact_lock(hashtext('cron:sync_pedidos_match_virgilio')::bigint) then return; end if;
  begin
    select md5(
      (select count(*)::text||':'||coalesce(max(id)::text,'')||':'||coalesce(max(created_at)::text,'')||':'||
              coalesce(sum(hashtext(coalesce(status,'')||coalesce(enviado_a_compras_at::text,'')))::text,'0')
         from public.orders where created_at >= now() - interval '21 days')
      ||'|'||
      (select count(*)::text||':'||coalesce(max(id)::text,'')||':'||coalesce(max(created_at)::text,'')||':'||
              coalesce(sum(hashtext(coalesce(status,'')||coalesce(enviado_a_compras_at::text,'')))::text,'0')
         from public.chef_orders_cache where created_at >= now() - interval '21 days')
    ) into v_h;
  exception when others then v_h := null; end;
  select value into v_prev from public.app_settings where key='huella_sync_pedidos_match';
  if v_h is null or v_prev is null or v_prev is distinct from v_h then
    perform public.sync_pedidos_match_virgilio();
    perform public.sync_vendedor_avisos_virgilio();
    if v_h is not null then
      insert into public.app_settings(key,value) values('huella_sync_pedidos_match', v_h)
        on conflict (key) do update set value=excluded.value;
    end if;
  end if;
end $g$;
$cmd$);

-- 2b) gate reingresos (huella de contenido de las 4 fuentes sobre FDW, ~1,6 s; FAIL-OPEN)
select cron.alter_job(39, command := $cmd$
do $g$
declare v_h text; v_prev text;
begin
  if not pg_try_advisory_xact_lock(hashtext('cron:sync_reingresos_virgilio')::bigint) then return; end if;
  begin
    select md5(
      coalesce((select sum(hashtext(coalesce(cod,'')||'|'||coalesce(sin_stock::text,'')||'|'||coalesce(reingreso_est::text,''))) from virgilio.v_lk_reingresos)::text,'')||'/'||
      coalesce((select sum(hashtext(coalesce(cod,'')||'|'||coalesce(sin_stock::text,'')||'|'||coalesce(reingreso_est::text,''))) from virgilio.v_ch_reingresos)::text,'')||'/'||
      coalesce((select valor from virgilio.v_lk_config where clave='entrega_estimada_global'),'')||'/'||
      coalesce((select sum(hashtext(coalesce(fecha::text,'')||'|'||coalesce(habil::text,''))) from virgilio.v_lk_dias_habiles)::text,'')
    ) into v_h;
  exception when others then v_h := null; end;
  select value into v_prev from public.app_settings where key='huella_sync_reingresos';
  if v_h is null or v_prev is null or v_prev is distinct from v_h then
    perform public.sync_reingresos_virgilio();
    if v_h is not null then
      insert into public.app_settings(key,value) values('huella_sync_reingresos', v_h)
        on conflict (key) do update set value=excluded.value;
    end if;
  end if;
end $g$;
$cmd$);

-- 3) latido de la cache de precios de Chef, separado a su propio cron (5 min, cadencia de Pablo)
select cron.schedule('lk-item-precio-heartbeat', '3-59/5 * * * *', $cmd$
do $g$ begin
  if pg_try_advisory_xact_lock(hashtext('cron:lk_item_precio_heartbeat')::bigint) then
    perform public.sync_web_ocultos_virgilio();
  end if;
end $g$;
$cmd$);
