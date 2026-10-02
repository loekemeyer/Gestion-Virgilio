-- v26.05 (Luis, 02/10): el stock GP2 que suma Pedidos Importación es SOLO el de la parte Cervantes.
-- "tiene que sumar lo que esta en GP2 pero solo en la parte de cervantes".
-- Desde GP2 v1.224.0 (Thomas, 01/10) GP2 tiene depósitos propios EN Virgilio (virgilio_sector, la
-- ubicación "Virgilio (Distribución)" y el sector Bolsas Plásticas "(en Virgilio)"). Lo que está ahí
-- físicamente está en Virgilio: si GV lo sumaba como "stock de Cervantes" y además lo registraba como
-- insumo propio, contaba dos veces.
--
-- gv_gp2_inventario gana la columna `parte` (AL FINAL: create or replace sólo deja agregar al final):
--   virgilio  = tipo virgilio / virgilio_sector, o sector cuyo nombre dice "en Virgilio"
--   terceros  = tallerista, proveedor_servicio, proveedor_at, inyector
--   cervantes = el resto (sectores de Cervantes, Art. Terminado (Fábrica), análisis)
-- gv_gp2_stock_componente saca la parte virgilio. TERCEROS SIGUE CONTANDO (como desde la v25.61):
-- es stock de Cervantes en manos de un tallerista/PS (ej. la pieza en Fábrica antes de armarse).
--
-- Impacto medido el 02/10: 0 (ningún componente vinculado tiene stock en Virgilio ni en terceros):
-- gv_importados_ordenes 156 filas, sum(stock_gp2) 51.822, md5 63517c15283ae66e94cd71d02a640d80
-- igual antes y después.
-- Rollback: volver a correr sql/gv_gp2_inventario_v2501.sql (la columna `parte` queda; no molesta),
-- o quitar el WHERE de gv_gp2_stock_componente.
create or replace view public.gv_gp2_inventario with (security_invoker = true) as
select i.id, c.id componente_id, c.codigo, c.descripcion, s.nombre sector, c.unidad_medida,
       c.codigo_virgilio, c.proveedor, u.tipo ubicacion_tipo, u.nombre ubicacion,
       i.cantidad, i.maximo, i.maximo_origen, i.actualizado_en, coalesce(c.discontinuado,false) discontinuado,
       case when u.tipo in ('virgilio','virgilio_sector') or u.nombre ~* 'en virgilio' then 'virgilio'
            when u.tipo in ('tallerista','proveedor_servicio','proveedor_at','inyector') then 'terceros'
            else 'cervantes' end as parte
  from "GP2".inventario i
  join "GP2".componente c on c.id = i.componente_id
  join "GP2".ubicacion u on u.id = i.ubicacion_id
  left join "GP2".sector s on s.id = c.sector_id;

create or replace view public.gv_gp2_stock_componente with (security_invoker = true) as
select componente_id, codigo, descripcion, sector, unidad_medida, codigo_virgilio, proveedor,
       sum(cantidad) cantidad, sum(maximo) maximo, count(*) ubicaciones,
       count(*) filter (where cantidad <> 0) ubicaciones_con_stock, max(actualizado_en) actualizado_en
  from public.gv_gp2_inventario
 where parte <> 'virgilio'   -- v26.05: lo que GP2 tiene EN Virgilio no es stock de Cervantes
 group by 1,2,3,4,5,6,7;

alter view public.gv_gp2_inventario set (security_invoker = true);
alter view public.gv_gp2_stock_componente set (security_invoker = true);
revoke insert, update, delete, truncate on public.gv_gp2_inventario, public.gv_gp2_stock_componente from anon, authenticated;
grant select on public.gv_gp2_inventario, public.gv_gp2_stock_componente to anon, authenticated;

-- ⏸ Centinela: PENDIENTE del "sí" de Luis (D1 del 02/10). Las dos vistas de arriba ya están aplicadas.
insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
values ('gv_gp2_stock_componente','vista','parte <> ''virgilio''',
        'Importación suma sólo el stock GP2 de la parte Cervantes (sin los depósitos de GP2 en Virgilio)',
        'Luis','v26.05');
