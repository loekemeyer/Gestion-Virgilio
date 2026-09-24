-- v22.23 (Luis, 2026-09-24) — cruce NP ↔ factura ISIS: CH 0006 tenía asignada la factura de CH 0007.
--
-- Qué pasó: el cliente Chef 2469 (Ambrosio) tuvo dos pedidos en la tanda E12B, CH 0006 y CH 0007,
-- los dos con 25 cajas entregadas. El greedy desempataba sólo por cajas y fecha: CH 0006 se llevó
-- la FC-A-0006-00005554 (14/09), que tiene los artículos de CH 0007, y CH 0007 quedó sin factura.
-- La factura de CH 0006 es la FC-A-0006-00005558 (15/09, $717.124,80 = lo armado). NO fue por
-- faltantes: los faltantes (727E ×2, 865E ×1) están bien fuera de la factura.
--
-- Dos cambios:
--  1) Desempate por ARTÍCULOS: mism = códigos entregados de la NP que no están en la factura (la L
--     se pela de los dos lados). Orden: mism, dcajas, dfecha.
--  2) Ventana de fecha hasta facturado_at + 3 (la 5558 salió el 15/09, 4 días después de la salida
--     del 11/09, y quedaba afuera de ±3).
--
-- Medido: asignadas 958 -> 980. Cambian 22 NP y en todas mejora la coincidencia: 7 pares de ISIS
-- intercambiados que tenían 3 a 17 artículos que no estaban en la factura pasan a 0-1, 8 NP de
-- Chef (44612-44619) que no tenían factura la consiguen, y CH 0006/CH 0007 quedan con $0 de diferencia.
-- Conciliación: 204 de 215 facturadas dan igual. gv_cruce_fc_asig_refrescar 1,3 s.
--
-- Rollback: sacar el bloque "mism", volver el order by a "p.dcajas, p.dfecha, p.np, p.doc_id" y la
-- ventana a "b.fecha_salida - 3 and b.fecha_salida + 3"; después select public.gv_cruce_fc_asig_refrescar();

CREATE OR REPLACE FUNCTION public.gv_cruce_fc_asignacion()
 RETURNS TABLE(np text, doc_id bigint, candidatos integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
           coalesce(n.cajas_ent, 0::numeric) as cajas_ent,
           -- v22.23: la factura puede salir dias despues de la salida (CH 0006: salio 11/09, se mando
           -- a facturar el 14/09 y ISIS la emitio el 15/09). La ventana llega hasta facturado + 3.
           greatest(f.fecha_salida, (f.facturado_at at time zone 'America/Argentina/Buenos_Aires')::date) as fecha_fc
      from public."Facturacion_NP" f
      left join public.gv_vista_facturacion_neto n on n.np = f.np
  ), docs as (
    select 'lk'::text                           as empresa,
           d.id,
           d.fecha,
           coalesce(d.total_cajas, -1::numeric) as cajas,
           canon_cod(d.contraparte_codigo)      as cc
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
         d.id                          as doc_id,
         abs(d.cajas - b.cajas_ent)    as dcajas,
         abs(d.fecha - b.fecha_salida) as dfecha
    from base b
    join docs d
      on d.empresa = b.empresa
     and d.cc      = b.cc
     and d.fecha between b.fecha_salida - 3 and coalesce(b.fecha_fc, b.fecha_salida) + 3
   where abs(d.cajas - b.cajas_ent) <= greatest(1::numeric, b.cajas_ent * 0.15);

  -- v22.23 (Luis): desempate por ARTICULOS en comun. Con dos pedidos del mismo cliente y las
  -- mismas cajas (CH 0006 / CH 0007, 25 y 25) el greedy se llevaba la factura mas cercana en
  -- fecha aunque tuviera otros articulos. mism = codigos entregados de la NP que NO estan en la
  -- factura (la L se pela de los dos lados).
  alter table _gv_cruce_pares add column mism integer;
  -- v22.23: en una sola pasada (por par eran 9 s: recorria Entregas_Virgilio entero cada vez).
  -- Alias _gv_* en todo: la funcion devuelve columnas np / doc_id y un nombre suelto es ambiguo.
  drop table if exists _gv_np_cods;
  create temp table _gv_np_cods as
    select distinct regexp_replace(e.np, '\.0+$', '') as nnp,
           canon_cod(regexp_replace(upper(btrim(e.cod_art)), '([0-9E])L$', '\1')) as c
      from public."Entregas_Virgilio" e
     where coalesce(e.cajas_entregadas, 0) > 0
       and regexp_replace(e.np, '\.0+$', '') in (select _gv_p0.np from _gv_cruce_pares _gv_p0);
  drop table if exists _gv_doc_cods;
  create temp table _gv_doc_cods as
    select distinct 'lk'::text as emp, di.documento_id as did,
           canon_cod(regexp_replace(upper(btrim(di.codigo_articulo)), '([0-9E])L$', '\1')) as c
      from isis_lk.documento_items di
     where di.codigo_articulo is not null and di.documento_id in (select _gv_p0.doc_id from _gv_cruce_pares _gv_p0)
    union
    select distinct 'chef'::text, di.documento_id,
           canon_cod(regexp_replace(upper(btrim(di.codigo_articulo)), '([0-9E])L$', '\1'))
      from isis_ch.documento_items di
     where di.codigo_articulo is not null and di.documento_id in (select _gv_p0.doc_id from _gv_cruce_pares _gv_p0);
  update _gv_cruce_pares _gv_p set mism = _gv_z.n
    from (select _gv_p2.np as znp, _gv_p2.doc_id as zdoc, count(*) filter (where _gv_dc.c is null) as n
            from _gv_cruce_pares _gv_p2
            join _gv_np_cods _gv_nc on _gv_nc.nnp = _gv_p2.np
            left join _gv_doc_cods _gv_dc on _gv_dc.did = _gv_p2.doc_id and _gv_dc.emp = gv_empresa_de_np_texto(_gv_p2.np) and _gv_dc.c = _gv_nc.c
           group by _gv_p2.np, _gv_p2.doc_id) _gv_z
   where _gv_z.znp = _gv_p.np and _gv_z.zdoc = _gv_p.doc_id;
  update _gv_cruce_pares set mism = 0 where mism is null;

  drop table if exists _gv_cruce_asig;
  create temp table _gv_cruce_asig(np text primary key, doc_id bigint unique);

  for r in
    select p.np, p.doc_id
      from _gv_cruce_pares p
     order by p.mism, p.dcajas, p.dfecha, p.np, p.doc_id
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
$function$;

select public.gv_cruce_fc_asig_refrescar();
