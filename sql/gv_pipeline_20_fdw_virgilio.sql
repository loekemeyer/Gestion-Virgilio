-- ============================================================================
-- [20] PASILLO FDW — correr en el proyecto VIRGILIO (hrxfctzncixxqmpfhskv)
-- ----------------------------------------------------------------------------
-- Monta 2 FDW read-only (a LK y a Chef) apuntados a la vista-contrato de cada
-- fuente, y una vista unificada `public.vista_pedidos_web_feed` (lk + ch).
--
-- Los passwords deben coincidir con los del rol `virgilio_reader` de cada
-- fuente (archivos 10 y 11). Placeholders acá; los reales viven en el mapping.
-- Rotar: alter user mapping for postgres server <srv> options (set password '...');
-- ============================================================================

create extension if not exists postgres_fdw;

-- Servidor + mapping a LK
create server lk_feed foreign data wrapper postgres_fdw
  options (host 'db.kwkclwhmoygunqmlegrg.supabase.co', port '5432', dbname 'postgres', sslmode 'require');
create user mapping for postgres server lk_feed
  options (user 'virgilio_reader', password '<<LK_VIRGILIO_READER_PASSWORD>>');

-- Servidor + mapping a Chef
create server chef_feed foreign data wrapper postgres_fdw
  options (host 'db.nkhzocgdpwtgrmwleihr.supabase.co', port '5432', dbname 'postgres', sslmode 'require');
create user mapping for postgres server chef_feed
  options (user 'virgilio_reader', password '<<CHEF_VIRGILIO_READER_PASSWORD>>');

-- Foreign tables mapeadas a cada v_virgilio_pedidos_feed
create schema if not exists fuentes;

create foreign table fuentes.pedidos_lk (
  empresa text, order_id bigint, cod_cliente bigint, cliente_nombre text,
  created_at timestamptz, fecha date, hora text, status text,
  sucursal_entrega text, condicion_pago text, items jsonb
) server lk_feed options (schema_name 'public', table_name 'v_virgilio_pedidos_feed');

create foreign table fuentes.pedidos_ch (
  empresa text, order_id bigint, cod_cliente bigint, cliente_nombre text,
  created_at timestamptz, fecha date, hora text, status text,
  sucursal_entrega text, condicion_pago text, items jsonb
) server chef_feed options (schema_name 'public', table_name 'v_virgilio_pedidos_feed');

-- Feed unificado que consume la pipeline
create or replace view public.vista_pedidos_web_feed as
  select * from fuentes.pedidos_lk
  union all
  select * from fuentes.pedidos_ch;

-- Verificación:
-- select empresa, count(*), max(created_at) from public.vista_pedidos_web_feed group by 1;
