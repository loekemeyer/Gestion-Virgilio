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
