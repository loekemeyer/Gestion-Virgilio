# Tests GP2

Suite creada 2026-08-29. Dos capas:

## 1) `tests/ui/` — pantallas (Playwright + Chromium)

Cada `test_*.js` abre la pantalla real del repo con **Supabase stubeado** (no tocan la
base): verifican payloads de RPC, filtros, cálculos en pantalla y flujos completos.
`run.sh` corre **todos** los `test_*.js` de la carpeta (hoy 37); si agregás uno, entra solo.

| Test | Pantalla / flujo |
|---|---|
| test_bom.js | Editor de BOM del ABM Artículos |
| test_botones_fuera.js | Botones sacados 2026-08-29 (RD/CM/REM) fuera y el resto presente; menú sin los candados muertos |
| test_contratos_db.js | Guardia del contrato pantalla ↔ base: toda `rpc('x')` y todo `from('x')` de las pantallas GP2 (las `_GP2`, las de entrada y `control-cajas`/`control-remaches`) existe en `db/` (funciones, tablas, vistas); cada columna pedida en `from(tabla).select(...)` existe en la tabla; en cada llamada con objeto literal, cada clave es un parámetro real de la función y no falta ninguno sin DEFAULT. Si falla porque `db/` está viejo, se regenera `db/`, no se toca el test (sin navegador, lee archivos) |
| test_control_tall_gp2.js | Control Talleristas GP2: caracterización previa a la unificación de pantallas |
| test_ctrl.js | Control Envíos y Entregas (pivote, medidas Kg/Uni/Cajas) |
| test_despiece_verif.js | Despiece x Artículo v2 (fusión de Verificación + VerifMadres): receta, rutas, faltantes prorrateados |
| test_dev.js | Devolución Cervantes (sector / Para Analizar) |
| test_entrega_ps_gp2.js | Entrega Prov Serv GP2: caracterización previa a la unificación |
| test_entregas_at_gp2.js | Entrega Prov AT nativa GP2 (idea 7216): bundle, buffer, payload de `crear_entrega_prov_at`, cliente apunta a GP2 |
| test_entregas_tall_gp2.js | Entregas Talleristas GP2: caracterización previa a la unificación |
| test_envios_ps_gp2.js | Envíos Prov Serv GP2: fase 0/1, cálculo de cajones, payload de `crear_envio_ps` |
| test_envios_tall_gp2.js | Envíos Talleristas GP2: caracterización previa a la unificación |
| test_faltantes_gp2.js | Faltantes: automáticos por stock online de Crudo/Procesado + marcas manuales |
| test_helpers_ui.js | Guardia de `gp2-ui.js` (helpers de pantalla en UNA copia): cada helper hace lo que promete, toda pagina que carga un JS compartido carga antes `gp2-ui.js` + `gp2-numero.js`, y ninguna pagina que ya los carga conserva un `esc`/`$`/"hoy"/CSV propio (sin navegador, lee archivos) |
| test_inicio_pend.js | Alerta de cargas de Virgilio sin aplicar (espejo_pend) |
| test_inyectores.js | Inyectores: botonera por proveedor, asignar/desasignar (payload de la RPC), aviso de partes que fabrica un tallerista, resumen y chips de rubro |
| test_kg_y_unidades.js | El insumo que viene en cajas y se pesa (`componente.recibe_en_cajas`): recepción en kg, control cajas × kg/caja |
| test_login_flow.js | GP2_MODULOS con auth-guard, Cerrar sesión, redirect de la landing vieja (`Inicio/index.html`) |
| test_marcas.js | Las marcas salen de los datos (`componente.marca`), no de una lista escrita a mano |
| test_menu_una_pantalla.js | El menú en celular: los 13 grupos entran en una pantalla, tocables (>=44px) y legibles (>=14px), versión visible, sin texto de relleno, y al abrir un grupo se ve solo ese |
| test_mon2.js | Cierres del Día · Premios, ex "Monitor 2.0" (premio espejo y calculado, alertas ±3) |
| test_numero.js | Guardia de la regla de número (`gp2-numero.js`): punto de miles, coma decimal, separador automático; rechaza saneadores propios en pantallas GP2 y, donde la regla está cargada, cualquier `.value` leído con `Number/parseInt` crudo |
| test_oc.js / test_oc_print.js | Órdenes de Compra: sugeridos, reglas de cartón C/LOKE/8, crear, imprimir; Charcas en paquetes (`charcas_kg_x_paquete` del bundle, unidad `paq` a `crear_oc`) y el mensaje de la OC gemela genérica. **Ojo**: el fixture de `test_oc.js` trae el contrato viejo (consumo × meses); la fórmula vigente máximo − stock queda sin cubrir hasta la idea 7242 |
| test_op_e2e.js | App Operarios entera: legajo → E con rollo → C → RM → baja vía RPC → cola ✓. El stub **revienta** si la app toca una tabla directo |
| test_pm.js | Problemas con Matrices (RM/PM, uni acumuladas, golpes) |
| test_pwa_icono.js | El icono de la app llega al teléfono: apple-touch-icon en las páginas de entrada, iconos del manifest existentes, maskable declarado y con token de versión |
| test_recepcion_etapas.js | Recepción: pesaje por etapas con varios ítems |
| test_recepcion_oc.js | Recepción: la tarjeta muestra "OC: N" (lo que falta de las OC abiertas) |
| test_recepcion_salir_pesaje.js | Recepción v3.22: no se puede salir sin controlar |
| test_recepcion_uni.js | El remito en unidades se guarda en unidades (remaches/bombillas); control en kg con pasaje a unidades |
| test_smoke_gp2.js | Humo de las 47 pantallas GP2 con Supabase stubeado y sin red: falla si falta un `<script src>` local (ruta/token mal) o si revienta un helper de la casa (`GP2UI`, `GP2N`, `esc`, `$`...); los errores de datos por el stub vacío se listan como aviso |
| test_stock_general.js | Stocks General: los dos flujos heredados de Registrar Movimiento (Ajuste +/- y Armado en fábrica), payload exacto de `registrar_movimientos` |
| test_stock_sector.js | La pantalla única de stock por sector (`StockSector_GP2.html?sector=N`, ex 9 pantallas): título, botones, columnas, KPIs, popup, RPC y menú para cada uno de los 9 sectores, a 390px |
| test_teclado_numerico.js | Letra grande (>=18px) y `inputmode` numérico en todos los campos de número de las pantallas GP2 |
| test_tokens_cache.js | Guardia de caché y clave: un solo ?v= por asset compartido, versión/token nunca reusados, y la clave anon sólo en supabase-config.js (sin navegador, lee git) |
| test_valorizacion.js | Valorización: stock y pedido-a-máximo valorizados con el motor de costos |

**Correr**: `bash tests/ui/run.sh`
Requiere `node` + `playwright` (local o global: `npm i -g playwright`). Si Chromium no
está en `/opt/pw-browsers/chromium` (entorno remoto), instalarlo con
`npx playwright install chromium` o apuntar `CHROMIUM_PATH` al ejecutable.

## 2) BD — pruebas con rollback

Las pruebas del motor (circuito E2E completo, cruce OC, premio nativo, RLS como anon,
triggers de máximos) se corren como bloques `DO $$ ... $$` que SIEMPRE terminan en
`raise exception 'OK_ROLLBACK ...'` para revertir todo. Ver los detalles y resultados en
`LOCKS.txt` [HISTORIAL] (entradas 2026-08-29). Patrón: armar el escenario con las RPCs
reales, verificar deltas contra snapshot, y abortar con OK_ROLLBACK — la base queda intacta.
