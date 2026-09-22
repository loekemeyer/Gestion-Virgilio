-- ============================================================================
-- v21.05 (Luis, 2026-09-22) — EL REGISTRO DEL ARMADO VIAJA CON EL PEDIDO
--
-- Luis, textual: "Pedido ARMADO tiene que tener el dato. Pedido que todavia no
-- armaron, no importa. Pedido en proceso ponemos que no se pueda mover hasta que
-- terminen de armarlo o lo cancelen y listo".
--
-- POR QUE. `TP` y `TAP` son eventos de la TANDA (texto = 'E29A', sin NP) y la pila de
-- stock va toda con `ref = <tanda>`: medido sobre E29A, sus seis filas
-- (picking/separado/facturado) van con ref = tanda y NINGUNA tiene NP. Renombrar no es
-- opcion, porque la tanda vieja sigue viva con los otros pedidos adentro. Por eso la
-- tanda NUEVA nacia sin registro de produccion y sin cajas: el monitor la mostraba
-- pendiente y el deposito re-pickeaba mercaderia que ya estaba en un pallet (E29A, 88
-- cajas el 21/09).
--
-- LOS TRES ESTADOS, que es la definicion de Luis:
--   · sin empezar  -> tanda nueva y listo, no hay nada que llevar.
--   · en proceso   -> NO SE MUEVE. Sus cajas estan en la pila de la tanda sin separar
--                     por pedido (eso recien pasa en el armado): no hay porcion que
--                     llevarse. Se termina de armar o se cancela.
--   · armado       -> se mueve CON su registro: TP + TAP copiados, sus filas de
--                     Entregas_Virgilio, y su porcion de `a_facturar`.
--
-- MEDIDO, en transaccion abortada sobre E29C (6 NP, 176 cajas en a_facturar):
--   LK 0101 -> E75A · a_facturar E29C 176->104 + nueva 72 = 176 · GLOBAL sin cambio
--   (615->615, diferencia 0) · separar_pedidos 0 en las dos · 2 eventos en la nueva ·
--   19 filas de Entregas · el aviso trae ROTULAR · gv_stock_tanda_pickeado_negativo = 0.
--   CH 0025 (pickeada sin armar) -> EN_PROCESO, frenado.
--   Y el guard llamado DIRECTO, sin la senal, sigue frenando el armado.
--
-- ⚠ NO se copian los PKC. Medido: copiarlos dispara `reconciliar_stock_articulo_rt` y
--   re-pickea (gondola -85 -> -194, separar_pedidos 0 -> +106). El picking de la tanda
--   vieja se queda donde esta; lo que viaja es la PORCION, como `ajuste`, que ni el
--   reconciliador de etapa 1 ni el de etapa 2 recalculan.
--
-- ⚠ Las copias van con `ts_inicio = ts_cliente` (duracion CERO). El trabajo ya se conto
--   en la tanda vieja; con la duracion original el mismo picking sumaria dos veces en la
--   productividad del legajo.
--
-- ⚠ Y el bloque de arriba se aplico MAL la primera vez: las lineas se concatenaron con
--   `\n` dentro de comillas simples, o sea BARRA-N literal, asi que el guard entero quedo
--   comentado (una sola linea que empieza con `--`). El CREATE salio limpio y la funcion
--   corrio igual. Lo caza la PRUEBA, no la lectura: el caso 2 frenaba con el mensaje
--   viejo. Al parchear por texto, los saltos van con `chr(10)`.
-- ============================================================================

-- ── 1. La etapa 2 se puede SILENCIAR dentro de una transaccion ──────────────────
-- Sin esto el movimiento es imposible de hacer bien: el trigger corre AFTER STATEMENT,
-- o sea que ve los estados INTERMEDIOS, y `reconciliar_pipeline_stock_etapa2` reparte
-- contra `Entregas_Virgilio`:
--   · moviendo las Entregas ANTES del stock, el bloque B ve `entregado` mas chico con el
--     mismo `pick` y manda la diferencia a `terminado`: cajas FANTASMA en gondola.
--   · moviendo el stock ANTES de las Entregas, la tanda nueva entra al bloque A con
--     `entregado = 0` y manda TODO a `terminado`: lo mismo, peor.
-- La unica forma correcta es hacer las tres cosas y reconciliar UNA vez al final.
-- Es aditivo: sin el flag se comporta exactamente como siempre.
create or replace function public.trg_entregas_reconciliar()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  -- v21.05: `gv.sin_reconciliar` lo prende (LOCAL a la transaccion) el movimiento de un
  -- pedido armado, que reconcilia una sola vez al final. Cualquier otro camino no lo
  -- setea nunca y entra por el mismo lugar de siempre.
  if coalesce(current_setting('gv.sin_reconciliar', true), '') = '1' then
    return null;
  end if;
  perform public.reconciliar_pipeline_stock_etapa2();
  return null;
exception when others then
  return null;
end;
$function$;

-- ── 2. El movimiento del registro ───────────────────────────────────────────────
create or replace function public.gv_ppp_pedido_llevar_registro(
  p_nps text[], p_vieja text, p_nueva text, p_por text default null)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_v text := upper(btrim(coalesce(p_vieja, '')));
  v_n text := upper(btrim(coalesce(p_nueva, '')));
  v_nps text[]; v_ev int := 0; v_ent int := 0; v_mov int := 0;
  v_cajas numeric := 0; v_leg text;
begin
  if v_v = '' or v_n = '' or v_v = v_n then return jsonb_build_object('hizo', false, 'motivo', 'sin tandas'); end if;
  select array_agg(distinct regexp_replace(upper(btrim(x)), '\.0+$', ''))
    into v_nps from unnest(coalesce(p_nps, array[]::text[])) x where btrim(x) <> '';
  if v_nps is null or array_length(v_nps, 1) = 0 then return jsonb_build_object('hizo', false, 'motivo', 'sin NP'); end if;

  perform set_config('gv.sin_reconciliar', '1', true);

  -- (a) los CIERRES de la tanda: TP (pickeada) y TAP (armada). Sin esto la tanda nueva
  --     figura pendiente y el deposito la vuelve a pickear.
  insert into public."Registros_Produccion_Virgilio"
    (client_id, legajo, opcion, descripcion, texto, ts_cliente, ts_inicio, gv_app)
  select 'mv_' || v_n || '_' || o.opcion || '_' || v_v, o.legajo, o.opcion,
         coalesce(o.descripcion, o.opcion) || ' (viene de ' || v_v || ')',
         v_n, o.ts_cliente, o.ts_cliente, 'gv'
    from (select distinct on (r.opcion) r.opcion, r.legajo, r.descripcion, r.ts_cliente
            from public."Registros_Produccion_Virgilio" r
           where r.opcion in ('TP','TAP') and upper(btrim(coalesce(r.texto,''))) = v_v
             and coalesce(btrim(r.legajo),'') not in ('0','1')
           order by r.opcion, r.ts_cliente desc) o
   where not exists (select 1 from public."Registros_Produccion_Virgilio" y
                      where y.opcion = o.opcion and upper(btrim(coalesce(y.texto,''))) = v_n)
  on conflict (client_id) do nothing;
  get diagnostics v_ev = row_count;

  -- (b) el registro POR NP de que tiene adentro cada pedido
  update public."Entregas_Virgilio" e set tanda = v_n
   where upper(btrim(coalesce(e.tanda,''))) = v_v
     and regexp_replace(upper(btrim(coalesce(e.np,''))), '\.0+$', '') = any (v_nps);
  get diagnostics v_ent = row_count;

  select (array_agg(r.legajo order by r.ts_cliente desc))[1] into v_leg
    from public."Registros_Produccion_Virgilio" r
   where r.opcion = 'TAP' and upper(btrim(coalesce(r.texto,''))) = v_n;

  -- (c) la PORCION de la pila. Medido: despues del armado `separar_pedidos` cierra en
  --     CERO y las cajas estan en `a_facturar` (E29C: sep 0 / a_facturar 176).
  --     Cuanto: lo que dice Entregas_Virgilio de ESAS NP — desde la v21.00 es un dato
  --     declarado por quien tiene el pallet delante, no una resta. Topeado contra lo que
  --     la pila tiene de verdad: nunca se le saca mas de lo que hay.
  --     La clave normaliza sufijo de empresa, ceros a la izquierda y la L del pedido
  --     (`438EL` del remito contra `438E LK` de la gondola).
  with nrm as (
    select regexp_replace(upper(regexp_replace(regexp_replace(trim(z.c),' +(LK|CH)$',''),'^0+(?=.)','')),
                          '([0-9E])L$','\1') k, z.c
      from (select distinct cod_art c from public."Entregas_Virgilio"
             where upper(btrim(coalesce(tanda,''))) = v_n) z),
  pedido as (
    select n.k, sum(coalesce(e.cajas_entregadas,0)) cajas
      from public."Entregas_Virgilio" e join nrm n on n.c = e.cod_art
     where upper(btrim(coalesce(e.tanda,''))) = v_n
     group by 1 having sum(coalesce(e.cajas_entregadas,0)) > 0),
  pila as (
    select regexp_replace(upper(regexp_replace(regexp_replace(trim(m.cod_art),' +(LK|CH)$',''),'^0+(?=.)','')),
                          '([0-9E])L$','\1') k,
           (array_agg(m.cod_art order by m.id))[1] cod_art,
           (array_agg(m.empresa order by m.id))[1] emp, sum(m.delta) net
      from public."Movimientos_Stock" m
     where m.deposito = 'a_facturar'
       and upper(btrim(split_part(coalesce(m.ref,''),'|',1))) = v_v
     group by 1 having sum(m.delta) > 0),
  pasa as (select p.cod_art, p.emp, least(p.net, d.cajas) qty
             from pila p join pedido d on d.k = p.k where least(p.net, d.cajas) > 0)
  insert into public."Movimientos_Stock"
    (cod_art, descripcion, deposito, delta, tipo, ref, legajo, empresa, client_id)
  select x.cod_art, '', 'a_facturar', x.delta, 'ajuste', x.ref,
         coalesce(nullif(btrim(coalesce(v_leg,'')),''), 'pipeline'), x.emp, x.cid
    from pasa cross join lateral (values
      (pasa.cod_art, -pasa.qty, v_v || '|MOV-' || v_n, pasa.emp,
       'movped_' || v_v || '_' || v_n || '_' || pasa.cod_art || '_out'),
      (pasa.cod_art,  pasa.qty, v_n || '|MOV-' || v_v, pasa.emp,
       'movped_' || v_v || '_' || v_n || '_' || pasa.cod_art || '_in')
    ) x(cod_art, delta, ref, emp, cid)
  on conflict do nothing;
  get diagnostics v_mov = row_count;

  select coalesce(sum(m.delta),0) into v_cajas from public."Movimientos_Stock" m
   where m.deposito='a_facturar' and m.tipo='ajuste'
     and upper(btrim(coalesce(m.ref,''))) = v_n || '|MOV-' || v_v;

  perform set_config('gv.sin_reconciliar', '0', true);
  perform public.reconciliar_pipeline_stock_etapa2();

  return jsonb_build_object('hizo', true, 'vieja', v_v, 'nueva', v_n, 'nps', v_nps,
    'eventos_copiados', v_ev, 'entregas_movidas', v_ent,
    'filas_stock', v_mov, 'cajas_pasadas', v_cajas);
end;
$function$;

revoke all on function public.gv_ppp_pedido_llevar_registro(text[], text, text, text) from public;
revoke all on function public.gv_ppp_pedido_llevar_registro(text[], text, text, text) from anon;
revoke all on function public.gv_ppp_pedido_llevar_registro(text[], text, text, text) from authenticated;
grant execute on function public.gv_ppp_pedido_llevar_registro(text[], text, text, text) to service_role;

-- ── 3. Los dos PARCHES, idempotentes sobre la definicion VIVA ───────────────────
-- Igual que sql/gv_clin_dos_estados_v2086.sql: estas dos funciones las tocan varias
-- sesiones, asi que NO se reescriben enteras — se parchea encima de pg_get_functiondef,
-- y si el ancla no matchea se levanta un `raise` en vez de pisar una version vieja.
do $$
declare src text; nue text; a text; nl text := chr(10);
begin
  -- 3.a el guard deja pasar el ARMADO solo cuando el llamador declara que el registro viaja
  src := pg_get_functiondef('public.gv_np_mover_guard(text[],text,text)'::regprocedure);
  if position('gv.pedido_lleva_registro' in src) = 0 then
    a := '     and (x.tiene_picking or x.tiene_armado)';
    if position(a in src) = 0 then raise exception 'gv_np_mover_guard: no matchea el ancla'; end if;
    nue := replace(src, a,
      '     -- v21.05 (Luis, 22/09) - el ARMADO ya no queda huerfano: gv_ppp_pedido_mover le COPIA' || nl ||
      '     -- el TP/TAP a la tanda nueva, le pasa su porcion de a_facturar y avisa POR PANTALLA que' || nl ||
      '     -- hay que re-rotular el pallet. Prende `gv.pedido_lleva_registro` (LOCAL a la' || nl ||
      '     -- transaccion) justo antes de mover, y si llevar_registro explota se cae todo junto:' || nl ||
      '     -- el movimiento y el registro son la misma transaccion.' || nl ||
      '     -- El PICKEADO SIN ARMAR sigue frenado siempre: sus cajas estan en la pila de la tanda,' || nl ||
      '     -- sin separar por pedido, y no hay porcion que llevarse.' || nl ||
      '     and ( (x.tiene_picking and not x.tiene_armado)' || nl ||
      '           or (x.tiene_armado and coalesce(current_setting(''gv.pedido_lleva_registro'', true), '''') <> ''1'') )');
    execute nue;
  end if;

  -- 3.b el mover: frena el EN PROCESO, prende la senal y lleva el registro
  src := pg_get_functiondef('public.gv_ppp_pedido_mover(text,date,text,text,boolean)'::regprocedure);
  if position('EN_PROCESO' in src) = 0 then
    raise exception 'gv_ppp_pedido_mover: falta el guard EN_PROCESO — aplicar el bloque 3.b a mano sobre la definicion viva (ver el .sql anterior a este en el historial)';
  end if;
  if position('gv_ppp_pedido_llevar_registro' in src) = 0 then
    raise exception 'gv_ppp_pedido_mover: falta la llamada a gv_ppp_pedido_llevar_registro';
  end if;
end $$;

-- ── 4. Los centinelas (ya insertados; el insert queda para un proyecto nuevo) ────
insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
values
 ('gv_ppp_pedido_mover','funcion','gv_ppp_pedido_llevar_registro',
  'Al mover un pedido ARMADO a una tanda nueva, el registro del armado (TP/TAP + Entregas + su porcion de la pila) viaja con el. Sin esto la tanda nueva nace pendiente y el deposito la re-pickea (caso E29A, 88 cajas).','Luis','v21.05'),
 ('gv_ppp_pedido_mover','funcion','EN_PROCESO',
  'Un pedido empezado y sin terminar de armar NO se mueve: sus cajas estan en la pila de la tanda sin separar por pedido. Se termina de armar o se cancela (Luis, 22/09).','Luis','v21.05'),
 ('gv_np_mover_guard','funcion','gv\.pedido_lleva_registro',
  'El guard deja pasar el ARMADO solo cuando el llamador declaro que el registro viaja. El PICKEADO SIN ARMAR sigue frenado siempre.','Luis','v21.05'),
 ('trg_entregas_reconciliar','funcion','sin_reconciliar',
  'La etapa 2 se puede silenciar dentro de la transaccion: el movimiento de un pedido armado toca eventos, Entregas y stock, y reconciliar en un estado intermedio manda cajas a gondola.','Luis','v21.05')
on conflict do nothing;

-- Chequeo:  select * from public.gv_reglas_perdidas;   -- vacia = todo bien
-- ⚠ EL FRENO SIGUE PUESTO hasta que Luis lo diga:
--     select valor from public."PPP_Web_Config" where clave = 'np_mover_frenado';   -- 1
--   Se levanta con:
--     update public."PPP_Web_Config" set valor = 0 where clave = 'np_mover_frenado';
