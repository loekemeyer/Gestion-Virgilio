-- ════════════════════════════════════════════════════════════════════════════
-- gv_lk_rellenar_sheets_payload — v17.40 (2026-09-14)
-- PROYECTO: LK (kwkclwhmoygunqmlegrg).  NO va en Virgilio.
-- Cron en LK: jobid 46 `gv-lk-rellenar-payload`, cada 10 min, modo escritura.
--
-- POR QUÉ EXISTE
-- El checkout de la página LK crea el pedido con la RPC submit_order_fast y
-- DESPUÉS, en un update aparte sin catch (script.js ~8750), guarda
-- orders.sheets_payload. Desde el 2026-09-11 11:11 ART ese update no se ejecuta
-- cuando la sesión es la de un CLIENTE (con la del admin sí anda). La vista
-- v_pedidos_web filtra por "sheets_payload is not null", así que el pedido
-- queda invisible para Gestión Virgilio: sin NP, sin tanda y sin figurar en
-- A Programar. Medido: 10/09 0 sin payload de 8; 11/09 6 de 9; 12/09 7 de 7;
-- 14/09 19 de 19. 32 filas de orders = 6 pedidos reales, 4,30 M$, 166 cajas.
--
-- QUÉ HACE
-- Barrido de red: arma el payload desde order_items + customers +
-- customer_delivery_addresses para los pedidos que quedaron sin él. NO toca el
-- camino crítico del checkout (nada de triggers sobre orders), así que no
-- puede romper el alta de un pedido. Si el front se arregla, el barrido deja
-- de encontrar candidatos y no hace nada. Es una red, no el arreglo: la causa
-- real sigue en el front y hay que encontrarla.
--
-- QUÉ NO PUEDE RECUPERAR
-- Lo que sólo vivía en el payload y no está en ninguna tabla: número de OC y
-- las observaciones que escribió el cliente. La sucursal de entrega se
-- autocompleta con la dirección del cliente (misma regla de orden que usa
-- v_pedidos_web: primero las que tienen zona_expreso, después por slot) y se
-- marca sucursal_autocompletada; si el cliente tiene más de una,
-- sucursal_ambigua queda en true y hay que confirmarla con él.
--
-- ⚠ LOS TRES GUARDAS, Y POR QUÉ ESTÁN
-- 1. p_desde (default 2026-09-11, cuando se rompió). SIN ESTE PISO el barrido
--    agarra ~60 pedidos de MARZO que también tienen el payload en NULL y los
--    mete en la PPP de esta semana. Lo cazó el dry-run; no bajarlo.
-- 2. Ráfaga (p_ventana_rafaga_min, 30 min): al fallar el paso el cliente vuelve
--    a confirmar y cada intento crea una fila nueva de orders (Rodríguez lo
--    intentó 9 veces). Sólo se rellena el ÚLTIMO de la ráfaga.
-- 3. Ya cubierto (p_ventana_recarga_h, 6 h): si el cliente recargó y ESE pedido
--    sí tiene payload, el anterior no se rellena — si no, se duplica. Caso
--    testigo: Schell 3790, 1391/1392/1393 rotos y 1394 bueno (mismos 6
--    artículos, sólo cambió el 505 de 12 a 15 cajas), ya en la tanda E01H.
-- Los descartados quedan con el payload en NULL, o sea invisibles: no se borra
-- nada y se pueden recuperar después mirando gv_lk_payload_recuperado.
--
-- ROLLBACK
--   select cron.unschedule('gv-lk-rellenar-payload');
--   update public.orders set sheets_payload = null
--    where id in (select order_id from public.gv_lk_payload_recuperado where accion='relleno');
--   drop function public.gv_lk_rellenar_sheets_payload(bigint[], boolean, timestamptz, integer, integer, integer);
--   drop table public.gv_lk_payload_recuperado;
-- ════════════════════════════════════════════════════════════════════════════

-- ── 1. Log / backup de lo que toca el barrido ──────────────────────────────
create table if not exists public.gv_lk_payload_recuperado (
  id            bigserial primary key,
  order_id      bigint      not null,
  accion        text        not null,
  motivo        text,
  ganador_id    bigint,                        -- en un descarte: quién se quedó con el pedido
  payload       jsonb,                         -- lo que se escribió (null si se descartó)
  creado_at     timestamptz not null default now()
);
create index if not exists gv_lk_payload_recuperado_order_idx
  on public.gv_lk_payload_recuperado (order_id);

alter table public.gv_lk_payload_recuperado drop constraint if exists gv_lk_payload_recuperado_accion_check;
alter table public.gv_lk_payload_recuperado add constraint gv_lk_payload_recuperado_accion_check
  check (accion in ('relleno','descartado_rafaga','descartado_sin_items','descartado_ya_cubierto'));

alter table public.gv_lk_payload_recuperado enable row level security;
revoke all on public.gv_lk_payload_recuperado from anon, authenticated;

-- ── 2. El barrido ──────────────────────────────────────────────────────────
create or replace function public.gv_lk_rellenar_sheets_payload(
  p_ids                bigint[]    default null,   -- null = barrido; con ids = sólo esos
  p_dry_run            boolean     default true,   -- true = no escribe, sólo informa
  p_desde              timestamptz default '2026-09-11 00:00:00-03',  -- ⚠ piso duro, ver guarda 1
  p_min_edad_min       integer     default 10,     -- deja respirar al front antes de meter mano
  p_ventana_rafaga_min integer     default 30,     -- reintentos del mismo cliente
  p_ventana_recarga_h  integer     default 6       -- recarga que SÍ entró
)
returns table (
  order_id bigint, accion text, motivo text, cod_cliente text, razon_social text,
  creado timestamptz, lineas integer, cajas numeric, total numeric,
  sucursal text, ambigua boolean, ganador_id bigint
)
language plpgsql security definer set search_path = public as $fn$
declare
  v_rafaga  interval := make_interval(mins  => p_ventana_rafaga_min);
  v_recarga interval := make_interval(hours => p_ventana_recarga_h);
begin
  return query
  with cand as (
    select o.id, o.customer_code, o.created_at, o.total, o.payment_method,
           o.is_promo, o.extra_discount
      from public.orders o
     where o.sheets_payload is null
       and o.created_at >= p_desde
       and o.created_at <  now() - make_interval(mins => p_min_edad_min)
       and (p_ids is null or o.id = any (p_ids))
  ),
  marcado as (
    select c.*,
           -- (a) otro candidato del mismo cliente entró después, dentro de la ráfaga
           (select max(c2.id) from cand c2
             where c2.customer_code = c.customer_code
               and c2.created_at between c.created_at and c.created_at + v_rafaga
               and c2.id > c.id) as pisado_por_cand,
           -- (b) el cliente recargó y ESE sí tiene payload: el pedido ya está cubierto
           (select max(o2.id) from public.orders o2
             where o2.customer_code = c.customer_code
               and o2.sheets_payload is not null
               and o2.created_at between c.created_at and c.created_at + v_recarga) as cubierto_por
      from cand c
  ),
  dir as (
    select m.id as oid, d.label, d.slot, d.zona_expreso,
           count(*) over (partition by m.id) as cuantas
      from marcado m
      join public.customers c on c.cod_cliente::text = m.customer_code
      join public.customer_delivery_addresses d on d.customer_id = c.id
  ),
  dir1 as (
    select distinct on (oid) oid, label, (cuantas > 1) as ambigua
      from dir order by oid, (btrim(coalesce(zona_expreso,'')) <> '') desc, slot
  ),
  -- El código de condición de pago no se hardcodea: se aprende del histórico.
  cp as (
    select o.payment_method,
           mode() within group (order by (o.sheets_payload->>'condicion_pago_code')) as code
      from public.orders o where o.sheets_payload ? 'condicion_pago_code' group by 1
  ),
  items as (
    select i.order_id as oid, count(*)::integer as lineas, sum(i.cajas)::numeric as cajas,
           jsonb_agg(jsonb_build_object('cod_art', p.cod, 'cod_original', null,
                                        'cajas', i.cajas, 'uxb', i.uxb) order by i.id)
             filter (where p.cod is not null) as items
      from public.order_items i
      left join public.products p on p.id = i.product_id
     group by i.order_id
  ),
  armado as (
    select m.id, m.customer_code, m.created_at, m.total::numeric as total,
           m.pisado_por_cand, m.cubierto_por,
           cu.business_name, it.lineas, it.cajas, it.items,
           d1.label as sucursal, coalesce(d1.ambigua, false) as ambigua,
           jsonb_strip_nulls(jsonb_build_object(
             'order_number',        m.id::text,
             'cod_cliente',         m.customer_code,
             'vend',                coalesce(cu.vend, ''),
             'condicion_pago',      coalesce(m.payment_method, ''),
             'condicion_pago_code', nullif(cp.code,'')::numeric,
             'sucursal_entrega',    coalesce(d1.label, ''),
             'cliente_nuevo',       '',
             'observaciones',       'recuperado automaticamente - CONFIRMAR sucursal de entrega',
             'is_promo',            coalesce(m.is_promo, false),
             'extra_discount',      coalesce(m.extra_discount, 0),
             'payment_term',        cu.payment_term,
             'order_total',         m.total,
             'source',              'Web',
             'mode',                'new',
             -- marcas propias del barrido, para distinguirlo de un payload del front
             'payload_recuperado',      true,
             'sucursal_autocompletada', (d1.label is not null),
             'sucursal_ambigua',        coalesce(d1.ambigua, false),
             'items',                   coalesce(it.items, '[]'::jsonb)
           )) as payload
      from marcado m
      left join public.customers cu on cu.cod_cliente::text = m.customer_code
      left join items it on it.oid = m.id
      left join dir1  d1 on d1.oid = m.id
      left join cp        on cp.payment_method = m.payment_method
  ),
  decidido as (
    select a.*,
           case when a.cubierto_por    is not null then 'descartado_ya_cubierto'
                when a.pisado_por_cand is not null then 'descartado_rafaga'
                when a.items           is null     then 'descartado_sin_items'
                else 'relleno' end as accion,
           coalesce(a.cubierto_por, a.pisado_por_cand) as ganador
      from armado a
  ),
  escrito as (
    update public.orders o set sheets_payload = d.payload
      from decidido d
     where o.id = d.id and d.accion = 'relleno' and not p_dry_run
       and o.sheets_payload is null          -- guard: nunca pisa un payload del front
    returning o.id
  ),
  logueado as (
    insert into public.gv_lk_payload_recuperado (order_id, accion, motivo, ganador_id, payload)
    select d.id, d.accion,
           case d.accion
             when 'descartado_ya_cubierto' then 'el cliente recargo y ese pedido si tiene payload'
             when 'descartado_rafaga'      then 'reintento del mismo cliente dentro de ' || p_ventana_rafaga_min || ' min'
             when 'descartado_sin_items'   then 'el pedido no tiene order_items con articulo'
             else 'payload armado desde order_items' end,
           d.ganador,
           case when d.accion = 'relleno' then d.payload end
      from decidido d
     where not p_dry_run and (d.accion <> 'relleno' or d.id in (select id from escrito))
    returning 1
  )
  select d.id, d.accion,
         case d.accion
           when 'descartado_ya_cubierto' then 'el cliente recargo y ese pedido si tiene payload'
           when 'descartado_rafaga'      then 'reintento dentro de ' || p_ventana_rafaga_min || ' min'
           when 'descartado_sin_items'   then 'sin order_items con articulo'
           else 'payload armado desde order_items' end,
         d.customer_code, d.business_name, d.created_at,
         d.lineas, d.cajas, d.total, d.sucursal, d.ambigua, d.ganador
    from decidido d order by d.total desc nulls last, d.id;
end $fn$;

revoke all on function public.gv_lk_rellenar_sheets_payload(bigint[], boolean, timestamptz, integer, integer, integer)
  from public, anon, authenticated;
grant execute on function public.gv_lk_rellenar_sheets_payload(bigint[], boolean, timestamptz, integer, integer, integer)
  to service_role;

-- ── 3. El cron ─────────────────────────────────────────────────────────────
-- select cron.schedule('gv-lk-rellenar-payload', '*/10 * * * *',
--   $cron$ select public.gv_lk_rellenar_sheets_payload(null, false) $cron$);

-- ── Verificación ───────────────────────────────────────────────────────────
-- Siempre en dry-run antes de escribir:
--   select * from public.gv_lk_rellenar_sheets_payload(null, true);
-- Qué tocó el barrido:
--   select accion, count(*) from public.gv_lk_payload_recuperado group by 1;
-- Que el feed de Gestión ya los vea:
--   select order_id, cod, lineas, cajas, m3, zona_expreso
--     from public.gv_pedidos_web_np_lk(date '2026-09-11');
