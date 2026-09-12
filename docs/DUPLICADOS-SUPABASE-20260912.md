# Mapa de datos duplicados en Supabase — 12/09/2026

Pedido de Thomas (12/09): *"lanza agentes que lea supa para ver qué tablas hay con info
duplicada/triplicada/etc"*. Tres agentes barrieron el proyecto `hrxfctzncixxqmpfhskv` en paralelo
(stock/insumos/importados · pedidos/PPP/facturación · maestros/RRHH/clientes/precios), **sólo
lectura**, cada hallazgo medido con una consulta, no estimado.

Lo que se busca acá **no es "filas repetidas dentro de una tabla"**: es **el mismo dato guardado en
dos o tres lugares que hoy no coinciden**.

---

## Ya arreglado en esta misma sesión

| | Qué era | Dónde quedó |
|---|---|---|
| ✅ | **`vista_saldos_stock` emitía el mismo `cod_art` dos veces** (~280 códigos). Rompía el `REFRESH CONCURRENTLY` de `vista_stock_procesada` y **la pantalla de Stock quedó congelada 10 h** | v16.08, §3.cr |
| ✅ | **El trigger de `stocks_carga_rapida` sumaba el depósito insumos al stock total** y nunca llenaba `insumos_dep` (590E: 2.447 cajas cuando hay 51) | v16.09, §3.cs |
| ✅ | **El módulo de importados tenía su propio libro de stock** (`Importados_Mov_Stock`) en vez de leer el depósito | v16.04 / v16.08, §3.cq |
| ✅ | **El front leía `Volumen_Articulos` cruda** (hallazgo 5): el picking veía 548 artículos en m³ = 0 y 82 con el valor equivocado | v16.10, §3.ct |
| ✅ | **Geocodificaciones que contradicen a su barrio** (hallazgo 2): 21 filas, Soldati en Corrientes, Parque Patricios en Bahía Blanca | v16.10, §3.ct |

Centinelas nuevos, los dos tienen que dar **0 filas siempre**:

```sql
select * from public.gv_stock_cod_duplicado;   -- el refresh de Stock no se va a caer
select * from public.gv_geo_incoherente;       -- ningún barrio del AMBA con coordenada lejos
```

---

## 🔴 Abiertos — ALTA

### 1. `uni_x_caja` vive en 8 tablas y hay DOS vistas resolutoras que se contradicen
`Articulos_Cajas` · `Articulos Virgilio X Tallerista` · `Uni_x_Articulo_x_Caja` · `Despiece x Articulo`
(dos columnas en la misma tabla) · `OC_Maximos` · `proyeccion_madre.uxb` · `precios_venta.uxb` ·
`cob_uxb_lk` · `Importados` · `Importados_Volumen`.

- `vista_uni_x_caja` (maestro → OC_Maximos → proyeccion_madre) alimenta `vista_stock_procesada` y el
  generador de OC → **manda para comprar**.
- `vista_uxb_articulo` (Articulos_Cajas → OC_Maximos activo → precios_venta) → **manda para cobrar**.

**335 códigos en las dos, 33 dan distinto.** El **112**: se compra pensando 24 u/caja y se factura
pensando 12. También 101 (6 vs 12), 255 (12 vs 8), 508 (12 vs 6), 631/632/633 de Chef (12 vs 24).
Par a par: `Articulos_Cajas` vs `OC_Maximos` **37/316**; vs `cob_uxb_lk` **26/247**; vs
`Despiece x Articulo` **30/205**; `N_Caja` vs `Uni_x_Articulo_x_Caja` **28/266**.

**No hay fuente de verdad.** Es el hallazgo con más superficie de todo el barrido.

### 2. Geocodificación: la misma dirección en dos puntos, hasta 842 km
`GV_Geo_Cliente` (1.019 filas, canónica) y `PPP_Geo` (221, la que usa el **orden de carga del
camión**). 149 `dir_key` en común, **13 con coordenada distinta**.

Y **`GV_Geo_Cliente` se contradice a sí misma**: la PK es `(cod, dir_key)`, así que la misma
dirección geocodificada para otro cliente quedó en otro lado. **24 `dir_key` con 2 coordenadas**, 5
a más de 50 km:

| dir_key | una | la otra | distancia |
|---|---|---|---|
| `luna 1299\|parque patricios` | CABA | **Bahía Blanca** | 628 km (y la mala es la canónica) |
| `b. de astrada 2850\|soldati` | CABA | **Corrientes** | 798 km |
| `pergamino 3751\|soldati` | CABA | **ciudad de Pergamino** | 253 km |
| `av.del valle 1139\|barracas` | — | — | 305 km, **mismo cliente** |
| `asamblea 665\|parque chacabuco` | — | — | 21 km, mismo "Regalitos S.R.L." |

Nominatim tomó el nombre de la calle como localidad. **Las tandas se arman por cercanía real**: una
coordenada a 600 km rompe la agrupación y el cálculo de km.

### 3. `PPP_Entregados_Meta` es un espejo muerto que alimenta 21 objetos vivos
El cron que la llena (**jobid 27**) está **apagado**. Último dato: **02/09**. **121 de 121** NPs
facturadas desde el 03/09 **no están**. La leen 15 vistas y 6 funciones, entre ellas
`vista_stock_procesada` (refresh cada 2 min), `reconciliar_pipeline_stock` (cada 10 min),
`vista_control_remitos`, `vista_tanda_m3`, `vista_faltante_real`, `gv_pedidos_web_excluidos`.

El watchdog de frescura (`watchdog_frescura_datos`) **sólo vigila `proyeccion_madre`**, por eso
nadie se enteró.

### 4. `Entregas_Virgilio`: 62 filas duplicadas, 236 cajas contadas dos veces
60 pares `(np, cod_art)` repetidos sobre 28 NPs, entre el 01/07 y el 19/08. **La tabla no tiene
índice único sobre la clave natural.** Patrón: una fila con `tanda` + `fecha_salida` y otra con los
dos en `null`.

Esto explica los 17 casos donde `Entregas_Virgilio.cajas_pedidas` daba el doble que
`PPP_Base_Pedidos.cajas`: **no eran valores en conflicto, era doble conteo**.

### 5. m³: el front lee la tabla cruda, el backend la vista resuelta
`GV_Volumen_Articulos` (override) pisa a `Volumen_Articulos` en **55 de 157** códigos, con ratios
de 0,10× a 21,7×. Pero `index.html` (`fetchVolumenArticulos`) le pega a **`Volumen_Articulos`
directo**, sin el override.

`521L` 0,0024 vs **0,0240** y `366EL` 0,0016 vs **0,0160** → se cargan con **10× el volumen real**.
`539EL` 0,063 vs 0,0029 → 21× al revés. **El m³ es lo que arma tandas y llena camiones.**

### 6. Dos padrones de empleados: 11 legajos nombran a personas distintas
`public.Empleados` (69) · `planify.employees` (53) · `GP2.empleado` (65) ·
`planify.empleados_liquidacion` (41) · `fichada.empleados` (8) · `empleados_loekemeyer_chef` (37).

31 legajos en común entre los dos principales, **19 con otro nombre, 13 personas realmente
distintas**, 11 sacando los de prueba. Esos 11 acumulan en 90 días **1.792 eventos de producción de
Virgilio**, **373 de Cervantes**, **179 filas de `db_n8n_espejo`** y **217 días de asistencia**.

| legajo | `public.Empleados` | `planify.employees` |
|---|---|---|
| 504 | Kevin Latronico | **Melany Pierola** |
| 267 | Matias Franco | **Nazareno Rodriguez** |
| 268 | Ariadna Diaz / Diego Gonzzales | **Javier Buyo** |
| 249 | RRHH | **Tomas Beviglia** |

**Causa de fondo:** `public.Empleados` **reusa legajos** (268, 274 y 282 tienen dos filas: el viejo
de baja y el nuevo activo) y las copias se quedaron con una sola de las dos.

### 7. Asistencia en dos sistemas y **ninguna** hora coincide
`Fichadas_Historico` (17.249 eventos, la sincroniza un cron cada 2 min) vs
`planify.asistencia_diaria` (1.529 filas, carga manual). Desde el 01/04 se cruzan **12 pares
legajo+fecha** y **los 12 tienen la salida distinta**, 8 la entrada.

Legajo **237** el 31/07: la fichada dice 08:18–17:33, Planify dice entrada/salida `null` y
**`horas_trabajadas = 9` fijo**. Legajo **277** el 03/09: fichada 09:37 de salida, Planify
15:00–17:40.

**`asistencia_diaria` es lo que alimenta liquidación y no mira la fichada.**

### 8. Sueldos: `empleados_liquidacion` contradice a `employees`
41 filas, **4 con legajo distinto**. El `employee_id 56` tiene **dos** filas de liquidación:
"Melany Pierola" legajo 503 y "Kevin Latronico" legajo 504, las dos apuntando al mismo empleado.
Damian: legajo `C5` en una y `17` en la otra. Romina: legajo `-1`. Otro: `sin legajo`.

### 9. `wa_np_snapshot` finge estar fresca
`wa_np_snapshot_run()` hace `on conflict do update set direccion = coalesce(s.direccion, excluded.direccion)`:
**una vez que el valor no es null no se actualiza nunca más**, pero sí pisa `updated_at = now()`.

Sobre 133 NPs comunes con la programación: **14 dirección distinta, 7 razón social, 7 barrio, 4
zona**. La NP **98686** dice `Av. F. Lacroze 2481` cuando la entrega real es **`Av Corrientes
3864`** — y es el dato con el que se le avisa al cliente.

### 10. `cod_cliente` sin `empresa`: 252 códigos son dos clientes distintos
`whatsapp_clientes` (942) y `clientes_vendedor` (1.245) guardan el código **sin la empresa**. **257
códigos existen en LK y en Chef, y en 252 la razón social es otra.** Caen sobre código ambiguo
**166 filas de teléfonos** y **252 de vendedor**.

El cod `1` es "Loekemeyer SRL" en LK y "Tierra Nativa SA" en Chef, con **un solo teléfono y un solo
vendedor**. Es exactamente la regla del dueño: *"el cod cliente no significa nada, sólo el CUIT
vale"*. (En los 332 códigos que sí cruzan bien, el teléfono es idéntico: **el problema es la clave,
no el valor**.)

### 11. Flejes: 47 de 54 stocks iniciales no coinciden
`Flejes."Stock Inicial"` vs `flejes_stock_planta`. **No es desfasaje: los timestamps son
idénticos** (13/08). Las dos familias hermanas están perfectas (`Cajas` 0/14,
`Partes_Plasticas` 0/75), así que es sólo flejes.

| N Fleje | madre | planta |
|---|---|---|
| 1 Mgo Plano Manija | **0** | 709,2 |
| 22 Cpo Sacacorchos | **0** | 621 |
| 6 Mgo Plano Marip | 1.560 | 738 |
| 10 Arandela Afila | 252 | 1.310 |
| 19 Cuchilla De Pelador | 672 | 144 |

Con `Stock Inicial = 0` el fleje **no se repone**.

### 12. Precios de proveedor: la pantalla de Facturas lee una lista de abril
`Precios_Proveedores` (753 filas, **congelada el 09/04**) vs `GP2.precio_proveedor` (314, viva al
10/09). 49 pares: **35 con precio distinto, 36 con fecha distinta, 49 con la moneda escrita
distinto** ("Peso" vs "ARS").

`Facturas/index.html` de **los dos admin de Cervantes** lee la vieja; el motor de costos de GP2 usa
la nueva. Caja Nº 10: 509,20 vs 567,41. Ø 1.25 Aluminio: **14.293,71 "Peso"** vs **10,5 USD**.

---

## 🟡 Abiertos — MEDIA

| # | Qué | Medido |
|---|---|---|
| 13 | **`PPP_Base_Pedidos` congelada el 04/09** (máx. pedido 98700 mientras la programación va por 98704) + **14 líneas duplicadas con cajas distintas** (98608: el mismo artículo con 2 y con 1). Efecto: `gv_np_web_dobles` cruza por esa fecha → **el detector de NP duplicadas está ciego** para todo lo posterior al 04/09 | 14/14 |
| 14 | **Dos libros de stock de importados** que no reconcilian: `Importados_Mov_Stock` (unidades) vs `Movimientos_Stock` (cajas) | 84/92 códigos |
| 15 | **`Ubicaciones_Articulos` vs `Racks_Planimetria`**: misma estructura, mismo `created_at` al microsegundo, cantidades distintas (529E en Y14: 37 master vs 12) | 16/70 |
| 16 | **`Insumos_Ubicaciones_Unificadas` congelada el 10/08**: H201Part muestra **0** donde el original tiene **24.000** | 4/151 |
| 17 | **`Capacidad_Sector` vs `GV_Lugar_Item`**: 204 asignaciones que no se cruzan y **`cajas_max` NULL en las 782 filas** de la nueva. Además `GV_Lugar_Item` no tiene `empresa` | 647/657 |
| 18 | **`Facturacion_NP` vs la programación**: 9 de 63 con otra tanda/fecha. La **NP 98490** figura facturada como `D47C` el 27/08 y programada + entregada como `D54C` el 09/09 | 9/63 |
| 19 | **`db_n8n_espejo` difiere de su madre** (`Registros Produccion Cervantes`): 7 matrices distintas, 9 unidades distintas, **22 cierres que no llegaron al espejo**. El premio y el reporte salen del espejo | 38/1.768 |
| 20 | **`Matrices` (public) tiene los tiempos en 0** y `GP2.matriz` los tiene cargados: `Uni_X_Golpe = 0` en **113 de 114**. **65 eventos en 90 días** quedaron sin benchmark | 113/114 |
| 21 | **`proyeccion_madre` vs `GP2.est_madre`**: 37 filas con distinta proyección en unidades (cod 836: 106 vs 2.544). Documentado y a propósito — pero el origen queda con el dato malo | 37/405 |
| 22 | **Candidatos de RRHH**: 469 nombres repetidos = 1.257 filas en `lecturacvs.candidates`, **122 con `status` contradictorio**; y los 12 que hicieron la prueba online tienen `prueba_online_at` en NULL | 122/469 |
| 23 | **Tres copias de la lista de códigos duales** (`Codigos_Duales`, `codigos_duales`, `stock_v2.codigos_duales`), cada una leída por código distinto. Si mañana se agrega un dual en una sola, las otras dos mezclan stock LK/CH | 4 cods |
| 24 | **`Codigos_ISIS_Map`**: 3 códigos internos con **dos equivalencias distintas** (LK `7506600` → `5046` "skin Abrelata Uña" **o** `5146` "Colocar Tornillo CQ Al") | 3/1.595 |
| 25 | **`Importados.uni_x_caja` vs `Importados_Volumen.uni_inner`**: 101 coinciden con `uni_inner`, **0** con `uni_master`, **19 con ninguno** | 19/155 |
| 26 | **El código 026 es dos productos según la tabla**: "PINZA DE FIDEOS AC INOX VERDE" vs "Ø 8 Colador N8". Igual el 056E ("Llavero Destapacorona" vs "Destapador Full Black"). En total 330 códigos con descripción distinta entre 7 tablas | 330/461 |
| 27 | **`Entregas Prov AT`**: la copia de GP2 perdió **937 cajas (15%)** y está congelada el 31/08. **Ningún cron copia `public` → `GP2`** | 25 filas |
| 28 | **NP 98050**: figura en `NP_Canceladas` (cargado el 11/09) y a la vez facturada y entregada el 29/07 | 1 |
| 29 | **`Insumos_Factores` (MC) vs `Importados_Volumen.uni_master`**: 440E 12 vs 24, 584E 60 vs 48 | 2/6 |
| 30 | **Zona guardada por fila** contra `Zonas_Barrios`: 3 filas en la programación (Burzaco como "Zona 2 - CABA Centro") y 7 en `wa_np_snapshot` | 10 |

---

## 🟢 Redundancia inofensiva / espejos muertos

- **10 NPs de ISIS que duplican pedidos web** (98696–98703, 44620, 44621): contenidas por
  `GV_PPP_Prog_Override.oculto`, pero **siguen en la tabla cruda** con su `m3` cargado.
- **`PPP_Web_Tanda_Items` vacía** (0 filas) y todavía referenciada por 7 funciones; **22 de las 31
  tandas web vivas no están registradas** en `PPP_Web_Tandas`.
- **`GV_Conciliacion_Facturacion`** (67 filas): réplica de `Facturacion_NP`, **0 diferencias**.
- **5 padrones de proveedores sin clave común**: `Proveedores` (1.513, congelada el 30/03 y con
  `razon_social` cargada en **1 sola fila**), `proveedores` (53 apodos), `Proveedores_Insumos` (20),
  `OC_Maximos.proveedor` (19 texto libre), `Importados.proveedor` (7). **0 matcheos** entre el
  maestro y los chicos; 13 nombres de `OC_Maximos` no existen en ningún lado.
- **Espejos congelados:** `empleados_loekemeyer_chef` (22/04), `Fichadas_Virgilio` (27/05),
  `FichadaQR.*` y `reconocimiento_facial.*` (prototipos del 21/07 **con datos falsos**),
  `db_n8n_espejo_historico_20260419`, schemas `isis` y `chef` (**0 filas en las 10 tablas**),
  `GV_Zonas_Barrios` (vacía), `Supervisores_Virgilio` (vacía).
- **126 tablas `*_bkp_*` / `*backup*` / `zzz_*`** (13 MB). Las peligrosas:
  `clientes_dto_bkp_20260908` (**9 `dto_vol` distintos**) y `clientes_dto_backup_20260902` (**209
  distintos**) — si alguien consulta el backup aplica el descuento equivocado.
- **Usuarios/permisos en 6 tablas con 7 filas en total** — más fragmentación que duplicación.

## Verificado limpio (probado, no supuesto)

`PPP_Web_Base` → `PPP_Web_Programacion` (87/87) · `PPP_Web_NP` ↔ programación · `lk_pedidos_match`
↔ programación (87/87) · `Facturacion_NP` ↔ pedidos web · m³ de los 87 pedidos web contra
`vista_volumen_articulo_resuelto` · `vista_tanda_m3` contra la suma por tanda · `Entregas_Virgilio`
↔ `PPP_Entregados_Meta` en tanda (753) · `Entregas_Virgilio` ↔ `Facturacion_NP` en cod_cliente
(882) · `Cajas` y `Partes_Plasticas` contra sus `*_stock_planta` · `GV_Importados_Baches` ↔
`Importados` · `whatsapp_clientes` ↔ `GV_Clientes_Whatsapp` en los 332 que cruzan bien ·
`GP2.uni_x_articulo_x_caja` ↔ `public` · `precios_venta` vs `precios_venta_chef` ·
`Auditoria_Produccion_Virgilio` (0 `client_id` duplicados: **la producción no se cuenta doble**) ·
las 5 vistas centinela (`gv_np_prog_sin_base`, `gv_ppp_web_prog_sin_base`,
`vista_np_prog_sin_base`, `gv_ppp_super_mezclado`, `gv_ppp_cliente_dos_dias`) en **0 filas**.

---

## Nota transversal

**Ningún job de `cron.job` (de los 60) copia `public.*` → `GP2.*`.** Todos los espejos de GP2
(`est_madre`, `precio_proveedor`, `uni_x_articulo_x_caja`, `articulo_prov_at`, `entrega_prov_at`)
dependen de triggers o de copias a mano, con fechas dispersas (26/08, 31/08, 02/09, 09/09, 10/09).
Por eso casi todas las divergencias son **"la copia se quedó atrás"**, no "alguien editó las dos".

Y el patrón que se repite en los tres dominios: **una tabla derivada sin nadie que vigile que siga
al día**. El watchdog de frescura existe (`watchdog_frescura_datos`, cron 70) pero mira **una sola
tabla**.

---

## Dónde queda anotado

Los 16 hallazgos ALTA y MEDIA quedaron cargados en la auditoría (`github_repo_problemas`,
schema del proyecto `hrxfctzncixxqmpfhskv`) en estado **`abierto`**, cada uno con su medición.
Los tres que ya se arreglaron están en `corregido` con su commit.

```sql
select * from github_repo_problemas.v_problemas
 where estado = 'abierto' order by severidad, detectado_en desc;
```

---

## Mapa de LECTORES del UxB en el FRONT (grep, 2026-09-12, v16.32)

Contado a mano sobre los 4 repos clonados (`Gestion-Virgilio`, `loekemeyer/produccion-virgilio`,
`loekemeyer/gestion-productiva-2.0`, `loekemeyer/planify`), sólo `.js` / `.html` / `.ts` —
sin `sql/`, sin `docs/`. Es lo que **falta tocar** para que `GV_UxB` quede como fuente única.
Regla aprendida el 12/09: *ninguna columna se toca sin contar lectores del FRONT en los 4 repos*
(casi se dropea `Articulos_Cajas.Uni_x_Caja` "sin lectores" cuando tenía 7).

### `precios_venta.uxb` — **0 lectores vivos** ✅

- La Edge Function `sync-precios-venta` **ya no la escribe** (v16.22).
- Único lector del front: `loekemeyer/produccion-virgilio/index.html:30221` ("Plata perdida"),
  y esa app **está retirada desde el 2026-09-08**.
- Gestión Virgilio **no lee `precios_venta` directo en ningún lado**: la única mención en su
  `index.html` (línea 12349) es un comentario.
- → Es la primera candidata a `drop column`, una vez confirmado en la base que ninguna
  vista/función la siga leyendo.

### `OC_Maximos.uni_x_caja` — **1 lector real** (no 13)

Los 13 archivos que mencionaban `OC_Maximos` casi todos leen otras columnas. Del `uni_x_caja`:

| Lugar | Qué hace | Estado |
|---|---|---|
| `index.html:13498` (`ocgFetchMaximos`) → `index.html:12938` | columna **Uni/Caja** de la tabla "① Config (OC_Maximos)" en la Ficha del artículo | **único consumidor real**; es un diagnóstico de lo que tiene la config, no la fuente de verdad |
| `index.html:14116` / `:14125` / `:14170` | la grilla de Config de compras | **ya sale de `GV_UxB`**: leen `vista_generador_oc`, repuntada en v16.29 ✅ |
| `index.html:13906` (generador de OCs) | lo a pedir en cajas | **ya sale de `GV_UxB`** (v16.29) ✅ |
| `modulo_talleristas_edit.js` 140 · 148 · 240 · 300 · 363 | muestra "(N u/caja)" al lado del código asignado a un tallerista | display; repuntable a `GV_UxB` |

### `Articulos_Cajas.Uni_x_Caja` — **7 lectores, todos del mismo módulo**

Y **no es el mismo dato**: es el empaque del **despiece de Cervantes** (talleristas / partes),
no el UxB de venta de LK/Chef. Por eso conviene **documentarlo como dominio aparte** y no
absorberlo en `GV_UxB`.

- `cervantes-admin/entero/Despiece x Articulo/app.js:82` y `app-inverso.js:82`
- `cervantes-admin/gp2/Despiece x Articulo/app.js:79` y `app-inverso.js:79`
- `loekemeyer/gestion-productiva-2.0/Despiece x Articulo/app.js:79` y `app-inverso.js:79` (repo origen)
- `loekemeyer/produccion-virgilio/index.html:29555` (app retirada)

Los otros 6 archivos que la traen hacen `select("*")` y **nunca usan el campo** — verificado con
grep dentro de cada uno (`ControlAT.js`, `EnviosTall.js`, `ControlTall.js`, en las 3 copias).
El único que la nombra, `ControlTall.js:1418`, es un comentario que aclara que ahí **no** aplica.

### `Articulos Virgilio X Tallerista.Uni_x_Caja` (el "maestro") — 3 lectores

- `index.html:22434` / `:22693` — factores para pasar unidades ↔ cajas ↔ master en Stock
- `recepcion.js:2632` / `:2674` — lo mismo para Racks
- `modulo_talleristas_arts.js:180` · `193` · `229` · `240` · `476` — alta de artículos a un tallerista
  (y **escribe** `Uni_x_Caja` en la línea 476)

Es el único de los cuatro que además **se escribe desde el front**, así que repuntarlo a `GV_UxB`
pide tocar el alta, no sólo la lectura.
