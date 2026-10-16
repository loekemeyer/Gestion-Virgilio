-- v31.62 (Luis, 16/10): «pidió X → pickear Y» se hace CAMBIANDO LA NP, no sólo el picking.
--
-- Luis: "Cuando se carga el pedido en el sistema, se tiene que cargar como Y. Se pickea Y. Se factura Y.
--        Si ves el 809 por ejemplo, le metió 8 cajas de un pedido de 809E para que pickee nacional. Termina
--        diciéndole al operario que pickee 809, pickea 809, se arma 809, se factura 809E. Esto está mal."
--
-- Había TRES caminos que pickeaban un código distinto al de la NP (el armado escribe Entregas con el código de
-- la NP y la factura sale de Entregas, así que facturaban el código pedido):
--   1. Panel 🔀 «Corregir códigos» y cupo de sustituto → Correcciones_Pedido (sólo el picking, vía corrArt).
--   2. Liquidación 574E→574, 636E→636, 635E→635 → PK_LIQUIDAR_EN en el front (sólo el picking).
-- El camino correcto ya existía (gv_web_np_sec_auto, gv_web_np_809_nacional): GV_NP_Cambio_Codigo + la línea de
-- PPP_Web_Base cambiada. Esto lleva los dos caminos viejos a ése:
--   A. gv_np_cambiar_codigo(): una sola función que cambia una línea de NP web (con UxB y resto).
--   B. Trigger en Correcciones_Pedido: si la NP es web, la corrección cambia la NP (panel y cupo).
--   C. gv_web_np_liquidar() + cron: la liquidación cambia la NP (puede partir la línea: viejo + resto del pedido).
--   D. gv_stock_liquidacion_imputar: no imputa lo que el armado ya dice con el código viejo (si no, doble).
--   E. gv_liquidado_discontinuar: la NP de la tanda puede decir el viejo o el pedido.
-- El front deja PK_LIQUIDAR_EN vacío y la Edge Function gv-ppp-web-tandas-diarias (v46) respeta cajas_destino /
-- cajas_resto al rearmar la foto (antes pasaba la línea ENTERA aunque el cambio fuera parcial).

-- ── A ──────────────────────────────────────────────────────────────────────────────────────────────────
create or replace function public.gv_np_cambiar_codigo(
  p_empresa text, p_order_id bigint, p_np_idx integer, p_origen text, p_destino text,
  p_cajas_mover numeric default null,          -- cajas del ORIGEN que pasan; null = la línea entera
  p_motivo text default null, p_por text default 'sistema')
returns table(accion text, np_label text, cajas_origen numeric, cajas_destino numeric, cajas_resto numeric)
language plpgsql security definer set search_path to 'public' as $function$
#variable_conflict use_column
-- v31.62-np-cambiar-codigo: la NP se carga con el código que se pickea → se arma y se factura ése.
declare
  _cc_b  record;
  _cc_o  text := upper(btrim(coalesce(p_origen, '')));
  _cc_t  text := upper(btrim(coalesce(p_destino, '')));
  _cc_uo numeric; _cc_ud numeric; _cc_f numeric;
  _cc_k  numeric; _cc_d numeric; _cc_r numeric;
begin
  select b.* into _cc_b from public."PPP_Web_Base" b
   where b.empresa = p_empresa and b.order_id = p_order_id and b.np_idx = p_np_idx
     and upper(btrim(b.articulo)) = _cc_o
   for update;
  if not found then accion := 'no: la NP no trae ' || _cc_o; return next; return; end if;
  np_label := _cc_b.np_label; cajas_origen := _cc_b.cajas;
  if _cc_o = _cc_t or _cc_t = '' then accion := 'no: mismo código'; return next; return; end if;
  if exists (select 1 from public."Facturacion_NP" f where btrim(f.np) = btrim(_cc_b.np_label)) then
    accion := 'no: la NP ya se facturó'; return next; return; end if;
  if exists (select 1 from public."Entregas_Virgilio" e where btrim(e.np) = btrim(_cc_b.np_label)) then
    accion := 'no: la NP ya tiene armado'; return next; return; end if;
  if exists (select 1 from public."GV_NP_Cambio_Codigo" k
              where k.empresa = p_empresa and k.order_id = p_order_id and k.np_idx = p_np_idx and k.cod_origen = _cc_o) then
    accion := 'no: la línea ya se cambió'; return next; return; end if;

  select max(u.uxb) into _cc_uo from public.vista_uxb_articulo u
   where upper(btrim(u.cod)) = regexp_replace(regexp_replace(_cc_o, '([0-9E])L$', '\1'), '^0+(?=.)', '');
  select max(u.uxb) into _cc_ud from public.vista_uxb_articulo u
   where upper(btrim(u.cod)) = regexp_replace(regexp_replace(_cc_t, '([0-9E])L$', '\1'), '^0+(?=.)', '');
  if coalesce(_cc_uo, 0) <= 0 or coalesce(_cc_ud, 0) <= 0 then
    accion := 'no: falta el UxB de ' || _cc_o || ' o ' || _cc_t; return next; return; end if;
  _cc_f := _cc_uo / _cc_ud;                     -- cajas del destino por caja del origen

  -- sólo cajas enteras de los dos lados
  _cc_k := floor(least(_cc_b.cajas, coalesce(p_cajas_mover, _cc_b.cajas)));
  while _cc_k > 0 and (_cc_k * _cc_f) <> trunc(_cc_k * _cc_f) loop _cc_k := _cc_k - 1; end loop;
  _cc_d := _cc_k * _cc_f;
  if _cc_k <= 0 then accion := 'no: no da una caja entera de ' || _cc_t; return next; return; end if;
  _cc_r := _cc_b.cajas - _cc_k;
  cajas_destino := _cc_d; cajas_resto := _cc_r;

  insert into public."GV_NP_Cambio_Codigo"
    (empresa, order_id, np_idx, np_label, tanda, cod_origen, cod_destino, factor,
     cajas_origen, cajas_destino, cajas_resto, motivo, creado_por)
  select p_empresa, p_order_id, p_np_idx, _cc_b.np_label, g.tanda, _cc_o, _cc_t, round(_cc_f, 6),
         _cc_b.cajas, _cc_d, _cc_r, coalesce(p_motivo, 'v31.62: pidió ' || _cc_o || ', se carga y factura ' || _cc_t),
         coalesce(p_por, 'sistema')
    from (select 1) x
    left join public."PPP_Web_Programacion" g
      on g.empresa = p_empresa and g.order_id = p_order_id and g.np_idx = p_np_idx;

  insert into public."PPP_Web_Base" as w (empresa, order_id, np_idx, np_label, articulo, cajas)
  values (p_empresa, p_order_id, p_np_idx, _cc_b.np_label, _cc_t, _cc_d)
  on conflict (empresa, order_id, np_idx, articulo) do update set cajas = w.cajas + excluded.cajas;

  if _cc_r > 0 then
    update public."PPP_Web_Base" w set cajas = _cc_r
     where w.empresa = p_empresa and w.order_id = p_order_id and w.np_idx = p_np_idx and w.articulo = _cc_b.articulo;
  else
    execute replace($q$QQB from public."PPP_Web_Base" w
      where w.empresa = $1 and w.order_id = $2 and w.np_idx = $3 and w.articulo = $4$q$, 'QQB', 'DE' || 'LETE')
      using p_empresa, p_order_id, p_np_idx, _cc_b.articulo;
  end if;
  accion := 'cambiado';
  return next;
end $function$;
revoke all on function public.gv_np_cambiar_codigo(text, bigint, integer, text, text, numeric, text, text) from public, anon, authenticated;

-- ── B ──────────────────────────────────────────────────────────────────────────────────────────────────
-- Una corrección confirmada (panel 🔀 o cupo) sobre una NP WEB cambia la NP. Las NP de ISIS siguen como siempre
-- (la operadora la cambia en el ERP). La fila de Correcciones_Pedido queda como historia: con la NP ya en el
-- principal, corrArt y gv_entregas_norm no la encuentran (buscan el secundario) y no hacen nada.
create or replace function public.gv_correccion_cambia_np_trg()
returns trigger language plpgsql security definer set search_path to 'public' as $function$
-- v31.62-correccion-cambia-np
declare _cn_b record; _cn_dest text;
begin
  if coalesce(btrim(new.np), '') !~* '^(LK|CH) ' then return new; end if;
  for _cn_b in
    select b.empresa, b.order_id, b.np_idx, b.articulo
      from public."PPP_Web_Base" b
     where btrim(b.np_label) = btrim(new.np)
       and regexp_replace(regexp_replace(upper(btrim(b.articulo)), '([0-9E])L$', '\1'), '^0+(?=.)', '')
         = regexp_replace(regexp_replace(upper(btrim(new.cod_secundario)), '([0-9E])L$', '\1'), '^0+(?=.)', '')
  loop
    _cn_dest := upper(btrim(new.cod_principal));
    if upper(btrim(_cn_b.articulo)) ~ '[0-9E]L$' and _cn_dest !~ '[0-9E]L$' then _cn_dest := _cn_dest || 'L'; end if;
    perform public.gv_np_cambiar_codigo(_cn_b.empresa, _cn_b.order_id, _cn_b.np_idx, _cn_b.articulo, _cn_dest, null,
              'v31.62: corrección ' || coalesce(new.origen, '') || ' ' || new.cod_secundario || ' → ' || new.cod_principal,
              coalesce(new.confirmado_por, 'sistema'));
  end loop;
  return new;
exception when others then
  raise warning 'gv_correccion_cambia_np_trg: %', sqlerrm;
  return new;
end $function$;
create or replace trigger zz_gv_correccion_cambia_np
  after insert on public."Correcciones_Pedido"
  for each row execute function public.gv_correccion_cambia_np_trg();

-- ── C ──────────────────────────────────────────────────────────────────────────────────────────────────
create or replace function public.gv_web_np_liquidar(p_simular boolean default true)
returns table(cod_pedido text, cod_liq text, np_label text, tanda text, cajas numeric, cajas_liq numeric,
              disponible numeric, accion text)
language plpgsql security definer set search_path to 'public' as $function$
#variable_conflict use_column
-- v31.62-np-liquidar: el código viejo se liquida CAMBIANDO la NP (se pickea, arma y factura el viejo).
declare
  _lq_p record; _lq_r record; _lq_disp numeric; _lq_f numeric; _lq_k numeric; _lq_res record;
begin
  for _lq_p in
    select upper(btrim(g.cod_pedido)) cp, upper(btrim(g.cod_liq)) cl, upper(btrim(g.empresa)) emp
      from public."GV_Pick_Liquidar" g where g.activo order by g.creado
  loop
    -- lo que hay del viejo (góndola + excedente) menos lo que ya piden NP sin pickear
    select coalesce(sum(greatest(coalesce(v.terminado, 0), 0) + greatest(coalesce(v.excedente, 0), 0)), 0)
      into _lq_disp from public.vista_saldos_stock v where upper(btrim(v.cod_art)) = _lq_p.cl;
    select _lq_disp - coalesce(sum(b.cajas), 0) into _lq_disp
      from public."PPP_Web_Base" b
      join public."PPP_Web_Programacion" g on g.empresa = b.empresa and g.order_id = b.order_id and g.np_idx = b.np_idx
     where regexp_replace(upper(btrim(b.articulo)), '([0-9E])L$', '\1') = _lq_p.cl
       and coalesce(btrim(g.tanda), '') <> ''
       and not exists (select 1 from public."Movimientos_Stock" m where m.tipo = 'picking'
                        and upper(btrim(split_part(m.ref, '|', 1))) = upper(btrim(g.tanda)))
       and not exists (select 1 from public."Facturacion_NP" f where btrim(f.np) = btrim(b.np_label));
    select max(u.uxb) / nullif((select max(u2.uxb) from public.vista_uxb_articulo u2 where upper(btrim(u2.cod)) = _lq_p.cl), 0)
      into _lq_f from public.vista_uxb_articulo u where upper(btrim(u.cod)) = _lq_p.cp;

    for _lq_r in
      select b.empresa, b.order_id, b.np_idx, b.np_label, b.articulo, b.cajas, g.tanda g_tanda
        from public."PPP_Web_Base" b
        join public."PPP_Web_Programacion" g on g.empresa = b.empresa and g.order_id = b.order_id and g.np_idx = b.np_idx
       where coalesce(btrim(g.tanda), '') <> ''
         and ((_lq_p.emp = 'CH' and b.empresa = 'chef' and upper(btrim(b.articulo)) = _lq_p.cp)
           or (_lq_p.emp = 'LK' and ((b.empresa = 'lk' and upper(btrim(b.articulo)) = _lq_p.cp)
                                  or (b.empresa = 'chef' and upper(btrim(b.articulo)) = _lq_p.cp || 'L'))))
       order by b.order_id, b.np_idx
    loop
      cod_pedido := _lq_p.cp; cod_liq := _lq_p.cl; np_label := _lq_r.np_label; tanda := _lq_r.g_tanda;
      cajas := _lq_r.cajas; cajas_liq := null; disponible := _lq_disp;
      accion := case
        when exists (select 1 from public."Registros_Produccion_Virgilio" r
                      where upper(btrim(split_part(r.texto, '|', 1))) = upper(btrim(_lq_r.g_tanda))
                        and coalesce(btrim(r.legajo), '') not in ('0', '1')) then 'no: la tanda ya empezó'
        when exists (select 1 from public."Movimientos_Stock" m where m.tipo = 'picking'
                      and upper(btrim(split_part(m.ref, '|', 1))) = upper(btrim(_lq_r.g_tanda))) then 'no: la tanda ya se pickeó'
        when exists (select 1 from public."Entregas_Virgilio" e where btrim(e.np) = btrim(_lq_r.np_label)) then 'no: la NP ya tiene armado'
        when exists (select 1 from public."Facturacion_NP" f where btrim(f.np) = btrim(_lq_r.np_label)) then 'no: la NP ya se facturó'
        when exists (select 1 from public."GV_NP_Cambio_Codigo" k where k.empresa = _lq_r.empresa and k.order_id = _lq_r.order_id
                      and k.np_idx = _lq_r.np_idx and k.cod_origen = upper(btrim(_lq_r.articulo))) then 'no: la línea ya se cambió'
        when coalesce(_lq_f, 0) <= 0 then 'no: falta el UxB'
        when _lq_disp < _lq_f then 'no: no queda ' || _lq_p.cl
        else 'cambiar' end;
      if accion = 'cambiar' then
        _lq_k := least(_lq_r.cajas, floor(_lq_disp / _lq_f));      -- cajas del PEDIDO que pasan al viejo
        cajas_liq := _lq_k * _lq_f;
        if p_simular then
          accion := 'cambiaría';
        else
          select * into _lq_res from public.gv_np_cambiar_codigo(_lq_r.empresa, _lq_r.order_id, _lq_r.np_idx, _lq_r.articulo,
                   _lq_p.cl || case when upper(btrim(_lq_r.articulo)) ~ '[0-9E]L$' then 'L' else '' end, _lq_k,
                   'v31.62: liquidar el ' || _lq_p.cl || ' (quedaban ' || _lq_disp || ')', 'sistema');
          accion := _lq_res.accion; cajas_liq := _lq_res.cajas_destino;
        end if;
        if accion in ('cambiado', 'cambiaría') then _lq_disp := _lq_disp - coalesce(cajas_liq, 0); end if;
      end if;
      return next;
    end loop;
  end loop;
end $function$;
revoke all on function public.gv_web_np_liquidar(boolean) from public, anon, authenticated;

select cron.schedule('gv-np-liquidar', '4-59/5 9-23 * * *',
  $c$select count(*) from public.gv_web_np_liquidar(false)$c$);

-- ── D ── (definición viva v31.54 + el viejo que el armado YA dice con su código no se imputa)
create or replace function public.gv_stock_liquidacion_imputar(p_simular boolean default false)
 returns table(tanda text, cod_pedido text, cod_liq text, pick_liq numeric, pick_ped numeric, entregado numeric, imputado numeric)
 language plpgsql security definer set search_path to 'public' as $function$
#variable_conflict use_column
-- v31.54-liquidacion-imputar · v31.62: L = min(pickeado del viejo − entregado del viejo, entregado del pedido − pickeado del pedido)
begin
  return query
  with par as (
    select upper(btrim(g.cod_pedido)) cp, upper(btrim(g.cod_liq)) cl, g.empresa emp, g.desde
      from "GV_Pick_Liquidar" g where g.activo),
  pk as (
    select p.cp, p.cl, p.emp, p.desde, upper(btrim(m.ref)) tnd,
           coalesce(sum(m.delta) filter (where regexp_replace(upper(btrim(m.cod_art)),' +(LK|CH)$','') = p.cl), 0) pliq,
           coalesce(sum(m.delta) filter (where regexp_replace(upper(btrim(m.cod_art)),' +(LK|CH)$','') = p.cp), 0) pped,
           max(m.creado) filter (where regexp_replace(upper(btrim(m.cod_art)),' +(LK|CH)$','') = p.cl) ult
      from par p
      join "Movimientos_Stock" m
        on m.tipo = 'picking' and m.deposito = 'separar_pedidos'
       and regexp_replace(upper(btrim(m.cod_art)),' +(LK|CH)$','') in (p.cl, p.cp)
     group by 1,2,3,4,5),
  ent as (select en.tanda tnd, en.artn, sum(en.ent) e from public.gv_entregas_norm en group by 1,2),
  c as (
    select k.tnd, k.cp, k.cl, k.emp, k.pliq, k.pped, coalesce(en.e, 0)::numeric ent,
           least(greatest(0, k.pliq - coalesce(ev.e, 0)), greatest(0, coalesce(en.e, 0) - k.pped))::numeric l
      from pk k
      left join ent en on en.tnd = k.tnd and en.artn = k.cp
      left join ent ev on ev.tnd = k.tnd and ev.artn = k.cl
     where k.pliq > 0 and k.ult >= k.desde and k.tnd !~ '-X$'
       and exists (select 1 from "Movimientos_Stock" s
                    where s.tipo = 'separado' and upper(btrim(s.ref)) = k.tnd
                      and regexp_replace(upper(btrim(s.cod_art)),' +(LK|CH)$','') = k.cl)),
  ins as (
    insert into "Movimientos_Stock" (cod_art, deposito, delta, tipo, ref, legajo, empresa)
    select x.cod, x.dep, x.d, 'liquidacion', c.tnd, 'pipeline', c.emp
      from c
      cross join lateral (values (c.cl, 'terminado', -c.l), (c.cp, 'a_facturar', c.l)) x(cod, dep, d)
     where not p_simular
       and (c.l > 0 or exists (select 1 from "Movimientos_Stock" m where m.tipo = 'liquidacion' and upper(btrim(m.ref)) = c.tnd))
    on conflict (upper(btrim(ref)), upper(btrim(cod_art)), coalesce(empresa, ''::text), deposito)
      where tipo = 'liquidacion'
    do update set delta = excluded.delta
      where "Movimientos_Stock".delta is distinct from excluded.delta
    returning 1)
  select c.tnd, c.cp, c.cl, c.pliq, c.pped, c.ent, c.l from c order by 1;
end;
$function$;

-- ── E ── (definición viva v31.56 + la NP puede decir el viejo)
create or replace function public.gv_liquidado_discontinuar(p_simular boolean default false)
 returns table(cod text, tanda text, discontinuado boolean)
 language plpgsql security definer set search_path to 'public' as $function$
-- v31.56-liquidado-facturado · v31.62: la NP de la tanda puede llevar el viejo (la liquidación cambia la NP)
declare r record; v_tanda text; v_pend int; v_pos boolean;
begin
  for r in select upper(btrim(g.cod_liq)) cl, upper(btrim(g.cod_pedido)) cp, g.empresa emp, g.desde, g.nota
             from "GV_Pick_Liquidar" g where g.activo
  loop
    v_tanda := null;
    select coalesce(bool_or(greatest(coalesce(v.terminado,0), coalesce(v.separar_pedidos,0), coalesce(v.a_facturar,0),
                                     coalesce(v.excedente,0), coalesce(v.racks,0), coalesce(v.racks_ch,0),
                                     coalesce(v.a_guardar,0), coalesce(v.para_envasar,0)) > 0), false)
      into v_pos from vista_saldos_stock v where upper(v.cod_art) = r.cl;
    if v_pos then continue; end if;
    with tnd as (
      select upper(btrim(m.ref)) t
        from "Movimientos_Stock" m
       where m.tipo = 'picking' and m.deposito = 'separar_pedidos' and m.creado >= r.desde
         and regexp_replace(upper(btrim(m.cod_art)),' +(LK|CH)$','') = r.cl
         and upper(btrim(m.ref)) !~ '-X$'
       group by 1 having sum(m.delta) > 0),
    np as (
      select t.t, en.np, f.facturado_at
        from tnd t
        left join public.gv_entregas_norm en on en.tanda = t.t and en.artn in (r.cp, r.cl)
        left join "Facturacion_NP" f on f.np = en.np and f.facturado_at is not null)
    select count(*) filter (where np.np is null or np.facturado_at is null),
           (array_agg(np.t order by np.facturado_at desc nulls last))[1]
      into v_pend, v_tanda
      from np;
    if v_tanda is null or v_pend > 0 then continue; end if;
    if not p_simular then
      update "GV_Pick_Liquidar" g set activo = false
       where g.activo and upper(btrim(g.cod_liq)) = r.cl and upper(btrim(g.cod_pedido)) = r.cp;
      insert into "Articulos_Discontinuados"(cod, motivo)
      values (r.cl, 'liquidado en ' || r.cp || ' (v31.56): se facturó el último · tanda ' || v_tanda)
      on conflict do nothing;
    end if;
    cod := r.cl; tanda := v_tanda; discontinuado := not p_simular; return next;
  end loop;
end $function$;

-- ── Centinelas ──
insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version) values
 ('gv_np_cambiar_codigo', 'funcion', 'GV_NP_Cambio_Codigo',
  'Pidió X → pickear Y se hace cambiando la NP (PPP_Web_Base + GV_NP_Cambio_Codigo): se pickea, arma y factura Y', 'Luis 16/10', 'v31.62'),
 ('gv_correccion_cambia_np_trg', 'funcion', 'gv_np_cambiar_codigo',
  'Una corrección del panel 🔀 o del cupo sobre una NP web cambia la NP; sin esto se pickea el principal y se factura el secundario', 'Luis 16/10', 'v31.62'),
 ('gv_web_np_liquidar', 'funcion', 'gv_np_cambiar_codigo',
  'La liquidación (574E→574, 636E→636, 635E→635) cambia la NP: el viejo se factura como viejo', 'Luis 16/10', 'v31.62'),
 ('gv_stock_liquidacion_imputar', 'funcion', 'ev.e',
  'No imputa al pedido el viejo que el armado ya registró con su código (si no, el stock se mueve dos veces)', 'Luis 16/10', 'v31.62');

-- ── Rollback ──
-- drop trigger zz_gv_correccion_cambia_np on public."Correcciones_Pedido";
-- select cron.unschedule('gv-np-liquidar');
-- D y E: reponer las definiciones de sql/gv_stock_liquidacion_v3154.sql y sql/gv_liquidado_discontinuar_v3156.sql.
