-- v21.13 — Luis, 2026-09-22: "OCs. Generacion manual. Si se generan manualmente, que consulte
-- cuando retomar el ciclo de generacion automatica en ese momento."
--
-- QUE PASABA: el cron 50 (`ocs-auto-miercoles`, '0 10 * * 3') generaba TODOS los miercoles sin
-- mirar si alguien las habia generado a mano el lunes. El unico guard de
-- `generar_ocs_automaticas` es "ya hay OCs de HOY", asi que una corrida manual del lunes no
-- movia nada: el miercoles salia igual, dos dias despues.
--
-- COMO QUEDA: el ciclo tiene un ANCLA en `GV_OC_Auto.proxima_auto`. El cron pasa a ser DIARIO y
-- llama al envoltorio `gv_oc_auto_corrida()`, que:
--   * si el ancla esta vacia -> ciclo historico (solo miercoles). Migracion sin cambio de conducta.
--   * si hoy < ancla        -> no hace nada y devuelve `pospuesta_hasta:<fecha>`.
--   * si hoy >= ancla       -> genera y adelanta el ancla `hoy + cadencia_dias` (7).
-- Al generar A MANO, la pantalla pregunta cuando retomar y escribe el ancla con
-- `gv_oc_auto_programar(fecha, motivo)`. O sea que la fecha elegida MANDA: puede ser cualquier
-- dia, no solo miercoles, porque el cron ya corre todos los dias y el que decide es el ancla.
--
-- ⚠ `generar_ocs_automaticas(boolean)` NO SE TOCA. El ciclo vive en el envoltorio, asi que otra
--    sesion puede seguir editando esa funcion sin pisar esta regla, y el rollback es una linea.
--
-- ROLLBACK (deja todo como antes; la tabla puede quedar, nadie mas la lee):
--   select cron.alter_job(50, schedule := '0 10 * * 3',
--                             command  := 'select public.generar_ocs_automaticas()');

-- ── 1. el ancla ────────────────────────────────────────────────────────────────
create table if not exists public."GV_OC_Auto" (
  id             int primary key default 1,
  proxima_auto   date,
  cadencia_dias  int  not null default 7,
  motivo         text,
  fijado_por     text,
  fijado_en      timestamptz default now(),
  constraint gv_oc_auto_una_fila check (id = 1),
  constraint gv_oc_auto_cadencia check (cadencia_dias between 1 and 90)
);
alter table public."GV_OC_Auto" enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where schemaname='public'
                  and tablename='GV_OC_Auto' and policyname='gv_oc_auto_lectura') then
    create policy gv_oc_auto_lectura on public."GV_OC_Auto" for select to anon, authenticated using (true);
  end if;
end $$;
-- se escribe SOLO por las dos funciones de abajo (security definer)
revoke insert, update, delete, truncate on public."GV_OC_Auto" from anon, authenticated;
grant select on public."GV_OC_Auto" to anon, authenticated;

-- semilla: el miercoles que viene, que es el ciclo que ya corria
insert into public."GV_OC_Auto" (id, proxima_auto, cadencia_dias, motivo, fijado_por)
select 1,
       (select d::date from generate_series(
           (now() at time zone 'America/Argentina/Buenos_Aires')::date + 1,
           (now() at time zone 'America/Argentina/Buenos_Aires')::date + 7, interval '1 day') d
         where extract(isodow from d) = 3 limit 1),
       7, 'semilla v21.13: el ciclo miercoles que ya corria', 'sistema'
 on conflict (id) do nothing;

-- ── 2. el envoltorio que corre el cron ─────────────────────────────────────────
create or replace function public.gv_oc_auto_corrida()
returns text
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_hoy  date := (now() at time zone 'America/Argentina/Buenos_Aires')::date;
  v_prox date;
  v_cad  int := 7;
  v_res  text;
begin
  select a.proxima_auto, coalesce(a.cadencia_dias, 7)
    into v_prox, v_cad
    from public."GV_OC_Auto" a where a.id = 1;
  if not found then v_cad := 7; end if;

  if v_prox is null then
    -- sin ancla cargada: se comporta como siempre (solo miercoles)
    if extract(isodow from v_hoy) <> 3 then
      return 'fuera_de_ciclo:no_es_miercoles';
    end if;
  elsif v_hoy < v_prox then
    return 'pospuesta_hasta:' || to_char(v_prox, 'YYYY-MM-DD');
  end if;

  v_res := public.generar_ocs_automaticas(false);

  -- El ancla avanza salvo que la corrida se haya caido: ahi se reintenta manana sola.
  -- Se adelanta TAMBIEN cuando no habia nada que pedir o ya habia OCs del dia, porque en los
  -- dos casos el turno de esta semana ya se consumio.
  if coalesce(left(v_res, 6), '') <> 'error:' then
    insert into public."GV_OC_Auto" (id, proxima_auto, cadencia_dias, motivo, fijado_por, fijado_en)
    values (1, v_hoy + v_cad, v_cad, 'ciclo automatico (' || coalesce(v_res, '?') || ')', 'sistema', now())
    on conflict (id) do update
       set proxima_auto = excluded.proxima_auto,
           motivo       = excluded.motivo,
           fijado_por   = excluded.fijado_por,
           fijado_en    = excluded.fijado_en;
  end if;
  return v_res;
end
$function$;
revoke execute on function public.gv_oc_auto_corrida() from public, anon, authenticated;

-- ── 3. la RPC que llama la pantalla despues de generar a mano ─────────────────
create or replace function public.gv_oc_auto_programar(p_fecha date, p_motivo text default null)
returns table(proxima_auto date, cadencia_dias int, motivo text, fijado_por text)
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_hoy date := (now() at time zone 'America/Argentina/Buenos_Aires')::date;
  v_qui text := coalesce(nullif(auth.jwt() ->> 'email', ''), session_user);
begin
  if not (public.es_supervisor_virgilio() or public.gv_es_supervisor_o_servicio()) then
    raise exception 'Solo un supervisor puede mover el ciclo de las OC automaticas.';
  end if;
  if p_fecha is null then
    raise exception 'Falta la fecha desde la que retoma la generacion automatica.';
  end if;
  if p_fecha < v_hoy then
    raise exception 'La fecha (%) ya paso. El ciclo se retoma de hoy en adelante.', p_fecha;
  end if;
  if p_fecha > v_hoy + 180 then
    raise exception 'La fecha (%) esta a mas de 180 dias.', p_fecha;
  end if;

  insert into public."GV_OC_Auto" (id, proxima_auto, cadencia_dias, motivo, fijado_por, fijado_en)
  values (1, p_fecha, 7, coalesce(nullif(btrim(p_motivo), ''), 'se generaron a mano'), v_qui, now())
  on conflict (id) do update
     set proxima_auto = excluded.proxima_auto,
         motivo       = excluded.motivo,
         fijado_por   = excluded.fijado_por,
         fijado_en    = excluded.fijado_en;

  return query select a.proxima_auto, a.cadencia_dias, a.motivo, a.fijado_por
                 from public."GV_OC_Auto" a where a.id = 1;
end
$function$;
revoke execute on function public.gv_oc_auto_programar(date, text) from public, anon;
grant  execute on function public.gv_oc_auto_programar(date, text) to authenticated, service_role;

-- ── 4. el cron pasa a diario y llama al envoltorio ────────────────────────────
select cron.alter_job(50, schedule := '0 10 * * *',
                          command  := 'select public.gv_oc_auto_corrida()');
-- ⚠ El jobname sigue siendo 'ocs-auto-miercoles' y ya NO dice la verdad (corre todos los dias,
--   el que decide es el ancla). No se pudo renombrar: `update cron.job` da `permission denied
--   for table job` hasta para postgres en Supabase, y `cron.alter_job` no tiene job_name.

-- ── 5. centinelas (la regla no se puede perder en silencio) ───────────────────
insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
values ('gv_oc_auto_corrida', 'funcion', 'pospuesta_hasta',
        'La generacion automatica de OC respeta el ancla GV_OC_Auto.proxima_auto: si se generaron a mano, no vuelve a generar hasta la fecha que eligio el supervisor.',
        'Luis', 'v21.13')
on conflict do nothing;
