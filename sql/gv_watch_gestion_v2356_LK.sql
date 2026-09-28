-- v23.56 (Luis, 28/09): aviso por Telegram si la base de GESTIÓN deja de contestar.
-- Caída del 28/09 14:11–14:19 ART: la base no contestó 8 min y nadie se enteró por el sistema.
-- El vigilante NO puede vivir en la base que vigila (se cae con ella): corre en LK
-- (kwkclwhmoygunqmlegrg), que es otra instancia y ya manda Telegram al grupo de Gestión.
--
--   GESTIÓN: public.gv_ping()  -> devuelve now(); anon puede ejecutarla (no lee tablas).
--   LK:      cron 'gv-watch-gestion' cada minuto -> public.gv_watch_gestion_tick()
--              1) resuelve los pings anteriores contra net._http_response
--              2) 3 fallas seguidas (~3 min) -> "🔴 la base de Gestión no contesta"
--              3) primer OK después de avisar -> "🟢 volvió · N min caída"
--              4) manda el ping nuevo (timeout 15 s)
--
-- Chequeo (en LK):  select * from public.gv_watch_gestion order by id desc limit 10;
--                   select * from public.gv_watch_gestion_estado;
-- Rollback (en LK): select cron.unschedule('gv-watch-gestion');
--                   drop function public.gv_watch_gestion_tick();
--                   drop table public.gv_watch_gestion, public.gv_watch_gestion_estado;

-- ===== GESTIÓN (hrxfctzncixxqmpfhskv) =====
-- create or replace function public.gv_ping() returns timestamptz language sql stable
--   set search_path = public, pg_temp as $$ select now() $$;
-- revoke all on function public.gv_ping() from public;
-- grant execute on function public.gv_ping() to anon, authenticated;

-- ===== LK (kwkclwhmoygunqmlegrg) =====
create table if not exists public.gv_watch_gestion (
  id           bigserial primary key,
  request_id   bigint,
  pedido_en    timestamptz not null default now(),
  estado       text not null default 'pendiente',   -- pendiente | ok | falla
  status_code  int,
  detalle      text,
  resuelto_en  timestamptz
);
alter table public.gv_watch_gestion enable row level security;
revoke all on public.gv_watch_gestion from anon, authenticated;

create table if not exists public.gv_watch_gestion_estado (
  id           int primary key default 1 check (id = 1),
  caida_desde  timestamptz,
  avisado      boolean not null default false
);
insert into public.gv_watch_gestion_estado (id) values (1) on conflict do nothing;
alter table public.gv_watch_gestion_estado enable row level security;
revoke all on public.gv_watch_gestion_estado from anon, authenticated;

create or replace function public.gv_watch_gestion_tick()
returns text language plpgsql security definer
set search_path = public, net, pg_temp as $f$
declare
  v_fallas_seguidas int := 3;                -- ~3 min sin contestar
  v_chat  text := '-1004379879565';          -- grupo de Gestión
  v_url   text := 'https://hrxfctzncixxqmpfhskv.supabase.co/rest/v1/rpc/gv_ping';
  v_key   text := 'sb_publishable_BqpAgZH6ty-9wft10_YMhw_0rcIPuWT';
  v_ult   text[];
  v_est   record;
  v_req   bigint;
  v_min   int;
begin
  -- 1) resolver los pings pendientes
  update public.gv_watch_gestion w
     set estado = case when r.status_code = 200 and not coalesce(r.timed_out,false) then 'ok' else 'falla' end,
         status_code = r.status_code,
         detalle = left(coalesce(r.error_msg, case when r.status_code <> 200 then r.content end, ''), 200),
         resuelto_en = now()
    from net._http_response r
   where w.estado = 'pendiente' and r.id = w.request_id;
  update public.gv_watch_gestion
     set estado = 'falla', detalle = 'sin respuesta en 60 s', resuelto_en = now()
   where estado = 'pendiente' and pedido_en < now() - interval '60 seconds';

  select array_agg(estado order by id desc) into v_ult
    from (select id, estado from public.gv_watch_gestion
           where estado <> 'pendiente' order by id desc limit v_fallas_seguidas) z;
  select * into v_est from public.gv_watch_gestion_estado where id = 1;

  -- 2) caída
  if coalesce(array_length(v_ult,1),0) = v_fallas_seguidas
     and not ('ok' = any(v_ult)) and not v_est.avisado then
    update public.gv_watch_gestion_estado
       set avisado = true,
           caida_desde = (select min(pedido_en) from (select pedido_en from public.gv_watch_gestion
                           where estado <> 'pendiente' order by id desc limit v_fallas_seguidas) z)
     where id = 1
     returning * into v_est;
    perform public.tg_enqueue(
      '🔴 La base de Gestión Virgilio NO CONTESTA desde las '
      || to_char(v_est.caida_desde at time zone 'America/Argentina/Buenos_Aires','HH24:MI')
      || '. Los celulares no pueden grabar ni loguearse. Si no vuelve en 10 min: Dashboard de Supabase → proyecto hrxfctzncixxqmpfhskv → Restart.',
      'gv-caida-' || extract(epoch from v_est.caida_desde)::bigint, v_chat);
  -- 3) volvió
  elsif v_est.avisado and v_ult[1] = 'ok' then
    v_min := greatest(1, round(extract(epoch from now() - v_est.caida_desde) / 60)::int);
    perform public.tg_enqueue(
      '🟢 La base de Gestión Virgilio volvió a contestar ('
      || to_char(now() at time zone 'America/Argentina/Buenos_Aires','HH24:MI')
      || '). Estuvo caída ~' || v_min || ' min. Revisar que los celulares hayan subido lo pendiente.',
      'gv-volvio-' || extract(epoch from v_est.caida_desde)::bigint, v_chat);
    update public.gv_watch_gestion_estado set avisado = false, caida_desde = null where id = 1;
  end if;

  -- 4) ping nuevo
  select net.http_post(url := v_url, body := '{}'::jsonb,
           headers := jsonb_build_object('apikey', v_key, 'Content-Type', 'application/json'),
           timeout_milliseconds := 15000) into v_req;
  insert into public.gv_watch_gestion (request_id) values (v_req);

  delete from public.gv_watch_gestion where pedido_en < now() - interval '7 days';
  return coalesce(array_to_string(v_ult, ','), '-');
end $f$;
revoke all on function public.gv_watch_gestion_tick() from public, anon, authenticated;

select cron.schedule('gv-watch-gestion', '* * * * *', 'select public.gv_watch_gestion_tick()');
