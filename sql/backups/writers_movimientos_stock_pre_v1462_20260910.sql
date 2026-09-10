-- BACKUP (rollback) — definiciones ORIGINALES de los 6 writers de Movimientos_Stock
-- ANTES de v14.75 (2026-09-10). Para revertir: ejecutar este archivo entero + refrescar vistas.
-- Capturado con pg_get_functiondef el 2026-09-10.
-- ============================================================================================

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
    update "Racks_Planimetria" set cod_art=v_cod, master_cajas=v_master, innercajas=v_inner, estado='ocupado', emp=v_emp where id = r.id;
  elsif upper(btrim(r.cod_art)) = v_cod then
    update "Racks_Planimetria" set master_cajas = coalesce(master_cajas,0) + v_master, innercajas = coalesce(innercajas,0) + v_inner where id = r.id;
  else
    return 'ocupado:' || r.cod_art;
  end if;
  insert into "Movimientos_Stock"(cod_art, deposito, delta, tipo, ref, unidad, legajo)
  values (v_cod, 'racks', v_inner, 'ingreso', 'ingreso a racks '||v_sec||' ('||coalesce(v_master,0)||' master)', 'inner', nullif(p_legajo,''));
  return 'ok';
end $function$;

CREATE OR REPLACE FUNCTION public.racks_plani_ingreso_nacional(p_sector text, p_cod text, p_master numeric, p_inner numeric, p_origen text, p_emp text, p_legajo text)
 RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare
  v_sec text := upper(btrim(coalesce(p_sector,''))); v_cod text := upper(btrim(coalesce(p_cod,'')));
  v_codn text := upper(regexp_replace(btrim(coalesce(p_cod,'')), '^0+(.)', '\1'));
  v_inner numeric := coalesce(p_inner, 0); v_master numeric := coalesce(p_master, 0);
  v_orig text := lower(btrim(coalesce(p_origen,''))); v_emp text := coalesce(nullif(btrim(coalesce(p_emp,'')),''), 'LK');
  v_cutoff timestamptz; v_disp numeric; r record;
begin
  if v_sec = '' or v_cod = '' then return 'error: falta sector o codigo'; end if;
  if v_inner <= 0 then return 'error: las cajas deben ser mayor a 0'; end if;
  if v_orig not in ('a_guardar','excedente') then return 'error: origen invalido'; end if;
  select valor::timestamptz into v_cutoff from "Stock_Config" where clave='cutoff_ts' limit 1;
  select coalesce(sum(m.delta),0) into v_disp from "Movimientos_Stock" m
   where m.deposito = v_orig and upper(regexp_replace(btrim(m.cod_art), '^0+(.)', '\1')) = v_codn
     and (v_cutoff is null or m.tipo='inicial' or m.ts >= v_cutoff);
  if v_disp < v_inner then return 'sin_stock:'||round(coalesce(v_disp,0)); end if;
  select * into r from "Racks_Planimetria" where upper(btrim(sector)) = v_sec limit 1;
  if not found then
    insert into "Racks_Planimetria"(sector, cod_art, master_cajas, innercajas, estado, emp) values (v_sec, v_cod, v_master, v_inner, 'ocupado', v_emp);
  elsif r.estado is distinct from 'ocupado' or r.cod_art is null or btrim(coalesce(r.cod_art,'')) = '' then
    update "Racks_Planimetria" set cod_art=v_cod, master_cajas=v_master, innercajas=v_inner, estado='ocupado', emp=v_emp where id = r.id;
  elsif upper(btrim(r.cod_art)) = v_cod then
    update "Racks_Planimetria" set master_cajas = coalesce(master_cajas,0) + v_master, innercajas = coalesce(innercajas,0) + v_inner where id = r.id;
  else
    return 'ocupado:' || r.cod_art;
  end if;
  insert into "Movimientos_Stock"(cod_art, deposito, delta, tipo, ref, unidad, legajo) values
    (v_cod, v_orig,  -v_inner, 'traslado', 'nacional a racks '||v_sec, 'inner', nullif(p_legajo,'')),
    (v_cod, 'racks',  v_inner, 'traslado', 'nacional desde '||v_orig||' a '||v_sec, 'inner', nullif(p_legajo,''));
  return 'ok';
end $function$;

CREATE OR REPLACE FUNCTION public.registrar_baja_racks(p_items jsonb)
 RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare it jsonb; v_cid text; v_cod text; v_caj numeric; v_desc text; v_sec text; v_ref text; v_leg text; v_ord bigint; n int := 0;
begin
  if p_items is null then return 0; end if;
  for it in select value from jsonb_array_elements(p_items) as t(value) loop
    v_cod := nullif(btrim(it->>'cod_art'), ''); v_caj := coalesce((it->>'cajas')::numeric, 0);
    if v_cod is null or v_caj <= 0 then continue; end if;
    v_cid := nullif(it->>'cid',''); if v_cid is null then v_cid := 'br_' || replace(gen_random_uuid()::text,'-',''); end if;
    v_desc := it->>'descripcion'; v_sec := nullif(it->>'sector','');
    v_ref := coalesce(nullif(it->>'ref',''), 'rack ' || coalesce(v_sec,'s/sector'));
    v_leg := coalesce(nullif(it->>'legajo',''), '0'); v_ord := nullif(it->>'orden_id','')::bigint;
    insert into public."Racks_Bajadas" (orden_id, cod_art, descripcion, cajas, estado, aprobada_at, creada_por, sector, client_id)
    values (v_ord, v_cod, v_desc, v_caj, 'aprobada', now(), v_leg, v_sec, v_cid) on conflict do nothing;
    insert into public."Movimientos_Stock" (cod_art, descripcion, deposito, delta, tipo, ref, legajo, client_id)
    values (v_cod, v_desc, 'racks', -v_caj, 'baja_racks', v_ref, v_leg, v_cid || '-r') on conflict do nothing;
    insert into public."Movimientos_Stock" (cod_art, descripcion, deposito, delta, tipo, ref, legajo, client_id)
    values (v_cod, v_desc, 'terminado', v_caj, 'baja_racks', v_ref, v_leg, v_cid || '-t') on conflict do nothing;
    n := n + 1;
  end loop;
  return n;
end; $function$;

-- aceptar_conteo, anular_modo_op, faltante_resolver: originales = idénticos a v14.75 SIN la
-- columna `empresa` en el INSERT (y sin la derivación de v_emp). El texto completo original
-- quedó en el historial de esta sesión (pg_get_functiondef 2026-09-10). Rollback práctico:
-- quitar `, empresa` del INSERT y el bloque de cálculo de v_emp en cada una.
