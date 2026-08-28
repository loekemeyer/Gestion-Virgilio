-- =====================================================================
-- Hardening de seguridad — 2026-08-28 (ideas aceptadas por el usuario)
-- APLICADO en Supabase Virgilio (hrxfctzncixxqmpfhskv) vía apply_migration.
-- Este archivo es la copia versionada de lo que YA se aplicó (verificado).
-- =====================================================================

-- idea 1037 — 3 tablas con RLS off + grants abiertos a anon (no las usa el front
-- ni una vista). Enable RLS (deny-all sin policy) + revoke.
-- migración: rls_tablas_sin_rls_1037
alter table public."Uni_x_Articulo_x_Caja" enable row level security;
revoke all on public."Uni_x_Articulo_x_Caja" from anon, authenticated;
alter table public."EntregasProvAT_bkp_20260825" enable row level security;
revoke all on public."EntregasProvAT_bkp_20260825" from anon, authenticated;
alter table planify."_bak_tn_purge" enable row level security;
revoke all on planify."_bak_tn_purge" from anon, authenticated;

-- idea 8436 — http SSRF: los callers legítimos son SECURITY DEFINER (no afectados).
-- ⚠ NO APLICADO EFECTIVAMENTE: los grants de public.http_* pertenecen a
-- supabase_admin; el rol `postgres` (con el que corre el MCP / SQL editor) NO puede
-- revocarlos (revoke reporta success pero es no-op; el ACL sigue con anon=X). Para
-- cerrarlo hay que MOVER la extensión http fuera de `public` (a `extensions`) o pedirlo
-- por soporte de Supabase, en una ventana de mantenimiento (los definers la llaman como
-- public.http_get → habría que re-apuntarlos). QUEDA PENDIENTE.

-- idea 2758 — search_path mutable en 7 funciones (ninguna usa funciones de otro schema
-- sin calificar → no cambia comportamiento).
-- migración: hardening_search_path_view_grants_2758_7240_6932_5341
alter function public.rechazar_conteo(bigint, text, text)         set search_path = public, pg_temp;
alter function public.asignar_fleje_operario(integer, text, text) set search_path = public, pg_temp;
alter function public.refresh_stock_view()                        set search_path = public, pg_temp;
alter function public.generar_inconsistencias(date)               set search_path = public, pg_temp;
alter function public.notificar_alerta_pedido_web()               set search_path = public, pg_temp;
alter function public.descontar_kg_fleje(integer, real, text)     set search_path = public, pg_temp;
alter function public.procesar_conteo_alertas()                   set search_path = public, pg_temp;

-- idea 7240 — vista ppp_etapa_tanda a security_invoker (no la usa el front; tablas base
-- ya legibles por anon).
alter view public.ppp_etapa_tanda set (security_invoker = true);

-- idea 6932 — planify.admin_kv / premios: RLS YA estaba ON sin policy (deny-all). Se
-- limpian los grants inertes. Planify entra por RPCs SECURITY DEFINER / service_role.
revoke all on planify.admin_kv from anon, authenticated;
revoke all on planify.premios from anon, authenticated;

-- idea 5341 — usuarios.password_hash legible por anon + escritura anon abierta.
-- El revoke de columna NO alcanza si hay grant a nivel tabla → se revoca todo y se
-- re-otorga SELECT solo sobre columnas no sensibles. Login por validar_login() (definer).
-- migración: usuarios_lockdown_anon_5341
revoke all on public.usuarios from anon, authenticated;
grant select (id, usuario, es_maestro, activo, created_at, ultimo_login) on public.usuarios to anon, authenticated;
-- (además se dropearon las policies insert_all/update_all/delete_all de anon)

-- idea 1542 (parcial) — RPCs de notificación Telegram callable por anon = spam. Son
-- cron (sin args), no las llama el front. Revoke efectivo (funciones propias de postgres).
-- migración: revoke_telegram_spam_rpcs_1542
revoke execute on function public.notificar_falta_facturacion_1630_telegram() from anon, authenticated, public;
revoke execute on function public.notificar_faltantes_sin_completar_telegram() from anon, authenticated, public;
revoke execute on function public.notificar_marianela_print_facturar()        from anon, authenticated, public;
revoke execute on function public.notificar_pasaje_papeles_48h()              from anon, authenticated, public;
-- ⏳ La parte "recalculos" de 1542 (recalcular_matriz, reconciliar_stock_articulo_rt,
--    recalcular_maximo_por_cod, etc.) NO se tocó: podrían ser RPCs que el front invoca.
--    Verificar uso real por función antes de revocar.

-- =====================================================================
-- PENDIENTES (tocan apps fuera de este repo o exceden privilegios postgres):
--  · 8436 http SSRF — mover extensión (ver arriba).
--  · 6738 planify_employee_login / planify_maestro_login IGNORAN el password (bypass).
--         Corregir requiere saber si planify.employees tiene columna de password y NO
--         dejar afuera a la fuerza de trabajo → decisión de producto + front de Planify.
--  · 2221 brute-force validar_login / check_app_password (app_login en texto plano).
--         Necesita rate-limiting / cambio de app; app externa.
--  · 1712 fichadaqr_ficho_hoy — enumeración legajo→email sin auth. La app externa
--         FichadaQR podría llamarla como anon (idea 4961 la reemplaza). Revisar con eso.
--  · 4072 cp_* (portal proveedores) admin brute-forceable. App externa.
--  · 1431 prode_set_result con clave hardcodeada. Juego interno; cambiarla rompe su admin.
--  · 5035 5 triggers Telegram sin WHEN (eficiencia, impacto bajo; las funciones ya
--         auto-chequean). Agregar WHEN requiere leer cada función; se difiere.
-- =====================================================================

-- ✅ APLICADO 2026-08-28 — Idea 5035: WHEN clause en 5 triggers Telegram
-- (migración triggers_telegram_add_when_clause)
-- trg_carga_sin_control_telegram    → WHEN (NEW.opcion = 'CRA')
-- trg_facturacion_override_telegram → WHEN (NEW.opcion = 'FCO')
-- trg_ppp_error_telegram            → WHEN (NEW.opcion = 'PPE')
-- trg_recepcion_sin_planim_telegram → WHEN (NEW.opcion = 'RSP')
-- trg_sin_planim_telegram           → WHEN (NEW.opcion = 'PSP')
