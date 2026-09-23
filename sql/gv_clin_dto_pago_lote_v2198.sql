-- v21.98 (Vivi, 2026-09-23) — el 25 % por pago adelantado va TAMBIEN en la celda Monto y en el
-- Speech 1. Antes vivia solo en el pop-up de composicion (v21.92).
--
-- QUE SE MIDIO. LK 1448 (Silvano, LK 4282): la pantalla decia `c/IVA $2.052.219` y el pedido en
-- la base de LK guarda `subtotal 1.696.048,956 · payment_discount 0,25 · total 1.272.036,717`.
-- O sea que el numero que se le reclamaba al cliente estaba **25 % arriba** de lo que tiene que
-- pagar: $1.539.164,43 con IVA, no $2.052.219.
--
-- POR QUE UNA RPC NUEVA Y NO TOCAR gv_clientes_nuevos_valor_lote. Esa funcion alimenta el limite
-- de credito y la cuarentena; cambiarle la firma obliga a DROP y deja a los llamadores en el aire.
-- Esto es ADITIVO: una lectura aparte, en su propia llamada con su propio catch, y si falla la
-- celda sigue mostrando lo de siempre (regla: una lectura ROTA no es un CERO — sin dato NO se
-- asume 25 %).
--
-- ⚠ El descuento sale del PLAZO DE PAGO del pedido (`lk_pedidos_match.metodo_pago` →
--   `deudores_condiciones.dias` → `cobranzas_escalones`), que es la misma cadena de
--   gv_dto_pago_pedido (v21.92). Contado = 0-14 dias = 25 %.
--
-- Rollback: drop function public.gv_clin_dto_pago_lote(jsonb);

CREATE OR REPLACE FUNCTION public.gv_clin_dto_pago_lote(p_pedidos jsonb)
 RETURNS TABLE(empresa text, order_id text, metodo_pago text, escalon_label text, dto numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select s.empresa, s.order_id, d.metodo_pago, d.escalon_label, d.dto
    from (select lower(coalesce(e->>'empresa','lk'))  as empresa,
                 nullif(trim(e->>'order_id'), '')     as order_id
            from jsonb_array_elements(coalesce(p_pedidos, '[]'::jsonb)) e
           where nullif(trim(e->>'order_id'), '') is not null) s
    cross join lateral public.gv_dto_pago_pedido(s.empresa, s.order_id) d
   where es_supervisor_virgilio() or gv_es_supervisor_o_servicio();
$function$;

revoke all on function public.gv_clin_dto_pago_lote(jsonb) from public;
grant execute on function public.gv_clin_dto_pago_lote(jsonb) to authenticated, service_role;

insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
values ('gv_clin_dto_pago_lote','funcion','gv_dto_pago_pedido',
        'El descuento por plazo de pago del lote sale de gv_dto_pago_pedido, no se recalcula aparte: una sola cadena metodo_pago -> dias -> escalon.',
        'Vivi','v21.98')
on conflict do nothing;

-- Chequeo:  select * from public.gv_clin_dto_pago_lote(
--   '[{"empresa":"lk","order_id":"1448"}]'::jsonb);   -- Contado / 0,2500
