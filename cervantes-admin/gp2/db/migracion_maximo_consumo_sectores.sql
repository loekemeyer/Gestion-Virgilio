-- 2026-09-29 · Maximo de Crudo/Procesado = consumo x meses_stock del sector, PARA TODOS (ya no 5 cajones).
-- Usuario (Thomas): "USA LA REGLA DE CONSUMO, NO DE 5 CAJONES". Generaliza el opt-in de
-- migracion_maximo_consumo_meses.sql (G5/G6/G7/G8) a todo Sector Crudo (1) y Sector Procesado (2).
-- + Los 20 maximos 'fisico' de Caja/Remache vuelven a est_madre ("CORREGI").
-- + Y1 (Sector Afilado, 'migrado_de_minimo') pasa a consumo x meses.
-- + RULETA queda 'fisico' con su valor (no la consume ningun articulo: es para afilar la piedra que afila).
-- + A9 "Cpo Mango Alambre Corta Queso Crom." se borra (discontinuo, 0 movimientos, 0 recetas, 0 rutas).
begin;

create or replace function "GP2".recalcular_maximos_consumo_meses()
 returns jsonb language plpgsql security definer set search_path to 'GP2' as $function$
-- maximo_origen 'consumo_meses' = consumo mensual (Est Madre explotada) x meses_stock de la ubicacion.
-- 2026-09-29 (G5-G8): opt-in por fila. 2026-09-29 (mas tarde): TODO Sector Crudo y Sector Procesado entra
-- solo, salvo 'fisico' / 'faat_reserva_lote' (usuario: "usa la regla de consumo, no de 5 cajones").
-- Sin consumo -> maximo NULL (no 0): el componente no se repone.
declare v_set int := 0; v_adop int := 0;
begin
  with adop as (
    update inventario i set maximo_origen = 'consumo_meses'
      from ubicacion u, componente c
     where u.id = i.ubicacion_id and u.tipo = 'sector' and c.id = i.componente_id
       and c.sector_id = u.ref_id and c.sector_id in (1, 2)
       and coalesce(i.maximo_origen, '') not in ('fisico', 'faat_reserva_lote', 'consumo_meses')
    returning 1)
  select count(*) into v_adop from adop;

  with upd as (
    update inventario i set maximo = nullif(greatest(coalesce(v.max_calc,0),0), 0)
    from v_nivel_stock v
    where v.inv_id = i.id and i.maximo_origen = 'consumo_meses'
      and i.maximo is distinct from nullif(greatest(coalesce(v.max_calc,0),0), 0)
    returning 1)
  select count(*) into v_set from upd;
  return jsonb_build_object('ok', true, 'adoptados', v_adop, 'actualizados', v_set);
end $function$;

-- recalcular_maximos_cajones queda como nombre (lo llaman trg_maximos_cajones_componente / _parametro y
-- fn_recalc_maximos_cajones), pero ya no aplica 5 cajones: delega en la regla de consumo.
create or replace function "GP2".recalcular_maximos_cajones()
 returns jsonb language plpgsql security definer set search_path to 'GP2' as $function$
-- 2026-09-29: la regla de 5 cajones (2026-08-30) se retiro. Crudo/Procesado = consumo x meses_stock.
begin
  return "GP2".recalcular_maximos_consumo_meses();
end $function$;

-- RULETA (Sector Crudo): no la consume ningun articulo; se conserva el maximo que tenia, como fijo.
update "GP2".inventario i set maximo_origen = 'fisico'
  from "GP2".componente c
 where c.id = i.componente_id and c.codigo = 'RULETA' and c.sector_id = 1 and i.ubicacion_id = 1;

-- Y1 (Sector Afilado): consumo x meses.
update "GP2".inventario i set maximo_origen = 'consumo_meses'
  from "GP2".componente c, "GP2".ubicacion u
 where c.id = i.componente_id and c.codigo = 'Y1' and u.id = i.ubicacion_id and u.tipo = 'sector'
   and u.ref_id = c.sector_id;

-- Caja / Remache: los 'fisico' con consumo vuelven a la Est Madre.
update "GP2".inventario i set maximo_origen = null
  from "GP2".v_nivel_stock v, "GP2".sector s
 where v.inv_id = i.id and s.id = v.sector_id and s.nombre in ('Sector Caja', 'Sector Remache')
   and i.maximo_origen = 'fisico' and v.max_calc > 0;

-- A9 Cpo Mango Alambre Corta Queso Crom. (id 84): discontinuo, se borra.
-- Se va con el: precio_servicio_pieza id 1 (cromado Pedernera $4.757,70/kg, lista 2026-07-01) y 2 filas
-- de inventario en 0 (ubic 2 y 25).
delete from "GP2".precio_servicio_pieza where componente_id = 84;
delete from "GP2".inventario where componente_id = 84;
delete from "GP2".componente where id = 84 and codigo = 'A9';

select "GP2".recalcular_maximos_insumos();
select "GP2".recalcular_maximos_consumo_meses();
select "GP2".recalcular_maximo_mp_ps();

-- La version del mediodia (opt-in) habia quedado con EXECUTE para anon (C de verificar.sql): security definer
-- que escribe inventario. Se cierra.
revoke execute on function "GP2".recalcular_maximos_consumo_meses() from public, anon, authenticated;

commit;
