# CLAUDE.md — Producción Virgilio

## 📌 LEER PRIMERO: `docs/ESTADO-Y-PENDIENTES.md`

**Foto del estado al 2026-09-13.** Qué falta de verdad está en la base
(`select * from github_repo_problemas.v_problemas where estado='abierto'`), pero ese archivo tiene
lo que la tabla NO cuenta: **qué decidió el dueño y no hay que revisitar**, **qué sólo puede
destrabar él** (redeploy de Vercel, rotar las credenciales de Meta y OpenAI) y **qué quedó a
medias**. Mantenerlo al día al cerrar cada tanda de trabajo.

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

## ⚠⚠⚠ REGLA: TRAER SIEMPRE LA DEFINICIÓN VIVA, Y USAR SIEMPRE LA TABLA VIGENTE

**Luis, 2026-09-17, después de que esto costara 4 tandas con el picking duplicado:**
*"QUE SIEMPRE TRAIGAN DEFINICIONES VIVAS Y ACTUALIZADAS ASÍ COMO TAMBIÉN QUE USEN LAS TABLAS
VIGENTES."*

**Vale para TODOS los repos** (LK, Chef, Gestión Virgilio, Planify y cualquiera nuevo: copiar
este bloque al `CLAUDE.md` del repo nuevo). Son dos reglas con la misma raíz: **lo que uno tiene
en la cabeza no es lo que está corriendo.**

### 1. Antes de `CREATE OR REPLACE`, traer la definición VIVA

**Nunca** partir de una copia propia, de un archivo del repo, ni de lo que se leyó hace un rato
en la misma charla. **Varias sesiones de Claude tocan los mismos objetos al mismo tiempo**, y un
`CREATE OR REPLACE` pisa el cuerpo entero sin decir una palabra.

```sql
-- SIEMPRE este, justo antes de escribir:
select pg_get_functiondef('public.<la funcion>'::regprocedure);
select pg_get_viewdef('public.<la vista>'::regclass, true);
-- y para una vista, ademas, las opciones (o te comes el security_invoker):
select relname, reloptions from pg_class where oid = 'public.<la vista>'::regclass;
```

Se le agrega el cambio **encima de eso**, y recién ahí se escribe.

**Lo que costó no hacerlo (problema 390, 17/09):** dos sesiones editaron
`trg_normalizar_empresa_stock()` el mismo día. La segunda partió de una copia anterior y borró la
regla *"en un código no dual la empresa la da el artículo"*. La tanda **D72A** —que se factura por
Chef pero lleva artículos de Loekemeyer— pasó a etiquetarse CH, el índice único no la reconoció
contra el LK del picking original, y **se duplicó el picking entero de 4 tandas**: +287 cajas
fantasma en Pickeados y −265 en góndola.

### 2. Y después PROBARLO, no leerlo

Leer la función que uno acaba de escribir no prueba nada: la que corre puede ser otra. Se hace un
`insert` de verdad contra la tabla real, se mira el resultado y se borra:

```sql
insert into public."Movimientos_Stock" (cod_art, deposito, delta, tipo, ref, legajo, empresa)
values ('501','separar_pedidos',0,'ajuste','__PRUEBA__','t','CH');   -- tiene que quedar LK
select cod_art, empresa from public."Movimientos_Stock" where ref = '__PRUEBA__';
delete from public."Movimientos_Stock" where ref = '__PRUEBA__';
```

Mismo criterio que ya vale para el armado de tandas: *"un cambio de regla de armado no está
probado hasta que se corre el armador"*.

### 3. Los dos centinelas, que avisan solos

```sql
select * from public.gv_reglas_perdidas;        -- vacía = ninguna regla se perdió
select * from public.gv_tablas_viejas_en_uso;   -- qué objeto sigue leyendo una tabla congelada
```

`gv_reglas_perdidas` se alimenta de **`GV_Reglas_Centinela`**, que es una tabla editable: cada
fila dice "en tal objeto tiene que seguir apareciendo tal patrón, porque tal regla". **Al agregar
una regla que no se puede perder, agregarle su fila**, que es un `insert`, no código:

```sql
insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
values ('<objeto>','funcion','<regex que tiene que estar>','<la regla en castellano>',
        '<quien la pidio>','<version>');
```

⚠ El centinela **saca los comentarios antes de buscar**: si no, un `-- NO usar X` contaba como
uso de X.

⚠⚠ **Y esa regla la había perdido el propio centinela** (v21.82, 23/09). `gv_reglas_perdidas`
comparaba `cuerpo !~ patron` a secas: el vigilante estaba en la misma falla que vigila. Ya había
dejado pasar una — la regla **(a000) v21.61** del armador tenía como patrón `\(a000\) v21\.61`,
que en esa función **sólo existe dentro del comentario**: borrando el código y dejando el
comentario, el centinela seguía en verde. Medido: **1 de 124**. Hoy la limpieza vive en
**`gv_regla_presente(cuerpo, patron)`**, que usan la vista y el barrido, así que no puede haber
dos criterios.

> **Al registrar una regla, el patrón se elige del CÓDIGO, nunca del comentario que lo explica.**
> Un patrón como `(a000) v21.61` o `-- REGLA DE LUIS` vigila el rótulo, no la regla.

**El botón de prueba de la base** — el equivalente de `tests/tools/mutar.cjs` para lo que vive
en Supabase:

```sql
select * from public.gv_centinelas_flojos;   -- ningún 'VIGILA UN COMENTARIO' = todo bien
```

Al 23/09: **0** que vigilan un comentario, **0** perdidas, 26 con patrón genérico.

⚠ **«Genérico» NO se mide por cuántos OBJETOS nombran la palabra: se mide por cuántas veces
aparece el patrón EN SU PROPIO cuerpo** (v21.84). El centinela sólo mira su objeto, así que un
patrón que aparece **una sola vez** ES la regla: borrarla la borra, y no importa que otros 25
objetos digan `PPP_Web_Programacion`. **19 de los 26 están así y están bien.** Los otros 7
aparecen 2+ veces, y ahí sí hay que mirar si la segunda aparición no es la regla:

| centinela | veces | por qué queda flojo |
|---|---:|---|
| `gv_np_destino` · `es_retira` | 6 | la regla es *un Retira sale `retira`, no `ambiguo`* y vive en UNA línea; las otras 5 son la columna y su arrastre |
| `gv_retira_contradictorio` · `es_retira` | 5 | la regla es el `WHERE` de doble dirección, no la columna |
| `gv_tanda_armada_sin_armado` · `Entregas_Virgilio` | 2 | **una de las dos es el texto del `motivo`**: borrando el `FROM` real el centinela queda verde contra un string |
| `gv_empresa_de_entrega` · `'LK'` | 2 | una es la rama de la **L** y la otra la de la **NP**: borrar la L deja el patrón puesto |

Las otras 3 (`gv_ppp_web_dias_ancla`, `gv_ppp_web_retenido`, `gv_clin_vincular`) repiten porque
**las dos apariciones son la misma regla**: quedan como están.

> **Al elegir el patrón, la pregunta no es "¿esta palabra está?": es "¿si borro la regla, esta
> palabra se va?".** Si queda, el centinela vigila el vecindario, no la regla.

```sql
-- las veces que el patrón aparece en el cuerpo de SU objeto (1 = es la regla)
select id, objeto, patron from public.gv_centinelas_flojos;
```

Y la prueba de verdad, que es romper la regla y ver si avisa, **revirtiendo siempre** (el bloque
completo está en `sql/gv_centinelas_boton_de_prueba_v2182.sql`):

```sql
do $prueba$ … execute <la funcion SIN la regla>; …
  raise exception 'RESULTADO -> antes: % · con la regla borrada: % · la nombra: %', …;
end $prueba$;
```

⚠ **El resultado va en el mensaje del `raise`, no en un `notice`**: desde el MCP los `notice` no
se ven, y el `raise` es además lo que aborta la transacción y deja la función como estaba.
Medido con `refresh_stocks_carga_rapida`: *antes 0 perdidas · con la regla borrada 1 · la nombra
sí*, y después la función intacta.

⚠ **Lo que se probó y se descartó, para no rehacerlo:** una vista que borraba la **primera**
aparición del patrón y miraba si el centinela avisaba. Marcaba **41 de 124** y era ruido — el
caso real es el reemplazo del objeto entero, donde desaparecen todas. Se borró el mismo día.

**Y un tercero, del lado del stock** (v19.49, después del doble drenaje de D66D):

```sql
select * from public.gv_stock_afacturar_tanda_negativa where clase='tanda';  -- vacía = todo bien
select * from public."GV_Stock_Drenaje_Bloqueado";   -- lo que el guard frenó: si tiene filas, alguien factura dos veces
```

Lo sostiene el trigger **`zzz_facturado_no_negativo`**: un `facturado` sobre `a_facturar` cuya pila
de tanda ya está en cero se descarta y queda anotado. **`gv_stock_negativos` no reemplaza a esto**:
agrega por código sin mirar la tanda, así que el saldo positivo de otra tanda tapa el agujero — el
17/09 mostraba 3 de los 12 códigos que D66D había dejado en negativo. §3.gr.

### 4. Las tablas que valen hoy

La lista viva está en la regla **"LAS TABLAS QUE VALEN"** más abajo, con la medición de cuál se
escribió por última vez. Resumen: góndola y racks → **`GV_Lugar` + `GV_Lugar_Item`** (vista
`gv_lugar_articulo`) y **`Racks_Planimetria`**; **nunca** `Ubicaciones_Articulos` (congelada el
10/08) ni `Planimetria` como fuente (sólo guarda los huérfanos que el mapa rescata). Entregados
→ **Recepción Remitos** (`opcion='CRN'`), nunca `PPP_Entregados_Meta`.

**Antes de escribir una consulta contra una tabla que uno no tocó nunca**, mirar cuándo se
escribió por última vez:

```sql
select * from public.gv_fuentes_lugares;   -- tabla · rol · última escritura · días · quién la lee
```

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
3. **Excepción del dueño:** Thomas Loekemeyer NO usa Planify. Sus pedidos se cargan en el
   Planify de **Tomás Beviglia (employee_id 20)** con el nombre antepuesto por **`Th `**
   (ej. `Th Fecha estimada de entrega por zona`).

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

## ⚠ REGLA: el cartel de permiso de `execute_sql` NO se arregla desde el repo

**Medido el 2026-09-18 (v19.74), después de que dos sesiones perdieran horas buscándolo en el
lugar equivocado.** El síntoma: `mcp__Supabase__execute_sql` abre el cartel de permiso en cada
llamada, aunque esté en `permissions.allow` de `.claude/settings.json` y la sesión corra en Auto.

### La causa: el CONNECTOR de claude.ai marca esa herramienta como `always_ask`

No es el settings del repo, no es el trust, no son los hooks, no es el modo. La plataforma le
escribe a la sesión un archivo `/tmp/mcp-config-<session>.json` armado desde **la configuración
del connector en claude.ai**, y ahí cada herramienta viene con su `permission_policy`:

```json
{"name": "execute_sql",          "permission_policy": "always_ask"}
{"name": "apply_migration",      "permission_policy": "always_ask"}
{"name": "list_tables",          "permission_policy": "always_allow"}
{"name": "deploy_edge_function", "permission_policy": "always_allow"}
```

**De las 27 herramientas de Supabase, esas DOS son las únicas en `always_ask`** — hasta
`delete_branch`, `pause_project` y `deploy_edge_function` están en `always_allow`. El CLI lo
convierte en una regla `ask` con `source = 'mcpServerPolicy'`, y en Claude Code la precedencia es
**deny > ask > allow**: un `ask` le gana a CUALQUIER `allow`, venga del repo, del settings de
usuario o del flag `--allowed-tools`. Por eso agregar la herramienta a `allow` no cambia nada.

**Se confirma solo, por un segundo lado:** el proceso de Claude arranca con un
`--allowed-tools` que enumera las herramientas de Supabase una por una y **saltea exactamente
esas dos**.

### Dónde SÍ se apaga

En **claude.ai → Settings → Connectors → Supabase**, poniendo `execute_sql` en *Always allow*
(lo mismo para `apply_migration` si se quiere). O, cuando salta el cartel, eligiendo la opción
de **"siempre permitir" en vez de la de permitir una vez** — ésa escribe la política del
connector y vale para las sesiones siguientes.

**Lo aprieta el dueño en su cuenta. Desde el repo no hay forma**, y no hay que volver a intentarlo.

### Cómo se mide, para no volver a adivinar

Las dos consultas que contestan todo, desde adentro del contenedor:

```bash
# 1) la política real de cada herramienta del connector (la causa)
python3 -c "import json;d=json.load(open([f for f in __import__('glob').glob('/tmp/mcp-config-*.json')][0]));print(d['mcpServers']['Supabase']['tools'])"

# 2) si el settings del repo se leyó, y con qué reglas (el efecto)
grep -n "Applying permission update" /tmp/claude-code.log
```

El `/tmp/claude-code.log` es el debug del CLI y dice, línea por línea, qué reglas entraron y de
qué fuente (`userSettings`, `projectSettings`, `cliArg`, `flagSettings`). **Al 18/09 muestra las
50 reglas de `projectSettings` con `mcp__Supabase__execute_sql` adentro**: o sea que el settings
del repo se lee perfecto y el problema nunca estuvo ahí.

⚠ **El aviso "Ignoring N permissions.allow entries: this workspace has not been trusted" ya NO
existe** en el CLI 2.1.276 (se buscó el string en el binario: 0 apariciones). Si una doc vieja lo
menciona como "la única señal de que el settings se lee", está desactualizada — la señal de hoy
son las líneas `Applying permission update` del log.

### Lo que SÍ sigue siendo cierto del settings del repo

1. **El modo de la sesión pesa**: en **Manual** (`default`) sólo las lecturas corren solas. Se
   elige en el selector de la sesión (Auto / Aceptar ediciones / Plan; **no hay
   `bypassPermissions`**, Auto es el máximo). `permissions.defaultMode` desde el settings de un
   repo se ignora.
2. **El único settings que llega a una sesión cloud es `.claude/settings.json` DEL REPO**, y sólo
   si la sesión tiene **un** repositorio. `~/.claude/settings.json` y `.claude/settings.local.json`
   no se leen; escribirlos desde el setup script del entorno no sirve.
3. ⚠⚠ **La salida de un hook `PreToolUse` / `PostToolUse` en TEXTO PLANO NO LE LLEGA AL MODELO.**
   El CLI la corre, la anota en el log como `success` y **la descarta**; la línea del log lo dice:
   `Hook output does not start with {, treating as plain text`. Para que llegue tiene que ser
   **JSON**: `{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"…"}}`.
   **La de `SessionStart` sí llega en texto plano** (por eso la línea de `claude-permisos.sh` se ve
   en cada arranque), y por eso la regla de "quién habla" cuelga de ahí.

   Medido el 23/09: los dos hooks de **caveman** —puestos en la v20.58, el 21/09— estuvieron
   **muertos desde que se escribieron**, 431 corridas de `PreToolUse` y 412 de `PostToolUse` sin que
   una sola llegara. Por eso caveman "no se respetaba". Se probó cambiando uno a JSON y viendo el
   texto aparecer en el resultado de la herramienta siguiente — **no se prueba leyendo el settings**.

   ⚠ `UserPromptSubmit` **no está configurado** (0 corridas): es el hook pensado para inyectar
   contexto en cada mensaje del usuario, por si algún día hace falta algo más fuerte que el arranque.

4. **Un `hooks` mal formado tira el archivo ENTERO, sin avisar.** El formato viejo
   —`{"matcher":"", "command":"..."}`— ya no vale; hoy va con el array `hooks` anidado:
   ```jsonc
   "hooks": { "SessionStart": [ { "matcher": "",
     "hooks": [ { "type": "command", "command": "echo hola" } ] } ] }
   ```
   Con el formato viejo la `permissions.allow` deja de existir y no se tira ningún error. Así
   estuvo este repo desde el commit `542ab7e` (16/09) hasta la v19.63.
5. ⚠ **En Auto, un `allow` "peligroso" se descarta a propósito**, y el log lo dice:
   `Ignoring dangerous permission Bash(*) from .claude/settings.json (bypasses classifier)`. Por
   eso un `"Bash"` pelado en `allow` **no** hace que Bash deje de pasar por el clasificador.
   Las reglas con comando concreto (`Bash(git status:*)`) sí valen.
6. ⚠ Un `ask` matchea por **prefijo del comando**: `Bash(git push:*)` **no** agarra
   `git -C /ruta push …` ni `cd X && git push`. Si algo tiene que frenar sí o sí, va en `deny`.

### ⚠ Cómo NO probarlo

- **`claude --print` adentro del contenedor**: ese CLI es local, lee el settings de usuario y
  exige el trust; la sesión cloud no hace ninguna de las dos cosas. El 18/09 dio verde tres veces
  seguidas mientras el usuario seguía autorizando de a uno.
- **Preguntándole a la sesión**: Claude **no ve los carteles**, sólo sabe si la llamada corrió o
  fue rechazada. Cualquier prueba de esto la mira el usuario en pantalla — o se lee del
  `mcp-config`, que es la fuente y no requiere mirar nada.

⚠ Que `execute_sql` pregunte o no **no cambia la regla del 26/08**: los datos no se tocan sin
permiso explícito. Eso lo sostiene este archivo, no el diálogo de permisos.

`scripts/claude-permisos.sh` y `scripts/setup-entorno-claude.sh` quedan para las sesiones
**locales**, donde sí manda el settings de usuario y hace falta el trust. En cloud no hacen nada.

## 🪨 Modo Caveman (SIEMPRE activo)

**Cada conversación abre con caveman activo por defecto.** Responder en modo **caveman**:
frases cortas, directas, mínimas palabras, sin relleno. Solo aplica al **chat** (no al
código, comentarios ni mensajes de commit).

- **`desactiva caveman`** = responder solo el **próximo mensaje** normal/completo, y después **volver solo** a caveman.
- **`caveman desactivacion total`** = apagar caveman por completo (queda desactivado hasta que se reactive).

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

Vale para TODOS los repos. Es sólo cómo se escribe el mensaje del chat: no cambia nada técnico.

## 🟥🟥🟥 REGLA (Luis, 2026-09-23, v21.87): UN GRUPO DE ZONAS POR DÍA — y "mismo cliente, mismo día" NO EXISTE MÁS

> ## **DEROGADA: "nunca +1 pedido de un cliente va separado en la PPP".** No se junta al cliente en un día.
> ## Un cliente con sucursales en dos zonas va en **dos días**, cada pedido con el camión de SU zona.

**Luis, textual:** *"Saca esa regla de que se junta al cliente. Un cliente puede tener sucursales en
2 zonas diferentes y lo más importante es eso. En serio saca esa regla porque por más que lo explico
la seguís refiriendo y no va."* Toda mención de esa regla más abajo en este archivo (Thomas v15.52,
el "mismo día para el cliente" del principio rector, el ancla de cliente v20.27, la alarma
`gv_ppp_cliente_dos_dias`) queda **sin efecto**. No citarla, no proponerla, no "respetarla".

**Cómo elige el día el armado desde la v21.87** (`gv_ppp_web_dia_grupo`, pase **(g)** de
`gv_ppp_web_armar_pendientes`; forward-facing: lo ya programado no se toca):

| paso | qué hace |
|---|---|
| plazo | entrada del pedido + **14 días corridos**; por **expreso + 13**. Hacia atrás al día con reparto |
| fecha mínima | la de siempre: `gv_ppp_web_dia_minimo` (4 hábiles, calculado al mediodía) |
| 1 | si su **grupo** (Capital Sur Z1 · Capital Centro Z2 · Capital Oeste Z3, juntas si cada una < 1 m³ · GBA Sur · GBA Oeste · GBA Norte Z6+Z7) ya sale un día del plazo → **ese**, sin mirar el cupo (el 4,30 m³ es promedio, no techo) |
| 2 | si no, el **último día LIBRE** del plazo (sin ningún grupo de reparto), para que los pedidos del grupo que entren después se sumen |
| 3 | si todos los días del plazo tienen otro grupo → **gana el cliente**: el día con menos grupos (segundo camión / flete) |
| 4 | ya vencido → lo antes posible, aunque mezcle grupos: el rezagado no se traba |

- Súper y Retira no son "grupo de reparto" (camión propio / no usan camión) y no ocupan el día.
- Súper con turno, Retira con día elegido, cliente nuevo aprobado (48 h) y diferidos: **sin cambios**.
- Apagados en modo grupo: (a1), (a2), (b00) ancla de cliente, (b0) ancla por número de zona,
  (b) cascada por cupo, (c) zonas manuales, (d) juntar clientes. El INC (auto_super) sigue con su cascada.
- **Interruptor**: `PPP_Web_Config.grupo_dia_activo` — sin fila = prendido; con `valor = 0` vuelve
  la lógica anterior sin redeploy. `sql/gv_programacion_grupo_dia_v2187.sql` (el marcador interno
  dice `v21.80-grupo`: es la llave de idempotencia, no cambiarlo).

**Probado corriendo el armador** en transacción abortada (23/09): Z3 → 30/09 con Centro-Oeste
(E48G), Z4 → 05/10 con GBA Sur (E73A), Z6 sin camión en el plazo → 07/10 (último día libre), un
expreso vencido Z1 → 01/10 con Capital Sur, y el **mismo cliente** en Z3 y Z6 → **dos días**.

## ⚠ REGLA (Luis, 2026-09-23, v21.97): POP-UP de DÍA OCUPADO al programar a mano

Al soltar un pedido en A Programar sobre un día que YA tiene programación, sale un pop-up (`aprDiaOcupadoAbrir`)
con 3 opciones, cada una con su reporte previo (m³ del día contra el promedio 4,30, más de 2 camiones, pedidos
que pasan a vencer): **1) sumarlo** · **2) reprogramar lo PENDIENTE del día con la lógica automática** ·
**3) correr toda la programación desde ese día, 1 día con reparto**. Día vacío → como siempre, sin pop-up.

Lo resuelve **`gv_ppp_dia_reprogramar(fecha, 'correr'|'automatico', simular, por)`** (`simular = true` no escribe;
ejecutando es atómico). **NO se mueven** (Luis): **súper**, **retira fijos**, lo que **ya salió** y una tanda
**EN PROCESO** (pickeo o armado empezado sin TAP). Armada, facturada o pendiente **se mueve con su MISMO código**
(el papel del pallet sigue valiendo). La tanda nueva se arma DESPUÉS de mover, o se correría también.

⚠ **El trigger `gv_web_cliente_un_solo_dia` quedó APAGADO** (23/09): aplicaba la regla derogada "mismo cliente,
mismo día" — frenaba los movimientos y movía solos los otros pedidos del cliente a su día. Rollback:
`alter table public."PPP_Web_Programacion" enable trigger gv_web_cliente_un_solo_dia;`
`sql/gv_ppp_dia_reprogramar_v2197.sql`, `tests/apr-dia-ocupado.cjs`.

## ⚠⚠ NO REPORTAR (Luis, 23/09): "entran N pedidos y no se programan" en el log del armado

`GV_PPP_Web_Armado_Log` / `GV_Tandas_Auto_Log` muestran en CADA corrida pedidos que entran y no arman tanda.
**Es lo esperado y NO es un bug** cuando son: **súper sin turno** (ej. LK 1504 La Anónima, 2 NP, Zona 5),
**cliente nuevo sin aprobar** o **cuarentena**. Luis ya lo revisó 3 veces el 23/09: *"ESTA BIEN que no se
programen automáticamente"*. Antes de mencionarlo, mirar si el pedido es súper (`gv_es_super`), cliente nuevo
o cuarentena; si es eso, **no se dice nada**. Sólo se reporta un pedido común (no súper, no retenido) que no
se programa.

## 🟩🟩🟩 PRINCIPIO RECTOR DE LA PROGRAMACIÓN (Luis, 2026-09-22)

> ## Agrupar pedidos existe para **ENTREGAR LA MAYOR CANTIDAD DE MERCADERÍA EN LA MENOR CANTIDAD DE CAMIONES.**

**Es el para qué de la tanda.** Toda regla de armado, de movimiento y de reprogramación se mide
contra esto: si una decisión hace salir más camiones para la misma mercadería, está mal, por más
que respete todas las demás reglas.

### La consecuencia que se saca mal todo el tiempo: se agrupa POR PEDIDO, NUNCA por cliente

**Luis, textual:** *"Un cliente puede tener sucursales en lugares diferentes (uno que tenga en
Zona 1 y zona 5 por ejemplo, no van a salir juntas en un mismo camión, van a ir en camiones que
vayan a esas zonas)."*

La unidad de agrupamiento y de movimiento es el **PEDIDO** (todas las NP de ese `order_id` juntas),
**no el cliente**. Juntar por cliente parece prolijo y es lo contrario del principio: manda mercadería
a un camión que no va a esa zona, o parte un camión en dos.

⚠ **Al mover un pedido, NO se arrastran los otros pedidos del mismo cliente.** Medido el 22/09:
hay 5 tandas vivas con 2+ pedidos distintos del mismo cliente (E48D tiene **8** de Jazquel). Moverlos
juntos "porque son del mismo cliente" es justamente lo que esta regla prohíbe.

**Cómo convive con las otras dos reglas de cliente, que siguen valiendo:**

| regla | qué dice | por qué no choca |
|---|---|---|
| ~~Thomas: *"nunca +1 pedido de un cliente va separado en la PPP"*~~ | **DEROGADA (Luis, 23/09, v21.87)** | ver "UN GRUPO DE ZONAS POR DÍA" |
| Luis v18.87: *"la tanda de un cliente se parte por CAMIÓN"* | mismo día, distinta tanda si la zona manda a otro camión | es esta misma regla aplicada al armado |

O sea: **mismo día para el cliente · tanda por camión · agrupamiento por pedido.**

⚠ **Y la alarma de "cliente en días distintos" (`gv_ppp_cliente_dos_dias`) salta SÓLO si esos pedidos
podrían ir en el MISMO camión** (Luis, 23/09, v21.70). Caso Multi Bazar (LK 4042): 4 pedidos a Río
Negro y Santa Cruz por expreso y a San Martín por reparto propio, en 3 camiones distintos — juntarlos
en un día no ahorra un viaje y el 2/10 ya salían los 2 camiones de Capital. El corte es la etiqueta de
`gv_ppp_web_camion` (Capital Sur / Capital Centro-Oeste / GBA Sur / GBA Oeste / GBA Norte). Las tres dicen lo
mismo desde tres lados, y el principio rector es el que las ordena cuando parecen chocar.

## ⚠⚠ LA LÓGICA DE PROGRAMACIÓN, RESUMIDA POR LUIS (2026-09-19)

Es el objetivo contra el que se mide cualquier cambio de armado. Textual:

> 1. Hay que programar para sacar lo más rápido los pedidos posible, **como máximo 2 camiones
>    por día**.
> 2. Hay que programar los **m³ lo más al ras de lo que lleguen a preparar**, para que no haya
>    ineficiencia interna ni necesidad de reprogramar para adelantar ni para retrasar, para
>    evitar errores de programación.
> 3. La lógica de los **km recorridos entre destinos debe ser la menor posible**.
> 4. Los pedidos **no pueden demorar más de 10 días hábiles** en salir.
> 5. Si hay más demora, **o se priorizan pedidos, o se trae más gente al depósito** a ayudar a
>    armar.

**Las cinco no son independientes y hay que tenerlo presente al tocar el armado:**

- **(1) y (3) tiran contra (4).** Juntar pedidos para bajar km exige esperar a que se acumulen;
  esperar demora la salida. El modelo de anclas resuelve ese compromiso con la ventana: cuanto
  más larga, menos camiones y más demora. Toda discusión sobre la ventana es esta discusión.
- **(2) es la que evita el retrabajo.** El cupo del día tiene que ser el que el depósito
  realmente arma, ni más ni menos: de más obliga a reprogramar para atrás, de menos deja gente
  ociosa y empuja pedidos hacia adelante. Hoy vive en `gv_ppp_web_cupo` (pickers × 3 m³) y, en
  el modelo de anclas, en `ancla_cupo_m3_dia` (10 m³, el p90 medido).
- **(5) es la válvula, y es una decisión de Luis, no del sistema.** El sistema avisa que un
  pedido va a pasar los 10 días hábiles; quién prioriza o si se suma gente lo decide él.
- El tope de 2 camiones por día es `jornada_camiones`; el de 6 m³ por camión, `camion_m3_tope`;
  la jornada de 8 h, `jornada_horas_max`.

---

## ⚠ REGLA: borrar un pedido = borrarlo de TODOS lados (todos los repos/proyectos)

Cuando el usuario pida **borrar un pedido**, borrarlo de **todos los lugares donde ese pedido
interviene**, no de uno solo. Un pedido web vive en varios proyectos a la vez:

1. **Página de la empresa** (su propio proyecto Supabase): `orders` + `order_items`
   — LK = `kwkclwhmoygunqmlegrg` (repo `pagina-LK-copia`); Chef = `nkhzocgdpwtgrmwleihr` (repo `paginach`).
2. **Gestión Virgilio** (`hrxfctzncixxqmpfhskv`): la NP y la programación. Buscar el `order_id`
   (filtrando `empresa` = `lk`/`chef`) en `PPP_Web_NP`, `PPP_Web_Programacion`, `PPP_Web_Base`,
   `PPP_Web_Tanda_Items`. Si ya está en tanda/picking, avisarlo antes de borrar.

**Backup antes de cada borrado** (protocolo de Supabase). Borrar hijos antes que padres
(`order_items` antes de `orders`). Al terminar, reportar en qué lugares apareció y de cuáles se borró.

---

App web (PWA, sin framework) para registrar producción de depósito (picking,
armado, carga de camión, recepción). La usan operarios desde el celular y
supervisores desde un monitor. Se sirve por GitHub Pages desde `main`.

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

## ⚠ Regla del dueño (2026-09-07, v13.64): ISIS o web, da lo mismo — salvo en Facturación

*"Que el pedido sea de ISIS o cargado por la web no me interesa para absolutamente nada. Lo que me importa
es para el módulo de Facturación, después de eso no."* → **Ninguna pantalla fuera de Facturación separa,
etiqueta ni cuenta aparte lo de ISIS y lo web** (ni "camiones web / ISIS", ni "m³ web", ni Tipo "WEB"). Por
dentro la distinción sigue (NP web = número de pedido con prefijo, facturada = bajar el Excel de ISIS), pero
no se muestra. Al agregar una pantalla o una columna, mostrar todo junto.

## ⚠ Regla del dueño (2026-09-07, v13.71): lo que entra por Chef ES de Chef; artículo LK → "L" al final

Un cliente de LK que pide por la página de Chef: el pedido es de Chef de punta a punta, se factura por Chef, y
cada artículo de Loekemeyer va con **"L" al final** (505 → 505L; 438E → 438EL). La regla vive en las páginas
(`paginach` / `pagina-LK-copia`, `admin-supercot.js` `addLSuffix = isChef`) y Gestión la respeta: la L manda el
stock a la góndola LK (`pkEmpresaArt`), el m³ sale de `vista_volumen_articulo_resuelto` (tiene los `NNNL`), el
precio de la lista LK pelando la L (`gv_ppp_np_valor` v13.71), y la factura / Excel ISIS llevan el código crudo
con L. **Nunca** recodificar 7xx→5xx ni "pasar a LK" un pedido de Chef. Informe: `docs/INFORME-PEDIDOS-LK-POR-CHEF.md`.
**Tierra del Fuego (v13.77, dueño 07/09): *"los que le hacemos FC E [Factura E] vendiéndole art. de Loeke … el pedido se arma
como Loeke (con una L al final) y después va a ISIS de CH, no de LK"*** — un pedido de la página LK con sucursal de entrega en
Tierra del Fuego sigue siendo NP **LK** (se pickea de la góndola Loeke), pero cada artículo lleva **L** (505L) y el Excel ISIS va
al de **Chef** con el código de cliente de Chef del mismo CUIT (vista `v_pedidos_web` de LK: `isis_empresa`, `cod_isis`;
`_facXlsArmar`). Los 10 clientes LK de TdF ya cruzan por CUIT. **Excepción: La Anónima (771) se vende por LK** (`gv_isis_override` en LK, por CUIT). **Cencosud (Chef 2444) es el caso inverso: NP de Chef con artículos de Loeke sin L** → entra al checklist de ajustes ISIS (`gv_fac_ajustes_isis` v2, v13.79). Ser cliente de las dos empresas, solo, no es problema; **el cod
cliente no significa nada, sólo el CUIT vale** (v13.76). La regla v13.75/76 ("cliente con FC en LK → no se programa",
`cliente_fc_lk`) fue un malentendido y está **apagada** (`doble_lk_dias = 0`); **también la de v13.72 ("mismo cliente por CUIT, mismo día en ISIS LK", `en_produccion_lk`; `doble_lk_mismo_dia = 0`, v13.82)**: *"ya expliqué que eso no corresponde"*. §3.az, §3.ba y §3.bb.
**⚠ Y la CUARENTENA de esos pedidos se evalúa con el cliente de CHEF (v17.75, dueño 14/09: *"se marcan y se evalúan
para cuarentena con código de cliente CH"*).** El padrón de LK los tiene con **límite 0** y 4 de 9 como *Suspendido*,
justamente porque a ese cliente no se le vende por LK: evaluar por LK retiene pedidos sanos (pasó con **LK 1431**,
Il Cheff) y nunca mide el crédito. El mapeo `(lk, cod)` → `(chef, cod_isis)` vive en `GV_Cliente_Isis` —lo empuja LK
con `sync_cliente_isis_virgilio()`, cron cada 15 min— y lo resuelve `gv_cuarentena_ident`, que usan las tres
funciones de Cuarentena. **Una NP tipeada en ISIS NO se remapea**: lleva el código de ese ISIS. **⚠ Cencosud NO entra
por esta regla y NO hay que darlo de alta** (dueño, 14/09: *"Cencosud sube pedido por Krikos… siempre (histórico)
subió pedidos por CH. No lo voy a dar de alta."*): no carga por la página, sus OC entran por **Krikos** y la Bandeja
las manda directo al portal de **Chef** (`precios_super.cadena`: `cencosud` → `empresa='chef'`, `cod_cliente_chef=2444`,
`cod_cliente_lk` nulo). Medido: 4.452 líneas del 2444 en `sales_lines` marcadas `chef` desde 2021-05-27, ninguna en LK.
Su caso propio —NP de Chef con artículos de Loeke **sin** L— ya lo cubre `gv_fac_ajustes_isis` (v13.79): es el caso
**inverso** al de Tierra del Fuego. `sql/gv_cliente_isis_v1775.sql`, §3.fp.

## ⚠ REGLA (Luis, 2026-09-22, v21.09): la L es de CENCOSUD y de TIERRA DEL FUEGO — de nadie más

**Luis, textual:** *"lo de la L debería aplicar únicamente a CENCOSUD y a pedidos que van a
TIERRA DEL FUEGO"*.

La regla v13.71 de más abajo (*"lo que entra por Chef ES de Chef; artículo LK → L al final"*)
se leyó como *"todo pedido de Chef lleva L"*, y **no es eso**:

> **La L no la decide quién FACTURA: la decide de quién son los ARTÍCULOS.**

| súper | factura por | sus artículos son de | ¿L? |
|---|---|---|:--:|
| **Cencosud** | Chef | **LK** (matchea contra LK + `loke_products`) | **SÍ** |
| **Dorinka** (Chango Más) | Chef | **Chef** (`usa_productos_chef`) | **NO** |
| el resto (Coto, INC, Día, Diarco…) | LK | LK | NO |

El criterio ya estaba en el código y en la config: `isChefSuper(k) && !usesChefProducts(k)`,
que sale de `precios_super.cadena` de LK. Medido: `empresa='chef' and usa_productos_chef=false`
devuelve **una sola cadena, Cencosud**.

**Lo que estaba roto** (en `pagina-LK-copia/admin-supercot.js` y su espejo `admin/` de acá):
`addLSuffix = isChef` en el submit y `cencosud || dorinka` en el PDF. El admin de **Chef**
(`paginach`) siempre estuvo bien, con el comentario *"Dorinka NO lleva L (son art. de Chef);
solo Cencosud"*.

**Lo que costó, medido:** el pedido 229 de Dorinka (NP **CH 0025**) salió con los 5 códigos con
L — `769L`, `840L`, `838L`, `865EL`, `798EL` — y del lado de LK **no hay una sola caja** de
ninguno: 769 → 0, 798E → 0, 840 → 0, 865E → 0. Todo el stock está en Chef (40, 74, 85 y 9).

⚠ **Esto NO contradice la regla de abajo: la L sigue sin sacarse nunca de un pedido.** Lo que
cambia es **quién se la pone al armarlo**. Si un pedido ya tiene la L, viaja y rutea como
siempre; lo que no puede es nacer con una L que no le corresponde.

⚠ **Y Tierra del Fuego va por otro camino** (v13.77): ahí la L no la pone el cotizador de
súper sino el pedido de la página de LK con sucursal de entrega en TdF. Son dos orígenes
distintos de la misma marca.

`sql/gv_secundarios_web_y_regla_L_v2109.sql`.

**Chequeo (v21.84):** `node tests/regla-L-super.cjs` — candado **estático** sobre
`admin/admin-supercot.js`: las dos asignaciones de `addLSuffix` (el submit y el PDF) tienen que
llevar `&& !usesChefProducts(...)`. Verificado que falla con `addLSuffix = isChefSuper(k)` a
secas, que es como estuvo hasta la v21.09. Se corre **sin comentarios**: el comentario que
explica la regla nombra `usesChefProducts` igual, y un candado que vigila su propio comentario
no vigila nada (v21.82).

⚠ Esta regla **no tiene centinela en la base y no puede tenerlo**: no vive en Supabase, vive en
el JS de las páginas. Gestión tiene la copia que se sirve por Pages; el fuente está en
`pagina-LK-copia` y `paginach`, y ahí **no hay test que lo sostenga** — al tocar ese archivo en
cualquiera de los dos repos, mirar esto.

## ⚠⚠⚠ REGLA: LA "L" NO ES UN CÓDIGO — ES UNA DENOTACIÓN

**Thomas, 2026-09-18, textual:** *"la L no existe. `026L` no es un código válido. Existe sólo para
denotar que el `026L` es un `026` en pedido de Chef que se pickea del stock de LK."*

**No hay ningún artículo que termine en L** (verificado el 02/09 en `loke_products`,
`chef_articulos_activos`, `milver_products`, remaps y todo el pipeline). La L es una **marca de
ruteo** que viaja pegada al código del PEDIDO y significa exactamente dos cosas:

1. al **pickear** → la caja sale de la góndola de **Loekemeyer**, no de la de Chef;
2. al **facturar** → la línea va al ISIS de **Chef** con el artículo de Loeke.

### Dónde va la L y dónde NO — está resuelto en el código, no hay que decidirlo cada vez

| capa | objeto | ¿lleva L? | quién lo resuelve |
|---|---|:--:|---|
| Pedido | `PPP_Web_Base.articulo`, `gv_ppp_np_items` | **SÍ** (`026L`) | lo trae el feed de la página |
| Picking (pantalla y stock) | lista de picking, `Movimientos_Stock.cod_art` | **NO** (`026`, o `438E LK` si es dual) | **`pkResolveArt`** = `pkStripL` + `pkEmpresaArt` |
| Armado / factura | `Entregas_Virgilio.cod_art`, Excel ISIS | **SÍ**, crudo (`438EL`) | `_facXlsArmar` lo toma tal cual de `Entregas_Virgilio` |
| Badge **FC s/Salida** (Stocks) | `vista_fc_sin_salida`, `stocks_carga_rapida.fc_sin_salida` | **NO** | **`gv_cod_stock_de_entrega`** (artículo) + **`gv_empresa_de_entrega`** (empresa), en columnas separadas (v21.13) |

```js
// index.html, v12.39 — el comentario que lo dice todo:
function pkEmpresaArt(cod, np) { return /[0-9E]L$/.test(cod) ? "LK" : empresaDeNp(np); }
function pkStripL(cod)         { return cod.replace(/([0-9E])L$/, "$1"); }
function pkResolveArt(art, np) { return pkCodEmpresa(pkStripL(art), np, pkEmpresaArt(art, np)); }
//  "NO se usa para el código del PEDIDO que va a Entregas_Virgilio/factura
//   (ese se conserva crudo, ej. 438EL)."
```

⚠ **Por eso NO hay que "limpiar" la L de `PPP_Web_Base`.** Si se la saca, el código deja de matchear
`/[0-9E]L$/`, `pkEmpresaArt` cae en `empresaDeNp(np)` → como la NP es de Chef, **el picking manda al
operario a la góndola de Chef** y la factura sale con el artículo equivocado. El 18/09 se sacó y se
repuso dentro de la misma tanda de trabajo; queda escrito para que no se repita.

⚠ **Y la L tampoco se agrega a mano en Gestión.** La pone la página al armar el pedido
(`admin-supercot.js`, `addLSuffix = isChef`). Gestión la **respeta y la rutea**, no la genera.

⚠⚠ **Y todo lo que MUESTRA stock a partir de un código de FACTURA tiene que resolverlo primero**
(v21.13, Luis 22/09). `Entregas_Virgilio` guarda `026L` porque ése es el código de la factura; el
badge **FC s/Salida** lo agrupaba con `norm_cod()`, que **sólo saca ceros a la izquierda — no pela la
L**, así que el 026 salía partido en dos filas (026 = 10, **026L** = 1) y el front fabricaba una fila
fantasma sin empresa ni descripción. Eran **32 códigos**, todos del mismo pedido de Chef con
artículos de Loeke.

> ## **«438E LK» NO ES UN CÓDIGO.** Es el artículo `438E` **de la empresa `LK`**, y son **dos datos**.

**Luis, 22/09, textual:** *"Debería ser en todos lados «438E» de la empresa «LK» o de la empresa «CH»
como dato en una columna aparte que viaje con el código a todos lados."* Y el modelo correcto **ya es
el del libro de stock**: `Movimientos_Stock` guarda `cod_art = '438E'` + columna `empresa`, y
`GV_Lugar_Item` lo mismo — **0 filas con sufijo pegado en las dos**. El string concatenado vive en un
solo lugar, **8 filas de 367 de `stocks_carga_rapida`** (los 4 duales × 2 empresas), como **clave
heredada** de `vista_stock_procesada`; esa tabla **ya tiene los dos datos separados al lado**
(`cod_base` + `linea`). **Nada nuevo se escribe concatenado.**

Los dos datos salen de dos funciones, y no se vuelven a pegar:

| función | devuelve | ejemplo |
|---|---|---|
| **`gv_cod_stock_de_entrega(cod, np, emp)`** | el **artículo** | `026L` → `26` · `438EL` → `438E` |
| **`gv_empresa_de_entrega(cod, np, emp)`** | la **empresa** | `438EL` → `LK` · `438E` en NP de Chef → `CH` |

⚠ **La empresa de un código con L es LK: la da la L, NUNCA la NP.** En un código **no dual** la da el
**artículo** (`gv_empresa_de_articulo`), no el pedido — regla v19.26.

⚠ **En los duales, cruzar por el código solo cuenta doble o cuenta cero.** El universo de stock los
tiene desdoblados y el cruce es por **igualdad exacta**: con `438EL` y `438E` a secas los dos
quedaban en **0**, y el fallback `codBase` del front le daba las mismas cajas a las dos filas. El
cruce va por **`(cod_base, linea)`** y el front lee el número de **su propia fila**, no de un mapa.

**Al escribir una vista o una pantalla que cruce un código de `Entregas_Virgilio` / factura contra
stock o góndola: el artículo por `gv_cod_stock_de_entrega`, la empresa por `gv_empresa_de_entrega`,
en columnas separadas — nunca `norm_cod` a secas y nunca concatenados.** Lo sostienen
`tests/fcs-codigo-l.cjs` —que corre `pkResolveArt` de verdad y compara contra la base, así que avisa
si el front y el SQL se desfasan— y cuatro filas en `GV_Reglas_Centinela`.
`sql/gv_fc_sin_salida_codigo_l_v2113.sql`, §3.mj.

**Chequeo** (el operario tiene que ver el código pelado y la góndola LK):

```sql
-- el pedido con L …
select np_label, articulo from public."PPP_Web_Base" where empresa='chef' and articulo ~ '[0-9E]L$';
-- … y el picking sin L: ningún movimiento de stock puede terminar en L
select cod_art from public."Movimientos_Stock" where cod_art ~ '[0-9E]L$';   -- vacío = todo bien
```

## ⚠ Regla de Thomas (2026-09-18, v20.17 · asentada v20.20): el EXCEDENTE va en el ORDEN DEL RECORRIDO

Probando el módulo de operarios con una tanda: *"primero le dice que pickee del excedente, eso
rompe el flujo de movimiento por las góndolas"*. Y sobre la regla que lo había puesto adelante:
***"olvidate de esa regla de excedente primero hasta nuevo aviso"***.

**La v15.41 (pedido de Luis) queda DEROGADA hasta que Thomas diga lo contrario.** No volver a
poner los pasos `art·EXC` al principio, ni "mientras tanto" ni como fallback: hoy se ordenan por
el `orden` del sector donde está el excedente y, sin ese dato, van al final.

Por qué, medido el 18/09 sobre `GV_Lugar` — y es el dato que la v15.41 no miró:

| zona | `orden` |
|---|---|
| góndola de picking (pasillos A..Ñ) | 1 – 657 |
| racks K/N/O | 706 – 717 |
| **zona P, donde se apila el excedente** | **718 – 757** |

El excedente está **después de toda la góndola**: ponerlo primero es mandar al operario al fondo
del depósito y hacerlo volver al pasillo A.

⚠ **Lo que se resigna a propósito:** si el excedente miente (el saldo dice 10 y hay 6), el paso de
góndola de ese artículo ya pasó. Era justo lo que buscaba la v15.41 y **Thomas decidió que manda el
recorrido**. Si algún día molesta, el arreglo NO es volver atrás: es que el faltante del excedente
**reabra** el paso de góndola de ese artículo. Eso tampoco se hace sin que lo pida.

Lo sostiene `tests/pk-excedente-orden.cjs` y el candado invertido de `tests/pk-deposito-pkc.cjs`
(`items.concat(excSteps)` tiene que estar, `excSteps.concat(items)` no). Problema 455.

## ⚠⚠ REGLA (Thomas, 2026-09-23, v21.47): los FERIADOS tienen UNA tabla canónica — `GV_Feriados`

**Thomas, textual:** *"que quede bien definido que es la canónica así cualquier implementación que
requiera ver feriados la podés encontrar a futuro y dejar de duplicarla"*.

> ## Si algo necesita saber si un día es feriado, lo pregunta a **`public."GV_Feriados"`**. No se escribe la lista de nuevo.

**Estaba escrita TRES veces, a mano:** `FERIADOS_AR` en `index.html`, `FERIADOS` en
`monitor/tv.html` y el CTE `feriados` adentro de `gv_monitor_horas_operario_dia`. Medido el
23/09: las tres tenían **las mismas 16 fechas** — pero las tres **terminaban el 2026-12-25**, así
que desde el 1.º de enero ninguna conocía un solo feriado. Ahora las tres leen la tabla, que ya
tiene 2027 (16 feriados, con los trasladables en su fecha observada).

⚠⚠ **Son TRES tablas distintas y no hay que mezclarlas.** La que se elige mal es siempre la misma:

| pregunta | tabla | qué mueve si se carga ahí |
|---|---|---|
| ¿es feriado nacional? | **`GV_Feriados`** · `gv_es_feriado(d)` | el conteo de horas de un cierre que cruza la medianoche |
| ¿se trabaja en el depósito? | `GV_Dias_No_Habiles` · `gv_es_dia_habil(d)` | los días hábiles de **toda** la operación: la espera de cada pedido, el tope de 10 y la anticipación mínima de 4 |
| ¿sale el camión? | `GV_Dias_Sin_Reparto` · `gv_es_dia_con_reparto(d)` | la programación del reparto |

⚠ Los **puentes turísticos** van con `tipo = 'no_laborable'` y **NO son feriado**: en el depósito se
trabaja. `gv_es_feriado` los devuelve `false`. Están cargados a propósito, para que nadie los vuelva
a agregar como feriado "porque faltaban".

**Agregar un año es un `insert`, no un deploy** (fuente: Ley 27.399 + decretos; los trasladables van
con su fecha OBSERVADA y el original en `trasladado_de`):

```sql
insert into public."GV_Feriados" (fecha, nombre, tipo, trasladado_de)
values (date '2028-01-01', 'Año Nuevo', 'feriado', null) on conflict (fecha) do nothing;
```

⚠ **El hardcodeo del front NO se borró: quedó de FALLBACK.** Si el fetch falla o vuelve vacío, la
lista vieja de 2026 sigue puesta — mejor ésa que ninguna. Por eso `ensureFeriadosAR` (index.html) y
`cargarFeriados` (tv.html) sólo pisan la lista **si vino algo**.

⚠ Los puentes de **2027** los fija el PEN por decreto y al 23/09/2026 no estaban publicados: ese año
va sólo con los feriados de la ley.

**Chequeo:** `select tipo, count(*) from public."GV_Feriados" group by 1;` — al 23/09, 32 feriados
(16 de 2026 + 16 de 2027) y 3 no laborables. `sql/gv_feriados_v2147.sql`.

⚠⚠ **NO se automatiza: Thomas decidió (23/09) que se ajusta A MANO en enero.** Textual: *"no, queda
para que se ajuste manual en enero"*. **No volver a proponer el cron.** Se midió antes de decidir:
API oficial del Estado no hay (`datos.gob.ar` da 502), y las dos comunitarias son complementarias y
ninguna alcanza sola — **Nager.Date** trae los trasladables ya movidos pero **no trae los puentes**,
y **ArgentinaDatos** marca los puentes pero devuelve los trasladables **sin mover** para los años sin
decreto (Güemes 2027 el 17/06, cuando por ley cae el 21/06). El detalle y lo que falta cargar en
enero están en `docs/ESTADO-Y-PENDIENTES.md` §2.

## ⚠ REGLA (Thomas, 2026-09-23, v21.47): un centinela de PATRÓN no ve un cambio de CUENTA — para eso está la HUELLA

`gv_reglas_perdidas` contesta *"¿el patrón sigue en el cuerpo?"*. Es lo que hace falta cuando el
riesgo es que otra sesión pise el objeto con una copia vieja. **No sirve** cuando el riesgo es que
alguien deje el patrón puesto y le cambie la cuenta.

Eso pasa cuando el cuerpo de un objeto está **espejado afuera de la base**. El caso concreto:
`tests/mon-vs-vista.cjs` corre el monitor grande de verdad y lo compara contra
`tests/tools/vista-15.json`, que es una **foto** de `gv_monitor_horas_operario_dia('2026-09-15')`
—las sesiones no le pueden pegar a Supabase, así que esa mitad va congelada—. Si alguien le cambia
una regla a la función y el JSON no se mueve, **el test queda verde y miente**.

```sql
select * from public.gv_huellas_cambiadas;   -- vacía = todo bien
```

**Al cambiar a propósito un objeto con huella, son dos pasos y el segundo lo dicta la vista:**

1. volver a congelar lo que lo espeja (cómo, está adentro del propio fixture);
2. `update public."GV_Huella_Objeto" set md5_esperado = '<el md5_actual que imprime la vista>',
   version = '<vNN.NN>', actualizado_en = now() where objeto = '<el objeto>';`

⚠ **Salta también por un comentario, y está bien:** es un md5 del cuerpo entero. Un falso positivo
cuesta releer el fixture; un falso negativo cuesta un test que miente. Verificado rompiéndolo a
propósito (un comentario metido en el cuerpo, en transacción abortada: la vista devolvió su fila).

**Al espejar el cuerpo de un objeto afuera de la base, agregarle su fila** — es un `insert`, no
código. `sql/gv_huella_objeto_v2147.sql`.

## ⚠ REGLA: LAS TABLAS QUE VALEN — góndola, racks y empresa del artículo

**Luis, 2026-09-17:** *"fijate que estés usando las tablas actualizadas de `gv_` y escribí en
algún lado que esas son las tablas que valen para que no se vean tablas desactualizadas o
erróneas"*. Hay tablas viejas conviviendo con las vivas, con el **mismo contenido aparente**, y
leer la que no es da respuestas que suenan bien y están mal.

| Para saber… | **LA QUE VALE** | La vieja, NO usar |
|---|---|---|
| Qué artículo va en qué sector de **góndola**, y de qué empresa es el sector | **`GV_Lugar` + `GV_Lugar_Item`** → vista **`gv_lugar_articulo`** (y `gv_planimetria_celda`) | `Planimetria` ⚠ ver abajo |
| Qué hay cargado en cada **rack** | **`Racks_Planimetria`** | **`Ubicaciones_Articulos`** |
| De qué **empresa** es un artículo (el dato de la columna LK/CH) | **`gv_empresa_de_articulo(cod)`** y su caché `GV_Articulo_Empresa_Cache` | `gv_articulo_empresa` (la vista rota) |

**Medido el 17/09**, que es lo que decide cuál está viva:

| tabla | filas | último movimiento |
|---|---|---|
| `GV_Lugar` / `GV_Lugar_Item` | 872 / 790 | **2026-09-16** |
| `Racks_Planimetria` | 154 | **2026-09-16** |
| `Ubicaciones_Articulos` | 872 | **2026-08-10** ← congelada hace más de un mes |
| `Planimetria` | 370 | 2026-09-11 |

Y quién las escribe: `Racks_Planimetria` la mueven `racks_plani_ingreso`, `racks_plani_descontar`,
`racks_plani_mover`, `registrar_baja_racks` y `vista_insumos` — o sea, la app. A
`Ubicaciones_Articulos` **no la escribe nadie** desde el 10/08.

### ⚠ `Planimetria` está congelada pero NO se borra

Dejó de leerse para el picking en la **v15.77** y de escribirse en la **v17.26**, así que como
fuente **no vale**. Pero tiene un rol vivo a propósito, y el código lo dice en tres lugares:
guarda los **códigos huérfanos que nunca llegaron a `GV_Lugar_Item`** (los 17 del problema 156 —
palos de amasar 231/232/233, línea Acacia, 537, 567…), y el Mapa de góndolas los **rescata de ahí
con un click** (`pmapViejaFetch` / `pmapViejaTraer`). Además la leen `gv_codigos_multigrafia` y
`vista_nc_loeke_chef`. **No usarla como fuente, no borrarla.**

**Cuánto se superpone con las `GV_`, medido el 17/09**: de los 370 pares (código, sector) de la
vieja, **335 son idénticos** a la viva. De los 25 códigos que sobran, **8 son duales escritos con
sufijo de empresa** (`437E CH`, `809E LK`… misma info, otra grafía), **1 es basura** (`LIBRE`) y
**16 son códigos reales sin lugar en `GV_Lugar_Item`**, 12 de ellos con movimientos (580E con 153,
232, 231, 233, 865ED, 702EN, 537, 567, 828, 997E, 998E, 702). **Ésos 16 son la razón por la que la
tabla no se borra** — y el motivo por el que `gv_empresa_de_articulo` la usa como **último
recurso**, filtrada (nunca un dual, nunca un pseudo-código con sufijo, nunca `LIBRE`).

`Ubicaciones_Articulos` es otra cosa: **38 días sin escribirse, 0 funciones y 0 lectores en el
front**. Ésa sí no sirve para nada vivo.

### El centinela: `gv_fuentes_lugares`

Para no tener que volver a medir esto a mano, la vista dice sola cuál está viva:

```sql
select * from public.gv_fuentes_lugares;
-- tabla · rol · última escritura · días sin escribirse · funciones y vistas que la leen
```

### Lo que costó descubrirlo

Buscando dónde estaban físicamente las cajas del **809E**, `Ubicaciones_Articulos` decía que en el
rack `AD5` había un código **`809E-QUESO`** y en `Y12` un **`809E-PIZZA`**. Los dos son **inventos
de esa tabla**: no existen como artículo ni como insumo (**0 movimientos** en `Movimientos_Stock`,
0 en el depósito `insumos`) y son los **únicos dos códigos con guion** de toda la tabla. La tabla
viva dice lo correcto: el código es `809E` y el rack de LK es **`AE11`**, no Y12.

### ⚠ Los sectores de rack van con CERO adelante: `AD05`, no `AD5`

**27 de los 29** sectores de `Racks_Planimetria` que no existían en `GV_Lugar` eran el mismo error
de tipeo: falta el cero. Se corrigieron 26 (los que tienen gemelo `rack`) el 17/09, backup en
`zz_backups."GV_Backup_RacksPlani_sectores_20260917"`. **Al cargar un rack a mano, escribir el
sector como está en `GV_Lugar`.** Chequeo:

```sql
select distinct r.sector from public."Racks_Planimetria" r
 where not exists (select 1 from public."GV_Lugar" l where l.sector = r.sector);
-- al 17/09 quedan 3 y son otro problema, no el del cero: O2, O5 (no existen en ninguna forma)
-- y Z7 (su gemelo Z07 existe pero es GÓNDOLA, no rack)
```

### ✅ La contradicción de AD06 — resuelta por el conteo del 17/09

`AD06` figuraba con dos filas: `CH / 809E / 360 cajas` (del 08/07) y `LK / 368E / 56` (del
31/08), con `GV_Lugar` diciendo que AD06 es un rack de **LK**. Luis contó: **en AD06 hay 368E,
14 MC**, y punto. Las 360 de 809E CH eran layout viejo que ya no estaba (ni en el libro de
stock: el saldo de racks eran las 336 de AD05), así que se borraron. Igual `AE11 / 809E / 8 MC`.

**Y apareció la misma contradicción en AD05**: tenía `emp = CH` pero las 28 MC que hay adentro
son **809E de Loekemeyer**. Se aplicó el criterio de Luis para el 396 en P39 (*"la góndola está
mal asignada, ajustala"*): **AD05 pasó a LK**, el artículo no se movió. v19.33,
`sql/gv_conteo_809e_v1933.sql`.

⚠ **Y el que muerde: `809` y `809E` son artículos DISTINTOS, los dos de Chef.** El `809` es el
secundario, vive en la góndola **M16**; el `809E` de Chef está en **M14**. Contar las cajas de
M16 como 809E le habría sumado 9 al código equivocado. Lo frenó Luis en el momento.

### ⚠ Un código DUAL no tiene empresa: `gv_empresa_de_articulo` contesta **NULL**

Los 4 de `codigos_duales` (437E, 438E, 439E, 809E) viven en las **dos** góndolas: la empresa la
dice de qué pila salió la caja, o sea el **pedido**, no el artículo. Hasta la v19.30 la función
devolvía **`'LK'`** para 437E/438E/439E, porque la góndola hoy los tiene de un solo lado — falso, y
el tipo de respuesta que suena bien y está mal. El trigger nunca se la comió (chequea
`codigos_duales` **antes** de llamarla), pero cualquier otro llamador sí. Ahora el guard está
adentro de la función y del refresco del caché. Chequeo:

```sql
select cod, public.gv_empresa_de_articulo(cod) from public.codigos_duales;
-- las 4 tienen que dar NULL
```

### ⚠ Y un DUAL **no es el mismo artículo de los dos lados: cambia el PACKAGING**

**Luis, 2026-09-21:** *"No son el mismo artículo por más que tengan el mismo código. Cambia el
packaging, por eso está dividido así."*

Es la pregunta que se hace sola al mirar el generador de OC, porque los números invitan a
equivocarse. Medido ese día:

| código | stock lado LK | stock lado CH | se pide (CH) |
|---|---|---|---|
| 437E | 286 (189 en racks) | 14 | 145 |
| 809E | 349 | 113 | 126 |
| 438E | 117 | 3 | 86 |
| 439E | 15 | 8 | 10 |

Leído como si fuera un solo artículo, eso parece **357 cajas que se compran teniendo 767 del otro
lado**, o sea un traslado de góndola disfrazado de compra. **No lo es.** Son dos productos
distintos con el mismo número: la caja de Loekemeyer no sirve para un pedido de Chef.

**Entonces:** el generador está haciendo lo correcto al pedir por separado, y **nunca hay que
proponer "trasladar de la góndola LK a la de Chef" para ahorrarse la compra**. La única
consecuencia del código compartido es la de siempre: la empresa la da de qué pila salió la caja
(el pedido), no el artículo.

## ⚠ REGLA: el CÓDIGO DE CLIENTE es por EMPRESA — nunca cruzar por código solo

**Thomas, 2026-09-16:** *"¿contemplaste que los códigos de clientes de LK y CH son diferentes?
Un cliente puede tener un código en LK y otro diferente en CH, y el mismo número de código puede
ser de dos clientes diferentes (uno de LK y otro de CH)."* Es la contracara operativa de la regla
de arriba (*"el cod cliente no significa nada, sólo el CUIT vale"*, v13.76), y hay que tenerla a
mano **cada vez que se escribe una consulta**, no sólo al pensar en identidad de clientes.

**Medido el 16/09 sobre las facturas parseadas** (`isis_lk.documentos` / `isis_ch.documentos`):

| | |
|---|---|
| códigos de cliente en facturas de **LK** | **1.057** |
| códigos de cliente en facturas de **Chef** | **396** |
| códigos que existen en **las dos** | **115** |
| …de esos, **clientes DISTINTOS** | **114** |

O sea: **cuando un código coincide entre las dos empresas, el 99 % de las veces son dos personas
distintas.** Cruzar por código sin empresa no es "un poco impreciso": está mal casi siempre que
matchea. Ejemplo del día: **4181 en LK es Mitre Hugo Alberto; en Chef ese código no existe.**

```sql
-- el barrido que lo mide (y que hay que repetir si se duda)
with lk as (select distinct regexp_replace(coalesce(contraparte_codigo,''),'^0+','') cod,
                   (array_agg(contraparte_nombre order by fecha desc))[1] nombre
              from isis_lk.documentos where familia='factura_venta' group by 1),
     ch as (select distinct regexp_replace(coalesce(contraparte_codigo,''),'^0+','') cod,
                   (array_agg(contraparte_nombre order by fecha desc))[1] nombre
              from isis_ch.documentos where familia='factura_venta' group by 1)
select count(*) comparten_codigo,
       count(*) filter (where upper(btrim(lk.nombre)) <> upper(btrim(ch.nombre))) son_otro_cliente
  from lk join ch using (cod);
```

**Qué hacer siempre:**
- La clave de un cliente es **`(empresa, cod)`**, nunca `cod` solo. Vale para `Facturacion_NP`,
  `PPP_Web_Programacion`, `Entregas_Virgilio`, `GV_Clientes_Direcciones`, `GV_Clientes_Nuevos`,
  `cobranzas_cliente_cadena` y cualquier tabla con `cod_cliente`.
- Las facturas viven en **dos esquemas separados** (`isis_lk` / `isis_ch`): buscar la factura de
  una NP **en el esquema de SU empresa**, no en los dos.
- La empresa de una NP sale del **prefijo** (`LK …` / `CH …`) o, en las de ISIS, de
  **`> 90000 = LK`** (la regla que usa `gv_ppp_prog_arbol`). No inventar otra: un
  `np ~ '^4\d{4}$'` acierta con las NP de Chef de ISIS pero **manda las `CH 0012` web a LK**.
  Lo que ya existe y es de fiar: `gv_empresa_de_np_texto(np)` y `gv_emp_de_np(np)`.
- Las funciones que ya lo hacen bien y sirven de molde: `gv_fac_rs_np` (cruza por
  `empresa + cod`) y `gv_vista_cruce_facturacion` (`d.empresa = b.empresa`).

⚠ **La excepción que rompe hasta esto: Tierra del Fuego.** Una NP de **LK** se factura en el
ISIS de **Chef**, con el **código de cliente de Chef** (regla v13.77, arriba). Si se busca la
factura en `isis_lk` con el código LK no aparece, y la NP queda como *"sin factura"* sin estarlo.
El mapeo `(lk, cod) → (chef, cod_isis)` está en **`GV_Cliente_Isis`** (9 filas al 16/09):
**antes de concluir que una NP de LK no se facturó, mirar ahí.**

## ⚠ Regla del dueño (2026-09-07, v14.12): el agregado va en tanda nueva SÓLO si mezclaría ISIS con web

*"Solo va en tanda nueva si mezcla lo que es pedido isis y pedido web"* → **el corte es el ORIGEN, no
"¿ya se pickeó?"**. Agregado web + tanda **WEB** del mismo cliente y día, sin empezar → **se junta**.
Agregado web + tanda de **ISIS** → **siempre tanda nueva**, aunque nadie la haya tocado. El guard de
"sin empezar" se mantiene (sumarle algo a una tanda ya pickeada rompe el picking).

Vive en `gv_ppp_web_tanda_abierta_cliente` (sólo mira `PPP_Web_Programacion`; las tandas de ISIS **no**
son candidatas), que usa el bloque (a1) de `gv_ppp_web_armar_pendientes` en los crons 71 y 73.
**Desde v18.87 recibe un 4.º argumento, la zona**, y sólo devuelve tandas del mismo camión (regla de
Luis, más abajo); la firma de 3 argumentos se dropeó a propósito para que ningún llamador viejo siga
resolviendo a la vieja en silencio.
**La v14.05 lo había leído al revés** y metía pedidos de la página adentro de tandas de ISIS; se corrigió
en la v14.12. Caso testigo: Osa (2533, mié 09/09) → `E09A` ISIS + `E09B` web, mismo camión, picking
separado. §3.ca/§3.cb de `docs/SUPABASE-GESTION-VIRGILIO.md` y `sql/gv_ppp_web_tanda_abierta_cliente_v1412.sql`.

## ⚠ Regla del dueño (2026-09-07, v14.00): en el CHAT, los nombres; en la APP, los códigos

*"Yo nunca entendí CCR y CCN. Para mí es control remitos, carga camión y recepción remitos, sólo esos
nombres entiendo"* → **hablarle SIEMPRE con los nombres**: `CR`/`CCR` = **Control Remitos** · `CC`/`CCN` =
**Carga Camión** · `RR`/`CRN` = **Recepción Remitos** · `TAP` = armado terminado · `TAL` = armado de la NP.

**Eso NO es un pedido de cambiar la pantalla.** Cuando se interpretó así (v13.97, revertida en la v14.00) la
corrección fue textual: ***"en la app no tenías que cambiar nada. CR, TAP, CC, RR para operarios está ok"***.
Los operarios los usan todos los días y son los de los botones. **No tocar los códigos en la app ni en la base.**

## ⚠ Regla del dueño (2026-09-07, v14.23): el SÚPER no se junta con clientes

*"Súper no se puede juntar con clientes. Ya tenías esa regla. Van separados."* → un camión que
lleva un súper (Coto, Carrefour, Chango Más, Krikos…) **no lleva ningún cliente común**, y al
revés. Nada de "aprovechar el viaje" porque quede cerca.

**El armado automático ya la respeta** (`gv_ppp_web_camion_del_dia` sólo reusa camiones con
`zona !~* 'super|retira|expo'`; el bloque 3b dice que un súper con zona numérica no es camión a
esa zona). Lo que NO la respetaba era el atajo manual: un `GV_PPP_Prog_Override` metido a mano
se saltea esa función. Pasó el 07/09 —se enganchó Luján al camión de Chango Más en Moreno
porque quedaba a 31,5 km— y se revirtió el mismo día.

**⚠ La tabla que manda es `GV_Supers`** (19 activas), NO `gv_clientes_horario` (24: agrega 3
clientes comunes que piden turno y se come 1 súper que no lo pide). El front (`pppSupersNeed`) y
el backend (`gv_es_super`) ya usan la buena.

**⚠ Y la regla se rompe por ZONA, siempre en el mismo lugar: un súper con zona numérica.** Dorinka
(Chango Más) y Diarco vienen como *"Zona 5 - GBA Oeste"*, así que cualquier filtro escrito como
`zona !~* 'super|retira|expo'` los deja pasar. Se tapó tres veces — `_sin_tanda` (v18.28), `_ex` y
`gv_ppp_web_dia_camion` (v18.60) — y en la v18.87 apareció la cuarta: `_open`, la lista de tandas
que todavía acumulan, metía clientes comunes **adentro de la tanda del súper**. **Al tocar el
armado, buscar `'super|retira|expo'` y preguntarse si ahí no debería ir `gv_es_super`.**

**⚠ Y no se prueba leyendo el código.** Las tres puertas anteriores parecían cerradas; la cuarta
la destapó correr `ppp_web_armar_tandas` de verdad con `p_filas` de prueba dentro de una
transacción abortada. Problema 334.

**Chequeo:** `select * from public.gv_ppp_super_mezclado;` — vacía = todo bien. Mirarla después
de tocar tandas a mano. Desde v18.87 dice además si el camión se armó **AUTOMÁTICA / MANUAL /
ISIS** (`camion_armado`, `origen`, `origen_detalle`) y deja afuera las tandas de
`GV_Vehiculo_Propio` (la kangoo no es el camión). `sql/gv_ppp_super_mezclado_v1887.sql`, §3.ic.

## ⚠ REGLA (Luis, 2026-09-21, v20.70): el ARMADO es de la TANDA — el pedido de adentro puede ser otro

**Luis, al ver que D69H figuraba armada:** *"nunca se pickeo pero figura como armado? como, por
qué?"*.

`EP`, `TP`, `AP` y `TAP` son eventos de la **TANDA**: `texto = 'D69H'`, sin NP. Una vez que una
tanda tiene TAP **queda armada para siempre**, aunque después le saquen y le pongan pedidos
adentro. El único registro por NP es **`Entregas_Virgilio`** (np, artículo, pedidas / entregadas /
faltó), y nada relaciona una cosa con la otra.

**Caso D69H (21/09):** su TAP del 16/09 era de **LK 0058**, un pedido que ya no estaba en la
tanda; los dos que sí estaban —LK 0070 y LK 0083, **62 cajas, 15 líneas**— no tenían ni picking ni
armado, y la tanda salía el miércoles marcada como armada.

**Chequeo:** `select * from public.gv_tanda_armada_sin_armado;` — vacía = todo bien. Marca la NP
programada a futuro que está en una tanda con TAP vivo sin una sola línea propia en
`Entregas_Virgilio`.

⚠ **Para deshacer un evento NO se borra la fila: se le cambia la opción** (`TAP→TAPX`, `AP→APX`,
`TP→TPX`, `EP→EPX`, `PKC→PKCX`), más su fila en `GV_Tanda_Anulada`. Borrarla libera el
`client_id` y **la cola offline del celular resucita el evento** (v18.71/72, caso E25A: borrado
16:56, reinsertado 17:17). Con la X la fila sigue ocupando su `client_id` y ningún consumidor la
cuenta, porque todos filtran por igualdad exacta. Ya existen `anular_armado_virgilio` y
`gv_anular_picking_virgilio`, pero **sólo sirven dentro de las 72 h / 3 días y para el mismo
legajo**: más viejo que eso se hace a mano con ese mismo patrón y con backup.

⚠ **Y el armado NO mide lo que hay: resta.** `cajas_entregadas = cajas_pedidas − faltante
declarado`, con `cajas_pedidas` saliendo de `PPP_Web_Base`. Nunca mira cuántas cajas se
pickearon, así que con el pallet vacío escribe *"entregadas = pedidas"* si nadie declara el
faltante. **Pendiente de Luis (21/09):** *"cuando se arma el pedido, debería definirse (tenés que
saber qué carajo estás armando en base a lo que tenés y quedar anotado para cada NP, así es como
funca la facturación actualmente)"*. `sql/gv_tanda_armada_sin_armado_v2070.sql`,
`tests/ppp-tanda-armada-sin-armado.cjs`, §3.lp.

## ⚠ QUIÉN ORGANIZA LA PROGRAMACIÓN: el automático arma, **MARIANELA** organiza

**Definido por Luis, 2026-09-17.** Hasta ese día no estaba escrito en ningún lado, y por eso una
tanda mal armada podía quedar semanas a la vista sin que fuera de nadie (pasó con D69F).

**Medido sobre los últimos 30 días**, que es lo que hizo falta para definirlo:

| quién deja programada una NP web | NP | de ésas, retocadas |
|---|---|---|
| **`sistema`** (crons 71 y 73) | **148** | 91 |
| `loekemeyer.n8n@gmail.com` (el panel) | 21 | 19 |

O sea: **el automático organiza el 88 %**. Lo que se toca a mano se toca desde una **cuenta
compartida**, así que la base guarda la cuenta y no la persona. Luis decidió **dejarlo así** (no se
agrega firma por legajo): la responsabilidad se define acá, no se deduce del dato.

**Marianela Becker** (Planify **38**) es la responsable de lo que el automático NO resuelve:

- **A Programar**: Retira sin día elegido, súper, pedidos sin zona y los que no tienen camión previsto.
- **Los choques de regla**, que el sistema a propósito **no** resuelve solo y deja a la vista:
  un cliente que hay que juntar en un día pero ese día no tiene camión de su etiqueta
  (`gv_ppp_cliente_dos_dias`), y una tanda repartida en dos camiones (`gv_ppp_tanda_camion_mezclado`).
- **Mirar esos dos centinelas**, que es justamente lo que no pasaba: D69F estaba ahí desde el 16/09
  y se encontró recién el 17/09 barriendo a mano.

```sql
select * from public.gv_ppp_tanda_camion_mezclado;   -- vacía = todo bien
select * from public.gv_ppp_cliente_dos_dias;        -- vacía = todo bien
select * from public.gv_ppp_super_mezclado;          -- vacía = todo bien
select * from public.gv_ppp_tanda_dos_dias;          -- vacía = todo bien
```

⚠ **Que una tanda salga marcada NO la arregla sola, y Claude no la toca por su cuenta**: mover una
NP de tanda es decisión de armado. Se reporta; lo decide Marianela. Con D69F, Luis lo dijo
explícito el 17/09: *"no toques D69F"* — la tanda sale así el lunes 21/09.

## ⚠ Regla de Luis (2026-09-16, v18.87): la tanda de un cliente se parte por CAMIÓN

*"Claro que se parte en zonas distintas (si un mismo cliente pide para una sucursal que tiene en
Tucumán y otra en Río Negro, ¿lo pondrías en el mismo camión?). Se factura diferente también, es
uno de los criterios justamente para parsear qué factura correspondía con qué pedido (la zona)."*

> **el DÍA sigue siendo uno solo por cliente · la TANDA se parte por camión**

Así convive con la regla de Thomas (*"nunca si hay +1 pedido de un cliente puede ir separado en la
PPP, salvo los súper"*): Jazquel entrega todo el mismo día, pero lo de Balvanera/Once va en el
camión de **Capital** y lo de Ciudadela en el de **GBA Oeste**. Si las dos reglas chocan (hay que
juntar al cliente en un día y ese día no hay camión de su etiqueta), **gana ésta: la NP no se
mueve** y queda a la vista en `gv_ppp_cliente_dos_dias`.

**El corte es la etiqueta de `gv_ppp_web_camion`** (Capital / GBA Sur / GBA Oeste / GBA Norte),
**no el número de zona**: una tanda de CABA mezcla Zona 1+2 o 2+3 a propósito, por cercanía de
sectores, y va en el mismo camión. Medido sobre toda la historia, el corte por camión marca **una
sola** tanda mal (D69F) y el corte por número marca tres, dos de ellas sanas.

⚠ **La causa estaba en `ppp_web_armar_tandas`, que agrupaba `group by cliente` y tomaba
`min(camion)`** — no en `gv_ppp_web_tanda_abierta_cliente` ni en el pase (a1), que fue lo primero
que se arregló y no alcanzó. **Un cambio de regla de armado no está probado hasta que se corre el
armador** (con `p_filas` de prueba dentro de una transacción abortada, no leyendo la función).

**Chequeo:** `select * from public.gv_ppp_tanda_camion_mezclado;` — vacía = todo bien.
`sql/gv_ppp_web_tanda_por_camion_v1887.sql`, §3.ib.

## ⚠ Una tanda NO puede salir en dos días (v18.92, problema 338)

Un mismo código de tanda en dos fechas cae en **dos camiones distintos** y rompe todo lo que
agrupa por tanda: `vista_tanda_m3`, el camión, la hoja de ruta y la carga.

**Por dónde entraba:** el botón *"Reusar tanda"* al reprogramar una NP de ISIS desde *A Programar*
(`gv_ppp_isis_programar`, v16.03). Reusa el código anterior cuando todas las NP que entran vienen
de esa tanda — **pero contaba las que ENTRAN, no las que QUEDAN**. Caso D69C: el 16/09 11:59 se
reprogramaron 98615 y 98616 al 17/09 reusando D69C mientras 98622 seguía en D69C el 21/09.

Desde v18.92, si quedan NP de esa tanda en otro día **no se reusa**: va una tanda nueva y el aviso
dice por qué. **No se bloquea con un `raise` a propósito**: separar un pedido de su tanda es una
decisión legítima del supervisor, y el contenido es el mismo (no hay que volver a pickear).

**Chequeo:** `select * from public.gv_ppp_tanda_dos_dias;` — vacía = todo bien.
`sql/gv_ppp_isis_programar_reusar_v1892.sql`, §3.ig.

## ⚠ Regla de Luis (2026-09-17, v19.52): RETIRA con día elegido se programa SOLO y PISA EL CUPO

*"Necesito que viaje el dato y llegue a la PPP para que se pueda programar automaticamente"* · y
sobre el cupo: ***"si, igual que super con turno (que tambien tiene que viajar en el pedido)"***.

Las dos páginas le piden el **día** (mínimo +3 días hábiles, lun-vie) y la **franja** a quien marca
"Retira". Desde la v19.52 ese dato **viaja con el pedido**: LK → `lk_pedidos_match.retiro_fecha` /
`retiro_franja` por el FDW (cron cada 15 min), y lo lee `gv_web_retiro_pactado`. El pase **(a4)** de
`gv_ppp_web_armar_pendientes` lo programa ese día, con `p_forzar_cods` → **pisa el cupo**. Cada
Retira va en **su propia tanda** (no se mezcla con reparto ni con otro que retira).

**Sin día elegido no se programa solo**: queda en A Programar con el badge para completarlo a mano.
Pasa siempre con los que carga un admin por el **Cotizador** y con los **recuperados**
(`payload_recuperado`), que no pasan por el checkout.

⚠ **Un Retira puede no llamarse "Retira".** Lo que manda es `customer_delivery_addresses.zona_expreso`,
no el nombre de la sucursal: *"Convenir en Av. Panamericana"* tiene `zona_expreso = 'Retira'` y
`direccion_entrega = 'Virgilio 2788'` (el depósito). Antes de decir que un pedido con `retiro_fecha`
"no es Retira", mirar la zona, no la etiqueta.

⚠ **Al tocar el armado, buscar `'^\s*Zona\s*[0-9]+'` y preguntarse si ahí no falta Retira.** Los 11
pases lo exigen, y por eso durante dos semanas ningún Retira se programó solo aunque el cliente ya
hubiera elegido el día. Es el mismo tipo de agujero que `'super|retira|expo'` (regla del súper).

⚠ **Y "Retiro" NO es "Retira"** (v19.86): Retiro es un barrio de CABA (Zona 2). La regla web
matchea **exacto** (`^retira$`), nunca por subcadena — con `~* 'retir'` esas direcciones quedaban
marcadas como retiro en fábrica y no se repartían nunca. Y al revés: el retiro que viene por el
**expreso** (`nombre_expreso = 'Retira'`, 140 direcciones en LK) no se veía, porque `zona_expreso`
sigue trayendo el barrio del cliente y ganaba el `coalesce`. Se mira la dirección también
(`Exp. Retira — …`, `Virgilio 2788`). Centinela: `select * from public.gv_retira_sin_etiqueta;`
— vacía = todo bien. §3.js.

⚠⚠⚠ **Y desde la v20.74 el badge lo decide EL PEDIDO, no la ficha** (Thomas, 21/09: *"¿qué puso el
cliente? ¿que retira o que se lo entreguemos en algún lado? eso es lo que tiene que decir el badge…
a menos que se cambie de alguna forma"*). La columna `expreso` de `gv_np_destino` sale de
`es_retira` —la dirección y el barrio que viajan con la NP— y **no** de `nombre_expreso` del padrón:
si el pedido dice retira, el badge dice **Retira** aunque el padrón calle (eran 9 NP mudas); si el
pedido dice que se entrega, el badge **nunca** dice Retira aunque el padrón lo diga. `nombre_expreso`
sigue diciendo **por qué medio** viaja (Snaider, Arias…), que es para lo que sirve.

⚠ **Lo que eligió el cliente es una SUCURSAL: lo que define el modo es su DIRECCIÓN, no su nombre.**
*"Convenir en Av. Panamericana"* tiene dirección `Virgilio 2788` → retira. Medido al 21/09: 24 NP con
badge Retira y 24 con zona Retira, y **0** que se reparten diciendo Retira. §3.lr.

⚠⚠ **Y el error va también para el otro lado: un pedido que se REPARTE puede decir Retira**
(v20.66, Thomas 21/09, problema 470). El `nombre_expreso` de la ficha queda en `Retira` cuando un
cliente pasa de retirar a que se le entregue — nadie borra ese campo al cargarle la dirección — y
`gv_np_destino` lo publica como destino: Iro Iro (4223) figuraba **Retira** mientras iba en camión
a Longchamps, ya facturado. **Antes de sacarle la etiqueta de retiro a un pedido, mirar la zona de
la programación, no el `nombre_expreso`.** Y la señal de que el `Retira` de una ficha es resto y no
condición: **ese cliente tiene ADEMÁS su fila de retiro de verdad aparte** (`Virgilio 2788`, en
otro slot). Centinela: `select * from public.gv_retira_contradictorio;` — vacía = todo bien;
**sólo `service_role`**, porque cuelga de `gv_np_destino` y leída por `anon` contestaría vacía por
RLS, o sea que mentiría. §3.ln.

**Chequeo:** `select empresa, order_id, retiro_fecha, retiro_franja from public.lk_pedidos_match
where retiro_fecha is not null;` · `sql/gv_retira_dia_elegido_v1952.sql`, §3.ja.

## ⚠ Regla de Luis (2026-09-17, v19.44): la REPOSICIÓN CHICA no cae en cuarentena

*"Si un cliente hizo un pedido, se le factura (tiene deuda) y en un plazo de 10 días desde la
facturación entra un pedido de ese mismo cliente de 1 item (un código nada más que pide) debería
quedar exceptuado de la cuarentena."*

**Perdona SÓLO `deuda`.** Suspendido, sin cta cte y cliente nuevo siguen reteniendo. Configurable
en `PPP_Web_Config.cuar_repo_motivos`; `limite_credito` no entra ahí (lo arma
`gv_cuarentena_limite`, no `marcar_calc`). El plazo se cuenta contra la **fecha del pedido** y el
`max(fecha)` de la factura va **topeado a esa fecha** — sin el tope entran facturas posteriores al
pedido. Los ítems salen de `lk_pedidos_match.items_string`; la factura, de `isis_lk`/`isis_ch`
(la fuente de deuda no tiene fecha). Una NP de ISIS no se exime: sin datos, retener.

⚠⚠ **El primer intento (v19.41) dejó la CUARENTENA EN 0 y se revirtió (v19.43). Dos lecciones que
valen para cualquier cambio, no sólo para esto:**

1. **Un cast protegido por un regex en la MISMA condición no protege nada.** Postgres evalúa el
   cast primero. `(p.order_id)::bigint` con `'npNNNNN'` → `22P02` y la RPC entera devuelve 400.
   Se castea el bigint **de la tabla** a texto (`lp.order_id::text = p.order_id`), nunca al revés.
   Es el mismo pozo del problema 358, que ya estaba escrito acá.
2. **Lo nuevo no puede ir adentro del `Promise.all` de lo que ya funciona.** La RPC del chip
   estaba ahí: al fallar, el `await` tiró y `cuarMarcarPedidos` entero cayó al catch, o sea que
   **ningún** pedido quedó marcado. Ahora va en su propia llamada con su propio catch, y el
   backend llama al envoltorio **`gv_cuarentena_repo_seguro`**, que atrapa cualquier excepción y
   devuelve vacío (nadie exento = todos retenidos).

**Y se prueba rompiéndolo a propósito**: con `gv_cuarentena_repo_lote` reemplazada por un `1/0`,
`marcar_calc` tiene que seguir devolviendo los retenidos (medido: 60 rota / 59 sana).

**Chequeo:** `select * from public.gv_cuarentena_repo_hoy where exento;`
`sql/gv_cuarentena_repo_chica_v1944.sql`, §3.iy.

## ⚠ REGLA (Luis, 2026-09-21, v20.64): DÍA SIN REPARTO ≠ día no hábil

**Luis:** *"hace que la programacion automatica vea que el martes no se programa nada"*.

Un día puede tener el depósito **armando normal** y **ningún camión saliendo**. Son dos preguntas
distintas y hay que tenerlas separadas:

| pregunta | función | tabla |
|---|---|---|
| ¿se trabaja en el depósito? | `gv_es_dia_habil(d)` | `GV_Dias_No_Habiles` |
| ¿además sale el camión? | **`gv_es_dia_con_reparto(d)`** | + **`GV_Dias_Sin_Reparto`** |

⚠ **Nunca cargar un día sin reparto en `GV_Dias_No_Habiles`.** Eso dice "no se trabaja" y mueve el
conteo de días hábiles de **toda** la operación: la espera de cada pedido, los 10 días hábiles del
tope y la anticipación mínima de 4.

**Cerrar un día es un `insert`, no un deploy:**

```sql
insert into public."GV_Dias_Sin_Reparto" (fecha, motivo, creado_por)
values (date '2026-12-24', 'Nochebuena: no sale camion', 'Luis');
```

⚠ **Vaciar el día a mano NO alcanza: hay que cerrarlo.** El 21/09 una sesión movió las 12 tandas
del martes 22 a las 12:27 y **a las 12:45 el armador creó E12F para ese mismo día**. La puerta es
`gv_ppp_web_dia_camion`, que devuelve el primer día que ya tiene camión a esa zona y **a propósito
no mira el día mínimo** (v15.48). Correr el piso no sirve: hay que decir que ese día no hay camión.

**Al tocar el armado, los CINCO que eligen fecha** (los 11 pases de `gv_ppp_web_armar_pendientes`
no usan ningún otro): `gv_ppp_web_dia_camion`, `gv_ppp_web_proximo_dia_con_cupo`,
`gv_ppp_web_dia_minimo`, `gv_web_retiro_pactado` y —**el que se escapó, v20.83**—
`gv_ppp_web_dia_cliente`.

⚠ **El quinto no CALCULA el día: lo COPIA.** Por eso no aparece buscando `proximo_dia` ni
`dia_camion`, y la v20.64 lo dejó afuera: el martes 22 se cerró a las **13:38:37** y la corrida
del armador de las **14:30:13** igual creó `E12H` (LK 0193, Pezzali, Zona 3) para ese día, por
los pases **(a1)** y **(a2)**, que son los únicos que eligen la fecha ahí. La forma de
encontrarlos a todos no es grepear nombres: es mirar **quién le pasa una fecha a
`ppp_web_armar_tandas`**.

`ppp_web_armar_tandas` **no elige** —escribe la
fecha que le pasó el llamador— y por eso no lleva el salto: se lo comería el día que el cliente
pactó para su Retira.

**RETIRA (Luis, textual): *"Solo los que ya estan programados, no se programan retiros nuevos"*.**
Lo viene a buscar el cliente al depósito, no usa camión: el Retira ya programado **sale igual** y
no se mueve. Lo que se frena es programar uno nuevo ahí.

**Chequeo:** `select * from public.gv_dia_sin_reparto_ocupado;` — vacía = no quedó nada de reparto
en un día cerrado. Mira **web e ISIS** y saca lo que ya salió por CCN/CRN.
`sql/gv_dia_sin_reparto_v2064.sql`, `tests/ppp-dia-sin-reparto.cjs`, §3.ll.

## ⚠ REGLA (Luis, 2026-09-21, v20.91): el armado NO puede entregar más de lo que se pickeó

`Entregas_Virgilio` escribe `cajas_entregadas = cajas_pedidas − faltante`, y ese faltante sale del
reparto del Paso 2 del asistente, que vive detrás de un booleano **global**:

```js
const hayFalt = arts.some(a => a.nps.length);
```

`arts` sólo tiene los artículos que se pudieron cruzar contra `pickBase`. Si ese cruce falla
—un código que no matchea, un pedido que no está en la base— `hayFalt` queda en `false`,
`faltMap` sale **vacío** y se pierden **todos** los faltantes de la tanda: cada línea se escribe
*"entregadas = pedidas"* con el pallet a medio llenar.

**Medido sobre 90 días: 119 líneas, 554 cajas, 80 tandas** con el picking diciendo `real = 0` y el
remito diciendo entregado. Todas **dentro de la ventana de 5 días** — el dato estaba y se perdía
en el cruce, no por llegar tarde.

Desde la v20.91 hay un **TOPE que no depende del reparto**: el picking (PKC) dice cuántas cajas se
levantaron de cada código y la suma de lo entregado no puede pasarse de ahí. Lo que sobra se
recorta —por la NP que más entregó— y va a `cajas_falto`, que es lo que el remito tiene que decir.

⚠ **La clave del tope es ESTRICTA**: `codBase(pkStripL(cod))`. **No** colapsa la `E` final como
`_compMatchArt`: `809` y `809E` son artículos distintos y acá un match de más **recorta cajas que
sí están en el pallet**. Y **suma**, no toma el mínimo: `faltantesDeTanda` dedupea por el código
crudo, así que un dual entra dos veces (`438E LK` y `438E CH`) y las dos son cajas de verdad.

### ⚠ Y un armado ANTERIOR al picking no traba el armado de verdad

El candado anti doble-armado (v5.72) miraba sólo si la tanda tenía filas en `Entregas_Virgilio`.
**Caso E12L / LK 0043:** el 17/09 quedó registrado un armado **sin picking** (7 líneas, 15 cajas,
cero movimientos de stock ese día); el 21/09 Fabi pickeó de verdad y a las 15:38 Juan dio AP y se
comió *"La tanda ya fue armada"* — cuatro días después y con la mercadería en la mano.

**La regla:** un armado anterior al último `TP`/`PKC` de la tanda es de otro ciclo y no traba. Dos
armados del **mismo** ciclo son posteriores al picking y el candado sigue frenando igual (NP 98114).
⚠ **Ante cualquier duda, traba**: sin picking medible, sin fecha de armado o con el endpoint caído,
devuelve `true`.

### ⚠ Y «A Programar» no ofrece un pedido que ya salió

**Luis:** *"no me tires el histórico, fijate en lo que hay programado ahora che. de ahora en
adelante"*. Los guards de `gv_ppp_isis_sin_tanda` (facturada, entregada, cancelada) colgaban de un
`or o.desprogramada`, así que una NP marcada desprogramada volvía a ofrecerse aunque ya estuviera
facturada y entregada. Y faltaba el guard de **CCN / CRN**: un pedido puede haber salido en el
camión sin estar todavía en `Facturacion_NP`. Impacto medido: **0 NP** salen de la lista hoy — el
cambio cierra la puerta para adelante, no le saca nada al supervisor.

**Chequeo:** `select * from public.gv_reglas_perdidas;` · `node tests/comp-tope-pickeado.cjs` ·
`node tests/comp-armado-viejo-no-traba.cjs`. `sql/gv_isis_sin_tanda_freno_v2091.sql`, §3.lz.

### ⚠ Y un armado ANULADO tampoco traba: la `-X` es la salida, no un armado (v21.21, Luis 22/09)

**Luis, con la captura del operario:** *"le sale al operador pero me dicen que no la prepararon
todavía (la estaban preparando recién)"*.

Para deshacer un armado **no se borra la fila de `Entregas_Virgilio`: se le pega `-X` a la
`tanda`** (`E29D` → `E29D-X`) y queda su fila en `GV_Tanda_Anulada`. Es el mismo criterio que los
eventos (`TAP`→`TAPX`) y por el mismo motivo: borrarla libera el `client_id` y **la cola offline
del celular resucita el armado**.

`_compNpsYaArmadas` —el candado anti doble-armado **por NP**, v15.92— leía
`?select=np&np=in.(…)` **sin mirar la tanda**, así que una fila anulada trababa igual que una
viva, **y para siempre**.

**Caso E29D (22/09):** `LK 0034` se desarmó el 15/09 —17 cajas volvieron, 13 a góndola y 4 a
excedente— y se anuló el TAP (`GV_Tanda_Anulada` id 19). El 22/09 el operario, con el pallet a
medio preparar, se comía *"Ya está armado el pedido NP LK 0034, LK 0035 (en otra tanda)"*.

⚠ **Y el propio cartel le decía *"avisá para darlo de baja a mano primero"*, que era
exactamente lo que ya se había hecho: el candado ignoraba su propia salida.** Medido al 22/09:
**20 filas en 2 tandas** (`E29D-X` con 19 de LK 0034/0035, `D69H-X` con 1 de LK 0058).

⚠ **`_compTandaYaArmada` (el candado por TANDA) NO tenía el problema**, y por eso el síntoma
aparecía en uno solo de los dos: filtra `tanda=eq.<T>` y `E29D-X` no matchea. Que un candado
esté sano no dice nada del otro.

⚠ **La convención vive en UNA función, `_entregaAnulada(row)`**, no repetida en cada lector — la
usan también los dos lectores de `cajas_falto` (`cpCerrarTareaSiCompleta`, `faltMaybeCompletar`),
que sumaban las cajas de un armado anulado y dejaban la tarea de faltante abierta para siempre.
**Al leer `Entregas_Virgilio` por NP, pedir también `tanda` y pasarla por ahí.**

⚠ **Una fila SIN tanda (null o vacía) NO se toma por anulada: traba.** El candado es lo
conservador — mismo criterio que la v20.91 (*"ante cualquier duda, traba"*).

**Chequeo:** `select tanda, count(*) from public."Entregas_Virgilio" where tanda ~ '-X$' group by 1;`
· `node tests/comp-armado-anulado.cjs` (verificado que falla contra el código anterior).

#### ⚠⚠ Y la otra mitad es BACKEND: el DEDUP también toma la anulada como antecedente (v21.31)

**Luis, textual:** *"fijate que no vaya a pasar con ningún otro pedido. si fuese a pasar fijate
de hacer la corrección de antemano"*. Barriendo las NP programadas apareció el gemelo del bug,
del lado del servidor, y **ya había mordido**.

`entregas_virgilio_dedup` —trigger BEFORE INSERT de `Entregas_Virgilio`— descarta la fila cuando
ya existe **misma NP + mismo código + las tres cantidades iguales**, y **a propósito NO mira la
tanda** (v15.92: un pedido reprogramado y rearmado quedaba duplicado). Con una fila anulada
delante, ese mismo criterio **descarta la fila del rearmado**.

**Caso E29D / LK 0034 (22/09):** el armado del 15/09 se anuló; el 22/09 a las 15:31 el operario
rearmó y de las **19 líneas entraron 3** — sólo las que habían cambiado de cantidad. Las otras
16 se descartaron contra `E29D-X`: **38 cajas fuera del remito y de la factura**.

⚠ **Y no avisa nada**: el `INSERT` devuelve 201 igual, el evento `ENT` de la cola sí lleva los
18 códigos, y el operario ve *"Entregas registradas: 19"*. La diferencia sólo se ve mirando la
tabla.

> **Las dos mitades del mismo agujero**: el front (`_compNpsYaArmadas`) y el backend
> (`entregas_virgilio_dedup`) leen `Entregas_Virgilio` **por NP ignorando la tanda** — que es
> justo la columna donde viaja la marca de anulación. Arreglar una sola deja la otra viva.

⚠ **El dedup de verdad NO se toca**: dos armados iguales del mismo ciclo siguen descartándose,
porque esas filas están vivas. Probado con las dos mitades — una fila igual a una **anulada**
entra (1), una fila igual a una **viva** se descarta (0).

⚠ **Se aplica sobre `pg_get_functiondef`, es idempotente y falla con un `raise` si el texto no
matchea** (varias sesiones tocan estos objetos). El marcador adentro de la función dice `v21.22`,
que es la versión con la que se aplicó: **no cambiarlo**, es la llave que evita reaplicar.

**Chequeo:** `select * from public.gv_entregas_perdidas_por_anulacion;` — vacía = ningún remito
quedó incompleto por una anulación. Dice la NP, la tanda anulada, la viva, cuántos códigos y
cuántas cajas. **Sólo marca la NP que SE REARMÓ**: una anulación sin rearmado no perdió nada,
está esperando que alguien arme (por eso `LK 0058` / `D69H-X` no figura).
Y `select * from public.gv_reglas_perdidas;`. `sql/gv_entregas_dedup_anulada_v2131.sql`.

## ⚠ REGLA (Thomas, 2026-09-21, v20.86): lo ARMADO SIN DÍA tiene que verse en el badge

**Thomas, textual:** *"debería aparecer discriminado en el badge del icono de PPP en la página
principal del admin (un número rojo con los pendientes)"*.

**`GV_PPP_Armados_Espera` es un agujero por diseño si nadie lo mira.** Toda NP que esté ahí
pierde la `fecha_entrega` en `gv_ppp_programacion_diaria` —es el sentido del módulo: armado a
propósito sin día— así que **desaparece de todos los días de la Programación** y no puede figurar
como "Salió".

**Caso Iro Iro (21/09):** NP 98626/98627, 0,483 m³, pickeadas el 14/09, armadas el 15/09,
**facturadas el 16/09** y metidas ahí el 18/09. Tres días en el pallet, con la factura hecha,
sin aparecer en ninguna pantalla. **Lo encontró Thomas mirando, no el sistema.**

Desde la v20.86 es el tipo `armado_espera` de `gv_ppp_avisos` (orden 4, antes que los retenidos y
que las alertas web) y tiene su renglón en `gv_ppp_avisos_detalle` con las NP, la tanda, los m³,
la zona, los días que lleva y **si ya se facturó**, que es lo que apura.

⚠ **Cuenta PEDIDOS, no filas** (Iro Iro son 2 NP de un pedido = 1), igual que el resto del badge.

⚠ **`por` y `motivo` de esa tabla vienen NULL** en las dos filas que existen: el detalle dice
*"no quedó registrado quién ni por qué"* en vez de inventarlo. Si algún día se escribe quién lo
dejó ahí, el detalle ya lo muestra solo.

**El front no se tocó**: `pppFetchAvisos` y `pppAvisosAbrir` leen las dos vistas genéricamente,
así que un tipo nuevo aparece sin tocar `index.html`. **Al agregar otro aviso, se agrega en el
SQL y listo** — y con su fila en `GV_Reglas_Centinela`.

**Chequeo:** `select * from public.gv_ppp_armado_espera;` — lo armado sin día, con los días que
lleva y si está facturado. `sql/gv_ppp_armado_espera_v2086.sql`,
`tests/ppp-armado-espera-badge.cjs`, §3.lx.

## ⚠ REGLA (Thomas, 2026-09-21, v20.80): un pedido programado NO vuelve a «A Programar»

**Thomas, textual:** *"sacá del módulo programación la opción de mandar pedidos a «A programar».
Una vez programados o se eliminan o se reprograman para otra fecha"*.

| qué se quiere hacer | el único camino |
|---|---|
| que salga otro día | **📅 Cambiar de día** (`pgaNpMoverAbrir`): elige día y después tanda nueva o una existente |
| que no salga | **✕ Cancelar pedido** (`pppVencCancelar`): sale de la PPP y lo armado vuelve a «A guardar» |

⚠ **Las puertas eran TRES y en dos módulos distintos** —la fila de la NP en el árbol
(`pgaEnviarAProgramar`), y los dos paneles de la NP: pedido sin empezar (`pppVencVolver`) y vencido
(`pppVencSinProgramar`)—, más una **cuarta automática**: al corregir la dirección y cambiar la
zona, preguntaba si devolverlo a A Programar; ahora abre el pop-up de Cambiar de día. Las
funciones siguen en el archivo (como `gv_ppp_np_desarmar` en la v18.77): lo que no puede volver es
la **puerta**.

**Chequeo:** `node tests/ppp-sin-a-programar.cjs` — candado **estático** sobre `index.html`, porque
un test de pantalla prueba una puerta y deja pasar las otras dos. ⚠ No escribirlo con un regex
`[^"']*`: el `onclick` vive dentro de un string de JS con las comillas escapadas, así que ese regex
no matchea nunca y el test da **falso verde** (pasó en el primer intento, con las tres puertas
puestas). §3.lu.

⚠ **`GV_PPP_Web_Retenido` deja de recibir filas nuevas**, pero las que hay siguen vivas y su regla
—la de abajo— sigue valiendo: al programarlas vuelven a su tanda sólo si está sana.

## ⚠ REGLA (Luis, 2026-09-21, v20.56): un pedido retenido NO vuelve a una tanda que avanzó sin él

**Luis, textual:** *"esto me preocupa. estaban armados? qué interacción tienen si vuelven a
programación a su tanda y su tanda está armada/facturada/entregada cuando estos no?"*.

Cuando un supervisor saca un pedido de su tanda con «↳ Enviar a programar», `GV_PPP_Web_Retenido`
recuerda de qué tanda venía para devolverlo ahí. **Pero esa tanda sigue avanzando sin él.**

⚠ **Los flags `ya_pickeada` / `ya_armada` de la TABLA son la FOTO del momento en que se sacó el
pedido.** D69H decía `false` (del 15/09) y el 21/09 ya tenía TAP: el chip le decía al supervisor
lo contrario de la realidad. **Nunca leer esos flags de la tabla — leer la vista
`gv_ppp_web_retenido`, que los calcula en vivo.**

Probado en transacción abortada (LK 1448 → D69H): las 3 NP salían del árbol como **ARMADAS sin
haberse pickeado nunca** —su mercadería no está en ese pallet— y dejaban la tanda en **dos días**
(problema 338). Y una de ellas venía de **otra** tanda: la función tomaba una sola `tanda_previa`
con `limit 1` para todo el pedido.

**La regla:** vuelve a su tanda **sólo** si esa tanda está `sin empezar` o `no existe`. Con
`pickeada`, `armada`, `facturada`, `salio` o el código tomado, **va a una tanda NUEVA y se pickea
como cualquier otro**. Y si la tanda sale otro día que el elegido, se frena: una tanda en dos días
cae en dos camiones.

**Chequeo:** `select np_label, tanda_previa, tanda_estado, tanda_fecha from
public.gv_ppp_web_retenido;` · `sql/gv_retenido_tanda_viva_v2056.sql`,
`tests/apr-retenido-tanda.cjs`, §3.lg.

⚠⚠ **Y TAMPOCO vuelve si esa tanda es de OTRO CAMIÓN** (v20.94, problema 489). La v20.56 tapó
el ESTADO de la tanda y dejó abierta la ZONA: **LK 1448** (Silvano, Zona 6 - **GBA Norte**) tenía
como tanda previa **D69H** (Zona 2 - CABA Centro, camión **Capital**), y el chip decía *"esa tanda
sale el 23/09 y no se empezó: vuelve ahí"*. Seguir ese consejo parte la tanda en dos camiones y
pone `gv_ppp_tanda_camion_mezclado` en rojo (regla v18.87). Hoy el estado es **`otro camion`** y
el chip nombra los dos: *"esa tanda va en el camión Capital y este pedido en el de GBA Norte"*.

⚠ **Una tanda ya MEZCLADA también sale `otro camion`** (`camion_tanda` queda `Capital + GBA Norte`
y nunca coincide): no se le suma nada a una tanda que ya está mal. Y el corte es la **etiqueta** de
`gv_ppp_web_camion`, no el número de zona — una tanda de CABA mezcla Zona 1+2 a propósito.

⚠ La firma es **`gv_ppp_web_camion(text, text)`**, no `(text, date)`.
`sql/gv_retenido_camion_v2092.sql`, `tests/apr-retenido-camion.cjs`, §3.md.

⚠⚠ **Y el CÓDIGO de esa tanda queda RESERVADO mientras el pedido espera** (v20.60, Luis: *"el
problema si vuelve con el codigo viejo es si se pisa con algun pedido que haya quedado dentro de la
tanda con ese codigo y haya quilombo (como ya hubo)"*). Al sacar el **último** pedido de una tanda,
su código desaparece de todas las tablas vivas: `GV_PPP_Web_Retenido.tanda_previa` **no estaba**
entre las fuentes de `gv_tandas_codigos_usados_sync()`, así que volvía a la bolsa de códigos libres
y otra tanda se lo llevaba — y después el retenido caía **adentro de esa tanda ajena**. E50A, E26B
y E52A estaban las tres sueltas al 21/09.

**Son dos preguntas distintas y no hay que confundirlas:**

| pregunta | función | la usa |
|---|---|---|
| *¿este código se usó alguna vez?* | `gv_ppp_web_codigo_tomado(cod)` | el generador de códigos nuevos |
| *¿hay algo VIVO adentro que no sea mío?* | `gv_ppp_web_codigo_vivo(cod, empresa, order_id)` | el retorno del retenido |

La reserva es **viva** y la memoria la absorbe después (`fuente = 'retenido'`). **La vista nunca
puede preguntarle a la memoria**: el código que la propia reserva quemó bloquearía a su dueño y el
pedido no podría volver nunca. `sql/gv_retenido_codigo_reservado_v2060.sql`,
`tests/apr-codigo-reservado.cjs`, §3.li.

## ⚠ Regla de Luis (2026-09-21, v20.45): la ZONA es dónde va el camión; el DESTINO es otra cosa

**Luis, textual:** *"es especialmente importante poder identificar si el expreso tiene que
entregar a Misiones"*.

Un pedido por expreso tiene **dos lugares**, y la PPP sólo mostraba uno:

| | qué es | dónde se lee |
|---|---|---|
| **zona / barrio** | dónde lo deja el camión: el galpón del expreso, **en CABA** | `zona_expreso` |
| **destino** | dónde termina la mercadería: la provincia del cliente | `provincia` + `localidad` |

Medido el 21/09: **143 de 390** pedidos web de LK de 60 días van al interior (37 %), **141 con
zona de CABA/GBA**. LK 0027 (Albalandia, Puerto Rico, Misiones) se leía *"Zona 1 · Soldati"*.

**El dato SIEMPRE existió en las dos páginas** (`customer_delivery_addresses.provincia`) y ya
viajaba a Gestión en `GV_Clientes_Direcciones`. Lo que faltaba era **atarlo a la NP y mostrarlo**.

- Lo resuelve **`gv_np_destino`** (una fila por NP: provincia, localidad, expreso, `alerta`).
- Se resuelve **al LEER, no al escribir**: `PPP_Web_Programacion` tiene **cinco** caminos de
  escritura y persistirlo obliga a tocar los cinco. Al leer hay un solo lugar, sirve para las NP
  de ISIS y para lo viejo, y se corrige solo cuando el cliente corrige su dirección.
- Lo que desambigua es la **`etiqueta`** de la sucursal (el `label` de la página): **119 clientes
  tienen direcciones en más de una provincia**, así que cruzar por `(empresa, cod)` solo se
  equivoca. Sin señal, `provincia` queda **null** — no se inventa.

⚠ **Qué provincias se marcan NO está en el código.** Sale de `PPP_Web_Config.provincias_alerta`
(hoy `Misiones`). Para agregar otra es un `update`, no un deploy:

```sql
update public."PPP_Web_Config" set valor_texto = 'Misiones,Tierra del Fuego'
 where clave = 'provincias_alerta';
```

En la Programación: la NP marcada va naranja con el badge de la provincia, y el **día** y la
**tanda** que la contienen van naranja con la medalla *"Hay pedido Misiones"*. La marca **sube**
de la NP al día y a la tanda; no se calcula aparte.

**Chequeo:** `select * from public.gv_destino_sin_provincia;` — pedido programado cuyo destino no
se pudo resolver, con el `motivo` (v20.62). Al 21/09 son **24**: 20 direcciones del padrón sin
provincia cargada (9 de Cencosud) y 4 de dos clientes que no están en el padrón. **Ninguna
`ambiguo`.** `sql/gv_destino_misiones_v2045.sql`, `tests/ppp-misiones.cjs`, §3.kz.

### ⚠ Y una NP de ISIS **no trae expreso**: lo que desambigua es el BARRIO (v20.62, Thomas)

Medido el 21/09: **0 de las 120 filas** de `gv_ppp_programacion_diaria` traen `Exp.`. El
`Exp. <expreso> — <dir> (<etiqueta>)` lo arma la **página**; la NP de ISIS trae `direccion` y
`barrio` pelados. Así que para un cliente con sucursales en varias provincias, el destino de una
NP de ISIS se resuelve por el **barrio contra la localidad del padrón**, no por el expreso — que
además no alcanzaría: de sus 73 combinaciones (cliente, expreso) sólo **41 pintan una sola
provincia**. Y la etiqueta puede tener **paréntesis adentro** (`Río Gall (25 de mayo)`): el regex
del label tolera un nivel de anidado, o esas NP no matchean ninguna sucursal (pasó con LK 0178 y
LK 0179, a Santa Cruz, que se leían *"Zona 3 - CABA Oeste"*). Un **Retira** sale `como='retira'`,
no `ambiguo`: no hay expreso que entregue nada.

⚠ **Y la normalización va ADENTRO de `gv_destino_score`, repetida, no llamando a un helper.**
Una función SQL con `SET search_path` **no se inlinea**: llamarla 20 veces por par costaba
**3.590 ms contra 870** (4.338 pares, 3 corridas). Es feo a propósito y está comentado ahí.
`sql/gv_destino_isis_v2062.sql`, §3.lj.

⚠⚠ **Y la trampa que se comió la v20.45 entera, que vale para CUALQUIER vista nueva:** una vista
con `security_invoker = true` sobre una tabla con RLS **no da error cuando el lector no tiene
acceso — devuelve menos filas**. `GV_Clientes_Direcciones` tiene RLS sin policy, así que `anon`
no ve ni una fila y `gv_np_destino` le contestaba **HTTP 200 con `sin padron` para las 1.482 NP**.
Probarla desde el MCP no prueba nada: el MCP entra como `postgres`.

```sql
do $$ declare n int; begin
  set local role anon; select count(*) into n from public.<la vista>; reset role;
  raise notice 'anon ve %', n; end $$;
```

El arreglo **no** es abrirle la tabla a `anon` (es el padrón de direcciones y CUIT de 1.849
clientes): es una RPC **SECURITY DEFINER** que devuelva sólo lo que la pantalla usa
(`gv_np_destino_lista()` → np, provincia, expreso, alerta, texto) y **revocarle el SELECT de la
vista a `anon`**, porque leída desde el navegador miente.

⚠⚠ **Y la segunda mitad, del mismo tipo: PostgREST corta en 1.000 filas** (`db-max-rows`), y
**`limit=5000` NO lo levanta**: contesta `200` con las primeras 1.000 y **nada dice que falten**.
Con 1.482 NP, `LK 0027` quedaba afuera del corte y el pedido de Misiones seguía sin pintarse con
la RPC ya arreglada. **Un endpoint que devuelve exactamente 1.000 filas nunca es una casualidad.**
El arreglo es pedir **por lista** (`p_nps text[]`, de a 500) lo que la pantalla está mostrando, no
el universo. §3.lb.

⚠⚠ **Y vale para TODA la app, no para esa pantalla.** Se barrieron las 115 lecturas REST de
`index.html`: **32 leen el universo entero de algo**, varias con un `limit=20000` o `limit=50000`
**que nunca hizo nada**. Hoy ninguna está cortada (la mayor es `vista_uxb_articulo` con 527 filas),
pero todas crecen y el día que pasen las 1.000 no va a avisar nadie.

- **`gvRestTodo(path)`** pagina con `offset` hasta que vuelve una página corta, y le saca el
  `limit=` viejo al path. Las 8 lecturas enteras de objetos que crecen ya van por ahí.
- **`tests/rest-tope-1000.cjs`** rehace el barrido en cada corrida y **falla** si aparece una
  lectura sin filtro que no use `gvRestTodo` ni esté declarada en `CHICAS` con su conteo medido.

> **Un `limit=` alto no es una garantía, es una expresión de deseo.** Si la consulta lee el
> universo entero de algo que crece: o `gvRestTodo`, o declarada como chica. §3.ld.

⚠⚠ **Y desde la v20.53 está tapado para TODA la app, sin tocar la configuración del proyecto**
(Luis: *"quiero que esto quede cubierto sin el cambio global al proyecto"*). **No se sube
`db-max-rows`**: es del PROYECTO, y contra esta base pegan también Producción Virgilio y los admin
de Cervantes — una consulta sin `limit` sobre `Movimientos_Stock` pasaría de traer 1.000 a traer
63 mil. En su lugar **`supabase-config.js` envuelve `fetch` una sola vez** (es el único archivo que
cargan todas las páginas *y* el service worker): si una respuesta de `/rest/v1/` llega justo con
1.000 filas, pide el resto con `offset` y devuelve todo junto.

| la URL trae… | qué hace |
|---|---|
| nada, o `limit=` **mayor** a 1.000 | **completa** |
| `limit=` **menor o igual** a 1.000 | **no toca nada** (el que llamó pidió esa cantidad) |

Esa segunda fila es la que hace imposible la recursión con `gvRestTodo`, que pagina con
`limit=1000`. Se da cuenta por el header **`Content-Range`**, que el navegador puede leer (medido:
`Access-Control-Expose-Headers` lo incluye), así que cuando no hay corte **el body no se toca**.
`offset` anda igual en tablas, vistas y `rpc` POST. §3.le.

## ⚠ Regla de Luis (2026-09-21): la CUARENTENA se mide por SUCURSAL, y Retira nunca exime

*"Para clientes que tienen múltiples sucursales, se debería llevar registro por el «a qué sucursal
se corresponde la deuda»… si un cliente tiene direcciones de entrega A y B, hace hoy un pedido
para A, se le arma, se le factura y se le envía (generándole deuda) y en ese momento, antes de
pagar, quiere hacer un pedido para sucursal B, este debería pasar sin ser retenido."*

**Las dos decisiones que cierran la regla, textuales del 21/09: «retiene, y toda la deuda viva».**

1. **Deuda que NO se pueda atribuir a una sucursal → RETIENE.** Sin atribución no hay excepción:
   es el mismo criterio que la reposición chica (*"sin datos, retener"*).
2. **La ventana es TODA la deuda viva**, no los últimos N días.
3. **Retira nunca exime.** Un cliente con una sola dirección real no convierte su Retira en
   "otra sucursal"; y al multi-sucursal, con cualquier deuda, el Retira lo retiene igual.
4. La clave de la sucursal es **`dir_key`** (`gv_dir_key(direccion, barrio)`), **no** la etiqueta
   `sucursal_entrega`: Chef trae la dirección en el 100 % de sus pedidos web y la etiqueta casi
   nunca (48 de 56 pedidos de 60 días sin ella). Por eso la regla vale para **LK y Chef**.

**La cadena, y por dónde NO va:**

```
comprobante del Excel de deuda -> factura de ISIS (gv_comprobante_key)
  -> GV_Cruce_FC_Asig  -> NP -> GV_NP_Sucursal -> dir_key
```

⚠ **No va por el remito.** Se probó (`GV_NP_Remito`) y rinde **101** NP contra **923** del cruce
NP↔FC, y no aporta una sola NP propia: de las 114 que tienen remito cargado, las 114 ya están en
el cruce. Luis lo frenó el mismo día: *"la idea del remito no sirve… cruzás NP con FC"*.

**Lo que hay que saber antes de tocar esto:**

- **El Excel de deuda SÍ trae el detalle por comprobante** (Crystal agrupado: col E = comprobante,
  col L = pendiente). Hasta la v20.35 el front lo leía y lo tiraba: mandaba sólo el total por
  cliente. Ahora se guarda en **`GV_Cuarentena_Deuda_Detalle`**, y desde la v20.37 **el archivo
  crudo queda en el bucket `cuarentena`** (antes no se subía a ningún lado y había que volver a
  pedírselo a quien lo bajó del ERP).
- **La dirección de una NP de ISIS vive un día.** `GV_PPP_Programacion_Diaria` tiene sólo lo
  programado (133 filas al 21/09) y después se borra: por eso existe **`GV_NP_Sucursal`**, que la
  captura cada hora (cron 97). Lo viejo no se recupera — el registro empieza el 21/09.
- **Chequeo:** `select estado_cadena, count(*) from public.gv_cuarentena_deuda_sucursal group by 1;`
  — `ok` es lo que llega a la dirección; `sin factura parseada` tiene que dar 0.

## ⚠⚠ REGLA (Thomas, 2026-09-22, v20.95): el ARMADO AUTOMÁTICO no programa CUARENTENA ni CLIENTE NUEVO sin aprobación humana

**Thomas, textual:** *"armado automatico no debería programar automaticamente clientes nuevos ni
clientes en cuarentena que no hayan sido aprobados por un humano, nunca. Si ya fueron aprobados y
se atrasa la entrega o algo asi, si se puede reprogramar automaticamente, pero primero aprobado
por humano."*

**Hasta el 22/09 la retención vivía SÓLO en el front.** Medido sobre `pg_proc`: ni
`gv_ppp_web_armar_pendientes`, ni `ppp_web_armar_tandas`, ni `gv_ppp_web_juntar_clientes`, ni
`gv_pedidos_web_excluidos` nombraban la palabra cuarentena. El armador sólo saltea lo diferido
(a0), lo retenido **a mano** en `GV_PPP_Web_Retenido` (a0b) y lo cancelado (a0c): alcanzaba con
que el pedido no tuviera fila ahí para que el cron lo programara igual.

| NP | cliente | motivo | quedó en |
|---|---|---|---|
| LK 0094/95/96 (1448) | Silvano Lucas Martin (4282) | **cliente nuevo**, pipeline en `ingresado` | E72A · 28/09 |
| CH 0004 (218) | Ierakuin Srl (1665) | **deuda $2.062.528,58** | E71A · 28/09 |

A los dos los había devuelto Vivi a mano el 18/09 (*"No pago"*) y los dos volvieron solos, sin una
fila en `GV_Cuarentena_Liberados`.

**APROBADO POR HUMANO = fila en `GV_Cuarentena_Liberados`** que levante ESE motivo. La escriben el
botón de Cuarentena y el ✅ del pipeline de Clientes nuevos (los dos vía `gv_cuarentena_liberar`).
Aprobado, el pedido vuelve a los pases normales y se reprograma solo como cualquier otro.

⚠ **El criterio de QUÉ retiene no se duplica en el armado**: lo da `gv_cuarentena_marcar_calc`, la
misma que usa la pantalla, con sus excepciones vivas (`gv_excepcion_cuarentena`, reposición chica
v19.44, mismo pedido v20.52, resta de motivos liberados v20.86). Si cambia una regla de cuarentena,
el armado la hereda sola. Medido: **Suppa (1482, deuda $836.909) NO retiene**, porque su deuda es
la factura de otra NP del **mismo** pedido.

⚠ **`gv_cuarentena_ya_programado()` marca DE MÁS**: no aplica esas excepciones, así que lista a
Suppa como retenido-y-programado cuando la Cuarentena no lo retiene. Es un centinela con falsos
positivos, no una fuente.

⚠⚠ **`gv_cuarentena_retiene_lote` es FAIL-CLOSED, al revés del patrón de la v19.44**: si no se
puede evaluar, devuelve **todo el lote** y no se programa nada. Un armado que no corre se ve
(`GV_PPP_Web_Armado_Log`, `gv_ppp_web_armado_salud`); un pedido con deuda que sale en el camión, no.
Y ojo: el `WHERE` de `gv_cuarentena_marcar_calc` termina en `(es_supervisor_virgilio() or
gv_es_supervisor_o_servicio())`, o sea que **sin permiso devuelve CERO FILAS** — leído como *"no hay
retenidos"* sería el mismo bug al revés. Por eso el chequeo de identidad se hace **antes y afuera**.

⚠ **No costó tiempo: lo bajó.** El pase va **después** del tope (a00), así evalúa a lo sumo
`armado_tope_pedidos` (120). El guard cuesta 1.041 ms sobre 218 pedidos (766 son
`gv_cuarentena_mismo_pedido_seguro`), pero el armado cuesta ~43 ms por pedido y los retenidos
dejaron de procesarse: LK con ~170 de entrada pasó de 4.515 / 5.499 / 4.951 ms a **4.327 / 4.306**.

⚠ **El alias del subselect es `_cq_r`, no `r`** — la función declara `r record` y un alias `r` la
vuelve ambigua: explota **en ejecución** con `42702`, no al crearse (pozo de la v19.56). Volvió a
morder en el primer intento y **lo cazó la prueba, no la lectura**: se corre el armador con un
retenido y un cliente sano dentro de una transacción abortada, y se prueban **las dos mitades** de
la regla (sin aprobar → sin tanda; con fila en Liberados → se programa).

**Chequeo:** `select * from public.gv_reglas_perdidas;` — vacía = todo bien.
`sql/gv_armado_cuarentena_v2095.sql`, §3.me.

## ⚠ REGLA (Luis, 2026-09-23, v21.47): una RESPUESTA no opina sobre lo que no PREGUNTÓ

**Luis, textual:** *"primero revisá por qué Ierakuin no está en el submódulo de cuarentena. Se
sigue escapando y seguís sin poder arreglarlo"*.

Síntoma: **`web CH 218 · Ierakuin Srl (CH 1665)`** se dibujaba en la lista normal de «Pedidos a
programar» **con el chip 🚧 «retenido en cuarentena · no se arma solo»** —que lo pinta el
backend— mientras el submódulo Cuarentena no lo tenía. Los dos lados decían cosas distintas del
mismo pedido.

**Medido:** `gv_cuarentena_marcar` devuelve ese pedido con `motivos ["deuda"]` y
**$2.062.528,58**. El backend nunca se equivocó; lo que fallaba es cómo el front aplica la
respuesta.

**La causa.** Los pedidos de **Chef llegan tarde** (otra vuelta de red: `gv_pedidos_web_np_chef_admin`
por FDW), así que `cuarMarcarPedidos` corre **dos veces por carga** (v20.98): la primera con
LK+ISIS y la segunda, cuando Chef ya está, con la lista completa. Las dos terminaban recorriendo
`_apr.pedidosTodos` —que para entonces **ya incluye a Chef**— y **borrando la marca de todo
pedido que su respuesta no nombrara**:

```js
else { if (p.cuarentena_motivos) delete p.cuarentena_motivos; … }
```

La corrida de LK **no preguntó por Chef**, así que si contesta última le borra la cuarentena al
único pedido de Chef. Es una carrera —por eso aparece y desaparece, y por eso la v20.98 parecía
haberlo arreglado—: alcanza con que la llamada de LK se reintente una vez (v20.96, los timeouts
son frecuentes) para que llegue después.

> **La regla:** una marcación toca **sólo los pedidos de su propio lote**. Lo que no preguntó no
> lo sabe, y no saber no es "no retiene".

⚠ **Lo que SÍ se sigue limpiando:** un pedido que estaba en el lote y ya no retiene pierde la
marca, o un liberado quedaría retenido para siempre. El test muerde por los dos lados.

⚠ **Es el mismo pozo de §"una lectura ROTA no es un CERO", un paso más adelante:** ahí el cero
venía de un feed caído; acá viene de *"no pregunté"*. En los dos casos el front lo leyó como
*"no hay"*.

**Chequeo:** `node tests/apr-cuar-chef-tarde.cjs` — corre las dos marcaciones de verdad, con la
de LK contestando última. Verificado que falla contra el código anterior (*"el pedido de Chef
perdió su cuarentena"*).

## ⚠⚠ REGLA (Luis, 2026-09-24, v22.17): el freno de cuarentena vale también A MANO — y el liberado se REEVALÚA

**Caso LK 1475 · Oriental Party (LK 1618, deuda $3.222.078,75)**: el 24/09 entre 10:01:21 y
10:03:43 `gv_cuarentena_marcar` le dio **500 siete veces** al navegador; A Programar lo dibujó
sano y a las 10:03:38 se programó a mano (terminó en E92A). Nadie lo aprobó. Problema 528.

| capa | qué hace desde v22.17 |
|---|---|
| **servidor** | `gv_ppp_web_tanda_programar` y `gv_ppp_web_tanda_reusar` llaman a `gv_cuarentena_retiene_lote` (el MISMO criterio del armador, fail-closed): retenido sin aprobar → error `CUARENTENA: …`; no se pudo evaluar → error *"no se programó nada, probá de nuevo"* |
| **front** | `aprGenerarTanda` no programa un pedido web cuya cuarentena no se pudo VERIFICAR (`p._cuarOk`, lo pone la marcación sólo en los pedidos de su lote). Sin marca no hay "no retiene": hay "no sé" |
| **liberar** | `gv_cuarentena_liberar` borra la fila de `GV_PPP_Web_Retenido`: aprobado, el pedido **olvida la tanda de la que lo sacaron** y el armador lo reprograma con la lógica normal. En cuarentena el chip dice *"↻ al aprobarlo se reprograma"*, no *"vuelve a E92A"* |

⚠ **Olvidar la tanda es SÓLO para el pedido limpio** (v22.18, Luis: *"que no queden datos del picking
o del armado que después distorsionen"*): si al sacarlo ya estaba pickeado o armado
(`ya_pickeada`/`ya_armada` de la tabla, que acá SÍ es la foto correcta: la del pedido) o tiene
`Entregas_Virgilio` vivas, la memoria **queda**, el armador lo sigue salteando y decide una persona.

⚠ **Las NP de ISIS no tienen el freno del servidor** (el armador tampoco las evalúa): sólo web. No
entran más NP de ISIS nuevas (Luis, 24/09), así que no se extiende.
**Chequeo:** `select * from public.gv_reglas_perdidas;` · `node tests/apr-cuar-freno-manual.cjs` ·
`node tests/apr-fit.cjs`. `sql/gv_cuarentena_freno_manual_v2217.sql`.

## ⚠ REGLA (Luis, 2026-09-25, v22.46): el PEDIDO PARTIDO por importados es UNO — cuarentena y cliente nuevo

**Luis:** *"si bien se parte en dos pedidos para poder programarse, realmente surge de un mismo pedido
del cliente"* · *"es solamente un pedido para tema del límite de los 3 primeros pedidos"* · *"todo lk y ch"*.

La página parte el pedido cuando trae importados sin stock: la parte que espera reingreso es otro
`order_id` con `lk_pedidos_match.pedido_origen` = el original (LK: `orders.sheets_payload`; Chef:
`chef_orders_cache.sheets_payload`, las dos viajan por `sync_pedidos_match_virgilio`).

| qué | cómo |
|---|---|
| aprobar una parte aprueba todo el pedido | `gv_cuarentena_liberados_familia` (Liberados + herencia por `pedido_origen`, las dos direcciones), leída por `gv_cuarentena_marcar_calc` (MATERIALIZADA una vez) y `gv_cuarentena_ya_programado` |
| la parte diferida NO se programa sola si el cliente está retenido | pase **(a0d2)** del armador: `v_dif` pasa por `gv_cuarentena_retiene_lote`. Antes (b2) lo programaba sin mirar: LK 1546 (Solia) → F01A |
| cuenta como 1 pedido para los 3 de cliente nuevo | LK `gv_clientes_nuevos_calc`: una fecha de factura que es **sólo** de artículos de una parte diferida no suma (`hijo_it` / `fecha_hijo` / `corr`) |
| **o quedan las dos partes en cuarentena o ninguna** (v22.47) | la reposición chica (v19.44) NO exime a un pedido partido: la parte diferida suele tener 1 código y zafaba sola |
| en Cuarentena es **UNA fila** (v22.47) | `cuarAgrupar` + `gv_pedidos_partidos()`: chip 🧩 *N pedidos (1 partido)*, m³ sumado, «Enviar» apunta al original y aprueba todo. `tests/apr-cuar-pedido-partido.cjs` |

⚠ **Caso Solia: la cuarentena NO la causó el partido.** La deuda de $3.421.315,29 es de facturas
del 17/08 y 10/09 (NP 98427/28, 98613/14). Lo que estaba mal es que la mitad diferida se programó
sola sin aprobación.

⚠ **No meter una función con `= any(...)` dentro del lateral de Liberados**: se probó y la
marcación pasó de 366 ms a 10 s (timeout 8 s). Va la vista materializada.

⚠ En LK, **`chef_customers` es FDW** (+2 s por lectura): usar `chef_customers_cache`.

`sql/gv_pedido_partido_cuarentena_v2246.sql`, `sql/gv_clientes_nuevos_calc_hijo_v2246_LK.sql`.

## ⚠ REGLA (Luis, 2026-09-21, v20.89): el PIPELINE **reemplazó** al submódulo de clientes nuevos

**Luis, textual:** *"implementá esta nueva versión de clientes nuevos en «A programar»
reemplazando la vieja"*. El submódulo 🆕 Clientes nuevos **ya no se dibuja**: en su lugar, dentro
de «A Programar», está el pipeline. Su pestaña propia se fue — el mismo módulo en dos lugares era
justo el problema de convivencia que se quería evitar. `clinNuevosHtml` y sus 9 funciones siguen
en el archivo (como `gv_ppp_np_desarmar` en la v18.77): lo que no puede volver es la **puerta**.

```
ingresado → [🔎 Análisis Cred.] abre Equifax y arranca el reloj
  → analisis → la dirección define UNO DE DOS:
      · 🤝 Referenciado    → ✅ Aprobar y programar
      · 💳 No referenciado → Speech 1 → Speech 2 (24 h) → 💵 Pagó → ✅ Aprobar
                                                        └→ 🗑 Cancelar pedido
```

### Los estados son DOS, y son del CLIENTE

**Luis, 21/09:** *"Después del análisis solo hay 2 estados que un cliente puede tener:
Referenciado y No referenciado. No referenciado se le requiere que pague los primeros 3 pedidos
por adelantado y el pipeline contempla todos los casos ahí (comunicaciones, aceptación,
cancelación)."*

⚠ **«No válido» ya NO existe.** Al cliente al que no se le quiere vender **se le elimina el
pedido** (🗑, disponible desde `ingresado`, sin tener que analizarlo), que lo saca de la PPP y lo
deja en el log de anulados. Eso descarta *ese* pedido: si vuelve a pedir, entra de nuevo — y el
log del cliente, que ahora es histórico, muestra que ya pasó antes.

⚠⚠ **Y la DECISIÓN AHORA SE HEREDA** (Luis: *"la verificación no se vuelve a hacer… lo único que
queda definir es el contacto por speech"*). **Esto dio vuelta la regla de la v20.73**, que decía
lo contrario. El 2.º pedido de un No referenciado arranca en «No referenciado» —o sea, pidiendo
el Speech 1— sin volver a Equifax, con el chip **🧠 ya definido**.

**Lo que NO se hereda son los timestamps**: el pedido nuevo tiene su `speech1_at` en null, así que
paga por adelantado igual. Si se heredaran, el 2.º pedido saldría como «ya pagado». Lo resuelve
`decision_ef = coalesce(propia, del cliente)` en `gv_clin_pipeline_lote`, y lo marca
`decision_heredada`.

### ⚠ El cliente nuevo RECURRENTE no se vuelve a analizar (Luis, 23/09, v21.48)

**Luis:** *"para clientes nuevos recurrentes (que todavía no tienen 3 pedidos completados) debería
directamente abrir el «qué sigue» en speech 1, speech 2 y agregar la opción de marcarlo como
referido"*. Caso: **LK 1448 · Silvano (LK 4282)**, 2.º pedido, figuraba «Sin analizar» porque su
1.er pedido es anterior al pipeline y no había decisión que heredar.

Si el pedido no tiene decisión propia ni heredada y `GV_Clientes_Nuevos.pedidos >= 1`,
`gv_clin_pipeline_lote` devuelve `decision = no_referenciado` (columnas nuevas `recurrente`,
`pedidos_previos`) → arranca en **💬 Speech 1**, con el chip **🔁 recurrente**. En
`no_referenciado`, `speech1` y `speech2` está el botón **🤝 Referenciado** (`gv_clin_etapa` ya le
da prioridad sobre los speech). No se escribe ninguna fila: se deriva al leer.
`sql/gv_clin_recurrente_v2148.sql`, `tests/pipe-recurrente.cjs`.

### ⚠ El cliente nuevo APROBADO sale en 48 h (Luis, 23/09, v21.67)

Aprobado (fila en `GV_Cuarentena_Liberados` con `cliente_nuevo`) → el pase **(a0e)** del armador lo
programa **forzado** en uno de los **2 días con reparto** siguientes a la aprobación
(`gv_clin_dia_aprobado`): primero el que ya tiene camión a su grupo de zonas, después el que tiene
cupo. Si no encaja por zona sale igual. El botón de Equifax abre la landing
(`https://www.equifax.com.ar/`), decidido por Luis. `sql/gv_clin_aprobado_48h_v2167.sql`.

### Los 3 pedidos NO se cuentan acá: ya los corta LK

*"Después de que pasan 3 pedidos bien pagando por adelantado ya se considera un cliente normal."*
Eso **ya estaba hecho y no se tocó**: `GV_Clientes_Nuevos` sólo trae clientes con **1 o 2**
pedidos facturados (medido al 21/09: 269 con 1, 80 con 2, **ninguno con 3**). Al tercero el
cliente desaparece de la tabla y deja de caer en el retén. Y como un pedido cancelado por no
pagar nunca se factura, no suma — el contador hace exactamente lo que pide la regla.

### ⚠ CUARENTENA PRIMERO — y liberar ya no levanta el candado entero

**Luis:** *"cuarentena toma prioridad sobre cliente nuevo (ej, un cliente nuevo con deuda pasa
primero por la cuarentena y después cuando es liberado con «Enviar a Pedidos a programar» va al
módulo de clientes nuevos"*.

Medido el 21/09 sobre 45 pedidos retenidos: **25** sin cliente nuevo, **13** cliente nuevo puro,
**7** cliente nuevo + deuda. Sin esta regla esos 7 (el **35 %** de los clientes nuevos) habrían
quedado en las **dos** columnas a la vez.

| el pedido está… | dónde cae |
|---|---|
| retenido por deuda / suspendido / límite (con o sin cliente nuevo) | **Cuarentena** |
| retenido **sólo** por cliente nuevo | **el pipeline** |
| liberado de la deuda, pero sigue siendo cliente nuevo | **el pipeline** |
| liberado de todo | Pedidos a programar |

Son **dos cambios que van juntos**, y uno sin el otro no hace nada:

1. **`gv_cuarentena_marcar_calc` resta** de los motivos vivos los que esa liberación resolvió
   (`GV_Cuarentena_Liberados.motivos`, que ya se guardaba y **nadie leía**). Antes el liberado
   quedaba excluido entero.
2. **El botón de Cuarentena nunca libera `cliente_nuevo`** (`cuarLiberarConfirmar` lo filtra). Si
   lo liberara, el pedido se iría derecho a programar y no pasaría nunca por el pipeline. Quien
   levanta ese motivo es el **✅ del pipeline**.

⚠ **Una liberación vieja con `motivos` en NULL *o en array vacío* libera TODO.** Los dos casos
significan lo mismo —"no se registró el detalle"— y sin el segundo guard el pedido **1368**, que
tiene `'{}'`, volvía al retén. Medido: de los 38 ya liberados, vuelven **2** (98585 y 98586, que
se liberaron sólo por deuda y siguen siendo cliente nuevo), y **los dos ya están programados**, o
sea que no están en la lista de pendientes: cero impacto visible.

### ⚠ El TELÉFONO se busca por `(empresa, cod)`, nunca por código solo

El Excel del dueño del 08/09 **ya está dentro de `whatsapp_clientes`**: de los 332 códigos
compartidos, **0** tienen teléfono distinto, y las dos cargas se escribieron con 12 segundos de
diferencia. No hay dos verdades — pero **26 filas del dueño nunca llegaron**:

| | |
|---|---:|
| filas del dueño que no están en `whatsapp_clientes` | **26** |
| …que son el mismo código en LK **y** en CH | 13 códigos |
| …de esos 13, con **otro teléfono** en cada empresa | **13** |
| …de esos 13, con **otra razón social** | **13** |

`whatsapp_clientes` no tiene columna empresa, así que esos códigos no entraban y **se descartaron
los dos lados**. Por eso `GV_Clientes_Whatsapp` (358, con empresa) **manda**, y `whatsapp_clientes`
(942, sin empresa) es el respaldo **sólo si el código no existe en las dos empresas** — son **257**
según el padrón de direcciones. La RPC devuelve además `origen`: `padron_empresa`, `historico`,
`ambiguo_sin_dato` o `sin_dato`.

**Chequeo** (tienen que salir dos teléfonos distintos):
```sql
select * from public.gv_cliente_nuevo_wpp_lote(
  '[{"empresa":"lk","cod":"94"},{"empresa":"chef","cod":"94"}]'::jsonb);
```

⚠ **Lo que sigue faltando, y no es un bug del código:** de los 12 clientes nuevos de hoy, **6 no
tienen teléfono en ninguna tabla** — y **11 de 12 tienen mail**. La página les pide mail, no
WhatsApp. Eso se arregla en la página, no acá. (Otros 2 están sólo en `customers.whatsapp` de LK
y necesitan que LK los empuje por el FDW, como `sync_cliente_isis_virgilio`.)

### El LOG es del CLIENTE, no sólo del pedido

**Luis:** *"deberían quedar registrados los «Coment.» a modo de log histórico. Si un cliente
vuelve a entrar en el módulo de clientes nuevos, debería traer todo el log anterior de veces
anteriores que estuvo."*

`GV_Cuarentena_Comentarios` tiene ahora **`cod`** (nullable, sin default que reescriba). El
backfill lo recuperó cruzando con `GV_Cuarentena_Log`: **70 de 71**. El 📖 muestra el hilo de
**este** pedido y debajo, apagado, **🕘 Antes, con este cliente** —los comentarios de sus otros
pedidos— vía `gv_clin_comentarios_cliente`, en su propia llamada con su propio catch.

### Lo que no cambió, y no se toca

| | el pipeline usa… |
|---|---|
| aprobar | **`gv_cuarentena_liberar`**, la MISMA función de siempre |
| el timer | sella **`GV_Clientes_Nuevos_Contacto`** |
| el log | **`GV_Cuarentena_Log`** con prefijo `pipeline_` |

Lo sostiene `tests/pipe-clientes-nuevos.cjs` con el **candado invertido**: si alguien le escribe
al pipeline su propio «aprobar», el test se pone en rojo.

### ⚠⚠ Esta función LA TOCAN VARIAS SESIONES — y lo pisó una, en el medio

Mientras se escribía esto, otra sesión hizo `CREATE OR REPLACE` de
**`gv_cuarentena_marcar_calc`** partiendo de su propia copia y **borró este cambio** (se notó
porque apareció su CTE `mismo`, de la v20.52, que antes no estaba). Se reaplicó sobre la
definición viva, conservando lo de la otra sesión.

Por eso el bloque de `sql/gv_clin_dos_estados_v2086.sql` **se aplica sobre `pg_get_functiondef`,
es idempotente** (si ya tiene la regla, no hace nada) y **falla con un `raise` si el texto no
matchea**, en vez de escribir una versión vieja encima. Y las cinco reglas tienen su fila en
`GV_Reglas_Centinela`:

```sql
select * from public.gv_reglas_perdidas;   -- vacía = ninguna regla se perdió
```

### Qué se prueba, y cómo

- **`tests/pipe-en-a-programar.cjs`** dibuja A Programar de verdad y mira **qué columna se lleva
  cada pedido**: es lo único que prueba que no se duplican. Ahí están también la zona, el
  colapsable, los dos estados y el fallback de la pestaña vieja.
- **`tests/pipe-clientes-nuevos.cjs`** son los candados estáticos (el aprobar compartido, el
  guard del array vacío, la herencia, el log por cliente, el teléfono por empresa).
- **`tests/pipe-vinculo-en-el-cuadro.cjs`** corre el cuadro y mira el **orden real** de las RPC.
  ⚠ Un candado de texto no puede verificar semántica: cuando importa el orden o la condición, el
  test se corre.

⚠ **El fallback de la pestaña vieja va ANTES del `return` de `"prog"`** en `pppRenderProg`, o no
se ejecuta nunca. Lo verifica el test — el primer intento lo puso después y quedaba muerto.

**Los relojes y la URL de Equifax se cambian con un `update`, no con un deploy:**

```sql
update public."PPP_Web_Config" set valor = 48 where clave = 'clin_speech_horas';
update public."PPP_Web_Config" set valor_texto = '<url>' where clave = 'clin_equifax_url';
```

⚠ `PPP_Web_Config.valor` es **numeric** y `make_interval(hours => numeric)` **no existe**: esos
coalesce van con `::int` o la función explota en la primera llamada (el `CREATE` sale limpio).

**El CLIENTE DE PRUEBA** (botón «👁 Ver cliente de prueba») avanza por las etapas de verdad, pero
su clave es `__DEMO__` y el backend lo aísla: no escribe el log, ni el timer, ni ninguna
excepción. **Si se suma una escritura nueva a `gv_clin_evento`, va con `and not v_demo`.**

**Chequeo:** `select * from public.gv_clin_vencidos;` — lo que espera hace demasiado (el pedido
**no se cancela solo**). Y `select * from public.gv_clin_prioritarios;` — lo aprobado que tiene
que salir en 2 días hábiles. `sql/gv_clin_dos_estados_v2086.sql` (vigente; se aplicó como v20.89 — la v20.86, la v20.87 y la v20.88 se las llevaron otras sesiones) y
`sql/gv_clin_pipeline_v2066.sql` (tablas, config, vínculo y vistas), §3.ln.

## ⚠ Regla del dueño (2026-09-15): Oscar hace el SKIN — la OC va a su nombre y NO se toca

Al revisar por qué llegaban los WhatsApps de *"SIN OC generada"* aparecieron 14 códigos —casi
todas bombillas, más 506 Abrelata Uña, 500 Abrelata Uña Pata y 280 Manga Repostera— configurados
con proveedor **Oscar** pero recibidos siempre como **Log/ Fabr**. **No es un error de
configuración.** Thomas: *"el 506, todos esos artículos, salen en la orden de compra de Logística
Fabric históricamente, pero los entregaba Oscar. Lo que hacía Oscar era el skin solamente:
nosotros le damos el artículo listo para que le ponga un skin y lo entregue en Virgilio
encajado."* **Oscar falleció; sigue trabajando su nieto**, así que el dueño decidió dejarlo:
*"dejalo ahí"*. **No cambiar el proveedor de esos códigos en `OC_Maximos`.**

⚠ **Lo que sí está mal es la CARGA, y es de procedimiento, no de código.** Medido el 15/09:
`Oscar` **está** en `vista_entidades_recepcion` como tallerista —o sea que el operario lo puede
elegir en la pantalla de recepción— y sin embargo **no figura ni una vez** en
`Entregas Tallerista Virgilio` (0 filas en 5 meses): siempre se carga `Log/ Fabr`. Las OC, al
revés, salen **todas** a nombre de Oscar (31 líneas de esos 14 códigos en los 2 meses que tiene
`Ordenes_Compra`, desde el 13/07). Mientras las dos puntas no coincidan, el aviso va a saltar
siempre. **El arreglo es que al recibir esos artículos elijan `Oscar`, no `Log/ Fabr`.**
Problema 250.

## ⚠ Regla del dueño (2026-09-18): en las OC la PROYECCIÓN es siempre rey

**Thomas, 2026-09-18, sobre el generador de OCs:** *"Proyección es siempre rey"*.

El **Máximo** de un artículo es `ceil(proyección × índice)` y **nada lo topa**. Si eso da más que
la capacidad de góndola, **se pide igual** y el excedente va a racks. Medido el 18/09 con el **505**:
capacidad 3340, proyección 2342,33 × índice 1,5 = **3514**, y el máximo es 3514.

Es lo que ya hace `vista_generador_oc`, así que **no hay nada que cambiar** — está escrito acá para
que nadie vuelva a "arreglarlo" agregándole un `min(proy × índice, capacidad)`.

**La capacidad manda en un solo caso, y no es una excepción a la regla: cuando NO hay proyección**
(`proy = 0`, artículos sin ventas). Sin proyección no hay rey: el objetivo pasa a ser llenar la
góndola. Eran **10 de los 238 activos** al 18/09 a la mañana (109 Sac Zincado, 618, 630E, 631,
631E, 634E, 635E, 636E, 857, 613); **desde la v20.09 son 6**, porque tres de ellos —**618, 631 y
857**— figuraban ahí **por un bug de la cuenta**: tienen `proy_uni_mes = 0` pero `proy_cajas_mes`
de 0,17 / 0,33, y el generador leía la columna de unidades. Sí tienen proyección, mínima, así que
mandan ellos y no la góndola.

⚠ **El tilde `llenar_gondola` de ⚙ Configuraciones hace exactamente lo contrario** — pisa la
proyección con la capacidad, incluso cuando la proyección es más alta. **Al 18/09 no lo tiene
tildado ningún artículo (0 de 238)**, y no hay que tildarlo salvo que el dueño lo pida para un
código puntual.

⚠ **El tope existió hasta HOY a las 13:26**, y lo sacó esta misma regla: la **v19.71** cambió
`LEAST(ceil(proy × índice), cap)` por `ceil(proy × índice)` en el CASE del Máximo (*"no contemples
el máximo de góndola para pedidos. Tenemos que tener la mercadería que hace falta, después vemos
cómo la guardamos"*). Midió **49 códigos que suben el Máximo, 33 que pasan a pedir más, +2.178
cajas** (7.324 → 9.502). La flecha roja **⤓ "Topado a la capacidad de góndola"** quedó huérfana ahí
mismo y **se sacó en la v19.78** (problema 419) — no era un resto viejo, estuvo diciendo la verdad
hasta esa tarde. Si vuelve a aparecer un cartel de tope, está mintiendo.

**Consecuencia aceptada, no un bug:** comprando por encima de la góndola, el aviso de recepción
*"no entra en góndola"* salta más seguido y el excedente va a racks.

⚠ **Y la proyección sale de `proyeccion_madre`, que la empuja LK — no se calcula acá.** El cron
`sync-proyeccion-madre-virgilio` (jobid **25 en LK**) era **semanal** y su única corrida del 16/09
cayó adentro de los cuatro días en que la base de LK estuvo ahogada (15–18/09, hasta 2.130 corridas
fallidas por día): se perdieron 7 días de dato y el watchdog, con umbral de 9 días, no dijo nada.
Desde la **v20.38** el cron es **diario** (`'20 9 * * *'` = 06:20 ART) y el umbral de
`watchdog_frescura_datos()` es de **40 h**. Antes de mirar un número del generador:

```sql
select public.watchdog_frescura_datos();   -- avisos=0 y cuántas horas tiene la proyección
```

⚠ **El sync tarda ~70 s y el MCP corta a los 60**, así que llamarlo desde una sesión hace ROLLBACK
y no escribe nada (el delete+insert está adentro de la función). Se corre con un job de pg_cron de
una sola vez y después se borra con `cron.unschedule`. §3.ks.

**Chequeo:**

```sql
select count(*) filter (where llenar_gondola)                as pisan_la_proyeccion,   -- tiene que dar 0
       count(*) filter (where activo and tiene_prov_real
                          and proy = 0 and cap > 0)          as sin_proy_van_por_cap,  -- 6 (v20.09)
       count(*) filter (where activo and tiene_prov_real)    as activos                -- 241 al 18/09 (eran 238: los 3 duales con proveedor pasaron a 2 filas cada uno, v19.84)
  from public.vista_generador_oc;
```

## ⚠ Regla del dueño (2026-09-18, v19.85): lo COMPROMETIDO no es stock disponible

**Thomas, 2026-09-18:** *"lo comprometido (separar_pedidos y a_facturar) no debería contar como
stock disponible para la cuenta de 'lo que tenemos - lo que nos falta'"*.

El `stock` de **`vista_generador_oc`** es el **DISPONIBLE**:

```
terminado + a_guardar + racks + excedente + para_envasar + racks_ch      ← cuenta
separar_pedidos + a_facturar                                            ← NO cuenta
```

**Por qué, y es la parte que importa:** `total = maximo + pedidos - stock`, y el CTE `pend_np`
**excluye** las NP cuya tanda ya tiene **TP**. O sea que el pedido pickeado deja de compensar
como demanda — mientras su mercadería seguía sumando como disponible, porque el picking la mueve
a `separar_pedidos` / `a_facturar` pero no la saca del depósito. **La misma caja tratada de dos
maneras incompatibles en las dos puntas de la resta**, y siempre para el mismo lado: se pedía de
menos. Medido al corregirlo: **1.205 cajas comprometidas, +816 de a pedir en 64 códigos**, ninguno
a la baja. Problema 428, §3.jq.

⚠ **Esto NO cambia el módulo Stocks ni ninguna otra pantalla**: lo comprometido sigue existiendo y
se sigue viendo donde corresponde. Cambia **sólo** la cuenta del generador de OC.

⚠ **Y destapó un negativo viejo**: el **256** (Mate Madera Cerámica) tiene 2 cajas comprometidas
contra 1 de saldo total, así que su disponible da **−1** — un sobre-pickeo que ya estaba en el
libro y que el stock total tapaba. El `greatest(0, …)` lo contiene. **No se tocó el dato.**

> **La regla general, que vale para cualquier resta:** si un lado saca un hecho, el otro tiene
> que sacarlo también. El bug no estaba en ninguna de las dos mitades leída sola — las dos eran
> defendibles por separado.

**Chequeo:** `select * from public.gv_reglas_perdidas;` — el centinela `COALESCE\(s\.fin_dep`
vive ahí. `sql/gv_generador_oc_stock_disponible_v1985.sql`.

## ⚠ REGLA (Luis, 2026-09-22, v21.14): la góndola es de 4 filas — **A y P son las únicas de 5**

**Luis, textual:** *"solo las góndolas A y P son de 5 filas, el resto está organizado en filas de
a 4… que por ejemplo ahí las H las muestre de a 4 filas y no 5"*.

El Mapa de góndolas dibujaba **todas** con módulos de 5 (`PMAP_ALTO = 5`), así que la H salía en
**12 columnas de 5** cuando en el depósito son **15 de 4**: la celda que el operario veía arriba a
la izquierda no era la que tiene enfrente.

Hoy la altura la da `pmapAlto(g)`: **`PMAP_ALTO_X = { A: 5, P: 5 }`**, default **4**. Al agregar
una góndola de 5 filas va ahí, no se toca el default.

**Y la numeración cierra con eso** (medido el 22/09 sobre `gv_planimetria_celda`): cada góndola
tiene su `celda` corrida de 1 a N sin huecos y **N es divisible por SU altura** —
`A = 85 = 17×5`, `P = 40 = 8×5`, `B/D/F/H/J/L/M/Ñ = 60 = 15×4`, `C/E/G/I = 20 = 5×4` —, así que
el corte cae siempre donde tiene que caer. `Y` y `Z` tienen **una celda suelta cada una** (Y29,
Z07) y van por el default.

**Chequeo:** `node tests/pmap-gondolas.cjs` — verifica que A corta en `1–5` y F en `1–4`, y que
F13 queda **abajo de la 4.ª columna**, no arriba de la 3.ª. Verificado que falla con el 5 fijo.

## ⚠ REGLA (Thomas, 2026-09-23, v21.99): AGREGAR EXPRESO ISIS — la cola NO frena ningún pedido

El cliente ahora ve con qué expreso le entregamos y lo puede cambiar desde el checkout de la
página. Cada cambio cae en el módulo **🚚 Agregar Expreso ISIS** para cargarlo a mano en ISIS.

> ## **Cuando llega acá, el pedido YA SALIÓ con el expreso nuevo.**
> LK escribe la ficha (`customer_delivery_addresses`) en el acto y `v_pedidos_web` la lee **en
> vivo**, así que la PPP, el remito y el camión ya van al galpón correcto. Lo único que falta es
> dejarlo igual en ISIS para que la próxima factura salga bien.

**Por eso esta pantalla sin mirar una semana NO traba nada** — desincroniza ISIS, que es otra cosa.
Leerlo como un freno es el error a no cometer: la regla de Thomas es *"la prioridad es que el
cliente termine de mandar el pedido, sin ninguna limitación administrativa"*.

⚠ **La fila ROJA es la única que necesita llamar al cliente**: un expreso que no está en nuestro
padrón **y** que vino sin dirección (`falta_direccion`). La dirección es **opcional** del lado del
cliente a propósito. Las demás se cargan con lo que ya está.

⚠ **La clave de `GV_Expreso_Pendiente` es `(empresa, id)`.** El `id` es el de la tabla de LK; el
día que entre Chef sus ids son de su propio `bigserial` y pisarían filas de LK en silencio.

⚠ **Marcar "Cargado en ISIS" es de SUPERVISOR** y va por `gv_expreso_marcar`, no por un UPDATE
suelto: la tabla no tiene escritura para `anon`.

⚠ **Descartar NO revierte nada**: la ficha del cliente en la página ya quedó con ese expreso.
Sólo saca el renglón de la cola. El cartel del botón lo dice.

⚠ **La cola se lee PAGINADA** (`gvRestTodo`, y está en `DEBEN_PAGINAR`): es una cola, y una cola
crece sola si nadie la vacía. Un `limit=1000` ahí sería una expresión de deseo.

**Chequeo:** `select * from public.gv_expreso_pendiente;` — vacía = nada pendiente de ISIS ·
`node tests/exp-isis-modulo.cjs`. `sql/gv_expreso_pendiente_v2199.sql`, §3.mx.

## ⚠ REGLA (Luis, 2026-09-22, v21.14): generar las OC a mano MUEVE el ciclo automático

**Luis, textual:** *"OCs. Generación manual. Si se generan manualmente, que consulte cuándo
retomar el ciclo de generación automática en ese momento."*

El cron **50** generaba todos los miércoles y su único guard era *"¿ya hay OC de HOY?"*: una
corrida manual del lunes **no frenaba la del miércoles**, que salía dos días después.

Ahora el ciclo tiene un **ancla**, `GV_OC_Auto.proxima_auto`, y el cron corre **todos los días**
llamando a **`gv_oc_auto_corrida()`**:

| situación | qué hace |
|---|---|
| `hoy < ancla` | `pospuesta_hasta:<fecha>` — no genera |
| `hoy >= ancla` | genera y adelanta el ancla a `hoy + cadencia_dias` (7) |
| ancla en **NULL** | ciclo histórico: **sólo miércoles** (es el fallback, del backend y del contador) |

Al generar a mano, la pantalla pregunta y escribe el ancla con **`gv_oc_auto_programar(fecha,
motivo)`** (supervisor adentro de la RPC). **La fecha puede ser cualquier día**, no sólo
miércoles: el `schedule` ya no decide nada, decide el ancla.

⚠ **`generar_ocs_automaticas(boolean)` NO SE TOCÓ**: el ciclo vive en el envoltorio, así que otra
sesión puede seguir editando esa función sin pisar la regla.

⚠ **El ancla avanza también con `sin_items` y `ya_hay_del_dia`** (el turno de la semana ya se
consumió) y **no avanza con `error:`**, para que una caída se reintente sola al día siguiente.

⚠ **El jobname sigue diciendo `ocs-auto-miercoles` y ya no es cierto**: `update cron.job` da
`permission denied for table job` y `cron.alter_job` no tiene `job_name`.

⚠⚠ **Generar a mano NO mueve el ancla solo: la mueve el DIÁLOGO** (v21.25). El backend no puede
adivinar cuándo se retoma, así que si el supervisor cierra con «Dejarlo como está», el ancla queda
donde estaba — y si estaba en hoy o mañana, la corrida de las 07:00 **vuelve a generar todo**,
porque el único guard propio de `generar_ocs_automaticas` es *"ya hay OC de HOY"* y lo de ayer no
lo mira. Medido en transacción abortada: con OC del día anterior y el ancla en hoy, genera **150
líneas**. Por eso el diálogo avisa en amarillo cuando el ancla está a un día o menos, y el botón
de escape dice qué día sale si no se elige nada. **La decisión es del supervisor; lo que no puede
es ser invisible.**

**Chequeo:** `select * from public."GV_OC_Auto";` · `select * from public.gv_reglas_perdidas;` ·
`node tests/oc-auto-ciclo.cjs`. `sql/gv_oc_auto_ciclo_v2114.sql`, §3.mk.
**Rollback, una línea:**
`select cron.alter_job(50, schedule := '0 10 * * 3', command := 'select public.generar_ocs_automaticas()');`

## ⚠ PROTOCOLO: Backend vs Front-end — decidir y avisar (ya NO se pregunta)

**Cuando alguien pide cambiar lógica** (normalización de códigos, cálculos, filtros,
agregaciones, reglas de negocio, etc.) hay que definir si va en el **backend**
(vista/función/RPC de Supabase) o en el **front-end**. Antes esto se preguntaba; desde
el **2026-09-11** ya no (regla "NO preguntar — razonar primero"): **se decide, se hace y
se avisa en una línea dónde se puso y por qué.**

El criterio ya está escrito y no hace falta consultarlo cada vez: **si el cambio afecta
datos persistidos o una regla de negocio, va al backend** (protocolo de abajo), y el front
sólo lo duplica como optimización de UX. Va al front únicamente lo que es **puramente
visual** (cómo se muestra, ordena o pinta algo que ya viene resuelto del backend).

La única pregunta que sobrevive es cuando las dos opciones cambian el resultado del
negocio y no hay regla previa que lo resuelva. Aplica a **todos los chats** sobre este repo.

## ⚠ PROTOCOLO OBLIGATORIO: Lógica de negocio SIEMPRE en el backend

**Conversiones, normalizaciones, validaciones y reglas de negocio que afectan
datos persistidos van en Supabase (triggers, funciones, vistas), NO en el
front-end.** El front puede duplicar la lógica como optimización UX (mostrar
el dato convertido antes de que el servidor responda), pero la fuente de
verdad es el backend. Si algo se implementa en el front, **siempre debe
existir el equivalente en el backend** (trigger/función) que garantice la
integridad aunque el front no lo haga.

Ejemplo concreto: la conversión MC↔Uni de insumos (v11.77) vive en el trigger
`normalizar_unidad_insumo` de `Movimientos_Stock`. El front también convierte
como optimización, pero el trigger es el que manda.

## ⚠⚠ PROTOCOLO OBLIGATORIO: la base es COMPARTIDA con Producción Virgilio

> **Actualización del dueño (2026-09-08): Producción Virgilio YA NO SE USA** (todo migró a
> Gestión). **Ya no se condiciona un cambio de Gestión por "no romper Producción".** Las reglas
> de abajo (agregar en vez de modificar, overrides, etc.) siguen siendo **buena disciplina** —
> reducen riesgo y mantienen el rollback limpio— pero **dejaron de ser un bloqueo**: si lo
> correcto es tocar un objeto compartido/de Producción, se hace. La contrapartida es
> **obligatoria**: todo cambio que toque un objeto compartido/de Producción se anota en
> **`docs/ROLLBACK-PRODUCCION.md`** con impacto y rollback exacto (ese archivo es la fuente
> única para desarmar lo que afecte a Producción). Los backups siguen siendo obligatorios.
>
> ⚠⚠ **MEDIDO el 2026-09-15: "ya no se usa" es falso para el FRONT.** Producción sigue abierta en
> alguna máquina y sigue pegando contra esta base. Se mide con `gv_app` (v14.51: la pone Gestión;
> **NULL = Producción**):
>
> ```sql
> select coalesce(gv_app,'(null)') app, count(*) n,
>        max(ts_cliente at time zone 'America/Argentina/Buenos_Aires')::text ultimo
>   from public."Registros_Produccion_Virgilio"
>  where ts_cliente >= now() - interval '3 days' group by 1 order by n desc;
> -- (null) | 33 | 2026-09-15 08:02:43
> ```
>
> Y su repo tiene commits hasta el 2026-09-14. **Costó un bug real:** el rename de las tablas PPP
> del 12/09 (`PPP_Programacion_Diaria` → `GV_PPP_Programacion_Diaria`) dejó a esa app imprimiendo
> los remitos con `Cliente —` / `Fecha Entrega —` durante 3 días, hasta que lo reportó un operario.
> Tapado con dos vistas de compatibilidad (`sql/gv_ppp_compat_nombres_viejos.sql`, §3.gc).
>
> **La regla que queda:** "no romper Producción" sigue sin ser un bloqueo —se toca lo que haya que
> tocar— pero **renombrar o borrar un objeto de `public.*` obliga a grepear TAMBIÉN el front de
> `loekemeyer/produccion-virgilio`**, no sólo `pg_proc.prosrc` y el `index.html` de acá. Y antes de
> escribir que una app está muerta, **medirlo con `gv_app`**.

**Gestión Virgilio y Producción Virgilio usan el MISMO proyecto Supabase
(`hrxfctzncixxqmpfhskv`) y la MISMA anon key.** Producción Virgilio (repo
`loekemeyer/Produccion-Virgilio`) fue la app que usaban los operarios (hasta el
2026-09-07). Cualquier cosa que se toque en `public.*` —una fila, una columna,
una función, un trigger, un cron, un grant— la ve esa app al instante.

**Regla del dueño (2026-09-04): sobre una tabla compartida se AGREGA, nunca se
MODIFICA lo que ya está.** Cuando no alcance con agregar, se crea una tabla nueva
que sea la **fuente canónica para Gestión**, y Producción sigue leyendo la suya.

| Querés… | |
|---|---|
| Agregar **filas** a una tabla compartida | ✅ `insert … on conflict do nothing`. Nunca `do update`. |
| Agregar una **columna** | ✅ nullable, sin `default` que reescriba, sin backfill, con prefijo `gv_`. |
| `update` / `delete` / `truncate` de filas existentes | ❌ → tabla `GV_*` de override + vista que la superpone (ej. `GV_PPP_Prog_Override` → `gv_ppp_programacion_diaria`, v13.50) |
| Cambiar o borrar una columna existente | ❌ → override |
| Objeto **nuevo** (tabla, vista, función) | ✅ con prefijo `PPP_Web_*`, `GV_*`, `gv_*`, `ppp_web_*` |
| `create or replace` de una función/vista que Producción usa | ❌ → crear `gv_<nombre>` nueva |
| Trigger sobre una tabla compartida | ❌ **nunca**: corre para Producción también |
| Dropear algo que no creamos nosotros | ❌ |

**Antes de tocar CUALQUIER objeto de `public.*`, grepear el repo de Producción**
(clonado en `/home/user/loekemeyer/produccion-virgilio`; si no está, traerlo con
`add_repo` + `git clone`):

```bash
grep -rn "NOMBRE_DEL_OBJETO" --include=*.js --include=*.html --include=*.sql \
  /home/user/loekemeyer/produccion-virgilio
```

Además: **toda vista nueva va con `security_invoker = true`** (sin eso corre como
`postgres` y saltea la RLS — el 2026-09-04 eso costó una filtración real), **RLS
prendida por defecto** en cada tabla nueva, y los **crons/Edge Functions llevan
prefijo** porque son globales al proyecto.

📒 **Todo cambio se anota en `docs/SUPABASE-GESTION-VIRGILIO.md` el mismo día**, con
el impacto medido (la consulta que lo prueba, no "no debería afectar") y el rollback.
Ese archivo —no la memoria— es lo que dice en qué estado está el pipeline al abrir
una sesión nueva. **Leerlo antes de tocar Supabase.**

📌 **Y qué FALTA para cerrar el pipeline está en `docs/PENDIENTES-PIPELINE-GESTION.md`**
(nota del dueño del 2026-09-04, cruzada con el estado real del repo). Al sábado 2026-09-05 el
pipeline está **cerrado de punta a punta**: pedido de la página → NP = nº de pedido → A
Programar / job 00:01 → picking, armado, carga (mismo código que Producción) → Facturación
(NP web: bajar el Excel ISIS = facturada) → control de remito = entregado, solo. Lo que
queda es del dueño (cron de Chef, El Martillo, operarios a Gestión) o estacionado
(duales, módulo Chef, tracking a la página). **Krikos ya no está estacionado** (v14.17,
07/09): la Bandeja de OC de supermercados está construida y la fecha de entrega del súper ya
viaja de LK a `lk_pedidos_match`. ⚠ **Y lo de Krikos que figuraba como pendiente del dueño YA
ESTÁ HECHO** (comprobado el 2026-09-13): `KRIKOS_IMAP_PASS` está en el Vault de LK desde el
11/09 y la rama `claude/krikos-tema-anterior-v0l88o` no tiene ningún commit fuera de `main`.
El ingest **corre**: la bandeja tiene 21 OC y la corrida de los :00/:10/:20 contesta
`ok:true`. No volver a pedirlos. **Leerlo al abrir una sesión nueva sobre el pipeline.**

## ⚠⚠⚠ CUANDO GESTIÓN TOMA CONTROL Y SE VUELVE LA VERSIÓN QUE USAMOS, SEGUIR CON LA NUMERACIÓN QUE DEJÓ VIRGILIO

**Estado desde el 2026-09-04 (viernes, a la noche): la numeración está PRENDIDA
(`numeracion_activa = 1`), el cron de tandas (jobid 71) activo, y las tandas con prefijo `GV-`
hasta el sábado 05/09, cuando el dueño lo hizo sacar (`tanda_prefijo = ''` → `E01A`).** Decisión del dueño: prender **sólo Virgilio**, sin tocar LK — el mail de
las 12:30 (`procesar-pedidos-web`) siguió andando hasta el **sábado 2026-09-05 a las 13:50 ART,
cuando el dueño lo hizo apagar** (crons 7 y 10 de LK en `active=false`, v12.94). Último envío a
ISIS: sábado 12:30, pedidos 1340..1349. **⚠ Cambio del sábado a la noche (v13.15): el dueño dijo
"el lunes van a empezar a usar GV, no más PV" → el mail del sábado se IGNORA y GV programa también
los 1340..1349** (`PPP_Web_Config.excluir_enviados_a_isis = 0`; no cargar ese mail en ISIS, quedarían
dobles). **Desde el lunes 2026-09-07 los operarios usan Gestión.** **⚠ v13.22 (sábado a la noche): ANTICIPACIÓN
MÍNIMA de 4 días hábiles** (`PPP_Web_Config.dias_anticipacion_min`, `gv_ppp_web_dia_minimo()`): el lunes
los operarios sólo arman lo que ISIS dejó (mar 8 / mié 9 / jue 10); lo que Gestión programe cae recién el
**viernes 11** en adelante (job 00:01 vía cron 71 con `{"fecha": …}`, intradía, "A Programar"). Poner en 0
para volver a hoy/mañana. §3.af. **El lunes 07/09 es Día del Metalúrgico: no hábil** (`GV_Dias_No_Habiles`,
§3.ag); primer día real con Gestión = martes 08. **Cupo diario = pickers típicos × 3 m³ (hoy 6), contando
ISIS + web** (`gv_ppp_web_cupo`, idea 6220, v13.23, §3.ah; `cupo_por_dotacion = 0` → 5 fijo). **v13.67 (lun 07/09 01:30): los crons 71 y 73 de Virgilio estuvieron apagados desde el 06/09 20:40 (otro chat) hasta que `ppp_web_armar_tandas` v7 hizo que la tanda ACUMULE entre corridas hasta 0,80 m³ (`sql/ppp_web_armar_tandas_v7_acumula.sql`, §3.av); están PRENDIDOS de nuevo.** **El cron de Chef quedó APAGADO el domingo 2026-09-06** (proyecto nkhzocgdpwtgrmwleihr, jobs 1
`procesar-pedidos-web` y 2 `retry-procesar-pedidos` en `active=false`, lo corrió el dueño; v13.31).
Último mail de Chef: sábado 05/09 12:30, pedido 217; el del viernes llevó el 216. **Ninguno de los dos
se carga en ISIS: 216 ya es E02A (vie 11) y 217 es E06A (lun 14).** Para volver a prenderlo:
`cron.alter_job(1, active := true)` y `(2, …)` en Chef. **Dueño 07/09: "no, dejalo apagado"** (Gestión programa Chef; si se prende, compras tipea dobles). **Cron 76 `gv-alerta-sin-eventos`** (lun–vie 10:30 ART, v13.72): día hábil sin eventos de operarios → Telegram.
Detalle, medición y rollback en `docs/SUPABASE-GESTION-VIRGILIO.md` §3.l y §3.p.

- **NP** → **v13.70 (2026-09-07): la NP web es un CONTADOR propio, un número por bloque, SIN sufijo** (dueño:
  *"el pedido tiene que ser único; no 1540-1, 1540-2; guardá el ID de la página pero que sea otro número; LK y 4
  dígitos"*): `LK 0001`, `LK 0002`… / `CH 0001`… (`gv_ppp_web_np_asignar` con lock, `PPP_Web_NP_Seed`, índice único
  `(empresa, np)`). El pedido de la página (`order_id`) queda guardado como referencia y se muestra "web LK 1350"
  hasta que se programa (ahí se asigna la NP). Un pedido de 4 bloques = 4 NP distintas. Deshace v12.92 (NP = nº de
  pedido con sufijo `-2`); `sql/gv_np_contador_v1370.sql`, §3.aw. Se
  programa por el job de las 00:01 para zona 1, 2 y 3 (`zonas_automaticas = '1,2,3'` desde v13.07)
  y a mano en "A Programar" para el resto.
  **Desde el 2026-09-05 además hay armado INTRADÍA** (idea 7317, cron jobid 73 — **cada 5 min
  desde el 15/09**, `*/5 9-23 * * *` UTC = 06:00–20:55 ART; antes cada 15 min lun–vie
  07:00–18:45 —, Edge Function v14 con `{"intradia": true}`): cuando lo pendiente de
  las zonas automáticas suma ≥ 0,80 m³ se arma ya, para hoy si es antes de las 12:00 y hay cupo, si no
  para el próximo hábil con cupo (`gv_ppp_web_proximo_dia_entrega`). §3.x de la doc de Supabase.
  **v13.47 (domingo 06/09, dueño: *"mandá directo a Programación si ya está, no más en A Programar"*):
  cada corrida programa TODO lo que tiene día previsible** — zonas automáticas en cascada de días con
  cupo, zonas manuales (4/5/6/7) al día en que ya hay camión a la zona (`gv_ppp_web_armar_pendientes`,
  §3.ao); el intradía corre todos los días 06:00–20:45 y el umbral está en 0,001. En A Programar quedan
  sólo Retira, Súper, sin zona y sin camión previsto. **v13.69: A Programar = pedidos | días; se arrastra el pedido DIRECTO al día, sin botones de tanda LK/Chef** (la planilla v13.61 se borró: al dueño no le gustó; la columna de tandas sin fecha sólo aparece si quedó alguna vieja). Soltar un pedido en un día arma la tanda con código automático y la programa (`aprGenerarTanda`; se descarta si falla: **ninguna tanda queda sin fecha**). **La PPP entra entera en una pantalla** (`pppFitPantalla`, zoom automático, sin scroll interno). Tandas numeradas como Producción (E01A, E02A…). **v13.60: camión = LETRA+NN y se REUSA por día y etiqueta** (Capital / GBA Sur / GBA Oeste / GBA Norte): una tanda nueva entra al camión que ya va ese día, aunque sea de ISIS (E01F, D68G); camión nuevo sólo si no hay. `sql/gv_ppp_web_camion_del_dia.sql`, §3.at. Ese día además se corrió la semana un día hábil (lun 7 feriado, nada armado; súper quedan) — backup `sql/backups/reprogramacion_20260906_pre_v1360.sql`.
  **Y las tandas se arman por CERCANÍA REAL** (v13.07, §3.y): sectores + vecinos en `GV_Sectores`,
  `GV_Barrios_Sector`, `GV_Sectores_Vecinos`, `GV_Barrios_Pares` (`sql/gv_sectores.sql`); Núñez
  nunca con Lugano, Barracas sí con Constitución o Avellaneda. Interruptor
  `PPP_Web_Config.sectores_activos` (0 = regla vieja por grupo de zona). Probar sin escribir:
  `gv_ppp_web_armar_simular(...)`.
  Regla del dueño: *"cuando Gestión tome control, va a asignarle la numeración
  nuestra a los pedidos que estén pendientes y a los que vayan cayendo"*. **Pendiente =
  pedido de la página con fecha ≥ `gestion_desde` (2026-09-03, piso) que Producción/ISIS no
  tenga** (v13.15). Con `excluir_enviados_a_isis = 1` además se excluye lo que salió por el mail
  (`enviado_a_compras`; era la regla de convivencia, v12.94); desde el sábado 05/09 a la noche
  está en 0 porque el lunes nadie usa Producción. La regla vive en UNA RPC de Virgilio, `gv_pedidos_web_excluidos`, que
  llaman el job y "A Programar"; los feeds de LK son crudos. Motivos: `enviado_a_isis`,
  `anterior_al_cambio`, `en_produccion`. **Bloques**: de a 18 (LK) / 15 (Chef) SEGUIDOS en el
  orden del carrito, igual que ISIS (v12.94; antes serpentina por m³).
  `pwebNumerar()` —la que numeraba todo al abrir una pantalla— quedó inalcanzable desde v12.82.
- **Tandas** → **codificación histórica `LETRA+NN+LETRA`** desde el sábado 2026-09-05 (dueño:
  *"sacá el prefijo GV-"*; `tanda_prefijo = ''`). `ppp_web_proxima_letra()` retoma desde la
  última letra de Producción (D71A) → la primera tanda de Gestión es **`E01A`**. Hasta ese día
  el prefijo era `GV-` para no pisarse con Producción; para volver: `valor_texto = 'GV-'`.
- **Canilla del espejo de ISIS: ABIERTA de nuevo desde el domingo 2026-09-06 (v13.51).** Gestión lee las
  vistas **`gv_ppp_programacion_diaria` / `gv_ppp_base_pedidos` / `gv_ppp_entregados_meta`**
  (`sql/gv_espejo_corte.sql`), que con `PPP_Web_Config.espejo_np_corte_lk/_chef = null` devuelven todo lo
  que ISIS numere (ISIS sigue cargando pedidos propios, ej. 98704 Salvetti D60G). Lo que NO debe verse
  (una NP de ISIS que duplica un pedido web ya programado por Gestión) se oculta **fila por fila** con
  `GV_PPP_Prog_Override.oculto = true` (`sql/gv_ppp_prog_override.sql`); las tres vistas y
  `gv_pedidos_web_excluidos` la saltean. Al 06/09 hay 10 ocultas: 98696–98703 y 44620/44621, el mail del
  sábado que se cargó en ISIS igual. La misma tabla sirve para **pisar tanda/fecha** de una NP de ISIS sin
  tocar la tabla compartida (44619 Chango Mas → E07A, v13.50). Estuvo cerrada del 05/09 al 06/09 (v12.90,
  corte 98694/44619); para cerrarla otra vez: `update public."PPP_Web_Config" set valor = 98704 where clave =
  'espejo_np_corte_lk'` (y 44621 en `_chef`). Detalle §3.m, §3.ap y §3.aq de `docs/SUPABASE-GESTION-VIRGILIO.md`.

**Para apagarlo (mismo día, todo reversible):**

```sql
-- en VIRGILIO (hrxfctzncixxqmpfhskv)
update public."PPP_Web_Config" set valor = 0 where clave = 'numeracion_activa';
select cron.alter_job(71, active := false);
```

**Hecho el sábado 2026-09-05: las tandas siguen la codificación histórica** (`tanda_prefijo = ''`;
`ppp_web_proxima_letra()` retomó desde la última letra que dejó Producción, D71A → `E01A`).
Para volver al prefijo de convivencia:

```sql
update public."PPP_Web_Config" set valor_texto = 'GV-' where clave = 'tanda_prefijo';
```

**La NP web es el número de pedido de la página** (v12.92): `LK 1350`, `LK 1350-2` (bloque 2),
`CH 0217`. Sin choque con Producción, cuyas NP son de 5 dígitos desde 44361 y sin prefijo. La
etiqueta la arma **`gv_ppp_web_np_label(empresa, np, np_idx)`** en el backend — prefijo +
espacio + 4 dígitos + `-bloque` si el bloque es > 1; el front (`pwebNpLabel`) y la Edge
Function (`npLabel`) la duplican sólo como optimización de UX. Historia del 2026-09-05: se
pasó de 5 a 4 dígitos (v12.91) y de contador propio a número de pedido (v12.92), las dos
veces antes de numerar el primero.

Con el prefijo vacío, `ppp_web_armar_tandas` vuelve sola a la codificación histórica
`LETRA+NN+LETRA` y `ppp_web_proxima_letra()` **retoma desde la última letra que dejó
Virgilio** (mira las dos tablas). No hay que tocar código ni redeployar nada.

Detalle y pruebas: `docs/SUPABASE-GESTION-VIRGILIO.md` §3.e y §3.f, `sql/ppp_web_tandas.sql`
y `sql/gv_tandas_diarias.sql`.

## ⚠ PROTOCOLO OBLIGATORIO: Backups antes de tocar datos en Supabase

**SIEMPRE que edites/alters/truncates/deletes en tablas de Supabase:**

1. **Haz un backup ANTES** de cualquier cambio:
   ```sql
   -- Exportar completa la tabla como SQL restore-ready
   SELECT * FROM table_name;
   -- Copiar resultado → archivo SQL con CREATE + INSERTs
   ```
2. **Guarda el backup** como `backup_table_YYYYMMDD_hhmmss.sql` en un lugar seguro (comentario/notas).

   ⚠ **Si el backup es una TABLA (`create table ... as select`), CERRALA en el mismo paso.**
   `create table as` la crea **sin RLS** y con los **grants por defecto** del esquema `public`,
   así que nace con `anon` pudiendo `INSERT` / `UPDATE` / `DELETE` — y un backup es una copia
   de datos reales, o sea la **puerta de atrás** a lo que la tabla madre sí protege. El
   2026-09-12 había **27 tablas de backup abiertas** así (una con 54.143 filas de saldos y
   otra con 23.647 de picking), y encima se podían borrar con la anon key: justo lo que tiene
   que estar íntegro el día que haya que restaurar. Las tablas de backup **no las lee ninguna
   app** — se consultan a mano por el MCP, que entra como `postgres` y saltea la RLS — así
   que cerrarlas no rompe nada:

   ⚠⚠ **Y desde el 2026-09-12 el backup NO se crea en `public`: va al esquema `zz_backups`.**
   Ese día `public` tenía **388 tablas y 133 eran backups** — un tercio. El desorden no lo
   hizo nadie en particular: lo hizo el protocolo, que decía crearlos ahí. Se movieron todas
   (public quedó en 256) después de comprobar que no las usa **nadie**: 0 vistas, 0 funciones,
   0 crons, 0 FK, 0 triggers, y 0 apariciones en el código de `gestion-virgilio`,
   `produccion-virgilio` y `planify` (780 archivos). El índice de lo que se movió está en
   `public."GV_Backups_Indice"`.

   ```sql
   create table zz_backups."GV_Backup_<lo_que_sea>_<YYYYMMDD>" as select … ;
   -- ⬇ las dos líneas que NO hay que olvidarse
   alter table zz_backups."GV_Backup_<lo_que_sea>_<YYYYMMDD>" enable row level security;
   revoke insert, update, delete, truncate on zz_backups."GV_Backup_<lo_que_sea>_<YYYYMMDD>"
     from anon, authenticated;
   ```

   El esquema `zz_backups` ya tiene revocado el acceso para `anon` y `authenticated`, así que
   una tabla creada ahí **nace cerrada** aunque uno se olvide de las dos líneas. Igual van:
   son gratis y no dependen de que nadie se acuerde. Para volver un backup a `public`:
   `alter table zz_backups.X set schema public;`. Para borrarlos todos de verdad:
   `drop schema zz_backups cascade;`.

   Sin policies, con la RLS prendida `anon` ve **0 filas** (no da error, simplemente no ve
   nada), que es lo que se quiere. Chequeo de que no quedó ninguna suelta:

   ```sql
   select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity
      and (has_table_privilege('anon', c.oid, 'INSERT')
        or has_table_privilege('anon', c.oid, 'UPDATE')
        or has_table_privilege('anon', c.oid, 'DELETE'));
   -- vacío = todo bien
   ```
   ⚠⚠ **El backup se guarda con la CLAVE PRIMARIA de la tabla.** El 2026-09-12, al corregir
   `Despiece x Articulo`, el backup se guardó por `COD` — que NO es único (754 filas, 238
   códigos). Para los 49 códigos que tenían filas con valores distintos entre sí, ese backup
   sólo permite restaurar **a nivel código, no fila por fila**. Si no se sabe cuál es la clave,
   se averigua ANTES de escribir:

   ```sql
   select column_name from information_schema.columns
    where table_schema='public' and table_name='<tabla>' order by ordinal_position;
   -- y confirmar que es única:  select count(*), count(distinct <clave>) from public."<tabla>";
   ```

   ⚠ **Y ojo con los JOIN por una columna que no es única: multiplican.** En esa misma tabla, el
   primer intento de contar las filas a tocar dio **1320 de una tabla de 754** — imposible, y por
   eso no se ejecutó. Si un conteo da más filas que la tabla, el join está mal, no los datos.

   ⚠ **Medir con la MISMA granularidad con la que se va a escribir.** Una medición agrupada con
   `max()` por código dijo "67 códigos mal"; fila por fila eran **23 con valor distinto y 55
   vacíos**. Un `UPDATE` va fila por fila, así que la medición también.

3. **Ejecuta tu cambio** (ALTER, TRUNCATE, DELETE, INSERT).
4. **Si algo falla o se rompe:** Restore inmediato ejecutando el SQL guardado.

**Ejemplo:**
```sql
-- BACKUP (ejecutar primero, guardar resultado)
SELECT 'INSERT INTO Capacidad_Sector (empresa, sector, cod, cajas_max) VALUES (' ||
  quote_literal(empresa) || ',' || quote_literal(sector) || ',' || 
  quote_literal(cod) || ',' || quote_literal(cajas_max) || ');'
FROM "Capacidad_Sector"
WHERE empresa IS NOT NULL;

-- Aquí va tu cambio (DESPUÉS de guardar el backup)
ALTER TABLE Capacidad_Sector ADD COLUMN nueva_col TEXT;

-- Si falla: restore ejecutando los INSERTs guardados
```

**Historial de incidentes:** 2026-08-07 — TRUNCATE accidental de Capacidad_Sector (730 registros
perdidos). Lección aprendida → este protocolo existe.

⚠⚠ **`DROP ... CASCADE`: contar los dependientes TRANSITIVOS, no los directos.** Un
`create or replace` no existe para matviews, así que tocar `vista_stock_procesada` obliga a
DROP + CREATE. Las dos veces que se hizo (v16.20 y v16.33) el CASCADE se llevó
`gv_importados_ordenes` —que cuelga en **segundo** nivel, vía `gv_importados_stock_dep`— y la
pantalla de Importados quedó en 404. La segunda vez fue con una consulta de dependencias ya
hecha: devolvía sólo las directas. Antes de cualquier DROP CASCADE:

```sql
with recursive dep as (
  select c.oid, c.relname, c.relkind, 1 lvl
    from pg_class c where c.oid = 'public.<el objeto>'::regclass
  union
  select c.oid, c.relname, c.relkind, dep.lvl + 1
    from dep
    join pg_depend d  on d.refobjid = dep.oid
    join pg_rewrite r on r.oid = d.objid
    join pg_class c   on c.oid = r.ev_class and c.oid <> dep.oid
)
select lvl, relkind, relname from dep where lvl > 1 order by lvl, relname;
```

Respaldar la definición + opciones + grants de **todas** las que salgan, recrearlas en la misma
transacción, y después mirar `select * from public.gv_endpoints_rotos;` — es el centinela que
cazó las dos veces.

⚠ **Y el CREATE completo de cada vista va EN EL REPO, no "aplicado en la base".** Lo que hizo
cara la recuperación no fue el CASCADE: fue que la v16.30 se había aplicado como reemplazo de
texto sobre `pg_get_viewdef`, así que el repo no tenía la definición viva y hubo que
reconstruirla juntando un archivo viejo con instrucciones en prosa. Si se parchea una vista con
`replace()` sobre su propia definición, **guardar después el `CREATE` resultante completo**.

⚠⚠ **`CREATE OR REPLACE VIEW` sin `WITH (...)` BORRA las `reloptions` — o sea que te comés el
`security_invoker`.** No las conserva: las resetea a null, sin decir nada. Y una vista sin
`security_invoker` corre como `postgres` y **saltea la RLS**, que es la filtración que costó caro
el 2026-09-04. Pasó de nuevo el 2026-09-15 (v18.05) con `gv_ppp_web_estado` y
`gv_fac_armado_sin_facturar`: las dos se reemplazaron para agregarles una condición y las dos
perdieron la opción. Entonces, al reemplazar una vista:

```sql
-- ANTES: anotar qué opciones tiene
select relname, reloptions from pg_class where oid = 'public.<vista>'::regclass;
-- DESPUÉS (siempre, aunque parezca que no hacía falta):
alter view public.<vista> set (security_invoker = true);
-- Y el chequeo de que no quedó ninguna suelta que la anon pueda leer:
select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
 where n.nspname='public' and c.relkind='v'
   and coalesce(array_to_string(c.reloptions,','),'') not like '%security_invoker%'
   and has_table_privilege('anon', c.oid, 'SELECT');
-- vacío = todo bien
```

⚠⚠ **`DROP COLUMN`: barrer también `pg_proc.prosrc`, no sólo las vistas — y DESPUÉS llamar a
las funciones.** Postgres **no revalida el cuerpo de una función** cuando se dropea una columna:
el `DROP COLUMN` sale sin un solo error y el fallo queda **latente hasta la primera llamada**. El
2026-09-12 la v16.39 borró `precios_venta.uxb` con un barrido que miró vistas y no funciones, y
dejó **tres funciones rotas** en producción — `isis_pedido_json`, `gv_isis_pedido_json` y
`gv_ppp_web_valor_items` (esta última **valoriza los ítems de un pedido web**, o sea camino de
precio). Se descubrieron de casualidad un día después, al hacer un `CREATE OR REPLACE` de esas
funciones por otro motivo: ahí Postgres sí validó el cuerpo y falló.

```sql
-- ANTES de dropear una columna
select p.oid::regprocedure from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.prosrc ~* '\muxb\M';   -- el nombre de la columna
-- DESPUÉS del drop: llamar de verdad a cada una. Un DROP COLUMN limpio no prueba nada.
```

⚠ **Renombrar una tabla es MUCHO más barato que reescribir sus consumidores.** Las **vistas
referencian por OID**, así que un `alter table ... rename to` es transparente para ellas y siguen
andando sin tocarlas. Sólo hay que reescribir lo que nombra por **texto**: las funciones
(`prosrc`) y el front. El 2026-09-12, pasar las 3 tablas PPP a nombre `GV_` bajó el cambio de
**~70 objetos a 31 funciones + 1 constante** de `index.html`. El loop mecánico es
`pg_get_functiondef` → `replace()` → `execute`, todo en UNA transacción con el nombre de la
función en el `raise exception`: si una no compila, no queda nada a medias (pasó, y así se
encontró lo del `DROP COLUMN`).

**2026-09-11 (v15.44) — `index.html` y `sw.js` pusheados VACÍOS a `main`: la app quedó en blanco
con los operarios pickeando.** Causa: un script de edición que abría el archivo en modo `w` dentro
de la misma expresión que lo leía (`open(p,"w").write(open(p).read()...)`); Python evalúa el `open`
de escritura primero, así que trunca antes de leer. Se restauró por hotfix (`0995684`) y se repusieron
los cambios en la v15.45. **Regla: al editar un archivo por script, leer a una variable, verificar el
largo del resultado, y recién entonces escribir. Y antes de `git commit`, mirar `git diff --stat`: un
archivo con miles de líneas borradas no es un cambio, es un error.**

## ⚠ REGLA: si algo tira «canceling statement», mirar `pg_stat_statements` ANTES de tocar la función

**Luis, 2026-09-17:** *"cuando le doy «Sí, cancelar» sale lo de canceling statement"*. La RPC que
fallaba tardaba **1,3 s** medida paso por paso contra un `statement_timeout` de **8 s** — o sea 6×
de margen. El problema no era ella: era que **el cron 34 (`detectar_faltantes_llegaron`) ocupaba el
54 % del tiempo de la base** (3.606 corridas, 64,7 s de media, 233.157 s de ejecución en 120 h de
reloj) porque corría un `exists` correlacionado por fila: 967 × 63.614 = 61,5 millones de
comparaciones, cada 2 minutos. Optimizar la RPC lenta habría sido tiempo perdido.

**El orden que hay que seguir**, y son tres consultas:

```sql
-- 1) ¿quién se está comiendo la base? (esto contesta el 90 % de los "timeout al azar")
select calls, round(total_exec_time/1000) total_s, round(mean_exec_time) mean_ms,
       round(max_exec_time) max_ms, left(regexp_replace(query,'\s+',' ','g'),110) q
  from extensions.pg_stat_statements order by total_exec_time desc limit 12;
select stats_reset::text, now()::text from extensions.pg_stat_statements_info;  -- 2) la ventana
-- 3) y recién ahora, la función sospechosa, paso por paso con clock_timestamp()
```

**Comparar `total_s` contra los segundos de reloj de la ventana**: si una sola consulta suma más
de la mitad, ahí está el problema, no en la que se queja.

Cuatro cosas que aprendimos y no hay que volver a probar:

- **Subir el `statement_timeout` desde adentro de la función NO sirve.** Postgres arma el timer al
  empezar el statement y no lo re-arma si el GUC cambia después. Medido: con `set local
  statement_timeout = '2s'`, un `set_config('statement_timeout','25s',true)` adentro de un `do`
  no evita que corte a los 2 s.
- **Medir desde el MCP no reproduce el timeout.** El MCP entra como `postgres`, que **no tiene**
  `statement_timeout`; `authenticated`, `anon` y `authenticator` tienen **8 s** (y `authenticator`
  además `lock_timeout = 8 s`). Para medir como el front: `set local role authenticated`.
- **Un statement cortado por timeout NO queda en `pg_stat_statements`.** Que la RPC que se quejó no
  aparezca ahí es señal de que nunca terminó, no de que no se llamó.
- **Y el corte deshace la transacción ENTERA**, así que reintentar es seguro: eso es lo que hay que
  decirle al usuario ("no se canceló nada, probá de nuevo"), no el texto crudo de Postgres.

Detalle y medición: `docs/SUPABASE-GESTION-VIRGILIO.md` §3.iz, problema 382.

## ⚠ REGLA: un CTE con el nombre de una variable plpgsql explota SÓLO al ejecutarse — y sólo en su rama

**2026-09-17 (v19.56, problema 400).** Al agregarle rotación al tope del armador, los CTE nuevos se
llamaron `z / g / k / r / o / a / e`. `gv_ppp_web_armar_pendientes` **ya tiene una variable
`r record`** en su `declare`, así que el CTE `r` la vuelve ambigua:

```
ERROR: 42702 column reference "r.*" is ambiguous
DETAIL: It could refer to either a PL/pgSQL variable or a table column.
```

**Las tres cosas que lo hicieron pasar inadvertido**, y son las que hay que recordar:

1. **El `CREATE OR REPLACE` salió limpio.** Postgres no valida los cuerpos de las sentencias SQL
   de una función plpgsql al crearla: el error es de **ejecución**.
2. **La función corrió bien después de aplicarla** (36 ms) — pero con 0 pendientes, o sea **sin
   entrar nunca a la rama nueva**. Que la función no explote NO prueba que el camino nuevo ande:
   hay que llamarla con datos que **entren por ahí**. En este caso, con más pedidos que el tope.
3. **La prueba previa sí había andado**, porque se hizo en un bloque `do $$` anónimo que no tiene
   la variable `r`. El SQL suelto y el SQL adentro de la función no son el mismo ambiente.

Resultado: la corrida del cron de las 17:55 de **LK** murió (y `chef` no, porque sus 23 pedidos no
llegaban al tope y no entraban a la rama). Una corrida perdida, 5 minutos.

**Qué hacer:** a todo CTE nuevo dentro de una función plpgsql, **prefijo** (`_tp_z`, `_tp_g`…).
Es gratis y saca el problema de raíz. Y antes de dar por buena una rama nueva, **hacerla entrar**.

⚠ **Lo bueno**: lo cazó el centinela que la misma versión había agregado — el hueco en
`GV_PPP_Web_Armado_Log`. Un camino nuevo sin forma de ver si corrió es un camino que falla en
silencio; por eso el log iba junto con el cambio y no después.

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

## Estructura: dos apps en un repo (Virgilio + Cervantes + selector)

Este repo junta **las dos plantas** (reemplaza al viejo repo `App-Produccion`, que se
borró). Layout:

- **Raíz** → app **Virgilio** (sin cambios; la usa también la app de Play Store/TWA).
- **`/cervantes/`** → app **Cervantes** (desde 2026-09-10 **el fuente vive acá**; el repo
  `Registro-Produccion-2.0` quedó congelado — ver más abajo).
- **`/selector/`** → pantalla **"¿Dónde vas a trabajar hoy?"** que linkea a ambas:
  Virgilio `../` y Cervantes `../cervantes/`. Recuerda la última planta usada
  (`localStorage` `appprod_ultima_planta`, marca "Última vez"), **no redirige solo**.
- Botón **"← Cambiar planta"** en la pantalla inicial de cada app → va al `selector/`.
- `selector/sw.js` y `cervantes/sw.js` no cachean (mismo patrón que Virgilio). Las dos
  apps conviven sin pisarse: tablas Supabase distintas (`Registros_Produccion_Virgilio`
  vs `Registros Produccion Cervantes`), IndexedDB y claves `localStorage` con prefijos
  distintos. Cervantes usa rutas relativas y SW con scope `/cervantes/`.
- **`/monitor/tv.html`** → **monitor liviano para la TV de pared** (v18.74): el mismo
  tablero, de SOLO LECTURA y sin nada clickeable, en **56 KB** contra los ~4,97 MB que
  pesa cargar el `index.html` entero (el monitor usa el 8,9 % de ese código, y el
  kiosko se recarga cada 7 min porque se queda sin RAM). **Es una segunda vista de los
  mismos datos**: si cambia una regla del tablero hay que tocar los dos lados — en el
  código de `tv.html` esos puntos están marcados con `≡ index.html`, y `tests/mon-tv.cjs`
  los verifica. `/monitor` sigue yendo al monitor grande. Detalle en `GUIA-PROYECTO.md`,
  sección "Monitor TV".
- **Entrada por defecto = Virgilio (raíz)**, no el selector (para no romper la URL
  actual ni la app de Play Store). Si se quisiera el selector como entrada, mover el
  selector a la raíz y Virgilio a `/virgilio/` (revisar TWA).
- ✅ **`/cervantes/` YA NO es una copia: es el fuente** (decisión del dueño, 2026-09-10).
  La integración se hizo **para que los operarios de Registro Producción pasen a Gestión
  Virgilio**, así que el código de Cervantes **se mantiene acá**, en `cervantes/`. El repo
  `Registro-Produccion-2.0` quedó **congelado** en `68eec03` (app **v1.9.0**): no se toca,
  no se re-sincroniza desde ahí, y el dueño **lo va a borrar** cuando termine la mudanza.
  Su URL se deja andando mientras tanto **a propósito** — sin cartel ni redirect.
  Nada se pierde al mudarse: es el **mismo origin** de GitHub Pages, así que la cola de
  eventos pendientes (IndexedDB `registro-prod` + localStorage) y la sesión son las mismas
  en las dos URLs.
- **Login de Cervantes = el global de la raíz** (gate en el `<head>` de `cervantes/index.html`,
  v1.9.0). Con sesión (Google autorizada, o sesión por legajo del día en `vir_legajo_auth`)
  **no se vuelve a pedir el legajo**: lo precarga, esconde el input y saluda por nombre. Los
  supervisores de la lista tipean el legajo. Sin sesión: bajo `/cervantes/` vuelve a `../`;
  en la URL suelta cae a la pantalla de legajo (el gate detecta dónde corre).
  **Un operario puede trabajar en las dos plantas** (regla del dueño, 2026-09-10: *"se tiene
  que poder, porque pueden ir entre Cervantes y Virgilio"*) → Cervantes **NO** filtra por
  `Empleados.Sede`; un legajo de sede V entra igual. Por eso el saludo lleva al lado
  **"¿No sos vos? Cambiar operario"** (v1.9.1): en un equipo compartido borra la sesión del
  anterior y devuelve el campo de legajo, que si no quedaba escondido y el que agarraba la
  tablet tomaba producción con el legajo del otro. Una sesión **de otro día** no se usa
  (se valida `day` contra hoy AR) y desde v1.9.2 **se borra ahí mismo**, sin esperar a que
  la limpie la raíz. Ojo: eso es la sesión de LOGIN; el **estado de trabajo** es otra cosa
  y no se toca — vive en `prod_state_Cervantes_v2_supa::<día>::<legajo>` y su guard diario
  retiene 14 días calendario (para no perder una matriz abierta el sábado).
- **Al tocar Cervantes**: subir `LOCAL_VERSION` (`cervantes/app.js`), `CACHE_VERSION`
  (`cervantes/sw.js`) y los `?v=` + el badge de `cervantes/index.html` **al mismo número**.
  Si se desalinean, el celular se queda con el JS viejo cacheado — pasó, y por eso los
  operarios corrieron 5 versiones atrás sin que nadie lo notara.

### Admin de Cervantes — dos pantallas, COPIADAS acá (`cervantes-admin/`)

- **El supervisor que elige Cervantes en el selector de planta NO va a la pantalla de
  operario: va al admin** (`chooseCervantes` → `showCervAdmin`, v14.73). El operario sigue
  derecho a `./cervantes/`. La distinción es `__identity.type === "supervisor"`.
- **Los admin de Cervantes son DOS y están COPIADOS acá** (decisión del dueño, 2026-09-10:
  *"copia, no link… ya que esto es una integración"*): `cervantes-admin/entero/` (repo
  `GestionProductivaEntero`) y `cervantes-admin/gp2/` (repo `Gestion-Productiva-2.0`). La
  pantalla `#cervAdmin` muestra las dos tarjetas. **Todo Cervantes vive en este repo**: la
  app de operario en `cervantes/` y los dos admin acá.
- **De la copia se dejaron afuera** los archivos de repo, no de app: `.git`, `.claude`,
  `.vscode`, `.mcp.json`, `.planning`, `LOCKS.txt` y los `.bat`. **Y desde el 2026-09-12
  tampoco entra `db/A_Costos_VIGENTES.xlsx`**: es la planilla madre de costos, o sea datos, y
  este repo se sirve por GitHub Pages. Que el `.gitignore` del origen la deje pasar allá no
  significa que tenga que viajar acá.
- **Re-sincronizada el 2026-09-12 (v16.32)**, con 92 diferencias acumuladas. Cómo se hace, para
  la próxima: copiar `gestion-productiva-2.0` entero salvo lo de arriba, **re-aplicar a mano los
  parches de la copia** (los de abajo) y **verificarlos uno por uno antes de commitear** — el
  del `signOut` es el que importa: si se pierde, un supervisor que no esté en la whitelist de
  GP2 queda echado de Gestión entera. El `CLAUDE.md` del origen se copia **renombrado**, con el
  banner de "esto es documentación" pegado adelante. Chequeo de que no quedó ninguno suelto:
  `find cervantes-admin -name CLAUDE.md` tiene que dar vacío.
- **Los `CLAUDE.md` de los dos admin SÍ están, pero RENOMBRADOS** (v14.75):
  `cervantes-admin/entero/claude-admin--GestionProductivaEntero.md` y
  `cervantes-admin/gp2/claude-admin--Gestion-Productiva-2.0.md`. Ahí está cómo opera cada
  admin (tablas madre vs derivadas, orden de normalización, "casa del vecino", convenciones,
  trampas conocidas) y no está repetido en ningún otro `.md`. **Nunca renombrarlos de vuelta
  a `CLAUDE.md`**: con ese nombre se cargan como instrucciones del proyecto y una sesión de
  Gestión Virgilio pasa a obedecer las reglas de otro repo. Cada uno abre con un banner que
  lo aclara. Las reglas que mandan acá son las de ESTE archivo.
- **Los 5 agentes de GP2** quedaron archivados en `cervantes-admin/gp2/agentes/` (fuera de
  `.claude/`, con su README): se conserva el trabajo si aquel repo se apaga, sin que una
  sesión de acá los cargue sola. Para usarlos hay que copiarlos a `.claude/agents/` a mano.
- **Parches propios de estas copias** (no revertirlos al re-sincronizar):
  1. **Ningún rechazo de whitelist hace `signOut()`** (`entero/login.html`, `gp2/login.html`).
     La sesión de Google es **compartida** con Gestión (mismo origin, mismo proyecto): cerrarla
     ahí echaba al supervisor de Gestión entera sólo por no estar en `usuarios_permitidos`
     (que hoy tiene **2 mails**: `loekemeyer.n8n@` admin y `loekemeyer.logistica@` envíos).
     Ahora sólo se limpia el `sessionStorage` de esa app.
  2. **`entero/Inicio/index.html`**: el botón "Cerrar sesión" pasó a **"← Volver a Gestión"**
     (`../../../`) — hacía `signOut` + borraba las claves `sb-*`, o sea te echaba de todo.
  3. **`gp2/GP2_MODULOS.html`**: link **"← Volver a Gestión"** en el header (`../../`).
  4. **La fecha de carga lleva el AÑO: `dd/mm/aa`, nunca `dd/mm`** (v20.54, pedido de Elías,
     2026-09-21). `getDiaMesHoy()` y `getFechaDiaMes()` de `Talleristas/Envios/EnviosTall.js` y
     `getDiaMesHoy()` + los dos `split("-")` de `Prov Serv/Envios/EnviosPS.js`, en las **dos**
     copias, escribían el día y el mes y **tiraban el año** — incluso cuando el operario elegía
     la fecha en el `<input type=date>`, que lo trae. Medido ese día: **154 filas de `Envios a
     Talleristas` y 41 de `Envios a PS` sin año**, todas de agosto y septiembre de 2026, o sea
     que la carga de hoy lo estaba perdiendo. Hoy no molesta porque el año se adivina; el 1.º de
     enero esas filas dejan de poder ubicarse (`StockFlejes/cajas.js` las fecha con
     `hoy.getFullYear()`). El formato elegido es el que ya tenían las otras **2.446** filas, y
     ningún lector se rompe: los parsers (`mmDe` / `ddDe` de `EnviosPS.js`, los `split('/')`)
     ya toleran `dd/mm`, `dd-mm`, `dd/mm/aa`, `dd/mm/aaaa` e ISO, y **no hay un solo filtro por
     igualdad** sobre `Dia-mes`. ⚠ Al tocar cualquier pantalla de carga, mirar que la fecha que
     se guarda tenga año. **`Entregas PS` escribe ISO (`arDateISO()`) y se dejó como está**:
     tiene el año, y cambiarla movería un formato que los lectores ya soportan a propósito.
- **`.nojekyll` en la raíz**: sin eso, Pages corre Jekyll y **no publica** lo que empieza con
  `_` — y las copias traen varios (`_backup_relevamiento_*`, `_export`, `_archivo`).
- El botón **🏭 Admin Cervantes (GP2)** del panel supervisor abre **esa misma pantalla**
  (`openAdminCervantes` → `showCervAdmin`): una sola puerta, no dos criterios.
- ⚠ **Ojo, deuda heredada**: cada admin trae adentro su propio `Produccion/RegistroApp/`, o
  sea que en el repo ahora hay **más de una copia** de la app de registro además de
  `cervantes/`. No se tocó; si algún día se unifica, es ahí donde hay que mirar.
- **No hace falta puente de sesión** (a diferencia de `/admin/` de LK, que necesita
  `lk_bridge_vjwt` porque es OTRO proyecto Supabase): GP2 usa el **mismo proyecto**
  `hrxfctzncixxqmpfhskv` y el **mismo origin**, con el `storageKey` default, así que la
  sesión de Google del supervisor ya se ve del otro lado y el login de GP2 entra solo
  (`getSession()` → `procesarSesion` → whitelist `GP2.get_role_for_email`).
- ⚠ **Hoy el login de GP2 está APAGADO**: `GP2_AUTH_ON = false` en su `auth-guard.js`
  (lo apagó el usuario el 2026-08-29: *"la página ya está privada y va a costar que
  accedan, por ahora prefiero que esté suelto"*). O sea que ese botón hoy entra **sin
  pedir nada**. Para volver a prenderlo hay que tocar el OTRO repo: `true` ahí y bumpear
  el `?v=` de `auth-guard.js` en sus HTML.

## ⚠ REGLA (Elías, 2026-09-21, v20.58): la fecha se guarda ENTERA — y el blindaje va con centinela

Dos cosas que salieron del mismo tirón y no se separan.

### 1. Una fecha sin año es un dato que se pudre solo

`opEnviar` de **`recepcion.js`** —la pantalla de Recepción, la que usan los operarios— armaba
el `Dia_mes` de **`Entregas Prov AT`** tirando el año: `partes[2] + "-" + partes[1]` → `18-09`.
**El 100 % de esa tabla nacía sin año**; las 121 filas que hoy lo tienen se lo puso alguien a
mano entre el 25 y el 31/08. El mismo renglón, con la fecha vacía, escribía `Dia_mes = ""` y la
entrega entraba sin fecha sin que nada avisara.

Mirá el `else` de esa misma función: para `Entregas Tallerista Virgilio` guarda
`Fecha: opState.fecha` **entera**. Mismo archivo, dos ramas, dos criterios — por eso una tabla
tiene año y la otra no.

Lo que costó: de las 41 filas sin datar, **37 se recuperaron leyendo `Fecha_RTO` /
`Fecha_Factura` de la misma fila** (coinciden día y mes en las 37) y **4 hubo que
preguntárselas a Elías** (Pintos, remito 0438, `17-09`). Y lo primero que se intentó fue
deducir el año por la secuencia de `id`: Elías lo frenó —*"si no tienen forma no les inventes;
intentá buscar registros, logs"*— y tenía razón, porque el registro existía y estaba en la
propia fila. **Antes de deducir un dato, mirar si la fila no lo trae al lado.**

Hoy: `dd/mm/aa`, y sin fecha no se graba. Lo sostiene `tests/recepcion-fecha-anio.cjs`.

⚠ **`Entregas Prov AT` ya tiene `created_at`** (default `now()`, v20.58). Las 162 filas viejas
quedan en **NULL a propósito**: no se les inventa una fecha de carga.

### 2. Blindar sin centinela es cambiar un error ruidoso por uno mudo

**Elías, textual:** *"pero cómo nos daríamos cuenta que entró una vacía?"*

`Entregas_Tallerista_Excel` castea `"Fecha"::date`, así que **una** fila con `'|||'` hacía que
la vista entera devolviera `22007` y se viera vacía: 1.409 filas invisibles por culpa de una,
durante cinco meses. Ponerle un `CASE` para que no explote es correcto, **pero solo eso deja el
dato sucio entrando en silencio**. Por eso el blindaje se aplicó junto con:

```sql
select * from public.gv_fechas_carga_invalidas;   -- vacía = todo bien
```

Barre las 6 tablas de entregas y envíos y dice `fecha VACIA`, `sin año` o `no es una fecha`, con
tabla, id y valor. Al 21/09 marca 4 filas: las de Pintos 0438 que faltan datar.

**La regla general:** cuando se tape un error que hoy se ve (una pantalla que se rompe, un
proceso que corta), el tapón va **en el mismo commit** que la forma nueva de enterarse. Si no,
lo único que se logró es dejar de ver el problema. Es el mismo criterio de §"una lectura ROTA no
es un CERO": el centinela tiene que mirar dónde queda huella **cuando falla**, no cuando anda.

**Y se prueba rompiéndolo:** se insertó una fila con `Fecha = '__PRUEBA__'`, se comprobó que la
vista sigue devolviendo todo (1.410 filas, esa con `Dia` nulo) y que el centinela la caza, y se
borró. `sql/gv_fechas_carga_v2058.sql`.

## Panel Web LK bajo `/admin/`

Desde v9.11 el repo hospeda una **copia del panel admin de PaginaLK** bajo
`/admin/`. Se accede desde el panel supervisor de Virgilio con el botón grande
**🌐 Panel Web LK** (fila principal, 7 columnas). El botón chequea supervisor y
navega a `admin/admin.html`. Login: **código OTP de 6 dígitos al mail** vía la
Edge Function `admin-login-otp` (verify_jwt=false) que manda el código con
Resend directo (`onboarding@resend.dev` como sender — el SMTP nativo del
proyecto LK apunta a `@loekemeyer.com` sin verificar en Resend y rechazaría).
Al verificar setea un password temporal aleatorio en el user y el front hace
`signInWithPassword` para quedar con sesión.

### Decisión de arquitectura: coexistencia, NO migración

- El admin apunta al proyecto Supabase **LK** (`kwkclwhmoygunqmlegrg`) —
  distinto del de Virgilio (`hrxfctzncixxqmpfhskv`).
- Son **dos proyectos Supabase separados a propósito**: producción y comercial
  son dominios distintos con dueños de datos distintos (ISIS/ERP produce
  `sales_lines`; Virgilio produce `Registros_Produccion_Virgilio`).
- **No migrar tablas ni RPCs de LK a Virgilio.** La copia del admin son 31k
  líneas con 60 RPCs, 40+ tablas, 4 Edge Fns, caches y crons propios; moverlo
  serían semanas de trabajo sin ganar función que hoy no exista.
- Cuando desde Virgilio haga falta un dato del admin (BCRA, deuda, historia de
  un cliente titular de una NP), agregar un cruce puntual vía `postgres_fdw`
  (mismo patrón que ya usa Virgilio contra LK para PPP, o LK contra Chef para
  el padrón). Un cruce por vez, on-demand.

### La copia bajo `/admin/` es un espejo, no un fork

- Cambios que hagan falta al admin **deben originarse en el repo `PaginaLK`**
  y después re-copiarse acá. Mismo patrón que `/cervantes/`.
- Archivos copiados: `admin.html`, `admin.js`, `admin-supercot.js`,
  `admin-osa.js`, `admin-excel-krikos.js`, `analisis-venta-cliente.js`,
  `analisis-cobranzas.html/.js/.css`, `carga-pedidos.html`, `historial.html/.js`,
  `sugerencias.html/.js`, `excel-parser-smart.js`, `argentina-map-data.js`,
  `argentina-provinces.json`, `version.js`, `css/admin.css`, `css/productos.css`,
  `osa/`, `img/favicon.jpg`, `img/no-image.jpg`.
- **Ajustes propios de la copia** (no revertir al re-sincronizar): (a) redirects
  `location.href = "/mayorista"` en admin.js → `"../"` (index Virgilio),
  (b) botón sidebar "Volver a Mayorista" → "Volver a Producción" con `href="../"`,
  (c) `<meta name="robots" content="noindex,nofollow" />` en los HTML del admin
  para que ni buscadores ni la revisión del TWA lo indexen, (d) handler de
  login OTP `lkSendOtp`/`lkVerifyOtp` al final de admin.js que llama a la
  Edge Function `admin-login-otp`, (e) form de OTP dentro del `#loadingScreen`
  de admin.html, (f) redirects `/mayorista` → `../` en `carga-pedidos.html`
  (3 lugares), `historial.html`, `historial.js`, `sugerencias.html`,
  `sugerencias.js`, `analisis-venta-cliente.js` (2 lugares) — el original
  apunta a `mayorista.html` del sitio LK que no existe en Virgilio,
  (g) `historial.html` usa `img/favicon.jpg` (no `.png`, no existe),
  (h) **entrada directa sin OTP desde Virgilio** (v12.35): `admin.js` trae
  `lkTryBridge()` y `checkAuth()` lo llama antes de mostrar el login; canjea el
  `access_token` de la sesión Virgilio (dejado en `sessionStorage` como
  `lk_bridge_vjwt` por `openPanelWebLK()` de Virgilio, mismo origen) por la
  acción `bridge` de la Edge Fn `admin-login-otp`. Si al re-sincronizar se pisa
  alguno, buscar por `LK_ADMIN_EMAIL`, `LK_OTP_FN_URL`, `_lkOtpFn`, `lkTryBridge`,
  `lk_bridge_vjwt`, `lkLoginBox`, o `grep -r "/mayorista"` (no debe haber ninguno).

### Convenciones operativas

- El SW de Virgilio **no cachea** (`self.addEventListener("fetch", () => {})`
  es no-op), así que no colisiona con `/admin/`.
- El TWA de Play Store apunta a la raíz de Virgilio; el admin está dentro del
  `scope`, por eso lleva `robots noindex,nofollow`. No usarlo nunca como `start_url`.
- Los HTML del admin llevan hardcodeado un `?v=23176` heredado del repo LK
  (cache-busting). **No hay hook automático que lo bumpee** desde Virgilio. Si
  se toca un `.js` o `.css` del admin y se necesita invalidar cache, se
  hace a mano incrementando ese número — o el user hace `Ctrl+F5` (que es lo
  habitual).
- La anon key de LK vive en `admin/admin.js` (además de en `sw.js` y `index.html`
  del propio proyecto LK). Al rotar la anon key de LK, actualizarla también acá.

### Edge Function `admin-login-otp` (proyecto Supabase LK)

- Código fuente: `admin/supabase/admin-login-otp/index.ts`.
- Deployada manualmente desde el Dashboard de Supabase LK (verify_jwt=off).
- Reusa la tabla `admin_otp_codes` y los secrets `RESEND_API_KEY` / `RESEND_FROM`
  del vault, que ya usa la Edge Fn `admin-otp` (2FA del admin PPP).
- Destinatario **hardcodeado** a `loekemeyer.n8n@gmail.com`. El user está creado
  a mano en `auth.users` del proyecto LK y vinculado en `public.admins`.
- Si se cambia el destinatario o se agrega otro admin, editar `RECIPIENT_EMAIL`
  en la función Y re-deployar; crear el nuevo user en LK y agregarlo a `admins`.
- **Sensible: 73 chars rompen bcrypt.** El password temporal usa
  `crypto.randomUUID()` (36 chars). No concatenar dos UUIDs — pasa de 72 y falla.
- **NO usar `listUsers` para resolver el recipient.** LK tiene >1200 usuarios
  (clientes del sitio); el admin quedaba fuera de la primera página de 200 → 500
  en OTP y bridge. La función resuelve el `user_id` con la RPC
  `get_admin_login_user_id()` (SECURITY DEFINER, solo `service_role`; SQL en
  `admin/supabase/admin-login-otp/get_admin_login_user_id.sql`).
- **Acción `bridge` (v12.35):** entrada directa sin OTP desde Producción
  Virgilio. Recibe el `access_token` de la sesión del supervisor de Virgilio
  (`vjwt`), lo valida server-side contra el auth de Virgilio
  (`hrxfctzncixxqmpfhskv`, con la **clave publishable** de GV escrita en la función —
  ya no la anon legacy, v16.55, problema 19) y **sólo si el
  mail del token == `RECIPIENT_EMAIL`** (mismo dueño, no amplía acceso a nadie)
  devuelve el mismo password temporal que `verify`. Gate 100% en backend: el
  front no puede falsear identidad. Si mañana se quiere que otro supervisor
  entre, ampliar el chequeo de `vemail` en la función (y crear su user en LK).

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

## ⚠⚠ REGLA (Luis, 2026-09-23, v21.53): LA SUITE NO SE DEJA EN ROJO — el que rompe, arregla

**Luis:** *"que la suite en rojo avise sola"*. Lo primero que apareció al medirlo es que el
aviso **ya existía** —`.github/workflows/ci.yml` corre la suite entera en cada push a `main`—
y que no decía nada porque **los últimos 20 runs de `main` estaban en rojo**. El rojo dejó de
significar algo, que es exactamente lo que el propio `ci.yml` cuenta que ya había pasado una
vez: *"fallaba siempre… main quedaba en rojo permanente"*.

**Cómo se llegó ahí, y no fue nadie en particular:** varias sesiones pushearon diciendo, en el
mensaje del commit, *"Tests: fallan los 4 que ya fallaban antes"* o *"los que fallan… fallan
igual sin este cambio"*. Cada una tenía razón por separado; el resultado fue dos semanas de CI
inútil.

### Las tres cosas que ahora valen

1. **No se pushea a `main` con la suite en rojo.** Si un test se pone rojo por un cambio tuyo,
   se arregla en el mismo commit. Si ya estaba rojo, **se arregla igual o se dice por qué no**:
   el número del test, la causa y qué falta. *"Ya fallaba antes"* no es una razón para dejarlo.
2. **Un test viejo NO es un test roto, y se actualiza en el commit que lo deja viejo.** El 23/09
   había cuatro rojos y **ninguno era un bug de la app**: dos median cosas que el dueño mandó
   sacar (el Tablero de 6 días de la v21.38, el criterio de atrasado de la v21.37) y nadie los
   volvió a mirar. Al sacar una pantalla, `grep` por su nombre en `tests/`.
3. **Un test que falla 1 de cada 3 es tan malo como uno roto.** Los otros dos rojos eran
   **carreras**: pasaban 5 de 5 en una máquina libre y fallaban con otro Chromium al lado — o
   sea, fallaban en CI, que es más lento. Un intermitente entrena a todos a ignorar el rojo.
   Se arreglan como los demás: esperar al `load`, reintentar el click, subir el timeout.

### Cómo se mira, ahora que `run.sh` no corta

**`tests/run.sh` corre TODO y lista los rojos al final** (v21.53). Antes tenía `set -e` y
cortaba en el primero: por eso nadie sabía el tamaño del problema — local cortaba en el test
124 de 217 y CI, con ése ya arreglado, cortaba en el siguiente. Hicieron falta cuatro vueltas
para descubrir que los rojos eran cuatro.

```bash
bash tests/run.sh          # al final: "SUITE VERDE — 219 corridas, 0 rojos" o la lista
```

⚠⚠ **Y un test que no está en `run.sh` no lo corre NADIE** (v21.77). Al medirlo el 23/09, la
suite listaba **218 de los 274 archivos** de `tests/`: el **20 % nunca se ejecutaba**, y entre
ellos había centinelas —`encoding-utf8`, `regla-L`, `fcs-codigo-l`, `rr-sin-remitos-cierra`,
`comp-armado-anulado`, `stock-refresh-si-cambio`—. Se corrieron los 56 uno por uno y **53
pasaban**: entraron todos. Hoy `run.sh` lista **271 de 274**.

> **Escribir el test no alcanza: hay que agregarlo a `run.sh`.** No se descubren solos, y el
> archivo suelto en `tests/` da la sensación de estar cubierto sin estarlo.

✅ **Los 3 que faltaban ya entraron (v21.78)**, y ninguno era un bug de la app — los tres
medían algo que dejó de ser cierto:

| test | por qué fallaba |
|---|---|
| `oc-auto-ciclo` | exigía **3 atajos** de fecha en el diálogo y los **miércoles son 2**: `_ocAutoOpciones` agrega "El próximo miércoles" **sólo si no cae en la misma fecha** que "En 7 días", y un miércoles cae. Fallaba **1 de cada 7 días** |
| `ppp-reprog-boton` | le faltaba el mock de **`gv_ppp_atrasados`** desde la v21.37: la solapa de vencidos salía con "0 pedidos" y el cartel rojo nunca se dibujaba |
| `stk-buscar-cero-adelante` | medía la regla de la v18.20/18.25 (*"31" encuentra el 031*), que **la v21.09 derogó** (*"si busco 30 aparece el 030 y es un error"*) |

⚠ **Un test que falla un día de la semana es peor que uno roto**: pasa 6 de 7 y entrena a todos
a ignorar el rojo. Se arregla midiendo **la regla** (están los dos atajos fijos; el del miércoles
sólo cuando aporta una fecha nueva), no la cantidad.

⚠ **Y el mock nuevo va ADENTRO del `if (m)` que resuelve las `/rpc/`**, no debajo: toda RPC
entra por ahí y sale por su `ok([])`, así que una condición puesta más abajo no se alcanza
nunca. Pasó en el primer intento y el test siguió en rojo sin decir por qué.

⚠ **Al editar `run.sh` por script, ojo con `\n_resumen`:** matchea la **definición** de la
función además del llamado del final. El primer intento insertó el bloque dos veces y el
archivo quedó con 53 tests duplicados. Va con `rindex`, y después se cuenta:
`grep -oE "node tests/[A-Za-z0-9._-]+\.cjs" tests/run.sh | sort | uniq -d` tiene que dar vacío.

### ⚠ Un test verde no dice que el test SIRVA — para eso está la prueba de MUTACIÓN

**Luis, 23/09: *"revisá otros tests"*.** Un test verde dice que hoy no se rompió, no que
muerda. La única forma de saberlo es **romper el código a propósito y ver si se entera**:
`node tests/tools/mutar.cjs` (catálogo de **11** mutaciones al 23/09, cada una con los tests que
TIENEN que ponerse rojos; las 11 las caza su test). **No va en `run.sh`**: muta archivos y tarda.

⚠ **Desde la v21.84 una mutación puede vivir en OTRO archivo**, no sólo en `index.html`: la
entrada lleva `archivo: "admin/admin-supercot.js"` y el `finally` restaura **todos** los que
tocó. Hacía falta porque la regla de la **L** (v21.09) no está en el index: vive en el espejo
del panel de LK, que se sirve por Pages igual que todo lo demás.

⚠⚠ **Mientras `mutar.cjs` corre NO se toca el árbol de git.** Restaura desde la copia que leyó
al arrancar, así que un `git stash` / `git pull` en el medio le deja **la mutación escrita
encima** de lo que acabás de traer — y el script igual dice *"restaurado ✓"*, porque para él
quedó como lo encontró. Pasó el 23/09: quedó `_pgaObsGrupoBadge(){return '';}` en `index.html`.
La señal es un `git status` con el index modificado sin que lo hayas editado; se arregla con
`git checkout -- index.html`.

**Lo que dio el barrido del 23/09 sobre los 274 tests:**

| se buscó | resultado |
|---|---|
| mocks de RPC inalcanzables (el pozo de la v21.78) | **0** · los 3 candidatos eran vistas o aserciones |
| tests sin un solo assert | **0** · los 40 marcados salen con `process.exit(cond ? 1 : 0)` |
| el regex `[^"']*` sobre un `onclick` (pozo v20.80) | **0** |
| 8 mutaciones dirigidas | **las 8 las caza su test** |

⚠ **Una mutación que no rompe a nadie NO siempre es un test flojo: puede ser INOCUA.** Pasó
con `items.concat(excSteps)` del picking — el orden lo da el **sector**, y la concatenación
sólo decide el **desempate a igual orden**, así que `pk-excedente-orden` tenía razón en no
moverse. **Antes de acusar a un test, mirar si la mutación cambia algo de verdad.** Ese caso
igual sirvió: el desempate no se probaba corriendo (sólo un candado de texto en
`pk-deposito-pkc`) y se le agregó el chequeo **D** a `pk-excedente-orden`.

⚠ **Y dos que siguen verdes con razón, para no volver a marcarlos:** `stk-buscar-cero` mide
el filtro de ceros, no el prefijo; y **`regla-L.cjs` no mira el código** — es un candado sobre
el `CLAUDE.md`, para que el bloque de la L no se borre. La regla **en el código** la sostiene
`fcs-codigo-l`, que sí se entera.

⚠ **La heurística estática sola no alcanza**, y quedó medido: buscar "claves que nadie lee"
marcó **114 tests** y eran casi todos ruido (leen el objeto entero con
`Object.values(r).every(Boolean)` o destructuring). Mutar mide; grepear supone.

⚠ **El veredicto que vale es el de CI, no el local.** El runner de GitHub es más lento y ahí
aparecen las carreras que la máquina de desarrollo no muestra. Después de pushear, mirar el run:
`mcp__github__actions_list` con `ci.yml`, o Actions → *CI — smoke tests*.

⚠ **Y CI avisa solo desde la v21.53**: cuando la suite se pone roja **abre un issue** con el
commit y los tests que fallaron, y lo **cierra solo** cuando vuelve a verde. No hace falta
configurar nada (usa el `GITHUB_TOKEN` del propio workflow). Si el issue está abierto, la suite
está rota **ahora**; no hay que entrar a Actions a mirar.

⚠⚠ **Y en `main` los runs NO se cancelan entre sí** (v21.57). La v16.25 había puesto
`cancel-in-progress: true` para que un push nuevo matara al viejo, y con la suite corriendo
entera —8 a 12 min— contra sesiones que pushean cada 3 a 5, eso dejaba a **todos** los runs
muertos antes de terminar: el 23/09 los runs 1147 a 1150 se cancelaron uno atrás del otro y
**ninguno dio veredicto**. Un CI que nunca termina no avisa nada. El motivo original —"corridas
peleando por el runner"— no aplica: el repo es **público**, o sea Actions gratis y 20 jobs
concurrentes. En los PR se sigue cancelando.

⚠ **Sin cancelación los runs terminan DESORDENADOS**, y un run viejo que cierra el issue que
abrió uno nuevo diría "está verde" con `main` en rojo. Por eso el paso del aviso **compara su
`context.sha` contra el head de `main`** y, si main ya avanzó, no toca el issue: ese run habla
de un commit que ya no es el estado de hoy.

## Git

- **Trabajar SIEMPRE directo en `main`**: commitear y pushear ahí sin preguntar.
  **NUNCA crear ni usar ramas** (ni feature branches, ni ramas de Claude).
  Todo va a `main` directo. Si la plataforma crea una rama automáticamente,
  mergear a `main` de inmediato y trabajar desde ahí.
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

## ⚠⚠ `trg_normalizar_empresa_stock()` LA TOCAN VARIAS SESIONES — traer la viva antes de tocarla

**Problema 390, 17/09.** Dos sesiones de Claude editaron esa función el mismo día. La segunda
hizo `CREATE OR REPLACE` **partiendo de una copia anterior** a la regla de la v19.26, y la borró
sin que nada avisara. Costó **4 tandas con el picking duplicado** (D72A 228 filas, E11B 24, D72C
y 98648|CP 2 cada una), con **+287 cajas fantasma en Pickeados y −265 en góndola**.

**Por qué el índice único no lo frenó:** `mov_stock_pipeline_dedup` incluye
`COALESCE(empresa,'')`. Con la regla vieja (por NP) **D72A se etiquetó CH** —se factura por Chef,
NP 44609— mientras el picking original del 14/09 estaba en **LK**, porque sus 38 artículos son de
Loekemeyer. Distinta empresa = distinta fila para el `ON CONFLICT` = duplicado.

**Antes de hacerle un `CREATE OR REPLACE` a esa función** (o a cualquiera del stock):

```sql
-- 1. traer la definicion VIVA y agregarle el cambio ENCIMA. Nunca partir de una copia propia.
select pg_get_functiondef('public.trg_normalizar_empresa_stock()'::regprocedure);
-- 2. despues, probar con un INSERT de verdad (leer la funcion no alcanza):
insert into public."Movimientos_Stock" (cod_art, deposito, delta, tipo, ref, legajo, empresa)
values ('501','separar_pedidos',0,'ajuste','__PRUEBA__','t','CH');   -- tiene que quedar LK
delete from public."Movimientos_Stock" where ref = '__PRUEBA__';
-- 3. y el centinela, que tiene que dar TRUE:
select p.prosrc ~ 'gv_empresa_de_articulo' as tiene_la_regla_del_articulo
  from pg_proc p join pg_trigger t on t.tgfoid = p.oid where t.tgname = 'zz_normalizar_empresa';
```

**Las tres reglas que tienen que convivir en esa función, y ninguna puede pisar a la otra:**

| regla | qué hace |
|---|---|
| **v19.42** (problema 378) | un NPD sin picking en esa tanda → `RETURN NULL` (si no, deja Pickeados en negativo) |
| **v19.26** (Luis, 16/09) | código **NO dual** → manda el **ARTÍCULO**, no el pedido. Va **antes** de la herencia por tanda |
| **v18.99** | en un dual, la NP puede venir de los **dos lados** del pipe, con guard de largo 4-6 |

**Chequeo de que no volvió a pasar:** `select * from public.gv_stock_empresa_fantasma;` vacía, y
esta consulta en 0 — caza el duplicado que el índice único no ve, porque compara **sin** la empresa:

⚠ **Ese centinela cambió en la v19.77 (problema 416): ahora sólo marca el split de etiqueta de
verdad** (`fantasma = least(positivo, negativo)`). Antes disparaba con **cualquier** saldo
negativo de una sola empresa —donde no hay ninguna caja fantasma— y por eso vivía en rojo. Los
sobre-pickeos comunes van a **`gv_stock_negativos`**, que ya los lista con descripción.

⚠ **Y hay un tercer duplicado que ninguno de los dos veía**, porque el `ref` es **otro**: el que
deja el renombre de tanda. `select * from public.gv_stock_picking_duplicado;` — vacía = todo
bien. El 18/09 marcó 4 tandas (D71B/E40A, E03F/E12R, E11B/E41A, E03G/E44A): **+461 cajas en
Pickeados, −443 en góndola**. Causa: `gv_ppp_tanda_renombrar` no renombra los eventos **PKC**
(la tanda va en el campo 1 y `gv_evento_tanda` devuelve NULL) ni los `ref` con pipe
(`tanda|NP`, `NP|CP`), así que el cron 68 vuelve a insertar el picking con el código viejo.
§3.jj, problemas 417, 420 y 421.

⚠ **Y un CUARTO, que es el que ve el agujero en vez del duplicado:**
`select * from public.gv_stock_tanda_pickeado_negativo;` — vacía = todo bien. Marca la tanda
cuyo **Pickeados quedó negativo**, con el motivo: *"armada sin picking propio"* (pickeado 0 y el
armado igual drenó — la firma del renombre), *"drenaje mayor que el picking"*, o —desde la
v20.32— *"el picking cierra: lo negativo lo dejó un ajuste manual"*.

⚠ **Y cuenta los ajustes que nombran la tanda en TEXTO LIBRE, no sólo los que traen el código
pelado de `ref`** (v20.32, problema 459). Un ajuste manual se anota con `ref = 'D53A'`, pero su
**reversión** se anota con texto (`ajuste manual | Revierte ajuste D53A: …`): contando uno y no el
otro, D53A vivía en rojo con el depósito sano, y los negativos de D20E y E10A no los veía nadie.
El código que sale del texto libre **se valida contra `GV_Tandas_Codigos_Usados`**, o el regex
inventa tandas.

**Va POR TANDA a propósito.** `gv_stock_negativos` agrega por código sin mirar la tanda, así que
el saldo positivo de otra tanda **tapa el agujero**: el 18/09 el hueco de E12K eran **34 códigos
/ 46 cajas** y en pantalla se veían **7**. Y a medida que se armaban otras tandas se consumía ese
colchón y aparecían códigos nuevos en rojo sin que se hubiera roto nada — el cartel prendía y
apagaba solo. Por tanda el número es estable y dice **dónde**.
`sql/gv_stock_tanda_pickeado_negativo_v2032.sql`, §3.kd y §3.kr.

```sql
select count(*) from (
  select 1 from public."Movimientos_Stock" where tipo in ('picking','separado','facturado')
   group by upper(btrim(ref)), upper(btrim(cod_art)), deposito, tipo
  having count(*) > 1 and count(distinct coalesce(empresa,'')) > 1) z;
```

## ⚠ REGLA: el `ref` del pipeline de stock NO se renombra a ciegas — se FUSIONA

**2026-09-18, problema 407.** Mover la tanda **E12A** (pickeada y armada) al lunes 21/09 desde
«📅 Cambiar de día» devolvía el error crudo de Postgres:

```
duplicate key value violates unique constraint "mov_stock_pipeline_dedup"
```

`gv_ppp_tanda_renombrar` hacía `update "Movimientos_Stock" set ref = <tanda nueva>` **a ciegas**, y
ese índice es **único** por `(ref, cod_art, empresa, deposito, tipo)` para
`picking/separado/facturado` — es el guard que impide el doble picking (problema 390). Si la tanda
destino ya tiene el mismo artículo pickeado, choca: **fusionar dos tandas armadas era imposible**,
aunque la pantalla lo ofrezca. Medido: E12A chocaba con 126 filas de E12E, 120 de E12F, 84 de E12K.

**Lo que corresponde es sumar los `delta`, y no es una licencia:** ese `delta` es el total pickeado
de la tanda para ese artículo y lo escribe `reconciliar_stock_articulo_rt` desde los eventos PKC;
como los eventos también se renombran, el reconciliador va a recalcularlo como la suma de las dos.
El saldo del depósito no se mueve ni una caja (medido: 0 saldos cambiados).

⚠ **Primero el DELETE de la fila vieja, después el UPDATE que suma.**
`trigger_actualizar_saldo_stock` recalcula el saldo del código desde cero pero corre
**AFTER INSERT OR UPDATE y NO en DELETE**: al revés, `stocks_carga_rapida` queda inflado.

⚠ **Y un código de tanda está TOMADO si tiene stock, aunque no figure en ninguna programación.**
`gv_ppp_web_codigo_tomado` sólo miraba las programaciones, así que «➕ Tanda nueva» podía reciclar
un código con movimientos viejos (353 al 18/09, más E01G de la serie viva). Ahora mira también
`Movimientos_Stock` — escrito como `upper(btrim(m.ref))`, **sin `coalesce`**, o no entra por el
índice y pasa de 0,1 ms a 49 ms de seq scan en un loop de hasta 400 vueltas.

**Chequeo:** `select * from public.gv_reglas_perdidas;` (las dos reglas tienen su centinela) y

```sql
select count(*) from (
  select 1 from public."Movimientos_Stock" where tipo in ('picking','separado','facturado')
   group by upper(btrim(ref)), upper(btrim(cod_art)), deposito, tipo
  having count(*) > 1 and count(distinct coalesce(empresa,'')) > 1) z;   -- 0
```

`sql/gv_ppp_tanda_fusion_stock_v1969.sql`, §3.jh.

## ⚠ REGLA: el guard del PEDIDO SUELTO no se le aplica a la TANDA ENTERA

**Luis, 2026-09-21 (v20.30, problema 458).** Son dos movimientos distintos y el sistema tiene que
tratarlos distinto:

| qué se mueve | ¿se puede si está pickeada? | por qué |
|---|---|---|
| **una NP sola**, a otra tanda | **NO** — `gv_np_mover_guard` la frena | las cajas viven en la pila de la TANDA: quedarían huérfanas (caso Martinelli, v20.01) |
| **la tanda entera**, a otro código o fusionada | **SÍ** | `gv_ppp_tanda_renombrar` se lleva el stock con ella y lo fusiona |
| **una NP sola cuya tanda YA SALIÓ SIN ELLA** y cuya pila cierra en cero | **SÍ** (v20.72) | no hay una sola caja que pueda quedar huérfana: lo pickeado ya drenó al facturarse y lo que queda es un bulto esperando el camión |

⚠⚠ **El tercer caso cierra un callejón que dejó un pedido 3 días parado** (v20.72, Thomas 21/09,
problema 472): `gv_ppp_tanda_mover` frena la tanda que salió en parte y **manda a mover la NP sola**,
y el guard frenaba exactamente eso con *"avisá a sistemas"*. Caso **LK 0027 (Albalandia)**: E03C
salió el 17/09 con 4 de sus 5 NP y el quinto quedó sin CCR, sin CCN y sin CRN. Lo resuelve
**`gv_np_mover_exento_salida(np, tanda)`**, con **tres** condiciones necesarias: la tanda ya salió ·
esta NP no · la pila cierra en cero. **Con saldo vivo sigue frenando** — ahí el motivo de la v20.01
vale igual.

⚠ **Al medir la pila de una tanda, contar los `ref` COMPUESTOS.** El drenaje del facturado se anota
como `<tanda>|<NP>` (`E03C|LK 0027`): filtrando `ref = 'E03C'` a secas da **+182** y parece que hay
stock vivo cuando cierra en cero. Van los tres: `= <tanda>`, `<tanda>|%` y `%|<tanda>`.

**Y el caso se ve solo**, que es lo que faltaba — Albalandia no aparecía en ninguna pantalla:
`select * from public.gv_pedido_quedo_sin_salir;` — vacía = ningún bulto quedó atrás; dice hace
cuántos días salió el resto y si se puede reprogramar sin tocar el stock. §3.lq.

Hasta la v20.30 el guard se disparaba en los dos casos, así que **"📅 Cambiar de día" con código
nuevo o fusión estaba bloqueado en 10 de las 12 tandas vivas** —incluida D69H, la que el centinela
de camión mezclado marcaba para que la arreglara Marianela— con el cartel *"avisá a sistemas"*.
Cambiar el día **sin** tocar el código sí andaba, y por eso no saltaba siempre.

Lo resuelve `p_tanda_entera`, que viaja `gv_ppp_tanda_mover` → `gv_ppp_nps_mover_a` → el guard y
exime **sólo las NP de esa tanda**: una NP de otra tanda pickeada se sigue frenando.

⚠ **No es un `p_forzar` ni un "saltear el guard".** Si aparece la tentación de agregar un booleano
que lo apague, es la señal de que se está por reabrir el pozo de las 92 cajas huérfanas.

**Chequeo** (las cuatro reglas tienen centinela): `select * from public.gv_reglas_perdidas;` —
vacía = todo bien. `sql/gv_mover_tanda_entera_v2030.sql`, §3.kq.

## ⚠⚠ REGLA (Luis, 2026-09-22, v21.10): el REGISTRO DEL ARMADO viaja con el pedido

**Luis, textual:** *"Pedido ARMADO tiene que tener el dato. Pedido que todavía no armaron, no
importa. Pedido en proceso ponemos que no se pueda mover hasta que terminen de armarlo o lo
cancelen y listo"*.

`TP` y `TAP` son eventos de la **TANDA** (`texto = 'E29A'`, sin NP) y la pila de stock va toda
con `ref = <tanda>`: medido sobre E29A, sus seis filas (picking / separado / facturado) van con
`ref = tanda` y **ninguna tiene NP**. Renombrar no es opción — la tanda vieja sigue viva con los
otros pedidos adentro. Por eso la tanda nueva nacía **sin registro de producción y sin cajas**: el
monitor la mostraba pendiente y el depósito re-pickeaba mercadería que ya estaba en un pallet
(E29A, 88 cajas el 21/09).

| estado del pedido | qué hace al moverlo |
|---|---|
| **sin empezar** | tanda nueva y listo: no hay nada que llevar |
| **en proceso** (pickeado, sin terminar de armar) | **NO SE MUEVE.** Sus cajas están en la pila de la tanda **sin separar por pedido** — eso recién pasa en el armado. Se termina de armar o se cancela |
| **armado** | se mueve **con su registro**: `TP` + `TAP` copiados, sus filas de `Entregas_Virgilio`, y su porción de `a_facturar` |

**Medido en transacción abortada sobre E29C** (6 NP, 176 cajas): LK 0101 → E75A ·
`a_facturar` 176 → 104 + 72 en la nueva = **176** · **el total global no se movió** (615 → 615) ·
2 eventos en la nueva · `gv_stock_tanda_pickeado_negativo` = 0.

⚠ **Después del armado `separar_pedidos` cierra en CERO**: las cajas están en **`a_facturar`**.
Ahí es donde vive la porción que viaja, no en la pila de picking.

⚠ **NO se copian los PKC.** Medido: copiarlos dispara `reconciliar_stock_articulo_rt` y
**re-pickea** (góndola −85 → −194, `separar_pedidos` 0 → +106). Por lo mismo, la porción viaja
como **`ajuste`**: las filas `picking` las reescribe la etapa 1 desde los PKC y las `separado` las
reescribe la etapa 2, así que un split ahí **se deshace solo**.

⚠ **La etapa 2 se silencia durante el movimiento** (`gv.sin_reconciliar`, local a la
transacción). El trigger corre AFTER STATEMENT, o sea que ve los estados intermedios, y
`reconciliar_pipeline_stock_etapa2` reparte contra `Entregas_Virgilio`: moviendo las Entregas
antes del stock manda la diferencia a **`terminado`** (cajas fantasma en góndola), y moviendo el
stock antes de las Entregas manda **todo** a góndola. Se hacen las tres cosas y se reconcilia
**una** vez al final.

⚠ **El guard de la v20.01 deja pasar el armado sólo cuando el llamador declara que el registro
viaja** (`gv.pedido_lleva_registro`). Llamado directo, sin esa señal, sigue frenando — verificado.
Y las copias van con `ts_inicio = ts_cliente`, **duración cero**: el trabajo ya se contó en la
tanda vieja.

⚠ **Al parchear una función por texto, los saltos de línea van con `chr(10)`.** El guard del
EN PROCESO se aplicó la primera vez con `\n` dentro de comillas simples —barra-n literal— así que
**quedó comentado entero** en una sola línea. El `CREATE` salió limpio y la función corrió igual.
Lo cazó la prueba, no la lectura.

**El supervisor ve el AVISO**: *"⚠⚠ ROTULAR: este pedido ya estaba armado y sale con CÓDIGO NUEVO.
El pallet tiene el papel de E29C y ahora es E75A. Cambiarle el rótulo ANTES de cargarlo. NO hay que
volver a pickearlo ni armarlo: el picking y el armado ya viajaron."*

### ⚠ De dónde heredó el registro una tanda: `gv_tanda_registro_heredado` (v21.16, Luis)

**Luis, al leer que los PKC no viajan:** *"tiene que quedar el registro de que se pickeó (que se
levantó de la góndola ya), correcto?"*. Sí, y es el **TP**, con la fecha y el legajo reales del
picking original — no se inventa que se pickeó hoy. El candado anti doble-armado
(`opcion in (TP,PKC)`), el monitor y la lista de picking lo ven, así que **nadie la vuelve a
mandar a pickear**: es lo que falló con E29A y sus 88 cajas.

Lo que queda en la tanda vieja es el **detalle por artículo** (los PKC: *"501 · esperadas 7 ·
reales 7"*). Ése es el renglón del libro de góndola, y las cajas salieron una sola vez, de ahí.

El rastro del traspaso siempre se escribió —en el `client_id` de los eventos copiados
(`mv_<nueva>_<TP|TAP>_<vieja>`) y en el `ref` de los ajustes (`<nueva>|MOV-<vieja>`)— pero
**enterrado**: ninguna pantalla lo mostraba. La vista lo saca a la superficie, una fila por
(tanda que recibió, tanda de origen):

```sql
select tanda, vino_de, np_lista, cajas_movidas, pickeado_el, pickeado_por,
       pkc_propios, pkc_en_origen, donde_esta_el_detalle
  from public.gv_tanda_registro_heredado;
```

Medido sobre el movimiento de prueba LK 0101/0102 · E29C → E75A: **72 cajas · 17 códigos ·
pickeado el 21/09 14:12 por el legajo 104 · pkc_propios 0 · pkc_en_origen 60**, y la columna que
contesta la pregunta: *"el detalle del picking (60 códigos) está en E29C — acá NO se volvió a
levantar de la góndola"*.

⚠ **No persiste nada**: se calcula al leer, de los rastros que el movimiento ya escribe. Si
cambia el formato del `client_id` o del `ref`, cambia acá y en ningún otro lado.

⚠ **`full outer join` entre los eventos y el stock a propósito**: puede haber eventos sin cajas
(un pedido con 0 entregadas) y cajas sin eventos (la tanda nueva ya tenía TP/TAP propios y el
`not exists` de la función no los volvió a copiar).

⚠ Medido con `set local role anon` y `authenticated`: las tres identidades ven la fila (es la
trampa de la v20.45 — una vista con `security_invoker` sobre una tabla con RLS **no da error, da
menos filas**). Su fila de centinela vigila el patrón `pkc_en_origen`.

**Chequeo:** `select * from public.gv_reglas_perdidas;` — vacía = todo bien.
`sql/gv_pedido_mover_registro_v2105.sql`, `sql/gv_tanda_registro_heredado_v2116.sql`.

⚠ **EL FRENO GENERAL SIGUE PUESTO** (`PPP_Web_Config.np_mover_frenado = 1`), **pero desde la
v21.60 frena SÓLO la NP cuya tanda tiene picking o armado** (Luis, 23/09: *"sacá la traba de mover
NPs individuales sólo para las que están pendientes sin nada armado"*). Una NP **pendiente** se
mueve sola con «📅 Cambiar de día» → tanda nueva o existente. Primer caso: LK 0156 (Matiz) E74A →
E78A. Se levanta del todo con `update public."PPP_Web_Config" set valor = 0 where clave =
'np_mover_frenado';`. Centinela en `GV_Reglas_Centinela`. `sql/gv_np_mover_pendiente_v2160.sql`.
## ⚠ REGLA (Thomas, 2026-09-22, v21.06): el refresco del stock se hace SOLO si algo cambió

Cron 55 refrescaba `vista_stock_procesada` **cada 2 minutos, siempre**: **1.770 s sobre una
ventana de 26,4 h = 7,4 % del tiempo total de la base**, para una matview de **367 filas /
216 kB**. Y sobre 7 días, sólo **277 de los 5.040 bloques** de 2 minutos tuvieron movimiento de
stock: el **94,5 % de los refrescos no cambiaba una sola fila**. Esa contención es la que daba
los `canceling statement due to statement timeout` de la Cuarentena (problema 492).

Hoy el cron llama a **`gv_refresh_stock_si_cambio()`**. Medido en vivo: **refresco 1.813 ms ·
chequeo que salta 12 ms (150×)**.

⚠⚠ **Y con esa primera versión el ahorro fue del 1,2 %, no del 94,5 % (v21.31).** La huella
contaba **escrituras**, y hay crons que reescriben tablas enteras sin cambiar nada: el **cron 81
`gv-reconciliar-aguardar` corre cada 2 minutos** —el mismo minuto que el 55— y toca
`Movimientos_Stock`. Medido: `PPP_Web_Base` 582.748 updates contra 372 inserts, `GV_UxB` 34.036
contra 0. El riesgo estaba escrito acá mismo como caso raro; **es el caso normal de esta base**,
y la medición de 5 minutos que lo dio por bueno cayó justo entre dos corridas del cron. Hoy las
5 tablas ruidosas llevan **firma de CONTENIDO** (`GV_Stock_Huella_Expr`, que es un `insert`, no
código): 60-74 ms de huella y **0 refrescos / 3 saltos = 100 % ahorrado** con el cron 81
corriendo en el medio. §3.mj.

⚠ **La frescura NO empeora.** El chequeo sigue corriendo cada 2 minutos: apenas se escribe un
movimiento, el refresco sale en la corrida siguiente. Lo único que se saca es el refresco que
no cambiaba nada.

⚠ **El árbol de dependencias se camina EN VIVO, no es una lista a mano.** La matview cuelga de
**23 tablas y 5 vistas**; se resuelve con `pg_rewrite`/`pg_depend`, así que una tabla nueva entra
sola (verificado 23 de 23, 11 ms). Una lista escrita a mano es el mismo pozo de los pases que
eligen fecha (v20.83), el `ref` compuesto (v20.72) y las 18 tablas del renombre (v20.88):
**siempre falta una**.

⚠ **La matview se excluye de su propia huella**, o su refresco cambiaría la huella y se
refrescaría para siempre. Y la comparación que manda es el **jsonb entero**, no clave por clave:
así una tabla que entra o sale del árbol también cuenta.

⚠ **FAIL-OPEN, al revés del guard de cuarentena (v20.95):** sin huella, se refresca. Un refresco
de más cuesta 2 s; una vista de stock vieja la mira un operario y le miente. Más el **piso de
frescura** (60 min).

⚠ **La huella cuenta ESCRITURAS, no contenido** (`pg_stat_user_tables`). Un `delete`+`insert`
con contenido idéntico dispara un refresco al pedo, y un reset de estadísticas fuerza uno: las
dos fallan hacia refrescar de más, nunca de menos.

⚠⚠ **Y lo que el stock gasta de verdad NO es esto.** Medido el 22/09: `vista_saldos_stock` se
lee **directo desde la app en 5 lugares** de `index.html` — **1.759 llamadas, 2.850 s**, contra
los **1.808 s** del refresco. Pedir **un solo código** (`clave=eq.438E`) cuesta lo mismo que
pedir todos (**769 ms**): `clave` es una expresión calculada, así que no hay índice que valga y
recorre las 67.242 filas y las ordena para devolver 0 (`Rows Removed by Filter: 496`). El
arreglo **NO es una columna nueva**: `clave` no existe en la tabla, pero `ckey` —la
normalización del código— es función pura de `cod_art` con funciones inmutables, así que alcanza
un **índice de EXPRESIÓN** (`mov_stock_ckey_idx`, 496 kB): sin columna, sin trigger, sin backfill
y sin reescribir una fila. Y como el índice sólo sirve si alguien filtra por esa expresión, va con
**`gv_saldos_por_clave(text[])`**: **687 ms → 7 ms** para un código, 69 ms para diez, con salida
verificada idéntica (496 = 496 filas, `EXCEPT ALL` 0 en las dos direcciones). v21.31, §3.mj.

⚠ **`work_mem` NO es el arreglo, se midió y se descartó.** Con 4 MB el orden se cae a disco
(`external merge Disk: 3.304 kB`); con 32 MB entra en memoria y el I/O temporal se va a 0 — pero
la consulta pasa de **769 ms a 751 ms**. Los 750 ms son el recorrido y el regex por fila, no el
orden. No volver a proponerlo para esto.

### ⚠⚠ Y `vista_stock_procesada` NO puede reemplazar a `vista_saldos_stock` (medido 23/09)

La tentación es obvia — la matview ya está calculada y las lecturas del universo entero de
`vista_saldos_stock` son hoy el mayor consumidor del stock: **cuatro formas de consulta, 3.524 s
sobre una ventana de 47,9 h = 2,0 % del tiempo de la base** (`stockFetchSaldos` 1.902 llamadas,
`_pppChkFetchSaldos` 254). **No se puede, y el número lo cierra:**

| | |
|---|---:|
| filas de `vista_saldos_stock` | 496 |
| filas de `vista_stock_procesada` | 367 |
| códigos que la matview NO tiene | **152** |
| …de esos, **con stock real** | **119** |
| …de esos, **insumos** | **101** |
| cajas de `terminado` que se perderían | **2.266** |

En las 344 filas comunes los números coinciden (**0 difieren**), así que la matview *parece*
equivalente mirando cualquier código de góndola. Y los módulos que llaman a `stockFetchSaldos`
son justamente MG, bajar racks, **insumos** y salida Cervantes. Sería el pozo de la v20.95:
**una fila que no sale no se distingue de un código que no existe.**

⚠⚠ **Y TAMPOCO se cachea `vista_saldos_stock` en una matview propia. RETIRADO**: lo propuse
el 23/09 y Thomas lo bajo el mismo dia — ***"todo el stock tiene que verse lo mas en vivo posible
siempre"***. Esa vista se recalcula en cada lectura a proposito (765 ms, 67.945 movimientos), y
`gv_saldos_por_clave` tampoco cachea nada: el indice acelera el recorrido, no lo evita. **El stock
no se cachea.** Si el 2,0 % molesta algún día, el camino es bajar CUÁNTO recorre (la idea de los
últimos 2 meses con el histórico por código a demanda), no congelarlo.

⚠ **El picking NO se repunta a `gv_saldos_por_clave`**, y no es olvido: son **44 llamadas y 35 s
sobre esos 3.524 s (1 %)**, contra tocar el camino caliente del operario. Lo sostiene el candado
invertido de `tests/stock-clave-indexada.cjs`.

⚠ **El `count=exact` que todavía aparece en `pg_stat_statements`** (887 llamadas pagando el doble:
1.925 ms contra 1.021 ms de la misma consulta sin él) **no está en el código**: lo sacó la v20.78.
Son celulares con el `index.html` viejo cacheado. Se muere solo; no hay nada que arreglar.

### ⚠ Cron 81 `gv-reconciliar-aguardar`: reescribe lo mismo cada 2 minutos, y se deja así

Su `on conflict … do update set delta = excluded.delta, legajo = excluded.legajo` **no tiene
`where`**, así que reescribe sus 10 filas cada corrida cambie o no el valor: 1.438 corridas /
278 s / 194 ms de media (peor 13.271 ms), y `Movimientos_Stock` con **10.719 updates contra 2.853
inserts, 11.847 tuplas muertas y `last_autovacuum` en null**.

**Era la causa de que la primera huella (por escrituras) ahorrara 1,2 % en vez de 94,5 %.** Con la
huella por CONTENIDO eso ya no importa, y **Thomas decidió el 23/09 dejar el cron 55 y el 81 como
están**. Lo que queda es el churn del libro de stock, que no molesta a nadie hoy. Si algún día se
toca, el arreglo es una línea (`where … is distinct from …`) — y toca una función que escribe en
`Movimientos_Stock`, o sea que lo autoriza el dueño.

### ⚠⚠ REGLA (Thomas, 2026-09-23, v21.48): la pantalla de Stocks NO lee la matview — lee `stocks_carga_rapida`

**Thomas, textual:** *"todo el stock tiene que verse lo mas en vivo posible siempre"*.

Al medirlo apareció que esa regla **no se estaba cumpliendo, y no por el cron 55**. El dato llega
a la pantalla por **tres saltos**, no uno:

| salto | quién | cada |
|---|---|---|
| `Movimientos_Stock` | el libro | **en vivo** |
| → `vista_stock_procesada` | cron 55 | 2 min, y sólo si cambió |
| → **`stocks_carga_rapida`** | **cron 57** | **5 min, siempre** |
| → pantalla Stocks | `supaFetchAllSafe` | al abrir |

**Atraso máximo: 7 minutos**, y los dos crons no están sincronizados — si el 57 corre justo antes
de que el 55 refresque, se pagan los 7 completos. Los 2 min del 55 eran el salto chico.

Desde la v21.48 **`gv_refresh_stock_si_cambio` reescribe `stocks_carga_rapida` en la MISMA corrida
en que refresca la matview**: la frescura baja a **2 min** y de paso el cron 57 deja de reescribirla
cuando no cambió nada (eran 580 corridas / 324 s / 559 ms por ventana de 47,9 h, con el mismo
94,5 % de corridas inútiles que ya se le había sacado al 55).

⚠ **El lock va con `pg_try_advisory_xact_lock`, NUNCA con el bloqueante.** El advisory **5768** lo
toman **TRES** jobs — el **57**, el **68** (`reconciliar-pipeline-stock`) y el **92**
(`gv-refrescar-articulo-empresa`, `*/15`) —: esperarlo ocuparía uno de los **SEIS** worker slots de
la instancia (`max_worker_processes = 6`, medido). Si no se consigue, no pasa nada — lo reescribe
el 57.

### ⚠⚠ Y ahí había una CARRERA: el 57 le ganaba el lock al 55 y leía la matview VIEJA (v21.57)

**Thomas, textual:** *"fijate que el 57 no lo este pisando"*. No lo estaba pisando siempre, pero
podía — y el registro lo muestra. Los tres arrancaban **en el mismo segundo**:

| minuto | cron 55 | cron 57 | cron 68 |
|---|---|---|---|
| **08:50** | 00.327 · **4.156 ms** | 00.343 · 1.175 ms | 00.389 · **6.529 ms** |
| 08:30 | 00.620 · 4.264 ms | 00.628 · 1.216 ms | 00.748 |
| 08:00 | 00.929 · 1.187 ms | 00.870 · **2.625 ms** | 01.102 |

`*/2` y `*/5` coinciden en los múltiplos de 10: **seis veces por hora**. En la corrida de las
**08:50** el 68 se quedó el lock 6,5 s y el 55 terminó su refresco a los 4,1 s: **no pudo
encadenar**. Cuando gana el 57, además, escribe `stocks_carga_rapida` desde la matview **vieja**.

⚠ **Y no es teórico:** `cron.job_run_details` tiene un **`job startup timeout` del propio cron 68**
el 22/09 a las 10:30 — uno de los dos minutos más cargados. El pozo de los seis worker slots ya
estaba mordiendo acá, no sólo en LK.

**El arreglo no toca la función: los desfasa.** El 55 corre **sólo en minutos PARES**, así que los
otros van a **IMPARES** y la carrera desaparece (el 55 dura 4,3 s en su peor caso: no cruza el
minuto).

| job | antes | ahora | minutos |
|---|---|---|---|
| 57 `refresh_stocks_carga_rapida` | `*/5` | **`3-59/6`** | 3,9,15,21,27,33,39,45,51,57 |
| 68 `reconciliar-pipeline-stock` | `*/10` | **`1-59/10`** | 1,11,21,31,41,51 |

> ⚠ **Cada 6 y cada 10, NO cada 5 ni cada 15.** La paridad se conserva sólo si el paso es PAR:
> `*/5` y `*/15` alternan par/impar por construcción, así que **un cron cada 5 o cada 15 minutos
> no puede quedar siempre impar**. Por eso el 57 pasó de 5 a 6 minutos, y por eso **el 92 no se
> movió**: sigue pisando al 55 en :00 y :30.

**Medido**, minutos por hora en que el 55 se encuentra el lock ocupado: **6 → 2**
(55 vs 57: **0** · 55 vs 68: **0** · 55 vs 92: 2). Y el pico por minuto bajó: **:00 de 19 a 17
jobs**, :30 de 17 a 15.

⚠ El 57 y el 68 **siguen chocando entre sí** 2 veces por hora (:21 y :51) y es **inevitable**
(paso 6 y paso 10, mcm 30). No molesta: el lock los serializa y ninguno lee una matview a medio
refrescar, porque el 55 no corre en impares.

⚠ **Costo aceptado:** `fc_sin_salida` y las descripciones pasan de 5 a **6 min**.

**Rollback, dos líneas:**
```sql
select cron.alter_job(57, schedule := '*/5 * * * *');
select cron.alter_job(68, schedule := '*/10 * * * *');
```

⚠ **FAIL-OPEN, y con el fallo A LA VISTA.** Si la derivada explota, la matview se refresca igual y
el motivo lo dice. **Probado rompiéndola a propósito** (`perform 1/0`) en transacción abortada:
`refrescada=true | motivo=piso de frescura (60 min) (carga_rapida fallo: division by zero)`.
Un tapón sin forma de enterarse es cambiar un error ruidoso por uno mudo (regla de Elías, v20.58).

⚠ **El cron 57 NO se apaga**: es la red del lock ocupado y del fallo. Bajarlo a `*/10` sería un
segundo paso y **no está hecho**.

⚠ **Lo que NO arregla:** si querés el stock *realmente* en vivo en esa pantalla, hay que sacarle a
`stocks_carga_rapida` la dependencia de la matview, y eso se paga con latencia al abrir (~765 ms
contra los 55 ms de hoy). Es otra conversación.

**Verificado corriéndolo** (23/09): `solo_medir` → no encadena · piso de frescura en 0 →
`"... + carga_rapida"`, 3.260 ms · `stocks_carga_rapida` **idéntica antes y después**
(367 filas, md5 `3000430e5cfbde71e8b995819a3ce21e`): el encadenado adelanta el dato, no lo cambia.
`sql/gv_stock_carga_rapida_encadenada_v2148.sql`, `tests/stock-carga-rapida-encadenada.cjs`, §3.mo.

**Chequeo:**
```sql
select * from public.gv_stock_refresh_salud;              -- estado='ok' y pct_ahorrado
select * from public.gv_refresh_stock_si_cambio(60,true); -- qué HARÍA, sin refrescar
```

**Rollback, una línea:**
```sql
select cron.alter_job(55, command := 'REFRESH MATERIALIZED VIEW CONCURRENTLY vista_stock_procesada');
```

`sql/gv_refresh_stock_si_cambio_v2105.sql`, `tests/stock-refresh-si-cambio.cjs`, §3.mi.

## ⚠ REGLA: una lectura ROTA no es un CERO — y un centinela que sólo mira el log del éxito es ciego

**2026-09-18, problemas 402 y 403.** El armado automático de pedidos web estuvo **5 h 40 sin
correr** (17/09 18:20 → 18/09 00:01 ART) y las 30 y pico de corridas quedaron anotadas **en
verde**. Dos errores distintos, los dos del mismo tipo, y los dos hay que buscarlos en cualquier
cosa que lea de afuera:

**1. El `catch` que deja el número en 0 y sigue.** En `gv-ppp-web-tandas-diarias`, si el feed de
LK tiraba (la base de LK estaba ahogada y devolvía `57014`), el `catch` guardaba el error en
`detalle` y **`m3Auto` seguía valiendo 0**. Dos líneas más abajo, `m3Auto < umbral` entraba por
la rama *"no hay nada que armar"*, escribía `estado = 'intradia_sin_umbral'` con motivo
*"pendiente automático 0.000 m³"* y contestaba `ok: true` / HTTP 200.

> **Si no se pudo medir, el umbral no dice nada.** Un feed caído tiene que salir por la rama de
> error, no por la de "no había nada". Ojo con esto cada vez que un `catch` no corta el flujo:
> la variable que quedó en su valor inicial va a ser leída como un dato real más abajo.

**2. El centinela miraba el log equivocado.** `gv_ppp_web_armado_salud` leía sólo
`GV_PPP_Web_Armado_Log`, que escribe el armador **al final de su corrida**: si el armador nunca
se llama, no hay fila y el centinela no tiene nada que decir más que "SIN CORRER". Ahora cruza
con `GV_Tandas_Auto_Log`, que la Edge Function escribe **siempre**, corra o no el armador.

> **El log del paso que falló no está donde está el log del paso que anduvo.** Al armar un
> centinela, preguntarse *"¿qué fila existe cuando esto se rompe?"* — si la respuesta es
> "ninguna", el centinela está mirando el lugar equivocado.

Dos detalles de implementación que costaron y conviene no repetir:

- **Las dos empresas tienen que salir siempre** (lista fija `unnest(array['lk','chef'])` +
  `left join`). Si el centinela se arma desde el log, la empresa que nunca corrió no aparece: se
  queda mudo justo el día que todo está roto. Por lo mismo, el último intento se toma con
  `(array_agg(x order by ts desc))[1]` y **no** con `order by … limit 1`: un `cross join` contra
  una tabla vacía devuelve **cero filas**.
- **`create or replace view` sólo deja agregar columnas AL FINAL.** Meter una en el medio obliga
  a `DROP` + recrear todo lo que cuelgue (y a acordarse del `security_invoker`).

**Chequeo:** `select * from public.gv_ppp_web_armado_salud;` — `FEED CAIDO` / `SIN CORRER` son
para mirar; `sin nada que armar` y `fuera de horario` son sanos. §3.jf,
`sql/gv_armado_salud_feed_v1958.sql`.

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

## ⚠ REGLA (Luis, 2026-09-22, v21.03): un módulo que ABRE TOGGLE tiene que poder CERRARSE desde el caso VACÍO

**Luis, textual:** *"si uno aprieta recepción de remitos ahora, figura que no hay remitos para
recepcionar (correcto) pero después aprieta cerrar y queda marcado en rojo el módulo RR y no deja
comenzar picking/armado"*.

El toggle se abre en el **primer toque del botón**, y recién después se consulta la lista. Si la
lista viene vacía y el único botón del modal **minimiza** (`crClose` / `ccClose` / `ccrClose`: *"sigue
abierto, re-abrís tocando el botón"*), el toggle queda abierto — y con **cualquier** toggle abierto
`updateCoreButtonsState` deshabilita los `CORE_CODES`: **EP y AP trabados, sin salida dentro de la app.**

| módulo | el botón que cierra de verdad |
|---|---|
| CC · Carga Camión | `ccEndWithoutLoading` |
| CR · Control Remitos | `ccrEndWithout` |
| RR · Recepción Remitos | **`crEndWithout`** (faltaba hasta la v21.03) |

**Y son EXACTAMENTE esos tres** (medido el 22/09 sobre `selectOption`): el pozo no es de cualquier
toggle, es de los que **estando abiertos RE-ABREN su popup en vez de cerrarse**, así que la única
salida está adentro del modal. En `RT`, `RI`, `EI`, `AT`, `PB`, `Limp`, `PC`, `Perm` y `CT`, tocar
el botón de nuevo **cierra** — no hay forma de quedar trabado. Al agregar un módulo con popup, la
pregunta es ésa: *¿su botón re-abre o cierra?* Si re-abre, necesita su `…EndWithout`.

⚠ **Y en TODA pantalla del módulo, no sólo en la de la lista** (v21.10). El chooser de CC
(*"¿qué vas a cargar? Camión / Retira"*) se dibuja **antes** de consultar nada y su único «Cerrar»
minimizaba: el escape aparecía recién después de elegir y que la lista viniera vacía.

⚠ **Minimizar y cerrar son cosas distintas, y el caso vacío es siempre CERRAR.** No tiene sentido
dejar abierto un módulo sin nada adentro: si después entra trabajo, se vuelve a tocar el botón y la
lista se re-consulta igual. «Sigo después» sólo va en el caso de **error de carga**, donde sí puede
haber items y conviene reintentar.

⚠ **Y el escape NO emite el evento del toggle si el toggle no está abierto.** La misma lista la abre
el supervisor (`openRemitosAdmin`) con legajo **`"0"`** y **sin botonera**: ahí el evento sería huérfano.

⚠ **Vale para cada camino que puede DEJAR la lista vacía, no sólo para el fetch inicial.** En RR el
otro era `crMarkSinSalida`: al marcar «↩ s/salida» el último remito caía en el mismo pozo.

**Y no se prueba leyendo el botón.** Lo que hay que mirar es si el **toggle quedó abierto**, o sea
correr la pantalla: `node tests/rr-sin-remitos-cierra.cjs` (verificado que falla contra el código
anterior). Al agregar un módulo con toggle + lista, agregarle su caso vacío a ese test.

## ⚠ REGLA (Luis, 2026-09-21, v20.78): antes de optimizar, medir — y leer lo que se usa, no el universo

**Luis, con la captura del `canceling statement due to statement timeout` en A Programar:**
*"banda de timeouts, fijate de optimizar la toma de datos de pedidos"*.

El orden sigue siendo el de §"si algo tira «canceling statement», mirar `pg_stat_statements`
ANTES de tocar la función". Lo que apareció al mirarlo son tres cosas que se repiten en toda
la app, y por eso quedan escritas acá:

### 1. Una función SQL con `SET search_path` NO se inlinea — buscarla en los `WHERE`

Es el mismo pozo de `gv_destino_score` (v20.62), y estaba en otros dos lugares:
`gv_espejo_np_pasa` se llamaba **una vez por fila** dentro de `gv_ppp_base_pedidos` (9.618) y
de `gv_pedidos_web_excluidos` (16.143). Y con la canilla del espejo **abierta** —corte `lk` y
`chef` en `null`, como está desde el 06/09— **devuelve `true` siempre**: ninguna de esas
llamadas decidía nada.

```sql
-- el short-circuit, que es todo el arreglo:
where ((c.lk is null and c.chef is null) or gv_espejo_np_pasa(b.pedido, c.lk, c.chef))
```

`gv_ppp_base_pedidos`: 153 ms → **33 ms**. `gv_pedidos_web_excluidos`: 2.465 ms → **517 ms**
(y su peor llamada era de 7.958 ms contra un timeout de 8 s). Las dos con **0 filas de
diferencia**, medido con `EXCEPT ALL` en las dos direcciones.

### 2. Si el front usa un pedacito, el pedacito se arma en el servidor

`gv_ppp_base_pedidos` son 9.618 filas y PostgREST corta en 1.000: **diez vueltas, y cada
vuelta recalcula la vista entera**. De esas 9.618 filas el picking quiere `pedido → items` y
el panel de Despiece quiere los códigos. Las dos vistas nuevas entran en **una página**:

| lectura | vista | filas |
|---|---|---:|
| base de picking | **`gv_ppp_base_pedidos_items`** (`jsonb_agg` en orden de `id`) | 816 |
| panel de Despiece | **`gv_ppp_base_articulos`** | 321 |

**1.530 ms → 35 ms por lectura**, y son 2.324 lecturas cada 6 h.

### 3. `Prefer: count=exact` cuesta un recuento entero por página, y nadie lo usa

`supaFetchAll` lo mandaba en **cada** página: PostgREST contaba la relación completa por
vuelta (`pgrst_source_count`) para devolver un total que la función ni mira. Se sacó.

⚠ **Sin `count=exact` el header viene `0-999/*`**, así que el `else` del corte tiene que
colgar del **NaN**, no de la barra: con el código viejo `cr.indexOf("/")` seguía dando ≥ 0, el
total quedaba en `Infinity` y se pedía **una página vacía de más en cada lectura paginada de
la app**.

**Chequeo:** `select * from public.gv_reglas_perdidas;` — vacía = ninguna de las dos reglas se
perdió. Y `tests/pedidos-lectura-1vuelta.cjs`, que muerde por los dos lados (el literal en el
código y el header que sale de verdad en la request).
`sql/gv_base_pedidos_lectura_v2078.sql`, `sql/gv_pedidos_web_excluidos_v2078.sql`, §3.ls.

## ⚠ REGLA (Luis, 2026-09-22, v21.01): en el generador de OC, **`activo` NO es una decisión**

**Luis, al ver el 838 en OCs:** *"quiero entender por qué figura el 838 en OCs y la lógica
subyacente para encontrar otros códigos que estén errados"*.

`vista_generador_oc` arma su universo con la **UNIÓN de CINCO fuentes** — stock
(`vista_saldos_stock`), proyección (`proyeccion_madre`), **demanda** (pedidos pendientes),
capacidad (`Capacidad_Sector`) y configuración (`OC_Maximos`) — y después resuelve:

```sql
COALESCE("OC_Maximos".activo, true) AS activo
```

> **Un código sin fila en `OC_Maximos` entra igual y nace ACTIVO.** "Activo" no dice *"alguien
> decidió que esto se compra"*: dice *"nadie dijo lo contrario"*. Lo único que lo saca de la
> lista de compra es `tiene_prov_real` (`proveedor IS NOT NULL`).

**Caso testigo:** el **838** (Filtro para Mate y Café) no está en `OC_Maximos`; lo arrastró la
**demanda** — dos pedidos web de Chef de **Dorinka** (CH 0025 · 48 cajas, CH 0027 · 32), entrega
25/09. Sin góndola, sin capacidad, sin proyección y sin proveedor: **no se puede pickear ni
comprar**. Y no es teórico — la tanda **E41A** se pickeó el 15/09 y las tres filas del 838 en
`Movimientos_Stock` quedaron en **delta 0**. El **838E** (Rallador Cilíndrico Mini), que es el
que está vivo, sí tiene las cuatro cosas.

⚠ **Lo que NO es un error y por eso el centinela no lo lista:** 73 códigos tienen fila activa
**sin proveedor**, y **72 terminan en E** — son **importados**, no tienen proveedor local y está
bien que no lo tengan. Filtrar por *"activo sin proveedor"* da 73 falsos positivos.

⚠ **Y la comparación pela el sufijo de empresa antes que los ceros.** Un dual entra al
generador como `438E LK` / `438E CH` (`universo_e`) pero en `OC_Maximos` vive como `438E`:
comparando el código crudo salen **8 duales sanos** como si estuvieran sin configurar.

**Chequeo:** `select * from public.gv_oc_codigos_sin_config order by pedidos desc;` — al 22/09
son **16** (7 con pedidos, 82 cajas), con el `motivo` que dice cuál duele: *pedido sin góndola*,
*pedido sin OC*, *stock sin OC* o *resto* (código viejo o mal tipeado: `438E-`, `501B`, `587C`).
`sql/gv_oc_codigos_sin_config_v2101.sql`.

## ⚠ REGLA (Luis, 2026-09-23, v21.52): al facturar un DUAL, la caja sale de la pila donde ESTÁ

Caso **438E de Chef con «a facturar» en −1**: tanda D47B, pedido CH 0030. El armado anotó
`438E` **sin la L**, así que al facturar `stockSalidaFacturadoNP` tomó la empresa del pedido (CH)
y descontó de la pila de Chef, con la caja en la de LK. El guard `zzz_facturado_no_negativo`
no lo frenó porque mide la pila **sin empresa** (a propósito, v19.49) y LK tenía saldo.

Hoy ese mismo guard, en un código de `codigos_duales`, **cambia la empresa del descuento a la
otra** si la que viene no tiene saldo en esa tanda y la otra sí. No se tocó
`trg_normalizar_empresa_stock`. Centinela `v_otra` en `GV_Reglas_Centinela`.
`sql/gv_facturado_dual_pila_v2152.sql`.

⚠ Al corregir a mano la empresa de un movimiento, el caché `stocks_carga_rapida` se recalcula
**sólo para la empresa nueva**: la vieja hay que refrescarla aparte (un `update` sin cambios sobre
otro movimiento de esa empresa).

## ⚠ REGLA (Luis, 2026-09-22, v21.15): pelar la L de LOS DOS LADOS es no matchear nunca

Tercera pieza del agujero de la v21.12. **`reporte_agentes_equivalencia_facturar()`** —el aviso de
Telegram *"al facturar cambíá el código"*, cron 14, 08:00 / 12:00 / 16:00 ART— no usaba
`vista_pedidos_equivalencia`: **rehacía el join por su cuenta contra `GV_PPP_Base_Pedidos`**, o sea
que los pedidos de la página no existían para él.

Y al taparlo apareció el error que duele, que estaba también en la vista:

> **`Equivalencias_Codigos` tiene dos `cod_pedido` que TERMINAN EN L** — `438EL` → `438E` y
> `439EL` → `439E`. Pelando la L del pedido, `438EL` se compara como `438E` contra un `cod_pedido`
> que es `438EL`: **no matchea nunca**. El pelado hacía invisibles justo a las dos equivalencias
> que existen para códigos con L.

Medido: **CH 0022 (438EL) y CH 0024 (439EL)**, las dos programadas y sin facturar, no salían en
ningún lado. Hoy se compara el código **crudo Y el pelado**: cualquiera que matchee, avisa. Sobrar
un aviso no cuesta nada (dice *"mirá el código al facturar"*); faltar uno cuesta una factura mal.

⚠ **Esto NO vale para `Equivalencias_Familia`** (`vista_pedidos_secundarios`): ahí `cod_secundario`
no tiene **ni una** fila terminada en L, así que pelar es lo correcto y se deja como está. La
diferencia no se adivina — se mide: `where upper(btrim(<col>)) ~ '[0-9E]L$'`.

⚠ **La consulta del aviso salió de la función y es una VISTA**
(`gv_equivalencia_facturar_pendiente`), para poder probarla sin mandar el Telegram: `tg_enqueue`
escribe en `telegram_outbox` y el cron 28 lo vacía **cada minuto**, así que llamar a la función
"para ver qué da" manda el mensaje de verdad. La prueba va dentro de un `do $$ … raise exception $$`
que aborta todo (verificado: la fila encolada desapareció al revertir).

**Chequeo:** `select * from public.gv_equivalencia_facturar_pendiente;` ·
`select * from public.gv_reglas_perdidas;` — vacía = todo bien.
`sql/gv_equivalencia_facturar_web_v2115.sql`.

## ⚠⚠ REGLA (Luis, 2026-09-22, v21.20): a BLISTPACK, OSCAR y PEDERNERA **no se les manda OC**

**Luis, textual:** *"a blistpack/oscar/pedernera no se le manda OC, porque ellos fabrican acorde
a lo que le mandamos desde log/fabr"*. Y antes, sobre esos tres códigos: *"544, 560, 800 son pedernera 100%, pero no se le manda la OC a pedernera, solo
se le manda a log. Pero la recepción de mercadería es mercadería de Pedernera"*.

**Es el caso Oscar exactamente al revés**, y las dos puntas están bien: la orden se le emite a
**`Log/ Fabr`** y el que trae las cajas es **`Pedernera`**. Ninguna de las dos se "corrige".

Medido el 22/09:

| | 544 Batidor Pera | 560 Pinza Chica | 800 Pinza Chica Display |
|---|---|---|---|
| OC emitidas | **Log/ Fabr** · 6 · 2.022 cajas | **Log/ Fabr** · 4 · 168 | **0** |
| recepción | **Pedernera** · 22 · 1.866 | **Pedernera** · 7 · 259 | **0** |
| `OC_Maximos.proveedor` (quién FABRICA) | **Pedernera** (v21.23) | **Pedernera** (v21.23) | Pedernera |

⚠ **La consecuencia medible: `cantidad_recibida = 0` en las DIEZ OC.** 2.190 cajas ordenadas,
2.125 recibidas, **0 imputadas** — nueve quedaron `anulada` y una `pendiente`.
**`gv_oc_recompute_recibido(proveedor, codigo)` cruza por el par `(proveedor, código)`**, así que
con nombres distintos en las dos puntas la OC **no se cierra nunca sola**.

### ⚠⚠ Y son EXACTAMENTE estos tres: NO es un patrón de toda la tabla

**Luis, 2026-09-22, textual:** *"No siempre es la norma general de que le entrega a otro. En los
únicos que la orden sale en nombre de uno y le entrega a otro son los casos de Pedernera,
Blistpack y Oscar."*

O sea: **«la OC sale a uno y entrega otro» es una REGLA de negocio sólo para los tres fabricantes
de `GV_OC_Fabrica_Para`.** Cualquier otro código donde eso pase **es configuración mal puesta**, y
se arregla poniendo en `OC_Maximos.proveedor` al que de verdad entrega. **No se agrandan las
excepciones**: si aparece un caso nuevo, primero se mira la config, y sólo Luis decide si ese
fabricante entra a la tabla.

**Los 19 códigos que quedaban los revisa y los configura Luis, uno por uno** (22/09: *"lo
configuro yo, los 22 artículos que me pasaste, y lo damos por cerrado con eso"*). **Claude no los
toca.** Medido ese día contra `vista_generador_oc` —que es lo que se va a emitir, no lo que se
emitió—: **5 ya están bien** (550, 584E, 234, 609, 580: la config ya dice el que entrega y las OC
viejas a otro nombre son restos que se limpian solos), **1 no tiene proveedor** (583E, que por eso
no se puede comprar) y **13 hay que mirarlos**.

**El 591 (Despolvillador de Yerba) ya está cerrado: DISCONTINUADO** (Luis, 22/09: *"no se va a
recibir más ni va a salir en OC"*). `activo = false`, `proveedor = null` y el motivo en la
descripción; backup en `zz_backups."GV_Backup_OCMaximos_591_20260922"`. Verificado **como `anon`**,
que es la identidad del celular: sale de la lista de compra, del buscador de códigos activos de
Recepción (el «+» de Log/ Fabr lee `OC_Maximos where activo`) y del botón de Tierra Nativa — los
tres en **0**. Sus 6 OC (119 cajas, del 12/08 al 16/09) ya estaban **todas `anulada` con 0
recibido**, así que no quedó ninguna viva que cancelar.

⚠ **Discontinuar acá NO lo saca de la página.** En LK `products.active` sigue en `true` y sin
badge: el cliente lo sigue pidiendo. Al 22/09 hay **7 NP programadas** con 591 (22/09 al 02/10)
contra **13 cajas de stock** — salen con lo que hay. Si además hay que dejar de venderlo, es otro
cambio, en el proyecto de LK.

⚠ **La medición se hace contra `vista_generador_oc`, NO contra `OC_Maximos` a secas ni contra las
OC ya emitidas.** El 550 es el ejemplo: sus OC salieron a **Poly** hasta el 16/09 y hoy la config
dice **Garcia**, o sea que ya está corregido y lo que se ve es historia. Mirando sólo las OC
emitidas, un código ya arreglado sigue apareciendo como problema para siempre.

**El número era 22, no 25.**

> **Se retira el "25 pares" del barrido anterior: estaba CONTAMINADO.** Cruzaba por **número de
> código** y **Basconia compra ACERO EN KILOS** (rubro `Flejes`, unidad `Kg`), con códigos que
> chocan con los de artículo terminado: su `0635` es *"Arandela Gde/Chica Afila (77 x 1,25)"*, no
> el artículo 635. Basconia tiene **una sola tanda, del 13/07, 10 líneas, 7.650 Kg**, y **cero
> entregas** en `Entregas Tallerista Virgilio`: **no entra en esto por ningún lado**, ni tiene
> nada que ver con 544/560/800.

El barrido que vale filtra **`rubro = 'Art Term'` y `unidad = 'Cajas'`**, y deja afuera los alias
que `gv_prov_match` ya resuelve (`Martin C` = Martin, `Carlos E` = Carlos, `Pettofrezza` = Rafael)
y los tres fabricantes de `GV_OC_Fabrica_Para`. Al 22/09: **22 pares · 19 códigos · 4.654 cajas de
OC sin imputar**. Los que pesan:

| código | OC a | entrega | cajas OC | qué dice la config |
|---|---|---|---:|---|
| 510 | Carlos E | Log/ Fabr | 1.250 | el de la OC |
| 550 | **Poly** | Garcia (256) · Log/ Fabr (21) | 1.007 | **Garcia — ninguno de los dos** |
| 583E | Garcia | Log/ Fabr | 599 | el de la OC |
| 505 | Garcia | **Lucho (3.221)** · Log/ Fabr (98) | 274 | el de la OC |
| 584E | Garcia | Log/ Fabr | 222 | el de la OC |
| 103 | Martin C | Log/ Fabr | 186 | el de la OC |
| 922 · 911 · 224 · 223 | Pintos | Log/ Fabr | 275 | el de la OC |
| 123 | Lucho ↔ Garcia (los dos sentidos) | Garcia / Lucho | 179 | Garcia |
| 609 | German | Rafael | 151 | el de la OC |
| 591 | Tierra Nativa | Log/ Fabr | 119 | el de la OC |
| 580 | Carlos E | Log/ Fabr | 119 | el de la OC |
| 760 | Poly | Garcia | 99 | el de la OC |
| 234 | Tierra Nativa | Log/ Fabr | 94 | **el que entrega** |
| 519 · 719 | Log/ Fabr | Lucho | 39 | el de la OC |
| 355 | German ↔ Pettofrezza | Rafael / German | 31 | Pettofrezza |

**Ninguno se tocó**, y quedaron para Luis. El barrido, para volver a correrlo, y la consulta que
arma la lista de trabajo (código · qué emitiría hoy · quién viene entregando · estado) están en
`sql/gv_oc_maximos_544_560_v2123.sql`.

> **Son dos datos distintos y los dos son ciertos:** quién **fabrica y entrega** (así se carga en
> Recepción, y está bien) y a quién se le **emite la orden** (siempre `Log/ Fabr`, que es el que
> les manda el material). **Ninguno se "corrige" con el otro** — y en particular `OC_Maximos` NO
> se toca: su `proveedor` sigue diciendo quién fabrica, que es lo que el dueño pidió conservar el
> 15/09 (*"dejalo ahí"*). Lo que faltaba es la pieza que los relaciona.

**La pieza es `GV_OC_Fabrica_Para`** (fabricante → quién recibe la OC), con las tres filas que
dictó Luis. Al 22/09 **el dato y el centinela están aplicados; las dos mitades del arreglo NO**
— son dato real y las autoriza el dueño. Están escritas, con su medición, en
`sql/gv_oc_fabrica_para_v2120.sql`:

1. **que la OC salga a nombre de quién la recibe** — un solo lugar, `gv_oc_generar_pendientes`,
   por donde escriben el generador manual **y** el automático (cron 50).
2. **que la recepción del fabricante impute contra la OC de `Log/ Fabr`** — el mecanismo **ya
   existe**: `gv_norm_prov_keys` devuelve un **array** de claves y `gv_prov_match` las compara
   todas contra todas (así está resuelto hoy `pettofrezza → rafael`, hardcodeado adentro de dos
   funciones). Se le suma esta tabla como fuente y ese alias se migra ahí.
   ⚠ **Fusiona los dos nombres a efectos de imputación.** Riesgo medido: sólo **3 códigos** tienen
   entregas de los dos por separado desde el 01/06 — 506 (Log/ Fabr 3.439 vs Blistpack 203), 659
   (42 vs 8) y 764 (49 vs 8). ⚠ Y recalcula `cantidad_recibida` y `estado`: va con backup.

### ✅ v21.23: `OC_Maximos` de 544 y 560 → Pedernera (Luis: *"si, corregí 544 y 560 a Pedernera"*)

Hasta la v21.22 convivían **las dos configuraciones para el mismo fabricante**: de los 7 códigos
que fabrica Pedernera, la config decía `Pedernera` en 5 (115, 561, 800, 801, 802) y `Log/ Fabr`
en 2 (**544 y 560**). Medido sobre las entregas desde el 01/06, Pedernera entregó 115, 544, 560 y
802 — o sea que los dos que decían `Log/ Fabr` son suyos igual.

**Esto NO cambia a quién se le emite la OC**: `OC_Maximos.proveedor` dice **quién FABRICA** (regla
del dueño del 15/09, caso Oscar: *"dejalo ahí"*) y la emisión la resuelve `gv_oc_emite_a()`.
Verificado: los 7 códigos dicen `Pedernera` en la config y los 7 siguen emitiendo a `Log/ Fabr`.

Backup `zz_backups."GV_Backup_OCMaximos_20260922"` (clave `cod`, única: 360/360).
`sql/gv_oc_maximos_544_560_v2123.sql`.

**Chequeo:** `select * from public.gv_oc_proveedor_no_recibe_oc;` — vacía = todo emitido a quién
corresponde. Al 22/09 marca **225 cajas en 12 líneas** por salir mal en la próxima corrida:
Blistpack **177** (10 códigos, casi todos bombillas, más Manga Repostera) y Pedernera **48**
(561 Pinza Larga y 801 Pinza Grande Alambre).

### ⚠⚠ LAS TRES CAPAS, y la del medio es la que usa el operario todos los días

**Luis, textual:** *"Cuando pedernera entrega, el operario de GV debe poner pedernera y anotar ahí
lo que reciben. En el celular del operario de GV debe figurar la OC de las cajas a entregar"*.

| capa | a nombre de quién | dónde |
|---|---|---|
| se **emite** la OC | `Log/ Fabr` | `gv_oc_generar_pendientes` |
| se **entrega** | el fabricante | `Entregas Tallerista Virgilio` |
| el **botón del celular** | **el fabricante** | `oc_vigentes_por_proveedor` |

**Antes (medido llamando la RPC con cada nombre): `Pedernera` devolvía CERO** — el operario tocaba
el botón del que le estaba entregando y no veía ninguna OC — mientras el **560**, que trae
Pedernera, aparecía bajo **`Log/ Fabr`**. Y sin OC a la vista se pierde el control de cantidad:
`opState.ocOk` queda en false y el margen del +20 % no se exige.

**Las tres mitades aplicadas en la v21.22**, acotadas a `GV_OC_Fabrica_Para` (Luis: *"2 no
necesariamente, tengo que ver caso x caso"* — el resto de la tabla **no** se tocó):

1. **Al emitir**: `gv_oc_emite_a()` dentro de `gv_oc_generar_pendientes`, el **único** lugar por
   donde escriben el generador manual y el cron 50.
2. **Al imputar**: `gv_oc_recompute_recibido` suma las claves de los fabricantes a `pkeys`. El
   mecanismo **ya existía** (es un array, y `gv_prov_match` compara todas contra todas: así estaba
   resuelto `pettofrezza → rafael`). Impacto medido: **6 filas, todas 544 y 560** — 776 cajas del
   544 imputadas en 5 OC anuladas y el 560 completo (57/57) pasando a **recibida**. Ninguna OC de
   otro proveedor se movió. Backup: `zz_backups."GV_Backup_OrdenesCompra_20260922"`.
3. **El botón**: `gv_oc_codigo_del_fabricante` dice qué códigos entrega cada uno, y
   `oc_vigentes_por_proveedor` se lo suma al fabricante y se lo saca al que recibe la orden.

⚠⚠ **Y el botón NO puede derivarse de `OC_Maximos.proveedor` a secas, porque ese campo está
MEZCLADO.** De los 4 códigos que Pedernera entregó desde el 01/06 (115, 544, 560, 802 · 2.355
cajas) la config dice **Pedernera en 2 y `Log/ Fabr` en los otros 2**. Derivarlo sólo de ahí mueve
**11 líneas de OC** que son config vieja y no esta regla: 515/615/635 (Basconia → Carlos E, 1.800
cajas), 222 y 910 (Maspoli → Pintos), 234, 618, 725. Por eso la vista une **config ∪ lo que viene
entregando**, y sólo para los tres fabricantes de la tabla.

⚠⚠⚠ **Y mordió la trampa de la v20.45.** `GV_OC_Fabrica_Para` nació con RLS sin policy y
`oc_vigentes_por_proveedor` es **INVOKER**: medido, **postgres veía 1 código y el operario 0**.
No da error — da menos filas, y probarlo desde el MCP no prueba nada porque el MCP entra como
`postgres`. Se le puso policy de **SELECT** (es config de proveedores: 3 filas con nombres); la
escritura sigue revocada. **Toda RPC nueva que el celular llame se prueba con
`set local role anon`, no desde el MCP.**

**La prueba que vale, corrida como `anon`** (OC del 561 emitida, transacción abortada):

```
boton PEDERNERA: 561 (pend 41)          <- la OC donde el operario la necesita
boton LOG/ FABR: 255                    <- sigue con lo suyo, sin el 561
Garcia (control): 113, 323, 439E, 839   <- sin cambios
```

**Chequeo:** `select * from public.gv_reglas_perdidas;` — vacía = todo bien ·
`select * from public.gv_oc_codigo_del_fabricante order by 2,3;`
`sql/gv_oc_fabrica_para_v2122.sql`.

### ⚠ Lo que NO va: la excepción de la doble OC (v21.14, aplicada y revertida el mismo día)

Una lectura anterior del pedido —*"deberían generar OCs por el total (100%) para fab y para
carlos"*— se implementó como `OCG_DOBLE_100`: dos OC por código, una a `Log/ Fabr` y otra a
`Carlos E`. **El dato la desmintió**: en toda la historia de `Ordenes_Compra` esos códigos tienen
**cero OC a `Carlos E`** y cero a Pedernera. El único rastro de un Carlos son **3 filas de
recepción de mayo-junio a nombre de `AGUIRRE CARLOS RODOLFO`** (260 cajas de 544), muertas desde
el **04/06**, justo antes de que empezara Pedernera el 10/06. `Carlos E` y `Carlos` son entidades
distintas de `Pedernera` en `Talleristas_Contacto` — no es un alias.

**Se revirtió entero** (la constante, el armado de subs, la marca `dupProv`, el `Math.max` de la
vista y el texto de la celda Tallerista). Si vuelve a aparecer la idea de una lista hardcodeada de
códigos con doble OC, **es la señal de que falta el alias de entrega**, que es otra cosa.

## ⚠ REGLA (Luis, 2026-09-25, v22.53): ♻ RECUPERAR ITEMS DE FC — completar la facturación de una NP ya facturada

**Luis:** *"que se pueda completar la facturación de un pedido ya facturado en caso de que ingrese
mercadería entre la facturación y la entrega al cliente"*. Botón verde **♻ Recuperar pedido** en el
encabezado de Facturación.

| paso | cómo |
|---|---|
| lista | `gv_fac_recuperar_lista(p_dias)`: NP facturadas, buscador por varias palabras, filtro LK/CH, días y «sólo con faltantes» |
| detalle | `gv_fac_recuperar_detalle(np)`: por código **faltó al facturar** (reconstruido), **completado después** (CP), ya complementado, **pendiente** (tope). Lo completado después viene tildado |
| ✔ Marcar como facturado | ya se facturó **a mano** en ISIS antes (el confirm lo dice). Graba el lote modo `marcado` |
| ⬇ Excel ISIS | `_facXlsArmar(nps, {lineas, cab})` con **sólo** los códigos marcados. Graba el lote modo `excel` **antes** de bajar |
| cruce | `gv_fac_complemento_cruce()` (corre con el cron 90) busca la factura de cada lote: mismo cliente, ±10 días, cajas ±15 %, todos los códigos en la factura. Queda en `GV_Fac_Complemento_Doc` |

⚠ **«Faltó al facturar» se reconstruye**: `cp_reducir_faltante_cap` (Completar Pedido) **suma a
`cajas_entregadas`** y resta de `cajas_falto`, así que después de un CP la fila ya no dice lo que se
facturó. Se descuenta lo que CP sumó **después de `facturado_at`** (`Movimientos_Stock` tipo `cp` a
`a_facturar`, `ref` = NP).

⚠ **El cruce principal se enteró**: la factura de un complemento **no es candidata** para la NP, y lo
que CP sumó después de facturar se descuenta del `cajas_ent` contra el que compara (en un CTE: por
subselect pasó de 1,6 s a > 60 s). Conciliación muestra el chip **♻ +N cj** en la NP.

⚠ **No mueve stock**: lo físico va por Completar Pedido, que ya drena `a_facturar` si la NP estaba
facturada. **No toca `Facturacion_NP`** (una fila por NP): los complementos viven en `GV_Fac_Complemento`.

`sql/gv_fac_recuperar_pedido_v2253.sql`, `tests/fac-recuperar-pedido.cjs` (el marcador interno de las funciones dice `v22.52-compl`: es la llave de idempotencia, no cambiarlo).

⚠ **v22.59 (Luis): cada botón abre el cartel «¿Querés que saquemos de góndola los artículos
seleccionados?» SÍ / NO** (✕ = no se hace nada). **SÍ** descuenta de góndola (`terminado`) **aunque quede
en negativo**; el movimiento va `tipo='ajuste'`, `ref='<NP>|FCC'` y `descripcion` *"Sale de góndola:
facturado con «Recuperar items de FC»…"*. **NO exige escribir por qué** (backend: `p_motivo_no_stock`, si
falta da error) y queda en `GV_Fac_Complemento.stock_detalle.motivo_no`. Lo completado con Completar
Pedido después de facturar ya drenó y **no se descuenta dos veces**. Candado `pg_advisory_xact_lock` por
NP + freno de doble clic. `sql/gv_fac_recuperar_stock_v2259.sql` (reemplaza la `_v2258`). **El aviso de Telegram de
stock negativo SE DEJA** (Luis): para estos movimientos dice el motivo y el stock en A guardar / Racks /
Excedente, *"registren el movimiento si salió de ahí"* (`sql/gv_fac_recuperar_aviso_negativo_v2261.sql`).

## ⚠ REGLA (Luis, 2026-09-24, v22.40): el descuento de OC de una recepción NO se puede perder

**Caso:** 24/09 11:49 la base cortó por timeout y la carga de Blist-Pack (763 + 764) dio 500 en
`gv_oc_aplicar_recepcion`: el 764 (19 cajas) quedó sin imputar a la OC 1668 (0/15). `recepcion.js`
la llamaba sin mirar el resultado, y **`supabase.rpc` no rechaza con un 500: resuelve con `{error}`**.

| capa | qué hace |
|---|---|
| celular | **cola persistente** (`rcp_oc_pend_v1` en localStorage, v22.42): cada recepción queda ahí **hasta que la base la acepta** — reintenta a los 5 s, 15 s, 30 s, 1 min y después cada 2 min, y también al abrir la app y al volver la conexión. Sobrevive al cierre de la app |
| backend | cron **`gv-oc-recepcion-red`** (`7,19,29,43,55 * * * *`, minutos impares fuera del 57 y el 68) → `gv_oc_recompute_recepciones_recientes(36)`: recalcula las OC de todo código recibido en las últimas 36 h. Idempotente: si cuadra no escribe (22 códigos, 1,4 s) |

**Por qué falló, medido:** la función tarda **0,16 s** normalmente. A las 11:49:08 le tocó la cola de
**8 consultas pesadas en el mismo segundo** (A Programar: `gv_cuarentena_marcar` ×3 y
`gv_ppp_web_dia_salida` ×3; Facturación: `facturacion_neto_lote` ×2), todas cortadas a los 8 s:
esperó 15,4 s y cayó por `57014`. No es la recepción la que pesa; es la saturación de un momento.

⚠ **El cron 93 (miércoles) NO se toca**: es del circuito de OCs automáticas (Luis: *"lo del
miércoles es que se manden las OCs"*). Probado rompiéndolo en transacción abortada: OC 1668 puesta
en 0 → la red la devolvió a 15 / recibida. Problema 544. `sql/gv_oc_recepcion_red_v2240.sql`,
`tests/rcp-oc-reintento.cjs`. Rollback: `select cron.unschedule('gv-oc-recepcion-red');`

## ⚠ REGLA (Luis, 2026-09-23, v21.63): CLIENTES DE PRUEBA — van a la PPP, el operario no los ve

**Luis:** *"que sus pedidos solo se puedan programar como tanda única (código PruebaX) · si se
programa automáticamente, con las reglas que ya hay · que no se considere cliente nuevo · que NO le
figuren a los operarios (no son pedidos reales, no quiero que rompan la operación)"*.

Primer cliente: **LK 99862 «Luiggy y Luiggy (PRUEBA)»**, copia de Muller y Muller (LK 862) en la
página LK — usuario `prueba123`. La lista vive en **`GV_Clientes_Prueba`** (agregar otro = un `insert`).

| qué | cómo |
|---|---|
| tanda única | `GV_Clientes_Reglas` regla `solo` (ya existía) |
| código `PRUEBAn` | `gv_prueba_tandas_normalizar()`, cron `gv-prueba-tandas` c/5 min, renombra con `gv_ppp_tanda_renombrar`. En MAYÚSCULAS: todo compara con `upper(btrim())` |
| no es cliente nuevo | copia de la excepción de Muller en `gv_excepcion_cuarentena` |
| oculto al operario | front: `gvSinPrueba` (listas de picking/armado, picking, armado, faltantes, monitor), `gvEsTandaPrueba` (Carga Camión, Control Remitos, Recepción Remitos), `monitor/tv.html`, y el **Excel ISIS los saca** |
| eliminar | botón **🗑 Eliminar** en la fila de una tanda PRUEBA = «Cancelar pedido» (`gv_ppp_pedido_cancelar`, todo el pedido) |
| cupo y camión | cuentan como cualquier pedido (*"con las reglas que ya hay"*) |

⚠ **El filtro del front NO toca el mapa cacheado** (`_pppCache`): el supervisor sigue viendo las
tandas PRUEBA en la PPP. **Centinela:** `select * from public.gv_prueba_mezclada;` — vacía = ningún
pedido de prueba quedó adentro de una tanda con pedidos reales (esa no se renombra).
`sql/gv_clientes_prueba_v2163.sql`, `tests/prueba-oculta-operario.cjs`.

## ⚠ REGLA (Marianela, 2026-09-23, v21.76): una tanda EMPEZADA no cambia de CÓDIGO al moverla de día

**Marianela:** *"cuando tengamos una tanda en proceso de picking o armado y la cambio para otro día
… no deje cambiar el nombre porque los operarios trabajan por nombre de tanda, luego no la encuentran"*.

El paso 2 de «📅 Cambiar de día» sólo ofrecía **➕ Tanda nueva** o **meterla en otra**: las dos le
cambiaban el código. Ahora hay **🔒 Mismo código** (`p_tanda_destino = null`, modo `mantiene`) y,
si la tanda tiene eventos de operario reales (legajo ≠ 0/1), `gv_ppp_tanda_mover` frena cualquier
cambio de código con **`TANDA_CANDADO`**. Juntar OTRA tanda adentro de la empezada sigue valiendo:
la empezada no cambia de nombre.

**Chequeo:** `select * from public.gv_reglas_perdidas;` · `node tests/ppp-tanda-candado-codigo.cjs`.
`sql/gv_tanda_candado_codigo_v2176.sql`.

## ⚠ REGLA (Thomas, 2026-09-23, v21.56): UN CAMIÓN = UN GRUPO DE ZONAS — Capital son DOS camiones

**Thomas, textual:** *"no podés programar para un solo día zona 1, zona 2, zona 3, zona 6, zona 7. Es un
desastre"* · *"No puedo ir tantas veces a zona 3 y 4 y 5 y 6"*.

| camión | zonas | sectores |
|---|---|---|
| **Capital Sur** | Z1 | A, B |
| **Capital Centro** | Z2 | (la zona manda, no el sector) |
| **Capital Oeste** | Z3 | (la zona manda, no el sector) |
| GBA Sur | Z4 | J, K, L |
| GBA Oeste | Z5 | M |
| GBA Norte | Z6 + Z7 | N, P |
| súper | cada uno el suyo | — |

⚠⚠ **Z2 y Z3 son camiones DISTINTOS (Luis, 23/09, v21.91)** — *"¿cuál sería la lógica de tener
separadas las zonas Z2 y Z3 si son lo mismo?"*. Se retira el "Capital Centro-Oeste = Z2 + Z3" de la
v21.43. En `gv_ppp_web_camion` la ZONA manda sobre el sector para Z2 y Z3 (los sectores C..H siguen
armando la tanda por cercanía, no deciden el camión). Centinela `Capital Oeste` en `GV_Reglas_Centinela`.
⚠⚠⚠ **REGLA VIGENTE (Luis, 23/09, v21.95) — se retiran la v21.91 y la v21.94 como "camiones distintos siempre":**
- **Z2 y Z3 van en el MISMO camión si cada una suma < 1 m³ ese día** (web + ISIS; Retira no cuenta). Apenas una
  llega a 1 m³, esa va sola. Sirve para compensar zonas de poco volumen.
- **Z6 y Z7 van SIEMPRE juntas** (un camión, GBA Norte). Z7 sale sola sólo si en su plazo no hay día con Z6.
- **Prioridad: máxima entrega con la menor cantidad de camiones.**
- **Las TANDAS no se tocan** (Luis: *"no rompas la lógica de tandas"*): `gv_ppp_web_camion` sigue dando una
  etiqueta por zona (Capital Centro / Capital Oeste / GBA Norte / GBA Norte Lejos) y una tanda no mezcla esas
  zonas. La unión es del CAMIÓN: la aplican `gv_ppp_web_dia_grupo` (el armado, al elegir el día) y el Resumen de
  la PPP (al contar camiones). Si una zona pasa de 1 m³ después, cambia la cuenta y ningún pallet se toca.
  `sql/gv_programacion_camion_z2z3_z6z7_v2195.sql`.

Hasta la v21.57 `gv_ppp_web_camion` devolvía **"Capital" para Z1, Z2 y Z3**, así que un día con Z1+Z2+Z3
contaba como un solo camión y nada lo marcaba. Máximo **2 camiones por día**, cada uno a **un** grupo, y
**cada grupo sale una sola vez** mientras entre en un camión (Z4 4,03 m³ → una salida, no cuatro).

⚠ **El súper NO se junta en un día** (*"Matiz es súper, no se juntan"*): `gv_ppp_cliente_dos_dias` no lo marca.

⚠ **Norma de salida (Thomas, 23/09):** *"hoy tiene que facturarse para mañana lo que se armó ayer. Y nada
más que eso"* — armado día 1, factura día 2, sale día 3. Vale también para el súper en el armado.

El 22/09 21:54 una reprogramación a mano niveló los días a 4,30 m³ sin mirar el camión y dejó GBA Sur en
4 salidas, Oeste en 3 y Norte en 3. Se rehizo el 23/09 (25 tandas).

**Chequeo:** `select * from public.gv_ppp_tanda_camion_mezclado;` · `select * from public.gv_reglas_perdidas;`
`sql/gv_camion_un_grupo_zonas_v2156.sql`.

### ⚠⚠ Y NO HAY TOPE DE m³ POR CAMIÓN (v21.75, 23/09): `camion_m3_tope` NO es la capacidad

**Textual:** *"no hay límite para arriba en la cantidad de metros cúbicos por camión. Puedo tener
hasta 40 metros cúbicos en un camión."*

> **`PPP_Web_Config.camion_m3_tope` = 6 es lo que el armador MEZCLA en una TANDA, no lo que entra
> en el camión.** Lo lee `gv_ppp_web_agrupar_geo` / `gv_ancla_simular`, y ahí está bien. Usarlo
> como capacidad del camión es lo que partía un pedido en tres.

**Lo que costó, medido:** el Resumen de la PPP contaba `ceil(m³ / 6)` por ruta, así que el
**28/10** —**12,33 m³ de Matiz sola**, un cliente, una entrega— decía **3 camiones**. Y contaba con
las **dos rutas viejas** (Z1+Z2+Z3+Z4 = un camión), o sea que un día con Z2+Z3+Z4+Z6 decía **2**
cuando salen **3** y el exceso sobre el tope de 2 camiones por día no se veía en la única pantalla
que mira el conjunto.

Hoy el Resumen cuenta **un camión por grupo de zonas** (la tabla de arriba) + **uno por cliente
súper** + **Retira sin camión**, y un grupo **no se parte** hasta los **40 m³** que entran
físicamente, que viven en **`PPP_Web_Config.jornada_camion_m3_cap`** — entra por el fetch
`clave=like.jornada*` que el front ya hacía, y sin la fila usa 40 de default.

⚠ **El armado NO se tocó**: sigue con `camion_m3_tope` y sus reglas. Esto es la cuenta que
**muestra** el Resumen.

⚠ **Y la DEMORA de esa tabla es la MAYOR del día, no el promedio** (mismo pedido): *"en lugar de
figurar los días de demora promedio, el día de mayor demora… y que pueda tocar y ver por camión,
ordenado por mayor demora, la demora real de cada uno"*. El promedio de un día con un pedido de 35
días y otro de 76 daba **55,5**, un número que no le pasa a ninguno de los dos y que escondía al que
estaba parado hace 76. La celda abre el pop-up de camiones ordenado por demora; a partir de **14
días corridos** (los 10 hábiles del punto 4 de la lógica de programación) va en rojo.

**Chequeo:** `node tests/ppp-res-demora-camion.cjs` — corre la pantalla y clickea la celda.
Verificado que falla contra el código anterior con los números del reclamo (3 camiones, 55,5 días).
`sql/gv_resumen_camion_m3_v2175.sql` (la fila de config, **pendiente del sí del dueño**).

## ⚠ REGLA (Luis, 2026-09-22, v21.39): las tandas son de 0,80 m³ — y el armado las FUSIONA

**Luis, textual:** *"¿Por qué las tandas son tan chicas? Tienen que ser de 0,8 en promedio.
Mínimo 0,6, máximo 1. Salvo pedidos más grandes. ¿No tenés esa lógica?"* Y sobre la fusión:
*"tiene que ser 0,80"*.

**Media lógica estaba, media no.** `tanda_m3_max_mezcla` (1,00) sí se usa: es el techo hasta el
que una tanda abierta sigue recibiendo clientes. **`tanda_m3_min` (0,60) NO lo lee ninguna
función** —medido: 0 apariciones en `pg_proc`—; es sólo un cartel del front de A Programar.

**Medido el 22/09** (tandas de los últimos 7 días + futuras), separando lo que no es camión:

| clase | tandas | promedio | < 0,6 | de 1 solo cliente |
|---|---:|---:|---:|---:|
| **Reparto** | 62 | **0,631 m³** | 35 | 41 |
| Retira | 17 | 0,301 | 15 | 17 |
| Súper | 7 | 3,070 | 1 | 7 |

Retira no usa camión (cada uno viene a buscar el suyo) y el súper va solo por regla. El número
que importa es el de reparto.

### La causa: la tanda nace con lo que hay en ese momento y nadie la vuelve a juntar

`ppp_web_armar_tandas` acumula clientes **nuevos** en una tanda abierta del mismo día y camión
(`_open`, v13.67), pero **nunca fusiona dos tandas que ya existen**. Caso testigo, 28/09 GBA
Oeste: **5 tandas para 0,846 m³**, tres del mismo sector M (Ciudadela) — E46A nació el 08/09,
E46B/E46C el 16/09, E49A el 14/09, E50A el 08/09, cada una para OTRO día. Cuando se
reprogramaron todas al 28/09 quedaron 5 tandas en el mismo camión y ninguna regla las miró.

### El pase de fusión: `gv_ppp_web_fusionar_tandas(empresa, desde, simular, por)`

Corre **al final de cada corrida del armador** (pase (e) de `gv_ppp_web_armar_pendientes`) y
junta, por (fecha, camión), las tandas que se pueden juntar, de la más grande a la más chica,
hasta el **objetivo `tanda_m3_fusion` = 0,80** sin pasar nunca el **máximo
`tanda_m3_max_mezcla` = 1,00**. Sólo absorbe una tanda cuyas paradas sean **todas** compatibles
con las de la que recibe (`gv_ppp_web_compat`: mismo camión, sectores vecinos o pares del
dueño). La fusión la hace `gv_ppp_tanda_renombrar`, que ya sabe mover programación, eventos y
stock (v19.69 / v20.88).

**Lo que NO toca, a propósito:** tandas con cualquier evento de operario (PK/PKC/EP/TP/TAP/AP/
CC/CCN, legajo real) o con stock movido —un pallet con papel no se renombra solo, regla
v20.88—, súper, retira, cliente `solo`, tanda de dos camiones, tanda en dos días (problema 338)
y día sin reparto.

⚠ **El interruptor es `PPP_Web_Config.tanda_fusion_activa`** (0 = apagado). Prenderlo es un
`update`, no un deploy. **Prendido el 22/09 con el sí de Luis** (*"prendé la fusión"*): la
primera corrida real hizo E70A→E64A, E18A→E48C y E46C→E49A.

### ⚠ Al reprogramar a mano, el CLIENTE se junta por `cliente_key`, no por `(empresa, cod)`

El 22/09 se reprogramaron 21 tandas a mano para dejar cada día en el cupo (4,30 m³). El plan
agrupó los pedidos de un mismo cliente por **código dentro de cada empresa**, y **Clapera Alicia
Raquel** es **2447 en Chef y 2394 en LK** —misma persona, misma dirección (Rabanal 2866, expreso
a Rosario)—: E65A (LK) fue al 05/10 y E26C/E53B (Chef) quedaron el 30/09. Lo cazó
`gv_ppp_cliente_dos_dias` (5 filas). La regla de Thomas (*"nunca +1 pedido de un cliente va
separado en la PPP"*) cruza empresas: **la clave del cliente para el día es `cliente_key`**, la
misma que usa ese centinela. Y se mira **antes y después** de cualquier movida de tandas.

**Probado corriendo el armador**, no leyéndolo (regla v19.56): en transacción abortada, con el
interruptor en 1, `gv_ppp_web_armar_pendientes('lk', …)` entró al pase y fusionó E70A→E64A,
E18A→E48C y E46C→E49A: **51 → 48 tandas**, los tres códigos viejos sin una sola fila. Y lo que
**no** fusionó lo explica la cercanía, no un bug: E37C (San Cristóbal, A) con E29G (Villa Luro,
C) no son vecinos; E48A (Pompeya, B) no es vecino de H ni F; E61A + E61E = 1,031 > 1,00.

`p_simular = true` (default) no escribe: devuelve lo que HARÍA. Es la forma de mirarlo:

```sql
select * from public.gv_ppp_web_fusionar_tandas('lk');    -- qué juntaría hoy, sin tocar nada
select * from public.gv_reglas_perdidas;                   -- vacía = el pase sigue en el armador
```

`sql/gv_ppp_web_fusionar_tandas_v2139.sql`.

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

## ⚠ REGLA (Luis, 2026-09-23, v21.42): el SUPERVISOR no firma con legajo 0 — 0 y 1 son PRUEBA en todo el sistema

**Luis, con Ocupación abierta en el 18/09:** *"Sigo sin entender esos 2. En prog dice que está todo
ok pero allá dicen esos 2"*.

Los 2 (LK 0038 y LK 0055, E12C) salieron el 18/09 con Carga Camión de Eduardo y el supervisor les
hizo Recepción Remitos el 21/09 **desde el panel** (`openRemitosAdmin`), que firmaba el CRN con
**legajo `"0"`**. Y `es_legajo_test` dice que 0 y 1 son legajos de prueba: `gv_ppp_entregados`
descarta ese CRN, el pedido nunca pasa a Entregado y el front lo deja en `programados` → **Ocupación
lo muestra en su día viejo**. Programación no lo muestra porque arranca en hoy y `gv_ppp_atrasados`
da por salido con el **CCN** (legajo real). Dos pantallas, dos criterios, y las dos "tenían razón".

Medido: **8 NP desde el 10/09** con el CRN sólo de legajo 0 (LK 0011, 98502, LK 0038, LK 0055,
CH 0010, CH 0012, CH 0013, CH 0016); en julio/agosto hay ~230 más de Producción (`gv_app` null).

Hoy el supervisor firma **`sup:<mail>`** (`gvLegajoSupervisor()`), nunca 0. Lo sostiene
`tests/rr-supervisor-legajo.cjs`. ⚠ Los otros `legajo: "0"` del archivo (ajustes de stock, CRA
"carga sin control", PPE "errores en PPP") son eventos del **sistema**, no de una persona, y quedan
como están.

## ⚠ REGLA (Luis, 2026-09-23, v21.41): el día «⏸ Armados en espera» NO EXISTE MÁS

**Luis, con la captura de la Programación:** *"No tiene que existir «Armados en espera»"*.

Historia corta, para no volver a ponerlo: nació en la v19.29 (pedido de Luis: un «día» sin fecha
para tandas armadas a propósito), en la v19.32 pasó a estar **siempre** en la tabla aunque vacío,
en la v21.40 el botón del pop-up pasó a ser un casillero de la grilla, y en la v21.41 Luis lo sacó
entero: **ni la fila en la tabla de Programación ni el destino en «📅 Cambiar de día»**.

- Lo que se sacó son las **puertas**: la fila vacía (`_pgaConEspera` sigue en el archivo sin
  llamador) y el destino del pop-up (`pppTandaEspera` / `pppMovEsperaElegir` siguen sin puerta,
  como `gv_ppp_np_desarmar` en la v18.77). La RPC `gv_ppp_tanda_espera` y la tabla
  `GV_PPP_Armados_Espera` no se tocaron.
- **Lo parado viejo no se esconde.** Si el backend devuelve una tanda con la fecha centinela
  (`9999-12-31`), la tabla la sigue mostrando con su nombre, no como fecha; y el badge
  `armado_espera` de `gv_ppp_avisos` (Thomas, v20.86) sigue vigilando la tabla. Al 23/09 había
  **0** tandas ahí, así que nada quedó a oscuras.

**Chequeo:** `node tests/ppp-armados-espera.cjs` — es el candado invertido: se pone en rojo si
vuelve la fila vacía o el destino del pop-up, y si una tanda parada dejara de verse.

## ⚠ REGLA (Luis, 2026-09-22, v21.30): el operario puede recibir un código que NO es del proveedor

**Luis, textual:** *"cuando se elige al tallerista deberían aparecer los códigos asignados a el
como proveedor y un botón más grande que diga «Introducir Código diferente» … Una vez envíe el
dato de la recepción, debería aparecer un botón para notificar a Thomy por WhatsApp (como si
hubiesen recibido mercadería > a las OCs establecidas) que no impida la recepción"*.

El buscador de códigos activos ya existía desde la **v15.76**, pero era el `+` de **Log/Fabr** y
**de nadie más**: si Pedernera entregaba un código que no estaba en su lista, el operario no tenía
forma de cargarlo. Y con la lista vacía la pantalla cortaba con un `return` que dejaba sólo el
cartel *"No hay códigos"*. Hoy el botón grande **«🔍 Introducir código diferente»** está en todos
los proveedores, con lista vacía también.

⚠ **El código agregado así NO se asigna al proveedor** — sólo en Log/Fabr, que es como venía. Si
se guardara en `Articulos Virgilio X Tallerista`, la próxima entrega del mismo código entraría en
silencio y el aviso a Thomas no saldría nunca más. Es exactamente lo que se quiere evitar.

⚠ **El aviso es el del exceso de OC, no uno nuevo.** Un código que no es del proveedor no tiene OC
suya → `ocRef = 0` → ya entraba por `opExcesoItems` y el botón de WhatsApp ya aparecía. Lo que
faltaba era **decirlo por su nombre**: `noAsig` hace que el mensaje diga *"un proveedor entregó un
código que no está asignado a él"* en vez de *"SIN OC generada (OC = 0)"*, que es lo mismo que ya
se corrigió en la v19.57 para el caso de la OC ajena.

**Los tres casos del mensaje, y no se pisan:**

| qué pasó | qué dice |
|---|---|
| el código está en la OC de **otro** proveedor (`ajena`, v19.57) | *"la OC es de Poly (155 pendientes)"* |
| el código **no está asignado** a este proveedor (`noAsig`, v21.30) | *"NO está asignado a Lucho ni tiene OC suya"* |
| es suyo pero no hay OC (`sinOc`, v17.99) | *"SIN OC generada (OC = 0)"* |

**Chequeo:** `node tests/rcp-codigo-diferente.cjs` — corre la pantalla de verdad y mira las dos
mitades (que el botón esté para un tallerista común **y** que Log/Fabr siga guardando fijo).
Verificado que falla contra el código anterior.

### ⚠ Y un código con proveedor puede NO figurar en el módulo de operarios

Lo que el operario ve al elegir a un proveedor sale de **dos tablas distintas**, y ninguna es
`OC_Maximos`:

| tipo de entidad | de dónde salen sus códigos |
|---|---|
| `tallerista` | **`Articulos Virgilio X Tallerista`** por `Cod_Tallerista` + `Linea` |
| `prov_at` | **`vista_articulos_prov_at`** por `proveedor` + `linea` |

⚠ **El barrido se hace con `gv_prov_match`, NUNCA por nombre crudo.** `OC_Maximos` dice
`Martin C` / `Carlos E` / `Pettofrezza` / `Blistpack` donde la entidad se llama `Martin` /
`Carlos` / `Rafael` / `Blist-Pack`: comparando el texto pelado salen **91 códigos "a nombre de
otro"** que están perfectos. Con el matcher, de los 238 activos con proveedor faltan **49**.

⚠ **Y el `Cod_Tallerista` es POR LÍNEA**: `Codigos X Tallerista` tiene una fila por (nombre,
línea). **Blist-Pack no tiene fila CH**, así que sus 5 códigos de Chef (758, 762, 763, 764, 769)
no pueden aparecer aunque se los dé de alta — falta ese dato, lo define el dueño.

⚠ **`vista_articulos_prov_at.linea` sale de un LATERAL contra la tabla de TALLERISTAS**, que no
tiene nada que ver con un prov AT. Un código que no esté ahí sale con `linea = ''` y el
`.eq("linea","LK")` del celular no lo encuentra nunca. Al 22/09 era **1 de 87** (el 193, Kuffo).

**✅ APLICADO el 22/09 con el OK de Luis: 40 filas nuevas** (backup
`zz_backups."GV_Backup_ArtXTall_20260922"`, 335 → 375), verificado como `anon`. Y la vista
`vista_articulos_prov_at` ya cae a `OC_Maximos.linea` cuando la tabla de talleristas no tiene el
código, así que el 193 sale `LK` y **ninguno de los 87 queda sin línea**.

⚠ **Las tres correcciones que dictó Luis y bajaron el alta de 43 a 40:**

| qué dijo | qué se hizo |
|---|---|
| *"231, 232, 233 los hace log fabr"* | van bajo **Log/ Fabr**, no Tierra Nativa. El dato no lo desmiente: esos 3 tienen **cero entregas** registradas. ⚠ El **55215** (Palo de Amasar 40) **sí** es de Tierra Nativa — 208 cajas el 26/08. Son cosas distintas |
| *"582E y 119 no se fabrica, se importa listo para la venta"* | **no entran**: un importado no se recibe por el módulo de talleristas |
| *"581T es discontinuo… si no genera OC no me jode"* | **no entra**. Medido: `total = 0` en `vista_generador_oc` (proy 0, stock 73 = capacidad), así que hoy no genera OC. ⚠ Pero apenas se venda una caja el `total` sube y **sí** la genera: si es discontinuo de verdad, va `activo = false` como el 591 |

⚠ **Y quedan DOS cosas de config, que son de Luis y NO se tocaron:**

1. **231/232/233 siguen diciendo `Tierra Nativa` en `OC_Maximos`**, así que generan **17 cajas**
   de OC a ese proveedor (5 + 7 + 5, todo por pedidos). El operario ya los ve bien; lo que falta
   es la config. SQL propuesto al final de `sql/gv_recepcion_codigos_con_proveedor_v2130.sql`.
2. **119 genera 19 cajas a Lucho y 582E genera 18 a Garcia** — si se importan, esas dos OC están
   mal emitidas.

**Chequeo:** la consulta de barrido está al final de
`sql/gv_recepcion_codigos_con_proveedor_v2130.sql`. Al 22/09 devuelve **11 filas y las 11 están
explicadas** ahí mismo (5 de Blist-Pack CH, 3 que Luis sacó y los 3 palos, que esperan la config).

## ⚠ REGLA (Luis, 2026-09-22, v20.95): un código BUSCADO se muestra aunque esté en 0

**Luis, textual:** *"838E NO APARECE en la vista de stocks"*.

La tabla de Stock esconde a propósito las filas que están en 0 en **todos** los sectores y sin
pedidos — son ruido al mirar la tabla entera. Pero ese filtro (`_stkHasAny`) se aplicaba
**también al buscar**, así que tipear el código entero no traía nada. Eran **46 códigos**, **21
con proyección viva** (838E: capacidad 35, proyección 34,17 caj/mes, comprado por Log/ Fabr).

> **Una fila que no sale no se distingue de un código que no existe.** El 0 es la respuesta
> —*"no hay"*—, no un motivo para callarse.

⚠ El comentario de arriba del filtro **ya decía** *"con búsqueda sí se muestran (para poder
encontrarlos)"* y el código hacía lo contrario. Un comentario que contradice a su propio bloque
es una señal, no un adorno: el que se equivocó casi siempre es el código.

⚠ **Sin buscar el filtro SIGUE valiendo**, o vuelve el ruido de las filas todo-cero.
`tests/stk-buscar-cero.cjs` muerde por los dos lados.

### ⚠⚠ Y la otra mitad, que es la contraria: un código que NO EXISTE no se dibuja (v21.76)

**Luis, 23/09:** *"si busco 865 me muestra el 865 pelado (que no existe), ¿se puede poner un
filtro para que no muestre esos?"*.

> **No es lo mismo un 0 que un fantasma.** La v20.95 dice que un código que EXISTE y está en
> cero **se muestra**, porque el 0 es la respuesta. Acá no hay respuesta que dar: el código no
> es una cosa.

**De dónde salía el 865, medido:** de **dos filas de `Movimientos_Stock`** — un ajuste manual
del 18/08 a las 10:32 (−1) y su reversión a las 10:57 (+1). Alguien tipeó `865` en vez de
`865E` y lo corrigió 25 minutos después. Pero **el universo de stock se arma desde los
MOVIMIENTOS, no desde un maestro de artículos**, así que el código quedó vivo en la pantalla
para siempre: cada error de tipeo en un ajuste deja un fantasma permanente. Eran **19** al
23/09, entre ellos `VASTIDOR`, `H201 PART`, `N° 74` y `FLEJES LOEKEMEYER·0.80 X 64`.

El criterio **no mira el saldo para decidir**: mira si el código existe
(`gv_stock_cod_conocido`, que consulta **siete** maestros). El saldo entra sólo como guard,
para no esconder nunca algo con una caja, un pedido, proyección, capacidad o FC pendiente.

⚠ **Los siete maestros hacen falta los siete.** Con `vista_nombres_articulos` sola se escondían
también **991E, 993E, 996E, 997E y 998E** — que no están ahí pero sí en `vista_uxb_articulo`, y
que se pickean de verdad (el 998E el 22/09). Esconderlos habría sido el pozo de la v20.95.

⚠ **El front NO se tocó**: `_stkSaldosFromView` ya respetaba `visible_en_stock === false` con su
propio guard de saldo y pedidos en cero. El mecanismo estaba; faltaba que alguien marcara estos
códigos. Se marca en **`refresh_stocks_carga_rapida()`**, no en `vista_stock_procesada`: ésa es
una matview y cambiarla obliga a DROP + CASCADE, que ya se llevó puesta `gv_importados_ordenes`
dos veces (v16.20 y v16.33).

**Chequeo:** `select * from public.gv_stock_codigos_fantasma;` — dice cada uno con sus
movimientos y el motivo (*"ajuste mal tipeado que ya se revirtió"*). Al 23/09: **19 filas, 0
con saldo**. `node tests/stk-codigo-inexistente.cjs` (verificado que falla si el flag vuelve a
`true`). `sql/gv_stock_codigos_fantasma_v2176.sql`.

⚠ **Hallazgo aparte, NO es de este cambio:** el **439E** (Colador Pasta) ya venía oculto por la
regla vieja del dual partido —base pelada con stock 0— y tiene **proyección 27 caj/mes y
capacidad 66**. El guard del front sólo exige stock y pedidos en cero, así que hoy no se ve.
Queda reportado; no se tocó.

## ⚠⚠ REGLA (Vivi, 2026-09-23, v22.03): estar PROGRAMADO no garantiza la caja — si no hay stock, no se cobra

**Vivi, textual:** *"si ya no hay stock del 323E, no debo cobrarselo. esa logica no la tenes ya
explicada?"*. La tenía (regla v20.41: el importado sin stock no entra en el monto) y **no estaba
corriendo**.

`gv_clientes_nuevos_valor_lote` y `gv_clin_composicion` reparten los importados escasos con un
greedy por `(fecha_pedido, hora, order_id)`, y le hacían un **atajo** al pedido que ya figura en
`gv_demanda_programada_pendiente`: *"sus cajas ya se contaron en `_prog`, no compite"* → `falta = 0`.

> **El atajo supone que lo PROGRAMADO entra en lo DISPONIBLE. Cuando no entra, la reserva es
> ficticia y el sistema dice "tiene stock" con la góndola vacía.**

**Medido el 23/09 sobre `web LK 1448`** (Silvano, LK 4282, cliente nuevo en cuarentena): sus 3 NP
están en la vista con `tanda = ''` y `fecha_entrega` **NULL** — o sea **desprogramadas** — y aún así
disparaban el atajo. Los **17** importados salían con `cajas_falta = 0` y `valor_importados = 0,00`,
y **7 estaban sobrevendidos**:

| código | disponible | programado |
|---|---:|---:|
| 035E · 323E · 970E · 971E | **0** | 8 · 10 · 3 · 4 |
| 590E | 3 | 64 |
| 583E | 5 | 17 |
| 584E | 15 | 28 |

**Cómo queda:** si de un código hay menos disponible que programado, se reparte lo que hay entre
**toda** la demanda programada por su `prioridad` — que ordena por fecha de entrega, y **la NP sin
fecha va ÚLTIMA**, que es justo el caso del cliente nuevo retenido — y cada pedido se queda con su
parte. Lo que no cubre es `cajas_falta`, sale con `importe = 0,00` y **no se cobra**.

⚠ **Cuando lo programado SÍ entra en lo disponible, `cubiertas = cajas` y el resultado es
idéntico al de hoy**: el cambio muerde sólo en el sobreventa. Verificado con 529E y 812E del mismo
pedido, que siguen en `falta 0`.

⚠ **`cubiertas` queda NULL, no 0, cuando ese código del pedido no tiene fila en la vista** (una NP
ya facturada mientras otra sigue viva). Ahí **no se asume faltante**: cae al greedy normal contra
`libre`. Un `coalesce(..., 0)` habría dicho *"no hay"* sin haber medido nada.

⚠ **El valor_lote llevaba además el doble conteo que la v21.96 ya le había sacado a la
composición.** `order_items` de LK trae **dos filas** para 323E (2+1) y dos para 590E (3+3), y sin
agregar por código antes del greedy cada mitad mide a su hermana como `tomado_antes` — o sea el
pedido peleando contra sí mismo. Ahora las dos funciones tienen su `_itg`.

**Impacto medido**, sobre los 7 pedidos web desprogramados de hoy: **$2.218.883** que dejan de
cobrarse por adelantado (1451 455.881 · 1343 445.041 · 1347 440.940 · 1474 397.637 · 1448 343.730 ·
1482 71.705 · 1349 63.949). Costo como `authenticated`: composición **297 ms**, valor_lote **279 ms**
(el timeout de ese rol es 8 s).

**Chequeo:** `select * from public.gv_reglas_perdidas;` — vacía = todo bien (3 centinelas:
`_vl_progalloc`, `_cp_progalloc`, `_vl_itg`). Probado rompiéndolo a propósito en transacción
abortada: *antes 0 perdidas · con la regla borrada 1 · la nombra sí*.
`sql/gv_clin_falta_programado_sobrevendido_v2203.sql`.

## ⚠ REGLA (Luis, 2026-09-21, v20.88): cuando el registro y el PALLET no coinciden, manda el PALLET

**Luis, textual:** *"Te estoy diciendo que el pedido está armado y se armó otra vez. Si registrás
algo diferente estás yendo contra la realidad física del depósito. Actualmente está allá con un
papel impreso que dice que pertenece a la tanda E03F."*

El caso: **LK 0043 (El Gran Bazar)** se armó el 17/09 y su papel salió con el código **E03F**; en
el sistema la tanda figuraba como **E12L**, porque se había renombrado y el papel quedó con el
nombre viejo. El 21/09 el pedido **se pickeó de nuevo** y el candado anti doble-armado frenó al
operario que iba a armarlo por segunda vez.

**Lo que NO se hace:** "corregir" el papel del depósito desde la base. Se renombra la tanda al
código del papel y se repone lo que el registro había perdido.

- La tanda se renombró `E12L` → **`E03F`** y el armado del 17/09 se repuso tal cual.
- **El segundo picking va a `a_guardar`**, nunca de vuelta a góndola: esas cajas están en un
  pallet, no en el sector.
- El **`TAP` que nunca se dio** se carga con la fecha y el legajo del armado REAL. Sin él, la
  tanda sigue apareciendo en la lista de Armado con el picking cerrado y traba al próximo.

### Un mismo código puede tener DOS usos, y no se mezclan

Al renombrar una tanda **el rastro se va con el nombre nuevo y el viejo queda vacío** (de E03F
sólo quedaba el `lock` en `GV_Tandas_Codigos_Usados`), así que el generador lo puede volver a
entregar. `E03F` ya había sido lo que hoy es `E12R`.

Cada uso se anota por separado en **`GV_Tanda_Codigo_Historia`** y se lee junto, sin mezclar, en
**`gv_tanda_codigo_vidas`**. **Al reusar a mano un código que ya tuvo otra vida, agregarle su
fila** — es un `insert`, no código.

```sql
select codigo, uso, estado, renombrada_a, clientes_hoy from public.gv_tanda_codigo_vidas;
```

### Y el renombre se salteaba la programación web

`gv_ppp_tanda_renombrar` renombra **18 tablas** y no tocaba **`PPP_Web_Programacion`**, la tabla
madre de los pedidos de la página: la tanda quedaba **partida en dos nombres según desde dónde se
la mirara** (stock, picking, armado y factura en el nuevo; la PPP en el viejo). Medido: 0 tandas
web desincronizadas de antes.

⚠ Mismo tipo de agujero que el `ref` compuesto y los pases que eligen fecha: **una lista de
lugares donde hay que replicar algo, y uno que falta. Al agregar una tabla con columna `tanda`,
agregarla también al renombre.** Y se prueba **corriéndolo**: `gv_ppp_tanda_renombrar` tiene que
devolver **5** objetos, no 4.

**Chequeo:** `select * from public.gv_reglas_perdidas;` — vacía = todo bien.
`sql/gv_ppp_tanda_renombrar_prog_web_v2088.sql`, `tests/ppp-renombrar-prog-web.cjs`, §3.lw.
