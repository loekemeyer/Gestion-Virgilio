-- v31.83 — Cotizacion para las paginas LK y Chef (admin «Pedidos Sin Cotizador», Luis 16/10/2026).
-- APLICADO en Gestion (hrxfctzncixxqmpfhskv) el 16/10/2026: migraciones `gv_web_cotiza_vistas` y
-- `gv_web_cotiza_precio_super_definer`.
--
-- "Cuando entra a Gestion y la PPP te cotiza cuanta plata es el pedido... las paginas deberian poder
-- cotizarlo" (Luis). Estas dos vistas exponen los MISMOS datos y reglas que gv_ppp_web_valor_items:
--   precio unit = lista del super (cliente de cadena con lista propia)
--                 -> lista LK (precios_venta)  [Chef: solo codigos con L]
--                 -> lista Chef (precios_venta_chef) [solo Chef]
--   uxb         = la del super, si no max(GV_UxB) por gv_cod_stock, si no 1
--   dto_vol     = clientes_dto (0 si es cliente de cadena con lista propia)
--   valor linea = cajas * uxb * precio * (1 - dto_vol) * factor_web (0,98 cond web; 1 «Sin Cotizador»)
-- ⚠ Si cambia la cuenta de gv_ppp_web_valor_items, cambiar tambien estas vistas.
-- Verificado el 16/10 sobre 331 pedidos web programados (286 LK, 45 Chef, 22 de cadena):
-- 0 diferencias contra gv_ppp_web_valor_items.
--
-- Se leen SOLO por FDW: lk_ppp_reader (LK, RPC admin_cotiza_cliente) y ch_ppp_reader (Chef).
-- Sin anon/authenticated: son precios y descuentos por cliente.
-- ⚠ cobranzas_precios_super es security_invoker: leida por el rol FDW la RLS de precios_super_lk la
-- deja en 0 filas SIN error. Por eso se lee a traves de la funcion definer de abajo.

create or replace function public.gv_web_cotiza_precio_super()
returns table(super_key text, nc text, precio_unit numeric, uxb integer)
language sql stable security definer set search_path to 'public'
as $$ select ps.super_key, ps.nc, ps.precio_unit, ps.uxb::int from public.cobranzas_precios_super ps $$;
revoke all on function public.gv_web_cotiza_precio_super() from anon, authenticated, public;
grant execute on function public.gv_web_cotiza_precio_super() to lk_ppp_reader, ch_ppp_reader;

create or replace view public.gv_web_cotiza_precio as
  with ux as (
    select public.gv_cod_stock(g.cod) as k, max(g.uxb) as uxb
      from public."GV_UxB" g where g.uxb > 0 group by 1
  )
  select 'lk'::text as lista, public.canon_cod(pv.cod) as cod, pv.precio_unit,
         coalesce(ux.uxb, 1)::int as uxb
    from public.precios_venta pv
    left join ux on ux.k = public.gv_cod_stock(pv.cod)
  union all
  select 'chef', public.canon_cod(pc.cod), pc.precio_unit, coalesce(ux.uxb, 1)::int
    from public.precios_venta_chef pc
    left join ux on ux.k = public.gv_cod_stock(pc.cod)
  union all
  select ps.super_key, ps.nc, ps.precio_unit,
         coalesce(ps.uxb, (select ux.uxb from ux where ux.k = public.gv_cod_stock(ps.nc)), 1)::int
    from public.gv_web_cotiza_precio_super() ps;

create or replace view public.gv_web_cotiza_cliente as
  select coalesce(cd.empresa, ca.empresa) as empresa,
         coalesce(cd.cod_cliente, ca.cod_cliente) as cod_cliente,
         ca.super_key,
         case when ca.super_key is not null then 0 else coalesce(cd.dto_vol, 0) end as dto_vol
    from public.clientes_dto cd
    full join (
      select case when cc.empresa = 'lk' then 'lk' else 'chef' end as empresa,
             btrim(cc.cod_cliente) as cod_cliente, cc.super_key
        from public.cobranzas_cliente_cadena cc
        join public.cobranzas_super_cadena sc on sc.super_key = cc.super_key and not sc.usa_lista_general
    ) ca on ca.empresa = cd.empresa and ca.cod_cliente = btrim(cd.cod_cliente);

revoke all on public.gv_web_cotiza_precio, public.gv_web_cotiza_cliente from anon, authenticated, public;
grant select on public.gv_web_cotiza_precio, public.gv_web_cotiza_cliente to lk_ppp_reader, ch_ppp_reader;

-- ── D14 (Luis 16/10/2026): la UxB sale de gv_uxb_de(cod, empresa) (v31.94), no del max ciego ──
-- Migraciones `gv_web_cotiza_precio_uxb_de` + `gv_web_cotiza_uxb_definer`.
-- ⚠ gv_uxb_de es security invoker: por FDW da «permission denied for table GV_Articulo_Empresa_Cache»
--   (estuvo ~1 min asi). Por eso la vista llama al envoltorio definer gv_web_cotiza_uxb.
-- Precio de super sin UxB propia (40 filas): la vista lo deja en null y la pagina usa la UxB de la
-- lista de su empresa para ese codigo, si no 1 (= gv_ppp_web_valor_items). Verificado 16/10 sobre 331
-- pedidos: 0 diferencias.
create or replace function public.gv_web_cotiza_uxb(p_cod text, p_empresa text)
returns numeric language sql stable security definer set search_path to 'public'
as $$ select public.gv_uxb_de(p_cod, p_empresa) $$;
revoke all on function public.gv_web_cotiza_uxb(text, text) from anon, authenticated, public;
grant execute on function public.gv_web_cotiza_uxb(text, text) to lk_ppp_reader, ch_ppp_reader;

create or replace view public.gv_web_cotiza_precio as
  select 'lk'::text as lista, public.canon_cod(pv.cod) as cod, pv.precio_unit,
         coalesce(public.gv_web_cotiza_uxb(public.canon_cod(pv.cod), 'lk'), 1)::int as uxb
    from public.precios_venta pv
  union all
  select 'chef', public.canon_cod(pc.cod), pc.precio_unit,
         coalesce(public.gv_web_cotiza_uxb(public.canon_cod(pc.cod), 'chef'), 1)::int
    from public.precios_venta_chef pc
  union all
  select ps.super_key, ps.nc, ps.precio_unit, ps.uxb::int
    from public.gv_web_cotiza_precio_super() ps;
revoke all on public.gv_web_cotiza_precio from anon, authenticated, public;
grant select on public.gv_web_cotiza_precio to lk_ppp_reader, ch_ppp_reader;
