-- v16.00 (2026-09-12) — 323ES suelto: FOB 0,20 (el 323E envasado sigue 0,225)
-- Dueño, 12/09: "me cobra 0.225 el 323E, si viene suelto (323ES), es 0.2".
--
-- Dos cosas estaban mal:
--   1) Importados.323ES.fob_uni estaba en 0,225 (copiado del 323E).
--   2) La línea del pedido "323ES suelto" estaba codificada 323E, así que tomaba 0,225.
--      Por eso ese pedido daba 675 en vez de 600 (3.000 u x 0,20).
-- El PI NY26-031438 NO cambia: ahí el 323E va envasado, a 0,225 (FOB 38.639,84).

-- backups
-- create table public."GV_Importados_bkp_323ES_20260912" as
--   select * from public."Importados" where upper(cod_art) in ('323E','323ES');
-- create table public."GV_Baches_bkp_323ES_20260912" as
--   select * from public."GV_Importados_Baches" where pedido_ref = '323ES suelto';

update public."Importados" set fob_uni = 0.2 where upper(cod_art) = '323ES';
update public."GV_Importados_Baches" set cod_art = '323ES'
 where pedido_ref = '323ES suelto' and cod_art = '323E';

-- rollback
-- update public."Importados" set fob_uni = 0.225 where upper(cod_art) = '323ES';
-- update public."GV_Importados_Baches" set cod_art = '323E'
--  where pedido_ref = '323ES suelto' and cod_art = '323ES';
