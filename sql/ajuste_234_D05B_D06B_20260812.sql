-- =====================================================================
--  ajuste_234_D05B_D06B_20260812.sql
--  Ajuste de stock: 8 cajas del art 234 facturadas que nunca se descontaron.
--
--  QUÉ PASÓ
--    Tandas D05B (NPs 98140/98141/98142/98143) y D06B (98151/98154/98155),
--    pickeadas el 04/08. En el picking el operario registró que NO encontró
--    ninguna caja del art 234:
--       PKC  D05B|234|5|0     (esperado 5, real 0)
--       PKC  D06B|234|3|0     (esperado 3, real 0)
--    El pipeline hizo lo correcto: real=0 → no bajó nada de góndola, el 234
--    nunca entró a separar_pedidos ni a a_facturar, y la ETAPA 3 (facturado)
--    no tuvo nada que drenar. Por eso el 234 NO tiene ningún movimiento en
--    esas dos tandas, mientras los otros 25/16 artículos sí descontaron
--    (D05B facturado -160, D06B -112).
--    PERO las cajas SÍ salieron y se facturaron (confirmado por el usuario).
--    Nadie corrió "Completar Pedido" (CP), que es el mecanismo previsto para
--    esto — en las NPs vecinas de esos mismos días (98110, 98120, 98144,
--    98265) el 234 sí se completó por CP.
--    Resultado: 8 cajas fantasma de más en el stock del sistema.
--
--  DESGLOSE (de PPP_Base_Pedidos)
--    D05B → 98140: 2 + 98142: 3  = 5
--    D06B → 98154: 2 + 98155: 1  = 3
--                                 ---
--                                   8
--
--  ESTADO PREVIO (saldo del art 234 por depósito, 2026-08-12)
--    terminado        10.0     <-- de acá se descuenta
--    a_facturar        1
--    a_guardar         0
--    excedente         0
--    separar_pedidos   0
--    (post-ajuste esperado: terminado = 2.0)
--
--  POR QUÉ terminado: el 234 nunca entró al circuito picking→a_facturar, así
--  que las 8 cajas quedaron en el bucket vendible (terminado). No se usa
--  tipo='facturado' a propósito: ese tipo drena a_facturar y está bajo el
--  índice único `mov_stock_pipeline_dedup` (tanda,art,depósito,tipo) — meter
--  un 'facturado' acá podría chocar/confundir a la ETAPA 3 del cron.
--
--  ⚠ NOTA DE ALCANCE: esto NO es un caso aislado. Mismo patrón (faltó en el
--  picking + tanda facturada + sin CP): 1.651 cajas en 136 tandas desde el
--  cutoff. NO todas son fuga — sólo lo son las que efectivamente salieron y
--  se facturaron (hay que cotejar contra la factura del ERP). Otras 553 cajas
--  en 36 tandas sí se resolvieron con CP.
-- =====================================================================

-- ---------- APLICAR ----------
INSERT INTO "Movimientos_Stock"
  (ts, cod_art, descripcion, deposito, delta, tipo, ref, legajo, client_id)
VALUES
  (now(), '234', 'Ajuste: 8 cajas facturadas sin descontar (PKC real=0, sin CP). NPs 98140/98142.',
   'terminado', -5, 'ajuste', 'D05B|FIX_234_FACTURADO_SIN_PICKING_20260812', 'reconcilia',
   'fix_234_d05b_20260812'),
  (now(), '234', 'Ajuste: 8 cajas facturadas sin descontar (PKC real=0, sin CP). NPs 98154/98155.',
   'terminado', -3, 'ajuste', 'D06B|FIX_234_FACTURADO_SIN_PICKING_20260812', 'reconcilia',
   'fix_234_d06b_20260812');

-- ---------- REVERTIR (restore) ----------
-- El cambio es sólo-inserción: no toca ni borra ninguna fila existente, así
-- que revertir es exacto y basta con borrar estas dos filas por client_id.
--
--   DELETE FROM "Movimientos_Stock"
--   WHERE client_id IN ('fix_234_d05b_20260812', 'fix_234_d06b_20260812');

-- ---------- VERIFICAR ----------
--   SELECT deposito, sum(delta) AS saldo
--   FROM "Movimientos_Stock" WHERE upper(trim(cod_art)) = '234'
--   GROUP BY 1 ORDER BY 1;      -- terminado debe quedar en 2.0
