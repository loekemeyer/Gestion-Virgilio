-- v31.93 (Luis, 16/10/2026): el uxb lo manda la fila de la EMPRESA DUEÑA del artículo, nunca el max(uxb)
-- de LK y CH juntos. Caso: 231/232/233 LK pasaron de 24 a 12 (Elías, 16/10, curado) y la fila CH 24
-- (absorbida del fallback del 12/09, que venía de OC_Maximos) seguía ganando por ser la más alta.
-- Orden: empresa dueña (GV_Articulo_Empresa_Cache) > LK > curado > no absorbido del fallback > más reciente.
-- Cambió: 231, 232, 233 (24 -> 12) y 724 (24 -> 4: el dueño es LK, Vaso Fernetero; el 24 era el Espumante de Chef).
-- Aplicado en vivo; centinelas en GV_Reglas_Centinela (patrón 'r\.empresa = e\.empresa').
-- Quedan con max(uxb) sin empresa (no tocadas): gv_ppp_web_valor_items, gv_clin_composicion,
-- gv_cuarentena_pedido_composicion, isis_pedido_json, gv_isis_pedido_json.

create or replace view public.vista_uxb_articulo as
with r as (
  select gv_cod_stock(u.cod) as c, u.empresa, u.uxb, u.curado, u.origen, u.actualizado
    from "GV_UxB" u where u.uxb > 0::numeric
), g as (
  select distinct on (r.c) r.c, r.uxb as u
    from r left join "GV_Articulo_Empresa_Cache" e on e.cod_canon = r.c
   order by r.c, (r.empresa = e.empresa) desc nulls last, (r.empresa = 'LK') desc,
            r.curado desc nulls last, (coalesce(r.origen,'') ilike 'absorbido%') asc, r.actualizado desc nulls last
), grafias as (
  select gv_cod_stock("GV_UxB".cod) as base, regexp_replace(upper(btrim("GV_UxB".cod)), '^0+(?=.)', '') as cod from "GV_UxB"
  union select gv_cod_stock("Articulos_Cajas"."Cod_Art"), regexp_replace(upper(btrim("Articulos_Cajas"."Cod_Art")), '^0+(?=.)', '') from "Articulos_Cajas"
  union select gv_cod_stock("OC_Maximos".cod), regexp_replace(upper(btrim("OC_Maximos".cod)), '^0+(?=.)', '') from "OC_Maximos"
  union select gv_cod_stock(precios_venta.cod), regexp_replace(upper(btrim(precios_venta.cod)), '^0+(?=.)', '') from precios_venta
)
select x.cod, max(g.u) as uxb, 'GV_UxB'::text as fuente
  from grafias x join g on g.c = x.base
 group by x.cod;
alter view public.vista_uxb_articulo set (security_invoker = true);

create or replace view public.vista_uni_x_caja as
with r as (
  select gv_cod_stock(u.cod) as c, u.empresa, u.uxb, u.curado, u.origen, u.actualizado
    from "GV_UxB" u where u.uxb > 0::numeric
), g as (
  select distinct on (r.c) r.c, r.uxb as u
    from r left join "GV_Articulo_Empresa_Cache" e on e.cod_canon = r.c
   order by r.c, (r.empresa = e.empresa) desc nulls last, (r.empresa = 'LK') desc,
            r.curado desc nulls last, (coalesce(r.origen,'') ilike 'absorbido%') asc, r.actualizado desc nulls last
), grafias as (
  select gv_cod_stock("GV_UxB".cod) as base, regexp_replace(upper(btrim("GV_UxB".cod)), '^0+(?=.)', '') as codn from "GV_UxB"
  union select gv_cod_stock("Articulos_Cajas"."Cod_Art"), regexp_replace(upper(btrim("Articulos_Cajas"."Cod_Art")), '^0+(?=.)', '') from "Articulos_Cajas"
  union select gv_cod_stock("OC_Maximos".cod), regexp_replace(upper(btrim("OC_Maximos".cod)), '^0+(?=.)', '') from "OC_Maximos"
  union select gv_cod_stock("Articulos Virgilio X Tallerista"."Cod_Art"::text), regexp_replace(upper(btrim("Articulos Virgilio X Tallerista"."Cod_Art"::text)), '^0+(?=.)', '') from "Articulos Virgilio X Tallerista"
  union select gv_cod_stock(proyeccion_madre.cod), regexp_replace(upper(btrim(proyeccion_madre.cod)), '^0+(?=.)', '') from proyeccion_madre
)
select x.codn, max(g.u) as uni_x_caja, 'GV_UxB'::text as fuente
  from grafias x join g on g.c = x.base
 group by x.codn;
alter view public.vista_uni_x_caja set (security_invoker = true);
