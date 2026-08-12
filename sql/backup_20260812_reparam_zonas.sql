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
