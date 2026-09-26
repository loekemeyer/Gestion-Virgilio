-- v22.96 (2026-09-26) — IMPORTACIÓN: escribir sólo con login de SUPERVISOR (cierra la v22.81)
-- Proyecto Supabase: hrxfctzncixxqmpfhskv · Pedido de Thomas, 26/09 ("Si").
--
-- QUÉ SE MIDIÓ (26/09):
--   · La v22.81 dejó el "Paso C" sin aplicar: Importados.imp_upd_anon (UPDATE anon, using true),
--     Importados.imp_write (ALL authenticated, using true), Importados_Volumen.impvol_ins / impvol_upd (anon).
--     "authenticated" incluye a los ~450 usuarios ANÓNIMOS del proyecto: using (true) = cualquiera.
--   · Importados_Config / Importados_Partes_Map / Importados_Stock_Parte: ALL to authenticated using (true).
--     Nadie los escribe desde el front (rg sobre el repo: 0 escrituras).
--   · 21 RPC SECURITY DEFINER que escriben (giros, cuenta corriente, baches, fechas, NTL, alias, en curso)
--     ejecutables por anon SIN chequeo. Quién las llama: SÓLO el módulo 📦 Importación de index.html (panel
--     supervisor). Ningún cron, ningún trigger, ningún otro front. gv_importados_resync la llaman además 5 de
--     ellas por dentro (el JWT es el mismo, pasa igual).
--
-- QUÉ HACE:
--   1) Paso C de la v22.81: saca las policies abiertas del maestro y revoca la escritura de anon.
--   2) Config / mapa de partes / stock de parte: la escritura pasa a supervisor.
--   3) Candado de supervisor al principio de las 21 RPC (se aplica sobre pg_get_functiondef, idempotente:
--      marca 'v22.96-sup'; falla con raise si una no matchea). Pasa: supervisor (es_supervisor_virgilio) o
--      servicio/postgres (gv_es_supervisor_o_servicio: crons, MCP, service_role).
--   4) Un centinela por RPC en GV_Reglas_Centinela.
--   El front (v22.96) ya firma estas RPC con la sesión Google (_pedImpRpc + _PED_IMP_RPC_ESCRITURA).
--
-- NO TOCA Stock_Config: la escriben 10 pantallas con la clave pública (stock, guardado, OCs, importación);
-- cerrarla exige pasar esas 10 a la sesión primero. Queda como paso aparte.

-- ---------- 1) maestro: Paso C de la v22.81 ----------
drop policy if exists imp_upd_anon on public."Importados";
drop policy if exists imp_write    on public."Importados";
drop policy if exists impvol_ins   on public."Importados_Volumen";
drop policy if exists impvol_upd   on public."Importados_Volumen";
revoke insert, update, delete on public."Importados"         from anon;
revoke insert, update, delete on public."Importados_Volumen" from anon;

-- ---------- 2) config / partes / stock de parte ----------
drop policy if exists impcfg_write on public."Importados_Config";
drop policy if exists ipm_all      on public."Importados_Partes_Map";
drop policy if exists isp_all      on public."Importados_Stock_Parte";
create policy impcfg_write_supervisor on public."Importados_Config"      for all to authenticated
  using (public.es_supervisor_virgilio()) with check (public.es_supervisor_virgilio());
create policy ipm_write_supervisor    on public."Importados_Partes_Map"  for all to authenticated
  using (public.es_supervisor_virgilio()) with check (public.es_supervisor_virgilio());
create policy isp_write_supervisor    on public."Importados_Stock_Parte" for all to authenticated
  using (public.es_supervisor_virgilio()) with check (public.es_supervisor_virgilio());

-- ---------- 3) candado en las 21 RPC ----------
do $sup$
declare
  f text; o oid; d text; d2 text; n int := 0;
  guard constant text :=
    E'\n  -- v22.96-sup: sólo supervisor (Thomas 26/09, cierra la v22.81)\n'
    || E'  if not (public.es_supervisor_virgilio() or public.gv_es_supervisor_o_servicio()) then\n'
    || E'    raise exception ''Sólo un supervisor logueado puede guardar en Importación (iniciá sesión con Google; si ya estás, actualizá la app).'' using errcode = ''42501'';\n'
    || E'  end if;';
begin
  foreach f in array array['gv_imp_carga_pedido_set','gv_imp_cc_deuda_add','gv_imp_cc_deuda_borrar','gv_imp_cc_deuda_set',
    'gv_imp_cc_set','gv_imp_ntl_efectivo_add','gv_imp_ntl_efectivo_borrar','gv_imp_pago_add','gv_imp_pago_borrar',
    'gv_imp_pago_cargas_set','gv_imp_prov_alias_set','gv_importado_bache_add','gv_importado_bache_borrar',
    'gv_importado_bache_editar','gv_importado_bache_embarque','gv_importado_bache_llego','gv_importado_pedido_fechas',
    'gv_importado_pedido_ref','gv_importados_resync','importados_marcar_llegada','importados_set_curso'] loop
    select p.oid into o from pg_proc p join pg_namespace s on s.oid = p.pronamespace where s.nspname = 'public' and p.proname = f;
    if o is null then raise exception 'no existe %', f; end if;
    d := pg_get_functiondef(o);
    if position('v22.96-sup' in d) > 0 then continue; end if;          -- ya aplicado
    d2 := regexp_replace(d, '^(.*?\$function\$.*?\mbegin\M)', '\1' || guard, 'i');
    if d2 = d then raise exception 'no encontré el begin de %', f; end if;
    execute d2;
    n := n + 1;
  end loop;
  raise notice 'candado aplicado a % funciones', n;
end $sup$;

-- ---------- 4) centinelas ----------
insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
select f, 'funcion', 'es_supervisor_virgilio\(\) or public\.gv_es_supervisor_o_servicio\(\)',
       'Importación: esta RPC escribe y sólo la puede usar un supervisor logueado (o el servicio); sin esto cualquiera con la clave pública carga o borra giros, baches, fechas o la cuenta corriente',
       'Thomas', 'v22.96'
  from unnest(array['gv_imp_carga_pedido_set','gv_imp_cc_deuda_add','gv_imp_cc_deuda_borrar','gv_imp_cc_deuda_set',
    'gv_imp_cc_set','gv_imp_ntl_efectivo_add','gv_imp_ntl_efectivo_borrar','gv_imp_pago_add','gv_imp_pago_borrar',
    'gv_imp_pago_cargas_set','gv_imp_prov_alias_set','gv_importado_bache_add','gv_importado_bache_borrar',
    'gv_importado_bache_editar','gv_importado_bache_embarque','gv_importado_bache_llego','gv_importado_pedido_fechas',
    'gv_importado_pedido_ref','gv_importados_resync','importados_marcar_llegada','importados_set_curso']) f
 where not exists (select 1 from public."GV_Reglas_Centinela" c where c.objeto = f and c.version = 'v22.96');

-- ---------- verificación ----------
-- select tablename, policyname, cmd, roles from pg_policies where schemaname='public'
--  and tablename in ('Importados','Importados_Volumen','Importados_Config','Importados_Partes_Map','Importados_Stock_Parte') order by 1,2;
-- select * from public.gv_reglas_perdidas;   -- vacía
-- Como anon, una RPC de escritura tiene que dar 42501 y un UPDATE a Importados 0 filas.

-- ---------- ROLLBACK ----------
-- grant insert, update on public."Importados", public."Importados_Volumen" to anon;
-- create policy imp_upd_anon on public."Importados" for update to anon, authenticated using (true) with check (true);
-- create policy imp_write    on public."Importados" for all to authenticated using (true) with check (true);
-- create policy impvol_ins   on public."Importados_Volumen" for insert to anon with check (true);
-- create policy impvol_upd   on public."Importados_Volumen" for update to anon using (true) with check (true);
-- drop policy impcfg_write_supervisor on public."Importados_Config";      create policy impcfg_write on public."Importados_Config" for all to authenticated using (true) with check (true);
-- drop policy ipm_write_supervisor    on public."Importados_Partes_Map";  create policy ipm_all      on public."Importados_Partes_Map" for all to authenticated using (true) with check (true);
-- drop policy isp_write_supervisor    on public."Importados_Stock_Parte"; create policy isp_all      on public."Importados_Stock_Parte" for all to authenticated using (true) with check (true);
-- Candado: por cada función, pg_get_functiondef → sacar el bloque que empieza en '-- v22.96-sup' hasta su 'end if;' → execute.
-- update public."GV_Reglas_Centinela" set activo = false where version = 'v22.96' and patron like 'es_supervisor_virgilio%';
