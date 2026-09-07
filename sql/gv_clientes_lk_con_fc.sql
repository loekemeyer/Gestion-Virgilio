-- gv_clientes_lk_con_fc.sql — proyecto LK (kwkclwhmoygunqmlegrg) · v13.75 (2026-09-07)
-- ¿A qué clientes de LK les hicimos FC Electr. en ISIS LK con artículos de Loekemeyer en los últimos N días?
-- Lo llama Gestión (A Programar y la Edge Function gv-ppp-web-tandas-diarias v18) para pasarle `fc_lk` a
-- gv_pedidos_web_excluidos de Virgilio (motivo 'cliente_fc_lk'). sales_lines llega por lote mensual (ago-26
-- hasta el 31/08, importado el 02/09); la parte reciente la cubre Virgilio con isis_lk.documentos.
-- Migración gv_clientes_lk_con_fc_v1375. Rollback: drop function public.gv_clientes_lk_con_fc(text[], int);
create or replace function public.gv_clientes_lk_con_fc(p_cods_lk text[], p_dias int default 180)
returns table (cod_lk text, ultima_fc date, fcs bigint)
language sql
stable
security definer
set search_path = public
as $$
  select s.customer_code as cod_lk,
         max(s.invoice_date)::date as ultima_fc,
         count(distinct s.invoice_date)::bigint as fcs
    from public.sales_lines s
   where s.empresa = 'lk'
     and s.customer_code = any(coalesce(p_cods_lk, '{}'))
     and s.invoice_date >= to_char(current_date - greatest(coalesce(p_dias, 180), 1), 'YYYY-MM-DD')
     and not exists (select 1 from public.sales_excluded_items x where x.item_code = s.item_code)
   group by s.customer_code
$$;
revoke all on function public.gv_clientes_lk_con_fc(text[], int) from public, anon;
grant execute on function public.gv_clientes_lk_con_fc(text[], int) to authenticated, service_role, gv_reader;
