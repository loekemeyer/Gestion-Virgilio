-- v15.57 (2026-09-11) — Qué contenía una NP (código + cajas), con UNA sola clave de texto para
-- las dos familias: NP de ISIS ('98532', sin el '.0' del espejo) y NP web ('LK 0024', np_label).
-- Lo abre el toque sobre la NP en el Resumen de la PPP (pppResTgl → pppChequeoNp), que desde
-- esta versión lee esta vista en vez de gv_ppp_base_pedidos: ahí las NP web no existían y el
-- modal decía "No encontré artículos".
--
-- Objeto NUEVO con prefijo gv_: no cambia gv_ppp_base_pedidos (lo siguen leyendo el stock, el
-- semáforo del ✓ y las OCs) ni PPP_Web_Base. security_invoker: corre con los permisos de quien
-- consulta (anon ya lee las dos fuentes desde la app).
--
-- Prueba:  select np, origen, count(*), sum(cajas) from public.gv_np_items
--          where np in ('LK 0024','98532') group by 1,2;
--          → LK 0024 web 1 línea 5 cajas · 98532 isis 18 líneas 23 cajas
-- Rollback: drop view public.gv_np_items;  (el front cae a "No encontré artículos", no rompe)

create or replace view public.gv_np_items
with (security_invoker = true) as
select regexp_replace(btrim(b.pedido), '\.0+$', '') as np,
       btrim(b.articulo)                         as articulo,
       b.cajas::numeric                          as cajas,
       'isis'::text                              as origen
  from public.gv_ppp_base_pedidos b
 where b.pedido is not null
union all
select w.np_label                                as np,
       btrim(w.articulo)                         as articulo,
       w.cajas::numeric                          as cajas,
       'web'::text                               as origen
  from public."PPP_Web_Base" w
 where w.np_label is not null;

comment on view public.gv_np_items is
  'v15.57 — lineas (articulo, cajas) de una NP por su clave visible: ''98532'' (ISIS, sin .0) o ''LK 0024'' (web, np_label). Union de gv_ppp_base_pedidos + PPP_Web_Base. Lo abre el toque sobre la NP en el Resumen de la PPP (pppChequeoNp).';

grant select on public.gv_np_items to anon, authenticated;
