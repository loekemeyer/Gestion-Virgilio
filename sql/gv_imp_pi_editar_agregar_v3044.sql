-- REGLA_CONFIRMADA_POR_USUARIO (Luis, 14/10: «1 agrega el boton»)
-- v30.44 (Luis, 14/10): ✏️ EDITAR PI — «que haya un botón que permita agregar artículos al pedido».
-- Caso: PI OL-10139 (Ownland) quedó sin el 811E.
--
-- Misma RPC, misma firma (no hay que dropear nada ni hay llamada ambigua en PostgREST): un elemento de
-- p_cambios SIN bache_id y CON importado_id + agregar=true es un renglón NUEVO de la PI.
--   · hereda de la PI: pedido_ref, proveedor, fecha_embarque y fecha_reingreso (las del primer renglón en curso)
--   · cod_art y marca salen del maestro Importados; el FOB lo pone el trigger gv_importados_bache_fob
--   · frena si el artículo ya tiene renglón en curso en esa PI (se corrige la cantidad, no se duplica)
--   · queda en GV_Imp_PI_Edicion como campo 'unidades', antes 0 → después N, con el bache nuevo
--   · simular no escribe nada (igual que el resto)
-- Se aplicó sobre pg_get_functiondef vivo (v24.99-pi-editar). Centinelas 279/280 intactas + 1 nueva.

create or replace function public.gv_imp_pi_editar(p_pedido_ref text, p_proveedor text, p_editor text, p_cambios jsonb, p_nuevo_ref text default null::text, p_simular boolean default false)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
-- v24.99-pi-editar (marcador de idempotencia: no cambiarlo)
-- v30.44-pi-agregar: un cambio sin bache_id y con importado_id + agregar = renglón nuevo de la PI
declare
  v_editor text := btrim(coalesce(p_editor, ''));
  v_canon  text;
  v_nuevo_editor boolean := false;
  v_usuario text := coalesce(nullif(auth.jwt() ->> 'email', ''), session_user::text);
  v_lote uuid := gen_random_uuid();
  v_ref_nuevo text := nullif(btrim(coalesce(p_nuevo_ref, '')), '');
  v_ref_cambia boolean;
  c jsonb; b record; im record; bp record;
  v_id bigint; v_u int; v_antes_visto int; v_imp bigint; v_new_id bigint;
  v_filas jsonb := '[]'::jsonb;
  v_imps bigint[] := '{}';
  v_agregados bigint[] := '{}';
  v_nuevos bigint[] := '{}';
  v_tot_antes bigint := 0; v_tot_desp bigint := 0; v_n int := 0;
  v_base bigint[];
  v_ts timestamptz := now();
begin
  if not (public.es_supervisor_virgilio() or public.gv_es_supervisor_o_servicio()) then
    raise exception 'Sólo un supervisor logueado puede editar una PI (iniciá sesión con Google; si ya estás, actualizá la app).' using errcode = '42501';
  end if;
  if coalesce(btrim(p_pedido_ref), '') = '' then raise exception 'Falta el número de PI.'; end if;
  if v_editor = '' then raise exception 'Decí quién corrige la PI.'; end if;
  if length(v_editor) > 60 then raise exception 'El nombre del editor es demasiado largo.'; end if;

  perform pg_advisory_xact_lock(hashtext('gv_imp_pi:' || p_pedido_ref || '§' || coalesce(p_proveedor, '')));

  select e.nombre into v_canon from public."GV_Imp_PI_Editor" e
   where lower(translate(btrim(e.nombre), 'ÁÉÍÓÚáéíóúÑñ', 'AEIOUaeiouNn'))
       = lower(translate(v_editor, 'ÁÉÍÓÚáéíóúÑñ', 'AEIOUaeiouNn'))
   limit 1;
  if v_canon is null then v_nuevo_editor := true; v_canon := v_editor; end if;

  select array_agg(x.id order by x.id) into v_base
    from public."GV_Importados_Baches" x
   where x.estado = 'en_curso'
     and coalesce(nullif(btrim(x.pedido_ref), ''), '(sin pedido)') = p_pedido_ref
     and (p_proveedor is null
          or coalesce(nullif(btrim(x.proveedor), ''), '(sin proveedor)') = p_proveedor);
  if v_base is null then raise exception 'La PI % no tiene líneas en curso.', p_pedido_ref; end if;

  select coalesce(sum(x.unidades), 0) into v_tot_antes
    from public."GV_Importados_Baches" x where x.id = any (v_base);
  v_tot_desp := v_tot_antes;

  for c in select * from jsonb_array_elements(coalesce(p_cambios, '[]'::jsonb)) loop
    -- v30.44: renglón NUEVO (agregar un artículo a la PI)
    if nullif(c ->> 'bache_id', '') is null and coalesce((c ->> 'agregar')::boolean, false) then
      v_imp := nullif(c ->> 'importado_id', '')::bigint;
      if v_imp is null then raise exception 'Falta el artículo a agregar.'; end if;
      select id, cod_art, marca, activo into im from public."Importados" where id = v_imp;
      if not found then raise exception 'El artículo % no existe en el maestro de importados.', v_imp; end if;
      if nullif(c ->> 'unidades', '') is null then raise exception 'Falta la cantidad del %.', im.cod_art; end if;
      v_u := round((c ->> 'unidades')::numeric);
      if v_u <= 0 then raise exception 'El % se agrega con una cantidad mayor a 0.', im.cod_art; end if;
      if v_imp = any (v_agregados) or exists (select 1 from public."GV_Importados_Baches" x
                                              where x.id = any (v_base) and x.importado_id = v_imp) then
        raise exception 'El % ya está en la PI %: corregí su cantidad en vez de agregarlo.', im.cod_art, p_pedido_ref;
      end if;
      v_agregados := v_agregados || v_imp;
      select x.proveedor, x.fecha_embarque, x.fecha_reingreso into bp
        from public."GV_Importados_Baches" x where x.id = v_base[1];

      v_n := v_n + 1;
      v_tot_desp := v_tot_desp + v_u;
      v_new_id := null;
      if not p_simular then
        insert into public."GV_Importados_Baches"
          (importado_id, cod_art, proveedor, marca, unidades, fecha_reingreso, fecha_embarque,
           pedido_ref, estado, creado_por)
        values (im.id, im.cod_art, bp.proveedor, im.marca, v_u, bp.fecha_reingreso, bp.fecha_embarque,
           btrim(p_pedido_ref), 'en_curso', left(v_canon, 60))
        returning id into v_new_id;
        v_nuevos := v_nuevos || v_new_id;
        insert into public."GV_Imp_PI_Edicion" (lote, ts, editor, editor_nuevo, usuario, pedido_ref, proveedor,
          campo, bache_id, importado_id, cod_art, marca, antes_u, despues_u)
        values (v_lote, v_ts, v_canon, v_nuevo_editor, v_usuario, p_pedido_ref, bp.proveedor,
          'unidades', v_new_id, im.id, im.cod_art, im.marca, 0, v_u);
      end if;
      v_filas := v_filas || jsonb_build_object('bache_id', v_new_id, 'cod_art', im.cod_art, 'marca', im.marca,
        'antes', 0, 'despues', v_u, 'delta', v_u, 'sale', false, 'nuevo', true);
      if not (im.id = any (v_imps)) then v_imps := v_imps || im.id; end if;
      continue;
    end if;

    v_id := nullif(c ->> 'bache_id', '')::bigint;
    if v_id is null or not (v_id = any (v_base)) then
      raise exception 'La línea % no es de la PI %.', coalesce(c ->> 'bache_id', '?'), p_pedido_ref;
    end if;
    if nullif(c ->> 'unidades', '') is null then raise exception 'Falta la cantidad nueva de la línea %.', v_id; end if;
    v_u := round((c ->> 'unidades')::numeric);
    select * into b from public."GV_Importados_Baches" where id = v_id for update;
    v_antes_visto := nullif(c ->> 'antes', '')::int;
    if v_antes_visto is not null and v_antes_visto <> b.unidades then
      raise exception 'El % cambió mientras editabas (tenía %, ahora %). Volvé a abrir la PI.', b.cod_art, v_antes_visto, b.unidades;
    end if;
    if v_u = b.unidades then continue; end if;
    if v_u < 0 then raise exception 'El % no puede quedar en negativo.', b.cod_art; end if;
    if v_u < coalesce(b.unidades_llegadas, 0) then
      raise exception 'El % no puede quedar en % u: ya llegaron %.', b.cod_art, v_u, b.unidades_llegadas;
    end if;

    v_n := v_n + 1;
    v_tot_desp := v_tot_desp - b.unidades + v_u;
    v_filas := v_filas || jsonb_build_object('bache_id', b.id, 'cod_art', b.cod_art, 'marca', b.marca,
      'antes', b.unidades, 'despues', v_u, 'delta', v_u - b.unidades, 'sale', v_u = 0);
    if not (b.importado_id = any (v_imps)) then v_imps := v_imps || b.importado_id; end if;

    if not p_simular then
      if v_u = 0 then
        update public."GV_Importados_Baches" set estado = 'anulado', actualizado = v_ts where id = b.id;
      else
        update public."GV_Importados_Baches"
           set unidades = v_u,
               estado = case when v_u <= coalesce(unidades_llegadas, 0) then 'llegado' else 'en_curso' end,
               actualizado = v_ts
         where id = b.id;
      end if;
      insert into public."GV_Imp_PI_Edicion" (lote, ts, editor, editor_nuevo, usuario, pedido_ref, proveedor,
        campo, bache_id, importado_id, cod_art, marca, antes_u, despues_u)
      values (v_lote, v_ts, v_canon, v_nuevo_editor, v_usuario, p_pedido_ref, b.proveedor,
        'unidades', b.id, b.importado_id, b.cod_art, b.marca, b.unidades, v_u);
    end if;
  end loop;

  v_ref_cambia := v_ref_nuevo is not null and v_ref_nuevo <> p_pedido_ref;
  if v_ref_cambia and not p_simular then
    -- v30.44: también los renglones recién agregados (no están en v_base)
    update public."GV_Importados_Baches" set pedido_ref = v_ref_nuevo, actualizado = v_ts
     where id = any (v_base) or id = any (v_nuevos);
    insert into public."GV_Imp_PI_Edicion" (lote, ts, editor, editor_nuevo, usuario, pedido_ref, proveedor,
      campo, antes_ref, despues_ref)
    values (v_lote, v_ts, v_canon, v_nuevo_editor, v_usuario, p_pedido_ref, p_proveedor,
      'pedido_ref', p_pedido_ref, v_ref_nuevo);
  end if;

  if v_nuevo_editor and not p_simular and (v_n > 0 or v_ref_cambia) then
    insert into public."GV_Imp_PI_Editor" (nombre, creado_por) values (v_canon, v_usuario)
    on conflict do nothing;
  end if;

  if not p_simular then
    for v_id in select unnest(v_imps) loop
      perform public.gv_importados_resync(v_id);
    end loop;
  end if;

  return jsonb_build_object(
    'simulado', p_simular, 'lote', case when p_simular then null else v_lote end, 'ts', v_ts,
    'editor', v_canon, 'editor_nuevo', v_nuevo_editor, 'usuario', v_usuario,
    'pedido_ref', p_pedido_ref, 'ref_nuevo', case when v_ref_cambia then v_ref_nuevo else null end,
    'cambios', v_n, 'filas', v_filas, 'total_antes', v_tot_antes, 'total_despues', v_tot_desp);
end $function$;

insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
select 'gv_imp_pi_editar', 'funcion', 'v_imp = any \(v_agregados\) or exists',
       'Editar PI permite AGREGAR artículos a la PI (renglón nuevo, sin duplicar uno que ya está)', 'Luis', 'v30.44'
where not exists (select 1 from public."GV_Reglas_Centinela" where objeto = 'gv_imp_pi_editar' and patron like 'v_imp = any%');
