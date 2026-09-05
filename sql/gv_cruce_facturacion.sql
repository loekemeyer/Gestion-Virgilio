-- ══════════════════════════════════════════════════════════════════════════
-- gv_cruce_facturacion.sql — Cruce Facturación vs ISIS que entiende las NP web
-- v13.10 · 2026-09-05 sábado · idea 8033 · Virgilio (hrxfctzncixxqmpfhskv)
-- ══════════════════════════════════════════════════════════════════════════
-- EL AGUJERO: `vista_facturacion_neto_items` y `vista_cruce_facturacion` (objetos de
-- PRODUCCIÓN, sql/cruce_facturacion.sql de ese repo) deciden la empresa así:
--     case when np ~ '^9' then 'lk' else 'chef' end
-- Una NP web de LK es `LK 1350`: no empieza con 9 → cae como Chef → busca la factura en
-- isis_ch.documentos y con clientes_dto de chef → NUNCA cruza. Las de Chef (`CH 0217`)
-- caen bien de casualidad.
--
-- LA REGLA DEL DUEÑO: sobre lo compartido se AGREGA, no se modifica. Así que no se toca
-- ninguna vista de Producción: se crean las copias `gv_*` con la empresa resuelta por la
-- etiqueta (`LK …` → lk, `CH …` → chef, 9xxxx → lk, resto → chef) y el front de Gestión
-- (pestaña "Facturación vs ISIS") pasa a llamar `gv_cruce_facturacion_resumen`. Para las NP
-- numéricas el resultado es IDÉNTICO al de Producción (misma lógica, mismo orden).
--
-- Objetos (todos nuevos):
--   gv_vista_facturacion_neto_items  — security_invoker, sin grant a anon/authenticated
--   gv_vista_facturacion_neto        — idem
--   gv_vista_cruce_facturacion       — idem (como la original: interna)
--   gv_cruce_facturacion_resumen(…)  — RPC SECURITY DEFINER, execute anon/authenticated
--   gv_cruce_facturacion_totales(…)  — idem
--
-- ROLLBACK: drop function gv_cruce_facturacion_resumen(date,date,text,text,text,int,int);
--   drop function gv_cruce_facturacion_totales(date,date,text); drop view gv_vista_cruce_facturacion;
--   drop view gv_vista_facturacion_neto; drop view gv_vista_facturacion_neto_items; y el front
--   vuelve a `cruce_facturacion_resumen`.
-- ══════════════════════════════════════════════════════════════════════════

-- Empresa de una NP, entendiendo la etiqueta web. (No se reusa empresa_de_np, que es de
-- Producción y devuelve 'CH' para 'LK 1350' porque mira sólo los dígitos.)
create or replace function public.gv_empresa_de_np_texto(p_np text)
returns text
language sql
immutable
set search_path = public, pg_temp
as $$
  select case when p_np ~* '^\s*LK' then 'lk'
              when p_np ~* '^\s*CH' then 'chef'
              when p_np ~ '^9'      then 'lk'
              else 'chef' end;
$$;
grant execute on function public.gv_empresa_de_np_texto(text) to anon, authenticated;

create or replace view public.gv_vista_facturacion_neto_items
with (security_invoker = true) as
with ent as (
  select regexp_replace(e.np, '\.0+$', '') as np,
         canon_cod(e.cod_art) as cod_canon,
         min(e.cod_art) as cod_orig,
         regexp_replace(e.cod_cliente, '\D', '', 'g') as cc,
         sum(coalesce(e.cajas_entregadas, 0)) as cajas_ent,
         sum(coalesce(e.cajas_pedidas, 0)) as cajas_ped,
         sum(coalesce(e.cajas_falto, 0)) as cajas_falto
    from public."Entregas_Virgilio" e
   where coalesce(e.cajas_pedidas, 0) > 0 or coalesce(e.cajas_entregadas, 0) > 0 or coalesce(e.cajas_falto, 0) > 0
   group by regexp_replace(e.np, '\.0+$', ''), canon_cod(e.cod_art), regexp_replace(e.cod_cliente, '\D', '', 'g')
), base as (
  select ent.*,
         public.gv_empresa_de_np_texto(ent.np) as empresa,
         (select cc2.super_key
            from public.cobranzas_cliente_cadena cc2
            join public.cobranzas_super_cadena sc on sc.super_key = cc2.super_key and not sc.usa_lista_general
           where cc2.empresa = case when public.gv_empresa_de_np_texto(ent.np) = 'lk' then 'lk' else 'ch' end
             and cc2.cod_cliente = ent.cc
           limit 1) as super_key
    from ent
)
select b.np,
       b.cc as cod_cliente,
       coalesce(pv.cod, b.cod_orig) as cod,
       b.cajas_ped, b.cajas_ent, b.cajas_falto,
       coalesce(ps.uxb, pv.uxb) as uxb,
       coalesce(ps.precio_unit, pv.precio_unit) as precio_lista,
       case when b.super_key is not null then 0 else coalesce(cd.dto_vol, 0) end as dto_vol,
       case when coalesce(ps.precio_unit, pv.precio_unit) is not null and coalesce(ps.precio_unit, pv.precio_unit) > 0
            then round(b.cajas_ent * coalesce(ps.uxb, pv.uxb, 1) * coalesce(ps.precio_unit, pv.precio_unit)
                       * (1 - case when b.super_key is not null then 0 else coalesce(cd.dto_vol, 0) end), 2)
            else null end as importe_ent,
       case when coalesce(ps.precio_unit, pv.precio_unit) is not null and coalesce(ps.precio_unit, pv.precio_unit) > 0
            then round(b.cajas_ped * coalesce(ps.uxb, pv.uxb, 1) * coalesce(ps.precio_unit, pv.precio_unit)
                       * (1 - case when b.super_key is not null then 0 else coalesce(cd.dto_vol, 0) end), 2)
            else null end as importe_ped,
       (coalesce(ps.precio_unit, pv.precio_unit) is null or coalesce(ps.precio_unit, pv.precio_unit) <= 0) as sin_precio,
       b.cod_canon,
       case when b.super_key is not null then 1.0 else 0.98 end as factor_web,
       (b.super_key is not null) as es_super
  from base b
  left join public.clientes_dto cd on cd.cod_cliente = b.cc and cd.empresa = b.empresa
  left join public.precios_venta pv on canon_cod(pv.cod) = b.cod_canon
  left join public.cobranzas_precios_super ps on b.super_key is not null and ps.super_key = b.super_key and ps.nc = cob_norm_cod(b.cod_orig);
revoke all on public.gv_vista_facturacion_neto_items from anon, authenticated;

create or replace view public.gv_vista_facturacion_neto
with (security_invoker = true) as
select np,
       max(cod_cliente) as cod_cliente,
       round(coalesce(sum(importe_ent * factor_web), 0), 2) as neto,
       round(coalesce(sum(importe_ped * factor_web), 0), 2) as neto_original,
       round(coalesce(sum(importe_ped * factor_web), 0) - coalesce(sum(importe_ent * factor_web), 0), 2) as falto_valor,
       sum(cajas_ped) as cajas_ped,
       sum(cajas_ent) as cajas_ent,
       sum(cajas_falto) as cajas_falto,
       count(*) filter (where sin_precio) as items_sin_precio
  from public.gv_vista_facturacion_neto_items
 group by np;
revoke all on public.gv_vista_facturacion_neto from anon, authenticated;

create or replace view public.gv_vista_cruce_facturacion
with (security_invoker = true) as
select np, tanda, fecha_salida, rs_virgilio, cod_cliente, empresa, neto_calculado, cajas_ent, items_sin_precio,
       doc_id, comprobante_id, doc_fecha, factura_total, factura_neto, factura_cajas, storage_path, cae,
       candidatos_cercanos, diff, diff_pct, estado,
       exists (select 1 from public.cobranzas_cliente_cadena cc
                where cc.cod_cliente = v.cod_cliente and cc.empresa = v.empresa) as es_super
from (
  with base as (
    select f.np, f.tanda, f.fecha_salida, f.razon_social as rs_virgilio, f.cod_cliente,
           public.gv_empresa_de_np_texto(f.np) as empresa,
           n.neto as neto_calculado, n.cajas_ent, n.items_sin_precio
      from public."Facturacion_NP" f
      left join public.gv_vista_facturacion_neto n on n.np = f.np
  ), cand as (
    select b.*, d.id as doc_id, d.comprobante_id, d.fecha as doc_fecha, d.total as factura_total,
           d.subt_gravado as factura_neto, d.total_cajas as factura_cajas, d.storage_path, d.cae,
           abs(coalesce(d.total_cajas, -1) - coalesce(b.cajas_ent, -1)) as dcajas,
           abs(d.fecha - b.fecha_salida) as dfecha,
           greatest(1, coalesce(b.cajas_ent, 0) * 0.15) as tolerancia_cajas
      from base b
      left join lateral (
        select dd.id, dd.comprobante_id, dd.fecha, dd.total, dd.subt_gravado, dd.total_cajas, dd.storage_path, dd.cae
          from isis_lk.documentos dd
         where b.empresa = 'lk' and dd.familia = 'factura_venta' and dd.contraparte_codigo is not null
           and canon_cod(dd.contraparte_codigo) = canon_cod(b.cod_cliente)
           and dd.fecha between b.fecha_salida - 3 and b.fecha_salida + 3
        union all
        select dd.id, dd.comprobante_id, dd.fecha, dd.total, dd.subt_gravado, dd.total_cajas, dd.storage_path, dd.cae
          from isis_ch.documentos dd
         where b.empresa = 'chef' and dd.familia = 'factura_venta' and dd.contraparte_codigo is not null
           and canon_cod(dd.contraparte_codigo) = canon_cod(b.cod_cliente)
           and dd.fecha between b.fecha_salida - 3 and b.fecha_salida + 3
      ) d on true
  ), ranked as (
    select c.*,
           row_number() over (partition by c.np order by c.dcajas, c.dfecha) as rn,
           count(*) filter (where c.doc_id is not null and c.dcajas <= c.tolerancia_cajas) over (partition by c.np) as candidatos_cercanos
      from cand c
  ), top1 as (
    select * from ranked where rn = 1
  )
  select top1.np, top1.tanda, top1.fecha_salida, top1.rs_virgilio, top1.cod_cliente, top1.empresa,
         top1.neto_calculado, top1.cajas_ent, top1.items_sin_precio,
         case when top1.doc_id is not null and top1.dcajas <= top1.tolerancia_cajas then top1.doc_id end as doc_id,
         case when top1.doc_id is not null and top1.dcajas <= top1.tolerancia_cajas then top1.comprobante_id end as comprobante_id,
         case when top1.doc_id is not null and top1.dcajas <= top1.tolerancia_cajas then top1.doc_fecha end as doc_fecha,
         case when top1.doc_id is not null and top1.dcajas <= top1.tolerancia_cajas then top1.factura_total end as factura_total,
         case when top1.doc_id is not null and top1.dcajas <= top1.tolerancia_cajas then top1.factura_neto end as factura_neto,
         case when top1.doc_id is not null and top1.dcajas <= top1.tolerancia_cajas then top1.factura_cajas end as factura_cajas,
         case when top1.doc_id is not null and top1.dcajas <= top1.tolerancia_cajas then top1.storage_path end as storage_path,
         case when top1.doc_id is not null and top1.dcajas <= top1.tolerancia_cajas then top1.cae end as cae,
         top1.candidatos_cercanos,
         case when top1.doc_id is not null and top1.dcajas <= top1.tolerancia_cajas then top1.factura_neto - top1.neto_calculado end as diff,
         case when top1.doc_id is not null and top1.dcajas <= top1.tolerancia_cajas and top1.neto_calculado is not null and top1.neto_calculado <> 0
              then round((top1.factura_neto - top1.neto_calculado) / top1.neto_calculado * 100, 2) end as diff_pct,
         case when top1.neto_calculado is null then 'sin_neto'
              when top1.doc_id is null or top1.dcajas > top1.tolerancia_cajas then 'sin_factura'
              when top1.candidatos_cercanos > 1 then 'ambiguo'
              when abs(coalesce(top1.factura_neto, 0) - top1.neto_calculado) <= greatest(50, top1.neto_calculado * 0.01) then 'ok'
              else 'diff' end as estado
    from top1
) v;
revoke all on public.gv_vista_cruce_facturacion from anon, authenticated;

create or replace function public.gv_cruce_facturacion_resumen(
  p_desde   date default (current_date - interval '30 days')::date,
  p_hasta   date default current_date,
  p_empresa text default null,
  p_estado  text default null,
  p_q       text default null,
  p_limit   int  default 100,
  p_offset  int  default 0)
returns table (
  np text, tanda text, fecha_salida date, rs_virgilio text, cod_cliente text, empresa text,
  neto_calculado numeric, cajas_ent numeric, items_sin_precio bigint,
  doc_id bigint, comprobante_id text, doc_fecha date, factura_total numeric, factura_neto numeric,
  factura_cajas numeric, storage_path text, cae text, candidatos_cercanos bigint,
  diff numeric, diff_pct numeric, estado text, es_super boolean, total_count bigint)
language sql security definer set search_path = public, pg_temp
as $$
  select v.*, count(*) over ()::bigint as total_count
    from public.gv_vista_cruce_facturacion v
   where v.fecha_salida between p_desde and p_hasta
     and (p_empresa is null or p_empresa = '' or v.empresa = p_empresa)
     and (p_estado is null or p_estado = '' or v.estado = p_estado)
     and (p_q is null or p_q = ''
          or v.rs_virgilio ilike '%'||p_q||'%' or v.cod_cliente ilike '%'||p_q||'%' or v.np ilike '%'||p_q||'%')
   order by case v.estado when 'diff' then 0 when 'ambiguo' then 1 when 'sin_factura' then 2 when 'sin_neto' then 3 else 4 end,
            abs(coalesce(v.diff, 0)) desc
   limit greatest(p_limit, 1) offset greatest(p_offset, 0)
$$;
grant execute on function public.gv_cruce_facturacion_resumen(date, date, text, text, text, int, int) to anon, authenticated;

create or replace function public.gv_cruce_facturacion_totales(
  p_desde   date default (current_date - interval '30 days')::date,
  p_hasta   date default current_date,
  p_empresa text default null)
returns table (estado text, n bigint, suma_diff numeric)
language sql security definer set search_path = public, pg_temp
as $$
  select estado, count(*)::bigint, coalesce(sum(diff), 0)
    from public.gv_vista_cruce_facturacion
   where fecha_salida between p_desde and p_hasta
     and (p_empresa is null or p_empresa = '' or empresa = p_empresa)
   group by estado
$$;
grant execute on function public.gv_cruce_facturacion_totales(date, date, text) to anon, authenticated;
