# Pendientes del pipeline de Gestión Virgilio — nota del dueño, 2026-09-04

> **Para qué existe.** El dueño dejó una hoja escrita a mano con lo que falta para
> cerrar el pipeline de Gestión Virgilio. Esto la transcribe y la cruza con el estado
> **real** del repo y de Supabase, para que una sesión nueva sepa en un archivo dónde
> está parada y qué sigue, sin depender de la memoria de ningún chat.
>
> Se avanzó **hasta la programación de pedidos** (solapa "A Programar", v12.83).
> Todo lo que sigue está abierto.
>
> Lo de arriba está construido cumpliendo las dos reglas de siempre: **A) que funcione**
> y **B) que no toque la operación de Producción Virgilio**, que es la app que los
> operarios están usando en este momento sobre la misma base.
>
> Detalle técnico de cada cosa: `docs/SUPABASE-GESTION-VIRGILIO.md` (§3.b a §3.j y §5).
> No borres entradas de acá: se tildan (`[x]`) o se tachan (`~~…~~`).

---

## Transcripción de la nota (textual)

```
                    ┌───────────────────────────────────┐
                    │ Entre góndola A4x y A5x           │  ( ) (X) ( )
                    │ hay un art mal puesto             │
                    └───────────────────────────────────┘

Pendiente

Pág LK / CH                              Gestión Virgilio
* Módulo Editar pedidos                  * Armado de tandas
  (clientes pueden agregar                 (auto solo zona 1 y 2, el
  cosas al pedido) recomiendo               resto tiene que ser manual)
  que sea solo agregar (hace             * Verificar flujo en picking,
  difícil que saquen o cancelen)           armado, esperando facturación
* Fecha de entrega Supers                * Ajustar módulo de facturación
  (tiene que viajar a Supa                 (definir envío a ISIS)
  junto con el pedido; bot               * Verificar flujo completo
  la parsea tal vez)                       y ver cruce de factura
```

---

## ⚠ El interruptor que bloquea la mitad de esta lista

Los puntos **8808, 9871, 8033** y buena parte de **1439** no se pueden probar con datos
reales mientras la numeración de NP esté apagada. Es **a propósito**, no es un bug:

| | |
|---|---|
| `PPP_Web_Config.numeracion_activa` | `0` → `gv_ppp_web_np_asignar` corta con su mensaje |
| `PPP_Web_Config.tanda_prefijo` | `GV-` → las tandas de prueba no se confunden con las de Producción |
| cron `gv-ppp-web-tandas-diarias` (jobid 71) | **apagado** |
| `PPP_Web_NP` | vacía |

Hoy la NP la manda **ISIS** a la hoja y la usa Producción. Gestión numera el día que tome
control, y ese día son dos líneas (`docs/SUPABASE-GESTION-VIRGILIO.md` §3.e).
**No prenderlo por iniciativa propia**: lo decide el dueño.

Para probar mientras tanto se prende y se apaga **dentro de una sola transacción**
(así se probó el §3.j), o se usan filas propias en `PPP_Web_Programacion`, que es nuestra.

---

## Pág LK / CH — el front vive en OTROS repos

Estos dos puntos se implementan en `PaginaLK` y en el repo de Chef, **no acá**. Lo que
Gestión tiene que dar es la cañería, y en el punto 1 ya está dada.

### [ ] 4990 — Módulo "Editar pedidos": el cliente agrega al pedido ya mandado

Textual: *"Módulo Editar pedidos (clientes pueden agregar cosas al pedido) recomiendo que
sea solo agregar (hace difícil que saquen o cancelen)"*.

**Lo que ya está (§3.h, v12.79).** La recomendación del dueño ya está impuesta por el
backend, no por la buena voluntad del front:

| objeto | qué da |
|---|---|
| vista `gv_ppp_web_estado` | `puede_agregar` (true hasta que se factura) · `puede_quitar` (**siempre false**) · `agregado_seria_urgente` |
| `ppp_web_resync` | el agregado entra a la **misma tanda** que sus hermanas, con `es_agregado`, `agregado_a_np` y `prioridad = 100`. Y ya **no borra** si la tanda está en marcha |
| front Virgilio v12.79 | cartel rojo *"ESTO ES UN AGREGADO AL PEDIDO XXX Y SALEN JUNTOS"* en el monitor y en cada paso del picking |

**Lo que falta:**

1. **El front de las páginas** (`PaginaLK` + Chef): botón de agregar, mostrar el estado del
   pedido, y bloquear cuando `puede_agregar` es false. Es la idea **8743**, que además
   pide mostrar *por qué* está bloqueado.
2. ~~**El picking todavía no ordena por `prioridad`.**~~ ✅ **HECHO — v12.85.** La tanda
   hereda la prioridad más alta de sus NP y las urgentes se dibujan en un bloque rojo
   **arriba de todo**, salteándose el orden por fecha (el día de esa tanda puede estar
   tres grupos más abajo). Aditivo: las de ISIS quedan igual que siempre. Regresión:
   `tests/pk-prioridad-agregado.cjs`.
3. Nada de esto corrió con datos reales (interruptor).

**⚠ Lo que falta acá es sólo el front de las páginas, y arrastra una decisión de fondo:**
el módulo *"Editar pedidos"* **ya existe** en `pagina-LK-copia` (`editOrder()` +
RPC `edit_order_fast`), pero hace lo contrario de lo que pide la nota: **borra y reinserta
los ítems**, así que el cliente puede sacar y bajar cantidades. Y su ventana es *hasta las
12:30 / hasta `enviado_a_compras_at`*, no *hasta que se factura*. Ver el bloque de
decisiones abiertas al final de este archivo.

### [ ] 9357 — Fecha de entrega de Supers: tiene que viajar con el pedido

Textual: *"Fecha de entrega Supers (tiene que viajar a Supa junto con el pedido; bot la
parsea tal vez)"*.

**Por qué importa.** El súper entrega con fecha comprometida, y hoy esa fecha **no existe
en ningún campo** del pedido web: el `sheets_payload` que mandan las páginas no la trae
(ver el JSON real en §3.b). La fecha de entrega la elige el supervisor recién al programar
la tanda, en el calendario de la solapa "A Programar". Para un súper eso es al revés: la
fecha viene dada y la tanda se arma alrededor.

**A favor:** los súpers **ya van a mano** hoy — `gv_ppp_web_zona_automatica` sólo deja
pasar zona 1 y 2, y `Super` queda afuera del armado automático (§3.i). O sea el lugar
donde hay que mostrar la fecha ya es la pantalla manual.

**Lo que falta / hay que definir:**

1. **De dónde sale la fecha.** Carga del vendedor en la página, o parseo de la orden de
   compra del súper ("bot la parsea tal vez"). Si es parseo, define el formato de entrada.
2. **Por dónde viaja.** Campo nuevo en el pedido de las páginas → tiene que llegar a
   Supabase junto con el pedido, no por un canal aparte.
3. **Cómo la usa Gestión.** Mostrarla en la tarjeta del pedido de la columna izquierda de
   "A Programar", ordenar por ella, y avisar si la tanda se programa para una fecha que no
   es la comprometida. Es un aviso más de los de `gv_ppp_web_tanda_avisos`, no un bloqueo.
4. **Cross-repo:** los puntos 1 y 2 son de `PaginaLK` / Chef. El 3 es de este repo.

---

## Gestión Virgilio

### [x] 8808 — Armado de tandas: auto sólo zona 1 y 2, el resto manual

Textual: *"Armado de tandas (auto solo zona 1 y 2, el resto tiene que ser manual)"*.

**Está hecho, las dos mitades**, y es hasta donde se avanzó hoy:

| mitad | dónde | estado |
|---|---|---|
| Automático acotado a zona 1 y 2 | §3.i · `PPP_Web_Config.zonas_automaticas = '1,2'` · `gv_ppp_web_zona_automatica` | ✅ probado con las zonas reales (`Zona 10` no se confunde con la 1) |
| Manual para el resto | §3.j · solapa **"A Programar"**, v12.80→v12.83 | ✅ probado de punta a punta |

Piezas del manual: `PPP_Web_Tandas` / `PPP_Web_Tanda_Items` (borradores que el depósito
**no ve**), `gv_ppp_web_tandas_abiertas`, los 6 avisos de `gv_ppp_web_tanda_avisos`,
`gv_ppp_web_tanda_nueva/_agregar/_sacar/_descartar/_programar`, `gv_ppp_web_calendario`.
La unidad de arrastre es el **pedido**, no la NP. Regresión: `tests/apr-programar.cjs`.

Sumar una zona al automático es un `update`, sin tocar código:

```sql
update public."PPP_Web_Config" set valor_texto = '1,2,3' where clave = 'zonas_automaticas';
```

**Lo que queda de esto:**

1. Programar **corta** mientras la numeración esté apagada (arriba). Es lo único que separa
   al módulo de estar operativo.
2. El cron de las 00:01 está apagado; el armado automático no corre solo.
3. Cosmético: con la zona 3 fuera del automático, el resumen sigue diciendo "Zonas 2+3"
   aunque el grupo tenga sólo zona 2. La columna `zona` de cada NP guarda la zona real.

### [ ] 9871 — Verificar el flujo: picking → armado → esperando facturación

Textual: *"Verificar flujo en picking, armado, esperando facturación"*.

**Lo que hay.** La vista `gv_ppp_web_estado` deriva el estado de los eventos que los
operarios ya emiten, sin ninguna columna que mantener ni ningún trigger sobre tabla
compartida (que además está prohibido):

```
sin_programar → programado → en_picking → pickeado → en_armado → armado → facturado
```

Se probó contra **tandas reales de Producción** (`C62A`, `C34B`, `C33C`), pero con filas
propias en `PPP_Web_Programacion` apuntando a esas tandas. El branch `facturado` **no se
pudo probar con datos**: haría falta una fila en `Facturacion_NP`, que es compartida.

**Lo que falta verificar de verdad — una NP web de punta a punta:**

1. Que la NP programada **aparezca en el celular del operario** (`mergeMonitorPppWeb`, que
   filtra `tanda=not.is.null`).
2. Que el **picking la ordene por `prioridad`** (hoy no lo hace — ver 4990 punto 2).
3. Que el armado la cierre y quede en *esperando facturación*.
4. Que el estado que muestra `gv_ppp_web_estado` sea el mismo que ve el depósito en cada
   paso.

**⚠ El agujero más grande de este tramo: el stock.** `trg_normalizar_empresa_stock`
(trigger de `Movimientos_Stock`, tabla **compartida**) completa la empresa de un
movimiento con `empresa_de_np`, que **no entiende las NP web**. Hay que definir cómo entra
el stock de un pedido web sin poner un trigger en una tabla compartida (§5.1). Sin esto,
picking y armado de una NP web mueven stock mal o no lo mueven.

**Bloqueantes:** el interruptor de numeración, y `PPP_Web_Base.np_label` es `NOT NULL`, así
que sin numerar el operario **no puede ni abrir la tanda**.

### [ ] 1439 — Ajustar el módulo de facturación y definir el envío a ISIS

Textual: *"Ajustar módulo de facturación (definir envío a ISIS)"*.

**El contrato ya está escrito y mandado**, y es lo que ISIS pidió (Alternativa B: ISIS
consulta una API nuestra). `docs/ISIS-API-ESPECIFICACION.md` pasó a **v2.0**; el PDF para
el proveedor es `docs/API-Virgilio-ISIS-v2.0.pdf`. Los tres puntos:

- **El pedido no lleva NP.** La clave es `referencia` (`LK 1344`), va en la URL y en el
  listado, no dentro del pedido. La NP la pone ISIS al facturar.
- **El formato es el del mail de las 12:30**, el que ISIS ya sabe recibir. Cambia cuándo se
  manda (al cerrarse el armado, no a las 12:30), por dónde llega y que las cantidades ya
  vienen firmes: viajan las cajas **armadas**, no las pedidas.
- **No vuelve nada de ISIS.** Sin acuse, sin NP, sin CAE.

**⚠ El código desplegado sigue en la v1.0.** Lista concreta de lo que falta:

1. Reescribir la salida como un objeto **nuevo `gv_*`**. `isis_pedido_json` **no sirve y no
   hay que reusarla**: arma un *informe* del pedido terminado, con otra forma, y hace
   `np::bigint` sacando los no-dígitos (una NP `LK 1343` viajaría como `1343`).
2. Traer los campos comerciales del `sheets_payload` de LK.
3. Cambiar la clave de `isis_export_pedidos` de NP a **referencia**.
4. **Sacar** las rutas de acuse y la RPC `isis_api_acuse` (el punto P3 del informe quedó
   sin objeto).
5. Reemplazar el disparador `Facturacion_NP` por **el cierre del armado**.
6. **UI de las tres sublistas** del módulo Facturación — el backend ya está
   (`vista_facturacion_estado`), falta la pantalla (§5.3).
7. **Conectar las NP web a `Facturacion_NP`** con la etiqueta (`LK 00001`). Nada lo
   bloquea —las columnas `np` son `text` y `validar_np_armada` sólo exige ítems armados—
   pero todavía no pasó ninguna (§5.4).

**Decisiones abiertas antes de construir (§3.b):**

- Una NP nuestra = un pedido para ISIS. Un pedido partido en 3 NP entra como 3 pedidos.
  **Confirmar.**
- **Qué va en `order_number`** cuando el pedido está partido en varias NP, para que ISIS no
  las confunda.
- Cuáles de los campos de contexto comercial (`deuda`, `credit_limit`, `lc`,
  `order_total`, `extra_discount`) usa ISIS de verdad y cuáles pueden ir vacíos.

### [ ] 8033 — Verificar el flujo completo y ver el cruce de factura

Textual: *"Verificar flujo completo y ver cruce de factura"*.

Es el cierre: pedido web → programación → picking → armado → envío a ISIS → factura →
**cruce**. Sólo se puede hacer de verdad con la numeración prendida.

**Del cruce, lo que hay medido:** `vista_cruce_facturacion` hoy explica **735 de 735** NP
facturadas con **0 acuses** — el vínculo factura ↔ pedido lo resuelve nuestro parseo, sin
que ISIS devuelva nada. Por eso el contrato pudo quedar en una sola vía.

**Lo que falta verificar:** que ese mismo cruce funcione con las **NP web nuevas**, que se
aparean por la **etiqueta** (`LK 00001`, la que arma `gv_ppp_web_np_label`) y no por un
número suelto. El apareo por etiqueta ya se usó y se midió en el §3.g; falta verlo con una
factura real de una NP web.

---

## Suelto en la hoja, sin contexto

### [ ] 1946 — ⚠ A CONFIRMAR: aviso "entre góndola A4x y A5x hay un art mal puesto"

Arriba de todo, el dueño dibujó lo que parece un **aviso descartable** (recuadro con
texto y una X): *"Entre góndola A4x y A5x hay un art mal puesto"*.

No está bajo ninguna de las dos columnas y no tiene más explicación. **Lectura probable —
no confirmada:** que durante el picking (o un recorrido de control) se pueda reportar que
hay un artículo mal ubicado entre dos góndolas, y que eso salga como aviso que alguien
puede descartar cuando lo acomoda.

Se cruza con la idea **3402** (*picking: ver el stock de góndola en pantalla y tildar o
cruzar cada artículo antes de sacar la mercadería*).

**Preguntarle al dueño qué es antes de construir nada.**

---

## 4990 — lo que se encontró al abrir la página LK (2026-09-04)

Repo `loekemeyer/pagina-LK-copia` (clonado en `/home/user/pagina-lk-copia`, HEAD `4421dc8`).
⚠ `loekemeyer/PaginaLK` —el que nombra el `CLAUDE.md`— está **archivado**; el vivo es éste.

**El módulo "Editar pedidos" YA EXISTE.** No hay que construirlo, hay que corregirlo:

| pieza | dónde | qué hace hoy |
|---|---|---|
| `editOrder(orderId)` | `script.js:2181` | carga los ítems del pedido **al carrito** |
| `isOrderEditable(order)` | `script.js:2166` | UI: editable si `enviado_a_compras_at` es null **y** antes del corte de las 12:30 |
| RPC `edit_order_fast` | `sql/order_items_source.sql:105` | el candado real: rechaza si `enviado_a_compras_at is not null` |
| `mode: "edit"` | `script.js:7622` | viaja en el `sheets_payload` |

**Los dos choques con lo que pide la nota:**

1. **Hoy el cliente puede SACAR.** `edit_order_fast` hace `delete from order_items where
   order_id = …` y reinserta lo que llegue: si el carrito viene con menos, el pedido se
   achica; si viene vacío, queda vacío. La nota dice *"sólo agregar (hace difícil que
   saquen o cancelen)"*, y nuestra vista ya lo declara (`puede_quitar` **siempre false**).
2. **La ventana no es la misma.** La página corta en *12:30 / enviado a compras*;
   `gv_ppp_web_estado` dice *hasta que se factura*. Aflojarla hoy tocaría la operación
   actual, porque mientras Gestión no tome control el pedido sigue saliendo a ISIS por el
   mail de las 12:30 y `enviado_a_compras_at` es el candado que lo sostiene.

**Y un tercer problema, de plomería:** `gv_ppp_web_estado` vive en el proyecto **Virgilio**
(`hrxfctzncixxqmpfhskv`) y la página habla con el de **LK** (`kwkclwhmoygunqmlegrg`), que
son dos proyectos separados a propósito. Para que la página muestre el estado hace falta un
camino Virgilio → LK. Hoy existe el inverso: **LK empuja a Virgilio** por el FDW
`virgilio_db` / rol `lk_ppp_reader` sobre la tabla espejo `lk_pedidos_match`
(`sql/pedidos_match_virgilio.sql`). El mismo patrón, invertido, es la opción obvia.

### Decisiones abiertas (bloquean el resto de 4990)

1. **El candado de "sólo agregar": ¿backend o front?** El protocolo dice backend, o sea
   `edit_order_fast` — pero es una función en producción que usan clientes reales ahora
   mismo.
2. **¿Se afloja la ventana ya, o recién el día que Gestión tome control?**
3. **¿Cómo llega el estado a la página?** Espejo Virgilio → LK (mismo patrón que
   `lk_pedidos_match`, invertido) o algo más.

---

## Orden sugerido para arrancar

1. **Preguntar por 1946** (es una pregunta, cuesta un mensaje) y **por las definiciones de
   9357** (de dónde sale la fecha del súper).
2. **Picking por `prioridad`** (4990 punto 2). Es de este repo, es chico, y desbloquea
   parte de 9871.
3. **Stock de los pedidos web** (§5.1). Es el agujero real de 9871 y hay que resolverlo sin
   trigger sobre tabla compartida.
4. **1439**: reescribir la salida a ISIS como objeto `gv_*` según el contrato v2.0, y la UI
   de las tres sublistas de Facturación.
5. **8033** al final, con la numeración prendida el día que el dueño lo diga.
