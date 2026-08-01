# Ideas del usuario — Producción Virgilio

Proyección en el repo de las ideas que **escribe el usuario** en cualquier chat.
Cada idea queda acá (durable, versionada) y además en la tabla `agente_propuestas`
(Supabase) para entrar al mismo circuito que las de los agentes: se desarrolla sola
en su rama `idea/<código>`, se recuerda en el Telegram de las 8 **todos los días
hasta que el usuario la active**, y se mergea a `main` cuando el usuario dice el número.

- `[ ]` = pendiente / esperando activación · `[x]` = activada (mergeada a main) ·
  `~~tachada~~` = descartada.
- El código de 4 dígitos es el mismo que en la tabla y en el Telegram.

> Este archivo es un espejo legible. La fuente operativa es la tabla
> `agente_propuestas`. Al registrar o activar una idea del usuario se actualizan
> los dos. No borres entradas: se tildan o se tachan.

## Ideas

- [ ] **3908** (2026-08-01) — **Sugeridor de picking en base al conteo de góndola**: al armar un picking, decirle al operario **antes de levantar** qué faltantes va a tener (recorrido + por artículo: cajas pedidas vs en góndola + veredicto hay-todo/faltan-N/sin-stock). Botón **"esto está mal"** para marcar discrepancia y desconfiar del sistema. Extras: picking como recuento continuo · qué pedidos salen 100% completos · reposición góndola vs PPP · negativos imposibles en vivo · nivel de confianza/frescura del dato. Detrás de un switch para pilotar — _pendiente (idea grande)_
- [x] **8243** (2026-07-31) — **Lectora de código de barras inalámbrica** para el picking (reemplazar la botonera del celu: cada disparo carga en vivo). Enfoque: scanner Bluetooth/ring → la PWA captura el scan → mapea barcode→código → emite PKC de siempre. WiFi ya mitigado por la cola offline — _hecha (v6.83, en main): decode EAN-13 (TODO 779558700+NNN / FALTA 779558701+NNN, verificado contra la etiqueta real), todo detrás del switch `vir_picking_scanner` (off = igual que hoy), toggle desde el módulo del operador y el Print Station. ⏳ Falta el piloto con la lectora real (comprar) y pegar las etiquetas de slot. **Refinamiento pendiente (01/08):** durante el picking el operario **no toca la pantalla**, solo escanea; TODO=agarró todo, FALTA=marca corto **sin** preguntar cuánto; recién al dar **TP** pregunta en lote las cantidades de los FALTA. Lógica pura de app (sin hardware)._
- [ ] **5290** (2026-07-31, refinado 2026-08-01) — **Impresora automática de etiquetas por lío**. El **programa emite solo** cada etiqueta al terminar el armado (NO generar a mano). Ej: 10 líos → **10 etiquetas distintas**, cada una con **composición del lío (cod+cajas), nombre del cliente y lugar de entrega**. Datos ya existen (`n.liosArr` + NP/PPP). Falta el **puente de impresión**: cola de etiquetas en Supabase + agente en la PC que imprime el ZPL en la **Zebra S4M** (el celu no imprime directo). Detrás de un switch. **Piloto (01/08):** S4M queda en la PC lejana; cada etiqueta lleva tanda+operador+cliente + una **cabecera "nota de pedido"** por trabajo para que impresiones simultáneas no se mezclen. **Futuro:** micro-PC + impresora chica por puesto de armado (entra bajo la mesa) — _pendiente (idea grande)_
- [x] **2769** (2026-07-31) — Insumos **505C/CB01/523C/H201Lever**: borrar stock y colocar en insumos con el conteo físico (sectores X20/N7/W1/O1) — _hecha: saldo en **unidades** bajo códigos numéricos 2955/4626/1685/2815 (142000/2950/6000/26400), viejos en 0, Cabezal ≠ Espiral 2805. En Supabase._
- [x] **2091** (2026-07-31) — Mover el botón **Cerrar** del módulo Consulta de NP (composición a líos) **arriba a la derecha** — _hecha (v6.68, en main)_
- [x] **1963** (2026-07-31) — **Prolijar** la estética del pop-up de movimientos por artículo (alinear rótulos, chips en pill, alinear el `+`) — _hecha (v6.68, en main)_
- [x] **1636** (2026-07-31) — **Fix estancado**: el `cp` (completar pedido) con legajo 0 se excluía y rompía el saldo → falso positivo del 534/323E en "a guardar". Ahora el saldo es event-sourced sobre todos los movimientos (sin filtrar legajo), como la app — _hecha (v6.68 + backend Supabase, en main)_
- [x] **1108** (2026-07-31) — Que las columnas de depósito (A facturar / A guardar / etc.) se puedan **abrir aunque digan 0**, si el artículo tuvo movimientos ahí alguna vez — _hecha (v6.67, en main)_
- [x] **3989** (2026-07-31) — Un **`+`** en cada recepción del pop-up que muestre la **entrega completa**: día que llegó, de qué prov/tall, qué códigos entregó y cuántas cajas de cada uno — _hecha (v6.67, en main)_
- [x] **2415** (2026-07-31) — En el pop-up de movimientos por artículo (📦 A guardar) mostrar las **siglas y el legajo de quien recibió** — _hecha (v6.66, en main)_
- [x] **1730** (2026-07-31) — Redefinir **ESTANCADO**: es cuando de lo que llegó se guardó una **parte** (entre góndola y excedente) pero **no la totalidad** (llegan 14, guardan 10, quedan 4 → eso es estancado). Una recepción nueva intacta **no** es estancado (caso cod 824) — _hecha (v6.66 + backend Supabase, en main)_

<!-- Nuevas entradas se agregan ARRIBA de esta línea, formato:
- [ ] **CÓDIGO** (AAAA-MM-DD) — texto de la idea — _estado_
-->
