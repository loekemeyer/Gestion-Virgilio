-- ============================================================================
-- v19.62 — El generador de OC IGNORABA los pedidos WEB · problema 405
--
-- Thomas, 2026-09-18, mirando el 321 en la pantalla de Stocks:
--   *"¿Por qué 321 sacó OC de 120 si está así?"* — la pantalla mostraba
--   321 de stock y **198 cajas pedidas**, y la OC del 16/09 salió por 120.
--
-- La cuenta de esa OC cerraba con los datos que TENÍA: 445 + 6 − 331 = 120.
-- El problema es que esos datos estaban mal: contaba **6** cajas pedidas cuando
-- había ~199.
--
-- CAUSA. El CTE `pend_np` miraba SOLO `GV_PPP_Programacion_Diaria`, o sea las NP
-- de ISIS. Las NP web viven en `PPP_Web_Programacion` y se nombran con
-- `gv_ppp_web_np_label(empresa, np, np_idx)` ("LK 0001"), así que ninguna
-- matcheaba contra `gv_demanda_pedidos.pedido` y **su demanda contaba CERO**.
--
-- ⚠ El arreglo ya estaba escrito AL LADO y nadie lo trajo: `vista_stock_procesada`
-- tiene el CTE `pend_np_oc`, que hace el UNION con la web y además saltea
-- `GV_Web_Cancelados`. Esta vista quedó con la versión vieja. Por eso el parche
-- copia ese bloque tal cual en vez de inventar uno nuevo.
--
-- MEDIDO el 18/09, antes de aplicar:
--
--   | | |
--   |---|---|
--   | códigos con demanda web ignorada | **265** |
--   | cajas que el generador no veía   | **4.465** |
--   | códigos que pasan a pedir más    | **92** |
--   | cajas de más a pedir             | **2.651** |
--
--   Caso testigo 321 (Rallador Cilíndrico): pedidos 3 → **196**, a pedir 127 → **320**.
--   Peores: 505 (85→574), 501 (89→325), 506 (630→833), 321 (127→320), 586 (0→188).
--
-- ⚠ El 321 igual queda topeado por la GÓNDOLA, no por la proyección: la
-- proyección pide 366 × 1,5 = 550 y la capacidad es 445, así que `maximo` = 445.
-- Con la web contada da 445 + 196 − 321 = 320.
--
-- SIN DOBLE CONTEO, medido: las 16 NP de `GV_PPP_Prog_Override` marcadas `oculto`
-- (los espejos de ISIS que duplican un pedido web) aportan **0 cajas** de demanda,
-- así que el UNION no suma nada dos veces.
--
-- ⚠ `vista_generador_oc` la lee TAMBIÉN el front de Producción Virgilio
-- (`index.html` y `sw.js`) → la nota de rollback va en `docs/ROLLBACK-PRODUCCION.md`.
--
-- CÓMO SE APLICÓ: reemplazo de texto sobre `pg_get_viewdef` de la definición
-- **viva** (nunca sobre una copia del repo — varias sesiones tocan los mismos
-- objetos), con dos guards: que el ancla exista y que aparezca UNA sola vez.
-- Respaldo de la definición previa + sus opciones en
-- `zz_backups."GV_Backup_Def_GeneradorOC_20260918"`.
--
-- ⚠⚠ `CREATE OR REPLACE VIEW` **borra las `reloptions`**: el
-- `alter view ... set (security_invoker = true)` NO es opcional, va siempre.
-- ============================================================================

-- ── El parche idempotente, tal cual se aplicó ───────────────────────────────
do $do$
declare
  v_def text;
  v_viejo text := E'                   FROM pickeadas))\n        ), dem_raw AS (';
  v_nuevo text := E'                   FROM pickeadas))\n        UNION\n         SELECT DISTINCT gv_ppp_web_np_label(w.empresa, w.np, w.np_idx) AS np\n           FROM "PPP_Web_Programacion" w\n          WHERE NOT (gv_ppp_web_np_label(w.empresa, w.np, w.np_idx) IN ( SELECT btrim("Facturacion_NP".np) AS btrim\n                   FROM "Facturacion_NP")) AND NOT (upper(btrim(COALESCE(w.tanda, \'\'::text))) IN ( SELECT pickeadas.tanda\n                   FROM pickeadas)) AND NOT (EXISTS ( SELECT 1\n                   FROM "GV_Web_Cancelados" wc\n                  WHERE wc.np_label = gv_ppp_web_np_label(w.empresa, w.np, w.np_idx)))\n        ), dem_raw AS (';
begin
  v_def := pg_get_viewdef('public.vista_generador_oc'::regclass, true);
  if position(v_viejo in v_def) = 0 then
    raise exception 'el ancla del reemplazo NO esta en la definicion viva (ya aplicado, o la vista cambio)';
  end if;
  if (length(v_def) - length(replace(v_def, v_viejo, ''))) / length(v_viejo) <> 1 then
    raise exception 'el ancla aparece mas de una vez: reemplazo ambiguo';
  end if;
  execute 'create or replace view public.vista_generador_oc as ' || replace(v_def, v_viejo, v_nuevo);
  execute 'alter view public.vista_generador_oc set (security_invoker = true)';
end $do$;

comment on view public.vista_generador_oc is
  'v19.62 - A pedir = max(0, ceil(Maximo + Pedidos - Stock)). Pedidos = NP no facturadas cuya tanda no tiene TP, de ISIS (GV_PPP_Programacion_Diaria) Y de la WEB (PPP_Web_Programacion, salteando GV_Web_Cancelados). Hasta la v19.61 miraba solo ISIS y se comia 4.465 cajas de demanda web.';

-- ============================================================================
-- EL BLOQUE QUE CAMBIÓ, para poder leerlo sin ejecutar nada
-- ============================================================================
-- ANTES:
--   pend_np AS (
--            SELECT DISTINCT btrim(p.np) AS np
--              FROM "GV_PPP_Programacion_Diaria" p
--             WHERE NOT (btrim(p.np) IN (SELECT btrim(np) FROM "Facturacion_NP"))
--               AND NOT (upper(btrim(COALESCE(p.tanda, ''))) IN (SELECT tanda FROM pickeadas))
--   )
--
-- DESPUÉS: lo mismo, más
--   UNION
--            SELECT DISTINCT gv_ppp_web_np_label(w.empresa, w.np, w.np_idx) AS np
--              FROM "PPP_Web_Programacion" w
--             WHERE NOT (gv_ppp_web_np_label(...) IN (SELECT btrim(np) FROM "Facturacion_NP"))
--               AND NOT (upper(btrim(COALESCE(w.tanda, ''))) IN (SELECT tanda FROM pickeadas))
--               AND NOT EXISTS (SELECT 1 FROM "GV_Web_Cancelados" wc
--                                WHERE wc.np_label = gv_ppp_web_np_label(...))
--
-- El resto de la vista NO se tocó. La definición completa resultante queda
-- reconstruible con: select pg_get_viewdef('public.vista_generador_oc'::regclass, true);
--
-- ============================================================================
-- VERIFICACIÓN
-- ============================================================================
-- 1) el caso testigo
-- select codn, stock, proy, cap, maximo, pedidos, total
--   from public.vista_generador_oc where codn = '321';
--   -> pedidos 196 (era 3), total 320 (era 127), maximo 445 = la capacidad de gondola
--
-- 2) que la opcion no se perdio (si esto no da security_invoker, la vista saltea la RLS)
-- select relname, reloptions from pg_class where oid = 'public.vista_generador_oc'::regclass;
--
-- 3) el centinela de dependientes
-- select * from public.gv_endpoints_rotos;   -- vacio
--
-- 4) que la demanda web ya no queda afuera (tiene que dar 0)
-- with pickeadas as (select distinct upper(btrim(texto)) tanda
--        from public."Registros_Produccion_Virgilio" where opcion='TP'),
-- np as (select distinct public.gv_ppp_web_np_label(w.empresa, w.np, w.np_idx) np
--          from public."PPP_Web_Programacion" w
--         where not (upper(btrim(coalesce(w.tanda,''))) in (select tanda from pickeadas)))
-- select count(*) from public.gv_demanda_pedidos b join np on np.np = btrim(b.pedido)
--  where not exists (select 1 from public.vista_generador_oc v
--                     where v.codn = public.norm_cod(b.articulo) and v.pedidos > 0);
--
-- ============================================================================
-- ROLLBACK  (vuelve a pedir SIN contar la web, o sea 2.651 cajas menos)
-- ============================================================================
-- do $$
-- declare v_def text;
--   v_nuevo text := E'                   FROM pickeadas))\n        ), dem_raw AS (';
--   v_viejo text := E'                   FROM pickeadas))\n        UNION\n         SELECT DISTINCT gv_ppp_web_np_label(w.empresa, w.np, w.np_idx) AS np\n           FROM "PPP_Web_Programacion" w\n          WHERE NOT (gv_ppp_web_np_label(w.empresa, w.np, w.np_idx) IN ( SELECT btrim("Facturacion_NP".np) AS btrim\n                   FROM "Facturacion_NP")) AND NOT (upper(btrim(COALESCE(w.tanda, ''''::text))) IN ( SELECT pickeadas.tanda\n                   FROM pickeadas)) AND NOT (EXISTS ( SELECT 1\n                   FROM "GV_Web_Cancelados" wc\n                  WHERE wc.np_label = gv_ppp_web_np_label(w.empresa, w.np, w.np_idx)))\n        ), dem_raw AS (';
-- begin
--   v_def := pg_get_viewdef('public.vista_generador_oc'::regclass, true);
--   execute 'create or replace view public.vista_generador_oc as ' || replace(v_def, v_viejo, v_nuevo);
--   execute 'alter view public.vista_generador_oc set (security_invoker = true)';
-- end $$;
--
-- o, directo desde el respaldo:
-- do $$ declare d text; begin
--   select definicion into d from zz_backups."GV_Backup_Def_GeneradorOC_20260918";
--   execute 'create or replace view public.vista_generador_oc as ' || d;
--   execute 'alter view public.vista_generador_oc set (security_invoker = true)';
-- end $$;
