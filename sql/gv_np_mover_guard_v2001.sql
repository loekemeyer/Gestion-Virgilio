-- v20.01 (2026-09-18) — NO SE MUEVE UN PEDIDO CUYA TANDA YA TIENE EL TRABAJO HECHO
-- =============================================================================================
-- THOMAS, 18/09, con el caso Martinelli todavía caliente: *"que el sistema avise cuando movés un
-- pedido que ya tiene picking o armado hecho. URGENTE YA y que inhabilite. Cuando haga falta se
-- ve el código en el momento."*
--
-- POR QUÉ. Mover una NP de una tanda a otra cambia el PAPEL —programación, Entregas, facturación,
-- eventos— pero NO las cajas: el picking y el armado viven en la pila de la TANDA, no del pedido.
-- La mercadería se queda en la tanda vieja y nadie se entera. Eso es exactamente lo que pasó con
-- la NP 98622 (Martinelli): armada en D69C el 16/09, movida a E33A, 92 cajas huérfanas en el piso
-- de armado que después el facturado de OTRA NP se llevó como si hubieran salido.
--
-- BLOQUEA, no avisa. Ya había un aviso de texto en `gv_ppp_isis_programar` —*"si ya estaba
-- pickeada y armada, no hay que repetirlo"*— y no alcanzó: se reprogramó igual, se volvió a
-- pickear y quedaron 184 cajas afuera para un pedido de 92. La excepción se levanta a mano, caso
-- por caso, mirando el stock; es lo que decidió el dueño.
-- =============================================================================================

-- ── 1. ¿ESTA TANDA YA TIENE TRABAJO HECHO? ──────────────────────────────────────────────────
-- Dos señales por lado, y las baratas primero: el stock sale por el índice del dedup y los
-- eventos por el índice de `opcion` (EP/TP/AP/TAP son pocos miles de filas). ~16 ms por NP.
create or replace function public.gv_tanda_trabajo_hecho(p_tanda text)
 returns table(tanda text, tiene_picking boolean, tiene_armado boolean, cajas numeric)
 language sql stable security definer set search_path to 'public','pg_temp' as $function$
  with t as (select nullif(upper(btrim(coalesce(p_tanda,''))),'') tanda)
  select t.tanda,
    t.tanda is not null and (
      exists (select 1 from public."Movimientos_Stock" m
               where upper(btrim(m.ref)) = t.tanda and m.tipo = 'picking' and m.delta <> 0)
      or exists (select 1 from public."Registros_Produccion_Virgilio" r
                  where r.opcion in ('EP','TP') and upper(btrim(r.texto)) = t.tanda
                    and not public.es_legajo_test(r.legajo))),
    t.tanda is not null and (
      exists (select 1 from public."Entregas_Virgilio" e where upper(btrim(e.tanda)) = t.tanda)
      or exists (select 1 from public."Registros_Produccion_Virgilio" r
                  where r.opcion in ('AP','TAP') and upper(btrim(r.texto)) = t.tanda
                    and not public.es_legajo_test(r.legajo))),
    coalesce((select sum(m.delta) from public."Movimientos_Stock" m
               where upper(btrim(m.ref)) = t.tanda and m.tipo = 'picking'
                 and m.deposito = 'separar_pedidos'), 0)
  from t;
$function$;

-- La misma pregunta, pero por NP: resuelve su tanda de hoy (web primero, ISIS después) y delega.
create or replace function public.gv_np_trabajo_hecho(p_np text)
 returns table(np text, tanda text, tiene_picking boolean, tiene_armado boolean, cajas numeric)
 language sql stable security definer set search_path to 'public','pg_temp' as $function$
  with n as (select regexp_replace(upper(btrim(coalesce(p_np,''))),'\.0+$','') np),
  t as (select n.np, coalesce(
      (select upper(btrim(w.tanda)) from public."PPP_Web_Programacion" w
        where upper(btrim(public.gv_ppp_web_np_label(w.empresa, w.np, w.np_idx))) = n.np
          and nullif(btrim(coalesce(w.tanda,'')),'') is not null limit 1),
      (select upper(btrim(d.tanda)) from public.gv_ppp_programacion_diaria d
        where regexp_replace(upper(btrim(d.np)),'\.0+$','') = n.np
          and nullif(btrim(coalesce(d.tanda,'')),'') is not null limit 1)) tanda
    from n)
  select t.np, x.tanda, x.tiene_picking, x.tiene_armado, x.cajas
    from t cross join lateral public.gv_tanda_trabajo_hecho(t.tanda) x;
$function$;

-- ── 2. EL FRENO ─────────────────────────────────────────────────────────────────────────────
-- ⚠ Sólo frena cuando el DESTINO es OTRA tanda. Cambiarle el DÍA a una tanda entera —que pasa
-- todo el tiempo— no se toca: ahí la mercadería viaja con su tanda y no se pierde nada.
create or replace function public.gv_np_mover_guard(p_nps text[], p_tanda_destino text)
 returns void language plpgsql stable security definer set search_path to 'public','pg_temp' as $function$
declare
  v_t text := upper(btrim(coalesce(p_tanda_destino, '')));
  v_msg text;
begin
  if v_t = '' then return; end if;
  select string_agg(format('%s (esta en %s, %s)', x.np, x.tanda,
                    concat_ws(' y ', case when x.tiene_picking then 'pickeada' end,
                                     case when x.tiene_armado  then 'armada'   end)), E'\n  - ')
    into v_msg
    from unnest(coalesce(p_nps, array[]::text[])) n
    cross join lateral public.gv_np_trabajo_hecho(n) x
   where x.tanda is not null and x.tanda <> v_t and (x.tiene_picking or x.tiene_armado);
  if v_msg is not null then
    raise exception E'No se puede mover a %:\n  - %\n\nEsa tanda YA tiene el trabajo hecho. Si se mueve el pedido, la mercaderia queda fisicamente en la tanda vieja y el sistema la pierde de vista. Hay que resolver el stock primero: avisa a sistemas.', v_t, v_msg
      using errcode = '23514';
  end if;
end $function$;

-- ── 3. DÓNDE SE ENGANCHA ────────────────────────────────────────────────────────────────────
-- (a) `gv_ppp_nps_mover_a`, apenas se arma la lista de NP:
--       perform public.gv_np_mover_guard(v_nps, v_t);
--
-- (b) `gv_ppp_isis_programar`, justo después de decidir el código y ANTES de escribir el
--     override — es el camino por el que se fue 98622. Acá la NP está *sin tanda*, así que la
--     que importa es `tanda_previa`, y sólo frena si el código que sale es DISTINTO:
--
--       if v_prev is not null and upper(btrim(coalesce(v_code,''))) <> upper(btrim(v_prev)) then
--         declare t record;
--         begin
--           select * into t from public.gv_tanda_trabajo_hecho(v_prev);
--           if t.tiene_picking or t.tiene_armado then raise exception '…' using errcode='23514'; end if;
--         end;
--       end if;
--
-- Reusar la MISMA tanda sigue pasando: ese es el caso sano y el que el operario quiere.
--
-- NO se engancha en `gv_ppp_web_tanda_reusar` (devuelve el pedido a SU tanda anterior, o sea el
-- caso sano) ni en los desprogramar (sacar de la tanda es reversible y la NP conserva su
-- `tanda_previa`; el freno actúa cuando se la quiere mandar a un código nuevo).
-- Tampoco en `gv_ppp_pedido_mover` / `gv_ppp_tanda_mover`, que pasan por el renombrador y por lo
-- tanto SÍ arrastran la mercadería.
--
-- El mensaje llega al usuario tal cual: `aprMsgErr` del front saca el `message` de PostgREST.

-- ── PROBADO CORRIÉNDOLO (todo dentro de bloques que abortan, no se escribió nada) ───────────
--   · mover 98622 (E33A, pickeada y armada) a otra tanda .......... FRENÓ  ✔
--   · mover 98622 a SU MISMA tanda con otra fecha ................. pasó   ✔
--   · misma tanda / NP inexistente / lista vacía .................. pasan  ✔
--   · la rama de bloqueo de `gv_ppp_isis_programar` con D69C ...... "su tanda anterior D69C ya
--     esta pickeada y armada y las 148 cajas pickeadas quedarian ahi, sin dueno"  ✔
--   · el camino sano de `gv_ppp_isis_programar` (98617, tanda previa E12I sin trabajo) ... corrió ✔
