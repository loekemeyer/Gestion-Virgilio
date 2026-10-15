-- v31.11 (Luis, 15/10; la base dice v31.10-gondola): Ingreso a racks → pestaña «Desde góndola».
-- racks_plani_ingreso_nacional acepta p_origen = 'terminado' (la góndola): descuenta de terminado y suma
-- al rack en la DIRECCIÓN (v29.78, centinela 431 «v_emp, v_pos)»). En góndola, los 4 duales (437E, 438E,
-- 439E, 809E) cuentan el saldo SÓLO de la empresa elegida: la góndola de LK y la de CH son distintas.
-- Rollback: la versión anterior es la misma función sin 'terminado' en la lista de orígenes y sin v_dual.
CREATE OR REPLACE FUNCTION public.racks_plani_ingreso_nacional(p_sector text, p_cod text, p_master numeric, p_inner numeric, p_origen text, p_emp text, p_legajo text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
 v_sec text := public.gv_rack_sector(p_sector); v_cod text := upper(btrim(coalesce(p_cod,'')));
 v_codn text := upper(regexp_replace(btrim(coalesce(p_cod,'')), '^0+(.)', '\1'));
 v_inner numeric := coalesce(p_inner, 0); v_master numeric := coalesce(p_master, 0);
 v_orig text := lower(btrim(coalesce(p_origen,'')));
 v_dual boolean := public.gv_empresa_de_articulo(upper(btrim(coalesce(p_cod,'')))) is null;   -- v31.10-gondola
 v_emp text := coalesce(public.gv_empresa_de_articulo(upper(btrim(coalesce(p_cod,'')))), nullif(upper(btrim(coalesce(p_emp,''))),''), public.gv_emp_default_o_dual(p_cod));
 v_cutoff timestamptz; v_disp numeric; v_chk text; v_pos text := public.gv_rack_pos(p_sector);  -- v29.78-parte
 v_origtxt text;
begin
 if btrim(coalesce(p_sector,'')) = '' or v_cod = '' then return 'error: falta sector o codigo'; end if;
 if v_inner <= 0 then return 'error: las cajas deben ser mayor a 0'; end if;
 if v_orig not in ('a_guardar','excedente','terminado') then return 'error: origen invalido'; end if;
 v_origtxt := case when v_orig = 'terminado' then 'gondola' else v_orig end;
 select valor::timestamptz into v_cutoff from "Stock_Config" where clave='cutoff_ts' limit 1;
 select coalesce(sum(m.delta),0) into v_disp from "Movimientos_Stock" m
 where m.deposito = v_orig and upper(regexp_replace(btrim(m.cod_art), '^0+(.)', '\1')) = v_codn
 and (v_cutoff is null or m.tipo='inicial' or m.ts >= v_cutoff)
 and (v_orig <> 'terminado' or not v_dual or upper(coalesce(m.empresa,'')) = v_emp);
 if v_disp < v_inner then return 'sin_stock:'||round(coalesce(v_disp,0)); end if;
 v_chk := public.gv_rack_pos_chequear(p_sector, v_cod);
 if v_chk is not null then return v_chk; end if;
 insert into "Movimientos_Stock"(cod_art, deposito, delta, tipo, ref, unidad, legajo, empresa, ubicacion) values
 (v_cod, v_orig, -v_inner, 'traslado', case when v_orig = 'terminado' then 'gondola a racks '||v_pos else 'nacional a racks '||v_pos end, 'inner', nullif(p_legajo,''), v_emp, null),
 (v_cod, 'racks', v_inner, 'traslado', 'nacional desde '||v_origtxt||' a '||v_pos, 'inner', nullif(p_legajo,''), v_emp, v_pos);
 perform public.gv_rack_cxm_anotar(v_cod, v_emp, v_inner, v_master);
 update public."GV_Rack_Revisar" set resuelto_en = now(), resuelto_por = 'ingreso ' || coalesce(nullif(p_legajo,''),'?'),
 nota = 'se ingresaron ' || v_inner || ' cajas de ' || v_cod
 where resuelto_en is null and public.gv_rack_sector(sector) = v_sec and upper(cod) = v_cod;
 return 'ok';
end $function$;
