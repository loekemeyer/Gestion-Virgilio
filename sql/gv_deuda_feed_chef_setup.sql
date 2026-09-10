-- ============================================================================
-- Aviso de deuda en el portal de CHEF (idea 6064) — BACKEND, setup manual
-- ============================================================================
--
-- QUÉ HACE
--   Deja que el portal de Chef (repo `paginach`, proyecto Supabase de Chef
--   nkhzocgdpwtgrmwleihr) lea, ANTES de que el cliente confirme el pedido, la
--   deuda que Gestión Virgilio sube ~1x por semana a `GV_Cuarentena_Fuente`
--   (tipo='deuda'). Sólo AVISA, no bloquea. Umbral $1.000. Filtra empresa='chef'.
--
-- POR QUÉ ES MANUAL
--   El lado LK ya está hecho y en producción (view `gv_deuda_feed` en Virgilio +
--   RPC `get_mi_deuda()` en LK, que lee por el FDW `virgilio_db`/rol
--   `lk_ppp_reader`). Para Chef falta lo mismo, pero el proyecto Supabase de Chef
--   NO es alcanzable desde la sesión de Claude (MCP sólo llega a Virgilio, LK y
--   Costos), así que este bloque lo corre el dueño a mano: PART A en el SQL editor
--   de VIRGILIO, PART B en el SQL editor de CHEF.
--
-- SEGURIDAD
--   - Rol nuevo `chef_gv_reader` en Virgilio: SELECT sólo sobre la view del feed,
--     nada más (no reusa `lk_ppp_reader` para no compartir su credencial).
--   - Elegir una password fuerte y usar la MISMA en PART A y PART B. NO commitear
--     la password a ningún repo: reemplazar el placeholder <PASSWORD_CHEF_READER>
--     al pegar en el editor.
--   - La RPC `get_mi_deuda()` de Chef resuelve el cliente por `auth.uid()` en el
--     backend (no recibe el código del front), así que un cliente no puede leer la
--     deuda de otro. Se le revoca a `anon`; queda sólo `authenticated`.
--
-- ROLLBACK: al pie del archivo.
-- ============================================================================


-- ====================  PART A — correr en VIRGILIO  =========================
-- Proyecto Control Partes Talleristas (hrxfctzncixxqmpfhskv).
-- La view `public.gv_deuda_feed` YA existe (la creó el lado LK). Acá sólo se
-- agrega un rol de sólo-lectura dedicado a Chef y se le da SELECT sobre esa view.

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'chef_gv_reader') then
    -- Reemplazar <PASSWORD_CHEF_READER> por una password fuerte (la misma que en PART B).
    create role chef_gv_reader with login password '<PASSWORD_CHEF_READER>';
  end if;
end $$;

grant usage on schema public to chef_gv_reader;
grant select on public.gv_deuda_feed to chef_gv_reader;

-- Chequeo: debe devolver 40 filas de chef (o las que haya cargadas hoy).
-- set role chef_gv_reader;
-- select count(*) from public.gv_deuda_feed where empresa='chef';
-- reset role;


-- ======================  PART B — correr en CHEF  ===========================
-- Proyecto Supabase de Chef (nkhzocgdpwtgrmwleihr), SQL editor (rol postgres).

create extension if not exists postgres_fdw;

-- 1) Server hacia Virgilio (idéntico al `virgilio_db` que ya usa LK).
do $$
begin
  if not exists (select 1 from pg_foreign_server where srvname = 'virgilio_db') then
    create server virgilio_db
      foreign data wrapper postgres_fdw
      options (host 'db.hrxfctzncixxqmpfhskv.supabase.co', port '5432',
               dbname 'postgres', sslmode 'require');
  end if;
end $$;

-- 2) User mapping: postgres (dueño de las RPC SECURITY DEFINER) se conecta como
--    el rol de sólo-lectura de Virgilio. Reemplazar <PASSWORD_CHEF_READER>.
do $$
begin
  if not exists (
    select 1 from pg_user_mappings
    where srvname = 'virgilio_db' and usename = 'postgres'
  ) then
    create user mapping for postgres server virgilio_db
      options (user 'chef_gv_reader', password '<PASSWORD_CHEF_READER>');
  end if;
end $$;

-- 3) Esquema + foreign table que apunta a la view del feed en Virgilio.
create schema if not exists virgilio;

create foreign table if not exists virgilio.gv_deuda_feed (
  empresa    text,
  cod        text,
  deuda      numeric,
  cargado_at timestamptz
) server virgilio_db
  options (schema_name 'public', table_name 'gv_deuda_feed');

-- 4) RPC que llama el front del portal de Chef. Resuelve el cliente por
--    auth.uid() (no confía en el front) y suma su deuda empresa='chef'.
--    OJO: si en el proyecto de Chef la tabla de vínculo NO es `user_customer_links`
--    sino que el cliente sale directo de `customers.auth_user_id`, usar la variante
--    comentada más abajo.
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
    union
    select distinct c.cod_cliente::text as cod
    from user_customer_links ucl
    join customers c on c.id = ucl.customer_id
    where ucl.auth_user_id = auth.uid()
  )
  select coalesce(sum(f.deuda), 0)::numeric as deuda,
         max(f.cargado_at)                   as cargado_at
  from virgilio.gv_deuda_feed f
  join mis_cods m on m.cod = f.cod
  where f.empresa = 'chef';
$$;

-- Si `user_customer_links` no existe en el proyecto de Chef, borrar la RPC de
-- arriba y usar esta (sólo customers.auth_user_id):
-- create or replace function public.get_mi_deuda()
-- returns table(deuda numeric, cargado_at timestamptz)
-- language sql stable security definer set search_path = public, virgilio as $$
--   with mis_cods as (
--     select distinct c.cod_cliente::text as cod
--     from customers c where c.auth_user_id = auth.uid()
--   )
--   select coalesce(sum(f.deuda),0)::numeric, max(f.cargado_at)
--   from virgilio.gv_deuda_feed f join mis_cods m on m.cod = f.cod
--   where f.empresa = 'chef';
-- $$;

revoke all on function public.get_mi_deuda() from public, anon;
grant execute on function public.get_mi_deuda() to authenticated;

-- Chequeo (con una sesión de cliente real, o simulando el JWT):
--   select set_config('request.jwt.claims',
--     json_build_object('sub', '<auth_user_id_de_un_cliente_con_deuda>')::text, true);
--   select * from public.get_mi_deuda();


-- ============================  ROLLBACK  ====================================
-- En CHEF:
--   drop function if exists public.get_mi_deuda();
--   drop foreign table if exists virgilio.gv_deuda_feed;
--   drop user mapping if exists for postgres server virgilio_db;
--   -- (dejar el server virgilio_db si algún otro cruce lo usa)
--   -- drop server if exists virgilio_db cascade;
-- En VIRGILIO:
--   revoke select on public.gv_deuda_feed from chef_gv_reader;
--   revoke usage on schema public from chef_gv_reader;
--   drop role if exists chef_gv_reader;
-- ============================================================================
