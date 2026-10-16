-- v31.96 (Luis 16/10, D4): uxb sin max ciego en las funciones de pedido. Aplicado en vivo con un DO que
-- reemplazó en la definición VIVA el "(select max(g.uxb) from GV_UxB ...)" por gv_uxb_de(cod, empresa).
create or replace function public.gv_uxb_de(p_cod text, p_empresa text default null)
returns numeric language sql stable as $$
  select u.uxb
    from public."GV_UxB" u
    left join public."GV_Articulo_Empresa_Cache" e on e.cod_canon = public.gv_cod_stock(p_cod)
   where public.gv_cod_stock(u.cod) = public.gv_cod_stock(p_cod) and u.uxb > 0
   order by (u.empresa = case lower(btrim(coalesce(p_empresa,''))) when 'chef' then 'CH' when 'ch' then 'CH' when 'lk' then 'LK' end) desc nulls last,
            (u.empresa = e.empresa) desc nulls last, (u.empresa = 'LK') desc,
            u.curado desc nulls last, (coalesce(u.origen,'') ilike 'absorbido%') asc, u.actualizado desc nulls last
   limit 1
$$;
-- empresa pasada: gv_ppp_web_valor_items / gv_clin_composicion / gv_cuarentena_pedido_composicion →
--   case when v.es_l then 'lk' else p_empresa end ; isis_pedido_json / gv_isis_pedido_json → null (empresa dueña).
-- D5: update "OC_Maximos" set uni_x_caja = 12 where gv_cod_stock(cod) in ('231','232','233') and uni_x_caja = 24;
