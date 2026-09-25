-- v22.59 (Luis, 2026-09-25) — ♻ RECUPERAR ITEMS DE FC: el ajuste de stock es SÍ / NO con motivo.
--   "Queres que saquemos de gondola los articulos seleccionados?" · SÍ = se descuenta de góndola
--   (terminado) y PUEDE quedar negativo; el movimiento dice que fue por la facturación del complemento.
--   NO = hay que escribir por qué, y queda registrado en el lote (stock_detalle.motivo_no).
--   Se sigue sin descontar dos veces lo que ya salió con Completar Pedido después de facturar.
-- Reemplaza la de v22.58 (que sacaba sólo lo que había, de terminado → a_guardar → excedente).
drop function if exists public.gv_fac_complemento_registrar(text, jsonb, text, text, boolean);
create or replace function public.gv_fac_complemento_registrar(
  p_np text, p_items jsonb, p_modo text, p_por text,
  p_ajustar_stock boolean default null, p_motivo_no_stock text default null)
returns uuid language plpgsql security definer set search_path to 'public' as $function$
declare
  v_lote uuid := gen_random_uuid(); v_f record; r record;
  v_pend numeric; v_cpd numeric; v_prev_stock numeric; v_prev_comp numeric; v_mover numeric;
  v_cs text; v_emp text; v_det jsonb; v_movido numeric; n int := 0;
begin
  if not (public.es_supervisor_virgilio() or public.gv_es_supervisor_o_servicio()) then
    raise exception 'Sólo un supervisor puede completar la facturación de un pedido';
  end if;
  if p_modo not in ('marcado','excel') then raise exception 'modo inválido: %', p_modo; end if;
  -- v22.59: la pregunta del stock se contesta SIEMPRE; NO exige motivo.
  if p_ajustar_stock is null then raise exception 'Falta contestar si se saca de góndola'; end if;
  if not p_ajustar_stock and length(btrim(coalesce(p_motivo_no_stock,''))) < 3 then
    raise exception 'Si no se saca de góndola hay que escribir por qué';
  end if;
  -- v22.56: un solo registro por NP a la vez (doble clic / dos supervisores): el segundo espera y revalida el pendiente.
  perform pg_advisory_xact_lock(hashtext('gv_fac_compl_lock|' || btrim(p_np)));
  select * into v_f from public."Facturacion_NP" where btrim(np) = btrim(p_np);
  if not found then raise exception 'La NP % no está facturada: se factura desde el Facturador', p_np; end if;
  for r in
    select btrim(x->>'cod') as cod, sum((x->>'cajas')::numeric) as cajas
      from jsonb_array_elements(coalesce(p_items,'[]'::jsonb)) x
     where coalesce((x->>'cajas')::numeric, 0) > 0 group by 1
  loop
    select dd.pendiente, dd.completado_despues into v_pend, v_cpd
      from public.gv_fac_recuperar_detalle(v_f.np) dd where dd.cod_art = r.cod;
    if v_pend is null then raise exception 'El código % no está en la NP %', r.cod, v_f.np; end if;
    if r.cajas > v_pend then
      raise exception 'El código % tiene % cajas pendientes de facturar y se marcaron %', r.cod, v_pend, r.cajas;
    end if;
    v_movido := 0;
    if p_ajustar_stock then
      -- lo que Completar Pedido ya sacó después de facturar no se descuenta dos veces
      select coalesce(sum(c.cajas_stock),0), coalesce(sum(c.cajas),0) into v_prev_stock, v_prev_comp
        from public."GV_Fac_Complemento" c
       where c.np = v_f.np and c.anulado_at is null
         and canon_cod(regexp_replace(upper(btrim(c.cod_art)), '([0-9E])L$', '\1'))
           = canon_cod(regexp_replace(upper(r.cod), '([0-9E])L$', '\1'));
      v_mover := greatest(0, r.cajas - greatest(0, coalesce(v_cpd,0) + v_prev_stock - v_prev_comp));
      v_cs  := public.gv_cod_stock_de_entrega(r.cod, v_f.np, null);
      v_emp := public.gv_empresa_de_entrega(r.cod, v_f.np, null);
      if v_mover > 0 then
        -- v22.59 (Luis): se descuenta de góndola aunque quede en negativo; el movimiento dice por qué.
        insert into public."Movimientos_Stock"(cod_art, deposito, delta, tipo, ref, legajo, empresa, descripcion, client_id)
        values (v_cs, 'terminado', -v_mover, 'ajuste', v_f.np || '|FCC', coalesce('sup:' || nullif(p_por,''), 'sup'),
                coalesce(v_emp, 'Mixto'),
                'Sale de góndola: facturado con «Recuperar items de FC» (NP ' || v_f.np || ', ' ||
                  case p_modo when 'excel' then 'Excel ISIS' else 'marcado a mano' end || ')',
                'fcc_' || v_lote || '_' || r.cod);
        v_movido := v_mover;
      end if;
      v_det := jsonb_build_object('ajusta', true, 'sacado', v_movido, 'ya_habia_salido', r.cajas - v_mover,
                                  'deposito', 'terminado');
    else
      v_det := jsonb_build_object('ajusta', false, 'motivo_no', btrim(p_motivo_no_stock));
    end if;
    insert into public."GV_Fac_Complemento"(lote, empresa, np, cod_cliente, cod_art, cajas, modo, creado_por, cajas_stock, stock_detalle)
    values (v_lote, public.gv_empresa_de_np_texto(v_f.np), v_f.np, v_f.cod_cliente, r.cod, r.cajas, p_modo, p_por, v_movido, v_det);
    n := n + 1;
  end loop;
  if n = 0 then raise exception 'No se marcó ningún código con cajas'; end if;
  return v_lote;
end $function$;
revoke all on function public.gv_fac_complemento_registrar(text, jsonb, text, text, boolean, text) from public, anon;
grant execute on function public.gv_fac_complemento_registrar(text, jsonb, text, text, boolean, text) to authenticated, service_role;

drop function if exists public.gv_fac_complemento_lista(text);
create or replace function public.gv_fac_complemento_lista(p_np text default null)
returns table(lote uuid, np text, empresa text, cod_cliente text, modo text, creado_por text, creado_at timestamptz,
              lineas integer, cajas numeric, items jsonb, doc_id bigint, factura text, factura_fecha date,
              factura_cajas numeric, ajusto_stock boolean, cajas_stock numeric, motivo_no_stock text)
language sql stable security definer set search_path to 'public' as $function$
  select c.lote, min(c.np), min(c.empresa), min(c.cod_cliente), min(c.modo), min(c.creado_por),
         min(c.creado_at), count(*)::int, sum(c.cajas),
         jsonb_agg(jsonb_build_object('cod', c.cod_art, 'cajas', c.cajas, 'stock', c.cajas_stock,
                                      'stock_detalle', c.stock_detalle) order by c.cod_art),
         min(d.doc_id),
         min(coalesce(dl.tipo, dc.tipo) || ' ' || coalesce(dl.punto_venta, dc.punto_venta) || '-' || coalesce(dl.numero, dc.numero)),
         min(coalesce(dl.fecha, dc.fecha)), min(coalesce(dl.total_cajas, dc.total_cajas)),
         bool_or(coalesce((c.stock_detalle->>'ajusta')::boolean, false)), sum(c.cajas_stock),
         min(c.stock_detalle->>'motivo_no')
    from public."GV_Fac_Complemento" c
    left join public."GV_Fac_Complemento_Doc" d on d.lote = c.lote
    left join isis_lk.documentos dl on d.empresa = 'lk'   and dl.id = d.doc_id
    left join isis_ch.documentos dc on d.empresa = 'chef' and dc.id = d.doc_id
   where c.anulado_at is null
     and (p_np is null or c.np = btrim(p_np))
     and (public.es_supervisor_virgilio() or public.gv_es_supervisor_o_servicio())
   group by c.lote
   order by min(c.creado_at) desc;
$function$;
revoke all on function public.gv_fac_complemento_lista(text) from public, anon;
grant execute on function public.gv_fac_complemento_lista(text) to authenticated, service_role;
