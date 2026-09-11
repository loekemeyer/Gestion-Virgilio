-- v15.52 (2026-09-11) — Cajas ENTREGADAS por mes para un código: talleristas + proveedores AT.
-- Gemela de ventas_mensuales_cod (lo FACTURADO): el popup de Proyección (Stocks → Proy. caj/mes)
-- muestra las dos series lado a lado, mes → entregadas → barra → facturadas.
--
-- Objeto NUEVO con prefijo gv_: no toca nada de Producción. SECURITY INVOKER (anon ya lee las
-- dos tablas de entregas por la vista). Lee vista_historial_entregas, cuyo `fecha` es TEXT con
-- tres formatos mezclados: 'YYYY-MM-DD' (talleristas y prov AT con Dia_mes 'DD-MM'), 'DD/MM/YY'
-- (prov AT crudo) y basura ('|||'). Acá se parsea UNA vez, en el backend.
--
-- `cubierto` distingue "ese mes entregó 0" de "ese mes no había registro de ese circuito":
--   · prov AT   → Entregas Prov AT arranca el 04/06/2026
--   · tallerista → Entregas Tallerista Virgilio arranca 12/2025
-- El circuito del artículo se toma de sus propias entregas; si nunca entregó, del padrón
-- (Articulos x Prov AT → prov_at; Articulos Virgilio X Tallerista → tallerista).
--
-- Prueba:  select * from public.gv_entregas_mensuales_cod('321', 12);
--          → 2025-10..2026-05 cajas 0 cubierto false · 2026-06 506 · 07 500 · 08 382 · 09 150
--          select * from public.gv_entregas_mensuales_cod('031', 10);   -- tallerista, cubierto desde 12/2025
-- Rollback: drop function public.gv_entregas_mensuales_cod(text, integer);

create or replace function public.gv_entregas_mensuales_cod(p_cod text, p_meses integer default 12)
returns table(mes text, cajas numeric, cubierto boolean)
language sql
stable
security invoker
set search_path to 'public'
as $function$
with par as (
  select regexp_replace(upper(btrim(coalesce(p_cod, ''))), '^0+(?=.)', '') as ck,
         greatest(coalesce(p_meses, 12), 1) as n
),
ent as (
  select v.fuente,
         regexp_replace(upper(btrim(v.cod_art)), '^0+(?=.)', '') as ck,
         case
           when v.fecha ~ '^\d{4}-\d{2}-\d{2}'      then substr(v.fecha, 1, 7)
           when v.fecha ~ '^\d{1,2}/\d{1,2}/\d{2}$' then to_char(to_date(v.fecha, 'DD/MM/YY'), 'YYYY-MM')
           when v.fecha ~ '^\d{1,2}/\d{1,2}/\d{4}$' then to_char(to_date(v.fecha, 'DD/MM/YYYY'), 'YYYY-MM')
         end as mes,
         coalesce(v.cajas, 0) as cajas
  from public.vista_historial_entregas v
),
fnt as (
  select coalesce(
    (select e.fuente from ent e, par where e.ck = par.ck and e.mes is not null
       group by e.fuente order by count(*) desc limit 1),
    (select 'prov_at' from public."Articulos x Prov AT" a, par
       where regexp_replace(upper(btrim(a."Cod_Art")), '^0+(?=.)', '') = par.ck limit 1),
    (select 'tallerista' from public."Articulos Virgilio X Tallerista" t, par
       where regexp_replace(upper(btrim(t."Cod_Art")), '^0+(?=.)', '') = par.ck limit 1)
  ) as fuente
),
serie as (
  select to_char(d, 'YYYY-MM') as mes
  from par, generate_series(
    date_trunc('month', (now() at time zone 'America/Argentina/Buenos_Aires')::date) - ((par.n - 1) || ' months')::interval,
    date_trunc('month', (now() at time zone 'America/Argentina/Buenos_Aires')::date),
    interval '1 month') d
)
select s.mes,
       coalesce((select sum(e.cajas) from ent e, par where e.ck = par.ck and e.mes = s.mes), 0)::numeric,
       exists (select 1 from ent e, fnt where e.mes = s.mes and e.fuente = fnt.fuente)
from serie s
where exists (select 1 from par where par.ck <> '')
order by s.mes;
$function$;

comment on function public.gv_entregas_mensuales_cod(text, integer) is
  'v15.52 — cajas entregadas por mes de un codigo (vista_historial_entregas: talleristas + prov AT). cubierto=false => ese mes no hay registro de ese circuito, no es un cero real.';

grant execute on function public.gv_entregas_mensuales_cod(text, integer) to anon, authenticated;
