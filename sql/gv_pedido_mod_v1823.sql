-- ============================================================================
-- v18.23 — "Modificar Pedidos" (PPP de Gestión): backend.
-- PROYECTO: LK (kwkclwhmoygunqmlegrg). ⚠ NO es Virgilio.
--
-- POR QUÉ ACÁ Y NO EN GESTIÓN. Un pedido de la página no existe en la base de
-- Gestión: Gestión lo LEE de LK (`v_pedidos_web_np`, con la sesión de admin que
-- arma `pwebLkToken()`), y de la foto que guarda en `PPP_Web_Programacion`. La
-- fuente de verdad del contenido y de la dirección es `orders.sheets_payload` de
-- LK — de ahí salen el Excel de ISIS, el corte en NP, el m³ y el picking. Así que
-- modificar el pedido es escribir acá. Medido el 15/09: Gestión NO tiene ninguna
-- foreign table (0 filas en pg_foreign_table), o sea que no puede escribir en LK;
-- LK sí tiene FDW a Chef y a Virgilio.
--
-- POR QUÉ NO ENTRA CHEF TODAVÍA. La foreign table `chef_orders` es de SOLO
-- LECTURA: el update de prueba (en transacción abortada) devolvió
--   ERROR 42501: permission denied for table orders
--   CONTEXT: remote SQL command: UPDATE public.orders SET sheets_payload = ...
-- El usuario remoto del server `chef_db` no tiene UPDATE. Para Chef hace falta una
-- RPC del lado de Chef; hasta entonces la función corta con un mensaje claro en vez
-- de simular que se guardó.
--
-- LO QUE **NO** HAY QUE HACER ACÁ: recalcular NP, tandas ni m³. Eso ya existe y
-- corre solo — `ppp_web_resync` (Virgilio) pone la foto al día en cada carga de la
-- PPP, porque un pedido web SIEMPRE se pudo editar desde la página hasta que se
-- factura. Esta función cambia el pedido; la programación se reacomoda sola con la
-- máquina que ya está probada.
-- ============================================================================

-- ── 1) El log ───────────────────────────────────────────────────────────────
create table if not exists public."GV_Pedido_Mod_Log" (
  id        bigserial primary key,
  empresa   text        not null check (empresa in ('lk','chef')),
  order_id  bigint      not null,
  hecho_en  timestamptz not null default now(),
  quien     text,
  quien_uid uuid,
  tipo      text        not null check (tipo in ('items','direccion','items+direccion')),
  motivo    text,
  antes     jsonb       not null,
  despues   jsonb       not null,
  detalle   jsonb,
  origen    text        not null default 'gestion:modificar-pedidos'
);
create index if not exists gv_pedido_mod_log_pedido_ix
  on public."GV_Pedido_Mod_Log" (empresa, order_id, hecho_en desc);

alter table public."GV_Pedido_Mod_Log" enable row level security;
revoke insert, update, delete, truncate on public."GV_Pedido_Mod_Log" from anon, authenticated;
grant select on public."GV_Pedido_Mod_Log" to authenticated;
do $$ begin
  if not exists (select 1 from pg_policies where schemaname='public'
                   and tablename='GV_Pedido_Mod_Log' and policyname='gv_pedido_mod_log_admin_lee') then
    create policy gv_pedido_mod_log_admin_lee on public."GV_Pedido_Mod_Log"
      for select to authenticated
      using (exists (select 1 from public.admins a where a.auth_user_id = auth.uid()));
  end if;
end $$;

-- ── 2) Normalización de un código de artículo ──────────────────────────────
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

  select coalesce(jsonb_agg(to_jsonb(l) order by l.hecho_en desc), '[]'::jsonb)
    into v_log from public."GV_Pedido_Mod_Log" l
   where l.empresa = v_emp and l.order_id = p_order_id;

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
  p_espera     jsonb default null
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
  v_id    bigint;
  v_sync  boolean := false;
begin
  if not exists (select 1 from public.admins a where a.auth_user_id = auth.uid()) then
    raise exception 'Hace falta la sesión de supervisor para modificar un pedido.'
      using errcode = 'insufficient_privilege';
  end if;
  if v_emp <> 'lk' then
    raise exception 'El pedido es de la página de Chef y esa base todavía no acepta cambios desde Gestión: hay que modificarlo en la página de Chef.'
      using errcode = 'feature_not_supported';
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

  insert into public."GV_Pedido_Mod_Log"
    (empresa, order_id, quien, quien_uid, tipo, motivo, antes, despues, detalle)
  values (v_emp, p_order_id, nullif(btrim(coalesce(p_quien,'')), ''), auth.uid(), v_tipo,
          nullif(btrim(coalesce(p_motivo,'')), ''),
          jsonb_build_object('items', v_items_old, 'sucursal_entrega', v_suc),
          jsonb_build_object('items', coalesce(v_items_new, v_items_old),
                             'sucursal_entrega', coalesce(v_suc_new, v_suc)),
          v_det)
  returning id into v_id;

  return jsonb_build_object('ok', true, 'log_id', v_id, 'tipo', v_tipo, 'detalle', v_det,
                            'sucursal_entrega', coalesce(v_suc_new, v_suc),
                            'items', coalesce(v_items_new, v_items_old));
end $$;

revoke all on function public.gv_pedido_mod_ctx(text, bigint) from public, anon;
revoke all on function public.gv_pedido_mod_guardar(text, bigint, jsonb, text, jsonb, text, text, jsonb) from public, anon;
grant execute on function public.gv_pedido_mod_ctx(text, bigint) to authenticated;
grant execute on function public.gv_pedido_mod_guardar(text, bigint, jsonb, text, jsonb, text, text, jsonb) to authenticated;
grant execute on function public.gv_pedido_mod_cod(text) to authenticated, anon;
