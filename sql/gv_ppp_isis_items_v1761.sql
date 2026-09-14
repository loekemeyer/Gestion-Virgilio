-- v17.61 (Luis, 2026-09-14) — EL CONTENIDO DE UNA NP DE ISIS
--
-- La v17.57 puso el detalle del pedido (códigos / cajas / unidades) en la ficha de A Programar,
-- y para las NP que vienen de ISIS escribió "el detalle de artículos no está en la página, se ve
-- en ISIS". Eso es falso y Luis lo cazó: *"esa NP tenía el detalle de los códigos y las cajas, en
-- algún lugar está; si no, cuando llega a facturación ¿cómo se factura?"*.
--
-- Está en `GV_PPP_Base_Pedidos` — la base del PPP, la misma que alimenta el picking y, río abajo,
-- la facturación. De hecho `gv_ppp_isis_sin_tanda` ya cuenta ahí las `lineas` y las `cajas` que la
-- propia ficha venía mostrando en el resumen: los renglones estaban a un JOIN de distancia.
--
-- Esta vista los devuelve agrupados por código, con las cajas y —resolviendo el uxb del artículo
-- contra `gv_uxb_resuelto`— las unidades, para que la tabla se lea igual que la de un pedido web.
--
-- Convenciones que copia de `gv_ppp_isis_sin_tanda` (para que los números den lo mismo):
--   · la NP se normaliza con `regexp_replace(btrim(pedido), '\.0+$', '')` (la base trae "98587.0")
--   · empresa = 'chef' si la NP empieza con 4, si no 'lk'
-- Y lee `gv_ppp_base_pedidos` (la vista, no la tabla): así respeta el corte del espejo de ISIS y
-- las filas ocultas por `GV_PPP_Prog_Override.oculto`, igual que el resto de Gestión.
--
-- ⚠ `gv_uxb_resuelto.empresa` es 'LK' / 'CH' en MAYÚSCULA, no 'lk' / 'chef'. Joinear con
-- minúscula devuelve uxb NULL para todo (pasó al escribir esto).
--
-- Objeto NUEVO con prefijo gv_ y `security_invoker = true` (protocolo del CLAUDE.md): sin eso
-- correría como `postgres` y saltearía la RLS de la tabla madre.

create or replace view public.gv_ppp_isis_items
with (security_invoker = true) as
with b as (
  select regexp_replace(btrim(bp.pedido), '\.0+$', '') as np,
         btrim(bp.articulo)                            as art,
         sum(coalesce(bp.cajas, 0))::numeric           as cajas,
         count(*)::int                                 as renglones
    from public.gv_ppp_base_pedidos bp
   where btrim(coalesce(bp.articulo, '')) <> ''
   group by 1, 2
)
select b.np,
       case when left(b.np, 1) = '4' then 'chef' else 'lk' end as empresa,
       b.art,
       b.cajas,
       b.renglones,
       u.uxb,
       case when u.uxb is null then null else (b.cajas * u.uxb)::numeric end as uni
  from b
  left join public.gv_uxb_resuelto u
    on u.empresa = case when left(b.np, 1) = '4' then 'CH' else 'LK' end
   and btrim(u.cod) = b.art;

grant select on public.gv_ppp_isis_items to anon, authenticated;

comment on view public.gv_ppp_isis_items is
  'v17.61 (Luis) — renglones de una NP de ISIS para la ficha de A Programar: codigo, cajas y (si se puede resolver) unidades. Sale de gv_ppp_base_pedidos, la MISMA base que alimenta el picking y la facturacion. La NP se normaliza igual que en gv_ppp_isis_sin_tanda (saca el .0 final); empresa = chef si la NP empieza con 4, si no lk.';

-- ── MEDICIÓN (lo que se corrió el 14/09, no "no debería afectar") ───────────────────────────
-- Los totales de la vista nueva tienen que dar IGUAL que los que ya mostraba la ficha:
--
--   select s.np, s.lineas, s.cajas, i.lineas_v, i.cajas_v, i.sin_uxb,
--          (s.lineas = i.lineas_v and s.cajas = i.cajas_v) as coincide
--     from public.gv_ppp_isis_sin_tanda s
--     left join lateral (
--       select count(*)::int lineas_v, coalesce(sum(cajas),0) cajas_v,
--              count(*) filter (where uxb is null)::int sin_uxb
--         from public.gv_ppp_isis_items x where x.np = s.np
--     ) i on true
--    order by s.np;
--
-- Resultado: 5 NP (98587, 98588, 98589, 98590, 98617), las 5 `coincide = true`, 0 códigos sin uxb.
-- Ej. 98587 (Zhang Qikuan): 18 renglones, 21 cajas — los mismos que la ficha ya decía.
-- Lectura como `anon` comprobada (`set local role anon`): devuelve las 18 filas.
-- Costo: la base tiene ~9.800 filas; filtrada por np, 6 ms.

-- ── ROLLBACK ───────────────────────────────────────────────────────────────────────────────
-- drop view if exists public.gv_ppp_isis_items;
-- (la vista es NUEVA y no la lee nadie más que la ficha de A Programar; sin ella la ficha vuelve
--  a decir que no tiene el detalle, nada más.)
