-- BACKUP 2026-09-07 — estado de gv_vista_cruce_facturacion y sus RPC ANTES de v14.11
-- (asignación 1-a-1 de facturas). Para rollback: correr este archivo entero.
-- Objetos propios de Gestión (prefijo gv_): no los usa Producción Virgilio.

create or replace view public.gv_vista_cruce_facturacion as
 SELECT np, tanda, fecha_salida, rs_virgilio, cod_cliente, empresa, neto_calculado,
    cajas_ent, items_sin_precio, doc_id, comprobante_id, doc_fecha, factura_total,
    factura_neto, factura_cajas, storage_path, cae, candidatos_cercanos, diff,
    diff_pct, estado,
    (EXISTS ( SELECT 1 FROM cobranzas_cliente_cadena cc
               WHERE cc.cod_cliente = v.cod_cliente AND cc.empresa = v.empresa)) AS es_super
   FROM ( WITH base AS (
                 SELECT f.np, f.tanda, f.fecha_salida, f.razon_social AS rs_virgilio,
                    f.cod_cliente, gv_empresa_de_np_texto(f.np) AS empresa,
                    n.neto AS neto_calculado, n.cajas_ent, n.items_sin_precio
                   FROM "Facturacion_NP" f
                     LEFT JOIN gv_vista_facturacion_neto n ON n.np = f.np
                ), cand AS (
                 SELECT b.np, b.tanda, b.fecha_salida, b.rs_virgilio, b.cod_cliente, b.empresa,
                    b.neto_calculado, b.cajas_ent, b.items_sin_precio,
                    d.id AS doc_id, d.comprobante_id, d.fecha AS doc_fecha, d.total AS factura_total,
                    d.subt_gravado AS factura_neto, d.total_cajas AS factura_cajas, d.storage_path, d.cae,
                    abs(COALESCE(d.total_cajas, '-1'::integer::numeric) - COALESCE(b.cajas_ent, '-1'::integer::numeric)) AS dcajas,
                    abs(d.fecha - b.fecha_salida) AS dfecha,
                    GREATEST(1::numeric, COALESCE(b.cajas_ent, 0::numeric) * 0.15) AS tolerancia_cajas
                   FROM base b
                     LEFT JOIN LATERAL ( SELECT dd.id, dd.comprobante_id, dd.fecha, dd.total,
                            dd.subt_gravado, dd.total_cajas, dd.storage_path, dd.cae
                           FROM isis_lk.documentos dd
                          WHERE b.empresa = 'lk'::text AND dd.familia = 'factura_venta'::text
                            AND dd.contraparte_codigo IS NOT NULL
                            AND canon_cod(dd.contraparte_codigo) = canon_cod(b.cod_cliente)
                            AND dd.fecha >= (b.fecha_salida - 3) AND dd.fecha <= (b.fecha_salida + 3)
                        UNION ALL
                         SELECT dd.id, dd.comprobante_id, dd.fecha, dd.total,
                            dd.subt_gravado, dd.total_cajas, dd.storage_path, dd.cae
                           FROM isis_ch.documentos dd
                          WHERE b.empresa = 'chef'::text AND dd.familia = 'factura_venta'::text
                            AND dd.contraparte_codigo IS NOT NULL
                            AND canon_cod(dd.contraparte_codigo) = canon_cod(b.cod_cliente)
                            AND dd.fecha >= (b.fecha_salida - 3) AND dd.fecha <= (b.fecha_salida + 3)) d ON true
                ), ranked AS (
                 SELECT c.*,
                    row_number() OVER (PARTITION BY c.np ORDER BY c.dcajas, c.dfecha) AS rn,
                    count(*) FILTER (WHERE c.doc_id IS NOT NULL AND c.dcajas <= c.tolerancia_cajas) OVER (PARTITION BY c.np) AS candidatos_cercanos
                   FROM cand c
                ), top1 AS ( SELECT * FROM ranked WHERE ranked.rn = 1 )
         SELECT top1.np, top1.tanda, top1.fecha_salida, top1.rs_virgilio, top1.cod_cliente,
            top1.empresa, top1.neto_calculado, top1.cajas_ent, top1.items_sin_precio,
            CASE WHEN top1.doc_id IS NOT NULL AND top1.dcajas <= top1.tolerancia_cajas THEN top1.doc_id ELSE NULL::bigint END AS doc_id,
            CASE WHEN top1.doc_id IS NOT NULL AND top1.dcajas <= top1.tolerancia_cajas THEN top1.comprobante_id ELSE NULL::text END AS comprobante_id,
            CASE WHEN top1.doc_id IS NOT NULL AND top1.dcajas <= top1.tolerancia_cajas THEN top1.doc_fecha ELSE NULL::date END AS doc_fecha,
            CASE WHEN top1.doc_id IS NOT NULL AND top1.dcajas <= top1.tolerancia_cajas THEN top1.factura_total ELSE NULL::numeric END AS factura_total,
            CASE WHEN top1.doc_id IS NOT NULL AND top1.dcajas <= top1.tolerancia_cajas THEN top1.factura_neto ELSE NULL::numeric END AS factura_neto,
            CASE WHEN top1.doc_id IS NOT NULL AND top1.dcajas <= top1.tolerancia_cajas THEN top1.factura_cajas ELSE NULL::numeric END AS factura_cajas,
            CASE WHEN top1.doc_id IS NOT NULL AND top1.dcajas <= top1.tolerancia_cajas THEN top1.storage_path ELSE NULL::text END AS storage_path,
            CASE WHEN top1.doc_id IS NOT NULL AND top1.dcajas <= top1.tolerancia_cajas THEN top1.cae ELSE NULL::text END AS cae,
            top1.candidatos_cercanos,
            CASE WHEN top1.doc_id IS NOT NULL AND top1.dcajas <= top1.tolerancia_cajas THEN top1.factura_neto - top1.neto_calculado ELSE NULL::numeric END AS diff,
            CASE WHEN top1.doc_id IS NOT NULL AND top1.dcajas <= top1.tolerancia_cajas AND top1.neto_calculado IS NOT NULL AND top1.neto_calculado <> 0::numeric
                 THEN round((top1.factura_neto - top1.neto_calculado) / top1.neto_calculado * 100::numeric, 2) ELSE NULL::numeric END AS diff_pct,
            CASE WHEN top1.neto_calculado IS NULL THEN 'sin_neto'::text
                 WHEN top1.doc_id IS NULL OR top1.dcajas > top1.tolerancia_cajas THEN 'sin_factura'::text
                 WHEN top1.candidatos_cercanos > 1 THEN 'ambiguo'::text
                 WHEN abs(COALESCE(top1.factura_neto, 0::numeric) - top1.neto_calculado) <= GREATEST(50::numeric, top1.neto_calculado * 0.01) THEN 'ok'::text
                 ELSE 'diff'::text END AS estado
           FROM top1) v;

CREATE OR REPLACE FUNCTION public.gv_cruce_facturacion_totales(p_desde date DEFAULT ((CURRENT_DATE - '30 days'::interval))::date, p_hasta date DEFAULT CURRENT_DATE, p_empresa text DEFAULT NULL::text)
 RETURNS TABLE(estado text, n bigint, suma_diff numeric)
 LANGUAGE sql SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $function$
  select estado, count(*)::bigint, coalesce(sum(diff), 0)
    from public.gv_vista_cruce_facturacion
   where fecha_salida between p_desde and p_hasta
     and (p_empresa is null or p_empresa = '' or empresa = p_empresa)
   group by estado
$function$;

CREATE OR REPLACE FUNCTION public.gv_cruce_facturacion_resumen(p_desde date DEFAULT ((CURRENT_DATE - '30 days'::interval))::date, p_hasta date DEFAULT CURRENT_DATE, p_empresa text DEFAULT NULL::text, p_estado text DEFAULT NULL::text, p_q text DEFAULT NULL::text, p_limit integer DEFAULT 100, p_offset integer DEFAULT 0)
 RETURNS TABLE(np text, tanda text, fecha_salida date, rs_virgilio text, cod_cliente text, empresa text, neto_calculado numeric, cajas_ent numeric, items_sin_precio bigint, doc_id bigint, comprobante_id text, doc_fecha date, factura_total numeric, factura_neto numeric, factura_cajas numeric, storage_path text, cae text, candidatos_cercanos bigint, diff numeric, diff_pct numeric, estado text, es_super boolean, total_count bigint)
 LANGUAGE sql SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $function$
  select v.*, count(*) over ()::bigint as total_count
    from public.gv_vista_cruce_facturacion v
   where v.fecha_salida between p_desde and p_hasta
     and (p_empresa is null or p_empresa = '' or v.empresa = p_empresa)
     and (p_estado is null or p_estado = '' or v.estado = p_estado)
     and (p_q is null or p_q = ''
          or v.rs_virgilio ilike '%'||p_q||'%' or v.cod_cliente ilike '%'||p_q||'%' or v.np ilike '%'||p_q||'%')
   order by case v.estado when 'diff' then 0 when 'ambiguo' then 1 when 'sin_factura' then 2 when 'sin_neto' then 3 else 4 end,
            abs(coalesce(v.diff, 0)) desc
   limit greatest(p_limit, 1) offset greatest(p_offset, 0)
$function$;
