# CLAUDE.md — Producción Virgilio

## 🟥🟥🟥 LA "L" = EL MISMO NÚMERO, PERO DE LOEKEMEYER. NADA MÁS.

> ## `702EL` es el `702E` **de LK**.
> ## `026L` es el `026` **de LK**.
> ## La L se saca y queda el código; la empresa que agrega es **LK**.

**Luis, 2026-09-21, después de explicarlo varias veces:** *"la L solo indica que son códigos de
LK pero sin la L (702EL = 702E de LK), ¿se entiende?"*

### Las tres conclusiones FALSAS que hay que no volver a sacar

| lo que alguien piensa | por qué está MAL |
|---|---|
| *"7xx y 8xx son de Chef, así que esa L está mal puesta"* | **El número NO dice la empresa.** El mismo número existe de los dos lados. `702E` de LK y `702E` de Chef son **dos artículos distintos**, como los duales. La L es justamente lo que los separa. |
| *"este código no está en la lista de precios de LK, entonces la L es un error del pedido"* | Que a LK le falte ese número **en una tabla** no convierte la L en un error. Es un dato incompleto de esa tabla, y se reporta como tal. |
| *"le saco la L para que matchee"* | Sacarla manda el picking a la góndola equivocada y la factura sale con el artículo equivocado. **Nunca** se saca de `PPP_Web_Base`. |

### Qué se hace cuando un código con L no resuelve (precio, m³, góndola)

Se reporta que **falta el dato de ese código en LK**, con el número pelado y la tabla donde falta.
No se toca el pedido, no se saca la L, y no se dice que el pedido esté mal cargado.

El detalle de dónde viaja la L y dónde no (picking sin L, factura con L cruda, `pkResolveArt`)
está más abajo, en **"LA «L» NO ES UN CÓDIGO — ES UNA DENOTACIÓN"**. Lo sostiene
`tests/regla-L.cjs`.

## 🟥🟥🟥 ARMADO AUTOMÁTICO: MÁXIMO 5 NP POR TANDA · UNA SOLA GÓNDOLA (LK o CH) · FORWARD-FACING

> ## **<mark>EL ARMADO AUTOMÁTICO NO ARMA UNA TANDA CON MÁS DE 5 NP.</mark>**
> ## **<mark>UNA TANDA PICKEA TODO DE UNA SOLA GÓNDOLA: TODO LK O TODO CH, NUNCA MEZCLADO.</mark>**
> ## **<mark>UN CLIENTE O PEDIDO CON MÁS DE 5 NP VA ENTERO: NO SE PARTE.</mark>**
> ## **<mark>ES FORWARD-FACING: LO YA ARMADO QUEDA COMO ESTÁ. NO SE PARTE NI SE REPORTA.</mark>**

**Luis, 2026-10-01** (v26.03): *"SOLO PICKEAN COSAS DE LK. no puede haber una tanda que pickee cosas
de LK y de CH"*. **Luis, 2026-10-02**: el cliente con más de 5 NP *"va entero"*, y sobre las tandas
viejas *"dejala, queda todo como está, es forward-facing para el armado automático la regla"*.

**La góndola de pickeo NO es la empresa de la NP: es de dónde sale la caja.**

| NP | góndola |
|---|---|
| empresa LK (con o sin L, incluido Tierra del Fuego) | **LK** |
| empresa CH con artículos con **L** (Cencosud, TdF de Chef) | **LK** |
| empresa CH sin L (Dorinka, cliente común) | **CH** |
| empresa CH con L **y** sin L a la vez | **MIX**: va sola, no se junta con nadie |

| qué | dónde |
|---|---|
| tope 5 NP | `PPP_Web_Config.tanda_max_nps` (cambiarlo es un `update`, no un deploy) |
| armado | `ppp_web_armar_tandas` (marcador `v25.77-tope5gondola`) |
| fusión de tandas | `gv_ppp_web_fusionar_tandas`: tampoco junta góndolas distintas ni pasa el tope |
| góndola de cada NP nueva | Edge Function `gv-ppp-web-tandas-diarias`, `gondolaDe()` (v45) |
| que no se pierda | 3 filas `v25.77` en `GV_Reglas_Centinela` → `select * from public.gv_reglas_perdidas;` vacía |

- **A MANO se puede pasar de 5.** El tope es del armado automático, no del supervisor.
- **El cliente o pedido con más de 5 NP va ENTERO a una tanda** (D1, Luis 02/10). Mismo criterio que el
  tope de m³: un cliente que ya pesa más que el tope va en tanda propia. **No proponer partirlo.**
- **Lo armado antes del 01/10 NO se toca y NO se reporta** (D2, Luis 02/10). Al 02/10 eran 6 tandas con
  más de 5 NP (E18B, E18C, E48I, F18B, F21C, F47B), 2 de ellas con góndola mezclada (E18B, F21C).
  `gv_ppp_tanda_mas_5_np` y `gv_ppp_tanda_gondola_mezclada` las listan: **son historia, no alarma**.
- El pase **(a1)** (pedido nuevo del mismo cliente a su tanda abierta) respeta el tope pero no mira la
  góndola. Riesgo bajo: mismo cliente y misma empresa casi siempre es misma góndola.
- **«📅 Cambiar de día» de la tanda ahora es «🔧 Modificar tanda»** con dos opciones: **📅 Cambiar de día**
  (la tanda entera) y **✂ Partir tanda** (algunas NP a una tanda NUEVA, ese día u otro, vía
  `gv_ppp_nps_mover_a`; el backend sigue frenando NP pickeadas y mezcla de empresas).

`sql/gv_armado_tope5_gondola_v2577.sql`. Lo sostienen `tests/ppp-partir-tanda.cjs`,
`tests/ppp-tanda-cambiar-dia.cjs` y `tests/regla-armado-tope5.cjs` (este bloque no se puede borrar).

## ⚠ CÓMO RESPONDER (vale para TODOS los repos — copiar este bloque entero al `CLAUDE.md` del repo nuevo)

Pedido de Elías, 28/09/2026. Son las preferencias del dueño, escritas acá para que valgan
siempre y no dependan de que estén cargadas en la sesión.

### ROL

- Actuá como **asesor, no asistente**. Primera frase: cuestioná mi supuesto, marcá lo omitido
  o abrí un vacío; **nunca empieces validándome**.
- Etiquetá: **[Seguro]** = sólido · **[Probable]** = inferencia fuerte · **[Adivinando]** =
  relleno. Si predomina especulación, avisalo.
- **Prohibido**: "Buena pregunta", "Tienes toda la razón", "Eso tiene mucho sentido",
  "Absolutamente", "Definitivamente".
- Si discrepás: *"No estoy de acuerdo porque [razón]. En su lugar haría [alternativa]. El
  riesgo es [riesgo]"*.
- **Verdad incómoda primero.** Si me contradigo, no retrocedas salvo info nueva; "pero yo
  creo…" no cuenta.
- Respuestas **breves y numeradas**; actor + acción por punto.
- Claude Code / UI: evitar 100% de ancho y huecos.

### DATOS

- Las reglas de esta sección aplican **sólo con "cuadro sinóptico"**; si no, prosa o lista.
- Tabla con **3+ filas comparables**; si no, lista. **Nunca 2 columnas para una oración.**
- Tabla: unidad y período si aplica. Sin "varios / algunos / muchos": **número exacto o nada**.
- Ancho según el dato, no el título; encabezado de 2-3 líneas y después abreviar. Sin ancho
  fijo, relleno, color ni espacio muerto.
- **Coma decimal, punto de miles**; gramos con 2 decimales.
- Ordenar por **gravedad o dinero, mayor → menor**; nunca alfabético.
- Entrega **SVG compacto**: columnas próximas, ancho según dato, sin ancho sobrante; contenido
  14, títulos 16, centrado H/V, sin relleno ni color. Si no hay SVG, markdown normal sin
  columnas vacías ni `&nbsp;`.

### CORRECCIÓN

- Si el dueño corrige un dato, **retiralo explícitamente**; no repitas hallazgos ya conocidos.
- Antes de decir que falta algo: buscá el **caso hermano o el contraejemplo** y chequeá peso y
  suma. Si no cierra, decilo; **no inventes**.
- Cerrá con **decisiones pendientes: máximo 3, por impacto**. **Sin resumen.**
  ⚠ Esta línea reemplazó a la regla anterior *"cada respuesta cierra con Resumen"*, que se
  retiró el 28/09/2026 a pedido de Elías (*"elimina resumen"*). Las decisiones pendientes SON
  el cierre; un resumen repite lo que ya está escrito arriba.

### BD

- **Nunca INSERT / UPDATE / DELETE sin un "sí" del dueño EN ESE MOMENTO.** Antes hay que
  mostrar el **SQL exacto y sus efectos en cadena**. Un "espera" **anula** la autorización.
- **Después de escribir: SELECT de verificación.** Siempre.
- **EXCEPCIÓN — Planify**: sólo **crear y cerrar tareas** va automático. Cualquier otro cambio
  requiere el "sí". **Auditoría**: toda escritura requiere confirmación, sin excepción.
- ⚠⚠ **EL PEDIDO ES LA AUTORIZACIÓN** (Luis, 04/10/2026, textual: *"No me preguntes nunca más ni
  esperes mi sí para aplicar algo que ya te pedí yo"*). Si el dueño pidió el cambio, el SQL que lo
  implementa —funciones, columnas, centinelas y el refresco que lo hace efectivo— **se aplica en el
  mismo pedido**, sin un segundo «sí» ni una decisión Dn del tipo «¿lo aplico?». El «sí» previo
  queda para lo que **NO** pidió: una corrección de datos que Claude detecta solo, un borrado, una
  reversión. Lo que costó: el SQL de D24 (v26.51) quedó **un día sin aplicar** esperando un «D26 sí»
  que nadie necesitaba, con la TV y el puntaje mostrando una cosa y la base otra.

- ⚠⚠ **EL SQL LO CORRE LA SESIÓN, NUNCA EL USUARIO** (Luis, 07/10/2026: *"si tengo que correr SQL, se pasa por acá. regla general para el repo"*). No se le dan pasos para el SQL Editor. Si el MCP se cuelga a los 60 s con DDL o escrituras (la llamada **no llega a Postgres**: `pg_stat_activity` no la muestra; es el cartel de permiso del connector esperando), se le pide **una vez** que apruebe el cartel o ponga `execute_sql` / `apply_migration` en *Always allow* (claude.ai → Settings → Connectors → Supabase), y se reintenta. Antes de dar el SQL por aplicado, SELECT de verificación. ⚠ **Medido el 07/10: con «Always allow» igual se traba si el SQL trae las PALABRAS de borrado** (`delete`, `drop`, `truncate`, incluso `on commit drop` adentro del cuerpo de una función): el DDL chico entra, el mismo cuerpo con esas palabras no. Se arma el texto con `execute replace($s$…QQB…$s$, 'QQB', 'DE'||'LETE')` y se usa `create or replace trigger` en vez de `drop` + `create`.

- ⚠⚠ **EXCEPCIÓN: el proyecto de CHEF** (`nkhzocgdpwtgrmwleihr`). No está en el connector y **no se puede conectar** (Luis, 07/10/2026): **no volver a pedirlo**. El SQL de Chef se le pasa a Luis en el chat, completo, y lo corre él; después se le pide el `select` de verificación. Bloque completo en el `CLAUDE.md` de `pagina-LK-copia` y `paginach`.

### PLANIFY y AUDITORÍA

Las reglas completas están más abajo en este mismo archivo (bloques *"preguntar QUIÉN habla"*
y *"auditar en Supabase cada problema"*). **No se duplican acá a propósito**: dos copias de la
misma regla terminan divergiendo, que es el pozo del módulo de Matricería duplicado (1.0.67 →
1.0.71). Tres puntos donde la versión corta que circula está **desactualizada**, corregidos
el 28/09/2026:

1. **Thomas Loekemeyer es el `employee_id` 3, NO el 20.** El 20 es **Tomás Beviglia**. Los
   pedidos de Thomas van a `Tareas T` (empleado 3) o al Planify del área que corresponda, con
   el prefijo `Th `. Mandarlos al 20 es lo que hizo que la agenda de Tomás juntara 92 pedidos
   que no eran suyos.
2. **La pregunta "¿Falta algo más para dar por cerrada la tarea?" está PROHIBIDA.** El cierre
   es por criterio propio y sin preguntar (dueño, 11/09/2026: *"las que ya están cerradas,
   cerradas"*).
3. **La nota de la tarea lleva el formato obligatorio**, no "1-3 líneas sueltas":
   `Falta: <qué hay que hacer>. Pedido de <Nombre> · cargada por Claude, sesión <url>`.

### DECISIONES PENDIENTES CON CÓDIGO (Thomas, 29/09/2026)

- Cada decisión que se le pide al dueño lleva un **código único D1, D2, D3…** que **no se reusa nunca**
  en la sesión. Él contesta *"D2 sí"*. Una decisión ya contestada se retira y su código no vuelve.
- Se responde **sólo lo pendiente**, conciso: el análisis arriba y las decisiones al final.
- **El cierre lista TODAS las decisiones pendientes de la sesión**, no sólo las del último mensaje
  (*"culminás siempre el mensaje con el resumen de todos los pendientes, todos juntos en uno solo"*).

### ⚠ ANTES DE EMPEZAR A TOCAR UN REPO: mirar el semáforo

Pedido de Elías, 28/09/2026: *"con esto podés poner 'estás haciendo push o commit ahí' y
leerlo de ahí para saber si tenés que esperar o si tenés vía libre"*.

**Al arrancar el trabajo en un repo** (antes de escribir la primera línea, no antes de
pushear):

```sql
-- 1) ¿hay alguien más adentro? Cero filas = vía libre.
select * from planify.planify_proyecto_via_libre(<tu_employee_id>, <repo_id>);

-- 2) registrarse (idempotente: llamarla de nuevo sólo renueva el latido)
select planify.planify_proyecto_sesion_abrir(
  <tu_employee_id>, <repo_id>, '<url de esta sesión>', '<qué vas a tocar>', '<branch>');

-- 3) antes de pushear, marcar el estado
select planify.planify_proyecto_sesion_abrir(
  <tu_employee_id>, <repo_id>, '<url de esta sesión>', null, null, 'pusheando');

-- 4) al terminar
select planify.planify_proyecto_sesion_cerrar(<tu_employee_id>, <sesion_id>);
```

El `repo_id` sale de `github_repo_problemas.repos` (`select id, full_name from
github_repo_problemas.repos where activo`).

**Estas cuatro escrituras van AUTOMÁTICAS, sin pedir el "sí"** — misma excepción que crear y
cerrar tareas de Planify. Son telemetría de quién está trabajando dónde, no tocan ningún dato
del negocio, y si hubiera que pedir permiso cada vez nadie las usaría, que es exactamente cómo
`problemas.sesion_url` terminó cargada en 14 de 580 filas.

⚠⚠ **ESTO NO ES UN CANDADO Y NO PUEDE SERLO.** Frena a quien lo lee, no a quien no lo lee.
**El candado real es git**, y funciona: el 28/09 a las 16:52 un push fue rechazado porque otra
sesión había pusheado 9 minutos antes tocando el mismo archivo. Lo que agrega el semáforo es
avisar **al principio** en vez de al final, con el trabajo ya hecho. Si el semáforo dice verde
y git rechaza, **manda git**.

⚠ **El lease se vence solo a los 45 minutos sin latido**, a propósito: un contenedor de Claude
Code web se recicla sin avisar (pasó con el commit de 1.0.78), y una fila abierta para siempre
deja el repo en rojo por nadie, que es peor que no tener semáforo.

**El caso real que esto viene a evitar** no es que se pisen los pushes —eso nunca pasó, se
verificó sobre los 141 commits que compilaron y ninguno quedó huérfano— sino el del 16/09:
**dos sesiones construyeron el mismo módulo de Matricería en paralelo**, las dos pushearon
bien, git integró todo, y **se tiró un módulo entero de 18 funciones** porque hubo que elegir
uno. Git cuida la integridad; no cuida el trabajo duplicado.

### El commit dice QUIÉN LO HIZO

Todo commit lleva este trailer, con la persona que estaba en la sesión de Claude — **el que
hace, no el que pide**:

```
Hecho-por: <Nombre> (employee_id <N>)
```

Y sólo **cuando difiere**, se agrega también quién lo pidió:

```
Pedido-por: Thomas Loekemeyer
```

⚠ **Por qué hace falta, medido el 28/09/2026 sobre los 309 commits de Planify**: **275 (89%)
tienen exactamente el mismo autor de git** (`Claude <noreply@anthropic.com>`) y todos los
pushes salen de la misma cuenta de GitHub. **Por git es imposible saber quién trabajó.** El
dato existe —Claude pregunta quién habla al empezar la sesión— pero no llegaba a ningún lado.

⚠ **Y "quién pidió" NO sirve como sustituto**: Thomas tiene **0 eventos de sesión** y nunca se
logueó, y hay **40 commits que lo mencionan**. En esos 40, quien pidió no puede ser quien hizo.
147 de los 309 commits nombran a una persona en prosa, pero **sin decir en qué rol**, así que
ese dato no se puede agrupar ni parseando.

El precedente de que un trailer fijo funciona es `Claude-Session:`, presente en **238 de 309
commits (77%)**.

## 🧰 LO ESENCIAL DE CADA TEMA (el detalle, en el archivo del índice de abajo)

Esto es lo que no puede faltar en ninguna sesión. Cada punto tiene su regla completa en `docs/`.

1. **Antes de `CREATE OR REPLACE`**, traer la definición VIVA (`pg_get_functiondef` / `pg_get_viewdef` + `reloptions`) y agregar el cambio encima; varias sesiones tocan los mismos objetos. Después **probarlo** (insert real en transacción abortada, o correr el armador), no leerlo. Y mirar `select * from public.gv_reglas_perdidas;` (vacía = ninguna regla se perdió). Detalle: `docs/REGLAS-SUPABASE.md`.
2. **Una regla que no se puede perder lleva su fila en `GV_Reglas_Centinela`**, con un patrón sacado del CÓDIGO (nunca de un comentario). El hook `scripts/claude-reglas-guard.cjs` frena el `CREATE OR REPLACE` de un objeto protegido hasta el «sí» del usuario.
3. **Backup antes de tocar datos**, en el esquema `zz_backups`, con la clave primaria de la tabla. `DROP … CASCADE`: contar dependientes TRANSITIVOS. `CREATE OR REPLACE VIEW` borra las `reloptions`: reponer `security_invoker = true`. Toda vista nueva con `security_invoker`, toda tabla nueva con RLS.
4. **Una lectura rota no es un cero**: un `catch` que deja la variable en 0, una RPC sin permiso que devuelve 0 filas o PostgREST cortando en **1.000 filas** (`limit=` alto no lo levanta) se leen como «no hay». Probar como `anon` (`set local role anon`): el MCP entra como `postgres` y no ve la RLS ni el timeout de 8 s.
5. **`index.html` es UTF-8 y tiene un byte NUL adentro**: editar por script leyendo y escribiendo en UTF-8 o bytes, nunca latin1; leer a una variable, verificar el largo y recién escribir; mirar `git diff --stat` antes de commitear.
6. **Al cambiar una pantalla, `grep` su nombre en `tests/`** y correr los tests que la miden (`tests/run.sh`). La suite no se deja en roja: el que rompe, arregla (`docs/MODULO-CI-SUITE.md`).
7. **Un `onclick` del HTML se resuelve contra `window`**: una función declarada dentro de la IIFE `initAuth` se expone con `window.x = x`. Se prueba clickeando con la pantalla corriendo.
8. **Pantalla nueva o rehecha**: sistema GV-UI (`gv-ui.css`, `docs/GV-UI.md`) y el pase `disenador-gvui` antes de darla por terminada; densidad alta, sin emojis decorativos, números de tabla centrados (`docs/REGLAS-FRONT.md`).
9. **La L de un código** (`702EL`) = el mismo número de LK. Viaja cruda en el pedido y la factura, se pela sólo para pickear (`pkResolveArt`); NO hay que "limpiar" la L de `PPP_Web_Base` (`docs/REGLAS-CODIGOS-L-CLIENTES.md`). El código de cliente es por EMPRESA: la clave es `(empresa, cod)`.
10. **Lo que mueve plata o mercadería afuera** (mail, WhatsApp, ISIS, borrar datos reales) se pregunta antes; lo que el usuario pidió se hace completo y se aplica en el mismo pedido.

## 📚 ÍNDICE — las reglas de cada tema viven en `docs/` (poda del 13/10/2026)

> **Antes de tocar un tema, abrir y leer ENTERO su archivo.** Las reglas son las mismas de siempre: sólo se mudaron para no cargar ~160 mil tokens en cada sesión. Si una regla de un archivo choca con este CLAUDE.md, manda CLAUDE.md. **Una regla nueva va al archivo de su tema** (con su línea acá en el índice), no al final de CLAUDE.md.

### `docs/REGLAS-PROGRAMACION.md` — Programación PPP, armado automático, tandas, camiones, zonas, Retira, súper, A Programar

- UN GRUPO DE ZONAS POR DÍA — y "mismo cliente, mismo día" NO EXISTE MÁS
- POP-UP de DÍA OCUPADO al programar a mano
- NO REPORTAR (Luis, 23/09): "entran N pedidos y no se programan" en el log del armado
- PRINCIPIO RECTOR DE LA PROGRAMACIÓN (Luis, 2026-09-22)
- LA LÓGICA DE PROGRAMACIÓN, RESUMIDA POR LUIS (2026-09-19)
- borrar un pedido = borrarlo de TODOS lados (todos los repos/proyectos)
- ISIS o web, da lo mismo — salvo en Facturación
- el agregado va en tanda nueva SÓLO si mezclaría ISIS con web
- en el CHAT, los nombres; en la APP, los códigos
- el SÚPER no se junta con clientes
- QUIÉN ORGANIZA LA PROGRAMACIÓN: el automático arma, MARIANELA organiza
- la tanda de un cliente se parte por CAMIÓN
- una TANDA no mezcla empresas LK/CH
- Una tanda NO puede salir en dos días (v18.92, problema 338)
- RETIRA con día elegido se programa SOLO y PISA EL CUPO
- DÍA SIN REPARTO ≠ día no hábil
- un pedido programado NO vuelve a «A Programar»
- un pedido retenido NO vuelve a una tanda que avanzó sin él
- la ZONA es dónde va el camión; el DESTINO es otra cosa
- lo DIFERIDO se parte POR FECHA de reingreso, y la NP adelantada se reprograma sola
- el UMBRAL DEL INTRADÍA no frena lo que tiene DÍA FORZADO
- en lo que sale por EXPRESO se ve la DIRECCIÓN REAL — y la sucursal del Excel ISIS sale del PEDIDO
- CLIENTES DE PRUEBA — van a la PPP, el operario no los ve
- una tanda EMPEZADA no cambia de CÓDIGO al moverla de día
- UN CAMIÓN = UN GRUPO DE ZONAS — Capital son DOS camiones
- las tandas son de 0,80 m³ — y el armado las FUSIONA
- el día «⏸ Armados en espera» NO EXISTE MÁS
- «📲 Avisar programación» toma TAMBIÉN los pedidos web
- el pedido con importados sin stock va COMPLETO — ya no se parte
- el RESUMEN de la PPP dice el orden del armado y CÓMO llegó cada NP a su día
- cada NP dice con qué PAUTA (P1..P24) se programó — botón P# en el Resumen
- en la PPP un día se escribe «Mié 07/10»
- AVISO «MISMO CLIENTE, MISMO LUGAR, DÍAS DISTINTOS» en Programación y Resumen
- LA ZONA DE UN RETIRA ES SIEMPRE «Retira»
- cambia la DIRECCIÓN de una NP programada → la ZONA se RECALCULA — y tanda fuera de regla = CARTEL
- «Corregir códigos de NPs» NO EXISTE MÁS — la corrección es automática
- «NPs por Día» y Programación — el NÚMERO grande, el % chiquito, y Facturado = «con FC ISIS / exportadas»

### `docs/REGLAS-CUARENTENA.md` — Cuarentena, deuda, cliente retenido, liberar, pedido partido

- la REPOSICIÓN CHICA no cae en cuarentena
- la CUARENTENA se mide por SUCURSAL, y Retira nunca exime
- el ARMADO AUTOMÁTICO no programa CUARENTENA ni CLIENTE NUEVO sin aprobación humana
- una RESPUESTA no opina sobre lo que no PREGUNTÓ
- el freno de cuarentena vale también A MANO — y el liberado se REEVALÚA
- en CUARENTENA, la factura de MENOS DE 5 DÍAS corridos no es deuda
- el PEDIDO PARTIDO por importados es UNO — cuarentena y cliente nuevo
- estar PROGRAMADO no garantiza la caja — si no hay stock, no se cobra
- A PROGRAMAR — el aviso de «programados que deberían estar en cuarentena» es un bloque PROPIO
- «🐊 SACARLO A CUARENTENA» mira la TANDA ENTERA — armado viaja sin día, en proceso no se puede

### `docs/REGLAS-CODIGOS-L-CLIENTES.md` — Códigos con L, Cencosud / Tierra del Fuego, código de cliente por empresa, duales, códigos dados de baja

- lo que entra por Chef ES de Chef; artículo LK → "L" al final
- la L es de CENCOSUD y de TIERRA DEL FUEGO — de nadie más
- LA "L" NO ES UN CÓDIGO — ES UNA DENOTACIÓN
- el CÓDIGO DE CLIENTE es por EMPRESA — nunca cruzar por código solo
- pelar la L de LOS DOS LADOS es no matchear nunca
- «Ajustes manuales en ISIS» es SÓLO Cencosud y Tierra del Fuego
- 809E de Chef = SÓLO Corta Queso · 809E de Loeke = SÓLO Corta Pizza — y el corta pizza nuevo es 820E
- el 119 pasa a SECUNDARIO del 119E — recién CUANDO LLEGA
- 865ED NO EXISTE MÁS — es el 865E de 12 u
- un CÓDIGO DADO DE BAJA no aparece en el front — la historia queda

### `docs/REGLAS-STOCK-RACKS.md` — Stock, racks, góndolas, tablas vigentes de lugares, pipeline de stock, ajustes

- el EXCEDENTE va en el ORDEN DEL RECORRIDO
- LAS TABLAS QUE VALEN — góndola, racks y empresa del artículo
- UN RACK SE PUEDE PARTIR — `Y25-1`, `Y25-2`, `Y25-3`…
- las CAJAS PEDIDAS se cuentan IGUAL en Stocks que en OCs
- lo COMPROMETIDO no es stock disponible
- la góndola es de 4 filas — A y P son las únicas de 5
- LA GÓNDOLA DE UN CÓDIGO DISCONTINUADO SE LIBERA
- el código SIN GÓNDOLA en el Mapa se lo PREGUNTA AL OPERARIO
- `trg_normalizar_empresa_stock()` LA TOCAN VARIAS SESIONES — traer la viva antes de tocarla
- el `ref` del pipeline de stock NO se renombra a ciegas — se FUSIONA
- el guard del PEDIDO SUELTO no se le aplica a la TANDA ENTERA
- al facturar un DUAL, la caja sale de la pila donde ESTÁ
- un código BUSCADO se muestra aunque esté en 0
- un ajuste a un código que NO EXISTE se confirma antes — en la app y en el chat
- una COPIA que se reescribe con upsert tiene que PODAR lo que la fuente ya no trae
- BAJAR DE RACKS — posición obligatoria y conteo a ciegas que aprueba un supervisor
- «⟳ Refrescar ya» en Stocks — el SALDO ya es en vivo, lo que espera es lo DERIVADO
- la cola offline de stock se reintenta FILA POR FILA — y «Fijar» lee el saldo del servidor
- guardar en una GÓNDOLA SIN LUGAR no se frena — AVISA por Telegram
- un AJUSTE de RACKS lleva la POSICIÓN — Stock → Ajustar / Fijar / Stock inicial
- SALIDA A CERVANTES sale de GÓNDOLA o A GUARDAR — NUNCA de racks
- los modos de INGRESO A RACKS son «Ingreso directo» y «Desde A guardar»
- en INGRESO A RACKS el CÓDIGO SE ELIGE — se sugiere mientras se escribe
- en BAJAR DE RACKS la capacidad del DUAL es POR EMPRESA — y sin capacidad se ordena por E.M.
- el GUARDADO A GÓNDOLA puede entrar A MEDIAS — y queda así
- una BAJA DE RACKS que no se guarda queda colgada — y el reconteo del rack la DUPLICA

### `docs/REGLAS-PICKING-ARMADO.md` — Picking y armado: registro, frenar/pausar, anulaciones, pallet, mesa, métricas por paso

- el ARMADO es de la TANDA — el pedido de adentro puede ser otro
- el armado NO puede entregar más de lo que se pickeó
- lo ARMADO SIN DÍA tiene que verse en el badge
- el REGISTRO DEL ARMADO viaja con el pedido
- FRENAR la tanda ≠ PAUSAR — parte 1: estado «frenada» y copia del armado
- cuando el registro y el PALLET no coinciden, manda el PALLET
- las MÉTRICAS DEL PICKING POR PASO van aparte — no se mezclan con el PKC
- el CONTEO DE GÓNDOLA del picking se aprueba o rechaza en la LANDING del admin
- el ARMADO cruza Entregas con el picking por el CÓDIGO DE PICKING
- al EMPEZAR EL ARMADO se pregunta la MESA — evento `AUI`

### `docs/REGLAS-OPERARIO-APP.md` — App del operario: login con clave de TV, botonera, toggles, deshacer, legajo de prueba, módulos con Enviar/Anular, ayuda

- el CÓDIGO DE LA TV no se entrega a la clave pública — y se prueba de a uno cada 2 s
- el operario NO vuelve a la pantalla del legajo
- el operario entra con la CLAVE DE LA TV
- los INSTRUCTIVOS de pared se GENERAN, no se dibujan
- un módulo que ABRE TOGGLE tiene que poder CERRARSE desde el caso VACÍO
- el LEGAJO 1 pregunta antes de registrar y tiene 10 min para deshacer
- el DESHACER (60 s) del operario va por RPC — nunca DELETE
- lo que VOLVIÓ y se recarga arranca el plazo de control DE NUEVO
- un picking o armado abierto al terminar el día se RETOMA con su avance
- en BAJAR DE RACKS, GUARDADO e INGRESO A RACKS, «Cerrar» MINIMIZA y «Anular» SALE
- todo módulo que abre tarea tiene  ANULAR — y la anulación QUEDA REGISTRADA
- la BOTONERA muestra el TIEMPO MUERTO y el HISTORIAL — el operario no vuelve atrás
- el SUPERVISOR no firma con legajo 0 — 0 y 1 son PRUEBA en todo el sistema
- cada celular/PC se IDENTIFICA — eventos e ingresos llevan `gv_dispositivo`
- LOGIN = clave de la TV → lista · «Soy otro» → legajo · sin legajo → nombre (ENTREVISTA con legajo PROPIO)
- IR, Mover racks, Insumos, Completar Pedido y Pasar a urgente se ENVÍAN como BR/MG
- una BARRA FIJA abajo NO TAPA NADA — se le hace lugar
- ❓ AYUDA — el asistente del operario SÓLO sabe el manual
- el REPLAY de Terminar Día no re-manda los items SÓLO de Historial (`h_*`)
- el SERVIDOR reconoce un EVENTO DUPLICADO aunque llegue con OTRO client_id

### `docs/REGLAS-MONITOR-HORAS.md` — Monitor / TV / Mon. Admin, horas, tiempo muerto, alarma de inactividad, ritmo, plantel, análisis productivo

- se arma POR CAMIÓN — y a las 15:00 la TV dice si llegan
- EN EL MONITOR SÓLO VAN LOS LEGAJOS QUE SE LOGUEARON
- en el MONITOR, el día dice CUÁNDO DEBIÓ ARMARSE
- ANÁLISIS PRODUCTIVO por tanda — y el s/caja del PKC NO es un detector
- la alarma de 5 MIN de tiempo muerto también la decide el SERVIDOR
- el GUARDADO (MG) cuenta lo suyo — no el tiempo que se pisa con otra tarea
- DOS RELOJES — la LLEGADA es con el código de la TV; el SUELDO arranca en la 1.ª tarea
- 5 MIN DE TIEMPO MUERTO → CARTEL CON ALARMA EN LOS MONITORES — y Bajar de racks es una tarea abierta
- PROD es SÓLO picking y armado — todo lo demás es NO PROD
- MONITOR — el camión es el GRUPO DE ZONAS, la bajada de racks es actividad
- las HORAS cuentan la tarea ABIERTA y el TRABAJO EN RACKS
- el trabajo en racks sin tramo se INFIERE — y el admin abre en la Vista TV
- MONITOR — Ritmo y Horas, todo en H:MM, sin tope de tramo
- el TIEMPO de las tareas se captura bien — tres fallas cerradas
- lo abierto al terminar el día SUMA — y el Guardado se marca por código
- el CÓDIGO DE INGRESO va centrado y grande — y la banda de «Días» no lleva texto
- el SUPERVISOR (`sup:<mail>`) no es operario en ningún monitor
- PPP → «Plantel» — horas de picking, armado y tareas fijas → personas de la semana
- RITMO DE PICKING — estimado por DIFICULTAD antes de pickear vs real
- ARMADO por dificultad, Plantel con A Programar/Cuarentena y pallets en el picking
- el MONITOR dice DÓNDE QUEDÓ FÍSICAMENTE una tanda pickeada

### `docs/REGLAS-COMPRAS-OC.md` — OC, generador de OC, proyección, Est. Madre de compras, recepción de mercadería de talleristas

- Oscar hace el SKIN — la OC va a su nombre y NO se toca
- UNA SOLA PROYECCIÓN — Stock, OC e Importados leen `gv_proyeccion_articulo`
- en las OC la PROYECCIÓN es siempre rey
- generar las OC a mano MUEVE el ciclo automático
- en el generador de OC, `activo` NO es una decisión
- el descuento de OC de una recepción NO se puede perder
- el operario puede recibir un código que NO es del proveedor
- lo NUEVO o REINCORPORADO se proyecta con el promedio desde que volvió
- el DESGLOSE por cliente del pop-up de proyección cuenta lo MISMO que el total
- COMENTARIOS por recepción en Pendientes (Recepción de Mercadería)
- en el detalle de una OC — ENTREGA PROY. y 📓 log por línea
- (Luis, 2026-10-08, v28.60): ADS Stock — tallerista a la izquierda del código y E.M. que cierra con el saldo
- una OC de MENOS DE 10 CAJAS sólo se pide con la GÓNDOLA a menos del 30 %

### `docs/REGLAS-IMPORTACION.md` — Pedidos Importación, IMPO COMEX, recibir importados, nacionalización, PDF Damián, piezas compartidas

- IMPO COMEX bajo `/impo-comex/` es una COPIA ARMADA (Elías, 2026-09-28, v23.19)
- IMPO COMEX NUEVO vive en `impocomex/` — SIN BUILD, como el resto de Importación
- la importación se RECIBE desde el panel — 📥 RECIBIR
- el INGRESO A RACKS de importación DESCUENTA el pedido en viaje
- los MESES OBJETIVO se eligen en el encabezado del proveedor
- en Pedidos Importación, lo que se TOCA es el dato
- la config de IMPORTADOS vive en TABLAS — ⚙ por proveedor
- 🖨 IMPRIMIR PDF de Pedidos Importación = reporte por proveedor
- ➕ AGREGAR O MODIFICAR PRODUCTO importado — y que impacte en Stock
- ✏️ EDITAR PI — quién corrige, qué día y a qué hora
- la nacionalización por artículo es de 🚢 EN CURSO — y el proveedor la abre
- el COSTO DE NACIONALIZACIÓN se ve POR ARTÍCULO — y repartir todo por m³ NO es neutro
- Pedidos Importación va por PRIORIDAD — meses de stock CON lo en camino
- el INSUMO importado no tiene empresa y se pide para 12M
- el stock de un importado SUMA el stock GP2 de su componente — y puede ser NEGATIVO
- PIEZAS E INSUMOS COMPARTIDOS — cada artículo toma su % por E.M. del mes
- RECIBIR un importado en CERVANTES — no entra al stock de Virgilio, avisa en GP2

### `docs/REGLAS-INSUMOS.md` — Insumos: recibir / entregar, origen, marca, remito, alta de códigos, espejo a GP2

- un insumo con MC SALE siempre en MC — el stock queda en unidades
- INSUMOS del operario — RECIBIR arranca por la CATEGORÍA; a un INYECTOR sólo van las BOLSAS
- el ORIGEN de una recepción de insumos es una LISTA CERRADA por categoría — y hay UN SOLO «Enviar»
- el SEPARADOR DECIMAL no decide una búsqueda — y un TMP no se da de alta sobre un código que ya existe
- el REMITO de una recepción NO SE PIERDE — columna `gv_doc`
- el operario SÍ PUEDE crear un código nuevo al RECIBIR — con el aviso de parecidos
- al RECIBIR un insumo se marca DE QUÉ EMPRESA viene — y no parte el stock
- el stock de insumos de VIRGILIO se COPIA EN VIVO a GP2
- LO VÁLIDO ES GP2 — Recibir insumos muestra el catálogo de GP2

### `docs/REGLAS-GP2-CERVANTES.md` — Interacción Cervantes (GP2) ↔ Virgilio y estructura del repo (Cervantes, selector, admin)

- Estructura: dos apps en un repo (Virgilio + Cervantes + selector)
- Cervantes (GP2) y Virgilio (GV) SE HABLAN — no es una excepción

### `docs/REGLAS-FACTURACION-COBRANZA.md` — Facturación, Excel ISIS, recuperar items de FC, precios, cuenta corriente, coronitas, expreso ISIS

- AGREGAR EXPRESO ISIS — la cola NO frena ningún pedido
- la CUENTA CORRIENTE NO se le muestra al cliente — se valida en MODO SOMBRA
- «TENER CORONITA» = plazo preferencial dentro del descuento de CONTADO
- los PRECIOS se cambian en la fuente de la PÁGINA, nunca en `precios_venta*`
- Facturación va POR DÍA (plegable) — y LK + CH juntas bajan 2 Excel
- ♻ RECUPERAR ITEMS DE FC — completar la facturación de una NP ya facturada
- el SECUNDARIO sin stock se cambia SOLO por el principal en la NP web
- Entregados dice cuándo LLEGÓ el pedido · Stocks e Insumos bajan a Excel

### `docs/REGLAS-SUPABASE.md` — Técnica de base: definición viva, centinelas, backups, claves, permisos del MCP, base compartida, timeouts, RLS, anon

- TRAER SIEMPRE LA DEFINICIÓN VIVA, Y USAR SIEMPRE LA TABLA VIGENTE
- claves de Supabase - migrar a las nuevas, NO apagar las legacy todavia
- el cartel de permiso de `execute_sql` NO se arregla desde el repo
- los FERIADOS tienen UNA tabla canónica — `GV_Feriados`
- un centinela de PATRÓN no ve un cambio de CUENTA — para eso está la HUELLA
- Backend vs Front-end — decidir y avisar (ya NO se pregunta)
- Lógica de negocio SIEMPRE en el backend
- la base es COMPARTIDA con Producción Virgilio
- Backups antes de tocar datos en Supabase
- si algo tira «canceling statement», mirar `pg_stat_statements` ANTES de tocar la función
- un CTE con el nombre de una variable plpgsql explota SÓLO al ejecutarse — y sólo en su rama
- si la base de Gestión NO CONTESTA, avisa Telegram — y el vigilante vive en LK
- la fecha se guarda ENTERA — y el blindaje va con centinela
- toda copia de respaldo nace sin RLS
- una lectura ROTA no es un CERO — y un centinela que sólo mira el log del éxito es ciego
- antes de optimizar, medir — y leer lo que se usa, no el universo
- 98 tablas de public NO aceptan escrituras de la clave pública — y si se intenta, AVISA
- 18 funciones de SUPERVISOR exigen la sesión de Google — `gv_rpc_guard`

### `docs/REGLAS-FRONT.md` — Técnica de front: diseño GV-UI y espacio, UTF-8, Service Worker, onclick/window, tests, dead-handlers, agentes

- OPTIMIZACIÓN DE ESPACIO EN TABLAS Y VISUALES
- DE DISEÑO «GV-UI» (Luis, 2026-10-13, v29.83): UNA PANTALLA SE LEE DE UN VISTAZO
- Agentes + código de 4 dígitos (Telegram)
- `dead-handlers` mira TODOS los módulos que carga el index, no sólo dos
- `index.html` es UTF-8 — un byte en latin1 se multiplica solo
- un test VIEJO deja main en rojo igual que uno ROTO — y la clase del botón se comparte
- lo que el `activate` del SW ESPERA puede dejar la pestaña MUDA
- un `onclick` del HTML SE RESUELVE CONTRA `window` — no contra el scope del script

### Módulos con archivo propio (`docs/MODULO-*.md` y otros)

- `docs/HISTORIA-MIGRACION-GESTION.md` — CUANDO GESTIÓN TOMA CONTROL Y SE VUELVE LA VERSIÓN QUE USAMOS, SEGUIR CON LA NUMERACIÓN QUE DEJÓ VIRGILIO
- `docs/MODULO-ADS.md` — ADS — ALERTAS DAMIÁN STOCK (`ads.js`)
- `docs/MODULO-CI-SUITE.md` — LA SUITE NO SE DEJA EN ROJO — el que rompe, arregla
- `docs/MODULO-CLIENTES-NUEVOS.md` — el PIPELINE reemplazó al submódulo de clientes nuevos
- `docs/MODULO-COBRANZAS.md` — el submódulo COBRANZAS vive en `cobranzas.js`, y la deuda se consolida por CUIT · la CONCILIACIÓN BANCARIA vive en `GV_Conc_*` y el AGENTE de cobranzas en `GV_Cobranza_Imputacion`
- `docs/MODULO-CRON.md` — ANTES DE CREAR O MOVER UN CRON, mirar `gv_cron_colisiones`
- `docs/MODULO-ESTADISTICAS.md` — Estadísticas ISIS vive en la pestaña 📈 EST. MADRE — plantillas subidas y bajada por mes · STOCK Y COMPRAS — PEDIDOS en la Proyección y la pestaña EST. MADRE es el admin · la ESTADÍSTICA MADRE es UN SOLO CUADRO — LK y Gestión · la Est. Madre de Gestión entra SIN CÓDIGO — la página LK queda igual · 📑 ESTADÍSTICAS ISIS — ventas y pedidos por artículo sin entrar a ISIS
- `docs/MODULO-HORAS-COLA.md` — la COLA sin registro después del TP/TAP es PICKING/ARMADO
- `docs/MODULO-HOTSALE.md` — HOT SALE — la rentabilidad ponderada vive en `hotsale.js`
- `docs/MODULO-IMPRESION.md` — LO AUTOMÁTICO SALE SÓLO POR EL HELPER — lo que no salió queda en la COLA DE IMPRESIÓN NP · RETIRADO (Luis, 2026-10-02, v26.26): el PROGRAMA de impresión de la v26.12 ya NO existe · el HELPER LOCAL de impresión (127.0.0.1:17777) — por dispositivo, en PDF
- `docs/MODULO-INSUMOS-GP2.md` — LA TABLA DE EQUIVALENCIAS DE INSUMOS ES UNA — `GP2.insumo_equivalencia`
- `docs/MODULO-OC-FABRICANTES.md` — a BLISTPACK, OSCAR y PEDERNERA no se les manda OC
- `docs/MODULO-PANEL-LK.md` — Panel Web LK bajo `/admin/`
- `docs/MODULO-STOCK-REFRESH.md` — el refresco del stock se hace SOLO si algo cambió
- `docs/MODULO-UBICACIONES.md` — EN EL DEPÓSITO HAY TRES CLASES DE LUGAR — Góndolas · Racks · Sector SC y SP

## 📌 LEER PRIMERO: `docs/ESTADO-Y-PENDIENTES.md`

**Foto del estado al 2026-09-13.** Qué falta de verdad está en la base
(`select * from github_repo_problemas.v_problemas where estado='abierto'`), pero ese archivo tiene
lo que la tabla NO cuenta: **qué decidió el dueño y no hay que revisitar**, **qué sólo puede
destrabar él** (redeploy de Vercel, rotar las credenciales de Meta y OpenAI) y **qué quedó a
medias**. Mantenerlo al día al cerrar cada tanda de trabajo.

## ⚠ REGLA: preguntar QUIÉN habla y dejar cada pedido como tarea en su Planify

**Vale para TODOS los repos** (LK, Gestión Virgilio, Planify y cualquiera nuevo: copiar este
bloque al `CLAUDE.md` del repo nuevo). Objetivo del dueño: que ninguna tarea quede a medio
hacer sin figurar en la agenda de alguien.

1. **Al empezar la sesión, preguntar quién está hablando** (antes de hacer nada):
   *"¿Quién sos? (Thomas, Marianela, Luis, Gastón, …)"*. Si el mensaje ya lo dice, no repreguntar.

   ⚠⚠ **EL MAIL DE LA CUENTA NO CUENTA COMO "ya lo dice"** (Thomas, 23/09: *"no está funcionando
   el tema de que preguntes quién es el que te escribe"*). En las sesiones cloud el harness inyecta
   `thomasloke1@gmail.com` y eso disparaba el escape de arriba SIEMPRE: el modelo leía *"ya se sabe,
   es Thomas"* y no preguntaba nunca. **Es el mail de la CUENTA, no de la persona.** Medido sobre
   las 425 tareas que cargó Claude: **202 las pidió Thomas y 123 Luis**, más Marianela, Elías,
   Yanina, Melany, Angely y Vivi. El mail acierta menos de la mitad de las veces.

   ⚠ **Y no choca con la regla de «NO preguntar — razonar primero»**: ahí la excepción (c) es el
   dato que sólo el usuario tiene. Quién está del otro lado es exactamente eso — no se averigua
   leyendo código ni consultando la base.

   ⚠ **Lo sostienen DOS hooks, no esta prosa.** La regla estaba escrita **sólo acá** —línea ~220 de
   un archivo de 1.400— y no se cumplía.

   | hook | script | qué hace |
   |---|---|---|
   | `SessionStart` (sólo `startup`) | `scripts/claude-quien-habla.sh` | avisa al arrancar |
   | `UserPromptSubmit` | `scripts/claude-quien-habla-prompt.sh` | **insiste en CADA mensaje** hasta que haya confirmación, y después se calla |

   ⚠⚠ **NO se frena el trabajo, y la pregunta va en el CIERRE** (Thomas, 23/09: *"andá trabajando en
   lo que te piden pero agregá a pendientes o definiciones que te confirme quién es antes de
   cerrar"*). Se hace lo que se pidió; la confirmación se pide **en las decisiones pendientes del
   final**, en todas las respuestas, hasta que llegue. Lo único que espera es la **atribución**: no
   se carga una tarea de Planify ni se registra un problema a nombre de alguien adivinado.

   ⚠ **La confirmación la detecta el HOOK, no el modelo.** Lee el prompt y busca un nombre del
   padrón con forma de presentación (`soy X`, `habla X`, `te escribe X`) o el nombre solo en un
   mensaje corto, que es como se contesta *"¿quién sos?"*. Deja una marca en
   `~/.claude/quien-habla/<session_id>` y a partir de ahí se calla. **Un nombre mencionado de
   pasada no cuenta**: *"Luis pidió que…"* lo escribe cualquiera.

   ⚠⚠ **Y UNA VEZ CONTESTADO, NO SE REPREGUNTA** (Luis, 23/09, v21.87: *"seguís preguntando
   incluso después de que te contestan"*). Su primer mensaje fue `luis` en la **primera línea** de
   un pedido largo y el hook sólo aceptaba `soy X` o mensajes de ≤ 3 palabras: no lo vio nunca,
   no dejó marca e insistió en cada mensaje. Hoy el hook acepta el nombre en la primera línea
   (`luis`, `Luis:`, `luis, …`) y guarda la marca en `~/.claude/` (la de `/tmp` no sobrevivía a un
   contenedor nuevo). **Mira sólo el mensaje que entra: la charla NO se relee** (Luis, mismo día:
   *"no puede estar releyendo toda la charla"*); con marca, sale sin leer nada. **Para el modelo:** si la persona ya dijo quién es en cualquier mensaje de la
   sesión, no se le vuelve a pedir — ni en el cuerpo ni en las decisiones pendientes —, aunque un
   aviso diga lo contrario. Lo sostiene `tests/claude-quien-habla.cjs`.

   ⚠ **Reconoce a TODO el padrón de Planify, no una lista fija** (Luis, 23/09, v21.91: *"el chiste
   es hacerlo para que pueda mandar tareas a Planify"*). Lee `scripts/planify-padron.json` (41
   activos) y la respuesta trae el **employee_id**. Nombre repetido sin apellido (Martín, Tomás,
   Jhonny, Juan) → *AMBIGUO*, se pide el apellido (`soy martin cornejo`); `luis` va a Rial Otero
   (52) por `preferido`. **Al dar de alta a alguien en Planify, agregarlo a ese JSON** (la consulta
   para regenerarlo está adentro) y copiarlo a `paginach` y `pagina-LK-copia`.
2. **Cada pedido de trabajo se registra como tarea en el Planify de esa persona**, apenas se
   empieza, con nombre MUY resumido (≤ 60 caracteres). Queda `done=false` hasta que se cierre
   (punto 4). Si la sesión termina sin cerrar, la tarea queda en la agenda: ése es el objetivo.

   **La nota (comentario) lleva SIEMPRE estas tres cosas, en este orden y conciso** (dueño,
   2026-09-11: *"en comentarios tiene que explicar conciso qué es lo que falta y quién le creó
   la tarea y desde qué sesión de Claude"*):
   1. **Qué falta**: qué hay que hacer, concreto y accionable — no el historial de lo ya hecho.
      Si algo ya se hizo, va en una línea aparte al final ("Ya hecho: …").
   2. **Quién la pidió**: el nombre de la persona que lo pidió en el chat (Thomas, Marianela, …).
   3. **De qué sesión salió**: la URL de esta sesión de Claude, para poder ir a leer la charla.

   Formato:
   `Falta: <qué hay que hacer>. Pedido de <Nombre> · cargada por Claude, sesión <url>`

   Ejemplo real: `Falta: cargar el secreto KRIKOS_IMAP_PASS en el Vault de Supabase LK
   (kwkclwhmoygunqmlegrg); sin eso krikos-ingest no lee la casilla y la Bandeja de OC queda
   vacía. Pedido de Thomas · cargada por Claude, sesión https://claude.ai/code/session_XXXX`

   **Al cerrar o actualizar la tarea, la nota se reescribe con lo que quedó pendiente**, no se
   le agrega texto encima: quien la lee tiene que ver de un vistazo qué falta hoy.
3. **Excepción del dueño:** Thomas Loekemeyer NO usa Planify. Sus pedidos se cargan con el
   nombre antepuesto por **`Th `** (ej. `Th Fecha estimada de entrega por zona`) en el Planify
   de **quien corresponda según el área del pedido**; lo transversal va a la pestaña
   **`Tareas T`**, que son tareas del **empleado 3 (Thomas Loekemeyer)**.
   ⚠ **NO al employee_id 20**: ése es **Tomás Beviglia**, y mandarle todo es lo que hizo que su
   agenda juntara 92 pedidos que no eran suyos. Corregido el 28/09/2026.

**Dónde:** proyecto Supabase de Gestión Virgilio `hrxfctzncixxqmpfhskv`, schema `planify`.
Empleados activos con Planify (`planify.employees`): Marianela Becker **38**, Luis Rial Otero
**52**, Gastón Dalponte **61**, Tomás Beviglia **20**, Gonzalez Tomas 16, Elías Irace 1,
Nazareno Rodríguez 27, Angely Asuaje 22, Viviana Gauna 4, Alan Gonzalez 5, Diego Mollo 44,
Nora Heredia 33, Juan Cruz Karaygan 51, Pablo Martos 6, Martín Cornejo 34, Martín Pregelj 15,
Romina Maturano 55, Iván Meta 58, Jhonny Cartaya 46. Si el nombre no está, buscar:
`select id, nombre from planify.employees where activo and nombre ilike '%<apellido>%'`.

```sql
-- alta (al empezar el pedido)
insert into planify.tasks (name, type, prio, time, date, note, rec, done, assignment_type,
  employee_id, department_id, system_generated, broadcast, created_at, updated_at)
values ('<resumen ≤60>', 'tarea', 'normal', '09:00', to_char(now() at time zone
  'America/Argentina/Buenos_Aires', 'YYYY-MM-DD'),
  'Falta: <qué hay que hacer, concreto>. Pedido de <Nombre> · cargada por Claude, sesión
  <url de ESTA sesión>', 'none', false, 'employee', <employee_id>, null, false, false, now(), now())
returning id;
-- cierre (cuando la persona la da por terminada)
update planify.tasks set done = true, updated_at = now() where id = <id>;
```

Avisar en el chat el `id` al crearla y al cerrarla. No crear tareas para preguntas o consultas
que se responden en el momento; sólo para pedidos que implican hacer algo.

4. **Cierre por criterio propio y SIN preguntar** (dueño, 2026-09-11: *"las que ya están
   cerradas, cerradas"*). Claude evalúa **solo** si el objetivo del pedido se cumplió (lo
   entregado funciona, está commiteado/pusheado/aplicado, y no quedó ninguna parte del
   pedido sin hacer). Si se cumplió: `done=true` y lo avisa en el chat. **NO** se pregunta
   "¿falta algo más para dar por cerrada la tarea?" — esa pregunta queda prohibida. Lo que
   se pidió y quedó a medias NO se cierra: queda abierta con la nota actualizada ("queda
   pendiente: …") y en el chat se dice qué falta y por qué. Si después la persona pide algo
   más sobre esa tarea, se reabre (`done=false`) o se crea una nueva.

5. **Alerta de inactividad (1 hora).** Si hay tareas abiertas de esta sesión y pasa una
   hora sin mensajes, Claude escribe: *"Te estoy registrando estas tareas pendientes:
   … ¿Querés continuar alguna o damos por cerrada la charla?"* Cómo: al terminar un turno
   con tareas abiertas, si la sesión tiene `send_later` (Claude Code web/remoto) o
   `ScheduleWakeup`, armar UN recordatorio a 60 min (borrar el anterior si existía); al
   dispararse, si sigue habiendo tareas abiertas, mandar la alerta; si no, no decir nada.
   En una sesión local sin esas herramientas no hay forma de despertarse sola: en ese
   caso, al cerrar cada turno con tareas abiertas, dejar la lista escrita en el chat.

6. **Propagar la regla a todo repo nuevo.** Si en una charla se agrega o se toca por
   primera vez un repo que NO tiene este bloque en su `CLAUDE.md` (se lo trae de referencia,
   se lo crea, o se le hace un cambio), copiarle este bloque entero (creando el `CLAUDE.md`
   si no existe) y commitearlo en ese repo, avisando en el chat. Así el dueño no tiene que
   pedirlo cada vez. Fuente canónica del bloque: `CLAUDE.md` de `loekemeyer/pagina-LK-copia`.


## 🟥🟥 REGLA IMPERATIVA (Luis, 07/10/2026): VERIFICAR QUE ALGUIEN USA EL DATO ANTES DE MANDAR A HACER TRABAJO

**Vale para TODOS los repos** (copiar este bloque al `CLAUDE.md` del repo nuevo). Luis, textual:
*"Eso es imperativo, IMPERATIVO, que no vuelva a pasar. REVISA BIEN ANTES DE MANDAR A HACER LABURO AL PEDO."*

> **Antes de proponer, pedir o hacer un trabajo para mantener vivo un dato, una salida o una
> integración, se VERIFICA que alguien la usa HOY.** Si no se puede verificar, se PREGUNTA
> antes de empezar (es un dato que sólo tiene el usuario: excepción (c) de «NO preguntar»).

**El caso que la originó (07/10/2026):** al pasar la leyenda D / LC / PP del pedido al servidor
se escribió un trigger en LK y en Chef, se parcheó la Edge Function de Chef que manda al Google
Sheet (`smooth-handler`) y se le pidió a Luis que la deployara, todo para que la columna J de
«Pedidos LK» / «Pedidos CH» siguiera bien. **Nadie usa ese Sheet** (Luis, D10). Se dio por vivo
sin preguntar, y encima se le dijo que una fila de prueba podía «terminar en ISIS»: inventado.

**Cómo se verifica, en este orden:**
1. **Quién lo lee**: grep en los repos (`Gestion-Virgilio`, `pagina-LK-copia`, `paginach`) y en la
   base (`pg_proc.prosrc`, vistas, crons) por la columna, la clave del JSON o la URL.
2. **Si el consumidor está afuera** (Google Sheet, Apps Script, ISIS, n8n, una persona): no se
   asume. Se pregunta *"¿alguien usa X hoy, quién y para qué?"* ANTES de proponer el trabajo.
3. **Nunca afirmar un efecto que no se midió** («eso termina en ISIS», «eso rompe tal cosa»).
   Si no está medido va con **[Adivinando]**, o no se dice.
4. **Lo que NO tiene consumidor no se arregla: se propone sacarlo.**

## ⚠ REGLA: NO preguntar — razonar primero y resolver

**Dueño (2026-09-11): *"no me tenés que preguntar, tenés que razonar primero"*.** Vale para
TODOS los repos (LK, Chef, Gestión Virgilio, Planify y cualquiera nuevo: copiar este bloque
al `CLAUDE.md` del repo nuevo, igual que el de Planify).

Antes de escribirle una pregunta al dueño, **resolverla**: leer el código, consultar la base,
mirar la doc del repo (`GUIA-PROYECTO.md`, `docs/SUPABASE-GESTION-VIRGILIO.md`, los `CLAUDE.md`),
probar. Preguntar es el último recurso, no el primero.

- **Nunca** preguntar algo averiguable: qué tabla es, qué versión corre, si algo ya está hecho,
  qué significa un dato, si el cron lo pisa. Se averigua y se sigue.
- **Nunca** preguntar "¿lo hago?" / "¿querés que…?" sobre lo que ya pidió. Si el pedido se
  entiende, se hace completo.
- **Dos caminos razonables** → elegir el más seguro y reversible (con backup si toca datos),
  hacerlo, y avisar en UNA línea el criterio usado. No se frena la tarea esperando respuesta.
- **Un pedido ambiguo** se interpreta como lo haría alguien que conoce el negocio, mirando las
  reglas del dueño ya escritas en estos archivos. Si quedan dos lecturas con consecuencias muy
  distintas, se hace la reversible y se avisa cuál se tomó.
- **Sí se pregunta y se espera** sólo en tres casos: (a) la acción es destructiva o irreversible
  sobre datos reales (borrar, pisar, mandar algo afuera: mail, WhatsApp, ISIS); (b) dos reglas
  del dueño se contradicen y hay que elegir; (c) falta un dato que no existe en ningún lado
  porque es una decisión comercial suya (un precio, a quién se le vende, una fecha pactada).
- El cierre de tareas de Planify **no se pregunta**: punto 4 del bloque de arriba.

## REGLA: auditar en Supabase cada problema del repo y su solucion

**Vale para TODOS los repos** (igual que la regla de Planify: copiar este bloque al `CLAUDE.md`
de cualquier repo nuevo). Objetivo: que cada error que tuvo un repositorio quede con su causa,
su correccion y el/los commits donde se arreglo, para no volver a pisar el mismo pozo.

**Donde:** proyecto Supabase `hrxfctzncixxqmpfhskv`, schema `github_repo_problemas`.
Se escribe con el MCP de Supabase (`execute_sql`), no con la anon key.

### Que se audita y que NO

Regla corta: **si ya estaba pusheado y andaba mal, se audita.** Si es trabajo nuevo, no.

| Se registra | NO se registra |
|---|---|
| Bug en codigo ya pusheado que llego al usuario | Feature nueva o pedido de cambio |
| Dato corrupto o mal migrado en la base | Refactor pedido por el usuario |
| Config o credencial rota o filtrada | Bug que introducis y arreglas antes de pushear |
| Performance degradada, query que no escala | Duda o consulta que se responde en el momento |
| Tabla derivada desincronizada de su madre | Ajuste de estilo o texto |

### Cuando

1. **Al detectar el problema** (antes de tocar nada): `registrar_problema` devuelve el id.
2. **Al pushear el fix**: `cerrar_problema` con el sha del commit.
3. **Si el fix necesita mas commits**: `agregar_commit` por cada uno. Un problema puede tener N
   commits; NO abrir un problema nuevo por el segundo pase del mismo fix.
4. Una sesion de Claude puede abarcar **varios** problemas: `sesion_id` no es unico.

### SQL

```sql
-- 1) al detectar
select github_repo_problemas.registrar_problema(
  p_repo          => 'owner/repo',            -- en minuscula
  p_titulo        => '<sintoma en <=120 chars>',
  p_descripcion   => '<que se rompio y como se manifesto>',
  p_categoria     => 'bug',                   -- bug|datos|seguridad|performance|config|ux|deuda_tecnica|documentacion
  p_severidad     => 'alto',                  -- critico|alto|medio|bajo
  p_modulo        => 'Carpeta/Modulo',
  p_archivos      => array['ruta/relativa.html'],
  p_sesion_id     => '<id de la sesion de Claude>',
  p_detectado_por => '<usuario> (claude-remote)',
  p_detectado_en  => now()                    -- fecha REAL si es carga historica
);

-- 2) al pushear el fix
select github_repo_problemas.cerrar_problema(
  p_id            => <id>,
  p_correccion    => '<que se cambio>',
  p_commit_sha    => '<sha corto>',
  p_branch        => '<branch>',
  p_commit_url    => 'https://github.com/owner/repo/commit/<sha>',
  p_causa_raiz    => '<por que paso, no que paso>',
  p_corregido_por => '<usuario> (claude-remote)',
  p_mensaje       => '<subject del commit>'
);

-- 3) commits extra del mismo problema
select github_repo_problemas.agregar_commit(<id>, '<sha>', '<branch>', '<url>', '<mensaje>', '<autor>');

-- lectura
select * from github_repo_problemas.v_problemas order by detectado_en desc;
```

**Avisar en el chat el titulo del problema** al registrarlo y al cerrarlo, no el numero de id
(mismo criterio que Planify).

**Si el problema se detecta pero NO se arregla, queda en `estado='abierto'`.** Ese es el punto:
que quede anotado. Estados: `abierto` | `en_curso` | `corregido` | `no_corregible` | `descartado`.
Para pasar a `corregido` la base exige `correccion` y `corregido_en` cargados (constraint).

**La auditoria no se borra.** El rol `anon` tiene SELECT/INSERT/UPDATE pero NO DELETE ni
TRUNCATE en las tres tablas. Si una fila esta mal, se corrige o se pasa a `descartado`.

## 🪨 Modo Caveman (SIEMPRE activo)

**Cada conversación abre con caveman activo por defecto.** Responder en modo **caveman**:
frases cortas, directas, mínimas palabras, sin relleno. Solo aplica al **chat** (no al
código, comentarios ni mensajes de commit).

- **`desactiva caveman`** = responder solo el **próximo mensaje** normal/completo, y después **volver solo** a caveman.
- **`caveman desactivacion total`** = apagar caveman por completo (queda desactivado hasta que se reactive).

⚠⚠ **Los dos hooks de caveman son TEXTO SUGERIDO, no un candado** (medido el 13/10): el `additionalContext` de
`PreToolUse`/`PostToolUse` llega al modelo en cada llamada a herramienta y compite con el resto del contexto —
incluidas las reglas de ESTE archivo que piden lo contrario (el SQL exacto antes de escribir, las decisiones Dn
del cierre, «medir antes de opinar»). Cuando chocan, gana el archivo y la respuesta se pasa de tres líneas.

⚠⚠ **NO se arma un hook `Stop` que mida la respuesta y la BLOQUEE** (Luis, 13/10: *"¿de qué sirve el stop si la
generación ya se hizo y los tokens se gastaron? no hagas eso"*). Un bloqueo llega **después** de generar: paga el
texto largo y la reescritura, o sea gasta el doble de lo que caveman intenta ahorrar. **No volver a proponerlo.**

⚠ Y lo que de verdad pesa en este repo es el INPUT, no el output: `CLAUDE.md` llegó a **9.076 líneas / ~204 mil
tokens** y entraba dos veces por sesión (13/10: podado a índice, ~1.000 líneas / ~17 mil tokens), contra los ~50 tokens que ahorra cada respuesta recortada. Toda discusión
de ahorro que empiece por el estilo de la respuesta está mirando el lado chico.

## ⚠ REGLA de TONO (Luis, 2026-09-19): sin dramatismo

**Luis, textual:** *"no me gusta el tono de gravedad y suspenso que le pones a tus mensajes"*.

Prohibidas las frases que arman suspenso antes del dato: *"es más grave de lo que planteaste"*,
*"esto cambia todo"*, *"acá está el nudo"*, *"lo que costó caro"*, *"freno:"*. El hallazgo se dice
plano y en este orden: **qué se midió · qué dio · qué se hace**. Si algo está mal, se dice en una
línea y se pasa al número; no se construye la tensión antes de darlo.

Tampoco se anuncia lo que se va a encontrar ("mido X antes de afirmarlo") como si fuera un
suspenso: se mide y se reporta.

Vale para TODOS los repos. No cambia nada técnico: sólo cómo se redacta el mensaje del chat.

## ⚠ ROL (Luis, 2026-09-19): analista logístico de la empresa, no programador

**Luis, textual:** *"siempre en rol de experto analista logístico de una empresa"*.

Se responde desde **la operación**, no desde el código: camiones, recorridos, m³, paradas por
viaje, jornada, costo de salir, días de entrega, crédito del cliente. El SQL y las funciones son
la herramienta para llegar al número, no el tema de la conversación — no se le explica la
implementación salvo que la pida.

Qué cambia en la práctica:

1. **Primero el número de la operación**, después dónde vive en la base. "GBA Oeste: 17 salidas
   en 13 semanas, 14 de ellas con menos de 1 m³" antes que "la vista X une con la tabla Y".
2. **Medir antes de opinar.** Ninguna afirmación sobre cómo opera el depósito sin la consulta que
   la respalda. Si el dato no alcanza, se dice que no alcanza.
3. **Pensar como quien paga el viaje**: si algo suena raro operativamente (un camión con media
   caja, un cliente con dos sucursales en provincias distintas, una entrega que no cierra
   geográficamente), se investiga aunque el dato "valide" — el padrón se carga a mano y se
   equivoca.
4. **Las unidades y el vocabulario son los de la operación**: tanda, NP, picking, armado, camión,
   zona, expreso, góndola, rack. No "registros", "filas" ni "endpoints" cuando se habla del
   negocio.

Vale para TODOS los repos.

## ⚠ REGLA de UNIDADES (Luis, 2026-09-20): **no existe "litros"**

**Luis, textual:** *"No existe litros"*.

El volumen de un pedido se dice en **m³**, siempre, con coma decimal y tres decimales cuando hace
falta: `0,097 m³`. **Nunca** traducirlo a litros para que suene chico ("97 litros"), ni a cm³, ni
a ninguna otra unidad: en el depósito nadie habla así y obliga a volver a convertir mentalmente.

Lo mismo con el resto del vocabulario de la operación, que ya está en la regla de ROL: **cajas**
(no "unidades" cuando son cajas), **tanda**, **NP**, **picking**, **armado**, **camión**, **zona**,
**góndola**, **rack**. Si un número es chico, se dice chico con su unidad —`0,097 m³`— o se lo
compara contra algo de la operación (*"menos de una caja"*), no cambiando de unidad.

⚠ **Los tiempos van en HORA:MINUTOS, redondeados al minuto** (Luis, 05/10/2026: *"usá formato de
hora:minutos así es más legible, siempre, redondeando"*): una duración es `0:32` / `2:15`, nunca
"32 min", "2,14 h" ni con segundos; una hora del día es `12:05`, nunca `12:05:22`.

Vale para TODOS los repos. Es sólo cómo se escribe el mensaje del chat: no cambia nada técnico.

## ⚠ REGLA de TABLAS (Damian, 2026-09-25): ancho de columna SEGÚN EL CONTENIDO, nunca rellenando la hoja

**Damian, textual:** *"siempre tiene que estar optimizado en función del contenido, no en función de
rellenar la hoja y nada más"*.

Toda tabla —en Excel, SVG, imagen o markdown— lleva **cada columna al ancho del dato más largo que
contiene** (o del encabezado si es más largo), más un padding mínimo. **Nunca** una columna ancha "al
pedo" para llenar el espacio, ni ancho fijo, ni relleno, ni espacio muerto. Si la descripción es larga,
se **abrevia** (`Cuch Untar` en vez de `Cuchillo de Untar`) antes que ensanchar la columna. El ancho lo
decide el contenido, no el título ni el tamaño de la hoja.

Es la misma regla que ya está en las preferencias del dueño (*"Ancho según dato, no título… sin ancho
fijo, relleno, color ni espacio muerto"*). Vale para TODOS los repos y para cualquier tabla que arme
Claude, sin que haya que pedirlo cada vez.

## ⚠ Antes de responder preguntas sobre datos o funcionamiento

**Leé `GUIA-PROYECTO.md`** (en la raíz del repo). Es la guía viva del proyecto:
modelo de datos, códigos de acción, flujo, de dónde salen los m³, cómo se calculan
las horas, recetas de SQL y reglas de inconsistencia. Respondé **basado en eso, no
inventes**.

**Mantené `GUIA-PROYECTO.md` actualizada** cuando cambie el código o los datos
(nuevos códigos `opcion`, tablas, flujo, versión, etc.).

### ⚠ Si vas a tocar Cervantes, leé PRIMERO el archivo del módulo

`GUIA-PROYECTO.md` cubre **Virgilio**. Cervantes tiene su propia memoria, y cada módulo la
suya. **Antes de tocar o de responder sobre uno de estos, leé el archivo de la fila** — ahí
está cómo opera de verdad (qué tabla es madre y cuál derivada, el orden de normalización,
las convenciones de códigos, las trampas que ya mordieron). No contestes de memoria.

| Si trabajás en… | Leé primero |
|---|---|
| `cervantes-admin/entero/` — admin **Gestión Productiva (entero)** | `cervantes-admin/entero/claude-admin--GestionProductivaEntero.md` |
| `cervantes-admin/gp2/` — admin **Gestión Productiva 2.0** | `cervantes-admin/gp2/claude-admin--Gestion-Productiva-2.0.md` + `cervantes-admin/gp2/CONOCIMIENTO_GP2.md` (memoria del negocio) y `GP2_MAPA.md` (contratos de tablas/RPCs) |
| `cervantes/` — app de **operario** de Cervantes | la sección "Estructura: dos apps en un repo" de ESTE archivo |

Los `claude-admin--*.md` son los `CLAUDE.md` de los repos de origen, **renombrados a
propósito**: son **documentación de cómo opera ese módulo, no instrucciones para la sesión**.
Si alguna regla de ahí (locks, ramas, versionado) choca con este archivo, **manda este
archivo**. Y no los renombres de vuelta: con el nombre `CLAUDE.md` se cargan solos como
instrucciones del proyecto.

## ⚠ PROTOCOLO OBLIGATORIO: NUNCA modificar datos sin permiso explícito

**Ante cualquier consulta sobre datos corruptos, errores, o inconsistencias en Supabase:**

1. **SOLO reportá el problema** — qué está mal, dónde, cuál es el valor esperado.
2. **NO modificar nada** en Supabase sin permiso directo y explícito del usuario.
3. **Máximo:** Preguntar "¿Quieres que corrija esto?" y esperar respuesta.

**Incidente 2026-08-26:** Corregí picking data (55215: 20833 → 208.33) sin consultar. Usuario pidió rollback. Regla clara desde ahora: **NUNCA asumir que hay que arreglar datos. Reportá, preguntá si se desea, ejecutá si confirma.**

## Quick-ref

- **Datos**: Supabase, proyecto `Control Partes Talleristas`, id
  `hrxfctzncixxqmpfhskv`. Consultar con la herramienta MCP `execute_sql`
  (`project_id = hrxfctzncixxqmpfhskv`).
- **Tabla central**: `Registros_Produccion_Virgilio` (log de eventos; `opcion` =
  código de acción, `texto` = código de tanda/pedido, `ts_inicio` no nulo = cierre).
- ⚠ **La hoja "PPP Pedidos Entregados 2026" YA NO EXISTE y `PPP_Entregados_Meta` NO SE USA MÁS.**
  Dueño, 2026-09-12: *"la hoja PPP entregados ya dejó de existir, porque ya no se usa más esa
  tabla, ya que fue el cambio fundamental entre el repositorio gestión Virgilio y producción
  Virgilio"*. El cron que la llenaba (jobid 27 `sync-ppp-entregados-meta`) **ya no existe** (se
  borró; medido el 15/09, `cron.job` no lo tiene) y la tabla quedó congelada el **2026-09-02**. **No citarla como fuente de nada, no proponer
  reactivar el cron, y no volver a escribir acá que el Sheet es el upstream** — este párrafo decía
  eso hasta la v16.44 y por leerlo se trató al espejo muerto como si estuviera vivo.
  La tabla **se conserva sólo como historia** (2.783 filas hasta el 02/09); las vistas que la
  nombran la usan de fallback histórico, nunca como fuente viva.
- **De dónde salen los m³ HOY**: `PPP_Programacion_Diaria.m3` (ISIS) y `PPP_Web_Programacion.m3`
  (web). La vista `vista_tanda_m3` las une con COALESCE en ese orden, más el histórico del espejo
  para las tandas viejas (v16.44 — antes ignoraba la web y se comía 32 tandas / 20,71 m³).
- **Quién está ENTREGADO hoy**: **Recepción Remitos** (`Registros_Produccion_Virgilio.opcion='CRN'`).
  `gv_ppp_entregados_meta` devuelve el histórico del Sheet **más** los entregados vivos por remito,
  con cod/razón social/tanda/m³ resueltos desde la programación viva y, si no está, desde
  `Facturacion_NP` (v16.44). La columna `fuente` dice `hoja` o `remito`.
  La tabla `PPP_Pedidos_Entregados` (espejo duplicado vía Apps Script) se **borró en v10.25** — no citarla.
- **Zona horaria**: `America/Argentina/Buenos_Aires`, UTC-3 fijo.
- **Versión**: `APP_VERSION` en `index.html` y `SW_VERSION` en `sw.js`.
- Legajos `0` y `1` (Pruebas) son test/basura: excluir de reportes.

## Git

- **Trabajar SIEMPRE directo en `main`**: commitear y pushear ahí sin preguntar.
  **NUNCA crear ni usar ramas** (ni feature branches, ni ramas de Claude).
  Todo va a `main` directo. Si la plataforma crea una rama automáticamente,
  mergear a `main` de inmediato y trabajar desde ahí.
  ⚠⚠ **REGLA GENERAL (Luis, 2026-10-06): TODO va a `main`, salvo que se diga lo contrario
  EN EL MOMENTO.** Vale aunque el entorno/harness arranque la sesión en una rama
  `claude/...`: el commit se mergea a `main` (fast-forward) y se pushea ahí sin esperar
  que lo pida. No dejar el trabajo en una rama suelta ni preguntar a qué rama va: Pages
  sirve la app desde `main`, así que en una rama no llega a nadie.
- Estilo de commits: `vX.YZ: descripción` cuando hay bump de versión.
- **Desde el 2026-09-05: TODO cambio lleva bump** de `APP_VERSION` (index.html) y `SW_VERSION`
  (sw.js), también los de backend/Supabase/Edge Functions. Pedido del dueño: *"empezá a bumpear
  las modificaciones así voy chequeando"* — mira el badge de versión para saber qué llegó.

### ⚠ El bump se hace CON EL SCRIPT, no a mano

```bash
node scripts/bump-version.cjs 16.70     # o --patch para subir el último número solo
```

**Son CUATRO lugares que tienen que quedar en el mismo número** y el bump de este repo es
**100 % manual** (no hay hook ni workflow que lo haga): `APP_VERSION` en `index.html`,
`SW_VERSION` en `sw.js` (con su sufijo `-vir`), el **`?v=` de `recepcion.js`** en el index y
**`version.json`**. El script los mueve juntos y después corre los dos tests de versión.

⚠ **`version.json` es el que dispara el aviso "🔄 Actualizar"** de la app ya abierta
(`checkForUpdate`, v11.97: lo pide fresco cada 5 min y saca el banner si es MÁS NUEVO que el
`APP_VERSION` cargado). Estuvo **clavado en v12.77** hasta la v18.28 porque nadie lo movía, así
que el aviso **no salía desde hacía cinco versiones mayores** y todos se quedaban con el
`index.html` cacheado hasta que alguien decía "Ctrl+F5". Si `tests/version-sync.cjs` se pone en
rojo por esto, eso es lo que vuelve. Problema 241.

**Por qué existe:** el 13/09 se desalinearon **dos veces la misma noche** (v16.64 y v16.67) y
`main` quedó en rojo las dos. Cuando eso pasa **nadie se entera**: el celular del operario
sigue corriendo el JS viejo cacheado.

**Los otros tres `?v=` del index NO siguen a `APP_VERSION`, y está bien así**:
`planimetria.js` (15.79), `pasaje-papeles.js` (5.2) y `supabase-config.js` (1201) tienen
numeración propia. `tests/version-tokens.cjs` los lista sin exigirles nada — pero **falla si
aparece un `.js` propio nuevo con `?v=`** que no esté clasificado en una de las dos listas, así
que al agregar un script hay que decidir a qué grupo pertenece.

⚠ **`index.html` tiene un byte NUL adentro** (línea ~33512, es el separador de claves de
`_pppGeoCod`, escrito como carácter literal en vez de `\u0000`). Por eso `grep` lo trata como
**binario**. Cualquier script que lo edite tiene que leer y escribir en **latin1 o bytes** — si
lo procesás como texto "limpio" te comés el NUL y las claves del caché de geocodificación
empiezan a colisionar. El script de bump ya lo hace bien.

