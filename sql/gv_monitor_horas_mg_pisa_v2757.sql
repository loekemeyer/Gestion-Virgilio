-- v27.55 (Thomas, D6, 06/10/2026): el GUARDADO (MG) puede durar mucho "siempre y cuando se este guardando o que en
-- (Se aplicó el 06/10 como v27.57; el marcador interno dice v27.55-mgpisa: es la llave de idempotencia, no cambiarlo.)
-- el medio se pise con otra tarea". Caso Isidro (94) 06/10: MG 10:48 -> 16:49 con Limp 10:58-12:09 y 12:46-15:57,
-- IR 16:22-16:29 adentro, y un MG 09:30 -> 10:48 que duplicaba los tres de 09:30/09:59/10:08 (con RT 10:09-10:41 adentro).
-- La vista sumaba mov 4,97 + no prod 5,65 = 10,62 h en una jornada de 8,82.
-- Regla: los tramos MG cerrados del dia cuentan como la UNION de sus intervalos, MENOS lo que se pisa con cualquier
-- otra tarea del legajo (tiempo muerto, tramos cerrados de otras tareas, racks inferidos -IR incluido- y lo abierto).
-- Un IR adentro de un MG deja de quedar "tapado": cuenta como racks y se le saca al MG. El MG que cruza el dia sigue
-- como antes. Parche idempotente sobre la definicion viva de las dos funciones (marcador v27.55-mgpisa).
-- ≡ index.html fetchMonitorDayStats (bloque v27.55-mgpisa).
-- REGLA_CONFIRMADA_POR_USUARIO
do $q$
declare f text; d text; r text[]; i int;
  mg_ctes text := $c$mg_raw as (   -- v27.55-mgpisa (Thomas D6, 06/10): el MG cerrado del dia = UNION de sus tramos, menos lo que se pisa con otra tarea
  select b.legajo, b.ts_inicio as ini, b.ts_cliente as fin from base b
   where b.opcion = 'MG' and b.ts_inicio is not null and b.tanda <> 'ANULADO'
     and (b.ts_inicio at time zone 'America/Argentina/Buenos_Aires')::date = p_dia
     and b.ts_cliente > b.ts_inicio and b.ts_cliente - b.ts_inicio < interval '24 hours'
),
mg_isla as (
  select g.legajo, min(g.ini) as ini, max(g.fin) as fin from (
    select o.legajo, o.ini, o.fin,
           sum(case when o.pm is null or o.ini > o.pm then 1 else 0 end)
             over (partition by o.legajo order by o.ini rows unbounded preceding) as grp
      from (select m.legajo, m.ini, m.fin,
                   max(m.fin) over (partition by m.legajo order by m.ini rows between unbounded preceding and 1 preceding) as pm
              from mg_raw m) o) g
   group by g.legajo, g.grp
),
mg_oc_raw as (
  select m.legajo, m.ini, m.fin from muerto m
  union all
  select b.legajo, b.ts_inicio, b.ts_cliente from base b
   where b.ts_inicio is not null and b.ts_cliente > b.ts_inicio
     and b.opcion not in ('MG','AT','PB','Limp','PC','CT')
  union all
  select s.legajo, s.ini, s.fin from rk_seg s where s.fin > s.ini
  union all
  select t.legajo, t.ini, t.fin from ab_tr t where t.k <> 'MG' and t.fin > t.ini
  union all
  select n2.legajo, n2.ini, n2.fin from ab_no n2 where n2.fin > n2.ini
),
mg_oc as (
  select g.legajo, min(g.ini) as ini, max(g.fin) as fin from (
    select o.legajo, o.ini, o.fin,
           sum(case when o.pm is null or o.ini > o.pm then 1 else 0 end)
             over (partition by o.legajo order by o.ini rows unbounded preceding) as grp
      from (select m.legajo, m.ini, m.fin,
                   max(m.fin) over (partition by m.legajo order by m.ini rows between unbounded preceding and 1 preceding) as pm
              from mg_oc_raw m) o) g
   group by g.legajo, g.grp
),
mg_ag as (
  select i.legajo,
         sum(greatest(0, extract(epoch from (i.fin - i.ini)) - coalesce((
           select sum(extract(epoch from (least(i.fin, o.fin) - greatest(i.ini, o.ini))))
             from mg_oc o where o.legajo = i.legajo and o.fin > i.ini and o.ini < i.fin), 0))) as s
    from mg_isla i group by i.legajo
),
$c$;
begin
 foreach f in array array['public.gv_monitor_horas_operario_dia(date)','public.gv_horas_operario_detalle_v2(date)'] loop
   d := pg_get_functiondef(f::regprocedure);
   if position('v27.55-mgpisa' in d) > 0 then continue; end if;
   r := array[
     -- 1) rk_pts: origen del punto
     $a$    select m.legajo::text as legajo, m.ts as t
      from public."Movimientos_Stock" m$a$,
     $a$    select m.legajo::text as legajo, m.ts as t, 'BR'::text as src
      from public."Movimientos_Stock" m$a$,
     $a$    select b.legajo, b.ts_cliente from base b where b.opcion = 'IR') y$a$,
     $a$    select b.legajo, b.ts_cliente, 'IR' from base b where b.opcion = 'IR') y$a$,
     -- 2) un IR adentro de un MG ya no queda tapado por el MG
     $a$                        and y.t > c.ts_inicio and y.t <= c.ts_cliente + interval '1 minute')$a$,
     $a$                        and not (y.src = 'IR' and c.opcion = 'MG')
                        and y.t > c.ts_inicio and y.t <= c.ts_cliente + interval '1 minute')$a$,
     -- 3) ev sabe si el tramo cruza el dia
     $a$  select n.legajo, n.opcion, n.tanda,
         greatest(0, n.open_s$a$,
     $a$  select n.legajo, n.opcion, n.tanda, (n.dia_ini <> n.dia_fin) as cruza,
         greatest(0, n.open_s$a$];
   if f like '%operario_dia%' then
     r := r || array[
       $a$sum(e.dur_s) filter (where e.opcion in ('MG','RT','RI','EI','RKB','IRT') and e.tanda <> 'ANULADO') as mov_s,$a$,
       $a$sum(e.dur_s) filter (where (e.opcion in ('RT','RI','EI','RKB','IRT') or (e.opcion = 'MG' and e.cruza)) and e.tanda <> 'ANULADO') as mov_s,$a$,
       $a$legajos as ($a$,
       mg_ctes || 'legajos as (',
       $a$coalesce(b.mov_s, 0) + coalesce(ab.mov_s, 0) + coalesce(rk.s, 0)$a$,
       $a$coalesce(b.mov_s, 0) + coalesce(ab.mov_s, 0) + coalesce(rk.s, 0) + coalesce(mg.s, 0)$a$,
       $a$  left join rk_ag  rk on rk.legajo = l.legajo$a$,
       $a$  left join rk_ag  rk on rk.legajo = l.legajo
  left join mg_ag  mg on mg.legajo = l.legajo$a$];
   else
     r := r || array[
       $a$   where e.opcion in ('CC','CR','RR','MG','RT','RI','EI','RKB','IRT','AT','PB','Limp','PC','CT','Perm')$a$,
       $a$   where (e.opcion in ('CC','CR','RR','RT','RI','EI','RKB','IRT','AT','PB','Limp','PC','CT','Perm') or (e.opcion = 'MG' and e.cruza))$a$,
       $a$det as ($a$,
       mg_ctes || 'det as (',
       $a$  union all select r.legajo, 'RKB', r.s::numeric from rk_ag r$a$,
       $a$  union all select r.legajo, 'RKB', r.s::numeric from rk_ag r
  union all select g.legajo, 'MG', g.s::numeric from mg_ag g$a$];
   end if;
   for i in 1 .. array_length(r,1) by 2 loop
     if (length(d) - length(replace(d, r[i], ''))) / length(r[i]) <> 1 then
       raise exception 'no matchea (%) en %: %', i, f, left(r[i], 60);
     end if;
     d := replace(d, r[i], r[i+1]);
   end loop;
   execute d;
 end loop;
end $q$;
-- Rollback: volver a la definicion anterior (pg_get_functiondef guardado en el chat de la sesion) o aplicar
-- los reemplazos al reves; la huella vuelve al md5 anterior.
