-- v31.48 · Luis 16/10/2026: popup «Cajas pedidas» muestra la FECHA DE REALIZACIÓN del pedido.
-- gv_np_prog_info suma la columna fecha_recep AL FINAL (CREATE OR REPLACE sólo permite agregar al final).
-- ISIS: gv_ppp_programacion_diaria.fecha_recep · web: PPP_Web_Programacion.fecha_recep (la fecha real del
-- pedido; PPP_Web_Base.creado_at es cuándo se copió, 0 a 14 días después).
create or replace view public.gv_np_prog_info with (security_invoker = true) as
 SELECT btrim(p.np) AS np,
    'isis'::text AS origen,
    upper(btrim(COALESCE(p.tanda, ''::text))) AS tanda,
    "left"(p.fecha_entrega, 10) AS fecha_entrega,
    btrim(COALESCE(p.razon_social, ''::text)) AS razon_social,
    "left"(p.fecha_recep, 10) AS fecha_recep
   FROM gv_ppp_programacion_diaria p
  WHERE NULLIF(btrim(p.np), ''::text) IS NOT NULL
UNION ALL
 SELECT gv_ppp_web_np_label(w.empresa, w.np, w.np_idx) AS np,
    'web'::text AS origen,
    upper(btrim(COALESCE(w.tanda, ''::text))) AS tanda,
    "left"(w.fecha_entrega::text, 10) AS fecha_entrega,
    btrim(COALESCE(w.razon_social, ''::text)) AS razon_social,
    "left"(w.fecha_recep::text, 10) AS fecha_recep
   FROM "PPP_Web_Programacion" w
  WHERE w.np IS NOT NULL;
