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

### Forma que va a tener la cuenta corriente (borrador, a confirmar con el Excel)

- **`GV_Imp_Facturas`** — la factura comercial: emisor (¿el proveedor o NTL?), número, fecha,
  monto, a qué embarque/despacho corresponde. Es la **pata legal**.
- **`GV_Imp_Pagos`** — el giro: fecha, USD, beneficiario (NTL), contra qué factura se cursó,
  cotización si hace falta. Es la **pata financiera**.
- **`GV_Imp_Pagos_Imputacion`** — a qué **PI** se aplica cada giro (uno a varios, parcial). Es la
  **pata comercial**, y es la que da el saldo por pedido y por proveedor.

Saldo del PI = total del PI − imputado. Saldo del proveedor = suma de sus PI.
El PI ya existe como `pedido_ref` en `GV_Importados_Baches` (v15.72), así que la cuenta corriente
se cuelga de ahí sin duplicar nada.

**Nada de esto está construido**: falta el Excel con el que Thomas lo lleva hoy, para copiar el
modelo real (cómo anota el anticipo del 30%, si un pago se parte entre varios PI, si hay algo en
pesos, cómo trata las diferencias de cambio y los gastos de NTL) en vez de inventarlo.

## Fuentes

- BCRA, Com. "A" 8226 (14/04/2025) y Com. "A" 8417 (09/04/2026) — texto en
  `boletinoficial.gob.ar` y `bcra.gob.ar/archivos/Pdfs/comytexord/A8417.pdf`.
- BCRA, TO *Exterior y Cambios*, pto. 10 (pagos de importaciones de bienes) y 10.4 (beneficiario).
- BCRA, SEPAIMPO — Com. "A" 5060 y régimen informativo de seguimiento de pagos de importaciones.
- Resúmenes de prensa especializada (aduananews, El Cronista, despachantesargentinos) sobre el
  pasaje de las SIRA al pago "a la vista" y los errores que bloquean pagos.
