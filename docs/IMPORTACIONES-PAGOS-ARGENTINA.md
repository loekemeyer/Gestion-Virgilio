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

- ~~**Frontier**: el Excel dice FOB 14.400 y el motor calcula 14.000~~ → **cerrado (v15.76)**: manda el
  PI, `fob_uni` de 505C pasó a **0,072**. Ya no queda ninguna fila con `fob_difiere`.
- ~~**Frontier, la llegada no cierra**~~ → **cerrado (v15.76)**: *"embarca el 26 de octubre y llega 45
  días después"* → **10/12/2026**. La que estaba mal era la llegada (04/11), que daba 9 días de viaje.
- **Becky `PI B260601-2`**: el 30 % figura pagado el **02-jun** y el PI está fechado el 14/07 en
  §3.bm.13. Y son **112 días** hasta el embarque contra los *"90 días después del depósito"* del PI.
- **Ownland**: el Excel confirma **u$s 46.626**, así que el *"u$s 13.988"* que §3.bm.5 leyó del
  PI OL-10139 es lo que está mal, no el cálculo del motor.

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
