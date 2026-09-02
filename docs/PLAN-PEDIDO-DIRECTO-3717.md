# Plan Pedido web directo a Virgilio — Idea 3717

**Idea:** 3717 (propuesta de un empleado, registrada 2026-09-02)  
**Fecha del plan:** 2026-09-02 (borrador) → 2026-09-02 (final, tras revisión de 3 críticos: operación, datos, técnica — 42 objeciones, ver §13)  
**Estado:** plan — **nada ejecutado** (ni tablas, ni syncs, ni Apps Script, ni crons, ni mail 12:30)  
**Relación con 5547:** reemplaza P2/P3/P5 y las piezas 1-3 y 6 del plan ISIS; deja en pie P1 (redefinido como "pedido armado listo para facturar") y P4. Ver §6.4.  
**Ideas cruzadas:** 4529/9949 (`lk_pedidos_match`), 1655 (ventana de Base), 8606 (variante correcta al pickear), 7411 (datos duplicados), 9073 (portal privado app.loekemeyer.com), 2536 (inventario de repos), 9670/1817 (blindaje canon: runbook de migraciones + `tests/anon-writes.cjs`).

> **Marco fijado por el dueño (2026-09-02):** (a) la PPP de Virgilio deja de ser espejo del Excel/Sheet y pasa a nutrirse de los pedidos de la página LK, programando en Virgilio; (b) por ahora **no se toca nada con implicancias** — lo único autorizado antes de terminar la documentación es el botón "descargar Excel" en Facturación (**Paso 0**, §11); (c) primero documentar todo, después construir; (d) despliegue en una **copia del repo** que convive con el actual hasta que ande (§12).

> **Fuentes:** dossier de 7 lectores (ppp, np, fac, lk, isis, puente, métricas) sobre los repos `Produccion-Virgilio` y `pagina-LK-copia` y las bases Virgilio `hrxfctzncixxqmpfhskv` / LK `kwkclwhmoygunqmlegrg` (sólo SELECT), más la revisión de 3 críticos. Todo lo que un crítico afirmó y cambia el diseño se **re-verificó hoy contra la base** (regla de empresa, duplicados de `Entregas_Virgilio`, policies de `orders`, opciones del FDW, horarios de edición y de tilde, observaciones de la PPP, `Codigos_ISIS_Map`). Lo que no se pudo verificar dice **a verificar**.

> **Qué cambió respecto del borrador (resumen):** provisoria de 9 dígitos y regla de empresa por **primer dígito** (fase 1); **dos estados** `importada`/`facturada` — `Facturacion_NP` se escribe recién con la factura real, en el mismo tilde de hoy; **editable hasta que tenga tanda**; export **dedup por (np, cod_art)**; índice único **parcial**; push **idempotente por fila** con `connect_timeout`/`batch_size`/advisory lock; filtro del piloto **en los dos lados**; `PPP_Entregados_Meta` alimentada desde Virgilio como **prerrequisito** del piloto; **archivado** de filas web; **cuarentena** de filas del Sheet que ya son un tramo web; `np_rename_log` + `deshacer_np_isis`; renombre por **regexp** (no por lista de opciones); export **complementario con identidad propia**; trigger fns **`SECURITY DEFINER` + `REVOKE`**; `condicion_pago_code` vía `lk_pedidos_match`; Paso 0 con archivo `PRUEBA_NO_IMPORTAR_*` y botón oculto; tests en `run.sh`.

---

## 1. Objetivo y qué cambia

**En 5 líneas.** El pedido web nace en `orders` (LK) y hoy espera hasta 24 h al mail de las 12:30, la operadora lo importa en ISIS, ISIS lo numera, baja dos reportes al Excel PPP, el Apps Script lo empuja a Supabase Virgilio y recién ahí el depósito lo ve. La idea: LK empuja el pedido a Virgilio en minutos, Virgilio lo parte de a 18 líneas como hoy, lo programa, lo pickea y lo arma **sin que ISIS exista todavía**, y cuando está armado la operadora baja desde Facturación un Excel **idéntico al de las 12:30 pero con lo armado** y lo importa en ISIS sólo para facturar. ISIS deja de ser la entrada del circuito y pasa a ser la salida. El único dato que ISIS sigue generando y Virgilio necesita es el **número de NP**, que ahora llega *después* de armar y *antes* de facturar (§3).

### 1.1 Hoy vs propuesto, paso a paso

| # | Paso | Hoy (quién) | Propuesto (quién) | Queda / desaparece |
|---|---|---|---|---|
| 1 | Pedido web | Cliente / admin "Pedir para" / cotizador → `submit_order_fast` + `sheets_payload` (script.js:7038-7318) | Igual | Queda |
| 2 | Espera al cron 12:30 (`procesar-pedidos-web`, mediana 12,9 h, p90 22,7 h) | Automático | Push LK→Virgilio cada 5 min (`sync_pedidos_web_virgilio()`) | **Desaparece** la espera |
| 3 | Mail con Excel XML 2003 a ventas@ (`procesar-pedidos-db`) | Automático | Sólo para clientes **fuera del piloto**, con el filtro del piloto **también en la Edge Fn** (§6.2); al final se apaga | Desaparece al cutover |
| 4 | Importar Excel en ISIS → ISIS numera NP | Operadora (mañana) | Se mueve al paso 12 | Se mueve |
| 5 | Bajar 2 reportes ISIS → Excel "AAA PPP Vigente" → Sheet → Apps Script → `PPP_*` (reemplazo total) | Operadora + Apps Script | `aplicar_pedidos_web()` (cron Virgilio) inserta cabecera + líneas con NP provisoria y `origen='web'` | **Desaparece para lo web**; para KRIKOS Chef / carga directa en ISIS / clientes nuevos (~9 % de NP, §4.10) **queda hasta la fase 9** — la operadora sigue bajando los 2 reportes todos los días mientras exista una NP no web |
| 6 | Partición ≥18 líneas | Edge Fn LK (`processOrders`) | Función SQL en Virgilio, mismo algoritmo (§4.3) | Queda (cambia de lado) |
| 7 | Programar tanda / fecha_entrega / op / observaciones | Operadora en el Excel PPP (`PPP_READONLY=true`, index.html:28019) | Operadora en Virgilio, RPC `ppp_programar()` (§4.5) | Cambia de lugar |
| 8 | Picking (EP/TP/PKC) + armado (AP/TAP/TAL) → `Entregas_Virgilio` | Operarios | Igual, sobre la NP provisoria | Queda |
| 9 | Facturación: tilde por NP → `Facturacion_NP` (post-factura) | Operadora administrativa | **Igual**: el tilde sigue siendo post-factura y sigue escribiendo `Facturacion_NP` — pero para NP web recién es posible **después** de los pasos 11-12 (§4.7) | Queda |
| 10 | Ajustar a mano en ISIS la NP por lo entregado (51 % de NP con faltante) | Operadora | Desaparece: el Excel ya lleva `cajas_entregadas` | **Desaparece** |
| 11 | Descargar Excel de NP armadas (checklist en Facturación) | — | Botón en Facturación (**Paso 0**, §11) | Nuevo |
| 12 | Importar en ISIS → NP real → tipear la primera NP del lote en Virgilio → `confirmar_np_isis()` renombra (estado `importada`) → facturar en ISIS → tilde (paso 9) | — | Operadora, **en el mismo turno, antes de la carga del camión** (SLA §3.6) | Nuevo |
| 13 | CCN / remitos / cobranzas / WhatsApp / cruce facturas | Automático + operadora | Igual, ya con NP real (la carga de un tramo con provisoria se bloquea en la app, §3.6) | Queda sin cambios |

---

## 2. Proceso actual verificado (hechos duros)

Detalle en `docs/PLAN-PEDIDO-DIRECTO-3717.CONTEXTO.md` (anexo con los hechos relevados y el extracto de la Edge Fn); acá lo que el plan usa. Lo marcado **(re-verificado)** se corrió hoy tras la revisión.

- **Entrada:** `orders.sheets_payload` (jsonb) lo escribe el **navegador** después del RPC (`script.js:7244-7253`, fire-and-forget). 90 días: 568 pedidos, 0 sin payload, 0 con payload ≠ `order_items`. `orders` no tiene `updated_at`; `status` es 100 % `'pendiente'` (1236/1236); **no existe cancelación** de pedido web; `edit_order_fast` bloquea con `FOR UPDATE` + RAISE si `enviado_a_compras_at` no es null. **(re-verificado)** Policies vivas en `orders`: `orders_delete_own` (`auth.uid() = auth_user_id`, DELETE, sin mirar sellos), `orders_update_own_sheets` (UPDATE, idem), `orders_admin_*`; triggers: sólo `orders_notify_whatsapp` (AFTER INSERT) y `trg_fill_order_customer_code`. **(re-verificado)** Las 7 ediciones (`mode='edit'`) de 90 días se hicieron entre **1 min y 19 h** después del pedido (18:01, 19:01, 19:36, 19:37, 09:59 del día siguiente, 16:06, 16:16): sólo 2 de 7 caen dentro de 5 min.
- **Cron LK** `procesar-pedidos-web` `30 15 * * *` UTC (12:30 ART) → `enviar_pedidos_main()` → `net.http_post` → Edge Fn **`procesar-pedidos-db`** (v9). Retry `2-59/6 15,16`. Log `procesar_pedidos_log`: sólo `company='Lk'` (154 corridas). **Chef no pasa por acá**: si el proyecto Chef (`nkhzocgdpwtgrmwleihr`) tiene su propio cron/Edge Fn, no está en ningún repo ni es consultable desde acá (**a verificar**, precondición de la fase 8).
- **Regla 18** (`processOrders`, `procesar-pedidos-db.ts:6-17`): clave `N° Pedido|Sucursal|Cliente`; ≥18 líneas → bloques de ≤18 (los grandes primero, luego los chicos enteros); `N_Pedido` correlativo 1..N del archivo, **no** es la NP. Cuenta ítems del payload, no artículos distintos (por eso hay NP de 19 líneas: 98293, 98501).
- **Excel:** XML Spreadsheet 2003, hoja 1 sin encabezado, 12 columnas `fecha, N_Pedido, cliente, vend, articulo, cajas, uni, sucursal, leyenda2, condPago, pctDto, numOC`; hoja 2 "Resumen". Tipos de celda: `Number` si `/^-?\d+(\.\d+)?$/` y no empieza con `0` (salvo `0.`), si no `String`; vacío → `<Cell/>`. `numOC` viajó vacío en 1.013/1.013 pedidos desde marzo; `pctDto` es fijo `"2% Descuento Web"`. **(re-verificado)** `condPago` viaja como **código** y `sheets_payload.condicion_pago_code` lo tiene en 100 % de los pedidos de 90 días (8: 387, 9: 54, 18: 50, 11: 20, 3: 15, 10: 15, 1: 11, 13: 8, 12: 5, 14: 3, 2: 2); `v_pedidos_match`/`lk_pedidos_match` **no** lo llevan (sólo `metodo_pago` texto: "Pago Contado: 25% Dto" 488, "Contado" 220, "Prefiero no decidir ahora" 88, null 42, "CHECK:10010:S+ 90…" 14, "Echeq 120 dias" 10…).
- **ISIS numera al importar:** correlativo por empresa (LK 9xxxx, Chef 4xxxx), contiguo y en orden `N_Pedido` dentro del lote (3/3 lotes verificados), intercalado con KRIKOS/COT/manuales entre lotes; 50 huecos en 750 (LK). `fecha_recep` de la NP = fecha del pedido web. **ISIS no devuelve la NP** por ningún canal; la factura parseada tampoco la lleva (0/415). El reporte "Base Datos Pedidos" trae las cajas que ISIS tiene en el pedido (con 3717: las **entregadas** que llevó el Excel).
- **Sheet → Supabase:** Excel VBA → Apps Script `handleCargaPPPSync_` (fuera del repo) → Sheet → `pushPPPToSupabase_` (`apps-script/sync-ppp-supabase.gs:61-108`) → `DELETE ?id=gte.0` + INSERT lotes de 500 con **service_role**, **dos requests REST sin transacción**, sin retry. El pull server-side (`sync_ppp_base_pedidos()`) **no existe en la base**. Sin `UNIQUE(np)` (hoy 0 duplicados en 183, pero la hoja los puede traer y se toleran con `max()`), `id` cambia en cada push. El reemplazo total es también la **purga**: la operadora saca del Excel las NP entregadas (hoy 63 NP ya facturadas siguen en Prog porque el Excel tarda en depurarlas) y Base arranca el 01/07 (ventana ~2 meses, idea 1655). `PPP_Programacion_Diaria.observaciones` trae **instrucciones comerciales** que la operadora tipea en ISIS: `FACTURAR EN SEPTIEMBRE`, `11:00Hs`, `PEDIDO EXPO`, `OC 032112` **(re-verificado)**.
- **Virgilio:** `PPP_READONLY=true` (index.html:28019): la app no escribe tanda/fecha; programa la operadora en el Excel local. Picking/armado leen `PPP_Base_Pedidos` por NP; armado escribe `Entregas_Virgilio` (`compTerminar`, index.html:9896); Facturación (`facTickNP`, :34004-34121) upserta `Facturacion_NP` (trigger `validar_np_armada` exige filas en `Entregas_Virgilio`) y el front drena stock (`stockSalidaFacturadoNP` :22668). La factura se hace **a mano en ISIS** antes del tilde. **(re-verificado)** El tilde se hace a las 16-17 h (517 de 748 NP en 60 días); tilde → primer CCN: **p10 = 3,5 h, 51 NP cargadas dentro de las 2 h del tilde**; 0 NP con CCN antes del tilde. El cierre de jornada (`generateFacturacionPDF` :34303, `facBtnCierre` :33687, `Facturacion_Cierres` con `fecha_reparto = cierre+1`) y "Armar ruta" (`openRuteo` :27909) leen `Facturacion_NP` con `cierre_id null`.
- **`Entregas_Virgilio` tiene la misma línea armada dos veces** **(re-verificado)**: en 60 días, 71 pares `(np, cod_art)` repetidos en 28 NP, **todas en `Facturacion_NP`**; 61 con cantidades idénticas, 59 con `sum(cajas_entregadas) > cajas_pedidas`, 71/71 con `max(cajas_entregadas) ≤ cajas_pedidas`; 13 en tandas distintas (re-armado, p.ej. 98490 en D47C y D54C) y el resto misma tanda con `fecha_salida` en dos formatos (`'2026-09-02 00:00:00'` vs `'2026-09-02'`, que `trg_entregas_virgilio_dedup` no ve como iguales). Hoy es inocuo porque ISIS factura por lo pedido; con 3717 es **bloqueante** para el export (§4.6, §11.1).
- **Triggers que salen de Virgilio con la NP** **(re-verificado)**: `trg_virgilio_entrega_to_formato` es **AFTER INSERT** en `Entregas_Virgilio` (cod 288 Torres y Liva / 2533 OSA, `cajas_entregadas > 0`) → `net.http_post` a la Edge Fn LK `virgilio-entrega-sync` con `ev_id, np, cod_art, cajas_entregadas, tanda`; no dispara en UPDATE. `trigger_actualizar_saldo_stock` en `Movimientos_Stock` es **AFTER INSERT OR UPDATE sin `OF`**: cualquier UPDATE de `ref` recalcula el saldo (agregado sobre toda la tabla por fila).
- **Eventos con la NP embebida en `texto`** (60 días, legajos reales) **(re-verificado)**: TAL 941, CCN 695, CCR 693, AUB 373, CRN 292, CP 184, **FCO 69**, NPD 36, FAL 2, FSS 1. FCO (override de facturación) ocurre **antes** del tilde y el borrador no lo listaba.
- **Ya existe un puente LK→Virgilio:** FDW `virgilio_db` (LK) con rol `lk_ppp_reader`, que escribe `lk_pedidos_match` (cada 15 min, 555/555 corridas ok en 7 días, 6,5 s por corrida) y `proyeccion_madre`. **(re-verificado)** Opciones del server: `host, port, dbname, sslmode=require` — **sin `connect_timeout` ni `batch_size`**. El rol puede ejecutar **238 funciones** de `public` por herencia de `PUBLIC`. Virgilio no tiene FDW hacia LK. Chef: `chef_db` (`chef_orders`: `id, created_at, customer_id, status, sheets_payload, payment_method`), sólo SELECT y sin confirmar (el bloque Chef del match vive en un `exception … raise notice`); 50 de las 57 filas chef de `lk_pedidos_match` vienen **sin `sucursal_entrega`**.
- **`Facturacion_NP` tiene CRUD abierto a `anon`** (9 policies: `insert_anon`, `update_anon`, `delete_anon`, …) **(re-verificado)**. `Entregas_Virgilio` (`ent_insert` anon+auth) y `Registros_Produccion_Virgilio` (`insert_all` anon+auth) reciben INSERT del operario con la anon key: cualquier trigger fn nueva sobre esas tablas corre como `anon` salvo que sea `SECURITY DEFINER` (`docs/RIESGO-ESTRUCTURAL-CANON.md`, incidente 28/08).
- **`sync_ppp_entregados_meta()` hace `TRUNCATE`** + parse del CSV del Sheet "PPP Pedidos Entregados 2026" **(re-verificado)**, que se alimenta del Excel PPP local: una NP que no está en ese Excel **nunca** llega a `PPP_Entregados_Meta`.
- **Hallazgo colateral (no es de esta idea):** `sincronizar_ppp()` de LK falla todos los días desde el 26/08 (`relation "public.PPP_Pedidos_Entregados" does not exist`); las `ppp_*` de LK y el dashboard `gv_ppp_*` están congelados. Reportado, no tocado.

---

## 3. La decisión central: identidad de la NP

Hoy la NP existe **antes** de programar. Con 3717 existe **después** de armar. Todo Virgilio cuelga de ese número: `text` en 21 tablas y 34 vistas, PK en 9 tablas, ~4.270 eventos con la NP embebida en `texto`, `Movimientos_Stock.ref = 'tanda|NP'`, y la **empresa se deduce del número en ~20 lugares** (`empresaDeNp` index.html:7326 y `pkNpEsLoeke` :7990 `parseInt > 90000 → LK else CH`, `empresa_de_np()` `::bigint > 90000`, `cob_empresa_np()`, `trg_normalizar_empresa_stock`, `vista_faltante_real/demanda`, `vista_np_factura`, `vista_np_sucursal`, LK `sincronizar_ppp`/`gv_ppp_*`).

**Frontera temporal (60 días):** 0 NP con CCN antes del tilde; 679/687 tenían TAL antes del tilde; 2.927/2.961 etiquetas de lío y 83/110 remitos de armado se imprimieron antes. **Pero la frontera es corta:** p10 tilde→CCN = 3,5 h y 51 NP se cargan dentro de las 2 h. Por eso el renombre no puede quedar "para la mañana siguiente": §3.6 fija el SLA y la app bloquea la carga de un tramo con provisoria.

### 3.1 Opciones

| Opción | Qué es | Costo concreto | Veredicto |
|---|---|---|---|
| **A — provisoria renombrada al importar** | Virgilio arma con un id provisorio; al importar el Excel, una RPC transaccional lo renombra a la NP de ISIS en todo lo anterior | 1 RPC `confirmar_np_isis()` que toca ≈30 filas por NP: `Entregas_Virgilio.np`, `texto` de `Registros_Produccion_Virgilio` **por regexp** (TAL/AUB/NPD/FAL/CP/**FCO**/**PPG** y cualquier opción futura, §3.5), `Etiquetas_Lio`, `Impresion_NP` (PK), `Faltantes_Tareas`, `Correcciones_Pedido` (PK), `Movimientos_Stock.ref` (`'NP'`, `'NP|CP'`), `wa_np_snapshot` (PK), `envio_programacion_log`, `PPP_*`, `np_map`; todo queda en `np_rename_log` (§3.7). Ningún trigger de `Registros_Produccion_Virgilio` dispara en UPDATE (el único, `trg_pkc_reconciliar_stock`, está deshabilitado). `Entregas_Virgilio` no tiene policy UPDATE para anon → la RPC es `SECURITY DEFINER`. Papel impreso antes (remito de armado, etiqueta ZPL) queda con la provisoria: se acepta o se reimprime. Lo que **salió de Virgilio** con la provisoria (`pa_entregas` en LK, §3.5) se re-postea | **Recomendada** |
| B — provisoria permanente + `np_isis` aparte | La provisoria queda para siempre; la NP de ISIS es una columna más | Reescribir los ~20 puntos de "empresa por número", `coalesce(np_isis, np)` en ~10 vistas y 5 funciones que cruzan la frontera del tilde, doble búsqueda en Consultar NP / Cobranzas / Completar pedido, exponer `np_isis` a LK por FDW, doble identidad en pantalla y papel para siempre | No |
| C — predecir / reservar la numeración de ISIS | Adivinar la NP antes de importar | Inviable como predicción: la base del lote sólo se conoce al importar, la secuencia es compartida con KRIKOS/COT/manuales/anuladas y Chef es otra serie. **Viable como mecanismo de mapeo por lote** (§3.4) | Sólo como mecanismo de A |

### 3.2 Formato de la provisoria y regla de empresa (cambia respecto del borrador)

El borrador proponía `<E> + order_id(6) + parte(1)` (8 dígitos) y afirmaba "cero cambios" en los ~20 puntos de empresa-por-número. **Era falso para Chef**: `40013361 > 90000` → `empresa_de_np()`, `empresaDeNp` y `pkNpEsLoeke` la clasifican **LK** (sólo `cob_empresa_np`, `vista_np_sucursal` y `sincronizar_ppp` de LK miran el primer dígito). El picking de duales 437E/438E/439E/809E de una NP Chef iría a la góndola LK, `pkCodEmpresa` armaría `437E LK` y `trg_normalizar_empresa_stock` marcaría el drenaje como LK. No hay atajo por longitud (ninguna provisoria con `order_id` de 6 dígitos queda por debajo de 90.000), así que **la regla se reescribe en la fase 1**, antes de cualquier provisoria:

```
Regla nueva (fase 1, un cambio por punto):  primer dígito '9' → LK ; '4' → CH ; otro → '' / NULL
  empresa_de_np()      : CASE left(digits,1) WHEN '9' THEN 'LK' WHEN '4' THEN 'CH' END
  empresaDeNp (7326)   : d[0] === '9' ? 'LK' : d[0] === '4' ? 'CH' : ''
  pkNpEsLoeke (7990)   : d[0] === '9'
```

**(re-verificado)** Es equivalente a la regla actual sobre **todas** las NP existentes: `Facturacion_NP` 987 con primer dígito 9 y 175 con 4 (0 filas donde `> 90000` y `left(np,1)='9'` difieran); `PPP_Base_Pedidos` 8.344 / 1.054; las 20 NP del simulador (`999…`, 11 dígitos) siguen siendo LK. Test `tests/emp-np.cjs` existente se amplía con `9xxxxxxxx` y `4xxxxxxxx`. Los otros puntos (`cob_empresa_np`, `vista_np_sucursal`, `left(np,1)` en LK) ya son por primer dígito y no se tocan. `sql/empresa_de_np.sql` se actualiza.

Formato final, **numérico, prefijo de empresa, 9 dígitos, parte de 2 dígitos** (así también hay lugar para los complementos de §4.8):

```
NP provisoria = <E> + order_id (6 dígitos, cero a la izquierda) + parte (2 dígitos)
  LK   → 9 + 001336 + 01 = 900133601   (9 dígitos; ISIS usa 5: 98684; simulador 11: 9990…)
  Chef → 4 + 001336 + 01 = 400133601
  parte 01..89 = tramos de la partición 18 ; 91..99 = exports complementarios (§4.8)
```

- Se distingue de una NP de ISIS por longitud (`^\d{9}$` vs `^\d{5}$`). `order_id` tope 999.999 (hoy 1.336). Partes: máximo real por pedido 7 (120 líneas / 18); 89 de margen.
- Consumidores numéricos a ajustar (1 línea cada uno): `vista_np_faltantes_secuencia` (excluir `^\d{9}$`), `pppFindNpPdf` (sin PDF de ISIS para una provisoria: mostrar "sin PDF"), `_pppNpsCompact` (colapsa rangos; inocuo). En pantalla y papel la provisoria se muestra con prefijo visual **"NPV "** (riesgo 2).
- `order_id` choca entre portales LK y Chef → el prefijo es obligatorio y además va **columna `empresa` explícita** en las tablas nuevas (§4.1).

### 3.3 Pre-partición determinística (requisito de A)

El renombre sólo es 1:1 si Virgilio **pre-parte** el pedido en tramos de ≤18 líneas con el mismo algoritmo que `processOrders` y trata cada tramo como unidad de programación/armado (como hoy: 256 de 801 NP tienen 18-19 líneas, 198 grupos partidos). Si el armador viera el pedido entero (hasta 120 líneas), una provisoria → N NP de ISIS y `Entregas_Virgilio`/TAL no se podrían repartir.

### 3.4 Mecanismo de mapeo: "primera NP del lote" + cuarentena del Sheet

Verificado 3/3 lotes: `NP_i = primera_NP + (N_Pedido_i − 1)`. Flujo: la operadora importa el Excel en ISIS, mira la primera NP que ISIS asignó, la tipea en Virgilio (campo en el modal de export, §11.4); `confirmar_np_isis(p_export_id, p_np_inicial)` valida que la cantidad de NP generadas coincida con `cant_np` del export y renombra en una transacción. **Un Excel por empresa** (ISIS LK y Chef son series distintas → dos "primera NP").

**Ventana de doble existencia (objeción OP-2), resuelta con cuarentena, no con rechazo.** Si la operadora importa en ISIS y baja los reportes al Excel PPP **antes** de confirmar en Virgilio (o `confirmar_np_isis` falla), el push del Sheet trae la NP real `98690` con `origen='sheet'`, `tanda=''`, y el reporte "Base" trae las cajas **entregadas** que llevó el Excel. El borrador hacía que `confirmar_np_isis` rechazara ("ninguna NP resultante debe existir") → lote trabado con las dos identidades vivas. Diseño final:

- `ppp_cuarentena_sheet` (BEFORE INSERT, `SECURITY DEFINER`, §6.1): una fila `origen='sheet'` de **Prog** cuya `(cod, fecha_recep)` coincide con un tramo de `np_map` en estado `exportada` (todavía sin `np_isis`) **no entra a `PPP_Programacion_Diaria`**: se guarda en `ppp_cuarentena_sheet(np, cod, fecha_recep, tanda, m3, …, visto_at)` y `RETURN NULL`. Las filas de **Base** con `pedido` en cuarentena van a `ppp_cuarentena_sheet_lineas`. Si la NP ya figura en `np_map.np_isis` (post-renombre), `RETURN NULL` directo (era el `ppp_ignora_np_ya_web` del borrador).
- `confirmar_np_isis` **verifica y absorbe**: compara las líneas en cuarentena `(articulo, cajas)` contra `Facturacion_Export_Lineas` del tramo (son exactamente las que ISIS recibió, coincidencia exacta esperada), renombra, borra la cuarentena en la misma transacción y anota `np_map.verificado_sheet_at`. Si hay cuarentena y la operadora todavía no tipeó, el modal **sugiere** la primera NP a partir de ella (auto-completar con confirmación humana). Si la comparación no coincide → no renombra ese tramo, Telegram, y queda para revisión.
- Automatizar del todo depende de P3 (que ISIS devuelva NP↔referencia; pregunta H6).

### 3.5 Qué cambia en cada consumidor con A

| Consumidor | Cambio |
|---|---|
| Picking / armado / líos / etiquetas / remito de armado / Cola de impresión | Ninguno (trabajan con `np` text; la provisoria conserva la empresa por primer dígito, §3.2). Reimpresión opcional post-renombre |
| `Registros_Produccion_Virgilio.texto` (TAL, AUB, NPD, FAL, CP, **FCO**, **PPG** nuevo, y cualquier opción futura) | Renombre por **regexp**, no por lista: `update … set texto = regexp_replace(texto, '(^|\|)' || np_prov || '(\||$)', '\1' || np_isis || '\2') where created_at >= np_map.creado_at and texto ~ ('(^|\|)' || np_prov || '(\||$)')`; conteo por `opcion` en `np_rename_log`. Idem `Movimientos_Stock.ref` |
| `Movimientos_Stock` → `trigger_actualizar_saldo_stock` | Hoy `AFTER INSERT OR UPDATE` sin `OF`: el renombre de `ref` recalcularía el saldo por fila (decenas de full scans por lote con locks sobre `stocks_carga_rapida`). Fase 1: `ALTER TRIGGER … AFTER INSERT OR UPDATE OF delta, deposito, cod_art, empresa` (**re-verificado**: `actualizar_saldo_trigger()` sólo lee esas 4 columnas) |
| `Facturacion_NP` + sus 4 triggers, `Comprobantes_ARCA`, drenaje `ref='tanda|NP'`, `wa_*`, LK `ppp_facturacion`/`trg_notify_despacho` | Ninguno: se escriben recién con la NP real y con la factura hecha, en el tilde de siempre (§4.7) |
| **`trg_virgilio_entrega_to_formato` → LK `pa_entregas` (OSA 2533 / TyL 288)** | **Faltaba en el borrador.** Dispara al armar (AFTER INSERT) con la provisoria y no re-dispara en UPDATE. `confirmar_np_isis` re-postea a `virgilio-entrega-sync` una acción `rename` por `ev_id` afectado (`{ev_id, np_old, np_new}`); la Edge Fn LK (repo PaginaLK) actualiza `pa_entregas` por el marker `[ev:id]`, ya idempotente. Los dos clientes tienen pedidos web (2533: 10, 288: 11) y entrarían al piloto → es requisito de la fase 6 |
| CCN → CCR/CRN/CRA/FSS, `vista_control_remitos`, ruteo, `Pasaje_Papeles`, cruce facturas, cobranzas, `PPP_Entregados_Meta`, PDF de ISIS, `bot_tracking_produccion` | Nacen después del tilde (SLA §3.6). Si igual alguno naciera con provisoria, el regexp los renombra; lo que salió por WhatsApp/papel no |
| `vista_np_faltantes_secuencia`, `pppFindNpPdf` | 1 línea c/u (excluir/avisar provisorias `^\d{9}$`) |
| `NP_Canceladas` | Acepta provisoria (es text); la cancelación pre-import se resuelve en §4.9 |
| `Alertas_Pedidos_Web`, `lk_pedidos_match`, `vista_np_sucursal` | Dejan de ser necesarias para lo web (`np_map` trae `order_id`, sucursal y condición). Se mantienen durante la transición para las NP `origen='sheet'` |

### 3.6 Frontera operativa y SLA (nuevo)

- **SLA:** para un tramo web, **tilde de armado → export → import en ISIS → confirmar NP → factura → tilde de facturación** ocurre **en el mismo turno y antes de cargar el camión**. Es lo que hoy ya pasa con la factura (0 CCN antes del tilde en 60 días); lo nuevo es que la operadora administrativa hace import + tipeo en el medio.
- **Guard en la app:** Carga de camión (`CCN`) sobre una NP `^\d{9}$` → la pantalla no la ofrece y muestra "NPV pendiente de ISIS". No se usa `RAISE` en trigger: un RAISE sobre un INSERT del operario con anon key envenena la cola offline (`enqueueReport` reintenta para siempre) — mismo patrón del incidente 28/08. En su lugar, trigger AFTER INSERT (`SECURITY DEFINER`) que manda Telegram si entra un CCN con provisoria; y el regexp del renombre lo corrige después.
- **Fines de semana:** un tramo armado el sábado no se exporta hasta el lunes (hoy tampoco se factura ni se carga: 0 CCN pre-tilde). El cierre de jornada avisa "N tramos web armados sin ISIS" (§4.7) para que no se olviden.

### 3.7 `np_rename_log` y `deshacer_np_isis` (nuevo — es el backup del protocolo)

`confirmar_np_isis` corre un UPDATE masivo **todos los días** sobre ~8 tablas; el protocolo del repo exige backup antes de cada UPDATE y "reversible por `np_map`" sólo valía si nadie escribía con la NP real en el medio. Diseño: la RPC escribe en la **misma transacción** `np_rename_log(export_id, np_prov, np_isis, tabla, pk_json, columna, antes, despues, at)` una fila por celda tocada; `deshacer_np_isis(p_export_id)` lo recorre al revés (y aborta si una fila ya no tiene el valor `despues`, o sea alguien escribió encima → se reporta, no se pisa). Ese log **es** el backup exigido por el protocolo; se archiva a los 90 días.

---

## 4. Arquitectura propuesta

### 4.1 Tablas nuevas y columnas (DDL esquemático)

```sql
-- Staging: 1 fila por pedido web, la escribe LK por FDW (rol lk_ppp_reader). Virgilio la consume por cron.
create table "Pedidos_Web" (
  empresa        text not null check (empresa in ('lk','chef')),
  order_id       bigint not null,
  version        int  not null default 1,          -- sube en cada re-push (edición en LK)
  items_hash     text not null,                     -- md5 de items ordenados; detecta cambios
  fecha_pedido   date not null, hora_pedido text,
  cod_cliente    text not null, razon_social text not null,
  vend           text, tipo text not null,          -- WEB | COT | KRIKOS | EXCEL (de sheets_payload.source)
  sucursal_entrega text, direccion text, barrio text, -- resueltos por LK desde customer_delivery_addresses
  condicion_pago_code text, condicion_pago text,
  leyenda2       text,                               -- "D x - LC x - PP x" ya armado por LK (statusFields) — dato comercial, no se expone (§4.13)
  num_oc         text, observaciones text, cliente_nuevo boolean, due_date date,
  items          jsonb not null,                     -- [{cod_art, cod_original, cajas, uxb}] en el orden del payload
  estado         text not null default 'nuevo',     -- nuevo | aplicado | reenviado | error | cancelado | rechazado
  np_asignadas   text[], aplicado_at timestamptz, error text,
  synced_at      timestamptz not null default now(),
  primary key (empresa, order_id)
);
-- Traza pedido ↔ tramo ↔ NP (fuente de verdad del vínculo; reemplaza el hack match_string para lo web)
create table np_map (
  empresa text not null, order_id bigint not null, parte smallint not null,   -- parte 1..89 tramos, 91..99 complementos (§4.8)
  complemento_de smallint,                          -- parte del tramo original si es complemento
  np_prov text not null unique,                     -- 900133601
  np_isis text unique,                              -- 98690 (null hasta importar)
  export_id uuid, importado_at timestamptz, verificado_sheet_at timestamptz,
  estado text not null default 'a_programar',       -- a_programar | programada | armada | exportada | importada | facturada | cancelada | archivada
  no_facturar_hasta date,                           -- "FACTURAR EN SEPTIEMBRE" (§4.5/§4.12)
  creado_at timestamptz not null default now(), actualizado_at timestamptz,
  primary key (empresa, order_id, parte)
);
create unique index np_map_np_isis_uidx on np_map(np_isis) where np_isis is not null;
-- Export a ISIS (patrón Facturacion_Cierres ↔ cierre_id)
create table "Facturacion_Export_ISIS" (
  id uuid primary key default gen_random_uuid(), empresa text not null,
  generado_at timestamptz default now(), generado_por text, cant_np int, cant_lineas int,
  np_inicial_isis text, confirmado_at timestamptz, archivo text, prueba boolean not null default false  -- Paso 0 = prueba
);
create table "Facturacion_Export_Lineas" (           -- foto exacta de lo que ISIS recibió, 1 fila por (np, cod_art) ya agregada
  export_id uuid references "Facturacion_Export_ISIS"(id), np text, n_pedido int, n_linea int,
  cod_art text, cajas numeric, uxb numeric, uni numeric, primary key (export_id, np, n_linea)
);
-- Log del renombre (backup del protocolo) y su inverso
create table np_rename_log (id bigserial primary key, export_id uuid, np_prov text, np_isis text, tabla text, pk jsonb, columna text, antes text, despues text, at timestamptz default now());
-- Cuarentena de filas del Sheet que ya son un tramo web (§3.4)
create table ppp_cuarentena_sheet (np text primary key, cod text, fecha_recep text, tanda text, m3 numeric, fila jsonb, visto_at timestamptz default now(), np_map_candidato text);
create table ppp_cuarentena_sheet_lineas (np text, articulo text, cajas numeric, cliente text, fecha text);
-- Histórico de filas web archivadas (§4.14)
create table "PPP_Historico_Web" (tabla text, np text, fila jsonb, archivado_at timestamptz default now());
-- Heartbeat del push (LK escribe now() en cada corrida aunque no haya pedidos)
create table sync_heartbeat (nombre text primary key, ultimo timestamptz not null);
-- Columnas nuevas en tablas existentes (aditivas, nullable, sin efecto en el circuito actual)
alter table "PPP_Programacion_Diaria" add column origen text not null default 'sheet', add column empresa text, add column order_id bigint, add column parte smallint;
alter table "PPP_Base_Pedidos"        add column origen text not null default 'sheet', add column uxb numeric;
alter table "Facturacion_NP"          add column isis_export_id uuid, add column isis_importada_at timestamptz;
alter table "PPP_Entregados_Meta"     add column origen text not null default 'sheet';   -- §4.7 / §6.4
-- Índice único PARCIAL: sólo las filas web (el Sheet sigue pudiendo traer duplicados "fiel a la hoja", tolerados con max())
create unique index ppp_prog_np_web_uidx on "PPP_Programacion_Diaria"(np) where origen = 'web';
-- Config de programación (dayCap/tandaCap salen de localStorage, protocolo backend)
create table ppp_config (clave text primary key, valor jsonb, actualizado_por text, actualizado_at timestamptz default now());
-- Vista segura para la pantalla de la copia (sin leyenda2 ni items)
create view v_pedidos_web_estado as select empresa, order_id, version, fecha_pedido, cod_cliente, razon_social, tipo, estado, np_asignadas, error, synced_at, aplicado_at from "Pedidos_Web";
-- Vista para que LK lea el estado de sus tramos (§4.2 pull-back) — sin datos comerciales
create view v_np_map_lk as select empresa, order_id, parte, np_prov, np_isis, estado, p.tanda, p.fecha_entrega, m.actualizado_at from np_map m left join "PPP_Programacion_Diaria" p on p.np = coalesce(m.np_isis, m.np_prov) and p.origen='web';
```

**Del lado LK:**
```sql
alter table orders add column enviado_a_virgilio_at timestamptz, add column cancelado_at timestamptz, add column version_virgilio int not null default 1, add column canal text;  -- canal: 'virgilio' | 'compras' (quién lo tomó)
create table pedidos_web_piloto (cod_cliente text primary key, empresa text not null default 'lk', desde timestamptz default now(), nota text);
create table pedidos_web_estado (empresa text, order_id bigint, parte smallint, np_prov text, np_isis text, estado text, tanda text, fecha_entrega text, synced_at timestamptz, primary key (empresa, order_id, parte));  -- copia local de v_np_map_lk (§4.2)
create table pedidos_web_push_log (id bigserial primary key, order_id bigint, empresa text, ok boolean, error text, at timestamptz default now());
alter server virgilio_db options (add connect_timeout '10', add batch_size '100');
```

**Permisos** (§4.13 amplía): `Pedidos_Web`, `sync_heartbeat` → `grant select,insert,update,delete to lk_ppp_reader` + policy `for all to lk_ppp_reader`; **`revoke all from anon, authenticated`** (los default privileges de Virgilio dan CRUD a anon en toda tabla nueva — hallazgo `cobranzas_escalones`, GUIA:335-345). `np_map`, `Facturacion_Export_*`, `np_rename_log`, `ppp_cuarentena_*`, `PPP_Historico_Web`, `ppp_config` → **sin policy directa**: se leen por vista/RPC `SECURITY DEFINER` con chequeo de supervisor por mail (patrón `ppp_prog_write_sup`). `v_np_map_lk` → `grant select to lk_ppp_reader`. **Ningún grant nuevo del rol `lk_ppp_reader` sobre `PPP_*`** (hoy sólo SELECT).

### 4.2 Transporte LK → Virgilio: FDW push a staging, idempotente por fila (recomendado)

| Opción | Pros | Contras | Veredicto |
|---|---|---|---|
| **(a) LK empuja por FDW a `Pedidos_Web` + cron Virgilio aplica** | Server `virgilio_db`, mapping y rol **ya existen**; patrón probado 2 veces (555/555 ok); nada nuevo expuesto a anon; Virgilio lee tabla local (cero FDW en camino caliente) | Latencia = período del cron (`*/5` → 288 conexiones TLS/día); postgres_fdw **no hace two-phase commit** (el remoto commitea en el pre-commit local): un commit local fallido deja la fila remota sin sello → hay que ser idempotente por fila; el cron de LK no es visible desde Virgilio → heartbeat | **Recomendada** |
| (b) Virgilio tira de LK | — | No hay FDW inverso; PostgREST corta en 1000; el pull con anon key ya congeló `proyeccion_madre` 3 semanas; el repo decidió "push" dos veces | No |
| (c) Edge Fn en Virgilio llamada por `net.http_post` desde LK | Asíncrono | Dos secretos nuevos; sin transacción entre "marcar" y "escribir"; `pg_net` no reintenta; 5 piezas contra 2 | No |
| (d) Trigger en `orders` | Inmediato | `AFTER INSERT` de `orders` **no tiene items** (el payload lo escribe el browser después); FDW sincrónico en la transacción del checkout; si Virgilio está caído el checkout falla o el pedido se pierde | No |

**Función LK `sync_pedidos_web_virgilio()`** (`SECURITY DEFINER`, owner postgres, misma forma que `sync_pedidos_match_virgilio` pero **por fila**):

1. `if not pg_try_advisory_lock(hashtext('sync_pedidos_web_virgilio')) then return; end if;` — dos corridas no se pisan (pg_cron no impide solapamiento). `set local statement_timeout = '60s'`. `connect_timeout '10'` en el server para que un Virgilio caído falle en 10 s y no apile jobs.
2. Candidatos: `orders` con `sheets_payload is not null and enviado_a_virgilio_at is null and cancelado_at is null and customer_code in (select cod_cliente from pedidos_web_piloto where empresa='lk')`, `for update skip locked`. **Consistencia payload/items:** sólo se empuja si `md5(items del payload)` = `md5(order_items)` (el navegador escribe el payload después del RPC; si todavía no lo hizo, espera al próximo ciclo). Si `enviado_a_compras_at is not null` (ya salió en el mail) → **no** se empuja: `canal='compras'` y se sella `enviado_a_virgilio_at` para no volver a mirarlo (ese pedido sigue ISIS-first).
3. Por pedido, en un bloque `begin … exception when others then insert into pedidos_web_push_log(...); continue; end`: resuelve `razon_social` (`customers.business_name`), `direccion`/`barrio` (`customer_delivery_addresses.direccion_entrega`/`zona_expreso` por `customer_id` + `label = sucursal_entrega`; si hay 2 labels iguales toma el `slot` más reciente y anota `observaciones`), `leyenda2` (`statusFields` portado), `tipo` desde `source`, `condicion_pago_code`. Luego **idempotencia**: `select estado, items_hash from virgilio.pedidos_web where empresa=… and order_id=…`; si no hay fila → `insert`; si hay fila en `nuevo|error|rechazado` → `delete` + `insert` (fresca); si hay fila `aplicado` con otro `items_hash` → `update set items=…, items_hash=…, version=version+1, estado='reenviado', synced_at=now()` (Virgilio decide, §4.3.6); si hay fila `aplicado` con el mismo hash → nada remoto. Después sella `enviado_a_virgilio_at = now()`, `canal='virgilio'` **y también `enviado_a_compras_at = now()`** (así el mail de las 12:30 no lo vuelve a mandar aunque el filtro de §6.2 fallara). Un pedido roto no frena a los demás.
4. **Pull-back de estados (misma conexión):** `insert into pedidos_web_estado select * from virgilio.v_np_map_lk where empresa='lk' and order_id in (pedidos de los últimos 14 días)` con delete previo por ventana (mismo patrón que el match). Alimenta `isOrderEditable`/`edit_order_fast` (§4.9), `order_tracking`/`bot_pending_notifications` (§6.4) y `gv_ppp_*`, sin FDW en ningún camino caliente.
5. `insert into virgilio.sync_heartbeat … on conflict` — como es una tabla foránea no acepta `on conflict`: `update … ; if not found then insert`. `pg_advisory_unlock` al final (y en el `exception` externo).

Cron LK `*/5`. Chef: mismo patrón vía `chef_db` en fase 8 (§4.11). `edit_order_fast` e `isOrderEditable` (script.js:1803-1818) pasan a la regla de §4.9.

**Filtro del piloto en los dos lados (objeción TE-1).** El sello doble del push no alcanza: `procesar-pedidos-db` lee `orders?enviado_a_compras_at=is.null` sin saber del piloto, y (a) un pedido piloto que entra 12:26 puede salir en el mail antes del push de 12:30, (b) con Virgilio caído a las 12:30 nada se selló y el mail se lleva todos los piloto → NP en ISIS antes de armar **y** provisoria después. Por eso: **`procesar-pedidos-db` v10** agrega `customer_code=not.in.(…)` con la lista leída de `pedidos_web_piloto` (un cambio de 10 líneas en la Edge Fn, que igual se apaga al final), y `enviar_pedidos_main()` llama primero a `sync_pedidos_web_virgilio()` (así lo normal es que todo piloto ya esté sellado). Y el push, por su lado, respeta `enviado_a_compras_at` (paso 2). Las dos barreras son independientes; ninguna sola alcanza.

### 4.3 Regla de partición 18 y validación: en el backend de Virgilio

**`aplicar_pedidos_web()`** (plpgsql, `SECURITY DEFINER SET search_path = public`, owner postgres, `REVOKE EXECUTE FROM public, anon, authenticated, lk_ppp_reader`; cron Virgilio `*/2`, visible en `watchdog_syncs_externos`):

1. Toma `Pedidos_Web` con `estado in ('nuevo','reenviado','cancelado')`, en orden `(empresa, order_id)`.
2. **Valida antes de convertir en NP** (objeción TE-11: el rol `lk_ppp_reader` escribe una tabla que se vuelve picking): `cod_cliente` existe en el padrón (`clientes_vendedor`/`whatsapp_clientes`/Prog histórica, **a definir** cuál es el padrón de Virgilio), cada `cod_art` existe en `Volumen_Articulos` o `vista_uxb_articulo` (o `Equivalencias_Codigos`), `cajas > 0` y numérico, ≤ 200 líneas, `order_id` dentro de `[max(order_id) aplicado − 500, +500]`, `fecha_pedido` ≤ hoy + 1. Lo que no pasa → `estado='error'`, `error`, Telegram (`tg_enqueue(msg, dedup)`, 2 argumentos). Nada entra a la PPP sin pasar por acá.
3. Parte igual que `processOrders`: si `jsonb_array_length(items) >= 18` → bloques de 18 en el orden del payload; si `< 18` → un tramo. Cuenta **ítems**, no artículos distintos (fidelidad; consolidar es la pregunta D7). `parte` = 01..N.
4. Por tramo: `np_prov` (§3.2), INSERT `PPP_Programacion_Diaria` (`np, tanda='', tipo, fecha_recep=fecha_pedido, cod, razon_social, m3, v=vend, direccion, barrio, op='', fecha_entrega='', zona` → la deriva `ppp_autozona`, `observaciones`, `origen='web'`, `empresa`, `order_id`, `parte`) + INSERT `PPP_Base_Pedidos` (`pedido=np_prov, articulo=padCodArt(cod_art)` — mismo `padStart(3,'0')+letras` que el Excel, `cajas, cliente=razon_social, fecha=fecha_pedido, origen='web', uxb`) + INSERT `np_map`.
5. `m3` = Σ `cajas × Volumen_Articulos.m3` (11 de 321 artículos pedidos sin m3 → se suma lo que hay y `observaciones += 'm3 incompleto'`). Comparar contra ISIS en el piloto (ej. NP 98684 = 0,318).
6. Marca `estado='aplicado'`, `np_asignadas`. Como corre como postgres, `corregir_pedido_secundario_auto` y `zona_canonica()` no dan 42501.
7. **`reenviado` (edición en LK, `version > 1`):** por tramo, si `np_map.estado = 'a_programar'` (sin tanda) **y** no hay eventos EP/TP/AP/TAP/TAL con esa NP/tanda → borra y reinserta sus filas `PPP_*` (nueva partición; si cambia la cantidad de tramos, los sobrantes pasan a `cancelada`). Si algún tramo ya tiene tanda o eventos → **no toca**, `estado='rechazado'` + Telegram; LK lo ve en `pedidos_web_estado` en ≤5 min y el admin resuelve (§4.9).
8. **`cancelado`:** si ningún tramo tiene tanda/eventos → borra `PPP_*` y `np_map.estado='cancelada'`; si ya hay picking → `NP_Canceladas` (motivo "Cancelado por el cliente") + Telegram.

Idempotente por `(empresa, order_id)`; `np_prov` UNIQUE en `np_map` y el índice parcial de Prog impiden duplicar. Test: la función SQL sobre los 411 pedidos de 60 días debe dar los mismos 636 tramos que `processOrders` (`tests/np-particion.sql`, §7).

### 4.4 Cómo aparece en "Pedidos a programar" y en la base

Igual que hoy: **una fila en `PPP_Programacion_Diaria` con `tanda=''` y `fecha_entrega=''`** + sus líneas en `PPP_Base_Pedidos`. Con eso, sin tocar la app: solapa "A Programar" (`pppRenderProg`, index.html:28099), ⚠ "sin programar" en Cajas pedidas (`ocgDemanda`), `vista_np_sin_programar` en 0, `vista_np_prog_sin_base` en 0, monitor/operario la ignoran hasta que tenga tanda (`fetchMonitorFromSupabase` :30440). **No** replicar la `fecha_entrega` tentativa por zona del Excel (las 53 NP sin tanda la traen → `programmed=true` → la solapa "A Programar" da 0): con `fecha_entrega=''` la solapa vuelve a servir (pregunta D5).

### 4.5 Cómo se programa: en la app (Virgilio), no en el Sheet

`PPP_READONLY=false` en la copia + escritura **por NP y por backend**: RPC **`ppp_programar(p_np, p_tanda, p_fecha_entrega, p_zona, p_observaciones, p_no_facturar_hasta)`** (`SECURITY DEFINER`, chequeo de supervisor por mail como `ppp_prog_write_sup`, sólo sobre `origen='web'` mientras el Sheet siga vivo) que actualiza la fila (trigger deja `op='SI'` cuando hay tanda — hoy `op='SI'` ≡ "tiene tanda", 0 inconsistencias en 183), pasa `np_map.estado='programada'` y registra un evento `PPG` en `Registros_Produccion_Virgilio` (`texto = np|tanda|fecha`) para auditoría. **`observaciones` es editable** (objeción DA-9): es el único campo donde hoy la operadora anota "FACTURAR EN SEPTIEMBRE", "11:00Hs", "PEDIDO EXPO"; `no_facturar_hasta` es la versión estructurada y el checklist del export la respeta (§4.7). `pppConfirmarProgramar`/`_pppScheduleTandas` (index.html:26339-26392) hoy escriben `localStorage` (`vir_ppp_edits`): se redirigen a la RPC. El sugeridor (`_pppComputeSugerencia`) y `pppAutoBaseN` quedan como están. `dayCap`/`tandaCap` (`vir_ppp_cfg`) → `ppp_config`. **Unicidad por NP: índice único parcial `where origen='web'`** (§4.1) — no `UNIQUE(np)` global: el push del Sheet es DELETE + INSERT en dos requests sin transacción, y un renglón duplicado en el Excel dejaría la PPP entera vacía hasta el próximo push, sin Telegram (objeciones OP-11, DA-4, TE-3). Las filas sheet siguen deduplicadas con `max()` como hoy.

### 4.6 Botón de Facturación y generación del Excel

Especificación completa en §11 (Paso 0). Decisión de dónde se genera:

| Dónde | Pros | Contras |
|---|---|---|
| **RPC `facturacion_export_isis(p_nps text[], p_empresa, p_prueba)` resuelve las 12 columnas + N_Pedido + split; el navegador serializa el XML 2003 y dispara el Blob** | Lógica en backend (protocolo); un solo SQL auditable; el front sólo formatea; mismos bytes que hoy importa ISIS (port literal de `generateExcel`, ~60 líneas) | El estado "exportada" lo marca la misma RPC antes de devolver filas (transacción) |
| Edge Function en Virgilio | Podría mandar el mail a ventas@ como hoy | Secretos Gmail nuevos en Virgilio; la operadora **baja el archivo y lo importa**: no hace falta mail |
| Todo en navegador | Rápido de escribir | Lógica en front (contra protocolo), 5 viajes, imposible de auditar |

**Recomendación:** RPC + serialización en navegador. **La RPC agrega por `(np, cod_art)`** (objeciones DA-1, OP-3): `distinct on (np, cod_art) … order by id desc` sobre `Entregas_Virgilio` (la última fila armada manda), `cajas = least(cajas_entregadas, cajas_pedidas)`, y marca ⚠ "re-armada" en el checklist cuando había más de una fila; si `sum(cajas_entregadas) > cajas_pedidas` entre filas distintas la NP se muestra pero **no se exporta** hasta que un supervisor la destilde/confirme. Sin esto, 28 de las últimas 748 NP habrían ido a ISIS al doble. Mail sólo si el dueño lo pide (pregunta D9).

### 4.7 Estados del tramo web: `armada → exportada → importada → facturada` (cambia respecto del borrador)

El borrador convertía el tilde en "cola de export" y hacía que `confirmar_np_isis` insertara `Facturacion_NP` con `facturado_at=now()`. Dos objeciones opuestas lo tumbaron: (DA-3) sacar `Facturacion_NP` del tilde deja sin NP web al cierre de jornada, al PDF y a "Armar ruta" (todos leen `Facturacion_NP` con `cierre_id null`); (TE-8) insertarla al confirmar la NP avisa "facturado" por WhatsApp (`wa_np_facturado_trg` → `wa_grupo_completo_check` → `lk_notif-facturado`) y drena `a_facturar` **antes de que exista la factura**. Diseño final — **`Facturacion_NP` se escribe cuando hoy, con la factura real, y con la NP real**:

| Estado `np_map` | Quién lo pone | Qué habilita |
|---|---|---|
| `armada` | Trigger AFTER INSERT en `Entregas_Virgilio` (`SECURITY DEFINER`) cuando la NP web tiene filas con `cajas_entregadas > 0` | Aparece en el checklist "Armadas — pendientes de ISIS" de Facturación (§11.2). **No** escribe `Facturacion_NP` |
| `exportada` | `facturacion_export_isis()` en una transacción: inserta `Facturacion_Export_ISIS` + `Facturacion_Export_Lineas` (foto agregada de `Entregas_Virgilio`), marca `np_map.export_id`, devuelve las filas. Si el front no recibe filas, no genera archivo. Re-export = botón explícito con confirm | La operadora importa en ISIS |
| `importada` | `confirmar_np_isis(p_export_id, p_np_inicial)`: renombra (§3.1-A, §3.5), absorbe cuarentena (§3.4), escribe `np_rename_log`, re-postea `pa_entregas` (288/2533), `importado_at`. **No** inserta `Facturacion_NP`, no drena, no avisa | La NP ya es real: aparece en la lista normal de Facturación como cualquier NP de ISIS; la operadora factura en ISIS |
| `facturada` | **El tilde de siempre** (`facTickNP`, post-factura) inserta `Facturacion_NP` con la NP real y el front drena stock **como hoy** (`stockSalidaFacturadoNP`). Trigger AFTER INSERT en `Facturacion_NP` (`SECURITY DEFINER`): si la NP está en `np_map` → `estado='facturada'`, `isis_export_id`, e **inserta `PPP_Entregados_Meta` (`origen='web'`)** (§6.4) | Cierre de jornada, PDF, ruteo, CCN, WhatsApp, ARCA, cobranzas, LK: todo idéntico a hoy |
| `archivada` | Cron nocturno `ppp_archivar_web()` (§4.14) | Sale de `PPP_*` |

Consecuencias: (1) el **drenaje de stock no se mueve** al backend en esta idea (el borrador lo movía a `confirmar_np_isis`; era "el cambio más delicado del módulo" y ya no hace falta — queda como mejora aparte, sin bloquear); (2) `facRevertir` (DELETE `cierre_id is null`) y `trg_revertir_drenaje_facturado` no necesitan guard nuevo: revertir un tilde web deja la NP real en estado `importada`, igual que hoy una NP destildada; (3) `no_facturar_hasta` / texto "FACTURAR EN" en observaciones → el checklist del export la **excluye** hasta esa fecha (con ⚠ visible), así "lo exportado se factura ese día" (riesgo 16) no choca con la nota comercial; (4) el cierre de jornada avisa "**N tramos web armados sin ISIS** (estados `armada|exportada|importada`) — ¿cerrar igual?" para que nada quede olvidado el viernes. NP `origen='sheet'` (KRIKOS/COT/manual): tilde igual que hoy, no entran al export.

### 4.8 Parciales, faltantes, completar (CP) y reasignar (RC)

- El Excel lleva **`cajas_entregadas`** (decisión del dueño 25/08 en 5547: factura parcial, los faltantes se pierden), **agregadas por `(np, cod_art)`** (§4.6). Líneas con `cajas_entregadas=0` **no van**. El faltante queda en `Entregas_Virgilio.cajas_falto` → los reportes de "plata perdida" siguen saliendo de Virgilio.
- **CP/RC después del export** (hoy 2 NP / 4 cajas en 60 días; RC: 0). El borrador decía "export complementario → nueva NP en ISIS" sin decir dónde vivía esa NP (objeción OP-10): `np_map` es 1:1 y `Facturacion_NP` tiene PK `np`, así que una segunda NP de ISIS para el mismo tramo no drenaba, no entraba a `wa_*`/cobranzas/ARCA y `vista_np_factura` la marcaba `ambiguo`. Diseño final: **el complemento tiene identidad propia** — fila de `np_map` con `parte 91..99`, `complemento_de = parte original`, su `np_prov` (`9 + order_id + 91`), sus `Facturacion_Export_Lineas` (sólo la diferencia +N que da `vista_export_isis_diferencias` = `Entregas_Virgilio` agregada − Σ exports del tramo), su propia NP de ISIS al confirmar y su propia fila de `Facturacion_NP` (m3 de la diferencia) al tilde. `Entregas_Virgilio` sigue colgada de la NP original; la vista de diferencias mira el tramo + sus complementos.
- **Hasta que exista el complemento (fase 7), CP/RC sobre un tramo `exportada|importada|facturada` se bloquea en la app** (la pantalla de CP/RC consulta `np_map.estado` por vista) con Telegram; −N (RC sobre donante exportada) siempre es aviso + ajuste manual en ISIS. Pregunta D8.
- `validar_np_armada` sigue valiendo: sólo se exporta lo que tiene `Entregas_Virgilio`.

### 4.9 Ediciones y cancelaciones del pedido web (cambia respecto del borrador)

- **Edición: "editable hasta que tenga tanda"** (objeción DA-5: las 7 ediciones reales de 90 días ocurrieron entre 1 min y 19 h después del pedido; "editable hasta el push" bloqueaba 5 de 7 sin procedimiento para el resto). Regla única, en las dos bases:
  - LK, `isOrderEditable` + `edit_order_fast`: editable si `enviado_a_virgilio_at is null`, **o** si todos sus tramos en `pedidos_web_estado` (copia de ≤5 min, §4.2.4) están en `a_programar`. `edit_order_fast` (que ya hace `FOR UPDATE`) reemplaza `order_items`, pone `enviado_a_virgilio_at = null`, `version_virgilio + 1`; el navegador reescribe el payload (policy `orders_update_own_sheets` con `enviado_a_virgilio_at is null` lo permite justo porque el RPC lo des-selló); el push lo reenvía con `estado='reenviado'` cuando payload e items coinciden (§4.2.2).
  - Virgilio, `aplicar_pedidos_web()` es **la autoridad** (§4.3.7): aplica si el tramo sigue sin tanda ni eventos; si en esos ≤5 min alguien lo programó → `rechazado` + Telegram; LK lo ve en el próximo pull-back y el admin resuelve (cancela el tramo en Virgilio con "Cancelar tramo" y recarga, o llama al cliente). No hay caso sin procedimiento.
  - Triggers de blindaje en LK (objeción OP-9): AFTER UPDATE OF `sheets_payload` en `orders` y AFTER INSERT/DELETE en `order_items` → si `enviado_a_virgilio_at is not null` lo ponen en null y suben `version_virgilio` (cubre cualquier camino que no pase por `edit_order_fast`).
- **Borrado/reescritura por el cliente después del push** (objeciones OP-8, TE-14): en la **fase 2**, `alter policy orders_delete_own … using (auth.uid() = auth_user_id and enviado_a_virgilio_at is null)` y `alter policy orders_update_own_sheets … using (… and enviado_a_virgilio_at is null) with check (…)`. Un pedido empujado ya no se puede borrar ni reescribir por fuera del RPC.
- **Cancelación:** hoy no existe. `orders.cancelado_at` + RPC `cancelar_pedido(p_order_id, p_motivo)` (cliente mientras sea editable; admin siempre); el push manda `estado='cancelado'` (si la fila ya está `aplicado`, `update … set estado='cancelado'`); `aplicar_pedidos_web()` §4.3.8. Desde Virgilio: botón **"Cancelar tramo"** en la pantalla `v_pedidos_web_estado`/`np_map` de la copia (RPC `cancelar_tramo_web`, supervisor) que borra `PPP_*` del tramo sin eventos y avisa por Telegram al legajo si estaba en curso; con picking → `NP_Canceladas`. Informar la cancelación a LK va por el pull-back (`estado='cancelada'`). `orders_delete_own` queda sólo para pedidos no empujados.
- **Rollback de lo ya empujado** (objeción TE-6): RPC LK `rollback_pedidos_web(p_order_ids bigint[])` que en **una** transacción FDW pone `estado='cancelado'` en `Pedidos_Web`, des-sella `enviado_a_compras_at` y `enviado_a_virgilio_at`, `canal=null`, y deja constancia en `pedidos_web_push_log`; `aplicar_pedidos_web()` borra los tramos sin eventos; el pedido sale en el próximo mail de las 12:30. Con picking iniciado no hay vuelta: se termina por el camino nuevo. Runbook en `docs/` con el `select` de verificación (§6.3).

### 4.10 Pedidos que NO vienen de la web (fallback)

Cobertura medida **por empresa**: Programación LK WEB 141/150 = 94 %, COT 6/6, KRIKOS 3/3, tipo vacío 0/3 (Matiz); Chef WEB 13/15 = 86,7 %, COT 3/3, KRIKOS 0/3 (Dorinka); total 166/183 = 90,7 %. Base: LK 665/700 = 95 %, Chef 72/101 = 71 %. Lo no cubierto sigue **ISIS-first**: ISIS los numera y entran a Virgilio por (i) el Sheet durante la transición (`origen='sheet'`, §6.1) — o sea **la operadora sigue bajando los 2 reportes todos los días hasta la fase 9** (objeción DA-12; §1.1 fila 5) — y (ii) después, por un formulario **"Cargar NP manual"** en la copia: NP real de ISIS, `cod`, fecha, líneas `cod_art + cajas` (pegadas desde el reporte o tipeadas), `origen='manual'`; m³/uxb/zona/partición los calcula **la misma función de §4.3** (`aplicar_pedido_manual()` reusa el cuerpo con `np` dado en vez de provisoria); lo carga **quien carga en ISIS, en el mismo acto**. Conviven con las web en la misma tanda: cada NP sabe su `origen`.

### 4.11 Chef (prefijo 4)

Fase 8, con **precondiciones explícitas** (objeción TE-13): (1) inventario de `cron.job` y Edge Functions del proyecto Chef `nkhzocgdpwtgrmwleihr` — si Chef tiene su propio "procesar-pedidos", el filtro del piloto tiene que estar **también ahí** (§6.2), y hoy no hay nada de Chef en ningún repo; (2) grant en Chef `update (enviado_a_compras_at, enviado_a_virgilio_at) on orders to loke_reader` (hoy sólo SELECT, y ni eso confirmado), o una tabla de sellos del lado LK `chef_orders_enviados(order_id, at)`; (3) `v_pedidos_match_chef` trae `sucursal_entrega` y `condicion_pago_code` de `chef_orders.sheets_payload` (hoy 50/57 sin sucursal); (4) la regla de empresa por primer dígito ya desplegada (fase 1). Hasta cumplirlas, **Chef queda fuera del piloto en los dos lados**. Push con `empresa='chef'`, provisoria `4…`, Excel separado por empresa, lote/primera NP por empresa. Krikos Chef entra por el mismo push desde `chef_orders`.

### 4.12 m³ / zona / vendedor / tipo / observaciones

| Dato | Fuente | Gap |
|---|---|---|
| m³ | `Volumen_Articulos` en `aplicar_pedidos_web()` | 11/321 artículos sin m³; comparar contra ISIS en piloto |
| zona | `ppp_autozona` desde `barrio` (= `zona_expreso` de LK) | 61 de 138 valores de `zona_expreso` no matchean `Zonas_Barrios` (~10 % de direcciones): tabla `Zonas_Barrios_Alias` o corregir el padrón LK. Lo no resuelto cae en `PPE sinzona` (Telegram) |
| v (vendedor) | `sheets_payload.vend` (210/210) | 10 clientes sin `vend` en LK. Se guarda para el Excel |
| tipo | `source`: Web→WEB, Cotizador→COT, Krikos→KRIKOS, Excel→EXCEL | `KRIKOS` lo consume `pppEsSuper`/alertas |
| observaciones | Inicial: `coalesce(observaciones, 'OC '||pdf_oc, 'CLIENTE NUEVO - EXPO')`; **editable** por `ppp_programar()` (§4.5) | Hoy lo tipea la operadora en ISIS; en régimen lo escribe en Virgilio y viaja como referencia (H5) |
| no_facturar_hasta | `np_map`, desde `ppp_programar()` | Reemplaza el texto "FACTURAR EN SEPTIEMBRE"; el export la respeta |
| fecha_entrega | vacía hasta programar; `due_date` de Krikos como sugerencia | Ver D5 |
| fecha_fc | se abandona (`Facturacion_NP.facturado_at` la reemplaza) | — |

### 4.13 Seguridad y permisos (nuevo, consolida objeciones TE-2, TE-9, TE-10, TE-11)

- **Toda trigger fn nueva sobre tablas que reciben INSERT con anon key** (`Entregas_Virgilio`, `Registros_Produccion_Virgilio`, `PPP_*`, `Facturacion_NP`) es **`SECURITY DEFINER SET search_path = public`** y lleva **`REVOKE EXECUTE FROM anon, authenticated`** sobre la **función** (no sobre la tabla). Aplica a: `ppp_protege_origen_web`, `ppp_cuarentena_sheet`, `np_map_marcar_armada`, `np_map_marcar_facturada`, `ccn_provisoria_telegram`, el re-mapeo de colas offline por `np_map`. Motivo: una fn INVOKER que lea `np_map` (sin policy para anon) corriendo como `anon` da `42501` y rompe **todos** los armados y eventos, en silencio si el `.catch` no distingue (incidente 28/08, `docs/RIESGO-ESTRUCTURAL-CANON.md`). `pppSubir` (supervisor JWT) también pasa por los triggers de `PPP_*` → mismo tratamiento.
- **Checklist de migración del runbook (idea 9670)** en cada fase que cree funciones, y **`tests/anon-writes.cjs`** (idea 1817: por cada tabla con policy INSERT anon, INSERT dummy y 2xx, contra el **branch**) como criterio de "listo" de las fases 1 y 5.
- **Datos comerciales:** `Pedidos_Web.leyenda2` (deuda, límite, PP) y `items` no se exponen a ningún rol del navegador: la pantalla de la copia lee `v_pedidos_web_estado` vía RPC `pedidos_web_estado(p_desde)` (`SECURITY DEFINER`, supervisor por mail). `np_map` idem (`np_map_listar()`).
- **Rol `lk_ppp_reader`:** `Pedidos_Web` es la primera tabla que ese rol escribe y que se **convierte en operación**; la defensa es la validación del consumidor (§4.3.2). Además, en un proyecto aparte (no bloquea): revocar `EXECUTE … FROM PUBLIC` en las `SECURITY DEFINER` sensibles (hoy el rol alcanza 238 funciones por herencia; `REVOKE … FROM lk_ppp_reader` solo no alcanza porque el grant es de `PUBLIC`) y `ALTER DEFAULT PRIVILEGES … REVOKE`.
- **`Facturacion_NP` con CRUD anon (9 policies):** cerrar a JWT antes de colgarle `isis_export_id` (colateral, D15).

### 4.14 Archivado: la "ventana" que hoy impone el Excel (nuevo)

Hoy el reemplazo total del Sheet es también la purga (§2). Con `ppp_protege_origen_web` (BEFORE DELETE → `RETURN NULL` para `origen='web'`) y sin archivado, cada tramo web quedaría **para siempre** en `PPP_Programacion_Diaria` con tanda y en `PPP_Base_Pedidos`: el monitor/operario (`fetchMonitorFromSupabase` arma tandas con toda fila con np+tanda), `pppRenderProg` "programados", `reconciliar_pipeline_stock`, `vista_np_sucursal`, `cobranzas_valorizar_np`, `wa_np_snapshot_run` listarían cientos de tandas viejas a los 3 meses (objeción OP-4). Cron nocturno **`ppp_archivar_web()`**: para `np_map.estado in ('facturada','cancelada')`, copia las filas `origen='web'` de Prog/Base a `PPP_Historico_Web` (jsonb) y las borra — Prog cuando hay CRN o `facturado_at < now() − 3 días` (replica "la operadora la saca del Excel cuando salió"); Base a los **60 días** de `fecha_pedido` (replica la ventana de 1655; `Facturacion_Export_Lineas` y `Entregas_Virgilio` conservan el detalle); `PPP_Entregados_Meta` web se conserva como el Sheet anual. `np_map.estado='archivada'`. `confirmar_np_isis` no archiva nada (la NP real sigue viva hasta salir).

---

## 5. Mapeo de campos del Excel (columna → fuente exacta → gap)

Columnas y tipos según `generateExcel` real. "Hoy" = Paso 0 sobre NP del circuito actual (sin cambiar nada); "Régimen" = flujo 3717 con `Pedidos_Web`/`np_map`. Cobertura medida sobre las **450 NP facturadas en los últimos 30 días** (sin 999…): **385 LK + 65 Chef**. Donde la cobertura difiere por empresa se informa por separado (objeción DA-8).

| # | Col | Hoy (Paso 0) | Cobertura hoy | Régimen | Gap |
|---|---|---|---|---|---|
| 1 | `fecha` dd/MM/yyyy | `min(PPP_Base_Pedidos.fecha)` de la NP (= fecha del pedido web por construcción) | 450/450 | `Pedidos_Web.fecha_pedido` | Ninguno |
| 2 | `N_Pedido` | Correlativo 1..N por NP en el orden del checklist | — | Idem, 1 tramo = 1 N_Pedido; complementos = N_Pedido propio | Ninguno |
| 3 | `cliente` | `Facturacion_NP.cod_cliente` | 450/450 | `np_map → Pedidos_Web.cod_cliente` | Ninguno |
| 4 | `vend` | `clientes_vendedor.vend` (snapshot manual 11/08) | 406/450 (90 %) | `Pedidos_Web.vend` | Hoy 10 % vacío → la operadora completa en ISIS |
| 5 | `articulo` | `Entregas_Virgilio.cod_art` **agregado por `(np, cod_art)`** (§4.6) → quitar sufijo ` LK`/` CH` si lo hubiera (**a verificar** si `fn_canon_col_cod_art` los deja) → `padCodArt` | 100 % | Idem | Código **real** armado (437E, no 029). Si ISIS lo tiene en su maestro se prueba con el Paso 0 (H7); `Codigos_ISIS_Map` **no sirve** para esto (es el mapa de insumos/producción: `codigo_interno` 7 dígitos → `nuevo_codigo`, rubros Insumos/Proceso/Materia Prima); el único mapa de venta es `Equivalencias_Codigos` (8 filas, 029→437E), ya en la dirección que el Excel necesita |
| 6 | `cajas` | `least(cajas_entregadas, cajas_pedidas)` de la **última** fila `(np, cod_art)` (>0) | 100 % | Idem | Hoy el Excel lleva pedidas; ahora entregadas (decisión 25/08). 28 NP de 748 tenían la línea dos veces: sin la agregación irían al doble |
| 7 | `uni` = cajas×uxb | `vista_uxb_articulo.uxb` con `cod = ltrim(cod_art,'0')` | 5.286/5.288 líneas | `Pedidos_Web.items[].uxb` | El desfase reportado (174/450) era **formato** (`40` vs `040`); normalizar en la RPC |
| 8 | `sucursal` | `lk_pedidos_match.sucursal_entrega` por `cod_cliente` + `empresa` + `fecha_pedido` ∈ [fecha−3, fecha]; desempate por **inclusión de los ítems del tramo en `items_string` del pedido** (no igualdad del `match_string` entero: un pedido de 93-120 líneas partido en 6-7 tramos nunca iguala a un tramo — objeción DA-11), luego `orden_en_dia`; **⚠ siempre que haya >1 pedido del cliente ese día** (22 cliente-día con 2 sucursales en 90 días), no sólo si `ambiguo` | **LK 380/385 (99 %)**; **Chef 5/65 (8 %)**: 50 de 57 filas chef vienen sin sucursal | `Pedidos_Web.sucursal_entrega` (label exacto) | Chef **queda fuera del Paso 0** (o sale con ⚠ en todas): su Excel no probaría el formato real hasta que `v_pedidos_match_chef` traiga la sucursal |
| 9 | `leyenda2` "D x - LC x - PP x" | **No existe en Virgilio** → vacío | 0 % | `Pedidos_Web.leyenda2` (LK la arma con `statusFields`) | ¿Obligatoria en ISIS? (H5) |
| 10 | `condPago` (código) | **`lk_pedidos_match.condicion_pago_code`** — columna nueva en `v_pedidos_match`/`lk_pedidos_match` (1 columna del lado LK, misma sync de 15 min; el código ya viene en `sheets_payload.condicion_pago_code` en 100 % de los pedidos). **Sin mapa de textos**: `metodo_pago` es texto libre ("Contado" 220 sin tasa, "Prefiero no decidir ahora" 88, "CHECK:10010:S+ 90…", "Echeq 120 dias"…) y no se mapea a nada (objeción DA-7) | Con la columna: ~99 % LK (misma cobertura que sucursal); sin ella: 0 % | `Pedidos_Web.condicion_pago_code` | Es el único DDL del Paso 0 fuera de la RPC → pregunta D11 |
| 11 | `pctDto` | Fijo "2% Descuento Web" como hoy | — | Idem; opción `''` para súper con lista propia y "Pedir para" admin | Pregunta D10 |
| 12 | `numOC` | Vacío (como en 1.013/1.013 pedidos) | — | `Pedidos_Web.num_oc` = `coalesce(numOC, pdf_oc)` (Krikos 35/35 traen `pdf_oc`) | Mejora gratis |

Cabecera PPP (`PPP_Programacion_Diaria` ← `Pedidos_Web`): `np`←`np_prov`, `tipo`←`tipo`, `fecha_recep`←`fecha_pedido`, `cod`←`cod_cliente`, `razon_social`←`razon_social` (= `customers.business_name`, verificado idéntico en 9 NP), `m3`←calculado, `v`←`vend`, `direccion`←`customer_delivery_addresses.direccion_entrega`, `barrio`←`zona_expreso`, `zona`←trigger, `observaciones`←§4.12; `tanda/op/fecha_entrega/fecha_fc` vacíos.

---

## 6. Convivencia con el circuito viejo, cutover y rollback

### 6.1 Coexistencia por NP con `origen`, sin tocar el Apps Script

El choque real es el **reemplazo total** de `PPP_*` por el push del Sheet (`_pppSupaReplaceAll_`: `DELETE ?id=gte.0` + INSERT). Tres triggers en Virgilio lo neutralizan **sin modificar "Carga PPP.gs"** (fuera del repo). Los tres son **`SECURITY DEFINER` + `REVOKE EXECUTE` a anon/authenticated** (§4.13): el Apps Script escribe con service_role pero `pppSubir` escribe con JWT de supervisor, y una fn INVOKER que toque `np_map`/`ppp_cuarentena_*` desde `authenticated` daría `42501` y tumbaría el `pppSubir` entero (objeción TE-9).

- `ppp_protege_origen_web` BEFORE DELETE en `PPP_Programacion_Diaria` y `PPP_Base_Pedidos`: `IF old.origen='web' THEN RETURN NULL` (el push del Sheet sigue borrando y reinsertando sólo lo suyo).
- `ppp_cuarentena_sheet` BEFORE INSERT (§3.4): si `new.origen='sheet'` y la NP ya está en `np_map.np_isis` → `RETURN NULL`; si `(cod, fecha_recep)` coincide con un tramo `exportada` sin `np_isis` → a cuarentena y `RETURN NULL`; las líneas de Base cuyo `pedido` esté en cuarentena, idem.
- **No** se agrega un trigger que rechace NP `sheet` duplicadas (lo proponía OP-11): el índice único es parcial (§4.5) y las filas sheet siguen tolerando duplicados con `max()` como hoy; agregar comportamiento al camino del Sheet es justo lo que se quiere evitar.

Resultado: el Sheet sigue alimentando las NP no web (§4.10) y `PPP_Entregados_Meta` sheet; las web viven en Virgilio. El día que el Sheet deje de usarse, los triggers quedan inertes.

### 6.2 Cutover gradual por cliente (piloto), con el filtro en los dos lados

El corte real está del lado LK: un pedido no puede ir **a la vez** al mail de las 12:30 y al push. `pedidos_web_piloto(cod_cliente, empresa)` es la única lista, y la leen **tres** piezas (§4.2): `sync_pedidos_web_virgilio()` (sólo empuja piloto y sella los dos campos), **`procesar-pedidos-db` v10** (excluye piloto del `orders?…` — así ni la carrera de 12:26 ni un Virgilio caído a las 12:30 mandan un piloto al mail) y `enviar_pedidos_main()` (corre el push antes de postear). Chef: hasta cumplir §4.11, **fuera del piloto también del lado que manda su mail**. Etapas: 2-3 clientes LK de pocas líneas → clientes grandes con partición → todos LK → Chef. El mail de las 12:30 sigue saliendo para el resto y se apaga cuando la lista es "todos" y pasan N semanas sin incidentes.

### 6.3 Rollback

- **Por pedido ya empujado:** `rollback_pedidos_web(p_order_ids)` en LK (§4.9): una transacción FDW, des-sella, cancela en `Pedidos_Web`, log; `aplicar_pedidos_web()` borra los tramos sin eventos; el pedido sale en el próximo mail. Verificación: `select id, enviado_a_compras_at, enviado_a_virgilio_at, canal from orders where id = any(…)` y en Virgilio `select * from v_pedidos_web_estado where order_id = any(…)` → `cancelado`. Con picking iniciado: se termina por el camino nuevo (export + import).
- **Por cliente:** sacarlo del piloto (los tres filtros lo leen) + rollback de sus pedidos sin eventos.
- **Total:** `update cron.job set active=false where jobname='sync-pedidos-web-virgilio'` en LK, `pedidos_web_piloto` vacía, `aplicar_pedidos_web` off. Como LK no tiene Telegram, la confirmación de que el cron está apagado es `sync_heartbeat.ultimo` en Virgilio **dejando de avanzar** (el watchdog lo avisa al revés: heartbeat viejo = push apagado). El Sheet nunca dejó de empujar; nada del circuito viejo se desmontó hasta el final.
- Backups antes de cada DDL (protocolo del repo): `PPP_Programacion_Diaria`, `PPP_Base_Pedidos`, `Facturacion_NP`, `Entregas_Virgilio`, `PPP_Entregados_Meta`, `Movimientos_Stock` (por el `ALTER TRIGGER`). El renombre diario tiene su propio backup: `np_rename_log` (§3.7).

### 6.4 Qué pasa con cada pieza del circuito viejo

| Pieza | Transición | Final |
|---|---|---|
| Sheet PPP + Excel "AAA PPP Vigente" + Apps Script push | Sigue para NP no web (la operadora baja los 2 reportes todos los días hasta la fase 9) | Se apaga cuando exista "Cargar NP manual" (§4.10) |
| **Tracking WhatsApp al cliente y solapa Tracking del admin LK** (`order_tracking` con `np_number = order_id`, `bot_pending_notifications` tipos `programado`/`entregado`, cargados desde el Excel PPP en admin.js `parseTracking` :2536-2556) | **Objeción OP-12: el hueco empezaba en la fase 6**, no al final. Un pedido piloto no está en ese Excel → el cliente dejaría de recibir "programado"/"entregado" desde el primer día. Diseño: cron LK (mismo del push, §4.2.4) deriva `order_tracking`/`bot_pending_notifications` desde `pedidos_web_estado` (`programada` + `fecha_entrega` → 'programado'; `facturada` → 'enviado'/'entregado'). **Prerrequisito de la fase 6** | El Excel deja de alimentar tracking |
| Mail 12:30 (`procesar-pedidos-web`, `retry-procesar-pedidos`, `procesar-pedidos-db` v10 con filtro piloto) | Sigue para no-piloto | Cron off; Edge Fn queda desplegada como contingencia (`dry:true`) |
| Reportes de ISIS (Programación Diaria / Base Datos Pedidos) | Sigue bajándolos la operadora para lo no web; lo que trae de NP web va a cuarentena/`RETURN NULL` (§6.1) | Deja de hacer falta |
| **`PPP_Entregados_Meta`** (Sheet "PPP Pedidos Entregados 2026", cron cada 30 min, `TRUNCATE`) | **Objeción OP-5: ninguna NP web llegaría a Meta, ni antes ni después del renombre** (no está en el Excel). Consumidores que dependen de Meta y no de `Facturacion_NP`: `pppTandaM3Map` (:25602) y `vista_tanda_m3`, `_pppMetaEntSet` (:25627, entregados de PPP), reparto de Carga Camión ("sale del CC por CCN o por Meta"), `sync_pasaje_rr`, `reconciliar_pipeline_stock`, `generar_inconsistencias`, `vista_np_sin_programar`, LK `ppp_entregados`. Diseño: columna `origen` en Meta; el trigger del tilde (§4.7 `facturada`) inserta `(np real, cod, rs, tanda, m3 de Prog, fecha_entrega = fecha_salida, origen='web')`; `sync_ppp_entregados_meta()` pasa de `TRUNCATE` a `DELETE WHERE origen='sheet'` (con `WHERE` real: `supautils` bloquea DELETE sin WHERE para roles no superusuario). **Prerrequisito de la fase 6**, construido en la 5 | Migrar los 8 consumidores a `Facturacion_NP` + CCN — proyecto aparte |
| `lk_pedidos_match` / `vista_np_sucursal` / `Alertas_Pedidos_Web` | Sigue para NP `origen='sheet'`; gana `condicion_pago_code` (§5) | Se retira cuando todo sea web-directo o queda como verificación |
| `pa_entregas` (OSA/TyL en LK) vía `virgilio-entrega-sync` | Nace con provisoria al armar; `confirmar_np_isis` re-postea `rename` (§3.5) | Igual |
| Cobranzas (`cobranzas_valorizar_np`, `cob_empresa_np`) | Sin cambios: corren sobre NP real post-import | Sin cambios |
| Cruce facturas ISIS (`vista_np_factura`, v12.29) | Sin cambios (matchea por cliente+fecha+neto) | Con `np_map` se puede mejorar el match |
| `sincronizar_ppp()` LK (roto desde 26/08) | Arreglar la foreign table `virgilio.pedidos_entregados` (fuera de esta idea) | Si se arregla, `gv_ppp_*` ve provisorias como backlog LK (`left(np,1)='9'`): correcto |
| 5547 | P1 se redefine ("pedido armado listo para facturar" = Excel de 3717, o JSON como upgrade); P2/P3/P5 se caen; P4 independiente; comunicar a Horacio (H8) | Un solo dueño del pedido: Virgilio |

---

## 7. Fases de implementación

Cada fase se verifica sola y no depende de la siguiente. Estimación relativa (S < M < L). "Branch" = probable en un branch de Supabase (§12.2). Cada fase que cree funciones corre el checklist del runbook de migraciones (9670) y agrega sus tests a `tests/run.sh` (objeción TE-15).

| Fase | Contenido | Criterio de "listo" | Est. | Branch |
|---|---|---|---|---|
| **0** | Botón Excel en Facturación sobre NP actuales (§11): RPC `facturacion_export_isis` (dedup, cobertura por empresa), serializador, archivo `PRUEBA_NO_IMPORTAR_*`, botón oculto; opcional `condicion_pago_code` en `lk_pedidos_match` (D11) | ISIS importa el archivo en entorno de prueba (o Horacio confirma formato); gaps medidos por empresa; **`tests/fac-excel-isis.cjs`** (fixture 3 NP → XML byte a byte, casos `029`, celda vacía, NP re-armada) en `run.sh` | S | Sí (RPC) |
| **1** | DDL aditivo: `Pedidos_Web`, `np_map`, `Facturacion_Export_*`, `np_rename_log`, `ppp_cuarentena_*`, `PPP_Historico_Web`, `ppp_config`, `sync_heartbeat`, columnas `origen/empresa/order_id/parte/uxb` y `PPP_Entregados_Meta.origen`, **índice único parcial**, triggers §6.1 (`SECURITY DEFINER` + REVOKE), vistas `v_pedidos_web_estado`/`v_np_map_lk`, **regla de empresa por primer dígito** (`empresa_de_np`, `empresaDeNp`, `pkNpEsLoeke`), **`ALTER TRIGGER trigger_actualizar_saldo_stock … UPDATE OF`**, `REVOKE` a anon en todo lo nuevo | Push del Sheet sigue igual (conteos antes/después, y un push con una NP repetida a propósito en el branch **no** vacía la tabla); `pppSubir` igual; `tests/emp-np.cjs` ampliado con `9…`/`4…` de 9 dígitos; `tests/anon-writes.cjs` verde en branch | M | Sí |
| **2** | LK: columnas `enviado_a_virgilio_at/cancelado_at/version_virgilio/canal`, `pedidos_web_piloto`, `pedidos_web_estado`, `pedidos_web_push_log`, `sync_pedidos_web_virgilio()` (por fila, advisory lock, pull-back), cron `*/5`, heartbeat; **`ALTER SERVER virgilio_db` (`connect_timeout`, `batch_size`)**; **policies `orders_delete_own`/`orders_update_own_sheets` con sello**; triggers de des-sello en `orders`/`order_items`; **`procesar-pedidos-db` v10 con filtro piloto** + `enviar_pedidos_main()` llama al push; `rollback_pedidos_web()` | Con piloto vacío: 0 filas empujadas, heartbeat cada 5 min, mail de las 12:30 idéntico; con 1 cliente de prueba: fila en `Pedidos_Web` con los 12 datos + dirección/barrio; **simulación de Virgilio caído** (server apuntado a puerto cerrado en branch de LK, o `connect_timeout` forzado): la corrida falla en ≤10 s, no se apila, el mail no lleva al piloto; un pedido roto no frena a los demás (`pedidos_web_push_log`) | M | No (FDW apunta a prod) |
| **3** | Virgilio: `aplicar_pedidos_web()` (validaciones, partición, `reenviado`, `cancelado`) + cron `*/2` + watchdog; fix `vista_np_faltantes_secuencia`/`pppFindNpPdf`; prefijo visual "NPV" | Pedido de prueba → N tramos en `PPP_*` con `origen='web'`; **`tests/np-particion.sql`**: sobre los 411 pedidos de 60 días la función da los mismos 636 tramos que `processOrders`; m³ ±5 % vs ISIS; zona derivada; sobrevive a un push del Sheet; una fila inválida (cod_art inexistente) queda en `error` + Telegram, no en la PPP | M | Sí (con `Pedidos_Web` sembrada a mano) |
| **4** | Programar en la app: `PPP_READONLY=false` en la copia, `ppp_programar()` (con `observaciones` y `no_facturar_hasta`), `ppp_config`, evento `PPG`; pantalla `v_pedidos_web_estado` con "Cancelar tramo" | Operadora programa 1 tanda de prueba en la copia; monitor/operario la ven; `ppp_etapa_tanda` la sigue; **`tests/ppp-programar-rpc.cjs`** (con `page.route` mockeando el RPC) en `run.sh` | M | Sí |
| **5** | Facturación régimen: estados `armada/exportada/importada/facturada` (§4.7), `facturacion_export_isis()` con estado, `confirmar_np_isis()` (renombre por regexp + cuarentena + `np_rename_log` + re-post `pa_entregas`), `deshacer_np_isis()`, trigger de `Facturacion_NP` → `np_map` + **`PPP_Entregados_Meta` web** + cambio de `sync_ppp_entregados_meta` a `DELETE WHERE origen='sheet'`, guard CCN en la app + Telegram, aviso en el cierre, **`ppp_archivar_web()`**, Edge Fn LK `virgilio-entrega-sync` acción `rename` (repo PaginaLK) | Sobre un tramo de prueba armado con legajo 0/1 en el branch: export → renombre → `deshacer` → renombre otra vez; `Entregas_Virgilio`, TAL/FCO, `Etiquetas_Lio`, `Movimientos_Stock.ref` renombrados y `vista_saldos_stock` **idéntica** antes/después (el saldo no se recalcula: `UPDATE OF`); tilde → `Facturacion_NP` con NP real + fila en Meta `origen='web'`; cuarentena absorbe un push del Sheet simulado con la NP real; `tests/anon-writes.cjs` verde | L | Sí (lo más importante de probar ahí) |
| **6** | Piloto real 2-3 clientes LK (**no** 288/2533 hasta que `rename` de `pa_entregas` esté desplegado en LK); tracking LK desde `pedidos_web_estado`; Excel de cierre; papel (reimpresión) | **Prerrequisitos:** Meta web (fase 5), tracking LK, filtro piloto en la Edge Fn, policies de `orders`. 2 semanas sin intervención manual en ISIS salvo importar + facturar; NP real coincide con la cuarentena/`match` en 100 %; ningún CCN con provisoria; cliente recibe "programado"/"entregado" | M | No |
| **7** | Cancelación desde LK (`cancelar_pedido`), export complementario con identidad (§4.8), `Zonas_Barrios_Alias` | Cancelación desde web borra tramo sin picking; CP post-export genera complementario con su NP/`Facturacion_NP` propia | M | Parcial |
| **8** | Chef (§4.11): inventario del proyecto Chef, grant/sellos, sucursal y condición en `v_pedidos_match_chef`, push `empresa='chef'` | Pedido Chef de prueba → tramo `4…` (clasificado CH en picking dual 437E) → Excel Chef → NP 4xxxx | M | No |
| **9** | Ampliar piloto a todos LK, apagar mail 12:30, "Cargar NP manual", `ppp_programar` también para `origen='manual'`, docs (GUIA, CLAUDE.md, `sql/`) | 4 semanas sin mail; Sheet apagado; los 2 reportes de ISIS dejan de bajarse | S | — |

---

## 8. Riesgos y mitigaciones

| # | Riesgo | Impacto | Mitigación |
|---|---|---|---|
| 1 | ISIS no devuelve la NP y el tipeo de "primera NP" se equivoca (lote intercalado con KRIKOS/manual, anulada) | Renombre a NP ajenas; cascada de 30 filas por NP mal | `confirmar_np_isis` valida cantidad y contrasta con la cuarentena del Sheet cuando existe (§3.4); **`np_rename_log` + `deshacer_np_isis`** (§3.7); pedir a ISIS P3 invertido (H6) |
| 2 | Provisoria confundida con NP real por humanos (9 dígitos) | Búsquedas y papel | Prefijo visual "NPV" en pantalla/remito; reimprimir tras renombre |
| 3 | Push del Sheet borra filas web | Pedidos desaparecen de PPP | Trigger BEFORE DELETE §6.1; test de la fase 1 |
| 4 | Doble entrada a ISIS (mail 12:30 + export) | NP duplicadas en ISIS | **Filtro del piloto en los dos lados** (§4.2, §6.2) + sello doble + el push respeta `enviado_a_compras_at` |
| 5 | Pedido editado/cancelado después del push | Se arma lo que no es | Editable hasta que tenga tanda con Virgilio como autoridad (§4.9); policies con sello; triggers de des-sello; Telegram si ya hay picking |
| 6 | `Pedidos_Web` nace con CRUD a anon (default privileges) | Fuga de datos comerciales (deuda, límite) | `REVOKE` explícito en el mismo DDL; vista sin `leyenda2`/`items` + RPC de supervisor (§4.13) |
| 7 | Regla "empresa por número" en ~20 lugares | Picking dual a góndola equivocada | **Regla por primer dígito en fase 1** (§3.2), equivalente para todas las NP existentes (0 diferencias); test 437E sobre `4…` de 9 dígitos |
| 8 | Sin `barrio` no hay `zona`; 61 valores de `zona_expreso` no matchean | Panel PPE `sinzona` se llena | `Zonas_Barrios_Alias`; corregir padrón LK |
| 9 | ISIS rechaza fecha de pedido de 12-14 días atrás, código real (437E) o `leyenda2` vacía | Import falla | Preguntas H3/H5/H7; Paso 0 sirve justamente para probarlo |
| 10 | Tope 18 no es de ISIS pero sí de algo (formulario/impreso) | Partición innecesaria o insuficiente | H4; mantener 18 hasta respuesta |
| 11 | `confirmar_np_isis` renombra a medias | Estado inconsistente | Una transacción; `np_rename_log`; test en branch |
| 12 | El renombre recalcula saldos de stock N veces | Locks y lentitud diaria | `ALTER TRIGGER … UPDATE OF` (fase 1); `vista_saldos_stock` idéntica antes/después como criterio |
| 13 | Push/cron cae en silencio (LK no tiene Telegram) o Virgilio caído apila jobs | Pedidos que no llegan; conexiones colgadas | `connect_timeout 10` + `statement_timeout 60s` + advisory lock; `sync_heartbeat` + `watchdog_frescura_datos` + `watchdog_syncs_externos` |
| 14 | Commit a medias del FDW (sin 2PC) deja fila remota sin sello local | Push trabado para siempre | Idempotencia por fila (`select` → `insert`/`delete+insert`/`update`) + excepción por pedido (§4.2.3) |
| 15 | Trigger fn nueva corriendo como `anon` | 42501 masivo: se rompen armados y eventos (incidente 28/08) | `SECURITY DEFINER` + REVOKE en todas (§4.13); `tests/anon-writes.cjs` en fases 1 y 5 |
| 16 | Ventana entre importar en ISIS y confirmar en Virgilio: el Sheet trae la NP real como `sheet` | Mismo pedido dos veces en PPP; se re-pickea | Cuarentena §3.4; `confirmar_np_isis` absorbe |
| 17 | Camión cargado con provisoria (p10 tilde→CCN 3,5 h) | CCN/CCR/CRN/remitos/cobranzas con `9…` de 9 dígitos | SLA + guard en Carga de camión + Telegram + renombre por regexp cubre lo que igual entró (§3.6) |
| 18 | `Entregas_Virgilio` con la misma línea dos veces (28 NP/748) | ISIS factura al doble | Agregación por `(np, cod_art)` en la RPC + ⚠ + bloqueo si suma > pedido (§4.6) |
| 19 | Filas web nunca salen de `PPP_*` | Monitor/PPP con cientos de tandas viejas | `ppp_archivar_web()` (§4.14) |
| 20 | NP web ausentes de `PPP_Entregados_Meta` | m³ despachados, reparto, entregados, inconsistencias, LK parciales | Meta web desde el tilde + `sync` con `DELETE WHERE origen='sheet'`; prerrequisito de fase 6 |
| 21 | `pa_entregas` (OSA/TyL) queda con provisoria | Cruce contra remito del cliente falla | Re-post `rename` desde `confirmar_np_isis`; 288/2533 fuera del piloto hasta desplegarlo |
| 22 | Tracking WhatsApp al cliente se apaga para el piloto | Cliente sin "programado"/"entregado" | `order_tracking` desde `pedidos_web_estado` antes de la fase 6 |
| 23 | `lk_ppp_reader` escribe una tabla que se vuelve picking | Fila inválida/maliciosa entra a la PPP | Validación en `aplicar_pedidos_web()` (§4.3.2); revoke de `PUBLIC` en DEFINER sensibles (aparte) |
| 24 | El repo copia comparte `localStorage`/IndexedDB con el actual si vive en el mismo origen | Colas offline y edits mezclados | Origen distinto (app.loekemeyer.com, 9073) o prefijo de claves (§12.4) |
| 25 | `Facturacion_NP` con CRUD abierto a anon (9 policies) | Cualquiera con la anon key marca facturada | Cerrar a JWT antes de colgarle `isis_export_id` (D15) |
| 26 | ISIS queda con "pedido pendiente" si la operadora importa sin facturar | Saldos comprometidos en ISIS | H1/H2; regla: lo exportado se factura ese día; `no_facturar_hasta` saca del export lo que no debe facturarse aún |
| 27 | El branch de Supabase nace con 60+ crons activos y URLs de LK prod en funciones | Pruebas de fase 5 disparan Edge Fns de LK reales; Telegram | Branch desde `pg_dump --schema-only` con `cron.job` desactivado y hosts reemplazados (§12.2) |

---

## 9. Preguntas

### 9.1 Para el dueño (cerradas; opción recomendada primero)

1. **Identidad:** ¿A — provisoria renombrada al importar (recomendada) / B — provisoria permanente + `np_isis`?
2. **Formato de provisoria y regla de empresa:** ¿numérica `9|4 + order_id(6) + parte(2)` = 9 dígitos **y** reescribir la regla de empresa a "primer dígito" en fase 1 (recomendada: la regla actual `> 90000` clasificaría toda provisoria Chef como LK) / no numérica `WL1336-2` (requiere reescribir los ~20 puntos igual, y más)?
3. **Partición:** ¿mantener el corte de 18 en Virgilio al ingresar, 1 tramo = 1 unidad de armado = 1 NP (recomendada) / armar el pedido entero y partir sólo al exportar (rompe el renombre 1:1)?
4. **Edición web:** ¿**editable hasta que tenga tanda**, con Virgilio como autoridad y rechazo avisado por Telegram/admin (recomendada: las 7 ediciones reales de 90 días fueron entre 1 min y 19 h después del pedido) / editable sólo hasta el push (≤5 min; bloquea 5 de 7 y no tiene procedimiento para el resto)?
5. **`fecha_entrega` al ingresar:** ¿vacía hasta programar, la solapa "A Programar" vuelve a servir (recomendada) / replicar la tentativa por zona del Excel?
6. **Programación:** ¿en la app con RPC por NP, `PPP_READONLY=false` en la copia, con `observaciones` y `no_facturar_hasta` editables (recomendada, es el marco (a)) / seguir en el Excel y que el Sheet empuje sólo tanda/fecha por NP (requiere tocar "Carga PPP.gs")?
7. **Artículo repetido en el pedido** (13 NP, p.ej. 574x4 + 574x2): ¿mantener dos líneas como hoy (recomendada, fidelidad) / consolidar?
8. **CP/RC después de exportar:** ¿bloquear en la app hasta la fase 7 y después export complementario **con identidad propia** (`np_map` parte 91..99, su NP y su `Facturacion_NP`) (recomendada) / bloquear para siempre?
9. **Mail a ventas@ con el Excel:** ¿no, sólo descarga (recomendada) / sí (Edge Fn + secretos Gmail en Virgilio)?
10. **`pctDto`:** ¿fijo "2% Descuento Web" como hoy (recomendada para el Paso 0) / vacío para súper con lista propia y "Pedir para" del admin (régimen)?
11. **Paso 0, alcance del DDL:** el Paso 0 crea 1 RPC + 1 helper en Virgilio y **ninguna tabla**. Para que `condPago` no salga vacío hace falta **1 columna** `condicion_pago_code` en `v_pedidos_match`/`lk_pedidos_match` (LK + Virgilio, misma sync de 15 min). ¿Autorizás esa columna ahora (recomendada: sin ella el Paso 0 mide un 0 % ficticio de condPago) / Paso 0 sin condPago?
12. **Estado "exportada" en el Paso 0:** ¿sin persistir (`localStorage` + `prueba=true` no aplica; recomendada bajo el marco (b)) / tabla `Facturacion_Export_ISIS` ahora?
13. **Cutover:** ¿piloto por lista de clientes con el filtro **en los dos lados** (recomendada; implica un cambio chico en `procesar-pedidos-db`, v10) / corte total un día?
14. **Chef:** ¿fase 8, después de LK estable y con las precondiciones de §4.11 (recomendada) / desde el arranque?
15. **Despliegue:** ¿copia del repo apuntando al **mismo** proyecto Supabase con feature flag y tablas nuevas aisladas, hosteada en app.loekemeyer.com (recomendada, §12) / proyecto Supabase nuevo / branch como entorno de operación?
16. **Colaterales:** ¿autorizás reportar/arreglar `sincronizar_ppp()` de LK (roto desde 26/08), cerrar el CRUD anon de `Facturacion_NP`, y normalizar `fecha_salida` a `date` en `trg_entregas_virgilio_dedup` (7411)? (no son de esta idea; sólo con permiso explícito)
17. **Papel:** ¿se acepta remito de armado y etiqueta ZPL con la provisoria "NPV" (recomendada) / reimpresión obligatoria al renombrar?
18. **SLA operativo (§3.6):** ¿confirmás que import + tipeo de la primera NP + factura + tilde se hacen en el mismo turno, antes de cargar el camión, y que los sábados los tramos web armados esperan al lunes (como hoy la factura)?

### 9.2 Para ISIS (Horacio Barbieri, Ticket 1159666)

- **H1.** ¿El importador de pedidos por Excel puede facturar en el mismo acto ("Emite Factura de los Pedidos = Sí" aplica a lo importado)? ¿Como cuenta corriente?
- **H2.** ¿Existe "importar y facturar" sin dejar pedido pendiente, o son dos pasos? ¿Qué pasa con una NP importada y no facturada ese día?
- **H3.** ¿Acepta un pedido con cantidades definitivas y fecha de pedido de 5-15 días atrás? ¿Impacta en stock comprometido o reportes?
- **H4.** ¿Hay tope de líneas por pedido en el importador (¿18?) o el tope es del formulario/impreso? ¿Y en la factura?
- **H5.** ¿`Numero OC` y `Leyenda 2` son obligatorios? ¿Se imprimen en la factura? (para usarlos como referencia externa: `Numero OC` = `np_prov`).
- **H6 (P3 invertido).** ¿Puede ISIS devolver la NP asignada por fila importada (archivo, JSON o API saliente), o al menos conservar la referencia externa en el reporte "Programación Diaria"?
- **H7.** ¿El maestro de artículos de ISIS tiene los códigos reales (437E, 438EL, 865ED)? La prueba concreta es el dry-run del Paso 0 con una NP que contenga 437E, 438EL y un E-sufijo de Chef. (Sin referencia a `Codigos_ISIS_Map`: es el mapa de insumos, no de venta.)
- **H8.** Comunicar: el JSON 98180/98187 y P2/P3/P5 quedan reemplazados; P1 pasa a ser "pedido armado listo para facturar" (Excel hoy, JSON como upgrade); P4 sigue igual.

---

## 10. Números que justifican

| Métrica (60 días salvo indicación) | Valor |
|---|---|
| Pedidos web LK | 411 (8,2/día); 7.803 líneas (156/día); mediana 15 líneas; máx 93 |
| Pedidos con ≥18 líneas → partición | 178 (43,3 %) → 636 N_Pedido/NP (×1,55) |
| Espera al cron 12:30 | mediana 12,9 h, p90 22,7 h, máx 24 h; 50,1 % entra después de las 12:30; 37 viernes tarde |
| Ciclo pedido → primer picking / → salida | mediana 11,8 d / 14 d (p90 19,7 / 21). Dominado por la cola de PPP; la idea ahorra las 11-13 h de espera + el trabajo humano de importar y bajar 2 reportes |
| Cobertura del canal web, **por empresa** | Programación: LK WEB 94 %, COT/KRIKOS 100 %, tipo vacío 0 % (Matiz); Chef WEB 86,7 %, COT 100 %, KRIKOS 0 % (Dorinka); total 90,7 %. Base: LK 95 %, Chef 71 % |
| Ediciones reales (`mode='edit'`, 90 d) | 7; entre 1 min y 19 h después del pedido; 2 dentro de 5 min |
| NP facturadas | 748 en 40 días = 18,7/día; 51,4 % con faltante; 95,0 % de cajas entregadas; 8,2 % de líneas con faltante → hoy 380 ajustes manuales en ISIS por período |
| **NP con la misma línea armada dos veces** | 28 NP / 71 pares `(np, cod_art)` en 60 días, todas facturadas; 59 pares con suma > pedido |
| **Tilde → primer CCN** | p10 3,5 h; 51 NP dentro de 2 h; 0 CCN antes del tilde; tilde a las 16-17 h en 517/748 |
| NP con 18-19 líneas | 256/801 (32 %); 198 grupos partidos / 494 NP; 194/198 terminan en parte <18 |
| ISIS conserva 1 N_Pedido = 1 NP | 09-01: 17 generadas = 17 NP (98652-98668); 09-02: 16 = 98669-98684 |
| CP después de facturada / RC después | 2 NP, 4 cajas / 0 |
| Canceladas | 13 (todas 11/08, "Cancelado por el cliente"); 0 NP perdidas en 60 d |
| Eventos con NP en `texto` antes del tilde | TAL 941, AUB 373, CP 184, **FCO 69**, NPD 36, FAL 2 |
| Puente FDW existente | 555/555 corridas ok en 7 días; 39 ms round-trip; 6,5 s por corrida por `batch_size=1`; sin `connect_timeout` |
| Datos para el Excel hoy en Virgilio (450 NP / 30 d) | fecha 100 %, cod 100 %, artículos+cajas 100 %, uxb 5.286/5.288 líneas, vend 90 %, sucursal **LK 99 % / Chef 8 %**, leyenda2 0 %, condPago 0 % sin la columna de D11 |
| `sucursal` ambigua | 22 cliente-día con 2 sucursales distintas en 90 días; 17/977 `ambiguo=true` |
| Clientes con espejo `pa_entregas` | 2533 (10 pedidos web, último 31/08), 288 (11) |

---

## 11. Paso 0 — botón Excel en Facturación (lo único autorizado)

**Aislado, sin efectos sobre el circuito actual.** Trabaja sobre NP que **ya están en `Facturacion_NP`** (NP reales de ISIS). ISIS ya tiene esas NP, así que el archivo **no se importa en producción** — y como es importable tal cual (mismas 12 columnas, `N_Pedido` 1..N, sin rastro de la NP real: ISIS numeraría 16 NP nuevas para pedidos ya facturados; objeción DA-6), el Paso 0 lleva **tres candados**: (1) archivo **`PRUEBA_NO_IMPORTAR_DD-MM-YY_HHMM.xls`**; (2) hoja "Resumen" con la primera fila **"NP YA NUMERADAS EN ISIS — SÓLO PRUEBA DE FORMATO"** y la lista de NP reales; (3) **botón oculto**: sólo con `?isisTest=1` en la URL **y** mail del dueño o de los 3 supervisores de `ppp_prog_write_sup` (no aparece en la pantalla diaria de la operadora hasta la fase 5). Sirve para (a) validar con Horacio/la operadora que ISIS importa un archivo post-armado con este formato (empresa de prueba o dry-run), (b) medir los gaps reales por empresa (§5), (c) dejar construida la RPC y el serializador que la fase 5 reutiliza tal cual.

### 11.1 Datos (RPC `facturacion_export_isis(p_nps text[], p_prueba boolean default true)`)

`SECURITY DEFINER SET search_path = public`, chequeo de supervisor (mail del JWT ∈ los 3 de `ppp_prog_write_sup` o `_facEsOperadora`), `REVOKE EXECUTE FROM anon`. Devuelve una fila por línea **ya agregada por `(np, cod_art)`**:

```sql
with ent as (                                   -- última fila armada por (np, cod_art); ⚠ si hubo más de una
  select distinct on (np, cod_art) np, cod_art, id, cajas_pedidas, cajas_entregadas,
         count(*) over (partition by np, cod_art)                       as n_filas,
         sum(cajas_entregadas) over (partition by np, cod_art)          as sum_ent
  from "Entregas_Virgilio" where np = any(p_nps) order by np, cod_art, id desc
), base as (select pedido np, min(fecha)::date fecha_min from "PPP_Base_Pedidos" where pedido = any(p_nps) group by pedido),
tramo as (  -- ítems de la NP para el desempate de sucursal por INCLUSIÓN (no igualdad)
  select np, string_agg(ltrim(cod_art,'0') || 'x' || cajas_pedidas::text, ',' order by ltrim(cod_art,'0')) items from ent group by np)
select f.np, e.cod_art,
       to_char(coalesce(b.fecha_min, f.fecha_salida::date),'DD/MM/YYYY')      as fecha,
       f.cod_cliente                                                           as cliente,
       coalesce(v.vend,'')                                                     as vend,
       lpad(regexp_replace(a.cod,'\D','','g'),3,'0') || upper(regexp_replace(a.cod,'\d','','g')) as articulo,  -- padCodArt
       least(e.cajas_entregadas, e.cajas_pedidas)                              as cajas,
       least(e.cajas_entregadas, e.cajas_pedidas) * u.uxb                      as uni,        -- null si no hay uxb
       coalesce(s.sucursal_entrega,'')                                         as sucursal,
       ''                                                                      as leyenda2,   -- no existe en Virgilio
       coalesce(s.condicion_pago_code,'')                                      as condpago,   -- columna nueva de lk_pedidos_match (D11); '' si no está
       '2% Descuento Web'                                                      as pctdto,
       ''                                                                      as numoc,
       s.ambiguo or s.n_pedidos_dia > 1                                        as suc_dudosa,
       (e.n_filas > 1)                                                         as re_armada,
       (e.sum_ent > e.cajas_pedidas)                                           as entregado_mayor_pedido,   -- bloquea hasta revisar
       (u.uxb is null) as sin_uxb, (v.vend is null) as sin_vend, (f.np ~ '^4') as es_chef
from "Facturacion_NP" f
join ent e on e.np = f.np and e.cajas_entregadas > 0
cross join lateral (select regexp_replace(e.cod_art,'\s+(LK|CH)$','') cod) a
left join base b on b.np = f.np
left join tramo t on t.np = f.np
left join clientes_vendedor v on v.cod_cliente = f.cod_cliente
left join vista_uxb_articulo u on u.cod = ltrim(a.cod,'0')                     -- la vista guarda '40', Entregas '040'
left join lateral (
  select m.sucursal_entrega, m.ambiguo, m.condicion_pago_code,
         count(*) over () as n_pedidos_dia
  from lk_pedidos_match m
  where m.cod_cliente = f.cod_cliente and m.empresa = case when f.np ~ '^9' then 'lk' else 'chef' end
    and m.fecha_pedido between b.fecha_min - 3 and b.fecha_min
  order by (position(t.items in m.items_string) > 0) desc, m.orden_en_dia limit 1) s on true
where f.np = any(p_nps)
order by f.np, e.id;
```

**Inventario exacto de lo que crea el Paso 0** (objeción DA-13): en Virgilio, **1 RPC** `facturacion_export_isis` (el desempate de sucursal va inline, sin helper `np_match_string`; el `CASE` de condPago desaparece) y **0 tablas, 0 columnas**; en LK, **opcional y sujeto a D11**, 1 columna `condicion_pago_code` en `v_pedidos_match` + `lk_pedidos_match` (con `sync_pedidos_match_virgilio()` copiándola). Sin D11, `condpago` sale `''` y se informa como gap. `N_Pedido` lo asigna el front en el orden del checklist (1..N por NP). **Chef queda fuera del Paso 0** (checkbox deshabilitado con "sin sucursal en 60/65") salvo que el dueño quiera ver el archivo igual.

### 11.2 UI

En el bloque `.fac-cierre` (index.html:3476-3486), arriba de "Terminé — Generar PDF", **oculto por defecto** (`?isisTest=1` + mail autorizado): botón **"⬇ Excel para ISIS (prueba)"**. Abre un overlay con el molde `.facfc-` (`facFCEnsureModal`): una fila por NP tildada hoy (`_facNpsHoyReal`, opcional "incluir de otros días" con selector de `fecha_salida`), checkbox marcado por defecto salvo Chef / `entregado_mayor_pedido`, columnas NP · Cod · Razón social · Líneas · Cajas ent. · ⚠ (sucursal dudosa / sin vend / sin uxb / sin condPago / **re-armada** / **entregado > pedido**). Botón "Generar Excel (N NP, M líneas)". Sólo supervisor/operadora (`requireSupervisor()` :24580).

### 11.3 Formato (port literal de `generateExcel`)

XML Spreadsheet 2003, mismos estilos `Default/Header/Data/Desglose`, hoja 1 `"DD-MM-YY 9Hs"` sin encabezado con las 12 columnas en orden, tipos `Number`/`String` con la regla `isNum` (un `String` que empieza con `0` — `029` — queda String), vacío → `<Cell/>`; hoja 2 "Resumen" con la leyenda de prueba, `Pedidos | NP` y "Desglose" `Cod Clte | Num Ped | Cant Items`. Archivo `PRUEBA_NO_IMPORTAR_DD-MM-YY_HHMM.xls`, `Blob` `application/vnd.ms-excel`, `a.download`. Función `facExcelIsisXml(rows, opts)` en index.html (~60 líneas), sin librería; en la fase 5 la misma función recibe `opts.prueba=false` y nombra `Pedidos_Armadas_DD-MM-YY_HHMM.xls`.

### 11.4 Estado "exportada"

- **Opción 0-a (recomendada bajo el marco (b)):** sin persistencia en backend. `localStorage` `vir_fac_isis_export` `{np: ts}` para pintar "📤 dd/mm hh:mm" en `facRenderTicked` en ese navegador, y la fecha/hora en el nombre del archivo.
- **Opción 0-b:** tabla `Facturacion_Export_ISIS` (+ `Lineas`, con `prueba=true`) ahora — contradice el marco (b) salvo autorización explícita (D12).
- El campo "primera NP de ISIS" y `confirmar_np_isis()` **no** van en el Paso 0.

### 11.5 Backend vs navegador y verificación

RPC en backend para los datos + serialización XML en el navegador. No Edge Fn (no hay mail). Verificación **automatizada, no a ojo** (objeción TE-15): `tests/fac-excel-isis.cjs` en `run.sh` con un fixture de 3 NP (una con faltante, una con artículo dual `437E`, una re-armada con línea doble) → XML esperado **byte a byte**, incluidos `029` como String, celda vacía `<Cell/>`, orden de columnas y el nombre `PRUEBA_NO_IMPORTAR_*`; más una corrida manual `select * from facturacion_export_isis(array['98684'])` sobre 3 NP conocidas comparada contra un `dry:true` de `procesar-pedidos-db` del mismo pedido (mismo orden de celdas y tipos).

---

## 12. Estrategia de despliegue: repo copia en paralelo (marco d)

### 12.1 Qué copia el repo y qué no

Copiar `Produccion-Virgilio` copia **sólo el front** (`index.html`, `sw.js`, `manifest.json`, `vendor/`, `/cervantes/`, `/admin/`, `/selector/`, `tests/`). **No copia**: las ~865 migraciones aplicadas (schema de Supabase), datos, triggers, 60+ crons, Edge Functions, vault, el rol `lk_ppp_reader` y el FDW de LK, ni el Apps Script. Si la copia apunta al mismo proyecto y escribe en `PPP_*`, `Facturacion_NP`, `Entregas_Virgilio`, `Movimientos_Stock`, `Registros_Produccion_Virgilio`, **pisa producción**; si apunta a otro proyecto, el depósito tendría dos verdades de stock y eventos.

### 12.2 Opciones de separación del backend

| Opción | Qué separa | Costo | Problema | Veredicto |
|---|---|---|---|---|
| **Branch de Supabase** | DB completa recreada desde migraciones; host propio | Pro plan + ~US$0,32/día por branch (**a verificar**); 0 branches hoy | Sin **datos** (sembrar), sin vault ni secretos de Edge Fns, sin FDW desde LK. **Y peor (objeción TE-12):** las migraciones incluyen `cron.schedule(...)` (`telegram-outbox-flush` `* * * * *`, `sync-clientes-dto-14d`, `sync-precios-venta`, `wa_barrido_avisos` → `…kwkclwhmoygunqmlegrg…/lk_factura-check` **prod**, `planify_*`) que **corren desde el primer minuto**, y `fn_facturado_notif_wa`, `wa_factura_notificar`, `ventas_mensuales_cod`, `fn_virgilio_entrega_to_formato` tienen la URL de LK prod adentro: insertar `Facturacion_NP` en el branch dispara Edge Fns de LK reales. `supabase/` del repo sólo tiene `functions/` (0 migraciones en git) → el drift prod↔branch no se diffea desde git | **Sí como laboratorio** de las fases 1/3/4/5, **pero creado así**: `pg_dump --schema-only` de prod → `update cron.job set active=false` → `sed` de `kwkclwhmoygunqmlegrg`/`hrxfctzncixxqmpfhskv` por un host inexistente → restore en el branch. Comparar `pg_dump --schema-only` prod vs branch antes de probar. A mediano plazo: hosts a una tabla `app_config` leída por las fns |
| Proyecto Supabase nuevo (clon) | Todo | Alto: recrear Edge Fns + secretos, vault, crons, rol y segundo FDW en LK, Apps Script no lo conoce, TWA/PWA re-apuntar | Dos verdades transaccionales desde el minuto 1 | No (salvo que 9073 decida cambiar de organización Supabase) |
| **Mismo proyecto, tablas/columnas nuevas aisladas + feature flag en la copia** | Sólo lo nuevo (§4.1); lo transaccional sigue siendo único | Bajo: DDL aditivo, inerte para la app vieja (`origen` default `'sheet'`) | El único conflicto es el reemplazo total del Sheet → resuelto por triggers (§6.1); el flag `FLUJO_DIRECTO` en la copia enciende PPP editable, checklist de export y confirmar NP; la app vieja sigue viendo las NP web como filas más de la PPP | **Recomendada** |
| Esquema/prefijo (`v2.*`) en el mismo proyecto | Tablas duplicadas | 19 vistas + 20 funciones que leen `PPP_*` habría que duplicar | Duplica exactamente lo que 7411 quiere eliminar | No |

### 12.3 Cómo conviven las dos apps con la opción recomendada

- La copia (`Produccion-Virgilio-v2`, o rama/carpeta según 2536) apunta al **mismo** proyecto y a las **mismas tablas transaccionales**: picking, armado, stock y eventos son una sola verdad; un operario puede usar cualquiera de las dos apps el mismo día. Lo que difiere está detrás de `FLUJO_DIRECTO`: PPP editable (§4.5), checklist de export + confirmar NP (§4.7), pantalla `v_pedidos_web_estado`/`np_map` con "Cancelar tramo" (§4.9), guard de CCN (§3.6).
- Los cambios de fase 1 que **no** van detrás del flag (regla de empresa por primer dígito, `emp-np.cjs`) se hacen en **los dos** repos: la app vieja también tiene que clasificar bien una provisoria si un operario la abre desde ahí.
- El cutover no es "app vieja → app nueva" sino **por cliente** en LK (§6.2). Cuando el piloto es "todos" y pasan N semanas, se archiva el repo viejo, se re-apunta TWA/PWA (`start_url`) y se apaga el Sheet.

### 12.4 Hosting de la copia y estado del navegador

- **Recomendado:** la copia nace en **app.loekemeyer.com** (Cloudflare Pages + Access, idea 9073; repo privado; deploy al pushear). Origen distinto → `localStorage`/IndexedDB/SW separados **gratis**: **19 claves** distintas de `localStorage` en index.html (**re-verificado** con `grep -o 'localStorage\.[gs]etItem("[^"]*"' | sort -u`), entre ellas `vir_ppp_edits`, `vir_ppp_cfg`, `vir_entregas_pend`, la cola `enqueueReport`, `_compPersist`, `crSaveChecked`, `appprod_ultima_planta`. La sesión Google del supervisor es por origen: agregar el nuevo origen al cliente OAuth. El TWA de Play Store sigue apuntando a la raíz de GitHub Pages hasta el final.
- **Si tiene que vivir en GitHub Pages** (mismo origen, p.ej. `/v2/`): prefijar las 19 claves (`vir2_`), nombre de IndexedDB y scope del SW; `sw.js` no cachea, así que no colisiona; `robots noindex` como `/admin/`.
- Supabase: `APP_VERSION`/`SW_VERSION` independientes; misma anon key; RLS y policies no cambian. `tests/run.sh` corre en el CI del repo copia con los tests nuevos (§7).

### 12.5 Orden concreto

1. Paso 0 en el repo actual (única cosa autorizada), con su test.
2. Cerrar y aprobar este plan (preguntas §9.1).
3. Branch de Supabase **creado con crons desactivados y hosts reemplazados** (§12.2) → fases 1, 3, 4, 5 de laboratorio con datos sembrados.
4. Merge del DDL aditivo a prod (fase 1) con backups; verificar que el push del Sheet sigue igual; regla de empresa en los dos repos.
5. Copia del repo en app.loekemeyer.com con `FLUJO_DIRECTO=false` (idéntica a la actual) → prueba de hosting/Access (9073).
6. Fase 2 en LK con piloto vacío → heartbeat; prueba de Virgilio caído.
7. `FLUJO_DIRECTO=true` en la copia + piloto de 2-3 clientes (fase 6) con sus prerrequisitos (Meta web, tracking LK, `rename` de `pa_entregas`).
8. Ampliar, Chef, apagar mail y Sheet, archivar repo viejo (fases 8-9).

---

## 13. Objeciones consideradas

42 objeciones de 3 críticos (OP = operación, DA = datos, TE = técnica). "Aceptada" = cambió el diseño (no sólo una nota). Donde dos objeciones se contradecían se dice cuál manda y por qué.

| Id | Grav. | Título corto | Qué se cambió / por qué se descarta | Sección |
|---|---|---|---|---|
| OP-1 | alta | Provisoria Chef `4…` clasificada como LK (`> 90000`) | **Aceptada** (re-verificado: `empresa_de_np`, `empresaDeNp`, `pkNpEsLoeke` usan `> 90000`). Regla por primer dígito en fase 1, equivalente sobre las 1.162 NP de `Facturacion_NP` (0 diferencias); test `emp-np.cjs` ampliado | §3.2, §7 f1, riesgo 7 |
| OP-2 | alta | Ventana de doble existencia entre importar en ISIS y tipear la primera NP | **Aceptada**: cuarentena de filas `sheet` que coinciden con un tramo `exportada`; `confirmar_np_isis` verifica contra `Facturacion_Export_Lineas` y absorbe, en vez de rechazar | §3.4, §6.1, riesgo 16 |
| OP-3 | alta | NP armadas dos veces: `cajas_entregadas` sumadas duplican la factura | **Aceptada** (71 pares / 28 NP re-verificados). RPC agrega por `(np, cod_art)`: última fila + `least(·, cajas_pedidas)` + ⚠ + bloqueo si la suma supera lo pedido; PK de `Export_Lineas` con `n_linea`. Coincide con DA-1 | §4.6, §11.1, riesgo 18 |
| OP-4 | alta | Las filas web nunca salen de `PPP_*` (se pierde la ventana del Excel) | **Aceptada**: estado `archivada` + cron `ppp_archivar_web()` (Prog al salir, Base a 60 días) + `PPP_Historico_Web` | §4.14, riesgo 19 |
| OP-5 | alta | `PPP_Entregados_Meta` no verá ninguna NP web | **Aceptada** como **prerrequisito de la fase 6**: columna `origen`, insert desde el tilde `facturada`, `sync` con `DELETE WHERE origen='sheet'` | §4.7, §6.4, §7 f5-f6, riesgo 20 |
| OP-6 | media | Espejo OSA/TyL `pa_entregas` nace con provisoria y el renombre no cruza | **Aceptada**: `confirmar_np_isis` re-postea `rename` por `ev_id` a `virgilio-entrega-sync`; 288/2533 fuera del piloto hasta desplegarlo. Coincide con DA-10 y TE-7 | §3.5, §6.4, §7 f6, riesgo 21 |
| OP-7 | media | Lista de eventos a renombrar incompleta (FCO, PPG) y frágil | **Aceptada** (FCO 69 en 60 d re-verificado): renombre por regexp sobre `texto` y `Movimientos_Stock.ref`, conteo por opción en `np_rename_log` | §3.1, §3.5 |
| OP-8 | media | El cliente puede borrar el pedido o reescribir el payload después del push | **Aceptada** en la **fase 2**: policies `orders_delete_own`/`orders_update_own_sheets` con `enviado_a_virgilio_at is null`. Coincide con TE-14 | §4.9, §7 f2 |
| OP-9 | media | Race de edición: el push lleva el payload viejo y `version>1` es código muerto | **Aceptada**: el push exige payload = `order_items` (hash), `edit_order_fast` des-sella + `version_virgilio+1`, triggers de des-sello en `orders`/`order_items`. Se **descarta** armar `items` desde `order_items` en vez del payload: el payload lleva `cod_original`/`uxb` tal como viaja hoy y verificado 0 diferencias en 90 d; el hash cubre la carrera | §4.2.2, §4.9 |
| OP-10 | media | El export complementario crea una NP de ISIS sin identidad en Virgilio | **Aceptada**: complemento como fila de `np_map` (parte 91..99, `complemento_de`), su `np_prov`, sus líneas, su `Facturacion_NP`; bloqueado en la app hasta la fase 7. Por eso la parte pasa a 2 dígitos (§3.2) | §4.8, D8 |
| OP-11 | media | `UNIQUE(np)` en Prog puede vaciar la PPP con el próximo push | **Aceptada** el índice único **parcial** (`where origen='web'`). Se **descarta** el trigger que rechace NP `sheet` duplicadas con PPE: agrega comportamiento al camino del Sheet que se quiere dejar intacto; el `max()` de hoy sigue tolerándolas. Coincide con DA-4 y TE-3 | §4.5, §6.1 |
| OP-12 | media | Los avisos WhatsApp de tracking (LK) se apagan para el piloto | **Aceptada** como prerrequisito de la fase 6: `pedidos_web_estado` (pull-back en el mismo cron del push, vía `v_np_map_lk`) alimenta `order_tracking`/`bot_pending_notifications` | §4.2.4, §6.4, riesgo 22 |
| OP-13 | baja | `Codigos_ISIS_Map` no es un mapa de artículos de venta | **Aceptada** (re-verificado: columnas `codigo_interno`/`nuevo_codigo`/`rubro`). Referencia sacada de H7 y §5; la prueba es el dry-run del Paso 0 | §5 col 5, H7 |
| DA-1 | alta | Paso 0: `Entregas_Virgilio` con la misma línea dos veces → Excel duplica cajas | **Aceptada** (misma evidencia que OP-3; además `fecha_salida` en dos formatos). `distinct on (np, cod_art) … order by id desc`; PK con `n_linea`; normalizar `fecha_salida` en el dedup queda como colateral (D16) | §4.6, §11.1, §2 |
| DA-2 | alta | La frontera tilde→camión no es de 39,7 h: p10 3,5 h, 51 NP en 2 h | **Aceptada** (re-verificado). SLA en el mismo turno, guard de CCN en la app + Telegram (sin `RAISE`, para no envenenar la cola offline), aviso en el cierre, regexp cubre lo que igual entró | §3, §3.6, §4.7, riesgo 17, D18 |
| DA-3 | alta | Sacar `Facturacion_NP` del tilde deja sin NP web al cierre, al PDF y a "Armar ruta" | **Aceptada**, y **manda sobre el diseño del borrador junto con TE-8** (que pedía lo contrario para el WhatsApp): `Facturacion_NP` se escribe en el tilde de siempre, post-factura, con la NP real → cierre/PDF/ruteo no cambian. Se **descarta** escribirla al tilde con la provisoria (propuesta alternativa de DA-3): dispararía `wa_np_facturado_trg` sin factura, que es exactamente TE-8 | §4.7 |
| DA-4 | alta | `UNIQUE(np)` en Prog rompe el push del Sheet (lote de 500) | **Aceptada**: índice único parcial (ver OP-11) | §4.5 |
| DA-5 | alta | Las ediciones reales pasan horas después: "hasta el push" las bloquea todas | **Aceptada** (re-verificado: 1 min a 19 h; 2 de 7 dentro de 5 min). "Editable hasta que tenga tanda" desde v1, Virgilio como autoridad, `rechazado` + Telegram, "Cancelar tramo" para la operadora. D4 recomienda esto | §4.9, D4 |
| DA-6 | media | El botón del Paso 0 vive en la pantalla diaria y el archivo es importable tal cual | **Aceptada**: `PRUEBA_NO_IMPORTAR_*`, leyenda en "Resumen", botón oculto (`?isisTest=1` + mail autorizado) hasta la fase 5 | §11 |
| DA-7 | media | condPago del Paso 0: el mapa de textos no resuelve ~30 % y el código ya viaja en el payload | **Aceptada** (re-verificado: `condicion_pago_code` en 100 % de los pedidos; textos sin tasa). Columna `condicion_pago_code` en `v_pedidos_match`/`lk_pedidos_match`; mapa de textos eliminado; sujeto a D11 | §5 col 10, §11.1, D11 |
| DA-8 | media | Chef en el Paso 0 sale sin sucursal en >90 % y el plan lo tapa con el 93 % global | **Aceptada** (50/57 sin sucursal; 65 NP Chef de 450). Cobertura por empresa en §5 y §10; Chef fuera del Paso 0; sucursal en `v_pedidos_match_chef` como precondición de la fase 8 | §5, §10, §4.11 |
| DA-9 | media | No hay dónde escribir "FACTURAR EN SEPTIEMBRE" / "11:00Hs" | **Aceptada** (re-verificado en la tabla): `ppp_programar()` con `p_observaciones` y `p_no_facturar_hasta`; el checklist de export excluye lo que no debe facturarse aún | §4.5, §4.7, §4.12 |
| DA-10 | media | LK sí ve la provisoria: `trg_virgilio_entrega_to_formato` es INSERT-only | **Aceptada** (ver OP-6) | §3.5 |
| DA-11 | media | Desempate de sucursal por `match_string` falla con pedidos partidos | **Aceptada**: inclusión de los ítems del tramo en `items_string` + ⚠ siempre que haya >1 pedido del cliente ese día; en régimen `np_map` | §5 col 8, §11.1 |
| DA-12 | baja | "Bajar 2 reportes" no desaparece mientras exista una NP no web; "Cargar NP manual" sin definir | **Aceptada**: §1.1 fila 5 "queda hasta fase 9"; formulario mínimo definido (NP real, cod, líneas; m³/uxb/zona por la misma función), lo carga quien carga en ISIS | §1.1, §4.10 |
| DA-13 | baja | "Ninguna tabla nueva" en el Paso 0 no era cierto (`cond_pago_codigo`, `np_match_string`) | **Aceptada**: inventario exacto (1 RPC, 0 tablas, desempate inline; la columna LK sólo con D11) | §11.1 |
| TE-1 | alta | El sello doble no evita la doble entrada: el filtro del piloto vive sólo en el push | **Aceptada**: filtro en `procesar-pedidos-db` v10 + `enviar_pedidos_main()` corre el push antes + el push respeta `enviado_a_compras_at` | §4.2, §6.2, riesgo 4 |
| TE-2 | alta | El trigger BEFORE INSERT que re-mapea por `np_map` es el patrón del incidente 28/8 | **Aceptada**: todas las trigger fns nuevas `SECURITY DEFINER` + `REVOKE EXECUTE` sobre la fn; `tests/anon-writes.cjs` como criterio de listo en fases 1 y 5 | §4.13, §7, riesgo 15 |
| TE-3 | alta | `UNIQUE(np)` convierte un duplicado del Excel en tabla vacía | **Aceptada**: índice único parcial (ver OP-11) | §4.5 |
| TE-4 | alta | El push no es idempotente ante un commit a medias del FDW | **Aceptada**: por fila, `select` remoto → `insert` / `delete+insert` / `update`, bloque `exception` por pedido, `pedidos_web_push_log`. Se ajusta el "delete+insert" a secas: si la fila remota ya está `aplicado`, un delete la resetearía a `nuevo` y la volvería a aplicar; ahí va `update` con `version+1` | §4.2.3, riesgo 14 |
| TE-5 | alta | Sin `connect_timeout` ni tope, un Virgilio caído apila jobs en LK | **Aceptada** (re-verificado: `srvoptions` sin `connect_timeout`/`batch_size`): `ALTER SERVER … connect_timeout '10', batch_size '100'`, `statement_timeout 60s`, `pg_try_advisory_lock`; prueba de Virgilio caído en fase 2 | §4.1, §4.2.1, §7 f2, riesgo 13 |
| TE-6 | media | Rollback "en 5 minutos" no existe para lo ya empujado | **Aceptada**: RPC LK `rollback_pedidos_web()` en una transacción FDW + runbook + heartbeat como confirmación de cron apagado | §4.9, §6.3 |
| TE-7 | media | El renombre olvida lo que salió con la provisoria y recalcula stock N veces | **Aceptada** (re-verificado: `trigger_actualizar_saldo_stock` AFTER INSERT OR UPDATE sin `OF`; la fn sólo lee `cod_art, empresa, delta, deposito`): `ALTER TRIGGER … UPDATE OF` en fase 1 + re-post de `pa_entregas` | §3.5, §7 f1, riesgo 12 |
| TE-8 | media | `confirmar_np_isis` inserta `Facturacion_NP` con `facturado_at=now()` antes de la factura | **Aceptada**: dos estados `importada`/`facturada`; `Facturacion_NP` recién en el tilde post-factura (ver DA-3). Bonus: el drenaje de stock ya no se mueve al backend en esta idea | §4.7 |
| TE-9 | media | Las trigger fns de coexistencia corren como el invocador y `pppSubir` las va a pisar | **Aceptada**: `SECURITY DEFINER` + REVOKE en `ppp_protege_origen_web` y `ppp_cuarentena_sheet`; checklist del runbook en fase 1 | §6.1, §4.13 |
| TE-10 | media | `Pedidos_Web` revocada contradice la pantalla de errores y expone datos comerciales | **Aceptada**: vista `v_pedidos_web_estado` sin `leyenda2`/`items` + RPC con chequeo de supervisor; `np_map` igual; sin policy directa | §4.1, §4.13 |
| TE-11 | media | `lk_ppp_reader` pasa a alimentar una tabla que se convierte en NP sin validación | **Aceptada** en el consumidor: `aplicar_pedidos_web()` valida cliente, artículos, cajas, tope, ventana de `order_id`. El `REVOKE … FROM lk_ppp_reader` sobre todas las fns se **matiza**: el grant es de `PUBLIC` (238 fns por herencia), así que hay que revocar de `PUBLIC` fn por fn — proyecto aparte, no bloquea | §4.3.2, §4.13, riesgo 23 |
| TE-12 | media | El branch nace con 60+ crons activos y URLs de prod hardcodeadas; sin `supabase/migrations` | **Aceptada**: branch desde `pg_dump --schema-only` con `cron.job` desactivado y hosts reemplazados; comparar schema prod vs branch; `app_config` a mediano plazo | §12.2, §12.5, riesgo 27 |
| TE-13 | media | Chef depende de un tercer proyecto que nadie controla y el mail de Chef no lo sella LK | **Aceptada**: precondiciones explícitas de la fase 8 (inventario del proyecto Chef, grant/sellos, sucursal y condición en la vista); Chef fuera del piloto **en los dos lados** | §4.11, §6.2, §7 f8 |
| TE-14 | baja | `orders_delete_own` deja borrar un pedido ya empujado | **Aceptada** (ver OP-8); la cola `pedidos_web_cancelados` se **descarta**: con la policy el borrado post-push ya no existe, y la cancelación va por `cancelar_pedido` + `estado='cancelado'` en el push | §4.9, §7 f2 |
| TE-15 | baja | El plan no suma nada a `tests/run.sh` y el Excel se valida a mano | **Aceptada**: `fac-excel-isis.cjs` (fase 0), `emp-np.cjs` ampliado y `anon-writes.cjs` (fase 1), `np-particion.sql` (fase 3), `ppp-programar-rpc.cjs` (fase 4); `run.sh` en el CI de la copia | §7, §11.5, §12.4 |
| TE-16 | baja | Backup "antes de cada DDL" no cubre el UPDATE masivo diario del renombre | **Aceptada**: `np_rename_log` en la misma transacción + `deshacer_np_isis()`; ese log es el backup del protocolo | §3.7, §6.3, riesgo 1 |

**Contradicciones resueltas:** DA-3 (escribir `Facturacion_NP` al tilde, aunque sea con provisoria) vs TE-8 (no escribirla hasta la factura): se toma la **consecuencia** de DA-3 (cierre/PDF/ruteo no pueden quedar sin NP web) y el **mecanismo** de TE-8 (dos estados, `Facturacion_NP` sólo con factura real); el SLA de DA-2 es lo que hace compatibles a los dos. OP-11 vs TE-3 sobre el trigger de duplicados `sheet`: manda TE-3 (no agregar comportamiento al camino del Sheet). OP-9 "items desde `order_items`" vs fidelidad del payload: manda el payload con hash de consistencia.

---

## Anexo — puntos del código que toca cada fase (referencia rápida)

| Archivo / objeto | Líneas / nombre | Fase |
|---|---|---|
| `index.html` Facturación | `.fac-cierre` 3476-3486; `facBtnCierre` 3481/33687; `facRender` 33640-33797; `facRenderTicked` 33617; `_facEsOperadora` 33817; `facTickNP` 34004-34121; `facRevertir` 34139; `generateFacturacionPDF` 34303; `facAuthWriteHeaders` 33798; `Facturacion_Cierres` 4129 | 0, 5 |
| `index.html` PPP | `PPP_READONLY` 28019; `pppRenderProg` 28099; `_pppComputeSugerencia`; `pppAutoBaseN`; `_pppScheduleTandas` 26339; `pppConfirmarProgramar` 26392; `PPP_EDITS_KEY`/`PPP_CFG_KEY` 26032/26057; `pppSubir` 28311; `pppFindNpPdf`; `pppTandaM3Map` 25602; `_pppMetaEntSet` 25627 | 4, 5, 9 |
| `index.html` stock/drenaje | `stockSalidaFacturadoNP` 22668 (**no se toca** en esta idea); `stockDrenarCPFacturado` 22699 | — |
| `index.html` empresa por NP | `empresaDeNp` 7326; `pkNpEsLoeke` 7990; `pkCodEmpresa`; `_pppOrderDirsForNp` | **1** (regla por primer dígito, en los dos repos) |
| `index.html` carga camión / CP / ruteo | pantalla CCN (guard NPV); CP/RC (bloqueo sobre exportadas); `openRuteo` 27909; `stkOpenNpFaltan` 14123 | 5, 7 |
| `index.html` monitor | `fetchMonitorFromSupabase` 30440 (lee tandas: archivado §4.14) | 5 |
| Virgilio SQL | `empresa_de_np()` (`sql/empresa_de_np.sql`), `actualizar_saldo_trigger`/`trigger_actualizar_saldo_stock`, `trg_facturacion_np_validar`, `revertir_drenaje_facturado`, `wa_np_facturado_trg`, `fn_virgilio_entrega_to_formato`, `entregas_virgilio_dedup`, `sync_ppp_entregados_meta()` (`sql/sync_ppp_entregados_meta.sql`), `vista_np_faltantes_secuencia`, `ppp_autozona`, `fn_norm_ppp_*`, `watchdog_syncs_externos`, `watchdog_frescura_datos`, `tg_enqueue` | 1, 3, 5 |
| LK SQL | `submit_order_fast`, `edit_order_fast`, policies `orders_delete_own`/`orders_update_own_sheets`, `sync_pedidos_match_virgilio` + `v_pedidos_match`/`v_pedidos_match_chef` (`sql/pedidos_match_virgilio.sql:172-215`; columna `condicion_pago_code`), `enviar_pedidos_main`, `postear_envio_pedidos`, cron `procesar-pedidos-web`, `pg_foreign_server virgilio_db` | 0 (D11), 2, 8, 9 |
| LK front | `script.js:1803-1818` `isOrderEditable`; `:7038-7318` `_submitSingleOrder`; `admin.js:2536-2556` `parseTracking` | 2, 6, 7 |
| Edge Fns LK | `procesar-pedidos-db` v9 → **v10** (filtro piloto; `processOrders`/`generateExcel`/`statusFields` se portan); `virgilio-entrega-sync` (acción `rename`) | 2, 5 |
| Apps Script | `apps-script/sync-ppp-supabase.gs:61-108` (`_pppSupaReplaceAll_`); "Carga PPP.gs" fuera del repo — **no se toca** | — |
| Tests | `tests/run.sh`; nuevos `fac-excel-isis.cjs`, `np-particion.sql`, `ppp-programar-rpc.cjs`, `anon-writes.cjs` (1817); `emp-np.cjs` ampliado | 0, 1, 3, 4 |
| Docs a actualizar al construir | `GUIA-PROYECTO.md` (PPP, Facturación, estados de `np_map`, `lk_pedidos_match` "única tabla" → dos), `CLAUDE.md`, `docs/CHECKLIST-MIGRACIONES.md` (9670), `sql/` nuevos: `pedidos_web.sql`, `np_map.sql`, `facturacion_export_isis.sql`, `confirmar_np_isis.sql`, `ppp_programar.sql`, `ppp_archivar_web.sql`, `ppp_cuarentena_sheet.sql`; LK `sql/sync_pedidos_web_virgilio.sql`, `sql/rollback_pedidos_web.sql`; `docs/integracion-isis.md` (P1-P5 redefinidos) | cada fase |
