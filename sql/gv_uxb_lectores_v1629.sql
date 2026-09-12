-- ============================================================================
-- v16.29 (2026-09-12) — los lectores directos empiezan a apuntar a GV_UxB.
-- Y al hacerlo aparecen DOS bugs de valuación, los dos por el mismo artículo.
--
-- La v16.28 dejó la FUENTE única. Este tramo repunta los lectores que todavía
-- leían un uni_x_caja/uxb propio sin pasar por los resolvedores.
--
--   vista_generador_oc ........ proyeccion_madre.uxb → GV_UxB   firma IDÉNTICA
--   vista_facturacion_neto_items  pc.uxb fuera del COALESCE     sin cambio
--   vista_plata_perdida ....... idem                            sin cambio
--   cobranzas_precios ......... idem                            sin cambio
--   vista_facturable_anticipado  un SEGUNDO COALESCE → uxe      +$445.548  ⚠
--   gv_ppp_np_valor ........... CASE chef→pc.uxb → GV_UxB       +$6.072.000 ⚠
--
-- LOS DOS QUE SE MOVIERON SON BUGS, Y LOS DOS SON EL 824.
--
-- vista_facturable_anticipado era internamente inconsistente: tenía DOS COALESCE
-- —el de la columna `uxb`, que ya usaba uxe, y otro adentro del round() que calcula
-- `valor_estimado`, que seguía en pc.uxb—. O sea que MOSTRABA un UxB y VALUABA con
-- otro. Tres líneas del 824.
--
-- gv_ppp_np_valor tomaba el UxB de la lista de precios de Chef. 33 NP, todas de Chef,
-- todas suben. El desglose por artículo da UN SOLO código: el 824, en 28 líneas.
-- precios_venta_chef dice 12 y GV_UxB dice 36, que es la corrección de Thomas
-- ("824: 36"). Con la lista vieja esas NP se valuaban a un tercio.
--
-- PRIMERA COLUMNA LIBERADA: proyeccion_madre.uxb → uxb_obsoleto_v1629.
-- No la lee nadie más (el front sólo pide cod,proy_cajas_mes; ninguna función la
-- nombra). Se RENOMBRÓ en vez de dropear porque hay un sync mensual externo
-- (n8n / Apps Script) que no se pudo inspeccionar desde acá: si algo la escribe se
-- ve, sin haber perdido los 410 valores. Backup:
-- zz_backups."GV_proyeccion_madre_uxb_20260912". Si en unos días nada falla, dropear.
--
-- precios_venta_chef.uxb NO se renombró: quedan dos menciones (cobranzas_precios y el
-- propio gv_ppp_np_valor) pero ya como FALLBACK detrás de la fuente única, que es sano.
--
-- MEDIDO AL CIERRE: stock 363 con 0 filas sin uxb · vista_generador_oc 349 ·
-- facturación $1.395.224.315,83 sin moverse · anticipado $77.843.819,56 ·
-- gv_ppp_np_valor $1.395.961.659 · los 4 centinelas en 0.
--
-- BACKUPS: zz_backups."GV_Viewdefs_bkp_20260912e" (5 definiciones previas),
--          zz_backups."GV_Snap_generador_oc_20260912" (las 349 filas de antes),
--          zz_backups."GV_proyeccion_madre_uxb_20260912" (cod + uxb).
-- ============================================================================

-- 1) vista_generador_oc: la división uni/uxb usa GV_UxB. proy_raw deja las patas crudas
--    y la división pasa al CTE `proy`, con un join a `gux` (no se puede correlacionar una
--    subconsulta con la expresión del GROUP BY: Postgres no la reconoce como agrupada).
--      proy_raw: sum(proy_uni_mes) AS uni, max(proy_cajas_mes) AS cajas
--      gux:      select gv_cod_stock(cod) c, max(uxb) u from "GV_UxB" where uxb>0 group by 1
--      proy:     sum(CASE WHEN gx.u > 0 THEN pr.uni / gx.u ELSE pr.cajas END)

-- 2) las 4 vistas de valuación: sacar pc.uxb del COALESCE (uxe ya ganaba antes)
--      'uxe.uxb, pc.uxb'  ->  'uxe.uxb'

-- 3) vista_facturable_anticipado, el segundo COALESCE (el del valor_estimado)
--      'COALESCE(pcl.uxb, pc.uxb, pv.uxb, ux.uxb, 1)'
--   -> 'COALESCE(pcl.uxb, uxe.uxb, pv.uxb, ux.uxb, 1)'

-- 4) gv_ppp_np_valor: el uxb sale de GV_UxB por empresa, la lista queda de fallback
--      CASE WHEN l.empresa_precio='chef' THEN pc.uxb ELSE pv.uxb END
--   -> COALESCE((select max(e.uxb) from gv_uxb_emp e
--                 where e.empresa_precio = l.empresa_precio
--                   and e.cod_canon = canon_cod(l.articulo_precio)),
--               CASE WHEN l.empresa_precio='chef' THEN pc.uxb ELSE pv.uxb END)

-- 5) la columna obsoleta
alter table public.proyeccion_madre rename column uxb to uxb_obsoleto_v1629;
comment on column public.proyeccion_madre.uxb_obsoleto_v1629 is
  'OBSOLETA desde v16.29 (12/09/2026). El UxB sale de GV_UxB. vista_generador_oc ya no la lee. Renombrada en vez de dropeada porque hay un sync mensual externo que no se pudo inspeccionar; si nada falla en unos dias, dropear. Backup: zz_backups."GV_proyeccion_madre_uxb_20260912".';
-- y sale del centinela gv_uxb_desalineado: ya no es fuente, no hay nada que alinear

-- ── verificación ──
-- select count(*) from public.gv_uxb_desalineado;   -- 0
-- select count(*) from public.gv_endpoints_rotos;   -- 0
