-- v22.28 (Luis, 24/09/2026): «tarda mucho en cargar las facturas en conciliación… sale timeout».
-- Medido: al abrir, el front esperaba gv_cruce_fc_asig_refrescar_si_viejo (2,5 s: recalcula
-- el cruce NP↔FC y REESCRIBÍA las 980 filas aunque cambiaran 0) y recién después pedía la lista
-- (1,5–3 s). Dos recálculos a la vez se esperaban (máx. medido 9,4 s). A las 11:49 la base tuvo
-- ~20 cortes por timeout en todas las pantallas; Conciliación era la primera en caer.
--
-- 1) GV_Cruce_FC_Asig_Corrida (1 fila): hora de la última corrida. La frescura sale de acá.
-- 2) gv_cruce_fc_asig_refrescar(): pg_try_advisory_xact_lock(90901) → si hay otra corrida
--    devuelve -2 sin esperar; upsert sólo de filas que cambian; devuelve cuántas cambiaron.
-- 3) gv_cruce_fc_asig_refrescar_si_viejo(): lee la corrida; -1 fresco, -2 en curso, >=0 cambios.
-- 4) gv_conciliacion_lista(): el neto actual sólo de las NP de GV_Conciliacion_Facturacion
--    (220) en vez de gv_vista_facturacion_neto entera (1.048 NP, 1,3 s). Salida idéntica
--    (220 = 220, EXCEPT 0 en np/neto_actual/corregido/estado/diff).
-- 5) Front: el recálculo corre en paralelo a la lista; si devuelve > 0 la lista se re-pide.
-- Centinela: GV_Reglas_Centinela 'pg_try_advisory_xact_lock\(90901\)'.

create table if not exists public."GV_Cruce_FC_Asig_Corrida" (id int primary key default 1 check (id = 1), corrido_at timestamptz not null, cambios int);
alter table public."GV_Cruce_FC_Asig_Corrida" enable row level security;
revoke all on public."GV_Cruce_FC_Asig_Corrida" from anon, authenticated;

CREATE OR REPLACE FUNCTION public.gv_cruce_fc_asig_refrescar()
 RETURNS integer LANGUAGE plpgsql SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp' SET statement_timeout TO '120000'
AS $function$
declare n integer; v_cambios integer := 0; v_x integer;
begin
  if not pg_try_advisory_xact_lock(90901) then return -2; end if;
  drop table if exists _gv_asig_new;
  create temp table _gv_asig_new as select * from public.gv_cruce_fc_asignacion();
  select count(*) into n from _gv_asig_new;
  if n = 0 then drop table if exists _gv_asig_new; return 0; end if;
  delete from public."GV_Cruce_FC_Asig" a where not exists (select 1 from _gv_asig_new x where x.np = a.np);
  get diagnostics v_x = row_count; v_cambios := v_cambios + v_x;
  insert into public."GV_Cruce_FC_Asig" (np, doc_id, candidatos, actualizado_at)
  select x.np, x.doc_id, x.candidatos, now() from _gv_asig_new x
  on conflict (np) do update
     set doc_id = excluded.doc_id, candidatos = excluded.candidatos, actualizado_at = now()
   where "GV_Cruce_FC_Asig".doc_id is distinct from excluded.doc_id
      or "GV_Cruce_FC_Asig".candidatos is distinct from excluded.candidatos;
  get diagnostics v_x = row_count; v_cambios := v_cambios + v_x;
  insert into public."GV_Cruce_FC_Asig_Corrida" (id, corrido_at, cambios) values (1, now(), v_cambios)
  on conflict (id) do update set corrido_at = excluded.corrido_at, cambios = excluded.cambios;
  drop table if exists _gv_asig_new;
  return v_cambios;
end $function$;

CREATE OR REPLACE FUNCTION public.gv_cruce_fc_asig_refrescar_si_viejo(p_seg integer DEFAULT 180)
 RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_ult timestamptz;
begin
  select corrido_at into v_ult from public."GV_Cruce_FC_Asig_Corrida" where id = 1;
  if v_ult is null then select max(actualizado_at) into v_ult from public."GV_Cruce_FC_Asig"; end if;
  if v_ult is null or v_ult < now() - make_interval(secs => greatest(p_seg, 0)) then
    return public.gv_cruce_fc_asig_refrescar();
  end if;
  return -1;
end $function$;

-- gv_conciliacion_lista: parche sobre pg_get_functiondef (la tocan otras sesiones), reemplaza
--   left join public.gv_vista_facturacion_neto na on na.np = s.np
-- por
--   left join (select i.np, round(coalesce(sum(i.importe_ent * i.factor_web), 0::numeric), 2) as neto
--                from public.gv_vista_facturacion_neto_items i
--               where i.np in (select b.np from public."GV_Conciliacion_Facturacion" b)
--               group by i.np) na on na.np = s.np
-- Rollback: el reemplazo inverso.
