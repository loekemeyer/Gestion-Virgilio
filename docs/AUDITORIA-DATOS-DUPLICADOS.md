# Auditoría de datos duplicados y multi-fuente — Producción Virgilio

> Idea del usuario **normalizar-datos** (2026-08-28). Generada por agente sobre el repo +
> `GUIA-PROYECTO.md` (sin acceso directo a Supabase: lo citado sale de los DDL de `sql/`,
> `apps-script/` y el front). Objetivo: plan para normalizar las tablas.

---

## TOP 10 priorizado (impacto vs esfuerzo)

| # | Hallazgo | Impacto | Esfuerzo | Nota |
|---|---|---|---|---|
| 1 | **No existe tabla maestra de Artículos**: descripción, marca, uxb, m³, capacidad y proveedor viven repartidos en 8+ tablas keyed por `cod` con formatos distintos (§1.4–1.6) | Muy alto — es la raíz de las ~140 normalizaciones del front | Alto (por etapas) | Las vistas `vista_nombres_articulos` / `vista_marca_articulo` / `vista_uxb_articulo` ya son el embrión: falta la tabla `Articulos` canónica debajo |
| 2 | **`cod_art` sin canónico en el WRITE**: `fn_canon_cod_art` excluye los tipos `picking/separado/facturado` (`sql/canon_cod_art.sql:36`) y ninguna otra tabla (Entregas_Virgilio, Racks_*, Capacidad_*) canonicaliza al insertar | Alto — obliga a `_ocgNorm` en 140 lugares de index.html + normalizadores paralelos | Medio | Extender el trigger (o `norm_cod`) a todas las tablas con `cod` y guardar SIEMPRE el canónico |
| 3 | **Planimetría en 2 capas + capacidad en 2 tablas**: `window.GONDOLA` estático (planimetria.js:9) + tabla `Planimetria` que lo pisa (index.html:7312) + `Capacidad_Sector` + `Capacidad_Gondola` — el mapa sector↔cod vive en 4 lados | Alto | Medio | Dejar `Planimetria` como única fuente; `planimetria.js` pasa a cache generado o desaparece |
| 4 | **Regla de empresa (LK/CH) duplicada front/SQL**: `empresaDeNp` NP>90000 + `EMPRESA_SPLIT_CODS` + `NOMBRE_POR_EMPRESA` hardcodeados en index.html (7360, 10202, 10185) y la misma regla re-tipeada en SQL (`sql/nc_loeke_chef.sql:64`, `vista_faltante_demanda`) | Alto — regla de negocio frágil (rangos de NP) en ≥5 lugares | Bajo/Medio | Función SQL `empresa_de_np(np)` + tabla `Codigos_Duales`; el front la consume |
| 5 | **`EQUIV_FAMILIAS` duplicada literal**: lista curada a mano DOS veces — const en index.html:11302 y tabla `Equivalencias_Familia` (`sql/equivalencias_familia_secundarios.sql:7` lo admite: "= EQUIV_FAMILIAS en index.html") | Alto riesgo de drift silencioso | Bajo | El front carga la tabla (como ya hace con `Equivalencias_Codigos`); borrar la const |
| 6 | **Doc/SQL del repo desactualizados vs DB**: `PPP_Pedidos_Entregados` se BORRÓ el 2026-08-12 (v10.25) pero CLAUDE.md (Quick-ref), GUIA §3/§7/§11 (líneas 6981, 7424, 7534) y `sql/productividad_operario.sql:163-185` (definición vieja de `vista_tanda_m3`) siguen citándola | Alto para cualquier agente/persona que responda con la guía | Bajo | Actualizar guía + re-versionar la vista viva; la regla "la fuente de verdad es la DB" (sync_ppp_entregados_meta.sql:7) invita a este drift |
| 7 | **Sheet PPP espejado por 2 mecanismos distintos**: Apps Script push (Programación + Base, reemplazo total, parseo por posición) vs función Postgres `sync_ppp_entregados_meta()` pull cada 30 min (parseo CSV por regex) — parsers distintos del mismo Sheet | Medio/Alto | Medio | Unificar en pull server-side (patrón sync_ppp_entregados_meta) para las 3 tablas → se elimina la service_role key del Apps Script |
| 8 | **Precios en 3 copias + 1 vía en vivo**: `precios_venta` (snapshot manual desde LK), `precios_venta_chef` (2 pasos a mano), `cob_uxb_lk`, y la Edge Fn `arca-wsfe/preciar` que lee LK EN VIVO — el "💵 Neto" (snapshot) puede diferir de la factura emitida (vivo) | Alto ($ visibles) | Medio | Automatizar `precios_venta*` con Edge Fn + cron (patrón `sync-clientes-dto` ya probado) |
| 9 | **Faltantes en 5 representaciones**: `PKC` (esp\|real), `Entregas_Virgilio.cajas_falto`, `Faltantes_Tareas`/`_Revisados`/`_Avisados`/`_Notas`, `NPD`, y las vistas `vista_faltante_real/demanda/catalogo` | Medio/Alto | Alto | Declarar canónico persistido (`Entregas_Virgilio.cajas_falto`) + todo lo demás vistas derivadas de PKC |
| 10 | **Anon key en 6 archivos y la guía dice 3**: index.html:4084, sw.js:15, fichada-config.js:14, fichadas-monitor.html:263, recepcion.js:29, productividad.html:493 (GUIA:369: "vive en 3 archivos — rotar los 3" — subconteo) + la key de LK aparte en admin/admin.js | Medio (operativo al rotar) | Bajo | Un `supabase-config.js` compartido; corregir la guía ya |

---

## Balde 1 — Mismo dato en 2+ tablas de Supabase

### 1.1 m³ (metros cúbicos)
- **Dónde**: `PPP_Programacion_Diaria.m3` (por NP, programado) · `PPP_Entregados_Meta.m3` (por NP, entregado; `sql/sync_ppp_entregados_meta.sql`) · `Facturacion_NP.m3` (**snapshot al tick** de la operadora, GUIA:7039-7041) · vista `vista_tanda_m3` (COALESCE entregado→programado; definición VIEJA en `sql/productividad_operario.sql:172-185` — la viva ya lee `PPP_Entregados_Meta`, GUIA:560) · `Volumen_Articulos.m3` (por artículo — concepto distinto, m³ de catálogo, index.html:7712).
- **Fuente de verdad hoy**: Google Sheet "PPP Pedidos Entregados 2026" col G `Mt3` (upstream); en Supabase, `PPP_Entregados_Meta` para entregado + `PPP_Programacion_Diaria` para programado, ya unificadas en `vista_tanda_m3`.
- **Divergencia vista**: el propio repo documentó 3 tandas con m³ distinto entre los dos espejos antes de la unificación v10.25 (GUIA:553-555). `Facturacion_NP.m3` es una foto: si la operadora corrige el m³ en el Sheet después del tick, diverge y nadie lo reconcilia.
- **Propuesta**: `vista_tanda_m3` queda canónica; `Facturacion_NP.m3` → columna derivable (vista join a PPP por np) o al menos documentar el semántico "snapshot al facturar". Actualizar `sql/productividad_operario.sql` y GUIA/CLAUDE.md (tabla borrada — TOP-6). **Esfuerzo bajo · riesgo bajo** (la app ya lee la vista).

### 1.2 Faltantes (lo que no salió)
- **Dónde**: eventos `PKC` en `Registros_Produccion_Virgilio` (`TANDA|COD|ESP|REAL`, la medición cruda) · `Entregas_Virgilio.cajas_falto` (reparto del faltante por NP en el wizard, GUIA:7024) · `Faltantes_Tareas` (tarea de reposición, index.html:21471, `sql/detectar_faltantes_llegaron.sql`) · `Faltantes_Revisados`/`Faltantes_Avisados` (cierre/dedup de alertas, `sql/faltantes_resolver.sql`) · `Faltantes_Notas` (día resolución/motivo, index.html:16052) · eventos `NPD` (difiere de mesa) · vistas `vista_faltante_real` (re-deriva de PKC), `vista_faltante_demanda`, `vista_faltante_catalogo` (GUIA:7199-7217).
- **Fuente de verdad hoy**: ambigua — `vista_faltante_real` deriva de PKC mientras `Entregas_Virgilio.cajas_falto` es lo persistido que consumen facturación, plata perdida (`sql/plata_perdida.sql`) y el programa externo. `CP` (Completar Pedido) muta `cajas_falto` y re-emite TAL, pero NO re-escribe el PKC → los dos caminos divergen por diseño después de un CP.
- **Propuesta**: declarar `Entregas_Virgilio.cajas_falto` el canónico persistido del faltante comercial y PKC el canónico del faltante operativo (picking), y que TODAS las vistas de faltante digan de cuál derivan; unificar el ciclo de vida (Tareas/Revisados/Avisados/Notas podrían ser una sola tabla `Faltantes` con estado + nota). **Esfuerzo alto · riesgo medio** (hay triggers Telegram y consumidor externo).

### 1.3 Cliente / razón social
- **Dónde**: `PPP_Programacion_Diaria.razon_social` · `PPP_Entregados_Meta.rs` · `Facturacion_NP.razon_social` (snapshot al tick) · `Alertas_Pedidos_Web.cliente` · `clientes_dto` (cod→dto, espejo LK) · `clientes_vendedor` (cod→vendedor, snapshot LK, GUIA:947) · `whatsapp_clientes` (cod→tel). No hay tabla `Clientes` en Virgilio; el padrón real es `customers` del proyecto LK.
- **Riesgo**: razón social re-tipeada por fila (viene del Sheet); un cambio de nombre en LK deja copias viejas en 3+ tablas. Divergencia potencial, no vista en el repo.
- **Propuesta**: tabla `Clientes` espejo de LK (cod PK, razón social, tel, vendedor, dto) con el sync ya existente de `clientes_dto` ampliado; `whatsapp_clientes`/`clientes_vendedor` se pliegan ahí; las tablas de hechos guardan solo `cod_cliente` (FK débil) y la RS sale por join/vista. **Esfuerzo medio · riesgo medio** (dto_vol es sensible: mantener RLS cerrada como hoy — GUIA:104-105).

### 1.4 UxB (unidades por caja) — 4+ columnas
- **Dónde**: `precios_venta.uxb` (venta) · `Articulos_Cajas.Uni_x_Caja` (depósito/empaque) · `OC_Maximos.uni_x_caja` (compras) · `Importados.uni_x_caja` (caja inner) + `Importados_Volumen.uni_master` (master, GUIA:1127-1129) · `Articulos Virgilio X Tallerista` (cajas_x_master/uni_x_caja, GUIA:7228-7229).
- **Estado**: auditado el 2026-08-22/23 (GUIA:361-368): se decidió **NO unificar globalmente** porque es dependiente del contexto (ej. 724: 24 depósito / 4 venta) y se creó `vista_uxb_articulo` (canónica de depósito, index.html:10173). Divergencia REAL vista: 589E uxb 12→24 corregido en dos tablas a mano (GUIA:396).
- **Propuesta**: una tabla `Articulos_UxB(cod, contexto, uxb)` (o columnas uxb_venta/uxb_deposito/uxb_compra/uni_master en la maestra del TOP-1) para que "corregir un uxb" sea un UPDATE, no una cacería en 4 tablas. **Esfuerzo medio · riesgo medio** (los cálculos de plata NO deben cambiar de fuente sin querer — nota explícita GUIA:367).

### 1.5 Descripción de artículo
- **Dónde**: `E. Madre LK` · `Articulos Virgilio X Tallerista` · `OC_Maximos.descripcion` · `Articulos_Cajas.Descripcion` (**con duplicados: 026 = "Colador N°8" y "Pinza de Fideos"**, GUIA:4846-4848) · `precios_venta.descripcion` · `Importados` · `Insumos.nombre` · `Comprobantes_NC_Items.descripcion`.
- **Estado**: resuelto en lectura con `vista_nombres_articulos` (prioridad E. Madre > X Tallerista > OC_Maximos; index.html:10139-10152). Recepción usa a propósito el Desc del tallerista (GUIA:369-370).
- **Propuesta**: la vista queda; a mediano plazo la descripción canónica vive en la tabla maestra del TOP-1 y las demás se vuelven read-only/deprecadas. **Esfuerzo bajo (ya hecho en lectura) · riesgo bajo**.

### 1.6 Marca/Línea LK/CH
- **Dónde**: `OC_Maximos.linea` · `Articulos_Cajas.Marca` · el sufijo del propio código (" LK"/" CH"/" LOKE"). Unificada en lectura por `vista_marca_articulo` + `artMarca()` (index.html:10153-10169, GUIA:362-364).
- **Propuesta**: igual que 1.5 — columna en la maestra. **Bajo/bajo**.

### 1.7 Layout físico / capacidad de góndola
- **Dónde**: `window.GONDOLA` (planimetria.js:9, generado del Excel) · tabla `Planimetria` (merge que pisa, index.html:7312-7326) · `Capacidad_Sector` (sector, cod, cajas_max — la funcional) · `Capacidad_Gondola` (snapshot completo LK+CH del Excel `Maximo_por_Estanteria.xlsx`, `sql/capacidad_gondola_final.sql:1-14`) · `Racks_Planimetria` (racks) · `Envasar_Ubicaciones` (para_envasar, GUIA nota EA) · `Insumos_Ubicaciones` + `Insumos.ubicacion` legacy.
- **Divergencia vista**: solape de orden isla I vs L/M y sector `J9` vs `J09` corregidos a mano (GUIA:396-397); el mismo par (sector, cod) existe en `Planimetria`, `Capacidad_Sector` y `Capacidad_Gondola` sin FK entre sí; `Capacidad_Sector` es "solo LK" mientras `Capacidad_Gondola` tiene emp — dos criterios.
- **Propuesta**: una tabla `Gondola_Celdas(emp, sector, cod, orden_picking, cajas_max)`; `Planimetria` y `Capacidad_Sector` se vuelven vistas sobre ella; `Capacidad_Gondola` se elimina (era referencia). Ver también TOP-3 para la capa estática. **Esfuerzo medio · riesgo medio** (generador de OC y picking la consumen).

### 1.8 Ubicación de insumos — 3 fuentes con COALESCE
- **Dónde**: `vista_insumos` hace COALESCE de `Racks_Planimetria` → `Insumos_Ubicaciones` → `Insumos.ubicacion` legacy (GUIA:7245-7252).
- **Propuesta**: migrar el legacy `Insumos.ubicacion` a `Insumos_Ubicaciones` y dropear la columna; la vista queda con 2 fuentes semánticamente distintas (racks vs piezas). **Bajo/bajo**.

### 1.9 Pedido (cajas pedidas) — snapshot deliberado
- `PPP_Base_Pedidos` es efímera (reemplazo total) y `Entregas_Virgilio.cajas_pedidas` la snapshotea al TAP (GUIA:7029-7031, "no se re-lee la efímera"). **Es diseño correcto** (registro histórico) — solo documentarlo como tal en el plan para no "desduplicarlo" por error. Evidencia de fragilidad: hizo falta el trigger dedup `sql/entregas_virgilio_dedup.sql` (retry offline + TOCTOU duplicaban filas).

### 1.10 Saldos de stock — log + 2 vistas + cálculo front
- `Movimientos_Stock` (log) · `vista_saldos_stock` · `vista_stock_procesada` (MATERIALIZED, refresh cada 2 min → ventana de 2 min de datos viejos) · `stockComputeSaldos()` en el front (solo As-Of) — GUIA:7107-7124. La lógica de saldo existe 3 veces (2 SQL + 1 JS). **Propuesta**: mantener; pero que `stockComputeSaldos` As-Of sea una RPC (`saldos_asof(ts)`) para que la fórmula viva una sola vez. **Medio/bajo**.

### 1.11 Zona de reparto
- `PPP_Programacion_Diaria.zona` (columna del Sheet, por NP) **y** `Zonas_Barrios` (barrio→zona, diccionario, GUIA:7140; index.html:26075-26099). **Divergencia VISTA y ya monitoreada**: el evento `PPE` reporta `zonadif:N` (zona de la fila ≠ zona del diccionario) y `sinzona:N` (GUIA:7331). **Propuesta**: `Zonas_Barrios` canónica; `zona` de la PPP pasa a ser derivada (o al menos el monitor PPE ya la reconcilia — formalizarlo). **Bajo/bajo**.

---

## Balde 2 — Dato espejado desde fuente externa

| Dato | Fuente de verdad declarada | Copia en Virgilio | Vía de sync | Riesgo de divergencia |
|---|---|---|---|---|
| Programación diaria + base de pedidos | Google Sheet PPP (`1-16YXe0…`) | `PPP_Programacion_Diaria`, `PPP_Base_Pedidos` | **Apps Script push** con service_role, reemplazo total, mapeo por posición (`apps-script/sync-ppp-supabase.gs:28-45`) | Si la macro no corre o cambia el orden de columnas, espejo viejo/roto sin alerta; parser distinto al de la vía 2 |
| Pedidos entregados (np, cod, rs, tanda, m³, fecha) | mismo Sheet, gid 2146771217, col G `Mt3` (NO col H "Mt3 FC") | `PPP_Entregados_Meta` | **pg_cron pull** cada :07/:37, `http_get` + parseo CSV por regex, TRUNCATE+INSERT (`sql/sync_ppp_entregados_meta.sql`) | Dos parsers distintos del mismo Sheet (posición vs ordinal de comillas); el doble espejo de esta hoja YA divergió (3 tandas) y se eliminó en v10.25 — precedente real |
| Descuento por volumen (`dto_vol`) | LK `customers` | `clientes_dto` | Edge Fn `sync-clientes-dto` + cron cada 14 días (GUIA:82-94) | Hasta 14 días de atraso — aceptado; el mejor patrón de sync del repo |
| Precios de venta LK | LK `products.list_price/uxb` | `precios_venta` | **MANUAL**: SELECT generador de INSERT corrido a mano en LK y pegado en Virgilio (`sql/plata_perdida.sql:27-36`) | Alto: sin cron, precio viejo = "plata perdida" y "💵 Neto" mal valorizados; además la factura real usa `arca-wsfe/preciar` EN VIVO contra LK → dos números distintos posibles para la misma NP |
| Precios Chef | Chef `products` (proyecto `nkhzocgdpwtgrmwleihr`) | `precios_venta_chef` | Manual 2 pasos (`sql/cobranzas_chef_sync.sql`) | Ídem anterior |
| Cliente→vendedor | LK `customers` | `clientes_vendedor` | Snapshot manual (GUIA:947) | Vendedor reasignado en LK no se refleja |
| uxb padrón LK completo | LK products ∪ loke_products | `cob_uxb_lk` (`sql/cobranzas.sql:82`) | Manual | Ídem |
| Fichadas | — (la app ES la fuente) | **doble escritura**: `Fichadas_Virgilio` + espejo `Fichadas_Historico` desde el cliente (fichada.js:29,142,235; index.html:6196-6209 espeja PC/FJ) | 2 POSTs del front | Si uno de los dos POSTs falla, las tablas divergen; nadie reconcilia. Propuesta: trigger AFTER INSERT en `Fichadas_Virgilio`/`Registros` que llene `Fichadas_Historico` server-side (1 escritura) |
| Planimetría | Excel `AAA_PPP_Vigente.xlsm` hoja "Picking" | `planimetria.js` (archivo generado, con aliases 0XX regenerables A MANO — header planimetria.js:1-8) + tabla `Planimetria` (overrides) | Regeneración manual del .js + edición admin de la tabla | Alto: dos capas con merge en runtime; el override de la tabla puede quedar tapado por una regeneración del .js o viceversa |
| Capacidad góndola | Excel `Maximo_por_Estanteria.xlsx` | `Capacidad_Gondola` + `Capacidad_Sector` | Script SQL one-shot (`sql/capacidad_gondola_final.sql`) | Cambio físico de góndola requiere re-correr un SQL de 1000 líneas |
| Panel admin / Cervantes | repos `PaginaLK` y `Registro-Produccion-2.0` | `/admin/`, `/cervantes/` | Copia manual con 7 parches locales a re-aplicar (CLAUDE.md) | Alto y ya asumido; fuera de alcance de datos, pero la **anon key de LK** duplicada en `admin/admin.js` entra en la rotación de claves |
| Nombres E. Madre | Sheet/tabla "E. Madre LK" (talleristas) | consumida vía `vista_nombres_articulos` | — | la fuente prioritaria del nombre canónico depende de un espejo de talleristas |

**Propuesta transversal balde 2**: estandarizar TODO espejo externo al patrón "Edge Function + pg_cron + columna `actualizado`" (ya probado en `clientes_dto` y `sync_ppp_entregados_meta`), y una tabla `Sync_Estado(fuente, last_ok, filas)` con alerta Telegram si un sync envejece — hoy solo el outbox tiene watchdog. Eliminar los syncs manuales de precios (TOP-8). **Esfuerzo medio · riesgo bajo** (aditivo).

---

## Balde 3 — Maestros hardcodeados en código que existen (o deberían) en tabla

| Hallazgo | Archivo:línea | Tabla equivalente | Estado / propuesta |
|---|---|---|---|
| `window.GONDOLA` (≈340 códigos→sector,orden + aliases 0XX a mano) | planimetria.js:9 | `Planimetria` (+ `Capacidad_Sector`) | La tabla solo PISA al estático (index.html:7307-7326). Invertir: tabla = fuente única; el .js muere o se convierte en cache offline generado desde la tabla. **Medio/medio** |
| `EQUIV_FAMILIAS` (lista curada completa, duplicada literal) | index.html:11302 | `Equivalencias_Familia` | **La misma lista tipeada 2 veces** (admitido en `sql/equivalencias_familia_secundarios.sql:7`). Front debe fetchear la tabla. **Bajo/bajo** |
| Semilla `_codeEquiv` {29→437E, 30→438E} | index.html:7337 | `Equivalencias_Codigos` (se mergea encima, :7387-7395) | Aceptable como fallback offline, pero si se edita la tabla y no la semilla, un arranque sin red usa datos viejos. Documentar o generar la semilla en build. **Bajo/bajo** |
| `EMPRESA_SPLIT_CODS` {437E,438E,439E,809E} + `NOMBRE_POR_EMPRESA` {809E} + regla `empresaDeNp` NP>90000 | index.html:10202, 10185, 7360-7367 | ninguna (regla también re-tipeada en `sql/nc_loeke_chef.sql:64`, `vista_nc_loeke_chef.sql:42`, `vista_faltante_demanda`) | Crear `Codigos_Duales(cod, nombre_lk, nombre_ch)` + función SQL `empresa_de_np()`; front y vistas la usan. **Bajo-medio / medio** (toca picking y stock) |
| `IMP_ALIAS` {865ED→865E} | index.html:11528 | `Equivalencias_Codigos` podría absorberlo | Alias solo-front, invisible al backend. **Bajo/bajo** |
| `INS_CATS` / `INS_UNIS` defaults | index.html:18830-18837 | `Insumos_Categorias` / `Insumos_Unidades` (fetch en :18848) | Ya migrado a tabla con default como semilla offline — patrón correcto, dejar |
| `SUPERVISOR_EMAILS` (3 fijos) | index.html:34378 | `Supervisores_Virgilio` (merge, :28148-28209) | Los fijos no se pueden revocar sin deploy. Mover los 3 a la tabla con flag `fijo`. **Bajo/bajo**. Ídem `RECIPIENT_EMAIL` hardcodeado en la Edge Fn `admin-login-otp` (CLAUDE.md) |
| Anon key Virgilio ×6 archivos | index.html:4084 · sw.js:15 · fichada-config.js:14 · fichadas-monitor.html:263 · recepcion.js:29 · productividad.html:493 | — | GUIA:369 dice "3 archivos" → **desactualizada y peligrosa para una rotación**. Config compartida + corregir guía. **Bajo/bajo** |
| Chat id Telegram `-1004379879565` | default de `tg_enqueue` + `sql/telegram_alertas.sql` (3 usos) | podría vivir en `Stock_Config`/Vault | **Bajo/bajo** |
| Legajos test `0`/`1` excluidos ad-hoc | front (múltiples) + `generar_inconsistencias` + recetas SQL (GUIA:7196, 7538) | `Empleados.tipo` ya existe | Marcar `Empleados.tipo='test'` y filtrar por eso en una función/vista, no por literales. **Bajo/bajo** |
| Metas premio picking/armado (1.6/0.7 m³/h) | localStorage `prod_metas` (GUIA:12b) | ninguna | Por dispositivo: otra pantalla admin ve otras metas. Mover a `Stock_Config`. **Bajo/bajo** |
| Regla "L final = reenvasado x24" (`pkStripL`) y alias " LOKE" | index.html:7378-7384 | ninguna | Reglas de normalización de negocio solo-front; si un cron/SQL cruza esos códigos no las aplica. Llevarlas a `norm_cod`/vistas. **Bajo/medio** |

---

## Balde 4 — Normalizaciones y claves inconsistentes entre tablas

> ⚠ **Regla del dueño (2026-08-28), manda sobre lo que sigue:** para los códigos de dos
> dígitos, **el código ES con cero adelante** (`026`, `029`, `034`, `043`…) — "lo corregí
> mil veces". Verificado: stock, capacidad, pedidos y OCs ya guardan la forma con cero, y
> **no hay saldos partidos** entre variantes; las únicas tablas peladas son
> `Articulos_Cajas` y `proyeccion_madre` (espejo del motor LK). Consecuencia: cualquier
> normalización de escritura o backfill debe canonizar **HACIA la forma con cero**, nunca
> sacándolo. Los normalizadores que quitan ceros (`_ocgNorm`, `canon_cod`, `norm_cod`)
> valen solo para COMPARAR, no para guardar ni mostrar.

### 4.1 `cod_art`: ceros a la izquierda (el peor)
- **La misma entidad** se guarda como `27` / `027` / `0027` según la fuente (E.Madre, Pedidos Talleristas, carga manual) — index.html:10204-10208. Consecuencia: saldo partido en `Movimientos_Stock` (incidente que motivó `sql/canon_cod_art.sql:4-7`).
- **Mitigaciones actuales, fragmentadas**: trigger `fn_canon_cod_art` solo en `Movimientos_Stock` y **excluyendo** los tipos del pipeline (canon_cod_art.sql:36); funciones SQL `norm_cod` y `canon_cod` (dos, similares); en el front **7 normalizadores**: `_ocgNorm` (index.html:11294, ~140 usos; duplicado en recepcion.js:1165), `_stkNormCod` (14557, además quita espacios internos — ¡regla distinta!), `_cpNorm` (20997), `codBase` (7384), `codCanon`/`_padCod` (10231/10217), `_equivNorm`, `pkStripL`.
- **Propuesta**: (a) canonizar en el WRITE en todas las tablas con cod (trigger genérico con `canon_cod`), (b) backfill one-shot por tabla (con backup, protocolo CLAUDE.md), (c) el front deja de normalizar para comparar y solo canoniza display. **Esfuerzo medio-alto · riesgo medio** (el índice de dedup del pipeline depende del formato actual — canon_cod_art.sql:13-16: resolver primero esa "Capa 1b" pendiente).

### 4.2 Sufijo de empresa " LK"/" CH"/" LOKE"
- El stock y la planimetría guardan `438E LK`/`438E CH`; pedido/faltantes/facturación usan el pelado `438E` (`codBase`, index.html:7379-7384). La misma entidad con 2 claves según la tabla → todo cruce stock↔pedido pasa por `codBase()` en el front y por lógica replicada en las vistas de faltante. **Propuesta**: columna `empresa` separada en `Movimientos_Stock`/`Racks_*` en lugar de sufijo embebido en la clave (migración con vista de compatibilidad). **Alto/alto** — alternativa barata: función SQL `cod_base(text)` + usarla en TODAS las vistas para que la regla exista una sola vez.

> ⚠ **Corrección 2026-08-28 (verificado contra datos reales).** Dos afirmaciones de §4.3 y
> §4.4 estaban mal: **(a)** el problema del `.0` **ya no existe** — 0 de 11.954 filas de
> `PPP_Base_Pedidos`; lo arreglaron upstream el Apps Script y el importador del front, así
> que el doble-query de `index.html:14022` es código muerto probado. **(b)** "toda vista
> hace `upper(btrim(tanda))`" es falso: solo `vista_tanda_m3`; `ppp_etapa_tanda` compara
> case-sensitive. Además ya existía un trigger `fn_norm_tanda` (recorta bordes, no
> uppercasea). **Lo que sí es un bug real y medible**: 19 filas de `PPP_Base_Pedidos` tienen
> `articulo` en minúscula (943e, 948e, 942e, 838e, 580e, 574e) y el front, que consulta con
> `codBase()` en mayúscula, **no las ve** — 19 NPs y 36 cajas invisibles en "Cajas pedidas".
> Propuesta de DDL (sin tocar datos) en `sql/PROPUESTA_norm_ppp_np_tanda_articulo.sql`.

### 4.3 NP como texto con basura `.0`
- `PPP_Base_Pedidos.pedido` llega a veces como `97754.0` (float del Sheet): el front consulta `np` **y** `np+".0"` (index.html:13937) y limpia con `replace(/\.0+$/,"")` en ≥3 lugares (14515, 14600, 14605). `Facturacion_NP.np` y `Entregas_Virgilio.np` guardan el limpio. Misma entidad, dos formatos según tabla.
- **Propuesta**: limpiar en el sync (Apps Script `_pppMapBasePedidos_` o trigger BEFORE INSERT en `PPP_Base_Pedidos`: `regexp_replace(pedido,'\.0+$','')`). **Bajo/bajo** — elimina el doble-query y los strips del front.

### 4.4 Tanda: mayúsculas/minúsculas
- `Registros.texto` siempre `.trim().toUpperCase()` (GUIA:6953) pero las tablas PPP traen la tanda tal cual el Sheet → toda vista/join hace `upper(btrim(tanda))` (vista_tanda_m3, sync_ppp_entregados_meta, recetas §11) y hasta hay índice funcional `upper(tanda)`. **Propuesta**: normalizar tanda en el sync de PPP (mismo lugar que 4.3). **Bajo/bajo**.

### 4.5 Fechas como texto
- `Entregas_Virgilio.fecha_salida` es `text` (GUIA:7018), "Entregas Tallerista Virgilio" guarda `Fecha` texto + `created_at` (recepcion.js:1807), tablas PPP con fechas texto del Sheet. Ya mordió: bug TZ de `new Date("YYYY-MM-DD")` corrió fechas un día (GUIA:345-346). **Propuesta**: tipar `date` en las tablas propias (Entregas_Virgilio primero); PPP puede quedar texto por ser espejo, pero las vistas deberían castear una sola vez. **Medio/medio**.

### 4.6 Nombres de columna para la misma clave
- El código de artículo se llama `cod_art` (Movimientos_Stock, Entregas_Virgilio), `cod` (OC_Maximos, precios_venta, Faltantes_Notas), `codigo` (Volumen_Articulos), `articulo` (PPP_Base_Pedidos), `Cod_Art` (Articulos_Cajas, X Tallerista); el cliente es `cod_cliente`/`cod`; el NP es `np`/`pedido`. No rompe, pero encarece cada vista nueva. **Propuesta**: convención para tablas nuevas + renombrar solo al tocar cada tabla por otra razón. **Bajo/bajo**.

---

## Plan de normalización sugerido (orden de ataque)

1. **Semana 1 (todo bajo riesgo)**: ~~TOP-6 (docs/SQL stale)~~ ✅ (refs a `PPP_Pedidos_Entregados` marcadas obsoletas en `ppp_supabase.sql`, `MIGRACION-SUPABASE-PPP.md`, `PLAN-INTEGRACION-ISIS-5547.md`), ~~TOP-10 (key en 1 archivo + corregir GUIA)~~ ✅ (GUIA actualizada: 6 archivos con la anon key), ~~TOP-5 (`EQUIV_FAMILIAS` del front)~~ ✅ (v11.101/v11.102: loader desde tabla `Equivalencias_Familia` con semilla conservada como fallback offline), 4.3/4.4 (limpiar np/tanda en el sync), legajos test a `Empleados.tipo`, metas a `Stock_Config`.
2. **Semanas 2-3**: TOP-8 (cron de precios), ~~TOP-4 (`empresa_de_np` + `Codigos_Duales` en SQL)~~ ✅, TOP-7 (unificar sync PPP en pull server-side), ~~fichadas a trigger server-side~~ ✅ (Phase 1+2: `trg_fichadas_virgilio_espejo` + `trg_registros_fichada_espejo`; front ya no escribe en `Fichadas_Historico`), ~~tabla `Sync_Estado` con alerta~~ ✅ (`watchdog_syncs_externos` lee `cron.job_run_details`).
3. **Mes 2**: TOP-2 (canon de `cod_art` en el write + backfill, respetando el protocolo de backups del CLAUDE.md), TOP-3 (`Planimetria`/`Gondola_Celdas` única), 1.11 (zona).
4. **Trimestre**: TOP-1 (tabla maestra `Articulos` absorbiendo descripción/marca/uxb-por-contexto/volumen; las vistas `vista_nombres/marca/uxb_articulo` pasan a leerla — el front no cambia), TOP-9 (faltantes), 4.2 (columna empresa vs sufijo — la más invasiva, dejarla última y con vista de compatibilidad).

Regla vigente que el plan respeta (CLAUDE.md): preguntar backend vs front antes de implementar, lógica de negocio en backend con el front como optimización, backup antes de tocar datos, y nunca corregir datos sin permiso explícito.
