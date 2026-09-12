-- gv_deadlock_cron57_cron68_PENDIENTE.sql — arreglo del deadlock diario entre el cron 57
-- (refresh_stocks_carga_rapida) y el cron 68 (reconciliar_pipeline_stock).
--
-- ⚠ NO APLICADO TODAVÍA. Escrito el 2026-09-12 con el canal SQL del MCP caído.
--    Antes de correrlo hay que hacer los pasos 0 y 1, que son de MEDICIÓN.
--
-- Diagnóstico completo en docs/HALLAZGOS-LOGS-20260912.md.
-- Resumen: las dos funciones tocan las mismas filas de stock en ORDEN DISTINTO. Cuando sus
-- horarios coinciden se traban y Postgres mata siempre a la misma, refresh_stocks_carga_rapida().
-- 11 veces el 12/09. Cada vez, el cache de carga rápida no se refresca y Stock sirve un número
-- viejo, sin que nadie se entere: el cron no avisa.
--
--   Process A: SELECT public.refresh_stocks_carga_rapida()   <- cron 57, la víctima
--   Process B: select public.reconciliar_pipeline_stock();   <- cron 68
--
-- Estrategia elegida: **candado de aplicación sobre el COMANDO DEL CRON**, no sobre las
-- funciones. Serializa las dos corridas sin tocar una sola línea de lógica, y se deshace
-- volviendo a poner el command original. Las funciones son objetos compartidos con Producción
-- (hoy retirada) y este camino evita tener que anotarlas en docs/ROLLBACK-PRODUCCION.md.
--
-- pg_cron manda el `command` como una sola simple-query, así que los dos statements corren
-- en la MISMA transacción implícita: el pg_advisory_xact_lock se toma antes y se suelta al
-- commit. Si una está corriendo, la otra espera en vez de trabarse.
--
-- ⚠ UNA QUERY POR LLAMADA. No pegar el archivo entero de una.

-- ── 0) MEDIR ANTES (guardar el número, es el antes/después) ──────────────────────────────
-- Deadlocks en las últimas 24 h. El 12/09 a las 17:20 ART daba 11.
--   (se mide con query_logs, no con SQL: source='postgres_logs' and event_message='deadlock detected')

-- ── 1) MIRAR LO QUE HAY, sin tocar nada ──────────────────────────────────────────────────
select jobid, schedule, command, active
  from cron.job where jobid in (55, 57, 68) order by jobid;

-- ¿Cuánto tarda cada una y con qué frecuencia falla? (pg_cron guarda el detalle)
select jobid, status, count(*) n,
       round(avg(extract(epoch from (end_time - start_time)))::numeric, 1) seg_prom,
       round(max(extract(epoch from (end_time - start_time)))::numeric, 1) seg_max
  from cron.job_run_details
 where jobid in (57, 68) and start_time > now() - interval '24 hours'
 group by jobid, status order by jobid, n desc;

-- ¿La víctima se llama desde otro lado además del cron? Si sí, el candado del cron protege
-- cron-vs-cron nada más, y habría que subirlo a la función.
select p.oid::regprocedure as fn
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname not in ('pg_catalog','information_schema')
   and p.prosrc ilike '%refresh_stocks_carga_rapida%';

-- ── 2) BACKUP del command actual (para el rollback exacto) ───────────────────────────────
create table if not exists zz_backups."GV_Backup_cron_job_20260912" as
  select jobid, schedule, command, active, now() as guardado_en
    from cron.job where jobid in (55, 57, 68);
alter table zz_backups."GV_Backup_cron_job_20260912" enable row level security;
revoke insert, update, delete, truncate on zz_backups."GV_Backup_cron_job_20260912"
  from anon, authenticated;

-- ── 3) EL FIX: mismo candado en las dos, así no pueden interleavearse ────────────────────
-- La clave (5768) es arbitraria pero tiene que ser LA MISMA en las dos.
select cron.alter_job(57, command :=
  $c$select pg_advisory_xact_lock(5768); select public.refresh_stocks_carga_rapida();$c$);

select cron.alter_job(68, command :=
  $c$select pg_advisory_xact_lock(5768); select public.reconciliar_pipeline_stock();$c$);

-- ── 4) VERIFICAR ─────────────────────────────────────────────────────────────────────────
select jobid, schedule, command from cron.job where jobid in (57, 68) order by jobid;

-- Y a las 24 h volver a contar deadlocks en los logs. Objetivo: 0.
-- Además, que el cron 57 deje de tener corridas en 'failed':
select jobid, status, count(*) from cron.job_run_details
 where jobid in (57, 68) and start_time > now() - interval '24 hours'
 group by jobid, status order by jobid;

-- ── ROLLBACK ─────────────────────────────────────────────────────────────────────────────
-- Volver a poner el command tal cual estaba, desde el backup:
--   select cron.alter_job(57, command := (select command from
--     zz_backups."GV_Backup_cron_job_20260912" where jobid = 57));
--   select cron.alter_job(68, command := (select command from
--     zz_backups."GV_Backup_cron_job_20260912" where jobid = 68));

-- ── SI EL CANDADO NO ALCANZA ─────────────────────────────────────────────────────────────
-- (o sea: si el paso 1 muestra que refresh_stocks_carga_rapida se llama desde un trigger o
--  desde la app, no sólo desde el cron)
-- Entonces el candado tiene que ir ADENTRO de las dos funciones, como primera línea:
--   perform pg_advisory_xact_lock(5768);
-- Eso sí toca objetos compartidos → va anotado en docs/ROLLBACK-PRODUCCION.md con el
-- prosrc viejo completo, y el backup del prosrc va antes:
--   create table zz_backups."GV_Backup_prosrc_stock_20260912" as
--     select oid::regprocedure::text fn, prosrc from pg_proc
--      where proname in ('refresh_stocks_carga_rapida','reconciliar_pipeline_stock');
