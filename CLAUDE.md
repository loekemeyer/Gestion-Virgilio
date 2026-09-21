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
3. **Un `hooks` mal formado tira el archivo ENTERO, sin avisar.** El formato viejo
   —`{"matcher":"", "command":"..."}`— ya no vale; hoy va con el array `hooks` anidado:
   ```jsonc
   "hooks": { "SessionStart": [ { "matcher": "",
     "hooks": [ { "type": "command", "command": "echo hola" } ] } ] }
   ```
   Con el formato viejo la `permissions.allow` deja de existir y no se tira ningún error. Así
   estuvo este repo desde el commit `542ab7e` (16/09) hasta la v19.63.
4. ⚠ **En Auto, un `allow` "peligroso" se descarta a propósito**, y el log lo dice:
   `Ignoring dangerous permission Bash(*) from .claude/settings.json (bypasses classifier)`. Por
   eso un `"Bash"` pelado en `allow` **no** hace que Bash deje de pasar por el clasificador.
   Las reglas con comando concreto (`Bash(git status:*)`) sí valen.
5. ⚠ Un `ask` matchea por **prefijo del comando**: `Bash(git push:*)` **no** agarra
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

## ⚠ REGLA (Luis, 2026-09-21, v20.86): el PIPELINE **reemplazó** al submódulo de clientes nuevos

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
que salir en 2 días hábiles. `sql/gv_clin_dos_estados_v2086.sql` (vigente) y
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
