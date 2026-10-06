-- v27.16 (Luis, 2026-10-06) — ORGANIZACIÓN DE CRONS: vista de colisiones + anti-solape
-- =====================================================================================
-- Causa de fondo del 504 del 06/10: la base de LK se ahogó porque varios crons pesados
-- disparan en el mismo minuto (6 worker slots; cuando se agotan → `job startup timeout`
-- para todo lo demás) Y porque un cron lento se solapaba CONSIGO MISMO (el watchdog que
-- tardó 748 s y seguía disparando cada minuto llegó a ~12 instancias encimadas).
--
-- Esto resuelve la raíz con dos piezas, y se aplica en LK (kwkclwhmoygunqmlegrg) Y en
-- Gestión (hrxfctzncixxqmpfhskv):
--   1) gv_cron_colisiones / gv_cron_agenda  — SÓLO LECTURA (telemetría). Se consulta ANTES
--      de crear o mover un cron, para elegir un minuto libre (regla en el CLAUDE.md).
--   2) anti-solape por DO-block en el COMMAND del cron (no se toca el cuerpo de la función).
--
-- Rollback de la vista:   drop view if exists public.gv_cron_colisiones;
--                         drop view if exists public.gv_cron_agenda;
--                         drop function if exists public.gv_cron_minutos(text);
-- Rollback del anti-solape: restaurar el command original de cada cron (abajo, al final).

-- ---------------------------------------------------------------------------------------
-- 1) VISTA DE COLISIONES  (correr en LOS DOS proyectos)
-- ---------------------------------------------------------------------------------------

-- expande el campo de MINUTO de una expresión cron a los minutos 0-59 en que dispara.
-- soporta: *  ·  */N  ·  A-B/N  ·  A-B  ·  A  ·  A,B,C (y combinaciones con coma).
-- lo que no puede parsear devuelve NULL (se ve como minutos=null en gv_cron_agenda:
--   "una lectura rota no es un cero" — se ve, no se esconde).
create or replace function public.gv_cron_minutos(sched text)
returns int[] language plpgsql immutable as $$
declare f text; p text; out int[] := '{}'; a int; b int; st int;
begin
  f := split_part(btrim(sched), ' ', 1);
  if f is null or f = '' then return null; end if;
  foreach p in array string_to_array(f, ',') loop
    if p = '*' then
      out := out || (select array_agg(g) from generate_series(0,59) g);
    elsif p ~ '^\*/[0-9]+$' then
      st := split_part(p,'/',2)::int;
      out := out || (select array_agg(g) from generate_series(0,59,st) g);
    elsif p ~ '^[0-9]+-[0-9]+/[0-9]+$' then
      a := split_part(split_part(p,'/',1),'-',1)::int;
      b := split_part(split_part(p,'/',1),'-',2)::int;
      st := split_part(p,'/',2)::int;
      out := out || (select array_agg(g) from generate_series(a,b,st) g);
    elsif p ~ '^[0-9]+-[0-9]+$' then
      a := split_part(p,'-',1)::int; b := split_part(p,'-',2)::int;
      out := out || (select array_agg(g) from generate_series(a,b) g);
    elsif p ~ '^[0-9]+$' then
      out := out || array[p::int];
    else
      return null;
    end if;
  end loop;
  return (select array_agg(distinct g order by g) from unnest(out) g);
end $$;

-- un renglón por cron activo: en qué minutos dispara, si corre cada hora, y cuánto tarda
-- (promedio y máximo de los últimos 7 días). pesado = promedio >= 5 s.
create or replace view public.gv_cron_agenda as
select j.jobid, j.jobname, j.schedule,
       split_part(j.schedule,' ',2)='*' as cada_hora,
       public.gv_cron_minutos(j.schedule) as minutos,
       d.avg_s, d.max_s,
       coalesce(d.avg_s,0) >= 5 as pesado
from cron.job j
left join lateral (
  select round(avg(extract(epoch from end_time-start_time))::numeric,1) avg_s,
         round(max(extract(epoch from end_time-start_time))::numeric,1) max_s
  from cron.job_run_details r
  where r.jobid = j.jobid and r.start_time > now() - interval '7 days'
) d on true
where j.active;

-- un renglón por MINUTO del reloj (0-59): cuántos crons de-cada-hora disparan ahí, cuántos
-- pesados, y la lista (los pesados marcados con *). Los jobs de hora fija (reportes diarios)
-- no entran: el riesgo de slots es de los que corren cada hora. Hay 6 worker slots: si un
-- minuto junta más jobs pesados que eso, se cae todo.
create or replace view public.gv_cron_colisiones as
select m as minuto,
       count(*) as jobs,
       count(*) filter (where a.pesado) as pesados,
       string_agg(a.jobname || case when a.pesado then ' *' else '' end, ', '
                  order by a.pesado desc, a.jobname) as detalle
from public.gv_cron_agenda a
cross join lateral unnest(a.minutos) m
where a.cada_hora and a.minutos is not null
group by m
order by pesados desc, jobs desc, minuto;

-- ---------------------------------------------------------------------------------------
-- 2) ANTI-SOLAPE  (SÓLO LK — los 5 crons pesados; aplicado el 06/10)
-- ---------------------------------------------------------------------------------------
-- No se toca el cuerpo de la función: se envuelve el COMMAND del cron en un DO que toma un
-- advisory lock de transacción. Si una corrida anterior sigue viva (su sesión aún tiene el
-- lock), la nueva se saltea. El lock se libera solo al terminar la transacción del cron.
-- La llave es hashtext('cron:<fn>') — única por función, sin chocar con el 5768 del stock.

select cron.alter_job(63, command := $cmd$do $g$ begin if pg_try_advisory_xact_lock(hashtext('cron:gv_watch_gestion_tick')::bigint) then perform public.gv_watch_gestion_tick(); end if; end $g$;$cmd$);
select cron.alter_job(39, command := $cmd$do $g$ begin if pg_try_advisory_xact_lock(hashtext('cron:sync_reingresos_virgilio')::bigint) then perform public.sync_reingresos_virgilio(); end if; end $g$;$cmd$);
select cron.alter_job(48, command := $cmd$do $g$ begin if pg_try_advisory_xact_lock(hashtext('cron:sincronizar_chef_orders')::bigint) then perform public.sincronizar_chef_orders(90); end if; end $g$;$cmd$);
select cron.alter_job(41, command := $cmd$do $g$ begin if pg_try_advisory_xact_lock(hashtext('cron:sync_diferido_virgilio')::bigint) then perform public.sync_diferido_virgilio(); end if; end $g$;$cmd$);
select cron.alter_job(66, command := $cmd$do $g$ begin if pg_try_advisory_xact_lock(hashtext('cron:wa_avisos_retiro_web')::bigint) then perform public.wa_avisos_retiro_web(); end if; end $g$;$cmd$);

-- rollback del anti-solape (comando original de cada cron):
--   select cron.alter_job(63, command := 'select public.gv_watch_gestion_tick()');
--   select cron.alter_job(39, command := 'select public.sync_reingresos_virgilio();');
--   select cron.alter_job(48, command := 'select public.sincronizar_chef_orders(90);');
--   select cron.alter_job(41, command := 'select public.sync_diferido_virgilio();');
--   select cron.alter_job(66, command := 'select public.wa_avisos_retiro_web();');

-- ---------------------------------------------------------------------------------------
-- chequeo
-- ---------------------------------------------------------------------------------------
-- select minuto, jobs, pesados, detalle from public.gv_cron_colisiones;   -- mapa de choques
-- select jobid, jobname, schedule, cada_hora, avg_s, max_s, pesado from public.gv_cron_agenda order by avg_s desc nulls last;
