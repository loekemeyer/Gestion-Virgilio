-- REGLA_CONFIRMADA_POR_USUARIO — Luis, 28/09: "sí. fijate que tengas los puntos de inicio y fin para
-- calcularla bien. fijate que si cortan en el medio para ir al baño tenga la misma lógica que otras
-- actividades" · "ingreso a racks y guardado a góndola, todo eso es trabajo en racks y debería contar".
-- v23.66 — gv_monitor_horas_operario_dia:
--  (1) Hs MOV suma también el trabajo en racks: RKB (Bajar de racks) e IRT (Ingreso a racks), tramos
--      cerrados que emite el front con ts_inicio = apertura del módulo.
--  (2) HOY cuenta la tarea ABIERTA hasta ahora (antes sólo lo cerrado: Farias con el armado de E30A
--      abierto desde las 11:29 no sumaba). Por operario: la tarea abierta más reciente (EP, AP,
--      toggle, MGI, RKI, IRI) sin su cierre, sin FJ posterior y de menos de 12 h, desde su inicio hasta
--      now(), MENOS los tiempos muertos que caen adentro (el baño abierto también); el muerto abierto
--      (AT/PB/Limp/PC/CT) y el permiso suman a no productivas. Días pasados: igual que antes.
-- Se aplica sobre pg_get_functiondef (idempotente; raise si un texto no matchea).
do $do$
declare d text; n text;
begin
  d := pg_get_functiondef('public.gv_monitor_horas_operario_dia(date)'::regprocedure);
  if d like '%v23.66-abiertas%' then raise notice 'ya aplicada'; return; end if;
  n := d;
  -- (1) mov
  n := replace(n, $r$filter (where e.opcion in ('MG','RT','RI','EI'))$r$,
                  $r$filter (where e.opcion in ('MG','RT','RI','EI','RKB','IRT'))$r$);
  if n = d then raise exception 'no matcheó el balde mov'; end if; d := n;
  -- (2a) aperturas sin cierre (sólo hoy) — va antes de muerto_raw
  n := replace(n, $r$muerto_raw as (
  select b.legajo, b.ts_inicio as ini, b.ts_cliente as fin
    from base b
   where b.opcion in ('AT','PB','Limp','PC','CT')
     and b.ts_inicio is not null
     and b.ts_cliente > b.ts_inicio
     and b.ts_cliente - b.ts_inicio <= interval '8 hours'
),$r$, $r$abre as (   -- v23.66-abiertas: aperturas de HOY (EP/AP/toggles/MGI/RKI/IRI) sin su cierre
  select b.legajo, b.tanda, b.ts_cliente as ini,
         case b.opcion when 'MGI' then 'MG' when 'RKI' then 'RKB' when 'IRI' then 'IRT' else b.opcion end as k
    from base b
   where p_dia = (now() at time zone 'America/Argentina/Buenos_Aires')::date
     and b.ts_inicio is null
     and b.opcion in ('EP','AP','MGI','RKI','IRI','CR','RR','CC','RT','MG','RI','EI','AT','PB','Limp','PC','Perm','CT')
),
abierta as (
  select a.* from abre a
   where now() - a.ini < interval '12 hours'
     and not exists (
       select 1 from base c
        where c.legajo = a.legajo and c.ts_cliente > a.ini
          and (   (a.k = 'EP' and c.opcion = 'TP'  and (c.tanda = '' or c.tanda = a.tanda))
               or (a.k = 'AP' and c.opcion = 'TAP' and (c.tanda = '' or c.tanda = a.tanda))
               or (a.k = 'MG' and c.opcion in ('MG','MGC'))
               or (a.k not in ('EP','AP','MG') and c.opcion = a.k and c.ts_inicio is not null)
               or c.opcion = 'FJ'))
),
muerto_raw as (
  select b.legajo, b.ts_inicio as ini, b.ts_cliente as fin
    from base b
   where b.opcion in ('AT','PB','Limp','PC','CT')
     and b.ts_inicio is not null
     and b.ts_cliente > b.ts_inicio
     and b.ts_cliente - b.ts_inicio <= interval '8 hours'
  union all   -- v23.66: el tiempo muerto ABIERTO (está en el baño ahora) también se resta
  select x.legajo, x.ini, now() from abierta x where x.k in ('AT','PB','Limp','PC','CT')
),$r$);
  if n = d then raise exception 'no matcheó muerto_raw'; end if; d := n;
  -- (2b) cuánto suma lo abierto — va antes de legajos
  n := replace(n, $r$legajos as (select b.legajo from base b group by b.legajo)$r$,
$r$ab_tr as (select distinct on (x.legajo) x.legajo, x.k, x.ini from abierta x
            where x.k not in ('AT','PB','Limp','PC','CT','Perm') order by x.legajo, x.ini desc),
ab_no as (select distinct on (x.legajo) x.legajo, x.k, x.ini from abierta x
            where x.k in ('AT','PB','Limp','PC','CT','Perm') order by x.legajo, x.ini desc),
ab_s as (
  select t.legajo, case when t.k in ('EP','AP','CC','CR','RR') then 'prod' else 'mov' end as balde,
         greatest(0, extract(epoch from (now() - t.ini)) - coalesce((
           select sum(extract(epoch from (least(now(), m.fin) - greatest(t.ini, m.ini))))
             from muerto m where m.legajo = t.legajo and m.fin > t.ini and m.ini < now()), 0)) as s
    from ab_tr t
  union all
  select n2.legajo, 'noprod', greatest(0, extract(epoch from (now() - n2.ini))) from ab_no n2
),
ab_ag as (select a.legajo, sum(a.s) filter (where a.balde = 'prod') as prod_s,
                 sum(a.s) filter (where a.balde = 'mov') as mov_s,
                 sum(a.s) filter (where a.balde = 'noprod') as no_s
            from ab_s a group by a.legajo),
legajos as (select b.legajo from base b group by b.legajo)$r$);
  if n = d then raise exception 'no matcheó legajos'; end if; d := n;
  -- (2c) sumarlo a los baldes
  n := replace(n, $r$               + coalesce(b.prod_otros_s,0)) / 3600.0)::numeric, 2),
       round((coalesce(b.mov_s, 0) / 3600.0)::numeric, 2),
       round((coalesce(b.noprod_s, 0) / 3600.0)::numeric, 2),$r$,
$r$               + coalesce(b.prod_otros_s,0) + coalesce(ab.prod_s,0)) / 3600.0)::numeric, 2),
       round(((coalesce(b.mov_s, 0) + coalesce(ab.mov_s, 0)) / 3600.0)::numeric, 2),
       round(((coalesce(b.noprod_s, 0) + coalesce(ab.no_s, 0)) / 3600.0)::numeric, 2),$r$);
  if n = d then raise exception 'no matcheó los baldes del select'; end if; d := n;
  n := replace(n, $r$  left join baldes  b on b.legajo = l.legajo$r$,
                  $r$  left join baldes  b on b.legajo = l.legajo
  left join ab_ag  ab on ab.legajo = l.legajo$r$);
  if n = d then raise exception 'no matcheó el join de baldes'; end if; d := n;
  execute d;
end $do$;
-- centinela 96: la lista de MOV ahora incluye el trabajo en racks
update public."GV_Reglas_Centinela"
   set patron = $p$in \('MG','RT','RI','EI','RKB','IRT'\)$p$,
       regla  = 'Hs MOVIMIENTO son MG/RT/RI/EI + trabajo en racks (RKB bajar de racks, IRT ingreso a racks; Luis v23.66). Baño, limpieza, timbre, comida, conteo y permiso NO son movimiento: van a no productivas.'
 where id = 96;
insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
select 'gv_monitor_horas_operario_dia', 'funcion', 'ab_ag', 'Hoy cuenta la tarea ABIERTA hasta ahora (la más reciente sin cierre ni FJ, < 12 h), menos los tiempos muertos adentro; el muerto abierto va a no productivas.', 'Luis', 'v23.66'
where not exists (select 1 from public."GV_Reglas_Centinela" where objeto = 'gv_monitor_horas_operario_dia' and patron = 'ab_ag');
