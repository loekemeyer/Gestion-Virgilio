-- v18.40 · 2026-09-15 — Corrección de 7 recepciones cargadas con el código sin la E
-- Autorizado por Thomas el 15/09 ("Está mal recibido todos esos sin la E" → "Sí").
-- Doc: docs/SUPABASE-GESTION-VIRGILIO.md §3.hf · Rollback: docs/ROLLBACK-PRODUCCION.md
-- Problema 264 (cerrado con 6145ca5). Problema 265 (espejo GP2) queda ABIERTO.

-- ── 1) Backup (ya ejecutado; queda acá para el registro) ──────────────────────
create table if not exists zz_backups."GV_Backup_EntregasTall_SinE_20260915" as
select * from public."Entregas Tallerista Virgilio"
where id in (1961,1962,1960,2293,1902,2294,2295);
alter table zz_backups."GV_Backup_EntregasTall_SinE_20260915" enable row level security;
revoke insert, update, delete, truncate
  on zz_backups."GV_Backup_EntregasTall_SinE_20260915" from anon, authenticated;

-- ── 2) La corrección ─────────────────────────────────────────────────────────
-- Por id (la PK real), no por código. Ninguno de los dos triggers de la tabla
-- (trg_recep_pagos_tall, trg_virgilio_espejo_gp2) es AFTER UPDATE, así que no se dispara nada.
update public."Entregas Tallerista Virgilio"
   set "Cod" = "Cod" || 'E'
 where id in (1961,1962,1960,2293,1902,2294,2295)
   and "Cod" in ('582','583','584','599','727','943','948');
-- 582→582E 136cj · 583→583E 24 · 584→584E 10 · 599→599E 16 · 727→727E 7 · 943→943E 3 · 948→948E 16

-- ── 3) Verificación: 0 filas sin E que tengan variante con E ─────────────────
with e as (select distinct regexp_replace(cod,'E$','') b
             from public.vista_stock_procesada where cod ~ '[0-9]E$')
select t."Cod", count(*) filas, sum(t."Cajas") cajas
  from public."Entregas Tallerista Virgilio" t
  join e on e.b = t."Cod"
 where not exists (select 1 from public.vista_stock_procesada s where s.cod = t."Cod")
 group by 1;   -- vacío = todo bien

-- ── 4) ROLLBACK ──────────────────────────────────────────────────────────────
-- update public."Entregas Tallerista Virgilio" t
--    set "Cod" = b."Cod"
--   from zz_backups."GV_Backup_EntregasTall_SinE_20260915" b
--  where t.id = b.id;
