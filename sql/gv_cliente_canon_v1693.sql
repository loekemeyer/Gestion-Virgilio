-- ============================================================================
-- v16.93 — Un cliente = un CUIT. Se termina el bardo de los cod de cliente.
--
-- Proyecto: LK (kwkclwhmoygunqmlegrg). Ahi vive `sales_lines`, que guarda las
-- facturas de LK y de Chef en la MISMA tabla, separadas solo por la columna
-- `empresa`.
--
-- POR QUE EXISTE
-- El informe "Clientes en riesgo" mostro "Relca S.R.L 2495 cj/trim vs 3584 en
-- su pico -> -30%". Thomas (14/09): "Relca esta mal. Es cencosud, no relca.
-- Tenes un bardo con los cod de clientes que no quiero ver mas".
-- Tenia razon, y habia DOS errores encima del mismo codigo:
--
--   1) El nombre se resolvia contra public.customers (padron de LK) usando
--      SOLO customer_code. El cod 2444 es Relca en LK y Cencosud en Chef.
--      Medido al 14/09 sobre los ultimos 24 meses: 62 codigos usados por las
--      dos empresas, 27 de ellos son clientes DISTINTOS (CUIT distinto),
--      59.680 cajas mal atribuidas.
--
--   2) Las filas de sales_lines del cod 2444 con empresa='lk' no son de Relca:
--      son de Cencosud. Salen del batch `jumbo_2026_02_20` (Jumbo = Cencosud,
--      subido el 20/02/2026, 552 filas, 22.721 cajas, 2024-03 a 2026-02) que
--      DUPLICA lo que ya estaba bajo empresa='chef' — los totales mensuales
--      coinciden uno a uno en los 24 meses — mas julio y agosto 2026 de los
--      batches `julio_26` y `ago-26`. En LK el cod 2444 no tiene una sola
--      venta propia. Relca no vende nada por LK.
--
-- Regla del dueno (CLAUDE.md, v13.76): "el cod cliente no significa nada,
-- solo el CUIT vale".
--
-- QUE DEJA
--   GV_Ventas_Correccion      tabla: batches cargados con la empresa equivocada
--   gv_cliente_padron         (empresa, cod) -> cuit + razon social cruda
--   gv_cliente_canon          (empresa, cod) -> cliente_id (CUIT) + razon social unica
--   gv_ventas_cliente_raw     sales_lines + correccion + cliente, con flags
--   gv_ventas_cliente         idem, ya sin los duplicados  <- USAR ESTA
--   gv_ventas_corte_empresa   hasta que mes llego el feed de cada empresa
--   gv_clientes_riesgo        el informe de caidas, ya resuelto por CUIT
--
-- `cliente_id` es el CUIT normalizado (11 digitos). Si el codigo no tiene CUIT
-- en ningun padron cae a 'empresa:cod', asi nunca se juntan dos desconocidos
-- distintos por compartir el numero.
--
-- NO SE TOCO UN SOLO DATO de sales_lines ni de customers: todo esto son
-- objetos nuevos que se superponen (mismo patron que GV_PPP_Prog_Override).
--
-- ROLLBACK
--   drop view if exists public.gv_clientes_riesgo;
--   drop view if exists public.gv_ventas_corte_empresa;
--   drop view if exists public.gv_ventas_cliente;
--   drop view if exists public.gv_ventas_cliente_raw;
--   drop view if exists public.gv_cliente_canon;
--   drop view if exists public.gv_cliente_padron;
--   drop table if exists public."GV_Ventas_Correccion";
-- ============================================================================

-- 0) Correcciones de carga: que batch entro con la empresa equivocada.
create table if not exists public."GV_Ventas_Correccion" (
  id            bigserial primary key,
  import_batch  text not null,
  customer_code text,                       -- null = todo el batch
  empresa_real  text check (empresa_real in ('lk','chef')),
  duplicado     boolean not null default false,
  motivo        text not null,
  creado_por    text,
  creado_at     timestamptz not null default now()
);
alter table public."GV_Ventas_Correccion" enable row level security;
revoke insert, update, delete, truncate on public."GV_Ventas_Correccion" from anon, authenticated;
create unique index if not exists gv_ventas_correccion_uq
  on public."GV_Ventas_Correccion" (import_batch, coalesce(customer_code,'*'));

insert into public."GV_Ventas_Correccion" (import_batch, customer_code, empresa_real, duplicado, motivo, creado_por)
values
 ('jumbo_2026_02_20', '2444', 'chef', true,
  'Carga historica de Jumbo (Cencosud) subida el 20/02/2026 con empresa=lk y cod 2444. En LK el cod 2444 es Relca S.R.L, asi que las 22.721 cajas de Cencosud aparecian como Relca. Son las MISMAS facturas que ya estan bajo empresa=chef (chef_hist_xlsx_202607): los totales mensuales coinciden uno a uno en los 24 meses 2024-03 a 2026-02. Se marca duplicado: no se cuenta en los reportes.',
  'Claude (pedido de Thomas, 14/09)'),
 ('julio_26', '2444', 'chef', false,
  'Julio 2026 del cod 2444 cargado con empresa=lk. Es Cencosud, no Relca: en LK el cod 2444 NO tiene ninguna venta propia (todas sus filas salen de esta carga o de jumbo_2026_02_20) y la serie mensual sigue sin escalon a la de Chef (jun 1470 -> jul 1092 -> ago 1403). Chef dejo de cargarse por su propio feed el 30/06.',
  'Claude (pedido de Thomas, 14/09)'),
 ('ago-26', '2444', 'chef', false,
  'Agosto 2026 del cod 2444 cargado con empresa=lk. Mismo caso que julio_26: es Cencosud.',
  'Claude (pedido de Thomas, 14/09)')
on conflict (import_batch, coalesce(customer_code,'*')) do nothing;

-- 1) Padron crudo de las dos empresas, con el CUIT normalizado a 11 digitos.
create or replace view public.gv_cliente_padron
with (security_invoker = true) as
  select 'lk'::text                                                     as empresa,
         c.cod_cliente::text                                            as cod,
         nullif(regexp_replace(coalesce(c.cuit, ''), '\D', '', 'g'), '') as cuit,
         nullif(btrim(c.business_name), '')                             as razon_social,
         'customers'::text                                              as fuente
    from public.customers c
   where c.cod_cliente is not null
  union all
  select 'chef'::text,
         p.cod_cliente::text,
         nullif(regexp_replace(coalesce(p.cuit, ''), '\D', '', 'g'), ''),
         nullif(btrim(p.business_name), ''),
         'chef_padron'::text
    from public.chef_padron p
   where p.cod_cliente is not null;

comment on view public.gv_cliente_padron is
  'v16.93 - padron de las dos empresas, una fila por (empresa, cod). El cod NO es unico entre empresas: 2444 es Relca en LK y Cencosud en Chef.';

-- 2) El resolvedor. Una fila por (empresa, cod) -> identidad canonica.
create or replace view public.gv_cliente_canon
with (security_invoker = true) as
with pad as (
  select empresa, cod,
         max(case when length(cuit) = 11 then cuit end) as cuit,
         max(razon_social)                              as razon_social
    from public.gv_cliente_padron group by 1, 2
), feed as (
  -- nombres de ISIS: cubren los codigos que facturan pero no estan en el padron
  select empresa, cod_cliente::text as cod, max(razon_social) as razon_social
    from public.ppp_np_feed
   where cod_cliente is not null and razon_social is not null group by 1, 2
  union all
  select empresa, cod::text, max(razon_social)
    from public.ppp_programacion
   where cod is not null and razon_social is not null and empresa in ('lk','chef') group by 1, 2
), feed1 as (
  select empresa, cod, max(razon_social) as razon_social from feed group by 1, 2
), vend as (
  select distinct empresa, customer_code as cod from public.sales_lines where customer_code is not null
), todos as (
  select empresa, cod from pad
  union select empresa, cod from feed1
  union select empresa, cod from vend
), propio as (
  select t.empresa, t.cod, p.cuit, coalesce(p.razon_social, f.razon_social) as razon_social
    from todos t
    left join pad   p on p.empresa = t.empresa and p.cod = t.cod
    left join feed1 f on f.empresa = t.empresa and f.cod = t.cod
), base as (
  -- ultimo recurso: el codigo no existe en su propia empresa pero si en la otra
  -- (caso Dorinka 2686 y Loekemeyer 1434, filas de Chef cargadas como LK)
  select pr.empresa, pr.cod,
         coalesce(pr.cuit, o.cuit)                 as cuit,
         coalesce(pr.razon_social, o.razon_social) as razon_social,
         (pr.cuit is null and pr.razon_social is null and o.cod is not null) as cruzado_otra_empresa
    from propio pr
    left join pad o
      on o.cod = pr.cod
     and o.empresa = case pr.empresa when 'lk' then 'chef' else 'lk' end
     and pr.cuit is null and pr.razon_social is null
), nombre_por_cuit as (
  -- un CUIT, un nombre: gana el del padron de LK; si solo esta en Chef, el de Chef
  select cuit,
         coalesce(max(razon_social) filter (where empresa = 'lk'),
                  max(razon_social) filter (where empresa = 'chef')) as razon_social
    from base where cuit is not null group by 1
)
select b.empresa, b.cod, b.cuit,
       coalesce(b.cuit, b.empresa || ':' || b.cod)                               as cliente_id,
       coalesce(n.razon_social, b.razon_social, upper(b.empresa) || ' ' || b.cod) as cliente,
       (b.cuit is null)                                       as sin_cuit,
       (coalesce(n.razon_social, b.razon_social) is null)      as sin_nombre,
       b.cruzado_otra_empresa
  from base b left join nombre_por_cuit n on n.cuit = b.cuit;

comment on view public.gv_cliente_canon is
  'v16.93 - (empresa, cod) -> cliente_id (CUIT) + razon social unica. Todo reporte de clientes pasa por aca; resolver por cod solo cruza LK con Chef.';

-- 3) Ventas resueltas. `_raw` deja ver la correccion; la otra ya viene limpia.
create or replace view public.gv_ventas_cliente_raw
with (security_invoker = true) as
select s.invoice_date::date                 as fecha,
       s.empresa                            as empresa_cargada,
       coalesce(f.empresa_real, s.empresa)  as empresa,
       s.customer_code                      as cod,
       k.cliente_id, k.cuit, k.cliente,
       s.item_code, s.boxes, s.import_batch,
       coalesce(f.duplicado, false)         as duplicado,
       f.motivo                             as correccion
  from public.sales_lines s
  left join public."GV_Ventas_Correccion" f
    on f.import_batch = s.import_batch
   and (f.customer_code is null or f.customer_code = s.customer_code)
  left join public.gv_cliente_canon k
    on k.empresa = coalesce(f.empresa_real, s.empresa)
   and k.cod     = s.customer_code;

create or replace view public.gv_ventas_cliente
with (security_invoker = true) as
select fecha, empresa, cod, cliente_id, cuit, cliente, item_code, boxes
  from public.gv_ventas_cliente_raw
 where not duplicado;

comment on view public.gv_ventas_cliente is
  'v16.93 - sales_lines con el cliente ya resuelto y sin los duplicados de carga. Usar ESTA en los reportes: sales_lines pelada mezcla LK con Chef bajo el mismo customer_code.';

-- 4) Hasta que mes llego el feed de cada empresa (al 14/09: LK 2026-08, Chef
--    2026-06). Sin esto, todo cliente de Chef parece que se esta cayendo.
create or replace view public.gv_ventas_corte_empresa
with (security_invoker = true) as
select empresa, max(mes) as mes_corte
  from (select empresa, date_trunc('month', fecha)::date mes, count(distinct cliente_id) n
          from public.gv_ventas_cliente group by 1, 2) t
 where n >= 10
 group by 1;

-- 5) El informe de caidas. Trimestre actual vs el mejor trimestre movil de los
--    24 meses anteriores, SIN solapar con el actual (ventanas que terminan 3 o
--    mas meses atras): si no, un cliente con compras a saltos "cae" siempre.
drop view if exists public.gv_clientes_riesgo;
create view public.gv_clientes_riesgo
with (security_invoker = true) as
with m as (
  select v.cliente_id, v.empresa, date_trunc('month', v.fecha)::date mes, sum(v.boxes) cajas
    from public.gv_ventas_cliente v group by 1, 2, 3
), corte as (
  -- por empresa, salvo que el cliente tenga datos mas nuevos (caso Cencosud,
  -- cuyas filas de jul/ago entraron por el feed de LK)
  select m.cliente_id, m.empresa, greatest(c.mes_corte, max(m.mes)) as mes_corte
    from m join public.gv_ventas_corte_empresa c on c.empresa = m.empresa
   group by 1, 2, c.mes_corte
), corte_cli as (
  select cliente_id, max(mes_corte) mes_corte from corte group by 1
), kk as (
  select m.cliente_id,
         (extract(year from age(c.mes_corte, m.mes)) * 12
          + extract(month from age(c.mes_corte, m.mes)))::int as k,
         sum(m.cajas) cajas
    from m join corte c on c.cliente_id = m.cliente_id and c.empresa = m.empresa
   group by 1, 2
), serie as (
  select c.cliente_id, g.k, coalesce(sum(kk.cajas), 0) cajas,
         (c.mes_corte - (g.k || ' months')::interval)::date as mes
    from corte_cli c
    cross join generate_series(0, 25) g(k)
    left join kk on kk.cliente_id = c.cliente_id and kk.k = g.k
   group by 1, 2, 4
), roll as (
  select cliente_id, k, mes,
         sum(cajas) over (partition by cliente_id order by k rows between current row and 2 following) trimestre
    from serie
), p as (
  select cliente_id,
         max(trimestre) filter (where k = 0)               as trim_actual,
         max(trimestre) filter (where k between 3 and 21)  as pico,
         (array_agg(to_char(mes, 'YYYY-MM') order by trimestre desc, k)
            filter (where k between 3 and 21))[1]          as mes_pico
    from roll group by 1
)
select n.cliente, p.cliente_id,
       coalesce(p.trim_actual, 0)::int as trim_actual,
       coalesce(p.pico, 0)::int        as pico,
       p.mes_pico,
       round(100.0 * (coalesce(p.trim_actual, 0) - p.pico) / nullif(p.pico, 0))::int as caida_pct,
       (select max(fecha) from public.gv_ventas_cliente v where v.cliente_id = p.cliente_id) as ultima_compra
  from p
  join (select distinct cliente_id, cliente from public.gv_cliente_canon) n on n.cliente_id = p.cliente_id
 where coalesce(p.trim_actual, 0) > 0 and coalesce(p.pico, 0) > 0;

comment on view public.gv_clientes_riesgo is
  'v16.93 - clientes cayendo: trimestre actual vs su mejor trimestre movil anterior, por CUIT. Filtro tipico: pico >= 300 and caida_pct <= -30.';

-- ---------------------------------------------------------------------------
-- Chequeos (al 2026-09-14)
--   select count(*) from public.gv_ventas_cliente where cliente is null;  -- 0
--   select * from public.gv_cliente_canon where cod = '2444';
--     -> chef 2444 Cencosud S.A. / lk 2444 Relca S.R.L, cada uno con su CUIT
--   select cliente, trim_actual, pico, caida_pct from public.gv_clientes_riesgo
--    where cliente ilike '%Cencosud%';   -- 3965 vs 4664 = -15%, NO esta cayendo
-- ---------------------------------------------------------------------------
