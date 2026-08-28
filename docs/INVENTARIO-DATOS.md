# Inventario de datos — qué usa este repo y de dónde sale

> Relevado el 2026-08-28 contra el código real del repo y el catálogo real de Supabase
> (proyecto Virgilio `hrxfctzncixxqmpfhskv`). Complementa `docs/AUDITORIA-DATOS-DUPLICADOS.md`
> (idea 7411): ahí está QUÉ está duplicado; acá está QUÉ se usa y DÓNDE vive.

## 1. Resumen

El repo (raíz Virgilio: `index.html`, `recepcion.js`, `sw.js`, `planimetria.js`,
`fichada*.js/html`, `fichadas-monitor.html`, `productividad.html`, `monitor/`,
`modulo_talleristas_*.js`, `pasaje-papeles.js`) referencia **113 objetos de datos**:

| Dónde vive | Cuántos | Detalle |
|---|---|---|
| Virgilio — tablas | 69 | schema `public` de `hrxfctzncixxqmpfhskv` |
| Virgilio — vistas | 38 | `vista_*`, `v_*` |
| Virgilio — matview | 1 | `vista_stock_procesada` (refresh cada 2 min) |
| **Proyecto LK** (`kwkclwhmoygunqmlegrg`) | 4 | `customers`, `products`, `loke_products`, `remitos` |
| **No existe** | 1 | `Stock_Saldos` ⚠ ver §4 |

Además usa **20 RPCs** (`/rest/v1/rpc/…`): `aceptar_conteo`, `anular_picking_virgilio`,
`anular_toggle_virgilio`, `corr_convertir_faltante`, `cp_completar_faltante`,
`cp_reducir_faltante_cap`, `facturacion_neto_detalle`, `facturacion_neto_lote`,
`faltante_resolver`, `generar_inconsistencias`, `insumo_unidad_guardar`,
`nuevo_insumo_tmp`, `racks_plani_descontar`, `racks_plani_mover`, `reasignar_cajas`,
`rechazar_conteo`, `tanda_liberar`, `tanda_reservar`, `ventas_mensuales_cod`,
`zona_barrio_set`.

Y **Edge Functions**: `arca-wsfe` (facturación ARCA), `sync-clientes-dto`, más las de
fichada/recon-facial. `/admin/` (espejo de PaginaLK) apunta al proyecto **LK**, no a este.

## 2. Los datos más usados (por cantidad de referencias en el código)

`Stock_Config` (16) · `OC_Maximos` (14) · `PPP_Entregados_Meta` (8) · `PPP_Base_Pedidos` (8) ·
`Movimientos_Stock` (7) · `Pasaje_Papeles` (6) · `PPP_Programacion_Diaria` (6) · `Empleados` (6) ·
`vista_saldos_stock` (5) · `Registros_Produccion_Virgilio` (4) · `Racks_Planimetria` (4) ·
`PPP_Geo` (4) · `Articulos_Discontinuados` (4) · `Tall_ProvAT_PS` (4).

## 3. Las HOJAS de Google que usa el repo, y dónde están en Supabase

Son **2 planillas**. Ninguna la lee el front directo: todas entran a Supabase y la app lee
de las tablas (desde v5.34 `index.html` ya no contacta Google).

### 3.1 Planilla PPP — `1-16YXe0xq6x9i-Yhk5cm5V3VqvQ0PWZtcDbm8OeeKW0`

| Hoja | Tabla en Supabase | Cómo llega | Frecuencia | Estado (2026-08-28) |
|---|---|---|---|---|
| `PPP Excel Programacion Diaria` | **`PPP_Programacion_Diaria`** | **Apps Script push** (`apps-script/sync-ppp-supabase.gs`, service_role, DELETE+INSERT) | al guardar en la hoja | 148 filas |
| `PPP Excel Base Datos Pedidos` | **`PPP_Base_Pedidos`** | **Apps Script push** (mismo script) | al guardar en la hoja | 11.954 filas |
| `PPP Excel Pedidos Entregados 2026` (gid **2146771217**, col `Mt3` — NO "Mt3 FC") | **`PPP_Entregados_Meta`** | **pg_cron pull**: `sync_ppp_entregados_meta()` (`http_get` + parseo CSV, TRUNCATE+INSERT) | job **27**, `7,37 * * * *` | 2.728 filas · último OK 22:37 ✅ |

⚠ Son **dos mecanismos distintos** para la misma planilla (push por Apps Script vs pull por
cron), con parsers distintos — es el TOP-7 de la auditoría. La tabla
`PPP_Pedidos_Entregados` (tercer espejo) **se borró en v10.25**.

### 3.2 Planilla Fichadas — `19jF76wpbkVi7qBYNQ6BeZe1w5skJojljLJZttaOBD8g`

| Hoja | Tabla en Supabase | Cómo llega | Frecuencia | Estado (2026-08-28) |
|---|---|---|---|---|
| Respuestas del Google Form (gid **1495479968**) | **`Fichadas_Historico`** | `sync_fichadas_respuestas()` (upsert idempotente por `UNIQUE(ts_evento,email,evento)`) | job **25**, `*/2 * * * *` | 16.540 filas · último OK 22:46 ✅ |
| Pivot / estructura (gid **1548577326**) | **`Fichadas_Estructura`** | `sync_fichadas_estructura()` (full replace) | job **26**, `*/10 * * * *` | 27 filas · último OK 22:40 ✅ |

⚠ `Fichadas_Historico` recibe **dos escrituras**: este cron **y** el front (fichada.js espeja
sus fichadas ahí además de a `Fichadas_Virgilio`) — ver balde 2 de la auditoría.
⚠ El job 25 (cada 2 min) acumuló **9 corridas fallidas en 48 h** (de ~1440): intermitente,
se recupera solo, pero no hay watchdog que avise si dejara de recuperarse.

## 4. Hallazgo: `Stock_Saldos` no existe

`index.html:15548` consulta `/rest/v1/Stock_Saldos`, pero **esa tabla no existe** en el
proyecto. La llamada usa `supaFetchAllSafe(...).catch(→ [])`, así que falla en silencio y
devuelve vacío. Hay que decidir: crear la tabla/vista, apuntar a `stocks_carga_rapida` o
`vista_saldos_stock`, o borrar el fetch muerto.

## 5. Datos que NO son de este proyecto

`customers`, `products`, `loke_products`, `remitos` viven en el proyecto **LK**
(`kwkclwhmoygunqmlegrg`) y se leen con la anon key de LK (`SUPABASE_LK_KEY` en `index.html`).
Es la decisión de arquitectura documentada en `CLAUDE.md`: coexistencia, NO migración.
