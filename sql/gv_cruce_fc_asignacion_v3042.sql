-- v30.42 (Luis, 14/10/2026): Conciliación — la NP facturada ANTES de su salida quedaba "sin factura".
-- Caso: LK 0421 (Garbarino Franco Tomas) se mandó a facturar el 14/10, ISIS emitió la FC A 0004-00036219
-- ese mismo día, pero la salida está programada el 04/11. La ventana del cruce arrancaba en salida - 3
-- (01/11), así que la FC quedaba afuera. Medido: 72 de 98 NP facturadas > 3 días antes de salir, sin FC.
-- Ahora la ventana arranca en la fecha más temprana entre salida y envío a facturar, menos 3.
-- Probado antes de aplicar: 0 NP ya asignadas cambian de factura; 56 nuevas encuentran la suya.
-- Aplicado por MCP sobre la definición viva. Centinelas: 181 (complementos) y 463 (esta ventana).
-- Problema de auditoría: «Conciliación: NP facturada antes de su salida queda sin factura».

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
  -- v22.52-compl: lo que Completar Pedido sumo DESPUES de facturar no esta en la factura original
  with _gv_cpp as (
    select f2.np, sum(m.delta) as c
      from public."Movimientos_Stock" m
      join public."Facturacion_NP" f2 on f2.np = split_part(m.ref, '|', 1)
     where m.tipo = 'cp' and m.deposito = 'a_facturar' and m.delta > 0 and m.creado > f2.facturado_at
     group by f2.np
  ), base as (
    select f.np,
           f.fecha_salida,
           canon_cod(f.cod_cliente)          as cc,
           gv_empresa_de_np_texto(f.np)      as empresa,
           greatest(0::numeric, coalesce(n.cajas_ent, 0::numeric) - coalesce(_gv_c.c, 0::numeric)) as cajas_ent,
           -- v22.23: la factura puede salir dias despues de la salida (CH 0006: salio 11/09, se mando
           -- a facturar el 14/09 y ISIS la emitio el 15/09). La ventana llega hasta facturado + 3.
           greatest(f.fecha_salida, (f.facturado_at at time zone 'America/Argentina/Buenos_Aires')::date) as fecha_fc,
           -- v30.42 (Luis, 14/10): facturada ANTES de salir (LK 0421: FC 14/10, salida 04/11). La ventana
           -- arranca en la fecha mas temprana entre salida y envio a facturar.
           least(f.fecha_salida, (f.facturado_at at time zone 'America/Argentina/Buenos_Aires')::date) as fecha_desde
      from public."Facturacion_NP" f
      left join public.gv_vista_facturacion_neto n on n.np = f.np
      left join _gv_cpp _gv_c on _gv_c.np = f.np
  ), docs as (
    select 'lk'::text                           as empresa,
           d.id,
           d.fecha,
           coalesce(d.total_cajas, -1::numeric) as cajas,
           canon_cod(d.contraparte_codigo)      as cc
      from isis_lk.documentos d
     where d.familia = 'factura_venta'
       and d.contraparte_codigo is not null
       and not exists (select 1 from public."GV_Fac_Complemento_Doc" _gv_x where _gv_x.empresa = 'lk' and _gv_x.doc_id = d.id)
    union all
    select 'chef'::text,
           d.id,
           d.fecha,
           coalesce(d.total_cajas, -1::numeric),
           canon_cod(d.contraparte_codigo)
      from isis_ch.documentos d
     where d.familia = 'factura_venta'
       and d.contraparte_codigo is not null
       and not exists (select 1 from public."GV_Fac_Complemento_Doc" _gv_x where _gv_x.empresa = 'chef' and _gv_x.doc_id = d.id)
  )
  select b.np,
         d.id                          as doc_id,
         abs(d.cajas - b.cajas_ent)    as dcajas,
         abs(d.fecha - b.fecha_salida) as dfecha
    from base b
    join docs d
      on d.empresa = b.empresa
     and d.cc      = b.cc
     and d.fecha between coalesce(b.fecha_desde, b.fecha_salida) - 3 and coalesce(b.fecha_fc, b.fecha_salida) + 3
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
