-- v23.49 (Luis, 28/09) — RECIBIR importación, segunda vuelta. Sobre sql/gv_imp_recibir_v2345.sql.
-- "Tenés que dejar que ponga más de lo que debería haber llegado. Tiene que afectar stock real y
--  fijate que escriba bien en las tablas (sin reescribir toda la tabla). Anticipémonos a todo lo que
--  puede salir mal. Si se marca recibido, debería marcarlo como que ya se recibió y no está más
--  pedido o en viaje."
--
-- Cambios:
--  1. p_cerrar (default TRUE): al recibir, el bache pasa a 'llegado' aunque haya llegado menos → deja
--     de sumar en «En curso» y en viaje (gv_importados_resync sólo cuenta 'en_curso'). Lo que faltó
--     queda anotado en GV_Imp_Recepcion.faltante. Con p_cerrar=false (desmarcado en la pantalla)
--     sigue en viaje el resto.
--  2. Lo recibido de más: entra ENTERO al stock y unidades_llegadas guarda lo REAL (antes se topaba
--     al pendiente). GV_Imp_Recepcion.sobrante lo deja escrito.
--  3. Idempotencia: p_client_id (lo genera la pantalla al abrir el modal). Un doble click o un
--     reintento tras un corte de red devuelve la misma recepción, no graba dos veces (índice único).
--  4. Anular: gv_imp_recepcion_anular(id, motivo). Sólo la ÚLTIMA recepción viva de ese bache; mete
--     movimientos inversos (no borra nada) y frena si lo recibido ya se movió de donde se puso.
--     Devuelve el bache a como estaba (llegadas y estado).
--  5. Escrituras: sólo INSERT en Movimientos_Stock / GV_Imp_Recepcion* / Importados_Mov_Stock,
--     un UPDATE por id del bache y el resync de ESE código. Ningún UPDATE/DELETE masivo.
-- Rollback: volver a correr sql/gv_imp_recibir_v2345.sql (deja la firma de 6 args) y
--           drop function gv_imp_recepcion_anular(bigint,text).

alter table public."GV_Imp_Recepcion"
  add column if not exists client_id text,
  add column if not exists faltante numeric,
  add column if not exists sobrante numeric,
  add column if not exists cerro_bache boolean,
  add column if not exists estado_antes text,
  add column if not exists llegadas_antes numeric,
  add column if not exists anulada_en timestamptz,
  add column if not exists anulada_por text,
  add column if not exists anulada_motivo text;
create unique index if not exists gv_imp_recepcion_client_id_uq on public."GV_Imp_Recepcion"(client_id) where client_id is not null;

drop function if exists public.gv_imp_recibir(bigint,text,numeric,jsonb,text,boolean);
drop function if exists public.gv_imp_recepcion_historial(int);

create or replace function public.gv_imp_recibir(p_bache_id bigint, p_empresa text, p_uni_x_caja numeric,
  p_destinos jsonb, p_nota text default null, p_simular boolean default true,
  p_cerrar boolean default true, p_client_id text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare b record; im record; d jsonb; v_cod text; v_emp text; v_dual boolean; v_uxc numeric;
        v_dest text; v_sec text; v_cant numeric; v_conf text; v_res text; v_ins text;
        v_cap numeric; v_saldo numeric; v_gond_pend numeric := 0;
        v_cajas numeric := 0; v_uni numeric := 0; v_conflictos jsonb := '[]'; v_lineas jsonb := '[]';
        v_rec_id bigint; v_por text; v_pend numeric; v_estado text; v_ref text; v_dep text; v_prev record;
        v_cid text := nullif(btrim(coalesce(p_client_id, '')), '');
begin
  if not (public.es_supervisor_virgilio() or public.gv_es_supervisor_o_servicio()) then
    raise exception 'Sólo un supervisor puede recibir importaciones.' using errcode = '42501';
  end if;
  -- v23.49 idempotencia: el mismo client_id (doble click, reintento tras corte) devuelve lo ya grabado
  if not p_simular and v_cid is not null then
    select * into v_prev from public."GV_Imp_Recepcion" where client_id = v_cid;
    if found then
      return jsonb_build_object('ok', true, 'simulado', false, 'repetida', true, 'recepcion_id', v_prev.id,
        'cajas', v_prev.cajas, 'unidades', v_prev.unidades, 'estado', v_prev.estado_bache,
        'faltante', v_prev.faltante, 'sobra', v_prev.sobrante);
    end if;
  end if;
  select * into b from public."GV_Importados_Baches" where id = p_bache_id for update;
  if not found then raise exception 'Ese pedido (bache %) ya no existe: recargá la pantalla.', p_bache_id; end if;
  if b.estado <> 'en_curso' then raise exception 'Ese pedido ya no está en viaje (%): alguien lo recibió o lo anuló. Recargá la pantalla.', b.estado; end if;
  select * into im from public."Importados" where id = b.importado_id;
  v_cod := upper(regexp_replace(btrim(b.cod_art), '([0-9E])L$', '\1'));
  v_dual := exists (select 1 from public.codigos_duales x where x.cod = public.gv_cod_stock(v_cod));
  v_emp := upper(btrim(coalesce(p_empresa, '')));
  if v_dual and v_emp not in ('LK','CH') then raise exception 'Código dual: elegí la empresa (LK o CH).'; end if;
  if not v_dual then v_emp := coalesce(public.gv_empresa_de_articulo(v_cod), nullif(v_emp,''), 'LK'); end if;
  v_uxc := coalesce(nullif(p_uni_x_caja, 0), nullif(im.uni_x_caja, 0));
  if v_uxc is not null and (v_uxc <= 0 or v_uxc > 100000) then raise exception 'Unidades por caja fuera de rango (%).', v_uxc; end if;
  if jsonb_typeof(p_destinos) <> 'array' or jsonb_array_length(p_destinos) = 0 then
    raise exception 'Falta indicar a dónde va la mercadería.';
  end if;
  if jsonb_array_length(p_destinos) > 30 then raise exception 'Demasiados destinos (%).', jsonb_array_length(p_destinos); end if;
  for d in select * from jsonb_array_elements(p_destinos) loop
    v_dest := lower(btrim(coalesce(d->>'destino', '')));
    begin v_cant := coalesce((d->>'cantidad')::numeric, 0);
    exception when others then raise exception 'Cantidad inválida: %', d->>'cantidad'; end;
    v_res := nullif(lower(btrim(coalesce(d->>'resolucion', ''))), '');
    v_sec := null; v_conf := null; v_ins := null;
    if v_cant <= 0 then raise exception 'La cantidad de cada destino tiene que ser mayor a 0.'; end if;
    if v_cant > 1000000 then raise exception 'Cantidad fuera de rango (%): ¿error de tipeo?', v_cant; end if;
    if v_dest not in ('a_guardar','excedente','gondola','rack','insumos') then raise exception 'Destino inválido: %', v_dest; end if;
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
           and public.gv_cod_stock(la.cod) = public.gv_cod_stock(v_cod) and (not v_dual or la.empresa = v_emp) limit 1;
        if v_sec is null then raise exception 'La celda % no es de este código% en el Mapa.', coalesce(d->>'sector','(vacía)'), case when v_dual then ' (' || v_emp || ')' else '' end; end if;
        select coalesce(sum(la.cajas_max), 0) into v_cap from public.gv_lugar_articulo la
         where la.tipo = 'gondola' and public.gv_cod_stock(la.cod) = public.gv_cod_stock(v_cod) and (not v_dual or la.empresa = v_emp);
        select coalesce(sum(m.delta), 0) into v_saldo from public."Movimientos_Stock" m
         where m.deposito = 'terminado' and public.gv_cod_stock(m.cod_art) = public.gv_cod_stock(v_cod) and (not v_dual or m.empresa = v_emp);
        v_gond_pend := v_gond_pend + v_cant;
        if v_cap > 0 and v_saldo + v_gond_pend > v_cap then
          v_conf := 'gondola_llena: capacidad ' || v_cap || ' cajas, hay ' || v_saldo || ', entran ' || greatest(0, v_cap - v_saldo - (v_gond_pend - v_cant)) || ' de ' || v_cant;
        elsif v_cap = 0 then
          v_conf := 'gondola_sin_capacidad: la celda no tiene capacidad cargada en el Mapa';
        end if;
      elsif v_dest = 'rack' then
        v_sec := public.gv_rack_sector(d->>'sector');
        v_conf := public.gv_rack_pos_chequear(d->>'sector', v_cod);
        if v_conf like 'error:%' then raise exception 'Rack %: %', coalesce(d->>'sector','?'), substr(v_conf, 8); end if;
        if v_conf like 'ocupado:%' then v_conf := 'rack_ocupado: ' || v_sec || ' tiene ' || substr(v_conf, 9); end if;
        if exists (select 1 from public."GV_Lugar" l where l.sector = v_sec and l.empresa not in (v_emp)) then
          v_conf := coalesce(v_conf || ' · ', '') || 'rack_otra_empresa: ' || v_sec || ' es de ' || (select l.empresa from public."GV_Lugar" l where l.sector = v_sec);
        end if;
      end if;
    end if;
    if v_conf is not null and coalesce(v_res, '') <> 'forzar' then
      v_conflictos := v_conflictos || jsonb_build_object('destino', v_dest, 'sector', v_sec, 'cantidad', v_cant, 'conflicto', v_conf);
    end if;
    v_lineas := v_lineas || jsonb_build_object('destino', v_dest, 'sector', v_sec, 'cantidad', v_cant, 'cod_insumo', v_ins, 'conflicto', v_conf, 'resolucion', v_res);
  end loop;
  if v_cajas > 0 and v_uxc is null then raise exception 'Falta cuántas unidades trae cada caja de % para descontar el pedido.', v_cod; end if;
  v_uni := round(v_uni + v_cajas * coalesce(v_uxc, 0));
  v_pend := greatest(0, b.unidades - b.unidades_llegadas);
  v_estado := case when coalesce(p_cerrar, true) or b.unidades_llegadas + v_uni >= b.unidades then 'llegado' else 'en_curso' end;
  if p_simular or jsonb_array_length(v_conflictos) > 0 then
    return jsonb_build_object('ok', jsonb_array_length(v_conflictos) = 0, 'simulado', true, 'conflictos', v_conflictos, 'lineas', v_lineas,
      'cajas', v_cajas, 'unidades', v_uni, 'pendiente', v_pend, 'sobra', greatest(0, v_uni - v_pend),
      'faltante', case when v_estado = 'llegado' then greatest(0, v_pend - v_uni) else 0 end, 'estado', v_estado, 'empresa', v_emp);
  end if;
  v_por := coalesce(nullif(auth.jwt()->>'email', ''), current_user);
  v_ref := 'IMP ' || coalesce(nullif(btrim(b.pedido_ref), ''), b.proveedor, '?') || ' · bache ' || b.id;
  insert into public."GV_Imp_Recepcion"(bache_id, importado_id, cod_art, empresa, proveedor, pedido_ref, unidades, uni_x_caja, cajas,
    pendiente_antes, estado_bache, por, nota, client_id, faltante, sobrante, cerro_bache, estado_antes, llegadas_antes)
  values (b.id, b.importado_id, b.cod_art, v_emp, b.proveedor, b.pedido_ref, v_uni, v_uxc, v_cajas,
    v_pend, v_estado, v_por, nullif(btrim(coalesce(p_nota, '')), ''), v_cid,
    case when v_estado = 'llegado' then greatest(0, v_pend - v_uni) else 0 end, greatest(0, v_uni - v_pend),
    v_estado = 'llegado', b.estado, b.unidades_llegadas)
  returning id into v_rec_id;
  for d in select * from jsonb_array_elements(v_lineas) loop
    v_dest := d->>'destino'; v_cant := (d->>'cantidad')::numeric; v_sec := d->>'sector';
    v_dep := case v_dest when 'gondola' then 'terminado' when 'rack' then case when v_emp = 'CH' and exists
               (select 1 from public."GV_Lugar" l where l.sector = v_sec and l.empresa = 'CH') then 'racks_ch' else 'racks' end else v_dest end;
    if v_dest = 'insumos' then
      insert into public."Movimientos_Stock"(cod_art, deposito, delta, tipo, ref, unidad, legajo, empresa, ubicacion)
      values (d->>'cod_insumo', 'insumos', v_cant, 'recepcion_insumo', v_ref, 'Uni', v_por, null, v_sec);
    elsif v_dest = 'rack' then
      insert into public."Movimientos_Stock"(cod_art, deposito, delta, tipo, ref, unidad, legajo, empresa, ubicacion)
      values (v_cod, v_dep, v_cant, 'ingreso', v_ref || ' → rack ' || v_sec, 'inner', v_por, v_emp, v_sec);
      perform public.gv_rack_cxm_anotar(v_cod, v_emp, v_cant, null);
      update public."GV_Rack_Revisar" set resuelto_en = now(), resuelto_por = 'recepción importación', nota = 'se ingresaron ' || v_cant || ' cajas de ' || v_cod
       where resuelto_en is null and public.gv_rack_sector(sector) = v_sec and upper(cod) = v_cod;
    else
      insert into public."Movimientos_Stock"(cod_art, deposito, delta, tipo, ref, unidad, legajo, empresa, ubicacion)
      values (v_cod, v_dep, v_cant, 'recepcion_imp', v_ref, 'inner', v_por, v_emp, v_sec);
    end if;
    insert into public."GV_Imp_Recepcion_Destino"(recepcion_id, destino, sector, cod_stock, cantidad, unidad, deposito, conflicto, resolucion)
    values (v_rec_id, v_dest, v_sec, coalesce(d->>'cod_insumo', v_cod), v_cant, case when v_dest = 'insumos' then 'Uni' else 'cajas' end, v_dep, d->>'conflicto', d->>'resolucion');
  end loop;
  insert into public."Importados_Mov_Stock"(ts, cod_art, marca, tipo, delta_uni, ref, legajo, creado)
  values (now(), b.cod_art, b.marca, 'ingreso', v_uni, 'recepcion importacion #' || v_rec_id, v_por, now());
  -- lo REAL que llegó (puede pasar lo pedido); el estado lo decide p_cerrar
  update public."GV_Importados_Baches" set unidades_llegadas = unidades_llegadas + v_uni::int, estado = v_estado, actualizado = now() where id = b.id;
  perform public.gv_importados_resync(b.importado_id);
  return jsonb_build_object('ok', true, 'simulado', false, 'recepcion_id', v_rec_id, 'cajas', v_cajas, 'unidades', v_uni,
    'pendiente_antes', v_pend, 'estado', v_estado, 'sobra', greatest(0, v_uni - v_pend),
    'faltante', case when v_estado = 'llegado' then greatest(0, v_pend - v_uni) else 0 end);
end $$;

-- Anular: sólo la última recepción viva del bache; movimientos inversos (no borra nada).
create or replace function public.gv_imp_recepcion_anular(p_id bigint, p_motivo text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r record; d record; b record; v_saldo numeric; v_por text; v_ref text; v_tipo text; v_dual boolean;
begin
  if not (public.es_supervisor_virgilio() or public.gv_es_supervisor_o_servicio()) then
    raise exception 'Sólo un supervisor puede anular una recepción.' using errcode = '42501';
  end if;
  if length(btrim(coalesce(p_motivo, ''))) < 3 then raise exception 'Escribí por qué se anula.'; end if;
  select * into r from public."GV_Imp_Recepcion" where id = p_id for update;
  if not found then raise exception 'La recepción % no existe.', p_id; end if;
  if r.anulada_en is not null then raise exception 'Esa recepción ya estaba anulada.'; end if;
  select * into b from public."GV_Importados_Baches" where id = r.bache_id for update;
  if exists (select 1 from public."GV_Imp_Recepcion" x where x.bache_id = r.bache_id and x.anulada_en is null and x.id > r.id) then
    raise exception 'Hay una recepción posterior de ese mismo pedido: anulá primero la última.';
  end if;
  -- frenar si lo recibido ya se movió de donde se puso
  v_dual := exists (select 1 from public.codigos_duales x where x.cod = public.gv_cod_stock(regexp_replace(upper(btrim(r.cod_art)), '([0-9E])L$', '\1')));
  for d in select * from public."GV_Imp_Recepcion_Destino" where recepcion_id = p_id loop
    select coalesce(sum(m.delta), 0) into v_saldo from public."Movimientos_Stock" m
     where m.deposito = d.deposito and public.gv_cod_stock(m.cod_art) = public.gv_cod_stock(d.cod_stock)
       and (d.destino = 'insumos' or not v_dual or m.empresa = r.empresa)
       and (d.destino not in ('rack','insumos') or m.ubicacion = d.sector);
    if v_saldo < d.cantidad then
      raise exception 'No se puede anular: de las % % que entraron a % % hoy quedan %. Ya se movieron; corregí con un ajuste de stock.',
        d.cantidad, case when d.unidad = 'Uni' then 'u' else 'cajas' end, d.deposito, coalesce(d.sector, ''), v_saldo;
    end if;
  end loop;
  v_por := coalesce(nullif(auth.jwt()->>'email', ''), current_user);
  v_ref := 'ANULA IMP #' || p_id || ' · ' || btrim(p_motivo);
  for d in select * from public."GV_Imp_Recepcion_Destino" where recepcion_id = p_id loop
    v_tipo := case when d.destino = 'insumos' then 'ajuste' else 'recepcion_imp_anula' end;
    insert into public."Movimientos_Stock"(cod_art, deposito, delta, tipo, ref, unidad, legajo, empresa, ubicacion)
    values (d.cod_stock, d.deposito, -d.cantidad, v_tipo, v_ref, case when d.destino = 'insumos' then 'Uni' else 'inner' end,
            v_por, case when d.destino = 'insumos' then null else r.empresa end, d.sector);
  end loop;
  insert into public."Importados_Mov_Stock"(ts, cod_art, marca, tipo, delta_uni, ref, legajo, creado)
  values (now(), r.cod_art, b.marca, 'ajuste', -r.unidades, 'anula recepcion importacion #' || p_id, v_por, now());
  update public."GV_Importados_Baches"
     set unidades_llegadas = coalesce(r.llegadas_antes, greatest(0, unidades_llegadas - r.unidades::int))::int,
         estado = coalesce(r.estado_antes, 'en_curso'), actualizado = now()
   where id = r.bache_id;
  update public."GV_Imp_Recepcion" set anulada_en = now(), anulada_por = v_por, anulada_motivo = btrim(p_motivo) where id = p_id;
  perform public.gv_importados_resync(r.importado_id);
  return jsonb_build_object('ok', true, 'recepcion_id', p_id, 'bache_estado', coalesce(r.estado_antes, 'en_curso'));
end $$;

create or replace function public.gv_imp_recepcion_historial(p_dias int default 180)
returns table (id bigint, ts timestamptz, cod_art text, descripcion text, empresa text, proveedor text, pedido_ref text,
  unidades numeric, cajas numeric, uni_x_caja numeric, pendiente_antes numeric, estado_bache text, por text, nota text,
  faltante numeric, sobrante numeric, cerro_bache boolean, anulada_en timestamptz, anulada_por text, anulada_motivo text,
  es_ultima boolean, destinos jsonb)
language sql stable security definer set search_path = public as $$
  select r.id, r.ts, r.cod_art, im.descripcion, r.empresa, r.proveedor, r.pedido_ref, r.unidades, r.cajas, r.uni_x_caja,
         r.pendiente_antes, r.estado_bache, r.por, r.nota, r.faltante, r.sobrante, r.cerro_bache,
         r.anulada_en, r.anulada_por, r.anulada_motivo,
         r.anulada_en is null and not exists (select 1 from public."GV_Imp_Recepcion" x where x.bache_id = r.bache_id and x.anulada_en is null and x.id > r.id),
         (select jsonb_agg(jsonb_build_object('destino', d.destino, 'sector', d.sector, 'cantidad', d.cantidad, 'unidad', d.unidad, 'deposito', d.deposito, 'cod', d.cod_stock, 'conflicto', d.conflicto, 'resolucion', d.resolucion) order by d.id)
            from public."GV_Imp_Recepcion_Destino" d where d.recepcion_id = r.id)
    from public."GV_Imp_Recepcion" r left join public."Importados" im on im.id = r.importado_id
   where (public.es_supervisor_virgilio() or public.gv_es_supervisor_o_servicio())
     and r.ts >= now() - make_interval(days => greatest(coalesce(p_dias, 180), 1))
   order by r.ts desc
$$;

revoke all on function public.gv_imp_recibir(bigint,text,numeric,jsonb,text,boolean,boolean,text) from public;
revoke all on function public.gv_imp_recepcion_anular(bigint,text) from public;
revoke all on function public.gv_imp_recepcion_historial(int) from public;
grant execute on function public.gv_imp_recibir(bigint,text,numeric,jsonb,text,boolean,boolean,text) to authenticated, service_role;
grant execute on function public.gv_imp_recepcion_anular(bigint,text) to authenticated, service_role;
grant execute on function public.gv_imp_recepcion_historial(int) to authenticated, service_role;

-- Centinelas (aplicados con el sí de Luis, 28/09; ids 235-239; en la base dicen version 'v23.46', que era el número previsto):
-- insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version) values
-- ('gv_imp_recibir','funcion','''recepcion_imp''', 'tipo recepcion_imp (no dispara recepción rara)','Luis','v23.46'),
-- ('gv_imp_recibir','funcion','gv_rack_pos_chequear','conflicto de rack','Luis','v23.46'),
-- ('gv_imp_recibir','funcion','client_id = v_cid','idempotencia','Luis','v23.46'),
-- ('gv_imp_recibir','funcion','coalesce\(p_cerrar, true\)','al recibir el pedido deja de estar en viaje','Luis','v23.46'),
-- ('gv_imp_recepcion_anular','funcion','v_saldo < d\.cantidad','anular frena si ya se movió','Luis','v23.46');
