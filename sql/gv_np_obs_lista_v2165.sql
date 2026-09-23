-- v21.65 (Luis, 2026-09-23) — aplicado en Gestión el 23/09.
-- (1) Badge «💬 comentario» en la NP de Programación: gv_np_obs_lista(p_nps) devuelve el comentario
--     de la NP o, si la NP se programó antes de que llegara la copia de LK, el del pedido. Solo lectura.
-- (2) En LK (kwkclwhmoygunqmlegrg), también aplicado el 23/09: v_pedidos_web_np y
--     gv_pedidos_web_np_chef(_admin) suman retiro_fecha / retiro_franja AL FINAL, sacados de
--     orders.sheets_payload / chef_orders_cache.sheets_payload. Así A Programar muestra el día de
--     retiro apenas entra el pedido (antes esperaba la copia de lk_pedidos_match, c/15 min).
--     Permisos de la de Chef: service_role + gv_reader (la _admin: authenticated + service_role).
create or replace function public.gv_np_obs_lista(p_nps text[])
returns table(np text, obs text)
language sql stable security definer
set search_path to 'public', 'pg_temp'
as $$
  select l.lab, coalesce(nullif(btrim(w.observaciones), ''), nullif(btrim(m.observaciones), ''))
    from public."PPP_Web_Programacion" w
    cross join lateral (select public.gv_ppp_web_np_label(w.empresa, w.np, w.np_idx) as lab) l
    left join public.lk_pedidos_match m on m.empresa = w.empresa and m.order_id = w.order_id
   where w.np is not null
     and l.lab = any (p_nps)
     and coalesce(nullif(btrim(w.observaciones), ''), nullif(btrim(m.observaciones), '')) is not null;
$$;
revoke execute on function public.gv_np_obs_lista(text[]) from public;
grant execute on function public.gv_np_obs_lista(text[]) to anon, authenticated, service_role;
-- rollback: drop function public.gv_np_obs_lista(text[]);
