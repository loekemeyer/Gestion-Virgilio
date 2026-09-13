# Triage de problemas abiertos — `github_repo_problemas` — 2026-09-13

Agente de solo lectura. Nada se tocó: ni base, ni repos. Todo lo de abajo está **re-medido hoy**
(SELECT sobre `hrxfctzncixxqmpfhskv`, lectura de LK `kwkclwhmoygunqmlegrg`, `get_edge_function`,
grep en `/home/user/Gestion-Virgilio` y `/home/user/Gestion-Productiva-2.0`).

**20 abiertos** (la consigna decía 19): 18 de `gestion-virgilio`, 1 de `pagina-lk-copia` (16),
1 de `gestion-productiva-2.0` (46). El 198E no aparece en ningún abierto (sólo se lo nombra dentro
de la descripción del 62); no se investigó.

Clases: **A** código en el repo · **B** UPDATE/DDL con SQL listo · **C** decisión/dato del dueño o
Luis · **D** ya no vigente → cerrar/descartar · **E** fuera de alcance.

## Resumen

| id | sev | título corto | clase | una línea |
|---:|---|---|:-:|---|
| 62 | alto | Cencosud/Dorinka sin lista de precios | **C** | Hoy **0 líneas sin precio** (antes 391): la cascada v16.06 cae a la lista general LK y al último precio facturado. Las 254 líneas Cencosud / 128 Dorinka se valorizan, pero **con un precio que no es el de la cadena**. Falta la lista (no está ni en LK). |
| 65 | alto | Lista de súper de LK no llega a Gestión | **A+C** | Sigue sin sync (ninguna función escribe `cobranzas_precios_super`; `sync-precios-venta` no la toca). LK: `precios_super.precio` (9 cadenas). Bloqueo: La Anónima neto −19% que LK no tiene configurado. |
| 110 | alto | Depósito inventa códigos en racks | **B+C** | Bloque 1 hecho (546V en 3 posiciones, 891 cajas, alta en Insumos) **pero `Movimientos_Stock` 546V = 0**: sigue sin contarse. 809E AD06 (360 CH) + AE11 (64 LK) siguen como `809E-QUESO/PIZZA`. 1000900 y 522S sin alta. **1.555 cajas invisibles.** |
| 20 | alto | Credenciales hardcodeadas en 11 Edge Functions | **E** | Dueño: *"No la cambiemos por ahora"*. Avance real hoy: 2 de 11 (`leer-factura` → tapón 410, `leer-produccion-foto` → sólo env; GP2 `8e7dfce`). Quedan 9: token Meta en 3 de GV, 6 de LK. |
| 16 | alto | Vercel no deploya `main` de LK | **E** | Sin acceso a Vercel ni al repo LK desde acá. Sólo el dueño (Redeploy). Se confirma cuando `loekemeyer.com/version.js` ≥ 2.3.375. |
| 74 | alto | Dos padrones de empleados | **C** | Sigue: 29 legajos comunes, **18 con otro nombre**, 3 legajos repetidos en `Empleados` (268/274/282), 2 `employee_id` con doble fila de liquidación. Hay que decidir cuál padrón manda. |
| 75 | alto | Asistencia en dos sistemas | **C** | Sigue: 12 pares legajo+fecha desde 01/04, **12/12 salida distinta**, 10/12 entrada NULL en Planify. Liquidación sigue mirando `asistencia_diaria`, no la fichada. |
| 77 | alto | `cod_cliente` sin empresa (252 ambiguos) | **A+C** | Estructura igual (sin columna empresa). Con el padrón que hay hoy en GV (`GV_Clientes_Whatsapp`, 358 filas) sólo se ven **13 ambiguos**; los 252 se midieron contra LK+Chef completos. Lectores: `gv_cuar_contacto_lote`, `vista_avisar_programacion`, `vista_plata_perdida`, `index.html`. |
| 78 | alto | Flejes: 47/54 stocks iniciales distintos | **C→D?** | Sigue 47/54 (6 con madre 0 y planta >0). **Nadie lee `flejes_stock_planta`** (0 funciones, 0 vistas, 0 en front de GV y GP2). `Flejes."Stock Inicial"` sólo lo lee el admin viejo (entero) y `v_grj_componentes_con_peso`. GP2 tiene su propio inventario. Probable huérfana. |
| 79 | alto | Facturas controla contra precios de abril | **D** | `Precios_Proveedores` sigue congelada (753 filas, 09/04). Pero la pantalla **se borró en GP2** (`8e7dfce`, en origin/main) y en el menú GP2 la reemplaza `Compras/LecturaFacturas_GP2.html`. Las copias en `cervantes-admin/{entero,gp2}/Facturas` no cuelgan de ningún menú. → `descartado` (pantalla fuera de uso). |
| 46 | medio | 7 artículos con parte en receta sin rama de ruta | **D** | La consulta informativa de `db/verificar.sql` da hoy **2 pares, los dos de "Fábrica"** (570/858 · E6), que son legítimos. 103/A11, 120/A9, 564/PC12, 508-518-708/D13 y el doble A4 del 547 **ya no están**. → `corregido`. |
| 53 | medio | Parseo ISIS: `precio_unit` y descripción mal | **E** | El consumo en Gestión ya se arregló (v16.59). Lo que queda es **el parser, que no vive en la base, ni en Edge Functions, ni en el repo** (ingesta por archivo → `ingesta_log`). Hoy no cuadran 59.537/246.899 (LK) y 17.241/67.630 (Chef). |
| 59 | medio | A Facturar con 168 cajas de más | **C** | Sigue: saldo 1.623 vs 1.456 esperadas = **167 sobran**. No trazable por NP (refs mezcladas). Necesita conteo físico o decisión de ajuste. |
| 80 | medio | Espejo ISIS congelado + 14 líneas duplicadas | **B+E** | 14 pares `(pedido, articulo)` siguen. Espejo congelado 04/09 (NP máx 98704) = decisión del dueño (E). SQL de dedupe abajo; 5 pares con cajas distintas necesitan elegir. |
| 81 | medio | `db_n8n_espejo` sin 22 cierres de Cervantes | **C** | Sigue: **21 cierres** (ventana ±3 min) sin fila en el espejo sobre 1.775 en 90 días. No hay trigger madre→espejo; lo escribe la app. Premio/reporte salen del espejo. |
| 82 | medio | `public.Matrices` sin `Uni_X_Golpe` / `Tiempo_Historico` | **B** | Sigue: **114/114 UxG=0** en public (GP2 los tiene), **14** con TH=0 que GP2 sí tiene, **65 eventos** en 90 días sin benchmark. SQL listo abajo. 1 par con TH contradictorio → decidir. |
| 83 | medio | Copias congeladas (3 tablas) | **D+C** | `Insumos_Ubicaciones_Unificadas` y `Ubicaciones_Articulos`: **0 lectores** (funciones, vistas, front) → huérfanas, descartar. `GP2.entrega_prov_at` 125 vs public 150: el admin viejo **sigue cargando** (15 filas / 576 cajas después del 31/08) → decidir dónde se carga. |
| 84 | medio | Góndola: mapa vs capacidad, 107 celdas | **C** | Sigue igual: 107 (solo_capacidad 70, solo_mapa 28, sector_inexistente 9). `GV_Lugar_Item.cajas_max` NULL en 782/782. Luis decide cuál manda. SQL de backfill opcional abajo. |
| 88 | medio | 439E Chef sin lugar en góndola | **C→B** | Sigue: `gv_lugar_articulo` sólo LK (H33, H34, Ñ54); stock CH 8 terminado + 8 a_facturar. Falta que Luis diga el sector; el INSERT es una línea. |
| 111 | medio | Plan decía migrar `Racks_Planimetria` | **D** | Ya corregido en `docs/PLAN-SACAR-SUFIJO-EMPRESA.md` (commit `f11af92`, v16.63, **en origin/main**). → `corregido`. |

**Por clase:** A 2 (65, 77 — ambos con una decisión colgando) · B 3 (82, 110, 80) · C 8 (62, 74, 75,
59, 81, 84, 88, 78) · D 4 (46, 79, 111, 83-parcial) · E 3 (16, 20, 53).

**Los 3 con más plata:** (1) **110** — 1.555 cajas que el stock no cuenta (546V 891 + 809E 424 +
1000900 160 + 522S 80); (2) **62** — 382 líneas / 34 NP de Cencosud y Dorinka facturándose con la
lista general LK en vez de la de la cadena (diferencia desconocida hasta tener la lista); (3) **65** —
un sync ciego subiría 19% La Anónima ($67.095 vs $54.347 en la lista) y 10% Diarco.

---

## Detalle por id

### 62 · Cencosud y Dorinka sin lista de precios — **C**

- **Medido hoy:** `gv_vista_facturacion_neto_items` tiene **0 líneas `sin_precio`** de 10.590 (el registro decía 391 al 12/09). Cencosud: 254 líneas, 21 NP, `precio_lista` NULL = 0. Dorinka: 128 líneas, 13 NP, NULL = 0.
- **Por qué:** la cascada v16.06 (`vista_facturacion_neto_items`) es `COALESCE(ps.precio_unit, pcl.precio_unit, pc.precio_unit, pv.precio_unit, pfc.precio_neto)` = lista súper → precio por cliente → lista Chef → **lista general LK** → **último precio facturado** (`GV_Precio_Facturado_Cache`, 103 filas Cencosud / 38 Dorinka). Ej.: NP 44612 · 504 $3.290 y 523 $7.830 = exactamente `precios_venta` (lista general).
- **Sigue vigente en lo esencial:** `cobranzas_super_cadena` marca a las dos con `usa_lista_general=false` y `cobranzas_precios_super` tiene **0** códigos para ambas. Y **LK tampoco las tiene**: `precios_super.precio` sólo tiene 9 cadenas (abastecedor, alberdi, coto, dia, diarco, inc, laanonima, libertad, toledo). No hay de dónde sincronizar.
- **Qué necesito (C):** la lista de Cencosud (hoja "Jumbo Krea T") y de Dorinka (hoja "WMart Chef") — o la decisión de que **sí** se facturan a lista general (entonces `update cobranzas_super_cadena set usa_lista_general=true where super_key in ('cencosud','dorinka')` y el problema se cierra como "decisión").
- **Ojo:** el 439E en NP 44619 (Dorinka, factura por Chef) sigue sin estar en `precios_venta_chef` — mismo patrón que el 198E (no investigado por consigna).

### 65 · La lista de súper de LK no llega sola a Gestión — **A + C**

- **Medido hoy:** ninguna función de GV escribe `cobranzas_precios_super` (lectores: `cobranzas_valorizar_np`, `gv_ppp_web_valor_items`, `cobranzas_resumen`, más la vista de facturación). `sync-precios-venta` v13 sólo trae `products`, `item_precios(manual)`, Chef `products`, `loke_products`. No hay FDW ni foreign tables.
- **LK:** schema `precios_super` con `lista(super_key, lista_fecha, updated_at)`, `precio(super_key, cod, price)`, `cadena(… item_discount, usa_lista_general …)`, `precio_hist`. 9 cadenas, 483 precios, última carga Diarco 11/08.
- **Comparación LK vs GV:** 7 coinciden; GV tiene `gm` (37) y `gigot` (2) que LK no tiene; Diarco LK $24.883 vs GV neto con `item_discount 0.10`; La Anónima LK $67.095 vs GV `item_discount 0.19` (GV lo tiene en `cobranzas_super_cadena`, LK no).
- **A (código):** extender `supabase/functions/sync-precios-venta/index.ts` con un paso 5: `fetchAll(LK_URL, LK_KEY, "precios_super.precio"…)` (PostgREST expone schemas sólo si están en `db-schemas`; si no, pasar por una RPC de LK que devuelva `super_key, cod, price`) + `precios_super.cadena.item_discount`, y upsert en `cobranzas_precios_super(super_key, nc, precio_unit)` con `precio_unit = price * (1 - item_discount)` y `nc = cob_norm_cod(cod)`. Reconciliar sólo las cadenas que vengan de LK (no borrar `gm`/`gigot`).
- **C (decisión):** (1) confirmar que el 19% de La Anónima es un descuento de lista y cargarlo en LK `precios_super.cadena.item_discount` (si no, el sync la sube 19%); (2) `gm` y `gigot`: ¿se cargan en LK o quedan sólo en GV?

### 110 · El depósito inventa códigos en los racks — ⚠ MAL PLANTEADO, re-diagnosticado 2026-09-13

> **El título de este problema hace pensar en un caso puntual del 809E. No lo es.**
> `Racks_Planimetria` y `Movimientos_Stock` divergen en **16 de los 50 artículos** que tienen
> racks, **en las dos direcciones**: el rack dice **2.308 cajas de más** en unos y el stock dice
> **1.178 de más** en otros (plani 16.514 vs stock 15.811, neto **703**). El 809E es uno de los 16.
> Nada de esto se resuelve cargando un ajuste suelto.
>
> | cod | pos | plani | stock | dif | dónde |
> |---|--:|--:|--:|--:|---|
> | `505I` | 1 | 336 | 1.310 | **−974** | AD09 (LK 336) |
> | `546V` | 3 | 891 | 0 | **+891** | AD12 189 · AE09 351 · X13 351 |
> | `809E` | 3 | 760 | 336 | **+424** | AD06 (CH 360) · AD5 (CH 336) · AE11 (LK 64) |
> | `437E` | 5 | 432 | 189 | **+243** | AC04 105 · Z05 120 · **Z07 69 ×3** |
> | `523C` | 1 | 240 | 0 | **+240** | W1 (LK 240) |
> | `1000900` | 1 | 160 | 0 | **+160** | Y4 (LK 160) |
> | `816E` | 3 | 368 | 488 | **−120** | AB05 184 · AD03 128 · X12 56 |
> | `056E` | 1 | 216 | 300 | **−84** | W03 (LK 216) |
> | `522S` | 1 | 80 | 0 | **+80** | W04 (LK 80) |
> | `438E` | 2 | 156 | 90 | **+66** | AD11 78 · X11 78 |
>
> (siguen 585E 42, 541E 42, 106E 36, 725E 36, 702E 24, 589E 24)
>
> **Qué pasó de verdad con el 809E** — leyendo los 14 movimientos uno por uno. El **04/08** hubo
> una **migración**: el stock de racks pasó del modelo viejo (`Mixto` + depósito `racks_ch`) al
> nuevo (`racks` + columna `empresa`). Se ve en el 437E, que ese día se partió en LK 258 + CH 36.
> Para el 809E se fijó **CH = 336** (que es AD5) y **LK = 48**, y se puso `racks_ch` en 0 con el
> ref *"pedido del usuario"*. **AD06 (360) se quedó afuera de esa migración** y AE11 se cargó
> como 48 cuando el rack dice 64; el 20/08 esos 48 salieron como *"rack s/sector"*.
> O sea: **no fue una decisión de que la mercadería no estuviera — fue una migración incompleta.**
> ⚠ El dueño no tiene por qué recordarlo: el ref decía sólo "pedido del usuario".
>
> **Correcciones a lo que decía la versión anterior de esta ficha:**
> 1. ~~"meter los 360 en `racks` podría contarlos dos veces"~~ — **falso**. `racks_ch` es una
>    **columna aparte** en `vista_saldos_stock`, no se suma con `racks`, y el 809E ahí está en 0.
> 2. `racks_ch` **está muerto**: 5 movimientos en total, 3 artículos, el último el 10/08 (contra
>    379 movimientos y 83 artículos de `racks`, vivo al 11/09). El modelo bueno es `racks` +
>    `empresa`. ⚠ **Pero tiene un saldo vivo varado: 444 cajas de `712E`**, de un conteo del
>    08/07 que nadie neteó, en una columna que no mira nadie.
>
> **Lo único de todo esto que NO necesita mirar el depósito** (y por lo tanto se puede hacer un
> domingo): `Z07` / `437E` tiene **3 filas idénticas** en `Racks_Planimetria` (ids 241, 242, 259,
> 69 cajas cada una) — y es el **único** duplicado (sector, cod_art) de toda la tabla. Sacando
> las dos de más, la divergencia del 437E baja de 243 a **105**, que es exactamente la posición
> `AC04`. No cierra del todo, pero 138 de esas 243 cajas **no existen: son una fila repetida**.
>
> ```sql
> create table zz_backups."GV_Backup_Racks_Plani_Z07_20260913" as
>   select * from public."Racks_Planimetria" where id in (242, 259);
> alter table zz_backups."GV_Backup_Racks_Plani_Z07_20260913" enable row level security;
> revoke insert, update, delete, truncate
>   on zz_backups."GV_Backup_Racks_Plani_Z07_20260913" from anon, authenticated;
> delete from public."Racks_Planimetria" where id in (242, 259);  -- se queda la 241
> ```
>
> ✅ Lo que sí se hizo el 13/09: `809E-QUESO` y `809E-PIZZA` → **`809E`** en las 3 filas, con
> backup en `zz_backups."GV_Backup_Racks_Planimetria_809E_20260913"`. Quedan **0** filas con
> códigos inventados.

<details><summary>Diagnóstico y SQL originales (el INSERT de stock está mal, ver arriba)</summary>


> **Se hizo el renombre. NO se cargó el stock, y es a propósito — el SQL de abajo está mal.**
>
> ✅ `Racks_Planimetria`: `809E-QUESO` y `809E-PIZZA` → **`809E`** en las 3 filas
> (AD06 30/360 CH · AE11 8/64 LK · AD5 28/336 CH). Backup en
> `zz_backups."GV_Backup_Racks_Planimetria_809E_20260913"`. Quedan **0** filas con códigos
> inventados (`809E-QUESO`, `809E-PIZZA`, `1546903`, `VASTIDOR`).
>
> ⛔ **El INSERT a `Movimientos_Stock` de abajo NO se corrió.** El propio bloque avisaba
> "confirmar `tipo`/`ref` con el formato de `stkInsAlta`"; al medirlo contra la tabla real
> aparecieron **tres** cosas que lo invalidan:
> 1. **`ubicacion` no se usa nunca** en `deposito='racks'` (todas las filas la tienen NULL).
>    El INSERT la llenaba con `'AD06'` / `'AE11'`.
> 2. **`unidad` no es `'cajas'`**: en racks es NULL, o `'inner'` en los `conteo_racks`.
> 3. **Y lo que importa de verdad: existe el depósito `racks_ch`.** El 809E de Chef ya tuvo
>    ahí un `conteo_racks` de **+360** y un `ajuste` de **−360** (neto 0) — o sea los 360 de
>    AD06 **ya se contaron una vez** y alguien los sacó. Meter otros +360 en `racks` con
>    `empresa='CH'` no es "cargar lo que faltaba": es un cuarto movimiento sobre algo que ya
>    tiene historia, en **otro depósito** del que usa Chef.
>
> Saldos reales de 809E hoy: `racks` = **336** · `racks_ch` = **0**.
> Son **424 cajas** en juego, así que no se adivina: hay que decidir si AD06 va a `racks_ch`
> o a `racks`, y por qué se neteó el conteo anterior.

<details><summary>Diagnóstico y SQL original (el INSERT está mal, ver arriba)</summary>


- **Bloque 1 verificado:** `Racks_Planimetria` ya dice `546V` en AD12 (63/189), AE09 (117/351), X13 (117/351) = 891 cajas; `Insumos` tiene `546V Bastidor 546 importados AD12`; `GV_Lugar_Item` AD12/AE09 → 546V. **Pero `Movimientos_Stock` para 546V = 0 movimientos** (1546903 n=3 saldo 0, VASTIDOR n=2 saldo 0): las 891 cajas siguen fuera del stock.
- **Sigue igual:** `809E-QUESO` AD06 30/360 (CH) y AD5 28/336 (CH), `809E-PIZZA` AE11 8/64 (LK). Movimientos 809E: CH racks 336 (= AD5), AD06 y AE11 no. `1000900` Y4 40/160 y `522S` W04 20/80 sin alta en `Insumos` ni `OC_Maximos`. 33 posiciones ocupadas sin planimetría (antes 37). `GV_Lugar_Item` dice AD06 → 368E (contradice al rack).
- **B — SQL listo para "dale" (809E, es lo único que no depende de un dato nuevo):**
  ```sql
  create table zz_backups."GV_Backup_Racks_Planimetria_809E_20260913" as
    select * from public."Racks_Planimetria" where cod_art in ('809E-QUESO','809E-PIZZA');
  alter table zz_backups."GV_Backup_Racks_Planimetria_809E_20260913" enable row level security;
  revoke insert, update, delete, truncate on zz_backups."GV_Backup_Racks_Planimetria_809E_20260913" from anon, authenticated;
  -- el código vuelve a ser 809E; la empresa ya está en la columna emp
  update public."Racks_Planimetria" set cod_art = '809E' where cod_art in ('809E-QUESO','809E-PIZZA');
  -- stock: lo que no estaba contado (AD06 360 CH, AE11 64 LK). AD5 (336 CH) ya está.
  insert into public."Movimientos_Stock"(ts, cod_art, deposito, delta, tipo, ref, empresa, ubicacion, unidad)
  values (now(), '809E', 'racks', 360, 'ajuste', 'problema 110: AD06 809E-QUESO', 'CH', 'AD06', 'cajas'),
         (now(), '809E', 'racks',  64, 'ajuste', 'problema 110: AE11 809E-PIZZA', 'LK', 'AE11', 'cajas');
  ```
  Cadena: `refresh_stocks_carga_rapida` (cron 57) y `reconciliar_pipeline_stock` (68) lo toman solos; `gv_ocupacion_lugar`/`gv_gondola_divergente` ven el código al instante. **Antes de correrlo confirmar `tipo`/`ref` con el formato que usa `stkInsAlta`** (no lo verifiqué contra el front).
- **C (Luis):** (1) 546V: ¿stock inicial 891 en depósito `insumos` (como 523C) o `racks`? — es un INSERT igual al de arriba; (2) `1000900` (espiral) y `522S`: nombre y categoría para `Insumos`; (3) si el 809E de Loeke pasa a 820E "en la próxima importación", ¿la fila AE11 se renombra ya o espera?

</details>

### 20 · Credenciales hardcodeadas en 11 Edge Functions — **E**

- **Estado real hoy (leído con `get_edge_function`):**
  - GV `leer-factura` v35: **tapón 410**, sin clave. `leer-produccion-foto` v34: **sólo `Deno.env.get("OPENAI_API_KEY")`**. (GP2 `8e7dfce`, en origin/main.) → 2 de 11 resueltos.
  - GV `send-whatsapp` v38, `send-rendimiento-matrices` v32, `reporte-diario-rendimiento` v77: **token de Meta `EAAUepTT…` sigue pegado** (el mismo en las tres).
  - LK `sheets-proxy` v70, `retry-sheets` v47, `sheets-entregas-proxy` v60: `SHEETS_SECRET = "Damian.10.2026.WEB"` + URL del Apps Script (retry-sheets además `CRON_SECRET`). `virgilio-entrega-sync` v17 y `lk_notif-facturado` v11: `x-sync-secret` compartido. `sync-product-m3` v39: `SHEET_SYNC_SECRET` como fallback.
- **Clase E porque el dueño dijo "No la cambiemos por ahora"** (ESTADO-Y-PENDIENTES §2) y porque el orden correcto exige rotar en Meta/OpenAI primero. Los internos (`x-sync-secret`, `SHEET_SYNC_SECRET`, `CRON_SECRET`) sí se podrían mover al Vault sin tocar a nadie afuera, pero `SHEETS_SECRET` exige tocar el Apps Script (no accesible). Queda abierto a propósito.

### 16 · Vercel dejó de deployar `main` de pagina-lk-copia — **E**

No hay clon del repo LK ni acceso a Vercel en esta sesión; no se puede re-medir. Sigue siendo del dueño (Deployments → Redeploy). Único cambio de página atascado: `64f98ba` (aviso de renglones sin match en OC de súper).

### 74 · Dos padrones de empleados — **C**

- **Hoy:** `public.Empleados` 69, `planify.employees` 53; **29 legajos comunes, 18 con otro nombre**; 3 legajos repetidos en `Empleados` (dos filas: baja + activo); 2 `employee_id` con doble fila en `planify.empleados_liquidacion`. Ejemplos vigentes: 268 Diego Gonzzales / Ariadna Diaz vs Javier Buyo; 267 Matias Franco vs Nazareno Rodríguez; 249 RRHH vs Tomás Beviglia; 504 Kevin Latronico vs Melany Pierola.
- **Pregunta:** ¿cuál es el padrón madre (RRHH / Planify) y se acepta que `public.Empleados` deje de reusar legajos? Sin eso no hay UPDATE seguro: los 11 legajos ambiguos tienen 1.792 eventos de producción atrás.

### 75 · Asistencia en dos sistemas — **C**

- **Hoy:** `Fichadas_Historico` 17.249 (última 11/09 17:46), `asistencia_diaria` 1.530 (última 12/09). Desde 01/04: 12 pares legajo+fecha, **12 con salida distinta, 12 con entrada distinta, 10 con entrada NULL en Planify**.
- **Pregunta:** ¿la liquidación tiene que salir de la fichada? Si sí, el fix es un job Planify que rellene `entrada_real/salida_real` desde `Fichadas_Historico` (repo Planify, no éste). Si no, se cierra como "decisión: son dos sistemas".

### 77 · `cod_cliente` sin empresa — **A + C**

- **Hoy:** `whatsapp_clientes` 942 y `clientes_vendedor` 1.245, ambas **sin columna empresa** (sin cambios). Con el padrón que existe hoy en GV (`GV_Clientes_Whatsapp`, 358 filas LK+CH) sólo 13 códigos son ambiguos (13 en `clientes_vendedor`, 0 en `whatsapp_clientes`); los 252 del registro se midieron contra los padrones completos de LK y Chef, que GV no tiene.
- **Lectores:** función `gv_cuar_contacto_lote`; vistas `vista_avisar_programacion`, `vista_plata_perdida`; `index.html` (5 y 3 referencias).
- **A:** `GV_Clientes_Whatsapp` ya lleva `empresa`: apuntar los 3 objetos + `index.html` ahí y dejar `whatsapp_clientes` como legado (misma jugada que se hizo con `Codigos_Duales` en v16.49). Para `clientes_vendedor` no hay tabla con empresa → **B chico**: `alter table public.clientes_vendedor add column empresa text` (nullable, sin backfill) y que la carga lo llene.
- **C:** ¿de dónde sale `clientes_vendedor` hoy (quién la carga y con qué archivo)? Sin eso el backfill de empresa es adivinar.

### 78 · Flejes: 47/54 stocks iniciales distintos — **C → probable D**

- **Hoy:** sigue 47/54, 6 con madre 0 y planta >0, `stock_inicial_updated_at` idénticos (13/08), sólo planta "Cervantes".
- **Hallazgo nuevo:** **`flejes_stock_planta` no la lee nadie**: 0 funciones, 0 vistas, 0 en `index.html`, 0 en todo el repo GV y 0 en GP2. `Flejes."Stock Inicial"` lo leen `v_grj_componentes_con_peso` y 10 archivos del admin viejo (`cervantes-admin/entero/StockFlejes/*`, Talleristas). GP2 lleva el stock de flejes en `GP2.inventario`.
- **Pregunta (Luis):** ¿el stock de flejes vivo es el de GP2? Si sí → `descartado` ("las dos tablas de public son del vecino; la planta es huérfana") y anotar `flejes_stock_planta` en la lista de tablas al pedo (tarea 3237).

### 79 · Facturas controla contra precios de abril — **D**

- `Precios_Proveedores`: 753 filas, `max(created_at)` 2026-04-09, `max(fecha_ult_lista)` 2026-03-25; ninguna función la lee. `GP2.precio_proveedor`: 312 filas, copiado hasta 11/09.
- **La pantalla no existe más en su origen:** GP2 `8e7dfce` (13/09, en origin/main) borró `Facturas/index.html`; el menú `GP2_MODULOS.html` linkea `Compras/LecturaFacturas_GP2.html`. En GV quedan las copias `cervantes-admin/entero/Facturas/index.html` (admin viejo) y `cervantes-admin/gp2/Facturas/index.html` (copia desactualizada), ninguna linkeada desde un menú.
- **Propuesta:** `descartado` con esta evidencia, y en la próxima re-sincronización de `cervantes-admin/gp2/` borrar esa copia (A trivial).

> ⚠ **CORREGIDO EL MISMO DÍA (v16.75). El 79 NO se cierra: las copias SÍ están linkeadas.**
> La línea de arriba dice "ninguna linkeada desde un menú" y es falsa —
> `cervantes-admin/entero/Inicio/index.html:1256` tiene el botón
> **"Lectura de Facturas Entrantes"** → `../Facturas/index.html`, y ese admin se abre desde el
> panel supervisor de Gestión. O sea que la pantalla sigue viva y alcanzable.
> Lo que SÍ se hizo: se borró `cervantes-admin/gp2/Facturas/` (el origen, GP2, la borró en
> `8e7dfce`; era pura desincronización del espejo).
> **Y hay algo nuevo que empeora el cuadro:** al sacar la clave de OpenAI filtrada (13/09), la
> Edge Function `leer-factura` quedó como tapón que contesta **410**. La copia de `entero/` la
> sigue llamando, así que hoy esa pantalla **no lee ninguna factura**: falla con un error, no
> con la lista vieja de abril. Es consecuencia aceptada de matar la clave, no un descuido.
> **Decide Thomas:** sacarle el botón del menú de `entero/` (parche de la copia, como los otros
> tres que ya tiene), o dejarlo hasta que se apague el admin viejo. `GestionProductivaEntero`
> no está en el alcance de esta sesión, así que allá no se tocó nada.

### 46 · 7 artículos con parte en receta sin rama de ruta (GP2) — **D**

- Corrí hoy la consulta informativa `receta_sin_rama_que_la_lleve` de `db/verificar.sql` (líneas 230-251) contra la base: **2 pares, ambos tallerista "Fábrica"** (570 y 858 con E6 Pala Canelón), que el propio archivo marca como correctos. Chequeo directo: 547 tiene un solo A4 (Caja N°10) y está en ruta; 508/518/708 ya no listan D13; 103/120/564 no tienen partes sin ruta.
- **Propuesta:** `cerrar_problema` como `corregido`. No pude fijar el commit exacto (varios del 13/09 tocan recetas: `ee712a4` "despiece completo verificado 190/190", `7fab29f`, `cb645a6`); quien cierre puede confirmarlo con `git log -S'A11' -- db/` en GP2.

### 53 · Parseo de facturas de ISIS — **E**

- **Hoy:** con la fórmula correcta no cuadran **59.537 / 246.899** en `isis_lk.documento_items` (24,1%) y **17.241 / 67.630** en `isis_ch` (25,5%). Único lector de `precio_unit` en la base: `gv_conciliacion_comparar` (ya despeja el precio, v16.59).
- **Quién escribe:** ninguna función de la base (`insert into isis_*.documento_items` = 0 hits), ninguna Edge Function de GV (`isis-api` sólo lee y sirve pedidos), nada en el repo. La ingesta es **por archivo** (`ingesta_log`, "una fila por archivo") desde un proceso externo. → el arreglo del parser no se puede hacer desde este repo. Queda abierto como E; opcional A: una vista `isis_lk.v_documento_items_precio` con el precio despejado para que nadie vuelva a leer `precio_unit`.

### 59 · A Facturar tiene 168 cajas de más — **C**

- **Hoy:** saldo `a_facturar` = **1.623** (CH 705, LK 976, Mixto −58); NP armadas sin facturar = **21 NP / 1.456 cajas** → **167 sobran** (el 221 de la NP 98532 ya se corrigió: era 168). Sigue sin poder atribuirse por NP (salida con ref `TANDA|NP` / `NP|CP`, entrada con la tanda).
- **Pregunta:** ¿conteo físico de a_facturar (por empresa) para un ajuste único? El "Mixto = −58" sugiere movimientos sin empresa que también hay que mirar.

### 80 · Espejo ISIS congelado + 14 líneas duplicadas — ✅ B EJECUTADO 2026-09-13 ("dale")

> **Aplicado y verificado.** Backup previo en
> `zz_backups."GV_Backup_PPP_Base_Pedidos_dup_20260913"` (**28 filas** = los 14 pares enteros).
> El DELETE borró **5 filas** (duplicados exactos, se quedó el `id` menor):
> `GV_PPP_Base_Pedidos` pasó de **9.786 a 9.781**.
>
> ⚠ **CORRECCIÓN al diagnóstico de abajo: NO eran 5 los pares con `cajas` distintas, son 9.**
> El texto original listaba sólo 5 y por eso subestimaba lo que queda por decidir. Los 9 que
> siguen duplicados, con las dos cantidades:
>
> | pedido | artículo | filas (id:cajas) |
> |---|---|---|
> | 44496 | 713  | 4582093:2 / 4582097:8 |
> | 97966 | 590E | 4583328:4 / 4583329:7 |
> | 97971 | 590E | 4583387:2 / 4583388:4 |
> | 97996 | 323E | 4583677:2 / 4583678:1 |
> | 98128 | 590E | 4585079:0 / 4585080:4 |
> | 98161 | 590E | 4585449:0 / 4585450:5 |
> | 98293 | 574  | 4586878:4 / 4586879:2 |
> | 98336 | 590E | 4587459:2 / 4587460:1 |
> | 98608 | 323E | 4590508:2 / 4590509:1 |
>
> `gv_np_web_dobles` sigue en **20** (no lo movía este borrado). Sin índice único hasta que
> queden 0. **E (el congelamiento del espejo) es decisión del dueño y no se tocó.**

<details><summary>Diagnóstico y SQL original</summary>


- **Hoy:** 14 pares `(pedido, articulo)` duplicados en `GV_PPP_Base_Pedidos` (9.786 filas), `max(fecha)` 04/09 en Base y en `GV_PPP_Programacion_Diaria` (NP máx 98704). `gv_np_web_dobles` = 20 (igual). El congelamiento es decisión del dueño (E).
- **B — SQL listo (borra sólo los duplicados exactos; los que difieren en `cajas` quedan para decidir):**
  ```sql
  create table zz_backups."GV_Backup_PPP_Base_Pedidos_dup_20260913" as
    select * from public."GV_PPP_Base_Pedidos" b
     where (pedido, articulo) in (select pedido, articulo from public."GV_PPP_Base_Pedidos" group by 1,2 having count(*)>1);
  alter table zz_backups."GV_Backup_PPP_Base_Pedidos_dup_20260913" enable row level security;
  revoke insert, update, delete, truncate on zz_backups."GV_Backup_PPP_Base_Pedidos_dup_20260913" from anon, authenticated;
  -- duplicados exactos (misma cantidad): se queda el id menor
  delete from public."GV_PPP_Base_Pedidos" b
   using public."GV_PPP_Base_Pedidos" o
   where o.pedido=b.pedido and o.articulo=b.articulo and o.cajas is not distinct from b.cajas and o.id < b.id;
  -- lo que queda con cajas distintas (decidir cuál es la buena):
  select pedido, articulo, string_agg(id||':'||cajas, ' / ') from public."GV_PPP_Base_Pedidos"
   group by 1,2 having count(*)>1;
  ```
  Cadena: la tabla es histórica; la leen `gv_np_web_dobles`, `gv_ppp_base_pedidos` y la facturación de NP de ISIS ya facturadas. Sin índice único hasta que queden 0.
- **C:** los 5 pares con cajas distintas (98608/323E 2 vs 1, 98293/574 4 vs 2, 98161/590E 0 vs 5, 98128/590E 0 vs 4, 44496/713 2 vs 8): cuál vale.

</details>

### 81 · `db_n8n_espejo` difiere de su madre — **C**

- **Hoy:** 1.775 cierres (opción C) en 90 días; **21 sin fila en el espejo** (ventana ±3 min, mismo legajo). Madre 18.219 / espejo 15.220, las dos al día (12/09 13:41). **No hay trigger** sobre `Registros Produccion Cervantes`: el espejo lo escribe la app, así que un cierre que falló al insertar no se recupera solo.
- **Pregunta:** ¿se regeneran esos 21 en el espejo (con `recalcular_matriz` para premio)? Es un INSERT por fila con `Legajo, Matriz, Uni, Fecha, Hora_Inicio/Fin` sacados de la madre; lo dejo como C porque el premio de esos días ya se reportó y reinsertar cambia el histórico de rendimiento.

### 82 · `public.Matrices` con `Uni_X_Golpe` en 0 — ✅✅ EJECUTADO 2026-09-13 ("dale" de Thomas)

> **Aplicado y verificado.** Backup completo previo en
> `zz_backups."GV_Backup_Matrices_20260913"` (**414 filas**, la tabla entera: 414 con
> `Uni_X_Golpe` en 0 y 173 con `Tiempo_Historico` en 0).
> Después del UPDATE, sobre los **114 pares** public↔GP2: `Uni_X_Golpe` en 0 → **0**,
> `Uni_X_Golpe` distinto de GP2 → **0**, `Tiempo_Historico` en 0 teniendo GP2 valor → **0**.
> No se pisó ningún valor ya cargado (el UPDATE es condicional).
>
> ⛔ **Queda abierto el único par contradictorio** (el "C chico"): matriz **365 · Corte Pieza
> Grande SacaFuente Pizzero**, `Tiempo_Historico` public = **1,7** vs GP2 = **2,41**. Los dos
> tienen valor, así que el UPDATE no lo tocó a propósito. **Cuál manda lo decide Thomas.**
>
> ⛔ **Falta** `select public.recalcular_matriz(<N_Matriz>)` para las que tenían TH en 0: los
> **65 eventos** de 90 días del espejo con `Tiempo_Historico=0` **no se recalculan solos**.
> No se corrió porque reescribe premios ya registrados — eso es plata y va con su propio "dale".

<details><summary>Diagnóstico y SQL original</summary>


- **Hoy:** 114 pares public↔GP2: **114 con UxG=0 en public** (GP2 lo tiene en los 114, 0 contradicciones); **14 con TH=0 en public y cargado en GP2**; 1 par con TH distinto entre los dos; **65 eventos** en 90 días en el espejo con `Tiempo_Historico=0` pese a que GP2 lo tiene.
- **Quién lo consume:** `reporte-diario-rendimiento` y `send-rendimiento-matrices` (Edge) leen `public.Matrices.Tiempo_Historico`; el espejo lo copia al registrar; RPC `recalcular_matriz` lo recalcula. Triggers en `Matrices`: `trg_audit_matrices` (loguea), `trg_matrices_disc_flow`, `trg_sync_stock_matrices` (upsertea `UnixCajon_Stock_Registro_Prod_Cerv` con `Uni_X_Cajon`, que no se toca → inocuo).
- **B — SQL listo:**
  ```sql
  create table zz_backups."GV_Backup_Matrices_20260913" as select * from public."Matrices";
  alter table zz_backups."GV_Backup_Matrices_20260913" enable row level security;
  revoke insert, update, delete, truncate on zz_backups."GV_Backup_Matrices_20260913" from anon, authenticated;
  -- UxG: 114 filas; TH: sólo donde public está en 0 y GP2 tiene valor (14). No se pisa ningún valor cargado.
  update public."Matrices" m
     set "Uni_X_Golpe" = case when coalesce(m."Uni_X_Golpe",0)=0 then g.uni_x_golpe::int else m."Uni_X_Golpe" end,
         "Tiempo_Historico" = case when coalesce(m."Tiempo_Historico",0)=0 and coalesce(g.tiempo_historico,0)>0 then g.tiempo_historico else m."Tiempo_Historico" end
    from "GP2".matriz g
   where trim(g.n_matriz)=trim(m."N_Matriz")
     and (coalesce(m."Uni_X_Golpe",0)=0 or (coalesce(m."Tiempo_Historico",0)=0 and coalesce(g.tiempo_historico,0)>0));
  -- después: select public.recalcular_matriz(<N_Matriz>) para las 14 (los 65 eventos no se recalculan solos)
  ```
  Ojo: `Matrices` es **tabla madre** según CLAUDE.md (alimenta `db_n8n_espejo`); el UPDATE va con backup y `trg_audit_matrices` lo deja trazado. **C chico:** el par con TH contradictorio (public > 0 y GP2 > 0 distintos) — cuál manda.

</details>

### 83 · Copias congeladas — **D + C**

1. `Insumos_Ubicaciones_Unificadas`: `max(updated_at)` 11/08 vs original 04/09; 4/151 distintas. **0 lectores** (funciones, vistas, `index.html`). → huérfana: `descartado` + candidata a `zz_backups` o drop (tarea 3237).
2. `GP2.entrega_prov_at` 125 vs `public."Entregas Prov AT"` 150: hay **15 filas / 576 cajas** en public con `Fecha_RTO` > 31/08, o sea **el admin viejo sigue cargando entregas AT** mientras GP2 tiene `EntregasAT_GP2.html`. Por la regla GP2 ("public es la casa del vecino") no se copia; **C:** decidir que las entregas AT se cargan sólo en GP2 y apagar la pantalla vieja.
3. `Ubicaciones_Articulos` (872) vs `Racks_Planimetria` (154): 16/69 pares distintos. **0 lectores** de `Ubicaciones_Articulos`; `Racks_Planimetria` es la viva (10 refs en `index.html`). → huérfana, mismo destino que (1).

### 84 · Góndola: mapa vs capacidad — **C**

- **Hoy:** `gv_gondola_divergente` = **107** (solo_capacidad 70, solo_mapa 28, sector_inexistente 9), sin cambios. `GV_Lugar_Item.cajas_max` NULL en **782/782**; `Capacidad_Sector` 736 filas.
- **Decisión (Luis):** cuál mapa manda. Si es `GV_Lugar_Item`, el backfill que destraba la migración es:
  ```sql
  -- sólo las celdas que existen en los dos; no crea ni borra nada
  update public."GV_Lugar_Item" li set cajas_max = cs.cajas_max
    from public."Capacidad_Sector" cs where cs.sector=li.sector and cs.cod=li.cod and li.cajas_max is null;
  ```
  y las 70 "solo_capacidad" / 28 "solo_mapa" se resuelven una por una con el centinela.

### 88 · 439E de Chef sin lugar — **C → B de una línea**

- **Hoy:** `gv_lugar_articulo` 439E = LK H33, H34, Ñ54; nada CH. Stock 439E: LK terminado 16, **CH terminado 8 + a_facturar 8**. Los otros duales sí tienen las dos: 437E CH L07/L08, 438E CH L05/L06, 809E CH M13-M15.
- **Falta un dato:** el sector de góndola Chef donde va el 439E. Con eso: `insert into public."GV_Lugar_Item"(sector, cod, clase, activo) values ('<sector CH>', '439E', 'articulo', true);` (verificar `clase` contra las filas vecinas antes de correr).

### 111 · El plan decía migrar `Racks_Planimetria` — **D**

`docs/PLAN-SACAR-SUFIJO-EMPRESA.md` ya tiene el aviso "⚠ CORRECCIÓN (2026-09-13): `Racks_Planimetria` NO se reemplaza" (líneas 319-340) y la fila tachada en el paso 5. Commit `f11af92` (v16.63), presente en `origin/main`. → `cerrar_problema(111, …, p_commit_sha => 'f11af92')`.

---

## Qué NO se hizo (a propósito)

- No se tocó ningún dato ni archivo de los repos; los SQL de arriba están para un "dale" explícito.
- No se investigó el 198E.
- No se propone borrar backups ni saltear tests.
- No se pudo medir el 16 (Vercel/LK) ni el parser del 53 (vive fuera de la base y del repo).
