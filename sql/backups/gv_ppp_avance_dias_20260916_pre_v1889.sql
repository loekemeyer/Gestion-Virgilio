-- BACKUP 2026-09-16 — definición VIVA de public.gv_ppp_avance_dias(date,date) ANTES de la
-- v18.89 (`sql/gv_ppp_arbol_desprogramadas_v1889.sql`). Tomada con pg_get_functiondef.
-- Correr este archivo tal cual deshace el cambio en esta función; el gemelo
-- (gv_ppp_prog_arbol) se deshace corriendo `sql/gv_ppp_prog_arbol_v1766.sql`, que el 16/09
-- se verificó idéntico a lo que había vivo.

CREATE OR REPLACE FUNCTION public.gv_ppp_avance_dias(p_desde date, p_hasta date)
 RETURNS TABLE(fecha date, pedidos integer, m3 numeric, pick_ped integer, pick_m3 numeric, arm_ped integer, arm_m3 numeric, curso_ped integer, sin_ped integer, pct_listo integer, pct_armado integer, pct_listo_ped integer, pct_armado_ped integer, pct_listo_m3 integer, pct_armado_m3 integer, base text, curso_m3 numeric, sin_m3 numeric, fact_ped integer, fact_m3 numeric, pct_fact integer, pct_curso integer, pct_sin integer)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
with fuentes as (
  -- ⚠ TABLAS BASE, no gv_ppp_en_salida / gv_ppp_entregados: esas dos vistas tardan 3 y 4 segundos
  --    y el rol anon corta a los 3 (statement_timeout). Ver §3.ef.
  select 1 as pri, regexp_replace(btrim(p.np), '\.0+$', '') as np,
         upper(btrim(coalesce(p.tanda, ''))) as tanda, coalesce(p.m3, 0)::numeric as m3,
         nullif(left(btrim(p.fecha_entrega), 10), '')::date as fe
    from public.gv_ppp_programacion_diaria p
   where left(btrim(coalesce(p.fecha_entrega, '')), 10) ~ '^\d{4}-\d{2}-\d{2}$'
  union all
  select 2, public.gv_ppp_web_np_label(w.empresa, w.np, w.np_idx),
         upper(btrim(coalesce(w.tanda, ''))), coalesce(w.m3, 0)::numeric, w.fecha_entrega
    from public."PPP_Web_Programacion" w where w.tanda is not null and btrim(w.tanda) <> ''
  union all
  -- ya facturado: salió de la programación de ISIS. fecha_salida hace de fecha de entrega,
  -- igual que en gv_ppp_en_salida.
  select 3, regexp_replace(upper(btrim(f.np)), '\.0+$', ''),
         upper(btrim(coalesce(f.tanda, ''))), coalesce(f.m3, 0)::numeric, f.fecha_salida
    from public."Facturacion_NP" f where f.fecha_salida is not null
  union all
  select 4, regexp_replace(btrim(h.np), '\.0+$', ''),
         upper(btrim(coalesce(h.tanda, ''))), coalesce(h.m3, 0)::numeric,
         case when left(btrim(coalesce(h.fecha_entrega, '')), 10) ~ '^\d{4}-\d{2}-\d{2}$'
              then left(btrim(h.fecha_entrega), 10)::date end
    from public."GV_PPP_Entregados_Historico" h
),
uni as (select distinct on (np) np, tanda, m3, fe from fuentes where np <> '' and fe is not null order by np, pri, m3 desc),
dia as (select * from uni where fe between p_desde and p_hasta),
ev as (
  select upper(btrim(r.texto)) as tanda, r.opcion, r.ts_cliente
    from public."Registros_Produccion_Virgilio" r
   where r.opcion in ('EP','TP','AP','TAP') and coalesce(btrim(r.legajo), '') not in ('0','1')
     and btrim(coalesce(r.texto, '')) <> '' and r.ts_cliente >= (p_desde - interval '60 days')
),
pick as (select distinct on (tanda) tanda, opcion from ev where opcion in ('EP','TP') order by tanda, ts_cliente desc),
arm  as (select distinct on (tanda) tanda, opcion from ev where opcion in ('AP','TAP') order by tanda, ts_cliente desc),
salio as (   -- cargado al camión (CCN) o remito controlado (CRN) = salió, o sea armado sí o sí
  select distinct regexp_replace(upper(btrim(split_part(r.texto, '|', 1))), '\.0+$', '') as np
    from public."Registros_Produccion_Virgilio" r
   where r.opcion in ('CCN','CRN') and coalesce(btrim(r.legajo), '') not in ('0','1')
     and btrim(coalesce(r.texto, '')) <> ''
),
fact as (select distinct regexp_replace(upper(btrim(f.np)), '\.0+$', '') as np from public."Facturacion_NP" f),
est as (
  select d.fe, d.m3,
         case when s.np is not null then 'armado'
              when a.opcion = 'TAP'  then 'armado'
              when a.opcion = 'AP'   then 'armando'
              when p.opcion = 'TP'   then 'picking'
              when p.opcion = 'EP'   then 'pickeando'
              else 'sin' end as est,
         (fc.np is not null) as facturada
    from dia d
    left join salio s on s.np = upper(d.np)
    left join fact fc on fc.np = upper(d.np)
    left join pick  p on p.tanda = d.tanda and d.tanda <> ''
    left join arm   a on a.tanda = d.tanda and d.tanda <> ''
),
agg as (
  select fe,
         count(*)::int as pedidos,
         round(sum(m3), 3) as m3,
         count(*) filter (where est in ('armado','armando','picking'))::int as pick_ped,
         round(coalesce(sum(m3) filter (where est in ('armado','armando','picking')), 0), 3) as pick_m3,
         count(*) filter (where est = 'armado')::int as arm_ped,
         round(coalesce(sum(m3) filter (where est = 'armado'), 0), 3) as arm_m3,
         count(*) filter (where est in ('armando','picking','pickeando'))::int as curso_ped,
         round(coalesce(sum(m3) filter (where est in ('armando','picking','pickeando')), 0), 3) as curso_m3,
         count(*) filter (where est = 'sin')::int as sin_ped,
         round(coalesce(sum(m3) filter (where est = 'sin'), 0), 3) as sin_m3,
         count(*) filter (where est = 'armado' and facturada)::int as fact_ped,
         round(coalesce(sum(m3) filter (where est = 'armado' and facturada), 0), 3) as fact_m3
    from est group by fe
)
select g.fecha,
       coalesce(a.pedidos, 0), coalesce(a.m3, 0),
       coalesce(a.pick_ped, 0), coalesce(a.pick_m3, 0),
       coalesce(a.arm_ped, 0), coalesce(a.arm_m3, 0),
       coalesce(a.curso_ped, 0), coalesce(a.sin_ped, 0),
       public.gv_pct(a.pick_ped, a.pedidos),
       public.gv_pct(a.arm_ped,  a.pedidos),
       public.gv_pct(a.pick_ped, a.pedidos),
       public.gv_pct(a.arm_ped,  a.pedidos),
       public.gv_pct(a.pick_m3,  a.m3),
       public.gv_pct(a.arm_m3,   a.m3),
       'pedidos'::text,
       coalesce(a.curso_m3, 0), coalesce(a.sin_m3, 0),
       coalesce(a.fact_ped, 0), coalesce(a.fact_m3, 0),
       public.gv_pct(a.fact_ped,  a.arm_ped),
       public.gv_pct(a.curso_ped, a.pedidos),
       public.gv_pct(a.sin_ped,   a.pedidos)
  from (select generate_series(p_desde, p_hasta, interval '1 day')::date as fecha) g
  left join agg a on a.fe = g.fecha
 order by 1;
$function$
