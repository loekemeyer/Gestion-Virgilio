-- v20.50 (2026-09-21) — Luis: "pone esa regla de que se busque en la lista de chef si no esta en LK".
--
-- La L indica que el codigo es el mismo numero pero de Loekemeyer (702EL = 702E de LK), asi que
-- el precio se busca en la lista de LK pelando la L. Cuando LK NO lista ese numero, el pedido
-- quedaba en $0: la funcion no tenia a donde caer porque el join a precios_venta_chef llevaba
-- "and not v.es_l".
--
-- Ahora el orden es: lista del super -> lista de LK -> lista de Chef. Para un codigo con L manda
-- LK y Chef es el respaldo; para un codigo sin L de Chef nada cambia (precios_venta no joinea).
--
-- Medido el 21/09 sobre los pedidos web de Chef: 2 pedidos, 13 lineas, $15.138.480 que pasan de
-- no valorizarse a valorizarse.
--
--   chef 215:  0,00 -> 14.364.390,00      chef 229:  0,00 -> 1.471.020,00
--   chef 227 y 228 sin cambio (900.768,00 y 649.809,60) — regresion.
--   505L (codigo con L que SI esta en LK) sigue usando la lista de LK: 19.080,00.
--
-- Centinela: fila en GV_Reglas_Centinela para gv_ppp_web_valor_items; si alguien repone el
-- "and not v.es_l" el patron deja de matchear y gv_reglas_perdidas lo marca.
--
-- Rollback: reponer "and not v.es_l" en el join a precios_venta_chef y borrar esa fila.

CREATE OR REPLACE FUNCTION public.gv_ppp_web_valor_items(p_empresa text, p_cod text, p_items jsonb, p_cond text DEFAULT NULL::text)
 RETURNS numeric
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with it as (
    select nullif(trim(e->>'art'), '') as art,
           coalesce((e->>'cajas')::numeric, 0) as cajas
    from jsonb_array_elements(coalesce(p_items, '[]'::jsonb)) e
    where nullif(trim(e->>'art'), '') is not null
  ),
  cli as (
    select ( select cc2.super_key
               from cobranzas_cliente_cadena cc2
               join cobranzas_super_cadena sc on sc.super_key = cc2.super_key and not sc.usa_lista_general
              where cc2.empresa = case when lower(p_empresa)='lk' then 'lk' else 'ch' end
                and cc2.cod_cliente = btrim(coalesce(p_cod,'')) limit 1) as super_key,
           ( select cd.dto_vol from clientes_dto cd
              where cd.cod_cliente = btrim(coalesce(p_cod,'')) and cd.empresa = lower(p_empresa) limit 1) as dto_vol
  ),
  val as (
    select it.cajas,
           (lower(p_empresa)='chef' and canon_cod(it.art) ~ '^[0-9]+E?L$') as es_l,
           case when lower(p_empresa)='chef' and canon_cod(it.art) ~ '^[0-9]+E?L$'
                then regexp_replace(canon_cod(it.art),'L$','') else canon_cod(it.art) end as cod_precio,
           it.art, c.super_key,
           case when c.super_key is not null then 0 else coalesce(c.dto_vol,0) end as dto_vol,
           case when c.super_key is not null then 1.0
                when nullif(trim(coalesce(p_cond,'')),'') in ('8','9','10','11','12','13','18') then 0.98
                else 1.0 end as factor_web
    from it cross join cli c
  ),
  px as (
    select v.cajas, v.dto_vol, v.factor_web,
           -- super -> lista LK -> lista Chef. Para un codigo con L manda la lista de LK; si
           -- LK no lo tiene, cae a la de Chef (Luis, 2026-09-21, v20.49): sin eso el pedido
           -- quedaba en $0 (chef 229 y chef 215). Para un codigo sin L de Chef pv no joinea,
           -- asi que sigue valiendo su lista de siempre.
           coalesce(ps.precio_unit, pv.precio_unit, pc.precio_unit) as precio,
           coalesce(ps.uxb, (select max(g.uxb) from public."GV_UxB" g where public.gv_cod_stock(g.cod) = public.gv_cod_stock(v.cod_precio) and g.uxb > 0), 1) as uxb
    from val v
    left join precios_venta pv on (lower(p_empresa) <> 'chef' or v.es_l) and canon_cod(pv.cod) = v.cod_precio
    left join precios_venta_chef pc on lower(p_empresa) = 'chef' and canon_cod(pc.cod) = v.cod_precio
    left join cobranzas_precios_super ps on v.super_key is not null and ps.super_key = v.super_key and ps.nc = cob_norm_cod(v.art)
  )
  select coalesce(round(sum(
           case when precio is not null and precio > 0
                then cajas * uxb::numeric * precio * (1 - dto_vol) * factor_web
                else 0 end)::numeric, 2), 0)
  from px;
$function$;

insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
values ('gv_ppp_web_valor_items','funcion',
        'precios_venta_chef pc on lower\(p_empresa\) = ''chef'' and canon_cod',
        'Un codigo con L se valoriza con la lista de LK y, si LK no lo tiene, con la de Chef. El join a precios_venta_chef NO lleva "and not v.es_l": con ese filtro los pedidos de Chef con articulos de LK que LK no lista quedaban en $0 (chef 215 y 229).',
        'Luis','v20.49')
on conflict do nothing;

notify pgrst, 'reload schema';
