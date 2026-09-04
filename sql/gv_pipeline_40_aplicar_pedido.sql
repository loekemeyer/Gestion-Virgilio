-- ============================================================================
-- [40] FUNCIÓN aplicar_pedido — correr en VIRGILIO (hrxfctzncixxqmpfhskv)
-- ----------------------------------------------------------------------------
-- Toma un pedido del feed (lk/ch), lo parte (tope 18 lk / 15 ch, en el ORDEN
-- del payload), le asigna la NP interna, calcula el m³ por tramo y arma una
-- tanda automática. Escribe SOLO en `pipeline.*`.
--
-- NP interna:  <E> + order_id(6) + parte(2)
--   E = '9' para lk, '4' para ch  (regla de empresa por primer dígito)
--   ej: lk 888 -> 900088801 / 900088802 / 900088803
--
-- m³: suma(cajas * Volumen_Articulos.m3) por tramo (join por codigo).
-- Tanda de prueba: 'W' + YYYYMMDD + '-' + empresa + order_id.
--
-- Idempotente: reprocesar el mismo pedido borra su corrida anterior.
--
-- Uso:  select pipeline.aplicar_pedido('lk', 888);
--       select pipeline.aplicar_pedido('ch', 213);
-- ============================================================================

create or replace function pipeline.aplicar_pedido(p_empresa text, p_order_id bigint)
returns jsonb language plpgsql security definer
set search_path = pipeline, public, pg_temp as $$
declare
  v      record;
  v_tope int;
  v_pref text;
  v_tanda text;
  v_out  jsonb;
begin
  select * into v from public.vista_pedidos_web_feed
   where empresa = p_empresa and order_id = p_order_id;
  if not found then
    raise exception 'Pedido %/% no está en el feed', p_empresa, p_order_id;
  end if;

  v_tope  := case p_empresa when 'ch' then 15 else 18 end;
  v_pref  := case p_empresa when 'lk' then '9' else '4' end || lpad(p_order_id::text, 6, '0');
  v_tanda := 'W' || to_char(now(), 'YYYYMMDD') || '-' || p_empresa || p_order_id;

  -- idempotente: limpiar corrida previa de este pedido
  delete from pipeline.ppp_base where pedido like v_pref || '%';
  delete from pipeline.ppp_prog where np     like v_pref || '%';
  delete from pipeline.pedidos_web where empresa = p_empresa and order_id = p_order_id;

  drop table if exists _it;
  create temp table _it on commit drop as
  select it.ord as pos,
         it.item->>'cod_art'          as cod_art,
         (it.item->>'cajas')::numeric as cajas,
         v_pref || lpad((((it.ord - 1) / v_tope)::int + 1)::text, 2, '0') as np
  from jsonb_array_elements(v.items) with ordinality as it(item, ord);

  -- líneas
  insert into pipeline.ppp_base (pedido, articulo, cajas, cliente, fecha)
  select np, cod_art, cajas, v.cliente_nombre, v.fecha::text
  from _it order by pos;

  -- cabeceras (una por tramo, con m³ calculado)
  insert into pipeline.ppp_prog (np, tanda, m3, cod, razon_social, direccion, fecha_recep, tipo, op)
  select i.np, v_tanda, sum(i.cajas * coalesce(va.m3, 0)),
         v.cod_cliente::text, v.cliente_nombre, v.sucursal_entrega, v.fecha::text, '', ''
  from _it i
  left join public."Volumen_Articulos" va on va.codigo = i.cod_art
  group by i.np;

  -- control
  insert into pipeline.pedidos_web (empresa, order_id, np_interna, cod_cliente, cliente_nombre, sucursal_entrega)
  select p_empresa, p_order_id,
         (select string_agg(np, ',') from (select distinct np from _it order by np) s),
         v.cod_cliente, v.cliente_nombre, v.sucursal_entrega;

  select jsonb_agg(jsonb_build_object(
           'np', np, 'm3', round(m3, 3),
           'lineas', (select count(*) from pipeline.ppp_base b where b.pedido = p.np)
         ) order by np)
    into v_out
  from pipeline.ppp_prog p
  where p.np like v_pref || '%';

  return jsonb_build_object('empresa', p_empresa, 'order_id', p_order_id, 'tanda', v_tanda, 'tramos', v_out);
end $$;

revoke all on function pipeline.aplicar_pedido(text, bigint) from anon, authenticated;
