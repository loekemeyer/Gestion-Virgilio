-- v16.22 (2026-09-12) — el UxB se resuelve POR EMPRESA, y el 067 = 60
--
-- Dos cosas, las dos del pedido de Thomas ("067 60" y "2 desarrollame un poco mas").
--
-- ── 1) 067 Sacacorcho Tipo Mozo Suelto = 60 ────────────────────────────────────────────
-- El catálogo de LK decía 50 y tres tablas nuestras decían 60. Thomas resolvió: 60.
-- Queda curado en GV_UxB, así que el trigger gv_uxb_protege_curado impide que el sync lo pise.
--
-- PERO faltaba una fuga: el sync también escribía precios_venta.uxb desde el catálogo de LK,
-- y ahí NO había protección — el 067 volvía a 50 cada 15 min. Arreglado en la Edge Function
-- sync-precios-venta v12: el payload de precios_venta YA NO lleva uxb. Es la lista de PRECIOS;
-- el UxB lo manda GV_UxB y nadie más. (PostgREST con merge-duplicates sólo pisa las columnas
-- presentes en el payload, así que al sacarla la columna queda intacta.)
--
-- ── 2) los 12 códigos que son DOS productos distintos ──────────────────────────────────
-- Un mismo cod es un artículo en LK y otro en Chef: 26 es Colador N°8 en LK y Pinza de Fideos
-- en Chef; 43 es Colador 10 en LK y Tres en Uno en Chef; etc. (tabla GV_Cod_Dos_Productos).
--
-- El problema real no era el nombre: era que Facturación resolvía el UxB SIN mirar la empresa.
--   COALESCE(ps.uxb, pcl.uxb, pc.uxb, pv.uxb, ux.uxb)
--                              ^chef   ^LK    ^LK
-- Si el código no estaba en la lista de Chef (pc), caía en las dos fuentes de LK. O sea que una
-- NP de Chef podía tomar el UxB del artículo de LK que comparte el número. Pasó de verdad:
-- el 26 de una NP de Chef (Pinza de Fideos x12) se facturó con 36, el del Colador de LK.
--
-- La solución NO es cambiarle el código a Chef (eso es tocar su catálogo y el ISIS). Es que la
-- vista resuelva por empresa, que es dato que ya tenía a mano: b.empresa_precio, que además ya
-- contempla la regla de la "L" (artículo de Loeke vendido por Chef → se valúa como LK).
--
--   gv_uxb_emp (empresa_precio, cod_canon, cod_norm, uxb)  ← GV_UxB, las dos normalizaciones
--   COALESCE(ps.uxb, pcl.uxb, uxe.uxb, pc.uxb, pv.uxb, ux.uxb)
--
-- Va después de los overrides por cliente (ps = precio de súper, pcl = precio por cliente) y
-- ANTES de las listas, porque las listas traen el uxb viejo del catálogo y GV_UxB es la fuente.
--
-- IMPACTO MEDIDO en vista_facturacion_neto_items (mismas 10.604 filas): +$13.090.716 contra el
-- baseline de la mañana, de los cuales +$2.685.467 son de la v16.21. Este paso pone +$10.405.249,
-- todo en 5 códigos de Chef:
--
--   cod   líneas  antes → ahora   delta        por qué
--   824      36    12   →  36     +6.247.481   Thomas: "824: 36". Articulos_Cajas CH también 36
--   830       2    null →  24     +1.798.085   regla del dueño (colador 20 = 24); no se valuaba
--   877E      3    null →  12     +1.319.333   del listado de Thomas (CH x12); no se valuaba
--   828       2    null →  24     +1.060.346   Articulos_Cajas CH = 24 (Colador N°16)
--   26        1    36   →  12       -73.372    ACÁ estaba el error: Pinza de Fideos con el UxB
--                                              del Colador de LK
--
-- vista_plata_perdida y vista_facturable_anticipado: 0 de diferencia (mismo cambio aplicado,
-- ningún caso vivo). Los otros 7 duales no mueven nada: o no tienen líneas facturadas, o los
-- dos lados tienen la misma UxB (29 y 34 son 24 en las dos, 658 y 659 son 24 en las dos).
--
-- CENTINELA: select count(*) from public.gv_uxb_desalineado;  -- 0
-- BACKUPS: GV_Viewdefs_bkp_20260912c (las 3 vistas, definición previa), con RLS y sin escritura
--          para anon, como pide el protocolo.
-- ROLLBACK: docs/ROLLBACK-PRODUCCION.md, entrada v16.22.

-- ── 067 = 60 (curado: el sync no lo pisa) ──
insert into public."GV_UxB" (empresa, cod, uxb, descripcion, origen, curado, actualizado)
values ('LK','067',60,'Sacacorcho Tipo Mozo Suelto',
        'Thomas 12/09/2026: 067 = 60 (el catalogo de LK decia 50)', true, now())
on conflict (empresa,cod) do update set uxb=60, descripcion=excluded.descripcion,
  origen=excluded.origen, curado=true, actualizado=now();

-- ── el lado CH de los duales que faltaba, desde Articulos_Cajas marca CH ──
insert into public."GV_UxB" (empresa, cod, uxb, descripcion, origen, curado, actualizado)
select 'CH', d.cod, a."Uni_x_Caja"::numeric, d.ch,
       'dual 12/09/2026: lado CH desde Articulos_Cajas (el cod es otro producto en Chef)', true, now()
from public."GV_Cod_Dos_Productos" d
join public."Articulos_Cajas" a
  on public.gv_cod_stock(a."Cod_Art") = d.cod and upper(a."Marca") = 'CH' and a."Uni_x_Caja" > 0
where not exists (select 1 from public."GV_UxB" g where g.empresa='CH' and g.cod=d.cod)
on conflict (empresa,cod) do nothing;

-- ── el resolvedor por empresa ──
drop view if exists public.gv_uxb_emp;
create view public.gv_uxb_emp with (security_invoker = true) as
  select case when empresa = 'LK' then 'lk' else 'chef' end as empresa_precio,
         public.canon_cod(cod) as cod_canon,   -- neto_items y facturable_anticipado
         public.norm_cod(cod)  as cod_norm,    -- plata_perdida
         uxb::int as uxb
    from public."GV_UxB" where uxb is not null;
grant select on public.gv_uxb_emp to anon, authenticated, service_role, lk_ppp_reader;

-- ── las 3 vistas: create or replace (sin drops, tipos idénticos), agregando el join y el
--    escalón uxe en el COALESCE. Se hizo con un DO que reemplaza el texto sobre pg_get_viewdef;
--    la definición previa de cada una queda en GV_Viewdefs_bkp_20260912c ──
--   vista_facturacion_neto_items : COALESCE(ps, pcl, uxe, pc, pv, ux)    join por b.empresa_precio
--   vista_facturable_anticipado  : COALESCE(pcl, uxe, pc, pv, ux)        join por c.empresa_precio
--   vista_plata_perdida          : COALESCE(pcl, uxe, pc, pv, ux, 1)     join por e.empresa_precio (norm_cod)

-- ── realinear precios_venta, que traía el uxb viejo del catálogo de LK ──
with g as (select public.gv_cod_stock(cod) c,
                  coalesce(max(uxb) filter (where empresa='LK'), max(uxb)) u
           from public."GV_UxB" group by 1)
update public.precios_venta p set uxb = g.u::int
from g where g.c = public.gv_cod_stock(p.cod) and p.uxb::numeric is distinct from g.u;

-- ── verificación ──
-- select count(*) from public.gv_uxb_desalineado;   -- 0
-- select * from public."GV_Cod_Dos_Productos";      -- 12, los dos lados cargados
