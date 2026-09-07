-- BACKUP · GV_PPP_Prog_Override — ANTES de adelantar la tanda del cliente 2533 al miércoles
-- 2026-09-07 ~01:00 ART · proyecto Virgilio (hrxfctzncixxqmpfhskv)
--
-- QUÉ SE PIDIÓ. Dueño 07/09: "la tanda del cliente 2533 adelantala para el miércoles y posterga lo del
-- miércoles que necesites al jueves".
--
-- QUÉ SE HIZO.
--   · D66B (Osa Distribuidora SRL "Chemelo", cod 2533, Zona 1 - CABA Sur, 2 NP, 4,041 m³):
--       jue 10/09 → mié 09/09.  [vuelve a la fecha que tenía antes de la reprogramación del 06/09]
--   · El camión de GBA Sur del miércoles ENTERO pasa al jueves, para hacerle lugar (4,368 m³):
--       D60F (98603, 3,014) · D60B (98534, 98535, 0,736) · D60A (98494/95/96, 0,550) · D60C (98530, 0,068)
--       mié 09/09 → jue 10/09.
--   · NO se tocó D62A (súper La Anónima, 2,992 m³): es súper y además YA ESTÁ EMPEZADA (EP/PKC/PSP/PUB/TP
--     desde el 03/09). Tampoco D60E (Zona 5 - GBA Oeste, 0,214), que no hacía falta mover.
--
-- Ninguna de las tandas movidas tiene eventos de operarios (verificado en Registros_Produccion_Virgilio).
-- Son NP de ISIS: se pisan por GV_PPP_Prog_Override, sin tocar la tabla compartida PPP_Programacion_Diaria.
--
-- RESULTADO: mié 09 7,574 → 7,247 m³ (súper + GBA Oeste + Capital) · jue 10 7,776 → 8,103 m³
--            (Capital + GBA Sur). Los dos días ya venían por encima del cupo de 6,00.
--
-- RESTORE: ejecutar los 9 updates de abajo (deja todo como estaba tras la reprogramación del 06/09).

update public."GV_PPP_Prog_Override" set fecha_entrega = '2026-09-09'::date, nota = 'v13.60 2026-09-06 · dueño: "pasemos los del 8 al 9 y así vamos avanzando" (lun 7 feriado, nada armado): D60A 2026-09-08 → 2026-09-09' where np = '98494';
update public."GV_PPP_Prog_Override" set fecha_entrega = '2026-09-09'::date, nota = 'v13.60 2026-09-06 · dueño: "pasemos los del 8 al 9 y así vamos avanzando" (lun 7 feriado, nada armado): D60A 2026-09-08 → 2026-09-09' where np = '98495';
update public."GV_PPP_Prog_Override" set fecha_entrega = '2026-09-09'::date, nota = 'v13.60 2026-09-06 · dueño: "pasemos los del 8 al 9 y así vamos avanzando" (lun 7 feriado, nada armado): D60A 2026-09-08 → 2026-09-09' where np = '98496';
update public."GV_PPP_Prog_Override" set fecha_entrega = '2026-09-09'::date, nota = 'v13.60 2026-09-06 · dueño: "pasemos los del 8 al 9 y así vamos avanzando" (lun 7 feriado, nada armado): D60C 2026-09-08 → 2026-09-09' where np = '98530';
update public."GV_PPP_Prog_Override" set fecha_entrega = '2026-09-09'::date, nota = 'v13.60 2026-09-06 · dueño: "pasemos los del 8 al 9 y así vamos avanzando" (lun 7 feriado, nada armado): D60B 2026-09-08 → 2026-09-09' where np = '98534';
update public."GV_PPP_Prog_Override" set fecha_entrega = '2026-09-09'::date, nota = 'v13.60 2026-09-06 · dueño: "pasemos los del 8 al 9 y así vamos avanzando" (lun 7 feriado, nada armado): D60B 2026-09-08 → 2026-09-09' where np = '98535';
update public."GV_PPP_Prog_Override" set fecha_entrega = '2026-09-09'::date, nota = 'v13.60 2026-09-06 · dueño: "pasemos los del 8 al 9 y así vamos avanzando" (lun 7 feriado, nada armado): D60F 2026-09-08 → 2026-09-09' where np = '98603';
update public."GV_PPP_Prog_Override" set fecha_entrega = '2026-09-10'::date, nota = 'v13.60 2026-09-06 · dueño: "pasemos los del 8 al 9 y así vamos avanzando" (lun 7 feriado, nada armado): D66B 2026-09-09 → 2026-09-10' where np = '98650';
update public."GV_PPP_Prog_Override" set fecha_entrega = '2026-09-10'::date, nota = 'v13.60 2026-09-06 · dueño: "pasemos los del 8 al 9 y así vamos avanzando" (lun 7 feriado, nada armado): D66B 2026-09-09 → 2026-09-10' where np = '98667';
