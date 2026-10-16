-- v31.54 (Luis, 16/10/2026, D1) — el armado ya no devuelve a góndola el código LIQUIDADO.
--
-- Problema 850. La liquidación del picking (v30.29, PK_LIQUIDAR_EN en index.html: 574E → 574)
-- hace levantar 574 para pedidos de 574E. El armado (reconciliar_pipeline_stock_etapa2) cruza
-- lo pickeado contra Entregas, que dice 574E: no encuentra entrega del 574 y su `separado` va a
-- TERMINADO (+1). Quedaba el 574 con una caja fantasma en góndola (F47A, F48N), el picking
-- siguiente lo volvía a pedir (F97A) y el 574E de esa tanda quedaba corto en a_facturar.
--
-- Arreglo: por cada tanda YA ARMADA (tiene separado del código viejo) se calcula
--   L = min(pickeado del viejo, entregado del pedido − pickeado del pedido)
-- y se asienta un par `liquidacion` (ref = tanda): terminado del viejo −L, a_facturar del
-- pedido +L. Neto: el 574 baja L (salió de la góndola), el 574E queda con su pila de a_facturar
-- completa y la factura (que sale en 574E) la drena sin bloqueo. No toca etapa2 ni
-- gv_entregas_norm (protegidas): corre después, en el mismo cron 68.
-- Idempotente: upsert por (tanda, código, empresa, depósito); si cambian las entregas, se ajusta.
--
-- Para liquidar otro código: una fila en GV_Pick_Liquidar Y la misma en PK_LIQUIDAR_EN.

create table if not exists public."GV_Pick_Liquidar" (
  cod_pedido text not null,
  cod_liq    text not null,
  empresa    text not null default 'LK',
  desde      timestamptz not null,
  activo     boolean not null default true,
  nota       text,
  creado     timestamptz not null default now(),
  primary key (cod_pedido, cod_liq, empresa)
);
alter table public."GV_Pick_Liquidar" enable row level security;
revoke all on public."GV_Pick_Liquidar" from anon;

insert into public."GV_Pick_Liquidar" (cod_pedido, cod_liq, empresa, desde, nota)
values ('574E', '574', 'LK', timestamptz '2026-10-14 00:00-03',
        'Luis 14/10 (v30.29): liquidar el 574 nacional dentro de los pedidos de 574E')
on conflict do nothing;

create unique index if not exists mov_stock_liquidacion_dedup
  on public."Movimientos_Stock" (upper(btrim(ref)), upper(btrim(cod_art)), coalesce(empresa, ''::text), deposito)
  where tipo = 'liquidacion';

create or replace function public.gv_stock_liquidacion_imputar(p_simular boolean default false)
returns table(tanda text, cod_pedido text, cod_liq text, pick_liq numeric, pick_ped numeric, entregado numeric, imputado numeric)
language plpgsql security definer set search_path = public as $f$
#variable_conflict use_column
-- v31.54-liquidacion-imputar
begin
  return query
  with par as (
    select upper(btrim(g.cod_pedido)) cp, upper(btrim(g.cod_liq)) cl, g.empresa emp, g.desde
      from "GV_Pick_Liquidar" g where g.activo),
  pk as (
    select p.cp, p.cl, p.emp, p.desde, upper(btrim(m.ref)) tnd,
           coalesce(sum(m.delta) filter (where regexp_replace(upper(btrim(m.cod_art)),' +(LK|CH)$','') = p.cl), 0) pliq,
           coalesce(sum(m.delta) filter (where regexp_replace(upper(btrim(m.cod_art)),' +(LK|CH)$','') = p.cp), 0) pped,
           max(m.creado) filter (where regexp_replace(upper(btrim(m.cod_art)),' +(LK|CH)$','') = p.cl) ult
      from par p
      join "Movimientos_Stock" m
        on m.tipo = 'picking' and m.deposito = 'separar_pedidos'
       and regexp_replace(upper(btrim(m.cod_art)),' +(LK|CH)$','') in (p.cl, p.cp)
     group by 1,2,3,4,5),
  ent as (select en.tanda tnd, en.artn, sum(en.ent) e from public.gv_entregas_norm en group by 1,2),
  c as (
    select k.tnd, k.cp, k.cl, k.emp, k.pliq, k.pped, coalesce(en.e, 0)::numeric ent,
           least(k.pliq, greatest(0, coalesce(en.e, 0) - k.pped))::numeric l
      from pk k
      left join ent en on en.tnd = k.tnd and en.artn = k.cp
     where k.pliq > 0 and k.ult >= k.desde and k.tnd !~ '-X$'
       and exists (select 1 from "Movimientos_Stock" s
                    where s.tipo = 'separado' and upper(btrim(s.ref)) = k.tnd
                      and regexp_replace(upper(btrim(s.cod_art)),' +(LK|CH)$','') = k.cl)),
  ins as (
    insert into "Movimientos_Stock" (cod_art, deposito, delta, tipo, ref, legajo, empresa)
    select x.cod, x.dep, x.d, 'liquidacion', c.tnd, 'pipeline', c.emp
      from c
      cross join lateral (values (c.cl, 'terminado', -c.l), (c.cp, 'a_facturar', c.l)) x(cod, dep, d)
     where not p_simular
       and (c.l > 0 or exists (select 1 from "Movimientos_Stock" m where m.tipo = 'liquidacion' and upper(btrim(m.ref)) = c.tnd))
    on conflict (upper(btrim(ref)), upper(btrim(cod_art)), coalesce(empresa, ''::text), deposito)
      where tipo = 'liquidacion'
    do update set delta = excluded.delta
      where "Movimientos_Stock".delta is distinct from excluded.delta
    returning 1)
  select c.tnd, c.cp, c.cl, c.pliq, c.pped, c.ent, c.l from c order by 1;
end;
$f$;
revoke all on function public.gv_stock_liquidacion_imputar(boolean) from public, anon, authenticated;

-- cron 68 (cada 10 min): después de la reconciliación del pipeline.
select cron.alter_job(68, command :=
  'select pg_advisory_xact_lock(5768); select public.reconciliar_pipeline_stock(); select public.gv_stock_liquidacion_imputar();');

insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version, activo)
values ('gv_stock_liquidacion_imputar', 'funcion', 'cross join lateral \(values \(c\.cl, ''terminado'', -c\.l\)',
        'El 574 levantado por la liquidación del picking se imputa al 574E del pedido (terminado del viejo −L, a_facturar del pedido +L); sin eso vuelve a góndola en el armado',
        'Luis', 'v31.54', true);

-- Rollback:
--   select cron.alter_job(68, command := 'select pg_advisory_xact_lock(5768); select public.reconciliar_pipeline_stock();');
--   delete from "Movimientos_Stock" where tipo = 'liquidacion';
--   drop function public.gv_stock_liquidacion_imputar(boolean);
--   update "GV_Reglas_Centinela" set activo = false where objeto = 'gv_stock_liquidacion_imputar';
