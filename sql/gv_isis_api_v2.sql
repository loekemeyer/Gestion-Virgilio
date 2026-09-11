-- ═══════════════════════════════════════════════════════════════════════════
-- gv_isis_api_v2.sql — Salida v2.0 hacia ISIS (contrato docs/ISIS-API-ESPECIFICACION.md §6).
--
-- Reunión 04/09 (ticket TkT115966): el pedido viaja como JSON y la clave es la
-- REFERENCIA (la etiqueta de la NP, "LK 0011"), NO una NP numérica. La NP la pone
-- ISIS al facturar. Objetos NUEVOS con prefijo gv_ — no tocan nada compartido ni la
-- v1.0 (isis_pedido_json / isis_api_pendientes / isis_api_pedido siguen intactos).
--
-- Alcance de esta Fase 1 (lado Virgilio, sin FDW a LK):
--   • Lista y pedido servidos por REFERENCIA, sólo pedidos WEB (LK/CH ####); los NP
--     numéricos ya están en ISIS y no se le ofrecen (evita doble carga).
--   • Los campos comerciales que viven en LK (vend, condicion_pago[_code],
--     payment_term, sucursal_entrega) salen NULL por ahora — se completan en Fase 2
--     (guardándolos al tomar el pedido, como plantea el anexo §2 de la spec).
--   • Sin acuse (el vínculo factura↔pedido lo resuelve nuestro parseo).
--
-- EXECUTE sólo para service_role (la Edge Function isis-api). RLS de las tablas
-- intacta: la anon key sigue sin ver isis_export_pedidos.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── El pedido completo, sobre v2.0 §6 ──────────────────────────────────────
CREATE OR REPLACE FUNCTION public.gv_isis_pedido_json(p_ref text)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
WITH r AS (
  SELECT trim(coalesce(p_ref,'')) AS ref
),
q AS (   -- fila de la cola (da empresa/estado/terminado_en)
  SELECT e.* FROM public.isis_export_pedidos e, r WHERE e.np = r.ref LIMIT 1
),
f AS (   -- cabecera (cod_cliente, razón social, fecha de salida)
  SELECT fn.* FROM public."Facturacion_NP" fn, r
   WHERE regexp_replace(fn.np, '\.0+$', '') = r.ref LIMIT 1
),
ent AS (   -- lo REALMENTE armado (código real ya resuelto por equivalencias)
  SELECT public.canon_cod(e.cod_art)          AS cod,
         SUM(coalesce(e.cajas_entregadas,0))  AS cajas_ent
    FROM public."Entregas_Virgilio" e, r
   WHERE regexp_replace(e.np, '\.0+$', '') = r.ref
   GROUP BY 1
),
items AS (
  SELECT ent.cod AS cod_art, ent.cajas_ent AS cajas, pv.uxb
    FROM ent
    LEFT JOIN public.precios_venta pv ON public.canon_cod(pv.cod) = ent.cod
   WHERE ent.cajas_ent > 0
),
tot AS (
  SELECT count(*) AS n, coalesce(sum(cajas),0) AS cajas FROM items
)
SELECT CASE WHEN (SELECT ref FROM r) = '' OR NOT EXISTS (SELECT 1 FROM ent WHERE cajas_ent > 0)
  THEN NULL
  ELSE jsonb_build_object(
    'referencia',          (SELECT ref FROM r),
    'empresa',             coalesce((SELECT empresa FROM q), public.empresa_de_np((SELECT ref FROM r))),
    'estado_integracion',  coalesce((SELECT estado FROM q), 'pendiente'),
    'terminado_en',        to_char(coalesce((SELECT terminado_en FROM q), (SELECT facturado_at FROM f), now())
                                    AT TIME ZONE 'America/Argentina/Buenos_Aires', 'YYYY-MM-DD"T"HH24:MI:SS') || '-03:00',
    'fecha_entrega',       to_char((SELECT fecha_salida FROM f), 'YYYY-MM-DD'),
    'pedido',              jsonb_build_object(
                             'source',              'Virgilio',
                             'cod_cliente',         nullif(regexp_replace(coalesce((SELECT cod_cliente FROM f),''), '\D','','g'), ''),
                             'razon_social',        (SELECT razon_social FROM f),
                             'sucursal_entrega',    NULL,   -- Fase 2 (vive en LK)
                             'vend',                NULL,   -- Fase 2
                             'condicion_pago',      NULL,   -- Fase 2
                             'condicion_pago_code', NULL,   -- Fase 2
                             'payment_term',        NULL,   -- Fase 2
                             'observaciones',       '',
                             'items',               coalesce((
                                SELECT jsonb_agg(
                                         jsonb_build_object('cod_art', cod_art, 'cajas', cajas)
                                         || CASE WHEN uxb IS NOT NULL THEN jsonb_build_object('uxb', uxb) ELSE '{}'::jsonb END
                                         ORDER BY cod_art)
                                  FROM items), '[]'::jsonb)
                           ),
    'control',             jsonb_build_object(
                             'items',         (SELECT n FROM tot),
                             'cajas',         (SELECT cajas FROM tot),
                             'neto_estimado', (SELECT round(neto,2) FROM public.vista_facturacion_neto WHERE np = (SELECT ref FROM r) LIMIT 1),
                             'moneda',        'ARS',
                             'nota',          'Informativo, sólo para control. El importe a facturar lo determina ISIS con su lista de precios.'
                           )
  )
END;
$$;
COMMENT ON FUNCTION public.gv_isis_pedido_json(text) IS
  'v2.0 §6: pedido para ISIS por REFERENCIA (etiqueta NP). cajas = lo armado. Campos comerciales de LK = NULL en Fase 1.';

-- ── Listado de cabeceras por estado — SÓLO pedidos web ─────────────────────
CREATE OR REPLACE FUNCTION public.gv_isis_pedidos_lista(
  p_estado  text        DEFAULT 'pendiente',
  p_empresa text        DEFAULT NULL,
  p_desde   timestamptz DEFAULT NULL,
  p_limit   int         DEFAULT 100
)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT coalesce(jsonb_agg(x.obj ORDER BY x.terminado_en), '[]'::jsonb)
  FROM (
    SELECT e.terminado_en,
           jsonb_build_object(
             'referencia',         e.np,
             'empresa',            e.empresa,
             'estado_integracion', e.estado,
             'terminado_en',       to_char(e.terminado_en AT TIME ZONE 'America/Argentina/Buenos_Aires', 'YYYY-MM-DD"T"HH24:MI:SS') || '-03:00',
             'items',              (SELECT count(*) FROM public."Entregas_Virgilio" ev
                                     WHERE regexp_replace(ev.np, '\.0+$','') = e.np AND coalesce(ev.cajas_entregadas,0) > 0),
             'cajas',              (SELECT coalesce(sum(ev.cajas_entregadas),0) FROM public."Entregas_Virgilio" ev
                                     WHERE regexp_replace(ev.np, '\.0+$','') = e.np)
           ) AS obj
      FROM public.isis_export_pedidos e
     WHERE e.estado = coalesce(nullif(p_estado,''), 'pendiente')
       AND (e.np ILIKE 'LK %' OR e.np ILIKE 'CH %')          -- sólo WEB: los NP numéricos ya están en ISIS
       AND (p_empresa IS NULL OR e.empresa = upper(p_empresa))
       AND (p_desde   IS NULL OR e.terminado_en >= p_desde)
     ORDER BY e.terminado_en
     LIMIT greatest(1, least(coalesce(p_limit,100), 1000))
  ) x;
$$;
COMMENT ON FUNCTION public.gv_isis_pedidos_lista(text,text,timestamptz,int) IS
  'v2.0 §4.1: cabeceras por estado, sólo referencias web (LK/CH ####).';

-- ── ISIS marca "lo bajé" (pendiente → entregado) ───────────────────────────
CREATE OR REPLACE FUNCTION public.gv_isis_pedido_marcar_entregado(p_ref text)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  WITH upd AS (
    UPDATE public.isis_export_pedidos
       SET estado = 'entregado', actualizado_en = now()
     WHERE np = trim(coalesce(p_ref,'')) AND estado = 'pendiente'
     RETURNING 1
  )
  SELECT EXISTS (SELECT 1 FROM upd);
$$;
COMMENT ON FUNCTION public.gv_isis_pedido_marcar_entregado(text) IS
  'v2.0 §7: GET /pedidos/{ref} pasa el pedido a entregado. Sólo referencias web.';

-- ── Permisos: sólo la Edge Function (service_role) ─────────────────────────
REVOKE ALL ON FUNCTION public.gv_isis_pedido_json(text)                              FROM public, anon, authenticated;
REVOKE ALL ON FUNCTION public.gv_isis_pedidos_lista(text,text,timestamptz,int)       FROM public, anon, authenticated;
REVOKE ALL ON FUNCTION public.gv_isis_pedido_marcar_entregado(text)                  FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.gv_isis_pedido_json(text)                           TO service_role;
GRANT EXECUTE ON FUNCTION public.gv_isis_pedidos_lista(text,text,timestamptz,int)    TO service_role;
GRANT EXECUTE ON FUNCTION public.gv_isis_pedido_marcar_entregado(text)               TO service_role;
