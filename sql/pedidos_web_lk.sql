-- ============================================================================
-- Pedidos web de LK, ya partidos en NP · Idea 3717
-- ============================================================================
-- QUÉ ES: las notas de pedido que hoy produce el Excel del mail de las 12:30,
--         calculadas EN VIVO sobre la misma tabla donde caen los pedidos de la
--         página (`orders` del proyecto LK). Gestión Virgilio las lee de acá.
--
-- ⚠ ESTO VIVE ENTERO EN EL PROYECTO **LK** (kwkclwhmoygunqmlegrg).
--
-- NO HAY COPIA. Se probó primero con una tabla espejo en Virgilio alimentada por
--   un cron cada 15 minutos, y se descartó por decisión del dueño (2026-09-03):
--   es otra copia más de un dato que ya existe, con su propia forma de quedar
--   desincronizada. Gestión lee la tabla de LK, directo. Si algo cambia en la
--   página, se ve al instante y no a los 15 minutos.
--
-- CÓMO LLEGA GESTIÓN HASTA ACÁ: el repo ya tiene cliente Supabase de LK y sesión
--   de admin de LK — es el mismo bridge que hoy abre el Panel Web LK sin OTP
--   (`lkTryBridge`, v12.35), que loguea como `loekemeyer.n8n@gmail.com`, que está
--   en `public.admins`. No hace falta ninguna credencial ni permiso nuevo.
--
-- SEGURIDAD: las dos vistas van con `security_invoker = true`, así que la RLS de
--   `orders` es la que decide, no el dueño de la vista. Sin eso, la vista correría
--   como `postgres` y CUALQUIER cliente logueado del portal vería los pedidos de
--   todos los demás. Verificado el 2026-09-03:
--       admin del bridge     → 1.463 NP
--       otro authenticated   → 0 NP
--       anon                 → permission denied
--   Al tocar estas vistas hay que volver a correr esas tres pruebas.
--
-- ----------------------------------------------------------------------------
-- LA REGLA DE CORTE (leída de la Edge Function, no supuesta)
-- ----------------------------------------------------------------------------
--   Sale de `processOrders` de `procesar-pedidos-db`, que es la que arma el Excel
--   del mail. Agrupa por (N° Pedido, Sucursal, Cliente) — y un pedido web tiene un
--   solo cliente y una sola sucursal, así que el grupo es el pedido entero.
--   Los de >= tope se cortan en bloques del tope, CONTIGUOS EN EL ORDEN DEL
--   CARRITO; los de < tope son una sola NP. `ceil(linea_rn / tope)` reproduce los
--   dos casos, incluido el borde de exactamente 18.
--
--   TOPE: **18 en Loekemeyer, 15 en Chef.** Medido, no recordado: un tope deja una
--   pila de NP justo en el valor del tope. Sobre `PPP_Base_Pedidos` de Virgilio,
--   por cantidad de líneas por NP:
--       líneas:   15    16    17    18    19
--       lk:       25    27    13   253     2      → pila en 18
--       chef:     25     0     1     1     0      → pila en 15, cae a 0 en 16
--   Los pocos que se pasan son NP que no nacieron del Excel web (pedidos por
--   teléfono cargados directo a ISIS): esa tabla tiene todas las NP, no solo las
--   de la página.
--
--   ⚠ NUNCA ORDENAR POR CÓDIGO DE ARTÍCULO ACÁ. La Edge Function no ordena nada:
--   recorre las filas como vienen. Reordenar es el bug clásico de este módulo, y
--   es la razón por la que `lk_pedidos_match` NO sirve para esto — su
--   `items_string` viene ordenado por código y ya perdió el orden del carrito.
--
-- ----------------------------------------------------------------------------
-- LA NORMA DEL EXCEL QUE **NO** SE COPIA: la numeración
-- ----------------------------------------------------------------------------
--   El `N° Pedido` del Excel (`globalN`) es un contador de la tanda: numera
--   primero todos los pedidos de >= 18 líneas y después los chicos. O sea que EL
--   MISMO PEDIDO SACA UN NÚMERO DISTINTO según con qué otros pedidos salga en el
--   mail. No es identidad y no sirve como clave.
--   Por eso acá va una NP propia y estable: 9 dígitos,
--   `<empresa><order_id 6><parte 2>`, con el primer dígito marcando la empresa
--   igual que ISIS (9 = Loekemeyer, 4 = Chef). Pedido 1342 parte 1 → 900134201.
--   Se renombra a la NP real de ISIS cuando ISIS la asigna (el `np_map` del plan,
--   todavía sin construir).
--
-- EL m³ NO SALE DE ACÁ: LK no tiene el volumen por caja. Vive en
--   `Volumen_Articulos` de Virgilio y lo resuelve Gestión contra su propia base.
--   Verificado el 2026-09-03: de los 230 artículos que alguna vez se pidieron por
--   la web, los 230 tienen m³ cargado. Del catálogo entero faltan 3 (442E, 444E y
--   446E, los Bowl Ac. Inox. Base Silicona de 16, 20 y 24 cm), que nunca se
--   pidieron por web todavía.
--
-- ALCANCE: hoy solo Loekemeyer. Chef vive en otro proyecto y llega por el FDW
--   `chef_db`; falta el `grant select on public.orders to loke_reader` del lado
--   de Chef, el mismo pendiente que ya saltea `sync_pedidos_match_virgilio`.
--   El tope de 15 ya está contemplado en el CTE `cap`.
-- ============================================================================


-- 1) El pedido web abierto en líneas, EN EL ORDEN DEL CARRITO.
--    `with ordinality` es la pieza que conserva ese orden.
--    La normalización del código replica `padCodArt` de la Edge Function:
--    primera corrida de dígitos a 3 posiciones + primera corrida de letras.
--    El filtro `~ '\d'` no pierde nada: 0 de 16.137 ítems históricos no tienen
--    dígitos (medido 2026-09-03).
create or replace view public.v_pedidos_web
with (security_invoker = true) as
select
  'lk'::text                                                as empresa,
  o.id                                                      as order_id,
  it.ord::int                                               as linea_rn,
  coalesce(o.sheets_payload->>'cod_cliente',
           o.sheets_payload->>'codCliente')                 as cod_cliente,
  c.business_name                                           as razon_social,
  (o.created_at at time zone 'America/Argentina/Buenos_Aires')::date        as fecha_pedido,
  to_char(o.created_at at time zone 'America/Argentina/Buenos_Aires',
          'HH24:MI:SS')                                     as hora_pedido,
  o.created_at,
  coalesce(o.sheets_payload->>'sucursal_entrega',
           o.sheets_payload->>'sucursalEntrega')            as sucursal_entrega,
  o.sheets_payload->>'vend'                                 as vend,
  coalesce(o.sheets_payload->>'condicion_pago_code',
           o.sheets_payload->>'condicionPagoCode')          as condicion_pago_code,
  coalesce(o.sheets_payload->>'numOC',
           o.sheets_payload->>'numero_oc',
           o.sheets_payload->>'numeroOC')                   as numero_oc,
  o.sheets_payload->>'observaciones'                        as observaciones,
  lpad((regexp_match(it.value->>'cod_art', '\d+'))[1], 3, '0')
    || coalesce((regexp_match(it.value->>'cod_art', '[a-zA-Z]+'))[1], '')   as art,
  nullif(coalesce(it.value->>'cajas', it.value->>'Cajas'), '')::numeric     as cajas,
  nullif(it.value->>'uxb', '')::numeric                                     as uxb,
  coalesce(nullif(it.value->>'cajas', ''), '0')::numeric
    * coalesce(nullif(it.value->>'uxb', ''), '0')::numeric                  as uni,
  o.enviado_a_compras_at
from public.orders o
left join public.customers c
  on c.cod_cliente::text = coalesce(o.sheets_payload->>'cod_cliente',
                                    o.sheets_payload->>'codCliente')
cross join lateral jsonb_array_elements(o.sheets_payload->'items')
     with ordinality as it(value, ord)
where o.sheets_payload is not null
  and jsonb_typeof(o.sheets_payload->'items') = 'array'
  and (it.value->>'cod_art') ~ '\d';


-- 2) Las NP ya cortadas. Esto es lo que consume Gestión Virgilio.
--    `items` va como jsonb EN ORDEN para que el front no tenga que pedir las
--    líneas por separado ni volver a ordenarlas.
--    `enviado_a_compras` en false = el pedido todavía no salió por mail, o sea
--    que ISIS ni se enteró. Ese es el caso que la idea 3717 viene a resolver.
create or replace view public.v_pedidos_web_np
with (security_invoker = true) as
with cap as (
  select 'lk'::text as empresa, 18 as cap_lineas
  union all
  select 'chef',                15
),
part as (
  select i.*, ceil(i.linea_rn::numeric / c.cap_lineas)::int as np_idx
  from public.v_pedidos_web i
  join cap c on c.empresa = i.empresa
)
select
  p.empresa,
  p.order_id,
  p.np_idx,
  case p.empresa when 'lk' then '9' when 'chef' then '4' else '0' end
    || lpad(p.order_id::text, 6, '0')
    || lpad(p.np_idx::text,   2, '0')                as np_prov,
  min(p.cod_cliente)                                 as cod,
  min(p.razon_social)                                as razon_social,
  min(p.fecha_pedido)                                as fecha_recep,
  min(p.hora_pedido)                                 as hora_recep,
  min(p.sucursal_entrega)                            as direccion,
  min(p.vend)                                        as v,
  min(p.condicion_pago_code)                         as condicion_pago_code,
  min(p.numero_oc)                                   as numero_oc,
  bool_and(p.enviado_a_compras_at is not null)       as enviado_a_compras,
  count(*)                                           as lineas,
  sum(p.cajas)                                       as cajas,
  jsonb_agg(jsonb_build_object('art', p.art, 'cajas', p.cajas, 'uxb', p.uxb, 'uni', p.uni)
            order by p.linea_rn)                     as items,
  string_agg(p.art, ',' order by p.linea_rn)         as arts
from part p
group by p.empresa, p.order_id, p.np_idx;


-- 3) Permisos. `anon` no entra ni a mirar; `authenticated` entra pero la RLS de
--    `orders` decide qué ve, y solo un admin ve todo.
revoke all on public.v_pedidos_web    from anon;
revoke all on public.v_pedidos_web_np from anon;
grant select on public.v_pedidos_web    to authenticated;
grant select on public.v_pedidos_web_np to authenticated;


-- ----------------------------------------------------------------------------
-- Controles (correr a mano)
-- ----------------------------------------------------------------------------
--
--   -- Lo que todavía no salió por mail. Sin esto, estos pedidos no existen para
--   -- nadie hasta el día siguiente:
--   select np_prov, cod, razon_social, fecha_recep, hora_recep, direccion,
--          lineas, cajas
--     from public.v_pedidos_web_np
--    where not enviado_a_compras
--    order by order_id, np_idx;
--
--   -- Que el corte no se haya roto: ninguna NP puede pasarse de su tope.
--   select empresa, max(lineas) from public.v_pedidos_web_np group by empresa;
--
--   -- Las tres pruebas de seguridad (ver arriba). La del medio y la de abajo
--   -- tienen que dar 0 y "permission denied":
--   begin;
--     set local role authenticated;
--     set local request.jwt.claims = '{"sub":"<uid del admin>","role":"authenticated"}';
--     select count(*) from public.v_pedidos_web_np;
--   rollback;
-- ----------------------------------------------------------------------------
