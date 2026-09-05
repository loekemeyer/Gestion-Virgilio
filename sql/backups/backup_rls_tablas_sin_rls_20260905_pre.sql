-- Estado ANTES de la migración gv_rls_tablas_sin_rls_20260905 (idea 6309), 2026-09-05.
-- Las 11 tablas de public.* que estaban con RLS APAGADA (relrowsecurity=false):
--   Partes_Plasticas_bkp_codisis_20260904      grants anon/authenticated: ALL   (backup, sin uso en código)
--   Partes_Plasticas_bkp_proveedor_20260904    grants anon/authenticated: ALL   (backup, sin uso en código)
--   clientes_dto_backup_20260902               grants anon/authenticated: ALL   (backup, sin uso en código)
--   cobranzas_super_cadena_backup_20260902     grants anon/authenticated: ALL   (backup, sin uso en código)
--   precios_super_lk_backup_20260902           grants anon/authenticated: ALL   (backup, sin uso en código)
--   snap_costo_nombres_0903                    grants anon/authenticated: ALL   (snapshot, sin uso en código)
--   codigos_duales                             grants anon/authenticated: ALL   (la lee vista_saldos_stock — vista sin security_invoker, corre como owner)
--   cobranzas_escalones                        grants anon/authenticated: SELECT (la lee vista_deudores_documentos)
--   deudores_condiciones                       sin grants a anon/authenticated (la lee vista_deudores_documentos)
--   wa_grupo_listo                             grants anon/authenticated: ALL   (la usan funciones SECURITY DEFINER wa_*)
--   wa_np_snapshot                             grants anon/authenticated: ALL   (la lee vista_np_factura + funciones wa_*)
-- Ninguna tenía policies. Los grants NO se tocaron.
--
-- ROLLBACK (deja todo exactamente como estaba):
alter table public."Partes_Plasticas_bkp_codisis_20260904"   disable row level security;
alter table public."Partes_Plasticas_bkp_proveedor_20260904" disable row level security;
alter table public.clientes_dto_backup_20260902               disable row level security;
alter table public.cobranzas_super_cadena_backup_20260902     disable row level security;
alter table public.precios_super_lk_backup_20260902           disable row level security;
alter table public.snap_costo_nombres_0903                    disable row level security;
alter table public.codigos_duales                             disable row level security;
alter table public.cobranzas_escalones                        disable row level security;
alter table public.deudores_condiciones                       disable row level security;
alter table public.wa_grupo_listo                             disable row level security;
alter table public.wa_np_snapshot                             disable row level security;
drop policy if exists gv_select_all on public.codigos_duales;
drop policy if exists gv_select_all on public.cobranzas_escalones;
drop policy if exists gv_select_all on public.deudores_condiciones;
drop policy if exists gv_select_all on public.wa_grupo_listo;
drop policy if exists gv_select_all on public.wa_np_snapshot;
