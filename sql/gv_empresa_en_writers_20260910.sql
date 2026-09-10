-- v14.62 (2026-09-10) — Que los 6 writers de Movimientos_Stock PASEN la columna `empresa`
-- explícita, en vez de dejar que el trigger la adivine (para duales sin sufijo ni NP caía en
-- 'Mixto' → stock al código base oculto, ni LK ni CH). Regla del dueño: la columna empresa se
-- agregó para ser la fuente explícita. El trigger trg_normalizar_empresa_stock RESPETA la
-- empresa cuando llega != NULL/Mixto, así que setearla explícita manda.
--
-- Fuente de la empresa por función:
--   racks_plani_ingreso / _nacional -> p_emp (ya lo reciben; lo escriben a Racks_Planimetria.emp)
--   registrar_baja_racks           -> item.emp, fallback Racks_Planimetria.emp del sector
--   aceptar_conteo                 -> Capacidad_Sector.empresa del sector contado (góndola)
--   anular_modo_op                 -> Control_Modo_OP.linea (la línea de la recepción original)
--   faltante_resolver              -> empresa del separado/picking de esa tanda+cod (inequívoco)
-- En todos: si no se puede determinar, queda NULL y el trigger decide (comportamiento previo).
--
-- Objetos COMPARTIDOS (los usa/usaba Producción). Backup = sección ROLLBACK al final.
-- ============================================================================================

-- 1) racks_plani_ingreso — agrega empresa=v_emp al movimiento de ingreso a racks
CREATE OR REPLACE FUNCTION public.racks_plani_ingreso(p_sector text, p_cod text, p_master numeric, p_inner numeric, p_emp text, p_legajo text)
 RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare
  v_sec   text := upper(btrim(coalesce(p_sector,'')));
  v_cod   text := upper(btrim(coalesce(p_cod,'')));
  v_inner numeric := coalesce(p_inner, 0);
  v_master numeric := coalesce(p_master, 0);
  v_emp   text := coalesce(nullif(btrim(coalesce(p_emp,'')),''), 'LK');
  r record;
begin
  if v_sec = '' or v_cod = '' then return 'error: falta sector o codigo'; end if;
  if v_inner <= 0 then return 'error: las cajas deben ser mayor a 0'; end if;

  select * into r from "Racks_Planimetria" where upper(btrim(sector)) = v_sec limit 1;
  if not found then
    insert into "Racks_Planimetria"(sector, cod_art, master_cajas, innercajas, estado, emp)
    values (v_sec, v_cod, v_master, v_inner, 'ocupado', v_emp);
  elsif r.estado is distinct from 'ocupado' or r.cod_art is null or btrim(coalesce(r.cod_art,'')) = '' then
    update "Racks_Planimetria"
       set cod_art=v_cod, master_cajas=v_master, innercajas=v_inner, estado='ocupado', emp=v_emp
     where id = r.id;
  elsif upper(btrim(r.cod_art)) = v_cod then
    update "Racks_Planimetria"
       set master_cajas = coalesce(master_cajas,0) + v_master,
           innercajas   = coalesce(innercajas,0) + v_inner
     where id = r.id;
  else
    return 'ocupado:' || r.cod_art;
  end if;

  insert into "Movimientos_Stock"(cod_art, deposito, delta, tipo, ref, unidad, legajo, empresa)
  values (v_cod, 'racks', v_inner, 'ingreso',
          'ingreso a racks '||v_sec||' ('||coalesce(v_master,0)||' master)', 'inner', nullif(p_legajo,''), v_emp);

  return 'ok';
end $function$;

-- 2) racks_plani_ingreso_nacional — agrega empresa=v_emp a los dos movimientos (origen y racks)
CREATE OR REPLACE FUNCTION public.racks_plani_ingreso_nacional(p_sector text, p_cod text, p_master numeric, p_inner numeric, p_origen text, p_emp text, p_legajo text)
 RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare
  v_sec    text := upper(btrim(coalesce(p_sector,'')));
  v_cod    text := upper(btrim(coalesce(p_cod,'')));
  v_codn   text := upper(regexp_replace(btrim(coalesce(p_cod,'')), '^0+(.)', '\1'));
  v_inner  numeric := coalesce(p_inner, 0);
  v_master numeric := coalesce(p_master, 0);
  v_orig   text := lower(btrim(coalesce(p_origen,'')));
  v_emp    text := coalesce(nullif(btrim(coalesce(p_emp,'')),''), 'LK');
  v_cutoff timestamptz;
  v_disp   numeric;
  r record;
begin
  if v_sec = '' or v_cod = '' then return 'error: falta sector o codigo'; end if;
  if v_inner <= 0 then return 'error: las cajas deben ser mayor a 0'; end if;
  if v_orig not in ('a_guardar','excedente') then return 'error: origen invalido'; end if;

  select valor::timestamptz into v_cutoff from "Stock_Config" where clave='cutoff_ts' limit 1;
  select coalesce(sum(m.delta),0) into v_disp
    from "Movimientos_Stock" m
   where m.deposito = v_orig
     and upper(regexp_replace(btrim(m.cod_art), '^0+(.)', '\1')) = v_codn
     and (v_cutoff is null or m.tipo='inicial' or m.ts >= v_cutoff);
  if v_disp < v_inner then return 'sin_stock:'||round(coalesce(v_disp,0)); end if;

  select * into r from "Racks_Planimetria" where upper(btrim(sector)) = v_sec limit 1;
  if not found then
    insert into "Racks_Planimetria"(sector, cod_art, master_cajas, innercajas, estado, emp)
    values (v_sec, v_cod, v_master, v_inner, 'ocupado', v_emp);
  elsif r.estado is distinct from 'ocupado' or r.cod_art is null or btrim(coalesce(r.cod_art,'')) = '' then
    update "Racks_Planimetria"
       set cod_art=v_cod, master_cajas=v_master, innercajas=v_inner, estado='ocupado', emp=v_emp
     where id = r.id;
  elsif upper(btrim(r.cod_art)) = v_cod then
    update "Racks_Planimetria"
       set master_cajas = coalesce(master_cajas,0) + v_master,
           innercajas   = coalesce(innercajas,0) + v_inner
     where id = r.id;
  else
    return 'ocupado:' || r.cod_art;
  end if;

  insert into "Movimientos_Stock"(cod_art, deposito, delta, tipo, ref, unidad, legajo, empresa) values
    (v_cod, v_orig,  -v_inner, 'traslado', 'nacional a racks '||v_sec, 'inner', nullif(p_legajo,''), v_emp),
    (v_cod, 'racks',  v_inner, 'traslado', 'nacional desde '||v_orig||' a '||v_sec, 'inner', nullif(p_legajo,''), v_emp);

  return 'ok';
end $function$;

-- 3) registrar_baja_racks — empresa del item, fallback Racks_Planimetria.emp del sector
CREATE OR REPLACE FUNCTION public.registrar_baja_racks(p_items jsonb)
 RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare
  it jsonb; v_cid text; v_cod text; v_caj numeric; v_desc text; v_sec text; v_ref text; v_leg text; v_ord bigint; v_emp text;
  n int := 0;
begin
  if p_items is null then return 0; end if;
  for it in select value from jsonb_array_elements(p_items) as t(value)
  loop
    v_cod := nullif(btrim(it->>'cod_art'), '');
    v_caj := coalesce((it->>'cajas')::numeric, 0);
    if v_cod is null or v_caj <= 0 then continue; end if;

    v_cid  := nullif(it->>'cid','');
    if v_cid is null then v_cid := 'br_' || replace(gen_random_uuid()::text,'-',''); end if;
    v_desc := it->>'descripcion';
    v_sec  := nullif(it->>'sector','');
    v_ref  := coalesce(nullif(it->>'ref',''), 'rack ' || coalesce(v_sec,'s/sector'));
    v_leg  := coalesce(nullif(it->>'legajo',''), '0');
    v_ord  := nullif(it->>'orden_id','')::bigint;

    -- v14.62: empresa explícita (para que bajar un rack CH caiga en la góndola CH, no en Mixto)
    v_emp := nullif(btrim(it->>'emp'),'');
    if v_emp is null and v_sec is not null then
      select emp into v_emp from "Racks_Planimetria" where upper(btrim(sector)) = upper(btrim(v_sec)) limit 1;
    end if;

    insert into public."Racks_Bajadas"
      (orden_id, cod_art, descripcion, cajas, estado, aprobada_at, creada_por, sector, client_id)
    values
      (v_ord, v_cod, v_desc, v_caj, 'aprobada', now(), v_leg, v_sec, v_cid)
    on conflict do nothing;

    insert into public."Movimientos_Stock"
      (cod_art, descripcion, deposito, delta, tipo, ref, legajo, client_id, empresa)
    values
      (v_cod, v_desc, 'racks', -v_caj, 'baja_racks', v_ref, v_leg, v_cid || '-r', v_emp)
    on conflict do nothing;

    insert into public."Movimientos_Stock"
      (cod_art, descripcion, deposito, delta, tipo, ref, legajo, client_id, empresa)
    values
      (v_cod, v_desc, 'terminado', v_caj, 'baja_racks', v_ref, v_leg, v_cid || '-t', v_emp)
    on conflict do nothing;

    n := n + 1;
  end loop;
  return n;
end;
$function$;

-- 4) aceptar_conteo — empresa del SECTOR contado (Capacidad_Sector.empresa)
CREATE OR REPLACE FUNCTION public.aceptar_conteo(p_conteo_id bigint, p_admin_legajo text)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_conteo RECORD; v_cod_norm text; v_contado numeric; v_stock_al_conteo numeric;
  v_dif_original numeric; v_emp text;
BEGIN
  SELECT * INTO v_conteo FROM "Conteo_Stock" WHERE id = p_conteo_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'error', 'Conteo no encontrado'); END IF;
  IF v_conteo.estado <> 'pendiente' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Conteo ya procesado (' || v_conteo.estado || ')');
  END IF;

  v_cod_norm := UPPER(TRIM(v_conteo.cod));
  v_contado := COALESCE(CASE WHEN v_conteo.deposito = 'insumos' THEN v_conteo.cantidad ELSE v_conteo.cajas END, 0);

  IF v_conteo.stock_sistema IS NOT NULL THEN
    v_stock_al_conteo := v_conteo.stock_sistema;
  ELSE
    IF v_conteo.deposito = 'insumos' THEN
      SELECT COALESCE(SUM(delta) FILTER (WHERE unidad = v_conteo.unidad), 0)
      INTO v_stock_al_conteo FROM "Movimientos_Stock"
      WHERE cod_art = v_cod_norm AND deposito = 'insumos';
    ELSE
      SELECT COALESCE(COALESCE(terminado,0) + COALESCE(excedente,0), 0)
      INTO v_stock_al_conteo FROM vista_saldos_stock WHERE cod_art = v_cod_norm;
    END IF;
    v_stock_al_conteo := COALESCE(v_stock_al_conteo, 0);
  END IF;

  v_dif_original := v_contado - v_stock_al_conteo;

  IF v_dif_original = 0 THEN
    UPDATE "Conteo_Stock" SET estado = 'aceptado', procesado_por = p_admin_legajo, procesado_en = now()
    WHERE id = p_conteo_id;
    RETURN jsonb_build_object('ok', true, 'mensaje', 'Conteo aceptado (stock coincide, sin ajuste)',
      'delta', 0, 'contado', v_contado, 'stock_al_conteo', v_stock_al_conteo);
  END IF;

  -- v14.62: empresa del sector contado (góndola). Sin sector o insumo → NULL (trigger decide).
  IF v_conteo.deposito <> 'insumos' AND nullif(btrim(v_conteo.sector),'') IS NOT NULL THEN
    SELECT empresa INTO v_emp FROM "Capacidad_Sector"
     WHERE upper(btrim(sector)) = upper(btrim(v_conteo.sector)) LIMIT 1;
  END IF;

  INSERT INTO "Movimientos_Stock" (cod_art, deposito, delta, tipo, ref, legajo, unidad, empresa)
  VALUES (
    v_cod_norm, v_conteo.deposito, v_dif_original, 'ajuste',
    'conteo #' || p_conteo_id || ' | contado ' || v_contado || ' vs sistema ' || v_stock_al_conteo || ' (dif ' || (CASE WHEN v_dif_original > 0 THEN '+' ELSE '' END) || v_dif_original || ')',
    p_admin_legajo,
    CASE WHEN v_conteo.deposito = 'insumos' THEN v_conteo.unidad ELSE NULL END,
    v_emp
  );

  UPDATE "Conteo_Stock" SET estado = 'aceptado', procesado_por = p_admin_legajo, procesado_en = now()
  WHERE id = p_conteo_id;

  RETURN jsonb_build_object('ok', true, 'mensaje', 'Conteo aceptado, stock ajustado',
    'delta', v_dif_original, 'contado', v_contado, 'stock_al_conteo', v_stock_al_conteo);
END;
$function$;

-- 5) anular_modo_op — empresa = Control_Modo_OP.linea (la línea de la recepción original)
CREATE OR REPLACE FUNCTION public.anular_modo_op(p_id bigint)
 RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare r record;
begin
  select * into r from "Control_Modo_OP" where id = p_id;
  if not found then return 'no_existe'; end if;
  if r.estado = 'anulado' then return 'ya_anulado'; end if;
  if r.created_at < now() - interval '48 hours' then return 'vencido'; end if;

  if r.tipo = 'prov_at' then
    delete from "Entregas Prov AT" where "Remito" = r.remito and "Proveedor" = r.nombre;
  else
    delete from "Entregas Tallerista Virgilio" where "Remito" = r.remito and "Codigo_Tall" = r.codigo_tall;
  end if;

  if coalesce(btrim(r.detalle), '') <> '' then
    insert into "Movimientos_Stock"(cod_art, deposito, delta, tipo, ref, legajo, descripcion, client_id, empresa)
    select cod, 'a_guardar', -cajas, 'ajuste',
           coalesce(nullif(btrim(r.remito), ''), 's/remito') || '|ANULA',
           'anula_recep', 'Recepción anulada (Modo OP #' || p_id || ')',
           'anrec_' || p_id || '_' || cod,
           nullif(btrim(r.linea), '')                     -- v14.62: empresa de la recepción original
      from (
        select btrim(split_part(p, '→', 1)) as cod,
               nullif(btrim(split_part(p, '→', 2)), '')::numeric as cajas
          from unnest(string_to_array(r.detalle, '·')) p
      ) x
     where x.cod <> '' and x.cajas is not null and x.cajas > 0
    on conflict (client_id) where (client_id is not null) do nothing;
  end if;

  update "Control_Modo_OP" set estado = 'anulado', procesado_at = now() where id = p_id;
  return 'ok';
end;
$function$;

-- 6) faltante_resolver — empresa del separado/picking de esa tanda+cod (si es inequívoco)
CREATE OR REPLACE FUNCTION public.faltante_resolver(p_tanda text, p_cod text, p_accion text, p_legajo text DEFAULT NULL::text, p_motivo text DEFAULT NULL::text)
 RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare
  v_tanda text := upper(trim(p_tanda));
  v_cod   text := upper(trim(p_cod));
  v_cajas numeric;
  v_emp   text;
begin
  if p_accion not in ('descontar', 'ok') then return 'error:accion_invalida'; end if;

  select cajas into v_cajas
  from public.vista_faltantes_sin_completar
  where tanda = v_tanda and cod = v_cod;

  if v_cajas is null then return 'ya_resuelto'; end if;

  if p_accion = 'descontar' then
    -- v14.62: empresa de la góndola que drenó esa tanda+cod (una sola empresa → inequívoco)
    select case when count(distinct m.empresa)=1 then max(m.empresa) end
      into v_emp
      from "Movimientos_Stock" m
     where upper(btrim(split_part(coalesce(m.ref,''),'|',1))) = v_tanda
       and regexp_replace(upper(btrim(m.cod_art)),'^0+(?=.)','') = regexp_replace(v_cod,'^0+(?=.)','')
       and m.empresa in ('LK','CH');

    begin
      insert into public."Movimientos_Stock"
        (ts, cod_art, descripcion, deposito, delta, tipo, ref, legajo, client_id, empresa)
      values (now(), v_cod,
              'Faltante facturado sin completar: salió y se facturó. ' || coalesce(nullif(trim(p_motivo), ''), ''),
              'terminado', -v_cajas, 'ajuste',
              v_tanda || '|FALTANTE_RESUELTO',
              coalesce(nullif(trim(p_legajo), ''), 'reconcilia'),
              'faltres_' || lower(v_tanda) || '_' || lower(v_cod),
              v_emp);
    exception when unique_violation then null;
    end;
  end if;

  insert into public."Faltantes_Revisados" (tanda, cod, accion, motivo, cajas, legajo)
  values (v_tanda, v_cod, p_accion, nullif(trim(p_motivo), ''), v_cajas, nullif(trim(p_legajo), ''))
  on conflict (tanda, cod) do nothing;

  return 'ok';
end;
$function$;
