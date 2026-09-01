-- Backup: vista_cola_impresion (definición previa a v12.24 (arts_fallback/faltantes_fallback))
-- Fecha: 2026-09-01
-- Motivo: se expande la vista para exponer artículos/faltantes desde Entregas_Virgilio,
--         así la Cola de impresión NP puede armar remito aunque el TAL venga sin resumen
--         (caso ETIQUETA de súper, o NP cerradas con 0 líos).
CREATE OR REPLACE VIEW public.vista_cola_impresion AS
 WITH tal AS (
         SELECT DISTINCT ON ((regexp_replace(TRIM(BOTH FROM split_part("Registros_Produccion_Virgilio".texto, '|'::text, 1)), '\.0+$'::text, ''::text))) regexp_replace(TRIM(BOTH FROM split_part("Registros_Produccion_Virgilio".texto, '|'::text, 1)), '\.0+$'::text, ''::text) AS np,
            upper(TRIM(BOTH FROM split_part("Registros_Produccion_Virgilio".texto, '|'::text, 3))) AS tanda,
            "Registros_Produccion_Virgilio".ts_cliente AS armado_ts,
            split_part("Registros_Produccion_Virgilio".texto, '|'::text, 4) AS resumen,
            "Registros_Produccion_Virgilio".legajo AS armador_leg
           FROM "Registros_Produccion_Virgilio"
          WHERE "Registros_Produccion_Virgilio".opcion = 'TAL'::text AND "Registros_Produccion_Virgilio".ts_cliente >= '2026-08-25 12:10:00-03'::timestamp with time zone
          ORDER BY (regexp_replace(TRIM(BOTH FROM split_part("Registros_Produccion_Virgilio".texto, '|'::text, 1)), '\.0+$'::text, ''::text)), "Registros_Produccion_Virgilio".ts_cliente DESC
        ), fn AS (
         SELECT DISTINCT ON ((regexp_replace(TRIM(BOTH FROM "Facturacion_NP".np), '\.0+$'::text, ''::text))) regexp_replace(TRIM(BOTH FROM "Facturacion_NP".np), '\.0+$'::text, ''::text) AS np,
            "Facturacion_NP".razon_social
           FROM "Facturacion_NP"
        ), pm AS (
         SELECT DISTINCT ON ((TRIM(BOTH FROM "PPP_Programacion_Diaria".np))) TRIM(BOTH FROM "PPP_Programacion_Diaria".np) AS np,
            "PPP_Programacion_Diaria".razon_social
           FROM "PPP_Programacion_Diaria"
        )
 SELECT t.np,
    COALESCE(NULLIF(t.tanda, ''::text), '—'::text) AS tanda,
    t.armado_ts,
    COALESCE(NULLIF(TRIM(BOTH FROM fn.razon_social), ''::text), pm.razon_social, ''::text) AS razon_social,
    EXTRACT(epoch FROM now() - t.armado_ts) > (24 * 3600)::numeric AS vencido,
    t.resumen,
    t.armador_leg
   FROM tal t
     LEFT JOIN "Impresion_NP" i ON i.np = t.np
     LEFT JOIN fn ON fn.np = t.np
     LEFT JOIN pm ON pm.np = t.np
  WHERE i.np IS NULL
  ORDER BY t.armado_ts;
