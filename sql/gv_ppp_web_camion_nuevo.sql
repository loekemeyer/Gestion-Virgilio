-- gv_ppp_web_camion_nuevo.sql — ¿esta tanda abre un camión NUEVO ese día? · v13.86 (2026-09-08) · Virgilio
-- Dueño: "si se programa algo para un segundo camión para un mismo día (salvo que sea súper), debe pedirle
-- confirmación: ¿seguro que vas a usar un segundo camión?". Dado el día y las paradas de la tanda que se está por
-- programar, dice a qué camión iría cada parada (misma etiqueta que el armado: Capital / GBA Sur / GBA Oeste /
-- GBA Norte, vía GV_Sectores y gv_ppp_web_camion) y si ese camión YA va ese día. Mira las tandas web
-- (PPP_Web_Programacion) y las de ISIS (gv_ppp_programacion_diaria), sin súper / retira / expo — no son camión de
-- reparto — y sin KRIKOS. Sólo lee. Migración gv_ppp_web_camion_nuevo_v1386.
-- Lo usa `aprConfirmar` en A Programar: pregunta si hay alguna fila con ya_va = false, es_super = false y
-- camiones_dia > 0 (o sea, ese día ya sale algún camión y ésta abre otro).
-- Rollback: drop function public.gv_ppp_web_camion_nuevo(date, jsonb);
create or replace function public.gv_ppp_web_camion_nuevo(p_fecha date, p_filas jsonb default '[]'::jsonb)
returns table (camion text, ya_va boolean, paradas int, camiones_dia int, es_super boolean)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  with fila as (
    select coalesce(nullif(x->>'zona',''), '(sin zona)') as zona,
           nullif(x->>'barrio','')    as barrio,
           nullif(x->>'direccion','') as direccion
      from jsonb_array_elements(coalesce(p_filas, '[]'::jsonb)) x
  ),
  mia as (
    select public.gv_ppp_web_camion(f.zona, public.gv_ppp_web_sector(f.zona, f.barrio, f.direccion)) as camion,
           (f.zona ~* 'super|retira|expo') as es_super
      from fila f
  ),
  dia as (
    select distinct public.gv_ppp_web_camion(t.zona, public.gv_ppp_web_sector(t.zona, t.barrio, t.direccion)) as camion
      from (
        select w.zona, w.barrio, w.direccion
          from public."PPP_Web_Programacion" w
         where w.fecha_entrega = p_fecha and coalesce(nullif(btrim(w.tanda),''),'') <> ''
        union all
        select i.zona, i.barrio, i.direccion
          from public.gv_ppp_programacion_diaria i
         where btrim(i.fecha_entrega::text) ~ '^\d{4}-\d{2}-\d{2}'
           and left(btrim(i.fecha_entrega::text), 10)::date = p_fecha
           and coalesce(nullif(btrim(i.tanda),''),'') <> ''
           and coalesce(i.tipo,'') <> 'KRIKOS'
      ) t
     where coalesce(t.zona,'') !~* 'super|retira|expo'
  )
  select m.camion,
         exists (select 1 from dia d where d.camion = m.camion) as ya_va,
         count(*)::int as paradas,
         (select count(*)::int from dia) as camiones_dia,
         bool_or(m.es_super) as es_super
    from mia m
   group by m.camion
   order by count(*) desc, m.camion;
$$;
grant execute on function public.gv_ppp_web_camion_nuevo(date, jsonb) to anon, authenticated;
