-- v29.74 (Elías, 13/10/2026) — SEGURIDAD DEL CÓDIGO DE LA TV (Virgilio y Cervantes)
-- [Elías: «1 hay que cambiar» · «4 limitar a cada 2 seg. y hacer que solo sea aceptable el código anterior durante
--  5 segundos después que desaparece de la TV … y se le puede hacer que envíen su mac a los 6 intentos»]
--
-- PARTE A (no rompe nada) — APLICADA el 13/10/2026 (+ el lock v29.74-lock). Verificada por HTTP con la clave pública:
--   validar 'abcd' → codigo; 3 simultáneos → 1 codigo + 2 espera; GP2.monitor_clave_validar y gv_clave_chequear → 401;
--   gv_tv_clave_actual_tv('xx') → desconocida.
--   A1. GV_Clave_Intento + gv_clave_chequear(): el limitador ÚNICO de los 4 validadores del código de la TV.
--       · un intento FALLIDO desde una IP (o equipo) frena esa IP 2 s  → 'espera'
--       · el código del minuto anterior vale SÓLO los primeros 5 s del minuto nuevo (65 s de código activo)
--       · desde la 6.ª falla en 10 min, sin identificación del equipo no se valida → 'dispositivo'
--         (el navegador no da la MAC: se registra gv_dispositivo + huella + navegador + IP) y avisa por Telegram
--       · 10 fallas por equipo o 40 por IP en 10 min → 'bloqueo' (el mismo tope que ya tenía Cervantes)
--   A2. Los 4 validadores pasan por ahí: gv_tv_clave_validar (Gestión), reg_prod_3_0_virgilio_operarios (3.0 Virgilio),
--       reg_prod_3_0_cerv_ingresar (3.0 Cervantes + tablet GP2). GP2.monitor_clave_validar deja de ser llamable con la
--       clave pública (lo usaba sólo cerv_ingresar, que es SECURITY DEFINER).
--   A3. Vínculo de la TV: GV_TV_Pantalla + gv_tv_vincular_pedir / gv_tv_vincular_aprobar / gv_tv_pantallas / gv_tv_revocar
--       + gv_tv_clave_actual_tv(secreto). La TV guarda un secreto propio; un supervisor la aprueba con el código de 6 dígitos.
-- PARTE B (rompe la TV si no está vinculada: se aplica cuando Elías confirma que la TV ya muestra el código vinculada)
--   gv_tv_clave_actual() exige sesión de supervisor y se le saca a la clave pública.

-- ═══════════════════════════ A1 · limitador ═══════════════════════════
create table if not exists public."GV_Clave_Intento" (
  id bigserial primary key,
  at timestamptz not null default now(),
  app text not null,
  ip text, dispositivo text, huella text, navegador text,
  ok boolean not null,
  motivo text
);
create index if not exists gv_clave_intento_ip_idx on public."GV_Clave_Intento" (ip, at desc) where not ok;
create index if not exists gv_clave_intento_disp_idx on public."GV_Clave_Intento" (dispositivo, at desc) where not ok;
alter table public."GV_Clave_Intento" enable row level security;
revoke all on public."GV_Clave_Intento" from anon, authenticated;

create or replace function public.gv_clave_ip() returns text language plpgsql stable set search_path to '' as $f$
declare h jsonb;
begin
  begin h := coalesce(nullif(current_setting('request.headers', true), ''), '{}')::jsonb;
  exception when others then h := '{}'::jsonb; end;
  return coalesce(nullif(btrim(h->>'cf-connecting-ip'), ''),
                  nullif(btrim(split_part(coalesce(h->>'x-forwarded-for', ''), ',', 1)), ''),
                  nullif(btrim(h->>'x-real-ip'), ''));
end $f$;

-- p_sistema: 'virgilio' (gv_tv_clave_de) o 'cervantes' (GP2._monitor_clave_de)
-- -> {ok:true} | {ok:false, error:'codigo'|'espera'|'dispositivo'|'bloqueo'}
create or replace function public.gv_clave_chequear(p_sistema text, p_app text, p_clave text,
    p_dispositivo text, p_huella text, p_navegador text)
returns jsonb language plpgsql volatile security definer set search_path to '' as $f$
declare
  v_marca constant text := 'v29.74-clave';
  v_ip   text := public.gv_clave_ip();
  v_disp text := nullif(left(btrim(coalesce(p_dispositivo, '')), 80), '');
  v_c    text := regexp_replace(coalesce(p_clave, ''), '\D', '', 'g');
  v_seg  int  := floor(extract(epoch from now()))::bigint % 60;
  v_t    bigint := floor(extract(epoch from now()) / 60)::bigint;
  v_f_ip int := 0; v_f_disp int := 0; v_ult timestamptz; v_ok boolean;
begin
  -- 1 intento cada 2 s después de una falla (por IP; sin IP, por equipo)
  -- dos intentos simultáneos de la misma IP no se ven entre sí: se serializan (medido 13/10: 2 a 6 ms → los dos 'codigo')
  perform pg_advisory_xact_lock(hashtext('gv_clave:' || coalesce(v_ip, v_disp, '?'))::bigint);  -- v29.74-lock
  select max(at) into v_ult from public."GV_Clave_Intento"
   where not ok and at > now() - interval '2 seconds'
     and ((v_ip is not null and ip = v_ip) or (v_ip is null and v_disp is not null and dispositivo = v_disp));
  if v_ult is not null then return jsonb_build_object('ok', false, 'error', 'espera'); end if;

  if v_ip is not null then
    select count(*) into v_f_ip from public."GV_Clave_Intento" where not ok and at > now() - interval '10 minutes' and ip = v_ip;
  end if;
  if v_disp is not null then
    select count(*) into v_f_disp from public."GV_Clave_Intento" where not ok and at > now() - interval '10 minutes' and dispositivo = v_disp;
  end if;
  if v_f_disp >= 10 or v_f_ip >= 40 then
    insert into public."GV_Clave_Intento" (app, ip, dispositivo, huella, navegador, ok, motivo)
    values (p_app, v_ip, v_disp, left(p_huella, 120), left(p_navegador, 200), false, 'bloqueo');
    return jsonb_build_object('ok', false, 'error', 'bloqueo');
  end if;
  -- desde la 6.ª falla: sin identificar el equipo no se valida, y se avisa
  if greatest(v_f_ip, v_f_disp) >= 6 then
    if v_disp is null then
      insert into public."GV_Clave_Intento" (app, ip, dispositivo, huella, navegador, ok, motivo)
      values (p_app, v_ip, null, left(p_huella, 120), left(p_navegador, 200), false, 'dispositivo');
      return jsonb_build_object('ok', false, 'error', 'dispositivo');
    end if;
    begin
      perform public.tg_enqueue(
        '🔐 CÓDIGO DE LA TV — ' || greatest(v_f_ip, v_f_disp) || ' intentos fallidos en 10 min (' || p_app || ')' || E'\n' ||
        'IP ' || coalesce(v_ip, '¿?') || ' · equipo ' || left(v_disp, 12) ||
        coalesce(E'\n' || left(p_navegador, 120), ''),
        'gv_clave_6_' || coalesce(v_ip, v_disp) || '_' || to_char(now(), 'YYYYMMDDHH24'));
    exception when others then null; end;
  end if;

  if v_c ~ '^\d{4}$' then
    if p_sistema = 'cervantes' then
      v_ok := v_c = "GP2"._monitor_clave_de(v_t) or (v_seg < 5 and v_c = "GP2"._monitor_clave_de(v_t - 1));
    else
      v_ok := v_c = public.gv_tv_clave_de(v_t) or (v_seg < 5 and v_c = public.gv_tv_clave_de(v_t - 1));
    end if;
  else v_ok := false; end if;

  insert into public."GV_Clave_Intento" (app, ip, dispositivo, huella, navegador, ok, motivo)
  values (p_app, v_ip, v_disp, left(p_huella, 120), left(p_navegador, 200), v_ok, case when v_ok then null else 'codigo' end);
  if not v_ok then return jsonb_build_object('ok', false, 'error', 'codigo'); end if;
  return jsonb_build_object('ok', true);
end $f$;
revoke all on function public.gv_clave_chequear(text, text, text, text, text, text) from public, anon, authenticated;

-- ═══════════════════════════ A2 · los validadores ═══════════════════════════
-- Gestión Virgilio: la lista de operarios sale igual que antes; sólo cambia la puerta.
create or replace function public.gv_tv_clave_operarios() returns jsonb language sql stable security definer
set search_path to '' as $f$
  -- v23.84: los que trabajaron en Virgilio en 15 días. v23.85: apodos 104 J. Colombia, 277 Jhonny.
  -- v27.37: + operarios validados a mano (GV_Operario_Alta), aunque no tengan eventos todavía.
  select coalesce((
    with base as (
      select btrim(e."Legajo") legajo,
             case btrim(e."Legajo") when '104' then 'J. Colombia' when '277' then 'Jhonny'
                  else btrim(e."Empleado") end nombre
        from public."Empleados" e
       where upper(btrim(coalesce(e."Activo", ''))) <> 'NO'
         and btrim(coalesce(e."Legajo", '')) not in ('', '0', '1', '600')
         and btrim(coalesce(e."Empleado", '')) <> ''
         and exists (select 1 from public."Registros_Produccion_Virgilio" r
                      where r.ts_cliente >= now() - interval '15 days'
                        and btrim(r.legajo::text) = btrim(e."Legajo"))),
    val as (
      select btrim(a.legajo) legajo, btrim(a.nombre) nombre
        from public."GV_Operario_Alta" a
       where a.estado = 'validado' and btrim(coalesce(a.legajo,'')) not in ('','0','1','600')),
    u as (
      select legajo, nombre from base
      union
      select v.legajo, v.nombre from val v where not exists (select 1 from base b where b.legajo = v.legajo))
    select jsonb_agg(jsonb_build_object('legajo', legajo, 'nombre', nombre) order by nombre) from u), '[]'::jsonb);
$f$;
revoke all on function public.gv_tv_clave_operarios() from public, anon, authenticated;

create or replace function public.gv_tv_clave_validar(p_clave text, p_dispositivo text, p_huella text, p_navegador text)
returns jsonb language plpgsql volatile security definer set search_path to '' as $f$
declare v jsonb;
begin
  v := public.gv_clave_chequear('virgilio', 'gestion', p_clave, p_dispositivo, p_huella, p_navegador);
  if not coalesce((v->>'ok')::boolean, false) then return v; end if;
  return jsonb_build_object('ok', true, 'operarios', public.gv_tv_clave_operarios());
end $f$;
revoke all on function public.gv_tv_clave_validar(text, text, text, text) from public;
grant execute on function public.gv_tv_clave_validar(text, text, text, text) to anon, authenticated;

-- la de un argumento (celulares sin actualizar): misma puerta, sin identificar el equipo
create or replace function public.gv_tv_clave_validar(p_clave text)
returns jsonb language plpgsql volatile security definer set search_path to '' as $f$
begin
  return public.gv_tv_clave_validar(p_clave, null, null, null);
end $f$;

-- 3.0 Virgilio
create or replace function reg_prod_3_0.reg_prod_3_0_virgilio_operarios(p_clave text, p_dispositivo text, p_huella text, p_navegador text)
returns jsonb language plpgsql volatile security definer set search_path to '' as $f$
declare v jsonb;
begin
  v := public.gv_clave_chequear('virgilio', 'virgilio-3.0', p_clave, p_dispositivo, p_huella, p_navegador);
  if not coalesce((v->>'ok')::boolean, false) then return v; end if;
  return jsonb_build_object('ok', true, 'operarios', coalesce((
    select jsonb_agg(jsonb_build_object('legajo', regexp_replace(o.legajo, '^c', ''), 'legajo_verdadero', o.legajo,
                                        'nombre', o.nombre) order by o.nombre)
      from reg_prod_3_0.operario o
     where o.legajo <> '0'), '[]'::jsonb));
end $f$;
revoke all on function reg_prod_3_0.reg_prod_3_0_virgilio_operarios(text, text, text, text) from public;
grant execute on function reg_prod_3_0.reg_prod_3_0_virgilio_operarios(text, text, text, text) to anon, authenticated;

create or replace function reg_prod_3_0.reg_prod_3_0_virgilio_operarios(p_clave text)
returns jsonb language plpgsql volatile security definer set search_path to '' as $f$
begin
  return reg_prod_3_0.reg_prod_3_0_virgilio_operarios(p_clave, null, null, null);
end $f$;

-- 3.0 Cervantes: el chequeo del código pasa por el limitador (se reemplaza la llamada a monitor_clave_validar
-- y el bloqueo propio, que ahora hace el limitador). Cirugía sobre la definición viva: frena si no calza.
do $$
declare d text; n int;
  v1 constant text := '  if v_f_disp >= 10 or v_f_ip >= 40 then';
  v2 constant text := $a$  if coalesce(("GP2".monitor_clave_validar(p_clave) ->> 'ok')::boolean, false) is not true then
    perform reg_prod_3_0.reg_prod_3_0_ingreso_log(p_app, v_leg, null, 'clave_tv', false, 'codigo', true,
                                                  p_dispositivo, p_huella, p_navegador, p_extra);
    return jsonb_build_object('ok', false, 'error', 'codigo');
  end if;$a$;
  n2 constant text := $a$  v_chk := public.gv_clave_chequear('cervantes', coalesce(p_app, 'cervantes'), p_clave, p_dispositivo, p_huella, p_navegador);   /* v29.74-clave */
  if coalesce((v_chk->>'ok')::boolean, false) is not true then
    perform reg_prod_3_0.reg_prod_3_0_ingreso_log(p_app, v_leg, null, 'clave_tv', false, coalesce(v_chk->>'error', 'codigo'), true,
                                                  p_dispositivo, p_huella, p_navegador, p_extra);
    return jsonb_build_object('ok', false, 'error', coalesce(v_chk->>'error', 'codigo'));
  end if;$a$;
begin
  select pg_get_functiondef(p.oid) into d from pg_proc p
   where p.pronamespace = 'reg_prod_3_0'::regnamespace and p.proname = 'reg_prod_3_0_cerv_ingresar';
  if strpos(d, 'v29.74-clave') > 0 then raise notice 'cerv_ingresar ya tiene el limitador'; return; end if;
  foreach n in array array[(length(d) - length(replace(d, v1, ''))) / length(v1),
                           (length(d) - length(replace(d, v2, ''))) / length(v2)] loop
    if n <> 1 then raise exception 'cerv_ingresar: un texto a reemplazar aparece % veces', n; end if;
  end loop;
  d := replace(d, v1, '  if false and (v_f_disp >= 10 or v_f_ip >= 40) then   /* v29.74: el bloqueo lo hace gv_clave_chequear */');
  d := replace(d, v2, n2);
  d := replace(d, E'  v_nombre text;\n', E'  v_nombre text;\n  v_chk    jsonb;\n');
  if strpos(d, 'v_chk    jsonb;') = 0 then raise exception 'cerv_ingresar: no encuentro el declare'; end if;
  execute d;
end $$;

-- GP2.monitor_clave_validar: ya no se llama directo con la clave pública (sólo desde cerv_ingresar)
revoke execute on function "GP2".monitor_clave_validar(text) from public, anon, authenticated;

-- ═══════════════════════════ A3 · vínculo de la TV ═══════════════════════════
create table if not exists public."GV_TV_Pantalla" (
  id bigserial primary key,
  nombre text,
  secreto_hash text not null unique,
  codigo_vinc text,
  estado text not null default 'pendiente' check (estado in ('pendiente', 'activa', 'revocada')),
  ip text, navegador text,
  creado_en timestamptz not null default now(),
  pedido_en timestamptz not null default now(),
  aprobado_por text, aprobado_en timestamptz,
  ultimo_uso timestamptz
);
alter table public."GV_TV_Pantalla" enable row level security;
revoke all on public."GV_TV_Pantalla" from anon, authenticated;

create or replace function public.gv_tv_hash(p_secreto text) returns text language sql immutable set search_path to '' as $f$
  select encode(extensions.digest(coalesce(p_secreto, ''), 'sha256'), 'hex');
$f$;
revoke all on function public.gv_tv_hash(text) from public, anon, authenticated;

-- La TV pide el alta con su secreto (lo genera ella y lo guarda). Devuelve el código de 6 dígitos para que un
-- supervisor la apruebe. Vence a los 30 min (la TV vuelve a pedir y sale otro código).
create or replace function public.gv_tv_vincular_pedir(p_secreto text, p_navegador text)
returns jsonb language plpgsql volatile security definer set search_path to '' as $f$
declare v_h text; r record; v_ip text := public.gv_clave_ip(); v_cod text; i int := 0;
begin
  if length(coalesce(p_secreto, '')) < 32 then return jsonb_build_object('ok', false, 'error', 'secreto'); end if;
  v_h := public.gv_tv_hash(p_secreto);
  select * into r from public."GV_TV_Pantalla" where secreto_hash = v_h;
  if found and r.estado = 'activa' then return jsonb_build_object('ok', true, 'estado', 'activa'); end if;
  if found and r.estado = 'revocada' then return jsonb_build_object('ok', false, 'estado', 'revocada'); end if;
  if found and r.pedido_en > now() - interval '30 minutes' then
    return jsonb_build_object('ok', true, 'estado', 'pendiente', 'codigo', r.codigo_vinc);
  end if;
  -- freno contra el llenado: 5 por IP y 50 en total cada 10 min
  if (select count(*) from public."GV_TV_Pantalla" where estado = 'pendiente' and pedido_en > now() - interval '10 minutes'
        and ip is not distinct from v_ip) >= 5
     or (select count(*) from public."GV_TV_Pantalla" where estado = 'pendiente' and pedido_en > now() - interval '10 minutes') >= 50 then
    return jsonb_build_object('ok', false, 'error', 'espera');
  end if;
  loop
    v_cod := lpad(((('x' || encode(extensions.gen_random_bytes(4), 'hex'))::bit(32)::bigint) % 1000000)::text, 6, '0');
    exit when not exists (select 1 from public."GV_TV_Pantalla" where estado = 'pendiente' and codigo_vinc = v_cod
                            and pedido_en > now() - interval '30 minutes');
    i := i + 1; if i > 20 then return jsonb_build_object('ok', false, 'error', 'espera'); end if;
  end loop;
  if found then
    update public."GV_TV_Pantalla" set codigo_vinc = v_cod, pedido_en = now(), ip = v_ip, navegador = left(p_navegador, 200)
     where id = r.id;
  else
    insert into public."GV_TV_Pantalla" (secreto_hash, codigo_vinc, ip, navegador) values (v_h, v_cod, v_ip, left(p_navegador, 200));
  end if;
  return jsonb_build_object('ok', true, 'estado', 'pendiente', 'codigo', v_cod);
end $f$;
revoke all on function public.gv_tv_vincular_pedir(text, text) from public;
grant execute on function public.gv_tv_vincular_pedir(text, text) to anon, authenticated;

-- El código de ingreso para la TV vinculada. Pendiente o desconocida: no lo da.
create or replace function public.gv_tv_clave_actual_tv(p_secreto text)
returns jsonb language plpgsql volatile security definer set search_path to '' as $f$
declare r record;
begin
  select * into r from public."GV_TV_Pantalla" where secreto_hash = public.gv_tv_hash(p_secreto);
  if not found then return jsonb_build_object('ok', false, 'estado', 'desconocida'); end if;
  if r.estado <> 'activa' then
    return jsonb_build_object('ok', false, 'estado', r.estado,
      'codigo', case when r.estado = 'pendiente' and r.pedido_en > now() - interval '30 minutes' then r.codigo_vinc end);
  end if;
  if r.ultimo_uso is null or r.ultimo_uso < now() - interval '5 minutes' then
    update public."GV_TV_Pantalla" set ultimo_uso = now() where id = r.id;
  end if;
  return jsonb_build_object('ok', true, 'estado', 'activa',
    'clave', public.gv_tv_clave_de(floor(extract(epoch from now()) / 60)::bigint),
    'cambia_en_s', 60 - (floor(extract(epoch from now()))::bigint % 60));
end $f$;
revoke all on function public.gv_tv_clave_actual_tv(text) from public;
grant execute on function public.gv_tv_clave_actual_tv(text) to anon, authenticated;

create or replace function public.gv_tv_vincular_aprobar(p_codigo text, p_nombre text)
returns jsonb language plpgsql volatile security definer set search_path to '' as $f$
declare r record; v_cod text := regexp_replace(coalesce(p_codigo, ''), '\D', '', 'g');
begin
  if not public.es_supervisor_virgilio() then raise exception 'SUPERVISOR: hace falta la sesión de supervisor'; end if;
  select * into r from public."GV_TV_Pantalla"
   where estado = 'pendiente' and codigo_vinc = v_cod and pedido_en > now() - interval '30 minutes'
   order by pedido_en desc limit 1;
  if not found then return jsonb_build_object('ok', false, 'error', 'No hay ninguna TV esperando con ese código (vence a los 30 min).'); end if;
  update public."GV_TV_Pantalla"
     set estado = 'activa', nombre = coalesce(nullif(btrim(p_nombre), ''), 'TV ' || r.id), codigo_vinc = null,
         aprobado_por = lower(auth.jwt() ->> 'email'), aprobado_en = now()
   where id = r.id;
  return jsonb_build_object('ok', true, 'id', r.id);
end $f$;
revoke all on function public.gv_tv_vincular_aprobar(text, text) from public, anon;
grant execute on function public.gv_tv_vincular_aprobar(text, text) to authenticated;

create or replace function public.gv_tv_pantallas()
returns table (id bigint, nombre text, estado text, aprobado_por text, aprobado_en timestamptz, ultimo_uso timestamptz, navegador text)
language plpgsql stable security definer set search_path to '' as $f$
begin
  if not public.es_supervisor_virgilio() then raise exception 'SUPERVISOR: hace falta la sesión de supervisor'; end if;
  return query select p.id, p.nombre, p.estado, p.aprobado_por, p.aprobado_en, p.ultimo_uso, p.navegador
                 from public."GV_TV_Pantalla" p where p.estado <> 'pendiente' order by p.estado, p.ultimo_uso desc nulls last;
end $f$;
revoke all on function public.gv_tv_pantallas() from public, anon;
grant execute on function public.gv_tv_pantallas() to authenticated;

create or replace function public.gv_tv_revocar(p_id bigint)
returns jsonb language plpgsql volatile security definer set search_path to '' as $f$
begin
  if not public.es_supervisor_virgilio() then raise exception 'SUPERVISOR: hace falta la sesión de supervisor'; end if;
  update public."GV_TV_Pantalla" set estado = 'revocada' where id = p_id and estado = 'activa';
  return jsonb_build_object('ok', found);
end $f$;
revoke all on function public.gv_tv_revocar(bigint) from public, anon;
grant execute on function public.gv_tv_revocar(bigint) to authenticated;

-- ═══════════════════════════ PARTE B (aplicar DESPUÉS de vincular la TV) ═══════════════════════════
-- create or replace function public.gv_tv_clave_actual() returns jsonb language plpgsql stable security definer
-- set search_path to '' as $f$
-- begin
--   if not public.es_supervisor_virgilio() then raise exception 'SUPERVISOR: hace falta la sesión de supervisor'; end if;   -- v29.74-tvsup
--   return jsonb_build_object('clave', public.gv_tv_clave_de(floor(extract(epoch from now()) / 60)::bigint),
--     'cambia_en_s', 60 - (floor(extract(epoch from now()))::bigint % 60));
-- end $f$;
-- revoke execute on function public.gv_tv_clave_actual() from public, anon;
-- grant execute on function public.gv_tv_clave_actual() to authenticated;
-- Rollback de la parte B:  grant execute on function public.gv_tv_clave_actual() to anon;  (y el cuerpo viejo, sin el if)

-- Rollback de la parte A: la definición vieja de los 4 validadores está en el commit anterior de este archivo
-- (gv_tv_clave_validar(text), reg_prod_3_0_virgilio_operarios(text), cerv_ingresar) y
-- grant execute on function "GP2".monitor_clave_validar(text) to anon, authenticated;
