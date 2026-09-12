-- ============================================================================
-- v16.43 — El stock y el generador de OC dejan de ser ciegos a la demanda web
-- Proyecto Supabase: hrxfctzncixxqmpfhskv (Gestion Virgilio)
--
-- EL PROBLEMA
-- -----------
-- Toda la cadena de demanda (cuanto hay pedido, cuanto falta, cuanto hay que
-- comprar) leia UNA sola tabla: "PPP_Base_Pedidos", que es el espejo de ISIS.
-- Esa tabla quedo CONGELADA el 04/09/2026 (9.786 filas, no crece mas), porque
-- desde el 06/09 los pedidos de la pagina caen directo a "PPP_Web_Base" —
-- fue el primer cambio de Produccion Virgilio hacia Gestion Virgilio.
--
-- Resultado: 3.415 cajas de demanda web INVISIBLES para el stock y para las OC.
-- Sobre 4.720,66 cajas que el sistema creia pendientes, la demanda real estaba
-- subestimada ~42%. Nadie lo veia porque no daba error: daba un numero menor.
--
-- LA SOLUCION
-- -----------
-- Una vista union, gv_demanda_pedidos, que es la demanda COMPLETA:
--   * ISIS  -> gv_ppp_base_pedidos  (el espejo, NO la tabla cruda: ya aplica el
--              corte de espejo y el ocultamiento fila-por-fila de
--              GV_PPP_Prog_Override.oculto)
--   * web   -> "PPP_Web_Base"       (np_label como identificador de pedido)
-- y las 5 vistas + 1 matview de la cadena pasan a leerla.
--
-- POR QUE gv_ppp_base_pedidos Y NO LA TABLA CRUDA
-- -----------------------------------------------
-- Hay 11 NP de ISIS marcadas oculto=true en GV_PPP_Prog_Override (98696-98703,
-- 98050, 44620, 44621): son duplicados de pedidos web que Gestion ya programo.
-- Sumarlas junto con su version web contaria la misma mercaderia dos veces.
-- Leer el espejo las descuenta: -726 cajas. Ver la reconciliacion abajo.
--
-- MEDICION (12/09/2026, antes -> despues)
-- ----------------------------------------
--   vista_stock_procesada  filas          363    -> 366    (+3 codigos que solo
--                                                           tenian demanda web)
--   vista_stock_procesada  stock_total    48197  -> 48197  (sin cambios: el
--                                                           stock no se toco)
--   vista_stock_procesada  cajas_pedidas  4720.66 -> 7409.66
--   vista_stock_procesada  a_pedir        7561   -> 9092
--   v_cajas_pedidas        filas          192    -> 254
--   vista_generador_oc     filas          349    -> 345
--   gv_importados_ordenes  cajas_pedidas  1351   -> 2079
--
--   Reconciliacion exacta del +2.689,00:
--     ISIS crudo pendiente                 4720.66
--     ISIS por el espejo (-11 NP ocultas)  3994.66   (-726.00)
--     + web pendiente                     +3415.00   (3571 totales - 156 ya
--                                                     facturadas o canceladas)
--     = 7409.66  ✔ coincide con lo medido
--
-- ============================================================================
-- OJO: vista_stock_procesada es una MATVIEW. No admite create or replace, asi
-- que va DROP CASCADE + CREATE. El CASCADE llega a NIVEL 3, no 2:
--
--     vista_stock_procesada
--       +-- Stock_Saldos               (nivel 2)
--       +-- gv_importados_stock_dep    (nivel 2)
--             +-- gv_importados_ordenes  (nivel 3)  <-- se cayo DOS veces
--                                                       (v16.20 y v16.33) por
--                                                       mirar solo las directas
--
-- Antes de cualquier DROP CASCADE correr la consulta recursiva del CLAUDE.md,
-- y despues del cambio: select * from public.gv_endpoints_rotos;  (vacio = ok)
--
-- gv_importados_ordenes se recrea desde sql/gv_importados_ordenes_completa_v1634.sql
-- gv_importados_stock_dep esta en   sql/gv_importados_stock_real_v1604.sql
-- (los dos se incluyen igual mas abajo para que este archivo sea autosuficiente)
-- ============================================================================


-- ############################################################################
-- 1) La demanda completa: ISIS + web
-- ############################################################################

-- ============ gv_demanda_pedidos ============
drop view if exists public.gv_demanda_pedidos cascade;
create view public.gv_demanda_pedidos with (security_invoker = true) as
 SELECT b.pedido,
    b.articulo,
    b.cajas,
    'isis'::text AS origen
   FROM gv_ppp_base_pedidos b
UNION ALL
 SELECT w.np_label AS pedido,
    w.articulo,
    w.cajas,
    'web'::text AS origen
   FROM "PPP_Web_Base" w;
grant select on public.gv_demanda_pedidos to anon, authenticated, service_role;

-- ============ v_cajas_pedidas ============
drop view if exists public.v_cajas_pedidas cascade;
create view public.v_cajas_pedidas with (security_invoker = true) as
 WITH cerradas AS (
         SELECT "Facturacion_NP".np
           FROM "Facturacion_NP"
          WHERE "Facturacion_NP".np IS NOT NULL
        UNION
         SELECT "PPP_Entregados_Meta".np
           FROM "PPP_Entregados_Meta"
          WHERE "PPP_Entregados_Meta".np IS NOT NULL
        UNION
         SELECT "NP_Canceladas".np
           FROM "NP_Canceladas"
          WHERE "NP_Canceladas".np IS NOT NULL
        )
 SELECT regexp_replace(articulo, '([0-9Ee])[Ll]$'::text, '\1'::text) AS articulo,
    sum(cajas) AS cajas_pedidas
   FROM gv_demanda_pedidos b
  WHERE NOT (EXISTS ( SELECT 1
           FROM cerradas c
          WHERE c.np = b.pedido))
  GROUP BY (regexp_replace(articulo, '([0-9Ee])[Ll]$'::text, '\1'::text))
 HAVING sum(cajas) > 0::numeric;
grant select on public.v_cajas_pedidas to anon, authenticated, service_role;

-- ############################################################################
-- 2) La matview del stock. DROP CASCADE (llega a nivel 3) + CREATE + indice.
--    Tres cambios respecto de la v16.33:
--      R1  cerradas   += "GV_Web_Cancelados" (las NP web canceladas se cierran
--                       ahi, no en "NP_Canceladas")
--      R2  dem_raw y dem_oc_raw leen gv_demanda_pedidos (2 ocurrencias)
--      R3  pend_np_oc += las NP web programadas, no facturadas, no pickeadas y
--                       no canceladas. Hacia falta porque "PPP_Programacion_Diaria"
--                       es solo de ISIS: la programacion web vive en
--                       "PPP_Web_Programacion" y se identifica con
--                       gv_ppp_web_np_label(empresa, np, np_idx) = np_label.
-- ############################################################################

drop materialized view if exists public.vista_stock_procesada cascade;
create materialized view public.vista_stock_procesada as
 WITH fam AS (
         SELECT regexp_replace(upper(TRIM(BOTH FROM "Equivalencias_Familia".cod_secundario)), '^0+(?=.)'::text, ''::text) AS sec,
            regexp_replace(upper(TRIM(BOTH FROM "Equivalencias_Familia".cod_principal)), '^0+(?=.)'::text, ''::text) AS ppal
           FROM "Equivalencias_Familia"
        ), ins_cods AS (
         SELECT DISTINCT upper(TRIM(BOTH FROM "Insumos".cod)) AS cod
           FROM "Insumos"
          WHERE NULLIF(TRIM(BOTH FROM "Insumos".cod), ''::text) IS NOT NULL
        ), stock AS (
         SELECT regexp_replace(upper(TRIM(BOTH FROM vista_saldos_stock.clave)), '^0+(?=.)'::text, ''::text) AS codn,
            max(vista_saldos_stock.descripcion) AS descripcion,
            sum(COALESCE(vista_saldos_stock.terminado, 0::numeric)) AS terminado,
            sum(COALESCE(vista_saldos_stock.excedente, 0::numeric)) AS excedente,
            sum(COALESCE(vista_saldos_stock.separar_pedidos, 0::numeric)) AS separar_pedidos,
            sum(COALESCE(vista_saldos_stock.a_facturar, 0::numeric)) AS a_facturar,
            sum(COALESCE(vista_saldos_stock.a_guardar, 0::numeric)) AS a_guardar,
            sum(COALESCE(vista_saldos_stock.racks, 0::numeric)) AS racks,
            sum(COALESCE(vista_saldos_stock.racks_ch, 0::numeric)) AS racks_ch,
            sum(COALESCE(vista_saldos_stock.para_envasar, 0::numeric)) AS para_envasar,
            sum(COALESCE(vista_saldos_stock.insumos, 0::numeric)) AS insumos_dep
           FROM vista_saldos_stock
          GROUP BY (regexp_replace(upper(TRIM(BOTH FROM vista_saldos_stock.clave)), '^0+(?=.)'::text, ''::text))
        ), stock_e AS (
         SELECT s.codn,
            s.descripcion,
            s.terminado,
            s.excedente,
            s.separar_pedidos,
            s.a_facturar,
            s.a_guardar,
            s.racks,
            s.racks_ch,
            s.para_envasar,
            s.insumos_dep,
            regexp_replace(s.codn, '\s+(LK|CH|LOKE)$'::text, ''::text) AS cod_base,
                CASE
                    WHEN s.codn ~ '\s+(LK|LOKE)$'::text THEN 'LK'::text
                    WHEN s.codn ~ '\s+CH$'::text THEN 'CH'::text
                    ELSE NULL::text
                END AS linea_sufijo,
            s.terminado + s.excedente + s.separar_pedidos + s.a_facturar + s.a_guardar + s.racks + s.racks_ch + s.para_envasar AS stock_producto,
            COALESCE(f.ppal, s.codn) AS familia_ppal,
            f.sec IS NOT NULL AS es_secundario
           FROM stock s
             LEFT JOIN fam f ON f.sec = s.codn
        ), splits_con_stock AS (
         SELECT DISTINCT stock_e.cod_base
           FROM stock_e
          WHERE stock_e.linea_sufijo IS NOT NULL AND stock_e.stock_producto > 0::numeric
        ), cerradas AS (
         SELECT "Facturacion_NP".np
           FROM "Facturacion_NP"
          WHERE "Facturacion_NP".np IS NOT NULL
        UNION
         SELECT "PPP_Entregados_Meta".np
           FROM "PPP_Entregados_Meta"
          WHERE "PPP_Entregados_Meta".np IS NOT NULL
        UNION
         SELECT "NP_Canceladas".np
           FROM "NP_Canceladas"
          WHERE "NP_Canceladas".np IS NOT NULL
        UNION
         SELECT wc.np_label
           FROM "GV_Web_Cancelados" wc
          WHERE wc.np_label IS NOT NULL
        ), dem_raw AS (
         SELECT regexp_replace(upper(resolver_equiv(TRIM(BOTH FROM b.articulo))), '^0+(?=.)'::text, ''::text) AS codn,
            sum(COALESCE(b.cajas, 0::numeric)) AS pedidos
           FROM gv_demanda_pedidos b
          WHERE NULLIF(TRIM(BOTH FROM b.articulo), ''::text) IS NOT NULL AND NOT (EXISTS ( SELECT 1
                   FROM cerradas c_1
                  WHERE c_1.np = b.pedido))
          GROUP BY (regexp_replace(upper(resolver_equiv(TRIM(BOTH FROM b.articulo))), '^0+(?=.)'::text, ''::text))
         HAVING sum(COALESCE(b.cajas, 0::numeric)) > 0::numeric
        ), pickeadas AS (
         SELECT DISTINCT upper(TRIM(BOTH FROM "Registros_Produccion_Virgilio".texto)) AS tanda
           FROM "Registros_Produccion_Virgilio"
          WHERE "Registros_Produccion_Virgilio".opcion = 'TP'::text AND NULLIF(TRIM(BOTH FROM COALESCE("Registros_Produccion_Virgilio".texto, ''::text)), ''::text) IS NOT NULL
        ), pend_np_oc AS (
         SELECT DISTINCT TRIM(BOTH FROM p_1.np) AS np
           FROM "PPP_Programacion_Diaria" p_1
          WHERE NOT (TRIM(BOTH FROM p_1.np) IN ( SELECT TRIM(BOTH FROM "Facturacion_NP".np) AS btrim
                   FROM "Facturacion_NP")) AND NOT (upper(TRIM(BOTH FROM COALESCE(p_1.tanda, ''::text))) IN ( SELECT pickeadas.tanda
                   FROM pickeadas))
        UNION
         SELECT DISTINCT gv_ppp_web_np_label(w_1.empresa, w_1.np, w_1.np_idx) AS np
           FROM "PPP_Web_Programacion" w_1
          WHERE NOT (gv_ppp_web_np_label(w_1.empresa, w_1.np, w_1.np_idx) IN ( SELECT TRIM(BOTH FROM "Facturacion_NP".np) AS btrim
                   FROM "Facturacion_NP")) AND NOT (upper(TRIM(BOTH FROM COALESCE(w_1.tanda, ''::text))) IN ( SELECT pickeadas.tanda
                   FROM pickeadas)) AND NOT (EXISTS ( SELECT 1
                   FROM "GV_Web_Cancelados" wc_1
                  WHERE wc_1.np_label = gv_ppp_web_np_label(w_1.empresa, w_1.np, w_1.np_idx)))
        ), dem_oc_raw AS (
         SELECT regexp_replace(upper(resolver_equiv(TRIM(BOTH FROM b.articulo))), '^0+(?=.)'::text, ''::text) AS codn,
            sum(COALESCE(b.cajas, 0::numeric)) AS pedidos
           FROM gv_demanda_pedidos b
             JOIN pend_np_oc n ON TRIM(BOTH FROM b.pedido) = n.np
          WHERE NULLIF(TRIM(BOTH FROM b.articulo), ''::text) IS NOT NULL
          GROUP BY (regexp_replace(upper(resolver_equiv(TRIM(BOTH FROM b.articulo))), '^0+(?=.)'::text, ''::text))
        ), dem_fam AS (
         SELECT COALESCE(f.ppal, dr_1.codn) AS codn,
            sum(dr_1.pedidos) AS pedidos
           FROM dem_oc_raw dr_1
             LEFT JOIN fam f ON f.sec = dr_1.codn
          GROUP BY (COALESCE(f.ppal, dr_1.codn))
        ), universo AS (
         SELECT stock_e.codn
           FROM stock_e
        UNION
         SELECT dem_raw.codn
           FROM dem_raw
        ), proy AS (
         SELECT regexp_replace(upper(TRIM(BOTH FROM proyeccion_madre.cod)), '^0+(?=.)'::text, ''::text) AS codn,
            sum(COALESCE(proyeccion_madre.proy_cajas_mes, 0::numeric)) AS proy_cajas_mes
           FROM proyeccion_madre
          GROUP BY (regexp_replace(upper(TRIM(BOTH FROM proyeccion_madre.cod)), '^0+(?=.)'::text, ''::text))
        UNION ALL
         SELECT gv_cod_stock(g.cod) ||
                CASE
                    WHEN g.empresa = 'chef'::text THEN ' CH'::text
                    ELSE ' LK'::text
                END AS codn,
            sum(COALESCE(g.proy_cajas_mes, 0::numeric)) AS proy_cajas_mes
           FROM "GV_Proyeccion_Emp" g
          GROUP BY (gv_cod_stock(g.cod)), g.empresa
        ), cap AS (
         SELECT regexp_replace(upper(TRIM(BOTH FROM "Capacidad_Sector".cod)), '^0+(?=.)'::text, ''::text) AS codn,
            sum(COALESCE("Capacidad_Sector".cajas_max, 0::numeric)) AS capacidad_gondola
           FROM "Capacidad_Sector"
          GROUP BY (regexp_replace(upper(TRIM(BOTH FROM "Capacidad_Sector".cod)), '^0+(?=.)'::text, ''::text))
        ), oc_cfg AS (
         SELECT DISTINCT ON ((regexp_replace(upper(TRIM(BOTH FROM "OC_Maximos".cod)), '^0+(?=.)'::text, ''::text))) regexp_replace(upper(TRIM(BOTH FROM "OC_Maximos".cod)), '^0+(?=.)'::text, ''::text) AS codn,
            "OC_Maximos".linea,
            NULLIF(TRIM(BOTH FROM COALESCE("OC_Maximos".proveedor, ''::text)), ''::text) AS proveedor,
            NULLIF(TRIM(BOTH FROM COALESCE("OC_Maximos".proveedor2, ''::text)), ''::text) AS proveedor2,
            COALESCE("OC_Maximos".prop_prov1, 100::numeric) AS pr1,
            COALESCE("OC_Maximos".prop_prov2, 0::numeric) AS pr2,
                CASE
                    WHEN COALESCE("OC_Maximos".indice, 0::numeric) > 0::numeric THEN "OC_Maximos".indice
                    ELSE 1.5
                END AS indice,
            COALESCE("OC_Maximos".activo, true) AS activo
           FROM "OC_Maximos"
          WHERE NULLIF(TRIM(BOTH FROM "OC_Maximos".cod), ''::text) IS NOT NULL
          ORDER BY (regexp_replace(upper(TRIM(BOTH FROM "OC_Maximos".cod)), '^0+(?=.)'::text, ''::text)), (COALESCE("OC_Maximos".activo, true)) DESC NULLS LAST
        ), uxc AS (
         SELECT vista_uni_x_caja.codn,
            vista_uni_x_caja.uni_x_caja
           FROM vista_uni_x_caja
        ), ncaja AS (
         SELECT DISTINCT ON (t.codn) t.codn,
            t.n_caja
           FROM ( SELECT regexp_replace(upper(TRIM(BOTH FROM "Articulos_Cajas"."Cod_Art")), '^0+(?=.)'::text, ''::text) AS codn,
                    "Articulos_Cajas"."N_Caja" AS n_caja,
                    count(*) AS c
                   FROM "Articulos_Cajas"
                  WHERE "Articulos_Cajas"."N_Caja" IS NOT NULL
                  GROUP BY (regexp_replace(upper(TRIM(BOTH FROM "Articulos_Cajas"."Cod_Art")), '^0+(?=.)'::text, ''::text)), "Articulos_Cajas"."N_Caja") t
          ORDER BY t.codn, t.c DESC, t.n_caja
        )
 SELECT u.codn AS cod,
    COALESCE(se.cod_base, regexp_replace(u.codn, '\s+(LK|CH|LOKE)$'::text, ''::text)) AS cod_base,
    COALESCE(se.descripcion, nom.descripcion) AS descripcion,
    COALESCE(se.linea_sufijo, oc.linea) AS linea,
    COALESCE(se.familia_ppal, COALESCE(f2.ppal, u.codn)) AS familia_principal,
    COALESCE(se.es_secundario, f2.sec IS NOT NULL) AS es_secundario,
    COALESCE(se.terminado, 0::numeric) AS terminado,
    COALESCE(se.excedente, 0::numeric) AS excedente,
    COALESCE(se.separar_pedidos, 0::numeric) AS separar_pedidos,
    COALESCE(se.a_facturar, 0::numeric) AS a_facturar,
    COALESCE(se.a_guardar, 0::numeric) AS a_guardar,
    COALESCE(se.racks, 0::numeric) AS racks,
    COALESCE(se.racks_ch, 0::numeric) AS racks_ch,
    COALESCE(se.para_envasar, 0::numeric) AS para_envasar,
    COALESCE(se.insumos_dep, 0::numeric) AS insumos_dep,
    COALESCE(se.stock_producto, 0::numeric) AS stock_total,
    COALESCE(dr.pedidos, 0::numeric) AS cajas_pedidas,
    COALESCE(df.pedidos, 0::numeric) AS cajas_pedidas_familia,
    COALESCE(p.proy_cajas_mes, 0::numeric) AS proy_cajas_mes,
    COALESCE(c.capacidad_gondola, 0::numeric) AS capacidad_gondola,
    ic.cod IS NOT NULL AND (COALESCE(se.terminado, 0::numeric) + COALESCE(se.racks, 0::numeric) + COALESCE(se.racks_ch, 0::numeric) + COALESCE(se.excedente, 0::numeric) + COALESCE(se.a_guardar, 0::numeric)) = 0::numeric AS es_insumo,
    COALESCE(oc.activo, true) AS activo_oc,
    oc.proveedor IS NOT NULL AS tiene_prov_real,
    oc.proveedor,
    oc.proveedor2,
    COALESCE(oc.pr1, 100::numeric) AS pr1,
    COALESCE(oc.pr2, 0::numeric) AS pr2,
    COALESCE(oc.indice, 1.5) AS indice,
    COALESCE(ux.uni_x_caja, 0::numeric) AS uni_x_caja,
    nc.n_caja,
        CASE
            WHEN COALESCE(p.proy_cajas_mes, 0::numeric) > 0::numeric THEN LEAST(ceil(COALESCE(p.proy_cajas_mes, 0::numeric) * COALESCE(oc.indice, 1.5)), COALESCE(NULLIF(COALESCE(c.capacidad_gondola, 0::numeric), 0::numeric), 1000000000::numeric))
            WHEN oc.proveedor IS NOT NULL THEN COALESCE(NULLIF(COALESCE(c.capacidad_gondola, 0::numeric), 0::numeric), 0::numeric)
            ELSE 0::numeric
        END AS maximo,
    GREATEST(0::numeric, ceil(
        CASE
            WHEN COALESCE(p.proy_cajas_mes, 0::numeric) > 0::numeric THEN LEAST(ceil(COALESCE(p.proy_cajas_mes, 0::numeric) * COALESCE(oc.indice, 1.5)), COALESCE(NULLIF(COALESCE(c.capacidad_gondola, 0::numeric), 0::numeric), 1000000000::numeric))
            WHEN oc.proveedor IS NOT NULL THEN COALESCE(NULLIF(COALESCE(c.capacidad_gondola, 0::numeric), 0::numeric), 0::numeric)
            ELSE 0::numeric
        END + COALESCE(df.pedidos, 0::numeric) - COALESCE(se.stock_producto, 0::numeric)))::integer AS a_pedir,
        CASE
            WHEN ic.cod IS NOT NULL AND COALESCE(se.stock_producto, 0::numeric) = 0::numeric AND COALESCE(dr.pedidos, 0::numeric) = 0::numeric THEN false
            WHEN COALESCE(se.cod_base, regexp_replace(u.codn, '\s+(LK|CH|LOKE)$'::text, ''::text)) = u.codn AND scs.cod_base IS NOT NULL AND COALESCE(se.stock_producto, 0::numeric) = 0::numeric THEN false
            ELSE true
        END AS visible_en_stock
   FROM universo u
     LEFT JOIN stock_e se ON se.codn = u.codn
     LEFT JOIN fam f2 ON f2.sec = u.codn
     LEFT JOIN vista_nombres_articulos nom ON nom.cod = u.codn
     LEFT JOIN dem_raw dr ON dr.codn = u.codn
     LEFT JOIN dem_fam df ON df.codn = COALESCE(se.familia_ppal, COALESCE(f2.ppal, u.codn))
     LEFT JOIN proy p ON p.codn = u.codn
     LEFT JOIN cap c ON c.codn = u.codn
     LEFT JOIN ins_cods ic ON ic.cod = u.codn
     LEFT JOIN oc_cfg oc ON oc.codn = u.codn
     LEFT JOIN splits_con_stock scs ON scs.cod_base = u.codn
     LEFT JOIN uxc ux ON ux.codn = u.codn
     LEFT JOIN ncaja nc ON nc.codn = u.codn
  WHERE NOT (ic.cod IS NOT NULL AND COALESCE(se.stock_producto, 0::numeric) = 0::numeric AND COALESCE(dr.pedidos, 0::numeric) = 0::numeric)
  ORDER BY u.codn;
create unique index idx_vista_stock_procesada_cod
  on public.vista_stock_procesada using btree (cod);
grant select on public.vista_stock_procesada to anon, authenticated, service_role;
-- El indice unico NO es decorativo: sin el, los crons 55 y 57 no pueden hacer
-- REFRESH MATERIALIZED VIEW CONCURRENTLY. Probar despues de recrear:
--   refresh materialized view concurrently public.vista_stock_procesada;

-- ############################################################################
-- 3) Los tres dependientes que se lleva el CASCADE. Recrear en este orden.
-- ############################################################################

-- ============ Stock_Saldos (nivel 2) ============
drop view if exists public."Stock_Saldos" cascade;
create view public."Stock_Saldos" with (security_invoker = true) as
 SELECT cod_base,
    familia_principal,
    es_secundario,
    stock_total
   FROM vista_stock_procesada;
grant select on public."Stock_Saldos" to anon, authenticated, service_role;

-- ============ gv_importados_stock_dep (nivel 2) ============
drop view if exists public.gv_importados_stock_dep cascade;
create view public.gv_importados_stock_dep with (security_invoker = true) as
 WITH sal AS (
         SELECT gv_cod_stock(s.cod_art) AS cod_norm,
            upper(COALESCE(s.empresa, 'Mixto'::text)) AS empresa,
            sum(COALESCE(s.terminado, 0::numeric) + COALESCE(s.excedente, 0::numeric) + COALESCE(s.separar_pedidos, 0::numeric) + COALESCE(s.a_facturar, 0::numeric) + COALESCE(s.a_guardar, 0::numeric) + COALESCE(s.racks, 0::numeric) + COALESCE(s.racks_ch, 0::numeric) + COALESCE(s.para_envasar, 0::numeric)) AS cajas_bruto,
            sum(COALESCE(s.insumos, 0::numeric)) AS cajas_insumos
           FROM vista_saldos_stock s
          GROUP BY (gv_cod_stock(s.cod_art)), (upper(COALESCE(s.empresa, 'Mixto'::text)))
        ), dem AS (
         SELECT gv_cod_stock(p.cod) AS cod_norm,
                CASE
                    WHEN p.cod ~ '\s+CH$'::text THEN 'CH'::text
                    WHEN p.cod ~ '\s+(LK|LOKE)$'::text THEN 'LK'::text
                    ELSE 'MIXTO'::text
                END AS empresa,
            sum(COALESCE(p.cajas_pedidas, 0::numeric)) AS cajas_pedidas
           FROM vista_stock_procesada p
          GROUP BY (gv_cod_stock(p.cod)), (
                CASE
                    WHEN p.cod ~ '\s+CH$'::text THEN 'CH'::text
                    WHEN p.cod ~ '\s+(LK|LOKE)$'::text THEN 'LK'::text
                    ELSE 'MIXTO'::text
                END)
        )
 SELECT COALESCE(sal.cod_norm, dem.cod_norm) AS cod_norm,
    COALESCE(sal.empresa, dem.empresa) AS empresa,
    COALESCE(sal.cajas_bruto, 0::numeric) AS cajas_bruto,
    COALESCE(dem.cajas_pedidas, 0::numeric) AS cajas_pedidas,
    COALESCE(sal.cajas_insumos, 0::numeric) AS cajas_insumos
   FROM sal
     FULL JOIN dem ON dem.cod_norm = sal.cod_norm AND dem.empresa = sal.empresa;
grant select on public.gv_importados_stock_dep to anon, authenticated, service_role;

-- ============ gv_importados_ordenes (nivel 3) ============
-- Definicion completa en sql/gv_importados_ordenes_completa_v1634.sql — hay que
-- recrearla DESPUES de gv_importados_stock_dep. Es la que se cayo dos veces.

-- ############################################################################
-- 4) El resto de la cadena de demanda (create or replace, no hace falta drop)
-- ############################################################################

-- ============ vista_stock_vs_pedidos ============
drop view if exists public.vista_stock_vs_pedidos cascade;
create view public.vista_stock_vs_pedidos with (security_invoker = true) as
 WITH stk AS (
         SELECT gv_cod_stock(vista_saldos_stock.cod_art) AS cod,
            sum(COALESCE(vista_saldos_stock.terminado, 0::numeric)) AS terminado,
            sum(COALESCE(vista_saldos_stock.excedente, 0::numeric)) AS excedente,
            sum(COALESCE(vista_saldos_stock.separar_pedidos, 0::numeric)) AS separar_pedidos,
            sum(COALESCE(vista_saldos_stock.a_facturar, 0::numeric)) AS a_facturar,
            sum(COALESCE(vista_saldos_stock.a_guardar, 0::numeric)) AS a_guardar,
            sum(COALESCE(vista_saldos_stock.racks, 0::numeric)) AS racks,
            sum(COALESCE(vista_saldos_stock.racks_ch, 0::numeric)) AS racks_ch,
            sum(COALESCE(vista_saldos_stock.para_envasar, 0::numeric)) AS para_envasar,
            sum(COALESCE(vista_saldos_stock.terminado, 0::numeric) + COALESCE(vista_saldos_stock.excedente, 0::numeric) + COALESCE(vista_saldos_stock.separar_pedidos, 0::numeric) + COALESCE(vista_saldos_stock.a_facturar, 0::numeric) + COALESCE(vista_saldos_stock.a_guardar, 0::numeric) + COALESCE(vista_saldos_stock.racks, 0::numeric) + COALESCE(vista_saldos_stock.racks_ch, 0::numeric) + COALESCE(vista_saldos_stock.para_envasar, 0::numeric)) AS stock_total
           FROM vista_saldos_stock
          GROUP BY (gv_cod_stock(vista_saldos_stock.cod_art))
        ), pend_np AS (
         SELECT DISTINCT btrim("PPP_Programacion_Diaria".np) AS np
           FROM "PPP_Programacion_Diaria"
          WHERE NOT (btrim("PPP_Programacion_Diaria".np) IN ( SELECT btrim("Facturacion_NP".np) AS btrim
                   FROM "Facturacion_NP"))
        ), dem AS (
         SELECT gv_cod_stock(b.articulo) AS cod,
            sum(COALESCE(b.cajas, 0::numeric)) AS pedidos_ped,
            count(DISTINCT b.pedido) AS nps_ped
           FROM gv_demanda_pedidos b
             JOIN pend_np p ON btrim(b.pedido) = p.np
          WHERE NULLIF(btrim(b.articulo), ''::text) IS NOT NULL
          GROUP BY (gv_cod_stock(b.articulo))
        )
 SELECT COALESCE(s.cod, d.cod) AS cod,
    COALESCE(s.stock_total, 0::numeric) AS stock_total,
    COALESCE(s.terminado, 0::numeric) AS terminado,
    COALESCE(s.excedente, 0::numeric) AS excedente,
    COALESCE(s.separar_pedidos, 0::numeric) AS separar_pedidos,
    COALESCE(s.a_facturar, 0::numeric) AS a_facturar,
    COALESCE(s.a_guardar, 0::numeric) AS a_guardar,
    COALESCE(s.racks, 0::numeric) AS racks,
    COALESCE(s.racks_ch, 0::numeric) AS racks_ch,
    COALESCE(s.para_envasar, 0::numeric) AS para_envasar,
    COALESCE(d.pedidos_ped, 0::numeric) AS pedidos_ped,
    COALESCE(d.nps_ped, 0::bigint) AS nps_ped,
    GREATEST(COALESCE(d.pedidos_ped, 0::numeric) - COALESCE(s.stock_total, 0::numeric), 0::numeric) AS falta
   FROM stk s
     FULL JOIN dem d ON d.cod = s.cod
  WHERE COALESCE(s.stock_total, 0::numeric) <> 0::numeric OR COALESCE(d.pedidos_ped, 0::numeric) <> 0::numeric;
grant select on public.vista_stock_vs_pedidos to anon, authenticated, service_role;
-- ============ vista_faltante_demanda ============
drop view if exists public.vista_faltante_demanda cascade;
create view public.vista_faltante_demanda with (security_invoker = true) as
 WITH np_excl AS (
         SELECT DISTINCT TRIM(BOTH FROM "Facturacion_NP".np) AS np
           FROM "Facturacion_NP"
        UNION
         SELECT DISTINCT TRIM(BOTH FROM "PPP_Entregados_Meta".np) AS btrim
           FROM "PPP_Entregados_Meta"
        UNION
         SELECT DISTINCT TRIM(BOTH FROM "NP_Canceladas".np) AS btrim
           FROM "NP_Canceladas"
        ), nps AS (
         SELECT TRIM(BOTH FROM p.np) AS np,
            upper(TRIM(BOTH FROM COALESCE(p.tanda, ''::text))) AS tanda,
            "left"(p.fecha_entrega, 10) AS fecha_salida,
            TRIM(BOTH FROM COALESCE(p.cod, ''::text)) AS cod_cliente,
            COALESCE(p.razon_social, ''::text) AS rs,
            lower(TRIM(BOTH FROM COALESCE(p.zona, ''::text))) = 'super'::text AS es_super
           FROM "PPP_Programacion_Diaria" p
          WHERE NOT (TRIM(BOTH FROM p.np) IN ( SELECT np_excl.np
                   FROM np_excl))
        ), pick_ev AS (
         SELECT upper(TRIM(BOTH FROM "Registros_Produccion_Virgilio".texto)) AS tanda,
            "Registros_Produccion_Virgilio".opcion
           FROM "Registros_Produccion_Virgilio"
          WHERE ("Registros_Produccion_Virgilio".opcion = ANY (ARRAY['EP'::text, 'TP'::text])) AND NOT es_legajo_test("Registros_Produccion_Virgilio".legajo) AND (upper(TRIM(BOTH FROM COALESCE("Registros_Produccion_Virgilio".texto, ''::text))) IN ( SELECT DISTINCT nps.tanda
                   FROM nps
                  WHERE nps.tanda <> ''::text))
        ), tanda_st AS (
         SELECT DISTINCT t.tanda,
                CASE
                    WHEN (EXISTS ( SELECT 1
                       FROM pick_ev e_1
                      WHERE e_1.tanda = t.tanda AND e_1.opcion = 'TP'::text)) THEN 'preparado'::text
                    WHEN (EXISTS ( SELECT 1
                       FROM pick_ev e_1
                      WHERE e_1.tanda = t.tanda AND e_1.opcion = 'EP'::text)) THEN 'enpicking'::text
                    ELSE 'sinpickear'::text
                END AS estado
           FROM ( SELECT DISTINCT nps.tanda
                   FROM nps
                  WHERE nps.tanda <> ''::text) t
        ), emp AS (
         SELECT nps.np,
                CASE
                    WHEN COALESCE(regexp_replace(nps.np, '\D'::text, ''::text, 'g'::text), '0'::text)::bigint > 90000 THEN 'LK'::text
                    ELSE 'CH'::text
                END AS empresa
           FROM nps
        )
 SELECT
        CASE
            WHEN norm_cod(b.articulo) = ANY (ARRAY['437E'::text, '438E'::text, '439E'::text, '809E'::text]) THEN (norm_cod(b.articulo) || ' '::text) || e.empresa
            ELSE norm_cod(b.articulo)
        END AS cod,
    n.np,
    n.rs,
    n.cod_cliente,
    COALESCE(b.cajas, 0::numeric) AS cajas,
    n.fecha_salida,
        CASE
            WHEN n.fecha_salida ~ '^\d{4}-\d{2}-\d{2}$'::text THEN dia_armado(n.fecha_salida::date)::text
            ELSE n.fecha_salida
        END AS fecha_armado,
    n.tanda,
    COALESCE(ts.estado, 'sinpickear'::text) AS estado_picking,
    n.es_super
   FROM nps n
     JOIN gv_demanda_pedidos b ON TRIM(BOTH FROM b.pedido) = n.np
     JOIN emp e ON e.np = n.np
     LEFT JOIN tanda_st ts ON ts.tanda = n.tanda
  WHERE TRIM(BOTH FROM COALESCE(b.articulo, ''::text)) <> ''::text;
grant select on public.vista_faltante_demanda to anon, authenticated, service_role;

-- ============ vista_generador_oc ============
drop view if exists public.vista_generador_oc cascade;
create view public.vista_generador_oc with (security_invoker = true) as
 WITH fam AS (
         SELECT regexp_replace(regexp_replace(regexp_replace(upper(btrim("Equivalencias_Familia".cod_secundario)), '^0+(?=.)'::text, ''::text), 'L$'::text, ''::text), '^546E$'::text, '546'::text) AS sec,
            regexp_replace(regexp_replace(regexp_replace(upper(btrim("Equivalencias_Familia".cod_principal)), '^0+(?=.)'::text, ''::text), 'L$'::text, ''::text), '^546E$'::text, '546'::text) AS ppal
           FROM "Equivalencias_Familia"
        ), stk_raw AS (
         SELECT regexp_replace(regexp_replace(regexp_replace(upper(btrim(vista_saldos_stock.cod_art)), '^0+(?=.)'::text, ''::text), ' +(LK|CH)$'::text, ''::text), '·.*$'::text, ''::text) AS codn,
            sum(COALESCE(vista_saldos_stock.terminado, 0::numeric) + COALESCE(vista_saldos_stock.a_guardar, 0::numeric) + COALESCE(vista_saldos_stock.racks, 0::numeric) + COALESCE(vista_saldos_stock.excedente, 0::numeric) + COALESCE(vista_saldos_stock.separar_pedidos, 0::numeric) + COALESCE(vista_saldos_stock.a_facturar, 0::numeric) + COALESCE(vista_saldos_stock.para_envasar, 0::numeric) + COALESCE(vista_saldos_stock.racks_ch, 0::numeric)) AS stock,
            sum(COALESCE(vista_saldos_stock.terminado, 0::numeric) + COALESCE(vista_saldos_stock.a_guardar, 0::numeric) + COALESCE(vista_saldos_stock.racks, 0::numeric) + COALESCE(vista_saldos_stock.excedente, 0::numeric) + COALESCE(vista_saldos_stock.para_envasar, 0::numeric) + COALESCE(vista_saldos_stock.racks_ch, 0::numeric)) AS fin_dep,
            max(vista_saldos_stock.descripcion) AS descripcion
           FROM vista_saldos_stock
          GROUP BY (regexp_replace(regexp_replace(regexp_replace(upper(btrim(vista_saldos_stock.cod_art)), '^0+(?=.)'::text, ''::text), ' +(LK|CH)$'::text, ''::text), '·.*$'::text, ''::text))
        ), stk AS (
         SELECT COALESCE(f.ppal, sr.codn) AS codn,
            sum(sr.stock) AS stock,
            sum(sr.fin_dep) AS fin_dep,
            max(sr.descripcion) AS descripcion
           FROM stk_raw sr
             LEFT JOIN fam f ON f.sec = sr.codn
          GROUP BY (COALESCE(f.ppal, sr.codn))
        ), proy_raw AS (
         SELECT regexp_replace(regexp_replace(regexp_replace(upper(btrim(proyeccion_madre.cod)), '^0+(?=.)'::text, ''::text), 'L$'::text, ''::text), '^546E$'::text, '546'::text) AS codn,
            sum(COALESCE(proyeccion_madre.proy_uni_mes, 0::numeric)) AS uni,
            max(COALESCE(proyeccion_madre.proy_cajas_mes, 0::numeric)) AS cajas
           FROM proyeccion_madre
          WHERE btrim(proyeccion_madre.cod) ~ '^[0-9]'::text
          GROUP BY (regexp_replace(regexp_replace(regexp_replace(upper(btrim(proyeccion_madre.cod)), '^0+(?=.)'::text, ''::text), 'L$'::text, ''::text), '^546E$'::text, '546'::text))
        ), gux AS (
         SELECT gv_cod_stock("GV_UxB".cod) AS c,
            max("GV_UxB".uxb) AS u
           FROM "GV_UxB"
          WHERE "GV_UxB".uxb > 0::numeric
          GROUP BY (gv_cod_stock("GV_UxB".cod))
        ), proy AS (
         SELECT COALESCE(f.ppal, pr.codn) AS codn,
            sum(
                CASE
                    WHEN gx.u > 0::numeric THEN pr.uni / gx.u
                    ELSE pr.cajas
                END) AS proy
           FROM proy_raw pr
             LEFT JOIN fam f ON f.sec = pr.codn
             LEFT JOIN gux gx ON gx.c = pr.codn
          GROUP BY (COALESCE(f.ppal, pr.codn))
        ), cap AS (
         SELECT regexp_replace(upper(btrim("Capacidad_Sector".cod)), '^0+(?=.)'::text, ''::text) AS codn,
            sum(COALESCE("Capacidad_Sector".cajas_max, 0::numeric)) AS cap
           FROM "Capacidad_Sector"
          GROUP BY (regexp_replace(upper(btrim("Capacidad_Sector".cod)), '^0+(?=.)'::text, ''::text))
        ), cfg AS (
         SELECT DISTINCT ON ((regexp_replace(upper(btrim("OC_Maximos".cod)), '^0+(?=.)'::text, ''::text))) regexp_replace(upper(btrim("OC_Maximos".cod)), '^0+(?=.)'::text, ''::text) AS codn,
            upper(btrim("OC_Maximos".cod)) AS cod_cfg,
            "OC_Maximos".descripcion,
            "OC_Maximos".linea,
            NULLIF(btrim(COALESCE("OC_Maximos".proveedor, ''::text)), ''::text) AS proveedor,
            COALESCE("OC_Maximos".prop_prov1, 100::numeric) AS pr1,
            NULLIF(btrim(COALESCE("OC_Maximos".proveedor2, ''::text)), ''::text) AS proveedor2,
            COALESCE("OC_Maximos".prop_prov2, 0::numeric) AS pr2,
                CASE
                    WHEN COALESCE("OC_Maximos".indice, 0::numeric) > 0::numeric THEN "OC_Maximos".indice
                    ELSE 1.5
                END AS indice,
            COALESCE("OC_Maximos".activo, true) AS activo,
            COALESCE("OC_Maximos".llenar_gondola, false) AS llenar_gondola
           FROM "OC_Maximos"
          WHERE NULLIF(btrim("OC_Maximos".cod), ''::text) IS NOT NULL
          ORDER BY (regexp_replace(upper(btrim("OC_Maximos".cod)), '^0+(?=.)'::text, ''::text)), (COALESCE("OC_Maximos".activo, true)) DESC NULLS LAST
        ), pickeadas AS (
         SELECT DISTINCT upper(btrim("Registros_Produccion_Virgilio".texto)) AS tanda
           FROM "Registros_Produccion_Virgilio"
          WHERE "Registros_Produccion_Virgilio".opcion = 'TP'::text AND NULLIF(btrim(COALESCE("Registros_Produccion_Virgilio".texto, ''::text)), ''::text) IS NOT NULL
        ), pend_np AS (
         SELECT DISTINCT btrim(p.np) AS np
           FROM "PPP_Programacion_Diaria" p
          WHERE NOT (btrim(p.np) IN ( SELECT btrim("Facturacion_NP".np) AS btrim
                   FROM "Facturacion_NP")) AND NOT (upper(btrim(COALESCE(p.tanda, ''::text))) IN ( SELECT pickeadas.tanda
                   FROM pickeadas))
        ), dem_raw AS (
         SELECT regexp_replace(upper(btrim(b.articulo)), '^0+(?=.)'::text, ''::text) AS codn,
            sum(COALESCE(b.cajas, 0::numeric)) AS pedidos
           FROM gv_demanda_pedidos b
             JOIN pend_np n ON btrim(b.pedido) = n.np
          WHERE NULLIF(btrim(b.articulo), ''::text) IS NOT NULL
          GROUP BY (regexp_replace(upper(btrim(b.articulo)), '^0+(?=.)'::text, ''::text))
        ), dem AS (
         SELECT COALESCE(f.ppal, dr.codn) AS codn,
            sum(dr.pedidos) AS pedidos
           FROM dem_raw dr
             LEFT JOIN fam f ON f.sec = dr.codn
          GROUP BY (COALESCE(f.ppal, dr.codn))
        ), ncaja AS (
         SELECT DISTINCT ON (t.codn) t.codn,
            t.n_caja
           FROM ( SELECT regexp_replace(upper(btrim("Articulos_Cajas"."Cod_Art")), '^0+(?=.)'::text, ''::text) AS codn,
                    "Articulos_Cajas"."N_Caja" AS n_caja,
                    count(*) AS c
                   FROM "Articulos_Cajas"
                  WHERE "Articulos_Cajas"."N_Caja" IS NOT NULL
                  GROUP BY (regexp_replace(upper(btrim("Articulos_Cajas"."Cod_Art")), '^0+(?=.)'::text, ''::text)), "Articulos_Cajas"."N_Caja") t
          ORDER BY t.codn, t.c DESC, t.n_caja
        ), universo AS (
         SELECT stk.codn
           FROM stk
          WHERE stk.fin_dep > 0::numeric
        UNION
         SELECT proy.codn
           FROM proy
          WHERE proy.proy > 0::numeric
        UNION
         SELECT dem.codn
           FROM dem
        UNION
         SELECT cap.codn
           FROM cap
          WHERE cap.cap > 0::numeric
        UNION
         SELECT cfg.codn
           FROM cfg
        ), base AS (
         SELECT u.codn,
            COALESCE(c.cod_cfg, u.codn) AS cod,
            COALESCE(c.descripcion, s.descripcion) AS descripcion,
            c.linea,
            COALESCE(c.proveedor, '(sin proveedor)'::text) AS proveedor,
            c.proveedor IS NOT NULL AS tiene_prov_real,
            COALESCE(c.pr1, 100::numeric) AS pr1,
            c.proveedor2,
            COALESCE(c.pr2, 0::numeric) AS pr2,
            COALESCE(c.indice, 1.5) AS indice,
            COALESCE(c.activo, true) AS activo,
            c.codn IS NOT NULL AS en_config,
            COALESCE(c.llenar_gondola, false) AS llenar_gondola,
            COALESCE(s.stock, 0::numeric) AS stock,
            COALESCE(pr.proy, 0::numeric) AS proy,
            COALESCE(cp.cap, 0::numeric) AS cap,
            COALESCE(d.pedidos, 0::numeric) AS pedidos,
            COALESCE(ux.uni_x_caja, 0::numeric) AS uni_x_caja,
            nc.n_caja
           FROM universo u
             LEFT JOIN stk s ON s.codn = u.codn
             LEFT JOIN proy pr ON pr.codn = u.codn
             LEFT JOIN cap cp ON cp.codn = u.codn
             LEFT JOIN dem d ON d.codn = u.codn
             LEFT JOIN cfg c ON c.codn = u.codn
             LEFT JOIN ncaja nc ON nc.codn = u.codn
             LEFT JOIN vista_uni_x_caja ux ON ux.codn = u.codn
        ), conmax AS (
         SELECT b.codn,
            b.cod,
            b.descripcion,
            b.linea,
            b.proveedor,
            b.tiene_prov_real,
            b.pr1,
            b.proveedor2,
            b.pr2,
            b.indice,
            b.activo,
            b.en_config,
            b.llenar_gondola,
            b.stock,
            b.proy,
            b.cap,
            b.pedidos,
            b.uni_x_caja,
            b.n_caja,
                CASE
                    WHEN COALESCE(b.llenar_gondola, false) AND b.cap > 0::numeric THEN b.cap
                    WHEN b.proy > 0::numeric THEN LEAST(ceil(b.proy * b.indice), COALESCE(NULLIF(b.cap, 0::numeric), 1000000000::numeric))
                    WHEN b.tiene_prov_real THEN COALESCE(NULLIF(b.cap, 0::numeric), 0::numeric)
                    ELSE 0::numeric
                END AS maximo
           FROM base b
        )
 SELECT codn,
    cod,
    descripcion,
    linea,
    proveedor,
    tiene_prov_real,
    pr1,
    proveedor2,
    pr2,
    indice,
    activo,
    en_config,
    stock,
    proy,
    cap,
    pedidos,
    uni_x_caja,
    n_caja,
    maximo,
    GREATEST(0::numeric, ceil(maximo + pedidos - stock))::integer AS total,
    llenar_gondola
   FROM conmax cm
  WHERE NOT (EXISTS ( SELECT 1
           FROM fam f2
          WHERE f2.sec = cm.codn));
grant select on public.vista_generador_oc to anon, authenticated, service_role;

-- ############################################################################
-- 5) Verificacion
-- ############################################################################
-- select * from public.gv_endpoints_rotos;            -- vacio = nada roto
-- refresh materialized view concurrently public.vista_stock_procesada;
-- select count(*), count(distinct cod), sum(cajas_pedidas) from public.vista_stock_procesada;
--   -> 366 | 366 | 7409.66
--
-- Lo que NO se toco, a proposito: las 5 vistas de higiene de NP de ISIS
-- (vista_np_sin_programar, vista_np_prog_sin_base, vista_np_faltantes_secuencia,
-- vista_np_sucursal, gv_ppp_isis_sin_tanda) siguen leyendo "PPP_Base_Pedidos".
-- Esta bien: son diagnosticos sobre la numeracion de ISIS, y las NP web no
-- tienen numero de secuencia de ISIS.
