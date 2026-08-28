-- Entrega de PRUEBA para mostrarle el circuito al sector Pagos (2026-08-28).
-- Tallerista Poly (cod 2416, linea LK) · remito 1500 · art 513 · 250 cajas.
-- Foto: se reutilizo la del remito 38825 (no se subio archivo nuevo al bucket
-- `remitos`, asi que este script NO debe borrar nada de Storage).
--
-- Lo que se cargo (mismo orden que escribe recepcion.js en una recepcion real):
--   1. "Entregas Tallerista Virgilio"  -> id 2266   (dispara trg_recep_pagos_tall)
--   2. planify.tasks                   -> id 2696   (tarea broadcast al sector Pagos, dept 6)
--   3. "Movimientos_Stock"             -> id 23670762 (a_guardar +250, legajo 1 = Pruebas)
--   4. "Pasaje_Papeles"                -> id 92     (remito pendiente de enviar)
--   5. "Control_Modo_OP"               -> id 366    (checklist pendiente, codigo 7250, con foto)
--
-- ROLLBACK — ejecutar cuando la demo termine. Va de la punta hacia atras para no
-- dejar huerfanos. Ojo con el orden: primero la tarea de Planify, porque el trigger
-- dedupea por el marcador [vrec:...] y si se borra la entrega antes, una recarga
-- del mismo remito volveria a crearla.

begin;

-- 5. Ficha de recepcion (checklist + foto)
delete from public."Control_Modo_OP"
 where remito = '1500' and nombre = 'Poly' and codigo = '7250';

-- 4. Pasaje de Papeles
delete from public."Pasaje_Papeles"
 where numero_remito = '1500' and razon_social = 'Poly';

-- 3. Stock (saca las 250 cajas de "a guardar")
delete from public."Movimientos_Stock"
 where client_id = 'mst_prueba_pagos_1500_513';

-- 2. Tarea del sector Pagos en Planify
delete from planify.tasks
 where note like '%[vrec:tallerista|1500|POLY]%';

-- 1. La entrega
delete from public."Entregas Tallerista Virgilio"
 where "Remito" = '1500' and "Nombre_Tall" = 'Poly';

commit;

-- Control post-borrado: las 5 lineas tienen que dar 0.
-- select
--   (select count(*) from public."Entregas Tallerista Virgilio" where "Remito"='1500') as entregas,
--   (select count(*) from planify.tasks where note like '%[vrec:tallerista|1500|POLY]%') as tareas_pagos,
--   (select count(*) from public."Movimientos_Stock" where client_id='mst_prueba_pagos_1500_513') as stock,
--   (select count(*) from public."Pasaje_Papeles" where numero_remito='1500') as papeles,
--   (select count(*) from public."Control_Modo_OP" where remito='1500') as recepcion;
