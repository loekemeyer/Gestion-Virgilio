-- v24.99 (30/09/2026) — EDITAR UNA PI: corregir las cantidades de cada ítem, con registro de QUIÉN,
-- QUÉ DÍA y A QUÉ HORA.
--
-- Pedido: "Quiero poder modificar las PIs … que cuando toco el lápiz me pregunte quién es la persona
-- que va a corregir la PI. Las personas habilitadas son Tomás, Vivi, Luis, Tomás, Gastón, y un
-- cuadradito Otro para poner el nombre, y ya se registre como un nuevo editor de pedidos. Tiene que
-- quedar registrado qué día, a qué hora, lo modificó qué persona."
--
-- Piezas:
--   GV_Imp_PI_Editor   quién puede corregir una PI. «Otro» agrega una fila (queda como editor nuevo).
--   GV_Imp_PI_Edicion  el log: una fila por cambio (cantidad de un ítem o número de PI), con el
--                      editor, el usuario logueado y el momento. Un guardado = un `lote`.
--   gv_imp_pi_editores()                         lista para los botones del pop-up.
--   gv_imp_pi_editar(ref, prov, editor, cambios, nuevo_ref, simular)
--                                                 simular=true NO escribe: devuelve el antes → después.
--   gv_imp_pi_ediciones(ref, prov, limite)        el historial de ese pedido.
--
-- Reglas:
--   * La cantidad nueva no puede ser menor a lo que ya llegó. 0 con nada llegado = el ítem sale de la
--     PI (estado 'anulado'; `unidades` queda como estaba porque la tabla exige > 0, y el log dice 0).
--   * El front manda lo que VIO (`antes`): si la línea cambió mientras se editaba, no pisa — frena.
--   * Se reusa la regla de siempre para Importados: gv_importados_resync por cada artículo tocado.
--   * Sólo supervisor, igual que el resto de Importación (v22.96).
--
-- Rollback:
--   drop function if exists public.gv_imp_pi_editar(text,text,text,jsonb,text,boolean);
--   drop function if exists public.gv_imp_pi_ediciones(text,text,int);
--   drop function if exists public.gv_imp_pi_editores();
--   drop table if exists public."GV_Imp_PI_Edicion";
--   drop table if exists public."GV_Imp_PI_Editor";

create table if not exists public."GV_Imp_PI_Editor" (
  id          bigserial primary key,
  nombre      text not null,
  activo      boolean not null default true,
  orden       int not null default 100,
  creado      timestamptz not null default now(),
  creado_por  text
);
create unique index if not exists gv_imp_pi_editor_nombre_uq
  on public."GV_Imp_PI_Editor" (lower(translate(btrim(nombre), 'ÁÉÍÓÚáéíóúÑñ', 'AEIOUaeiouNn')));
alter table public."GV_Imp_PI_Editor" enable row level security;
revoke all on public."GV_Imp_PI_Editor" from anon, authenticated;

insert into public."GV_Imp_PI_Editor" (nombre, orden, creado_por) values
  ('Thomas', 1, 'semilla v24.99'),
  ('Tomás',  2, 'semilla v24.99'),
  ('Vivi',   3, 'semilla v24.99'),
  ('Luis',   4, 'semilla v24.99'),
  ('Gastón', 5, 'semilla v24.99')
on conflict do nothing;

create table if not exists public."GV_Imp_PI_Edicion" (
  id           bigserial primary key,
  lote         uuid not null,
  ts           timestamptz not null default now(),
  editor       text not null,
  editor_nuevo boolean not null default false,
  usuario      text,
  pedido_ref   text,
  proveedor    text,
  campo        text not null check (campo in ('unidades','pedido_ref')),
  bache_id     bigint,
  importado_id bigint,
  cod_art      text,
  marca        text,
  antes_u      int,
  despues_u    int,
  antes_ref    text,
  despues_ref  text
);
create index if not exists gv_imp_pi_edicion_ref_idx on public."GV_Imp_PI_Edicion" (pedido_ref, proveedor, ts desc);
create index if not exists gv_imp_pi_edicion_bache_idx on public."GV_Imp_PI_Edicion" (bache_id);
alter table public."GV_Imp_PI_Edicion" enable row level security;
revoke all on public."GV_Imp_PI_Edicion" from anon, authenticated;

create or replace function public.gv_imp_pi_editores()
returns table (nombre text, orden int, creado timestamptz, creado_por text)
language plpgsql stable security definer set search_path = public, pg_temp
as $$
begin
  if not (public.es_supervisor_virgilio() or public.gv_es_supervisor_o_servicio()) then
    raise exception 'Sólo un supervisor logueado puede editar una PI (iniciá sesión con Google; si ya estás, actualizá la app).' using errcode = '42501';
  end if;
  return query
    select e.nombre, e.orden, e.creado, e.creado_por
      from public."GV_Imp_PI_Editor" e
     where e.activo
     order by e.orden, e.nombre;
end $$;

create or replace function public.gv_imp_pi_editar(
  p_pedido_ref text,
  p_proveedor  text,
  p_editor     text,
  p_cambios    jsonb,
  p_nuevo_ref  text default null,
  p_simular    boolean default false)
returns jsonb
language plpgsql security definer set search_path = public, pg_temp
as $$
-- v24.99-pi-editar (marcador de idempotencia: no cambiarlo)
declare
  v_editor text := btrim(coalesce(p_editor, ''));
  v_canon  text;
  v_nuevo_editor boolean := false;
  v_usuario text := coalesce(nullif(auth.jwt() ->> 'email', ''), session_user::text);
  v_lote uuid := gen_random_uuid();
  v_ref_nuevo text := nullif(btrim(coalesce(p_nuevo_ref, '')), '');
  v_ref_cambia boolean;
  c jsonb; b record;
  v_id bigint; v_u int; v_antes_visto int;
  v_filas jsonb := '[]'::jsonb;
  v_imps bigint[] := '{}';
  v_tot_antes bigint := 0; v_tot_desp bigint := 0; v_n int := 0;
  v_base bigint[];
  v_ts timestamptz := now();
begin
  if not (public.es_supervisor_virgilio() or public.gv_es_supervisor_o_servicio()) then
    raise exception 'Sólo un supervisor logueado puede editar una PI (iniciá sesión con Google; si ya estás, actualizá la app).' using errcode = '42501';
  end if;
  if coalesce(btrim(p_pedido_ref), '') = '' then raise exception 'Falta el número de PI.'; end if;
  if v_editor = '' then raise exception 'Decí quién corrige la PI.'; end if;
  if length(v_editor) > 60 then raise exception 'El nombre del editor es demasiado largo.'; end if;

  -- un guardado a la vez por pedido
  perform pg_advisory_xact_lock(hashtext('gv_imp_pi:' || p_pedido_ref || '§' || coalesce(p_proveedor, '')));

  select e.nombre into v_canon from public."GV_Imp_PI_Editor" e
   where lower(translate(btrim(e.nombre), 'ÁÉÍÓÚáéíóúÑñ', 'AEIOUaeiouNn'))
       = lower(translate(v_editor, 'ÁÉÍÓÚáéíóúÑñ', 'AEIOUaeiouNn'))
   limit 1;
  if v_canon is null then v_nuevo_editor := true; v_canon := v_editor; end if;

  -- las líneas del pedido: la MISMA clave que gv_importado_pedido_lineas
  select array_agg(x.id order by x.id) into v_base
    from public."GV_Importados_Baches" x
   where x.estado = 'en_curso'
     and coalesce(nullif(btrim(x.pedido_ref), ''), '(sin pedido)') = p_pedido_ref
     and (p_proveedor is null
          or coalesce(nullif(btrim(x.proveedor), ''), '(sin proveedor)') = p_proveedor);
  if v_base is null then raise exception 'La PI % no tiene líneas en curso.', p_pedido_ref; end if;

  select coalesce(sum(x.unidades), 0) into v_tot_antes
    from public."GV_Importados_Baches" x where x.id = any (v_base);
  v_tot_desp := v_tot_antes;

  -- 1) cantidades
  for c in select * from jsonb_array_elements(coalesce(p_cambios, '[]'::jsonb)) loop
    v_id := nullif(c ->> 'bache_id', '')::bigint;
    if v_id is null or not (v_id = any (v_base)) then
      raise exception 'La línea % no es de la PI %.', coalesce(c ->> 'bache_id', '?'), p_pedido_ref;
    end if;
    if nullif(c ->> 'unidades', '') is null then raise exception 'Falta la cantidad nueva de la línea %.', v_id; end if;
    v_u := round((c ->> 'unidades')::numeric);
    select * into b from public."GV_Importados_Baches" where id = v_id for update;
    v_antes_visto := nullif(c ->> 'antes', '')::int;
    if v_antes_visto is not null and v_antes_visto <> b.unidades then
      raise exception 'El % cambió mientras editabas (tenía %, ahora %). Volvé a abrir la PI.', b.cod_art, v_antes_visto, b.unidades;
    end if;
    if v_u = b.unidades then continue; end if;
    if v_u < 0 then raise exception 'El % no puede quedar en negativo.', b.cod_art; end if;
    if v_u < coalesce(b.unidades_llegadas, 0) then
      raise exception 'El % no puede quedar en % u: ya llegaron %.', b.cod_art, v_u, b.unidades_llegadas;
    end if;

    v_n := v_n + 1;
    v_tot_desp := v_tot_desp - b.unidades + v_u;
    v_filas := v_filas || jsonb_build_object('bache_id', b.id, 'cod_art', b.cod_art, 'marca', b.marca,
      'antes', b.unidades, 'despues', v_u, 'delta', v_u - b.unidades, 'sale', v_u = 0);
    if not (b.importado_id = any (v_imps)) then v_imps := v_imps || b.importado_id; end if;

    if not p_simular then
      if v_u = 0 then
        update public."GV_Importados_Baches" set estado = 'anulado', actualizado = v_ts where id = b.id;
      else
        update public."GV_Importados_Baches"
           set unidades = v_u,
               estado = case when v_u <= coalesce(unidades_llegadas, 0) then 'llegado' else 'en_curso' end,
               actualizado = v_ts
         where id = b.id;
      end if;
      insert into public."GV_Imp_PI_Edicion" (lote, ts, editor, editor_nuevo, usuario, pedido_ref, proveedor,
        campo, bache_id, importado_id, cod_art, marca, antes_u, despues_u)
      values (v_lote, v_ts, v_canon, v_nuevo_editor, v_usuario, p_pedido_ref, b.proveedor,
        'unidades', b.id, b.importado_id, b.cod_art, b.marca, b.unidades, v_u);
    end if;
  end loop;

  -- 2) número de PI (todas las líneas del pedido, también la que recién salió)
  v_ref_cambia := v_ref_nuevo is not null and v_ref_nuevo <> p_pedido_ref;
  if v_ref_cambia and not p_simular then
    update public."GV_Importados_Baches" set pedido_ref = v_ref_nuevo, actualizado = v_ts
     where id = any (v_base);
    insert into public."GV_Imp_PI_Edicion" (lote, ts, editor, editor_nuevo, usuario, pedido_ref, proveedor,
      campo, antes_ref, despues_ref)
    values (v_lote, v_ts, v_canon, v_nuevo_editor, v_usuario, p_pedido_ref, p_proveedor,
      'pedido_ref', p_pedido_ref, v_ref_nuevo);
  end if;

  -- 3) editor nuevo: queda registrado sólo si hubo un cambio de verdad
  if v_nuevo_editor and not p_simular and (v_n > 0 or v_ref_cambia) then
    insert into public."GV_Imp_PI_Editor" (nombre, creado_por) values (v_canon, v_usuario)
    on conflict do nothing;
  end if;

  -- 4) Importados.pedido_curso / reingreso_est
  if not p_simular then
    for v_id in select unnest(v_imps) loop
      perform public.gv_importados_resync(v_id);
    end loop;
  end if;

  return jsonb_build_object(
    'simulado', p_simular, 'lote', case when p_simular then null else v_lote end, 'ts', v_ts,
    'editor', v_canon, 'editor_nuevo', v_nuevo_editor, 'usuario', v_usuario,
    'pedido_ref', p_pedido_ref, 'ref_nuevo', case when v_ref_cambia then v_ref_nuevo else null end,
    'cambios', v_n, 'filas', v_filas, 'total_antes', v_tot_antes, 'total_despues', v_tot_desp);
end $$;

create or replace function public.gv_imp_pi_ediciones(
  p_pedido_ref text default null, p_proveedor text default null, p_limite int default 300)
returns table (id bigint, lote uuid, ts timestamptz, editor text, editor_nuevo boolean, usuario text,
  pedido_ref text, proveedor text, campo text, cod_art text, marca text,
  antes_u int, despues_u int, antes_ref text, despues_ref text)
language plpgsql stable security definer set search_path = public, pg_temp
as $$
begin
  if not (public.es_supervisor_virgilio() or public.gv_es_supervisor_o_servicio()) then
    raise exception 'Sólo un supervisor logueado puede ver las ediciones de una PI.' using errcode = '42501';
  end if;
  return query
    select l.id, l.lote, l.ts, l.editor, l.editor_nuevo, l.usuario, l.pedido_ref, l.proveedor, l.campo,
           l.cod_art, l.marca, l.antes_u, l.despues_u, l.antes_ref, l.despues_ref
      from public."GV_Imp_PI_Edicion" l
     where p_pedido_ref is null
        or l.pedido_ref = p_pedido_ref
        or l.despues_ref = p_pedido_ref
        or l.bache_id in (select x.id from public."GV_Importados_Baches" x
                           where coalesce(nullif(btrim(x.pedido_ref), ''), '(sin pedido)') = p_pedido_ref
                             and (p_proveedor is null
                                  or coalesce(nullif(btrim(x.proveedor), ''), '(sin proveedor)') = p_proveedor))
     order by l.ts desc, l.id
     limit greatest(1, least(coalesce(p_limite, 300), 2000));
end $$;

revoke all on function public.gv_imp_pi_editar(text,text,text,jsonb,text,boolean) from public;
revoke all on function public.gv_imp_pi_editores() from public;
revoke all on function public.gv_imp_pi_ediciones(text,text,int) from public;
grant execute on function public.gv_imp_pi_editar(text,text,text,jsonb,text,boolean) to anon, authenticated, service_role;
grant execute on function public.gv_imp_pi_editores() to anon, authenticated, service_role;
grant execute on function public.gv_imp_pi_ediciones(text,text,int) to anon, authenticated, service_role;

-- segunda migración (mismo día): sólo authenticated + centinela
revoke execute on function public.gv_imp_pi_editar(text,text,text,jsonb,text,boolean) from anon;
revoke execute on function public.gv_imp_pi_editores() from anon;
revoke execute on function public.gv_imp_pi_ediciones(text,text,int) from anon;
insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version) values
 ('gv_imp_pi_editar','funcion','''unidades'', b\.id, b\.importado_id',
  'Editar una PI deja registrado QUIÉN (editor elegido en el lápiz), QUÉ DÍA y A QUÉ HORA cada cantidad cambiada (GV_Imp_PI_Edicion)',
  '(a confirmar)','v24.99'),
 ('gv_imp_pi_editar','funcion','v_antes_visto <> b\.unidades',
  'Editar una PI no pisa una línea que cambió mientras se editaba: compara con el antes que vio el front',
  '(a confirmar)','v24.99');

-- Probado en transacción abortada (30/09): 2 cambios (438E 1224→2520, 035E→0 'anulado'), número de PI
-- R1→R2 en las 11 líneas, 3 filas de log, editor nuevo registrado, Importados.pedido_curso 438E=2520 /
-- 035E=0, y un `antes` viejo frena con "cambió mientras editabas".
