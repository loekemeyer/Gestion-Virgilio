-- v26.73 · PASO 1 de 3 · CORRER EN EL PROYECTO DE CHEF (nkhzocgdpwtgrmwleihr), SQL Editor.
-- Copiar TODO este archivo (termina en «FIN PASO 1») y apretar Run. Tiene que decir «Success».
-- Crea la función que deja un pedido de Cencosud o Dorinka en la base de Chef igual que el panel:
-- llama a public.submit_order_fast a nombre de un admin de Chef y completa sheets_payload,
-- is_promo y extra_discount. No duplica la misma OC del mismo cliente y sucursal en 60 días.
-- Rollback: drop function public._krikos_insert_pedido(jsonb, boolean);

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

revoke all on function public._krikos_insert_pedido(jsonb, boolean) from public, anon, authenticated;
-- FIN PASO 1
