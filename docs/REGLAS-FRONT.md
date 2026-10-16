# Reglas Front — Técnica de front: diseño GV-UI y espacio, UTF-8, Service Worker, onclick/window, tests, dead-handlers, agentes

> Movido de `CLAUDE.md` el 2026-10-13 (poda 3ra tanda, pedido de Luis) **sin cambiar una palabra**.
> **Leerlo ENTERO antes de tocar algo de este tema.** Las reglas siguen valiendo igual que cuando estaban en CLAUDE.md.

## 🟥 REGLA RECTORA (Luis, 28/09/2026): OPTIMIZACIÓN DE ESPACIO EN TABLAS Y VISUALES

**Vale para TODOS los repos y TODA pantalla, tabla, ficha o reporte** (copiar este bloque al
`CLAUDE.md` del repo nuevo). **Mostrar la mayor cantidad de información en el menor espacio
posible, apuntando siempre a la claridad.** Lo primero que se achica es el espacio HORIZONTAL.

1. **El espacio en blanco o vacío se evita como la plaga.** Ninguna celda de relleno: si un dato
   no existe, la fila/columna se reacomoda (el vecino ocupa el lugar con `colspan`), no queda un
   hueco. Un dato que falta se marca con "—"; una celda que no tiene nada que decir no existe.
2. **Todo el contenido centrado**, no algunas cosas sí y otras no.
3. **Rótulos abreviados** (`Localidad pto Venta` → `Loc PDV`, `Límite de crédito` → `Lím. crédito`).
   **Doble o triple fila en el rótulo no molesta**: se parte antes que ensanchar la columna.
4. **Lo que va junto, va junto**: datos de la misma familia en el mismo bloque, con un rótulo
   común y sub-rótulos (Pagos → Último · Anteúlt. · Antepenúlt.; FC por año como matriz).
5. **Si el dato se explica solo, no lleva rótulo** (una dirección de mail no necesita "Mail").
6. **No repetir**: una unidad (`$`) va una vez en el rótulo, no en cada celda; dos datos iguales
   (Loc PDV = Loc entrega) se muestran en una sola celda.
7. **Rótulo arriba del dato** cuando eso ahorra ancho; el ancho de cada columna lo da el dato.

Caso que la originó: la Ficha de Cliente del admin (hoja de 4 columnas rótulo/valor, ~705 px,
con celdas vacías, pagos separados y rótulo "Mail") pasó a una grilla de 6 columnas con el
rótulo arriba: **~530 px**, sin una celda vacía. Lo sostiene `tests/ficha-hoja.cjs` (bloque E) en
`pagina-LK-copia`.

### ⚠ MENOS EMOJIS (Luis, 2026-10-06): limpieza visual, no decoración

**Vale para TODOS los repos y toda pantalla, tabla, cartel o reporte.** Luis, con el desplegable
del orden de prioridad del Resumen de la PPP: *"menos emojis en general"*. El emoji **decorativo**
—el que sólo adorna un título, un botón o un bullet— se saca: una pantalla llena de íconos cansa
y resta claridad. Una lista larga NO va como columna de 24 bullets con un emoji por línea: va en
**grilla compacta** (CSS `column-width`), sin pictogramas al costado de cada ítem.

El emoji **se deja sólo cuando ES el dato**: un ícono que la tabla usa de verdad y que la leyenda
explica (📦/📅 de «no es demora»), un estado que se lee de un vistazo, el prefijo de un módulo que
el operario ya tiene memorizado. La prueba es: si el emoji se saca y no se pierde información, se
saca.

> **Tablas: ancho según contenido** (Luis, 16/10/2026): ninguna tabla se estira al 100 % del contenedor;
> cada columna a su dato, encabezados centrados 13–14 px oscuros, dato ≥ 14 px; en los pop-ups, tabla centrada,
> letra que escala con la pantalla, sin párrafos de resumen arriba y sin emojis decorativos. Regla completa y medición:
> **`docs/GV-UI.md` §5 «Ancho según contenido — Luis 16/10/2026»**.

## 🟥🟥🟥 REGLA RECTORA DE DISEÑO «GV-UI» (Luis, 2026-10-13, v29.83): UNA PANTALLA SE LEE DE UN VISTAZO

**Luis, textual:** *"quiero que agarremos una filosofía de diseño visual / front / usabilidad
moderna y que cortemos con la basura. Buscamos que sea rápidamente procesable visualmente
cualquier pantalla de esta aplicación. Sin texto excesivo, claridad visual, directo al grano con
la información más importante primero y bien simple."* · *"Deberíamos hacer un agente o .md o algo
para que cuando se genere un módulo nuevo, haga un pase para dejar establecidas las normas de
estética y diseño unificadas para el programa."*

**Vale para TODOS los repos y TODA pantalla nueva o que se toque** (copiar este bloque al
`CLAUDE.md` del repo nuevo). No reemplaza la regla de espacio del 28/09 ni la de «MENOS EMOJIS»:
las tres son la misma idea — **densidad alta, ruido cero** —. Ésta agrega la **jerarquía**.

> ## **La pregunta de cada pantalla es: «¿qué tiene que saber el que la abre, en 2 segundos?».**
> Eso va primero, grande y solo. Todo lo demás baja un nivel o se pliega.

| pieza | qué es |
|---|---|
| **`gv-ui.css`** | la FUENTE: tokens (`--gv-*`) y clases (`.gv-state`, `.gv-item`, `.gv-tbl`, `.gv-hero`…). Se carga en `index.html` con el `?v=` de la app |
| **`docs/GV-UI.md`** | de dónde sale cada número, con el contraste MEDIDO de cada color. Se lee antes de tocar el CSS |
| **`.claude/agents/disenador-gvui`** | **el PASE**: audita un módulo contra el sistema y devuelve `archivo:línea — [severidad] → fix` |
| **`tests/gv-ui-sistema.cjs`** | el candado del sistema (paleta, escala, tokens muertos, la pantalla de referencia) |
| **`analisis.js`** | la **pantalla de referencia**: es el molde |

### Los 8 puntos

1. **UN dato principal por pantalla, y es el texto más grande que se ve.** Si hay dos cosas del
   mismo tamaño, no hay jerarquía: el ojo no sabe dónde parar. El título y el código de la cosa
   (la tanda, el cliente, la OC) **no** son el dato principal: son el rótulo.
2. **Tres niveles de tamaño y nada más.** La escala es **11 · 12 · 14 · 16 · 20 · 30 px** (+ 46
   para el dato principal), y sale de los tokens: **un módulo no escribe un `font-size` propio**.
   **14 px es el PISO de un dato**; 11 y 12 son sólo rótulo o metadato.
   ⚠ **Para densificar se achica el AIRE, nunca la letra** (es la regla explícita de SAP Fiori:
   entre su modo cómodo y su modo compacto el `font-size` no cambia).
3. **El veredicto antes que los números.** Arriba va UNA línea (≤ 60 caracteres) que dice qué pasa
   y qué hacer («2 hallazgos fuertes: mirar de cerca»), no un párrafo que repite lo de abajo.
4. **Lo explicativo se pliega.** Glosarios, metodología, desgloses y la letra chica van en un
   `<details>` cerrado. **Ningún bloque de texto largo se dibuja abierto.**
5. **El color significa, y NUNCA va solo** (WCAG 1.4.1: un lector de pantalla no anuncia el color
   y un daltónico no lo distingue). Estado = **color + forma + palabra**. Se testea en 10 segundos
   con `filter: grayscale(100%)`: si en gris no se distingue, falla.
6. **Un rótulo son 1 o 2 palabras, sin la explicación al lado.** `rendimiento`, no
   `rendimiento (esperado ÷ real)`. La explicación vive en el `<details>` del punto 4.
7. **Una línea por ítem**, con un punto de color para la severidad, y «y N más» pasando de 8.
8. **Sin emojis decorativos** (regla del 06/10) y **sin unidad repetida**: va en el rótulo.

### ⚠⚠ EL PASE: una pantalla nueva no está terminada hasta que lo pasa

**Al crear un módulo o rehacer una pantalla, antes de darla por terminada se corre el agente
`disenador-gvui`.** Mide 10 puntos sobre la pantalla CORRIENDO (no leyendo el código: el
`font-size` que vale es el computado, y el que manda puede venir del CSS global del index): usa el
sistema · escala · contraste calculado · jerarquía · veredicto · nada largo sin plegar · tabla ·
color que va solo · blanco de toque de 44 px a 430 px de ancho · emojis y rótulos.

Y al test del módulo se le copia el **bloque `(g)` de `tests/analisis-productivo.cjs`**, que mide
la regla sola: *un hallazgo sin candado vuelve en la próxima pantalla*.

### Lo que esto cierra, medido el 13/10 antes de empezar

`index.html` tenía **302 colores y 38 tamaños de letra distintos**; `importacion.js` 72 y 19;
`cobranzas.js` 44 y 16. Cada módulo escribía su propio `<style>` con su propia escala: **no había
una app, había nueve.** Tras el pase, `analisis.js` quedó en **0 tamaños propios y 0 hex propios**.

**Tres colores que estaban mal y ahora son tokens** (contraste calculado con la fórmula WCAG 2.x,
contra el fondo real de la app, no contra blanco):

| estaba | medía | va |
|---|---:|---|
| ámbar `#d97706` de «para mirar» | **2,97** ✗ | `--gv-warn` `#92400e` (**6,61**) |
| amarillo `#f1c21b` como texto | **1,57** ✗ | sólo de FONDO con texto negro (**10,75**) |
| gris `#94a3b8` en rótulos | **2,39** ✗ | `--gv-ink-2` `#475569` (**7,07**) · el `#94a3b8` queda sólo para líneas |

### Lo que está DECIDIDO y no se vuelve a discutir

- **Los números de tabla van CENTRADOS. Cerrado por Luis el 13/10/2026** (*"dejalo centrado,
  decisión estilística para todo GV"*), sabiendo que Polaris y el resto de la industria piden
  alinearlos a la derecha. **Es una decisión de estilo de la casa, no un descuido: no se vuelve a
  proponer la alineación a la derecha, ni como mejora ni como hallazgo de un pase.** Lo que **sí**
  entró, porque no choca con nada, son las **cifras tabulares** (`font-variant-numeric:
  tabular-nums`): arreglan que la columna baile sin mover la alineación.
- **Los `<th>` van en sentence case** («Desde el anterior», no «DESDE EL ANTERIOR»): Carbon lo
  cambió en su v10 y la lectura en mayúscula es ~10 % más lenta. **Ya es así en `.gv-tbl`**, o sea
  en la pantalla de referencia; las tablas viejas que todavía tienen `text-transform: uppercase`
  se arreglan cuando se las toca, no antes. **La mayúscula sí se deja en una etiqueta de 3-4
  letras** (`PICK`, `ARM`, `PICKING`): ahí no hay palabra que reconocer.
- **La migración es forward-facing**: `gv-ui.css` lo usa el módulo nuevo y el que se toca. **Nadie
  reescribe `importacion.js` por esto.** Los 302 colores del index se mueren solos.
- **`monitor/tv.html` queda AFUERA** del sistema a propósito: es una pantalla a 4 metros, con
  fondo oscuro y su propia escala en `--u` (`min(1vh, 0,5625vw)`). Tiene su sistema y funciona.

**Chequeo:** `node tests/gv-ui-sistema.cjs` (el sistema: la paleta se mide, la escala está
completa, no hay token muerto y la pantalla de referencia no tiene un px ni un hex propio) ·
`node tests/analisis-productivo.cjs` (el bloque **(g)**: la regla sobre la pantalla corriendo;
verificado que falla al achicar el dato principal). Los números, las fuentes (Carbon, Fiori,
Fluent, Material 3, Polaris, Ant, NN/g, WCAG) y las decisiones abiertas: **`docs/GV-UI.md`**.

## Agentes + código de 4 dígitos (Telegram)

Los agentes ya **NO corren automáticos** (el loop cada 2 h y el curador diario
fueron eliminados el 2026-08-10 para bajar consumo de tokens). Los subagentes
siguen definidos en `.claude/agents/` y se invocan **a mano** cuando hace falta:
`mejoras-virgilio`, `revisor-logica`, `auditor-consistencia`, `auditor-supabase`,
`guardian-stock`, `guardian-tests`, `revisor-render`, `keeper-guia`,
`curador-telegram`. Detalle en `docs/AGENTES-DIARIOS.md`.

Cuando se invoca un agente, cada idea nueva entra a `agente_propuestas`
(`estado='pendiente'`). Si se implementa y verifica (`node --check` + smoke
headless), pasa a `estado='lista'` en su rama **`idea/<código>`**. **Nunca** se
toca `main` desde el agente.

Cada propuesta tiene un **código de 4 dígitos** único.

### ⚠ Reglas para CUALQUIER chat sobre este repo

**Comando `:`** — si el usuario escribe un mensaje que es (o empieza con) `:`,
mostrale **todas las ideas creadas** como **checklist, de a 5** (paginá de 5 en 5),
para que marque cuáles confirma. Traelas así:

```sql
select codigo, estado, agente, impacto, titulo, rama
from public.agente_propuestas
where estado in ('pendiente','lista') order by creado_en desc;
```

Mostralas como `[ ] 4837 · [logica·alto] Título (rama idea/4837)`. El usuario
tilda las que quiere → tratá cada tildada como "idea aceptada" (regla de abajo).

**Idea escrita por el usuario** — cuando el usuario escriba una idea/mejora/pedido
en el chat (aunque no dé ningún número), **registrala para que no se pierda**:

1. `select public.nuevo_codigo_propuesta();` para el código.
2. `insert into public.agente_propuestas (codigo, agente, titulo, detalle, estado)
   values ('<cod>','usuario','<título corto>','<lo que pidió, textual>','pendiente');`
3. Agregá una línea ARRIBA en `docs/IDEAS-USUARIO.md`:
   `- [ ] **<cod>** (AAAA-MM-DD) — <idea> — _pendiente_`, y commiteá/pusheá a `main`.
4. Confirmale al usuario: "Anotada como **<cod>**" (así puede activarla después por número).

Las ideas del usuario tienen **prioridad**: quedan `pendientes` en la tabla hasta
que el usuario las active por número o las descarte.

**Idea aceptada (por número o tildada en el checklist)** — cuando el usuario diga
un **código de 4 dígitos** (`4837`, "hacé el 4837", "acepto 4837") o tilde ideas
en el checklist, por cada código aceptado **mergealo a `main` directamente**:

1. `select codigo, titulo, estado, rama from public.agente_propuestas where codigo='4837';`
2. Si `estado='lista'` y tiene `rama`: `git fetch origin && git checkout main &&
   git pull origin main && git merge --no-ff origin/idea/4837 && git push origin main`.
   Si hay conflicto por drift de main, resolvé o rebasá la rama sobre main y reintentá.
3. Si `estado='pendiente'` (todavía sin rama): desarrollala vos ahora en `idea/4837`,
   verificá (`node --check` + smoke headless), y mergeala a main igual.
4. Marcá `update public.agente_propuestas set estado='hecha', actualizado_en=now()
   where codigo='4837';`. Si el usuario la rechaza → `estado='descartada'`.
   Si es idea del usuario (`agente='usuario'`), además actualizá su línea en
   `docs/IDEAS-USUARIO.md` (`[x]` si hecha, `~~tachada~~` si descartada) y commiteá a `main`.

El merge a `main` es **directo, sin mostrar diff** (así lo pidió el usuario), salvo
que en el momento pida verlo.

## ⚠ REGLA (v29.99): `dead-handlers` mira TODOS los módulos que carga el index, no sólo dos

Un `onclick="fn(...)"` llama a `window.fn`: una función que queda **dentro de una closure** deja el
botón **muerto** y la página no tira ningún error. `tests/dead-handlers.cjs` cubría `index.html` +
`importacion.js`; hoy cubre también cobranzas, hotsale, estadisticas, ads, plantel, analisis, ayuda,
recepcion, planimetria y los dos de talleristas (**1.104 handlers**). **Al sacar un módulo nuevo del
index, agregarlo a `ARCHIVOS`** — si el archivo no existe, el test falla y lo dice.

Lo que destapó: la v29.92 puso `rolPickerAbrir` y `rolElegir` adentro de la closure donde ya viven
`gsLoad` / `gsResolver` (que se exponen a mano con `window.x = x`), así que los dos botones del panel
por rol no hacían nada. **Ese bloque de `index.html` (~63000) NO es top-level**: toda función que se
llame desde un `onclick` va expuesta.

**Barrido del 13/10, 0 muertos fuera de esos dos:** `monitor/tv.html`, `monitor/admin.html`, el
selector y Cervantes no usan `onclick="..."` de texto (asignan la función o usan `addEventListener`,
que no se puede romper por nombre); `admin/` (el espejo de LK) tiene 88 handlers y los 88 resuelven;
`impocomex/` tiene 49 y los 4 que un escaneo estático marca (`onBlur`, `onBorrar`, `onInput`,
`repinta`) son **métodos de objeto y callbacks de `IC.on(...)`**, no globales: falsos positivos.

## ⚠ REGLA (v21.10): `index.html` es UTF-8 — un byte en latin1 se multiplica solo

El archivo declara `<meta charset="UTF-8">`. El 22/09 tenía **5 bytes sueltos en latin1/cp1252**,
dejados por sesiones que lo editaron con herramientas distintas. Tres eran de comentario; **los
otros dos estaban en un string de JS que va al `innerHTML`** —el chip «Mismo pedido» de A Programar—
y el operario veía **`🧾 Mismo pedido � LK 0001 � $836.909`** en vez del separador `·`.

⚠ **Lo que lo hace crecer es que rompe las herramientas.** Con un byte inválido, cualquier script
que abra el archivo como texto UTF-8 explota (`UnicodeDecodeError`); abrirlo como **latin1** para
esquivarlo convierte **todos** los acentos buenos en mojibake y los reescribe así. O sea: el atajo
obvio para editar el archivo es justo lo que multiplica el problema.

**Al editar `index.html` por script**: leerlo y escribirlo en **UTF-8** o **en bytes** (`"rb"`/`"wb"`
con los patrones en `.encode("utf-8")`), **nunca** en latin1. Y sigue valiendo lo del **NUL** de
`_pppGeoCod`: es UTF-8 válido y legítimo, sólo hace que `grep` trate al archivo como binario.

**Chequeo:** `node tests/encoding-utf8.cjs` — index.html, sw.js, recepcion.js, planimetria.js y
supabase-config.js; falla nombrando archivo, línea y contexto. Verificado rompiéndolo a propósito.

## ⚠ REGLA (v21.61): un test VIEJO deja main en rojo igual que uno ROTO — y la clase del botón se comparte

El 23/09 la v21.76 agregó el **candado de código** (una tanda empezada conserva su nombre) con su
test propio `ppp-tanda-candado-codigo.cjs`, y dejó **`ppp-tanda-cambiar-dia.cjs` sin tocar**. Ese
test medía justo lo contrario —que una tanda ARMADA puede ir a «tanda nueva» o fusionarse— así que
main quedó en rojo (issue del CI) hasta la v21.61. Es el caso que la regla de la v21.53 ya nombra:
**al cambiar una pantalla, `grep` su nombre en `tests/` antes de dar el cambio por terminado.**

⚠⚠ **Y el botón nuevo se llama IGUAL que el viejo.** «🔒 Mismo código» salió con la clase
`mv-esp-b nueva` —la misma de «➕ Tanda nueva»— y **dibujado primero**, así que
`querySelector("#pppMovBody .mv-esp-b.nueva")` pasó a agarrar otro botón sin que nada avisara: el
test clickeaba el candado creyendo que clickeaba tanda nueva, y el `p_tanda_destino` salía `null`
en vez de `""`. **Un selector que ya usa alguien no se reutiliza para un botón distinto.**

Qué mide hoy `ppp-tanda-cambiar-dia.cjs`, que son **dos casos y no uno**:

| tanda | estado | qué ofrece el paso 2 |
|---|---|---|
| **E01A** (c) | armada | **sólo** «🔒 Mismo código» → `p_tanda_destino = null`. Ni tanda nueva ni fusión |
| **E02A** (f) | pendiente | «➕ Tanda nueva» **y** los destinos, con su compatible / incompatible / aviso |

⚠ **E02A NO se agrega como tercera fila del árbol**: probado, eso rompe el render de «Pedidos
atrasados» y tira (e) abajo. El pop-up se arma igual que `pgaTandaMoverAbrir`, cambiando lo único
que separa los dos casos: `empezada`.

⚠ **Y había una carrera aparte, real**: dos `.click()` sin guard (el de «tanda nueva» y el del
botón de atrasados, que esperaba la FILA y clickeaba el BOTÓN) morían con *"Cannot read properties
of null"* bajo carga — 1 de cada 4 corriendo en paralelo. Ahora reintentan, como el click del día
en la v21.49. Medido después: **8 de 8 en paralelo**.

**Chequeo:** `node tests/ppp-tanda-cambiar-dia.cjs` — verificado que **falla (4) contra el
`index.html` anterior al candado**, o sea que no tapa nada.

## ⚠ REGLA (v24.32): lo que el `activate` del SW ESPERA puede dejar la pestaña MUDA

El `event.waitUntil()` de `activate` no termina hasta que se asienta lo que le pasaste, y la página
que todavía está booteando pasa sus `fetch` por ese Service Worker. **Un `await` adentro del
`waitUntil` que no resuelve deja el SW a medio activar y el hilo principal de la pestaña esperándolo
para siempre**: sin error, sin cartel, la app muda.

El que mordió: la recarga única de la v23.70 (`forzado-v2370`) hacía `await c.navigate(...)` **cliente
por cliente**. Si esa navegación no resuelve —red que no contesta, recurso abortado— se colgaba todo.
Hoy las navegaciones se disparan **sin esperarlas una por una** y el conjunto tiene un techo de 2 s:
la recarga sigue saliendo y `activate` no se puede colgar.

> **Al agregar algo al `waitUntil` de `install` o `activate`: o no se espera, o se espera con techo.**

⚠ **Lo cazó un test, no la lectura.** `tests/vendor-sin-cdn.cjs` corta toda salida a internet: la
página llegaba a `readyState = complete` y a los **~1,9 s** dejaba de responder — `page.evaluate` y
hasta un `Runtime.evaluate` de `1+1` por CDP se comían el timeout, mientras `Debugger.pause` seguía
entrando (o sea: el renderer vivo y el hilo trabado). Se aisló sirviendo el mismo `index.html` con el
`navigator.serviceWorker.register` neutralizado → **VIVO**; con el SW puesto y sin el `await` del
`navigate` → **VIVO**. Ese test es el centinela: no hay otro.

## ⚠⚠ REGLA (Luis, 2026-10-13, v29.95): un `onclick` del HTML SE RESUELVE CONTRA `window` — no contra el scope del script

**Luis, con la captura del cuadro «¿Quién sos?»:** *"aprieto luis y no entra"*.

El panel por ROL (v29.92) dibujaba sus botones con handlers **inline**
(`onclick="rolElegir('luis')"`), y todo ese bloque vive **adentro de la IIFE `initAuth`**
del segundo `<script>` de `index.html` (líneas ~62957-66056). Un handler inline **no ve el
scope del script: se resuelve contra `window`**, así que el click tiraba *"rolElegir is not
defined"* y **no pasaba nada** — ni un cartel, ni un error a la vista.

> **Si una función se usa en un `onclick` / `onchange` del HTML y se declaró dentro de esa
> IIFE, hay que exponerla: `window.laFuncion = laFuncion;`** Es el mismo pozo de `window.sb`
> (v23.98), y el archivo ya lo resuelve así en decenas de lugares (`window.pkFrenar`,
> `window.cobrosRenderTab`, `window.histReintentar`…).

| dónde vive la función | ¿hace falta exponerla? |
|---|---|
| el primer `<script>` (líneas 7081-62940), que **no** es IIFE | no: ya es global |
| un `.js` propio cargado como script clásico (`ads.js`, `cobranzas.js`…) | no, salvo que esté en su propia IIFE |
| **la IIFE `initAuth`** (segundo `<script>`) | **sí**, siempre |

Expuestas para el panel por rol: `rolElegir`, `rolPickerAbrir`, `GV_ROL_ITEMS` (las filas del
checklist llaman `GV_ROL_ITEMS[i].open()`).

⚠⚠ **UN CANDADO ESTÁTICO NO VE ESTE BUG**: el `onclick` está y la función está. La única forma
de medirlo es **clickear con la pantalla corriendo**. Lo sostiene
`tests/rol-panel-click.cjs`, que aprieta «Luis» de verdad y además barre **todo** `onclick` del
cuadro y del panel exigiendo que resuelva contra `window` (así un botón nuevo del bloque no
vuelve a nacer muerto). ⚠ Ese barrido lleva un guard de *"¿encontré al menos uno?"*: sin él daba
**verde con el bug puesto**, porque con el cuadro sin dibujar hay 0 onclicks y 0 faltantes.

**Barrido del 13/10 sobre toda la IIFE** (funciones declaradas ahí y usadas en un handler
inline sin exponer): **0 casos más**. El panel por rol era el único.

### ⚠ v30.03 (Luis, 13/10): el panel por rol es UNA LÍNEA con BADGE — el checklist se despliega

**Luis, con la captura:** *"esa visual es horrible … ajusta eso en un menu colapsable con un
badge. que el arreglo sea general y no solo para luis"*.

El panel se dibujaba abierto: ~560 px de alto empujando el panel de administración entero, con
«Hola, Luis» partido en dos renglones, el veredicto en prosa y un «cambiar» de una pantalla de
ancho. Es la regla de espacio del 28/09 y el punto 4 de GV-UI (*lo explicativo se pliega; ningún
bloque largo se dibuja abierto*).

| | |
|---|---|
| plegado (lo que se ve al entrar) | **44 px**: `▶ Luis · Administración general` + badge + `cambiar` |
| badge | **`3 para mirar`** (rojo) · **`✓ al día`** (verde) · **`sin contadores`** (gris). El color NUNCA va solo: lleva palabra (GV-UI 5) |
| desplegado | el checklist de siempre, 474 px |
| abierto/cerrado | `localStorage gv_rol_abierto`, por dispositivo. **Arranca plegado**: el dato es el badge |

⚠ **Vale para los CINCO roles y las tres áreas**, que es lo que pidió Luis: es el mismo render
(`rolPanelRender`), no hay nada propio de Luis. Lo mide el test sobre los 5.

⚠ **El `button{width:100%;padding:16px;font-size:22px}` global de la línea 26 también muerde acá**
(mismo pozo que el pop-up de Importados, v23.93): sin `#rolPanel button{width:auto}` el «cambiar»
sale de una pantalla de ancho. Y el reset se lleva puesto el ancho de la BARRA y de las FILAS, así
que las dos vuelven con `#rolPanel .rolp-bar, #rolPanel .rolp-row{width:100%}`.

⚠ **«cambiar» vive DENTRO de la barra que despliega**: se le pasa el evento
(`rolPickerAbrir(event)`, que corta la propagación). **No se escribe `event.stopPropagation()` en
el `onclick`**: ahí el identificador que se llama es un método, y el barrido genérico del test
—que exige que todo `onclick` resuelva contra `window`— lo marcaría como función faltante.

**Chequeo:** `node tests/rol-panel-click.cjs` — mide, con la pantalla corriendo y para los 5
roles, que arranque plegado en una línea, que el badge lleve palabra, que «cambiar» sea angosto y
que tocar la barra despliegue el checklist.

### ⚠ v30.04 (13/10): EL PASE `disenador-gvui` sobre el panel por rol

Se corrió el agente sobre la pantalla CORRIENDO (no leyendo el CSS) a 1280 y a 390 px, en los
tres estados del contador. Devolvió **5 ALTA · 6 MEDIA · 4 BAJA**; se aplicó todo:

| qué estaba mal, medido | cómo quedó |
|---|---|
| el ✓ verde `#16a34a` daba **3,15:1** y el `—` de «no pude leer» `#94a3b8` **2,45** (AA pide 4,5) | el PUNTO sigue en `--gv-muted` (es un ícono) y el NÚMERO va aparte: `--gv-ok` **4,68** · `--gv-error` **6,04** · `--gv-ink-2` **7,07** |
| el **DATO** del plegado (el badge) medía **12,5 px** contra el nombre —que es el RÓTULO— a 14 | badge **16 px** (`--gv-fs-lg`), nombre **12** (`--gv-fs-sm`): la jerarquía deja de estar al revés |
| «cambiar» era un `<span onclick>` **adentro del `<button>` de la barra**: **22 px** de alto, `tabIndex -1` y un lector leía la barra entera como un solo control | `<button>` hermano dentro de `.rolp-head`, **44 px**, alcanzable por teclado, y la barra con `aria-expanded` |
| **6 tamaños y 11 hex propios** con `gv-ui.css` ya cargado en `index.html:14` | 0 propios: todo sale de los tokens |
| el cuadro «¿Quién sos?» **no tenía salida** (ni ✕, ni backdrop, ni Escape) | cierra con Escape o tocando el fondo **sólo si ya hay alguien elegido**: en el primer ingreso sigue obligando a elegir |
| rótulos de hasta **7 palabras** que repetían el hint, y un 📥 en 1 de 8 | «Movimientos por resolver», «Ingresos a racks sin revisar», «Programados con cuarentena»; sin emoji |

⚠ **Y apareció uno que el pase no vio**, midiendo a 390 px: sin **`min-width:0`** en la barra y en
`.rolp-quien`, el contenido les pone un min-width implícito, no encogen, y **«cambiar» se salía
12 px del panel**, pegado al borde de la pantalla. Es el pozo clásico de un hijo de flex con texto.

⚠⚠ **Dos candados nuevos, y el segundo es el que importa:** el bloque **(g)** de
`tests/rol-panel-click.cjs` mide sobre la pantalla corriendo el **contraste calculado** de los tres
estados, la escala, la jerarquía badge > nombre, los 44 px y el desborde, **a 1280 y a 390**.
Verificado que falla contra el index anterior reproduciendo los números del pase (2,45 · 3,15 ·
13 px · 22 px · `tabIndex -1`).

> ⚠ **El helper de contraste va como FUNCIÓN, no como string en un template literal.** Ahí el `\d`
> del regex pierde la barra —en un template una escapada desconocida deja sólo la letra—, el match
> no devuelve nada y **TODO contraste sale 1:1**: el test queda verde con los colores mal puestos.
> Pasó en el primer intento y lo cazó que los 18 chequeos dieran exactamente «1:1».

### ⚠ v30.05 (Luis, 13/10): el rol de JUAN es la IMPRESIÓN, y el panel NO TOCA EL HELPER

**Luis:** *"agregale un usuario tambien a Juan. Necesita que la impresion automatica de notas de
picking/armado salga y nada más. fijate que esto no joda con el helper"*.

Área nueva **`impresion`** («Impresión de notas»), con **dos** ítems y nada más — Juan no ve la PPP,
ni compras, ni cobranzas:

| ítem | qué dice | abre |
|---|---|---|
| **Impresión automática** | si en ESTA PC el helper está conectado, contesta y la estación está prendida | ⚙️ Helper de impresión |
| **Hojas sin imprimir** | picking y armado pendientes de `colaImpFetch` (el facturado no es de Juan) | 📅 Cola por día |

> ## **El panel MIRA el helper; no lo prende, no lo apaga y no le pega a 127.0.0.1 de más.**

- No llama a `gvHelperConectar`, `gvHelperGuardar` ni `psSetAuto`: eso sigue siendo del pop-up de
  ⚙️ Configuración, donde conectar = esta PC imprime sola (v26.30).
- ⚠⚠ **Y sólo pinguea el loopback si el helper está CONECTADO en esa PC.** Desconectado, el
  navegador no sale a `127.0.0.1` — en un celular Chrome pediría permiso de red local para nada
  (regla v26.24). Es lo único que podía «joder con el helper» y es lo que mide el candado.
- Los ítems de Juan son **LOCALES** (`it.local`, se miden en el navegador) y no en `gv_rol_panel`.
  Por eso `rolPanelCargar` tiene ahora dos clases de ítem; **un área sin ítems remotos ni llama a la
  RPC**. Cada local resuelve por su cuenta y repinta: uno lento no traba a los otros, y una lectura
  rota deja «—», nunca «✓ al día».

**Chequeo:** `node tests/rol-panel-click.cjs`, bloque **(h)** — con el helper desconectado mide que
**no salga un solo request a 127.0.0.1**, que Juan vea sus 2 ítems y que `gv_helper_imp_v1` y
`ps_auto_virgilio` queden **sin tocar**; con el helper conectado y contestando, que sí lo pinguee y
marque ✓ sin apagarle nada. Verificado que falla sacando el guard: *«el panel le pegó a 127.0.0.1
con el helper DESCONECTADO»*.

### ⚠ v30.14 (Luis, 13/10): el rol de PAGOS — un deadline vencido tapa la pantalla, no cada remito

**Luis:** *"cuando uno se loguea a GV ahora pregunta quien es uno. Creale un usuario a Pagos"* y, sobre
Recepción de Mercadería: *"cuando se registra en el sistema corre un timmer. si en la misma hora al
siguiente día habil no se proceso (o se marco como no recibido) les tiene que saltar una alerta en el
planify a los de pagos (Mel, Nora y Pablo) y en GV si estan logueados como pagos de que tienen que
resolverlo en ese momento si o si (procesarlo o marcarlo como «No recibido»)"*.

> ## **Esto NO es volver al trigger de v18.81 (dado de baja a pedido del dueño).**
> Aquel avisaba a Pagos por CADA remito, al instante. Éste avisa **sólo si venció un plazo sin que
> nadie lo haya resuelto** — ni procesado ni marcado «No recibido». Son dos reglas distintas, no la
> misma reabierta: una es *"avisá siempre"*, la otra es *"avisá sólo si nadie hizo nada a tiempo"*.

| pieza | qué hace |
|---|---|
| área nueva **`pagos`** (`GV_SUP_ROLES.pagos`, `GV_AREA_NOMBRE`) | «Pagos», al lado de admin/ventas/impo/impresión |
| ítem **«Recepciones vencidas sin resolver»** (`GV_ROL_ITEMS`, áreas `admin`+`pagos`) | el mismo conteo que el cartel bloqueante; `gv_rol_panel` suma `recep_pagos_vencida` |
| **cartel bloqueante** (`pagosAlertaInit`/`_Check`/`_Render`/`_Stop`) | tapa toda la pantalla, **sin ✕ ni Escape**, sólo mientras el rol elegido sea Pagos; se arma al elegir el rol y se repite **cada 60 s**; se cae solo cuando la lista queda en 0 y se auto-apaga si deja de ser Pagos o deja de haber sesión de supervisor — no depende de que el logout de turno se acuerde de llamarlo |
| botón del cartel **«Ir a resolver ahora»** | `abrirRecepcionPagosVencidas()` → el deep-link que ya usa Planify, `window.recepcionAbrirPendientes()` |

**El deadline es "al siguiente día hábil, a la misma hora"**, no "24 h corridas": `gv_proximo_dia_habil_desde`
(nuevo, pisa `gv_es_dia_habil`) + la hora del `created_at` original. **Resuelto** = `Control_Modo_OP.estado <>
'pendiente'` (el «Enviar» final) **o** `gv_no_recibido_at` cargado (el botón «No recibido»): cualquiera de los
dos cierra la alerta.

**Base** (`gv_recepcion_pagos_vencida()` + `GV_Recepcion_Pagos_Alerta` + `gv_recepcion_pagos_alerta_tick()`,
cron cada 10 min jobid 159): crea **una** tarea de Planify `broadcast=true, department_id=6` por recepción
vencida nueva, y cierra (`done=true`) la de las que ya se resolvieron. **No hizo falta tocar Planify**: Mel
(Melany Pierola), Nora (Nora Heredia) y Pablo (Martos Pablo) son exactamente los activos del departamento 6
("Pagos"), así que el mecanismo de broadcast por sector que ya existe alcanza solo.

⚠ **El tick ya corrió contra datos reales al aplicar la migración** y encontró un caso genuino: Carriero,
remito 1751 (vencido). Creó la tarea de verdad — no es un simulacro, Mel/Nora/Pablo la ven la próxima vez que
abran Planify.

**Chequeo:** `node tests/rol-panel-click.cjs`, bloque **(i)** — el área dice "Pagos", el ítem marca el número
real (no "✓"), el cartel aparece con el dato mockeado y tiene botón, y se cae solo al resolverse **sin cambiar
de rol** (llamando a `pagosAlertaCheck()` directo, el mismo chequeo que corre solo cada minuto). ⚠ El mock
genérico `**/rest/v1/**` tiene que registrarse **ANTES** que los específicos de cada RPC: Playwright prueba
las rutas en el orden inverso al de registro (la última agregada va primero), así que un catch-all agregado
después tapa a los específicos.

⚠ Los objetos de la base, el centinela y los comentarios del código dicen **v30.14** (la versión con que se
aplicaron): es la llave de idempotencia, **no cambiarla**; la app salió en v30.19 porque otras sesiones se
adelantaron entre medio (dos veces: primero a v30.17, después a v30.18).

