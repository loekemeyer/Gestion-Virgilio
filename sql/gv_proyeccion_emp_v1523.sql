-- v15.23 — Proyección por empresa para Pedidos Importación (YA APLICADO 2026-09-11). Detalle: docs/SUPABASE-GESTION-VIRGILIO.md §3.bm.15
--
-- ===== VIRGILIO (hrxfctzncixxqmpfhskv) =====
create table if not exists public."GV_Proyeccion_Emp" (
  cod text not null, empresa text not null check (empresa in ('lk','chef')),
  proy_cajas_mes numeric not null default 0, actualizado timestamptz not null default now(),
  primary key (cod, empresa));
alter table public."GV_Proyeccion_Emp" enable row level security;
create policy gv_proy_emp_read on public."GV_Proyeccion_Emp" for select to anon, authenticated using (true);
create policy gv_proy_emp_writer on public."GV_Proyeccion_Emp" for all to lk_ppp_reader using (true) with check (true);
grant select on public."GV_Proyeccion_Emp" to anon, authenticated;
grant select, insert, update, delete on public."GV_Proyeccion_Emp" to lk_ppp_reader;
-- v_importados_ordenes: igual a v15.11 salvo el CTE `pe` (GV_Proyeccion_Emp por empresa) que reemplaza a `proy`
-- (proyeccion_madre); est_madre_live = proy_cajas_mes × uni_x_caja; est_madre_eff = coalesce(override, live, seed, 0).
-- ventas_mensuales_cod(p_cod, p_meses, p_empresa default null): agrega &p_empresa=lk|chef a la URL del feed de LK.
--
-- ===== LK (kwkclwhmoygunqmlegrg) =====
-- _fn_proy_window_emp(p_meses, p_emp): copia de _fn_proy_window con `sl.empresa = p_emp`.
-- fn_proyeccion_importados_emp(): p6/p12 por empresa (lk, chef) → (cod, empresa, proy_cajas_mes).
-- fn_ventas_mensuales_virgilio(p_cod, p_meses default 6, p_empresa default null): se dropeó la firma de 2 args.
-- create foreign table virgilio."GV_Proyeccion_Emp" (cod text, empresa text, proy_cajas_mes numeric, actualizado timestamptz)
--   server virgilio_db options (schema_name 'public', table_name 'GV_Proyeccion_Emp');
-- sync_proyeccion_emp_virgilio(): temp → delete where cod is not null → insert (abort si 0 filas).
-- select cron.schedule('sync-proyeccion-emp-virgilio', '25 9 * * 3', 'select public.sync_proyeccion_emp_virgilio();');
--
-- Chequeo: select cod_art, marca, est_madre_fuente, est_madre_eff from v_importados_ordenes where gv_cod_stock(cod_art) in ('437E','438E','809E');
