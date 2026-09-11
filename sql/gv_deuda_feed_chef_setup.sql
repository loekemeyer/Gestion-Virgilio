-- ============================================================================
-- Aviso de deuda en el portal de CHEF (idea 6064) — BACKEND (YA APLICADO 2026-09-11)
-- ============================================================================
--
-- QUÉ HACE
--   El portal de Chef (repo `paginach`, proyecto Supabase de Chef
--   nkhzocgdpwtgrmwleihr) lee, ANTES de que el cliente confirme el pedido, la
--   deuda que Gestión Virgilio sube ~1x por semana a `GV_Cuarentena_Fuente`
--   (tipo='deuda'). Sólo AVISA, no bloquea. Umbral $1.000. Filtra empresa='chef'.
--
-- CÓMO QUEDÓ (lo que efectivamente se corrió)
--   Chef YA tenía un FDW a Virgilio (server `virgilio_db`, user mapping para
--   `postgres` que conecta como el rol **`ch_ppp_reader`** de Virgilio). Así que
--   NO hizo falta crear rol nuevo ni user mapping: alcanzó con
--     (a) darle SELECT a ese rol sobre la view del feed EN VIRGILIO, y
--     (b) crear en CHEF la foreign table + la RPC get_mi_deuda.
--   (Se probó primero con un rol nuevo `chef_gv_reader`, pero el mapping viejo ya
--   apuntaba a `ch_ppp_reader`; se borró el rol nuevo y se usó el existente.)
--
-- SEGURIDAD
--   - `ch_ppp_reader` sólo suma SELECT sobre la view del feed; nada más.
--   - get_mi_deuda resuelve el cliente por `auth.uid()` en el backend, revocada
--     de anon, sólo `authenticated`.
--
-- ROLLBACK al pie.
-- ============================================================================


-- ====================  PART A — VIRGILIO (hrxfctzncixxqmpfhskv)  =============
-- Ya corrido por Claude. La view `public.gv_deuda_feed` la creó el lado LK.
grant usage on schema public to ch_ppp_reader;
grant select on public.gv_deuda_feed to ch_ppp_reader;

-- Chequeo (asumiendo el rol): debe dar 40 filas de chef.
--   grant ch_ppp_reader to current_user;
--   set role ch_ppp_reader;
--   select count(*) from public.gv_deuda_feed where empresa='chef';
--   reset role;


-- ======================  PART B — CHEF (nkhzocgdpwtgrmwleihr)  ===============
-- Server + user mapping (ch_ppp_reader) YA existían de un FDW previo. Sólo se
-- agregó la foreign table y la RPC:

create schema if not exists virgilio;

create foreign table if not exists virgilio.gv_deuda_feed (
  empresa    text,
  cod        text,
  deuda      numeric,
  cargado_at timestamptz
) server virgilio_db
  options (schema_name 'public', table_name 'gv_deuda_feed');

create or replace function public.get_mi_deuda()
returns table(deuda numeric, cargado_at timestamptz)
language sql
stable
security definer
set search_path = public, virgilio
as $$
  with mis_cods as (
    select distinct c.cod_cliente::text as cod
    from customers c
    where c.auth_user_id = auth.uid()
  )
  select coalesce(sum(f.deuda), 0)::numeric as deuda,
         max(f.cargado_at)                   as cargado_at
  from virgilio.gv_deuda_feed f
  join mis_cods m on m.cod = f.cod
  where f.empresa = 'chef';
$$;

revoke all on function public.get_mi_deuda() from public, anon;
grant execute on function public.get_mi_deuda() to authenticated;

-- Chequeo (Chef): trae filas => el FDW lee bien.
--   select postgres_fdw_disconnect_all();
--   select * from virgilio.gv_deuda_feed where empresa='chef' limit 3;


-- ============================  ROLLBACK  ====================================
-- En CHEF:
--   drop function if exists public.get_mi_deuda();
--   drop foreign table if exists virgilio.gv_deuda_feed;
--   -- NO tocar el server virgilio_db ni el user mapping: son de un FDW previo.
-- En VIRGILIO:
--   revoke select on public.gv_deuda_feed from ch_ppp_reader;
--   -- (dejar el usage on schema public: el rol ya lo tenía para su FDW previo)
-- ============================================================================
