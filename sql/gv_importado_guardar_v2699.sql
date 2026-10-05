-- v26.99 (Luis, 05/10/2026) — la solapa pasa a «Agregar o modificar producto» y el alta impacta en
-- TODOS los lugares de stock (D1 y D2 de la v26.98: "en página está bien que no, pero en stock y demás sí").
--
-- gv_importado_guardar(p jsonb): sin p.id = ALTA; con p.id = MODIFICAR ese artículo (Importados.id).
-- Lo que escribe, todo en una transacción:
--   Importados              descripción, FOB, uni × inner, MOQ, primer pedido (proveedor: todas las filas del código)
--   Importados_Volumen      uni × MC, uni × inner, medidas MC e inner, m³
--   GV_UxB                  la caja de venta (= inner; si viene suelto, la MC) por empresa, curado a mano
--   OC_Maximos              la fila del código con su línea (sin proveedor: un importado no se compra por OC)
--   GV_Producto_Tipo        tipo de producto y familia (agrupa el PDF de Damián)
--   GV_Articulo_INAL        si lleva INAL, certificado y vencimiento (base de la Autorización de Impo)
--   GV_Lugar_Item           su góndola y capacidad (vía gv_lugar_item_guardar, que valida el lugar)
--   Equivalencias_Familia   si es secundario de otro código
--   Movimientos_Stock       en el ALTA, un ajuste de 0 cajas en 'terminado' si el código no tiene ningún
--                           movimiento: Stocks arma su lista con lo que tiene movimientos o pedidos, y sin
--                           esa fila el artículo no aparece hasta que llega.
-- Empresa de stock: LK y Loke → LK · CH → CH · Mixto (insumo) → sin UxB, tipo ni movimiento.
--
-- gv_importado_ficha(p_id) devuelve lo que hay cargado de un artículo (para modificar) y las listas de
-- tipos y familias. gv_importado_alta(jsonb) (v26.98) queda como envoltorio de guardar.
--
-- Rollback: volver gv_importado_alta a la versión de sql/gv_importado_alta_v2698.sql y
--   drop function public.gv_importado_guardar(jsonb); drop function public.gv_importado_ficha(bigint);

create or replace function public.gv_importado_guardar(p jsonb)
returns jsonb language plpgsql security definer set search_path to 'public' as $f$
-- v26.99-guardar-imp
declare
  v_id   bigint := nullif(p->>'id','')::bigint;
  v_cod  text := upper(btrim(coalesce(p->>'cod','')));
  v_marca text := btrim(coalesce(p->>'marca',''));
  v_prov text := btrim(coalesce(p->>'proveedor',''));
  v_desc text := btrim(coalesce(p->>'descripcion',''));
  v_fob  numeric := nullif(p->>'fob','')::numeric;
  v_um   numeric := nullif(p->>'uni_mc','')::numeric;
  v_ui   numeric := nullif(p->>'uni_inner','')::numeric;
  v_moq  numeric := nullif(p->>'moq','')::numeric;
  v_ped  numeric := nullif(p->>'primer_pedido_u','')::numeric;
  v_ml numeric := nullif(p->>'mc_largo','')::numeric;  v_ma numeric := nullif(p->>'mc_ancho','')::numeric;  v_mh numeric := nullif(p->>'mc_alto','')::numeric;
  v_il numeric := nullif(p->>'in_largo','')::numeric;  v_ia numeric := nullif(p->>'in_ancho','')::numeric;  v_ih numeric := nullif(p->>'in_alto','')::numeric;
  v_tipo text := nullif(btrim(coalesce(p->>'tipo','')),'');
  v_fam  text := nullif(btrim(coalesce(p->>'familia','')),'');
  v_inal boolean := coalesce((p->>'inal')::boolean, false);
  v_icert text := nullif(btrim(coalesce(p->>'inal_certificado','')),'');
  v_ivence date := nullif(p->>'inal_vence','')::date;
  v_gsec text := nullif(upper(btrim(coalesce(p->>'gondola_sector',''))),'');
  v_gcap numeric := nullif(p->>'gondola_cap','')::numeric;
  v_sec_de text := nullif(upper(btrim(coalesce(p->>'secundario_de',''))),'');
  v_por text := coalesce(nullif(btrim(p->>'por'),''), auth.jwt()->>'email', 'gestion');
  v_simular boolean := coalesce((p->>'simular')::boolean, false);
  v_canon text; v_m3 numeric; v_m3i numeric; v_m3c numeric; v_emp text; v_tmarca text; v_uxb numeric;
  v_alta boolean := v_id is null; v_mov boolean := false; v_hechos text[] := '{}';
  v_old record;
begin
  if not public.es_supervisor_virgilio() then raise exception 'SUPERVISOR: sólo un supervisor logueado puede guardar un importado'; end if;
  if not v_alta then
    select * into v_old from public."Importados" where id = v_id;
    if not found then raise exception 'NO EXISTE: el artículo % no está en el maestro', v_id; end if;
    v_cod := upper(btrim(v_old.cod_art)); v_marca := v_old.marca;   -- código y empresa no se cambian al modificar
  end if;
  if v_cod = '' then raise exception 'FALTA: el código'; end if;
  if v_marca not in ('LK','CH','Loke','Mixto') then raise exception 'FALTA: la empresa (LK, CH, Loke o Mixto)'; end if;
  if v_prov = '' then raise exception 'FALTA: el proveedor'; end if;
  if v_desc = '' then raise exception 'FALTA: la descripción'; end if;
  if v_fob is null or v_fob <= 0 then raise exception 'FALTA: el FOB (u$s por unidad, mayor a 0)'; end if;
  if v_um is null or v_um <= 0 then raise exception 'FALTA: las unidades por master caja'; end if;
  if v_ui is null or v_ui < 0 then raise exception 'FALTA: las unidades por inner (0 = viene suelto)'; end if;
  if v_ui > 0 and mod(v_um, v_ui) <> 0 then raise exception 'NO CIERRA: % u por MC no es múltiplo de % u por inner', v_um, v_ui; end if;
  if v_moq is not null and v_moq < 0 then raise exception 'NO CIERRA: el MOQ no puede ser negativo'; end if;
  if v_ped is not null and v_ped < 0 then raise exception 'NO CIERRA: el primer pedido no puede ser negativo'; end if;
  if v_ped is not null and mod(v_ped, v_um) <> 0 then raise exception 'NO CIERRA: el primer pedido (% u) tiene que ser master cajas enteras de % u', v_ped, v_um; end if;
  if v_gcap is not null and v_gcap < 0 then raise exception 'NO CIERRA: la capacidad de góndola no puede ser negativa'; end if;
  if v_gcap is not null and v_gsec is null then raise exception 'FALTA: la góndola de esa capacidad'; end if;

  v_canon := public.canon_cod_art_val(v_cod);
  if v_alta and exists (select 1 from public."Importados" where upper(btrim(cod_art)) = upper(v_canon) and coalesce(marca,'') = v_marca) then
    raise exception 'YA_EXISTE: el % de % ya está en el maestro de importados (usá Modificar)', v_canon, v_marca;
  end if;
  if v_gsec is not null and not exists (select 1 from public."GV_Lugar" l where upper(btrim(l.sector)) = v_gsec) then
    raise exception 'NO EXISTE: la góndola % no está en el Mapa', v_gsec;
  end if;
  if v_gsec is not null and v_marca <> 'Mixto' and exists (select 1 from public."GV_Lugar" l where upper(btrim(l.sector)) = v_gsec
        and (l.tipo <> 'gondola' or l.empresa <> case v_marca when 'CH' then 'CH' else 'LK' end)) then
    raise exception 'NO CIERRA: % no es una góndola de % (la empresa del artículo en stock la da su góndola)', v_gsec, case v_marca when 'CH' then 'CH' else 'LK' end;
  end if;
  if v_sec_de is not null then
    v_sec_de := public.canon_cod_art_val(v_sec_de);
    if upper(v_sec_de) = upper(v_canon) then raise exception 'NO CIERRA: un código no puede ser secundario de sí mismo'; end if;
    if not public.gv_stock_cod_conocido(v_sec_de) then raise exception 'NO EXISTE: el principal % no es un código conocido', v_sec_de; end if;
  end if;

  v_emp := case v_marca when 'CH' then 'CH' when 'Mixto' then null else 'LK' end;
  v_tmarca := case v_marca when 'CH' then 'CH' when 'Loke' then 'LOKE' when 'LK' then 'LK' end;
  v_uxb := case when v_ui > 0 then v_ui else v_um end;
  v_m3  := case when v_ml > 0 and v_ma > 0 and v_mh > 0 then round(v_ml*v_ma*v_mh/1000000.0, 6) end;
  v_m3i := case when v_il > 0 and v_ia > 0 and v_ih > 0 then round(v_il*v_ia*v_ih/1000000.0, 6) end;
  v_mov := v_alta and v_emp is not null and not exists (select 1 from public."Movimientos_Stock" m where upper(btrim(m.cod_art)) = upper(v_canon));

  if v_simular then
    return jsonb_build_object('ok', true, 'simular', true, 'alta', v_alta, 'cod', v_canon, 'm3_master', v_m3, 'm3_inner', v_m3i, 'empresa_stock', v_emp, 'mov_alta', v_mov);
  end if;

  -- Importados
  if v_alta then
    insert into public."Importados" (cod_art, marca, proveedor, descripcion, fob_uni, uni_x_caja, moq, pedido_manual,
                                     principal, activo, notas, creado, actualizado)
    values (v_canon, v_marca, v_prov, v_desc, v_fob, nullif(v_ui,0), v_moq, nullif(v_ped,0), true, true,
            'Alta desde Gestión (➕ Agregar producto) · ' || v_por || ' · ' ||
            to_char(now() at time zone 'America/Argentina/Buenos_Aires','DD/MM/YY HH24:MI'), now(), now())
    returning id into v_id;
  else
    update public."Importados" set descripcion = v_desc, fob_uni = v_fob, uni_x_caja = nullif(v_ui,0), moq = v_moq,
           pedido_manual = nullif(v_ped,0), actualizado = now() where id = v_id;
  end if;
  update public."Importados" set proveedor = v_prov, actualizado = now()
   where upper(btrim(cod_art)) = upper(v_canon) and coalesce(proveedor,'') <> v_prov;
  v_hechos := array_append(v_hechos, 'maestro');

  -- Importados_Volumen
  insert into public."Importados_Volumen" (cod, largo_cm, ancho_cm, alto_cm, m3_master, uni_master, uni_inner,
                                           inner_largo_cm, inner_ancho_cm, inner_alto_cm, m3_inner, fuente, actualizado)
  values (v_canon, v_ml, v_ma, v_mh, v_m3, v_um, v_ui, v_il, v_ia, v_ih, v_m3i, 'Gestión ' || v_por, now())
  on conflict (cod) do update set largo_cm = excluded.largo_cm, ancho_cm = excluded.ancho_cm, alto_cm = excluded.alto_cm,
    m3_master = excluded.m3_master, uni_master = excluded.uni_master, uni_inner = excluded.uni_inner,
    inner_largo_cm = excluded.inner_largo_cm, inner_ancho_cm = excluded.inner_ancho_cm, inner_alto_cm = excluded.inner_alto_cm,
    m3_inner = excluded.m3_inner, fuente = excluded.fuente, actualizado = now();
  v_hechos := array_append(v_hechos, 'volumen');

  -- m³ de la CAJA DE VENTA (= el inner; suelto = la MC) para la PPP (vista_volumen_articulo_resuelto):
  -- medido el inner, ése; si no, la MC repartida en sus inner. En un código que ya tiene m³ sólo se pisa
  -- si se midió el inner (no se cambia el m³ de la PPP con una cuenta).
  v_m3c := coalesce(v_m3i, case when v_m3 is not null then round(v_m3 / (v_um / v_uxb), 5) end);
  if v_m3c > 0 and (v_m3i is not null or not exists (select 1 from public.vista_volumen_articulo_resuelto r where upper(r.codigo) = upper(v_canon))) then
    insert into public."GV_Volumen_Articulos" (codigo, m3, motivo, creado)
    values (v_canon, v_m3c, 'importados (' || case when v_m3i is not null then 'inner medido' else 'MC / inner' end || ') · ' || v_por, now())
    on conflict (codigo) do update set m3 = excluded.m3, motivo = excluded.motivo, creado = now();
    v_hechos := array_append(v_hechos, 'm3');
  end if;

  if v_emp is not null then
    -- GV_UxB: la caja de venta del stock
    insert into public."GV_UxB" (empresa, cod, uxb, descripcion, origen, actualizado, curado)
    values (v_emp, v_canon, v_uxb, v_desc, 'importados_' || v_por, now(), true)
    on conflict (empresa, cod) do update set uxb = excluded.uxb, descripcion = excluded.descripcion,
      origen = excluded.origen, actualizado = now(), curado = true;
    -- OC_Maximos: la fila del código con su línea (un importado no lleva proveedor de OC)
    insert into public."OC_Maximos" (cod, descripcion, linea, max_cajas, activo, actualizado, indice, llenar_gondola)
    values (v_canon, v_desc, v_emp, 0, true, now(), 1.5, false)
    on conflict (cod, linea) do update set descripcion = excluded.descripcion, actualizado = now();
    v_hechos := v_hechos || array['uxb','oc'];
  end if;

  -- tipo de producto
  if v_tipo is not null and v_tmarca is not null then
    insert into public."GV_Producto_Tipo" (marca, cod, tipo, familia, cargado_en)
    values (v_tmarca, v_canon, v_tipo, v_fam, now())
    on conflict (marca, cod) do update set tipo = excluded.tipo, familia = excluded.familia, cargado_en = now();
    v_hechos := array_append(v_hechos, 'tipo');
  end if;

  -- INAL: marcado = fila (con su certificado); desmarcado = se saca la fila de ESTE código
  if v_inal then
    insert into public."GV_Articulo_INAL" (codigo, marca, descripcion, importador, certificado, vence, cargado_en)
    values (v_canon, v_marca, v_desc, (select importador from public.gv_imp_proveedor_cfg where proveedor = v_prov limit 1), v_icert, v_ivence, now())
    on conflict (codigo) do update set certificado = coalesce(excluded.certificado, "GV_Articulo_INAL".certificado),
      vence = coalesce(excluded.vence, "GV_Articulo_INAL".vence), descripcion = excluded.descripcion, cargado_en = now();
    v_hechos := array_append(v_hechos, 'inal');
  elsif not v_alta then
    delete from public."GV_Articulo_INAL" where upper(btrim(codigo)) = upper(v_canon);
  end if;

  -- góndola
  if v_gsec is not null then
    perform public.gv_lugar_item_guardar(v_gsec, v_canon, 'articulo', v_gcap);
    v_hechos := array_append(v_hechos, 'gondola');
  end if;

  -- familia: secundario de
  if v_sec_de is not null then
    insert into public."Equivalencias_Familia" (cod_secundario, cod_principal, empresa, descripcion, actualizado_en)
    values (v_canon, v_sec_de, v_emp, v_desc, now())
    on conflict (cod_secundario) do update set cod_principal = excluded.cod_principal, empresa = excluded.empresa, actualizado_en = now();
    v_hechos := array_append(v_hechos, 'familia');
  elsif not v_alta and coalesce((p->>'secundario_de_quitar')::boolean, false) then
    delete from public."Equivalencias_Familia" where upper(btrim(cod_secundario)) = upper(v_canon);
  end if;

  -- Stocks: que aparezca antes de que llegue
  if v_mov then
    insert into public."Movimientos_Stock" (cod_art, descripcion, deposito, delta, tipo, ref, legajo, empresa, client_id)
    values (v_canon, v_desc,   -- la descripción del movimiento es la que muestra Stocks
            'terminado', 0, 'ajuste', 'ALTA IMP ' || v_canon, 'sup:' || v_por, v_emp, 'alta_imp_' || v_canon || '_' || v_emp);
    v_hechos := array_append(v_hechos, 'stock');
  end if;

  return jsonb_build_object('ok', true, 'alta', v_alta, 'id', v_id, 'cod', v_canon, 'm3_master', v_m3, 'm3_inner', v_m3i, 'hechos', to_jsonb(v_hechos));
end $f$;

create or replace function public.gv_importado_ficha(p_id bigint default null)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $f$
-- v26.99-ficha-imp
declare v_cod text; v_marca text; v_art jsonb;
begin
  if not public.es_supervisor_virgilio() then raise exception 'SUPERVISOR: sólo un supervisor logueado'; end if;
  if p_id is not null then
    select upper(btrim(cod_art)), marca into v_cod, v_marca from public."Importados" where id = p_id;
    if v_cod is null then raise exception 'NO EXISTE: el artículo %', p_id; end if;
    select jsonb_build_object(
      'id', i.id, 'cod', i.cod_art, 'marca', i.marca, 'proveedor', i.proveedor, 'descripcion', i.descripcion,
      'fob', i.fob_uni, 'moq', i.moq, 'primer_pedido_u', i.pedido_manual, 'activo', i.activo,
      'uni_mc', v.uni_master, 'uni_inner', v.uni_inner,
      'mc_largo', v.largo_cm, 'mc_ancho', v.ancho_cm, 'mc_alto', v.alto_cm,
      'in_largo', v.inner_largo_cm, 'in_ancho', v.inner_ancho_cm, 'in_alto', v.inner_alto_cm,
      'tipo', x.tipo_producto, 'familia', x.familia, 'inal', coalesce(x.inal,false),
      'inal_certificado', x.inal_certificado, 'inal_vence', x.inal_vence,
      'inal_propio', exists(select 1 from public."GV_Articulo_INAL" a where upper(btrim(a.codigo)) = v_cod),
      'secundario_de', (select cod_principal from public."Equivalencias_Familia" e where upper(btrim(e.cod_secundario)) = v_cod),
      'gondolas', (select jsonb_agg(jsonb_build_object('sector', l.sector, 'cap', l.cajas_max) order by l.sector)
                     from public."GV_Lugar_Item" l where upper(btrim(l.cod)) = v_cod and l.activo and l.clase = 'articulo'),
      'en_curso', (select coalesce(sum(b.unidades - b.unidades_llegadas),0) from public."GV_Importados_Baches" b
                    where upper(btrim(b.cod_art)) = v_cod and b.estado = 'en_curso'))
      into v_art
      from public."Importados" i
      left join public."Importados_Volumen" v on upper(btrim(v.cod)) = v_cod
      left join public.gv_imp_articulo_extra x on x.cod_art = v_cod and upper(x.marca) = upper(i.marca)
     where i.id = p_id;
  end if;
  return jsonb_build_object('art', v_art,
    'tipos', (select jsonb_agg(t order by t) from (select distinct tipo t from public."GV_Producto_Tipo" where tipo is not null) z),
    'familias', (select jsonb_agg(f order by f) from (select distinct familia f from public."GV_Producto_Tipo" where familia is not null) z));
end $f$;

-- el alta de la v26.98 pasa a ser un envoltorio (mismos parámetros)
create or replace function public.gv_importado_alta(p jsonb)
returns jsonb language sql security definer set search_path to 'public' as $f$
  -- v26.99: envoltorio de gv_importado_guardar (alta = sin id). YA_EXISTE lo controla guardar.
  select public.gv_importado_guardar(p - 'id');
$f$;

revoke all on function public.gv_importado_guardar(jsonb) from public, anon;
grant execute on function public.gv_importado_guardar(jsonb) to authenticated;
revoke all on function public.gv_importado_ficha(bigint) from public, anon;
grant execute on function public.gv_importado_ficha(bigint) to authenticated;
revoke all on function public.gv_importado_alta(jsonb) from public, anon;
grant execute on function public.gv_importado_alta(jsonb) to authenticated;

-- centinelas (aplicado como CTE): id 333 pasó a objeto gv_importado_guardar (patrón YA_EXISTE);
-- 334 'ALTA IMP' (ajuste de 0 cajas para que figure en Stocks) · 335 'GV_UxB' (la caja de venta en Stocks)
