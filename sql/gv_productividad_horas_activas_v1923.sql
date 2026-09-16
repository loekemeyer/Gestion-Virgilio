-- ============================================================================
-- v19.23 (2026-09-16) — LA PRODUCTIVIDAD CUENTA HORAS ACTIVAS, NO HORAS DE RELOJ
--
-- Regla de Luis: *"debería solo contar horas activas. si está 1 hora pickeando
-- algo, termina el día y después de 14 horas comienza el siguiente día y en 30
-- min de trabajo lo cierra, tardó 1:30hs y no 15:30"*.
--
-- El monitor ya lo hacía (`computeClosureDur` en index.html parte el cruce de
-- día y usa la fichada / el FJ reales). El BACKEND no: `valido` exigía MISMO DÍA,
-- así que una tanda cerrada al otro día no contaba 15:30 — contaba **CERO**, y se
-- llevaba puestos sus m³. Medido: 23 de 460 cierres de 40 días cruzan el día (5%).
--
-- Tres cambios, los dos en las dos vistas:
--   1) `valido` ya NO exige mismo día. El tope de 12 h pasa a ser sobre las horas
--      ACTIVAS (720 min), no sobre el reloj: así entra el cierre legítimo de la
--      mañana siguiente y sigue afuera el olvido (C06B: 2.067 h de reloj, 549 h
--      activas → sigue inválido).
--   2) el tope por evento (`cap_min`: TAP 180, TP 120, …) se aplica sobre tiempo
--      ACTIVO, con `gv_fin_activo`. Antes era `ts_inicio + least(reloj, cap)`, que
--      para un cruce de día caía DENTRO del primer día y le contaba el tope
--      entero (2 h) a un trabajo de 55 min.
--   3) la duración de cada isla pasa de `epoch(me - ms)/60` (reloj, con la noche
--      adentro) a `gv_min_activos(legajo, ms, me)`.
--   4) en la semanal, `min_x_armado` y los `t_*` (carga, control, recepción…)
--      pasan de `raw_min` a `act_min` por el mismo motivo.
--
-- ⚠ El camino caliente NO llama a la función: cuando apertura y cierre son del
--   mismo día (437 de 460) se usa la resta directa, inline. La función sólo se
--   evalúa en el 5% que cruza.
--
-- ROLLBACK: `sql/backups/vista_productividad_pre_v1923_20260916.sql` (runnable).
-- Medición e impacto: docs/SUPABASE-GESTION-VIRGILIO.md §3.ij.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1) Las ventanas de jornada: única fuente de verdad del criterio.
-- ---------------------------------------------------------------------------
create or replace function public.gv_jornada_ventanas(
  p_legajo text, p_ini timestamptz, p_fin timestamptz
) returns table (w_s timestamptz, w_e timestamptz)
language plpgsql stable as $$
/* Los TRAMOS TRABAJADOS entre dos instantes, recortados a la jornada del legajo.
   `gv_min_activos` y `gv_fin_activo` se apoyan acá — un solo criterio, un solo lugar.

   Mismo criterio que `computeClosureDur` del monitor (index.html):
     · día de apertura → de p_ini al FJ REAL de ese día (si lo marcó) o a hora_salida.
     · día de cierre   → de la fichada REAL (o el primer evento, o hora_entrada) a p_fin.
     · días del medio  → jornada completa, salteando sábado, domingo y GV_Dias_No_Habiles.
   Fallback 08:00-17:00 si el legajo no tiene horario cargado.

   ⚠ MISMO DÍA sale sin tocar la base: es el 95% de los cierres. */
declare
  v_ent time := null; v_sal time := null;
  d date; d_ini date; d_fin date;
  s timestamptz; e timestamptz; v_aux timestamptz;
  tz text := 'America/Argentina/Buenos_Aires';
begin
  if p_legajo is null or p_ini is null or p_fin is null or p_fin <= p_ini then return; end if;

  d_ini := (p_ini at time zone tz)::date;
  d_fin := (p_fin at time zone tz)::date;
  if d_ini = d_fin then
    w_s := p_ini; w_e := p_fin; return next; return;
  end if;

  select em.hora_entrada, em.hora_salida into v_ent, v_sal
    from public."Empleados" em where em."Legajo"::text = p_legajo limit 1;
  v_ent := coalesce(v_ent, time '08:00');
  v_sal := coalesce(v_sal, time '17:00');
  if v_sal <= v_ent then v_ent := time '08:00'; v_sal := time '17:00'; end if;

  for d in select g::date from generate_series(d_ini, d_fin, interval '1 day') g loop
    -- los días del medio que no se trabajan no cuentan (los extremos sí: el evento los toca)
    if d <> d_ini and d <> d_fin then
      if extract(dow from d) in (0, 6) then continue; end if;
      if exists (select 1 from public."GV_Dias_No_Habiles" h where h.fecha = d) then continue; end if;
    end if;

    s := ((d + v_ent) at time zone tz);
    e := ((d + v_sal) at time zone tz);

    if d = d_ini then
      select max(r.ts_cliente) into v_aux
        from public."Registros_Produccion_Virgilio" r
       where r.legajo = p_legajo and r.opcion = 'FJ'
         and (r.ts_cliente at time zone tz)::date = d;
      if v_aux is not null then e := v_aux; end if;
    end if;

    if d = d_fin then
      select least(
               (select min(f.ts_cliente) from public."Fichadas_Virgilio" f
                 where f.legajo::text = p_legajo
                   and (f.ts_cliente at time zone tz)::date = d),
               (select min(r.ts_cliente) from public."Registros_Produccion_Virgilio" r
                 where r.legajo = p_legajo
                   and (r.ts_cliente at time zone tz)::date = d)
             ) into v_aux;
      if v_aux is not null then s := v_aux; end if;
    end if;

    w_s := greatest(s, p_ini);
    w_e := least(e, p_fin);
    if w_e > w_s then return next; end if;
  end loop;
  return;
end $$;

create or replace function public.gv_min_activos(
  p_legajo text, p_ini timestamptz, p_fin timestamptz
) returns numeric
language sql stable as $$
  -- minutos trabajados de verdad entre los dos instantes (la noche no cuenta)
  select coalesce(sum(extract(epoch from (v.w_e - v.w_s)) / 60.0), 0)
    from public.gv_jornada_ventanas(p_legajo, p_ini, p_fin) v;
$$;

create or replace function public.gv_fin_activo(
  p_legajo text, p_ini timestamptz, p_fin timestamptz, p_cap_min numeric
) returns timestamptz
language plpgsql stable as $$
/* El instante hasta donde hay que contar para acumular p_cap_min minutos ACTIVOS
   desde p_ini. Si en [p_ini, p_fin] nunca se llega al tope, devuelve p_fin. */
declare v record; acc numeric := 0; falta numeric;
begin
  if p_cap_min is null or p_cap_min <= 0 then return p_ini; end if;
  for v in select * from public.gv_jornada_ventanas(p_legajo, p_ini, p_fin) loop
    falta := p_cap_min - acc;
    if extract(epoch from (v.w_e - v.w_s)) / 60.0 >= falta then
      return v.w_s + make_interval(secs => (falta * 60)::double precision);
    end if;
    acc := acc + extract(epoch from (v.w_e - v.w_s)) / 60.0;
  end loop;
  return p_fin;
end $$;

revoke all on function public.gv_jornada_ventanas(text, timestamptz, timestamptz) from public;
revoke all on function public.gv_min_activos(text, timestamptz, timestamptz) from public;
revoke all on function public.gv_fin_activo(text, timestamptz, timestamptz, numeric) from public;
grant execute on function public.gv_jornada_ventanas(text, timestamptz, timestamptz) to anon, authenticated, service_role;
grant execute on function public.gv_min_activos(text, timestamptz, timestamptz) to anon, authenticated, service_role;
grant execute on function public.gv_fin_activo(text, timestamptz, timestamptz, numeric) to anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 2) vista_productividad_diaria
-- ---------------------------------------------------------------------------
create or replace view public.vista_productividad_diaria with (security_invoker = true) as
with ev0 as (
  select coalesce(r.legajo, '?') as legajo,
         r.opcion,
         (coalesce(r.ts_cliente, r.created_at) at time zone 'America/Argentina/Buenos_Aires')::date as dia,
         upper(btrim(r.texto)) as tanda,
         r.ts_inicio,
         r.ts_cliente,
         case r.opcion when 'TAP' then 180 else 120 end as cap_min,
         /* horas ACTIVAS. El mismo día se resuelve inline (95% de los casos, sin
            llamar a la función); sólo el cruce de día paga el cálculo. */
         case when r.ts_inicio is null or r.ts_cliente <= r.ts_inicio then null
              when (r.ts_inicio  at time zone 'America/Argentina/Buenos_Aires')::date
                 = (r.ts_cliente at time zone 'America/Argentina/Buenos_Aires')::date
                   then extract(epoch from (r.ts_cliente - r.ts_inicio)) / 60.0
              else public.gv_min_activos(coalesce(r.legajo, '?'), r.ts_inicio, r.ts_cliente)
         end as act_min
    from public."Registros_Produccion_Virgilio" r
   where coalesce(r.ts_cliente, r.created_at) > now() - interval '40 days'
     and not es_legajo_test(r.legajo)
     and r.opcion in ('TAP', 'TP')
), ev as (
  select ev0.*,
         /* v19.23 — ya NO se exige mismo día: se exige que el tiempo ACTIVO sea
            razonable (≤ 12 h). El cierre de la mañana siguiente entra; el olvido de
            tres meses sigue afuera. */
         (ev0.act_min is not null
          and extract(epoch from (ev0.ts_cliente - ev0.ts_inicio)) >= 60
          and ev0.act_min <= 720) as valido
    from ev0
), dead_raw as (
  select coalesce(r.legajo, '?') as legajo,
         r.ts_inicio as s,
         least(r.ts_cliente,
               r.ts_inicio + (case r.opcion when 'PC' then 90 else 30 end) * interval '1 minute') as e
    from public."Registros_Produccion_Virgilio" r
   where coalesce(r.ts_cliente, r.created_at) > now() - interval '40 days'
     and not es_legajo_test(r.legajo)
     and r.opcion in ('AT', 'PB', 'Limp', 'PC', 'CT')
     and r.ts_inicio is not null and r.ts_cliente > r.ts_inicio
), dead_isl as (
  select y.legajo, y.s, y.e,
         sum(case when y.rmax is null or y.s > y.rmax then 1 else 0 end)
           over (partition by y.legajo order by y.s, y.e) as grp
    from (select dr.legajo, dr.s, dr.e,
                 max(dr.e) over (partition by dr.legajo order by dr.s, dr.e
                                 rows between unbounded preceding and 1 preceding) as rmax
            from dead_raw dr) y
), dead as (
  select legajo, min(s) as s, max(e) as e from dead_isl group by legajo, grp
), evc as (
  select ev.legajo, ev.opcion, ev.dia, ev.tanda, ev.ts_inicio,
         /* v19.23 — el tope se cuenta en tiempo ACTIVO. Inline cuando no cruza el día. */
         case when (ev.ts_inicio  at time zone 'America/Argentina/Buenos_Aires')::date
                 = (ev.ts_cliente at time zone 'America/Argentina/Buenos_Aires')::date
                   then ev.ts_inicio + least(ev.ts_cliente - ev.ts_inicio, ev.cap_min * interval '1 minute')
              else public.gv_fin_activo(ev.legajo, ev.ts_inicio, ev.ts_cliente, ev.cap_min)
         end as e_cap
    from ev where ev.valido
), m3 as (
  select tanda, m3 from public.vista_tanda_m3
), isl as (
  select y.legajo, y.dia, y.opcion, y.tanda, y.s, y.e,
         sum(case when y.rmax is null or y.s > y.rmax then 1 else 0 end)
           over (partition by y.legajo, y.dia, y.opcion, y.tanda order by y.s, y.e) as grp
    from (select evc.legajo, evc.dia, evc.opcion, evc.tanda,
                 evc.ts_inicio as s, evc.e_cap as e,
                 max(evc.e_cap) over (partition by evc.legajo, evc.dia, evc.opcion, evc.tanda
                                      order by evc.ts_inicio, evc.e_cap
                                      rows between unbounded preceding and 1 preceding) as rmax
            from evc) y
), core as (
  select legajo, dia, opcion, tanda, grp, min(s) as ms, max(e) as me
    from isl group by legajo, dia, opcion, tanda, grp
), muerto as (
  select c.legajo, c.dia, c.opcion, c.tanda, c.grp,
         /* ⚠ LEAST/GREATEST IGNORAN NULL: sin el `case`, una isla sin tiempo muerto
            (d.legajo null por el LEFT JOIN) devolvía `least(me, null) = me` y
            restaba la isla entera. v19.07. */
         coalesce(sum(case when d.legajo is null then 0
                           else greatest(0, extract(epoch from (least(c.me, d.e) - greatest(c.ms, d.s))) / 60.0)
                      end), 0) as min_muerto
    from core c
    left join dead d on d.legajo = c.legajo and d.s < c.me and c.ms < d.e
   group by c.legajo, c.dia, c.opcion, c.tanda, c.grp
), efft as (
  select c.legajo, c.dia, c.opcion, c.tanda,
         /* v19.23 — minutos ACTIVOS de la isla, no de reloj. Inline si no cruza el día. */
         sum(greatest(0,
             (case when (c.ms at time zone 'America/Argentina/Buenos_Aires')::date
                      = (c.me at time zone 'America/Argentina/Buenos_Aires')::date
                        then extract(epoch from (c.me - c.ms)) / 60.0
                   else public.gv_min_activos(c.legajo, c.ms, c.me) end)
             - mu.min_muerto)) as eff_min
    from core c
    join muerto mu on mu.legajo = c.legajo and mu.dia = c.dia
                  and mu.opcion = c.opcion and mu.tanda = c.tanda and mu.grp = c.grp
   group by c.legajo, c.dia, c.opcion, c.tanda
), tnd as (
  select e.legajo, e.dia, e.opcion, e.tanda,
         max(m.m3) as m3, bool_or(e.valido) as any_valido,
         coalesce(max(ef.eff_min), 0) as eff_min
    from ev e
    left join m3 m on m.tanda = e.tanda
    left join efft ef on ef.legajo = e.legajo and ef.dia = e.dia
                     and ef.opcion = e.opcion and ef.tanda = e.tanda
   group by e.legajo, e.dia, e.opcion, e.tanda
), tndr as (
  select tnd.*,
         (tnd.m3 is not null and tnd.eff_min > 0
          and (60 * tnd.m3 / tnd.eff_min) > case when tnd.opcion = 'TAP' then 4.0 else 8.0 end) as ritmo_roto
    from tnd
)
select legajo, dia,
       count(*) filter (where opcion = 'TAP') as armadas,
       count(*) filter (where opcion = 'TP')  as pickeadas,
       round(coalesce(sum(m3) filter (where opcion = 'TAP' and any_valido and not ritmo_roto and m3 is not null), 0), 2) as arm_m3,
       round(coalesce(sum(m3) filter (where opcion = 'TP'  and any_valido and not ritmo_roto and m3 is not null), 0), 2) as pick_m3,
       round(coalesce(sum(eff_min) filter (where opcion = 'TAP' and any_valido and not ritmo_roto), 0), 1) as arm_eff_min,
       round(coalesce(sum(eff_min) filter (where opcion = 'TP'  and any_valido and not ritmo_roto), 0), 1) as pick_eff_min,
       round(coalesce(sum(m3) filter (where opcion = 'TAP' and m3 is not null), 0), 2) as arm_m3_tot,
       round(coalesce(sum(m3) filter (where opcion = 'TP'  and m3 is not null), 0), 2) as pick_m3_tot
  from tndr group by legajo, dia;

alter view public.vista_productividad_diaria set (security_invoker = true);

-- ---------------------------------------------------------------------------
-- 3) vista_productividad_semanal
-- ---------------------------------------------------------------------------
create or replace view public.vista_productividad_semanal with (security_invoker = true) as
with ev0 as (
  select coalesce(r.legajo, '?') as legajo,
         r.opcion,
         (coalesce(r.ts_cliente, r.created_at) at time zone 'America/Argentina/Buenos_Aires')::date as dia,
         date_trunc('week', (coalesce(r.ts_cliente, r.created_at) at time zone 'America/Argentina/Buenos_Aires')::date::timestamp) as sem,
         upper(btrim(r.texto)) as tanda,
         r.ts_inicio,
         r.ts_cliente,
         case r.opcion
           when 'TAP' then 180 when 'TP'  then 120
           when 'CC'  then 60  when 'CCN' then 60  when 'CCR' then 60
           when 'CR'  then 30  when 'CRN' then 30
           when 'MG'  then 20  when 'PC'  then 90
           when 'RT'  then 45  when 'RR'  then 45
           when 'RI'  then 30  when 'EI'  then 30
           when 'Limp' then 30 else 30 end as cap_min,
         /* v19.23 — act_min reemplaza a raw_min en TODO lo que mide tiempo. El mismo
            día se resuelve inline: esta vista barre TODOS los eventos de 56 días. */
         case when r.ts_inicio is null or r.ts_cliente <= r.ts_inicio then null
              when (r.ts_inicio  at time zone 'America/Argentina/Buenos_Aires')::date
                 = (r.ts_cliente at time zone 'America/Argentina/Buenos_Aires')::date
                   then extract(epoch from (r.ts_cliente - r.ts_inicio)) / 60.0
              else public.gv_min_activos(coalesce(r.legajo, '?'), r.ts_inicio, r.ts_cliente)
         end as act_min
    from public."Registros_Produccion_Virgilio" r
   where coalesce(r.ts_cliente, r.created_at) > now() - interval '56 days'
     and not es_legajo_test(r.legajo)
), ev as (
  select ev0.*,
         (ev0.act_min is not null
          and extract(epoch from (ev0.ts_cliente - ev0.ts_inicio)) >= 60
          and ev0.act_min <= 720) as valido
    from ev0
), dead_raw as (
  select coalesce(r.legajo, '?') as legajo,
         r.ts_inicio as s,
         least(r.ts_cliente,
               r.ts_inicio + (case r.opcion when 'PC' then 90 else 30 end) * interval '1 minute') as e
    from public."Registros_Produccion_Virgilio" r
   where coalesce(r.ts_cliente, r.created_at) > now() - interval '56 days'
     and not es_legajo_test(r.legajo)
     and r.opcion in ('AT', 'PB', 'Limp', 'PC', 'CT')
     and r.ts_inicio is not null and r.ts_cliente > r.ts_inicio
), dead_isl as (
  select y.legajo, y.s, y.e,
         sum(case when y.rmax is null or y.s > y.rmax then 1 else 0 end)
           over (partition by y.legajo order by y.s, y.e) as grp
    from (select dr.legajo, dr.s, dr.e,
                 max(dr.e) over (partition by dr.legajo order by dr.s, dr.e
                                 rows between unbounded preceding and 1 preceding) as rmax
            from dead_raw dr) y
), dead as (
  select legajo, min(s) as s, max(e) as e from dead_isl group by legajo, grp
), evc as (
  select ev.legajo, ev.opcion, ev.dia, ev.sem, ev.tanda, ev.ts_inicio, ev.ts_cliente,
         ev.valido, ev.act_min, ev.cap_min,
         case when (ev.ts_inicio  at time zone 'America/Argentina/Buenos_Aires')::date
                 = (ev.ts_cliente at time zone 'America/Argentina/Buenos_Aires')::date
                   then ev.ts_inicio + least(ev.ts_cliente - ev.ts_inicio, ev.cap_min * interval '1 minute')
              else public.gv_fin_activo(ev.legajo, ev.ts_inicio, ev.ts_cliente, ev.cap_min)
         end as e_cap
    from ev where ev.valido
), m3 as (
  select upper(btrim(tanda)) as tanda, sum(m3) as m3
    from public."GV_PPP_Entregados_Historico"
   where m3 > 0 and btrim(coalesce(tanda, '')) <> ''
   group by upper(btrim(tanda))
), jor as (
  select d.legajo, d.sem, round(sum(d.span), 1) as jornada_min,
         count(*) filter (where d.worked) as jornadas
    from (select ev.legajo, ev.sem, ev.dia,
                 least(extract(epoch from (max(ev.ts_cliente) - min(coalesce(ev.ts_inicio, ev.ts_cliente)))) / 60.0, 960) as span,
                 bool_or(ev.opcion in ('TAP', 'TP')) as worked
            from ev group by ev.legajo, ev.sem, ev.dia) d
   group by d.legajo, d.sem
), iv as (
  select legajo, sem, ts_inicio as s, e_cap as e, 'all'  as scope from evc
  union all
  select legajo, sem, ts_inicio, e_cap, 'prod' from evc where opcion in ('TAP', 'TP')
  union all
  select legajo, sem, ts_inicio, e_cap, 'arm'  from evc where opcion = 'TAP'
  union all
  select legajo, sem, ts_inicio, e_cap, 'pick' from evc where opcion = 'TP'
), isl as (
  select y.legajo, y.sem, y.scope, y.s, y.e,
         sum(case when y.rmax is null or y.s > y.rmax then 1 else 0 end)
           over (partition by y.legajo, y.sem, y.scope order by y.s, y.e) as grp
    from (select iv.legajo, iv.sem, iv.scope, iv.s, iv.e,
                 max(iv.e) over (partition by iv.legajo, iv.sem, iv.scope order by iv.s, iv.e
                                 rows between unbounded preceding and 1 preceding) as rmax
            from iv) y
), mg as (
  select legajo, sem, scope, grp, min(s) as ms, max(e) as me
    from isl group by legajo, sem, scope, grp
), mgn as (
  select g.legajo, g.sem, g.scope, g.grp, g.ms, g.me,
         coalesce(sum(case when d.legajo is null then 0
                           else greatest(0, extract(epoch from (least(g.me, d.e) - greatest(g.ms, d.s))) / 60.0)
                      end), 0) as min_muerto
    from mg g
    left join dead d on d.legajo = g.legajo and d.s < g.me and g.ms < d.e
   group by g.legajo, g.sem, g.scope, g.grp, g.ms, g.me
), eff as (
  select z.legajo, z.sem,
         max(z.tot) filter (where z.scope = 'arm')  as arm_eff,
         max(z.tot) filter (where z.scope = 'pick') as pick_eff,
         max(z.tot) filter (where z.scope = 'prod') as prod_eff,
         max(z.tot) filter (where z.scope = 'all')  as all_eff
    from (select legajo, sem, scope,
                 sum(greatest(0,
                     (case when (ms at time zone 'America/Argentina/Buenos_Aires')::date
                              = (me at time zone 'America/Argentina/Buenos_Aires')::date
                                then extract(epoch from (me - ms)) / 60.0
                           else public.gv_min_activos(legajo, ms, me) end)
                     - min_muerto)) as tot
            from mgn group by legajo, sem, scope) z
   group by z.legajo, z.sem
)
select e.legajo,
       to_char(e.sem, 'IYYY-"S"IW') as semana,
       e.sem as semana_ts,
       count(*) filter (where e.opcion = 'TAP') as armadas,
       count(*) filter (where e.opcion = 'TP')  as pickeadas,
       round(percentile_cont(0.5) within group (order by e.act_min::double precision)
             filter (where e.opcion = 'TAP' and e.valido))::integer as min_x_armado,
       round(coalesce(ef.arm_eff, 0), 1)  as arm_eff_min,
       round(coalesce(ef.pick_eff, 0), 1) as pick_eff_min,
       round(coalesce(ef.prod_eff, 0), 1) as prod_eff_min,
       round(coalesce(ef.all_eff, 0), 1)  as all_eff_min,
       round(sum(m.m3) filter (where e.opcion = 'TAP' and e.valido and m.m3 is not null), 2) as arm_m3,
       round(sum(m.m3) filter (where e.opcion = 'TP'  and e.valido and m.m3 is not null), 2) as pick_m3,
       count(*) filter (where e.opcion = 'TAP' and e.valido and m.m3 is not null) as arm_tandas_dur,
       count(*) filter (where e.opcion = 'TP'  and e.valido and m.m3 is not null) as pick_tandas_dur,
       coalesce(max(j.jornadas), 0) as jornadas,
       round(coalesce(max(j.jornada_min), 0), 1) as jornada_min,
       round(sum(least(e.act_min, e.cap_min::numeric)) filter (where e.valido and e.opcion in ('CC','CCN','CCR')), 1) as t_carga,
       round(sum(least(e.act_min, e.cap_min::numeric)) filter (where e.valido and e.opcion in ('CR','CRN')), 1) as t_control,
       round(sum(least(e.act_min, e.cap_min::numeric)) filter (where e.valido and e.opcion = 'MG'), 1) as t_movim,
       round(sum(least(e.act_min, e.cap_min::numeric)) filter (where e.valido and e.opcion = 'PC'), 1) as t_comida,
       round(sum(least(e.act_min, e.cap_min::numeric)) filter (where e.valido and e.opcion in ('RT','RR','RI','EI')), 1) as t_recep,
       round(sum(least(e.act_min, e.cap_min::numeric)) filter (where e.valido and e.opcion = 'Limp'), 1) as t_limp,
       round(sum(least(e.act_min, e.cap_min::numeric)) filter (where e.valido and e.opcion not in
             ('TAP','TP','CC','CCN','CCR','CR','CRN','MG','PC','RT','RR','RI','EI','Limp')), 1) as t_otros
  from ev e
  left join m3  m on m.tanda  = e.tanda
  left join jor j on j.legajo = e.legajo and j.sem = e.sem
  left join eff ef on ef.legajo = e.legajo and ef.sem = e.sem
 group by e.legajo, e.sem, ef.arm_eff, ef.pick_eff, ef.prod_eff, ef.all_eff
having count(*) filter (where e.opcion in ('TAP', 'TP')) > 0;

alter view public.vista_productividad_semanal set (security_invoker = true);

-- ---------------------------------------------------------------------------
-- 4) Chequeos (los cinco tienen que dar lo que dice el comentario)
-- ---------------------------------------------------------------------------
-- a) el ejemplo textual de Luis: 16:05 → 08:05 del otro día = 0,93 h, no 16 h
--    select round(public.gv_min_activos('237','2026-09-14T16:05-03','2026-09-15T08:05-03')/60,2);
-- b) ninguna vista quedó sin security_invoker legible por anon:
--    select c.relname from pg_class c join pg_namespace n on n.oid=c.relnamespace
--     where n.nspname='public' and c.relkind='v'
--       and coalesce(array_to_string(c.reloptions,','),'') not like '%security_invoker%'
--       and has_table_privilege('anon', c.oid, 'SELECT');           -- 0 filas
-- c) ningún día con más minutos efectivos que minutos de jornada:
--    select * from public.vista_productividad_diaria where arm_eff_min + pick_eff_min > 960;
-- d) los cierres que cruzan el día ahora cuentan, y con horas sanas:
--    ver §3.ij de docs/SUPABASE-GESTION-VIRGILIO.md
-- e) gv_endpoints_rotos vacío:  select * from public.gv_endpoints_rotos;
