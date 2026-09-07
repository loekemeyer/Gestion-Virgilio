-- gv_cuits_con_fc_lk.sql — proyecto LK (kwkclwhmoygunqmlegrg) · v13.76 (2026-09-07)
-- Dueño: "el cod cliente no significa nada, sólo el CUIT es lo que vale". Reemplaza a gv_clientes_lk_con_fc
-- (v13.75, por código LK; dropeada en la misma migración).
--   · gv_cuits_de_chef(p_cods_ch)         → CUIT (dígitos) de cada código de Chef, desde chef_padron (todos).
--   · gv_cuits_con_fc_lk(p_cuits, p_dias) → CUITs a los que LK les hizo FC Electr. con artículos de Loeke en los
--     últimos N días: sales_lines → customers (cod_cliente → cuit), sin sales_excluded_items. sales_lines llega
--     por lote mensual (ago-26 hasta el 31/08); la parte reciente la cubre Virgilio con isis_lk.documentos
--     (contraparte_cuit). Las llama Gestión (A Programar y la Edge Function gv-ppp-web-tandas-diarias v19) para
--     pasarle `cuit` y `fc_lk` a gv_pedidos_web_excluidos v4 (motivo 'cliente_fc_lk').
-- Migración gv_cuits_de_chef_y_cuits_con_fc_lk_v1376. Rollback: drop function public.gv_cuits_de_chef(text[]);
-- drop function public.gv_cuits_con_fc_lk(text[], int);
create or replace function public.gv_cuits_de_chef(p_cods_ch text[])
returns table (cod_ch text, cuit text)
language sql stable security definer set search_path = public
as $$
  select p.cod_cliente::text as cod_ch,
         nullif(regexp_replace(coalesce(p.cuit, ''), '\D', '', 'g'), '') as cuit
    from public.chef_padron p
   where p.cod_cliente::text = any(coalesce(p_cods_ch, '{}'))
$$;
revoke all on function public.gv_cuits_de_chef(text[]) from public, anon;
grant execute on function public.gv_cuits_de_chef(text[]) to authenticated, service_role, gv_reader;

create or replace function public.gv_cuits_con_fc_lk(p_cuits text[], p_dias int default 180)
returns table (cuit text, ultima_fc date, fcs bigint, cods_lk text[])
language sql stable security definer set search_path = public
as $$
  with c as (
    select cod_cliente::text as cod_cliente, regexp_replace(coalesce(cuit, ''), '\D', '', 'g') as cuit
      from public.customers
     where regexp_replace(coalesce(cuit, ''), '\D', '', 'g') = any(coalesce(p_cuits, '{}'))
  )
  select c.cuit,
         max(s.invoice_date)::date as ultima_fc,
         count(distinct s.invoice_date)::bigint as fcs,
         array_agg(distinct s.customer_code) as cods_lk
    from public.sales_lines s
    join c on c.cod_cliente = s.customer_code
   where s.empresa = 'lk'
     and s.invoice_date >= to_char(current_date - greatest(coalesce(p_dias, 180), 1), 'YYYY-MM-DD')
     and not exists (select 1 from public.sales_excluded_items x where x.item_code = s.item_code)
   group by c.cuit
$$;
revoke all on function public.gv_cuits_con_fc_lk(text[], int) from public, anon;
grant execute on function public.gv_cuits_con_fc_lk(text[], int) to authenticated, service_role, gv_reader;
