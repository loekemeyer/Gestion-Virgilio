# Reglas Compras Oc — OC, generador de OC, proyección, Est. Madre de compras, recepción de mercadería de talleristas

> Movido de `CLAUDE.md` el 2026-10-13 (poda 3ra tanda, pedido de Luis) **sin cambiar una palabra**.
> **Leerlo ENTERO antes de tocar algo de este tema.** Las reglas siguen valiendo igual que cuando estaban en CLAUDE.md.

## ⚠ REGLA (Thomas, 2026-10-13, v30.28): PISO DE STOCK DEL SUPER en el generador de OC

Un artículo de **baja rotación que compra un super** quiebra stock: el super no compra todos los
meses, pero cuando compra se lleva un pedido grande, y la Estadística Madre (promedio de ventanas
6/12 meses) lo diluye. Caso 789 "Pisa Papas" (Chef): madre 8,83 caj/mes → máximo OC `ceil(8,83×1,5)`=14,
y Chango Mas (Dorinka 2686) había pedido **18** → quiebre.

- **NO se infla la Estadística Madre** (es cuadro único LK+Gestión, arrastra `GP2.est_madre` y el
  semáforo de colores, y el motor vive en LK). El piso va en el **máximo de la OC**, en Virgilio.
- **Piso** = **percentil** de los pedidos del super (no el promedio —daría 7,33, menos que hoy— ni el
  máximo —sería la *incorporación*, siempre la compra más alta y puntual). Config en
  `Stock_Config('piso_super_percentil', default 0,75)` y `('piso_super_meses', default 12)`.
- **Vista `gv_piso_super`** (por `cod_canon`, cliente activo en `GV_Supers`, pedidos de `Entregas_Virgilio`
  últimos 12 m) → `vista_generador_oc` hace `maximo = GREATEST(maximo, piso_cajas)`.
- **Se auto-apaga en alta rotación**: si el motor ya proyecta más que un pedido del super, gana el
  motor y el piso es invisible (cero sobrestock). Medido 13/10: 129 códigos con super, el piso solo
  **muerde en 13** (baja rotación); 789 pasó de máximo 14 / total 8 a **17 / 11**.
- Límite: hoy `Entregas_Virgilio` tiene ~4 meses; la ventana de 12 m recién pesa con más historia.
  Piso por `cod_canon` sin split de empresa (un dual aplicaría el mismo piso a LK y CH; sólo muerde
  en baja rotación). Centinela `GV_Reglas_Centinela` id 455 (patrón `gv_piso_super`).
- `sql/gv_piso_super_oc_v3027.sql`.

## ⚠ Regla del dueño (2026-09-15): Oscar hace el SKIN — la OC va a su nombre y NO se toca

Al revisar por qué llegaban los WhatsApps de *"SIN OC generada"* aparecieron 14 códigos —casi
todas bombillas, más 506 Abrelata Uña, 500 Abrelata Uña Pata y 280 Manga Repostera— configurados
con proveedor **Oscar** pero recibidos siempre como **Log/ Fabr**. **No es un error de
configuración.** Thomas: *"el 506, todos esos artículos, salen en la orden de compra de Logística
Fabric históricamente, pero los entregaba Oscar. Lo que hacía Oscar era el skin solamente:
nosotros le damos el artículo listo para que le ponga un skin y lo entregue en Virgilio
encajado."* **Oscar falleció; sigue trabajando su nieto**, así que el dueño decidió dejarlo:
*"dejalo ahí"*. **No cambiar el proveedor de esos códigos en `OC_Maximos`.**

⚠ **Lo que sí está mal es la CARGA, y es de procedimiento, no de código.** Medido el 15/09:
`Oscar` **está** en `vista_entidades_recepcion` como tallerista —o sea que el operario lo puede
elegir en la pantalla de recepción— y sin embargo **no figura ni una vez** en
`Entregas Tallerista Virgilio` (0 filas en 5 meses): siempre se carga `Log/ Fabr`. Las OC, al
revés, salen **todas** a nombre de Oscar (31 líneas de esos 14 códigos en los 2 meses que tiene
`Ordenes_Compra`, desde el 13/07). Mientras las dos puntas no coincidan, el aviso va a saltar
siempre. **El arreglo es que al recibir esos artículos elijan `Oscar`, no `Log/ Fabr`.**
Problema 250.

## ⚠ REGLA (Luis, 2026-09-25, v22.68): UNA SOLA PROYECCIÓN — Stock, OC e Importados leen `gv_proyeccion_articulo`

Antes cada módulo armaba la suya (Importados con overrides a mano y familia; Stock sin familia; el
29L caía del lado CH) y el 437E daba un número distinto en cada pantalla. Hoy los cuatro lectores
(`vista_stock_procesada`, `vista_generador_oc`, `gv_importados_ordenes`, `v_importados_ordenes`)
toman la misma vista: código pelado → `proy_cajas_mes`, `COD LK` → `proy_lk`, `COD CH` → `proy_ch`.

| regla | dónde |
|---|---|
| sin ventas entre empresas (Chef 1434 = Loekemeyer Hnos, LK 411 = Chef SRL) | LK `ventas_clientes_internos` |
| venta de Chef con **L** a **Cencosud** o **Tierra del Fuego** → cuenta en **LK** del código base; el resto de Chef (Dorinka, Lia Rojas) queda en Chef | LK `ventas_proy_lineas` |
| el principal **suma a su familia** (029 → 437E) y el pop-up dice cuánto aporta cada uno | `gv_proyeccion_articulo.detalle_familia` |
| ventana 6 · piso 4.º mejor mes · fallback 12 · índice 1,5 · meses objetivo importados | `Stock_Config` `proy_*`, editable en **OCs → ⚙ Configuraciones** (`gv_proy_config_guardar`) |

⚠ **Nada va fijo en el código**: LK lee los parámetros con `proy_cfg()` por `v_lk_config`, así que
un cambio impacta en el sync diario de las 06:20 ART, no en el acto.
⚠ **Los overrides manuales de Importados siguen aplicando, aparte y a la vista** (Luis: "separado y
discriminado de momento"). Meses sin stock: pendiente de Luis. **Excepciones por artículo: NINGUNA** (Luis, 25/09, v22.74: *"están bien todos esos"*): se revisaron las 17 familias y las tres donde el secundario pesa más que el primario están bien cargadas — 574E ← 574 (el 574E no vende nada propio: sus 87 cajas/mes son del 574), 580 ← 580E y 607E ← 565. No volver a proponer sacarlas de la familia.
⚠ **Sin venta = sin proyección** (Luis, v22.70: *"no le pongas una proyección a mano, ya no va más eso"*): Importados ya no cae al `est_madre_seed`; la fuente dice `sin proyeccion` y vale 0. `sql/gv_importados_sin_seed_v2270.sql`.
⚠ En Stock, **buscar exacto un principal trae sus secundarios** (437E → 029, 607E → 565), leídos de `familia_principal`/`es_secundario` de la fila. `tests/stk-busca-secundarios.cjs`.
⚠⚠ **El SECUNDARIO no tiene proyección propia en NINGÚN lado** (Luis, v22.72: *"toda la proyección del secundario se vuelca al principal… si el 580E tuvo demanda, no debería aparecer ni en stocks ni en importados"*). Vale para cualquier secundario, sea importado o nacional (580E → 580, 574 → 574E). En `gv_proyeccion_articulo` su fila va en 0; `proy_propia` guarda su venta, que el principal muestra en «incluye». `sql/gv_proyeccion_secundario_cero_v2272.sql`.
⚠⚠ **La proyección va SIEMPRE en CAJAS ENTERAS, en todos lados** (Luis, v22.84: *"76 unidades tiene que figurar 72 (3 cajas redondas)"*). Se redondea en la FUENTE, `gv_proyeccion_articulo`: `proy_lk` y `proy_ch` al entero más cercano y `proy_cajas_mes = round(lk) + round(ch)`; Importados en unidades sale múltiplo exacto de la caja. Retira el criterio de la v22.73 (2 decimales). **Mínimo 1 caja si vende algo** (Luis, v22.86): si el redondeo da 0 y la venta es > 0, va 1 caja al lado que más vende (eran 14 códigos). El generador de OC toma `proy_lk`/`proy_ch` directo en los duales (la proporción dejaba 22,000…014 y el `ceil` del máximo salía 1 de más). `sql/gv_proyeccion_cajas_enteras_v2284.sql`.
⚠⚠ **El front NO vuelve a sumar la familia** (Luis, v22.71: el 580 salía 108 = 58,50 + 49 y el 580E "—"): la proyección que llega de la base YA trae la familia sumada. `openStockAdmin` no consolida con `EQUIV_FAMILIAS` y `ocgFetchProyeccion` lee `gv_proyeccion_articulo` (sin secundarios). `tests/stk-proy-sin-doble-familia.cjs`.
⚠ `ventas_mensuales_cod` la pisó otra sesión el 25/09 y perdió la familia: ahora tiene centinela.
**Chequeo:** `select * from public.gv_reglas_perdidas;`. `sql/gv_proyeccion_unica_v2268.sql`.

## ⚠ Regla del dueño (2026-09-18): en las OC la PROYECCIÓN es siempre rey

**Thomas, 2026-09-18, sobre el generador de OCs:** *"Proyección es siempre rey"*.

El **Máximo** de un artículo es `ceil(proyección × índice)` y **nada lo topa**. Si eso da más que
la capacidad de góndola, **se pide igual** y el excedente va a racks. Medido el 18/09 con el **505**:
capacidad 3340, proyección 2342,33 × índice 1,5 = **3514**, y el máximo es 3514.

Es lo que ya hace `vista_generador_oc`, así que **no hay nada que cambiar** — está escrito acá para
que nadie vuelva a "arreglarlo" agregándole un `min(proy × índice, capacidad)`.

**La capacidad manda en un solo caso, y no es una excepción a la regla: cuando NO hay proyección**
(`proy = 0`, artículos sin ventas). Sin proyección no hay rey: el objetivo pasa a ser llenar la
góndola. Eran **10 de los 238 activos** al 18/09 a la mañana (109 Sac Zincado, 618, 630E, 631,
631E, 634E, 635E, 636E, 857, 613); **desde la v20.09 son 6**, porque tres de ellos —**618, 631 y
857**— figuraban ahí **por un bug de la cuenta**: tienen `proy_uni_mes = 0` pero `proy_cajas_mes`
de 0,17 / 0,33, y el generador leía la columna de unidades. Sí tienen proyección, mínima, así que
mandan ellos y no la góndola.

⚠ **El tilde `llenar_gondola` de ⚙ Configuraciones hace exactamente lo contrario** — pisa la
proyección con la capacidad, incluso cuando la proyección es más alta. **Al 18/09 no lo tiene
tildado ningún artículo (0 de 238)**, y no hay que tildarlo salvo que el dueño lo pida para un
código puntual.

⚠ **El tope existió hasta HOY a las 13:26**, y lo sacó esta misma regla: la **v19.71** cambió
`LEAST(ceil(proy × índice), cap)` por `ceil(proy × índice)` en el CASE del Máximo (*"no contemples
el máximo de góndola para pedidos. Tenemos que tener la mercadería que hace falta, después vemos
cómo la guardamos"*). Midió **49 códigos que suben el Máximo, 33 que pasan a pedir más, +2.178
cajas** (7.324 → 9.502). La flecha roja **⤓ "Topado a la capacidad de góndola"** quedó huérfana ahí
mismo y **se sacó en la v19.78** (problema 419) — no era un resto viejo, estuvo diciendo la verdad
hasta esa tarde. Si vuelve a aparecer un cartel de tope, está mintiendo.

**Consecuencia aceptada, no un bug:** comprando por encima de la góndola, el aviso de recepción
*"no entra en góndola"* salta más seguido y el excedente va a racks.

⚠ **Y la proyección sale de `proyeccion_madre`, que la empuja LK — no se calcula acá.** El cron
`sync-proyeccion-madre-virgilio` (jobid **25 en LK**) era **semanal** y su única corrida del 16/09
cayó adentro de los cuatro días en que la base de LK estuvo ahogada (15–18/09, hasta 2.130 corridas
fallidas por día): se perdieron 7 días de dato y el watchdog, con umbral de 9 días, no dijo nada.
Desde la **v20.38** el cron es **diario** (`'20 9 * * *'` = 06:20 ART) y el umbral de
`watchdog_frescura_datos()` es de **40 h**. Antes de mirar un número del generador:

```sql
select public.watchdog_frescura_datos();   -- avisos=0 y cuántas horas tiene la proyección
```

⚠ **El sync tarda ~70 s y el MCP corta a los 60**, así que llamarlo desde una sesión hace ROLLBACK
y no escribe nada (el delete+insert está adentro de la función). Se corre con un job de pg_cron de
una sola vez y después se borra con `cron.unschedule`. §3.ks.

**Chequeo:**

```sql
select count(*) filter (where llenar_gondola)                as pisan_la_proyeccion,   -- tiene que dar 0
       count(*) filter (where activo and tiene_prov_real
                          and proy = 0 and cap > 0)          as sin_proy_van_por_cap,  -- 6 (v20.09)
       count(*) filter (where activo and tiene_prov_real)    as activos                -- 241 al 18/09 (eran 238: los 3 duales con proveedor pasaron a 2 filas cada uno, v19.84)
  from public.vista_generador_oc;
```

## ⚠ REGLA (Luis, 2026-09-22, v21.14): generar las OC a mano MUEVE el ciclo automático

**Luis, textual:** *"OCs. Generación manual. Si se generan manualmente, que consulte cuándo
retomar el ciclo de generación automática en ese momento."*

El cron **50** generaba todos los miércoles y su único guard era *"¿ya hay OC de HOY?"*: una
corrida manual del lunes **no frenaba la del miércoles**, que salía dos días después.

Ahora el ciclo tiene un **ancla**, `GV_OC_Auto.proxima_auto`, y el cron corre **todos los días**
llamando a **`gv_oc_auto_corrida()`**:

| situación | qué hace |
|---|---|
| `hoy < ancla` | `pospuesta_hasta:<fecha>` — no genera |
| `hoy >= ancla` | genera y adelanta el ancla a `hoy + cadencia_dias` (7) |
| ancla en **NULL** | ciclo histórico: **sólo miércoles** (es el fallback, del backend y del contador) |

Al generar a mano, la pantalla pregunta y escribe el ancla con **`gv_oc_auto_programar(fecha,
motivo)`** (supervisor adentro de la RPC). **La fecha puede ser cualquier día**, no sólo
miércoles: el `schedule` ya no decide nada, decide el ancla.

⚠ **`generar_ocs_automaticas(boolean)` NO SE TOCÓ**: el ciclo vive en el envoltorio, así que otra
sesión puede seguir editando esa función sin pisar la regla.

⚠ **El ancla avanza también con `sin_items` y `ya_hay_del_dia`** (el turno de la semana ya se
consumió) y **no avanza con `error:`**, para que una caída se reintente sola al día siguiente.

⚠ **El jobname sigue diciendo `ocs-auto-miercoles` y ya no es cierto**: `update cron.job` da
`permission denied for table job` y `cron.alter_job` no tiene `job_name`.

⚠⚠ **Generar a mano NO mueve el ancla solo: la mueve el DIÁLOGO** (v21.25). El backend no puede
adivinar cuándo se retoma, así que si el supervisor cierra con «Dejarlo como está», el ancla queda
donde estaba — y si estaba en hoy o mañana, la corrida de las 07:00 **vuelve a generar todo**,
porque el único guard propio de `generar_ocs_automaticas` es *"ya hay OC de HOY"* y lo de ayer no
lo mira. Medido en transacción abortada: con OC del día anterior y el ancla en hoy, genera **150
líneas**. Por eso el diálogo avisa en amarillo cuando el ancla está a un día o menos, y el botón
de escape dice qué día sale si no se elige nada. **La decisión es del supervisor; lo que no puede
es ser invisible.**

**Chequeo:** `select * from public."GV_OC_Auto";` · `select * from public.gv_reglas_perdidas;` ·
`node tests/oc-auto-ciclo.cjs`. `sql/gv_oc_auto_ciclo_v2114.sql`, §3.mk.
**Rollback, una línea:**
`select cron.alter_job(50, schedule := '0 10 * * 3', command := 'select public.generar_ocs_automaticas()');`

## ⚠ REGLA (Luis, 2026-09-22, v21.01): en el generador de OC, **`activo` NO es una decisión**

**Luis, al ver el 838 en OCs:** *"quiero entender por qué figura el 838 en OCs y la lógica
subyacente para encontrar otros códigos que estén errados"*.

`vista_generador_oc` arma su universo con la **UNIÓN de CINCO fuentes** — stock
(`vista_saldos_stock`), proyección (`proyeccion_madre`), **demanda** (pedidos pendientes),
capacidad (`Capacidad_Sector`) y configuración (`OC_Maximos`) — y después resuelve:

```sql
COALESCE("OC_Maximos".activo, true) AS activo
```

> **Un código sin fila en `OC_Maximos` entra igual y nace ACTIVO.** "Activo" no dice *"alguien
> decidió que esto se compra"*: dice *"nadie dijo lo contrario"*. Lo único que lo saca de la
> lista de compra es `tiene_prov_real` (`proveedor IS NOT NULL`).

**Caso testigo:** el **838** (Filtro para Mate y Café) no está en `OC_Maximos`; lo arrastró la
**demanda** — dos pedidos web de Chef de **Dorinka** (CH 0025 · 48 cajas, CH 0027 · 32), entrega
25/09. Sin góndola, sin capacidad, sin proyección y sin proveedor: **no se puede pickear ni
comprar**. Y no es teórico — la tanda **E41A** se pickeó el 15/09 y las tres filas del 838 en
`Movimientos_Stock` quedaron en **delta 0**. El **838E** (Rallador Cilíndrico Mini), que es el
que está vivo, sí tiene las cuatro cosas.

⚠ **Lo que NO es un error y por eso el centinela no lo lista:** 73 códigos tienen fila activa
**sin proveedor**, y **72 terminan en E** — son **importados**, no tienen proveedor local y está
bien que no lo tengan. Filtrar por *"activo sin proveedor"* da 73 falsos positivos.

⚠ **Y la comparación pela el sufijo de empresa antes que los ceros.** Un dual entra al
generador como `438E LK` / `438E CH` (`universo_e`) pero en `OC_Maximos` vive como `438E`:
comparando el código crudo salen **8 duales sanos** como si estuvieran sin configurar.

**Chequeo:** `select * from public.gv_oc_codigos_sin_config order by pedidos desc;` — al 22/09
son **16** (7 con pedidos, 82 cajas), con el `motivo` que dice cuál duele: *pedido sin góndola*,
*pedido sin OC*, *stock sin OC* o *resto* (código viejo o mal tipeado: `438E-`, `501B`, `587C`).
`sql/gv_oc_codigos_sin_config_v2101.sql`.

## ⚠ REGLA (Luis, 2026-09-24, v22.40): el descuento de OC de una recepción NO se puede perder

**Caso:** 24/09 11:49 la base cortó por timeout y la carga de Blist-Pack (763 + 764) dio 500 en
`gv_oc_aplicar_recepcion`: el 764 (19 cajas) quedó sin imputar a la OC 1668 (0/15). `recepcion.js`
la llamaba sin mirar el resultado, y **`supabase.rpc` no rechaza con un 500: resuelve con `{error}`**.

| capa | qué hace |
|---|---|
| celular | **cola persistente** (`rcp_oc_pend_v1` en localStorage, v22.42): cada recepción queda ahí **hasta que la base la acepta** — reintenta a los 5 s, 15 s, 30 s, 1 min y después cada 2 min, y también al abrir la app y al volver la conexión. Sobrevive al cierre de la app |
| backend | cron **`gv-oc-recepcion-red`** (`7,19,29,43,55 * * * *`, minutos impares fuera del 57 y el 68) → `gv_oc_recompute_recepciones_recientes(36)`: recalcula las OC de todo código recibido en las últimas 36 h. Idempotente: si cuadra no escribe (22 códigos, 1,4 s) |

**Por qué falló, medido:** la función tarda **0,16 s** normalmente. A las 11:49:08 le tocó la cola de
**8 consultas pesadas en el mismo segundo** (A Programar: `gv_cuarentena_marcar` ×3 y
`gv_ppp_web_dia_salida` ×3; Facturación: `facturacion_neto_lote` ×2), todas cortadas a los 8 s:
esperó 15,4 s y cayó por `57014`. No es la recepción la que pesa; es la saturación de un momento.

⚠ **El cron 93 (miércoles) NO se toca**: es del circuito de OCs automáticas (Luis: *"lo del
miércoles es que se manden las OCs"*). Probado rompiéndolo en transacción abortada: OC 1668 puesta
en 0 → la red la devolvió a 15 / recibida. Problema 544. `sql/gv_oc_recepcion_red_v2240.sql`,
`tests/rcp-oc-reintento.cjs`. Rollback: `select cron.unschedule('gv-oc-recepcion-red');`

## ⚠ REGLA (Luis, 2026-09-22, v21.30): el operario puede recibir un código que NO es del proveedor

**Luis, textual:** *"cuando se elige al tallerista deberían aparecer los códigos asignados a el
como proveedor y un botón más grande que diga «Introducir Código diferente» … Una vez envíe el
dato de la recepción, debería aparecer un botón para notificar a Thomy por WhatsApp (como si
hubiesen recibido mercadería > a las OCs establecidas) que no impida la recepción"*.

El buscador de códigos activos ya existía desde la **v15.76**, pero era el `+` de **Log/Fabr** y
**de nadie más**: si Pedernera entregaba un código que no estaba en su lista, el operario no tenía
forma de cargarlo. Y con la lista vacía la pantalla cortaba con un `return` que dejaba sólo el
cartel *"No hay códigos"*. Hoy el botón grande **«🔍 Introducir código diferente»** está en todos
los proveedores, con lista vacía también.

⚠ **El código agregado así NO se asigna al proveedor** — sólo en Log/Fabr, que es como venía. Si
se guardara en `Articulos Virgilio X Tallerista`, la próxima entrega del mismo código entraría en
silencio y el aviso a Thomas no saldría nunca más. Es exactamente lo que se quiere evitar.

⚠ **El aviso es el del exceso de OC, no uno nuevo.** Un código que no es del proveedor no tiene OC
suya → `ocRef = 0` → ya entraba por `opExcesoItems` y el botón de WhatsApp ya aparecía. Lo que
faltaba era **decirlo por su nombre**: `noAsig` hace que el mensaje diga *"un proveedor entregó un
código que no está asignado a él"* en vez de *"SIN OC generada (OC = 0)"*, que es lo mismo que ya
se corrigió en la v19.57 para el caso de la OC ajena.

**Los tres casos del mensaje, y no se pisan:**

| qué pasó | qué dice |
|---|---|
| el código está en la OC de **otro** proveedor (`ajena`, v19.57) | *"la OC es de Poly (155 pendientes)"* |
| el código **no está asignado** a este proveedor (`noAsig`, v21.30) | *"NO está asignado a Lucho ni tiene OC suya"* |
| es suyo pero no hay OC (`sinOc`, v17.99) | *"SIN OC generada (OC = 0)"* |

**Chequeo:** `node tests/rcp-codigo-diferente.cjs` — corre la pantalla de verdad y mira las dos
mitades (que el botón esté para un tallerista común **y** que Log/Fabr siga guardando fijo).
Verificado que falla contra el código anterior.

### ⚠ Y un código con proveedor puede NO figurar en el módulo de operarios

Lo que el operario ve al elegir a un proveedor sale de **dos tablas distintas**, y ninguna es
`OC_Maximos`:

| tipo de entidad | de dónde salen sus códigos |
|---|---|
| `tallerista` | **`Articulos Virgilio X Tallerista`** por `Cod_Tallerista` + `Linea` |
| `prov_at` | **`vista_articulos_prov_at`** por `proveedor` + `linea` |

⚠ **El barrido se hace con `gv_prov_match`, NUNCA por nombre crudo.** `OC_Maximos` dice
`Martin C` / `Carlos E` / `Pettofrezza` / `Blistpack` donde la entidad se llama `Martin` /
`Carlos` / `Rafael` / `Blist-Pack`: comparando el texto pelado salen **91 códigos "a nombre de
otro"** que están perfectos. Con el matcher, de los 238 activos con proveedor faltan **49**.

⚠ **Y el `Cod_Tallerista` es POR LÍNEA**: `Codigos X Tallerista` tiene una fila por (nombre,
línea). **Blist-Pack no tiene fila CH**, así que sus 5 códigos de Chef (758, 762, 763, 764, 769)
no pueden aparecer aunque se los dé de alta — falta ese dato, lo define el dueño.

⚠ **`vista_articulos_prov_at.linea` sale de un LATERAL contra la tabla de TALLERISTAS**, que no
tiene nada que ver con un prov AT. Un código que no esté ahí sale con `linea = ''` y el
`.eq("linea","LK")` del celular no lo encuentra nunca. Al 22/09 era **1 de 87** (el 193, Kuffo).

**✅ APLICADO el 22/09 con el OK de Luis: 40 filas nuevas** (backup
`zz_backups."GV_Backup_ArtXTall_20260922"`, 335 → 375), verificado como `anon`. Y la vista
`vista_articulos_prov_at` ya cae a `OC_Maximos.linea` cuando la tabla de talleristas no tiene el
código, así que el 193 sale `LK` y **ninguno de los 87 queda sin línea**.

⚠ **Las tres correcciones que dictó Luis y bajaron el alta de 43 a 40:**

| qué dijo | qué se hizo |
|---|---|
| *"231, 232, 233 los hace log fabr"* | van bajo **Log/ Fabr**, no Tierra Nativa. El dato no lo desmiente: esos 3 tienen **cero entregas** registradas. ⚠ El **55215** (Palo de Amasar 40) **sí** es de Tierra Nativa — 208 cajas el 26/08. Son cosas distintas |
| *"582E y 119 no se fabrica, se importa listo para la venta"* | **no entran**: un importado no se recibe por el módulo de talleristas |
| *"581T es discontinuo… si no genera OC no me jode"* | **no entra**. Medido: `total = 0` en `vista_generador_oc` (proy 0, stock 73 = capacidad), así que hoy no genera OC. ⚠ Pero apenas se venda una caja el `total` sube y **sí** la genera: si es discontinuo de verdad, va `activo = false` como el 591 |

⚠ **Y quedan DOS cosas de config, que son de Luis y NO se tocaron:**

1. **231/232/233 siguen diciendo `Tierra Nativa` en `OC_Maximos`**, así que generan **17 cajas**
   de OC a ese proveedor (5 + 7 + 5, todo por pedidos). El operario ya los ve bien; lo que falta
   es la config. SQL propuesto al final de `sql/gv_recepcion_codigos_con_proveedor_v2130.sql`.
2. **119 genera 19 cajas a Lucho y 582E genera 18 a Garcia** — si se importan, esas dos OC están
   mal emitidas.

**Chequeo:** la consulta de barrido está al final de
`sql/gv_recepcion_codigos_con_proveedor_v2130.sql`. Al 22/09 devuelve **11 filas y las 11 están
explicadas** ahí mismo (5 de Blist-Pack CH, 3 que Luis sacó y los 3 palos, que esperan la config).

## ⚠ REGLA (Thomas, 2026-09-30, D4): lo NUEVO o REINCORPORADO se proyecta con el promedio desde que volvió

En LK, `fn_proyeccion_oc_virgilio` (CTE `_vt_*`): un artículo cuya primera venta después de 6+ meses sin vender cae en los últimos 6 meses, y que ya tiene **2+ meses cerrados**, se proyecta con el **promedio desde que volvió** si da más que la regla del 4.º mejor mes (sólo sube). El mes en curso no cuenta. **Los códigos de 5 dígitos no entran**: se hacen contra pedido, no se stockean. Medido: suben 38 artículos (198E 35 → 70, 702EN 29,5 → 59). **Y los de 5 dígitos numéricos (`^[0-9]{5}$`) no tienen proyección en absoluto** (D25, filtro `v24.71-5dig` en el WHERE final): al 30/09 sólo el 55215. `sql/lk_proyeccion_reincorporados_v2470_LK.sql`.

### ⚠ v24.70 (Luis): la TV son DOS columnas — «Días» va con Operarios y lleva el m³; «Total por día» NO existe más

**Luis:** *"pone el bloque de «dias» junto con el de «operarios» y «en este momento» agregandole los m3 por
día. «Total por día» sacalo, que quede una vision estilo «dos columnas»"*.

| columna | qué lleva |
|---|---|
| izquierda | veredicto + avisos + tandas |
| derecha | Operarios · **Días** (con columna **M³**) · En este momento (crece) |

- El M³ del día es el **mismo** que daba «Total por día»: la suma de las tandas del día (`porDia`), con el m³ del
  árbol de la PPP de respaldo. El desglose por camión se fue con la tarjeta; el camión sigue vivo en el veredicto.
- La mudanza a dos columnas para pantallas < 1500 px se borró: ahora siempre son dos.
- `monUnirCentroOeste` queda en el archivo sin llamador (≡ index.html).
- **Chequeo:** `node tests/mon-tv.cjs` (verificado que falla contra la v24.69: 3 columnas, sin M³, con «Total por día»).

### ⚠ v24.88 (Luis): la tabla de tandas de la TV vuelve a llevar CLIENTE y NP

**Luis:** *"tiene que aparecer en la parte de la izquierda junto a las tandas y los m3: el cliente y detalle de NPs"*.
Se retira el «tanda · m³ · progreso y nada más» de la v23.92. Columnas: **Tanda · M³ · Cliente · NP · Progreso**
(la zona y los días siguen afuera). Cliente resumido (sin SRL/SA) y **«+N»** si la tanda lleva varios; las NP con el
prefijo una vez por empresa (`LK 0101·0102 · 98615`), hasta 2 renglones; el `title` trae la lista completa. La
columna izquierda pasó a **1,15fr** contra 1fr. `resumirCliente` / `clienteTanda` / `npsCortas` en `monitor/tv.html`.
**Chequeo:** `node tests/mon-tv.cjs`.
**v24.92 (Luis): las NP van en UNA línea y, si no entran, ROTAN como cartel de Wall Street** (*"en caso de que haya
más NPs de las que entran, que empiece a rotar"*). `activarTicker` duplica el texto sólo en la celda que se desborda
(giro sin salto, ~6 caracteres por segundo); las que entran quedan quietas. Columnas 17/9/26/28 %. Candado en `mon-tv` (E32A con 9 NP rota, E30A no).
**v25.01 (Luis, 30/09):** en **Días** el número de pedidos va grande y el % chiquito abajo, los dos en color · rota
también el **cliente** · las luces **P/A quedan centradas** (quién la tiene y hace cuánto va ABAJO, `.semdet`) · cuadro
nuevo **🚚 Pendientes de hoy** (`pendientesHoy`: lo de hoy sin CCN, por tanda + cliente, con el estado del más atrasado,
lo más atrasado primero). `activarTicker` es idempotente y se re-mide al cambiar el tamaño (la pestaña oculta del admin
mide 0). Columnas 16/9/33/28 %. La TV pesa 99 KB contra el techo de 100 de `mon-tv`.
**v25.6 (Luis, 30/09):** el cliente muestra **todos los nombres** (no «+N») y rota si no entra · el cartel va a **3/4** de
velocidad (4,5 caracteres/s) · **nada de la columna derecha se corta**: «En este momento» muestra sólo lo que entra
(se fue el mínimo de 6) y «Pendientes de hoy» toma a lo sumo la mitad del alto libre, con «+ N más» · las letras van en
**`--u` = min(1vh, 0,5625vw)**, así en una pantalla más angosta que 16:9 achican con el ancho.

## ⚠ REGLA (Luis, 2026-09-30, v25.5): el DESGLOSE por cliente del pop-up de proyección cuenta lo MISMO que el total

Caso 702E julio: el total decía 1.644 u (137 cajas: 18 del 702E + 119 del **702EN**, su secundario) y el
desglose «🧾 Facturado» 216 u. El total (`ventas_mensuales_cod`) suma la familia y lee `ventas_proy_lineas`
(regla L, sin ventas entre empresas); el desglose pedía sólo el principal sobre `sales_lines` cruda.
Hoy `gv_ventas_clientes_mes_cod` manda la familia a **`fn_ventas_clientes_mes_fam_virgilio`** (LK), con los
mismos tres criterios, y cada cliente dice de qué código salió (`702E 7 · 702EN 59`, columna `codigos`).
`fn_ventas_clientes_mes_virgilio` (la vieja) queda sin llamador, de rollback. Centinela `Equivalencias_Familia`.
**Al tocar un criterio del total mensual, tocar también el desglose.** Problema 640.
`sql/gv_proy_desglose_familia_v254.sql`, `sql/gv_proy_desglose_familia_v254_LK.sql`, `tests/proy-entregadas.cjs`.

## ⚠ REGLA (Luis, 2026-10-06, v27.12): COMENTARIOS por recepción en Pendientes (Recepción de Mercadería)

Botón redondo 📓 en el encabezado de cada tarjeta de Pendientes (`recepcion.js`, `pendCard` → `pendComentBtn`):
abre un **hilo** de comentarios sobre el estado de esa recepción. Badge azul con el conteo (batch al abrir,
`pendComentConteos`).

- **Append-only en `GV_Recepcion_Comentarios`** (`id`, `recepcion_id` → `Control_Modo_OP(id)`, `autor`, `texto`,
  `created_at`): anon **SELECT + INSERT**, nunca UPDATE/DELETE (es un log, como `GV_Cuarentena_Comentarios`). RLS on,
  policies `gv_rcpc_sel`/`gv_rcpc_ins`. Se instaló con `select public.gv_rcp_coment_instalar();` (DDL de 1.er nivel se
  cuelga en el MCP; va adentro de la función).
- **Mismo "quién escribe" que Recibido**: chips Nora/Pablo/Otro de `GV_Recepcion_Receptores` (`pendReceptoresLista` +
  `pendNombreCap` + `pendReceptorGuardar`), reusados dentro del cuadro de comentarios.
- **No frena nada**: no toca el checklist ni el botón Enviar; se puede comentar aunque la recepción no esté completa.
- Si la lectura del hilo falla, lo dice; no se queda vacío ("no pude leer" no es "sin comentarios").
- **Chequeo:** `node tests/rcp-comentarios.cjs` (candado estático: las funciones de `recepcion.js` son de módulo, no
  viven en `window`).

## ⚠ REGLA (Luis, 2026-10-07, v28.02): en el detalle de una OC — ENTREGA PROY. y 📓 log por línea

- Al lado de «Pedido» (Compras → OC de un tallerista) va **Entrega proy.**: lo que el tallerista confirma o se estima que entrega
  en la vigencia de la OC (1 semana). Lo carga un supervisor; queda en `Ordenes_Compra.gv_entrega_proy` (+ `_por` / `_at`) por
  `gv_oc_entrega_proy_guardar`. El **📓** abre el log de esa línea (`GV_OC_Log`, append-only, fecha/hora y autor; RPC
  `gv_oc_log_agregar` / `_leer` / `_conteos`).
- **Sólo pantalla**: no va a impresos, WhatsApp ni Excel (Luis: *"de momento que se vea ahí el dato"*).
- **v28.22 (Luis): el detalle de la OC ya NO edita.** Pedido es texto, se fueron el ⛽ de cada línea, la barra verde «Llenar góndola» (con «Guardar cantidades»), la línea de totales y la nota de Recibido; el 📓 va al tamaño del ⛽ (`oc-fillbtn`). Las funciones `ocDet*` quedan sin puerta.
- **v28.24 (Luis): la tabla del detalle va al ancho del dato** (`width:auto`), encabezados y números centrados, relleno 5 px, Entrega proy. de 46 px. v28.25: cada encabezado dividido con una línea, como Stock · Máximo · Cap gónd.
- **v28.27 (Luis: *"si no te quedó registro en ningún lado estamos mal"*): Entrega proy. se guarda con el botón «💾 Guardar entrega proy. (N)»** de la barra, no al cambiar la casilla; salir con cambios sin guardar pide confirmación. **Cada guardado queda en `GV_OC_Entrega_Proy_Hist`** (valor, anterior, quién, cuándo), aunque después se borre; `Ordenes_Compra.gv_entrega_proy` es sólo el valor de hoy. El 📓 (`GV_OC_Log`) es aparte. Lo cargado antes de la v28.27 (el 50 del 248 del 07/10) no quedó en ningún lado.
- **v28.29 (Luis): al lado de la casilla van DOS botones chiquitos apilados: arriba 💾 (guarda ESA línea; se pinta amarillo con un cambio sin guardar) y abajo 📓 (log).** Se fue el botón «Guardar entrega proy.» de la barra.
- `sql/gv_oc_entrega_proy_log_v2802.sql` (v28.21; salió como v28.03, número que quedaba por debajo del 28.2 de otra sesión), `tests/oc-entrega-proy.cjs`.

## ⚠ (Luis, 2026-10-08, v28.60): ADS Stock — tallerista a la izquierda del código y E.M. que cierra con el saldo

- Columna **Tallerista** (los de la OC vigente del código) a la izquierda de Cód. Sólo pantalla (el Excel tiene formato de Luis).
- La **E.M. plazo** que se muestra sale del saldo del servidor (`disp − comp − saldo`): la base cuenta los días de E.M. con
  `gv_ads_em_dias` (distribución de demora) y el front con la fórmula vieja daba 0 mientras el saldo restaba 1 (058: −16).

## ⚠ REGLA (Luis, 2026-10-08, v28.61): una OC de MENOS DE 10 CAJAS sólo se pide con la GÓNDOLA a menos del 30 %

- Por código (el total antes de repartir entre proveedores): góndola (`terminado`) ≥ 30 % de la capacidad → no se pide.
  Sin capacidad cargada no se frena. `gv_oc_chica_frenada()` (lectura, anon) es la única cuenta; parámetros en
  `Stock_Config` (`oc_chica_cajas` 10, `oc_chica_gondola_pct` 0,30).
- La usan `generar_ocs_automaticas` (marcador `v28.61-oc-chica`) y el generador manual (`ocgEnter`: a pedir 0 y la nota
  «⏸ N OC de menos de 10 cajas no se piden»; si la lectura falla lo dice). Al 08/10 frena 18 códigos.
- `sql/gv_oc_chica_frenada_v2861.sql`, `tests/oc-chica-gondola.cjs`.

