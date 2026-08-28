-- Watchdog de los syncs externos — APLICADO 2026-08-28
-- (migración `watchdog_syncs_externos`). Copia versionada.
--
-- Problema: si un cron de sync deja de correr, el dato espejado queda viejo y NADIE
-- se entera. El cron de fichadas ya venía acumulando 9 fallos en 48 h sin aviso.
--
-- Diseño deliberadamente SIMPLE: NO se creó tabla `Sync_Estado`.
-- `cron.job_run_details` ya tiene la verdad (qué corrió, cuándo, con qué status),
-- así que el watchdog la lee. Menos piezas = menos cosas que mantener.
--
-- Umbral por sync = ~3x su período, para no avisar por un fallo aislado que se
-- recupera solo en la próxima corrida:
--   job 25 sync-fichadas-respuestas  (cada 2 min)  -> alerta si > 30 min sin OK
--   job 26 sync-fichadas-estructura  (cada 10 min) -> alerta si > 60 min sin OK
--   job 27 sync-ppp-entregados-meta  (:07 y :37)   -> alerta si > 120 min sin OK
--
-- Dedup por (sync + día): máximo UN aviso por sync por día aunque corra cada hora.
-- Reusa tg_enqueue/tg_outbox_flush como el resto de las alertas del proyecto.
-- El cron corre a los :23 de cada hora (fuera de los minutos de los syncs).
--
-- Prueba al aplicar: "watchdog ok · avisos=0 · sync-fichadas-respuestas=0min
-- sync-fichadas-estructura=0min sync-ppp-entregados-meta=3min".
--
-- Para agregar un sync nuevo: sumarlo al VALUES (jobid, umbral_min) de abajo.

create or replace function public.watchdog_syncs_externos()
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  r record;
  v_dia   text := to_char((now() at time zone 'America/Argentina/Buenos_Aires'), 'YYYYMMDD');
  v_min   int;
  v_msg   text;
  v_avisos int := 0;
  v_detalle text := '';
begin
  for r in
    select j.jobid, j.jobname, j.active,
           (select max(d.end_time) from cron.job_run_details d
             where d.jobid = j.jobid and d.status = 'succeeded') as ultimo_ok,
           u.umbral_min
      from cron.job j
      join (values (25, 30), (26, 60), (27, 120)) as u(jobid, umbral_min)
        on u.jobid = j.jobid
  loop
    if r.ultimo_ok is null then
      v_min := 999999;
    else
      v_min := floor(extract(epoch from (now() - r.ultimo_ok)) / 60)::int;
    end if;

    v_detalle := v_detalle || r.jobname || '=' || v_min || 'min ';

    if (not r.active) or v_min > r.umbral_min then
      v_avisos := v_avisos + 1;
      v_msg := '🚨 SYNC CAIDO — ' || r.jobname || E'\n' ||
               case when not r.active
                    then 'El cron esta DESACTIVADO.'
                    else 'Hace ' || v_min || ' min que no corre bien (umbral ' || r.umbral_min || ' min).' end || E'\n' ||
               'El dato que espeja esta tabla quedo viejo. Revisar cron.job_run_details del job ' || r.jobid || '.';
      begin
        perform public.tg_enqueue(v_msg, 'syncwd_' || r.jobid || '_' || v_dia, null, null);
        perform public.tg_outbox_flush();
      exception when others then null;   -- el aviso no debe romper el watchdog
      end;
    end if;
  end loop;

  return 'watchdog ok · avisos=' || v_avisos || ' · ' || btrim(v_detalle);
end;
$$;

revoke execute on function public.watchdog_syncs_externos() from public, anon, authenticated;

-- select cron.schedule('watchdog-syncs-externos', '23 * * * *', 'select public.watchdog_syncs_externos();');
-- rollback: select cron.unschedule('watchdog-syncs-externos');
--           drop function if exists public.watchdog_syncs_externos();
