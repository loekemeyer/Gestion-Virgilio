-- Backfill Entregas_Virgilio 2026-08-31 (aplicado, ids generados 9805..10052).
--
-- CONTEXTO
-- Entre 2026-08-28 12:42:25 UTC (justo después del deploy de idea 7411) y
-- 2026-08-31 hasta la aplicación del fix v12.18, TODO INSERT de anon en
-- Entregas_Virgilio fallaba con 42501 (trigger canon → REVOKE anon). El
-- .catch de _compSaveEntregas tragaba silencioso los 4xx, así que los
-- armados se perdían sin siquiera encolar en localStorage. Resultado:
-- 24 NPs armadas (TAL en Registros_Produccion_Virgilio) sin ninguna fila
-- en Entregas_Virgilio → Facturación las escondía por el filtro v12.01
-- (que exige presencia en Entregas_Virgilio).
--
-- CRITERIO
-- Se reconstruye el pedido entero de cada NP desde PPP_Base_Pedidos
-- (una fila por artículo, cajas = cajas_pedidas). Como los faltantes solo
-- vivían en el faltMap en memoria del asistente Completar (no se guardan
-- en Registros_Produccion_Virgilio — el TAL sólo trae líos, no los
-- (cod,cajas) del faltante), el backfill setea cajas_falto=0 y
-- cajas_entregadas=cajas_pedidas. Si en alguna NP hubo faltante real,
-- la operadora facturará de más — es más seguro que no poder facturar.
-- fecha_salida y cod_cliente se toman de PPP_Programacion_Diaria por np.
--
-- IDEMPOTENCIA
-- El WHERE NOT EXISTS deja sin tocar las 4 NPs con TAL que ya tenían filas
-- (44591 D47B / 98477 D47A del 27/8 · 98581 98582 D50C del 28/8 09:42,
-- justo antes del deploy del bug). Ejecutar de nuevo no duplica.
--
-- REVERT
-- Como todas las filas del backfill quedaron con id >= 9805 y max_id
-- pre-backfill era 9793, revertir es:
--   DELETE FROM "Entregas_Virgilio" WHERE id BETWEEN 9805 AND 10052;
-- (o WHERE id > 9793 si no hubo inserts posteriores).

INSERT INTO "Entregas_Virgilio" (fecha_salida, cod_cliente, np, cod_art, cajas_pedidas, cajas_entregadas, cajas_falto, tanda)
WITH tal AS (
  SELECT DISTINCT split_part(texto, '|', 1) AS np, split_part(texto, '|', 3) AS tanda
  FROM "Registros_Produccion_Virgilio"
  WHERE opcion='TAL' AND created_at >= '2026-08-28 12:42:25+00'
), sin_dup AS (
  SELECT t.np, t.tanda FROM tal t
  WHERE t.np ~ '^\d+$'
    AND NOT EXISTS (SELECT 1 FROM "Entregas_Virgilio" e WHERE e.np = t.np)
)
SELECT
  coalesce(pd.fecha_entrega, '') AS fecha_salida,
  coalesce(pd.cod, '') AS cod_cliente,
  sd.np,
  pbp.articulo AS cod_art,
  pbp.cajas AS cajas_pedidas,
  pbp.cajas AS cajas_entregadas,
  0::numeric AS cajas_falto,
  sd.tanda
FROM sin_dup sd
JOIN "PPP_Base_Pedidos" pbp ON pbp.pedido = sd.np
LEFT JOIN "PPP_Programacion_Diaria" pd ON pd.np = sd.np
WHERE coalesce(pbp.cajas, 0) > 0 AND pbp.articulo IS NOT NULL AND pbp.articulo <> '';
