-- ============================================================================
-- Pedidos_Web · ingesta de los pedidos de la página LK hacia Gestión Virgilio
-- Idea 3717 · Paso 1 de la fase de implementación
-- ============================================================================
-- QUÉ HACE: espeja en Virgilio, línea por línea y EN EL ORDEN DEL CARRITO, los
--           pedidos web que hoy solo viven en el proyecto LK. Con eso Virgilio
--           deja de depender del espejo de la PPP de ISIS para saber qué hay
--           que programar.
--
-- POR QUÉ ASÍ: es el mismo patrón que ya corre en producción para
--   `lk_pedidos_match` — LK EMPUJA por el FDW `virgilio_db` con el rol
--   `lk_ppp_reader`. Virgilio lee una tabla local y nunca paga el costo del
--   FDW en el camino caliente (la lección que dejó el padrón de Chef).
--
-- DIFERENCIA CLAVE CONTRA `lk_pedidos_match`: esa tabla lleva `items_string`
--   ordenado POR CÓDIGO, así que ya perdió el orden del carrito y no sirve
--   para partir el pedido en NP. Acá va una fila por línea con `linea_rn`,
--   que es la posición real dentro de `sheets_payload.items`. Ese orden es
--   justamente lo que la regla de corte necesita.
--
-- ALCANCE: solo Loekemeyer (`empresa = 'lk'`). Chef queda para después: sus
--   pedidos viven en otro proyecto y todavía falta el
--   `grant select on public.orders to loke_reader` del lado de Chef (el mismo
--   pendiente que ya saltea `sync_pedidos_match_virgilio`).
--
-- ⚠ `Pedidos_Web` ES UN ESPEJO PURO Y SE REESCRIBE ENTERO CADA 15 MINUTOS.
--   NO agregarle columnas de trabajo (tanda, zona, operario, estado): se
--   borrarían en la próxima corrida. Todo eso va en la tabla de programación,
--   que es el Paso 3 y todavía no existe.
--
-- REGLA DE CORTE (leída de la Edge Function `procesar-pedidos-db`, que es la
--   que arma el Excel del mail de las 12:30 — no es una suposición):
--   `processOrders` agrupa por (N° Pedido, Sucursal, Cliente) —y como un
--   pedido web tiene un solo cliente y una sola sucursal, el grupo es el
--   pedido entero—. Los de >= 18 líneas se cortan en bloques de 18 CONTIGUOS
--   en el orden del payload; los de < 18 son una sola NP. `ceil(linea_rn/18)`
--   reproduce los dos casos, incluido el borde de exactamente 18.
--   NO hay ningún ORDER BY por artículo: reordenar es el bug clásico acá.
--
-- NP PROVISORIA: 9 dígitos, `<empresa><order_id 6><parte 2>`, con el primer
--   dígito marcando la empresa igual que las NP de ISIS (9 = Loekemeyer,
--   4 = Chef). El pedido 1342 parte 1 → 900134201. Se renombra a la NP real
--   cuando ISIS la asigna (eso es el `np_map` del plan, todavía sin construir).
-- ============================================================================


-- ############################################################################
-- PARTE A · LADO VIRGILIO   (proyecto hrxfctzncixxqmpfhskv)
-- ############################################################################

-- A.1 · La tabla espejo. Una fila por LÍNEA de pedido.
create table if not exists public."Pedidos_Web" (
  empresa              text        not null default 'lk',
  order_id             bigint      not null,
  linea_rn             integer     not null,   -- posición en el carrito: define el corte
  cod_cliente          text,
  razon_social         text,
  fecha_pedido         date,
  hora_pedido          text,
  created_at           timestamptz,
  sucursal_entrega     text,
  vend                 text,
  condicion_pago_code  text,
  numero_oc            text,
  observaciones        text,
  art                  text,                   -- normalizado igual que padCodArt
  cajas                numeric,
  uxb                  numeric,
  uni                  numeric,
  enviado_a_compras_at timestamptz,            -- null = todavía no salió por mail
  synced_at            timestamptz not null default now(),
  primary key (empresa, order_id, linea_rn)
);

create index if not exists pedidos_web_fecha_idx
  on public."Pedidos_Web" (empresa, fecha_pedido);
create index if not exists pedidos_web_pendientes_idx
  on public."Pedidos_Web" (empresa, order_id)
  where enviado_a_compras_at is null;

-- A.2 · RLS. Copia exacta del patrón de `lk_pedidos_match`: la app lee, el rol
--       del FDW escribe. Sin la policy de `lk_ppp_reader` el push falla en
--       silencio (RLS está activo y el rol no es superusuario).
alter table public."Pedidos_Web" enable row level security;

drop policy if exists pedidos_web_select on public."Pedidos_Web";
create policy pedidos_web_select on public."Pedidos_Web"
  for select to anon, authenticated using (true);

drop policy if exists pedidos_web_writer on public."Pedidos_Web";
create policy pedidos_web_writer on public."Pedidos_Web"
  for all to lk_ppp_reader using (true) with check (true);

grant select on public."Pedidos_Web" to anon, authenticated;
grant select, insert, update, delete on public."Pedidos_Web" to lk_ppp_reader;


-- A.3 · Las NP que Virgilio programaría, ya cortadas y con m³ propio.
--       El m³ NO viene de LK: sale de `Volumen_Articulos` de Virgilio, que es
--       donde está el dato. El LEFT JOIN es a propósito — un artículo sin m³
--       no puede hacer desaparecer la línea, así que se cuenta aparte en
--       `arts_sin_m3` para que el faltante se vea en pantalla.
create or replace view public.v_pedidos_web_np as
with cap as (
  select 'lk'::text as empresa, 18 as cap_lineas
  union all
  select 'chef',                15
),
part as (
  select p.*, ceil(p.linea_rn::numeric / c.cap_lineas)::int as np_idx
  from public."Pedidos_Web" p
  join cap c on c.empresa = p.empresa
)
select
  p.empresa,
  p.order_id,
  p.np_idx,
  case p.empresa when 'lk' then '9' when 'chef' then '4' else '0' end
    || lpad(p.order_id::text, 6, '0')
    || lpad(p.np_idx::text,   2, '0')                     as np_prov,
  min(p.cod_cliente)                                      as cod,
  min(p.razon_social)                                     as razon_social,
  min(p.fecha_pedido)                                     as fecha_recep,
  min(p.hora_pedido)                                      as hora_recep,
  min(p.sucursal_entrega)                                 as direccion,
  min(p.vend)                                             as v,
  min(p.condicion_pago_code)                              as condicion_pago_code,
  min(p.numero_oc)                                        as numero_oc,
  bool_and(p.enviado_a_compras_at is not null)            as enviado_a_compras,
  count(*)                                                as lineas,
  sum(p.cajas)                                            as cajas,
  round(sum(p.cajas * va.m3)::numeric, 3)                 as m3,
  count(*) filter (where va.codigo is null)               as arts_sin_m3,
  string_agg(p.art, ',' order by p.linea_rn)              as arts
from part p
left join public."Volumen_Articulos" va on va.codigo = p.art
group by p.empresa, p.order_id, p.np_idx;

grant select on public.v_pedidos_web_np to anon, authenticated;


-- ############################################################################
-- PARTE B · LADO LK   (proyecto kwkclwhmoygunqmlegrg)
-- ############################################################################

-- B.1 · La tabla de Virgilio, vista desde LK por el FDW que ya existe.
create foreign table if not exists virgilio.pedidos_web (
  empresa              text,
  order_id             bigint,
  linea_rn             integer,
  cod_cliente          text,
  razon_social         text,
  fecha_pedido         date,
  hora_pedido          text,
  created_at           timestamptz,
  sucursal_entrega     text,
  vend                 text,
  condicion_pago_code  text,
  numero_oc            text,
  observaciones        text,
  art                  text,
  cajas                numeric,
  uxb                  numeric,
  uni                  numeric,
  enviado_a_compras_at timestamptz,
  synced_at            timestamptz
)
server virgilio_db
options (schema_name 'public', table_name 'Pedidos_Web');


-- B.2 · El pedido web abierto en líneas, en el orden del carrito.
--       `with ordinality` es la pieza que conserva ese orden.
--       La normalización del código replica `padCodArt` de la Edge Function
--       (primera corrida de dígitos a 3 posiciones + primera corrida de letras).
--       El filtro `~ '\d'` no pierde nada: 0 de 16.137 ítems históricos no
--       tienen dígitos (medido 2026-09-03).
create or replace view public.v_pedidos_web as
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

-- La vista expone razón social y condición de pago de cualquier cliente: no va
-- para anon ni para authenticated. Mismo criterio que `v_pedidos_match`.
revoke all on public.v_pedidos_web from anon, authenticated;


-- B.3 · El push. Ventana móvil de 30 días con delete+insert, igual que
--       `sync_pedidos_match_virgilio`. 30 y no 14 porque un pedido puede
--       seguir en armado bastante después de haber entrado.
create or replace function public.sync_pedidos_web_virgilio()
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_corte date;
begin
  v_corte := (now() at time zone 'America/Argentina/Buenos_Aires')::date - 30;

  -- El WHERE no es opcional: supautils bloquea DELETE sin WHERE para roles
  -- que no son superusuario, y el error solo aparece en tiempo de ejecución.
  delete from virgilio.pedidos_web
   where empresa = 'lk' and fecha_pedido >= v_corte;

  insert into virgilio.pedidos_web
    (empresa, order_id, linea_rn, cod_cliente, razon_social, fecha_pedido,
     hora_pedido, created_at, sucursal_entrega, vend, condicion_pago_code,
     numero_oc, observaciones, art, cajas, uxb, uni, enviado_a_compras_at,
     synced_at)
  select empresa, order_id, linea_rn, cod_cliente, razon_social, fecha_pedido,
         hora_pedido, created_at, sucursal_entrega, vend, condicion_pago_code,
         numero_oc, observaciones, art, cajas, uxb, uni, enviado_a_compras_at,
         now()
    from public.v_pedidos_web
   where fecha_pedido >= v_corte;
end;
$function$;

revoke all on function public.sync_pedidos_web_virgilio() from public, anon, authenticated;


-- B.4 · Cron cada 15 minutos, alineado con el de `lk_pedidos_match`.
select cron.schedule('sync-pedidos-web-virgilio', '*/15 * * * *',
                     $$select public.sync_pedidos_web_virgilio()$$);


-- ############################################################################
-- PARTE C · VERIFICACIÓN Y VUELTA ATRÁS
-- ############################################################################
--
-- C.1 · Correrlo a mano una vez (en LK):
--     select public.sync_pedidos_web_virgilio();
--
-- C.2 · Control de que llegó completo (en VIRGILIO). Tiene que dar una fila
--       por pedido y coincidir con lo que hay en LK:
--     select empresa, count(distinct order_id) pedidos, count(*) lineas,
--            max(synced_at) ultima_sync
--       from public."Pedidos_Web" group by empresa;
--
-- C.3 · Los pedidos que TODAVÍA no salieron por mail (los que hoy no se pueden
--       programar hasta el día siguiente) — que es el punto entero de la idea:
--     select * from public.v_pedidos_web_np
--      where not enviado_a_compras order by order_id, np_idx;
--
-- C.4 · Apagar el cron sin borrar nada:
--     select cron.unschedule('sync-pedidos-web-virgilio');
--
-- C.5 · Vuelta atrás completa. No toca ningún dato existente: todo lo de este
--       archivo son objetos nuevos.
--     -- en LK:
--     select cron.unschedule('sync-pedidos-web-virgilio');
--     drop function if exists public.sync_pedidos_web_virgilio();
--     drop view     if exists public.v_pedidos_web;
--     drop foreign table if exists virgilio.pedidos_web;
--     -- en VIRGILIO:
--     drop view  if exists public.v_pedidos_web_np;
--     drop table if exists public."Pedidos_Web";
-- ============================================================================
