-- =====================================================================
-- backup_capacidad_sector_20260809_codigos_sinE.sql — RESTORE POINT (protocolo CLAUDE.md)
-- Antes de renombrar en Capacidad_Sector los códigos mal escritos (les faltaba la E) a su
-- versión E: 102→102E, 106→106E, 124→124E, 439→439E, 877→877E (confirmado por el usuario).
-- Si el UPDATE rompe algo, restaurar: borrar las filas E creadas y re-insertar estas.
-- =====================================================================
INSERT INTO "Capacidad_Sector" (empresa,sector,cod,cajas_max) VALUES ('LOKE','Ñ05','102',96);
INSERT INTO "Capacidad_Sector" (empresa,sector,cod,cajas_max) VALUES ('LOKE','Ñ06','102',96);
INSERT INTO "Capacidad_Sector" (empresa,sector,cod,cajas_max) VALUES ('LOKE','Ñ07','102',96);
INSERT INTO "Capacidad_Sector" (empresa,sector,cod,cajas_max) VALUES ('LOKE','Ñ08','102',60);
INSERT INTO "Capacidad_Sector" (empresa,sector,cod,cajas_max) VALUES ('LOKE','Ñ09','106',120);
INSERT INTO "Capacidad_Sector" (empresa,sector,cod,cajas_max) VALUES ('LOKE','Ñ10','106',120);
INSERT INTO "Capacidad_Sector" (empresa,sector,cod,cajas_max) VALUES ('LOKE','Ñ11','106',120);
INSERT INTO "Capacidad_Sector" (empresa,sector,cod,cajas_max) VALUES ('LOKE','Ñ12','106',75);
INSERT INTO "Capacidad_Sector" (empresa,sector,cod,cajas_max) VALUES ('LOKE','Ñ30','124',105);
INSERT INTO "Capacidad_Sector" (empresa,sector,cod,cajas_max) VALUES ('LOKE','Ñ31','124',105);
INSERT INTO "Capacidad_Sector" (empresa,sector,cod,cajas_max) VALUES ('LOKE','Ñ53','439',18);
INSERT INTO "Capacidad_Sector" (empresa,sector,cod,cajas_max) VALUES ('LOKE','Ñ54','439',18);
INSERT INTO "Capacidad_Sector" (empresa,sector,cod,cajas_max) VALUES ('CH','M45','877',24);
