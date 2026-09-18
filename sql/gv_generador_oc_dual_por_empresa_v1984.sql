-- ============================================================================
-- v19.84 — LO QUE SE PIDE POR OC VA CON EL CÓDIGO DE EMPRESA (problema 430)
--
-- Thomas, 2026-09-18: *"LO QUE SE PIDE POR OCs TIENE QUE SER LOS CODIGOS CON EMPRESA.
-- Considera que esos codigos viajan en todos lados con el codigo de empresa y ese se tiene
-- que usar en las ordenes de compra para saber cual se esta comprando"*.
--
-- ANTES: los 4 códigos DUALES (437E, 438E, 439E, 809E) salían en UNA fila con el stock, la
-- capacidad, la proyección y los pedidos de las DOS empresas sumados. La OC decía "437E" y
-- no se sabía si se compraba el de Loeke o el de Chef. Peor: el stock de una empresa TAPABA
-- el faltante de la otra.
--
-- AHORA: un dual sale en DOS filas, `437E LK` y `437E CH`, cada una con lo suyo. La fila
-- pelada ya no existe, así que no hay línea de OC ambigua.
--
--   | de dónde sale cada cosa | cómo se parte |
--   |---|---|
--   | stock     | `vista_saldos_stock.clave` (ya viene partida: "437E LK" / "437E CH") |
--   | capacidad | `Capacidad_Sector.empresa` (con `LOKE` → `LK`: así están Ñ53 y Ñ54 del 439E) |
--   | proyección| la razón `proyeccion_madre.proy_cajas_lk` / `proy_cajas_chef` aplicada al total, para que la suma de las dos dé EXACTO lo de antes |
--   | pedidos   | la empresa de la NP (`gv_empresa_de_np_texto`), con la regla de la "L" (438EL → LK) |
--   | descripción | `codigos_duales.nombre_lk` / `nombre_ch` si están cargados (el 809E los tiene: Corta Pizza Familiar / Corta Queso) |
--   | config (proveedor, %, índice, uni×caja, activo, objetivo) | **una sola, la del código pelado** en `OC_Maximos`. Las dos mitades comparten proveedor: es el mismo que fabrica los dos. Por eso la vista devuelve la columna nueva `cod_config`, que es a quién hay que escribirle desde la pantalla Config. |
--
-- MEDIDO contra el estado anterior (snapshot en
-- zz_backups."GV_Backup_GeneradorOC_antes_20260918"):
--
--   · filas 404 → 408 (se van las 4 peladas, entran las 8 mitades)
--   · **0 códigos NO duales cambiaron** — ni una fila, ni un número
--   · total a pedir de los activos: 10.307 → 10.632 (+325, todo de los duales)
--   · y las sumas cierran: stock 14+290 = 304 · cap 48+120 = 168 · pedidos 0+12 = 12 ·
--     proyección 69,82+27,93 = 97,75 (el total exacto de antes)
--
--   | código | antes | ahora |
--   |---|---|---|
--   | 437E | total **0** (304 de stock contra 196 de máximo) | **CH pide 126** (14 de stock, máximo 140) · LK 0 (290 de stock) |
--   | 438E | total 10 | **CH 86** (3 de stock) · LK 0 (119) |
--   | 439E | total 7 | CH 4 · LK 3 |
--   | 809E | total 0 (463 de stock) | **CH 123** (113 de stock) · LK 0 (350) — sin proveedor, así que no entra a ninguna OC |
--
-- O sea que la vista agregada estaba ESCONDIENDO faltantes reales: había 304 coladores 16cm
-- pero casi todos de Loeke, Chef estaba en 14 y el sistema decía "no pidas nada".
--
-- ⚠ LO QUE FALTA, y es la parte de abajo de la cadena: cuando llega la mercadería, la OC se
-- descuenta en `gv_oc_recompute_recibido`, que cruza `Entregas Tallerista Virgilio."Cod"`
-- (código PELADO, la tabla no tiene empresa) contra `norm_cod(Ordenes_Compra.codigo)`. Con la
-- OC de un dual ahora escrita "437E CH", ese cruce NO matchea: la OC no se cierra sola y el
-- aviso de "SIN OC generada" / "entrega ajena" puede saltar de más. Hay que agregarle a esa
-- tabla una columna de empresa (nullable, `gv_`), que recepcion.js ya sabe (opState.linea), y
-- hacer empresa-aware `gv_oc_recompute_recibido` y `gv_oc_entrega_ajena`. Hasta entonces, una
-- OC de un dual hay que marcarla recibida a mano en el módulo de OCs.
--
-- ROLLBACK: la definición anterior COMPLETA quedó guardada en
-- zz_backups."GV_Backup_VistaGeneradorOC_def_20260918" (columna `definicion`, 11.596 chars,
-- con sus reloptions). Se recrea con `create or replace view public.vista_generador_oc with
-- (security_invoker = true) as <definicion>`. Ojo: eso saca la columna `cod_config`, así que
-- hay que volver también el front (index.html) a la v19.79.
--
-- Centinela: fila en GV_Reglas_Centinela (el patrón `codigos_duales` tiene que seguir en la
-- vista, o los duales vuelven a salir sumados en una sola línea de OC).
-- ============================================================================

create or replace view public.vista_generador_oc with (security_invoker = true) as
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
          GROUP BY 1, 2
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
          WHERE sr.emp IS NOT NULL AND (EXISTS ( SELECT 1 FROM dual dd WHERE dd.codn = COALESCE(f.ppal, sr.codn)))
          GROUP BY 1, 2
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
          GROUP BY 1, 2
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
         SELECT regexp_replace(upper(btrim(b.articulo)), '^0+(?=.)'::text, ''::text) AS codn,
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
          GROUP BY 1, 2
        ), dem AS (
         SELECT COALESCE(f.ppal, dr.codn) AS codn,
            sum(dr.pedidos) AS pedidos
           FROM dem_raw dr
             LEFT JOIN fam f ON f.sec = dr.codn
          GROUP BY (COALESCE(f.ppal, dr.codn))
        ), dem_e AS (
         SELECT COALESCE(f.ppal, dr.codn) AS codn,
            COALESCE(
                CASE WHEN f.ppal IS NOT NULL THEN f.empresa ELSE NULL::text END,
                dr.emp) AS emp,
            sum(dr.pedidos) AS pedidos
           FROM dem_raw dr
             LEFT JOIN fam f ON f.sec = dr.codn
          WHERE (EXISTS ( SELECT 1 FROM dual dd WHERE dd.codn = COALESCE(f.ppal, dr.codn)))
          GROUP BY 1, 2
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
         SELECT u.codn, e.emp
           FROM universo u
             JOIN dual dd ON dd.codn = u.codn
             CROSS JOIN ( VALUES ('LK'::text), ('CH'::text)) e(emp)
        UNION ALL
         SELECT u.codn, NULL::text AS emp
           FROM universo u
          WHERE NOT (EXISTS ( SELECT 1 FROM dual dd WHERE dd.codn = u.codn))
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
                    WHEN u.emp IS NULL THEN COALESCE(s.stock, 0::numeric)
                    ELSE COALESCE(se.stock, 0::numeric)
                END AS stock,
                CASE
                    WHEN u.emp IS NULL THEN COALESCE(pr.proy, 0::numeric)
                    WHEN COALESCE(pr.p_lk, 0::numeric) + COALESCE(pr.p_ch, 0::numeric) > 0::numeric
                    THEN COALESCE(pr.proy, 0::numeric) * (
                        CASE WHEN u.emp = 'LK'::text THEN COALESCE(pr.p_lk, 0::numeric) ELSE COALESCE(pr.p_ch, 0::numeric) END
                        / (COALESCE(pr.p_lk, 0::numeric) + COALESCE(pr.p_ch, 0::numeric)))
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
          WHERE f2.sec = cm.codn_base)) AND cm.codn_base <> 'LIBRE'::text;
