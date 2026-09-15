-- v18.54 — gv_ppp_np_valor: 28.325 ms → 384 ms (74×). Devolvía HTTP 500.
--
-- El uxb salía de una SUBCONSULTA ESCALAR CORRELACIONADA dentro de `pr`:
--   (select max(e.uxb) from gv_uxb_emp e where e.empresa_precio = l.empresa_precio and …)
-- o sea un Seq Scan de GV_UxB (984 filas) POR CADA LÍNEA DE PEDIDO. Con 10.969 líneas
-- (9.661 de ISIS + 1.308 web) eran 10.969 loops y 197.442 buffers: 28.325 ms contra el
-- statement_timeout de 8 s de anon, así que la vista respondía 500.
--
-- Y el daño no se quedaba en su pantalla: cada llamada ocupaba una conexión del pool casi
-- medio minuto, así que arrastraba a las demás. Facturación —que dispara 15 consultas en
-- paralelo— quedaba colgada en "Cargando tandas…" sin tener nada que ver con esta vista.
--
-- El arreglo es agregar el uxb UNA sola vez y cruzarlo por hash. `MATERIALIZED` no es
-- opcional: el CTE se referencia una sola vez y sin esa palabra Postgres lo puede volver a
-- inlinear, que es exactamente el plan que se quiere evitar.
--
-- Verificado: salida IDÉNTICA (943 filas, EXCEPT ALL 0 en los dos sentidos contra el
-- snapshot zz_backups."GV_Backup_np_valor_antes_20260915") y HTTP 200 con la clave publishable.
-- Rollback: sql/backups/gv_ppp_np_valor_pre_v1854_20260915.sql
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
 ), ux as materialized (
   select e.empresa_precio, e.cod_canon, max(e.uxb) as uxb
     from gv_uxb_emp e group by 1, 2
 ), pr as (
   select l.np, l.empresa, l.articulo, l.cajas,
          u.uxb,
          case when l.empresa_precio = 'chef' then pc.precio_unit else pv.precio_unit end as precio_unit
     from lin2 l
     left join ux u on u.empresa_precio = l.empresa_precio and u.cod_canon = canon_cod(l.articulo_precio)
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

-- ⚠ CREATE OR REPLACE VIEW resetea las reloptions: sin esta línea se pierde el
-- security_invoker y la vista pasa a saltear la RLS.
alter view public.gv_ppp_np_valor set (security_invoker = true);
