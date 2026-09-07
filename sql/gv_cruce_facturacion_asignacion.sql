-- =============================================================================
-- v14.13 (2026-09-07) — Cruce Facturación ↔ ISIS: asignación 1-a-1 de facturas
--
-- PROBLEMA que resuelve:
--   La vista elegía, para CADA NP, la factura de ISIS más parecida en cajas.
--   Nada impedía que DOS NP del mismo cliente y el mismo día eligieran LA MISMA
--   factura. Cuando eso pasaba, la NP quedaba marcada 'ambiguo' y no se cruzaba.
--   Medido el 2026-09-07 sobre los últimos 30 días: 52 NP en 'ambiguo', todas
--   con más de una candidata — o sea, el 100% de ese estado era este problema.
--
-- QUÉ CAMBIA:
--   Cada factura de ISIS se usa UNA SOLA VEZ. La asignación es greedy: se
--   recorren todos los pares (NP, factura) elegibles ordenados por diferencia
--   de cajas y después por diferencia de fecha, y se toma el par si ni la NP ni
--   la factura fueron ya tomadas. Determinístico: el orden desempata por np y
--   por doc_id, así dos corridas dan lo mismo.
--
--   El estado 'ambiguo' DESAPARECE. Una NP que se quedó sin factura porque otra
--   NP se la llevó cae en 'sin_factura' (que es la verdad: para esa NP no queda
--   comprobante). 'candidatos_cercanos' se conserva y ahora significa "cuántas
--   facturas eran elegibles para esta NP", que es la pista para revisarla.
--
--   Elegibilidad (sin cambios): mismo cliente (canon_cod) y misma empresa,
--   fecha de la factura dentro de ±3 días de la fecha de salida, y diferencia
--   de cajas dentro de la tolerancia (15% de lo entregado, con piso de 1 caja).
--
-- COLUMNAS: las mismas 22 de antes, en el mismo orden. Por eso NO hace falta
--   tocar gv_cruce_facturacion_resumen ni _totales (hacen `select v.*`) ni el
--   front. Sólo cambia el contenido.
--
-- ROLLBACK: sql/backups/gv_cruce_facturacion_20260907_pre_asignacion.sql
--
-- COMPARTIDA: todo lleva prefijo gv_ y no lo lee Producción Virgilio
--   (verificado con grep sobre el repo). No se toca ningún objeto de Producción.
-- =============================================================================

-- 1) La asignación. Va en plpgsql porque el greedy necesita recorrer los pares
--    en orden y saltear los que chocan — eso no se puede escribir como una vista.
--    Devuelve UNA fila por NP que tuvo al menos una factura elegible:
--      doc_id     = la factura que le tocó (null si otra NP se la llevó)
--      candidatos = cuántas facturas eran elegibles para esa NP
create or replace function public.gv_cruce_fc_asignacion()
returns table(np text, doc_id bigint, candidatos integer)
language plpgsql
volatile
security definer
set search_path to 'public', 'pg_temp'
as $$
declare
  r record;
begin
  drop table if exists _gv_cruce_pares;
  create temp table _gv_cruce_pares as
  with base as (
    select f.np,
           f.fecha_salida,
           canon_cod(f.cod_cliente)          as cc,
           gv_empresa_de_np_texto(f.np)      as empresa,
           coalesce(n.cajas_ent, 0::numeric) as cajas_ent
      from public."Facturacion_NP" f
      left join public.gv_vista_facturacion_neto n on n.np = f.np
  ), docs as (
    select 'lk'::text                        as empresa,
           d.id,
           d.fecha,
           coalesce(d.total_cajas, -1::numeric) as cajas,
           canon_cod(d.contraparte_codigo)   as cc
      from isis_lk.documentos d
     where d.familia = 'factura_venta'
       and d.contraparte_codigo is not null
    union all
    select 'chef'::text,
           d.id,
           d.fecha,
           coalesce(d.total_cajas, -1::numeric),
           canon_cod(d.contraparte_codigo)
      from isis_ch.documentos d
     where d.familia = 'factura_venta'
       and d.contraparte_codigo is not null
  )
  select b.np,
         d.id                              as doc_id,
         abs(d.cajas - b.cajas_ent)        as dcajas,
         abs(d.fecha - b.fecha_salida)     as dfecha
    from base b
    join docs d
      on d.empresa = b.empresa
     and d.cc      = b.cc
     and d.fecha between b.fecha_salida - 3 and b.fecha_salida + 3
   where abs(d.cajas - b.cajas_ent) <= greatest(1::numeric, b.cajas_ent * 0.15);

  drop table if exists _gv_cruce_asig;
  create temp table _gv_cruce_asig(np text primary key, doc_id bigint unique);

  -- Greedy: el par más ajustado primero. Si la NP o la factura ya se usaron,
  -- el unique lo rechaza y se sigue. Es O(pares) con la base de hoy (1.167 NP).
  for r in
    select p.np, p.doc_id
      from _gv_cruce_pares p
     order by p.dcajas, p.dfecha, p.np, p.doc_id
  loop
    begin
      insert into _gv_cruce_asig(np, doc_id) values (r.np, r.doc_id);
    exception when unique_violation then
      null;
    end;
  end loop;

  return query
    select p.np, a.doc_id, count(*)::integer
      from _gv_cruce_pares p
      left join _gv_cruce_asig a on a.np = p.np
     group by p.np, a.doc_id;
end
$$;

comment on function public.gv_cruce_fc_asignacion() is
  'v14.13 — Asigna cada factura de ISIS a UNA sola NP (greedy por diferencia de cajas y fecha). La usa gv_vista_cruce_facturacion.';

-- 2) La vista, ahora apoyada en la asignación. Mismas 22 columnas que antes.
create or replace view public.gv_vista_cruce_facturacion
with (security_invoker = true) as
with base as (
  select f.np,
         f.tanda,
         f.fecha_salida,
         f.razon_social               as rs_virgilio,
         f.cod_cliente,
         gv_empresa_de_np_texto(f.np) as empresa,
         n.neto                       as neto_calculado,
         n.cajas_ent,
         n.items_sin_precio
    from public."Facturacion_NP" f
    left join public.gv_vista_facturacion_neto n on n.np = f.np
), asig as (
  select * from public.gv_cruce_fc_asignacion()
), doc as (
  select 'lk'::text as empresa, d.id, d.comprobante_id, d.fecha, d.total,
         d.subt_gravado, d.total_cajas, d.storage_path, d.cae
    from isis_lk.documentos d
   where d.familia = 'factura_venta'
  union all
  select 'chef'::text, d.id, d.comprobante_id, d.fecha, d.total,
         d.subt_gravado, d.total_cajas, d.storage_path, d.cae
    from isis_ch.documentos d
   where d.familia = 'factura_venta'
)
select b.np,
       b.tanda,
       b.fecha_salida,
       b.rs_virgilio,
       b.cod_cliente,
       b.empresa,
       b.neto_calculado,
       b.cajas_ent,
       b.items_sin_precio,
       d.id                                as doc_id,
       d.comprobante_id,
       d.fecha                             as doc_fecha,
       d.total::numeric                    as factura_total,
       d.subt_gravado::numeric             as factura_neto,
       d.total_cajas::numeric              as factura_cajas,
       d.storage_path,
       d.cae,
       coalesce(a.candidatos, 0)::bigint   as candidatos_cercanos,
       case when d.id is not null then (d.subt_gravado - b.neto_calculado)::numeric end as diff,
       case when d.id is not null and b.neto_calculado is not null and b.neto_calculado <> 0
            then round((d.subt_gravado - b.neto_calculado) / b.neto_calculado * 100, 2)::numeric end as diff_pct,
       case when b.neto_calculado is null then 'sin_neto'
            when d.id is null            then 'sin_factura'
            when abs(coalesce(d.subt_gravado, 0) - b.neto_calculado)
                 <= greatest(50::numeric, b.neto_calculado * 0.01) then 'ok'
            else 'diff'
       end                                 as estado,
       exists (select 1 from cobranzas_cliente_cadena cc
                where cc.cod_cliente = b.cod_cliente and cc.empresa = b.empresa) as es_super
  from base b
  left join asig a on a.np = b.np
  left join doc  d on d.empresa = b.empresa and d.id = a.doc_id;

comment on view public.gv_vista_cruce_facturacion is
  'v14.13 — Cruza el neto que calculó Gestión contra la factura real de ISIS. Cada factura se asigna a una sola NP (gv_cruce_fc_asignacion). El estado ambiguo ya no existe.';

-- 3) Seguridad: la vista ya es security_invoker y no tiene grants para anon /
--    authenticated (se lee sólo por las RPC SECURITY DEFINER). La función nueva
--    nace con EXECUTE para PUBLIC, así que hay que sacárselo a mano.
revoke execute on function public.gv_cruce_fc_asignacion() from public;
revoke execute on function public.gv_cruce_fc_asignacion() from anon;
revoke execute on function public.gv_cruce_fc_asignacion() from authenticated;
