-- v19.96 (2026-09-18) — Al RENOMBRAR una tanda, el CANDADO se va con ella
-- =============================================================================================
-- SÍNTOMA (Thomas, 18/09): el armador elige E12A en el módulo, toca Enviar y la app le dice que
-- "ya la agarró Jhonny". El operario se queda sin poder arrancar una tanda que está pickeada.
--
-- CAUSA. `gv_ppp_tanda_renombrar` renombraba los eventos, las Entregas, la Facturación, el stock
-- y las tablas de tandas — TODO menos `GV_Tandas_Lock`, que no aparecía ni una vez en su cuerpo.
-- El candado se quedaba con el código VIEJO, o sea a nombre de la tanda que ANTES usaba ese
-- código. Medido el 18/09, y las dos veces el candado se escribió el MISMO SEGUNDO que el evento
-- que hoy dice otra cosa:
--
--   candado                                    evento del mismo segundo   es de
--   E12A · picking · Cartaya · completada      EP E12S  16/09 10:24:49    E12S
--   E12E · picking · Cartaya · TOMADA          EP E37F  16/09 13:08:51    E37F
--
-- Lo que rompía, en las dos direcciones:
--   · sobre el código VIEJO (E12A, E12E) el candado ajeno frena a quien quiera trabajarlo
--     ("ya está PICKEADA (la terminó …)" / "la está pickeando …"), y un `estado='tomada'`
--     colgado deja además al dueño sin poder empezar NINGUNA otra (guard `otra_tanda_abierta`,
--     ventana de 3 días);
--   · sobre el código NUEVO (E12S, E37F) no quedaba candado, así que su picking se podía
--     REABRIR — justo el invariante que la tabla existe para sostener (v18.65, pedido de Luis).
--
-- ⚠ FUSIÓN, no rename a ciegas: `GV_Tandas_Lock` es única por (tanda, fase). Si el destino ya
-- tiene esa fase —el caso de juntar dos tandas—, un `update` pelado tira el unique y la RPC
-- entera devuelve 400, que es exactamente el pozo del problema 407 con `Movimientos_Stock`.
-- Criterio: MANDA EL DESTINO (es la tanda que sobrevive y su candado refleja su propio trabajo)
-- y la fila del origen se borra. Es el lado indulgente: nadie queda trabado por un candado que
-- ya no representa a nadie, y el evento EP/AP del origen sigue estando para reconstruir.
--
-- Rollback: volver a la definición de la v19.76 (git) — el bloque nuevo es aditivo y no toca
-- ninguna de las otras tablas.
-- =============================================================================================

create or replace function public.gv_ppp_tanda_renombrar(p_vieja text, p_nueva text, p_por text default null)
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

  -- v19.76 (problema 413) — ídem `gv_ppp_nps_mover_a`: el campo de la tanda depende del evento.
  -- El `campo1|campo2|v_b` de antes acertaba sólo con el TAL, y aun ahí le comía el resumen y la
  -- clase (campos 4 y 5).
  update public."Registros_Produccion_Virgilio" r
     set texto = public.gv_evento_set_tanda(r.opcion, r.texto, v_b)
   where public.gv_evento_tanda(r.opcion, r.texto) = v_a
     and public.gv_evento_set_tanda(r.opcion, r.texto, v_b) is not null;

  update public."Entregas_Virgilio" e set tanda = v_b where upper(btrim(e.tanda)) = v_a;
  update public."Facturacion_NP" f set tanda = v_b where upper(btrim(f.tanda)) = v_a;

  -- v19.69 (problema 407) — EL STOCK DEL PIPELINE NO SE PUEDE RENOMBRAR A CIEGAS.
  -- `mov_stock_pipeline_dedup` es único por (ref, cod_art, empresa, deposito, tipo) para
  -- picking/separado/facturado: es el guard que impide el doble picking. Al fusionar una tanda
  -- dentro de OTRA ya pickeada, el `set ref = v_b` de toda la vida chocaba contra ese índice y la
  -- RPC entera devolvía 400, o sea que juntar dos tandas armadas era imposible.
  -- Lo que corresponde es FUSIONAR: el `delta` es el total pickeado de la tanda para ese artículo
  -- (lo escribe `reconciliar_stock_articulo_rt` desde los eventos PKC).
  -- ⚠ Primero el DELETE y después el UPDATE: `trigger_actualizar_saldo_stock` recalcula el saldo
  -- del código desde cero pero NO corre en DELETE, así que al revés dejaría el saldo inflado.
  -- ⚠ v19.76: el PKC lleva la tanda en el CAMPO 1 y hoy no lo renombra nadie, así que la frase
  -- "como los eventos también se renombran acá arriba" NO vale para el PKC. Medido y abierto
  -- aparte (problema 421): tocarlo mueve stock. Detalle: sql/gv_ppp_tanda_fusion_stock_v1969.sql
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

  -- v19.96 — EL CANDADO SE VA CON LA TANDA (ver la cabecera de este archivo).
  -- Primero se borra la fila del origen cuyo destino YA tiene esa fase (el destino manda), y
  -- recién después se renombra el resto: al revés, el update choca con el unique (tanda, fase).
  delete from public."GV_Tandas_Lock" l
   where upper(btrim(l.tanda)) = v_a
     and exists (select 1 from public."GV_Tandas_Lock" d
                  where upper(btrim(d.tanda)) = v_b and d.fase = l.fase);
  update public."GV_Tandas_Lock" l set tanda = v_b where upper(btrim(l.tanda)) = v_a;

  update public."GV_PPP_Armados_Espera" e set tanda = v_b where upper(btrim(coalesce(e.tanda, ''))) = v_a;
  update public."PPP_Web_Tandas" t set codigo = v_b
   where upper(btrim(t.codigo)) = v_a
     and not exists (select 1 from public."PPP_Web_Tandas" x where upper(btrim(x.codigo)) = v_b);
  delete from public."PPP_Web_Tandas" t where upper(btrim(t.codigo)) = v_a;
  return v_n;
end $function$;

-- =============================================================================================
-- CENTINELA: un candado que no coincide con ningún EP/AP de su tanda
-- =============================================================================================
-- Vacía = todo bien. Una fila = el candado quedó a nombre de otro código (lo que pasó acá) o de
-- alguien que nunca arrancó esa fase en esa tanda.
create or replace view public.gv_tandas_lock_huerfano
with (security_invoker = true) as
with ev as (
  select upper(btrim(texto)) tanda,
         case when opcion in ('EP', 'EPX') then 'picking' else 'armado' end fase,
         btrim(legajo) legajo
    from public."Registros_Produccion_Virgilio"
   where opcion in ('EP', 'EPX', 'AP', 'APX')
     and ts_cliente >= now() - interval '60 days'
)
select l.tanda, l.fase, l.legajo, l.nombre, l.estado, l.ts,
       (select count(*) from ev where ev.tanda = upper(btrim(l.tanda)) and ev.fase = l.fase) as eventos_de_la_tanda,
       (select string_agg(distinct ev.legajo, ',') from ev
         where ev.tanda = upper(btrim(l.tanda)) and ev.fase = l.fase) as legajos_de_los_eventos
  from public."GV_Tandas_Lock" l
 where coalesce(btrim(l.legajo), '') <> ''
   and l.ts >= now() - interval '60 days'
   and not exists (select 1 from ev
                    where ev.tanda = upper(btrim(l.tanda)) and ev.fase = l.fase
                      and ev.legajo = btrim(l.legajo));

-- La regla, para que el centinela de reglas perdidas avise si alguien la borra de la función.
insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
values ('gv_ppp_tanda_renombrar', 'funcion', 'GV_Tandas_Lock',
        'Al renombrar o fusionar una tanda, su fila de GV_Tandas_Lock se va con ella (el destino manda; la del origen se borra si el destino ya tiene esa fase). Sin esto el candado queda a nombre del codigo viejo y traba al operario.',
        'Thomas 18/09', 'v19.96')
on conflict do nothing;

-- Chequeos:
--   select * from public.gv_tandas_lock_huerfano;   -- vacía = todo bien
--   select * from public.gv_reglas_perdidas;        -- vacía = todo bien
