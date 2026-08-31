-- ============================================================================
-- ALTA TALLERISTA OSCAR — LÍNEA LK (2026-08-31)
--
-- Problema: Oscar figuraba en "Codigos X Tallerista" con Codigo NULL en LK y CH
-- → su botón en Recepción aparecía deshabilitado ("Este tallerista no trabaja
-- para...") y las recepciones suyas se cargaban por Log/Fabr. Además sus
-- artículos en "Articulos Virgilio X Tallerista" estaban mezclados: algunos con
-- Cod_Tallerista='0001' (el código de Log/ Fabr — por eso aparecían en la
-- grilla de Log/Fabr) y otros con NULL (no aparecían en ninguna).
--
-- Cambio (pedido del usuario): Oscar puede entregar, todos LK:
--   500, 506, 510, 555, 557, 558, 654, 658, 659
-- Se le asigna código propio REAL '3709' (dado por el usuario;
-- si después aparece un código ISIS real, se cambia en las dos tablas y listo),
-- se normalizan sus filas LK a ese código, se borran los duplicados que estaban
-- bajo 0001, y se agrega el 658 (solo existía para Log/Fabr).
--
-- NO se toca: Oscar en línea CH (queda sin código → botón CH deshabilitado),
-- ni sus filas CH, ni las filas LK de Oscar fuera de la lista pedida
-- (280, 759, 762, 764, 769 — quedan como estaban, ver nota al final).
-- ============================================================================

-- ── BACKUP (estado previo, restore-ready) ───────────────────────────────────
-- "Codigos X Tallerista" (Oscar):
--   ('Oscar','CH',NULL) · ('Oscar','LK',NULL)
-- Revert: UPDATE "Codigos X Tallerista" SET "Codigo"=NULL WHERE "Nombre"='Oscar' AND "Linea"='LK';
--
-- "Articulos Virgilio X Tallerista" — filas LK de Oscar afectadas (id → estado previo):
--   id  89: 500 Cod_Tallerista=NULL     id 310: 506 NULL      id 203: 510 NULL
--   id 150: 558 NULL                    id 225: 555 NULL      id  14: 557 NULL
--   id  15: 654 NULL                    id 305: 659 '0001'
-- Duplicados borrados (restaurar con los INSERT de abajo si hace falta):
--   INSERT INTO "Articulos Virgilio X Tallerista" (id,"Linea","Cod_Art","Desc","Tallerista","Uni_x_Caja","Cod_Tallerista","Kg Recibido","destino_entrega","sector_factura","Cajas_x_Master") VALUES
--     (590,'LK','555','Cepillo Limpia Bombilla  ','Oscar',36,'0001',0,'virgilio',NULL,NULL),
--     (617,'LK','557','Bombilla Resorte Chata   ','Oscar',24,'0001',0,'virgilio',NULL,NULL),
--     (542,'LK','654','Bombilla Autolimpiante In','Oscar',24,'0001',0,'virgilio',NULL,NULL);
-- Revert de los updates de artículos:
--   UPDATE "Articulos Virgilio X Tallerista" SET "Cod_Tallerista"=NULL  WHERE id IN (89,310,203,150,225,14,15);
--   UPDATE "Articulos Virgilio X Tallerista" SET "Cod_Tallerista"='0001' WHERE id = 305;
--   DELETE FROM "Articulos Virgilio X Tallerista" WHERE "Tallerista"='Oscar' AND "Linea"='LK' AND "Cod_Art"='658';

-- ── CAMBIO ──────────────────────────────────────────────────────────────────
begin;

-- 1) Código propio para Oscar en LK → habilita su botón en Recepción.
update "Codigos X Tallerista" set "Codigo"='3709'
 where "Nombre"='Oscar' and "Linea"='LK';

-- 2) Sus artículos LK pasan a su código (estaban en NULL o en 0001).
update "Articulos Virgilio X Tallerista" set "Cod_Tallerista"='3709'
 where id in (89,310,203,150,225,14,15,305);

-- 3) Duplicados LK bajo 0001 (misma fila que ya quedó en 3709): fuera.
delete from "Articulos Virgilio X Tallerista" where id in (590,617,542);

-- 4) 658 no existía para Oscar: se clona del maestro de Log/Fabr LK.
insert into "Articulos Virgilio X Tallerista"
  ("Linea","Cod_Art","Desc","Tallerista","Uni_x_Caja","Cod_Tallerista","Kg Recibido","destino_entrega","sector_factura","Cajas_x_Master")
select "Linea","Cod_Art","Desc",'Oscar',"Uni_x_Caja",'3709',0,"destino_entrega","sector_factura","Cajas_x_Master"
  from "Articulos Virgilio X Tallerista"
 where "Linea"='LK' and "Cod_Art"='658' and "Tallerista"='Log/ Fabr'
 limit 1;

commit;

-- ── VERIFICACIÓN ────────────────────────────────────────────────────────────
-- Debe dar: cod_oscar_lk='3709' y arts='500,506,510,555,557,558,654,658,659'
select (select "Codigo" from "Codigos X Tallerista" where "Nombre"='Oscar' and "Linea"='LK') as cod_oscar_lk,
       (select string_agg("Cod_Art", ',' order by "Cod_Art")
          from "Articulos Virgilio X Tallerista"
         where "Cod_Tallerista"='3709' and "Linea"='LK') as arts;

-- ── PENDIENTE / NOTA ────────────────────────────────────────────────────────
-- Quedan filas de Oscar SIN tocar (fuera de la lista del usuario): LK 280, 759,
-- 762, 764, 769 (algunas bajo 0001 → siguen mostrándose en la grilla Log/Fabr)
-- y todas sus filas CH. Si Oscar también entrega alguna de esas, repetir el
-- patrón de arriba (update a '3709' + borrar duplicado si lo hay).
