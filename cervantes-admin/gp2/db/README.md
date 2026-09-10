# db/ — Respaldo del schema GP2

Export automático **2026-09-05** (cierre de la auditoría de arquitectura del 2026-09-04, ver
`REFACTOR_GP2.md`) desde Supabase (`hrxfctzncixxqmpfhskv`). El schema vive SOLO en la base
(las migraciones se aplican por MCP y no quedan en el repo): este directorio es la foto.

| Archivo | Contenido | Exactitud |
|---|---|---|
| `tablas_GP2.sql` | **47 tablas** (columnas, identity, defaults, **comentario en las 47 tablas** y en 44 columnas) + 153 constraints (PK, UNIQUE, FK, CHECK — 17 vocabularios cerrados) + 49 índices sueltos + 9 triggers + RLS en las 47 + 47 policies (todas SELECT) | DDL reconstruido de `pg_catalog`; constraints/índices/triggers exactos vía `pg_get_*def` |
| `funciones_GP2.sql` | Las **119 funciones/RPC** del schema (96 RPC de pantalla + 23 internas) | Exacto (`pg_get_functiondef`), **verificado md5 contra la base** (119/119 el 2026-09-05 ~10:30 UTC, tras los ciclos 8–9: `fn_movimiento_calc`, `crear_oc`, `oc_bundle`, `crear_entrega_prov_at`) |
| `vistas_GP2.sql` | Las **13 vistas** (con sus `comment on view`) | Exacto (`pg_get_viewdef`) |
| `verificar.sql` | **29 invariantes** de la base en una consulta (contrapartes con ubicación, inventario = ledger, grants, RLS, `search_path`, PS híbridos y su materia prima, códigos, rutas y recetas, recepción ↔ ledger, espejo de Virgilio, claves de `parametro` que lee el código): cada fila debe dar `n = 0` | Sólo lectura; correrla antes de tocar la base y al cerrar; el agente diario la corre al empezar |
| `relevamiento_GP2.sql` | Registro de las 3 migraciones del Relevamiento nativo (2026-09-04) con su porqué | Documental; el estado vigente está en los tres archivos de arriba |
| `PENDIENTE_v_costo_componente_servicio_exacto.sql` | Cirugías de costos aplicadas el 2026-08-31 + el pendiente de servicios exactos por pieza | Documental / idempotente |
| `respaldo_inventario_minimo_20260902.csv` | Las 378 filas de `inventario` cuyo mínimo cambió el 2026-09-02 (mínimo anterior y recalculado) | Reemplaza a la tabla `inventario_minimo_backup_20260902`, borrada el 2026-09-04 |

Comparado con el export anterior (2026-08-31: 51 tablas / 102 funciones / 15 vistas — y la base
llegó a tener 67 / 135 / 16 el 2026-09-04 por las fotos `snap_*` y funciones huérfanas):
**menos objetos, no más**. Lo que se fue y por qué está en `REFACTOR_GP2.md`; en resumen:
13 fotos `snap_*`/backup, `agente_propuestas`, `tallerista_alias`, `ruta_confirmada`+`ruta_problema`
(→ `ruta_revision`), `estadistica`, `entrega_cervantes`, `precio_servicio`, `devolucion_tallerista`
(→ `movimiento.nota`), `proveedor_servicio_alias` (→ `proveedor_servicio.nombre_corto`); vistas
`v_consumo_parte`, `v_consumo_fleje_kg` v1 (la v2 volvió a llamarse así), `v_punto_stock`,
`v_valor_stock`, `v_valor_pedido`; las funciones sin llamador; y `cargar_compra_altrak` +
`cargar_compra_aperam_chapa` (→ `cargar_compra_mp(p_proveedor, …)`, con la materia prima de cada PS
híbrido en `proveedor_servicio.mp_componente_id`). Nuevo: `ubic_de(tipo, ref_id)`
(una sola forma de resolver ubicaciones), `v_nivel_stock`, `v_contraparte_parte`, `sector.es_insumo`, `movimiento.nota`,
el CHECK de vocabulario de `movimiento.tipo_mov`, y FKs/índices que faltaban.

**Qué NO incluye**: los DATOS (maestros e inventario viven en la base), los GRANT/REVOKE
(ver abajo), las secuencias sueltas viejas (quedan como `default nextval(...)`), ni los dos
triggers espejo que viven sobre tablas de `public` (`trg_virgilio_espejo_gp2` sobre
`Entregas Tallerista Virgilio` → `fn_entregas_virgilio_espejo`; `trg_est_madre_sync_gp2` sobre
`proyeccion_madre` → `fn_est_madre_sync`; sus funciones sí están en `funciones_GP2.sql`), ni el
`cron.job` `actualizar_dolar_oficial`.

**Grants (2026-09-04)**: ninguna tabla GP2 acepta escritura anónima directa (todas las policies
son SELECT para `anon, authenticated`; la escritura va por RPC SECURITY DEFINER). Las **23
funciones internas** (helpers `_aplicar_recepcion_a_oc`, `_es_sector_insumo`, `to_canonical`,
`inv_delta`, `ubic_de`, `ubic_de_componente`, `recepcion_tara`, `relev_*`; las `fn_*` de trigger;
`recalcular_*`; `recepcion_virgilio`; `actualizar_dolar_oficial`) **no tienen EXECUTE para
`anon`** (`alter default privileges ... revoke execute on functions from public` + REVOKE
explícito). Las 96 RPC de pantalla sí. Al crear una RPC nueva: `grant execute on function
"GP2".x to anon, authenticated`. Las **secuencias** tampoco tienen USAGE para `anon`/`authenticated`
(las 4 que lo conservaban — `movimiento`, `entrega_prov_at`, `articulo_prov_at`,
`uni_x_articulo_x_caja` — se revocaron el 2026-09-05; ninguna función no-DEFINER escribe).
**`search_path`**: todas las funciones GP2 tienen `set search_path = GP2` (sólo GP2; desde el
2026-09-05), salvo `get_role_for_email` (`public`, delega) y `actualizar_dolar_oficial`
(`GP2, public, extensions`, usa `http`). Una función nueva se crea con `set search_path to 'GP2'`.

**Para restaurar en una base vacía**: correr en orden `tablas_GP2.sql` → `funciones_GP2.sql` →
`vistas_GP2.sql`, después los 2 triggers de `public`, el cron y los grants. Ojo con el orden de
las FKs entre tablas (si falla, correr las FKs en una segunda pasada) y con el orden de las
vistas (`v_consumo_demanda` antes que `v_consumo_componente`; `v_consumo_fleje_kg` y
`v_consumo_componente` antes que `v_nivel_stock` y `v_faltante_estado`; `v_control_pallet` antes
que `v_recepcion_control`); los archivos van alfabéticos, así que si algo falla, repetir la pasada.

**Para regenerar este export**: pedirle a Claude "regenerá db/". Son las tres consultas de
**`db/regenerar.sql`** (solo lectura sobre `pg_catalog`; cada una devuelve el texto de un archivo),
y se verifica con `md5(pg_get_functiondef)` contra el archivo. Truco con el MCP de Supabase: si el
resultado es chico viene "inline" y no se puede guardar tal cual; concatenar `|| repeat(' ', 300000)`
al final fuerza que quede en un archivo de tool-result, y después se recorta (así se regeneró
`vistas_GP2.sql` el 2026-09-05).
