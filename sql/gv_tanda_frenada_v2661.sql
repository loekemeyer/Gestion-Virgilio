-- =====================================================================================
-- v26.61 (Luis, 05/10/2026) — FRENAR LA TANDA, parte 1: el estado «frenada» y la copia
-- del avance del armado en el servidor.
--
-- Luis: "cuando se termina (completo o incompleto) debería capturar la información el
-- servidor para que después se pueda continuar desde otro dispositivo" · "que no se pueda
-- abrir una tanda con la que otra persona ya está trabajando" · FRENAR ≠ pausar:
--   · PAUSAR = salir un rato (baño, comida): la tanda sigue siendo del operario. Ya existe
--     (picking: «Cerrar» arriba a la derecha; armado: «⏸ Pausar» del asistente). NO se toca.
--   · FRENAR = soltarla con todo lo hecho registrado: la retoma él u otro operario.
--
-- ESTA PARTE NO CAMBIA NADA DE LO QUE SE VE HOY: nadie produce todavía el estado
-- «frenada» (el botón, el freno al fichar salida y el del supervisor son la parte 2), y la
-- copia del armado sólo se ESCRIBE (nadie la lee hasta la parte 2).
--
--   1. GV_Tandas_Lock acepta el estado 'frenada' (libre → tomada → frenada → tomada → completada).
--   2. GV_Tanda_Freno: historial de cada freno (quién, por qué, dónde quedó el carro, quién la retomó).
--   3. gv_tanda_frenar(): frena una fase TOMADA. 'boton' = sólo el dueño · 'supervisor' =
--      es_supervisor_virgilio() · 'fichaje' = sólo si el dueño fichó salida (FJ) después de tomarla.
--   4. gv_tanda_reservar(): una frenada la retoma el MISMO operario sin cartel (vuelve a 'tomada');
--      a otro le contesta ok=false motivo 'frenada' (un celular viejo muestra el «ya la tiene X» de
--      siempre = queda frenado como hoy). Se parchea sobre la definición VIVA y conserva la regla
--      v23.65 (_tr_anulada). Una frenada NO cuenta como «otra tanda abierta» (D9): el filtro de esa
--      regla ya es estado = 'tomada'.
--   5. gv_tanda_tomar_frenada(): otro operario se la lleva (después del cartel, parte 2).
--   6. GV_Armado_Avance + gv_armado_avance_guardar / _leer: la copia del asistente de armado,
--      una fila por tanda (la última), con resumen (NP, NP listas, líos, cajas en líos).
--
-- BACKUP: zz_backups."GV_Backup_TandaFreno_defs_20261005" (definición de gv_tanda_reservar y
-- del check de estado, ANTES del cambio). ROLLBACK al final del archivo.
-- =====================================================================================

-- 0) BACKUP de lo que se modifica -------------------------------------------------------
create table if not exists zz_backups."GV_Backup_TandaFreno_defs_20261005" (
  objeto text primary key, def text not null, guardado_en timestamptz not null default now());
alter table zz_backups."GV_Backup_TandaFreno_defs_20261005" enable row level security;
revoke all on zz_backups."GV_Backup_TandaFreno_defs_20261005" from anon, authenticated;
insert into zz_backups."GV_Backup_TandaFreno_defs_20261005" (objeto, def)
select 'gv_tanda_reservar', pg_get_functiondef('public.gv_tanda_reservar(text,text,text,text)'::regprocedure)
on conflict (objeto) do nothing;
insert into zz_backups."GV_Backup_TandaFreno_defs_20261005" (objeto, def)
select 'gv_tandas_lock_estado', pg_get_constraintdef(oid) from pg_constraint
 where conrelid = 'public."GV_Tandas_Lock"'::regclass and conname = 'gv_tandas_lock_estado'
on conflict (objeto) do nothing;

-- 1) ESTADO 'frenada' -----------------------------------------------------------------
alter table public."GV_Tandas_Lock" drop constraint if exists gv_tandas_lock_estado;
alter table public."GV_Tandas_Lock" add constraint gv_tandas_lock_estado
  check (estado = any (array['tomada'::text, 'frenada'::text, 'completada'::text]));

-- 2) HISTORIAL DE FRENOS -----------------------------------------------------------------
create table if not exists public."GV_Tanda_Freno" (
  id              bigserial primary key,
  tanda           text not null,
  fase            text not null check (fase in ('picking','armado')),
  legajo          text,                 -- de quién era la tanda cuando se frenó
  nombre          text,
  por             text not null,        -- quién la frenó: el legajo, 'sup:<mail>' o 'sistema'
  motivo          text not null check (motivo in ('boton','fichaje','supervisor')),
  ubicacion       text,                 -- picking: dónde quedó el carro
  ts_freno        timestamptz not null default now(),
  retomada_por    text,
  retomada_nombre text,
  retomada_ts     timestamptz
);
create index if not exists gv_tanda_freno_tanda_idx on public."GV_Tanda_Freno" (tanda, fase, ts_freno desc);
alter table public."GV_Tanda_Freno" enable row level security;
revoke all on public."GV_Tanda_Freno" from anon, authenticated;

-- 3) FRENAR ----------------------------------------------------------------------------
create or replace function public.gv_tanda_frenar(
  p_tanda text, p_fase text, p_legajo text,
  p_motivo text default 'boton', p_ubicacion text default null)
returns jsonb
language plpgsql security definer set search_path to 'public'
as $function$
-- v26.61-frenar (Luis, 05/10): soltar una tanda TOMADA con lo hecho registrado.
declare
  t text := upper(btrim(coalesce(p_tanda,'')));
  f text := lower(btrim(coalesce(p_fase,'')));
  l text := btrim(coalesce(p_legajo,''));
  m text := lower(btrim(coalesce(p_motivo,'boton')));
  r public."GV_Tandas_Lock";
  v_por text;
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

  update public."GV_Tandas_Lock" set estado = 'frenada', ts_estado = now() where tanda = t and fase = f;
  insert into public."GV_Tanda_Freno" (tanda, fase, legajo, nombre, por, motivo, ubicacion)
  values (t, f, r.legajo, r.nombre, v_por, m, nullif(btrim(coalesce(p_ubicacion,'')),''));
  return jsonb_build_object('ok', true, 'motivo', 'frenada', 'legajo', r.legajo, 'nombre', r.nombre);
end $function$;
revoke all on function public.gv_tanda_frenar(text,text,text,text,text) from public;
grant execute on function public.gv_tanda_frenar(text,text,text,text,text) to anon, authenticated;

-- 4) gv_tanda_reservar: la frenada — se parchea sobre la definición VIVA ----------------
-- REGLA_CONFIRMADA_POR_USUARIO (Luis, 05/10: «metele»): se AGREGA la rama 'frenada'; la regla
-- v23.65 (_tr_anulada, centinela 251) queda intacta y se verifica con gv_reglas_perdidas.
do $patch$
declare
  d text := pg_get_functiondef('public.gv_tanda_reservar(text,text,text,text)'::regprocedure);
  ancla text := '  if coalesce(r.legajo,'''') = l or public.es_legajo_test(coalesce(r.legajo,'''')) then';
  bloque text :=
    '  -- v26.61-frenada (Luis, 05/10): una tanda FRENADA la retoma el mismo operario sin cartel;' || chr(10) ||
    '  -- a otro se le contesta ''frenada'' (el cartel y gv_tanda_tomar_frenada son de la parte 2).' || chr(10) ||
    '  if r.estado = ''frenada'' then' || chr(10) ||
    '    if coalesce(r.legajo,'''') = l then' || chr(10) ||
    '      update public."GV_Tandas_Lock" set estado = ''tomada'', ts_estado = now() where tanda = t and fase = f;' || chr(10) ||
    '      update public."GV_Tanda_Freno" set retomada_por = l, retomada_nombre = nullif(btrim(coalesce(p_nombre,'''')),''''), retomada_ts = now()' || chr(10) ||
    '       where id = (select z.id from public."GV_Tanda_Freno" z where z.tanda = t and z.fase = f and z.retomada_ts is null order by z.ts_freno desc limit 1);' || chr(10) ||
    '      return jsonb_build_object(''ok'', true, ''motivo'', ''propia'', ''retomada'', true,' || chr(10) ||
    '        ''legajo'', r.legajo, ''nombre'', r.nombre, ''estado'', ''tomada'', ''desde'', r.ts);' || chr(10) ||
    '    end if;' || chr(10) ||
    '    return jsonb_build_object(''ok'', false, ''motivo'', ''frenada'',' || chr(10) ||
    '      ''legajo'', r.legajo, ''nombre'', r.nombre, ''estado'', r.estado, ''desde'', r.ts_estado);' || chr(10) ||
    '  end if;' || chr(10);
begin
  if position('v26.61-frenada' in d) > 0 then
    raise notice 'gv_tanda_reservar ya tiene la rama frenada: no se toca';
    return;
  end if;
  if position(ancla in d) = 0 then
    raise exception 'gv_tanda_reservar: no encontré el ancla (otra sesión la cambió) — no se aplica';
  end if;
  if position('_tr_anulada' in d) = 0 then
    raise exception 'gv_tanda_reservar: falta la regla v23.65 (_tr_anulada) — no se aplica';
  end if;
  execute replace(d, ancla, bloque || ancla);
end $patch$;

-- 5) OTRO OPERARIO SE LLEVA UNA FRENADA (después del cartel) -----------------------------
create or replace function public.gv_tanda_tomar_frenada(
  p_tanda text, p_fase text, p_legajo text, p_nombre text default null)
returns jsonb
language plpgsql security definer set search_path to 'public'
as $function$
-- v26.61-tomar (Luis, 05/10): «Estás por agarrar una tanda que empezó A ¿Seguro?» → sí.
declare
  t text := upper(btrim(coalesce(p_tanda,'')));
  f text := lower(btrim(coalesce(p_fase,'')));
  l text := btrim(coalesce(p_legajo,''));
  n text := nullif(btrim(coalesce(p_nombre,'')),'');
  r public."GV_Tandas_Lock";
  o public."GV_Tandas_Lock";
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
  update public."GV_Tandas_Lock"
     set estado = 'tomada', legajo = l, nombre = n, ts = now(), ts_estado = now()
   where tanda = t and fase = f;
  update public."GV_Tanda_Freno" set retomada_por = l, retomada_nombre = n, retomada_ts = now()
   where id = (select z.id from public."GV_Tanda_Freno" z where z.tanda = t and z.fase = f
                 and z.retomada_ts is null order by z.ts_freno desc limit 1);
  return jsonb_build_object('ok', true, 'motivo', case when coalesce(r.legajo,'') = l then 'propia' else 'tomada_de' end,
    'legajo_anterior', r.legajo, 'nombre_anterior', r.nombre);
end $function$;
revoke all on function public.gv_tanda_tomar_frenada(text,text,text,text) from public;
grant execute on function public.gv_tanda_tomar_frenada(text,text,text,text) to anon, authenticated;

-- 6) COPIA DEL AVANCE DEL ARMADO --------------------------------------------------------
create table if not exists public."GV_Armado_Avance" (
  tanda          text primary key,
  legajo         text,
  dispositivo    text,
  app            text,
  estado         text not null default 'en_curso' check (estado in ('en_curso','terminado','anulado')),
  step           int,
  nps            int,
  nps_listas     int,
  lios           int,
  cajas_en_lios  numeric,
  snapshot       jsonb,
  ts_cliente     timestamptz not null,
  creado_en      timestamptz not null default now(),
  actualizado_en timestamptz not null default now()
);
alter table public."GV_Armado_Avance" enable row level security;
revoke all on public."GV_Armado_Avance" from anon, authenticated;

create or replace function public.gv_armado_avance_guardar(
  p_tanda text, p_legajo text, p_estado text, p_ts_cliente timestamptz,
  p_snapshot jsonb default null, p_dispositivo text default null, p_app text default null)
returns text
language plpgsql security definer set search_path to 'public'
as $function$
-- v26.61-avance: la última foto del asistente de armado, una fila por tanda. Sin lectores
-- hasta la parte 2. Reglas: el legajo de prueba no guarda; desde el MISMO celular no pisa
-- con una foto más vieja (un reintento atrasado); una TERMINADA sólo la pisa una foto posterior.
declare
  t text := upper(btrim(coalesce(p_tanda,'')));
  l text := btrim(coalesce(p_legajo,''));
  e text := lower(btrim(coalesce(p_estado,'en_curso')));
  n int;
begin
  if t = '' or p_ts_cliente is null or e not in ('en_curso','terminado','anulado') then return 'datos_invalidos'; end if;
  if public.es_legajo_test(l) then return 'prueba'; end if;
  if p_snapshot is not null and pg_column_size(p_snapshot) > 2000000 then return 'grande'; end if;
  insert into public."GV_Armado_Avance" as a
    (tanda, legajo, dispositivo, app, estado, step, nps, nps_listas, lios, cajas_en_lios, snapshot, ts_cliente)
  select t, nullif(l,''), p_dispositivo, p_app, e,
         (p_snapshot ->> 'step')::int,
         jsonb_array_length(coalesce(p_snapshot -> 'nps', '[]'::jsonb)),
         (select count(*) from jsonb_array_elements(coalesce(p_snapshot -> 'nps', '[]'::jsonb)) x
           where (x ->> 'liosDone')::boolean is true),
         (select coalesce(sum(jsonb_array_length(coalesce(x -> 'liosArr', '[]'::jsonb))), 0)
            from jsonb_array_elements(coalesce(p_snapshot -> 'nps', '[]'::jsonb)) x),
         (select coalesce(sum((y ->> 'cajas')::numeric), 0)
            from jsonb_array_elements(coalesce(p_snapshot -> 'nps', '[]'::jsonb)) x,
                 jsonb_array_elements(coalesce(x -> 'liosArr', '[]'::jsonb)) y),
         p_snapshot, p_ts_cliente
  on conflict (tanda) do update set
         legajo = coalesce(excluded.legajo, a.legajo),
         dispositivo = excluded.dispositivo, app = excluded.app, estado = excluded.estado,
         step = coalesce(excluded.step, a.step),
         nps = case when excluded.snapshot is null then a.nps else excluded.nps end,
         nps_listas = case when excluded.snapshot is null then a.nps_listas else excluded.nps_listas end,
         lios = case when excluded.snapshot is null then a.lios else excluded.lios end,
         cajas_en_lios = case when excluded.snapshot is null then a.cajas_en_lios else excluded.cajas_en_lios end,
         snapshot = coalesce(excluded.snapshot, a.snapshot),
         ts_cliente = excluded.ts_cliente, actualizado_en = now()
   where (a.estado <> 'terminado' and (excluded.dispositivo is distinct from a.dispositivo
                                       or excluded.ts_cliente >= a.ts_cliente))
      or (a.estado = 'terminado' and excluded.ts_cliente > a.ts_cliente);
  get diagnostics n = row_count;
  return case when n = 0 then 'viejo' else 'ok' end;
end $function$;
revoke all on function public.gv_armado_avance_guardar(text,text,text,timestamptz,jsonb,text,text) from public;
grant execute on function public.gv_armado_avance_guardar(text,text,text,timestamptz,jsonb,text,text) to anon, authenticated;

create or replace function public.gv_armado_avance_leer(p_tanda text)
returns jsonb
language sql stable security definer set search_path to 'public'
as $function$
  select to_jsonb(a) from public."GV_Armado_Avance" a where a.tanda = upper(btrim(coalesce(p_tanda,'')));
$function$;
revoke all on function public.gv_armado_avance_leer(text) from public;
grant execute on function public.gv_armado_avance_leer(text) to anon, authenticated;

-- 7) CENTINELAS --------------------------------------------------------------------------
insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
select * from (values
  ('gv_tanda_reservar', 'funcion', 'r\.estado = ''frenada''',
   'una tanda FRENADA la retoma el mismo operario sin cartel; a otro se le contesta frenada (no se abre una tanda con la que otro está trabajando)', 'Luis', 'v26.61'),
  ('gv_tanda_frenar', 'funcion', 'fj\.opcion = ''FJ''',
   'el freno por fichaje sólo vale si el dueño fichó salida después de tomar la tanda', 'Luis', 'v26.61'),
  ('gv_armado_avance_guardar', 'funcion', 'excluded\.ts_cliente >= a\.ts_cliente',
   'la copia del armado no se pisa con una foto más vieja del mismo celular', 'Luis', 'v26.61')
) v(objeto, clase, patron, regla, quien_pidio, version)
where not exists (select 1 from public."GV_Reglas_Centinela" c where c.objeto = v.objeto and c.patron = v.patron);

-- =====================================================================================
-- ROLLBACK (todo junto, en este orden):
--   do $rb$ begin
--     execute (select def from zz_backups."GV_Backup_TandaFreno_defs_20261005" where objeto = 'gv_tanda_reservar');
--   end $rb$;
--   update public."GV_Tandas_Lock" set estado = 'tomada' where estado = 'frenada';
--   alter table public."GV_Tandas_Lock" drop constraint gv_tandas_lock_estado;
--   alter table public."GV_Tandas_Lock" add constraint gv_tandas_lock_estado
--     check (estado = any (array['tomada'::text, 'completada'::text]));
--   drop function if exists public.gv_tanda_frenar(text,text,text,text,text);
--   drop function if exists public.gv_tanda_tomar_frenada(text,text,text,text);
--   drop function if exists public.gv_armado_avance_guardar(text,text,text,timestamptz,jsonb,text,text);
--   drop function if exists public.gv_armado_avance_leer(text);
--   -- las dos tablas nuevas: respaldar antes si tienen filas que interesen
--   drop table if exists public."GV_Tanda_Freno";
--   drop table if exists public."GV_Armado_Avance";
--   delete from public."GV_Reglas_Centinela" where version = 'v26.61';
-- =====================================================================================
