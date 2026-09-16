-- v18.88 (2026-09-16) — Conciliación: "No se pudo cargar el detalle: statement timeout".
--
-- SÍNTOMA
--   Facturación > Conciliación > 🔍 Comparar abría el modal y moría con
--   "canceling statement due to statement timeout".
--
-- CAUSA (dos capas, las dos medidas)
--   1) gv_conciliacion_comparar(np) resolvía el doc_id de la factura por
--      gv_vista_cruce_facturacion, y esa vista llamaba a gv_cruce_fc_asignacion() EN VIVO.
--      Esa función es plpgsql, arma dos temp tables y recalcula la asignación GLOBAL
--      NP<->factura (867 pares) en CADA consulta: 1,2 s fijos, traiga una fila o mil.
--   2) Peor: el "where i.np = r.np" contra gv_vista_facturacion_neto_items quedaba como
--      JOIN (r era un CTE), así que la vista NO podía empujar el filtro y calculaba los
--      ítems de TODAS las NP. Total por llamada: 2.143 ms.
--   3) Y el listado dispara gv_conciliacion_motivo —que llama a comparar— para CADA fila
--      con diferencia (hoy 23), todas en paralelo. 23 recómputos globales simultáneos
--      saturaban el pool y el Comparar del usuario se comía el statement_timeout de 8 s.
--
-- FIX
--   a) Cache GV_Cruce_FC_Asig + gv_cruce_fc_asig_refrescar(). La asignación es greedy
--      GLOBAL (cada factura se asigna a UNA sola NP, por orden de dcajas/dfecha), así que
--      NO se puede calcular por NP: hay que cachearla. La refresca el cron
--      gv-cruce-fc-asig (cada 10 min) y gv_conciliacion_lista si tiene más de 3 min.
--   b) gv_vista_cruce_facturacion lee el cache en vez de llamar a la función.
--   c) gv_conciliacion_comparar pasa a plpgsql y resuelve np/empresa/doc_id/neto a
--      VARIABLES antes de la consulta grande → el filtro por NP sí se empuja.
--
-- MEDIDO (antes → después)
--   gv_conciliacion_comparar('LK 0097')   2.143 ms → 90 ms   (24x)
--   gv_conciliacion_motivo('LK 0097')     ~2.900 ms → 31 ms  (93x)
--   gv_conciliacion_lista(200,0)          ~3.000 ms → 920 ms
--   gv_vista_cruce_facturacion completa   1.303 filas, md5 7f08b03adaa982c79c61e675f5d31f7c
--                                         ANTES y DESPUÉS (idéntica)
--   gv_conciliacion_comparar, las 142 NP de GV_Conciliacion_Facturacion: firma md5 por NP
--   igual en 142 de 142 (zz_backups."GV_Cmp_Comparar_20260916").
--
-- ROLLBACK: sql/backups/gv_conciliacion_comparar_20260916_pre_v1888.sql

-- 1) EL CACHE ------------------------------------------------------------------------
create table if not exists public."GV_Cruce_FC_Asig" (
  np             text primary key,
  doc_id         bigint,
  candidatos     integer not null default 0,
  actualizado_at timestamptz not null default now()
);
alter table public."GV_Cruce_FC_Asig" enable row level security;   -- sin policies = anon no ve nada
revoke all on public."GV_Cruce_FC_Asig" from anon, authenticated;
comment on table public."GV_Cruce_FC_Asig" is
 'v18.88 - cache de gv_cruce_fc_asignacion() (asignacion global NP<->factura de ISIS). La asignacion es GREEDY GLOBAL: no se puede calcular por NP, por eso se cachea. La refresca gv_cruce_fc_asig_refrescar() (cron gv-cruce-fc-asig, cada 10 min) y gv_conciliacion_lista si tiene mas de 3 min. Sin policies = anon no ve nada; se lee solo por funciones SECURITY DEFINER.';

-- 2) REFRESCO ------------------------------------------------------------------------
create or replace function public.gv_cruce_fc_asig_refrescar()
returns integer
language plpgsql
security definer
set search_path to 'public','pg_temp'
set statement_timeout to '120000'
as $$
declare n integer;
begin
  drop table if exists _gv_asig_new;
  create temp table _gv_asig_new as select * from public.gv_cruce_fc_asignacion();
  select count(*) into n from _gv_asig_new;
  -- guard: si la asignacion viene vacia, NO se pisa el cache (un cache vacio dejaria la
  -- Conciliacion sin facturas y nadie se enteraria).
  if n = 0 then drop table if exists _gv_asig_new; return 0; end if;
  delete from public."GV_Cruce_FC_Asig" a where not exists (select 1 from _gv_asig_new x where x.np = a.np);
  insert into public."GV_Cruce_FC_Asig" (np, doc_id, candidatos, actualizado_at)
  select x.np, x.doc_id, x.candidatos, now() from _gv_asig_new x
  on conflict (np) do update
     set doc_id = excluded.doc_id, candidatos = excluded.candidatos, actualizado_at = now();
  drop table if exists _gv_asig_new;
  return n;
end $$;
revoke execute on function public.gv_cruce_fc_asig_refrescar() from public, anon, authenticated;

create or replace function public.gv_cruce_fc_asig_refrescar_si_viejo(p_seg integer default 180)
returns integer
language plpgsql
security definer
set search_path to 'public','pg_temp'
as $$
declare v_ult timestamptz;
begin
  select max(actualizado_at) into v_ult from public."GV_Cruce_FC_Asig";
  if v_ult is null or v_ult < now() - make_interval(secs => greatest(p_seg, 0)) then
    return public.gv_cruce_fc_asig_refrescar();
  end if;
  return -1;   -- estaba fresco, no se toco
end $$;
revoke execute on function public.gv_cruce_fc_asig_refrescar_si_viejo(integer) from public, anon, authenticated;

select public.gv_cruce_fc_asig_refrescar();

-- 3) LA VISTA LEE EL CACHE -----------------------------------------------------------
create or replace view public.gv_vista_cruce_facturacion as
 with base as (
   select f.np, f.tanda, f.fecha_salida, f.razon_social as rs_virgilio, f.cod_cliente,
          gv_empresa_de_np_texto(f.np) as empresa,
          n.neto as neto_calculado, n.cajas_ent, n.items_sin_precio
     from "Facturacion_NP" f
     left join gv_vista_facturacion_neto n on n.np = f.np
 ), asig as (
   -- v18.88: lee el CACHE (GV_Cruce_FC_Asig). Antes llamaba a gv_cruce_fc_asignacion(),
   -- que recalcula la asignacion GLOBAL con temp tables (1,2 s) en CADA consulta.
   select a.np, a.doc_id, a.candidatos from public."GV_Cruce_FC_Asig" a
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
-- OBLIGATORIO: CREATE OR REPLACE VIEW borra las reloptions.
alter view public.gv_vista_cruce_facturacion set (security_invoker = true);

-- 4) COMPARAR SIN LA VISTA Y CON EL FILTRO EMPUJADO ----------------------------------
create or replace function public.gv_conciliacion_comparar(p_np text)
returns table(cod text, descripcion text, cajas_ges numeric, cajas_isis numeric,
              precio_ges numeric, precio_isis numeric, dto_ges numeric, dto_isis numeric,
              importe_ges numeric, importe_isis numeric, diff numeric,
              sin_precio_ges boolean, motivo text)
language plpgsql
security definer
set search_path to 'public','pg_temp'
as $$
#variable_conflict use_column
declare
  v_np text; v_empresa text; v_doc_id bigint; v_neto numeric;
begin
  -- v18.88 — np/empresa/doc_id/neto se resuelven a VARIABLES antes de la consulta grande.
  -- Antes salian de un CTE (r) que ademas joineaba gv_vista_cruce_facturacion: el filtro
  -- "i.np = r.np" quedaba como JOIN y gv_vista_facturacion_neto_items no podia empujarlo,
  -- asi que calculaba los items de TODAS las NP. 2.143 ms -> 90 ms por llamada.
  -- El doc_id sale del cache GV_Cruce_FC_Asig (la asignacion NP<->factura es greedy GLOBAL,
  -- no se puede calcular por NP; la refresca gv_cruce_fc_asig_refrescar).
  select s.np, s.empresa into v_np, v_empresa
    from public."GV_Conciliacion_Facturacion" s
   where s.np = p_np or regexp_replace(s.np, '\.0+$', '') = regexp_replace(p_np, '\.0+$', '')
   limit 1;
  if v_np is null then return; end if;

  select a.doc_id into v_doc_id from public."GV_Cruce_FC_Asig" a where a.np = v_np;
  if v_doc_id is not null then
    if v_empresa = 'lk' then
      select d.subt_gravado::numeric into v_neto from isis_lk.documentos d
       where d.id = v_doc_id and d.familia = 'factura_venta';
    else
      select d.subt_gravado::numeric into v_neto from isis_ch.documentos d
       where d.id = v_doc_id and d.familia = 'factura_venta';
    end if;
    if not found then v_doc_id := null; end if;
  end if;

  return query
  with ges as (
    select canon_cod(i.cod) as cc, min(i.cod) as cod,
           sum(i.cajas_ent) as cajas, max(i.precio_lista) as precio,
           max(i.dto_vol) as dto, sum(round(coalesce(i.importe_ent,0) * i.factor_web, 2)) as importe,
           bool_or(i.sin_precio) as sin_precio
      from public.gv_vista_facturacion_neto_items i
     where i.np = v_np
     group by canon_cod(i.cod)
  ), isis_raw as (
    -- solo renglones con codigo: el "2% Descuento Web" viene sin codigo y con importe null
    select canon_cod(di.codigo_articulo) as cc, min(di.codigo_articulo) as cod, max(di.descripcion) as descripcion,
           sum(di.cantidad_caja) as cajas,
           round(sum(di.importe) / nullif(sum(di.cantidad * (1 - coalesce(di.dto_1,0)/100.0) * (1 - coalesce(di.dto_2,0)/100.0)), 0), 2) as precio,
           max(coalesce(di.dto_1,0) + coalesce(di.dto_2,0)) as dto, sum(di.importe) as importe_gross
      from (
        select codigo_articulo, descripcion, cantidad, cantidad_caja, precio_unit, dto_1, dto_2, importe
          from isis_lk.documento_items
         where v_empresa = 'lk' and documento_id = v_doc_id and codigo_articulo is not null
        union all
        select codigo_articulo, descripcion, cantidad, cantidad_caja, precio_unit, dto_1, dto_2, importe
          from isis_ch.documento_items
         where v_empresa = 'chef' and documento_id = v_doc_id and codigo_articulo is not null
      ) di
     group by canon_cod(di.codigo_articulo)
  ), fac as (
    -- factor del descuento global prorrateado por renglon (neto / suma bruta); 1 si no hay
    select case when sum(importe_gross) > 0 and v_neto is not null
                then v_neto / sum(importe_gross) else 1 end as factor
      from isis_raw
  ), isis as (
    select i.cc, i.cod, i.descripcion, i.cajas, i.precio, i.dto,
           round(i.importe_gross * (select factor from fac), 2) as importe
      from isis_raw i
  )
  select coalesce(g.cod, x.cod), x.descripcion,
         g.cajas, x.cajas, g.precio, x.precio,
         round(coalesce(g.dto,0) * 100, 2), x.dto,
         g.importe, x.importe,
         round(coalesce(x.importe,0) - coalesce(g.importe,0), 2),
         coalesce(g.sin_precio, false),
         case when g.cc is null then 'falta_en_gestion'
              when x.cc is null then 'no_facturado'
              when coalesce(g.sin_precio,false) then 'sin_precio'
              when round(coalesce(g.dto,0)*100,2) <> coalesce(x.dto,0) then 'descuento'
              when round(coalesce(g.precio,0),2) <> round(coalesce(x.precio,0),2) then 'precio'
              when abs(coalesce(x.importe,0) - coalesce(g.importe,0)) > 1 then 'importe'
              else 'ok' end
    from ges g
    full outer join isis x on x.cc = g.cc
   order by abs(coalesce(x.importe,0) - coalesce(g.importe,0)) desc, coalesce(g.cod, x.cod);
end $$;

-- 5) LA PANTALLA GARANTIZA EL CACHE FRESCO -------------------------------------------
create or replace function public.gv_conciliacion_lista(p_limit integer default 200, p_offset integer default 0, p_q text default null::text, p_empresa text default null::text)
returns table(np text, empresa text, tanda text, cod_cliente text, razon_social text, fecha_salida date, cajas_ent numeric, neto_gestion numeric, items_sin_precio integer, registrado_at timestamp with time zone, factura_neto numeric, factura_cajas numeric, comprobante_id text, doc_fecha date, storage_path text, es_super boolean, diff numeric, diff_pct numeric, estado text, neto_actual numeric, corregido boolean, motivo text, total_count bigint)
language plpgsql
security definer
set search_path to 'public','pg_temp'
set statement_timeout to '20000'
as $$
#variable_conflict use_column
begin
  -- v18.88 — la pantalla es la que garantiza el cache fresco: si GV_Cruce_FC_Asig tiene mas de
  -- 3 min, se recalcula aca (1,3 s) y asi los 🔍 Comparar / motivos que vienen despues leen algo
  -- al dia. El cron gv-cruce-fc-asig lo mantiene fresco para el resto de los consumidores.
  perform public.gv_cruce_fc_asig_refrescar_si_viejo(180);

  return query
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
   limit greatest(p_limit, 1) offset greatest(p_offset, 0);
end $$;

-- 6) CRON ----------------------------------------------------------------------------
-- select cron.schedule('gv-cruce-fc-asig', '*/10 * * * *', $c$select public.gv_cruce_fc_asig_refrescar();$c$);
-- jobid 90 al 2026-09-16.

-- CHEQUEOS
-- select count(*), max(actualizado_at) from public."GV_Cruce_FC_Asig";
-- -- el cache tiene que ser identico a la funcion viva:
-- with viva as (select * from public.gv_cruce_fc_asignacion()),
--      cache as (select np, doc_id, candidatos from public."GV_Cruce_FC_Asig")
-- select (select count(*) from (select * from viva except select * from cache) z) solo_viva,
--        (select count(*) from (select * from cache except select * from viva) z) solo_cache;
-- -- y la vista:
-- select count(*), md5(string_agg(t::text,'|' order by t.np, t.doc_id)) from public.gv_vista_cruce_facturacion t;
