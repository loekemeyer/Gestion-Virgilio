-- =============================================================================
-- v26.70 · CORRER EN EL PROYECTO DE CHEF (nkhzocgdpwtgrmwleihr) · SQL Editor, todo junto.
-- Luis, 05/10/2026: «correr un sql en el proyecto de chef que le permita al programa hacer lo
-- que necesita» · «DORINKA Y CENCOSUD QUIERO QUE SE CARGUEN AUTOMATICAMENTE».
-- =============================================================================
-- NO CAMBIA DÓNDE VIVE NINGÚN PEDIDO. Hoy, cuando se carga a mano:
--   · Cencosud (PDF Krikos del admin de LK): artículos de LK con L, y el pedido queda guardado
--     en la base de CHEF porque lo factura Chef (pedidos 245, 246 y 247 del 02/10).
--   · Dorinka (admin de Chef): artículos de Chef sin L, pedido en la base de Chef (241 del 30/09).
-- Este SQL le da a la carga automática UNA puerta para dejar el pedido en el mismo lugar y de
-- la misma forma: llama a la MISMA función con la que el admin de Chef carga hoy
-- (public.submit_order_fast), a nombre de un admin de Chef, y después completa sheets_payload,
-- is_promo y extra_discount igual que el panel.
--
-- SEGURIDAD: sólo entra quien tenga el token. El token vive en el Vault de LK
-- (KRIKOS_CHEF_TOKEN); acá queda sólo su sha256, así que este archivo no tiene nada secreto.
-- La función que escribe (_krikos_insert_pedido) no la puede llamar nadie de afuera.
--
-- NO DUPLICA: si ya hay un pedido del mismo cliente con la misma OC y la misma sucursal en los
-- últimos 60 días (por ejemplo, porque alguien lo cargó a mano antes), devuelve ESE pedido.
--
-- AL FINAL corre una PRUEBA QUE NO GRABA NADA: rearma el 247 (Cencosud) y el 241 (Dorinka) por
-- la puerta automática adentro de una transacción que se deshace, y lista en qué quedarían
-- distintos de los cargados a mano. Pegale el resultado a Claude. Esperado: sólo diferencias de
-- cosas que cambian solas (fechas, estado) y «quedó grabado algo?» = 0.
--
-- ROLLBACK: drop function public.krikos_crear_pedido_super(text, jsonb);
--           drop function public._krikos_insert_pedido(jsonb, boolean);
-- =============================================================================

create or replace function public._krikos_insert_pedido(p_order jsonb, p_simular boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $fn$
declare
  v_oc    text  := nullif(btrim(coalesce(p_order #>> '{sheets_payload,pdf_oc}', '')), '');
  v_suc   text  := coalesce(p_order #>> '{sheets_payload,sucursal_entrega}', '');
  v_cli   uuid;
  v_items jsonb;
  v_admin uuid;
  v_mail  text;
  v_id    bigint;
  v_dup   bigint;
  v_fila  jsonb;
  v_det   jsonb;
begin
  if jsonb_typeof(p_order -> 'sheets_payload') is distinct from 'object' or v_oc is null then
    raise exception 'krikos: falta sheets_payload.pdf_oc';
  end if;
  if nullif(p_order ->> 'customer_id', '') is null then
    raise exception 'krikos: falta customer_id';
  end if;
  v_cli   := (p_order ->> 'customer_id')::uuid;
  v_items := case when jsonb_typeof(p_order -> 'items') = 'array' then p_order -> 'items' else '[]'::jsonb end;

  -- no duplicar la misma OC del mismo cliente y sucursal
  select o.id into v_dup
    from public.orders o
   where o.customer_id = v_cli
     and o.sheets_payload ->> 'pdf_oc' = v_oc
     and coalesce(o.sheets_payload ->> 'sucursal_entrega', '') = v_suc
     and o.created_at > now() - interval '60 days'
   order by o.id desc
   limit 1;
  if v_dup is not null and not p_simular then
    return jsonb_build_object('ok', true, 'order_id', v_dup, 'duplicado', true);
  end if;

  -- a nombre de un admin de Chef: es el mismo control que pasa el panel al cargar a mano
  select a.auth_user_id, u.email into v_admin, v_mail
    from public.admins a
    left join auth.users u on u.id = a.auth_user_id
   order by (u.email = 'loekemeyer.n8n@gmail.com') desc nulls last, a.created_at
   limit 1;
  if v_admin is null then
    raise exception 'krikos: no hay ningún admin en public.admins';
  end if;
  perform set_config('request.jwt.claim.sub', v_admin::text, true);
  perform set_config('request.jwt.claims',
    jsonb_build_object('sub', v_admin, 'role', 'authenticated', 'email', v_mail)::text, true);

  begin
    v_id := public.submit_order_fast(
      p_auth_user_id     => v_admin,
      p_customer_id      => v_cli,
      p_status           => coalesce(p_order ->> 'status', 'pendiente'),
      p_payment_method   => coalesce(p_order ->> 'payment_method', 'Sin especificar'),
      p_payment_discount => coalesce((p_order ->> 'payment_discount')::numeric, 0),
      p_web_discount     => coalesce((p_order ->> 'web_discount')::numeric, 0),
      p_subtotal         => coalesce((p_order ->> 'subtotal')::numeric, 0),
      p_total            => coalesce((p_order ->> 'total')::numeric, 0),
      p_items            => v_items);
    -- lo mismo que hace el panel después de crear el pedido
    update public.orders
       set sheets_payload = jsonb_set(p_order -> 'sheets_payload', '{order_number}', to_jsonb(v_id::text)),
           is_promo = false,
           extra_discount = 0
     where id = v_id;
    select to_jsonb(o) into v_fila from public.orders o where o.id = v_id;
    select coalesce(jsonb_agg(to_jsonb(i)), '[]'::jsonb) into v_det from public.order_items i where i.order_id = v_id;
    if p_simular then
      raise exception using errcode = 'P0001', message = '__krikos_simulacion__';
    end if;
  exception when sqlstate 'P0001' then
    if sqlerrm = '__krikos_simulacion__' then
      return jsonb_build_object('ok', true, 'simulado', true, 'admin', v_mail, 'fila', v_fila, 'items', v_det);
    end if;
    raise;
  end;

  return jsonb_build_object('ok', true, 'order_id', v_id, 'duplicado', false);
end
$fn$;

create or replace function public.krikos_crear_pedido_super(p_token text, p_order jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $fn$
begin
  if p_token is null
     or encode(sha256(convert_to(p_token, 'UTF8')), 'hex')
        <> '7e2fb177e09403b13cbc42cd7abcf09ab912868b9d6f6937e5ddb1d7c625f155' then
    raise exception 'krikos_crear_pedido_super: token inválido' using errcode = '28000';
  end if;
  return public._krikos_insert_pedido(p_order, false);
end
$fn$;

revoke all on function public._krikos_insert_pedido(jsonb, boolean) from public, anon, authenticated;
revoke all on function public.krikos_crear_pedido_super(text, jsonb) from public;
grant execute on function public.krikos_crear_pedido_super(text, jsonb) to anon, authenticated, service_role;

-- ── PRUEBA (no graba nada): la puerta automática contra el 247 (Cencosud) y el 241 (Dorinka) ──
-- Si algo falla, la prueba NO se corta: anota el error para que Claude lo vea.
drop table if exists pg_temp._krikos_prueba;
create temp table _krikos_prueba (que text, a_mano jsonb, automatico jsonb);

do $prueba$
declare
  v_ref   record;
  v_f     jsonb;
  v_items jsonb;
  v_body  jsonb;
  v_r     jsonb;
begin
  for v_ref in select * from (values ('Cencosud 247', 247::bigint), ('Dorinka 241', 241::bigint)) t(nombre, id) loop
    select to_jsonb(o) into v_f from public.orders o where o.id = v_ref.id;
    if v_f is null then
      insert into _krikos_prueba values (v_ref.nombre || ' · ERROR', null, to_jsonb('no existe el pedido'::text));
      continue;
    end if;
    -- los renglones como los manda el panel (un artículo de Loeke va en product_id con is_loke)
    select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
             'product_id', coalesce(nullif(s.j ->> 'product_id', ''), s.j ->> 'loke_product_id'),
             'cajas', s.j -> 'cajas', 'uxb', s.j -> 'uxb',
             'is_loke', coalesce(s.j -> 'is_loke', 'false'::jsonb),
             'unit_list_price', s.j -> 'unit_list_price', 'unit_your_price', s.j -> 'unit_your_price',
             'line_total', s.j -> 'line_total'))), '[]'::jsonb)
      into v_items
      from (select to_jsonb(i) j from public.order_items i where i.order_id = v_ref.id) s;
    -- exactamente lo que manda el panel al cargar a mano
    v_body := (select jsonb_object_agg(e.key, e.value) from jsonb_each(v_f) e
                where e.key in ('customer_id','status','payment_method','payment_discount',
                                'web_discount','subtotal','total'))
              || jsonb_build_object('items', v_items,
                   'sheets_payload', (v_f -> 'sheets_payload') || '{"order_number": "", "pdf_oc": "__PRUEBA__"}'::jsonb);
    begin
      v_r := public._krikos_insert_pedido(v_body, true);
      insert into _krikos_prueba
        select v_ref.nombre || ' · ' || k.key, v_f -> k.key, v_r -> 'fila' -> k.key
          from jsonb_object_keys(v_f) k(key)
         where k.key not in ('id', 'created_at', 'sheets_payload')
           and (v_f -> k.key) is distinct from (v_r -> 'fila' -> k.key);
      insert into _krikos_prueba values (v_ref.nombre || ' · renglones', to_jsonb(jsonb_array_length(v_items)),
                                         to_jsonb(jsonb_array_length(v_r -> 'items')));
      insert into _krikos_prueba
        select v_ref.nombre || ' · renglones distintos', null, to_jsonb(count(*))
          from (select to_jsonb(i) - 'id' - 'order_id' - 'created_at' x from public.order_items i where i.order_id = v_ref.id
                except all
                select e - 'id' - 'order_id' - 'created_at' from jsonb_array_elements(v_r -> 'items') e) z;
      insert into _krikos_prueba values (v_ref.nombre || ' · admin que usa', null, to_jsonb(v_r ->> 'admin'));
    exception when others then
      insert into _krikos_prueba values (v_ref.nombre || ' · ERROR', null, to_jsonb(sqlerrm));
    end;
  end loop;
  insert into _krikos_prueba
    select 'triggers de orders', null, to_jsonb(string_agg(tgname, ', '))
      from pg_trigger where tgrelid = 'public.orders'::regclass and not tgisinternal;
end
$prueba$;

-- lo que hay que pegarle a Claude (y la prueba de que no quedó nada grabado)
select * from _krikos_prueba
union all
select 'quedó grabado algo? (tiene que dar 0)', null,
       to_jsonb((select count(*) from public.orders where sheets_payload ->> 'pdf_oc' = '__PRUEBA__'));
