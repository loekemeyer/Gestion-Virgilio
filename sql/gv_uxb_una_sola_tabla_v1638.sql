-- gv_uxb_una_sola_tabla_v1638.sql — APLICADO 2026-09-12.
--
-- Pedido del dueño, textual: *"yo para las unidades por caja creo que solamente miren a una
-- tabla Supabase, no es tan complejo"*.
--
-- Tenía razón y yo me había quedado corto. En la v16.36 saqué `precios_venta.uxb` y el shim
-- `gv_uxb_lk` de las cadenas, pero **dejé dos eslabones por delante de `GV_UxB`** argumentando
-- que eran "el UxB pactado por cliente y por súper". Mirando los datos, esa defensa no se
-- sostiene:
--
--   · `pcl` = `GV_Precios_Cliente` → la tabla tiene **4 filas**, de UN cliente (2533), y **una
--     sola tiene `uxb` cargado**: el código 198E con **12**… que es exactamente lo que dice
--     `GV_UxB`. O sea que ese eslabón nunca aportó un valor distinto.
--   · `ps` = `cobranzas_precios_super` → sus dos ramas ya van a `GV_UxB`: `u` vía `gv_uxb_lk`, y
--     `pv` vía `cobranzas_precios`, que se repuntó en la v16.36.
--
-- ── LO QUE SE TOCÓ ───────────────────────────────────────────────────────────────────────
--
-- | vista | antes (v16.36) | ahora |
-- |---|---|---|
-- | `vista_facturacion_neto_items` | `COALESCE(ps.uxb, pcl.uxb, uxe.uxb)` | `uxe.uxb` |
-- | `vista_facturable_anticipado` | `COALESCE(pcl.uxb, uxe.uxb)` / `(…, 1)` | `uxe.uxb` / `COALESCE(uxe.uxb, 1)` |
-- | `vista_plata_perdida` ×2 | `COALESCE(pcl.uxb, uxe.uxb, 1)` | `COALESCE(uxe.uxb, 1)` |
--
-- `uxe` es `gv_uxb_emp`, que es una vista sobre `GV_UxB`. **Ya no queda ninguna otra fuente.**
--
-- ── MEDICIÓN ─────────────────────────────────────────────────────────────────────────────
--   vista_facturacion_neto_items : 10.604 líneas · 0 sin uxb · $1.395.224.315,83 —
--     y **0 filas de diferencia** comparando fila a fila contra la versión anterior.
--   vista_facturable_anticipado  : 724 filas · $77.843.819,56
--   vista_plata_perdida          : 902 filas
--
-- ── CHEQUEO DE QUE NO QUEDÓ NADA ─────────────────────────────────────────────────────────
-- Barrido de todas las vistas de `public` buscando un `uxb` que venga de otra tabla:
--
--   select n.nspname||'.'||c.relname
--     from pg_class c join pg_namespace n on n.oid = c.relnamespace
--    where n.nspname = 'public' and c.relkind in ('v','m')
--      and pg_get_viewdef(c.oid, true) ~
--          '(precios_venta\.uxb|precios_venta_chef\.uxb|pv\.uxb|pc\.uxb|pcl\.uxb|ux\.uxb|ps\.uxb)';
--
-- Devuelve sólo `cobranzas_precios_super`, y su `pv` es `cobranzas_precios`, que ya lee
-- `GV_UxB`. **Todo el UxB de Gestión sale hoy de una sola tabla.**
--
-- ── Y DE PASO ────────────────────────────────────────────────────────────────────────────
-- `gv_bkp_facneto_items_v1604` era una vista de BACKUP viviendo en `public`. No la lee nadie
-- (0 vistas, 0 funciones, y 0 apariciones en el front de los 4 repos), así que se mudó a
-- `zz_backups`, que es donde va un backup desde la v16.27:
--
--   alter view public.gv_bkp_facneto_items_v1604 set schema zz_backups;
--
-- Con eso, el `alter table precios_venta drop column uxb` de prueba (en `begin/rollback`) pasó
-- de ser rechazado por **6 vistas / 16 objetos** (antes de la v16.36) a **2**, y ninguna es de
-- producción: la vista de backup ya mudada y `gv_uxb_desalineado`, el centinela de drift.
--
-- **La columna NO se dropeó**: es irreversible y no hace falta para el objetivo — ya es
-- inalcanzable desde todo camino vivo. Queda para una pasada propia, con el OK del dueño.

do $$
declare d text; n int;
begin
  d := pg_get_viewdef('public.vista_facturacion_neto_items'::regclass, true);
  if position('COALESCE(ps.uxb, pcl.uxb, uxe.uxb) AS uxb_r' in d) = 0 then raise exception 'sin cadena'; end if;
  execute 'create or replace view public.vista_facturacion_neto_items as '
       || replace(d, 'COALESCE(ps.uxb, pcl.uxb, uxe.uxb) AS uxb_r', 'uxe.uxb AS uxb_r');

  d := pg_get_viewdef('public.vista_facturable_anticipado'::regclass, true);
  n := (length(d) - length(replace(d, 'COALESCE(pcl.uxb, uxe.uxb)', ''))) / 26;
  if n <> 1 then raise exception 'anticipado: aparece % veces', n; end if;
  d := replace(d, 'COALESCE(pcl.uxb, uxe.uxb, 1)', 'COALESCE(uxe.uxb, 1)');
  d := replace(d, 'COALESCE(pcl.uxb, uxe.uxb)', 'uxe.uxb');
  execute 'create or replace view public.vista_facturable_anticipado as ' || d;

  d := pg_get_viewdef('public.vista_plata_perdida'::regclass, true);
  n := (length(d) - length(replace(d, 'COALESCE(pcl.uxb, uxe.uxb, 1)', ''))) / 29;
  if n <> 2 then raise exception 'plata perdida: aparece % veces, esperaba 2', n; end if;
  execute 'create or replace view public.vista_plata_perdida as '
       || replace(d, 'COALESCE(pcl.uxb, uxe.uxb, 1)', 'COALESCE(uxe.uxb, 1)');
end $$;

alter view public.gv_bkp_facneto_items_v1604 set schema zz_backups;

-- ROLLBACK: las definiciones previas están en
--   zz_backups."GV_Backup_viewdefs_uxb_chain_20260912"   (estado ANTES de la v16.36)
-- y la mudanza se deshace con
--   alter view zz_backups.gv_bkp_facneto_items_v1604 set schema public;
