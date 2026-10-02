-- v25.50 (Elías, 01/10/2026): detalle de horas por operario y por TAREA de un día.
-- Es la misma lógica de neteo de gv_monitor_horas_operario_dia (copia verbatim de sus CTE), pero en vez
-- de agrupar en prod / mov / no prod devuelve una columna por tarea, más los m³ de las tandas cerradas
-- (para m³/h de picking y de armado). La usa la Edge Function gv-reporte-horas-xlsx.
-- OBJETO NUEVO: no reemplaza nada. Sólo lectura. Ejecutable sólo por service_role.
-- v25.50b: se alinea con la regla v25.64-anulado de gv_monitor_horas_operario_dia (Luis, 01/10): el
-- tramo con texto ANULADO de CC/CR/RR/RT/RI/EI NO cuenta en su tarea; sale aparte en `anu` (no productivo).
-- Es la versión _v2 porque cambiar las columnas de salida exige drop + create, y el DDL de la base
-- tardaba más de 60 s el 01/10. La _v1 (sin `anu`) se descarta.
-- Chequeo de que la lógica no se desfasó de la viva (sin comentarios ni espacios, hasta `pick as (`
-- y de `jornada as (` a `ab_no as (`): ver el barrido md5 al pie.
-- Rollback: drop function public.gv_horas_operario_detalle_v2(date);
create or replace function public.gv_horas_operario_detalle_v2(p_dia date)
 returns table(legajo text, nombre text, dia date, jor numeric, pick numeric, arm numeric,
               cr numeric, rg numeric, limp numeric, rk numeric, pc numeric, cc numeric, rr numeric,
               pb numeric, ei numeric, at numeric, ct numeric, ri numeric, perm numeric,
               m3p numeric, m3a numeric, anu numeric)
 language sql stable
 set search_path to 'public'
as $f$
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
         coalesce(nullif(btrim(e."Empleado"), ''), '') as nombre,
         coalesce(nullif(btrim(e."hora_entrada"::text), '')::time, time '08:00') as h_ent,
         coalesce(nullif(btrim(e."hora_salida"::text),  '')::time, time '17:00') as h_sal
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
abre as (
  select b.legajo, b.tanda, b.ts_cliente as ini,
         case b.opcion when 'MGI' then 'MG' when 'RKI' then 'RKB' when 'IRI' then 'IRT' else b.opcion end as k
    from base b
   where b.ts_inicio is null
     and b.opcion in ('EP','AP','MGI','RKI','IRI','CR','RR','CC','RT','MG','RI','EI','AT','PB','Limp','PC','Perm','CT')
),
abierta as (
  select a.*,
         least(coalesce((select min(f.ts_cliente) from base f
                    where f.legajo = a.legajo and f.opcion = 'FJ' and f.ts_cliente > a.ini),
                  least(now(), greatest((select max(u.ts_cliente) from base u where u.legajo = a.legajo),
                        (p_dia + coalesce((select e.h_sal from emp e where e.legajo = a.legajo), time '17:00'))
                          at time zone 'America/Argentina/Buenos_Aires'))),
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
  union all
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
              else 0 end as open_s,
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
jornada as (
  select b.legajo, min(b.ts_cliente) as primer,
         max(b.ts_cliente) filter (where b.opcion = 'FJ') as fj,
         max(b.ts_cliente) as ultimo
    from base b group by b.legajo
),
rk_pts as (
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
det as (
  select e.legajo,
         case when e.tanda = 'ANULADO' and e.opcion in ('CC','CR','RR','RT','RI','EI') then 'ANU' else e.opcion end as k,
         sum(e.dur_s)::numeric as s from evok e
   where e.opcion in ('CC','CR','RR','MG','RT','RI','EI','RKB','IRT','AT','PB','Limp','PC','CT','Perm')
   group by 1,2
  union all select p.legajo, 'PICK', p.dur_s::numeric from pick_ag p
  union all select a.legajo, 'ARM', a.dur_s::numeric from arm_ag a
  union all select t.legajo, case t.k when 'EP' then 'PICK' when 'AP' then 'ARM' else t.k end,
         greatest(0, extract(epoch from (t.fin - t.ini)) - coalesce((
           select sum(extract(epoch from (least(t.fin, m.fin) - greatest(t.ini, m.ini))))
             from muerto m where m.legajo = t.legajo and m.fin > t.ini and m.ini < t.fin), 0))::numeric
    from ab_tr t
  union all select n2.legajo, n2.k, greatest(0, extract(epoch from (n2.fin - n2.ini)))::numeric from ab_no n2
  union all select r.legajo, 'RKB', r.s::numeric from rk_ag r
  union all select j.legajo, 'JORNADA',
         extract(epoch from (coalesce(j.fj, greatest(j.ultimo, least(now(),
           (p_dia + coalesce((select e2.h_sal from emp e2 where e2.legajo = j.legajo), time '17:00'))
             at time zone 'America/Argentina/Buenos_Aires')))
           - j.primer))::numeric
    from jornada j
),
agg as (select d.legajo, d.k, sum(d.s) as s from det d group by 1,2),
m3 as (
  select b.legajo, b.opcion, sum(v.m3) as m3
    from (select distinct x.legajo, x.opcion, x.tanda from base x
           where x.opcion in ('TP','TAP') and x.ts_inicio is not null and x.tanda <> '') b
    join public.vista_tanda_m3 v on upper(btrim(v.tanda)) = b.tanda
   group by 1,2
)
select a.legajo,
       coalesce(nullif((select e3.nombre from emp e3 where e3.legajo = a.legajo), ''), 'Leg ' || a.legajo),
       p_dia,
       round(coalesce(sum(a.s) filter (where a.k = 'JORNADA'), 0) / 3600.0, 4),
       round(coalesce(sum(a.s) filter (where a.k = 'PICK'), 0) / 3600.0, 4),
       round(coalesce(sum(a.s) filter (where a.k = 'ARM'), 0) / 3600.0, 4),
       round(coalesce(sum(a.s) filter (where a.k = 'CR'), 0) / 3600.0, 4),
       round(coalesce(sum(a.s) filter (where a.k in ('MG','RT')), 0) / 3600.0, 4),
       round(coalesce(sum(a.s) filter (where a.k = 'Limp'), 0) / 3600.0, 4),
       round(coalesce(sum(a.s) filter (where a.k in ('RKB','IRT')), 0) / 3600.0, 4),
       round(coalesce(sum(a.s) filter (where a.k = 'PC'), 0) / 3600.0, 4),
       round(coalesce(sum(a.s) filter (where a.k = 'CC'), 0) / 3600.0, 4),
       round(coalesce(sum(a.s) filter (where a.k = 'RR'), 0) / 3600.0, 4),
       round(coalesce(sum(a.s) filter (where a.k = 'PB'), 0) / 3600.0, 4),
       round(coalesce(sum(a.s) filter (where a.k = 'EI'), 0) / 3600.0, 4),
       round(coalesce(sum(a.s) filter (where a.k = 'AT'), 0) / 3600.0, 4),
       round(coalesce(sum(a.s) filter (where a.k = 'CT'), 0) / 3600.0, 4),
       round(coalesce(sum(a.s) filter (where a.k = 'RI'), 0) / 3600.0, 4),
       round(coalesce(sum(a.s) filter (where a.k = 'Perm'), 0) / 3600.0, 4),
       round(coalesce((select x.m3 from m3 x where x.legajo = a.legajo and x.opcion = 'TP'), 0), 3),
       round(coalesce((select x.m3 from m3 x where x.legajo = a.legajo and x.opcion = 'TAP'), 0), 3),
       round(coalesce(sum(a.s) filter (where a.k = 'ANU'), 0) / 3600.0, 4)
  from agg a
 where a.legajo ~ '^[0-9]+$' and a.legajo not in ('600', '999', '9999')
 group by a.legajo
 order by a.legajo;
$f$;

revoke all on function public.gv_horas_operario_detalle_v2(date) from public, anon, authenticated;
grant execute on function public.gv_horas_operario_detalle_v2(date) to service_role;

-- Barrido de que la lógica sigue igual a la viva (los dos hashes tienen que dar IGUAL en las dos filas):
-- with n as (select proname, regexp_replace(regexp_replace(prosrc,'--[^\n]*','','g'),'\s+','','g') s
--              from pg_proc where pronamespace='public'::regnamespace
--               and proname in ('gv_monitor_horas_operario_dia','gv_horas_operario_detalle_v2'))
-- select proname, md5(substring(s from 1 for position('pickas(' in s))) a,
--        md5(substring(s from position('jornadaas(' in s) for position('ab_noas(' in s)-position('jornadaas(' in s))) b from n;

-- ---------------------------------------------------------------------------------------------------
-- gv_horas_operario_tandas_v2(p_dia): detalle por tanda de picking (TP) y armado (TAP) con minutos NETOS
-- (pausas descontadas, D15 = B de Elías, 01/10). Es el mismo cuerpo de gv_horas_operario_detalle_v2
-- hasta el CTE `arm` inclusive, con otra salida: así la suma por operario cierra con «Pking x Hs» /
-- «Arma x Hs» del resumen. Se crea copiando la definición viva (no se duplica el texto acá).
-- Sólo lectura, sólo service_role. Rollback: drop function public.gv_horas_operario_tandas_v2(date);
do $x$
declare src text; corte int; fin text;
begin
  select p.prosrc into src from pg_proc p where p.oid = 'public.gv_horas_operario_detalle_v2(date)'::regprocedure;
  corte := position('pick_ag as (' in src);
  if corte = 0 then raise exception 'no encontre pick_ag'; end if;
  fin := $q$z as (select 1)
select t.legajo, t.tarea, t.tanda, round(t.dur_s / 60.0, 1), round(v.m3, 3)
  from (select p.legajo, 'pick'::text as tarea, p.tanda, p.dur_s from pick p
        union all select a.legajo, 'arm', a.tanda, a.dur_s from arm a) t
  join public.vista_tanda_m3 v on upper(btrim(v.tanda)) = t.tanda
 where t.legajo ~ '^[0-9]+$' and t.legajo not in ('600','999','9999')
 order by 1, 2, 5 desc;
$q$;
  execute 'create or replace function public.gv_horas_operario_tandas_v2(p_dia date)
 returns table(legajo text, tarea text, tanda text, min_net numeric, m3 numeric)
 language sql stable set search_path to ''public'' as $f$' || substring(src from 1 for corte - 1) || fin || '$f$';
end $x$;
revoke all on function public.gv_horas_operario_tandas_v2(date) from public, anon, authenticated;
grant execute on function public.gv_horas_operario_tandas_v2(date) to service_role;
