# GV-UI — el sistema de diseño de Gestión Virgilio

**Pedido de Luis, 13/10/2026:** *"quiero que agarremos una filosofía de diseño visual / front /
usabilidad moderna y que cortemos con la basura. Buscamos que sea rápidamente procesable
visualmente cualquier pantalla de esta aplicación. Sin texto excesivo, claridad visual, directo al
grano con la información más importante primero y bien simple."* · *"Deberíamos hacer un agente o
.md o algo para que cuando se genere un módulo nuevo, haga un pase para dejar establecidas las
normas de estética y diseño unificadas para el programa."*

| pieza | qué es |
|---|---|
| **`gv-ui.css`** | la FUENTE: tokens y clases. Un módulo no escribe sus propios px ni sus propios hex |
| **este archivo** | de dónde sale cada número y por qué. Se lee antes de tocar `gv-ui.css` |
| **`.claude/agents/disenador-gvui`** | el PASE: audita un módulo contra esto y devuelve el diff |
| **`tests/gv-ui-sistema.cjs`** | el candado: el módulo nuevo usa el CSS compartido y no inventa escala |
| regla corta | el bloque **«GV-UI»** del `CLAUDE.md` (los 8 puntos) |

## Por qué existe — el número que lo justifica

Medido el 13/10/2026, antes de escribir una línea:

| archivo | tamaños de letra distintos | colores distintos |
|---|---:|---:|
| `index.html` | **38** | **302** |
| `importacion.js` | 19 | 72 |
| `analisis.js` | 17 | 29 |
| `cobranzas.js` | 16 | 44 |
| `hotsale.js` | 13 | 18 |
| `estadisticas.js` | 10 | 15 |
| `ads.js` | 6 | 22 |
| `plantel.js` | 6 | 20 |

Cada módulo escribía su propio `<style>` con su propia escala. No es que estuviera feo: es que
**no había UNA app, había nueve**, y cada pantalla nueva arrancaba de cero.

---

## 1. Los 8 principios (la versión corta vive en `CLAUDE.md`)

1. **UN dato principal por pantalla, y es el texto más grande que se ve.**
2. **Tres niveles de tamaño y nada más.** Un cuarto es indecisión.
3. **El veredicto antes que los números**: una línea que dice qué pasa y qué hacer.
4. **Lo explicativo se pliega** en un `<details>` cerrado.
5. **El color significa**, y nunca va solo.
6. **Un rótulo son 1 o 2 palabras**, sin la fórmula al lado.
7. **Una línea por ítem**, con «y N más» pasando de 8.
8. **Sin emojis decorativos y sin unidad repetida.**

---

## 2. Tipografía

```
11 · 12 · 14 · 16 · 20 · 30     (+ 46 para el dato principal)
```

- **14 px es el PISO de un dato.** Carbon (`body-compact-01`, 14/18), Fluent (Body 1, 14/20) y Ant
  Design ponen el dato de tabla en 14 px y **ninguno baja de ahí**. 11 y 12 son para rótulo o
  metadato, nunca para el número que el supervisor viene a leer.
- **Los saltos son de 2 px, no un ratio modular.** Un ratio de 1,25 desde 14 px da 17,5: inservible.
  Carbon y Fluent hacen lo mismo en su rango denso (10 → 12 → 14 → 16 → 20).
- **El dato principal es ~3× el rótulo** (46 contra 11-14).
- **Para densificar se achica el AIRE, nunca la letra.** Es la regla explícita de SAP Fiori: entre
  su modo *cozy* y su modo *compact* **el tamaño de fuente no cambia** — cambian el espaciado y los
  controles. Si una pantalla no entra, se baja el padding y el alto de fila, no el `font-size`.

### Encabezados de columna: **sentence case, NO MAYÚSCULAS**

Carbon decía *title case* en la v9 y **lo cambió a sentence case en la v10/v11**; Atlassian y GOV.UK
piden lo mismo. El motivo medible: la lectura en mayúscula es del orden de **10 % más lenta**. La
única excepción admitida es un rótulo **muy corto y de vistazo** —un chip de 4 letras, el `PICK` /
`ARM` de una tarjeta—, donde no hay palabra que reconocer y la mayúscula sirve de etiqueta.

**Aplicado**: `.gv-tbl th` no lleva `text-transform`. La mayúscula se deja sólo donde el rótulo es
una **etiqueta de 3-4 letras** (`PICK` / `ARM` de una tarjeta, `PICKING` sobre el dato principal):
ahí no hay una palabra que reconocer y la mayúscula no penaliza. Las tablas viejas con
`text-transform: uppercase` se arreglan cuando se las toca — la migración es forward-facing.

---

## 3. Espaciado y densidad

```
2 · 4 · 8 · 12 · 16 · 24 · 32 · 48 px
```

Base 4, con el 2 para lo micro — es la escala de Carbon (`spacing-01` = 2 px, `-02` = 4 px).

| | alto de fila | padding de celda |
|---|---|---|
| compacto | **32 px** | 4 / 8 |
| normal | **40 px** | 8 / 12 |
| cómodo | **48 px** | 12 / 16 |

- Son los tamaños `sm` / `md` / `lg` de Carbon, y el *compact* de Fiori es 32 px también.
- **El encabezado tiene el mismo alto que la fila** (Carbon).
- **Material define la densidad como una función, no como tres presets**: cada nivel resta **4 px**
  de padding o de alto. Es la forma correcta de pensar un modo denso nuevo.
- **No se mezclan densidades dentro de una jerarquía** (Fiori): una tabla compacta adentro de una
  pantalla cómoda se lee como un error de maquetación.
- **La densidad extrema no se fuerza por default.** Material: *"People should be able to opt in to
  dense layouts"*; Carbon expone los dos altos chicos como preferencia del usuario.

---

## 4. Color — todo medido, nada estimado

Contraste calculado con la fórmula WCAG 2.x contra el fondo de la app (`#f6f7f9`). **Mínimo AA:
4,5:1 para texto chico · 3:1 para texto grande (≥ 24 px, o ≥ 19 px en negrita) y para bordes.**

| token | hex | sobre `#f6f7f9` | para qué |
|---|---|---:|---|
| `--gv-ink` | `#0f172a` | **16,65** | texto |
| `--gv-ink-2` | `#475569` | **7,07** | texto secundario y rótulos |
| `--gv-error` | `#b91c1c` | **6,04** | error, valor malo |
| `--gv-warn` | `#92400e` | **6,61** | alerta (TEXTO) |
| `--gv-ok` | `#15803d` | **4,68** | valor bueno |
| `--gv-info` | `#0f62fe` | **4,67** | informativo |
| `--gv-muted` | `#94a3b8` | 2,39 | **SÓLO líneas e íconos. Nunca texto.** |

### Las tres trampas que esto cierra

1. **El ámbar `#d97706` que la app venía usando mide 2,97 y NO cumple AA.** Lo reemplaza `#92400e`
   (6,61). Era el color de «para mirar», o sea justo el que tiene que leerse.
2. **El amarillo pleno `#f1c21b` como TEXTO sobre blanco mide 1,68.** Es ilegible. Sólo sirve
   **como fondo con texto negro** (`#161616` sobre `#f1c21b` = **10,75**, pasa AAA). Por eso no hay
   token de texto amarillo.
3. **El gris se mide contra el fondo real, no contra blanco.** `#64748b` da 4,76 sobre blanco y
   **4,44 sobre `#f6f7f9`**: pasa y no pasa según dónde caiga. Por eso el secundario es `#475569`.

### El color nunca va solo

**WCAG 1.4.1 (nivel A):** el color no puede ser el único medio visual de transmitir información. Un
lector de pantalla no anuncia el color, y un daltónico no lo distingue.

- **Falla:** un punto verde = bien, rojo = mal.
- **Pasa:** `.gv-state` — el borde izquierdo de color **y** la palabra («2 hallazgos fuertes»).
- **Pasa:** la fila mala de la tabla — fondo rosa **y** barra izquierda **y** el número en rojo.
- **Cómo se testea en 10 segundos:** DevTools, `filter: grayscale(100%)` sobre la pantalla. Si en
  gris no se distingue, falla.

---

## 5. Tablas

- **Divisores horizontales finos, sin zebra.** Carbon permite el zebra como opción pero exige que,
  si se apaga, haya divisores. Con color semántico en juego (fila mala, valor en rojo) el zebra
  **pelea con el dato**: gana el divisor.
- **Cifras tabulares** (`font-variant-numeric: tabular-nums`, ya en `.gv-tbl`). Sin eso el `1` ocupa
  menos que el `8` y la columna de m³ baila. Lo recomienda Polaris y es gratis.
- **Encabezado sticky** (`position: sticky; top: 0` sobre un wrapper con `overflow: auto`). El scroll
  va en el **wrapper**, nunca en la página.
- **Fila problemática:** fondo + barra de 4 px a la izquierda + el valor marcado. Nunca fondo solo.
- **Más de ~8 columnas**: primera columna fija o esconder columnas. Las tarjetas apiladas sirven
  hasta 6 columnas cortas; pasado eso son listas verticales peores que la tabla.

### La alineación de los números: CENTRADOS — cerrado

**Ningún design system de peso recomienda centrar números; Polaris lo desaconseja explícitamente** y
pide numéricas a la derecha, porque alinea unidades y decimales y hace escaneable la columna.

**Se le llevó a Luis con ese argumento y decidió centrado** (13/10/2026: *"dejalo centrado, decisión
estilística para todo GV"*), en línea con su regla del 28/09 (*"todo el contenido centrado, no
algunas cosas sí y otras no"*). **Es estilo de la casa, tomado a sabiendas: no se vuelve a proponer
la alineación a la derecha** — ni como mejora, ni como hallazgo de un pase, ni "porque lo dice
Polaris". Eso ya se discutió.

Lo que sí entró, porque no choca con nada, son las **cifras tabulares**
(`font-variant-numeric: tabular-nums`, ya en `.gv-tbl`): arreglan la mitad del problema —que la
columna baile porque el `1` es más angosto que el `8`— sin mover la alineación.

### Ancho según contenido — Luis 16/10/2026

**Luis, textual** (sobre el pop-up «Cajas pedidas — 936E» de Stock y Compras): *"que revise esto y
establezca una regla. Tablas optimizadas horizontalmente (no debería haber tanto espacio entre
columna y columna (mucho espacio en blanco entre razon social, cajas y NP). Headers centrados,
minimo gasto de espacio horizontal, font y visual lo mas grande y clara posible. implementa cambios
a lo largo del modulo"*.

El caso: la tabla NP · Razón Social · Cajas · Pick · Arm iba a `width:100%` con `table-layout:fixed`
dentro de una tarjeta de 760 px. Medido: 730 px de tabla para 4 datos cortos (NP 266 px, Razón
Social 254 px), encabezado de 10 px en mayúscula `#64748b`, dato de 12 px, números a la derecha.
Después: 559 px de tabla (NP 145, Razón Social 260 con «…», Cajas 57), encabezado 14 px `#334155`
centrado, dato 14 px. Es la misma regla que la de Damian del 25/09 para las tablas de Claude, ahora
para las de la app.

1. **La tabla NO se estira al contenedor.** `width:auto` (o `max-content`) y `table-layout:auto`;
   **nunca `width:100%`**. Cada columna mide su dato más largo + padding mínimo (8–10 px por lado).
   Si sobra espacio, sobra **a la derecha de la tabla**, no repartido entre columnas. El wrapper
   también va a su ancho (`width:fit-content; max-width:100%`) para que el borde no dibuje la caja
   vacía.
2. **El texto largo se corta, no ensancha.** La razón social / descripción lleva `max-width`
   (≈ 240–260 px en escritorio, ≈ 120 px a ≤ 560 px) con `text-overflow:ellipsis` y el texto entero
   en el `title`.
3. **Encabezados centrados, todos**, legibles: **13–14 px**, color `#334155` o `--gv-ink-2`
   (≥ 7:1), sin el gris lavado (`#94a3b8` = 2,56:1) y sin la mayúscula de 10–11 px (§2).
4. **Dato ≥ 14 px** (§2). Números **centrados** con `tabular-nums` (decisión cerrada, arriba).
5. **Mínimo gasto horizontal**: sin columnas fantasma, sin anchos fijos en `%`, sin
   `table-layout:fixed` con columnas al `%`. La única excepción es una tabla ancha con `<colgroup>`
   medido (Pedidos Importación, `.mva-tbl.wide`), que ya mide lo que suman sus columnas.
6. **Pop-ups**: la tarjeta puede seguir en 760 px; la tabla de adentro no se estira con ella.
7. **Celular (430 px)**: la tabla tiene que entrar sin scroll horizontal; se baja el padding a
   6–7 px y el `max-width` del texto largo, **no** la letra.

**Dónde vive**: `.gv-tbl.fit` + `.gv-tblwrap.fit` en `gv-ui.css` para pantallas nuevas. En Stock y
Compras (index.html): `.mva-tbl` (todas las tablas de los pop-ups `_stkPopShell`), `.stk-tbl`,
`.oc-tbl`, `.abast-tbl`, `.proyv-tab` / `.proyv-det`. **La grilla de Stocks** sólo cambió encabezado
y letra: ya era `stk-tbl-fit`.

#### Segunda pasada — pop-ups (Luis, 16/10/2026, mirándolo en un monitor de 1920 px)

**Luis, textual:** *"Mejor pero se puede mejorar aun mas: 1) '936E · pedido PENDIENTE: 12 cajas en 1 NP(s)
(+15 NP ya facturadas/entregadas — no se muestran; verlas en 🕓 Historial)' <- textos como ese no aportan
nada, sacalo. 2) la tabla tiene que estar centrada en sí en el pop-up. 3) Mira todo el espacio
desperdiciado en la pantalla. Que se agrande ajustándose a la pantalla (más grandes las fonts, más
claridad visual). 4) Los emojis al lado de pedido y entrega están al pedo, no quiero tanto EMOJI AI en la
página."*

8. **Sin párrafos de resumen ni explicativos arriba de la tabla** que repitan lo que la tabla ya dice
   (el total está en la fila TOTAL; lo descontado está en el Historial). Un aviso que **cambia una
   decisión** (NP sin programar ⚠) queda, en **una línea corta**: `⚠ 1 NP sin programar en el PPP (6 cajas)`.
   Si la vista no tiene fila de total, el total va en una línea de ≤ 40 caracteres (`12 cajas en 3 NP`).
9. **La tabla va centrada** en el cuerpo del pop-up (`margin-left/right: auto` en el wrapper).
10. **El pop-up escala con la pantalla.** La letra del dato es `clamp(14px, 1vw, 20px)` (14 en
    celular y notebook, ~19 en 1920), el encabezado `clamp(14px, 0.9vw, 17px)`, el título
    `clamp(16px, 1.2vw, 24px)`. La tarjeta mide lo que su contenido (`width: fit-content`) entre
    `min(560px, 96vw)` y `min(clamp(760px, 62vw, 1240px), 96vw)`: no queda una tarjeta chica en el medio
    de 1920 px, ni una tarjeta ancha con la tabla flotando. En celular la letra **nunca baja de 14**.
11. **Sin emojis decorativos** en títulos, rótulos, encabezados, botones ni celdas (🛒 📅 🟡 📦 🧾 🕓 🔁 📍
    👤 ⬇ …): texto plano — «Pedido 7/10», «Entrega 22/10», «Exportar a Excel». Queda un ícono sólo si
    es un **estado que se lee de un golpe y no tiene palabra**: ⚠ de alerta, ✓ hecho, ✕ cerrar/descartar.

Medido en «Cajas pedidas — 936E»: a 1920 px, dato de 14 → 19,2 px, encabezado 14 → 17 px, tarjeta de
760 px con la tabla de 577 recostada a la izquierda → tarjeta de 758 px con la tabla de 728 centrada; a
430 px, 14 px y sin scroll horizontal. Lo sostiene `tests/stk-tabla-ancho-contenido.cjs` (f–i).

**Alcanza también a Pedidos Importación** (`importacion.js`, Luis 16/10, «D2 sí»): títulos, solapas, botones y celdas
sin emojis (quedan ⚠ ✓ ✕ y los de estado ⛔ 🔴 🟡 del MOQ y la quiebra, más los botones que son sólo ícono 📦 📥 ✏️,
que sacados pierden el rótulo), sin los párrafos de explicación arriba de las tablas (quedan, en una línea, los avisos
que cambian una decisión y los conteos sin fila de total), tarjeta al ancho del contenido y solapas que escalan. **La
tabla ancha `.mva-tbl.wide` queda con sus anchos fijos** (`<colgroup>` medido, `_anchoMax`, `tests/pedimp-ancho-tabla.cjs`
y la regla v24.32 de `docs/REGLAS-IMPORTACION.md`): sólo cambió el encabezado (12 → 13 px, #334155, centrado); su letra
de 15 px no escala, porque las columnas están medidas en px para ese tamaño.

**Botones que son sólo ícono (📦 📥 ✏️ ⚙): QUEDAN — decisión cerrada** (Luis, 16/10/2026: *"esos dejalos"*). No se
proponen pasar a texto ni se marcan como hallazgo en un pase de diseño.

---

## 6. Estados de la pantalla

| situación | qué se muestra |
|---|---|
| **cargando** | < 1 s: **nada**. 1–10 s: `.gv-msg` con «Calculando…». > 10 s: porcentaje y forma de cortar |
| **vacío de verdad** | «No hay tandas con picking o armado terminado en el período» |
| **vacío por filtro** | **es otro estado**: «Ninguna tanda con avisos» + cómo aflojar el filtro |
| **error** | `.gv-err` con el motivo. **Nunca se dibuja como vacío** |
| **parcial** | se dice qué dato falta y por qué, el resto se muestra |

- Los tres umbrales son los de Nielsen: **0,1 s** instantáneo · **1 s** sin perder el hilo · **10 s**
  límite de atención.
- **Vacío de verdad y vacío por filtro son estados distintos** (Carbon y Cloudscape los separan por
  nombre). Confundirlos deja al usuario en un callejón sin salida.
- **El parcial no está en ningún design system de la industria**: la regla *«una lectura ROTA no es
  un CERO»* de este repo es más estricta que el estado del arte. No hay nada que importar; hay algo
  que exportar.

---

## 7. Microcopy

- **Rótulo:** 1 o 2 palabras, sentence case, sin dos puntos al final, sin la fórmula entre
  paréntesis. `rendimiento`, no `rendimiento (esperado ÷ real)`.
- **Mensaje de error:** lo importante **primero** (frontload), al lado de lo que falló, redactado a
  nivel de lectura de 7.º grado. *«No se pudo leer: timeout»* antes que *«Ha ocurrido un error al
  intentar procesar su solicitud»*.
- **Nunca culpar al usuario** en un estado vacío.
- **Hora en 24 h `HH:MM`** (regla de unidades del repo). Tiene respaldo: la guía británica permite
  24 h *"si los usuarios internos evidentemente lo prefieren"*, que es exactamente un depósito.
- **Fecha `Mié 07/10`** (`gvDiaTxt`), **m³ con coma decimal**, la unidad en el rótulo y no en cada
  celda.

---

## 8. Celular del operario

- **Todo lo que se toca mide 44 × 44 px de ÁREA** (el ícono puede medir 20). Es el AAA de WCAG 2.5.5
  y el mínimo de Apple HIG; cumpliendo 44 se cumple también el AA de 24. El operario trabaja de pie,
  con guantes y con luz de galpón: acá el piso de accesibilidad **es** el requisito funcional.
- **Una tabla ancha no se convierte en tarjetas si hay que comparar filas**: scroll horizontal en el
  wrapper y primera columna fija.
- **En celular la barra de scroll está oculta**: si hay columnas más allá del borde, hace falta una
  señal visible.

---

## 9. Lo que NO se hace

| antipatrón | por qué |
|---|---|
| Encabezados de columna en MAYÚSCULA | ~10 % más lento de leer (Carbon pasó a sentence case) |
| Zebra **y** sin divisores | Carbon: si se apaga el zebra, los divisores son obligatorios |
| Mezclar densidades en una jerarquía | Fiori |
| Sombras decorativas | la elevación es información (apilamiento real), no adorno |
| Más de 2 radios distintos | `--gv-r-sm` y `--gv-r`, y la pastilla |
| Tarjetas anidadas | tres bordes para un dato |
| Emoji decorativo | se anuncia por su nombre Unicode, que casi nunca es lo que se quiso decir. **Si se saca y no se pierde información, se saca** |
| Párrafo de resumen o de explicación arriba de una tabla | repite lo que la tabla ya dice (Luis 16/10: *"textos como ese no aportan nada, sacalo"*). Un aviso que cambia una decisión va en **una línea** (§5) |
| Emoji en título, encabezado, botón o celda de un pop-up (🛒 📅 🟡 📦 🧾 🕓) | Luis 16/10: *"no quiero tanto EMOJI AI en la página"*. Texto plano; sólo ⚠ ✓ ✕ como estado (§5) |
| Tabla estirada al 100 % o pop-up de ancho fijo chico en una pantalla grande | ríos blancos entre columnas / letra chica en el medio de 1920 px (§5, «Ancho según contenido») |
| Un `font-size` o un hex nuevo en un módulo | para eso están los tokens |

---

## 10. La pantalla de referencia

**`analisis.js` (Análisis Productivo) es el molde.** Al escribir una pantalla nueva se mira cómo
está hecha ésa, no cómo estaba la vieja.

| qué | dónde |
|---|---|
| encabezado + subtítulo | `.an-hd` |
| veredicto + acciones | `.gv-state` |
| el dato principal | `.an-hero` → `.gv-hero` |
| hallazgos | `.gv-item` |
| lo plegado | `details` / `summary` |
| tabla | `.gv-tbl` dentro de `.gv-tblwrap` |

---

## 11. El PASE de diseño de un módulo nuevo

**Obligatorio antes de dar por terminada una pantalla nueva.** Lo corre el agente
`disenador-gvui` (`.claude/agents/disenador-gvui.md`), que renderiza la pantalla headless y la
compara contra este documento. Los 10 puntos que mira, en orden:

1. ¿Carga `gv-ui.css` y usa `.gv` en su contenedor raíz?
2. ¿Cuántos `font-size` propios escribe? (debería ser 0 fuera de los tokens)
3. ¿Cuántos hex propios escribe? ¿Alguno es texto con contraste < 4,5?
4. ¿Cuál es el texto más grande de la pantalla? ¿Es el dato principal?
5. ¿Hay un veredicto de una línea arriba?
6. ¿Hay texto explicativo largo sin plegar?
7. ¿La tabla tiene `tabular-nums`, divisores y encabezado sticky?
8. ¿Algún estado se comunica **sólo** con color? (prueba en escala de grises)
9. ¿Los blancos de toque llegan a 44 px a ≤ 560 px de ancho?
10. ¿Hay emojis que, sacados, no pierden información?

Devuelve `archivo:línea — [severidad] problema → fix`, y el candado automático de los puntos 2, 3,
4, 6, 8 y 10 es `tests/gv-ui-sistema.cjs`.

---

## 12. Lo que queda abierto

- **La migración de los módulos viejos**: es **forward-facing**. `gv-ui.css` lo usa el módulo nuevo
  y el que se toca; nadie reescribe `importacion.js` por esto. Los 302 colores de `index.html` se
  van muriendo solos.
- **`monitor/tv.html` queda afuera a propósito**: es una pantalla a 4 metros, con fondo oscuro y su
  propia escala en `--u` (`min(1vh, 0,5625vw)`). Tiene su propio sistema y funciona.

---

## 13. De dónde salen los números

IBM Carbon (tipografía, espaciado, alto de fila, tabla, color) · SAP Fiori (densidad cozy/compact,
44 px táctil) · Microsoft Fluent 2 (escala tipográfica) · Material 3 (densidad como función de −4 px,
48 dp táctil) · Shopify Polaris (alineación y cifras tabulares) · Ant Design (padding de celda) ·
Atlassian y GOV.UK (microcopy, sentence case) · Nielsen Norman Group (umbrales de respuesta, mensajes
de error, acordeones) · WCAG 2.1/2.2 (1.4.1, 1.4.3, 1.4.11, 2.5.5, 2.5.8) · Shneiderman 1996
(«overview first, zoom and filter, details on demand»).

⚠ **Los contrastes de este documento están calculados acá**, con la fórmula WCAG 2.x, no copiados de
ninguna tabla. Para recalcular con un color nuevo está el script al final de la sección 4 del
`CLAUDE.md`, o:

```js
const L = h => { h = h.replace("#",""); if (h.length===3) h = h.split("").map(c=>c+c).join("");
  const c=[0,2,4].map(i=>parseInt(h.substr(i,2),16)/255)
    .map(v=> v<=0.03928 ? v/12.92 : Math.pow((v+0.055)/1.055, 2.4));
  return 0.2126*c[0] + 0.7152*c[1] + 0.0722*c[2]; };
const ratio = (a,b) => { const x=L(a), y=L(b);
  return ((Math.max(x,y)+0.05) / (Math.min(x,y)+0.05)).toFixed(2); };
ratio("#92400e", "#f6f7f9");   // 6.61
```
