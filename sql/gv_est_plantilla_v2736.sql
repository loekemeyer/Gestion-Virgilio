-- v27.36 · Plantillas de la Est. Madre y de Costos (Luis, 06/10/2026).
-- «Subir Estadística Madre» / «Subir Costos» en la pestaña Est. Madre de Stock y Compras guardan acá
-- el ORDEN de los códigos y el TIPO de cada uno (número o texto: 505 vs '026'), una fila por hoja:
--   madre_lk  = hoja «Loeke Madre…» (columna «Cod Nuevo Isis»)
--   madre_ch  = hoja «Chef Madre…» / «Chef Master» (columna «Cod. Isis»)
--   costos_lk = bloque «Loeke» de «Aportes Gastos» (o el «costo lk final» suelto)
--   costos_ch = bloque «Chef» de «Aportes Gastos»
-- filas = [{c: código o null (renglón en blanco / título), n: true si es número, d: descripción, t: título}]
-- Lo arma el navegador (estadisticas.js); la base sólo lo guarda. Sólo supervisor.
-- Rollback: drop function public.gv_est_plantilla_guardar(text,text,text,jsonb,jsonb);
--           drop function public.gv_est_plantilla_leer(); drop table public."GV_Est_Plantilla";

create table if not exists public."GV_Est_Plantilla" (
  clave       text primary key check (clave in ('madre_lk','madre_ch','costos_lk','costos_ch')),
  archivo     text,
  hoja        text,
  filas       jsonb not null,
  meta        jsonb,
  subido_por  text,
  subido_en   timestamptz not null default now()
);
alter table public."GV_Est_Plantilla" enable row level security;
revoke all on public."GV_Est_Plantilla" from anon, authenticated;

create or replace function public.gv_est_plantilla_guardar(p_clave text, p_archivo text, p_hoja text, p_filas jsonb, p_meta jsonb default null)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare n int;
begin
  if not (es_supervisor_virgilio() or gv_es_supervisor_o_servicio()) then raise exception 'SUPERVISOR: sólo un supervisor puede subir la plantilla'; end if;
  if p_clave not in ('madre_lk','madre_ch','costos_lk','costos_ch') then raise exception 'clave inválida: %', p_clave; end if;
  if jsonb_typeof(p_filas) <> 'array' then raise exception 'filas tiene que ser una lista'; end if;
  select count(*) into n from jsonb_array_elements(p_filas) e where coalesce(e->>'c','') <> '';
  if n < 5 then raise exception 'la plantilla % trae % códigos: no se guarda', p_clave, n; end if;
  insert into public."GV_Est_Plantilla"(clave, archivo, hoja, filas, meta, subido_por, subido_en)
  values (p_clave, p_archivo, p_hoja, p_filas, p_meta, coalesce(auth.jwt()->>'email','?'), now())
  on conflict (clave) do update set archivo = excluded.archivo, hoja = excluded.hoja, filas = excluded.filas,
    meta = excluded.meta, subido_por = excluded.subido_por, subido_en = excluded.subido_en;
  return jsonb_build_object('clave', p_clave, 'codigos', n, 'filas', jsonb_array_length(p_filas));
end $$;

create or replace function public.gv_est_plantilla_leer()
returns table(clave text, archivo text, hoja text, filas jsonb, meta jsonb, subido_por text, subido_en timestamptz)
language sql stable security definer set search_path = public, pg_temp as $$
  select clave, archivo, hoja, filas, meta, subido_por, subido_en from public."GV_Est_Plantilla"
   where (es_supervisor_virgilio() or gv_es_supervisor_o_servicio());
$$;

revoke all on function public.gv_est_plantilla_guardar(text,text,text,jsonb,jsonb) from public, anon;
revoke all on function public.gv_est_plantilla_leer() from public, anon;
grant execute on function public.gv_est_plantilla_guardar(text,text,text,jsonb,jsonb) to authenticated, service_role;
grant execute on function public.gv_est_plantilla_leer() to authenticated, service_role;
