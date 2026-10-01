-- v25.79 (Luis, 01/10): ALARMA de operario INACTIVO en los monitores.
-- El celular del operario, al llegar a 5 min de tiempo muerto, abre la alerta (gv_alerta_inactivo_abrir);
-- al registrar la próxima tarea la cierra (gv_alerta_inactivo_cerrar). La TV (monitor/tv.html) lee
-- gv_alertas_inactivo_vivas() cada pocos segundos y muestra el pop-up 15 s o hasta que se cierre.
create table if not exists public."GV_Alerta_Inactivo" (
  id bigserial primary key,
  legajo text not null,
  nombre text,
  abierta_en timestamptz not null default now(),
  cerrada_en timestamptz,
  dispositivo text
);
alter table public."GV_Alerta_Inactivo" enable row level security;
revoke all on public."GV_Alerta_Inactivo" from anon, authenticated;
create index if not exists gv_alerta_inactivo_abierta_idx on public."GV_Alerta_Inactivo" (abierta_en desc);
create index if not exists gv_alerta_inactivo_leg_idx on public."GV_Alerta_Inactivo" (legajo) where cerrada_en is null;

create or replace function public.gv_alerta_inactivo_abrir(p_legajo text, p_dispositivo text default null)
returns bigint language plpgsql security definer set search_path to 'public' as $f$
declare v_id bigint; v_leg text := nullif(btrim(p_legajo), ''); v_nom text;
begin
  if v_leg is null or v_leg in ('0','1') then return null; end if;
  -- una sola alerta viva por legajo (el celular puede reintentar o recargar)
  select id into v_id from public."GV_Alerta_Inactivo"
   where legajo = v_leg and cerrada_en is null and abierta_en > now() - interval '12 hours'
   order by id desc limit 1;
  if v_id is not null then return v_id; end if;
  select "Empleado" into v_nom from public."Empleados" where "Legajo"::text = v_leg limit 1;
  insert into public."GV_Alerta_Inactivo" (legajo, nombre, dispositivo)
  values (v_leg, coalesce(nullif(btrim(v_nom), ''), 'Legajo ' || v_leg), left(p_dispositivo, 80))
  returning id into v_id;
  return v_id;
end $f$;

create or replace function public.gv_alerta_inactivo_cerrar(p_legajo text)
returns int language plpgsql security definer set search_path to 'public' as $f$
declare n int;
begin
  update public."GV_Alerta_Inactivo" set cerrada_en = now()
   where legajo = nullif(btrim(p_legajo), '') and cerrada_en is null;
  get diagnostics n = row_count;
  return n;
end $f$;

create or replace function public.gv_alertas_inactivo_vivas()
returns table (id bigint, legajo text, nombre text, abierta_en timestamptz, cerrada boolean)
language sql stable security definer set search_path to 'public' as $f$
  select a.id, a.legajo, a.nombre, a.abierta_en, a.cerrada_en is not null
    from public."GV_Alerta_Inactivo" a
   where a.abierta_en > now() - interval '3 minutes'
   order by a.abierta_en;
$f$;

revoke all on function public.gv_alerta_inactivo_abrir(text, text) from public;
revoke all on function public.gv_alerta_inactivo_cerrar(text) from public;
revoke all on function public.gv_alertas_inactivo_vivas() from public;
grant execute on function public.gv_alerta_inactivo_abrir(text, text) to anon, authenticated;
grant execute on function public.gv_alerta_inactivo_cerrar(text) to anon, authenticated;
grant execute on function public.gv_alertas_inactivo_vivas() to anon, authenticated;
-- Rollback: drop function gv_alertas_inactivo_vivas(); drop function gv_alerta_inactivo_cerrar(text);
--           drop function gv_alerta_inactivo_abrir(text,text); drop table "GV_Alerta_Inactivo";
