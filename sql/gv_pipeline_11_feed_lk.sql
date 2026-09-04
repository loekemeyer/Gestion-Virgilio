-- ============================================================================
-- [11] FEED LK — correr en el proyecto LK web (kwkclwhmoygunqmlegrg)
-- ----------------------------------------------------------------------------
-- Misma vista-contrato que Chef, empresa 'lk'. Mismo rol lector.
-- ============================================================================

create or replace view public.v_virgilio_pedidos_feed as
select
  'lk'::text                                        as empresa,
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
  coalesce(o.sheets_payload->'items','[]'::jsonb)   as items,
  /* barrio: `customer_delivery_addresses.zona_expreso` guarda el BARRIO del punto
     de entrega, NO la zona (pese al nombre de la columna). Match por
     (customer_id + label de la sucursal pedida); si no hay, primer slot cargado.
     Es el mismo dato que v12.74 usa en el front para resolver la zona. */
  coalesce(
    (select da.zona_expreso
       from public.customer_delivery_addresses da
      where da.customer_id = o.customer_id
        and da.label = (o.sheets_payload->>'sucursal_entrega')
        and coalesce(da.zona_expreso,'') <> ''
      limit 1),
    (select da.zona_expreso
       from public.customer_delivery_addresses da
      where da.customer_id = o.customer_id
        and coalesce(da.zona_expreso,'') <> ''
      order by da.slot
      limit 1)
  )                                                 as barrio
from public.orders o
left join public.customers c on c.id = o.customer_id;

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'virgilio_reader') then
    create role virgilio_reader login password '<<LK_VIRGILIO_READER_PASSWORD>>';
  end if;
end$$;

grant usage  on schema public                       to virgilio_reader;
grant select on public.v_virgilio_pedidos_feed      to virgilio_reader;
