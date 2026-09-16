-- ROLLBACK de la v18.88 (2026-09-16) — Conciliación: timeout al abrir 🔍 Comparar.
-- Restituye las tres piezas como estaban ANTES: la vista llamando a gv_cruce_fc_asignacion()
-- en vivo, gv_conciliacion_comparar en LANGUAGE sql resolviendo el doc_id por la vista, y
-- gv_conciliacion_lista sin el refresco del cache.
--
-- Para deshacer también lo nuevo:
--   select cron.unschedule('gv-cruce-fc-asig');
--   drop function if exists public.gv_cruce_fc_asig_refrescar_si_viejo(integer);
--   drop function if exists public.gv_cruce_fc_asig_refrescar();
--   drop table if exists public."GV_Cruce_FC_Asig";

create or replace view public.gv_vista_cruce_facturacion as
 with base as (
   select f.np, f.tanda, f.fecha_salida, f.razon_social as rs_virgilio, f.cod_cliente,
          gv_empresa_de_np_texto(f.np) as empresa,
          n.neto as neto_calculado, n.cajas_ent, n.items_sin_precio
     from "Facturacion_NP" f
     left join gv_vista_facturacion_neto n on n.np = f.np
 ), asig as (
   select gv_cruce_fc_asignacion.np, gv_cruce_fc_asignacion.doc_id, gv_cruce_fc_asignacion.candidatos
     from gv_cruce_fc_asignacion() gv_cruce_fc_asignacion(np, doc_id, candidatos)
 ), doc as (
   select 'lk'::text as empresa, d_1.id, d_1.comprobante_id, d_1.fecha, d_1.total,
          d_1.subt_gravado, d_1.total_cajas, d_1.storage_path, d_1.cae
     from isis_lk.documentos d_1 where d_1.familia = 'factura_venta'::text
   union all
   select 'chef'::text, d_1.id, d_1.comprobante_id, d_1.fecha, d_1.total,
          d_1.subt_gravado, d_1.total_cajas, d_1.storage_path, d_1.cae
     from isis_ch.documentos d_1 where d_1.familia = 'factura_venta'::text
 )
 select b.np, b.tanda, b.fecha_salida, b.rs_virgilio, b.cod_cliente, b.empresa,
    b.neto_calculado, b.cajas_ent, b.items_sin_precio,
    d.id as doc_id, d.comprobante_id, d.fecha as doc_fecha,
    d.total::numeric as factura_total, d.subt_gravado::numeric as factura_neto,
    d.total_cajas::numeric as factura_cajas, d.storage_path, d.cae,
    coalesce(a.candidatos, 0)::bigint as candidatos_cercanos,
    case when d.id is not null then d.subt_gravado - b.neto_calculado else null::numeric end as diff,
    case when d.id is not null and b.neto_calculado is not null and b.neto_calculado <> 0::numeric
         then round((d.subt_gravado - b.neto_calculado) / b.neto_calculado * 100::numeric, 2)
         else null::numeric end as diff_pct,
    case when b.neto_calculado is null then 'sin_neto'::text
         when d.id is null then 'sin_factura'::text
         when abs(coalesce(d.subt_gravado, 0::numeric) - b.neto_calculado) <= greatest(50::numeric, b.neto_calculado * 0.01) then 'ok'::text
         else 'diff'::text end as estado,
    (exists ( select 1 from cobranzas_cliente_cadena cc
               where cc.cod_cliente = b.cod_cliente and cc.empresa = b.empresa)) as es_super
   from base b
   left join asig a on a.np = b.np
   left join doc d on d.empresa = b.empresa and d.id = a.doc_id;
alter view public.gv_vista_cruce_facturacion set (security_invoker = true);

create or replace function public.gv_conciliacion_comparar(p_np text)
 returns table(cod text, descripcion text, cajas_ges numeric, cajas_isis numeric, precio_ges numeric, precio_isis numeric, dto_ges numeric, dto_isis numeric, importe_ges numeric, importe_isis numeric, diff numeric, sin_precio_ges boolean, motivo text)
 language sql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
  with r as (
    select s.np, s.empresa, c.doc_id, c.factura_neto
      from public."GV_Conciliacion_Facturacion" s
      left join public.gv_vista_cruce_facturacion c on c.np = s.np
     where s.np = p_np or regexp_replace(s.np, '\.0+$', '') = regexp_replace(p_np, '\.0+$', '')
     limit 1
  ), ges as (
    select canon_cod(i.cod) as cc, min(i.cod) as cod,
           sum(i.cajas_ent) as cajas, max(i.precio_lista) as precio,
           max(i.dto_vol) as dto, sum(round(coalesce(i.importe_ent,0) * i.factor_web, 2)) as importe,
           bool_or(i.sin_precio) as sin_precio
      from public.gv_vista_facturacion_neto_items i, r
     where i.np = r.np
     group by canon_cod(i.cod)
  ), isis_raw as (
    select canon_cod(di.codigo_articulo) as cc, min(di.codigo_articulo) as cod, max(di.descripcion) as descripcion,
           sum(di.cantidad_caja) as cajas, round(sum(di.importe) / nullif(sum(di.cantidad * (1 - coalesce(di.dto_1,0)/100.0) * (1 - coalesce(di.dto_2,0)/100.0)), 0), 2) as precio,
           max(coalesce(di.dto_1,0) + coalesce(di.dto_2,0)) as dto, sum(di.importe) as importe_gross
      from r
      join lateral (
        select codigo_articulo, descripcion, cantidad, cantidad_caja, precio_unit, dto_1, dto_2, importe
          from isis_lk.documento_items where documento_id = r.doc_id and r.empresa = 'lk' and codigo_articulo is not null
        union all
        select codigo_articulo, descripcion, cantidad, cantidad_caja, precio_unit, dto_1, dto_2, importe
          from isis_ch.documento_items where documento_id = r.doc_id and r.empresa = 'chef' and codigo_articulo is not null
      ) di on true
     group by canon_cod(di.codigo_articulo)
  ), fac as (
    select case when sum(importe_gross) > 0 and (select factura_neto from r) is not null
                then (select factura_neto from r) / sum(importe_gross) else 1 end as factor
      from isis_raw
  ), isis as (
    select i.cc, i.cod, i.descripcion, i.cajas, i.precio, i.dto,
           round(i.importe_gross * (select factor from fac), 2) as importe
      from isis_raw i
  )
  select coalesce(g.cod, x.cod) as cod, x.descripcion,
         g.cajas as cajas_ges, x.cajas as cajas_isis,
         g.precio as precio_ges, x.precio as precio_isis,
         round(coalesce(g.dto,0) * 100, 2) as dto_ges, x.dto as dto_isis,
         g.importe as importe_ges, x.importe as importe_isis,
         round(coalesce(x.importe,0) - coalesce(g.importe,0), 2) as diff,
         coalesce(g.sin_precio, false) as sin_precio_ges,
         case when g.cc is null then 'falta_en_gestion'
              when x.cc is null then 'no_facturado'
              when coalesce(g.sin_precio,false) then 'sin_precio'
              when round(coalesce(g.dto,0)*100,2) <> coalesce(x.dto,0) then 'descuento'
              when round(coalesce(g.precio,0),2) <> round(coalesce(x.precio,0),2) then 'precio'
              when abs(coalesce(x.importe,0) - coalesce(g.importe,0)) > 1 then 'importe'
              else 'ok' end as motivo
    from ges g
    full outer join isis x on x.cc = g.cc
   order by abs(coalesce(x.importe,0) - coalesce(g.importe,0)) desc, coalesce(g.cod, x.cod);
$function$;

create or replace function public.gv_conciliacion_lista(p_limit integer default 200, p_offset integer default 0, p_q text default null::text, p_empresa text default null::text)
 returns table(np text, empresa text, tanda text, cod_cliente text, razon_social text, fecha_salida date, cajas_ent numeric, neto_gestion numeric, items_sin_precio integer, registrado_at timestamp with time zone, factura_neto numeric, factura_cajas numeric, comprobante_id text, doc_fecha date, storage_path text, es_super boolean, diff numeric, diff_pct numeric, estado text, neto_actual numeric, corregido boolean, motivo text, total_count bigint)
 language sql
 security definer
 set search_path to 'public', 'pg_temp'
 set statement_timeout to '20000'
as $function$
  with j as (
    select s.np, s.empresa, s.tanda, s.cod_cliente, s.razon_social,
           s.fecha_salida, s.cajas_ent, s.neto_gestion, s.items_sin_precio, s.registrado_at,
           c.factura_neto, c.factura_cajas, c.comprobante_id, c.doc_fecha, c.storage_path,
           coalesce(c.es_super, false) as es_super, na.neto as neto_actual,
           case when c.factura_neto is not null and s.neto_gestion is not null
                then round(c.factura_neto - s.neto_gestion, 2) end as diff,
           case when c.factura_neto is not null and s.neto_gestion is not null and s.neto_gestion <> 0
                then round((c.factura_neto - s.neto_gestion) / s.neto_gestion * 100, 2) end as diff_pct,
           case when s.neto_gestion is null then 'sin_neto'
                when c.factura_neto is null then 'sin_factura'
                when abs(c.factura_neto - s.neto_gestion) <= 100 then 'ok'
                else 'diff' end as estado
      from public."GV_Conciliacion_Facturacion" s
      left join public.gv_vista_cruce_facturacion c on c.np = s.np
      left join public.gv_vista_facturacion_neto na on na.np = s.np
  ), j2 as (
    select j.*,
           (j.estado = 'diff' and j.factura_neto is not null and j.neto_actual is not null
            and abs(j.factura_neto - j.neto_actual) <= 100) as corregido
      from j
  )
  select j2.np, j2.empresa, j2.tanda, j2.cod_cliente, j2.razon_social,
         j2.fecha_salida, j2.cajas_ent, j2.neto_gestion, j2.items_sin_precio, j2.registrado_at,
         j2.factura_neto, j2.factura_cajas, j2.comprobante_id, j2.doc_fecha, j2.storage_path, j2.es_super,
         j2.diff, j2.diff_pct, j2.estado, j2.neto_actual, j2.corregido,
         null::text as motivo,
         count(*) over ()::bigint as total_count
    from j2
   where (p_empresa is null or p_empresa = '' or j2.empresa = p_empresa)
     and (p_q is null or p_q = ''
          or j2.razon_social ilike '%'||p_q||'%' or j2.cod_cliente ilike '%'||p_q||'%' or j2.np ilike '%'||p_q||'%')
   order by j2.registrado_at desc
   limit greatest(p_limit, 1) offset greatest(p_offset, 0)
$function$;
