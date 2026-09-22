-- ═══════════════════════════════════════════════════════════════════════════
-- v21.17 / v21.18 — Horas por operario del día, clasificadas
--                   (pedido de Damián, 22/09, via Marianela)
--
-- El monitor de la TV mostraba m³ pickeados y armados del día, pero NADA por
-- operario: la tabla "Mts3 x Hora" se había dejado afuera a propósito porque
-- dependía de `computeClosureDur` (index.html), la parte más pesada del cálculo.
-- Damián pidió el otro corte: cuántas horas puso cada uno y EN QUÉ.
--
-- ⚠ LA CLASIFICACIÓN VIVE ACÁ, NO EN EL FRONT. Es una regla de negocio (qué
--   cuenta como hora productiva), así que va al backend — protocolo del repo.
--
-- ⚠ Y CORRIGE UNA MEZCLA QUE YA ESTABA: `MOV_TOGGLE_CODES` de index.html era
--   {MG, RI, EI, RT, AT, PB, Limp} — o sea que "Paré Baño" y "Limpieza"
--   contaban como MOVIMIENTO de mercadería. Acá van separados, y en la v21.18
--   `index.html` se alineó con esto mismo:
--
--     PRODUCTIVAS  TP  TAP  CC  CR  RR       picking, armado, carga camión, remitos
--     MOVIMIENTO   MG  RT   RI  EI           guardado a góndola, recepción, insumos
--     NO PRODUCT.  AT  PB   Limp PC CT Perm  timbre, baño, limpieza, comida, conteo, permiso
--
--   Un código que no esté en ninguna de las tres NO suma a ningún balde
--   (PKC, CCN, TAL… no tienen duración).
--
-- ⚠ v21.18 — EL TIEMPO MUERTO SE RESTA de la tarea que lo contiene, que es la
--   regla de Luis del 16/09 (v19.07, problema 349): *"si arma 1 h, va al baño
--   10 min y arma 50 min más, debería ser 1 h 50 de armado y 10 de baño, cada
--   uno contado individual"*. Sin esto la TV y el monitor grande daban números
--   distintos para el mismo día. Medido con el ejemplo de Luis, en una
--   transacción abortada: **armado 169,8 min · no productivas 10,2 min**, o sea
--   los mismos 170 y 10 que verifica `tests/muerto-neteado.cjs` sobre
--   `fetchMonitorDayStats`.
--
-- ⚠ El tiempo se acredita UNA vez por tanda (≡ index.html v12.97): si una
--   tanda se cerró dos veces por error, las horas no se cuentan dos veces.
-- ⚠ `LT` (llegada tarde) es tiempo NO trabajado: se excluye (≡ index.html).
-- ⚠ Legajos 0 y 1 son prueba/basura (regla del CLAUDE.md).
--
-- ⚠⚠ LOS BALDES PUEDEN SOLAPARSE Y SU SUMA PASARSE DE `hs_total`. `CR` y `RR`
--    son toggles que sobreviven abiertos mientras el operario hace otra cosa
--    (SURVIVING_TOGGLES). Medido el 22/09 con el legajo 104: RR 08:42→11:43
--    corriendo en paralelo con RT, AT y dos MG. NO es un error de la vista: es
--    lo que pasó. Por eso el front saca el "% productivas" sobre el tiempo
--    MEDIDO (prod+mov+noprod) y no sobre la jornada, que daría más de 100 %.
-- ═══════════════════════════════════════════════════════════════════════════

create or replace view public.gv_monitor_horas_operario as
with dia as (
  select (now() at time zone 'America/Argentina/Buenos_Aires')::date as d
),
base as (
  select r.legajo::text                        as legajo,
         r.opcion,
         upper(btrim(coalesce(r.texto, '')))   as tanda,
         r.ts_inicio, r.ts_cliente
    from public."Registros_Produccion_Virgilio" r, dia
   where (r.ts_cliente at time zone 'America/Argentina/Buenos_Aires')::date = dia.d
     and coalesce(btrim(r.legajo::text), '') not in ('', '0', '1')
     and r.opcion <> 'LT'
),
/* Arranque del día de cada operario = su primer evento. Todas las duraciones se
   recortan contra él: una tarea que quedó abierta AYER y se cierra hoy sólo
   aporta las horas de HOY. Sin ese recorte, un TP que cierra el EP del viernes
   le metía el fin de semana entero al lunes. */
inicio as (select legajo, min(ts_cliente) as arranque from base group by legajo),
ev0 as (select b.*, i.arranque from base b join inicio i on i.legajo = b.legajo),
/* Los ratos de tiempo muerto del día, por operario. `DEAD_TIME_CODES` de
   index.html: mientras están abiertos BLOQUEAN todo, así que no se pisan entre
   sí y sumar los solapes no cuenta nada dos veces. */
muerto as (
  select legajo, greatest(ts_inicio, arranque) as ini, ts_cliente as fin
    from ev0
   where opcion in ('AT','PB','Limp','PC','CT')
     and ts_inicio is not null
     and ts_cliente > greatest(ts_inicio, arranque)
),
ev as (
  select e.*,
         case when e.ts_inicio is null then null else greatest(0,
           extract(epoch from (e.ts_cliente - greatest(e.ts_inicio, e.arranque)))
           /* El descuento va SÓLO en las productivas: el baño que pasó adentro
              de un armado no es armado. A los toggles de movimiento no se les
              resta nada — los de tiempo muerto los bloquean, así que no pueden
              solaparse. Y a los de tiempo muerto tampoco, o se restarían a sí
              mismos. */
           - case when e.opcion in ('TP','TAP','CC','CR','RR') then coalesce((
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
/* Picking y armado: una fila por (legajo, tanda) para no contar dos veces la
   misma tanda cerrada dos veces. */
pick as (select legajo, tanda, max(dur_s) as dur_s from evok
          where opcion = 'TP' and dur_s is not null and tanda <> '' group by legajo, tanda),
arm  as (select legajo, tanda, max(dur_s) as dur_s from evok
          where opcion = 'TAP' and dur_s is not null and tanda <> '' group by legajo, tanda),
pick_ag as (select legajo, count(*) as tandas, sum(dur_s) as dur_s from pick group by legajo),
arm_ag  as (select legajo, count(*) as tandas, sum(dur_s) as dur_s from arm  group by legajo),
/* El resto de los baldes: acá sí cuenta cada cierre (un operario puede ir tres
   veces al baño y las tres suman). */
baldes as (
  select legajo,
         sum(dur_s) filter (where opcion in ('CC','CR','RR'))                    as prod_otros_s,
         sum(dur_s) filter (where opcion in ('MG','RT','RI','EI'))               as mov_s,
         sum(dur_s) filter (where opcion in ('AT','PB','Limp','PC','CT','Perm')) as noprod_s
    from evok where dur_s is not null group by legajo
),
jornada as (
  select legajo, min(arranque) as primer,
         max(ts_cliente) filter (where opcion = 'FJ') as fj,
         max(ts_cliente)                              as ultimo
    from evok group by legajo
),
legajos as (select legajo from evok group by legajo)
select l.legajo,
       coalesce(nullif(btrim(e."Empleado"), ''), 'Leg ' || l.legajo)        as nombre,
       (select d from dia)                                                  as dia,
       coalesce(p.tandas, 0)                                                as tandas_pick,
       round((coalesce(p.dur_s, 0) / 3600.0)::numeric, 2)                   as hs_pick,
       case when coalesce(p.tandas, 0) = 0 then 0
            else round((p.dur_s / 3600.0 / p.tandas)::numeric, 2) end       as prom_hs_pick,
       coalesce(a.tandas, 0)                                                as tandas_arm,
       round((coalesce(a.dur_s, 0) / 3600.0)::numeric, 2)                   as hs_arm,
       case when coalesce(a.tandas, 0) = 0 then 0
            else round((a.dur_s / 3600.0 / a.tandas)::numeric, 2) end       as prom_hs_arm,
       round(((coalesce(p.dur_s,0) + coalesce(a.dur_s,0)
               + coalesce(b.prod_otros_s,0)) / 3600.0)::numeric, 2)         as hs_prod,
       round((coalesce(b.mov_s, 0) / 3600.0)::numeric, 2)                   as hs_mov,
       round((coalesce(b.noprod_s, 0) / 3600.0)::numeric, 2)                as hs_noprod,
       /* Sin FJ la jornada sigue abierta, pero NO se deja correr hasta
          medianoche: se topea en la hora de salida del empleado (fallback
          17:00, igual que `durLaboralMs`). Si siguió registrando después de esa
          hora manda su último evento, así nunca infla y el que se queda de más
          se ve igual. */
       round((extract(epoch from (
              coalesce(j.fj, greatest(j.ultimo, least(now(),
                ((select d from dia) + coalesce(nullif(btrim(e."hora_salida"::text),'')::time,
                                                time '17:00'))
                  at time zone 'America/Argentina/Buenos_Aires')))
              - j.primer)) / 3600.0)::numeric, 2)                           as hs_total,
       (j.fj is null)                                                       as en_jornada
  from legajos l
  left join pick_ag p on p.legajo = l.legajo
  left join arm_ag  a on a.legajo = l.legajo
  left join baldes  b on b.legajo = l.legajo
  left join jornada j on j.legajo = l.legajo
  left join public."Empleados" e on e."Legajo"::text = l.legajo
 order by (coalesce(p.dur_s,0) + coalesce(a.dur_s,0)) desc, nombre;

alter view public.gv_monitor_horas_operario set (security_invoker = true);
grant select on public.gv_monitor_horas_operario to anon, authenticated;

-- ── Centinelas: la clasificación no se puede perder en un CREATE OR REPLACE ──
-- ⚠ Los patrones van escritos como los NORMALIZA `pg_get_viewdef`, no como se
--    escriben acá arriba: un `in ('MG','RT',…)` se guarda como
--    `= ANY (ARRAY['MG'::text, …])`. Escritos "como uno los tipeó", los tres
--    centinelas arrancan EN ROJO el día que se crean (pasó, y por eso está acá).
insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
values
 ('gv_monitor_horas_operario','vista',
  'ARRAY\[''MG''::text, ''RT''::text, ''RI''::text, ''EI''::text\]',
  'Hs MOVIMIENTO son SOLO MG/RT/RI/EI. Bano, limpieza, timbre, comida, conteo y permiso NO son movimiento de mercaderia: van a no productivas (el MOV_TOGGLE_CODES de index.html los mezclaba).',
  'Damian (via Marianela)','v21.17'),
 ('gv_monitor_horas_operario','vista',
  'ARRAY\[''AT''::text, ''PB''::text, ''Limp''::text, ''PC''::text, ''CT''::text, ''Perm''::text\]',
  'Hs NO PRODUCTIVAS = timbre, bano, limpieza, comida, conteo y permiso de salida.',
  'Damian (via Marianela)','v21.17'),
 ('gv_monitor_horas_operario','vista','GROUP BY evok\.legajo, evok\.tanda',
  'El tiempo de picking y de armado se acredita UNA vez por tanda: una tanda cerrada dos veces por error no puede contar las horas dos veces (= index.html v12.97).',
  'Damian (via Marianela)','v21.17'),
 ('gv_monitor_horas_operario','vista','opcion <> ''LT''',
  'La llegada tarde (LT) es tiempo NO trabajado y no entra en ningun balde de horas (= index.html fetchMonitorDayStats).',
  'Damian (via Marianela)','v21.17'),
 ('gv_monitor_horas_operario','vista','muerto',
  'El tiempo muerto (AT/PB/Limp/PC/CT) se RESTA de las horas productivas que lo contienen: si arma 1 h, va al bano 10 min y arma 50 min mas, son 1 h 50 de armado y 10 de bano, cada uno contado individual (regla de Luis, v19.07 = computeClosureDur de index.html).',
  'Luis (v19.07) / Damian','v21.18');

-- ── Chequeos ────────────────────────────────────────────────────────────────
--   select * from public.gv_reglas_perdidas;             -- vacia = todo bien
--   select * from public.gv_monitor_horas_operario;      -- las horas de hoy
--   -- y que la anon la vea IGUAL que postgres (trampa de la v20.45):
--   set local role anon; select count(*) from public.gv_monitor_horas_operario;
--
-- El ejemplo de Luis, PROBADO de verdad y sin dejar nada: el `raise` aborta la
-- transaccion, asi que los eventos de prueba NO quedan. Tiene que dar
-- armado 169,8 min (110 + 60) y no productivas 10,2 min.
--
-- do $$
-- declare d date := (now() at time zone 'America/Argentina/Buenos_Aires')::date;
--         v_arm numeric; v_no numeric; v_mov numeric;
-- begin
--   insert into public."Registros_Produccion_Virgilio"(legajo,opcion,descripcion,texto,ts_cliente,ts_inicio,client_id) values
--    ('999','AP','prueba','Z01A',(d+time '09:00') at time zone 'America/Argentina/Buenos_Aires',null,'__PRUEBA_HS_1__'),
--    ('999','PB','prueba','',    (d+time '10:10') at time zone 'America/Argentina/Buenos_Aires',(d+time '10:00') at time zone 'America/Argentina/Buenos_Aires','__PRUEBA_HS_2__'),
--    ('999','TAP','prueba','Z01A',(d+time '11:00') at time zone 'America/Argentina/Buenos_Aires',(d+time '09:00') at time zone 'America/Argentina/Buenos_Aires','__PRUEBA_HS_3__'),
--    ('999','AP','prueba','Z01B',(d+time '11:05') at time zone 'America/Argentina/Buenos_Aires',null,'__PRUEBA_HS_4__'),
--    ('999','TAP','prueba','Z01B',(d+time '12:05') at time zone 'America/Argentina/Buenos_Aires',(d+time '11:05') at time zone 'America/Argentina/Buenos_Aires','__PRUEBA_HS_5__');
--   select hs_arm, hs_noprod, hs_mov into v_arm, v_no, v_mov
--     from public.gv_monitor_horas_operario where legajo = '999';
--   raise exception 'PRUEBA-> armado_min=% noprod_min=% mov_min=%',
--     round(v_arm*60,1), round(v_no*60,1), round(v_mov*60,1);
-- end $$;

-- Rollback: drop view public.gv_monitor_horas_operario;
--           delete from public."GV_Reglas_Centinela" where objeto = 'gv_monitor_horas_operario';
