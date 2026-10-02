-- v26.28 (Luis, 02/10/2026, D4 «sí»): borra lo que quedó en la base del programa de impresión de la v26.12.
-- El front ya no lo usa desde la v26.26 (queda sólo el helper local, 127.0.0.1).
-- Medido el 02/10: GV_Impresion_PC 0 filas · _Regla 0 · _Trabajo 0 · _Clave 1 · 0 crons · 0 vistas · 0 centinelas;
-- lo único que nombra estas tablas son estas mismas 9 funciones.
-- ⚠ Desde la sesión de Claude NO entró: execute_sql y apply_migration se colgaron a los 60 s sin llegar a
-- Postgres. Correr en Supabase → SQL Editor (proyecto hrxfctzncixxqmpfhskv).
-- Rollback: el CREATE completo está en sql/gv_impresion_programa_v2611.sql; la clave queda en zz_backups.

create table if not exists zz_backups."GV_Backup_Impresion_Clave_20261002" as select * from public."GV_Impresion_Clave";
alter table zz_backups."GV_Backup_Impresion_Clave_20261002" enable row level security;
revoke insert, update, delete, truncate on zz_backups."GV_Backup_Impresion_Clave_20261002" from anon, authenticated;

drop function if exists public.gv_imp_trabajo_reintentar(bigint);
drop function if exists public.gv_imp_trabajos(integer);
drop function if exists public.gv_imp_encolar(text,text,text,text,text,text);
drop function if exists public.gv_imp_regla_guardar(text,text,text,boolean,integer);
drop function if exists public.gv_imp_config();
drop function if exists public.gv_imp_agente_resultado(text,text,bigint,boolean,text);
drop function if exists public.gv_imp_agente_tomar(text,text,integer);
drop function if exists public.gv_imp_agente_latido(text,text,jsonb,text,text);
drop function if exists public._gv_imp_clave_ok(text);
drop table if exists public."GV_Impresion_Trabajo", public."GV_Impresion_Regla", public."GV_Impresion_PC", public."GV_Impresion_Clave";

-- verificación: tiene que dar 0 · 0 · 1
select (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public' and p.proname in ('gv_imp_trabajo_reintentar','gv_imp_trabajos','gv_imp_encolar',
           'gv_imp_regla_guardar','gv_imp_config','gv_imp_agente_resultado','gv_imp_agente_tomar','gv_imp_agente_latido','_gv_imp_clave_ok')) funciones,
       (select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace
         where n.nspname = 'public' and c.relkind = 'r' and c.relname like 'GV_Impresion_%') tablas,
       (select count(*) from zz_backups."GV_Backup_Impresion_Clave_20261002") backup;
