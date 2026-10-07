-- v27.61 (Luis, 07/10) · proyecto LK (kwkclwhmoygunqmlegrg)
-- wa_avisos_retiro_web() (cron 66, cada 10 min) tardaba ~4,8 s por corrida: el planner unía la vista
-- remota virgilio.gv_pedido_web_estado_pagina (FDW a Gestión) contra orders/v_pedidos_web y la volvía
-- a pedir por fila. Ahora la lee UNA vez ya filtrada (offset 0 = barrera de optimización) y recién
-- ahí une. Misma lógica y mismos filtros. Medido: consulta 2.459 ms -> 17 ms; función entera 71 ms.
do $$ declare d text; n text; v_old text; v_new text; begin
 d := pg_get_functiondef('public.wa_avisos_retiro_web()'::regprocedure);
 if d like '%v27.61-fdw-1vez%' then return; end if;
 v_old := $q$    from virgilio.gv_pedido_web_estado_pagina e
    join orders o on o.id = e.order_id
    join customers c on c.id = o.customer_id$q$;
 v_new := $q$    -- v27.61-fdw-1vez: la vista remota (FDW a Gestión) se lee UNA vez y se filtra local antes de unir (2,5 s -> 17 ms)
    from (select order_id, empresa, estado, entregado, fecha_entrega from virgilio.gv_pedido_web_estado_pagina
           where empresa = 'lk' and estado = 'facturado' and not coalesce(entregado, false) offset 0) e
    join lateral (select o0.* from orders o0 where o0.id = e.order_id and o0.sheets_sent
                    and o0.created_at > now() - interval '30 days' offset 0) o on true
    join customers c on c.id = o.customer_id$q$;
 n := replace(d, v_old, v_new);
 if n = d then raise exception 'no matcheó'; end if;
 execute n;
end $$;
-- Rollback: volver a las 3 líneas de v_old.
