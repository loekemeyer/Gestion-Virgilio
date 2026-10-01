-- v25.95 (2026-10-01) — Recepción Remitos: el reloj de las 30 hs arranca en la carga ACTUAL.
--
-- Caso: LK 0122 (Inc) y LK 0177 (Multi Bazar) salieron, volvieron (↩ s/salida = FSS) y se
-- recargaron el 01/10. `first_load` era min(CCN) de los 7 días, o sea la carga ANTERIOR a la
-- vuelta (28/09 y 29/09), y RR los mostraba VENCIDOS recién cargados. Además la PPP mandó la
-- alarma CRA "carga sin control" falsa de los dos (01/10 16:38).
--
-- Regla: el ciclo vigente empieza en la primera CCN POSTERIOR a la última FSS que haya antes
-- de la última CCN. Sin FSS en el medio, es igual que antes (min de las CCN).
-- Sólo cambia el CTE `ccn` (+ el CTE nuevo `fss_prev`); mismas columnas, mismo orden.
--
-- Rollback: volver a `min(ccn_raw.ts_cliente) AS first_load` sin el join a fss_prev
-- (definición anterior completa en zz_backups no hace falta: es este mismo texto sin fss_prev).

CREATE OR REPLACE VIEW public.vista_control_remitos AS
 WITH since AS (
         SELECT now() - '7 days'::interval AS ts
        ), ccn_raw AS (
         SELECT split_part("Registros_Produccion_Virgilio".texto, '|'::text, 1) AS np_raw,
            upper(TRIM(BOTH FROM COALESCE(split_part("Registros_Produccion_Virgilio".texto, '|'::text, 2), ''::text))) AS tanda,
            "Registros_Produccion_Virgilio".ts_cliente,
            row_number() OVER (PARTITION BY (TRIM(BOTH FROM split_part("Registros_Produccion_Virgilio".texto, '|'::text, 1))) ORDER BY "Registros_Produccion_Virgilio".ts_cliente) AS rn_first,
            row_number() OVER (PARTITION BY (TRIM(BOTH FROM split_part("Registros_Produccion_Virgilio".texto, '|'::text, 1))) ORDER BY "Registros_Produccion_Virgilio".ts_cliente DESC) AS rn_last
           FROM "Registros_Produccion_Virgilio"
          WHERE "Registros_Produccion_Virgilio".opcion = 'CCN'::text AND "Registros_Produccion_Virgilio".ts_cliente >= (( SELECT since.ts
                   FROM since))
        ), fss_prev AS (
         -- v25.95: la última vuelta al depósito (FSS) ANTERIOR a la última carga
         SELECT f.np,
            max(f.ts_cliente) AS fss_prev
           FROM ( SELECT regexp_replace(TRIM(BOTH FROM split_part(r.texto, '|'::text, 1)), '\.0+$'::text, ''::text) AS np,
                    r.ts_cliente
                   FROM "Registros_Produccion_Virgilio" r
                  WHERE r.opcion = 'FSS'::text AND r.ts_cliente >= (( SELECT since.ts
                           FROM since))) f
             JOIN ( SELECT regexp_replace(TRIM(BOTH FROM ccn_raw.np_raw), '\.0+$'::text, ''::text) AS np,
                    max(ccn_raw.ts_cliente) AS last_ccn
                   FROM ccn_raw
                  GROUP BY (regexp_replace(TRIM(BOTH FROM ccn_raw.np_raw), '\.0+$'::text, ''::text))) l ON l.np = f.np AND f.ts_cliente < l.last_ccn
          GROUP BY f.np
        ), ccn AS (
         SELECT regexp_replace(TRIM(BOTH FROM ccn_raw.np_raw), '\.0+$'::text, ''::text) AS np,
            max(
                CASE
                    WHEN ccn_raw.tanda <> ''::text AND ccn_raw.tanda <> '—'::text THEN ccn_raw.tanda
                    ELSE NULL::text
                END) AS tanda,
            -- v25.95-ciclo: la carga vigente es la primera DESPUÉS de la última vuelta (FSS)
            min(ccn_raw.ts_cliente) FILTER (WHERE ccn_raw.ts_cliente > COALESCE(fp.fss_prev, '-infinity'::timestamp with time zone)) AS first_load,
            max(ccn_raw.ts_cliente) AS last_ccn
           FROM ccn_raw
             LEFT JOIN fss_prev fp ON fp.np = regexp_replace(TRIM(BOTH FROM ccn_raw.np_raw), '\.0+$'::text, ''::text)
          GROUP BY (regexp_replace(TRIM(BOTH FROM ccn_raw.np_raw), '\.0+$'::text, ''::text))
        ), tal AS (
         SELECT DISTINCT ON ((regexp_replace(TRIM(BOTH FROM split_part("Registros_Produccion_Virgilio".texto, '|'::text, 1)), '\.0+$'::text, ''::text))) regexp_replace(TRIM(BOTH FROM split_part("Registros_Produccion_Virgilio".texto, '|'::text, 1)), '\.0+$'::text, ''::text) AS np,
            split_part("Registros_Produccion_Virgilio".texto, '|'::text, 2)::integer AS lios,
            NULLIF(lower(TRIM(BOTH FROM split_part("Registros_Produccion_Virgilio".texto, '|'::text, 5))), ''::text) AS clase
           FROM "Registros_Produccion_Virgilio"
          WHERE "Registros_Produccion_Virgilio".opcion = 'TAL'::text AND "Registros_Produccion_Virgilio".ts_cliente >= (( SELECT since.ts
                   FROM since))
          ORDER BY (regexp_replace(TRIM(BOTH FROM split_part("Registros_Produccion_Virgilio".texto, '|'::text, 1)), '\.0+$'::text, ''::text)), "Registros_Produccion_Virgilio".ts_cliente DESC
        ), crn AS (
         SELECT DISTINCT regexp_replace(TRIM(BOTH FROM split_part("Registros_Produccion_Virgilio".texto, '|'::text, 1)), '\.0+$'::text, ''::text) AS np
           FROM "Registros_Produccion_Virgilio"
          WHERE "Registros_Produccion_Virgilio".opcion = 'CRN'::text AND "Registros_Produccion_Virgilio".ts_cliente >= (( SELECT since.ts
                   FROM since))
        ), fss AS (
         SELECT regexp_replace(TRIM(BOTH FROM split_part("Registros_Produccion_Virgilio".texto, '|'::text, 1)), '\.0+$'::text, ''::text) AS np,
            max("Registros_Produccion_Virgilio".ts_cliente) AS fss_ts
           FROM "Registros_Produccion_Virgilio"
          WHERE "Registros_Produccion_Virgilio".opcion = 'FSS'::text AND "Registros_Produccion_Virgilio".ts_cliente >= (( SELECT since.ts
                   FROM since))
          GROUP BY (regexp_replace(TRIM(BOTH FROM split_part("Registros_Produccion_Virgilio".texto, '|'::text, 1)), '\.0+$'::text, ''::text))
        ), caj AS (
         SELECT regexp_replace(TRIM(BOTH FROM "Entregas_Virgilio".np), '\.0+$'::text, ''::text) AS np,
            sum(COALESCE("Entregas_Virgilio".cajas_pedidas, 0::numeric)) AS cajas
           FROM "Entregas_Virgilio"
          GROUP BY (regexp_replace(TRIM(BOTH FROM "Entregas_Virgilio".np), '\.0+$'::text, ''::text))
        ), ppp_meta AS (
         SELECT DISTINCT ON ((TRIM(BOTH FROM "GV_PPP_Programacion_Diaria".np))) TRIM(BOTH FROM "GV_PPP_Programacion_Diaria".np) AS np,
            TRIM(BOTH FROM COALESCE("GV_PPP_Programacion_Diaria".cod, ''::text)) AS cod_cliente,
            COALESCE("GV_PPP_Programacion_Diaria".razon_social, ''::text) AS rs
           FROM "GV_PPP_Programacion_Diaria"
        ), ent_meta AS (
         SELECT DISTINCT ON ((TRIM(BOTH FROM "GV_PPP_Entregados_Historico".np))) TRIM(BOTH FROM "GV_PPP_Entregados_Historico".np) AS np,
            TRIM(BOTH FROM COALESCE("GV_PPP_Entregados_Historico".cod, ''::text)) AS cod_cliente,
            COALESCE("GV_PPP_Entregados_Historico".rs, ''::text) AS rs
           FROM "GV_PPP_Entregados_Historico"
        )
 SELECT c.np,
    COALESCE(c.tanda, '—'::text) AS tanda,
    c.first_load,
    c.last_ccn,
    t.lios,
    crn.np IS NOT NULL AS controlado,
    f.fss_ts IS NOT NULL AND f.fss_ts > c.last_ccn AS sin_salida,
    COALESCE(pm.cod_cliente, em.cod_cliente, ''::text) AS cod_cliente,
    COALESCE(pm.rs, em.rs, ''::text) AS rs,
    EXTRACT(epoch FROM now() - c.first_load) > (30 * 3600)::numeric AS vencido,
    t.clase,
    cj.cajas
   FROM ccn c
     LEFT JOIN tal t ON t.np = c.np
     LEFT JOIN crn ON crn.np = c.np
     LEFT JOIN fss f ON f.np = c.np
     LEFT JOIN caj cj ON cj.np = c.np
     LEFT JOIN ppp_meta pm ON pm.np = c.np
     LEFT JOIN ent_meta em ON em.np = c.np
  WHERE crn.np IS NULL AND NOT (f.fss_ts IS NOT NULL AND f.fss_ts > c.last_ccn)
  ORDER BY (EXTRACT(epoch FROM now() - c.first_load) > (30 * 3600)::numeric) DESC, (COALESCE(c.tanda, '—'::text)), c.np;

ALTER VIEW public.vista_control_remitos SET (security_invoker = true);

-- Chequeo: LK 0122 y LK 0177 tienen que dar first_load 01/10 y vencido = false.
-- select np, first_load, last_ccn, vencido from public.gv_vista_control_remitos where np in ('LK 0122','LK 0177');
