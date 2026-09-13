-- =====================================================================================
-- gv_vista_control_remitos — la fuente de la pantalla Recepcion Remitos (RR).
-- Definicion VIVA al 2026-09-13 (v16.82). Se guarda entera en el repo porque la regla del
-- CLAUDE.md lo exige: una vista parcheada "en la base" y no en el repo costo caro el 12/09.
--
-- v15.42: nace como gv_ para completar cod_cliente y razon social de las NP web
--         ("LK 0003", "CH 0012"), que la vista_control_remitos vieja dejaba vacias porque
--         solo miraba las dos tablas de ISIS.
-- v16.82: suma la columna `remito` desde public."GV_NP_Remito" (ver gv_np_remito_v1682.sql).
--         LEFT JOIN: si la NP no resolvio remito, queda NULL y el front muestra la NP.
-- =====================================================================================
create or replace view public.gv_vista_control_remitos
with (security_invoker = true) as
 SELECT v.np,
    v.tanda,
    v.first_load,
    v.last_ccn,
    v.lios,
    v.controlado,
    v.sin_salida,
    COALESCE(NULLIF(btrim(v.cod_cliente), ''::text), w.cod_cliente, ev.cod_cliente, ''::text) AS cod_cliente,
    COALESCE(NULLIF(btrim(v.rs), ''::text), w.razon_social, fn.razon_social, ''::text) AS rs,
    v.vencido,
    v.clase,
    v.cajas,
    rm.remito
   FROM vista_control_remitos v
     LEFT JOIN LATERAL ( SELECT btrim(COALESCE(p.cod_cliente, ''::text)) AS cod_cliente,
            COALESCE(p.razon_social, ''::text) AS razon_social
           FROM "PPP_Web_Programacion" p
          WHERE gv_ppp_web_np_label(p.empresa, p.np, p.np_idx) = btrim(v.np)
          ORDER BY p.actualizado_at DESC NULLS LAST, p.creado_at DESC NULLS LAST
         LIMIT 1) w ON true
     LEFT JOIN LATERAL ( SELECT btrim(f.razon_social) AS razon_social
           FROM "Facturacion_NP" f
          WHERE regexp_replace(btrim(f.np), '\\.0+$'::text, ''::text) = btrim(v.np) AND COALESCE(btrim(f.razon_social), ''::text) <> ''::text
          ORDER BY f.facturado_at DESC NULLS LAST
         LIMIT 1) fn ON true
     LEFT JOIN LATERAL ( SELECT btrim(e.cod_cliente) AS cod_cliente
           FROM "Entregas_Virgilio" e
          WHERE regexp_replace(btrim(e.np), '\\.0+$'::text, ''::text) = btrim(v.np) AND COALESCE(btrim(e.cod_cliente), ''::text) <> ''::text
         LIMIT 1) ev ON true
     LEFT JOIN public."GV_NP_Remito" rm ON rm.np = btrim(v.np);
