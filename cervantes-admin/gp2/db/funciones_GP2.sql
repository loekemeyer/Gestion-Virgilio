-- =====================================================================
-- FUNCIONES del schema GP2 — export automatico 2026-09-28 (pg_get_functiondef, exacto)
-- Fuente de verdad: Supabase (hrxfctzncixxqmpfhskv). Este archivo es respaldo/referencia.
-- 167 funciones. Los GRANT/REVOKE no estan aca: EXECUTE para anon solo en las RPC de pantalla (ver db/README.md).
-- Desde 2026-09-28 (seguridad fase B) las 62 RPC que escriben llaman a "GP2"._exigir_autorizado() y NO las ejecuta anon.
-- =====================================================================

-- ---------- _aplicar_recepcion_a_oc ----------
CREATE OR REPLACE FUNCTION "GP2"._aplicar_recepcion_a_oc(p_comp_id bigint, p_cantidad numeric, p_unidad text, p_proveedor text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
declare
  it record; v_resto numeric := p_cantidad; v_aplicar numeric; v_pend numeric;
  v_kgu numeric; v_cant_item numeric; v_ocs jsonb := '[]'::jsonb;
  v_prov text := nullif(btrim(coalesce(p_proveedor,'')),'');
begin
  select kg_x_uni into v_kgu from componente where id = p_comp_id;
  for it in
    select oi.id, oi.cantidad, oi.recibido, oi.unidad, o.id oc_id, o.numero, o.estado
    from orden_compra_item oi
    join orden_compra o on o.id = oi.oc_id
    where oi.componente_id = p_comp_id
      and o.estado in ('enviada','borrador')
      and oi.recibido < oi.cantidad
    order by case when v_prov is not null and o.proveedor = v_prov then 0 else 1 end,
             case o.estado when 'enviada' then 0 else 1 end, o.numero, oi.id
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

-- ---------- _autorizado ----------
CREATE OR REPLACE FUNCTION "GP2"._autorizado()
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'GP2', 'pg_temp'
AS $function$
declare
  v_claims jsonb := nullif(current_setting('request.jwt.claims', true), '')::jsonb;
  v_rol text;
  v_email text;
begin
  -- Sin pedido de PostgREST (SQL del dueno, cron, migraciones): no hay a quien controlar.
  if v_claims is null then return true; end if;
  v_rol := v_claims->>'role';
  if v_rol = 'service_role' then return true; end if;          -- Edge Functions / backend
  if v_rol is distinct from 'authenticated' then return false; end if;   -- anon: afuera
  v_email := lower(coalesce(v_claims->>'email', ''));
  if v_email = '' then return false; end if;
  -- Cualquiera con cuenta de Google puede loguearse en Supabase: el rol no alcanza,
  -- tiene que estar en la whitelist (la misma que usa login.html).
  return "GP2".get_role_for_email(v_email) is not null;
end $function$
;

-- ---------- _es_comprable ----------
CREATE OR REPLACE FUNCTION "GP2"._es_comprable(p_comp bigint)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'GP2'
AS $function$
  select exists (
    select 1 from componente c
      left join sector s on s.id = c.sector_id
     where c.id = p_comp
       and coalesce(c.estado_compra,'') <> 'fabricacion'
       and ( coalesce(s.es_insumo, false)                                  -- insumo de sector comprable
          or c.estado_compra = 'importado'                                  -- pieza importada, viva donde viva
          or exists (select 1 from proveedor_servicio ps                    -- PS hibrido: nos vende la pieza hecha
                      where ps.hibrido and ps.nombre = btrim(coalesce(c.proveedor,''))) ))
$function$
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

-- ---------- _exigir_autorizado ----------
CREATE OR REPLACE FUNCTION "GP2"._exigir_autorizado()
 RETURNS void
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'GP2', 'pg_temp'
AS $function$
begin
  if not "GP2"._autorizado() then
    raise exception 'No autorizado: inicia sesion con una cuenta habilitada'
      using errcode = '42501';
  end if;
end $function$
;

-- ---------- _exigir_operario ----------
CREATE OR REPLACE FUNCTION "GP2"._exigir_operario(p_legajo text)
 RETURNS void
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'GP2', 'pg_temp'
AS $function$
declare
  v_claims jsonb := nullif(current_setting('request.jwt.claims', true), '')::jsonb;
begin
  if "GP2"._autorizado() then return; end if;   -- SQL, service_role o mail habilitado
  if v_claims->>'role' = 'authenticated'
     and v_claims->'app_metadata'->>'rol' = 'operario'
     and v_claims->'app_metadata'->>'legajo' = btrim(coalesce(p_legajo, '')) then
    return;
  end if;
  raise exception 'No autorizado: entrá con tu legajo desde la red de la empresa' using errcode = '42501';
end $function$
;

-- ---------- _oc_num ----------
CREATE OR REPLACE FUNCTION "GP2"._oc_num(p numeric)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select replace(to_char(round(coalesce(p,0)), 'FM999,999,999,999'), ',', '.')
$function$
;

-- ---------- _oc_validar_carton ----------
CREATE OR REPLACE FUNCTION "GP2"._oc_validar_carton(p_items jsonb)
 RETURNS text[]
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
  -- 2026-09-28: el MULTIPLO de la familia y el minimo por codigo YA NO frenan la OC [Thomas:
  -- "Que esto no aparezca", sobre el cartel "el total debe ser multiplo de 16.000"]. La tirada se
  -- muestra en cada fila de la pantalla; lo que el comprador escribe es su decision. Queda SOLO el
  -- piso de la familia (carton_formato.pedido_minimo: la bolsa de Vihal 20.000). Es el port literal
  -- de validarCarton() de Compras/OC_GP2.html; test_oc_reglas_js_vs_db compara los dos.
  with paq as (
    select coalesce((select valor::numeric from parametro where clave = 'pliego_uni_x_paquete'), 100) q
  ),
  base as (
    select c.id as comp_id, c.codigo, (it->>'cantidad')::numeric as cantidad,
           coalesce(c.es_pliego,false) as pliego,
           case when coalesce(c.es_pliego,false)
                then 'PLIEGO|' || coalesce(c.marca,'(sin marca)') || '|'
                else coalesce(c.carton_formato,'') || '|' || coalesce(c.marca,'(sin marca)') || '|'
                     || coalesce(c.carton_categoria,'') end as fam_key,
           case when coalesce(c.es_pliego,false)
                then 'PLIEGO|' || coalesce(c.marca,'(sin marca)')
                else coalesce(c.carton_formato,'') || '|' || coalesce(c.marca,'(sin marca)') end as fam_base,
           case when coalesce(c.es_pliego,false)
                then 'Pliegos' || coalesce(' ' || c.marca, '')
                else 'Formato ' || coalesce(c.carton_formato,'') || coalesce(' ' || c.marca, '')
                     || coalesce(' · ' || c.carton_categoria, '') end as fam_label,
           (not coalesce(c.es_pliego,false)) and coalesce(cc.mezcla_libre,false) as comodin,
           case when coalesce(c.es_pliego,false) then paq.q else cf.pliegos_multiplo end as pm,
           case when coalesce(c.es_pliego,false) then 0 else coalesce(cf.pedido_minimo,0) end as pmin
      from jsonb_array_elements(coalesce(p_items,'[]'::jsonb)) it
      cross join paq
      join componente c on c.id = (it->>'comp_id')::bigint
      left join carton_formato   cf on cf.nombre = c.carton_formato
      left join carton_categoria cc on cc.nombre = c.carton_categoria and cc.formato = c.carton_formato
     where c.sector_id = 10
       and (coalesce(c.es_pliego,false) or coalesce(cf.pliegos_multiplo,0) > 0)
       and coalesce((it->>'cantidad')::numeric, 0) > 0
  ),
  destino as (
    select distinct on (fam_base) fam_base, fam_key
      from (select fam_base, fam_key,
                   ceil(sum(cantidad) / max(pm)) * max(pm) - sum(cantidad) as falta
              from base where not comodin group by fam_base, fam_key) f
     order by fam_base, falta desc, fam_key
  ),
  asignado as (
    select b.*,
           case when b.comodin and d.fam_key is not null then d.fam_key else b.fam_key end as k,
           (b.comodin and d.fam_key is not null) as mudado
      from base b
      left join destino d on d.fam_base = b.fam_base and b.comodin
  ),
  cabecera as (
    select distinct on (k) k, fam_label, pmin from asignado
     order by k, comodin, comp_id
  ),
  fam as (
    select a.k,
           max(c.fam_label) || case when bool_or(a.mudado) then ' (+ sacacorchos)' else '' end as lbl,
           sum(a.cantidad) as total, max(c.pmin) pmin
      from asignado a join cabecera c on c.k = a.k group by a.k
  )
  select coalesce(array_agg(f.lbl || ': el pedido mínimo es ' || "GP2"._oc_num(f.pmin)
           || ' y hay ' || "GP2"._oc_num(f.total) || '.' order by f.k), '{}')
    from fam f where f.pmin > 0 and f.total < f.pmin;
$function$
;

-- ---------- _oc_validar_minimo_proveedor ----------
CREATE OR REPLACE FUNCTION "GP2"._oc_validar_minimo_proveedor(p_items jsonb)
 RETURNS text[]
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
  with mp as (
    select coalesce(nullif(btrim(c.proveedor),''), '(sin proveedor)') as prov,
           sum((it->>'cantidad')::numeric) as kg
      from jsonb_array_elements(coalesce(p_items,'[]'::jsonb)) it
      join componente c on c.id = (it->>'comp_id')::bigint
     where c.sector_id = 14 and coalesce((it->>'cantidad')::numeric, 0) > 0
     group by 1
  )
  select coalesce(array_agg(
      mp.prov || ': el pedido mínimo es ' || "GP2"._oc_num(pi.pedido_minimo_kg)
      || ' kg y hay ' || "GP2"._oc_num(mp.kg) || ' kg (faltan '
      || "GP2"._oc_num(pi.pedido_minimo_kg - mp.kg) || ').' order by mp.prov), '{}')
    from mp join proveedor_insumo pi on pi.nombre = mp.prov
   where coalesce(pi.pedido_minimo_kg, 0) > 0 and mp.kg < pi.pedido_minimo_kg;
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
  perform "GP2"._exigir_autorizado();  -- seguridad punto 1 fase B (2026-09-28)
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
  perform "GP2"._exigir_autorizado();  -- seguridad punto 1 fase B (2026-09-28)
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
  perform "GP2"._exigir_autorizado();  -- seguridad punto 1 fase B (2026-09-28)
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
declare r record; j jsonb; v_fecha date; v_venta numeric; v_compra numeric; v_prov jsonb; v_max jsonb;
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

  -- materia prima plastica: con el dolar nuevo puede cambiar quien es el mas barato (2026-09-10).
  -- Si falla, el dolar igual queda actualizado.
  begin
    v_prov := "GP2".recalcular_proveedor_material();
  exception when others then
    v_prov := jsonb_build_object('ok', false, 'error', sqlerrm);
  end;
  -- y el maximo de cada material sigue al consumo del dia (2,5 meses en bolsas enteras, 2026-09-11)
  begin
    v_max := "GP2".recalcular_maximo_material();
  exception when others then
    v_max := jsonb_build_object('ok', false, 'error', sqlerrm);
  end;

  return jsonb_build_object('ok', true, 'fecha', v_fecha, 'venta', v_venta, 'compra', v_compra, 'proveedor_material', v_prov, 'maximo_material', v_max);
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
  perform "GP2"._exigir_autorizado();  -- seguridad punto 1 fase B (2026-09-28)
  if p_motivo not in ('inicial','ajuste','devolucion') then
    raise exception 'Motivo invalido: %', p_motivo;
  end if;
  insert into rollo_evento(componente_id, kg_por_rollo, delta, motivo, nota)
  values (p_comp_id, p_kg_por_rollo, p_delta, p_motivo, p_nota) returning id into v_id;
  return jsonb_build_object('ok',true,'id',v_id);
end $function$
;

-- ---------- alerta_recepcion_marcar ----------
CREATE OR REPLACE FUNCTION "GP2".alerta_recepcion_marcar(p_id bigint, p_estado text DEFAULT 'resuelta'::text, p_nota text DEFAULT NULL::text, p_usuario text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
declare v jsonb;
begin
  perform "GP2"._exigir_autorizado();  -- seguridad punto 1 fase B (2026-09-28)
  -- Los tres estados los fija el check de la tabla: abierta | vista | resuelta.
  if p_estado not in ('abierta','vista','resuelta') then
    raise exception 'Estado invalido: "%". Solo abierta, vista o resuelta.', p_estado;
  end if;
  update alerta_recepcion
     set estado      = p_estado,
         nota        = coalesce(nullif(btrim(p_nota),''), nota),
         cerrado_en  = case when p_estado = 'abierta' then null else now() end,
         cerrado_por = case when p_estado = 'abierta' then null else p_usuario end
   where id = p_id
  returning to_jsonb(alerta_recepcion.*) into v;
  if v is null then raise exception 'No existe la alerta %', p_id; end if;
  return jsonb_build_object('ok', true, 'alerta', v);
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
  'recepcion_de_mas', jsonb_build_object(
    'total', (select count(*) from "GP2".alerta_recepcion where estado = 'abierta'),
    'items', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', a.id, 'fecha', to_char(a.fecha at time zone 'America/Argentina/Buenos_Aires','YYYY-MM-DD HH24:MI'),
               'quien', a.origen_nombre, 'tipo', a.origen_tipo, 'cod', a.cod,
               'descripcion', a.descripcion, 'esperado', a.esperado, 'recibido', a.recibido,
               'exceso', a.exceso, 'unidad', a.unidad, 'esperado_origen', a.esperado_origen)
             order by a.fecha desc)
      from (select * from "GP2".alerta_recepcion where estado = 'abierta' order by fecha desc limit 100) a),
      '[]'::jsonb)
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
  perform "GP2"._exigir_autorizado();  -- seguridad punto 1 fase B (2026-09-28)
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
  perform "GP2"._exigir_autorizado();  -- seguridad punto 1 fase B (2026-09-28)
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
  insert into ubicacion (tipo, ref_id, nombre, meses_stock)
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
  perform "GP2"._exigir_autorizado();  -- seguridad punto 1 fase B (2026-09-28)
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
  perform "GP2"._exigir_autorizado();  -- seguridad punto 1 fase B (2026-09-28)
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
  perform "GP2"._exigir_autorizado();  -- seguridad punto 1 fase B (2026-09-28)
  if p_recepcion_ids is null or array_length(p_recepcion_ids, 1) is null then
    return query select 0, 0;
    return;
  end if;

  -- Movimientos asociados: la compra (movimiento_id) y, si los hay, el consumo de materia prima que
  -- esa recepcion disparo (rollos_json: movimiento_material_id del inyector, movimiento_chapa_id de Eclipse).
  select coalesce(array_agg(x) filter (where x is not null), array[]::bigint[])
    into v_mov_ids
  from (
    select movimiento_id x from "GP2".recepcion_insumo where id = any(p_recepcion_ids)
    union all
    select (rollos_json->>'movimiento_material_id')::bigint from "GP2".recepcion_insumo where id = any(p_recepcion_ids)
    union all
    select (rollos_json->>'movimiento_chapa_id')::bigint from "GP2".recepcion_insumo where id = any(p_recepcion_ids)
  ) q;

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
  perform "GP2"._exigir_autorizado();  -- seguridad punto 1 fase B (2026-09-28)
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
  perform "GP2"._exigir_autorizado();  -- seguridad punto 1 fase B (2026-09-28)
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
  perform "GP2"._exigir_autorizado();  -- seguridad punto 1 fase B (2026-09-28)
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

-- ---------- calculadora_cajones_bundle ----------
CREATE OR REPLACE FUNCTION "GP2".calculadora_cajones_bundle()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
  select jsonb_build_object(
    'cajones', (select coalesce(jsonb_agg(jsonb_build_object('n', numero, 'tara', tara_kg) order by numero), '[]'::jsonb)
                  from cajon),
    'sectores', (select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'nom', s.nombre, 'n', s.n) order by s.nombre), '[]'::jsonb)
                   from (select se.id, se.nombre, count(c.id) n
                           from sector se join componente c on c.sector_id = se.id
                          where c.kg_x_uni is not null and c.kg_x_uni > 0
                          group by se.id, se.nombre) s),
    'comps', (select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'cod', c.codigo, 'd', c.descripcion,
                                                           's', c.sector_id, 'kg', c.kg_x_uni,
                                                           'uxc', c.uni_x_cajon) order by c.codigo), '[]'::jsonb)
                from componente c
               where c.kg_x_uni is not null and c.kg_x_uni > 0)
  );
$function$
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
  perform "GP2"._exigir_autorizado();  -- seguridad punto 1 fase B (2026-09-28)
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
  perform "GP2"._exigir_autorizado();  -- seguridad punto 1 fase B (2026-09-28)
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
  perform "GP2"._exigir_autorizado();  -- seguridad punto 1 fase B (2026-09-28)
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

  select id into v_bruto from "GP2".componente where codigo='ALAMBRE';
  if v_bruto is null then raise exception 'ALAMBRE no existe'; end if;

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
  v_ps_eclipse bigint;
  v_ubic_eclipse bigint;
  v_stock_chapa_antes numeric; v_stock_chapa_despues numeric;
  v_f timestamptz := coalesce(p_fecha, now());
begin
  perform "GP2"._exigir_autorizado();  -- seguridad punto 1 fase B (2026-09-28)
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

  v_ubic_procesado := "GP2".ubic_de('sector', v_sec);
  if v_ubic_procesado is null then
    raise exception 'No hay ubicacion tipo=sector para el sector % del componente %', v_sec, v_codigo;
  end if;

  select id into v_ps_eclipse from "GP2".proveedor_servicio where nombre = 'Eclipse';
  if v_ps_eclipse is null then raise exception 'No existe el proveedor de servicio "Eclipse"'; end if;
  v_ubic_eclipse := "GP2".ubic_de('proveedor_servicio', v_ps_eclipse);
  if v_ubic_eclipse is null then raise exception 'El PS "Eclipse" no tiene ubicacion'; end if;

  select id into v_chapa from "GP2".componente where codigo='FLEJE_DESCORAZONADOR';
  if v_chapa is null then raise exception 'FLEJE_DESCORAZONADOR no existe (Fase 1 pendiente)'; end if;
  select coalesce(desperdicio_pct, 0) into v_desperdicio from "GP2".proveedor_servicio where id = v_ps_eclipse;
  if v_desperdicio < 0 or v_desperdicio >= 100 then v_desperdicio := 0; end if;  -- proteccion division

  -- Peso del producto entregado: el KG que pesamos (real, del remito verificado). Las UNIDADES
  -- son solo referencia (lo que declara Eclipse). Si no viene kg, cae al teorico uni*kg_x_uni.
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

-- ---------- cartones_para_reemplazo ----------
CREATE OR REPLACE FUNCTION "GP2".cartones_para_reemplazo(p_tipo text, p_ref bigint)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
with propios as (
  select distinct ac.componente_id as comp_id
    from articulo_prov_at apa
    join articulo a on a.codigo = apa.cod_art
    join articulo_componente ac on ac.articulo_id = a.id
    join componente c on c.id = ac.componente_id and c.sector_id in (10,11)
   where p_tipo = 'proveedor_at' and apa.proveedor_at_id = p_ref and coalesce(apa.activo,true)
  union
  select distinct v.comp_id
    from v_contraparte_parte v
    join componente c on c.id = v.comp_id and c.sector_id in (10,11)
   where p_tipo = 'tallerista' and v.tipo = 'tallerista' and v.lado = 'entrada' and v.ref_id = p_ref
),
todos as (
  select c.id comp_id, c.codigo cod, c.descripcion descr, c.sector_id sec_id, s.nombre sector,
         case when c.sector_id = 10
                then nullif(c.entrega_uni_x,0)
              else (select pa.valor::numeric from parametro pa where pa.clave = 'caja_uni_x_paquete')
         end factor,
         coalesce((select i.cantidad from inventario i
                    where i.componente_id = c.id
                      and i.ubicacion_id = ubic_de('sector', c.sector_id) limit 1), 0) online_sector,
         exists (select 1 from propios p where p.comp_id = c.id) propio
    from componente c join sector s on s.id = c.sector_id
   where c.sector_id in (10,11) and not coalesce(c.discontinuado,false)
)
select jsonb_build_object(
  'oficiales', (select coalesce(jsonb_agg(jsonb_build_object(
                  'comp_id',comp_id,'cod',cod,'desc',descr,'sec_id',sec_id) order by cod),'[]'::jsonb)
                 from todos where propio),
  'otros',     (select coalesce(jsonb_agg(jsonb_build_object(
                  'comp_id',comp_id,'cod',cod,'desc',descr,'sec_id',sec_id,'sector',sector,
                  'factor',factor,'online_sector',online_sector) order by cod),'[]'::jsonb)
                 from todos where not propio));
$function$
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
  perform "GP2"._exigir_autorizado();  -- seguridad punto 1 fase B (2026-09-28)
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

-- ---------- chequear_sustituto ----------
CREATE OR REPLACE FUNCTION "GP2".chequear_sustituto(p_destino_tipo text, p_destino_id bigint, p_comp_id bigint, p_sustituye_comp_id bigint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
declare v_sec_s int; v_sec_o int; v_cod_s text; v_cod_o text; v_ok boolean;
begin
  if p_sustituye_comp_id is null then return; end if;
  if p_sustituye_comp_id = p_comp_id then
    raise exception 'Un carton no puede reemplazarse a si mismo';
  end if;
  select sector_id, codigo into v_sec_s, v_cod_s from componente where id = p_comp_id;
  select sector_id, codigo into v_sec_o, v_cod_o from componente where id = p_sustituye_comp_id;
  if v_sec_o is null then
    raise exception 'El carton reemplazado (%) no existe', p_sustituye_comp_id;
  end if;
  if v_sec_s is distinct from v_sec_o then
    raise exception 'No se puede mandar % (sector %) en reemplazo de % (sector %): tiene que ser del mismo sector',
      v_cod_s, v_sec_s, v_cod_o, v_sec_o;
  end if;
  if v_sec_o not in (10, 11) then
    raise exception 'Solo se reemplazan cartones (sector 10) y cajas (sector 11)';
  end if;
  if p_destino_tipo = 'proveedor_at' then
    select exists (
      select 1 from articulo_prov_at apa
       join articulo a on a.codigo = apa.cod_art
       join articulo_componente ac on ac.articulo_id = a.id
      where apa.proveedor_at_id = p_destino_id and coalesce(apa.activo,true)
        and ac.componente_id = p_sustituye_comp_id) into v_ok;
  else
    select exists (
      select 1 from v_contraparte_parte v
       where v.tipo = 'tallerista' and v.lado = 'entrada'
         and v.ref_id = p_destino_id and v.comp_id = p_sustituye_comp_id) into v_ok;
  end if;
  if not v_ok then
    raise exception '% no es un carton de ese destino: no hay articulo suyo que lo consuma', v_cod_o;
  end if;
end $function$
;

-- ---------- cod_norm ----------
CREATE OR REPLACE FUNCTION "GP2".cod_norm(p text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select nullif(regexp_replace(upper(regexp_replace(coalesce(p,''), '[^A-Za-z0-9]', '', 'g')), '^0+', ''), '');
$function$
;

-- ---------- comp_terminado_de ----------
CREATE OR REPLACE FUNCTION "GP2".comp_terminado_de(p_art bigint)
 RETURNS bigint
 LANGUAGE sql
 STABLE
 SET search_path TO 'GP2'
AS $function$
  select coalesce(
    (select rp.comp_entrada_id
       from ruta r join ruta_paso rp on rp.ruta_id = r.id
      where r.articulo_id = p_art and rp.tipo_paso = 'virgilio' and rp.comp_entrada_id is not null
      order by rp.ruta_id limit 1),
    (select c.id from componente c join articulo a on a.id = p_art
      where c.sector_id = 12 and c.codigo = a.codigo
      order by c.id limit 1))
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
    'maximo',  (select i.maximo from inventario i cross join u
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

-- ---------- consumo_bundle ----------
CREATE OR REPLACE FUNCTION "GP2".consumo_bundle()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
with desp as (
  select coalesce(valor,4) pct from parametro where clave='inyeccion_desperdicio_pct'
), resina as (
  -- una resina no se consume por receta: la gastan las piezas que se inyectan con ella
  select r.id comp_id,
         round(sum(coalesce(v.consumo_uni_mes,0)*coalesce(p.kg_x_uni,0))
               * (1 + (select pct from desp)/100.0), 2) kg_mes,
         count(p.id) piezas
    from componente r
    join componente p on p.material_id = r.id
    left join v_consumo_componente v on v.componente_id = p.id
   where r.sector_id = 14
   group by r.id
), filas as (
  select c.id comp_id, c.codigo cod, c.descripcion desc_, c.sector_id, s.nombre sector,
         c.unidad_medida um, c.kg_x_uni, c.uni_x_cajon,
         (c.sector_id = 5) es_fleje, (c.sector_id = 14) es_resina,
         v.consumo_uni_mes uni_mes,
         coalesce(fk.consumo_kg_mes, rs.kg_mes) kg_mes,
         coalesce(v.en_articulos, rs.piezas) en_articulos,
         case when coalesce(c.uni_x_cajon,0) > 0 and v.consumo_uni_mes is not null
              then round(v.consumo_uni_mes / c.uni_x_cajon, 2) end cajones_mes
    from componente c
    join sector s on s.id = c.sector_id
    left join v_consumo_componente v on v.componente_id = c.id
    left join v_consumo_fleje_kg fk on fk.componente_id = c.id and c.sector_id = 5
    left join resina rs on rs.comp_id = c.id
   where v.consumo_uni_mes is not null or rs.kg_mes is not null
)
select jsonb_build_object(
  'filas', coalesce((select jsonb_agg(jsonb_build_object(
      'comp_id', comp_id, 'cod', cod, 'desc', desc_,
      'sector_id', sector_id, 'sector', sector,
      'um', um, 'kg_x_uni', kg_x_uni, 'uni_x_cajon', uni_x_cajon,
      'es_fleje', es_fleje, 'es_resina', es_resina,
      'base', case when es_resina then 'piezas' else 'articulos' end,
      'uni_mes', uni_mes, 'kg_mes', kg_mes,
      'cajones_mes', cajones_mes, 'en_articulos', en_articulos)
      order by coalesce(uni_mes, kg_mes) desc nulls last, cod) from filas), '[]'::jsonb),
  'sectores', coalesce((select jsonb_agg(jsonb_build_object(
      'id', sector_id, 'nombre', sector, 'n', n,
      'unidad', unidad, 'uni_mes', t_uni, 'kg_mes', t_kg, 'cajones_mes', t_caj)
      order by n desc)
    from (select sector_id, sector, count(*) n,
                 round(sum(uni_mes)) t_uni,
                 round(sum(kg_mes), 2) t_kg,
                 round(sum(cajones_mes), 1) t_caj,
                 case when bool_or(es_fleje) or bool_or(es_resina) then 'kg' else 'uni' end unidad
            from filas group by sector_id, sector) x), '[]'::jsonb),
  'generado_en', now());
$function$
;

-- ---------- consumo_detalle ----------
CREATE OR REPLACE FUNCTION "GP2".consumo_detalle(p_comp_id bigint)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
with cab as (
  select c.id, c.codigo, c.descripcion, c.sector_id, c.uni_x_cajon, s.nombre sector,
         (c.sector_id = 5) es_fleje, (c.sector_id = 14) es_resina,
         (select coalesce(valor,4) from parametro where clave='inyeccion_desperdicio_pct') desp_pct
    from componente c left join sector s on s.id = c.sector_id
   where c.id = p_comp_id
), piezas as (
  select p.codigo, p.descripcion, p.kg_x_uni,
         coalesce(v.consumo_uni_mes,0) uni_mes,
         coalesce(v.consumo_uni_mes,0) * coalesce(p.kg_x_uni,0)
           * (1 + (select desp_pct from cab)/100.0) kg_mes
    from componente p
    join cab on cab.es_resina and p.material_id = cab.id
    left join v_consumo_componente v on v.componente_id = p.id
)
select jsonb_build_object(
  'comp_id', c.id,
  'codigo', c.codigo,
  'descripcion', c.descripcion,
  'sector', c.sector,
  'es_fleje', c.es_fleje,
  'es_resina', c.es_resina,
  'base', case when c.es_resina then 'piezas' else 'articulos' end,
  'desperdicio_pct', case when c.es_resina then c.desp_pct end,
  'uni_x_cajon', c.uni_x_cajon,
  'total_uni_mes', (select round(sum(d.uni_mes)) from v_consumo_demanda d where d.componente_id = c.id),
  'total_kg_mes', coalesce(
      (select fk.consumo_kg_mes from v_consumo_fleje_kg fk where fk.componente_id = c.id),
      (select round(sum(kg_mes),2) from piezas)),
  'piezas', coalesce((
    select jsonb_agg(jsonb_build_object(
             'codigo', codigo, 'descripcion', descripcion,
             'kg_x_uni', kg_x_uni,
             'uni_mes', round(uni_mes),
             'kg_mes', round(kg_mes, 2)
           ) order by kg_mes desc) from piezas), '[]'::jsonb),
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
             where rp.comp_entrada_id = c.id and c.es_fleje
               and coalesce(m.partes_por_kilo_de_fleje,0) > 0) p
      join v_consumo_demanda d2 on d2.articulo_id = p.art_id and d2.componente_id = p.sal
      where p.art_id = a.id
    ) kg on true
    where d.componente_id = c.id
  ), '[]'::jsonb)
)
from cab c;
$function$
;

-- ---------- control_entrega_bundle ----------
CREATE OR REPLACE FUNCTION "GP2".control_entrega_bundle(p_dias integer DEFAULT 7)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
with base as (
  -- P.S.: entrega la pieza PROCESADA (comp_transformado_id) y consume la SC (comp_id)
  select m.id, m.fecha, 'proveedor_servicio'::text as cp_tipo, ps.id as cp_id, ps.nombre as cp_nombre,
         m.comp_id as sc_id, m.comp_transformado_id as sp_id,
         coalesce(m.cantidad_transformada, m.cantidad) as declarado,
         m.unidad_destino as unidad, m.cajones,
         ps.entrega_unidad, ps.entrega_uni_x, ps.envio_unidad, ps.envio_uni_x
    from movimiento m
    join ubicacion u on u.id = m.ubic_origen_id and u.tipo = 'proveedor_servicio'
    join proveedor_servicio ps on ps.id = u.ref_id
   where m.tipo_mov = 'entrega_ps'
  union all
  -- TALLERISTA: entrega comp_id, y lo que consumio son los movimientos hijos (mov_padre_id). El
  -- ENVASE del control lo dice la PIEZA (bolsas de 120 en GRJ5/GRJ6, cajones en el resto) y viaja
  -- en las mismas claves que usa el P.S., asi el front no aprende un modelo nuevo.
  select m.id, m.fecha, 'tallerista', t.id, t.nombre,
         (select h.comp_id from movimiento h
           where h.mov_padre_id = m.id and h.tipo_mov = 'consumo_tall' order by h.id limit 1),
         m.comp_id,
         m.cantidad, m.unidad_destino, m.cajones,
         coalesce(sp.entrega_unidad, 'cajones'), coalesce(sp.entrega_uni_x, sp.uni_x_cajon),
         null::text, null::numeric
    from movimiento m
    join ubicacion u on u.id = m.ubic_origen_id and u.tipo = 'tallerista'
    join tallerista t on t.id = u.ref_id
    join componente sp on sp.id = m.comp_id
   where m.tipo_mov = 'entrega_tallerista'
), fila as (
  select b.*, sc.codigo sc_cod, sc.descripcion sc_desc, sc.uni_x_cajon sc_unixcaj,
         sp.codigo sp_cod, sp.descripcion sp_desc, sp.unidad_medida sp_um,
         sp.kg_x_uni sp_kgxuni, sp.uni_x_cajon sp_unixcaj, ssp.nombre sp_sector,
         c.id ctrl_id, c.declarado ctrl_decl, c.controlado, c.controlado_cajones,
         c.controlado_en, c.controlado_por,
         -- ¿ESTA PIEZA SE PESA EN EL CONTROL? Con la pieza medida en kg, siempre. En un tallerista,
         -- una pieza que declara su propio envase se CUENTA y no se pesa [usuario 2026-09-23: "El
         -- remito de las bombillas en uni. Control en bolsas. El remito de la cuchilla en kg y
         -- control kg y cajones"]. En un P.S., alcanza con que la pieza tenga kg_x_uni.
         case when lower(coalesce(b.unidad,'uni')) = 'kg' then true
              when b.cp_tipo = 'tallerista' then (sp.entrega_unidad is null and coalesce(sp.kg_x_uni,0) > 0)
              else coalesce(sp.kg_x_uni,0) > 0 end as pesa
    from base b
    join componente sp on sp.id = b.sp_id
    left join componente sc on sc.id = b.sc_id
    left join sector ssp on ssp.id = sp.sector_id
    left join entrega_control c on c.movimiento_id = b.id
   where (c.id is null or b.fecha >= now() - make_interval(days => greatest(coalesce(p_dias,7), 1)))
)
select jsonb_build_object(
  'generado_en', now(),
  -- tolerancia del control: 5 % [usuario 2026-09-23, "todo control no puede exceder el 5% de
  -- diferencia"]. UNA SOLA CLAVE para todos los controles de la casa: la que era tol_ctrl_ps_pct
  -- aca y tol_ctrl_peso_pct en el pesaje de insumos es hoy tol_ctrl_pct, y vale 5.
  'tol_pct', coalesce((select valor::numeric from parametro where clave = 'tol_ctrl_pct'), 5),
  'pend', coalesce((select jsonb_agg(jsonb_build_object(
            'mov_id', id, 'fecha', fecha, 'cp_tipo', cp_tipo, 'cp_id', cp_id, 'cp_nombre', cp_nombre,
            'sc_cod', sc_cod, 'sc_desc', sc_desc, 'sc_unixcaj', sc_unixcaj,
            'sp_id', sp_id, 'sp_cod', sp_cod, 'sp_desc', sp_desc,
            'sp_um', sp_um, 'sp_kgxuni', sp_kgxuni, 'sp_unixcaj', sp_unixcaj, 'sp_sector', sp_sector,
            'entrega_unidad', entrega_unidad, 'entrega_uni_x', entrega_uni_x,
            'envio_unidad', envio_unidad, 'envio_uni_x', envio_uni_x,
            'pesa', pesa,
            'declarado', declarado, 'unidad', unidad, 'cajones', cajones
          ) order by fecha desc, id desc) from fila where ctrl_id is null), '[]'::jsonb),
  'hechos', coalesce((select jsonb_agg(jsonb_build_object(
            'mov_id', id, 'fecha', fecha, 'cp_tipo', cp_tipo, 'cp_nombre', cp_nombre,
            'sp_cod', sp_cod, 'sp_desc', sp_desc, 'unidad', unidad,
            'declarado', ctrl_decl, 'controlado', controlado, 'cajones', controlado_cajones,
            'diff', controlado - ctrl_decl,
            'controlado_en', controlado_en, 'controlado_por', controlado_por
          ) order by controlado_en desc) from fila where ctrl_id is not null), '[]'::jsonb),
  -- INSUMOS SIN CONTROLAR (2026-09-30) [Nazareno: "Me gustaria que aparezca en el boton de control
  -- ... Tendrias que poner los de talleristas, p.s. y prov de insumo"]. El control de un insumo que
  -- se controla en OTRA pagina (control-remaches / control-cajas) solo se abria con la redireccion
  -- automatica al guardar la recepcion: si el operario salia, quedaba controlado=false y ninguna
  -- pantalla lo llevaba de vuelta (caso real: E13, C13, GRJ31 y GRJ32 de Importado). Va AGRUPADO
  -- por sector y proveedor (una fila por pantalla de control, no una por recepcion) y la pantalla
  -- decide con gp2-control-insumo.js (GP2CI) a donde lleva cada grupo: un grupo sin pantalla de
  -- control no se muestra. via='pesaje' son los flejes, cuyo control es el pesaje por pallet de
  -- Recepcion de Insumos y no marca controlado: mismo criterio que pendientesDePesaje() de esa
  -- pantalla (pallets sin pesar o 'sin controlar' en v_recepcion_control).
  'insumos_pend', coalesce((select jsonb_agg(jsonb_build_object(
            'via', g.via, 'sector_id', g.sector_id, 'sector', g.sector, 'proveedor', g.proveedor,
            'n', g.n, 'codigos', to_jsonb(g.codigos), 'desde', g.desde
          ) order by g.desde, g.sector_id, g.proveedor)
      from (select 'control'::text as via, c.sector_id, s.nombre as sector,
                   nullif(trim(r.proveedor), '') as proveedor, count(*) as n,
                   (array_agg(distinct c.codigo order by c.codigo))[1:8] as codigos, min(r.fecha) as desde
              from recepcion_insumo r
              join componente c on c.id = r.componente_id
              left join sector s on s.id = c.sector_id
             where not coalesce(r.controlado, false) and c.sector_id <> 5
             group by c.sector_id, s.nombre, nullif(trim(r.proveedor), '')
            union all
            select 'pesaje', c.sector_id, s.nombre, nullif(trim(r.proveedor), ''), count(*),
                   (array_agg(distinct c.codigo order by c.codigo))[1:8], min(r.fecha)
              from v_recepcion_control v
              join recepcion_insumo r on r.id = v.recepcion_id
              join componente c on c.id = r.componente_id
              left join sector s on s.id = c.sector_id
             where c.sector_id = 5 and (v.pallets_sin_pesar > 0 or v.estado = 'sin controlar')
             group by c.sector_id, s.nombre, nullif(trim(r.proveedor), '')) g), '[]'::jsonb)
);
$function$;
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
  -- Hibridos (Fleje90/Charcas, Chapa430/Eclipse): la MP BRUTA (ALAMBRE, FLEJE_DESCORAZONADOR)
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
      and comp_id not in (select id from componente where codigo in ('ALAMBRE','FLEJE_DESCORAZONADOR'))
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
    -- UNA SOLA TOLERANCIA DE CONTROL EN TODA LA CASA: 5 % [usuario 2026-09-23, textual:
    -- "todo control no puede exceder el 5% de diferencia"]. Antes este control usaba un 10 %
    -- escrito en control-remaches.js y el pesaje de flejes un 2 % (tol_ctrl_peso_pct), que se
    -- renombro a esta clave.
    'tol_pct', coalesce((select valor from parametro where clave = 'tol_ctrl_pct'), 5),
    'sector', (select nombre from sector where id = p_sector_id),
    'sector_id', p_sector_id,
    'recepciones', coalesce((select jsonb_agg(row_to_json(rec)) from rec), '[]'::jsonb),
    'uni_x_paq_default', coalesce((select valor::numeric from parametro where clave = 'caja_uni_x_paquete'), 25)
  );
$function$
;

-- ---------- controlar_entrega ----------
CREATE OR REPLACE FUNCTION "GP2".controlar_entrega(p_mov_id bigint, p_cantidad numeric, p_cajones numeric DEFAULT NULL::numeric, p_usuario text DEFAULT NULL::text, p_nota text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
declare
  m movimiento%rowtype;
  v_u text; v_decl numeric; v_cons numeric; v_cod text; v_id bigint;
  v_factor numeric; v_hijos int := 0; v_comp bigint;
begin
  perform "GP2"._exigir_autorizado();  -- seguridad punto 1 fase B (2026-09-28)
  if p_cantidad is null or p_cantidad <= 0 then
    raise exception 'La cantidad controlada tiene que ser mayor a 0.';
  end if;
  select * into m from movimiento where id = p_mov_id;
  if not found then raise exception 'El movimiento % no existe.', p_mov_id; end if;
  if m.tipo_mov not in ('entrega_ps', 'entrega_tallerista') then
    raise exception 'El movimiento % no es una entrega de un tercero (es %).', p_mov_id, m.tipo_mov;
  end if;
  if exists (select 1 from entrega_control c where c.movimiento_id = p_mov_id) then
    raise exception 'Esa entrega ya fue controlada.';
  end if;

  -- lo que decia el REMITO. En el P.S. es la cantidad ENTREGADA (cantidad_transformada, la pieza
  -- procesada); en el tallerista, la cantidad del movimiento, que ya es lo que entrego.
  v_u    := case when lower(coalesce(m.unidad_destino,'uni')) = 'kg' then 'kg' else 'uni' end;
  v_decl := case when m.tipo_mov = 'entrega_ps' then coalesce(m.cantidad_transformada, m.cantidad)
                 else m.cantidad end;
  v_comp := coalesce(m.comp_transformado_id, m.comp_id);

  insert into entrega_control(movimiento_id, declarado, declarado_unidad, declarado_cajones,
                              controlado, controlado_cajones, controlado_por, nota)
  values (p_mov_id, v_decl, v_u, m.cajones, p_cantidad, p_cajones, p_usuario, p_nota)
  returning id into v_id;

  -- EL STOCK QUEDA CON LO CONTROLADO (mismo criterio que controlar_recepcion_kg en insumos).
  if m.tipo_mov = 'entrega_ps' then
    -- la entrega del P.S. es 1 a 1: la SC consumida es la misma cantidad que la SP recibida,
    -- expresada en la canonica de la SP (igual que crear_entrega_ps).
    v_cons := to_canonical(m.comp_transformado_id, p_cantidad, v_u);
    update movimiento
       set cantidad = v_cons, cantidad_transformada = p_cantidad,
           cajones = coalesce(p_cajones, cajones)
     where id = p_mov_id;
  else
    -- TALLERISTA: se pisa lo entregado Y SE ESCALAN LOS CONSUMOS con el mismo factor [usuario
    -- 2026-09-23, eligiendo entre las dos opciones: "entrego 98 de 100 -> consumio 98"]. Los
    -- consumos son los movimientos hijos (mov_padre_id), que crear_entrega_tallerista dejo
    -- colgados de esta entrega. Sin esa columna no se sabria cuales son: todas las entregas del
    -- dia comparten la misma fecha.
    v_factor := p_cantidad / nullif(v_decl, 0);
    if v_factor is not null and v_factor <> 1 then
      update movimiento set cantidad = round(cantidad * v_factor, 6)
       where mov_padre_id = p_mov_id;
      get diagnostics v_hijos = row_count;
    end if;
    v_cons := p_cantidad;
    update movimiento
       set cantidad = p_cantidad, cajones = coalesce(p_cajones, cajones)
     where id = p_mov_id;
  end if;

  select codigo into v_cod from componente where id = v_comp;
  return jsonb_build_object('ok', true, 'id', v_id, 'movimiento_id', p_mov_id, 'cod', v_cod,
    'tipo_mov', m.tipo_mov, 'declarado', v_decl, 'controlado', p_cantidad, 'unidad', v_u,
    'diff', p_cantidad - v_decl, 'cajones', p_cajones, 'consumo_canon', v_cons,
    'consumos_ajustados', v_hijos);
end $function$
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
  perform "GP2"._exigir_autorizado();  -- seguridad punto 1 fase B (2026-09-28)
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
  perform "GP2"._exigir_autorizado();  -- seguridad punto 1 fase B (2026-09-28)
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
  perform "GP2"._exigir_autorizado();  -- seguridad punto 1 fase B (2026-09-28)
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
        v_art_id bigint; v_uxc numeric; v_uni numeric;
        v_aviso text := null; v_res jsonb := null;
begin
  perform "GP2"._exigir_autorizado();  -- seguridad punto 1 fase B (2026-09-28)
  if coalesce(p_cajas,0) <= 0 then
    raise exception 'La cantidad de cajas tiene que ser mayor a cero';
  end if;
  if not exists (select 1 from proveedor_at where id = p_prov_at_id) then
    raise exception 'El proveedor % no existe', p_prov_at_id;
  end if;

  -- La asignacion se chequea por EXISTENCIA de la fila, no por su descripcion: habia 5 filas del
  -- catalogo con descripcion vacia (193, 231, 232, 233, 591) y la entrega se rechazaba diciendo
  -- que el articulo no estaba asignado, que era falso.
  if not exists (select 1 from articulo_prov_at a
                  where a.proveedor_at_id = p_prov_at_id and a.cod_art = p_cod_art) then
    raise exception 'El articulo % no esta asignado a ese proveedor', p_cod_art;
  end if;

  select a.id, a.articulos_por_caja into v_art_id, v_uxc from articulo a where a.codigo = p_cod_art;

  select nullif(btrim(coalesce(a.descripcion,'')),'') into v_desc
    from articulo_prov_at a
   where a.proveedor_at_id = p_prov_at_id and a.cod_art = p_cod_art
   limit 1;
  v_desc := coalesce(v_desc, (select nullif(btrim(coalesce(descripcion,'')),'') from articulo where id = v_art_id), p_cod_art);

  v_fecha := coalesce(p_fecha, (now() at time zone 'America/Argentina/Buenos_Aires')::date);

  insert into entrega_prov_at
    (proveedor_at_id, cod_art, descripcion, cantidad_cajas, remito,
     fecha_rto, dia_mes, tipo_entrega)
  values
    (p_prov_at_id, p_cod_art, v_desc, p_cajas,
     nullif(btrim(coalesce(p_remito,'')),''),
     v_fecha, to_char(v_fecha, 'DD/MM/YY'), null)
  returning id into v_id;

  -- Ledger: sin esto el articulo comprado terminado nunca entraba al stock y el carton/caja que
  -- se le mando al proveedor no se consumia nunca.
  v_uni := p_cajas * coalesce(nullif(v_uxc,0), 1);
  if v_art_id is null then
    v_aviso := 'Entrega registrada, pero NO se movio stock: el codigo '||p_cod_art||' no es un articulo de GP2';
  elsif not exists (select 1 from articulo_componente ac where ac.articulo_id = v_art_id) then
    v_aviso := 'Entrega registrada, pero NO se movio stock: el articulo '||p_cod_art||' no tiene receta cargada';
  else
    begin
      v_res := "GP2".recepcion_virgilio(jsonb_build_object(
        'fecha', v_fecha::timestamptz, 'origen_tipo', 'proveedor_at', 'origen_id', p_prov_at_id,
        'remito', p_remito,
        'items', jsonb_build_array(jsonb_build_object('articulo_id', v_art_id, 'cantidad', v_uni))));
    exception when others then
      v_aviso := 'Entrega registrada, pero NO se movio stock: '||sqlerrm;
    end;
  end if;

  return jsonb_build_object('ok', true, 'id', v_id, 'descripcion', v_desc,
    'unidades', v_uni, 'stock', v_res, 'aviso', v_aviso);
end $function$
;

-- ---------- crear_entrega_ps ----------
CREATE OR REPLACE FUNCTION "GP2".crear_entrega_ps(p_ps_id bigint, p_comp_sc_id bigint, p_comp_sp_id bigint, p_kg numeric, p_fecha timestamp with time zone DEFAULT now(), p_cajones numeric DEFAULT NULL::numeric, p_faltante boolean DEFAULT false, p_unidad text DEFAULT 'kg'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
declare v_ps bigint; v_dest bigint; v_sec_id bigint; v_secsp text; v_umsp text;
        v_codsp text; v_codsc text; v_cons numeric; v_id bigint; v_u text;
        v_por_oc boolean; v_prov_sp text; v_oc jsonb := '[]'::jsonb;
begin
  perform "GP2"._exigir_autorizado();  -- seguridad punto 1 fase B (2026-09-28)
  if p_kg is null or p_kg <= 0 then raise exception 'La cantidad debe ser mayor a 0'; end if;
  v_u := case when lower(btrim(coalesce(p_unidad,'kg'))) = 'kg' then 'kg' else 'uni' end;
  select c.sector_id, s.nombre, c.codigo, c.unidad_medida, nullif(btrim(coalesce(c.proveedor,'')),'')
    into v_sec_id, v_secsp, v_codsp, v_umsp, v_prov_sp
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
  v_cons := to_canonical(p_comp_sp_id, p_kg, v_u);
  insert into movimiento(fecha,tipo_mov,comp_id,ubic_origen_id,ubic_destino_id,cantidad,unidad_origen,
                         comp_transformado_id,cantidad_transformada,unidad_destino,cajones,faltante)
  values (coalesce(p_fecha,now()),'entrega_ps',p_comp_sc_id,v_ps,v_dest,v_cons,
          case when lower(coalesce(v_umsp,'unidad'))='kg' then 'kg' else 'uni' end,
          p_comp_sp_id,p_kg,v_u,p_cajones,coalesce(p_faltante,false))
  returning id into v_id;

  -- FASONERO (proveedor_servicio.pedido_por_oc, hoy Maspoli): a este PS se le emite O.C. por la
  -- pieza que entrega, asi que la entrega TIENE que descontar esa O.C. -- si no, la orden queda
  -- abierta para siempre y el sugerido de materia prima a enviarle (que sale del pendiente de la
  -- O.C.) nunca baja. Mismo cruce FIFO que usa la recepcion de insumos, priorizando la O.C. del
  -- proveedor de la pieza. Los PS normales no tienen O.C. y no pasan por aca.
  select ps.pedido_por_oc into v_por_oc from proveedor_servicio ps where ps.id = p_ps_id;
  if coalesce(v_por_oc, false) then
    v_oc := "GP2"._aplicar_recepcion_a_oc(p_comp_sp_id, p_kg, v_u, v_prov_sp);
  end if;

  return jsonb_build_object('ok',true,'id',v_id,'sc',v_codsc,'sp',v_codsp,'cantidad',p_kg,'unidad',v_u,
    'kg',case when v_u='kg' then p_kg end,
    'consumo_canon',v_cons,'cajones',p_cajones,'faltante',coalesce(p_faltante,false),'oc',v_oc);
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
                           cantidad, unidad_origen, unidad_destino, mov_padre_id)
    values (coalesce(p_fecha, now()), 'consumo_tall', p_comp_entrada_id,
            v_ubic_tall, null, p_cantidad, v_unidad, v_unidad, v_mov_id)
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
                               cantidad, unidad_origen, unidad_destino, mov_padre_id)
        values (coalesce(p_fecha, now()), 'consumo_tall', r.hijo_id, v_ubic_tall, null,
                v_hijo_qty, v_hijo_um, v_hijo_um, v_mov_id)
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
CREATE OR REPLACE FUNCTION "GP2".crear_envio_prov_at(p_prov_at_id bigint, p_comp_id bigint, p_cantidad numeric, p_unidad text, p_fecha timestamp with time zone DEFAULT NULL::timestamp with time zone, p_sustituye_comp_id bigint DEFAULT NULL::bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
declare v_ubic_o bigint; v_ubic_d bigint; v_sector int; v_mov bigint;
        v_unidad text := lower(trim(coalesce(p_unidad,'uni')));
begin
  perform "GP2"._exigir_autorizado();  -- seguridad punto 1 fase B (2026-09-28)
  if coalesce(p_cantidad,0) <= 0 then raise exception 'Cantidad invalida'; end if;
  if v_unidad not in ('kg','uni') then
    raise exception 'Unidad invalida: "%". Debe ser "kg" o "uni".', coalesce(p_unidad,'null');
  end if;
  select sector_id into v_sector from componente where id = p_comp_id;
  if v_sector is null then raise exception 'Componente % no existe', p_comp_id; end if;
  if v_sector not in (10, 11) then
    raise exception 'Solo se envia carton (sector 10) o cajas (sector 11) a los Prov AT';
  end if;
  perform "GP2".chequear_sustituto('proveedor_at', p_prov_at_id, p_comp_id, p_sustituye_comp_id);
  v_ubic_o := "GP2".ubic_de('sector', v_sector);
  v_ubic_d := "GP2".ubic_de('proveedor_at', p_prov_at_id);
  if v_ubic_o is null then raise exception 'No hay ubicacion para el sector % del componente %', v_sector, p_comp_id; end if;
  if v_ubic_d is null then raise exception 'El Prov AT % no tiene ubicacion', p_prov_at_id; end if;

  insert into movimiento (fecha, tipo_mov, comp_id, ubic_origen_id, ubic_destino_id, cantidad,
                          unidad_origen, unidad_destino, sustituye_comp_id)
  values (coalesce(p_fecha, now()), 'envio_prov_at', p_comp_id, v_ubic_o, v_ubic_d, p_cantidad,
          v_unidad, v_unidad, p_sustituye_comp_id)
  returning id into v_mov;
  return jsonb_build_object('ok', true, 'movimiento_id', v_mov,
                            'sustituye_comp_id', p_sustituye_comp_id);
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
  perform "GP2"._exigir_autorizado();  -- seguridad punto 1 fase B (2026-09-28)
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
CREATE OR REPLACE FUNCTION "GP2".crear_envio_tallerista(p_tallerista_id bigint, p_comp_id bigint, p_cantidad numeric, p_unidad text, p_fecha timestamp with time zone DEFAULT now(), p_sustituye_comp_id bigint DEFAULT NULL::bigint)
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
  perform "GP2"._exigir_autorizado();  -- seguridad punto 1 fase B (2026-09-28)
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

  perform "GP2".chequear_sustituto('tallerista', p_tallerista_id, p_comp_id, p_sustituye_comp_id);

  v_ubic_origen := "GP2".ubic_de('sector', v_sector_id);
  if v_ubic_origen is null then
    raise exception 'No existe ubicacion de sector para "%" (componente % / id=%).', coalesce(v_sector_nombre, v_sector_id::text), coalesce(v_cod,'?'), p_comp_id;
  end if;

  insert into movimiento(
    fecha, tipo_mov, comp_id, ubic_origen_id, ubic_destino_id, cantidad, unidad_origen,
    unidad_destino, sustituye_comp_id
  ) values (
    coalesce(p_fecha, now()), 'envio_tallerista', p_comp_id, v_ubic_origen, v_ubic_destino,
    p_cantidad, v_unidad, v_unidad, p_sustituye_comp_id
  ) returning id into v_new_id;

  return jsonb_build_object(
    'ok', true, 'id', v_new_id, 'tallerista', v_tall_nombre, 'codigo', v_cod,
    'sector', v_sector_nombre, 'ubic_origen_id', v_ubic_origen, 'ubic_destino_id', v_ubic_destino,
    'cantidad', p_cantidad, 'unidad', v_unidad, 'sustituye_comp_id', p_sustituye_comp_id
  );
end $function$
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
  v_err_carton text[];
begin
  perform "GP2"._exigir_autorizado();  -- seguridad punto 1 fase B (2026-09-28)
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

  -- REGLAS DE CARTON (REGLAS_OC_INSUMOS.md): multiplo de familia, multiplo por codigo,
  -- minimo por codigo, pedido minimo de la familia, pliegos de a 100 y comodin sacacorchos.
  -- Vivian SOLO en OC_GP2.html y esta funcion tiene EXECUTE para anon: aceptaba cualquier
  -- cantidad. Se valida ANTES de insertar la OC, asi no queda una cabecera huerfana.
  v_err_carton := "GP2"._oc_validar_carton(coalesce(p->'items','[]'::jsonb));
  if array_length(v_err_carton, 1) > 0 then
    raise exception 'El pedido de carton no cumple las reglas: %', array_to_string(v_err_carton, ' ');
  end if;

  -- PEDIDO MINIMO EN KG del proveedor de materia prima plastica. Misma historia que el
  -- carton: bloqueaba solo desde la pantalla. Idea 7329.
  v_err_carton := "GP2"._oc_validar_minimo_proveedor(coalesce(p->'items','[]'::jsonb));
  if array_length(v_err_carton, 1) > 0 then
    raise exception 'El pedido no llega al minimo del proveedor: %', array_to_string(v_err_carton, ' ');
  end if;

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
      -- la lista, y si tampoco hay lista, USD). La lista es la del proveedor ASIGNADO al
      -- componente si tiene precio suyo; si no, la mas nueva (2026-09-10).
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
        left join proveedor_insumo pi on pi.nombre = cc.proveedor
        where pp.componente_id = (it->>'comp_id')::bigint and pp.precio is not null
        order by (pi.cod_prov is not null and pp.cod_prov = pi.cod_prov) desc,
                 pp.fecha_lista desc nulls last, pp.id desc limit 1
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
      left join proveedor_insumo pi on pi.nombre = cc.proveedor
      where pp.componente_id = v_mp_id and pp.precio is not null
      order by (pi.cod_prov is not null and pp.cod_prov = pi.cod_prov) desc,
               pp.fecha_lista desc nulls last, pp.id desc limit 1
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

-- ---------- crear_preaviso ----------
CREATE OR REPLACE FUNCTION "GP2".crear_preaviso(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
declare
  v_tipo text := lower(coalesce(p->>'tipo_contraparte',''));
  v_ref  bigint := nullif(p->>'contraparte_id','')::bigint;
  v_fecha date := coalesce(nullif(p->>'fecha_promesa','')::date,
                           (now() at time zone 'America/Argentina/Buenos_Aires')::date);
  it jsonb; v_n integer := 0; v_ids bigint[] := '{}'; v_id bigint;
begin
  perform "GP2"._exigir_autorizado();  -- seguridad punto 1 fase B (2026-09-28)
  if v_tipo not in ('tallerista','proveedor_servicio','proveedor_at') then
    raise exception 'tipo_contraparte invalido: %', v_tipo;
  end if;
  if "GP2".ubic_de(v_tipo, v_ref) is null then
    raise exception 'La contraparte % % no existe o no tiene ubicacion', v_tipo, v_ref;
  end if;

  for it in select * from jsonb_array_elements(coalesce(p->'items','[]'::jsonb)) loop
    if coalesce((it->>'cantidad')::numeric, 0) <= 0 then continue; end if;
    insert into preaviso (tipo_contraparte, contraparte_id, comp_id, cantidad, unidad,
                          fecha_promesa, nota, creado_por)
    values (v_tipo, v_ref, (it->>'comp_id')::bigint, (it->>'cantidad')::numeric,
            coalesce(nullif(it->>'unidad',''), 'uni'), v_fecha,
            nullif(p->>'nota',''), nullif(p->>'usuario',''))
    returning id into v_id;
    v_ids := v_ids || v_id; v_n := v_n + 1;
  end loop;

  if v_n = 0 then raise exception 'No vino ningun item con cantidad'; end if;
  return jsonb_build_object('ok', true, 'n', v_n, 'ids', to_jsonb(v_ids));
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
        v_prov text; v_mat bigint; v_kg_x_uni numeric; v_prov_id bigint; v_ubic_iny bigint; v_pct numeric;
        v_kg_mat numeric; v_mov_mat bigint; v_material jsonb;
begin
  if p_cantidad is null or p_cantidad<=0 then raise exception 'La cantidad debe ser mayor a 0'; end if;
  select sector_id, unidad_medida, material_id, kg_x_uni, nullif(btrim(coalesce(proveedor,'')),'')
    into v_sec, v_um, v_mat, v_kg_x_uni, v_prov
    from "GP2".componente where id=p_comp_id;
  if v_sec is null then raise exception 'El insumo no existe'; end if;
  -- Que se puede comprar es una propiedad del COMPONENTE, no solo del sector: una pieza importada
  -- (C13, D1, Z23A, Z23B) vive en Sector Procesado y se recepciona igual (2026-09-11).
  if not "GP2"._es_comprable(p_comp_id) then raise exception 'El componente % no se compra (no es insumo, ni importado, ni lo entrega un PS hibrido)', p_comp_id; end if;
  v_ubic := "GP2".ubic_de('sector', v_sec);
  if v_ubic is null then raise exception 'No hay ubicacion para el sector del insumo'; end if;
  v_u := case when lower(coalesce(nullif(p_unidad,''), v_um, 'uni'))='kg' then 'kg' else 'uni' end;
  v_f := coalesce(p_fecha, now());
  insert into "GP2".movimiento(fecha,tipo_mov,comp_id,ubic_origen_id,ubic_destino_id,cantidad,unidad_origen,unidad_destino)
  values(v_f,'compra',p_comp_id,null,v_ubic,p_cantidad,v_u,v_u) returning id into v_movid;
  insert into "GP2".recepcion_insumo(fecha,componente_id,proveedor,remito,cantidad,unidad,movimiento_id)
  values(v_f,p_comp_id,nullif(btrim(coalesce(p_proveedor,'')),''),nullif(btrim(coalesce(p_remito,'')),''),p_cantidad,v_u,v_movid)
  returning id into v_recid;
  v_oc := "GP2"._aplicar_recepcion_a_oc(p_comp_id, p_cantidad, v_u, p_proveedor);

  v_prov := coalesce(nullif(btrim(coalesce(p_proveedor,'')),''), v_prov);
  if v_mat is not null and v_prov is not null then
    select id into v_prov_id from "GP2".proveedor_insumo where nombre = v_prov;
    v_ubic_iny := "GP2".ubic_de('inyector', v_prov_id);
    if v_ubic_iny is not null then
      if v_u = 'uni' and (v_kg_x_uni is null or v_kg_x_uni <= 0) then
        raise exception 'La pieza % tiene material asignado pero no tiene kg_x_uni: no se puede descontar el material del inyector', p_comp_id;
      end if;
      v_pct := coalesce((select valor from "GP2".parametro where clave='inyeccion_desperdicio_pct'), 0);
      v_kg_mat := round(((case when v_u='kg' then p_cantidad else p_cantidad * v_kg_x_uni end) * (1 + v_pct/100))::numeric, 3);
      insert into "GP2".movimiento(fecha,tipo_mov,comp_id,ubic_origen_id,ubic_destino_id,cantidad,unidad_origen,unidad_destino,nota)
      values(v_f,'consumo_inyector',v_mat,v_ubic_iny,null,v_kg_mat,'kg','kg',
             'Material consumido al inyectar '||p_cantidad||' '||v_u||' del comp '||p_comp_id||' (recepcion '||v_recid||')')
      returning id into v_mov_mat;
      update "GP2".recepcion_insumo
         set rollos_json = coalesce(rollos_json,'{}'::jsonb)
                        || jsonb_build_object('movimiento_material_id', v_mov_mat, 'material_id', v_mat,
                                              'kg_material', v_kg_mat, 'desperdicio_pct', v_pct)
       where id = v_recid;
      v_material := jsonb_build_object('material_id', v_mat, 'kg', v_kg_mat, 'movimiento_id', v_mov_mat,
                      'ubicacion_inyector_id', v_ubic_iny, 'desperdicio_pct', v_pct,
                      'stock_inyector', (select cantidad from "GP2".inventario where componente_id=v_mat and ubicacion_id=v_ubic_iny));
    end if;
  end if;

  return jsonb_build_object('ok',true,'recepcion_id',v_recid,'movimiento_id',v_movid,'unidad',v_u,'oc_cruzada',v_oc,'material',v_material);
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
  perform "GP2"._exigir_autorizado();  -- seguridad punto 1 fase B (2026-09-28)
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
  join "GP2".componente c on c.id = rp.comp_entrada_id and c.sector_id in (5, 13)
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
  -- 2026-09-23: se ocultan las rutas de articulos discontinuados
  where not coalesce(a.discontinuado, false)
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
    -- 2026-09-23: lo discontinuado no se muestra en el programa
    where not coalesce(a.discontinuado, false)
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
  perform "GP2"._exigir_autorizado();  -- seguridad punto 1 fase B (2026-09-28)
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
  perform "GP2"._exigir_autorizado();  -- seguridad punto 1 fase B (2026-09-28)
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
                  where a.proveedor_at_id = p.id and coalesce(a.activo,true)
                    and not exists (select 1 from articulo art where art.codigo = a.cod_art and art.discontinuado))
      ) order by p.nombre), '[]'::jsonb)
    from proveedor_at p where coalesce(p.activo,true)),
  'arts', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', a.id, 'prov_id', a.proveedor_at_id, 'cod_art', a.cod_art,
        'descripcion', a.descripcion, 'n_caja', a.n_caja, 'marca', a.marca
      ) order by a.cod_art), '[]'::jsonb)
    from articulo_prov_at a where coalesce(a.activo,true)
       and not exists (select 1 from articulo art where art.codigo = a.cod_art and art.discontinuado)),
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

-- ---------- enviar_material_inyector ----------
CREATE OR REPLACE FUNCTION "GP2".enviar_material_inyector(p_proveedor text, p_comp_id bigint, p_kg numeric, p_fecha timestamp with time zone DEFAULT now(), p_nota text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
declare v_prov_id bigint; v_ubic_iny bigint; v_ubic_mp bigint; v_codigo text; v_sec bigint; v_mov bigint;
        v_antes_mp numeric; v_desp_mp numeric; v_desp_iny numeric;
begin
  perform "GP2"._exigir_autorizado();  -- seguridad punto 1 fase B (2026-09-28)
  if p_kg is null or p_kg <= 0 then raise exception 'Los kg deben ser mayores a 0 (recibido: %)', p_kg; end if;
  select codigo, sector_id into v_codigo, v_sec from componente where id = p_comp_id;
  if v_codigo is null then raise exception 'El componente % no existe', p_comp_id; end if;
  if v_sec <> 14 then raise exception 'El componente % no es materia prima plastica (sector %)', v_codigo, v_sec; end if;
  select id into v_prov_id from proveedor_insumo where nombre = btrim(coalesce(p_proveedor,''));
  if v_prov_id is null then raise exception 'El proveedor "%" no existe', p_proveedor; end if;
  v_ubic_iny := "GP2".ubic_de('inyector', v_prov_id);
  if v_ubic_iny is null then raise exception 'El proveedor "%" no es un inyector (no tiene ubicacion tipo inyector)', p_proveedor; end if;
  v_ubic_mp := "GP2".ubic_de('sector', 14);
  select coalesce(cantidad,0) into v_antes_mp from inventario where componente_id=p_comp_id and ubicacion_id=v_ubic_mp;

  insert into movimiento(fecha, tipo_mov, comp_id, ubic_origen_id, ubic_destino_id, cantidad, unidad_origen, unidad_destino, nota)
  values (coalesce(p_fecha, now()), 'envio_inyector', p_comp_id, v_ubic_mp, v_ubic_iny, p_kg, 'kg', 'kg', nullif(btrim(coalesce(p_nota,'')),''))
  returning id into v_mov;

  select coalesce(cantidad,0) into v_desp_mp  from inventario where componente_id=p_comp_id and ubicacion_id=v_ubic_mp;
  select coalesce(cantidad,0) into v_desp_iny from inventario where componente_id=p_comp_id and ubicacion_id=v_ubic_iny;
  return jsonb_build_object('ok', true, 'movimiento_id', v_mov, 'codigo', v_codigo, 'kg', p_kg,
    'virgilio_antes', v_antes_mp, 'virgilio_despues', v_desp_mp, 'inyector_despues', v_desp_iny,
    'virgilio_negativo', (v_desp_mp < 0));
end $function$
;

-- ---------- enviar_material_virgilio ----------
CREATE OR REPLACE FUNCTION "GP2".enviar_material_virgilio(p_cod_virgilio text, p_bolsas numeric, p_inyector text, p_legajo text DEFAULT NULL::text, p_nota text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
declare v_comp bigint; v_kg_bolsa numeric; v_res jsonb;
begin
  if p_bolsas is null or p_bolsas <= 0 then raise exception 'Las bolsas deben ser mayores a 0'; end if;
  select id into v_comp from componente where sector_id = 14 and upper(btrim(codigo_virgilio)) = upper(btrim(coalesce(p_cod_virgilio,'')));
  if v_comp is null then raise exception 'El codigo "%" no es una bolsa de material conocida en GP2', p_cod_virgilio; end if;
  v_kg_bolsa := coalesce((select valor from parametro where clave='material_plastico_kg_x_bolsa'), 25);
  v_res := enviar_material_inyector(p_inyector, v_comp, p_bolsas * v_kg_bolsa, now(),
             concat_ws(' · ', 'Virgilio: ' || p_bolsas || ' bolsas', nullif('legajo ' || p_legajo, 'legajo '), nullif(btrim(coalesce(p_nota,'')), '')));
  return v_res || jsonb_build_object('bolsas', p_bolsas, 'kg_x_bolsa', v_kg_bolsa, 'codigo_virgilio', upper(btrim(p_cod_virgilio)));
end $function$
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
    from componente c join sector s on s.id=c.sector_id
    where c.sector_id in (10,11) and c.id not in (select comp_id from "GP2".v_componente_muerto)),
  -- prov_insumos (2026-09-15): mapa proveedor_at -> cartones/cajas que la receta de SUS articulos
  -- consume. La pantalla filtra los insumos por este set: a un prov solo se le muestra lo que
  -- realmente usa, no el catalogo completo de sector 10/11. Mismo cruce que stock_general_extra_bundle.
  'prov_insumos', (select coalesce(jsonb_object_agg(prov_at_id::text, arr),'{}'::jsonb) from (
      select apa.proveedor_at_id as prov_at_id, jsonb_agg(distinct ac.componente_id) arr
        from articulo_prov_at apa
        join articulo a on a.codigo = apa.cod_art and not a.discontinuado
        join articulo_componente ac on ac.articulo_id = a.id
        join componente c on c.id = ac.componente_id and c.sector_id in (10,11)
       where coalesce(apa.activo,true)
       group by apa.proveedor_at_id) x),
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
    and not ps0.hibrido
    and rp.comp_entrada_id not in (select comp_id from "GP2".v_componente_muerto)
    and (rp.comp_salida_id is null or rp.comp_salida_id not in (select comp_id from "GP2".v_componente_muerto))
),
ocp as (
  -- PENDIENTE DE O.C. por pieza: lo que el proveedor todavia nos debe entregar de una O.C. ya
  -- ENVIADA. Se mira 'enviada' y no 'borrador' por la misma razon que en el inyector
  -- (tablet_bundle.rep_iny): el borrador es un pedido que todavia no salio, y hasta que no sale
  -- no hay nada que mandarle. Baja sola al entregar: crear_entrega_ps descuenta el recibido.
  select oi.componente_id, sum(oi.cantidad - coalesce(oi.recibido,0)) pend
  from orden_compra_item oi join orden_compra o on o.id = oi.oc_id
  where o.estado = 'enviada' and oi.cantidad > coalesce(oi.recibido,0)
  group by oi.componente_id
),
fila as (
  select p.proveedor_id, ps.proceso,
         sc.id sc_id, sc.codigo sc_cod, sc.descripcion sc_desc,
         sc.unidad_medida sc_um, sc.kg_x_uni sc_kgxuni, sc.uni_x_cajon sc_unixcaj,
         ssc.nombre sc_sector,
         sp.id sp_id, sp.codigo sp_cod, sp.descripcion sp_desc, sp.uni_x_cajon sp_unixcaj,
         sp.unidad_medida sp_um, sp.kg_x_uni sp_kgxuni,
         (select i.cantidad from inventario i
           where i.componente_id=sc.id and i.ubicacion_id="GP2".ubic_de('sector', sc.sector_id) limit 1) online_sc,
         (select i.cantidad from inventario i where i.componente_id=sc.id
            and i.ubicacion_id="GP2".ubic_de('proveedor_servicio', p.proveedor_id) limit 1) online_ps,
         (select i.maximo from inventario i where i.componente_id=sc.id
            and i.ubicacion_id="GP2".ubic_de('proveedor_servicio', p.proveedor_id) limit 1) maximo,
         -- EL CAJON QUE ANOTO LOGISTICA (2026-09-21). Cuantas unidades entraron por cajon segun
         -- movimiento.cajones de los envios a ESTE proveedor de ESTA pieza. Con eso el stock en su
         -- poder se dice en los cajones que se le mandaron y no en el cajon teorico del maestro
         -- [usuario: "tiene que aparecer en su stock los cajones que escribe logistica, no los que
         -- se calcula a partir de los kg"]. null = nadie anoto cajones -> se usa sc.uni_x_cajon.
         (select v.uni_x_cajon_anotado from v_caj_contraparte v
           where v.componente_id = sc.id
             and v.ubicacion_id = "GP2".ubic_de('proveedor_servicio', p.proveedor_id)) sc_unixcaj_anot,
         (select i.cantidad from inventario i
           where i.componente_id=sp.id and i.ubicacion_id="GP2".ubic_de('sector', sp.sector_id) limit 1) online_sp,
         (select i.maximo from inventario i
           where i.componente_id=sp.id and i.ubicacion_id="GP2".ubic_de('sector', sp.sector_id) limit 1) maximo_sp,
         -- FASONERO (proveedor_servicio.pedido_por_oc, hoy Maspoli): unidades de ESTA salida que
         -- estan pendientes de O.C. enviada. null cuando el PS no es fasonero (el sugerido de ese
         -- sigue saliendo del maximo). OJO: este bundle lo comparten Envio a PS y Entrega PS, asi
         -- que el filtro "sin O.C. no se le manda nada" NO se hace aca -- lo hace la pantalla de
         -- ENVIO. Si se filtrara aca, un fasonero sin O.C. abierta desapareceria tambien de la
         -- ENTREGA y no habria como registrar lo que todavia debe.
         case when ps.pedido_por_oc
              then coalesce((select o3.pend from ocp o3 where o3.componente_id = p.sp_id), 0)
         end oc_pend
  from pares p
  join proveedor_servicio ps on ps.id=p.proveedor_id
  join componente sc on sc.id=p.sc_id
  join sector ssc on ssc.id=sc.sector_id
  left join componente sp on sp.id=p.sp_id
)
select jsonb_build_object(
  -- envio_unidad / envio_uni_x / envio_carga_unidad: la unidad de ENVIO del proveedor (bolsas de
  -- Ester, paquetes de AJ). Solo display: la pantalla muestra el sugerido en esa unidad (techo) y,
  -- si envio_carga_unidad='kg', la cantidad se escribe en kg con las bolsas al lado. Lo que se
  -- registra sigue yendo en kg a crear_envio_ps. [usuario 2026-09-17]
  -- pedido_por_oc: fasonero. En Envio a PS el sugerido deja de ser (maximo SP - online) y pasa a
  -- ser la suma de oc_pend de sus salidas menos lo que ya tiene en su poder, y sin O.C. no se le
  -- muestra nada para enviar.
  'ps', (select coalesce(jsonb_agg(jsonb_build_object(
            'id',ps.id,'nombre',ps.nombre,'cod_prov',ps.cod_prov,'proceso',ps.proceso,
            'envio_unidad',ps.envio_unidad,'envio_uni_x',ps.envio_uni_x,
            'envio_carga_unidad',ps.envio_carga_unidad,
            'pedido_por_oc',ps.pedido_por_oc
          ) order by ps.nombre),'[]'::jsonb)
        from proveedor_servicio ps
        where exists (select 1 from pares p where p.proveedor_id=ps.id)),
  'partes', (select coalesce(jsonb_object_agg(proveedor_id::text, arr),'{}'::jsonb) from (
        select proveedor_id, jsonb_agg(jsonb_build_object(
          'sc_id',sc_id,'sc_cod',sc_cod,'sc_desc',sc_desc,'sc_sector',sc_sector,
          'sc_um',sc_um,'sc_kgxuni',sc_kgxuni,'sc_unixcaj',sc_unixcaj,'sc_unixcaj_anot',sc_unixcaj_anot,
          'sp_id',sp_id,'sp_cod',sp_cod,'sp_desc',sp_desc,'sp_unixcaj',sp_unixcaj,
          'sp_um',sp_um,'sp_kgxuni',sp_kgxuni,
          'proceso',proceso,
          'online_sc',coalesce(online_sc,0),'online_ps',coalesce(online_ps,0),
          'online_sp',coalesce(online_sp,0),'maximo',maximo,'maximo_sp',maximo_sp,
          'oc_pend',oc_pend
        ) order by sc_cod) arr
        from fila group by proveedor_id) z)
);
$function$
;

-- ---------- fabricar_stock ----------
CREATE OR REPLACE FUNCTION "GP2".fabricar_stock(p_mid bigint, p_salida bigint, p_uni numeric, p_fecha timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
declare
  v_sal_um text; v_sec_sal int; v_usal bigint; v_ud text; v_partes numeric;
  r record; v_first boolean := true; v_movid bigint; v_first_mov bigint;
  v_ent_um text; v_sec_ent int; v_uent bigint; v_cant numeric; v_uo text;
  v_aviso text := null; v_n int := 0; v_has_bom boolean;
begin
  perform "GP2"._exigir_autorizado();  -- seguridad punto 1 fase B (2026-09-28)
  select partes_por_kilo_de_fleje into v_partes from matriz where id = p_mid;
  select unidad_medida, sector_id into v_sal_um, v_sec_sal from componente where id = p_salida;
  v_usal := "GP2".ubic_de('sector', v_sec_sal);
  v_ud := case when lower(coalesce(v_sal_um,'')) = 'kg' then 'kg' else 'uni' end;
  select exists(select 1 from componente_bom where componente_padre_id = p_salida) into v_has_bom;

  for r in
    select ent, qty from (
      select b.componente_hijo_id ent, b.cantidad qty
        from componente_bom b
       where v_has_bom and b.componente_padre_id = p_salida
      union all
      select rp.comp_entrada_id ent, max(coalesce(rp.cantidad,1)) qty
        from ruta_paso rp
       where (not v_has_bom) and rp.matriz_id = p_mid and rp.comp_salida_id = p_salida
         and rp.comp_entrada_id is not null
       group by rp.comp_entrada_id
    ) e
    order by ent
  loop
    select unidad_medida, sector_id into v_ent_um, v_sec_ent from componente where id = r.ent;
    v_uent := "GP2".ubic_de('sector', v_sec_ent);
    if lower(coalesce(v_ent_um,'')) = 'kg' then
      if v_partes is null or v_partes <= 0 then
        v_aviso := 'Registrado, pero una entrada en kg no se movio: la matriz no tiene rendimiento (ppk)';
        continue;
      end if;
      v_cant := (p_uni * r.qty) / v_partes; v_uo := 'kg';
    else
      v_cant := p_uni * r.qty; v_uo := 'uni';
    end if;
    if v_uent is null or v_usal is null then
      if v_aviso is null then v_aviso := 'Registrado, pero falta ubicacion de sector para alguna pieza'; end if;
      continue;
    end if;
    insert into movimiento(fecha,tipo_mov,comp_id,ubic_origen_id,ubic_destino_id,cantidad,unidad_origen,
                           comp_transformado_id,cantidad_transformada,unidad_destino)
    values (p_fecha,'fabricacion', r.ent, v_uent, v_usal, v_cant, v_uo, p_salida,
            case when v_first then p_uni else 0 end, v_ud)
    returning id into v_movid;
    if v_first then v_first_mov := v_movid; v_first := false; end if;
    v_n := v_n + 1;
  end loop;

  if v_n = 0 and v_aviso is null then
    v_aviso := 'Registrado (solo produccion): la matriz no tiene entrada/salida resuelta en las rutas';
  end if;
  return jsonb_build_object('movimiento_id', v_first_mov, 'n_entradas', v_n, 'aviso', v_aviso);
end $function$
;

-- ---------- factura_alias_guardar ----------
CREATE OR REPLACE FUNCTION "GP2".factura_alias_guardar(p_proveedor text, p_cod_prov text, p_comp_id bigint, p_descripcion text DEFAULT NULL::text, p_usuario text DEFAULT NULL::text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
declare v_id bigint;
begin
  perform "GP2"._exigir_autorizado();  -- seguridad punto 1 fase B (2026-09-28)
  if coalesce(trim(p_proveedor),'') = '' then raise exception 'Falta el proveedor'; end if;
  if "GP2".cod_norm(p_cod_prov) is null then raise exception 'Falta el codigo del proveedor'; end if;
  if not exists (select 1 from componente where id = p_comp_id) then
    raise exception 'El componente % no existe', p_comp_id;
  end if;

  insert into factura_alias (proveedor, cod_prov, componente_id, descripcion, creado_por)
  values (trim(p_proveedor), trim(p_cod_prov), p_comp_id, nullif(trim(coalesce(p_descripcion,'')),''), p_usuario)
  on conflict (proveedor, cod_prov)
  do update set componente_id = excluded.componente_id,
                descripcion   = coalesce(excluded.descripcion, factura_alias.descripcion),
                creado_por    = coalesce(excluded.creado_por, factura_alias.creado_por),
                creado_en     = now()
  returning id into v_id;

  return v_id;
end $function$
;

-- ---------- factura_lectura_permitida ----------
CREATE OR REPLACE FUNCTION "GP2".factura_lectura_permitida()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
declare
  v_hoy date := (now() at time zone 'America/Argentina/Buenos_Aires')::date;
  v_tope integer := coalesce((select valor::integer from parametro where clave = 'facturas_lecturas_x_dia'), 50);
  v_n integer;
begin
  perform "GP2"._exigir_autorizado();  -- seguridad punto 1 fase B (2026-09-28)
  insert into factura_lectura (dia, n, ultima_en) values (v_hoy, 1, now())
  on conflict (dia) do update set n = factura_lectura.n + 1, ultima_en = now()
  returning n into v_n;

  if v_n > v_tope then
    return jsonb_build_object('ok', false, 'usadas', v_n, 'tope', v_tope);
  end if;
  return jsonb_build_object('ok', true, 'usadas', v_n, 'tope', v_tope);
end $function$
;

-- ---------- factura_match ----------
CREATE OR REPLACE FUNCTION "GP2".factura_match(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'GP2', 'extensions'
AS $function$
declare
  v_prov_txt text := nullif(p->>'proveedor','');
  v_prov_id  bigint; v_prov_nom text; v_prov_cod text; v_prov_sim numeric;
  it jsonb; v_cod text; v_desc text; v_res jsonb := '[]'::jsonb;
  -- variables sueltas y NO un record: un record toma su forma del ultimo SELECT INTO y
  -- revienta con "record has no field" cuando ninguna rama matchea (mordio el 13-09).
  v_id bigint; v_ccod text; v_cdesc text; v_sec integer; v_via text; v_conf text;
  v_cand jsonb; v_sim numeric; v_sim2 numeric;
begin
  -- 1) quien es el proveedor: por nombre contra proveedor_insumo (el nombre de la factura
  --    nunca viene igual: "TALLERES GRAFICOS POL S.A." vs "Talleres Graficos Pol")
  if v_prov_txt is not null then
    select pi.id, pi.nombre, pi.cod_prov,
           round(public.similarity("GP2".texto_norm(pi.nombre), "GP2".texto_norm(v_prov_txt))::numeric, 2)
      into v_prov_id, v_prov_nom, v_prov_cod, v_prov_sim
      from proveedor_insumo pi
     where public.similarity("GP2".texto_norm(pi.nombre), "GP2".texto_norm(v_prov_txt)) > 0.25
     order by public.similarity("GP2".texto_norm(pi.nombre), "GP2".texto_norm(v_prov_txt)) desc
     limit 1;
  end if;

  for it in select * from jsonb_array_elements(coalesce(p->'items','[]'::jsonb)) loop
    v_cod := "GP2".cod_norm(it->>'codigo');
    v_desc := "GP2".texto_norm(it->>'descripcion');
    v_id := null; v_ccod := null; v_cdesc := null; v_sec := null;
    v_via := null; v_conf := null; v_cand := null; v_sim := null; v_sim2 := null;

    -- a) lo que ya se ato a mano para este proveedor: lo aprendido gana siempre
    if v_cod is not null and v_prov_txt is not null then
      select c.id, c.codigo, c.descripcion, c.sector_id, 'alias', 'alto'
        into v_id, v_ccod, v_cdesc, v_sec, v_via, v_conf
        from factura_alias fa join componente c on c.id = fa.componente_id
       where "GP2".cod_norm(fa.cod_prov) = v_cod
         and lower(fa.proveedor) in (lower(coalesce(v_prov_nom, v_prov_txt)), lower(v_prov_txt))
       limit 1;
    end if;

    -- b) codigo ISIS del fleje (el unico codigo de tercero que GP2 ya tiene cargado)
    if v_id is null and v_cod is not null then
      select c.id, c.codigo, c.descripcion, c.sector_id, 'cod_isis', 'alto'
        into v_id, v_ccod, v_cdesc, v_sec, v_via, v_conf
        from fleje_detalle fd join componente c on c.id = fd.componente_id
       where "GP2".cod_norm(fd.cod_isis) = v_cod
       limit 1;
    end if;

    -- c) el proveedor factura con NUESTRO codigo
    if v_id is null and v_cod is not null then
      select c.id, c.codigo, c.descripcion, c.sector_id, 'codigo_gp2', 'medio'
        into v_id, v_ccod, v_cdesc, v_sec, v_via, v_conf
        from componente c
       where "GP2".cod_norm(c.codigo) = v_cod
       limit 1;
    end if;

    -- d) por DESCRIPCION, SOLO dentro de la lista de productos de ese proveedor. Se
    --    auto-asigna unicamente si el parecido es fuerte Y el segundo quedo claramente
    --    atras; si no, vuelven los candidatos y decide la persona.
    if v_id is null and v_desc is not null and v_prov_cod is not null then
      with cand as (
        select distinct on (c.id)
               c.id, c.codigo, c.descripcion, c.sector_id, pp.producto,
               greatest(public.similarity("GP2".texto_norm(pp.producto), v_desc),
                        public.similarity(coalesce("GP2".texto_norm(c.descripcion),''), v_desc)) as sim
          from precio_proveedor pp join componente c on c.id = pp.componente_id
         where "GP2".cod_norm(pp.cod_prov) = "GP2".cod_norm(v_prov_cod)
         order by c.id, sim desc
      ), top as (
        select * from cand where sim > 0.18 order by sim desc limit 4
      )
      select (select round(max(sim)::numeric,2) from top),
             (select round(sim::numeric,2) from top order by sim desc offset 1 limit 1),
             (select jsonb_agg(jsonb_build_object('comp_id',id,'comp_cod',codigo,'comp_desc',descripcion,
                                                  'producto',producto,'sim',round(sim::numeric,2)) order by sim desc)
                from top)
        into v_sim, v_sim2, v_cand;

      if v_sim is not null and v_sim >= 0.55 and (v_sim2 is null or v_sim - v_sim2 >= 0.15) then
        select (x->>'comp_id')::bigint, x->>'comp_cod', x->>'comp_desc'
          into v_id, v_ccod, v_cdesc
          from jsonb_array_elements(v_cand) x limit 1;
        select sector_id into v_sec from componente where id = v_id;
        v_via := 'descripcion'; v_conf := 'medio'; v_cand := null;
      elsif v_cand is not null then
        v_via := 'sugerido'; v_conf := 'bajo';
      end if;
    end if;

    v_res := v_res || jsonb_build_object(
      'codigo',      it->>'codigo',
      'descripcion', it->>'descripcion',
      'cantidad',    nullif(it->>'cantidad','')::numeric,
      'unidad',      it->>'unidad',
      'precio_uni',  nullif(it->>'precio_unitario','')::numeric,
      'comp_id',     v_id,
      'comp_cod',    v_ccod,
      'comp_desc',   v_cdesc,
      'sector_id',   v_sec,
      'via',         coalesce(v_via, 'sin_match'),
      'confianza',   coalesce(v_conf, 'nulo'),
      'sim',         v_sim,
      'candidatos',  v_cand
    );
  end loop;

  return jsonb_build_object(
    'ok', true,
    'proveedor_texto', v_prov_txt,
    'proveedor', jsonb_build_object('id', v_prov_id, 'nombre', v_prov_nom, 'cod_prov', v_prov_cod, 'sim', v_prov_sim),
    'items', v_res,
    'resueltos', (select count(*) from jsonb_array_elements(v_res) x where x->>'comp_id' is not null),
    'sugeridos', (select count(*) from jsonb_array_elements(v_res) x where x->>'via' = 'sugerido'),
    'sin_match', (select count(*) from jsonb_array_elements(v_res) x where x->>'via' = 'sin_match'),
    'total', jsonb_array_length(v_res)
  );
end $function$
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
  -- MATERIALIZED a proposito: sin eso la CTE se inlinea y movimientos_bundle() corre 4 veces
  -- (una por cada uso de j). No sacar.
  with m as materialized (select "GP2".movimientos_bundle() j)
  select m.j
      || jsonb_build_object('art', (select coalesce(jsonb_agg(v order by (v->>'id')::bigint), '[]'::jsonb)
                                     from jsonb_each(m.j->'art') e(k, v)))
      || jsonb_build_object('mat', (select coalesce(jsonb_object_agg(k, v || jsonb_build_object('primera', coalesce((v->>'primera')::boolean, false))), '{}'::jsonb)
                                     from jsonb_each(m.j->'mat') e(k, v)))
      -- aporte['art:comp'] = unidades por mes que ESE articulo consume de ESE componente
      -- (v_consumo_demanda: receta + sub-BOM + los intermedios de la ruta, ya explotados)
      || jsonb_build_object('aporte', (select coalesce(jsonb_object_agg(d.articulo_id::text||':'||d.componente_id::text, d.uni_mes), '{}'::jsonb)
                                        from "GP2".v_consumo_demanda d))
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
  perform "GP2"._exigir_autorizado();  -- seguridad punto 1 fase B (2026-09-28)
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
  if NEW.uxb_obsoleto_v1629 is null and NEW.proy_cajas_mes is not null then
    select round(NEW.proy_cajas_mes * a.articulos_por_caja) into v_uni
    from "GP2".articulo a
    where regexp_replace(a.codigo, '^0+', '') = regexp_replace(NEW.cod, '^0+', '')
      and a.articulos_por_caja is not null
    limit 1;
    if v_uni is null then v_uni := NEW.proy_uni_mes; end if;
  end if;

  insert into "GP2".est_madre (cod, proy_cajas_mes, uxb, proy_uni_mes, actualizado)
  values (NEW.cod, NEW.proy_cajas_mes, NEW.uxb_obsoleto_v1629, v_uni, NEW.actualizado)
  on conflict (cod) do update
    set proy_cajas_mes = EXCLUDED.proy_cajas_mes,
        uxb            = EXCLUDED.uxb,
        proy_uni_mes   = EXCLUDED.proy_uni_mes,
        actualizado    = EXCLUDED.actualizado,
        copiado_en     = now();
  return NEW;
end $function$
;

-- ---------- fn_material_mejor_proveedor ----------
CREATE OR REPLACE FUNCTION "GP2".fn_material_mejor_proveedor()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
begin
  perform "GP2".recalcular_proveedor_material();
  return null;
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

-- ---------- fn_oc_virgilio_espejo ----------
CREATE OR REPLACE FUNCTION "GP2".fn_oc_virgilio_espejo()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
-- Espejo fila a fila de public."Ordenes_Compra" en GP2.oc_virgilio (patron de fn_est_madre_sync).
-- Un error aca NUNCA puede frenar a Gestion Virgilio: se avisa y la fila de public sigue.
begin
  begin
    if TG_OP = 'DELETE' then
      delete from "GP2".oc_virgilio where id = OLD.id;
      return OLD;
    end if;
    insert into "GP2".oc_virgilio (id, fecha, proveedor, codigo, cantidad, cantidad_recibida, unidad, estado, oc_uni_caja, notas, actualizado)
    values (NEW.id, NEW.fecha, NEW.proveedor, NEW.codigo, NEW.cantidad, NEW.cantidad_recibida, NEW.unidad, NEW.estado, NEW.oc_uni_caja, NEW.notas, now())
    on conflict (id) do update
      set fecha = excluded.fecha, proveedor = excluded.proveedor, codigo = excluded.codigo,
          cantidad = excluded.cantidad, cantidad_recibida = excluded.cantidad_recibida,
          unidad = excluded.unidad, estado = excluded.estado, oc_uni_caja = excluded.oc_uni_caja,
          notas = excluded.notas, actualizado = now(), copiado_en = now();
  exception when others then
    raise warning 'fn_oc_virgilio_espejo: % (OC id %)', sqlerrm, coalesce(NEW.id, OLD.id);
  end;
  return coalesce(NEW, OLD);
end $function$
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

-- ---------- fn_recalc_maximos_diferido ----------
CREATE OR REPLACE FUNCTION "GP2".fn_recalc_maximos_diferido()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
-- Recalcula los maximos UNA vez por transaccion, al COMMIT (constraint trigger DEFERRABLE INITIALLY
-- DEFERRED sobre est_madre / articulo_componente / ruta_paso / articulo_familia). El sync diario de LK
-- borra e inserta las ~330 filas de proyeccion_madre de a una, en UNA transaccion: con el trigger
-- statement-level anterior (fn_recalc_maximos_insumos) el recalculo corria ~658 veces por sync (~54 s,
-- el DELETE solo 21 s contra un statement_timeout de 120 s). Ahora corre una vez, contra la est_madre
-- final, y ademas refresca los maximos de TALLERISTA, que nadie recalculaba cuando cambiaba la Est
-- Madre (68 estaban viejos el 2026-09-26). Prov AT queda afuera a proposito: la Tablet le pone techo 0
-- (usuario 2026-09-24) y no tiene filas de inventario. D10, 2026-09-26.
-- 2026-09-28: + recalcular_maximo_mp_ps (ALAMBRE / FLEJE_DESCORAZONADOR), al final porque sale del maximo
-- de las piezas que acaban de recalcularse.
-- 2026-09-29: + recalcular_maximos_consumo_meses (filas con maximo_origen 'consumo_meses'), antes de
-- mp_ps porque este sale del maximo de las piezas.
declare v_tx text := txid_current()::text;
begin
  if current_setting('gp2.maximos_tx', true) = v_tx then return null; end if;
  perform set_config('gp2.maximos_tx', v_tx, true);   -- local a la transaccion: se borra sola al COMMIT
  begin
    perform "GP2".recalcular_maximos_insumos();
    perform "GP2".recalcular_maximos_talleristas();
    perform "GP2".recalcular_maximos_consumo_meses();
    perform "GP2".recalcular_maximo_mp_ps();
  exception when others then
    -- un error en el recalculo NO puede tumbar el sync de LK ni un guardado de receta: se avisa y sigue
    raise warning 'fn_recalc_maximos_diferido: % — los maximos quedan como estaban; correr recalcular_maximos_* a mano', sqlerrm;
  end;
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

-- ---------- fn_ubicacion_de_contraparte ----------
CREATE OR REPLACE FUNCTION "GP2".fn_ubicacion_de_contraparte()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
declare v_tipo text; v_nom text; v_stk numeric;
begin
  case tg_table_name
    when 'tallerista' then
      v_tipo := 'tallerista';  v_nom := 'Tallerista ' || new.nombre;             v_stk := 1;
    when 'proveedor_at' then
      v_tipo := 'proveedor_at'; v_nom := 'Prov. Art. Term. ' || new.nombre;      v_stk := null;
    when 'proveedor_servicio' then
      v_tipo := 'proveedor_servicio'; v_nom := 'Prov. Serv. ' || new.nombre;     v_stk := 0;
    when 'sector' then
      if not coalesce(new.es_insumo, false) then return new; end if;
      v_tipo := 'sector';      v_nom := new.nombre;                              v_stk := null;
    else
      return new;
  end case;

  -- ubic_de ya la resuelve (incluye el override de deposito compartido) -> no hay nada que crear
  if "GP2".ubic_de(v_tipo, new.id) is not null then return new; end if;

  insert into ubicacion (tipo, ref_id, nombre, meses_stock)
  values (v_tipo, new.id, v_nom, v_stk)
  on conflict do nothing;
  return new;
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
  perform "GP2"._exigir_autorizado();  -- seguridad punto 1 fase B (2026-09-28)
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
    SELECT c.carton_formato, nullif(c.entrega_uni_x,0), c.es_pliego
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
    'recepcion_de_mas', (select count(*) from "GP2".alerta_recepcion where estado = 'abierta'),
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
                            where c.sector_id=sec_sel.sid and btrim(coalesce(c.proveedor,''))=pi.nombre),
                     'es_inyector', ("GP2".ubic_de('inyector', pi.id) is not null)
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
                'material_id', c.material_id,
                'material', (select m.codigo from componente m where m.id=c.material_id),
                'lo_produce', (select t.nombre from ruta_paso rp
                                join tallerista t on t.id=rp.tallerista_id
                               where rp.comp_salida_id=c.id limit 1),
                'stock', coalesce((select sum(i.cantidad) from inventario i where i.componente_id=c.id),0),
                'en_recetas', (select count(*) from articulo_componente ac where ac.componente_id=c.id)
              ) order by c.codigo), '[]'::jsonb)
             from componente c, sec_sel where c.sector_id=sec_sel.sid),
  -- materia prima plastica por inyector (2026-09-10): lo que necesita para sus OC abiertas vs lo que tiene
  'material', (select coalesce(jsonb_agg(to_jsonb(v) order by v.proveedor, v.material_codigo), '[]'::jsonb)
               from v_material_inyector v),
  'materiales', (select coalesce(jsonb_agg(jsonb_build_object(
                    'comp_id', m.id, 'codigo', m.codigo, 'descripcion', m.descripcion,
                    'kg_virgilio', coalesce((select i.cantidad from inventario i
                                              where i.componente_id=m.id and i.ubicacion_id="GP2".ubic_de('sector',14)),0)
                  ) order by m.codigo), '[]'::jsonb)
                 from componente m where m.sector_id=14 and m.estado_compra is null),
  'desperdicio_pct', (select valor from parametro where clave='inyeccion_desperdicio_pct'),
  'kg_x_bolsa', (select valor from parametro where clave='material_plastico_kg_x_bolsa')
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
  perform "GP2"._exigir_autorizado();  -- seguridad punto 1 fase B (2026-09-28)
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
  perform "GP2"._exigir_autorizado();  -- seguridad punto 1 fase B (2026-09-28)
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
  perform "GP2"._exigir_autorizado();  -- seguridad punto 1 fase B (2026-09-28)
  update produccion set revisado = true where id = row_id;
  if not found then
    raise exception 'Registro id=% no encontrado', row_id;
  end if;
end;
$function$
;

-- ---------- material_virgilio_bundle ----------
CREATE OR REPLACE FUNCTION "GP2".material_virgilio_bundle()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
select jsonb_build_object(
  'kg_x_bolsa', coalesce((select valor from parametro where clave='material_plastico_kg_x_bolsa'), 25),
  'materiales', coalesce((select jsonb_agg(jsonb_build_object(
      'comp_id', c.id, 'codigo', c.codigo, 'codigo_virgilio', c.codigo_virgilio, 'descripcion', c.descripcion,
      'kg_en_virgilio', coalesce(i.cantidad, 0),
      'bolsas_en_virgilio', round(coalesce(i.cantidad, 0) / coalesce((select valor from parametro where clave='material_plastico_kg_x_bolsa'), 25), 1),
      'inyectores', coalesce((select jsonb_agg(jsonb_build_object(
          'proveedor', v.proveedor, 'kg_en_inyector', v.kg_en_inyector, 'kg_requerido_oc', v.kg_requerido_oc,
          'kg_a_enviar', v.kg_a_enviar, 'bolsas_a_enviar', v.bolsas_a_enviar) order by v.bolsas_a_enviar desc, v.proveedor)
        from v_material_inyector v where v.material_id = c.id), '[]'::jsonb)
    ) order by c.codigo)
    from componente c
    left join inventario i on i.componente_id = c.id and i.ubicacion_id = ubic_de('sector', 14)
    where c.sector_id = 14 and c.estado_compra is null), '[]'::jsonb),
  'inyectores', coalesce((select jsonb_agg(pi.nombre order by pi.nombre)
    from proveedor_insumo pi join ubicacion u on u.tipo='inyector' and u.ref_id = pi.id where pi.activo), '[]'::jsonb),
  'generado_en', now());
$function$
;

-- ---------- matriz_racha_bundle ----------
CREATE OR REPLACE FUNCTION "GP2".matriz_racha_bundle(p_solo_con_produccion boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
  select jsonb_build_object(
    'matrices', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'matriz', r.matriz,
        'descripcion', r.descripcion,
        'unidades', r.unidades,
        'golpes', r.golpes,
        'uni_x_golpe', r.uni_x_golpe,
        'accidentes', r.accidentes,
        'record', r.record,
        'es_record', r.es_record,
        'ultimo_accidente', r.ultimo_accidente,
        'ultimo_tipo', r.ultimo_tipo,
        'ultimo_detalle', r.ultimo_detalle,
        'ultima_produccion', r.ultima_produccion,
        'dias_sin_accidente', case when r.ultimo_accidente is not null
          then ((now() at time zone 'America/Argentina/Buenos_Aires')::date
                - (r.ultimo_accidente at time zone 'America/Argentina/Buenos_Aires')::date) end
      ) order by r.unidades desc, r.matriz), '[]'::jsonb)
      from matriz_racha r
      where not p_solo_con_produccion or r.unidades > 0 or r.accidentes > 0
    ),
    'totales', (
      select jsonb_build_object(
        'matrices', count(*),
        'unidades', coalesce(sum(unidades),0),
        'accidentes', coalesce(sum(accidentes),0),
        'en_record', count(*) filter (where es_record))
      from matriz_racha
    ),
    'actualizado_en', (select max(actualizado_en) from matriz_racha)
  );
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
    'ubic', (select coalesce(jsonb_object_agg(id::text, jsonb_build_object('tipo',tipo,'ref',ref_id,'nom',nombre,'meses',meses_stock)),'{}'::jsonb) from ubicacion),
    'art', (select coalesce(jsonb_object_agg(a.id::text, jsonb_build_object('id',a.id,'cod',a.codigo,'fam',a.familia,'cja',a.componente_caja_id,'por',a.articulos_por_caja,
            'desc',a.descripcion,'disc',a.discontinuado,
            'est',(select em.proy_uni_mes from est_madre em where regexp_replace(em.cod,'^0+','') = regexp_replace(a.codigo,'^0+','') limit 1))),'{}'::jsonb) from articulo a),
    'comp', (select coalesce(jsonb_object_agg(id::text, jsonb_build_object('cod',codigo,'d',descripcion,'s',sector_id,'um',unidad_medida,'kg_x_uni',kg_x_uni,'uxc',uni_x_cajon)),'{}'::jsonb) from componente),
    'prov_serv', (select coalesce(jsonb_object_agg(id::text, jsonb_build_object('nom',nombre,'proceso',proceso)),'{}'::jsonb) from proveedor_servicio),
    -- prov_at (2026-09-12): lo necesita Recepcion Virgilio, que recibe terminados tanto de
    -- talleristas como de proveedores de articulo terminado. Antes el paso proveedor_at de
    -- ruta_paso no llegaba al bundle y la pantalla vieja lo sacaba de public.
    'prov_at', (select coalesce(jsonb_object_agg(id::text, jsonb_build_object('nom',nombre,'cod',cod_prov,'act',activo)),'{}'::jsonb) from proveedor_at),
    'tall', (select coalesce(jsonb_object_agg(id::text, jsonb_build_object('nom',nombre,'ubi_stock',ubicacion_stock_id,'act',activo)),'{}'::jsonb) from tallerista),
    'mat', (select coalesce(jsonb_object_agg(id::text, jsonb_build_object('n',n_matriz,'d',descripcion,'tipo',tipo,'ppk',partes_por_kilo_de_fleje,'primera',(case when partes_por_kilo_de_fleje is not null then true end),'uxg',uni_x_golpe,'maq',maquina,'act',activa)),'{}'::jsonb) from matriz),
    -- vocabulario de movimiento (2026-09-11): unica fuente de los mapas TIPOS del JS
    'tipos_mov', (select coalesce(jsonb_object_agg(clave, jsonb_build_object('lbl',label,'lado',lado,'cls',clase,'ord',orden)),'{}'::jsonb) from tipo_movimiento),
    'bom_art', (select coalesce(jsonb_object_agg(articulo_id::text, arr),'{}'::jsonb) from (
        select articulo_id, jsonb_agg(jsonb_build_object('c',componente_id,'q',cantidad)) arr
        from articulo_componente group by articulo_id) x),
    'bom_comp', (select coalesce(jsonb_object_agg(componente_padre_id::text, arr),'{}'::jsonb) from (
        select componente_padre_id, jsonb_agg(jsonb_build_object('c',componente_hijo_id,'q',cantidad)) arr
        from componente_bom group by componente_padre_id) x),
    'rp', (select coalesce(jsonb_object_agg(ruta_id::text, arr),'{}'::jsonb) from (
        select rp.ruta_id, jsonb_agg(jsonb_build_object('o',rp.orden,'tipo',rp.tipo_paso,
            'flje', case when rp.tipo_paso = 'ingreso' and rp.orden = 1 and ce.sector_id = 5 then rp.comp_entrada_id end,
            'mat',rp.matriz_id,'prov',rp.proveedor_id,'tall',rp.tallerista_id,'pat',rp.proveedor_at_id,
            'ce',rp.comp_entrada_id,'cs',rp.comp_salida_id,
            'art', case when rp.tipo_paso = 'virgilio' then r.articulo_id end) order by rp.orden) arr
        from ruta_paso rp
        left join componente ce on ce.id = rp.comp_entrada_id
        left join ruta r on r.id = rp.ruta_id
        group by rp.ruta_id) x),
    'inv', (select coalesce(jsonb_object_agg(componente_id::text||':'||ubicacion_id::text, jsonb_build_object('cant',cantidad,'max',maximo)),'{}'::jsonb) from inventario),
    -- componente terminado -> articulo, por la unica puerta (comp_terminado_de). Antes esto
    -- salia del paso virgilio y recepcion_virgilio buscaba por codigo: dos criterios. Idea 7322.
    'c2a', (select coalesce(jsonb_object_agg(comp_id::text, articulo_id),'{}'::jsonb) from (
        select distinct on (comp_id) comp_id, articulo_id from (
          select "GP2".comp_terminado_de(a.id) comp_id, a.id articulo_id from articulo a) y
         where comp_id is not null order by comp_id, articulo_id) x)
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
  -- precio del proveedor ASIGNADO al componente (cod_prov de proveedor_insumo = cod_prov del precio);
  -- si no hay uno suyo, el mas nuevo. Un material con varios proveedores cotiza al elegido (2026-09-10).
  select distinct on (pp.componente_id) pp.componente_id,
         case when pp.precio_por_kg then pp.precio * cc.kg_x_uni else pp.precio end precio,
         case when upper(coalesce(pp.moneda,'USD')) like '%US%' then 'USD' else 'ARS' end moneda
  from precio_proveedor pp
  join componente cc on cc.id = pp.componente_id
  left join proveedor_insumo pi on pi.nombre = cc.proveedor
  where pp.componente_id is not null and pp.precio is not null
  order by pp.componente_id,
           (pi.cod_prov is not null and pp.cod_prov = pi.cod_prov) desc,
           pp.fecha_lista desc nulls last, pp.id desc
), pvx as (
  -- precio de CADA proveedor que cotiza el componente (cod_prov -> proveedor_insumo), el mas
  -- nuevo de cada uno. Hace falta desde que un componente puede comprarse a mas de un proveedor
  -- (componente_proveedor_alt, 2026-09-17): la OC a Recicor tiene que salir con el precio de
  -- Recicor y no con el de Corrugadora. NO cambia el precio vigente: ese sigue siendo pv.
  select distinct on (pp.componente_id, pi2.nombre) pp.componente_id, pi2.nombre proveedor,
         case when pp.precio_por_kg then pp.precio * cc.kg_x_uni else pp.precio end precio,
         case when upper(coalesce(pp.moneda,'USD')) like '%US%' then 'USD' else 'ARS' end moneda
  from precio_proveedor pp
  join componente cc on cc.id = pp.componente_id
  join proveedor_insumo pi2 on pi2.cod_prov = pp.cod_prov
  where pp.componente_id is not null and pp.precio is not null
  order by pp.componente_id, pi2.nombre, pp.fecha_lista desc nulls last, pp.id desc
), fas as (
  -- PIEZAS DE FASONERO (proveedor_servicio.pedido_por_oc): el PS nos entrega la pieza poniendo
  -- material propio y nos la cobra, asi que SE LE EMITE O.C. aunque la pieza siga marcada
  -- estado_compra='fabricacion'. El estado_compra NO se toca a proposito: ponerlo en null la
  -- convierte en insumo comprado y le vuela el costo de ruta (medido 2026-09-18: los 5 articulos
  -- de Maspoli perdian $710,89 cada uno). Hoy: Maspoli SRL -> PC12 / PEP7 / PEP8.
  select distinct rp.comp_salida_id comp_id
  from ruta_paso rp
  join proveedor_servicio ps on ps.id = rp.proveedor_id
  where rp.tipo_paso = 'proveedor_servicio' and ps.pedido_por_oc and rp.comp_salida_id is not null
), ins as (
  select c.id comp_id, c.codigo, c.descripcion, c.sector_id, s.nombre sector,
         c.unidad_medida um, c.kg_x_uni, c.uni_x_cajon,
         nullif(trim(c.proveedor),'') proveedor,
         coalesce(u.meses_stock, inv.meses_stock) meses_stock,
         case when c.sector_id = 5 then fk.consumo_kg_mes else cp.consumo_uni_mes end consumo,
         case when c.sector_id = 5 or lower(coalesce(c.unidad_medida,'')) = 'kg'
              then 'kg' else 'uni' end unidad,
         inv.cantidad online,
         inv.maximo maximo_inv,
         inv.maximo_origen maximo_origen_inv,
         inv.ubicacion_id, inv.ubic_nombre,
         coalesce(pd.pendiente, 0) pendiente_oc,
         c.carton_formato, c.carton_categoria, c.marca,
         coalesce(c.es_pliego, false) es_pliego,
         coalesce(cc2.mezcla_libre, false) mezcla_libre,
         cf.pliegos_multiplo, cf.codigo_multiplo, cf.min_codigo_x_multiplo, cf.pedido_minimo,
         c.pedido_minimo_uni,
         -- FAMILIA DE PEDIDO del plastico (2026-09-29): las piezas de la misma matriz del inyector;
         -- el minimo del proveedor es de la FAMILIA [Thomas: "entre todos los pirolos tengo que
         -- llegar a 36000"]. La OC agrupa por familia y muestra el minimo con el total pedido.
         c.familia_pedido, fp.pedido_minimo_uni familia_minimo,
         -- LA UNIDAD DEL REMITO (2026-09-28): la O.C. se pide en la misma unidad en que se recibe
         -- [Thomas: "usa las mismas unidades de medida para las ordenes de compra"]. Mismos datos
         -- que usa Recepcion de Insumos para decidir la unidad.
         c.remito_unidad, coalesce(c.recibe_en_cajas, false) recibe_en_cajas,
         c.entrega_unidad, c.entrega_uni_x,
         pv.precio, pv.moneda
  from componente c
  join sector s on s.id = c.sector_id
  left join ubicacion u on u.id = "GP2".ubic_de('sector', c.sector_id)
  -- una sola definicion de "donde se repone este componente" (v_reposicion, 2026-09-11)
  left join "GP2".v_reposicion inv on inv.componente_id = c.id
  left join v_consumo_componente cp on cp.componente_id = c.id and c.sector_id <> 5
  left join v_consumo_fleje_kg fk on fk.componente_id = c.id and c.sector_id = 5
  left join pend pd on pd.componente_id = c.id
  left join carton_formato cf on cf.nombre = c.carton_formato
  left join carton_categoria cc2 on cc2.nombre = c.carton_categoria and cc2.formato = c.carton_formato
  left join familia_pedido fp on fp.nombre = c.familia_pedido
  left join pv on pv.componente_id = c.id
  left join fas on fas.comp_id = c.id
  where (
          "GP2"._es_sector_insumo(c.sector_id)
          or trim(coalesce(c.proveedor,'')) in ('Resortes Charcas','Eclipse')
          or (c.proveedor is not null
              and exists (select 1 from proveedor_insumo pi where pi.nombre = c.proveedor))
        )
    -- lo que la pieza de un fasonero (fas) SI se compra, con su estado_compra intacto
    and (c.estado_compra is null or fas.comp_id is not null)
    and c.id not in (select comp_id from "GP2".v_componente_muerto)
    -- LO QUE PRODUCE UN PS NO SE COMPRA (usuario 2026-09-08: "esas dos partes de charcas se
    -- tratan como proveedor de servicio"). Si el proveedor que figura en el componente es el
    -- MISMO PS que lo produce en una ruta (ruta_paso tipo proveedor_servicio, comp_salida = el
    -- componente), no hay OC: se le manda la materia prima y se recibe por Entrega PS. Hoy son
    -- IC3 e IC3V (Charcas corta el ALAMBRE de Altrak, que SI se compra, en su rubro
    -- Alambre). Se mira el proveedor DEL COMPONENTE, no el paso suelto: un insumo que compramos
    -- y mandamos a pintar (paso PS con entrada=salida) sigue en la OC, y las bombillas que
    -- Charcas nos VENDE (BOM10/EP10/LLF8) tambien.
    -- El match va por NOMBRE o por COD_PROV: "Maspoli SRL" (proveedor_servicio) y "Maspoli SRL"
    -- con tilde (proveedor_insumo) son el mismo proveedor escrito distinto, y no puede ser una
    -- tilde la que decida si una pieza entra en la O.C. El fasonero (pedido_por_oc) queda AFUERA
    -- de esta exclusion: a el si se le compra lo que produce.
    and not exists (
      select 1 from ruta_paso rp
      join proveedor_servicio ps2 on ps2.id = rp.proveedor_id
      where rp.tipo_paso = 'proveedor_servicio'
        and rp.comp_salida_id = c.id
        and not ps2.pedido_por_oc
        and ( ps2.nombre = c.proveedor
           or ps2.cod_prov = (select pi3.cod_prov from proveedor_insumo pi3
                               where pi3.nombre = c.proveedor) )
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
      'proveedor',proveedor,
      -- proveedores ALTERNATIVOS que entregan la misma pieza (componente_proveedor_alt): la OC
      -- se le puede emitir a cualquiera de ellos, sin duplicar el componente.
      'proveedores_alt',(select coalesce(jsonb_agg(a.proveedor order by a.proveedor),'[]'::jsonb)
                           from componente_proveedor_alt a
                           join proveedor_insumo pa on pa.nombre = a.proveedor and pa.activo
                          where a.componente_id = calc.comp_id),
      -- precio POR proveedor, para que la hoja que se le manda a cada uno salga con SU lista.
      'precios_prov',(select coalesce(jsonb_object_agg(x.proveedor,
                         jsonb_build_object('precio',x.precio,'moneda',x.moneda)),'{}'::jsonb)
                        from pvx x where x.componente_id = calc.comp_id),
      'um',um,'unidad',unidad,'kg_x_uni',kg_x_uni,'uni_x_cajon',uni_x_cajon,
      'consumo',consumo,'consumo_uni_mes',consumo,'meses',meses_stock,
      'online',coalesce(online,0),'stock',coalesce(online,0),
      'maximo',maximo_ef,'maximo_origen',maximo_origen_ef,'maximo_inventario',maximo_inv,
      'ubicacion_id',ubicacion_id,'ubicacion',ubic_nombre,
      'pendiente_oc',pendiente_oc,
      'sugerido', greatest(0, round(coalesce(maximo_ef,0) - coalesce(online,0))),
      'sugerido_consumo', greatest(0, round(coalesce(consumo,0)*coalesce(meses_stock,0) - coalesce(online,0))),
      'precio',precio,'moneda',moneda,
      'carton_formato',carton_formato,'carton_categoria',carton_categoria,
      'marca',marca,'mezcla_libre',mezcla_libre,'es_pliego',es_pliego,
      'pliegos_multiplo',pliegos_multiplo,'pedido_minimo',pedido_minimo,
      'codigo_multiplo',codigo_multiplo,'min_codigo_x_multiplo',min_codigo_x_multiplo,
      'pedido_minimo_uni',pedido_minimo_uni,
      'familia_pedido',familia_pedido,'familia_minimo',familia_minimo,
      'remito_unidad',remito_unidad,'recibe_en_cajas',recibe_en_cajas,
      'entrega_unidad',entrega_unidad,'entrega_uni_x',entrega_uni_x
    ) order by sector_id, codigo),'[]'::jsonb) from calc),
  'pliego_uni_x_paquete', (select valor from parametro where clave='pliego_uni_x_paquete'),
  'paq', (select valor from parametro where clave='carton_uni_x_paquete'),
  'charcas_kg_x_paquete', (select valor from parametro where clave='charcas_kg_x_paquete'),
  -- kg por BOLSA del remache: el proveedor lo entrega en bolsas de 25 kg y la O.C. va en
  -- multiplos de esa bolsa [usuario 2026-09-18]. Null = la pantalla usa su default (25).
  'remache_kg_x_bolsa', (select valor from parametro where clave='remache_kg_x_bolsa'),
  'facturar_pct_loeke', (select valor from parametro where clave='oc_facturar_pct_loeke'),
  'proveedores', (select coalesce(jsonb_agg(jsonb_build_object(
      'nombre',pi.nombre,'rubro',pi.rubro,'modo_control',pi.modo_control,
      'cod_prov',pi.cod_prov,'activo',pi.activo,'dias_entrega',pi.dias_entrega,'entrega_en',pi.entrega_en,'pedido_minimo_kg',pi.pedido_minimo_kg,
      'insumos',(select count(*) from componente c3
                  where (c3.estado_compra is null
                         or exists (select 1 from fas f3 where f3.comp_id = c3.id))
                    and (c3.proveedor = pi.nombre
                         or exists (select 1 from componente_proveedor_alt a3
                                     where a3.componente_id = c3.id and a3.proveedor = pi.nombre)))
    ) order by pi.nombre),'[]'::jsonb) from proveedor_insumo pi),
  'ocs', (select coalesce(jsonb_agg(jsonb_build_object(
      'id',o.id,'numero',o.numero,'proveedor',o.proveedor,'rubro',o.rubro,'estado',o.estado,
      'nota',o.nota,'creado_en',o.creado_en,
      'fecha_entrega_estimada',o.fecha_entrega_estimada,
      'cod_prov',(select pi2.cod_prov from proveedor_insumo pi2 where pi2.nombre = o.proveedor),
      'entrega_en',(select pi2.entrega_en from proveedor_insumo pi2 where pi2.nombre = o.proveedor),
      'total_usd',(select coalesce(sum(oi.cantidad*oi.precio_uni),0) from orden_compra_item oi
                   where oi.oc_id=o.id and oi.moneda='USD'),
      'total_ars',(select coalesce(sum(oi.cantidad*oi.precio_uni),0) from orden_compra_item oi
                   where oi.oc_id=o.id and oi.moneda='ARS'),
      'items',(select coalesce(jsonb_agg(jsonb_build_object(
                 'codigo',c2.codigo,'descripcion',c2.descripcion,'cantidad',oi.cantidad,
                 'unidad',oi.unidad,'recibido',oi.recibido,
                 'precio_uni',oi.precio_uni,'moneda',oi.moneda,
                 'sector_id',c2.sector_id,'codigo_isis_ch',c2.codigo_isis_ch,
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
  perform "GP2"._exigir_autorizado();  -- seguridad punto 1 fase B (2026-09-28)
  if p_estado not in ('borrador','enviada','recibida','anulada') then
    raise exception 'Estado invalido: %', p_estado;
  end if;
  update orden_compra set estado = p_estado where id = p_oc_id;
  if not found then raise exception 'OC % no existe', p_oc_id; end if;
  return jsonb_build_object('ok', true);
end $function$
;

-- ---------- oc_maximo_desglose ----------
CREATE OR REPLACE FUNCTION "GP2".oc_maximo_desglose(p_componente_id bigint)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
with c as (
  select comp.id, comp.codigo, comp.descripcion, comp.sector_id, comp.unidad_medida, comp.kg_x_uni,
         (comp.sector_id = 14) es_resina,
         (comp.sector_id = 5)  es_fleje,
         "GP2".ubic_de('sector', comp.sector_id) ubic
  from componente comp where comp.id = p_componente_id
), cab as (
  select c.*,
         (select meses_stock from ubicacion where id = c.ubic) meses,
         (select i.maximo from inventario i where i.componente_id = c.id and i.ubicacion_id = c.ubic) maximo,
         (select i.maximo_origen from inventario i where i.componente_id = c.id and i.ubicacion_id = c.ubic) maximo_origen,
         (select round(consumo_kg_mes,2) from v_consumo_fleje_kg f where f.componente_id = c.id) consumo_kg_fleje,
         (select round(consumo_uni_mes) from v_consumo_componente v where v.componente_id = c.id) consumo_uni,
         (select coalesce(valor,4) from parametro where clave='inyeccion_desperdicio_pct') desp_pct
  from c
), filas_art as (
  select a.codigo cod, a.descripcion desc_,
         (select em.proy_uni_mes from est_madre em
           where regexp_replace(regexp_replace(em.cod,'L$',''),'^0+','') = regexp_replace(a.codigo,'^0+','') limit 1) venta_uni_mes,
         d.uni_mes aporte_uni_mes
  from v_consumo_demanda d
  join cab on cab.id = d.componente_id and not cab.es_resina
  join articulo a on a.id = d.articulo_id
), filas_pieza as (
  select p.codigo cod, p.descripcion desc_,
         coalesce(v.consumo_uni_mes,0) aporte_uni_mes,
         p.kg_x_uni pieza_kg,
         coalesce(v.consumo_uni_mes,0) * coalesce(p.kg_x_uni,0) * (1 + (select desp_pct from cab)/100.0) aporte_kg
  from componente p
  join cab on cab.es_resina and p.material_id = cab.id
  left join v_consumo_componente v on v.componente_id = p.id
), resina_tot as (
  select round(sum(aporte_kg),2) kg_mes from filas_pieza
)
select jsonb_build_object(
  'comp', (select jsonb_build_object('id',id,'codigo',codigo,'descripcion',descripcion,
              'sector_id',sector_id,'unidad',unidad_medida,'kg_x_uni',kg_x_uni,
              'es_resina',es_resina,'es_fleje',es_fleje) from cab),
  'meses', (select meses from cab),
  'maximo', (select maximo from cab),
  'maximo_origen', (select maximo_origen from cab),
  'consumo_uni_mes', (select case when es_resina then null else consumo_uni end from cab),
  'consumo_kg_mes',  (select case when es_fleje then consumo_kg_fleje
                                  when es_resina then (select kg_mes from resina_tot) end from cab),
  'desperdicio_pct', (select case when es_resina then desp_pct end from cab),
  'consumo_x_meses', (select round(
       coalesce(case when es_fleje then consumo_kg_fleje
                     when es_resina then (select kg_mes from resina_tot)
                     else consumo_uni end, 0) * coalesce(meses,0)) from cab),
  'base', (select case when es_resina then 'piezas' else 'articulos' end from cab),
  'filas', case when (select es_resina from cab) then
      coalesce((select jsonb_agg(jsonb_build_object(
        'cod',cod,'desc',desc_,'aporte_uni_mes',round(aporte_uni_mes),
        'aporte_kg', round(aporte_kg,2)) order by aporte_kg desc) from filas_pieza), '[]'::jsonb)
    else
      coalesce((select jsonb_agg(jsonb_build_object(
        'cod',cod,'desc',desc_,'venta_uni_mes',round(venta_uni_mes),
        'aporte_uni_mes',round(aporte_uni_mes,2),
        'aporte_kg', case when (select kg_x_uni from cab) is not null
                          then round(aporte_uni_mes * (select kg_x_uni from cab), 2) end)
        order by aporte_uni_mes desc) from filas_art), '[]'::jsonb)
    end,
  'generado_en', now());
$function$
;

-- ---------- oc_pendientes_virgilio ----------
CREATE OR REPLACE FUNCTION "GP2".oc_pendientes_virgilio()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
select coalesce((select jsonb_agg(jsonb_build_object(
  'oc_id', o.id, 'numero', o.numero, 'proveedor', o.proveedor,
  'cod_prov', pi.cod_prov, 'estado', o.estado, 'creado_en', o.creado_en,
  'fecha_entrega_estimada', o.fecha_entrega_estimada, 'nota', o.nota,
  'items', (select jsonb_agg(jsonb_build_object(
              'item_id', oi.id, 'comp_id', c.id, 'codigo', c.codigo, 'codigo_isis_ch', c.codigo_isis_ch,
              'cod_virgilio', c.codigo_virgilio,
              'descripcion', c.descripcion, 'unidad', oi.unidad,
              'cantidad', oi.cantidad, 'recibido', oi.recibido,
              'pendiente', greatest(oi.cantidad - oi.recibido, 0),
              'pendiente_bolsas', round(greatest(oi.cantidad - oi.recibido, 0) / coalesce((select valor from parametro where clave='material_plastico_kg_x_bolsa'), 25), 1)
            ) order by c.codigo)
            from orden_compra_item oi join componente c on c.id = oi.componente_id where oi.oc_id = o.id)
) order by o.numero)
from orden_compra o
left join proveedor_insumo pi on pi.nombre = o.proveedor
where o.estado in ('borrador','enviada')
  and pi.entrega_en is null
  and exists (select 1 from orden_compra_item oi where oi.oc_id = o.id)
  and not exists (select 1 from orden_compra_item oi join componente c on c.id = oi.componente_id
                   where oi.oc_id = o.id and c.sector_id <> 14)), '[]'::jsonb);
$function$
;

-- ---------- operario_por_legajo ----------
CREATE OR REPLACE FUNCTION "GP2".operario_por_legajo(p_legajo text)
 RETURNS TABLE(employee_id bigint, legajo text, nombre text, hora_entrada time without time zone, hora_salida time without time zone, permisos jsonb)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  -- Operario = activo en Planify + ficha de liquidación activa tipo 'planta' (RRHH), salvo que el
  -- admin GP2 lo haya marcado "no registra producción" en GP2.operario (sin fila = habilitado).
  -- Lee SOLO legajo, nombre, activo, tipo_empleado y horario_laboral ("08:30 a 17:30"): nada de
  -- sueldos, CBU, CUIL ni fechas. El horario se usa para la llegada tarde y el cajón que sigue.
  -- La letra es parte del legajo (c = CHEF SRL); se devuelve en minúscula (así va en la sesión).
  -- permisos = los flags de rol de GP2.operario (sin fila = operario de balancín, todo en false).
  select e.id::bigint, lower(e.legajo::text), e.nombre::text,
         nullif(substring(l.horario_laboral::text from '^\s*(\d{1,2}:\d{2})'), '')::time,
         nullif(substring(l.horario_laboral::text from '(\d{1,2}:\d{2})\s*$'), '')::time,
         jsonb_build_object(
           'es_matriceria', coalesce(o.es_matriceria, false), 'es_piedra', coalesce(o.es_piedra, false),
           'es_alimentador', coalesce(o.es_alimentador, false), 've_cm', coalesce(o.ve_cm, false),
           've_trm', coalesce(o.ve_trm, false), 've_tl', coalesce(o.ve_tl, false),
           've_rem', coalesce(o.ve_rem, false), 've_mm', coalesce(o.ve_mm, false))
    from planify.employees e
    join planify.empleados_liquidacion l
      on l.employee_id = e.id and l.activo and l.tipo_empleado = 'planta'
    left join "GP2".operario o on o.employee_id = e.id
   where e.activo
     and lower(e.legajo::text) = lower(trim(p_legajo))
     and coalesce(o.registra_produccion, true)
   order by l.id
   limit 1;
$function$
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
  perform "GP2"._exigir_autorizado();  -- seguridad punto 1 fase B (2026-09-28)
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
    from proveedor_servicio ps where lower(btrim(ps.proceso)) = 'pintado';

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
    join proveedor_servicio p2 on p2.id = rp.proveedor_id and lower(btrim(p2.proceso)) = 'pintado'
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

-- ---------- planilla_cargar ----------
CREATE OR REPLACE FUNCTION "GP2".planilla_cargar(p_snapshot_id integer, p_filas jsonb)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
declare n int;
begin
  if not exists (select 1 from "GP2".planilla_snapshot where id = p_snapshot_id) then
    raise exception 'snapshot % inexistente', p_snapshot_id;
  end if;
  insert into "GP2".planilla_fila (snapshot_id, hoja, fila, bloque, datos, formulas)
  select p_snapshot_id, h.key, (e->>0)::int, e->>2, e->1, e->3
    from jsonb_each(p_filas) h,
         jsonb_array_elements(h.value) e
  on conflict on constraint planilla_fila_uk
    do update set datos    = excluded.datos,
                  bloque   = excluded.bloque,
                  formulas = excluded.formulas;
  get diagnostics n = row_count;
  return n;
end $function$
;

-- ---------- planilla_fecha ----------
CREATE OR REPLACE FUNCTION "GP2".planilla_fecha(p text)
 RETURNS date
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'GP2'
AS $function$
  select case when p ~ '^\d{4}-\d{2}-\d{2}' then left(p,10)::date end;
$function$
;

-- ---------- planilla_num ----------
CREATE OR REPLACE FUNCTION "GP2".planilla_num(p text)
 RETURNS numeric
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'GP2'
AS $function$
  select case when p ~ '^-?[0-9]+(\.[0-9]+)?$' then p::numeric end;
$function$
;

-- ---------- planilla_snapshot_nuevo ----------
CREATE OR REPLACE FUNCTION "GP2".planilla_snapshot_nuevo(p_archivo text, p_nota text DEFAULT NULL::text, p_subido_por text DEFAULT NULL::text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
declare v_id int;
begin
  update "GP2".planilla_snapshot set vigente = false where vigente;
  insert into "GP2".planilla_snapshot (archivo, nota, subido_por)
       values (p_archivo, p_nota, p_subido_por) returning id into v_id;
  return v_id;
end $function$
;

-- ---------- preaviso_marcar ----------
CREATE OR REPLACE FUNCTION "GP2".preaviso_marcar(p_id bigint, p_estado text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
begin
  perform "GP2"._exigir_autorizado();  -- seguridad punto 1 fase B (2026-09-28)
  if p_estado not in ('cumplido','anulado','pendiente') then
    raise exception 'estado invalido: %', p_estado;
  end if;
  update preaviso
     set estado = p_estado,
         cerrado_en = case when p_estado = 'pendiente' then null else now() end
   where id = p_id;
  if not found then raise exception 'No existe el preaviso %', p_id; end if;
  return jsonb_build_object('ok', true, 'id', p_id, 'estado', p_estado);
end $function$
;

-- ---------- preavisos_bundle ----------
CREATE OR REPLACE FUNCTION "GP2".preavisos_bundle()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
  select jsonb_build_object(
    -- quien entrega: el que aparece como contraparte en algun paso de ruta
    'contrapartes', (
      select coalesce(jsonb_agg(x order by x->>'nombre'), '[]'::jsonb) from (
        select distinct jsonb_build_object('tipo','tallerista','id',t.id,'nombre',t.nombre) x
          from ruta_paso rp join tallerista t on t.id = rp.tallerista_id
         where rp.tipo_paso = 'tallerista' and t.activo
        union
        select distinct jsonb_build_object('tipo','proveedor_servicio','id',ps.id,'nombre',ps.nombre)
          from ruta_paso rp join proveedor_servicio ps on ps.id = rp.proveedor_id
         where rp.tipo_paso = 'proveedor_servicio'
        union
        select distinct jsonb_build_object('tipo','proveedor_at','id',pa.id,'nombre',pa.nombre)
          from ruta_paso rp join proveedor_at pa on pa.id = rp.proveedor_at_id
         where rp.tipo_paso = 'proveedor_at' and pa.activo
      ) y),
    -- que devuelve cada una: la salida de sus pasos (o la entrada del paso virgilio que le sigue)
    'entrega', (
      select coalesce(jsonb_agg(jsonb_build_object('tipo',tipo,'ref',ref,'comp_id',comp_id,
                                                   'cod',cod,'desc',descr) order by tipo, ref, cod), '[]'::jsonb)
        from (
          select distinct on (tipo, ref, c.id) tipo, ref, c.id comp_id, c.codigo cod, c.descripcion descr
            from (
              select 'tallerista'::text tipo, rp.tallerista_id ref, rp.comp_salida_id comp
                from ruta_paso rp where rp.tipo_paso='tallerista' and rp.comp_salida_id is not null
                 and not exists (select 1 from ruta r_ join articulo a_ on a_.id=r_.articulo_id
                                  where r_.id=rp.ruta_id and coalesce(a_.discontinuado,false))
              union all
              select 'proveedor_servicio', rp.proveedor_id, rp.comp_salida_id
                from ruta_paso rp where rp.tipo_paso='proveedor_servicio' and rp.comp_salida_id is not null
                 and not exists (select 1 from ruta r_ join articulo a_ on a_.id=r_.articulo_id
                                  where r_.id=rp.ruta_id and coalesce(a_.discontinuado,false))
              union all
              -- el prov AT entrega el terminado: es la entrada del paso virgilio de esa ruta
              select 'proveedor_at', rp.proveedor_at_id,
                     (select v.comp_entrada_id from ruta_paso v
                       where v.ruta_id = rp.ruta_id and v.tipo_paso='virgilio' and v.orden > rp.orden
                       order by v.orden limit 1)
                from ruta_paso rp where rp.tipo_paso='proveedor_at'
                 and not exists (select 1 from ruta r_ join articulo a_ on a_.id=r_.articulo_id
                                  where r_.id=rp.ruta_id and coalesce(a_.discontinuado,false))
            ) z join componente c on c.id = z.comp
           where ref is not null
        ) w),
    'abiertos', (
      select coalesce(jsonb_agg(to_jsonb(v) order by v.fecha_promesa), '[]'::jsonb)
        from v_preaviso_estado v where v.estado = 'pendiente')
  );
$function$
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
  select distinct on (rp.ruta_id) rp.ruta_id, rp.comp_entrada_id fl
  from "GP2".ruta_paso rp
  join "GP2".componente c on c.id = rp.comp_entrada_id and c.sector_id in (5, 13)
  where rp.tipo_paso = 'ingreso' and rp.orden = 1
  order by rp.ruta_id, rp.orden
),
rutas_full as (
  select r.id, r.nombre nom, rf.fl f, r.articulo_id a
  from "GP2".ruta r left join ruta_fleje rf on rf.ruta_id = r.id
)
select jsonb_build_object(
  'art', (select jsonb_agg(jsonb_build_object('id',id,'cod',codigo,'fam',familia,'d',descripcion,'mk',marca,'disc',discontinuado) order by id) from "GP2".articulo),
  'comp', (select jsonb_object_agg(id::text, jsonb_build_object('cod',codigo,'d',descripcion,'s',sector_id)) from "GP2".componente),
  'fl', '{}'::jsonb,
  'mat', (select jsonb_object_agg(id::text, jsonb_build_object('n',n_matriz,'d',descripcion,'t',tipo,'r',partes_por_kilo_de_fleje,'p',(partes_por_kilo_de_fleje is not null))) from "GP2".matriz),
  'prov', (select jsonb_object_agg(id::text, jsonb_build_object('n',nombre,'p',proceso)) from "GP2".proveedor_servicio),
  'provat', (select jsonb_object_agg(id::text, nombre) from "GP2".proveedor_at),
  'tall', (select jsonb_object_agg(id::text, nombre) from "GP2".tallerista),
  'bom', (select jsonb_agg(jsonb_build_object('a',articulo_id,'c',componente_id,'q',cantidad)) from "GP2".articulo_componente),
  'children', (select jsonb_object_agg(componente_padre_id::text, arr) from (
       select componente_padre_id, jsonb_agg(jsonb_build_object('c',componente_hijo_id,'q',cantidad)) arr
       from "GP2".componente_bom where componente_padre_id is not null group by componente_padre_id) x),
  'rutas', (select jsonb_agg(jsonb_build_object('id',id,'nom',nom,'f',f,'a',a) order by id) from rutas_full),
  'rp', (select jsonb_object_agg(ruta_id::text, arr) from (
       select rp.ruta_id, jsonb_agg(jsonb_build_object('o',rp.orden,'tp',rp.tipo_paso,'m',rp.matriz_id,'pr',rp.proveedor_id,'ta',rp.tallerista_id,'pat',rp.proveedor_at_id,'ce',rp.comp_entrada_id,'cs',rp.comp_salida_id,
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
with pasos as (
  select distinct r.articulo_id, a.codigo art_codigo, a.familia,
         rp.comp_salida_id, cs.codigo paso_cod, cs.descripcion paso_desc,
         rp.tallerista_id, t.nombre tallerista
    from ruta_paso rp
    join ruta r        on r.id = rp.ruta_id
    join articulo a    on a.id = r.articulo_id
    join componente cs on cs.id = rp.comp_salida_id
    join tallerista t  on t.id = rp.tallerista_id
   where rp.tallerista_id is not null
), compartidos as (
  select articulo_id, comp_salida_id
    from pasos group by 1, 2 having count(distinct tallerista_id) >= 2
), filas as (
  select p.*, re.pct, re.es_supuesto
    from pasos p
    join compartidos c on c.articulo_id = p.articulo_id and c.comp_salida_id = p.comp_salida_id
    left join v_reparto_efectivo re on re.articulo_id = p.articulo_id
     and re.comp_salida_id = p.comp_salida_id and re.tallerista_id = p.tallerista_id
), entradas as (
  -- que parte recibe cada tallerista para ese articulo, y cuanto puede tener en su casa
  select distinct r.articulo_id, rp.tallerista_id, rp.comp_entrada_id,
         ce.codigo parte_cod, ce.descripcion parte_desc,
         i.maximo, i.cantidad, i.maximo_origen
    from ruta_paso rp
    join ruta r        on r.id = rp.ruta_id
    join componente ce on ce.id = rp.comp_entrada_id
    left join ubicacion u on u.tipo = 'tallerista' and u.ref_id = rp.tallerista_id
    left join inventario i on i.componente_id = rp.comp_entrada_id and i.ubicacion_id = u.id
   where rp.tallerista_id is not null and rp.comp_entrada_id is not null and r.articulo_id is not null
), partes_por_paso as (
  select f.articulo_id, f.comp_salida_id, e.comp_entrada_id, e.parte_cod, e.parte_desc,
         jsonb_agg(jsonb_build_object('tall_id', e.tallerista_id, 'maximo', e.maximo,
                                      'stock', e.cantidad, 'origen', e.maximo_origen)
                   order by e.tallerista_id) por_tall
    from (select distinct articulo_id, comp_salida_id from filas) f
    join entradas e on e.articulo_id = f.articulo_id
    join filas ff on ff.articulo_id = f.articulo_id and ff.comp_salida_id = f.comp_salida_id
                 and ff.tallerista_id = e.tallerista_id
   group by f.articulo_id, f.comp_salida_id, e.comp_entrada_id, e.parte_cod, e.parte_desc
)
select jsonb_build_object(
  'generado_en', now(),
  'pasos', coalesce((
     select jsonb_agg(x order by x->>'art_codigo', x->>'paso_cod') from (
       select jsonb_build_object(
         'articulo_id', f.articulo_id, 'art_codigo', f.art_codigo, 'familia', f.familia,
         'comp_salida_id', f.comp_salida_id, 'paso_cod', f.paso_cod, 'paso_desc', f.paso_desc,
         'n_talleristas', count(*),
         'suma_pct', round(sum(f.pct), 2),
         'talleristas', jsonb_agg(jsonb_build_object(
            'tall_id', f.tallerista_id, 'tallerista', f.tallerista,
            'pct', f.pct, 'es_supuesto', coalesce(f.es_supuesto, false)) order by f.tallerista),
         'partes', coalesce((
            select jsonb_agg(jsonb_build_object('cod', pp.parte_cod, 'desc', pp.parte_desc,
                                                'por_tall', pp.por_tall) order by pp.parte_cod)
              from partes_por_paso pp
             where pp.articulo_id = f.articulo_id and pp.comp_salida_id = f.comp_salida_id), '[]'::jsonb)
       ) x
       from filas f
       group by f.articulo_id, f.art_codigo, f.familia, f.comp_salida_id, f.paso_cod, f.paso_desc
     ) s), '[]'::jsonb)
);
$function$
;

-- ---------- recalcular_maximo_material ----------
CREATE OR REPLACE FUNCTION "GP2".recalcular_maximo_material()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
declare v_kg_bolsa numeric; v_meses numeric; v_pct numeric; v_ubic bigint; v_cambios jsonb; v_tot numeric;
        v_plastico numeric; v_mb_total numeric; v_prop numeric; v_cambios_mb jsonb;
        v_mb_pct numeric; v_kg_con_color numeric; v_kg_sin_color numeric;
begin
  v_kg_bolsa := coalesce((select valor from parametro where clave='material_plastico_kg_x_bolsa'), 25);
  v_pct := coalesce((select valor from parametro where clave='inyeccion_desperdicio_pct'), 0);
  -- Cuanto master lleva la pieza sobre sus kg de resina, APARTE (usuario 2026-09-12: 4 %).
  v_mb_pct := coalesce((select valor from parametro where clave='master_bach_pct'), 4);
  v_ubic := ubic_de('sector', 14);
  v_meses := coalesce((select meses_stock from ubicacion where id = v_ubic), 2.5);

  with cons as (
    select c.material_id, sum(v.consumo_uni_mes * coalesce(c.kg_x_uni,0)) * (1 + v_pct/100) kg_mes
      from v_consumo_componente v join componente c on c.id = v.componente_id
     where c.material_id is not null group by 1
  ), nuevo as (
    select m.id comp_id, m.codigo, cons.kg_mes,
           ceil(cons.kg_mes * v_meses / v_kg_bolsa) * v_kg_bolsa maximo
      from componente m join cons on cons.material_id = m.id
     where m.sector_id = 14 and cons.kg_mes > 0
  ), upd as (
    update inventario i set maximo = n.maximo, maximo_origen = 'fisico'
      from nuevo n
     where i.componente_id = n.comp_id and i.ubicacion_id = v_ubic and i.maximo is distinct from n.maximo
    returning n.codigo, i.maximo, n.kg_mes
  )
  select coalesce(jsonb_agg(jsonb_build_object('codigo', codigo, 'maximo_kg', maximo, 'bolsas', maximo / v_kg_bolsa, 'consumo_kg_mes', round(kg_mes))), '[]'::jsonb)
    into v_cambios from upd;

  -- ===== MASTER BACH =====
  -- La regla del usuario: cada parte plastica inyectada tiene SU color, y el master es el 4 % de
  -- los kg de resina de esa parte, APARTE de los kg de resina. Asi que el camino bueno es sumar
  -- por color, no repartir un total.
  --
  -- Mientras componente.mb_color este sin cargar (necesita la columna MB del Excel de plasticos),
  -- esas piezas caen a un pozo "sin color" que se reparte con la proporcion que ya tenian los
  -- cuatro master. Es un maximo: errar para arriba es lo correcto. A medida que se carguen los
  -- colores, la parte prorrateada se encoge sola y la cuenta se vuelve exacta sin tocar nada.
  select coalesce(sum(i.maximo), 0) into v_plastico
    from inventario i join componente m on m.id = i.componente_id
   where m.sector_id = 14 and i.ubicacion_id = v_ubic and m.codigo_virgilio is not null;
  v_mb_total := v_plastico * v_mb_pct / 100;

  -- kg de resina de las piezas QUE YA declaran color, y de las que no
  with cons as (
    select c.mb_color, sum(v.consumo_uni_mes * coalesce(c.kg_x_uni,0)) * (1 + v_pct/100) * v_meses kg
      from v_consumo_componente v join componente c on c.id = v.componente_id
     where c.material_id is not null group by 1
  )
  select coalesce(sum(kg) filter (where mb_color is not null), 0),
         coalesce(sum(kg) filter (where mb_color is null), 0)
    into v_kg_con_color, v_kg_sin_color from cons;

  select coalesce(sum(i.maximo), 0) into v_prop
    from inventario i join componente m on m.id = i.componente_id
   where m.sector_id = 14 and i.ubicacion_id = v_ubic and m.codigo_virgilio is null;

  with color_de as (   -- que letra le toca a cada componente de master, por su descripcion
    select m.id, i.maximo prop,
           case when m.descripcion ilike '%rojo%'   then 'R'
                when m.descripcion ilike '%blanco%' then 'B'
                when m.descripcion ilike '%azul%'   then 'A'
                when m.descripcion ilike '%negro%'  then 'N' end letra
      from componente m join inventario i on i.componente_id = m.id and i.ubicacion_id = v_ubic
     where m.sector_id = 14 and m.codigo_virgilio is null
  ), por_color as (    -- kg de master que pide cada color POR SUS PIEZAS
    select c.mb_color letra,
           sum(v.consumo_uni_mes * coalesce(c.kg_x_uni,0)) * (1 + v_pct/100) * v_meses * v_mb_pct / 100 kg
      from v_consumo_componente v join componente c on c.id = v.componente_id
     where c.material_id is not null and c.mb_color is not null group by 1
  ), mb as (
    select cd.id componente_id, m.codigo,
           greatest(v_kg_bolsa,
             ceil( ( coalesce(pc.kg, 0)                                    -- lo suyo, por color
                     + (v_mb_total * case when v_plastico > 0 then v_kg_sin_color / nullif(v_kg_con_color + v_kg_sin_color, 0) else 1 end)
                       * (case when v_prop > 0 then cd.prop / v_prop
                               else 1.0 / nullif((select count(*) from color_de), 0) end)   -- el pozo sin color
                   ) / v_kg_bolsa ) * v_kg_bolsa) nuevo
      from color_de cd join componente m on m.id = cd.id
      left join por_color pc on pc.letra = cd.letra
  ), updmb as (
    update inventario i set maximo = mb.nuevo, maximo_origen = 'mb_' || v_mb_pct::int::text || 'pct_por_color'
      from mb where i.componente_id = mb.componente_id and i.ubicacion_id = v_ubic
        and (i.maximo is distinct from mb.nuevo or i.maximo_origen is distinct from 'mb_' || v_mb_pct::int::text || 'pct_por_color')
    returning mb.codigo, i.maximo
  )
  select coalesce(jsonb_agg(jsonb_build_object('codigo', codigo, 'maximo_kg', maximo, 'bolsas', maximo / v_kg_bolsa)), '[]'::jsonb)
    into v_cambios_mb from updmb;

  select coalesce(sum(i.maximo), 0) / v_kg_bolsa into v_tot
    from inventario i join componente m on m.id = i.componente_id where m.sector_id = 14 and i.ubicacion_id = v_ubic;
  return jsonb_build_object('ok', true, 'meses', v_meses, 'kg_x_bolsa', v_kg_bolsa, 'cambios', v_cambios,
                            'plastico_kg', v_plastico, 'mb_pct', v_mb_pct, 'mb_kg', round(v_mb_total,1),
                            'mb_kg_con_color', round(v_kg_con_color,1), 'mb_kg_sin_color', round(v_kg_sin_color,1),
                            'cambios_mb', v_cambios_mb,
                            'total_bolsas', v_tot, 'pallets', ceil(v_tot / 15), 'capacidad_bolsas', 300);
end $function$
;

-- ---------- recalcular_maximo_mp_ps ----------
CREATE OR REPLACE FUNCTION "GP2".recalcular_maximo_mp_ps()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
-- [usuario 2026-09-28: "si tengo que tener 10 alambres y eso equivale a 0.1 de fleje hay que mandarle
-- eso" + "calcula el maximo segun los meses del sector x consumo de articulo"]. La materia prima que
-- se compra en kg y la entrega el proveedor a un PS que la corta en piezas (ALAMBRE -> Charcas
-- -> IC3/IC3V; FLEJE_DESCORAZONADOR -> Eclipse -> Z31) NO tiene consumo propio: su maximo es el de las piezas.
--   maximo_mp (kg, en la ubicacion del PS) = sum por pieza de
--     maximo_pieza x kg_x_uni_pieza / (1 - desperdicio_pct del PS / 100)
--   maximo_pieza = inventario.maximo de la pieza en su sector; si esta vacio,
--                  consumo (v_consumo_componente) x meses_stock del sector.
-- Pasos que entran: tipo proveedor_servicio, entrada en kg, salida contada (no kg) y distinta.
declare v_set int := 0; v_ins int := 0; v_clr int := 0; v_det jsonb;
begin
  create temp table _mp_obj on commit drop as
  with paso as (
    select distinct rp.proveedor_id, rp.comp_entrada_id ent, rp.comp_salida_id sal
      from ruta_paso rp
      join ruta r on r.id = rp.ruta_id and r.articulo_id is not null
      join componente ce on ce.id = rp.comp_entrada_id and ce.unidad_medida = 'kg'
      join componente cs on cs.id = rp.comp_salida_id and coalesce(cs.unidad_medida,'') <> 'kg'
     where rp.tipo_paso = 'proveedor_servicio' and rp.proveedor_id is not null
       and rp.comp_entrada_id <> rp.comp_salida_id
       and rp.comp_entrada_id not in (select comp_id from v_componente_muerto)
       and rp.comp_salida_id  not in (select comp_id from v_componente_muerto)
  ), pieza as (
    select p.proveedor_id, p.ent, p.sal, cs.codigo, cs.kg_x_uni,
           coalesce(ps.desperdicio_pct, 0) desp,
           coalesce(isec.maximo, round(coalesce(vc.consumo_uni_mes, 0) * coalesce(u.meses_stock, 1))) max_pieza,
           case when isec.maximo is not null then 'maximo' else 'consumo_x_meses' end fuente
      from paso p
      join componente cs on cs.id = p.sal
      join proveedor_servicio ps on ps.id = p.proveedor_id
      left join ubicacion u on u.id = ubic_de('sector', cs.sector_id)
      left join inventario isec on isec.componente_id = p.sal and isec.ubicacion_id = u.id
      left join v_consumo_componente vc on vc.componente_id = p.sal
     where coalesce(cs.kg_x_uni, 0) > 0 and coalesce(ps.desperdicio_pct, 0) < 100
  )
  select proveedor_id, ent, ubic_de('proveedor_servicio', proveedor_id) ubic_id,
         round(sum(max_pieza * kg_x_uni / (1 - desp / 100)), 2) max_kg,
         jsonb_agg(jsonb_build_object('pieza', codigo, 'maximo_pieza', max_pieza, 'fuente', fuente,
                                      'kg_x_uni', kg_x_uni, 'desperdicio_pct', desp) order by codigo) piezas
    from pieza group by proveedor_id, ent;

  with upd as (
    update inventario i set maximo = o.max_kg, maximo_origen = 'derivado_pieza'
      from _mp_obj o
     where i.componente_id = o.ent and i.ubicacion_id = o.ubic_id and o.max_kg > 0
       and coalesce(i.maximo_origen, '') <> 'fisico'
       and (i.maximo is distinct from o.max_kg or i.maximo_origen is distinct from 'derivado_pieza')
    returning 1)
  select count(*) into v_set from upd;

  with ins as (
    insert into inventario (componente_id, ubicacion_id, cantidad, maximo, maximo_origen, actualizado_en)
    select o.ent, o.ubic_id, 0, o.max_kg, 'derivado_pieza', now()
      from _mp_obj o
     where o.ubic_id is not null and o.max_kg > 0
       and not exists (select 1 from inventario i where i.componente_id = o.ent and i.ubicacion_id = o.ubic_id)
    returning 1)
  select count(*) into v_ins from ins;

  -- el que dejo de tener pieza (se cambio la ruta) no se queda con un maximo viejo
  with clr as (
    update inventario i set maximo = null, maximo_origen = null
     where i.maximo_origen = 'derivado_pieza'
       and not exists (select 1 from _mp_obj o where o.ent = i.componente_id and o.ubic_id = i.ubicacion_id and o.max_kg > 0)
    returning 1)
  select count(*) into v_clr from clr;

  select coalesce(jsonb_agg(jsonb_build_object('mp', c.codigo, 'maximo_kg', o.max_kg, 'piezas', o.piezas)), '[]'::jsonb)
    into v_det from _mp_obj o join componente c on c.id = o.ent;
  drop table _mp_obj;
  return jsonb_build_object('ok', true, 'actualizados', v_set, 'creados', v_ins, 'limpiados', v_clr, 'detalle', v_det);
end $function$
;

-- ---------- recalcular_maximos_cajones ----------
CREATE OR REPLACE FUNCTION "GP2".recalcular_maximos_cajones()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
-- 2026-09-29: la regla de 5 cajones (2026-08-30) se retiro. Crudo/Procesado = consumo x meses_stock.
begin
  return "GP2".recalcular_maximos_consumo_meses();
end $function$
;

-- ---------- recalcular_maximos_consumo_meses ----------
CREATE OR REPLACE FUNCTION "GP2".recalcular_maximos_consumo_meses()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
-- maximo_origen 'consumo_meses' = consumo mensual (Est Madre explotada) x meses_stock de la ubicacion.
-- 2026-09-29 (G5-G8): opt-in por fila. 2026-09-29 (mas tarde): TODO Sector Crudo y Sector Procesado entra
-- solo, salvo 'fisico' / 'faat_reserva_lote' (usuario: "usa la regla de consumo, no de 5 cajones").
-- 2026-09-29: en Crudo/Procesado el maximo NO puede exceder max_cajones_x_ubicacion (5) x uni_x_cajon
-- (usuario: "el maximo de sector crudo y sector procesado no puede exceder los 5 cajones").
-- Sin consumo -> maximo NULL (no 0): el componente no se repone.
declare v_set int := 0; v_adop int := 0; v_caj numeric;
begin
  select valor into v_caj from parametro where clave = 'max_cajones_x_ubicacion';
  if v_caj is null or v_caj <= 0 then v_caj := 5; end if;

  with adop as (
    update inventario i set maximo_origen = 'consumo_meses'
      from ubicacion u, componente c
     where u.id = i.ubicacion_id and u.tipo = 'sector' and c.id = i.componente_id
       and c.sector_id = u.ref_id and c.sector_id in (1, 2)
       and coalesce(i.maximo_origen, '') not in ('fisico', 'faat_reserva_lote', 'consumo_meses')
    returning 1)
  select count(*) into v_adop from adop;

  with obj as (
    select v.inv_id,
           nullif(case when v.sector_id in (1, 2) and c.uni_x_cajon > 0
                       then least(greatest(coalesce(v.max_calc,0),0), round(v_caj * c.uni_x_cajon))
                       else greatest(coalesce(v.max_calc,0),0) end, 0) as max_nuevo
      from v_nivel_stock v join componente c on c.id = v.componente_id
  ), upd as (
    update inventario i set maximo = o.max_nuevo
    from obj o
    where o.inv_id = i.id and i.maximo_origen = 'consumo_meses'
      and i.maximo is distinct from o.max_nuevo
    returning 1)
  select count(*) into v_set from upd;
  return jsonb_build_object('ok', true, 'adoptados', v_adop, 'actualizados', v_set, 'tope_cajones', v_caj);
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

-- ---------- recalcular_maximos_prov_at ----------
CREATE OR REPLACE FUNCTION "GP2".recalcular_maximos_prov_at(p_crear_faltantes boolean DEFAULT false, p_componentes bigint[] DEFAULT NULL::bigint[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
declare
  v_set int := 0; v_creados int := 0; v_cambios jsonb; v_faltan jsonb; v_sin_consumo jsonb;
begin
  with objetivo as (
    select v.inv_id, v.componente_id, v.proveedor_at_id, v.max_calc, v.maximo as maximo_viejo
      from v_nivel_stock_prov_at v
     where coalesce(v.maximo_origen, '') <> 'fisico'
       and v.max_calc > 0
       and (p_componentes is null or v.componente_id = any (p_componentes))
  ), upd as (
    update inventario i
       set maximo = o.max_calc, maximo_origen = 'est_madre_x_reparto'
      from objetivo o
     where i.id = o.inv_id
       and (i.maximo is distinct from o.max_calc or i.maximo_origen is distinct from 'est_madre_x_reparto')
    returning o.proveedor_at_id, o.componente_id, o.maximo_viejo, o.max_calc
  )
  select count(*), coalesce(jsonb_agg(jsonb_build_object(
           'prov_at', (select nombre from proveedor_at p where p.id = u.proveedor_at_id),
           'componente', (select codigo from componente c where c.id = u.componente_id),
           'antes', u.maximo_viejo, 'ahora', u.max_calc) order by u.proveedor_at_id), '[]'::jsonb)
    into v_set, v_cambios from upd u;

  -- (prov AT, pieza) con consumo pero SIN fila de inventario en su ubicacion. Al 2026-09-23 son
  -- TODAS: las 12 ubicaciones de prov AT tienen 0 filas de inventario, asi que sin este paso no
  -- hay donde escribir un maximo. Se informan siempre; se crean solo si lo piden.
  select coalesce(jsonb_agg(jsonb_build_object(
           'prov_at', (select nombre from proveedor_at p where p.id = f.proveedor_at_id),
           'componente', (select codigo from componente c where c.id = f.componente_id),
           'maximo', f.max_calc) order by f.proveedor_at_id), '[]'::jsonb)
    into v_faltan
    from (select cp.proveedor_at_id, cp.componente_id, u.id as ubic_id,
                 round(cp.uni_mes * coalesce(u.meses_stock, 1)) as max_calc
            from v_consumo_prov_at cp
            join ubicacion u on u.tipo = 'proveedor_at' and u.ref_id = cp.proveedor_at_id
           where cp.uni_mes > 0
             and (p_componentes is null or cp.componente_id = any (p_componentes))
             and not exists (select 1 from inventario i
                              where i.componente_id = cp.componente_id and i.ubicacion_id = u.id)) f;

  if p_crear_faltantes then
    with falta as (
      select cp.proveedor_at_id, cp.componente_id, u.id as ubic_id,
             round(cp.uni_mes * coalesce(u.meses_stock, 1)) as max_calc
        from v_consumo_prov_at cp
        join ubicacion u on u.tipo = 'proveedor_at' and u.ref_id = cp.proveedor_at_id
       where cp.uni_mes > 0
         and (p_componentes is null or cp.componente_id = any (p_componentes))
         and not exists (select 1 from inventario i
                          where i.componente_id = cp.componente_id and i.ubicacion_id = u.id)
    ), ins as (
      insert into inventario (componente_id, ubicacion_id, cantidad, maximo, maximo_origen, actualizado_en)
      select f.componente_id, f.ubic_id, 0, f.max_calc, 'est_madre_x_reparto', now()
        from falta f
      returning 1
    )
    select count(*) into v_creados from ins;
  end if;

  -- filas con maximo cargado que hoy no tienen consumo: se informan, no se limpian
  select coalesce(jsonb_agg(jsonb_build_object(
           'prov_at', (select nombre from proveedor_at p where p.id = v.proveedor_at_id),
           'componente', (select codigo from componente c where c.id = v.componente_id),
           'maximo', v.maximo) order by v.proveedor_at_id), '[]'::jsonb)
    into v_sin_consumo
    from v_nivel_stock_prov_at v
   where v.max_calc = 0 and v.maximo is not null and coalesce(v.maximo_origen, '') <> 'fisico';

  return jsonb_build_object('ok', true, 'actualizados', v_set, 'creados', v_creados,
    'faltan_fila_inventario', v_faltan, 'sin_consumo', v_sin_consumo, 'cambios', v_cambios);
end $function$
;

-- ---------- recalcular_maximos_talleristas ----------
CREATE OR REPLACE FUNCTION "GP2".recalcular_maximos_talleristas(p_solo_repartidos boolean DEFAULT false, p_componentes bigint[] DEFAULT NULL::bigint[], p_limpiar_sin_ruta boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
declare v_set int := 0; v_cambios jsonb; v_limpiados int := 0; v_con_ruta jsonb;
begin
  with repartidos as (
    select distinct rp.tallerista_id, rp.comp_entrada_id
      from ruta_paso rp
      join ruta r on r.id = rp.ruta_id
      join reparto_tallerista rt
        on rt.articulo_id = r.articulo_id and rt.comp_salida_id = rp.comp_salida_id
       and rt.tallerista_id = rp.tallerista_id
     where rp.comp_entrada_id is not null
  ), objetivo as (
    select v.inv_id, v.componente_id, v.tallerista_id, v.max_calc, v.maximo maximo_viejo
      from v_nivel_stock_tallerista v
     where coalesce(v.maximo_origen, '') <> 'fisico'
       and v.max_calc > 0
       and (not p_solo_repartidos
            or exists (select 1 from repartidos x
                        where x.tallerista_id = v.tallerista_id and x.comp_entrada_id = v.componente_id))
       and (p_componentes is null or v.componente_id = any (p_componentes))
  ), upd as (
    update inventario i
       set maximo = o.max_calc, maximo_origen = 'est_madre_x_reparto'
      from objetivo o
     where i.id = o.inv_id
       and (i.maximo is distinct from o.max_calc or i.maximo_origen is distinct from 'est_madre_x_reparto')
    returning o.tallerista_id, o.componente_id, o.maximo_viejo, o.max_calc
  )
  select count(*), coalesce(jsonb_agg(jsonb_build_object(
           'tallerista', (select nombre from tallerista t where t.id = u.tallerista_id),
           'componente', (select codigo from componente c where c.id = u.componente_id),
           'antes', u.maximo_viejo, 'ahora', u.max_calc) order by u.tallerista_id), '[]'::jsonb)
    into v_set, v_cambios from upd u;

  if p_limpiar_sin_ruta then
    with sin_ruta as (
      select v.inv_id from v_nivel_stock_tallerista v
       where v.max_calc = 0 and v.maximo is not null and coalesce(v.maximo_origen, '') <> 'fisico'
         and not exists (select 1 from ruta_paso rp
                          where rp.tallerista_id = v.tallerista_id and rp.comp_entrada_id = v.componente_id)
    ), lim as (
      update inventario i set maximo = null, maximo_origen = null
        from sin_ruta s where i.id = s.inv_id returning 1
    )
    select count(*) into v_limpiados from lim;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'tallerista', (select nombre from tallerista t where t.id = v.tallerista_id),
           'componente', (select codigo from componente c where c.id = v.componente_id),
           'maximo', v.maximo) order by v.tallerista_id), '[]'::jsonb)
    into v_con_ruta
    from v_nivel_stock_tallerista v
   where v.max_calc = 0 and v.maximo is not null and coalesce(v.maximo_origen, '') <> 'fisico'
     and exists (select 1 from ruta_paso rp
                  where rp.tallerista_id = v.tallerista_id and rp.comp_entrada_id = v.componente_id);

  return jsonb_build_object('ok', true, 'actualizados', v_set, 'limpiados', v_limpiados,
    'sin_consumo_con_ruta', v_con_ruta, 'cambios', v_cambios);
end $function$
;

-- ---------- recalcular_proveedor_material ----------
CREATE OR REPLACE FUNCTION "GP2".recalcular_proveedor_material()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
declare v_cambios jsonb;
begin
  with mejor as (
    select componente_id, proveedor, precio_ars_kg
      from v_material_precio_proveedor where orden = 1
  ), upd as (
    update componente c
       set proveedor = m.proveedor
      from mejor m
     where c.id = m.componente_id and c.sector_id = 14
       and c.proveedor is distinct from m.proveedor
    returning c.codigo, c.proveedor nuevo, m.precio_ars_kg
  )
  select coalesce(jsonb_agg(jsonb_build_object('codigo', codigo, 'proveedor', nuevo, 'precio_ars_kg', precio_ars_kg)), '[]'::jsonb)
    into v_cambios from upd;
  return jsonb_build_object('ok', true, 'cambios', v_cambios);
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
        -- en que unidad viene el REMITO de esta pieza ('kg' | 'uni' | null = la canonica).
        -- Misma columna que usa la Tablet: la plancha de niquel de CC Galvanoquimica viene
        -- pesada aunque el resto del Sector Plastico se cuente [usuario 2026-09-23].
        'remito_unidad',c.remito_unidad,
        -- remito_unidad='envase': el remito viene contado en el envase de la pieza
        -- (entrega_unidad x entrega_uni_x). Caso C13 Corta Queso Bastidor: cajas de 144
        -- [usuario 2026-09-25]. La pantalla lo pasa a unidades al guardar.
        'entrega_unidad',c.entrega_unidad,'entrega_uni_x',c.entrega_uni_x,
        'proveedor',nullif(trim(c.proveedor),''),
        -- proveedores ALTERNATIVOS que entregan la misma pieza (componente_proveedor_alt).
        -- El principal sigue siendo c.proveedor: esto no cambia OC ni costo, solo hace que
        -- la pieza aparezca tambien bajo el otro proveedor en Recepcion de Insumos.
        'proveedores_alt', coalesce((select jsonb_agg(a.proveedor order by a.proveedor)
             from "GP2".componente_proveedor_alt a
             join "GP2".proveedor_insumo pa on pa.nombre = a.proveedor and pa.activo
            where a.componente_id = c.id), '[]'::jsonb),
        'estado_compra',c.estado_compra,
        'marca',c.marca, 'carton_formato',c.carton_formato, 'es_pliego',c.es_pliego,
        'paq_x_bolsa',cf.paq_x_bolsa, 'uni_x_bolsa_cat',c.entrega_uni_x, 'kg_x_uni',c.kg_x_uni,'recibe_en_cajas',coalesce(c.recibe_en_cajas,false),
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
      -- una sola regla de "que se compra" (_es_comprable): sector de insumo, pieza importada
      -- o pieza que entrega un PS hibrido. Antes era sector + los dos hibridos hardcodeados.
      where "GP2"._es_comprable(c.id) and coalesce(c.estado_compra,'') <> 'discontinuo'
        and c.id not in (select comp_id from "GP2".v_componente_muerto)),
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
           where clave like 'tara_pallet%' or clave in ('tol_ctrl_pct','carton_uni_x_paquete'))
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
  -- CARTON SUSTITUTO (2026-09-21): cuando al tercero se le mando el carton de otro articulo (sin
  -- stock del suyo, con la etiqueta pegada encima), lo que se consume al recibir el terminado
  -- tiene que ser ESE y no el de la receta, que en su poder no esta. El reparto lo hace
  -- repartir_sustituto y vale para las dos ramas: la linea PRINCIPAL (en 51 de 193 articulos el
  -- principal ES el carton o la caja) y las demas lineas de la receta.
  v_ucons bigint; v_usado jsonb := '{}'::jsonb; v_rep jsonb; t jsonb; v_i int;
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
    v_compfin := "GP2".comp_terminado_de(v_art.id);
    if v_compfin is null then raise exception 'El articulo % no tiene componente terminado', v_art.codigo; end if;
    select ac.componente_id, ac.cantidad, c.sector_id into v_prin
      from articulo_componente ac join componente c on c.id=ac.componente_id
     where ac.articulo_id=v_art.id
     order by (c.sector_id=2) desc, ac.cantidad desc, ac.componente_id limit 1;
    if v_prin.componente_id is null then raise exception 'El articulo % no tiene receta', v_art.codigo; end if;

    -- ---- las lineas que NO son la principal: consumo puro ----
    for r in select ac.componente_id, ac.cantidad, c.sector_id
               from articulo_componente ac join componente c on c.id=ac.componente_id
              where ac.articulo_id=v_art.id and ac.componente_id<>v_prin.componente_id loop
      v_ucons := case when v_tipo='interno' then "GP2".ubic_de('sector', r.sector_id) else v_uorig end;
      v_rep := "GP2".repartir_sustituto(
                 case when r.sector_id in (10,11) and v_tipo <> 'interno' then v_ucons end,
                 r.componente_id, v_qty * r.cantidad, v_usado);
      v_usado := v_rep->'usado';
      for t in select value from jsonb_array_elements(v_rep->'tramos') loop
        v_movs := v_movs || jsonb_build_object(
          'tipo_mov','consumo_virgilio','comp_id',(t->>'comp_id')::bigint,
          'ubic_origen_id', v_ucons, 'ubic_destino_id', null,
          'cantidad', (t->>'cantidad')::numeric,
          'sustituye_comp_id', t->>'sustituye_comp_id');
      end loop;
    end loop;

    -- ---- la linea PRINCIPAL: es la que trae el terminado a Virgilio ----
    -- El movimiento de recepcion es UNO SOLO por articulo (si no, el terminado entraria dos veces):
    -- el primer tramo se lo lleva, y si el saldo del sustituto no alcanza, el resto sale como
    -- consumo aparte del carton oficial.
    v_ucons := case when v_tipo='interno' then "GP2".ubic_de('sector', v_prin.sector_id) else v_uorig end;
    v_rep := "GP2".repartir_sustituto(
               case when v_prin.sector_id in (10,11) and v_tipo <> 'interno' then v_ucons end,
               v_prin.componente_id, v_qty * v_prin.cantidad, v_usado);
    v_usado := v_rep->'usado';
    v_i := 0;
    for t in select value from jsonb_array_elements(v_rep->'tramos') loop
      v_i := v_i + 1;
      if v_i = 1 then
        v_movs := v_movs || jsonb_build_object(
          'tipo_mov','recepcion_virgilio','comp_id',(t->>'comp_id')::bigint,
          'ubic_origen_id', v_ucons, 'ubic_destino_id', v_uvirg,
          'cantidad', (t->>'cantidad')::numeric,
          'sustituye_comp_id', t->>'sustituye_comp_id',
          'comp_transformado_id', v_compfin, 'cantidad_transformada', v_qty);
      else
        v_movs := v_movs || jsonb_build_object(
          'tipo_mov','consumo_virgilio','comp_id',(t->>'comp_id')::bigint,
          'ubic_origen_id', v_ucons, 'ubic_destino_id', null,
          'cantidad', (t->>'cantidad')::numeric,
          'sustituye_comp_id', t->>'sustituye_comp_id');
      end if;
    end loop;
    v_n := v_n+1;
  end loop;

  if v_dry then return jsonb_build_object('ok',true,'dry_run',true,'articulos',v_n,'movimientos',v_movs); end if;

  insert into movimiento(fecha,tipo_mov,comp_id,ubic_origen_id,ubic_destino_id,cantidad,unidad_origen,
                         comp_transformado_id,cantidad_transformada,unidad_destino,sustituye_comp_id)
  select v_fecha, m->>'tipo_mov', (m->>'comp_id')::bigint,
         nullif(m->>'ubic_origen_id','')::bigint, nullif(m->>'ubic_destino_id','')::bigint,
         (m->>'cantidad')::numeric,'uni',
         nullif(m->>'comp_transformado_id','')::bigint, nullif(m->>'cantidad_transformada','')::numeric,'uni',
         nullif(m->>'sustituye_comp_id','')::bigint
  from jsonb_array_elements(v_movs) m;

  return jsonb_build_object('ok',true,'articulos',v_n,'movimientos',jsonb_array_length(v_movs));
end $function$
;

-- ---------- recibir_mensaje_cervantes ----------
CREATE OR REPLACE FUNCTION "GP2".recibir_mensaje_cervantes(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'GP2', 'pg_temp'
AS $function$
declare v_id uuid; v_leg text := btrim(coalesce(p->>'legajo',''));
begin
  if v_leg = '' then raise exception 'Falta el legajo'; end if;
  perform "GP2"._exigir_operario(v_leg);
  if coalesce(p->>'client_id','') = '' or coalesce(p->>'opcion','') = '' then
    raise exception 'Faltan client_id u opcion';
  end if;
  insert into registros_produccion_cervantes (client_id, legajo, opcion, descripcion, texto, matriz, ts_cliente, ts_inicio, app_version)
  values (p->>'client_id', v_leg, p->>'opcion', nullif(p->>'descripcion',''), nullif(p->>'texto',''),
          nullif(btrim(coalesce(p->>'matriz','')),''), coalesce(nullif(p->>'ts_cliente','')::timestamptz, now()),
          nullif(p->>'ts_inicio','')::timestamptz, nullif(p->>'app_version',''))
  on conflict (client_id) do nothing
  returning id into v_id;
  if v_id is null then   -- reintento de la cola offline: ya estaba
    select id into v_id from registros_produccion_cervantes where client_id = p->>'client_id';
    return jsonb_build_object('ok', true, 'id', v_id, 'dup', true);
  end if;
  return jsonb_build_object('ok', true, 'id', v_id);
end $function$
;

-- ---------- recibir_oc_virgilio ----------
CREATE OR REPLACE FUNCTION "GP2".recibir_oc_virgilio(p_oc_id bigint, p_items jsonb, p_remito text DEFAULT NULL::text, p_legajo text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
declare v_oc record; v_it jsonb; v_res jsonb; v_out jsonb := '[]'::jsonb; v_comp bigint; v_cant numeric; v_kg_bolsa numeric;
begin
  perform "GP2"._exigir_autorizado();  -- seguridad punto 1 fase B (2026-09-28)
  select * into v_oc from orden_compra where id = p_oc_id;
  if v_oc.id is null then raise exception 'La OC % no existe', p_oc_id; end if;
  if v_oc.estado not in ('borrador','enviada') then raise exception 'La OC % esta %', v_oc.numero, v_oc.estado; end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'p_items tiene que ser un array [{comp_id, cantidad}] o [{cod_virgilio, bolsas}]';
  end if;
  v_kg_bolsa := coalesce((select valor from parametro where clave='material_plastico_kg_x_bolsa'), 25);
  for v_it in select * from jsonb_array_elements(p_items) loop
    v_comp := (v_it->>'comp_id')::bigint;
    if v_comp is null and v_it->>'cod_virgilio' is not null then
      select id into v_comp from componente where sector_id = 14 and upper(btrim(codigo_virgilio)) = upper(btrim(v_it->>'cod_virgilio'));
      if v_comp is null then raise exception 'El codigo "%" no es una bolsa de material conocida en GP2', v_it->>'cod_virgilio'; end if;
    end if;
    v_cant := coalesce((v_it->>'cantidad')::numeric, (v_it->>'bolsas')::numeric * v_kg_bolsa);
    if v_comp is null or v_cant is null then raise exception 'Cada item necesita comp_id+cantidad (kg) o cod_virgilio+bolsas: %', v_it; end if;
    if not exists (select 1 from orden_compra_item oi where oi.oc_id = p_oc_id and oi.componente_id = v_comp) then
      raise exception 'El componente % no esta en la OC %', v_comp, v_oc.numero;
    end if;
    v_res := crear_recepcion_insumo(v_comp, v_oc.proveedor, v_cant, 'kg', p_remito, now());
    update recepcion_insumo
       set rollos_json = coalesce(rollos_json,'{}'::jsonb)
                      || jsonb_build_object('recibido_en', 'virgilio', 'legajo', p_legajo, 'oc_id', p_oc_id, 'bolsas', (v_it->>'bolsas')::numeric)
     where id = (v_res->>'recepcion_id')::bigint;
    v_out := v_out || jsonb_build_object('comp_id', v_comp, 'kg', v_cant, 'recepcion_id', v_res->'recepcion_id', 'oc_cruzada', v_res->'oc_cruzada');
  end loop;
  return jsonb_build_object('ok', true, 'oc_id', p_oc_id, 'numero', v_oc.numero,
    'estado', (select estado from orden_compra where id = p_oc_id), 'recepciones', v_out);
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
  v_nsal int; v_salida bigint;
  v_movid bigint; v_aviso text;
  v_th numeric; v_tt numeric; v_premio numeric; v_segs numeric;
  v_golpes numeric; v_uxg numeric; v_res jsonb;
begin
  perform "GP2"._exigir_autorizado();  -- seguridad punto 1 fase B (2026-09-28)
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
      v_res := "GP2".fabricar_stock(v_mid, v_salida, v_uni, v_f);
      v_movid := nullif(v_res->>'movimiento_id','')::bigint;
      if (v_res->>'n_entradas')::int = 0 then v_aviso := coalesce(v_aviso, v_res->>'aviso'); end if;
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
        v_tipo text; v_cant numeric; v_o bigint; v_d bigint; v_comp bigint;
        v_trans bigint; v_cant_t numeric; v_i int := 0;
begin
  perform "GP2"._exigir_autorizado();  -- seguridad punto 1 fase B (2026-09-28)
  if jsonb_typeof(p_rows) <> 'array' then raise exception 'p_rows debe ser un array JSON'; end if;
  if jsonb_array_length(p_rows)=0 then raise exception 'No hay movimientos para registrar'; end if;
  for r in select * from jsonb_array_elements(p_rows) loop
    v_i := v_i + 1;
    v_tipo   := nullif(btrim(coalesce(r->>'tipo_mov','')),'');
    v_cant   := coalesce(nullif(r->>'cantidad','')::numeric, 0);
    v_o      := nullif(r->>'ubic_origen_id','')::bigint;
    v_d      := nullif(r->>'ubic_destino_id','')::bigint;
    v_comp   := nullif(r->>'comp_id','')::bigint;
    v_trans  := nullif(r->>'comp_transformado_id','')::bigint;
    v_cant_t := nullif(r->>'cantidad_transformada','')::numeric;

    if v_tipo is null then raise exception 'Movimiento %: falta tipo_mov', v_i; end if;
    if v_comp is null then raise exception 'Movimiento % (%): falta comp_id', v_i, v_tipo; end if;
    if v_tipo = 'ajuste' then
      if v_cant = 0 then raise exception 'Movimiento % (ajuste): la cantidad no puede ser 0', v_i; end if;
    elsif v_cant <= 0 then
      raise exception 'Movimiento % (%): la cantidad debe ser mayor a 0 (recibido %)', v_i, v_tipo, v_cant;
    end if;
    if v_o is null and v_d is null then
      raise exception 'Movimiento % (%): tiene que tocar al menos una ubicacion', v_i, v_tipo;
    end if;
    -- mismo componente, misma ubicacion de los dos lados = no mueve nada
    if v_o is not null and v_o = v_d and coalesce(v_trans, v_comp) = v_comp then
      raise exception 'Movimiento % (%): el mismo componente entra y sale de la misma ubicacion (%)', v_i, v_tipo, v_o;
    end if;
    if (v_trans is null) <> (v_cant_t is null) then
      raise exception 'Movimiento % (%): comp_transformado_id y cantidad_transformada van juntos o ninguno', v_i, v_tipo;
    end if;
    if v_cant_t is not null and v_tipo <> 'ajuste' and v_cant_t <= 0 then
      raise exception 'Movimiento % (%): cantidad_transformada debe ser mayor a 0', v_i, v_tipo;
    end if;
    if v_trans is not null and v_d is null then
      raise exception 'Movimiento % (%): una transformacion necesita ubicacion destino', v_i, v_tipo;
    end if;

    insert into "GP2".movimiento(
      fecha, tipo_mov, comp_id, ubic_origen_id, ubic_destino_id, cantidad,
      unidad_origen, comp_transformado_id, cantidad_transformada, unidad_destino,
      cajones, faltante, nota
    ) values (
      coalesce(nullif(r->>'fecha','')::timestamptz, now()),
      v_tipo, v_comp, v_o, v_d, v_cant,
      coalesce(nullif(r->>'unidad_origen',''),'uni'),
      v_trans, v_cant_t,
      coalesce(nullif(r->>'unidad_destino',''),'uni'),
      nullif(r->>'cajones','')::numeric,
      coalesce(nullif(r->>'faltante','')::boolean, false),
      nullif(btrim(coalesce(r->>'nota','')),'')
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
  v_nsal int; v_salida bigint;
  v_movid bigint; v_aviso text := null;
  v_uxg numeric; v_uni numeric; v_res jsonb;
begin
  perform "GP2"._exigir_autorizado();  -- seguridad punto 1 fase B (2026-09-28)
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

  insert into produccion(fecha, legajo, nombre_empleado, matriz_raw, matriz_id, nombre_matriz, uni,
                         golpes, uni_x_golpe, dia, mes, quincena, origen_created_at)
  values (v_f, nullif(btrim(coalesce(p_legajo,'')),''), nullif(btrim(coalesce(p_nombre,'')),''),
          btrim(p_matriz), v_mid, v_mname, v_uni,
          p_golpes, case when p_golpes is not null then coalesce(v_uxg,1) end,
          extract(day from (v_f at time zone 'America/Argentina/Buenos_Aires'))::int, extract(month from (v_f at time zone 'America/Argentina/Buenos_Aires'))::int,
          case when extract(day from (v_f at time zone 'America/Argentina/Buenos_Aires'))::int <= 15 then 1 else 2 end, now())
  returning id into v_id;

  if v_salida is not null then
    v_res := "GP2".fabricar_stock(v_mid, v_salida, v_uni, v_f);
    v_movid := nullif(v_res->>'movimiento_id','')::bigint;
    v_aviso := v_res->>'aviso';
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
  -- Fuera del carton, el envase es uni_x_cajon; si la pieza no lo tiene y SI tiene su envase de
  -- entrega (componente.entrega_uni_x + entrega_unidad: Z21 cajas de 450, GRJ13/GRJ14 cajas de
  -- 100, GRJ21A/B cajas de 5400), se cuenta en ESE envase (2026-09-25; antes quedaba sin factor y
  -- el relevamiento solo dejaba cargar sueltas, contra la planilla que cuenta "Cajon/Bulto").
  select
    case
      when coalesce(c.relev_solo_sueltas,false) then null
      when c.sector_id = 10 and coalesce(c.es_pliego,false)
        then (select valor::numeric from "GP2".parametro where clave='pliego_uni_x_paquete')
      when c.sector_id = 10
        then nullif(c.entrega_uni_x,0)
      when c.sector_id = 11
        then (select valor::numeric from "GP2".parametro where clave='caja_uni_x_paquete')
      when c.sector_id = 5 then null                      -- fleje se cuenta en kg
      else coalesce(nullif(c.uni_x_cajon, 0), nullif(c.entrega_uni_x, 0))
    end,
    case
      when coalesce(c.relev_solo_sueltas,false) then null  -- sin envase: solo sueltas
      when c.sector_id not in (5, 10, 11) and nullif(c.uni_x_cajon, 0) is null
           and nullif(c.entrega_uni_x, 0) is not null and c.entrega_unidad is not null
        then initcap(c.entrega_unidad)
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
  perform "GP2"._exigir_autorizado();  -- seguridad punto 1 fase B (2026-09-28)
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
  perform "GP2"._exigir_autorizado();  -- seguridad punto 1 fase B (2026-09-28)
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
  perform "GP2"._exigir_autorizado();  -- seguridad punto 1 fase B (2026-09-28)
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
  perform "GP2"._exigir_autorizado();  -- seguridad punto 1 fase B (2026-09-28)
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
  perform "GP2"._exigir_autorizado();  -- seguridad punto 1 fase B (2026-09-28)
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
  perform "GP2"._exigir_autorizado();  -- seguridad punto 1 fase B (2026-09-28)
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
  perform "GP2"._exigir_autorizado();  -- seguridad punto 1 fase B (2026-09-28)
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

-- ---------- repartir_sustituto ----------
CREATE OR REPLACE FUNCTION "GP2".repartir_sustituto(p_ubic bigint, p_oficial bigint, p_necesidad numeric, p_usado jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
declare v_tramos jsonb := '[]'::jsonb; v_falta numeric := coalesce(p_necesidad,0);
        v_usado jsonb := coalesce(p_usado,'{}'::jsonb);
        s record; v_k text; v_disp numeric; v_usa numeric;
begin
  if p_ubic is not null and v_falta > 0 then
    for s in select * from "GP2".v_carton_sustituto_saldo
              where ubicacion_id = p_ubic and oficial_id = p_oficial
              order by desde, sustituto_id loop
      exit when v_falta <= 0;
      v_k    := p_oficial::text || ':' || s.sustituto_id::text;
      v_disp := s.saldo - coalesce((v_usado->>v_k)::numeric, 0);
      if v_disp <= 0 then continue; end if;
      v_usa  := least(v_falta, v_disp);
      v_usado := v_usado || jsonb_build_object(v_k, coalesce((v_usado->>v_k)::numeric,0) + v_usa);
      v_tramos := v_tramos || jsonb_build_object('comp_id', s.sustituto_id, 'cantidad', v_usa,
                                                 'sustituye_comp_id', p_oficial);
      v_falta := v_falta - v_usa;
    end loop;
  end if;
  if v_falta > 0 or jsonb_array_length(v_tramos) = 0 then
    v_tramos := v_tramos || jsonb_build_object('comp_id', p_oficial, 'cantidad', greatest(v_falta,0));
  end if;
  return jsonb_build_object('tramos', v_tramos, 'usado', v_usado);
end $function$
;

-- ---------- reparto_guardar ----------
CREATE OR REPLACE FUNCTION "GP2".reparto_guardar(p_articulo_id bigint, p_comp_salida_id bigint, p_filas jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
declare v_suma numeric; v_n int; v_intruso text; v_max jsonb;
begin
  if p_articulo_id is null or p_comp_salida_id is null then
    raise exception 'Falta el articulo o el paso';
  end if;

  select count(*), coalesce(sum((f->>'pct')::numeric), 0)
    into v_n, v_suma from jsonb_array_elements(coalesce(p_filas, '[]'::jsonb)) f;

  if v_n > 0 then
    if abs(v_suma - 100) > 0.01 then
      raise exception 'Los porcentajes de un paso tienen que sumar 100 (suman %)', v_suma;
    end if;
    select string_agg(t.nombre, ', ') into v_intruso
      from jsonb_array_elements(p_filas) f
      join tallerista t on t.id = (f->>'tallerista_id')::bigint
     where not exists (
       select 1 from ruta_paso rp join ruta r on r.id = rp.ruta_id
        where r.articulo_id = p_articulo_id and rp.comp_salida_id = p_comp_salida_id
          and rp.tallerista_id = (f->>'tallerista_id')::bigint);
    if v_intruso is not null then
      raise exception 'Segun las rutas, % no hace ese paso', v_intruso;
    end if;
  end if;

  delete from reparto_tallerista
   where articulo_id = p_articulo_id and comp_salida_id = p_comp_salida_id;

  if v_n > 0 then
    insert into reparto_tallerista (articulo_id, comp_salida_id, tallerista_id, pct)
    select p_articulo_id, p_comp_salida_id, (f->>'tallerista_id')::bigint, (f->>'pct')::numeric
      from jsonb_array_elements(p_filas) f;
  end if;

  -- el maximo de cada tallerista sale de lo que le toca hacer: si cambia el reparto, cambia
  v_max := recalcular_maximos_talleristas(true);
  return jsonb_build_object('ok', true, 'filas', v_n, 'maximos', v_max);
end $function$
;

-- ---------- reprocesar_espejo_virgilio ----------
CREATE OR REPLACE FUNCTION "GP2".reprocesar_espejo_virgilio(p_ids bigint[] DEFAULT NULL::bigint[], p_dry_run boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
declare
  r record; v_tipo text; v_ref bigint; v_art record; v_uni numeric; v_fecha timestamptz;
  v_res jsonb; v_out jsonb := '[]'::jsonb; v_ok int := 0; v_no int := 0; v_motivo text;
begin
  for r in
    select * from virgilio_espejo_pend
     where resuelto_en is null
       and (p_ids is null or id = any(p_ids))
     order by id
  loop
    v_motivo := null; v_res := null; v_tipo := null; v_ref := null;
    begin
      -- contraparte: alias primero, despues tallerista por nombre, despues prov AT
      select a.tipo, a.ref_id into v_tipo, v_ref
        from contraparte_alias a where a.alias = upper(btrim(coalesce(r.nombre_tall,'')));
      if v_tipo is null then
        select 'tallerista', t.id into v_tipo, v_ref from tallerista t
         where upper(t.nombre) = upper(btrim(coalesce(r.nombre_tall,'')))
            or upper(t.nombre) ~ ('(^|\s)'||upper(btrim(coalesce(r.nombre_tall,'')))||'($|\s)') limit 1;
      end if;
      if v_tipo is null then
        select 'proveedor_at', p.id into v_tipo, v_ref from proveedor_at p
         where upper(p.nombre) = upper(btrim(coalesce(r.nombre_tall,''))) limit 1;
      end if;
      if v_tipo is null then v_motivo := 'contraparte sin resolver'; end if;

      if v_motivo is null then
        select a.id, a.articulos_por_caja into v_art from articulo a
         where a.codigo = btrim(r.cod)
            or regexp_replace(a.codigo,'^0+','') = regexp_replace(btrim(r.cod),'^0+','')
         order by (a.codigo = btrim(r.cod)) desc limit 1;
        if v_art.id is null then v_motivo := 'articulo sin equivalente en GP2';
        elsif not exists (select 1 from articulo_componente ac where ac.articulo_id = v_art.id)
          then v_motivo := 'el articulo todavia no tiene receta';
        end if;
      end if;

      if v_motivo is null then
        v_uni := coalesce(r.cajas,0) * coalesce(v_art.articulos_por_caja,0);
        if v_uni <= 0 then v_motivo := 'cantidad en cero'; end if;
      end if;

      if v_motivo is null then
        begin v_fecha := nullif(btrim(coalesce(r.fecha,'')),'')::timestamptz;
        exception when others then v_fecha := null; end;
        v_res := "GP2".recepcion_virgilio(jsonb_build_object(
          'fecha', coalesce(v_fecha, r.creado_en, now()),
          'origen_tipo', v_tipo, 'origen_id', v_ref,
          'dry_run', p_dry_run,
          'items', jsonb_build_array(jsonb_build_object('articulo_id', v_art.id, 'cantidad', v_uni))));
        if not p_dry_run then
          update virgilio_espejo_pend
             set resuelto_en = now(), resultado = v_res
           where id = r.id;
        end if;
        v_ok := v_ok + 1;
      else
        v_no := v_no + 1;
        if not p_dry_run then
          update virgilio_espejo_pend set resultado = jsonb_build_object('motivo', v_motivo, 'visto_en', now())
           where id = r.id;
        end if;
      end if;
    exception when others then
      v_motivo := 'error: '||sqlerrm; v_no := v_no + 1;
    end;

    v_out := v_out || jsonb_build_object('id', r.id, 'cod', r.cod, 'tall', r.nombre_tall,
               'cajas', r.cajas, 'uni', v_uni, 'origen', v_tipo, 'ok', (v_motivo is null),
               'motivo', v_motivo, 'movimientos', v_res->'movimientos');
  end loop;
  return jsonb_build_object('ok', true, 'dry_run', p_dry_run, 'reprocesadas', v_ok,
                            'siguen_pendientes', v_no, 'detalle', v_out);
end $function$
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
  perform "GP2"._exigir_autorizado();  -- seguridad punto 1 fase B (2026-09-28)
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
  perform "GP2"._exigir_autorizado();  -- seguridad punto 1 fase B (2026-09-28)
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
  perform "GP2"._exigir_autorizado();  -- seguridad punto 1 fase B (2026-09-28)
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
  perform "GP2"._exigir_autorizado();  -- seguridad punto 1 fase B (2026-09-28)
  update "GP2".ruta_revision
     set estado = 'resuelto', resuelto_en = now()
   where id = p_id and estado = 'pendiente';
end;
$function$
;

-- ---------- stock_general_extra_bundle ----------
CREATE OR REPLACE FUNCTION "GP2".stock_general_extra_bundle()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
with pa as (
  select p.id, p.nombre, "GP2".ubic_de('proveedor_at', p.id) ubic_id
    from proveedor_at p
   where coalesce(p.activo, true)
), pa_comp as (
  select distinct pa.id pa_id, pa.nombre, pa.ubic_id, c.id comp_id, c.sector_id
    from pa
    join articulo_prov_at apa on apa.proveedor_at_id = pa.id and coalesce(apa.activo, true)
    join articulo a on a.codigo = apa.cod_art
    join articulo_componente ac on ac.articulo_id = a.id
    join componente c on c.id = ac.componente_id
   where c.sector_id in (10, 11)          -- Sector Carton y Sector Caja
), pares as (
  select distinct p1.comp_salida_id comp_id, p1.proveedor_id ps1_id, p2.proveedor_id ps2_id
    from ruta_paso p1
    join ruta_paso p2 on p2.ruta_id = p1.ruta_id and p2.orden = p1.orden + 1
   where p1.tipo_paso = 'proveedor_servicio' and p2.tipo_paso = 'proveedor_servicio'
     and p1.comp_salida_id is not null and p2.comp_entrada_id = p1.comp_salida_id
), tr as (
  select pr.comp_id, ps1.nombre ps1_nombre, ps2.nombre ps2_nombre,
         coalesce((select sum(m._delta_dest) from movimiento m
                    where m.tipo_mov = 'entrega_ps'
                      and coalesce(m.comp_transformado_id, m.comp_id) = pr.comp_id
                      and m.ubic_origen_id = "GP2".ubic_de('proveedor_servicio', ps1.id)), 0)
       - coalesce((select sum(m._delta_orig) from movimiento m
                    where m.tipo_mov = 'envio_ps' and m.comp_id = pr.comp_id
                      and m.ubic_destino_id = "GP2".ubic_de('proveedor_servicio', ps2.id)), 0) cant
    from pares pr
    join proveedor_servicio ps1 on ps1.id = pr.ps1_id
    join proveedor_servicio ps2 on ps2.id = pr.ps2_id
)
select jsonb_build_object(
  'prov_at', coalesce((select jsonb_agg(x order by x->>'nom') from (
      select jsonb_build_object(
               'id', pa_id, 'nom', nombre, 'ubic', ubic_id,
               'filas', jsonb_agg(jsonb_build_object(
                          'cid', comp_id,
                          'cant', coalesce((select i.cantidad from inventario i
                                             where i.componente_id = comp_id and i.ubicacion_id = ubic_id), 0),
                          'max',  (select i.maximo from inventario i
                                    where i.componente_id = comp_id and i.ubicacion_id = ubic_id))
                        order by comp_id)) x
        from pa_comp group by pa_id, nombre, ubic_id) y), '[]'::jsonb),
  'transito', coalesce((select jsonb_agg(jsonb_build_object(
      'cid', comp_id, 'ps1', ps1_nombre, 'ps2', ps2_nombre, 'cant', cant)
      order by ps1_nombre, ps2_nombre, comp_id) from tr), '[]'::jsonb),
  'generado_en', now());
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
ubic_v as (
  select "GP2".ubic_de('virgilio_sector', p_sector_id) id
),
comps as (
  select c.* from componente c where c.sector_id = p_sector_id
),
ent as (
  select coalesce(m.comp_transformado_id, m.comp_id) comp_id,
         m.tipo_mov,
         sum(coalesce(m._delta_dest,0)) qty,
         count(*) n
    from movimiento m
   where m.ubic_destino_id = (select id from ubic)
   group by 1,2
),
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
  'ubicacion_virgilio_id', (select id from ubic_v),
  'filas', coalesce((select jsonb_agg(jsonb_build_object(
      'comp_id', c.id,
      'cod', c.codigo,
      'desc', c.descripcion,
      'um', c.unidad_medida,
      'kg_x_uni', c.kg_x_uni,
      'uni_x_cajon', c.uni_x_cajon,
      'online', coalesce(i.cantidad,0),
      'en_virgilio', case when (select id from ubic_v) is null then null else coalesce(iv.cantidad,0) end,
      'maximo', i.maximo,
      'n_fleje', fd.n_fleje,
      'mov', coalesce(mv.obj, '{}'::jsonb)
    ) order by c.codigo)
    from comps c
    left join inventario i on i.componente_id=c.id and i.ubicacion_id=(select id from ubic)
    left join inventario iv on iv.componente_id=c.id and iv.ubicacion_id=(select id from ubic_v)
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

-- ---------- tablet_bundle ----------
CREATE OR REPLACE FUNCTION "GP2".tablet_bundle()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
with
-- FASONERO (proveedor_servicio.pedido_por_oc, hoy Maspoli): lo que falta entregar de su O.C.
-- ENVIADA, sumado por (proveedor, pieza que se le manda). Es el techo de lo que hay que mandarle:
-- si nos debe 10 mangos, hay que tener 10 virolas en su poder [usuario 2026-09-18]. Mismo criterio
-- que el inyector (rep_iny): el borrador es un pedido que todavia no salio y no dispara envio.
oc_ps as (
  select p.proveedor_id, p.comp_entrada_id as comp_id, sum(coalesce(x.pend,0)) as pend
    from (select distinct rp.proveedor_id, rp.comp_entrada_id, rp.comp_salida_id
            from ruta_paso rp
            join proveedor_servicio ps on ps.id = rp.proveedor_id and ps.pedido_por_oc
           where rp.tipo_paso = 'proveedor_servicio' and rp.comp_entrada_id is not null) p
    left join lateral (
       select sum(oi.cantidad - coalesce(oi.recibido,0)) as pend
         from orden_compra_item oi join orden_compra o on o.id = oi.oc_id
        where oi.componente_id = p.comp_salida_id and o.estado = 'enviada'
          and oi.cantidad > coalesce(oi.recibido,0)
    ) x on true
   group by p.proveedor_id, p.comp_entrada_id
),
env as (
  select v.tipo, v.ref_id::text as ref, v.comp_id
    from v_contraparte_parte v
   where v.lado = 'entrada'
     and ( (v.tipo = 'tallerista'
            and exists (select 1 from tallerista t where t.id = v.ref_id and t.activo and t.id <> 3))
        or (v.tipo = 'proveedor_servicio'
            -- los PS hibridos (Charcas/Eclipse) NO se envian desde la tablet: la entrega de su
            -- materia prima se registra solo en el modulo Casos especiales [usuario 2026-09-17].
            -- el FASONERO aparece SIEMPRE, igual que el inyector: sin O.C. su sugerido es 0 y sube
            -- cuando la orden sale [usuario 2026-09-18: "los inyectores por mas que no este
            -- cargada la orden de compra aparecen igual con cero sugerido, tendria que aparecer
            -- Maspoli con cero sugerido y cuando sale la orden de compra ahi sube el sugerido de
            -- entrega de virolas"]. El techo lo pone oc_ps en la CTE rep, que sin O.C. da 0.
            and exists (select 1 from proveedor_servicio ps where ps.id = v.ref_id and not ps.hibrido)) )
  union all
  select 'proveedor_at', apa.proveedor_at_id::text, ac.componente_id
    from articulo_prov_at apa
    join articulo a on a.codigo = apa.cod_art and not a.discontinuado
    join articulo_componente ac on ac.articulo_id = a.id
    join componente c on c.id = ac.componente_id
   where coalesce(apa.activo,true)
     and c.sector_id in (10,11) and not coalesce(c.discontinuado,false)
  union all
  select 'inyector', c.proveedor, c.material_id
    from componente c
   where c.material_id is not null and c.estado_compra is null and c.proveedor is not null
     and exists (select 1 from proveedor_insumo pi where pi.nombre = c.proveedor)
   group by c.proveedor, c.material_id
),
-- rep (Enviar a PS / tallerista): el Maximo y el Sugerido salen del CONSUMO DE LA PIEZA QUE SE
-- ENVIA (la entrada), no de la salida. [usuario 2026-09-17: "sale del consumo de estadistica
-- madre x max de meses por ubicacion"]. Antes se calculaba sobre la SALIDA (inventario.maximo de
-- la pieza procesada/armada): las salidas de tallerista son nodos "X Terminado" del sector 12 que
-- no tienen demanda ni maximo cargado, asi que el 90% de las filas salia en 0 (Martin 6 de 94).
-- Ahora maximo = consumo(entrada) x meses_stock de la ubicacion del sector de la entrada:
--   · tallerista -> v_consumo_tallerista (la demanda YA repartida entre los que hacen el paso,
--     via v_reparto_efectivo; asi no se le pide un mes entero a cada uno de dos que arman lo mismo),
--   · PS         -> v_consumo_componente (demanda total de la pieza),
--   · PROV AT    -> v_consumo_prov_at (la demanda del articulo repartida entre los prov AT que lo
--     entregan y los talleristas que lo arman; sin reparto dictado, partes iguales) [usuario
--     2026-09-23: "el inventario maximo de los prov de art terminado tiene que ser al igual que
--     los talleristas de un mes de consumo... si hay mas de uno dividir segun la proporcion"],
--   · fleje (sector 5, en kg) -> v_consumo_fleje_kg (kg/mes) para cualquiera de los dos tipos.
-- Sugerido = maximo − lo que el tercero ya tiene (inventario en su ubicacion). meses_stock cae a 1
-- si la ubicacion no lo tiene (mismo default que OC). OJO, la ubicacion de la que salen los MESES
-- no es la misma para todos: el tallerista y el P.S. la toman del SECTOR de la pieza (como estaba),
-- y el prov AT de SU PROPIA ubicacion, que es donde vive el "un mes" que pidio el usuario. El consumo ya viene en la unidad de la
-- entrada (kg para fleje, uni para el resto), asi que no hay factor de conversion.
-- CONSUMOS, UNA sola vez (2026-09-22): antes se consultaban las tres vistas de consumo fila por
-- fila dentro de rep (una subconsulta correlacionada por cada pieza x destino), y cada vista es
-- un agregado de 30-40 ms. Materializadas aca se calculan una vez y rep las cruza por join:
-- tablet_bundle bajo de ~700 ms a ~200 ms con el mismo resultado.
cons_fk   as materialized (select componente_id, consumo_kg_mes from v_consumo_fleje_kg),
cons_tall as materialized (select tallerista_id, componente_id, uni_mes from v_consumo_tallerista),
cons_comp as materialized (select componente_id, consumo_uni_mes from v_consumo_componente),
cons_pat  as materialized (select proveedor_at_id, componente_id, uni_mes from v_consumo_prov_at),
rep as (
  select e.tipo, e.ref, e.comp_id,
         round(t.techo) as maximo_dest,
         null::numeric as stock_dest,   -- el front muestra saldo_dest como "Stock", no este
         greatest(0, round(
            t.techo
            - coalesce((select i.cantidad from inventario i
                         where i.componente_id = e.comp_id
                           and i.ubicacion_id = ubic_de(e.tipo, e.ref::bigint) limit 1),0)
         , 2)) as sugerido
    from (select distinct tipo, ref, comp_id from env
           where tipo in ('proveedor_servicio','tallerista','proveedor_at')) e
    join componente ent on ent.id = e.comp_id
    left join cons_fk   fk on fk.componente_id = e.comp_id
    left join cons_tall ct on ct.componente_id = e.comp_id and e.tipo = 'tallerista'
                          and ct.tallerista_id = e.ref::bigint
    left join cons_pat cpa on cpa.componente_id = e.comp_id and e.tipo = 'proveedor_at'
                          and cpa.proveedor_at_id = e.ref::bigint
    left join cons_comp vc on vc.componente_id = e.comp_id
    cross join lateral (
       select
         coalesce((select u.meses_stock from ubicacion u
                    where u.id = case when e.tipo = 'proveedor_at'
                                        then ubic_de('proveedor_at', e.ref::bigint)
                                      -- el tallerista se surte de UN mes (regla del usuario 2026-09-23:
                                      -- "los talleristas de un mes de consumo"), que vive en SU propia
                                      -- ubicacion (las 12 en meses_stock=1). Antes tomaba el meses_stock
                                      -- del SECTOR de la pieza (Bombilla=3, Plastico=4, Carton/Fleje=6),
                                      -- pensado para el stock de insumos del sector, e inflaba el
                                      -- sugerido: LLF8 a Alex daba 29 cajones (6.644 x 3 / 698) en vez
                                      -- de 9,5. El P.S. sigue tomando el del sector (como estaba).
                                      when e.tipo = 'tallerista'
                                        then ubic_de('tallerista', e.ref::bigint)
                                      else ubic_de('sector', ent.sector_id) end
                    limit 1), 1) as meses,
         case
           -- solo el fleje que se PESA va por kg/mes. IC3/IC3V (alambre N 90 cortado) son sector 5 pero
           -- se cuentan en unidades: no estan en v_consumo_fleje_kg y daban sugerido 0 a IJUPA
           -- [usuario 2026-09-25: "me aparece cero cajones en el sugerido. Tendria que salir el consumo"].
           when ent.sector_id = 5 and ent.unidad_medida = 'kg' then coalesce(fk.consumo_kg_mes, 0)
           when e.tipo = 'tallerista'     then coalesce(ct.uni_mes, 0)
           when e.tipo = 'proveedor_at'   then coalesce(cpa.uni_mes, 0)
           else                                coalesce(vc.consumo_uni_mes, 0)
         end as consumo
    ) cons
    cross join lateral (
       -- FASONERO: el techo es lo que falta entregar de su O.C., no el consumo x meses. Para el
       -- resto (PS normal y tallerista) no cambia nada.
       select case when e.tipo = 'proveedor_servicio'
                    and exists (select 1 from proveedor_servicio ps3
                                 where ps3.id = e.ref::bigint and ps3.pedido_por_oc)
                   then coalesce((select oc.pend from oc_ps oc
                                   where oc.proveedor_id = e.ref::bigint and oc.comp_id = e.comp_id), 0)
                   -- TALLERISTA CON O.C. DE VIRGILIO: mismo criterio que el fasonero sin O.C. — el
                   -- pedido no sale del consumo x meses sino de una orden que GP2 no lee, asi que
                   -- el techo es 0 y con el el sugerido [usuario 2026-09-23: "No es o.c. de
                   -- insumos. Es orden de compra que se hace desde Gestion Virgilio que hoy no
                   -- esta modelado aca. Por ahora sugeri 0"]. Cuando esa O.C. se modele, este 0
                   -- es lo unico que se cambia.
                   when e.tipo = 'tallerista'
                    and exists (select 1 from tallerista t8
                                 where t8.id = e.ref::bigint and t8.pedido_por_oc_virgilio)
                   -- (2026-09-26, unas horas: los pasos que entregan en GARAGE tambien iban por esta O.C.;
                   -- el dueno lo corrigio: "los que llenan garage se tienen que llenar por orden de compra
                   -- de INSUMOS, no por orden de compra de articulo terminado". Vuelven al maximo de la casa.)
                   -- 2026-09-26: la O.C. de Virgilio YA se lee (espejo GP2.oc_virgilio). El techo son las
                   -- partes que ese tallerista necesita para lo que falta entregar de la O.C. vigente,
                   -- explotada por receta y ruta (v_oc_virgilio_partes_tallerista). Sin O.C. sigue en 0.
                   then coalesce((select vt.uni_requeridas from v_oc_virgilio_partes_tallerista vt
                                   where vt.tallerista_id = e.ref::bigint and vt.componente_id = e.comp_id), 0)
                   -- PROV. DE ART. TERMINADO: igual que el tallerista con O.C. de Virgilio. El proveedor de
                   -- articulo terminado no tiene un maximo de inventario nuestro alla (no es gente de
                   -- la misma confianza que el tallerista a facon): lo que hay que mandarle sale de una
                   -- O.C. que emite Gestion Virgilio y que GP2 no lee, asi que el techo es 0 y con el el
                   -- sugerido [usuario 2026-09-24: "no tienen un maximo alla ellos... por lo tanto no
                   -- tiene que haber un sugerido de que mandarle, sino que tiene que aparecer en cero.
                   -- Cuando salga orden de compra de Virgilio... lo hace otro sistema ahora"]. DA VUELTA
                   -- la migracion del 2026-09-23 (consumo x meses con reparto), que queda dormida.
                   when e.tipo = 'proveedor_at'
                   -- ...HASTA EL 2026-09-26: ahora GP2 lee esa O.C. (espejo GP2.oc_virgilio ->
                   -- v_oc_virgilio_partes) y el techo son las PARTES (carton y caja) que el prov AT
                   -- necesita tener para cumplir lo que le falta entregar de su O.C. vigente
                   -- [usuario 2026-09-26: "solamente tenemos que mandarle partes para que puedan
                   -- hacer lo que les pide su orden de compra"]. Sin O.C. vigente sigue en 0.
                   then coalesce((select vp.uni_requeridas from v_oc_virgilio_partes vp
                                   where vp.tipo = 'proveedor_at' and vp.ref_id = e.ref::bigint
                                     and vp.componente_id = e.comp_id), 0)
                   else cons.consumo * cons.meses end as techo
    ) t
),
-- INYECTOR: el pedido de bolsas surge de la O.C. de partes plasticas ENVIADA (no del deficit
-- automatico). Sin OC enviada -> maximo(O.C.)=0 y sugerido=0; recien cuando se manda la OC de partes
-- (Compras/OC_GP2, proveedor = el inyector) aparecen los kg de bolsa. [usuario 2026-09-16]
rep_iny as (
  select 'inyector'::text as tipo, c.proveedor as ref, c.material_id as comp_id,
         sum(coalesce(ocp.pend,0) * coalesce(c.kg_x_uni,0)) as maximo_dest,  -- O.C. de partes -> kg de resina
         0::numeric as stock_dest,                                           -- el Stock lo pone online_sector en el front
         greatest(0, round(
            sum(coalesce(ocp.pend,0) * coalesce(c.kg_x_uni,0))
            - coalesce((select ir.cantidad from inventario ir
                         where ir.componente_id = c.material_id
                           and ir.ubicacion_id = ubic_de('inyector',
                                 (select pi2.id from proveedor_insumo pi2 where pi2.nombre = c.proveedor limit 1))
                         limit 1), 0)
         , 2)) as sugerido
    from componente c
    left join lateral (
       -- el vinculo es la PIEZA (c.proveedor ya es el inyector), no o.proveedor: la OC de rubro
       -- Plastico abarca partes de varios inyectores y puede venir con proveedor NULL.
       select sum(oi.cantidad - coalesce(oi.recibido,0)) as pend
         from orden_compra o
         join orden_compra_item oi on oi.oc_id = o.id
        where o.estado = 'enviada' and oi.componente_id = c.id
    ) ocp on true
   where c.material_id is not null and c.estado_compra is null and c.proveedor is not null
     and exists (select 1 from proveedor_insumo pi where pi.nombre = c.proveedor)
   group by c.proveedor, c.material_id
),
rec as (
  select 'tallerista'::text as tipo, v.ref_id::text as ref, v.comp_id,
         case when exists (select 1 from componente_bom b where b.componente_padre_id = v.comp_id)
              then null::bigint
              else (select case when count(distinct rp.comp_entrada_id) = 1
                                then min(rp.comp_entrada_id) end
                      from ruta_paso rp
                     where rp.tipo_paso = 'tallerista' and rp.tallerista_id = v.ref_id
                       and rp.comp_salida_id = v.comp_id and rp.comp_entrada_id is not null
                       and rp.comp_entrada_id <> v.comp_id) end as comp_entrada_id,
         (select count(distinct rp.comp_entrada_id) from ruta_paso rp
           where rp.tipo_paso = 'tallerista' and rp.tallerista_id = v.ref_id
             and rp.comp_salida_id = v.comp_id and rp.comp_entrada_id is not null
             and rp.comp_entrada_id <> v.comp_id)::int as n_entradas,
         exists (select 1 from componente_bom b where b.componente_padre_id = v.comp_id) as tiene_bom,
         null::text as cod_art,
         coalesce((select i.cantidad from inventario i
                    where i.componente_id = v.comp_id
                      and i.ubicacion_id = ubic_de('tallerista', v.ref_id) limit 1), 0) as esperado,
         'online_tall'::text as esperado_origen
    from v_contraparte_parte v
    join componente c on c.id = v.comp_id
   where v.tipo = 'tallerista' and v.lado = 'salida'
     and c.sector_id <> 12 and not coalesce(c.discontinuado,false)
     and exists (select 1 from tallerista t where t.id = v.ref_id and t.activo and t.id <> 3)
  union all
  select 'proveedor_servicio', rp.proveedor_id::text, rp.comp_salida_id, rp.comp_entrada_id,
         1, false, null::text,
         coalesce((select i.cantidad from inventario i
                    where i.componente_id = rp.comp_entrada_id
                      and i.ubicacion_id = ubic_de('proveedor_servicio', rp.proveedor_id) limit 1), 0),
         'online_ps'
    from (select distinct proveedor_id, comp_entrada_id, comp_salida_id
            from ruta_paso
           where tipo_paso = 'proveedor_servicio' and proveedor_id is not null
             and comp_entrada_id is not null and comp_salida_id is not null) rp
    join componente cs on cs.id = rp.comp_salida_id and not coalesce(cs.discontinuado,false)
  union all
  select 'proveedor_at', a.proveedor_at_id::text, null::bigint, null::bigint, 0, false, a.cod_art,
         (select sum(oi.cantidad - coalesce(oi.recibido,0)) from orden_compra o
            join orden_compra_item oi on oi.oc_id = o.id
            join componente ci on ci.id = oi.componente_id
           where o.estado in ('borrador','enviada')
             and o.proveedor = (select nombre from proveedor_at where id = a.proveedor_at_id)
             and ci.codigo = a.cod_art),
         'oc'
    from articulo_prov_at a
   where coalesce(a.activo,true)
     and exists (select 1 from proveedor_at p where p.id = a.proveedor_at_id and coalesce(p.activo,true))
     and not exists (select 1 from articulo art where art.codigo = a.cod_art and art.discontinuado)
  union all
  select 'proveedor_insumo', o.proveedor, oi.componente_id, null::bigint, 0, false, null::text,
         sum(oi.cantidad - coalesce(oi.recibido,0)),
         'oc'
    from orden_compra o
    join orden_compra_item oi on oi.oc_id = o.id
   where o.estado in ('borrador','enviada')
   group by o.proveedor, oi.componente_id
  having sum(oi.cantidad - coalesce(oi.recibido,0)) > 0
  union all
  select 'virgilio', 'virgilio', i.componente_id, null::bigint, 0, false, null::text,
         sum(i.cantidad), 'online_virgilio'
    from inventario i
    join ubicacion u on u.id = i.ubicacion_id and u.tipo in ('virgilio','virgilio_sector')
    join componente c on c.id = i.componente_id
   where c.sector_id <> 12 and not coalesce(c.discontinuado,false)
   group by i.componente_id
  having sum(i.cantidad) <> 0
),
env_x as (
  select distinct on (e.tipo, e.ref, e.comp_id) e.tipo, e.ref, e.comp_id,
         c.codigo cod, c.descripcion descr, s.nombre sector, c.unidad_medida um,
         c.uni_x_cajon uxc, c.kg_x_uni kgu,
         -- envase de ENVIO propio de la pieza (componente.entrega_unidad/entrega_uni_x): una caja
         -- de 100 (GRJ13/GRJ14), una caja de 2400 (Descorazonador) o las bolsas de 120 de GRJ5/GRJ6.
         -- Si esta cargado gana sobre el "cajon" teorico (uni_x_cajon). [usuario 2026-09-24]
         c.entrega_unidad ent_uni, c.entrega_uni_x ent_ux,
         -- en que se escribe la CANTIDAD del envio: 'envase' (cajas cerradas) o 'kg'. NULL = la
         -- regla del sector (carton/caja en envase, el resto en kg). Z21: cajas [usuario 2026-09-25].
         c.envio_carga env_carga_pieza,
         c.sector_id sec_id, c.carton_formato cfmt,
         coalesce((select i.cantidad from inventario i
                    where i.componente_id = c.id
                      and i.ubicacion_id = ubic_de('sector', c.sector_id) limit 1), 0) online_sector,
         -- saldo en poder del tercero = lo que le enviamos − lo que nos entregó = inventario de lo
         -- que se le manda (la pieza/resina) en la ubicacion del destino. [usuario 2026-09-16]
         coalesce((select i.cantidad from inventario i
                    where i.componente_id = c.id
                      and i.ubicacion_id = (case
                            when e.tipo in ('proveedor_servicio','tallerista','proveedor_at') then ubic_de(e.tipo, e.ref::bigint)
                            when e.tipo = 'inyector' then ubic_de('inyector',
                                  (select pi3.id from proveedor_insumo pi3 where pi3.nombre = e.ref limit 1))
                          end) limit 1), 0) saldo_dest,
         coalesce(rep.maximo_dest, ri.maximo_dest) maximo_dest,
         coalesce(rep.stock_dest,  ri.stock_dest)  stock_dest,
         coalesce(rep.sugerido,    ri.sugerido)    sugerido
    from env e
    join componente c on c.id = e.comp_id and not coalesce(c.discontinuado,false)
                     and c.id not in (select comp_id from "GP2".v_componente_muerto)
    left join sector s on s.id = c.sector_id
    left join rep     on rep.tipo = e.tipo and rep.ref = e.ref and rep.comp_id = e.comp_id
    left join rep_iny ri on ri.tipo = e.tipo and ri.ref = e.ref and ri.comp_id = e.comp_id
   order by e.tipo, e.ref, e.comp_id
),
rec_x as (
  select r.tipo, r.ref, r.comp_id, r.comp_entrada_id, r.n_entradas, r.tiene_bom, r.cod_art,
         max(r.esperado) esperado, min(r.esperado_origen) esperado_origen,
         coalesce(c.codigo, r.cod_art) cod,
         coalesce(c.descripcion, (select max(descripcion) from articulo_prov_at ap
                                   where ap.cod_art = r.cod_art)) descr,
         s.nombre sector, c.unidad_medida um, c.uni_x_cajon uxc, c.kg_x_uni kgu,
         c.entrega_unidad ent_uni, c.entrega_uni_x ent_ux, c.remito_unidad remito_uni,
         ce.codigo ent_cod, ce.descripcion ent_desc,
         -- el CAJON DE LA PIEZA ENVIADA, SOLO donde la pieza vuelve en el MISMO cajon en el que se
         -- mando: hoy los REMACHES que niquela Guazzaroni (sector 8). El esperado de un P.S. se
         -- cuenta en unidades de la ENTRADA (es lo que el proveedor tiene en su poder), asi que ahi
         -- el envase con el que se mira tiene que ser el de ESA pieza y no el de la que devuelve
         -- [usuario 2026-09-18: "Guazzaroni nos entrega los remaches niquelados en los mismos
         -- cajones que se lo enviamos... si envio 2 cajones lo esperado es recibir 2 cajones aprox
         -- (el peso niquelado es un poquito mas - muy infima la diferencia)", y enseguida el limite:
         -- "no aplica para todos los casos... te lo estoy diciendo en el caso de los remaches"].
         -- El uni_x_cajon del remache niquelado (V11 = 2.729 uni = 2 kg) NO es un cajon: es la bolsa
         -- en la que se fracciona DESPUES de recibirlo, con la matriz de embolsado. Mirar el
         -- esperado con ese numero multiplicaba por 10 lo que se le habia mandado.
         -- NULL en el resto de los P.S.: ahi el front sigue con el cajon de la pieza devuelta.
         case when ce.sector_id = 8 then ce.uni_x_cajon end ent_uxc,
         case when ce.sector_id = 8 then ce.kg_x_uni    end ent_kgu,
         -- ...Y CUANTO MIDE ESE CAJON DE VERDAD (2026-09-21): el que anoto logistica al enviar
         -- (movimiento.cajones), no el uni_x_cajon del maestro. CV1 salio como 1 cajon de 21 kg
         -- contra un cajon teorico de 20 kg y la tarjeta de Recibir decia 1,05 cajones [usuario:
         -- "tiene que aparecer en su stock los cajones que escribe logistica, no los que se
         -- calcula a partir de los kg"]. Va SOLO donde ya va ent_uxc (P.S. y sector Remache), que
         -- es donde el front mira el envase de la pieza ENVIADA; null = nadie anoto cajones y
         -- queda el de siempre.
         max(case when ce.sector_id = 8 and r.tipo = 'proveedor_servicio'
                  then (select v.uni_x_cajon_anotado from v_caj_contraparte v
                         where v.componente_id = r.comp_entrada_id
                           and v.ubicacion_id = ubic_de(r.tipo, r.ref::bigint)) end) ent_uxc_anot,
         (select a.articulos_por_caja from articulo a where a.codigo = r.cod_art) por_caja
    from rec r
    left join componente c on c.id = r.comp_id
    left join componente ce on ce.id = r.comp_entrada_id
    left join sector s on s.id = c.sector_id
   where (r.comp_id is null or not coalesce(c.discontinuado,false))
     and (r.comp_id is null or r.comp_id not in (select comp_id from "GP2".v_componente_muerto))
   group by r.tipo, r.ref, r.comp_id, r.comp_entrada_id, r.n_entradas, r.tiene_bom, r.cod_art,
            c.codigo, c.descripcion, s.nombre, c.unidad_medida, c.uni_x_cajon, c.kg_x_uni,
            c.entrega_unidad, c.entrega_uni_x, c.remito_unidad,
            ce.codigo, ce.descripcion, ce.uni_x_cajon, ce.kg_x_uni, ce.sector_id
),
-- envio_unidad / envio_uni_x / envio_carga_unidad: unidad de ENVIO por proveedor (display), p.ej. AJ
-- Adhesivos manda de a paquetes de 100 pliegos y Ester de a bolsas de 1800 mangos. Es solo
-- presentacion: el front muestra/precarga el sugerido dividido por envio_uni_x (techo) y rotula la
-- columna con envio_unidad. envio_carga_unidad dice en QUE unidad se escribe la CANTIDAD: null = en
-- la unidad de envio (AJ escribe paquetes y el front multiplica de nuevo), 'kg' = se escribe en kg y
-- al lado se muestran las bolsas (Ester). En los dos casos lo que llega a la base esta en unidad
-- canonica (uni/kg): el inventario nunca ve bolsas ni paquetes. Hoy solo lo tiene
-- proveedor_servicio; el resto va null. [usuario 2026-09-17]
cp as (
  select 'tallerista'::text tipo, t.id::text ref, t.nombre, null::text envio_unidad, null::numeric envio_uni_x, null::text envio_carga_unidad, null::text entrega_unidad, null::numeric entrega_uni_x
    from tallerista t
   where t.activo and t.id <> 3
     and exists (select 1 from v_contraparte_parte v where v.tipo='tallerista' and v.ref_id = t.id)
  union all
  select 'proveedor_servicio', ps.id::text, ps.nombre, ps.envio_unidad, ps.envio_uni_x, ps.envio_carga_unidad, ps.entrega_unidad, ps.entrega_uni_x
    from proveedor_servicio ps
   where exists (select 1 from v_contraparte_parte v where v.tipo='proveedor_servicio' and v.ref_id = ps.id)
  union all
  select 'proveedor_at', p.id::text, p.nombre, null::text, null::numeric, null::text, null::text, null::numeric
    from proveedor_at p where coalesce(p.activo,true)
  union all
  select distinct 'proveedor_insumo', o.proveedor, o.proveedor, null::text, null::numeric, null::text, null::text, null::numeric
    from orden_compra o where o.estado in ('borrador','enviada')
  union all
  select 'virgilio', 'virgilio', 'Virgilio', null::text, null::numeric, null::text, null::text, null::numeric
  union all
  select distinct 'inyector', c.proveedor, c.proveedor, null::text, null::numeric, null::text, null::text, null::numeric
    from componente c
   where c.material_id is not null and c.estado_compra is null and c.proveedor is not null
     and exists (select 1 from proveedor_insumo pi where pi.nombre = c.proveedor)
)
select jsonb_build_object(
  'generado_en', now(),
  'contrapartes', (
    select coalesce(jsonb_agg(jsonb_build_object(
             'tipo', cp.tipo, 'ref', cp.ref, 'nombre', cp.nombre,
             -- O.C. DE GESTION VIRGILIO (2026-09-23): a este tallerista no se le manda contra el
             -- maximo de la casa; lo que tiene que hacer sale de una O.C. que emite Gestion
             -- Virgilio y que GP2 todavia no lee. La Tablet lo muestra en su propia baldosa
             -- ("Talleristas O.C.", solo en Enviar) y su sugerido es 0 (ver la CTE t) [usuario].
             'oc', (cp.tipo = 'tallerista' and exists (select 1 from tallerista t9
                      where t9.id = cp.ref::bigint and t9.pedido_por_oc_virgilio)),
             'envio_unidad', cp.envio_unidad, 'envio_uni_x', cp.envio_uni_x,
             'entrega_unidad', cp.entrega_unidad, 'entrega_uni_x', cp.entrega_uni_x,
             'envio_carga_unidad', cp.envio_carga_unidad,
             'n_env', (select count(*) from env_x e where e.tipo = cp.tipo and e.ref = cp.ref),
             'n_rec', (select count(*) from rec_x r where r.tipo = cp.tipo and r.ref = cp.ref)
           ) order by cp.nombre), '[]'::jsonb)
      from cp where cp.nombre is not null),
  'enviar', (
    select coalesce(jsonb_agg(jsonb_build_object(
             'tipo', tipo, 'ref', ref, 'comp_id', comp_id, 'cod', cod, 'desc', descr,
             'sector', sector, 'um', um, 'uxc', uxc, 'kg_x_uni', kgu,
             'env_unidad', case when tipo in ('tallerista','proveedor_at')
                                  then case when sec_id in (10,11) then coalesce(nullif(btrim(ent_uni),''), 'paquetes')
                                            else coalesce(nullif(btrim(ent_uni),''), 'cajones') end end,
             'env_factor', case when tipo in ('tallerista','proveedor_at') then case
                                  when sec_id = 10 then nullif(ent_ux,0)
                                  when sec_id = 11 then (select pa.valor::numeric from parametro pa
                                                          where pa.clave = 'caja_uni_x_paquete')
                                  else coalesce(nullif(ent_ux,0), uxc) end end,
             'env_carga',  case when tipo in ('tallerista','proveedor_at')
                                  then coalesce(env_carga_pieza,
                                         case when sec_id in (10,11) then 'envase' else 'kg' end) end,
             'online_sector', online_sector, 'saldo_dest', saldo_dest,
             'maximo', maximo_dest, 'stock_dest', stock_dest, 'sugerido', sugerido
           ) order by cod), '[]'::jsonb) from env_x),
  'recibir', (
    select coalesce(jsonb_agg(jsonb_build_object(
             'tipo', tipo, 'ref', ref, 'comp_id', comp_id, 'comp_entrada_id', comp_entrada_id,
             'n_entradas', n_entradas, 'tiene_bom', tiene_bom,
             'cod_art', cod_art, 'cod', cod, 'desc', descr, 'sector', sector, 'um', um,
             'uxc', uxc, 'kg_x_uni', kgu, 'por_caja', por_caja,
             -- LA UNIDAD DEL REMITO LA DICE LA PIEZA (componente.remito_unidad): las bombillas de
             -- Martin vienen contadas y la cuchilla pesada [usuario 2026-09-23]. Sin dato, la
             -- Tablet usa la unidad canonica.
             'remito_unidad', remito_uni,
             -- envase de ENTREGA (hoy solo el tallerista): el esperado se mira en cajones (o en las
             -- bolsas de 120 de GRJ5/GRJ6) y la cantidad se escribe en kg.
             'env_unidad', case when tipo = 'tallerista' then coalesce(ent_uni, 'cajones') end,
             'env_factor', case when tipo = 'tallerista' then coalesce(ent_ux, uxc) end,
             'env_carga',  case when tipo = 'tallerista' then 'kg' end,
             'ent_cod', ent_cod, 'ent_desc', ent_desc, 'ent_uxc_anot', ent_uxc_anot,
             'ent_uxc', ent_uxc, 'ent_kgu', ent_kgu,
             'esperado', esperado, 'esperado_origen', esperado_origen
           ) order by cod), '[]'::jsonb) from rec_x),
  'alertas_abiertas', (select count(*) from alerta_recepcion where estado = 'abierta')
);
$function$
;

-- ---------- tablet_registrar ----------
CREATE OR REPLACE FUNCTION "GP2".tablet_registrar(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
declare
  v_modo   text := lower(coalesce(p->>'modo',''));
  v_tipo   text := lower(coalesce(p->>'tipo',''));
  v_ref    text := nullif(btrim(coalesce(p->>'ref','')),'');
  v_nom    text;
  v_fecha  timestamptz := coalesce((p->>'fecha')::timestamptz, now());
  v_remito text := nullif(btrim(coalesce(p->>'remito','')),'');
  it       jsonb;
  v_comp   bigint; v_ent bigint; v_cant numeric; v_uni text; v_esp numeric;
  v_cod    text; v_desc text; v_cod_art text; v_por_caja numeric; v_cajones numeric;
  v_sust   bigint;
  v_r      jsonb; v_res jsonb := '[]'::jsonb; v_alertas jsonb := '[]'::jsonb;
  v_comparable numeric; v_alerta_id bigint; v_n int := 0;
  v_ubic_o bigint; v_ubic_d bigint; v_sec bigint; v_um text; v_mov bigint;
begin
  perform "GP2"._exigir_autorizado();  -- seguridad punto 1 fase B (2026-09-28)
  if v_modo not in ('enviar','recibir') then
    raise exception 'Modo invalido: "%". Tiene que ser enviar o recibir.', coalesce(v_modo,'null');
  end if;
  if v_ref is null then raise exception 'Falta decir a quien (ref).'; end if;
  if jsonb_typeof(p->'items') <> 'array' or jsonb_array_length(p->'items') = 0 then
    raise exception 'No hay nada cargado para registrar.';
  end if;

  v_nom := case v_tipo
    when 'tallerista'         then (select nombre from tallerista where id = v_ref::bigint)
    when 'proveedor_servicio' then (select nombre from proveedor_servicio where id = v_ref::bigint)
    when 'proveedor_at'       then (select nombre from proveedor_at where id = v_ref::bigint)
    when 'proveedor_insumo'   then v_ref
    when 'inyector'           then (select nombre from proveedor_insumo where nombre = v_ref)
    when 'virgilio'           then 'Virgilio'
  end;
  if v_nom is null then
    raise exception 'Contraparte inexistente (tipo=%, ref=%).', coalesce(v_tipo,'null'), v_ref;
  end if;
  if v_modo = 'enviar' and v_tipo not in ('tallerista','proveedor_servicio','proveedor_at','inyector') then
    raise exception 'A "%" no se le envia desde la tablet: solo talleristas, prov. de servicio, prov. art. terminado e inyectores.', v_nom;
  end if;

  for it in select value from jsonb_array_elements(p->'items') loop
    v_comp     := nullif(it->>'comp_id','')::bigint;
    v_ent      := nullif(it->>'comp_entrada_id','')::bigint;
    v_cod_art  := nullif(btrim(coalesce(it->>'cod_art','')),'');
    v_cant     := nullif(it->>'cantidad','')::numeric;
    v_uni      := lower(coalesce(nullif(it->>'unidad',''), 'uni'));
    v_esp      := nullif(it->>'esperado','')::numeric;
    v_por_caja := nullif(it->>'por_caja','')::numeric;
    -- carton de OTRO articulo mandado en lugar del que corresponde (2026-09-21): viaja el carton
    -- OFICIAL al que reemplaza. Lo valida crear_envio_* (mismo sector, y que sea pieza del destino).
    v_sust     := nullif(it->>'sustituye_comp_id','')::bigint;
    v_cajones  := nullif(it->>'cajones','')::numeric;
    if v_uni not in ('uni','kg') then raise exception 'Unidad invalida: "%"', v_uni; end if;
    if v_cant is null or v_cant <= 0 then
      raise exception '% : la cantidad tiene que ser mayor a 0.', coalesce(v_cod_art, v_comp::text, '?');
    end if;
    if v_sust is not null and (v_modo <> 'enviar' or v_tipo not in ('tallerista','proveedor_at')) then
      raise exception 'El reemplazo de carton solo existe al ENVIAR a un tallerista o a un prov. de art. terminado.';
    end if;
    select codigo, descripcion into v_cod, v_desc from componente where id = v_comp;
    v_cod := coalesce(v_cod, v_cod_art);

    if v_modo = 'enviar' then
      if v_tipo = 'tallerista' then
        v_r := "GP2".crear_envio_tallerista(v_ref::bigint, v_comp, v_cant, v_uni, v_fecha, v_sust);
      elsif v_tipo = 'proveedor_servicio' then
        v_r := "GP2".crear_envio_ps(v_ref::bigint, v_comp, v_cant, v_uni, v_fecha, v_cajones);
      elsif v_tipo = 'inyector' then
        v_r := "GP2".enviar_material_inyector(v_ref, v_comp, v_cant, v_fecha);
      else
        v_r := "GP2".crear_envio_prov_at(v_ref::bigint, v_comp, v_cant, v_uni, v_fecha, v_sust);
      end if;
      v_comparable := null;
    else
      if v_tipo = 'tallerista' then
        v_r := "GP2".crear_entrega_tallerista(v_ref::bigint, v_comp, v_cant, v_uni, v_fecha, true, v_ent);
      elsif v_tipo = 'proveedor_servicio' then
        if v_ent is null then
          raise exception '% : falta saber que SC consume ese SP (comp_entrada_id).', coalesce(v_cod,'?');
        end if;
        v_r := "GP2".crear_entrega_ps(v_ref::bigint, v_ent, v_comp, v_cant, v_fecha, null, false, v_uni);
      elsif v_tipo = 'proveedor_at' then
        if v_cod_art is null then raise exception 'Falta el codigo de articulo del prov. art. terminado.'; end if;
        v_r := "GP2".crear_entrega_prov_at(v_ref::bigint, v_cod_art, v_cant::int, v_remito, v_fecha::date);
      elsif v_tipo = 'proveedor_insumo' then
        v_r := "GP2".crear_recepcion_insumo(v_comp, v_ref, v_cant, v_uni, v_remito, v_fecha);
      else
        select sector_id, unidad_medida into v_sec, v_um from componente where id = v_comp;
        if v_sec is null then raise exception 'El componente % no existe', v_comp; end if;
        v_ubic_d := "GP2".ubic_de('sector', v_sec);
        v_ubic_o := coalesce(
          (select i.ubicacion_id from inventario i
             join ubicacion u on u.id = i.ubicacion_id
            where i.componente_id = v_comp and u.tipo in ('virgilio_sector','virgilio') and i.cantidad > 0
            order by case when u.tipo = 'virgilio_sector' then 0 else 1 end limit 1),
          "GP2".ubic_de('virgilio_sector', v_sec),
          (select id from ubicacion where tipo = 'virgilio' limit 1));
        if v_ubic_o is null or v_ubic_d is null then
          raise exception '% : falta la ubicacion de Virgilio o la del sector destino.', coalesce(v_cod,'?');
        end if;
        insert into movimiento(fecha, tipo_mov, comp_id, ubic_origen_id, ubic_destino_id,
                               cantidad, unidad_origen, unidad_destino, nota)
        values (v_fecha, 'traslado', v_comp, v_ubic_o, v_ubic_d, v_cant, v_uni, v_uni,
                'Recibido de Virgilio (tablet)')
        returning id into v_mov;
        v_r := jsonb_build_object('ok', true, 'movimiento_id', v_mov);
      end if;
    end if;

    v_n := v_n + 1;
    v_res := v_res || jsonb_build_object('cod', v_cod, 'cantidad', v_cant, 'unidad', v_uni, 'res', v_r);

    if v_modo = 'recibir' and v_esp is not null then
      v_comparable := case when v_tipo = 'proveedor_at'
                           then v_cant * coalesce(nullif(v_por_caja,0), 1) else v_cant end;
      -- LA ALERTA NO SALTA POR UN DECIMAL [usuario 2026-09-23: "por que salta la alerta? es
      -- exactamente la misma cantidad", con 1.852 uni contra 1.852 esperadas]. El saldo que el
      -- tercero tiene en su poder arrastra decimales de las conversiones kg <-> uni (10 kg de mango
      -- son 1.851,8518 uni), asi que comparar crudo anota una alerta por cada redondeo. Media
      -- unidad, o 5 gramos si la pieza se mide en kg: nadie entrega 0,15 mangos. La MISMA
      -- tolerancia vive en exceso() de la Tablet, que es el cartel que ve el operario.
      -- El case va ENTRE PARENTESIS a proposito: sin eso plpgsql corta la condicion del IF en el
      -- primer THEN que encuentra, que seria el del case, y la funcion no compila.
      -- Y NO SE COMPARA CONTRA EL STOCK DE UN P.S. [usuario 2026-09-23: "esta alerta me tiene
      -- que aparecer no a la hora de recibir, sino a la hora de hacer el control... porque puede
      -- haber 1.800 unidades de stock de proveedor de servicio y capaz recibo menos"]: lo que se
      -- carga aca es el REMITO y una entrega parcial es lo normal. Esa comparacion vive en
      -- ControlEntregaPS, contra el remito. En los demas destinos el aviso queda, pero recien
      -- arriba del 5 % (el mismo umbral que pidio para el control), con el piso de media unidad
      -- -5 gramos en kg- que cubre el caso de esperado 0.
      if v_tipo <> 'proveedor_servicio'
         and v_comparable > v_esp + greatest(
               (case when lower(coalesce(v_uni,'')) = 'kg' then 0.005 else 0.5 end),
               v_esp * 0.05) then
        insert into alerta_recepcion(fecha, origen_tipo, origen_ref, origen_nombre, comp_id, cod,
                                     descripcion, esperado, recibido, exceso, unidad, esperado_origen,
                                     movimiento_id)
        values (v_fecha, v_tipo, v_ref, v_nom, v_comp, v_cod, coalesce(v_desc, v_cod_art),
                v_esp, v_comparable, v_comparable - v_esp, v_uni,
                nullif(it->>'esperado_origen',''),
                coalesce((v_r->>'movimiento_id')::bigint, (v_r->>'id')::bigint))
        returning id into v_alerta_id;
        v_alertas := v_alertas || jsonb_build_object('id', v_alerta_id, 'cod', v_cod,
                       'esperado', v_esp, 'recibido', v_comparable, 'exceso', v_comparable - v_esp);
      end if;
    end if;
  end loop;

  return jsonb_build_object('ok', true, 'n', v_n, 'contraparte', v_nom, 'modo', v_modo,
                            'items', v_res, 'alertas', v_alertas);
end $function$
;

-- ---------- talleristas_bundle ----------
CREATE OR REPLACE FUNCTION "GP2".talleristas_bundle()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
with ub as (
  select t.id tall_id, u.ubic_id
    from tallerista t
    join lateral (select "GP2".ubic_de('tallerista', t.id) ubic_id) u on u.ubic_id is not null
),
cfg as (
  select rp.tallerista_id, cc.comp_id, cc.lado
    from ruta_paso rp
    join ruta r on r.id = rp.ruta_id
    join articulo a on a.id = r.articulo_id and not coalesce(a.discontinuado, false)
    cross join lateral (values (rp.comp_entrada_id,'entrada'),(rp.comp_salida_id,'salida')) cc(comp_id,lado)
   where rp.tipo_paso = 'tallerista' and rp.tallerista_id is not null and cc.comp_id is not null
   group by rp.tallerista_id, cc.comp_id, cc.lado
),
mov as (
  select u.tall_id, m.comp_id,
         sum(case when m.tipo_mov='envio_tallerista' then coalesce(m._delta_dest,0) else 0 end) enviado,
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
         c.unidad_medida um, c.kg_x_uni, c.uni_x_cajon, c.entrega_unidad, c.entrega_uni_x,
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
                        'entrega_unidad',entrega_unidad,'entrega_uni_x',entrega_uni_x,
                        'online_tall',online_tall,'online_sector',online_sector,
                        'enviado',enviado,'entregado',entregado,'devuelto',devuelto,
                        'saldo',(enviado-entregado-devuelto)
                      ) j
                 from fila) z2
        group by tallerista_id) y)
);
$function$
;

-- ---------- texto_norm ----------
CREATE OR REPLACE FUNCTION "GP2".texto_norm(p text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select nullif(lower(extensions.unaccent(regexp_replace(coalesce(p,''), '\s+', ' ', 'g'))), '');
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
  perform "GP2"._exigir_autorizado();  -- seguridad punto 1 fase B (2026-09-28)
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

-- ---------- traslado_virgilio ----------
CREATE OR REPLACE FUNCTION "GP2".traslado_virgilio(p_comp_id bigint, p_cantidad numeric, p_sentido text DEFAULT 'ida'::text, p_fecha timestamp with time zone DEFAULT now(), p_nota text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'GP2'
AS $function$
declare v_sec bigint; v_um text; v_cerv bigint; v_virg bigint; v_mov bigint; v_u text;
begin
  perform "GP2"._exigir_autorizado();  -- seguridad punto 1 fase B (2026-09-28)
  if p_cantidad is null or p_cantidad <= 0 then raise exception 'La cantidad debe ser mayor a 0'; end if;
  if p_sentido not in ('ida','vuelta') then raise exception 'p_sentido debe ser ida o vuelta'; end if;
  select sector_id, unidad_medida into v_sec, v_um from componente where id = p_comp_id;
  if v_sec is null then raise exception 'El componente % no existe', p_comp_id; end if;
  v_cerv := ubic_de('sector', v_sec);
  v_virg := ubic_de('virgilio_sector', v_sec);
  if v_virg is null then raise exception 'El sector % no tiene deposito en Virgilio (solo Crudo y Procesado)', v_sec; end if;
  v_u := case when lower(coalesce(v_um,'uni')) = 'kg' then 'kg' else 'uni' end;
  insert into movimiento(fecha, tipo_mov, comp_id, ubic_origen_id, ubic_destino_id, cantidad, unidad_origen, unidad_destino, nota)
  values (coalesce(p_fecha, now()), 'traslado', p_comp_id,
          case when p_sentido='ida' then v_cerv else v_virg end,
          case when p_sentido='ida' then v_virg else v_cerv end,
          p_cantidad, v_u, v_u, p_nota)
  returning id into v_mov;
  return jsonb_build_object('ok', true, 'movimiento_id', v_mov, 'sentido', p_sentido,
    'stock_cervantes', (select cantidad from inventario where componente_id=p_comp_id and ubicacion_id=v_cerv),
    'stock_virgilio',  (select cantidad from inventario where componente_id=p_comp_id and ubicacion_id=v_virg));
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
-- 'stock' es TODO lo que hay del componente, en cualquier ubicacion: es lo que se valoriza.
-- 'maximo' y 'pedido' salen de v_reposicion (la ubicacion donde el componente se repone), que es
-- la MISMA regla que usa la OC. Antes esta funcion sumaba el maximo de todas las ubicaciones y
-- restaba stocks negativos de talleristas/PS: 54 componentes no cerraban contra la pantalla de OC.
with inv as (
  select componente_id, sum(coalesce(cantidad,0)) stock
  from inventario group by componente_id
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
     'stock',coalesce(i.stock,0),
     'stock_repo',coalesce(r.cantidad,0),'ubic_repo',r.ubic_nombre,
     'maximo',coalesce(r.maximo,0),'pedido',coalesce(r.sugerido,0)
   ) order by cc.sector_id, cc.codigo),'[]'::jsonb)
   from "GP2".v_costo_componente cc
   left join inv i on i.componente_id = cc.comp_id
   left join "GP2".v_reposicion r on r.componente_id = cc.comp_id
   where cc.sector_tipo <> 'terminado'),
  'generado_en', now()
);
$function$
;
