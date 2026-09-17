-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- ROLLBACK de la v19.34 («✕ Cancelar pedido» en la fila de la NP).
-- Deja la base como estaba el 2026-09-17 antes del cambio. Correrlo ENTERO.
-- ═══════════════════════════════════════════════════════════════════════════════════════════

-- 1) el pase (a0c) del armador: se saca con el replace inverso
do $do$
declare d text; bloque text; i int; j int;
begin
  d := pg_get_functiondef('public.gv_ppp_web_armar_pendientes(text,date,jsonb,jsonb)'::regprocedure);
  i := position('  -- (a0c) v19.34' in d);
  if i = 0 then raise notice 'el pase (a0c) no esta'; return; end if;
  j := position('  -- (a) forzados con fecha' in d);
  if j <= i then raise exception 'no encuentro el final del bloque (a0c)'; end if;
  execute left(d, i - 1) || substr(d, j);
end $do$;

-- 2) volver a la firma de 5 argumentos de gv_ppp_np_desarmar (la de la v18.94)
drop function if exists public.gv_ppp_np_desarmar(text,text,text,boolean,boolean,boolean,boolean);

create or replace function public.gv_ppp_np_desarmar(p_np text, p_justificativo text, p_por text default null,
                                                     p_vuelve boolean default false, p_a_guardar boolean default false)
 returns table(np text, es_isis boolean, tanda text, arts integer, cajas numeric, detalle text)
 language plpgsql security definer set search_path to 'public', 'pg_temp'
as $function$
#variable_conflict use_column
declare
  v_np   text := regexp_replace(btrim(p_np), '\.0+$', '');
  v_just text := btrim(coalesce(p_justificativo, ''));
  v_vuelve boolean := coalesce(p_vuelve, false);
  v_ag   boolean := coalesce(p_a_guardar, false);   -- v18.88: todo a «A guardar»
  v_isis boolean; v_emp text; v_num int; v_oid bigint;
  v_tanda text; v_fe date; v_cod text; v_rs text; v_m3 numeric;
  v_items jsonb; v_dev jsonb; v_arts int := 0; v_cajas numeric := 0; v_n int;
  v_term numeric := 0; v_exc numeric := 0; v_guard numeric := 0;
begin
  if not (es_supervisor_virgilio() or gv_es_supervisor_o_servicio()) then
    raise exception 'Solo un supervisor puede desarmar un pedido.' using errcode='42501';
  end if;
  if length(v_just) < 10 then
    raise exception 'Falta el justificativo del desarme (al menos 10 caracteres): queda guardado con el registro.';
  end if;

  v_isis := v_np !~* '^(LK|CH)\s*\d+';

  if exists (select 1 from public."Registros_Produccion_Virgilio" r
              where r.opcion in ('CCN','CRN')
                and regexp_replace(upper(btrim(split_part(r.texto,'|',1))), '\.0+$','') = upper(v_np)
                and not public.es_legajo_test(r.legajo)) then
    raise exception 'La NP % ya tiene Carga Camion o Recepcion Remitos: salio. Eso se cierra con el remito, no se desarma.', v_np;
  end if;

  if v_isis then
    select regexp_replace(btrim(p.tanda),'\s+$',''), nullif(left(btrim(p.fecha_entrega),10),'')::date,
           btrim(p.cod), btrim(p.razon_social), p.m3
      into v_tanda, v_fe, v_cod, v_rs, v_m3
      from public.gv_ppp_programacion_diaria p
     where regexp_replace(btrim(p.np), '\.0+$','') = v_np limit 1;
  else
    v_emp := case when upper(left(v_np,2)) = 'CH' then 'chef' else 'lk' end;
    v_num := (regexp_match(v_np, '(\d+)'))[1]::int;
    select n.order_id into v_oid from public."PPP_Web_NP" n where n.empresa = v_emp and n.np = v_num limit 1;
    select btrim(w.tanda), w.fecha_entrega, btrim(w.cod_cliente), btrim(w.razon_social), w.m3
      into v_tanda, v_fe, v_cod, v_rs, v_m3
      from public."PPP_Web_Programacion" w
     where w.empresa = v_emp and w.np = v_num limit 1;
  end if;
  if v_tanda is null then
    raise exception 'No encuentro la NP % en la programacion.', v_np;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object('art', i.art, 'cajas', i.cajas, 'uxb', i.uxb, 'uni', i.uni)
                            order by i.art), '[]'::jsonb)
    into v_items from public.gv_ppp_np_items i where i.np = v_np;

  drop table if exists _gv_dev;
  create temp table _gv_dev on commit drop as
  with ped as (
    select public.canon_cod(i.art) ck, sum(i.cajas)::numeric cajas
      from public.gv_ppp_np_items i where i.np = v_np group by 1
  ), sal as (
    select public.canon_cod(m.cod_art) ck,
           (array_agg(m.cod_art order by length(m.cod_art)))[1] cod_art,
           (array_agg(m.empresa) filter (where m.empresa is not null))[1] empresa,
           coalesce(sum(m.delta) filter (where m.deposito = 'a_facturar'), 0)      fact,
           coalesce(sum(m.delta) filter (where m.deposito = 'separar_pedidos'), 0) sep,
           coalesce(-sum(m.delta) filter (where m.tipo = 'picking' and m.deposito = 'terminado' and m.delta < 0), 0) org_term,
           coalesce(-sum(m.delta) filter (where m.tipo = 'picking' and m.deposito = 'excedente' and m.delta < 0), 0) org_exc
      from public."Movimientos_Stock" m
     where upper(btrim(m.ref)) = upper(btrim(v_tanda))
     group by 1
  ), dev as (
    select public.canon_cod(m.cod_art) ck,
           coalesce(sum(m.delta) filter (where m.deposito = 'terminado'), 0) t,
           coalesce(sum(m.delta) filter (where m.deposito = 'excedente'), 0) e
      from public."Movimientos_Stock" m
     where m.tipo = 'desarme' and m.delta > 0
       and m.descripcion like '%(tanda ' || v_tanda || ')%'
     group by 1
  ), c as (
    select s.cod_art, s.empresa, s.fact, s.sep,
           greatest(s.org_term - coalesce(dv.t, 0), 0) as org_term,
           greatest(s.org_exc  - coalesce(dv.e, 0), 0) as org_exc,
           least(p.cajas, greatest(s.fact, 0) + greatest(s.sep, 0)) as total
      from ped p
      join sal s on s.ck = p.ck
      left join dev dv on dv.ck = p.ck
  )
  select c.cod_art, c.empresa, c.org_term, c.org_exc, c.total,
         least(c.total, greatest(c.fact, 0))           as de_fact,
         c.total - least(c.total, greatest(c.fact, 0)) as de_sep,
         0::numeric as a_term,
         0::numeric as a_exc,
         c.total as a_guardar
    from c where c.total > 0;

  insert into public."Movimientos_Stock" (ts, cod_art, descripcion, deposito, delta, tipo, ref, legajo, empresa)
  select now(), d.cod_art,
         case when v_ag and not v_vuelve then 'Cancelacion del pedido ' else 'Desarme del pedido ' end
           || v_np || ' (tanda ' || v_tanda || '): ' || v_just,
         x.dep, x.signo * x.cant, 'desarme', v_np, nullif(btrim(p_por), ''), d.empresa
    from _gv_dev d
    cross join lateral (values
      ('a_facturar',      -1, d.de_fact),
      ('separar_pedidos', -1, d.de_sep),
      ('terminado',        1, d.a_term),
      ('excedente',        1, d.a_exc),
      ('a_guardar',        1, d.a_guardar)
    ) as x(dep, signo, cant)
   where x.cant > 0;

  select coalesce(jsonb_agg(jsonb_build_object('art', d.cod_art, 'empresa', d.empresa,
                              'de_a_facturar', d.de_fact, 'de_separar', d.de_sep,
                              'a_gondola', d.a_term, 'a_excedente', d.a_exc, 'a_guardar', d.a_guardar,
                              'total', d.total,
                              'salio_de_terminado', d.org_term, 'salio_de_excedente', d.org_exc)
                            order by d.cod_art), '[]'::jsonb),
         count(*), coalesce(sum(d.total), 0),
         coalesce(sum(d.a_term), 0), coalesce(sum(d.a_exc), 0), coalesce(sum(d.a_guardar), 0)
    into v_dev, v_arts, v_cajas, v_term, v_exc, v_guard
    from _gv_dev d;

  if v_isis then
    if v_vuelve then
      perform public.gv_ppp_isis_desprogramar(array[v_np], 'desarmado: ' || v_just, p_por);
    else
      insert into public."NP_Canceladas" (np, motivo, legajo)
      values (v_np, case when v_ag then 'cancelado: ' else 'desarmado: ' end || v_just,
              coalesce(nullif(btrim(p_por),''), 'supervisor'))
      on conflict (np) do update set motivo = excluded.motivo, legajo = excluded.legajo;
      insert into public."GV_PPP_Prog_Override" (np, oculto, nota)
      values (v_np, true, 'v17.90 ' || to_char(now() at time zone 'America/Argentina/Buenos_Aires','YYYY-MM-DD HH24:MI')
                          || case when v_ag then ' · CANCELADO (' else ' · DESARMADO (' end
                          || v_arts || ' art / ' || v_cajas || ' cajas): ' || v_just
                          || coalesce(' · por ' || nullif(btrim(p_por),''), ''))
      on conflict (np) do update set oculto = true, nota = excluded.nota;
    end if;
  else
    if v_vuelve then
      delete from public."GV_Web_Cancelados" c where c.empresa = v_emp and c.order_id = v_oid;
      insert into public."GV_PPP_Web_Retenido" as t
        (empresa, order_id, np_idx, np, tanda_previa, fecha_previa, ya_pickeada, ya_armada, motivo, por)
      select w.empresa, w.order_id, w.np_idx, w.np,
             nullif(btrim(w.tanda), ''), w.fecha_entrega,
             exists (select 1 from public."Registros_Produccion_Virgilio" r
                      where r.opcion in ('EP','TP')
                        and upper(btrim(split_part(r.texto,'|',1))) = upper(btrim(w.tanda))
                        and not public.es_legajo_test(r.legajo)),
             exists (select 1 from public."Registros_Produccion_Virgilio" r
                      where r.opcion in ('AP','TAP')
                        and upper(btrim(split_part(r.texto,'|',1))) = upper(btrim(w.tanda))
                        and not public.es_legajo_test(r.legajo)),
             'desarmado: ' || v_just, nullif(btrim(p_por), '')
        from public."PPP_Web_Programacion" w
       where w.empresa = v_emp and w.np = v_num
         and coalesce(nullif(btrim(w.tanda), ''), '') <> ''
      on conflict (empresa, order_id, np_idx) do update
         set tanda_previa = coalesce(excluded.tanda_previa, t.tanda_previa),
             fecha_previa = coalesce(excluded.fecha_previa, t.fecha_previa),
             ya_pickeada  = excluded.ya_pickeada or t.ya_pickeada,
             ya_armada    = excluded.ya_armada   or t.ya_armada,
             motivo = excluded.motivo, por = excluded.por, creado_at = now();
    else
      insert into public."GV_Web_Cancelados" (empresa, order_id, np_label, motivo, por)
      values (v_emp, v_oid, v_np, case when v_ag then 'cancelado: ' else 'desarmado: ' end || v_just,
              nullif(btrim(p_por),''))
      on conflict (empresa, order_id) do update
         set motivo = excluded.motivo, por = excluded.por, np_label = excluded.np_label, creado_at = now();
      delete from public."GV_PPP_Web_Retenido" t where t.empresa = v_emp and t.order_id = v_oid;
    end if;
    update public."PPP_Web_Programacion" w
       set tanda = null, fecha_entrega = null, actualizado_at = now()
     where w.empresa = v_emp and w.np = v_num;
    get diagnostics v_n = row_count;
  end if;

  insert into public."GV_Desarmes"
    (np, empresa, es_isis, order_id, cod_cliente, razon_social, tanda, fecha_entrega, m3,
     items, stock_devuelto, justificativo, por, vuelve)
  values (v_np, coalesce(v_emp, case when upper(v_np) like 'CH%' then 'chef' else 'lk' end),
          v_isis, v_oid, v_cod, v_rs, v_tanda, v_fe, v_m3, v_items, v_dev, v_just,
          nullif(btrim(p_por),''), v_vuelve);

  return query select v_np, v_isis, v_tanda, v_arts, v_cajas,
    (case when v_cajas = 0 then 'no habia mercaderia movida: no se devolvio nada'
          else v_arts || ' articulo' || case when v_arts = 1 then '' else 's' end || ' · ' || v_cajas
               || ' caja' || case when v_cajas = 1 then '' else 's' end || ' devueltas ('
               || concat_ws(', ',
                    case when v_term  > 0 then v_term  || ' a gondola'   end,
                    case when v_exc   > 0 then v_exc   || ' a excedente' end,
                    case when v_guard > 0 then v_guard || ' a A guardar' end) || ')'
     end
     || case when v_vuelve then ' · vuelve a A Programar y el automatico NO lo va a tomar'
             when v_ag     then ' · pedido CANCELADO: sale de la PPP y no vuelve'
             else ' · el pedido NO vuelve' end)::text;
end;
$function$;

-- 3) las funciones nuevas
drop function if exists public.gv_ppp_pedido_cancelar(text,text,text,boolean,boolean);
drop function if exists public.gv_ppp_np_cancelar_previo(text);
drop function if exists public.gv_ppp_np_devolucion(text,text);

-- 4) la tabla. ⚠ Mirarla ANTES de borrarla: cada fila es una NP que un supervisor canceló a
--    mano, y sin ella el cron la vuelve a programar. Si hay filas, mejor dejarla.
--    select * from public."GV_PPP_Web_NP_Cancelada";
-- drop table public."GV_PPP_Web_NP_Cancelada";

-- ⚠ Lo que NO se deshace solo: los movimientos de stock que ya devolvió una cancelación
--    (tipo = 'desarme'), y las NP que ya salieron de la PPP. Para revivir una NP web cancelada:
--    delete from public."GV_PPP_Web_NP_Cancelada" where np_label = '<NP>';
--    delete from public."GV_Web_Cancelados"       where np_label = '<NP>';
--    y para una de ISIS: delete from public."NP_Canceladas" where np = '<NP>';
--                        update public."GV_PPP_Prog_Override" set oculto = false where np = '<NP>';
