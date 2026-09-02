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
-- v12.36 (2026-09-02): dto_vol se resuelve por (cod_cliente, EMPRESA). clientes_dto
-- pasó a PK compuesta (cod_cliente, empresa) y sync-clientes-dto trae los DOS padrones
-- (LK customers.dto_vol → 'lk'; Chef customers.dto_vol → 'chef'). Antes el join era solo
-- por código y una NP de Chef tomaba por azar el dto del cliente LK con el mismo número
-- (numeraciones independientes). La empresa se deriva de la NP: ^9 = lk, resto = chef.
--
-- v12.37 (2026-09-02): CLIENTES DE SÚPER. Si el cliente de la NP es una cadena de
-- supermercado con lista especial (cobranzas_cliente_cadena → cobranzas_precios_super,
-- que ya aplica item_discount), se valoriza con esa lista, SIN dto_vol y SIN el 2%
-- (el súper no paga el descuento web). Por eso el 2% ahora se aplica POR LÍNEA
-- (columna factor_web = 1 para súper, 0,98 para el resto) en vez de sobre el subtotal.
-- Si el artículo no está en la lista de súper, cae a la lista general (igual sin dto/2%).
-- Cadenas con usa_lista_general=true (ej. Messina) NO son súper acá: van como cliente
-- normal. Verificado contra ISIS: Coto/Diarco/INC/Abastecedor/La Anónima ≈ 0%.
--
-- Objetos:
--   vista_facturacion_neto_items  — detalle por ítem CON dto/lista súper (interna, REVOKE anon).
--   vista_facturacion_neto        — por NP: neto, neto_original, falto_valor (pública).
--   vista_facturacion_faltantes   — por ítem con cajas_falto>0 + $ no facturado (pública).
--   facturacion_neto_lote(text[]) — np→neto,faltan[] para la columna 💵 Neto (SECURITY DEFINER).
--   facturacion_neto_detalle(text)— desglose por ítem para el modal (SECURITY DEFINER).
-- Depende de: public.canon_cod(text), public.cob_norm_cod(text), precios_venta,
--   clientes_dto, cobranzas_cliente_cadena, cobranzas_super_cadena, cobranzas_precios_super,
--   Entregas_Virgilio.
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
),
base AS (
  SELECT ent.*,
    (CASE WHEN ent.np ~ '^9' THEN 'lk' ELSE 'chef' END) AS empresa,
    -- cadena de súper del cliente (cobranzas usa 'lk'/'ch'); sólo cadenas con lista especial
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
       -- 2% web: NO aplica al súper (factor 1); sí al resto (factor 0,98). Por línea.
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

CREATE OR REPLACE VIEW public.vista_facturacion_neto AS
SELECT np,
       max(cod_cliente) AS cod_cliente,
       ROUND(COALESCE(SUM(importe_ent * factor_web),0), 2) AS neto,
       ROUND(COALESCE(SUM(importe_ped * factor_web),0), 2) AS neto_original,
       ROUND(COALESCE(SUM(importe_ped * factor_web),0) - COALESCE(SUM(importe_ent * factor_web),0), 2) AS falto_valor,
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
            THEN ROUND((importe_ped - importe_ent) * factor_web, 2) END AS importe_falto
FROM public.vista_facturacion_neto_items
WHERE cajas_falto > 0;
GRANT SELECT ON public.vista_facturacion_faltantes TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.facturacion_neto_lote(p_nps text[])
RETURNS TABLE(np text, neto numeric, faltan text[])
LANGUAGE sql SECURITY DEFINER SET search_path = public
AS $$
  WITH want AS (SELECT DISTINCT regexp_replace(x, '\.0+$', '') AS np FROM unnest(coalesce(p_nps,'{}')) x)
  SELECT i.np,
         ROUND(COALESCE(SUM(i.importe_ent * i.factor_web),0), 2) AS neto,
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
