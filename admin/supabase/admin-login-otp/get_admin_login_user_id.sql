-- Dependencia de la Edge Function admin-login-otp (proyecto Supabase LK).
-- Resuelve el user_id del admin del Panel Web LK por mail, en O(1) (índice de
-- auth.users). Reemplaza el listUsers({perPage:200}) que fallaba con 500: LK
-- tiene >1200 usuarios (clientes del sitio comercial) y el recipient quedaba
-- fuera de la primera página → afectaba TANTO al OTP como al bridge.
--
-- SECURITY DEFINER porque auth.users no es accesible por PostgREST con la anon
-- key. Solo la llama el service_role (la Edge Function); se revoca a todo el resto.
--
-- Aplicada como migración `admin_login_user_id_lookup` (2026-09-02).
create or replace function public.get_admin_login_user_id()
returns uuid
language sql
security definer
set search_path = public, auth
as $$
  select id from auth.users where lower(email) = 'loekemeyer.n8n@gmail.com' limit 1;
$$;

revoke all on function public.get_admin_login_user_id() from public, anon, authenticated;
grant execute on function public.get_admin_login_user_id() to service_role;
