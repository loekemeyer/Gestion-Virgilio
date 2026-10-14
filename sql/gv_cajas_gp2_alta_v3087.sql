-- v30.87 (Luis, 14/10): "dalas de alta en la parte de virgilio de GP2. que vean todas las cajas que hay para que
-- nunca les falte ningún código para recibir/enviar (tengan o no stock)".
-- Las cajas que GP2.uni_x_articulo_x_caja usa y no existían como componente: Nº 5, 8, 14, 27, 28 y P.
-- Código de Cervantes PROVISORIO CJ<n> (las 11 de siempre tienen A1…A11 por ubicación; éstas no tienen lugar en Cervantes).
with nuevas(n, cod_gp2, descr, cod_v) as (values
  ('5','CJ5','Caja N°5','Caja Nº 5'), ('8','CJ8','Caja N°8','Caja Nº 8'), ('14','CJ14','Caja N°14','Caja Nº 14'),
  ('27','CJ27','Caja N°27','Caja Nº 27'), ('28','CJ28','Caja N°28','Caja Nº 28'), ('P','CJP','Caja P','Caja P')),
comp as (
  insert into "GP2".componente (codigo, descripcion, sector_id, unidad_medida, discontinuado)
  select cod_gp2, descr, 11, 'unidad', false from nuevas
  on conflict do nothing
  returning id, codigo),
inv as (
  insert into "GP2".inventario (componente_id, ubicacion_id, cantidad)
  select c.id, u.u, 0 from comp c cross join (values (11), (77)) u(u)   -- 11 = Sector Caja · 77 = Sector Caja en Virgilio
  on conflict do nothing returning id),
gv as (
  insert into public."Insumos" (cod, nombre, categoria, creado_por)
  select cod_v, descr, 'cajas', 'v30.87 alta de cajas de GP2 (Luis)' from nuevas
  where not exists (select 1 from public."Insumos" i where upper(btrim(i.cod)) = upper(nuevas.cod_v))
  returning cod)
insert into "GP2".insumo_equivalencia (cod_virgilio, componente_id, nota, creado_por)
select upper(n.cod_v), c.id, 'v30.87 alta de cajas (Luis 14/10)', 'claude-gv'
  from nuevas n join comp c on c.codigo = n.cod_gp2
on conflict do nothing;
-- verificación: select c.codigo, c.descripcion, e.cod_virgilio from "GP2".componente c
--   left join "GP2".insumo_equivalencia e on e.componente_id = c.id where c.sector_id = 11 order by c.id;
