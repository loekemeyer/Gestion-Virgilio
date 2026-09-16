-- ============================================================================
-- BACKUP — definiciones de vista_productividad_diaria / _semanal TAL COMO
-- ESTABAN ANTES de la v19.23 (2026-09-16), o sea la v19.07 (tiempo muerto
-- neteado, pero el tiempo de RELOJ como base y el cruce de día descartado).
--
-- Este archivo es el ROLLBACK: se ejecuta tal cual y deja las dos vistas como
-- estaban. Sacado con pg_get_viewdef y formateado a mano.
--
-- ⚠ `CREATE OR REPLACE VIEW` sin `WITH (...)` BORRA las reloptions, así que las
--    dos llevan el `with (security_invoker = true)` adentro Y el `alter view`
--    después. Sin security_invoker la vista corre como postgres y saltea la RLS.
--
-- Qué cambió en la v19.23 (para entender qué se estaría deshaciendo):
--   1) `valido` exigía MISMO DÍA y tope de 43200 s (12 h) de reloj → una tanda
--      cerrada al otro día se descartaba entera, con sus m³.
--   2) `e_cap` topeaba el tiempo de RELOJ (`ts_inicio + least(raw, cap)`).
--   3) la duración era `epoch(me - ms)/60`, o sea reloj, con la noche adentro.
-- ============================================================================

create or replace view public.vista_productividad_diaria with (security_invoker = true) as
with ev as (
  select coalesce(r.legajo, '?') as legajo,
         r.opcion,
         (coalesce(r.ts_cliente, r.created_at) at time zone 'America/Argentina/Buenos_Aires')::date as dia,
         upper(btrim(r.texto)) as tanda,
         r.ts_inicio,
         r.ts_cliente,
         (r.ts_inicio is not null
          and r.ts_cliente > r.ts_inicio
          and extract(epoch from (r.ts_cliente - r.ts_inicio)) >= 60
          and extract(epoch from (r.ts_cliente - r.ts_inicio)) <= 43200
          and (r.ts_inicio  at time zone 'America/Argentina/Buenos_Aires')::date
            = (r.ts_cliente at time zone 'America/Argentina/Buenos_Aires')::date) as valido,
         case r.opcion when 'TAP' then 180 else 120 end as cap_min
    from public."Registros_Produccion_Virgilio" r
   where coalesce(r.ts_cliente, r.created_at) > now() - interval '40 days'
     and not es_legajo_test(r.legajo)
     and r.opcion in ('TAP', 'TP')
), dead_raw as (
  select coalesce(r.legajo, '?') as legajo,
         r.ts_inicio as s,
         least(r.ts_cliente,
               r.ts_inicio + (case r.opcion when 'PC' then 90 else 30 end) * interval '1 minute') as e
    from public."Registros_Produccion_Virgilio" r
   where coalesce(r.ts_cliente, r.created_at) > now() - interval '40 days'
     and not es_legajo_test(r.legajo)
     and r.opcion in ('AT', 'PB', 'Limp', 'PC', 'CT')
     and r.ts_inicio is not null and r.ts_cliente > r.ts_inicio
), dead_isl as (
  select y.legajo, y.s, y.e,
         sum(case when y.rmax is null or y.s > y.rmax then 1 else 0 end)
           over (partition by y.legajo order by y.s, y.e) as grp
    from (select dr.legajo, dr.s, dr.e,
                 max(dr.e) over (partition by dr.legajo order by dr.s, dr.e
                                 rows between unbounded preceding and 1 preceding) as rmax
            from dead_raw dr) y
), dead as (
  select legajo, min(s) as s, max(e) as e from dead_isl group by legajo, grp
), evc as (
  select ev.legajo, ev.opcion, ev.dia, ev.tanda, ev.ts_inicio,
         ev.ts_inicio + least(ev.ts_cliente - ev.ts_inicio, ev.cap_min * interval '1 minute') as e_cap
    from ev where ev.valido
), m3 as (
  select tanda, m3 from public.vista_tanda_m3
), isl as (
  select y.legajo, y.dia, y.opcion, y.tanda, y.s, y.e,
         sum(case when y.rmax is null or y.s > y.rmax then 1 else 0 end)
           over (partition by y.legajo, y.dia, y.opcion, y.tanda order by y.s, y.e) as grp
    from (select evc.legajo, evc.dia, evc.opcion, evc.tanda,
                 evc.ts_inicio as s, evc.e_cap as e,
                 max(evc.e_cap) over (partition by evc.legajo, evc.dia, evc.opcion, evc.tanda
                                      order by evc.ts_inicio, evc.e_cap
                                      rows between unbounded preceding and 1 preceding) as rmax
            from evc) y
), core as (
  select legajo, dia, opcion, tanda, grp, min(s) as ms, max(e) as me
    from isl group by legajo, dia, opcion, tanda, grp
), muerto as (
  select c.legajo, c.dia, c.opcion, c.tanda, c.grp,
         coalesce(sum(case when d.legajo is null then 0
                           else greatest(0, extract(epoch from (least(c.me, d.e) - greatest(c.ms, d.s))) / 60.0)
                      end), 0) as min_muerto
    from core c
    left join dead d on d.legajo = c.legajo and d.s < c.me and c.ms < d.e
   group by c.legajo, c.dia, c.opcion, c.tanda, c.grp
), efft as (
  select c.legajo, c.dia, c.opcion, c.tanda,
         sum(greatest(0, extract(epoch from (c.me - c.ms)) / 60.0 - mu.min_muerto)) as eff_min
    from core c
    join muerto mu on mu.legajo = c.legajo and mu.dia = c.dia
                  and mu.opcion = c.opcion and mu.tanda = c.tanda and mu.grp = c.grp
   group by c.legajo, c.dia, c.opcion, c.tanda
), tnd as (
  select e.legajo, e.dia, e.opcion, e.tanda,
         max(m.m3) as m3, bool_or(e.valido) as any_valido,
         coalesce(max(ef.eff_min), 0) as eff_min
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
       count(*) filter (where opcion = 'TP')  as pickeadas,
       round(coalesce(sum(m3) filter (where opcion = 'TAP' and any_valido and not ritmo_roto and m3 is not null), 0), 2) as arm_m3,
       round(coalesce(sum(m3) filter (where opcion = 'TP'  and any_valido and not ritmo_roto and m3 is not null), 0), 2) as pick_m3,
       round(coalesce(sum(eff_min) filter (where opcion = 'TAP' and any_valido and not ritmo_roto), 0), 1) as arm_eff_min,
       round(coalesce(sum(eff_min) filter (where opcion = 'TP'  and any_valido and not ritmo_roto), 0), 1) as pick_eff_min,
       round(coalesce(sum(m3) filter (where opcion = 'TAP' and m3 is not null), 0), 2) as arm_m3_tot,
       round(coalesce(sum(m3) filter (where opcion = 'TP'  and m3 is not null), 0), 2) as pick_m3_tot
  from tndr group by legajo, dia;

alter view public.vista_productividad_diaria set (security_invoker = true);

-- ----------------------------------------------------------------------------

create or replace view public.vista_productividad_semanal with (security_invoker = true) as
with ev as (
  select coalesce(r.legajo, '?') as legajo,
         r.opcion,
         (coalesce(r.ts_cliente, r.created_at) at time zone 'America/Argentina/Buenos_Aires')::date as dia,
         date_trunc('week', (coalesce(r.ts_cliente, r.created_at) at time zone 'America/Argentina/Buenos_Aires')::date::timestamp) as sem,
         upper(btrim(r.texto)) as tanda,
         r.ts_inicio,
         r.ts_cliente,
         (r.ts_inicio is not null
          and r.ts_cliente > r.ts_inicio
          and extract(epoch from (r.ts_cliente - r.ts_inicio)) >= 60
          and extract(epoch from (r.ts_cliente - r.ts_inicio)) <= 43200
          and (r.ts_inicio  at time zone 'America/Argentina/Buenos_Aires')::date
            = (r.ts_cliente at time zone 'America/Argentina/Buenos_Aires')::date) as valido,
         case when r.ts_inicio is not null and r.ts_cliente > r.ts_inicio
              then extract(epoch from (r.ts_cliente - r.ts_inicio)) / 60.0 end as raw_min,
         case r.opcion
           when 'TAP' then 180 when 'TP'  then 120
           when 'CC'  then 60  when 'CCN' then 60  when 'CCR' then 60
           when 'CR'  then 30  when 'CRN' then 30
           when 'MG'  then 20  when 'PC'  then 90
           when 'RT'  then 45  when 'RR'  then 45
           when 'RI'  then 30  when 'EI'  then 30
           when 'Limp' then 30 else 30 end as cap_min
    from public."Registros_Produccion_Virgilio" r
   where coalesce(r.ts_cliente, r.created_at) > now() - interval '56 days'
     and not es_legajo_test(r.legajo)
), dead_raw as (
  select coalesce(r.legajo, '?') as legajo,
         r.ts_inicio as s,
         least(r.ts_cliente,
               r.ts_inicio + (case r.opcion when 'PC' then 90 else 30 end) * interval '1 minute') as e
    from public."Registros_Produccion_Virgilio" r
   where coalesce(r.ts_cliente, r.created_at) > now() - interval '56 days'
     and not es_legajo_test(r.legajo)
     and r.opcion in ('AT', 'PB', 'Limp', 'PC', 'CT')
     and r.ts_inicio is not null and r.ts_cliente > r.ts_inicio
), dead_isl as (
  select y.legajo, y.s, y.e,
         sum(case when y.rmax is null or y.s > y.rmax then 1 else 0 end)
           over (partition by y.legajo order by y.s, y.e) as grp
    from (select dr.legajo, dr.s, dr.e,
                 max(dr.e) over (partition by dr.legajo order by dr.s, dr.e
                                 rows between unbounded preceding and 1 preceding) as rmax
            from dead_raw dr) y
), dead as (
  select legajo, min(s) as s, max(e) as e from dead_isl group by legajo, grp
), evc as (
  select ev.legajo, ev.opcion, ev.dia, ev.sem, ev.tanda, ev.ts_inicio, ev.ts_cliente,
         ev.valido, ev.raw_min, ev.cap_min,
         ev.ts_inicio + least(ev.ts_cliente - ev.ts_inicio, ev.cap_min * interval '1 minute') as e_cap
    from ev where ev.valido
), m3 as (
  select upper(btrim(tanda)) as tanda, sum(m3) as m3
    from public."GV_PPP_Entregados_Historico"
   where m3 > 0 and btrim(coalesce(tanda, '')) <> ''
   group by upper(btrim(tanda))
), jor as (
  select d.legajo, d.sem, round(sum(d.span), 1) as jornada_min,
         count(*) filter (where d.worked) as jornadas
    from (select ev.legajo, ev.sem, ev.dia,
                 least(extract(epoch from (max(ev.ts_cliente) - min(coalesce(ev.ts_inicio, ev.ts_cliente)))) / 60.0, 960) as span,
                 bool_or(ev.opcion in ('TAP', 'TP')) as worked
            from ev group by ev.legajo, ev.sem, ev.dia) d
   group by d.legajo, d.sem
), iv as (
  select legajo, sem, ts_inicio as s, e_cap as e, 'all'  as scope from evc
  union all
  select legajo, sem, ts_inicio, e_cap, 'prod' from evc where opcion in ('TAP', 'TP')
  union all
  select legajo, sem, ts_inicio, e_cap, 'arm'  from evc where opcion = 'TAP'
  union all
  select legajo, sem, ts_inicio, e_cap, 'pick' from evc where opcion = 'TP'
), isl as (
  select y.legajo, y.sem, y.scope, y.s, y.e,
         sum(case when y.rmax is null or y.s > y.rmax then 1 else 0 end)
           over (partition by y.legajo, y.sem, y.scope order by y.s, y.e) as grp
    from (select iv.legajo, iv.sem, iv.scope, iv.s, iv.e,
                 max(iv.e) over (partition by iv.legajo, iv.sem, iv.scope order by iv.s, iv.e
                                 rows between unbounded preceding and 1 preceding) as rmax
            from iv) y
), mg as (
  select legajo, sem, scope, grp, min(s) as ms, max(e) as me
    from isl group by legajo, sem, scope, grp
), mgn as (
  select g.legajo, g.sem, g.scope, g.grp, g.ms, g.me,
         coalesce(sum(case when d.legajo is null then 0
                           else greatest(0, extract(epoch from (least(g.me, d.e) - greatest(g.ms, d.s))) / 60.0)
                      end), 0) as min_muerto
    from mg g
    left join dead d on d.legajo = g.legajo and d.s < g.me and g.ms < d.e
   group by g.legajo, g.sem, g.scope, g.grp, g.ms, g.me
), eff as (
  select z.legajo, z.sem,
         max(z.tot) filter (where z.scope = 'arm')  as arm_eff,
         max(z.tot) filter (where z.scope = 'pick') as pick_eff,
         max(z.tot) filter (where z.scope = 'prod') as prod_eff,
         max(z.tot) filter (where z.scope = 'all')  as all_eff
    from (select legajo, sem, scope,
                 sum(greatest(0, extract(epoch from (me - ms)) / 60.0 - min_muerto)) as tot
            from mgn group by legajo, sem, scope) z
   group by z.legajo, z.sem
)
select e.legajo,
       to_char(e.sem, 'IYYY-"S"IW') as semana,
       e.sem as semana_ts,
       count(*) filter (where e.opcion = 'TAP') as armadas,
       count(*) filter (where e.opcion = 'TP')  as pickeadas,
       round(percentile_cont(0.5) within group (order by e.raw_min::double precision)
             filter (where e.opcion = 'TAP' and e.valido))::integer as min_x_armado,
       round(coalesce(ef.arm_eff, 0), 1)  as arm_eff_min,
       round(coalesce(ef.pick_eff, 0), 1) as pick_eff_min,
       round(coalesce(ef.prod_eff, 0), 1) as prod_eff_min,
       round(coalesce(ef.all_eff, 0), 1)  as all_eff_min,
       round(sum(m.m3) filter (where e.opcion = 'TAP' and e.valido and m.m3 is not null), 2) as arm_m3,
       round(sum(m.m3) filter (where e.opcion = 'TP'  and e.valido and m.m3 is not null), 2) as pick_m3,
       count(*) filter (where e.opcion = 'TAP' and e.valido and m.m3 is not null) as arm_tandas_dur,
       count(*) filter (where e.opcion = 'TP'  and e.valido and m.m3 is not null) as pick_tandas_dur,
       coalesce(max(j.jornadas), 0) as jornadas,
       round(coalesce(max(j.jornada_min), 0), 1) as jornada_min,
       round(sum(least(e.raw_min, e.cap_min::numeric)) filter (where e.valido and e.opcion in ('CC','CCN','CCR')), 1) as t_carga,
       round(sum(least(e.raw_min, e.cap_min::numeric)) filter (where e.valido and e.opcion in ('CR','CRN')), 1) as t_control,
       round(sum(least(e.raw_min, e.cap_min::numeric)) filter (where e.valido and e.opcion = 'MG'), 1) as t_movim,
       round(sum(least(e.raw_min, e.cap_min::numeric)) filter (where e.valido and e.opcion = 'PC'), 1) as t_comida,
       round(sum(least(e.raw_min, e.cap_min::numeric)) filter (where e.valido and e.opcion in ('RT','RR','RI','EI')), 1) as t_recep,
       round(sum(least(e.raw_min, e.cap_min::numeric)) filter (where e.valido and e.opcion = 'Limp'), 1) as t_limp,
       round(sum(least(e.raw_min, e.cap_min::numeric)) filter (where e.valido and e.opcion not in
             ('TAP','TP','CC','CCN','CCR','CR','CRN','MG','PC','RT','RR','RI','EI','Limp')), 1) as t_otros
  from ev e
  left join m3  m on m.tanda  = e.tanda
  left join jor j on j.legajo = e.legajo and j.sem = e.sem
  left join eff ef on ef.legajo = e.legajo and ef.sem = e.sem
 group by e.legajo, e.sem, ef.arm_eff, ef.pick_eff, ef.prod_eff, ef.all_eff
having count(*) filter (where e.opcion in ('TAP', 'TP')) > 0;

alter view public.vista_productividad_semanal set (security_invoker = true);
