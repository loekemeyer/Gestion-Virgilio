-- v22.53 (Luis, 2026-09-25) — FACTURACIÓN · «Recuperar pedido»: completar la facturación de una NP
-- ya facturada cuando entra mercadería entre la factura y la entrega al cliente.
--
--   GV_Fac_Complemento      una fila por código facturado de más (lote = una acción del admin).
--                           modo 'marcado' = ya lo facturó a mano en ISIS · 'excel' = bajó el Excel.
--   GV_Fac_Complemento_Doc  el lote ↔ la factura de ISIS que lo cubre (la encuentra el cruce).
--
--   gv_fac_recuperar_lista(p_dias)     NP facturadas con lo que les faltó al facturar.
--   gv_fac_recuperar_detalle(p_np)     por código: pedidas, facturadas, faltó, completado
--                                      físicamente después (CP), ya complementado, pendiente.
--   gv_fac_complemento_registrar(...)  graba el lote (tope: lo que faltó al facturar).
--   gv_fac_complemento_cruce()         busca la factura de ISIS de cada lote sin factura.
--   gv_fac_complemento_lista(p_np)     lotes con su estado de factura (Conciliación).
--
-- «Lo que faltó al facturar» se reconstruye: Completar Pedido (cp_reducir_faltante_cap) SUMA a
-- cajas_entregadas y RESTA de cajas_falto, así que lo que CP agregó DESPUÉS de facturado_at
-- (Movimientos_Stock tipo 'cp' a a_facturar, ref = NP) se descuenta para volver al estado original.
-- Todas las RPC son SECURITY DEFINER con chequeo de supervisor adentro; las tablas nacen cerradas.

create table if not exists public."GV_Fac_Complemento" (
  id          bigserial primary key,
  lote        uuid not null,
  empresa     text not null,
  np          text not null,
  cod_cliente text,
  cod_art     text not null,
  cajas       numeric not null check (cajas > 0),
  modo        text not null check (modo in ('marcado','excel')),
  creado_por  text,
  creado_at   timestamptz not null default now(),
  anulado_at  timestamptz,
  anulado_por text
);
create index if not exists gv_fac_complemento_np_idx on public."GV_Fac_Complemento" (np);
create index if not exists gv_fac_complemento_lote_idx on public."GV_Fac_Complemento" (lote);
alter table public."GV_Fac_Complemento" enable row level security;
revoke all on public."GV_Fac_Complemento" from anon, authenticated;

create table if not exists public."GV_Fac_Complemento_Doc" (
  lote           uuid primary key,
  empresa        text not null,
  doc_id         bigint not null,
  candidatos     integer,
  actualizado_at timestamptz not null default now()
);
alter table public."GV_Fac_Complemento_Doc" enable row level security;
revoke all on public."GV_Fac_Complemento_Doc" from anon, authenticated;

-- ── detalle por código ─────────────────────────────────────────────────────────────────
create or replace function public.gv_fac_recuperar_detalle(p_np text)
returns table(cod_art text, descripcion text, pedidas numeric, entregadas_al_fc numeric,
              falto_al_fc numeric, completado_despues numeric, complementado numeric,
              pendiente numeric, sugerido numeric)
language sql stable security definer
set search_path to 'public'
as $$
  with f as (
    select f.np, f.facturado_at from public."Facturacion_NP" f
     where btrim(f.np) = btrim(p_np)
       and (public.es_supervisor_virgilio() or public.gv_es_supervisor_o_servicio())
  ),
  e as (   -- la última fila viva por (np, código): mismo criterio que el Excel ISIS
    select distinct on (btrim(ev.cod_art)) btrim(ev.cod_art) as cod_art,
           coalesce(ev.cajas_pedidas,0) as ped, coalesce(ev.cajas_entregadas,0) as ent
      from public."Entregas_Virgilio" ev join f on btrim(ev.np) = f.np
     where coalesce(ev.tanda,'') !~ '-X$'
     order by btrim(ev.cod_art), ev.id desc
  ),
  cp as (   -- lo que Completar Pedido le sumó DESPUÉS de facturar
    select canon_cod(regexp_replace(upper(btrim(m.cod_art)), '([0-9E])L$', '\1')) as k, sum(m.delta) as c
      from public."Movimientos_Stock" m join f on split_part(m.ref,'|',1) = f.np
     where m.tipo = 'cp' and m.deposito = 'a_facturar' and m.delta > 0 and m.creado > f.facturado_at
     group by 1
  ),
  co as (
    select canon_cod(regexp_replace(upper(btrim(c.cod_art)), '([0-9E])L$', '\1')) as k, sum(c.cajas) as c
      from public."GV_Fac_Complemento" c join f on c.np = f.np
     where c.anulado_at is null group by 1
  ),
  x as (
    select e.cod_art, e.ped,
           canon_cod(regexp_replace(upper(e.cod_art), '([0-9E])L$', '\1')) as k,
           e.ent - least(coalesce(cp.c,0), e.ent) as ent_fc,
           coalesce(cp.c,0) as cpd, coalesce(co.c,0) as comp
      from e
      left join cp on cp.k = canon_cod(regexp_replace(upper(e.cod_art), '([0-9E])L$', '\1'))
      left join co on co.k = canon_cod(regexp_replace(upper(e.cod_art), '([0-9E])L$', '\1'))
  )
  select x.cod_art,
         (select n.descripcion from public.vista_nombres_articulos n
           where canon_cod(n.cod) = x.k limit 1),
         x.ped, x.ent_fc,
         greatest(0, x.ped - x.ent_fc),
         x.cpd, x.comp,
         greatest(0, greatest(0, x.ped - x.ent_fc) - x.comp),
         least(greatest(0, greatest(0, x.ped - x.ent_fc) - x.comp), greatest(0, x.cpd - x.comp))
    from x
   order by x.cod_art;
$$;

-- ── lista de NP facturadas ─────────────────────────────────────────────────────────────
create or replace function public.gv_fac_recuperar_lista(p_dias integer default 90)
returns table(np text, empresa text, tanda text, cod_cliente text, razon_social text,
              fecha_salida date, facturado_at timestamptz, lineas integer, cajas_fc numeric,
              lineas_falto integer, cajas_falto numeric, cajas_completadas_despues numeric,
              cajas_complementadas numeric, lotes integer, lotes_sin_factura integer)
language sql stable security definer
set search_path to 'public'
as $$
  with f as (
    select f.* from public."Facturacion_NP" f
     where f.facturado_at >= now() - make_interval(days => greatest(1, coalesce(p_dias, 90)))
       and (public.es_supervisor_virgilio() or public.gv_es_supervisor_o_servicio())
  ),
  e as (
    select distinct on (btrim(ev.np), btrim(ev.cod_art)) btrim(ev.np) as np, btrim(ev.cod_art) as cod_art,
           canon_cod(regexp_replace(upper(btrim(ev.cod_art)), '([0-9E])L$', '\1')) as k,
           coalesce(ev.cajas_pedidas,0) as ped, coalesce(ev.cajas_entregadas,0) as ent
      from public."Entregas_Virgilio" ev
     where btrim(ev.np) in (select f.np from f) and coalesce(ev.tanda,'') !~ '-X$'
     order by btrim(ev.np), btrim(ev.cod_art), ev.id desc
  ),
  cp as (
    select f.np, canon_cod(regexp_replace(upper(btrim(m.cod_art)), '([0-9E])L$', '\1')) as k, sum(m.delta) as c
      from public."Movimientos_Stock" m join f on split_part(m.ref,'|',1) = f.np
     where m.tipo = 'cp' and m.deposito = 'a_facturar' and m.delta > 0 and m.creado > f.facturado_at
     group by 1, 2
  ),
  x as (
    select e.np, e.ped, e.ent - least(coalesce(cp.c,0), e.ent) as ent_fc, coalesce(cp.c,0) as cpd
      from e left join cp on cp.np = e.np and cp.k = e.k
  ),
  agg as (
    select x.np, count(*)::int as lineas, sum(x.ent_fc) as cajas_fc,
           count(*) filter (where x.ped > x.ent_fc)::int as lineas_falto,
           sum(greatest(0, x.ped - x.ent_fc)) as cajas_falto, sum(x.cpd) as cpd
      from x group by 1
  ),
  co as (
    select c.np, sum(c.cajas) as cajas, count(distinct c.lote)::int as lotes,
           count(distinct c.lote) filter (where d.lote is null)::int as sin_fc
      from public."GV_Fac_Complemento" c
      left join public."GV_Fac_Complemento_Doc" d on d.lote = c.lote
     where c.anulado_at is null group by 1
  )
  select f.np, public.gv_empresa_de_np_texto(f.np), f.tanda, f.cod_cliente, f.razon_social,
         f.fecha_salida, f.facturado_at,
         coalesce(a.lineas,0), coalesce(a.cajas_fc,0), coalesce(a.lineas_falto,0),
         coalesce(a.cajas_falto,0), coalesce(a.cpd,0), coalesce(co.cajas,0),
         coalesce(co.lotes,0), coalesce(co.sin_fc,0)
    from f left join agg a on a.np = f.np left join co on co.np = f.np
   order by f.facturado_at desc;
$$;

-- ── grabar un lote ─────────────────────────────────────────────────────────────────────
create or replace function public.gv_fac_complemento_registrar(p_np text, p_items jsonb, p_modo text, p_por text)
returns uuid
language plpgsql security definer
set search_path to 'public'
as $$
declare
  v_lote uuid := gen_random_uuid();
  v_f record;
  r record;
  v_pend numeric;
  n int := 0;
begin
  if not (public.es_supervisor_virgilio() or public.gv_es_supervisor_o_servicio()) then
    raise exception 'Sólo un supervisor puede completar la facturación de un pedido';
  end if;
  if p_modo not in ('marcado','excel') then raise exception 'modo inválido: %', p_modo; end if;
  select * into v_f from public."Facturacion_NP" where btrim(np) = btrim(p_np);
  if not found then raise exception 'La NP % no está facturada: se factura desde el Facturador', p_np; end if;

  for r in
    select btrim(x->>'cod') as cod, (x->>'cajas')::numeric as cajas
      from jsonb_array_elements(coalesce(p_items,'[]'::jsonb)) x
     where coalesce((x->>'cajas')::numeric, 0) > 0
  loop
    select d.pendiente into v_pend from public.gv_fac_recuperar_detalle(v_f.np) d where d.cod_art = r.cod;
    if v_pend is null then raise exception 'El código % no está en la NP %', r.cod, v_f.np; end if;
    if r.cajas > v_pend then
      raise exception 'El código % tiene % cajas pendientes de facturar y se marcaron %', r.cod, v_pend, r.cajas;
    end if;
    insert into public."GV_Fac_Complemento"(lote, empresa, np, cod_cliente, cod_art, cajas, modo, creado_por)
    values (v_lote, public.gv_empresa_de_np_texto(v_f.np), v_f.np, v_f.cod_cliente, r.cod, r.cajas, p_modo, p_por);
    n := n + 1;
  end loop;
  if n = 0 then raise exception 'No se marcó ningún código con cajas'; end if;
  return v_lote;
end $$;

-- ── cruce: la factura de ISIS de cada lote ─────────────────────────────────────────────
create or replace function public.gv_fac_complemento_cruce()
returns integer
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $$
declare r record; n int := 0;
begin
  drop table if exists _gv_fcl;
  create temp table _gv_fcl as
    select c.lote, min(c.empresa) as empresa, min(c.np) as np, canon_cod(min(c.cod_cliente)) as cc,
           (min(c.creado_at) at time zone 'America/Argentina/Buenos_Aires')::date as fecha,
           sum(c.cajas) as cajas,
           array_agg(distinct canon_cod(regexp_replace(upper(btrim(c.cod_art)), '([0-9E])L$', '\1'))) as cods
      from public."GV_Fac_Complemento" c
     where c.anulado_at is null
       and not exists (select 1 from public."GV_Fac_Complemento_Doc" d where d.lote = c.lote)
     group by c.lote;

  drop table if exists _gv_fcl_par;
  create temp table _gv_fcl_par as
    with docs as (
      select 'lk'::text as empresa, d.id, d.fecha, coalesce(d.total_cajas,-1::numeric) as cajas, canon_cod(d.contraparte_codigo) as cc
        from isis_lk.documentos d where d.familia = 'factura_venta' and d.contraparte_codigo is not null
      union all
      select 'chef', d.id, d.fecha, coalesce(d.total_cajas,-1::numeric), canon_cod(d.contraparte_codigo)
        from isis_ch.documentos d where d.familia = 'factura_venta' and d.contraparte_codigo is not null
    )
    select l.lote, d.empresa, d.id as doc_id, abs(d.cajas - l.cajas) as dcajas, abs(d.fecha - l.fecha) as dfecha
      from _gv_fcl l
      join docs d on d.empresa = l.empresa and d.cc = l.cc
                 -- 'marcado' = ya facturado ANTES en ISIS: la ventana mira hacia atrás también
                 and d.fecha between l.fecha - 10 and l.fecha + 10
     where abs(d.cajas - l.cajas) <= greatest(1::numeric, l.cajas * 0.15)
       and not exists (select 1 from public."GV_Cruce_FC_Asig" a where a.doc_id = d.id)
       and not exists (select 1 from public."GV_Fac_Complemento_Doc" x where x.doc_id = d.id and x.empresa = d.empresa)
       -- todos los códigos del lote tienen que estar en la factura
       and not exists (
         select 1 from unnest(l.cods) k
          where not exists (
            select 1 from isis_lk.documento_items di
             where d.empresa = 'lk' and di.documento_id = d.id
               and canon_cod(regexp_replace(upper(btrim(di.codigo_articulo)), '([0-9E])L$', '\1')) = k)
            and not exists (
            select 1 from isis_ch.documento_items di
             where d.empresa = 'chef' and di.documento_id = d.id
               and canon_cod(regexp_replace(upper(btrim(di.codigo_articulo)), '([0-9E])L$', '\1')) = k));

  for r in select p.lote, p.empresa, p.doc_id,
                  (select count(*) from _gv_fcl_par q where q.lote = p.lote)::int as cand
             from _gv_fcl_par p order by p.dcajas, p.dfecha, p.lote, p.doc_id
  loop
    if not exists (select 1 from public."GV_Fac_Complemento_Doc" x where x.lote = r.lote)
       and not exists (select 1 from public."GV_Fac_Complemento_Doc" x where x.doc_id = r.doc_id and x.empresa = r.empresa) then
      insert into public."GV_Fac_Complemento_Doc"(lote, empresa, doc_id, candidatos) values (r.lote, r.empresa, r.doc_id, r.cand);
      n := n + 1;
    end if;
  end loop;
  return n;
end $$;
revoke all on function public.gv_fac_complemento_cruce() from public, anon, authenticated;

-- ── lotes con su estado (para Recuperar y Conciliación) ─────────────────────────────────
create or replace function public.gv_fac_complemento_lista(p_np text default null)
returns table(lote uuid, np text, empresa text, cod_cliente text, modo text, creado_por text,
              creado_at timestamptz, lineas integer, cajas numeric, items jsonb,
              doc_id bigint, factura text, factura_fecha date, factura_cajas numeric)
language sql stable security definer
set search_path to 'public'
as $$
  select c.lote, min(c.np), min(c.empresa), min(c.cod_cliente), min(c.modo), min(c.creado_por),
         min(c.creado_at), count(*)::int, sum(c.cajas),
         jsonb_agg(jsonb_build_object('cod', c.cod_art, 'cajas', c.cajas) order by c.cod_art),
         min(d.doc_id),
         min(coalesce(dl.tipo, dc.tipo) || ' ' || coalesce(dl.punto_venta, dc.punto_venta) || '-' || coalesce(dl.numero, dc.numero)),
         min(coalesce(dl.fecha, dc.fecha)), min(coalesce(dl.total_cajas, dc.total_cajas))
    from public."GV_Fac_Complemento" c
    left join public."GV_Fac_Complemento_Doc" d on d.lote = c.lote
    left join isis_lk.documentos dl on d.empresa = 'lk'   and dl.id = d.doc_id
    left join isis_ch.documentos dc on d.empresa = 'chef' and dc.id = d.doc_id
   where c.anulado_at is null
     and (p_np is null or c.np = btrim(p_np))
     and (public.es_supervisor_virgilio() or public.gv_es_supervisor_o_servicio())
   group by c.lote
   order by min(c.creado_at) desc;
$$;

revoke all on function public.gv_fac_recuperar_detalle(text) from public, anon;
revoke all on function public.gv_fac_recuperar_lista(integer) from public, anon;
revoke all on function public.gv_fac_complemento_registrar(text, jsonb, text, text) from public, anon;
revoke all on function public.gv_fac_complemento_lista(text) from public, anon;
grant execute on function public.gv_fac_recuperar_detalle(text) to authenticated, service_role;
grant execute on function public.gv_fac_recuperar_lista(integer) to authenticated, service_role;
grant execute on function public.gv_fac_complemento_registrar(text, jsonb, text, text) to authenticated, service_role;
grant execute on function public.gv_fac_complemento_lista(text) to authenticated, service_role;
grant execute on function public.gv_fac_complemento_cruce() to service_role;

-- ── el cruce principal (una NP ↔ una factura) se entera de los complementos ─────────────
--   1) la factura de un complemento NO es candidata para la NP (es de las cajas de más);
--   2) las cajas que Completar Pedido sumó DESPUÉS de facturar no estaban en la factura
--      original: se descuentan del cajas_ent contra el que se compara (±15 %). Va en un CTE
--      (_gv_cpp), NO en un subselect por NP: así fue el primer intento y pasó de 1,6 s a > 60 s.
--   3) el refresco del cruce (cron 90) corre también el cruce de complementos.
-- Medido en transacción abortada: 1.600 ms (antes ~1.600-1.900) y 0 asignaciones distintas del cache.
do $$
declare v text; v2 text;
begin
  v := pg_get_functiondef('public.gv_cruce_fc_asignacion()'::regprocedure);
  if v !~ '_gv_cpp' then
    v2 := replace(v, '  with base as (',
        '  -- v22.52-compl: lo que Completar Pedido sumo DESPUES de facturar no esta en la factura original' || chr(10) ||
        '  with _gv_cpp as (' || chr(10) ||
        '    select f2.np, sum(m.delta) as c' || chr(10) ||
        '      from public."Movimientos_Stock" m' || chr(10) ||
        '      join public."Facturacion_NP" f2 on f2.np = split_part(m.ref, ''|'', 1)' || chr(10) ||
        '     where m.tipo = ''cp'' and m.deposito = ''a_facturar'' and m.delta > 0 and m.creado > f2.facturado_at' || chr(10) ||
        '     group by f2.np' || chr(10) ||
        '  ), base as (');
    v2 := replace(v2, '           coalesce(n.cajas_ent, 0::numeric) as cajas_ent,',
        '           greatest(0::numeric, coalesce(n.cajas_ent, 0::numeric) - coalesce(_gv_c.c, 0::numeric)) as cajas_ent,');
    v2 := replace(v2, '      left join public.gv_vista_facturacion_neto n on n.np = f.np' || chr(10) || '  ), docs as (',
        '      left join public.gv_vista_facturacion_neto n on n.np = f.np' || chr(10) ||
        '      left join _gv_cpp _gv_c on _gv_c.np = f.np' || chr(10) || '  ), docs as (');
    v2 := replace(v2, '       and d.contraparte_codigo is not null' || chr(10) || '    union all',
        '       and d.contraparte_codigo is not null' || chr(10) ||
        '       and not exists (select 1 from public."GV_Fac_Complemento_Doc" _gv_x where _gv_x.empresa = ''lk'' and _gv_x.doc_id = d.id)' || chr(10) || '    union all');
    v2 := replace(v2, '       and d.contraparte_codigo is not null' || chr(10) || '  )',
        '       and d.contraparte_codigo is not null' || chr(10) ||
        '       and not exists (select 1 from public."GV_Fac_Complemento_Doc" _gv_x where _gv_x.empresa = ''chef'' and _gv_x.doc_id = d.id)' || chr(10) || '  )');
    if (length(v2) - length(replace(v2, 'GV_Fac_Complemento_Doc', ''))) / 22 <> 2
       or (length(v2) - length(replace(v2, '_gv_cpp', ''))) / 7 <> 2 or v2 !~ '_gv_c\.c' then
      raise exception 'gv_cruce_fc_asignacion: el texto no matchea, no se aplica';
    end if;
    execute v2;
  end if;

  v := pg_get_functiondef('public.gv_cruce_fc_asig_refrescar()'::regprocedure);
  if v !~ 'gv_fac_complemento_cruce' then
    v2 := replace(v,
      '  drop table if exists _gv_asig_new;' || chr(10) || '  return v_cambios;',
      '  -- v22.52: las facturas complementarias (Recuperar pedido). Nunca tumba el refresco.' || chr(10) ||
      '  begin perform public.gv_fac_complemento_cruce(); exception when others then null; end;' || chr(10) ||
      '  drop table if exists _gv_asig_new;' || chr(10) || '  return v_cambios;');
    if v2 = v then raise exception 'gv_cruce_fc_asig_refrescar: el texto no matchea'; end if;
    execute v2;
  end if;
end $$;

-- Centinelas: PENDIENTE del "sí" de Luis (es un INSERT)
-- insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version) values
--  ('gv_cruce_fc_asignacion','funcion','GV_Fac_Complemento_Doc','la factura de un complemento (Recuperar pedido) no es candidata para la NP','Luis','v22.53'),
--  ('gv_cruce_fc_asig_refrescar','funcion','gv_fac_complemento_cruce','el refresco del cruce busca tambien las facturas complementarias','Luis','v22.53');

-- Rollback: drop de las 5 funciones gv_fac_* y las 2 tablas GV_Fac_Complemento*, y en
-- gv_cruce_fc_asignacion / gv_cruce_fc_asig_refrescar deshacer los replace de arriba
-- (definición previa: sql/gv_cruce_fc_asignacion_v2223.sql + v22.28 del refrescar).
