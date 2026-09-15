-- ============================================================================
-- v18.45 — "Modificar Pedidos": los pedidos de CHEF también.  PROYECTO: LK.
--
-- Hasta la v18.39 Chef quedaba afuera porque el FDW de LK a Chef podía LEER pero
-- no escribir. El 15/09 Thomas corrió del lado de Chef lo que faltaba:
--
--   grant update (sheets_payload) on public.orders to loke_reader;
--   grant select, insert on public.customer_delivery_addresses to loke_reader;
--   create policy loke_reader_edita_ficha    on public.orders
--     for update to loke_reader using (true) with check (true);
--   create policy loke_reader_lee_dir        on public.customer_delivery_addresses
--     for select to loke_reader using (true);
--   create policy loke_reader_agrega_dir     on public.customer_delivery_addresses
--     for insert to loke_reader with check (true);
--
-- ⚠ Las POLICIES hacen falta además de los grants: en Chef las dos tablas tienen
-- RLS prendida. Y el `update` está acotado por columna, así que `loke_reader` sólo
-- puede tocar `sheets_payload`: ni el total, ni el estado, ni el cliente.
--
-- ⚠ Y OJO CON VERIFICARLO: `has_table_privilege(...,'UPDATE')` da **false** aunque
-- el grant esté bien, porque es un permiso POR COLUMNA. Va
-- `has_column_privilege('loke_reader','public.orders','sheets_payload','UPDATE')`,
-- o directamente el update de prueba en una transacción que se aborta.
--
-- CÓMO QUEDÓ ARMADO. No se tocó el camino de LK, que ya estaba probado y en uso:
-- `gv_pedido_mod_ctx` y `gv_pedido_mod_guardar` DESPACHAN a una gemela `_chef`
-- cuando la empresa es Chef. Diferencias reales entre las dos ramas:
--
--   · tablas: `chef_orders`, `chef_customer_delivery_addresses`, `chef_customers`
--     (foreign tables) y el catálogo `chef_ext.products`;
--   · la tabla de direcciones de Chef NO tiene `pending_isis`;
--   · `chef_orders` es una foreign table: no admite `for update`, así que la fila no
--     se lockea. Lo que protege del cambio de atrás es `p_espera`, que compara la
--     ficha entera;
--   · Chef no tiene `order_items` de este lado: la ficha es lo único que mantener;
--   · la sucursal: los 63 pedidos de la PÁGINA de Chef la guardan como
--     `sucursalEntrega` (camelCase) y los 10 de Cotizador/Krikos como
--     `sucursal_entrega`. Se leen las dos y se escriben las dos;
--   · los códigos: un artículo de Loeke vendido por Chef va con **L** al final
--     (regla del dueño v13.71). Un código vale si está en `chef_ext.products`, o si
--     pelándole la L está en `products` de LK, o si ya aparece en alguna ficha de
--     Chef. Medido el 15/09: de 106 códigos en uso, 91 por la primera vía y 3 por la
--     segunda; el resto entra por la tercera, que es la que evita bloquear lo que ya
--     existe sin dejar pasar un código tipeado mal;
--   · el catálogo viaja DENTRO del contexto: `chef_ext` no está publicado en la API
--     de PostgREST, así que el front no puede pedirlo por REST como el de LK.
--
-- Prueba (15/09, transacción abortada, pedido CH 229): sin motivo corta; con motivo,
-- el 769L pasó de 8 a 12 cajas, se agregó el 043 ×2, se creó la dirección "PRUEBA
-- Claude CH" (slot 2) y quedó elegida, y se escribió 1 fila de log con
-- empresa='chef'. Tras el rollback, nada.
-- ============================================================================


-- ── 1) El contexto del pedido de Chef ──────────────────────────────────────
create or replace function public.gv_pedido_mod_ctx_chef(p_order_id bigint)
returns jsonb
language plpgsql security definer set search_path to 'public','chef_ext','pg_temp' as $fn$
declare
  v_o record; v_c record; v_suc text;
  v_items jsonb; v_dirs jsonb; v_log jsonb; v_est jsonb; v_cat jsonb;
begin
  if not exists (select 1 from public.admins a where a.auth_user_id = auth.uid()) then
    raise exception 'Hace falta la sesion de supervisor para abrir un pedido.' using errcode='insufficient_privilege';
  end if;

  select o.id, o.sheets_payload, o.enviado_a_compras_at, o.customer_id
    into v_o from public.chef_orders o where o.id = p_order_id;
  if not found then raise exception 'No existe el pedido % en la pagina de Chef.', p_order_id; end if;

  -- los pedidos de la PAGINA de Chef guardan la sucursal como `sucursalEntrega` (camelCase);
  -- los de Cotizador y Krikos como `sucursal_entrega`. Medido: 63 y 10.
  v_suc := coalesce(v_o.sheets_payload->>'sucursal_entrega', v_o.sheets_payload->>'sucursalEntrega');
  select c.id, c.cod_cliente, c.business_name into v_c
    from public.chef_customers c where c.id = v_o.customer_id;

  select coalesce(jsonb_agg(jsonb_build_object(
           'i', it.ord - 1, 'cod_art', it.value->>'cod_art',
           'cod', public.gv_pedido_mod_cod(it.value->>'cod_art'),
           'cajas', nullif(coalesce(it.value->>'cajas', it.value->>'Cajas'), '')::numeric,
           'uxb', nullif(it.value->>'uxb', '')::numeric,
           'descripcion', coalesce(p.description, lp.description),
           'catalogo', (p.id is not null or lp.id is not null)) order by it.ord), '[]'::jsonb)
    into v_items
    from jsonb_array_elements(coalesce(v_o.sheets_payload->'items', '[]'::jsonb)) with ordinality it(value, ord)
    left join chef_ext.products p on public.gv_pedido_mod_cod(p.cod) = public.gv_pedido_mod_cod(it.value->>'cod_art')
    -- un articulo de Loeke vendido por Chef va con L al final (regla del dueno v13.71):
    -- se lo busca en el catalogo de LK pelandole la L
    left join public.products lp on p.id is null
         and public.gv_pedido_mod_cod(lp.cod) = public.gv_pedido_mod_cod(regexp_replace(it.value->>'cod_art', 'L$', '', 'i'));

  select coalesce(jsonb_agg(jsonb_build_object(
           'slot', d.slot, 'label', d.label, 'direccion', d.direccion_entrega,
           'localidad', d.localidad, 'provincia', d.provincia, 'barrio', d.zona_expreso, 'cp', d.cp,
           'actual', btrim(lower(d.label)) = btrim(lower(coalesce(v_suc, '')))) order by d.slot), '[]'::jsonb)
    into v_dirs
    from public.chef_customer_delivery_addresses d where d.customer_id = v_o.customer_id;

  select to_jsonb(g) into v_est from virgilio.gv_pedido_web_estado_pagina g
   where g.empresa = 'chef' and g.order_id = p_order_id;

  select coalesce(jsonb_agg(jsonb_build_object(
           'hecho_en', l.hecho_en, 'quien', l.quien, 'quien_sesion', l.quien_sesion,
           'tipo', l.tipo, 'motivo', l.motivo, 'detalle', l.detalle) order by l.hecho_en desc), '[]'::jsonb)
    into v_log
    from virgilio."GV_Pedido_Mod_Log" l
   where l.empresa = 'chef' and l.fuente = 'web' and l.order_id = p_order_id;

  -- el catalogo viaja EN el contexto: `chef_ext` no esta publicado en la API, y son ~150 filas
  select coalesce(jsonb_agg(jsonb_build_object('cod', public.gv_pedido_mod_cod(p.cod),
                                               'desc', p.description, 'uxb', p.uxb) order by p.cod), '[]'::jsonb)
    into v_cat from chef_ext.products p where coalesce(p.active, true);

  return jsonb_build_object(
    'empresa', 'chef', 'order_id', p_order_id,
    'cod_cliente', coalesce(v_c.cod_cliente::text, v_o.sheets_payload->>'cod_cliente'),
    'razon_social', v_c.business_name, 'sucursal_entrega', v_suc,
    'enviado_a_compras', (v_o.enviado_a_compras_at is not null),
    'items', v_items, 'items_raw', coalesce(v_o.sheets_payload->'items', '[]'::jsonb),
    'direcciones', v_dirs, 'sin_stock', '[]'::jsonb, 'catalogo', v_cat,
    'estado', coalesce(v_est, '{}'::jsonb), 'log', v_log);
end $fn$;
revoke all on function public.gv_pedido_mod_ctx_chef(bigint) from public, anon;
grant execute on function public.gv_pedido_mod_ctx_chef(bigint) to authenticated;

-- ── 2) El guardado ─────────────────────────────────────────────────────────
create or replace function public.gv_pedido_mod_guardar_chef(
  p_order_id   bigint,
  p_items      jsonb  default null,
  p_sucursal   text   default null,
  p_dir_nueva  jsonb  default null,
  p_motivo     text   default null,
  p_quien      text   default null,
  p_espera     jsonb  default null,
  p_nps        text[] default null
) returns jsonb
language plpgsql security definer set search_path to 'public','chef_ext','pg_temp' as $fn$
declare
  v_o record; v_suc text; v_suc_new text;
  v_items_old jsonb; v_items_new jsonb;
  v_slot int; v_label text; v_malos text; v_tipo text; v_det jsonb; v_pay jsonb; v_mail text;
begin
  if not exists (select 1 from public.admins a where a.auth_user_id = auth.uid()) then
    raise exception 'Hace falta la sesion de supervisor para modificar un pedido.' using errcode='insufficient_privilege';
  end if;
  if length(btrim(coalesce(p_motivo,''))) < 3 then
    raise exception 'Falta el justificativo: hay que escribir por que se modifica el pedido.' using errcode='check_violation';
  end if;
  if length(btrim(coalesce(p_quien,''))) < 2 then
    raise exception 'Falta quien hace la modificacion.' using errcode='check_violation';
  end if;
  if p_items is null and p_sucursal is null and p_dir_nueva is null then
    raise exception 'No viene ningun cambio.' using errcode='check_violation';
  end if;

  -- `chef_orders` es una FOREIGN TABLE: no admite `for update`, asi que no se lockea la fila.
  -- La proteccion contra el cambio de atras es `p_espera`, que compara la ficha entera.
  select o.id, o.sheets_payload, o.customer_id, o.enviado_a_compras_at
    into v_o from public.chef_orders o where o.id = p_order_id;
  if not found then raise exception 'No existe el pedido % en la pagina de Chef.', p_order_id; end if;
  if v_o.sheets_payload is null then
    raise exception 'El pedido % no tiene ficha: no se puede modificar desde aca.', p_order_id;
  end if;

  if exists (select 1 from virgilio.gv_pedido_web_estado_pagina g
              where g.empresa = 'chef' and g.order_id = p_order_id and (g.facturado or g.entregado)) then
    raise exception 'El pedido ya esta facturado o entregado: no se modifica desde aca.' using errcode='check_violation';
  end if;

  v_items_old := coalesce(v_o.sheets_payload->'items', '[]'::jsonb);
  v_suc := coalesce(v_o.sheets_payload->>'sucursal_entrega', v_o.sheets_payload->>'sucursalEntrega');
  if p_espera is not null and p_espera is distinct from v_items_old then
    raise exception 'El pedido cambio mientras lo tenias abierto. Cerra y volve a abrirlo.' using errcode='serialization_failure';
  end if;

  if p_dir_nueva is not null then
    v_label := btrim(coalesce(p_dir_nueva->>'label', p_dir_nueva->>'direccion', ''));
    if v_label = '' then raise exception 'La direccion nueva necesita un nombre.' using errcode='check_violation'; end if;
    if exists (select 1 from public.chef_customer_delivery_addresses d
                where d.customer_id = v_o.customer_id and btrim(lower(d.label)) = btrim(lower(v_label))) then
      raise exception 'El cliente ya tiene una direccion con el nombre "%".', v_label using errcode='unique_violation';
    end if;
    select coalesce(max(d.slot), 0) + 1 into v_slot
      from public.chef_customer_delivery_addresses d where d.customer_id = v_o.customer_id;
    -- la tabla de Chef NO tiene `pending_isis` (la de LK si)
    insert into public.chef_customer_delivery_addresses
      (customer_id, slot, label, direccion_entrega, calle, altura, cp, localidad, provincia,
       zona_expreso, observaciones)
    values (v_o.customer_id, v_slot, v_label,
            nullif(btrim(coalesce(p_dir_nueva->>'direccion','')), ''),
            nullif(btrim(coalesce(p_dir_nueva->>'calle','')), ''),
            nullif(btrim(coalesce(p_dir_nueva->>'altura','')), ''),
            nullif(btrim(coalesce(p_dir_nueva->>'cp','')), ''),
            nullif(btrim(coalesce(p_dir_nueva->>'localidad','')), ''),
            nullif(btrim(coalesce(p_dir_nueva->>'provincia','')), ''),
            nullif(btrim(coalesce(p_dir_nueva->>'barrio','')), ''),
            nullif(btrim(coalesce(p_dir_nueva->>'observaciones','')), ''));
    v_suc_new := v_label;
  elsif p_sucursal is not null then
    if not exists (select 1 from public.chef_customer_delivery_addresses d
                    where d.customer_id = v_o.customer_id
                      and btrim(lower(d.label)) = btrim(lower(p_sucursal))) then
      raise exception 'El cliente no tiene ninguna direccion que se llame "%".', p_sucursal using errcode='check_violation';
    end if;
    v_suc_new := btrim(p_sucursal);
  end if;

  if p_items is not null then
    if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
      raise exception 'Un pedido no puede quedar sin ningun renglon.' using errcode='check_violation';
    end if;
    -- un codigo vale si esta en el catalogo de Chef, o si pelandole la L esta en el de LK
    -- (articulo de Loeke vendido por Chef), o si ya aparece en alguna ficha de Chef
    select string_agg(distinct x.cod_art, ', ') into v_malos
      from (select it.value->>'cod_art' as cod_art,
                   nullif(it.value->>'cajas','')::numeric as cajas,
                   nullif(it.value->>'uxb','')::numeric   as uxb
              from jsonb_array_elements(p_items) it) x
     where public.gv_pedido_mod_cod(x.cod_art) is null
        or coalesce(x.cajas, 0) <= 0 or x.cajas <> trunc(x.cajas)
        or coalesce(x.uxb, 0) <= 0
        or (not exists (select 1 from chef_ext.products p
                         where public.gv_pedido_mod_cod(p.cod) = public.gv_pedido_mod_cod(x.cod_art))
        and not exists (select 1 from public.products p
                         where public.gv_pedido_mod_cod(p.cod) =
                               public.gv_pedido_mod_cod(regexp_replace(x.cod_art, 'L$', '', 'i')))
        and not exists (select 1 from public.chef_orders o2, jsonb_array_elements(o2.sheets_payload->'items') i2
                         where o2.sheets_payload is not null
                           and public.gv_pedido_mod_cod(i2.value->>'cod_art') = public.gv_pedido_mod_cod(x.cod_art)));
    if v_malos is not null then
      raise exception 'Renglones que no puedo guardar (codigo desconocido o cantidad invalida): %', v_malos
        using errcode='check_violation';
    end if;
    if exists (select 1 from (select public.gv_pedido_mod_cod(it.value->>'cod_art') c
                                from jsonb_array_elements(p_items) it) q
                group by q.c having count(*) > 1) then
      raise exception 'Hay un codigo repetido en la lista: junta las cajas en un solo renglon.' using errcode='check_violation';
    end if;
    select jsonb_agg(jsonb_build_object(
             'cod_art', public.gv_pedido_mod_cod(it.value->>'cod_art'),
             'cajas', (nullif(it.value->>'cajas','')::numeric)::int,
             'uxb',   (nullif(it.value->>'uxb','')::numeric)::int) order by it.ord)
      into v_items_new
      from jsonb_array_elements(p_items) with ordinality it(value, ord);
  end if;

  v_pay := v_o.sheets_payload;
  if v_items_new is not null then v_pay := v_pay || jsonb_build_object('items', v_items_new); end if;
  if v_suc_new is not null then
    -- se escriben las dos claves: la pagina de Chef lee `sucursalEntrega` y el resto `sucursal_entrega`
    v_pay := v_pay || jsonb_build_object('sucursal_entrega', v_suc_new);
    if v_pay ? 'sucursalEntrega' then v_pay := v_pay || jsonb_build_object('sucursalEntrega', v_suc_new); end if;
  end if;
  update public.chef_orders set sheets_payload = v_pay where id = p_order_id;
  -- Chef no tiene `order_items` de este lado: la ficha es lo unico que hay que mantener.

  v_tipo := case when v_items_new is not null and v_suc_new is not null then 'items+direccion'
                 when v_items_new is not null then 'items' else 'direccion' end;
  with viejo as (select it.value->>'cod_art' cod, (nullif(it.value->>'cajas',''))::numeric cajas
                   from jsonb_array_elements(v_items_old) it),
       nuevo as (select it.value->>'cod_art' cod, (nullif(it.value->>'cajas',''))::numeric cajas
                   from jsonb_array_elements(coalesce(v_items_new, v_items_old)) it),
       j as (select coalesce(n.cod, v.cod) cod, v.cajas de, n.cajas a
               from nuevo n full join viejo v
                 on public.gv_pedido_mod_cod(v.cod) = public.gv_pedido_mod_cod(n.cod))
  select jsonb_build_object(
    'agregados', coalesce((select jsonb_agg(jsonb_build_object('cod', cod, 'cajas', a)) from j where de is null), '[]'::jsonb),
    'quitados',  coalesce((select jsonb_agg(jsonb_build_object('cod', cod, 'cajas', de)) from j where a is null), '[]'::jsonb),
    'cambiados', coalesce((select jsonb_agg(jsonb_build_object('cod', cod, 'de', de, 'a', a)) from j
                            where de is not null and a is not null and de is distinct from a), '[]'::jsonb),
    'direccion', case when v_suc_new is null then null
                      else jsonb_build_object('de', v_suc, 'a', v_suc_new,
                                              'creada', (p_dir_nueva is not null), 'slot', v_slot) end,
    'order_items_sync', false
  ) into v_det;

  begin v_mail := coalesce(auth.jwt()->>'email',''); exception when others then v_mail := ''; end;
  insert into virgilio."GV_Pedido_Mod_Log"
    (empresa, fuente, clave, order_id, nps, hecho_en, quien, quien_sesion, tipo, motivo,
     antes, despues, detalle, origen)
  values ('chef', 'web', p_order_id::text, p_order_id, p_nps, now(),
          btrim(p_quien), nullif(v_mail,''), v_tipo, btrim(p_motivo),
          jsonb_build_object('items', v_items_old, 'sucursal_entrega', v_suc),
          jsonb_build_object('items', coalesce(v_items_new, v_items_old),
                             'sucursal_entrega', coalesce(v_suc_new, v_suc)),
          v_det, 'gestion:modificar-pedidos');

  return jsonb_build_object('ok', true, 'tipo', v_tipo, 'detalle', v_det,
                            'sucursal_entrega', coalesce(v_suc_new, v_suc),
                            'items', coalesce(v_items_new, v_items_old));
end $fn$;
revoke all on function public.gv_pedido_mod_guardar_chef(bigint, jsonb, text, jsonb, text, text, jsonb, text[]) from public, anon;
grant execute on function public.gv_pedido_mod_guardar_chef(bigint, jsonb, text, jsonb, text, text, jsonb, text[]) to authenticated;

-- ── El despacho, en las dos funciones de LK ────────────────────────────────
-- En `gv_pedido_mod_ctx`, donde antes cortaba con "esa base todavía no acepta
-- cambios", ahora dice:
--
--   if v_emp = 'chef' then return public.gv_pedido_mod_ctx_chef(p_order_id); end if;
--   if v_emp <> 'lk' then
--     raise exception 'Empresa desconocida: %', v_emp using errcode = 'check_violation';
--   end if;
--
-- Y en `gv_pedido_mod_guardar`:
--
--   if v_emp = 'chef' then
--     return public.gv_pedido_mod_guardar_chef(p_order_id, p_items, p_sucursal, p_dir_nueva,
--                                              p_motivo, p_quien, p_espera, p_nps);
--   end if;
--   if v_emp <> 'lk' then
--     raise exception 'Empresa desconocida: %', v_emp using errcode = 'check_violation';
--   end if;
--
-- El resto del cuerpo de las dos, sin cambios (sql/gv_pedido_mod_v1829.sql).
--
-- ── Rollback ───────────────────────────────────────────────────────────────
-- Volver los dos `if` al `raise exception ... feature_not_supported` y
-- `drop function public.gv_pedido_mod_guardar_chef(bigint,jsonb,text,jsonb,text,text,jsonb,text[]);`
-- `drop function public.gv_pedido_mod_ctx_chef(bigint);`
-- Del lado de Chef, los `revoke` y `drop policy` que están arriba, al revés.
