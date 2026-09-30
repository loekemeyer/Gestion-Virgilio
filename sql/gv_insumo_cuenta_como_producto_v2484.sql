-- v24.84 (Luis, 30/09): un importado que es INSUMO (323ES suelto) y cuyo stock cuenta como stock del producto
-- que se vende (323E LK / 838E CH), con conversión unidades-de-insumo por caja de producto.
-- APLICADO el 30/09 con el sí de Luis ("metele al 323ES In").

-- a) la regla lleva la conversión (NULL = como antes: 1 unidad de la parte por unidad del producto)
alter table public."Importados_Stock_Parte" add column if not exists parte_x_caja numeric;
-- b) el insumo, en unidades
insert into public."Insumos" (cod, nombre, categoria, creado_por) values ('323ES In','Rallador 4 Lados Mini Suelto','importados','luis_30092026');
insert into public."Insumos_Factores" (cod_art, unidad, factor, es_base, actualizado) values ('323ES In','Uni',1,true,now());
-- c) recibir el pedido 323ES = ingresa el insumo 323ES In
insert into public."GV_Importados_Insumo_Map" (insumo_cod, importado_cod, nota)
values ('323ES In','323ES','suelto para envasar como 323E (LK) y 838E (CH) — Luis 30/09');
-- d) 12 u de 323ES In = 1 caja de 323E y 1 caja de 838E (es POSIBILIDAD de armar: sólo apaga el cartel)
insert into public."Importados_Stock_Parte" (terminado, parte, parte_x_caja) values ('323E','323ES In',12), ('838E','323ES In',12);

-- e) gv_reingresos_feed: el CTE `parte` pasa a ser una fila por regla, y el disponible suma
--    floor(stock de la parte / coalesce(parte_x_caja, UxB del producto)). Parche por texto sobre la
--    definición viva (ver la sesión); centinela id 255 (patrón coalesce\(pt\.parte_x_caja, i\.uxc\)).
--    Probado en transacción abortada: +3000 u de 323ES In -> 323E y 838E con sin_stock = false.

-- f) ETA vencida (D9): gv_importados_eta_vencida(p_simular default true, p_dias default 7) + log
--    GV_Importados_ETA_Log. El cron NO está activado todavía (espera el sí): al activarlo mueve 20 pedidos
--    (19 del PI B260601 del 29/09 y el 323ES del 22/09) al 07/10.
--    select cron.schedule('gv-importados-eta-vencida', '7 3 * * *', 'select count(*) from public.gv_importados_eta_vencida(false)');

-- Rollback:
-- delete from public."Importados_Stock_Parte" where parte = '323ES In';
-- delete from public."GV_Importados_Insumo_Map" where insumo_cod = '323ES In';
-- delete from public."Insumos_Factores" where cod_art = '323ES In';
-- delete from public."Insumos" where cod = '323ES In';
