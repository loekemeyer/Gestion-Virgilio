# Hallazgos de seguridad separados por planta (2026-09-29)

Sale de `SEGURIDAD-MATRIZ-FUNCIONES.md` y `SEGURIDAD-MATRIZ-TABLAS.md` (mismo relevamiento, 28/09). La planta se
asigna por el nombre y por quién la llama (app/archivo) — **[Probable]**: revisar las de "Ambas/compartida".

## Cervantes — 25 funciones, 44 tablas

**Funciones** (rol propuesto · ¿se cierra ya?):

- `public.fn_audit_matrices()` — revocar · ninguno
- `public.fn_sp_kg_stockini_ts()` — revocar · ninguno
- `public.fn_stock_ini_ts_flejes()` — revocar · ninguno
- `public.fn_stock_ini_ts_remache()` — revocar · ninguno
- `public.fn_stock_ini_ts_underscore()` — revocar · ninguno
- `public.gp2_matriz_racha_trg_espejo()` — revocar · ninguno
- `public.gp2_matriz_racha_trg_planify()` — revocar · ninguno
- `public.sync_stock_desde_matrices()` — revocar · ninguno
- `public.trg_despiece_delete()` — revocar · ninguno
- `public.gp2_matriz_racha_sync(p_matriz)` — servicio · ninguno
- `public.fix_op233_eod_20260428()` — revocar · ninguno. Hoy anon puede re-ejecutar el parche del 28/04 sobre `Registros Produccion Cervan
- `public.cargar_entrega(7 args)` — revocar · ninguno
- `public.asignar_fleje_operario(p_entrada_id, p_legajo, p_matriz)` — revocar · ninguno
- `public.descontar_kg_fleje(p_entrada_id, p_kg, p_evento_id)` — revocar · ninguno
- `public.liberar_fleje(p_entrada_id, p_kg_restante)` — revocar · ninguno
- `public.sumar_cajas_recibidas(p_cod, p_cod_tallerista, p_cajas)` — revocar · ninguno
- `public.rebuild_partes_x_tallerista()` — servicio · ninguno
- `public.actualizar_despiece()` — servicio · se cae todo INSERT/UPDATE de pesos hecho con clave pública (programa viejo, `cervantes-adm
- `public.actualizar_partes_tallerista()` — servicio · idem
- `public.recalcular_stock_online_cajon_total()` — servicio · se caen las cargas de Entregas PS / Envíos a Talleristas con clave pública
- `public.rc_alerta_recepcion_fleje(p_text, p_dedup)` — gp2`); 0 · aviso de diferencia de flejes se cae
- `public.marcar_revisado(row_id)` — gp2`); **PUB 2 OTRA (2 errores)**. (GP2 llama a `GP2.marcar_revisado`, otra función) · Disruptivas del programa viejo
- `public.anular_produccion(9 args)` — supervisor · idem
- `public.toggle_anular_tiempo(row_id)` — supervisor · Tiempos del programa viejo
- `public.recalcular_matriz(p_matriz, p_nuevo_tiempo)` — admin · cambiar tiempo histórico desde el programa viejo

**Tablas** (tipo · ¿se cierra ya?):

- public.`Catalogo Tall Cervantes` — maestro · **sí**
- public.`entregas_cervantes_v2` — gestión · **sí**
- public.`partes_excluidas_por_tallerista` — maestro · **sí**
- public.`cajas_excluidas_por_tallerista` — maestro · **sí**
- public.`Matrices_audit` — log/auditoría · **sí**
- public.`BOMB` — maestro · **sí**
- public.`Causa-Efecto` — maestro · **sí**
- public.`Cepillos` — maestro · **sí**
- public.`Garage` — maestro · **sí**
- public.`GRJ_Componentes` — maestro · **sí**
- public.`Flejes` — maestro (stock inicial) · **sí**
- public.`Partes_Plasticas` — maestro (stock inicial) · **sí**
- public.`Pieza Madre` — maestro · **sí**
- public.`Remaches SC` — maestro (pesos) · **sí**
- public.`Remaches SP` — maestro (pesos) · **sí**
- public.`Sector Bombilla` — maestro (pesos) · **sí**
- public.`Sector Carton` — maestro · **sí**
- public.`SectorPlasticos` **[MADRE]** — maestro (pesos) · **sí**
- public.`Articulos x Prov AT` — maestro · **sí**
- public.`Balancines` — maestro · **sí**
- public.`Partes x Tallerista` — derivada (NO tocar directo) · **sí para anon** (Despiece ya no lo borra anon si se cierra en la misma tanda); los trigge
- public.`Envios a PS` — gestión (PS) · **sí para anon** (solo la escriben pantallas con sesión Google); con `es_gestion()` recién
- public.`Envios a Talleristas` — gestión (talleristas) · **sí para anon** (solo la escriben pantallas con sesión Google); con `es_gestion()` recién
- public.`SP Kg` **[MADRE]** — maestro (pesos) · **sí para anon** (solo la escriben pantallas con sesión Google); con `es_gestion()` recién
- public.`SC Kg` **[MADRE]** — maestro (pesos) · **sí para anon** (solo la escriben pantallas con sesión Google); con `es_gestion()` recién
- public.`Partes x PS` **[MADRE]** — maestro (config PS) · **sí para anon** (solo la escriben pantallas con sesión Google); con `es_gestion()` recién
- public.`Matrices` **[MADRE]** — maestro · **sí para anon** (solo la escriben pantallas con sesión Google); con `es_gestion()` recién
- public.`Entregas PS` — gestión (PS) · **sí para anon** (solo la escriben pantallas con sesión Google); con `es_gestion()` recién
- public.`Entregas Tallerista Cervantes` — gestión (talleristas) · **sí para anon** (solo la escriben pantallas con sesión Google); con `es_gestion()` recién
- public.`Devoluciones Tallerista Cervantes` — gestión (talleristas) · **sí para anon** (solo la escriben pantallas con sesión Google); con `es_gestion()` recién
- public.`Envios Prov AT` — gestión (prov. AT) · **sí para anon** (solo la escriben pantallas con sesión Google); con `es_gestion()` recién
- public.`Ajustes Online PS` — gestión (PS) · **sí para anon** (solo la escriben pantallas con sesión Google); con `es_gestion()` recién
- public.`Control_Logistica` — gestión · **sí para anon** (solo la escriben pantallas con sesión Google); con `es_gestion()` recién
- public.`Flejes_Entradas` — gestión (compras) · **sí para anon** (solo la escriben pantallas con sesión Google); con `es_gestion()` recién
- public.`Relevamientos_Cajas` — gestión (conteo) · **sí para anon** (solo la escriben pantallas con sesión Google); con `es_gestion()` recién
- public.`Relevamientos_Cajas_Items` — gestión (conteo) · **sí para anon** (solo la escriben pantallas con sesión Google); con `es_gestion()` recién
- public.`Proporcion_Articulo_Tallerista` — maestro · **sí para anon** (solo la escriben pantallas con sesión Google); con `es_gestion()` recién
- public.`Rutas_Confirmadas` — gestión (verificación) · **sí para anon** (solo la escriben pantallas con sesión Google); con `es_gestion()` recién
- public.`Rutas_Problemas` — gestión (verificación) · **sí para anon** (solo la escriben pantallas con sesión Google); con `es_gestion()` recién
- public.`Entrevistas` — gestión RRHH (datos personales) · **sí para anon** (solo la escriben pantallas con sesión Google); con `es_gestion()` recién
- public.`db_n8n_espejo` — producción (tablet Cervantes) · no — rompe tablet Cervantes (Registro Producción) y celulares de operarios
- public.`Registros Produccion Cervantes` — producción (tablet Cervantes) · no — rompe tablet Cervantes + SW offline
- public.`Auditoria_Produccion` — log producción · no — rompe tablet Cervantes
- public.`Tall_ProvAT_PS` — maestro · no — rompe pantallas de GV que escriben con la clave pública (pasar a sesión Google)

## Virgilio — 127 funciones, 38 tablas

**Funciones** (rol propuesto · ¿se cierra ya?):

- `public.actualizar_saldo_trigger()` — revocar · ninguno
- `public.exigir_foto_procesado()` — revocar · ninguno
- `public.gv_match_cod_a_programacion()` — revocar · ninguno
- `public.gv_ppp_web_super_tanda_sola()` — revocar · ninguno
- `public.gv_supers_sync()` — revocar · ninguno
- `public.gv_uxb_protege_curado()` — revocar · ninguno
- `public.gv_web_cliente_un_solo_dia()` — revocar · ninguno
- `public.notificar_pedido_adelantado_telegram()` — revocar · ninguno
- `public.notificar_recepcion_excede_oc_telegram()` — revocar · ninguno
- `public.ppp_autozona()` — revocar · ninguno
- `public.ppp_web_prog_touch()` — revocar · ninguno
- `public.procesar_conteo_alertas()` — revocar · ninguno
- `public.trg_facturado_no_negativo()` — revocar · ninguno
- `public.trg_gv_marca_manual()` — revocar · ninguno
- `public.trg_pkc_reconciliar_rt()` — revocar · ninguno
- `public.wa_factura_notificar()` — revocar · ninguno
- `public.enviar_digest_agentes()` — servicio · ninguno
- `public.generar_ocs_automaticas(p_forzar)` — servicio · ninguno (hoy anon puede generar OC)
- `public.gv_np_mover_guard(p_nps, p_tanda_destino, p_tanda_entera)` — servicio · ninguno
- `public.gv_oc_recompute_recibido(p_nombre, p_cod)` — servicio · ninguno
- `public.gv_ppp_nps_mover_a(p_nps, p_tanda, p_fecha, p_nota, p_tanda_entera)` — servicio · ninguno. **La más peligrosa**: mueve cualquier NP con la clave pública
- `public.gv_ppp_reprogramar_sin_factura(p_aplicar, p_fecha)` — servicio · ninguno (hoy anon puede reprogramar con `p_aplicar=true`)
- `public.gv_refrescar_precio_facturado()` — servicio · ninguno
- `public.gv_tandas_codigos_usados_sync(p_desde)` — servicio · ninguno
- `public.refresh_stocks_carga_rapida()` — servicio · ninguno
- `public.wa_np_snapshot_run()` — servicio · ninguno
- `public.wa_grupo_completo_check(p_np)` — servicio · ninguno
- `public.tanda_reservar(p_tanda, p_fase, p_legajo, p_nombre)` — servicio · solo si alguien abre la copia vieja de GV
- `public.tanda_liberar(p_tanda, p_fase, p_legajo)` — servicio · idem
- `public.anular_picking_virgilio(p_legajo, p_tanda)` — revocar · idem
- `public.oc_backfill_valores(p_solo_null)` — servicio · ninguno
- `public.faltante_tarea_cancelar(p_id)` — supervisor · ninguno
- `public.gv_pedido_horario_borrar(p_empresa, p_clave, p_por)` — supervisor · ninguno
- `public.gv_ppp_en_salida_desmarcar(p_nps, p_por)` — supervisor · ninguno
- `public.gv_clin_desvincular(4 args)` — supervisor · ninguno
- `public.wa_sim_cleanup()` — revocar · ninguno
- `public.wa_sim_cleanup_all()` — servicio · ninguno. Hoy anon borra en `isis_*.documentos`, `Facturacion_NP`, programación
- `public.wa_sim_factura_np(p_cuit, p_np)` — servicio · ninguno
- `public.wa_sim_insert_documento(9 args)` — servicio · ninguno
- `public.wa_sim_seed_order(4 args) y (5 args)` — servicio · ninguno
- `public.banco_movimiento_aplicar(4 args)` — supervisor · ninguno
- `public.banco_movimiento_ignorar(3 args)` — supervisor · ninguno
- `public.banco_movimientos_importar(5 args)` — supervisor · ninguno
- `public.deuda_registrar_cobro(8 args)` — supervisor · ninguno
- `public.deuda_anular_cobro(p_id, p_por)` — supervisor · ninguno
- `public.facturable_anticipado_reservar(4 args)` — supervisor · ninguno
- `public.facturable_anticipado_liberar(p_id, p_por)` — supervisor · ninguno
- `public.gv_clin_evento(9 args)` — supervisor · ninguno
- `public.gv_clin_vincular(8 args)` — supervisor · ninguno
- `public.gv_expreso_marcar(4 args)` — supervisor · ninguno
- `public.gv_fac_export_registrar(8 args)` — supervisor · ninguno
- `public.gv_ppp_dia_reprogramar(4 args)` — supervisor · ninguno
- `public.gv_ppp_en_salida_marcar(4 args)` — supervisor · ninguno
- `public.gv_ppp_isis_desprogramar(3 args)` — supervisor · ninguno
- `public.gv_ppp_isis_programar(3 args)` — supervisor · ninguno
- `public.gv_ppp_pedido_mover(5 args)` — supervisor · ninguno
- `public.gv_ppp_tanda_espera(3 args)` — supervisor · ninguno
- `public.gv_ppp_tanda_mover(5 args)` — supervisor · ninguno
- `public.gv_imp_carga_pedido_set(5 args)` — supervisor · ninguno
- `public.gv_imp_cc_deuda_add(10 args)` — supervisor · ninguno
- `public.gv_imp_cc_deuda_borrar(p_id)` — supervisor · ninguno
- `public.gv_imp_cc_deuda_set(p_id, p_campo, p_valor)` — supervisor · ninguno
- `public.gv_imp_cc_set(14 args)` — supervisor · ninguno
- `public.gv_imp_ntl_efectivo_add(6 args)` — supervisor · ninguno
- `public.gv_imp_ntl_efectivo_borrar(p_id)` — supervisor · ninguno
- `public.gv_imp_pago_add(10 args)` — supervisor · ninguno
- `public.gv_imp_pago_borrar(p_pago_id)` — supervisor · ninguno
- `public.gv_imp_pago_cargas_set(3 args)` — supervisor · ninguno
- `public.gv_imp_prov_alias_set(3 args)` — supervisor · ninguno
- `public.gv_imp_recibir(8 args)` — supervisor · ninguno
- `public.gv_imp_recepcion_anular(p_id, p_motivo)` — supervisor · ninguno
- `public.gv_importado_bache_add(6 args)` — supervisor · ninguno
- `public.gv_importado_bache_borrar(p_bache_id)` — supervisor · ninguno
- `public.gv_importado_bache_editar(4 args)` — supervisor · ninguno
- `public.gv_importado_bache_embarque(p_bache_id, p_embarque)` — supervisor · ninguno
- `public.gv_importado_bache_llego(3 args)` — supervisor · ninguno
- `public.gv_importado_pedido_fechas(6 args)` — supervisor · ninguno
- `public.gv_importado_pedido_ref(3 args)` — supervisor · ninguno
- `public.gv_importados_resync(p_importado_id)` — supervisor · ninguno
- `public.importados_marcar_llegada(3 args)` — supervisor · ninguno
- `public.importados_set_curso(p_id, p_uni)` — supervisor · ninguno
- `public.reconciliar_stock_articulo_rt(p_tanda, p_cod_raw)` — servicio · **se cae el picking de la tablet de GV** (inserta PKC con clave pública)
- `public.gv_ancla_demora_paradas(9 args)` — lectura · romper el cálculo de demora de ancla
- `public.gv_ppp_web_agrupar_geo(p_paradas)` — lectura · idem sombra PPP
- `public.gv_evento_tanda_campo(p_opcion)` — lectura · puede estar en un índice/columna: no tocar
- `public.anular_armado_virgilio(p_legajo, p_tanda, p_motivo)` — operario · el operario no puede deshacer un armado
- `public.anular_toggle_virgilio(p_legajo, p_opcion)` — operario · no se puede cerrar/deshacer sesión de tarea
- `public.gv_anular_picking_virgilio(p_legajo, p_tanda)` — operario · no se puede anular un picking fantasma
- `public.anular_modo_op(p_id)` — operario · recepción RT no puede anular
- `public.gv_tanda_reservar(p_tanda, p_fase, p_legajo, p_nombre)` — operario · nadie puede tomar una tanda (picking/armado paran)
- `public.gv_tanda_completar(p_tanda, p_fase, p_legajo)` — operario · no se cierran tandas
- `public.gv_tanda_lock_anular(p_tanda, p_fase, p_legajo)` — operario · no se libera una tanda tomada
- `public.faltante_tarea_crear(7 args)` — operario · no se generan tareas de faltantes desde la tablet
- `public.faltante_tarea_asignar(p_id, p_legajo, p_nombre)` — operario · no se toman tareas de faltante
- `public.faltante_tarea_soltar(p_id, p_legajo)` — operario · idem soltar
- `public.faltante_tarea_completar(p_id)` — operario · idem completar
- `public.cp_completar_faltante(p_id, p_qty)` — operario · completar faltantes en pedido se cae
- `public.cp_reducir_faltante_cap(p_id, p_qty)` — operario · idem
- `public.reasignar_cajas(p_target_id, p_qty, p_donor_id)` — operario · reasignar cajas entre pedidos se cae
- `public.racks_plani_ingreso(6 args)` — operario · ingreso a racks (planimetría) se cae
- `public.racks_plani_ingreso_nacional(7 args)` — operario · idem nacional
- `public.racks_plani_mover(5 args)` — operario · mover entre racks se cae
- `public.registrar_baja_racks(p_items)` — operario · bajadas de rack se cae
- `public.nuevo_insumo_tmp(p_detalle, p_categoria, p_legajo)` — operario · alta de insumo provisorio desde la tablet se cae
- `public.gv_insumo_ubicaciones_guardar(p_cod, p_items)` — operario · guardar ubicaciones de insumo se cae
- `public.aceptar_conteo(p_conteo_id, p_admin_legajo)` — supervisor · no se aprueban conteos
- `public.rechazar_conteo(p_conteo_id, p_admin_legajo, p_razon)` — supervisor · idem
- `public.faltante_resolver(5 args)` — supervisor · resolver faltantes facturados se cae
- `public.corr_convertir_faltante(p_np, p_sec, p_ppal)` — supervisor · ninguno si la sesión está (ya la manda)
- `public.gv_conciliacion_registrar(p_np)` — supervisor · ninguno (ya manda sesión)
- `public.gv_pedido_horario_set(7 args)` — supervisor · ninguno (ya manda sesión)
- `public.zona_barrio_set(p_barrio, p_zona)` — supervisor · asignar barrio→zona se cae
- `public.gv_conc_cargar(p_banco, p_anio, p_filas, p_archivo, p_token)` — supervisor / servicio · **la macro de conciliación deja de cargar**
- `(más las 42 de la tanda B y 4 de la tanda A, que ya chequean o no se usan)` —  · 
- `public.insumo_alta(5 args)` — admin · ABM insumos se cae
- `public.insumo_borrar(p_cod)` — admin · idem
- `public.insumo_editar(6 args)` — admin · idem
- `public.insumo_recodificar(p_cod, p_nuevo)` — admin · idem
- `public.insumo_identificar(4 args) y (5 args)` — admin · idem
- `public.insumo_factores_guardar(p_cod, p_factores)` — admin · idem
- `public.insumo_cat_guardar(5 args) y (6 args)` — admin · idem
- `public.insumo_cat_borrar(p_clave)` — admin · idem
- `public.insumo_unidad_guardar(p_nombre, p_activa)` — admin · idem
- `public.gv_supers_set(7 args)` — admin · editor de súper se cae
- `public.gv_supers_baja(p_empresa, p_cod, p_por)` — admin · idem
- `public.cp_save(p_token, p_item_id, p_patch)` — token · cerrarla rompe el link al proveedor
- `public.cp_submit(p_token)` — token · idem

**Tablas** (tipo · ¿se cierra ya?):

- public.`Proveedores_Insumos` — maestro · **sí**
- public.`Proveedores_Stock_Config` — maestro · **sí**
- public.`Importados_Mov_Stock` — log/operario · **sí**
- public.`GV_Viaje_Horas` — gestión · **sí**
- public.`Control_Carga_Remitos` — gestión · **sí**
- public.`Pasaje_Papeles` — gestión · **sí** (confirmar que la copia vieja no se usa)
- public.`Insumos` — maestro · **sí** (probar alta de insumo en GV)
- public.`Fichadas_Virgilio` — operario (fichada) · **casi**: 0 escrituras en 2 días; confirmar que `fichada.html` ya no se usa (reemplazada p
- public.`Registros_Produccion_Virgilio` — producción (GV) · no — rompe GV operarios Virgilio (muchos con datos móviles)
- public.`Auditoria_Produccion_Virgilio` — log producción · no — rompe GV
- public.`Movimientos_Stock` — operario (stock/picking) · no — rompe GV picking/recepción
- public.`Etiquetas_Lio` — operario (lío/etiquetas) · no — rompe GV + imprimidor si escribe con la pública
- public.`Guardado_Sesiones` — operario (log de tiempos) · no — rompe GV
- public.`Impresion_NP` — operario (log impresión NP) · no — rompe GV
- public.`Entregas_Virgilio` — operario (picking/entregas) · no — rompe GV picking
- public.`Control_Modo_OP` — operario (recepción) · no — rompe GV recepción (usa sesión anónima → hoy igual a pública)
- public.`Racks_Bajadas` — operario (racks) · no — rompe GV
- public.`Racks_Ordenes` — operario (racks) · no — rompe GV
- public.`Insumos_Ubicaciones` — operario (ubicaciones) · no — rompe GV
- public.`Envasar_Ubicaciones` — operario (ubicaciones) · no — rompe GV
- public.`Conteo_Stock` — operario (conteo) · no — rompe GV conteo
- public.`Conteo_Alertas` — operario (conteo) · no — rompe GV
- public.`GV_Recepcion_Receptores` — operario (recepción) · no — rompe GV recepción
- public.`errores_cliente` — log · no — rompe GV (solo reporte de errores)
- public.`Alertas_Pedidos_Web` — gestión (pedidos) · no — rompe pantallas de GV que escriben con la clave pública (pasar a sesión Google)
- public.`Camioneros` — gestión (logística) · no — rompe pantallas de GV que escriben con la clave pública (pasar a sesión Google)
- public.`Correcciones_Pedido` — gestión (pedidos) · no — rompe pantallas de GV que escriben con la clave pública (pasar a sesión Google)
- public.`Faltantes_Notas` — gestión · no — rompe pantallas de GV que escriben con la clave pública (pasar a sesión Google)
- public.`NC_Loeke_Chef_Hechas` — gestión (NC) · no — rompe pantallas de GV que escriben con la clave pública (pasar a sesión Google)
- public.`NP_Canceladas` — gestión (NP) · no — rompe pantallas de GV que escriben con la clave pública (pasar a sesión Google)
- public.`NP_Secuencia_Revisadas` — gestión (NP) · no — rompe pantallas de GV que escriben con la clave pública (pasar a sesión Google)
- public.`NP_Sin_Base_Revisadas` — gestión (NP) · no — rompe pantallas de GV que escriben con la clave pública (pasar a sesión Google)
- public.`PPP_Geo` — gestión (geocodificación) · no — rompe pantallas de GV que escriben con la clave pública (pasar a sesión Google)
- public.`Etiqueta_Lio_Legajos` — config operarios · no — rompe pantallas de GV que escriben con la clave pública (pasar a sesión Google)
- public.`envio_programacion_log` — log · no — rompe pantallas de GV que escriben con la clave pública (pasar a sesión Google)
- public.`Volumen_Articulos` — maestro (volúmenes) · no — rompe pantallas de GV que escriben con la clave pública (pasar a sesión Google)
- public.`Articulos_Cajas` — maestro · no — rompe pantallas de GV que escriben con la clave pública (pasar a sesión Google)
- public.`Articulos_Discontinuados` — maestro · no — rompe pantallas de GV que escriben con la clave pública (pasar a sesión Google)

## Ambas/compartida — 7 funciones, 12 tablas

**Funciones** (rol propuesto · ¿se cierra ya?):

- `public.gv_capacidad_sector_escribir()` — revocar · ninguno
- `public.trg_articulos_delete()` — revocar · ninguno
- `public.gv_ppp_web_tanda_reusar(4 args)` — supervisor · ninguno (el armador usa `sb_secret`)
- `public.registrar_unidades(p_n_matriz, p_cantidad, p_completar, p_legajo, p_evento_id)` — operario · no se registran unidades por cajón en ninguna tablet de producción
- `public.asignar_matriz_balancin(p_balancin, p_matriz)` — operario · CM no asigna la matriz al balancín
- `public.rc_set_conteo(p_tipo, p_det_id, p_vals)` — operario · relevamiento de conteo (programa viejo) se cae
- `public.gv_oc_generar_pendientes(p_rows)` — supervisor · ninguno (ya manda sesión)

**Tablas** (tipo · ¿se cierra ya?):

- public.`Preavisos` — gestión · **sí**
- public.`Despiece x Articulo` — derivada (via actualizar_despiece) · **sí para anon** (solo la escriben pantallas con sesión Google); con `es_gestion()` recién
- public.`Recepcion_Insumos` — gestión (compras) · **sí para anon** (solo la escriben pantallas con sesión Google); con `es_gestion()` recién
- public.`Pendientes` — gestión · **sí para anon** (solo la escriben pantallas con sesión Google); con `es_gestion()` recién
- public.`Entrevistas_Virgilio` — gestión RRHH (datos personales) · **sí para anon** (solo la escriben pantallas con sesión Google); con `es_gestion()` recién
- public.`Entregas Tallerista Virgilio` — operario (recepción) · no — rompe GV recepción
- public.`Entregas Prov AT` — operario (recepción) · no — rompe GV recepción
- public.`Articulos Virgilio X Tallerista` **[MADRE]** — maestro usado en recepción · no — rompe GV recepción / ABM talleristas
- public.`Ordenes_Compra` — gestión (compras) · no — rompe pantallas de GV que escriben con la clave pública (pasar a sesión Google)
- public.`Cajas` — maestro (cajas/stock inicial) · no — rompe pantallas de GV que escriben con la clave pública (pasar a sesión Google)
- public.`Codigos X Tallerista` — maestro · no — rompe pantallas de GV que escriben con la clave pública (pasar a sesión Google)
- public.`Empleados` — maestro (datos personales) · no — rompe pantallas de GV que escriben con la clave pública (pasar a sesión Google)

## Sin planta (servicio, pruebas, sin uso) — 31 funciones, 15 tablas

**Funciones** (rol propuesto · ¿se cierra ya?):

- `función(args)` — rol mínimo · riesgo
- `public.sync_fichadas_estructura()` — servicio · ninguno
- `public.sync_fichadas_respuestas()` — servicio · ninguno
- `procesos.area_id(p_area)` — servicio · ninguno
- `procesos.cargar_md(8 args)` — servicio · ninguno
- `procesos.cargar_staging(8 args)` — servicio · ninguno
- `procesos.marcar_revisada(6 args)` — servicio · ninguno
- `procesos.upsert_seccion(8 args)` — servicio · ninguno
- `public.planify_record_deploy(8 args) y (10 args)` — servicio · ninguno: el workflow ya manda `service_role`
- `public.fn_recalcular_maximo_por_desc_base()` — revocar · ninguno
- `public.import_proveedores_csv(csv_text)` — revocar · ninguno
- `public.upsert_proveedor_articulos(p_nombre, p_tipo, p_articulos)` — revocar · ninguno
- `public.validar_login(p_usuario, p_password)` — revocar · ninguno. Hoy es un oráculo de contraseñas de `public.usuarios` abierto a anon
- `public.sync_pasaje_rr()` — revocar · ninguno
- `public.http_delete(uri) y (uri, content, content_type)` — revocar · ninguno (GP2 usa `http_get` desde funciones definer)
- `función(args)` — rol mínimo · riesgo
- `función(args)` — rol mínimo · riesgo si se revoca hoy
- `public.actualizar_partes_ps()` — servicio · idem
- `public.sync_partes_from_articulo(p_id)` — servicio · se cae el ABM de `Articulos Virgilio X Tallerista` / `Despiece x Articulo`
- `función(args)` — rol mínimo · riesgo
- `public.generar_inconsistencias(p_dia)` — lectura (supervisor) · cerrar hoy rompe el informe de inconsistencias
- `función(args)` — rol mínimo · riesgo si se aplica antes de la etapa 2
- `public.marcar_auditoria_visto(p_id, p_visto, p_nota, p_legajo)` — supervisor* · el monitor no marca auditorías
- `función(args)` — rol mínimo · riesgo si se aplica antes de que la pantalla mande sesión
- `public.rc_borrar(p_relevamiento_id)` — supervisor · borrar relevamiento (programa viejo)
- `public.planify_recruit_set_estado(p_id, p_status)` — supervisor (Planify maestro) · Reclutamiento de Planify
- `public.planify_recruit_set_calif(p_id, p_calif)` — supervisor · idem
- `public.planify_recruit_set_archivado(p_id, p_val)` — supervisor · idem
- `public.planify_recruit_set_search(p_id, p_search_id)` — supervisor · idem
- `función(args)` — rol mínimo · riesgo si se aplica antes
- `función(args)` — rol mínimo · riesgo

**Tablas** (tipo · ¿se cierra ya?):

- public.`_rls_diag` — basura · **sí**
- public.`Precios_Historico` — maestro · **sí**
- public.`Stock_Ubicaciones` — maestro · **sí**
- public.`empleados_loekemeyer_chef` — maestro (datos personales) · **sí**
- public.`Registros Historicos` — log (histórico) · **sí**
- public.`Codificacion Mensajes` — maestro · **sí**
- public.`Stock_Inicial_Cartones` — maestro · **sí**
- public.`peso_cajones` — maestro · **sí**
- public.`Precios_Proveedores` — maestro (precios) · **sí**
- public.`articulos` — maestro · **sí**
- public.`Proveedores` — maestro (datos de contacto) · **sí** (junto con la RPC)
- public.`proveedores` — maestro · **sí** (junto con la RPC)
- public.`Comprobantes_NC` — gestión (NC) · **sí**
- public.`Comprobantes_NC_Items` — gestión (NC) · **sí**
- public.`Fichadas_Historico` — log fichadas · **sí**
