-- v19.74 — gv_viaje_np: la VUELTA se corta bien (problema 412)
--
-- ANTES:  vuelta = 1 + sum(orden = 1) OVER (… ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING)
-- La ventana excluía la fila actual, así que la NP con orden = 1 —la PRIMERA que manda el
-- operario al tocar "Terminé"— no abría su propia vuelta: quedaba contada en la anterior y la
-- vuelta nueva arrancaba recién en la segunda NP. Resultado: cada carga real salía partida en
-- dos, y TODOS los fleteros mostraban una "vuelta 1" de exactamente 1 NP.
--
-- AHORA:  vuelta = GREATEST(sum(orden = 1) OVER (… AND CURRENT ROW), 1)
--   · se cuenta INCLUYENDO la fila actual → la NP con orden = 1 abre su vuelta;
--   · el GREATEST(…, 1) es para los CCN VIEJOS, anteriores a la v15.70, que no traen el 4º
--     campo (orden NULL): sin él esas cargas caían en "vuelta 0". Son 20 fletero-días.
--
-- Medición (18/09, toda la historia de CCN): 47 vueltas → 35, sobre 32 fletero-días. 998 NP,
-- las mismas antes y después. `gv_viajes_sin_controlar` sigue vacía y `gv_endpoints_rotos` en 0.
-- Caso testigo: Guillermo 14/09 hizo UNA carga de 9 NP a las 10:51 + la de Cencosud (6 NP);
-- figuraba como 1 + 8 + 5 en tres vueltas, ahora es 9 + 6 en dos.
--
-- No rompe nada: `gv_viaje_np`, `gv_viaje` y `gv_viajes_sin_controlar` no las lee ninguna
-- función, vista, cron ni pantalla (verificado sobre pg_proc, pg_views, cron.job e index.html);
-- se consultan a mano. `GV_Viaje_Horas`, que joinea por (fecha, fletero, vuelta), está VACÍA,
-- así que la renumeración no despega ninguna hora ya cargada.
--
-- ROLLBACK: volver a poner `1 + COALESCE(…)` y `ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING`
-- (sin el GREATEST), y reponer el security_invoker.

create or replace view public.gv_viaje_np as
 WITH ccn AS (
         SELECT regexp_replace(upper(btrim(split_part(r.texto, '|'::text, 1))), '\.0+$'::text, ''::text) AS np,
            NULLIF(upper(btrim(split_part(r.texto, '|'::text, 2))), ''::text) AS tanda,
            NULLIF(btrim(split_part(r.texto, '|'::text, 3)), ''::text) AS fletero,
            NULLIF(btrim(split_part(r.texto, '|'::text, 4)), ''::text)::integer AS orden,
            (r.ts_cliente AT TIME ZONE 'America/Argentina/Buenos_Aires'::text)::date AS fecha,
            r.ts_cliente AS cargado_at,
            r.legajo
           FROM "Registros_Produccion_Virgilio" r
          WHERE r.opcion = 'CCN'::text AND NOT es_legajo_test(r.legajo)
        ), uno AS (
         SELECT DISTINCT ON (ccn.fecha, (COALESCE(ccn.fletero, ''::text)), ccn.np) ccn.np,
            ccn.tanda,
            ccn.fletero,
            ccn.orden,
            ccn.fecha,
            ccn.cargado_at,
            ccn.legajo
           FROM ccn
          ORDER BY ccn.fecha, (COALESCE(ccn.fletero, ''::text)), ccn.np, ccn.cargado_at DESC
        ), num AS (
         SELECT u.np,
            u.tanda,
            u.fletero,
            u.orden,
            u.fecha,
            u.cargado_at,
            u.legajo,
            GREATEST(COALESCE(sum(
                CASE
                    WHEN u.orden = 1 THEN 1
                    ELSE 0
                END) OVER (PARTITION BY u.fecha, u.fletero ORDER BY u.cargado_at, u.np ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW), 0::bigint), 1::bigint) AS vuelta
           FROM uno u
        ), crn AS (
         SELECT DISTINCT regexp_replace(upper(btrim(split_part("Registros_Produccion_Virgilio".texto, '|'::text, 1))), '\.0+$'::text, ''::text) AS np,
            min("Registros_Produccion_Virgilio".ts_cliente) AS controlado_at
           FROM "Registros_Produccion_Virgilio"
          WHERE "Registros_Produccion_Virgilio".opcion = 'CRN'::text
          GROUP BY (regexp_replace(upper(btrim(split_part("Registros_Produccion_Virgilio".texto, '|'::text, 1))), '\.0+$'::text, ''::text))
        ), dat AS (
         SELECT regexp_replace(btrim(gv_ppp_programacion_diaria.np), '\.0+$'::text, ''::text) AS np,
            gv_ppp_programacion_diaria.m3,
            gv_ppp_programacion_diaria.zona,
            gv_ppp_programacion_diaria.razon_social,
            gv_ppp_programacion_diaria.cod
           FROM gv_ppp_programacion_diaria
        UNION ALL
         SELECT gv_ppp_web_estado.np_label,
            gv_ppp_web_estado.m3,
            gv_ppp_web_estado.zona,
            gv_ppp_web_estado.razon_social,
            gv_ppp_web_estado.cod_cliente
           FROM gv_ppp_web_estado
        UNION ALL
         SELECT regexp_replace(upper(btrim("Facturacion_NP".np)), '\.0+$'::text, ''::text) AS regexp_replace,
            "Facturacion_NP".m3,
            NULL::text AS text,
            "Facturacion_NP".razon_social,
            "Facturacion_NP".cod_cliente
           FROM "Facturacion_NP"
        )
 SELECT n.fecha,
    n.fletero,
    n.vuelta,
    n.np,
    n.tanda,
    n.orden,
    n.cargado_at,
    n.legajo,
    d.razon_social,
    d.cod AS cod_cliente,
    d.m3,
    gv_es_super_np(n.np, d.cod) OR lower(COALESCE(d.zona, ''::text)) ~ 'super|súper'::text AS es_super,
    lower(COALESCE(d.zona, ''::text)) ~ 'retira'::text AS es_retira,
    c.np IS NOT NULL AS controlada,
    c.controlado_at
   FROM num n
     LEFT JOIN crn c ON c.np = n.np
     LEFT JOIN LATERAL ( SELECT dat.np,
            dat.m3,
            dat.zona,
            dat.razon_social,
            dat.cod
           FROM dat
          WHERE dat.np = n.np
          ORDER BY dat.m3 DESC NULLS LAST
         LIMIT 1) d ON true;

-- ⚠ CREATE OR REPLACE VIEW sin WITH (...) borra las reloptions: hay que reponerlo SIEMPRE.
alter view public.gv_viaje_np set (security_invoker = true);

-- chequeos
-- select min(vuelta) from public.gv_viaje_np;          -- 1
-- select count(*) from public.gv_viajes_sin_controlar; -- vacía = todo bien
-- select count(*) from public.gv_endpoints_rotos;      -- 0
