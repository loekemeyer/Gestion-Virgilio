-- ============================================================================
-- v18.29 — "Modificar Pedidos": QUIÉN y POR QUÉ obligatorios, y el log se muda a
-- GESTIÓN para que lo lea Facturación. REEMPLAZA a sql/gv_pedido_mod_v1823.sql
-- (ese archivo queda como historia: su tabla de log, que vivía en LK, se dropeó).
--
-- POR QUÉ SE MUDÓ EL LOG. Luis pidió que Facturación muestre un badge en la
-- columna NP cuando el pedido se modificó después de entrar, "para que se pueda
-- facturar a mano correctamente en ISIS". Facturación es una pantalla de Gestión
-- y lee con la anon key: el log tiene que estar de este lado. Medido el 15/09
-- (transacción abortada): LK **sí puede ESCRIBIR** en Virgilio por el FDW
-- `virgilio_db` (insert de prueba en virgilio.gv_ppp_web_diferido → rows=1), así
-- que la función de LK escribe el log en Gestión por foreign table, en la MISMA
-- transacción en la que cambia el pedido. Si el log falla, el pedido no cambia.
--
-- ⚠ TRAMPA DE postgres_fdw: la foreign table NO declara `id`. Si se la declara,
-- el INSERT remoto manda TODAS las columnas —incluida id como NULL— y revienta
-- contra el not-null del bigserial. Sin declararla, el default remoto se aplica.
-- ============================================================================

-- ══════════════ PARTE 1 — en GESTIÓN (hrxfctzncixxqmpfhskv) ══════════════

-- Quién hace la modificación. Arranca con Mariana; desde el desplegable de la
-- pantalla se agregan más (RPC de abajo), que es lo que pidió Luis.
create table if not exists public."GV_Modif_Personas" (
  id         bigserial primary key,
  nombre     text        not null,
  activo     boolean     not null default true,
  creado_at  timestamptz not null default now(),
  creado_por text
);
create unique index if not exists gv_modif_personas_nombre_ux
  on public."GV_Modif_Personas" (lower(btrim(nombre)));
insert into public."GV_Modif_Personas" (nombre, creado_por)
select 'Mariana', 'semilla v18.29'
where not exists (select 1 from public."GV_Modif_Personas" where lower(btrim(nombre)) = 'mariana');

alter table public."GV_Modif_Personas" enable row level security;
revoke insert, update, delete, truncate on public."GV_Modif_Personas" from anon, authenticated;
grant select on public."GV_Modif_Personas" to anon, authenticated, lk_ppp_reader;
do $$ begin
  if not exists (select 1 from pg_policies where schemaname='public'
                   and tablename='GV_Modif_Personas' and policyname='gv_modif_personas_lee') then
    create policy gv_modif_personas_lee on public."GV_Modif_Personas"
      for select to anon, authenticated, lk_ppp_reader using (true);
  end if;
end $$;

create or replace function public.gv_modif_persona_agregar(p_nombre text, p_por text default null)
returns table (id bigint, nombre text)
language plpgsql security definer set search_path to 'public','pg_temp' as $fn$
declare v_n text := btrim(coalesce(p_nombre, ''));
begin
  if length(v_n) < 2 then
    raise exception 'El nombre tiene que tener al menos 2 letras.' using errcode='check_violation';
  end if;
  if length(v_n) > 60 then
    raise exception 'Ese nombre es demasiado largo.' using errcode='check_violation';
  end if;
  insert into public."GV_Modif_Personas" (nombre, creado_por)
  values (v_n, nullif(btrim(coalesce(p_por,'')), ''))
  on conflict (lower(btrim(nombre))) do nothing;
  return query select p.id, p.nombre from public."GV_Modif_Personas" p
                where lower(btrim(p.nombre)) = lower(v_n);
end $fn$;
revoke all on function public.gv_modif_persona_agregar(text, text) from public, anon;
grant execute on function public.gv_modif_persona_agregar(text, text) to authenticated;

-- El log, canónico. `motivo` es NOT NULL y no puede ser vacío: el justificativo
-- obligatorio es una regla de la base, no un chequeo de la pantalla.
create table if not exists public."GV_Pedido_Mod_Log" (
  id           bigserial primary key,
  empresa      text        not null check (empresa in ('lk','chef')),
  fuente       text        not null default 'web' check (fuente in ('web','isis')),
  clave        text        not null,
  order_id     bigint,
  nps          text[],
  hecho_en     timestamptz not null default now(),
  quien        text,
  quien_sesion text,
  tipo         text        not null,
  motivo       text        not null check (btrim(motivo) <> ''),
  antes        jsonb       not null,
  despues      jsonb       not null,
  detalle      jsonb,
  origen       text        not null default 'gestion:modificar-pedidos'
);
create index if not exists gv_pedido_mod_log_clave_ix on public."GV_Pedido_Mod_Log" (empresa, clave, hecho_en desc);
create index if not exists gv_pedido_mod_log_order_ix on public."GV_Pedido_Mod_Log" (empresa, order_id);

alter table public."GV_Pedido_Mod_Log" enable row level security;
revoke update, delete, truncate on public."GV_Pedido_Mod_Log" from anon, authenticated;
revoke insert on public."GV_Pedido_Mod_Log" from anon;
grant select on public."GV_Pedido_Mod_Log" to anon, authenticated, lk_ppp_reader;
grant insert on public."GV_Pedido_Mod_Log" to lk_ppp_reader;
grant usage, select on sequence public."GV_Pedido_Mod_Log_id_seq" to lk_ppp_reader;
do $$ begin
  if not exists (select 1 from pg_policies where schemaname='public'
                   and tablename='GV_Pedido_Mod_Log' and policyname='gv_pedido_mod_log_lee') then
    create policy gv_pedido_mod_log_lee on public."GV_Pedido_Mod_Log"
      for select to anon, authenticated, lk_ppp_reader using (true);
  end if;
  if not exists (select 1 from pg_policies where schemaname='public'
                   and tablename='GV_Pedido_Mod_Log' and policyname='gv_pedido_mod_log_escribe_fdw') then
    create policy gv_pedido_mod_log_escribe_fdw on public."GV_Pedido_Mod_Log"
      for insert to lk_ppp_reader with check (true);
  end if;
end $$;

-- El texto corto que va en el globito del badge de Facturación.
create or replace function public.gv_pedido_mod_resumen(p_detalle jsonb)
returns text language sql immutable set search_path to 'public','pg_temp' as $fn$
  select nullif(array_to_string(array_remove(array[
    (select string_agg(x->>'cod' || ': ' || (x->>'de') || '→' || (x->>'a') || ' cajas', ' · ')
       from jsonb_array_elements(coalesce(p_detalle->'cambiados','[]'::jsonb)) x),
    (select string_agg('+ ' || (x->>'cod') || ' ×' || (x->>'cajas'), ' · ')
       from jsonb_array_elements(coalesce(p_detalle->'agregados','[]'::jsonb)) x),
    (select string_agg('− ' || (x->>'cod'), ' · ')
       from jsonb_array_elements(coalesce(p_detalle->'quitados','[]'::jsonb)) x),
    case when p_detalle->'direccion' is null or p_detalle->'direccion' = 'null'::jsonb then null
         else 'entrega: ' || coalesce(p_detalle->'direccion'->>'de','—') || ' → ' ||
              coalesce(p_detalle->'direccion'->>'a','—') end
  ], null), ' · '), '');
$fn$;
grant execute on function public.gv_pedido_mod_resumen(jsonb) to anon, authenticated, lk_ppp_reader;

-- Una fila por NP, que es como Facturación mira el mundo. Además de las NP que se
-- guardaron en el momento del cambio, resuelve las que el pedido tiene HOY: si el
-- pedido se volvió a partir después de la modificación, el badge sigue apareciendo
-- donde corresponde (medido: una modificación cargada con 2 NP salió con 3).
create or replace view public.gv_pedido_mod_np with (security_invoker = true) as
with base as (
  select l.id, l.empresa, l.fuente, l.order_id, l.nps, l.hecho_en, l.quien, l.motivo,
         public.gv_pedido_mod_resumen(l.detalle) as resumen
    from public."GV_Pedido_Mod_Log" l
), expand as (
  select b.id, btrim(x.np) as np, b.hecho_en, b.quien, b.motivo, b.resumen
    from base b, unnest(coalesce(b.nps, '{}'::text[])) as x(np)
  union
  select b.id, public.gv_ppp_web_np_label(b.empresa, g.np, g.np_idx), b.hecho_en, b.quien, b.motivo, b.resumen
    from base b
    join public."PPP_Web_Programacion" g on g.empresa = b.empresa and g.order_id = b.order_id
   where b.fuente = 'web' and b.order_id is not null
)
select e.np,
       count(*)::int   as mods,
       max(e.hecho_en) as ultima,
       string_agg(coalesce(e.resumen, e.motivo), ' | ' order by e.hecho_en) as resumen,
       jsonb_agg(jsonb_build_object('cuando', e.hecho_en, 'quien', e.quien,
                                    'motivo', e.motivo, 'que', e.resumen)
                 order by e.hecho_en desc) as cambios
  from expand e
 where coalesce(btrim(e.np), '') <> ''
 group by e.np;
alter view public.gv_pedido_mod_np set (security_invoker = true);
grant select on public.gv_pedido_mod_np to anon, authenticated;

-- ══════════════ PARTE 2 — en LK (kwkclwhmoygunqmlegrg) ══════════════

-- La foreign table por la que la función de LK escribe el log en Gestión.
-- ⚠ SIN la columna `id` (ver la trampa de arriba).
drop foreign table if exists virgilio."GV_Pedido_Mod_Log";
create foreign table virgilio."GV_Pedido_Mod_Log" (
  empresa text, fuente text, clave text, order_id bigint, nps text[], hecho_en timestamptz,
  quien text, quien_sesion text, tipo text, motivo text, antes jsonb, despues jsonb,
  detalle jsonb, origen text
) server virgilio_db options (schema_name 'public', table_name 'GV_Pedido_Mod_Log');
grant select on virgilio."GV_Pedido_Mod_Log" to authenticated;

-- La tabla de log que la v18.23 había creado en LK ya no va:
drop table if exists public."GV_Pedido_Mod_Log";

-- ── Normalización de un código de artículo ──────────────────────────────
-- El mismo criterio que usa `v_pedidos_web`: 3 dígitos con ceros adelante + las
-- letras que traiga, en mayúscula. "44" -> "044", "438el" -> "438EL".
create or replace function public.gv_pedido_mod_cod(p text)
returns text language sql immutable set search_path to 'public','pg_temp' as $$
  select case
    when (regexp_match(coalesce(p,''), '\d+'))[1] is null then null
    else lpad((regexp_match(p, '\d+'))[1], 3, '0')
         || upper(coalesce((regexp_match(p, '[a-zA-Z]+'))[1], ''))
  end;
$$;

-- ── 3) Lo que necesita el modal para abrir ─────────────────────────────────
create or replace function public.gv_pedido_mod_ctx(p_empresa text, p_order_id bigint)
returns jsonb
language plpgsql security definer set search_path to 'public','pg_temp' as $$
declare
  v_emp text := lower(coalesce(p_empresa, 'lk'));
  v_o   record;
  v_c   record;
  v_suc text;
  v_items jsonb; v_dirs jsonb; v_log jsonb; v_est jsonb; v_sin jsonb;
begin
  if not exists (select 1 from public.admins a where a.auth_user_id = auth.uid()) then
    raise exception 'Hace falta la sesión de supervisor para abrir un pedido.'
      using errcode = 'insufficient_privilege';
  end if;
  if v_emp <> 'lk' then
    raise exception 'El pedido es de la página de Chef y esa base todavía no acepta cambios desde Gestión.'
      using errcode = 'feature_not_supported';
  end if;

  select o.id, o.sheets_payload, o.enviado_a_compras_at, o.customer_id
    into v_o from public.orders o where o.id = p_order_id;
  if not found then raise exception 'No existe el pedido % en la página de LK.', p_order_id; end if;

  v_suc := coalesce(v_o.sheets_payload->>'sucursal_entrega', v_o.sheets_payload->>'sucursalEntrega');
  select c.id, c.cod_cliente, c.business_name into v_c
    from public.customers c where c.id = v_o.customer_id;

  -- los renglones del pedido, con la descripción y el uxb del catálogo
  select coalesce(jsonb_agg(jsonb_build_object(
           'i',           it.ord - 1,
           'cod_art',     it.value->>'cod_art',
           'cod',         public.gv_pedido_mod_cod(it.value->>'cod_art'),
           'cajas',       nullif(coalesce(it.value->>'cajas', it.value->>'Cajas'), '')::numeric,
           'uxb',         nullif(it.value->>'uxb', '')::numeric,
           'descripcion', coalesce(p.description, lp.description),
           'catalogo',    (p.id is not null or lp.id is not null)
         ) order by it.ord), '[]'::jsonb)
    into v_items
    from jsonb_array_elements(coalesce(v_o.sheets_payload->'items', '[]'::jsonb))
           with ordinality it(value, ord)
    left join public.products       p  on public.gv_pedido_mod_cod(p.cod)  = public.gv_pedido_mod_cod(it.value->>'cod_art')
    left join public.loke_products  lp on public.gv_pedido_mod_cod(lp.cod) = public.gv_pedido_mod_cod(it.value->>'cod_art');

  -- la libreta de direcciones del cliente: lo que ya puede elegir en la página
  select coalesce(jsonb_agg(jsonb_build_object(
           'slot', d.slot, 'label', d.label, 'direccion', d.direccion_entrega,
           'localidad', d.localidad, 'provincia', d.provincia,
           'barrio', d.zona_expreso, 'cp', d.cp,
           'actual', btrim(lower(d.label)) = btrim(lower(coalesce(v_suc, '')))
         ) order by d.slot), '[]'::jsonb)
    into v_dirs
    from public.customer_delivery_addresses d where d.customer_id = v_o.customer_id;

  -- en qué anda el pedido del lado de Gestión (por FDW: es la vista de Virgilio)
  select to_jsonb(g) into v_est
    from virgilio.gv_pedido_web_estado_pagina g
   where g.empresa = 'lk' and g.order_id = p_order_id;

  select coalesce(jsonb_agg(jsonb_build_object(
           'hecho_en', l.hecho_en, 'quien', l.quien, 'quien_sesion', l.quien_sesion,
           'tipo', l.tipo, 'motivo', l.motivo, 'detalle', l.detalle) order by l.hecho_en desc), '[]'::jsonb)
    into v_log
    from virgilio."GV_Pedido_Mod_Log" l
   where l.empresa = v_emp and l.fuente = 'web' and l.order_id = p_order_id;

  -- Los códigos que HOY están sin stock con fecha de reingreso. No es un adorno: el trigger
  -- `marcar_pedido_diferido` corre con cada UPDATE de sheets_payload, así que agregarle al
  -- pedido uno de estos lo marca DIFERIDO entero. La pantalla los muestra con un reloj.
  select coalesce(jsonb_agg(distinct r.cod), '[]'::jsonb) into v_sin
    from public.reingreso_cache r where r.sin_stock;

  return jsonb_build_object(
    'empresa', v_emp, 'order_id', p_order_id,
    'cod_cliente', coalesce(v_c.cod_cliente::text, v_o.sheets_payload->>'cod_cliente'),
    'razon_social', v_c.business_name,
    'sucursal_entrega', v_suc,
    'enviado_a_compras', (v_o.enviado_a_compras_at is not null),
    'items', v_items,
    -- la ficha CRUDA, para que la pantalla la devuelva como `p_espera` y el guardado corte si
    -- el pedido cambió por otro lado mientras el modal estaba abierto
    'items_raw', coalesce(v_o.sheets_payload->'items', '[]'::jsonb),
    'direcciones', v_dirs, 'sin_stock', v_sin,
    'estado', coalesce(v_est, '{}'::jsonb), 'log', v_log);
end $$;

-- ── 4) Guardar la modificación ─────────────────────────────────────────────
-- p_items    : la lista COMPLETA nueva [{cod_art, cajas, uxb}]; null = no tocar.
-- p_sucursal : label de una dirección que YA tiene el cliente;  null = no tocar.
-- p_dir_nueva: {label, direccion, calle, altura, localidad, provincia, cp, barrio,
--               observaciones} -> se le da de alta al cliente como una opción más de
--               la página (customer_delivery_addresses) y se usa en este pedido.
-- p_espera   : los items tal como los leyó la pantalla; si el pedido cambió por otro
--               lado mientras tanto, corta en vez de pisar.
create or replace function public.gv_pedido_mod_guardar(
  p_empresa    text,
  p_order_id   bigint,
  p_items      jsonb default null,
  p_sucursal   text  default null,
  p_dir_nueva  jsonb default null,
  p_motivo     text  default null,
  p_quien      text  default null,
  p_espera     jsonb default null,
  p_nps        text[] default null
) returns jsonb
language plpgsql security definer set search_path to 'public','pg_temp' as $$
declare
  v_emp   text := lower(coalesce(p_empresa, 'lk'));
  v_o     record;
  v_suc   text;
  v_suc_new text;
  v_items_old jsonb; v_items_new jsonb;
  v_slot  int; v_label text;
  v_malos text;
  v_tipo  text;
  v_det   jsonb;
  v_pay   jsonb;
  v_sync  boolean := false;
  v_mail  text;
begin
  if not exists (select 1 from public.admins a where a.auth_user_id = auth.uid()) then
    raise exception 'Hace falta la sesión de supervisor para modificar un pedido.'
      using errcode = 'insufficient_privilege';
  end if;
  if v_emp <> 'lk' then
    raise exception 'El pedido es de la página de Chef y esa base todavía no acepta cambios desde Gestión: hay que modificarlo en la página de Chef.'
      using errcode = 'feature_not_supported';
  end if;
  -- v18.29 (Luis): *"que no deje guardar cambios de modificación si la persona
  -- modificándolo no pone justificativo"*. La regla vive ACÁ, no sólo en la pantalla.
  if length(btrim(coalesce(p_motivo, ''))) < 3 then
    raise exception 'Falta el justificativo: hay que escribir por qué se modifica el pedido.'
      using errcode = 'check_violation';
  end if;
  if length(btrim(coalesce(p_quien, ''))) < 2 then
    raise exception 'Falta quién hace la modificación.' using errcode = 'check_violation';
  end if;
  if p_items is null and p_sucursal is null and p_dir_nueva is null then
    raise exception 'No viene ningún cambio.' using errcode = 'check_violation';
  end if;

  select o.id, o.sheets_payload, o.customer_id, o.enviado_a_compras_at
    into v_o from public.orders o where o.id = p_order_id for update;
  if not found then raise exception 'No existe el pedido % en la página de LK.', p_order_id; end if;
  if v_o.sheets_payload is null then
    raise exception 'El pedido % no tiene ficha (sheets_payload): no se puede modificar desde acá.', p_order_id;
  end if;

  -- ⚠ El mismo corte que usa la página para dejar editar: facturado o entregado, no se toca.
  if exists (select 1 from virgilio.gv_pedido_web_estado_pagina g
              where g.empresa = 'lk' and g.order_id = p_order_id and (g.facturado or g.entregado)) then
    raise exception 'El pedido ya está facturado o entregado: no se modifica desde acá.'
      using errcode = 'check_violation';
  end if;

  v_items_old := coalesce(v_o.sheets_payload->'items', '[]'::jsonb);
  v_suc := coalesce(v_o.sheets_payload->>'sucursal_entrega', v_o.sheets_payload->>'sucursalEntrega');

  -- ¿cambió por otro lado mientras estaba abierto el modal?
  if p_espera is not null and p_espera is distinct from v_items_old then
    raise exception 'El pedido cambió mientras lo tenías abierto (lo editaron en la página, o en otra pantalla). Cerrá y volvé a abrirlo.'
      using errcode = 'serialization_failure';
  end if;

  -- ── dirección nueva: se le da de alta al cliente ──────────────────────────
  if p_dir_nueva is not null then
    v_label := btrim(coalesce(p_dir_nueva->>'label', p_dir_nueva->>'direccion', ''));
    if v_label = '' then raise exception 'La dirección nueva necesita un nombre.' using errcode='check_violation'; end if;
    if exists (select 1 from public.customer_delivery_addresses d
                where d.customer_id = v_o.customer_id
                  and btrim(lower(d.label)) = btrim(lower(v_label))) then
      raise exception 'El cliente ya tiene una dirección con el nombre "%".', v_label using errcode='unique_violation';
    end if;
    select coalesce(max(d.slot), 0) + 1 into v_slot
      from public.customer_delivery_addresses d where d.customer_id = v_o.customer_id;
    insert into public.customer_delivery_addresses
      (customer_id, slot, label, direccion_entrega, calle, altura, cp, localidad, provincia,
       zona_expreso, observaciones, pending_isis, created_at)
    values (v_o.customer_id, v_slot, v_label,
            nullif(btrim(coalesce(p_dir_nueva->>'direccion','')), ''),
            nullif(btrim(coalesce(p_dir_nueva->>'calle','')), ''),
            nullif(btrim(coalesce(p_dir_nueva->>'altura','')), ''),
            nullif(btrim(coalesce(p_dir_nueva->>'cp','')), ''),
            nullif(btrim(coalesce(p_dir_nueva->>'localidad','')), ''),
            nullif(btrim(coalesce(p_dir_nueva->>'provincia','')), ''),
            nullif(btrim(coalesce(p_dir_nueva->>'barrio','')), ''),
            nullif(btrim(coalesce(p_dir_nueva->>'observaciones','')), ''),
            true, now());
    v_suc_new := v_label;
  elsif p_sucursal is not null then
    if not exists (select 1 from public.customer_delivery_addresses d
                    where d.customer_id = v_o.customer_id
                      and btrim(lower(d.label)) = btrim(lower(p_sucursal))) then
      raise exception 'El cliente no tiene ninguna dirección que se llame "%".', p_sucursal
        using errcode = 'check_violation';
    end if;
    v_suc_new := btrim(p_sucursal);
  end if;

  -- ── contenido ─────────────────────────────────────────────────────────────
  if p_items is not null then
    if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
      raise exception 'Un pedido no puede quedar sin ningún renglón.' using errcode='check_violation';
    end if;
    -- cada renglón: código conocido, cajas > 0 entera, uxb > 0
    select string_agg(distinct x.cod_art, ', ') into v_malos
      from (select it.value->>'cod_art' as cod_art,
                   nullif(it.value->>'cajas','')::numeric as cajas,
                   nullif(it.value->>'uxb','')::numeric   as uxb
              from jsonb_array_elements(p_items) it) x
     where public.gv_pedido_mod_cod(x.cod_art) is null
        or coalesce(x.cajas, 0) <= 0 or x.cajas <> trunc(x.cajas)
        or coalesce(x.uxb, 0) <= 0
        or (not exists (select 1 from public.products p
                         where public.gv_pedido_mod_cod(p.cod) = public.gv_pedido_mod_cod(x.cod_art))
        and not exists (select 1 from public.loke_products lp
                         where public.gv_pedido_mod_cod(lp.cod) = public.gv_pedido_mod_cod(x.cod_art)));
    if v_malos is not null then
      raise exception 'Renglones que no puedo guardar (código desconocido o cantidad inválida): %', v_malos
        using errcode = 'check_violation';
    end if;
    if exists (select 1 from (select public.gv_pedido_mod_cod(it.value->>'cod_art') c
                                from jsonb_array_elements(p_items) it) q
                group by q.c having count(*) > 1) then
      raise exception 'Hay un código repetido en la lista: junta las cajas en un solo renglón.'
        using errcode = 'check_violation';
    end if;
    select jsonb_agg(jsonb_build_object(
             'cod_art', public.gv_pedido_mod_cod(it.value->>'cod_art'),
             'cod_original', it.value->'cod_original',
             'cajas', (nullif(it.value->>'cajas','')::numeric)::int,
             'uxb',   (nullif(it.value->>'uxb','')::numeric)::int) order by it.ord)
      into v_items_new
      from jsonb_array_elements(p_items) with ordinality it(value, ord);
  end if;

  -- ── se escribe la ficha, que es lo que lee Gestión / el Excel de ISIS ─────
  v_pay := v_o.sheets_payload;
  if v_items_new is not null then v_pay := v_pay || jsonb_build_object('items', v_items_new); end if;
  if v_suc_new  is not null then v_pay := v_pay || jsonb_build_object('sucursal_entrega', v_suc_new);
    if v_pay ? 'sucursalEntrega' then v_pay := v_pay || jsonb_build_object('sucursalEntrega', v_suc_new); end if;
  end if;
  update public.orders set sheets_payload = v_pay where id = p_order_id;

  -- El espejo de la página (`order_items`) se rearma SOLO si cada código resuelve a
  -- un producto del catálogo. Si alguno no resuelve, la ficha ya quedó bien —que es
  -- lo que mira la producción— y se deja constancia en el log de que el espejo no se
  -- tocó, en vez de dejar el pedido de la web con un renglón de menos.
  if v_items_new is not null then
    if not exists (select 1 from jsonb_array_elements(v_items_new) it
                    where not exists (select 1 from public.products p
                                       where public.gv_pedido_mod_cod(p.cod) = it.value->>'cod_art')
                      and not exists (select 1 from public.loke_products lp
                                       where public.gv_pedido_mod_cod(lp.cod) = it.value->>'cod_art')) then
      delete from public.order_items where order_id = p_order_id;
      insert into public.order_items (order_id, product_id, loke_product_id, cajas, uxb, is_loke, source)
      select p_order_id, p.id, lp.id, (it.value->>'cajas')::int, (it.value->>'uxb')::int,
             (p.id is null), 'gestion'
        from jsonb_array_elements(v_items_new) it
        left join public.products      p  on public.gv_pedido_mod_cod(p.cod)  = it.value->>'cod_art'
        left join public.loke_products lp on p.id is null
                                         and public.gv_pedido_mod_cod(lp.cod) = it.value->>'cod_art';
      v_sync := true;
    end if;
  end if;

  -- ── el log ────────────────────────────────────────────────────────────────
  v_tipo := case when v_items_new is not null and v_suc_new is not null then 'items+direccion'
                 when v_items_new is not null then 'items' else 'direccion' end;
  with viejo as (
    select it.value->>'cod_art' cod, (nullif(it.value->>'cajas',''))::numeric cajas
      from jsonb_array_elements(v_items_old) it),
  nuevo as (
    select it.value->>'cod_art' cod, (nullif(it.value->>'cajas',''))::numeric cajas
      from jsonb_array_elements(coalesce(v_items_new, v_items_old)) it),
  j as (
    select coalesce(n.cod, v.cod) cod, v.cajas de, n.cajas a
      from nuevo n full join viejo v
        on public.gv_pedido_mod_cod(v.cod) = public.gv_pedido_mod_cod(n.cod))
  select jsonb_build_object(
    'agregados',  coalesce((select jsonb_agg(jsonb_build_object('cod', cod, 'cajas', a)) from j where de is null), '[]'::jsonb),
    'quitados',   coalesce((select jsonb_agg(jsonb_build_object('cod', cod, 'cajas', de)) from j where a is null), '[]'::jsonb),
    'cambiados',  coalesce((select jsonb_agg(jsonb_build_object('cod', cod, 'de', de, 'a', a)) from j where de is not null and a is not null and de is distinct from a), '[]'::jsonb),
    'direccion',  case when v_suc_new is null then null
                       else jsonb_build_object('de', v_suc, 'a', v_suc_new,
                                               'creada', (p_dir_nueva is not null), 'slot', v_slot) end,
    'order_items_sync', v_sync
  ) into v_det;

  begin v_mail := coalesce(auth.jwt()->>'email', ''); exception when others then v_mail := ''; end;

  -- ⚠ v18.29: el log va a GESTIÓN por FDW, en la misma transacción. Si falla, el pedido
  -- no se modifica — que es lo que se quiere: un cambio sin registro no sirve.
  insert into virgilio."GV_Pedido_Mod_Log"
    (empresa, fuente, clave, order_id, nps, hecho_en, quien, quien_sesion, tipo, motivo,
     antes, despues, detalle, origen)
  values (v_emp, 'web', p_order_id::text, p_order_id, p_nps, now(),
          btrim(p_quien), nullif(v_mail,''), v_tipo, btrim(p_motivo),
          jsonb_build_object('items', v_items_old, 'sucursal_entrega', v_suc),
          jsonb_build_object('items', coalesce(v_items_new, v_items_old),
                             'sucursal_entrega', coalesce(v_suc_new, v_suc)),
          v_det, 'gestion:modificar-pedidos');

  return jsonb_build_object('ok', true, 'tipo', v_tipo, 'detalle', v_det,
                            'sucursal_entrega', coalesce(v_suc_new, v_suc),
                            'items', coalesce(v_items_new, v_items_old));
end $$;

revoke all on function public.gv_pedido_mod_ctx(text, bigint) from public, anon;
revoke all on function public.gv_pedido_mod_guardar(text, bigint, jsonb, text, jsonb, text, text, jsonb, text[]) from public, anon;
drop function if exists public.gv_pedido_mod_guardar(text, bigint, jsonb, text, jsonb, text, text, jsonb);
grant execute on function public.gv_pedido_mod_ctx(text, bigint) to authenticated;
grant execute on function public.gv_pedido_mod_guardar(text, bigint, jsonb, text, jsonb, text, text, jsonb, text[]) to authenticated;
grant execute on function public.gv_pedido_mod_cod(text) to authenticated, anon;
