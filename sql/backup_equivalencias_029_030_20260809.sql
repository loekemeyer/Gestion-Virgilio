-- =====================================================================
-- backup_equivalencias_029_030_20260809.sql — RESTORE POINT (protocolo CLAUDE.md)
-- Migración de 029/030 de Equivalencias_Codigos (badge facturación, ya sacado en v8.58)
-- a Equivalencias_Familia (módulo "Cambiar código", secundario→principal), confirmado por el
-- usuario: 029 secundario → 437E primario, 030 secundario → 438E primario.
--
-- Restore: borrar de Familia los cod_secundario 029/030 y re-insertar en Codigos estas filas.
INSERT INTO "Equivalencias_Codigos" (cod_pedido,cod_real,nota) VALUES ('029','437E LK','Colador 16cm importado — stock de Loekemeyer');
INSERT INTO "Equivalencias_Codigos" (cod_pedido,cod_real,nota) VALUES ('030','438E LK','Colador 20cm importado — stock de Loekemeyer');
-- =====================================================================
