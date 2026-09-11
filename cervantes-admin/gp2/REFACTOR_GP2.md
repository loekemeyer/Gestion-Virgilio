# REFACTOR_GP2.md — bitácora de la auditoría de arquitectura (2026-09-04)

> Registro de los cambios de la auditoría/refactor en loop de 7 horas sobre GP2 (base +
> código). Cada bloque dice QUÉ se cambió, POR QUÉ, CÓMO se verificó y qué queda pendiente.
> Las dudas que dependen de una regla de negocio están en `PREGUNTAS_ARQUITECTURA_GP2.md`.
> Los cambios en Supabase quedan aplicados como migraciones `refactor_20260904_*` (no las
> versiona git; `db/` se regenera al final).

## Resumen ejecutivo (al cierre, 2026-09-05 08:40 AR)

Siete horas efectivas de loop analizar → detectar → corregir → validar → re-analizar, de reloj:
2026-09-04 17:44 → 19:13 AR (1 h 29), 22:00 → 01:32 AR (3 h 32) y 06:40 → 08:40 AR (2 h 00), con
dos cortes por límite de uso de la cuenta en el medio (19:13 → 22:00 y 01:32 → 06:40 AR) que no
cuentan. Las horas de cada ciclo son las de sus commits en git. 40 ciclos (1, 1b, 2, 2a–2z, 3–15)
y 9 agentes: 5 de la primera ronda (tablas, datos, código muerto, funciones, ubicaciones — dos
murieron con el primer corte y se terminaron a mano), `gp2-auditor-costos` y `gp2-experto` como
segunda opinión (el experto dos veces: al final de la primera noche y al cierre, donde encontró
que la regla de OC gemela generalizada en el ciclo 10 era un modelo que el usuario había dado de
baja el 04/09 → pregunta 28), y `gp2-verificador-ui` como gate final (3 corridas de la suite,
render a 390 px: APTO). 50 commits, todos en `main`. Al cierre se liberó el LockX de `LOCKS.txt`.

| | Antes (17:44 AR) | Después |
|---|---|---|
| Tablas GP2 | 67 | **47** (−20: 13 fotos `snap_*`/backup, `agente_propuestas`, `tallerista_alias`, `ruta_confirmada`+`ruta_problema`→`ruta_revision`, `estadistica`, `entrega_cervantes`, `precio_servicio`, `devolucion_tallerista`→`movimiento.nota`, `proveedor_servicio_alias`→`proveedor_servicio.nombre_corto`) |
| Vistas | 16 | **13** (−5 muertas, +`v_nivel_stock` y +`v_contraparte_parte`, cada una reemplaza un CTE escrito dos o tres veces) |
| Funciones/RPC | 135 | **119** (−20: 16 sin llamador o duplicadas, `cargar_compra_altrak`/`aperam_chapa`, `control_cajas_bundle`/`control_kg_bundle`; +`ubic_de`, +`descontrolar_recepcion`, +`cargar_compra_mp`, +`control_recepcion_bundle`) |
| Tablas sin RLS | 16 | **0** |
| Funciones internas ejecutables por `anon` | 20 | **0** (23 internas con REVOKE; 96 RPC de pantalla) |
| Columnas borradas | — | 12 (`produccion` ×4, `tallerista.clase`, `fleje_detalle.kg_x_uni`, `ruta_paso.articulo_id`, `matriz.tipo_matriz`, `articulo.estadistica_madre_uni_mes`, `tarifa_servicio.unidad`…) |
| Constraints nuevos | — | CHECK vocabulario `tipo_mov` (16 palabras), `componente.unidad_medida`, `familia.nombre` UNIQUE, alias en mayúsculas; FKs `articulo.familia`, `articulo.componente_caja_id`, `recepcion_insumo.movimiento_id`; índices únicos `ubicacion(tipo,ref_id)` y singletons; índices `movimiento(fecha,id)`, `movimiento(tipo_mov,comp_id)`, `produccion(legajo,fecha)`; ciclos 8–9: 15 vocabularios cerrados más (`movimiento.unidad_*` `kg`/`uni`, `ubicacion.tipo`, `ruta_paso.tipo_paso`, `inventario.*_origen`, `moneda` ×5, `unidad` ×2, `empresa`, `tipo_entrega`) |
| Archivos del repo | 133 HTML + ~160 JS/MD/… | **−90** (74 muertos, 9 pantallas de stock → 1, docs fusionadas) |
| Copias de helpers en pantallas | 79 `esc`, 42 `$`, 45 `fmt`, 12 "hoy", 40 `createClient`, 3 CSV | **0** (viven en `gp2-ui.js`, `gp2-numero.js`, `supabase-config.js:GP2_SB`); sólo Recepción Insumos conserva su parser a propósito (7259) |
| Tests | 33 | **37** (+`test_stock_sector`, `test_helpers_ui` con 5 reglas, `test_smoke_gp2` sobre las 47 pantallas, `test_contratos_db` con 5 reglas — toda `rpc()`/`from()` de las pantallas existe en `db/`, cada columna pedida existe, cada clave `p_*` es un parámetro real y no falta ninguno obligatorio —; `test_numero` con 4 reglas) |
| Bugs vivos encontrados y arreglados | — | **10**: `talleristas_bundle` sin `partes` (Control Talleristas vacío), `recepcion_tall` vs `entrega_tallerista` (dos palabras, un evento), `consumo_armado` no contado como entregado, `crear_entrega_ps` con la unidad de la SC en una cantidad de SP, «Desmarcar» del control de recepciones roto desde el 31/08, PS 12 AJ Adhesivos sin ubicación (`crear_envio_ps` explotaba), 6 "hoy" en UTC (día corrido después de las 21:00), otros 3 PS + 1 Prov AT sin ubicación porque `alta_proveedor_servicio` no la creaba (causa raíz arreglada, ciclo 2s), una entrega de Virgilio (160 cajas del 510) que el espejo perdió por ese mismo hueco y nadie reintentaba (repuesta, ciclo 2w), y `crear_oc` sumando los paquetes de Charcas como kg para la OC gemela a Altrak (latente: sin OC afectada, ciclo 9) |
| Invariantes de la base | — | **29** en `db/verificar.sql` (contrapartes con ubicación, inventario = ledger, grants, RLS, `search_path`, PS híbridos y su materia prima, códigos, rutas y recetas, espejo de Virgilio, recepción ↔ ledger, claves de `parametro` que lee el código), todas en 0; más 7 consultas informativas con su pregunta/idea |
| Preguntas para el usuario | — | 28 en `PREGUNTAS_ARQUITECTURA_GP2.md` (la 8 con 24 datos; la 27 con 80 renglones mínimo > máximo; la 28, la OC gemela de Charcas: modelo dado de baja el 04/09 que el código sigue haciendo) |
| RPC probadas en vivo (rollback) | — | **105**: 45 de lectura + ~60 de escritura con deltas de inventario verificados, 0 errores (ciclos 2o, 2q, 2s, 2u) |
| Ideas registradas | — | 7250–7266 en `IDEAS-GP2.md` (7253, 7256, 7257 y 7262 ya hechas; 7255 y 7265 a medias) |

Verificaciones al cierre (08:30 AR): `db/verificar.sql` 29 invariantes en 0; conservación
ledger↔inventario 0 desvíos tras un circuito de escritura de 7 llamadas en rollback; las 111
llamadas `rpc()` y 26 `from()` de las pantallas cruzadas contra `db/` (`test_contratos_db`, 5
reglas); 0 hrefs rotos; advisor de seguridad de Supabase: 0 hallazgos en GP2 (697, todos en
`public`); advisor de performance: sólo INFO (14 FKs sin índice en tablas de decenas de filas, 5
índices sin uso todavía) — decisión: no indexar tablas chicas; suite 37/37 en 7 corridas hoy (una
falló por solaparse con la suite del verificador: idea 7266) y gate de UI APTO; `db/` regenerado
(md5 119/119). Todo en `main`.

## Punto de partida (2026-09-04 17:44 AR)

| | Antes |
|---|---|
| Tablas GP2 | **67** (13 eran `snap_*` / backup sin ningún uso, 3 sin RLS además de esas) |
| Vistas | 16 |
| Funciones/RPC | **135** (14 sin ningún llamador: ni pantalla, ni función, ni trigger, ni cron) |
| Suite UI | 33/33 OK |
| Archivos HTML en el repo | 133 (≈50 son pantallas del programa viejo contra `public`) |

Problemas principales detectados en el mapa inicial (detalle en las secciones de cada ciclo):
- Tablas temporales de sesiones anteriores acumuladas en la base (`snap_*`, `*_backup_*`).
- Funciones huérfanas (bundles sin pantalla, trigger functions nunca colgadas, shims a `public`).
- Varias fuentes de verdad para el mismo dato: `est_madre` vs `articulo.estadistica_madre_uni_mes`;
  `tallerista.ubicacion_stock_id` vs `ubicacion(tipo, ref_id)`; `fleje_detalle.kg_x_uni` vs
  `componente.kg_x_uni`; 4 candidatas a "unidades por caja"; 3 tablas de alias; 5 tablas de precios.
- Módulo viejo de Relevamiento (schema `relevamiento_cervantes`) todavía linkeado desde la tablet.

---

## Ciclo 1 — limpieza segura de la base (17:45–18:05 AR)

### Tablas eliminadas (14)
| Tabla | Filas | Por qué | Respaldo |
|---|---|---|---|
| `snap_costo_20260903`, `snap_costo2_20260903`, `snap_costo_516`, `snap_costo_maspoli`, `snap_costo_pliegos`, `snap_costo_pliegos_0903`, `snap_costo_remaches` | 574–575 c/u | fotos de `v_costo_componente` para comparar antes/después de cambios ya cerrados (IDEAS 7218–7240). Recomputables. | no hace falta (vista) |
| `snap_recepcion_20260903`, `snap_mov_recepcion_20260903`, `snap_inventario_20260903` | 81/81/1056 | copia previa al borrado de las 81 recepciones DE PRUEBA (IDEAS 7220, aprobado por el usuario) | eran datos de prueba |
| `snap_recepcion_maspoli`, `snap_precio_mangos_maspoli` | 6/3 | copia previa del cambio Maspoli (cerrado) | — |
| `inventario_minimo_backup_20260902` | 1054 | foto previa al `recalcular_minimos()` del 2026-09-02 | **`db/respaldo_inventario_minimo_20260902.csv`** (las 378 filas que cambiaron, con mínimo anterior y recalculado) |
| `agente_propuestas` | 0 | el agente diario registra en `IDEAS-GP2.md` (git), nunca usó la tabla | — |

Verificado antes de borrar: ninguna función, vista, trigger ni archivo del repo las nombra
(regex sobre `pg_proc.prosrc`, `pg_get_viewdef`, `pg_depend` y `grep -r` en HTML/JS/SQL).
Migración: `refactor_20260904_drop_snapshots`, `refactor_20260904_drop_funciones_muertas_1`.

### Seguridad
- `relevamiento`, `relevamiento_cronograma`, `relevamiento_item` eran las únicas tablas vivas sin
  RLS (nacieron el 2026-09-04): ahora RLS + policy `p_gp2_select` (anon/authenticated) como el
  resto del schema. La escritura ya iba sólo por las RPC `relevamiento_*` (SECURITY DEFINER).
  Migración `refactor_20260904_rls_relevamiento`. **Advisor: 0 tablas sin RLS.**
- `relev_factor` y `relev_total_uni` eran las 2 únicas funciones GP2 sin `search_path` fijo
  (advisor `function_search_path_mutable`): `set search_path = 'GP2'`
  (`refactor_20260904_search_path_relev`). Advisor de seguridad para GP2: 0 hallazgos.
- Advisor de performance para GP2 (solo INFO): 10 FKs sin índice en tablas de <500 filas y 9
  índices sin uso en tablas chicas. No se agregan índices a tablas de decenas de filas; los
  índices sin uso se revisan en el ciclo de índices.

### Funciones eliminadas (14)
| Función | Por qué |
|---|---|
| `control_remaches_bundle()` | stub `select control_kg_bundle(8)`; las pantallas llaman `control_kg_bundle` directo |
| `despiece_bundle()` | reemplazada por `despiece_verif_bundle` (2026-08-30) |
| `entregas_tallerista_bundle()`, `envios_tallerista_bundle()`, `partes_por_tallerista()` | sin pantalla desde 2026-08-29 (Control Envíos y Entregas las cubre); la tercera sólo la llamaba la segunda |
| `fn_espejo_entrega_tallerista()`, `fn_espejo_produccion()` | trigger functions nunca colgadas de un trigger; producción es nativa (decisión 2026-08-29) y el espejo vivo de Virgilio es `fn_entregas_virgilio_espejo` |
| `recepcion_virgilio_bundle()` | sin pantalla (Entrega Virgilio sigue en la app vieja) |
| `stock_bundle()` | Stocks General usa `stock_sector_bundle` |
| `nuevo_codigo_propuesta()` | sólo servía a `agente_propuestas` |
| `rc_agregar_lugar`, `rc_borrar`, `rc_generar`, `rc_set_conteo` | shims de 60 chars que reenviaban a `public.rc_*` para la pantalla vieja de Relevamiento (borrada, ver abajo) |

Verificado: `grep -r` del nombre en todo HTML/JS (sin tests) = 0 llamadas; ningún trigger
(`pg_trigger.tgfoid`), ningún `cron.job`, ninguna otra función las nombra.

### Código eliminado
- `Relevamiento/relevamiento.html` + `relevamiento.js` (84 KB, schema `relevamiento_cervantes`
  vía `public.rc_*`), `Relevamiento/_backup_relevamiento_20260731.{html,js}` (foto de backup con la
  clave anon embebida) y `Relevamiento/db.sql` (DDL del schema viejo). Decisión del usuario
  2026-09-04: *"borrá relevamientos (viejo) y dejá solo relevamiento gp2 (nuevo)"*. La tablet
  (`envios-only.html`) y la lista del rol `envios` en `auth-guard.js` pasan a
  `Relevamiento/Relevamiento_GP2.html`.
- `tests/ui/test_tokens_cache.js`: el backup deja de estar en la lista de archivos permitidos con
  la clave.

### Docs
- `CONOCIMIENTO_GP2.md` §2e-bis y §4q actualizados (dónde vive el respaldo de mínimos; el módulo
  viejo de Relevamiento ya no existe).

### Estado tras el ciclo 1
53 tablas · 16 vistas · 121 funciones · 0 tablas sin RLS.

---

## Ciclo 1b — código muerto del repo (agente A3, 18:05–18:21 AR)

Auditoría de alcance desde las 7 entradas (index, login, GP2_MODULOS, envios-only, manifest,
los 2 sw.js) siguiendo todo href/src/location/MENU: **247 assets → 121 alcanzables / 126 no**.

### Archivos eliminados (74, ≈1,74 MB, ≈41.500 líneas) — todos en git si hacen falta
| Grupo | Archivos | Evidencia |
|---|---|---|
| Export generado | `Despiece x Articulo/_export/` (6; 1,12 MB) | nadie lo carga; `despiece_lib.js` leía `public` por REST con la clave anon embebida |
| Planificación vieja | `.planning/` (23; 219 KB) | GSD abril–mayo 2026 sobre un Electron que nunca existió; 0 referencias |
| Prototipo OCR | `Talleristas/Recepcion/ocr-segmentos/` (6; 74 KB) | tests de mesa y plantillas; `test-lector.html` cargaba un JS que ya no estaba ahí |
| Pantallas GP2 jubiladas hoy | `Compras/AltrakCharcas_GP2.html`, `Compras/AperamEclipse_GP2.html`, `Prov Serv/CharcasEclipse/` | menú v1.18/1.19/1.20 (2026-09-04): el flujo pasó a Recepción Insumos y Entrega PS; sin link, sin test |
| Backups y fotos | `_legacy_EntregasAT.{html,js,css}.bak`, `Produccion/InformesVirgilio/Code.gs.backup`, `Produccion/.claude/settings.json` (ruta UNC) | copias congeladas / leftovers |
| JS/CSS sin cargador | `helpers.js` (además rompía al cargarse: `PROV_AT` sin definir), `cajones-popup.js/.css` (`cajonesPopup` nunca invocado; se sacaron sus 2 etiquetas de EnviosPS.html y EnviosTall.html), `StockFlejes/flejes.js/.css` (nadie los carga; clave anon embebida) | grep en todo el repo |
| Assets | `en-stock.ico`, `en-stock.png` (favicon viejo), `Art` (0 bytes), `Produccion/ejemplo_reporte.html` | 0 referencias |
| Docs superadas | `CONTEXTO_SESION_2026-08-29.txt`, `E2E_TEST_RESULT_2026-08-28.md`, `ESTADO_MIGRACION_GP2.md`, `AUDIT_COMPLETO_2026-04-19.md`, `INFORME_AUDITORIA_SUPABASE.md`, `PROBLEMAS_CODIGOS_ISIS_2026-07-15.md`, `SC_sin_vincular_SC_Kg.txt`, `Diagrama_Sistema.html`, `Onboarding-Gestion-Productiva.html` | handoffs de agosto y auditorías del vecino (abril/julio); 0 referencias; lo vigente vive en CONOCIMIENTO/IDEAS |
| SQL y scripts one-off sobre `public` | `Cod_ISIS_Pedernera_2026-07-15.sql`, `SQL_INSERT_SP_Kg.sql`, `SQL_UNIFICAR_CP4_GRJ3.sql`, `SQL_TRIGGERS_SINCRONIZACION.sql`, `gen_sql.sh`, `envios_excel.py`, `read_conteo_*.py` (4) | ya aplicados en la casa del vecino; leen rutas `S:\` y Excel con fecha |
| Dependencias sin uso | `package.json`, `package-lock.json` | ningún archivo hace `require`; los tests usan Playwright global |
| Redirect duplicado | `Inicio/index_GP2.html` | `Inicio/index.html` hace lo mismo; se dejó ese (lo abre `test_login_flow`) reducido a 14 líneas |

### Ediciones que acompañan
- `StockFlejes/control-cajas.html` y `control-remaches.html`: el botón Atrás caía en
  `StockFlejes/index.html` (el menú VIEJO de insumos, que resucitaba 4 stocks de `public`);
  ahora vuelve a `GP2_MODULOS.html`.
- `tests/ui/test_tokens_cache.js`: la clave anon ya no tiene excepciones (solo `supabase-config.js`).
- `tests/README.md`: la tabla listaba 16 tests (uno inexistente) y omitía 17; ahora los 33.
- `CLAUDE.md` (referencia a `Inicio/index_GP2.html`), `CONOCIMIENTO_GP2.md` §2i-bis (los `.bak`).

### Lo que NO se borró (decisión del usuario, ver PREGUNTAS 1–2 y 4–6)
Las ≈120 páginas del programa viejo contra `public` (29 todavía linkeadas desde la tablet o
la whitelist; 91 sin ningún link), los 5 módulos con candado del menú, los redirects de
cortesía, y las docs que todavía referencia alguien (`AUDITORIA_RUTAS_2026-04-18.md`,
`Tablas_Madre_y_Dependencias.xls`, `SQL_GP2_PENDIENTES.sql`, `ANALISIS_GP2_2026-08-28.md`,
`AUDITORIA_GP2_2026-08-31.md`, `PENDIENTES_UBICACIONES_2026-08-30.md`, `MACRO_ENTREGAS_SUPABASE.bas`).

### Duplicación de código detectada (para los ciclos siguientes)
`esc()` ×79, `fmt()` ×45 (8 variantes), `$()` ×42, 3 semánticas de "hoy" (2 en UTC),
52 `createClient` inline, 4 frameworks de popup, 9 pantallas de stock por sector 86–96 %
idénticas, `control-cajas` / `control-remaches` 74 % iguales, `gp2-modulo.css` y
`gp2-claro.css` definiendo los mismos 17 selectores. Detalle en el informe A3.

---

## Ciclo 2 — funciones, vistas y seguridad (agente A4, 18:21–18:46 AR)

### Bug vivo corregido: `talleristas_bundle` no coincidía con sus pantallas
La versión en la base devolvía `partes` como **lista plana** (`codigo`, `descripcion`,
`online`), pero `EnviosTalleristas_GP2.html` y `ControlTalleristas_GP2.html` leen
`D.partes[tallerista_id].entrada[]` con `cod`, `desc`, `online_tall`, `online_sector`, `saldo` —
el contrato que la función tenía en el export del 2026-08-31. Con la función de hoy cada
tallerista mostraba **0 partes** (los tests no lo veían porque stubean el bundle con la forma
que espera el JS). Se restauró el diccionario por tallerista conservando el filtro
`tallerista.activo` y los saldos actuales; la clave `bom`, que nadie leía, se fue.
Verificado: 10 talleristas con partes, Martin Cornejo 83 de entrada, claves correctas.
Migración `refactor_20260904_talleristas_bundle_partes_por_tallerista`.

### Borrados
- `cargar_recepcion_charcas(p_comp_id, p_paquetes, p_remito, p_fecha)`: modelo viejo por paquetes
  que exigía el componente `ALAM_FILTRO`, que **no existe** (explotaba siempre); la pantalla llama
  a la de 5 args (`p_uni_remito` + `p_kg_balanza`).
- Vistas sin ningún lector: `v_consumo_fleje_kg` (v1: contradecía a la `_v2` en 5 flejes),
  `v_consumo_parte` (contradecía a `v_consumo_componente` en 209 componentes), `v_punto_stock`,
  `v_valor_pedido`, `v_valor_stock` (Valorización recalcula lo mismo en su bundle). 16 → 11 vistas.
  Migración `refactor_20260904_drop_vistas_y_overload_muertas`.
- `crear_oc(p jsonb, p_fecha_entrega date)`: wrapper que metía en `p` un dato que `OC_GP2.html`
  ya mandaba adentro de `p`. La pantalla pasó a llamar con un solo parámetro (ciclo 1b); la
  overload se borra en cuanto el deploy de la pantalla esté publicado.

### Seguridad
- 20 funciones internas (helpers `_aplicar_recepcion_a_oc`, `to_canonical`, `_es_sector_insumo`,
  `relev_*`, `recepcion_tara`, `crear_recepcion_insumo`; las 8 trigger functions `fn_*`;
  `recepcion_virgilio`; mantenimiento `recalcular_*`; cron `actualizar_dolar_oficial`) tenían
  EXECUTE para `anon` por el default de Postgres: con la clave anon cualquiera podía pisar
  máximos/mínimos, marcar OC recibidas o disparar el HTTP del dólar. **REVOKE** a
  public/anon/authenticated. Verificado con una prueba con rollback que un trigger dispara aunque
  el rol que hace el DML no tenga EXECUTE sobre su función.
- `alter default privileges ... revoke execute on functions from public`: las funciones nuevas
  ya no nacen públicas; las 18 RPC de pantalla que dependían del default pasan a GRANT explícito.
  Migración `refactor_20260904_revoke_funciones_internas`.

### Performance
- `movimiento` no tenía índice por `fecha` ni por `tipo_mov` (8 bundles filtran por eso):
  `movimiento_fecha_idx (fecha desc, id desc)` y `movimiento_tipo_comp_idx (tipo_mov, comp_id)`.

### Datos corregidos (agente A2, «corregible sin duda»; migraciones `refactor_20260904_datos_corregibles_1`, `_est_madre_guard_y_crear_oc_overload`, `_borrar_pruebas_rollos_produccion`)
| Qué | Filas | Detalle |
|---|---|---|
| `componente.unidad_medida` fuera de {kg, unidad} | 19 | `uni`×7, `pliego`×11, `paquete`×1 → `unidad` + CHECK para que no vuelva |
| Familias inexistentes | 2 | `Bombillas` (11 artículos) y `Bowls` (071) faltaban en `familia`; ahora `articulo.familia` es FK |
| Caja en la columna pero no en la receta | 13 | 11 bombillas + 103 + 120 + 071 tenían `componente_caja_id` (y 11 de ellos el paso `insumo` de la caja en su ruta) sin la fila 1/`articulos_por_caja` en `articulo_componente`, como llevan los otros 86. La demanda de A8/A11/A9/A4 no llegaba a OC ni a máximos. (071: ver PREGUNTAS 8.18) |
| `est_madre` con filas contables | 5 | `E`, `GASTOTRRECH`, `CHEQRECHAZAO`, `ANTICIPO VTA MERCAERIA`, `TRANSFRECH` venían de `public.proyeccion_madre`; borradas y el trigger `fn_est_madre_sync` ahora saltea todo código que no empiece con dígito |
| Mínimos en unidades sobre componentes en kg | 7 | IC3 100.800 → 836,64 kg, IE13, IZ19A y sus filas en tallerista/Virgilio: convertidos con `kg_x_uni`, `minimo_origen='excel_uni_convertido_kg'` |
| Inventario ≠ ledger (IC3 / IC3V) | 4 | al pasar IC3/IC3V de unidad a kg quedaron 2 movimientos con `_delta` viejos y 4 filas de inventario sin re-derivar (IC3@Fleje decía 510; el ledger 33,98 kg). Se recalcularon los deltas (1459, 1463) y se re-derivó el inventario de los dos componentes desde el ledger. Conservación: **0 filas que no cierran** en todo el inventario |
| Restos de pruebas | 31 + 1 + 3 | 31 `rollo_evento` (61 rollos fantasma de recepciones de prueba ya borradas), el `rollo_uso` abierto y las 3 filas de `produccion` del legajo 1 «Pruebas» |
| BOM13 / BOM14 | 3 | filas en cantidad 0 en Sector Garage (resto de cuando eran sector 9) borradas; BOM14 sin fila en Sector Bombilla, creada |
| `precio_proveedor` | 14 | `moneda='Peso'`×11 → `ARS`; `cod_prov='Cimarron'`×3 → `4444` |
| `empleado.tipo` | 3 | `Operario` → `operario` |
| Recepción 415 | 1 | pliego con `uni_x_paq=250` → 100 (regla del paquete de pliegos) |
| `ruta.nombre` | 3 | 611/615 «(Cimarron)» → «(Gentile Norberto)» (el tallerista real del paso); 35 = RULETA (herramienta, sin artículo) |
| Alias | 3 | `LUCHO`/`MASPOLI` pasan de `tallerista_alias` a `contraparte_alias`; `Oscar` y `Becker Sandra Nora` a mayúsculas (el trigger compara `upper()`, nunca matcheaban); `'Carlos'→Alex` borrado (contradecía `'CARLOS'→Carlos Aguirre`; PREGUNTAS 7); CHECK `alias = upper(alias)` |

### Tablas y columnas eliminadas (ciclo 2a)
- `pedido` (0 filas, ningún uso), `tallerista_alias` (sin lector desde el ciclo 1), `tipo_cambio.moneda`
  (constante, la PK es la fecha).

### Vocabulario de `tipo_mov`: una sola palabra para "el tallerista entregó"
El motor JS (`gp2-motor.js`, pantalla Entregas Talleristas GP2) escribía `recepcion_tall`, la
API SQL (`crear_entrega_tallerista`) escribe `entrega_tallerista`, y los bundles de talleristas
(`talleristas_bundle`, `faltante_partes_tallerista_bundle`, `control_envios_bundle`) sólo leen
`entrega_tallerista` → las 3 entregas cargadas desde la pantalla GP2 **no contaban como
entregadas** en Control Talleristas ni en Faltante Partes. Se unificó en `entrega_tallerista`
(JS, test y las 3 filas del ledger; los deltas no cambian). Queda para el cierre del ciclo 2:
`consumo_armado`/`consumo_transformacion` (SQL) → `consumo_tall` (lo que leen los bundles) y un
CHECK con el vocabulario cerrado.

### Docs
- `TABLET_LOGISTICA.md` (specs físicas de la tablet) se fusionó en `CONOCIMIENTO_GP2.md` §3c-quater
  y se borró. `SQL_GP2_PENDIENTES.sql` tenía todos sus bloques aplicados (los `_bak_*` que
  esperaban confirmación ya no existen) y se borró; `GP2_MAPA.md` dejó de citarlo y corrigió dos
  frases viejas ("la tabla empleado no existe", "falta persistencia de Verificación").
- `CLAUDE.md`: referencias a archivos que no están en el repo (`ANALISIS_LOGICA_GP2.md`, los 3
  HTML con `var D`) corregidas; sección nueva que apunta a `GP2_MAPA.md`, `REFACTOR_GP2.md`,
  `PREGUNTAS_ARQUITECTURA_GP2.md` y `db/`.

### Código: 9 pantallas de stock por sector → 1 (agente B4)
`StockSC_GP2`, `StockSP_GP2`, `StockMovimiento_GP2` y las 6 de `StockFlejes/*_GP2` (Cajas,
Cartones, Plásticos, Remaches, Bombillas, Garage) eran 9 HTML de ~98 líneas, 86–96 % idénticos
(sólo cambiaba `window.STOCK_CFG`). Ahora es **una** pantalla,
`StockSector/StockSector_GP2.html?sector=<id>`, con la configuración por sector en el mapa
`SECTORES` de `gp2-stock-sector.js`. El menú mantiene los 9 botones con los mismos rótulos y
orden. Verificado por diff del DOM renderizado viejo vs nuevo (7 byte-idénticas; SC/SP sólo cambian
el link cruzado, que apuntaba a un archivo que ya no existe) y render a 390 px en los 9 sectores.
Test nuevo `tests/ui/test_stock_sector.js` (186 aserciones). Neto: −662 líneas de app.
Los rótulos de tipos de movimiento de `gp2-composicion.js` y de Stocks General pasan al
vocabulario real del ledger (tenían los nombres del programa viejo).

### Estado tras el ciclo 2a
51 tablas · 11 vistas · 120 funciones.

---

## Ciclo 2b — podas y fusiones con edición de funciones (agente B2, 18:46–18:57 AR)

Cada migración `refactor_20260904_b2_*` comparó el md5 del JSON de los bundles antes/después
(sin `generado_en`) y abortaba si algo cambiaba fuera de lo pedido.

| Cambio | Detalle | Verificación |
|---|---|---|
| `ruta_confirmada` + `ruta_problema` → **`ruta_revision`** | una fila por firma con `estado` confirmada/pendiente/resuelto; `ruta_confirmar/reportar/resolver` reescritas con la misma firma; `despiece_verif_bundle` devuelve las mismas claves que lee Despiece_GP2 | prueba con rollback: reportar → re-reportar (mismo id) → resolver → confirmar |
| `ruta_paso.articulo_id` y `componente_fleje_id` **borradas** | 620/620 = `ruta.articulo_id`; 216/216 = entrada del paso 1 (tipo `ingreso`, sector Fleje). Los 4 bundles que las exportaban las derivan por join | 47/47 claves de bundle idénticas antes y después |
| `articulo.estadistica_madre_uni_mes` **borrada** | difería de `est_madre.proy_uni_mes` en 87/87 y Despiece calculaba demanda con ese número viejo. `abm_articulos_bundle`, `despiece_verif_bundle`, `faltantes_bundle`, `movimientos_bundle` devuelven `est` desde `est_madre`; `abm_articulo_upsert` pierde `p_estadistica` (firma de 5 args); el ABM muestra el campo sólo lectura | sólo cambia la clave `art`; test_bom OK |
| `matriz.tipo_matriz` y `primera_del_fleje` **borradas** | `tipo_matriz` sin ningún lector (la 118 «501» pasa a `tipo='P'`, piedra); `primera_del_fleje='SI'` ≡ `partes_por_kilo_de_fleje is not null` en 115/115, los 3 bundles lo derivan | md5 de `mat` idéntico salvo el tipo de la 118 |
| `tallerista.entrega_cervantes` **borrada** | 0 usos (era true en Alex, Martin, IJUPA: el dato queda en CONOCIMIENTO) | guard por regex en la migración |
| `precio_servicio` **borrada** | modelo viejo (precio único por PS), 0 filas; `v_costo_componente` sin la CTE `psrv` | md5 de las 591 filas de la vista idéntico |

Desvío documentado: el "fleje de la ruta" se define como entrada del paso 1 **de tipo `ingreso`**
(5 rutas con paso 1 `insumo` IE13/IZ19A nunca tuvieron fleje marcado y siguen igual; si el
negocio quiere contarlas, es sacar esa condición en 4 bundles).

### Estado tras el ciclo 2b
49 tablas · 11 vistas · 121 funciones (hubo +1 por `ubic_de`, ver ciclo 2c).

---

## Ciclo 2c — una sola puerta para las ubicaciones (agente B1) + helpers de pantalla en un archivo (agente B5), 18:26–22:15 AR (con el primer corte, 19:13–22:00, en el medio)

Los dos agentes murieron a mitad de camino por el límite de uso de la cuenta (22:13 UTC; volvió a
la 01:00 UTC). Lo que dejaron se verificó a mano y se terminó desde la sesión principal.

### Base: `ubic_de(tipo, ref_id)` (32 migraciones `refactor_20260904_ubic_*`)
- **Problema**: 25 búsquedas de `ubicacion` repartidas en 15 funciones, tres de ellas **por
  nombre** (`crear_envio_ps`, `crear_entrega_ps`, `crear_envio_tallerista`: renombrar un sector
  las rompía), el resto por `ref_id`, y dos funciones que ignoraban el override
  `tallerista.ubicacion_stock_id`.
- **Hecho**: función `"GP2".ubic_de(p_tipo, p_ref_id)` (STABLE, `coalesce(override del
  tallerista, ubicacion por (tipo, ref_id))`). Reescritas para usarla: `crear_envio_ps`,
  `crear_entrega_ps`, `crear_envio_tallerista`, `crear_entrega_tallerista`,
  `crear_devolucion_tallerista` (ahora por `ref_id`, ya no por nombre), `crear_envio_prov_at`
  (valida la ubicación del proveedor), `crear_recepcion_insumo`, `cargar_recepcion_charcas`,
  `cargar_recepcion_eclipse`, `cargar_compra_altrak`, `cargar_compra_aperam_chapa`,
  `registrar_evento_prod`, `registrar_produccion`, `recepcion_virgilio`, `relevamiento_aplicar`,
  `relevamiento_cerrar`, `relevamiento_detalle`, `composicion_stock` y los bundles `oc`, `flejes`,
  `envios_ps`, `stock_transito_ps`, `talleristas`, `envios_prov_at`, `control_ps`, `stock_sector`,
  `recepcion`, `orden_produccion`, más la vista `v_faltante_estado`.
- **Índices únicos** `ubicacion_tipo_ref_uq (tipo, ref_id) where ref_id is not null` y
  `ubicacion_singleton_uq (tipo) where tipo in ('virgilio','analisis')`: una respuesta por clave.
- **Dato corregido (A2-06)**: el PS 12 «AJ Adhesivos» tenía 12 pasos de ruta y 12 precios pero
  **ninguna ubicación** (`crear_envio_ps` explotaba). Se creó la ubicación 50 con la misma
  convención que los otros PS.
- **Verificación**: md5 de la salida de 12 bundles/vistas antes y después de reescribirlos:
  idénticos, salvo `talleristas_bundle`, que cambia solo por `now()` (se comprobó que el hash
  cambia también entre dos ejecuciones sin tocar nada). Consulta de control: ninguna función
  del schema contiene ya `from ubicacion ... where nombre`.

### Código: `gp2-ui.js` (helpers de pantalla, UNA copia)
- **Problema (A3)**: 40 `esc()` con tres implementaciones, 33 `$()`, 6 clases por signo, 12
  "hoy" con tres semánticas (UTC / hora del aparato / Argentina: las dos primeras corren el día
  después de las 21:00) y 3 exportadores a CSV, cada uno distinto.
- **Hecho**: `gp2-ui.js` con `GP2UI.esc / $ / cls / hoyAR / fechaAR / exportarCSV`. Los JS
  compartidos (`gp2-envios-common.js`, `gp2-composicion.js`, `gp2-stock-sector.js`,
  `consumo-detalle.js`) ya no traen copia: dependen de `GP2UI` y `GP2N` (que la página carga
  antes; el test `test_helpers_ui.js` vigila el orden). `GP2EE` dejó de reexportar lo que era
  pass-through (`$`, `esc`, `conMiles`, `autoMiles`, `autoMilesEn`, `fechaAR`, `clsSaldo`,
  `genCode`) y `GP2M` dejó de exportar 9 internos que nadie llamaba. `GP2N.fmt` gana un tercer
  parámetro (`nullTxt`) para que las pantallas que muestran «—» sin valor no se escriban su
  propio `fmt`.
- **Pantallas tocadas** (11): Control PS, Pintores, Stock Tránsito PS, Control Talleristas,
  Control Envíos, Envíos/Entregas PS, Envíos/Entregas Talleristas, Stock por sector, Orden de
  Producción: cargan `gp2-ui.js` (+ `gp2-numero.js` las 5 que no lo tenían) y usan los helpers
  de la casa; los tres CSV a mano (Control Talleristas, Control Envíos, Stock Tránsito) pasan a
  `GP2UI.exportarCSV`. "Hoy" en Control PS ahora es la fecha **argentina**.
- **Bug encontrado al hacerlo**: en Control PS la cantidad y los kg se leían con `Number(el.value)`;
  al cargar `gp2-numero.js` (que formatea «1.500» mientras se tipea) eso leería 1,5. Pasan a
  `GP2N.num`. Lo mismo en el popup de tandas (`parseInt` sobre cajones/unidades → `parseEntero`).
  Nueva regla en `test_numero.js`: donde está cargado `gp2-numero.js`, ningún `.value` se lee
  con `Number/parseFloat/parseInt` crudo.
- **Tokens**: `gp2-ui.js 20260905a`, `gp2-numero.js 20260905b`, `gp2-envios-common.js 20260905c`,
  `gp2-composicion.js 20260905d`, `gp2-stock-sector.js 20260905e`, `gp2-motor.js 20260905f`,
  `consumo-detalle.js 20260905g`, `version.js 20260905h` (v1.109.0), `tandas-popup.js 20260905i`.
- **Queda** (para un ciclo siguiente): las ~30 pantallas que todavía no cargan `gp2-ui.js`
  conservan su `esc`/`$` propio; se migran de a tandas con el mismo test como red.

### Estado tras el ciclo 2c
49 tablas · 11 vistas · 121 funciones · 35 tests.

---

## Ciclo 2d — vocabulario cerrado del ledger, dos tablas menos, tres bugs de lógica (22:15–22:27 AR, sesión principal)

Migraciones `refactor_20260905_*` (5), cada una verificada con un `DO` que termina en
`OK_ROLLBACK`.

| Qué | Antes | Ahora |
|---|---|---|
| `crear_entrega_tallerista` | escribía `consumo_armado` / `consumo_transformacion`; los bundles (`talleristas_bundle`, `faltante_partes_tallerista_bundle`) y el motor JS cuentan `consumo_tall` → lo que el tallerista consumía al armar **no se contaba como entregado** | escribe `consumo_tall` (T1: armado H11, 2 hijos, los dos salen como `consumo_tall`) |
| `movimiento.tipo_mov` | texto libre (el JS manda lo que sea por `registrar_movimientos`); tres veces apareció una palabra nueva para un evento con nombre | **CHECK `movimiento_tipo_mov_chk`** con las 16 palabras (T4: `recepcion_tall` rechazado) |
| `devolucion_tallerista` (tabla cabecera, 0 filas) | repetía tallerista (= origen) y destino (= ubic destino) y agregaba `motivo` | **borrada**; `movimiento.nota` (texto libre del operario) guarda el motivo; `crear_devolucion_tallerista` devuelve `id` = movimiento; `devoluciones_tallerista_bundle.ultimas` sale del ledger (T2) |
| `proveedor_servicio_alias` (6 filas: nombre_viejo, ps_nombre, confianza, nota) | un atributo del PS disfrazado de tabla; única lectora `control_ps_bundle` | **borrada**; `proveedor_servicio.nombre_corto` (FAAT, Guazzaroni, Pedernera, Scor, Jade, Ximpa); Control PS muestra «en planta: Jade»; las notas fueron a `CONOCIMIENTO_GP2.md` §4r |
| `v_consumo_fleje_kg_v2` | nombre heredado de cuando convivía con la v1 (borrada el 04) | `v_consumo_fleje_kg`; las 4 funciones que la nombran (`recalcular_maximos_insumos`, `consumo_detalle`, `oc_bundle`, `recalcular_minimos`) reescritas por `replace()` sobre su propia definición |
| `_es_sector_insumo(p)` | `p in (5,6,7,8,9,10,11)` escrito en la función; 6 lectoras | `sector.es_insumo` (columna) + función STABLE que la lee. Comportamiento idéntico; el sector 13 «Alambre» queda fuera como estaba → pregunta 21 |
| `crear_entrega_ps` | la cantidad consumida de la SC se calcula en la canónica de la **SP** pero se declaraba con la unidad de la **SC**: con SC en kg el trigger habría leído piezas como kg | `unidad_origen` sigue a la dimensión de la cantidad (la de la SP); el trigger convierte a la canónica de la SC (T3: IA2 en kg ← A1 en uni: 25,19 uni × 0,0502 = 1,264 kg ✓) |
| `control_ps_bundle`, `control_kg_bundle`, `control_cajas_bundle`, `pintores_bundle` | VOLATILE sin escribir nada | STABLE |

También: pregunta 22 (`entrega_prov_at` es un segundo ledger paralelo a `movimiento`, 125 filas
con datos de remito/factura: se deja y se pregunta).

### Estado tras el ciclo 2d
**47 tablas · 11 vistas · 121 funciones · 35 tests.**

---

## Ciclo 2e — auditoría de columnas (todas-null, constantes, ids sin FK), 22:27–22:33 AR

Consulta generada sobre `information_schema.columns` (count / count(col) / count(distinct col)
para las ~330 columnas de las 47 tablas) + búsqueda de cada columna sospechosa en `pg_proc`,
`pg_views` y el código. Migración `refactor_20260905_produccion_columnas_muertas_fks_clase`.

| Hallazgo | Decisión |
|---|---|
| `produccion.espejo_id`, `fecha_inicio`, `fecha_fin`, `espejado_en`: herencia del espejo `db_n8n_espejo`, ninguna función/vista/pantalla las lee | **borradas** (30 → 26 columnas) |
| `produccion.dia`, `mes`, `quincena`: derivables de `fecha`, pero las escriben `registrar_evento_prod` / `registrar_produccion` (la app de operarios) y las lee `produccion_maestro_bundle` | se dejan: tocar la RPC de operarios sin poder correr el flujo real no vale 3 columnas de una tabla vacía. Anotado como deuda |
| `tallerista.clase`: `'tallerista'` en las 13 filas (los proveedores AT tienen su tabla); única lectora `despiece_verif_bundle` como subtítulo | **borrada**; el bundle devuelve el mismo texto fijo |
| `articulo.componente_caja_id` y `recepcion_insumo.movimiento_id`: ids sin FK, 0 huérfanos | **FKs agregadas** (`on delete set null` en la segunda: `anular_recepcion` borra el movimiento y conserva la recepción) |
| `sector.oc_rubro_id` (sólo Alambre=5): ninguna función la usa | se queda: la lee `OC_GP2.html` directo (`from('sector')`) |
| `orden_compra.creado_por`, `proveedor_insumo.dias_entrega`, `tarifa_servicio.precio_uni`, `articulo_prov_at.marca`: todas null hoy | se quedan: las escriben/leen funciones vivas; son datos que todavía no se cargaron |
| `recepcion_insumo.base/pallets/pisos/rollos/sueltas/controlado_por` (25 filas, todas null) | pesaje por pallet, pregunta 20 |
| `movimiento.cajones` (2 de 221 con valor) y `faltante` (siempre false) | se quedan: los escriben `crear_envio_ps` / `crear_entrega_ps` cuando la pantalla los manda |

## Ciclo 2f — las 30 pantallas restantes pasan a `gp2-ui.js` + test de humo de las 47 pantallas, 22:27–22:33 AR (mismo commit que 2e)

- Script `migra_gp2ui.py` (scratchpad): sólo toca definiciones que reconoce exactamente
  (`function $(id){...getElementById...}`, `const $=id=>...`, `var $ = function(id){...}`, y
  `function esc(...)` cuyo cuerpo sea uno de los idiomas conocidos: `replace(`, `replaceAll(`,
  `createElement('div')`); inserta `<script src=".../gp2-ui.js?v=20260905a">` después de
  `supabase-config.js`. 30 pantallas, 30 OK, ninguna con cuerpo desconocido.
- A mano: 6 "hoy" con `toISOString().slice(0,10)` (fecha UTC: después de las 21:00 era el día
  siguiente) → `GP2UI.hoyAR()` (Despiece, ABM Artículos, Faltante Partes, Proporciones,
  Entrevistas, Tiempos); 3 CSV a mano → `GP2UI.exportarCSV` (Problemas con Matrices,
  Entrevistas, Tiempos).
- **Test nuevo `test_smoke_gp2.js`**: abre las 47 pantallas GP2 con Supabase stubeado y sin
  red; falla si falta un `<script src>` local o si revienta un helper de la casa. Se verificó
  que detecta las dos cosas con una página trampa (`nope.js` + `GP2UI` sin cargar).
- Resultado: 41 pantallas cargan `gp2-ui.js` (eran 11), 0 copias de `esc`/`$`/hoy/CSV en
  ellas (`test_helpers_ui.js`), 36 tests.

### Estado tras el ciclo 2f
**47 tablas · 11 vistas · 121 funciones · 36 tests.**

---

## Ciclo 2g — lógica duplicada en la base (A4 3c/3e/3f/4.7), 22:33–22:41 AR

Migraciones `refactor_20260905_bundles_duplicados_y_fecha_ar` y `refactor_20260905_v_nivel_stock`.

| Qué | Antes | Ahora | Verificación |
|---|---|---|---|
| `faltantes_bundle` | el mismo diccionario que `movimientos_bundle` escrito dos veces (2,2 KB), único llamador Despiece_GP2 | envoltorio: `movimientos_bundle()` con `art` como lista y `mat.primera` nunca null | claves iguales; `comp`/`inv`/`rp`/`bom_*` contenidos; `art` 99/99 contenidos; 61 matrices `primera=true` como antes |
| `movimientos_componente` | copia del CTE de `composicion_stock` | **borrada**; `gp2-stock-sector.js` pide `composicion_stock` y lee `movs` | md5 de la salida idéntico en 3 muestras; `test_stock_sector.js` actualizado |
| `recalcular_maximos_insumos` / `recalcular_minimos` | el CTE «consumo mensual × meses de la ubicación» dos veces | vista **`v_nivel_stock`** (consumo_mes, max_calc, min_calc, es_insumo) y cada función es un `update ... from v_nivel_stock` | md5 de `inventario` (mínimo/máximo/orígenes) tras correr las dos: **idéntico** antes y después (`04d81610…`) |
| `registrar_produccion` | `dia/mes/quincena` en UTC (`registrar_evento_prod` los hace en hora argentina): a las 22:00 caían en días distintos | los tres en `America/Argentina/Buenos_Aires` | texto verificado |
| `alertas_bundle` | motivo de la alerta «stock bajo mínimo» describía agosto (stock negativo irreal) | motivo real: desactivada a propósito, falta la regla → pregunta 24 | |

Quedan anotadas: pregunta 23 (OC en borrador se "recibe"), 24 (alerta), 25 (`recalcular_minimos`
cambiaría 48 mínimos hoy; colgarla del trigger de la Est Madre como los máximos).
No se hizo (riesgo > valor a esta hora): `catalogo_bundle` común a `programa_bundle` (nombres
cortos en `Programa.html`), helper común de `registrar_evento_prod`/`registrar_produccion`
(RPC de la app de operarios), `cargar_recepcion` única sobre configuración
(`proveedor_servicio.mp_componente_id`...). Están en IDEAS-GP2.md.

### Estado tras el ciclo 2g
**47 tablas · 12 vistas · 120 funciones · 36 tests.**

---

## Ciclo 2h — el cliente Supabase en un solo lugar + una columna duplicada menos, 22:41–22:52 AR

- **`fleje_detalle.kg_x_uni` borrada** (`refactor_20260905_fleje_detalle_sin_kg_x_uni`):
  duplicaba `componente.kg_x_uni` (3 filas con valor, las 3 iguales; ninguna función, vista ni
  pantalla la leía o escribía). El peso del fleje tiene una sola fuente.
- **`GP2_SB()` en `supabase-config.js`** (idea 7253): había 40 `createClient(...)` inline en
  cinco formas de texto (con y sin `persistSession:false`, con `SUPABASE_URL`/`SB_URL`/
  `window.SB_URL`, en una o cuatro líneas). Ahora las 38 pantallas/JS GP2 llaman `GP2_SB()`
  (schema `GP2`, sin sesión persistida) y `GP2EE.sb()` delega en él. Quedan a propósito:
  `login.html` (cliente de auth sobre `public`) y `operarios_gp2.js` (opciones de auth propias,
  y su token está atado al auto-recargador). Token `supabase-config.js 20260905k` en las 103
  páginas que lo cargan; `disruptivas_GP2.js 20260905l`.
- **Guardia nueva** (`test_helpers_ui.js` punto 4): ninguna pantalla GP2 ni JS que cargue crea su
  propio `createClient`. `test_smoke_gp2.js`: 47 páginas, 0 fallos, 0 avisos.
- Verificación de seguridad de paso: las 23 funciones sin EXECUTE para `anon` son todas internas
  (helpers, triggers, mantenimiento, cron); ninguna pantalla las llama (grep de `rpc('...')`).

### Estado tras el ciclo 2h
**47 tablas · 12 vistas · 120 funciones · 36 tests.**

---

## Ciclo 2i — reglas de la casa escritas, tres `fmt` menos, índice para operarios, conservación verificada, 22:52–22:56 AR

- **`CLAUDE.md`**: sección nueva «Helpers de pantalla y cliente Supabase: UNA copia
  (OBLIGATORIO)»: `GP2UI`, `GP2N`, `GP2_SB()`, orden de carga y los tres tests guardianes. Es lo
  que hace que el refactor de hoy no se deshaga en la próxima sesión.
- Relevamiento, Validación de Stock y OC: su `fmt` propio (`toLocaleString('es-AR')` con «—»
  sin valor) pasa a `GP2N.fmt(n, d, '—')`. Regla 4 nueva en `test_numero.js`: donde está cargado
  `gp2-numero.js` no hay formateador propio de números (`tandas-popup.js` permitido mientras lo
  carguen pantallas viejas sin la regla, pregunta 2).
- Índice `produccion_legajo_fecha_idx` (A4 6.2): `registro_operarios_bundle` suma la producción
  por legajo y fecha para cada rollo abierto; la tabla nace vacía y crece con la app.
- **Conservación del inventario re-verificada** tras todos los cambios del día: ledger
  (`_delta_orig`/`_delta_dest` agregados por componente y ubicación) vs `inventario.cantidad`:
  **0 desvíos** en 1078 filas / 221 movimientos. Los 32 negativos son los de la pregunta 8.
- Mirada la idea 7257 (`v_contraparte_parte`): la vista sirve para 3 de las 5 copias; las otras
  dos son "pares" (sc→sp, dos PS consecutivos). Queda como idea con esa precisión.

### Estado tras el ciclo 2i
**47 tablas · 12 vistas · 120 funciones · 36 tests.**

---

## Ciclo 2j — primera tanda de `fmt` a `GP2N.fmt` (idea 7256), 22:56–23:01 AR

Ocho pantallas sin campos numéricos (para que enganchar `gp2-numero.js` no cambie ningún
input): Inyectores, Recepciones, Valorización, Faltante Partes Tallerista, Faltantes,
Entrevistas, Monitor y Tiempos. Cada `fmt`/`n0`/`n2`/`fmtNum` propio pasa a
`GP2N.fmt(n, decimales, sinValor)` conservando su default (0 ó 2 decimales, «—» o «0» sin
valor). `test_numero.js` regla 4 (sin `toLocaleString` propio donde está la regla) y regla 3
(sin parses crudos) en verde; `test_smoke_gp2.js` 47/47. Quedan (IDEAS 7256): las pantallas con
campos numéricos y las dos con decimales fijos.

### Estado tras el ciclo 2j
**47 tablas · 12 vistas · 120 funciones · 36 tests.**

---

## Ciclo 2k — segunda tanda de la regla de número: las pantallas con campos, 23:01–23:07 AR

- Los patrones de `test_numero.js` ahora ven también `Number($('x').value)`, `$R(...)` y
  `parseFloat(String(...).replace(',','.'))` con paréntesis anidados. Con eso aparecieron
  **cuatro parsers propios más** que la primera pasada no vio: Flejes (`Number(...)` en el modal y
  `parseFloat(...replace(',','.'))` en el ajuste de rollos), Devolución (`parseFloat(replace(',','.'))`),
  Envíos AT (`parseInt(replace(/\D/g,''))`), Control AT (`n(v)` con `replace(',','.')`) y
  Stock General (`parseFloat(val('f_qty'))`). Todos → `GP2N.num` / `GP2N.entero`, y esas
  pantallas cargan `gp2-numero.js` (con lo que sus campos ganan el separador de miles).
- Problemas con Matrices: el campo «Matriz» es un código (`101B`), no una cantidad:
  `data-miles="no"` para que el separador no lo toque.
- `GP2N.fmt(n, dec, sinValor, fijo)`: cuarto parámetro para decimales **fijos** («1,50»),
  que necesitaban Control AT y Cierres del Día (`monitor2`) y era la razón de sus `fmt` propios.
  Token `gp2-numero.js 20260905m` en las 32 páginas que lo cargan.
- **Recepción Insumos queda fuera a propósito** (idea 7259): su `parseNum` sigue OTRA regla
  («12.5» = 12,5) y sus sanitizadores pelean con el separador automático; es la pantalla de
  carga más usada y se migra con el operario al lado. `test_numero.js` la lista como permitida
  con ese motivo, así no se pierde.
- 18 pantallas sin formateador ni parser propio; smoke 47/47.

### Estado tras el ciclo 2k
**47 tablas · 12 vistas · 120 funciones · 36 tests.**

---

## Ciclo 2l — un botón roto desde el 31/08 y el respaldo `db/`, 23:07–23:16 AR

- **Bug vivo**: «Desmarcar» (deshacer el control de una recepción) en `control-cajas.js` y
  `control-remaches.js` hacía `UPDATE` directo sobre `recepcion_insumo` y `movimiento` desde el
  navegador. Desde el 2026-08-31 `anon` no tiene UPDATE en ninguna tabla GP2 → el botón fallaba
  con "permission denied" (y el `update` de `movimiento` ni siquiera chequeaba el error). Se
  encontró buscando `from('movimiento')` en el código para actualizar `GP2_MAPA.md`.
  **Arreglo**: RPC `descontrolar_recepcion(p_recepcion_id)` (SECURITY DEFINER, simétrica de
  `controlar_recepcion_cajas/_kg`: vuelve la cantidad al declarado, borra el desglose y ajusta el
  movimiento; idempotente). Probada con rollback sobre la recepción 418. Tokens
  `control-cajas.js 1.1.1`, `control-remaches.js 1.5.1`.
- `GP2_MAPA.md`: la sección "Escritura" decía que se insertaba en `movimiento` directo y que
  `registrar_movimientos` estaba sin usar; hoy es al revés y quedó escrito.
- **`db/` regenerado** (47 tablas · 120 funciones md5 120/120 · 12 vistas) con `db/regenerar.sql`
  para la próxima vez; `db/README.md` reescrito (qué se fue, grants vigentes, orden de restauración).
- ABM Artículos y Programa pasan a `GP2N` (parses y `fmt`; el campo «Código» del ABM con
  `data-miles="no"` porque es un código, no una cantidad; Programa muestra decimales según
  magnitud pero en es-AR).

### Estado tras el ciclo 2l
**47 tablas · 12 vistas · 121 funciones · 36 tests.**

---

## Ciclo 2m — barrido de escrituras directas y de RPC fantasma, 23:16–23:20 AR

Después del botón roto del ciclo 2l se buscó **todo** `.from('tabla').insert/update/delete`
en las 62 pantallas/JS GP2: quedaba **uno** más, en Recepción Insumos (`update cantidad_declarada`
tras cargar, con `try/catch` que se tragaba el "permission denied"). Era redundante: la RPC de
control guarda la declarada la primera vez. Fuera. **Guardia nueva** (`test_helpers_ui.js` regla
5): ninguna pantalla GP2 escribe una tabla directo; probada con una página trampa.
También se verificó que los 10 nombres que las pantallas leen con `.from()` (`componente`,
`produccion`, `inventario`, `empleado`, `sector`, `v_recepcion_unificada`, `recepcion_insumo`,
`proveedor_servicio`, `movimiento`, `familia`) existen, y que las RPC que las pantallas nombran
existen todas en la base: las 97 RPC que nombran las pantallas existen y tienen EXECUTE para
`anon`; la única RPC con EXECUTE que ninguna pantalla llama es `crear_entrega_tallerista` — y
eso destapó que **la entrega del tallerista está implementada dos veces** (motor JS vs RPC, con
distinta forma en el ledger). No se borró ninguna: es la pregunta 26 / idea 7260.

### Estado tras el ciclo 2m
**47 tablas · 12 vistas · 121 funciones · 36 tests.**

---

## Ciclo 2n — contratos pantalla ↔ base y espejos, 23:20–23:27 AR (solo lectura)

| Chequeo | Resultado |
|---|---|
| Nombres de RPC que llaman las 62 pantallas/JS GP2 (97) existen en la base y tienen EXECUTE para `anon` | **97/97** |
| Claves `p_*` que las pantallas mandan en cada `rpc('x', {...})` vs la firma real de la función (61 llamadas con argumentos) | **0 claves inexistentes** |
| Nombres que las pantallas leen con `.from('...')` (10) existen como tabla o vista | **10/10** |
| `href` locales de las 50 páginas de entrada GP2 (menú, tablet, login, `*_GP2`) apuntan a archivos que existen | **0 rotos** |
| Escrituras directas a tablas desde pantallas | **0** (guardia en `test_helpers_ui.js`) |
| Ledger vs inventario | **0 desvíos** (1078 filas, 221 movimientos) |
| `GP2.est_madre` vs `public.proyeccion_madre` | 5 filas contables del origen (no son artículos) que el espejo omite a propósito; **36 con `proy_uni_mes` distinto porque el origen trae `uxb` vacío y su "uni" es en realidad cajas**: `fn_est_madre_sync` recalcula uni = cajas × `articulo.articulos_por_caja` (ej. 43: 4 cajas × 24 = 96). Es lo diseñado, no un desvío |
| `articulo` activos sin ruta / componentes de receta que ninguna ruta produce | 0 / 0 |
| `virgilio_espejo_pend` | 14 entregas de Virgilio sin aplicar (pregunta 8: 13 artículos que GP2 no conoce) |

De paso, las tres últimas copias de formateador fuera de la regla (Informes por matriz, Informes
por persona, Disruptivas — esta última con su `esc` propio y un "hoy" en UTC) pasan a
`GP2N`/`GP2UI`: **no queda ningún parser ni formateador de números propio en las pantallas GP2**,
salvo Recepción Insumos (7259, a propósito).

### Estado tras el ciclo 2n
**47 tablas · 12 vistas · 121 funciones · 36 tests.**

---

## Ciclo 2o — circuito completo con rollback (VALIDÁ), 23:27–23:33 AR

Un solo `DO` que termina en `OK_ROLLBACK` recorre las RPC reescritas hoy, en el orden real de la
planta, y verifica cada delta de `inventario`:

| Paso | RPC | Delta verificado |
|---|---|---|
| OC a Pettofrezza por 5 PA4 + recepción de 3 | `crear_oc`, `crear_recepcion_insumo` | Plástico +3; `orden_compra_item.recibido` = 3 (cruce FIFO) |
| Envío de 100 A1 a FAAT | `crear_envio_ps` | Procesado −100, PS FAAT +100 |
| Entrega de 1 kg de IA2 hecha con A1 | `crear_entrega_ps` | PS FAAT −25,19 A1 (1 kg ÷ 0,0397 kg/uni), Fleje +1 kg IA2 |
| Envío de 50 Z23 a Danica Garcia | `crear_envio_tallerista` | Procesado −50, tallerista +50 |
| Entrega de 20 + consumo de 5 (forma del motor JS) | `registrar_movimientos` | tallerista −25, Procesado +20 |
| Devolución de 5 a Para Analizar | `crear_devolucion_tallerista` | tallerista −5, Analizar +5 |
| Lo que ve Control Talleristas | `talleristas_bundle` | enviado 50 · entregado 25 · devuelto 5 · saldo 20 |

Integridad referencial de datos (solo lectura): 0 pasos de ruta sin actor o sin entrada, 0
recetas/BOM con cantidad inválida, 0 movimientos sin ubicación, 0 ubicaciones de sector
huérfanas, 0 talleristas inactivos con stock. Lo que queda es de negocio y ya está en la
pregunta 8 (PEP3/PA10 en Plástico, IE3/IC2 sin `kg_x_uni`, 574/119/615/809 discontinuados con
demanda, 9 componentes discontinuados que siguen en rutas: A1C1, A9, BOM10, C12, GRJ13, I3B,
IZ19A, L4B1, V20).

### Estado tras el ciclo 2o
**47 tablas · 12 vistas · 121 funciones · 36 tests.**

---

## Ciclo 2p — `v_contraparte_parte` (idea 7257), 23:33–23:35 AR

"Qué parte entra y sale por cada contraparte" se derivaba de `ruta_paso` en tres funciones con
tres textos distintos: `control_ps_bundle.cfg`, `partes_por_ps` (dos subconsultas correlacionadas)
y `talleristas_bundle.cfg` (un `union` de entrada/salida). Ahora es la vista
**`v_contraparte_parte(tipo, ref_id, comp_id, lado)`** (662 filas) y las tres la leen. Verificación:
md5 de la salida de las tres funciones (sin `generado_en`) **idéntico antes y después**
(`10426b61…`, `06d74310…`, `21ac3190…`). Los "pares" (`envios_ps_bundle`: sc→sp del mismo paso;
`stock_transito_ps_bundle`: dos PS consecutivos) son otro concepto y quedan como están.
Migración `refactor_20260905_v_contraparte_parte`.

### Estado tras el ciclo 2p
**47 tablas · 13 vistas · 121 funciones · 36 tests.**

---

## Ciclo 2q — `cargar_compra_mp` (idea 7251, primer paso), 23:35–23:43 AR

`cargar_compra_altrak` y `cargar_compra_aperam_chapa` eran la misma función con tres constantes
adentro (qué componente bruto, qué PS híbrido lo recibe, qué proveedor lo vende) y el reparto
corto/largo sólo en una. Ahora: **`proveedor_servicio.mp_componente_id`** (Charcas → FLEJE90_BRUTO,
Eclipse → CHAPA430; quién lo vende ya estaba en `componente.proveedor`) y **una** RPC
`cargar_compra_mp(p_proveedor, p_kg, p_remito, p_fecha, p_pct_corto)` que resuelve el PS por
datos. Un tercer proveedor de materia prima es una fila, no una función.
Verificación con rollback: vieja vs nueva, para Altrak (con 70/30) y Aperam: misma recepción
(proveedor, kg, `rollos_json`), misma ubicación destino, mismos deltas de inventario, misma
respuesta de reparto; proveedor sin PS híbrido rechazado. Las dos viejas se borraron; Recepción
Insumos llama la genérica (dos líneas, `stock_kg` en vez de `stock_charcas_kg`/`stock_eclipse_kg`).

### Estado tras el ciclo 2q
**47 tablas · 13 vistas · 120 funciones · 36 tests.**

---

## Ciclo 2r — `db/` al día y los literales de `control_ps_bundle`, 23:43–23:52 AR

- `db/funciones_GP2.sql` regenerado con `db/regenerar.sql` (120 funciones, **md5 120/120 contra la
  base**, 0 distintas, 0 sólo en la base); `db/README.md` con los números reales (120 funciones =
  97 RPC de pantalla + 23 internas).
- Los últimos literales de negocio en SQL que quedaban de la auditoría A4 (`control_ps_bundle`:
  `ps_id=1` con `IC3`/`IC3V`, `ps_id=13` con `1686`) se evaluaron contra `v_contraparte_parte`:
  la salida de Charcas sí sale de la vista, **Eclipse no tiene pasos en `ruta_paso`** (su producto
  1686 no se deriva de ninguna ruta). Reemplazar uno solo dejaría dos mecanismos para lo mismo,
  peor que el literal. Se deja, anotado en la idea 7258: el día que Eclipse tenga ruta, salen juntos.

### Estado tras el ciclo 2r
**47 tablas · 13 vistas · 120 funciones · 36 tests.**

---

## Ciclo 2s — otros ángulos: grants, columnas muertas, contrapartes sin ubicación, invariantes, 23:52–00:07 AR

Barrido desde ángulos que no se habían mirado. Hallazgos y qué se hizo:

- **Secuencias con USAGE para `anon`/`authenticated`** (4: `movimiento`, `entrega_prov_at`,
  `articulo_prov_at`, `uni_x_articulo_x_caja`; resto de cuando esas tablas aceptaban INSERT directo).
  Ninguna función no-DEFINER escribe, así que el grant no servía: revocado.
- **`cargar_compra_mp` con `SELECT INTO` no estricto**: si dos PS híbridos recibieran materia prima
  del mismo proveedor, tomaba uno cualquiera en silencio. Ahora `INTO STRICT` con dos errores
  claros (sin PS / ambiguo). Probado con rollback: camino normal igual, proveedor inexistente
  rechazado, ambigüedad simulada detectada.
- **BUG VIVO nº 8 — contrapartes sin ubicación**: los PS 9 «Rec Color», 10 «Daniel» y 14 «Esther»
  y el Prov AT 13 «Tierra Nativa SA» no tenían fila en `ubicacion`: `crear_envio_ps` /
  `crear_envio_prov_at` explotaban con "No hay ubicación para…" (el mismo bug de AJ Adhesivos,
  A2-06). **Causa raíz**: `alta_proveedor_servicio` (botón "nuevo pintor" de Pintores) daba de
  alta el PS sin su ubicación. Se crearon las 4 que faltaban (ubicaciones 51–54, misma convención
  de nombre) y la RPC crea la ubicación en la misma transacción (devuelve `ubicacion_id`).
  Verificado con rollback. Sectores 12 «Terminado» y 13 «Alambre» siguen sin ubicación a
  propósito: Terminado vive en Virgilio (`ubic_de_componente` cae ahí) y el 13 es la pregunta 21
  (se le agregó el dato).
- **Columnas que no lee nadie** (374 columnas × funciones + vistas + pantallas): una sola,
  `inventario.cajones_x_ubicacion` (154 valores del Excel viejo) → agregada a la pregunta 5, no se
  borra sin respuesta. Las otras 6 "sólo pantallas" (`sector.oc_pide/oc_rubro_id`, `uni_x_articulo_x_caja.*`,
  `precio_tallerista.concepto`, `proveedor_at.notas`) sí se leen desde `from()` o son texto libre.
- **JS huérfanos**: 0 (59 archivos, todos referenciados). **Nombres de función repetidos entre
  archivos JS**: 201, casi todos en pantallas del programa viejo (pregunta 1) o pares
  `x.js`/`x_GP2.js` deliberados; en GP2 sólo quedaba `cls` en Disruptivas → `GP2UI.cls` (token 20260905q).
- **Advisor de seguridad**: 697 hallazgos en el proyecto, **0 en GP2** (todos en `public`,
  `planify`, etc. — la casa del vecino). **`pg_stat_statements`**: ningún bundle GP2 pasa de 310 ms
  promedio (`despiece_verif_bundle` 303, `oc_bundle` 134, `recepcion_bundle` 81 con un pico de 2,7 s
  en 323 llamadas). Sin acción.
- **Extensiones/tipos**: sin tipos ni secuencias huérfanos en GP2.
- **`db/verificar.sql`** (nuevo): 14 invariantes en una consulta (contrapartes con ubicación,
  inventario = ledger, funciones internas sin EXECUTE, RLS + policies sólo SELECT, secuencias y
  tablas sin escritura anónima, PS híbrido con MP y sin ambigüedad, código único por sector,
  movimientos con ubicación, inventario sin pares repetidos, rutas con pasos, RPC de pantalla con
  EXECUTE). Hoy: 14/14 en 0. Cada regla es un bug que ya pasó.

### Estado tras el ciclo 2s
**47 tablas · 13 vistas · 120 funciones · 36 tests · 14 invariantes en 0.** (`db/funciones_GP2.sql`
se regenera al cierre: cambiaron `cargar_compra_mp` y `alta_proveedor_servicio`.)

---

## Ciclo 2t — código muerto fino, vocabulario, páginas huérfanas, CSS, 00:07–00:13 AR

- **Funciones JS sin ningún llamador** en las 42 pantallas GP2 + 18 JS compartidos: 3, todas en
  Recepción Insumos (`provPideRollos`, `provControlaPeso`, `pendCount`) → borradas. En los JS
  compartidos, 0.
- **Vocabulario `tipo_mov`**: las 16 palabras del CHECK están vivas (13 en RPC, `stock_inicial` en
  datos, `armado_fabrica` / `consumo_prod` las emite el motor JS de Stocks General). El trigger
  `fn_movimiento_calc` no ramifica por tipo: el tipo es semántico, el delta sale de las unidades.
  Anotado como decisión 6.
- **Páginas GP2 sin ningún link** que las alcance: 0 de 42 (todas llegan desde `GP2_MODULOS.html`
  u otra pantalla).
- **Contrato de claves bundle → pantalla** (qué claves lee cada pantalla vs qué devuelve el
  bundle): la heurística por nombre de variable es demasiado ruidosa (DOM y filas anidadas se
  confunden con claves) — no sirve como guardia automática; el contrato queda en el índice de
  `GP2_MAPA.md` y en `test_smoke_gp2.js`.
- **CSS**: 145 KB de CSS inline en 42 pantallas (1.578 reglas). Sólo 30 son idénticas a
  `gp2-modulo.css` y sólo 9 se repiten en ≥5 pantallas sin estar en el compartido (2,8 KB): las
  pantallas están estilizadas una por una, no hay una capa común que extraer. Sin acción (mover
  CSS es riesgo visual por cero valor medible).
- Decisiones 7 (no renombrar RPC/parámetros) y 8 (toda contraparte nace con ubicación).

### Estado tras el ciclo 2t
**47 tablas · 13 vistas · 120 funciones · 36 tests · 14 invariantes en 0.**

---

## Ciclo 2u — VALIDAR: las 97 RPC corridas de verdad (con rollback), 00:13–00:24 AR

Después de tocar 30+ funciones en el día, la única prueba que vale es correrlas. Todo dentro de
bloques `DO` que terminan en `raise exception 'OK_ROLLBACK …'` (nada queda escrito) y que
verifican los deltas de inventario, no sólo que "no explote":

- **Bundles de lectura**: los 37 `*_bundle` + `partes_por_ps`, `charcas_pendiente`,
  `composicion_stock`, `consumo_detalle` → 45 llamadas, 0 errores.
- **Producción**: `registrar_evento_prod` (mueve stock 0→10 en la pieza de la matriz, detecta
  el `id_ejecucion` duplicado), `anular_evento_prod` (eliminar='S'), `registrar_produccion`,
  `anular_produccion`, `marcar_revisado`.
- **Relevamiento completo**: abrir → guardar (2 envases + 3 sueltas = 503 uni) → comparar →
  cerrar (estado `contado`) → decidir `conteo` → aplicar: el stock pasa de 100 a 503 con 1
  ajuste; `descartar_si_vacio` y `eliminar` también.
- **Recepción de insumos**: `cargar_recepcion` (caja, cartón y fleje con rollos/pallets),
  `controlar_recepcion_cajas` (4 base × 2 pisos + 3 sueltas = 203 contra 200 declaradas),
  `controlar_recepcion_kg`, `pesar_pallet` (2 rollos × 125 kg, balanza 262,5 → "sobrante
  alto"), `descontrolar_recepcion` (vuelve a la declarada), `anular_recepcion` (1 recepción, 1
  movimiento), `guardar_control_cartones` (48 paquetes × 250).
- **PS híbridos**: `cargar_compra_mp` (ya en 2q/2s), `cargar_recepcion_charcas` y
  `cargar_recepcion_eclipse` (consumen la MP del PS).
- **Prov AT**: `crear_envio_prov_at` (sector 11 −7 / prov +7 exactos) y `crear_entrega_prov_at`.
- **Talleristas**: el circuito de 2o (envío/entrega/devolución) más `crear_entrega_tallerista`,
  la RPC que hoy no llama nadie (pregunta 26): funciona (Danica Garcia → Virgilio, 4 uni).
- **Rollos**: `tomar_rollo` → `cerrar_rollo` → `ajustar_rollos`.
- **ABM y maestros**: `abm_articulo_upsert` (alta) → `abm_bom_guardar` (con su aviso de ruta) →
  `abm_articulo_baja`; `empleado_guardar`, `empleado_activar`; `alta_proveedor_insumo`,
  `alta_proveedor_servicio`, `fleje_detalle_upsert`, `asignar_pintor_parte/activo`,
  `asignar_proveedor_parte`, `marcar_estado_compra`; `marcar_faltante` → `resolver_faltante`;
  `ruta_reportar` → `ruta_resolver`, `ruta_confirmar`; `registrar_movimientos` con una fila
  armada como la arma `gp2-motor.js` (ajuste +5 exacto).

**Resultado: 0 errores en las ~60 RPC de escritura y 45 de lectura.** Ningún bug nuevo; los
que había (ubicaciones, Desmarcar, unidades) ya estaban arreglados.

**Dato que salió de paso** (a `PREGUNTAS` como **27**): 80 renglones de inventario con
`minimo > maximo` (30 Procesado, 30 Crudo, 10 Bombilla…): dos reglas de reposición que nadie
cruzó — el renglón queda "bajo mínimo" para siempre y la OC nunca lo saca de ahí. Es de negocio;
cuando se responda, entra como invariante en `db/verificar.sql`.

### Estado tras el ciclo 2u
**47 tablas · 13 vistas · 120 funciones · 36 tests · 14 invariantes en 0 · 105 RPC probadas en vivo.**

---

## Ciclo 2v — mapa de la casa: triggers, cron, puntos de contacto con `public`, nomenclatura, 00:24–00:32 AR

- **`GP2_MAPA.md`**: sección nueva con los **9 triggers propios + 2 espejos sobre `public`** (qué
  tabla, qué función, qué hace) y el único cron de GP2 (`gp2-dolar-oficial`, entre 49 jobs del
  proyecto); y la lista cerrada de **puntos de contacto con la casa del vecino**: dos triggers
  espejo (`public` → GP2), `virgilio_espejo_pend.entrega_id`, `get_role_for_email` (delega en
  `public`) y `actualizar_dolar_oficial` (extensión `http`). Ninguna función, vista ni pantalla
  GP2 lee tablas de `public`. La sección "Pendiente de verificación" del mapa (3 puntos de agosto)
  quedó resuelta y dice dónde está cada verificación.
- **Nomenclatura** (374 columnas): `componente_id` ×13 vs `comp_id` ×1 (`movimiento`, más
  `comp_entrada_id`/`comp_salida_id` en `ruta_paso`); `creado_en` ×9 vs `created_at` ×1 vs
  `fecha` ×8; `codigo` ×2 vs `cod` ×2 vs `cod_art` ×3; `nota` ×7 vs `notas` ×1. Consistente en lo
  grueso; los pocos desvíos quedan (decisión 4: no se renombra por prolijidad). 33 tablas
  maestras sin columna de creación — no hace falta: son maestros, no eventos.
- **Advisor de performance** (re-corrido tras los cambios del día): 19 INFO en GP2 — 14 FKs sin
  índice (tablas de 12 a 600 filas) y 5 índices "sin uso" (dos son de hoy y todavía no los
  consultó nadie). Tabla más grande: `ruta_paso`, 2.595 filas / 792 kB. Decisión sostenida: no
  se indexa por indexar.
- **Comentarios en la base**: 43 de las 47 tablas no tenían `comment on table`. Ahora las 47 lo
  tienen (qué es, quién la escribe, con qué se cruza) — visible en el panel de Supabase y en
  `db/tablas_GP2.sql`. Cero cambio de comportamiento.
- `db/tablas_GP2.sql` y `db/funciones_GP2.sql` regenerados (md5 exacto).

### Estado tras el ciclo 2v
**47 tablas · 13 vistas · 120 funciones · 36 tests · 14 invariantes en 0.**

---

## Ciclo 2w — seguridad fina: `search_path` sólo GP2, y una entrega de Virgilio perdida, 00:32–00:40 AR

- **`search_path`**: 46 funciones tenían `"GP2", public`. Cualquier nombre no calificado que no
  existiera en GP2 se resolvía en la casa del vecino (una tabla homónima, una función
  sobrecargada). Ninguna usa objetos de `public` sin calificar: se probó **dentro de una
  transacción** (`ALTER FUNCTION … search_path = GP2` para las 46 + 64 llamadas: bundles, ledger,
  relevamiento, producción, recepción, envíos, ABM, rutas → 0 errores → rollback) y después se
  aplicó de verdad. Quedan con `public` sólo `get_role_for_email` (delega en `public`) y
  `actualizar_dolar_oficial` (extensión `http`).
- **BUG VIVO nº 9 — una entrega de Virgilio que el espejo perdió**: `virgilio_espejo_pend`
  tenía 14 filas; 13 son "artículo sin equivalente en GP2" (datos: códigos 535, 584E, 590E,
  590ES, 760, 207, 599, 727E, 877E, 943, 948, 817, 823 — pregunta 8), pero **una era un error**:
  la entrega 2308 (Carlos, 160 cajas del 510, remito 37996, 04/09 08:44) falló con "El origen
  tallerista 9 no tiene ubicación" — Carlos Aguirre todavía no tenía `ubicacion_stock_id` esa
  mañana — y **nadie la reintenta** (el espejo no tiene cola de reproceso). Se reprodujo con
  `dry_run` (1.920 uni = 160 × 12; consume las 4 partes de la receta en Pedernera/Carlos y
  recibe 1.920 del 510 terminado en Virgilio) y se aplicó con la fecha original; la fila
  pendiente se borró. Dos invariantes nuevos en `db/verificar.sql`: **N** (ninguna función con
  `public` en el `search_path`) y **O** (ningún `error:` en el espejo de Virgilio).

### Estado tras el ciclo 2w
**47 tablas · 13 vistas · 120 funciones · 36 tests · 16 invariantes en 0.**

---

## Ciclo 2x — errores silenciosos y datos raros, 00:40–00:45 AR

- **RPC sin manejo de error** en las 42 pantallas + JS compartidos: 102 llamadas `rpc(`; la
  heurística marcó 6 sin `error`/`catch` a ±5 líneas y las 6 son falsos positivos (el chequeo
  está 6–8 líneas más abajo, o lo hace `E.guardarItems` de `gp2-envios-common.js`, o un
  `try/catch` envolvente). **0 llamadas silenciosas** (la única que había, Recepción Insumos, se
  sacó en 2m).
- **Datos**: 0 renglones de stock en talleristas inactivos; 0 artículos sin `articulos_por_caja`
  (el espejo de Virgilio los necesita); 0 movimientos con fecha fuera de rango. **37 renglones
  con stock negativo**, casi todos en ubicaciones de talleristas (IJUPA −1.896, Pettofrezza
  −2.400, Pedernera/Carlos −1.920 ×4 — estos últimos son la entrega repuesta en 2w): es el hueco
  del **stock inicial** (las piezas se consumieron en Virgilio antes de que GP2 tuviera cargado lo
  que cada tallerista tenía), ya en la pregunta 8. No es un bug del motor: el ledger cierra.
- Idea **7261** (cola de reintento del espejo de Virgilio) registrada.

### Estado tras el ciclo 2x
**47 tablas · 13 vistas · 120 funciones · 36 tests · 16 invariantes en 0.**

---

## Ciclo 2y — `control_recepcion_bundle` (idea 7255, mitad SQL), 00:45–00:51 AR

`control_cajas_bundle()` y `control_kg_bundle(p_sector_id)` eran **la misma consulta** sobre
`recepcion_insumo` (una con el sector 11 fijo y las columnas del control por cajas, la otra con
las del pesaje) y la primera tenía el "25" de unidades por paquete escrito adentro, mientras
`parametro.caja_uni_x_paquete` dice lo mismo. Ahora **una** RPC `control_recepcion_bundle(p_sector_id)`
con la unión de columnas y el 25 leído del parámetro; `control-cajas.js` la llama con 11 y
`control-remaches.js` con su sector. Verificación: md5 de las recepciones (proyectadas a las
columnas de cada bundle viejo) idéntico para el 11 y el 5, mismo `uni_x_paq_default`, mismo
nombre de sector; suite con los stubs actualizados. Las dos viejas se borraron. Queda para la
idea 7255 la mitad de pantalla (dos HTML al 74 % iguales → uno con `?modo=`), que es riesgo
visual y se hace con el operario al lado.

### Estado tras el ciclo 2y
**47 tablas · 13 vistas · 119 funciones · 36 tests · 16 invariantes en 0.**

---

## Ciclo 2z — segunda opinión: dos agentes sobre costos y sobre las preguntas, 00:51–01:04 AR

Se lanzaron dos agentes de sólo lectura: **`gp2-auditor-costos`** (¿el refactor contaminó algún
número de plata?) y **`gp2-experto`** (¿las recomendaciones de las preguntas 21–27 cierran con
lo que el usuario ya decidió?). Lo que salió y qué se hizo:

- **Costos — sano en lo grueso**: `valorizacion_bundle` byte-idéntica al 31/08; borrar
  `precio_servicio` no movió un peso (md5 de las 591 filas de `v_costo_componente` ya verificado);
  `recalcular_maximos_insumos` → `v_nivel_stock` es la misma cuenta; el motor de inventario sólo
  cambió `search_path`; las tarifas no pueden duplicar (UNIQUE). Hallazgos y acción:
  1. **"Sector de insumo" tenía dos definiciones**: `sector.es_insumo` (OC, máximos) y dos arrays
     escritos a mano dentro de `v_costo_componente` sin el 9 Garage. Se probó en transacción
     (591 filas, **0 cambios** de costo hoy) y se aplicó: la vista lee `es_insumo`. Una fuente.
  2. `oc_bundle` toma el máximo de una ubicación ajena cuando la pieza no tiene fila en la de su
     sector: hoy pasa con 2 (`PEP3`, `PA10`, Procesado con stock en Plástico) → anotado en la
     pregunta 8, ítem 2 (ya preguntaba por esas dos); no se toca la regla.
  3. `recalcular_minimos` **sí pisa** las 697 filas con `minimo_origen` null cuando hay consumo
     (el comentario de la columna decía lo contrario): comentario corregido en la base, dato en
     `CONOCIMIENTO` y en la pregunta 25 (si A, agregar la guarda de `'fisico'`).
  4. `precio_tallerista.precio_uni` es un costo congelado (trigger al insertar; si cambia el
     peso no se mueve): hoy 0 filas desfasadas → idea **7262**.
  5. `fleje_detalle.kg_x_uni` borrada: los 3 flejes sin peso (`IF12`, `IE3`, `IC2`) tampoco lo
     tenían ahí (ya estaban en la pregunta 8, ítem 10): no se perdió ningún dato.
  6. **Doc desviada**: el sugerido de la OC es `maximo − stock` (sin `pendiente_oc` desde el
     04/09, "por ahora borralo") y `CLAUDE.md`, `OC_GP2.html` y `Valorizacion_GP2.html` decían
     otra cosa (y nombraban `v_valor_stock`/`v_valor_pedido`, que no existen) → corregidos.
- **Preguntas — una estaba mal planteada**: la **27** proponía topar el mínimo al máximo, que es
  exactamente lo que el usuario **descartó** el 02/09 ("es la planta, topearla sería tapar la
  señal", §2e-bis). Reescrita: las 80 filas son tres cosas (56 legítimas de 5 cajones; 10 de
  Bombilla por `meses_minimo 4 > meses_stock 3` — y Crudo/Procesado tienen 2 > 1 —; 14 sueltas), y
  el invariante correcto es "ninguna ubicación con `meses_minimo > meses_stock`" (hoy 3,
  pendiente en `db/verificar.sql`). La **21** gana la alternativa C (mover `FLEJE90_BRUTO` al
  sector 5 como ya se hizo con `CHAPA430`; B contradice al usuario, A no cambia nada porque el
  bruto no tiene consumo propio). La 25 y la 22/26 cierran (se anotaron las condiciones). Se
  corrigió `CONOCIMIENTO` (CHAPA430 es sector 5 desde el 04/09, no 13) y se agregaron 5 `[dato]`.
- `db/vistas_GP2.sql` regenerado; `version.js` **v1.109.1** (token `20260905r`).

### Estado tras el ciclo 2z
**47 tablas · 13 vistas · 119 funciones · 36 tests · 16 invariantes en 0 · 27 preguntas (la 8 con 22 datos).**

---

## Ciclo 3 — cierre: el contrato pantalla ↔ base como test, 01:04–01:31 AR

Lo que hoy se chequeó a mano cuatro veces (¿existe la RPC que nombra la pantalla?, ¿la tabla del
`from()`?, ¿las claves `p_*` son parámetros reales?) queda como guardia automática:
**`tests/ui/test_contratos_db.js`** lee `db/funciones_GP2.sql`, `db/tablas_GP2.sql` y
`db/vistas_GP2.sql` y recorre las 42 pantallas + 3 páginas de entrada + los 18 JS que cargan:
98 `rpc()` y 26 `from()` existen, y en las 60 llamadas con objeto literal las claves son
parámetros de verdad (probado: un `p_kgs` a propósito lo atrapa en dos líneas). Si falla porque
`db/` está viejo, la respuesta es regenerar `db/` — así el respaldo deja de ser opcional. Suite:
**37/37**. Últimas verificaciones antes de cerrar: 16 invariantes en 0, 46 lecturas ok, advisor
de seguridad 0 en GP2, md5 de `db/` exacto contra la base.

## Ciclo 4 — re-validación tras el segundo corte, 06:40–06:50 AR

La cuenta volvió a quedarse sin uso a la 01:32 AR; al retomar (06:40 AR): `main` no se movió
(nadie pusheó, el agente diario de las 06:00 no dejó commits), la base sigue en 47 / 13 / 119,
**19 invariantes en 0**, y el circuito de escritura completo corrió otra vez en rollback
después de los cambios de `search_path` y de `v_costo_componente`: ledger (ajuste +5 exacto),
relevamiento entero, producción (evento + anulación + registro), recepción (carga, control por
cajas, descontrol, anulación), compra de MP, envíos/entregas/devolución a PS, tallerista y Prov AT,
ABM, alta de PS, empleado, faltantes, rutas → **27 escrituras, 0 errores**. Suite 37/37. Último
barrido de datos por duplicación conceptual (misma descripción en el mismo sector, proveedores
con nombres parecidos, contrapartes repetidas entre tallerista / PS / Prov AT, artículos con la
misma descripción): lo que salió está en la pregunta 8 (ítem 16, las 3 personas que son
tallerista y Prov AT a la vez) o no es un duplicado.

## Ciclo 5 — idea 7262 y los precios que faltan, 06:50–06:55 AR

- **`v_costo_componente` ya no lee un costo congelado**: la tarifa del tallerista sale de
  `coalesce(precio_kg × componente.kg_x_uni, precio_uni)` (como ya hacía con
  `precio_servicio_pieza`), así que si mañana se corrige el peso de una pieza el costo se mueve
  solo. Probado en transacción antes de aplicar: las 591 filas idénticas (md5). Idea 7262 hecha.
- **Datos que faltan (a la pregunta 8)**: 12 insumos comprables sin ningún precio — entre ellos
  `CHAPA430`, la chapa de Eclipse, con lo que el 1686 se costea sin material — y 44 precios de
  `precio_proveedor` sin componente (resinas de Beta Plásticos y otros que GP2 no modela).

## Ciclo 6 — la guardia del contrato, completa, 06:55–07:00 AR

`test_contratos_db.js` gana la regla 4: en cada llamada `rpc('x', {…})` con objeto literal no
puede faltar ningún parámetro **sin DEFAULT** (el mismo "function not found" de PostgREST, al
revés), y cubre también `control-cajas` / `control-remaches` (GP2 sin sufijo): 70 llamadas con
objeto literal verificadas; probado en negativo (sacar `p_sector_id` lo atrapa). `EXPLAIN` de
`v_costo_componente`: 4 ms para las 591 filas, todo en memoria — la vista recursiva no es un
problema de performance.

## Ciclo 7 — columnas que leen las pantallas e invariantes de recetas y rutas, 07:00–07:05 AR

- `test_contratos_db.js` regla 5: cada columna que una pantalla pide con `from(tabla).select('a,b,…')`
  existe en la tabla según `db/tablas_GP2.sql` (maneja alias `x:col` y recursos embebidos
  `rel:fk(col)`; las vistas no declaran columnas y se saltean). Es exactamente la clase de
  regresión de las 11 columnas borradas hoy — que se chequearon a mano. Probado en negativo
  (`oc_pidee` lo atrapa). El test cubre ahora 111 llamadas `rpc()` en 68 archivos.
- `db/verificar.sql` gana 7 invariantes de estructura (S–Y): ningún terminado dentro de una receta,
  BOM sin ciclos directos ni indirectos, pasos de ruta sin orden repetido y con actor, cantidades
  de receta positivas, todo componente con sector. Todos en 0 → **26 invariantes**. Las 13 rutas
  sin artículo son rutas de intermedios (modelo válido): quedaron como consulta informativa.

## Ciclo 8 — vocabulario de unidades del ledger, 07:05–07:20 AR

- `movimiento.unidad_origen` / `unidad_destino` traían cinco palabras para dos dimensiones: `uni`
  ×159, `unidad` ×36, `kg` ×24, `pliego` ×2 y null (los 38 raros eran ajustes del 02/09 que pasaron
  `componente.unidad_medida` tal cual). `to_canonical` ya trataba todo lo que no fuera `kg` como
  `uni`, así que el stock era correcto — pero la palabra quedaba guardada como vino y cualquier
  consulta que filtrara por `unidad_origen = 'uni'` perdía filas.
- Migración `refactor_20260905_movimiento_unidad_vocabulario`: `fn_movimiento_calc` normaliza las
  dos columnas ANTES de calcular (`kg` / `uni` / null = "la del otro lado"), las 38 filas se tocaron
  (el BEFORE UPDATE normaliza, el AFTER UPDATE revierte y reaplica el mismo delta) y la tabla lo
  exige con `movimiento_unidad_origen_chk` / `_destino_chk` (140 constraints). Comentario en las
  dos columnas.
- Verificado en rollback antes de aplicar y en vivo después: inventario md5 idéntico (`0ec559b8`),
  conservación ledger ↔ inventario 0, `registrar_movimientos` con `unidad`/`Pliego` guarda
  `uni`/`uni`, un insert con `KG` guarda `kg`; `db/verificar.sql` 26 en 0. `db/` regenerado (md5
  119/119).
- Decisión: `componente.unidad_medida` sigue diciendo `unidad` y el ledger `uni` (decisión 4: no se
  renombra por prolijidad; el trigger traduce). Ninguna pantalla cambia: `gp2-motor.js` ya mandaba
  `uni` y el resto de las RPC también.

## Ciclo 9 — vocabularios cerrados en el resto de las tablas, y la OC de Charcas en kg, 07:20–07:33 AR

- Barrido de todas las columnas de texto con ≤ 8 valores distintos (una consulta con
  `query_to_xml` sobre `information_schema`): 30 columnas de tablas, 8 ya tenían CHECK. Para cada
  una se miró quién la escribe (funciones y pantallas) y quién la lee.
- Migración `refactor_20260905_vocabularios_cerrados`: 11 CHECK nuevos donde el único escritor es
  una función o una carga y alguna función compara con el literal — `ubicacion.tipo` (6 valores;
  `GP2_MAPA` decía cuatro), `ruta_paso.tipo_paso` (6), `inventario.maximo_origen` /
  `minimo_origen` (`recalcular_*` los comparan con `'fisico'`, `'est_madre'`…), `moneda` en las 4
  tablas de precios y en `orden_compra_item` (`v_costo_componente` y Valorización filtran por
  `'USD'`/`'ARS'`), `recepcion_insumo.unidad`, `uni_x_articulo_x_caja.empresa` (`CH`/`LK`). Todos
  pasan con los datos de hoy (probado en rollback antes de aplicar).
- **Bug vivo 10 (latente): la OC a Resortes Charcas.** La pantalla pide en PAQUETES de 10 kg y
  mandaba `unidad='paq'`; `crear_oc` guardaba `paq` tal cual y **sumaba los paquetes como si
  fueran kg** para la OC gemela a Altrak (3 paquetes → 3 kg de alambre en vez de 30), y
  `_aplicar_recepcion_a_oc` trataba `paq` como unidades al cruzar la recepción (kg de balanza ÷
  `kg_x_uni` contra una cantidad en paquetes). Todavía no había ninguna OC de Charcas (la única OC
  es la 1, Aperam, anulada), así que ningún dato quedó mal. Migración
  `refactor_20260905_oc_unidades_kg_uni`: el 10 pasa a `parametro.charcas_kg_x_paquete` (estaba
  hardcodeado en `OC_GP2.html`), `crear_oc` convierte `paq` → kg y `unidad` → `uni` al guardar (la
  OC queda en kg: la recepción cruza kg contra kg y la gemela suma kg de verdad), `oc_bundle` emite
  `paq` (la pantalla caía siempre al 250 de fallback aunque su comentario decía que llegaba del
  bundle) y `charcas_kg_x_paquete`, `OC_GP2.html` lee el parámetro, y `orden_compra_item.unidad`
  queda con CHECK `kg`/`uni`. Probado en rollback: 3 paq → item «30 kg», gemela Altrak 30,60 kg
  (×1,02), cruce de 12,5 kg aplicado directo; Eclipse 100 `unidad` → «100 uni», gemela Aperam
  1,76 kg; un `paq` insertado directo lo rechaza el CHECK.
- `crear_entrega_prov_at` escribía `tipo_entrega = 'entrega'`, una palabra que no existía en la
  columna (`factura` / `remito_factura`, dato del programa viejo que la pantalla nueva no
  pregunta): ahora deja null y la columna tiene CHECK.
- `tarifa_servicio.unidad` (6 filas, siempre `kg`) no la leía nadie — la tarifa ya dice su unidad
  con `precio_kg` / `precio_uni` —: columna borrada (12 columnas borradas en la auditoría).
- Se dejaron abiertas a propósito: `matriz.tipo` (A/B/D/P, clasificación del usuario),
  `empleado.tipo` (texto libre en el ABM y nadie lo lee), `proveedor_insumo.rubro` y
  `relevamiento_cronograma.tipo` (datos del usuario), `componente.marca` (las marcas salen de los
  datos: `test_marcas`) — aunque `LOEKE` ×73 y `LOKE` ×8 huelen a la misma marca (pregunta 8,
  ítem 23).

## Ciclo 10 — una sola regla de OC gemela (PS híbrido → proveedor de la materia prima), 07:33–07:43 AR

- `crear_oc` tenía dos ramas escritas a mano con el proveedor por nombre: «si es Resortes Charcas,
  OC gemela a Altrak por FLEJE90_BRUTO con `charcas_desperdicio_pct`» y «si es Eclipse, OC gemela
  a Aperam por CHAPA430 con `eclipse_desperdicio_pct`» — 60 líneas casi iguales, dos claves de
  `parametro` con el nombre del PS adentro, y un tercer PS híbrido habría pedido una rama más.
- Migración `refactor_20260905_oc_gemela_generica`: el desperdicio pasa a ser un atributo del PS
  (`proveedor_servicio.desperdicio_pct`: Charcas 2, Eclipse 28; las dos claves de `parametro` se
  borran y `cargar_recepcion_eclipse` lee la columna), y `crear_oc` tiene UNA regla: si el
  proveedor de la OC es un PS híbrido (`hibrido`, `mp_componente_id`), la gemela va al proveedor de
  esa MP (`componente.proveedor`) por kg de producto pedido × (1 + `desperdicio_pct`), con el rubro
  del proveedor de la MP (o el sector de la MP). Ningún proveedor ni componente por nombre en el
  código. Con las unidades ya normalizadas (ciclo 9) las dos fórmulas viejas eran la misma: kg en
  kg, uni × `kg_x_uni`.
- La respuesta pasa de `oc_gemela_altrak` / `oc_gemela_aperam` a un `oc_gemela` genérico
  (`proveedor`, `componente`, `kg`) y `OC_GP2.html` arma el mensaje con eso.
- Probado en rollback con los mismos números que las ramas viejas: Charcas 3 paq → Altrak 30,60 kg
  (rubro Sector Alambre), Eclipse 100 uni → Aperam 1,76 kg, una OC a Altrak (no híbrido) → sin
  gemela, recepción de Eclipse con el 28 % del PS (1,761 kg de chapa). Suite 37/37.

## Ciclo 11 — validación final: docs desviadas por los renombres de hoy, advisors, circuito de escritura, 07:43–07:50 AR

- Barrido de los nombres que cambiaron hoy (`oc_gemela_altrak`, `*_desperdicio_pct`,
  `tarifa_servicio.unidad`, `control_cajas_bundle`, `v_valor_stock`, `tallerista_alias`…) en
  docs, pantallas y agentes: 4 docs vivos los seguían usando como si existieran —
  `CONOCIMIENTO_GP2.md` (el 28 % de Eclipse "en `parametro`"; la fórmula de la gemela),
  `.claude/agents/gp2-auditor-costos.md` y `gp2-cargador-excel.md` (mandaban a leer
  `v_valor_stock`, borrada el 04/09: el auditor de costos habría arrancado con un error) y
  `tests/README.md` (la fórmula de la OC con "− pendiente"). Corregidos; las menciones en
  bitácoras históricas (`ANALISIS_*`, `AUDITORIA_*`, changelogs de pantallas) se dejan.
- Advisors de Supabase tras las 4 migraciones de hoy: seguridad **0 hallazgos en GP2** (los 697
  que lista son todos de `public`, la casa del vecino: 42 vistas SECURITY DEFINER, 10 tablas sin
  RLS, 65 funciones con `search_path` mutable…); performance en GP2 sólo INFO (14 FKs sin índice
  en tablas de decenas de filas, 5 índices sin uso todavía — el de `produccion(legajo, fecha)` es
  de ayer). Misma decisión: no indexar tablas chicas.
- Circuito de escritura completo en rollback, después de los ciclos 8–10: recepción de insumo en
  kg, envío a PS, envío + entrega de tallerista, ajuste con la palabra vieja `unidad`, OC a Charcas
  en paquetes y su recepción en kg de balanza — 7 llamadas, IC3 en Fleje +40 kg exactos, B8 en
  Danica +13, la OC de 2 paquetes (20 kg) queda `recibida` con 20 kg cruzados, conservación
  ledger ↔ inventario 0 desvíos, 0 unidades fuera de vocabulario. `db/verificar.sql` 26 en 0.

## Ciclo 12 — la configuración también tiene invariantes, y versión, 07:50–08:05 AR

- `db/verificar.sql` gana 3 reglas: **Z** toda clave de `parametro` que lee el código (12: los
  `clave = '…'` de funciones y vistas) existe — si falta, la función cae a un default escrito en
  el código y nadie se entera —, **Z2** ninguna clave que nadie lea (hoy las 12 filas de la tabla
  son exactamente las 12 que lee el código: las dos `*_desperdicio_pct` que quedaron huérfanas al
  pasar a `proveedor_servicio` se borraron en el ciclo 10), **Z3** todo PS híbrido tiene una
  materia prima con proveedor de insumo (sin eso `crear_oc` no puede armar la gemela). Las 3 en 0
  → **29 invariantes**.
- `version.js` v1.109.2 (token `20260905s` en `login`, `GP2_MODULOS`, `envios-only`): la OC
  cambió de comportamiento (Charcas en kg, gemela genérica) y el celular tiene que saberlo.

## Ciclo 13 — el test de la OC cubre a Charcas, 07:50–07:58 AR

- `test_oc.js` gana un insumo de Resortes Charcas y prueba lo de los ciclos 9–10 desde la
  pantalla: el sugerido en unidades se convierte a PAQUETES con el `charcas_kg_x_paquete` del
  bundle (el fixture manda 20, no 10: si la pantalla siguiera con el 10 escrito, la cuenta
  cambia), la equivalencia «= N uni», el payload a `crear_oc` con `unidad='paq'`, y el mensaje de
  la OC gemela armado desde la respuesta genérica. El test atrapó de entrada una imprecisión: el
  mensaje redondeaba 40,8 kg a «41» (`fmt` sin decimales) — ahora muestra un decimal.

## Ciclo 14 — últimos ángulos: tablas chicas, docs de la OC, copias de helpers, 07:56–08:10 AR

- El barrido de vocabularios del ciclo 9 se saltaba las tablas de menos de 5 filas: se repitió
  sobre ellas (`orden_compra.estado`, `relevamiento.estado`, `ruta_revision.estado`,
  `rollo_evento.motivo`, `faltante_marcado.origen`) y **todas ya tenían CHECK**; `oc_marcar`
  además valida el estado. Nada que agregar: el vocabulario de la base queda cerrado.
- Docs de la OC al día con los ciclos 9–10: `REGLAS_OC_INSUMOS.md` (sección nueva «PS híbridos
  — OC gemela», y el sugerido decía todavía «− pendiente OC»), `CLAUDE.md` (los paquetes de
  Charcas salen de `parametro.charcas_kg_x_paquete`), changelog v1.20.0 en `OC_GP2.html`.
- Cuatro pantallas cargaban `gp2-ui.js` y conservaban un `hoyAR()` propio byte a byte igual al de
  la casa (`EntregasAT`, `DevolucionCervantes`, `ProblemasMatrices` — con el mismo offset en días
  —, `monitor2`); el guardia sólo miraba las implementaciones en UTC, no el nombre. Pasan a
  `var hoyAR = GP2UI.hoyAR` (cero cambio de semántica) y `test_helpers_ui` gana la regla "sin
  `function hoyAR` propio". Los `fechaAR` locales NO se tocaron: el de EntregasAT muestra el año
  con 2 cifras y el de la casa con 4, y en 390px eso es una decisión de pantalla → **idea 7265**.
- Pregunta 8 ítem 24: `matriz.tipo` (A/B/D/P, nadie lo lee) y `empleado.tipo` (texto libre en el
  ABM) — con la respuesta se cierran con CHECK o se borran.

## Ciclo 15 — segunda opinión sobre la OC gemela: la regla generalizada era un modelo dado de baja, 08:10–08:35 AR

- Se le pidió a `gp2-experto` que cruzara la regla única de OC gemela (ciclo 10) con lo decidido.
  Respuesta incómoda y correcta: **el 04/09 el usuario había decidido** (`CONOCIMIENTO`, §Altrak/
  Charcas, "pendiente de implementar en `OC_GP2.html`") que la OC del Fleje 90 va SOLO a Altrak y
  que NO hay OC gemela en el flujo de Charcas — el corte entra por la recepción. El código siguió
  vivo con el modelo anterior (pantalla en paquetes + gemela a Altrak) y los ciclos 9–10 lo
  arreglaron y generalizaron **sin haber leído esa sección**. El arreglo del bug (paquetes sumados
  como kg) y la normalización de unidades siguen valiendo; la existencia misma de la gemela para
  Charcas queda como **pregunta 28** (A: apagarla, como decidiste; B: dejarla y completar vínculo
  padre–hijo + norma de envase). `REGLAS_OC_INSUMOS.md` lo marca como "lo que hace el código, no
  lo decidido".
- **El 2 % de desperdicio de Charcas era un default inventado** por un agente el 01/09
  (`coalesce(valor, 2)`), y el 04/09 el usuario dijo "sin dato, asumir 0". Al pasarlo a columna se
  le dio categoría de dato. Migración `refactor_20260905_charcas_desperdicio_0`: Charcas 0,
  Eclipse 28 (ese sí calibrado con remito). Con 0 la OC y la recepción de Charcas (1:1) vuelven a
  ser coherentes.
- Siete hallazgos más del experto sobre el circuito de la gemela (OC mixta sin validar, `paq`
  convertido para cualquier proveedor, `kg_x_uni` nulo → 0 kg en silencio, sin vínculo entre las
  dos OC, sin norma de envase, Eclipse no pedible desde la pantalla, precios de IC3/IC3V cargados
  como de Altrak y MP sin precio) → **idea 7267** y `CONOCIMIENTO` (+2 datos con 7 puntos).
- Lección para la bitácora: antes de generalizar una regla de negocio hay que leer su sección en
  `CONOCIMIENTO_GP2.md` entera, no sólo el código vivo. El código puede ir atrás de una decisión.

### Estado final
**47 tablas · 13 vistas · 119 funciones (96 RPC + 23 internas) · 153 constraints (17 vocabularios cerrados) · 37 tests (guardias con 5 + 6 + 4 reglas) · 29 invariantes en 0 · 12 claves de `parametro`, todas leídas · 28 preguntas (la 8 con 24 datos; la 28 es la OC gemela de Charcas) · ideas 7250–7267 (7253, 7256, 7257 y 7262 hechas; 7255 y 7265 a medias).**

---

## Decisiones arquitectónicas (acumuladas)

1. **Las copias de datos no viven en la base.** Un snapshot "por si hay que volver atrás" va a
   `db/` en git (CSV chico) o se recomputa; nunca queda como tabla `snap_*`/`_bak_*` en el schema.
2. **Una función sin llamador se borra**, no se guarda "por si acaso": está en git
   (`db/funciones_GP2.sql`) si hace falta recuperarla.
3. **Toda tabla GP2 tiene RLS + policy de lectura**; escritura sólo por RPC SECURITY DEFINER.
4. **No se renombran columnas por prolijidad.** Conviven `comp_id` (`movimiento`, `ruta_paso`) y
   `componente_id` (`inventario`, `articulo_componente`...), `cod`/`codigo`, `fecha`/`creado_en`.
   Renombrar toca decenas de funciones y pantallas por cero valor de negocio; la regla es
   **no agregar una tercera forma** (una tabla nueva usa `componente_id`, `codigo`, `creado_en`).
5. **Los helpers de pantalla y el cliente viven en un archivo cada uno** (`gp2-ui.js`,
   `gp2-numero.js`, `supabase-config.js:GP2_SB`) y hay tests que fallan si vuelve una copia.
6. **El vocabulario del ledger es cerrado** (CHECK) y **la escritura es sólo por RPC**: una
   palabra nueva o un `from().update()` en una pantalla se agregan a propósito, no por accidente.
   Las 16 palabras están todas vivas: 13 las escriben las RPC, `stock_inicial` es la carga del
   28/08, y `armado_fabrica` / `consumo_prod` las emite el motor JS (Stocks General → armado en
   fábrica) vía `registrar_movimientos`.
7. **Tampoco se renombran RPC ni parámetros por prolijidad** (`crear_*` / `cargar_*` /
   `registrar_*` / `alta_*` / `abm_*` conviven; `row_id` vs `p_id`): cada renombre toca una
   pantalla por cero valor. Una RPC nueva se llama `<verbo>_<cosa>` con parámetros `p_*`.
8. **Toda contraparte nace con su ubicación** (`alta_proveedor_servicio` la crea; los talleristas y
   Prov AT nuevos también tienen que crearla) y `db/verificar.sql` lo vigila.
9. **Toda columna de tipo / estado / origen / unidad / moneda tiene vocabulario cerrado (CHECK)**
   cuando alguna función compara con el literal: 17 al cierre (`tipo_mov`, `unidad_medida`,
   `estado_compra`, `modo_control`, `maquina`, `tiempo_unidad`, `contraparte_alias.tipo`,
   `movimiento.unidad_*`, `ubicacion.tipo`, `ruta_paso.tipo_paso`, `inventario.*_origen`,
   `moneda`, `unidad`, `empresa`, `tipo_entrega`). Las unidades son dos palabras, `kg` y `uni`,
   y el trigger del ledger traduce lo que venga. Quedan abiertas las clasificaciones que carga el
   usuario (`matriz.tipo`, `marca`, `rubro`).
10. **Nada por nombre en el código.** Un proveedor, un PS o un componente no se reconocen por su
    nombre en una función: se resuelven por datos (`proveedor_servicio.hibrido` +
    `mp_componente_id` + `desperdicio_pct` → la OC gemela; `sector.es_insumo`; `ubic_de`). Un PS
    híbrido nuevo se configura en la tabla, sin tocar `crear_oc`.

## Riesgos pendientes
- `auth-guard.js` tiene la lista de páginas del rol `envios` apuntando a pantallas del programa
  viejo (login apagado hoy, así que no aplica; si se prende, la tablet queda restringida a las
  viejas). Se resuelve con la respuesta a la pregunta 1 de `PREGUNTAS_ARQUITECTURA_GP2.md`.
- **Stock inicial de talleristas y PS no cargado**: 37 renglones negativos (IJUPA, Pettofrezza,
  Pedernera/Carlos…) porque Virgilio consume lo que GP2 nunca vio entrar. El motor cierra, los
  números de "qué tiene cada tallerista" no sirven hasta cargar ese stock (pregunta 8).
- **80 renglones con mínimo > máximo** (pregunta 27): Faltantes y la OC se contradicen en esas
  piezas hasta que el usuario diga qué regla manda.
- **El espejo de Virgilio no reintenta** (idea 7261): un `error:` técnico en una entrega queda
  perdido hasta que alguien mire `db/verificar.sql` (regla O) o Alertas (`espejo_pend`).
- **Recepción Insumos lee números con otra regla** (idea 7259): `12.5` es 12,5 ahí y 125 en el
  resto de la casa; se migra con el operario al lado.
- **Sector 13 «Alambre» sin ubicación** (pregunta 21): `FLEJE90_BRUTO` vive en Charcas y
  `ubic_de_componente` lo manda a Virgilio; cualquier función genérica que lo toque se equivoca.
- **Las 70 páginas del programa viejo** (44 pegan a `public`) siguen en el repo y en el menú de
  `auth-guard.js`; se borran con la respuesta a la pregunta 1.
- **`componente.marca` con `LOEKE` ×73 y `LOKE` ×8** (pregunta 8, ítem 23): las pantallas las
  muestran como dos marcas hasta que el usuario diga si son una.
- **`entrega_prov_at.dia_mes`** (idea 7264): 112 entregas viejas sólo tienen la fecha ahí (4 sin
  año); `entregas_at_bundle` hace `coalesce(fecha_rto, dia_mes)` mientras tanto.
- **`test_kg_y_unidades.js` sensible a la carga** (idea 7266): pasa solo y en 6 de 7 corridas de
  la suite; falló en la que se solapó con otra suite. No es un bug de la pantalla.
- **La OC gemela de Charcas es un modelo que el usuario dio de baja el 04/09 y el código sigue
  haciendo** (pregunta 28, ciclo 15): hasta que conteste, `CONOCIMIENTO` y `REGLAS_OC_INSUMOS` se
  contradicen a propósito (uno dice lo decidido, el otro lo que hace el código). Si alguien crea
  una OC a Charcas hoy, sale la gemela a Altrak con 0 % y sin vínculo con la primera (idea 7267).
- **La OC de Charcas nunca se probó con una OC real** (ciclos 9–10): el circuito paquetes → kg →
  gemela a Altrak → recepción está probado en rollback y en `test_oc`, no con un pedido de verdad.
