-- Rollback de objetos backend ALTA prioridad batch 2 (2026-08-12)
-- Ejecutar en orden inverso si hay que revertir.

DROP VIEW IF EXISTS vista_faltante_real;
DROP VIEW IF EXISTS vista_faltante_demanda;
DROP VIEW IF EXISTS vista_faltante_catalogo;
DROP VIEW IF EXISTS vista_avisar_programacion;
DROP VIEW IF EXISTS vista_racks_bajadas_pendientes;
DROP VIEW IF EXISTS vista_plata_perdida;
DROP FUNCTION IF EXISTS generar_inconsistencias(date);
DROP FUNCTION IF EXISTS gondola_return_check(jsonb);
DROP FUNCTION IF EXISTS dia_armado(date);
DROP FUNCTION IF EXISTS prox_habil(date);
