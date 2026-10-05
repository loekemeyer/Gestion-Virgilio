-- v26.73 · PASO 3 de 3 · CORRER EN EL PROYECTO DE CHEF (nkhzocgdpwtgrmwleihr), SQL Editor.
-- Copiar TODO este archivo (termina en «FIN PASO 3») y apretar Run.
-- PRUEBA QUE NO GRABA NADA: rearma el 247 (Cencosud) y el 241 (Dorinka) por la puerta automática
-- en una transacción que se deshace y lista en qué quedarían distintos de los cargados a mano.
-- Pegarle a Claude la tabla del resultado. Esperado: «quedó grabado algo?» = 0.

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
-- FIN PASO 3
