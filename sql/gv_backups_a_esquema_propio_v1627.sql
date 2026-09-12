-- ============================================================================
-- v16.27 (2026-09-12) — las 133 tablas de BACKUP salen de `public`
--
-- Thomas: "Si los backups no tienen uso ninguno para ningun repo, dale".
-- La condición era la verificación, así que se hizo entera ANTES de tocar nada.
--
-- EL TAMAÑO DEL PROBLEMA: `public` tenía 388 tablas y 133 eran backups. Un tercio.
-- 121.521 filas, 14 MB. Y no lo hizo nadie en particular: lo hizo el PROTOCOLO, que
-- decía crear cada backup en `public`. Por eso, además de mover las que había, se
-- cambió el CLAUDE.md para que las próximas nazcan en `zz_backups`.
--
-- VERIFICACIÓN (las dos mitades dieron cero)
--
--   En la base — ninguna de las 133 tiene:
--     · vista o matview que la lea ............ 0
--     · función que la nombre ................. 0   (todas las funciones, todos los esquemas)
--     · cron que la use ....................... 0
--     · foreign key (ni hacia ni desde) ....... 0
--     · trigger propio ........................ 0
--
--   En el código — 0 de 133 aparecen en NINGÚN repo que pegue contra este proyecto:
--     · loekemeyer/gestion-virgilio ..... 583 archivos  (incluye las copias de
--                                          admin LK, GP2 y los dos de Cervantes)
--     · loekemeyer/produccion-virgilio .. 157 archivos
--     · loekemeyer/planify ..............  40 archivos
--     Buscado por nombre exacto en .js .html .ts .tsx .py .cjs .mjs .json .yml .gs.
--     Se excluyeron .md y .sql a propósito: ahí sólo se documentan, no se usan.
--     (pagina-LK-copia y paginach no entran: pegan contra OTROS proyectos Supabase,
--      no pueden leer una tabla de éste.)
--
-- POR QUÉ SE MUEVEN Y NO SE DROPEAN. El objetivo era sacar el desorden de `public`,
-- y mover lo consigue igual: 388 → 256. Pero un `alter ... set schema` se deshace con
-- otro `alter`, y un `drop` de 121.521 filas no se deshace con nada. Ante dos caminos
-- que dan el mismo resultado, el reversible. Cuando Thomas quiera el borrado
-- definitivo: `drop schema zz_backups cascade;`
--
-- MEDIDO DESPUÉS: 0 vistas rotas · 0 endpoints rotos · los 5 centinelas en cero ·
-- facturación $1.395.224.815,83 igual · vista_saldos_stock 488 · vista_stock_procesada
-- 363 · Registros_Produccion_Virgilio 30.936. Nada se movió.
-- ============================================================================

create schema if not exists zz_backups;
-- el esquema nace cerrado: una tabla creada acá ya no queda abierta a anon aunque
-- uno se olvide del revoke (que es lo que venía pasando en public)
revoke all on schema zz_backups from anon, authenticated;
comment on schema zz_backups is
  'Tablas de BACKUP sacadas de public el 12/09/2026. Nadie las usa: 0 vistas, 0 funciones, 0 crons, 0 FK, 0 triggers, y 0 apariciones en el codigo de gestion-virgilio, produccion-virgilio y planify (780 archivos). Se movieron en vez de dropearlas para que sea reversible: alter table zz_backups.X set schema public. Para borrarlas de verdad: drop schema zz_backups cascade;';

-- índice de lo que había, para no perder el rastro de qué existió y con cuántas filas
drop table if exists public."GV_Backups_Indice";
create table public."GV_Backups_Indice" as
select c.relname tabla,
       (select n_live_tup from pg_stat_user_tables s where s.relid=c.oid) filas,
       pg_size_pretty(pg_total_relation_size(c.oid)) peso,
       'zz_backups'::text esquema_ahora,
       now() movida_el
from pg_class c join pg_namespace n on n.oid=c.relnamespace
where n.nspname='public' and c.relkind='r' and c.relname ~* '(bkp|backup|_bak|^zzz|^_bkp)'
  and c.relname <> 'GV_Backups_Indice';
alter table public."GV_Backups_Indice" enable row level security;
revoke insert, update, delete, truncate on public."GV_Backups_Indice" from anon, authenticated;

do $$
declare r record; n int := 0;
begin
  for r in select c.relname from pg_class c join pg_namespace ns on ns.oid=c.relnamespace
            where ns.nspname='public' and c.relkind='r'
              and c.relname ~* '(bkp|backup|_bak|^zzz|^_bkp)'
              and c.relname <> 'GV_Backups_Indice'
  loop
    execute format('alter table public.%I set schema zz_backups', r.relname);
    n := n + 1;
  end loop;
  raise notice 'movidas %', n;   -- 133
end $$;

-- ── verificación ──
-- select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace
--  where n.nspname='public' and c.relkind='r';        -- 256 (eran 388)
-- select * from public.gv_endpoints_rotos;            -- 0 filas
-- select * from public."GV_Backups_Indice";           -- las 133, con filas y peso

-- ── ROLLBACK ──
-- una sola:   alter table zz_backups."X" set schema public;
-- todas:      do $$ declare r record; begin
--               for r in select relname from pg_class c join pg_namespace n on n.oid=c.relnamespace
--                         where n.nspname='zz_backups' and c.relkind='r'
--               loop execute format('alter table zz_backups.%I set schema public', r.relname); end loop;
--             end $$;
