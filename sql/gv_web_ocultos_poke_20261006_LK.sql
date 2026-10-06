-- ============================================================================
-- CACHE DE PRECIOS / ON-OFF WEB AL TOQUE  ·  LK (kwkclwhmoygunqmlegrg)  ·  2026-10-06 (Thomas)
-- ----------------------------------------------------------------------------
-- PROBLEMA: el latido lk-item-precio-heartbeat (job 79) corría sync_web_ocultos_virgilio()
--   cada 5 min SIEMPRE (~4,1 s = ~49 s/h), el mayor gasto sostenido que quedaba en LK. Pero
--   lo que ese sync aplica casi nunca cambia:
--     · precios de LK   → products / loke_products / item_precios YA tienen trigger
--                         (tg_item_precio_*) que reconstruye item_precio_cache en cada write.
--     · precios de Chef → chef_ext.products (FDW a la base de Chef). Un trigger LOCAL de LK NO
--                         puede verlos: el update ocurre en otra base.
--     · on/off web      → GV_Web_Oculto de Gestión, leída por v_lk_web_ocultos (FDW). Mismo caso.
--   O sea: el poll de 5 min existía SÓLO por lo remoto (Chef + Gestión), y lo pagaba siempre.
--
-- SOLUCIÓN: EVENTO en vez de POLL. Quien cambia algo remoto le avisa a LK y LK reconstruye al
--   toque; el job 79 pasa a red de seguridad gateada (reconstruye sólo si quedó algo pendiente,
--   o cada 30 min como backstop). Patrón de flag sucio + "sólo si cambió", FAIL-OPEN.
--
--   1) RPC public.web_ocultos_poke(p_rebuild boolean default true)  [ESTE ARCHIVO, ya aplicada]
--      - marca app_settings['web_ocultos_dirty'] = now()  (barato, siempre)
--      - si p_rebuild y no se reconstruyó en los últimos 20 s: corre sync_web_ocultos_virgilio()
--        y marca app_settings['web_ocultos_done'] = now().  El guard de 20 s + advisory lock
--        hacen imposible martillarla (máx ~1 reconstrucción cada 20 s, global).
--      - anon la puede correr (la llama el front de Gestión y el trigger de Chef con la
--        publishable de LK). Es idempotente y no toca datos de negocio salvo el refresco.
--
--   2) job 79 gateado  [ESTE ARCHIVO, ya aplicado por select cron.alter_job]
--      - cada 5 min, ~0 cuando no hay nada pendiente (dos lecturas de app_settings).
--      - reconstruye si dirty > done, o si done tiene más de 30 min (backstop).
--
--   3) quién POKEA (instantáneo):
--      - on/off web (Gestión) → importacion.js pedImpWebVisible → _impPokeWebOcultos()
--        → POST a LK /rest/v1/rpc/web_ocultos_poke  (v27.18 de Gestión-Virgilio)
--      - precios de Chef      → TRIGGER en la base de CHEF (abajo; correr A MANO en Chef)
--      - precios de LK        → nadie: ya reconstruyen por su propio trigger.
--
-- GASTO: ~49 s/h → casi nada cuando no cambia nada + 2 reconstrucciones/h del backstop (~8 s/h)
--   + una por cada cambio real. Y el cambio se ve al toque, no en 5 min.
--
-- ROLLBACK:
--   select cron.alter_job(79, command := $$do $g$ begin
--     if pg_try_advisory_xact_lock(hashtext('cron:lk_item_precio_heartbeat')::bigint)
--     then perform public.sync_web_ocultos_virgilio(); end if; end $g$;$$);
--   drop function if exists public.web_ocultos_poke(boolean);
--   delete from public.app_settings where key in ('web_ocultos_dirty','web_ocultos_done');
--
-- CHEQUEO:
--   select public.web_ocultos_poke(true);  -- reconstruido=true la 1ª, false si se repite <20s
--   select key, value from public.app_settings where key like 'web_ocultos_%';
--   select jobid, jobname, schedule from cron.job where jobid=79;
-- ============================================================================

-- 1) RPC (ya aplicada en LK)
create or replace function public.web_ocultos_poke(p_rebuild boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $fn$
declare
  v_done timestamptz;
  v_now  timestamptz := now();
  v_did  boolean := false;
begin
  insert into public.app_settings(key, value) values ('web_ocultos_dirty', v_now::text)
    on conflict (key) do update set value = excluded.value;

  if coalesce(p_rebuild, true) then
    select nullif(value,'')::timestamptz into v_done
      from public.app_settings where key = 'web_ocultos_done';
    if v_done is null or v_done < v_now - interval '20 seconds' then
      if pg_try_advisory_xact_lock(hashtext('lk:web_ocultos_poke')::bigint) then
        perform public.sync_web_ocultos_virgilio();
        insert into public.app_settings(key, value) values ('web_ocultos_done', now()::text)
          on conflict (key) do update set value = excluded.value;
        v_did := true;
      end if;
    end if;
  end if;

  return jsonb_build_object('ok', true, 'reconstruido', v_did, 'ts', v_now);
end
$fn$;

revoke all on function public.web_ocultos_poke(boolean) from public;
grant execute on function public.web_ocultos_poke(boolean) to anon, authenticated, service_role;

-- 2) gate del job 79 (ya aplicado)
select cron.alter_job(79, command := $cmd$
do $g$
declare v_dirty timestamptz; v_done timestamptz;
begin
  if not pg_try_advisory_xact_lock(hashtext('cron:lk_item_precio_heartbeat')::bigint) then return; end if;
  select nullif(value,'')::timestamptz into v_dirty from public.app_settings where key='web_ocultos_dirty';
  select nullif(value,'')::timestamptz into v_done  from public.app_settings where key='web_ocultos_done';
  if v_done is null
     or (v_dirty is not null and v_dirty > v_done)
     or v_done < now() - interval '30 minutes' then
    perform public.sync_web_ocultos_virgilio();
    insert into public.app_settings(key,value) values('web_ocultos_done', now()::text)
      on conflict (key) do update set value=excluded.value;
  end if;
end $g$;
$cmd$);


-- ============================================================================
-- 3) TRIGGER EN LA BASE DE CHEF  (nkhzocgdpwtgrmwleihr)  —  CORRER A MANO EN EL SQL EDITOR DE CHEF
-- ----------------------------------------------------------------------------
-- Avisa a LK cuando cambia un precio de Chef, para que LK reconstruya item_precio_cache al toque
-- en vez de esperar el poll. Dispara un net.http_post "fire-and-forget" contra web_ocultos_poke de
-- LK; LK coalesce (guard de 20 s), así una lista de N filas o N updates = 1 reconstrucción.
--
-- Requisitos en Chef: extensión pg_net (viene en Supabase). La clave es la PUBLISHABLE de LK
-- (es pública: ya está embebida en el front). Si Chef un día rota la forma de cargar precios, el
-- trigger sigue valiendo: escucha la TABLA products, no una pantalla.
--
--   create extension if not exists pg_net;   -- normalmente ya está
--
-- create or replace function public.lk_avisar_precio_cambio()
-- returns trigger
-- language plpgsql
-- security definer
-- set search_path = public, extensions
-- as $$
-- begin
--   perform net.http_post(
--     url := 'https://kwkclwhmoygunqmlegrg.supabase.co/rest/v1/rpc/web_ocultos_poke',
--     headers := jsonb_build_object(
--       'Content-Type','application/json',
--       'apikey','sb_publishable_mVX5MnjwM770cNjgiL6yLw_LDNl9pML',
--       'Authorization','Bearer sb_publishable_mVX5MnjwM770cNjgiL6yLw_LDNl9pML'),
--     body := jsonb_build_object('p_rebuild', true)::text
--   );
--   return null;
-- exception when others then
--   return null;   -- nunca frenar la carga de precios por el aviso
-- end
-- $$;
--
-- drop trigger if exists trg_lk_avisar_precio on public.products;
-- create trigger trg_lk_avisar_precio
--   after update of list_price on public.products
--   for each statement
--   execute function public.lk_avisar_precio_cambio();
--
-- -- CHEQUEO (en Chef): tocá un precio y mirá que LK reconstruya
-- --   update public.products set list_price = list_price where cod = '<algún cod>';
-- -- y en LK:  select value from public.app_settings where key = 'web_ocultos_done';  (debe moverse)
-- ============================================================================
