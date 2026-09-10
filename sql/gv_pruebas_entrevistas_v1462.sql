-- v14.62 — Vista supervisor: qué candidatos hicieron la prueba con el legajo 600.  ✅ APLICADO 2026-09-10
-- Objeto NUEVO (prefijo gv_), security_invoker = true para respetar RLS.
-- Lee sólo lo del legajo de entrevista (es_legajo_entrevista => 600) y lo agrupa
-- por nombre de candidato + día.
--
-- ROLLBACK: drop view if exists public.gv_pruebas_entrevistas;

create or replace view public.gv_pruebas_entrevistas
with (security_invoker = true) as
select
  coalesce(nullif(btrim(r.gv_nombre_prueba), ''), '(sin nombre)') as candidato,
  (r.ts_cliente at time zone 'America/Argentina/Buenos_Aires')::date as dia,
  count(*)                                   as eventos,
  min(r.ts_cliente)                          as desde,
  max(r.ts_cliente)                          as hasta,
  string_agg(distinct r.opcion, ', ' order by r.opcion) as acciones
from public."Registros_Produccion_Virgilio" r
where public.es_legajo_entrevista(r.legajo)
group by 1, 2
order by dia desc, hasta desc;

comment on view public.gv_pruebas_entrevistas is
  'v14.62 — Candidatos de entrevista (legajo 600) por día: nombre, cantidad de eventos, ventana y acciones. security_invoker.';

grant select on public.gv_pruebas_entrevistas to anon, authenticated, service_role;
