-- v28.96 (Luis, 09/10/2026): lo que el operario ingresa por «Ingreso a racks» en modo 📦 Importación
-- (racks_plani_ingreso) se DESCUENTA SOLO del pedido de importación en viaje de ese código.
-- Caso: contenedor Becky PI B260601 entró el 09/10 por IR (404E 232 inner = 928 u) y el bache seguía en viaje.
--
-- Reglas:
--  * NO mueve stock: el stock ya entró a racks con el IR. Sólo suma unidades_llegadas al bache,
--    deja el registro en GV_Imp_Recepcion (se ve en 📜 Historial; ↩ Anular deshace sólo la imputación)
--    y en Importados_Mov_Stock, y recalcula el pedido en curso (gv_importados_resync_calc).
--  * Bache = el EN CURSO de ese código con reingreso más próximo y algo pendiente (dual: misma empresa).
--  * Lo de más queda como sobrante de ESE pedido: no descuenta otros pedidos (regla v23.49).
--  * Llega todo → el pedido pasa a 'llegado'. Llega menos → sigue en viaje con lo que falta.
--  * Nunca frena el IR: si la imputación falla, el ingreso queda igual y el motivo va al log.
--  * Idempotente por movimiento (client_id 'irmov_<id>').
-- Log: select * from public."GV_Imp_Ingreso_Racks_Log" order by ts desc;   (resultado <> 'imputado' = mirar)

create table if not exists public."GV_Imp_Ingreso_Racks_Log" (
  mov_id bigint primary key,
  ts timestamptz not null default now(),
  cod_art text, cajas numeric, legajo text, sector text,
  resultado text not null,          -- imputado | sin_pedido | sin_uni_x_caja | error
  bache_id bigint, recepcion_id bigint, unidades numeric, motivo text
);
alter table public."GV_Imp_Ingreso_Racks_Log" enable row level security;
revoke all on public."GV_Imp_Ingreso_Racks_Log" from anon, authenticated;

create or replace function public.gv_imp_imputar_ingreso_racks(p_mov_id bigint, p_legajo text default null)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $f$
declare m record; b record; v_cod text; v_dual boolean; v_uxc numeric; v_uni numeric; v_pend numeric;
        v_estado text; v_rec bigint; v_emp text; v_cid text := 'irmov_' || p_mov_id; v_es_imp boolean;
begin  -- v28.96-imp-ir
  select * into m from public."Movimientos_Stock" where id = p_mov_id;
  if not found or m.tipo <> 'ingreso' or m.deposito not in ('racks','racks_ch') or coalesce(m.delta,0) <= 0 then
    return jsonb_build_object('ok', false, 'motivo', 'no es un ingreso a racks');
  end if;
  if exists (select 1 from public."GV_Imp_Recepcion" where client_id = v_cid) then
    return jsonb_build_object('ok', true, 'repetida', true);
  end if;
  v_cod := upper(regexp_replace(btrim(m.cod_art), '([0-9E])L$', '\1'));
  v_emp := upper(coalesce(m.empresa, 'LK'));
  v_es_imp := exists (select 1 from public."Importados" i where public.gv_cod_stock(upper(btrim(i.cod_art))) = public.gv_cod_stock(v_cod));
  if not v_es_imp then return jsonb_build_object('ok', false, 'motivo', 'no es importado'); end if;
  v_dual := exists (select 1 from public.codigos_duales x where x.cod = public.gv_cod_stock(v_cod));
  select bb.*, coalesce(nullif(im.uni_x_caja, 0),
          (select nullif(v.uni_inner, 0) from public."Importados_Volumen" v where v.cod = bb.cod_art limit 1)) uxc
    into b
    from public."GV_Importados_Baches" bb join public."Importados" im on im.id = bb.importado_id
   where bb.estado = 'en_curso' and bb.unidades > bb.unidades_llegadas
     and public.gv_cod_stock(upper(regexp_replace(btrim(bb.cod_art), '([0-9E])L$', '\1'))) = public.gv_cod_stock(v_cod)
     and (not v_dual or (case when upper(coalesce(bb.marca, im.marca, '')) in ('CH','CHEF') then 'CH' else 'LK' end) = v_emp)
   order by bb.fecha_reingreso nulls last, bb.id
   limit 1
   for update of bb;
  if not found then
    insert into public."GV_Imp_Ingreso_Racks_Log"(mov_id, cod_art, cajas, legajo, sector, resultado, motivo)
    values (p_mov_id, v_cod, m.delta, coalesce(p_legajo, m.legajo), m.ubicacion, 'sin_pedido', 'no hay pedido de importación en viaje de ese código')
    on conflict (mov_id) do nothing;
    return jsonb_build_object('ok', false, 'motivo', 'sin pedido en viaje');
  end if;
  v_uxc := b.uxc;
  if v_uxc is null then
    insert into public."GV_Imp_Ingreso_Racks_Log"(mov_id, cod_art, cajas, legajo, sector, resultado, bache_id, motivo)
    values (p_mov_id, v_cod, m.delta, coalesce(p_legajo, m.legajo), m.ubicacion, 'sin_uni_x_caja', b.id, 'falta unidades por caja en Importados')
    on conflict (mov_id) do nothing;
    return jsonb_build_object('ok', false, 'motivo', 'sin unidades por caja');
  end if;
  v_uni := round(m.delta * v_uxc);
  v_pend := greatest(0, b.unidades - b.unidades_llegadas);
  v_estado := case when b.unidades_llegadas + v_uni >= b.unidades then 'llegado' else 'en_curso' end;
  insert into public."GV_Imp_Recepcion"(bache_id, importado_id, cod_art, empresa, proveedor, pedido_ref, unidades, uni_x_caja, cajas,
    pendiente_antes, estado_bache, por, legajo, nota, client_id, faltante, sobrante, cerro_bache, estado_antes, llegadas_antes)
  values (b.id, b.importado_id, b.cod_art, v_emp, b.proveedor, b.pedido_ref, v_uni, v_uxc, m.delta,
    v_pend, v_estado, 'operario · Ingreso a racks', coalesce(p_legajo, m.legajo),
    'Ingreso a racks ' || coalesce(m.ubicacion, '') || ' (operario, mov ' || p_mov_id || ')', v_cid,
    0, greatest(0, v_uni - v_pend), v_estado = 'llegado', b.estado, b.unidades_llegadas)
  returning id into v_rec;
  -- sin fila de destino A PROPÓSITO: ↩ Anular sólo deshace la imputación al pedido y NO saca el stock
  -- (las cajas están en el rack de verdad; el IR se corrige con su propio ajuste).
  insert into public."Importados_Mov_Stock"(ts, cod_art, marca, tipo, delta_uni, ref, legajo, creado)
  values (now(), b.cod_art, b.marca, 'ingreso', v_uni, 'recepcion importacion #' || v_rec || ' (ingreso a racks)', coalesce(p_legajo, m.legajo), now());
  update public."GV_Importados_Baches" set unidades_llegadas = unidades_llegadas + v_uni::int, estado = v_estado, actualizado = now()
   where id = b.id;
  perform public.gv_importados_resync_calc(b.importado_id);
  insert into public."GV_Imp_Ingreso_Racks_Log"(mov_id, cod_art, cajas, legajo, sector, resultado, bache_id, recepcion_id, unidades)
  values (p_mov_id, v_cod, m.delta, coalesce(p_legajo, m.legajo), m.ubicacion, 'imputado', b.id, v_rec, v_uni)
  on conflict (mov_id) do nothing;
  return jsonb_build_object('ok', true, 'recepcion_id', v_rec, 'bache_id', b.id, 'pedido_ref', b.pedido_ref,
    'unidades', v_uni, 'pendiente_antes', v_pend, 'estado', v_estado, 'sobra', greatest(0, v_uni - v_pend));
end $f$;
revoke all on function public.gv_imp_imputar_ingreso_racks(bigint, text) from public, anon, authenticated;

-- racks_plani_ingreso: misma función + la imputación al final (traída de pg_get_functiondef el 09/10)
create or replace function public.racks_plani_ingreso(p_sector text, p_cod text, p_master numeric, p_inner numeric, p_emp text, p_legajo text)
 returns text language plpgsql security definer set search_path to 'public' as $function$
declare
 v_sec text := public.gv_rack_sector(p_sector);
 v_cod text := upper(btrim(coalesce(p_cod,'')));
 v_inner numeric := coalesce(p_inner, 0); v_master numeric := coalesce(p_master, 0);
 v_emp text := coalesce(public.gv_empresa_de_articulo(upper(btrim(coalesce(p_cod,'')))), nullif(upper(btrim(coalesce(p_emp,''))),''), 'LK');
 v_chk text; v_mid bigint;
begin
 if btrim(coalesce(p_sector,'')) = '' or v_cod = '' then return 'error: falta sector o codigo'; end if;
 if v_inner <= 0 then return 'error: las cajas deben ser mayor a 0'; end if;
 v_chk := public.gv_rack_pos_chequear(p_sector, v_cod);
 if v_chk is not null then return v_chk; end if;
 insert into "Movimientos_Stock"(cod_art, deposito, delta, tipo, ref, unidad, legajo, empresa, ubicacion)
 values (v_cod, 'racks', v_inner, 'ingreso', 'ingreso a racks '||v_sec||' ('||coalesce(v_master,0)||' master)', 'inner', nullif(p_legajo,''), v_emp, v_sec)
 returning id into v_mid;
 perform public.gv_rack_cxm_anotar(v_cod, v_emp, v_inner, v_master);
 update public."GV_Rack_Revisar" set resuelto_en = now(), resuelto_por = 'ingreso ' || coalesce(nullif(p_legajo,''),'?'),
 nota = 'se ingresaron ' || v_inner || ' cajas de ' || v_cod
 where resuelto_en is null and public.gv_rack_sector(sector) = v_sec and upper(cod) = v_cod;
 -- v28.96 (Luis): lo que entra por acá es lo que llega de importación → descuenta el pedido en viaje.
 -- Nunca frena el ingreso: si falla, queda en GV_Imp_Ingreso_Racks_Log.
 begin
   perform public.gv_imp_imputar_ingreso_racks(v_mid, nullif(p_legajo,''));
 exception when others then
   begin
     insert into public."GV_Imp_Ingreso_Racks_Log"(mov_id, cod_art, cajas, legajo, sector, resultado, motivo)
     values (v_mid, v_cod, v_inner, nullif(p_legajo,''), v_sec, 'error', sqlerrm) on conflict (mov_id) do nothing;
   exception when others then null;
   end;
 end;
 return 'ok';
end $function$;

insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
values ('racks_plani_ingreso','funcion','gv_imp_imputar_ingreso_racks\(v_mid',
        'El ingreso a racks de importación descuenta el pedido de importación en viaje','Luis','v28.96'),
       ('gv_imp_imputar_ingreso_racks','funcion','unidades_llegadas \+ v_uni',
        'El ingreso a racks suma lo llegado al bache de importación (sin mover stock)','Luis','v28.96');

-- ROLLBACK: recrear racks_plani_ingreso sin el bloque «v28.96» (cuerpo anterior en el git log de este archivo / pg del 09/10)
-- y, para deshacer una imputación, ↩ Anular en 📜 Historial (gv_imp_recepcion_anular).
