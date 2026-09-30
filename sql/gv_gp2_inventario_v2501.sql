-- v25.01 (Thomas, 30/09): Gestion Virgilio LEE el stock de insumos de GP2.
-- GP2 vive en el MISMO proyecto (hrxfctzncixxqmpfhskv), schema "GP2". Estas vistas son solo lectura;
-- la fuente sigue siendo "GP2".inventario (GP2 no lee nada de public: la regla 0 de GP2 no se toca).
-- Al 30/09: 1.137 filas, 684 componentes, 5 filas con stock (a GP2 le faltan los datos, no el pipeline).
-- Rollback: drop view public.gv_gp2_stock_componente; drop view public.gv_gp2_inventario;
create or replace view public.gv_gp2_inventario with (security_invoker = true) as
select i.id, c.id componente_id, c.codigo, c.descripcion, s.nombre sector, c.unidad_medida,
       c.codigo_virgilio, c.proveedor, u.tipo ubicacion_tipo, u.nombre ubicacion,
       i.cantidad, i.maximo, i.maximo_origen, i.actualizado_en, coalesce(c.discontinuado,false) discontinuado
  from "GP2".inventario i
  join "GP2".componente c on c.id = i.componente_id
  join "GP2".ubicacion u on u.id = i.ubicacion_id
  left join "GP2".sector s on s.id = c.sector_id;
create or replace view public.gv_gp2_stock_componente with (security_invoker = true) as
select componente_id, codigo, descripcion, sector, unidad_medida, codigo_virgilio, proveedor,
       sum(cantidad) cantidad, sum(maximo) maximo, count(*) ubicaciones,
       count(*) filter (where cantidad <> 0) ubicaciones_con_stock, max(actualizado_en) actualizado_en
  from public.gv_gp2_inventario group by 1,2,3,4,5,6,7;
revoke insert, update, delete, truncate on public.gv_gp2_inventario, public.gv_gp2_stock_componente from anon, authenticated;
grant select on public.gv_gp2_inventario, public.gv_gp2_stock_componente to anon, authenticated;
-- Chequeo (como anon, que es lo que usa el navegador): 1.137 / 684.
