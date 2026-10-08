-- D15 (Thomas, 08/10/2026): las funciones que usan SOLO las pantallas de supervisor exigen la sesión
-- de supervisor (Google). Hasta acá cualquiera con la clave pública de la página —o un usuario
-- anónimo, que es como entra el celular del operario (483 de 505 usuarios de auth)— podía llamarlas.
--
-- Cómo: cada función arranca con `perform public.gv_rpc_guard('<nombre>')` (marcador rpc-guard-d15).
-- El guard mira la tabla GV_RPC_Guard: si la fila está activa y el que llama no es supervisor
-- (es_supervisor_virgilio() o gv_es_supervisor_o_servicio()), corta con 'SUPERVISOR: ...'.
--
-- ROLLBACK RÁPIDO (sin tocar ninguna función, efecto inmediato):
--   select public.gv_rpc_guard_instalar(false);                 -- apaga las 18 de una
--   update public."GV_RPC_Guard" set activo = false where fn = 'zona_barrio_set';   -- una sola
-- ROLLBACK TOTAL (vuelve los cuerpos al original guardado):
--   select public.gv_rpc_guard_quitar();
--
-- Afuera a propósito: gv_oc_generar_pendientes (regla protegida: se pide el sí aparte),
-- insumo_unidad_guardar (la llama el operario al inventar una unidad), y todo lo del celular
-- del operario (tandas, picking, racks, faltantes de armado).

create table if not exists public."GV_RPC_Guard" (
  fn text primary key, activo boolean not null default true,
  desde timestamptz not null default now(), version text);
alter table public."GV_RPC_Guard" enable row level security;
revoke all on public."GV_RPC_Guard" from anon, authenticated;

create table if not exists zz_backups."GV_Backup_RPCGuard_defs_20261008" (
  firma text primary key, def text not null, guardado timestamptz default now());
alter table zz_backups."GV_Backup_RPCGuard_defs_20261008" enable row level security;

create or replace function public.gv_rpc_guard(p_fn text) returns void
language plpgsql stable security definer set search_path = public, pg_temp as $f$
begin
  if not exists (select 1 from public."GV_RPC_Guard" g where g.fn = p_fn and g.activo) then return; end if;
  if public.es_supervisor_virgilio() or public.gv_es_supervisor_o_servicio() then return; end if;
  raise exception 'SUPERVISOR: % necesita la sesión de supervisor (Google). Entrá con tu cuenta y probá de nuevo.', p_fn
    using errcode = '42501';
end $f$;
revoke all on function public.gv_rpc_guard(text) from public, anon, authenticated;

create or replace function public.gv_rpc_guard_instalar(p_on boolean default true) returns text
language plpgsql security definer set search_path = public, pg_temp as $f$
declare
  fns text[] := array['aceptar_conteo','rechazar_conteo','faltante_resolver','zona_barrio_set',
    'insumo_alta','insumo_borrar','insumo_editar','insumo_recodificar','insumo_identificar',
    'insumo_factores_guardar','insumo_cat_guardar','insumo_cat_borrar','gv_supers_set','gv_supers_baja',
    'corr_convertir_faltante','gv_conciliacion_registrar','gv_pedido_horario_set','gv_insumo_ubicaciones_guardar'];
  r record; v_src text; v_def text; n int := 0;
begin
  if not p_on then
    update public."GV_RPC_Guard" set activo = false where fn = any(fns);
    return 'guard apagado';
  end if;
  for r in select p.oid, p.oid::regprocedure::text firma, p.proname, p.prosrc, l.lanname
             from pg_proc p join pg_language l on l.oid = p.prolang
            where p.pronamespace = 'public'::regnamespace and p.proname = any(fns) loop
    if r.prosrc ~ 'gv_rpc_guard' then continue; end if;
    v_def := pg_get_functiondef(r.oid);
    insert into zz_backups."GV_Backup_RPCGuard_defs_20261008"(firma, def) values (r.firma, v_def)
      on conflict (firma) do nothing;
    if r.lanname = 'plpgsql' then
      v_src := regexp_replace(r.prosrc, '\mbegin\M',
        'begin' || chr(10) || '  perform public.gv_rpc_guard(' || quote_literal(r.proname) || ');  -- rpc-guard-d15' || chr(10), 'i');
    elsif r.lanname = 'sql' then
      v_src := chr(10) || 'select public.gv_rpc_guard(' || quote_literal(r.proname) || ');  -- rpc-guard-d15' || chr(10) || r.prosrc;
    else
      raise exception 'lenguaje no previsto en %', r.firma;
    end if;
    if v_src = r.prosrc or position(r.prosrc in v_def) = 0 then raise exception 'no se pudo parchear %', r.firma; end if;
    execute replace(v_def, r.prosrc, v_src);
    n := n + 1;
  end loop;
  insert into public."GV_RPC_Guard"(fn, activo, version) select unnest(fns), true, 'rpc-guard-d15'
    on conflict (fn) do update set activo = true, desde = now();
  return 'guard prendido; funciones parcheadas ahora: ' || n;
end $f$;
revoke all on function public.gv_rpc_guard_instalar(boolean) from public, anon, authenticated;

create or replace function public.gv_rpc_guard_quitar() returns text
language plpgsql security definer set search_path = public, pg_temp as $f$
declare r record; n int := 0;
begin
  for r in select firma, def from zz_backups."GV_Backup_RPCGuard_defs_20261008" loop
    execute r.def; n := n + 1;
  end loop;
  update public."GV_RPC_Guard" set activo = false;
  return 'cuerpos originales repuestos: ' || n;
end $f$;
revoke all on function public.gv_rpc_guard_quitar() from public, anon, authenticated;

select public.gv_rpc_guard_instalar(true);
