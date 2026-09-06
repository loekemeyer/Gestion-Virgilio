-- ============================================================================
-- v13.43 — gv_pedidos_web_np_chef: la dirección de ENTREGA, no la sucursal del cliente
-- Proyecto LK (kwkclwhmoygunqmlegrg) · migración gv_pedidos_web_np_chef_direccion_entrega_v1343
--
-- Dueño (2026-09-06): "los de Chef probablemente estés poniendo la dirección de su
-- sucursal en lugar de la dirección de entrega nuestra". Exacto: el feed devolvía
-- `direccion` = sucursal_entrega del pedido ("I. Catolica 6- Rio Cuarto") y
-- `direccion_expreso` = null::text, siempre. Gestión geocodificaba Río Cuarto.
--
-- Chef SÍ tiene el dato: `chef_customer_delivery_addresses.direccion_entrega`
-- ("Pergamino 3751" para Elbantonio = el expreso en Soldati; "Hilarion De La
-- Quintana 2150" para Gifel = entrega local en San Martín).
--
-- Regla (espejo de lo que LK ya hace):
--   · intermediario (hay nombre_expreso, o la provincia no es Buenos Aires/CABA):
--     direccion = la sucursal del cliente (como antes) y direccion_expreso =
--     direccion_entrega → la Edge Function arma "Exp. — Pergamino 3751 (I. Catolica
--     6- Rio Cuarto)" y el geocodificador se queda con "Pergamino 3751";
--   · entrega local: direccion = direccion_entrega (la limpia) y direccion_expreso = null.
-- Todo lo demás idéntico a la v12.94 (bloques de a 15 seguidos, m³, etc.).
--
-- Verificado el 2026-09-06 sobre 60 días de pedidos: ninguna fila sin dirección.
-- Rollback: la definición anterior está en sql/gv_pedidos_web_np_feeds.sql.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.gv_pedidos_web_np_chef(p_dias integer DEFAULT 30)
 RETURNS TABLE(empresa text, order_id bigint, np_idx integer, cod text, razon_social text, fecha_recep date, hora_recep text, direccion text, v text, condicion_pago_code text, numero_oc text, enviado_a_compras boolean, lineas bigint, cajas numeric, items jsonb, arts text, localidad text, provincia text, zona_expreso text, nombre_expreso text, direccion_expreso text, m3 numeric, m3_parcial boolean, fecha_entrega_pactada date, np_total integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  return query
  with ped as materialized (
    select o.id, o.created_at, o.sheets_payload, o.enviado_a_compras_at
      from public.chef_orders o
     where o.sheets_payload is not null
       and jsonb_typeof(o.sheets_payload->'items') = 'array'
       and (o.created_at at time zone 'America/Argentina/Buenos_Aires')::date >= current_date - p_dias
  ),
  cust as materialized (select c.id, c.cod_cliente::text as cod from public.chef_customers c),
  dirs as materialized (
    select d.customer_id, d.slot, btrim(lower(d.label)) as lab,
           d.localidad, d.provincia, d.zona_expreso, d.nombre_expreso,
           d.direccion_entrega                      -- v13.43: adónde va NUESTRO camión
      from public.chef_customer_delivery_addresses d
  ),
  padron as materialized (select cp.cod_cliente, cp.business_name from public.chef_padron cp),
  vol as materialized (select vv.codigo, vv.m3 from virgilio.volumen_articulo vv),
  cab as (
    select p.id as l_order_id,
           coalesce(p.sheets_payload->>'cod_cliente', p.sheets_payload->>'codCliente') as l_cod,
           (p.created_at at time zone 'America/Argentina/Buenos_Aires')::date as l_fecha,
           to_char(p.created_at at time zone 'America/Argentina/Buenos_Aires', 'HH24:MI:SS') as l_hora,
           coalesce(p.sheets_payload->>'sucursal_entrega', p.sheets_payload->>'sucursalEntrega') as l_dir,
           p.sheets_payload->>'vend' as l_vend,
           coalesce(p.sheets_payload->>'condicion_pago_code', p.sheets_payload->>'condicionPagoCode') as l_cond,
           coalesce(p.sheets_payload->>'numOC', p.sheets_payload->>'numero_oc') as l_oc,
           nullif(coalesce(p.sheets_payload->>'fecha_entrega',
                           p.sheets_payload->>'fechaEntrega'), '')::date as l_pactada,
           (p.enviado_a_compras_at is not null) as l_enviado,
           p.sheets_payload as pay
      from ped p
  ),
  cab_dir as (
    select cab.*, dir.localidad as l_localidad, dir.provincia as l_provincia,
           dir.zona_expreso as l_zona_expreso, dir.nombre_expreso as l_nombre_expreso,
           nullif(btrim(dir.direccion_entrega), '') as l_dir_entrega,
           -- intermediario = expreso con nombre, o cliente de otra provincia (llega por expreso)
           ( btrim(coalesce(dir.nombre_expreso, '')) <> ''
             or (dir.provincia is not null and lower(btrim(dir.provincia)) not in
                 ('buenos aires', 'caba', 'capital federal', 'ciudad autonoma de buenos aires',
                  'ciudad autónoma de buenos aires', 'ciudad de buenos aires')) ) as l_intermediario
      from cab
      left join cust c on c.cod = cab.l_cod
      left join lateral (
        select d.localidad, d.provincia, d.zona_expreso, d.nombre_expreso, d.direccion_entrega
          from dirs d
         where d.customer_id = c.id and d.lab = btrim(lower(cab.l_dir))
         order by (btrim(coalesce(d.zona_expreso,'')) <> '') desc, d.slot
         limit 1
      ) dir on true
  ),
  li as (
    select cd.l_order_id, it.ord::int as linea_rn, cd.l_cod, cd.l_fecha, cd.l_hora,
           cd.l_dir, cd.l_vend, cd.l_cond, cd.l_oc, cd.l_pactada, cd.l_enviado,
           cd.l_localidad, cd.l_provincia, cd.l_zona_expreso, cd.l_nombre_expreso,
           cd.l_dir_entrega, cd.l_intermediario,
           lpad((regexp_match(it.value->>'cod_art', '\d+'))[1], 3, '0')
             || coalesce((regexp_match(it.value->>'cod_art', '[a-zA-Z]+'))[1], '') as l_art,
           nullif(coalesce(it.value->>'cajas', it.value->>'Cajas'), '')::numeric as l_cajas,
           nullif(it.value->>'uxb', '')::numeric as l_uxb
      from cab_dir cd
      cross join lateral jsonb_array_elements(cd.pay->'items') with ordinality as it(value, ord)
     where (it.value->>'cod_art') ~ '\d'
  ),
  con_m3 as (
    select li.*, v.m3 as m3_unit, coalesce(li.l_cajas, 0) * coalesce(v.m3, 0) as linea_m3
      from li left join vol v on v.codigo = upper(btrim(li.l_art))
  ),
  tramos as (
    select c.*, ceil(count(*) over (partition by c.l_order_id)::numeric / 15)::int as n_tramos
      from con_m3 c
  ),
  orden as (
    select t.*, row_number() over (partition by t.l_order_id order by t.linea_rn) as rk from tramos t
  ),
  part as (
    select o.*, ceil(o.rk::numeric / 15)::int as l_np_idx
      from orden o
  )
  select
    'chef'::text, p.l_order_id, p.l_np_idx, min(p.l_cod), min(cp.business_name),
    min(p.l_fecha), min(p.l_hora),
    -- v13.43: entrega local → la dirección de entrega limpia; con intermediario → la sucursal
    case when bool_or(p.l_intermediario) then min(p.l_dir) else coalesce(min(p.l_dir_entrega), min(p.l_dir)) end,
    min(p.l_vend), min(p.l_cond),
    min(p.l_oc),
    bool_or(p.l_enviado),
    count(*)::bigint, sum(p.l_cajas),
    jsonb_agg(jsonb_build_object('art', p.l_art, 'cajas', p.l_cajas, 'uxb', p.l_uxb,
                                 'uni', coalesce(p.l_cajas,0) * coalesce(p.l_uxb,0))
              order by p.linea_rn),
    string_agg(p.l_art, ',' order by p.linea_rn),
    min(p.l_localidad), min(p.l_provincia), min(p.l_zona_expreso), min(p.l_nombre_expreso),
    -- v13.43: adónde va el camión cuando hay intermediario (antes: null::text, siempre)
    case when bool_or(p.l_intermediario) then min(p.l_dir_entrega) else null::text end,
    round(sum(p.linea_m3)::numeric, 3),
    bool_or(p.m3_unit is null),
    min(p.l_pactada),
    min(p.n_tramos)::int
  from part p
  left join padron cp on cp.cod_cliente = p.l_cod
  group by p.l_order_id, p.l_np_idx;
end
$function$;
