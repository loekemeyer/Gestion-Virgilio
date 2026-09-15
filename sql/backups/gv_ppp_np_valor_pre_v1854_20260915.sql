-- Definición VIVA de gv_ppp_np_valor ANTES de la v18.54 (rollback).
-- Problema: el uxb salía de una subconsulta escalar CORRELACIONADA, o sea un Seq Scan de
-- GV_UxB por cada línea de pedido (10.969 loops, 197.442 buffers) = 28.325 ms contra un
-- statement_timeout de 8 s → HTTP 500.
create or replace view public.gv_ppp_np_valor as
 with lin as (
   select regexp_replace(btrim(b.pedido), '\.0+$', '') as np,
          case when btrim(b.pedido) ~ '^4' then 'chef' else 'lk' end as empresa,
          b.articulo, coalesce(b.cajas, 0::numeric) as cajas
     from gv_ppp_base_pedidos b
    where b.articulo is not null and coalesce(b.cajas, 0::numeric) > 0::numeric
   union all
   select w.np_label, lower(w.empresa), w.articulo, coalesce(w.cajas, 0::numeric)
     from "PPP_Web_Base" w
    where w.articulo is not null and coalesce(w.cajas, 0::numeric) > 0::numeric
 ), lin2 as (
   select l.np, l.empresa, l.articulo, l.cajas,
          case when upper(btrim(l.articulo)) ~ '[0-9E]L$' then 'lk' else l.empresa end as empresa_precio,
          case when upper(btrim(l.articulo)) ~ '[0-9E]L$' then regexp_replace(upper(btrim(l.articulo)), 'L$', '')
               else l.articulo end as articulo_precio
     from lin l
 ), pr as (
   select l.np, l.empresa, l.articulo, l.cajas,
          (select max(e.uxb) from gv_uxb_emp e
            where e.empresa_precio = l.empresa_precio and e.cod_canon = canon_cod(l.articulo_precio)) as uxb,
          case when l.empresa_precio = 'chef' then pc.precio_unit else pv.precio_unit end as precio_unit
     from lin2 l
     left join precios_venta pv on l.empresa_precio <> 'chef' and canon_cod(pv.cod) = canon_cod(l.articulo_precio)
     left join precios_venta_chef pc on l.empresa_precio = 'chef' and canon_cod(pc.cod) = canon_cod(l.articulo_precio)
 )
 select np, empresa,
        round(sum(cajas * coalesce(uxb, 1)::numeric * coalesce(precio_unit, 0::numeric)), 0) as valor_lista,
        count(*) as lineas,
        count(*) filter (where precio_unit is null or precio_unit <= 0::numeric) as lineas_sin_precio,
        sum(cajas) as cajas
   from pr
  group by np, empresa;
alter view public.gv_ppp_np_valor set (security_invoker = true);
