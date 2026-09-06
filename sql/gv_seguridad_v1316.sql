-- v13.16 · 2026-09-05 (sábado a la noche) · hallazgos del agente auditor-supabase.
-- Aplicado en Virgilio (hrxfctzncixxqmpfhskv) como migración `gv_seguridad_rpc_gate_supervisor_v1316`
-- y la parte A/C de `gv_gate_supervisor_y_facturado_web_v1316`. Detalle y rollback en
-- docs/SUPABASE-GESTION-VIRGILIO.md §3.ac. Todo sobre objetos NUESTROS (gv_* / ppp_web_* / GV_*):
-- no toca nada que use Producción Virgilio.

-- 1) RPC del cruce de factura: sin anon (datos de facturación). El front las llama con sesión.
revoke execute on function public.gv_cruce_facturacion_resumen(date,date,text,text,text,integer,integer) from anon;
revoke execute on function public.gv_cruce_facturacion_totales(date,date,text) from anon;

-- 2) armado y simulador: sin anon (la Edge Function usa service_role; el front, sesión de supervisor).
revoke execute on function public.gv_ppp_web_armar_simular(text,date,jsonb,text[]) from anon;
revoke execute on function public.ppp_web_armar_tandas(text,date,jsonb,text[]) from anon;
revoke execute on function public.gv_ppp_web_tanda_avisos(text,text) from anon;

-- 3) tablas de sectores: anon sólo lee; authenticated escribe por la policy de supervisores (necesita el grant).
revoke insert, update, delete, truncate, references, trigger on
  public."GV_Sectores", public."GV_Barrios_Sector", public."GV_Sectores_Vecinos", public."GV_Barrios_Pares"
from anon;
revoke truncate, references, trigger on
  public."GV_Sectores", public."GV_Barrios_Sector", public."GV_Sectores_Vecinos", public."GV_Barrios_Pares"
from authenticated;

-- 4) Gate de supervisor para las dos SECURITY DEFINER que escriben la programación y que hasta
--    v13.15 aceptaban cualquier sesión con auth.uid() (413 sesiones anónimas en auth.users).
--    Pasa: los 3 mails de supervisor, service_role (Edge Function) y postgres (SQL editor / cron).
--    ⚠ `session_user`, NO `current_user`: adentro de una SECURITY DEFINER current_user es el dueño
--    (postgres) y el primer `or` dejaba pasar a cualquiera (primera versión de la migración, corregida
--    la misma noche en `gv_es_supervisor_session_user_v1316`). session_user no cambia con SET ROLE ni
--    con SECURITY DEFINER: es `authenticator` para todo lo que entra por la API, `postgres` para el
--    SQL editor y los crons.
create or replace function public.gv_es_supervisor_o_servicio()
returns boolean language sql stable set search_path = public, pg_temp as $$
  select session_user in ('postgres', 'supabase_admin')
      or coalesce(auth.jwt() ->> 'role', '') = 'service_role'
      or coalesce(auth.jwt() ->> 'email', '') = any (array['loekemeyer.n8n@gmail.com','loekemeyer.logistica@gmail.com','comexloekemeyer@gmail.com']);
$$;
revoke all on function public.gv_es_supervisor_o_servicio() from public, anon;
grant execute on function public.gv_es_supervisor_o_servicio() to authenticated, service_role;

-- 4.a) ppp_web_np_asignar: wrapper con gate (la lógica sigue en gv_ppp_web_np_asignar).
create or replace function public.ppp_web_np_asignar(p_empresa text, p_pares jsonb)
returns table(r_order_id bigint, r_np_idx integer, r_np integer)
language plpgsql security definer set search_path to 'public'
as $function$
begin
  -- v13.16: antes bastaba auth.uid() (cualquier sesión anónima). Ahora: supervisor, service_role o postgres.
  if not public.gv_es_supervisor_o_servicio() then
    raise exception 'Sólo supervisores pueden asignar números de NP.';
  end if;
  return query select * from public.gv_ppp_web_np_asignar(p_empresa, p_pares);
end
$function$;

-- 4.b) gv_ppp_web_tanda_programar: mismo gate al principio. El cuerpo completo (sin cambios
--      fuera del `if`) está en sql/gv_tandas_diarias.sql / la migración; acá sólo el bloque nuevo:
--
--   if not public.gv_es_supervisor_o_servicio() then
--     raise exception 'Sólo supervisores pueden programar tandas.';
--   end if;

-- 5) search_path fijo en las funciones gv_/ppp_web_ que no lo tenían (advisor "function_search_path_mutable").
do $$
declare r record;
begin
  for r in
    select p.oid, p.proname, pg_get_function_identity_arguments(p.oid) as args
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.prokind = 'f' and p.proconfig is null
       and (p.proname like 'gv\_%' or p.proname like 'ppp\_web\_%')
  loop
    execute format('alter function public.%I(%s) set search_path = public, pg_temp', r.proname, r.args);
  end loop;
end $$;

-- ── Rollback ──────────────────────────────────────────────────────────────────────────
-- grant execute on function public.gv_cruce_facturacion_resumen(date,date,text,text,text,integer,integer) to anon;
-- grant execute on function public.gv_cruce_facturacion_totales(date,date,text) to anon;
-- grant execute on function public.gv_ppp_web_armar_simular(text,date,jsonb,text[]) to anon;
-- grant execute on function public.ppp_web_armar_tandas(text,date,jsonb,text[]) to anon;
-- grant execute on function public.gv_ppp_web_tanda_avisos(text,text) to anon;
-- Para volver al gate viejo (cualquier sesión): reemplazar el `if` por `if auth.uid() is null then …`.
