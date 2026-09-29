-- v23.86 (Luis, 28/09): ORDEN DE ARMADO POR CAMIÓN.
-- «Cuando hay más de una zona programada en un mismo día, primero que armen lo que va en un camión y
--  después lo que va en el otro … así, si no llegan, patean uno solo y no los dos por no sacar parte.»
-- Se agregan dos columnas AL FINAL de gv_monitor_tanda_camion (create or replace sólo deja agregar al final):
--   m3_camion    = m³ de ese camión ese día (el camión de la vista: Z2+Z3 juntas si cada una < 1 m³)
--   orden_camion = 1, 2, 3… dentro del día: primero el camión con MÁS m³ (si no llegan, se patea el más
--                  chico: la mayor cantidad de mercadería sale igual), Retira siempre al final.
-- La usan la TV (monitor/tv.html) y la botonera de Picking / Armado del celular (index.html).
-- Rollback: el CREATE de sql/gv_monitor_tanda_camion_v2364.sql (sin las dos columnas: hay que dropear
-- y recrear, porque create or replace no saca columnas).
create or replace view public.gv_monitor_tanda_camion with (security_invoker = true) as
 WITH src AS (
         SELECT upper(btrim(w.tanda)) AS tanda, w.fecha_entrega AS fecha, w.zona, lower(w.empresa) AS emp,
            w.cod_cliente AS cod, w.razon_social AS rs, COALESCE(w.m3, 0::numeric) AS m3, NULL::text AS tipo
           FROM "PPP_Web_Programacion" w
          WHERE w.tanda IS NOT NULL AND btrim(w.tanda) <> ''::text AND w.fecha_entrega IS NOT NULL
        UNION ALL
         SELECT upper(btrim(i.tanda)), "left"(i.fecha_entrega, 10)::date, i.zona,
                CASE WHEN i.np ~ '^\d+$'::text AND i.np::bigint > 90000 THEN 'lk'::text ELSE 'chef'::text END,
            i.cod, i.razon_social, COALESCE(i.m3, 0::numeric), i.tipo
           FROM gv_ppp_programacion_diaria i
          WHERE i.tanda IS NOT NULL AND btrim(i.tanda) <> ''::text AND i.fecha_entrega ~ '^\d{4}-\d{2}-\d{2}'::text AND i.np ~ '\d'::text
        ), t AS (
         SELECT src.tanda, src.fecha, sum(src.m3) AS m3,
            bool_or(COALESCE(src.tipo, ''::text) ~~* '%krikos%'::text OR COALESCE(src.zona, ''::text) ~* 'super'::text OR gv_es_super(src.emp, src.cod)) AS sup,
            bool_and(COALESCE(src.zona, ''::text) ~* '^\s*retira\s*$'::text) AS ret,
            min("substring"(src.zona, '(?i)zona\s*([0-9]+)'::text)::integer) AS zn,
            min(src.rs) FILTER (WHERE COALESCE(src.tipo, ''::text) ~~* '%krikos%'::text OR COALESCE(src.zona, ''::text) ~* 'super'::text OR gv_es_super(src.emp, src.cod)) AS rs_sup
           FROM src GROUP BY src.tanda, src.fecha
        ), g AS (
         SELECT t.tanda, t.fecha, t.m3, t.sup, t.ret, t.zn, t.rs_sup,
                CASE
                    WHEN t.sup THEN 'Súper · '::text || COALESCE(t.rs_sup, '?'::text)
                    WHEN t.ret THEN 'Retira'::text
                    WHEN t.zn = 1 THEN 'Capital Sur'::text
                    WHEN t.zn = 2 THEN 'Capital Centro'::text
                    WHEN t.zn = 3 THEN 'Capital Oeste'::text
                    WHEN t.zn = 4 THEN 'GBA Sur'::text
                    WHEN t.zn = 5 THEN 'GBA Oeste'::text
                    WHEN t.zn = ANY (ARRAY[6, 7]) THEN 'GBA Norte'::text
                    ELSE 'Sin zona'::text
                END AS grupo
           FROM t
        ), gd AS (
         SELECT g.*, sum(g.m3) OVER (PARTITION BY g.fecha, g.grupo) AS m3_grupo FROM g
        ), _oc_c AS (
         SELECT gd.tanda, gd.fecha, gd.m3, gd.grupo,
                CASE
                    WHEN (gd.grupo = ANY (ARRAY['Capital Centro'::text, 'Capital Oeste'::text])) AND gd.m3_grupo < 1::numeric AND (EXISTS ( SELECT 1
                       FROM gd o
                      WHERE o.fecha = gd.fecha AND o.m3_grupo < 1::numeric AND o.grupo =
                            CASE gd.grupo WHEN 'Capital Centro'::text THEN 'Capital Oeste'::text ELSE 'Capital Centro'::text END)) THEN 'Capital Centro-Oeste'::text
                    ELSE gd.grupo
                END AS camion
           FROM gd
        ), _oc_m AS (
         SELECT _oc_c.*, sum(_oc_c.m3) OVER (PARTITION BY _oc_c.fecha, _oc_c.camion) AS m3_cam FROM _oc_c
        )
 SELECT tanda, fecha, round(m3, 3) AS m3, camion, grupo <> 'Retira'::text AS usa_camion,
    round(m3_cam, 3) AS m3_camion,
    dense_rank() OVER (PARTITION BY fecha ORDER BY (camion = 'Retira'::text), m3_cam DESC, camion)::integer AS orden_camion
   FROM _oc_m;
grant select on public.gv_monitor_tanda_camion to anon, authenticated;
