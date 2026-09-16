-- Definición de public.gv_ocupacion_lugar tal como estaba ANTES de la v18.95
-- (tomada con pg_get_viewdef el 2026-09-16). Ejecutar este archivo es el rollback exacto
-- del PASO 3 de sql/gv_empresa_solo_duales_v1895.sql.
--
-- ⚠ Es la versión CON EL BUG del problema 340: el `AND s.empresa = l.empresa` exige que la
-- empresa del MOVIMIENTO sea la del LUGAR, así que para un código NO dual agarra sólo la
-- porción etiquetada del saldo. Medido el 16/09: de 790 filas, 458 difieren del saldo real y
-- 55 dan NULL teniendo saldo — 57.181 cajas de diferencia. Se guarda sólo para poder volver.

drop view if exists public.gv_ocupacion_lugar;
create view public.gv_ocupacion_lugar
with (security_invoker = true) as
 WITH saldo AS (
         SELECT upper(btrim(m.cod_art)) AS cod,
            upper(btrim(COALESCE(m.empresa, ''::text))) AS empresa,
                CASE
                    WHEN m.deposito = ANY (ARRAY['racks'::text, 'racks_ch'::text]) THEN 'rack'::text
                    WHEN m.deposito = 'insumos'::text THEN 'insumo'::text
                    ELSE 'gondola'::text
                END AS destino,
            sum(m.delta) AS saldo
           FROM "Movimientos_Stock" m
          GROUP BY (upper(btrim(m.cod_art))), (upper(btrim(COALESCE(m.empresa, ''::text)))), (
                CASE
                    WHEN m.deposito = ANY (ARRAY['racks'::text, 'racks_ch'::text]) THEN 'rack'::text
                    WHEN m.deposito = 'insumos'::text THEN 'insumo'::text
                    ELSE 'gondola'::text
                END)
        )
 SELECT l.sector,
    l.tipo,
    l.empresa,
    l.orden,
    li.cod,
    li.clase,
    li.cajas_max,
    sum(li.cajas_max) OVER (PARTITION BY li.cod, l.empresa) AS cajas_max_total_cod,
    s.saldo AS saldo_cod,
        CASE
            WHEN sum(li.cajas_max) OVER (PARTITION BY li.cod, l.empresa) > 0::numeric THEN round(100::numeric * s.saldo / sum(li.cajas_max) OVER (PARTITION BY li.cod, l.empresa), 1)
            ELSE NULL::numeric
        END AS pct_ocupado_cod
   FROM "GV_Lugar" l
     JOIN "GV_Lugar_Item" li ON li.sector = l.sector AND li.activo
     LEFT JOIN saldo s ON s.cod = upper(btrim(li.cod)) AND s.empresa = l.empresa AND s.destino =
        CASE
            WHEN li.clase = 'insumo'::text THEN 'insumo'::text
            ELSE l.tipo
        END
  WHERE l.activo;

alter view public.gv_ocupacion_lugar set (security_invoker = true);
