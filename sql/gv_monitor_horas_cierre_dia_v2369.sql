-- REGLA_CONFIRMADA_POR_USUARIO — Luis, 28/09: "fijate que cuando cierre el día hoy (aprox 17:30) tenga bien computadas sus horas"
-- v23.69 — gv_monitor_horas_operario_dia: la tarea ABIERTA ya no se PIERDE al fichar salida (FJ): cuenta HASTA el FJ.
-- Sin FJ, cuenta hasta ahora pero no más allá del fin de jornada (max(último evento, hora_salida)), igual que hs_total.
-- Idempotente (marcador v23.69-finab). raise si no matchea.
do $do$
declare d text; n text;
begin
  d := pg_get_functiondef('public.gv_monitor_horas_operario_dia(date)'::regprocedure);
  if d like '%v23.69-finab%' then raise notice 'ya aplicada'; return; end if;
  n := replace(d, $r$abierta as (
  select a.* from abre a
   where now() - a.ini < interval '12 hours'$r$,
$r$abierta as (   -- v23.69-finab: el FJ CIERRA la tarea abierta (no la borra); sin FJ, tope = fin de jornada
  select a.*,
         coalesce((select min(f.ts_cliente) from base f
                    where f.legajo = a.legajo and f.opcion = 'FJ' and f.ts_cliente > a.ini),
                  least(now(), greatest((select max(u.ts_cliente) from base u where u.legajo = a.legajo),
                        (p_dia + coalesce((select e.h_sal from emp e where e.legajo = a.legajo), time '17:00'))
                          at time zone 'America/Argentina/Buenos_Aires'))) as fin
    from abre a
   where now() - a.ini < interval '12 hours'$r$);
  if n = d then raise exception 'no matcheó abierta'; end if; d := n;
  n := replace(d, $r$               or (a.k not in ('EP','AP','MG') and c.opcion = a.k and c.ts_inicio is not null)
               or c.opcion = 'FJ'))$r$,
                  $r$               or (a.k not in ('EP','AP','MG') and c.opcion = a.k and c.ts_inicio is not null)))$r$);
  if n = d then raise exception 'no matcheó el FJ del not exists'; end if; d := n;
  n := replace(d, $r$select x.legajo, x.ini, now() from abierta x where x.k in$r$,
                  $r$select x.legajo, x.ini, x.fin from abierta x where x.k in$r$);
  if n = d then raise exception 'no matcheó muerto abierto'; end if; d := n;
  n := replace(d, $r$ab_tr as (select distinct on (x.legajo) x.legajo, x.k, x.ini from abierta x$r$,
                  $r$ab_tr as (select distinct on (x.legajo) x.legajo, x.k, x.ini, x.fin from abierta x$r$);
  if n = d then raise exception 'no matcheó ab_tr'; end if; d := n;
  n := replace(d, $r$ab_no as (select distinct on (x.legajo) x.legajo, x.k, x.ini from abierta x$r$,
                  $r$ab_no as (select distinct on (x.legajo) x.legajo, x.k, x.ini, x.fin from abierta x$r$);
  if n = d then raise exception 'no matcheó ab_no'; end if; d := n;
  n := replace(d, $r$         greatest(0, extract(epoch from (now() - t.ini)) - coalesce((
           select sum(extract(epoch from (least(now(), m.fin) - greatest(t.ini, m.ini))))
             from muerto m where m.legajo = t.legajo and m.fin > t.ini and m.ini < now()), 0)) as s$r$,
                  $r$         greatest(0, extract(epoch from (t.fin - t.ini)) - coalesce((
           select sum(extract(epoch from (least(t.fin, m.fin) - greatest(t.ini, m.ini))))
             from muerto m where m.legajo = t.legajo and m.fin > t.ini and m.ini < t.fin), 0)) as s$r$);
  if n = d then raise exception 'no matcheó ab_s'; end if; d := n;
  n := replace(d, $r$select n2.legajo, 'noprod', greatest(0, extract(epoch from (now() - n2.ini))) from ab_no n2$r$,
                  $r$select n2.legajo, 'noprod', greatest(0, extract(epoch from (n2.fin - n2.ini))) from ab_no n2$r$);
  if n = d then raise exception 'no matcheó ab_no s'; end if; d := n;
  execute d;
end $do$;
