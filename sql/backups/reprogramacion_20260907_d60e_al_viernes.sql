-- BACKUP · GV_PPP_Prog_Override — ANTES de pasar D60E al viernes 11
-- 2026-09-07 ~09:40 ART · proyecto Virgilio (hrxfctzncixxqmpfhskv)
--
-- POR QUÉ. Tras adelantar D66B (Chemelo) al miércoles 9 (ver reprogramacion_20260907_2533_al_miercoles.sql),
-- D60E quedó SOLA ese día: Betbeze Gimenez Nahuel, Av. Luro 6099, Gregorio de Laferrere (La Matanza), 0,214 m³
-- = un camión de GBA Oeste entero para una sola parada. El dueño preguntó si no quedaba suelta y a qué distancia
-- estaba de D66B: ~13 km en línea recta, sectores B (Capital Sur) y M (GBA Oeste) que NO son vecinos → nunca van
-- en el mismo camión. Se pasa al viernes 11, que ya tiene camión de GBA Oeste con 4,313 m³ (E07A).
-- Dueño: "pasala al viernes 11".
--
-- RESTORE: ejecutar los 2 updates de abajo (vuelve al miércoles 9).
update public."GV_PPP_Prog_Override" set fecha_entrega = '2026-09-09'::date, nota = 'v13.60 2026-09-06 · dueño: "pasemos los del 8 al 9 y así vamos avanzando" (lun 7 feriado, nada armado): D60E 2026-09-08 → 2026-09-09' where np = '98532';
update public."GV_PPP_Prog_Override" set fecha_entrega = '2026-09-09'::date, nota = 'v13.60 2026-09-06 · dueño: "pasemos los del 8 al 9 y así vamos avanzando" (lun 7 feriado, nada armado): D60E 2026-09-08 → 2026-09-09' where np = '98533';
