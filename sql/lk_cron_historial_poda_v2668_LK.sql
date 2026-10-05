-- =============================================================================
-- v26.68 · PROYECTO LK (kwkclwhmoygunqmlegrg) · D13 de Luis, 05/10/2026: «si, dale, corre d13»
-- Poda del historial de corridas de pg_cron (cron.job_run_details) — YA APLICADO.
-- =============================================================================
-- Por qué: cada corrida de un cron de LK (54 activos) anota una fila y nunca se borraba.
--   Antes: 410.943 filas desde el 28/03, 179 MB = 38 % de la base de LK (471 MB), en la
--   instancia chica que se cayó el 05/10 (0,5 GB de RAM, swap 486 MB, 116 % comprometida).
--   8.059 filas por día.
-- Después (medido): 55.855 filas (desde el 28/09), 18 MB; la base quedó en 311 MB.
--
-- Backup (zz_backups, RLS prendida, sin acceso anon/authenticated):
--   zz_backups."LK_Backup_cron_fallidas_20261005"  6.979 corridas fallidas, completas
--   zz_backups."LK_Backup_cron_resumen_20261005"   1.810 filas: corridas y fallidas por job y día
--
-- Efecto conocido: public.rep_salud, si un cron falla hace MÁS de 7 días, dice
-- «nunca terminó bien» en vez de «falla desde hace N días». Nada más lee esa tabla.
-- =============================================================================

-- 1) backup
create table zz_backups."LK_Backup_cron_fallidas_20261005" as
  select * from cron.job_run_details where runid < 355137 and status <> 'succeeded';
create table zz_backups."LK_Backup_cron_resumen_20261005" as
  select jobid, (start_time at time zone 'America/Argentina/Buenos_Aires')::date dia,
         count(*) corridas, count(*) filter (where status <> 'succeeded') fallidas
    from cron.job_run_details where runid < 355137 group by 1, 2;
alter table zz_backups."LK_Backup_cron_fallidas_20261005" enable row level security;
alter table zz_backups."LK_Backup_cron_resumen_20261005" enable row level security;
revoke all on zz_backups."LK_Backup_cron_fallidas_20261005" from anon, authenticated;
revoke all on zz_backups."LK_Backup_cron_resumen_20261005" from anon, authenticated;

-- 2) borrado en 4 tandas (runid 355137 = primera corrida de los últimos 7 días)
--    with d as (delete from cron.job_run_details where runid < 90000  returning 1) select count(*) from d;  -- 89.999
--    ... < 180000 → 90.000 · < 270000 → 90.000 · < 355137 → 85.137   (total 355.136)

-- 3) poda diaria: 03:27 ART. El minuto 27 de las 06 UTC tiene 3 crons; con éste, 4 (tope 5).
select cron.schedule('lk-podar-historial-cron', '27 6 * * *',
  $$delete from cron.job_run_details where start_time < now() - interval '7 days'$$);   -- jobid 77

-- 4) achicar el archivo
vacuum (full, analyze) cron.job_run_details;

-- Rollback: select cron.unschedule('lk-podar-historial-cron');
--   (lo borrado no vuelve; el resumen y las fallidas están en zz_backups)
