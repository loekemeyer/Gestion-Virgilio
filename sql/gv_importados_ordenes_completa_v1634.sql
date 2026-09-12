-- gv_importados_ordenes_completa_v1634.sql — 2026-09-12.
--
-- ⚠⚠ LA MISMA PIEDRA, DOS VECES. Un `DROP MATERIALIZED VIEW ... CASCADE` sobre
-- `vista_stock_procesada` se llevó esta vista en la v16.20 (y la pantalla de Importados
-- devolvió 404 hasta que se recreó en la v16.26) — y volvió a pasar **hoy con la v16.33**.
--
-- POR QUÉ SE REPITIÓ: antes de dropear miré las dependencias con una consulta de UN SOLO
-- NIVEL, que devolvió `Stock_Saldos` y `gv_importados_stock_dep`. Las respaldé y las recreé
-- bien. Pero `gv_importados_ordenes` cuelga de `gv_importados_stock_dep`, o sea **segundo
-- nivel**, y CASCADE baja hasta el fondo. Lo cazó el centinela `gv_endpoints_rotos`, que pasó
-- de 0 a 1.
--
-- REGLA: antes de un DROP CASCADE, listar dependientes **transitivos** (recursivo), no
-- directos. Y después del CREATE, mirar `gv_endpoints_rotos` — que para eso está.
--
-- LO SEGUNDO QUE FALLÓ, y es lo que hizo cara la recuperación: la v16.30 se aplicó como
-- **reemplazo de texto sobre `pg_get_viewdef`**, así que el repo NO tenía el CREATE completo
-- de la versión viva; había que reconstruirla juntando el CREATE de la v16.26 con las
-- sustituciones descritas en prosa en `sql/gv_uxb_importados_v1630.sql`. Este archivo cierra
-- eso: es la definición ENTERA, con el `gux` de la v16.30 ya incorporado. La regla del repo
-- ("el CREATE completo de cada objeto va en el repo, no 'aplicado en la base'") existe
-- exactamente para esto.
--
-- QUÉ HACE `gux`: el UxB sale de `GV_UxB` por empresa (fuente única), con
-- `Importados.uni_x_caja` de fallback para los que no están cargados. Los tres usos
-- —la columna de salida, `est_madre_live` y `stock_actual`/`unidades_pedidas`— pasan todos por
-- el mismo valor, así que no puede repetirse lo de `vista_facturable_anticipado` (mostrar un
-- UxB y calcular con otro).
--
-- VERIFICADO tras recrearla: 156 filas · 18.173 cajas brutas · 1.351 pedidas · 17.130
-- disponibles · 584E (el testigo del dueño) 15 − 5 = 10 cajas = 60 unidades · `anon` lee las
-- 156 · `gv_endpoints_rotos` de vuelta en 0.

create or replace view public.gv_importados_ordenes
with (security_invoker = true) as
 WITH gux AS (
         SELECT CASE WHEN "GV_UxB".empresa = 'CH'::text THEN 'CH'::text ELSE 'LK'::text END AS emp,
            gv_cod_stock("GV_UxB".cod) AS c,
            max("GV_UxB".uxb) AS u
           FROM "GV_UxB"
          WHERE "GV_UxB".uxb > 1::numeric
          GROUP BY 1, 2
        ), cfg AS (
         SELECT "Importados_Config".meses_objetivo
           FROM "Importados_Config"
          WHERE "Importados_Config".id = 1
        ), fam AS (
         SELECT gv_cod_stock("Equivalencias_Familia".cod_principal) AS ppal,
            gv_cod_stock("Equivalencias_Familia".cod_secundario) AS sec
           FROM "Equivalencias_Familia"
          WHERE NULLIF(btrim("Equivalencias_Familia".cod_principal), ''::text) IS NOT NULL AND NULLIF(btrim("Equivalencias_Familia".cod_secundario), ''::text) IS NOT NULL
        ), pe_raw AS (
         SELECT gv_cod_stock("GV_Proyeccion_Emp".cod) AS cod_norm,
            "GV_Proyeccion_Emp".empresa,
            "GV_Proyeccion_Emp".proy_cajas_mes
           FROM "GV_Proyeccion_Emp"
        ), pe AS (
         SELECT k.cod_norm,
            r.empresa,
            sum(r.proy_cajas_mes) AS proy_cajas_mes
           FROM ( SELECT DISTINCT pe_raw.cod_norm
                   FROM pe_raw
                UNION
                 SELECT fam.ppal
                   FROM fam) k
             JOIN pe_raw r ON r.cod_norm = k.cod_norm OR (r.cod_norm IN ( SELECT f.sec
                   FROM fam f
                  WHERE f.ppal = k.cod_norm))
          GROUP BY k.cod_norm, r.empresa
        ), partes AS (
         SELECT DISTINCT upper("Importados_Partes_Map".parte) AS cod
           FROM "Importados_Partes_Map"
        ), ch_rows AS (
         SELECT DISTINCT upper("Importados".cod_art) AS cod
           FROM "Importados"
          WHERE "Importados".principal AND "Importados".activo AND upper(COALESCE("Importados".marca, ''::text)) = 'CH'::text
        ), dup AS (
         SELECT gv_cod_stock("Importados".cod_art) AS cod_norm
           FROM "Importados"
          WHERE "Importados".principal AND "Importados".activo
          GROUP BY (gv_cod_stock("Importados".cod_art))
         HAVING count(*) > 1
        ), stk AS (
         SELECT i_1.id,
            COALESCE(sum(d.cajas_bruto), 0::numeric) AS cajas_bruto,
            COALESCE(sum(d.cajas_pedidas), 0::numeric) AS cajas_pedidas
           FROM "Importados" i_1
             LEFT JOIN gv_importados_stock_dep d ON d.cod_norm = gv_cod_stock(i_1.cod_art) AND (NOT (EXISTS ( SELECT 1
                   FROM dup
                  WHERE dup.cod_norm = gv_cod_stock(i_1.cod_art))) OR upper(COALESCE(i_1.marca, ''::text)) = 'CH'::text AND d.empresa = 'CH'::text OR upper(COALESCE(i_1.marca, ''::text)) <> 'CH'::text AND (d.empresa = ANY (ARRAY['LK'::text, 'MIXTO'::text])))
          GROUP BY i_1.id
        )
 SELECT i.id,
    i.cod_art,
    i.marca,
    i.proveedor,
    i.descripcion,
    i.fob_uni,
    COALESCE(gx.u, i.uni_x_caja) AS uni_x_caja,
    i.principal,
    i.activo,
    i.notas,
    i.est_madre_seed,
    i.est_madre_override,
    i.pedido_manual,
    COALESCE(i.pedido_curso, 0::numeric) AS pedido_curso,
        CASE
            WHEN upper(COALESCE(i.marca, ''::text)) = 'CH'::text THEN 'Chef'::text
            ELSE 'Loeke'::text
        END AS planta,
        CASE
            WHEN p.proy_cajas_mes IS NOT NULL THEN round(p.proy_cajas_mes * COALESCE(gx.u, i.uni_x_caja, 1::numeric))
            ELSE NULL::numeric
        END AS est_madre_live,
    ( SELECT cfg.meses_objetivo
           FROM cfg) AS meses_objetivo,
    COALESCE(i.est_madre_override,
        CASE
            WHEN p.proy_cajas_mes IS NOT NULL THEN round(p.proy_cajas_mes * COALESCE(gx.u, i.uni_x_caja, 1::numeric))
            ELSE NULL::numeric
        END, i.est_madre_seed, 0::numeric) AS est_madre_eff,
        CASE
            WHEN i.est_madre_override IS NOT NULL THEN 'override'::text
            WHEN p.proy_cajas_mes IS NOT NULL THEN 'live'::text
            ELSE 'seed'::text
        END AS est_madre_fuente,
    round(GREATEST(COALESCE(st.cajas_bruto, 0::numeric) - COALESCE(st.cajas_pedidas, 0::numeric), 0::numeric) * COALESCE(gx.u, i.uni_x_caja, 0::numeric)) AS stock_actual,
    GREATEST(COALESCE(st.cajas_bruto, 0::numeric) - COALESCE(st.cajas_pedidas, 0::numeric), 0::numeric) AS stock_cajas,
    COALESCE(st.cajas_bruto, 0::numeric) AS stock_cajas_bruto,
    COALESCE(st.cajas_pedidas, 0::numeric) AS cajas_pedidas,
    round(COALESCE(st.cajas_pedidas, 0::numeric) * COALESCE(gx.u, i.uni_x_caja, 0::numeric)) AS unidades_pedidas,
    COALESCE(si.stock_uni, 0::numeric) AS stock_insumos,
    pt.cod IS NOT NULL AS es_parte,
        CASE
            WHEN pt.cod IS NOT NULL AND si.cod IS NOT NULL THEN si.stock_uni
            ELSE round(GREATEST(COALESCE(st.cajas_bruto, 0::numeric) - COALESCE(st.cajas_pedidas, 0::numeric), 0::numeric) * COALESCE(gx.u, i.uni_x_caja, 0::numeric)) + COALESCE(si.stock_uni, 0::numeric)
        END AS stock_total
   FROM "Importados" i
     LEFT JOIN stk st ON st.id = i.id
     LEFT JOIN gux gx ON gx.emp =
        CASE
            WHEN upper(COALESCE(i.marca, ''::text)) = 'CH'::text THEN 'CH'::text
            ELSE 'LK'::text
        END AND gx.c = gv_cod_stock(i.cod_art)
     LEFT JOIN pe p ON p.cod_norm = gv_cod_stock(i.cod_art) AND p.empresa =
        CASE
            WHEN upper(COALESCE(i.marca, ''::text)) = 'CH'::text THEN 'chef'::text
            ELSE 'lk'::text
        END
     LEFT JOIN partes pt ON pt.cod = upper(i.cod_art)
     LEFT JOIN gv_importados_stock_insumos si ON upper(si.cod) = upper(i.cod_art) AND i.principal AND i.activo AND (upper(COALESCE(i.marca, ''::text)) = 'CH'::text OR NOT (EXISTS ( SELECT 1
           FROM ch_rows c
          WHERE c.cod = upper(i.cod_art))));

grant select on public.gv_importados_ordenes to anon, authenticated;

comment on view public.gv_importados_ordenes is
  'v16.34 — definicion COMPLETA (v16.26 + el CTE gux de la v16.30, que toma el UxB de GV_UxB). Recreada por segunda vez despues de un DROP CASCADE sobre vista_stock_procesada: la primera fue la v16.20, esta la v16.33. Motor de pedidos de importacion; stock_actual = deposito real menos lo ya pedido, con piso 0.';
