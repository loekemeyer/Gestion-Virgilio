-- ══════════════════════════════════════════════════════════════════════════
-- Facturable anticipado: qué artículos de NP sin armar ya tienen stock
-- disponible para facturar y entregar ANTES de cargar el camión completo.
-- ══════════════════════════════════════════════════════════════════════════
-- v12.30 (2026-09-01). Cuarta pestaña del overlay 💰 Deuda/Cobranzas
-- (📦 Facturable ya). Grano: NP pendiente (no está en Facturacion_NP, no está
-- cancelada) × artículo pedido en PPP_Base_Pedidos, sólo cuando hay stock
-- (vista_saldos_stock.terminado) para cubrir AL MENOS una caja.
--
-- El stock es un pool COMPARTIDO entre todas las NP pendientes del mismo
-- artículo — por eso NO se compara cada NP contra el stock total (eso
-- sobre-contaría si dos NP piden lo mismo). Se reparte por prioridad: las NP
-- con fecha_entrega más próxima se llevan la cobertura primero (running sum
-- de demanda con window function); si el stock no alcanza para todas, a las
-- de entrega más lejana les puede tocar cobertura parcial o ninguna.
--
-- Valorización: misma fórmula que vista_facturacion_neto (precios_venta ×
-- uxb × (1-dto_vol) × 0,98) — mismas limitaciones ya documentadas ahí: no
-- modela la lista negociada de súper (se marca es_super) ni tiene precio
-- para todos los códigos (se marca sin_precio, no se inventa un valor).
--
-- Objetos:
--   vista_facturable_anticipado         — NP × artículo con cobertura>0 (interna, REVOKE anon).
--   facturable_anticipado_resumen(...)   — agregado por NP, RPC (EXECUTE anon).
--   facturable_anticipado_detalle(np)    — detalle por artículo de una NP, RPC (EXECUTE anon).
-- ══════════════════════════════════════════════════════════════════════════

create view public.vista_facturable_anticipado as
with pend as (
  select pp.np, pp.tanda, pp.razon_social as rs_virgilio, pp.cod as cod_cliente,
         nullif(pp.fecha_entrega, '') as fecha_entrega,
         case when pp.np ~ '^9' then 'lk' else 'chef' end as empresa
  from public."PPP_Programacion_Diaria" pp
  where pp.np not in (select np from public."Facturacion_NP")
    and pp.np not in (select np from public."NP_Canceladas")
),
items as (
  select p.np, p.tanda, p.rs_virgilio, p.cod_cliente, p.fecha_entrega, p.empresa,
         b.articulo, sum(coalesce(b.cajas, 0)) as cajas_pedidas
  from pend p
  join public."PPP_Base_Pedidos" b on b.pedido = p.np
  where b.articulo is not null and coalesce(b.cajas, 0) > 0
  group by p.np, p.tanda, p.rs_virgilio, p.cod_cliente, p.fecha_entrega, p.empresa, b.articulo
),
con_stock as (
  select i.*, s.terminado,
    sum(i.cajas_pedidas) over (
      partition by i.articulo
      order by (i.fecha_entrega is null), i.fecha_entrega asc, i.np asc
      rows between unbounded preceding and 1 preceding
    ) as demanda_previa
  from items i
  join public.vista_saldos_stock s on public.canon_cod(s.cod_art) = public.canon_cod(i.articulo)
  where coalesce(s.terminado, 0) > 0
),
calc as (
  select *,
    greatest(0, least(cajas_pedidas, terminado - coalesce(demanda_previa, 0))) as cajas_cubribles
  from con_stock
),
precio as (
  select c.*, pv.uxb, pv.precio_unit,
         coalesce(cd.dto_vol, 0) as dto_vol,
         round(c.cajas_cubribles * coalesce(pv.uxb, 1) * coalesce(pv.precio_unit, 0)
               * (1 - coalesce(cd.dto_vol, 0)) * 0.98, 2) as valor_estimado,
         (pv.precio_unit is null or pv.precio_unit <= 0) as sin_precio
  from calc c
  left join public.precios_venta pv on public.canon_cod(pv.cod) = public.canon_cod(c.articulo)
  left join public.clientes_dto cd on cd.cod_cliente = c.cod_cliente
)
select
  np, tanda, rs_virgilio, cod_cliente, empresa, fecha_entrega,
  articulo, cajas_pedidas, terminado, demanda_previa, cajas_cubribles,
  (cajas_cubribles >= cajas_pedidas) as cubre_completo,
  uxb, precio_unit, dto_vol, valor_estimado, sin_precio,
  exists (
    select 1 from public.cobranzas_cliente_cadena cc
    where cc.cod_cliente = precio.cod_cliente and cc.empresa = precio.empresa
  ) as es_super
from precio
where cajas_cubribles > 0;

revoke all on public.vista_facturable_anticipado from anon, authenticated;

-- Resumen por NP, ordenado por lo que más conviene facturar ya (más $ primero).
create function public.facturable_anticipado_resumen(
  p_empresa text default null,
  p_q       text default null,
  p_limit   int  default 100,
  p_offset  int  default 0
)
returns table (
  np text, tanda text, rs_virgilio text, cod_cliente text, empresa text, fecha_entrega text,
  cant_articulos_np bigint, cant_articulos_cubribles bigint, cant_articulos_completos bigint,
  cajas_cubribles_total numeric, valor_estimado_total numeric, tiene_sin_precio boolean,
  es_super boolean, total_count bigint
)
language sql security definer set search_path = public
as $$
  with agg as (
    select
      v.np, max(v.tanda) as tanda, max(v.rs_virgilio) as rs_virgilio, max(v.cod_cliente) as cod_cliente,
      max(v.empresa) as empresa, max(v.fecha_entrega) as fecha_entrega,
      count(*) as cant_articulos_cubribles,
      count(*) filter (where v.cubre_completo) as cant_articulos_completos,
      sum(v.cajas_cubribles) as cajas_cubribles_total,
      sum(v.valor_estimado) as valor_estimado_total,
      bool_or(v.sin_precio) as tiene_sin_precio,
      bool_or(v.es_super) as es_super
    from public.vista_facturable_anticipado v
    group by v.np
  ),
  total_np as (
    select pedido as np, count(distinct articulo) as cant_articulos_np
    from public."PPP_Base_Pedidos"
    where pedido in (select np from agg)
    group by pedido
  )
  select
    a.np, a.tanda, a.rs_virgilio, a.cod_cliente, a.empresa, a.fecha_entrega,
    coalesce(t.cant_articulos_np, a.cant_articulos_cubribles), a.cant_articulos_cubribles,
    a.cant_articulos_completos, a.cajas_cubribles_total, a.valor_estimado_total,
    a.tiene_sin_precio, a.es_super,
    count(*) over ()::bigint as total_count
  from agg a
  left join total_np t on t.np = a.np
  where (p_empresa is null or p_empresa = '' or a.empresa = p_empresa)
    and (p_q is null or p_q = ''
         or a.rs_virgilio ilike '%'||p_q||'%' or a.cod_cliente ilike '%'||p_q||'%' or a.np ilike '%'||p_q||'%')
  order by a.valor_estimado_total desc nulls last
  limit greatest(p_limit, 1) offset greatest(p_offset, 0)
$$;
grant execute on function public.facturable_anticipado_resumen(text, text, int, int) to anon, authenticated;

-- Detalle por artículo de una NP puntual.
create function public.facturable_anticipado_detalle(p_np text)
returns table (
  articulo text, cajas_pedidas numeric, terminado numeric, demanda_previa numeric,
  cajas_cubribles numeric, cubre_completo boolean, valor_estimado numeric, sin_precio boolean
)
language sql security definer set search_path = public
as $$
  select articulo, cajas_pedidas, terminado, demanda_previa, cajas_cubribles,
         cubre_completo, valor_estimado, sin_precio
  from public.vista_facturable_anticipado
  where np = p_np
  order by articulo
$$;
grant execute on function public.facturable_anticipado_detalle(text) to anon, authenticated;

-- ══════════════════════════════════════════════════════════════════════════
-- v12.31 (2026-09-01). Reserva de stock — hallazgo de auditoría propia sobre
-- v12.30: facturar en el ISIS NO mueve Movimientos_Stock (son sistemas
-- separados), así que sin esto el mismo "terminado" se le podía volver a
-- ofrecer a OTRO cliente en la misma pestaña antes de cargar el camión y
-- registrar el movimiento físico real → doble promesa sobre la misma caja.
--
-- facturable_anticipado_reservas guarda "esto ya se decidió facturar
-- anticipado" por NP+artículo. La vista resta el pool reservado (de TODAS
-- las NP) del stock disponible antes de repartir por prioridad, y resta lo
-- reservado por la NP misma de su propia demanda pendiente (para no
-- sugerirle de nuevo lo que ya se comprometió). Se libera a mano cuando el
-- movimiento real ya se registró, o si se decide no facturarlo.
-- Verificado: reservar 50/200 cajas de un artículo bajó el pool compartido a
-- 150 para el resto de las NP; al liberar, volvió a 200. 0 privilegios
-- abiertos a anon/authenticated (tabla con RLS + REVOKE ALL, solo se
-- escribe vía las funciones SECURITY DEFINER de abajo).
-- ══════════════════════════════════════════════════════════════════════════

create table public.facturable_anticipado_reservas (
  id            bigint generated always as identity primary key,
  np            text not null,
  articulo      text not null,
  cajas         numeric not null check (cajas > 0),
  creado_por    text,
  creado_at     timestamptz not null default now(),
  liberado_at   timestamptz,
  liberado_por  text
);
comment on table public.facturable_anticipado_reservas is
  'Compromiso de "ya se decidió facturar esto anticipado" para un NP+artículo. '
  'Necesaria porque facturar en el ISIS NO mueve Movimientos_Stock (son sistemas '
  'separados): sin esta tabla el mismo stock "terminado" se le podía volver a '
  'ofrecer a otro cliente en la misma pestaña antes de cargar el camión y '
  'registrar el movimiento físico real. Se libera a mano cuando ya se cargó '
  '(el movimiento real ya lo refleja en Movimientos_Stock) o si se decide no '
  'facturarlo. Agregada 2026-09-01, hallazgo de auditoría propia sobre v12.30.';

alter table public.facturable_anticipado_reservas enable row level security;
revoke all on public.facturable_anticipado_reservas from anon, authenticated;

create index facturable_anticipado_reservas_articulo_idx
  on public.facturable_anticipado_reservas (articulo) where liberado_at is null;
create index facturable_anticipado_reservas_np_idx
  on public.facturable_anticipado_reservas (np, articulo) where liberado_at is null;

-- La vista se reemplaza completa (agrega reservado_propio/terminado_disponible
-- antes de calcular cajas_cubribles, y expone reservado_propio como
-- cajas_reservadas en el resultado final).
drop view public.vista_facturable_anticipado;

create view public.vista_facturable_anticipado as
with pend as (
  select pp.np, pp.tanda, pp.razon_social as rs_virgilio, pp.cod as cod_cliente,
         nullif(pp.fecha_entrega, '') as fecha_entrega,
         case when pp.np ~ '^9' then 'lk' else 'chef' end as empresa
  from public."PPP_Programacion_Diaria" pp
  where pp.np not in (select np from public."Facturacion_NP")
    and pp.np not in (select np from public."NP_Canceladas")
),
items as (
  select p.np, p.tanda, p.rs_virgilio, p.cod_cliente, p.fecha_entrega, p.empresa,
         b.articulo, sum(coalesce(b.cajas, 0)) as cajas_pedidas
  from pend p
  join public."PPP_Base_Pedidos" b on b.pedido = p.np
  where b.articulo is not null and coalesce(b.cajas, 0) > 0
  group by p.np, p.tanda, p.rs_virgilio, p.cod_cliente, p.fecha_entrega, p.empresa, b.articulo
),
reservas_articulo as (
  select articulo, sum(cajas) as reservado_total
  from public.facturable_anticipado_reservas
  where liberado_at is null
  group by articulo
),
reservas_propias as (
  select np, articulo, sum(cajas) as reservado_propio
  from public.facturable_anticipado_reservas
  where liberado_at is null
  group by np, articulo
),
items2 as (
  select i.*,
    coalesce(rp.reservado_propio, 0) as reservado_propio,
    greatest(0, i.cajas_pedidas - coalesce(rp.reservado_propio, 0)) as cajas_pedidas_pendiente
  from items i
  left join reservas_propias rp on rp.np = i.np and rp.articulo = i.articulo
),
con_stock as (
  select i.*, s.terminado,
    greatest(0, s.terminado - coalesce(ra.reservado_total, 0)) as terminado_disponible,
    sum(i.cajas_pedidas_pendiente) over (
      partition by i.articulo
      order by (i.fecha_entrega is null), i.fecha_entrega asc, i.np asc
      rows between unbounded preceding and 1 preceding
    ) as demanda_previa
  from items2 i
  join public.vista_saldos_stock s on public.canon_cod(s.cod_art) = public.canon_cod(i.articulo)
  left join reservas_articulo ra on ra.articulo = i.articulo
  where coalesce(s.terminado, 0) > 0
),
calc as (
  select *,
    greatest(0, least(cajas_pedidas_pendiente, terminado_disponible - coalesce(demanda_previa, 0))) as cajas_cubribles
  from con_stock
),
precio as (
  select c.*, pv.uxb, pv.precio_unit,
         coalesce(cd.dto_vol, 0) as dto_vol,
         round(c.cajas_cubribles * coalesce(pv.uxb, 1) * coalesce(pv.precio_unit, 0)
               * (1 - coalesce(cd.dto_vol, 0)) * 0.98, 2) as valor_estimado,
         (pv.precio_unit is null or pv.precio_unit <= 0) as sin_precio
  from calc c
  left join public.precios_venta pv on public.canon_cod(pv.cod) = public.canon_cod(c.articulo)
  left join public.clientes_dto cd on cd.cod_cliente = c.cod_cliente
)
select
  np, tanda, rs_virgilio, cod_cliente, empresa, fecha_entrega,
  articulo, cajas_pedidas, reservado_propio, terminado, demanda_previa, cajas_cubribles,
  ((cajas_cubribles + reservado_propio) >= cajas_pedidas) as cubre_completo,
  uxb, precio_unit, dto_vol, valor_estimado, sin_precio,
  exists (
    select 1 from public.cobranzas_cliente_cadena cc
    where cc.cod_cliente = precio.cod_cliente and cc.empresa = precio.empresa
  ) as es_super
from precio
where cajas_cubribles > 0;

revoke all on public.vista_facturable_anticipado from anon, authenticated;

-- Reservar/liberar/listar. facturable_anticipado_resumen(...) no cambia
-- (mismas columnas de salida; el agregado por NP ya refleja la cobertura
-- neta de reservas porque lee de la vista).
create function public.facturable_anticipado_reservar(
  p_np text, p_articulo text, p_cajas numeric, p_creado_por text default null
)
returns bigint
language plpgsql security definer set search_path = public
as $$
declare
  v_disponible numeric;
  v_id bigint;
begin
  if p_cajas is null or p_cajas <= 0 then
    raise exception 'cajas debe ser mayor a 0';
  end if;

  select cajas_cubribles into v_disponible
  from public.vista_facturable_anticipado
  where np = p_np and articulo = p_articulo;

  if v_disponible is null then
    raise exception 'No hay cobertura disponible para NP % / artículo % (ya se cubrió del todo o no hay stock)', p_np, p_articulo;
  end if;
  if p_cajas > v_disponible then
    raise exception 'Sólo hay % cajas disponibles para NP % / artículo % (pediste %)', v_disponible, p_np, p_articulo, p_cajas;
  end if;

  insert into public.facturable_anticipado_reservas (np, articulo, cajas, creado_por)
  values (p_np, p_articulo, p_cajas, p_creado_por)
  returning id into v_id;

  return v_id;
end;
$$;
grant execute on function public.facturable_anticipado_reservar(text, text, numeric, text) to anon, authenticated;

create function public.facturable_anticipado_liberar(p_id bigint, p_por text default null)
returns void
language sql security definer set search_path = public
as $$
  update public.facturable_anticipado_reservas
  set liberado_at = now(), liberado_por = p_por
  where id = p_id and liberado_at is null
$$;
grant execute on function public.facturable_anticipado_liberar(bigint, text) to anon, authenticated;

create function public.facturable_anticipado_reservas_activas(p_np text default null)
returns table (
  id bigint, np text, articulo text, cajas numeric,
  creado_por text, creado_at timestamptz, dias_activa int
)
language sql security definer set search_path = public
as $$
  select id, np, articulo, cajas, creado_por, creado_at,
         (current_date - creado_at::date) as dias_activa
  from public.facturable_anticipado_reservas
  where liberado_at is null
    and (p_np is null or p_np = '' or np = p_np)
  order by creado_at desc
$$;
grant execute on function public.facturable_anticipado_reservas_activas(text) to anon, authenticated;

-- facturable_anticipado_detalle se regeneró (drop+create) sólo para agregar
-- la columna cajas_reservadas — mismo cuerpo salvo eso.
drop function public.facturable_anticipado_detalle(text);
create function public.facturable_anticipado_detalle(p_np text)
returns table (
  articulo text, cajas_pedidas numeric, cajas_reservadas numeric, terminado numeric, demanda_previa numeric,
  cajas_cubribles numeric, cubre_completo boolean, valor_estimado numeric, sin_precio boolean
)
language sql security definer set search_path = public
as $$
  select articulo, cajas_pedidas, reservado_propio, terminado, demanda_previa, cajas_cubribles,
         cubre_completo, valor_estimado, sin_precio
  from public.vista_facturable_anticipado
  where np = p_np
  order by articulo
$$;
grant execute on function public.facturable_anticipado_detalle(text) to anon, authenticated;
