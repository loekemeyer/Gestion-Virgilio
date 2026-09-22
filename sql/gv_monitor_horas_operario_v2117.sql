-- ═══════════════════════════════════════════════════════════════════════════
-- v21.17 → v21.20 — Horas por operario del día, clasificadas
--                   (pedido de Damián, 22/09, via Marianela)
--
-- El monitor de la TV mostraba m³ pickeados y armados del día, pero NADA por
-- operario. Damián pidió el otro corte: cuántas horas puso cada uno y EN QUÉ.
--
-- ⚠ LA CLASIFICACIÓN VIVE ACÁ, NO EN EL FRONT. Es una regla de negocio (qué
--   cuenta como hora productiva), así que va al backend — protocolo del repo.
--
--     PRODUCTIVAS  TP  TAP  CC  CR  RR       picking, armado, carga camión, remitos
--     MOVIMIENTO   MG  RT   RI  EI           guardado a góndola, recepción, insumos
--     NO PRODUCT.  AT  PB   Limp PC CT Perm  timbre, baño, limpieza, comida, conteo, permiso
--
--   Corrige una mezcla que ya estaba: `MOV_TOGGLE_CODES` de index.html era
--   {MG, RI, EI, RT, AT, PB, Limp}, o sea que "Paré Baño" contaba como
--   MOVIMIENTO de mercadería. En la v21.18/19 `index.html` se alineó con esto y
--   le apareció la fila «No prod.» al lado de «Movim.».
--   Un código sin duración (PKC, CCN, TAL…) no suma a ningún balde.
--
-- ⚠ EL TIEMPO MUERTO SE RESTA de la tarea que lo contiene — regla de Luis del
--   16/09 (v19.07, problema 349): *"si arma 1 h, va al baño 10 min y arma 50 min
--   más, son 1 h 50 de armado y 10 de baño, cada uno contado individual"*.
--   **v21.20 (Thomas): también se le resta al MOVIMIENTO.** `PB` y `PC` están en
--   ALWAYS_ALLOWED_CODES, así que se pueden abrir con un RT/RI/EI en curso.
--   Medido sobre 30 días: 4 cierres de 352, 1,36 h de 65,75 (2,1 %).
--   A las NO PRODUCTIVAS no se les resta: se restarían a sí mismas.
--
-- ⚠ El tiempo se acredita UNA vez por tanda (≡ index.html v12.97).
-- ⚠ `LT` (llegada tarde) es tiempo NO trabajado: se excluye (≡ index.html).
-- ⚠ Legajos 0 y 1 son prueba/basura (regla del CLAUDE.md).
--
-- ⚠⚠ LOS BALDES PUEDEN SOLAPARSE Y SU SUMA PASARSE DE `hs_total`. `CR` y `RR`
--    son toggles que sobreviven abiertos mientras el operario hace otra cosa.
--    Medido el 22/09 con el legajo 104: RR 08:42→11:43 en paralelo con RT, AT y
--    dos MG. NO es un error: es lo que pasó. Por eso el front saca el
--    "% productivas" sobre el tiempo MEDIDO (prod+mov+noprod), no sobre la
--    jornada, que daría más de 100 %.
--
-- ⚠ v21.20 — EL CÁLCULO VIVE EN UNA FUNCIÓN CON `p_dia`, y la vista es un
--   envoltorio del día de hoy. Es lo que hace posible comparar contra el monitor
--   grande cualquier día con `tests/tools/monitor-vs-vista.cjs`: con la vista
--   atada a "hoy" no se podía comparar nunca, porque los fixtures son del 15/09.
-- ═══════════════════════════════════════════════════════════════════════════

-- ⚠⚠ v21.21 (Thomas, 22/09) — LAS DOS PANTALLAS DAN EL MISMO NÚMERO, y se elige
--   la regla del MONITOR GRANDE donde diferían. Lo que cambió acá:
--
--   1. UN CIERRE QUE CRUZA LA MEDIANOCHE cuenta también el tramo del día de
--      APERTURA: de la apertura al FJ real de ese día (si lo hay) o a la hora de
--      salida del empleado, más una jornada completa por cada día hábil del
--      medio. Es `computeClosureDur` de index.html, replicado. Antes la vista
--      arrancaba en el primer evento de hoy y perdía ese tramo.
--      ⚠ Desapareció el recorte por `arranque`, que era invención de la v21.17 y
--        además se comía el primer MG del día (un MG no tiene fila de apertura:
--        desde la v7.68 emite una sola fila con la duración adentro). Eso era la
--        diferencia del legajo 94: 2,63 contra 2,33.
--
--   2. LOS TIEMPOS MUERTOS SE MERGEAN ANTES DE RESTAR. Un `PB` adentro de un
--      `Limp` se restaba dos veces. Medido: legajo 277 del 15/09, 3 minutos.
--      Es lo que hace `deadByLeg` en index.html desde la v19.07.
--
--   3. Los FERIADOS son la copia de `FERIADOS_AR` de index.html, NO
--      `GV_Dias_No_Habiles` — esa tabla sólo tiene los días que el dueño cierra
--      el depósito (al 22/09, uno solo) y mueve el conteo de días hábiles de
--      TODA la operación.
--
--   Verificación, día 15/09, 5 operarios × 6 números: **coinciden todos**
--   (`tests/mon-vs-vista.cjs`, que corre en la suite).
--
create or replace function public.gv_monitor_horas_operario_dia(p_dia date)
returns table (
  legajo text, nombre text, dia date,
  tandas_pick bigint, hs_pick numeric, prom_hs_pick numeric,
  tandas_arm  bigint, hs_arm  numeric, prom_hs_arm  numeric,
  hs_prod numeric, hs_mov numeric, hs_noprod numeric, hs_total numeric,
  en_jornada boolean
)
language sql
stable
set search_path = public
as $$
with feriados as (
  /* Espejo de FERIADOS_AR de index.html. NO es `GV_Dias_No_Habiles`: esa tabla
     tiene los días que el dueño CIERRA el depósito (al 22/09, uno solo) y mueve
     el conteo de días hábiles de toda la operación. Si las dos listas se
     desfasan, lo caza `tests/mon-vs-vista.cjs`. */
  select unnest(array['2026-01-01','2026-02-16','2026-02-17','2026-03-24','2026-04-02',
                      '2026-04-03','2026-05-01','2026-05-25','2026-06-15','2026-06-20',
                      '2026-07-09','2026-08-17','2026-10-12','2026-11-23','2026-12-08',
                      '2026-12-25']::date[]) as d
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
/* El FJ del día ANTERIOR, que es lo que el monitor grande usa para cerrar el
   tramo del día de apertura (`fjPrevByLegajo`). Si el cierre abrió hace más de
   un día, no matchea y manda la hora de salida — igual que allá. */
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
/* ── Tiempos muertos, MERGEADOS ────────────────────────────────────────────
   ⚠ El merge no es un detalle: un `PB` que cae adentro de un `Limp` se restaba
   DOS VECES. Medido el 15/09 con el legajo 277: 3 minutos. Es lo mismo que hace
   `deadByLeg` en index.html desde la v19.07. */
muerto_raw as (
  select b.legajo, b.ts_inicio as ini, b.ts_cliente as fin
    from base b
   where b.opcion in ('AT','PB','Limp','PC','CT')
     and b.ts_inicio is not null
     and b.ts_cliente > b.ts_inicio
     and b.ts_cliente - b.ts_inicio <= interval '8 hours'   -- ≡ el guard de index.html
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
    left join emp e       on e.legajo   = b.legajo
    left join fj_prev fp  on fp.legajo  = b.legajo
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
         /* Días hábiles ESTRICTAMENTE entre apertura y cierre: jornada completa
            cada uno. Es raro, pero existe (una tanda abierta el viernes). */
         (select count(*) from generate_series(t.dia_ini + 1, t.dia_fin - 1, interval '1 day') g(d)
           where extract(isodow from g.d) < 6
             and not exists (select 1 from feriados f where f.d = g.d::date)) as dias_medio
    from tramos t
),
dur as (
  select c.*,
         case when c.dia_ini = c.dia_fin then c.ts_cliente else least(c.fj_open, c.ts_cliente) end as fin_open,
         case when c.dia_ini = c.dia_fin then greatest(0, extract(epoch from (c.ts_cliente - c.ts_inicio)))
              else greatest(0, extract(epoch from (least(c.fj_open, c.ts_cliente) - c.ts_inicio))) end as open_s,
         case when c.dia_ini = c.dia_fin then 0
              else greatest(0, extract(epoch from (c.ts_cliente - c.close_start))) end as close_s,
         case when c.dia_ini = c.dia_fin then 0
              else c.dias_medio * greatest(0, extract(epoch from (c.h_sal - c.h_ent))) end as medio_s
    from calc c
),
neteo as (
  select d.*,
         /* A las NO PRODUCTIVAS no se les resta nada: se restarían a sí mismas. */
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
/* Una fila por (legajo, tanda): el tiempo se acredita UNA vez por tanda aunque
   se la haya cerrado dos veces por error (≡ index.html v12.97). */
pick as (select e.legajo, e.tanda, max(e.dur_s) as dur_s from evok e
          where e.opcion = 'TP' and e.tanda <> '' group by e.legajo, e.tanda),
arm  as (select e.legajo, e.tanda, max(e.dur_s) as dur_s from evok e
          where e.opcion = 'TAP' and e.tanda <> '' group by e.legajo, e.tanda),
pick_ag as (select p.legajo, count(*) as tandas, sum(p.dur_s) as dur_s from pick p group by p.legajo),
arm_ag  as (select a.legajo, count(*) as tandas, sum(a.dur_s) as dur_s from arm  a group by a.legajo),
baldes as (
  select e.legajo,
         sum(e.dur_s) filter (where e.opcion in ('CC','CR','RR'))                    as prod_otros_s,
         sum(e.dur_s) filter (where e.opcion in ('MG','RT','RI','EI'))               as mov_s,
         sum(e.dur_s) filter (where e.opcion in ('AT','PB','Limp','PC','CT','Perm')) as noprod_s
    from evok e group by e.legajo
),
jornada as (
  select b.legajo, min(b.ts_cliente) as primer,
         max(b.ts_cliente) filter (where b.opcion = 'FJ') as fj,
         max(b.ts_cliente)                                as ultimo
    from base b group by b.legajo
),
legajos as (select b.legajo from base b group by b.legajo)
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
               + coalesce(b.prod_otros_s,0)) / 3600.0)::numeric, 2),
       round((coalesce(b.mov_s, 0) / 3600.0)::numeric, 2),
       round((coalesce(b.noprod_s, 0) / 3600.0)::numeric, 2),
       /* Sin FJ la jornada sigue abierta, pero NO se deja correr hasta
          medianoche: se topea en la hora de salida del empleado (fallback
          17:00). Si siguió registrando después de esa hora manda su último
          evento, así nunca infla. */
       round((extract(epoch from (
              coalesce(j.fj, greatest(j.ultimo, least(now(),
                (p_dia + coalesce(e2.h_sal, time '17:00')) at time zone 'America/Argentina/Buenos_Aires')))
              - j.primer)) / 3600.0)::numeric, 2),
       (j.fj is null)
  from legajos l
  left join pick_ag p on p.legajo = l.legajo
  left join arm_ag  a on a.legajo = l.legajo
  left join baldes  b on b.legajo = l.legajo
  left join jornada j on j.legajo = l.legajo
  left join emp e2 on e2.legajo = l.legajo
 order by (coalesce(p.dur_s,0) + coalesce(a.dur_s,0)) desc, 2;
$$;

grant execute on function public.gv_monitor_horas_operario_dia(date) to anon, authenticated;

-- La vista es SÓLO el envoltorio del día de hoy: es lo que lee monitor/tv.html.
create or replace view public.gv_monitor_horas_operario as
  select * from public.gv_monitor_horas_operario_dia(
    (now() at time zone 'America/Argentina/Buenos_Aires')::date);
alter view public.gv_monitor_horas_operario set (security_invoker = true);
grant select on public.gv_monitor_horas_operario to anon, authenticated;

-- ── Centinelas ──────────────────────────────────────────────────────────────
-- ⚠ Los patrones de una FUNCIÓN se comparan contra `prosrc`, que es el cuerpo
--    TAL CUAL se escribió. Los de una VISTA, contra `pg_get_viewdef`, que
--    NORMALIZA (`in (…)` se guarda como `= ANY (ARRAY[…])`). No son los mismos
--    patrones: escribirlos "como uno los tipeó" en una vista deja los centinelas
--    en rojo el día que se crean (pasó, y por eso está escrito acá).
insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
values
 ('gv_monitor_horas_operario_dia','funcion','in \(''MG'',''RT'',''RI'',''EI''\)',
  'Hs MOVIMIENTO son SOLO MG/RT/RI/EI. Bano, limpieza, timbre, comida, conteo y permiso NO son movimiento de mercaderia: van a no productivas (el MOV_TOGGLE_CODES de index.html los mezclaba).',
  'Damian (via Marianela)','v21.20'),
 ('gv_monitor_horas_operario_dia','funcion','in \(''AT'',''PB'',''Limp'',''PC'',''CT'',''Perm''\)',
  'Hs NO PRODUCTIVAS = timbre, bano, limpieza, comida, conteo y permiso de salida.',
  'Damian (via Marianela)','v21.20'),
 ('gv_monitor_horas_operario_dia','funcion','group by e\.legajo, e\.tanda',
  'El tiempo de picking y de armado se acredita UNA vez por tanda: una tanda cerrada dos veces por error no puede contar las horas dos veces (= index.html v12.97).',
  'Damian (via Marianela)','v21.20'),
 ('gv_monitor_horas_operario_dia','funcion','opcion <> ''LT''',
  'La llegada tarde (LT) es tiempo NO trabajado y no entra en ningun balde de horas (= index.html fetchMonitorDayStats).',
  'Damian (via Marianela)','v21.20'),
 ('gv_monitor_horas_operario_dia','funcion','muerto_open_s',
  'El tiempo muerto (AT/PB/Limp/PC/CT) se RESTA de la tarea que lo contiene, productiva o de MOVIMIENTO (regla de Luis v19.07, extendida a MG/RT/RI/EI por Thomas en la v21.20). A las no productivas no se les resta: se restarian a si mismas.',
  'Luis (v19.07) / Thomas','v21.21'),
 ('gv_monitor_horas_operario_dia','funcion','muerto_grp',
  'Los tiempos muertos se MERGEAN antes de restar: un PB adentro de un Limp restaria dos veces (paso el 15/09 con el legajo 277: 3 min de mas). Es lo mismo que hace deadByLeg en index.html.',
  'Thomas','v21.21'),
 ('gv_monitor_horas_operario_dia','funcion','fj_open',
  'Un cierre que CRUZA LA MEDIANOCHE cuenta tambien el tramo del dia de apertura (de la apertura al FJ real de ese dia, o a la hora de salida): es la regla del MONITOR GRANDE (computeClosureDur), elegida por Thomas el 22/09 para que las dos pantallas den lo mismo.',
  'Thomas','v21.21'),
 ('gv_monitor_horas_operario','vista','gv_monitor_horas_operario_dia',
  'La vista es un envoltorio: el calculo vive en gv_monitor_horas_operario_dia(p_dia) para poder pedir OTRO dia y comparar contra el monitor grande (tests/tools/monitor-vs-vista.cjs). Si alguien le vuelve a meter el calculo adentro, quedan dos implementaciones otra vez.',
  'Thomas','v21.20');

-- ── Chequeos ────────────────────────────────────────────────────────────────
--   select * from public.gv_reglas_perdidas;             -- vacia = todo bien
--   select * from public.gv_monitor_horas_operario;      -- las horas de hoy
--   select * from public.gv_monitor_horas_operario_dia(date '2026-09-15');
--   -- y que la anon la vea IGUAL que postgres (trampa de la v20.45):
--   set local role anon; select count(*) from public.gv_monitor_horas_operario;
--
-- Los dos ejemplos de Luis, PROBADOS de verdad y sin dejar nada: el `raise`
-- aborta la transaccion, asi que los eventos de prueba NO quedan.
--   (A) armado con un bano adentro  -> armado 169,8 min · no productivas 10,2 min
--   (B) recepcion con un bano adentro -> movimiento 109,8 min · no productivas 10,2 min
--
-- do $$
-- declare d date := (now() at time zone 'America/Argentina/Buenos_Aires')::date;
--         v_mov numeric; v_no numeric;
-- begin
--   insert into public."Registros_Produccion_Virgilio"(legajo,opcion,descripcion,texto,ts_cliente,ts_inicio,client_id) values
--    ('998','RT','prueba','',  (d+time '09:00') at time zone 'America/Argentina/Buenos_Aires', null,'__PRUEBA_MOV_0__'),
--    ('998','PB','prueba','',  (d+time '10:00') at time zone 'America/Argentina/Buenos_Aires', null,'__PRUEBA_MOV_1__'),
--    ('998','PB','prueba','',  (d+time '10:10') at time zone 'America/Argentina/Buenos_Aires',(d+time '10:00') at time zone 'America/Argentina/Buenos_Aires','__PRUEBA_MOV_2__'),
--    ('998','RT','prueba','66',(d+time '11:00') at time zone 'America/Argentina/Buenos_Aires',(d+time '09:00') at time zone 'America/Argentina/Buenos_Aires','__PRUEBA_MOV_3__');
--   select hs_mov, hs_noprod into v_mov, v_no
--     from public.gv_monitor_horas_operario where legajo = '998';
--   raise exception 'PRUEBA-> mov_min=% noprod_min=%', round(v_mov*60,1), round(v_no*60,1);
-- end $$;
--
-- ⚠ El fixture TIENE que traer los eventos de APERTURA (el `RT` sin ts_inicio):
--    sin ellos el `arranque` cae en el primer CIERRE y la prueba da cualquier
--    cosa (dio 49,8 y 0,0 el primer intento).
--
-- Rollback: drop view public.gv_monitor_horas_operario;
--           drop function public.gv_monitor_horas_operario_dia(date);
--           delete from public."GV_Reglas_Centinela"
--            where objeto in ('gv_monitor_horas_operario','gv_monitor_horas_operario_dia');
