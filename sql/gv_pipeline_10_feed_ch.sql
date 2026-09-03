-- ============================================================================
-- [10] FEED CHEF — correr en el proyecto CHEF (nkhzocgdpwtgrmwleihr)
-- ----------------------------------------------------------------------------
-- Crea la vista-contrato que Gestión Virgilio consume por FDW + el rol lector
-- de mínimo privilegio. La vista expone SOLO lo que la pipeline necesita, con
-- la misma forma que la de LK (empresa 'ch').
-- ============================================================================

create or replace view public.v_virgilio_pedidos_feed as
select
  'ch'::text                                        as empresa,
  o.id                                              as order_id,
  c.cod_cliente                                     as cod_cliente,
  c.business_name                                   as cliente_nombre,
  o.created_at                                      as created_at,
  (o.created_at at time zone 'America/Argentina/Buenos_Aires')::date            as fecha,
  to_char(o.created_at at time zone 'America/Argentina/Buenos_Aires','HH24:MI') as hora,
  o.status                                          as status,
  coalesce(
    o.sheets_payload->>'sucursal_entrega',
    (select da.label
       from public.customer_delivery_addresses da
      where da.customer_id = o.customer_id
      order by da.slot
      limit 1)
  )                                                 as sucursal_entrega,
  o.payment_method                                  as condicion_pago,
  coalesce(o.sheets_payload->'items','[]'::jsonb)   as items
from public.orders o
left join public.customers c on c.id = o.customer_id;

-- Rol lector de mínimo privilegio (reemplazar el placeholder por un password fuerte).
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'virgilio_reader') then
    create role virgilio_reader login password '<<CHEF_VIRGILIO_READER_PASSWORD>>';
  end if;
end$$;

grant usage  on schema public                       to virgilio_reader;
grant select on public.v_virgilio_pedidos_feed      to virgilio_reader;

-- Verificación:
-- select empresa, order_id, cod_cliente, sucursal_entrega, jsonb_array_length(items) n
-- from public.v_virgilio_pedidos_feed order by created_at desc limit 5;
