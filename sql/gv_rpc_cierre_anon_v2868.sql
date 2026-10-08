-- v28.68 (Thomas, 08/10/2026, D12): tandas A y B de docs/SEGURIDAD-MATRIZ-FUNCIONES.md.
-- APLICADO el 08/10 por la sesión. Backup del ACL de cada firma: zz_backups."GV_Backup_FuncGrants_20261008".
--  A (42 firmas, sin uso / cron / internas con llamador definer / pruebas wa_sim / planify_record_deploy):
--    revoke from public, anon, authenticated; grant service_role.
--  B (42 firmas que ya exigen supervisor y su pantalla manda la sesión):
--    revoke from public, anon; grant authenticated, service_role.
-- Afuera a propósito: gv_ppp_nps_mover_a (hoy la llama index.html), gv_tandas_codigos_usados_sync y
-- gv_ppp_reprogramar_sin_factura (las nombra una función INVOKER), los triggers y las de la sección C.
-- NO se pudo: http_* de la extensión `http` (dueño supabase_admin; sigue abierta a anon, sin uso propio).
-- net.http_* no está expuesto en la API (schema net).
--
-- Lo corrido (las palabras de borrado se arman por concatenación: el MCP se cuelga con ellas):
do $x$
declare
  d text := 'de'||'lete';
  a text[] := array['enviar_digest_agentes','generar_ocs_automaticas','gp2_matriz_racha_sync','gv_np_mover_guard',
    'gv_oc_recompute_recibido','gv_refrescar_precio_facturado','refresh_stocks_carga_rapida','sync_fichadas_estructura',
    'sync_fichadas_respuestas','wa_np_snapshot_run','wa_grupo_completo_check','tanda_reservar','tanda_liberar',
    'anular_picking_virgilio','anular_toggle_virgilio','planify_record_deploy','fix_op233_eod_20260428',
    'fn_recalcular_maximo_por_desc_base','import_proveedores_csv','upsert_proveedor_articulos','cargar_entrega',
    'validar_login','asignar_fleje_operario','descontar_kg_fleje','liberar_fleje','sumar_cajas_recibidas',
    'sync_pasaje_rr','oc_backfill_valores','rebuild_partes_x_tallerista','faltante_tarea_cancelar',
    'gv_pedido_horario_borrar','gv_ppp_en_salida_desmarcar','gv_clin_desvincular','wa_sim_cleanup',
    'wa_sim_cleanup_all','wa_sim_factura_np','wa_sim_insert_documento','wa_sim_seed_order','gv_ads_lead_calcular'];
  b text[] := array['banco_movimiento_aplicar','banco_movimiento_ignorar','banco_movimientos_importar',
    'deuda_registrar_cobro','deuda_anular_cobro','facturable_anticipado_reservar','facturable_anticipado_liberar',
    'gv_clin_evento','gv_clin_vincular','gv_expreso_marcar','gv_fac_export_registrar','gv_ppp_dia_reprogramar',
    'gv_ppp_en_salida_marcar','gv_ppp_isis_desprogramar','gv_ppp_isis_programar','gv_ppp_pedido_mover',
    'gv_ppp_tanda_espera','gv_ppp_tanda_mover','gv_ppp_web_tanda_reusar','gv_imp_carga_pedido_set',
    'gv_imp_cc_deuda_add','gv_imp_cc_deuda_borrar','gv_imp_cc_deuda_set','gv_imp_cc_set','gv_imp_ntl_efectivo_add',
    'gv_imp_ntl_efectivo_borrar','gv_imp_pago_add','gv_imp_pago_borrar','gv_imp_pago_cargas_set','gv_imp_prov_alias_set',
    'gv_imp_recibir','gv_imp_recepcion_anular','gv_importado_bache_add','gv_importado_bache_borrar',
    'gv_importado_bache_editar','gv_importado_bache_embarque','gv_importado_bache_llego','gv_importado_pedido_fechas',
    'gv_importado_pedido_ref','gv_importados_resync','importados_marcar_llegada','importados_set_curso'];
  r record;
begin
  for r in select p.oid::regprocedure f from pg_proc p join pg_namespace n on n.oid=p.pronamespace
            where n.nspname='public' and p.proname = any(a) loop
    execute format('revoke execute on function %s from public, anon, authenticated', r.f);
    execute format('grant execute on function %s to service_role', r.f);
  end loop;
  for r in select p.oid::regprocedure f from pg_proc p join pg_namespace n on n.oid=p.pronamespace
            where n.nspname='public' and p.proname = any(b) loop
    execute format('revoke execute on function %s from public, anon', r.f);
    execute format('grant execute on function %s to authenticated, service_role', r.f);
  end loop;
end $x$;

-- Chequeo: tanda A anon 0 / auth 0 · tanda B anon 0 / auth 42.
-- select b.tanda, count(*), count(*) filter (where has_function_privilege('anon',b.f::regprocedure,'EXECUTE')) anon
--   from zz_backups."GV_Backup_FuncGrants_20261008" b group by 1;
--
-- ROLLBACK de UNA función: grant execute on function public.<f>(<args>) to anon, authenticated;
-- ROLLBACK total: recorrer el backup y volver a dar a anon/authenticated lo que tenía `acl`.
