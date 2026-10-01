-- v25.93 · Hot Sale por súper, ítem por ítem (Thomas, 01/10/2026).
-- Objetos NUEVOS, sólo lectura, SECURITY DEFINER con guard de supervisor (leen isis_lk / isis_ch,
-- que anon no ve). Los usa hotsale.js: el selector de súper y la lista de ítems que ese súper
-- compró en los últimos N meses (default 12), ordenada por ÚLTIMA COMPRA, con la familia
-- (importado / nacional, por public."Importados") y el rubro (GV_Producto_Tipo.familia).
-- Rollback: drop function public.gv_hotsale_items_super(text,int); drop function public.gv_hotsale_supers();

create or replace function public.gv_hotsale_supers()
returns table(super_key text, nombre text, codigos jsonb, ultima_compra date)
language sql security definer set search_path = public, pg_temp as $$
  with s as (
    select super_key, min(nombre) nombre,
           jsonb_agg(jsonb_build_object('empresa', empresa, 'cod', cod) order by empresa) codigos
      from public."GV_Supers" where activo and super_key is not null group by super_key),
  u as (
    select g.super_key, max(d.fecha) ult
      from public."GV_Supers" g
      join isis_lk.documentos d on g.empresa = 'lk' and d.familia = 'factura_venta'
       and regexp_replace(coalesce(d.contraparte_codigo,''),'^0+','') = regexp_replace(g.cod,'^0+','')
     where g.activo group by g.super_key
    union all
    select g.super_key, max(d.fecha)
      from public."GV_Supers" g
      join isis_ch.documentos d on g.empresa = 'chef' and d.familia = 'factura_venta'
       and regexp_replace(coalesce(d.contraparte_codigo,''),'^0+','') = regexp_replace(g.cod,'^0+','')
     where g.activo group by g.super_key)
  select s.super_key, s.nombre, s.codigos, (select max(ult) from u where u.super_key = s.super_key) ultima_compra
    from s
   where (es_supervisor_virgilio() or gv_es_supervisor_o_servicio())
   order by ultima_compra desc nulls last, s.nombre;
$$;

create or replace function public.gv_hotsale_items_super(p_super_key text, p_meses int default 12)
returns table(empresa text, cod text, cod_base text, descripcion text, es_importado boolean, rubro text, tipo text,
              ultima_compra date, cajas numeric, unidades numeric, lineas int)
language sql security definer set search_path = public, pg_temp as $$
  with g as (select empresa, regexp_replace(cod,'^0+','') cod from public."GV_Supers" where activo and super_key = p_super_key),
  li as (
    select 'lk'::text empresa, i.codigo_articulo cod, i.descripcion, d.fecha, i.cantidad_caja, i.cantidad
      from g join isis_lk.documentos d on g.empresa = 'lk' and d.familia = 'factura_venta'
       and regexp_replace(coalesce(d.contraparte_codigo,''),'^0+','') = g.cod
       and d.fecha >= current_date - make_interval(months => greatest(coalesce(p_meses,12),1))
      join isis_lk.documento_items i on i.documento_id = d.id
    union all
    select 'chef', i.codigo_articulo, i.descripcion, d.fecha, i.cantidad_caja, i.cantidad
      from g join isis_ch.documentos d on g.empresa = 'chef' and d.familia = 'factura_venta'
       and regexp_replace(coalesce(d.contraparte_codigo,''),'^0+','') = g.cod
       and d.fecha >= current_date - make_interval(months => greatest(coalesce(p_meses,12),1))
      join isis_ch.documento_items i on i.documento_id = d.id),
  a as (
    select empresa, upper(btrim(cod)) cod,
           regexp_replace(regexp_replace(upper(btrim(cod)),'^0+',''),'([0-9E])L$','\1') cod_base,
           (array_agg(descripcion order by fecha desc))[1] descripcion,
           max(fecha) ultima_compra,
           round(sum(coalesce(cantidad_caja,0)),2) cajas, round(sum(coalesce(cantidad,0)),2) unidades, count(*)::int lineas
      from li where coalesce(btrim(cod),'') <> '' group by 1,2,3)
  select a.empresa, a.cod, a.cod_base, a.descripcion,
         exists (select 1 from public."Importados" im where regexp_replace(upper(btrim(im.cod_art)),'^0+','') = a.cod_base) es_importado,
         coalesce(t.familia, 'Sin rubro') rubro, t.tipo, a.ultima_compra, a.cajas, a.unidades, a.lineas
    from a
    left join lateral (select pt.familia, pt.tipo from public."GV_Producto_Tipo" pt
                        where regexp_replace(upper(btrim(pt.cod)),'^0+','') = a.cod_base limit 1) t on true
   where (es_supervisor_virgilio() or gv_es_supervisor_o_servicio())
   order by a.ultima_compra desc, a.cajas desc, a.cod;
$$;

revoke all on function public.gv_hotsale_supers() from public;
revoke all on function public.gv_hotsale_items_super(text, int) from public;
grant execute on function public.gv_hotsale_supers() to anon, authenticated, service_role;
grant execute on function public.gv_hotsale_items_super(text, int) to anon, authenticated, service_role;

-- chequeo (como postgres; como anon el guard devuelve vacío):
-- select * from public.gv_hotsale_supers();
-- select * from public.gv_hotsale_items_super('inc');
