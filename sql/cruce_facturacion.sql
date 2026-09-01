-- ══════════════════════════════════════════════════════════════════════════
-- Cruce Facturación: lo que Virgilio calculó vs lo que efectivamente se
-- facturó en el ISIS
-- ══════════════════════════════════════════════════════════════════════════
-- v12.29 (2026-09-01). Compara, por NP tildada como facturada:
--   - "Calculado" = vista_facturacion_neto.neto (sobre lo armado, precio de
--     lista × (1-dto_vol) × 0,98, SIN IVA — es la misma fuente que la columna
--     💵 Neto de la pantalla de Facturación).
--   - "Real" = isis_lk/isis_ch.documentos.subt_gravado del comprobante real
--     que emitió el ISIS (neto gravado, también SIN IVA — comparación
--     apples-to-apples, verificado: subt_gravado + iva_21 + iva_105 = total).
--
-- Matching: por cliente (canon_cod) + fecha (±3 días de fecha_salida, mismo
-- criterio que vista_np_factura) + cajas armadas vs cajas del comprobante,
-- con tolerancia relativa (≤1 caja o ≤15%, lo que sea mayor). Un candidato
-- fuera de esa tolerancia NO cuenta como match — antes de este umbral la
-- vista igual elegía "el menos malo" y eso producía diffs de hasta 16.940%
-- (factura de otro pedido del mismo cliente ese día, cajas nada que ver).
-- Con el umbral: distribución sana, el promedio de "diff" bajó de 66% a un
-- rango de un dígito/decenas.
--
-- Limitación conocida (no resuelta en v1): si una factura consolida varias
-- NP del mismo cliente/día, su total_cajas es la SUMA — no va a matchear 1:1
-- contra ninguna NP individual, puede salir "sin_factura" o "diff" sin que
-- haya error real. `candidatos_cercanos` en la vista ayuda a detectarlo.
--
-- Objetos:
--   vista_cruce_facturacion       — una fila por NP (interna, REVOKE anon).
--   cruce_facturacion_resumen(...) — listado paginado, RPC (EXECUTE anon).
--   cruce_facturacion_totales(...) — agregado por estado, RPC (EXECUTE anon).
-- ══════════════════════════════════════════════════════════════════════════

create view public.vista_cruce_facturacion as
select v.*,
  -- Clientes de súper (Coto, Diarco, INC...) no están bien modelados acá:
  -- vista_facturacion_neto usa precios_venta × dto_vol; el súper paga la
  -- lista negociada (precios_super), que es otra estructura. Su diferencia
  -- es ESPERADA, no necesariamente un error — se marca para no alarmar.
  exists (
    select 1 from public.cobranzas_cliente_cadena cc
    where cc.cod_cliente = v.cod_cliente and cc.empresa = v.empresa
  ) as es_super
from (
  with base as (
    select f.np, f.tanda, f.fecha_salida, f.razon_social as rs_virgilio, f.cod_cliente,
           case when f.np ~ '^9' then 'lk' else 'chef' end as empresa,
           n.neto as neto_calculado, n.cajas_ent, n.items_sin_precio
    from public."Facturacion_NP" f
    left join public.vista_facturacion_neto n on n.np = f.np
  ),
  cand as (
    select b.*,
      d.id as doc_id, d.comprobante_id, d.fecha as doc_fecha, d.total as factura_total,
      d.subt_gravado as factura_neto, d.total_cajas as factura_cajas, d.storage_path, d.cae,
      abs(coalesce(d.total_cajas, -1) - coalesce(b.cajas_ent, -1)) as dcajas,
      abs(d.fecha - b.fecha_salida) as dfecha,
      greatest(1, coalesce(b.cajas_ent, 0) * 0.15) as tolerancia_cajas
    from base b
    left join lateral (
      select dd.id, dd.comprobante_id, dd.fecha, dd.total, dd.subt_gravado, dd.total_cajas, dd.storage_path, dd.cae
      from isis_lk.documentos dd
      where b.empresa = 'lk' and dd.familia = 'factura_venta'
        and dd.contraparte_codigo is not null
        and public.canon_cod(dd.contraparte_codigo) = public.canon_cod(b.cod_cliente)
        and dd.fecha between b.fecha_salida - 3 and b.fecha_salida + 3
      union all
      select dd.id, dd.comprobante_id, dd.fecha, dd.total, dd.subt_gravado, dd.total_cajas, dd.storage_path, dd.cae
      from isis_ch.documentos dd
      where b.empresa = 'chef' and dd.familia = 'factura_venta'
        and dd.contraparte_codigo is not null
        and public.canon_cod(dd.contraparte_codigo) = public.canon_cod(b.cod_cliente)
        and dd.fecha between b.fecha_salida - 3 and b.fecha_salida + 3
    ) d on true
  ),
  ranked as (
    select c.*,
      row_number() over (partition by c.np order by c.dcajas asc nulls last, c.dfecha asc nulls last) as rn,
      count(*) filter (where c.doc_id is not null and c.dcajas <= c.tolerancia_cajas) over (partition by c.np) as candidatos_cercanos
    from cand c
  ),
  top1 as (
    select * from ranked where rn = 1
  )
  select
    np, tanda, fecha_salida, rs_virgilio, cod_cliente, empresa,
    neto_calculado, cajas_ent, items_sin_precio,
    case when doc_id is not null and dcajas <= tolerancia_cajas then doc_id end as doc_id,
    case when doc_id is not null and dcajas <= tolerancia_cajas then comprobante_id end as comprobante_id,
    case when doc_id is not null and dcajas <= tolerancia_cajas then doc_fecha end as doc_fecha,
    case when doc_id is not null and dcajas <= tolerancia_cajas then factura_total end as factura_total,
    case when doc_id is not null and dcajas <= tolerancia_cajas then factura_neto end as factura_neto,
    case when doc_id is not null and dcajas <= tolerancia_cajas then factura_cajas end as factura_cajas,
    case when doc_id is not null and dcajas <= tolerancia_cajas then storage_path end as storage_path,
    case when doc_id is not null and dcajas <= tolerancia_cajas then cae end as cae,
    candidatos_cercanos,
    case when doc_id is not null and dcajas <= tolerancia_cajas
         then (factura_neto - neto_calculado) end as diff,
    case when doc_id is not null and dcajas <= tolerancia_cajas
              and neto_calculado is not null and neto_calculado <> 0
         then round(((factura_neto - neto_calculado) / neto_calculado) * 100, 2) end as diff_pct,
    case
      when neto_calculado is null then 'sin_neto'
      when doc_id is null or dcajas > tolerancia_cajas then 'sin_factura'
      when candidatos_cercanos > 1 then 'ambiguo'
      when abs(coalesce(factura_neto, 0) - neto_calculado) <= greatest(50, neto_calculado * 0.01) then 'ok'
      else 'diff'
    end as estado
  from top1
) v;

revoke all on public.vista_cruce_facturacion from anon, authenticated;

-- Listado paginado, prioriza lo que hay que revisar (diff/ambiguo/sin_factura)
-- antes que lo que ya está OK.
create function public.cruce_facturacion_resumen(
  p_desde  date default (current_date - interval '30 days')::date,
  p_hasta  date default current_date,
  p_empresa text default null,
  p_estado  text default null,
  p_q       text default null,
  p_limit   int  default 100,
  p_offset  int  default 0
)
returns table (
  np text, tanda text, fecha_salida date, rs_virgilio text, cod_cliente text, empresa text,
  neto_calculado numeric, cajas_ent numeric, items_sin_precio bigint,
  doc_id bigint, comprobante_id text, doc_fecha date, factura_total numeric, factura_neto numeric,
  factura_cajas numeric, storage_path text, cae text, candidatos_cercanos bigint,
  diff numeric, diff_pct numeric, estado text, es_super boolean, total_count bigint
)
language sql security definer set search_path = public
as $$
  select v.*, count(*) over ()::bigint as total_count
  from public.vista_cruce_facturacion v
  where v.fecha_salida between p_desde and p_hasta
    and (p_empresa is null or p_empresa = '' or v.empresa = p_empresa)
    and (p_estado is null or p_estado = '' or v.estado = p_estado)
    and (p_q is null or p_q = ''
         or v.rs_virgilio ilike '%'||p_q||'%' or v.cod_cliente ilike '%'||p_q||'%' or v.np ilike '%'||p_q||'%')
  order by case v.estado
             when 'diff' then 0 when 'ambiguo' then 1 when 'sin_factura' then 2
             when 'sin_neto' then 3 else 4
           end,
           abs(coalesce(v.diff, 0)) desc
  limit greatest(p_limit, 1) offset greatest(p_offset, 0)
$$;
grant execute on function public.cruce_facturacion_resumen(date, date, text, text, text, int, int) to anon, authenticated;

-- Totales para el banner de resumen (evita traer todo al navegador solo para sumar).
create function public.cruce_facturacion_totales(
  p_desde   date default (current_date - interval '30 days')::date,
  p_hasta   date default current_date,
  p_empresa text default null
)
returns table (estado text, n bigint, suma_diff numeric)
language sql security definer set search_path = public
as $$
  select estado, count(*)::bigint, coalesce(sum(diff), 0)
  from public.vista_cruce_facturacion
  where fecha_salida between p_desde and p_hasta
    and (p_empresa is null or p_empresa = '' or empresa = p_empresa)
  group by estado
$$;
grant execute on function public.cruce_facturacion_totales(date, date, text) to anon, authenticated;
