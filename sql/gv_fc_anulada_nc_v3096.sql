-- v30.96 (Luis, 15/10/2026): CRUCE FC↔NP — las facturas ANULADAS por NC no son candidatas.
--
-- Caso: el 14/10 Muare (LK 4159) se facturó 3 veces (21 FC, 13 NC → 8 vivas para 8 NP), Poy (4142)
-- y Rosemblit (1917) 2 veces. El cruce no miraba las NC y desempataba por doc_id más bajo, así que
-- las 10 NP quedaron asignadas a las FC del PRIMER lote, que es el anulado.
--
-- ISIS no dice qué factura anula cada NC (isis_*.comprobantes_aplicados está vacío para las NC y el
-- PDF no trae el comprobante asociado). Pero la NC de anulación lista los MISMOS artículos con las
-- MISMAS cantidades y el mismo total que la FC. Se aparea por esa FIRMA, como una PILA: la NC anula
-- la ÚLTIMA factura viva con su firma emitida antes que ella (emitir → anular → re-emitir deja viva
-- la última). Una NC parcial (devolución de parte, descuento «P25%») no iguala la firma de ninguna
-- FC y no anula nada: la FC sigue viva, que es lo correcto.
--
-- Orden "antes que ella": la fecha ISIS es sólo día; dentro del día se usa la hora de ingesta
-- (created_at) con 3 min de margen (el lector levanta los PDF de a uno por minuto y mezcla el orden
-- dentro del minuto). Si con eso no aparece ninguna (cargas históricas en bloque, donde la hora de
-- ingesta no es la de emisión) se toma la última con esa firma, sin mirar la hora.
--
-- Piezas:
--   GV_FC_Anulada            (empresa, fc_id) → nc_id. Incremental: lo apareado no se recalcula.
--   gv_isis_doc_firma        firma de un documento (artículo×cantidad, ordenado).
--   gv_fc_nc_aparear(p_dias) aparea las NC sin aparear de los últimos p_dias. -2 = otra corrida.
--   gv_cruce_fc_asignacion   + not exists GV_FC_Anulada en docs (centinela).
--   gv_fac_complemento_cruce + idem.
--   gv_cruce_fc_asig_refrescar  llama a gv_fc_nc_aparear() antes de asignar (centinela). Nunca tumba el refresco.
--   gv_fc_anuladas_np(p_nps) para la Conciliación: qué FC anuladas tenía cada NP.

create table if not exists public."GV_FC_Anulada" (
  empresa        text        not null check (empresa in ('lk', 'chef')),
  fc_id          bigint      not null,
  nc_id          bigint      not null,
  fc_comprobante text,
  nc_comprobante text,
  cliente        text,
  total          numeric,
  cajas          numeric,
  fc_fecha       date,
  nc_fecha       date,
  firma          text,
  por_hora       boolean     not null default true,   -- false = se apareó sin la hora de ingesta (fallback)
  apareado_at    timestamptz not null default now(),
  primary key (empresa, fc_id),
  unique (empresa, nc_id)
);
alter table public."GV_FC_Anulada" enable row level security;
revoke all on public."GV_FC_Anulada" from anon, authenticated;
create index if not exists gv_fc_anulada_cliente on public."GV_FC_Anulada" (empresa, cliente, fc_fecha);

create or replace function public.gv_isis_doc_firma(p_empresa text, p_doc_id bigint)
returns text language sql stable security definer set search_path = public as $f$
  select string_agg(c || 'x' || q, '|' order by c, q)
    from (select upper(btrim(i.codigo_articulo)) as c, trim_scale(coalesce(i.cantidad, 0))::text as q
            from isis_lk.documento_items i
           where p_empresa = 'lk' and i.documento_id = p_doc_id and nullif(btrim(i.codigo_articulo), '') is not null
          union all
          select upper(btrim(i.codigo_articulo)), trim_scale(coalesce(i.cantidad, 0))::text
            from isis_ch.documento_items i
           where p_empresa = 'chef' and i.documento_id = p_doc_id and nullif(btrim(i.codigo_articulo), '') is not null) z
$f$;
revoke all on function public.gv_isis_doc_firma(text, bigint) from public, anon, authenticated;

create or replace function public.gv_fc_nc_aparear(p_dias integer default 45)
returns integer language plpgsql security definer set search_path = public as $f$
-- v30.96: la NC de anulación anula la ÚLTIMA FC viva con su misma firma (cliente + total +
-- artículos × cantidades) emitida antes que ella. Ver sql/gv_fc_anulada_nc_v3096.sql.
declare r record; v_fc bigint; v_hora boolean; n integer := 0;
begin
  if not pg_try_advisory_xact_lock(90902) then return -2; end if;
  drop table if exists _gv_an_nc;
  create temp table _gv_an_nc as
    select 'lk'::text as e, d.id, d.fecha, d.created_at, d.comprobante_id, canon_cod(d.contraparte_codigo) as cc, d.total
      from isis_lk.documentos d
     where d.familia = 'nc_venta' and d.contraparte_codigo is not null and d.total > 0
       and d.fecha >= current_date - greatest(p_dias, 0)
       and not exists (select 1 from public."GV_FC_Anulada" a where a.empresa = 'lk' and a.nc_id = d.id)
    union all
    select 'chef'::text, d.id, d.fecha, d.created_at, d.comprobante_id, canon_cod(d.contraparte_codigo), d.total
      from isis_ch.documentos d
     where d.familia = 'nc_venta' and d.contraparte_codigo is not null and d.total > 0
       and d.fecha >= current_date - greatest(p_dias, 0)
       and not exists (select 1 from public."GV_FC_Anulada" a where a.empresa = 'chef' and a.nc_id = d.id);

  -- FC candidatas: mismo cliente y mismo total que alguna NC sin aparear, hasta 90 días antes.
  drop table if exists _gv_an_fc;
  create temp table _gv_an_fc as
    select f.*, false as usada from (
      select 'lk'::text as e, d.id, d.fecha, d.created_at, d.comprobante_id, canon_cod(d.contraparte_codigo) as cc, d.total, d.total_cajas
        from isis_lk.documentos d
       where d.familia = 'factura_venta' and d.contraparte_codigo is not null
         and d.fecha >= current_date - greatest(p_dias, 0) - 90
         and not exists (select 1 from public."GV_FC_Anulada" a where a.empresa = 'lk' and a.fc_id = d.id)
      union all
      select 'chef'::text, d.id, d.fecha, d.created_at, d.comprobante_id, canon_cod(d.contraparte_codigo), d.total, d.total_cajas
        from isis_ch.documentos d
       where d.familia = 'factura_venta' and d.contraparte_codigo is not null
         and d.fecha >= current_date - greatest(p_dias, 0) - 90
         and not exists (select 1 from public."GV_FC_Anulada" a where a.empresa = 'chef' and a.fc_id = d.id)
    ) f
    where exists (select 1 from _gv_an_nc n where n.e = f.e and n.cc = f.cc and n.total = f.total
                    and f.fecha between n.fecha - 90 and n.fecha);

  alter table _gv_an_nc add column firma text;
  alter table _gv_an_fc add column firma text;
  -- sólo hace falta la firma de las NC que tienen alguna FC con su mismo cliente y total
  update _gv_an_nc n set firma = public.gv_isis_doc_firma(n.e, n.id)
   where exists (select 1 from _gv_an_fc f where f.e = n.e and f.cc = n.cc and f.total = n.total);
  update _gv_an_fc f set firma = public.gv_isis_doc_firma(f.e, f.id);

  for r in select * from _gv_an_nc where firma is not null order by fecha, created_at, id loop
    v_hora := true;
    select f.id into v_fc from _gv_an_fc f
     where not f.usada and f.e = r.e and f.cc = r.cc and f.total = r.total and f.firma = r.firma
       and f.fecha between r.fecha - 90 and r.fecha
       and f.created_at <= r.created_at + interval '3 minutes'
     order by f.fecha desc, f.comprobante_id desc limit 1;
    if v_fc is null then
      v_hora := false;
      select f.id into v_fc from _gv_an_fc f
       where not f.usada and f.e = r.e and f.cc = r.cc and f.total = r.total and f.firma = r.firma
         and f.fecha between r.fecha - 90 and r.fecha
       order by f.fecha desc, f.comprobante_id desc limit 1;
    end if;
    if v_fc is not null then
      insert into public."GV_FC_Anulada" (empresa, fc_id, nc_id, fc_comprobante, nc_comprobante, cliente, total, cajas,
                                          fc_fecha, nc_fecha, firma, por_hora)
      select r.e, f.id, r.id, f.comprobante_id, r.comprobante_id, r.cc, r.total, f.total_cajas, f.fecha, r.fecha, r.firma, v_hora
        from _gv_an_fc f where f.e = r.e and f.id = v_fc
      on conflict do nothing;
      update _gv_an_fc set usada = true where e = r.e and id = v_fc;
      n := n + 1;
    end if;
  end loop;
  drop table if exists _gv_an_nc;
  drop table if exists _gv_an_fc;
  return n;
end $f$;
revoke all on function public.gv_fc_nc_aparear(integer) from public, anon, authenticated;

-- Para la Conciliación: las FC anuladas que correspondían a cada NP. Con FC viva asignada, las
-- anuladas con SU MISMA firma (la refacturación); sin FC viva, las anuladas del cliente en la
-- ventana del cruce con las cajas dentro de la tolerancia (facturada y anulada sin refacturar).
create or replace function public.gv_fc_anuladas_np(p_nps text[])
returns table (np text, fc_comprobante text, nc_comprobante text, fc_fecha date, total numeric, tiene_viva boolean)
language sql stable security definer set search_path = public as $f$
  with b as (
    select f.np, gv_empresa_de_np_texto(f.np) as e, canon_cod(f.cod_cliente) as cc,
           least(f.fecha_salida, (f.facturado_at at time zone 'America/Argentina/Buenos_Aires')::date) - 3 as d0,
           greatest(f.fecha_salida, (f.facturado_at at time zone 'America/Argentina/Buenos_Aires')::date) + 3 as d1,
           a.doc_id, s.cajas_ent
      from public."Facturacion_NP" f
      left join public."GV_Cruce_FC_Asig" a on a.np = f.np
      left join public."GV_Conciliacion_Facturacion" s on s.np = f.np
     where f.np = any (coalesce(p_nps, '{}'::text[]))
  ), b2 as (
    select b.*, case when b.doc_id is not null then public.gv_isis_doc_firma(b.e, b.doc_id) end as firma_viva
      from b
  )
  select b2.np, x.fc_comprobante, x.nc_comprobante, x.fc_fecha, x.total, (b2.doc_id is not null)
    from b2
    join public."GV_FC_Anulada" x on x.empresa = b2.e and x.cliente = b2.cc
                                 and x.fc_fecha between coalesce(b2.d0, x.fc_fecha) and coalesce(b2.d1, x.fc_fecha)
   where (b2.doc_id is not null and x.firma = b2.firma_viva)
      or (b2.doc_id is null and (b2.cajas_ent is null
                                 or abs(coalesce(x.cajas, -1) - b2.cajas_ent) <= greatest(1::numeric, b2.cajas_ent * 0.15)))
   order by b2.np, x.fc_comprobante
$f$;
revoke all on function public.gv_fc_anuladas_np(text[]) from public, anon;
grant execute on function public.gv_fc_anuladas_np(text[]) to authenticated;

-- PENDIENTE (esperando el «sí» de Luis: son objetos con regla protegida en GV_Reglas_Centinela):
-- gv_cruce_fc_asignacion / gv_fac_complemento_cruce + not exists GV_FC_Anulada en docs, y
-- gv_cruce_fc_asig_refrescar llamando a gv_fc_nc_aparear() antes de asignar. Hasta entonces el
-- cruce sigue pudiendo asignar una FC anulada; la Conciliación ya muestra el chip.
