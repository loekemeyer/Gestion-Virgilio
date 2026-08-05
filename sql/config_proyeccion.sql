-- =====================================================================
-- config_proyeccion.sql — parámetros de la proyección editables desde la app (v7.55)
--
-- La proyección que alimenta el generador de OCs se calcula en PáginaLK
-- (proyecto Supabase "loekemeyer's web", `kwkclwhmoygunqmlegrg`) con
-- `fn_proyeccion_madre_emp` sobre `sales_lines`, y Virgilio la baja a `proyeccion_madre`
-- con `refresh_proyeccion_madre()` (ver `sql/refresh_proyeccion_madre.sql`).
--
-- v7.55: dos parámetros de esa proyección pasan a ser EDITABLES desde la app
-- (pantalla ⚙ Configurar parámetros → 📈 Parámetros de la proyección):
--   • PERÍODO a contemplar (meses): cuántos meses de ventas mirar (default 24).
--   • SUAVIZAR ANÓMALOS (bool): si descarta los picos "one-off" (un pedido puntual
--     mucho mayor que el promedio, aislado) a favor del promedio. Default true =
--     comportamiento histórico. Off = usa el promedio crudo (los picos inflan).
--
-- ── (A) PáginaLK — la función acepta los parámetros ─────────────────────────────
-- `fn_proyeccion_madre_emp(p_emp text, p_meses int default 24, p_suavizar boolean default true)`
--   • ventana: ... between mm.endm - (greatest(p_meses,1)-1) and mm.endm
--   • disr:    sum(case when p_suavizar and <pico anómalo> then v else 0 end)
-- Defaults preservan EXACTO el resultado previo. Migración en ese proyecto:
--   `fn_proyeccion_madre_emp_params_periodo_suavizar`. Verificado: default 24/true =
--   372 códigos / 20.225 cajas (igual que antes); 12 meses = 363 / 19.052; sin suavizar
--   = 372 / 28.329 (los picos inflan → confirma el suavizado).
--
-- ── (B) Virgilio — tabla de config + refresh que la lee ─────────────────────────
-- Tabla `Config_Proyeccion` (una sola fila, id=1) con `meses` y `suavizar`. RLS: anon+
-- authenticated LEEN; authenticated ESCRIBE (la app con sesión de supervisor). El
-- `refresh_proyeccion_madre()` lee esa fila y arma la URL con `&p_meses=..&p_suavizar=..`.
-- Se otorgó `execute` del refresh a `authenticated` para que la app pueda **recalcular en
-- el momento** al guardar (botón "💾 Guardar y recalcular" hace PATCH de Config_Proyeccion
-- + POST /rpc/refresh_proyeccion_madre).
--
-- ⚠ La definición VIVA está en las migraciones de Supabase; esta es la copia del repo.
-- =====================================================================

-- (B) Virgilio: tabla de parámetros + RLS.
create table if not exists public."Config_Proyeccion" (
  id int primary key default 1,
  meses int not null default 24,
  suavizar boolean not null default true,
  actualizado timestamptz not null default now(),
  constraint config_proy_single check (id = 1)
);
insert into public."Config_Proyeccion" (id, meses, suavizar) values (1, 24, true) on conflict (id) do nothing;
alter table public."Config_Proyeccion" enable row level security;
drop policy if exists config_proy_read on public."Config_Proyeccion";
drop policy if exists config_proy_write on public."Config_Proyeccion";
create policy config_proy_read  on public."Config_Proyeccion" for select to anon, authenticated using (true);
create policy config_proy_write on public."Config_Proyeccion" for all    to authenticated using (true) with check (true);

-- (B) el refresh lee la config y pasa los parámetros — ver sql/refresh_proyeccion_madre.sql
--     (versión v7.55: agrega `select meses,suavizar ... from Config_Proyeccion` y los concatena
--     a la URL del GET), y:
grant execute on function public.refresh_proyeccion_madre() to authenticated;

-- (A) PáginaLK (proyecto kwkclwhmoygunqmlegrg): la firma nueva de la función.
--   drop function if exists public.fn_proyeccion_madre_emp(text);
--   create function public.fn_proyeccion_madre_emp(p_emp text, p_meses int default 24, p_suavizar boolean default true)
--     ... (ventana p_meses + disruptsum condicionado a p_suavizar) ...
--   grant execute on function public.fn_proyeccion_madre_emp(text,int,boolean) to anon, authenticated;
