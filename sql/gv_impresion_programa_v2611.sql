-- ⛔ RETIRADO EN LA v26.26 (Luis, 02/10/2026: "me quedo con mi helper, sacá lo otro").
-- El front ya no usa nada de esto. Los objetos se borran con el ROLLBACK de abajo cuando Luis diga «sí».
-- Al 02/10: GV_Impresion_PC 0 filas · _Regla 0 · _Trabajo 0 · _Clave 1 (la clave del programa) · 0 crons · 0 centinelas.
-- =====================================================================
-- v26.11 (Luis, 02/10/2026) — IMPRESIÓN POR PROGRAMA EN LA PC (sin kiosco de Chrome)
-- (La app salió como v26.12: otra sesión publicó la v26.11 en el medio. En la base las funciones
--  dicen v26.11 y la migración se llama gv_impresion_programa_v2611: no cambiar esa etiqueta.)
-- ---------------------------------------------------------------------
-- Luis: "en GV tengas en configuraciones la opción de elegir diferentes impresoras
-- conectadas a la máquina para elegir dónde se imprime cada cosa … y la opción de
-- activar la impresión automática". La PC del depósito no puede abrir Chrome en kiosco.
--
-- El navegador NO puede ver ni elegir impresoras (window.print siempre abre el cuadro;
-- --kiosk-printing manda todo a una sola). Lo resuelve un programa en la PC
-- (tools/impresion/GV-Impresion.ps1, mismo esquema que el de etiquetas de lío):
--
--   GV (picking TP · armado TAL · facturado al exportar el Excel ISIS)
--     → gv_imp_encolar(tipo, ref, html)         una fila en GV_Impresion_Trabajo
--   programa en la PC (cada 5 s)
--     → gv_imp_agente_latido(...)               avisa que vive + sus impresoras
--     → gv_imp_agente_tomar(...)                toma lo suyo
--     → Chrome headless → PNG → impresora elegida
--     → gv_imp_agente_resultado(...)            impreso / error (y marca Impresion_NP)
--   GV → Configuración → Impresoras
--     → gv_imp_config() / gv_imp_regla_guardar(...) / gv_imp_trabajos() / gv_imp_trabajo_reintentar()
--
-- SIN REGLA CARGADA PARA UN TIPO, GV SIGUE COMO HOY (estación del navegador / fac_print_facturado).
-- Objetos NUEVOS (prefijo GV_ / gv_imp_). No se toca ningún objeto existente; la única
-- escritura sobre una tabla vieja es el insert en Impresion_NP que hace
-- gv_imp_agente_resultado cuando el programa CONFIRMA que imprimió (antes se marcaba
-- al mandar, aunque el papel no saliera).
--
-- ROLLBACK (deja todo como antes; GV vuelve solo al navegador porque no hay reglas):
--   drop function if exists public.gv_imp_trabajo_reintentar(bigint);
--   drop function if exists public.gv_imp_trabajos(integer);
--   drop function if exists public.gv_imp_encolar(text,text,text,text,text,text);
--   drop function if exists public.gv_imp_regla_guardar(text,text,text,boolean,integer);
--   drop function if exists public.gv_imp_config();
--   drop function if exists public.gv_imp_agente_resultado(text,text,bigint,boolean,text);
--   drop function if exists public.gv_imp_agente_tomar(text,text,integer);
--   drop function if exists public.gv_imp_agente_latido(text,text,jsonb,text,text);
--   drop function if exists public._gv_imp_clave_ok(text);
--   drop table if exists public."GV_Impresion_Trabajo", public."GV_Impresion_Regla",
--                        public."GV_Impresion_PC", public."GV_Impresion_Clave";
-- =====================================================================

-- ---------- tablas ----------
create table if not exists public."GV_Impresion_PC" (
  pc            text primary key,                       -- nombre de Windows ($env:COMPUTERNAME)
  impresoras    jsonb not null default '[]'::jsonb,     -- [{"nombre":"HP M404","predeterminada":true}]
  version       text,
  chrome        text,                                   -- ruta del Chrome/Edge que usa para dibujar ('' = no encontró)
  ultimo_latido timestamptz,
  creado_en     timestamptz not null default now()
);

create table if not exists public."GV_Impresion_Regla" (
  tipo           text primary key check (tipo in ('picking','armado','facturado')),
  pc             text,                                  -- null = sin programa → GV imprime como hoy
  impresora      text,
  auto           boolean not null default false,
  copias         integer not null default 1 check (copias between 1 and 5),
  actualizado_por text,
  actualizado_en timestamptz not null default now()
);

create table if not exists public."GV_Impresion_Trabajo" (
  id          bigserial primary key,
  tipo        text not null check (tipo in ('picking','armado','facturado','prueba')),
  ref         text not null,                            -- tanda (picking) · NP (armado/facturado)
  pc          text not null,
  impresora   text not null,
  copias      integer not null default 1,
  html        text,                                     -- documento completo; se vacía a los 7 días
  estado      text not null default 'pendiente'
              check (estado in ('pendiente','imprimiendo','impreso','error','vencido','cancelado')),
  intentos    integer not null default 0,
  error       text,
  clave_unica text unique,                              -- tipo:ref en los automáticos (no se imprime dos veces); null en prueba/reimpresión
  origen      text,
  creado_por  text,
  creado_en   timestamptz not null default now(),
  tomado_en   timestamptz,
  impreso_en  timestamptz
);
create index if not exists gv_impresion_trabajo_cola_idx
  on public."GV_Impresion_Trabajo" (pc, id) where estado in ('pendiente','imprimiendo');
create index if not exists gv_impresion_trabajo_creado_idx
  on public."GV_Impresion_Trabajo" (creado_en desc);

-- La clave que el programa necesita para hablar con la base. La ve sólo un supervisor
-- (Configuración → Impresoras) y va en clave.txt de la carpeta compartida. Sin ella
-- cualquiera con la clave pública podría registrar PCs falsas o "tomar" trabajos.
create table if not exists public."GV_Impresion_Clave" (
  id        integer primary key default 1 check (id = 1),
  clave     text not null,
  creado_en timestamptz not null default now()
);
insert into public."GV_Impresion_Clave" (id, clave)
select 1, upper(substr(md5(gen_random_uuid()::text || clock_timestamp()::text), 1, 4) || '-' ||
                substr(md5(gen_random_uuid()::text || clock_timestamp()::text), 1, 4) || '-' ||
                substr(md5(gen_random_uuid()::text || clock_timestamp()::text), 1, 4) || '-' ||
                substr(md5(gen_random_uuid()::text || clock_timestamp()::text), 1, 4))
on conflict (id) do nothing;

alter table public."GV_Impresion_PC"      enable row level security;
alter table public."GV_Impresion_Regla"   enable row level security;
alter table public."GV_Impresion_Trabajo" enable row level security;
alter table public."GV_Impresion_Clave"   enable row level security;
revoke all on public."GV_Impresion_PC", public."GV_Impresion_Regla",
              public."GV_Impresion_Trabajo", public."GV_Impresion_Clave" from anon, authenticated;
revoke all on sequence public."GV_Impresion_Trabajo_id_seq" from anon, authenticated;

-- ---------- helper ----------
create or replace function public._gv_imp_clave_ok(p_clave text)
returns boolean language sql stable security definer set search_path to 'public' as $$
  select exists (select 1 from public."GV_Impresion_Clave"
                  where upper(btrim(clave)) = upper(btrim(coalesce(p_clave, ''))));
$$;

-- ---------- lo que llama el PROGRAMA (clave pública + clave.txt) ----------
create or replace function public.gv_imp_agente_latido(
  p_clave text, p_pc text, p_impresoras jsonb, p_version text, p_chrome text)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
-- v26.11 — el programa avisa que vive y qué impresoras tiene la PC. Devuelve qué tipos
-- tiene asignados esa PC, para que lo muestre en su ventana.
declare v_pc text := upper(btrim(coalesce(p_pc, '')));
begin
  if not public._gv_imp_clave_ok(p_clave) then raise exception 'CLAVE_INVALIDA'; end if;
  if v_pc = '' or length(v_pc) > 64 then raise exception 'Falta el nombre de la PC'; end if;
  if p_impresoras is null or jsonb_typeof(p_impresoras) <> 'array' then p_impresoras := '[]'::jsonb; end if;

  insert into public."GV_Impresion_PC" (pc, impresoras, version, chrome, ultimo_latido)
  values (v_pc, p_impresoras, left(p_version, 40), left(p_chrome, 300), now())
  on conflict (pc) do update
     set impresoras = excluded.impresoras, version = excluded.version,
         chrome = excluded.chrome, ultimo_latido = now();

  -- limpieza: el html de lo viejo no sirve más (la fila queda como registro)
  update public."GV_Impresion_Trabajo" set html = null
   where html is not null and creado_en < now() - interval '7 days';

  return jsonb_build_object('ok', true, 'pc', v_pc,
    'reglas', coalesce((select jsonb_agg(jsonb_build_object('tipo', r.tipo, 'impresora', r.impresora,
                                                            'auto', r.auto, 'copias', r.copias) order by r.tipo)
                          from public."GV_Impresion_Regla" r where r.pc = v_pc), '[]'::jsonb));
end $$;

create or replace function public.gv_imp_agente_tomar(p_clave text, p_pc text, p_limite integer default 5)
returns table (id bigint, tipo text, ref text, impresora text, copias integer, html text)
language plpgsql security definer set search_path to 'public' as $$
#variable_conflict use_column
-- v26.11 — el programa toma los trabajos de SU PC. SKIP LOCKED: dos ventanas abiertas en
-- la misma PC nunca imprimen la misma hoja. Lo pendiente de más de 12 h se vence (no se
-- vuelca un día entero de golpe si la PC estuvo apagada).
declare v_pc text := upper(btrim(coalesce(p_pc, '')));
begin
  if not public._gv_imp_clave_ok(p_clave) then raise exception 'CLAVE_INVALIDA'; end if;
  update public."GV_Impresion_PC" set ultimo_latido = now() where pc = v_pc;

  update public."GV_Impresion_Trabajo" t
     set estado = 'vencido', error = 'más de 12 h esperando: no se imprimió'
   where t.pc = v_pc and t.estado = 'pendiente' and t.creado_en < now() - interval '12 hours';
  update public."GV_Impresion_Trabajo" t
     set estado = 'error', error = coalesce(t.error, '') || ' · se trabó 3 veces imprimiendo'
   where t.pc = v_pc and t.estado = 'imprimiendo' and t.tomado_en < now() - interval '5 minutes'
     and t.intentos >= 3;

  return query
  with c as (
    select t.id from public."GV_Impresion_Trabajo" t
     where t.pc = v_pc
       and (t.estado = 'pendiente'
            or (t.estado = 'imprimiendo' and t.tomado_en < now() - interval '5 minutes'))
     order by t.id
     limit greatest(1, least(coalesce(p_limite, 5), 20))
     for update skip locked
  )
  update public."GV_Impresion_Trabajo" t
     set estado = 'imprimiendo', tomado_en = now(), intentos = t.intentos + 1
    from c where t.id = c.id
  returning t.id, t.tipo, t.ref, t.impresora, t.copias, t.html;
end $$;

create or replace function public.gv_imp_agente_resultado(
  p_clave text, p_pc text, p_id bigint, p_ok boolean, p_error text)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
-- v26.11 — el programa dice si salió. Recién acá se marca Impresion_NP (la Cola de
-- impresión deja de acusar esa hoja): marcar al MANDAR decía "impreso" sin papel.
declare v_pc text := upper(btrim(coalesce(p_pc, ''))); t record;
begin
  if not public._gv_imp_clave_ok(p_clave) then raise exception 'CLAVE_INVALIDA'; end if;
  select * into t from public."GV_Impresion_Trabajo" w where w.id = p_id and w.pc = v_pc for update;
  if not found then return jsonb_build_object('ok', false, 'motivo', 'no existe en esta PC'); end if;

  if coalesce(p_ok, false) then
    update public."GV_Impresion_Trabajo"
       set estado = 'impreso', impreso_en = now(), error = null where id = p_id;
    if t.tipo = 'armado' then
      insert into public."Impresion_NP" (np, gv_origen) values (t.ref, 'programa') on conflict (np) do nothing;
    elsif t.tipo = 'picking' then
      insert into public."Impresion_NP" (np, gv_origen) values ('PK ' || t.ref, 'programa') on conflict (np) do nothing;
    end if;
    return jsonb_build_object('ok', true, 'estado', 'impreso');
  end if;

  update public."GV_Impresion_Trabajo"
     set estado = case when t.intentos >= 3 then 'error' else 'pendiente' end,
         error  = left(coalesce(p_error, 'sin detalle'), 500)
   where id = p_id;
  return jsonb_build_object('ok', true, 'estado', case when t.intentos >= 3 then 'error' else 'pendiente' end);
end $$;

-- ---------- lo que llama GV ----------
create or replace function public.gv_imp_config()
returns jsonb language sql stable security definer set search_path to 'public' as $$
-- v26.11 — PCs con programa, sus impresoras y las reglas. La CLAVE sólo para supervisor.
  select jsonb_build_object(
    'pcs', coalesce((select jsonb_agg(jsonb_build_object(
              'pc', p.pc, 'impresoras', p.impresoras, 'version', p.version, 'chrome', p.chrome,
              'ultimo_latido', p.ultimo_latido,
              'vivo', coalesce(p.ultimo_latido > now() - interval '2 minutes', false),
              'pendientes', (select count(*) from public."GV_Impresion_Trabajo" t
                              where t.pc = p.pc and t.estado in ('pendiente','imprimiendo')))
            order by p.ultimo_latido desc nulls last) from public."GV_Impresion_PC" p), '[]'::jsonb),
    'reglas', coalesce((select jsonb_agg(jsonb_build_object(
              'tipo', r.tipo, 'pc', r.pc, 'impresora', r.impresora, 'auto', r.auto, 'copias', r.copias,
              'actualizado_por', r.actualizado_por, 'actualizado_en', r.actualizado_en) order by r.tipo)
            from public."GV_Impresion_Regla" r), '[]'::jsonb),
    'clave', case when (public.es_supervisor_virgilio() or public.gv_es_supervisor_o_servicio())
                  then (select clave from public."GV_Impresion_Clave" where id = 1) end);
$$;

create or replace function public.gv_imp_regla_guardar(
  p_tipo text, p_pc text, p_impresora text, p_auto boolean, p_copias integer)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
-- v26.11 — dónde se imprime cada tipo. pc/impresora en null = sin programa (GV como hoy).
declare v_pc text := nullif(upper(btrim(coalesce(p_pc, ''))), '');
        v_imp text := nullif(btrim(coalesce(p_impresora, '')), '');
begin
  if not (public.es_supervisor_virgilio() or public.gv_es_supervisor_o_servicio()) then
    raise exception 'Solo supervisores';
  end if;
  if p_tipo not in ('picking','armado','facturado') then raise exception 'Tipo desconocido: %', p_tipo; end if;
  if (v_pc is null) <> (v_imp is null) then raise exception 'Elegí la PC y la impresora, o ninguna'; end if;
  if v_pc is not null then
    if not exists (select 1 from public."GV_Impresion_PC" where pc = v_pc) then
      raise exception 'La PC % no tiene el programa de impresión', v_pc;
    end if;
    if not exists (select 1 from public."GV_Impresion_PC" p, jsonb_array_elements(p.impresoras) e
                    where p.pc = v_pc and e->>'nombre' = v_imp) then
      raise exception 'La impresora "%" no está en la PC %', v_imp, v_pc;
    end if;
  end if;

  insert into public."GV_Impresion_Regla" (tipo, pc, impresora, auto, copias, actualizado_por, actualizado_en)
  values (p_tipo, v_pc, v_imp, coalesce(p_auto, false), greatest(1, least(coalesce(p_copias, 1), 5)),
          auth.jwt() ->> 'email', now())
  on conflict (tipo) do update
     set pc = excluded.pc, impresora = excluded.impresora, auto = excluded.auto,
         copias = excluded.copias, actualizado_por = excluded.actualizado_por, actualizado_en = now();

  return (select to_jsonb(r) from public."GV_Impresion_Regla" r where r.tipo = p_tipo);
end $$;

create or replace function public.gv_imp_encolar(
  p_tipo text, p_ref text, p_html text, p_origen text default null,
  p_pc text default null, p_impresora text default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
-- v26.11 — GV manda una hoja al programa. Sin p_pc: va por la REGLA del tipo y es
-- automática (clave tipo:ref → la misma hoja no sale dos veces aunque la manden dos PCs).
-- Con p_pc + p_impresora: prueba o reimpresión a mano (sin clave única).
-- Devuelve estado: encolado · duplicado · sin_regla (GV imprime como hoy) · apagado.
declare r record; v_pc text; v_imp text; v_cop integer := 1; v_manual boolean; v_id bigint;
begin
  if not (public.es_supervisor_virgilio() or public.gv_es_supervisor_o_servicio()) then
    raise exception 'Solo supervisores';
  end if;
  if p_tipo not in ('picking','armado','facturado','prueba') then raise exception 'Tipo desconocido: %', p_tipo; end if;
  if coalesce(btrim(p_ref), '') = '' then raise exception 'Falta la referencia (NP o tanda)'; end if;
  if coalesce(length(p_html), 0) < 20 or length(p_html) > 2000000 then raise exception 'Hoja vacía o demasiado grande'; end if;

  v_manual := nullif(btrim(coalesce(p_pc, '')), '') is not null;
  if v_manual then
    v_pc := upper(btrim(p_pc)); v_imp := nullif(btrim(coalesce(p_impresora, '')), '');
    if v_imp is null then raise exception 'Falta la impresora'; end if;
  else
    if p_tipo = 'prueba' then raise exception 'La prueba va con PC e impresora'; end if;
    select * into r from public."GV_Impresion_Regla" g where g.tipo = p_tipo;
    if not found or r.pc is null or r.impresora is null then
      return jsonb_build_object('estado', 'sin_regla');
    end if;
    if not r.auto then return jsonb_build_object('estado', 'apagado'); end if;
    v_pc := r.pc; v_imp := r.impresora; v_cop := r.copias;
  end if;

  insert into public."GV_Impresion_Trabajo"
         (tipo, ref, pc, impresora, copias, html, clave_unica, origen, creado_por)
  values (p_tipo, btrim(p_ref), v_pc, v_imp, v_cop, p_html,
          case when v_manual then null else p_tipo || ':' || upper(btrim(p_ref)) end,
          left(p_origen, 40), auth.jwt() ->> 'email')
  on conflict (clave_unica) do nothing
  returning id into v_id;

  if v_id is null then return jsonb_build_object('estado', 'duplicado', 'pc', v_pc, 'impresora', v_imp); end if;
  return jsonb_build_object('estado', 'encolado', 'id', v_id, 'pc', v_pc, 'impresora', v_imp,
    'pc_viva', coalesce((select ultimo_latido > now() - interval '2 minutes'
                           from public."GV_Impresion_PC" where pc = v_pc), false));
end $$;

create or replace function public.gv_imp_trabajos(p_limite integer default 40)
returns table (id bigint, tipo text, ref text, pc text, impresora text, estado text, intentos integer,
               error text, origen text, creado_por text, creado_en timestamptz, impreso_en timestamptz)
language plpgsql stable security definer set search_path to 'public' as $$
#variable_conflict use_column
begin
  if not (public.es_supervisor_virgilio() or public.gv_es_supervisor_o_servicio()) then
    raise exception 'Solo supervisores';
  end if;
  return query
  select t.id, t.tipo, t.ref, t.pc, t.impresora, t.estado, t.intentos, t.error, t.origen,
         t.creado_por, t.creado_en, t.impreso_en
    from public."GV_Impresion_Trabajo" t
   order by t.id desc
   limit greatest(1, least(coalesce(p_limite, 40), 200));
end $$;

create or replace function public.gv_imp_trabajo_reintentar(p_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
-- v26.11 — vuelve a mandar una hoja con error o vencida (si todavía tiene el html).
declare n integer;
begin
  if not (public.es_supervisor_virgilio() or public.gv_es_supervisor_o_servicio()) then
    raise exception 'Solo supervisores';
  end if;
  update public."GV_Impresion_Trabajo"
     set estado = 'pendiente', intentos = 0, error = null, creado_en = now(), tomado_en = null
   where id = p_id and estado in ('error','vencido','cancelado') and html is not null;
  get diagnostics n = row_count;
  return jsonb_build_object('ok', n = 1);
end $$;

-- ---------- permisos ----------
revoke execute on function public._gv_imp_clave_ok(text) from public, anon, authenticated;
revoke execute on function public.gv_imp_agente_latido(text,text,jsonb,text,text) from public;
revoke execute on function public.gv_imp_agente_tomar(text,text,integer) from public;
revoke execute on function public.gv_imp_agente_resultado(text,text,bigint,boolean,text) from public;
revoke execute on function public.gv_imp_config() from public;
revoke execute on function public.gv_imp_regla_guardar(text,text,text,boolean,integer) from public, anon;
revoke execute on function public.gv_imp_encolar(text,text,text,text,text,text) from public, anon;
revoke execute on function public.gv_imp_trabajos(integer) from public, anon;
revoke execute on function public.gv_imp_trabajo_reintentar(bigint) from public, anon;

grant execute on function public.gv_imp_agente_latido(text,text,jsonb,text,text) to anon, authenticated;
grant execute on function public.gv_imp_agente_tomar(text,text,integer) to anon, authenticated;
grant execute on function public.gv_imp_agente_resultado(text,text,bigint,boolean,text) to anon, authenticated;
grant execute on function public.gv_imp_config() to anon, authenticated;
grant execute on function public.gv_imp_regla_guardar(text,text,text,boolean,integer) to authenticated;
grant execute on function public.gv_imp_encolar(text,text,text,text,text,text) to authenticated;
grant execute on function public.gv_imp_trabajos(integer) to authenticated;
grant execute on function public.gv_imp_trabajo_reintentar(bigint) to authenticated;
