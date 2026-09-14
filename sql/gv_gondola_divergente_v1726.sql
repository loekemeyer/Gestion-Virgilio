-- ════════════════════════════════════════════════════════════════════
-- v17.26 — gv_gondola_divergente se reescribe SOBRE gv_planimetria_celda
--
-- POR QUÉ: quedaron dos centinelas contestando la misma pregunta con dos números.
-- El viejo (v16.50) decía 107 divergencias; el mapa de góndolas (v17.23, vista
-- gv_planimetria_celda) dice 35. Medido el 2026-09-14, los 72 de diferencia son
-- TODOS ruido del centinela viejo, no celdas sanas que el mapa se pierda:
--
--   | Del centinela viejo      | Qué eran en realidad                               |
--   |--------------------------|----------------------------------------------------|
--   | 9  sector_inexistente    | J1…J9 — pura grafía. `Capacidad_Sector` los guarda   |
--   |                          | sin el cero y `GV_Lugar` normalizado (J01…J09). El   |
--   |                          | viejo compara `upper(btrim(sector))` como TEXTO, así |
--   |                          | que 'J1' <> 'J01' y los daba por inexistentes.        |
--   | 9  solo_mapa             | misma causa: el par existe en las dos tablas pero con |
--   |                          | el sector escrito distinto.                           |
--   | 54 solo_capacidad        | son las 54 filas cuyo `cod` es 'Libre' — o sea celdas |
--   |                          | declaradas VACÍAS. Una celda vacía no es una          |
--   |                          | divergencia, es una celda vacía.                      |
--   | 19 solo_mapa + 16 solo_capacidad = **35 reales**                              |
--
-- `gv_planimetria_celda` no tiene ninguno de los tres problemas: parte el sector en
-- (góndola, celda) con `substring`/`regexp_replace`, así que J1 y J01 son la misma
-- celda; excluye `cod ~* '^\s*libre\s*$'`; y compara por `gv_cod_stock()`. O sea que
-- el centinela ya estaba escrito, mejor, adentro del mapa. Esto sólo lo expone con
-- los nombres de columna que el centinela viejo ya tenía, para no romper a nadie.
--
-- ⚠ El problema 84 está anclado al 107. El número que vale ahora es 35.
--
-- CONSUMIDORES: ninguno. Verificado el 14/09 — 0 funciones, 0 vistas, 0 crons y 0
-- apariciones en el front (`grep -rn gv_gondola_divergente`). Se consulta a mano.
-- Por eso se puede DROP + CREATE sin cascada.
--
-- ROLLBACK: el CREATE viejo, entero, está al pie de este archivo.
-- ════════════════════════════════════════════════════════════════════

drop view if exists public.gv_gondola_divergente;

create view public.gv_gondola_divergente
  with (security_invoker = true)
as
select
  m.estado                                        as motivo,
  m.cod,
  m.sector,
  m.cajas_max,
  case m.estado
    when 'solo_mapa'      then 'el mapa pone el artículo en esta celda pero no tiene capacidad cargada: el generador de OC y "llenar góndola" no saben cuántas cajas entran'
    when 'solo_capacidad' then 'hay capacidad cargada para este código en esta celda pero el mapa no lo pone ahí: el operario no lo va a encontrar'
  end                                             as que_pasa
from public.gv_planimetria_celda m
where m.estado in ('solo_mapa', 'solo_capacidad');

comment on view public.gv_gondola_divergente is
  'Centinela: celdas donde el mapa (GV_Lugar_Item) y la capacidad (Capacidad_Sector) no dicen lo mismo. Vacía = todo bien. v17.26: se deriva de gv_planimetria_celda, que normaliza el sector, saltea las celdas "Libre" y compara por gv_cod_stock — el centinela anterior no hacía ninguna de las tres y por eso inflaba 107 contra 35 reales.';

-- Uso:  select * from public.gv_gondola_divergente order by motivo, sector;
-- Conteo por motivo:
--   select motivo, count(*) from public.gv_gondola_divergente group by 1 order by 2 desc;

-- ════════════════════════════════════════════════════════════════════
-- ROLLBACK — definición v16.50, tal como estaba antes de este archivo
-- ════════════════════════════════════════════════════════════════════
-- drop view if exists public.gv_gondola_divergente;
-- create view public.gv_gondola_divergente with (security_invoker = true) as
--  WITH cs AS (
--          SELECT gv_cod_stock("Capacidad_Sector".cod) AS cod,
--             upper(btrim("Capacidad_Sector".sector)) AS sector,
--             max("Capacidad_Sector".cajas_max) AS cajas_max
--            FROM "Capacidad_Sector"
--           GROUP BY (gv_cod_stock("Capacidad_Sector".cod)), (upper(btrim("Capacidad_Sector".sector)))
--         ), gl AS (
--          SELECT gv_cod_stock(i.cod) AS cod,
--             upper(btrim(i.sector)) AS sector
--            FROM "GV_Lugar_Item" i
--              JOIN "GV_Lugar" l ON upper(btrim(l.sector)) = upper(btrim(i.sector))
--           WHERE l.tipo = 'gondola'::text
--           GROUP BY (gv_cod_stock(i.cod)), (upper(btrim(i.sector)))
--         )
--  SELECT 'solo_capacidad'::text AS motivo, cs.cod, cs.sector, cs.cajas_max,
--     'la capacidad cuenta esta celda pero el mapa (GV_Lugar_Item) no pone el artículo ahí'::text AS que_pasa
--    FROM cs
--   WHERE NOT (EXISTS ( SELECT 1 FROM gl WHERE gl.cod = cs.cod AND gl.sector = cs.sector))
--     AND (EXISTS ( SELECT 1 FROM "GV_Lugar" l WHERE upper(btrim(l.sector)) = cs.sector))
-- UNION ALL
--  SELECT 'solo_mapa'::text AS motivo, gl.cod, gl.sector, NULL::numeric AS cajas_max,
--     'el mapa muestra el artículo en esta celda pero no tiene capacidad cargada (Capacidad_Sector)'::text AS que_pasa
--    FROM gl
--   WHERE NOT (EXISTS ( SELECT 1 FROM cs WHERE cs.cod = gl.cod AND cs.sector = gl.sector))
-- UNION ALL
--  SELECT 'sector_inexistente'::text AS motivo, cs.cod, cs.sector, cs.cajas_max,
--     'la capacidad apunta a un sector que no existe en GV_Lugar'::text AS que_pasa
--    FROM cs
--   WHERE NOT (EXISTS ( SELECT 1 FROM "GV_Lugar" l WHERE upper(btrim(l.sector)) = cs.sector));
