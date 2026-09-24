-- v22.16 (Luis, 24/09): la demora del Resumen de la PPP no cuenta como espera lo que NO es demora.
--   * pedido PARTIDO por un importado que todavia no llego: la parte diferida se cuenta desde
--     que el importado esta disponible (GV_PPP_Web_Diferido.no_antes_de).
--   * RETIRO con dia elegido por el cliente (lk_pedidos_match.retiro_fecha).
--   * TURNO pactado del super (lk_pedidos_match.fecha_entrega, solo si es posterior al pedido:
--     en los pedidos sin turno viene igual a la fecha del pedido).
-- Devuelve una fila por NP web programada que tiene ancla POSTERIOR a la fecha del pedido.
-- SECURITY DEFINER a proposito (trampa v20.45): lk_pedidos_match / GV_PPP_Web_Diferido tienen RLS
-- y una vista invoker le contestaria VACIO a anon sin dar error. Devuelve solo np + motivo + fecha.
create or replace function public.gv_ppp_demora_ancla()
returns table(empresa text, np text, motivo text, ancla date, fecha_pedido date)
language sql stable security definer set search_path to 'public'
as $$
  with p as (
    select p.empresa, p.order_id, p.np_idx, p.fecha_recep::date as fr,
           public.gv_ppp_web_np_label(p.empresa, p.np, p.np_idx) as np
      from public."PPP_Web_Programacion" p
     where p.np is not null and p.fecha_entrega is not null
  ), c as (
    select p.empresa, p.np, p.fr, 1 as pri, 'importado'::text as motivo, d.no_antes_de::date as ancla
      from p join public."GV_PPP_Web_Diferido" d
        on d.empresa = p.empresa and d.order_id = p.order_id and d.np_idx = p.np_idx
    union all
    select p.empresa, p.np, p.fr, 2, 'retiro_pactado', m.retiro_fecha::date
      from p join public.lk_pedidos_match m on m.empresa = p.empresa and m.order_id = p.order_id
     where m.retiro_fecha is not null
    union all
    select p.empresa, p.np, p.fr, 3, 'turno_pactado', m.fecha_entrega::date
      from p join public.lk_pedidos_match m on m.empresa = p.empresa and m.order_id = p.order_id
     where m.fecha_entrega is not null and m.fecha_entrega::date > coalesce(m.fecha_pedido::date, p.fr)
  )
  select distinct on (c.empresa, c.np) c.empresa, c.np, c.motivo, c.ancla, c.fr
    from c
   where c.ancla > c.fr
   order by c.empresa, c.np, c.pri;
$$;
revoke all on function public.gv_ppp_demora_ancla() from public;
grant execute on function public.gv_ppp_demora_ancla() to anon, authenticated, service_role;

insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
values ('gv_ppp_demora_ancla','funcion','"GV_PPP_Web_Diferido"',
        'la parte de un pedido partido por un importado que no llego no cuenta como demora en el Resumen de la PPP','Luis','v22.16');
