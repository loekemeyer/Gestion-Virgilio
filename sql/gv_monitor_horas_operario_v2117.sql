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
with base as (
  select r.legajo::text as legajo, r.opcion,
         upper(btrim(coalesce(r.texto, ''))) as tanda,
         r.ts_inicio, r.ts_cliente
    from public."Registros_Produccion_Virgilio" r
   where (r.ts_cliente at time zone 'America/Argentina/Buenos_Aires')::date = p_dia
     and coalesce(btrim(r.legajo::text), '') not in ('', '0', '1')
     and r.opcion <> 'LT'
),
/* Arranque del día de cada operario = su primer evento. Todas las duraciones se
   recortan contra él: una tarea que quedó abierta AYER y se cierra hoy sólo
   aporta las horas de HOY.
   ⚠ ACÁ ESTÁ LA DIFERENCIA MEDIDA CONTRA EL MONITOR GRANDE (v21.20): él cuenta
   además el tramo del día de APERTURA, desde que se abrió hasta el fin de esa
   jornada (`businessDurBetweenMs`). Sobre el 15/09 eso son 0,08 h de promedio en
   el legajo 237 y 0,24 h en el 8 — los dos únicos con un cierre que cruzó la
   medianoche. NINGUNA de las dos está "mal": es una decisión pendiente. */
inicio as (select b.legajo, min(b.ts_cliente) as arranque from base b group by b.legajo),
ev0 as (select b.*, i.arranque from base b join inicio i on i.legajo = b.legajo),
muerto as (
  select e.legajo, greatest(e.ts_inicio, e.arranque) as ini, e.ts_cliente as fin
    from ev0 e
   where e.opcion in ('AT','PB','Limp','PC','CT')
     and e.ts_inicio is not null
     and e.ts_cliente > greatest(e.ts_inicio, e.arranque)
),
ev as (
  select e.*,
         case when e.ts_inicio is null then null else greatest(0,
           extract(epoch from (e.ts_cliente - greatest(e.ts_inicio, e.arranque)))
           - case when e.opcion in ('TP','TAP','CC','CR','RR','MG','RT','RI','EI') then coalesce((
               select sum(extract(epoch from (least(e.ts_cliente, m.fin)
                        - greatest(greatest(e.ts_inicio, e.arranque), m.ini))))
                 from muerto m
                where m.legajo = e.legajo
                  and m.fin > greatest(e.ts_inicio, e.arranque)
                  and m.ini < e.ts_cliente), 0) else 0 end) end as dur_s
    from ev0 e
),
/* Un cierre sin `ts_inicio` no es un cierre. El tope de 24 h saca los arrastres
   absurdos (un toggle que quedó abierto y lo cerró el autocierre). */
evok as (select * from ev where dur_s is null or (dur_s > 0 and dur_s < 24 * 3600)),
pick as (select e.legajo, e.tanda, max(e.dur_s) as dur_s from evok e
          where e.opcion = 'TP' and e.dur_s is not null and e.tanda <> '' group by e.legajo, e.tanda),
arm  as (select e.legajo, e.tanda, max(e.dur_s) as dur_s from evok e
          where e.opcion = 'TAP' and e.dur_s is not null and e.tanda <> '' group by e.legajo, e.tanda),
pick_ag as (select p.legajo, count(*) as tandas, sum(p.dur_s) as dur_s from pick p group by p.legajo),
arm_ag  as (select a.legajo, count(*) as tandas, sum(a.dur_s) as dur_s from arm  a group by a.legajo),
baldes as (
  select e.legajo,
         sum(e.dur_s) filter (where e.opcion in ('CC','CR','RR'))                    as prod_otros_s,
         sum(e.dur_s) filter (where e.opcion in ('MG','RT','RI','EI'))               as mov_s,
         sum(e.dur_s) filter (where e.opcion in ('AT','PB','Limp','PC','CT','Perm')) as noprod_s
    from evok e where e.dur_s is not null group by e.legajo
),
jornada as (
  select e.legajo, min(e.arranque) as primer,
         max(e.ts_cliente) filter (where e.opcion = 'FJ') as fj,
         max(e.ts_cliente)                                as ultimo
    from evok e group by e.legajo
),
legajos as (select e.legajo from evok e group by e.legajo)
select l.legajo,
       coalesce(nullif(btrim(e2."Empleado"), ''), 'Leg ' || l.legajo),
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
          17:00, igual que `durLaboralMs`). Si siguió registrando después de esa
          hora manda su último evento, así nunca infla. */
       round((extract(epoch from (
              coalesce(j.fj, greatest(j.ultimo, least(now(),
                (p_dia + coalesce(nullif(btrim(e2."hora_salida"::text),'')::time, time '17:00'))
                  at time zone 'America/Argentina/Buenos_Aires')))
              - j.primer)) / 3600.0)::numeric, 2),
       (j.fj is null)
  from legajos l
  left join pick_ag p on p.legajo = l.legajo
  left join arm_ag  a on a.legajo = l.legajo
  left join baldes  b on b.legajo = l.legajo
  left join jornada j on j.legajo = l.legajo
  left join public."Empleados" e2 on e2."Legajo"::text = l.legajo
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
 ('gv_monitor_horas_operario_dia','funcion','''TP'',''TAP'',''CC'',''CR'',''RR'',''MG'',''RT'',''RI'',''EI''',
  'El tiempo muerto (AT/PB/Limp/PC/CT) se RESTA de la tarea que lo contiene, productiva o de MOVIMIENTO: si arma 1 h, va al bano 10 min y arma 50 min mas, son 1 h 50 de armado y 10 de bano, cada uno contado individual (regla de Luis, v19.07; extendida a MG/RT/RI/EI por Thomas en la v21.20).',
  'Luis (v19.07) / Thomas','v21.20'),
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
