-- =============================================================================
-- gv_ppp_en_salida — EN SALIDA = SÓLO LO CARGADO AL CAMIÓN, Y CON FECHA (v15.85, 2026-09-11)
-- Proyecto Virgilio (hrxfctzncixxqmpfhskv) · vista NUESTRA (prefijo gv_), sólo lectura
-- =============================================================================
-- QUÉ PIDIÓ EL DUEÑO (Thomas, 2026-09-11, mirando la solapa En Salida):
--   *"Todos los pedidos que están acá tienen que volver a A Programar o a Programación.
--     Acá en En Salida no puede haber ningún pedido sin fecha, ni pedidos que no se hayan
--     cargado a un camión."*
--
--   O sea: En Salida = lo que SALIÓ de verdad (evento CCN = Carga Camión) y con su fecha
--   de carga. Todo lo demás vuelve a la Programación, que es donde se puede reprogramar,
--   desprogramar o cancelar.
--
-- QUÉ REGLAS ANTERIORES DESACTIVA (las dos las había pedido el mismo dueño; ésta es
-- posterior y explícita, así que manda):
--   · v13.62 (06/09) — "entra toda NP facturada que no tenga CRN, haya tenido CCN o no"
--     → `estado = 'facturada_sin_cargar'`.
--   · v15.55 (11/09, a la mañana) — salida presunta: la NP armada hace más de
--     `salida_presunta_horas` (36) sin CCN ni factura → `estado = 'armada_sin_carga'`.
--   Ninguna de las dos borra nada: los pedidos vuelven a verse en Programación, porque el
--   front esconde de Programación exactamente lo que está en esta vista (`_fuera()` de
--   `pppRenderProg`). Los vencidos caen en la lista de vencidos, con sus botones
--   "↩ A Programar" / "📅 Reprogramar" / "🚫 Cancelar" (v15.55 B).
--
-- CÓMO SE APAGA / SE VUELVE ATRÁS (sin DDL, un UPDATE):
--   update public."PPP_Web_Config" set valor = 0 where clave = 'en_salida_solo_cargadas';
--   → vuelve exactamente al comportamiento v15.63 (facturadas + salida presunta).
--
-- MEDIDO al aplicarla (2026-09-11):
--   antes: 41 NP  (19 'cargada' · 22 'facturada_sin_cargar' · 0 'armada_sin_carga')
--   después: 19 NP, todas con fecha_carga.
--   Las 22 que salen están TODAS en gv_ppp_programacion_diaria (verificado NP por NP),
--   así que ninguna queda colgada: reaparecen en Programación.
--     98480 98481 98530 (entrega 10/09, vencidas → lista de vencidos)
--     98585..98590 (D56D, sin fecha de entrega → vencidos, hay que reprogramarlas)
--     44605 98624 98625 98657..98660 (11/09) · 98637 98652..98654 98661 98662 (14/09)
--
-- NO TOCA PRODUCCIÓN: sólo lee, `security_invoker = true`, sin trigger ni escritura.
-- BACKUP de la definición previa: sql/backups/gv_ppp_en_salida_20260911_pre_v1585.sql
-- =============================================================================

insert into public."PPP_Web_Config" (clave, valor, descripcion, actualizado)
values ('en_salida_solo_cargadas', 1,
        'En Salida muestra SÓLO las NP con Carga Camión (CCN) y fecha de carga. 0 = vuelve a incluir facturadas sin cargar y salidas presuntas (v13.62/v15.55).',
        now())
on conflict (clave) do nothing;

create or replace view public.gv_ppp_en_salida
with (security_invoker = true) as
with cfg as (
  select coalesce((select c.valor from public."PPP_Web_Config" c where c.clave = 'salida_presunta_horas'), 36) as horas,
         coalesce((select c.valor from public."PPP_Web_Config" c where c.clave = 'en_salida_solo_cargadas'), 1) as solo_cargadas
), ccn as (
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
  select np from ccn
  union
  select np from fact
  union
  select t.np from tal t cross join cfg where t.armado_at < now() - make_interval(hours => cfg.horas::int)
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
  (t.np is not null)                          as armada,
  t.armado_at,
  (c.np is not null)                          as cargada,
  (cr.np is not null)                         as control_previo,
  fa.facturada_el,
  case when c.np is not null then 'cargada'
       when fa.np is not null then 'facturada_sin_cargar'
       else 'armada_sin_carga' end            as estado,
  greatest(0, current_date - coalesce(
      c.fecha_carga,
      nullif(left(coalesce(w.fecha_entrega, i.fecha_entrega), 10), '')::date))::int as dias_sin_controlar,
  round(extract(epoch from now() - t.armado_at) / 3600)  as horas_desde_armado,
  (c.np is null and fa.np is null)            as salida_presunta
from base b
  cross join cfg
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
  and (w.np is not null or i.np is not null)
  -- v15.85 (dueño): En Salida = SÓLO lo cargado al camión (CCN) y con fecha de carga.
  -- Con la llave en 0 vuelve la regla vieja (facturadas sin cargar + salida presunta).
  and (cfg.solo_cargadas = 0 or (c.np is not null and c.fecha_carga is not null))
  and (c.np is not null or fa.np is not null
       or nullif(left(coalesce(w.fecha_entrega, i.fecha_entrega), 10), '')::date < current_date)
  and not exists (select 1 from public."NP_Canceladas" nc
                   where regexp_replace(btrim(nc.np), '\.0+$', '') = b.np)
  and not exists (select 1 from public."GV_Web_Cancelados" wc
                   where upper(btrim(wc.np_label)) = upper(b.np));

-- ----------------------------------------------------------------------------
-- Controles (correr a mano después de tocarla)
-- ----------------------------------------------------------------------------
--   select estado, count(*), count(*) filter (where fecha_carga is null) sin_fecha
--     from public.gv_ppp_en_salida group by 1;            -- esperado: sólo 'cargada', sin_fecha = 0
--
--   -- Nada de lo que sale queda colgado: tiene que estar en la Programación.
--   select b.np from (…las que salieron…) b
--    where not exists (select 1 from public.gv_ppp_programacion_diaria g
--                       where regexp_replace(btrim(g.np),'\.0+$','') = b.np);
-- ----------------------------------------------------------------------------
