-- ============================================================================
-- [30] ESQUEMA AISLADO `pipeline` — correr en VIRGILIO (hrxfctzncixxqmpfhskv)
-- ----------------------------------------------------------------------------
-- Tablas espejo de la PPP, PERO aisladas: la app de producción lee
-- public.PPP_*, nunca pipeline.*. Escribir acá no afecta nada.
-- REVOKE para anon/authenticated + esquema fuera de PostgREST = invisible a la
-- anon key.
-- ============================================================================

create schema if not exists pipeline;
revoke all on schema pipeline from anon, authenticated;

-- Control: qué pedidos web se procesaron y sus NP internas
create table if not exists pipeline.pedidos_web (
  empresa          text,
  order_id         bigint,
  np_interna       text,
  cod_cliente      bigint,
  cliente_nombre   text,
  sucursal_entrega text,
  procesado_at     timestamptz default now(),
  primary key (empresa, order_id)
);

-- Espejo aislado de PPP_Base_Pedidos (las líneas)
create table if not exists pipeline.ppp_base (
  id       bigserial primary key,
  pedido   text,   -- NP interna
  articulo text,   -- cod_art
  cajas    numeric,
  cliente  text,
  fecha    text
);

-- Espejo aislado de PPP_Programacion_Diaria (la cabecera / tanda / m³)
create table if not exists pipeline.ppp_prog (
  id            bigserial primary key,
  np            text,
  tanda         text,
  m3            numeric,
  cod           text,   -- cod_cliente
  razon_social  text,
  direccion     text,
  barrio        text,
  zona          text,
  fecha_recep   text,
  fecha_entrega text,
  tipo          text,
  op            text
);

revoke all on all tables in schema pipeline from anon, authenticated;
