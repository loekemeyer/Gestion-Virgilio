-- v23.45 (Luis, 28/09): RECIBIR una importación desde el panel de Pedidos Importación.
-- "Cuando se recibe le pregunta cuánto se recibió, de qué empresa es el código (duales) y si lo
--  quiere enviar a A guardar o a algún otro lugar (guiado con los lugares que tenemos). Si entra
--  en conflicto con el espacio de rack/góndola tiene que avisar y preguntar cómo se resuelve.
--  Tiene que dejar anotados los datos en el backend + historial de recepción de importaciones."
--
-- Qué escribe una recepción:
--   · Movimientos_Stock, una fila por destino (el stock de verdad):
--       a_guardar / excedente         → tipo 'recepcion_imp' (cajas)
--       góndola  → deposito terminado → tipo 'recepcion_imp', ubicacion = celda
--       rack     → deposito racks     → tipo 'ingreso', ubicacion = posición (+ GV_Rack_CxM)
--       insumos  → deposito insumos   → tipo 'recepcion_insumo', unidad 'Uni', ubicacion = posición
--     ('recepcion_imp' y no 'recepcion': esa dispara el aviso de "recepción rara" pensado para
--      talleristas, y un contenedor siempre es "raro" contra la mediana de un tallerista.)
--   · GV_Importados_Baches: unidades_llegadas += lo recibido (llegado si completa) + resync.
--   · Importados_Mov_Stock: el log de siempre de "llegó" (nadie lo suma al stock).
--   · GV_Imp_Recepcion + GV_Imp_Recepcion_Destino: el historial (cuándo, qué, cómo, dónde).
--
-- Conflictos (se chequean con p_simular = true antes de grabar, y se vuelven a chequear al grabar):
--   · góndola: saldo de góndola + lo que entra > capacidad de sus celdas (GV_Lugar_Item.cajas_max)
--   · rack: gv_rack_pos_chequear (posición reservada / ocupada por otro código)
--   Cada destino con conflicto necesita una resolución explícita ('forzar'); si no, no graba nada.
--
-- Rollback: drop function gv_imp_recibir(bigint,text,numeric,jsonb,text,boolean);
--           drop function gv_imp_recibir_contexto(bigint); drop function gv_imp_recepcion_historial(int);
--           (las tablas GV_Imp_Recepcion* se conservan: son auditoría).

create table if not exists public."GV_Imp_Recepcion" (
  id bigserial primary key,
  ts timestamptz not null default now(),
  bache_id bigint, importado_id bigint,
  cod_art text not null, empresa text, proveedor text, pedido_ref text,
  unidades numeric not null, uni_x_caja numeric, cajas numeric,
  pendiente_antes numeric, estado_bache text,
  por text, legajo text, nota text
);
create table if not exists public."GV_Imp_Recepcion_Destino" (
  id bigserial primary key,
  recepcion_id bigint not null references public."GV_Imp_Recepcion"(id),
  destino text not null,            -- a_guardar | excedente | gondola | rack | insumos
  sector text, cod_stock text,
  cantidad numeric not null, unidad text not null,   -- 'cajas' o 'Uni'
  deposito text not null,
  conflicto text, resolucion text
);
alter table public."GV_Imp_Recepcion" enable row level security;
alter table public."GV_Imp_Recepcion_Destino" enable row level security;
revoke all on public."GV_Imp_Recepcion", public."GV_Imp_Recepcion_Destino" from anon, authenticated;

-- ─── contexto del modal: el bache, la conversión y los lugares posibles ───
create or replace function public.gv_imp_recibir_contexto(p_bache_id bigint)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare b record; im record; v_cod text; v_dual boolean; v_emp text; v_uxc numeric; v_um numeric;
        v_gond jsonb; v_racks jsonb; v_ins jsonb; v_ins_cods jsonb; v_saldo numeric; v_cap numeric;
begin
  if not (public.es_supervisor_virgilio() or public.gv_es_supervisor_o_servicio()) then
    raise exception 'Sólo un supervisor puede recibir importaciones.' using errcode = '42501';
  end if;
  select * into b from public."GV_Importados_Baches" where id = p_bache_id;
  if not found then raise exception 'Bache % no existe', p_bache_id; end if;
  select * into im from public."Importados" where id = b.importado_id;
  v_cod := upper(regexp_replace(btrim(b.cod_art), '([0-9E])L$', '\1'));
  v_dual := exists (select 1 from public.codigos_duales d where d.cod = public.gv_cod_stock(v_cod));
  v_emp := case when upper(coalesce(b.marca, im.marca, '')) in ('CH','CHEF') then 'CH'
                when upper(coalesce(b.marca, im.marca, '')) in ('LK','LOKE') or b.cod_art ~* '[0-9E]L$' then 'LK'
                else coalesce(public.gv_empresa_de_articulo(v_cod), 'LK') end;
  v_uxc := nullif(im.uni_x_caja, 0);
  select nullif(uni_master, 0) into v_um from public."Importados_Volumen" where cod = b.cod_art limit 1;

  -- góndola: las celdas del código en el Mapa, por empresa, con capacidad y saldo
  select coalesce(jsonb_agg(jsonb_build_object('sector', la.sector, 'empresa', la.empresa,
           'cajas_max', la.cajas_max) order by la.orden), '[]')
    into v_gond from public.gv_lugar_articulo la
   where la.tipo = 'gondola' and public.gv_cod_stock(la.cod) = public.gv_cod_stock(v_cod);

  -- racks de artículos (no insumos): libre / con este código / ocupado por otro / reservado
  select coalesce(jsonb_agg(jsonb_build_object('sector', l.sector, 'empresa', l.empresa, 'uso', l.uso,
           'estado', case when l.uso in ('pedidos','cajas') then 'reservado'
                          when rp.cod is null then 'libre'
                          when public.gv_cod_stock(rp.cod) = public.gv_cod_stock(v_cod) then 'mismo'
                          else 'ocupado' end,
           'cod', rp.cod, 'cajas', rp.cajas) order by l.orden), '[]')
    into v_racks
    from public."GV_Lugar" l
    left join lateral (select string_agg(distinct r.cod_art, ', ') cod, sum(r.innercajas) cajas
                         from public."Racks_Planimetria" r
                        where r.sector = l.sector and r.estado = 'ocupado' and r.fuente is not null) rp on true
   where l.tipo = 'rack' and l.activo and l.empresa in ('LK','CH');

  -- insumos: códigos de insumo que corresponden al importado y las posiciones IN
  select coalesce(jsonb_agg(distinct x), '[]') into v_ins_cods from (
    select m.insumo_cod x from public."GV_Importados_Insumo_Map" m where upper(m.importado_cod) = upper(b.cod_art)
    union select vi.cod from public.vista_insumos vi where upper(vi.cod) = upper(b.cod_art)) z;
  select coalesce(jsonb_agg(jsonb_build_object('sector', l.sector,
           'insumos', (select string_agg(distinct u.cod, ', ') from public.gv_insumo_ubicacion u where u.sector = l.sector)) order by l.orden), '[]')
    into v_ins from public."GV_Lugar" l where l.tipo = 'rack' and l.activo and l.empresa = 'IN';

  return jsonb_build_object(
    'bache_id', b.id, 'cod_art', b.cod_art, 'cod_stock', v_cod, 'descripcion', im.descripcion,
    'proveedor', b.proveedor, 'pedido_ref', b.pedido_ref, 'marca', coalesce(b.marca, im.marca),
    'unidades', b.unidades, 'llegadas', b.unidades_llegadas,
    'pendiente', greatest(0, b.unidades - b.unidades_llegadas), 'estado', b.estado,
    'dual', v_dual, 'empresa', v_emp, 'uni_x_caja', v_uxc, 'uni_master', v_um,
    'gondola', v_gond, 'racks', v_racks, 'insumos_pos', v_ins, 'insumos_cods', v_ins_cods,
    'saldo_gondola', jsonb_build_object(
       'LK', (select coalesce(sum(delta),0) from public."Movimientos_Stock" m
               where m.deposito = 'terminado' and public.gv_cod_stock(m.cod_art) = public.gv_cod_stock(v_cod) and coalesce(m.empresa,'LK') = 'LK'),
       'CH', (select coalesce(sum(delta),0) from public."Movimientos_Stock" m
               where m.deposito = 'terminado' and public.gv_cod_stock(m.cod_art) = public.gv_cod_stock(v_cod) and m.empresa = 'CH')));
end $$;

-- ─── recibir (o simular) ───
-- p_destinos: [{destino, sector, cantidad, cod_insumo, resolucion}]
--   cantidad en CAJAS para a_guardar/excedente/gondola/rack y en UNIDADES para insumos.
create or replace function public.gv_imp_recibir(p_bache_id bigint, p_empresa text, p_uni_x_caja numeric,
  p_destinos jsonb, p_nota text default null, p_simular boolean default true)
returns jsonb language plpgsql security definer set search_path = public as $$
declare b record; im record; d jsonb; v_cod text; v_emp text; v_dual boolean; v_uxc numeric;
        v_dest text; v_sec text; v_cant numeric; v_conf text; v_res text; v_ins text;
        v_cap numeric; v_saldo numeric; v_gond_pend numeric := 0;
        v_cajas numeric := 0; v_uni numeric := 0; v_conflictos jsonb := '[]'; v_lineas jsonb := '[]';
        v_rec_id bigint; v_por text; v_pend numeric; v_estado text; v_ref text; v_dep text;
begin
  if not (public.es_supervisor_virgilio() or public.gv_es_supervisor_o_servicio()) then
    raise exception 'Sólo un supervisor puede recibir importaciones.' using errcode = '42501';
  end if;
  select * into b from public."GV_Importados_Baches" where id = p_bache_id for update;
  if not found then raise exception 'Bache % no existe', p_bache_id; end if;
  if b.estado <> 'en_curso' then raise exception 'Ese pedido ya no está en curso (%).', b.estado; end if;
  select * into im from public."Importados" where id = b.importado_id;
  v_cod := upper(regexp_replace(btrim(b.cod_art), '([0-9E])L$', '\1'));
  v_dual := exists (select 1 from public.codigos_duales x where x.cod = public.gv_cod_stock(v_cod));
  v_emp := upper(btrim(coalesce(p_empresa, '')));
  if v_dual and v_emp not in ('LK','CH') then raise exception 'Código dual: elegí la empresa (LK o CH).'; end if;
  if not v_dual then v_emp := coalesce(public.gv_empresa_de_articulo(v_cod), nullif(v_emp,''), 'LK'); end if;
  v_uxc := coalesce(nullif(p_uni_x_caja, 0), nullif(im.uni_x_caja, 0));
  if jsonb_typeof(p_destinos) <> 'array' or jsonb_array_length(p_destinos) = 0 then
    raise exception 'Falta indicar a dónde va la mercadería.';
  end if;

  for d in select * from jsonb_array_elements(p_destinos) loop
    v_dest := lower(btrim(coalesce(d->>'destino', '')));
    v_cant := coalesce((d->>'cantidad')::numeric, 0);
    v_res := nullif(lower(btrim(coalesce(d->>'resolucion', ''))), '');
    v_sec := null; v_conf := null; v_ins := null;
    if v_cant <= 0 then raise exception 'La cantidad de cada destino tiene que ser mayor a 0.'; end if;
    if v_dest not in ('a_guardar','excedente','gondola','rack','insumos') then
      raise exception 'Destino inválido: %', v_dest;
    end if;
    if v_dest = 'insumos' then
      v_uni := v_uni + v_cant;
      v_ins := upper(btrim(coalesce(d->>'cod_insumo', v_cod)));
      select l.sector into v_sec from public."GV_Lugar" l
       where l.tipo = 'rack' and l.activo and l.empresa = 'IN' and l.sector = public.gv_rack_sector(d->>'sector');
      if v_sec is null then raise exception 'La posición de insumos % no existe en el Mapa.', coalesce(d->>'sector','(vacía)'); end if;
    else
      if v_cant <> round(v_cant) then raise exception 'Las cajas van enteras (%).', v_cant; end if;
      v_cajas := v_cajas + v_cant;
      if v_dest = 'gondola' then
        select la.sector into v_sec from public.gv_lugar_articulo la
         where la.tipo = 'gondola' and la.sector = upper(btrim(coalesce(d->>'sector','')))
           and public.gv_cod_stock(la.cod) = public.gv_cod_stock(v_cod) limit 1;
        if v_sec is null then raise exception 'La celda % no es de este código en el Mapa.', coalesce(d->>'sector','(vacía)'); end if;
        select coalesce(sum(la.cajas_max), 0) into v_cap from public.gv_lugar_articulo la
         where la.tipo = 'gondola' and public.gv_cod_stock(la.cod) = public.gv_cod_stock(v_cod)
           and (not v_dual or la.empresa = v_emp);
        select coalesce(sum(m.delta), 0) into v_saldo from public."Movimientos_Stock" m
         where m.deposito = 'terminado' and public.gv_cod_stock(m.cod_art) = public.gv_cod_stock(v_cod)
           and (not v_dual or m.empresa = v_emp);
        v_gond_pend := v_gond_pend + v_cant;
        if v_cap > 0 and v_saldo + v_gond_pend > v_cap then
          v_conf := 'gondola_llena: capacidad ' || v_cap || ' cajas, hay ' || v_saldo
                 || ', entran ' || greatest(0, v_cap - v_saldo - (v_gond_pend - v_cant)) || ' de ' || v_cant;
        elsif v_cap = 0 then
          v_conf := 'gondola_sin_capacidad: la celda no tiene capacidad cargada en el Mapa';
        end if;
      elsif v_dest = 'rack' then
        v_sec := public.gv_rack_sector(d->>'sector');
        v_conf := public.gv_rack_pos_chequear(d->>'sector', v_cod);
        if v_conf like 'error:%' then raise exception 'Rack %: %', coalesce(d->>'sector','?'), substr(v_conf, 8); end if;
        if v_conf like 'ocupado:%' then v_conf := 'rack_ocupado: ' || v_sec || ' tiene ' || substr(v_conf, 9); end if;
        if exists (select 1 from public."GV_Lugar" l where l.sector = v_sec and l.empresa not in (v_emp)) then
          v_conf := coalesce(v_conf || ' · ', '') || 'rack_otra_empresa: ' || v_sec || ' es de '
                 || (select l.empresa from public."GV_Lugar" l where l.sector = v_sec);
        end if;
      end if;
    end if;
    if v_conf is not null and coalesce(v_res, '') <> 'forzar' then
      v_conflictos := v_conflictos || jsonb_build_object('destino', v_dest, 'sector', v_sec, 'cantidad', v_cant, 'conflicto', v_conf);
    end if;
    v_lineas := v_lineas || jsonb_build_object('destino', v_dest, 'sector', v_sec, 'cantidad', v_cant,
                 'cod_insumo', v_ins, 'conflicto', v_conf, 'resolucion', v_res);
  end loop;

  if v_cajas > 0 and v_uxc is null then
    raise exception 'Falta cuántas unidades trae cada caja de % para descontar el pedido.', v_cod;
  end if;
  v_uni := v_uni + v_cajas * coalesce(v_uxc, 0);
  v_pend := greatest(0, b.unidades - b.unidades_llegadas);

  if p_simular or jsonb_array_length(v_conflictos) > 0 then
    return jsonb_build_object('ok', jsonb_array_length(v_conflictos) = 0, 'simulado', true,
      'conflictos', v_conflictos, 'lineas', v_lineas, 'cajas', v_cajas, 'unidades', v_uni,
      'pendiente', v_pend, 'sobra', greatest(0, v_uni - v_pend), 'empresa', v_emp);
  end if;

  v_por := coalesce(nullif(auth.jwt()->>'email', ''), current_user);
  v_ref := 'IMP ' || coalesce(nullif(btrim(b.pedido_ref), ''), b.proveedor, '?') || ' · bache ' || b.id;
  v_estado := case when b.unidades_llegadas + v_uni >= b.unidades then 'llegado' else 'en_curso' end;

  insert into public."GV_Imp_Recepcion"(bache_id, importado_id, cod_art, empresa, proveedor, pedido_ref,
    unidades, uni_x_caja, cajas, pendiente_antes, estado_bache, por, nota)
  values (b.id, b.importado_id, b.cod_art, v_emp, b.proveedor, b.pedido_ref,
    v_uni, v_uxc, v_cajas, v_pend, v_estado, v_por, nullif(btrim(coalesce(p_nota, '')), ''))
  returning id into v_rec_id;

  for d in select * from jsonb_array_elements(v_lineas) loop
    v_dest := d->>'destino'; v_cant := (d->>'cantidad')::numeric; v_sec := d->>'sector';
    v_dep := case v_dest when 'gondola' then 'terminado' when 'rack' then case when v_emp = 'CH' and exists
               (select 1 from public."GV_Lugar" l where l.sector = v_sec and l.empresa = 'CH') then 'racks_ch' else 'racks' end
             else v_dest end;
    if v_dest = 'insumos' then
      insert into public."Movimientos_Stock"(cod_art, deposito, delta, tipo, ref, unidad, legajo, empresa, ubicacion)
      values (d->>'cod_insumo', 'insumos', v_cant, 'recepcion_insumo', v_ref, 'Uni', v_por, null, v_sec);
    elsif v_dest = 'rack' then
      insert into public."Movimientos_Stock"(cod_art, deposito, delta, tipo, ref, unidad, legajo, empresa, ubicacion)
      values (v_cod, v_dep, v_cant, 'ingreso', v_ref || ' → rack ' || v_sec, 'inner', v_por, v_emp, v_sec);
      perform public.gv_rack_cxm_anotar(v_cod, v_emp, v_cant, null);
      update public."GV_Rack_Revisar" set resuelto_en = now(), resuelto_por = 'recepción importación',
             nota = 'se ingresaron ' || v_cant || ' cajas de ' || v_cod
       where resuelto_en is null and public.gv_rack_sector(sector) = v_sec and upper(cod) = v_cod;
    else
      insert into public."Movimientos_Stock"(cod_art, deposito, delta, tipo, ref, unidad, legajo, empresa, ubicacion)
      values (v_cod, v_dep, v_cant, 'recepcion_imp', v_ref, 'inner', v_por, v_emp, v_sec);
    end if;
    insert into public."GV_Imp_Recepcion_Destino"(recepcion_id, destino, sector, cod_stock, cantidad, unidad, deposito, conflicto, resolucion)
    values (v_rec_id, v_dest, v_sec, coalesce(d->>'cod_insumo', v_cod), v_cant,
            case when v_dest = 'insumos' then 'Uni' else 'cajas' end, v_dep, d->>'conflicto', d->>'resolucion');
  end loop;

  insert into public."Importados_Mov_Stock"(ts, cod_art, marca, tipo, delta_uni, ref, legajo, creado)
  values (now(), b.cod_art, b.marca, 'ingreso', v_uni, 'recepcion importacion #' || v_rec_id, v_por, now());
  update public."GV_Importados_Baches"
     set unidades_llegadas = unidades_llegadas + least(v_uni, v_pend)::int, estado = v_estado, actualizado = now()
   where id = b.id;
  perform public.gv_importados_resync(b.importado_id);

  return jsonb_build_object('ok', true, 'simulado', false, 'recepcion_id', v_rec_id, 'cajas', v_cajas,
    'unidades', v_uni, 'pendiente_antes', v_pend, 'estado', v_estado, 'sobra', greatest(0, v_uni - v_pend));
end $$;

-- ─── historial ───
create or replace function public.gv_imp_recepcion_historial(p_dias int default 180)
returns table (id bigint, ts timestamptz, cod_art text, descripcion text, empresa text, proveedor text,
  pedido_ref text, unidades numeric, cajas numeric, uni_x_caja numeric, pendiente_antes numeric,
  estado_bache text, por text, nota text, destinos jsonb)
language sql stable security definer set search_path = public as $$
  select r.id, r.ts, r.cod_art, im.descripcion, r.empresa, r.proveedor, r.pedido_ref, r.unidades, r.cajas,
         r.uni_x_caja, r.pendiente_antes, r.estado_bache, r.por, r.nota,
         (select jsonb_agg(jsonb_build_object('destino', d.destino, 'sector', d.sector, 'cantidad', d.cantidad,
                  'unidad', d.unidad, 'deposito', d.deposito, 'cod', d.cod_stock,
                  'conflicto', d.conflicto, 'resolucion', d.resolucion) order by d.id)
            from public."GV_Imp_Recepcion_Destino" d where d.recepcion_id = r.id)
    from public."GV_Imp_Recepcion" r
    left join public."Importados" im on im.id = r.importado_id
   where (public.es_supervisor_virgilio() or public.gv_es_supervisor_o_servicio())
     and r.ts >= now() - make_interval(days => greatest(coalesce(p_dias, 180), 1))
   order by r.ts desc
$$;

revoke all on function public.gv_imp_recibir_contexto(bigint) from public;
revoke all on function public.gv_imp_recibir(bigint,text,numeric,jsonb,text,boolean) from public;
revoke all on function public.gv_imp_recepcion_historial(int) from public;
grant execute on function public.gv_imp_recibir_contexto(bigint) to authenticated, service_role;
grant execute on function public.gv_imp_recibir(bigint,text,numeric,jsonb,text,boolean) to authenticated, service_role;
grant execute on function public.gv_imp_recepcion_historial(int) to authenticated, service_role;
