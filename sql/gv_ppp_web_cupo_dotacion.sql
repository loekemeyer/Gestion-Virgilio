-- CUPO POR DOTACIÓN · v13.23 (2026-09-05 sábado noche) · idea 6220 · migración `gv_ppp_web_cupo_por_dotacion_v1323`
-- Dueño: "el cupo depende de cuánta gente trabaje"; la gente sale "de los mensajes de producción"
-- (Registros_Produccion_Virgilio); lo de ISIS "lo que esté, esté" (cuenta para el cupo).
-- Análisis de 3 agentes sobre 90 días (scratchpad analisis-dotacion/tiempos/flujo, 2026-09-05):
--   1 picker ≈ 3,9 m³/día (p50), 2 pickers ≈ 6,2 → K = 3 m³ por picker. Armado rinde 0,55 m³/h-hombre y
--   suele ser el cuello; no se tapa con un segundo tope (se puede agregar después).
--
--   cupo(fecha)  = pickers_típicos × cupo_m3_por_picker
--   pickers_típicos = mediana de legajos distintos con eventos de picking (EP/TP/PKC, legajos ≠ 0/1)
--                     por día, sobre los últimos `cupo_dias_muestra` días con actividad (60 días atrás máx.)
--   usado(fecha) = web (PPP_Web_Programacion con tanda) + ISIS (gv_ppp_programacion_diaria, canilla cerrada)
-- Interruptores (PPP_Web_Config): cupo_por_dotacion (1/0) · cupo_m3_por_picker (3) · cupo_dias_muestra (10).
-- Con cupo_por_dotacion = 0 (o sin datos de picking) vuelve el fijo m3_max_dia (5).
-- Lo usan: gv_ppp_web_proximo_dia_entrega (job + intradía), gv_ppp_web_calendario (m3 = web + ISIS,
-- m3_web aparte), ppp_web_armar_tandas (parche: v_cupo y v_usado + ISIS) y gv_ppp_web_tanda_programar
-- (parche: aviso de cupo). Medido el sábado: pickers_típicos = 2 → cupo = 6; vie 11: 3,14 ISIS → resta 2,86;
-- lun 14: 1,51 → resta 4,49. Los 3,72 m³ web pendientes se reparten entre esos dos días.
-- Rollback: update public."PPP_Web_Config" set valor = 0 where clave = 'cupo_por_dotacion';  (todo vuelve a 5 fijo;
-- ISIS sigue contando: para sacarlo hay que revertir los parches, ver la migración).

insert into public."PPP_Web_Config" (clave, valor, descripcion) values
  ('cupo_por_dotacion', 1, 'v13.23 · 1 = cupo diario = pickers típicos × cupo_m3_por_picker (idea 6220); 0 = fijo m3_max_dia'),
  ('cupo_m3_por_picker', 3, 'v13.23 · m³ por picker y día (análisis 2026-09-05: 1 picker 3,9 · 2 pickers 6,2)'),
  ('cupo_dias_muestra', 10, 'v13.23 · cuántos días con actividad de picking se miran para la dotación típica (mediana)')
on conflict (clave) do nothing;

create or replace function public.gv_ppp_web_pickers_tipicos()
returns integer language sql stable security definer set search_path = public, pg_temp as $$
  with n as (select greatest(coalesce((select valor from public."PPP_Web_Config" where clave='cupo_dias_muestra'), 10), 1)::int as v),
  d as (
    select (r.ts_cliente at time zone 'America/Argentina/Buenos_Aires')::date as dia, count(distinct r.legajo) as pickers
      from public."Registros_Produccion_Virgilio" r
     where r.opcion in ('EP','TP','PKC') and r.legajo::text not in ('0','1')
       and r.ts_cliente >= now() - interval '60 days'
     group by 1 order by 1 desc limit (select v from n)
  )
  select coalesce(round(percentile_cont(0.5) within group (order by pickers))::int, 0) from d;
$$;

create or replace function public.gv_ppp_web_m3_isis(p_fecha date)
returns numeric language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce(round(sum(i.m3), 3), 0)
    from public.gv_ppp_programacion_diaria i
   where btrim(i.fecha_entrega::text) ~ '^\d{4}-\d{2}-\d{2}'
     and left(btrim(i.fecha_entrega::text), 10)::date = p_fecha
     and coalesce(nullif(btrim(i.tanda),''),'') <> '';
$$;

create or replace function public.gv_ppp_web_cupo(p_fecha date default current_date)
returns numeric language sql stable security definer set search_path = public, pg_temp as $$
  select case
           when coalesce((select valor from public."PPP_Web_Config" where clave='cupo_por_dotacion'), 0) = 1
                and public.gv_ppp_web_pickers_tipicos() > 0
           then public.gv_ppp_web_pickers_tipicos() * coalesce((select valor from public."PPP_Web_Config" where clave='cupo_m3_por_picker'), 3)
           else coalesce((select valor from public."PPP_Web_Config" where clave='m3_max_dia'), 5.00)
         end;
$$;
revoke all on function public.gv_ppp_web_pickers_tipicos(), public.gv_ppp_web_m3_isis(date), public.gv_ppp_web_cupo(date) from public, anon;
grant execute on function public.gv_ppp_web_pickers_tipicos(), public.gv_ppp_web_m3_isis(date), public.gv_ppp_web_cupo(date) to authenticated, service_role;

-- gv_ppp_web_proximo_dia_entrega: v_usado := web + gv_ppp_web_m3_isis(v_d); compara contra gv_ppp_web_cupo(v_d).
--   (cuerpo completo en sql/gv_ppp_web_anticipacion.sql, con estas dos líneas cambiadas)
-- gv_ppp_web_calendario: ver sql/gv_ppp_web_calendario.sql (m3 = web + ISIS, cupo = gv_ppp_web_cupo(dia), + m3_web).
-- ppp_web_armar_tandas v4 y gv_ppp_web_tanda_programar: parche con replace() sobre pg_get_functiondef:
--   'v_cupo numeric := coalesce((select valor from "PPP_Web_Config" where clave=''m3_max_dia''), 5.00);'
--     → 'v_cupo numeric := public.gv_ppp_web_cupo(p_fecha);'
--   y antes de usar v_usado: 'v_usado := v_usado + public.gv_ppp_web_m3_isis(p_fecha);'
--   (la migración aborta si no encuentra los puntos de inserción).

-- Consultas útiles:
--   select public.gv_ppp_web_pickers_tipicos(), public.gv_ppp_web_cupo(current_date);
--   select dia, m3, m3_web, m3_isis, cupo, resta, muy_pronto from public.gv_ppp_web_calendario('2026-09-07','2026-09-18');
