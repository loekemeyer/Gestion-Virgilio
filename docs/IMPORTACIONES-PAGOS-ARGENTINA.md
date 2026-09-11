# Pagos de importación al exterior — cómo funciona hoy (Argentina) y cómo lo hacemos nosotros

> Estado al **2026-09-11**. Documento de **contexto de negocio**, no instrucciones de sesión.
> Es la base del módulo de **cuenta corriente con los proveedores chinos** (pedido de Thomas,
> 11/09; tarea Planify 3186). Si algo de acá cambia, actualizarlo — el modelo de datos depende
> de esto.
>
> ⚠ **La fuente de verdad operativa es el despachante y el banco**, no este archivo. Acá está el
> marco para entender POR QUÉ la plata sale como sale, y qué hay que guardar de cada movimiento.

## 1. El marco cambiario vigente

Después de la **Com. "A" 8226 del BCRA (14/04/2025)** el pago de importaciones de bienes quedó
**a la vista**: para los despachos oficializados desde el 14/04/2025 el plazo de espera para
acceder al mercado de cambios es de **0 días** desde el registro de ingreso aduanero. (Los
despachos anteriores a esa fecha quedaron con los 30 días del régimen viejo.) La **Com. "A" 8417
(09/04/2026)** es de exportaciones de personas humanas, atesoramiento y coberturas: **no cambia**
el régimen de pago de importaciones.

Es decir: **mercadería ya nacionalizada = se puede girar ya, sin plazo y sin riesgo de seguimiento.**

### Las tres formas de pagar y qué arrastra cada una

| Forma | Cuándo | Qué arrastra |
|---|---|---|
| **Deuda comercial** (mercadería ya nacionalizada) | después del despacho a plaza | la más limpia: el despacho ya existe, no hay nada que demostrar después |
| **Pago a la vista** | contra embarque / llegada | seguimiento: hay que registrar el ingreso aduanero |
| **Pago anticipado** | antes del embarque | seguimiento con reloj: **90 días corridos** para registrar el ingreso aduanero (270 para bienes de capital), contados desde el acceso al mercado de cambios |

### SEPAIMPO: por qué el anticipo es caro en riesgo

Todo pago al exterior se registra en **SEPAIMPO** (Seguimiento de Pagos de Importaciones,
Com. "A" 5060 y sucesivas) y se **afecta a un despacho de importación**. El banco que hace el
seguimiento controla que el ingreso aduanero se registre dentro del plazo; si no, **informa el
incumplido al BCRA** (dentro de los 5 días hábiles del vencimiento). Un incumplido pendiente
**bloquea los pagos siguientes**: entre las condiciones para cursar un anticipo está
*no tener pagos con plazo vencido para demostrar el registro de ingreso aduanero*.

O sea: **un anticipo que se demora te traba toda la operatoria posterior.** Un pago contra
mercadería ya nacionalizada, no.

### Quién puede cobrar (esto importa para NTL)

Para la norma cambiaria, **proveedor del exterior es el que emitió la factura comercial** a
nombre del importador. Se puede pagar a **un beneficiario distinto del emisor de la factura**
sólo en dos carriles (pto. 10.4 del TO de Exterior y Cambios):

1. **Cesión de crédito** — el no residente que le compró el crédito al acreedor comercial del
   exterior, **sin modificar las condiciones** del crédito original; y
2. **Mismo grupo económico** — con documentación que acredite que las dos empresas del exterior
   son del mismo grupo y que intervienen por cuestiones administrativas/operativas internas,
   ajenas a la voluntad del importador argentino.

Además, si la factura tiene **más de 90 días** desde su emisión al momento de pedir el acceso al
mercado, el banco puede pedir certificación contable o documentación que justifique la demora.
Y desde 2026 los **freight forwarders y agentes logísticos tienen que declarar al exportador real
/ vendedor original de la carga**, así que el desdoble "quién factura ≠ quién cobra" es visible.

Dato operativo: **operaciones de más de USD 100.000 por día** requieren aviso al BCRA **48 h antes**
del acceso al mercado.

## 2. Cómo lo hacemos nosotros

Pagamos contra una cuenta de **freight forwarder en Hong Kong: NTL**. NTL es el que **cobra**;
las fábricas (Becky, Fujian, Hugo Wong, Ownland, Zhixin, Frontier, Kangli) son las que
**producen y embarcan**, y según el caso son las que **facturan**.

**La lógica, en las palabras de Thomas (11/09):** *"a NTL le mandamos plata correspondiente a
facturas que ya me entregaron. En el caso de Becky, la primera factura fue a nombre de ella; esa
factura se la pagué con una carga anterior, funciona así en Argentina. Ahora que tengo que pagar
el segundo pedido, que todavía no embarcó, le voy a pagar con la factura que ya me embarcó."*

Traducido al marco de arriba: **la salida de dólares viaja siempre pegada a una importación que
ya está nacionalizada** (que es lo que se puede girar hoy mismo, a la vista, sin abrir ningún
reloj de 90 días ni riesgo de incumplido en SEPAIMPO), **pero comercialmente esa plata financia
el pedido siguiente**, el que todavía no embarcó. El chino no mira contra qué despacho se giró:
mira que su PI esté cubierto para producir.

### La consecuencia para el sistema: son DOS cuentas distintas, no una

Por eso no alcanza con "cuánto le debo a Becky". Hay **tres ejes que no coinciden**:

| Eje | Pregunta que contesta | Dato |
|---|---|---|
| **Legal / cambiario** | ¿contra qué factura y qué despacho salió este giro? | factura comercial + despacho + SEPAIMPO |
| **Financiero** | ¿a quién se le giró y cuánto? | beneficiario (**NTL** casi siempre), fecha, USD |
| **Comercial** | ¿qué pedido queda cubierto con eso? | el **PI** (`GV_Importados_Baches.pedido_ref`) |

Un mismo giro puede pagar legalmente la factura del embarque de julio y cubrir comercialmente
parte del `PI B260601-2` que llega el 15/11. Y al revés: un PI se puede cubrir con varios giros.

## 3. El Excel de Thomas y la cuenta corriente del sistema (v15.74, 11/09/2026)

Thomas mandó la foto de su planilla — *"este es mi estado actual de deudas al exterior"*:
`docs/img/excel-deudas-exterior-20260911.jpg`.

| A nombre de | Proveedor | FOB | Pago | Pend Giro Directo | Falta | Embarque | | Fecha Pago 30% | Fecha Recup |
|---|---|---|---|---|---|---|---|---|---|
| NTL | Frontier | 14.400 | 4.320 | | 10.080 | 26-oct | | 25-ago | 30-oct |
| NTL | Fujian | 32.388 | 10.000 | | 22.388 | 19-sept | | 05-ago | 25-sept |
| NTL | Zhixin | 10.273 | 3.100 | | 7.173 | 14-oct | | 04-sept | 20-oct |
| Ownland | Ownland | 46.626 | 14.000 | 20.956 | 11.670 | 08-nov | | 09-sept | |
| Becky | Becky | 31.614 | 7.359 | 22.441 | 1.813 | 22-sept | | 02-jun | |
| Hugo | Hugo | 38.640 | 14.041 | 21.952 | 2.647 | 19-sept | | 30-jul | |

**Las reglas que salen de la planilla:**

1. **`Falta = FOB − Pago − Pend Giro Directo`**. Verificado fila por fila.
2. **`Embarque = Fecha Pago 30% + lead time del PI`**. La celda `G3` es literalmente **`=+I3+45`**.
   Los lead times que quedan: Zhixin **+40**, Fujian **+45**, Hugo **+51**, Ownland **+60**
   (coincide con el *"60 days when deposit received"* del PI OL-10139), Frontier **+62**,
   Becky **+112**. La **llegada** es el embarque + los días de viaje (~40–46; Hugo 45).
3. **"A nombre de"** = quién **emite la factura y cobra**: **NTL** (el forwarder de Hong Kong) o el
   proveedor. **Sólo las filas a nombre del proveedor tienen "Pend Giro Directo"** — lo que va
   girado derecho a la fábrica en vez de por NTL. **"Fecha Recup"** sólo aparece en las de NTL.
4. El **"Pago"** es el anticipo ya girado, en general el **30%** (Frontier 30,0 % exacto; Fujian
   30,9 %; Zhixin 30,2 %; Ownland 30,0 %).
5. El **30 % es un parámetro, no una regla** (dueño, 11/09): *"se pagó eso y me lo aceptaron los dos
   proveedores"*, así que Becky (23,3 %) y Hugo (36,3 %) son **un solo giro cada uno**.
6. Los pedidos **sin deuda no están en la planilla**: por eso no figura `PI B260601` (la 1.ª de
   Becky, la que ya pagó y es la factura con la que ahora paga la 2.ª) ni el `323ES suelto`.

### Cómo quedó en el sistema

`sql/gv_imp_cuenta_corriente_v1574.sql`. Dos tablas nuevas, colgadas del `pedido_ref` que ya
existía en `GV_Importados_Baches` (v15.72) — no se duplica ningún pedido:

| Objeto | Qué es |
|---|---|
| **`GV_Imp_Pedido_CC`** | la cabecera de plata de cada pedido: `a_nombre_de`, `fob_total`, `pend_giro_directo`, `fecha_pago_30`, `fecha_recup`. Una fila por (`pedido_ref`, `proveedor`) |
| **`GV_Imp_Pagos`** | **cada giro**: fecha, USD, beneficiario, tipo (`anticipo30` / `saldo` / `giro_directo`) y la **pata legal** (`factura_ref`, `despacho_ref`) |
| **`gv_imp_cuenta_corriente`** (vista, `security_invoker`) | junta las dos con el pedido en curso: FOB, **pagado = suma de los giros**, pend. giro directo, **falta**, saldo, días de viaje y días de producción |
| RPC | `gv_imp_cc_lista`, `gv_imp_cc_set`, `gv_imp_pagos`, `gv_imp_pago_add`, `gv_imp_pago_borrar` (SECURITY DEFINER, anon) |

La diferencia con el Excel es que **"Pago" no es un número tipeado: es la suma de los giros
cargados**. El seed dejó un giro por pedido con el monto y la fecha del 30 %; cuando Thomas cargue
los giros reales se borran esos y quedan los de verdad.

**Front (v15.74)**: la solapa 🚢 En curso tiene ahora dos vistas — **📦 Logística** (unidades, m³,
embarque, llegada) y **💵 Plata**, que es la planilla: A nombre de · FOB · Pagado · Pend. giro
directo · Falta · 💰 Pago 30% · 🚢 Embarque · ♻️ Recupero, todo editable, con los cuatro totales
arriba siguiendo el filtro de proveedor/pedido. El botón **💵 Giros** de cada fila abre el libro de
giros de ese pedido (listar, cargar, borrar). Test `tests/imp-cuenta-corriente.cjs`.

**Chequeo al sembrar**: el `falta` de la vista da exactamente el del Excel — Frontier 10.080 ·
Fujian 22.388 · Zhixin 7.173 · Ownland 11.670 · Becky 1.814 · Hugo 2.647.

### Lo que quedó marcado, sin tocar

- ~~**Frontier**: el Excel dice FOB 14.400 y el motor calcula 14.000~~ → **cerrado (v15.84)**: manda el
  PI, `fob_uni` de 505C pasó a **0,072**. Ya no queda ninguna fila con `fob_difiere`.
- ~~**Frontier, la llegada no cierra**~~ → **cerrado (v15.84)**: *"embarca el 26 de octubre y llega 45
  días después"* → **10/12/2026**. La que estaba mal era la llegada (04/11), que daba 9 días de viaje.
- **Becky `PI B260601-2`**: el 30 % figura pagado el **02-jun** y el PI está fechado el 14/07 en
  §3.bm.13. Y son **112 días** hasta el embarque contra los *"90 días después del depósito"* del PI.
- **Ownland**: el Excel confirma **u$s 46.626**, así que el *"u$s 13.988"* que §3.bm.5 leyó del
  PI OL-10139 es lo que está mal, no el cálculo del motor.

### NTL no es el único canal: hay casos y casos (dueño, 11/09)

Aclaración del dueño al quedar de pasar los Excel: ***"no a todos los proveedores lo llevamos con NTL
y tampoco lo llevamos aparte. Hay casos y casos"***. Va a pasar **dos cosas**:

1. el **Excel de la cuenta de NTL** (la cuenta de Hong Kong), y
2. las **cuentas individuales** con cada proveedor que se lleva **por fuera** de NTL.

Lo que eso implica para el modelo:

- **El canal es por GIRO, no por proveedor.** Un mismo proveedor puede tener plata girada por NTL y
  plata girada derecho. Eso **ya está soportado**: `GV_Imp_Pagos.beneficiario` y `tipo`
  (`giro_directo`) van fila por fila; el `a_nombre_de` de `GV_Imp_Pedido_CC` es la etiqueta del
  pedido (quién factura), no una restricción de por dónde se paga.
- **Falta lo nuevo: NTL es una cuenta corriente en sí misma.** Hasta acá NTL se trata como
  beneficiario de un giro. Pero si hay un extracto de NTL, NTL tiene **saldo propio**: entra lo que
  se le gira y sale lo que le paga a cada fábrica, y las dos patas no coinciden en el tiempo. Eso es
  una tabla aparte (movimientos de la cuenta NTL) que se concilia contra los giros ya cargados — no
  se puede derivar de lo que hay hoy. **Se define cuando llegue el Excel.**

### Lo que todavía no está

- **Imputación cruzada**: hoy cada giro se carga contra **un** pedido. La operatoria real es que la
  plata sale contra la factura de una carga vieja y cubre el PI siguiente — eso se anota en
  `factura_ref` como texto, pero **no hay todavía un vínculo formal factura ↔ despacho ↔ PI**. Si
  hace falta el detalle legal (para SEPAIMPO), se agrega `GV_Imp_Facturas` sin tocar lo hecho.
- Diferencias de cambio, gastos de NTL y pagos en pesos: no están modelados.

## Fuentes

- BCRA, Com. "A" 8226 (14/04/2025) y Com. "A" 8417 (09/04/2026) — texto en
  `boletinoficial.gob.ar` y `bcra.gob.ar/archivos/Pdfs/comytexord/A8417.pdf`.
- BCRA, TO *Exterior y Cambios*, pto. 10 (pagos de importaciones de bienes) y 10.4 (beneficiario).
- BCRA, SEPAIMPO — Com. "A" 5060 y régimen informativo de seguimiento de pagos de importaciones.
- Resúmenes de prensa especializada (aduananews, El Cronista, despachantesargentinos) sobre el
  pasaje de las SIRA al pago "a la vista" y los errores que bloquean pagos.

## 4. El Excel de la cuenta NTL, importado (v15.89, 11/09/2026)

Thomas mandó `Cuenta_Corriente_NTL.xlsx`: **6 hojas** — `Cuenta Corriente NTL` (la cuenta de Hong
Kong entera, 179 movimientos desde el 19/06/2024), `Cuenta Corriente CH` (**la parte de Chef de esa
misma cuenta**, 73 movimientos — no es un filtro: los importes son la porción de Chef), `Ownland`,
`Frontier`, `Becky` y `Resumen`.

### Cómo funciona el circuito (esto es lo que faltaba entender)

1. **Entra efectivo a NTL** (`Efectivo Recibido`, "USD Depositados Efectivo (Damian)") — u$s
   **140.300** en total. Cada depósito paga **3 % de "comisión por subida"** (transfer a Hong Kong).
2. **NTL le gira a la fábrica**: `Advance` (el 30 %) y después `Balance` (el 70 %), cada uno con sus
   **gastos bancarios** (u$s 7 a 15 por transferencia, a veces 60-100). Total transferido:
   **u$s 385.462**.
3. **Cuando la carga se nacionaliza entra el RECUPERO** (`Recupero NTL (proveedor)`): la plata vuelve
   a NTL porque recién ahí se puede girar legalmente desde Argentina (§1). Total recuperado:
   **u$s 241.021**. Sobre cada recupero NTL cobra su **5 % ("5% NTL s/FC")**.
4. **Comisiones y gastos acumulados: u$s 20.389.**

O sea que el "recupero de dólares al exterior" del que habla Thomas **es el crédito que repone el
saldo de NTL**, y el ciclo se cierra ahí.

**La columna `Empresa`** reparte cada movimiento en **`D`** (el efectivo depositado, todavía sin
asignar), **`TN`** (Tierra Nativa) y **`CH`** (Chef) — los dos importadores que ya usa el módulo.

### La imputación cruzada YA estaba en el Excel

Las hojas por proveedor (`Ownland`, `Frontier`) tienen exactamente las tres patas que en §3 quedaron
como "lo que todavía no está":

| Columna | Qué es |
|---|---|
| **`Salido por`** | el **canal**: `NTL` o `Bco` (giro directo). Confirma el "hay casos y casos" |
| **`A través de`** | la **carga/FC con la que se pagó** — la pata legal |
| **`Fue a`** | la **carga que queda cubierta** — la pata comercial |

Ejemplo textual de la hoja Ownland: `15/07/2025 · 4.719,84 · Bco · a través de CQ-9154 · fue a
CQ-9342A`. Eso es, tal cual, pagar un pedido con la factura de otra carga.

### Qué se importó

| Tabla | Qué trae |
|---|---|
| **`GV_Imp_NTL_Mov`** | 252 movimientos: hoja `NTL` (179) + hoja `CH` (73), con fecha, descripción, débito/crédito/saldo, origen-destino, referencia (el proveedor), empresa y tipo (`T` transferencia / `G` gasto / `DEV`) |
| **`GV_Imp_Prov_Mov`** | 28 movimientos de las hojas `Ownland` (21) y `Frontier` (7), con `salido_por`, `a_traves_de` y `fue_a` |

**Importación FIEL: no se interpretó ni se corrigió nada.** Cada fila guarda su número de fila del
Excel (`fila`) para poder volver al original.

**Chequeo contra los totales que el propio Excel trae arriba**: créditos de la hoja NTL
**406.081,80** contra los **406.082** del resumen, y créditos de la hoja CH **196.214,36** contra
**196.214**. Cierran. En Ownland, girado 157.594,40 − recuperos 157.560,40 = **34**, que es la
"Deuda real" que muestra esa hoja.

### Lo que no cierra y espera a Thomas

1. **Ownland: dos FOB distintos.** Esta planilla dice **34.956** (`China 52` / `CQ-9694`, y la fila
   199 del ledger: *"FOB 34956 − 14000 Adelanto = 20.956"*), y la planilla de deudas del mismo día
   decía **46.626**. El sistema tiene cargado 46.626.
2. **Becky 1.ª carga.** La hoja `Becky` dice: 1.ª carga 23.622,50 con **anticipo 6.920,86** y
   **16.701,60 pendientes**. En el sistema `PI B260601` figura con **0 pagado**, porque la planilla
   de deudas no lo traía. Falta cargar ese anticipo.
3. **Qué es `D`.** Por los movimientos parece el efectivo depositado todavía sin repartir entre TN y
   CH, pero es una lectura mía, no un dato.
4. **Cuatro fechas con el año cambiado** en el Excel (filas 35, 37, 43 de la hoja NTL y 28, 30, 32 de
   la CH: dicen 2025/2026 donde por la secuencia del saldo van 2024/2025). **Se importaron tal cual.**

## 5. La cuenta de NTL, andando en la app (v15.90)

`sql/` — vistas `gv_imp_ntl_cuenta` (el extracto con el **saldo corrido recalculado** y cada
movimiento clasificado) y `gv_imp_ntl_resumen` (por empresa), más las RPC `gv_imp_ntl_resumen()`,
`gv_imp_ntl_mov(limit, empresa, proveedor)` y `gv_imp_ntl_pendientes()`.

**Prueba de integridad**: el saldo corrido que calcula la vista se comparó **fila por fila** con el
que trae el Excel — **177 filas, 0 diferencias**, saldo final **u$s 230,43** en los dos.

La **clase** de cada movimiento sale de lo que dice el propio Excel, no se inventa: `ingreso`
(Efectivo/Transferencia Recibido), `recupero`, `giro` (Advance/Balance a la fábrica), `comision`,
`gasto_bancario` (los que dicen "Gtos Bancarios") y `devolucion`.

### Saldo por empresa

| Empresa | Ingresos | Recuperos | Girado a fábricas | Comisiones | Gastos banc. | **Saldo** |
|---|---|---|---|---|---|---|
| **D** (depósitos sin asignar) | 133.300 | — | — | 3.699 | — | **129.601** |
| **TN** Tierra Nativa | 13.445 | 83.912 | 180.498 | 4.712 | 317 | **−76.857** |
| **CH** Chef | 7.000 | 157.109 | 208.338 | 7.708 | 576 | **−52.513** |
| | | | | | | **230,43** |

**El bloque resumen del Excel tiene dos números viejos**: da `CH = −48.186` (contra −52.513) y un
"Saldo Final" de **12.335,33**, que es el saldo de la **fila 140, del 05/01/2026** — quedó pegado.
La partición de acá suma exactamente el saldo real del extracto (230,43); la del Excel, no.

### Solapa 💱 NTL

Cuarta solapa del módulo de importación. Muestra el **saldo de hoy** y el de cada empresa, los
acumulados del circuito (depositado / girado / recuperado / comisiones), los **recuperos pendientes**
(u$s 42.908: Hugo Wong CH37 21.952 y Ownland 20.956, los directos) y el **extracto navegable**, con
fichas por empresa y por proveedor y un "ver más" que pagina. Test `tests/imp-ntl.cjs`.

## 6. Cargas, conciliación y alias (v15.93)

Tres cosas más que se pudieron derivar **sin** los datos que faltan de Thomas. La solapa 💱 NTL pasa
a tener **tres vistas**: 📄 Extracto · 📦 Cargas · 🔗 Conciliación.

### Alias de proveedor — `GV_Imp_Prov_Alias`

El import es fiel, así que el nombre original **no se toca**: se traduce en una tabla aparte, con la
función `gv_imp_prov_canon()` que usan todas las vistas. Cargados los tres que son certeza
tipográfica — **`Fuyian` → Fujian**, **`Xihin` → Zhixin**, **`Becky Chen` → Becky` — y marcados como
**empresa mal tipeada** `Chef` y `Tierra`, que no son proveedores.

**Quedan 5 sin decidir** (`Cestos`, `Jason`, `Stephen Jiang`, `Qi Qiao`, `Wenxinda`): no están en
`Importados`. La pantalla los avisa arriba **con un ✏️ al lado de cada uno** (v15.99) para decir a
qué proveedor corresponden — o escribir `EMPRESA` si no son un proveedor.

### `gv_imp_cargas` — las cargas del Excel con su saldo

Una fila por **carga** (`CQ-9154`, `China 2`, …) con lo **girado**, el **FOB** y el **saldo**, más el
pedido en curso que más se le parece por proveedor y monto. **La sugerencia no se guarda**: el mapa
carga ↔ PI lo tiene que confirmar Thomas.

Lo que salió, y que apunta al FOB de Ownland:

| Proveedor | Carga | Girado | FOB | Saldo | Pedido que le calza |
|---|---|---|---|---|---|
| Frontier | `China 2` | 14.400 | 14.400 | **0** | `Frontier 505C` — **FOB igual** |
| Ownland | `CQ-9694` (la última, 13/03→03/06/2026) | 34.990 | **34.956** | −34 | `PI OL-10139` — FOB difiere **11.670** |

**Los 11.670 no son casualidad**: son exactamente el "Falta" de Ownland en la planilla de deudas
(46.626 − 14.000 − 20.956). Y 46.626 − 34.956 = **11.670** también. O bien el FOB de la carga es
34.956 y los 46.626 del sistema traen 11.670 de más, o bien `CQ-9694` y `PI OL-10139` son **dos
cargas distintas** — sus fechas (marzo-junio 2026 contra un PI del 02/09 que embarca el 08/11) hacen
pensar lo segundo. **No se tocó: lo define Thomas.**

### `gv_imp_conciliacion` — los giros cargados contra el Excel

Busca cada giro de `GV_Imp_Pagos` en las **dos** fuentes (el extracto de NTL y las hojas por
proveedor), por proveedor canónico + monto (±1) + la fecha más cercana. **4 de 6 aparecen**:

| Pedido | u$s | Resultado |
|---|---|---|
| `Frontier 505C` | 4.320 | ✅ **exacto** — extracto NTL fila 175, 25/08 |
| `PI BX260722D` Zhixin | 3.100 | ✅ **exacto** — fila 184, 04/09 (lo encontró vía el alias `Xihin`) |
| `PI HT26-06-600-R1` Fujian | 10.000 | ✅ monto ok, el extracto dice **04/08** y no 05/08 |
| `PI OL-10139` Ownland | 14.000 | ⚠ está en la **hoja Ownland**, pero del **13/03/2026**, *a través de `CQ-9553`, fue a `CQ-9694`* |
| `PI B260601-2` Becky | 7.359 | ❌ **sin match** |
| `PI NY26-031438` Hugo Wong | 14.041 | ❌ **sin match** |

Los dos sin match son los mismos que ya venían marcados por no dar el 30 % exacto. Y el de Ownland
es el que destapó el mapa: **el adelanto de 14.000 fue a `CQ-9694`, pagado a través de `CQ-9553`** —
que es, textual, la mecánica de pagar un pedido con la factura de otra carga.

## 7. El mapa carga ↔ pedido se carga desde la pantalla (v15.98)

En vez de esperar que Thomas conteste por chat qué carga es qué pedido, la pantalla se lo pregunta
y lo guarda. **El sistema sugiere; él confirma.**

| Objeto | Qué es |
|---|---|
| **`GV_Imp_Carga_Pedido`** | el mapa: (proveedor, carga) → `pedido_ref`. `pedido_ref` en null significa **"esta carga no es ninguno de los pedidos en curso"**, que también es una respuesta |
| **`GV_Imp_Pagos.carga_origen` / `.carga_destino`** | por giro: con qué carga se cursó (*a través de*) y cuál queda cubierta (*fue a*) |
| `gv_imp_carga_pedido_set()` · `gv_imp_pago_cargas_set()` | lo que escriben los botones |

**En 📦 Cargas**: cada fila tiene **🔗 Asignar**. Abre la lista de pedidos en curso de ese proveedor
numerada (se elige por número, `0` = ninguno, o se escribe el PI a mano). Lo confirmado se muestra
en verde con ✓; lo que todavía no, como *sugerido*.

**En 💵 Giros**: columna nueva **"Cargas (a través de → fue a)"**. Si el giro no las tiene cargadas
pero **el Excel de Thomas lo dice**, aparece la sugerencia con un botón **✓ usar** que la acepta de
una. Ejemplo real: el giro de 14.000 de Ownland trae *"según el Excel: CQ-9553 → CQ-9694"* (hoja
Ownland, fila 22).

Con eso, las preguntas que quedaban abiertas dejan de necesitar una respuesta por chat: se contestan
tocando un botón, y quedan guardadas.

### Lo que sigue

Que Thomas pase por 📦 Cargas y asigne las 9 cargas, y por 💵 Giros y acepte o corrija las cargas de
cada giro. Ahí el circuito queda atado de punta a punta. Lo único que **no** se puede resolver desde
la pantalla es lo que no está en ningún lado: el anticipo de la 1.ª Becky, qué es la empresa `D`, y
la hoja de Hugo Wong que no vino en el Excel.
