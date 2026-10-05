-- =====================================================================================
-- v26.62 · «FRENAR la tanda» — parte 2 (Luis, 2026-10-05)
-- Proyecto Gestión Virgilio (hrxfctzncixxqmpfhskv). APLICADO el 05/10 (el pedido es la autorización).
--
-- Qué hace la base desde acá:
--   1. gv_tanda_frenar deja en Registros_Produccion_Virgilio el CIERRE del tramo del dueño:
--      PKF (frenó picking) / APF (frenó armado), texto = tanda, ts_inicio = su EP/AP. Lo escribe la
--      base (client_id 'frn_<id freno>', gv_app 'gestion-db'): vale igual si frena el operario,
--      el supervisor o el fichaje. Nueva firma: + p_ts_cliente (cuándo frenó, si es creíble).
--   2. vista_tanda_status: una tanda con PKF/APF como último evento queda en 'picking'/'armando'
--      (no 'pickeado' ni 'completo') y pick_legajo / arm_legajo = el que la frenó.
--   3. gv_monitor_horas_operario_dia: PKF/APF CIERRAN el tramo abierto (no queda como tarea
--      abierta) y su duración suma a las horas de picking/armado de QUIEN la hizo (sin cola).
--      Huella re-congelada (md5 511b8f5eac8c198a3cbbc49c7de9b25c, v26.62). ≡ index.html
--      fetchMonitorDayStats. El 15/09 y del 01 al 05/10 dieron idéntico al aplicarlo.
--   4. gv_picking_puntaje_operario: una tanda con freno de picking no entra en el puntaje
--      (la pickearon dos tramos u operarios) hasta el reparto por operario (parte 3).
--   5. gv_tanda_tomar_frenada devuelve 'ubicacion' (dónde quedó el carro del último freno).
--
-- Centinelas: GV_Reglas_Centinela ids 300-306 (v26.62).
-- Backup de las definiciones anteriores: zz_backups."GV_Backup_TandaFreno_defs_20261005"
--   (objetos vista_tanda_status, gv_monitor_horas_operario_dia, gv_picking_puntaje_operario,
--    gv_tanda_reservar, gv_tandas_lock_estado). La gv_tanda_frenar v26.61 quedó RENOMBRADA a
--    gv_tanda_frenar_v2661 (el DROP se cuelga en el MCP).
--
-- ROLLBACK (al final del archivo).
-- =====================================================================================

-- 1) FRENAR deja el evento ----------------------------------------------------------------
-- (en vivo se hizo: alter function public.gv_tanda_frenar(text,text,text,text,text) rename to gv_tanda_frenar_v2661;)
create or replace function public.gv_tanda_frenar(
  p_tanda text, p_fase text, p_legajo text,
  p_motivo text default 'boton', p_ubicacion text default null, p_ts_cliente timestamptz default null)
returns jsonb
language plpgsql security definer set search_path to 'public'
as $function$
-- v26.61-frenar (Luis, 05/10): soltar una tanda TOMADA con lo hecho registrado.
-- v26.62-evento: deja en Registros_Produccion_Virgilio el cierre del tramo del dueño — PKF (picking)
-- o APF (armado), texto = tanda, ts_inicio = su EP/AP — para que las horas, la TV y la lista de
-- tandas sepan que la tanda quedó FRENADA (no en curso, no terminada). Lo escribe la base, no el
-- celular: vale igual si frena el operario, el supervisor o el fichaje.
declare
  t text := upper(btrim(coalesce(p_tanda,'')));
  f text := lower(btrim(coalesce(p_fase,'')));
  l text := btrim(coalesce(p_legajo,''));
  m text := lower(btrim(coalesce(p_motivo,'boton')));
  r public."GV_Tandas_Lock";
  v_por text;
  v_ini timestamptz;
  v_ts timestamptz;
  v_id bigint;
begin
  if t = '' or f not in ('picking','armado') or m not in ('boton','fichaje','supervisor') then
    return jsonb_build_object('ok', false, 'motivo', 'datos_invalidos');
  end if;
  if public.es_legajo_test(l) then
    return jsonb_build_object('ok', true, 'motivo', 'prueba');
  end if;
  select * into r from public."GV_Tandas_Lock" where tanda = t and fase = f for update;
  if not found then
    return jsonb_build_object('ok', false, 'motivo', 'no_tomada');
  end if;
  if r.estado = 'frenada' then        -- idempotente: un reintento de la cola no es un error
    return jsonb_build_object('ok', true, 'motivo', 'ya_frenada', 'legajo', r.legajo, 'nombre', r.nombre);
  end if;
  if r.estado <> 'tomada' then
    return jsonb_build_object('ok', false, 'motivo', 'no_tomada', 'estado', r.estado);
  end if;

  if m = 'boton' then
    if coalesce(r.legajo,'') <> l then
      return jsonb_build_object('ok', false, 'motivo', 'no_es_tuya', 'legajo', r.legajo, 'nombre', r.nombre);
    end if;
    v_por := l;
  elsif m = 'supervisor' then
    if not public.es_supervisor_virgilio() then
      return jsonb_build_object('ok', false, 'motivo', 'sin_permiso');
    end if;
    v_por := 'sup:' || coalesce(auth.jwt() ->> 'email', '?');
  else  -- 'fichaje': sólo si el dueño fichó salida DESPUÉS de tomarla. Lo verifica la base, no quien llama.
    if not exists (select 1 from public."Registros_Produccion_Virgilio" fj
                    where fj.opcion = 'FJ' and btrim(fj.legajo) = coalesce(r.legajo,'')
                      and fj.ts_cliente >= r.ts) then
      return jsonb_build_object('ok', false, 'motivo', 'sin_fichaje');
    end if;
    v_por := 'sistema';
  end if;

  -- el tramo del dueño: su último EP/AP vivo de esta tanda (desde que la tomó)
  select max(e.ts_cliente) into v_ini
    from public."Registros_Produccion_Virgilio" e
   where e.opcion = case f when 'picking' then 'EP' else 'AP' end
     and upper(btrim(e.texto)) = t and btrim(e.legajo) = coalesce(r.legajo,'');
  -- cuándo frenó: lo que dice el celular si es creíble (no antes del arranque ni en el futuro);
  -- por fichaje, el FJ; si no, ahora.
  if m = 'fichaje' then
    select min(fj.ts_cliente) into v_ts from public."Registros_Produccion_Virgilio" fj
     where fj.opcion = 'FJ' and btrim(fj.legajo) = coalesce(r.legajo,'') and fj.ts_cliente >= coalesce(v_ini, r.ts);
  elsif p_ts_cliente is not null and p_ts_cliente <= now() + interval '2 minutes'
        and p_ts_cliente >= coalesce(v_ini, r.ts) then
    v_ts := least(p_ts_cliente, now());
  end if;
  v_ts := coalesce(v_ts, now());

  update public."GV_Tandas_Lock" set estado = 'frenada', ts_estado = now() where tanda = t and fase = f;
  insert into public."GV_Tanda_Freno" (tanda, fase, legajo, nombre, por, motivo, ubicacion, ts_freno)
  values (t, f, r.legajo, r.nombre, v_por, m, nullif(btrim(coalesce(p_ubicacion,'')),''), v_ts)
  returning id into v_id;
  if coalesce(r.legajo,'') <> '' then
    insert into public."Registros_Produccion_Virgilio" (legajo, opcion, descripcion, texto, ts_cliente, ts_inicio, client_id, gv_app)
    values (r.legajo, case f when 'picking' then 'PKF' else 'APF' end,
            case f when 'picking' then 'Frenó picking' else 'Frenó armado' end
              || case m when 'boton' then '' when 'fichaje' then ' (al fichar salida)' else ' (supervisor)' end,
            t, v_ts, v_ini, 'frn_' || v_id, 'gestion-db')
    on conflict (client_id) do nothing;
  end if;
  return jsonb_build_object('ok', true, 'motivo', 'frenada', 'legajo', r.legajo, 'nombre', r.nombre, 'ts', v_ts);
end $function$;
revoke all on function public.gv_tanda_frenar(text,text,text,text,text,timestamptz) from public;
grant execute on function public.gv_tanda_frenar(text,text,text,text,text,timestamptz) to anon, authenticated;

-- 2) OTRO OPERARIO SE LLEVA UNA FRENADA: devuelve dónde quedó el carro -------------------
create or replace function public.gv_tanda_tomar_frenada(
  p_tanda text, p_fase text, p_legajo text, p_nombre text default null)
returns jsonb
language plpgsql security definer set search_path to 'public'
as $function$
-- v26.61-tomar (Luis, 05/10): «Estás por agarrar una tanda que empezó A ¿Seguro?» → sí.
-- v26.62: devuelve también dónde dejó el carro el que la frenó (ubicacion del último freno).
declare
  t text := upper(btrim(coalesce(p_tanda,'')));
  f text := lower(btrim(coalesce(p_fase,'')));
  l text := btrim(coalesce(p_legajo,''));
  n text := nullif(btrim(coalesce(p_nombre,'')),'');
  r public."GV_Tandas_Lock";
  o public."GV_Tandas_Lock";
  v_ub text;
begin
  if t = '' or f not in ('picking','armado') or l = '' then
    return jsonb_build_object('ok', false, 'motivo', 'datos_invalidos');
  end if;
  if public.es_legajo_test(l) then
    return jsonb_build_object('ok', true, 'motivo', 'prueba');
  end if;
  select * into r from public."GV_Tandas_Lock" where tanda = t and fase = f for update;
  if not found or r.estado <> 'frenada' then
    return jsonb_build_object('ok', false, 'motivo', 'no_frenada', 'estado', r.estado,
      'legajo', r.legajo, 'nombre', r.nombre);
  end if;
  -- una por vez (v18.73): si ya tiene OTRA tanda tomada de esta fase, no se lleva ésta.
  select * into o from public."GV_Tandas_Lock"
   where fase = f and estado = 'tomada' and legajo = l and tanda <> t and ts >= now() - interval '3 days'
   order by ts limit 1;
  if found then
    return jsonb_build_object('ok', false, 'motivo', 'otra_tanda_abierta', 'tanda_abierta', o.tanda);
  end if;
  select z.ubicacion into v_ub from public."GV_Tanda_Freno" z
   where z.tanda = t and z.fase = f and z.retomada_ts is null order by z.ts_freno desc limit 1;
  update public."GV_Tandas_Lock"
     set estado = 'tomada', legajo = l, nombre = n, ts = now(), ts_estado = now()
   where tanda = t and fase = f;
  update public."GV_Tanda_Freno" set retomada_por = l, retomada_nombre = n, retomada_ts = now()
   where id = (select z.id from public."GV_Tanda_Freno" z where z.tanda = t and z.fase = f
                 and z.retomada_ts is null order by z.ts_freno desc limit 1);
  return jsonb_build_object('ok', true, 'motivo', case when coalesce(r.legajo,'') = l then 'propia' else 'tomada_de' end,
    'legajo_anterior', r.legajo, 'nombre_anterior', r.nombre, 'ubicacion', v_ub);
end $function$;
revoke all on function public.gv_tanda_tomar_frenada(text,text,text,text) from public;
grant execute on function public.gv_tanda_tomar_frenada(text,text,text,text) to anon, authenticated;

-- 3) ESTADO DE LA TANDA: la frenada sigue en picking/armado ------------------------------
create or replace view public.vista_tanda_status with (security_invoker = true) as
 WITH evts AS (
         SELECT "Registros_Produccion_Virgilio".texto AS tanda,
            "Registros_Produccion_Virgilio".opcion,
            "Registros_Produccion_Virgilio".legajo,
            "Registros_Produccion_Virgilio".ts_cliente,
            row_number() OVER (PARTITION BY "Registros_Produccion_Virgilio".texto, (
                CASE
                    WHEN "Registros_Produccion_Virgilio".opcion = ANY (ARRAY['EP'::text, 'TP'::text, 'PKF'::text]) THEN 'pick'::text
                    ELSE 'arm'::text
                END) ORDER BY "Registros_Produccion_Virgilio".ts_cliente DESC) AS rn
           FROM "Registros_Produccion_Virgilio"
          WHERE ("Registros_Produccion_Virgilio".opcion = ANY (ARRAY['EP'::text, 'TP'::text, 'AP'::text, 'TAP'::text, 'PKF'::text, 'APF'::text])) AND NULLIF(TRIM(BOTH FROM "Registros_Produccion_Virgilio".texto), ''::text) IS NOT NULL AND NOT es_legajo_test("Registros_Produccion_Virgilio".legajo)
        )
 SELECT tanda,
    max(
        CASE
            WHEN (opcion = ANY (ARRAY['EP'::text, 'TP'::text, 'PKF'::text])) AND rn = 1 THEN opcion
            ELSE NULL::text
        END) AS last_pick_op,
    max(
        CASE
            WHEN (opcion = ANY (ARRAY['EP'::text, 'PKF'::text])) AND rn = 1 THEN legajo
            ELSE NULL::text
        END) AS pick_legajo,
    max(
        CASE
            WHEN (opcion = ANY (ARRAY['EP'::text, 'PKF'::text])) AND rn = 1 THEN ts_cliente
            ELSE NULL::timestamp with time zone
        END) AS pick_start_ts,
    max(
        CASE
            WHEN (opcion = ANY (ARRAY['AP'::text, 'TAP'::text, 'APF'::text])) AND rn = 1 THEN opcion
            ELSE NULL::text
        END) AS last_arm_op,
    max(
        CASE
            WHEN (opcion = ANY (ARRAY['AP'::text, 'APF'::text])) AND rn = 1 THEN legajo
            ELSE NULL::text
        END) AS arm_legajo,
    max(
        CASE
            WHEN (opcion = ANY (ARRAY['AP'::text, 'APF'::text])) AND rn = 1 THEN ts_cliente
            ELSE NULL::timestamp with time zone
        END) AS arm_start_ts,
        CASE
            WHEN max(
            CASE
                WHEN (opcion = ANY (ARRAY['EP'::text, 'TP'::text, 'PKF'::text])) AND rn = 1 THEN opcion
                ELSE NULL::text
            END) IS NULL THEN 'pendiente'::text
            WHEN max(
            CASE
                WHEN (opcion = ANY (ARRAY['EP'::text, 'TP'::text, 'PKF'::text])) AND rn = 1 THEN opcion
                ELSE NULL::text
            END) = ANY (ARRAY['EP'::text, 'PKF'::text]) THEN 'picking'::text
            WHEN max(
            CASE
                WHEN (opcion = ANY (ARRAY['EP'::text, 'TP'::text, 'PKF'::text])) AND rn = 1 THEN opcion
                ELSE NULL::text
            END) = 'TP'::text AND max(
            CASE
                WHEN (opcion = ANY (ARRAY['AP'::text, 'TAP'::text, 'APF'::text])) AND rn = 1 THEN opcion
                ELSE NULL::text
            END) = 'TAP'::text THEN 'completo'::text
            WHEN max(
            CASE
                WHEN (opcion = ANY (ARRAY['EP'::text, 'TP'::text, 'PKF'::text])) AND rn = 1 THEN opcion
                ELSE NULL::text
            END) = 'TP'::text AND (max(
            CASE
                WHEN (opcion = ANY (ARRAY['AP'::text, 'TAP'::text, 'APF'::text])) AND rn = 1 THEN opcion
                ELSE NULL::text
            END) = ANY (ARRAY['AP'::text, 'APF'::text])) THEN 'armando'::text
            WHEN max(
            CASE
                WHEN (opcion = ANY (ARRAY['EP'::text, 'TP'::text, 'PKF'::text])) AND rn = 1 THEN opcion
                ELSE NULL::text
            END) = 'TP'::text THEN 'pickeado'::text
            ELSE 'pendiente'::text
        END AS estado
   FROM evts
  WHERE rn = 1
  GROUP BY tanda;
alter view public.vista_tanda_status set (security_invoker = true);

-- 4) PUNTAJE: la tanda frenada se mide aparte -------------------------------------------
CREATE OR REPLACE FUNCTION public.gv_picking_puntaje_operario(p_dias integer DEFAULT 60)
 RETURNS TABLE(legajo text, nombre text, tandas integer, cajas numeric, indice_ult numeric, puntaje_ult integer, indice_per numeric, puntaje_per integer, publicable boolean, margen_pts numeric, tramos jsonb, ultima_tp timestamp with time zone, detalle jsonb)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare c jsonb; v_vent int; v_min int; v_base numeric; v_k numeric;
begin
  if not (public.es_supervisor_virgilio() or public.gv_es_supervisor_o_servicio()) then
    raise exception 'SUPERVISOR: el puntaje de picking es sólo para supervisores';
  end if;
  select jsonb_object_agg(clave, valor) into c from public."GV_Picking_Esquema";
  v_vent := coalesce((c->>'ventana_tandas')::int, 20);  v_min := coalesce((c->>'min_publica')::int, 10);
  v_base := coalesce((c->>'puntaje_base')::numeric, 5.5); v_k := coalesce((c->>'puntaje_por_indice')::numeric, 10);
  return query
  with g as (   -- sólo tandas con picking (líneas), de un turno (EP→TP ≤ 12 h, real ≤ 4 h) y cuyo TP sigue vivo (un TPX la saca sin borrar el caché)
    select t.*, row_number() over (partition by t.legajo order by t.tp desc) rn,
           row_number() over (partition by t.legajo order by t.tp) rn_asc
      from public."GV_Picking_Tanda" t
     where t.tp >= now() - make_interval(days => p_dias) and t.real_min between 0.5 and 240 and t.tamano > 0
       and coalesce(t.lineas, 0) > 0 and t.bruto_min <= 720
       and exists (select 1 from public."Registros_Produccion_Virgilio" e
                    where e.opcion = 'TP' and e.ts_cliente = t.tp and e.legajo::text = t.legajo and upper(btrim(e.texto)) = t.tanda)
       -- v26.62-frenada: una tanda FRENADA (dos operarios o dos tramos) se mide aparte, no en el puntaje
       and not exists (select 1 from public."GV_Tanda_Freno" fz where fz.tanda = t.tanda and fz.fase = 'picking')
  ),
  ult as (select g.legajo, sum(g.tamano) / sum(g.real_min) i, stddev_samp(g.indice) sd, count(*) n from g where g.rn <= v_vent group by g.legajo),
  per as (select g.legajo, sum(g.tamano) / sum(g.real_min) i, count(*) n, sum(g.cajas) cajas, max(g.tp) ultima from g group by g.legajo),
  tr  as (select z.legajo, jsonb_agg(round(z.i, 2) order by z.k) tramos
            from (select g.legajo, (g.rn_asc - 1) / 10 k, sum(g.tamano) / sum(g.real_min) i from g group by g.legajo, (g.rn_asc - 1) / 10) z
           group by z.legajo),
  det as (select g.legajo, jsonb_agg(jsonb_build_object('tanda', g.tanda, 'fecha', to_char(g.tp at time zone 'America/Argentina/Buenos_Aires', 'DD/MM'),
                   'tamano', round(g.tamano, 1), 'real', round(g.real_min, 1), 'indice', round(g.indice, 2), 'grado', g.grado, 'nivel', g.nivel,
                   'cajas', g.cajas, 'lineas', g.lineas, 'paradas', g.paradas, 'esc', g.esc, 'cola', round(g.cola_min, 1),
                   'cero', g.lineas_cero, 'frac', g.m3_frac) order by g.tp desc) d
            from g where g.rn <= v_vent group by g.legajo)
  select per.legajo, coalesce(e."Empleado", '') nombre, per.n::int, per.cajas,
         round(ult.i, 3), greatest(1, least(10, round(v_base + v_k * (ult.i - 1))))::int,
         round(per.i, 3), greatest(1, least(10, round(v_base + v_k * (per.i - 1))))::int,
         per.n >= v_min,
         case when ult.n >= 2 then round((v_k * 1.645 * coalesce(ult.sd, 0) / sqrt(ult.n))::numeric, 1) end,
         tr.tramos, per.ultima, det.d
    from per join ult on ult.legajo = per.legajo
    left join tr on tr.legajo = per.legajo
    left join det on det.legajo = per.legajo
    left join public."Empleados" e on btrim(e."Legajo") = per.legajo
   order by ult.i desc;
end
$function$;

-- 5) HORAS POR OPERARIO: el PKF/APF cierra el tramo y suma a quien lo hizo -----------------
CREATE OR REPLACE FUNCTION public.gv_monitor_horas_operario_dia(p_dia date)
 RETURNS TABLE(legajo text, nombre text, dia date, tandas_pick bigint, hs_pick numeric, prom_hs_pick numeric, tandas_arm bigint, hs_arm numeric, prom_hs_arm numeric, hs_prod numeric, hs_mov numeric, hs_noprod numeric, hs_total numeric, en_jornada boolean)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
with feriados as (
  select f.fecha as d from public."GV_Feriados" f where f.tipo = 'feriado'
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
abre as (   -- v23.66-abiertas: aperturas de HOY (EP/AP/toggles/MGI/RKI/IRI) sin su cierre
  select b.legajo, b.tanda, b.ts_cliente as ini,
         case b.opcion when 'MGI' then 'MG' when 'RKI' then 'RKB' when 'IRI' then 'IRT' else b.opcion end as k
    from base b
   where b.ts_inicio is null   -- v23.72-cruce: también días pasados (lo abierto al FJ suma a SU día)
     and b.opcion in ('EP','AP','MGI','RKI','IRI','CR','RR','CC','RT','MG','RI','EI','AT','PB','Limp','PC','Perm','CT')
),
abierta as (   -- v23.69-finab: el FJ CIERRA la tarea abierta (no la borra); sin FJ, tope = fin de jornada
  select a.*,
         least(coalesce((select min(f.ts_cliente) from base f
                    where f.legajo = a.legajo and f.opcion = 'FJ' and f.ts_cliente > a.ini),
                  least(now(), greatest((select max(u.ts_cliente) from base u where u.legajo = a.legajo),
                        (p_dia + coalesce((select e.h_sal from emp e where e.legajo = a.legajo), time '17:00'))
                          at time zone 'America/Argentina/Buenos_Aires'))),
         -- v23.72-sig: una tarea abierta termina donde EMPIEZA la siguiente del legajo (no se superpone)
         (select min(coalesce(s.ts_inicio, s.ts_cliente)) from base s
           where s.legajo = a.legajo and coalesce(s.ts_inicio, s.ts_cliente) > a.ini
             and ((s.ts_inicio is null and s.opcion in ('EP','AP','MGI','RKI','IRI','CR','RR','CC','RT','MG','RI','EI','AT','PB','Limp','PC','Perm','CT'))
               or (s.ts_inicio is not null and s.opcion in ('MG','RT','CC','CR','RR','RI','EI','RKB','IRT')))
             and not (a.k in ('EP','AP') and s.opcion in ('EP','AP')))) as fin
    from abre a
   where (p_dia < (now() at time zone 'America/Argentina/Buenos_Aires')::date or now() - a.ini < interval '12 hours')
     and not exists (
       select 1 from base c
        where c.legajo = a.legajo and c.ts_cliente > a.ini
          and (   (a.k = 'EP' and ((c.opcion = 'TP' and (c.tanda = '' or c.tanda = a.tanda)) or (c.opcion = 'PKF' and c.tanda = a.tanda)))
               or (a.k = 'AP' and ((c.opcion = 'TAP' and (c.tanda = '' or c.tanda = a.tanda)) or (c.opcion = 'APF' and c.tanda = a.tanda)))
               or (a.k = 'MG' and c.opcion in ('MG','MGC'))
               or (a.k not in ('EP','AP','MG') and c.opcion = a.k and c.ts_inicio is not null)))
),
muerto_raw as (
  select b.legajo, b.ts_inicio as ini, b.ts_cliente as fin
    from base b
   where b.opcion in ('AT','PB','Limp','PC','CT')
     and b.ts_inicio is not null
     and b.ts_cliente > b.ts_inicio
     and b.ts_cliente - b.ts_inicio <= interval '8 hours'
  union all   -- v23.66: el tiempo muerto ABIERTO (está en el baño ahora) también se resta
  select x.legajo, x.ini, x.fin from abierta x where x.k in ('AT','PB','Limp','PC','CT')
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
    left join emp e      on e.legajo  = b.legajo
    left join fj_prev fp on fp.legajo = b.legajo
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
         (select count(*) from generate_series(t.dia_ini + 1, t.dia_fin - 1, interval '1 day') g(d)
           where extract(isodow from g.d) < 6
             and not exists (select 1 from feriados f where f.d = g.d::date)) as dias_medio
    from tramos t
),
dur as (
  select c.*,
         case when c.dia_ini = c.dia_fin then c.ts_cliente else least(c.fj_open, c.ts_cliente) end as fin_open,
         case when c.dia_ini = c.dia_fin then greatest(0, extract(epoch from (c.ts_cliente - c.ts_inicio)))
              else 0 end as open_s,   -- v23.72-cruce: el tramo del día de apertura lo suma ESE día (CTE abierta)
         case when c.dia_ini = c.dia_fin then 0
              else greatest(0, extract(epoch from (c.ts_cliente - c.close_start))) end as close_s,
         case when c.dia_ini = c.dia_fin then 0
              else c.dias_medio * greatest(0, extract(epoch from (c.h_sal - c.h_ent))) end as medio_s
    from calc c
),
neteo as (
  select d.*,
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
cola as (   -- v26.43-cola (Luis, 02/10): lo que sigue a un TP/TAP SIN registro, hasta que el legajo empieza su
            -- proxima tarea registrada (o el fin de jornada), es picking/armado de esa tanda.
  select distinct on (c.legajo, c.opcion, c.tanda) c.legajo, c.opcion, c.tanda,
         greatest(0, extract(epoch from (
           least(coalesce((select min(case when s.ts_inicio is not null and s.ts_inicio <= c.ts_cliente then c.ts_cliente
                                          else coalesce(s.ts_inicio, s.ts_cliente) end)
                             from base s
                            where s.legajo = c.legajo and s.ts_cliente > c.ts_cliente
                              and s.opcion not in ('PUB','AUB','PKC','ENT','RSP','ROC','RAG','FGU','FSS','IMPT','TAL','GST','MGR','PKM','SSG','PSP','NPD','PKAX')
                              and s.opcion !~ 'X$'
                              and not (s.opcion = c.opcion and s.tanda = c.tanda)), 'infinity'),
                 coalesce((select min(m.ts) from public."Movimientos_Stock" m
                            where m.tipo = 'baja_racks' and m.deposito in ('racks','racks_ch')
                              and m.legajo::text = c.legajo and m.ts > c.ts_cliente
                              and (m.ts at time zone 'America/Argentina/Buenos_Aires')::date = p_dia), 'infinity'),
                 least(now(), greatest((select max(u.ts_cliente) from base u where u.legajo = c.legajo),
                       (p_dia + coalesce((select e.h_sal from emp e where e.legajo = c.legajo), time '17:00'))
                         at time zone 'America/Argentina/Buenos_Aires')))
           - c.ts_cliente))) as s
    from base c
   where c.opcion in ('TP','TAP') and c.tanda <> '' and c.tanda <> 'ANULADO'
   order by c.legajo, c.opcion, c.tanda, c.ts_cliente   -- la cola es la del PRIMER cierre de la tanda (= index.html)
),
pick_tp as (select e.legajo, e.tanda, max(e.dur_s) + coalesce(max(k.s), 0) as dur_s from evok e
          left join cola k on k.legajo = e.legajo and k.tanda = e.tanda and k.opcion = 'TP'
          where e.opcion = 'TP' and e.tanda <> '' group by e.legajo, e.tanda),
pick_fr as (   -- v26.62-frenada: el tramo FRENADO (PKF) suma a quien lo hizo, sin cola
  select e.legajo, e.tanda, sum(e.dur_s) as dur_s from evok e where e.opcion = 'PKF' and e.tanda <> '' group by e.legajo, e.tanda),
pick as (select coalesce(x.legajo, y.legajo) as legajo, coalesce(x.tanda, y.tanda) as tanda,
                coalesce(x.dur_s, 0) + coalesce(y.dur_s, 0) as dur_s
           from pick_tp x full join pick_fr y on y.legajo = x.legajo and y.tanda = x.tanda),
arm_tp  as (select e.legajo, e.tanda, max(e.dur_s) + coalesce(max(k.s), 0) as dur_s from evok e
          left join cola k on k.legajo = e.legajo and k.tanda = e.tanda and k.opcion = 'TAP'
          where e.opcion = 'TAP' and e.tanda <> '' group by e.legajo, e.tanda),
arm_fr  as (   -- v26.62-frenada: el tramo FRENADO (APF) suma a quien lo hizo, sin cola
  select e.legajo, e.tanda, sum(e.dur_s) as dur_s from evok e where e.opcion = 'APF' and e.tanda <> '' group by e.legajo, e.tanda),
arm  as (select coalesce(x.legajo, y.legajo) as legajo, coalesce(x.tanda, y.tanda) as tanda,
                coalesce(x.dur_s, 0) + coalesce(y.dur_s, 0) as dur_s
           from arm_tp x full join arm_fr y on y.legajo = x.legajo and y.tanda = x.tanda),
pick_ag as (select p.legajo, count(*) as tandas, sum(p.dur_s) as dur_s from pick p group by p.legajo),
arm_ag  as (select a.legajo, count(*) as tandas, sum(a.dur_s) as dur_s from arm  a group by a.legajo),
baldes as (
  select e.legajo,
         -- v25.64-anulado (Luis 01/10): una tarea ANULADA (cierre con texto ANULADO) es tiempo muerto
         sum(e.dur_s) filter (where e.opcion in ('CC','CR','RR') and e.tanda <> 'ANULADO')  as prod_otros_s,
         sum(e.dur_s) filter (where e.opcion in ('MG','RT','RI','EI','RKB','IRT') and e.tanda <> 'ANULADO') as mov_s,
         sum(e.dur_s) filter (where e.opcion in ('AT','PB','Limp','PC','CT','Perm')
                                 or (e.tanda = 'ANULADO' and e.opcion in ('CC','CR','RR','RT','RI','EI'))) as noprod_s
    from evok e group by e.legajo
),
jornada as (
  select b.legajo, min(b.ts_cliente) as primer,
         max(b.ts_cliente) filter (where b.opcion = 'FJ') as fj,
         max(b.ts_cliente)                                as ultimo
    from base b group by b.legajo
),
rk_pts as (   -- v23.68-rkinf: bajadas/ingresos a racks sin tramo registrado
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
         -- v23.70-sintope (Luis: "sin tope de tramo"): desde la actividad anterior; sin ninguna, desde la entrada
         coalesce((select max(z.ts) from (
                     select b.ts_cliente as ts from base b where b.legajo = p.legajo and b.ts_cliente < p.t
                     union all
                     select q.t from rk_pts q where q.legajo = p.legajo and q.t < p.t) z),
                  least(p.t, (p_dia + coalesce((select e.h_ent from emp e where e.legajo = p.legajo), time '08:00'))
                               at time zone 'America/Argentina/Buenos_Aires')) as ini
    from rk_pts p
),
rk_ag as (
  select s.legajo,
         sum(greatest(0, extract(epoch from (s.fin - s.ini)) - coalesce((
           select sum(extract(epoch from (least(s.fin, m.fin) - greatest(s.ini, m.ini))))
             from muerto m where m.legajo = s.legajo and m.fin > s.ini and m.ini < s.fin), 0))) as s
    from rk_seg s group by s.legajo
),
ab_tr as (select distinct on (x.legajo) x.legajo, x.k, x.ini, x.fin from abierta x
            where x.k not in ('AT','PB','Limp','PC','CT','Perm') order by x.legajo, x.ini desc),
ab_no as (select distinct on (x.legajo) x.legajo, x.k, x.ini, x.fin from abierta x
            where x.k in ('AT','PB','Limp','PC','CT','Perm') order by x.legajo, x.ini desc),
ab_s as (
  select t.legajo, case when t.k in ('EP','AP','CC','CR','RR') then 'prod' else 'mov' end as balde,
         greatest(0, extract(epoch from (t.fin - t.ini)) - coalesce((
           select sum(extract(epoch from (least(t.fin, m.fin) - greatest(t.ini, m.ini))))
             from muerto m where m.legajo = t.legajo and m.fin > t.ini and m.ini < t.fin), 0)) as s
    from ab_tr t
  union all
  select n2.legajo, 'noprod', greatest(0, extract(epoch from (n2.fin - n2.ini))) from ab_no n2
),
ab_ag as (select a.legajo, sum(a.s) filter (where a.balde = 'prod') as prod_s,
                 sum(a.s) filter (where a.balde = 'mov') as mov_s,
                 sum(a.s) filter (where a.balde = 'noprod') as no_s
            from ab_s a group by a.legajo),
legajos as (select b.legajo from base b group by b.legajo union select r.legajo from rk_pts r)
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
               + coalesce(b.prod_otros_s,0) + coalesce(ab.prod_s,0)) / 3600.0)::numeric, 2),
       round(((coalesce(b.mov_s, 0) + coalesce(ab.mov_s, 0) + coalesce(rk.s, 0)) / 3600.0)::numeric, 2),
       round(((coalesce(b.noprod_s, 0) + coalesce(ab.no_s, 0)) / 3600.0)::numeric, 2),
       round((extract(epoch from (
              coalesce(j.fj, greatest(j.ultimo, least(now(),
                (p_dia + coalesce(e2.h_sal, time '17:00')) at time zone 'America/Argentina/Buenos_Aires')))
              - j.primer)) / 3600.0)::numeric, 2),
       (j.fj is null)
  from legajos l
  left join pick_ag p on p.legajo = l.legajo
  left join arm_ag  a on a.legajo = l.legajo
  left join baldes  b on b.legajo = l.legajo
  left join ab_ag  ab on ab.legajo = l.legajo
  left join rk_ag  rk on rk.legajo = l.legajo
  left join jornada j on j.legajo = l.legajo
  left join emp e2 on e2.legajo = l.legajo
 order by (coalesce(p.dur_s,0) + coalesce(a.dur_s,0)) desc, 2;
$function$;

-- huella re-congelada (el cuerpo cambió a propósito; tests/tools/vista-15.json NO cambia: el 15/09 no hay PKF/APF)
-- update public."GV_Huella_Objeto" set md5_esperado = '511b8f5eac8c198a3cbbc49c7de9b25c', version = 'v26.62',
--        actualizado_en = now() where objeto = 'gv_monitor_horas_operario_dia';

-- 6) CENTINELAS (ids 300-306) -------------------------------------------------------------
-- insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version) values
--  ('gv_monitor_horas_operario_dia','funcion','c\.opcion = ''PKF'' and c\.tanda = a\.tanda', …,'Luis','v26.62'),
--  ('gv_monitor_horas_operario_dia','funcion','c\.opcion = ''APF'' and c\.tanda = a\.tanda', …),
--  ('vista_tanda_status','vista','''PKF''::text', …), ('vista_tanda_status','vista','''APF''::text', …),
--  ('gv_picking_puntaje_operario','funcion','fz\.fase = ''picking''', …),
--  ('gv_tanda_frenar','funcion','then ''PKF'' else ''APF''', …),
--  ('gv_tanda_tomar_frenada','funcion','''ubicacion'', v_ub', …);

-- Chequeo:
--   select * from public.gv_reglas_perdidas;     -- vacía
--   select * from public.gv_huellas_cambiadas;   -- vacía
--   select opcion, count(*) from public."Registros_Produccion_Virgilio" where opcion in ('PKF','APF') group by 1;

-- =====================================================================================
-- ROLLBACK (todo de una, en el SQL Editor):
-- do $rb$ declare d text; begin
--   for d in select def from zz_backups."GV_Backup_TandaFreno_defs_20261005"
--             where objeto in ('gv_monitor_horas_operario_dia','gv_picking_puntaje_operario') loop
--     execute d;
--   end loop;
--   execute 'create or replace view public.vista_tanda_status with (security_invoker = true) as '
--        || (select def from zz_backups."GV_Backup_TandaFreno_defs_20261005" where objeto = 'vista_tanda_status');
-- end $rb$;
-- drop function public.gv_tanda_frenar(text,text,text,text,text,timestamptz);
-- alter function public.gv_tanda_frenar_v2661(text,text,text,text,text) rename to gv_tanda_frenar;
-- update public."GV_Huella_Objeto" set md5_esperado = (select md5(prosrc) from pg_proc where proname = 'gv_monitor_horas_operario_dia')
--  where objeto = 'gv_monitor_horas_operario_dia';
-- update public."GV_Reglas_Centinela" set activo = false where id between 300 and 306;
-- (el front v26.62 sin estos objetos: las tandas frenadas no se ven como tal; volver a v26.61 en index.html)
-- =====================================================================================
