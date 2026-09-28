-- v23.72 (Luis, 28/09): "si tienen algo abierto y terminan el día, tiene que marcar".
--  1) lo abierto de un día PASADO también suma a su día (hasta el FJ; sin FJ, fin de jornada).
--  2) cross-day: el tramo del día de apertura ya no se suma el día del cierre (open_s = 0).
--  3) v23.72-sig: una tarea abierta termina donde EMPIEZA la siguiente del legajo (no se superpone).
-- Espejo en index.html fetchMonitorDayStats; lo sostiene tests/mon-vs-vista.cjs.
-- Rollback: volver a sql/gv_monitor_horas_sintope_v2370.sql + huella/fixture.
-- REGLA_CONFIRMADA_POR_USUARIO
CREATE OR REPLACE FUNCTION public.gv_monitor_horas_operario_dia(p_dia date)
 RETURNS TABLE(legajo text, nombre text, dia date, tandas_pick bigint, hs_pick numeric, prom_hs_pick numeric, tandas_arm bigint, hs_arm numeric, prom_hs_arm numeric, hs_prod numeric, hs_mov numeric, hs_noprod numeric, hs_total numeric, en_jornada boolean)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
with feriados as (
  select f.fecha as d from public."GV_Feriados" f where f.tipo = 'feriado'
),
base as (
  select r.legajo::text as legajo, r.opcion,
         upper(btrim(coalesce(r.texto, ''))) as tanda,
         r.ts_inicio, r.ts_cliente
    from public."Registros_Produccion_Virgilio" r
   where (r.ts_cliente at time zone 'America/Argentina/Buenos_Aires')::date = p_dia
     and coalesce(btrim(r.legajo::text), '') not in ('', '0', '1')
     and r.opcion <> 'LT'
),
emp as (
  select e."Legajo"::text as legajo,
         coalesce(nullif(btrim(e."Empleado"), ''), '')                              as nombre,
         coalesce(nullif(btrim(e."hora_entrada"::text), '')::time, time '08:00')    as h_ent,
         coalesce(nullif(btrim(e."hora_salida"::text),  '')::time, time '17:00')    as h_sal
    from public."Empleados" e
),
fj_prev as (
  select r.legajo::text as legajo, max(r.ts_cliente) as fj
    from public."Registros_Produccion_Virgilio" r
   where r.opcion = 'FJ'
     and (r.ts_cliente at time zone 'America/Argentina/Buenos_Aires')::date = p_dia - 1
   group by 1
),
ingreso as (
  select f.legajo::text as legajo, min(f.ts_cliente) as ts
    from public."Fichadas_Virgilio" f
   where f.tipo = 'ingreso'
     and (f.ts_cliente at time zone 'America/Argentina/Buenos_Aires')::date = p_dia
   group by 1
),
abre as (   -- v23.66-abiertas: aperturas de HOY (EP/AP/toggles/MGI/RKI/IRI) sin su cierre
  select b.legajo, b.tanda, b.ts_cliente as ini,
         case b.opcion when 'MGI' then 'MG' when 'RKI' then 'RKB' when 'IRI' then 'IRT' else b.opcion end as k
    from base b
   where b.ts_inicio is null   -- v23.72-cruce: también días pasados (lo abierto al FJ suma a SU día)
     and b.opcion in ('EP','AP','MGI','RKI','IRI','CR','RR','CC','RT','MG','RI','EI','AT','PB','Limp','PC','Perm','CT')
),
abierta as (   -- v23.69-finab: el FJ CIERRA la tarea abierta (no la borra); sin FJ, tope = fin de jornada
  select a.*,
         least(coalesce((select min(f.ts_cliente) from base f
                    where f.legajo = a.legajo and f.opcion = 'FJ' and f.ts_cliente > a.ini),
                  least(now(), greatest((select max(u.ts_cliente) from base u where u.legajo = a.legajo),
                        (p_dia + coalesce((select e.h_sal from emp e where e.legajo = a.legajo), time '17:00'))
                          at time zone 'America/Argentina/Buenos_Aires'))),
         -- v23.72-sig: una tarea abierta termina donde EMPIEZA la siguiente del legajo (no se superpone)
         (select min(coalesce(s.ts_inicio, s.ts_cliente)) from base s
           where s.legajo = a.legajo and coalesce(s.ts_inicio, s.ts_cliente) > a.ini
             and ((s.ts_inicio is null and s.opcion in ('EP','AP','MGI','RKI','IRI','CR','RR','CC','RT','MG','RI','EI','AT','PB','Limp','PC','Perm','CT'))
               or (s.ts_inicio is not null and s.opcion in ('MG','RT','CC','CR','RR','RI','EI','RKB','IRT')))
             and not (a.k in ('EP','AP') and s.opcion in ('EP','AP')))) as fin
    from abre a
   where (p_dia < (now() at time zone 'America/Argentina/Buenos_Aires')::date or now() - a.ini < interval '12 hours')
     and not exists (
       select 1 from base c
        where c.legajo = a.legajo and c.ts_cliente > a.ini
          and (   (a.k = 'EP' and c.opcion = 'TP'  and (c.tanda = '' or c.tanda = a.tanda))
               or (a.k = 'AP' and c.opcion = 'TAP' and (c.tanda = '' or c.tanda = a.tanda))
               or (a.k = 'MG' and c.opcion in ('MG','MGC'))
               or (a.k not in ('EP','AP','MG') and c.opcion = a.k and c.ts_inicio is not null)))
),
muerto_raw as (
  select b.legajo, b.ts_inicio as ini, b.ts_cliente as fin
    from base b
   where b.opcion in ('AT','PB','Limp','PC','CT')
     and b.ts_inicio is not null
     and b.ts_cliente > b.ts_inicio
     and b.ts_cliente - b.ts_inicio <= interval '8 hours'
  union all   -- v23.66: el tiempo muerto ABIERTO (está en el baño ahora) también se resta
  select x.legajo, x.ini, x.fin from abierta x where x.k in ('AT','PB','Limp','PC','CT')
),
muerto_ord as (
  select m.legajo, m.ini, m.fin,
         max(m.fin) over (partition by m.legajo order by m.ini
                          rows between unbounded preceding and 1 preceding) as prev_max
    from muerto_raw m
),
muerto_grp as (
  select o.legajo, o.ini, o.fin,
         sum(case when o.prev_max is null or o.ini > o.prev_max then 1 else 0 end)
           over (partition by o.legajo order by o.ini rows unbounded preceding) as grp
    from muerto_ord o
),
muerto as (select g.legajo, min(g.ini) as ini, max(g.fin) as fin
             from muerto_grp g group by g.legajo, g.grp),
cierres as (
  select b.*,
         (b.ts_inicio  at time zone 'America/Argentina/Buenos_Aires')::date as dia_ini,
         (b.ts_cliente at time zone 'America/Argentina/Buenos_Aires')::date as dia_fin,
         coalesce(e.h_ent, time '08:00') as h_ent,
         coalesce(e.h_sal, time '17:00') as h_sal,
         fp.fj as fj_prev, ing.ts as ingreso_ts
    from base b
    left join emp e      on e.legajo  = b.legajo
    left join fj_prev fp on fp.legajo = b.legajo
    left join ingreso ing on ing.legajo = b.legajo
   where b.ts_inicio is not null
),
tramos as (
  select c.*,
         case when c.dia_ini = c.dia_fin then null
              when c.fj_prev is not null
               and (c.fj_prev at time zone 'America/Argentina/Buenos_Aires')::date = c.dia_ini
              then c.fj_prev
              else (c.dia_ini + c.h_sal) at time zone 'America/Argentina/Buenos_Aires'
         end as fj_open,
         case when c.dia_ini = c.dia_fin then null
              when c.ingreso_ts is not null
               and (c.ingreso_ts at time zone 'America/Argentina/Buenos_Aires')::date = c.dia_fin
              then c.ingreso_ts
              else (c.dia_fin + c.h_ent) at time zone 'America/Argentina/Buenos_Aires'
         end as close_start_raw
    from cierres c
),
calc as (
  select t.*, greatest(t.ts_inicio, t.close_start_raw) as close_start,
         (select count(*) from generate_series(t.dia_ini + 1, t.dia_fin - 1, interval '1 day') g(d)
           where extract(isodow from g.d) < 6
             and not exists (select 1 from feriados f where f.d = g.d::date)) as dias_medio
    from tramos t
),
dur as (
  select c.*,
         case when c.dia_ini = c.dia_fin then c.ts_cliente else least(c.fj_open, c.ts_cliente) end as fin_open,
         case when c.dia_ini = c.dia_fin then greatest(0, extract(epoch from (c.ts_cliente - c.ts_inicio)))
              else 0 end as open_s,   -- v23.72-cruce: el tramo del día de apertura lo suma ESE día (CTE abierta)
         case when c.dia_ini = c.dia_fin then 0
              else greatest(0, extract(epoch from (c.ts_cliente - c.close_start))) end as close_s,
         case when c.dia_ini = c.dia_fin then 0
              else c.dias_medio * greatest(0, extract(epoch from (c.h_sal - c.h_ent))) end as medio_s
    from calc c
),
neteo as (
  select d.*,
         case when d.opcion in ('AT','PB','Limp','PC','CT','Perm') then 0 else
           least(d.open_s, coalesce((
             select sum(extract(epoch from (least(d.fin_open, m.fin) - greatest(d.ts_inicio, m.ini))))
               from muerto m
              where m.legajo = d.legajo and m.fin > d.ts_inicio and m.ini < d.fin_open), 0))
         end as muerto_open_s,
         case when d.dia_ini = d.dia_fin or d.opcion in ('AT','PB','Limp','PC','CT','Perm') then 0 else
           least(d.close_s, coalesce((
             select sum(extract(epoch from (least(d.ts_cliente, m.fin) - greatest(d.close_start, m.ini))))
               from muerto m
              where m.legajo = d.legajo and m.fin > d.close_start and m.ini < d.ts_cliente), 0))
         end as muerto_close_s
    from dur d
),
ev as (
  select n.legajo, n.opcion, n.tanda,
         greatest(0, n.open_s + n.close_s + n.medio_s - n.muerto_open_s - n.muerto_close_s) as dur_s
    from neteo n
),
evok as (select * from ev where dur_s > 0 and dur_s < 24 * 3600),
pick as (select e.legajo, e.tanda, max(e.dur_s) as dur_s from evok e
          where e.opcion = 'TP' and e.tanda <> '' group by e.legajo, e.tanda),
arm  as (select e.legajo, e.tanda, max(e.dur_s) as dur_s from evok e
          where e.opcion = 'TAP' and e.tanda <> '' group by e.legajo, e.tanda),
pick_ag as (select p.legajo, count(*) as tandas, sum(p.dur_s) as dur_s from pick p group by p.legajo),
arm_ag  as (select a.legajo, count(*) as tandas, sum(a.dur_s) as dur_s from arm  a group by a.legajo),
baldes as (
  select e.legajo,
         sum(e.dur_s) filter (where e.opcion in ('CC','CR','RR'))                    as prod_otros_s,
         sum(e.dur_s) filter (where e.opcion in ('MG','RT','RI','EI','RKB','IRT'))               as mov_s,
         sum(e.dur_s) filter (where e.opcion in ('AT','PB','Limp','PC','CT','Perm')) as noprod_s
    from evok e group by e.legajo
),
jornada as (
  select b.legajo, min(b.ts_cliente) as primer,
         max(b.ts_cliente) filter (where b.opcion = 'FJ') as fj,
         max(b.ts_cliente)                                as ultimo
    from base b group by b.legajo
),
rk_pts as (   -- v23.68-rkinf: bajadas/ingresos a racks sin tramo registrado
  select distinct y.legajo, y.t from (
    select m.legajo::text as legajo, m.ts as t
      from public."Movimientos_Stock" m
     where m.tipo = 'baja_racks' and m.deposito in ('racks','racks_ch')
       and (m.ts at time zone 'America/Argentina/Buenos_Aires')::date = p_dia
       and coalesce(btrim(m.legajo::text), '') not in ('', '0', '1')
    union all
    select b.legajo, b.ts_cliente from base b where b.opcion = 'IR') y
   where not exists (select 1 from base c
                      where c.legajo = y.legajo and c.ts_inicio is not null
                        and c.opcion not in ('AT','PB','Limp','PC','CT','Perm')
                        and y.t > c.ts_inicio and y.t <= c.ts_cliente + interval '1 minute')
),
rk_seg as (
  select p.legajo, p.t as fin,
         -- v23.70-sintope (Luis: "sin tope de tramo"): desde la actividad anterior; sin ninguna, desde la entrada
         coalesce((select max(z.ts) from (
                     select b.ts_cliente as ts from base b where b.legajo = p.legajo and b.ts_cliente < p.t
                     union all
                     select q.t from rk_pts q where q.legajo = p.legajo and q.t < p.t) z),
                  least(p.t, (p_dia + coalesce((select e.h_ent from emp e where e.legajo = p.legajo), time '08:00'))
                               at time zone 'America/Argentina/Buenos_Aires')) as ini
    from rk_pts p
),
rk_ag as (
  select s.legajo,
         sum(greatest(0, extract(epoch from (s.fin - s.ini)) - coalesce((
           select sum(extract(epoch from (least(s.fin, m.fin) - greatest(s.ini, m.ini))))
             from muerto m where m.legajo = s.legajo and m.fin > s.ini and m.ini < s.fin), 0))) as s
    from rk_seg s group by s.legajo
),
ab_tr as (select distinct on (x.legajo) x.legajo, x.k, x.ini, x.fin from abierta x
            where x.k not in ('AT','PB','Limp','PC','CT','Perm') order by x.legajo, x.ini desc),
ab_no as (select distinct on (x.legajo) x.legajo, x.k, x.ini, x.fin from abierta x
            where x.k in ('AT','PB','Limp','PC','CT','Perm') order by x.legajo, x.ini desc),
ab_s as (
  select t.legajo, case when t.k in ('EP','AP','CC','CR','RR') then 'prod' else 'mov' end as balde,
         greatest(0, extract(epoch from (t.fin - t.ini)) - coalesce((
           select sum(extract(epoch from (least(t.fin, m.fin) - greatest(t.ini, m.ini))))
             from muerto m where m.legajo = t.legajo and m.fin > t.ini and m.ini < t.fin), 0)) as s
    from ab_tr t
  union all
  select n2.legajo, 'noprod', greatest(0, extract(epoch from (n2.fin - n2.ini))) from ab_no n2
),
ab_ag as (select a.legajo, sum(a.s) filter (where a.balde = 'prod') as prod_s,
                 sum(a.s) filter (where a.balde = 'mov') as mov_s,
                 sum(a.s) filter (where a.balde = 'noprod') as no_s
            from ab_s a group by a.legajo),
legajos as (select b.legajo from base b group by b.legajo union select r.legajo from rk_pts r)
select l.legajo,
       coalesce(nullif(e2.nombre, ''), 'Leg ' || l.legajo),
       p_dia,
       coalesce(p.tandas, 0),
       round((coalesce(p.dur_s, 0) / 3600.0)::numeric, 2),
       case when coalesce(p.tandas, 0) = 0 then 0
            else round((p.dur_s / 3600.0 / p.tandas)::numeric, 2) end,
       coalesce(a.tandas, 0),
       round((coalesce(a.dur_s, 0) / 3600.0)::numeric, 2),
       case when coalesce(a.tandas, 0) = 0 then 0
            else round((a.dur_s / 3600.0 / a.tandas)::numeric, 2) end,
       round(((coalesce(p.dur_s,0) + coalesce(a.dur_s,0)
               + coalesce(b.prod_otros_s,0) + coalesce(ab.prod_s,0)) / 3600.0)::numeric, 2),
       round(((coalesce(b.mov_s, 0) + coalesce(ab.mov_s, 0) + coalesce(rk.s, 0)) / 3600.0)::numeric, 2),
       round(((coalesce(b.noprod_s, 0) + coalesce(ab.no_s, 0)) / 3600.0)::numeric, 2),
       round((extract(epoch from (
              coalesce(j.fj, greatest(j.ultimo, least(now(),
                (p_dia + coalesce(e2.h_sal, time '17:00')) at time zone 'America/Argentina/Buenos_Aires')))
              - j.primer)) / 3600.0)::numeric, 2),
       (j.fj is null)
  from legajos l
  left join pick_ag p on p.legajo = l.legajo
  left join arm_ag  a on a.legajo = l.legajo
  left join baldes  b on b.legajo = l.legajo
  left join ab_ag  ab on ab.legajo = l.legajo
  left join rk_ag  rk on rk.legajo = l.legajo
  left join jornada j on j.legajo = l.legajo
  left join emp e2 on e2.legajo = l.legajo
 order by (coalesce(p.dur_s,0) + coalesce(a.dur_s,0)) desc, 2;
$function$
;
