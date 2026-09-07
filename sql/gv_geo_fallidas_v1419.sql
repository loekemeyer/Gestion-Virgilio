-- gv_geo_fallidas — v14.19 (2026-09-07) · Virgilio (hrxfctzncixxqmpfhskv)
--
-- EL PROBLEMA (defecto de la v14.16, encontrado el mismo día)
-- ==========================================================
-- `gv_geo_faltantes_padron` devuelve lo que falta **siempre en el mismo orden**
-- (`amba desc, empresa, cod`) y el geocodificador toma los primeros 40. Los fallos no se
-- guardaban en ningún lado, así que una dirección que no resuelve **vuelve a salir primera en
-- la corrida siguiente, y en la otra, y en la otra**.
--
-- Alcanza con que 40 seguidas no resuelvan para que la cola quede tapada: el cron sigue
-- corriendo, gasta sus 40 llamadas a Nominatim cada 10 minutos, y **todo lo que está detrás no
-- se intenta nunca**. Es un bloqueo de cabecera de cola clásico.
--
-- Medido: de 16:22 a 17:53 el log da seis corridas seguidas con `pedidas 40, ubicadas 0,
-- fallaron 40` y el mismo "1731 sin ubicar todavía". La cobertura se quedó clavada en 368 de
-- 2.307. Nominatim NO nos está bloqueando — se probó una consulta directa desde la base y
-- contesta 200 con resultado; el problema es nuestro.
--
-- LA SOLUCIÓN
-- ===========
-- Recordar los intentos. Una dirección que falló `GV_GEO_MAX_INTENTOS` veces sale de la cola y
-- deja pasar a la que viene. No se pierde: queda en la tabla con su último error, que es
-- justamente la lista de las que hay que arreglar a mano (para eso ya existe
-- `GV_Geo_Correccion`, y corregir ahí una dirección la devuelve a la cola porque cambia el
-- `dir_key`... o se le baja el contador con `gv_geo_reintentar()`).
--
-- Tres intentos y no uno: Nominatim tiene picos y la cascada del geocodificador prueba varias
-- formas de preguntar. Con tres, un fallo pasajero no condena una dirección para siempre.

create table if not exists public."GV_Geo_Fallidas" (
  cod            text not null,
  dir_key        text not null,
  intentos       integer not null default 1,
  ultimo_error   text,
  ultimo_intento timestamptz not null default now(),
  primary key (cod, dir_key)
);

alter table public."GV_Geo_Fallidas" enable row level security;

drop policy if exists gv_geo_fallidas_lectura on public."GV_Geo_Fallidas";
create policy gv_geo_fallidas_lectura on public."GV_Geo_Fallidas"
  for select to authenticated using (true);

comment on table public."GV_Geo_Fallidas" is
  'v14.19 — cuántas veces falló cada dirección al geocodificar. Sin esto una dirección que no '
  'resuelve vuelve a salir primera en cada corrida y tapa la cola: nada de lo que está detrás '
  'se llega a intentar nunca.';

-- Anota un fallo (la llama la Edge Function con service_role).
create or replace function public.gv_geo_marcar_fallo(p_cod text, p_dir_key text, p_error text)
returns integer
language sql
security definer
set search_path to 'public', 'pg_temp'
as $$
  insert into public."GV_Geo_Fallidas" (cod, dir_key, intentos, ultimo_error, ultimo_intento)
  values (coalesce(p_cod, ''), p_dir_key, 1, left(coalesce(p_error, ''), 300), now())
  on conflict (cod, dir_key) do update
    set intentos       = public."GV_Geo_Fallidas".intentos + 1,
        ultimo_error   = left(coalesce(excluded.ultimo_error, ''), 300),
        ultimo_intento = now()
  returning intentos;
$$;
revoke all on function public.gv_geo_marcar_fallo(text, text, text) from public, anon;

-- Devuelve a la cola lo que se dio por perdido (después de corregir direcciones a mano).
create or replace function public.gv_geo_reintentar(p_cod text default null)
returns integer
language sql
security definer
set search_path to 'public', 'pg_temp'
as $$
  with borradas as (
    delete from public."GV_Geo_Fallidas"
     where p_cod is null or cod = p_cod
    returning 1
  )
  select count(*)::integer from borradas;
$$;
revoke all on function public.gv_geo_reintentar(text) from public, anon;

-- ── La vista, ahora sin las que ya se intentaron de más ────────────────────────────────────
-- `GV_GEO_MAX_INTENTOS` = 3, escrito en la propia vista para no agregar otra tabla de config.
create or replace view public.gv_geo_faltantes_padron
with (security_invoker = true) as
  select 'PADRON'::text as fuente, d.cod, d.razon_social, d.direccion,
         d.localidad as barrio, d.zona_expreso as zona, d.dir_key,
         coalesce(x.direccion_ok, gv_dir_geo_query(d.direccion)) as dir_query,
         coalesce(x.barrio_ok, d.localidad) as barrio_geo,
         (x.dir_key is not null) as corregida,
         null::date as fecha_entrega,
         d.empresa, d.provincia, d.amba
    from public."GV_Clientes_Direcciones" d
    left join public."GV_Geo_Correccion" x on x.dir_key = d.dir_key
    left join public."GV_Geo_Cliente"    c on c.cod = d.cod and c.dir_key = d.dir_key
    left join public."PPP_Geo"           g on g.dir_key = d.dir_key and g.lat is not null
    left join public."GV_Geo_Fallidas"   f on f.cod = d.cod and f.dir_key = d.dir_key
   where gv_dir_geo_query(d.direccion) is not null
     and c.cod is null
     and g.dir_key is null
     and coalesce(f.intentos, 0) < 3          -- ← lo que destapa la cola
     and lower(coalesce(d.zona_expreso, '')) not like '%retira%'
   order by d.amba desc, d.empresa, d.cod;

comment on view public.gv_geo_faltantes_padron is
  'v14.19 — direcciones del padrón sin ubicación, AMBA primero, SIN las que ya fallaron 3 veces '
  '(esas taparían la cola). Las descartadas están en GV_Geo_Fallidas con su último error.';

-- Para mirar qué quedó afuera y por qué.
create or replace view public.gv_geo_no_resueltas
with (security_invoker = true) as
  select f.cod, d.empresa, d.razon_social, d.direccion, d.localidad, d.provincia, d.amba,
         f.intentos, f.ultimo_error, f.ultimo_intento
    from public."GV_Geo_Fallidas" f
    left join public."GV_Clientes_Direcciones" d on d.cod = f.cod and d.dir_key = f.dir_key
   where f.intentos >= 3
   order by d.amba desc nulls last, f.intentos desc;

comment on view public.gv_geo_no_resueltas is
  'v14.19 — las direcciones que el geocodificador dio por perdidas. Es la lista para arreglar a '
  'mano en GV_Geo_Correccion; después, gv_geo_reintentar() las devuelve a la cola.';

-- ROLLBACK
--   (restaurar la vista de sql/gv_padron_direcciones_v1416.sql, sin el join a GV_Geo_Fallidas)
--   drop view if exists public.gv_geo_no_resueltas;
--   drop function if exists public.gv_geo_reintentar(text);
--   drop function if exists public.gv_geo_marcar_fallo(text, text, text);
--   drop table if exists public."GV_Geo_Fallidas";
