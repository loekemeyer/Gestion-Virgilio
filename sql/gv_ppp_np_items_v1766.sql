-- v17.66 (Luis, 2026-09-14) — EL CONTENIDO DE CUALQUIER NP, DE ISIS O WEB
--
-- La v17.61 creó `gv_ppp_isis_items` para el detalle de las NP de ISIS. Al hacer la tabla de
-- Programación (día → tanda → NP → contenido) hizo falta lo mismo para una NP **web**, y los
-- renglones de esas no están en `GV_PPP_Base_Pedidos`: están en `PPP_Web_Base`, que es lo que
-- escribe `gv_ppp_web_tanda_programar` al programar la tanda. Las dos tablas tienen la misma
-- forma (pedido/np_label, articulo, cajas), así que en vez de dos endpoints va uno solo.
--
--   `gv_ppp_np_items`  = ISIS (gv_ppp_base_pedidos) ∪ web (PPP_Web_Base), agrupado por código,
--                        con las cajas y —resolviendo el uxb del artículo— las unidades.
--
-- `gv_ppp_isis_items` queda como VISTA DE COMPATIBILIDAD (el mismo select, filtrado a origen
-- 'isis'): una pestaña que quedó abierta en la v17.61 la sigue llamando. Se puede dropear cuando
-- ya no queden clientes en esa versión.
--
-- ⚠ `gv_uxb_resuelto.empresa` es 'LK' / 'CH' en MAYÚSCULA, no 'lk' / 'chef'. Joinear en minúscula
-- deja todas las unidades en NULL (pasó al escribir la v17.61).
--
-- Objetos con prefijo gv_ y `security_invoker = true` (protocolo del CLAUDE.md).

create or replace view public.gv_ppp_np_items
with (security_invoker = true) as
with crudo as (
  -- NP de ISIS: la base del PPP (la vista, para respetar el corte del espejo y las ocultas)
  select regexp_replace(btrim(bp.pedido), '\.0+$', '') as np,
         btrim(bp.articulo)                            as art,
         coalesce(bp.cajas, 0)::numeric                as cajas,
         'isis'::text                                  as origen
    from public.gv_ppp_base_pedidos bp
   where btrim(coalesce(bp.articulo, '')) <> ''
  union all
  -- NP web: lo que escribió gv_ppp_web_tanda_programar al programar la tanda
  select btrim(wb.np_label),
         btrim(wb.articulo),
         coalesce(wb.cajas, 0)::numeric,
         'web'
    from public."PPP_Web_Base" wb
   where btrim(coalesce(wb.np_label, '')) <> '' and btrim(coalesce(wb.articulo, '')) <> ''
),
agr as (
  select np, art, origen, sum(cajas) as cajas, count(*)::int as renglones
    from crudo where np <> '' group by 1, 2, 3
)
select a.np,
       case when upper(a.np) like 'LK%' then 'lk'
            when upper(a.np) like 'CH%' then 'chef'
            when coalesce(nullif(regexp_replace(a.np, '\D', '', 'g'), '')::numeric, 0) > 90000 then 'lk'
            else 'chef' end as empresa,
       a.origen,
       a.art,
       a.cajas,
       a.renglones,
       u.uxb,
       case when u.uxb is null then null else (a.cajas * u.uxb)::numeric end as uni
  from agr a
  left join public.gv_uxb_resuelto u
    on u.empresa = case when upper(a.np) like 'LK%' then 'LK'
                        when upper(a.np) like 'CH%' then 'CH'
                        when coalesce(nullif(regexp_replace(a.np, '\D', '', 'g'), '')::numeric, 0) > 90000 then 'LK'
                        else 'CH' end
   and btrim(u.cod) = a.art;

grant select on public.gv_ppp_np_items to anon, authenticated;

comment on view public.gv_ppp_np_items is
  'v17.66 (Luis) — el contenido de CUALQUIER NP (de ISIS o web) por codigo: cajas y, si se resuelve el uxb, unidades. ISIS sale de gv_ppp_base_pedidos y web de PPP_Web_Base (lo que escribio gv_ppp_web_tanda_programar). Reemplaza a gv_ppp_isis_items, que queda como vista de compatibilidad para las pestanas ya abiertas en v17.61.';

-- compatibilidad con la v17.61 (se puede dropear cuando nadie quede en esa versión)
create or replace view public.gv_ppp_isis_items
with (security_invoker = true) as
select np,
       case when empresa = 'chef' then 'chef' else 'lk' end as empresa,
       art, cajas, renglones, uxb, uni
  from public.gv_ppp_np_items
 where origen = 'isis';

grant select on public.gv_ppp_isis_items to anon, authenticated;

-- ── MEDICIÓN (14/09) ───────────────────────────────────────────────────────────────────────
-- Cobertura contra lo que hay programado de hoy en adelante:
--
--   with t as (select np, origen from public.gv_ppp_prog_arbol(current_date, current_date + 60)),
--        c as (select t.np, t.origen,
--                     (select count(*) from public.gv_ppp_np_items i where i.np = t.np) rg from t)
--   select origen, count(*) nps, count(*) filter (where rg > 0) con_detalle,
--          count(*) filter (where rg = 0) sin_detalle from c group by 1;
--
-- → isis: 66 NP, 65 con detalle, 1 sin · web: 80 NP, 80 con detalle, 0 sin.
-- Lectura como `anon` comprobada (`set local role anon`): LK 0007 devuelve sus 18 códigos con uxb.

-- ── ROLLBACK ───────────────────────────────────────────────────────────────────────────────
-- Volver a la v17.61: recrear `gv_ppp_isis_items` con el CREATE de sql/gv_ppp_isis_items_v1761.sql
-- y después `drop view if exists public.gv_ppp_np_items;` (en ese orden: hoy la de compatibilidad
-- cuelga de la nueva).
