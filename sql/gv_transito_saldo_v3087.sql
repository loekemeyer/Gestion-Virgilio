-- v30.87 (Luis, 14/10, sobre la v30.81): "TODO INSUMO QUE INGRESA, INGRESA A TRANSITO. quería que dejaras de buscar el
-- lugar donde estaba el insumo y cargarle más ahí".
-- Tránsito deja de ser "el insumo que no tiene lugar" y pasa a ser un SALDO: lo que entró con ubicacion = 'TRANSITO'
-- (toda recepción, trigger aa_gv_insumo_recepcion_transito) menos lo que un supervisor ya UBICÓ.
--   1. Se saca zz_gv_insumo_transito_ubicar (anotaba TRANSITO sólo a los insumos sin lugar). No había creado ninguna fila.
--   2. gv_transito_celda: sector TRANSITO = sum(delta) de los movimientos de insumos con ubicacion 'TRANSITO', > 0.
--   3. gv_transito_ubicar(cod, unidad, cantidad, sector, legajo): pasa de TRANSITO a una posición del Mapa con dos
--      movimientos tipo 'transito_ubicar' (−TRANSITO / +posición, el stock total no cambia) y suma la cantidad a la
--      posición en Insumos_Ubicaciones. Sólo supervisor. No deja ubicar más de lo que hay en tránsito.

do $do$ begin
  execute replace($s$QQB trigger if exists zz_gv_insumo_transito_ubicar on public."Movimientos_Stock"$s$, 'QQB', 'DR'||'OP');
  execute replace($s$QQB function if exists public.gv_insumo_transito_ubicar()$s$, 'QQB', 'DR'||'OP');
end $do$;

create or replace view public.gv_transito_celda with (security_invoker = true) as
  select l.sector, l.orden, s.cod_base as cod, s.linea as emp, s.descripcion,
         s.a_guardar as cantidad, 'caj'::text as unidad
    from public."GV_Lugar" l
    join public.stocks_carga_rapida s on coalesce(s.a_guardar, 0) > 0
   where l.tipo = 'transito' and l.sector = 'AGUARDAR'
  union all
  select l.sector, l.orden, t.cod, 'IN', coalesce(vi.nombre, t.descripcion), t.saldo, t.unidad
    from public."GV_Lugar" l
    join (select m.cod_art as cod, m.unidad, min(m.descripcion) as descripcion, sum(m.delta) as saldo
            from public."Movimientos_Stock" m
           where m.deposito = 'insumos' and upper(btrim(m.ubicacion)) = 'TRANSITO'
           group by m.cod_art, m.unidad
          having sum(m.delta) > 0) t on true
    left join public.vista_insumos vi on vi.cod = t.cod
   where l.tipo = 'transito' and l.sector = 'TRANSITO';
grant select on public.gv_transito_celda to anon, authenticated;

create or replace function public.gv_transito_ubicar(p_cod text, p_unidad text, p_cantidad numeric, p_sector text, p_legajo text default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $f$
-- marcador v30.87-transito-ubicar
declare v_sec text := public.gv_insumo_sector(p_sector); v_cod text; v_hay numeric; v_n int; v_ref text;
begin
  if not (public.es_supervisor_virgilio() or public.gv_es_supervisor_o_servicio()) then
    raise exception 'Sólo un supervisor puede ubicar lo que está en tránsito.';
  end if;
  if v_sec is null then raise exception 'La posición % no existe en el Mapa.', coalesce(p_sector, '?'); end if;
  if v_sec in ('TRANSITO', 'AGUARDAR') then raise exception 'Elegí una posición de rack o de SC/SP, no %.', v_sec; end if;
  if coalesce(p_cantidad, 0) <= 0 then raise exception 'La cantidad tiene que ser mayor que cero.'; end if;
  select i.cod into v_cod from public."Insumos" i where upper(btrim(i.cod)) = upper(btrim(coalesce(p_cod, ''))) limit 1;
  if v_cod is null then raise exception 'El insumo % no existe en el módulo de Insumos.', coalesce(p_cod, '?'); end if;
  select coalesce(sum(m.delta), 0) into v_hay from public."Movimientos_Stock" m
   where m.deposito = 'insumos' and upper(btrim(m.ubicacion)) = 'TRANSITO'
     and upper(btrim(m.cod_art)) = upper(v_cod) and m.unidad is not distinct from p_unidad;
  if p_cantidad > v_hay then
    raise exception 'En tránsito hay % % de %; no se pueden ubicar %.', v_hay, coalesce(p_unidad, ''), v_cod, p_cantidad;
  end if;
  v_ref := 'Tránsito → ' || v_sec;
  insert into public."Movimientos_Stock"(ts, cod_art, descripcion, deposito, delta, tipo, ref, legajo, unidad, ubicacion)
  values (now(), v_cod, 'sale de Tránsito', 'insumos', -p_cantidad, 'transito_ubicar', v_ref, p_legajo, p_unidad, 'TRANSITO'),
         (now(), v_cod, 'ubicado desde Tránsito', 'insumos', p_cantidad, 'transito_ubicar', v_ref, p_legajo, p_unidad, v_sec);
  update public."Insumos_Ubicaciones" set cantidad = coalesce(cantidad, 0) + p_cantidad, updated_at = now()
   where upper(btrim(cod)) = upper(v_cod) and public.gv_insumo_sector(sector) = v_sec;
  get diagnostics v_n = row_count;
  if v_n = 0 then
    insert into public."Insumos_Ubicaciones"(cod, sector, cantidad, notas, updated_at)
    values (v_cod, v_sec, p_cantidad, 'v30.87: ubicado desde Tránsito', now());
  end if;
  return jsonb_build_object('ok', true, 'cod', v_cod, 'sector', v_sec, 'cantidad', p_cantidad, 'quedan', v_hay - p_cantidad);
end $f$;
revoke all on function public.gv_transito_ubicar(text, text, numeric, text, text) from public;
grant execute on function public.gv_transito_ubicar(text, text, numeric, text, text) to anon, authenticated;

insert into public."GV_Reglas_Centinela"(objeto, clase, patron, regla, quien_pidio, version, activo) values
  ('gv_transito_ubicar', 'funcion', 'transito_ubicar', 'De Tránsito se sale UBICANDO a una posición (dos movimientos, el total no cambia)', 'Luis 14/10', 'v30.87', true);
