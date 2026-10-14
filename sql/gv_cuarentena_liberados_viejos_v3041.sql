-- v30.41 (Luis, 14/10/2026, D2): un pedido que estuvo en cuarentena MÁS que la ventana del armador
-- (PPP_Web_Config.ventana_dias = 30) ya no venía en el feed de la Edge Function
-- gv-ppp-web-tandas-diarias: al aprobarlo, nadie lo programaba. Esta función le dice a la Edge
-- qué pedidos APROBADOS quedaron afuera de la ventana y sin tanda; la Edge los vuelve a leer con
-- una ventana más ancha, SÓLO esos (el resto de lo viejo no entra: no se reprograma basura vieja).
-- Tope: 120 días. Lo anulado/cancelado lo sigue sacando gv_pedidos_web_excluidos aguas abajo.
create or replace function public.gv_cuarentena_liberados_viejos(p_empresa text, p_ventana integer default 30)
returns table(order_id bigint, fecha_pedido date)
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $function$
  -- v30.41-cuar-viejos
  select m.order_id, min(m.fecha_pedido)
    from public.lk_pedidos_match m
   where m.empresa = lower(p_empresa)
     and m.fecha_pedido <  current_date - greatest(coalesce(p_ventana, 30), 1)
     and m.fecha_pedido >= current_date - 120
     and exists (select 1 from public.gv_cuarentena_liberados_familia lb
                  where lb.empresa = m.empresa
                    and public.gv_cuarentena_clave(lb.order_id) = m.order_id::text)
     and not exists (select 1 from public."PPP_Web_Programacion" w
                      where w.empresa = m.empresa and w.order_id = m.order_id
                        and coalesce(nullif(btrim(w.tanda), ''), '') <> '')
   group by m.order_id;
$function$;

revoke all on function public.gv_cuarentena_liberados_viejos(text, integer) from public, anon, authenticated;
grant execute on function public.gv_cuarentena_liberados_viejos(text, integer) to service_role;
