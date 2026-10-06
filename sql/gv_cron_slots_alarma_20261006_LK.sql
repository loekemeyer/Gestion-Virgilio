-- ============================================================================
-- ALARMA DE WORKER SLOTS  ·  LK (kwkclwhmoygunqmlegrg)  ·  2026-10-06 (Thomas)
-- ----------------------------------------------------------------------------
-- QUÉ: avisar POR TELEGRAM, en vivo, cuando la base de LK se está quedando sin
--      worker slots (los 6 de `max_worker_processes`), ANTES de que el armado
--      automático de Gestión muera 2 h como el 06/10.
--
-- POR QUÉ: el 06/10 LK se saturó 10:40-12:40 UTC; el armado intradía (lee el
--      feed de LK por `gv_pedidos_web_np_lk`) abortó con HTTP 504 de 07:49 a
--      09:42 ART, todos los ticks. La señal server-side fue 696 `job startup
--      timeout` en cron.job_run_details (pg_cron no podía arrancar workers).
--      `gv_cron_colisiones` es un MAPA que hay que mirar; esto es la ALARMA que
--      avisa sola, misma filosofía que los demás centinelas.
--
-- SEÑAL: 3+ jobs que fallan con `job startup timeout` o `canceling statement due
--      to statement timeout` en los últimos 6 min → un Telegram al grupo de
--      infra, dedup por HORA (no spamea durante un episodio largo).
--
-- CÓMO: va INLINE en el command del cron (do-block), igual que el anti-solape de
--      los pesados (39/48/63/66/41). No crea función: así se despliega por
--      `select cron.schedule(...)` sin tocar DDL de primer nivel (que cuelga el MCP).
--
-- LÍMITE: en una saturación TOTAL la propia alarma podría no conseguir worker.
--      Dispara en la cara inicial del episodio (primeros timeouts) y cuando la
--      base respira entre picos. La caída TOTAL ya la cubre, desde el otro lado,
--      `gv-watch-gestion` (cron 63 de LK que pinga Gestión).
--
-- GV: falta el espejo en Gestión (hrxfctzncixxqmpfhskv) — mismo do-block con la
--      tg_enqueue y el chat de GV. GV tuvo 0 choques en 3 días, por eso va después.
-- ============================================================================

select cron.schedule('gv-cron-slots-alarma', '1-59/5 * * * *', $cmd$
do $g$
declare v_n int; v_jobs text; v_chat text := '-1004379879565';
begin
  if not pg_try_advisory_xact_lock(hashtext('cron:gv_cron_slots_alarma')::bigint) then return; end if;
  select count(*), string_agg(distinct jobid::text, ',')
    into v_n, v_jobs
    from cron.job_run_details
   where start_time >= now() - interval '6 minutes' and status = 'failed'
     and (return_message ilike '%job startup timeout%'
          or return_message ilike '%statement due to statement timeout%');
  if coalesce(v_n,0) >= 3 then
    perform public.tg_enqueue(
      '🟠 LK se está quedando sin worker slots: ' || v_n ||
      ' jobs no arrancaron en los últimos 6 min (' ||
      to_char(now() at time zone 'America/Argentina/Buenos_Aires','HH24:MI') ||
      ' ART). El armado automático puede estar abortando. Jobs: ' || coalesce(v_jobs,'-') ||
      '. Mirá cron.job_run_details y pg_stat_activity.',
      'lk-slots-' || to_char(now() at time zone 'America/Argentina/Buenos_Aires','YYYYMMDDHH24'),
      v_chat);
  end if;
end $g$;
$cmd$);

-- ROLLBACK (una línea):
--   select cron.unschedule('gv-cron-slots-alarma');

-- CHEQUEO:
--   select jobid, jobname, schedule, active from cron.job where jobname='gv-cron-slots-alarma';
--   -- lo que evaluaría ahora (0 = sin choques):
--   select count(*) from cron.job_run_details
--    where start_time >= now() - interval '6 minutes' and status='failed'
--      and (return_message ilike '%job startup timeout%'
--           or return_message ilike '%statement due to statement timeout%');
