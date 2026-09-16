-- ============================================================================
-- v18.95 (2026-09-16, pedido de Luis) — MONTO POR LISTA para el submódulo "Clientes nuevos"
-- ============================================================================
-- Pedido: partir Cuarentena en dos submódulos. El de "Clientes nuevos" muestra una tabla
-- (pedido / fecha / m³ / razón social / zona / contacto / MONTO). El monto es el precio
-- total del pedido según lo que pidió y la lista de precios.
--
-- NO SE INVENTA VALORIZACIÓN: se reusa `gv_ppp_web_valor_items(empresa, cod, items, cond)`,
-- la MISMA función que ya usa el control de límite de crédito (`gv_cuarentena_limite`) para
-- decir si un pedido supera el crédito. Devuelve el neto sin IVA (criterio Facturación,
-- 2% web condicional por condición de pago). Así la Cuarentena y Clientes nuevos no pueden
-- decir montos distintos del mismo pedido.
--
-- Esta RPC sólo la EXPONE por lote: recibe la misma lista de items que arma el front
-- (cuarItemsDe → [{art, cajas}]) y devuelve el monto por pedido. Es aditiva, prefijo gv_,
-- SECURITY DEFINER con el mismo gate de supervisor que el resto de la Cuarentena. NO toca
-- ningún objeto compartido ni datos.
--
-- ROLLBACK:
--   drop function public.gv_clientes_nuevos_valor_lote(jsonb);
-- ============================================================================

create or replace function public.gv_clientes_nuevos_valor_lote(p_pedidos jsonb)
 returns table(order_id text, empresa text, valor numeric)
 language sql
 security definer
 set search_path to 'public'
as $function$
  select nullif(trim(e->>'order_id'), '')          as order_id,
         lower(coalesce(e->>'empresa','lk'))        as empresa,
         round(public.gv_ppp_web_valor_items(
                 lower(coalesce(e->>'empresa','lk')),
                 nullif(trim(e->>'cod'), ''),
                 e->'items',
                 nullif(e->>'cond','')), 2)          as valor
  from jsonb_array_elements(coalesce(p_pedidos, '[]'::jsonb)) e
  where (es_supervisor_virgilio() or gv_es_supervisor_o_servicio())
    and nullif(trim(e->>'order_id'), '') is not null;
$function$;

-- SECURITY DEFINER: Supabase le da EXECUTE a anon a toda función nueva → revocarlo a mano.
revoke all on function public.gv_clientes_nuevos_valor_lote(jsonb) from public, anon;
grant execute on function public.gv_clientes_nuevos_valor_lote(jsonb) to authenticated, service_role;

comment on function public.gv_clientes_nuevos_valor_lote(jsonb) is
  'v18.95 (Luis, 2026-09-16): monto por lista (neto sin IVA) de cada pedido del submódulo '
  'Clientes nuevos. Reusa gv_ppp_web_valor_items (misma valorización que el límite de crédito). '
  'Gate supervisor; sin gate devuelve 0 filas. Aditiva, no toca objetos compartidos.';

-- Chequeos:
--   select has_function_privilege('anon',   'public.gv_clientes_nuevos_valor_lote(jsonb)', 'EXECUTE');  -- false
--   select has_function_privilege('authenticated', 'public.gv_clientes_nuevos_valor_lote(jsonb)', 'EXECUTE');  -- true
