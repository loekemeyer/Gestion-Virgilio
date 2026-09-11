-- BACKUP 2026-09-11, ANTES de la v15.76 (sql/gv_precio_chef_v1576.sql).
-- Definiciones EXACTAS que estaban desplegadas (pg_get_viewdef) de las tres vistas que
-- valorizaban TODO —también las NP de Chef— con la lista de LK (public.precios_venta).
-- ROLLBACK = correr este archivo tal cual.
-- Snapshot de datos del "antes" de vista_facturacion_neto_items (10.588 filas):
--   public.gv_bkp_facneto_items_20260911

-- ── 1) vista_facturacion_neto_items ───────────────────────────────────────
CREATE OR REPLACE VIEW public.vista_facturacion_neto_items AS
WITH ent AS (
  SELECT regexp_replace(e.np, '\.0+$', '')            AS np,
         public.canon_cod(e.cod_art)                  AS cod_canon,
         min(e.cod_art)                               AS cod_orig,
         regexp_replace(e.cod_cliente, '\D', '', 'g') AS cc,
         SUM(COALESCE(e.cajas_entregadas,0))          AS cajas_ent,
         SUM(COALESCE(e.cajas_pedidas,0))             AS cajas_ped,
         SUM(COALESCE(e.cajas_falto,0))               AS cajas_falto
  FROM public."Entregas_Virgilio" e
  WHERE COALESCE(e.cajas_pedidas,0) > 0 OR COALESCE(e.cajas_entregadas,0) > 0 OR COALESCE(e.cajas_falto,0) > 0
  GROUP BY regexp_replace(e.np, '\.0+$', ''),
           public.canon_cod(e.cod_art),
           regexp_replace(e.cod_cliente, '\D', '', 'g')
),
base AS (
  SELECT ent.*,
    (CASE WHEN ent.np ~ '^9' THEN 'lk' ELSE 'chef' END) AS empresa,
    (SELECT cc2.super_key
       FROM public.cobranzas_cliente_cadena cc2
       JOIN public.cobranzas_super_cadena sc ON sc.super_key = cc2.super_key AND NOT sc.usa_lista_general
      WHERE cc2.empresa = (CASE WHEN ent.np ~ '^9' THEN 'lk' ELSE 'ch' END)
        AND cc2.cod_cliente = ent.cc
      LIMIT 1) AS super_key
  FROM ent
)
SELECT b.np,
       b.cc AS cod_cliente,
       COALESCE(pv.cod, b.cod_orig) AS cod,
       b.cajas_ped, b.cajas_ent, b.cajas_falto,
       COALESCE(ps.uxb, pv.uxb) AS uxb,
       COALESCE(ps.precio_unit, pv.precio_unit) AS precio_lista,
       CASE WHEN b.super_key IS NOT NULL THEN 0 ELSE COALESCE(cd.dto_vol, 0) END AS dto_vol,
       CASE WHEN COALESCE(ps.precio_unit, pv.precio_unit) IS NOT NULL AND COALESCE(ps.precio_unit, pv.precio_unit) > 0
            THEN ROUND(b.cajas_ent * COALESCE(ps.uxb, pv.uxb, 1) * COALESCE(ps.precio_unit, pv.precio_unit)
                       * (1 - CASE WHEN b.super_key IS NOT NULL THEN 0 ELSE COALESCE(cd.dto_vol,0) END), 2) END AS importe_ent,
       CASE WHEN COALESCE(ps.precio_unit, pv.precio_unit) IS NOT NULL AND COALESCE(ps.precio_unit, pv.precio_unit) > 0
            THEN ROUND(b.cajas_ped * COALESCE(ps.uxb, pv.uxb, 1) * COALESCE(ps.precio_unit, pv.precio_unit)
                       * (1 - CASE WHEN b.super_key IS NOT NULL THEN 0 ELSE COALESCE(cd.dto_vol,0) END), 2) END AS importe_ped,
       (COALESCE(ps.precio_unit, pv.precio_unit) IS NULL OR COALESCE(ps.precio_unit, pv.precio_unit) <= 0) AS sin_precio,
       b.cod_canon,
       CASE WHEN b.super_key IS NOT NULL THEN 1.0 ELSE 0.98 END AS factor_web,
       (b.super_key IS NOT NULL) AS es_super
FROM base b
LEFT JOIN public.clientes_dto  cd
       ON cd.cod_cliente = b.cc AND cd.empresa = b.empresa
LEFT JOIN public.precios_venta pv ON public.canon_cod(pv.cod) = b.cod_canon
LEFT JOIN public.cobranzas_precios_super ps
       ON b.super_key IS NOT NULL AND ps.super_key = b.super_key
      AND ps.nc = public.cob_norm_cod(b.cod_orig);
REVOKE ALL ON public.vista_facturacion_neto_items FROM anon, authenticated;

-- ── 2) vista_facturable_anticipado — sólo cambia el CTE `precio` ──────────
-- (el resto de la vista es idéntico; ver sql/facturable_anticipado.sql v12.31,
--  que es la definición completa previa a este cambio)
-- precio as (
--   select c.*, pv.uxb, pv.precio_unit,
--          coalesce(cd.dto_vol, 0) as dto_vol,
--          round(c.cajas_cubribles * coalesce(pv.uxb, 1) * coalesce(pv.precio_unit, 0)
--                * (1 - coalesce(cd.dto_vol, 0)) * 0.98, 2) as valor_estimado,
--          (pv.precio_unit is null or pv.precio_unit <= 0) as sin_precio
--   from calc c
--   left join public.precios_venta pv on public.canon_cod(pv.cod) = public.canon_cod(c.articulo)
--   left join public.clientes_dto cd on cd.cod_cliente = c.cod_cliente and cd.empresa = c.empresa
-- )

-- ── 3) vista_plata_perdida ────────────────────────────────────────────────
CREATE OR REPLACE VIEW public.vista_plata_perdida AS
 SELECT e.np,
    public.norm_cod(e.cod_art) AS cod,
    btrim(e.cod_art) AS cod_raw,
    e.cajas_falto AS cajas,
    e.cajas_pedidas AS ped,
    e.cajas_entregadas AS ent,
    left(e.fecha_salida, 10) AS fecha,
    btrim(e.cod_cliente) AS cod_cliente,
    COALESCE(pv.precio_unit, 0) AS precio_unit,
    COALESCE(pv.uxb, 1) AS uxb,
    COALESCE(pv.descripcion, '') AS descripcion,
    COALESCE(pv.precio_unit, 0) > 0 AND COALESCE(pv.precio_unit, 0) <> 8888 AS precio_ok,
    CASE WHEN COALESCE(pv.precio_unit, 0) > 0 AND COALESCE(pv.precio_unit, 0) <> 8888
         THEN COALESCE(e.cajas_falto, 0) * COALESCE(pv.uxb, 1) * COALESCE(pv.precio_unit, 0)
         ELSE 0 END AS plata,
    COALESCE(btrim(cv.vend), '') AS vendedor,
    COALESCE(fnp.razon_social, '') AS razon_social
   FROM public."Entregas_Virgilio" e
     LEFT JOIN public.precios_venta pv ON public.norm_cod(pv.cod) = public.norm_cod(e.cod_art)
     LEFT JOIN public.clientes_vendedor cv ON btrim(cv.cod_cliente) = btrim(e.cod_cliente)
     LEFT JOIN public."Facturacion_NP" fnp ON btrim(fnp.np) = btrim(e.np)
  WHERE COALESCE(e.cajas_falto, 0) > 0;
GRANT SELECT ON public.vista_plata_perdida TO anon, authenticated;
