-- =====================================================================================
-- v19.69 (2026-09-18) — problema 407
-- MOVER UNA TANDA YA PICKEADA DENTRO DE OTRA TANDA YA PICKEADA REVENTABA
--
-- Síntoma: desde «📅 Cambiar de día», mover la tanda E12A (7 NP, pickeada y armada) al lunes
-- 21/09 devolvía el error crudo de Postgres
--     duplicate key value violates unique constraint "mov_stock_pipeline_dedup"
-- y no se movía nada (la RPC devuelve 400 y la transacción hace rollback entero, así que no
-- quedó nada a medias — eso estuvo bien).
--
-- Causa: `gv_ppp_tanda_mover` llama a `gv_ppp_tanda_renombrar`, que hacía
--     update "Movimientos_Stock" set ref = <tanda nueva> where upper(btrim(ref)) = <tanda vieja>
-- a ciegas. `mov_stock_pipeline_dedup` es un índice ÚNICO sobre
--     (upper(trim(ref)), upper(trim(cod_art)), coalesce(empresa,''), deposito, tipo)
--     where tipo in ('picking','separado','facturado')
-- —el guard que impide el doble picking, el del problema 390—, así que si la tanda destino ya
-- tiene una fila del pipeline del mismo artículo, el renombre choca. Medido el 18/09 con E12A:
-- chocaba con 126 filas de E12E, 120 de E12F, 84 de E12K, 75 de E12J, 69 de E12G y 3 de D69H.
--
-- Arreglo: al renombrar hacia un código que ya tiene pipeline, las filas se FUSIONAN en vez de
-- pisarse. Es lo correcto y no es una licencia: el `delta` de esas filas es el TOTAL pickeado de
-- la tanda para ese artículo, y lo escribe `reconciliar_stock_articulo_rt` con
-- `do update set delta = excluded.delta` derivándolo de los eventos PKC. Como esta misma función
-- renombra también los eventos, el reconciliador va a recalcular ese total como la SUMA de las
-- dos tandas: sumar los delta es exactamente lo que va a quedar, y el saldo del depósito no se
-- mueve ni una caja.
--
-- ⚠ El orden importa: primero el DELETE de la fila vieja y después el UPDATE que suma.
-- `trigger_actualizar_saldo_stock` recalcula el saldo del código desde cero, pero corre
-- AFTER INSERT OR UPDATE y NO en DELETE: sumando antes de borrar, el recálculo contaría las dos
-- filas y `stocks_carga_rapida` quedaría inflado hasta el próximo movimiento de ese código.
--
-- Y el segundo agujero, el mismo pozo por otro lado: `gv_ppp_web_codigo_tomado` decidía si un
-- código estaba libre mirando SÓLO las programaciones. Un código que ya no figura en ninguna pero
-- tiene stock del pipeline (una tanda vieja ya entregada) se daba por libre, así que «Tanda nueva»
-- lo podía reciclar y meter el stock de hoy adentro del de aquella. Al 18/09 hay 353 códigos así
-- (casi todos de las series C y D, más E01G). Ahora también se lo cuenta como tomado.
--
-- MEDICIÓN (todo en transacciones abortadas, contra los datos reales del 18/09):
--   · fusión E12A → E12E: 33 filas, 27 chocaban → antes reventaba; ahora queda E12A en 0 filas,
--     E12E pasa de 213 a 219, y los saldos por (cod, depósito, empresa) cambian en 0 casos.
--   · tanda nueva E12A → E12T: movidas=1, saldos que cambian = 0.
--   · el saldo derivado (`stocks_carga_rapida`) queda igual de alineado que antes (el único
--     desalineado, 437E, ya lo estaba: es un dual y la clave lleva sufijo de empresa).
--   · el `exists` nuevo sale por `mov_stock_pipeline_dedup`: 0,1 ms (sin el índice eran 49 ms de
--     seq scan, y el generador de códigos lo llama hasta 400 veces en su loop).
--
-- ROLLBACK: las dos funciones son `create or replace`; las versiones anteriores están en
-- `sql/backups/gv_ppp_tanda_renombrar_pre_v1969.sql`.
-- =====================================================================================

create or replace function public.gv_ppp_tanda_renombrar(p_vieja text, p_nueva text, p_por text default null::text)
 returns integer
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare v_a text := upper(btrim(coalesce(p_vieja, ''))); v_b text := upper(btrim(coalesce(p_nueva, ''))); v_n int := 0;
begin
  if v_a = '' or v_b = '' or v_a = v_b then return 0; end if;
  update public."Registros_Produccion_Virgilio" r set texto = v_b where upper(btrim(r.texto)) = v_a;
  get diagnostics v_n = row_count;
  update public."Registros_Produccion_Virgilio" r
     set texto = split_part(r.texto, '|', 1) || '|' || split_part(r.texto, '|', 2) || '|' || v_b
   where upper(btrim(split_part(r.texto, '|', 3))) = v_a;
  update public."Entregas_Virgilio" e set tanda = v_b where upper(btrim(e.tanda)) = v_a;
  update public."Facturacion_NP" f set tanda = v_b where upper(btrim(f.tanda)) = v_a;

  -- v19.69 (problema 407) — EL STOCK DEL PIPELINE NO SE PUEDE RENOMBRAR A CIEGAS.
  -- `mov_stock_pipeline_dedup` es único por (ref, cod_art, empresa, deposito, tipo) para
  -- picking/separado/facturado: es el guard que impide el doble picking. Al fusionar una tanda
  -- dentro de OTRA ya pickeada, el `set ref = v_b` de toda la vida chocaba contra ese índice y la
  -- RPC entera devolvía 400, o sea que juntar dos tandas armadas era imposible.
  -- Lo que corresponde es FUSIONAR: el `delta` es el total pickeado de la tanda para ese artículo
  -- (lo escribe `reconciliar_stock_articulo_rt` desde los eventos PKC), y como los eventos también
  -- se renombran acá arriba, el reconciliador va a recalcularlo como la suma de las dos.
  -- ⚠ Primero el DELETE y después el UPDATE: `trigger_actualizar_saldo_stock` recalcula el saldo
  -- del código desde cero pero NO corre en DELETE, así que al revés dejaría el saldo inflado.
  create temp table if not exists _tr_fus (id_dest bigint primary key, suma numeric) on commit drop;
  delete from _tr_fus where true;
  insert into _tr_fus (id_dest, suma)
  select d.id, sum(v.delta)
    from public."Movimientos_Stock" v
    join public."Movimientos_Stock" d
      on d.tipo = v.tipo and d.deposito = v.deposito
     and upper(btrim(d.cod_art)) = upper(btrim(v.cod_art))
     and coalesce(d.empresa, '') = coalesce(v.empresa, '')
     and upper(btrim(coalesce(d.ref, ''))) = v_b
     and d.tipo in ('picking', 'separado', 'facturado')
   where upper(btrim(coalesce(v.ref, ''))) = v_a
     and v.tipo in ('picking', 'separado', 'facturado')
   group by d.id;

  delete from public."Movimientos_Stock" v
   where upper(btrim(coalesce(v.ref, ''))) = v_a
     and v.tipo in ('picking', 'separado', 'facturado')
     and exists (select 1 from public."Movimientos_Stock" d
                  where d.tipo = v.tipo and d.deposito = v.deposito
                    and upper(btrim(d.cod_art)) = upper(btrim(v.cod_art))
                    and coalesce(d.empresa, '') = coalesce(v.empresa, '')
                    and upper(btrim(coalesce(d.ref, ''))) = v_b
                    and d.tipo in ('picking', 'separado', 'facturado'));

  update public."Movimientos_Stock" d set delta = d.delta + f.suma
    from _tr_fus f where d.id = f.id_dest;

  update public."Movimientos_Stock" m set ref = v_b where upper(btrim(coalesce(m.ref, ''))) = v_a;

  update public."GV_PPP_Armados_Espera" e set tanda = v_b where upper(btrim(coalesce(e.tanda, ''))) = v_a;
  update public."PPP_Web_Tandas" t set codigo = v_b
   where upper(btrim(t.codigo)) = v_a
     and not exists (select 1 from public."PPP_Web_Tandas" x where upper(btrim(x.codigo)) = v_b);
  delete from public."PPP_Web_Tandas" t where upper(btrim(t.codigo)) = v_a;
  return v_n;
end $function$;

create or replace function public.gv_ppp_web_codigo_tomado(p_codigo text)
 returns boolean
 language sql
 stable
 set search_path to 'public', 'pg_temp'
as $function$
  -- v19.69 (problema 407): un código que ya no figura en ninguna programación pero TIENE stock del
  -- pipeline sigue estando tomado. Si se recicla, los movimientos de la tanda vieja quedan bajo el
  -- mismo `ref` que los de la nueva: el índice `mov_stock_pipeline_dedup` frena el renombre
  -- («duplicate key») o, peor, la fusión mezcla cajas de dos tandas de épocas distintas. Al 18/09
  -- hay 353 códigos así (casi todos de las series C y D, más E01G). El `exists` sale por ese mismo
  -- índice —0,1 ms medidos— así que el loop que busca letra libre no se encarece.
  select exists (select 1 from public."GV_PPP_Programacion_Diaria" where tanda = p_codigo)
      or exists (select 1 from public."PPP_Web_Programacion"    where tanda = p_codigo)
      or exists (select 1 from public."PPP_Web_Tandas"          where codigo = p_codigo and estado <> 'descartada')
      or exists (select 1 from public."GV_PPP_Prog_Override"    where tanda = p_codigo)
      or exists (select 1 from public."Movimientos_Stock" m
                  where upper(btrim(m.ref)) = upper(btrim(p_codigo))
                    and m.tipo in ('picking', 'separado', 'facturado'));
$function$;

-- CHEQUEO (tiene que dar vacío: ninguna tanda con pipeline duplicado sin empresa que lo explique)
-- select count(*) from (
--   select 1 from public."Movimientos_Stock" where tipo in ('picking','separado','facturado')
--    group by upper(btrim(ref)), upper(btrim(cod_art)), deposito, tipo
--   having count(*) > 1 and count(distinct coalesce(empresa,'')) > 1) z;
