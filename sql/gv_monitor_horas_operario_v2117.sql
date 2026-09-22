-- ═══════════════════════════════════════════════════════════════════════════
-- v21.17 — Horas por operario del día, clasificadas (pedido de Damián, 22/09)
--
-- El monitor de la TV mostraba m³ pickeados y armados del día, pero NADA por
-- operario: la tabla "Mts3 x Hora" se había dejado afuera a propósito porque
-- dependía de `computeClosureDur` (index.html), la parte más pesada del cálculo.
-- Damián pidió el otro corte: cuántas horas puso cada uno y EN QUÉ.
--
-- ⚠ LA CLASIFICACIÓN VIVE ACÁ, NO EN EL FRONT. Es una regla de negocio (qué
--   cuenta como hora productiva), así que va al backend — protocolo del repo.
--   El monitor grande y la TV leen el mismo número.
--
-- ⚠ Y CORRIGE UNA MEZCLA QUE YA ESTABA: `MOV_TOGGLE_CODES` de index.html es
--   {MG, RI, EI, RT, AT, PB, Limp} — o sea que "Paré Baño" y "Limpieza"
--   contaban como MOVIMIENTO de mercadería. Acá van separados:
--
--     PRODUCTIVAS  TP  TAP  CC  CR  RR       picking, armado, carga camión, remitos
--     MOVIMIENTO   MG  RT   RI  EI           guardado a góndola, recepción, insumos
--     NO PRODUCT.  AT  PB   Limp PC CT Perm  timbre, baño, limpieza, comida, conteo, permiso
--
--   Un código que no esté en ninguna de las tres NO suma a ningún balde
--   (PKC, CCN, TAL… no tienen duración).
--
-- ⚠ El tiempo se acredita UNA vez por tanda (≡ index.html v12.97): si una
--   tanda se cerró dos veces por error, las horas no se cuentan dos veces.
-- ⚠ `LT` (llegada tarde) es tiempo NO trabajado: se excluye (≡ index.html).
-- ⚠ Legajos 0 y 1 son prueba/basura (regla del CLAUDE.md).
--
-- ⚠⚠ LOS BALDES PUEDEN SOLAPARSE Y SU SUMA PASARSE DE `hs_total`. `CR` y `RR`
--    son toggles que sobreviven abiertos mientras el operario hace otra cosa
--    (SURVIVING_TOGGLES). Medido el 22/09 con el legajo 104: RR 08:42→11:43
--    corriendo en paralelo con RT, AT y dos MG → 8,62 h de baldes contra 6,03 h
--    de jornada. NO es un error de la vista: es lo que pasó. Por eso el front
--    saca el "% productivas" sobre el tiempo MEDIDO (prod+mov+noprod) y no
--    sobre la jornada, que daría más de 100 %.
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
ev as (
  select b.*, i.arranque,
         case when b.ts_inicio is null then null
              else greatest(0, extract(epoch from
                   (b.ts_cliente - greatest(b.ts_inicio, i.arranque)))) end as dur_s
    from base b join inicio i on i.legajo = b.legajo
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
  'Damian (via Marianela)','v21.17');

-- Chequeos
--   select * from public.gv_reglas_perdidas;             -- vacia = todo bien
--   select * from public.gv_monitor_horas_operario;      -- las horas de hoy
--   -- y que la anon la vea IGUAL que postgres (trampa de la v20.45):
--   set local role anon; select count(*) from public.gv_monitor_horas_operario;

-- Rollback: drop view public.gv_monitor_horas_operario;
--           delete from public."GV_Reglas_Centinela" where objeto = 'gv_monitor_horas_operario';
