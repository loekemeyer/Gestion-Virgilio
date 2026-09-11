-- =====================================================================
-- FUNCIONES del schema GP2 — export automatico 2026-09-05 (pg_get_functiondef, exacto)
-- Fuente de verdad: Supabase (hrxfctzncixxqmpfhskv). Este archivo es respaldo/referencia.
-- 119 funciones. Los GRANT/REVOKE no estan aca: EXECUTE para anon solo en las RPC de pantalla (ver db/README.md).
-- =====================================================================

-- ---------- _aplicar_recepcion_a_oc ----------
CREATE OR REPLACE FUNCTION "GP2"._aplicar_recepcion_a_oc(p_comp_id bigint, p_cantidad numeric, p_unidad text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
declare
  it record; v_resto numeric := p_cantidad; v_aplicar numeric; v_pend numeric;
  v_kgu numeric; v_cant_item numeric; v_ocs jsonb := '[]'::jsonb;
begin
  select kg_x_uni into v_kgu from componente where id = p_comp_id;
  for it in
    select oi.id, oi.cantidad, oi.recibido, oi.unidad, o.id oc_id, o.numero, o.estado
    from orden_compra_item oi
    join orden_compra o on o.id = oi.oc_id
    where oi.componente_id = p_comp_id
      and o.estado in ('enviada','borrador')
      and oi.recibido < oi.cantidad
    order by case o.estado when 'enviada' then 0 else 1 end, o.numero, oi.id
  loop
    exit when v_resto <= 0;
    -- convertir lo recibido a la unidad del item de OC si difieren
    v_cant_item := v_resto;
    if lower(coalesce(it.unidad,'uni')) <> lower(coalesce(p_unidad,'uni')) then
      if v_kgu is null or v_kgu <= 0 then
        continue; -- sin conversion posible: no cruzar contra este item
      elsif lower(coalesce(it.unidad,'uni')) = 'kg' then
        v_cant_item := v_resto * v_kgu;      -- recibi uni, la OC pide kg
      else
        v_cant_item := v_resto / v_kgu;      -- recibi kg, la OC pide uni
      end if;
    end if;
    v_pend := it.cantidad - it.recibido;
    v_aplicar := least(v_cant_item, v_pend);
    if v_aplicar <= 0 then continue; end if;
    update orden_compra_item set recibido = recibido + v_aplicar where id = it.id;
    -- descontar del resto en la unidad de la recepcion
    if lower(coalesce(it.unidad,'uni')) <> lower(coalesce(p_unidad,'uni')) then
      if lower(coalesce(it.unidad,'uni')) = 'kg' then v_resto := v_resto - v_aplicar / v_kgu;
      else v_resto := v_resto - v_aplicar * v_kgu; end if;
    else
      v_resto := v_resto - v_aplicar;
    end if;
    v_ocs := v_ocs || jsonb_build_object('numero', it.numero, 'aplicado', round(v_aplicar,2), 'unidad', it.unidad);
    -- OC completa -> recibida
    if not exists (select 1 from orden_compra_item x where x.oc_id = it.oc_id and x.recibido < x.cantidad) then
      update orden_compra set estado = 'recibida' where id = it.oc_id and estado <> 'anulada';
      v_ocs := v_ocs || jsonb_build_object('numero', it.numero, 'completa', true);
    end if;
  end loop;
  return v_ocs;
end $function$
;

-- ---------- _es_sector_insumo ----------
CREATE OR REPLACE FUNCTION "GP2"._es_sector_insumo(p bigint)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'GP2'
AS $function$
  select coalesce((select s.es_insumo from sector s where s.id = p), false)
$function$
;

-- ---------- abm_articulo_baja ----------
CREATE OR REPLACE FUNCTION "GP2".abm_articulo_baja(p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
declare v_cod text; v_bom int;
begin
  select codigo into v_cod from articulo where id=p_id;
  if v_cod is null then raise exception 'Artículo % inexistente', p_id; end if;
  delete from articulo_componente where articulo_id=p_id; get diagnostics v_bom = row_count;
  delete from articulo where id=p_id;
  return jsonb_build_object('ok',true,'id',p_id,'codigo',v_cod,'bom_borradas',v_bom);
end $function$
;

-- ---------- abm_articulo_upsert ----------
CREATE OR REPLACE FUNCTION "GP2".abm_articulo_upsert(p_id bigint, p_codigo text, p_familia text, p_caja_id bigint, p_por_caja integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
declare v_id bigint; v_accion text;
begin
  if p_codigo is null or btrim(p_codigo)='' then raise exception 'El código es obligatorio'; end if;
  if p_caja_id is not null and not exists (select 1 from componente where id=p_caja_id)
    then raise exception 'La caja (componente %) no existe', p_caja_id; end if;
  if p_id is null then
    if exists (select 1 from articulo where lower(btrim(codigo))=lower(btrim(p_codigo)))
      then raise exception 'Ya existe un artículo con el código %', p_codigo; end if;
    select coalesce(max(id),0)+1 into v_id from articulo;
    insert into articulo(id,codigo,familia,componente_caja_id,articulos_por_caja)
    values (v_id,btrim(p_codigo),p_familia,p_caja_id,p_por_caja);
    v_accion:='alta';
  else
    if not exists (select 1 from articulo where id=p_id) then raise exception 'Artículo % inexistente', p_id; end if;
    update articulo set codigo=btrim(p_codigo), familia=p_familia, componente_caja_id=p_caja_id,
      articulos_por_caja=p_por_caja where id=p_id;
    v_id:=p_id; v_accion:='edicion';
  end if;
  return jsonb_build_object('ok',true,'id',v_id,'accion',v_accion,'codigo',btrim(p_codigo));
end $function$
;

-- ---------- abm_articulos_bundle ----------
CREATE OR REPLACE FUNCTION "GP2".abm_articulos_bundle()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
select jsonb_build_object(
  'sect', (select jsonb_object_agg(id::text, jsonb_build_object('tipo',tipo,'nom',nombre)) from "GP2".sector),
  'partes', (select coalesce(jsonb_agg(jsonb_build_object(
      'id', c.id, 'cod', c.codigo, 'd', c.descripcion, 's', c.sector_id) order by c.codigo), '[]'::jsonb)
    from "GP2".componente c where c.sector_id is distinct from 12),
  'art', (
    select coalesce(jsonb_agg(
      jsonb_build_object(
        'id',   a.id,
        'cod',  a.codigo,
        'fam',  a.familia,
        'por',  a.articulos_por_caja,
        'caja', a.componente_caja_id,
        'caja_cod',  cj.codigo,
        'caja_desc', cj.descripcion,
        -- demanda (uni/mes) = Est Madre (proyeccion_madre espejada en est_madre), solo lectura
        'est',  (select em.proy_uni_mes from "GP2".est_madre em
                 where regexp_replace(em.cod,'^0+','') = regexp_replace(a.codigo,'^0+','') limit 1),
        'comp', coalesce((
          select jsonb_agg(jsonb_build_object(
            'cid', c.id,
            'cod', c.codigo,
            'd',   c.descripcion,
            's',   c.sector_id,
            'um',  c.unidad_medida,
            'q',   ac.cantidad,
            'kg',  c.kg_x_uni,
            'uxc', c.uni_x_cajon
          ) order by c.sector_id nulls last, c.codigo)
          from "GP2".articulo_componente ac
          join "GP2".componente c on c.id = ac.componente_id
          where ac.articulo_id = a.id
        ), '[]'::jsonb)
      ) order by a.codigo
    ), '[]'::jsonb)
    from "GP2".articulo a
    left join "GP2".componente cj on cj.id = a.componente_caja_id
  )
);
$function$
;

-- ---------- abm_bom_guardar ----------
CREATE OR REPLACE FUNCTION "GP2".abm_bom_guardar(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
declare
  v_art bigint := (p->>'articulo_id')::bigint;
  v_cod text; it jsonb; v_cid bigint; v_q numeric;
  v_altas int := 0; v_cambios int := 0; v_bajas int := 0;
  v_ids bigint[] := '{}'; v_avisos jsonb := '[]'::jsonb;
begin
  select codigo into v_cod from articulo where id = v_art;
  if v_cod is null then raise exception 'Articulo inexistente (id=%).', v_art; end if;

  for it in select * from jsonb_array_elements(coalesce(p->'lineas','[]'::jsonb)) loop
    v_cid := (it->>'comp_id')::bigint;
    v_q   := (it->>'cantidad')::numeric;
    if v_cid is null then raise exception 'Linea sin comp_id.'; end if;
    if v_q is null or v_q <= 0 then
      raise exception 'Cantidad invalida para el componente id=% (debe ser > 0).', v_cid;
    end if;
    if not exists (select 1 from componente c where c.id = v_cid) then
      raise exception 'Componente inexistente (id=%).', v_cid;
    end if;
    if exists (select 1 from componente c where c.id = v_cid and c.sector_id = 12) then
      raise exception 'Un articulo terminado no puede ser parte de una receta (comp id=%).', v_cid;
    end if;
    v_ids := v_ids || v_cid;
    if exists (select 1 from articulo_componente ac where ac.articulo_id=v_art and ac.componente_id=v_cid) then
      update articulo_componente set cantidad = v_q
       where articulo_id=v_art and componente_id=v_cid and cantidad is distinct from v_q;
      if found then v_cambios := v_cambios + 1; end if;
    else
      insert into articulo_componente(articulo_id, componente_id, cantidad) values (v_art, v_cid, v_q);
      v_altas := v_altas + 1;
    end if;
  end loop;

  delete from articulo_componente ac
   where ac.articulo_id = v_art and not (ac.componente_id = any(v_ids));
  get diagnostics v_bajas = row_count;

  -- avisos de normalizacion contra las rutas del articulo
  with salidas as (
    select distinct rp.comp_salida_id
    from ruta r join ruta_paso rp on rp.ruta_id = r.id
    where r.articulo_id = v_art and rp.comp_salida_id is not null
  ), receta as (
    select ac.componente_id from articulo_componente ac where ac.articulo_id = v_art
  )
  select coalesce(jsonb_agg(x.msg), '[]'::jsonb) into v_avisos
  from (
    select 'La parte '||c.codigo||' esta en la receta pero NINGUNA ruta del articulo la produce (completar ruta/ruta_paso).' as msg
    from receta rc join componente c on c.id = rc.componente_id
    where not "GP2"._es_sector_insumo(c.sector_id)
      and rc.componente_id not in (select comp_salida_id from salidas)
    union all
    select 'La ruta produce '||c.codigo||' pero NO esta en la receta (agregarla o revisar la ruta).'
    from salidas s join componente c on c.id = s.comp_salida_id
    where c.sector_id is distinct from 12
      and s.comp_salida_id not in (select componente_id from receta)
  ) x;

  return jsonb_build_object('ok', true, 'articulo', v_cod,
    'altas', v_altas, 'cambios', v_cambios, 'bajas', v_bajas, 'avisos', v_avisos);
end $function$
;

-- ---------- actualizar_dolar_oficial ----------
CREATE OR REPLACE FUNCTION "GP2".actualizar_dolar_oficial()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'GP2', 'public', 'extensions'
AS $function$
declare r record; j jsonb; v_fecha date; v_venta numeric; v_compra numeric;
begin
  select * into r from public.http_get('https://dolarapi.com/v1/dolares/oficial');
  if r.status <> 200 then
    return jsonb_build_object('ok', false, 'status', r.status);
  end if;
  j := r.content::jsonb;
  v_fecha  := (j->>'fechaActualizacion')::timestamptz::date;
  v_venta  := (j->>'venta')::numeric;
  v_compra := (j->>'compra')::numeric;
  if v_venta is null or v_venta <= 0 then
    return jsonb_build_object('ok', false, 'motivo', 'venta invalida', 'body', j);
  end if;

  insert into tipo_cambio (fecha, compra, venta)
  values (v_fecha, v_compra, v_venta)
  on conflict (fecha) do update set compra = excluded.compra, venta = excluded.venta, obtenido_en = now();

  -- el parametro es lo que leen las vistas de valorizacion: siempre el ultimo valor
  insert into parametro (clave, valor, descripcion)
  values ('tipo_cambio_usd_pesos', v_venta, 'Dolar oficial VENTA, actualizado solo por pg_cron (fuente dolarapi.com). Historia en GP2.tipo_cambio.')
  on conflict (clave) do update set valor = excluded.valor, descripcion = excluded.descripcion;

  return jsonb_build_object('ok', true, 'fecha', v_fecha, 'venta', v_venta, 'compra', v_compra);
end $function$
;

-- ---------- ajustar_rollos ----------
CREATE OR REPLACE FUNCTION "GP2".ajustar_rollos(p_comp_id bigint, p_kg_por_rollo numeric, p_delta integer, p_motivo text DEFAULT 'ajuste'::text, p_nota text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
declare v_id bigint;
begin
  if p_motivo not in ('inicial','ajuste','devolucion') then
    raise exception 'Motivo invalido: %', p_motivo;
  end if;
  insert into rollo_evento(componente_id, kg_por_rollo, delta, motivo, nota)
  values (p_comp_id, p_kg_por_rollo, p_delta, p_motivo, p_nota) returning id into v_id;
  return jsonb_build_object('ok',true,'id',v_id);
end $function$
;

-- ---------- alertas_bundle ----------
CREATE OR REPLACE FUNCTION "GP2".alertas_bundle()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
with ref as (
  select max(fecha)::date d from "GP2".produccion where (eliminar is null or eliminar <> 'S')
),
matrices as (
  select matriz_raw m,
         (array_agg(nombre_matriz) filter (where nombre_matriz is not null and nombre_matriz <> ''))[1] nm,
         max(tiempo_historico) th
  from "GP2".produccion
  where matriz_raw is not null and matriz_raw <> ''
    and (eliminar is null or eliminar <> 'S')
  group by matriz_raw
),
sin_tiempo as (
  select m, nm, th from matrices where th is null or th = 0
),
eventos as (
  select nombre_matriz, matriz_raw, legajo, nombre_empleado, fecha,
         to_char(fecha,'YYYY-MM-DD') fstr, to_char(hora_inicio,'HH24:MI:SS') hstr
  from "GP2".produccion
  where (eliminar is null or eliminar <> 'S')
    and fecha >= (select d from ref) - interval '30 days'
)
select jsonb_build_object(
  'generado_en', now(),
  'ref_fecha', (select d from ref),
  'ventana_dias', 30,
  'matriz_sin_tiempo', jsonb_build_object(
    'total', (select count(*) from sin_tiempo),
    'items', coalesce((
      select jsonb_agg(jsonb_build_object('N_Matriz', m, 'Nombre_Matriz', nm, 'Tiempo_Historico', coalesce(th,0)) order by m)
      from sin_tiempo), '[]'::jsonb)
  ),
  'rm', jsonb_build_object(
    'total', (select count(*) from eventos where nombre_matriz ilike 'RM %'),
    'items', coalesce((
      select jsonb_agg(jsonb_build_object('Fecha',fstr,'Hora',hstr,'Legajo',legajo,'Empleado',nombre_empleado,'Matriz',matriz_raw,'Nombre_Matriz',nombre_matriz) order by fecha desc)
      from eventos where nombre_matriz ilike 'RM %'), '[]'::jsonb)
  ),
  'pm', jsonb_build_object(
    'total', (select count(*) from eventos where nombre_matriz ilike 'PM %'),
    'items', coalesce((
      select jsonb_agg(jsonb_build_object('Fecha',fstr,'Hora',hstr,'Legajo',legajo,'Empleado',nombre_empleado,'Matriz',matriz_raw,'Nombre_Matriz',nombre_matriz) order by fecha desc)
      from eventos where nombre_matriz ilike 'PM %'), '[]'::jsonb)
  ),
  'pendientes', jsonb_build_array(
    jsonb_build_object(
      'clave','stock_bajo_minimo',
      'titulo','Stock bajo minimo',
      'motivo','Desactivada a proposito: el inventario GP2 ya cierra con el ledger (verificado 2026-09-04), pero falta decidir con que regla avisa (minimo por ubicacion vs maximo, y a quien). Ver PREGUNTAS_ARQUITECTURA_GP2.md punto 24.'
    )
  )
);
$function$
;

-- ---------- alta_proveedor_insumo ----------
CREATE OR REPLACE FUNCTION "GP2".alta_proveedor_insumo(p_nombre text, p_rubro text DEFAULT NULL::text, p_modo_control text DEFAULT 'ninguno'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
declare v_n text := nullif(btrim(coalesce(p_nombre,'')),'');
begin
  if v_n is null then raise exception 'El nombre del proveedor no puede estar vacio.'; end if;
  insert into proveedor_insumo(nombre, rubro, modo_control)
  values (v_n, nullif(btrim(coalesce(p_rubro,'')),''), coalesce(nullif(btrim(p_modo_control),''),'ninguno'))
  on conflict (nombre) do update
     set activo = true,
         rubro = coalesce(excluded.rubro, proveedor_insumo.rubro);
  return jsonb_build_object('ok',true,'nombre',v_n);
end $function$
;

-- ---------- alta_proveedor_servicio ----------
CREATE OR REPLACE FUNCTION "GP2".alta_proveedor_servicio(p_nombre text, p_proceso text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
declare
  v_nom text := nullif(btrim(coalesce(p_nombre,'')),'');
  v_proc text := nullif(btrim(coalesce(p_proceso,'')),'');
  v_id bigint; v_ubic bigint;
begin
  if v_nom is null then raise exception 'Falta el nombre del proveedor.'; end if;
  if v_proc is null then raise exception 'Falta el proceso.'; end if;

  select id into v_id from proveedor_servicio where lower(btrim(nombre)) = lower(v_nom);
  if v_id is not null then
    raise exception 'Ya existe un proveedor de servicio llamado "%".', v_nom;
  end if;

  -- cod_prov queda NULL a proposito: es el codigo externo y no se inventa.
  insert into proveedor_servicio (nombre, proceso, cod_prov)
  values (v_nom, v_proc, null) returning id into v_id;

  -- cada contraparte tiene SU ubicacion de stock (sin ella, crear_envio_ps no puede mandarle nada)
  insert into ubicacion (tipo, ref_id, nombre, meses_minimo)
  values ('proveedor_servicio', v_id, 'Prov. Serv. ' || v_nom, 0) returning id into v_ubic;

  return jsonb_build_object('ok', true, 'id', v_id, 'nombre', v_nom, 'proceso', v_proc, 'ubicacion_id', v_ubic);
end $function$
;

-- ---------- anular_evento_prod ----------
CREATE OR REPLACE FUNCTION "GP2".anular_evento_prod(p_id_ejecucion text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
declare v_n int;
begin
  if nullif(btrim(coalesce(p_id_ejecucion,'')),'') is null then
    raise exception 'Falta id_ejecucion';
  end if;
  update produccion set eliminar = 'S' where id_ejecucion = p_id_ejecucion;
  get diagnostics v_n = row_count;
  return jsonb_build_object('ok', true, 'anulados', v_n);
end $function$
;

-- ---------- anular_produccion ----------
CREATE OR REPLACE FUNCTION "GP2".anular_produccion(row_id bigint, p_hora_inicio text DEFAULT NULL::text, p_hora_fin text DEFAULT NULL::text, p_seg_tiempo_muerto numeric DEFAULT 0, p_uni numeric DEFAULT 0, p_seg_trabajados numeric DEFAULT 0, p_seg_historico numeric DEFAULT 0, p_premio numeric DEFAULT 0, p_anular boolean DEFAULT false)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
begin
  update produccion
  set hora_inicio = p_hora_inicio::time,
      hora_fin = p_hora_fin::time,
      segundos_tiempo_muerto = p_seg_tiempo_muerto,
      uni = p_uni,
      segundos_trabajados = p_seg_trabajados,
      segundos_historico = p_seg_historico,
      premio = p_premio,
      anular_tiempo = p_anular,
      revisado = case when p_anular then true else revisado end
  where id = row_id;
  if not found then
    raise exception 'Registro id=% no encontrado', row_id;
  end if;
end;
$function$
;

-- ---------- anular_recepcion ----------
CREATE OR REPLACE FUNCTION "GP2".anular_recepcion(p_recepcion_ids bigint[])
 RETURNS TABLE(anuladas integer, movimientos_borrados integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
declare
  v_mov_ids bigint[];
  v_movs int := 0;
  v_recs int := 0;
begin
  if p_recepcion_ids is null or array_length(p_recepcion_ids, 1) is null then
    return query select 0, 0;
    return;
  end if;

  -- Movimientos asociados (uno por recepcion en general, pueden ser null)
  select coalesce(array_agg(movimiento_id) filter (where movimiento_id is not null), array[]::bigint[])
    into v_mov_ids
  from "GP2".recepcion_insumo
  where id = any(p_recepcion_ids);

  -- Borrar movimientos primero: el trigger AFTER DELETE de GP2.movimiento
  -- (fn_movimiento_aplicar) revierte el impacto en GP2.inventario.
  if array_length(v_mov_ids, 1) is not null then
    delete from "GP2".movimiento where id = any(v_mov_ids);
    get diagnostics v_movs = row_count;
  end if;

  -- Borrar recepciones: cascadea a recepcion_control (CASCADE) y por ahi a
  -- recepcion_control_rollo (CASCADE tambien).
  delete from "GP2".recepcion_insumo where id = any(p_recepcion_ids);
  get diagnostics v_recs = row_count;

  return query select v_recs, v_movs;
end;
$function$
;

-- ---------- asignar_pintor_activo ----------
CREATE OR REPLACE FUNCTION "GP2".asignar_pintor_activo(p_comp_id bigint, p_prov_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
declare v_cod text; v_prov text;
begin
  select codigo into v_cod from componente where id = p_comp_id;
  if v_cod is null then raise exception 'Componente inexistente (id=%).', p_comp_id; end if;

  update parte_proveedor_servicio set asignado = false
   where componente_id = p_comp_id and asignado;

  if p_prov_id is not null then
    -- Solo puede quedarse con la parte alguien que ademas PUEDE pintarla.
    if not exists (select 1 from parte_proveedor_servicio
                    where componente_id = p_comp_id and proveedor_servicio_id = p_prov_id) then
      raise exception 'Ese pintor no esta habilitado para la parte %. Prendelo primero.', v_cod;
    end if;
    update parte_proveedor_servicio set asignado = true
     where componente_id = p_comp_id and proveedor_servicio_id = p_prov_id;
    select nombre into v_prov from proveedor_servicio where id = p_prov_id;
  end if;

  return jsonb_build_object('ok', true, 'codigo', v_cod, 'pintor', v_prov);
end $function$
;

-- ---------- asignar_pintor_parte ----------
CREATE OR REPLACE FUNCTION "GP2".asignar_pintor_parte(p_comp_id bigint, p_prov_id bigint, p_activo boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
declare
  v_cod text; v_prov text; v_n int;
begin
  select codigo into v_cod from componente where id = p_comp_id;
  if v_cod is null then
    raise exception 'Componente inexistente (id=%).', p_comp_id;
  end if;

  select nombre into v_prov from proveedor_servicio
   where id = p_prov_id and proceso = 'Pintado';
  if v_prov is null then
    raise exception 'El pintor (id=%) no existe. Dalo de alta primero.', p_prov_id;
  end if;

  if coalesce(p_activo,false) then
    insert into parte_proveedor_servicio (componente_id, proveedor_servicio_id)
    values (p_comp_id, p_prov_id)
    on conflict do nothing;
  else
    delete from parte_proveedor_servicio
     where componente_id = p_comp_id and proveedor_servicio_id = p_prov_id;
  end if;

  select count(*) into v_n from parte_proveedor_servicio where componente_id = p_comp_id;

  return jsonb_build_object('ok', true, 'comp_id', p_comp_id, 'codigo', v_cod,
                            'pintor', v_prov, 'activo', coalesce(p_activo,false),
                            'pintores_ahora', v_n);
end $function$
;

-- ---------- asignar_proveedor_parte ----------
CREATE OR REPLACE FUNCTION "GP2".asignar_proveedor_parte(p_comp_id bigint, p_proveedor text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
declare
  v_prov text := nullif(btrim(coalesce(p_proveedor,'')),'');
  v_cod text; v_sector text; v_antes text;
begin
  select c.codigo, s.nombre, nullif(btrim(coalesce(c.proveedor,'')),'')
    into v_cod, v_sector, v_antes
    from componente c left join sector s on s.id=c.sector_id
   where c.id = p_comp_id;
  if v_cod is null then
    raise exception 'Componente inexistente (id=%).', p_comp_id;
  end if;

  -- v_prov null = desasignar (queda pendiente de definir, no se inventa nada)
  if v_prov is not null and not exists (
       select 1 from proveedor_insumo where nombre = v_prov and activo) then
    raise exception 'El proveedor "%" no existe o esta inactivo. Dalo de alta primero.', v_prov;
  end if;

  update componente
     set proveedor = v_prov,
         estado_compra = case when v_prov is null then estado_compra else null end
   where id = p_comp_id;

  return jsonb_build_object('ok',true,'comp_id',p_comp_id,'codigo',v_cod,
                            'sector',v_sector,'antes',v_antes,'proveedor',v_prov);
end $function$
;

-- ---------- cargar_compra_mp ----------
CREATE OR REPLACE FUNCTION "GP2".cargar_compra_mp(p_proveedor text, p_kg numeric, p_remito text DEFAULT NULL::text, p_fecha timestamp with time zone DEFAULT now(), p_pct_corto numeric DEFAULT NULL::numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
declare
  v_ps bigint; v_ps_nombre text; v_comp bigint; v_cod text; v_ubic bigint; v_mov bigint; v_rec bigint;
  v_f timestamptz := coalesce(p_fecha, now()); v_stock numeric;
  v_pc numeric; v_pl numeric; v_kg_corto numeric; v_kg_largo numeric; v_split jsonb := null;
begin
  if p_kg is null or p_kg <= 0 then
    raise exception 'Los kg deben ser mayores a 0 (recibido: %)', p_kg;
  end if;

  -- que materia prima vende este proveedor y que PS hibrido la recibe (configuracion, no literales)
  begin
    select ps.id, ps.nombre, c.id, c.codigo into strict v_ps, v_ps_nombre, v_comp, v_cod
      from proveedor_servicio ps join componente c on c.id = ps.mp_componente_id
     where ps.hibrido and c.proveedor = p_proveedor;
  exception
    when no_data_found then
      raise exception 'Ningun PS hibrido recibe materia prima de "%" (falta proveedor_servicio.mp_componente_id o componente.proveedor)', p_proveedor;
    when too_many_rows then
      raise exception 'Mas de un PS hibrido recibe materia prima de "%": configuracion ambigua en proveedor_servicio.mp_componente_id', p_proveedor;
  end;
  v_ubic := ubic_de('proveedor_servicio', v_ps);
  if v_ubic is null then raise exception 'El PS "%" no tiene ubicacion', v_ps_nombre; end if;

  -- reparto corto/largo (instruccion de corte; hoy solo Charcas lo usa)
  if p_pct_corto is not null then
    if p_pct_corto < 0 or p_pct_corto > 100 then
      raise exception 'El %% de corto debe estar entre 0 y 100 (recibido: %)', p_pct_corto;
    end if;
    v_pc := p_pct_corto; v_pl := 100 - p_pct_corto;
    v_kg_corto := round((p_kg * v_pc/100)::numeric, 3);
    v_kg_largo := round((p_kg * v_pl/100)::numeric, 3);
    v_split := jsonb_build_object('pct_corto', v_pc, 'pct_largo', v_pl,
                                  'kg_corto_objetivo', v_kg_corto, 'kg_largo_objetivo', v_kg_largo);
  end if;

  insert into movimiento(fecha, tipo_mov, comp_id, ubic_origen_id, ubic_destino_id, cantidad, unidad_origen, unidad_destino)
  values (v_f, 'compra', v_comp, null, v_ubic, p_kg, 'kg', 'kg') returning id into v_mov;

  insert into recepcion_insumo(fecha, componente_id, proveedor, remito, cantidad, unidad, movimiento_id, rollos_json)
  values (v_f, v_comp, p_proveedor, nullif(btrim(coalesce(p_remito,'')),''), p_kg, 'kg', v_mov, v_split)
  returning id into v_rec;

  perform _aplicar_recepcion_a_oc(v_comp, p_kg, 'kg');
  select cantidad into v_stock from inventario where componente_id = v_comp and ubicacion_id = v_ubic;

  return jsonb_build_object('ok', true, 'recepcion_id', v_rec, 'movimiento_id', v_mov,
    'kg_cargados', p_kg, 'stock_kg', coalesce(v_stock, 0), 'ps_id', v_ps, 'ps', v_ps_nombre, 'componente', v_cod,
    'pct_corto', v_pc, 'pct_largo', v_pl, 'kg_corto_objetivo', v_kg_corto, 'kg_largo_objetivo', v_kg_largo);
end $function$
;

-- ---------- cargar_recepcion ----------
CREATE OR REPLACE FUNCTION "GP2".cargar_recepcion(p_comp_id bigint, p_proveedor text, p_cantidad numeric, p_unidad text DEFAULT NULL::text, p_remito text DEFAULT NULL::text, p_rollos integer DEFAULT NULL::integer, p_pallets integer DEFAULT NULL::integer, p_fecha timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
declare v_res jsonb; v_rec bigint;
begin
  if p_rollos is not null and p_rollos <= 0 then
    raise exception 'Los rollos deben ser mayores a 0 (recibido: %)', p_rollos;
  end if;
  if p_pallets is not null and p_pallets <= 0 then
    raise exception 'Los pallets deben ser mayores a 0 (recibido: %)', p_pallets;
  end if;
  v_res := "GP2".crear_recepcion_insumo(p_comp_id, p_proveedor, p_cantidad, p_unidad, p_remito, p_fecha);
  v_rec := (v_res->>'recepcion_id')::bigint;
  update "GP2".recepcion_insumo
     set rollos = p_rollos, pallets = p_pallets
   where id = v_rec;
  return v_res || jsonb_build_object('rollos', p_rollos, 'pallets', p_pallets);
end $function$
;

-- ---------- cargar_recepcion_charcas ----------
CREATE OR REPLACE FUNCTION "GP2".cargar_recepcion_charcas(p_comp_id bigint, p_uni_remito integer, p_kg_balanza numeric, p_remito text DEFAULT NULL::text, p_fecha timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
declare
  v_codigo text; v_prov text; v_kg_x_uni numeric; v_sec int;
  v_bruto bigint; v_uni_calc numeric; v_diff_pct numeric;
  v_ubic_destino bigint;
  v_ps_charcas bigint;        -- proveedor_servicio "Resortes Charcas", resuelto por nombre una vez
  v_ubic_charcas bigint;      -- ubic_de('proveedor_servicio', v_ps_charcas)  (era el literal 13)
  v_ubic_cervantes bigint;    -- ubic_de('sector', 5) = Sector Fleje          (era el literal 5)
  v_ubic_virgilio bigint;     -- ubic_de('virgilio')                          (era el literal 33)
  v_tol_pct constant numeric := 5;
  v_mov_prod bigint; v_mov_bruto bigint; v_rec bigint;
  v_stock_bruto_antes numeric; v_stock_bruto_despues numeric;
  v_f timestamptz := coalesce(p_fecha, now()); v_es_largo boolean;
begin
  if p_uni_remito is null or p_uni_remito <= 0 then
    raise exception 'Las unidades del remito deben ser > 0 (recibido: %)', p_uni_remito;
  end if;
  if p_kg_balanza is null or p_kg_balanza <= 0 then
    raise exception 'Los kg de balanza deben ser > 0 (recibido: %)', p_kg_balanza;
  end if;
  select codigo, proveedor, kg_x_uni, sector_id into v_codigo, v_prov, v_kg_x_uni, v_sec
    from "GP2".componente where id = p_comp_id;
  if v_codigo is null then raise exception 'El componente % no existe', p_comp_id; end if;
  if v_codigo not in ('IC3','IC3V') then
    raise exception 'El componente % no es IC3 ni IC3V (recibido: %)', p_comp_id, v_codigo;
  end if;
  if v_kg_x_uni is null or v_kg_x_uni <= 0 then
    raise exception 'El componente % no tiene kg_x_uni cargado', v_codigo;
  end if;

  -- ubicaciones: una sola forma de resolverlas (ubic_de)
  select id into v_ps_charcas from "GP2".proveedor_servicio where nombre = 'Resortes Charcas';
  if v_ps_charcas is null then raise exception 'No existe el proveedor de servicio "Resortes Charcas"'; end if;
  v_ubic_charcas   := "GP2".ubic_de('proveedor_servicio', v_ps_charcas);
  v_ubic_cervantes := "GP2".ubic_de('sector', 5);
  v_ubic_virgilio  := "GP2".ubic_de('virgilio');
  if v_ubic_charcas is null then raise exception 'El PS "Resortes Charcas" no tiene ubicacion'; end if;
  if v_ubic_cervantes is null then raise exception 'No hay ubicacion para el Sector Fleje (sector 5)'; end if;
  if v_ubic_virgilio is null then raise exception 'No existe la ubicacion de Virgilio'; end if;

  v_es_largo := (v_codigo='IC3V');
  v_ubic_destino := case when v_es_largo then v_ubic_virgilio else v_ubic_cervantes end;

  v_uni_calc := round(p_kg_balanza / v_kg_x_uni);
  v_diff_pct := round( (abs(p_uni_remito - v_uni_calc)::numeric / greatest(p_uni_remito,1)) * 100, 2 );

  select id into v_bruto from "GP2".componente where codigo='FLEJE90_BRUTO';
  if v_bruto is null then raise exception 'FLEJE90_BRUTO no existe'; end if;

  select coalesce(cantidad,0) into v_stock_bruto_antes
    from "GP2".inventario where componente_id=v_bruto and ubicacion_id=v_ubic_charcas;

  -- Mov 1: suma KG del producto cortado en destino
  insert into "GP2".movimiento(fecha,tipo_mov,comp_id,ubic_origen_id,ubic_destino_id,cantidad,unidad_origen,unidad_destino)
  values (v_f,'compra',p_comp_id,null,v_ubic_destino,p_kg_balanza,'kg','kg')
  returning id into v_mov_prod;

  -- Mov 2: descuenta los mismos kg del alambre bruto en Charcas (1:1, control)
  insert into "GP2".movimiento(fecha,tipo_mov,comp_id,ubic_origen_id,ubic_destino_id,cantidad,unidad_origen,unidad_destino)
  values (v_f,'consumo',v_bruto,v_ubic_charcas,null,p_kg_balanza,'kg','kg')
  returning id into v_mov_bruto;

  insert into "GP2".recepcion_insumo(fecha,componente_id,proveedor,remito,cantidad,unidad,movimiento_id,rollos_json)
  values (v_f, p_comp_id, 'Resortes Charcas',
          nullif(btrim(coalesce(p_remito,'')),''),
          p_kg_balanza, 'kg', v_mov_prod,
          jsonb_build_object(
            'producto', case when v_es_largo then 'largo' else 'corto' end,
            'uni_remito', p_uni_remito,
            'kg_balanza', p_kg_balanza,
            'uni_calculadas', v_uni_calc,
            'diferencia_pct', v_diff_pct,
            'tolerado_pct', v_tol_pct,
            'dentro_tolerancia', (v_diff_pct <= v_tol_pct),
            'movimiento_bruto_id', v_mov_bruto,
            'destino_ubic', v_ubic_destino
          ))
  returning id into v_rec;

  perform "GP2"._aplicar_recepcion_a_oc(p_comp_id, p_kg_balanza, 'kg');

  select coalesce(cantidad,0) into v_stock_bruto_despues
    from "GP2".inventario where componente_id=v_bruto and ubicacion_id=v_ubic_charcas;

  return jsonb_build_object(
    'ok', true, 'recepcion_id', v_rec,
    'movimiento_producto_id', v_mov_prod, 'movimiento_bruto_id', v_mov_bruto,
    'codigo', v_codigo, 'producto', case when v_es_largo then 'largo' else 'corto' end,
    'destino_ubic', v_ubic_destino,
    'uni_remito', p_uni_remito, 'kg_balanza', p_kg_balanza,
    'uni_calculadas', v_uni_calc, 'diferencia_pct', v_diff_pct,
    'tolerado_pct', v_tol_pct, 'dentro_tolerancia', (v_diff_pct <= v_tol_pct),
    'stock_bruto_charcas_antes', v_stock_bruto_antes,
    'stock_bruto_charcas_despues', v_stock_bruto_despues,
    'bruto_negativo', (v_stock_bruto_despues < 0)
  );
end $function$
;

-- ---------- cargar_recepcion_eclipse ----------
CREATE OR REPLACE FUNCTION "GP2".cargar_recepcion_eclipse(p_comp_id bigint, p_unidades integer, p_remito text DEFAULT NULL::text, p_fecha timestamp with time zone DEFAULT now(), p_kg_entrega numeric DEFAULT NULL::numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
declare
  v_codigo text; v_prov text; v_kg_x_uni numeric; v_sec int;
  v_chapa bigint; v_desperdicio numeric;
  v_kg_producto numeric; v_kg_chapa numeric; v_manual boolean := false;
  v_mov_prod bigint; v_mov_chapa bigint; v_rec bigint;
  v_ubic_procesado bigint;
  v_ps_eclipse bigint;        -- proveedor_servicio "Eclipse", resuelto por nombre una vez
  v_ubic_eclipse bigint;      -- ubic_de('proveedor_servicio', v_ps_eclipse)  (era el literal 48)
  v_stock_chapa_antes numeric; v_stock_chapa_despues numeric;
  v_f timestamptz := coalesce(p_fecha, now());
begin
  if p_unidades is null or p_unidades <= 0 then
    raise exception 'Las unidades deben ser mayores a 0 (recibido: %)', p_unidades;
  end if;
  select codigo, proveedor, kg_x_uni, sector_id into v_codigo, v_prov, v_kg_x_uni, v_sec
    from "GP2".componente where id = p_comp_id;
  if v_codigo is null then raise exception 'El componente % no existe', p_comp_id; end if;
  if coalesce(v_prov,'') <> 'Eclipse' then
    raise exception 'El componente % no es de Eclipse (proveedor: %)', v_codigo, coalesce(v_prov,'null');
  end if;
  if v_kg_x_uni is null or v_kg_x_uni <= 0 then
    raise exception 'El componente % no tiene kg_x_uni cargado', v_codigo;
  end if;

  -- Ubic destino del producto: la que corresponde al sector del componente.
  v_ubic_procesado := "GP2".ubic_de('sector', v_sec);
  if v_ubic_procesado is null then
    raise exception 'No hay ubicacion tipo=sector para el sector % del componente %', v_sec, v_codigo;
  end if;

  -- Ubic del PS Eclipse (donde vive la chapa bruta)
  select id into v_ps_eclipse from "GP2".proveedor_servicio where nombre = 'Eclipse';
  if v_ps_eclipse is null then raise exception 'No existe el proveedor de servicio "Eclipse"'; end if;
  v_ubic_eclipse := "GP2".ubic_de('proveedor_servicio', v_ps_eclipse);
  if v_ubic_eclipse is null then raise exception 'El PS "Eclipse" no tiene ubicacion'; end if;

  select id into v_chapa from "GP2".componente where codigo='CHAPA430';
  if v_chapa is null then raise exception 'CHAPA430 no existe (Fase 1 pendiente)'; end if;
  select coalesce(desperdicio_pct, 0) into v_desperdicio from "GP2".proveedor_servicio where id = v_ps_eclipse;  -- el % vive en el PS
  if v_desperdicio < 0 or v_desperdicio >= 100 then v_desperdicio := 0; end if;  -- proteccion division

  -- Peso del producto entregado: el KG del remito (real, se pesa) si viene; si no, el teorico.
  if p_kg_entrega is not null and p_kg_entrega > 0 then
    v_kg_producto := round(p_kg_entrega::numeric, 3);
    v_manual := true;
  else
    v_kg_producto := round((p_unidades * v_kg_x_uni)::numeric, 3);
  end if;
  -- La chapa consumida se deriva del peso entregado: el desperdicio es % DE LA CHAPA.
  v_kg_chapa := round((v_kg_producto / (1 - v_desperdicio/100))::numeric, 3);

  select coalesce(cantidad,0) into v_stock_chapa_antes
    from "GP2".inventario where componente_id=v_chapa and ubicacion_id=v_ubic_eclipse;

  -- Producto 1686: se guarda EN KG (lo pesado), NO en unidades.
  insert into "GP2".movimiento(fecha, tipo_mov, comp_id, ubic_origen_id, ubic_destino_id,
                               cantidad, unidad_origen, unidad_destino)
  values (v_f, 'compra', p_comp_id, null, v_ubic_procesado, v_kg_producto, 'kg', 'kg')
  returning id into v_mov_prod;

  insert into "GP2".movimiento(fecha, tipo_mov, comp_id, ubic_origen_id, ubic_destino_id,
                               cantidad, unidad_origen, unidad_destino)
  values (v_f, 'consumo', v_chapa, v_ubic_eclipse, null, v_kg_chapa, 'kg', 'kg')
  returning id into v_mov_chapa;

  insert into "GP2".recepcion_insumo(fecha, componente_id, proveedor, remito,
                                     cantidad, unidad, movimiento_id, rollos_json)
  values (v_f, p_comp_id, 'Eclipse', nullif(btrim(coalesce(p_remito,'')),''),
          v_kg_producto, 'kg', v_mov_prod,
          jsonb_build_object('uni_referencia', p_unidades, 'kg_entregado', v_kg_producto,
                             'kg_entrega_manual', v_manual,
                             'kg_chapa_consumida', v_kg_chapa, 'desperdicio_pct', v_desperdicio,
                             'movimiento_chapa_id', v_mov_chapa))
  returning id into v_rec;

  perform "GP2"._aplicar_recepcion_a_oc(p_comp_id, v_kg_producto, 'kg');

  select coalesce(cantidad,0) into v_stock_chapa_despues
    from "GP2".inventario where componente_id=v_chapa and ubicacion_id=v_ubic_eclipse;

  return jsonb_build_object(
    'ok', true, 'recepcion_id', v_rec,
    'movimiento_producto_id', v_mov_prod, 'movimiento_chapa_id', v_mov_chapa,
    'codigo', v_codigo, 'uni_referencia', p_unidades, 'kg_entregado', v_kg_producto,
    'kg_producto', v_kg_producto, 'kg_entrega_manual', v_manual,
    'kg_chapa_consumida', v_kg_chapa,
    'stock_chapa_eclipse_antes', v_stock_chapa_antes,
    'stock_chapa_eclipse_despues', v_stock_chapa_despues,
    'chapa_negativa', (v_stock_chapa_despues < 0)
  );
end $function$
;

-- ---------- cerrar_rollo ----------
CREATE OR REPLACE FUNCTION "GP2".cerrar_rollo(p_legajo text, p_quedo_resto boolean, p_uni_producidas numeric DEFAULT NULL::numeric, p_fecha timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
declare u record; v_uni numeric; v_ppk numeric; v_esp numeric; v_alerta text;
begin
  select * into u from rollo_uso where legajo=p_legajo and ts_fin is null
   order by ts_inicio desc limit 1;
  if u.id is null then
    return jsonb_build_object('ok',false,'error','No hay rollo abierto para el legajo '||p_legajo);
  end if;
  v_uni := coalesce(p_uni_producidas,
    (select coalesce(sum(uni),0) from produccion
      where legajo=p_legajo and fecha >= u.ts_inicio and fecha <= coalesce(p_fecha,now()) and uni > 0));
  select partes_por_kilo_de_fleje into v_ppk from matriz
   where btrim(n_matriz) = btrim(coalesce(u.matriz_raw,'')) limit 1;
  v_esp := case when v_ppk is not null and v_ppk > 0 then u.kg_por_rollo * v_ppk end;
  if not p_quedo_resto and v_esp is not null then
    if v_uni < v_esp * 0.6 then
      v_alerta := 'Rollo terminado con '||round(v_uni)||' uni, pero un rollo de '||u.kg_por_rollo||
        ' kg deberia dar ~'||round(v_esp)||'. Diferencia grande: revisar.';
    elsif v_uni > v_esp * 1.4 then
      v_alerta := 'Rollo rindio '||round(v_uni)||' uni, bastante mas que las ~'||round(v_esp)||
        ' esperadas. Revisar el parametro piezas/kg.';
    end if;
  end if;
  update rollo_uso set ts_fin=coalesce(p_fecha,now()), quedo_resto=p_quedo_resto,
    uni_producidas=v_uni, uni_esperadas=v_esp where id=u.id;
  -- si quedo resto, el rollo vuelve al stock como devolucion parcial NO se puede
  -- cuantificar en rollos enteros: queda registrado en el uso, no en el ledger.
  return jsonb_build_object('ok',true,'uso_id',u.id,'kg_por_rollo',u.kg_por_rollo,
    'uni_producidas',v_uni,'uni_esperadas',v_esp,'quedo_resto',p_quedo_resto,'alerta',v_alerta);
end $function$
;

-- ---------- charcas_pendiente ----------
CREATE OR REPLACE FUNCTION "GP2".charcas_pendiente()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
  with obj as (
    select
      coalesce(sum((rollos_json->>'kg_corto_objetivo')::numeric),0) as corto_obj,
      coalesce(sum((rollos_json->>'kg_largo_objetivo')::numeric),0) as largo_obj
    from "GP2".recepcion_insumo
    where proveedor='Altrak' and rollos_json ? 'kg_corto_objetivo'
  ),
  ent as (
    select
      coalesce(sum(case when componente_id=214 then cantidad else 0 end),0) as corto_ent,  -- IC3 corto
      coalesce(sum(case when componente_id=373 then cantidad else 0 end),0) as largo_ent    -- IC3V largo
    from "GP2".recepcion_insumo
    where componente_id in (214,373)
  )
  select jsonb_build_object(
    'corto_objetivo', obj.corto_obj, 'largo_objetivo', obj.largo_obj,
    'corto_entregado', ent.corto_ent, 'largo_entregado', ent.largo_ent,
    'corto_pendiente', round((obj.corto_obj - ent.corto_ent)::numeric, 2),
    'largo_pendiente', round((obj.largo_obj - ent.largo_ent)::numeric, 2)
  ) from obj, ent;
$function$
;

-- ---------- composicion_stock ----------
CREATE OR REPLACE FUNCTION "GP2".composicion_stock(p_comp_id bigint, p_ubic_id bigint DEFAULT NULL::bigint, p_limit integer DEFAULT 300, p_ubic_tipo text DEFAULT NULL::text, p_ref_id bigint DEFAULT NULL::bigint)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
  with u as (
    select coalesce(p_ubic_id, "GP2".ubic_de(p_ubic_tipo, p_ref_id)) as id
  ),
  todos as (
    select m.id, m.fecha, m.tipo_mov as tipo, 'ent'::text as signo,
           coalesce(m._delta_dest,0) as cantidad, m.cajones, m.faltante,
           coalesce(uo.nombre,'—') as contraparte,
           case when m.comp_transformado_id is not null and m.comp_id <> p_comp_id
                then (select codigo from componente where id = m.comp_id) end as via
    from movimiento m
    left join ubicacion uo on uo.id = m.ubic_origen_id
    cross join u
    where m.ubic_destino_id = u.id
      and coalesce(m.comp_transformado_id, m.comp_id) = p_comp_id
    union all
    select m.id, m.fecha, m.tipo_mov, 'sal',
           coalesce(m._delta_orig,0), m.cajones, m.faltante,
           coalesce(ud.nombre,'—'),
           case when m.comp_transformado_id is not null
                then (select codigo from componente where id = m.comp_transformado_id) end
    from movimiento m
    left join ubicacion ud on ud.id = m.ubic_destino_id
    cross join u
    where m.ubic_origen_id = u.id and m.comp_id = p_comp_id
  ),
  pagina as (select * from todos order by fecha desc, id desc limit greatest(p_limit,1))
  select jsonb_build_object(
    'comp', (select jsonb_build_object('id',c.id,'codigo',c.codigo,'descripcion',c.descripcion,
                                       'kg_x_uni',c.kg_x_uni,'uni_x_cajon',c.uni_x_cajon)
             from componente c where c.id = p_comp_id),
    'ubicacion', (select jsonb_build_object('id',x.id,'nombre',x.nombre,'tipo',x.tipo)
                  from ubicacion x cross join u where x.id = u.id),
    'online',  (select i.cantidad from inventario i cross join u
                where i.componente_id = p_comp_id and i.ubicacion_id = u.id),
    'minimo',  (select i.minimo from inventario i cross join u
                where i.componente_id = p_comp_id and i.ubicacion_id = u.id),
    'actualizado_en', (select i.actualizado_en from inventario i cross join u
                where i.componente_id = p_comp_id and i.ubicacion_id = u.id),
    'total_movs', (select count(*) from todos),
    'movs', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id',p.id,'fecha',p.fecha,'tipo',p.tipo,'signo',p.signo,
               'cantidad',p.cantidad,'cajones',p.cajones,'faltante',p.faltante,
               'contraparte',p.contraparte,'via',p.via
             ) order by p.fecha desc, p.id desc)
      from pagina p), '[]'::jsonb)
  );
$function$
;

-- ---------- consumo_detalle ----------
CREATE OR REPLACE FUNCTION "GP2".consumo_detalle(p_comp_id bigint)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
select jsonb_build_object(
  'comp_id', c.id,
  'codigo', c.codigo,
  'descripcion', c.descripcion,
  'sector', s.nombre,
  'es_fleje', (c.sector_id = 5),
  'uni_x_cajon', c.uni_x_cajon,
  'total_uni_mes', (select round(sum(d.uni_mes)) from v_consumo_demanda d where d.componente_id = c.id),
  'total_kg_mes', (select fk.consumo_kg_mes from v_consumo_fleje_kg fk where fk.componente_id = c.id),
  'articulos', coalesce((
    select jsonb_agg(jsonb_build_object(
             'articulo', a.codigo,
             'familia', a.familia,
             'proy_uni_mes', round(em.proy),
             'uni_mes', round(d.uni_mes),
             'kg_mes', kg.kg,
             'receta_directa', exists (select 1 from articulo_componente ac
                                        where ac.articulo_id = a.id and ac.componente_id = c.id)
           ) order by d.uni_mes desc)
    from v_consumo_demanda d
    join articulo a on a.id = d.articulo_id
    left join lateral (
      select sum(em2.proy_uni_mes) proy from est_madre em2
      where regexp_replace(em2.cod,'^0+','') = regexp_replace(a.codigo,'^0+','')
    ) em on true
    left join lateral (
      -- kg del fleje que este articulo consume (solo si el componente es fleje)
      select round(sum(d2.uni_mes / p.ppk), 1) kg
      from (select distinct r.articulo_id art_id, rp.comp_salida_id sal, m.partes_por_kilo_de_fleje ppk
              from ruta_paso rp
              join ruta r on r.id = rp.ruta_id
              join matriz m on m.id = rp.matriz_id
             where rp.comp_entrada_id = c.id and c.sector_id = 5
               and coalesce(m.partes_por_kilo_de_fleje,0) > 0) p
      join v_consumo_demanda d2 on d2.articulo_id = p.art_id and d2.componente_id = p.sal
      where p.art_id = a.id
    ) kg on true
    where d.componente_id = c.id
  ), '[]'::jsonb)
)
from componente c
left join sector s on s.id = c.sector_id
where c.id = p_comp_id;
$function$
;

-- ---------- control_envios_bundle ----------
CREATE OR REPLACE FUNCTION "GP2".control_envios_bundle(p_desde date, p_hasta date)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
select jsonb_build_object(
  'filas', (select coalesce(jsonb_agg(jsonb_build_object(
      'fecha', to_char(m.fecha at time zone 'America/Argentina/Buenos_Aires','YYYY-MM-DD'),
      'tipo', m.tipo_mov,
      'comp_id', c.id, 'codigo', c.codigo, 'descripcion', c.descripcion,
      'um', c.unidad_medida, 'kg_x_uni', c.kg_x_uni, 'uni_x_cajon', c.uni_x_cajon,
      'orig', uo.nombre, 'dest', ud.nombre,
      'cantidad', m.cantidad, 'unidad', coalesce(m.unidad_origen, m.unidad_destino),
      'canon', m._delta_orig)),'[]'::jsonb)
    from movimiento m
    join componente c on c.id = m.comp_id
    left join ubicacion uo on uo.id = m.ubic_origen_id
    left join ubicacion ud on ud.id = m.ubic_destino_id
    where m.tipo_mov in ('envio_ps','entrega_ps','envio_tallerista','entrega_tallerista',
                         'recepcion_virgilio','devolucion_tallerista','envio_prov_at','compra')
      and (m.fecha at time zone 'America/Argentina/Buenos_Aires')::date between p_desde and p_hasta),
  'desde', p_desde, 'hasta', p_hasta, 'generado_en', now());
$function$
;

-- ---------- control_ps_bundle ----------
CREATE OR REPLACE FUNCTION "GP2".control_ps_bundle()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
with ps as (
  select p.id ps_id, p.cod_prov, p.nombre, p.proceso, u.ubic_id
  from proveedor_servicio p
  join lateral (select "GP2".ubic_de('proveedor_servicio', p.id) ubic_id) u on u.ubic_id is not null
),
cfg as (
  -- que parte entra por PS: v_contraparte_parte (una sola definicion)
  select distinct ps.ubic_id, v.comp_id
  from ps join v_contraparte_parte v on v.tipo = 'proveedor_servicio' and v.ref_id = ps.ps_id and v.lado = 'entrada'
),
env as (
  select ubic_destino_id ubic_id, comp_id, sum(_delta_orig) enviado
  from movimiento
  where tipo_mov='envio_ps'
     or (tipo_mov='compra' and ubic_destino_id in (select ubic_id from ps))
  group by 1,2
),
ent as (
  -- Hibridos (Fleje90/Charcas, Chapa430/Eclipse): la MP BRUTA (FLEJE90_BRUTO, CHAPA430)
  -- se consume al cortarla, NO es una entrega. Lo que el PS entrega es el producto cortado
  -- (IC3/IC3V para Charcas, 1686 para Eclipse), que sale como 'compra' hacia su destino;
  -- esa compra se atribuye al PS que corta.
  select ubic_id, comp_id, sum(entregado) entregado from (
    select ubic_origen_id ubic_id, comp_id, sum(_delta_dest) entregado
    from movimiento where tipo_mov='entrega_ps'
    group by 1,2
    union all
    select ubic_origen_id ubic_id, comp_id, sum(_delta_dest) entregado
    from movimiento
    where tipo_mov='consumo' and ubic_origen_id in (select ubic_id from ps)
      and comp_id not in (select id from componente where codigo in ('FLEJE90_BRUTO','CHAPA430'))
    group by 1,2
    union all
    select (select ubic_id from ps where ps_id=1) ubic_id, m.comp_id, sum(m._delta_dest) entregado
    from movimiento m
    where m.tipo_mov='compra'
      and m.comp_id in (select id from componente where codigo in ('IC3','IC3V'))
    group by m.comp_id
    union all
    select (select ubic_id from ps where ps_id=13) ubic_id, m.comp_id, sum(m._delta_dest) entregado
    from movimiento m
    where m.tipo_mov='compra'
      and m.comp_id in (select id from componente where codigo='1686')
    group by m.comp_id
  ) e group by 1,2
),
inv as (select ubicacion_id ubic_id, componente_id comp_id, sum(cantidad) saldo from inventario group by 1,2),
keys as (
  select ubic_id, comp_id from cfg
  union select ubic_id, comp_id from env
  union select ubic_id, comp_id from ent
  union select ubic_id, comp_id from inv
),
partes as (
  select ps.ps_id, k.comp_id,
    coalesce(env.enviado,0) enviado, coalesce(ent.entregado,0) entregado, coalesce(inv.saldo,0) saldo
  from keys k
  join ps on ps.ubic_id=k.ubic_id
  left join env on env.ubic_id=k.ubic_id and env.comp_id=k.comp_id
  left join ent on ent.ubic_id=k.ubic_id and ent.comp_id=k.comp_id
  left join inv on inv.ubic_id=k.ubic_id and inv.comp_id=k.comp_id
),
partes_j as (
  select p.ps_id, jsonb_agg(jsonb_build_object(
      'comp_id',p.comp_id,'codigo',c.codigo,'descripcion',c.descripcion,'sector',s.nombre,
      'enviado',round(p.enviado,3),'entregado',round(p.entregado,3),'saldo',round(p.saldo,3)
    ) order by c.codigo, c.id) partes
  from partes p join componente c on c.id=p.comp_id left join sector s on s.id=c.sector_id
  group by p.ps_id
)
select jsonb_build_object('generado_en', now(),
  'proveedores', coalesce(jsonb_agg(jsonb_build_object(
    'ps_id',ps.ps_id,'nombre',ps.nombre,'proceso',ps.proceso,'cod_prov',ps.cod_prov,
    'nombre_corto', al.nombre_corto, 'partes', coalesce(pj.partes,'[]'::jsonb)
  ) order by ps.nombre),'[]'::jsonb))
from ps
left join lateral (select p2.nombre_corto from proveedor_servicio p2 where p2.id=ps.ps_id) al on true
left join partes_j pj on pj.ps_id=ps.ps_id;
$function$
;

-- ---------- control_recepcion_bundle ----------
CREATE OR REPLACE FUNCTION "GP2".control_recepcion_bundle(p_sector_id integer)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
  with rec as (
    select r.id, r.fecha, r.componente_id, r.proveedor, r.remito, r.cantidad,
           r.unidad, r.movimiento_id, r.created_at, r.controlado,
           r.cantidad_declarada, r.base, r.pisos, r.sueltas, r.paquetes,
           r.uni_x_paq, r.controlado_en, r.controlado_por,
           c.codigo, c.descripcion, c.recibe_en_cajas, c.kg_x_uni
    from recepcion_insumo r
    join componente c on c.id = r.componente_id
    where c.sector_id = p_sector_id
    order by r.fecha desc, r.id desc
    limit 500
  )
  select jsonb_build_object(
    'sector', (select nombre from sector where id = p_sector_id),
    'sector_id', p_sector_id,
    'recepciones', coalesce((select jsonb_agg(row_to_json(rec)) from rec), '[]'::jsonb),
    'uni_x_paq_default', coalesce((select valor::numeric from parametro where clave = 'caja_uni_x_paquete'), 25)
  );
$function$
;

-- ---------- controlar_recepcion_cajas ----------
CREATE OR REPLACE FUNCTION "GP2".controlar_recepcion_cajas(p_recepcion_id bigint, p_base integer, p_pisos integer, p_sueltas integer, p_uni_x_paq integer DEFAULT 25, p_usuario text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
DECLARE
  r "GP2".recepcion_insumo%ROWTYPE;
  v_base int := GREATEST(COALESCE(p_base, 0), 0);
  v_pisos int := GREATEST(COALESCE(p_pisos, 0), 0);
  v_sueltas int := GREATEST(COALESCE(p_sueltas, 0), 0);
  v_upp int := GREATEST(COALESCE(p_uni_x_paq, 25), 1);
  v_paq int := v_base * v_pisos;
  v_total int := v_paq * v_upp + v_sueltas;
  v_declarada numeric;
BEGIN
  SELECT * INTO r FROM "GP2".recepcion_insumo WHERE id = p_recepcion_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Recepción % no existe', p_recepcion_id USING ERRCODE = 'P0002';
  END IF;
  IF v_total <= 0 THEN
    RAISE EXCEPTION 'Total debe ser > 0 (base=%, pisos=%, sueltas=%)', v_base, v_pisos, v_sueltas USING ERRCODE = '22023';
  END IF;

  -- La primera vez, guarda la cantidad declarada; en re-control mantiene la original.
  v_declarada := COALESCE(r.cantidad_declarada, r.cantidad);

  UPDATE "GP2".recepcion_insumo
     SET controlado = true,
         cantidad_declarada = v_declarada,
         base = v_base,
         pisos = v_pisos,
         sueltas = v_sueltas,
         paquetes = v_paq,
         uni_x_paq = v_upp,
         cantidad = v_total,
         controlado_en = now(),
         controlado_por = p_usuario
   WHERE id = p_recepcion_id;

  -- Ajustar el movimiento asociado: los triggers de GP2.movimiento recalculan
  -- _delta_orig / _delta_dest y actualizan GP2.inventario.
  IF r.movimiento_id IS NOT NULL AND v_total::numeric <> r.cantidad THEN
    UPDATE "GP2".movimiento SET cantidad = v_total WHERE id = r.movimiento_id;
  END IF;

  RETURN jsonb_build_object(
    'recepcion_id', p_recepcion_id,
    'movimiento_id', r.movimiento_id,
    'declarada', v_declarada,
    'base', v_base, 'pisos', v_pisos, 'sueltas', v_sueltas,
    'paquetes', v_paq, 'uni_x_paq', v_upp,
    'total', v_total,
    'diff', v_total - v_declarada
  );
END;
$function$
;

-- ---------- controlar_recepcion_kg ----------
CREATE OR REPLACE FUNCTION "GP2".controlar_recepcion_kg(p_recepcion_id bigint, p_kg numeric, p_usuario text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
DECLARE
  r "GP2".recepcion_insumo%ROWTYPE;
  v_kg numeric := COALESCE(p_kg, 0);
  v_declarada numeric;
BEGIN
  SELECT * INTO r FROM "GP2".recepcion_insumo WHERE id = p_recepcion_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Recepción % no existe', p_recepcion_id USING ERRCODE = 'P0002';
  END IF;
  IF v_kg <= 0 THEN
    RAISE EXCEPTION 'Los kg controlados deben ser > 0 (recibido %)', v_kg USING ERRCODE = '22023';
  END IF;

  v_declarada := COALESCE(r.cantidad_declarada, r.cantidad);

  UPDATE "GP2".recepcion_insumo
     SET controlado = true,
         cantidad_declarada = v_declarada,
         cantidad = v_kg,
         base = null, pisos = null, sueltas = null, paquetes = null, uni_x_paq = null,
         controlado_en = now(),
         controlado_por = p_usuario
   WHERE id = p_recepcion_id;

  IF r.movimiento_id IS NOT NULL AND v_kg <> r.cantidad THEN
    UPDATE "GP2".movimiento SET cantidad = v_kg WHERE id = r.movimiento_id;
  END IF;

  RETURN jsonb_build_object(
    'recepcion_id', p_recepcion_id,
    'movimiento_id', r.movimiento_id,
    'declarada', v_declarada,
    'kg', v_kg,
    'diff', v_kg - v_declarada
  );
END;
$function$
;

-- ---------- crear_devolucion_tallerista ----------
CREATE OR REPLACE FUNCTION "GP2".crear_devolucion_tallerista(p_tallerista_id bigint, p_comp_id bigint, p_cantidad numeric, p_unidad text, p_destino text, p_motivo text DEFAULT NULL::text, p_fecha timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
declare
  v_tall text; v_cod text; v_sector text; v_sector_id bigint;
  v_ubic_orig bigint; v_ubic_dest bigint; v_mov bigint;
  v_unidad text := lower(trim(coalesce(p_unidad,'')));
  v_online numeric; v_canon numeric; v_aviso text;
begin
  if p_cantidad is null or p_cantidad <= 0 then
    raise exception 'La cantidad debe ser mayor a 0.';
  end if;
  if v_unidad not in ('kg','uni') then
    raise exception 'Unidad invalida: "%". Debe ser "kg" o "uni".', coalesce(p_unidad,'null');
  end if;
  if p_destino not in ('sector','analizar') then
    raise exception 'Destino invalido: "%". Debe ser "sector" o "analizar".', coalesce(p_destino,'null');
  end if;

  select nombre into v_tall from tallerista where id = p_tallerista_id;
  if v_tall is null then raise exception 'Tallerista inexistente (id=%).', p_tallerista_id; end if;

  v_ubic_orig := "GP2".ubic_de('tallerista', p_tallerista_id);
  if v_ubic_orig is null then
    raise exception 'El tallerista "%" no tiene ubicacion asociada.', v_tall;
  end if;

  select c.codigo, c.sector_id, s.nombre into v_cod, v_sector_id, v_sector
    from componente c left join sector s on s.id=c.sector_id where c.id=p_comp_id;
  if not found then raise exception 'Componente inexistente (id=%).', p_comp_id; end if;

  if p_destino = 'sector' then
    if v_sector_id is null then
      raise exception 'El componente "%" no tiene sector asignado; mandalo "Para Analizar".', coalesce(v_cod,'?');
    end if;
    v_ubic_dest := "GP2".ubic_de('sector', v_sector_id);
    if v_ubic_dest is null then
      raise exception 'No existe ubicacion de sector para "%".', coalesce(v_sector, v_sector_id::text);
    end if;
  else
    v_ubic_dest := "GP2".ubic_de('analisis');
    if v_ubic_dest is null then raise exception 'Falta la ubicacion "Para Analizar".'; end if;
  end if;

  -- avisar (sin bloquear) si devuelve mas de lo que tiene online
  v_canon := "GP2".to_canonical(p_comp_id, p_cantidad, v_unidad);
  select cantidad into v_online from inventario
   where componente_id=p_comp_id and ubicacion_id=v_ubic_orig;
  if coalesce(v_online,0) < v_canon then
    v_aviso := 'OJO: '||v_tall||' tiene online '||coalesce(round(v_online,2)::text,'0')||
      ' de '||coalesce(v_cod,'?')||' y devuelve '||round(v_canon,2)||' (queda negativo).';
  end if;

  -- El movimiento es la devolucion entera: tallerista = origen, destino = sector o Para
  -- Analizar, motivo = nota. No hay tabla cabecera (2026-09-05).
  insert into movimiento(fecha, tipo_mov, comp_id, ubic_origen_id, ubic_destino_id,
                         cantidad, unidad_origen, unidad_destino, nota)
  values (coalesce(p_fecha,now()), 'devolucion_tallerista', p_comp_id, v_ubic_orig, v_ubic_dest,
          p_cantidad, v_unidad, v_unidad, nullif(trim(coalesce(p_motivo,'')),''))
  returning id into v_mov;

  return jsonb_build_object('ok',true,'id',v_mov,'movimiento_id',v_mov,'tallerista',v_tall,
    'codigo',v_cod,'destino',p_destino,'cantidad',p_cantidad,'unidad',v_unidad,'aviso',v_aviso);
end $function$
;

-- ---------- crear_entrega_prov_at ----------
CREATE OR REPLACE FUNCTION "GP2".crear_entrega_prov_at(p_prov_at_id bigint, p_cod_art text, p_cajas integer, p_remito text DEFAULT NULL::text, p_fecha date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
declare v_desc text; v_id bigint; v_fecha date;
begin
  if coalesce(p_cajas,0) <= 0 then
    raise exception 'La cantidad de cajas tiene que ser mayor a cero';
  end if;
  if not exists (select 1 from proveedor_at where id = p_prov_at_id) then
    raise exception 'El proveedor % no existe', p_prov_at_id;
  end if;

  -- La descripcion se toma del maestro, no de lo que mande la pantalla: si
  -- manana cambia ahi, no quedan entregas viejas con el nombre de antes.
  select a.descripcion into v_desc
    from articulo_prov_at a
   where a.proveedor_at_id = p_prov_at_id and a.cod_art = p_cod_art
   limit 1;
  if v_desc is null then
    raise exception 'El articulo % no esta asignado a ese proveedor', p_cod_art;
  end if;

  v_fecha := coalesce(p_fecha, (now() at time zone 'America/Argentina/Buenos_Aires')::date);

  -- tipo_entrega (factura / remito_factura) es un dato del programa viejo que la pantalla no
  -- pregunta: queda null (antes se escribia 'entrega', una palabra que no existia).
  insert into entrega_prov_at
    (proveedor_at_id, cod_art, descripcion, cantidad_cajas, remito,
     fecha_rto, dia_mes, tipo_entrega)
  values
    (p_prov_at_id, p_cod_art, v_desc, p_cajas,
     nullif(btrim(coalesce(p_remito,'')),''),
     v_fecha, to_char(v_fecha, 'DD/MM/YY'), null)
  returning id into v_id;

  return jsonb_build_object('ok', true, 'id', v_id, 'descripcion', v_desc);
end $function$
;

-- ---------- crear_entrega_ps ----------
CREATE OR REPLACE FUNCTION "GP2".crear_entrega_ps(p_ps_id bigint, p_comp_sc_id bigint, p_comp_sp_id bigint, p_kg numeric, p_fecha timestamp with time zone DEFAULT now(), p_cajones numeric DEFAULT NULL::numeric, p_faltante boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
declare v_ps bigint; v_dest bigint; v_sec_id bigint; v_secsp text; v_umsp text;
        v_codsp text; v_codsc text; v_cons numeric; v_id bigint;
begin
  if p_kg is null or p_kg <= 0 then raise exception 'Los kg deben ser mayores a 0'; end if;
  select c.sector_id, s.nombre, c.codigo, c.unidad_medida into v_sec_id, v_secsp, v_codsp, v_umsp
    from componente c join sector s on s.id=c.sector_id where c.id=p_comp_sp_id;
  select codigo into v_codsc from componente where id=p_comp_sc_id;
  if v_secsp is null then raise exception 'Componente SP % inexistente o sin sector', p_comp_sp_id; end if;
  if v_codsc is null then raise exception 'Componente SC % inexistente', p_comp_sc_id; end if;
  v_ps   := "GP2".ubic_de('proveedor_servicio', p_ps_id);
  v_dest := "GP2".ubic_de('sector', v_sec_id);
  if v_ps is null then raise exception 'No hay ubicación para el proveedor de servicio %', p_ps_id; end if;
  if v_dest is null then raise exception 'No hay ubicación para el sector % (id=%) del SP', v_secsp, v_sec_id; end if;
  -- cantidad de SP recibida, en la canonica de la SP; la SC consumida es la misma cantidad
  -- (1 a 1) expresada en esa misma dimension.
  v_cons := to_canonical(p_comp_sp_id, p_kg, 'kg');
  insert into movimiento(fecha,tipo_mov,comp_id,ubic_origen_id,ubic_destino_id,cantidad,unidad_origen,
                         comp_transformado_id,cantidad_transformada,unidad_destino,cajones,faltante)
  values (coalesce(p_fecha,now()),'entrega_ps',p_comp_sc_id,v_ps,v_dest,v_cons,
          case when lower(coalesce(v_umsp,'unidad'))='kg' then 'kg' else 'uni' end,
          p_comp_sp_id,p_kg,'kg',p_cajones,coalesce(p_faltante,false))
  returning id into v_id;
  return jsonb_build_object('ok',true,'id',v_id,'sc',v_codsc,'sp',v_codsp,'kg',p_kg,
    'consumo_canon',v_cons,'cajones',p_cajones,'faltante',coalesce(p_faltante,false));
end $function$
;

-- ---------- crear_entrega_tallerista ----------
CREATE OR REPLACE FUNCTION "GP2".crear_entrega_tallerista(p_tallerista_id bigint, p_comp_id bigint, p_cantidad numeric, p_unidad text DEFAULT 'uni'::text, p_fecha timestamp with time zone DEFAULT now(), p_descontar_bom boolean DEFAULT true, p_comp_entrada_id bigint DEFAULT NULL::bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
declare
  v_unidad            text    := lower(trim(coalesce(p_unidad, 'uni')));
  v_tall_nombre       text;
  v_ubic_tall         bigint;
  v_ubic_origen       bigint;
  v_ubic_destino      bigint;
  v_destino_nom       text;
  v_cod               text;
  v_sector_id         bigint;
  v_sector_nom        text;
  v_qty_canon         numeric;
  v_mov_id            bigint;
  v_hijo_mov          bigint;
  v_hijos             jsonb   := '[]'::jsonb;
  v_es_armado         boolean := false;
  v_es_transformacion boolean := false;
  v_comp_entrada_cod  text;
  v_consumo_mov       bigint;
  r                   record;
  v_hijo_um           text;
  v_hijo_qty          numeric;
begin
  if p_cantidad is null or p_cantidad <= 0 then
    raise exception 'La cantidad debe ser mayor a 0 (recibido: %).', coalesce(p_cantidad::text, 'null');
  end if;
  if v_unidad not in ('kg', 'uni') then
    raise exception 'Unidad invalida: "%". Debe ser "kg" o "uni".', coalesce(p_unidad, 'null');
  end if;

  select nombre into v_tall_nombre from tallerista where id = p_tallerista_id;
  if v_tall_nombre is null then
    raise exception 'Tallerista inexistente (id=%).', p_tallerista_id;
  end if;
  v_ubic_tall := "GP2".ubic_de('tallerista', p_tallerista_id);
  if v_ubic_tall is null then
    raise exception 'El tallerista "%" (id=%) no tiene ubicacion asociada.', v_tall_nombre, p_tallerista_id;
  end if;

  select c.codigo, c.sector_id, s.nombre into v_cod, v_sector_id, v_sector_nom
    from componente c left join sector s on s.id = c.sector_id
   where c.id = p_comp_id;
  if not found then
    raise exception 'Componente inexistente (id=%).', p_comp_id;
  end if;

  -- Destino: ubicacion del sector del componente.
  -- Articulos terminados (sector sin ubicacion propia) van a Virgilio (regla en ubic_de_componente).
  v_ubic_destino := "GP2".ubic_de_componente(p_comp_id);
  if v_ubic_destino is null then
    raise exception 'No hay ubicacion destino para el componente "%" (sector %). Falta la ubicacion del sector o la de Virgilio.',
      coalesce(v_cod, '?'), coalesce(v_sector_nom, v_sector_id::text, 'sin sector');
  end if;
  select nombre into v_destino_nom from ubicacion where id = v_ubic_destino;

  -- Es armado si tiene partes en componente_bom y se pidio descontarlas.
  if p_descontar_bom then
    select exists(select 1 from componente_bom where componente_padre_id = p_comp_id)
      into v_es_armado;
  end if;

  -- Transformacion: tallerista recibio p_comp_entrada_id y entrega p_comp_id (distinto).
  -- Solo aplica para no-armados; los armados manejan sus insumos via BOM.
  v_es_transformacion := (p_comp_entrada_id is not null and not v_es_armado);

  -- Origen del movimiento principal:
  --   armado/transformacion -> null (el producto nace en la entrega)
  --   pass-through simple   -> tallerista (sale de su stock)
  v_ubic_origen := case
    when v_es_armado or v_es_transformacion then null
    else v_ubic_tall
  end;

  insert into movimiento(fecha, tipo_mov, comp_id, ubic_origen_id, ubic_destino_id,
                         cantidad, unidad_origen, unidad_destino)
  values (coalesce(p_fecha, now()), 'entrega_tallerista', p_comp_id,
          v_ubic_origen, v_ubic_destino, p_cantidad, v_unidad, v_unidad)
  returning id into v_mov_id;

  -- Para transformacion: registrar consumo del componente de entrada desde el tallerista.
  if v_es_transformacion then
    select codigo into v_comp_entrada_cod from componente where id = p_comp_entrada_id;
    if not found then
      raise exception 'Componente entrada inexistente (p_comp_entrada_id=%).', p_comp_entrada_id;
    end if;
    insert into movimiento(fecha, tipo_mov, comp_id, ubic_origen_id, ubic_destino_id,
                           cantidad, unidad_origen, unidad_destino)
    values (coalesce(p_fecha, now()), 'consumo_tall', p_comp_entrada_id,
            v_ubic_tall, null, p_cantidad, v_unidad, v_unidad)
    returning id into v_consumo_mov;
    v_hijos := jsonb_build_array(jsonb_build_object(
      'movimiento_id', v_consumo_mov,
      'componente_id', p_comp_entrada_id,
      'codigo',        v_comp_entrada_cod,
      'cantidad',      p_cantidad,
      'unidad',        v_unidad
    ));
  end if;

  -- Para armados: descontar cada componente del BOM desde el tallerista.
  if v_es_armado then
    v_qty_canon := to_canonical(p_comp_id, p_cantidad, v_unidad);
    for r in
      select b.componente_hijo_id as hijo_id, b.cantidad as por_unidad,
             c.codigo as hijo_cod, c.unidad_medida as hijo_um
        from componente_bom b join componente c on c.id = b.componente_hijo_id
       where b.componente_padre_id = p_comp_id
    loop
      v_hijo_um  := case when lower(coalesce(r.hijo_um, 'unidad')) = 'kg' then 'kg' else 'uni' end;
      v_hijo_qty := v_qty_canon * coalesce(r.por_unidad, 0);
      if v_hijo_qty > 0 then
        insert into movimiento(fecha, tipo_mov, comp_id, ubic_origen_id, ubic_destino_id,
                               cantidad, unidad_origen, unidad_destino)
        values (coalesce(p_fecha, now()), 'consumo_tall', r.hijo_id, v_ubic_tall, null,
                v_hijo_qty, v_hijo_um, v_hijo_um)
        returning id into v_hijo_mov;
        v_hijos := v_hijos || jsonb_build_object(
          'movimiento_id', v_hijo_mov,
          'componente_id', r.hijo_id,
          'codigo',        r.hijo_cod,
          'cantidad',      v_hijo_qty,
          'unidad',        v_hijo_um);
      end if;
    end loop;
  end if;

  return jsonb_build_object(
    'ok',                    true,
    'id',                    v_mov_id,
    'tallerista',            v_tall_nombre,
    'codigo',                v_cod,
    'es_armado',             v_es_armado,
    'es_transformacion',     v_es_transformacion,
    'comp_entrada_id',       p_comp_entrada_id,
    'destino',               v_destino_nom,
    'ubic_origen_id',        v_ubic_origen,
    'ubic_destino_id',       v_ubic_destino,
    'cantidad',              p_cantidad,
    'unidad',                v_unidad,
    'componentes_descontados', v_hijos
  );
end;
$function$
;

-- ---------- crear_envio_prov_at ----------
CREATE OR REPLACE FUNCTION "GP2".crear_envio_prov_at(p_prov_at_id bigint, p_comp_id bigint, p_cantidad numeric, p_unidad text, p_fecha timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
declare v_ubic_o bigint; v_ubic_d bigint; v_sector int; v_mov bigint;
        v_unidad text := lower(trim(coalesce(p_unidad,'uni')));
begin
  if coalesce(p_cantidad,0) <= 0 then raise exception 'Cantidad invalida'; end if;
  if v_unidad not in ('kg','uni') then
    raise exception 'Unidad invalida: "%". Debe ser "kg" o "uni".', coalesce(p_unidad,'null');
  end if;
  select sector_id into v_sector from componente where id = p_comp_id;
  if v_sector is null then raise exception 'Componente % no existe', p_comp_id; end if;
  if v_sector not in (10, 11) then
    raise exception 'Solo se envia carton (sector 10) o cajas (sector 11) a los Prov AT';
  end if;
  v_ubic_o := "GP2".ubic_de('sector', v_sector);
  v_ubic_d := "GP2".ubic_de('proveedor_at', p_prov_at_id);
  if v_ubic_o is null then raise exception 'No hay ubicacion para el sector % del componente %', v_sector, p_comp_id; end if;
  if v_ubic_d is null then raise exception 'El Prov AT % no tiene ubicacion', p_prov_at_id; end if;

  insert into movimiento (fecha, tipo_mov, comp_id, ubic_origen_id, ubic_destino_id, cantidad, unidad_origen, unidad_destino)
  values (coalesce(p_fecha, now()), 'envio_prov_at', p_comp_id, v_ubic_o, v_ubic_d, p_cantidad,
          v_unidad, v_unidad)
  returning id into v_mov;
  return jsonb_build_object('ok', true, 'movimiento_id', v_mov);
end $function$
;

-- ---------- crear_envio_ps ----------
CREATE OR REPLACE FUNCTION "GP2".crear_envio_ps(p_ps_id bigint, p_comp_sc_id bigint, p_cantidad numeric, p_unidad text, p_fecha timestamp with time zone DEFAULT now(), p_cajones numeric DEFAULT NULL::numeric, p_faltante boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
declare v_orig bigint; v_dest bigint; v_sec_id bigint; v_sec text; v_cod text; v_id bigint;
begin
  if p_cantidad is null or p_cantidad <= 0 then
    raise exception 'La cantidad debe ser mayor a 0';
  end if;
  if lower(coalesce(p_unidad,'')) not in ('kg','uni') then
    raise exception 'Unidad inválida (kg o uni)';
  end if;
  select c.sector_id, s.nombre, c.codigo into v_sec_id, v_sec, v_cod
    from componente c join sector s on s.id=c.sector_id where c.id=p_comp_sc_id;
  if v_sec is null then raise exception 'Componente % inexistente o sin sector', p_comp_sc_id; end if;
  v_orig := "GP2".ubic_de('sector', v_sec_id);
  v_dest := "GP2".ubic_de('proveedor_servicio', p_ps_id);
  if v_orig is null then raise exception 'No hay ubicación para el sector % (id=%)', v_sec, v_sec_id; end if;
  if v_dest is null then raise exception 'No hay ubicación para el proveedor de servicio %', p_ps_id; end if;
  insert into movimiento(fecha,tipo_mov,comp_id,ubic_origen_id,ubic_destino_id,cantidad,unidad_origen,cajones,faltante)
  values (coalesce(p_fecha,now()),'envio_ps',p_comp_sc_id,v_orig,v_dest,p_cantidad,lower(p_unidad),p_cajones,coalesce(p_faltante,false))
  returning id into v_id;
  return jsonb_build_object('ok',true,'id',v_id,'parte',v_cod,'sector',v_sec,
    'origen',v_orig,'destino',v_dest,'cantidad',p_cantidad,'unidad',lower(p_unidad),
    'cajones',p_cajones,'faltante',coalesce(p_faltante,false));
end $function$
;

-- ---------- crear_envio_tallerista ----------
CREATE OR REPLACE FUNCTION "GP2".crear_envio_tallerista(p_tallerista_id bigint, p_comp_id bigint, p_cantidad numeric, p_unidad text, p_fecha timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
declare
  v_tall_nombre   text;
  v_sector_nombre text;
  v_sector_id     bigint;
  v_cod           text;
  v_ubic_origen   bigint;
  v_ubic_destino  bigint;
  v_new_id        bigint;
  v_unidad        text := lower(trim(coalesce(p_unidad,'')));
begin
  if p_cantidad is null or p_cantidad <= 0 then
    raise exception 'La cantidad debe ser mayor a 0 (recibido: %).', coalesce(p_cantidad::text,'null');
  end if;
  if v_unidad not in ('kg','uni') then
    raise exception 'Unidad invalida: "%". Debe ser "kg" o "uni".', coalesce(p_unidad,'null');
  end if;

  select nombre into v_tall_nombre from tallerista where id = p_tallerista_id;
  if v_tall_nombre is null then
    raise exception 'Tallerista inexistente (id=%).', p_tallerista_id;
  end if;

  v_ubic_destino := "GP2".ubic_de('tallerista', p_tallerista_id);
  if v_ubic_destino is null then
    raise exception 'El tallerista "%" (id=%) no tiene ubicacion asociada (tipo=tallerista).', v_tall_nombre, p_tallerista_id;
  end if;

  select c.codigo, c.sector_id, s.nombre into v_cod, v_sector_id, v_sector_nombre
    from componente c left join sector s on s.id = c.sector_id
   where c.id = p_comp_id;
  if not found then
    raise exception 'Componente inexistente (id=%).', p_comp_id;
  end if;
  if v_sector_id is null then
    raise exception 'El componente "%" (id=%) no tiene sector asignado; no se puede resolver el origen.', coalesce(v_cod,'?'), p_comp_id;
  end if;

  v_ubic_origen := "GP2".ubic_de('sector', v_sector_id);
  if v_ubic_origen is null then
    raise exception 'No existe ubicacion de sector para "%" (componente % / id=%).', coalesce(v_sector_nombre, v_sector_id::text), coalesce(v_cod,'?'), p_comp_id;
  end if;

  insert into movimiento(
    fecha, tipo_mov, comp_id, ubic_origen_id, ubic_destino_id, cantidad, unidad_origen, unidad_destino
  ) values (
    coalesce(p_fecha, now()), 'envio_tallerista', p_comp_id, v_ubic_origen, v_ubic_destino, p_cantidad, v_unidad, v_unidad
  ) returning id into v_new_id;

  return jsonb_build_object(
    'ok', true, 'id', v_new_id, 'tallerista', v_tall_nombre, 'codigo', v_cod,
    'sector', v_sector_nombre, 'ubic_origen_id', v_ubic_origen, 'ubic_destino_id', v_ubic_destino,
    'cantidad', p_cantidad, 'unidad', v_unidad
  );
end;
$function$
;

-- ---------- crear_oc ----------
CREATE OR REPLACE FUNCTION "GP2".crear_oc(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
declare
  v_oc bigint; v_num int; it jsonb; v_n int := 0;
  v_prov text; v_nota_orig text; v_fent date;
  v_u text; v_cant numeric; v_kg_x_paq numeric; v_kg_x_uni_it numeric; v_sec_it bigint;
  -- OC gemela al proveedor de la materia prima (PS hibrido)
  v_mp_id bigint; v_pct numeric; v_kg_producto numeric := 0;
  v_mp_codigo text; v_mp_prov text; v_mp_rubro text; v_kg_mp numeric;
  v_oc_mp bigint; v_num_mp int;
begin
  v_prov := nullif(p->>'proveedor','');
  v_nota_orig := nullif(p->>'nota','');
  v_fent := nullif(p->>'fecha_entrega','')::date;
  -- Charcas se pide en PAQUETES de v_kg_x_paq kg (parametro charcas_kg_x_paquete) y la OC se
  -- guarda en kg: la recepcion (kg de balanza) cruza directo y la OC gemela suma kg.
  v_kg_x_paq := coalesce((select valor from parametro where clave='charcas_kg_x_paquete'), 10);
  -- PS HIBRIDO: la OC a un proveedor de servicio que procesa una materia prima nuestra (Charcas
  -- corta el alambre de Altrak, Eclipse estampa la chapa 430 de Aperam) dispara la OC gemela al
  -- proveedor de esa MP. desperdicio_pct es % DE LA CHAPA (materia prima), asi que la chapa a
  -- comprar = kg de producto pedido / (1 - desperdicio_pct/100). Todo sale de proveedor_servicio
  -- (hibrido, mp_componente_id, desperdicio_pct) y del componente MP; ningun proveedor por nombre.
  select ps.mp_componente_id, ps.desperdicio_pct into v_mp_id, v_pct
    from proveedor_servicio ps where ps.hibrido and ps.nombre = v_prov;
  if v_pct is not null and (v_pct < 0 or v_pct >= 100) then v_pct := 0; end if;  -- guard division

  select coalesce(max(numero),0)+1 into v_num from orden_compra;
  insert into orden_compra (numero, proveedor, rubro, nota, creado_por, fecha_entrega_estimada)
  values (v_num, v_prov, nullif(p->>'rubro',''), v_nota_orig, nullif(p->>'usuario',''), v_fent)
  returning id into v_oc;

  for it in select * from jsonb_array_elements(coalesce(p->'items','[]'::jsonb)) loop
    if coalesce((it->>'cantidad')::numeric,0) > 0 then
      -- unidad del item: kg o uni (vocabulario cerrado, CHECK en orden_compra_item). 'paq' (Charcas)
      -- se convierte a kg; 'unidad' o cualquier otra cosa es uni.
      v_u := lower(coalesce(nullif(it->>'unidad',''),'uni'));
      v_cant := (it->>'cantidad')::numeric;
      if v_u = 'paq' then
        v_cant := v_cant * v_kg_x_paq; v_u := 'kg';
      elsif v_u <> 'kg' then
        v_u := 'uni';
      end if;
      -- precio: el que mande el item pisa al de la lista. La moneda acompaña al
      -- precio elegido (si el item trae precio y no dice moneda, se asume la de
      -- la lista, y si tampoco hay lista, USD).
      insert into orden_compra_item (oc_id, componente_id, cantidad, unidad, precio_uni, moneda)
      select v_oc, (it->>'comp_id')::bigint, v_cant, v_u,
             coalesce(nullif(it->>'precio','')::numeric, pv.precio),
             case
               when nullif(it->>'precio','') is not null then
                 case when upper(coalesce(nullif(it->>'moneda',''), pv.moneda, 'USD')) like '%US%'
                      then 'USD' else 'ARS' end
               when pv.precio is null then null
               when upper(coalesce(pv.moneda,'USD')) like '%US%' then 'USD' else 'ARS' end
             end
      from (select 1) x
      left join lateral (
        select case when pp.precio_por_kg then pp.precio * cc.kg_x_uni else pp.precio end precio, pp.moneda
        from precio_proveedor pp join componente cc on cc.id = pp.componente_id
        where pp.componente_id = (it->>'comp_id')::bigint and pp.precio is not null
        order by pp.fecha_lista desc nulls last, pp.id desc limit 1
      ) pv on true;
      v_n := v_n + 1;

      -- kg de producto pedido al PS hibrido (lo que en kg va en kg, lo que va en uni por kg_x_uni).
      -- Para la OC gemela SOLO cuenta lo que el PS nos PRODUCE con nuestra materia prima. Un PS
      -- hibrido puede ademas VENDERNOS insumos (Charcas nos vende las bombillas BOM10/EP10/LLF8)
      -- y esos no consumen alambre nuestro: si contaran, una OC de bombillas a Charcas dispararia
      -- una OC de alambre a Altrak que nadie pidio. Se distinguen por el sector: lo que el PS
      -- produce no vive en un sector de insumo (2026-09-08).
      if v_mp_id is not null then
        select sector_id, kg_x_uni into v_sec_it, v_kg_x_uni_it
          from componente where id=(it->>'comp_id')::bigint;
        if not "GP2"._es_sector_insumo(v_sec_it) then
          if v_u = 'kg' then
            v_kg_producto := v_kg_producto + v_cant;
          else
            v_kg_producto := v_kg_producto + v_cant * coalesce(v_kg_x_uni_it, 0);
          end if;
        end if;
      end if;
    end if;
  end loop;
  if v_n = 0 then raise exception 'La OC no tiene items'; end if;

  -- OC GEMELA al proveedor de la materia prima
  if v_mp_id is not null and v_kg_producto > 0 then
    select c.codigo, c.proveedor, coalesce(pi.rubro, s.nombre)
      into v_mp_codigo, v_mp_prov, v_mp_rubro
      from componente c
      left join proveedor_insumo pi on pi.nombre = c.proveedor
      left join sector s on s.id = c.sector_id
     where c.id = v_mp_id;
    if v_mp_prov is null then
      raise exception 'La materia prima % del PS % no tiene proveedor: no se puede crear la OC gemela', v_mp_codigo, v_prov;
    end if;
    v_kg_mp := round(v_kg_producto / (1 - coalesce(v_pct,0)/100), 2);

    select coalesce(max(numero),0)+1 into v_num_mp from orden_compra;
    insert into orden_compra (numero, proveedor, rubro, nota, creado_por, fecha_entrega_estimada)
    values (v_num_mp, v_mp_prov, v_mp_rubro,
            'OC gemela de OC N° '||v_num||' ('||v_prov||'). Kg de '||v_mp_codigo||' = kg de producto pedido / (1 - '||coalesce(v_pct,0)/100||').',
            nullif(p->>'usuario',''), v_fent)
    returning id into v_oc_mp;

    insert into orden_compra_item (oc_id, componente_id, cantidad, unidad, precio_uni, moneda)
    select v_oc_mp, v_mp_id, v_kg_mp, 'kg', pv.precio,
           case when pv.precio is null then null
                when upper(coalesce(pv.moneda,'USD')) like '%US%' then 'USD' else 'ARS' end
    from (select 1) x
    left join lateral (
      select case when pp.precio_por_kg then pp.precio * cc.kg_x_uni else pp.precio end precio, pp.moneda
      from precio_proveedor pp join componente cc on cc.id = pp.componente_id
      where pp.componente_id = v_mp_id and pp.precio is not null
      order by pp.fecha_lista desc nulls last, pp.id desc limit 1
    ) pv on true;

    update orden_compra
       set nota = coalesce(v_nota_orig || E'\n', '') ||
                  'OC gemela a '||v_mp_prov||' N° '||v_num_mp||' con '||v_kg_mp||' kg de '||v_mp_codigo||'.'
     where id = v_oc;
  end if;

  return jsonb_build_object(
    'ok', true, 'oc_id', v_oc, 'numero', v_num, 'items', v_n,
    'fecha_entrega_estimada', v_fent,
    'oc_gemela', case when v_oc_mp is not null
      then jsonb_build_object('oc_id', v_oc_mp, 'numero', v_num_mp, 'proveedor', v_mp_prov,
                              'componente', v_mp_codigo, 'kg', v_kg_mp)
      else null end
  );
end $function$
;

-- ---------- crear_recepcion_insumo ----------
CREATE OR REPLACE FUNCTION "GP2".crear_recepcion_insumo(p_comp_id bigint, p_proveedor text, p_cantidad numeric, p_unidad text, p_remito text DEFAULT NULL::text, p_fecha timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
declare v_sec bigint; v_um text; v_ubic bigint; v_u text; v_movid bigint; v_recid bigint; v_f timestamptz; v_oc jsonb;
begin
  if p_cantidad is null or p_cantidad<=0 then raise exception 'La cantidad debe ser mayor a 0'; end if;
  select sector_id, unidad_medida into v_sec, v_um from "GP2".componente where id=p_comp_id;
  if v_sec is null then raise exception 'El insumo no existe'; end if;
  if not "GP2"._es_sector_insumo(v_sec) then raise exception 'El componente % no es un insumo (sector no comprable)', p_comp_id; end if;
  v_ubic := "GP2".ubic_de('sector', v_sec);
  if v_ubic is null then raise exception 'No hay ubicacion para el sector del insumo'; end if;
  v_u := case when lower(coalesce(nullif(p_unidad,''), v_um, 'uni'))='kg' then 'kg' else 'uni' end;
  v_f := coalesce(p_fecha, now());
  insert into "GP2".movimiento(fecha,tipo_mov,comp_id,ubic_origen_id,ubic_destino_id,cantidad,unidad_origen,unidad_destino)
  values(v_f,'compra',p_comp_id,null,v_ubic,p_cantidad,v_u,v_u) returning id into v_movid;
  insert into "GP2".recepcion_insumo(fecha,componente_id,proveedor,remito,cantidad,unidad,movimiento_id)
  values(v_f,p_comp_id,nullif(btrim(coalesce(p_proveedor,'')),''),nullif(btrim(coalesce(p_remito,'')),''),p_cantidad,v_u,v_movid)
  returning id into v_recid;
  v_oc := "GP2"._aplicar_recepcion_a_oc(p_comp_id, p_cantidad, v_u);
  return jsonb_build_object('ok',true,'recepcion_id',v_recid,'movimiento_id',v_movid,'unidad',v_u,'oc_cruzada',v_oc);
end $function$
;

-- ---------- descontrolar_recepcion ----------
CREATE OR REPLACE FUNCTION "GP2".descontrolar_recepcion(p_recepcion_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
declare
  r recepcion_insumo%rowtype;
  v_decl numeric;
begin
  select * into r from recepcion_insumo where id = p_recepcion_id;
  if not found then
    raise exception 'Recepción % no existe', p_recepcion_id using errcode = 'P0002';
  end if;
  if not coalesce(r.controlado, false) then
    return jsonb_build_object('recepcion_id', p_recepcion_id, 'ya_estaba', true, 'cantidad', r.cantidad);
  end if;
  -- vuelve a lo declarado en el remito (la primera vez que se controlo quedo guardado)
  v_decl := coalesce(r.cantidad_declarada, r.cantidad);

  update recepcion_insumo
     set controlado = false, controlado_en = null, controlado_por = null,
         base = null, pisos = null, sueltas = null, paquetes = null, uni_x_paq = null,
         cantidad = v_decl
   where id = p_recepcion_id;

  -- el movimiento tambien vuelve al declarado: los triggers recalculan el inventario
  if r.movimiento_id is not null and v_decl <> r.cantidad then
    update movimiento set cantidad = v_decl where id = r.movimiento_id;
  end if;

  return jsonb_build_object('recepcion_id', p_recepcion_id, 'movimiento_id', r.movimiento_id,
                            'cantidad', v_decl, 'antes', r.cantidad);
end $function$
;

-- ---------- despiece_verif_bundle ----------
CREATE OR REPLACE FUNCTION "GP2".despiece_verif_bundle()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
with sec_rel as (
  -- sector "relevante para peso": tiene al menos un componente con kg cargado
  -- (mismo criterio que usaba verifmadres_bundle para el filtro por defecto)
  select distinct sector_id from "GP2".componente
  where kg_x_uni is not null and kg_x_uni <> 0
),
pasos as (
  select rp.ruta_id, rp.orden o, rp.tipo_paso tp,
    case rp.tipo_paso
      when 'matriz' then m.n_matriz
      when 'proveedor_servicio' then pv.nombre
      when 'tallerista' then t.nombre
      else null end as actor,
    case rp.tipo_paso
      when 'matriz' then m.descripcion
      when 'proveedor_servicio' then pv.proceso
      when 'tallerista' then 'tallerista'
      else null end as actor_desc,
    ce.codigo ce, ce.descripcion ce_d, se.tipo ce_sect,
    cs.codigo cs, cs.descripcion cs_d, sc.tipo cs_sect,
    ra.codigo paso_art
  from "GP2".ruta_paso rp
  left join "GP2".matriz m on m.id = rp.matriz_id
  left join "GP2".proveedor_servicio pv on pv.id = rp.proveedor_id
  left join "GP2".tallerista t on t.id = rp.tallerista_id
  left join "GP2".componente ce on ce.id = rp.comp_entrada_id
  left join "GP2".sector se on se.id = ce.sector_id
  left join "GP2".componente cs on cs.id = rp.comp_salida_id
  left join "GP2".sector sc on sc.id = cs.sector_id
  left join "GP2".ruta rr on rr.id = rp.ruta_id
  -- el articulo se muestra en el paso final (virgilio), y sale de la ruta
  left join "GP2".articulo ra on ra.id = rr.articulo_id and rp.tipo_paso = 'virgilio'
),
ruta_fleje as (
  -- fleje de la ruta = entrada del paso 1 de tipo 'ingreso' cuando es un componente del Sector Fleje (5)
  select distinct on (rp.ruta_id) rp.ruta_id, rp.comp_entrada_id fl
  from "GP2".ruta_paso rp
  join "GP2".componente c on c.id = rp.comp_entrada_id and c.sector_id = 5
  where rp.tipo_paso = 'ingreso' and rp.orden = 1
  order by rp.ruta_id, rp.orden
),
rutas_full as (
  select r.id, r.nombre nom, a.codigo art, a.familia fam,
    cf.codigo fleje, cf.descripcion fleje_desc,
    (select jsonb_agg(jsonb_build_object(
        'o',p.o,'tp',p.tp,'actor',p.actor,'actor_desc',p.actor_desc,
        'ce',p.ce,'ce_d',p.ce_d,'ce_sect',p.ce_sect,
        'cs',p.cs,'cs_d',p.cs_d,'cs_sect',p.cs_sect,'art',p.paso_art) order by p.o)
     from pasos p where p.ruta_id = r.id) pasos
  from "GP2".ruta r
  left join "GP2".articulo a on a.id = r.articulo_id
  left join ruta_fleje rf on rf.ruta_id = r.id
  left join "GP2".componente cf on cf.id = rf.fl
)
select jsonb_build_object(
  'sect', (select jsonb_object_agg(id::text, jsonb_build_object('tipo',tipo,'nom',nombre)) from "GP2".sector),
  'art', (
    select coalesce(jsonb_agg(
      jsonb_build_object(
        'id',  a.id,
        'cod', a.codigo,
        'fam', a.familia,
        'por', a.articulos_por_caja,
        'caja',a.componente_caja_id,
        -- demanda (uni/mes) = Est Madre (est_madre.proy_uni_mes), solo lectura
        'est', (select em.proy_uni_mes from "GP2".est_madre em
                where regexp_replace(em.cod,'^0+','') = regexp_replace(a.codigo,'^0+','') limit 1),
        'comp', coalesce((
          select jsonb_agg(jsonb_build_object(
            'cod', c.codigo,
            'd',   c.descripcion,
            's',   c.sector_id,
            'um',  c.unidad_medida,
            'q',   ac.cantidad,
            'kg',  c.kg_x_uni,
            'uxc', c.uni_x_cajon,
            'fkg', ((c.kg_x_uni is null or c.kg_x_uni = 0)
                    and c.sector_id in (select sector_id from sec_rel)),
            'fuxc',((c.uni_x_cajon is null or c.uni_x_cajon = 0)
                    and c.sector_id in (select sector_id from sec_rel))
          ) order by c.sector_id nulls last, c.codigo)
          from "GP2".articulo_componente ac
          join "GP2".componente c on c.id = ac.componente_id
          where ac.articulo_id = a.id
        ), '[]'::jsonb)
      ) order by a.codigo
    ), '[]'::jsonb)
    from "GP2".articulo a
  ),
  'rutas', (select coalesce(jsonb_agg(jsonb_build_object(
       'id',id,'nom',nom,'art',art,'fam',fam,'fleje',fleje,'fleje_desc',fleje_desc,'pasos',pasos)
       order by art nulls last, id), '[]'::jsonb) from rutas_full),
  'confirmadas', (
    select coalesce(jsonb_agg(jsonb_build_object(
      'firma',firma,'articulo',articulo,'fleje',fleje,
      'por',usuario,'en',en)),
    '[]'::jsonb) from "GP2".ruta_revision where estado = 'confirmada'
  ),
  'problemas', (
    select coalesce(jsonb_agg(jsonb_build_object(
      'id',id,'firma',firma,'articulo',articulo,'fleje',fleje,
      'problema',problema,'estado',estado,
      'por',usuario,'en',en,'resuelto_en',resuelto_en)
      order by en desc),
    '[]'::jsonb) from "GP2".ruta_revision where estado <> 'confirmada'
  ),
  'madres', (
    -- resumen GLOBAL de datos faltantes (todos los componentes de sectores con
    -- peso, esten o no en una receta): la vista de conjunto que daba VerifMadres
    select jsonb_build_object(
      'total_comp', count(*),
      'sin_kg', count(*) filter (where c.kg_x_uni is null or c.kg_x_uni = 0),
      'sin_uxc', count(*) filter (where c.uni_x_cajon is null or c.uni_x_cajon = 0)
    )
    from "GP2".componente c
    where c.sector_id in (select sector_id from sec_rel)
  )
);
$function$
;

-- ---------- devoluciones_tallerista_bundle ----------
CREATE OR REPLACE FUNCTION "GP2".devoluciones_tallerista_bundle()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
select jsonb_build_object(
  'talleristas', (select coalesce(jsonb_agg(jsonb_build_object('id',t.id,'nombre',t.nombre) order by t.nombre),'[]'::jsonb)
    from tallerista t),
  -- lo que cada tallerista tiene online (posiciones <> 0): de ahi elige que devolver
  'online', (select coalesce(jsonb_agg(jsonb_build_object(
      'tall_id',u.ref_id,'comp_id',c.id,'codigo',c.codigo,'descripcion',c.descripcion,
      'sector',s.nombre,'cantidad',i.cantidad,'um',c.unidad_medida,
      'kg_x_uni',c.kg_x_uni,'uni_x_cajon',c.uni_x_cajon) order by c.codigo),'[]'::jsonb)
    from inventario i
    join ubicacion u on u.id=i.ubicacion_id and u.tipo='tallerista'
    join componente c on c.id=i.componente_id
    left join sector s on s.id=c.sector_id
    where i.cantidad <> 0),
  -- stock apartado en "Para Analizar"
  'analizar', (select coalesce(jsonb_agg(jsonb_build_object(
      'comp_id',c.id,'codigo',c.codigo,'descripcion',c.descripcion,'cantidad',i.cantidad,
      'um',c.unidad_medida) order by c.codigo),'[]'::jsonb)
    from inventario i
    join ubicacion u on u.id=i.ubicacion_id and u.tipo='analisis'
    join componente c on c.id=i.componente_id
    where i.cantidad <> 0),
  -- ultimas devoluciones: salen del ledger (tallerista = origen, destino = tipo de la
  -- ubicacion destino, motivo = nota). El tallerista se resuelve con ubic_de para respetar
  -- el deposito compartido (Carlos Aguirre guarda en la ubicacion de Pedernera).
  'ultimas', (select coalesce(jsonb_agg(jsonb_build_object(
      'fecha',m.fecha,'tallerista',t.nombre,'codigo',c.codigo,'cantidad',m.cantidad,
      'unidad',m.unidad_origen,
      'destino', case when ud.tipo = 'analisis' then 'analizar' else 'sector' end,
      'motivo',m.nota) order by m.fecha desc, m.id desc),'[]'::jsonb)
    from (select * from movimiento where tipo_mov = 'devolucion_tallerista' order by id desc limit 30) m
    join componente c on c.id=m.comp_id
    left join ubicacion ud on ud.id=m.ubic_destino_id
    left join lateral (select t.nombre from tallerista t
                        where "GP2".ubic_de('tallerista', t.id) = m.ubic_origen_id
                        order by t.id limit 1) t on true)
);
$function$
;

-- ---------- disruptivas_bundle ----------
CREATE OR REPLACE FUNCTION "GP2".disruptivas_bundle(p_desde date DEFAULT NULL::date, p_hasta date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
select jsonb_build_object(
  'empleados', coalesce((
    select jsonb_object_agg(legajo, nom)
    from (
      select legajo,
             (array_agg(nombre_empleado) filter (where nombre_empleado is not null and nombre_empleado <> ''))[1] nom
      from "GP2".produccion
      where legajo is not null and legajo <> ''
      group by legajo
    ) e
  ), '{}'::jsonb),
  'rows', coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', id,
      'Fecha', to_char(fecha, 'YYYY-MM-DD'),
      'Legajo', legajo,
      'Nombre_Empleado', nombre_empleado,
      'Matriz', matriz_raw,
      'Nombre_Matriz', nombre_matriz,
      'Uni', uni,
      'Segundos_Trabajados', segundos_trabajados,
      'Segundos_Historico', segundos_historico,
      'Segundos_Tiempo_Muerto', segundos_tiempo_muerto,
      'Tiempo_Historico', tiempo_historico,
      'Hora_Inicio', to_char(hora_inicio,'HH24:MI:SS'),
      'Hora_Fin', to_char(hora_fin,'HH24:MI:SS'),
      'Premio', premio,
      'Anular_Tiempo', anular_tiempo,
      'Revisado', revisado
    ) order by matriz_raw, fecha desc)
    from "GP2".produccion
    where (eliminar is null or eliminar <> 'S')
      and (revisado is null or revisado = false)
      and (anular_tiempo is null or anular_tiempo = false)
      and matriz_raw ~ '^\d+\w*$'
      and coalesce(legajo,'') <> '1'
      and matriz_raw not in ('501','502','252')
      and coalesce(tiempo_historico,0) > 0
      and ((premio > 5 and premio < 9.5) or premio < -5)
      and (p_desde is null or fecha >= p_desde)
      and (p_hasta is null or fecha < (p_hasta + 1))
  ), '[]'::jsonb)
);
$function$
;

-- ---------- empleado_activar ----------
CREATE OR REPLACE FUNCTION "GP2".empleado_activar(p_id bigint, p_activo boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
begin
  update empleado set activo = p_activo where id = p_id;
  if not found then raise exception 'No existe el operario %.', p_id; end if;
  return jsonb_build_object('ok', true, 'id', p_id, 'activo', p_activo);
end $function$
;

-- ---------- empleado_guardar ----------
CREATE OR REPLACE FUNCTION "GP2".empleado_guardar(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
declare v_id bigint; v_legajo text; v_nombre text; v_tipo text; v_hora time; v_activo boolean;
begin
  v_legajo := btrim(coalesce(p->>'legajo',''));
  v_nombre := btrim(coalesce(p->>'nombre',''));
  if v_legajo = '' then raise exception 'Falta el legajo.'; end if;
  if v_nombre = '' then raise exception 'Falta el nombre.'; end if;

  v_id     := nullif(btrim(coalesce(p->>'id','')),'')::bigint;
  v_tipo   := nullif(btrim(coalesce(p->>'tipo','')),'');
  v_hora   := nullif(btrim(coalesce(p->>'hora_entrada','')),'')::time;
  v_activo := coalesce((p->>'activo')::boolean, true);

  -- el legajo es unico: es la llave que cruza con la produccion
  if exists (select 1 from empleado e
             where btrim(e.legajo) = v_legajo and (v_id is null or e.id <> v_id)) then
    raise exception 'Ya existe un operario con el legajo %.', v_legajo;
  end if;

  if v_id is null then
    insert into empleado (legajo, nombre, tipo, hora_entrada, activo)
    values (v_legajo, v_nombre, v_tipo, v_hora, v_activo)
    returning id into v_id;
  else
    update empleado
       set legajo = v_legajo, nombre = v_nombre, tipo = v_tipo,
           hora_entrada = v_hora, activo = v_activo
     where id = v_id;
    if not found then raise exception 'No existe el operario %.', v_id; end if;
  end if;

  return jsonb_build_object('ok', true, 'id', v_id);
end $function$
;

-- ---------- entregas_prov_at_bundle ----------
CREATE OR REPLACE FUNCTION "GP2".entregas_prov_at_bundle()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
select jsonb_build_object(
  'provs', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', p.id, 'nombre', p.nombre,
        'arts', (select count(*) from articulo_prov_at a
                  where a.proveedor_at_id = p.id and coalesce(a.activo,true))
      ) order by p.nombre), '[]'::jsonb)
    from proveedor_at p where coalesce(p.activo,true)),
  'arts', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', a.id, 'prov_id', a.proveedor_at_id, 'cod_art', a.cod_art,
        'descripcion', a.descripcion, 'n_caja', a.n_caja, 'marca', a.marca
      ) order by a.cod_art), '[]'::jsonb)
    from articulo_prov_at a where coalesce(a.activo,true)),
  'ultimas', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', e.id, 'fecha', coalesce(e.fecha_rto::text, e.dia_mes),
        'prov', p.nombre, 'cod_art', e.cod_art,
        'descripcion', e.descripcion, 'cajas', e.cantidad_cajas,
        'remito', e.remito, 'facturada', (e.numero_factura is not null)
      ) order by e.id desc), '[]'::jsonb)
    from (select * from entrega_prov_at order by id desc limit 40) e
    left join proveedor_at p on p.id = e.proveedor_at_id)
);
$function$
;

-- ---------- envios_prov_at_bundle ----------
CREATE OR REPLACE FUNCTION "GP2".envios_prov_at_bundle()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
select jsonb_build_object(
  'provs', (select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'nombre',p.nombre) order by p.nombre),'[]'::jsonb)
    from proveedor_at p where coalesce(p.activo,true)),
  'insumos', (select coalesce(jsonb_agg(jsonb_build_object(
      'comp_id',c.id,'codigo',c.codigo,'descripcion',c.descripcion,'sector_id',c.sector_id,
      'sector',s.nombre,'um',c.unidad_medida,
      'online',(select i.cantidad from inventario i
                 where i.componente_id=c.id and i.ubicacion_id="GP2".ubic_de('sector', c.sector_id) limit 1)
    ) order by c.sector_id, c.codigo),'[]'::jsonb)
    from componente c join sector s on s.id=c.sector_id where c.sector_id in (10,11)),
  'online_prov', (select coalesce(jsonb_agg(jsonb_build_object(
      'prov_id',u.ref_id,'comp_id',i.componente_id,'cantidad',i.cantidad)),'[]'::jsonb)
    from inventario i join ubicacion u on u.id=i.ubicacion_id
    where u.tipo='proveedor_at' and i.cantidad <> 0),
  'ultimos', (select coalesce(jsonb_agg(jsonb_build_object(
      'fecha',m.fecha,'comp',c.codigo,'cantidad',m.cantidad,'prov',p.nombre) order by m.id desc),'[]'::jsonb)
    from (select * from movimiento where tipo_mov='envio_prov_at' order by id desc limit 30) m
    join componente c on c.id=m.comp_id
    join ubicacion u on u.id=m.ubic_destino_id
    join proveedor_at p on p.id=u.ref_id),
  'paq', (select valor from parametro where clave='carton_uni_x_paquete'));
$function$
;

-- ---------- envios_ps_bundle ----------
CREATE OR REPLACE FUNCTION "GP2".envios_ps_bundle()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
with pares as (
  select distinct rp.proveedor_id, rp.comp_entrada_id sc_id, rp.comp_salida_id sp_id
  from ruta_paso rp
  join proveedor_servicio ps0 on ps0.id = rp.proveedor_id
  where rp.tipo_paso='proveedor_servicio' and rp.proveedor_id is not null
    and rp.comp_entrada_id is not null
    and not ps0.hibrido      -- los hibridos (Charcas/Eclipse) no reciben Envio
),
fila as (
  select p.proveedor_id, ps.proceso,
         sc.id sc_id, sc.codigo sc_cod, sc.descripcion sc_desc,
         sc.unidad_medida sc_um, sc.kg_x_uni sc_kgxuni, sc.uni_x_cajon sc_unixcaj,
         ssc.nombre sc_sector,
         sp.id sp_id, sp.codigo sp_cod, sp.descripcion sp_desc, sp.uni_x_cajon sp_unixcaj,
         (select i.cantidad from inventario i
           where i.componente_id=sc.id and i.ubicacion_id="GP2".ubic_de('sector', sc.sector_id) limit 1) online_sc,
         (select i.cantidad from inventario i where i.componente_id=sc.id
            and i.ubicacion_id="GP2".ubic_de('proveedor_servicio', p.proveedor_id) limit 1) online_ps,
         (select i.maximo from inventario i where i.componente_id=sc.id
            and i.ubicacion_id="GP2".ubic_de('proveedor_servicio', p.proveedor_id) limit 1) maximo,
         (select i.cantidad from inventario i
           where i.componente_id=sp.id and i.ubicacion_id="GP2".ubic_de('sector', sp.sector_id) limit 1) online_sp,
         (select i.maximo from inventario i
           where i.componente_id=sp.id and i.ubicacion_id="GP2".ubic_de('sector', sp.sector_id) limit 1) maximo_sp
  from pares p
  join proveedor_servicio ps on ps.id=p.proveedor_id
  join componente sc on sc.id=p.sc_id
  join sector ssc on ssc.id=sc.sector_id
  left join componente sp on sp.id=p.sp_id
)
select jsonb_build_object(
  'ps', (select coalesce(jsonb_agg(jsonb_build_object(
            'id',ps.id,'nombre',ps.nombre,'cod_prov',ps.cod_prov,'proceso',ps.proceso
          ) order by ps.nombre),'[]'::jsonb)
        from proveedor_servicio ps
        where exists (select 1 from pares p where p.proveedor_id=ps.id)),
  'partes', (select coalesce(jsonb_object_agg(proveedor_id::text, arr),'{}'::jsonb) from (
        select proveedor_id, jsonb_agg(jsonb_build_object(
          'sc_id',sc_id,'sc_cod',sc_cod,'sc_desc',sc_desc,'sc_sector',sc_sector,
          'sc_um',sc_um,'sc_kgxuni',sc_kgxuni,'sc_unixcaj',sc_unixcaj,
          'sp_id',sp_id,'sp_cod',sp_cod,'sp_desc',sp_desc,'sp_unixcaj',sp_unixcaj,
          'proceso',proceso,
          'online_sc',coalesce(online_sc,0),'online_ps',coalesce(online_ps,0),
          'online_sp',coalesce(online_sp,0),'maximo',maximo,'maximo_sp',maximo_sp
        ) order by sc_cod) arr
        from fila group by proveedor_id) z)
);
$function$
;

-- ---------- faltante_partes_tallerista_bundle ----------
CREATE OR REPLACE FUNCTION "GP2".faltante_partes_tallerista_bundle()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
with mov as (
  -- normaliza cada movimiento a: tallerista, componente, enviado/entregado en unidades + kg crudo
  select
    case when m.tipo_mov = 'envio_tallerista' then ud.ref_id else uo.ref_id end as tall_id,
    m.comp_id,
    m.tipo_mov,
    case
      when m.unidad_origen = 'uni' then m.cantidad
      when m.unidad_origen = 'kg' and coalesce(c.kg_x_uni,0) > 0 then m.cantidad / c.kg_x_uni
      else 0
    end as uni,
    case when m.unidad_origen = 'kg' then m.cantidad else 0 end as kg_raw,
    case when m.unidad_origen = 'kg' and coalesce(c.kg_x_uni,0) = 0 then 1 else 0 end as kg_sin_factor
  from movimiento m
  join componente c on c.id = m.comp_id
  left join ubicacion uo on uo.id = m.ubic_origen_id
  left join ubicacion ud on ud.id = m.ubic_destino_id
  where m.tipo_mov in ('envio_tallerista','entrega_tallerista','consumo_tall','devolucion_tallerista')
),
agg as (
  select
    mov.tall_id,
    mov.comp_id,
    sum(case when mov.tipo_mov = 'envio_tallerista'   then mov.uni else 0 end) as enviado,
    sum(case when mov.tipo_mov in ('entrega_tallerista','consumo_tall') then mov.uni else 0 end) as entregado,
    sum(case when mov.tipo_mov = 'devolucion_tallerista' then mov.uni else 0 end) as devuelto,
    sum(case when mov.tipo_mov = 'envio_tallerista'   then mov.kg_raw else 0 end) as enviado_kg,
    max(mov.kg_sin_factor) as kg_sin_factor
  from mov
  group by mov.tall_id, mov.comp_id
),
saldos as (
  -- saldo = enviado - entregado - devuelto = lo que el tallerista todavia tiene en su poder
  -- se excluye saldo exacto = 0 (nada pendiente). saldos negativos se muestran tal cual (ledger parcial).
  select
    a.*,
    round((a.enviado - a.entregado - a.devuelto)::numeric, 2) as saldo
  from agg a
),
partes as (
  select
    s.tall_id,
    jsonb_build_object(
      'comp_id', s.comp_id,
      'cod', c.codigo,
      'desc', c.descripcion,
      'sector', sec.nombre,
      'kg_x_uni', c.kg_x_uni,
      'enviado', round(s.enviado::numeric, 2),
      'entregado', round(s.entregado::numeric, 2),
      'devuelto', round(s.devuelto::numeric, 2),
      'saldo', s.saldo,
      'enviado_kg', round(s.enviado_kg::numeric, 3),
      'kg_sin_factor', (s.kg_sin_factor = 1)
    ) as parte,
    s.saldo as saldo_sort
  from saldos s
  join componente c on c.id = s.comp_id
  left join sector sec on sec.id = c.sector_id
  where s.saldo <> 0
),
por_tall as (
  select
    p.tall_id,
    -- ordenadas por saldo DESC: mayor pendiente en poder del tallerista primero
    jsonb_agg(p.parte order by p.saldo_sort desc) as partes,
    count(*) as n_partes,
    count(*) filter (where p.saldo_sort > 0) as n_saldo_pos,
    count(*) filter (where p.saldo_sort < 0) as n_saldo_neg,
    round(sum(p.saldo_sort),2)                              as tot_saldo,
    round(sum(p.saldo_sort) filter (where p.saldo_sort > 0),2) as tot_pendiente,
    round(sum(p.saldo_sort) filter (where p.saldo_sort < 0),2) as tot_negativo
  from partes p
  group by p.tall_id
)
select jsonb_build_object(
  'generado_en', now(),
  'talleristas', coalesce(jsonb_agg(
    jsonb_build_object(
      'id', t.id,
      'nombre', t.nombre,
      'cod_prov', t.cod_prov,
      'n_partes', pt.n_partes,
      'n_saldo_pos', pt.n_saldo_pos,
      'n_saldo_neg', pt.n_saldo_neg,
      'tot_saldo', pt.tot_saldo,
      'tot_pendiente', coalesce(pt.tot_pendiente,0),
      'tot_negativo', coalesce(pt.tot_negativo,0),
      'partes', pt.partes
    ) order by pt.tot_pendiente desc nulls last
  ), '[]'::jsonb)
)
from por_tall pt
join tallerista t on t.id = pt.tall_id;
$function$
;

-- ---------- faltantes_bundle ----------
CREATE OR REPLACE FUNCTION "GP2".faltantes_bundle()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
  with m as (select "GP2".movimientos_bundle() j)
  select j
      || jsonb_build_object('art', (select coalesce(jsonb_agg(v order by (v->>'id')::bigint), '[]'::jsonb)
                                     from jsonb_each(j->'art') e(k, v)))
      || jsonb_build_object('mat', (select coalesce(jsonb_object_agg(k, v || jsonb_build_object('primera', coalesce((v->>'primera')::boolean, false))), '{}'::jsonb)
                                     from jsonb_each(j->'mat') e(k, v)))
  from m
$function$
;

-- ---------- faltantes_estado_bundle ----------
CREATE OR REPLACE FUNCTION "GP2".faltantes_estado_bundle()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
select jsonb_build_object(
  'max_cajones', coalesce((select valor from parametro where clave = 'max_cajones_x_ubicacion'), 5),
  'umbral_cajones', coalesce((select valor from parametro where clave = 'faltante_cajones_umbral'), 1),
  'estado', coalesce((select jsonb_agg(jsonb_build_object(
      'comp_id', componente_id, 'cod', codigo, 'desc', descripcion,
      'sector_id', sector_id,
      'stock', stock_uni, 'uxc', uni_x_cajon, 'caj_stock', cajones_stock,
      'consumo_mes', consumo_uni_mes, 'maximo', maximo,
      'cob_dias', cobertura_dias, 'cob_llena_dias', cobertura_llena_dias,
      'falt_auto', faltante_auto, 'ubic_corta', ubicacion_corta
    ) order by sector_id, codigo) from v_faltante_estado), '[]'::jsonb),
  'marcas', coalesce((select jsonb_agg(jsonb_build_object(
      'id', f.id, 'comp_id', f.componente_id, 'cod', c.codigo, 'desc', c.descripcion,
      'sector_id', c.sector_id, 'origen', f.origen, 'nota', f.nota,
      'por', f.marcado_por, 'creado_en', f.creado_en
    ) order by f.creado_en desc)
    from faltante_marcado f join componente c on c.id = f.componente_id
    where f.resuelto_en is null), '[]'::jsonb),
  'pendientes_uxc', coalesce((select jsonb_agg(jsonb_build_object(
      'comp_id', c.id, 'cod', c.codigo, 'desc', c.descripcion, 'sector_id', c.sector_id
    ) order by c.sector_id, c.codigo)
    from componente c
    where c.sector_id in (1, 2) and not (c.uni_x_cajon > 0)), '[]'::jsonb)
);
$function$
;

-- ---------- fleje_detalle_upsert ----------
CREATE OR REPLACE FUNCTION "GP2".fleje_detalle_upsert(p_comp_id bigint, p_proveedor text, p_medida text, p_cons numeric, p_kgcaj numeric, p_cod_isis text, p_kg_uni_desp numeric DEFAULT NULL::numeric, p_parte text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
declare v_prov text := nullif(btrim(coalesce(p_proveedor,'')),'');
begin
  if not exists(select 1 from "GP2".componente where id=p_comp_id and sector_id=5) then
    raise exception 'El componente % no es un fleje (Sector Fleje)', p_comp_id;
  end if;
  if v_prov is not null and not exists (
       select 1 from "GP2".proveedor_insumo where nombre = v_prov and activo) then
    raise exception 'El proveedor "%" no existe. Dalo de alta primero en Inyectores (boton "+ Proveedor").', v_prov;
  end if;

  insert into "GP2".fleje_detalle(componente_id, medida_mm, cons_mensual, kg_x_cajon, cod_isis, kg_uni_desp, descripcion_parte, actualizado_en)
  values(p_comp_id, nullif(p_medida,''), p_cons, p_kgcaj, nullif(p_cod_isis,''), p_kg_uni_desp, nullif(p_parte,''), now())
  on conflict (componente_id) do update set
    medida_mm=nullif(p_medida,''), cons_mensual=p_cons,
    kg_x_cajon=p_kgcaj, cod_isis=nullif(p_cod_isis,''), kg_uni_desp=p_kg_uni_desp,
    descripcion_parte=nullif(p_parte,''), actualizado_en=now();

  -- el proveedor vive en componente: una sola fuente
  update "GP2".componente set proveedor = v_prov where id = p_comp_id;

  return jsonb_build_object('ok',true,'comp_id',p_comp_id);
end $function$
;

-- ---------- flejes_bundle ----------
CREATE OR REPLACE FUNCTION "GP2".flejes_bundle()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
  with ubf as (select "GP2".ubic_de('sector', 5) id)
  select coalesce(jsonb_agg(jsonb_build_object(
      'comp_id', c.id, 'codigo', c.codigo, 'descripcion', c.descripcion,
      'n_fleje', coalesce(d.n_fleje, (regexp_match(c.descripcion,'(\d+)'))[1]),
      'parte', d.descripcion_parte,
      'medida', d.medida_mm, 'proveedor', nullif(trim(c.proveedor),''),
      'cons', d.cons_mensual, 'kg_x_cajon', d.kg_x_cajon, 'cod_isis', d.cod_isis,
      'kg_uni_desp', d.kg_uni_desp,
      'stock', coalesce((select i.cantidad from "GP2".inventario i
                          where i.componente_id=c.id and i.ubicacion_id=(select id from ubf)),0),
      'minimo', (select i.minimo from "GP2".inventario i
                  where i.componente_id=c.id and i.ubicacion_id=(select id from ubf)),
      'maximo', (select i.maximo from "GP2".inventario i
                  where i.componente_id=c.id and i.ubicacion_id=(select id from ubf))
    ) order by c.codigo), '[]'::jsonb)
  from "GP2".componente c
  left join "GP2".fleje_detalle d on d.componente_id=c.id
  where c.sector_id=5;
$function$
;

-- ---------- fn_entregas_virgilio_espejo ----------
CREATE OR REPLACE FUNCTION "GP2".fn_entregas_virgilio_espejo()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
declare
  v_nom  text := upper(btrim(coalesce(NEW."Nombre_Tall",'')));
  v_tipo text; v_ref bigint;
  v_art record; v_uni numeric; v_fecha timestamptz;
begin
  begin
    if coalesce(btrim(NEW."Cod"),'') = '' then return NEW; end if;

    begin v_fecha := nullif(btrim(coalesce(NEW."Fecha",'')),'')::timestamptz;
    exception when others then v_fecha := null; end;
    v_fecha := coalesce(v_fecha, now());

    select a.tipo, a.ref_id into v_tipo, v_ref from contraparte_alias a where a.alias = v_nom;
    if v_tipo is null then
      select 'tallerista', t.id into v_tipo, v_ref from tallerista t
       where upper(t.nombre)=v_nom or upper(t.nombre) ~ ('(^|\s)'||v_nom||'($|\s)') limit 1;
    end if;
    if v_tipo is null then
      select 'proveedor_at', p.id into v_tipo, v_ref from proveedor_at p where upper(p.nombre)=v_nom limit 1;
    end if;
    if v_tipo is null then
      insert into virgilio_espejo_pend(entrega_id,fecha,nombre_tall,cod,cajas,motivo)
      values (NEW.id, NEW."Fecha", NEW."Nombre_Tall", NEW."Cod", NEW."Cajas", 'contraparte sin resolver');
      return NEW;
    end if;

    -- articulo: exacto primero, despues sin ceros de adelante en ambos lados
    select a.id, a.articulos_por_caja into v_art from articulo a
     where a.codigo = btrim(NEW."Cod")
        or regexp_replace(a.codigo,'^0+','') = regexp_replace(btrim(NEW."Cod"),'^0+','')
     order by (a.codigo = btrim(NEW."Cod")) desc limit 1;
    if v_art.id is null then
      insert into virgilio_espejo_pend(entrega_id,fecha,nombre_tall,cod,cajas,motivo)
      values (NEW.id, NEW."Fecha", NEW."Nombre_Tall", NEW."Cod", NEW."Cajas", 'articulo sin equivalente en GP2');
      return NEW;
    end if;

    v_uni := coalesce(NEW."Cajas",0) * coalesce(v_art.articulos_por_caja,0);
    if v_uni <= 0 then
      insert into virgilio_espejo_pend(entrega_id,fecha,nombre_tall,cod,cajas,motivo)
      values (NEW.id, NEW."Fecha", NEW."Nombre_Tall", NEW."Cod", NEW."Cajas", 'cantidad en cero');
      return NEW;
    end if;

    perform "GP2".recepcion_virgilio(jsonb_build_object(
      'fecha', v_fecha, 'origen_tipo', v_tipo, 'origen_id', v_ref,
      'remito', NEW."Remito",
      'items', jsonb_build_array(jsonb_build_object('articulo_id', v_art.id, 'cantidad', v_uni))));
  exception when others then
    insert into virgilio_espejo_pend(entrega_id,fecha,nombre_tall,cod,cajas,motivo)
    values (NEW.id, NEW."Fecha", NEW."Nombre_Tall", NEW."Cod", NEW."Cajas", 'error: '||sqlerrm);
  end;
  return NEW;
end $function$
;

-- ---------- fn_est_madre_sync ----------
CREATE OR REPLACE FUNCTION "GP2".fn_est_madre_sync()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
declare
  v_uni numeric;
begin
  if TG_OP = 'DELETE' then
    delete from "GP2".est_madre where cod = OLD.cod;
    return OLD;
  end if;
  if TG_OP = 'UPDATE' and NEW.cod is distinct from OLD.cod then
    delete from "GP2".est_madre where cod = OLD.cod;
  end if;
  -- solo codigos de articulo (empiezan con digito): las filas contables del origen no entran
  if NEW.cod is null or NEW.cod !~ '^[0-9]' then
    return NEW;
  end if;

  v_uni := NEW.proy_uni_mes;
  if NEW.uxb is null and NEW.proy_cajas_mes is not null then
    select round(NEW.proy_cajas_mes * a.articulos_por_caja) into v_uni
    from "GP2".articulo a
    where regexp_replace(a.codigo, '^0+', '') = regexp_replace(NEW.cod, '^0+', '')
      and a.articulos_por_caja is not null
    limit 1;
    if v_uni is null then v_uni := NEW.proy_uni_mes; end if;
  end if;

  insert into "GP2".est_madre (cod, proy_cajas_mes, uxb, proy_uni_mes, actualizado)
  values (NEW.cod, NEW.proy_cajas_mes, NEW.uxb, v_uni, NEW.actualizado)
  on conflict (cod) do update
    set proy_cajas_mes = EXCLUDED.proy_cajas_mes,
        uxb            = EXCLUDED.uxb,
        proy_uni_mes   = EXCLUDED.proy_uni_mes,
        actualizado    = EXCLUDED.actualizado,
        copiado_en     = now();
  return NEW;
end $function$
;

-- ---------- fn_movimiento_aplicar ----------
CREATE OR REPLACE FUNCTION "GP2".fn_movimiento_aplicar()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
begin
  if tg_op in ('UPDATE','DELETE') then
    perform "GP2".inv_delta(coalesce(old.comp_transformado_id, old.comp_id),
                            old.ubic_destino_id, - old._delta_dest);
    perform "GP2".inv_delta(old.comp_id, old.ubic_origen_id, + old._delta_orig);
  end if;
  if tg_op in ('INSERT','UPDATE') then
    perform "GP2".inv_delta(coalesce(new.comp_transformado_id, new.comp_id),
                            new.ubic_destino_id, + new._delta_dest);
    perform "GP2".inv_delta(new.comp_id, new.ubic_origen_id, - new._delta_orig);
  end if;
  return null;
end;
$function$
;

-- ---------- fn_movimiento_calc ----------
CREATE OR REPLACE FUNCTION "GP2".fn_movimiento_calc()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
begin
  -- vocabulario cerrado de unidades del ledger: 'kg' o 'uni' (null = "la del otro lado");
  -- to_canonical ya trataba cualquier cosa que no fuera kg como uni, aca queda escrito
  new.unidad_origen  := case when new.unidad_origen  is null then null when lower(new.unidad_origen)  = 'kg' then 'kg' else 'uni' end;
  new.unidad_destino := case when new.unidad_destino is null then null when lower(new.unidad_destino) = 'kg' then 'kg' else 'uni' end;
  if new.comp_transformado_id is null then
    new._delta_orig := "GP2".to_canonical(new.comp_id, new.cantidad,
                                          coalesce(new.unidad_origen, new.unidad_destino));
    new._delta_dest := new._delta_orig;
  else
    new._delta_orig := "GP2".to_canonical(new.comp_id, new.cantidad, new.unidad_origen);
    new._delta_dest := "GP2".to_canonical(new.comp_transformado_id, new.cantidad_transformada, new.unidad_destino);
  end if;
  return new;
end;
$function$
;

-- ---------- fn_precio_tallerista_kg ----------
CREATE OR REPLACE FUNCTION "GP2".fn_precio_tallerista_kg()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
declare v_kg numeric;
begin
  if new.precio_kg is not null then
    select kg_x_uni into v_kg from componente where id = new.componente_id;
    if v_kg is null or v_kg <= 0 then
      raise exception 'No se puede cargar una tarifa por kilo para el componente % porque no tiene kg_x_uni', new.componente_id;
    end if;
    new.precio_uni := new.precio_kg * v_kg;
  end if;
  return new;
end $function$
;

-- ---------- fn_recalc_maximos_cajones ----------
CREATE OR REPLACE FUNCTION "GP2".fn_recalc_maximos_cajones()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
begin
  perform "GP2".recalcular_maximos_cajones();
  return null;
end $function$
;

-- ---------- fn_recalc_maximos_insumos ----------
CREATE OR REPLACE FUNCTION "GP2".fn_recalc_maximos_insumos()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
begin
  perform "GP2".recalcular_maximos_insumos();
  return null;
end $function$
;

-- ---------- fn_rollo_desde_control ----------
CREATE OR REPLACE FUNCTION "GP2".fn_rollo_desde_control()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
declare v_comp bigint;
begin
  select ri.componente_id into v_comp
  from recepcion_control ctl join recepcion_insumo ri on ri.id = ctl.recepcion_id
  where ctl.id = coalesce(new.control_id, old.control_id);
  if v_comp is null then return null; end if;
  if tg_op in ('DELETE','UPDATE') then
    insert into rollo_evento(componente_id, kg_por_rollo, delta, motivo, control_rollo_id, nota)
    values (v_comp, old.kg_por_rollo, -old.cantidad, 'recepcion', null, 'reversa control '||old.id);
  end if;
  if tg_op in ('INSERT','UPDATE') then
    insert into rollo_evento(componente_id, kg_por_rollo, delta, motivo, control_rollo_id)
    values (v_comp, new.kg_por_rollo, new.cantidad, 'recepcion', new.id);
  end if;
  return null;
end $function$
;

-- ---------- get_role_for_email ----------
CREATE OR REPLACE FUNCTION "GP2".get_role_for_email(p_email text)
 RETURNS text
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT public.get_role_for_email(p_email);
$function$
;

-- ---------- guardar_control_cartones ----------
CREATE OR REPLACE FUNCTION "GP2".guardar_control_cartones(p_items jsonb, p_usuario text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
DECLARE
  it            jsonb;
  r             "GP2".recepcion_insumo%ROWTYPE;
  v_rec         bigint;
  v_paq         int;
  v_bolsas      int;
  v_uxp_def     int;
  v_uxp         int;
  v_uxb         int;
  v_total_uni   int;
  v_declarada   numeric;
  v_fmt         text;
  v_es_pliego   boolean;
  v_ok          int := 0;
  v_detalle     jsonb := '[]'::jsonb;
  v_rj          jsonb;
BEGIN
  IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' THEN
    RAISE EXCEPTION 'p_items debe ser un array JSON' USING ERRCODE = '22023';
  END IF;

  -- uni x paquete: parametro (default 250)
  SELECT COALESCE(NULLIF(valor,0)::int, 250) INTO v_uxp_def
    FROM "GP2".parametro WHERE clave = 'carton_uni_x_paquete';
  IF v_uxp_def IS NULL OR v_uxp_def < 1 THEN v_uxp_def := 250; END IF;

  FOR it IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    v_rec    := (it->>'recepcion_id')::bigint;
    v_paq    := NULLIF((it->>'paquetes'),'')::int;
    v_bolsas := NULLIF((it->>'bolsas'),'')::int;

    IF v_rec IS NULL THEN
      RAISE EXCEPTION 'item sin recepcion_id: %', it USING ERRCODE = '22023';
    END IF;

    SELECT * INTO r FROM "GP2".recepcion_insumo WHERE id = v_rec;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Recepcion % no existe', v_rec USING ERRCODE = 'P0002';
    END IF;

    -- Resolver formato + es_pliego del componente. uni_x_bolsa:
    --   - pliegos (es_pliego=true): SIEMPRE 100 (100 pliegos por paquete, regla usuario 2026-09-01)
    --   - cartones (es_pliego=false): desde carton_formato.uni_x_bolsa
    v_uxb := NULL; v_fmt := NULL; v_es_pliego := false;
    SELECT c.carton_formato, cf.uni_x_bolsa, c.es_pliego
      INTO v_fmt, v_uxb, v_es_pliego
      FROM "GP2".componente c
      LEFT JOIN "GP2".carton_formato cf ON cf.nombre = c.carton_formato
     WHERE c.id = r.componente_id;

    IF v_es_pliego THEN v_uxb := 100; END IF;

    v_uxp := v_uxp_def;

    -- Reglas:
    -- Si el frontend mando 'bolsas' y hay uni_x_bolsa (bolsa o paquete de pliegos) -> control por bolsas/paquetes.
    -- Si mando 'paquetes' -> control por paquetes de 250 (Pliego/Bolsa sin uxb).
    IF v_bolsas IS NOT NULL AND v_bolsas > 0 AND v_uxb IS NOT NULL AND v_uxb > 0 THEN
      v_total_uni := v_bolsas * v_uxb;
      v_paq       := (v_total_uni + v_uxp - 1) / v_uxp;  -- paquetes equivalentes (informativo)
      v_rj := jsonb_build_object(
        'bolsas',       v_bolsas,
        'uni_x_bolsa',  v_uxb,
        'paquetes',     v_paq,
        'uni_x_paquete',v_uxp,
        'carton_formato', v_fmt,
        'es_pliego',    v_es_pliego
      );
    ELSIF v_paq IS NOT NULL AND v_paq > 0 THEN
      v_total_uni := v_paq * v_uxp;
      v_bolsas    := NULL;
      v_rj := jsonb_build_object(
        'paquetes',      v_paq,
        'uni_x_paquete', v_uxp,
        'carton_formato', v_fmt,
        'es_pliego',     v_es_pliego
      );
    ELSE
      RAISE EXCEPTION 'Recepcion %: cargar paquetes>0 o bolsas>0 (formato=%, uxb=%, pliego=%)', v_rec, v_fmt, v_uxb, v_es_pliego USING ERRCODE = '22023';
    END IF;

    IF v_total_uni <= 0 THEN
      RAISE EXCEPTION 'Recepcion %: total_uni debe ser > 0', v_rec USING ERRCODE = '22023';
    END IF;

    v_declarada := COALESCE(r.cantidad_declarada, r.cantidad);

    UPDATE "GP2".recepcion_insumo
       SET controlado         = true,
           cantidad_declarada = v_declarada,
           base               = NULL,
           pisos              = NULL,
           sueltas            = NULL,
           paquetes           = v_paq,
           uni_x_paq          = v_uxp,
           rollos_json        = v_rj,
           cantidad           = v_total_uni,
           controlado_en      = now(),
           controlado_por     = p_usuario
     WHERE id = v_rec;

    IF r.movimiento_id IS NOT NULL AND v_total_uni::numeric <> r.cantidad THEN
      UPDATE "GP2".movimiento SET cantidad = v_total_uni WHERE id = r.movimiento_id;
    END IF;

    v_ok := v_ok + 1;
    v_detalle := v_detalle || jsonb_build_object(
      'recepcion_id',   v_rec,
      'declarada',      v_declarada,
      'carton_formato', v_fmt,
      'es_pliego',      v_es_pliego,
      'paquetes',       v_paq,
      'bolsas',         v_bolsas,
      'uni_x_bolsa',    v_uxb,
      'uni_x_paq',      v_uxp,
      'total_uni',      v_total_uni,
      'diff',           v_total_uni - v_declarada
    );
  END LOOP;

  RETURN jsonb_build_object('ok', true, 'aplicados', v_ok, 'items', v_detalle);
END;
$function$
;

-- ---------- informes_bundle ----------
CREATE OR REPLACE FUNCTION "GP2".informes_bundle(p_desde date DEFAULT NULL::date, p_hasta date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
with base as (
  select
    legajo,
    nombre_empleado,
    trim(matriz_raw) as mat,
    coalesce(uni,0)::numeric              as uni,
    coalesce(segundos_trabajados,0)::numeric as seg,
    coalesce(segundos_historico,0)::numeric  as segh,
    coalesce(anular_tiempo,false)         as anul
  from "GP2".produccion
  where (eliminar is null or eliminar <> 'S')
    and coalesce(legajo,'') <> '1'
    and coalesce(legajo,'') <> ''
    and (p_desde is null or (fecha at time zone 'America/Argentina/Buenos_Aires')::date >= p_desde)
    and (p_hasta is null or (fecha at time zone 'America/Argentina/Buenos_Aires')::date <= p_hasta)
),
cat as (
  select *,
    (mat ~ '^\d+\w*$')                                             as es_matriz,
    (mat like 'RM%')                                              as es_rm,
    ((mat ~ '^\d+\w*$') and uni > 0)                              as is_prod,
    ((mat !~ '^\d+\w*$') and mat <> 'E' and mat <> 'LT' and mat not like 'RM%') as is_tm
  from base
),
agg as (
  select
    legajo,
    (array_agg(nombre_empleado) filter (where nombre_empleado is not null and nombre_empleado <> ''))[1] as nombre,
    coalesce(sum(seg)  filter (where is_prod and not anul), 0) as seg_trab,
    coalesce(sum(segh) filter (where is_prod and not anul), 0) as seg_hist,
    coalesce(sum(uni)  filter (where is_prod and not anul), 0) as uni,
    coalesce(sum(seg)  filter (where is_prod and anul), 0)     as seg_anulados,
    count(*)           filter (where es_rm)                    as roturas,
    coalesce(sum(seg)  filter (where is_prod or es_rm or is_tm), 0) as seg_total
  from cat
  group by legajo
),
tm as (
  select legajo, split_part(mat, ' ', 1) as code, sum(seg) as seg
  from cat
  where is_tm
  group by legajo, split_part(mat, ' ', 1)
),
tm_by_leg as (
  select legajo, jsonb_object_agg(code, seg) as tmjson
  from tm group by legajo
)
select jsonb_build_object(
  'desde', p_desde,
  'hasta', p_hasta,
  'personas', coalesce((
    select jsonb_agg(jsonb_build_object(
      'legajo',      a.legajo,
      'nombre',      coalesce(a.nombre, ''),
      'segTrab',     a.seg_trab,
      'segHist',     a.seg_hist,
      'uni',         a.uni,
      'segAnulados', a.seg_anulados,
      'segTotal',    a.seg_total,
      'roturas',     a.roturas,
      'puntaje',     case when a.seg_hist > 0 then (-((a.seg_trab / a.seg_hist) - 1)) * 10 else 0 end,
      'tm',          coalesce(t.tmjson, '{}'::jsonb)
    ) order by (case when a.seg_hist > 0 then (-((a.seg_trab / a.seg_hist) - 1)) * 10 else 0 end) desc)
    from agg a
    left join tm_by_leg t on t.legajo = a.legajo
    where a.seg_total > 0
  ), '[]'::jsonb)
);
$function$
;

-- ---------- informes_matriz_bundle ----------
CREATE OR REPLACE FUNCTION "GP2".informes_matriz_bundle(p_desde date DEFAULT NULL::date, p_hasta date DEFAULT NULL::date, p_incluir_piedra boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
with base as (
  select
    trim(matriz_raw)                          as mat,
    legajo,
    nombre_empleado,
    nombre_matriz,
    coalesce(uni,0)::numeric                   as uni,
    coalesce(segundos_trabajados,0)::numeric   as seg,
    coalesce(segundos_historico,0)::numeric    as segh,
    tiempo_historico::numeric                  as thist
  from "GP2".produccion
  where (eliminar is null or eliminar <> 'S')
    and coalesce(legajo,'') not in ('','1')
    and coalesce(anular_tiempo,false) = false
    and trim(matriz_raw) ~ '^\d+\w*$'
    and coalesce(uni,0) > 0
    and (p_incluir_piedra or trim(matriz_raw) <> '501')
    and (p_desde is null or (fecha at time zone 'America/Argentina/Buenos_Aires')::date >= p_desde)
    and (p_hasta is null or (fecha at time zone 'America/Argentina/Buenos_Aires')::date <= p_hasta)
),
cell as (
  select mat, legajo, sum(seg) as seg_trab, sum(uni) as uni
  from base group by mat, legajo
),
mat_meta as (
  select mat,
         mode() within group (order by nombre_matriz) as nombre,
         max(nullif(thist,0))                          as thist,
         sum(seg)                                      as seg_total,
         sum(uni)                                      as uni_total
  from base group by mat
),
emp as (
  select legajo,
         mode() within group (order by nombre_empleado) as nombre,
         sum(seg)                                        as seg_emp
  from base group by legajo
),
cell_by_mat as (
  select mat, jsonb_object_agg(legajo, jsonb_build_object('segTrab', seg_trab, 'uni', uni)) as celdas
  from cell group by mat
)
select jsonb_build_object(
  'desde', p_desde,
  'hasta', p_hasta,
  'empleados', coalesce((
    select jsonb_agg(jsonb_build_object('legajo', legajo, 'nombre', coalesce(nombre, legajo))
                     order by lower(coalesce(nombre, legajo)))
    from emp), '[]'::jsonb),
  'hsTotalByEmp', coalesce((select jsonb_object_agg(legajo, seg_emp) from emp), '{}'::jsonb),
  'matrices', coalesce((
    select jsonb_agg(jsonb_build_object(
      'mat',      m.mat,
      'nombre',   coalesce(m.nombre, ''),
      'tHist',    m.thist,
      'uniTotal', m.uni_total,
      'segTotal', m.seg_total,
      'segXUni',  case when m.uni_total > 0 then m.seg_total / m.uni_total else 0 end,
      'premio',   case when m.thist > 0 and m.uni_total > 0
                       then (-(((m.seg_total / m.uni_total) / m.thist) - 1)) * 10 else 0 end,
      'celdas',   coalesce(c.celdas, '{}'::jsonb)
    ) order by (substring(m.mat from '^\d+'))::bigint, m.mat)
    from mat_meta m
    left join cell_by_mat c on c.mat = m.mat
  ), '[]'::jsonb)
);
$function$
;

-- ---------- inicio_bundle ----------
CREATE OR REPLACE FUNCTION "GP2".inicio_bundle()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
with base as (
  select *
  from "GP2".produccion
  where (eliminar is null or eliminar <> 'S')
    and coalesce(legajo,'') <> '1'
    and coalesce(uni,0) > 0
),
hoy_rows as (
  select * from base where fecha::date = current_date
),
mes_rows as (
  select * from base
  where extract(year from fecha) = extract(year from current_date)
    and extract(month from fecha) = extract(month from current_date)
),
disruptivas as (
  select count(*) c
  from "GP2".produccion
  where (eliminar is null or eliminar <> 'S')
    and coalesce(legajo,'') <> '1'
    and revisado is not true
    and matriz_raw ~ '^\d+\w*$'
    and (coalesce(premio,0) > 5 or coalesce(premio,0) < -5)
    and extract(year from fecha) = extract(year from current_date)
    and extract(month from fecha) = extract(month from current_date)
),
sin_tiempo as (
  select count(*) c
  from (
    select matriz_raw
    from "GP2".produccion
    where matriz_raw ~ '^\d+\w*$'
      and (eliminar is null or eliminar <> 'S')
    group by matriz_raw
    having coalesce(max(tiempo_historico),0) = 0
  ) q
)
select jsonb_build_object(
  'generado_en', now(),
  'hoy', to_char(current_date,'YYYY-MM-DD'),
  'dia', jsonb_build_object(
    'uni', coalesce((select sum(uni) from hoy_rows),0),
    'registros', (select count(*) from hoy_rows),
    'empleados', (select count(distinct legajo) from hoy_rows),
    'matrices', (select count(distinct matriz_raw) from hoy_rows)
  ),
  'mes', jsonb_build_object(
    'anio', extract(year from current_date)::int,
    'mes', extract(month from current_date)::int,
    'uni', coalesce((select sum(uni) from mes_rows),0),
    'registros', (select count(*) from mes_rows),
    'empleados', (select count(distinct legajo) from mes_rows),
    'matrices', (select count(distinct matriz_raw) from mes_rows)
  ),
  'alertas', jsonb_build_object(
    'disruptivas_mes', (select c from disruptivas),
    'matrices_sin_tiempo', (select c from sin_tiempo),
    'espejo_pend', (select count(*) from "GP2".virgilio_espejo_pend),
    'espejo_pend_detalle', (select coalesce(jsonb_agg(jsonb_build_object(
        'id',p.id,'motivo',p.motivo) order by p.id desc), '[]'::jsonb)
      from (select id, motivo from "GP2".virgilio_espejo_pend order by id desc limit 5) p)
  )
);
$function$
;

-- ---------- inv_delta ----------
CREATE OR REPLACE FUNCTION "GP2".inv_delta(p_comp bigint, p_ubic bigint, p_delta numeric)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
begin
  if p_comp is null or p_ubic is null or p_delta is null or p_delta = 0 then
    return;
  end if;
  insert into "GP2".inventario (componente_id, ubicacion_id, cantidad, actualizado_en)
  values (p_comp, p_ubic, p_delta, now())
  on conflict (componente_id, ubicacion_id) do update
     set cantidad       = inventario.cantidad + excluded.cantidad,
         actualizado_en = now();
end;
$function$
;

-- ---------- inyectores_bundle ----------
CREATE OR REPLACE FUNCTION "GP2".inyectores_bundle(p_sector_id bigint DEFAULT NULL::bigint)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
with sec_sel as (
  select coalesce(p_sector_id,
                  (select id from sector where nombre='Sector Plástico' limit 1)) sid
),
sec_nom as (select s.id, s.nombre from sector s, sec_sel where s.id=sec_sel.sid)
select jsonb_build_object(
  'generado_en', now(),
  'sector', (select jsonb_build_object('id',id,'nombre',nombre) from sec_nom),
  'sectores', (select coalesce(jsonb_agg(jsonb_build_object(
                  'id', s.id, 'nombre', s.nombre,
                  'n', (select count(*) from componente c where c.sector_id=s.id),
                  -- pendiente = sin proveedor Y que se compre
                  'sin_prov', (select count(*) from componente c
                                where c.sector_id=s.id
                                  and c.estado_compra is null
                                  and nullif(btrim(coalesce(c.proveedor,'')),'') is null)
                ) order by s.nombre), '[]'::jsonb)
              from sector s where "GP2"._es_sector_insumo(s.id)),
  'proveedores', (select coalesce(jsonb_agg(jsonb_build_object(
                     'nombre', pi.nombre, 'modo_control', pi.modo_control,
                     'n', (select count(*) from componente c, sec_sel
                            where c.sector_id=sec_sel.sid and btrim(coalesce(c.proveedor,''))=pi.nombre)
                   ) order by pi.nombre), '[]'::jsonb)
                  from proveedor_insumo pi
                  where pi.activo
                    and (pi.rubro = (select nombre from sec_nom)
                         or exists (select 1 from componente c, sec_sel
                                     where c.sector_id=sec_sel.sid
                                       and btrim(coalesce(c.proveedor,''))=pi.nombre))),
  'partes', (select coalesce(jsonb_agg(jsonb_build_object(
                'comp_id', c.id, 'codigo', c.codigo, 'descripcion', c.descripcion,
                'proveedor', nullif(btrim(coalesce(c.proveedor,'')),''),
                'estado_compra', c.estado_compra,
                'um', c.unidad_medida, 'kg_x_uni', c.kg_x_uni, 'uni_x_cajon', c.uni_x_cajon,
                'lo_produce', (select t.nombre from ruta_paso rp
                                join tallerista t on t.id=rp.tallerista_id
                               where rp.comp_salida_id=c.id limit 1),
                'stock', coalesce((select sum(i.cantidad) from inventario i where i.componente_id=c.id),0),
                'en_recetas', (select count(*) from articulo_componente ac where ac.componente_id=c.id)
              ) order by c.codigo), '[]'::jsonb)
             from componente c, sec_sel where c.sector_id=sec_sel.sid)
);
$function$
;

-- ---------- marcar_estado_compra ----------
CREATE OR REPLACE FUNCTION "GP2".marcar_estado_compra(p_comp_id bigint, p_estado text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
declare v_e text := nullif(btrim(coalesce(p_estado,'')),''); v_cod text;
begin
  if v_e is not null and v_e not in ('fabricacion','discontinuo') then
    raise exception 'Estado invalido: "%". Solo "fabricacion", "discontinuo" o vacio.', v_e;
  end if;
  select codigo into v_cod from componente where id = p_comp_id;
  if v_cod is null then raise exception 'Componente inexistente (id=%).', p_comp_id; end if;
  -- estado y proveedor se excluyen: si no se compra, no tiene sentido un proveedor
  update componente
     set estado_compra = v_e,
         proveedor = case when v_e is null then proveedor else null end
   where id = p_comp_id;
  return jsonb_build_object('ok',true,'comp_id',p_comp_id,'codigo',v_cod,'estado',v_e);
end $function$
;

-- ---------- marcar_faltante ----------
CREATE OR REPLACE FUNCTION "GP2".marcar_faltante(p_comp_id bigint, p_origen text DEFAULT 'manual'::text, p_nota text DEFAULT NULL::text, p_usuario text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
declare v_id bigint; v_dup boolean := false;
begin
  if p_comp_id is null or not exists (select 1 from componente where id = p_comp_id) then
    return jsonb_build_object('ok', false, 'error', 'componente inexistente');
  end if;
  if p_origen not in ('envios_tall','envios_ps','operario','manual') then
    return jsonb_build_object('ok', false, 'error', 'origen invalido');
  end if;

  select id into v_id from faltante_marcado
  where componente_id = p_comp_id and origen = p_origen and resuelto_en is null
  order by creado_en desc limit 1;

  if v_id is not null then
    v_dup := true;
  else
    insert into faltante_marcado (componente_id, origen, nota, marcado_por)
    values (p_comp_id, p_origen, nullif(trim(p_nota), ''), nullif(trim(p_usuario), ''))
    returning id into v_id;
  end if;

  return jsonb_build_object('ok', true, 'id', v_id, 'ya_existia', v_dup);
end $function$
;

-- ---------- marcar_revisado ----------
CREATE OR REPLACE FUNCTION "GP2".marcar_revisado(row_id bigint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
begin
  update produccion set revisado = true where id = row_id;
  if not found then
    raise exception 'Registro id=% no encontrado', row_id;
  end if;
end;
$function$
;

-- ---------- movimientos_bundle ----------
CREATE OR REPLACE FUNCTION "GP2".movimientos_bundle()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
  select jsonb_build_object(
    'sect', (select coalesce(jsonb_object_agg(id::text, jsonb_build_object('tipo',tipo,'nom',nombre)),'{}'::jsonb) from sector),
    'ubic', (select coalesce(jsonb_object_agg(id::text, jsonb_build_object('tipo',tipo,'ref',ref_id,'nom',nombre,'meses',meses_minimo)),'{}'::jsonb) from ubicacion),
    'art', (select coalesce(jsonb_object_agg(a.id::text, jsonb_build_object('id',a.id,'cod',a.codigo,'fam',a.familia,'cja',a.componente_caja_id,'por',a.articulos_por_caja,
            'est',(select em.proy_uni_mes from est_madre em where regexp_replace(em.cod,'^0+','') = regexp_replace(a.codigo,'^0+','') limit 1))),'{}'::jsonb) from articulo a),
    'comp', (select coalesce(jsonb_object_agg(id::text, jsonb_build_object('cod',codigo,'d',descripcion,'s',sector_id,'um',unidad_medida,'kg_x_uni',kg_x_uni,'uxc',uni_x_cajon)),'{}'::jsonb) from componente),
    'prov_serv', (select coalesce(jsonb_object_agg(id::text, jsonb_build_object('nom',nombre,'proceso',proceso)),'{}'::jsonb) from proveedor_servicio),
    'tall', (select coalesce(jsonb_object_agg(id::text, jsonb_build_object('nom',nombre,'ubi_stock',ubicacion_stock_id)),'{}'::jsonb) from tallerista),
    -- 'primera' (primera matriz del fleje) = tiene partes_por_kilo_de_fleje cargado; true/null como salia antes (sin coalesce)
    'mat', (select coalesce(jsonb_object_agg(id::text, jsonb_build_object('n',n_matriz,'d',descripcion,'tipo',tipo,'ppk',partes_por_kilo_de_fleje,'primera',(case when partes_por_kilo_de_fleje is not null then true end),'uxg',uni_x_golpe,'maq',maquina,'act',activa)),'{}'::jsonb) from matriz),
    'bom_art', (select coalesce(jsonb_object_agg(articulo_id::text, arr),'{}'::jsonb) from (
        select articulo_id, jsonb_agg(jsonb_build_object('c',componente_id,'q',cantidad)) arr
        from articulo_componente group by articulo_id) x),
    'bom_comp', (select coalesce(jsonb_object_agg(componente_padre_id::text, arr),'{}'::jsonb) from (
        select componente_padre_id, jsonb_agg(jsonb_build_object('c',componente_hijo_id,'q',cantidad)) arr
        from componente_bom group by componente_padre_id) x),
    'rp', (select coalesce(jsonb_object_agg(ruta_id::text, arr),'{}'::jsonb) from (
        select rp.ruta_id, jsonb_agg(jsonb_build_object('o',rp.orden,'tipo',rp.tipo_paso,
            'flje', case when rp.tipo_paso = 'ingreso' and rp.orden = 1 and ce.sector_id = 5 then rp.comp_entrada_id end,
            'mat',rp.matriz_id,'prov',rp.proveedor_id,'tall',rp.tallerista_id,'ce',rp.comp_entrada_id,'cs',rp.comp_salida_id,
            'art', case when rp.tipo_paso = 'virgilio' then r.articulo_id end) order by rp.orden) arr
        from ruta_paso rp
        left join componente ce on ce.id = rp.comp_entrada_id
        left join ruta r on r.id = rp.ruta_id
        group by rp.ruta_id) x),
    'inv', (select coalesce(jsonb_object_agg(componente_id::text||':'||ubicacion_id::text, jsonb_build_object('cant',cantidad,'min',minimo,'max',maximo)),'{}'::jsonb) from inventario),
    'c2a', (select coalesce(jsonb_object_agg(comp_entrada_id::text, articulo_id),'{}'::jsonb) from (
        select distinct on (rp.comp_entrada_id) rp.comp_entrada_id, r.articulo_id
        from ruta_paso rp join ruta r on r.id = rp.ruta_id
        where rp.tipo_paso = 'virgilio' and rp.comp_entrada_id is not null and r.articulo_id is not null
        order by rp.comp_entrada_id, rp.ruta_id) x)
  );
$function$
;

-- ---------- oc_bundle ----------
CREATE OR REPLACE FUNCTION "GP2".oc_bundle()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
with pend as (
  select oi.componente_id, sum(oi.cantidad - oi.recibido) pendiente
  from orden_compra_item oi join orden_compra o on o.id = oi.oc_id
  where o.estado in ('borrador','enviada')
  group by oi.componente_id
), pv as (
  select distinct on (pp.componente_id) pp.componente_id,
         case when pp.precio_por_kg then pp.precio * cc.kg_x_uni else pp.precio end precio,
         case when upper(coalesce(pp.moneda,'USD')) like '%US%' then 'USD' else 'ARS' end moneda
  from precio_proveedor pp
  join componente cc on cc.id = pp.componente_id
  where pp.componente_id is not null and pp.precio is not null
  order by pp.componente_id, pp.fecha_lista desc nulls last, pp.id desc
), ins as (
  select c.id comp_id, c.codigo, c.descripcion, c.sector_id, s.nombre sector,
         c.unidad_medida um, c.kg_x_uni,
         nullif(trim(c.proveedor),'') proveedor,
         coalesce(u.meses_stock, inv.meses_stock) meses_stock,
         case when c.sector_id = 5 then fk.consumo_kg_mes else cp.consumo_uni_mes end consumo,
         case when c.sector_id = 5 or lower(coalesce(c.unidad_medida,'')) = 'kg'
              then 'kg' else 'uni' end unidad,
         inv.cantidad online,
         inv.minimo,
         inv.maximo maximo_inv,
         inv.maximo_origen maximo_origen_inv,
         inv.ubicacion_id, inv.ubic_nombre,
         coalesce(pd.pendiente, 0) pendiente_oc,
         c.carton_formato, c.carton_categoria, c.marca,
         coalesce(c.es_pliego, false) es_pliego,
         coalesce(cc2.mezcla_libre, false) mezcla_libre,
         cf.pliegos_multiplo, cf.codigo_multiplo, cf.min_codigo_x_multiplo, cf.pedido_minimo,
         pv.precio, pv.moneda
  from componente c
  join sector s on s.id = c.sector_id
  left join ubicacion u on u.id = "GP2".ubic_de('sector', c.sector_id)
  left join lateral (
    select i.cantidad, i.minimo, i.maximo, i.maximo_origen, i.ubicacion_id,
           iu.meses_stock, iu.nombre ubic_nombre
    from inventario i join ubicacion iu on iu.id = i.ubicacion_id
    where i.componente_id = c.id
    order by case
               when iu.id = "GP2".ubic_de('sector', c.sector_id)
                 or (c.sector_id = 12 and iu.id = "GP2".ubic_de('virgilio')) then 0
               when iu.tipo='sector' then 1
               when iu.tipo='proveedor_servicio' then 2
               else 3
             end,
             i.cantidad desc nulls last, i.ubicacion_id
    limit 1
  ) inv on true
  left join v_consumo_componente cp on cp.componente_id = c.id and c.sector_id <> 5
  left join v_consumo_fleje_kg fk on fk.componente_id = c.id and c.sector_id = 5
  left join pend pd on pd.componente_id = c.id
  left join carton_formato cf on cf.nombre = c.carton_formato
  left join carton_categoria cc2 on cc2.nombre = c.carton_categoria and cc2.formato = c.carton_formato
  left join pv on pv.componente_id = c.id
  where (
          "GP2"._es_sector_insumo(c.sector_id)
          or trim(coalesce(c.proveedor,'')) in ('Resortes Charcas','Eclipse')
          or (c.proveedor is not null
              and exists (select 1 from proveedor_insumo pi where pi.nombre = c.proveedor))
        )
    and c.estado_compra is null
    -- LO QUE PRODUCE UN PS NO SE COMPRA (usuario 2026-09-08: "esas dos partes de charcas se
    -- tratan como proveedor de servicio"). Si el proveedor que figura en el componente es el
    -- MISMO PS que lo produce en una ruta (ruta_paso tipo proveedor_servicio, comp_salida = el
    -- componente), no hay OC: se le manda la materia prima y se recibe por Entrega PS. Hoy son
    -- IC3 e IC3V (Charcas corta el FLEJE90_BRUTO de Altrak, que SI se compra, en su rubro
    -- Alambre). Se mira el proveedor DEL COMPONENTE, no el paso suelto: un insumo que compramos
    -- y mandamos a pintar (paso PS con entrada=salida) sigue en la OC, y las bombillas que
    -- Charcas nos VENDE (BOM10/EP10/LLF8) tambien.
    and not exists (
      select 1 from ruta_paso rp
      join proveedor_servicio ps2 on ps2.id = rp.proveedor_id
      where rp.tipo_paso = 'proveedor_servicio'
        and rp.comp_salida_id = c.id
        and ps2.nombre = c.proveedor
    )
), calc as (
  select ins.*,
         case when maximo_inv is not null then maximo_inv
              when round(coalesce(consumo,0) * coalesce(meses_stock,0)) > 0
                then round(coalesce(consumo,0) * coalesce(meses_stock,0))
              else null end as maximo_ef,
         case when maximo_inv is not null then maximo_origen_inv
              when round(coalesce(consumo,0) * coalesce(meses_stock,0)) > 0
                then 'consumo_x_meses'
              else null end as maximo_origen_ef
  from ins
)
select jsonb_build_object(
  'insumos', (select coalesce(jsonb_agg(jsonb_build_object(
      'comp_id',comp_id,'codigo',codigo,'descripcion',descripcion,'sector',sector,'sector_id',sector_id,
      'proveedor',proveedor,'um',um,'unidad',unidad,'kg_x_uni',kg_x_uni,
      'consumo',consumo,'consumo_uni_mes',consumo,'meses',meses_stock,
      'online',coalesce(online,0),'stock',coalesce(online,0),
      'minimo',minimo,
      'maximo',maximo_ef,'maximo_origen',maximo_origen_ef,'maximo_inventario',maximo_inv,
      'ubicacion_id',ubicacion_id,'ubicacion',ubic_nombre,
      'pendiente_oc',pendiente_oc,
      'sugerido', greatest(0, round(coalesce(maximo_ef,0) - coalesce(online,0))),
      'sugerido_consumo', greatest(0, round(coalesce(consumo,0)*coalesce(meses_stock,0) - coalesce(online,0))),
      'precio',precio,'moneda',moneda,
      'carton_formato',carton_formato,'carton_categoria',carton_categoria,
      'marca',marca,'mezcla_libre',mezcla_libre,'es_pliego',es_pliego,
      'pliegos_multiplo',pliegos_multiplo,'pedido_minimo',pedido_minimo,
      'codigo_multiplo',codigo_multiplo,'min_codigo_x_multiplo',min_codigo_x_multiplo
    ) order by sector_id, codigo),'[]'::jsonb) from calc),
  'pliego_uni_x_paquete', (select valor from parametro where clave='pliego_uni_x_paquete'),
  'paq', (select valor from parametro where clave='carton_uni_x_paquete'),
  'charcas_kg_x_paquete', (select valor from parametro where clave='charcas_kg_x_paquete'),
  'proveedores', (select coalesce(jsonb_agg(jsonb_build_object(
      'nombre',pi.nombre,'rubro',pi.rubro,'modo_control',pi.modo_control,
      'cod_prov',pi.cod_prov,'activo',pi.activo,'dias_entrega',pi.dias_entrega,
      'insumos',(select count(*) from componente c3
                  where c3.proveedor = pi.nombre and c3.estado_compra is null)
    ) order by pi.nombre),'[]'::jsonb) from proveedor_insumo pi),
  'ocs', (select coalesce(jsonb_agg(jsonb_build_object(
      'id',o.id,'numero',o.numero,'proveedor',o.proveedor,'rubro',o.rubro,'estado',o.estado,
      'nota',o.nota,'creado_en',o.creado_en,
      'fecha_entrega_estimada',o.fecha_entrega_estimada,
      'total_usd',(select coalesce(sum(oi.cantidad*oi.precio_uni),0) from orden_compra_item oi
                   where oi.oc_id=o.id and oi.moneda='USD'),
      'total_ars',(select coalesce(sum(oi.cantidad*oi.precio_uni),0) from orden_compra_item oi
                   where oi.oc_id=o.id and oi.moneda='ARS'),
      'items',(select coalesce(jsonb_agg(jsonb_build_object(
                 'codigo',c2.codigo,'descripcion',c2.descripcion,'cantidad',oi.cantidad,
                 'unidad',oi.unidad,'recibido',oi.recibido,
                 'precio_uni',oi.precio_uni,'moneda',oi.moneda,
                 'subtotal',case when oi.precio_uni is null then null else round(oi.cantidad*oi.precio_uni,2) end
               ) order by c2.codigo),'[]'::jsonb)
               from orden_compra_item oi join componente c2 on c2.id=oi.componente_id
              where oi.oc_id=o.id)
    ) order by o.numero desc),'[]'::jsonb) from orden_compra o),
  'tc', (select valor from parametro where clave='tipo_cambio_usd_pesos'),
  'generado_en', now()
);
$function$
;

-- ---------- oc_marcar ----------
CREATE OR REPLACE FUNCTION "GP2".oc_marcar(p_oc_id bigint, p_estado text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
begin
  if p_estado not in ('borrador','enviada','recibida','anulada') then
    raise exception 'Estado invalido: %', p_estado;
  end if;
  update orden_compra set estado = p_estado where id = p_oc_id;
  if not found then raise exception 'OC % no existe', p_oc_id; end if;
  return jsonb_build_object('ok', true);
end $function$
;

-- ---------- orden_produccion_bundle ----------
CREATE OR REPLACE FUNCTION "GP2".orden_produccion_bundle()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
with pasos as (
  -- ruta_paso repite el mismo paso en cada ruta que lo usa: deduplicar
  select distinct rp.matriz_id, rp.comp_entrada_id, rp.comp_salida_id
  from ruta_paso rp
  where rp.tipo_paso = 'matriz'
    and rp.matriz_id is not null
    and rp.comp_entrada_id is not null
    and rp.comp_salida_id is not null
),
comp_ids as (
  select comp_entrada_id id from pasos
  union
  select comp_salida_id from pasos
),
comps as (
  select c.id, c.codigo, c.descripcion, s.tipo,
         c.kg_x_uni, c.uni_x_cajon,
         fd.n_fleje, fd.medida_mm
  from componente c
  join sector s on s.id = c.sector_id
  left join fleje_detalle fd on fd.componente_id = c.id
  where c.id in (select id from comp_ids) or s.tipo in ('crudo','procesado')
),
dest as (
  -- destinos posibles: todo componente de Sector Crudo / Sector Procesado,
  -- con su consumo mensual atribuido (3b) y su inventario en la ubicacion
  -- del propio sector
  select c.id comp_id,
         u.meses_stock,
         vc.consumo_uni_mes,
         coalesce(i.cantidad, 0) stock_uni,
         coalesce(i.maximo, 0) maximo_uni,
         greatest(0, round(coalesce(vc.consumo_uni_mes,0) * coalesce(u.meses_stock,0)
                           - coalesce(i.cantidad,0))) faltante_uni
  from componente c
  join sector s on s.id = c.sector_id and s.tipo in ('crudo','procesado')
  join ubicacion u on u.id = "GP2".ubic_de('sector', c.sector_id)
  left join v_consumo_componente vc on vc.componente_id = c.id
  left join inventario i on i.componente_id = c.id and i.ubicacion_id = u.id
)
select jsonb_build_object(
  'pasos', (select coalesce(jsonb_agg(jsonb_build_object(
      'matriz_id', matriz_id, 'comp_entrada_id', comp_entrada_id,
      'comp_salida_id', comp_salida_id)), '[]'::jsonb) from pasos),
  'matrices', (select coalesce(jsonb_agg(jsonb_build_object(
      'id', m.id, 'n_matriz', m.n_matriz, 'descripcion', m.descripcion,
      'partes_por_kilo_de_fleje', m.partes_por_kilo_de_fleje)), '[]'::jsonb)
    from matriz m where m.id in (select matriz_id from pasos)),
  'componentes', (select coalesce(jsonb_agg(jsonb_build_object(
      'id', id, 'codigo', codigo, 'descripcion', descripcion, 'tipo', tipo,
      'kg_x_uni', kg_x_uni, 'uni_x_cajon', uni_x_cajon,
      'n_fleje', n_fleje, 'medida_mm', medida_mm)), '[]'::jsonb) from comps),
  'destinos', (select coalesce(jsonb_agg(jsonb_build_object(
      'comp_id', comp_id, 'meses_stock', meses_stock,
      'consumo_uni_mes', consumo_uni_mes,
      'stock_uni', stock_uni, 'maximo_uni', maximo_uni,
      'faltante_uni', faltante_uni)), '[]'::jsonb) from dest),
  'generado_en', now()
);
$function$
;

-- ---------- partes_por_ps ----------
CREATE OR REPLACE FUNCTION "GP2".partes_por_ps()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
  -- Para cada PS: que partes le mandan (sc = entrada) y que partes devuelve (sp = salida).
  -- Sale de v_contraparte_parte (una sola definicion, 2026-09-05).
  select coalesce(jsonb_object_agg(prov_id::text, jsonb_build_object('sc', coalesce(sc,'[]'::jsonb), 'sp', coalesce(sp,'[]'::jsonb))), '{}'::jsonb)
  from (
    select v.ref_id prov_id,
      (select jsonb_agg(distinct jsonb_build_object('id',c.id,'codigo',c.codigo,'descripcion',c.descripcion,'sector',s.nombre))
         from "GP2".v_contraparte_parte v2 join "GP2".componente c on c.id=v2.comp_id join "GP2".sector s on s.id=c.sector_id
        where v2.tipo='proveedor_servicio' and v2.ref_id=v.ref_id and v2.lado='entrada') sc,
      (select jsonb_agg(distinct jsonb_build_object('id',c.id,'codigo',c.codigo,'descripcion',c.descripcion,'sector',s.nombre))
         from "GP2".v_contraparte_parte v2 join "GP2".componente c on c.id=v2.comp_id join "GP2".sector s on s.id=c.sector_id
        where v2.tipo='proveedor_servicio' and v2.ref_id=v.ref_id and v2.lado='salida') sp
    from "GP2".v_contraparte_parte v
    where v.tipo='proveedor_servicio'
    group by v.ref_id
  ) x;
$function$
;

-- ---------- pesar_pallet ----------
CREATE OR REPLACE FUNCTION "GP2".pesar_pallet(p_recepcion_id bigint, p_nro_pallet integer, p_peso_balanza numeric, p_rollos jsonb, p_usuario text DEFAULT NULL::text, p_nota text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
declare v_ctl bigint; r jsonb; v_n int := 0;
begin
  if p_peso_balanza is null or p_peso_balanza <= 0 then
    raise exception 'El peso de balanza debe ser mayor a 0';
  end if;
  if p_nro_pallet is null or p_nro_pallet <= 0 then
    raise exception 'El numero de pallet debe ser mayor a 0';
  end if;
  if jsonb_typeof(coalesce(p_rollos,'[]'::jsonb)) <> 'array' then
    raise exception 'p_rollos debe ser un array JSON';
  end if;
  if not exists(select 1 from "GP2".recepcion_insumo where id = p_recepcion_id) then
    raise exception 'La recepcion % no existe', p_recepcion_id;
  end if;

  insert into "GP2".recepcion_control(recepcion_id, nro_pallet, peso_balanza, controlado_por, nota)
  values (p_recepcion_id, p_nro_pallet, p_peso_balanza,
          nullif(btrim(coalesce(p_usuario,'')),''), nullif(btrim(coalesce(p_nota,'')),''))
  on conflict (recepcion_id, nro_pallet) do update set
    peso_balanza = excluded.peso_balanza, controlado_por = excluded.controlado_por,
    nota = excluded.nota, controlado_en = now()
  returning id into v_ctl;

  delete from "GP2".recepcion_control_rollo where control_id = v_ctl;
  for r in select * from jsonb_array_elements(coalesce(p_rollos,'[]'::jsonb)) loop
    if coalesce((r->>'cantidad')::int,0) > 0 and coalesce((r->>'kg_por_rollo')::numeric,0) > 0 then
      insert into "GP2".recepcion_control_rollo(control_id, cantidad, kg_por_rollo)
      values (v_ctl, (r->>'cantidad')::int, (r->>'kg_por_rollo')::numeric);
      v_n := v_n + 1;
    end if;
  end loop;

  return jsonb_build_object(
    'ok', true, 'lineas', v_n,
    'pallet', (select to_jsonb(vp) from "GP2".v_control_pallet vp where vp.control_id = v_ctl),
    'recepcion', (select to_jsonb(vr) from "GP2".v_recepcion_control vr where vr.recepcion_id = p_recepcion_id));
end $function$
;

-- ---------- pintores_bundle ----------
CREATE OR REPLACE FUNCTION "GP2".pintores_bundle()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
declare
  v_pintores jsonb;
  v_partes   jsonb;
  r          record;
  v_carga    jsonb := '{}'::jsonb;   -- pintor_id -> cajones acumulados
  v_prop     jsonb := '{}'::jsonb;   -- comp_id  -> pintor_id propuesto
  v_elegido  bigint;
  v_min      numeric;
  v_c        numeric;
  p          bigint;
begin
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', ps.id, 'nombre', ps.nombre, 'cod_prov', ps.cod_prov,
           'puede', (select count(*) from parte_proveedor_servicio x
                      where x.proveedor_servicio_id = ps.id))
           order by ps.nombre), '[]'::jsonb)
    into v_pintores
    from proveedor_servicio ps where ps.proceso = 'Pintado';

  -- Reparto propuesto: de la parte mas pesada a la mas liviana.
  for r in
    select c.id comp_id,
           round(vc.consumo_uni_mes::numeric / nullif(c.uni_x_cajon,0), 2) as cajones
    from componente c
    left join v_consumo_componente vc on vc.componente_id = c.id
    where exists (select 1 from parte_proveedor_servicio x where x.componente_id = c.id)
    order by round(vc.consumo_uni_mes::numeric / nullif(c.uni_x_cajon,0), 2) desc nulls last, c.codigo
  loop
    if r.cajones is null then continue; end if;   -- sin dato: no se reparte
    v_elegido := null; v_min := null;
    for p in select proveedor_servicio_id from parte_proveedor_servicio
              where componente_id = r.comp_id order by proveedor_servicio_id
    loop
      v_c := coalesce((v_carga ->> p::text)::numeric, 0);
      if v_min is null or v_c < v_min then v_min := v_c; v_elegido := p; end if;
    end loop;
    if v_elegido is not null then
      v_prop  := v_prop  || jsonb_build_object(r.comp_id::text, v_elegido);
      v_carga := v_carga || jsonb_build_object(v_elegido::text, v_min + r.cajones);
    end if;
  end loop;

  with pintables as (
    select distinct rp.comp_entrada_id comp_id
    from ruta_paso rp
    join proveedor_servicio p2 on p2.id = rp.proveedor_id and p2.proceso='Pintado'
    where rp.comp_entrada_id is not null
  ),
  partes as (
    select distinct c.id comp_id, c.codigo, c.descripcion, c.uni_x_cajon,
           s.nombre sector
    from componente c
    left join sector s on s.id = c.sector_id
    where c.id in (select componente_id from parte_proveedor_servicio)
       or c.id in (select comp_id from pintables)
  )
  select coalesce(jsonb_agg(x order by x->>'codigo'), '[]'::jsonb) into v_partes
  from (
    select jsonb_build_object(
      'comp_id',     p.comp_id,
      'codigo',      p.codigo,
      'descripcion', p.descripcion,
      'sector',      p.sector,
      'consumo',     vc.consumo_uni_mes,
      'uni_x_cajon', p.uni_x_cajon,
      'cajones',     round(vc.consumo_uni_mes::numeric / nullif(p.uni_x_cajon,0), 2),
      'pueden',      coalesce((select jsonb_agg(pps.proveedor_servicio_id order by pps.proveedor_servicio_id)
                                 from parte_proveedor_servicio pps
                                where pps.componente_id = p.comp_id), '[]'::jsonb),
      'asignado',    (select pps.proveedor_servicio_id from parte_proveedor_servicio pps
                       where pps.componente_id = p.comp_id and pps.asignado),
      'propuesto',   (v_prop ->> p.comp_id::text)::bigint
    ) as x
    from partes p left join v_consumo_componente vc on vc.componente_id = p.comp_id
  ) t;

  return jsonb_build_object('pintores', v_pintores, 'partes', v_partes);
end $function$
;

-- ---------- problemas_matrices_bundle ----------
CREATE OR REPLACE FUNCTION "GP2".problemas_matrices_bundle(p_desde date, p_hasta date)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
with base as (
  select p.id, btrim(coalesce(p.matriz_raw,'')) as m, p.fecha, p.hora_inicio, p.hora_fin,
         p.legajo, p.nombre_empleado, p.uni, p.segundos_tiempo_muerto,
         case when p.nombre_matriz = 'Rotura Matriz' then 'RM'
              when p.nombre_matriz = 'Pare Matriz'   then 'PM' end as tipo
  from produccion p
  where (p.eliminar is null or p.eliminar <> 'S')
    and (p.fecha at time zone 'America/Argentina/Buenos_Aires')::date between p_desde and p_hasta
), ord as (
  select b.*,
         count(*) filter (where b.tipo = 'RM')
           over (partition by b.m order by b.fecha, b.id
                 rows between unbounded preceding and 1 preceding) as grp
  from base b where b.m <> ''
), acum as (
  select o.*,
         sum(case when o.uni > 0 then o.uni else 0 end)
           over (partition by o.m, coalesce(o.grp,0) order by o.fecha, o.id
                 rows between unbounded preceding and 1 preceding) as uni_acum
  from ord o
)
select jsonb_build_object(
  'eventos', (select coalesce(jsonb_agg(jsonb_build_object(
      'fecha', to_char(a.fecha at time zone 'America/Argentina/Buenos_Aires','YYYY-MM-DD'),
      'hora_inicio', a.hora_inicio, 'hora_fin', a.hora_fin,
      'tipo', a.tipo, 'legajo', a.legajo,
      'empleado', coalesce(a.nombre_empleado, e.nombre),
      'matriz', a.m, 'nombre_matriz', mt.descripcion,
      'segundos', a.segundos_tiempo_muerto,
      'uni_acum', coalesce(a.uni_acum, 0),
      'uni_x_golpe', mt.uni_x_golpe,
      'golpes', case when mt.uni_x_golpe > 0 then round(coalesce(a.uni_acum,0) / mt.uni_x_golpe) end
      ) order by a.fecha desc, a.id desc),'[]'::jsonb)
    from acum a
    left join empleado e on e.legajo = a.legajo
    left join matriz mt on btrim(mt.n_matriz) = a.m
    where a.tipo is not null),
  'empleados', (select coalesce(jsonb_agg(jsonb_build_object('legajo',legajo,'nombre',nombre) order by nombre),'[]'::jsonb)
    from empleado where activo),
  'desde', p_desde, 'hasta', p_hasta);
$function$
;

-- ---------- produccion_bundle ----------
CREATE OR REPLACE FUNCTION "GP2".produccion_bundle(p_matriz text DEFAULT NULL::text, p_anio integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
select jsonb_build_object(
  'matrices', coalesce((
    select jsonb_agg(jsonb_build_object('N_Matriz', m, 'Matriz', nm, 'Tiempo_Historico', th))
    from (
      select matriz_raw m,
             (array_agg(nombre_matriz) filter (where nombre_matriz is not null and nombre_matriz <> ''))[1] nm,
             max(tiempo_historico) th
      from "GP2".produccion
      where matriz_raw is not null and matriz_raw <> ''
        and (eliminar is null or eliminar <> 'S')
      group by matriz_raw
    ) q
  ), '[]'::jsonb),
  'empleados', coalesce((
    select jsonb_object_agg(legajo, nom)
    from (
      select legajo,
             (array_agg(nombre_empleado) filter (where nombre_empleado is not null and nombre_empleado <> ''))[1] nom
      from "GP2".produccion
      where legajo is not null and legajo <> ''
      group by legajo
    ) e
  ), '{}'::jsonb),
  'rows', coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', id,
      'Matriz', matriz_raw,
      'Nombre_Matriz', nombre_matriz,
      'Legajo', legajo,
      'Uni', uni,
      'Fecha', to_char(fecha, 'YYYY-MM-DD'),
      'Hora_Inicio', to_char(hora_inicio, 'HH24:MI:SS'),
      'Hora_Fin', to_char(hora_fin, 'HH24:MI:SS'),
      'Segundos_Trabajados', segundos_trabajados,
      'Tiempo_Toma', tiempo_toma,
      'Premio', premio,
      'Eliminar', eliminar
    ) order by fecha, hora_inicio)
    from "GP2".produccion
    where p_matriz is not null
      and matriz_raw = p_matriz
      and (eliminar is null or eliminar <> 'S')
      and coalesce(legajo, '') <> '1'
      and coalesce(uni, 0) > 0
      and coalesce(tiempo_toma, 0) > 0
      and (p_anio is null or extract(year from fecha) = p_anio)
  ), '[]'::jsonb)
);
$function$
;

-- ---------- produccion_maestro_bundle ----------
CREATE OR REPLACE FUNCTION "GP2".produccion_maestro_bundle(p_desde date DEFAULT NULL::date, p_hasta date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
with lims as (
  select coalesce(p_desde, p_hasta, current_date) as d0,
         coalesce(p_hasta, p_desde, current_date) as d1
)
select jsonb_build_object(
  'desde', (select to_char(d0,'YYYY-MM-DD') from lims),
  'hasta', (select to_char(d1,'YYYY-MM-DD') from lims),
  -- lista de matrices (solo cajones, uni>0) para el filtro
  'matrices', coalesce((
    select jsonb_agg(jsonb_build_object('n_matriz', m, 'nombre', nm) order by m)
    from (
      select matriz_raw m,
             (array_agg(nombre_matriz) filter (where nombre_matriz is not null and nombre_matriz <> ''))[1] nm
      from "GP2".produccion
      where matriz_raw is not null and matriz_raw <> '' and coalesce(uni,0) > 0
      group by matriz_raw
    ) q
  ), '[]'::jsonb),
  -- mapa legajo -> nombre para el filtro operario (no existe tabla Empleados en GP2)
  'empleados', coalesce((
    select jsonb_object_agg(legajo, nom)
    from (
      select legajo,
             (array_agg(nombre_empleado) filter (where nombre_empleado is not null and nombre_empleado <> ''))[1] nom
      from "GP2".produccion
      where legajo is not null and legajo <> ''
      group by legajo
    ) e
  ), '{}'::jsonb),
  -- filas del periodo (cajones + tiempos muertos), excluye soft-deletes
  'rows', coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', id,
      'fecha', to_char((fecha at time zone 'America/Argentina/Buenos_Aires'), 'YYYY-MM-DD'),
      'legajo', legajo,
      'nombre_empleado', nombre_empleado,
      'matriz', matriz_raw,
      'nombre_matriz', nombre_matriz,
      'uni', uni,
      'hora_inicio', to_char(hora_inicio, 'HH24:MI:SS'),
      'hora_fin', to_char(hora_fin, 'HH24:MI:SS'),
      'segundos_trabajados', segundos_trabajados,
      'segundos_tiempo_muerto', segundos_tiempo_muerto,
      'premio', premio,
      'tiempo_toma', tiempo_toma,
      'tiempo_historico', tiempo_historico,
      'dia', dia,
      'mes', mes,
      'revisado', revisado
    ) order by fecha desc, hora_inicio desc)
    from "GP2".produccion, lims
    where (eliminar is null or eliminar <> 'S')
      and (fecha at time zone 'America/Argentina/Buenos_Aires')::date between lims.d0 and lims.d1
  ), '[]'::jsonb)
);
$function$
;

-- ---------- programa_bundle ----------
CREATE OR REPLACE FUNCTION "GP2".programa_bundle()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
with ruta_fleje as (
  -- fleje de la ruta = entrada del paso 1 de tipo 'ingreso' cuando es un componente del Sector Fleje (5)
  select distinct on (rp.ruta_id) rp.ruta_id, rp.comp_entrada_id fl
  from "GP2".ruta_paso rp
  join "GP2".componente c on c.id = rp.comp_entrada_id and c.sector_id = 5
  where rp.tipo_paso = 'ingreso' and rp.orden = 1
  order by rp.ruta_id, rp.orden
),
rutas_full as (
  select r.id, r.nombre nom, rf.fl f, r.articulo_id a
  from "GP2".ruta r left join ruta_fleje rf on rf.ruta_id = r.id
)
select jsonb_build_object(
  'art', (select jsonb_agg(jsonb_build_object('id',id,'cod',codigo,'fam',familia) order by id) from "GP2".articulo),
  'comp', (select jsonb_object_agg(id::text, jsonb_build_object('cod',codigo,'d',descripcion,'s',sector_id)) from "GP2".componente),
  'fl', '{}'::jsonb,
  -- 'p' (primera matriz del fleje) = tiene partes_por_kilo_de_fleje cargado
  'mat', (select jsonb_object_agg(id::text, jsonb_build_object('n',n_matriz,'d',descripcion,'t',tipo,'r',partes_por_kilo_de_fleje,'p',(partes_por_kilo_de_fleje is not null))) from "GP2".matriz),
  'prov', (select jsonb_object_agg(id::text, jsonb_build_object('n',nombre,'p',proceso)) from "GP2".proveedor_servicio),
  'tall', (select jsonb_object_agg(id::text, nombre) from "GP2".tallerista),
  'bom', (select jsonb_agg(jsonb_build_object('a',articulo_id,'c',componente_id,'q',cantidad)) from "GP2".articulo_componente),
  'children', (select jsonb_object_agg(componente_padre_id::text, arr) from (
       select componente_padre_id, jsonb_agg(jsonb_build_object('c',componente_hijo_id,'q',cantidad)) arr
       from "GP2".componente_bom where componente_padre_id is not null group by componente_padre_id) x),
  'rutas', (select jsonb_agg(jsonb_build_object('id',id,'nom',nom,'f',f,'a',a) order by id) from rutas_full),
  'rp', (select jsonb_object_agg(ruta_id::text, arr) from (
       select rp.ruta_id, jsonb_agg(jsonb_build_object('o',rp.orden,'tp',rp.tipo_paso,'m',rp.matriz_id,'pr',rp.proveedor_id,'ta',rp.tallerista_id,'ce',rp.comp_entrada_id,'cs',rp.comp_salida_id,
            'fl', case when rp.tipo_paso = 'ingreso' and rp.orden = 1 and ce.sector_id = 5 then rp.comp_entrada_id end,
            'a',  case when rp.tipo_paso = 'virgilio' then r.articulo_id end) order by rp.orden) arr
       from "GP2".ruta_paso rp
       left join "GP2".componente ce on ce.id = rp.comp_entrada_id
       left join "GP2".ruta r on r.id = rp.ruta_id
       where rp.ruta_id is not null group by rp.ruta_id) x),
  'tall_art', (select jsonb_object_agg(a::text, arr) from (
       select r.articulo_id a, jsonb_agg(distinct t.nombre) arr
       from "GP2".ruta_paso rp join "GP2".ruta r on r.id = rp.ruta_id join "GP2".tallerista t on t.id = rp.tallerista_id
       join "GP2".componente cs on cs.id = rp.comp_salida_id
       where rp.tallerista_id is not null and r.articulo_id is not null and cs.sector_id = 12 group by r.articulo_id) x),
  'sect', (select jsonb_object_agg(id::text, jsonb_build_object('t',tipo)) from "GP2".sector),
  'rutas_by_art', (select jsonb_object_agg(a::text, arr) from (
       select a, jsonb_agg(jsonb_build_object('id',id,'nom',nom,'f',f,'a',a) order by id) arr
       from rutas_full where a is not null group by a) x)
);
$function$
;

-- ---------- proporciones_bundle ----------
CREATE OR REPLACE FUNCTION "GP2".proporciones_bundle()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
WITH pares AS (
  SELECT DISTINCT
    t.id AS tall_id, t.nombre AS tall_nombre, t.cod_prov,
    a.id AS art_id, a.codigo AS art_codigo, a.familia,
    cs.codigo AS parte_cod, cs.descripcion AS parte_desc
  FROM ruta_paso rp
  JOIN ruta r      ON r.id = rp.ruta_id
  JOIN tallerista t ON t.id = rp.tallerista_id
  JOIN articulo a  ON a.id = r.articulo_id
  LEFT JOIN componente cs ON cs.id = rp.comp_salida_id
  WHERE rp.tallerista_id IS NOT NULL AND r.articulo_id IS NOT NULL
),
art_tall AS (
  SELECT art_id, count(DISTINCT tall_id) AS num_tall
  FROM pares GROUP BY art_id
),
tap AS (
  SELECT tall_id, tall_nombre, cod_prov, art_id, art_codigo, familia,
         jsonb_agg(DISTINCT jsonb_build_object('cod', parte_cod, 'desc', parte_desc))
           FILTER (WHERE parte_cod IS NOT NULL) AS partes
  FROM pares
  GROUP BY tall_id, tall_nombre, cod_prov, art_id, art_codigo, familia
),
por_tallerista AS (
  SELECT tap.tall_id, tap.tall_nombre, tap.cod_prov,
    jsonb_agg(
      jsonb_build_object(
        'art_id', tap.art_id, 'art_codigo', tap.art_codigo, 'familia', tap.familia,
        'partes', COALESCE(tap.partes, '[]'::jsonb),
        'num_talleristas', at.num_tall,
        'compartido', (at.num_tall >= 2),
        'proporcion_pct', NULL
      ) ORDER BY tap.art_codigo
    ) AS articulos,
    count(*) FILTER (WHERE at.num_tall >= 2) AS n_compartidos
  FROM tap JOIN art_tall at USING (art_id)
  GROUP BY tap.tall_id, tap.tall_nombre, tap.cod_prov
),
compartidos AS (
  SELECT tap.art_id, tap.art_codigo, tap.familia, at.num_tall,
    jsonb_agg(
      jsonb_build_object(
        'tall_id', tap.tall_id, 'tallerista', tap.tall_nombre,
        'partes', COALESCE(tap.partes, '[]'::jsonb),
        'proporcion_pct', NULL
      ) ORDER BY tap.tall_nombre
    ) AS talleristas
  FROM tap JOIN art_tall at USING (art_id)
  WHERE at.num_tall >= 2
  GROUP BY tap.art_id, tap.art_codigo, tap.familia, at.num_tall
)
SELECT jsonb_build_object(
  'generado_en', now(),
  'proporcion_disponible', false,
  'nota', 'La proporcion exacta (% de volumen por tallerista) no existe en GP2: la tabla vieja Proporcion_Articulo_Tallerista estaba vacia y ruta_paso no registra reparto de volumen. Se muestra la relacion tallerista -> articulos/partes derivada de ruta_paso; la proporcion queda PENDIENTE.',
  'talleristas', COALESCE((
     SELECT jsonb_agg(jsonb_build_object(
        'id', tall_id, 'nombre', tall_nombre, 'cod_prov', cod_prov,
        'n_compartidos', n_compartidos, 'articulos', articulos
     ) ORDER BY tall_nombre) FROM por_tallerista), '[]'::jsonb),
  'articulos_compartidos', COALESCE((
     SELECT jsonb_agg(jsonb_build_object(
        'art_id', art_id, 'art_codigo', art_codigo, 'familia', familia,
        'num_talleristas', num_tall, 'talleristas', talleristas
     ) ORDER BY art_codigo) FROM compartidos), '[]'::jsonb)
);
$function$
;

-- ---------- recalcular_maximos_cajones ----------
CREATE OR REPLACE FUNCTION "GP2".recalcular_maximos_cajones()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
declare
  v_caj numeric;
  v_set int := 0;
  v_clr int := 0;
begin
  select valor into v_caj from parametro where clave = 'max_cajones_x_ubicacion';
  if v_caj is null or v_caj <= 0 then v_caj := 5; end if;

  with objetivo as (
    select i.id as inv_id,
           case when c.uni_x_cajon > 0 then round(v_caj * c.uni_x_cajon) end as max_nuevo
    from inventario i
    join ubicacion u on u.id = i.ubicacion_id and u.tipo = 'sector'
    join componente c on c.id = i.componente_id and c.sector_id = u.ref_id
    where c.sector_id in (1, 2)
      and coalesce(i.maximo_origen, '') <> 'fisico'
  ), upd as (
    update inventario i
    set maximo = o.max_nuevo, maximo_origen = 'cinco_cajones'
    from objetivo o
    where i.id = o.inv_id and o.max_nuevo > 0
      and (i.maximo is distinct from o.max_nuevo or i.maximo_origen is distinct from 'cinco_cajones')
    returning 1
  ), clr as (
    -- sin uni_x_cajon no hay maximo calculable: queda null y se lista pendiente
    update inventario i
    set maximo = null, maximo_origen = null
    from objetivo o
    where i.id = o.inv_id and o.max_nuevo is null
      and (i.maximo is not null or i.maximo_origen is not null)
    returning 1
  )
  select (select count(*) from upd), (select count(*) from clr) into v_set, v_clr;
  return jsonb_build_object('ok', true, 'max_cajones', v_caj, 'actualizados', v_set, 'sin_uni_x_cajon', v_clr);
end $function$
;

-- ---------- recalcular_maximos_insumos ----------
CREATE OR REPLACE FUNCTION "GP2".recalcular_maximos_insumos()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
declare v_set int := 0; v_clr int := 0;
begin
  -- Solo sectores de insumo, solo ubicaciones con meses_stock, y nunca sobre un maximo
  -- 'fisico' (el que el usuario fijo a mano por el lugar que hay).
  with objetivo as (
    select inv_id, max_calc as max_nuevo
      from v_nivel_stock
     where es_insumo
       and meses_stock is not null
       and coalesce(maximo_origen,'') <> 'fisico'
  ), upd as (
    update inventario i
    set maximo = o.max_nuevo, maximo_origen = 'est_madre'
    from objetivo o
    where i.id = o.inv_id and o.max_nuevo > 0
      and (i.maximo is distinct from o.max_nuevo or i.maximo_origen is distinct from 'est_madre')
    returning 1
  ), clr as (
    update inventario i
    set maximo = null, maximo_origen = null
    from objetivo o
    where i.id = o.inv_id and o.max_nuevo <= 0 and i.maximo_origen = 'est_madre'
    returning 1
  )
  select (select count(*) from upd), (select count(*) from clr) into v_set, v_clr;
  return jsonb_build_object('ok', true, 'actualizados', v_set, 'limpiados', v_clr);
end $function$
;

-- ---------- recalcular_minimos ----------
CREATE OR REPLACE FUNCTION "GP2".recalcular_minimos()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
declare v_set int := 0;
begin
  -- Solo ubicaciones de SECTOR y solo el sector propio del componente (v_nivel_stock). Los
  -- minimos de tallerista y de proveedor de servicio NO se tocan: tienen otro origen.
  -- Tampoco se toca la fila cuyo consumo es 0 o desconocido: ahi el minimo original del
  -- usuario es mejor dato que un cero calculado. No se inventa ni se borra.
  with objetivo as (
    select inv_id, min_calc as min_nuevo
      from v_nivel_stock
     where meses_minimo is not null
  ), upd as (
    update inventario i
       set minimo = o.min_nuevo, minimo_origen = 'consumo'
      from objetivo o
     where i.id = o.inv_id
       and o.min_nuevo > 0
       and (i.minimo is distinct from o.min_nuevo or i.minimo_origen is distinct from 'consumo')
    returning 1
  )
  select count(*) into v_set from upd;
  return jsonb_build_object('ok', true, 'actualizados', v_set);
end $function$
;

-- ---------- recepcion_bundle ----------
CREATE OR REPLACE FUNCTION "GP2".recepcion_bundle()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
  select jsonb_build_object(
    'insumos', (select coalesce(jsonb_agg(jsonb_build_object(
        'comp_id',c.id,'codigo',c.codigo,'descripcion',c.descripcion,'sector',s.nombre,
        'sector_id',c.sector_id,'um',c.unidad_medida,'uni_x_cajon',c.uni_x_cajon,
        'proveedor',nullif(trim(c.proveedor),''),
        'marca',c.marca, 'carton_formato',c.carton_formato, 'es_pliego',c.es_pliego,
        'paq_x_bolsa',cf.paq_x_bolsa, 'uni_x_bolsa_cat',cf.uni_x_bolsa, 'kg_x_uni',c.kg_x_uni,
        'n_fleje',fd.n_fleje,'medida',fd.medida_mm,
        'stock', coalesce((select sum(i.cantidad) from "GP2".inventario i
                    where i.componente_id = c.id and i.ubicacion_id = "GP2".ubic_de('sector', c.sector_id)),0),
        'ultima', (select jsonb_build_object('fecha',r.fecha,'cantidad',r.cantidad,'unidad',r.unidad,
                     'rollos',r.rollos,'pallets',r.pallets,'remito',r.remito,'proveedor',r.proveedor)
                     from "GP2".recepcion_insumo r where r.componente_id=c.id order by r.id desc limit 1),
        'oc_pend', (select case when count(*)=0 then null else jsonb_build_object(
                       'ocs', string_agg(distinct o.numero::text, ', '),
                       'n_ocs', count(distinct o.id),
                       'pendiente', sum(i.cantidad - coalesce(i.recibido,0)),
                       'unidad', min(i.unidad),
                       'unidades_mezcladas',(count(distinct i.unidad)>1)) end
                     from "GP2".orden_compra o join "GP2".orden_compra_item i on i.oc_id=o.id
                    where i.componente_id=c.id and o.estado in ('borrador','enviada')
                      and i.cantidad > coalesce(i.recibido,0))
      ) order by s.nombre, c.codigo),'[]'::jsonb)
      from "GP2".componente c
      join "GP2".sector s on s.id=c.sector_id
      left join "GP2".fleje_detalle fd on fd.componente_id=c.id
      left join "GP2".carton_formato cf on cf.nombre=c.carton_formato
      where ("GP2"._es_sector_insumo(c.sector_id)
             or trim(coalesce(c.proveedor,'')) in ('Resortes Charcas','Eclipse'))
        and c.estado_compra is null),
    'proveedores', (select coalesce(jsonb_agg(jsonb_build_object(
        'nombre',p.nombre,'modo_control',p.modo_control,
        'informa_rollos',(p.modo_control='rollos_remito'),
        'factura_uni',p.factura_uni) order by p.nombre),'[]'::jsonb)
      from "GP2".proveedor_insumo p where p.activo),
    'sectores', (select coalesce(jsonb_agg(jsonb_build_object('id',s.id,'nombre',s.nombre) order by s.nombre),'[]'::jsonb)
      from "GP2".sector s where "GP2"._es_sector_insumo(s.id)),
    'recepciones', (select coalesce(jsonb_agg(to_jsonb(v) order by v.recepcion_id desc),'[]'::jsonb)
      from (select * from "GP2".v_recepcion_control order by recepcion_id desc limit 200) v),
    'pallets', (select coalesce(jsonb_agg(to_jsonb(vp) order by vp.recepcion_id desc, vp.nro_pallet),'[]'::jsonb)
      from "GP2".v_control_pallet vp),
    'rollos', (select coalesce(jsonb_agg(jsonb_build_object(
        'control_id',cr.control_id,'cantidad',cr.cantidad,'kg_por_rollo',cr.kg_por_rollo) order by cr.id),'[]'::jsonb)
      from "GP2".recepcion_control_rollo cr),
    'tara', "GP2".recepcion_tara()
  );
$function$
;

-- ---------- recepcion_tara ----------
CREATE OR REPLACE FUNCTION "GP2".recepcion_tara()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
  select (select coalesce(jsonb_object_agg(clave, valor), '{}'::jsonb) from parametro
           where clave like 'tara_pallet%' or clave in ('tol_ctrl_peso_pct','carton_uni_x_paquete'))
      || coalesce((select jsonb_build_object('tara_estimada', round(avg(tara),1), 'tara_n', count(*))
                     from v_tara_pallet_real where tara between 1 and 15
                   having count(*) >= 5), '{}'::jsonb)
      || jsonb_build_object('tara_por_proveedor',
           coalesce((select jsonb_object_agg(proveedor, jsonb_build_object('tara', t, 'n', n))
                       from (select proveedor, round(avg(tara),1) t, count(*) n
                               from v_tara_pallet_real
                              where tara between 1 and 15 and proveedor is not null
                              group by proveedor having count(*) >= 5) x), '{}'::jsonb));
$function$
;

-- ---------- recepcion_virgilio ----------
CREATE OR REPLACE FUNCTION "GP2".recepcion_virgilio(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
declare
  v_fecha   timestamptz := coalesce(nullif(p->>'fecha','')::timestamptz, now());
  v_tipo    text := lower(coalesce(p->>'origen_tipo',''));
  v_oid     bigint := nullif(p->>'origen_id','')::bigint;
  v_dry     boolean := coalesce((p->>'dry_run')::boolean, false);
  v_uvirg   bigint; v_uorig bigint;
  it jsonb; v_art record; v_compfin bigint; v_qty numeric; v_prin record; r record;
  v_movs jsonb := '[]'::jsonb; v_n int := 0;
begin
  v_uvirg := "GP2".ubic_de('virgilio');
  if v_uvirg is null then raise exception 'No existe la ubicacion de Virgilio'; end if;
  if v_tipo not in ('tallerista','proveedor_at','proveedor_servicio','interno') then
    raise exception 'origen_tipo invalido: %', v_tipo;
  end if;
  if v_tipo <> 'interno' then
    v_uorig := "GP2".ubic_de(v_tipo, v_oid);
    if v_uorig is null then raise exception 'El origen % % no tiene ubicacion', v_tipo, v_oid; end if;
  end if;

  for it in select * from jsonb_array_elements(coalesce(p->'items','[]'::jsonb)) loop
    v_qty := coalesce((it->>'cantidad')::numeric, 0);
    if v_qty <= 0 then continue; end if;
    select a.id, a.codigo into v_art from articulo a
     where a.id = nullif(it->>'articulo_id','')::bigint or a.codigo = nullif(it->>'codigo','') limit 1;
    if v_art.id is null then raise exception 'Articulo no encontrado: %', coalesce(it->>'codigo', it->>'articulo_id'); end if;
    select c.id into v_compfin from componente c where c.sector_id=12 and c.codigo=v_art.codigo limit 1;
    if v_compfin is null then raise exception 'El articulo % no tiene componente terminado', v_art.codigo; end if;
    select ac.componente_id, ac.cantidad, c.sector_id into v_prin
      from articulo_componente ac join componente c on c.id=ac.componente_id
     where ac.articulo_id=v_art.id
     order by (c.sector_id=2) desc, ac.cantidad desc, ac.componente_id limit 1;
    if v_prin.componente_id is null then raise exception 'El articulo % no tiene receta', v_art.codigo; end if;

    for r in select ac.componente_id, ac.cantidad, c.sector_id
               from articulo_componente ac join componente c on c.id=ac.componente_id
              where ac.articulo_id=v_art.id and ac.componente_id<>v_prin.componente_id loop
      v_movs := v_movs || jsonb_build_object(
        'tipo_mov','consumo_virgilio','comp_id',r.componente_id,
        'ubic_origen_id', case when v_tipo='interno'
          then "GP2".ubic_de('sector', r.sector_id)
          else v_uorig end,
        'ubic_destino_id',null,'cantidad',v_qty*r.cantidad);
    end loop;

    v_movs := v_movs || jsonb_build_object(
      'tipo_mov','recepcion_virgilio','comp_id',v_prin.componente_id,
      'ubic_origen_id', case when v_tipo='interno'
        then "GP2".ubic_de('sector', v_prin.sector_id)
        else v_uorig end,
      'ubic_destino_id',v_uvirg,'cantidad',v_qty*v_prin.cantidad,
      'comp_transformado_id',v_compfin,'cantidad_transformada',v_qty);
    v_n := v_n+1;
  end loop;

  if v_dry then return jsonb_build_object('ok',true,'dry_run',true,'articulos',v_n,'movimientos',v_movs); end if;

  insert into movimiento(fecha,tipo_mov,comp_id,ubic_origen_id,ubic_destino_id,cantidad,unidad_origen,
                         comp_transformado_id,cantidad_transformada,unidad_destino)
  select v_fecha, m->>'tipo_mov', (m->>'comp_id')::bigint,
         nullif(m->>'ubic_origen_id','')::bigint, nullif(m->>'ubic_destino_id','')::bigint,
         (m->>'cantidad')::numeric,'uni',
         nullif(m->>'comp_transformado_id','')::bigint, nullif(m->>'cantidad_transformada','')::numeric,'uni'
  from jsonb_array_elements(v_movs) m;

  return jsonb_build_object('ok',true,'articulos',v_n,'movimientos',jsonb_array_length(v_movs));
end $function$
;

-- ---------- registrar_evento_prod ----------
CREATE OR REPLACE FUNCTION "GP2".registrar_evento_prod(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
declare
  v_id bigint; v_f timestamptz; v_f_ar timestamp; v_leg text; v_mat text; v_uni numeric;
  v_mid bigint; v_mname text; v_partes numeric; v_nombre text;
  v_nsal int; v_salida bigint; v_entrada bigint;
  v_ent_um text; v_sal_um text; v_sec_ent int; v_sec_sal int;
  v_uent bigint; v_usal bigint; v_cant numeric; v_uo text; v_ud text;
  v_movid bigint; v_aviso text;
  v_th numeric; v_tt numeric; v_premio numeric; v_segs numeric;
  v_golpes numeric; v_uxg numeric;
begin
  v_f   := coalesce(nullif(p->>'fecha','')::timestamptz, now());
  v_f_ar := v_f at time zone 'America/Argentina/Buenos_Aires';
  v_leg := nullif(btrim(coalesce(p->>'legajo','')),'');
  v_mat := nullif(btrim(coalesce(p->>'matriz','')),'');
  v_golpes := nullif(p->>'golpes','')::numeric;
  if v_leg is null then raise exception 'Falta el legajo'; end if;
  if v_mat is null then raise exception 'Falta la matriz/codigo del evento'; end if;

  select nombre into v_nombre from empleado where legajo = v_leg;
  select id, descripcion, partes_por_kilo_de_fleje, tiempo_historico, uni_x_golpe
    into v_mid, v_mname, v_partes, v_th, v_uxg
    from matriz where btrim(n_matriz) = v_mat limit 1;

  -- golpes -> unidades con el factor de la matriz (foto del factor al momento del registro)
  if v_golpes is not null and v_golpes > 0 then
    v_uni := v_golpes * coalesce(v_uxg,1);
  else
    v_golpes := null;
    v_uni := coalesce(nullif(p->>'uni','')::numeric, 0);
  end if;

  -- premio nativo: tiempo_toma = segundos trabajados / uni; premio contra el historico
  if v_uni > 0 then
    v_segs := nullif(p->>'segundos_trabajados','')::numeric;
    v_tt := coalesce(nullif(p->>'tiempo_toma','')::numeric,
                     case when v_segs > 0 then round((v_segs / v_uni)::numeric, 4) end);
    if v_tt is not null and v_th is not null and v_th > 0 then
      v_premio := round(((-(v_tt / v_th) + 1) * 10)::numeric, 2);
    end if;
  end if;

  insert into produccion(
    fecha, legajo, nombre_empleado, matriz_raw, matriz_id, nombre_matriz, uni,
    golpes, uni_x_golpe,
    hora_inicio, hora_fin, tiempo_toma, tiempo_historico, premio,
    segundos_trabajados, segundos_tiempo_muerto,
    dia, mes, quincena, id_ejecucion, origen_created_at
  ) values (
    v_f, v_leg, coalesce(nullif(p->>'nombre_empleado',''), v_nombre), v_mat, v_mid,
    coalesce(nullif(p->>'nombre_matriz',''), v_mname), v_uni,
    v_golpes, case when v_golpes is not null then coalesce(v_uxg,1) end,
    nullif(p->>'hora_inicio','')::time, nullif(p->>'hora_fin','')::time,
    v_tt, case when v_uni > 0 then v_th end, v_premio,
    nullif(p->>'segundos_trabajados','')::numeric,
    nullif(p->>'segundos_tiempo_muerto','')::numeric,
    extract(day from v_f_ar)::int, extract(month from v_f_ar)::int,
    case when extract(day from v_f_ar)::int <= 15 then 1 else 2 end,
    nullif(p->>'id_ejecucion',''), now()
  )
  on conflict (id_ejecucion) where id_ejecucion is not null do nothing
  returning id into v_id;

  -- reintento del mismo evento (id_ejecucion ya registrado): devolver el existente sin tocar stock
  if v_id is null then
    select id into v_id from produccion where id_ejecucion = nullif(p->>'id_ejecucion','');
    return jsonb_build_object('ok',true,'id',v_id,'dup',true);
  end if;

  if v_uni > 0 and v_mid is not null and coalesce(p->>'mover_stock','true') <> 'false' then
    v_salida := nullif(p->>'comp_salida_id','')::bigint;
    if v_salida is not null then
      if not exists(select 1 from ruta_paso where matriz_id=v_mid and comp_salida_id=v_salida) then
        v_aviso := 'Sin stock: la pieza elegida no corresponde a la matriz'; v_salida := null;
      end if;
    else
      select count(distinct comp_salida_id) into v_nsal
        from ruta_paso where matriz_id=v_mid and tipo_paso='matriz' and comp_salida_id is not null;
      if v_nsal = 1 then
        select distinct comp_salida_id into v_salida from ruta_paso
         where matriz_id=v_mid and tipo_paso='matriz' and comp_salida_id is not null;
      elsif v_nsal > 1 then v_aviso := 'Sin stock: la matriz produce varias piezas (falta comp_salida_id)';
      end if;
    end if;
    if v_salida is not null then
      select comp_entrada_id into v_entrada from ruta_paso
       where matriz_id=v_mid and comp_salida_id=v_salida and comp_entrada_id is not null limit 1;
      if v_entrada is not null then
        select unidad_medida, sector_id into v_ent_um, v_sec_ent from componente where id=v_entrada;
        select unidad_medida, sector_id into v_sal_um, v_sec_sal from componente where id=v_salida;
        v_uent := "GP2".ubic_de('sector', v_sec_ent);
        v_usal := "GP2".ubic_de('sector', v_sec_sal);
        if lower(coalesce(v_ent_um,''))='kg' then
          if v_partes is null or v_partes<=0 then
            v_aviso := 'Sin stock: la matriz no tiene piezas/kg cargadas';
          else v_cant := v_uni / v_partes; v_uo := 'kg'; end if;
        else v_cant := v_uni; v_uo := 'uni'; end if;
        v_ud := case when lower(coalesce(v_sal_um,''))='kg' then 'kg' else 'uni' end;
        if v_cant is not null and v_uent is not null and v_usal is not null then
          insert into movimiento(fecha,tipo_mov,comp_id,ubic_origen_id,ubic_destino_id,cantidad,unidad_origen,
                                 comp_transformado_id,cantidad_transformada,unidad_destino)
          values (v_f,'fabricacion', v_entrada, v_uent, v_usal, v_cant, v_uo, v_salida, v_uni, v_ud)
          returning id into v_movid;
        end if;
      else v_aviso := 'Sin stock: la matriz no tiene entrada en las rutas';
      end if;
    end if;
  end if;

  return jsonb_build_object('ok',true,'id',v_id,'movimiento_id',v_movid,'aviso',v_aviso,
    'premio',v_premio,'uni',v_uni,'golpes',v_golpes,'uni_x_golpe',v_uxg);
end $function$
;

-- ---------- registrar_movimientos ----------
CREATE OR REPLACE FUNCTION "GP2".registrar_movimientos(p_rows jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
declare r jsonb; ids bigint[]:='{}'; new_id bigint;
begin
  if jsonb_typeof(p_rows) <> 'array' then raise exception 'p_rows debe ser un array JSON'; end if;
  if jsonb_array_length(p_rows)=0 then raise exception 'No hay movimientos para registrar'; end if;
  for r in select * from jsonb_array_elements(p_rows) loop
    insert into "GP2".movimiento(
      fecha, tipo_mov, comp_id, ubic_origen_id, ubic_destino_id, cantidad,
      unidad_origen, comp_transformado_id, cantidad_transformada, unidad_destino,
      cajones, faltante
    ) values (
      coalesce(nullif(r->>'fecha','')::timestamptz, now()),
      r->>'tipo_mov',
      nullif(r->>'comp_id','')::bigint,
      nullif(r->>'ubic_origen_id','')::bigint,
      nullif(r->>'ubic_destino_id','')::bigint,
      coalesce(nullif(r->>'cantidad','')::numeric, 0),
      coalesce(nullif(r->>'unidad_origen',''),'uni'),
      nullif(r->>'comp_transformado_id','')::bigint,
      nullif(r->>'cantidad_transformada','')::numeric,
      coalesce(nullif(r->>'unidad_destino',''),'uni'),
      nullif(r->>'cajones','')::numeric,
      coalesce(nullif(r->>'faltante','')::boolean, false)
    ) returning id into new_id;
    ids := ids || new_id;
  end loop;
  return jsonb_build_object('ok', true, 'ids', to_jsonb(ids), 'n', coalesce(array_length(ids,1),0));
end $function$
;

-- ---------- registrar_produccion ----------
CREATE OR REPLACE FUNCTION "GP2".registrar_produccion(p_legajo text, p_matriz text, p_uni numeric DEFAULT NULL::numeric, p_fecha timestamp with time zone DEFAULT now(), p_nombre text DEFAULT NULL::text, p_comp_salida_id bigint DEFAULT NULL::bigint, p_golpes numeric DEFAULT NULL::numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
declare
  v_mid bigint; v_mname text; v_partes numeric; v_id bigint; v_f timestamptz;
  v_nsal int; v_salida bigint; v_entrada bigint;
  v_ent_um text; v_sal_um text; v_sec_ent int; v_sec_sal int;
  v_uent bigint; v_usal bigint; v_cant numeric; v_uo text; v_ud text;
  v_movid bigint; v_aviso text := null;
  v_uxg numeric; v_uni numeric;
begin
  if p_matriz is null or btrim(p_matriz)='' then raise exception 'La matriz es obligatoria'; end if;
  v_f := coalesce(p_fecha, now());
  select id, descripcion, partes_por_kilo_de_fleje, uni_x_golpe
    into v_mid, v_mname, v_partes, v_uxg
    from matriz where btrim(n_matriz)=btrim(p_matriz) limit 1;
  if v_mid is null then raise exception 'La matriz "%" no existe en GP2', p_matriz; end if;

  -- golpes manda; si no vienen golpes se acepta el numero de unidades como antes
  if p_golpes is not null then
    if p_golpes<=0 then raise exception 'Los golpes deben ser mayores a 0'; end if;
    v_uni := p_golpes * coalesce(v_uxg,1);
  else
    v_uni := p_uni;
  end if;
  if v_uni is null or v_uni<=0 then raise exception 'Las unidades deben ser mayores a 0'; end if;

  select count(distinct comp_salida_id) into v_nsal
    from ruta_paso where matriz_id=v_mid and tipo_paso='matriz' and comp_salida_id is not null;
  if p_comp_salida_id is not null then
    if exists(select 1 from ruta_paso where matriz_id=v_mid and comp_salida_id=p_comp_salida_id)
      then v_salida := p_comp_salida_id;
      else raise exception 'La pieza elegida no corresponde a la matriz %', p_matriz; end if;
  elsif v_nsal=1 then
    select distinct comp_salida_id into v_salida from ruta_paso where matriz_id=v_mid and tipo_paso='matriz' and comp_salida_id is not null;
  elsif v_nsal>1 then
    raise exception 'La matriz % produce varias piezas: elegi cual (p_comp_salida_id)', p_matriz;
  end if;
  if v_salida is not null then
    select comp_entrada_id into v_entrada from ruta_paso
      where matriz_id=v_mid and comp_salida_id=v_salida and comp_entrada_id is not null limit 1;
  end if;

  insert into produccion(fecha, legajo, nombre_empleado, matriz_raw, matriz_id, nombre_matriz, uni,
                         golpes, uni_x_golpe, dia, mes, quincena, origen_created_at)
  values (v_f, nullif(btrim(coalesce(p_legajo,'')),''), nullif(btrim(coalesce(p_nombre,'')),''),
          btrim(p_matriz), v_mid, v_mname, v_uni,
          p_golpes, case when p_golpes is not null then coalesce(v_uxg,1) end,
          extract(day from (v_f at time zone 'America/Argentina/Buenos_Aires'))::int, extract(month from (v_f at time zone 'America/Argentina/Buenos_Aires'))::int,
          case when extract(day from (v_f at time zone 'America/Argentina/Buenos_Aires'))::int <= 15 then 1 else 2 end, now())
  returning id into v_id;

  if v_salida is not null and v_entrada is not null then
    select unidad_medida, sector_id into v_ent_um, v_sec_ent from componente where id=v_entrada;
    select unidad_medida, sector_id into v_sal_um, v_sec_sal from componente where id=v_salida;
    v_uent := "GP2".ubic_de('sector', v_sec_ent);
    v_usal := "GP2".ubic_de('sector', v_sec_sal);
    if lower(coalesce(v_ent_um,''))='kg' then
      if v_partes is null or v_partes<=0 then v_aviso := 'Registrado, pero NO se movio stock: la matriz no tiene rendimiento (ppk) para pasar uni->kg de fleje';
      else v_cant := v_uni / v_partes; v_uo := 'kg'; end if;
    else
      v_cant := v_uni; v_uo := 'uni';
    end if;
    v_ud := case when lower(coalesce(v_sal_um,''))='kg' then 'kg' else 'uni' end;
    if v_cant is not null and v_uent is not null and v_usal is not null then
      insert into movimiento(fecha,tipo_mov,comp_id,ubic_origen_id,ubic_destino_id,cantidad,unidad_origen,
                             comp_transformado_id,cantidad_transformada,unidad_destino)
      values (v_f,'fabricacion', v_entrada, v_uent, v_usal, v_cant, v_uo, v_salida, v_uni, v_ud)
      returning id into v_movid;
    elsif v_aviso is null then v_aviso := 'Registrado, pero NO se movio stock: falta ubicacion de sector';
    end if;
  else
    v_aviso := 'Registrado (solo produccion): la matriz no tiene entrada/salida resuelta en las rutas';
  end if;

  return jsonb_build_object('ok',true,'id',v_id,'matriz',btrim(p_matriz),'nombre_matriz',v_mname,
    'uni',v_uni,'golpes',p_golpes,'uni_x_golpe',v_uxg,'salida_id',v_salida,'movimiento_id',v_movid,'aviso',v_aviso);
end $function$
;

-- ---------- registro_operarios_bundle ----------
CREATE OR REPLACE FUNCTION "GP2".registro_operarios_bundle()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
  select jsonb_build_object(
    'registro_en_golpes', (select coalesce((select valor from "GP2".parametro where clave='registro_en_golpes'),'1') = '1'),
    'empleados', (select coalesce(jsonb_object_agg(e.legajo, jsonb_build_object(
        'nombre',e.nombre,'activo',e.activo,'hora_entrada',e.hora_entrada)),'{}'::jsonb)
      from "GP2".empleado e),
    'matrices', (select coalesce(jsonb_agg(jsonb_build_object(
        'n',m.n_matriz,'d',m.descripcion,'ppk',m.partes_por_kilo_de_fleje,
        'uxg',m.uni_x_golpe,'maq',m.maquina,'act',m.activa) order by m.n_matriz),'[]'::jsonb)
      from "GP2".matriz m),
    'matriz_fleje', (select coalesce(jsonb_object_agg(q.n_matriz, jsonb_build_object(
        'comp_id',q.comp_id,'codigo',q.codigo,'descripcion',q.descripcion)),'{}'::jsonb)
      from (
        select distinct on (m.n_matriz) m.n_matriz, c.id comp_id, c.codigo, c.descripcion
        from "GP2".matriz m
        join "GP2".ruta_paso rp on rp.matriz_id=m.id and rp.tipo_paso='matriz' and rp.comp_entrada_id is not null
        join "GP2".componente c on c.id=rp.comp_entrada_id and c.sector_id=5
        order by m.n_matriz, c.id
      ) q),
    -- El fleje que le toca a CADA pieza de salida. Solo importa donde una matriz corta
    -- de mas de un fleje, pero se manda siempre: la app prefiere esto cuando hay pieza
    -- elegida y cae a 'matriz_fleje' si no lo encuentra.
    'matriz_fleje_pieza', (select coalesce(jsonb_object_agg(t.n_matriz, t.porpieza),'{}'::jsonb)
      from (
        select q.n_matriz,
               jsonb_object_agg(q.comp_salida_id::text, jsonb_build_object(
                 'comp_id',q.comp_id,'codigo',q.codigo,'descripcion',q.descripcion)) porpieza
        from (
          select distinct on (m.n_matriz, rp.comp_salida_id)
                 m.n_matriz, rp.comp_salida_id, c.id comp_id, c.codigo, c.descripcion
          from "GP2".matriz m
          join "GP2".ruta_paso rp on rp.matriz_id=m.id and rp.tipo_paso='matriz'
               and rp.comp_entrada_id is not null and rp.comp_salida_id is not null
          join "GP2".componente c on c.id=rp.comp_entrada_id and c.sector_id=5
          order by m.n_matriz, rp.comp_salida_id, c.id
        ) q
        group by q.n_matriz
      ) t),
    -- Matrices que producen MAS de una pieza: la app pregunta cual se fabrica
    -- y manda comp_salida_id en el evento C para que el stock vaya al lugar correcto.
    'matriz_salidas', (select coalesce(jsonb_object_agg(t.n_matriz, t.salidas),'{}'::jsonb)
      from (
        select m.n_matriz,
               jsonb_agg(jsonb_build_object('comp_id',q.comp_salida_id,'codigo',q.codigo,'descripcion',q.descripcion)
                         order by q.codigo) salidas
        from (
          select distinct rp.matriz_id, rp.comp_salida_id, c.codigo, c.descripcion
          from "GP2".ruta_paso rp
          join "GP2".componente c on c.id=rp.comp_salida_id
          where rp.tipo_paso='matriz' and rp.comp_salida_id is not null
        ) q
        join "GP2".matriz m on m.id=q.matriz_id
        group by m.n_matriz
        having count(*) > 1
      ) t),
    'rollos_saldo', (select coalesce(jsonb_agg(jsonb_build_object(
        'comp_id',v.componente_id,'codigo',v.codigo,'kg_por_rollo',v.kg_por_rollo,'rollos',v.rollos)
        order by v.codigo, v.kg_por_rollo),'[]'::jsonb)
      from "GP2".v_rollo_saldo v where v.rollos <> 0),
    -- Usos de rollo ABIERTOS (ts_fin null): kg usados calculados con lo YA registrado
    -- en produccion; la app suma encima solo lo que tiene en cola sin sincronizar.
    'rollos_abiertos', (select coalesce(jsonb_object_agg(u.legajo, jsonb_build_object(
        'uso_id',u.id,'comp_id',u.componente_id,'codigo',c.codigo,
        'kg_por_rollo',u.kg_por_rollo,'matriz',u.matriz_raw,'ts_inicio',u.ts_inicio,
        'kg_usados', case when m.partes_por_kilo_de_fleje > 0 then round(
            (coalesce((select sum(p.uni) from "GP2".produccion p
                       where p.legajo=u.legajo and p.fecha >= u.ts_inicio and p.uni > 0),0)
            / m.partes_por_kilo_de_fleje)::numeric, 2) else 0 end)),'{}'::jsonb)
      from "GP2".rollo_uso u
      join "GP2".componente c on c.id=u.componente_id
      left join "GP2".matriz m on btrim(m.n_matriz)=btrim(coalesce(u.matriz_raw,''))
      where u.ts_fin is null)
  );
$function$
;

-- ---------- relev_factor ----------
CREATE OR REPLACE FUNCTION "GP2".relev_factor(p_componente_id bigint)
 RETURNS TABLE(factor numeric, envase text, cuenta_kg boolean)
 LANGUAGE sql
 STABLE
 SET search_path TO 'GP2'
AS $function$
  select
    case
      when coalesce(c.relev_solo_sueltas,false) then null
      when c.sector_id = 10 and coalesce(c.es_pliego,false)
        then (select valor::numeric from "GP2".parametro where clave='pliego_uni_x_paquete')
      when c.sector_id = 10
        then (select nullif(cf.uni_x_bolsa,0)
              from "GP2".carton_formato cf where cf.nombre = c.carton_formato)
      when c.sector_id = 11
        then (select valor::numeric from "GP2".parametro where clave='caja_uni_x_paquete')
      when c.sector_id = 5 then null                      -- fleje se cuenta en kg
      else nullif(c.uni_x_cajon, 0)
    end,
    case
      when coalesce(c.relev_solo_sueltas,false) then null  -- sin envase: solo sueltas
      else case c.sector_id
        when 10 then case when coalesce(c.es_pliego,false) then 'Paq. de pliegos' else 'Paquetones' end
        when 11 then 'Paquetes'
        when  6 then 'Bolsas'
        when  7 then 'Bolsas'
        when  9 then 'Cajones'
        when  8 then 'Bolsas'
        else 'Cajones'
      end
    end,
    (c.sector_id = 5 and not coalesce(c.relev_solo_sueltas,false))
  from "GP2".componente c
  where c.id = p_componente_id;
$function$
;

-- ---------- relev_total_uni ----------
CREATE OR REPLACE FUNCTION "GP2".relev_total_uni(p_componente_id bigint, p_envases numeric, p_sueltas numeric, p_kg numeric)
 RETURNS numeric
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'GP2'
AS $function$
DECLARE f numeric; es_kg boolean; env text; um text; kxu numeric;
BEGIN
  SELECT rf.factor, rf.cuenta_kg, rf.envase INTO f, es_kg, env
  FROM "GP2".relev_factor(p_componente_id) rf;
  SELECT c.unidad_medida, nullif(c.kg_x_uni,0) INTO um, kxu
  FROM "GP2".componente c WHERE c.id=p_componente_id;

  IF es_kg THEN
    IF p_kg IS NULL THEN RETURN NULL; END IF;
    IF um = 'kg' THEN RETURN p_kg; END IF;
    IF kxu IS NULL THEN RETURN NULL; END IF;
    RETURN round(p_kg / kxu);
  END IF;

  -- sin envase (solo sueltas): el total es lo suelto y punto
  IF env IS NULL THEN RETURN p_sueltas; END IF;

  IF coalesce(p_envases,0) = 0 THEN RETURN coalesce(p_sueltas,0); END IF;
  IF f IS NULL THEN RETURN NULL; END IF;
  RETURN p_envases * f + coalesce(p_sueltas,0);
END $function$
;

-- ---------- relevamiento_abrir ----------
CREATE OR REPLACE FUNCTION "GP2".relevamiento_abrir(p_sector_id bigint, p_crono_id bigint DEFAULT NULL::bigint, p_encargado text DEFAULT NULL::text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
DECLARE v_id bigint; v_fecha date;
BEGIN
  IF p_sector_id IS NULL THEN
    RAISE EXCEPTION 'Este tipo de conteo todavia no tiene sector asignado';
  END IF;

  SELECT r.id INTO v_id FROM "GP2".relevamiento r
  WHERE r.sector_id = p_sector_id AND r.estado IN ('en_curso','contado')
    AND (p_crono_id IS NULL OR r.cronograma_id IS NOT DISTINCT FROM p_crono_id)
  ORDER BY r.id DESC LIMIT 1;
  IF v_id IS NOT NULL THEN RETURN v_id; END IF;

  SELECT k.fecha INTO v_fecha FROM "GP2".relevamiento_cronograma k WHERE k.id = p_crono_id;

  INSERT INTO "GP2".relevamiento (sector_id, fecha, encargado, cronograma_id)
  VALUES (p_sector_id, coalesce(v_fecha, current_date), nullif(trim(p_encargado),''), p_crono_id)
  RETURNING id INTO v_id;

  INSERT INTO "GP2".relevamiento_item (relevamiento_id, componente_id)
  SELECT v_id, c.id FROM "GP2".componente c WHERE c.sector_id = p_sector_id
  ON CONFLICT DO NOTHING;

  RETURN v_id;
END $function$
;

-- ---------- relevamiento_aplicar ----------
CREATE OR REPLACE FUNCTION "GP2".relevamiento_aplicar(p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
DECLARE v_sector bigint; v_ubic bigint; v_estado text; n_mov int := 0;
BEGIN
  SELECT r.sector_id, r.estado INTO v_sector, v_estado FROM "GP2".relevamiento r WHERE r.id=p_id;
  IF v_sector IS NULL THEN RAISE EXCEPTION 'No existe el relevamiento %', p_id; END IF;
  IF v_estado <> 'contado' THEN RAISE EXCEPTION 'El relevamiento % esta %, no contado', p_id, v_estado; END IF;

  v_ubic := "GP2".ubic_de('sector', v_sector);
  IF v_ubic IS NULL THEN RAISE EXCEPTION 'El sector % no tiene ubicacion', v_sector; END IF;

  WITH cand AS (
    SELECT ri.componente_id, ri.total_uni,
           coalesce((SELECT i.cantidad FROM "GP2".inventario i
                     WHERE i.componente_id = ri.componente_id AND i.ubicacion_id = v_ubic
                     LIMIT 1), 0) AS stock_hoy,
           c.unidad_medida
    FROM "GP2".relevamiento_item ri
    JOIN "GP2".componente c ON c.id = ri.componente_id
    WHERE ri.relevamiento_id = p_id AND ri.decision = 'conteo' AND ri.total_uni IS NOT NULL
  ), ins AS (
    INSERT INTO "GP2".movimiento
      (fecha, tipo_mov, comp_id, ubic_origen_id, ubic_destino_id, cantidad,
       unidad_origen, unidad_destino)
    SELECT now(), 'ajuste', cand.componente_id, NULL, v_ubic,
           (cand.total_uni - cand.stock_hoy), cand.unidad_medida, cand.unidad_medida
    FROM cand
    WHERE cand.total_uni <> cand.stock_hoy      -- si ya coincide, no se genera movimiento
    RETURNING 1
  ) SELECT count(*) INTO n_mov FROM ins;

  UPDATE "GP2".relevamiento SET estado='aplicado', aplicado_en=now() WHERE id=p_id;

  RETURN jsonb_build_object('id',p_id,'estado','aplicado','ajustes',n_mov);
END $function$
;

-- ---------- relevamiento_bundle ----------
CREATE OR REPLACE FUNCTION "GP2".relevamiento_bundle()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
  with base as (
    select k.*, k.sector_id::text as clave
    from "GP2".relevamiento_cronograma k
    where k.sector_id is not null                 -- sin sector no se muestra
      and not exists (                            -- ya validado: fuera, que pase el siguiente
        select 1 from "GP2".relevamiento r
        where r.cronograma_id = k.id and r.estado = 'aplicado'
      )
  ),
  prox as (
    select distinct on (b.clave) b.clave, b.tipo, b.sector_id, b.fecha, b.id crono_id
    from base b where b.fecha > current_date
    order by b.clave, b.fecha
  ),
  ult as (
    select distinct on (b.clave) b.clave, b.tipo, b.sector_id, b.fecha, b.id crono_id
    from base b
    where not exists (select 1 from prox p where p.clave = b.clave)
    order by b.clave, b.fecha desc
  ),
  fila as (select * from prox union all select * from ult)
  select jsonb_build_object(
    'hoy', current_date,
    'cronograma', coalesce(jsonb_agg(x order by x->>'fecha'), '[]'::jsonb)
  )
  from (
    select jsonb_build_object(
      'tipo', f.tipo, 'sector_id', f.sector_id, 'sector', s.nombre,
      'crono_id', f.crono_id, 'fecha', f.fecha, 'dias', (f.fecha - current_date),
      'vencido', (f.fecha < current_date),
      'componentes', (select count(*) from "GP2".componente c where c.sector_id = f.sector_id),
      'relevamiento', (
        select jsonb_build_object('id', r.id, 'estado', r.estado,
                 'contados', (select count(*) from "GP2".relevamiento_item ri
                              where ri.relevamiento_id = r.id and ri.contado),
                 'items', (select count(*) from "GP2".relevamiento_item ri
                           where ri.relevamiento_id = r.id))
        from "GP2".relevamiento r
        where r.cronograma_id = f.crono_id and r.estado <> 'anulado'
        order by r.id desc limit 1
      )
    ) x
    from fila f join "GP2".sector s on s.id = f.sector_id
  ) t;
$function$
;

-- ---------- relevamiento_cerrar ----------
CREATE OR REPLACE FUNCTION "GP2".relevamiento_cerrar(p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
DECLARE v_sector bigint; v_ubic bigint; v_estado text; n_cont int; n_sin int;
BEGIN
  SELECT r.sector_id, r.estado INTO v_sector, v_estado FROM "GP2".relevamiento r WHERE r.id = p_id;
  IF v_sector IS NULL THEN RAISE EXCEPTION 'No existe el relevamiento %', p_id; END IF;
  IF v_estado <> 'en_curso' THEN RAISE EXCEPTION 'El relevamiento % ya esta %', p_id, v_estado; END IF;

  v_ubic := "GP2".ubic_de('sector', v_sector);

  UPDATE "GP2".relevamiento_item ri
  SET stock_programa = coalesce((
        SELECT i.cantidad FROM "GP2".inventario i
        WHERE i.componente_id = ri.componente_id AND i.ubicacion_id = v_ubic
        LIMIT 1), 0),
      -- default = conteo, salvo que no se haya contado o el total no se pueda calcular
      decision = CASE WHEN ri.contado AND ri.total_uni IS NOT NULL THEN 'conteo' ELSE 'programa' END
  WHERE ri.relevamiento_id = p_id;

  UPDATE "GP2".relevamiento SET estado='contado', cerrado_en=now() WHERE id = p_id;

  SELECT count(*) FILTER (WHERE decision='conteo'), count(*) FILTER (WHERE decision='programa')
    INTO n_cont, n_sin FROM "GP2".relevamiento_item WHERE relevamiento_id = p_id;

  RETURN jsonb_build_object('id',p_id,'estado','contado','con_conteo',n_cont,'sin_conteo',n_sin);
END $function$
;

-- ---------- relevamiento_comparar ----------
CREATE OR REPLACE FUNCTION "GP2".relevamiento_comparar(p_id bigint)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
  select jsonb_build_object(
    'relevamiento', jsonb_build_object('id', r.id, 'estado', r.estado, 'fecha', r.fecha,
                                       'encargado', r.encargado, 'sector', s.nombre),
    'items', coalesce((
      select jsonb_agg(jsonb_build_object(
        'item_id', ri.id, 'codigo', c.codigo, 'descripcion', c.descripcion,
        'unidad', c.unidad_medida,
        'conteo', ri.total_uni,
        'programa', ri.stock_programa,
        'diferencia', (coalesce(ri.total_uni,0) - coalesce(ri.stock_programa,0)),
        'contado', ri.contado,
        'decision', ri.decision,
        'coincide', (ri.total_uni IS NOT NULL AND ri.total_uni = ri.stock_programa)
      ) order by
          -- primero lo que tiene diferencia, que es lo que hay que mirar
          (case when ri.contado and ri.total_uni is distinct from ri.stock_programa then 0 else 1 end),
          abs(coalesce(ri.total_uni,0) - coalesce(ri.stock_programa,0)) desc,
          c.codigo)
      from "GP2".relevamiento_item ri
      join "GP2".componente c on c.id = ri.componente_id
      where ri.relevamiento_id = r.id
    ), '[]'::jsonb)
  )
  from "GP2".relevamiento r join "GP2".sector s on s.id = r.sector_id
  where r.id = p_id;
$function$
;

-- ---------- relevamiento_decidir ----------
CREATE OR REPLACE FUNCTION "GP2".relevamiento_decidir(p_id bigint, p_items jsonb)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
DECLARE n int := 0;
BEGIN
  IF (SELECT estado FROM "GP2".relevamiento WHERE id=p_id) <> 'contado' THEN
    RAISE EXCEPTION 'El relevamiento % no esta en estado contado', p_id;
  END IF;
  WITH d AS (
    SELECT (x->>'item_id')::bigint item_id, x->>'decision' decision
    FROM jsonb_array_elements(p_items) x
  ), upd AS (
    UPDATE "GP2".relevamiento_item ri SET decision = d.decision
    FROM d WHERE ri.id = d.item_id AND ri.relevamiento_id = p_id
      AND d.decision IN ('conteo','programa')
      -- no se puede elegir "conteo" en algo que no se conto o no se pudo calcular
      AND (d.decision = 'programa' OR (ri.contado AND ri.total_uni IS NOT NULL))
    RETURNING 1
  ) SELECT count(*) INTO n FROM upd;
  RETURN n;
END $function$
;

-- ---------- relevamiento_descartar_si_vacio ----------
CREATE OR REPLACE FUNCTION "GP2".relevamiento_descartar_si_vacio(p_id bigint)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
DECLARE v_estado text; v_cont int;
BEGIN
  SELECT estado INTO v_estado FROM "GP2".relevamiento WHERE id = p_id;
  IF v_estado IS DISTINCT FROM 'en_curso' THEN RETURN false; END IF;

  SELECT count(*) INTO v_cont FROM "GP2".relevamiento_item
  WHERE relevamiento_id = p_id AND contado;
  IF v_cont > 0 THEN RETURN false; END IF;

  DELETE FROM "GP2".relevamiento WHERE id = p_id;   -- los items caen por ON DELETE CASCADE
  RETURN true;
END $function$
;

-- ---------- relevamiento_detalle ----------
CREATE OR REPLACE FUNCTION "GP2".relevamiento_detalle(p_id bigint)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
  select jsonb_build_object(
    'relevamiento', to_jsonb(r) - 'creado_en',
    'sector', s.nombre,
    'items', coalesce((
      select jsonb_agg(jsonb_build_object(
        'item_id', ri.id,
        'comp_id', c.id,
        'codigo', c.codigo,
        'descripcion', c.descripcion,
        'unidad', c.unidad_medida,
        'factor', rf.factor,
        'envase', rf.envase,
        'cuenta_kg', rf.cuenta_kg,
        'kg_x_uni', c.kg_x_uni,
        'envases', ri.envases,
        'sueltas', ri.sueltas,
        'kg', ri.kg,
        'total_uni', ri.total_uni,
        'contado', ri.contado,
        'stock_programa', coalesce((
          select i.cantidad from "GP2".inventario i
          where i.componente_id = c.id and i.ubicacion_id = "GP2".ubic_de('sector', r.sector_id)
          limit 1), 0)
      ) order by c.codigo)
      from "GP2".relevamiento_item ri
      join "GP2".componente c on c.id = ri.componente_id
      cross join lateral "GP2".relev_factor(c.id) rf
      where ri.relevamiento_id = r.id
    ), '[]'::jsonb)
  )
  from "GP2".relevamiento r join "GP2".sector s on s.id = r.sector_id
  where r.id = p_id;
$function$
;

-- ---------- relevamiento_eliminar ----------
CREATE OR REPLACE FUNCTION "GP2".relevamiento_eliminar(p_id bigint)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
DECLARE v_estado text;
BEGIN
  SELECT estado INTO v_estado FROM "GP2".relevamiento WHERE id = p_id;
  IF v_estado IS NULL THEN RETURN false; END IF;

  IF v_estado = 'aplicado' THEN
    RAISE EXCEPTION 'Este conteo ya se aplico al stock: no se puede borrar sin deshacer los ajustes';
  END IF;

  DELETE FROM "GP2".relevamiento WHERE id = p_id;   -- los items caen por ON DELETE CASCADE
  RETURN true;
END $function$
;

-- ---------- relevamiento_guardar ----------
CREATE OR REPLACE FUNCTION "GP2".relevamiento_guardar(p_id bigint, p_items jsonb)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
DECLARE n integer := 0;
BEGIN
  IF (SELECT estado FROM "GP2".relevamiento WHERE id = p_id) <> 'en_curso' THEN
    RAISE EXCEPTION 'El relevamiento % no esta en curso', p_id;
  END IF;

  WITH d AS (
    SELECT (x->>'item_id')::bigint item_id,
           nullif(x->>'envases','')::numeric envases,
           nullif(x->>'sueltas','')::numeric sueltas,
           nullif(x->>'kg','')::numeric kg
    FROM jsonb_array_elements(p_items) x
  ), upd AS (
    UPDATE "GP2".relevamiento_item ri
    SET envases = d.envases, sueltas = d.sueltas, kg = d.kg,
        total_uni = "GP2".relev_total_uni(ri.componente_id, d.envases, d.sueltas, d.kg),
        contado = (d.envases IS NOT NULL OR d.sueltas IS NOT NULL OR d.kg IS NOT NULL)
    FROM d WHERE ri.id = d.item_id AND ri.relevamiento_id = p_id
    RETURNING 1
  ) SELECT count(*) INTO n FROM upd;

  RETURN n;
END $function$
;

-- ---------- resolver_faltante ----------
CREATE OR REPLACE FUNCTION "GP2".resolver_faltante(p_id bigint DEFAULT NULL::bigint, p_comp_id bigint DEFAULT NULL::bigint, p_origen text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
declare v_id bigint;
begin
  if p_id is not null then
    v_id := p_id;
  elsif p_comp_id is not null and p_origen is not null then
    select id into v_id from faltante_marcado
    where componente_id = p_comp_id and origen = p_origen and resuelto_en is null
    order by creado_en desc limit 1;
  end if;

  if v_id is null then
    return jsonb_build_object('ok', true, 'resueltos', 0);
  end if;

  update faltante_marcado set resuelto_en = now()
  where id = v_id and resuelto_en is null;

  return jsonb_build_object('ok', true, 'resueltos', (select count(*) from faltante_marcado where id = v_id and resuelto_en is not null), 'id', v_id);
end $function$
;

-- ---------- rollos_bundle ----------
CREATE OR REPLACE FUNCTION "GP2".rollos_bundle()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
  select jsonb_build_object(
    'saldos', (select coalesce(jsonb_agg(to_jsonb(v) order by v.codigo, v.kg_por_rollo),'[]'::jsonb) from "GP2".v_rollo_saldo v),
    'eventos', (select coalesce(jsonb_agg(to_jsonb(x) order by x.id desc),'[]'::jsonb)
                from (select * from "GP2".v_rollo_evolucion order by id desc limit 300) x),
    'usos', (select coalesce(jsonb_agg(to_jsonb(u) order by u.id desc),'[]'::jsonb)
             from (select ru.*, c.codigo from "GP2".rollo_uso ru join "GP2".componente c on c.id=ru.componente_id
                   order by ru.id desc limit 100) u),
    'flejes', (select coalesce(jsonb_agg(jsonb_build_object('comp_id',c.id,'codigo',c.codigo,
                 'descripcion',c.descripcion,'n_fleje',fd.n_fleje,'medida',fd.medida_mm) order by c.codigo),'[]'::jsonb)
               from "GP2".componente c left join "GP2".fleje_detalle fd on fd.componente_id=c.id
               where c.sector_id=5)
  );
$function$
;

-- ---------- ruta_confirmar ----------
CREATE OR REPLACE FUNCTION "GP2".ruta_confirmar(p_firma text, p_articulo text, p_fleje text, p_usuario text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
declare v_id bigint;
begin
  -- confirmar la ruta: pisa cualquier problema pendiente de esa firma (queda resuelto por la confirmacion)
  insert into "GP2".ruta_revision as rv (firma,articulo,fleje,estado,usuario,en)
  values (p_firma, coalesce(p_articulo,''), coalesce(p_fleje,''), 'confirmada', coalesce(p_usuario,''), now())
  on conflict (firma) do update set
    estado      = 'confirmada',
    usuario     = excluded.usuario,
    en          = now(),
    resuelto_en = case when rv.estado = 'pendiente' then now() else rv.resuelto_en end,
    articulo    = coalesce(nullif(excluded.articulo,''), rv.articulo),
    fleje       = coalesce(nullif(excluded.fleje,''),    rv.fleje)
  returning id into v_id;
  return v_id;
end;
$function$
;

-- ---------- ruta_reportar ----------
CREATE OR REPLACE FUNCTION "GP2".ruta_reportar(p_firma text, p_articulo text, p_fleje text, p_problema text, p_usuario text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
declare v_id bigint;
begin
  -- reportar un problema quita la confirmacion previa de esa firma (misma fila, estado pendiente)
  insert into "GP2".ruta_revision as rv (firma,articulo,fleje,estado,problema,usuario,en)
  values (p_firma, coalesce(p_articulo,''), coalesce(p_fleje,''), 'pendiente',
          coalesce(nullif(btrim(p_problema),''), '(pendiente de revisar)'), coalesce(p_usuario,''), now())
  on conflict (firma) do update set
    estado      = 'pendiente',
    problema    = excluded.problema,
    usuario     = excluded.usuario,
    en          = now(),
    resuelto_en = null,
    articulo    = coalesce(nullif(excluded.articulo,''), rv.articulo),
    fleje       = coalesce(nullif(excluded.fleje,''),    rv.fleje)
  returning id into v_id;
  return v_id;
end;
$function$
;

-- ---------- ruta_resolver ----------
CREATE OR REPLACE FUNCTION "GP2".ruta_resolver(p_id bigint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
begin
  update "GP2".ruta_revision
     set estado = 'resuelto', resuelto_en = now()
   where id = p_id and estado = 'pendiente';
end;
$function$
;

-- ---------- stock_sector_bundle ----------
CREATE OR REPLACE FUNCTION "GP2".stock_sector_bundle(p_sector_id bigint)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
with ubic as (
  select "GP2".ubic_de('sector', p_sector_id) id
),
comps as (
  select c.* from componente c where c.sector_id = p_sector_id
),
-- entradas al sector: el componente que llega es el transformado si existe
ent as (
  select coalesce(m.comp_transformado_id, m.comp_id) comp_id,
         m.tipo_mov,
         sum(coalesce(m._delta_dest,0)) qty,
         count(*) n
    from movimiento m
   where m.ubic_destino_id = (select id from ubic)
   group by 1,2
),
-- salidas del sector
sal as (
  select m.comp_id, m.tipo_mov,
         sum(coalesce(m._delta_orig,0)) qty,
         count(*) n
    from movimiento m
   where m.ubic_origen_id = (select id from ubic)
   group by 1,2
),
mov as (
  select comp_id,
         jsonb_object_agg(tipo_mov, jsonb_build_object('ent',ent_q,'sal',sal_q,'n',n_tot)) obj
    from (
      select coalesce(e.comp_id, s.comp_id) comp_id,
             coalesce(e.tipo_mov, s.tipo_mov) tipo_mov,
             coalesce(e.qty,0) ent_q, coalesce(s.qty,0) sal_q,
             coalesce(e.n,0)+coalesce(s.n,0) n_tot
        from ent e
        full join sal s on s.comp_id=e.comp_id and s.tipo_mov=e.tipo_mov
    ) z
   group by comp_id
)
select jsonb_build_object(
  'generado_en', now(),
  'sector', (select jsonb_build_object('id',s.id,'nombre',s.nombre) from sector s where s.id=p_sector_id),
  'ubicacion_id', (select id from ubic),
  'filas', coalesce((select jsonb_agg(jsonb_build_object(
      'comp_id', c.id,
      'cod', c.codigo,
      'desc', c.descripcion,
      'um', c.unidad_medida,
      'kg_x_uni', c.kg_x_uni,
      'uni_x_cajon', c.uni_x_cajon,
      'online', coalesce(i.cantidad,0),
      'minimo', i.minimo,
      'maximo', i.maximo,
      'n_fleje', fd.n_fleje,
      'mov', coalesce(mv.obj, '{}'::jsonb)
    ) order by c.codigo)
    from comps c
    left join inventario i on i.componente_id=c.id and i.ubicacion_id=(select id from ubic)
    left join fleje_detalle fd on fd.componente_id=c.id
    left join mov mv on mv.comp_id=c.id), '[]'::jsonb)
);
$function$
;

-- ---------- stock_transito_ps_bundle ----------
CREATE OR REPLACE FUNCTION "GP2".stock_transito_ps_bundle()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
with pares as (
  select distinct
    p1.comp_salida_id comp_id,
    p1.proveedor_id ps1_id,
    p2.proveedor_id ps2_id,
    p1.comp_entrada_id sc_id
  from ruta_paso p1
  join ruta_paso p2 on p2.ruta_id = p1.ruta_id and p2.orden = p1.orden + 1
  where p1.tipo_paso='proveedor_servicio' and p2.tipo_paso='proveedor_servicio'
    and p1.comp_salida_id is not null and p2.comp_entrada_id = p1.comp_salida_id
), fila as (
  select pr.comp_id, c.codigo, c.descripcion, c.sector_id, c.unidad_medida um, c.kg_x_uni, c.uni_x_cajon,
         s.nombre sector,
         sc.codigo sc_cod,
         ps1.id ps1_id, ps1.nombre ps1_nombre, ps1.proceso ps1_proceso,
         ps2.id ps2_id, ps2.nombre ps2_nombre, ps2.proceso ps2_proceso,
         (select i.cantidad from inventario i
           where i.componente_id=pr.comp_id and i.ubicacion_id="GP2".ubic_de('sector', c.sector_id) limit 1) online,
         (select coalesce(sum(m._delta_dest),0) from movimiento m
           where m.tipo_mov='entrega_ps'
             and coalesce(m.comp_transformado_id, m.comp_id)=pr.comp_id
             and m.ubic_origen_id="GP2".ubic_de('proveedor_servicio', ps1.id)) entregado_origen,
         (select coalesce(sum(m._delta_orig),0) from movimiento m
           where m.tipo_mov='envio_ps' and m.comp_id=pr.comp_id
             and m.ubic_destino_id="GP2".ubic_de('proveedor_servicio', ps2.id)) enviado_siguiente
  from pares pr
  join componente c on c.id=pr.comp_id
  join sector s on s.id=c.sector_id
  left join componente sc on sc.id=pr.sc_id
  join proveedor_servicio ps1 on ps1.id=pr.ps1_id
  join proveedor_servicio ps2 on ps2.id=pr.ps2_id
)
select jsonb_build_object(
  'filas', (select coalesce(jsonb_agg(to_jsonb(f) order by f.codigo),'[]'::jsonb) from fila f),
  'generado_en', now());
$function$
;

-- ---------- talleristas_bundle ----------
CREATE OR REPLACE FUNCTION "GP2".talleristas_bundle()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
with ub as (
  -- ubicacion de cada tallerista via ubic_de (honra tallerista.ubicacion_stock_id: Carlos Aguirre -> 18)
  select t.id tall_id, u.ubic_id
    from tallerista t
    join lateral (select "GP2".ubic_de('tallerista', t.id) ubic_id) u on u.ubic_id is not null
),
cfg as (
  -- que parte entra y sale por tallerista: v_contraparte_parte (una sola definicion)
  select ref_id as tallerista_id, comp_id, lado
    from v_contraparte_parte
   where tipo = 'tallerista'
),
mov as (
  select u.tall_id, m.comp_id,
         sum(case when m.tipo_mov='envio_tallerista' then coalesce(m._delta_dest,0) else 0 end) enviado,
         -- _delta_orig se guarda POSITIVO (fn_movimiento_aplicar lo niega al aplicar):
         -- lo que salio del tallerista es +_delta_orig, no -_delta_orig
         sum(case when m.tipo_mov in ('entrega_tallerista','consumo_tall')
                  then coalesce(m._delta_orig,0) else 0 end) entregado,
         sum(case when m.tipo_mov='devolucion_tallerista'
                  then coalesce(m._delta_orig,0) else 0 end) devuelto
    from movimiento m
    join ub u on u.ubic_id in (m.ubic_origen_id, m.ubic_destino_id)
   group by u.tall_id, m.comp_id
),
fila as (
  select cfg.tallerista_id, cfg.lado,
         c.id comp_id, c.codigo cod, c.descripcion desc_, s.nombre sector,
         c.unidad_medida um, c.kg_x_uni, c.uni_x_cajon,
         coalesce((select i.cantidad from inventario i
                    join ub u2 on u2.ubic_id = i.ubicacion_id and u2.tall_id = cfg.tallerista_id
                   where i.componente_id = c.id limit 1), 0) online_tall,
         coalesce((select i.cantidad from inventario i
                   where i.componente_id = c.id and i.ubicacion_id = "GP2".ubic_de('sector', c.sector_id) limit 1), 0) online_sector,
         coalesce((select mv.enviado   from mov mv where mv.tall_id=cfg.tallerista_id and mv.comp_id=c.id), 0) enviado,
         coalesce((select mv.entregado from mov mv where mv.tall_id=cfg.tallerista_id and mv.comp_id=c.id), 0) entregado,
         coalesce((select mv.devuelto  from mov mv where mv.tall_id=cfg.tallerista_id and mv.comp_id=c.id), 0) devuelto
    from cfg
    join componente c on c.id = cfg.comp_id
    left join sector s on s.id = c.sector_id
)
select jsonb_build_object(
  'generado_en', now(),
  'tall', (select coalesce(jsonb_agg(jsonb_build_object(
              'id',t.id,'nombre',t.nombre,'cod_prov',t.cod_prov,
              'n_entrada',(select count(*) from cfg where cfg.tallerista_id=t.id and cfg.lado='entrada'),
              'n_salida', (select count(*) from cfg where cfg.tallerista_id=t.id and cfg.lado='salida')
            ) order by t.nombre),'[]'::jsonb)
            from tallerista t where t.activo),
  'partes', (select coalesce(jsonb_object_agg(tallerista_id::text, obj),'{}'::jsonb) from (
       select tallerista_id,
              jsonb_build_object(
                'entrada', coalesce(jsonb_agg(j order by cod) filter (where lado='entrada'),'[]'::jsonb),
                'salida',  coalesce(jsonb_agg(j order by cod) filter (where lado='salida'), '[]'::jsonb)
              ) obj
         from (select tallerista_id, lado, cod,
                      jsonb_build_object(
                        'comp_id',comp_id,'cod',cod,'desc',desc_,'sector',sector,'um',um,
                        'kg_x_uni',kg_x_uni,'uni_x_cajon',uni_x_cajon,
                        'online_tall',online_tall,'online_sector',online_sector,
                        'enviado',enviado,'entregado',entregado,'devuelto',devuelto,
                        'saldo',(enviado-entregado-devuelto)
                      ) j
                 from fila) z2
        group by tallerista_id) y)
);
$function$
;

-- ---------- to_canonical ----------
CREATE OR REPLACE FUNCTION "GP2".to_canonical(p_comp bigint, p_qty numeric, p_unit text)
 RETURNS numeric
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
declare
  v_canon   text;
  v_kgxuni  numeric;
  v_found   boolean := false;
  v_dim_mov text;
  v_dim_can text;
begin
  if p_qty is null then
    return 0;
  end if;
  if p_unit is null then
    return p_qty;
  end if;

  select unidad_medida, kg_x_uni, true
    into v_canon, v_kgxuni, v_found
    from "GP2".componente
   where id = p_comp;
  if not v_found then
    raise exception 'to_canonical: componente % inexistente', p_comp;
  end if;

  v_dim_mov := case when lower(p_unit) = 'kg' then 'kg' else 'uni' end;
  v_dim_can := case when lower(coalesce(v_canon,'unidad')) = 'kg' then 'kg' else 'uni' end;

  if v_dim_mov = v_dim_can then
    return p_qty;
  elsif v_dim_mov = 'kg' then
    if v_kgxuni is null or v_kgxuni = 0 then
      raise exception 'to_canonical: componente % sin kg_x_uni valido para kg->uni (qty=%)', p_comp, p_qty;
    end if;
    return p_qty / v_kgxuni;
  else
    if v_kgxuni is null or v_kgxuni = 0 then
      raise exception 'to_canonical: componente % sin kg_x_uni valido para uni->kg (qty=%)', p_comp, p_qty;
    end if;
    return p_qty * v_kgxuni;
  end if;
end;
$function$
;

-- ---------- tomar_rollo ----------
CREATE OR REPLACE FUNCTION "GP2".tomar_rollo(p_legajo text, p_comp_id bigint, p_kg_por_rollo numeric, p_matriz text DEFAULT NULL::text, p_fecha timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
declare v_ev bigint; v_uso bigint; v_saldo numeric;
begin
  if p_kg_por_rollo is null or p_kg_por_rollo <= 0 then
    raise exception 'Elegi el peso del rollo';
  end if;
  select coalesce(sum(delta),0) into v_saldo from rollo_evento
   where componente_id=p_comp_id and kg_por_rollo=p_kg_por_rollo;
  insert into rollo_evento(fecha, componente_id, kg_por_rollo, delta, motivo, legajo)
  values (coalesce(p_fecha,now()), p_comp_id, p_kg_por_rollo, -1, 'toma_operario', p_legajo)
  returning id into v_ev;
  -- cerrar un uso abierto anterior sin datos (tomo otro rollo sin cerrar el previo)
  update rollo_uso set ts_fin = coalesce(p_fecha,now())
   where legajo=p_legajo and ts_fin is null;
  insert into rollo_uso(legajo, componente_id, kg_por_rollo, matriz_raw, ts_inicio, rollo_evento_id)
  values (p_legajo, p_comp_id, p_kg_por_rollo, p_matriz, coalesce(p_fecha,now()), v_ev)
  returning id into v_uso;
  return jsonb_build_object('ok',true,'uso_id',v_uso,'evento_id',v_ev,
    'saldo_anterior',v_saldo,'saldo_nuevo',v_saldo-1,
    'aviso', case when v_saldo<=0 then 'OJO: el stock de ese rollo ya estaba en '||v_saldo else null end);
end $function$
;

-- ---------- ubic_de ----------
CREATE OR REPLACE FUNCTION "GP2".ubic_de(p_tipo text, p_ref_id bigint DEFAULT NULL::bigint)
 RETURNS bigint
 LANGUAGE sql
 STABLE
 SET search_path TO 'GP2'
AS $function$
  select coalesce(
    -- override explicito del tallerista (deposito compartido, p.ej. Carlos Aguirre usa la ubicacion 18 de Pedernera)
    case when p_tipo = 'tallerista'
         then (select t.ubicacion_stock_id from tallerista t where t.id = p_ref_id) end,
    (select u.id
       from ubicacion u
      where u.tipo = p_tipo
        and u.ref_id is not distinct from p_ref_id
      order by u.id
      limit 1))
$function$
;

-- ---------- ubic_de_componente ----------
CREATE OR REPLACE FUNCTION "GP2".ubic_de_componente(p_comp_id bigint)
 RETURNS bigint
 LANGUAGE sql
 STABLE
 SET search_path TO 'GP2'
AS $function$
  select coalesce("GP2".ubic_de('sector', c.sector_id), "GP2".ubic_de('virgilio'))
    from componente c
   where c.id = p_comp_id
$function$
;

-- ---------- validacion_bundle ----------
CREATE OR REPLACE FUNCTION "GP2".validacion_bundle()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
  select jsonb_build_object(
    'hoy', current_date,
    'pendientes', coalesce((
      select jsonb_agg(x order by x->>'fecha')
      from (
        select jsonb_build_object(
          'id', r.id, 'sector', s.nombre, 'sector_id', r.sector_id,
          'fecha', r.fecha, 'encargado', r.encargado,
          'cerrado_en', r.cerrado_en,
          'items',    (select count(*) from "GP2".relevamiento_item ri where ri.relevamiento_id=r.id),
          'contados', (select count(*) from "GP2".relevamiento_item ri where ri.relevamiento_id=r.id and ri.contado),
          -- cuantas filas contadas NO coinciden con lo que dice el programa
          'difieren', (select count(*) from "GP2".relevamiento_item ri
                       where ri.relevamiento_id=r.id and ri.contado
                         and ri.total_uni is distinct from ri.stock_programa)
        ) x
        from "GP2".relevamiento r join "GP2".sector s on s.id = r.sector_id
        where r.estado = 'contado'
      ) t), '[]'::jsonb),
    'aplicados', coalesce((
      select jsonb_agg(x order by x->>'aplicado_en' desc)
      from (
        select jsonb_build_object(
          'id', r.id, 'sector', s.nombre, 'fecha', r.fecha,
          'aplicado_en', r.aplicado_en,
          'contados', (select count(*) from "GP2".relevamiento_item ri
                       where ri.relevamiento_id=r.id and ri.contado)
        ) x
        from "GP2".relevamiento r join "GP2".sector s on s.id = r.sector_id
        where r.estado = 'aplicado'
        order by r.aplicado_en desc nulls last
        limit 20
      ) t), '[]'::jsonb)
  );
$function$
;

-- ---------- valorizacion_bundle ----------
CREATE OR REPLACE FUNCTION "GP2".valorizacion_bundle()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
with inv as (
  select componente_id,
         sum(coalesce(cantidad,0)) stock,
         sum(coalesce(maximo,0)) maximo,
         sum(greatest(0, coalesce(maximo,0) - coalesce(cantidad,0))) pedido
  from inventario
  group by componente_id
)
select jsonb_build_object(
  'tc', (select valor from parametro where clave='tipo_cambio_usd_pesos'),
  'tc_info', (select jsonb_build_object('fecha',fecha,'venta',venta,'fuente',fuente)
              from tipo_cambio order by fecha desc, obtenido_en desc limit 1),
  'costo_seg', (select valor from parametro where clave='costo_segundo_pesos'),
  'comps', (select coalesce(jsonb_agg(jsonb_build_object(
     'comp_id',cc.comp_id,'codigo',cc.codigo,'descripcion',cc.descripcion,
     'sector_id',cc.sector_id,'sector',cc.sector,'sector_tipo',cc.sector_tipo,'origen',cc.origen,
     'material_usd',cc.material_usd,'material_pesos',cc.material_pesos,
     'servicios_usd',cc.servicios_usd,'servicios_pesos',cc.servicios_pesos,
     'segundos_matriz',cc.segundos_matriz,'mano_obra_pesos',cc.mano_obra_pesos,
     'total_pesos',cc.total_pesos,
     'faltan_precios',cc.faltan_precios,'faltan_kg',cc.faltan_kg,'faltan_tiempos',cc.faltan_tiempos,
     'stock',coalesce(i.stock,0),'maximo',coalesce(i.maximo,0),'pedido',coalesce(i.pedido,0)
   ) order by cc.sector_id, cc.codigo),'[]'::jsonb)
   from "GP2".v_costo_componente cc
   left join inv i on i.componente_id = cc.comp_id
   where cc.sector_tipo <> 'terminado'),
  'generado_en', now()
);
$function$
;
