-- Backfill de faltantes (cajas_falto/cajas_entregadas) para las 20 NPs
-- que quedaron backfilleadas con falto=0 (ids 9805..10052). Complementa
-- sql/backfill_entregas_virgilio_20260831.sql y sql/fix_canon_col_security_definer_20260831.sql
--
-- FUENTE
-- Registros_Produccion_Virgilio.opcion='PKC' con texto="TANDA|COD|pedidas|pickeadas".
-- La diferencia pedidas-pickeadas por (tanda, cod normalizado sin 'E' final)
-- es el faltante que el picking dejó a la tanda. Se reparte proporcionalmente
-- entre las NPs de la tanda que pidieron ese cod (mismo criterio que
-- _compAsigProporcional en index.html), acotado a las cajas pedidas por la NP.
-- Cuando una tanda tiene una sola NP con ese cod (caso mayoritario) el faltante
-- va todo a esa NP. Solo se actualiza donde falta_np>0.
--
-- Se toma la ÚLTIMA fila PKC por (tanda, cod) porque PKC es upsertable
-- (isUpsert=true en enqueueReport).
--
-- REVERT
--   UPDATE "Entregas_Virgilio"
--   SET cajas_falto=0, cajas_entregadas=cajas_pedidas
--   WHERE id BETWEEN 9805 AND 10052;
--
-- CAVEATS
-- - No cubre faltantes manuales que el operario agregue en el paso "Faltantes"
--   del asistente Completar SIN que PKC lo refleje. Ese caso es raro (el
--   asistente reparte a partir del PKC en primer lugar) y no queda registro
--   server-side.

WITH last_pkc AS (
  SELECT DISTINCT ON (split_part(texto,'|',1), upper(trim(regexp_replace(split_part(texto,'|',2),'E$',''))))
    split_part(texto,'|',1) AS tanda,
    upper(trim(regexp_replace(split_part(texto,'|',2),'E$',''))) AS cod_norm,
    (split_part(texto,'|',3))::numeric AS pedidas,
    (split_part(texto,'|',4))::numeric AS pickeadas,
    ts_cliente
  FROM "Registros_Produccion_Virgilio"
  WHERE opcion='PKC' AND created_at >= '2026-08-28 12:42:25+00'
  ORDER BY 1,2,ts_cliente DESC
),
tanda_falta AS (
  SELECT tanda, cod_norm, sum(pedidas-pickeadas) AS falta_tanda
  FROM last_pkc GROUP BY 1,2 HAVING sum(pedidas-pickeadas) > 0
),
nps_pedido AS (
  SELECT e.id, e.tanda, e.np, upper(trim(regexp_replace(e.cod_art,'E$',''))) AS cod_norm, e.cajas_pedidas
  FROM "Entregas_Virgilio" e
  WHERE e.id BETWEEN 9805 AND 10052
),
tanda_pedido AS (
  SELECT tanda, cod_norm, sum(cajas_pedidas) AS total_pedido
  FROM nps_pedido GROUP BY 1,2
),
asig AS (
  SELECT np.id, np.cajas_pedidas,
         LEAST(np.cajas_pedidas, round(tf.falta_tanda * np.cajas_pedidas::numeric / NULLIF(tp.total_pedido,0))) AS falta_np
  FROM nps_pedido np
  JOIN tanda_falta tf USING (tanda, cod_norm)
  JOIN tanda_pedido tp USING (tanda, cod_norm)
)
UPDATE "Entregas_Virgilio" e
SET cajas_falto = a.falta_np,
    cajas_entregadas = e.cajas_pedidas - a.falta_np
FROM asig a
WHERE e.id = a.id AND a.falta_np > 0;
