-- BACKUP · 2026-09-07 · gv_ppp_web_armar_pendientes ANTES del bloque (a1) de la v14.05
-- (versión v13.93, con el bloque (a2) "el cliente ya tiene camión ese día").
-- Rollback: ejecutar este archivo tal cual en el SQL editor de Virgilio (hrxfctzncixxqmpfhskv).
CREATE OR REPLACE FUNCTION public.gv_ppp_web_armar_pendientes(p_empresa text, p_fecha date DEFAULT NULL::date, p_filas jsonb DEFAULT '[]'::jsonb, p_forzar jsonb DEFAULT '[]'::jsonb)
 RETURNS TABLE(r_fecha date, r_tanda text, r_zona text, r_np_count integer, r_m3 numeric, r_clientes integer, r_cods text[])
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_min    date := public.gv_ppp_web_dia_minimo();
  v_fecha  date;
  v_techo  date;
  v_i      int := 0;
  v_n      int;
  v_antes  int;
  r        record;
begin
  drop table if exists _gv_res;
  drop table if exists _gv_tmp;
  create temp table _gv_res (r_fecha date, r_tanda text, r_zona text, r_np_count int, r_m3 numeric, r_clientes int, r_cods text[]) on commit drop;
  create temp table _gv_tmp (r_tanda text, r_zona text, r_np_count int, r_m3 numeric, r_clientes int) on commit drop;

  -- (a) forzados con fecha (Chef de una razón social que entró por LK ese día)
  for r in
    select nullif(x->>'fecha','')::date as f, array_agg(distinct x->>'cod') as cods
      from jsonb_array_elements(coalesce(p_forzar, '[]'::jsonb)) x
     where nullif(x->>'fecha','') is not null and nullif(x->>'cod','') is not null
     group by 1 order by 1
  loop
    delete from _gv_tmp where true;
    insert into _gv_tmp select * from public.ppp_web_armar_tandas(p_empresa, r.f, p_filas, r.cods, false);
    insert into _gv_res
    select r.f, t.r_tanda, t.r_zona, t.r_np_count, t.r_m3, t.r_clientes,
           (select array_agg(distinct s.cliente) from _asig a join _sin_tanda s on s.order_id = a.order_id and s.np_idx = a.np_idx where a.tanda = t.r_tanda)
      from _gv_tmp t;
  end loop;

  -- (a2) v13.93 — EL CLIENTE YA TIENE CAMION ANTES: engancharlo ahi.
  v_techo := public.gv_ppp_web_proximo_dia_con_cupo(coalesce(p_fecha, v_min));
  for r in
    select d, jsonb_agg(x) as filas, array_agg(distinct x->>'cod') as cods
      from (
        select public.gv_ppp_web_dia_cliente(p_empresa, x->>'cod', current_date + 1, v_techo - 1) as d, x
          from jsonb_array_elements(p_filas) x
         where coalesce(x->>'zona','') ~ '^\s*Zona\s*[0-9]+'
           and nullif(btrim(coalesce(x->>'cod','')),'') is not null
           and not exists (select 1 from public."PPP_Web_Programacion" g
                            where g.empresa = p_empresa and g.order_id = (x->>'order_id')::bigint
                              and g.np_idx = (x->>'np_idx')::int and coalesce(nullif(trim(g.tanda),''),'') <> '')
      ) s
     where d is not null
     group by d order by d
  loop
    delete from _gv_tmp where true;
    insert into _gv_tmp select * from public.ppp_web_armar_tandas(p_empresa, r.d, r.filas, r.cods, true);
    insert into _gv_res
    select r.d, t.r_tanda, t.r_zona, t.r_np_count, t.r_m3, t.r_clientes,
           (select array_agg(distinct s.cliente) from _asig a join _sin_tanda s on s.order_id = a.order_id and s.np_idx = a.np_idx where a.tanda = t.r_tanda)
      from _gv_tmp t;
  end loop;

  -- (b) zonas automaticas en cascada
  v_fecha := coalesce(p_fecha, v_min);
  loop
    v_i := v_i + 1;
    exit when v_i > 8;
    select count(*) into v_n
      from jsonb_array_elements(p_filas) x
     where public.gv_ppp_web_zona_automatica(x->>'zona')
       and not exists (select 1 from public."PPP_Web_Programacion" g
                        where g.empresa = p_empresa and g.order_id = (x->>'order_id')::bigint
                          and g.np_idx = (x->>'np_idx')::int and coalesce(nullif(trim(g.tanda),''),'') <> '');
    exit when v_n = 0;
    v_fecha := public.gv_ppp_web_proximo_dia_con_cupo(v_fecha);
    select count(*) into v_antes from _gv_res;
    delete from _gv_tmp where true;
    insert into _gv_tmp select * from public.ppp_web_armar_tandas(p_empresa, v_fecha, p_filas, '{}', false);
    insert into _gv_res
    select v_fecha, t.r_tanda, t.r_zona, t.r_np_count, t.r_m3, t.r_clientes,
           (select array_agg(distinct s.cliente) from _asig a join _sin_tanda s on s.order_id = a.order_id and s.np_idx = a.np_idx where a.tanda = t.r_tanda)
      from _gv_tmp t;
    exit when (select count(*) from _gv_res) = v_antes;
    v_fecha := v_fecha + 1;
  end loop;

  -- (c) zonas manuales con camion
  for r in
    select d, jsonb_agg(x) as filas, array_agg(distinct x->>'cod') as cods
      from (
        select public.gv_ppp_web_dia_camion(x->>'zona', v_min) as d, x
          from jsonb_array_elements(p_filas) x
         where coalesce(x->>'zona','') ~ '^\s*Zona\s*[0-9]+'
           and not public.gv_ppp_web_zona_automatica(x->>'zona')
           and not exists (select 1 from public."PPP_Web_Programacion" g
                            where g.empresa = p_empresa and g.order_id = (x->>'order_id')::bigint
                              and g.np_idx = (x->>'np_idx')::int and coalesce(nullif(trim(g.tanda),''),'') <> '')
      ) s
     where d is not null
     group by d order by d
  loop
    delete from _gv_tmp where true;
    insert into _gv_tmp select * from public.ppp_web_armar_tandas(p_empresa, r.d, r.filas, r.cods, true);
    insert into _gv_res
    select r.d, t.r_tanda, t.r_zona, t.r_np_count, t.r_m3, t.r_clientes,
           (select array_agg(distinct s.cliente) from _asig a join _sin_tanda s on s.order_id = a.order_id and s.np_idx = a.np_idx where a.tanda = t.r_tanda)
      from _gv_tmp t;
  end loop;

  return query select * from _gv_res order by 1, 2;
end
$function$;
