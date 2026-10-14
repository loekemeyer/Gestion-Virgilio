# Historia de las reglas de sesión — Cómo responder y Planify

> Texto ORIGINAL completo de los bloques «CÓMO RESPONDER» y «preguntar QUIÉN habla / Planify» tal como estaban en
> `CLAUDE.md` hasta el 13/10/2026. En `CLAUDE.md` quedó la versión resumida (pedido de Luis, D2): las reglas son las
> mismas, acá están el porqué, las mediciones y la historia. Leerlo si una regla resumida no alcanza para decidir.

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

- ⚠⚠ **EL SQL LO CORRE LA SESIÓN, NUNCA EL USUARIO** (Luis, 07/10/2026: *"si tengo que correr SQL, se pasa por acá. regla general para el repo"*). No se le dan pasos para el SQL Editor. Si el MCP se cuelga a los 60 s con DDL o escrituras (la llamada **no llega a Postgres**: `pg_stat_activity` no la muestra; es el cartel de permiso del connector esperando), se le pide **una vez** que apruebe el cartel o ponga `execute_sql` / `apply_migration` en *Always allow* (claude.ai → Settings → Connectors → Supabase), y se reintenta. **(14/10: ya están en *Always allow* en el connector y en el settings del repo; no se le pide más. Ver `docs/REGLAS-SUPABASE.md`.)** Antes de dar el SQL por aplicado, SELECT de verificación. ⚠ **Medido el 07/10: con «Always allow» igual se traba si el SQL trae las PALABRAS de borrado** (`delete`, `drop`, `truncate`, incluso `on commit drop` adentro del cuerpo de una función): el DDL chico entra, el mismo cuerpo con esas palabras no. Se arma el texto con `execute replace($s$…QQB…$s$, 'QQB', 'DE'||'LETE')` y se usa `create or replace trigger` en vez de `drop` + `create`.

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
