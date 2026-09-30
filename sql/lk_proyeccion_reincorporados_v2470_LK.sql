-- v24.70 (Thomas, 30/09/2026, D4a) — BASE DE LK (kwkclwhmoygunqmlegrg).
-- Un artículo NUEVO o que VOLVIÓ a venderse (primera venta después de 6+ meses sin vender) se
-- proyecta con el PROMEDIO de lo vendido desde que volvió, si ya tiene 2 o más meses CERRADOS.
-- La regla vieja (4.º mejor mes de 6) lo dejaba en 0 o muy abajo hasta juntar 4 meses con venta.
-- Sólo SUBE: toma el mayor entre la proyección de siempre y el promedio desde la vuelta.
-- Medido el 30/09: sube 38 artículos (198E 35,2 → 70,3 · 702EN 29,5 → 59 · 566E 103,7 → 124,4 …).
-- El mes en curso NO cuenta (evita que una compra grande de un solo mes sea la proyección: 55219).
create or replace function public.fn_proyeccion_oc_virgilio()
 returns table(cod text, proy_cajas_mes numeric, uxb integer, proy_uni_mes numeric, proy_cajas_lk numeric, proy_cajas_chef numeric)
 language sql stable security definer
 set search_path to 'public'
 set statement_timeout to '60s'
as $function$
  with p6 as (select item, proy_cajas, proy_lk, proy_chef from public._fn_proy_window_split(public.proy_cfg('proy_meses_ventana',6)::int)),
       p12 as (select item, proy_cajas, proy_lk, proy_chef from public._fn_proy_window_split(public.proy_cfg('proy_meses_fallback',12)::int)),
       merged0 as (
         select coalesce(p6.item, p12.item) as item,
                case when coalesce(p6.proy_cajas, 0) > 0 then p6.proy_cajas
                     when coalesce(p12.proy_cajas, 0) > 0 then p12.proy_cajas
                     else 0 end as proy_cajas,
                case when coalesce(p6.proy_cajas, 0) > 0 then p6.proy_lk
                     when coalesce(p12.proy_cajas, 0) > 0 then p12.proy_lk
                     else 0 end as proy_lk,
                case when coalesce(p6.proy_cajas, 0) > 0 then p6.proy_chef
                     when coalesce(p12.proy_cajas, 0) > 0 then p12.proy_chef
                     else 0 end as proy_chef
         from p6 full join p12 on p12.item = p6.item
       ),
       -- v24.70-vuelta: nuevos / reincorporados con 2+ meses cerrados → promedio desde que volvieron
       _vt_l as (
         select coalesce(r.to_code, s.nitem) as item, date_trunc('month', s.invoice_date::date)::date as m,
                sum(s.boxes::numeric) as v, coalesce(sum(s.boxes::numeric) filter (where s.empresa = 'lk'), 0) as v_lk
           from public.ventas_proy_lineas s
           left join public.sales_item_remap r on r.from_code = s.nitem
          where s.invoice_date ~ '^\d{4}-\d{2}-\d{2}' and s.empresa in ('lk','chef') and s.customer_code is not null
            and s.invoice_date >= to_char(current_date - interval '30 months', 'YYYY-MM-DD')
            and s.invoice_date <  to_char(date_trunc('month', current_date), 'YYYY-MM-DD')
            and not exists (select 1 from public.ventas_clientes_internos vi where vi.empresa = s.empresa and vi.cod_cliente = s.customer_code::text)
            and not exists (select 1 from public.sales_excluded_items e where e.item_code = s.nitem)
          group by 1, 2
       ),
       _vt_f as (
         select item, max(m) filter (where gap) as desde
           from (select item, m, coalesce(m - lag(m) over (partition by item order by m) > 185, true) as gap from _vt_l) z
          group by item
       ),
       _vt as (
         select f.item, sum(l.v) as tot, sum(l.v_lk) as tot_lk,
                ((extract(year from date_trunc('month', current_date))*12 + extract(month from date_trunc('month', current_date)))
                 - (extract(year from f.desde)*12 + extract(month from f.desde))) as meses
           from _vt_f f join _vt_l l on l.item = f.item and l.m >= f.desde
          where f.desde >= (date_trunc('month', current_date) - interval '6 months')::date
            and f.item !~ '^[0-9]{5,}$'   -- los de 5 dígitos no se stockean: se hacen contra pedido (Thomas 30/09)
          group by f.item, f.desde
       ),
       merged as (
         select coalesce(m.item, v.item) as item,
                case when v.meses >= 2 and v.tot > 0 and round(v.tot / v.meses, 2) > coalesce(m.proy_cajas, 0)
                     then round(v.tot / v.meses, 2) else coalesce(m.proy_cajas, 0) end as proy_cajas,
                case when v.meses >= 2 and v.tot > 0 and round(v.tot / v.meses, 2) > coalesce(m.proy_cajas, 0)
                     then round(round(v.tot / v.meses, 2) * v.tot_lk / v.tot, 2) else coalesce(m.proy_lk, 0) end as proy_lk,
                case when v.meses >= 2 and v.tot > 0 and round(v.tot / v.meses, 2) > coalesce(m.proy_cajas, 0)
                     then round(v.tot / v.meses, 2) - round(round(v.tot / v.meses, 2) * v.tot_lk / v.tot, 2) else coalesce(m.proy_chef, 0) end as proy_chef
           from merged0 m full join _vt v on v.item = m.item
       ),
       conbase as (
         select item, proy_cajas, proy_lk, proy_chef,
                regexp_replace(item, '([0-9E])L$', '\1') as base
         from merged
       )
  select m.item as cod, m.proy_cajas as proy_cajas_mes,
         coalesce(p.uxb, lk.uxb, pb.uxb, lkb.uxb)::integer as uxb,
         round(m.proy_cajas * coalesce(p.uxb, lk.uxb, pb.uxb, lkb.uxb, 1))::numeric as proy_uni_mes,
         m.proy_lk as proy_cajas_lk, m.proy_chef as proy_cajas_chef
  from conbase m
  left join public.products p on regexp_replace(upper(p.cod),'^0+(?=.)','') = m.item
  left join public.loke_products lk on regexp_replace(upper(lk.cod),'^0+(?=.)','') = m.item
  left join public.products pb on m.base <> m.item
       and regexp_replace(upper(pb.cod),'^0+(?=.)','') = m.base
  left join public.loke_products lkb on m.base <> m.item
       and regexp_replace(upper(lkb.cod),'^0+(?=.)','') = m.base
  where m.proy_cajas > 0
  order by m.proy_cajas desc;
$function$;
-- Rollback: la definición anterior es la misma sin los CTE _vt_* (merged0 se llamaba merged).
