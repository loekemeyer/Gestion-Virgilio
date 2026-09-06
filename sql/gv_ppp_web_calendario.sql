-- ⚠ v13.23: la versión vigente devuelve además muy_pronto, dia_minimo y m3_web, con m3 = web + ISIS y cupo = gv_ppp_web_cupo(dia). Ver sql/gv_ppp_web_anticipacion.sql y sql/gv_ppp_web_cupo_dotacion.sql; el cuerpo de abajo es el de v13.18.
-- gv_ppp_web_calendario(p_desde, p_hasta) · los "circulitos" del calendario de "A Programar".
-- v13.18 (2026-09-06 noche) · dueño: "acá sigue figurando cero pero sí hay en la PPP".
-- Hasta v13.17 sólo sumaba PPP_Web_Programacion (tandas web). Ahora devuelve además lo que ISIS
-- ya tiene programado ese día (gv_ppp_programacion_diaria = espejo con la canilla cerrada, lo mismo
-- que muestra la solapa Programación): m3_isis, tandas_isis, np_isis.
-- ⚠ El cupo (`cupo`, `resta`, `pasado`) sigue siendo SOBRE LO WEB hasta que el dueño defina la regla
-- por dotación (idea 6220). El front lo muestra en una línea aparte "📋 ISIS: 13,45 m³ · 7 tanda(s)".
-- Migraciones: gv_ppp_web_calendario_con_isis_v1318 (drop + create: cambia el tipo de retorno) y
-- gv_ppp_web_calendario_con_isis_fix_fecha_v1318 (fecha_entrega del espejo es texto y puede venir "").
-- Grants como estaban: execute para anon, authenticated, service_role (sólo lee; la vista de ISIS
-- tiene security_invoker y la RLS de cada uno).

drop function if exists public.gv_ppp_web_calendario(date, date);
create function public.gv_ppp_web_calendario(
  p_desde date default date_trunc('month', current_date)::date,
  p_hasta date default (date_trunc('month', current_date) + interval '1 mon -1 days')::date)
returns table(dia date, habil boolean, m3 numeric, tandas integer, np integer, cupo numeric, resta numeric, pasado boolean,
              m3_isis numeric, tandas_isis integer, np_isis integer)
language sql stable set search_path = public, pg_temp as $$
  with cupo as (select coalesce((select valor from public."PPP_Web_Config" where clave='m3_max_dia'), 5.00) as v),
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
          group by r.f::date)
  select d.dia,
         public.gv_es_dia_habil(d.dia),
         coalesce(w.m3, 0),
         coalesce(w.tandas, 0),
         coalesce(w.np, 0),
         (select v from cupo),
         round(greatest((select v from cupo) - coalesce(w.m3, 0), 0), 3),
         coalesce(w.m3, 0) > (select v from cupo),
         coalesce(i.m3, 0),
         coalesce(i.tandas, 0),
         coalesce(i.np, 0)
    from d
    left join web  w on w.dia = d.dia
    left join isis i on i.dia = d.dia
   order by d.dia;
$$;
grant execute on function public.gv_ppp_web_calendario(date, date) to anon, authenticated, service_role;

-- Prueba (2026-09-06): select dia, m3, m3_isis, tandas_isis, np_isis from public.gv_ppp_web_calendario('2026-09-07','2026-09-11');
--   2026-09-08 → m3 0 · m3_isis 13.451 · 7 tandas · 11 NP
--   2026-09-09 → m3 0 · m3_isis 10.768 · 7 · 20
--   2026-09-10 → m3 0 · m3_isis  5.762 · 11 · 35
--   2026-09-11 → m3 0 · m3_isis  3.138 · 6 · 13
-- Rollback: volver a la versión sin las 3 columnas (docs/SUPABASE-GESTION-VIRGILIO.md §3.j) — drop + create.
