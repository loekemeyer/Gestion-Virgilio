> ⚠ **DESCARTADO (v7.20).** El usuario decidió no usar la lectora de código de barras:
> el piloto se sacó de la app (switch del operario, switch de admin y listener). Este
> documento queda como archivo de la idea. `tools/etiquetas-gondola.html` sigue en el
> repo: sirve para imprimir etiquetas de góndola aunque no haya lectora.

# Picking con lectora + etiquetas por lío — diseño (ideas 8243 y 5290)

> Estado: **diseño / en desarrollo**. Todo el cambio en la app va **detrás de un
> switch** (feature flag). Switch **apagado = la app funciona idéntico a hoy**;
> prendido = modo scanner. Pedido del dueño (31/07).

## Regla de oro: el switch

- Config nueva `Stock_Config` / `localStorage` **`picking_scanner`** (default **off**).
- Toggle en el panel de **supervisor** (y opcional por dispositivo).
- **Off** → el picking usa la botonera de hoy (agarré todas / algunas / ninguna),
  sin ningún cambio. **On** → se habilita la captura de la lectora.
- Reversible en 1 toque. Nada del modelo nuevo corre si el switch está off.

---

## Idea 8243 — Lectora de código de barras en el picking

### Qué reemplaza
Hoy el operario, por cada código de la tanda, toca en el celu **agarré todas /
algunas / ninguna**. Se busca reemplazar el toque por un **disparo de lectora**.

### Hardware (decidido / a comprar)
- **Lectora Bluetooth a batería** (idealmente **ring scanner** de dedo) emparejada
  al **celular actual** en **modo HID** (actúa como teclado). El celu queda en la
  funda; cada disparo "tipea" el contenido en la app.
- Se compra **UNA** para el piloto. Ver § Hardware recomendado abajo.

### Barcode (decidido — v6.76: EAN-13, dos códigos por artículo)
- **Dos EAN-13 por artículo** (los genera la herramienta): **TODO** = `779558700`+NNN+verificador
  (mercadería completa → "agarré todas") · **FALTA** = `779558701`+NNN+verificador (le falta algo
  → abre la tablet para completar la cantidad). `779` = Argentina (GS1); el **verificador** (mod-10)
  lo agrega la impresora (ZPL `^BE`) / el algoritmo público. La app distingue TODO/FALTA por el 9º
  dígito del prefijo (0/1).
- `NNN` = **parte numérica del código** (`943E`→`943`). ⚠ Pares base+variante **comparten NNN**
  (**323/323E · 502/502T · 505/505I · 510/510T · 587/587T · 580/580E/580ES**) → el scan resuelve por
  **contexto de la tanda** (el artículo que ese pedido pide); si una tanda pide los dos, hay que
  mirar. La herramienta **marca** esas colisiones (rojo / columna `nnn_compartido` del CSV).
- La app **también** lee un **Code-128** interno `CÓDIGO|T`/`CÓDIGO|A` como **fallback** (lleva el
  código completo, sin la ambigüedad del NNN) — por si algún artículo colisionado lo necesita.
- Decode en la app: `pkOnScan` → `_pkDecodeEAN` (prefijo+marcador+NNN) → `_pkFindByNum3` (matchea
  la parte numérica contra los artículos pendientes de la tanda).

### Etiquetas: van en el SLOT de góndola (decidido)
- Una etiqueta por artículo, **pegada en su lugar de góndola**, generada desde la
  **planimetría** (tabla `Planimetria` / `window.GONDOLA`, que ya mapea artículo↔sector).
- **2 barcodes por artículo**: **TODAS** (`código|T`) y **ALGUNAS** (`código|A`),
  bien diferenciados por **texto grande** (la Zebra es térmica B&N, no hay color).
- Slots compartidos (2 artículos) → 2 juegos de etiquetas. Excedente/racks (sin lugar
  fijo) → fallback a la tablet. Al mover un artículo de lugar → reimprimir su etiqueta.
- Herramienta: **`tools/etiquetas-gondola.html`** genera el **ZPL** para la Zebra.

### Flujo (con el switch ON)
1. **TODAS** → 1 disparo del barcode verde → la app carga la cantidad pedida de ese
   código y emite el **evento PKC de siempre**. (El 90% de los casos.)
2. **ALGUNAS** → disparo del barcode "algunas" → **selecciona el artículo** → la tablet
   pide "¿cuántas?" → tipean. (El scan puede decir "algunas" pero no *cuántas*.)
3. **NINGUNA** → desde la tablet (raro; se deja fricción a propósito).

### Por qué es seguro / en vivo
- El scan solo **reemplaza el toque**; **emite el mismo PKC** → el monitor en vivo
  **ya funciona**, sin cambios.
- **WiFi:** el link pistola→celu es **Bluetooth (no usa WiFi)**. La sync al server
  **ya tiene cola offline** (`vir_stock_pend`, `enqueueReport`, tests `pk-offline`)
  → un disparo nunca se pierde aunque se caiga la red. Respaldo: datos 4G en el celu.
- El **verificador** del barcode (o el checksum de Code-128) caza malas lecturas
  (beep de error) → no carga basura.

### Pasos de implementación (todo detrás del switch)
1. Flag `picking_scanner` + toggle en supervisor. (Off = hoy.)
2. Captura del scan (listener keydown "wedge": junta caracteres hasta Enter).
3. Decode `código|acción` → resolver contra la **lista de la tanda** (qué pide, cuántas).
4. TODAS → carga pedido + PKC. ALGUNAS → foco al artículo + input cantidad. Beep de error
   si el código no está en la tanda o el checksum falla.
5. Feedback en pantalla (glanceable, no se toca): "✓ 943E — 12 cargadas".
6. Smoke test del modo scanner (con el flag prendido) + verificar que **con el flag
   apagado el smoke actual sigue igual**.

---

## Idea 5290 — Impresora de etiquetas por lío + ensunchadora

### Contexto (dueño, 31/07)
Hoy, al terminar un lío hacen el suncho a mano y **escriben arriba** el código + cajas
+ cliente. Ya tienen una **impresora Zebra** y evalúan una **ensunchadora automática**.

### Flujo nuevo propuesto (con ensunchadora)
1. **Separan los ítems** del pedido (como hoy).
2. **Preparan las pilitas** de lo que van a armar.
3. **Se imprime la etiqueta de cada pilita** (código + cajas + cliente) → automática.
4. Pasan la pilita por la **ensunchadora**.
5. Así el **separado + armado de líos** queda como **un solo proceso**.

### Arquitectura de impresión (por qué un "puente")
- Una **PWA no imprime directo** a una térmica (iOS no da WebBluetooth/WebUSB). Patrón
  robusto: **puente de impresión** — un aparatito always-on (Raspberry Pi / tablet /
  mini-PC) en la WiFi del depósito, conectado a la **Zebra**, que:
  - **escucha una tabla nueva** `Cola_Etiquetas` en Supabase (o realtime),
  - al cerrar una pilita/lío, la app **inserta el job** (código, cajas, cliente — datos
    que **ya existen** por los eventos de armado / líos / AUB),
  - el puente **imprime por ZPL**.
- Ventaja: sirve para cualquier celu/iOS, es resiliente, y desacopla el teléfono de la
  impresora. El **mismo puente + Zebra** imprime también las **etiquetas de góndola**
  de la idea 8243 (una sola compra sirve para las dos).

### Impresora
- La **Zebra que ya tienen** probablemente sirve (las desktop ZD2xx/ZD4xx son directas
  a térmica y renderizan Code-128/Code-39 nativo por ZPL). Ver § Hardware para confirmar
  el modelo. Etiqueta ~ direct thermal, tamaño a definir (para pilita: ~50×75mm; para
  slot: ~40×25mm).

### Pasos (también detrás de switch propio, `etiqueta_lio`)
1. Tabla `Cola_Etiquetas` (Supabase) + plantilla ZPL.
2. Puente de impresión (script que escucha la cola e imprime).
3. Hook en el cierre de pilita/lío → inserta el job (detrás del flag).
4. Ajuste del flujo separado↔armado para el modelo "pilitas + ensunchadora".

---

## Hardware recomendado (a verificar en Mercado Libre AR)

### Lectora (idea 8243)
- **Premium / ideal:** **Zebra RS5100** (ring scanner Bluetooth, 1D/2D, batería de
  turno completo). Es lo que usan los grandes; más caro.
- **Económica para el piloto:** **ring scanner Bluetooth genérico** tipo **Eyoyo**
  (EY-016PRO) o **ONEWSCAN** — Bluetooth + 2.4G, batería, memoria offline, leen
  Code-128. USD ~40-100. Buscar en ML: *"escaner anillo bluetooth"* / *"ring scanner
  inalambrico codigo de barras"*.
- **Alternativa pistola:** lectora **Bluetooth a batería** (no ring). Buscar *"lectora
  codigo de barras inalambrica bluetooth recargable"*.
- Requisito: que lea **Code-128** (todas lo hacen) y modo **HID/teclado**.

### Impresora (idea 5290)
- La **Zebra que ya tienen** (confirmar modelo: ZD230 / ZD421 / GK420 / etc.). Cualquier
  Zebra desktop direct-thermal con ZPL sirve. Si es muy vieja (EPL) igual anda con
  plantilla EPL. Etiquetas: rollo direct-thermal del tamaño elegido.

> Nota: los links exactos de ML cambian seguido; comprar por **modelo** con esas
> búsquedas. Pedir factura y que aclare **Bluetooth + batería** (no solo USB).

---

## Sinergia y orden sugerido
1. **Comprar 1 lectora** + confirmar la Zebra. (En paralelo.)
2. **Imprimir las etiquetas de góndola** con `tools/etiquetas-gondola.html` (ya se puede,
   no depende de la app).
3. **Piloto del modo scanner** detrás del switch `picking_scanner`, con 1 operario.
4. **Etiqueta por lío** detrás del switch `etiqueta_lio` + puente de impresión.
5. Ajustar el flujo separado↔armado con las pilitas + ensunchadora.
