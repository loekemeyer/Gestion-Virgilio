-- v23.30 (Luis, 28/09: "es la pagina en general, urgente"): vista_saldos_stock en DOS pasos.
-- Antes aplicaba la regex de normalizacion del codigo a cada uno de los 70 mil movimientos
-- (722 ms en frio, 2-7 s con la base cargada, ~16 lecturas por minuto: la consulta que mas
-- tiempo de base se comia). Ahora agrupa primero por el codigo crudo (~3 mil grupos, 33 ms)
-- y recien ahi normaliza. Medido: 678 ms -> 108 ms; salida identica (EXCEPT ALL 0/0, 497 filas).
-- De rebote: gv_importados_ordenes 4.648 -> 88 ms, vista_generador_oc 5.176 -> 340 ms.
-- Rollback: la definicion anterior esta en zz_backups."GV_Backup_defs_saldos_stock_20260928".
create or replace view public.vista_saldos_stock with (security_invoker = true) as
 WITH cfg AS (
         SELECT ( SELECT "Stock_Config".valor
                   FROM "Stock_Config"
                  WHERE "Stock_Config".clave = 'cutoff_ts'::text
                 LIMIT 1) AS cutoff
        ), pre AS (
         -- v23.30: se agrupa PRIMERO por el codigo crudo (70 mil movimientos -> ~3 mil grupos)
         -- y recien despues se normaliza el codigo. La regex por fila costaba 20x (33 ms vs 722 ms).
         SELECT m.cod_art,
            m.descripcion,
            m.deposito,
            COALESCE(m.empresa, 'Mixto'::text) AS empresa,
            sum(m.delta) AS delta
           FROM "Movimientos_Stock" m, cfg
          WHERE cfg.cutoff IS NULL OR m.tipo = 'inicial'::text OR m.ts >= cfg.cutoff::timestamp with time zone
          GROUP BY m.cod_art, m.descripcion, m.deposito, (COALESCE(m.empresa, 'Mixto'::text))
        ), canon AS (
         SELECT p.cod_art,
            p.descripcion,
            p.deposito,
            p.delta,
            p.empresa,
                CASE
                    WHEN upper(btrim(p.cod_art)) ~ '^[0-9]+$'::text THEN
                    CASE
                        WHEN length(regexp_replace(upper(btrim(p.cod_art)), '^0+(?=.)'::text, ''::text)) >= 3 THEN regexp_replace(upper(btrim(p.cod_art)), '^0+(?=.)'::text, ''::text)
                        ELSE lpad(regexp_replace(upper(btrim(p.cod_art)), '^0+(?=.)'::text, ''::text), 3, '0'::text)
                    END
                    ELSE upper(btrim(p.cod_art))
                END AS ckey
           FROM pre p
        ), vivo AS (
         SELECT c.cod_art,
            c.descripcion,
            c.deposito,
            c.delta,
            c.empresa,
            c.ckey,
                CASE
                    WHEN (c.empresa = ANY (ARRAY['LK'::text, 'CH'::text])) AND (EXISTS ( SELECT 1
                       FROM codigos_duales d
                      WHERE regexp_replace(upper(btrim(d.cod)), '^0+(?=.)'::text, ''::text) = regexp_replace(c.ckey, '^0+(?=.)'::text, ''::text))) THEN (c.ckey || ' '::text) || c.empresa
                    ELSE c.ckey
                END AS outkey
           FROM canon c
        )
 SELECT (array_agg(cod_art ORDER BY (length(cod_art)), v.cod_art))[1] AS cod_art,
    (array_agg(descripcion ORDER BY (length(descripcion)), v.descripcion) FILTER (WHERE COALESCE(btrim(descripcion), ''::text) <> ''::text))[1] AS descripcion,
    COALESCE(sum(delta) FILTER (WHERE deposito = 'terminado'::text), 0::numeric) AS terminado,
    COALESCE(sum(delta) FILTER (WHERE deposito = 'excedente'::text), 0::numeric) AS excedente,
    COALESCE(sum(delta) FILTER (WHERE deposito = 'separar_pedidos'::text), 0::numeric) AS separar_pedidos,
    COALESCE(sum(delta) FILTER (WHERE deposito = 'a_facturar'::text), 0::numeric) AS a_facturar,
    COALESCE(sum(delta) FILTER (WHERE deposito = 'a_guardar'::text), 0::numeric) AS a_guardar,
    COALESCE(sum(delta) FILTER (WHERE deposito = 'racks'::text), 0::numeric) AS racks,
    COALESCE(sum(delta) FILTER (WHERE deposito = 'insumos'::text), 0::numeric) AS insumos,
    COALESCE(sum(delta) FILTER (WHERE deposito = 'para_envasar'::text), 0::numeric) AS para_envasar,
    COALESCE(sum(delta) FILTER (WHERE deposito = 'racks_ch'::text), 0::numeric) AS racks_ch,
        CASE
            WHEN count(DISTINCT empresa) = 1 THEN min(empresa)
            ELSE 'Mixto'::text
        END AS empresa,
        CASE
            WHEN outkey <> ckey THEN outkey
            ELSE (array_agg(cod_art ORDER BY (length(cod_art)), v.cod_art))[1]
        END AS clave
   FROM vivo v
  GROUP BY outkey, ckey
;
alter view public.vista_saldos_stock set (security_invoker = true);
