-- v22.23 (Luis, 24/09/2026) — switch «Web» por importado en Pedidos Importación.
-- OFF = el artículo NO aparece en la página de LK ni se puede pedir (products.active=false).
-- Gestión no tiene FDW hacia LK: la lista vive acá y la APLICA LK con su sync
-- (sync_reingresos_virgilio → sync_web_ocultos_virgilio, cron 39, cada 5 min).
-- LK sólo reactiva lo que ocultó este switch (web_oculto_gestion): un inactivo puesto a mano no se toca.
-- Mismo día: cron 39 de LK pasó de '9,39 * * * *' a '1-59/5 * * * *', y get_reingresos /
-- get_reingresos_chef filtran fecha_reingreso is not null (Luis: sin fecha no hay cartel).

-- ===================== VIRGILIO (hrxfctzncixxqmpfhskv) =====================
create table if not exists public."GV_Web_Oculto" (
  cod text primary key, motivo text, pedido_por text, creado_en timestamptz not null default now());
alter table public."GV_Web_Oculto" enable row level security;
revoke all on public."GV_Web_Oculto" from anon, authenticated;

create or replace function public.gv_web_oculto_set(p_cod text, p_visible boolean)
returns boolean language plpgsql security definer set search_path to 'public' as $f$
declare v_cod text := public.gv_cod_stock(p_cod);
begin
  if not (public.es_supervisor_virgilio() or public.gv_es_supervisor_o_servicio()) then
    raise exception 'Solo un supervisor puede ocultar un articulo de la pagina';
  end if;
  if coalesce(v_cod,'') = '' then raise exception 'codigo vacio'; end if;
  if p_visible then
    delete from public."GV_Web_Oculto" where cod = v_cod;
  else
    insert into public."GV_Web_Oculto" (cod, motivo, pedido_por)
    values (v_cod, 'oculto desde Importados', coalesce(auth.jwt()->>'email','?'))
    on conflict (cod) do nothing;
  end if;
  return p_visible;
end $f$;

create or replace function public.gv_web_ocultos()
returns table(cod text) language sql stable security definer set search_path to 'public' as $f$
  select x.cod from public."GV_Web_Oculto" x order by 1;
$f$;

create or replace function public.lk_web_ocultos_feed()
returns table(cod text) language sql stable security definer set search_path to 'public' as $f$
  select x.cod from public."GV_Web_Oculto" x;
$f$;
create or replace view public.v_lk_web_ocultos with (security_invoker = true) as
  select cod from public.lk_web_ocultos_feed();
revoke all on public.v_lk_web_ocultos from anon, authenticated;
grant select on public.v_lk_web_ocultos to lk_ppp_reader;
revoke execute on function public.lk_web_ocultos_feed() from public, anon, authenticated;
grant execute on function public.lk_web_ocultos_feed() to lk_ppp_reader;
revoke execute on function public.gv_web_oculto_set(text,boolean) from public, anon;
grant execute on function public.gv_web_oculto_set(text,boolean) to authenticated, service_role;
revoke execute on function public.gv_web_ocultos() from public;
grant execute on function public.gv_web_ocultos() to anon, authenticated, service_role;

-- ===================== LK (kwkclwhmoygunqmlegrg) =====================
-- create foreign table virgilio.v_lk_web_ocultos (cod text)
--   server virgilio_db options (schema_name 'public', table_name 'v_lk_web_ocultos');
-- create table public.web_oculto_gestion (cod text primary key, oculto_at timestamptz not null default now());
-- alter table public.web_oculto_gestion enable row level security;
-- create function public.sync_web_ocultos_virgilio(): lee la lista (1 lectura FDW), pone
--   active=false a los products activos de la lista (y los anota en web_oculto_gestion), y
--   devuelve active=true SOLO a los anotados que salieron de la lista. Si Virgilio no contesta, no toca nada.
-- sync_reingresos_virgilio(): se le agregó `perform public.sync_web_ocultos_virgilio();`
--   antes de su exception final (parche sobre pg_get_functiondef, idempotente).
-- Probado en transacción abortada: ocultar 360E → active=false + anotado; sacarlo de la lista →
--   active=true + desanotado; 599E apagado A MANO siguió inactivo.
-- Rollback LK: sacar la línea `perform` de sync_reingresos_virgilio y
--   update products p set active=true from web_oculto_gestion w where p.cod=w.cod;

-- ===================== v22.26 (Luis, 24/09): POR EMPRESA + CHEF =====================
-- GV_Web_Oculto pasa a PK (cod, empresa) con empresa 'LK'|'CH' (el mismo número puede ser
-- otro artículo en cada página). gv_web_oculto_set(p_cod, p_visible, p_empresa default 'LK');
-- gv_web_ocultos() y v_lk_web_ocultos devuelven (cod, empresa). El front dibuja un switch
-- por empresa según la marca del importado (LK/Loke → LK, CH → Chef).
-- LK: web_oculto_gestion pasa a PK (cod, tabla) con tabla 'products'|'loke_products'|'chef';
-- sync_web_ocultos_virgilio aplica LK sobre products y loke_products (línea Loke: 110, 119E…)
-- y CH sobre chef_ext.products (FDW chef_db, usuario loke_reader) en bloque propio.
-- Probado en transacción abortada: 360E (products) y 110 (loke_products) se ocultan y vuelven.
--
-- ⚠ FALTA, en el SQL editor de CHEF (nkhzocgdpwtgrmwleihr) — sin esto la parte de Chef
-- falla sola (permission denied) y LK sigue andando:
--   grant update (active) on public.products to loke_reader;
-- Es un grant por COLUMNA: loke_reader sólo puede cambiar active, nada más de products.
