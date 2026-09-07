-- =============================================================================
-- gv_ppp_en_salida.sql — EN SALIDA = FACTURADA Y SIN CONTROLAR (v13.62, 2026-09-07)
-- Proyecto Virgilio (hrxfctzncixxqmpfhskv) · vista NUESTRA (prefijo gv_), sólo lectura
-- =============================================================================
-- QUÉ CAMBIÓ Y POR QUÉ (dueño, 2026-09-06):
--   *"El 2 del 9 veo que hay 0,04 m³ de una nota de pedido que hasta que no esté
--     confirmado tiene que quedar en salida. Lo mismo los del 3 del 9: el 98502 y el
--     98569 tendrían que estar allá para que desde ahí se pueda manejar."*
--
--   La versión anterior (v13.02) exigía un evento **CCN** (carga al camión). Las tres
--   NP que nombró el dueño están facturadas y armadas pero **nunca tuvieron CCN**, así
--   que la vista no las podía ver y quedaban colgadas: fuera de Programación (fecha
--   vencida), fuera de En Salida y fuera de Entregados.
--
--     98665  Merajver Marcelo Fabián     D50E  0,042 m³  entrega 02/09  TAL, sin CCN
--     98502  Clapera Alicia Raquel       D55B  0,011 m³  entrega 03/09  TAL+AUB, sin CCN
--     98569  Distribuidora Pezzali S.A.  D55A  0,005 m³  entrega 03/09  TAL+FCO, sin CCN
--
--   REGLA NUEVA, elegida por el dueño: **entra toda NP facturada que no tenga CRN,
--   haya tenido CCN o no.** Se conserva además lo que tiene CCN aunque no esté
--   facturado (`base` = CCN ∪ facturadas), para que el cambio sea estrictamente
--   aditivo y nada de lo que hoy se ve pueda desaparecer.
--
-- EL FILTRO QUE NO PUEDE FALTAR: `gv_ppp_entregados_meta` (la hoja de entregados).
--   `Facturacion_NP` es el histórico completo y el CRN existe recién desde el
--   2026-09-05 (v12.95), así que sin ese filtro entraban **356 NP** — todo lo
--   facturado de siempre, entregado hace meses. Excluyendo lo que la hoja ya da por
--   entregado quedan **54**, que es el universo real de lo que no está cerrado.
--   Es el mismo criterio que ya usa el front en `_pppConfirmadas()` (CRN ∪ hoja).
--
-- MEDIDO al escribirla (2026-09-06), contra la vista v13.02:
--     total                     54   (antes 13)
--     perdidas respecto de v13.02   0   ← las 13 que se veían se siguen viendo
--     con CCN  ("cargada")      13
--     sin CCN  ("facturada_sin_cargar")  41
--     con CCR pero sin CCN       8   ← anomalía real, ver abajo
--     por fecha: 33 de septiembre, 20 de agosto, 1 del 29/07
--
-- ⚠ ANOMALÍA QUE DESTAPÓ (no la arregla esta vista, es de datos):
--   8 NP tienen **CCR** (control de remito antes de cargar) pero **no CCN** (carga al
--   camión): 98474, 98509, 98585, 98586, 98587, 98588, 98589, 98590. O el operario
--   saltea el CCN, o se está usando CCR en su lugar. Queda para revisar con el dueño.
--
-- COLUMNAS NUEVAS (van al final: `create or replace view` no deja reordenar):
--   armada          bool  · tiene TAL (terminó armado)
--   armado_at       tstz  · cuándo
--   cargada         bool  · tiene CCN
--   control_previo  bool  · tiene CCR
--   facturada_el    date  · fecha_salida de Facturacion_NP
--   estado          text  · 'cargada' | 'facturada_sin_cargar'
--   dias_sin_controlar int · días desde la carga (o desde la fecha de entrega si no hubo carga)
--
-- FSS ("facturado sin salida"): si hubo carga, saca la NP sólo si el FSS es POSTERIOR
--   a la última carga (se puede recargar y volver a entrar). Si nunca hubo carga, un
--   FSS la saca siempre — antes esa rama daba NULL y filtraba de más.
--
-- NO TOCA PRODUCCIÓN: sólo lee. Verificado el 2026-09-06 contra el repo
--   loekemeyer/produccion-virgilio (commit e15b682): **0 referencias** a
--   `gv_ppp_en_salida`. Sin trigger, sin escritura. `security_invoker = true`.
-- ROLLBACK: `git show HEAD~1:sql/gv_ppp_en_salida.sql` y correrlo.
-- =============================================================================

create or replace view public.gv_ppp_en_salida
with (security_invoker = true) as
with ccn as (
  select regexp_replace(upper(btrim(split_part(r.texto, '|', 1))), '\.0+$', '') as np,
         max(nullif(upper(btrim(split_part(r.texto, '|', 2))), '')) as tanda_ccn,
         min(r.ts_cliente) as cargado_at,
         max(r.ts_cliente) as ultima_carga_at,
         max((r.ts_cliente at time zone 'America/Argentina/Buenos_Aires')::date) as fecha_carga,
         count(*) as n_ccn
  from public."Registros_Produccion_Virgilio" r
  where r.opcion = 'CCN' and not public.es_legajo_test(r.legajo)
  group by 1
), tal as (
  select regexp_replace(upper(btrim(split_part(r.texto, '|', 1))), '\.0+$', '') as np,
         max(r.ts_cliente) as armado_at
  from public."Registros_Produccion_Virgilio" r
  where r.opcion = 'TAL' and not public.es_legajo_test(r.legajo)
  group by 1
), ccr as (
  select distinct regexp_replace(upper(btrim(split_part(r.texto, '|', 1))), '\.0+$', '') as np
  from public."Registros_Produccion_Virgilio" r where r.opcion = 'CCR'
), fss as (
  select regexp_replace(upper(btrim(split_part(r.texto, '|', 1))), '\.0+$', '') as np,
         max(r.ts_cliente) as fss_at
  from public."Registros_Produccion_Virgilio" r where r.opcion = 'FSS' group by 1
), crn as (
  select distinct regexp_replace(upper(btrim(split_part(r.texto, '|', 1))), '\.0+$', '') as np
  from public."Registros_Produccion_Virgilio" r where r.opcion = 'CRN'
), meta as (
  -- la hoja de entregados de ISIS: lo que ya está cerrado del lado del Excel
  select distinct regexp_replace(btrim(e.np), '\.0+$', '') as np from public.gv_ppp_entregados_meta e
), fact as (
  select regexp_replace(upper(btrim(f.np)), '\.0+$', '') as np, max(f.fecha_salida) as facturada_el
  from public."Facturacion_NP" f group by 1
), web as (
  select public.gv_ppp_web_np_label(p.empresa, p.np, p.np_idx) as np, p.empresa, p.tanda,
         p.cod_cliente as cod, p.razon_social as rs, p.m3, p.fecha_entrega::text as fecha_entrega,
         p.zona, p.barrio, p.direccion
  from public."PPP_Web_Programacion" p
), isis as (
  select x.np, x.tanda, x.cod, x.rs, x.m3, x.fecha_entrega, x.zona, x.barrio, x.direccion, x.prio
  from (
    select regexp_replace(btrim(g.np), '\.0+$', '') as np, g.tanda, g.cod, g.razon_social as rs, g.m3,
           left(g.fecha_entrega, 10) as fecha_entrega, g.zona, g.barrio, g.direccion, 1 as prio
      from public.gv_ppp_programacion_diaria g
    union all
    select regexp_replace(btrim(f.np), '\.0+$', ''), f.tanda, f.cod_cliente, f.razon_social, f.m3,
           f.fecha_salida::text, null, null, null, 2 from public."Facturacion_NP" f
    union all
    select regexp_replace(btrim(e.np), '\.0+$', ''), e.tanda, e.cod, e.rs, e.m3,
           left(e.fecha_entrega, 10), null, null, null, 3 from public.gv_ppp_entregados_meta e
  ) x
), base as (
  -- estrictamente aditivo: lo cargado al camión (como en v13.02) MÁS lo facturado
  select np from ccn union select np from fact
)
select
  b.np,
  coalesce(w.empresa, case when b.np ~ '^9' then 'lk' when b.np ~ '^4' then 'chef' end) as empresa,
  (w.np is not null)                          as es_web,
  coalesce(w.tanda, i.tanda, c.tanda_ccn)     as tanda,
  coalesce(w.cod, i.cod)                      as cod_cliente,
  coalesce(w.rs, i.rs)                        as razon_social,
  coalesce(w.m3, i.m3)                        as m3,
  coalesce(w.fecha_entrega, i.fecha_entrega)  as fecha_entrega,
  coalesce(w.zona, i.zona)                    as zona,
  coalesce(w.barrio, i.barrio)                as barrio,
  coalesce(w.direccion, i.direccion)          as direccion,
  c.fecha_carga,
  c.cargado_at,
  coalesce(c.n_ccn, 0)                        as n_ccn,
  (fa.np is not null)                         as facturada,
  -- ── columnas nuevas (v13.60) ────────────────────────────────────────────────
  (t.np is not null)                          as armada,
  t.armado_at,
  (c.np is not null)                          as cargada,
  (cr.np is not null)                         as control_previo,
  fa.facturada_el,
  case when c.np is not null then 'cargada' else 'facturada_sin_cargar' end as estado,
  greatest(0, current_date - coalesce(
      c.fecha_carga,
      nullif(left(coalesce(w.fecha_entrega, i.fecha_entrega), 10), '')::date))::int as dias_sin_controlar
from base b
  left join ccn  c  on c.np  = b.np
  left join tal  t  on t.np  = b.np
  left join ccr  cr on cr.np = b.np
  left join fact fa on fa.np = b.np
  left join crn  k  on k.np  = b.np
  left join fss  s  on s.np  = b.np
  left join meta mt on mt.np = b.np
  left join web  w  on w.np  = b.np
  left join lateral (
    select i1.np, i1.tanda, i1.cod, i1.rs, i1.m3, i1.fecha_entrega, i1.zona, i1.barrio, i1.direccion
      from isis i1 where i1.np = b.np order by i1.prio limit 1
  ) i on true
where k.np is null                    -- sin control de remito (CRN)
  and mt.np is null                   -- y que la hoja de entregados no lo dé por cerrado
  and (s.fss_at is null or (c.ultima_carga_at is not null and s.fss_at < c.ultima_carga_at))
  and (w.np is not null or i.np is not null);

-- ----------------------------------------------------------------------------
-- Controles (correr a mano después de tocarla)
-- ----------------------------------------------------------------------------
--   -- Nada de lo que se veía puede desaparecer (tiene que dar 0 contra la v13.02):
--   select count(*) from <vista_vieja> v where not exists (select 1 from gv_ppp_en_salida n where n.np = v.np);
--
--   -- Reparto por estado:
--   select estado, count(*), round(sum(m3),3) from public.gv_ppp_en_salida group by 1;
--
--   -- Las tres que motivaron el cambio tienen que estar:
--   select np, estado, armada, cargada, control_previo from public.gv_ppp_en_salida
--    where np in ('98665','98502','98569');
-- ----------------------------------------------------------------------------
