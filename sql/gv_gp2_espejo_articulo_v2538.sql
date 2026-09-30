-- v25.38 (2026-09-30) — GP2 ve el stock de ARTÍCULOS de Virgilio (espejo de solo lectura)
--
-- [usuario 30/09, Stock General de GP2] "que haya 3 box: 1) Cervantes … 2) Virgilio: Bolsas Plásticas,
-- SC, SP, Plásticos, Flejes, Cajas, Art. Terminado 3) Terceros". El «Art. Terminado» de la caja
-- Virgilio es el stock REAL de Virgilio de los artículos que arma Fábrica: vive en public
-- (stocks_carga_rapida) y GP2 no lee public (Regla 0). Mismo molde que la v25.17
-- (virgilio_insumo_stock / _ubicacion / virgilio_lugar): esta función reescribe
-- "GP2".virgilio_articulo_stock sólo si cambió el md5. La tabla la crea GP2
-- (db/migracion_tablet_virgilio.sql del repo gestion-productiva-2.0).
--
-- Sólo se AGREGA el bloque 4; los bloques 1-3 son los de la v25.17, copiados de la definición viva.
-- Rollback: volver a correr sql/gv_gp2_espejo_v2517.sql (la función sin el bloque 4).

CREATE OR REPLACE FUNCTION public.gv_gp2_espejo_sync()
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare h_new text; h_old text; out text := '';
begin
  -- 1) stock de insumos
  select md5(coalesce(string_agg(concat_ws('|',cod,unidad,nombre,categoria,saldo,ubicacion), '#' order by cod, unidad),'')) into h_new from (
    select m.cod_art cod, coalesce(m.unidad,'') unidad, max(vi.nombre) nombre, max(vi.categoria) categoria,
           round(sum(m.delta),4) saldo, max(nullif(vi.ubicacion,'')) ubicacion
      from public."Movimientos_Stock" m left join public.vista_insumos vi on vi.cod = m.cod_art
     where m.deposito='insumos' group by 1,2) z;
  select md5(coalesce(string_agg(concat_ws('|',cod,unidad,nombre,categoria,saldo,ubicacion), '#' order by cod, unidad),'')) into h_old from "GP2".virgilio_insumo_stock;
  if h_new is distinct from h_old then
    delete from "GP2".virgilio_insumo_stock;
    insert into "GP2".virgilio_insumo_stock(cod, unidad, nombre, categoria, saldo, ubicacion)
    select m.cod_art, coalesce(m.unidad,''), max(vi.nombre), max(vi.categoria), round(sum(m.delta),4), max(nullif(vi.ubicacion,''))
      from public."Movimientos_Stock" m left join public.vista_insumos vi on vi.cod = m.cod_art
     where m.deposito='insumos' group by 1,2;
    out := out || 'stock ';
  end if;
  -- 2) ubicaciones de insumos
  select md5(coalesce(string_agg(concat_ws('|',id,cod,sector,texto,cantidad,unidad,estado),'#' order by id),'')) into h_new from public.gv_insumo_ubicacion;
  select md5(coalesce(string_agg(concat_ws('|',id,cod,sector,texto,cantidad,unidad,estado),'#' order by id),'')) into h_old from "GP2".virgilio_insumo_ubicacion;
  if h_new is distinct from h_old then
    delete from "GP2".virgilio_insumo_ubicacion;
    insert into "GP2".virgilio_insumo_ubicacion(id, cod, sector, texto, cantidad, unidad, estado)
    select id, cod, sector, texto, cantidad, unidad, estado from public.gv_insumo_ubicacion;
    out := out || 'ubicacion ';
  end if;
  -- 3) el Mapa (góndolas y racks) con lo que tiene cada celda
  select md5(coalesce(string_agg(concat_ws('|',l.sector,l.tipo,l.empresa,l.uso,l.orden,l.activo,l.notas,a.codigos,a.cap),'#' order by l.sector),'')) into h_new
    from public."GV_Lugar" l left join (select sector, string_agg(cod||coalesce(' '||empresa,''), ', ' order by cod) codigos, sum(cajas_max) cap from public.gv_lugar_articulo group by 1) a using (sector);
  select md5(coalesce(string_agg(concat_ws('|',sector,tipo,empresa,uso,orden,activo,notas,codigos,cajas_max),'#' order by sector),'')) into h_old from "GP2".virgilio_lugar;
  if h_new is distinct from h_old then
    delete from "GP2".virgilio_lugar;
    insert into "GP2".virgilio_lugar(sector, tipo, empresa, uso, orden, activo, notas, codigos, cajas_max)
    select l.sector, l.tipo, l.empresa, l.uso, l.orden, l.activo, l.notas, a.codigos, a.cap
      from public."GV_Lugar" l left join (select sector, string_agg(cod||coalesce(' '||empresa,''), ', ' order by cod) codigos, sum(cajas_max) cap from public.gv_lugar_articulo group by 1) a using (sector);
    out := out || 'lugar ';
  end if;
  -- 4) (v25.38) el stock de ARTÍCULOS, en cajas, para la caja «Virgilio» de Stock General de GP2
  select md5(coalesce(string_agg(concat_ws('|',cod,cod_base,linea,descripcion,stock_total,terminado,excedente,racks,a_guardar,separar_pedidos,a_facturar),'#' order by cod),'')) into h_new
    from public.stocks_carga_rapida where not coalesce(es_insumo, false);
  select md5(coalesce(string_agg(concat_ws('|',cod,cod_base,linea,descripcion,stock_total,terminado,excedente,racks,a_guardar,separar_pedidos,a_facturar),'#' order by cod),'')) into h_old
    from "GP2".virgilio_articulo_stock;
  if h_new is distinct from h_old then
    delete from "GP2".virgilio_articulo_stock;
    insert into "GP2".virgilio_articulo_stock(cod, cod_base, linea, descripcion, stock_total, terminado, excedente,
                                              racks, a_guardar, separar_pedidos, a_facturar)
    select cod, cod_base, linea, descripcion, stock_total, terminado, excedente, racks, a_guardar, separar_pedidos, a_facturar
      from public.stocks_carga_rapida where not coalesce(es_insumo, false);
    out := out || 'articulo ';
  end if;
  return coalesce(nullif(btrim(out),''), 'sin cambios');
end $function$;
