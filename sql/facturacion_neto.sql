-- ══════════════════════════════════════════════════════════════════════════
-- Facturación — Neto a facturar + faltantes (cálculo centralizado, EN VIVO)
-- ══════════════════════════════════════════════════════════════════════════
-- Regla del dueño: neto = precio_lista × uxb × cajas × (1 − dto_vol) × (1 − 2%).
--   · dto_vol POR ÍTEM (dto por volumen del cliente, de clientes_dto).
--   · 2% sobre el SUBTOTAL.
--   · Neto "a facturar"  = sobre lo ARMADO (Entregas_Virgilio.cajas_entregadas).
--   · Neto "original"    = sobre el PEDIDO total (cajas_pedidas). La diferencia = faltó $.
-- NO se persiste: es dato derivado, se lee siempre al día de su fuente única.
-- El padrón de descuentos (dto_vol) NO se expone: vive en la vista interna (sin grant
-- a anon); las vistas públicas y las RPC devuelven solo importes/netos.
--
-- Objetos:
--   vista_facturacion_neto_items  — detalle por ítem CON dto (interna, REVOKE anon).
--   vista_facturacion_neto        — por NP: neto, neto_original, falto_valor (pública).
--   vista_facturacion_faltantes   — por ítem con cajas_falto>0 + $ no facturado (pública).
--   facturacion_neto_lote(text[]) — np→neto,faltan[] para la columna 💵 Neto (SECURITY DEFINER).
--   facturacion_neto_detalle(text)— desglose por ítem para el modal (SECURITY DEFINER).
-- Depende de: public.canon_cod(text), precios_venta, clientes_dto, Entregas_Virgilio.
-- ══════════════════════════════════════════════════════════════════════════

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
)
SELECT ent.np,
       ent.cc AS cod_cliente,
       COALESCE(pv.cod, ent.cod_orig) AS cod,           -- código del maestro (con su cero)
       ent.cajas_ped, ent.cajas_ent, ent.cajas_falto,
       pv.uxb, pv.precio_unit AS precio_lista, COALESCE(cd.dto_vol, 0) AS dto_vol,
       CASE WHEN pv.precio_unit IS NOT NULL AND pv.precio_unit > 0
            THEN ROUND(ent.cajas_ent * COALESCE(pv.uxb,1) * pv.precio_unit * (1 - COALESCE(cd.dto_vol,0)), 2) END AS importe_ent,
       CASE WHEN pv.precio_unit IS NOT NULL AND pv.precio_unit > 0
            THEN ROUND(ent.cajas_ped * COALESCE(pv.uxb,1) * pv.precio_unit * (1 - COALESCE(cd.dto_vol,0)), 2) END AS importe_ped,
       (pv.precio_unit IS NULL OR pv.precio_unit <= 0) AS sin_precio,
       ent.cod_canon
FROM ent
LEFT JOIN public.clientes_dto  cd ON cd.cod_cliente = ent.cc
LEFT JOIN public.precios_venta pv ON public.canon_cod(pv.cod) = ent.cod_canon;

REVOKE ALL ON public.vista_facturacion_neto_items FROM anon, authenticated;

CREATE OR REPLACE VIEW public.vista_facturacion_neto AS
SELECT np,
       max(cod_cliente) AS cod_cliente,
       ROUND(COALESCE(SUM(importe_ent),0) * 0.98, 2) AS neto,
       ROUND(COALESCE(SUM(importe_ped),0) * 0.98, 2) AS neto_original,
       ROUND((COALESCE(SUM(importe_ped),0) - COALESCE(SUM(importe_ent),0)) * 0.98, 2) AS falto_valor,
       SUM(cajas_ped)   AS cajas_ped,
       SUM(cajas_ent)   AS cajas_ent,
       SUM(cajas_falto) AS cajas_falto,
       COUNT(*) FILTER (WHERE sin_precio) AS items_sin_precio
FROM public.vista_facturacion_neto_items
GROUP BY np;
GRANT SELECT ON public.vista_facturacion_neto TO anon, authenticated;

CREATE OR REPLACE VIEW public.vista_facturacion_faltantes AS
SELECT np, cod, cajas_falto, cajas_ped, cajas_ent,
       CASE WHEN importe_ped IS NOT NULL AND importe_ent IS NOT NULL
            THEN ROUND((importe_ped - importe_ent) * 0.98, 2) END AS importe_falto
FROM public.vista_facturacion_neto_items
WHERE cajas_falto > 0;
GRANT SELECT ON public.vista_facturacion_faltantes TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.facturacion_neto_lote(p_nps text[])
RETURNS TABLE(np text, neto numeric, faltan text[])
LANGUAGE sql SECURITY DEFINER SET search_path = public
AS $$
  WITH want AS (SELECT DISTINCT regexp_replace(x, '\.0+$', '') AS np FROM unnest(coalesce(p_nps,'{}')) x)
  SELECT i.np,
         ROUND(COALESCE(SUM(i.importe_ent),0) * 0.98, 2) AS neto,
         COALESCE(ARRAY_AGG(DISTINCT i.cod) FILTER (WHERE i.sin_precio), '{}'::text[]) AS faltan
  FROM public.vista_facturacion_neto_items i
  JOIN want w ON w.np = i.np
  GROUP BY i.np
$$;
GRANT EXECUTE ON FUNCTION public.facturacion_neto_lote(text[]) TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.facturacion_neto_detalle(p_np text)
RETURNS TABLE(cod text, cajas_ped numeric, cajas_ent numeric, cajas_falto numeric,
              uxb integer, precio_lista numeric, dto_vol numeric,
              importe_ent numeric, importe_ped numeric, sin_precio boolean)
LANGUAGE sql SECURITY DEFINER SET search_path = public
AS $$
  SELECT cod, cajas_ped, cajas_ent, cajas_falto, uxb, precio_lista, dto_vol,
         importe_ent, importe_ped, sin_precio
  FROM public.vista_facturacion_neto_items
  WHERE np = regexp_replace(p_np, '\.0+$', '')
  ORDER BY cod_canon
$$;
GRANT EXECUTE ON FUNCTION public.facturacion_neto_detalle(text) TO anon, authenticated;
