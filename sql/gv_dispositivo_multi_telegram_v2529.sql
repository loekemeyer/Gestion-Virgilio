-- v25.29 (Luis, 30/09): "que avise por Telegram cuando pase" — un mismo celular/PC con 2+ operarios en el día.
-- Aplicado el 30/09. La vista reemplaza a la de la v25.26 (nombres de Empleados + columna claves).
drop view if exists public.gv_dispositivo_multi_operario;
create view public.gv_dispositivo_multi_operario with (security_invoker = true) as
with u as (
  select dispositivo, (created_at at time zone 'America/Argentina/Buenos_Aires')::date dia,
         coalesce(nullif(legajo,''), email) quien, created_at ts
    from public."GV_Dispositivo_Login"
  union all
  select r.gv_dispositivo, (r.created_at at time zone 'America/Argentina/Buenos_Aires')::date,
         r.legajo, r.created_at
    from public."Registros_Produccion_Virgilio" r
   where r.gv_dispositivo is not null and not public.es_legajo_test(r.legajo)
), q as (
  select u.dispositivo, u.dia, u.quien, min(u.ts) desde,
         coalesce((select e."Empleado" from public."Empleados" e where e."Legajo"::text = u.quien limit 1),
                  (select l.nombre from public."GV_Dispositivo_Login" l where l.dispositivo = u.dispositivo
                     and coalesce(nullif(l.legajo,''), l.email) = u.quien and nullif(l.nombre,'') is not null limit 1),
                  u.quien) nombre
    from u group by u.dispositivo, u.dia, u.quien
)
select dispositivo, dia, count(*) operarios,
       string_agg(nombre || case when quien ~ '^[0-9]+$' then ' (' || quien || ')' else '' end
                  || ' desde ' || to_char(desde at time zone 'America/Argentina/Buenos_Aires','HH24:MI'), ' · ' order by desde) quienes,
       min(desde) primero, max(desde) ultimo,
       (select l.user_agent from public."GV_Dispositivo_Login" l where l.dispositivo = q.dispositivo
         order by l.created_at desc limit 1) user_agent,
       string_agg(quien, ',' order by quien) claves
  from q group by dispositivo, dia having count(*) > 1;
revoke all on public.gv_dispositivo_multi_operario from anon, authenticated;

-- Un Telegram por cada operario NUEVO que aparece en el mismo dispositivo en el día
-- (dedup = dispositivo + día + md5 de los legajos: el mismo set no se repite).
create or replace function public.gv_alerta_dispositivo_multi_operario_telegram()
returns int language plpgsql security definer set search_path to 'public','pg_temp' as $f$
declare r record; n int := 0; v_hoy date := (now() at time zone 'America/Argentina/Buenos_Aires')::date;
begin
  for r in select * from public.gv_dispositivo_multi_operario where dia = v_hoy loop
    perform public.tg_enqueue(
      '📱 GESTIÓN — UN MISMO CELULAR CON ' || r.operarios || ' OPERARIOS (' || to_char(v_hoy,'DD/MM') || ')' || E'\n' ||
      r.quienes || E'\n' ||
      'Dispositivo ' || left(r.dispositivo, 8) || coalesce(' · ' || left(r.user_agent, 90), ''),
      'gv_disp_multi_' || r.dispositivo || '_' || v_hoy::text || '_' || md5(r.claves));
    n := n + 1;
  end loop;
  if n > 0 then perform public.tg_outbox_flush(); end if;
  return n;
end $f$;
revoke all on function public.gv_alerta_dispositivo_multi_operario_telegram() from public, anon, authenticated;
select cron.schedule('gv-alerta-dispositivo-multi', '5-59/10 * * * *',
  'select public.gv_alerta_dispositivo_multi_operario_telegram()');   -- jobid 118, minutos impares
-- Probado en transacción abortada: legajos 104 y 277 en un dispositivo -> 1 fila, operarios 2,
-- "Jhonny Moncayo (104) desde 15:29 · Jhonny Cartaya (277) desde 15:29".
-- Rollback: select cron.unschedule('gv-alerta-dispositivo-multi');
--           drop function public.gv_alerta_dispositivo_multi_operario_telegram();
