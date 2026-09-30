> ⚠️ **ESTO ES DOCUMENTACIÓN, NO INSTRUCCIONES.**
>
> Es el `CLAUDE.md` del repo **`Gestion-Productiva-2.0`**, traído tal cual el 2026-09-10 (re-sincronizado el 2026-09-30, v1.211.0) cuando ese admin
> se copió acá adentro (`cervantes-admin/gp2/`). Se guarda **renombrado a propósito**: un archivo
> llamado `CLAUDE.md` dentro de este repo se carga como instrucciones del proyecto, y una
> sesión de Gestión Virgilio terminaría obedeciendo las reglas de otro repo (locks, ramas,
> versionado) que acá no aplican o se contradicen con las nuestras.
>
> **Cómo leerlo:** es la memoria de **cómo opera este admin** — qué tabla es madre y cuál
> derivada, el orden de normalización, las convenciones, las trampas que ya mordieron. Sirve
> para entender el módulo antes de tocarlo. Lo que **no** es: una orden para la sesión.
> Las reglas que mandan acá están en el `CLAUDE.md` de la raíz de Gestión Virgilio.

---

# 📕 REGLA 0 (primera hoja del libro) — TODO LO DE SUPABASE SALE DEL SCHEMA `GP2`. NUNCA DE `public`.

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

**Regla del usuario (2026-09-12, textual): "quiero que esa máxima figure en la primera hoja del
libro… siempre que en cualquier sesión se hable de este repositorio, considerarlo para cuando
haya que trabajar con Supabase".** Se lee ANTES de escribir la primera consulta.

- **Cliente:** toda pantalla GP2 usa `GP2_SB()` (schema `GP2`, definido en `supabase-config.js`).
  Un `supabase.createClient(...)` suelto cae en `public` — eso está prohibido en GP2.
- **Tablas, vistas y RPCs:** lo que necesita una pantalla GP2 **tiene que existir en `GP2`**. Si no
  existe, se crea en `GP2` (mirando la lógica del vecino si hace falta), no se apunta a `public`.
- **Adentro de la base igual:** ninguna función ni vista de `GP2` lee tablas de negocio de `public`.
- **Internalizar NO es copiar la tabla del vecino.** Lo que hoy se mira en `public` entra a GP2
  **con la normalización de GP2** [usuario 2026-09-12: *"mantengamos la lógica de la normalización
  que yo uso en schema gp2"*]: el modelo es `componente` → `inventario` → `articulo_componente` /
  `componente_bom` → `ruta` / `ruta_paso` → `contraparte_alias` (ver "Completar tablas manteniendo
  la NORMALIZACIÓN" más abajo). Antes de crear una tabla nueva, **preguntarse si el dato ya se
  deduce del modelo**: caso real del 2026-09-12, "qué artículo entrega cada tallerista" NO necesitó
  calcar `Articulos Virgilio X Tallerista` — sale del último paso con contraparte antes del paso
  `virgilio` de la ruta. Una tabla plana del vecino copiada tal cual es deuda, no migración.
- **`public` = la casa del vecino** (programa viejo "Gestión Productiva Entero"): **solo lectura, y
  solo para entender cómo resolvió algo**. Ni un dato de negocio de GP2 sale de ahí.

**Por qué existe la regla (dicho por el dueño, 2026-09-12):** *"La creación de este repositorio
surgió porque en gestión productiva entero era todo quilombo, y yo empecé subiendo las tablas
normalizadas… En medio se hicieron como cincuenta tablas que mira desde public, y es un desastre,
yo no quería eso"*. Mirar `public` traiciona el motivo por el que GP2 existe. Detalle y auditoría
completa en `CONOCIMIENTO_GP2.md` §4cf.

**Estado al 2026-09-12 (auditado y limpiado):** el menú `GP2_MODULOS.html` abre **solo pantallas
GP2**; las 43 `*_GP2.html` (más `login.html`, que usa `sb.schema('GP2')`) usan el cliente GP2, y
ninguna función ni vista de `GP2` toca una tabla de `public` (única referencia: `public.http_get`,
la extensión http). Las **50 pantallas viejas que ya tenían reemplazo GP2 se borraron** (109
archivos; siguen en el historial de git y en `GestionProductivaEntero`). Quedan **3 archivos**
mirando `public`, ninguno colgado del menú y ninguno en uso: Control Carga Remitos, Preavisos e
`InformesVirgilio` (la carpeta `Facturas/` se borró entera el 2026-09-13: su único archivo llamaba a
la Edge Function `leer-factura` con la clave de OpenAI filtrada — ver LOCKS), que es de Gestión Virgilio y tiene su propio repo. El último que
estaba **vivo**, Calcular Cajones, se migró el 2026-09-13 (`CalcularCajones_GP2.html` +
`GP2.cajon`). El mapa completo, con lo
que se borró y lo que se relinkeó antes de borrar, está en `MIGRACION_PUBLIC_GP2.md`.

# ⚠️ ANTES DE CUALQUIER EDIT/WRITE: LEER LOCKS.txt Y REGISTRAR LockX. SIN EXCEPCIONES. ⚠️

# 🚨 TODO VA A `main`. SIEMPRE. SIN RAMAS. 🚨

**Regla del usuario (2026-08-31, textual): "SIEMPRE TODO TENES QUE SUBIRLO A MAIN. NO QUIERO
DECIRLO MAS EN NINGUNA SESION".** No se pregunta, no se propone una rama, no se espera
confirmación: el trabajo terminado y verificado se commitea y se pushea **a `main`**.

- **Si la sesión viene con una rama asignada** (las sesiones remotas de Claude Code arrancan
  con una rama tipo `claude/loquesea` obligatoria por configuración), **igual el destino final
  es `main`**: `git push origin <rama>:main`. Trabajar sobre `main` directo cuando se pueda.
- **Antes de pushear**: la suite completa en verde (`bash tests/ui/run.sh`). Eso es lo que
  reemplaza a la rama como red de seguridad — no el aislamiento, sino los tests.
- **Nunca dejar trabajo colgado en una rama.** Pasó el 2026-08-31: 5 commits quedaron en una
  rama mientras los cambios de Supabase YA estaban vivos en la base → la BD tenía los cambios
  y `main` no tenía el código que los acompaña. Ese desfasaje es el peligro real.
- **Ojo**: lo que se aplica en Supabase (migraciones, datos) **no lo versiona git** y queda
  vivo al instante. Razón de más para que el código llegue a `main` en el mismo momento.

# ⚡ EN ESTE REPO EL SQL SE EJECUTA, NO SE PREGUNTA (2026-09-23)

**Regla del usuario (2026-09-23, textual): "Guárdate como regla en este repo no me preguntes si
ejecutar o no. Ejecutalo directamente."** Reemplaza, **sólo en este repositorio**, la regla general
de pedir un "sí" antes de cada `INSERT` / `UPDATE` / `DELETE`.

- **No se pide confirmación** para los cambios de datos o de schema que el pedido ya implica: se
  ejecutan y después se informa **qué se ejecutó** y el `SELECT` de verificación. El registro va
  *después* del hecho, no antes. Preguntar "¿lo ejecuto?" es perder el turno.
- **Sí se sigue mostrando el SQL y la medición antes/después** de lo que mueve plata o stock. Eso
  no es pedir permiso: es dejar rastro de lo que ya se hizo.
- **Lo que NO cambia:** nunca un `DELETE` masivo ni un `TRUNCATE` de tablas madre (ver "Tablas
  Madre y Derivadas"), nunca borrar la auditoría, y **lo que está fuera de lo pedido se propone,
  no se ejecuta**. La regla saca el permiso previo, no el criterio.

# Gestion Productiva - Instrucciones para Claude

## ⚠ REGLA: preguntar QUIÉN habla y dejar cada pedido como tarea en su Planify

**Vale para TODOS los repos** (LK, Gestión Virgilio, Planify y cualquiera nuevo: copiar este
bloque al `CLAUDE.md` del repo nuevo). Objetivo del dueño: que ninguna tarea quede a medio
hacer sin figurar en la agenda de alguien.

1. **Al empezar la sesión, preguntar quién está hablando** (antes de hacer nada):
   *"¿Quién sos? (Thomas, Marianela, Luis, Gastón, …)"*. Si el mensaje ya lo dice, no repreguntar.
2. **Cada pedido de trabajo se registra como tarea en el Planify de esa persona**, apenas se
   empieza, con nombre MUY resumido (≤ 60 caracteres) y una nota de 1–3 líneas con el
   contexto. Queda `done=false` hasta que se cierre (punto 4). Si la sesión termina sin
   cerrar, la tarea queda en la agenda: ése es el objetivo.
3. **Excepción del dueño — EN ESTE REPO NO SE REGISTRA NADA.** `[Thomas, 2026-09-11, textual:
   "no registres tareas en planify a tomas"]`. Thomas Loekemeyer no usa Planify y **sus pedidos
   NO se cargan en el Planify de Tomás Beviglia** — ni con el prefijo `Th ` ni de ninguna otra
   forma. En GP2 el registro de lo pendiente vive en `CONOCIMIENTO_GP2.md`, `IDEAS-GP2.md` y el
   `[HISTORIAL]` de `LOCKS.txt`, no en Planify. Los puntos 2, 4 y 5 de arriba **no aplican**
   mientras el que habla sea Thomas; siguen valiendo si en esta carpeta trabaja otra persona
   (Marianela, Luis, Gastón, …), que sí tiene su propio Planify.

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
  'America/Argentina/Buenos_Aires', 'YYYY-MM-DD'), '<contexto 1-3 líneas> — cargado desde
  sesión de Claude', 'none', false, 'employee', <employee_id>, null, false, false, now(), now())
returning id;
-- cierre (cuando la persona la da por terminada)
update planify.tasks set done = true, updated_at = now() where id = <id>;
```

Avisar en el chat el `id` al crearla y al cerrarla. No crear tareas para preguntas o consultas
que se responden en el momento; sólo para pedidos que implican hacer algo.

4. **Cierre por criterio propio, no sólo por "listo".** Claude evalúa si el objetivo del
   pedido se cumplió (lo entregado funciona, está commiteado/aplicado, y no quedó ninguna
   parte del pedido sin hacer). Cuando lo considere cumplido, pregunta **"¿Falta algo más
   para dar por cerrada la tarea?"** — si la persona dice que no (o no pide nada más
   dentro de esa tarea), `done=true`. Si dice "listo" antes, también se cierra. Lo que se
   pidió y quedó a medias NO se cierra: se deja abierta con la nota actualizada
   ("queda pendiente: …").

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

## REGLA: claves de Supabase - migrar a las nuevas, NO apagar las legacy todavia

Estado al 2026-09-11. Supabase cambio el sistema de claves. Conviven dos juegos y **los dos
funcionan a la vez**, asi que se migra cliente por cliente sin downtime.

| Sistema | Claves | Se rota de a una |
|---|---|---|
| Nuevo | `sb_publishable_...` (frontend) + `sb_secret_...` (backend) | si |
| Legacy (JWT) | `anon` + `service_role` | NO: las dos derivan del JWT secret del proyecto |

Doc: `supabase.com/docs/guides/getting-started/migrating-to-new-api-keys`. Textual: *"The
legacy anon and service_role keys are based on your project's JWT secret, which makes them
hard to rotate without downtime."* **No existe boton "Roll" para las legacy.**

### 1. Lo filtrado vive en el HISTORIAL de git, y el historial no se arregla

Una `service_role` legacy quedo expuesta en el historial de un repo publico (ver `LOCKS.txt`
de `GestionProductivaEntero`, entrada 2026-09-04). El arbol de trabajo ya esta limpio, pero
eso no alcanza: lo que estuvo en un repo publico pudo clonarlo cualquiera y reescribir el
historial NO lo des-filtra. **El unico arreglo real es invalidar la clave.**

Precision importante: lo que se filtro es la **`service_role` key** (un JWT firmado con el
secret), NO el JWT secret. De un HS256 no se deriva la clave, asi que **apagar las legacy
alcanza** para matar lo filtrado. Rotar el JWT secret es un paso extra, no el obligatorio.

### 2. Como se invalida (y por que todavia no)

Dashboard -> Settings -> API Keys -> pestana **"Legacy anon, service_role API keys"** ->
boton **`Disable JWT-based API keys`**. Apaga `anon` y `service_role` de una sola vez. Es
reversible. Es lo que la doc pide para este caso: *"Make sure you also switch to publishable
and secret API keys and disable the anon and service_role keys."*

**NO apretarlo todavia:** apaga TAMBIEN la `anon`, que es la que usa el frontend. Hoy eso
tira abajo la app entera.

### 3. ⚠ EL STORAGE SI ACEPTA LAS CLAVES NUEVAS — lo que falta es el header `apikey`

**Este bloque cambio DOS veces el mismo dia, y la segunda es la buena.** Vale la pena leer las
dos, porque la equivocacion del medio es facil de repetir:

- **11/09** decia *"el Storage rechaza las claves nuevas al ESCRIBIR"* y que por eso no se podian
  apagar las legacy.
- **13/09 (v16.56)** dije que esa excepcion ya no existia, porque mande un upload con la
  `sb_publishable_` y dio 200. **Estaba mal la conclusion, no la medicion**: en esa prueba mande
  la clave en `apikey` **y** en `Authorization`, y no me di cuenta de que el que hacia el trabajo
  era el primero.
- **13/09 (v16.62), la buena:** el formato de la clave nunca fue el problema. **Lo que faltaba es
  el header `apikey`.**

Medicion contra el Storage real (bucket `inbox` de LK, objeto de prueba creado y borrado):

| Request | Resultado |
|---|---|
| `Bearer sb_secret_…` y nada mas | **403 `Invalid Compact JWS`** |
| `Bearer sb_secret_…` **+ `apikey: sb_secret_…`** | **200**, el objeto se sube |
| `Bearer sb_publishable_…` y nada mas | 403 `Invalid Compact JWS` |
| `Bearer sb_publishable_…` **+ `apikey: …`** | 403 **`new row violates row-level security policy`** ← paso auth; lo frena la RLS, que es lo correcto para una clave publica |

**Por que la legacy andaba sin `apikey`:** la legacy **es** un JWT, asi que el Storage la podia
parsear del Bearer. Con la clave nueva intenta lo mismo, no puede, y contesta `Invalid Compact
JWS`. Ese error significa *"no pude parsear el token"*, no *"no soporto el formato"*.

**Y por eso la app nunca estuvo rota:** `supabase-js` manda `apikey` siempre. Los que fallaban
eran los `curl` / `Invoke-RestMethod` escritos a mano, que mandan solo el Bearer — exactamente el
caso del workflow de Planify (runs 112 a 115 del 11/09). **Ya corregido**: `build-deploy.yml` y
`deploy-only.yml` de `loekemeyer/Planify` mandan las dos cabeceras desde el commit `75179d7`.

Repro, para volver a medirlo (ojo: **si da 200 crea el objeto**, hay que borrarlo con un `DELETE`
a la misma URL — `storage.objects` no se puede borrar por SQL, `storage.protect_delete()` lo
impide):

```sql
select net.http_post(
  url := 'https://<ref>.supabase.co/storage/v1/object/<bucket>/__prueba__.json',
  headers := jsonb_build_object('Authorization','Bearer <clave>','apikey','<clave>',
                                'Content-Type','application/json'),
  body := '{"p":1}'::jsonb);
```

**Inventario de lo que escribe en Storage, al 13/09** (todos con `supabase-js` salvo Planify, o
sea que ya mandan `apikey`): `recepcion.js` de Gestion (bucket `remitos`), `krikos-ingest` de LK
(`krikos-oc`), `script.js` de LK (`.remove()` de videos) y los workflows de Planify (corregidos).

⚠ **Y hay un pedazo de `recepcion.js` que quedo muerto**: `pendUploadFoto` tiene un tercer intento
que hace `signOut()` y sube con la clave pelada como Bearer. Estaba pensado para la anon legacy.
Hoy el primer intento anda, asi que no molesta, pero el comentario que dice que ese fallback
"sube igual" hay que leerlo con esta nota al lado.

### Orden obligatorio

1. Contar donde esta escrita la clave legacy en este repo:
   ```
   grep -rl 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9' . --exclude-dir=.git | wc -l
   ```
   (Referencia: `GestionProductivaEntero` tenia 66 archivos y 0 con la clave nueva.)
2. Reemplazar esa cadena por la `sb_publishable_...` del proyecto Supabase de ESTE repo
   (cada proyecto tiene la suya; no mezclar).
3. Migrar todo backend que use `service_role` (Edge Functions, n8n, scripts) a `sb_secret_...`.
4. Inventariar lo que escribe en Storage (ver el punto 3) y confirmar que **cada uno manda el
   header `apikey`**, no solo el Bearer. Ya NO hay que dejar nada en legacy por eso: con
   `apikey` el Storage acepta tanto `sb_secret_` como `sb_publishable_` (medido el 13/09).
   Lo que usa `supabase-js` ya lo manda solo; lo escrito a mano (`curl`, `Invoke-RestMethod`)
   hay que mirarlo uno por uno.
5. Recien con 1-4 hechos en TODOS los repos que peguen contra ese proyecto:
   `Disable JWT-based API keys`. **Ya no esta bloqueado por el Storage** (punto 3). Lo que
   falta: que el dueno cambie el secret `SUPABASE_SERVICE_KEY` de Planify por una
   `sb_secret_` y mire ese primer build, y que ningun cliente siga mandando la anon legacy.
   El boton lo aprieta el dueno, no Claude: apaga la `anon` que usa el frontend.

### Paso opcional: rotar el JWT secret

Sirve si ademas se sospecha del secret en si. Va en **Settings -> JWT Keys**
(`/dashboard/project/_/settings/jwt`), NO en la pagina de API Keys:

1. `Migrate JWT secret` - importa el secret viejo y crea una clave asimetrica standby. Sin downtime.
2. `Rotate keys` - la standby firma los JWT nuevos. NO desloguea a nadie: los tokens no
   vencidos se siguen aceptando.
3. Revocar el secret legacy, que queda en *Previously used*.

Dos avisos de la doc antes del paso 2:
- *"Make sure your app does not directly rely on the legacy JWT secret. If it's verifying every
  JWT against the legacy JWT secret (using a library like jose, jsonwebtoken or similar),
  continuing with the rotation might break those components."*
- *"If you're using Edge Functions that have the Verify JWT setting, continuing with the
  rotation might break your app. You will need to turn off this setting."*

Cuando revocar: esperar el tiempo de expiracion del access token + 15 min (1 h 15 min si es de
1 h) para no desloguear a nadie; en un incidente activo, revocar de inmediato.

**Al tocar cualquier archivo con una clave de Supabase, dejarlo en el sistema nuevo. Nunca
escribir codigo nuevo con la clave legacy.**

## 🪨 Modo Caveman (SIEMPRE activo)

**Cada conversación abre con caveman activo por defecto.** Responder en modo **caveman**:
frases cortas, directas, mínimas palabras, sin relleno. Solo aplica al **chat** (no al
código, comentarios ni mensajes de commit).

- **`desactiva caveman`** = responder solo el **próximo mensaje** normal/completo, y después **volver solo** a caveman.
- **`caveman desactivacion total`** = apagar caveman por completo (queda desactivado hasta que se reactive).

### 📏 EL LARGO DE LA RESPUESTA (regla del usuario, 2026-09-08, textual)

**"Me mandaste un mensaje eterno para que lea, imposible que te lea. Tus mensajes, por más de
que vos hagas tu trabajo interno, a lo último tenés que mandar un resumen conciso y breve para
que pueda leer solamente eso y no tener que leer todo tu proceso de análisis."**

- **El análisis se hace, pero NO se escribe.** Consultas, cruces, verificaciones: todo eso queda
  adentro. Lo que llega al chat es la **conclusión**.
- **Apuntar a ~10 líneas.** Si no entra, es porque se está contando el camino en vez del
  resultado. Sacar el camino, no el resultado.
- **Nada de volcar tablas de 20 filas, listados completos ni el paso a paso de cómo se llegó.**
  Si el detalle hace falta, va a un **archivo** (`.md` / `.xlsx`) y en el chat va **el link y una
  línea**. Ese es el lugar del detalle, no el chat.
- **Estructura fija:** (1) la respuesta en una o dos frases; (2) lo que hay que decidir o el
  número que falta; nada más. Los "hallazgos de paso" van al archivo o a `IDEAS-GP2.md`, no al
  mensaje.
- Vale igual cuando el hallazgo es grande o entusiasma: **un hallazgo grande se dice en una
  línea**, no en tres tablas.

## 🏠 Filosofía GP2: "la casa del vecino" (LEER SIEMPRE — analogía guía)

**Analogía base para todo el proyecto GP2 (usarla en todos los chats):**

- **`public` = la casa del vecino.** Es el programa viejo "Gestión Productiva Entero", ya
  construido y funcionando. NO es nuestra casa. NO se copia. NO se toca (solo lectura).
- **`GP2` (schema propio en Supabase) = mi casa.** La estamos construyendo de cero,
  **independiente** de la del vecino.
- **La regla de oro:** construimos mi casa **mirando la LÓGICA de cómo el vecino hizo la
  suya**, NO copiando su casa. Tomamos las ideas/lógica (cómo modela producción,
  causa-efecto, PS, talleristas, stock), pero los datos y la estructura son 100% míos,
  nativos de GP2. Cero dependencia de `public`.
- **Cuándo mirar al vecino:** solo para **llenar huecos** — cuando a mi casa le falta una
  lógica que el vecino ya resolvió, miro cómo lo hizo y lo implemento a mi manera en GP2.
- **Estado limpio = "como te lo mandé en un principio":** las tablas GP2 deben quedar como
  el Excel original que cargó el usuario (art 84, componente 471, proveedor_servicio 8,
  tallerista 12, matriz 115, ruta 555, ruta_paso 2346, ubicacion 32, articulo_componente
  505, componente_bom 32, inventario 848 con stock 0 + 766 mínimos). Snapshot de referencia:
  el `var D` embebido en los 3 HTML originales del usuario (`Registro_Movimientos.html`,
  `Programa_Stock_Loekemeyer.html`, `Faltantes_Loekemeyer.html`, que NO están en el repo) = ESA
  foto limpia.
- **NO inventar / NO asumir:** nunca crear datos de negocio inventados. Si falta un dato,
  marcarlo pendiente/null y que lo aporte el usuario. Agregar cosas nuevas a la casa se hace
  **deliberadamente**, no contaminando las tablas base.
- **El motor de inventario vive en la BD**, no en el JS: la app inserta filas crudas en
  `GP2.movimiento` y los triggers (`fn_movimiento_calc` + `fn_movimiento_aplicar`) calculan
  y aplican el delta en `GP2.inventario`. El `var D` de los HTML mapea 1:1 a tablas GP2
  (los contratos de los bundles y los nombres reales de las tablas están en `GP2_MAPA.md`).

## Campos de carga: letra grande + teclado numérico (OBLIGATORIO)

**Regla del usuario (2026-08-30): "Siempre quiero letras bien grandes y legibles para que
alguien que ve mal pueda escribir y no equivocarse. Donde van números, solo teclado numérico."**

En TODA pantalla, nueva o tocada:
1. **Letra grande en los campos**: mínimo 18px en inputs/selects (piso global en
   `gp2-modulo.css`); los campos importantes de carga (cantidades, pesos) mejor 19–20px.
   Nunca bajar de eso en el CSS propio de una pantalla.
2. **Teclado numérico donde van números**: todo `<input>` que recibe un número lleva
   `inputmode="numeric"` (enteros) o `inputmode="decimal"` (con coma). Vale también para
   los `type="number"` (el atributo garantiza el teclado correcto en el celular).
3. Etiquetas visibles al lado del campo, no solo placeholder (el placeholder desaparece
   al tipear y quien ve mal pierde la referencia).
4. **La letra grande NO puede romper la prolijidad** (dicho del usuario: "que se
   entienda que se puede tocar bien en todos lados sin que algo se vea feo — UX/UI
   súper prolija"). Al agrandar: las tablas anchas van dentro de `.table-wrap`
   (scrollean solas, la página nunca scrollea horizontal), los inputs de tabla llevan
   ancho explícito para no reventar la columna, y después de tocar tamaños se
   verifica el render en 390px (sin desbordes, sin solapamientos, touch ≥44px).
5. El test `tests/ui/test_teclado_numerico.js` lo vigila: falla si aparece un
   `type="number"` sin `inputmode`.
6. **La regla de número es una sola y vive en `gp2-numero.js` (`GP2N`)** — el punto es
   separador de miles, la coma el decimal, y el separador se pone automático a partir de
   cuatro dígitos. Una pantalla que lo carga ya tiene el formato en todos sus campos.
   **Nunca escribir un saneador de número propio**: `tests/ui/test_numero.js` lo rechaza.

## Helpers de pantalla y cliente Supabase: UNA copia (OBLIGATORIO desde 2026-09-05)

Ninguna pantalla GP2 escribe su propio `esc()`, `$()`, "hoy", exportador CSV ni
`createClient`. Existen una sola vez y hay tests que fallan si vuelve a aparecer una copia:

1. **`gp2-ui.js` (`GP2UI`)**: `esc`, `$`, `cls` (pos/neg/cero), `hoyAR()` (la fecha de HOY en
   Argentina; `toISOString().slice(0,10)` es UTC y después de las 21:00 da el día siguiente),
   `fechaAR(iso)` (dd/mm/aaaa), `exportarCSV(nombre, filas)` (`;`, BOM, coma decimal).
2. **`gp2-numero.js` (`GP2N`)**: `num` / `entero` para leer un campo, `fmt(n, dec, sinValor)`
   para mostrar. Donde está cargado, ningún `.value` se lee con `Number()`/`parseInt()` crudo
   (el campo se ve con separador de miles y "1.500" daría 1,5) y no hay `toLocaleString`
   propio.
3. **`GP2_SB()` (en `supabase-config.js`)**: el cliente GP2 (schema `GP2`, sin sesión
   persistida). `var SB = GP2_SB();` — nunca `supabase.createClient(...)` en una pantalla.
4. **Orden de carga**: `supabase-config.js` → `gp2-ui.js` → `gp2-numero.js` → los JS
   compartidos que dependen de ellos (`gp2-envios-common.js`, `gp2-composicion.js`,
   `gp2-stock-sector.js`, `consumo-detalle.js`) → el script de la pantalla.
5. Guardianes: `tests/ui/test_helpers_ui.js` (helpers, orden, copias, cliente),
   `test_numero.js` (regla de número, parses crudos, formateadores propios),
   `test_smoke_gp2.js` (abre las 47 pantallas con Supabase stubeado: falta un script o
   revienta un helper → falla) y `test_contratos_db.js` (toda `rpc('x')` / `from('x')` de las
   pantallas existe en `db/`, cada columna pedida en `from().select()` existe, cada clave `p_*`
   es un parámetro real de la función y no falta ninguno obligatorio: si falla porque `db/`
   está viejo, se regenera `db/`).

## Versionado (OBLIGATORIO en cada actualización)

**Cada vez que se modifica el JS/CSS/HTML de un módulo, bumpear la versión en el mismo commit.**
Las tablets y celulares cachean fuerte; sin bump siguen corriendo la versión vieja.

1. Subir el `?v=` de los `<script src="...?v=X.Y.Z">` y `<link href="...?v=X.Y.Z">` del HTML del módulo.
2. **La app de operarios NO muestra número de versión** (el usuario lo pidió sacar,
   2026-08-31): el badge `#syncBadge` es solo el estado de la cola (`✓ al día` / `⚠ N sin
   enviar`). Lo único versionado del operario es el `?v=` de su `<script>` (para el
   auto-recargador) y el `MI_V` del HTML tiene que quedar con **ese mismo token** — el
   `test_tokens_cache` lo vigila y verifica que no reaparezca una versión en pantalla. Nunca
   volver a poner un `const APP_VERSION` ni un `GP2 vX.Y.Z` en el operario.
3. Convención: fix chico = patch (1.2.0→1.2.1), feature = minor (1.2.0→1.3.0).
4. Si el HTML no tiene `?v=` en sus recursos externos, agregárselo al tocarlo.
5. **`version.js` (versión global) también se bumpea.** Es la que ve el usuario en el cartel
   "Versión vX.Y.Z" del login, `GP2_MODULOS.html`, `envios-only.html` y `Relevamiento`.
   (`Inicio/index.html` ya no muestra nada: hoy es un redirect de 14 líneas a
   `GP2_MODULOS.html`, que es quien carga `version.js`.)
   Al soltar features, subir `window.APP_VERSION` **y** el `?v=` de los `<script src="version.js?v=...">`
   (si no se bumpea el `?v=`, el celular sigue con el archivo viejo cacheado y muestra la versión de antes).

## 🧭 Otros archivos vivos que hay que conocer

- **`db/A_Costos_VIGENTES.xlsx` — LA PLANILLA DE COSTOS DEL USUARIO YA ESTÁ GUARDADA. NO PEDIRLA.**
  Vive en dos lugares: el archivo en el repo (esa ruta, 59 hojas) y su contenido en la base
  (`GP2.planilla_fila`, 16 hojas de costos; consultar por `GP2.v_planilla_precio` — lista de
  precios por proveedor/cod ISIS — y `GP2.v_planilla_costo` — hoja Costos con fórmulas). El
  usuario la subió "muchísimas veces" porque las sesiones no sabían que estaba (2026-09-10): una
  sesión que la necesite la lee de ahí. Si el usuario manda una versión nueva, se reemplaza el
  archivo en esa misma ruta y se refresca el snapshot (`planilla_snapshot_nuevo` +
  `planilla_cargar`, ver CONOCIMIENTO §4v).
- `GP2_MAPA.md`: contratos de los `*_bundle` y nombres reales de tablas/columnas (mirar antes de
  tocar una pantalla que hable con GP2).
- `REFACTOR_GP2.md`: bitácora de la auditoría de arquitectura del 2026-09-04 (qué se borró, qué se
  fusionó, por qué). `PREGUNTAS_ARQUITECTURA_GP2.md`: las dudas de negocio que salieron de ahí y
  esperan respuesta del usuario; si el usuario contesta alguna, aplicar y tachar.
- `db/`: respaldo del schema (tablas, funciones, vistas). Regenerarlo al terminar una sesión que
  cambió la base. **`db/verificar.sql`**: los invariantes de la base en una consulta (cada fila
  debe dar `n = 0`); correrla antes de tocar la base y al cerrar, y si algo da > 0 es lo primero
  que se arregla.

## 🧠 CONOCIMIENTO_GP2.md — la memoria del negocio (LEER AL INICIO, ESCRIBIR SIEMPRE)

**Leer `CONOCIMIENTO_GP2.md` al arrancar cada sesión, junto con este archivo.** Ahí está
el conocimiento del negocio que el usuario ya explicó alguna vez: quién provee qué, por
qué se decidió cada cosa, qué conviene y qué no, y las trampas que ya nos mordieron.

**Regla de captura (OBLIGATORIA):** cada vez que el usuario explique **cómo funciona algo,
por qué se hace así, quién hace qué, o qué decidió**, eso se agrega a `CONOCIMIENTO_GP2.md`
**en el mismo commit del trabajo** — no se espera a que "cierre el tema". Marcar el origen:
`[usuario]` lo dijo una persona, `[dato]` sale de una consulta (decir cuál), `[deducido]`
lo infirió el agente y está **sin confirmar**. Si un dato nuevo contradice uno viejo, se
corrige la línea y se anota la corrección: casi siempre significa que cambió la realidad y
hay que revisar el módulo que dependía de ese dato.

**El objetivo es que el usuario NO tenga que volver a explicar.** El agente
`.claude/agents/gp2-experto.md` usa ese archivo para hacer de contraparte: cruzar una idea,
decir si cierra con lo ya decidido y proponer alternativas. Invocarlo cuando haya que
**decidir** algo del negocio (no para tareas mecánicas). Si `CONOCIMIENTO_GP2.md` no crece,
el agente no sirve.

## Agente diario de mejoras + IDEAS-GP2.md (reglas para CUALQUIER chat)

Corre solo, todos los días a las 6:00 (AR), en una sesión nueva. Audita el repo (suite,
render 390px, deuda, docs desviadas) y registra ideas con **código de 4 dígitos** en
`IDEAS-GP2.md` **en main** (SIN ramas — regla del usuario 2026-08-30: "no quiero
ramas, solo en main"). Los fixes chicos y seguros los hace DIRECTO en main, con la
suite completa en verde antes de pushear, y los anota como hechos. Si no encuentra
nada, dice "Sin novedades" y no molesta. Aviso push al usuario al cierre.

**Comando `:`** — si el usuario escribe `:`, leer `IDEAS-GP2.md` y mostrar las ideas
`pendiente` como checklist de a 5, para que tilde.

**Idea aceptada** ("dale 4837" o tildada): desarrollarla AHORA directo en main,
verificar (suite en verde) y pushear. Después marcar la línea en IDEAS-GP2.md
(`[x]` hecha, o `~~tachada~~` descartada). Las ideas que escribe el usuario en el
chat también se registran ahí (mismo formato, para que no se pierdan).

## Perfiles de Usuario (LEER AL INICIO)

**Al arrancar cada sesión, leer `PERFILES.md` para saber con quién estás trabajando.**
El usuario se identifica por el nombre de usuario de Windows (mismo que usa el sistema de locks).
Adaptar el trato, nivel de detalle y módulos según el perfil del usuario.

## Renombres de Sectores (carga de stock_inicial)

**Al cargar `stock_inicial` desde Excel a `Partes x Tallerista`, leer `Renombres_Sectores.md`** —
contiene mapeos confirmados de codigos viejos del Excel a sectores actuales en BD
(p.ej. E11→D1, A2→PA2, EP2/3→PEP4). Antes de preguntar por discrepancias, chequear ahí
si ya existe el mapeo. Cuando el usuario confirme un renombre nuevo, agregarlo al archivo.

## Sistema de LOCKS (OBLIGATORIO - LEER PRIMERO)

**REGLA #1: NUNCA usar Edit ni Write sin antes leer LOCKS.txt y registrar tu LockX.**
**REGLA #2: NUNCA liberar un LockX sin revisar la WAIT QUEUE.**
**REGLA #3: Si te olvidas de los locks, el usuario te va a corregir. No dejes que pase.**

**Esta carpeta es compartida entre varias personas con Visual Studio Code + Claude.**
**Antes de tocar cualquier archivo, usar el sistema de locks en `LOCKS.txt`.**

### Protocolo de locks (como SQL Server):

| Lock | Significado | Compatible con |
|------|------------|----------------|
| LockS | Lectura/analisis para planificar cambios | Otros LockS (NO con LockX) |
| LockX | Edicion exclusiva del archivo | NADA (ni LockS ni LockX) |

### Identificacion: usar el nombre del usuario de Windows como identificador en los locks.

### Flujo NORMAL (archivo libre):

1. **Leer `LOCKS.txt`** seccion [LOCKS] - Verificar que el archivo NO tenga locks ajenos.
2. **Registrar tu LockX** en [LOCKS]: `LockX | ruta/archivo | tu-id | fecha hora | que vas a hacer`
3. **Re-leer el archivo** justo antes de editarlo (puede haber cambios recientes).
4. **Hacer la edicion** con Edit tool (ediciones minimas, nunca reescribir completo).
5. **Al terminar:**
   a. Revisar si hay alguien en [WAIT QUEUE] esperando por tu archivo.
   b. Si hay alguien esperando: cambiar su linea WAIT a READY.
   c. Borrar tu LockX de [LOCKS].
   d. Agregar linea en [HISTORIAL] con lo que hiciste (mantener max 10).

### Flujo con ESPERA (archivo bloqueado):

1. **Leer `LOCKS.txt`** -> El archivo tiene un LockX ajeno.
2. **Registrar WAIT** en [WAIT QUEUE]: `WAIT | ruta/archivo | tu-id | fecha hora | que necesitas hacer`
3. **Informar al usuario** que el archivo esta bloqueado y que quedo en cola de espera.
4. **Si hay otros archivos libres** del mismo pedido, trabajar en esos mientras tanto.
5. **Revisar periodicamente** (cada vez que termines otra tarea) si tu WAIT cambio a READY.
6. **Cuando veas READY:**
   a. **RE-LEER el archivo completo** (tiene cambios del lock anterior!).
   b. **Adaptar tu trabajo** a los cambios nuevos que encuentres.
   c. Borrar la linea READY, registrar tu LockX en [LOCKS].
   d. Ejecutar tu edicion.
   e. Repetir el paso 5 del flujo normal (revisar wait queue, liberar, historial).

### Reglas adicionales:
- Editar solo lo minimo necesario. No reformatear, no reordenar, no "mejorar" codigo no pedido.
- No tocar archivos fuera del alcance del pedido.
- Prioridad en wait queue: FIFO (primero en registrarse, primero en ejecutar).
- Si un lock lleva mucho tiempo (>30 min), avisar al usuario que puede estar obsoleto.
- NUNCA borrar lineas de locks ajenos sin autorizacion del usuario.

## Completar tablas manteniendo la NORMALIZACIÓN (ORDEN PRIMORDIAL)

**Cuando cambia un proceso o producto GP2 (qué partes lleva, quién arma, quién entrega),
actualizar TODAS las tablas normalizadas que lo describen, en ESTE orden, sin saltear ninguna:**

1. `componente` — altas/bajas de piezas. Antes de inventar un código, mirar la convención
   existente de la tabla (los cartones usan posición de estantería, los flejes "Fleje N°", etc.).
2. `inventario` — fila para el componente nuevo en su ubicación (cantidad 0).
3. `articulo_componente` y `componente_bom` — las recetas.
4. `ruta` / `ruta_paso` — los pasos, respetando las convenciones de nombres y el duplicado
   de ruta por tallerista cuando hay más de uno que hace el mismo paso.
5. `contraparte_alias` / espejo Virgilio — si cambia quién entrega.

Nunca parchar una sola tabla ni meter datos desnormalizados: una ruta que no cierra con la
receta, o una receta con componentes que ninguna ruta produce, rompen trazado y stock.
Ejemplo de referencia: reestructuración del artículo 506 (2026-08-29, ver HISTORIAL/git).

## Tablas Madre y Derivadas (OBLIGATORIO - LEER ANTES DE TOCAR SUPABASE)

**Antes de hacer INSERT, UPDATE o DELETE en Supabase, verificar en esta seccion si la tabla es MADRE o DERIVADA.**
**Si es DERIVADA, NO modificarla directamente. Ir a la tabla MADRE correspondiente.**
**Si no estas seguro, PREGUNTAR al usuario antes de ejecutar.**
**Referencia completa: `Tablas_Madre_y_Dependencias.xls` en la raiz del proyecto.**

### Cadena de Pesos (Kg x Uni / Kg x Cajon)

```
TABLAS MADRE (donde se carga):
  SP Kg          → sectores procesados (Sp, Kg X Uni, KG x Cajon)
  SC Kg          → sectores crudos (SC, Kg X Uni, KG x Cajon)
  SectorPlasticos → plásticos (Sector, Kg x Uni, Uni x Bolsa)
  Remaches SP/SC → remaches

TABLAS DERIVADAS (se sincronizan solas, NUNCA modificar directo):
  Despiece x Articulo  → KGxUni, Kg x Caj (sincronizado por funcion actualizar_despiece)
  Partes x Tallerista  → kgxuni, kg_x_caj (sincronizado por trigger desde Despiece)
```

**⚠️ Si alguien pide cargar pesos en `Despiece x Articulo` o `Partes x Tallerista`, AVISAR que se van a sobreescribir. Cargar en SP Kg o SC Kg segun corresponda.**

**⚠️ NUNCA vaciar (DELETE masivo / TRUNCATE) tablas madre.** Las tablas madre contienen datos maestros que alimentan tablas derivadas via triggers. Vaciarlas rompe toda la cadena de sincronizacion. Tablas madre protegidas: `SP Kg`, `SC Kg`, `SectorPlasticos`, `Matrices`, `Articulos Virgilio X Tallerista`, `Partes x PS`. Si el usuario pide vaciar alguna, ADVERTIR el impacto antes de ejecutar.

Orden de busqueda de `resolver_pesos_por_sector`: SP Kg → SC Kg → SectorPlasticos → Flejes → Remaches SP → Remaches SC (LIMIT 1, el primero que encuentre gana).

### Cadena de Talleristas

```
TABLA MADRE: Articulos Virgilio X Tallerista (Tallerista, Cod_Art, Desc)
DERIVADA:    Partes x Tallerista (se reconstruye por trigger INSERT/UPDATE/DELETE)
VISTAS:      v_piezas_por_tallerista → v_piezas_por_tallerista_resumen
```

### Cadena de Produccion

```
TABLA MADRE: Matrices (N_Matriz, Tiempo_Historico)
DERIVADA:    db_n8n_espejo → Segundos_Historico, Premio (via RPC recalcular_matriz)
AUDITORIA:   Matrices_audit (trigger fn_audit_matrices)
```

### Tablas de Movimientos (NO son derivadas, se escriben directamente)

| Tabla | Modulo que escribe |
|---|---|
| Envios a PS | Control PS, Facturas (carga manual) |
| Entregas PS | Control PS, Facturas (carga auto/manual) |
| Envios a Talleristas | Envio Talleristas |
| Entregas Tallerista Virgilio | Recepcion Cervantes/Virgilio |
| db_n8n_espejo | App Produccion, n8n |

### Partes x PS (tabla de configuracion, se modifica directamente)

Al modificar SC o SP en `Partes x PS`:
1. Verificar que el nuevo sector exista en SP Kg y/o SC Kg con sus pesos
2. Si no existe, CREARLO en la tabla madre antes de hacer el cambio
3. Revisar impacto en: Control PS, Stock SC, Stock SP, Stock Transito, Stock General, Plasticos

## Stack tecnologico

- Frontend: HTML/CSS/JS vanilla (sin framework)
- Backend/DB: Supabase (PostgreSQL) con JS client v2 desde CDN
- Auth: login.html + auth-guard.js con sessionStorage
- Tablas principales: `db_n8n_espejo`, `Empleados`, `Matrices`, `Registros Produccion Cervantes`
- Edge Functions: WhatsApp alertas, lectura facturas
- Server: Live Server en puerto 5501

## Estructura de carpetas

Cada modulo es una carpeta con su propio HTML/JS/CSS. Los modulos principales:
- `Produccion/` - Registro de produccion (app.js, maestro.html, abm.html)
- `Disruptivas/` - Producciones con premio anomalo (disruptivas.js)
- `Informes/` - Reportes
- `Inicio/` - Dashboard principal
- `Verificacion/` - Trazado de Rutas (REESCRITO 2026-04-18, ver abajo)

## ⚠ REGLA: qué tipo de operario ve qué botón (app de operarios / tablet)

**El operario no ve todos los botones: ve los de SU rol, y el rol vive en la BASE, no en el
código.** Las columnas están en `public.Empleados`, una fila por legajo: `es_matriceria`,
`es_piedra`, `es_alimentador`, `ve_cm`, `ve_trm`, `ve_tl`, `ve_rem`, `ve_mm`, `ve_ctm`, `ve_am`.
La implementación canónica es `capsDe()` + `botonVisible()` de `app.js` en el repo
`loekemeyer/Registro-Produccion-2.0` (v1.9.0): antes de agregar, sacar o mostrar un botón en
cualquier app de operarios, mirar esas dos funciones.

| Rol (cómo se reconoce) | Qué botones ve |
|---|---|
| **Balancín** = operario base, ningún flag prendido | E, C, PB, BC, LIMP, Perm, AL, PC, PM, RM, PCM + **MOV** |
| **Alimentador** (`es_alimentador`) | lo mismo + **PR**, **RD** y **CM** (el flag ya implica CM) |
| **Piedra** (`es_piedra`) | lo mismo pero **MOV P** en lugar de MOV; + **MM** si `ve_mm` |
| **Matricería** (`es_matriceria`) | **sólo** TRM (`ve_trm`), TL (`ve_tl`), REM (`ve_rem`) y CM (`ve_cm`). Ningún botón normal, ni siquiera E o C |
| Cualquiera con `ve_cm` | agrega **CM** aunque no sea alimentador (caso real: David Ayala, legajo 233, es de piedra) |

El orden importa: `botonVisible()` pregunta **primero** por matricería, así que un matricero con
otro flag prendido igual ve nada más que sus cuatro botones.

Tres cosas que no se negocian:

1. **Nunca ramificar por legajo.** Si un operario tiene que ver algo distinto, es un flag en
   `Empleados`, no un `if legajo === "19"`. El día que esa persona cambia de puesto o se va,
   el `if` queda mintiendo y nadie se entera.
2. **Botón nuevo = flag nuevo en `Empleados` + su casilla en el ABM de operarios**, en el mismo
   commit. Un flag sin código (o al revés) es una promesa que la app no cumple: hoy pasa con
   `ve_ctm` (botón CTM, Control Matriz) y `ve_am` (botón AM, Ayuda Matricería), prendidos los dos
   para Oscar Bordon (legajo 282) y **sin una línea de código en ningún repo**.
3. **CM (Cambiar Matriz) es tiempo muerto**: el 1er toque lo abre —pide matriz nueva y en qué
   balancín, y asigna la matriz al balancín en `public.Balancines`— y el 2do lo cierra midiendo
   la duración. No es un evento puntual. Los que no son tiempo muerto son E, C, RM, RD y LT.

**Estado al 2026-09-23 de la tablet de operarios de GP2** (`Produccion/RegistroApp/`,
`operarios_gp2.js` + `Registro_GP2.html`): **no aplica nada de esto todavía**. Muestra la misma
lista de botones a todo el mundo, no lee ningún flag, y ramifica por `LEGAJO_EDUARDO = "19"`
hardcodeado (le agrega el botón CT y le cambia el comportamiento de PR) — justo lo que el punto 1
prohíbe. Además le faltan CM, RD y REM, sacados el 2026-08-29 por uso histórico bajo. Cuando esa
pantalla vuelva a tocar botones, se arranca por acá.

## Verificacion - Trazado de Rutas (reescrito 2026-04-18)

Modulo unificado para trazar rutas productivas y validar integridad. Reemplaza el viejo
sistema con multiples botones (Ejecutar Verificacion, Constructor, Rutas Nuevo, etc.)
por un unico flujo:

**Logica de trazado** (DFS desde cada Fleje):
1. Sigue `Causa-Efecto` (Descuenta -> Aumenta via Matriz). Si Matriz es nombre de
   tallerista (Carlos, Martin, "Martin, Carlos"), se trata como tallerista no matriz.
2. Sigue `Partes x PS` (SC -> PS via Proceso, devuelve SP). Agrupa PS que hacen mismo
   proceso al mismo SP (ej. "Daniel / Jade").
3. Termina en `Partes x Tallerista` cuando sector_proce coincide con un tallerista.
4. ST como SP devuelto (Sector Transito): muestra descripcion del paso anterior +
   nombres de PS en transito (ej. "Cuchilla Pelapapa Doblada + New Metal/FAAT").
5. Aumenta=Fabr indica fabricacion interna (terminacion de ruta).

**4 tabs**:
- Trazar Rutas: rutas nuevas pendientes de revision.
- Rutas Confirmadas: las que diste OK. Persistidas en tabla `Rutas_Confirmadas`.
- Revisar despues: marcadas con boton 📌 sin describir motivo. Tabla `Rutas_Problemas`
  con `problema = '(pendiente de revisar)'`.
- Problemas: reportadas con ⚠ y descripcion. Misma tabla, otro filtro.

**Tablas auxiliares** (creadas 2026-04-18):
- `Rutas_Confirmadas` (id, fleje, descripcion, ruta_json, firma UNIQUE, confirmado_por,
  confirmado_en).
- `Rutas_Problemas` (id, fleje, descripcion_fleje, ruta_json, firma, problema,
  estado pendiente|resuelto, reportado_por, reportado_en, resuelto_en).
- Firma = "F:<fleje>|tipo:label|tipo:label|..." sirve para deduplicar rutas iguales
  entre re-trazados.

**Reportes/auditorias**:
- `AUDITORIA_RUTAS_2026-04-18.md` (raiz proyecto): inconsistencias detectadas.

## Patron de armado de productos: GRJ (Garaje)

Los GRJ (GRJ1, GRJ7, GRJ9, GRJ10, etc.) son productos intermedios armados por talleristas
(generalmente Martin y/o Carlos). Cada GRJ tiene componentes que se descuentan al
entregarlo en `Recepcion Cervantes.html`.

Configuracion en 2 lugares (mantener sincronizadas):

1. **`Talleristas/Recepcion/Recepcion Cervantes.html`**:
   - `GRJ_COMPONENTES = { GRJ7: ["A10","C10","V9"], GRJ10: ["Fleje31","Fleje32","LLF7B","LLF8"], ... }`
   - `GRJ_PESOS = { GRJ7: 0.033567, GRJ10: 0.068882, ... }`
   - `ARTICULOS_EMPRESA = { CARLOS: { LK: ["GRJ7","GRJ9","GRJ10"] }, MARTIN: ... }`

2. **Supabase**:
   - `Articulos Virgilio X Tallerista`: una fila por (Tallerista, Cod_Art=GRJX, Desc=componente)
   - `SP Kg`: el GRJ como Sp con peso total
   - `Despiece x Articulo`: el GRJ aparece como Sector Proce en el cod_art final

**Pendiente al 2026-04-18**: GRJ16 (Batidor Mini 580) creado en SP Kg pero falta
componentes/CE/asignacion (ver AUDITORIA_RUTAS_2026-04-18.md punto 7).

## Causa-Efecto: convenciones

- `Descuenta` y `Aumenta` deben ser sectores conocidos o "Fleje N" o "Mat N".
- `Matriz` puede ser:
  - Numero (ej. "62"): se renderiza como "Matriz 62" y busca su nombre en `Matrices.N_Matriz`.
  - Nombre de tallerista (ej. "Carlos", "Martin, Carlos"): el JS de trazado lo reconoce y
    lo pinta como 👷 tallerista (no como ⚙️ matriz).
  - "Fabr": fabricacion interna (sin tallerista ni matriz especifica).
- **NO usar formato "Matriz N" en Descuenta/Aumenta** — usar "Mat N" para que el sistema lo
  trate como nodo intermedio. Si aparece "Matriz N" como nodo, son inconsistencias (ver
  AUDITORIA_RUTAS_2026-04-18.md punto 5).

## OC Insumos (GP2) - CONSTRUIDO 2026-08-29

**Las reglas de pedido por tipo de insumo estan en `REGLAS_OC_INSUMOS.md` (raiz) y
parametrizadas en `GP2.carton_formato` / `carton_categoria` / `proveedor_insumo.modo_control`.
Leer ese archivo antes de tocar el modulo de OC.**

- **El modulo existe**: `Compras/OC_GP2.html` genera las OC con
  **sugerido = maximo - stock** (desde el 2026-09-03; ANTES era consumo x meses y la doc
  quedo desactualizada un dia; el "- pendiente OC" se saco el 2026-09-04 por pedido del usuario,
  "por ahora borralo": `oc_bundle` hoy NO resta lo que ya viene en camino). El `maximo` sale de
  `inventario.maximo`, y **solo si esta vacio** cae al consumo (Est Madre explotada:
  `v_consumo_componente` / `v_consumo_fleje_kg` en kg para flejes) x meses, marcado
  `maximo_origen='consumo_x_meses'`. **Asi se decidio y asi se queda** [usuario 2026-09-04:
  "llena el lugar (maximo segun norma de cada rubro)"]: el sugerido llena el maximo, y la
  norma del rubro (multiplos y minimos de carton, paquetes de 100 en pliegos, piso de
  bolsas, paquetes de Charcas — `parametro.charcas_kg_x_paquete`, hoy 10 kg; la OC se guarda
  en kg) se aplica DESPUES, redondeando para arriba.
  Primero el lugar, despues el envase. Tablas `GP2.orden_compra` / `orden_compra_item`,
  RPCs `oc_bundle` / `crear_oc` / `oc_marcar` / `abm_bom_guardar`. Cada OC se puede IMPRIMIR
  (hoja limpia para el proveedor). Estados: borrador -> enviada -> recibida / anulada.
- **La recepcion CRUZA contra OC**: `crear_recepcion_insumo` aplica lo recibido al campo
  `recibido` de las OC abiertas (FIFO, conversion kg/uni) y marca la OC `recibida` sola.
  La pantalla de Recepcion muestra el cruce.
- **La validacion de cartones (multiplos C/LOKE/8) esta VIVA** (verificado 2026-09-08): los 110
  cartones tienen `componente.carton_formato` y el tipo C ya tiene `carton_categoria` cargada
  (Abrelatas 6, Pelapapas 4, Resto 16, Sacacorchos 6). Familia = formato+marca+categoria,
  multiplos, minimo por codigo, comodin sacacorchos, pliegos de 100 y piso de bolsa 20.000
  funcionan y los cubre `test_oc.js`. (Hasta el 2026-09-08 esta linea decia que estaba DORMIDA
  "hasta que el usuario asigne el formato": era falso y hacia perder tiempo.)
- El viejo `StockFlejes/recepcion.html` (importar PDF del proveedor) es del programa viejo;
  el flujo GP2 no importa PDFs.

## Reglas para trabajar en este proyecto

- ANTES de tocar tablas madre, leer LOCKS.txt, registrar LockX.
- Triggers de sincronizacion: ver Tablas_Madre_y_Dependencias.xls.
- ST como sector SC en Partes x PS = Sector Transito (PS recibe pero no devuelve SP final,
  se manda al siguiente PS). Es valido pero el codigo "ST" se usa en muchos contextos —
  no asumir descripcion generica.

## Supabase

- URL: `https://hrxfctzncixxqmpfhskv.supabase.co`
- La tabla `db_n8n_espejo` es la principal de produccion. Campos clave:
  - `Legajo`, `Matriz`, `Nombre_Matriz`, `Uni`, `Fecha`
  - `Hora_Inicio`, `Hora_Fin`, `Segundos_Trabajados`, `Segundos_Tiempo_Muerto`
  - `Segundos_Historico`, `Premio`, `Tiempo_Toma`, `Tiempo_Historico`
  - `Eliminar` (soft delete = 'S'), `Revisado`, `Anular_Tiempo`
  - `ID_Ejecucion`, `Dia`, `Mes`
- La tabla `Empleados` tiene campo `Activo` (valor "SI" para activos)
- La tabla `Matrices` tiene `N_Matriz`, `Matriz` (nombre), `Tiempo_Historico`

## REGLA: toda copia de respaldo nace sin RLS

**Vale para TODOS los repos** (igual que las reglas de Planify y de auditoria: copiar este bloque
al `CLAUDE.md` de cualquier repo nuevo).

**⚠️ `CREATE TABLE AS` y `SELECT INTO` NO heredan Row Level Security de la tabla de origen.** La
copia queda con `relrowsecurity = false` aunque la madre este protegida, y los `GRANT` del schema
le siguen aplicando, asi que `anon` hereda SELECT/INSERT/UPDATE/DELETE. Postgres no emite ninguna
advertencia. **Prender RLS en el MISMO paso en que se crea la copia**, no despues:

```sql
create table <schema>.<copia> as select * from <schema>.<madre>;
alter table <schema>.<copia> enable row level security;  -- sin politicas = deny-all para anon
```

Sin politicas, RLS habilitada deja la tabla accesible solo para `service_role`, que es exactamente
lo que se quiere en un respaldo.

**Caso real (2026-09-14):** `planify.bkp_items_mayo_20260914`, respaldo de la liquidacion de sueldos
de mayo hecho —bien— antes de tocarla, quedo con 56 sueldos completos (legajo, nombre,
`sueldo_bolsillo`, banco, aportes) legibles y borrables por cualquiera con la clave publishable,
durante 24 horas. El respaldo estuvo bien; lo que falto fue el `alter`.

Para barrer copias abiertas en un proyecto:

```sql
select n.nspname, c.relname
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
 where c.relkind = 'r' and c.relrowsecurity = false
   and has_table_privilege('anon', c.oid, 'SELECT')
   and n.nspname not in ('pg_catalog','information_schema','pg_toast');
```

## ⚠ REGLA: por qué Claude pide permiso para TODO — y dónde se apaga de verdad

**Vale para TODOS los repos** (copiar este bloque al `CLAUDE.md` del repo nuevo, junto con el
bloque `permissions` de `.claude/settings.json`). Thomas, 2026-09-18: *"otras sesiones están
pidiendo muchísimos permisos para editar todo y antes no pasaba"*. Son tres cosas, en este orden.

### 1. Lo que MÁS pesa es el MODO de la sesión, y no se configura por archivo

En **Manual** (config value `default`) **sólo las lecturas corren solas**: todo lo demás pregunta,
haya o no regla de `allow`. En **Auto** corre todo con chequeo en segundo plano. El modo se elige
en el **selector de la sesión** (en la web, arriba del cuadro de mensaje) y se puede cambiar con
la sesión andando.

⚠ `permissions.defaultMode` con `"auto"` o `"bypassPermissions"` **se ignora** desde el
`.claude/settings.json` de un repo; sólo vale desde el settings de **usuario**, que en cloud no se
lee (punto 2). O sea: **en cloud, el modo se elige a mano y punto.** Una sesión en Manual va a
pedir permiso para todo por más lista que haya.

Cómo se reconoce: si te pide autorización hasta para un `select`, mirá el modo antes que el JSON.

### 2. La lista de permisos sale del `.claude/settings.json` DEL REPO — el único que llega

La doc de Claude Code lo dice sin vueltas:

> *"**User and project local settings** (`~/.claude/settings.json` and `.claude/settings.local.json`):
> **not read**. Both stay on your machine, and the local file isn't in the clone."*

Escribirlo desde el setup script del entorno **no sirve** para una sesión cloud. El 18/09 se perdió
medio día por creer lo contrario.

⚠ **Y hay una condición que tumba hasta eso:** el repo manda **sólo si la sesión tiene UN
repositorio**. Con varios adjuntos la sesión arranca **arriba** de los clones y de cada
`.claude/settings.json` toma únicamente los plugins y marketplaces — **ni permisos, ni hooks, ni
`env`**. Una sesión con 3 repos adjuntos pide permiso para todo y no hay archivo que lo arregle:
ahí el modo es lo único que queda.

### 3. Un `hooks` mal formado tira el archivo ENTERO, sin avisar

El formato viejo —`{"matcher":"", "command":"..."}`— ya no vale. Hoy va con el array `hooks`
adentro:

```jsonc
"hooks": { "PreToolUse": [ { "matcher": "",
  "hooks": [ { "type": "command", "command": "echo hola" } ] } ] }
```

Con el formato viejo Claude Code **descarta el `.claude/settings.json` completo**, así que la
`permissions.allow` deja de existir. No tira ningún error: simplemente no pasa nada. Así estuvo
este repo desde el commit `542ab7e` (16/09), y de yapa el hook de caveman nunca corrió ni una vez.

### ⚠ Cómo NO probarlo: `claude --print` adentro del contenedor

Ese `claude` es un CLI local: **sí** lee `~/.claude/settings.json` y **sí** exige el trust del
workspace (`~/.claude.json` → `hasTrustDialogAccepted`). La sesión cloud no hace ninguna de las
dos cosas. El 18/09 esa prueba dio verde tres veces seguidas mientras el usuario seguía
autorizando de a uno. **Se prueba en una sesión nueva de verdad**; el cartel dice el nombre de la
herramienta, y ése es el string que se agrega a `allow`.

### Lo que hay hoy en `.claude/settings.json`

`allow`: lectura/edición, subagentes, `WebFetch`/`WebSearch`, **`Bash` entero** y el SQL de
Supabase (`execute_sql`) más las herramientas de lectura de Supabase y GitHub.
`ask`: `git push`, `curl`, `wget`, `apply_migration`, `deploy_edge_function`.
`deny`: `rm -rf`, `sudo rm`, force-push, `git reset --hard`, `psql`, `supabase db`, leer `.env`.

⚠ Un `ask` matchea por **prefijo del comando**: `Bash(git push:*)` **no** agarra
`git -C /ruta push …`, que empieza con `git -C`. Medido el 18/09: por eso un push con `-C` salió
sin preguntar. Si un comando tiene que frenar sí o sí, va en `deny`, no en `ask`.

⚠ Que `execute_sql` no pregunte **no cambia la regla del 26/08**: los datos no se tocan sin
permiso explícito. Eso lo sostiene este archivo, no el diálogo de permisos.

`scripts/claude-permisos.sh` y `scripts/setup-entorno-claude.sh` quedan para las sesiones
**locales**, donde sí manda el settings de usuario y hace falta el trust. En cloud no hacen nada.

