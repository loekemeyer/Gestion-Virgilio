-- v11.81 — Casilla "llenar góndola" por artículo en el generador de OCs.
--
-- PROBLEMA: máximo = MENOR(proy×índice, capacidad). La capacidad de góndola
-- (Capacidad_Sector) solo actuaba de TECHO. Cuando la proyección es baja, la
-- orden sale de muy pocas cajas aunque la góndola sea grande (ej. Martín C.:
-- 043 Tres en Uno → proy 2 × 1.5 = 3 máx, con góndola de 180 cajas).
--
-- SOLUCIÓN: nueva columna OC_Maximos.llenar_gondola (bool, default false). En
-- los artículos tildados, máximo = capacidad de góndola (llena la góndola),
-- ignorando proy×índice. El resto sigue igual. El operario elige uno por uno
-- desde la config de OCs (⚙ Configuraciones).
--
-- Backend = fuente de verdad: el cron (generar_ocs_automaticas) y el front leen
-- vista_generador_oc, así que ambos reflejan la casilla sin tocar el front.
--
-- ROLLBACK vista: el def anterior está en sql/vista_generador_oc.sql / el
-- backup de abajo. Para revertir la columna:
--   alter table "OC_Maximos" drop column llenar_gondola;
--   (y recrear la vista sin la primera rama del CASE de "maximo").

-- 1) Columna nueva (additiva, no toca datos existentes).
alter table public."OC_Maximos"
  add column if not exists llenar_gondola boolean not null default false;

-- 2) Vista con la casilla aplicada en el cálculo del máximo.
create or replace view public.vista_generador_oc as
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
                CASE
                    WHEN max(proyeccion_madre.uxb) > 0 THEN sum(COALESCE(proyeccion_madre.proy_uni_mes, 0::numeric)) / max(proyeccion_madre.uxb)::numeric
                    ELSE max(COALESCE(proyeccion_madre.proy_cajas_mes, 0::numeric))
                END AS proy
           FROM proyeccion_madre
          WHERE btrim(proyeccion_madre.cod) ~ '^[0-9]'::text
          GROUP BY (regexp_replace(regexp_replace(regexp_replace(upper(btrim(proyeccion_madre.cod)), '^0+(?=.)'::text, ''::text), 'L$'::text, ''::text), '^546E$'::text, '546'::text))
        ), proy AS (
         SELECT COALESCE(f.ppal, pr.codn) AS codn,
            sum(pr.proy) AS proy
           FROM proy_raw pr
             LEFT JOIN fam f ON f.sec = pr.codn
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
           FROM "PPP_Base_Pedidos" b
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
