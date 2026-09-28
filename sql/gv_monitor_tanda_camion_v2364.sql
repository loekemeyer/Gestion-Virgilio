-- v23.64 (Luis, 28/09): "Total por día" del monitor contaba CAMIONES por letra+número de la
-- tanda (tandaCamion: E37A/E37E/E37F = "E37"), así que el 30/09 decía 11 camiones.
-- Un camión = UN GRUPO DE ZONAS (regla v21.56/v21.95): Capital Sur Z1 · Capital Centro Z2 ·
-- Capital Oeste Z3 (Z2+Z3 juntas si cada una < 1 m³ ese día) · GBA Sur Z4 · GBA Oeste Z5 ·
-- GBA Norte Z6+Z7 · cada SÚPER su camión (v14.23) · Retira sin camión.
-- ≡ index.html PPP_RES_CAMIONES (Resumen de la PPP). Lo leen el monitor admin y monitor/tv.html.
-- Rollback: drop view public.gv_monitor_tanda_camion;
create or replace view public.gv_monitor_tanda_camion with (security_invoker = true) as
with src as (
  select upper(btrim(w.tanda)) tanda, w.fecha_entrega::date fecha, w.zona, lower(w.empresa) emp,
         w.cod_cliente::text cod, w.razon_social rs, coalesce(w.m3,0)::numeric m3, null::text tipo
    from public."PPP_Web_Programacion" w
   where w.tanda is not null and btrim(w.tanda) <> '' and w.fecha_entrega is not null
  union all
  select upper(btrim(i.tanda)), left(i.fecha_entrega,10)::date, i.zona,
         case when i.np ~ '^\d+$' and i.np::bigint > 90000 then 'lk' else 'chef' end,
         i.cod, i.razon_social, coalesce(i.m3,0)::numeric, i.tipo
    from public.gv_ppp_programacion_diaria i
   where i.tanda is not null and btrim(i.tanda) <> '' and i.fecha_entrega ~ '^\d{4}-\d{2}-\d{2}' and i.np ~ '\d'
),
t as (
  select tanda, fecha, sum(m3) m3,
         bool_or(coalesce(tipo,'') ilike '%krikos%' or coalesce(zona,'') ~* 'super' or public.gv_es_super(emp, cod)) sup,
         bool_and(coalesce(zona,'') ~* '^\s*retira\s*$') ret,
         min(substring(zona from '(?i)zona\s*([0-9]+)')::int) zn,
         min(rs) filter (where coalesce(tipo,'') ilike '%krikos%' or coalesce(zona,'') ~* 'super' or public.gv_es_super(emp, cod)) rs_sup
    from src group by tanda, fecha
),
g as (
  select t.*, case when sup then 'Súper · ' || coalesce(rs_sup, '?')
                   when ret then 'Retira'
                   when zn = 1 then 'Capital Sur'   when zn = 2 then 'Capital Centro'
                   when zn = 3 then 'Capital Oeste' when zn = 4 then 'GBA Sur'
                   when zn = 5 then 'GBA Oeste'     when zn in (6,7) then 'GBA Norte'
                   else 'Sin zona' end grupo
    from t
),
gd as (select g.*, sum(m3) over (partition by fecha, grupo) m3_grupo from g)
select gd.tanda, gd.fecha, round(gd.m3, 3) m3,
       case when gd.grupo in ('Capital Centro','Capital Oeste') and gd.m3_grupo < 1
             and exists (select 1 from gd o where o.fecha = gd.fecha and o.m3_grupo < 1
                          and o.grupo = case gd.grupo when 'Capital Centro' then 'Capital Oeste' else 'Capital Centro' end)
            then 'Capital Centro-Oeste' else gd.grupo end as camion,
       (gd.grupo not in ('Retira')) as usa_camion
  from gd;
grant select on public.gv_monitor_tanda_camion to anon, authenticated;
