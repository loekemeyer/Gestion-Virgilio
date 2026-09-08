-- =============================================================================
-- gv_articulo_empresa.sql — FUENTE DE VERDAD de la empresa de cada artículo
-- Proyecto Virgilio (hrxfctzncixxqmpfhskv) · vista NUEVA gv_, sólo lectura
-- v14.46 (2026-09-08) · Fase 1 del modelo "identidad de empresa como columna"
-- =============================================================================
-- Para qué: la empresa es una propiedad del ARTÍCULO (a qué catálogo/góndola pertenece),
-- 1:1 para todos los códigos menos los 4 duales. Esta vista es la fuente única que después
-- consumen el stock, la valuación y (a futuro) las compras, para no re-derivar la empresa
-- de los dígitos de la NP ni codificarla en el string del código.
--
--   · LK   = artículo de Loekemeyer. Catálogo LK = precios_venta ∪ cob_uxb_lk. Incluye los
--            ~96 códigos que Chef REVENDE (mismo producto → se pickean de la góndola Loeke
--            con "L", regla v13.71). Por eso "está en los dos catálogos" NO es dual.
--   · CH   = artículo PROPIO de Chef (sólo en el catálogo de Chef, y no dual).
--   · dual = MISMO código, PRODUCTO DISTINTO en cada empresa (437E/438E/439E/809E, tabla
--            public.codigos_duales) → 2 filas (LK y CH); la empresa la decide la NP.
--
-- Medido (08/09, con los mirrors ya RECONCILIADOS, v14.47): 282 LK no-dual + 98 propios de
-- Chef + 4 duales (cada uno LK y CH) = 388 filas.
--   ⚠ OJO: depende de que precios_venta / precios_venta_chef sean el catálogo EXACTO. Antes de
--   v14.47 precios_venta arrastraba 115 filas viejas de Chef (del merge "Chef gana" previo al
--   split v14.44) que NUNCA se borraban → esta vista las tomaba como LK y daba "0 propios de
--   Chef" (mal). El sync ahora reconcilia (borra lo que no está en el catálogo de origen).
--
-- Se re-deriva sola: los catálogos los refresca sync-precios-venta cada 15 min (cron 66).
-- NO toca Producción (objeto nuevo gv_). Rollback: drop view public.gv_articulo_empresa;
-- =============================================================================
create or replace view public.gv_articulo_empresa
with (security_invoker = true) as
with lk as (
  select distinct canon_cod(cod) cc from public.precios_venta where canon_cod(cod) <> ''
  union
  select distinct canon_cod(cod) cc from public.cob_uxb_lk where canon_cod(cod) <> ''
),
ch as (
  select distinct canon_cod(cod) cc from public.precios_venta_chef where canon_cod(cod) <> ''
),
dual as (
  select distinct canon_cod(cod) cc from public.codigos_duales where canon_cod(cod) <> ''
),
todos as (
  select cc from lk union select cc from ch union select cc from dual
),
base as (
  select t.cc,
         (d.cc is not null) as es_dual,
         exists (select 1 from lk where lk.cc = t.cc) as in_lk,
         exists (select 1 from ch where ch.cc = t.cc) as in_ch
  from todos t
  left join dual d on d.cc = t.cc
)
select cc as cod_canon, 'LK'::text as empresa, es_dual from base where es_dual or in_lk
union all
select cc as cod_canon, 'CH'::text as empresa, es_dual from base where es_dual or (in_ch and not in_lk);
revoke all on public.gv_articulo_empresa from anon, authenticated;
grant select on public.gv_articulo_empresa to anon, authenticated;

-- Chequeos:
--   select empresa, es_dual, count(*) from public.gv_articulo_empresa group by 1,2;
--   select * from public.gv_articulo_empresa where cod_canon in ('809E','505');  -- 809E dual, 505 LK
