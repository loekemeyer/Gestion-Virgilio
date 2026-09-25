-- v22.82 (Luis, 25/09): el MAPA es el punto principal para definir qué hay en cada góndola / rack.
--   "hagamos que todas las definiciones de qué cosa hay en cada rack/góndola se puedan editar desde el apartado de
--    mapas … cambiarlo ahí informa a todos los demás" · "evitá choques con el stock: sería raro que Movimientos_Stock
--    diga que hay stock de un código pero ninguna góndola/rack lo tenga, debería salir una alerta en el módulo de mapa".
-- ROLLBACK: drop view public.gv_mapa_stock_sin_lugar; drop function public.gv_insumo_posicion_guardar(text,text,numeric,boolean,text,bigint);

-- insumos: poner / sacar / cambiar la cantidad de UN insumo en UNA posición del Mapa
create or replace function public.gv_insumo_posicion_guardar(p_sector text, p_cod text, p_cantidad numeric,
  p_quitar boolean default false, p_motivo text default null, p_reemplaza_id bigint default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_sec text := public.gv_rack_sector(p_sector); v_cod text; v_n int;
begin
  if not (public.es_supervisor_virgilio() or public.gv_es_supervisor_o_servicio()) then
    raise exception 'Sólo un supervisor puede cambiar dónde está un insumo.';
  end if;
  if v_sec is null then raise exception 'La posición % no existe en el Mapa.', coalesce(p_sector,'?'); end if;
  select i.cod into v_cod from public."Insumos" i where upper(btrim(i.cod)) = upper(btrim(coalesce(p_cod,''))) limit 1;
  -- quitar vale también para un código que no está en Insumos (quedaron 38 así, todos en 0): es sacar basura
  if p_quitar then
    delete from public."Insumos_Ubicaciones" where upper(btrim(cod)) = upper(btrim(coalesce(v_cod, p_cod, '')))
       and public.gv_rack_sector(sector) = v_sec;
    get diagnostics v_n = row_count;
    return jsonb_build_object('ok', true, 'cod', coalesce(v_cod, p_cod), 'sector', v_sec, 'quitado', v_n);
  end if;
  if v_cod is null then raise exception 'El insumo % no existe en el módulo de Insumos.', coalesce(p_cod,'?'); end if;
  if coalesce(p_cantidad,0) < 0 then raise exception 'La cantidad no puede ser negativa.'; end if;
  if p_reemplaza_id is not null then
    delete from public."Insumos_Ubicaciones" where id = p_reemplaza_id and upper(btrim(cod)) = upper(v_cod);
  end if;
  update public."Insumos_Ubicaciones" set sector = v_sec, cantidad = p_cantidad, updated_at = now(),
         notas = nullif(btrim(coalesce(p_motivo,'')),'')
   where upper(btrim(cod)) = upper(v_cod) and public.gv_rack_sector(sector) = v_sec;
  get diagnostics v_n = row_count;
  if v_n = 0 then
    insert into public."Insumos_Ubicaciones"(cod, sector, cantidad, notas, updated_at)
    values (v_cod, v_sec, p_cantidad, nullif(btrim(coalesce(p_motivo,'')),''), now());
  end if;
  return jsonb_build_object('ok', true, 'cod', v_cod, 'sector', v_sec, 'cantidad', p_cantidad);
end $$;
revoke all on function public.gv_insumo_posicion_guardar(text,text,numeric,boolean,text,bigint) from public, anon;
grant execute on function public.gv_insumo_posicion_guardar(text,text,numeric,boolean,text,bigint) to authenticated;

-- ALERTA: hay stock y ningún lugar del Mapa lo tiene
create or replace view public.gv_mapa_stock_sin_lugar with (security_invoker = true) as
select 'gondola'::text tipo, s.cod_base cod, s.linea emp, s.terminado cantidad, 'caj'::text unidad,
       'Hay ' || round(s.terminado) || ' cajas en góndola y ninguna celda del Mapa tiene el código' detalle, null::bigint ref_id
  from public.stocks_carga_rapida s
 where coalesce(s.terminado,0) > 0 and coalesce(s.visible_en_stock,true)
   and not exists (select 1 from public."GV_Lugar_Item" i join public."GV_Lugar" l on l.sector = i.sector and l.tipo = 'gondola'
                    where coalesce(i.activo,true) and public.gv_cod_stock(i.cod) = public.gv_cod_stock(s.cod_base))
union all
select 'rack', r.cod, r.emp, r.cajas, 'caj',
       case when r.cajas > 0 then 'Hay ' || round(r.cajas) || ' cajas en racks sin posición'
            else 'Se bajaron ' || round(-r.cajas) || ' cajas de racks sin decir de qué posición' end, null
  from public.gv_rack_sin_ubicar r
union all
select 'insumo', v.cod_art, 'IN', v.saldo, v.unidad,
       'Hay ' || round(v.saldo, 2) || ' ' || coalesce(v.unidad,'') || ' en stock y el insumo no está en ninguna posición del Mapa', null
  from public.vista_saldos_insumos_x_unidad v
 where v.saldo > 0
   and not exists (select 1 from public.gv_insumo_ubicacion u where upper(btrim(u.cod)) = upper(btrim(v.cod_art)) and u.estado = 'ok')
union all
select 'insumo_sin_lugar', u.cod, 'IN', u.cantidad, null,
       'Anotado en «' || u.texto || '», que no es una posición del Mapa', u.id
  from public.gv_insumo_ubicacion u where u.estado = 'sin_lugar';
grant select on public.gv_mapa_stock_sin_lugar to anon, authenticated;
