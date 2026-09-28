-- =============================================================================
-- Login de operarios por legajo + red de la empresa — ETAPAS 0 y 1 (2026-09-28).
-- Plan: docs/PLAN-LOGIN-OPERARIOS-RED.md. APLICADO en la base. Ninguna app lo usa todavía:
-- no cambia nada de lo que hoy funciona (pedido del dueño: "no rompas lo actual").
-- Edge Function: supabase/functions/login-operario (v2).
-- Probado 28/09: fuera de la red → 403; dentro (rango temporal) → sesión con rol operario y
-- legajo que la base lee con jwt_rol()/jwt_legajo(); 240 min + refresh; cierre nocturno
-- probado; usuario y rango de prueba borrados.
-- =============================================================================

-- ETAPA 0: inventario de escrituras con la clave pública (lo llena un Routine nocturno
-- 23:46 lun-sáb hasta el 03/10, desde los logs de la API, que duran 24 h).
create table if not exists public.seg_inventario_anon (
  dia date not null, ip text not null, org text, origen text,
  metodo text not null, ruta text not null, n integer not null,
  cargado_at timestamptz not null default now(),
  primary key (dia, ip, metodo, ruta)
);
alter table public.seg_inventario_anon enable row level security;
revoke all on public.seg_inventario_anon from anon, authenticated;

-- ETAPA 1
create table if not exists public.red_empresa (
  ip text primary key,            -- IP suelta o rango CIDR
  sede text, activo boolean not null default true, nota text,
  creado_at timestamptz not null default now()
);
alter table public.red_empresa enable row level security;
revoke all on public.red_empresa from anon, authenticated;
-- Semilla: las 3 IP de FichadaQR.config.ip_trabajo (falta confirmar sede de cada una).

create table if not exists public.seg_login_operario_log (
  id bigserial primary key, at timestamptz not null default now(),
  ip text, legajo text, app text, ok boolean not null, motivo text
);
alter table public.seg_login_operario_log enable row level security;
revoke all on public.seg_login_operario_log from anon, authenticated;

create or replace function public.ip_en_red_empresa(p_ip text) returns text
language plpgsql stable security definer set search_path = '' as $$
declare v text;
begin
  begin
    select coalesce(sede, 'red empresa') into v from public.red_empresa
     where activo and p_ip::inet <<= ip::cidr limit 1;
  exception when others then return null;
  end;
  return v;
end $$;
revoke all on function public.ip_en_red_empresa(text) from public, anon, authenticated;
grant execute on function public.ip_en_red_empresa(text) to service_role;

create or replace function public.jwt_rol() returns text
language sql stable set search_path = '' as $$
  select nullif(auth.jwt() -> 'app_metadata' ->> 'rol', '') $$;
create or replace function public.jwt_legajo() returns text
language sql stable set search_path = '' as $$
  select nullif(auth.jwt() -> 'app_metadata' ->> 'legajo', '') $$;
grant execute on function public.jwt_rol(), public.jwt_legajo() to anon, authenticated, service_role;

create or replace function public.cerrar_sesiones_operarios() returns integer
language plpgsql security definer set search_path = '' as $$
declare n integer;
begin
  delete from auth.sessions s using auth.users u
   where s.user_id = u.id and u.raw_app_meta_data ->> 'rol' = 'operario';
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function public.cerrar_sesiones_operarios() from public, anon, authenticated;
grant execute on function public.cerrar_sesiones_operarios() to service_role;
select cron.schedule('cerrar-sesiones-operarios', '30 2 * * *', 'select public.cerrar_sesiones_operarios();');  -- 23:30 AR

-- Rollback etapa 1:
--   select cron.unschedule('cerrar-sesiones-operarios');
--   drop function public.cerrar_sesiones_operarios(), public.jwt_rol(), public.jwt_legajo(), public.ip_en_red_empresa(text);
--   drop table public.seg_login_operario_log, public.red_empresa;
--   delete from auth.users where email like '%@operarios.interno';
