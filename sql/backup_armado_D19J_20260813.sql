-- =====================================================================
--  backup_armado_D19J_20260813.sql
--  BACKUP de los eventos de ARMADO de la tanda D19J (NPs 44529 / 44530)
--  ANTES de borrarlos.
--
--  QUÉ PASÓ
--    El 12/08 quedaron registrados AP (11:16) y TAP (11:41) por el legajo 122,
--    más los dos TAL (líos por NP: 44529 → 8 líos, 44530 → 2 líos).
--    El usuario confirmó que **el pedido NO se armó de verdad**: los eventos se
--    emitieron sin que el trabajo se hiciera.
--    Con el TAP puesto, la tanda no vuelve a ofrecerse para armar: el filtro de
--    AP excluye las que ya tienen TAP (`armadoDoneStrict`). Y con AP solo,
--    tampoco: quedaría como "armado en curso" (`armadoEnCursoBy`). Por eso se
--    borran LOS DOS, más los TAL que salieron con ese TAP.
--
--  STOCK: NO se toca. El TAP ya había movido separar_pedidos → a_facturar
--    (36 filas tipo 'separado') y después la facturación drenó a_facturar
--    (18 filas tipo 'facturado'). Cuando se rearme de verdad, el pipeline NO
--    duplica: el índice único `mov_stock_pipeline_dedup`
--    (ref, cod_art, deposito, tipo) hace que el segundo TAP no inserte nada.
--
--  ⚠ QUEDA UNA INCONSISTENCIA PARA REVISAR APARTE (no la resuelve este archivo):
--    las dos NP figuran FACTURADAS y con carga al camión (CRA 12/08 11:12),
--    o sea el sistema dice que salieron, pero físicamente no estaban armadas.
--
--  RESTORE: ejecutar los INSERT de abajo.
-- =====================================================================

INSERT INTO "Registros_Produccion_Virgilio"
  (id, client_id, legajo, opcion, descripcion, texto, ts_cliente, ts_inicio, created_at)
VALUES
  ('d5c43c77-2e57-4e51-bdce-19f2c3c1a01e', 'msq6a0de_b3ei7c', '122', 'AP',
   'Empecé Armado Pedido', 'D19J',
   '2026-08-12 11:16:21-03', NULL, '2026-08-12 11:16:21-03'),

  ('9725cbd2-96d8-42d5-9e5d-8a420b70d5a0', 'msq76g4n_ej51bq', '122', 'TAL',
   'Líos por NP (TAP)',
   '44529|8|D19J|A=840X3;B=609X4,859X1;C=706X2,713X3;D=920X3;E=701X3,836X1;F=809EX4;G=709X1,725EX1,764X1,862X1;H=702EX2|LIO',
   '2026-08-12 11:41:34-03', NULL, '2026-08-12 11:41:34-03'),

  ('18f43fea-51b6-4bba-8080-6e36108e5b78', 'msq76g51_0ruojm', '122', 'TAL',
   'Líos por NP (TAP)',
   '44530|2|D19J|A=901X2;B=824X1,825X1,852X1|LIO',
   '2026-08-12 11:41:34-03', NULL, '2026-08-12 11:41:34-03'),

  ('47e9ff52-a1e2-454a-9a04-9e7b67617b90', 'msq76h3p_k105iu', '122', 'TAP',
   'Terminé Armado Pedido', 'D19J',
   '2026-08-12 11:41:36-03', '2026-08-12 11:16:21-03', '2026-08-12 11:41:36-03');

-- ---------- LO QUE SE EJECUTÓ PARA BORRARLOS ----------
--   DELETE FROM "Registros_Produccion_Virgilio"
--   WHERE id IN ('d5c43c77-2e57-4e51-bdce-19f2c3c1a01e',
--                '9725cbd2-96d8-42d5-9e5d-8a420b70d5a0',
--                '18f43fea-51b6-4bba-8080-6e36108e5b78',
--                '47e9ff52-a1e2-454a-9a04-9e7b67617b90');

-- =====================================================================
--  ACTUALIZACIÓN 2026-08-13 — RESTAURADO
--    El usuario confirmó que D19J SÍ está armada (armado físico real). Los
--    eventos AP/TAP/TAL de arriba se RE-INSERTARON tal cual (mismo INSERT del
--    bloque de restore). Motivo: Entregas_Virgilio (20 filas) y el stock en
--    a_facturar (35 cajas) ya reflejaban ese armado; solo faltaban estos
--    eventos para que vista_tanda_status diera 'completo' y la tanda apareciera
--    en Facturación — NPs a FC.
--    NO se restauró la carga al camión (CRA/CCN) ni la facturación: siguen
--    anuladas a propósito (ver anular_circuito_D19J_20260813.sql), porque el
--    pedido está armado pero todavía NO cargado ni facturado — justo el estado
--    para que la operadora lo tilde en Facturación.
--    Verificado: vista_tanda_status = 'completo', Facturacion_NP sin 44529/44530.
-- =====================================================================
