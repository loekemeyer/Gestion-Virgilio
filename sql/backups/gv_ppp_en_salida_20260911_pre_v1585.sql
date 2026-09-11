-- BACKUP 2026-09-11 — definición de public.gv_ppp_en_salida ANTES de la v15.85
-- (estado v15.63: CCN ∪ facturadas ∪ salida presunta). Restaurar = correr esto tal cual.
-- Atajo equivalente, sin DDL:
--   update public."PPP_Web_Config" set valor = 0 where clave = 'en_salida_solo_cargadas';
create or replace view public.gv_ppp_en_salida
with (security_invoker = true) as
with cfg as (
  select coalesce((select c.valor from public."PPP_Web_Config" c where c.clave = 'salida_presunta_horas'), 36) as horas
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
  and (c.np is not null or fa.np is not null
       or nullif(left(coalesce(w.fecha_entrega, i.fecha_entrega), 10), '')::date < current_date)
  and not exists (select 1 from public."NP_Canceladas" nc
                   where regexp_replace(btrim(nc.np), '\.0+$', '') = b.np)
  and not exists (select 1 from public."GV_Web_Cancelados" wc
                   where upper(btrim(wc.np_label)) = upper(b.np));

