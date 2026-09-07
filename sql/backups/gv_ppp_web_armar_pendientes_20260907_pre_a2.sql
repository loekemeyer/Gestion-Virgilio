-- ============================================================================
-- BACKUP · gv_ppp_web_armar_pendientes ANTES del bloque (a2) — 2026-09-07 (v13.93)
-- ----------------------------------------------------------------------------
-- Ésta es la versión que estaba desplegada hasta la v13.92, sin la regla
-- "si el cliente ya tiene camión, engancharlo ahí". Correr este archivo la restaura.
-- Lo que agrega la v13.93 está documentado en sql/gv_ppp_web_dia_cliente.sql y en
-- docs/SUPABASE-GESTION-VIRGILIO.md.
-- ============================================================================

create or replace function public.gv_ppp_web_armar_pendientes(
  p_empresa text,
  p_fecha date default null::date,
  p_filas jsonb default '[]'::jsonb,
  p_forzar jsonb default '[]'::jsonb)
returns table (r_fecha date, r_tanda text, r_zona text, r_np_count int, r_m3 numeric, r_clientes int, r_cods text[])
language plpgsql
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_min    date := public.gv_ppp_web_dia_minimo();
  v_fecha  date;
  v_i      int := 0;
  v_n      int;
  v_antes  int;
  r        record;
begin
  drop table if exists _gv_res;
  drop table if exists _gv_tmp;
  create temp table _gv_res (r_fecha date, r_tanda text, r_zona text, r_np_count int, r_m3 numeric, r_clientes int, r_cods text[]) on commit drop;
  create temp table _gv_tmp (r_tanda text, r_zona text, r_np_count int, r_m3 numeric, r_clientes int) on commit drop;

  -- (a) forzados con fecha (Chef de una razon social que entro por LK ese dia)
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
$fn$;
