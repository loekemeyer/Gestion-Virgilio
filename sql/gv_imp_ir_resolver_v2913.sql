-- (Se aplicó con la etiqueta v29.11: los marcadores y centinelas de la base dicen v29.11 — llave, no cambiar. Salió como v29.13.)
-- v29.11 (Luis, 09/10): la recepción de los operarios (Ingreso a racks → 📦 Importación) mueve el stock y
-- AVISA al módulo de Importación «se recibió esto». El operario NO elige el pedido: eso se resuelve en el
-- módulo (solapa 📥 Recibido), donde un supervisor ve contra qué pedido se descontó y lo puede cambiar.
--   · un solo pedido en viaje de ese código → se descuenta solo (como desde la v28.96) y queda en el aviso
--   · DOS O MÁS pedidos en viaje           → NO se descuenta: queda «a elegir» en el aviso, con los candidatos
--   · ↔ Cambiar de pedido / sin pedido     → gv_imp_ir_asignar deshace la imputación y la rehace contra el elegido
-- El stock NO se toca nunca acá: ya entró con el ingreso a racks.
-- REGLA_CONFIRMADA_POR_USUARIO (Luis 09/10: "que eso se resuelva en el modulo de importacion")

alter table public."GV_Imp_Ingreso_Racks_Log"
  add column if not exists revisado_en timestamptz,
  add column if not exists revisado_por text,
  add column if not exists candidatos jsonb;

create or replace function public.gv_imp_imputar_ingreso_racks(p_mov_id bigint, p_legajo text default null)
 returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp'
as $function$
declare m record; b record; v_cod text; v_dual boolean; v_uxc numeric; v_uni numeric; v_pend numeric;
        v_estado text; v_rec bigint; v_emp text; v_cid text := 'irmov_' || p_mov_id; v_es_imp boolean;
        v_forzado bigint := nullif(current_setting('gv.ir_bache', true), '')::bigint;   -- v29.11-ir-elegir
        v_ncand int; v_cand jsonb;
begin  -- v28.96-imp-ir
  select * into m from public."Movimientos_Stock" where id = p_mov_id;
  if not found or m.tipo <> 'ingreso' or m.deposito not in ('racks','racks_ch') or coalesce(m.delta,0) <= 0 then
    return jsonb_build_object('ok', false, 'motivo', 'no es un ingreso a racks');
  end if;
  if exists (select 1 from public."GV_Imp_Recepcion" where client_id = v_cid and anulada_en is null) then
    return jsonb_build_object('ok', true, 'repetida', true);
  end if;
  v_cod := upper(regexp_replace(btrim(m.cod_art), '([0-9E])L$', '\1'));
  v_emp := upper(coalesce(m.empresa, 'LK'));
  v_es_imp := exists (select 1 from public."Importados" i where public.gv_cod_stock(upper(btrim(i.cod_art))) = public.gv_cod_stock(v_cod));
  if not v_es_imp then return jsonb_build_object('ok', false, 'motivo', 'no es importado'); end if;
  v_dual := exists (select 1 from public.codigos_duales x where x.cod = public.gv_cod_stock(v_cod));
  -- v29.11: con DOS o más pedidos en viaje no se adivina: queda a elegir en el módulo de Importación
  if v_forzado is null then
    select count(*), jsonb_agg(jsonb_build_object('bache_id', bb.id, 'pedido_ref', bb.pedido_ref, 'proveedor', bb.proveedor,
             'unidades', bb.unidades, 'llegadas', bb.unidades_llegadas, 'reingreso', bb.fecha_reingreso)
             order by bb.fecha_reingreso nulls last, bb.id)
      into v_ncand, v_cand
      from public."GV_Importados_Baches" bb join public."Importados" im on im.id = bb.importado_id
     where bb.estado = 'en_curso' and bb.unidades > bb.unidades_llegadas
       and public.gv_cod_stock(upper(regexp_replace(btrim(bb.cod_art), '([0-9E])L$', '\1'))) = public.gv_cod_stock(v_cod)
       and (not v_dual or (case when upper(coalesce(bb.marca, im.marca, '')) in ('CH','CHEF') then 'CH' else 'LK' end) = v_emp);
    if v_ncand > 1 then
      insert into public."GV_Imp_Ingreso_Racks_Log"(mov_id, cod_art, cajas, legajo, sector, resultado, motivo, candidatos)
      values (p_mov_id, v_cod, m.delta, coalesce(p_legajo, m.legajo), m.ubicacion, 'a_elegir',
              v_ncand || ' pedidos en viaje de ese código: se elige en Importación', v_cand)
      on conflict (mov_id) do update set resultado = excluded.resultado, motivo = excluded.motivo, candidatos = excluded.candidatos,
        bache_id = null, recepcion_id = null, unidades = null;
      return jsonb_build_object('ok', false, 'motivo', 'a elegir', 'candidatos', v_cand);
    end if;
  end if;
  select bb.*, coalesce(nullif(im.uni_x_caja, 0),
          (select nullif(v.uni_inner, 0) from public."Importados_Volumen" v where v.cod = bb.cod_art limit 1)) uxc
    into b
    from public."GV_Importados_Baches" bb join public."Importados" im on im.id = bb.importado_id
   where (case when v_forzado is null then bb.estado = 'en_curso' and bb.unidades > bb.unidades_llegadas
               else bb.id = v_forzado and bb.estado <> 'anulado' end)
     and public.gv_cod_stock(upper(regexp_replace(btrim(bb.cod_art), '([0-9E])L$', '\1'))) = public.gv_cod_stock(v_cod)
     and (v_forzado is not null or not v_dual or (case when upper(coalesce(bb.marca, im.marca, '')) in ('CH','CHEF') then 'CH' else 'LK' end) = v_emp)
   order by bb.fecha_reingreso nulls last, bb.id
   limit 1
   for update of bb;
  if not found then
    insert into public."GV_Imp_Ingreso_Racks_Log"(mov_id, cod_art, cajas, legajo, sector, resultado, motivo)
    values (p_mov_id, v_cod, m.delta, coalesce(p_legajo, m.legajo), m.ubicacion, 'sin_pedido',
            case when v_forzado is null then 'no hay pedido de importación en viaje de ese código' else 'el pedido elegido no es de ese código' end)
    on conflict (mov_id) do update set resultado = excluded.resultado, motivo = excluded.motivo, bache_id = null, recepcion_id = null, unidades = null;
    return jsonb_build_object('ok', false, 'motivo', case when v_forzado is null then 'sin pedido en viaje' else 'pedido de otro código' end);
  end if;
  v_uxc := b.uxc;
  if v_uxc is null then
    insert into public."GV_Imp_Ingreso_Racks_Log"(mov_id, cod_art, cajas, legajo, sector, resultado, bache_id, motivo)
    values (p_mov_id, v_cod, m.delta, coalesce(p_legajo, m.legajo), m.ubicacion, 'sin_uni_x_caja', b.id, 'falta unidades por caja en Importados')
    on conflict (mov_id) do update set resultado = excluded.resultado, motivo = excluded.motivo, bache_id = excluded.bache_id, recepcion_id = null, unidades = null;
    return jsonb_build_object('ok', false, 'motivo', 'sin unidades por caja');
  end if;
  v_uni := round(m.delta * v_uxc);
  v_pend := greatest(0, b.unidades - b.unidades_llegadas);
  v_estado := case when b.unidades_llegadas + v_uni >= b.unidades then 'llegado' else 'en_curso' end;
  insert into public."GV_Imp_Recepcion"(bache_id, importado_id, cod_art, empresa, proveedor, pedido_ref, unidades, uni_x_caja, cajas,
    pendiente_antes, estado_bache, por, legajo, nota, client_id, faltante, sobrante, cerro_bache, estado_antes, llegadas_antes)
  values (b.id, b.importado_id, b.cod_art, v_emp, b.proveedor, b.pedido_ref, v_uni, v_uxc, m.delta,
    v_pend, v_estado, case when v_forzado is null then 'operario · Ingreso a racks' else 'operario · Ingreso a racks (pedido elegido en Importación)' end,
    coalesce(p_legajo, m.legajo),
    'Ingreso a racks ' || coalesce(m.ubicacion, '') || ' (operario, mov ' || p_mov_id || ')', v_cid,
    0, greatest(0, v_uni - v_pend), v_estado = 'llegado', b.estado, b.unidades_llegadas)
  returning id into v_rec;
  -- sin fila de destino A PROPÓSITO: ↩ Anular sólo deshace la imputación al pedido y NO saca el stock
  insert into public."Importados_Mov_Stock"(ts, cod_art, marca, tipo, delta_uni, ref, legajo, creado)
  values (now(), b.cod_art, b.marca, 'ingreso', v_uni, 'recepcion importacion #' || v_rec || ' (ingreso a racks)', coalesce(p_legajo, m.legajo), now());
  update public."GV_Importados_Baches" set unidades_llegadas = unidades_llegadas + v_uni::int, estado = v_estado, actualizado = now()
   where id = b.id;
  perform public.gv_importados_resync_calc(b.importado_id);
  insert into public."GV_Imp_Ingreso_Racks_Log"(mov_id, cod_art, cajas, legajo, sector, resultado, bache_id, recepcion_id, unidades)
  values (p_mov_id, v_cod, m.delta, coalesce(p_legajo, m.legajo), m.ubicacion, 'imputado', b.id, v_rec, v_uni)
  on conflict (mov_id) do update set resultado = 'imputado', bache_id = excluded.bache_id, recepcion_id = excluded.recepcion_id,
    unidades = excluded.unidades, motivo = null;
  return jsonb_build_object('ok', true, 'recepcion_id', v_rec, 'bache_id', b.id, 'pedido_ref', b.pedido_ref,
    'unidades', v_uni, 'pendiente_antes', v_pend, 'estado', v_estado, 'sobra', greatest(0, v_uni - v_pend));
end $function$;
revoke execute on function public.gv_imp_imputar_ingreso_racks(bigint, text) from public, anon, authenticated;

-- ↔ Cambiar de pedido: deshace la imputación (si la hay) y la rehace contra el pedido elegido.
-- p_bache_id null = «no es de ningún pedido»: sólo deshace. NO toca el stock.
create or replace function public.gv_imp_ir_asignar(p_mov_id bigint, p_bache_id bigint)
 returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp'
as $function$
declare l record; r record; b record; v_por text; v_res jsonb;
begin  -- v29.11-ir-asignar
  if not (public.es_supervisor_virgilio() or public.gv_es_supervisor_o_servicio()) then
    raise exception 'SUPERVISOR: sólo un supervisor puede elegir el pedido de una recepción.' using errcode = '42501';
  end if;
  v_por := coalesce(nullif(auth.jwt()->>'email', ''), current_user);
  select * into l from public."GV_Imp_Ingreso_Racks_Log" where mov_id = p_mov_id for update;
  if not found then raise exception 'Ese ingreso a racks no está en el registro de Importación.'; end if;
  if l.recepcion_id is not null then
    select * into r from public."GV_Imp_Recepcion" where id = l.recepcion_id for update;
    if found and r.anulada_en is null then
      if r.bache_id is not distinct from p_bache_id then
        update public."GV_Imp_Ingreso_Racks_Log" set revisado_en = now(), revisado_por = v_por where mov_id = p_mov_id;
        return jsonb_build_object('ok', true, 'sin_cambio', true);
      end if;
      select * into b from public."GV_Importados_Baches" where id = r.bache_id for update;
      update public."GV_Importados_Baches"
         set unidades_llegadas = greatest(0, unidades_llegadas - r.unidades::int),
             estado = case when estado = 'anulado' then estado
                           when greatest(0, unidades_llegadas - r.unidades::int) < unidades then 'en_curso' else estado end,
             actualizado = now()
       where id = r.bache_id;
      update public."GV_Imp_Recepcion"
         set anulada_en = now(), anulada_por = v_por,
             anulada_motivo = 'cambiado de pedido en Importación (ingreso a racks de operario)',
             client_id = client_id || '~x' || id
       where id = r.id;
      insert into public."Importados_Mov_Stock"(ts, cod_art, marca, tipo, delta_uni, ref, legajo, creado)
      values (now(), r.cod_art, b.marca, 'ajuste', -r.unidades, 'cambia pedido recepcion importacion #' || r.id, v_por, now());
      perform public.gv_importados_resync_calc(r.importado_id);
    end if;
  end if;
  if p_bache_id is null then
    update public."GV_Imp_Ingreso_Racks_Log"
       set resultado = 'sin_pedido', motivo = 'no corresponde a ningún pedido (lo dijo ' || v_por || ')',
           bache_id = null, recepcion_id = null, unidades = null, revisado_en = now(), revisado_por = v_por
     where mov_id = p_mov_id;
    return jsonb_build_object('ok', true, 'sin_pedido', true);
  end if;
  perform set_config('gv.ir_bache', p_bache_id::text, true);
  v_res := public.gv_imp_imputar_ingreso_racks(p_mov_id, l.legajo);
  perform set_config('gv.ir_bache', '', true);
  if not coalesce((v_res->>'ok')::boolean, false) then
    raise exception 'No se pudo descontar de ese pedido: %', coalesce(v_res->>'motivo', '?');
  end if;
  update public."GV_Imp_Ingreso_Racks_Log" set revisado_en = now(), revisado_por = v_por where mov_id = p_mov_id;
  return v_res;
end $function$;
revoke execute on function public.gv_imp_ir_asignar(bigint, bigint) from public, anon;
grant execute on function public.gv_imp_ir_asignar(bigint, bigint) to authenticated;

create or replace function public.gv_imp_ir_visto(p_mov_id bigint)
 returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp'
as $function$
begin  -- v29.11-ir-visto
  if not (public.es_supervisor_virgilio() or public.gv_es_supervisor_o_servicio()) then
    raise exception 'SUPERVISOR: sólo un supervisor puede marcarlo visto.' using errcode = '42501';
  end if;
  if exists (select 1 from public."GV_Imp_Ingreso_Racks_Log" where mov_id = p_mov_id and resultado = 'a_elegir') then
    raise exception 'Primero elegí de qué pedido es (o «no es de ningún pedido»).';
  end if;
  update public."GV_Imp_Ingreso_Racks_Log"
     set revisado_en = now(), revisado_por = coalesce(nullif(auth.jwt()->>'email', ''), current_user)
   where mov_id = p_mov_id;
  return jsonb_build_object('ok', true);
end $function$;
revoke execute on function public.gv_imp_ir_visto(bigint) from public, anon;
grant execute on function public.gv_imp_ir_visto(bigint) to authenticated;

-- El aviso: lo que recibieron los operarios, con el pedido contra el que se descontó y los pedidos posibles.
create or replace function public.gv_imp_ir_avisos(p_dias int default 30)
 returns jsonb language plpgsql stable security definer set search_path to 'public', 'pg_temp'
as $function$
begin  -- v29.11-ir-avisos
  if not (public.es_supervisor_virgilio() or public.gv_es_supervisor_o_servicio()) then
    raise exception 'SUPERVISOR: el aviso de recepciones es de supervisor.' using errcode = '42501';
  end if;
  return coalesce((
    select jsonb_agg(x order by (x->>'pendiente')::boolean desc, x->>'ts' desc)
      from (
        select jsonb_build_object(
          'mov_id', l.mov_id, 'ts', coalesce(m.ts, l.ts), 'cod', l.cod_art,
          'descripcion', (select i.descripcion from public."Importados" i
                           where public.gv_cod_stock(upper(btrim(i.cod_art))) = public.gv_cod_stock(l.cod_art) limit 1),
          'cajas', l.cajas, 'unidades', l.unidades, 'sector', l.sector, 'legajo', l.legajo,
          'operario', (select e."Empleado" from public."Empleados" e where e."Legajo"::text = l.legajo limit 1),
          'empresa', m.empresa, 'resultado', l.resultado, 'motivo', l.motivo,
          'bache_id', l.bache_id, 'pedido_ref', bb.pedido_ref, 'proveedor', bb.proveedor,
          'revisado_en', l.revisado_en, 'revisado_por', l.revisado_por,
          'pendiente', l.revisado_en is null,
          'candidatos', coalesce((
             select jsonb_agg(jsonb_build_object('bache_id', c.id, 'pedido_ref', c.pedido_ref, 'proveedor', c.proveedor,
                      'marca', c.marca, 'unidades', c.unidades, 'llegadas', c.unidades_llegadas, 'estado', c.estado,
                      'reingreso', c.fecha_reingreso, 'actual', c.id = l.bache_id)
                      order by c.fecha_reingreso nulls last, c.id)
               from public."GV_Importados_Baches" c
              where public.gv_cod_stock(upper(regexp_replace(btrim(c.cod_art), '([0-9E])L$', '\1'))) = public.gv_cod_stock(l.cod_art)
                and ((c.estado = 'en_curso' and c.unidades > c.unidades_llegadas) or c.id = l.bache_id)), '[]'::jsonb)
        ) x
          from public."GV_Imp_Ingreso_Racks_Log" l
          left join public."Movimientos_Stock" m on m.id = l.mov_id
          left join public."GV_Importados_Baches" bb on bb.id = l.bache_id
         where l.resultado in ('imputado', 'a_elegir', 'sin_pedido', 'sin_uni_x_caja', 'error')
           and (l.revisado_en is null or l.ts >= now() - make_interval(days => greatest(1, p_dias)))
      ) z), '[]'::jsonb);
end $function$;
revoke execute on function public.gv_imp_ir_avisos(int) from public, anon;
grant execute on function public.gv_imp_ir_avisos(int) to authenticated;

-- centinelas
insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
values ('gv_imp_imputar_ingreso_racks', 'funcion', 'v_ncand > 1',
        'con dos o más pedidos en viaje del mismo código el ingreso a racks NO se descuenta solo: queda a elegir en Importación', 'Luis', 'v29.11'),
       ('gv_imp_ir_asignar', 'funcion', 'gv\.ir_bache',
        'el pedido de un ingreso a racks lo elige un supervisor en Importación, no el operario', 'Luis', 'v29.11');

-- Rollback: reponer el cuerpo v28.96 de sql/gv_imp_ingreso_racks_v2896.sql y
--   drop function public.gv_imp_ir_asignar(bigint,bigint); drop function public.gv_imp_ir_visto(bigint);
--   drop function public.gv_imp_ir_avisos(int);
