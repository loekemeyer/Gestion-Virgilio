-- ============================================================================
-- FIX URGENTE 2026-08-31 — "los artículos recibidos no aparecen en MG"
-- ============================================================================
-- CAUSA RAÍZ (verificada con insert de prueba como anon + rollback):
--   El hardening de seguridad del 27/8 ~22:00 dejó a `stocks_carga_rapida`
--   con RLS habilitada y UNA sola policy (SELECT para anon).
--   El trigger `actualizar_saldo_trigger` (AFTER INSERT en Movimientos_Stock,
--   SECURITY INVOKER) upsertea `stocks_carga_rapida` corriendo COMO EL ROL
--   QUE INSERTA. Desde la app el rol es `anon` → el upsert viola RLS (42501)
--   → se cae TODO el insert a `Movimientos_Stock` que venga del front.
--
-- EFECTO:
--   - Última recepción con movimiento a_guardar: 27/8 13:48 (remito 37583).
--   - Recepciones del 28/8 (Rafael 0903/0904: 878, 053, 101, 315, 355, 551,
--     594) y del 31/8 (Pedernera 38374/38373: 544 ×51, 802 ×63) quedaron en
--     "Entregas Tallerista Virgilio" pero SIN movimiento a_guardar
--     → no aparecen en "Guardar a Góndola" (MG).
--   - Lo del cron/pipeline (service_role) siguió andando: bypassa RLS.
--   - Los mismos guardados MG / stockMove del front también fallaban; la app
--     los encoló en localStorage (vir_stock_pend) con client_id estable.
--
-- RECUPERACIÓN DE DATOS: NO backfillear a mano. Al abrir la app en los
--   celulares que cargaron, stockFlushPend() reintenta la cola con el MISMO
--   client_id (índice mov_stock_clientid_dedup) → sube todo sin duplicar.
--
-- FIX (correr en el SQL Editor de Supabase, proyecto hrxfctzncixxqmpfhskv):

alter function public.actualizar_saldo_trigger() security definer;
alter function public.actualizar_saldo_trigger() set search_path = public, pg_temp;

-- La tabla-cache la escribe SOLO el trigger (ahora como owner). Cerrar los
-- grants de escritura directa que quedaron abiertos a anon/authenticated
-- (hoy inertes por la RLS solo-SELECT, pero no deben estar):
revoke insert, update, delete, truncate on public.stocks_carga_rapida from anon, authenticated;

-- VERIFICACIÓN (debe terminar sin error; no persiste nada):
-- begin;
-- set local role anon;
-- insert into public."Movimientos_Stock" (cod_art, deposito, delta, tipo, ref, legajo, client_id)
-- values ('999', 'a_guardar', 1, 'recepcion', 'TEST-DIAG', '0', 'mst_diag_test_rollback');
-- rollback;
