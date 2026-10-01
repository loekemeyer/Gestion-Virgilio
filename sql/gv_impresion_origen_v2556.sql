-- v25.56 (Luis, D5, 01/10): Impresion_NP dice por dónde salió cada hoja.
--   gv_origen = 'estacion' (la estación de auto-impresión, sola al TP / TAL) | 'cola' (Cola de impresión NP)
--   NULL = anterior al 01/10 o Producción Virgilio. Columna nullable, sin default, sin backfill.
alter table public."Impresion_NP" add column if not exists gv_origen text;
-- Chequeo: select np, impreso_en, gv_origen from public."Impresion_NP" order by impreso_en desc limit 20;
-- Rollback: alter table public."Impresion_NP" drop column gv_origen;
