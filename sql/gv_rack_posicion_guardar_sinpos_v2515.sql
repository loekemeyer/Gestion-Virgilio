-- =====================================================================================
-- v25.15 (Marianela, 30/09/2026) — Mapa de racks: el CONTEO no se suma al stock SIN POSICIÓN
-- =====================================================================================
-- Qué pasaba: al cargar el conteo de una posición desde el Mapa, la diferencia contra lo que
-- tenía ESA posición entraba como ajuste nuevo, sin descontar el stock «sin posición» del
-- mismo código, que es la misma mercadería. El total de racks se duplicaba:
--   505I: contado 1475 (AD12 420 · AA05 490 · R27 565) → quedó en 2614 (+1139 viejas sin posición)
--   056E: contado 300 en W03 → quedó en 384 (+84)
--   816E: contado 352 (AB05 208 · AD03 144) → quedó en 472 (+120)
-- Los tres se corrigieron con un ajuste por código el mismo día. Problema de auditoría 648.
--
-- Qué hace ahora: si lo contado es MAYOR a lo que tenía la posición, primero se TRASLADA lo que
-- haya sin posición de ese código (−N sin ubicación / +N en la posición, tipo 'traslado') y sólo
-- lo que sobre entra como ajuste. Si lo contado es MENOR, es ajuste negativo como siempre y lo sin
-- posición no se toca.
--
-- Se aplicó sobre pg_get_functiondef (definición viva), idempotente por el marcador
-- `sinpos-mapa-3009` — es la llave, no cambiarla. Probado en transacción abortada con 816E/AB05:
--   A) +10 sin posición, cuento +10  → total no cambia, sin posición 0
--   B) +10 sin posición, cuento +22  → 10 traslado + 12 ajuste, sin posición 0
--   C) +10 sin posición, cuento −40  → ajuste −40, sin posición sigue en 10
--
-- Chequeo: select * from public.gv_rack_sin_ubicar;  -- lo que queda sin posición
--          select * from public.gv_reglas_perdidas;  -- la fila del centinela de abajo
-- =====================================================================================

CREATE OR REPLACE FUNCTION public.gv_rack_posicion_guardar(p_sector text, p_cod text, p_master numeric, p_inner numeric, p_emp text, p_motivo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
 v_sec text := public.gv_rack_sector(p_sector);
 v_cod text := nullif(upper(btrim(coalesce(p_cod,''))),'');
 v_inner numeric := coalesce(p_inner,0); v_mast numeric := coalesce(p_master,0);
 v_mot text := nullif(btrim(coalesce(p_motivo,'')),'');
 v_quien text := 'sup:' || coalesce(auth.jwt() ->> 'email', session_user::text);
 v_emp text; r record; d numeric; v_res jsonb := '[]'::jsonb; v_tiene numeric; v_de_sinpos numeric; v_dep_sp text; -- sinpos-mapa-3009
begin
 if not (public.es_supervisor_virgilio() or public.gv_es_supervisor_o_servicio()) then
 raise exception 'Sólo un supervisor puede editar los racks.';
 end if;
 if v_sec is null then raise exception 'La posición % no existe como rack.', coalesce(p_sector,'?'); end if;
 if v_mot is null then raise exception 'Escribí el motivo del cambio (queda en el movimiento de stock).'; end if;
 if v_inner < 0 or v_mast < 0 then raise exception 'Las cantidades no pueden ser negativas.'; end if;
 perform pg_advisory_xact_lock(hashtext('gv_rack_pos|' || v_sec));
 if v_cod in ('PEDIDOS','CAJAS') then v_inner := 0; end if;
 if v_cod is not null and v_cod not in ('PEDIDOS','CAJAS') then
 if v_inner <= 0 then raise exception 'Poné las cajas que hay en la posición (o vaciala).'; end if;
 if not public.gv_stock_cod_conocido(v_cod) then raise exception 'El código % no existe.', v_cod; end if;
 end if;
 v_emp := upper(coalesce(case when v_cod is not null then public.gv_empresa_de_articulo(v_cod) end,
 nullif(btrim(coalesce(p_emp,'')),''),
 (select empresa from public."GV_Lugar" where sector = v_sec), 'LK'));
 if v_emp not in ('LK','CH') then raise exception 'Empresa inválida: % (va LK o CH).', v_emp; end if;
 for r in select m.deposito dep, upper(btrim(m.cod_art)) cod,
 case when m.deposito='racks_ch' then 'CH' else upper(coalesce(m.empresa,'LK')) end emp, sum(m.delta) s
 from public."Movimientos_Stock" m
 where m.deposito in ('racks','racks_ch') and m.ubicacion is not null and public.gv_rack_sector(m.ubicacion) = v_sec
 group by 1,2,3 having sum(m.delta) <> 0 loop
 if v_cod is null or v_cod in ('PEDIDOS','CAJAS') or r.cod <> v_cod or r.emp <> v_emp then
 insert into public."Movimientos_Stock"(cod_art, deposito, delta, tipo, ref, descripcion, unidad, legajo, empresa, ubicacion)
 values (r.cod, r.dep, -r.s, 'ajuste', 'rack ' || v_sec || ' · mapa', 'Mapa de racks: ' || v_mot, 'inner', v_quien, r.emp, v_sec);
 v_res := v_res || jsonb_build_object('cod', r.cod, 'emp', r.emp, 'delta', -r.s);
 end if;
 end loop;
 if v_cod is not null and v_cod not in ('PEDIDOS','CAJAS') then
 v_tiene := public.gv_rack_saldo_pos(v_sec, v_cod, v_emp);
 d := v_inner - v_tiene;
 -- sinpos-mapa-3009 (Marianela, 30/09): lo contado DE MAS sale primero de lo SIN POSICION del mismo codigo
 -- (es la misma mercaderia). Antes entraba como ajuste nuevo y el total se duplicaba: 505I +1139, 056E +84, 816E +120.
 if d > 0 then
  select m.deposito, sum(m.delta) into v_dep_sp, v_de_sinpos from public."Movimientos_Stock" m
   where m.deposito in ('racks','racks_ch') and upper(btrim(m.cod_art)) = v_cod
     and (case when m.deposito='racks_ch' then 'CH' else upper(coalesce(m.empresa,'LK')) end) = v_emp
     and (m.ubicacion is null or public.gv_rack_sector(m.ubicacion) is null)
   group by m.deposito order by sum(m.delta) desc limit 1;
  v_de_sinpos := least(d, greatest(coalesce(v_de_sinpos, 0), 0));
  if v_de_sinpos > 0 then
   insert into public."Movimientos_Stock"(cod_art, deposito, delta, tipo, ref, descripcion, unidad, legajo, empresa, ubicacion) values
    (v_cod, v_dep_sp, -v_de_sinpos, 'traslado', 'rack ' || v_sec || ' · mapa', 'Mapa de racks: ' || v_mot || ' · estaba sin posición', 'inner', v_quien, v_emp, null),
    (v_cod, v_dep_sp, v_de_sinpos, 'traslado', 'rack ' || v_sec || ' · mapa', 'Mapa de racks: ' || v_mot || ' · estaba sin posición', 'inner', v_quien, v_emp, v_sec);
   v_res := v_res || jsonb_build_object('cod', v_cod, 'emp', v_emp, 'delta', v_de_sinpos, 'de_sin_posicion', true);
   d := d - v_de_sinpos;
  end if;
 end if;
 if d <> 0 then
 insert into public."Movimientos_Stock"(cod_art, deposito, delta, tipo, ref, descripcion, unidad, legajo, empresa, ubicacion)
 values (v_cod, 'racks', d, 'ajuste', 'rack ' || v_sec || ' · mapa', 'Mapa de racks: ' || v_mot, 'inner', v_quien, v_emp, v_sec);
 v_res := v_res || jsonb_build_object('cod', v_cod, 'emp', v_emp, 'delta', d);
 end if;
 perform public.gv_rack_cxm_anotar(v_cod, v_emp, v_inner, v_mast);
 end if;
 update public."GV_Lugar" set uso = case v_cod when 'PEDIDOS' then 'pedidos' when 'CAJAS' then 'cajas' else null end,
 updated_at = now()
 where sector = v_sec and (uso in ('pedidos','cajas') or v_cod in ('PEDIDOS','CAJAS'))
 and uso is distinct from case v_cod when 'PEDIDOS' then 'pedidos' when 'CAJAS' then 'cajas' else null end;
 update public."GV_Rack_Revisar" set resuelto_en = now(), resuelto_por = v_quien, nota = 'Mapa: ' || v_mot
 where resuelto_en is null and coalesce(public.gv_rack_sector(sector), sector) = v_sec;
 return jsonb_build_object('ok', true, 'sector', v_sec, 'cod', v_cod, 'inner', v_inner, 'master', v_mast, 'emp', v_emp, 'stock', v_res);
end $function$;

-- ROLLBACK: volver a crear la función SIN el bloque `if d > 0 then … end if;` marcado con
-- sinpos-mapa-3009 (y sin las dos variables v_de_sinpos / v_dep_sp del declare). Todo lo demás
-- queda igual: es exactamente la definición que corría antes del 30/09.
