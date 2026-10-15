-- 440E de X21/X23 vuelve a INSUMO (Luis, 15/10/2026: "Mala mía. Esos que hay son insumos"). Corrige la v30.30 del 14/10.
-- Aplicado por MCP con el «D14 sí». Verificado: racks producto 0 · insumo 528 Uni · posiciones de insumo X21/X23 ok.
create table if not exists zz_backups."GV_440E_a_insumo_v3121" as
  select * from public."Movimientos_Stock" where upper(btrim(cod_art))='440E' and deposito in ('racks','insumos');
alter table zz_backups."GV_440E_a_insumo_v3121" enable row level security;
insert into public."Movimientos_Stock"(cod_art, deposito, delta, tipo, unidad, ubicacion, empresa, ref, legajo, descripcion) values
 ('440E','racks',-168,'ajuste','inner','X21','LK','440E producto -> insumo (Luis 15/10, corrige 14/10)','0','Luis 15/10: lo de X21 es insumo'),
 ('440E','racks',-360,'ajuste','inner','X23','LK','440E producto -> insumo (Luis 15/10, corrige 14/10)','0','Luis 15/10: lo de X23 es insumo'),
 ('440E','insumos',528,'ajuste','Uni',null,'Mixto','440E producto -> insumo (Luis 15/10, corrige 14/10)','0','Luis 15/10: 44 MC x 12 = 528 u en X21/X23');
insert into public."Insumos_Ubicaciones"(cod, sector, cantidad, notas) values
 ('440E','X21',0,'Luis 15/10: 14 MC'), ('440E','X23',0,'Luis 15/10: 30 MC');
-- ROLLBACK: insertar los tres movimientos con el signo contrario y borrar las 2 filas de Insumos_Ubicaciones (cod 440E, X21/X23).
