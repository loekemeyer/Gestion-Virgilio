-- ============================================================
-- BACKUP 2026-08-12 — reparametrización barrio→zona (correcciones geográficas)
-- Restore: ejecutar este archivo.
-- ============================================================

-- (1) Zonas_Barrios (mapeo): valores ANTERIORES
UPDATE "Zonas_Barrios" SET zona='Zona 2 - CABA Centro' WHERE barrio_norm='burzaco';   -- era Z2 Centro
UPDATE "Zonas_Barrios" SET zona='Zona 2 - CABA Centro' WHERE barrio_norm='v.devoto';  -- era Z2 Centro
DELETE FROM "Zonas_Barrios" WHERE barrio_norm='lanus';                                 -- no existía (alta nueva)

-- (2) Zona ANTERIOR de los pedidos movidos:
UPDATE "PPP_Programacion_Diaria" SET zona='Zona 2 - CABA Centro' WHERE btrim(np) IN ('97889','97964','98109');  -- Burzaco (Matiz SA)
UPDATE "PPP_Programacion_Diaria" SET zona='Zona 2 - CABA Centro' WHERE btrim(np) IN ('98213','98214');           -- V.Devoto (Regalitos SRL Suc.3)

-- ---- Ajuste 2 (23:53) — Villa Luro Z1 Sur -> Z3 Oeste (era geograficamente Oeste) ----
UPDATE "Zonas_Barrios" SET zona='Zona 1 - CABA Sur' WHERE barrio_norm='villa luro';
UPDATE "PPP_Programacion_Diaria" SET zona='Zona 1 - CABA Sur' WHERE btrim(np) IN ('98221','98223');  -- Multi Bazar, Bazar Y Cia

-- ---- Ajuste 3 (23:54) — Villa Bosch Z5 Oeste -> Z6 Norte (pedido del usuario) ----
UPDATE "Zonas_Barrios" SET zona='Zona 5 - GBA Oeste' WHERE barrio_norm='villa bosch';
UPDATE "PPP_Programacion_Diaria" SET zona='Zona 5 - GBA Oeste' WHERE btrim(np)='98241';  -- Manig S.R.L
