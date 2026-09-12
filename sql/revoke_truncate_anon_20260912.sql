-- 2026-09-12 — Le saca TRUNCATE al rol `anon` en TODAS las tablas de `public`.
--
-- POR QUÉ
-- TRUNCATE **no respeta RLS**. Tener la RLS prendida y las policies bien puestas no protege
-- de un truncate. La anon key es PÚBLICA (está escrita en el JS del sitio), así que con ella
-- se podía vaciar casi cualquier tabla del proyecto — Registros_Produccion_Virgilio,
-- PPP_Programacion_Diaria, Empleados, precios_venta, usuarios_permitidos… — y la app se
-- quedaba sin datos en silencio.
--
-- No lo pusimos nosotros: viene de los grants por DEFECTO del esquema public de Supabase.
-- El CLAUDE.md ya identificó el agujero en la v6.43 y lo cerró SÓLO para Movimientos_Stock
-- y OC_Maximos; las otras 323 quedaron. Se detectó al arreglar la fuga de GV_Krikos_OC.
--
-- POR QUÉ ES SEGURO
--   · Ninguna app del repo hace TRUNCATE con la anon key (grep sobre js/html, descartando
--     vendor/ y las copias de admin): 0 apariciones.
--   · Se toca SÓLO TRUNCATE. SELECT / INSERT / UPDATE / DELETE quedan intactos.
--
-- BACKUP (tomado ANTES): public."GV_Backup_Grants_Anon_20260912" — una fila por permiso de
-- escritura de anon, con el `grant` de rollback ya escrito en la columna `rollback_sql`.

do $$
declare r record; n int := 0;
begin
  for r in
    select c.relname
      from pg_class c
      join pg_namespace ns on ns.oid = c.relnamespace and ns.nspname = 'public'
     where c.relkind = 'r'
       and has_table_privilege('anon', c.oid, 'TRUNCATE')
  loop
    execute format('revoke truncate on public.%I from anon', r.relname);
    n := n + 1;
  end loop;
  raise notice 'TRUNCATE revocado a anon en % tablas', n;
end $$;

-- Y que las tablas NUEVAS no vuelvan a nacer con TRUNCATE para anon: sin esto, el próximo
-- `create table` en public repite el agujero — que es exactamente como nació GV_Krikos_OC.
alter default privileges in schema public revoke truncate on tables from anon;

-- ---------------------------------------------------------------------------
-- MEDICIÓN (probado corriendo COMO anon, no deducido de los grants)
-- ---------------------------------------------------------------------------
--   anon TRUNCATE en public: 420 → 100, y las 100 que quedan son VISTAS
--     (una vista no se puede truncar: "... is not a table").
--   truncate de una tabla ............................ permission denied ✅
--   truncate de Registros_Produccion_Virgilio ........ permission denied ✅
--   truncate de una de las vistas que quedan ......... "is not a table"  ✅
--   select en PPP_Programacion_Diaria (lo que usa el front) ... sigue leyendo ✅
--
-- ---------------------------------------------------------------------------
-- ROLLBACK
-- ---------------------------------------------------------------------------
-- do $r$ declare s text; begin
--   for s in select rollback_sql from public."GV_Backup_Grants_Anon_20260912"
--             where privilege_type = 'TRUNCATE'
--   loop execute s; end loop;
-- end $r$;
-- alter default privileges in schema public grant truncate on tables to anon;
--
-- ⚠ No debería hacer falta. Si algo dejó de andar, es porque estaba truncando con la anon
-- key — y eso es lo que hay que arreglar, no este revoke.
