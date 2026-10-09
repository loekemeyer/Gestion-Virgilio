-- v28.97: NP canceladas (web e ISIS) para que Completar Pedido no ofrezca faltantes de pedidos cancelados.
-- Rollback: drop function public.gv_np_canceladas_lista();
create or replace function public.gv_np_canceladas_lista()
returns table(np text) language sql stable security definer set search_path = public as $$
  select distinct upper(btrim(x)) from (
    select c.np_label x from public."GV_Web_Cancelados" c where coalesce(c.np_label,'') <> ''
    union all
    select public.gv_ppp_web_np_label(p.empresa, p.np, p.np_idx) from public."PPP_Web_Programacion" p
      join public."GV_Web_Cancelados" c on c.empresa = p.empresa and c.order_id::text = p.order_id::text
     where p.np is not null
    union all
    select n.np::text from public."NP_Canceladas" n
  ) z where x is not null;
$$;
grant execute on function public.gv_np_canceladas_lista() to anon, authenticated;
