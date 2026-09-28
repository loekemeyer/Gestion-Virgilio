-- REGLA_CONFIRMADA_POR_USUARIO — Luis, 28/09: "Isidro sigue en 1,6 hs MOV … no podés recuperar el dato?"
-- v23.68 — gv_monitor_horas_operario_dia: el trabajo en racks SIN tramo registrado (las bajadas y los
-- ingresos a racks anteriores a la v23.66, o de un celular viejo) se INFIERE de los movimientos reales:
--   · puntos = Movimientos_Stock tipo baja_racks (depósito racks/racks_ch) + eventos IR, del legajo y del día;
--   · se ignora el punto que cae adentro de un tramo registrado (RKB/IRT) o de otra tarea cerrada;
--   · tramo inferido = desde la actividad anterior del legajo (evento o punto) hasta el movimiento,
--     con TOPE de 60 min por tramo; menos el tiempo muerto que caiga adentro;
--   · suma a Hs MOV. Es una ESTIMACIÓN (el inicio real no quedó registrado): el tope evita inflarla.
-- ≡ index.html fetchMonitorDayStats (rkInferido). Idempotente (marcador v23.68-rkinf); raise si no matchea.
do $do$
declare d text; n text;
begin
  d := pg_get_functiondef('public.gv_monitor_horas_operario_dia(date)'::regprocedure);
  if d like '%v23.68-rkinf%' then raise notice 'ya aplicada'; return; end if;
  n := replace(d, $r$ab_tr as (select distinct on (x.legajo)$r$,
$r$rk_pts as (   -- v23.68-rkinf: bajadas/ingresos a racks sin tramo registrado
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
         greatest(p.t - interval '60 minutes',
                  coalesce((select max(z.ts) from (
                              select b.ts_cliente as ts from base b where b.legajo = p.legajo and b.ts_cliente < p.t
                              union all
                              select q.t from rk_pts q where q.legajo = p.legajo and q.t < p.t) z),
                           p.t - interval '60 minutes')) as ini
    from rk_pts p
),
rk_ag as (
  select s.legajo,
         sum(greatest(0, extract(epoch from (s.fin - s.ini)) - coalesce((
           select sum(extract(epoch from (least(s.fin, m.fin) - greatest(s.ini, m.ini))))
             from muerto m where m.legajo = s.legajo and m.fin > s.ini and m.ini < s.fin), 0))) as s
    from rk_seg s group by s.legajo
),
ab_tr as (select distinct on (x.legajo)$r$);
  if n = d then raise exception 'no matcheó ab_tr'; end if; d := n;
  n := replace(d, $r$       round(((coalesce(b.mov_s, 0) + coalesce(ab.mov_s, 0)) / 3600.0)::numeric, 2),$r$,
                  $r$       round(((coalesce(b.mov_s, 0) + coalesce(ab.mov_s, 0) + coalesce(rk.s, 0)) / 3600.0)::numeric, 2),$r$);
  if n = d then raise exception 'no matcheó mov del select'; end if; d := n;
  n := replace(d, $r$  left join ab_ag  ab on ab.legajo = l.legajo$r$,
                  $r$  left join ab_ag  ab on ab.legajo = l.legajo
  left join rk_ag  rk on rk.legajo = l.legajo$r$);
  if n = d then raise exception 'no matcheó el join ab_ag'; end if; d := n;
  n := replace(d, $r$legajos as (select b.legajo from base b group by b.legajo)$r$,
                  $r$legajos as (select b.legajo from base b group by b.legajo union select r.legajo from rk_pts r)$r$);
  if n = d then raise exception 'no matcheó legajos'; end if; d := n;
  execute d;
end $do$;
