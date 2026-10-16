# Revisión general de ineficiencias — 16/10/2026

Pedido de Thomas. Cinco agentes en solo lectura: front (código), front (red), base (consultas e
índices), base (crons, triggers, Edge Functions) y normalización. Ventana de `pg_stat_statements`:
01/10 → 15/10 (14,5 días).

Primero lo incómodo: casi todo el tiempo de base se lo comen los **crons y el Realtime**, no las
pantallas. Y en el front no pesan las funciones muertas (~30 KB): pesa la **forma de entrega**
(`index.html` 4,75 MB, 1,40 MB gzip, que baja también el celular del operario).

## 1. Aplicado hoy (v31.37) (sin riesgo, con el «sí» previo de Thomas)

| qué | antes | después |
|---|---|---|
| índice `idx_rpv_ccn_np` (RPV, CCN por NP) → `vista_ppp_pedidos_entregados` | 1.770 ms, 8 timeouts en 3 días | 167 ms |
| índice `gv_pk_paso_ev_mostrado` → `gv_analisis_badge` (badge del Análisis) | 2.623 ms, 24 timeouts en 3 días | 84 ms |
| índices `entregas_virgilio_np_norm_idx` + `facturacion_np_np_norm_idx` → `gv_vista_control_remitos` | 213 ms | 11 ms |
| `analyze` de 10 tablas chicas sin estadísticas (`codigos_duales`, `Equivalencias_Codigos`, `GV_Supers`, …) | `reltuples = -1` | con estadísticas |
| crons 25, 34, 87, 95, 26, 162, 61, 69, 92 movidos de minuto (misma frecuencia) | 16 jobs en :00, 14 en :30 | máximo 10 por minuto |
| `Entregas_Virgilio.fecha_salida`: 246 filas `YYYY-MM-DD 00:00:00` → `YYYY-MM-DD` | 2 formatos | 1 (backup `zz_backups."GV_Backup_EV_fecha_salida_20261016"`) |
| `GV_PPP_Atrasado_Cerrado.empresa`: 6 `ch` → `chef` | 2 vocabularios | 1 (backup `zz_backups."GV_Backup_Atrasado_Cerrado_20261016"`) |
| Facturación: el refresco de 5 s se pausa con la pestaña oculta | ~12 lecturas / 5 s siempre | 0 oculta, refresca al volver |
| Inconsistencias (20 s) y Faltantes (20 s): pausa con la pestaña oculta | siempre | sólo visible |
| `fetchFacturadosTodos`: paginado de a 1.000 | cortaba en 1.000 de 1.649 NP | trae todas |

`gv_reglas_perdidas` vacía después de los cambios.

## 2. Pendiente de decisión — base

| # | qué | medición | fix propuesto | riesgo |
|---|---|---|---|---|
| B1 | Realtime: decodificación de WAL | 6:22 h en 14,5 días (12,6 % de la base) | sacar de la publicación las tablas sin suscriptor (`Entregas Tallerista Virgilio`, …) y que `refresh_stocks_carga_rapida` (cron 57) no reescriba las 396 filas 3 veces por corrida (`IS DISTINCT FROM`): 5,88 M updates | medio (otras apps pueden escuchar) |
| B2 | `reconciliar_pipeline_stock` (cron 68, cada 10 min) | 3:21 h; sólo 29 de 1.008 corridas cambian algo; toma el lock 5768 que esperan 57 y 92 | correr sólo si cambió la huella; `pg_try_advisory_xact_lock`; antes medir por etapa con `track_functions='pl'` | medio |
| B3 | `sync_fichadas_respuestas` (cron 25, cada 2 min) | 3:13 h; `http_get` síncrono; 97 % de las corridas sin datos | horario laboral y cada 5 min (en uso: `fichadas-monitor.html`) | bajo |
| B4 | `gv_refresh_stock_si_cambio` (cron 55, cada 2 min) | 2:02 h | cada 10 min de noche | bajo |
| B5 | `gt.sync_pedidos_tn` (cron 126, cada 10 min) | 1:57 h; 3 pedidos TN en total, 0 en 7 días; sin lector en este repo | si nadie lo usa, sacarlo | bajo |
| B6 | `PPP_Web_Base`: upsert de la Edge Function reescribe todo | 6,32 M updates sobre 5.323 filas + 3 triggers por fila | trigger BEFORE UPDATE que no grabe si la fila no cambió | bajo-medio |
| B7 | `vista_saldos_stock` + `gv_saldos_stock_emp` | 1:29 h; seq scan de 86.572 movimientos por llamada | leer de la materializada `vista_stock` | medio |
| B8 | `gv_facturacion_neto_mat` (cron 109) | 1:12 h | horario laboral o por huella | bajo |
| B9 | `gv_tandas_codigos_usados_sync` (cron 95) sin `p_desde` | reescanea toda la historia | `p_desde => 1 día` + pasada nocturna completa | bajo |
| B10 | `gv_entregas_reconstruir` (cron 87) | 1.006 de 1.008 corridas sin efecto | correr sólo si hay TAP nuevo | bajo |
| B11 | `gv-geocodificar` (cron 75) | las 3 corridas de 24 h terminan en 504 a los 150 s | lotes más chicos | medio |
| B12 | `cron.job_run_details` | 137 MB, 518.668 filas desde 07/04 | borrar > 7 días (es borrado) | bajo |
| B13 | `gv_gp2_espejo_sync` (cron 112) | 3,9 % de corridas fallan por `virgilio_insumo_ubicacion_pkey` | bug: registrar en auditoría y arreglar | — |

## 3. Pendiente de decisión — front

| # | qué | medición | fix | esfuerzo |
|---|---|---|---|---|
| F1 | cada TP baja `Movimientos_Stock` entera | 86.572 filas, 25,2 MB, 87 páginas; ~380 bajadas ≈ 9,5 GB en 15 días | RPC de saldo sólo de los artículos de la tanda | medio |
| F2 | TV: 8 consultas cada 5 s sin caché | ~7.900 req/h por TV | eventos incrementales + caché 30 s, o una RPC «foto del tablero» | medio |
| F3 | Facturación: `Entregas_Virgilio` entera cada 30 s | 15.413 filas, 1,2 MB; ≈ 5 GB en 15 días | sólo las NP en pantalla (`np=in.(…)`) | bajo |
| F4 | supabase-js cargado 2 veces (v2.112.3 y v2.106.2; gana la vieja) | 212 KB por carga | dejar sólo `vendor/`; probar login | bajo |
| F5 | jsPDF + autotable + Chart.js en el `<head>` sin `defer` | 608 KB bloqueando el arranque | cargarlos a demanda | bajo |
| F6 | `importacion.js`, `cobranzas.js`, … cargados siempre | 796 KB | cargar al abrir la pantalla | medio |
| F7 | `?v=APP_VERSION` en 10 archivos: cada bump rebaja todo | 54 bumps desde el 09/10 | `?v=` por hash del archivo | medio |
| F8 | `reg.update()` del SW cada 60 s | 60 req/h por dispositivo | sólo si `version.json` trae versión nueva | bajo |
| F9 | `gv_ppp_prog_arbol` cada 60 s por TV / Mon. Admin | 1:40 h | TTL 3 min | bajo |
| F10 | ~45 funciones sin llamador, `openCobranzas` duplicada, 3 constantes sin uso, 164 clases CSS sin uso | ~40 KB | borrar por tandas con la suite en verde | bajo |
| F11 | 6 normalizadores distintos de código de artículo (`_mvNorm` / `_irNorm` no sacan ceros) | — | unificar en `_ocgNorm`, probar con «058» | bajo-medio |
| F12 | 240 copias del header de auth; 94 escrituras con la clave pública | — | un `gvHdr({write})` | medio-alto |

## 4. Normalización — lo que NO se aplicó

| # | qué | medición | por qué espera |
|---|---|---|---|
| N1 | `es_super` falso para todos los súper de Chef en 3 vistas de cruce (`'ch'` vs `'chef'`) | 62 NP Cencosud/Dorinka; 10 entran al Telegram de cruce sin deber | cambia lo que ve la conciliación y el aviso |
| N2 | `GV_Precio_Facturado_Cache`: el mismo cliente con 2-3 grafías (`118` / `00118`) | 440 clientes con gemela; 19 precios viejos; 135 clientes sin precio | cambia precios valorizados |
| N3 | trigger `trg_gv_ppp_web_base_sin_l_chef` le saca la L a líneas de Chef | sin log: no se sabe cuántas peló | choca con la regla de la L (21/09); decide el dueño |
| N4 | dos vocabularios de empresa (`lk/chef` y `LK/CH`) | 75 + 25 tablas, 36 funciones traducen | unificar rompe todo y el bot por FDW: **no se toca** |
| N5 | tablas sin lector en este repo (`pe_eventos`, `pe_resultados`, `Flejes_KG_Desp_x_Uni`, …) | 6 tablas | falta grepear `produccion-virgilio` |

## 5. Aplicado después (v31.38, D2 de Thomas)

- F1 resuelto: el TP pide sólo los movimientos de la familia de códigos de la tanda (`stockFetchMovs(cods)`), no la tabla entera. Medido como anon: 2 códigos = 2.604 filas en 5 ms, contra 86.572 filas / 25,2 MB. Test: `tests/tp-movs-filtrados.cjs`.
- Auditoría: registrados «Facturación: la lista de NP ya facturadas cortaba en 1.000 filas» (corregido, 26b5986) y «Cron 112 gv_gp2_espejo_sync falla el 3,9 %» (abierto).

## 6. v31.39 — D6: crons en horario

- 34, 55, 68, 81 y 109 corren igual de 5:00 a 22:59 y paran de 23:00 a 4:59 (30 días medidos: 0 movimientos, 0 eventos, 0 facturas, 0 fichadas en esa franja).
- El 25 (fichadas) queda las 24 h: `watchdog_syncs_externos` manda un Telegram si pasa 30 min sin correr. Achicarlo exige tocar el vigilante.
- D3 (regla que pela la L en Chef): **sin decidir**. Se apagó por error menos de un minuto y se reactivó; no entró ningún renglón en ese lapso.

## 7. Decidido por Thomas (16/10) — no revisitar

- **D3: NO se toca** `trg_gv_ppp_web_base_sin_l_chef`. Sigue activo pelando la L de Chef cuando el código no está en `precios_venta` de LK. No volver a proponer apagarlo salvo que lo pida el dueño.
- **D5: el schema `gt` y el cron 126 (`gt.sync_pedidos_tn`) SÍ se usan.** No proponer sacarlos.
- Abierto: D7 (cron 25 de fichadas de 2 a 5 min).
