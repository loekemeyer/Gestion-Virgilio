-- ============================================================================
-- v19.91 — LA DEMANDA DE UN CÓDIGO DUAL SE KEYEA CON LA EMPRESA (problema 427)
--
-- Thomas, 2026-09-18: *"437E por ejemplo, tenemos el código de LK y el código de CH (productos
-- que se consideran DIFERENTES, en diferentes lugares físicamente del depósito). En todo momento
-- viajan en tablas con una columna que dice de qué empresa son."*
--
-- ESTO ES LA ÚLTIMA PUNTA de un trabajo hecho en tramos, no un hallazgo nuevo. Lo anterior está
-- en `docs/PLAN-SACAR-SUFIJO-EMPRESA.md` (tramos 1, 2, 3, 4 y 4bis: v16.14 → v16.51) y en
-- `docs/ANALISIS-NIVEL2-EMPRESA-PAR.md`; problemas 92, 108, 88, 372, 390, 416 y 430.
--
-- ## El síntoma
--
-- La tabla de Stock mostraba `437E CH` con **15 cajas pedidas** que eran **todas de LK**, y el
-- pop-up del detalle decía, con razón, que lo de Chef ya estaba todo facturado.
--
-- ## La causa, en dos mitades
--
-- 1. **BACKEND.** `vista_stock_procesada` keyea el STOCK por `vista_saldos_stock.clave`, que para
--    un dual ya viene partida (`437E LK` / `437E CH`) desde el tramo 1. Pero la DEMANDA la
--    keyeaba con `gv_cod_stock(resolver_equiv(articulo))`, que **pela la empresa**: los pedidos
--    de las dos empresas caían juntos en una fila PELADA (`437E`) que la pantalla esconde
--    (`visible_en_stock = false`), y las dos mitades quedaban en **0**.
-- 2. **FRONT.** `_demOf` / `_proyOf` / `_demSPOf` hacían *fallback al código base* cuando no
--    encontraban la clave exacta. Así, la cifra de la fila escondida aparecía en **LAS DOS**
--    mitades: 15 en LK y 15 en CH, 30 en pantalla para una demanda real de 15.
--
-- ## El arreglo
--
-- Pieza nueva **`public.gv_cod_stock_dem(articulo, pedido)`**: una sola definición de "la clave
-- de stock de una línea de demanda". Hace UNA cosa: cuando el código es dual, le vuelve a pegar
-- la empresa. La empresa la da el **pedido** (`gv_empresa_de_np_texto`, la canónica, la misma que
-- usa `vista_generador_oc`), salvo que el artículo venga con **"L"** al final (438EL = artículo de
-- Loeke vendido por Chef → LK, regla del dueño v13.71, que gana porque se pickea de la góndola
-- Loeke). Sin pedido no hay empresa: devuelve la clave pelada, o sea la deja donde estaba, en vez
-- de atribuírsela a una empresa adivinada.
--
-- **Es un no-op demostrable para todo lo que no sea dual.** Medido sobre las **11.549 líneas** de
-- `gv_demanda_pedidos`: cambian **238**, y son exactamente los 4 códigos duales.
--
-- En `vista_stock_procesada` se cambió **sólo `dem_raw`** (el que alimenta `cajas_pedidas`, la
-- columna que se ve). `dem_oc_raw` / `dem_fam` quedaron intactos a propósito: alimentan
-- `cajas_pedidas_familia`, que **no la lee nadie** (ni el front ni `refresh_stocks_carga_rapida`),
-- y partirla exige llevar también la empresa de la familia — cambio aparte, no se mezcla.
--
-- ## Qué cambió, medido (baseline refrescado en la misma transacción, no un snapshot viejo)
--
--   | | |
--   |---|---|
--   | filas | 370 → **367** |
--   | códigos NO duales con la demanda cambiada | **0** |
--   | filas nuevas | **0** |
--   | la demanda de cada dual | **se reparte, el total por código no cambia** |
--
--   · `437E LK` 0 → **15** · `437E CH` 0 → 0   (las 15 eran todas de LK)
--   · `438E LK` 0 → **13** · `438E CH` 0 → **6**   (sumaban 19)
--   · `439E LK` 0 → **12** · `439E CH` 0 → 0
--   · `809E CH` 0 → **14** · `809E LK` 0 → **5**   (sumaban 19)
--
-- **Las 3 filas que desaparecen no son mercadería:** `437E` y `438E` son filas del catálogo de
-- `Insumos` con 0 de stock de mercadería, que el propio `WHERE` de la vista descarta cuando no
-- tienen demanda — se mantenían vivas sólo por la demanda mal keyeada. `809E` no tiene fila
-- pelada en `vista_saldos_stock` (sólo las dos mitades), así que existía sólo por lo mismo.
-- `439E` pelada sigue estando (tiene clave propia en saldos), en 0 y escondida.
--
-- ## Cómo se aplicó (y por qué así)
--
-- Una matview no admite `CREATE OR REPLACE`, así que fue **DROP CASCADE + CREATE en UNA
-- transacción** (la del `do` block: si algo falla no queda nada a medias — y falló dos veces con
-- asserts, y las dos veces se deshizo solo). El pozo documentado del CASCADE son los
-- **dependientes transitivos**: `Stock_Saldos` y `gv_importados_stock_dep` (nivel 2) y
-- `gv_importados_ordenes` (**nivel 3**, el que dejó Importados en 404 en la v16.20 y la v16.33).
-- Los tres se recrearon en la misma transacción **desde el catálogo** (`pg_get_viewdef`, no una
-- copia a mano), con `security_invoker = true` y los mismos grants.
--
-- Pasos, en orden:
--   1. `cron.alter_job(55, active := false)` y `(57, false)` — los dos que la refrescan.
--   2. Backups: `zz_backups."GV_Backup_VistaStockProcesada_antes_20260918"` (datos) y
--      `zz_backups."GV_Backup_VSP_defs_20260918"` (definición + reloptions + ACL + índices de la
--      matview y de los 3 dependientes).
--   3. El `do` block: trae la definición VIVA, verifica que el fragmento a cambiar aparezca
--      **2 veces en `dem_raw` y 2 en `dem_oc_raw`** (si no, aborta sin tocar nada), refresca la
--      matview vieja para tener un baseline del MISMO instante, dropea, crea, recrea índice +
--      grants + los 3 dependientes, y corre 4 asserts.
--   4. `cron.alter_job(55, true)`, `(57, true)`, `refresh_stocks_carga_rapida()`.
--   5. Chequeos: `gv_endpoints_rotos` vacía · `gv_reglas_perdidas` vacía · ACL idéntica a la de
--      antes (`anon=arwdxtm`) · lectura como `anon` OK · suite de 217 tests en verde.
--
-- ## Rollback
--
-- La definición anterior COMPLETA está en `zz_backups."GV_Backup_VSP_defs_20260918"` (columna
-- `definicion`, fila `vista_stock_procesada`), junto con las de los 3 dependientes. El rollback es
-- el mismo procedimiento al revés: apagar los crons 55/57, DROP CASCADE, recrear la matview con
-- esa definición, el índice único, los grants, los 3 dependientes, y volver el front a la v19.88.
-- Alcanza con volver `dem_raw` a `gv_cod_stock(resolver_equiv(TRIM(BOTH FROM b.articulo)))`.
--
-- Centinela: fila en `GV_Reglas_Centinela` (el patrón `gv_cod_stock_dem` tiene que seguir en la
-- vista). Front: `_stkLookupEmp` en `index.html` + `tests/stk-dual-demanda-empresa.cjs`.
-- ============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- 1) La pieza nueva: la clave de stock de una línea de demanda
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.gv_cod_stock_dem(p_articulo text, p_pedido text)
returns text
language sql
stable
set search_path to 'public','pg_temp'
as $fn$
  with b as (
    select public.gv_cod_stock(public.resolver_equiv(btrim(coalesce(p_articulo,'')))) as cb
  ), e as (
    select case
             when upper(btrim(coalesce(p_articulo,''))) ~ '[0-9E]L$' then 'LK'
             when nullif(btrim(coalesce(p_pedido,'')),'') is null    then null
             when public.gv_empresa_de_np_texto(btrim(p_pedido)) = 'chef' then 'CH'
             when public.gv_empresa_de_np_texto(btrim(p_pedido)) = 'lk'   then 'LK'
             else null
           end as emp
  )
  select case
           when e.emp is not null
            and exists (select 1 from public.codigos_duales d
                         where regexp_replace(upper(btrim(d.cod)), '^0+(?=.)', '') = b.cb)
           then b.cb || ' ' || e.emp
           else b.cb
         end
    from b, e;
$fn$;

-- La prueba de que es un no-op para todo lo que no sea dual (238 de 11.549, los 4 duales):
--   with l as (select gv_cod_stock(resolver_equiv(btrim(articulo))) viejo,
--                     gv_cod_stock_dem(articulo, pedido) nuevo
--                from public.gv_demanda_pedidos where nullif(btrim(articulo),'') is not null)
--   select count(*) lineas, count(*) filter (where viejo <> nuevo) cambian,
--          string_agg(distinct viejo||' -> '||nuevo, ' · ') filter (where viejo <> nuevo) detalle
--     from l;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2) El único cambio en la matview, aplicado sobre la definición VIVA
--    (el `do` block completo, con sus guards y sus asserts, está en §3.jt de
--     docs/SUPABASE-GESTION-VIRGILIO.md; acá queda el cambio en una línea)
-- ─────────────────────────────────────────────────────────────────────────────
--   dem_raw:  gv_cod_stock(resolver_equiv(TRIM(BOTH FROM b.articulo)))
--          →  gv_cod_stock_dem(b.articulo, b.pedido)
--   (2 ocurrencias: el SELECT y el GROUP BY. dem_oc_raw NO se toca.)
--
-- Después del swap, lo que hay que restituir sí o sí:
--   create unique index idx_vista_stock_procesada_cod on public.vista_stock_procesada using btree (cod);
--   grant insert, select, update, delete, references, trigger, maintain
--     on public.vista_stock_procesada to anon;
--   grant insert, select, update, delete, truncate, references, trigger, maintain
--     on public.vista_stock_procesada to authenticated, service_role;
--   -- y los 3 dependientes, cada uno con `with (security_invoker=true)` y los mismos grants:
--   --   Stock_Saldos · gv_importados_stock_dep · gv_importados_ordenes

-- ─────────────────────────────────────────────────────────────────────────────
-- 3) LA DEFINICIÓN COMPLETA, tal como quedó viva (v19.91)
--    Va acá entera a propósito: la lección de la v16.30 fue que el repo tenía
--    "instrucciones en prosa" y no el CREATE, y reconstruirla costó caro.
--    Ojo: una matview NO admite CREATE OR REPLACE. Para recrearla hay que
--    dropear con CASCADE y volver a crear el índice, los grants y los 3
--    dependientes (ver el punto 2).
-- ─────────────────────────────────────────────────────────────────────────────
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
         SELECT "GV_PPP_Entregados_Historico".np
           FROM "GV_PPP_Entregados_Historico"
          WHERE "GV_PPP_Entregados_Historico".np IS NOT NULL
        UNION
         SELECT "NP_Canceladas".np
           FROM "NP_Canceladas"
          WHERE "NP_Canceladas".np IS NOT NULL
        UNION
         SELECT wc.np_label
           FROM "GV_Web_Cancelados" wc
          WHERE wc.np_label IS NOT NULL
        ), dem_raw AS (
         -- v19.91 (problema 427): la clave lleva la EMPRESA cuando el codigo es dual.
         SELECT gv_cod_stock_dem(b.articulo, b.pedido) AS codn,
            sum(COALESCE(b.cajas, 0::numeric)) AS pedidos
           FROM gv_demanda_pedidos b
          WHERE NULLIF(TRIM(BOTH FROM b.articulo), ''::text) IS NOT NULL AND NOT (EXISTS ( SELECT 1
                   FROM cerradas c_1
                  WHERE c_1.np = b.pedido))
          GROUP BY (gv_cod_stock_dem(b.articulo, b.pedido))
         HAVING sum(COALESCE(b.cajas, 0::numeric)) > 0::numeric
        ), pickeadas AS (
         SELECT DISTINCT upper(TRIM(BOTH FROM "Registros_Produccion_Virgilio".texto)) AS tanda
           FROM "Registros_Produccion_Virgilio"
          WHERE "Registros_Produccion_Virgilio".opcion = 'TP'::text AND NULLIF(TRIM(BOTH FROM COALESCE("Registros_Produccion_Virgilio".texto, ''::text)), ''::text) IS NOT NULL
        ), pend_np_oc AS (
         SELECT DISTINCT TRIM(BOTH FROM p_1.np) AS np
           FROM "GV_PPP_Programacion_Diaria" p_1
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
         -- OJO: este NO se toco. Alimenta cajas_pedidas_familia, que no la lee nadie; partirla
         -- exige llevar tambien la empresa de la familia (ver el encabezado).
         SELECT gv_cod_stock(resolver_equiv(TRIM(BOTH FROM b.articulo))) AS codn,
            sum(COALESCE(b.cajas, 0::numeric)) AS pedidos
           FROM gv_demanda_pedidos b
             JOIN pend_np_oc n ON TRIM(BOTH FROM b.pedido) = n.np
          WHERE NULLIF(TRIM(BOTH FROM b.articulo), ''::text) IS NOT NULL
          GROUP BY (gv_cod_stock(resolver_equiv(TRIM(BOTH FROM b.articulo))))
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
         SELECT gv_cod_stock(proyeccion_madre.cod) AS codn,
            sum(COALESCE(proyeccion_madre.proy_cajas_mes, 0::numeric)) AS proy_cajas_mes
           FROM proyeccion_madre
          GROUP BY (gv_cod_stock(proyeccion_madre.cod))
        UNION ALL
         SELECT gv_cod_stock(g.cod) ||
                CASE
                    WHEN g.empresa = 'chef'::text THEN ' CH'::text
                    ELSE ' LK'::text
                END AS codn,
            sum(COALESCE(g.proy_cajas_mes, 0::numeric)) AS proy_cajas_mes
           FROM ( SELECT pm.cod,
                    e.empresa,
                    e.proy_cajas_mes
                   FROM proyeccion_madre pm
                     CROSS JOIN LATERAL ( VALUES ('lk'::text,COALESCE(pm.proy_cajas_lk, 0::numeric)), ('chef'::text,COALESCE(pm.proy_cajas_chef, 0::numeric))) e(empresa, proy_cajas_mes)
                  WHERE e.proy_cajas_mes > 0::numeric) g
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
