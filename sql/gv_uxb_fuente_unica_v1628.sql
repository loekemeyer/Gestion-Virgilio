-- ============================================================================
-- v16.28 (2026-09-12) — GV_UxB es la ÚNICA fuente de UxB. Se elimina la cascada.
--
-- Thomas: "Primero limpia las uxb. Que solo haya una y que todos los lugares que usan
-- esas tablas usen solo 1 lugar."
--
-- LO QUE MANTENÍA VIVAS LAS 8 COLUMNAS era la CASCADA DE FALLBACK. Los tres
-- resolvedores (gv_uxb_resuelto, vista_uni_x_caja, vista_uxb_articulo) consultaban
-- GV_UxB y, si no encontraban el código, bajaban por Articulos_Cajas -> OC_Maximos ->
-- maestro -> precios_venta -> proyeccion_madre. Mientras esa cascada existiera,
-- ninguna columna se podía sacar: cualquiera podía ser la que respondiera.
--
-- Medición de partida: de 960 filas resueltas, 300 NO salían de GV_UxB
--   OC_Maximos 217 · gv_uxb_lk 36 · precios_venta 21 · maestro 19 ·
--   Articulos_Cajas 4 · proyeccion_madre 2
--
-- ¿HABÍA QUE DECIDIR ALGO? No: las 5 fuentes coinciden en las 300. **0 conflictos.**
-- Así que se absorbieron tal cual, sin inventar ningún valor.
--
-- Los 36 de "gv_uxb_lk" no eran otra fuente: eran códigos que están en GV_UxB como LK
-- y el resolvedor caía a ese valor para CH. Correcto salvo para los 12 duales, que ya
-- tienen sus dos lados cargados. Ahora quedan explícitos como filas CH.
--
-- DESPIECE X ARTICULO: no se absorbió, y conviene saber por qué. Tiene DOS columnas de
-- UxB —`Uni x Cja` (vieja) y `Uni_x_Caja` (nueva)— y difiere en 21 códigos. Al mirarlos,
-- **la vieja coincide con lo resuelto en 18 de 21** y la nueva no (101: nueva 12 / vieja 6
-- / resuelto 6; 307: 100 / 24 / 24; 390-394: 12 / 24 / 24). Los otros 3 (500, 508, 708)
-- discrepan en las dos, y ahí lo resuelto coincide con lo que Thomas ya había decidido
-- ("508 x6", "708 x6"). O sea: `Despiece x Articulo.Uni_x_Caja` está mal cargada y NO es
-- fuente confiable de UxB. Queda anotada como columna a limpiar.
--
-- GRJ10 se sacó de GV_UxB: no es un artículo, son 4 partes distintas del batidor pera
-- bajo un mismo código de despiece. No le corresponde un UxB único.
--
-- EL CONTRATO DE SALIDA NO CAMBIÓ, y esto casi se rompe. Al reescribir vista_uni_x_caja
-- leyendo sólo GV_UxB, pasó de 599 a 523 filas: se perdían las 75 grafías **NNNL** (505L,
-- 438EL — el artículo de Loeke vendido por Chef), porque gv_cod_stock las colapsa al
-- código base y sus consumidores joinean por la grafía cruda. Hoy ninguno pedía una con L,
-- así que no se rompió nada visible — pero era un pozo esperando. La vista final emite
-- **las dos grafías**, cada una resolviendo su valor contra la fuente única.
--
-- MEDIDO DESPUÉS: vista_uni_x_caja 598 (era 599, falta sólo GRJ10) · vista_uxb_articulo
-- 523 (igual) · vista_stock_procesada 363 con **0 filas sin uxb** tras el refresh ·
-- vista_generador_oc 349 con los mismos 8 en cero de antes (LIBRE, "(no existe)", 505C
-- y otras partes: no son artículos) · vista_importados_partes 5 · facturación
-- $1.395.224.315,83 sin moverse · centinelas en 0.
--
-- LO QUE FALTA para poder DROPEAR las columnas: repuntar los lectores DIRECTOS, que son
-- los que todavía leen la columna sin pasar por los resolvedores —
--   Articulos_Cajas.Uni_x_Caja ........ sin lectores propios  → LISTA PARA DROPEAR
--   OC_Maximos.uni_x_caja ............. vista_generador_oc, vista_stock_procesada
--   proyeccion_madre.uxb .............. vista_generador_oc
--   maestro.Uni_x_Caja ................ v_piezas_por_tallerista, vista_racks_bajadas_pendientes
--   Importados.uni_x_caja ............. gv_importados_ordenes, vista_importados_partes
--   precios_venta(.chef).uxb .......... las vistas de valuación
--   Despiece x Articulo.Uni_x_Caja .... v_piezas_por_tallerista  (y está mal cargada)
--
-- BACKUPS: zz_backups."GV_UxB_bkp_pre_absorcion_20260912" y
--          zz_backups."GV_Viewdefs_bkp_20260912d" (las 3 definiciones previas).
-- ============================================================================

-- 1) absorber las 300 que resolvía el fallback (0 conflictos entre las 5 fuentes)
insert into public."GV_UxB" (empresa, cod, uxb, descripcion, origen, curado, actualizado)
select r.empresa, r.cod, r.uxb,
       nullif((select o.descripcion from public."OC_Maximos" o
                where public.gv_cod_stock(o.cod)=r.cod and o.activo limit 1),''),
       'absorbido del fallback 12/09 (v16.28) - venia de '||r.fuente, false, now()
from public.gv_uxb_resuelto r
where r.fuente <> 'GV_UxB'
on conflict (empresa,cod) do nothing;

delete from public."GV_UxB" where public.gv_cod_stock(cod) = 'GRJ10';

-- 2) el resolvedor: SIN cascada
create or replace view public.gv_uxb_resuelto with (security_invoker = true) as
select empresa, public.gv_cod_mostrar(cod) as cod, uxb, 'GV_UxB'::text as fuente
from public."GV_UxB" where uxb is not null;

-- 3) COMPRAR y FACTURAR: una sola fuente, mismo contrato de salida (incluidas las NNNL)
create or replace view public.vista_uni_x_caja with (security_invoker = true) as
with g as (select public.gv_cod_stock(cod) c, max(uxb) u from public."GV_UxB" where uxb > 0 group by 1),
grafias as (
  select public.gv_cod_stock(cod) base, regexp_replace(upper(btrim(cod)),'^0+(?=.)','') codn from public."GV_UxB" where uxb>0
  union select public.gv_cod_stock("Cod_Art"), regexp_replace(upper(btrim("Cod_Art")),'^0+(?=.)','') from public."Articulos_Cajas" where coalesce("Uni_x_Caja",0)>0
  union select public.gv_cod_stock(cod), regexp_replace(upper(btrim(cod)),'^0+(?=.)','') from public."OC_Maximos" where coalesce(uni_x_caja,0)>0
  union select public.gv_cod_stock("Cod_Art"::text), regexp_replace(upper(btrim("Cod_Art"::text)),'^0+(?=.)','') from public."Articulos Virgilio X Tallerista" where coalesce("Uni_x_Caja",0)>0
  union select public.gv_cod_stock(cod), regexp_replace(upper(btrim(cod)),'^0+(?=.)','') from public.proyeccion_madre where coalesce(uxb,0)>0
)
select x.codn, max(g.u) as uni_x_caja, 'GV_UxB'::text as fuente
from grafias x join g on g.c = x.base group by x.codn;

create or replace view public.vista_uxb_articulo with (security_invoker = true) as
with g as (select public.gv_cod_stock(cod) c, max(uxb) u from public."GV_UxB" where uxb > 0 group by 1),
grafias as (
  select public.gv_cod_stock(cod) base, regexp_replace(upper(btrim(cod)),'^0+(?=.)','') cod from public."GV_UxB" where uxb>0
  union select public.gv_cod_stock("Cod_Art"), regexp_replace(upper(btrim("Cod_Art")),'^0+(?=.)','') from public."Articulos_Cajas" where coalesce("Uni_x_Caja",0)>0
  union select public.gv_cod_stock(cod), regexp_replace(upper(btrim(cod)),'^0+(?=.)','') from public."OC_Maximos" where coalesce(uni_x_caja,0)>0
  union select public.gv_cod_stock(cod), regexp_replace(upper(btrim(cod)),'^0+(?=.)','') from public.precios_venta where coalesce(uxb,0)>0
)
select x.cod, max(g.u) as uxb, 'GV_UxB'::text as fuente
from grafias x join g on g.c = x.base group by x.cod;

-- ── verificación ──
-- select fuente, count(*) from public.gv_uxb_resuelto group by 1;   -- sólo GV_UxB
-- select count(*) from public.gv_uxb_desalineado;                   -- 0
