-- v25.18 (Luis, 30/09/2026): boton "Refrescar ya" en la tabla de Stocks.
-- "2 minutos es un monton". El refresco completo (matview + stocks_carga_rapida) tarda
-- ~7,4 s medidos (1,7 s + 5,7 s) y `authenticated` corta a los 8 s, asi que el navegador
-- NO lo corre directo: la RPC agenda un job de pg_cron de un solo disparo ('2 seconds'),
-- que corre como postgres sin statement_timeout, se borra a si mismo y refresca.
-- La pantalla espera mirando gv_stock_refresco_ultimo() y recarga cuando cambia.
--
-- Rollback:
--   select cron.unschedule('gv-stock-refrescar-ya') where exists (select 1 from cron.job where jobname='gv-stock-refrescar-ya');
--   drop function if exists public.gv_stock_refrescar_ya(); drop function if exists public.gv_stock_refrescar_job();
--   drop function if exists public.gv_stock_refresco_ultimo();

create or replace function public.gv_stock_refrescar_job()
returns void language plpgsql security definer
set search_path to 'public','pg_catalog'
as $function$
declare v_mot text;
begin
  -- PRIMERO se borra el job: si algo de abajo explota, no queda repitiendose cada 2 s.
  begin
    perform cron.unschedule('gv-stock-refrescar-ya');
  exception when others then null;
  end;
  select motivo into v_mot from public.gv_refresh_stock_si_cambio(0, false);
  -- si el lock 5768 estaba tomado (cron 57 / 68), la derivada no se reescribio: acá SI
  -- se espera (es un job en segundo plano, no el navegador).
  if v_mot ilike '%lock ocupado%' then
    perform pg_advisory_xact_lock(5768);
    perform public.refresh_stocks_carga_rapida();
    update public."GV_Stock_Refresh_Estado" set refrescado_en = now(),
           ultimo_motivo = left('boton Refrescar ya + carga_rapida (espero el lock)', 400)
     where id = 1;
  end if;
end $function$;

create or replace function public.gv_stock_refrescar_ya()
returns jsonb language plpgsql security definer
set search_path to 'public','pg_catalog'
as $function$
declare v_ult timestamptz;
begin
  if not (public.es_supervisor_virgilio() or public.gv_es_supervisor_o_servicio()) then
    raise exception 'Solo un supervisor puede forzar el refresco del stock';
  end if;
  select refrescado_en into v_ult from public."GV_Stock_Refresh_Estado" where id = 1;
  if exists (select 1 from cron.job where jobname = 'gv-stock-refrescar-ya') then
    return jsonb_build_object('estado','en_curso','antes',v_ult);
  end if;
  perform cron.schedule('gv-stock-refrescar-ya', '2 seconds', 'select public.gv_stock_refrescar_job()');
  return jsonb_build_object('estado','agendado','antes',v_ult);
end $function$;

create or replace function public.gv_stock_refresco_ultimo()
returns timestamptz language sql stable security definer
set search_path to 'public','pg_catalog'
as $function$ select refrescado_en from public."GV_Stock_Refresh_Estado" where id = 1 $function$;

revoke all on function public.gv_stock_refrescar_job() from public, anon, authenticated;
revoke all on function public.gv_stock_refrescar_ya() from public, anon;
grant execute on function public.gv_stock_refrescar_ya() to authenticated, service_role;
revoke all on function public.gv_stock_refresco_ultimo() from public;
grant execute on function public.gv_stock_refresco_ultimo() to anon, authenticated, service_role;
