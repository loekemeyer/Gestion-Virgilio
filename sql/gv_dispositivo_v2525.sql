-- v25.25 (Luis, 30/09): identificar el dispositivo (celular/PC) en eventos e ingresos.
-- Aplicado el 30/09. Forward-facing: columna nullable sin default; lo viejo queda NULL.
alter table public."Registros_Produccion_Virgilio" add column if not exists gv_dispositivo text;
create table if not exists public."GV_Dispositivo_Login" (
  id bigserial primary key, dispositivo text not null,
  tipo text, legajo text, email text, nombre text, metodo text,
  user_agent text, app_version text, created_at timestamptz not null default now());
alter table public."GV_Dispositivo_Login" enable row level security;
revoke all on public."GV_Dispositivo_Login" from anon, authenticated;
grant insert on public."GV_Dispositivo_Login" to anon, authenticated;
grant usage on sequence public."GV_Dispositivo_Login_id_seq" to anon, authenticated;
create policy gv_disp_login_insert on public."GV_Dispositivo_Login" for insert to anon, authenticated
  with check (length(dispositivo) between 8 and 64);
create index if not exists gv_disp_login_disp_idx on public."GV_Dispositivo_Login"(dispositivo, created_at desc);
create or replace view public.gv_dispositivos with (security_invoker = true) as
select dispositivo, min(created_at) primer_ingreso, max(created_at) ultimo_ingreso, count(*) ingresos,
       string_agg(distinct coalesce(nullif(nombre,''), legajo, email), ' · ') quienes,
       (array_agg(user_agent order by created_at desc))[1] user_agent,
       (array_agg(app_version order by created_at desc))[1] version
  from public."GV_Dispositivo_Login" group by dispositivo;
revoke all on public.gv_dispositivos from anon, authenticated;
-- Lectura (sólo por el MCP / postgres; anon no lee):
--   select * from public.gv_dispositivos order by ultimo_ingreso desc;
--   select gv_dispositivo, legajo, count(*) from public."Registros_Produccion_Virgilio"
--    where created_at >= current_date group by 1,2;
-- Rollback:
--   drop view public.gv_dispositivos; drop table public."GV_Dispositivo_Login";
--   alter table public."Registros_Produccion_Virgilio" drop column gv_dispositivo;  -- antes sacar el envío del front

-- v25.26 (Luis, 30/09): "si un mismo dispositivo loguea a multiples operarios que quede registrado".
-- Un renglón por (dispositivo, día) con 2+ operarios, cruzando ingresos y eventos (lo que llegue).
create or replace view public.gv_dispositivo_multi_operario with (security_invoker = true) as
with u as (
  select dispositivo, (created_at at time zone 'America/Argentina/Buenos_Aires')::date dia,
         coalesce(nullif(legajo,''), email) quien, coalesce(nullif(nombre,''), legajo, email) nombre,
         created_at ts, 'ingreso'::text fuente
    from public."GV_Dispositivo_Login"
  union all
  select r.gv_dispositivo, (r.created_at at time zone 'America/Argentina/Buenos_Aires')::date,
         r.legajo, r.legajo, r.created_at, 'evento'
    from public."Registros_Produccion_Virgilio" r
   where r.gv_dispositivo is not null and not public.es_legajo_test(r.legajo)
)
select dispositivo, dia, count(distinct quien) operarios, string_agg(distinct nombre, ' · ') quienes,
       min(ts) primero, max(ts) ultimo,
       (select l.user_agent from public."GV_Dispositivo_Login" l where l.dispositivo = u.dispositivo
         order by l.created_at desc limit 1) user_agent
  from u group by dispositivo, dia having count(distinct quien) > 1;
revoke all on public.gv_dispositivo_multi_operario from anon, authenticated;
-- Chequeo: select * from public.gv_dispositivo_multi_operario order by dia desc;
-- Probado en transacción abortada: 2 legajos en el mismo dispositivo -> 1 fila, operarios 2.
