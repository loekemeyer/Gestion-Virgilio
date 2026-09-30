-- 2026-09-29 · Maximo de Crudo/Procesado por CONSUMO x MESES DEL SECTOR (opt-in por fila).
-- Usuario: "Consumo x maximo de meses por sector" (para G5/G6/G7/G8 de los rompenueces 507/707).
-- maximo = v_nivel_stock.max_calc = consumo_mes (Est Madre) x ubicacion.meses_stock.
-- Las filas con maximo_origen 'consumo_meses' no las pisa recalcular_maximos_cajones y se
-- refrescan solas al cambiar Est Madre / recetas / rutas (fn_recalc_maximos_diferido).
begin;

alter table "GP2".inventario drop constraint inventario_maximo_origen_chk;
alter table "GP2".inventario add constraint inventario_maximo_origen_chk check (maximo_origen = any (array[
  'cinco_cajones','est_madre','est_madre_x_reparto','fisico','faat_reserva_lote','mb_2pct_por_color',
  'mb_4pct_por_color','migrado_de_minimo','derivado_pieza','consumo_meses']));

create or replace function "GP2".recalcular_maximos_consumo_meses()
 returns jsonb language plpgsql security definer set search_path to 'GP2' as $function$
-- maximo_origen 'consumo_meses' = consumo mensual (Est Madre) x meses_stock de la ubicacion.
-- Opt-in por fila de inventario; recalcular_maximos_cajones no lo pisa. Usuario 2026-09-29
-- (G5/G6/G7/G8): "Consumo x maximo de meses por sector".
declare v_set int := 0;
begin
  with upd as (
    update inventario i set maximo = greatest(coalesce(v.max_calc,0),0)
    from v_nivel_stock v
    where v.inv_id = i.id and i.maximo_origen = 'consumo_meses'
      and i.maximo is distinct from greatest(coalesce(v.max_calc,0),0)
    returning 1)
  select count(*) into v_set from upd;
  return jsonb_build_object('ok', true, 'actualizados', v_set);
end $function$;

create or replace function "GP2".recalcular_maximos_cajones()
 returns jsonb language plpgsql security definer set search_path to 'GP2' as $function$
declare
  v_caj numeric;
  v_set int := 0;
  v_clr int := 0;
begin
  select valor into v_caj from parametro where clave = 'max_cajones_x_ubicacion';
  if v_caj is null or v_caj <= 0 then v_caj := 5; end if;

  with objetivo as (
    select i.id as inv_id,
           case when c.uni_x_cajon > 0 then round(v_caj * c.uni_x_cajon) end as max_nuevo
    from inventario i
    join ubicacion u on u.id = i.ubicacion_id and u.tipo = 'sector'
    join componente c on c.id = i.componente_id and c.sector_id = u.ref_id
    where c.sector_id in (1, 2)
      and coalesce(i.maximo_origen, '') not in ('fisico', 'faat_reserva_lote', 'consumo_meses')
  ), upd as (
    update inventario i
    set maximo = o.max_nuevo, maximo_origen = 'cinco_cajones'
    from objetivo o
    where i.id = o.inv_id and o.max_nuevo > 0
      and (i.maximo is distinct from o.max_nuevo or i.maximo_origen is distinct from 'cinco_cajones')
    returning 1
  ), clr as (
    update inventario i
    set maximo = null, maximo_origen = null
    from objetivo o
    where i.id = o.inv_id and o.max_nuevo is null
      and (i.maximo is not null or i.maximo_origen is not null)
    returning 1
  )
  select (select count(*) from upd), (select count(*) from clr) into v_set, v_clr;
  return jsonb_build_object('ok', true, 'max_cajones', v_caj, 'actualizados', v_set, 'sin_uni_x_cajon', v_clr);
end $function$;

create or replace function "GP2".fn_recalc_maximos_diferido()
 returns trigger language plpgsql security definer set search_path to 'GP2' as $function$
-- Recalcula los maximos UNA vez por transaccion, al COMMIT (constraint trigger DEFERRABLE INITIALLY
-- DEFERRED sobre est_madre / articulo_componente / ruta_paso / articulo_familia). El sync diario de LK
-- borra e inserta las ~330 filas de proyeccion_madre de a una, en UNA transaccion: con el trigger
-- statement-level anterior (fn_recalc_maximos_insumos) el recalculo corria ~658 veces por sync (~54 s,
-- el DELETE solo 21 s contra un statement_timeout de 120 s). Ahora corre una vez, contra la est_madre
-- final, y ademas refresca los maximos de TALLERISTA, que nadie recalculaba cuando cambiaba la Est
-- Madre (68 estaban viejos el 2026-09-26). Prov AT queda afuera a proposito: la Tablet le pone techo 0
-- (usuario 2026-09-24) y no tiene filas de inventario. D10, 2026-09-26.
-- 2026-09-28: + recalcular_maximo_mp_ps (FLEJE90_BRUTO / CHAPA430), al final porque sale del maximo
-- de las piezas que acaban de recalcularse.
-- 2026-09-29: + recalcular_maximos_consumo_meses (filas con maximo_origen 'consumo_meses'), antes de
-- mp_ps porque este sale del maximo de las piezas.
declare v_tx text := txid_current()::text;
begin
  if current_setting('gp2.maximos_tx', true) = v_tx then return null; end if;
  perform set_config('gp2.maximos_tx', v_tx, true);   -- local a la transaccion: se borra sola al COMMIT
  begin
    perform "GP2".recalcular_maximos_insumos();
    perform "GP2".recalcular_maximos_talleristas();
    perform "GP2".recalcular_maximos_consumo_meses();
    perform "GP2".recalcular_maximo_mp_ps();
  exception when others then
    -- un error en el recalculo NO puede tumbar el sync de LK ni un guardado de receta: se avisa y sigue
    raise warning 'fn_recalc_maximos_diferido: % — los maximos quedan como estaban; correr recalcular_maximos_* a mano', sqlerrm;
  end;
  return null;
end $function$;

-- Opt-in: rompenueces crudos (G5/G6 -> 707, G7/G8 -> 507) en Sector Crudo.
update "GP2".inventario set maximo_origen = 'consumo_meses'
 where ubicacion_id = 1
   and componente_id in (select id from "GP2".componente where codigo in ('G5','G6','G7','G8'));
select "GP2".recalcular_maximos_consumo_meses();
select "GP2".recalcular_maximo_mp_ps();

commit;
