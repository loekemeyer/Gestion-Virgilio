-- ============================================================
-- BACKUP 2026-08-12 — reconciliación 3 bajadas de racks colgadas (leg 237, propuesta sin mover stock)
-- Restore: ejecutar este archivo.
-- ============================================================
-- (1) borrar los movimientos de reconciliación:
DELETE FROM "Movimientos_Stock" WHERE ref='reconc bajada leg237 20260812' AND tipo='baja_racks';
-- (2) volver las 3 bajadas a 'propuesta':
UPDATE "Racks_Bajadas" SET estado='propuesta', aprobada_at=NULL WHERE id IN (70,71,72);
