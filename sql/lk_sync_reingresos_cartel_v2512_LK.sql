-- v25.12 (Luis, 30/09) — PROYECTO LK (kwkclwhmoygunqmlegrg).
-- "desmarqué «cartel» pero sigue apareciendo en la página. ¿se puede hacer más automática la actualización?"
-- Las páginas leen reingreso_cache / reingreso_cache_chef, que rehace el cron 39 (sync_reingresos_virgilio)
-- cada 5 min. Esa función tarda ~11 s (8,4 s son sync_web_ocultos_virgilio) y anon corta a los 3 s, así que
-- el front no la puede llamar. Ésta rehace SÓLO el cartel (+ la fecha global de entrega): ~1,5 s medido.
-- La llama Gestión (importacion.js, _impSyncPaginas) al tocar Cartel / fecha de reingreso / entrega global.
-- Upsert + delete de lo que ya no viene (no delete+insert): si choca con el cron 39 no hay unique violation.
-- Si Virgilio no contesta, no toca nada: el cron 39 la rehace igual en <= 5 min.
create or replace function public.sync_reingresos_cartel_virgilio()
 returns void language plpgsql security definer set search_path to 'public'
as $function$
declare v_fecha text;
begin
  create temp table if not exists _rc_lk (cod text primary key, sin_stock boolean, fecha date) on commit drop;
  create temp table if not exists _rc_ch (cod text primary key, sin_stock boolean, fecha date) on commit drop;
  truncate _rc_lk; truncate _rc_ch;
  insert into _rc_lk select distinct on (cod) cod, coalesce(sin_stock,false), reingreso_est
    from virgilio.v_lk_reingresos where cod is not null;
  insert into _rc_ch select distinct on (cod) cod, coalesce(sin_stock,false), reingreso_est
    from virgilio.v_ch_reingresos where cod is not null;

  delete from public.reingreso_cache r where r.cod is not null and not exists (select 1 from _rc_lk t where t.cod = r.cod);
  insert into public.reingreso_cache (cod, sin_stock, fecha_reingreso, updated_at)
    select cod, sin_stock, fecha, now() from _rc_lk
    on conflict (cod) do update set sin_stock = excluded.sin_stock, fecha_reingreso = excluded.fecha_reingreso, updated_at = now()
     where reingreso_cache.sin_stock is distinct from excluded.sin_stock
        or reingreso_cache.fecha_reingreso is distinct from excluded.fecha_reingreso;

  delete from public.reingreso_cache_chef r where r.cod is not null and not exists (select 1 from _rc_ch t where t.cod = r.cod);
  insert into public.reingreso_cache_chef (cod, sin_stock, fecha_reingreso, updated_at)
    select cod, sin_stock, fecha, now() from _rc_ch
    on conflict (cod) do update set sin_stock = excluded.sin_stock, fecha_reingreso = excluded.fecha_reingreso, updated_at = now()
     where reingreso_cache_chef.sin_stock is distinct from excluded.sin_stock
        or reingreso_cache_chef.fecha_reingreso is distinct from excluded.fecha_reingreso;

  select nullif(btrim(vc.valor), '') into v_fecha from virgilio.v_lk_config vc
   where vc.clave = 'entrega_estimada_global' limit 1;
  if v_fecha is null then
    delete from public.app_settings where key = 'fecha_estimada_entrega';
  else
    insert into public.app_settings (key, value) values ('fecha_estimada_entrega', v_fecha)
    on conflict (key) do update set value = excluded.value;
  end if;
exception when others then
  raise notice 'sync_reingresos_cartel_virgilio: Virgilio no disponible (%)', sqlerrm;
end;
$function$;
revoke all on function public.sync_reingresos_cartel_virgilio() from public;
grant execute on function public.sync_reingresos_cartel_virgilio() to anon, authenticated, service_role;
-- Rollback: drop function if exists public.sync_reingresos_cartel_virgilio();
