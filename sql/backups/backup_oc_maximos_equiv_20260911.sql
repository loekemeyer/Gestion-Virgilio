-- Backup previo a los cambios del 2026-09-11 (pedidos por Luis).
-- Proyecto Gestión Virgilio hrxfctzncixxqmpfhskv.
-- Restore: correr estas 3 sentencias.

update public."OC_Maximos" set linea='' where cod='580';
update public."Equivalencias_Codigos" set nota='unificacion: 438EL = 438E CH' where cod_pedido='438EL';
update public."Equivalencias_Codigos" set nota='unificacion: 439EL (pickeado) = 439E CH' where cod_pedido='439EL';
