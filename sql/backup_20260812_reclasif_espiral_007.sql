-- ============================================================
-- BACKUP 2026-08-12 — reclasificación espiral mal unificado: N°7 → 007
-- Contexto: el código N°7 (fleje 60×2,10, 683 Kg) tenía además 9000 Uni de
-- "Espiral (Chef)" mal unificados (ajuste 04-08 "unificación: 18 MC × 500 = 9000 Uni").
-- El espiral es un insumo DISTINTO, código 007, que estaba en 0. Se mueven las 9000 Uni
-- del espiral desde N°7 hacia 007. El fleje N°7 queda en sus 683 Kg reales.
--
-- ESTADO PREVIO (insumos):
--   N°7  = 9683  (683 Kg fleje  +  9000 Uni espiral mal unificado)
--   007  = 0     (no existía)
-- ESTADO DESPUÉS:
--   N°7  = 683 Kg (solo fleje)
--   007  = 9000 Uni (espiral)
--
-- RESTORE (revertir): borrar los dos movimientos de reclasificación.
-- ============================================================
DELETE FROM "Movimientos_Stock"
WHERE ref = 'reclasif 20260812: espiral mal unificado N°7 <-> 007'
  AND deposito = 'insumos'
  AND cod_art IN ('N°7','007');
