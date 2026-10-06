-- v27.51 (Luis, 2026-10-06): "Ver pedido" del Log de Cuarentena = la MISMA composición que el
-- "Ver composición" de Clientes nuevos. Reemplaza a gv_cuarentena_pedido_detalle (v27.22), que
-- resolvía UxB/descripción contra vistas que no tienen todos los códigos (026/027 salían en blanco).
-- Acá la valorización es EXACTAMENTE la de gv_clin_composicion / gv_ppp_web_valor_items: UxB de
-- GV_UxB por gv_cod_stock, precio de precios_venta(_chef), descuento por volumen y factor web.
-- Diferencia con gv_clin_composicion: éste lee los ítems del PROPIO pedido (lk_pedidos_match), así
-- sirve para cualquier pedido del log (histórico/cerrado), y NO aplica el reparto de stock escaso
-- (muestra TODO lo que pidió el cliente: cajas_ok = cajas, falta = 0). SECURITY DEFINER + guard de
-- supervisor, igual que gv_cuarentena_log.  Rollback: drop function … .

drop function if exists public.gv_cuarentena_pedido_detalle(text, text);

create or replace function public.gv_cuarentena_pedido_composicion(p_empresa text, p_clave text)
returns table(
  art text, cajas numeric, importado boolean, uxb integer, unidades numeric,
  precio_unit numeric, bruto numeric, dto_vol numeric, dto_web numeric,
  importe numeric, sin_precio boolean, descripcion text)
language sql
stable security definer
set search_path to 'public'
as $function$
  with _pm as (
    select m.empresa, m.order_id, m.cod_cliente, m.items_string
      from public.lk_pedidos_match m
     where m.empresa  = lower(coalesce(nullif(trim(p_empresa),''),'lk'))
       and m.order_id = nullif(trim(p_clave),'')::bigint
     limit 1
  ),
  _tok as (
    select btrim(t) tok from _pm, regexp_split_to_table(coalesce(_pm.items_string,''), ',') t
  ),
  _it as (
    select regexp_match(tok, '^(.+?)[xX]([0-9]+)$') g from _tok where tok <> ''
  ),
  _items as (
    select (select empresa from _pm) empresa,
           (select cod_cliente from _pm) cod_cli,
           g[1] art, (g[2])::numeric cajas
      from _it where g is not null
  ),
  _itg as (
    select empresa, cod_cli, art, sum(cajas) cajas,
           public.gv_art_es_importado(art) imp
      from _items group by empresa, cod_cli, art
  ),
  _cli as (
    select ( select cc2.super_key
               from public.cobranzas_cliente_cadena cc2
               join public.cobranzas_super_cadena sc
                 on sc.super_key = cc2.super_key and not sc.usa_lista_general
              where cc2.empresa = case when (select min(empresa) from _itg) = 'lk' then 'lk' else 'ch' end
                and cc2.cod_cliente = btrim(coalesce((select min(cod_cli) from _itg), '')) limit 1) as super_key,
           ( select cd.dto_vol from public.clientes_dto cd
              where cd.cod_cliente = btrim(coalesce((select min(cod_cli) from _itg), ''))
                and cd.empresa = (select min(empresa) from _itg) limit 1) as dto_vol
  ),
  _val as (
    select f.art, f.cajas, f.imp, f.empresa,
           (f.empresa = 'chef' and public.canon_cod(f.art) ~ '^[0-9]+E?L$') as es_l,
           case when f.empresa = 'chef' and public.canon_cod(f.art) ~ '^[0-9]+E?L$'
                then regexp_replace(public.canon_cod(f.art),'L$','')
                else public.canon_cod(f.art) end as cod_precio,
           c.super_key,
           case when c.super_key is not null then 0 else coalesce(c.dto_vol, 0) end as dto_vol,
           1.0::numeric as factor_web
      from _itg f cross join _cli c
  ),
  _px as (
    select v.art, v.cajas, v.imp, v.dto_vol, v.factor_web,
           coalesce(ps.precio_unit, pv.precio_unit, pc.precio_unit) as precio,
           coalesce(ps.uxb, (select max(g.uxb) from public."GV_UxB" g
                              where public.gv_cod_stock(g.cod) = public.gv_cod_stock(v.cod_precio)
                                and g.uxb > 0), 1) as uxb
      from _val v
      left join public.precios_venta pv
             on (v.empresa <> 'chef' or v.es_l) and public.canon_cod(pv.cod) = v.cod_precio
      left join public.precios_venta_chef pc
             on v.empresa = 'chef' and public.canon_cod(pc.cod) = v.cod_precio
      left join public.cobranzas_precios_super ps
             on v.super_key is not null and ps.super_key = v.super_key
                and ps.nc = public.cob_norm_cod(v.art)
  )
  select x.art,
         x.cajas,
         x.imp,
         x.uxb::int,
         round(x.cajas * x.uxb::numeric, 2),
         round(coalesce(x.precio, 0), 2),
         round(case when x.precio is not null and x.precio > 0
                    then x.cajas * x.uxb::numeric * x.precio else 0 end, 2),
         round(x.dto_vol, 4),
         round(1 - x.factor_web, 4),
         round(case when x.precio is not null and x.precio > 0
                    then x.cajas * x.uxb::numeric * x.precio * (1 - x.dto_vol) * x.factor_web
                    else 0 end, 2),
         (x.precio is null or x.precio <= 0),
         coalesce(n.descripcion, nb.descripcion)
    from _px x
    left join public.vista_nombres_articulos n  on n.cod  = x.art
    left join public.vista_nombres_articulos nb on nb.cod = regexp_replace(x.art, '([0-9E])L$', '\1')
   where es_supervisor_virgilio() or gv_es_supervisor_o_servicio()
   order by x.art;
$function$;

revoke all on function public.gv_cuarentena_pedido_composicion(text, text) from public;
grant execute on function public.gv_cuarentena_pedido_composicion(text, text) to anon, authenticated, service_role;
