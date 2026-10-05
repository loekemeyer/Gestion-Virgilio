-- =============================================================================
-- v26.68 · CORRER EN EL PROYECTO DE CHEF (nkhzocgdpwtgrmwleihr) · SQL Editor, todo junto.
-- Luis, 05/10/2026: «hace falta una alternativa como venimos haciendo (correr un sql en el
-- proyecto de chef que le permita al programa hacer lo que necesita)».
-- =============================================================================
-- QUÉ HACE: le da al auto-import de Krikos (corre en LK) UNA puerta para crear en Chef el
-- pedido de una OC de Cencosud, igual que hoy lo crea a mano el panel de LK por la Edge
-- Function create-super-order:
--   · cabecera del pedido en public.orders con su sheets_payload (los códigos con L viajan
--     ahí; el pedido de Cencosud NO lleva renglones en order_items: el panel manda items=[]);
--   · sheets_payload.order_number = id del pedido, como deja create-super-order (ver pedido 247).
--
-- SEGURIDAD: sólo entra quien tenga el token. El token vive en el Vault de LK
-- (KRIKOS_CHEF_TOKEN); acá queda sólo su sha256, así que este archivo no tiene nada secreto.
-- La función que escribe (_krikos_insert_pedido) no la puede llamar nadie de afuera.
--
-- NO DUPLICA: si ya existe un pedido del mismo cliente con la misma OC y la misma sucursal
-- en los últimos 60 días (por ejemplo, porque se cargó a mano antes), devuelve ESE pedido
-- y no crea otro.
--
-- AL FINAL corre una PRUEBA QUE NO GRABA NADA: arma un pedido con los mismos datos que el
-- panel le mandó a create-super-order para el pedido 247 (Cencosud, Panamericana, 02/10),
-- lo inserta adentro de una transacción que se deshace, y lista las columnas donde el
-- automático quedaría DISTINTO al 247 cargado a mano. Pegale el resultado a Claude.
-- Lo esperado: sólo diferencias de cosas que cambian con el tiempo (o ninguna), y
-- «quedó grabado algo?» = 0.
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
  v_ord  jsonb := coalesce(p_order, '{}'::jsonb) - 'items' - 'id' - 'created_at';
  v_oc   text  := nullif(btrim(coalesce(p_order #>> '{sheets_payload,pdf_oc}', '')), '');
  v_suc  text  := coalesce(p_order #>> '{sheets_payload,sucursal_entrega}', '');
  v_cols text;
  v_id   bigint;
  v_dup  bigint;
  v_fila jsonb;
begin
  if jsonb_typeof(p_order -> 'sheets_payload') is distinct from 'object' or v_oc is null then
    raise exception 'krikos: falta sheets_payload.pdf_oc';
  end if;
  if jsonb_typeof(p_order -> 'items') = 'array' and jsonb_array_length(p_order -> 'items') > 0 then
    raise exception 'krikos: sólo pedidos sin renglones (Cencosud: los ítems viajan en sheets_payload)';
  end if;
  if nullif(p_order ->> 'customer_id', '') is null then
    raise exception 'krikos: falta customer_id';
  end if;

  -- no duplicar la misma OC del mismo cliente y sucursal
  select o.id into v_dup
    from public.orders o
   where o.customer_id = (p_order ->> 'customer_id')::uuid
     and o.sheets_payload ->> 'pdf_oc' = v_oc
     and coalesce(o.sheets_payload ->> 'sucursal_entrega', '') = v_suc
     and o.created_at > now() - interval '60 days'
   order by o.id desc
   limit 1;
  if v_dup is not null and not p_simular then
    return jsonb_build_object('ok', true, 'order_id', v_dup, 'duplicado', true);
  end if;

  -- se escriben SÓLO las columnas que vienen en el pedido y existen en orders
  -- (igual que un insert de supabase-js con ese objeto); el resto toma su default
  select string_agg(quote_ident(c.column_name), ', ' order by c.ordinal_position)
    into v_cols
    from information_schema.columns c
   where c.table_schema = 'public' and c.table_name = 'orders'
     and c.is_generated = 'NEVER'
     and coalesce(c.identity_generation, '') <> 'ALWAYS'
     and v_ord ? c.column_name;
  if v_cols is null then
    raise exception 'krikos: el pedido no trae ninguna columna de orders';
  end if;

  begin
    execute format(
      'insert into public.orders (%1$s) select %1$s from jsonb_populate_record(null::public.orders, $1) returning id',
      v_cols) into v_id using v_ord;
    update public.orders
       set sheets_payload = jsonb_set(sheets_payload, '{order_number}', to_jsonb(v_id::text))
     where id = v_id;
    select to_jsonb(o) into v_fila from public.orders o where o.id = v_id;
    if p_simular then
      raise exception using errcode = 'P0001', message = '__krikos_simulacion__';
    end if;
  exception when sqlstate 'P0001' then
    if sqlerrm = '__krikos_simulacion__' then
      return jsonb_build_object('ok', true, 'simulado', true, 'columnas', v_cols, 'fila', v_fila);
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

-- ── PRUEBA (no graba nada): el automático contra el pedido 247 cargado a mano ──────────
-- Si algo falla (por ejemplo una columna obligatoria que el panel no manda), la prueba NO se
-- corta: anota el error y lista las columnas obligatorias de orders con su valor en el 247.
drop table if exists pg_temp._krikos_prueba;
create temp table _krikos_prueba (columna text, pedido_247_a_mano jsonb, automatico_simulado jsonb);

do $prueba$
declare
  v_f jsonb; v_body jsonb; v_r jsonb;
begin
  select to_jsonb(o) into v_f from public.orders o where o.id = 247;
  if v_f is null then
    insert into _krikos_prueba values ('__ERROR__', null, to_jsonb('no existe el pedido 247'::text));
    return;
  end if;
  -- exactamente las claves que el panel le manda a create-super-order
  v_body := (select jsonb_object_agg(e.key, e.value) from jsonb_each(v_f) e
              where e.key in ('customer_id','status','payment_method','payment_discount',
                              'web_discount','subtotal','total'))
            || jsonb_build_object('items', '[]'::jsonb,
                 'sheets_payload', (v_f -> 'sheets_payload') || '{"order_number": "", "pdf_oc": "__PRUEBA__"}'::jsonb);
  begin
    v_r := public._krikos_insert_pedido(v_body, true);
    insert into _krikos_prueba
      select k.key, v_f -> k.key, v_r -> 'fila' -> k.key
        from jsonb_object_keys(v_f) k(key)
       where k.key not in ('id', 'created_at', 'sheets_payload')
         and (v_f -> k.key) is distinct from (v_r -> 'fila' -> k.key);
    insert into _krikos_prueba values ('__columnas que escribe__', null, to_jsonb(v_r ->> 'columnas'));
    insert into _krikos_prueba values ('__order_number simulado__', null, v_r -> 'fila' -> 'sheets_payload' -> 'order_number');
  exception when others then
    insert into _krikos_prueba values ('__ERROR__', null, to_jsonb(sqlerrm));
  end;
  -- columnas obligatorias sin default: si el panel no las manda, create-super-order las completa
  insert into _krikos_prueba
    select 'obligatoria: ' || c.column_name, v_f -> c.column_name, null
      from information_schema.columns c
     where c.table_schema = 'public' and c.table_name = 'orders'
       and c.is_nullable = 'NO' and c.column_default is null
       and c.is_generated = 'NEVER' and coalesce(c.identity_generation, '') = '';
  insert into _krikos_prueba
    select '__triggers de orders__', null, to_jsonb(string_agg(tgname, ', '))
      from pg_trigger where tgrelid = 'public.orders'::regclass and not tgisinternal;
end
$prueba$;

-- lo que hay que pegarle a Claude (y la prueba de que no quedó nada grabado)
select * from _krikos_prueba
union all
select '__quedó grabado algo? (tiene que dar 0)__', null,
       to_jsonb((select count(*) from public.orders where sheets_payload ->> 'pdf_oc' = '__PRUEBA__'));
