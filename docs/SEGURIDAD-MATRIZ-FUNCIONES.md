# Matriz de seguridad: funciones que escriben y hoy acepta la clave pública (28/09/2026)

Proyecto `hrxfctzncixxqmpfhskv`. Alcance: funciones de `public` y `procesos` que `anon` puede ejecutar
y que en su cuerpo tienen `insert/update/delete/truncate` → **186 firmas (181 nombres)**. Solo lectura:
no se ejecutó nada. Plan de referencia: `docs/PLAN-LOGIN-OPERARIOS-RED.md`.

## Resumen

1. **186 firmas**: 27 trigger · 26 internas/cron (sin app) · 7 solo Edge Function/CI con `service_role` · 4 no escriben de verdad (solo tablas temporales o comentario) · 100 RPC que llama alguna app · 22 sin uso en código ni logs.
2. **Rol propuesto**: revocar 42 (trigger, sin uso, fixes, `http_delete`) · servicio 36 · operario 24 · supervisor 64 · admin 14 · token propio 2 (control-proveedores) · lectura 4 (fuera de esta matriz).
3. **Chequeo actual**: 44 ya exigen supervisor/servicio (`es_supervisor_virgilio` / `gv_es_supervisor_o_servicio`), 3 con token (`cp_save`, `cp_submit`, `gv_conc_cargar` parcial), **139 no chequean nada** (27 de ellas son triggers, donde no aplica).
4. **Se pueden cerrar YA, sin romper nada: 76 firmas** (tanda A abajo): 27 trigger + 17 internas/cron con llamador `SECURITY DEFINER` o cron + 25 sin uso/pruebas/`http_delete` + 5 de `procesos` (ni siquiera expuesto en la API) + `planify_record_deploy` ×2 (CI con `service_role`). Ninguna aparece en el código de una app con la clave pública ni en los logs de 24 h con clave pública.
5. **Tanda B, también sin riesgo: 42 firmas** que ya exigen supervisor en la base y cuya pantalla ya manda la sesión Google (logs: `authenticated`). Revocarles `anon` no cambia nada: hoy la clave pública ya es rechazada adentro.
6. **Trampa**: 6 internas (`actualizar_despiece`, `actualizar_partes_ps`, `actualizar_partes_tallerista`, `recalcular_stock_online_cajon_total`, `sync_partes_from_articulo`, `reconciliar_stock_articulo_rt`) las llama un trigger **SECURITY INVOKER**: revocarlas hoy rompe el INSERT/UPDATE con la clave pública en `SP Kg`, `SC Kg`, `Flejes`, `Entregas PS`, `Articulos Virgilio X Tallerista` y **`Registros_Produccion_Virgilio` (picking de la tablet)**. Primero pasar el trigger a `SECURITY DEFINER`.
7. **Más peligrosas hoy** (anon, sin chequeo, secdef): `gv_ppp_nps_mover_a` (mueve cualquier NP de tanda y toca `Facturacion_NP`), `wa_sim_cleanup_all` (borra en `isis_lk/isis_ch`, `Facturacion_NP`, programación), `http_delete` (el servidor hace pedidos HTTP a donde le digan), `fix_op233_eod_20260428` (re-ejecuta un parche sobre producción), `recalcular_matriz` / `anular_produccion` / `toggle_anular_tiempo` (reescriben premios en `db_n8n_espejo`), `insumo_borrar` / `insumo_recodificar` / `gv_supers_set`, `anular_modo_op` (borra una recepción y su stock), `racks_plani_*` / `registrar_baja_racks` (stock), `validar_login` (oráculo de contraseñas), `rc_alerta_recepcion_fleje` (manda texto libre a un grupo de Telegram; el token del bot está escrito en el cuerpo de la función).
8. **Lo que falta para el resto**: etapa 2 del plan (tablets de GV y Registro Producción con `login-operario`; pantallas de stock/insumos/supers de GV, el programa viejo `gestionproductivaentero` y la copia `cervantes-admin/entero` con sesión Google; macro de conciliación y Planify con clave de servidor).
9. **Logs usados**: `edge_logs` de las últimas 24 h (28/09 ~18:45 UTC hacia atrás, lunes). Lo que se usa una vez por semana puede no aparecer: por eso "sin uso" exige además **cero** referencias en código de los 30+ repos clonados.
10. **Admin**: hoy `usuarios_permitidos` tiene 1 `admin` y 1 `envios`; supervisores = `Supervisores_Virgilio` + 3 mails fijos. Antes de cerrar las de rol admin hay que cargar ahí quién es admin.

## Recetas (el "cambio" de cada fila apunta a una)

Helper propuesto (una sola vez, antes de la tanda C). `jwt_rol()` solo existe para operarios (Google no trae `app_metadata.rol`), así que el rol de un mail sale de la whitelist:

```sql
create or replace function public.rol_actual() returns text
language sql stable security definer set search_path = public as $$
  select case
    when coalesce(auth.jwt()->>'role','') = 'service_role' then 'servicio'
    when public.jwt_rol() is not null then public.jwt_rol()                       -- operario (login-operario)
    when public.get_role_for_email(auth.jwt()->>'email') = 'admin' then 'admin'
    when public.es_supervisor_virgilio() then 'supervisor'
  end $$;

create or replace function public.exigir_rol(p_minimo text) returns void
language plpgsql stable security definer set search_path = public as $$
declare r text := public.rol_actual();
  n int := case r when 'servicio' then 9 when 'admin' then 3 when 'supervisor' then 2 when 'operario' then 1 else 0 end;
  m int := case p_minimo when 'servicio' then 9 when 'admin' then 3 when 'supervisor' then 2 when 'operario' then 1 end;
begin
  if n < m then raise exception 'No autorizado (se requiere %)', p_minimo using errcode = '42501'; end if;
end $$;
revoke execute on function public.exigir_rol(text), public.rol_actual() from public, anon;
grant  execute on function public.exigir_rol(text), public.rol_actual() to authenticated, service_role;
```

| Receta | Qué es |
|---|---|
| **R-TRG** | `revoke execute on function <f> from public, anon, authenticated;` — un trigger no necesita EXECUTE para dispararse; nadie lo puede llamar como RPC igual. |
| **R-SVC** | `revoke execute on function <f> from public, anon, authenticated; grant execute on function <f> to service_role;` (cron corre como `postgres`, no se entera). |
| **R-DEAD** | Igual que R-SVC; opcional después: `drop function`. |
| **R-OP** | `revoke … from public, anon; grant … to authenticated;` + primera línea: `perform public.exigir_rol('operario');` |
| **R-OP+L** | R-OP + `if public.rol_actual()='operario' and p_legajo is distinct from public.jwt_legajo() then raise exception 'legajo ajeno' using errcode='42501'; end if;` (supervisor/admin pueden actuar por otro legajo). |
| **R-SUP** | `revoke … from public, anon; grant … to authenticated;` + `perform public.exigir_rol('supervisor');` (donde ya está `es_supervisor_virgilio()` basta con el revoke/grant). |
| **R-ADM** | Igual con `exigir_rol('admin')`. |
| **R-DEF** | Pasar el trigger/función que la llama a `SECURITY DEFINER set search_path=public` y recién ahí R-SVC. |

Nota: `revoke … from anon` solo no alcanza donde la ACL tiene `=X/postgres` (PUBLIC): **siempre revocar también de `public`**. Tres ya tienen `anon` sacado pero siguen abiertas por PUBLIC: `gv_ppp_dia_reprogramar`, `gv_importado_bache_embarque`, `gv_ppp_en_salida_desmarcar`.

Leyenda de logs 24 h: **PUB** = clave pública sola · **AUTH** = sesión (`authenticated`) · **SVC** = `service_role`. Origen: EMP = IP de las 3 plantas, DUEÑO = 181.105.135.47, SERV = nube (GitHub/AWS), OTRA = otra red. "0" = ninguna llamada POST en 24 h. Los OPTIONS (preflight CORS) no se cuentan.

## Tabla completa

### A. Se pueden cerrar YA (76 firmas) — no las llama ninguna app con la clave pública (código + logs)

| función(args) | tipo | quién la llama (código; logs 24h) | rol mínimo | chequeo actual | cambio | riesgo |
|---|---|---|---|---|---|---|
| public.actualizar_saldo_trigger() | trigger | trigger en `Movimientos_Stock`; 0 | revocar | ninguno | R-TRG | ninguno |
| public.exigir_foto_procesado() | trigger | `Control_Modo_OP`; 0 | revocar | ninguno | R-TRG | ninguno |
| public.fn_audit_matrices() | trigger | `Matrices` (auditoría); 0 | revocar | ninguno | R-TRG | ninguno |
| public.fn_sp_kg_stockini_ts() | trigger | `SP Kg`; 0 | revocar | ninguno | R-TRG | ninguno |
| public.fn_stock_ini_ts_flejes() | trigger | `Flejes`; 0 | revocar | ninguno | R-TRG | ninguno |
| public.fn_stock_ini_ts_remache() | trigger | `Remaches SC/SP`; 0 | revocar | ninguno | R-TRG | ninguno |
| public.fn_stock_ini_ts_underscore() | trigger | `Cajas`, `Partes_Plasticas`, `Sector Bombilla`; 0 | revocar | ninguno | R-TRG | ninguno |
| public.gp2_matriz_racha_trg_espejo() | trigger | `db_n8n_espejo`; 0 | revocar | ninguno | R-TRG | ninguno |
| public.gp2_matriz_racha_trg_planify() | trigger | `planify.matrices_ingresos`; 0 | revocar | ninguno | R-TRG | ninguno |
| public.gv_capacidad_sector_escribir() | trigger | `Capacidad_Sector`; 0 | revocar | ninguno | R-TRG | ninguno |
| public.gv_match_cod_a_programacion() | trigger | `lk_pedidos_match`; 0 | revocar | ninguno | R-TRG | ninguno |
| public.gv_ppp_web_super_tanda_sola() | trigger | `PPP_Web_Programacion`; 0 | revocar | ninguno | R-TRG | ninguno |
| public.gv_supers_sync() | trigger | `GV_Supers`; 0 | revocar | ninguno | R-TRG | ninguno |
| public.gv_uxb_protege_curado() | trigger | `GV_UxB` (Edge `sync-precios-venta` solo lo menciona); 0 | revocar | ninguno | R-TRG | ninguno |
| public.gv_web_cliente_un_solo_dia() | trigger | `PPP_Web_Programacion`; 0 | revocar | ninguno | R-TRG | ninguno |
| public.notificar_pedido_adelantado_telegram() | trigger | `Registros_Produccion_Virgilio`; 0 | revocar | ninguno | R-TRG | ninguno |
| public.notificar_recepcion_excede_oc_telegram() | trigger | `Registros_Produccion_Virgilio`; 0 | revocar | ninguno | R-TRG | ninguno |
| public.ppp_autozona() | trigger | `GV_PPP_Programacion_Diaria`; 0 | revocar | ninguno | R-TRG | ninguno |
| public.ppp_web_prog_touch() | trigger | `PPP_Web_Programacion`; 0 | revocar | lee mail (auditoría) | R-TRG | ninguno |
| public.procesar_conteo_alertas() | trigger | `Conteo_Stock`; 0 | revocar | ninguno | R-TRG | ninguno |
| public.sync_stock_desde_matrices() | trigger | `Matrices`; 0 | revocar | ninguno | R-TRG | ninguno |
| public.trg_articulos_delete() | trigger | `Articulos Virgilio X Tallerista`; 0 | revocar | ninguno | R-TRG | ninguno |
| public.trg_despiece_delete() | trigger | `Despiece x Articulo`; 0 | revocar | ninguno | R-TRG | ninguno |
| public.trg_facturado_no_negativo() | trigger | `Movimientos_Stock`; 0 | revocar | ninguno | R-TRG | ninguno |
| public.trg_gv_marca_manual() | trigger | `GV_PPP_Prog_Override`, `PPP_Web_Programacion`; 0 | revocar | lee mail | R-TRG | ninguno |
| public.trg_pkc_reconciliar_rt() | trigger | `Registros_Produccion_Virgilio`; 0 | revocar | ninguno | R-TRG (ojo: la que llama adentro, `reconciliar_stock_articulo_rt`, NO; ver sección C) | ninguno |
| public.wa_factura_notificar() | trigger | `isis_lk.documentos`, `isis_ch.documentos`; 0 | revocar | ninguno | R-TRG | ninguno |
| public.enviar_digest_agentes() | cron | cron `digest-agentes-virgilio`; 0 | servicio | ninguno | R-SVC | ninguno |
| public.generar_ocs_automaticas(p_forzar) | interna | `gv_oc_auto_corrida` (definer); 0 | servicio | ninguno | R-SVC | ninguno (hoy anon puede generar OC) |
| public.gp2_matriz_racha_sync(p_matriz) | cron | cron `gp2-matriz-racha-nocturno` + 2 triggers definer; 0 | servicio | ninguno | R-SVC | ninguno |
| public.gv_np_mover_guard(p_nps, p_tanda_destino, p_tanda_entera) | interna | `gv_ppp_nps_mover_a` (definer); 0 | servicio | ninguno | R-SVC | ninguno |
| public.gv_oc_recompute_recibido(p_nombre, p_cod) | cron | cron `gv-oc-anular-superadas` + 3 definer (`recepcion.js` solo en comentario); 0 | servicio | ninguno | R-SVC | ninguno |
| public.gv_ppp_nps_mover_a(p_nps, p_tanda, p_fecha, p_nota, p_tanda_entera) | interna | `gv_ppp_pedido_mover`/`tanda_mover`/`tanda_renombrar` (definer); 0 | servicio | **ninguno** | R-SVC | ninguno. **La más peligrosa**: mueve cualquier NP con la clave pública |
| public.gv_ppp_reprogramar_sin_factura(p_aplicar, p_fecha) | cron | cron `gv-reprog-sin-factura-18hs`; 0 | servicio | ninguno | R-SVC | ninguno (hoy anon puede reprogramar con `p_aplicar=true`) |
| public.gv_refrescar_precio_facturado() | cron | cron `gv-precio-facturado-diario`; 0 | servicio | ninguno | R-SVC | ninguno |
| public.gv_tandas_codigos_usados_sync(p_desde) | cron | cron `gv-tandas-codigos-usados` (en `gv_ppp_web_codigo_tomado` solo comentario); 0 | servicio | ninguno | R-SVC | ninguno |
| public.refresh_stocks_carga_rapida() | cron | cron `refresh_stocks_carga_rapida` + `gv_refresh_stock_si_cambio` (definer); 0 | servicio | ninguno | R-SVC | ninguno |
| public.sync_fichadas_estructura() | cron | cron `sync-fichadas-estructura` (`fichadas-monitor.html` solo comentario); 0 | servicio | ninguno | R-SVC | ninguno |
| public.sync_fichadas_respuestas() | cron | cron `sync-fichadas-respuestas`; 0 | servicio | ninguno | R-SVC | ninguno |
| public.wa_np_snapshot_run() | cron | cron `wa_np_snapshot`; 0 | servicio | ninguno | R-SVC | ninguno |
| public.wa_grupo_completo_check(p_np) | interna | `wa_np_facturado_trg` (definer); 0 | servicio | ninguno | R-SVC | ninguno |
| public.tanda_reservar(p_tanda, p_fase, p_legajo, p_nombre) | interna | `gv_ppp_tanda_renombrar` (definer); solo copias viejas `produccion-virgilio`, `producc-virg-qr-test` (GV usa `gv_tanda_reservar`); 0 | servicio | ninguno | R-SVC | solo si alguien abre la copia vieja de GV |
| public.tanda_liberar(p_tanda, p_fase, p_legajo) | interna | `anular_armado_virgilio`, `anular_picking_virgilio`, `gv_ppp_tanda_renombrar` (definer); copias viejas; 0 | servicio | ninguno | R-SVC | idem |
| public.anular_picking_virgilio(p_legajo, p_tanda) | rpc vieja | solo copias viejas (GV usa `gv_anular_picking_virgilio`); 0 | revocar | ninguno | R-DEAD | idem |
| procesos.area_id(p_area) | interna | funciones de `procesos`/`planify` (definer). `procesos` **no está expuesto** en la API | servicio | ninguno | R-SVC | ninguno |
| procesos.cargar_md(8 args) | interna | `procesos.cargar_staging`; no expuesto | servicio | ninguno | R-SVC | ninguno |
| procesos.cargar_staging(8 args) | sin uso API | agentes por SQL directo; no expuesto | servicio | ninguno | R-SVC | ninguno |
| procesos.marcar_revisada(6 args) | interna | `procesos.revisar_tarea`; no expuesto | servicio | ninguno | R-SVC | ninguno |
| procesos.upsert_seccion(8 args) | interna | `procesos.revisar_tarea`; no expuesto | servicio | ninguno | R-SVC | ninguno |
| public.planify_record_deploy(8 args) y (10 args) | servicio | workflows `planify/.github/workflows/build-deploy.yml`, `deploy-only.yml`; **SVC 9 SERV** | servicio | ninguno | R-SVC (2 firmas) | ninguno: el workflow ya manda `service_role` |
| public.fix_op233_eod_20260428() | sin uso | nadie; 0 | revocar | ninguno | R-DEAD → drop | ninguno. Hoy anon puede re-ejecutar el parche del 28/04 sobre `Registros Produccion Cervantes` y `db_n8n_espejo` |
| public.fn_recalcular_maximo_por_desc_base() | sin uso | nadie; apunta a `public.mi_tabla` que no existe; 0 | revocar | ninguno | R-DEAD → drop | ninguno |
| public.import_proveedores_csv(csv_text) | sin uso | nadie; 0 | revocar | ninguno | R-DEAD | ninguno |
| public.upsert_proveedor_articulos(p_nombre, p_tipo, p_articulos) | sin uso | nadie; 0 | revocar | ninguno | R-DEAD | ninguno |
| public.cargar_entrega(7 args) | sin uso | nadie (`entregas_cervantes_v2`); 0 | revocar | valida `p_usuario_id` activo | R-DEAD | ninguno |
| public.validar_login(p_usuario, p_password) | sin uso | nadie; 0 | revocar | — | R-DEAD | ninguno. Hoy es un oráculo de contraseñas de `public.usuarios` abierto a anon |
| public.asignar_fleje_operario(p_entrada_id, p_legajo, p_matriz) | sin uso | nadie; 0 | revocar | ninguno | R-DEAD | ninguno |
| public.descontar_kg_fleje(p_entrada_id, p_kg, p_evento_id) | sin uso | nadie; 0 | revocar | ninguno | R-DEAD | ninguno |
| public.liberar_fleje(p_entrada_id, p_kg_restante) | sin uso | nadie; 0 | revocar | ninguno | R-DEAD | ninguno |
| public.sumar_cajas_recibidas(p_cod, p_cod_tallerista, p_cajas) | sin uso | nadie; escribe `Partes x Tallerista` (derivada); 0 | revocar | ninguno | R-DEAD | ninguno |
| public.sync_pasaje_rr() | sin uso | se sacó en `pasaje-papeles.js` v4.7; 0 | revocar | ninguno | R-DEAD | ninguno |
| public.oc_backfill_valores(p_solo_null) | sin uso | nadie ni cron; 0 | servicio | ninguno | R-SVC | ninguno |
| public.rebuild_partes_x_tallerista() | sin uso | nadie; borra y rearma la derivada; 0 | servicio | ninguno | R-SVC | ninguno |
| public.faltante_tarea_cancelar(p_id) | sin uso | nadie; 0 | supervisor | ninguno | R-SUP | ninguno |
| public.gv_pedido_horario_borrar(p_empresa, p_clave, p_por) | sin uso | nadie (GV solo usa `_set`); 0 | supervisor | ninguno | R-SUP | ninguno |
| public.gv_ppp_en_salida_desmarcar(p_nps, p_por) | sin uso | nadie; 0 (anon sacado pero abierta por PUBLIC) | supervisor | ok (supervisor/servicio) | R-SUP (revoke from public) | ninguno |
| public.gv_clin_desvincular(4 args) | sin uso | nadie; 0 | supervisor | ok (supervisor/servicio) | R-SUP | ninguno |
| public.wa_sim_cleanup() | prueba | nadie; 0 | revocar | ninguno | R-SVC | ninguno |
| public.wa_sim_cleanup_all() | prueba | Edge `lk_notif-sim` (GestOpClientes) con **service_role**; 0 | servicio | **ninguno** | R-SVC | ninguno. Hoy anon borra en `isis_*.documentos`, `Facturacion_NP`, programación |
| public.wa_sim_factura_np(p_cuit, p_np) | prueba | Edge `lk_notif-sim` (service_role); 0 | servicio | ninguno | R-SVC | ninguno |
| public.wa_sim_insert_documento(9 args) | prueba | Edge `lk_notif-sim` (service_role); 0 | servicio | ninguno | R-SVC | ninguno |
| public.wa_sim_seed_order(4 args) y (5 args) | prueba | Edge `lk_notif-sim` (service_role); 0 | servicio | ninguno | R-SVC (2 firmas) | ninguno |
| public.http_delete(uri) y (uri, content, content_type) | extensión | nadie por API; 0 | revocar | — | R-SVC (2 firmas). Revisar igual `http_get/post/put/patch/head` de la extensión `http`: mismo agujero, no entran acá porque no dicen "delete" | ninguno (GP2 usa `http_get` desde funciones definer) |

### B. Sin riesgo también ahora: ya exigen supervisor y la pantalla ya manda sesión (42 firmas)

Solo falta `revoke … from public, anon; grant … to authenticated` (el chequeo ya está). Llamador: `gestion-virgilio/index.html`.

| función(args) | tipo | quién la llama (código; logs 24h) | rol mínimo | chequeo actual | cambio | riesgo |
|---|---|---|---|---|---|---|
| public.banco_movimiento_aplicar(4 args) | rpc | GV Cobranzas, `sb.rpc` (sesión); 0 | supervisor | ok (`es_supervisor_virgilio`) | R-SUP (solo grants) | ninguno |
| public.banco_movimiento_ignorar(3 args) | rpc | idem; 0 | supervisor | ok | R-SUP | ninguno |
| public.banco_movimientos_importar(5 args) | rpc | idem; 0 | supervisor | ok | R-SUP | ninguno |
| public.deuda_registrar_cobro(8 args) | rpc | idem; 0 | supervisor | ok | R-SUP | ninguno |
| public.deuda_anular_cobro(p_id, p_por) | rpc | idem; 0 | supervisor | ok | R-SUP | ninguno |
| public.facturable_anticipado_reservar(4 args) | rpc | idem; 0 | supervisor | ok | R-SUP | ninguno |
| public.facturable_anticipado_liberar(p_id, p_por) | rpc | idem; 0 | supervisor | ok | R-SUP | ninguno |
| public.gv_clin_evento(9 args) | rpc | GV Clientes nuevos (`aprRpc`, sesión); AUTH 1 EMP | supervisor | ok | R-SUP | ninguno |
| public.gv_clin_vincular(8 args) | rpc | idem; 0 | supervisor | ok | R-SUP | ninguno |
| public.gv_expreso_marcar(4 args) | rpc | GV PPP expreso (`aprRpc`); 0 | supervisor | ok | R-SUP | ninguno |
| public.gv_fac_export_registrar(8 args) | rpc | GV Facturación (`facRpc`, sesión); AUTH 3 EMP | supervisor | ok (`gv_es_supervisor_o_servicio`) | R-SUP | ninguno |
| public.gv_ppp_dia_reprogramar(4 args) | rpc | GV PPP (`aprRpc`); AUTH 10 EMP | supervisor | ok | R-SUP (anon ya sacado; falta `public`) | ninguno |
| public.gv_ppp_en_salida_marcar(4 args) | rpc | GV PPP (`aprRpc`); 0 | supervisor | ok | R-SUP | ninguno |
| public.gv_ppp_isis_desprogramar(3 args) | rpc/interna | GV PPP + `gv_cuarentena_devolver` etc. (definer); 0 | supervisor | ok | R-SUP | ninguno |
| public.gv_ppp_isis_programar(3 args) | rpc | GV PPP (`aprRpc`); 0 | supervisor | ok | R-SUP | ninguno |
| public.gv_ppp_pedido_mover(5 args) | rpc | GV PPP (`aprRpc`); AUTH 4 EMP | supervisor | ok | R-SUP | ninguno |
| public.gv_ppp_tanda_espera(3 args) | rpc | GV PPP (`aprRpc`); 0 | supervisor | ok | R-SUP | ninguno |
| public.gv_ppp_tanda_mover(5 args) | rpc | GV PPP (`aprRpc`); AUTH 35 EMP + AUTH 2 DUEÑO | supervisor | ok | R-SUP | ninguno |
| public.gv_ppp_web_tanda_reusar(4 args) | rpc | GV PPP web (`aprRpc`) + `gv_ppp_web_armar_pendientes` (servicio); 0 | supervisor | ok | R-SUP | ninguno (el armador usa `sb_secret`) |
| public.gv_imp_carga_pedido_set(5 args) | rpc | GV Importación (`_pedImpRpc` con sesión); 0 | supervisor | ok | R-SUP | ninguno |
| public.gv_imp_cc_deuda_add(10 args) | rpc | idem; 0 | supervisor | ok | R-SUP | ninguno |
| public.gv_imp_cc_deuda_borrar(p_id) | rpc | idem; 0 | supervisor | ok | R-SUP | ninguno |
| public.gv_imp_cc_deuda_set(p_id, p_campo, p_valor) | rpc | idem; 0 | supervisor | ok | R-SUP | ninguno |
| public.gv_imp_cc_set(14 args) | rpc | idem; 0 | supervisor | ok | R-SUP | ninguno |
| public.gv_imp_ntl_efectivo_add(6 args) | rpc | idem; 0 | supervisor | ok | R-SUP | ninguno |
| public.gv_imp_ntl_efectivo_borrar(p_id) | rpc | idem; 0 | supervisor | ok | R-SUP | ninguno |
| public.gv_imp_pago_add(10 args) | rpc | idem; 0 | supervisor | ok | R-SUP | ninguno |
| public.gv_imp_pago_borrar(p_pago_id) | rpc | idem; 0 | supervisor | ok | R-SUP | ninguno |
| public.gv_imp_pago_cargas_set(3 args) | rpc | idem; 0 | supervisor | ok | R-SUP | ninguno |
| public.gv_imp_prov_alias_set(3 args) | rpc | idem; 0 | supervisor | ok | R-SUP | ninguno |
| public.gv_imp_recibir(8 args) | rpc | idem (recepción de importados); 0 | supervisor | ok | R-SUP | ninguno |
| public.gv_imp_recepcion_anular(p_id, p_motivo) | rpc | idem; 0 | supervisor | ok | R-SUP | ninguno |
| public.gv_importado_bache_add(6 args) | rpc | idem; 0 | supervisor | ok | R-SUP | ninguno |
| public.gv_importado_bache_borrar(p_bache_id) | rpc | idem; 0 | supervisor | ok | R-SUP | ninguno |
| public.gv_importado_bache_editar(4 args) | rpc | idem; 0 | supervisor | ok | R-SUP | ninguno |
| public.gv_importado_bache_embarque(p_bache_id, p_embarque) | rpc | idem; 0 | supervisor | ok | R-SUP (anon ya sacado; falta `public`) | ninguno |
| public.gv_importado_bache_llego(3 args) | rpc | idem; 0 | supervisor | ok | R-SUP | ninguno |
| public.gv_importado_pedido_fechas(6 args) | rpc | idem; 0 | supervisor | ok | R-SUP | ninguno |
| public.gv_importado_pedido_ref(3 args) | rpc | idem; 0 | supervisor | ok | R-SUP | ninguno |
| public.gv_importados_resync(p_importado_id) | rpc/interna | idem + 7 funciones `gv_imp*` (definer); 0 | supervisor | ok | R-SUP | ninguno |
| public.importados_marcar_llegada(3 args) | rpc | idem; 0 | supervisor | ok | R-SUP | ninguno |
| public.importados_set_curso(p_id, p_uni) | rpc | idem; 0 | supervisor | ok | R-SUP | ninguno |

(`gv_ppp_dia_reprogramar` y `gv_importado_bache_embarque` ya no tienen `anon` explícito pero siguen abiertas por PUBLIC.)

### C. Internas llamadas por un trigger INVOKER: cerrar DESPUÉS de pasar el llamador a definer (6)

| función(args) | tipo | quién la llama | rol mínimo | chequeo actual | cambio | riesgo si se revoca hoy |
|---|---|---|---|---|---|---|
| public.actualizar_despiece() | interna | `trg_recalcular_pesos` (invoker) en `SP Kg`, `SC Kg`, `Flejes`, `Remaches SC/SP`, `SectorPlasticos` | servicio | ninguno | R-DEF sobre `trg_recalcular_pesos`, después R-SVC | se cae todo INSERT/UPDATE de pesos hecho con clave pública (programa viejo, `cervantes-admin/entero`) |
| public.actualizar_partes_ps() | interna | idem | servicio | ninguno | idem | idem |
| public.actualizar_partes_tallerista() | interna | idem | servicio | ninguno | idem | idem |
| public.recalcular_stock_online_cajon_total() | interna | `trg_recalcular_stock_online_cajon_total` (invoker) en `Entregas PS`, `Envios a Talleristas`, `SP Kg` | servicio | ninguno | R-DEF, después R-SVC | se caen las cargas de Entregas PS / Envíos a Talleristas con clave pública |
| public.sync_partes_from_articulo(p_id) | interna | `trg_articulos_insert/update` y `sync_partes_from_codigo` (invoker) | servicio | ninguno | R-DEF sobre los 3, después R-SVC | se cae el ABM de `Articulos Virgilio X Tallerista` / `Despiece x Articulo` |
| public.reconciliar_stock_articulo_rt(p_tanda, p_cod_raw) | interna | `trg_pkc_reconciliar_rt` (invoker) en `Registros_Produccion_Virgilio`; `gv_ppp_pedido_llevar_registro` solo comentario | servicio | ninguno | R-DEF sobre `trg_pkc_reconciliar_rt`, después R-SVC | **se cae el picking de la tablet de GV** (inserta PKC con clave pública) |

### D. No escriben de verdad (solo tablas temporales o la palabra está en un comentario) — van con las lecturas, etapa 5 (4)

| función(args) | tipo | quién la llama (logs) | rol mínimo | chequeo | cambio | riesgo |
|---|---|---|---|---|---|---|
| public.generar_inconsistencias(p_dia) | rpc lectura | GV Producción (`fetch` con clave pública); **PUB 38 EMP** | lectura (supervisor) | ninguno | ninguno por ahora; etapa 5 | cerrar hoy rompe el informe de inconsistencias |
| public.gv_ancla_demora_paradas(9 args) | interna lectura | `gv_ancla_demora_resumen` (invoker) | lectura | ninguno | ninguno | romper el cálculo de demora de ancla |
| public.gv_ppp_web_agrupar_geo(p_paradas) | interna lectura | `gv_ppp_web_sombra(_detalle)` (invoker); en GV solo comentario | lectura | ninguno | ninguno | idem sombra PPP |
| public.gv_evento_tanda_campo(p_opcion) | interna pura | `gv_evento_tanda_idx` (invoker) | lectura | ninguno | ninguno | puede estar en un índice/columna: no tocar |

### E. Operario (24 + `marcar_auditoria_visto`, que es de supervisor) — tablet de GV (botonera Virgilio / Cervantes) y Registro Producción 2.0. Cerrar después de la etapa 2

| función(args) | tipo | quién la llama (código; logs 24h) | rol mínimo | chequeo actual | cambio | riesgo si se aplica antes de la etapa 2 |
|---|---|---|---|---|---|---|
| public.registrar_unidades(p_n_matriz, p_cantidad, p_completar, p_legajo, p_evento_id) | rpc | Registro Producción 2.0 `app.js`, `gestion-virgilio/cervantes/app.js`, programa viejo `RegistroApp/app.js` (3 copias); 0 | operario | ninguno | R-OP+L | no se registran unidades por cajón en ninguna tablet de producción |
| public.asignar_matriz_balancin(p_balancin, p_matriz) | rpc | Registro Producción 2.0 `app.js`, `gestion-virgilio/cervantes/app.js` (botón CM); 0 | operario | ninguno | R-OP | CM no asigna la matriz al balancín |
| public.anular_armado_virgilio(p_legajo, p_tanda, p_motivo) | rpc | GV `index.html` (fetch, clave pública); **PUB 1 EMP** | operario | ninguno | R-OP+L (supervisor puede por otro) | el operario no puede deshacer un armado |
| public.anular_toggle_virgilio(p_legajo, p_opcion) | rpc | GV `index.html` (clave pública); **PUB 2 EMP** | operario | ninguno | R-OP+L | no se puede cerrar/deshacer sesión de tarea |
| public.gv_anular_picking_virgilio(p_legajo, p_tanda) | rpc | GV `index.html` (clave pública); 0 | operario | ninguno | R-OP+L | no se puede anular un picking fantasma |
| public.anular_modo_op(p_id) | rpc | GV `recepcion.js` (`supabase.rpc`, clave pública) | operario | **ninguno** (borra recepción + stock por id) | R-OP + validar que la fila `Control_Modo_OP` sea del `jwt_legajo()` y < 15 min, si no supervisor | recepción RT no puede anular |
| public.gv_tanda_reservar(p_tanda, p_fase, p_legajo, p_nombre) | rpc | GV `index.html` `tandaReservar` (clave pública); **PUB 22 EMP** | operario | ninguno | R-OP+L | nadie puede tomar una tanda (picking/armado paran) |
| public.gv_tanda_completar(p_tanda, p_fase, p_legajo) | rpc | GV `index.html` (clave pública); **PUB 9 EMP** | operario | ninguno | R-OP+L | no se cierran tandas |
| public.gv_tanda_lock_anular(p_tanda, p_fase, p_legajo) | rpc | GV `index.html` (clave pública) + `anular_armado_virgilio` (definer); **PUB 1 EMP** | operario | ninguno | R-OP+L | no se libera una tanda tomada |
| public.faltante_tarea_crear(7 args) | rpc | GV `index.html` (`_faltRpc`, clave pública) + agente `agentes-operativos/faltantes_agent.py` (service key) + `detectar_faltantes_llegaron` (definer); 0 | operario | ninguno | R-OP | no se generan tareas de faltantes desde la tablet |
| public.faltante_tarea_asignar(p_id, p_legajo, p_nombre) | rpc | GV `index.html` (`_faltRpc`); 0 | operario | ninguno | R-OP+L | no se toman tareas de faltante |
| public.faltante_tarea_soltar(p_id, p_legajo) | rpc | GV `index.html` (`_faltRpc`); 0 | operario | ninguno | R-OP+L | idem soltar |
| public.faltante_tarea_completar(p_id) | rpc | GV `index.html` (`_faltRpc`); 0 | operario | ninguno | R-OP + la tarea debe estar asignada al `jwt_legajo()` | idem completar |
| public.cp_completar_faltante(p_id, p_qty) | rpc | GV `index.html` `cpReduceFaltante` (clave pública); 0 | operario | ninguno | R-OP | completar faltantes en pedido se cae |
| public.cp_reducir_faltante_cap(p_id, p_qty) | rpc | GV `index.html` `cpConfirm` (clave pública); 0 | operario | ninguno | R-OP | idem |
| public.reasignar_cajas(p_target_id, p_qty, p_donor_id) | rpc | GV `index.html` `_rcConfirmInner` (clave pública) | operario | ninguno | R-OP | reasignar cajas entre pedidos se cae |
| public.racks_plani_ingreso(6 args) | rpc | GV `index.html` ingreso a racks (clave pública); 0 | operario | ninguno | R-OP+L | ingreso a racks (planimetría) se cae |
| public.racks_plani_ingreso_nacional(7 args) | rpc | idem; 0 | operario | ninguno | R-OP+L | idem nacional |
| public.racks_plani_mover(5 args) | rpc | GV `index.html` `mvConfirmar` (clave pública); 0 | operario | ninguno | R-OP | mover entre racks se cae |
| public.registrar_baja_racks(p_items) | rpc | GV `index.html` `stockFlushPend` (clave pública); **PUB 6 EMP** | operario | ninguno | R-OP | bajadas de rack se cae |
| public.nuevo_insumo_tmp(p_detalle, p_categoria, p_legajo) | rpc | GV `index.html` `insCrearTmp` (clave pública); 0 | operario | ninguno | R-OP+L | alta de insumo provisorio desde la tablet se cae |
| public.rc_alerta_recepcion_fleje(p_text, p_dedup) | rpc | programa viejo `StockFlejes/recepcion.html` (+ copias `cervantes-admin/entero|gp2`); 0 | operario | ninguno (manda texto libre a Telegram; token del bot en el cuerpo) | R-OP; mover el token a un secreto (Vault) | aviso de diferencia de flejes se cae |
| public.rc_set_conteo(p_tipo, p_det_id, p_vals) | rpc | programa viejo `Relevamiento/relevamiento.js` (+ `cervantes-admin/entero`); 0 | operario | ninguno | R-OP | relevamiento de conteo (programa viejo) se cae |
| public.marcar_auditoria_visto(p_id, p_visto, p_nota, p_legajo) | rpc | programa viejo `Produccion/monitor.html` (+ 2 copias); 0 | supervisor* | ninguno | R-SUP (*es pantalla de monitor; si la usa un encargado con legajo, R-OP+L) | el monitor no marca auditorías |
| public.gv_insumo_ubicaciones_guardar(p_cod, p_items) | rpc | GV `index.html` `_stkInsUbicSync` (clave pública); 0 | operario | ninguno | R-OP | guardar ubicaciones de insumo se cae |

### F. Supervisor (17 que hoy no chequean nada)

| función(args) | tipo | quién la llama (código; logs 24h) | rol mínimo | chequeo actual | cambio | riesgo si se aplica antes de que la pantalla mande sesión |
|---|---|---|---|---|---|---|
| public.aceptar_conteo(p_conteo_id, p_admin_legajo) | rpc | GV Stock `stkAceptarConteo` (clave pública); 0 | supervisor | ninguno (el legajo admin viene del cliente) | R-SUP; tomar el "quién" del JWT, no de `p_admin_legajo` | no se aprueban conteos |
| public.rechazar_conteo(p_conteo_id, p_admin_legajo, p_razon) | rpc | idem; 0 | supervisor | ninguno | idem | idem |
| public.faltante_resolver(5 args) | rpc | GV Stock `stkFaltFactDo` (clave pública); 0 | supervisor | ninguno | R-SUP | resolver faltantes facturados se cae |
| public.corr_convertir_faltante(p_np, p_sec, p_ppal) | rpc | GV Correcciones (`facAuthWriteHeaders`, ya manda sesión); 0 | supervisor | ninguno | R-SUP | ninguno si la sesión está (ya la manda) |
| public.gv_conciliacion_registrar(p_np) | rpc | GV Facturación (sesión); **AUTH 11 EMP** | supervisor | ninguno | R-SUP | ninguno (ya manda sesión) |
| public.gv_oc_generar_pendientes(p_rows) | rpc | GV OC (`facAuthWriteHeaders`, sesión); 0 | supervisor | ninguno | R-SUP | ninguno (ya manda sesión) |
| public.gv_pedido_horario_set(7 args) | rpc | GV PPP badge horario (`aprRpc`, sesión); 0 | supervisor | ninguno | R-SUP | ninguno (ya manda sesión) |
| public.zona_barrio_set(p_barrio, p_zona) | rpc | GV PPP (fetch clave pública); 0 | supervisor | ninguno | R-SUP | asignar barrio→zona se cae |
| public.gv_conc_cargar(p_banco, p_anio, p_filas, p_archivo, p_token) | rpc | macro Excel `docs/conciliacion-bancaria/ConciliacionSupabase.bas` (clave pública + token); **PUB 9 EMP** | supervisor / servicio | parcial: token de `GV_Conc_Token` **o** supervisor | que la macro use clave de servidor (`sb_secret` guardada en la PC, no en el .bas) y dejar el token como segundo factor; después R-SUP | **la macro de conciliación deja de cargar** |
| public.marcar_revisado(row_id) | rpc | programa viejo `Disruptivas/disruptivas.js` (+ `cervantes-admin/entero|gp2`); **PUB 2 OTRA (2 errores)**. (GP2 llama a `GP2.marcar_revisado`, otra función) | supervisor | ninguno | R-SUP | Disruptivas del programa viejo |
| public.anular_produccion(9 args) | rpc | idem (reescribe premio/tiempos en `db_n8n_espejo`); 0 | supervisor | **ninguno** | R-SUP | idem |
| public.toggle_anular_tiempo(row_id) | rpc | programa viejo `Produccion/tiempos.html` (+ 2 copias); 0 | supervisor | ninguno | R-SUP | Tiempos del programa viejo |
| public.rc_borrar(p_relevamiento_id) | rpc | programa viejo `Relevamiento/relevamiento.js`; 0 | supervisor | ninguno | R-SUP | borrar relevamiento (programa viejo) |
| public.planify_recruit_set_estado(p_id, p_status) | rpc | Planify escritorio `main.js` (`_recruitRpc`, clave pública); 0 | supervisor (Planify maestro) | ninguno | tanda Planify: clave de servidor en el main process de Electron, luego R-SVC; o `planify_is_maestro` | Reclutamiento de Planify |
| public.planify_recruit_set_calif(p_id, p_calif) | rpc | idem; 0 | supervisor | ninguno | idem | idem |
| public.planify_recruit_set_archivado(p_id, p_val) | rpc | idem; 0 | supervisor | ninguno | idem | idem |
| public.planify_recruit_set_search(p_id, p_search_id) | rpc | idem; 0 | supervisor | ninguno | idem | idem |
| (más las 42 de la tanda B y 4 de la tanda A, que ya chequean o no se usan) | | | | | | |

### G. Admin (14 firmas) — maestros, configuración, recálculos

| función(args) | tipo | quién la llama (código; logs 24h) | rol mínimo | chequeo actual | cambio | riesgo si se aplica antes |
|---|---|---|---|---|---|---|
| public.recalcular_matriz(p_matriz, p_nuevo_tiempo) | rpc | programa viejo `Produccion/tiempos.html` (+ 2 copias en `cervantes-admin`); 0 | admin | **ninguno** (recalcula premios de toda la historia de una matriz) | R-ADM | cambiar tiempo histórico desde el programa viejo |
| public.insumo_alta(5 args) | rpc | GV Stock insumos (`_stkInsRpc`, clave pública, `p_legajo:"admin"` fijo); 0 | admin | ninguno | R-ADM | ABM insumos se cae |
| public.insumo_borrar(p_cod) | rpc | idem; 0 | admin | ninguno | R-ADM | idem |
| public.insumo_editar(6 args) | rpc | idem + `gv_insumo_ubicaciones_guardar` (definer); 0 | admin | ninguno | R-ADM | idem |
| public.insumo_recodificar(p_cod, p_nuevo) | rpc | idem (reescribe `Movimientos_Stock`); 0 | admin | ninguno | R-ADM | idem |
| public.insumo_identificar(4 args) y (5 args) | rpc | GV `stkInsAceptar` (clave pública); 0 | admin | ninguno | R-ADM (2 firmas) | idem |
| public.insumo_factores_guardar(p_cod, p_factores) | rpc | GV Stock insumos; 0 | admin | ninguno | R-ADM | idem |
| public.insumo_cat_guardar(5 args) y (6 args) | rpc | GV Stock insumos; 0 | admin | ninguno | R-ADM (2 firmas) | idem |
| public.insumo_cat_borrar(p_clave) | rpc | idem; 0 | admin | ninguno | R-ADM | idem |
| public.insumo_unidad_guardar(p_nombre, p_activa) | rpc | idem; 0 | admin | ninguno | R-ADM | idem |
| public.gv_supers_set(7 args) | rpc | GV PPP lista de súper (`pppSupersRpc`, clave pública); 0 | admin | ninguno | R-ADM | editor de súper se cae |
| public.gv_supers_baja(p_empresa, p_cod, p_por) | rpc | idem; 0 | admin | ninguno | R-ADM | idem |

### H. Token propio (control-proveedores): se quedan en anon (2)

| función(args) | tipo | quién la llama | rol mínimo | chequeo actual | cambio | riesgo |
|---|---|---|---|---|---|---|
| public.cp_save(p_token, p_item_id, p_patch) | rpc | `control-proveedores/client/src/api.js` (proveedor externo, sin login); 0 | token | ok: exige `cp_sessions.token` | mantener anon; verificar que el token sea largo/aleatorio y que `cp_save` rechace sesiones `enviada` | cerrarla rompe el link al proveedor |
| public.cp_submit(p_token) | rpc | idem; 0 | token | ok | idem | idem |

## Orden sugerido

1. **Tanda A** (76) + **tanda B** (42): hoy mismo, un solo script, con vuelta atrás = los `grant … to anon` inversos. Medir 1 día que no aparezcan 401/42501 nuevos.
2. **C** (6): `alter function <trigger> security definer set search_path = public` y después revocar.
3. Etapa 2 del plan (tablets con `login-operario`, pantallas de GV Stock/Insumos/Supers y el programa viejo con sesión Google, macro y Planify con clave de servidor) → recién ahí **E, F, G** con el helper `exigir_rol`.
4. D queda para la etapa 5 (lecturas).
