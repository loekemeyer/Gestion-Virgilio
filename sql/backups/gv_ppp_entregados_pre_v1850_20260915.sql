-- BACKUP de la definicion VIVA de public.gv_ppp_entregados antes de la v18.50 (2026-09-15).
-- Tomada con pg_get_viewdef(). Para volver atras: ejecutar este archivo entero.
-- (CRN solo, sin CCR: la v13.57 lo dejo asi a proposito; ver comentario en index.html
--  "SÓLO CRN (Recepción Remitos = el remito volvió) es controlado/entregado".)
create or replace view public.gv_ppp_entregados
with (security_invoker = true) as
 WITH crn AS (
         SELECT regexp_replace(upper(btrim(split_part(r.texto, '|'::text, 1))), '\.0+$'::text, ''::text) AS np,
            max(NULLIF(upper(btrim(split_part(r.texto, '|'::text, 2))), ''::text)) AS tanda_crn,
            min(r.ts_cliente) AS controlado_at,
            count(*) AS n_crn
           FROM "Registros_Produccion_Virgilio" r
          WHERE r.opcion = 'CRN'::text AND NOT es_legajo_test(r.legajo)
          GROUP BY (regexp_replace(upper(btrim(split_part(r.texto, '|'::text, 1))), '\.0+$'::text, ''::text))
        ), web AS (
         SELECT gv_ppp_web_np_label(p.empresa, p.np, p.np_idx) AS np, p.empresa, p.tanda, p.cod_cliente AS cod,
            p.razon_social AS rs, p.m3, p.fecha_entrega::text AS fecha_entrega
           FROM "PPP_Web_Programacion" p
        ), isis AS (
         SELECT x.np, x.tanda, x.cod, x.rs, x.m3, x.fecha_entrega, x.prio
           FROM ( SELECT regexp_replace(btrim(gv_ppp_programacion_diaria.np), '\.0+$'::text, ''::text) AS np,
                    gv_ppp_programacion_diaria.tanda, gv_ppp_programacion_diaria.cod,
                    gv_ppp_programacion_diaria.razon_social AS rs, gv_ppp_programacion_diaria.m3,
                    "left"(gv_ppp_programacion_diaria.fecha_entrega, 10) AS fecha_entrega, 1 AS prio
                   FROM gv_ppp_programacion_diaria
                UNION ALL
                 SELECT regexp_replace(btrim("Facturacion_NP".np), '\.0+$'::text, ''::text), "Facturacion_NP".tanda,
                    "Facturacion_NP".cod_cliente, "Facturacion_NP".razon_social, "Facturacion_NP".m3,
                    "Facturacion_NP".fecha_salida::text, 2
                   FROM "Facturacion_NP"
                UNION ALL
                 SELECT regexp_replace(btrim(gv_ppp_entregados_meta.np), '\.0+$'::text, ''::text), gv_ppp_entregados_meta.tanda,
                    gv_ppp_entregados_meta.cod, gv_ppp_entregados_meta.rs, gv_ppp_entregados_meta.m3,
                    "left"(gv_ppp_entregados_meta.fecha_entrega, 10), 3
                   FROM gv_ppp_entregados_meta) x
        ), ccn AS (
         SELECT regexp_replace(upper(btrim(split_part("Registros_Produccion_Virgilio".texto, '|'::text, 1))), '\.0+$'::text, ''::text) AS np,
            max(("Registros_Produccion_Virgilio".ts_cliente AT TIME ZONE 'America/Argentina/Buenos_Aires'::text)::date) AS fecha_carga
           FROM "Registros_Produccion_Virgilio"
          WHERE "Registros_Produccion_Virgilio".opcion = 'CCN'::text
          GROUP BY (regexp_replace(upper(btrim(split_part("Registros_Produccion_Virgilio".texto, '|'::text, 1))), '\.0+$'::text, ''::text))
        ), ent AS (
         SELECT regexp_replace(upper(btrim("Entregas_Virgilio".np)), '\.0+$'::text, ''::text) AS np,
            sum("Entregas_Virgilio".cajas_pedidas) AS cajas_pedidas, sum("Entregas_Virgilio".cajas_entregadas) AS cajas_entregadas,
            sum("Entregas_Virgilio".cajas_falto) AS cajas_falto
           FROM "Entregas_Virgilio"
          GROUP BY (regexp_replace(upper(btrim("Entregas_Virgilio".np)), '\.0+$'::text, ''::text))
        ), fact AS (
         SELECT DISTINCT regexp_replace(upper(btrim("Facturacion_NP".np)), '\.0+$'::text, ''::text) AS np
           FROM "Facturacion_NP"
        )
 SELECT c.np,
    COALESCE(w.empresa, CASE WHEN c.np ~ '^9'::text THEN 'lk'::text WHEN c.np ~ '^4'::text THEN 'chef'::text ELSE NULL::text END) AS empresa,
    w.np IS NOT NULL AS es_web,
    COALESCE(w.tanda, i.tanda, c.tanda_crn) AS tanda,
    COALESCE(w.cod, i.cod) AS cod_cliente,
    COALESCE(w.rs, i.rs) AS razon_social,
    COALESCE(w.m3, i.m3) AS m3,
    COALESCE(w.fecha_entrega, i.fecha_entrega) AS fecha_entrega,
    cc.fecha_carga, c.controlado_at, c.n_crn,
    e.cajas_pedidas, e.cajas_entregadas, e.cajas_falto,
    f.np IS NOT NULL AS facturada
   FROM crn c
     LEFT JOIN web w ON w.np = c.np
     LEFT JOIN LATERAL ( SELECT i_1.np, i_1.tanda, i_1.cod, i_1.rs, i_1.m3, i_1.fecha_entrega, i_1.prio
           FROM isis i_1 WHERE i_1.np = c.np ORDER BY i_1.prio LIMIT 1) i ON true
     LEFT JOIN ccn cc ON cc.np = c.np
     LEFT JOIN ent e ON e.np = c.np
     LEFT JOIN fact f ON f.np = c.np
  WHERE w.np IS NOT NULL OR i.np IS NOT NULL;
alter view public.gv_ppp_entregados set (security_invoker = true);
