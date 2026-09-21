-- v20.30 (Luis, 2026-09-21) — EL GUARD DEL PEDIDO SUELTO NO APLICA A LA TANDA ENTERA.
-- Problema 458.
--
-- `gv_np_mover_guard` (v20.01, caso Martinelli) frena mover UNA NP cuya tanda ya tiene picking o
-- armado: las cajas viven en la pila de la TANDA, asi que la mercaderia quedaria fisicamente en la
-- tanda vieja y el sistema la perderia de vista. Eso sigue igual.
--
-- Lo que estaba mal es que ese mismo guard se disparaba desde `gv_ppp_tanda_mover`, o sea cuando
-- viaja la TANDA COMPLETA a un codigo nuevo o se fusiona con otra. Ahi no hay orfandad posible:
-- despues del pase de NP, la propia funcion llama a `gv_ppp_tanda_renombrar`, que se lleva los
-- movimientos de stock, los eventos de operario, las entregas, los candados y las etiquetas al
-- codigo nuevo (y FUSIONA los deltas cuando el destino ya tiene ese articulo, v19.69/v20.04).
--
-- Medido el 21/09 dentro de una transaccion abortada, con el guard anulado a proposito:
--   · E12R -> E12S (las dos pickeadas, 183 filas de stock del mismo articulo en las dos):
--     654 movimientos quedaron en 471, 372 cajas, 0 saldos del deposito cambiados,
--     0 filas en gv_stock_picking_duplicado y 0 en gv_stock_empresa_fantasma.
--   · E12E (ISIS) -> E65A: override de 3 NP, la vista paso a la tanda y fecha nuevas,
--     309 movimientos viajaron, 38 cajas, 0 saldos cambiados.
-- Alcance del bloqueo antes del fix: 10 de las 12 tandas vivas, entre ellas D69H — la que el
-- centinela gv_ppp_tanda_camion_mezclado marca para que Marianela la separe.
--
-- ⚠ La exencion es POR TANDA, no un "saltear el guard": `gv_ppp_tanda_mover` pasa el codigo de la
-- tanda que se esta moviendo entera, y solo las NP que vienen de ESA tanda quedan exentas. Si el
-- array trajera una NP de otra tanda pickeada, el guard la frena igual.

-- ── 1. el guard, con la tanda exenta ──────────────────────────────────────────────────────────
create or replace function public.gv_np_mover_guard(
  p_nps text[], p_tanda_destino text, p_tanda_entera text default null)
returns void language plpgsql stable security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_t text := upper(btrim(coalesce(p_tanda_destino, '')));
  v_ex text := nullif(upper(btrim(coalesce(p_tanda_entera, ''))), '');
  v_msg text;
begin
  -- v20.01 (Thomas, 18/09) — NO SE MUEVE UN PEDIDO CUYA TANDA YA TIENE EL TRABAJO HECHO.
  -- Mover la NP cambia el papel (programacion, Entregas, facturacion, eventos) pero NO mueve las
  -- cajas: el picking y el armado viven en la PILA DE LA TANDA, no del pedido. La mercaderia
  -- queda en la tanda vieja y nadie se entera. Es el caso Martinelli (98622: armada en D69C,
  -- movida a E33A, 92 cajas huerfanas y el facturado de otra NP se las llevo).
  -- BLOQUEA, no avisa: decision de Thomas — "y que inhabilite; cuando haga falta se ve el codigo
  -- en el momento". La excepcion se levanta a mano, caso por caso, mirando el stock.
  -- v20.30 (Luis, 21/09, problema 458) — `p_tanda_entera` es la tanda que viaja COMPLETA. Sus NP
  -- quedan exentas porque el stock viaja con ellas (gv_ppp_tanda_renombrar se lo lleva y lo
  -- fusiona); las de cualquier OTRA tanda pickeada se siguen frenando igual.
  if v_t = '' then return; end if;
  select string_agg(format('%s (esta en %s, %s)', x.np, x.tanda,
                    concat_ws(' y ', case when x.tiene_picking then 'pickeada' end,
                                     case when x.tiene_armado  then 'armada'   end)), E'\n  - ')
    into v_msg
    from unnest(coalesce(p_nps, array[]::text[])) n
    cross join lateral public.gv_np_trabajo_hecho(n) x
   where x.tanda is not null and x.tanda <> v_t
     and (v_ex is null or x.tanda <> v_ex)
     and (x.tiene_picking or x.tiene_armado);
  if v_msg is not null then
    raise exception E'No se puede mover a %:\n  - %\n\nEsa tanda YA tiene el trabajo hecho. Si se mueve el pedido, la mercaderia queda fisicamente en la tanda vieja y el sistema la pierde de vista. Hay que resolver el stock primero: avisa a sistemas.', v_t, v_msg
      using errcode = '23514';
  end if;
end $function$;

-- ⚠ la firma de 2 argumentos se dropea a proposito: si queda, un llamador viejo resuelve a la
-- vieja en silencio y el fix no se aplica (mismo criterio que gv_ppp_web_tanda_abierta_cliente).
drop function if exists public.gv_np_mover_guard(text[], text);

-- ── 2. el pase de NP le cuenta al guard si viaja una tanda entera ─────────────────────────────
create or replace function public.gv_ppp_nps_mover_a(
  p_nps text[], p_tanda text, p_fecha date, p_nota text default null, p_tanda_entera text default null)
returns integer language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_nps text[]; v_t text := upper(btrim(coalesce(p_tanda, '')));
  v_esp date := public.gv_ppp_espera_fecha();
  v_fe date := case when p_fecha = public.gv_ppp_espera_fecha() then null else p_fecha end;
  v_web int := 0; v_isis int := 0;
begin
  select array_agg(distinct regexp_replace(upper(btrim(x)), '\.0+$', ''))
    into v_nps from unnest(coalesce(p_nps, array[]::text[])) x where btrim(coalesce(x, '')) <> '';
  if v_nps is null or array_length(v_nps, 1) = 0 then return 0; end if;

  -- v20.01 (Thomas, 18/09) — FRENO: no se mueve una NP cuya tanda ya tiene picking o armado
  -- hecho. Mover la NP cambia el papel pero NO las cajas, que viven en la pila de la TANDA.
  -- Levanta excepcion y no escribe nada. Caso Martinelli (98622, D69C -> E33A).
  -- v20.30 (problema 458) — salvo que sea la TANDA ENTERA la que viaja: ahi el stock va con ella
  -- (gv_ppp_tanda_renombrar), asi que no hay cajas huerfanas y el guard no corresponde.
  perform public.gv_np_mover_guard(v_nps, v_t, p_tanda_entera);

  -- ⚠ UN SOLO UPDATE para todas las NP: el trigger `gv_web_cliente_un_solo_dia` es AFTER ROW y
  -- corre al final del statement, así que con las hermanas ya movidas no salta. Moviéndolas de a
  -- una rebotaba con "los pedidos de un cliente no pueden salir en días distintos" por un estado
  -- intermedio que duraba una fila (medido el 17/09 con LK 0009 + LK 0010 de Emilio Martinez).
  update public."PPP_Web_Programacion" w
     set tanda = v_t, fecha_entrega = v_fe, actualizado_at = now()
   where upper(btrim(public.gv_ppp_web_np_label(w.empresa, w.np, w.np_idx))) = any (v_nps);
  get diagnostics v_web = row_count;

  insert into public."GV_PPP_Prog_Override" (np, tanda, fecha_entrega, nota)
  select n, v_t, v_fe, p_nota from unnest(v_nps) n
   where not exists (select 1 from public."PPP_Web_Programacion" w
                      where upper(btrim(public.gv_ppp_web_np_label(w.empresa, w.np, w.np_idx))) = n)
  on conflict (np) do update set tanda = excluded.tanda, fecha_entrega = excluded.fecha_entrega,
                                 nota = coalesce(excluded.nota, public."GV_PPP_Prog_Override".nota);
  get diagnostics v_isis = row_count;

  update public."Facturacion_NP" f set tanda = v_t
   where regexp_replace(upper(btrim(f.np)), '\.0+$', '') = any (v_nps);
  update public."Entregas_Virgilio" e set tanda = v_t
   where regexp_replace(upper(btrim(e.np)), '\.0+$', '') = any (v_nps);

  -- v19.76 (problema 413) — la tanda se escribe en EL CAMPO QUE LE TOCA A CADA EVENTO, y el resto
  -- del texto queda como estaba. Antes esto era `campo1|campo2|v_t` y pisaba el detalle del ENT,
  -- el chofer del CCN, la razón social del CRA/FCO y los campos 4-5 del TAL. `gv_evento_set_tanda`
  -- devuelve NULL cuando no hay nada que cambiar, y ese NULL es el filtro.
  update public."Registros_Produccion_Virgilio" r
     set texto = public.gv_evento_set_tanda(r.opcion, r.texto, v_t)
   where regexp_replace(upper(btrim(split_part(r.texto, '|', 1))), '\.0+$', '') = any (v_nps)
     and public.gv_evento_set_tanda(r.opcion, r.texto, v_t) is not null;

  if p_fecha = v_esp then
    insert into public."GV_PPP_Armados_Espera" (np, tanda, empresa, por, motivo, creado_en)
    select n, v_t, public.gv_emp_de_np(n), null, p_nota, now() from unnest(v_nps) n
    on conflict (np) do update set tanda = excluded.tanda, creado_en = now();
  else
    delete from public."GV_PPP_Armados_Espera" e where e.np = any (v_nps);
  end if;
  return v_web + v_isis;
end $function$;

drop function if exists public.gv_ppp_nps_mover_a(text[], text, date, text);

-- ── 3. gv_ppp_tanda_mover: le dice al guard que la tanda viaja ENTERA ─────────────────────────
-- (definicion viva al 21/09, con el unico cambio marcado "v20.30")
CREATE OR REPLACE FUNCTION public.gv_ppp_tanda_mover(p_tanda text, p_fecha date, p_por text DEFAULT NULL::text, p_forzar boolean DEFAULT false, p_tanda_destino text DEFAULT NULL::text)
 RETURNS TABLE(movidas integer, np_web integer, np_isis integer, m3 numeric, aviso text, empezada boolean, tanda_final text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_t text := upper(btrim(coalesce(p_tanda, '')));
  v_esp date := public.gv_ppp_espera_fecha();
  v_dest text; v_modo text;
  v_ev int; v_salio int; v_total int;
  v_web int := 0; v_isis int := 0; v_m3 numeric := 0;
  v_aviso text := null; v_cupo numeric; v_usado numeric; v_zona text;
  v_cand record;
begin
  if not public.gv_es_supervisor_o_servicio() then
    raise exception 'Sólo supervisores pueden mover tandas.';
  end if;
  if v_t = '' then raise exception 'Falta el código de la tanda.'; end if;
  if p_fecha is null then raise exception 'Falta la fecha nueva.'; end if;
  if p_fecha = v_esp and coalesce(btrim(p_tanda_destino), '') = '' then
    raise exception 'Para dejar la tanda % en Armados en espera usá gv_ppp_tanda_espera: ahí no se le pone fecha, se le saca.', v_t;
  end if;

  -- las NP de la tanda, con la etiqueta con la que las nombra el árbol
  create temp table if not exists _tm_nps (np text primary key, web boolean, zona text) on commit drop;
  delete from _tm_nps where true;   -- v19.34: WHERE obligatorio (safeupdate en el rol authenticator)
  insert into _tm_nps (np, web, zona)
  select x.np, bool_or(x.web), min(x.zona) from (
    select upper(btrim(public.gv_ppp_web_np_label(w.empresa, w.np, w.np_idx))) np, true web, coalesce(w.zona,'') zona
      from public."PPP_Web_Programacion" w where upper(btrim(coalesce(w.tanda, ''))) = v_t
    union all
    select regexp_replace(upper(btrim(d.np)), '\.0+$', ''), false, coalesce(d.zona,'')
      from public.gv_ppp_programacion_diaria d where upper(btrim(coalesce(d.tanda, ''))) = v_t and d.np is not null
    union all
    select regexp_replace(upper(btrim(f.np)), '\.0+$', ''), false, ''
      from public."Facturacion_NP" f where upper(btrim(coalesce(f.tanda, ''))) = v_t and f.np is not null
  ) x group by x.np;

  select count(*) into v_total from _tm_nps;
  select count(*) into v_salio from _tm_nps n
    join (select regexp_replace(upper(btrim(split_part(r2.texto, '|', 1))), '\.0+$', '') np,
                 max(r2.ts_cliente) filter (where r2.opcion = 'CCN') ccn,
                 max(r2.ts_cliente) filter (where r2.opcion = 'FSS') fss,
                 max(r2.ts_cliente) filter (where r2.opcion = 'CRN') crn
            from public."Registros_Produccion_Virgilio" r2
           where r2.opcion in ('CCN','FSS','CRN') and coalesce(btrim(r2.legajo), '') not in ('0','1')
             and btrim(coalesce(r2.texto, '')) <> '' group by 1) e on e.np = n.np
   where e.crn is not null or (e.ccn is not null and e.ccn >= coalesce(e.fss, '-infinity'::timestamptz));

  if v_total > 0 and v_salio = v_total then
    raise exception 'La tanda % ya salió entera (% pedido(s) con carga de camión o remito controlado): no hay nada a lo que cambiarle el día.', v_t, v_salio;
  end if;
  if v_salio > 0 then
    raise exception 'La tanda % ya salió en parte (% de % pedidos tienen carga de camión o remito). Cambiarle el día arrastraría lo que ya se entregó, y mover sólo el resto partiría la tanda en dos días. Reprogramá el pedido que falta desde su fila (botón 📅 Cambiar de día de la NP): sale en una tanda nueva, sin volver a pickear.', v_t, v_salio, v_total;
  end if;

  select count(*) into v_ev from public."Registros_Produccion_Virgilio" r
   where upper(btrim(split_part(r.texto, '|', 1))) = v_t;
  if v_ev > 0 and not coalesce(p_forzar, false) then
    raise exception 'TANDA_EMPEZADA: la tanda % ya tiene % evento(s) de operarios (pickeada o armada). Se puede mover igual —el contenido no cambia, no hay que volver a pickear— pero hay que confirmarlo.', v_t, v_ev;
  end if;

  -- ── a dónde va: mismo código / código nuevo del día / adentro de una tanda que ya existe ──
  select min(n.zona) into v_zona from _tm_nps n where coalesce(n.zona, '') <> '';
  if p_tanda_destino is null then
    v_dest := v_t; v_modo := 'mantiene';
  elsif btrim(p_tanda_destino) = '' or upper(btrim(p_tanda_destino)) = '*NUEVA*' then
    v_dest := public.gv_ppp_tanda_codigo_nuevo(p_fecha, v_zona); v_modo := 'nueva';
  else
    v_dest := upper(btrim(p_tanda_destino)); v_modo := 'fusion';
    select * into v_cand from public.gv_ppp_tandas_del_dia(p_fecha, null, v_t) t where t.tanda = v_dest;
    if v_cand.tanda is null then
      raise exception 'La tanda % no existe el %.', v_dest,
        (case when p_fecha = v_esp then 'día de espera' else to_char(p_fecha, 'DD/MM') end);
    end if;
    -- v19.32: la regla de estados de Luis NO se fuerza. `p_forzar` es para la tanda ya
    -- empezada (que sí se mueve, avisando), no para juntar una armada con una pendiente.
    if not v_cand.compatible then
      raise exception 'ESTADO_DISTINTO: %', v_cand.motivo;
    end if;
    v_aviso := v_cand.aviso;
  end if;

  select count(*) filter (where n.web), count(*) filter (where not n.web) into v_web, v_isis from _tm_nps n;
  perform public.gv_ppp_nps_mover_a((select array_agg(n.np) from _tm_nps n), v_dest, p_fecha,
      'v19.32 ' || to_char(now() at time zone 'America/Argentina/Buenos_Aires', 'YYYY-MM-DD HH24:MI')
      || ' · tanda ' || v_t || ' → ' || v_dest || ' el '
      || (case when p_fecha = v_esp then 'día de espera' else to_char(p_fecha, 'DD/MM') end)
      || coalesce(' por ' || nullif(btrim(p_por), ''), '')
      || case when v_ev > 0 then ' · estaba empezada (' || v_ev || ' evento(s))' else '' end,
      v_t);   -- v20.30 (problema 458): v_t es la tanda que viaja ENTERA. Sus NP quedan exentas del
              -- guard de la NP suelta, porque abajo gv_ppp_tanda_renombrar se lleva su stock.
  if v_total = 0 then raise exception 'No encontré la tanda %.', v_t; end if;

  -- el código viejo deja de existir: sus eventos, su stock y sus entregas se van con él
  if v_dest <> v_t then perform public.gv_ppp_tanda_renombrar(v_t, v_dest, p_por); end if;
  update public."PPP_Web_Tandas" t
     set fecha_entrega = (case when p_fecha = v_esp then null else p_fecha end)
   where upper(btrim(t.codigo)) = v_dest;

  select coalesce(round(sum(x.m3), 3), 0) into v_m3 from (
    select w.m3 from public."PPP_Web_Programacion" w where upper(btrim(coalesce(w.tanda,''))) = v_dest
    union all
    select d.m3 from public.gv_ppp_programacion_diaria d where upper(btrim(coalesce(d.tanda,''))) = v_dest
  ) x;

  if p_fecha <> v_esp then
    v_cupo := public.gv_ppp_web_cupo(p_fecha);
    select coalesce(sum(g.m3), 0) into v_usado from public."PPP_Web_Programacion" g
     where g.fecha_entrega = p_fecha and coalesce(nullif(trim(g.tanda), ''), '') <> '';
    v_usado := v_usado + public.gv_ppp_web_m3_isis(p_fecha);
    if v_usado > v_cupo then
      v_aviso := coalesce(v_aviso || ' ', '') || 'El ' || to_char(p_fecha, 'DD/MM') || ' queda con ' || round(v_usado, 3)
                 || ' m³, por encima del cupo de ' || v_cupo || ' m³.';
    end if;
    if not public.gv_es_dia_habil(p_fecha) then
      v_aviso := coalesce(v_aviso || ' ', '') || 'Ojo: el ' || to_char(p_fecha, 'DD/MM')
                 || ' no es día hábil (fin de semana o feriado).';
    end if;
  end if;
  if v_modo = 'fusion' then
    v_aviso := coalesce(v_aviso || ' ', '') || 'La tanda ' || v_t || ' dejó de existir: sus pedidos ahora son de ' || v_dest || '.';
  elsif v_modo = 'nueva' then
    v_aviso := coalesce(v_aviso || ' ', '') || 'Código nuevo: ' || v_t || ' pasó a ser ' || v_dest || '.';
  end if;

  return query select (v_web + v_isis), v_web, v_isis, v_m3, v_aviso, (v_ev > 0), v_dest;
end $function$;

-- ── 4. gv_ppp_tanda_renombrar: GV_Vehiculo_Propio y Comprobantes_ARCA ─────────────────────────
-- (definicion viva al 21/09, con el unico bloque nuevo marcado "v20.30")
CREATE OR REPLACE FUNCTION public.gv_ppp_tanda_renombrar(p_vieja text, p_nueva text, p_por text DEFAULT NULL::text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_a text := upper(btrim(coalesce(p_vieja, ''))); v_b text := upper(btrim(coalesce(p_nueva, ''))); v_n int := 0;
begin
  if v_a = '' or v_b = '' or v_a = v_b then return 0; end if;
  -- v19.98 — UN CODIGO DE TANDA NO SE RECICLA. El renombre es el momento exacto en que el codigo
  -- viejo se queda sin rastro en ningun lado (sus filas se van al nombre nuevo), asi que se anota
  -- aca mismo, antes de mover nada. El cron gv-tandas-codigos-usados lo haria igual, pero cada 10
  -- min: esto cierra la ventana de una tanda creada y renombrada entre dos corridas.
  insert into public."GV_Tandas_Codigos_Usados" (codigo, fuente) values (v_a, 'renombrada')
    on conflict (codigo) do nothing;
  insert into public."GV_Tandas_Codigos_Usados" (codigo, fuente) values (v_b, 'renombrada')
    on conflict (codigo) do nothing;

  update public."Registros_Produccion_Virgilio" r set texto = v_b where upper(btrim(r.texto)) = v_a;
  get diagnostics v_n = row_count;

  -- v19.76 (problema 413) — idem `gv_ppp_nps_mover_a`: el campo de la tanda depende del evento.
  update public."Registros_Produccion_Virgilio" r
     set texto = public.gv_evento_set_tanda(r.opcion, r.texto, v_b)
   where public.gv_evento_tanda(r.opcion, r.texto) = v_a
     and public.gv_evento_set_tanda(r.opcion, r.texto, v_b) is not null;

  update public."Entregas_Virgilio" e set tanda = v_b where upper(btrim(e.tanda)) = v_a;
  update public."Facturacion_NP" f set tanda = v_b where upper(btrim(f.tanda)) = v_a;

  -- v19.69 (problema 407) — EL STOCK DEL PIPELINE NO SE PUEDE RENOMBRAR A CIEGAS: se FUSIONA.
  -- Primero el DELETE y despues el UPDATE: `trigger_actualizar_saldo_stock` no corre en DELETE.
  -- v20.00: el comentario viejo decia que el PKC "hoy no lo renombra nadie". YA NO ES CIERTO: el
  -- update de arriba matchea por gv_evento_tanda sin filtro de campo, y para un PKC eso resuelve el
  -- campo 1 (medido: gv_evento_set_tanda(PKC, "E12L|066|...", "E12K") devuelve "E12K|066|..."). Un
  -- comentario que miente es como se equivoca la proxima sesion.
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

  -- v20.04 (Thomas, 18/09) — LOS REF CON PIPE TAMBIEN VIAJAN.
  -- El facturado no se anota con la tanda sola: se anota `TANDA|NP` (E03G|CH 0010). El update de
  -- arriba compara por igualdad exacta, asi que esos nunca matcheaban y se quedaban con el codigo
  -- VIEJO mientras el picking, el armado y la facturacion viajaban al nuevo. Resultado medido:
  -- E03G quedo en -140 y E44A con +140 de mas; D71B en -72 y E40A con +72. Ninguna caja se
  -- pierde —la suma da cero— pero la pila de cada tanda miente y el centinela vive en rojo.
  -- Misma fusion que arriba, por la misma razon: `facturado` esta dentro de
  -- `mov_stock_pipeline_dedup`, asi que si el destino ya tiene esa fila hay que SUMAR, no chocar.
  -- Y el DELETE va antes del UPDATE porque `trigger_actualizar_saldo_stock` no corre en DELETE.
  create temp table if not exists _tr_pipe (id_dest bigint primary key, suma numeric) on commit drop;
  delete from _tr_pipe where true;
  insert into _tr_pipe (id_dest, suma)
  select d.id, sum(v.delta)
    from public."Movimientos_Stock" v
    join public."Movimientos_Stock" d
      on d.tipo = v.tipo and d.deposito = v.deposito
     and upper(btrim(d.cod_art)) = upper(btrim(v.cod_art))
     and coalesce(d.empresa, '') = coalesce(v.empresa, '')
     and upper(btrim(coalesce(d.ref, ''))) = v_b || substr(upper(btrim(v.ref)), length(v_a) + 1)
     and d.tipo in ('picking', 'separado', 'facturado')
   where upper(btrim(coalesce(v.ref, ''))) like v_a || '|%'
     and v.tipo in ('picking', 'separado', 'facturado')
   group by d.id;

  delete from public."Movimientos_Stock" v
   where upper(btrim(coalesce(v.ref, ''))) like v_a || '|%'
     and v.tipo in ('picking', 'separado', 'facturado')
     and exists (select 1 from public."Movimientos_Stock" d
                  where d.tipo = v.tipo and d.deposito = v.deposito
                    and upper(btrim(d.cod_art)) = upper(btrim(v.cod_art))
                    and coalesce(d.empresa, '') = coalesce(v.empresa, '')
                    and upper(btrim(coalesce(d.ref, ''))) = v_b || substr(upper(btrim(v.ref)), length(v_a) + 1)
                    and d.tipo in ('picking', 'separado', 'facturado'));

  update public."Movimientos_Stock" d set delta = d.delta + f.suma
    from _tr_pipe f where d.id = f.id_dest;

  update public."Movimientos_Stock" m
     set ref = v_b || substr(btrim(m.ref), length(v_a) + 1)
   where upper(btrim(coalesce(m.ref, ''))) like v_a || '|%';

  -- v19.95 — EL CANDADO SE VA CON LA TANDA. `GV_Tandas_Lock` es unica por (tanda, fase): primero
  -- se borra la fila del origen cuyo destino YA tiene esa fase (el destino manda, es la tanda que
  -- sobrevive) y recien despues se renombra el resto; al reves el update choca con el unique.
  -- Sin esto el candado quedaba con el codigo VIEJO: trababa al operario sobre ese codigo
  -- ("ya la agarro Jhonny") y dejaba al codigo nuevo SIN candado, o sea reabrible.
  delete from public."GV_Tandas_Lock" l
   where upper(btrim(l.tanda)) = v_a
     and exists (select 1 from public."GV_Tandas_Lock" d
                  where upper(btrim(d.tanda)) = v_b and d.fase = l.fase);
  update public."GV_Tandas_Lock" l set tanda = v_b where upper(btrim(l.tanda)) = v_a;

  -- v20.19 — EL CANDADO VIEJO TAMBIEN. `Tandas_Lock` sigue viva: la escriben
  -- tanda_reservar y tanda_liberar, y tenia movimientos del 15/09. Mismo PK
  -- (tanda, fase) que GV_Tandas_Lock, asi que mismo tratamiento: primero el
  -- DELETE del origen que choca, despues el UPDATE. Un candado que se queda
  -- con el codigo viejo deja la tanda IMPICKEABLE para siempre (paso con E12L).
  delete from public."Tandas_Lock" l
   where upper(btrim(l.tanda)) = v_a
     and exists (select 1 from public."Tandas_Lock" d
                  where upper(btrim(d.tanda)) = v_b and d.fase = l.fase);
  update public."Tandas_Lock" l set tanda = v_b where upper(btrim(l.tanda)) = v_a;

  -- v20.00 (Thomas, 18/09) — LAS CUATRO TABLAS QUE FALTABAN. Al renombrar quedaban con el codigo
  -- viejo: las etiquetas de lio se imprimen con el codigo de la tanda, la conciliacion cruza por
  -- tanda, el override pisa la programacion de esa tanda y las tareas de faltante la nombran.
  -- ⚠ Faltantes_Avisados y Faltantes_Revisados tienen la tanda EN LA CLAVE PRIMARIA (tanda, cod):
  -- mismo tratamiento que el candado — primero el DELETE del origen que choca (manda el destino,
  -- que es la tanda que sobrevive) y recien despues el UPDATE; al reves explota el unique.
  delete from public."Faltantes_Avisados" o
   where upper(btrim(o.tanda)) = v_a
     and exists (select 1 from public."Faltantes_Avisados" d
                  where upper(btrim(d.tanda)) = v_b and d.cod = o.cod);
  update public."Faltantes_Avisados" set tanda = v_b where upper(btrim(tanda)) = v_a;

  delete from public."Faltantes_Revisados" o
   where upper(btrim(o.tanda)) = v_a
     and exists (select 1 from public."Faltantes_Revisados" d
                  where upper(btrim(d.tanda)) = v_b and d.cod = o.cod);
  update public."Faltantes_Revisados" set tanda = v_b where upper(btrim(tanda)) = v_a;

  update public."Etiquetas_Lio"               set tanda = v_b where upper(btrim(coalesce(tanda,''))) = v_a;
  update public."Faltantes_Tareas"            set tanda = v_b where upper(btrim(coalesce(tanda,''))) = v_a;
  update public."GV_Conciliacion_Facturacion" set tanda = v_b where upper(btrim(coalesce(tanda,''))) = v_a;
  update public."GV_PPP_Prog_Override"        set tanda = v_b where upper(btrim(coalesce(tanda,''))) = v_a;

  -- v20.30 (Luis, 21/09) — LAS DOS QUE FALTABAN, encontradas barriendo TODA columna
  -- `tanda` de public contra lo que la funcion tocaba. GV_Vehiculo_Propio dice que esa tanda va
  -- en la kangoo y NO en el camion (la lee gv_ppp_super_mezclado, entre otras): si se queda con
  -- el codigo viejo, la tanda renombrada vuelve a contar como camion. Comprobantes_ARCA guarda
  -- el remito electronico de la tanda. ⚠ GV_Vehiculo_Propio tiene la tanda de PK, asi que va el
  -- mismo tratamiento que el candado: primero el DELETE del origen que choca, despues el UPDATE.
  delete from public."GV_Vehiculo_Propio" o
   where upper(btrim(o.tanda)) = v_a
     and exists (select 1 from public."GV_Vehiculo_Propio" d where upper(btrim(d.tanda)) = v_b);
  update public."GV_Vehiculo_Propio" set tanda = v_b where upper(btrim(tanda)) = v_a;
  update public."Comprobantes_ARCA"  set tanda = v_b where upper(btrim(coalesce(tanda,''))) = v_a;

  -- ⚠ NO se tocan los LIBROS DE HISTORIA: GV_Desarmes, GV_Tanda_Anulada y
  -- GV_Stock_Drenaje_Bloqueado anotan que algo paso bajo ESE nombre, en ESE momento. Renombrarlos
  -- seria reescribir el pasado, que es lo contrario de para lo que existen.

  update public."GV_PPP_Armados_Espera" e set tanda = v_b where upper(btrim(coalesce(e.tanda, ''))) = v_a;
  update public."PPP_Web_Tandas" t set codigo = v_b
   where upper(btrim(t.codigo)) = v_a
     and not exists (select 1 from public."PPP_Web_Tandas" x where upper(btrim(x.codigo)) = v_b);
  delete from public."PPP_Web_Tandas" t where upper(btrim(t.codigo)) = v_a;
  return v_n;
end $function$;

-- ── 6. los centinelas (ya insertados; quedan aca para poder rehacerlos) ───────────────────────
-- insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version) values
--   ('gv_np_mover_guard','funcion','v_ex is null or x\.tanda <> v_ex', '…', 'Luis','v20.30'),
--   ('gv_ppp_nps_mover_a','funcion','gv_np_mover_guard\(v_nps, v_t, p_tanda_entera\)', '…', 'Luis','v20.30'),
--   ('gv_ppp_tanda_mover','funcion','end,\s*\n?\s*v_t\)', '…', 'Luis','v20.30'),
--   ('gv_ppp_tanda_renombrar','funcion','GV_Vehiculo_Propio', '…', 'Luis','v20.30');

-- ── ROLLBACK ──────────────────────────────────────────────────────────────────────────────────
-- Las definiciones anteriores estan en sql/gv_np_mover_guard_v2001.sql,
-- sql/gv_ppp_tanda_mover_v1911.sql y sql/gv_tanda_renombrar_ref_pipe_v2007.sql + v2019.
-- Para volver atras solo el guard (o sea, volver a bloquear tambien la tanda entera):
--   update public."GV_Reglas_Centinela" set activo = false where version = 'v20.30';
--   -- y en gv_ppp_nps_mover_a: perform public.gv_np_mover_guard(v_nps, v_t);   (sin el 3er arg)
