-- =============================================================================
-- gv_pedidos_web_np_feeds.sql — los dos feeds CRUDOS del job de tandas (2026-09-04)
-- Proyecto **LK** (kwkclwhmoygunqmlegrg). Funciones nuestras (prefijo gv_), sólo las
-- ejecuta service_role (el job). Antes de hoy NO estaban en ningún repo: se habían
-- creado directo en la base. Desde acá, esto es la fuente.
-- =============================================================================
-- HISTORIA DEL DÍA (para que no se repita):
--   · A la tarde se les metió el filtro "pendiente = no enviado a compras"
--     (`enviado_a_compras_at is null`) para que, al prender la numeración, el job no
--     programara 30 días de pedidos que ISIS ya había entregado (208 de 213).
--   · A la noche se SACÓ: dejaba afuera el limbo (pedidos que ya salieron a ISIS por
--     el mail de las 12:30 pero que Producción todavía no tiene) y el dueño quiere
--     que eso sea de Gestión. La regla de pendiente pasó a VIRGILIO, en la RPC
--     `gv_pedidos_web_excluidos` (sql/gv_pedidos_web_excluidos.sql): desde el día del
--     cambio (`PPP_Web_Config.gestion_desde`), lo que Producción no tenga.
--
-- Estas dos funciones vuelven a ser FEEDS CRUDOS: devuelven todo lo de la ventana y
-- no deciden nada. El job (gv-ppp-web-tandas-diarias) y "A Programar" les pasan lo
-- que devuelven a la RPC de Virgilio y sacan los excluidos. Una sola regla, en un
-- solo lugar, y LK no sabe nada de Producción.
--
-- CHEF: `chef_orders` (foreign table de LK sobre `orders` de Chef) NO espejaba
-- `enviado_a_compras_at`. Chef la tiene (verificado con IMPORT FOREIGN SCHEMA a un
-- schema temporal, borrado después). Se agregó al foreign table —aditivo— y queda:
-- `enviado_a_compras` en la salida de Chef pasa de `null` al dato real, informativo.
--
-- MEDIDO al dejarlas crudas (30 días reales): LK 352 NP · Chef 38 NP. De eso, la RPC
-- de Virgilio deja pendientes 10 pedidos de LK y 2 de Chef.
--
-- ROLLBACK: sql/backups/gv_pedidos_web_np_feeds_20260904_pre_filtro_enviado.sql
-- (las dos funciones tal como estaban antes del día; la LK es idéntica a la de acá
-- salvo el comentario, la Chef no devolvía `enviado_a_compras`).
-- =============================================================================

alter foreign table public.chef_orders add column if not exists enviado_a_compras_at timestamptz;

CREATE OR REPLACE FUNCTION public.gv_pedidos_web_np_lk(p_desde date)
 RETURNS TABLE(empresa text, order_id bigint, np_idx integer, cod text, razon_social text, fecha_recep date, hora_recep text, direccion text, v text, condicion_pago_code text, numero_oc text, enviado_a_compras boolean, lineas bigint, cajas numeric, items jsonb, arts text, localidad text, provincia text, zona_expreso text, nombre_expreso text, direccion_expreso text, m3 numeric, m3_parcial boolean, fecha_entrega_pactada date, np_total integer)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select p.empresa, p.order_id, p.np_idx, p.cod, p.razon_social, p.fecha_recep,
         p.hora_recep, p.direccion, p.v, p.condicion_pago_code, p.numero_oc,
         p.enviado_a_compras, p.lineas, p.cajas, p.items, p.arts,
         p.localidad, p.provincia, p.zona_expreso, p.nombre_expreso, p.direccion_expreso,
         p.m3, p.m3_parcial,
         -- Todavia no lo manda ninguna pagina; el dia que lo manden, llega solo.
         nullif(coalesce(o.sheets_payload->>'fecha_entrega',
                         o.sheets_payload->>'fechaEntrega'), '')::date,
         -- ⚠ EN CUANTOS BLOQUES ESTA PARTIDO EL PEDIDO.
         --   La vista lo calcula (n_tramos = ceil(lineas / 18)) pero NO lo devolvia,
         --   asi que rio abajo nadie sabia que un pedido estaba partido: se podia
         --   mandar el bloque 1 a una tanda y el 2 a otra. Como todos los bloques de
         --   un pedido comparten `fecha_recep`, el filtro de arriba se los lleva a
         --   todos o a ninguno, y contar sobre el resultado filtrado da bien.
         count(*) over (partition by p.empresa, p.order_id)::int
    from public.v_pedidos_web_np p
    left join public.orders o on o.id = p.order_id
   where p.fecha_recep >= p_desde
     -- 2026-09-04 (noche): el filtro "no enviado a compras" que estuvo unas horas aca
     -- se SACO. La regla de pendiente ahora vive en VIRGILIO (gv_pedidos_web_excluidos:
     -- desde el dia del cambio, lo que Produccion no tenga) y la aplican el job y
     -- "A Programar" sobre lo que esta funcion devuelve. Esta vuelve a ser un feed crudo.
   order by p.order_id, p.np_idx;
$function$;

CREATE OR REPLACE FUNCTION public.gv_pedidos_web_np_chef(p_dias integer DEFAULT 30)
 RETURNS TABLE(empresa text, order_id bigint, np_idx integer, cod text, razon_social text, fecha_recep date, hora_recep text, direccion text, v text, condicion_pago_code text, numero_oc text, enviado_a_compras boolean, lineas bigint, cajas numeric, items jsonb, arts text, localidad text, provincia text, zona_expreso text, nombre_expreso text, direccion_expreso text, m3 numeric, m3_parcial boolean, fecha_entrega_pactada date, np_total integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  -- Todas las tablas de Chef son FOREIGN TABLES. Sin `as materialized` el planner
  -- mete el lateral adentro del foreign scan y hace un round trip por fila: asi
  -- dio 57014 (statement timeout) el 2026-09-04.
  return query
  with ped as materialized (
    select o.id, o.created_at, o.sheets_payload, o.enviado_a_compras_at
      from public.chef_orders o
     where o.sheets_payload is not null
       and jsonb_typeof(o.sheets_payload->'items') = 'array'
       and (o.created_at at time zone 'America/Argentina/Buenos_Aires')::date >= current_date - p_dias
       -- 2026-09-04 (noche): SIN filtro por enviado_a_compras. La regla de pendiente
       -- vive en Virgilio (gv_pedidos_web_excluidos). Se conserva la columna en el
       -- foreign table y se devuelve el dato real, informativo.
  ),
  cust as materialized (select c.id, c.cod_cliente::text as cod from public.chef_customers c),
  dirs as materialized (
    select d.customer_id, d.slot, btrim(lower(d.label)) as lab,
           d.localidad, d.provincia, d.zona_expreso, d.nombre_expreso
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
           dir.zona_expreso as l_zona_expreso, dir.nombre_expreso as l_nombre_expreso
      from cab
      left join cust c on c.cod = cab.l_cod
      left join lateral (
        select d.localidad, d.provincia, d.zona_expreso, d.nombre_expreso
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
    -- 2026-09-05 (dueño, v12.94): bloques SEGUIDOS de a 15 en el orden del carrito,
    -- igual que el mail de Chef / ISIS (44592 = primeras 15 líneas del pedido 205,
    -- 44593 las 12 restantes). Antes: serpentina balanceada por m³.
    select t.*, row_number() over (partition by t.l_order_id order by t.linea_rn) as rk from tramos t
  ),
  part as (
    select o.*, ceil(o.rk::numeric / 15)::int as l_np_idx
      from orden o
  )
  select
    'chef'::text, p.l_order_id, p.l_np_idx, min(p.l_cod), min(cp.business_name),
    min(p.l_fecha), min(p.l_hora), min(p.l_dir), min(p.l_vend), min(p.l_cond),
    min(p.l_oc),
    bool_or(p.l_enviado),   -- dato real (antes null): informativo, no filtra
    count(*)::bigint, sum(p.l_cajas),
    jsonb_agg(jsonb_build_object('art', p.l_art, 'cajas', p.l_cajas, 'uxb', p.l_uxb,
                                 'uni', coalesce(p.l_cajas,0) * coalesce(p.l_uxb,0))
              order by p.linea_rn),
    string_agg(p.l_art, ',' order by p.linea_rn),
    min(p.l_localidad), min(p.l_provincia), min(p.l_zona_expreso), min(p.l_nombre_expreso),
    null::text,
    round(sum(p.linea_m3)::numeric, 3),
    bool_or(p.m3_unit is null),
    min(p.l_pactada),
    -- ⚠ En cuantos bloques quedo partido el pedido. `n_tramos` ya se calculaba
    --   (ceil(lineas / 15)) pero no salia de la funcion.
    min(p.n_tramos)::int
  from part p
  left join padron cp on cp.cod_cliente = p.l_cod
  group by p.l_order_id, p.l_np_idx;
end
$function$;
