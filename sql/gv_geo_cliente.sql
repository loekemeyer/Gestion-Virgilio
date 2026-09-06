-- ============================================================================
-- v13.40 — Ubicación por CÓDIGO de cliente + lista de lo que falta ubicar
--
-- POR QUÉ (dueño, 2026-09-06: "todo tenés que tener todas las ubicaciones"):
--   · la única ubicación era `PPP_Geo`, cuya clave es el TEXTO de la dirección
--     normalizado. Si ISIS escribe "Rivadavia 18059" un día y "Av Rivadavia
--     18059" otro, es una clave nueva y la ubicación se "pierde";
--   · sólo se geocodificaba cuando un supervisor abría 📍 Mapa de zonas y tocaba
--     el botón: la última corrida era del 21/08 y quedaban 43 de 54 direcciones
--     programadas sin ubicar. Sin ubicación, el orden de carga manda ese pedido
--     al final del reparto y el camión se carga mal.
--
-- ⚠ `PPP_Geo` es COMPARTIDA con Producción Virgilio (la usa su index.html): acá
--   no se toca. La Edge Function sólo le AGREGA filas. La fuente canónica de
--   Gestión es `GV_Geo_Cliente`.
--
-- Lo consume la Edge Function `gv-geocodificar` (cron 75, cada 6 h) y el front
-- (`pppRefreshGeo` → `_pppGeoDe`).
-- ============================================================================

-- La misma limpieza que hace el front (`_zgDirQuery`), pero acá manda el backend:
-- un pedido por expreso llega como "Exp. Arnes — AUSTRALIA 2959, Barracas
-- (Rivadavia 3663- Mar Del Plata)" y lo único ubicable es el depósito del
-- expreso; el nombre del expreso adelante y el domicilio final del cliente entre
-- paréntesis (que está en otra provincia) hacen que no encuentre nada.
create or replace function public.gv_dir_geo_query(p_dir text)
returns text language sql immutable set search_path to 'public', 'pg_temp' as $$
  select nullif(btrim(regexp_replace(
           regexp_replace(btrim(coalesce(p_dir, '')), '^\s*exp(reso)?\.?\s+[^—–-]{0,30}\s*[—–]\s*', '', 'i'),
           '\s*\([^)]*\)\s*$', '')), '');
$$;

-- La MISMA clave que arma el front (`_rtDirKey` = _rtNorm(dir)|_rtNorm(barrio)).
create or replace function public.gv_dir_key(p_dir text, p_barrio text)
returns text language sql immutable set search_path to 'public', 'pg_temp' as $$
  select lower(btrim(regexp_replace(coalesce(p_dir, ''), '\s+', ' ', 'g'))) || '|' ||
         lower(btrim(regexp_replace(coalesce(p_barrio, ''), '\s+', ' ', 'g')));
$$;

-- La clave NO puede ser sólo el cód: hay clientes con varias direcciones de
-- entrega (cód 1792 Dapelo entrega en Villa Crespo, Almagro y Colegiales). Con
-- (cód, dirección) la ventaja se mantiene: si ISIS cambia el tipeo, la fila
-- vieja del MISMO cód sigue ahí y el front cae en ella.
create table if not exists public."GV_Geo_Cliente" (
  cod            text not null,
  dir_key        text not null,
  razon_social   text,
  direccion      text,
  barrio         text,
  lat            double precision not null,
  lng            double precision not null,
  comp           jsonb,                            -- partido/barrio oficiales de Nominatim
  fuente         text default 'nominatim',
  manual         boolean not null default false,   -- puesta a mano: el cron NO la pisa
  usos           integer not null default 1,
  geocoded_at    timestamptz not null default now(),
  actualizado_at timestamptz not null default now(),
  primary key (cod, dir_key)
);
comment on table public."GV_Geo_Cliente" is
  'v13.40 — ubicación por (cód de cliente, dirección). Fuente canónica de Gestión; PPP_Geo (por dirección sola) es compartida con Producción y sólo se le agregan filas. manual=true la congela: el cron no la pisa.';
create index if not exists gv_geo_cliente_cod_idx on public."GV_Geo_Cliente" (cod);

alter table public."GV_Geo_Cliente" enable row level security;
drop policy if exists gv_geo_cliente_sel on public."GV_Geo_Cliente";
drop policy if exists gv_geo_cliente_ins on public."GV_Geo_Cliente";
drop policy if exists gv_geo_cliente_upd on public."GV_Geo_Cliente";
create policy gv_geo_cliente_sel on public."GV_Geo_Cliente" for select to anon, authenticated using (true);
create policy gv_geo_cliente_ins on public."GV_Geo_Cliente" for insert to authenticated with check (true);
create policy gv_geo_cliente_upd on public."GV_Geo_Cliente" for update to authenticated using (true) with check (true);
grant select on public."GV_Geo_Cliente" to anon, authenticated;
grant insert, update on public."GV_Geo_Cliente" to authenticated;

-- Ubicación de un cliente cuando la dirección exacta no está: la que más se usó
-- y, a igualdad, la última. Es el paracaídas contra el cambio de tipeo en ISIS.
create or replace function public.gv_geo_de_cliente(p_cod text)
returns table (lat double precision, lng double precision, dir_key text, direccion text)
language sql stable set search_path to 'public', 'pg_temp' as $$
  select c.lat, c.lng, c.dir_key, c.direccion
    from public."GV_Geo_Cliente" c
   where c.cod = btrim(coalesce(p_cod, '')) and btrim(coalesce(p_cod, '')) <> ''
   order by c.usos desc, c.actualizado_at desc
   limit 1;
$$;
grant execute on function public.gv_geo_de_cliente(text) to anon, authenticated;

create or replace view public.gv_geo_faltantes
with (security_invoker = true) as
with prog as (
  select 'ISIS'::text as fuente, i.cod, i.razon_social, i.direccion, i.barrio, i.zona,
         left(btrim(i.fecha_entrega::text), 10)::date as fecha_entrega
    from public.gv_ppp_programacion_diaria i
   where btrim(coalesce(i.tanda, '')) <> ''
     and btrim(i.fecha_entrega::text) ~ '^\d{4}-\d{2}-\d{2}'
     and left(btrim(i.fecha_entrega::text), 10)::date >= current_date - 7
  union all
  select 'WEB', w.cod_cliente, w.razon_social, w.direccion, w.barrio, w.zona, w.fecha_entrega
    from public."PPP_Web_Programacion" w
   where btrim(coalesce(w.tanda, '')) <> ''
     and w.fecha_entrega >= current_date - 7
), uno as (
  select distinct on (public.gv_dir_key(p.direccion, p.barrio))
         p.fuente, btrim(coalesce(p.cod, '')) as cod, p.razon_social, p.direccion, p.barrio, p.zona,
         public.gv_dir_key(p.direccion, p.barrio) as dir_key,
         public.gv_dir_geo_query(p.direccion) as dir_query,
         p.fecha_entrega
    from prog p
   where public.gv_dir_geo_query(p.direccion) is not null
     and lower(coalesce(p.zona, '')) not like '%retira%'
   order by public.gv_dir_key(p.direccion, p.barrio), p.fecha_entrega
)
select u.*
  from uno u
  left join public."PPP_Geo" g on g.dir_key = u.dir_key and g.lat is not null
  left join public."GV_Geo_Cliente" c on c.cod = u.cod and c.dir_key = u.dir_key
 where g.dir_key is null and c.cod is null;

comment on view public.gv_geo_faltantes is
  'v13.40 — direcciones programadas (ISIS + web, desde 7 días atrás) sin ubicación ni por (cód, dirección) ni por dirección. dir_query es la dirección limpia para el geocodificador. La consume la Edge Function gv-geocodificar.';
grant select on public.gv_geo_faltantes to anon, authenticated;

-- Bitácora de cada corrida, para darse cuenta si el cron deja de andar (mismo
-- criterio que GV_Tandas_Auto_Log).
create table if not exists public."GV_Geo_Log" (
  id          bigserial primary key,
  corrida_en  timestamptz not null default now(),
  estado      text not null,            -- ok | sin_faltantes | error
  pedidas     integer not null default 0,
  ubicadas    integer not null default 0,
  fallaron    integer not null default 0,
  motivo      text,
  detalle     jsonb
);
alter table public."GV_Geo_Log" enable row level security;
drop policy if exists gv_geo_log_sel on public."GV_Geo_Log";
create policy gv_geo_log_sel on public."GV_Geo_Log" for select to authenticated using (true);
grant select on public."GV_Geo_Log" to authenticated;
grant usage, select on sequence public."GV_Geo_Log_id_seq" to authenticated;

-- ── Cron (jobid 75): cada 6 h, en el minuto 20 ──────────────────────────────
-- select cron.schedule('gv-geocodificar', '20 */6 * * *', $CRON$
--   select net.http_post(
--     url     := 'https://hrxfctzncixxqmpfhskv.supabase.co/functions/v1/gv-geocodificar',
--     headers := jsonb_build_object(
--                  'Content-Type', 'application/json',
--                  'Authorization', 'Bearer ' || (select v from lecturacvs.app_secrets where k = 'SUPABASE_SERVICE_ROLE_KEY')),
--     body    := '{}'::jsonb,
--     timeout_milliseconds := 150000);
-- $CRON$);
--
-- Apagarlo:  select cron.alter_job(75, active := false);
-- A mano:    el mismo net.http_post de arriba, con body '{"max": 40}'.
--
-- ROLLBACK COMPLETO:
--   select cron.unschedule(75);
--   drop view public.gv_geo_faltantes;
--   drop function public.gv_geo_de_cliente(text);
--   drop table public."GV_Geo_Cliente";
--   drop table public."GV_Geo_Log";
--   drop function public.gv_dir_geo_query(text);
--   drop function public.gv_dir_key(text, text);
--   (PPP_Geo queda como está: sólo se le agregaron filas, ninguna se modificó.)
