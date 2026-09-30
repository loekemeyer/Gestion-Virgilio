-- LK (kwkclwhmoygunqmlegrg) — Luis 30/09/2026, problema 640.
-- Desglose por cliente del pop-up de proyección con el MISMO criterio que el total mensual
-- (fn_ventas_mensuales_virgilio): familia (lista de códigos), regla L (ventas_proy_lineas pela
-- la L), sin ventas entre empresas, sales_item_remap y sales_excluded_items.
-- Devuelve además `codigos`: de qué código salió cada cliente ("702E 7 · 702EN 5").
-- Rollback: drop function public.fn_ventas_clientes_mes_fam_virgilio(text,text,text);
--   (la vieja fn_ventas_clientes_mes_virgilio no se tocó)
create or replace function public.fn_ventas_clientes_mes_fam_virgilio(p_cods text, p_mes text, p_empresa text default null)
returns table(cliente text, cajas numeric, codigos text)
language sql stable security definer set search_path to 'public' set statement_timeout to '30s'
as $function$
  with gate as (
    select 1
    where coalesce(nullif(current_setting('request.headers', true), '')::json ->> 'x-feed-secret', '')
        = coalesce((select value from app_settings where key = 'virgilio_feed_secret'), '__no_secret__')
  ),
  tgt as (
    select substr(btrim(coalesce(p_mes, '')), 1, 7) as mes,
           nullif(lower(btrim(coalesce(p_empresa, ''))), '') as emp
  ),
  cods as (   -- la familia, normalizada igual que nitem de ventas_proy_lineas
    select distinct regexp_replace(regexp_replace(upper(btrim(x)), '^0+(?=.)', ''), '([0-9E])L$', '\1') as cod
    from unnest(string_to_array(coalesce(p_cods, ''), ',')) x where btrim(x) <> ''
  ),
  -- candidatos de item_code LITERALES, para entrar por idx_sales_lines_item_invoice:
  -- el código, con ceros adelante, con L (regla L), y los from_code que el remap manda acá.
  raiz as (
    select cod as v from cods
    union select r.from_code from public.sales_item_remap r join cods on r.to_code = cods.cod
  ),
  cands as (
    select p || v || l as v from raiz, unnest(array['', '0', '00']) p, unnest(array['', 'L']) l
  ),
  base as (
    select sl.customer_code::text as customer_code, sl.empresa_venta, sl.boxes::numeric as v,
           coalesce(r.to_code, sl.nitem) as item
    from public.ventas_proy_lineas sl
    cross join tgt
    left join public.sales_item_remap r on r.from_code = sl.nitem
    where sl.item_code in (select v from cands)
      and sl.invoice_date >= tgt.mes || '-01'
      and sl.invoice_date <  to_char((tgt.mes || '-01')::date + interval '1 month', 'YYYY-MM-DD')
      and sl.invoice_date ~ '^\d{4}-\d{2}-\d{2}'
      and (tgt.emp is null or sl.empresa = tgt.emp)
      and not exists (select 1 from public.sales_excluded_items e where e.item_code = sl.nitem)
  ),
  enfam as (select b.* from base b where b.item in (select cod from cods)),
  connom as (
    select coalesce(
             nullif(btrim(case when b.empresa_venta = 'chef' then cc.business_name else c.business_name end), ''),
             b.customer_code) as cliente, b.item, b.v
    from enfam b
    left join public.customers            c  on b.empresa_venta = 'lk'   and c.cod_cliente::text  = b.customer_code
    left join public.chef_customers_cache cc on b.empresa_venta = 'chef' and cc.cod_cliente::text = b.customer_code
  ),
  porcod as (select cliente, item, sum(v) v from connom group by 1, 2),
  agg as (
    select cliente, sum(v) as cajas,
           case when (select count(*) from cods) > 1
                then string_agg(item || ' ' || rtrim(to_char(v, 'FM999999990.##'), '.'), ' · ' order by item) end as codigos
    from porcod group by cliente
  ),
  rk as (select cliente, cajas, codigos, row_number() over (order by cajas desc, cliente) as rn from agg),
  otros as (
    select sum(p.v) cajas, string_agg(p.item || ' ' || rtrim(to_char(p.v, 'FM999999990.##'), '.'), ' · ' order by p.item) codigos
    from (select pc.item, sum(pc.v) v from porcod pc join rk on rk.cliente = pc.cliente and rk.rn > 5 group by 1) p
  )
  select z.cliente, z.cajas, z.codigos
  from (
    select cliente, cajas, codigos, 0 as ord, cajas as k from rk where rn <= 5
    union all
    select 'Otros', o.cajas, case when (select count(*) from cods) > 1 then o.codigos end, 1, 0::numeric
      from otros o where o.cajas > 0
  ) z, gate
  order by z.ord, z.k desc;
$function$;
revoke execute on function public.fn_ventas_clientes_mes_fam_virgilio(text,text,text) from public;
grant execute on function public.fn_ventas_clientes_mes_fam_virgilio(text,text,text) to anon, authenticated, service_role;
