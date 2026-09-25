-- v22.68 (Luis 25/09): "tiene que ser un módulo de front editable que tenga efecto en las tablas
-- del back". Pestaña 📦 Racks del Mapa: editar una posición escribe Racks_Planimetria Y el ajuste
-- de stock del depósito 'racks' (Movimientos_Stock) en la MISMA transacción.
-- Las funciones de abajo son las aplicadas en la base (traídas con pg_get_functiondef / viewdef).
--
-- Probado en transacción abortada (25/09): AA04 366E 75→80 (+5) · AA01 libre→960E 24 (+24) ·
-- AA07 960E→vacía (−24) · X05 368E 16→811E 20 (−16 368E, +20 811E) → stock racks de esos
-- 4 códigos 351 → 360 (= +5+24−24−16+20). Sin motivo o con código inexistente, error.
--
-- ⚠ Hallazgos NO arreglados acá (datos, piden sí del dueño):
--   1. 15 posiciones tienen DOS filas en Racks_Planimetria (una libre "de más"). racks_plani_mover
--      hace `update ... where sector = p_destino` y le pondría la carga a las DOS.
--      Esta RPC se protege eligiendo la fila por id.
--   2. gv_rack_stock_desfase: 19 códigos con distinto stock en racks que en sus posiciones.


create or replace function public.gv_rack_posicion_guardar(
  p_sector text, p_cod text, p_master numeric, p_inner numeric, p_emp text, p_motivo text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_sec   text := upper(btrim(coalesce(p_sector,'')));
  v_cod   text := nullif(upper(btrim(coalesce(p_cod,''))),'');
  v_inner numeric := coalesce(p_inner,0);
  v_mast  numeric := coalesce(p_master,0);
  v_mot   text := nullif(btrim(coalesce(p_motivo,'')),'');
  v_quien text := 'sup:' || coalesce(auth.jwt() ->> 'email', session_user::text);
  v_lug   record; r record; v_n_ocup int;
  v_emp   text; v_old_cod text; v_old_inner numeric := 0; v_old_emp text;
  v_old_real boolean := false; v_new_real boolean := false;
  v_res   jsonb := '[]'::jsonb; d numeric;
begin
  if not (public.es_supervisor_virgilio() or public.gv_es_supervisor_o_servicio()) then
    raise exception 'Sólo un supervisor puede editar los racks.';
  end if;
  if v_sec = '' then raise exception 'Falta la posición.'; end if;
  if v_mot is null then raise exception 'Escribí el motivo del cambio (queda en el movimiento de stock).'; end if;
  if v_inner < 0 or v_mast < 0 then raise exception 'Las cantidades no pueden ser negativas.'; end if;
  perform pg_advisory_xact_lock(hashtext('gv_rack_pos|' || v_sec));

  select sector, empresa into v_lug from public."GV_Lugar" where upper(btrim(sector)) = v_sec and tipo = 'rack' and activo;
  select count(*) into v_n_ocup from public."Racks_Planimetria" where upper(btrim(sector)) = v_sec and estado = 'ocupado';
  if v_n_ocup > 1 then raise exception 'La posición % tiene % cargas a la vez: hay que revisarla a mano antes de editar.', v_sec, v_n_ocup; end if;
  select * into r from public."Racks_Planimetria" where upper(btrim(sector)) = v_sec
   order by (estado = 'ocupado') desc, id limit 1 for update;
  if v_lug.sector is null and r.id is null then
    raise exception 'La posición % no existe como rack.', v_sec;
  end if;

  if r.id is not null and r.estado = 'ocupado' and nullif(btrim(coalesce(r.cod_art,'')),'') is not null then
    v_old_cod := upper(btrim(r.cod_art)); v_old_inner := coalesce(r.innercajas,0);
    v_old_emp := coalesce(nullif(btrim(r.emp),''),'LK');
    v_old_real := v_old_cod not in ('PEDIDOS','CAJAS');
  end if;

  v_emp := upper(coalesce(nullif(btrim(coalesce(p_emp,'')),''), v_old_emp, v_lug.empresa, 'LK'));
  if v_emp not in ('LK','CH') then raise exception 'Empresa inválida: % (va LK o CH).', v_emp; end if;

  if v_cod is not null and v_cod not in ('PEDIDOS','CAJAS') then
    if v_inner <= 0 then raise exception 'Poné las cajas que hay en la posición (o vaciala).'; end if;
    if not public.gv_stock_cod_conocido(v_cod) then raise exception 'El código % no existe.', v_cod; end if;
    v_new_real := true;
  end if;
  if v_cod is null then v_inner := 0; v_mast := 0; end if;
  if v_cod in ('PEDIDOS','CAJAS') then v_cod := initcap(v_cod); v_inner := 0; v_mast := 0; end if;

  if r.id is null then
    insert into public."Racks_Planimetria"(sector, cod_art, master_cajas, innercajas, estado, emp)
    values (coalesce(v_lug.sector, v_sec), v_cod, v_mast, v_inner, case when v_cod is null then 'libre' else 'ocupado' end, v_emp);
  else
    update public."Racks_Planimetria"
       set cod_art = v_cod, master_cajas = v_mast, innercajas = v_inner,
           estado = case when v_cod is null then 'libre' else 'ocupado' end, emp = v_emp
     where id = r.id;
  end if;

  if v_old_real and (not v_new_real or v_old_cod <> upper(v_cod) or v_old_emp <> v_emp) and v_old_inner <> 0 then
    insert into public."Movimientos_Stock"(cod_art, deposito, delta, tipo, ref, descripcion, unidad, legajo, empresa)
    values (v_old_cod, 'racks', -v_old_inner, 'ajuste', 'rack ' || v_sec || ' · mapa', 'Mapa de racks: ' || v_mot, 'inner', v_quien, v_old_emp);
    v_res := v_res || jsonb_build_object('cod', v_old_cod, 'emp', v_old_emp, 'delta', -v_old_inner);
    v_old_inner := 0;
  end if;
  if v_new_real then
    d := v_inner - case when v_old_real and v_old_cod = upper(v_cod) and v_old_emp = v_emp then v_old_inner else 0 end;
    if d <> 0 then
      insert into public."Movimientos_Stock"(cod_art, deposito, delta, tipo, ref, descripcion, unidad, legajo, empresa)
      values (upper(v_cod), 'racks', d, 'ajuste', 'rack ' || v_sec || ' · mapa', 'Mapa de racks: ' || v_mot, 'inner', v_quien, v_emp);
      v_res := v_res || jsonb_build_object('cod', upper(v_cod), 'emp', v_emp, 'delta', d);
    end if;
  end if;
  return jsonb_build_object('ok', true, 'sector', v_sec, 'cod', v_cod, 'inner', v_inner, 'master', v_mast, 'emp', v_emp, 'stock', v_res);
end $$;
revoke all on function public.gv_rack_posicion_guardar(text,text,numeric,numeric,text,text) from public, anon;
grant execute on function public.gv_rack_posicion_guardar(text,text,numeric,numeric,text,text) to authenticated;

create or replace view public.gv_rack_stock_desfase with (security_invoker = true) as
with rp as (
  select gv_cod_stock(cod_art) k, upper(coalesce(nullif(btrim(emp),''),'LK')) emp,
         sum(coalesce(innercajas,0)) plani, string_agg(sector || ' ' || coalesce(innercajas,0), ', ' order by sector) posiciones
    from public."Racks_Planimetria"
   where estado = 'ocupado' and nullif(btrim(cod_art),'') is not null
     and upper(btrim(cod_art)) not in ('PEDIDOS','CAJAS')
   group by 1,2
), st as (
  select gv_cod_stock(cod_art) k, upper(coalesce(empresa,'LK')) emp, sum(delta) stock
    from public."Movimientos_Stock" where deposito in ('racks','racks_ch')
   group by 1,2
)
select coalesce(rp.k, st.k) as cod, coalesce(rp.emp, st.emp) as empresa,
       coalesce(rp.plani,0) as en_posiciones, coalesce(st.stock,0) as stock_racks,
       coalesce(rp.plani,0) - coalesce(st.stock,0) as diferencia, rp.posiciones
  from rp full join st on st.k = rp.k and st.emp = rp.emp
 where coalesce(rp.plani,0) <> coalesce(st.stock,0);
grant select on public.gv_rack_stock_desfase to anon, authenticated;

-- Rollback: drop function public.gv_rack_posicion_guardar(text,text,numeric,numeric,text,text);
--           drop view public.gv_rack_stock_desfase;
