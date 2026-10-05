-- =============================================================================
-- v26.77 · PROYECTO LK (kwkclwhmoygunqmlegrg) · krikos-auto-import para las cadenas que
-- facturan por Chef (Cencosud con L, Dorinka sin L). Luis, 05/10/2026: «DORINKA Y CENCOSUD
-- QUIERO QUE SE CARGUEN AUTOMATICAMENTE».
-- =============================================================================
-- El pedido se crea en la base de Chef por la puerta krikos_crear_pedido_super (SQL que corrió
-- Luis en Chef, sql/chef_krikos_v2673_CHEF_*.sql). Acá van las tres piezas del lado de LK que
-- usa admin/krikos-auto-import.js (Edge Function krikos-auto-import), todas sólo service_role:
--
--   krikos_auto_chef_ctx(super_key)   el cliente de Chef (por el FDW, con vend, deuda, límite y
--                                     plazo; si Chef no contesta, de chef_customers_cache) y el
--                                     cod_remap de la cadena (Dorinka: 838 → 838E). Mismo origen
--                                     que el panel (scot_chef_cliente_super), sin el control de
--                                     admin porque la llama el servidor.
--   krikos_auto_chef_oc_cargada(oc)   ¿esa OC ya está cargada en Chef? (chef_orders.pdf_oc), con
--                                     el total y lo que dice el pedido, para no duplicar lo que
--                                     se cargó a mano y para comparar en modo prueba.
--   krikos_auto_marcar_chef(...)      deja la fila de la bandeja como 'cargado' con el número de
--                                     pedido de Chef (lo mismo que hace el panel al subirla).
--
-- Aplicado en LK el 05/10/2026 (bloque DO + execute desde la sesión; verificado contra las OC 9400210783,
-- 198413613, 940661104 y 210202906, ya cargadas a mano en Chef).
--
-- Rollback:
--   drop function public.krikos_auto_chef_ctx(text);
--   drop function public.krikos_auto_chef_oc_cargada(text);
--   drop function public.krikos_auto_marcar_chef(bigint, bigint, text, text);
-- =============================================================================

create or replace function public.krikos_auto_chef_ctx(p_super_key text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_cod   text;
  v_remap jsonb;
  v_usa   boolean;
  v_cli   jsonb;
begin
  select btrim(c.cod_cliente_chef), c.cod_remap, c.usa_productos_chef
    into v_cod, v_remap, v_usa
    from precios_super.cadena c
   where c.super_key = p_super_key and c.activo and c.empresa = 'chef';
  if not found then return null; end if;
  if coalesce(v_cod, '') <> '' then
    begin
      select jsonb_build_object(
               'id', s.id, 'cod_cliente', s.cod_cliente::text, 'business_name', s.business_name,
               'vend', s.vend, 'debt', s.debt, 'credit_limit', s.credit_limit,
               'payment_term', s.payment_term, 'parcial', false)
        into v_cli
        from chef_ext.customers_super s
       where s.cod_cliente = v_cod::bigint
       limit 1;
    exception when others then
      v_cli := null;
    end;
    if v_cli is null then
      select jsonb_build_object(
               'id', cc.id, 'cod_cliente', cc.cod_cliente::text, 'business_name', cc.business_name,
               'vend', null, 'debt', null, 'credit_limit', null, 'payment_term', null, 'parcial', true)
        into v_cli
        from chef_customers_cache cc
       where cc.cod_cliente::text = v_cod
       limit 1;
    end if;
  end if;
  return jsonb_build_object('cod_cliente_chef', v_cod, 'cod_remap', v_remap,
                            'usa_productos_chef', coalesce(v_usa, false), 'customer', v_cli);
end
$fn$;

create or replace function public.krikos_auto_chef_oc_cargada(p_oc text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare v jsonb;
begin
  if coalesce(btrim(p_oc), '') = '' then return '[]'::jsonb; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
           'order_id', o.id, 'creado', o.created_at, 'payment_method', o.payment_method,
           'total', t.total, 'sheets_payload', o.sheets_payload) order by o.id), '[]'::jsonb)
    into v
    from public.chef_orders o
    left join chef_ext.orders_total t on t.id = o.id
   where o.sheets_payload ->> 'pdf_oc' = btrim(p_oc);
  return v;
end
$fn$;

create or replace function public.krikos_auto_marcar_chef(p_id bigint, p_order_id bigint,
                                                          p_auto_estado text, p_auto_aviso text)
returns void
language sql
security definer
set search_path = public
as $fn$
  update public.krikos_oc_inbox
     set estado = 'cargado', order_id = p_order_id, resuelto_at = now(),
         auto_estado = p_auto_estado, auto_aviso = p_auto_aviso, auto_at = now()
   where id = p_id and order_id is null;
$fn$;

revoke all on function public.krikos_auto_chef_ctx(text) from public, anon, authenticated;
revoke all on function public.krikos_auto_chef_oc_cargada(text) from public, anon, authenticated;
revoke all on function public.krikos_auto_marcar_chef(bigint, bigint, text, text) from public, anon, authenticated;
grant execute on function public.krikos_auto_chef_ctx(text) to service_role;
grant execute on function public.krikos_auto_chef_oc_cargada(text) to service_role;
grant execute on function public.krikos_auto_marcar_chef(bigint, bigint, text, text) to service_role;

-- Chequeo (sólo lectura):
--   select public.krikos_auto_chef_ctx('cencosud'), public.krikos_auto_chef_ctx('dorinka');
--   select public.krikos_auto_chef_oc_cargada('<nro de una OC de Cencosud ya cargada>');
