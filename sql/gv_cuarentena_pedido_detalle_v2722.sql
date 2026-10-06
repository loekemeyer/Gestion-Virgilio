-- v27.22 (Luis, 2026-10-06): "Ver pedido" en el Log de Cuarentena — todo el detalle del pedido.
-- Una sola RPC de lectura (SECURITY DEFINER + guard de supervisor, igual que gv_cuarentena_log y
-- gv_cuarentena_comentarios): cabecera del cliente (razón social, CUIT, dirección, zona) + los
-- ítems que pidió, con descripción, UxB, unidades y m³, y los totales. La fuente del pedido web
-- es `lk_pedidos_match` (items_string = lo que pidió el cliente); el padrón de direcciones/CUIT es
-- GV_Clientes_Direcciones (RLS sin policy → por eso DEFINER, si no anon ve 0 filas, trampa v20.45).
-- La L se conserva para mostrar y se pela SÓLO para resolver descripción/UxB cuando el código con L
-- no está en esas tablas (el m³ sí tiene los NNNL, v13.71).  Rollback: drop function … .

create or replace function public.gv_cuarentena_pedido_detalle(p_empresa text, p_clave text)
returns jsonb
language plpgsql
stable security definer
set search_path to 'public'
as $function$
declare
  v_emp  text := lower(nullif(btrim(p_empresa),''));
  v_oid  bigint := nullif(btrim(p_clave),'')::bigint;
  v_m    record;
  v_dir  record;
  v_items jsonb;
  v_caj  numeric := 0;
  v_m3   numeric := 0;
begin
  if not (es_supervisor_virgilio() or gv_es_supervisor_o_servicio()) then
    return null;
  end if;
  if v_emp is null or v_oid is null then return null; end if;

  select m.order_id, m.cod_cliente, m.sucursal_entrega, m.fecha_pedido, m.fecha_entrega,
         m.metodo_pago, m.observaciones, m.items_string
    into v_m
    from public.lk_pedidos_match m
   where m.empresa = v_emp and m.order_id = v_oid
   limit 1;

  -- cliente: la sucursal que mejor matchea la del pedido, si no el primer slot
  select d.razon_social, d.cuit, d.direccion, d.localidad, d.provincia, d.zona_expreso
    into v_dir
    from public."GV_Clientes_Direcciones" d
   where d.empresa = v_emp and d.cod = coalesce(v_m.cod_cliente, '')
   order by (d.direccion is not distinct from v_m.sucursal_entrega) desc nulls last, d.slot asc
   limit 1;

  with toks as (
    select btrim(t) tok
      from regexp_split_to_table(coalesce(v_m.items_string, ''), ',') t
  ), it as (
    select regexp_match(tok, '^(.+?)[xX]([0-9]+)$') g from toks where tok <> ''
  ), items as (
    select g[1] art, (g[2])::int cajas from it where g is not null
  ), res as (
    select i.art,
           i.cajas,
           regexp_replace(i.art, '([0-9E])L$', '\1') art_base,
           coalesce(n.descripcion, nb.descripcion) descripcion,
           coalesce(u.uxb, ub.uxb) uxb,
           coalesce(v.m3, vb.m3) m3u
      from items i
      left join public.vista_nombres_articulos  n  on n.cod  = i.art
      left join public.vista_nombres_articulos  nb on nb.cod = regexp_replace(i.art, '([0-9E])L$', '\1')
      left join public.vista_uxb_articulo        u  on u.cod  = i.art
      left join public.vista_uxb_articulo        ub on ub.cod = regexp_replace(i.art, '([0-9E])L$', '\1')
      left join public.vista_volumen_articulo_resuelto v  on v.codigo  = i.art
      left join public.vista_volumen_articulo_resuelto vb on vb.codigo = regexp_replace(i.art, '([0-9E])L$', '\1')
  )
  select
     coalesce(jsonb_agg(jsonb_build_object(
        'art', art, 'descripcion', descripcion,
        'cajas', cajas,
        'uxb', round(coalesce(uxb,0)::numeric, 2),
        'uni', round((cajas * coalesce(uxb,0))::numeric, 0),
        'm3',  round((cajas * coalesce(m3u,0))::numeric, 3)
     ) order by art), '[]'::jsonb),
     coalesce(sum(cajas), 0),
     coalesce(sum(cajas * coalesce(m3u,0)), 0)
    into v_items, v_caj, v_m3
    from res;

  return jsonb_build_object(
    'empresa',      v_emp,
    'clave',        v_oid,
    'cod',          v_m.cod_cliente,
    'razon_social', v_dir.razon_social,
    'cuit',         v_dir.cuit,
    'direccion',    coalesce(v_m.sucursal_entrega, v_dir.direccion),
    'localidad',    v_dir.localidad,
    'provincia',    v_dir.provincia,
    'zona',         v_dir.zona_expreso,
    'fecha_pedido', v_m.fecha_pedido,
    'fecha_entrega',v_m.fecha_entrega,
    'metodo_pago',  v_m.metodo_pago,
    'observaciones',v_m.observaciones,
    'cajas_total',  v_caj,
    'm3_total',     round(v_m3::numeric, 3),
    'items',        v_items,
    'sin_pedido',   (v_m.order_id is null)
  );
end;
$function$;

revoke all on function public.gv_cuarentena_pedido_detalle(text, text) from public;
grant execute on function public.gv_cuarentena_pedido_detalle(text, text) to anon, authenticated, service_role;
