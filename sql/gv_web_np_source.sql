-- gv_web_np_source(p_order_ids bigint[])  — proyecto LK (kwkclwhmoygunqmlegrg)
-- v14.56 (2026-09-09)
--
-- Devuelve, por order_id, el `source` del pedido (sheets_payload->>'source'):
--   "Web"        = el cliente lo armó él mismo por la página (self-service)
--   "Cotizador" / "Excel" / "Krikos" / "Sin Cotizador" = cargado por un admin
-- Cubre LK (public.orders) y Chef (public.chef_orders, foreign table FDW chef_db).
--
-- Lo consume el export de Facturación de Gestión (_facXlsArmar en index.html):
-- la col K del Excel a ISIS ("2% Descuento Web") se pone SOLO cuando source='Web'.
-- Regla del dueño (2026-09-09): esa leyenda es solo para los pedidos que el
-- cliente arma por la web; NO para Cargar Cotizadores / PDF Krikos / Excel Fmto
-- Cltes / Pedidos sin cot.
--
-- OBJETO NUEVO Y ADITIVO: no se modificó ninguna vista/función existente
-- (v_pedidos_web, v_pedidos_web_np, gv_pedidos_web_np_chef* quedaron intactas).
-- ROLLBACK: drop function public.gv_web_np_source(bigint[]);

create or replace function public.gv_web_np_source(p_order_ids bigint[])
returns table(empresa text, order_id bigint, source text)
language plpgsql
security definer
set search_path to public
as $function$
begin
  if not exists (select 1 from public.admins a where a.auth_user_id = auth.uid()) then
    raise exception 'Solo administradores.';
  end if;
  return query
    select 'lk'::text, o.id, coalesce(o.sheets_payload->>'source','')
      from public.orders o
     where o.id = any(p_order_ids)
    union all
    select 'chef'::text, co.id::bigint, coalesce(co.sheets_payload->>'source','')
      from public.chef_orders co
     where co.id = any(p_order_ids);
end
$function$;

revoke all on function public.gv_web_np_source(bigint[]) from public, anon;
grant execute on function public.gv_web_np_source(bigint[]) to authenticated;
