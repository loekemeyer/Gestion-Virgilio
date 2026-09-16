-- ============================================================================
-- BACKUP 2026-09-16 — `vista_productividad_diaria` y `vista_productividad_semanal`
-- TAL COMO ESTABAN antes de la v19.07 (netear el tiempo muerto, problema 349).
--
-- Volcadas con `pg_get_viewdef(..., true)` y reescritas legibles SIN cambiar la
-- semántica. Las dos tenían `reloptions = {security_invoker=true}`.
--
-- ROLLBACK: correr este archivo entero. Deja las vistas sin el neteo (el tiempo muerto
-- vuelve a contarse adentro del picking y del armado).
-- ============================================================================

create or replace view public.vista_productividad_diaria
with (security_invoker = true) as
with ev as (
  select coalesce(legajo,'?') as legajo, opcion,
    ((coalesce(ts_cliente, created_at) at time zone 'America/Argentina/Buenos_Aires'))::date as dia,
    upper(btrim(texto)) as tanda, ts_inicio, ts_cliente,
    (ts_inicio is not null and ts_cliente > ts_inicio
      and extract(epoch from (ts_cliente - ts_inicio)) >= 60
      and extract(epoch from (ts_cliente - ts_inicio)) <= 43200
      and ((ts_inicio at time zone 'America/Argentina/Buenos_Aires'))::date
        = ((ts_cliente at time zone 'America/Argentina/Buenos_Aires'))::date) as valido,
    case opcion when 'TAP' then 180 else 120 end as cap_min
  from public."Registros_Produccion_Virgilio"
  where coalesce(ts_cliente, created_at) > (now() - interval '40 days')
    and not es_legajo_test(legajo)
    and opcion = any (array['TAP','TP'])
), evc as (
  select legajo, opcion, dia, tanda, ts_inicio,
    ts_inicio + least(ts_cliente - ts_inicio, cap_min * interval '1 minute') as e_cap
  from ev where valido
), m3 as (select tanda, m3 from public.vista_tanda_m3),
isl as (
  select y.legajo, y.dia, y.opcion, y.tanda, y.s, y.e,
    sum(case when y.rmax is null or y.s > y.rmax then 1 else 0 end)
      over (partition by y.legajo, y.dia, y.opcion, y.tanda order by y.s, y.e) as grp
  from (select legajo, dia, opcion, tanda, ts_inicio as s, e_cap as e,
          max(e_cap) over (partition by legajo, dia, opcion, tanda order by ts_inicio, e_cap
                           rows between unbounded preceding and 1 preceding) as rmax
        from evc) y
), efft as (
  select g.legajo, g.dia, g.opcion, g.tanda,
    sum(extract(epoch from (g.me - g.ms)) / 60.0) as eff_min
  from (select legajo, dia, opcion, tanda, grp, min(s) as ms, max(e) as me
        from isl group by legajo, dia, opcion, tanda, grp) g
  group by g.legajo, g.dia, g.opcion, g.tanda
), tnd as (
  select e.legajo, e.dia, e.opcion, e.tanda, max(m.m3) as m3,
    bool_or(e.valido) as any_valido, coalesce(max(ef.eff_min), 0) as eff_min
  from ev e
  left join m3 m on m.tanda = e.tanda
  left join efft ef on ef.legajo = e.legajo and ef.dia = e.dia
                   and ef.opcion = e.opcion and ef.tanda = e.tanda
  group by e.legajo, e.dia, e.opcion, e.tanda
), tndr as (
  select tnd.*,
    (tnd.m3 is not null and tnd.eff_min > 0
      and (60 * tnd.m3 / tnd.eff_min) > case when tnd.opcion = 'TAP' then 4.0 else 8.0 end) as ritmo_roto
  from tnd
)
select legajo, dia,
  count(*) filter (where opcion = 'TAP') as armadas,
  count(*) filter (where opcion = 'TP') as pickeadas,
  round(coalesce(sum(m3) filter (where opcion='TAP' and any_valido and not ritmo_roto and m3 is not null), 0), 2) as arm_m3,
  round(coalesce(sum(m3) filter (where opcion='TP'  and any_valido and not ritmo_roto and m3 is not null), 0), 2) as pick_m3,
  round(coalesce(sum(eff_min) filter (where opcion='TAP' and any_valido and not ritmo_roto), 0), 1) as arm_eff_min,
  round(coalesce(sum(eff_min) filter (where opcion='TP'  and any_valido and not ritmo_roto), 0), 1) as pick_eff_min,
  round(coalesce(sum(m3) filter (where opcion='TAP' and m3 is not null), 0), 2) as arm_m3_tot,
  round(coalesce(sum(m3) filter (where opcion='TP'  and m3 is not null), 0), 2) as pick_m3_tot
from tndr group by legajo, dia;

alter view public.vista_productividad_diaria set (security_invoker = true);


create or replace view public.vista_productividad_semanal
with (security_invoker = true) as
with ev as (
  select coalesce(legajo,'?') as legajo, opcion,
    ((coalesce(ts_cliente, created_at) at time zone 'America/Argentina/Buenos_Aires'))::date as dia,
    date_trunc('week', ((coalesce(ts_cliente, created_at) at time zone 'America/Argentina/Buenos_Aires'))::date::timestamp) as sem,
    upper(btrim(texto)) as tanda, ts_inicio, ts_cliente,
    (ts_inicio is not null and ts_cliente > ts_inicio
      and extract(epoch from (ts_cliente - ts_inicio)) >= 60
      and extract(epoch from (ts_cliente - ts_inicio)) <= 43200
      and ((ts_inicio at time zone 'America/Argentina/Buenos_Aires'))::date
        = ((ts_cliente at time zone 'America/Argentina/Buenos_Aires'))::date) as valido,
    case when ts_inicio is not null and ts_cliente > ts_inicio
         then extract(epoch from (ts_cliente - ts_inicio)) / 60.0 else null::numeric end as raw_min,
    case opcion
      when 'TAP' then 180 when 'TP' then 120
      when 'CC' then 60 when 'CCN' then 60 when 'CCR' then 60
      when 'CR' then 30 when 'CRN' then 30
      when 'MG' then 20 when 'PC' then 90
      when 'RT' then 45 when 'RR' then 45 when 'RI' then 30 when 'EI' then 30
      when 'Limp' then 30 else 30 end as cap_min
  from public."Registros_Produccion_Virgilio"
  where coalesce(ts_cliente, created_at) > (now() - interval '56 days')
    and not es_legajo_test(legajo)
), evc as (
  select legajo, opcion, dia, sem, tanda, ts_inicio, ts_cliente, valido, raw_min, cap_min,
    ts_inicio + least(ts_cliente - ts_inicio, cap_min * interval '1 minute') as e_cap
  from ev where valido
), m3 as (
  select upper(btrim(tanda)) as tanda, sum(m3) as m3
  from public."GV_PPP_Entregados_Historico"
  where m3 > 0 and btrim(coalesce(tanda,'')) <> ''
  group by upper(btrim(tanda))
), jor as (
  select d.legajo, d.sem, round(sum(d.span), 1) as jornada_min,
    count(*) filter (where d.worked) as jornadas
  from (select legajo, sem, dia,
          least(extract(epoch from (max(ts_cliente) - min(coalesce(ts_inicio, ts_cliente)))) / 60.0, 960) as span,
          bool_or(opcion = any (array['TAP','TP'])) as worked
        from ev group by legajo, sem, dia) d
  group by d.legajo, d.sem
), iv as (
  select legajo, sem, ts_inicio as s, e_cap as e, 'all'::text as scope from evc
  union all
  select legajo, sem, ts_inicio, e_cap, 'prod'::text from evc where opcion = any (array['TAP','TP'])
  union all
  select legajo, sem, ts_inicio, e_cap, 'arm'::text  from evc where opcion = 'TAP'
  union all
  select legajo, sem, ts_inicio, e_cap, 'pick'::text from evc where opcion = 'TP'
), isl as (
  select y.legajo, y.sem, y.scope, y.s, y.e,
    sum(case when y.rmax is null or y.s > y.rmax then 1 else 0 end)
      over (partition by y.legajo, y.sem, y.scope order by y.s, y.e) as grp
  from (select legajo, sem, scope, s, e,
          max(e) over (partition by legajo, sem, scope order by s, e
                       rows between unbounded preceding and 1 preceding) as rmax
        from iv) y
), eff as (
  select z.legajo, z.sem,
    max(z.tot) filter (where z.scope = 'arm')  as arm_eff,
    max(z.tot) filter (where z.scope = 'pick') as pick_eff,
    max(z.tot) filter (where z.scope = 'prod') as prod_eff,
    max(z.tot) filter (where z.scope = 'all')  as all_eff
  from (select mg.legajo, mg.sem, mg.scope,
          sum(extract(epoch from (mg.me - mg.ms)) / 60.0) as tot
        from (select legajo, sem, scope, grp, min(s) as ms, max(e) as me
              from isl group by legajo, sem, scope, grp) mg
        group by mg.legajo, mg.sem, mg.scope) z
  group by z.legajo, z.sem
)
select e.legajo,
  to_char(e.sem, 'IYYY-"S"IW') as semana,
  e.sem as semana_ts,
  count(*) filter (where e.opcion = 'TAP') as armadas,
  count(*) filter (where e.opcion = 'TP') as pickeadas,
  round(percentile_cont(0.5) within group (order by (e.raw_min::double precision))
        filter (where e.opcion = 'TAP' and e.valido))::integer as min_x_armado,
  round(coalesce(ef.arm_eff, 0), 1)  as arm_eff_min,
  round(coalesce(ef.pick_eff, 0), 1) as pick_eff_min,
  round(coalesce(ef.prod_eff, 0), 1) as prod_eff_min,
  round(coalesce(ef.all_eff, 0), 1)  as all_eff_min,
  round(sum(m.m3) filter (where e.opcion = 'TAP' and e.valido and m.m3 is not null), 2) as arm_m3,
  round(sum(m.m3) filter (where e.opcion = 'TP'  and e.valido and m.m3 is not null), 2) as pick_m3,
  count(*) filter (where e.opcion = 'TAP' and e.valido and m.m3 is not null) as arm_tandas_dur,
  count(*) filter (where e.opcion = 'TP'  and e.valido and m.m3 is not null) as pick_tandas_dur,
  coalesce(max(j.jornadas), 0::bigint) as jornadas,
  round(coalesce(max(j.jornada_min), 0), 1) as jornada_min,
  round(sum(least(e.raw_min, e.cap_min::numeric)) filter (where e.valido and (e.opcion = any (array['CC','CCN','CCR']))), 1) as t_carga,
  round(sum(least(e.raw_min, e.cap_min::numeric)) filter (where e.valido and (e.opcion = any (array['CR','CRN']))), 1) as t_control,
  round(sum(least(e.raw_min, e.cap_min::numeric)) filter (where e.valido and e.opcion = 'MG'), 1) as t_movim,
  round(sum(least(e.raw_min, e.cap_min::numeric)) filter (where e.valido and e.opcion = 'PC'), 1) as t_comida,
  round(sum(least(e.raw_min, e.cap_min::numeric)) filter (where e.valido and (e.opcion = any (array['RT','RR','RI','EI']))), 1) as t_recep,
  round(sum(least(e.raw_min, e.cap_min::numeric)) filter (where e.valido and e.opcion = 'Limp'), 1) as t_limp,
  round(sum(least(e.raw_min, e.cap_min::numeric)) filter (where e.valido and (e.opcion <> all (array['TAP','TP','CC','CCN','CCR','CR','CRN','MG','PC','RT','RR','RI','EI','Limp']))), 1) as t_otros
from ev e
  left join m3 m on m.tanda = e.tanda
  left join jor j on j.legajo = e.legajo and j.sem = e.sem
  left join eff ef on ef.legajo = e.legajo and ef.sem = e.sem
group by e.legajo, e.sem, ef.arm_eff, ef.pick_eff, ef.prod_eff, ef.all_eff
having count(*) filter (where e.opcion = any (array['TAP','TP'])) > 0;

alter view public.vista_productividad_semanal set (security_invoker = true);
