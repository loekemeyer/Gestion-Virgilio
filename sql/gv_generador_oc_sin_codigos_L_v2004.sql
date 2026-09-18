-- ============================================================================
-- v20.04 — LOS CÓDIGOS CON "L" NO SON ARTÍCULOS: NO VAN AL GENERADOR DE OC
--
-- Thomas, 2026-09-18 (video del Generador de OC): *"Todos los que tienen L no deben aparecer
-- para OC. Son para Loeke y nada más"*.
--
-- ## El síntoma
--
-- El Generador de OC listaba **53 filas fantasma** — `505L`, `513L`, `584EL`, `438EL`… — todas
-- con **(sin proveedor)**, sin descripción, `proy = 0`, `cap = 0`, `stock = 0`, `maximo = 0` y
-- un `total` igual a los pedidos. O sea: 53 renglones que pedían mercadería a nadie.
--
-- ## Qué es una "L" y por qué no es un artículo
--
-- Regla del dueño v13.71: un artículo de Loekemeyer vendido por la página de **Chef** viaja con
-- **"L" al final** (505 → 505L, 438E → 438EL). La L es una **marca de ruteo** — dice que esa
-- caja se pickea de la góndola de Loeke y que la factura sale por Chef. **El artículo es el
-- mismo**: no hay un 505L que comprarle a un proveedor, no tiene góndola propia, no tiene
-- proyección propia y no tiene stock propio.
--
-- Medido el 18/09: **ninguna** de las tablas del lado físico conoce un código con L —
-- `Articulos_Cajas` 0, `GV_UxB` 0, `OC_Maximos` 0, `Capacidad_Sector` 0, `Movimientos_Stock` 0,
-- `Equivalencias_Familia` 0. Sólo aparece en `proyeccion_madre` (que la vista ya pelaba) y en
-- `gv_demanda_pedidos` (que no).
--
-- ## La causa
--
-- De las cinco patas del universo de la vista, **cuatro ya pelaban la L** y una no:
--
--   | CTE | pelaba la L |
--   |---|---|
--   | `fam` (Equivalencias_Familia) | sí — `'L$'` |
--   | `proy_raw` (proyección) | sí — `'L$'` |
--   | `stk_raw` (stock) | no hace falta: no hay stock con L |
--   | `cap` (capacidad) | no hace falta: no hay góndola con L |
--   | **`dem_raw` (pedidos)** | **NO** ← acá estaba el agujero |
--
-- Así que la demanda de un pedido de Chef con artículo de Loeke se iba a un código propio que
-- nunca iba a tener ni stock ni proveedor que lo cubriera — y, peor, **se la robaba al código
-- base**, que es el que de verdad hay que comprar. La resta del generador
-- (`total = maximo + pedidos − stock`) quedaba corta en el código real. Es el mismo tipo de
-- error que la v19.85: un hecho que un lado cuenta y el otro no.
--
-- ## El arreglo, una línea
--
-- `dem_raw` pasa a keyear con **`gv_cod_stock(b.articulo)`** — la función canónica, que ya
-- pela `([0-9E])L$` además de los ceros, el sufijo de empresa y el `·…`. No se toca el `CASE`
-- de `emp`, que sigue leyendo el artículo CRUDO (`'[0-9E]L$'` → `'LK'`): así un `438EL` cae en
-- la mitad **`438E LK`**, que es donde se pickea (regla v13.71).
--
-- ⚠ No es "esconder las filas": la demanda **se muda al código base**. Esconderlas habría
-- borrado pedidos reales de la cuenta y se compraría de menos, justo al revés de la regla del
-- 18/09 (*"proyección es siempre rey… tenemos que tener la mercadería que hace falta"*).
--
-- ## Qué cambió, medido contra el snapshot previo
--
--   | | |
--   |---|---|
--   | filas | 408 → **355** (−53, todas las L) |
--   | filas con código terminado en L | 53 → **0** |
--   | filas nuevas | **0** |
--   | códigos que suben el "a pedir" | **35** |
--   | códigos que bajan | **0** |
--   | total a pedir | 11.259 → **11.230** cajas |
--
-- Las 81 cajas que estaban en las filas L se mudaron a su código base; 29 las absorbió el stock
-- que ese código base ya tenía, que es exactamente lo que tenía que pasar. Los que más suben:
-- 505 Pelador Plástico +4 (Garcia), 584E Aceitera 400 Ml +4 (Garcia), 502 Abrelatas Mariposa +3
-- (Poly), 506 Abrelata Uña +3 (Oscar). Y `439E LK` +1, que prueba el camino del dual.
--
-- Backup: `zz_backups."GV_Backup_VistaGeneradorOC_20260918"` (la definición vieja completa) y
-- `zz_backups."GV_Backup_VistaGeneradorOC_filas_20260918"` (las 408 filas de antes).
--
-- Rollback: `create or replace view public.vista_generador_oc as <definicion del backup>;`
-- más `alter view public.vista_generador_oc set (security_invoker = true);`
-- ============================================================================

-- Definición VIVA completa, tal como la devuelve pg_get_viewdef después del cambio.
-- (La v19.85 se había aplicado como replace() sobre la definición viva, así que el repo tenía
--  la de la v19.84 y ya no coincidía. Acá queda el CREATE entero, como pide el CLAUDE.md.)

create or replace view public.vista_generador_oc as
 WITH dual AS (
         SELECT regexp_replace(upper(btrim(d.cod)), '^0+(?=.)'::text, ''::text) AS codn,
            NULLIF(btrim(d.nombre_lk), ''::text) AS nombre_lk,
            NULLIF(btrim(d.nombre_ch), ''::text) AS nombre_ch
           FROM codigos_duales d
        ), fam AS (
         SELECT regexp_replace(regexp_replace(regexp_replace(upper(btrim("Equivalencias_Familia".cod_secundario)), '^0+(?=.)'::text, ''::text), 'L$'::text, ''::text), '^546E$'::text, '546'::text) AS sec,
            regexp_replace(regexp_replace(regexp_replace(upper(btrim("Equivalencias_Familia".cod_principal)), '^0+(?=.)'::text, ''::text), 'L$'::text, ''::text), '^546E$'::text, '546'::text) AS ppal,
                CASE
                    WHEN upper(btrim(COALESCE("Equivalencias_Familia".empresa, ''::text))) = 'CH'::text THEN 'CH'::text
                    WHEN upper(btrim(COALESCE("Equivalencias_Familia".empresa, ''::text))) = ANY (ARRAY['LK'::text, 'LOKE'::text]) THEN 'LK'::text
                    ELSE NULL::text
                END AS empresa
           FROM "Equivalencias_Familia"
        ), stk_raw AS (
         SELECT regexp_replace(regexp_replace(regexp_replace(upper(btrim(vista_saldos_stock.cod_art)), '^0+(?=.)'::text, ''::text), ' +(LK|CH)$'::text, ''::text), '·.*$'::text, ''::text) AS codn,
                CASE
                    WHEN upper(btrim(vista_saldos_stock.clave)) ~ ' +CH$'::text THEN 'CH'::text
                    WHEN upper(btrim(vista_saldos_stock.clave)) ~ ' +(LK|LOKE)$'::text THEN 'LK'::text
                    WHEN upper(btrim(COALESCE(vista_saldos_stock.empresa, ''::text))) = 'CH'::text THEN 'CH'::text
                    WHEN upper(btrim(COALESCE(vista_saldos_stock.empresa, ''::text))) = ANY (ARRAY['LK'::text, 'LOKE'::text]) THEN 'LK'::text
                    ELSE NULL::text
                END AS emp,
            sum(COALESCE(vista_saldos_stock.terminado, 0::numeric) + COALESCE(vista_saldos_stock.a_guardar, 0::numeric) + COALESCE(vista_saldos_stock.racks, 0::numeric) + COALESCE(vista_saldos_stock.excedente, 0::numeric) + COALESCE(vista_saldos_stock.separar_pedidos, 0::numeric) + COALESCE(vista_saldos_stock.a_facturar, 0::numeric) + COALESCE(vista_saldos_stock.para_envasar, 0::numeric) + COALESCE(vista_saldos_stock.racks_ch, 0::numeric)) AS stock,
            sum(COALESCE(vista_saldos_stock.terminado, 0::numeric) + COALESCE(vista_saldos_stock.a_guardar, 0::numeric) + COALESCE(vista_saldos_stock.racks, 0::numeric) + COALESCE(vista_saldos_stock.excedente, 0::numeric) + COALESCE(vista_saldos_stock.para_envasar, 0::numeric) + COALESCE(vista_saldos_stock.racks_ch, 0::numeric)) AS fin_dep,
            max(vista_saldos_stock.descripcion) AS descripcion
           FROM vista_saldos_stock
          GROUP BY (regexp_replace(regexp_replace(regexp_replace(upper(btrim(vista_saldos_stock.cod_art)), '^0+(?=.)'::text, ''::text), ' +(LK|CH)$'::text, ''::text), '·.*$'::text, ''::text)), (
                CASE
                    WHEN upper(btrim(vista_saldos_stock.clave)) ~ ' +CH$'::text THEN 'CH'::text
                    WHEN upper(btrim(vista_saldos_stock.clave)) ~ ' +(LK|LOKE)$'::text THEN 'LK'::text
                    WHEN upper(btrim(COALESCE(vista_saldos_stock.empresa, ''::text))) = 'CH'::text THEN 'CH'::text
                    WHEN upper(btrim(COALESCE(vista_saldos_stock.empresa, ''::text))) = ANY (ARRAY['LK'::text, 'LOKE'::text]) THEN 'LK'::text
                    ELSE NULL::text
                END)
        ), stk AS (
         SELECT COALESCE(f.ppal, sr.codn) AS codn,
            sum(sr.stock) AS stock,
            sum(sr.fin_dep) AS fin_dep,
            max(sr.descripcion) AS descripcion
           FROM stk_raw sr
             LEFT JOIN fam f ON f.sec = sr.codn
          GROUP BY (COALESCE(f.ppal, sr.codn))
        ), stk_e AS (
         SELECT COALESCE(f.ppal, sr.codn) AS codn,
            sr.emp,
            sum(sr.stock) AS stock,
            sum(sr.fin_dep) AS fin_dep
           FROM stk_raw sr
             LEFT JOIN fam f ON f.sec = sr.codn
          WHERE sr.emp IS NOT NULL AND (EXISTS ( SELECT 1
                   FROM dual dd
                  WHERE dd.codn = COALESCE(f.ppal, sr.codn)))
          GROUP BY (COALESCE(f.ppal, sr.codn)), sr.emp
        ), proy_raw AS (
         SELECT regexp_replace(regexp_replace(regexp_replace(upper(btrim(proyeccion_madre.cod)), '^0+(?=.)'::text, ''::text), 'L$'::text, ''::text), '^546E$'::text, '546'::text) AS codn,
            sum(COALESCE(proyeccion_madre.proy_uni_mes, 0::numeric)) AS uni,
            max(COALESCE(proyeccion_madre.proy_cajas_mes, 0::numeric)) AS cajas,
            sum(COALESCE(proyeccion_madre.proy_cajas_lk, 0::numeric)) AS p_lk,
            sum(COALESCE(proyeccion_madre.proy_cajas_chef, 0::numeric)) AS p_ch
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
                END) AS proy,
            sum(pr.p_lk) AS p_lk,
            sum(pr.p_ch) AS p_ch
           FROM proy_raw pr
             LEFT JOIN fam f ON f.sec = pr.codn
             LEFT JOIN gux gx ON gx.c = pr.codn
          GROUP BY (COALESCE(f.ppal, pr.codn))
        ), cap AS (
         SELECT regexp_replace(upper(btrim("Capacidad_Sector".cod)), '^0+(?=.)'::text, ''::text) AS codn,
            sum(COALESCE("Capacidad_Sector".cajas_max, 0::numeric)) AS cap
           FROM "Capacidad_Sector"
          WHERE upper(btrim(COALESCE("Capacidad_Sector".cod, ''::text))) <> 'LIBRE'::text
          GROUP BY (regexp_replace(upper(btrim("Capacidad_Sector".cod)), '^0+(?=.)'::text, ''::text))
        ), cap_e AS (
         SELECT regexp_replace(upper(btrim(c.cod)), '^0+(?=.)'::text, ''::text) AS codn,
                CASE
                    WHEN upper(btrim(COALESCE(c.empresa, ''::text))) = 'CH'::text THEN 'CH'::text
                    WHEN upper(btrim(COALESCE(c.empresa, ''::text))) = ANY (ARRAY['LK'::text, 'LOKE'::text]) THEN 'LK'::text
                    ELSE NULL::text
                END AS emp,
            sum(COALESCE(c.cajas_max, 0::numeric)) AS cap
           FROM "Capacidad_Sector" c
          WHERE upper(btrim(COALESCE(c.cod, ''::text))) <> 'LIBRE'::text
          GROUP BY (regexp_replace(upper(btrim(c.cod)), '^0+(?=.)'::text, ''::text)), (
                CASE
                    WHEN upper(btrim(COALESCE(c.empresa, ''::text))) = 'CH'::text THEN 'CH'::text
                    WHEN upper(btrim(COALESCE(c.empresa, ''::text))) = ANY (ARRAY['LK'::text, 'LOKE'::text]) THEN 'LK'::text
                    ELSE NULL::text
                END)
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
           FROM "GV_PPP_Programacion_Diaria" p
          WHERE NOT (btrim(p.np) IN ( SELECT btrim("Facturacion_NP".np) AS btrim
                   FROM "Facturacion_NP")) AND NOT (upper(btrim(COALESCE(p.tanda, ''::text))) IN ( SELECT pickeadas.tanda
                   FROM pickeadas))
        UNION
         SELECT DISTINCT gv_ppp_web_np_label(w.empresa, w.np, w.np_idx) AS np
           FROM "PPP_Web_Programacion" w
          WHERE NOT (gv_ppp_web_np_label(w.empresa, w.np, w.np_idx) IN ( SELECT btrim("Facturacion_NP".np) AS btrim
                   FROM "Facturacion_NP")) AND NOT (upper(btrim(COALESCE(w.tanda, ''::text))) IN ( SELECT pickeadas.tanda
                   FROM pickeadas)) AND NOT (EXISTS ( SELECT 1
                   FROM "GV_Web_Cancelados" wc
                  WHERE wc.np_label = gv_ppp_web_np_label(w.empresa, w.np, w.np_idx)))
        ), dem_raw AS (
         SELECT gv_cod_stock(b.articulo) AS codn,
                CASE
                    WHEN upper(btrim(b.articulo)) ~ '[0-9E]L$'::text THEN 'LK'::text
                    WHEN gv_empresa_de_np_texto(btrim(b.pedido)) = 'chef'::text THEN 'CH'::text
                    WHEN gv_empresa_de_np_texto(btrim(b.pedido)) = 'lk'::text THEN 'LK'::text
                    ELSE NULL::text
                END AS emp,
            sum(COALESCE(b.cajas, 0::numeric)) AS pedidos
           FROM gv_demanda_pedidos b
             JOIN pend_np n ON btrim(b.pedido) = n.np
          WHERE NULLIF(btrim(b.articulo), ''::text) IS NOT NULL
          GROUP BY (gv_cod_stock(b.articulo)), (
                CASE
                    WHEN upper(btrim(b.articulo)) ~ '[0-9E]L$'::text THEN 'LK'::text
                    WHEN gv_empresa_de_np_texto(btrim(b.pedido)) = 'chef'::text THEN 'CH'::text
                    WHEN gv_empresa_de_np_texto(btrim(b.pedido)) = 'lk'::text THEN 'LK'::text
                    ELSE NULL::text
                END)
        ), dem AS (
         SELECT COALESCE(f.ppal, dr.codn) AS codn,
            sum(dr.pedidos) AS pedidos
           FROM dem_raw dr
             LEFT JOIN fam f ON f.sec = dr.codn
          GROUP BY (COALESCE(f.ppal, dr.codn))
        ), dem_e AS (
         SELECT COALESCE(f.ppal, dr.codn) AS codn,
            COALESCE(
                CASE
                    WHEN f.ppal IS NOT NULL THEN f.empresa
                    ELSE NULL::text
                END, dr.emp) AS emp,
            sum(dr.pedidos) AS pedidos
           FROM dem_raw dr
             LEFT JOIN fam f ON f.sec = dr.codn
          WHERE (EXISTS ( SELECT 1
                   FROM dual dd
                  WHERE dd.codn = COALESCE(f.ppal, dr.codn)))
          GROUP BY (COALESCE(f.ppal, dr.codn)), (COALESCE(
                CASE
                    WHEN f.ppal IS NOT NULL THEN f.empresa
                    ELSE NULL::text
                END, dr.emp))
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
        ), nom_ux AS (
         SELECT DISTINCT ON ((gv_cod_stock(u.cod))) gv_cod_stock(u.cod) AS codn,
            btrim(u.descripcion) AS descripcion
           FROM "GV_UxB" u
          WHERE NULLIF(btrim(COALESCE(u.descripcion, ''::text)), ''::text) IS NOT NULL
          ORDER BY (gv_cod_stock(u.cod)), (COALESCE(u.curado, false)) DESC, u.actualizado DESC NULLS LAST
        ), nom_ac AS (
         SELECT DISTINCT ON ((regexp_replace(upper(btrim(a."Cod_Art")), '^0+(?=.)'::text, ''::text))) regexp_replace(upper(btrim(a."Cod_Art")), '^0+(?=.)'::text, ''::text) AS codn,
            btrim(a."Descripcion") AS descripcion
           FROM "Articulos_Cajas" a
          WHERE NULLIF(btrim(COALESCE(a."Descripcion", ''::text)), ''::text) IS NOT NULL
          ORDER BY (regexp_replace(upper(btrim(a."Cod_Art")), '^0+(?=.)'::text, ''::text)), (COALESCE(a."Suspendido", false)), a.id DESC
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
        ), universo_e AS (
         SELECT u.codn,
            e.emp
           FROM universo u
             JOIN dual dd ON dd.codn = u.codn
             CROSS JOIN ( VALUES ('LK'::text), ('CH'::text)) e(emp)
        UNION ALL
         SELECT u.codn,
            NULL::text AS emp
           FROM universo u
          WHERE NOT (EXISTS ( SELECT 1
                   FROM dual dd
                  WHERE dd.codn = u.codn))
        ), base AS (
         SELECT u.codn AS codn_base,
            u.emp,
            COALESCE(c.cod_cfg, u.codn) AS cod_config,
                CASE
                    WHEN u.emp IS NULL THEN COALESCE(c.cod_cfg, u.codn)
                    ELSE (COALESCE(c.cod_cfg, u.codn) || ' '::text) || u.emp
                END AS cod,
            COALESCE(
                CASE
                    WHEN u.emp = 'LK'::text THEN dd.nombre_lk
                    WHEN u.emp = 'CH'::text THEN dd.nombre_ch
                    ELSE NULL::text
                END, c.descripcion, s.descripcion, nx.descripcion, na.descripcion) AS descripcion,
            COALESCE(u.emp, c.linea) AS linea,
            COALESCE(c.proveedor, '(sin proveedor)'::text) AS proveedor,
            c.proveedor IS NOT NULL AS tiene_prov_real,
            COALESCE(c.pr1, 100::numeric) AS pr1,
            c.proveedor2,
            COALESCE(c.pr2, 0::numeric) AS pr2,
            COALESCE(c.indice, 1.5) AS indice,
            COALESCE(c.activo, true) AS activo,
            c.codn IS NOT NULL AS en_config,
            COALESCE(c.llenar_gondola, false) AS llenar_gondola,
                CASE
                    WHEN u.emp IS NULL THEN COALESCE(s.fin_dep, 0::numeric)
                    ELSE COALESCE(se.fin_dep, 0::numeric)
                END AS stock,
                CASE
                    WHEN u.emp IS NULL THEN COALESCE(pr.proy, 0::numeric)
                    WHEN (COALESCE(pr.p_lk, 0::numeric) + COALESCE(pr.p_ch, 0::numeric)) > 0::numeric THEN COALESCE(pr.proy, 0::numeric) * (
                    CASE
                        WHEN u.emp = 'LK'::text THEN COALESCE(pr.p_lk, 0::numeric)
                        ELSE COALESCE(pr.p_ch, 0::numeric)
                    END / (COALESCE(pr.p_lk, 0::numeric) + COALESCE(pr.p_ch, 0::numeric)))
                    ELSE 0::numeric
                END AS proy,
                CASE
                    WHEN u.emp IS NULL THEN COALESCE(cp.cap, 0::numeric)
                    ELSE COALESCE(ce.cap, 0::numeric)
                END AS cap,
                CASE
                    WHEN u.emp IS NULL THEN COALESCE(d.pedidos, 0::numeric)
                    ELSE COALESCE(de.pedidos, 0::numeric)
                END AS pedidos,
            COALESCE(ux.uni_x_caja, 0::numeric) AS uni_x_caja,
            nc.n_caja
           FROM universo_e u
             LEFT JOIN dual dd ON dd.codn = u.codn
             LEFT JOIN stk s ON s.codn = u.codn
             LEFT JOIN stk_e se ON se.codn = u.codn AND se.emp = u.emp
             LEFT JOIN proy pr ON pr.codn = u.codn
             LEFT JOIN cap cp ON cp.codn = u.codn
             LEFT JOIN cap_e ce ON ce.codn = u.codn AND ce.emp = u.emp
             LEFT JOIN dem d ON d.codn = u.codn
             LEFT JOIN dem_e de ON de.codn = u.codn AND de.emp = u.emp
             LEFT JOIN cfg c ON c.codn = u.codn
             LEFT JOIN ncaja nc ON nc.codn = u.codn
             LEFT JOIN vista_uni_x_caja ux ON ux.codn = u.codn
             LEFT JOIN nom_ux nx ON nx.codn = u.codn
             LEFT JOIN nom_ac na ON na.codn = u.codn
        ), conmax AS (
         SELECT b.codn_base,
            b.emp,
                CASE
                    WHEN b.emp IS NULL THEN b.codn_base
                    ELSE (b.codn_base || ' '::text) || b.emp
                END AS codn,
            b.cod,
            b.cod_config,
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
                    WHEN b.proy > 0::numeric THEN ceil(b.proy * b.indice)
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
    llenar_gondola,
    cod_config
   FROM conmax cm
  WHERE NOT (EXISTS ( SELECT 1
           FROM fam f2
          WHERE f2.sec = cm.codn_base)) AND codn_base <> 'LIBRE'::text;

alter view public.vista_generador_oc set (security_invoker = true);   -- NUNCA olvidarlo

-- centinela, para que la regla no se pierda en el próximo CREATE OR REPLACE
insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
values ('vista_generador_oc','vista','gv_cod_stock\(b\.articulo\)',
 'La demanda del generador de OC se keyea con gv_cod_stock, que pela la "L": un 505L no es un articulo, es un 505 de Loeke vendido por Chef. Ningun codigo con L puede aparecer en el Generador de OC.',
 'Thomas','v20.04')
on conflict do nothing;

-- CHEQUEOS
select count(*) from public.vista_generador_oc where cod ~ 'L$';  -- 0
select relname, reloptions from pg_class where oid='public.vista_generador_oc'::regclass;  -- security_invoker=true
select * from public.gv_reglas_perdidas;    -- vacía
select * from public.gv_endpoints_rotos;    -- vacía
