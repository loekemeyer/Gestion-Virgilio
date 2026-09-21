-- v20.78 — La toma de datos de pedidos: 1 vuelta en vez de 10, y sin la funcion por fila.
--
-- Que se midio (21/09, ventana de 22.553 s de pg_stat_statements):
--   gv_ppp_base_pedidos (select=articulo)            1.203 calls · 855 s · 711 ms de media
--   gv_ppp_base_pedidos (select=pedido,articulo,...) 1.121 calls · 815 s · 727 ms de media
--   gv_pedidos_web_excluidos                           270 calls · 566 s · hasta 7.958 ms (el timeout es 8 s)
-- O sea: 1.670 s de base, el 7,4 % de la ventana, para leer DOS VECES la misma vista entera.
--
-- Son tres cosas distintas y las tres suman:
--
-- 1) La vista llamaba a gv_espejo_np_pasa() FILA POR FILA (9.618 veces). Una funcion SQL
--    con SET search_path NO se inlinea (misma leccion que gv_destino_score, v20.62). Y con
--    el corte del espejo abierto -que es como esta desde el 06/09- la funcion devuelve
--    SIEMPRE true: las tres ramas del CASE terminan en "p_lk is null" / "p_chef is null".
--    Con el short-circuit adelante, la vista pasa de 153 ms a 33 ms. Medido: 0 filas de
--    diferencia en las dos direcciones del EXCEPT ALL.
--
-- 2) El front la leia ENTERA, 9.618 filas, y PostgREST corta en 1.000 -> 10 vueltas, cada
--    una recalculando la vista completa. Las dos vistas nuevas devuelven lo que el front
--    realmente usa, y las dos entran en UNA pagina:
--      gv_ppp_base_articulos       ->   321 filas (el panel de Despiece solo quiere los codigos)
--      gv_ppp_base_pedidos_items   ->   816 filas (el picking quiere pedido -> items)
--
-- 3) supaFetchAll mandaba Prefer: count=exact en CADA pagina, o sea un count exacto de la
--    vista entera por vuelta. Nadie usa ese total. Se saca en index.html.
--
-- Rollback: el CREATE OR REPLACE de gv_ppp_base_pedidos con la condicion vieja
-- (gv_espejo_np_pasa(b.pedido, c.lk, c.chef) pelado) + drop de las dos vistas nuevas.

create or replace view public.gv_ppp_base_pedidos as
 WITH base AS (
         SELECT b.id, b.pedido, b.articulo, b.cajas, b.cliente, b.fecha,
            regexp_replace(btrim(b.pedido), '\.0+$'::text, ''::text) AS np_n,
            upper(btrim(b.articulo)) AS art_n
           FROM "GV_PPP_Base_Pedidos" b
             CROSS JOIN gv_espejo_corte() c(lk, chef)
          -- v20.78: el short-circuit. Con el corte abierto la funcion siempre da true,
          -- y asi no se la llama una vez por fila.
          WHERE ((c.lk is null and c.chef is null) or gv_espejo_np_pasa(b.pedido, c.lk, c.chef))
            AND NOT (EXISTS ( SELECT 1 FROM "GV_PPP_Prog_Override" o
                  WHERE o.oculto AND o.np = regexp_replace(btrim(b.pedido), '\.0+$'::text, ''::text)))
        ), ov AS (
         SELECT o.id, regexp_replace(btrim(o.np), '\.0+$'::text, ''::text) AS np,
            upper(btrim(o.articulo)) AS articulo, o.cajas, o.quitado, o.cliente, o.fecha
           FROM "GV_PPP_Base_Override" o
        )
 SELECT b.id, b.pedido, b.articulo, b.cajas, b.cliente, b.fecha
   FROM base b
  WHERE NOT (EXISTS ( SELECT 1 FROM ov o WHERE o.np = b.np_n AND o.articulo = b.art_n))
UNION ALL
 SELECT min(b.id) AS id, min(b.pedido) AS pedido, min(b.articulo) AS articulo,
    max(o.cajas) AS cajas, min(b.cliente) AS cliente, min(b.fecha) AS fecha
   FROM base b JOIN ov o ON o.np = b.np_n AND o.articulo = b.art_n
  WHERE NOT o.quitado GROUP BY o.id
UNION ALL
 SELECT - o.id AS id, o.np AS pedido, o.articulo, o.cajas,
    COALESCE(o.cliente, d.cliente) AS cliente, COALESCE(o.fecha, d.fecha) AS fecha
   FROM ov o
     LEFT JOIN LATERAL ( SELECT b2.cliente, b2.fecha FROM base b2 WHERE b2.np_n = o.np LIMIT 1) d ON true
  WHERE NOT o.quitado AND NOT (EXISTS ( SELECT 1 FROM base b3 WHERE b3.np_n = o.np AND b3.art_n = o.articulo));

-- CREATE OR REPLACE VIEW sin WITH (...) BORRA las reloptions: sin esta linea la vista
-- pasa a correr como postgres y saltea la RLS.
alter view public.gv_ppp_base_pedidos set (security_invoker = true);

-- Solo los codigos. Lo unico que usa el panel de Despiece de esa vista.
create or replace view public.gv_ppp_base_articulos as
  select distinct btrim(articulo) as articulo
    from public.gv_ppp_base_pedidos
   where nullif(btrim(coalesce(articulo,'')), '') is not null;
alter view public.gv_ppp_base_articulos set (security_invoker = true);
grant select on public.gv_ppp_base_articulos to anon, authenticated;

-- pedido -> items, en el mismo orden de id que traia el select crudo (el picking los
-- muestra en ese orden). Una fila por pedido: 816 hoy, o sea UNA pagina.
create or replace view public.gv_ppp_base_pedidos_items as
  select p.pedido,
         jsonb_agg(jsonb_build_object('a', p.articulo, 'c', p.cajas) order by p.id) as items
    from public.gv_ppp_base_pedidos p
   where nullif(btrim(coalesce(p.pedido,'')), '') is not null
   group by p.pedido;
alter view public.gv_ppp_base_pedidos_items set (security_invoker = true);
grant select on public.gv_ppp_base_pedidos_items to anon, authenticated;
