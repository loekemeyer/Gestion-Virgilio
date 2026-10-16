-- v31.34 (Thomas) — Análisis Productivo «Por camión».
-- La operación se despacha por CAMIÓN, no por tanda. Esta función agrega, por camión y día de
-- entrega, las horas-hombre reales (picking + armado) contra las esperadas por dificultad y los
-- minutos-hombre por m³ (lo que paga el viaje). Ordena por min-h/m³ desc: el más caro, arriba.
--
-- Fuentes: GV_Picking_Tanda / GV_Armado_Tanda (deduplicadas a 1 fila por tanda = el pick/armado
-- real, misma regla que gv_analisis_tanda tras el fix D3) y gv_monitor_tanda_camion (tanda->camión,
-- fecha de entrega, m³). La ventana es por fecha de entrega; el picking/armado se busca en tp hasta
-- 15 días antes (se pickea/arma antes de entregar). La consume Análisis Productivo (Juan + admin).

create or replace function public.gv_analisis_camion(p_dias int, p_legajo text)
returns table(fecha date, camion text, tandas int, m3 numeric,
  min_pick numeric, min_arm numeric, min_real numeric, min_esp numeric,
  rendimiento numeric, min_x_m3 numeric)
language plpgsql stable security definer set search_path = public as $$
declare v_hoy date := (now() at time zone 'America/Argentina/Buenos_Aires')::date;
        v_desde date := v_hoy - (greatest(p_dias, 1) - 1);
begin
  if not public.gv_analisis_acceso_ok(p_legajo) then
    raise exception 'ACCESO: el Analisis Productivo es para el supervisor y los legajos habilitados';
  end if;
  return query
  with pk as (
    select distinct on (upper(btrim(t.tanda))) upper(btrim(t.tanda)) tanda, t.real_min, t.tamano
      from public."GV_Picking_Tanda" t
     where (t.tp at time zone 'America/Argentina/Buenos_Aires')::date between v_desde - 15 and v_hoy
       and not public.es_legajo_test(t.legajo)
     order by upper(btrim(t.tanda)), t.lineas desc nulls last, t.real_min asc nulls last, t.tp desc
  ), ar as (
    select distinct on (upper(btrim(t.tanda))) upper(btrim(t.tanda)) tanda, t.real_min, t.tamano
      from public."GV_Armado_Tanda" t
     where (t.tp at time zone 'America/Argentina/Buenos_Aires')::date between v_desde - 15 and v_hoy
       and not public.es_legajo_test(t.legajo)
     order by upper(btrim(t.tanda)), t.nps desc nulls last, t.tp desc
  ), cam as (
    select upper(btrim(c.tanda)) tanda, c.fecha, coalesce(nullif(btrim(c.camion), ''), 'Sin camión') camion, c.m3
      from public.gv_monitor_tanda_camion c
     where c.fecha between v_desde and v_hoy
  )
  select cam.fecha, cam.camion, count(*)::int,
    round(sum(cam.m3), 3),
    round(sum(coalesce(pk.real_min, 0)), 1), round(sum(coalesce(ar.real_min, 0)), 1),
    round(sum(coalesce(pk.real_min, 0) + coalesce(ar.real_min, 0)), 1),
    round(sum(coalesce(pk.tamano, 0) + coalesce(ar.tamano, 0)), 1),
    round(sum(coalesce(pk.tamano, 0) + coalesce(ar.tamano, 0)) / nullif(sum(coalesce(pk.real_min, 0) + coalesce(ar.real_min, 0)), 0) - 1, 3),
    round(sum(coalesce(pk.real_min, 0) + coalesce(ar.real_min, 0)) / nullif(sum(cam.m3), 0), 2)
  from cam left join pk on pk.tanda = cam.tanda left join ar on ar.tanda = cam.tanda
  group by cam.fecha, cam.camion
  order by cam.fecha desc, 10 desc nulls last;
end $$;
revoke all on function public.gv_analisis_camion(int, text) from public;
grant execute on function public.gv_analisis_camion(int, text) to anon, authenticated;
