-- v25.66 (Luis, 01/10) [los marcadores internos dicen v25.64-sinped: llave de idempotencia, no cambiar]: RECIBIR un importado SIN PEDIDO registrado.
-- La recepción necesita un bache; para lo que llega sin pedido se crea uno en la MISMA transacción, con
-- unidades = lo que llegó (nunca queda pendiente ni negativo), marcado sin_pedido = true y pedido_ref 'SIN PEDIDO'.
-- Anular la recepción o que Cervantes diga No → ese bache pasa a 'anulado' (no vuelve a figurar en viaje).
-- Rollback: drop function public.gv_imp_recibir_sin_pedido(bigint,text,numeric,jsonb,text,boolean,text);
--           drop function public.gv_imp_recibir_contexto_sin_pedido(bigint);
--           y revertir los dos parches (buscar 'v25.64-sinped').

alter table public."GV_Importados_Baches" add column if not exists sin_pedido boolean;

create or replace function public.gv_imp_recibir_contexto_sin_pedido(p_importado_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public' as $f$
declare v_id bigint; v_ctx jsonb;  -- v25.64-sinped
begin
  if not (public.es_supervisor_virgilio() or public.gv_es_supervisor_o_servicio()) then
    raise exception 'Sólo un supervisor puede recibir importaciones.' using errcode = '42501';
  end if;
  if not exists (select 1 from public."Importados" where id = p_importado_id) then raise exception 'Importado % no existe', p_importado_id; end if;
  begin
    insert into public."GV_Importados_Baches"(importado_id, cod_art, proveedor, marca, unidades, pedido_ref, estado, sin_pedido)
    select id, cod_art, proveedor, marca, 1, 'SIN PEDIDO', 'en_curso', true from public."Importados" where id = p_importado_id
    returning id into v_id;
    v_ctx := public.gv_imp_recibir_contexto(v_id);
    raise exception 'gv_rollback' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  return v_ctx || jsonb_build_object('bache_id', null, 'sin_pedido', true, 'importado_id', p_importado_id,
    'pedido_ref', 'SIN PEDIDO', 'unidades', 0, 'llegadas', 0, 'pendiente', 0);
end $f$;

create or replace function public.gv_imp_recibir_sin_pedido(p_importado_id bigint, p_empresa text, p_uni_x_caja numeric,
  p_destinos jsonb, p_nota text default null, p_simular boolean default true, p_client_id text default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $f$
declare im record; d jsonb; v_uxc numeric; v_uni numeric := 0; v_id bigint; v_r jsonb; v_prev record; v_por text;
        v_cid text := nullif(btrim(coalesce(p_client_id, '')), '');  -- v25.64-sinped
begin
  if not (public.es_supervisor_virgilio() or public.gv_es_supervisor_o_servicio()) then
    raise exception 'Sólo un supervisor puede recibir importaciones.' using errcode = '42501';
  end if;
  if not p_simular and v_cid is not null then
    select * into v_prev from public."GV_Imp_Recepcion" where client_id = v_cid;
    if found then
      return jsonb_build_object('ok', true, 'simulado', false, 'repetida', true, 'recepcion_id', v_prev.id, 'sin_pedido', true,
        'cajas', v_prev.cajas, 'unidades', v_prev.unidades, 'estado', v_prev.estado_bache, 'faltante', 0, 'sobra', 0);
    end if;
  end if;
  select * into im from public."Importados" where id = p_importado_id;
  if not found then raise exception 'Importado % no existe', p_importado_id; end if;
  if jsonb_typeof(p_destinos) <> 'array' then raise exception 'Falta indicar a dónde va la mercadería.'; end if;
  v_uxc := coalesce(nullif(p_uni_x_caja, 0), nullif(im.uni_x_caja, 0), 0);
  for d in select * from jsonb_array_elements(p_destinos) loop
    v_uni := v_uni + case when lower(coalesce(d->>'destino','')) = 'insumos'
                            or (lower(coalesce(d->>'destino','')) = 'cervantes' and lower(coalesce(d->>'unidad','')) in ('uni','u','unidades'))
                          then coalesce((d->>'cantidad')::numeric, 0)
                          else coalesce((d->>'cantidad')::numeric, 0) * v_uxc end;
  end loop;
  v_por := coalesce(nullif(auth.jwt()->>'email', ''), current_user);
  begin
    -- el pedido "es" lo que llegó: pendiente = recibido → nada queda en viaje y nada baja de cero
    insert into public."GV_Importados_Baches"(importado_id, cod_art, proveedor, marca, unidades, pedido_ref, estado, sin_pedido, creado_por)
    values (im.id, im.cod_art, im.proveedor, im.marca, greatest(1, round(v_uni))::int, 'SIN PEDIDO', 'en_curso', true, v_por)
    returning id into v_id;
    v_r := public.gv_imp_recibir(v_id, p_empresa, p_uni_x_caja, p_destinos, p_nota, p_simular, true, v_cid);
    if p_simular or not coalesce((v_r->>'ok')::boolean, false) then
      raise exception 'gv_rollback' using errcode = 'P0099';
    end if;
  exception when sqlstate 'P0099' then null;
  end;
  return v_r || jsonb_build_object('sin_pedido', true);
end $f$;

revoke all on function public.gv_imp_recibir_contexto_sin_pedido(bigint) from public, anon;
revoke all on function public.gv_imp_recibir_sin_pedido(bigint,text,numeric,jsonb,text,boolean,text) from public, anon;
grant execute on function public.gv_imp_recibir_contexto_sin_pedido(bigint) to authenticated, service_role;
grant execute on function public.gv_imp_recibir_sin_pedido(bigint,text,numeric,jsonb,text,boolean,text) to authenticated, service_role;

-- parches sobre la definición VIVA, idempotentes, fallan si el texto no matchea
do $p$ declare s text; n text;
begin
  s := pg_get_functiondef('public.gv_imp_recepcion_anular(bigint,text)'::regprocedure);
  if s !~ 'v25.64-sinped' then
    n := replace(s, $$estado = coalesce(r.estado_antes, 'en_curso'), actualizado = now()$$,
      $$estado = case when b.sin_pedido then 'anulado' else coalesce(r.estado_antes, 'en_curso') end, actualizado = now()  -- v25.64-sinped$$);
    if n = s then raise exception 'anular: el texto no matcheó'; end if;
    execute n;
  end if;
  s := pg_get_functiondef('public.gv_ingreso_virgilio_denegado()'::regprocedure);
  if s !~ 'v25.64-sinped' then
    n := replace(s, $$round(v_uni)::int), estado = 'en_curso', actualizado = now()$$,
      $$round(v_uni)::int), estado = case when b.sin_pedido then 'anulado' else 'en_curso' end, actualizado = now()  -- v25.64-sinped$$);
    if n = s then raise exception 'denegado: el texto no matcheó'; end if;
    execute n;
  end if;
end $p$;

-- y el retorno de anular dice 'anulado' para el bache sin pedido (aplicado igual, marcador v25.64-sinped-ret)
do $p$ declare s text; n text;
begin
  s := pg_get_functiondef('public.gv_imp_recepcion_anular(bigint,text)'::regprocedure);
  if s !~ 'v25.64-sinped-ret' then
    n := replace(s, $$'bache_estado', coalesce(r.estado_antes, 'en_curso'));$$,
      $$'bache_estado', case when b.sin_pedido then 'anulado' else coalesce(r.estado_antes, 'en_curso') end);  -- v25.64-sinped-ret$$);
    if n = s then raise exception 'ret: no matcheó'; end if;
    execute n;
  end if;
end $p$;
-- Probado en transacción abortada (01/10): 323ES sin pedido, 100 u a insumos AD04 → bache 100/100 llegado 'SIN PEDIDO',
-- simular no deja bache, en curso del importado queda en 0 (nunca negativo), anular → bache 'anulado'.
