-- ══════════════════════════════════════════════════════════════════════════
-- v15.76 (2026-09-11) — LAS NP DE CHEF SE VALORIZAN CON LA LISTA DE CHEF
-- ══════════════════════════════════════════════════════════════════════════
-- Síntoma (reportado por Thomas): el modal "💵 Neto a facturar — desglose" de una NP de
-- Chef (caso testigo NP 44607, cliente 2393 Miguel Addoumie) mostraba TODO en rojo
-- "sin precio" y NETO $0,00, con los 15 códigos del pedido listados en "SIN PRECIO ·
-- NO ENTRAN" (043, 609, 700, 701, 713, 727E, 731, 760, 798E, 802, 824, 825, 836, 840, 911).
-- Los 15 tienen precio cargado en public.precios_venta_chef.
--
-- Causa: las tres vistas derivaban la empresa de la NP (^9 = lk, resto = chef) para el
-- dto_vol y para la cadena de súper, pero después joineaban UNA SOLA lista de precios,
-- public.precios_venta, que es la de LOEKEMEYER. public.precios_venta_chef (101 códigos,
-- misma estructura, la sincroniza el mismo cron) no la miraba nadie en Facturación.
--
-- Medido antes del fix (11/09):
--   · vista_facturacion_neto_items: 1.141 de 1.568 líneas de NP de Chef (72,8%) con
--     sin_precio = true, contra 37 de 9.020 (0,4%) en las de LK.
--   · Las 187 líneas de Chef que SÍ se valorizaban usaban la lista de LK, y en 61 el
--     precio difiere del de Chef → números mal en pantalla, sin ningún aviso. (uxb: 0
--     diferencias entre las dos listas, así que las cajas nunca se vieron afectadas.)
--
-- Fix (las tres vistas, misma regla):
--   1. NP de Chef → public.precios_venta_chef por el código canónico.
--   2. Artículo con "L" al final (505L, 438EL) = artículo de LOEKEMEYER vendido por Chef
--      (regla del dueño v13.71, ya implementada en gv_ppp_np_valor): se valúa con la lista
--      de LK pelando la L. Hoy son 3 líneas (438EL, 439EL), todas sin precio hasta ahora.
--   3. Fallback: NP de Chef con un código que NO está en la lista de Chef → lista de LK.
--      Cubre el caso inverso ya documentado (Cencosud/Chef 2444: NP de Chef con artículos
--      de Loeke SIN la L) y, sobre todo, garantiza que NINGUNA línea que hoy tiene precio
--      lo pierda con este cambio. Son 126 líneas.
--   4. Las NP de LK no cambian: siguen leyendo sólo precios_venta (no hay fallback a Chef).
--   5. La lista de súper (cobranzas_precios_super) sigue teniendo prioridad sobre las dos.
--
-- Objetos tocados (los tres son vistas, sólo lectura, sin columnas nuevas → create or
-- replace; no se dropea nada y no hay dependientes que rehacer):
--   · public.vista_facturacion_neto_items   (sql/facturacion_neto.sql)
--   · public.vista_facturable_anticipado    (sql/facturable_anticipado.sql)
--   · public.vista_plata_perdida            (vivía sólo en la base; queda acá)
--
-- ROLLBACK: volver a correr las definiciones previas, que están en
--   sql/backups/vistas_precio_lk_20260911_pre_v1576.sql
-- ══════════════════════════════════════════════════════════════════════════


-- ─────────────────────────────────────────────────────────────────────────
-- 1) vista_facturacion_neto_items — el neto a facturar (la del reporte)
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW public.vista_facturacion_neto_items AS
WITH ent AS (
  SELECT regexp_replace(e.np, '\.0+$', '')            AS np,
         public.canon_cod(e.cod_art)                  AS cod_canon,
         min(e.cod_art)                               AS cod_orig,
         regexp_replace(e.cod_cliente, '\D', '', 'g') AS cc,
         SUM(COALESCE(e.cajas_entregadas,0))          AS cajas_ent,
         SUM(COALESCE(e.cajas_pedidas,0))             AS cajas_ped,
         SUM(COALESCE(e.cajas_falto,0))               AS cajas_falto
  FROM public."Entregas_Virgilio" e
  WHERE COALESCE(e.cajas_pedidas,0) > 0 OR COALESCE(e.cajas_entregadas,0) > 0 OR COALESCE(e.cajas_falto,0) > 0
  GROUP BY regexp_replace(e.np, '\.0+$', ''),
           public.canon_cod(e.cod_art),
           regexp_replace(e.cod_cliente, '\D', '', 'g')
),
base AS (
  SELECT ent.*,
    (CASE WHEN ent.np ~ '^9' THEN 'lk' ELSE 'chef' END) AS empresa,
    -- v15.76 — "L" al final = artículo de Loeke vendido por Chef (505L, 438EL): la lista
    -- que manda es la de LK y el código se busca pelado. Regla del dueño v13.71.
    (upper(btrim(ent.cod_orig)) ~ '[0-9E]L$') AS es_art_lk,
    -- cadena de súper del cliente (cobranzas usa 'lk'/'ch'); sólo cadenas con lista especial
    (SELECT cc2.super_key
       FROM public.cobranzas_cliente_cadena cc2
       JOIN public.cobranzas_super_cadena sc ON sc.super_key = cc2.super_key AND NOT sc.usa_lista_general
      WHERE cc2.empresa = (CASE WHEN ent.np ~ '^9' THEN 'lk' ELSE 'ch' END)
        AND cc2.cod_cliente = ent.cc
      LIMIT 1) AS super_key
  FROM ent
),
base2 AS (
  SELECT b.*,
    (CASE WHEN b.es_art_lk THEN 'lk' ELSE b.empresa END) AS empresa_precio,
    (CASE WHEN b.es_art_lk
          THEN public.canon_cod(regexp_replace(upper(btrim(b.cod_orig)), 'L$', ''))
          ELSE b.cod_canon END) AS cod_precio
  FROM base b
),
val AS (
  -- Prioridad de precio: lista de súper → lista de la empresa de la NP → lista de LK.
  SELECT b.*,
         COALESCE(ps.uxb, pc.uxb, pv.uxb)                 AS uxb_r,
         COALESCE(ps.precio_unit, pc.precio_unit, pv.precio_unit) AS precio_r,
         COALESCE(pc.cod, pv.cod)                         AS cod_lista,
         (CASE WHEN b.super_key IS NOT NULL THEN 0 ELSE COALESCE(cd.dto_vol, 0) END) AS dto_r
  FROM base2 b
  LEFT JOIN public.clientes_dto cd
         ON cd.cod_cliente = b.cc AND cd.empresa = b.empresa
  LEFT JOIN public.precios_venta_chef pc
         ON b.empresa_precio = 'chef' AND public.canon_cod(pc.cod) = b.cod_precio
  LEFT JOIN public.precios_venta pv
         ON public.canon_cod(pv.cod) = b.cod_precio
  LEFT JOIN public.cobranzas_precios_super ps
         ON b.super_key IS NOT NULL AND ps.super_key = b.super_key
        AND ps.nc = public.cob_norm_cod(b.cod_orig)
)
SELECT v.np,
       v.cc AS cod_cliente,
       -- el código que se muestra: el de la lista que lo valorizó, salvo en el caso "L",
       -- donde el código real del pedido es el que lleva la L (505L, no 505).
       CASE WHEN v.es_art_lk THEN v.cod_orig ELSE COALESCE(v.cod_lista, v.cod_orig) END AS cod,
       v.cajas_ped, v.cajas_ent, v.cajas_falto,
       v.uxb_r AS uxb,
       v.precio_r AS precio_lista,
       v.dto_r AS dto_vol,
       CASE WHEN v.precio_r IS NOT NULL AND v.precio_r > 0
            THEN ROUND(v.cajas_ent * COALESCE(v.uxb_r, 1) * v.precio_r * (1 - v.dto_r), 2) END AS importe_ent,
       CASE WHEN v.precio_r IS NOT NULL AND v.precio_r > 0
            THEN ROUND(v.cajas_ped * COALESCE(v.uxb_r, 1) * v.precio_r * (1 - v.dto_r), 2) END AS importe_ped,
       (v.precio_r IS NULL OR v.precio_r <= 0) AS sin_precio,
       v.cod_canon,
       -- 2% web: NO aplica al súper (factor 1); sí al resto (factor 0,98). Por línea.
       CASE WHEN v.super_key IS NOT NULL THEN 1.0 ELSE 0.98 END AS factor_web,
       (v.super_key IS NOT NULL) AS es_super
FROM val v;

REVOKE ALL ON public.vista_facturacion_neto_items FROM anon, authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- 2) vista_facturable_anticipado — "qué puedo facturar hoy con el stock que hay"
--    Misma corrección; el resto de la vista queda igual que la v12.31.
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW public.vista_facturable_anticipado AS
with pend as (
  select pp.np, pp.tanda, pp.razon_social as rs_virgilio, pp.cod as cod_cliente,
         nullif(pp.fecha_entrega, '') as fecha_entrega,
         case when pp.np ~ '^9' then 'lk' else 'chef' end as empresa
  from public."PPP_Programacion_Diaria" pp
  where pp.np not in (select np from public."Facturacion_NP")
    and pp.np not in (select np from public."NP_Canceladas")
),
items as (
  select p.np, p.tanda, p.rs_virgilio, p.cod_cliente, p.fecha_entrega, p.empresa,
         b.articulo, sum(coalesce(b.cajas, 0)) as cajas_pedidas
  from pend p
  join public."PPP_Base_Pedidos" b on b.pedido = p.np
  where b.articulo is not null and coalesce(b.cajas, 0) > 0
  group by p.np, p.tanda, p.rs_virgilio, p.cod_cliente, p.fecha_entrega, p.empresa, b.articulo
),
reservas_articulo as (
  select articulo, sum(cajas) as reservado_total
  from public.facturable_anticipado_reservas
  where liberado_at is null
  group by articulo
),
reservas_propias as (
  select np, articulo, sum(cajas) as reservado_propio
  from public.facturable_anticipado_reservas
  where liberado_at is null
  group by np, articulo
),
items2 as (
  select i.*,
    coalesce(rp.reservado_propio, 0) as reservado_propio,
    greatest(0, i.cajas_pedidas - coalesce(rp.reservado_propio, 0)) as cajas_pedidas_pendiente
  from items i
  left join reservas_propias rp on rp.np = i.np and rp.articulo = i.articulo
),
con_stock as (
  select i.*, s.terminado,
    greatest(0, s.terminado - coalesce(ra.reservado_total, 0)) as terminado_disponible,
    sum(i.cajas_pedidas_pendiente) over (
      partition by i.articulo
      order by (i.fecha_entrega is null), i.fecha_entrega asc, i.np asc
      rows between unbounded preceding and 1 preceding
    ) as demanda_previa
  from items2 i
  join public.vista_saldos_stock s on public.canon_cod(s.cod_art) = public.canon_cod(i.articulo)
  left join reservas_articulo ra on ra.articulo = i.articulo
  where coalesce(s.terminado, 0) > 0
),
calc as (
  select *,
    greatest(0, least(cajas_pedidas_pendiente, terminado_disponible - coalesce(demanda_previa, 0))) as cajas_cubribles
  from con_stock
),
calc2 as (
  -- v15.76 — de qué lista sale el precio (ver cabecera del archivo).
  select c.*,
    (case when upper(btrim(c.articulo)) ~ '[0-9E]L$' then 'lk' else c.empresa end) as empresa_precio,
    (case when upper(btrim(c.articulo)) ~ '[0-9E]L$'
          then public.canon_cod(regexp_replace(upper(btrim(c.articulo)), 'L$', ''))
          else public.canon_cod(c.articulo) end) as cod_precio
  from calc c
),
precio as (
  select c.*,
         coalesce(pc.uxb, pv.uxb) as uxb,
         coalesce(pc.precio_unit, pv.precio_unit) as precio_unit,
         coalesce(cd.dto_vol, 0) as dto_vol,
         round(c.cajas_cubribles * coalesce(pc.uxb, pv.uxb, 1)
               * coalesce(pc.precio_unit, pv.precio_unit, 0)
               * (1 - coalesce(cd.dto_vol, 0)) * 0.98, 2) as valor_estimado,
         (coalesce(pc.precio_unit, pv.precio_unit) is null
          or coalesce(pc.precio_unit, pv.precio_unit) <= 0) as sin_precio
  from calc2 c
  left join public.precios_venta_chef pc
         on c.empresa_precio = 'chef' and public.canon_cod(pc.cod) = c.cod_precio
  left join public.precios_venta pv
         on public.canon_cod(pv.cod) = c.cod_precio
  -- dto_vol por (cliente, empresa): LK/Chef tienen numeraciones independientes,
  -- la empresa ya viaja en c.empresa (derivada de la NP: ^9 = lk, resto = chef).
  left join public.clientes_dto cd on cd.cod_cliente = c.cod_cliente and cd.empresa = c.empresa
)
select
  np, tanda, rs_virgilio, cod_cliente, empresa, fecha_entrega,
  articulo, cajas_pedidas, reservado_propio, terminado, demanda_previa, cajas_cubribles,
  ((cajas_cubribles + reservado_propio) >= cajas_pedidas) as cubre_completo,
  uxb, precio_unit, dto_vol, valor_estimado, sin_precio,
  exists (
    select 1 from public.cobranzas_cliente_cadena cc
    where cc.cod_cliente = precio.cod_cliente and cc.empresa = precio.empresa
  ) as es_super
from precio
where cajas_cubribles > 0;

revoke all on public.vista_facturable_anticipado from anon, authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- 3) vista_plata_perdida — 💸 lo que no se facturó por quiebre de stock
--    (vivía sólo en la base; queda versionada acá). precio 8888 = placeholder de LK
--    sin precio real → no se valoriza, igual que antes.
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW public.vista_plata_perdida AS
with ev as (
  select e.*,
    (case when regexp_replace(e.np, '\.0+$', '') ~ '^9' then 'lk' else 'chef' end) as empresa,
    (upper(btrim(e.cod_art)) ~ '[0-9E]L$') as es_art_lk
  from public."Entregas_Virgilio" e
  where coalesce(e.cajas_falto, 0) > 0
),
ev2 as (
  select ev.*,
    (case when ev.es_art_lk then 'lk' else ev.empresa end) as empresa_precio,
    (case when ev.es_art_lk
          then public.norm_cod(regexp_replace(upper(btrim(ev.cod_art)), 'L$', ''))
          else public.norm_cod(ev.cod_art) end) as nc_precio
  from ev
)
select e.np,
  public.norm_cod(e.cod_art)      as cod,
  btrim(e.cod_art)                as cod_raw,
  e.cajas_falto                   as cajas,
  e.cajas_pedidas                 as ped,
  e.cajas_entregadas              as ent,
  left(e.fecha_salida, 10)        as fecha,
  btrim(e.cod_cliente)            as cod_cliente,
  coalesce(pc.precio_unit, pv.precio_unit, 0)  as precio_unit,
  coalesce(pc.uxb, pv.uxb, 1)                  as uxb,
  coalesce(pc.descripcion, pv.descripcion, '') as descripcion,
  (coalesce(pc.precio_unit, pv.precio_unit, 0) > 0
   and coalesce(pc.precio_unit, pv.precio_unit, 0) <> 8888) as precio_ok,
  case when coalesce(pc.precio_unit, pv.precio_unit, 0) > 0
        and coalesce(pc.precio_unit, pv.precio_unit, 0) <> 8888
       then coalesce(e.cajas_falto, 0) * coalesce(pc.uxb, pv.uxb, 1) * coalesce(pc.precio_unit, pv.precio_unit, 0)
       else 0 end as plata,
  coalesce(btrim(cv.vend), '')    as vendedor,
  coalesce(fnp.razon_social, '')  as razon_social
from ev2 e
left join public.precios_venta_chef pc
       on e.empresa_precio = 'chef' and public.norm_cod(pc.cod) = e.nc_precio
left join public.precios_venta pv
       on public.norm_cod(pv.cod) = e.nc_precio
left join public.clientes_vendedor cv on btrim(cv.cod_cliente) = btrim(e.cod_cliente)
left join public."Facturacion_NP" fnp on btrim(fnp.np) = btrim(e.np);

grant select on public.vista_plata_perdida to anon, authenticated;


-- ══════════════════════════════════════════════════════════════════════════
-- VERIFICACIÓN (correr después de aplicar)
-- ══════════════════════════════════════════════════════════════════════════
-- a) el caso testigo: la NP 44607 tiene que dar 15 líneas con precio y neto > 0
-- select cod, cajas_ent, uxb, precio_lista, sin_precio from public.vista_facturacion_neto_items
--  where np = '44607' order by cod_canon;
-- select * from public.facturacion_neto_lote(array['44607']);
--
-- b) líneas sin precio por empresa (antes: chef 1.141/1.568 = 72,8%)
-- select case when np ~ '^9' then 'lk' else 'chef' end emp, count(*) lineas,
--        count(*) filter (where sin_precio) sin_precio
--   from public.vista_facturacion_neto_items group by 1;
--
-- c) que NINGUNA línea de LK se haya movido (el fix no las toca)
--    comparar contra el backup: mismo importe_ent para np ~ '^9'.
