-- v22.58 (Luis, 2026-09-25) — ♻ RECUPERAR ITEMS DE FC: ajuste de stock opcional + candado por NP.
--
-- "Cuando se aprieta alguno de los botones, debería preguntar si quiere que se ajuste el stock
--  para sacar los items de góndola que se facturan … tiene que figurar en ese pedido … sin romper nada".
--
-- 1) Candado: pg_advisory_xact_lock por NP. Dos clics o dos supervisores a la vez: el segundo
--    espera, revalida el pendiente y se frena (probado: 2do frenado, grabado 1).
-- 2) p_ajustar_stock (default false). Si es true, por cada código se saca de góndola SÓLO lo que
--    todavía no salió:
--       ya salió sin facturar = (lo que Completar Pedido sumó después de la factura
--                                + lo que sacaron lotes anteriores) − lo ya complementado
--       a sacar = cajas del lote − ya salió sin facturar
--    Así un código completado con CP (que ya drenó góndola) no se descuenta dos veces.
--    Se saca de terminado → a_guardar → excedente, SÓLO lo que hay (nunca deja negativo); lo que
--    no alcanza queda anotado como faltante del ajuste, no se inventa.
--    Movimiento: tipo 'ajuste', ref '<NP>|FCC', client_id único por lote/código/depósito.
--    'ajuste' no lo reescribe ningún reconciliador (etapa 1 = picking, etapa 2 = separado).
--    El artículo y la empresa salen de gv_cod_stock_de_entrega / gv_empresa_de_entrega (la L).
-- 3) Figura en el pedido: GV_Fac_Complemento.cajas_stock / stock_detalle por línea, y
--    gv_fac_complemento_lista lo devuelve (cajas_stock, stock_faltante).

alter table public."GV_Fac_Complemento" add column if not exists cajas_stock numeric not null default 0;
alter table public."GV_Fac_Complemento" add column if not exists stock_detalle jsonb;

drop function if exists public.gv_fac_complemento_registrar(text, jsonb, text, text);
create or replace function public.gv_fac_complemento_registrar(
  p_np text, p_items jsonb, p_modo text, p_por text, p_ajustar_stock boolean default false)
returns uuid language plpgsql security definer set search_path to 'public' as $function$
declare
  v_lote uuid := gen_random_uuid();
  v_f record;
  r record;
  d record;
  v_pend numeric;
  v_cpd numeric;
  v_prev_stock numeric;
  v_prev_comp numeric;
  v_mover numeric;
  v_resta numeric;
  v_saldo numeric;
  v_n numeric;
  v_cs text;
  v_emp text;
  v_det jsonb;
  v_movido numeric;
  n int := 0;
begin
  if not (public.es_supervisor_virgilio() or public.gv_es_supervisor_o_servicio()) then
    raise exception 'Sólo un supervisor puede completar la facturación de un pedido';
  end if;
  if p_modo not in ('marcado','excel') then raise exception 'modo inválido: %', p_modo; end if;
  -- v22.56: un solo registro por NP a la vez (doble clic / dos supervisores): el segundo espera y revalida el pendiente.
  perform pg_advisory_xact_lock(hashtext('gv_fac_compl_lock|' || btrim(p_np)));
  select * into v_f from public."Facturacion_NP" where btrim(np) = btrim(p_np);
  if not found then raise exception 'La NP % no está facturada: se factura desde el Facturador', p_np; end if;

  for r in
    select btrim(x->>'cod') as cod, sum((x->>'cajas')::numeric) as cajas
      from jsonb_array_elements(coalesce(p_items,'[]'::jsonb)) x
     where coalesce((x->>'cajas')::numeric, 0) > 0
     group by 1
  loop
    select dd.pendiente, dd.completado_despues into v_pend, v_cpd
      from public.gv_fac_recuperar_detalle(v_f.np) dd where dd.cod_art = r.cod;
    if v_pend is null then raise exception 'El código % no está en la NP %', r.cod, v_f.np; end if;
    if r.cajas > v_pend then
      raise exception 'El código % tiene % cajas pendientes de facturar y se marcaron %', r.cod, v_pend, r.cajas;
    end if;

    v_det := null; v_movido := 0;
    if coalesce(p_ajustar_stock, false) then
      select coalesce(sum(c.cajas_stock),0), coalesce(sum(c.cajas),0) into v_prev_stock, v_prev_comp
        from public."GV_Fac_Complemento" c
       where c.np = v_f.np and c.anulado_at is null
         and canon_cod(regexp_replace(upper(btrim(c.cod_art)), '([0-9E])L$', '\1'))
           = canon_cod(regexp_replace(upper(r.cod), '([0-9E])L$', '\1'));
      v_mover := greatest(0, r.cajas - greatest(0, coalesce(v_cpd,0) + v_prev_stock - v_prev_comp));
      v_cs  := public.gv_cod_stock_de_entrega(r.cod, v_f.np, null);
      v_emp := public.gv_empresa_de_entrega(r.cod, v_f.np, null);
      v_resta := v_mover;
      v_det := '[]'::jsonb;
      for d in select unnest(array['terminado','a_guardar','excedente']) as dep loop
        exit when v_resta <= 0;
        select coalesce(sum(m.delta),0) into v_saldo from public."Movimientos_Stock" m
         where canon_cod(m.cod_art) = canon_cod(v_cs) and m.deposito = d.dep
           and (v_emp is null or upper(coalesce(m.empresa,'')) = upper(v_emp));
        v_n := least(v_resta, greatest(0, v_saldo));
        if v_n > 0 then
          insert into public."Movimientos_Stock"(cod_art, deposito, delta, tipo, ref, legajo, empresa, client_id)
          values (v_cs, d.dep, -v_n, 'ajuste', v_f.np || '|FCC', coalesce('sup:' || nullif(p_por,''), 'sup'),
                  coalesce(v_emp, 'Mixto'), 'fcc_' || v_lote || '_' || r.cod || '_' || d.dep);
          v_det := v_det || jsonb_build_object('deposito', d.dep, 'cajas', v_n);
          v_movido := v_movido + v_n; v_resta := v_resta - v_n;
        end if;
      end loop;
      v_det := jsonb_build_object('a_sacar', v_mover, 'sacado', v_movido, 'sin_stock', v_mover - v_movido,
                                  'ya_habia_salido', r.cajas - v_mover, 'movs', v_det);
    end if;

    insert into public."GV_Fac_Complemento"(lote, empresa, np, cod_cliente, cod_art, cajas, modo, creado_por, cajas_stock, stock_detalle)
    values (v_lote, public.gv_empresa_de_np_texto(v_f.np), v_f.np, v_f.cod_cliente, r.cod, r.cajas, p_modo, p_por,
            v_movido, v_det);
    n := n + 1;
  end loop;
  if n = 0 then raise exception 'No se marcó ningún código con cajas'; end if;
  return v_lote;
end $function$;
revoke all on function public.gv_fac_complemento_registrar(text, jsonb, text, text, boolean) from public, anon;
grant execute on function public.gv_fac_complemento_registrar(text, jsonb, text, text, boolean) to authenticated, service_role;

drop function if exists public.gv_fac_complemento_lista(text);
create or replace function public.gv_fac_complemento_lista(p_np text default null)
returns table(lote uuid, np text, empresa text, cod_cliente text, modo text, creado_por text, creado_at timestamptz,
              lineas integer, cajas numeric, items jsonb, doc_id bigint, factura text, factura_fecha date,
              factura_cajas numeric, ajusto_stock boolean, cajas_stock numeric, stock_faltante numeric)
language sql stable security definer set search_path to 'public' as $function$
  select c.lote, min(c.np), min(c.empresa), min(c.cod_cliente), min(c.modo), min(c.creado_por),
         min(c.creado_at), count(*)::int, sum(c.cajas),
         jsonb_agg(jsonb_build_object('cod', c.cod_art, 'cajas', c.cajas, 'stock', c.cajas_stock,
                                      'stock_detalle', c.stock_detalle) order by c.cod_art),
         min(d.doc_id),
         min(coalesce(dl.tipo, dc.tipo) || ' ' || coalesce(dl.punto_venta, dc.punto_venta) || '-' || coalesce(dl.numero, dc.numero)),
         min(coalesce(dl.fecha, dc.fecha)), min(coalesce(dl.total_cajas, dc.total_cajas)),
         bool_or(c.stock_detalle is not null), sum(c.cajas_stock),
         sum(coalesce((c.stock_detalle->>'sin_stock')::numeric, 0))
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
