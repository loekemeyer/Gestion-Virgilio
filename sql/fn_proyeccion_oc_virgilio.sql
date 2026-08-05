-- =====================================================================
-- fn_proyeccion_oc_virgilio.sql — proyección de ventas que alimenta las OCs (PáginaLK)
--
-- Vive en el proyecto Supabase "loekemeyer's web" (PáginaLK, `kwkclwhmoygunqmlegrg`),
-- sobre `sales_lines`. Es la proyección que Producción Virgilio baja a `proyeccion_madre`
-- (vía `refresh_proyeccion_madre()`) y que fija el Máximo del generador de OCs
-- (Máximo = proyección × índice, topado a capacidad).
--
-- Especificación (pedido del usuario, 2026-08-05):
--   • Combina ventas de **Loekemeyer + Chef** (`empresa in ('lk','chef')`).
--   • **Suavizado de anomalías** integrado: descarta el pico "one-off" de un pedido puntual
--     (v > 1,5×promedio, aislado y sin continuidad) para no inflar el promedio.
--   • Ventana **PRIMARIA = 6 meses** corridos. Si un producto proyecta **0 en 6 meses**,
--     usa los **últimos 12**. Si en 12 sigue **0**, queda en **0** (no se devuelve → el
--     generador lo trata como "sin proyección" y usa el objetivo de OC_Maximos).
--
-- ── DISEÑO ───────────────────────────────────────────────────────────────────
-- `_fn_proy_window(p_meses)`: helper que calcula la proyección combinada LK+Chef con
--   suavizado sobre los últimos `p_meses` meses (por (item, cliente): promedio de cajas/mes
--   sobre su período activo, menos las disrupciones; se suma sobre los clientes por item).
-- `fn_proyeccion_oc_virgilio()`: corre el helper para 6 y 12, y por item hace el coalesce
--   6m→12m→0. Devuelve sólo los items con proyección > 0 (cod, proy_cajas_mes, uxb,
--   proy_uni_mes). `statement_timeout = 60s` (evita que el REST del anon la corte).
--
-- NO toca `fn_proyeccion_madre_emp` (que sigue LK-only 24m para lo que use PáginaLK).
-- `refresh_proyeccion_madre()` (Virgilio) apunta a ESTA función — ver
-- `sql/refresh_proyeccion_madre.sql`.
--
-- Verificado 2026-08-05: 369 códigos · 18.055 cajas/mes (345 con proy en 6m, 23 al
-- fallback de 12m, 28 quedan en 0). Cobertura del generador: 175/190 activos = 92%.
--
-- ⚠ La definición VIVA está en la migración de Supabase (proyecto kwkclwhmoygunqmlegrg);
-- esta es la copia documentada para el repo.
-- =====================================================================
create or replace function public._fn_proy_window(p_meses int)
 returns table(item text, proy_cajas numeric)
 language sql stable security definer set search_path to 'public' set statement_timeout to '60s'
as $fn$
  with mm as (
    select max(extract(year from (invoice_date)::date)::int*12 + extract(month from (invoice_date)::date)::int) as endm
    from public.sales_lines where invoice_date ~ '^\d{4}-\d{2}-\d{2}'
  ),
  norm as (
    select regexp_replace(upper(sl.item_code),'^0+(?=.)','') as nitem, sl.customer_code as cust,
           (extract(year from (sl.invoice_date)::date)::int*12 + extract(month from (sl.invoice_date)::date)::int) as midx,
           sl.boxes::numeric as v
    from public.sales_lines sl, mm
    where sl.invoice_date ~ '^\d{4}-\d{2}-\d{2}'
      and sl.customer_code is not null and sl.customer_code not in ('1','3878')
      and sl.empresa in ('lk','chef')
      and (extract(year from (sl.invoice_date)::date)::int*12 + extract(month from (sl.invoice_date)::date)::int)
          between mm.endm - (greatest(coalesce(p_meses,6),1) - 1) and mm.endm
  ),
  base as (
    select coalesce(r.to_code, nz.nitem) as item, nz.cust, nz.midx, sum(nz.v) as v
    from norm nz
    left join public.sales_item_remap r on r.from_code = nz.nitem
    where not exists (select 1 from public.sales_excluded_items e where e.item_code = nz.nitem)
    group by 1,2,3
  ),
  agg as (
    select item, cust, sum(v) as sumactive, ((select endm from mm) - min(midx) + 1)::numeric as n
    from base group by item, cust
  ),
  mo as (
    select b.item, b.cust, b.v, a.sumactive, a.n, a.sumactive/a.n as rawavg,
      case when lag(b.midx) over (partition by b.item,b.cust order by b.midx) = b.midx-1
           then lag(b.v) over (partition by b.item,b.cust order by b.midx) else 0 end as prev_month_v,
      greatest(
        coalesce(max(b.v) over (partition by b.item,b.cust order by b.midx rows between unbounded preceding and 1 preceding),0),
        coalesce(max(b.v) over (partition by b.item,b.cust order by b.midx rows between 1 following and unbounded following),0)
      ) as max_other
    from base b join agg a on a.item=b.item and a.cust=b.cust
  ),
  disr as (
    select item, cust, sumactive, n,
      sum(case when v > 1.5*rawavg and max_other < 0.8*v and prev_month_v < 0.5*v then v else 0 end) as disruptsum
    from mo group by item, cust, sumactive, n
  )
  select item, round(sum((sumactive - disruptsum)/n), 2) as proy_cajas from disr group by item;
$fn$;

create or replace function public.fn_proyeccion_oc_virgilio()
 returns table(cod text, proy_cajas_mes numeric, uxb integer, proy_uni_mes numeric)
 language sql stable security definer set search_path to 'public' set statement_timeout to '60s'
as $fn$
  with p6 as (select item, proy_cajas from public._fn_proy_window(6)),
       p12 as (select item, proy_cajas from public._fn_proy_window(12)),
       merged as (
         select coalesce(p6.item, p12.item) as item,
                case when coalesce(p6.proy_cajas, 0) > 0 then p6.proy_cajas
                     when coalesce(p12.proy_cajas, 0) > 0 then p12.proy_cajas
                     else 0 end as proy_cajas
         from p6 full join p12 on p12.item = p6.item
       )
  select m.item as cod, m.proy_cajas as proy_cajas_mes,
         coalesce(p.uxb, lk.uxb)::integer as uxb,
         round(m.proy_cajas * coalesce(p.uxb, lk.uxb, 1))::numeric as proy_uni_mes
  from merged m
  left join public.products p on regexp_replace(upper(p.cod),'^0+(?=.)','') = m.item
  left join public.loke_products lk on regexp_replace(upper(lk.cod),'^0+(?=.)','') = m.item
  where m.proy_cajas > 0
  order by m.proy_cajas desc;
$fn$;

grant execute on function public.fn_proyeccion_oc_virgilio() to anon, authenticated;
