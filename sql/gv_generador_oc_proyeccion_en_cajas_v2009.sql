-- ============================================================================
-- v20.09 — LA PROYECCIÓN DEL GENERADOR DE OC SALE EN CAJAS, NO SE RECALCULA
--
-- Thomas, 2026-09-18: *"706 tiene proveedor, necesita pedir stock, no generó OCs"*.
--
-- ## El síntoma
--
-- El **706** (Abrelatas Uñas, proveedor Martin C) no aparecía en el Generador de OC. No es que
-- faltara la fila: estaba, con **`total = 0`**, así que la pantalla no la muestra porque no hay
-- nada que pedir. Y el `total` daba 0 porque la **proyección** que usaba el generador era
-- **16,75 cj/mes** — mientras el módulo **Stocks**, para el mismo artículo, mostraba **201**.
--
-- Dos pantallas, el mismo artículo, dos proyecciones que se llevan un factor de 12.
--
-- ## La causa: dos fuentes para el mismo número
--
-- `proyeccion_madre` tiene las dos formas del dato: `proy_uni_mes` (unidades) y
-- `proy_cajas_mes` (cajas). **Stocks lee `proy_cajas_mes`. El generador no: recalculaba**
-- `proy_uni_mes / uxb`, con el `uxb` de `GV_UxB`.
--
-- Mientras las dos puntas coinciden da igual. Pero el motor de proyección de LK, para los
-- códigos que no tiene con `uxb`, escribe las **cajas en las dos columnas**:
--
--   | cod | proy_uni_mes | proy_cajas_mes | uxb | uni/uxb |
--   |---|---|---|---|---|
--   | 505 | 27.854 | 2.321,17 | 12 | 2.321,17 ✔ |
--   | 505L | 254 | 21,17 | 12 | 21,17 ✔ |
--   | **706** | **201** | **201,00** | **12** | **16,75** ✘ |
--
-- Y no es un caso aislado: medido el 18/09, **119 de 333 códigos** discrepaban, casi todos de
-- la línea de **Chef** (7xx / 8xx / 9xx: 706, 713, 836, 840, 701, 824, 798E, 702E, 901, 847,
-- 802…). Sumados, el generador proyectaba **20.281,85 cj/mes** contra las **22.305,87** de
-- `proyeccion_madre`: **~2.000 cajas/mes de menos**, siempre para el lado de comprar de menos.
--
-- ## El arreglo
--
-- La proyección del generador pasa a ser **`sum(proy_cajas_mes)`**, el mismo número que muestra
-- Stocks y el mismo que suma la tabla madre. El CTE `gux` (que traía el `uxb` sólo para esta
-- cuenta) se va: ya no hay una segunda fuente que pueda derivar.
--
-- ⚠ Además se cambió `max(proy_cajas_mes)` por **`sum`** en `proy_raw`. Es el mismo agrupado
-- que ya hacía la columna de unidades: el código base y su gemelo con **"L"** son dos tajadas
-- de la misma proyección (505 = 2.321,17 LK + 21,17 CH = **2.342,34**, que es el número que el
-- CLAUDE.md cita para el 505). Con `max` el 546 se comía la tajada del 546E.
--
-- > **La regla que queda:** la proyección en cajas es `proy_cajas_mes`. Nadie la recalcula.
-- > Si un número de proyección hay que mostrarlo, sale de ahí.
--
-- ## Qué cambió, medido contra el snapshot previo (que ya tenía la v20.08)
--
--   | | |
--   |---|---|
--   | filas | 355 → **356** (entra el 228, 1 caja) |
--   | códigos que suben el "a pedir" | **53** |
--   | códigos que bajan | **4** |
--   | total a pedir | 11.230 → **12.477** cajas (**+1.247**) |
--   | proyección total de la vista | 20.281,85 → **22.278,87** cj/mes |
--
-- La proyección de la vista ahora cierra contra `proyeccion_madre` (22.305,87) salvo **27,00
-- cajas** que son 4 filas que NO son artículos y el filtro `cod ~ '^[0-9]'` saca a propósito:
-- `E` (26,67), `GASTOTRRECH`, `TRANSFRECH` y `ANTICIPO VTA MERCAERIA`.
--
-- **El 706**: proy 16,75 → **201**, máximo `ceil(201 × 2,5)` = **503**, y con 136 de stock y 14
-- pedidos pasa a pedir **381 cajas**. Antes: 0.
--
-- ⚠ **Las 4 bajas, y por qué no son un error.** Tres (618 Espátula Repost, 631 Espumadera, 857
-- Cuchillo De Torta) estaban en la lista de *"artículos sin proyección"* del CLAUDE.md, donde
-- manda la capacidad de góndola. **Estaban ahí por este mismo bug**: tienen `proy_uni_mes = 0`
-- pero `proy_cajas_mes` de 0,17 / 0,33, así que la cuenta vieja los leía como 0. Ahora tienen
-- proyección —mínima, pero proyección— y gana la regla del 18/09 (*"proyección es siempre
-- rey"*): piden 1 caja en vez de llenar la góndola. Los **"sin proyección" bajan de 10 a 6**.
-- La cuarta baja es el **502**, de 256 a **255**: `proy_cajas_mes` viene redondeada a 2
-- decimales (520,66) y la división daba 520,6667. Una caja.
--
-- Backups: `zz_backups."GV_Backup_VistaGeneradorOC_proy_20260918"` (la definición previa) y
-- `zz_backups."GV_Backup_VistaGeneradorOC_filas_proy_20260918"` (las 355 filas de antes).
-- ============================================================================

-- Definición VIVA completa (verificada por md5 contra la base: a20c8545…, 18.177 caracteres).

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
            sum(COALESCE(proyeccion_madre.proy_cajas_mes, 0::numeric)) AS cajas,
            sum(COALESCE(proyeccion_madre.proy_cajas_lk, 0::numeric)) AS p_lk,
            sum(COALESCE(proyeccion_madre.proy_cajas_chef, 0::numeric)) AS p_ch
           FROM proyeccion_madre
          WHERE btrim(proyeccion_madre.cod) ~ '^[0-9]'::text
          GROUP BY (regexp_replace(regexp_replace(regexp_replace(upper(btrim(proyeccion_madre.cod)), '^0+(?=.)'::text, ''::text), 'L$'::text, ''::text), '^546E$'::text, '546'::text))
        ), proy AS (
         SELECT COALESCE(f.ppal, pr.codn) AS codn,
            sum(pr.cajas) AS proy,
            sum(pr.p_lk) AS p_lk,
            sum(pr.p_ch) AS p_ch
           FROM proy_raw pr
             LEFT JOIN fam f ON f.sec = pr.codn
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
          WHERE f2.sec = cm.codn_base)) AND codn_base <> 'LIBRE'::text;;

alter view public.vista_generador_oc set (security_invoker = true);   -- NUNCA olvidarlo

-- centinela: que nadie vuelva a recalcular la proyeccion
insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
values ('vista_generador_oc','vista','sum\(pr\.cajas\) AS proy',
 'La proyeccion del generador de OC es proy_cajas_mes tal cual (sum), la misma que muestra Stocks. NO se recalcula dividiendo proy_uni_mes por el uxb: el motor de LK escribe las cajas en las dos columnas para los codigos que no tiene con uxb, y eso proyectaba 2.000 cajas/mes de menos.',
 'Thomas','v20.09')
on conflict do nothing;

-- CHEQUEOS
select cod, proy, maximo, stock, pedidos, total from public.vista_generador_oc where codn = '706';
-- proy = 201, total = 381
select round(sum(proy),2) from public.vista_generador_oc;                    -- 22.278,87
select round(sum(coalesce(proy_cajas_mes,0)),2) from public.proyeccion_madre; -- 22.305,87 (27,00 = 4 filas que no son articulos)
select * from public.gv_reglas_perdidas;    -- vacia
select * from public.gv_endpoints_rotos;    -- vacia
