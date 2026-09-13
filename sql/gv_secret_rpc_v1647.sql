-- ============================================================================
-- v16.47 — gv_secret(): las Edge Functions de Gestion pueden leer secretos del
--          Vault en vez de hardcodearlos. Habilitador del problema 20.
-- Proyecto Supabase: hrxfctzncixxqmpfhskv
--
-- POR QUE
-- -------
-- El problema 20 son 11 Edge Functions con credenciales escritas en el codigo.
-- Para sacarlas de ahi hace falta un lugar donde ponerlas, y desde esta sesion NO
-- se pueden cargar env vars de Edge Functions (no existe la herramienta). La via
-- que si funciona es el Vault de Postgres + una RPC que solo pueda leer
-- service_role. Es exactamente el patron que ya usaba el proyecto LK con
-- `krikos_secret`, y el que se uso para cerrar el problema 21.
--
-- Esta es la version de Gestion, cerrada desde el arranque (a krikos_secret hubo
-- que verificarle los grants despues; a esta se le revocan en el mismo script).
--
-- MEDICION DEL PROBLEMA 20, antes de tocar nada
-- ----------------------------------------------
-- Se barrieron TODOS los blobs del historial de los dos repos PUBLICOS
-- (Gestion-Virgilio 305 commits, pagina-LK-copia 311 tras profundizar el shallow):
--   0 claves de OpenAI, 0 tokens de Meta, 0 SHEETS_SECRET, 0 URLs de Apps Script.
--   Los unicos JWT legacy en el historial son de rol "anon" (publica por diseno);
--   NINGUN service_role — se busco por el marcador del payload, no por la palabra
--   suelta (los 473 hits de "service_role" en LK son nombres de variable).
-- O sea que la exposicion es al BUNDLE de la funcion deployada, que solo lee quien
-- ya tiene acceso al proyecto. No es una filtracion a internet.
--
-- De paso se verifico que no hubiera un agujero peor: hay dos funciones que leen el
-- Vault y figuran como ejecutables por anon (fn_facturado_notif_wa,
-- fn_virgilio_entrega_to_formato). No lo son en la practica: devuelven `trigger`.
-- Comprobado como anon: "trigger functions can only be called as triggers", y
-- "permission denied for schema vault" al intentar leer el Vault directo.
--
-- OJO CON EL ORDEN (lo importante)
-- ---------------------------------
-- Mover un secreto del codigo al Vault NO lo rota: quien ya tuvo acceso al proyecto
-- ya lo vio. Para los secretos de TERCEROS (token de Meta WhatsApp, API key de
-- OpenAI) el orden correcto es:
--   1. rotar en la consola de Meta / OpenAI  (lo hace el dueno)
--   2. cargar el valor NUEVO en el Vault:
--        select vault.create_secret('<valor nuevo>', 'META_WA_TOKEN');
--        select vault.create_secret('<valor nuevo>', 'OPENAI_API_KEY');
--   3. redeployar las funciones leyendo gv_secret() y SIN el literal
-- Hacerlo al reves obliga a copiar el secreto viejo a mano —o sea a pasearlo por
-- una conversacion y un historial— para una credencial que igual hay que reemplazar.
-- ============================================================================

create or replace function public.gv_secret(p_name text)
returns text
language sql
security definer
set search_path to 'public', 'vault'
as $$
  select decrypted_secret from vault.decrypted_secrets
   where name = p_name
   order by created_at desc limit 1
$$;

comment on function public.gv_secret(text) is
  'Lee un secreto del Vault por nombre. SOLO service_role: la usan las Edge Functions para no '
  'hardcodear credenciales (problema 20). Espejo de krikos_secret del proyecto LK.';

revoke all on function public.gv_secret(text) from public, anon, authenticated;
grant execute on function public.gv_secret(text) to service_role;

-- Chequeo: anon y authenticated NO, service_role SI
-- select has_function_privilege('anon','public.gv_secret(text)','EXECUTE');          -- false
-- select has_function_privilege('service_role','public.gv_secret(text)','EXECUTE');  -- true
