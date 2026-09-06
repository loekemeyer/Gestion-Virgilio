-- ============================================================================
-- v13.34 — El cupo diario, calculado UNA vez para todo un rango
--
-- POR QUÉ: "A Programar" tardaba ~5 s en abrir. Midiendo, el grueso era
-- `gv_ppp_web_calendario(hoy, hoy+20)`: 1.357 ms. La causa no era ninguna tabla
-- grande, sino que llamaba a `gv_ppp_web_cupo(dia)` UNA VEZ POR DÍA (21 llamadas)
-- y cada llamada evaluaba `gv_ppp_web_pickers_tipicos()` DOS veces —una en la
-- condición del `case`, otra en el resultado—, o sea 42 escaneos de 60 días de
-- `Registros_Produccion_Virgilio`.
--
-- CÓMO SE ARREGLA SIN DUPLICAR LA REGLA: la fórmula del cupo sigue viviendo en un
-- solo lugar, pero ahora ese lugar es `gv_ppp_web_cupo_dias(desde, hasta)`, que
-- resuelve los pickers y la config una sola vez y aplica la fórmula por día.
-- `gv_ppp_web_cupo(fecha)` pasa a ser el envoltorio de un día, así todo lo que ya
-- lo usaba (job, intradía, dia_salida, proximo_dia_entrega) sigue igual.
--
-- El `materialized` de los CTE es a propósito: sin él Postgres inlinea la
-- subconsulta y vuelve a contar los pickers por cada fila — que es exactamente el
-- problema que estamos sacando.
--
-- MEDIDO (2026-09-06):
--   gv_ppp_web_calendario(hoy, hoy+20):  1.357 ms → 22,8 ms
--   gv_ppp_web_dia_salida (4 pedidos):      99 ms → 60 ms
--   filas idénticas antes/después: `except` en los dos sentidos = 0 sobre 41 días.
--
-- ROLLBACK: volver a la versión anterior de `gv_ppp_web_cupo` y de
-- `gv_ppp_web_calendario` (ver sql/gv_ppp_web_cupo_dotacion.sql y
-- sql/gv_ppp_web_calendario.sql) y `drop function gv_ppp_web_cupo_dias(date,date)`.
-- ============================================================================

create or replace function public.gv_ppp_web_cupo_dias(p_desde date, p_hasta date)
returns table (dia date, cupo numeric)
language sql
stable security definer
set search_path to 'public', 'pg_temp'
as $function$
  with p as materialized (select public.gv_ppp_web_pickers_tipicos() as n),
       cfg as materialized (
         select coalesce(max(valor) filter (where clave = 'cupo_por_dotacion'), 0)   as por_dotacion,
                coalesce(max(valor) filter (where clave = 'cupo_m3_por_picker'), 3)  as m3_por_picker,
                coalesce(max(valor) filter (where clave = 'm3_max_dia'), 5.00)       as fijo
           from public."PPP_Web_Config")
  select g::date,
         case when cfg.por_dotacion = 1 and p.n > 0 then p.n * cfg.m3_por_picker else cfg.fijo end
    from generate_series(p_desde, p_hasta, interval '1 day') g
   cross join p cross join cfg;
$function$;

comment on function public.gv_ppp_web_cupo_dias(date, date) is
  'v13.34 — cupo diario (m³) para un rango. Fórmula única del cupo: pickers típicos × cupo_m3_por_picker si cupo_por_dotacion=1, si no m3_max_dia. Resuelve pickers y config UNA vez para todo el rango.';

-- Envoltorio de un día: todo lo que ya llamaba a gv_ppp_web_cupo(fecha) sigue igual.
create or replace function public.gv_ppp_web_cupo(p_fecha date default current_date)
returns numeric
language sql
stable security definer
set search_path to 'public', 'pg_temp'
as $function$
  select c.cupo from public.gv_ppp_web_cupo_dias(p_fecha, p_fecha) c;
$function$;

revoke all on function public.gv_ppp_web_cupo_dias(date, date) from public;
grant execute on function public.gv_ppp_web_cupo_dias(date, date) to authenticated, service_role;

-- El calendario deja de pedir el cupo día por día. Sin cambio de columnas ni de resultado.
create or replace function public.gv_ppp_web_calendario(
  p_desde date default (date_trunc('month', current_date::timestamptz))::date,
  p_hasta date default ((date_trunc('month', current_date::timestamptz) + interval '1 mon -1 days'))::date)
returns table(dia date, habil boolean, m3 numeric, tandas integer, np integer, cupo numeric, resta numeric,
              pasado boolean, m3_isis numeric, tandas_isis integer, np_isis integer, muy_pronto boolean,
              dia_minimo date, m3_web numeric)
language sql
stable
set search_path to 'public', 'pg_temp'
as $function$
  with minimo as (select public.gv_ppp_web_dia_minimo(now()) as d),
       d as (select generate_series(p_desde, p_hasta, interval '1 day')::date as dia),
       web as (
         select g.fecha_entrega as dia, round(sum(g.m3), 3) as m3, count(distinct g.tanda)::int as tandas, count(g.order_id)::int as np
           from public."PPP_Web_Programacion" g
          where g.fecha_entrega between p_desde and p_hasta
            and coalesce(nullif(trim(g.tanda),''),'') <> ''
          group by g.fecha_entrega),
       isis_raw as (
         select left(trim(i.fecha_entrega::text), 10) as f, i.tanda, i.m3
           from public.gv_ppp_programacion_diaria i
          where trim(i.fecha_entrega::text) ~ '^\d{4}-\d{2}-\d{2}'
            and coalesce(nullif(trim(i.tanda),''),'') <> ''),
       isis as (
         select r.f::date as dia, round(sum(r.m3), 3) as m3, count(distinct r.tanda)::int as tandas, count(*)::int as np
           from isis_raw r
          where r.f::date between p_desde and p_hasta
          group by r.f::date),
       c as materialized (select cd.dia, cd.cupo from public.gv_ppp_web_cupo_dias(p_desde, p_hasta) cd)
  select d.dia,
         public.gv_es_dia_habil(d.dia),
         coalesce(w.m3, 0) + coalesce(i.m3, 0),
         coalesce(w.tandas, 0) + coalesce(i.tandas, 0),
         coalesce(w.np, 0) + coalesce(i.np, 0),
         c.cupo,
         round(greatest(c.cupo - coalesce(w.m3, 0) - coalesce(i.m3, 0), 0), 3),
         coalesce(w.m3, 0) + coalesce(i.m3, 0) > c.cupo,
         coalesce(i.m3, 0),
         coalesce(i.tandas, 0),
         coalesce(i.np, 0),
         d.dia < (select d from minimo),
         (select d from minimo),
         coalesce(w.m3, 0)
    from d
    join c on c.dia = d.dia
    left join web  w on w.dia = d.dia
    left join isis i on i.dia = d.dia
   order by d.dia;
$function$;

-- Prueba de que no cambió nada (correr ANTES de aplicar para dejar la foto):
--   create table public."GV_Tmp_Cal_Baseline" as select * from public.gv_ppp_web_calendario(current_date, current_date + 40);
-- y DESPUÉS:
--   with nuevo as (select * from public.gv_ppp_web_calendario(current_date, current_date + 40))
--   select (select count(*) from (select * from nuevo except select * from public."GV_Tmp_Cal_Baseline") x) solo_nuevo,
--          (select count(*) from (select * from public."GV_Tmp_Cal_Baseline" except select * from nuevo) y) solo_viejo;
--   -- dio 0 / 0 el 2026-09-06. Después: drop table public."GV_Tmp_Cal_Baseline";
