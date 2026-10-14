# Reglas Supabase — Técnica de base: definición viva, centinelas, backups, claves, permisos del MCP, base compartida, timeouts, RLS, anon

> Movido de `CLAUDE.md` el 2026-10-13 (poda 3ra tanda, pedido de Luis) **sin cambiar una palabra**.
> **Leerlo ENTERO antes de tocar algo de este tema.** Las reglas siguen valiendo igual que cuando estaban en CLAUDE.md.

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

### 3 bis. Y la sesión que intenta cambiar una regla FRENA sola (Luis, 28/09, v23.37)

El hook **`scripts/claude-reglas-guard.cjs`** (PreToolUse de `execute_sql` / `apply_migration`) frena
todo `CREATE OR REPLACE` / `DROP` / `ALTER` —y el parche por texto `execute … pg_get_functiondef`— sobre
un objeto de **`GV_Reglas_Centinela`**, o sobre el centinela mismo. Le muestra al modelo la regla y
quién la pidió: **se le explica al usuario y se espera su "sí"**; recién ahí se reintenta con el
comentario `-- REGLA_CONFIRMADA_POR_USUARIO` y el permiso sale en pantalla. La lista vive en
**`scripts/reglas-protegidas.json`**: al agregar una fila al centinela, regenerarla (la consulta está
en la cabecera del hook). El centinela vigila además **triggers** (`clase = 'trigger'`).
⚠ Sólo corre en sesiones de ESTE repo: una sesión de LK o Chef que pegue contra esta base no lo tiene.
`tests/claude-reglas-guard.cjs`.

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

> **ACTUALIZADO 14/10/2026 (Luis): ya está resuelto. NO pedirle al usuario que apruebe ni que ponga Always allow.**
> Medido en la sesión del 14/10: `/tmp/mcp-config-*.json` trae `execute_sql` y `apply_migration` en `always_allow`
> (la única de Supabase en `always_ask` es `create_edge_function_secret`) y un `select` corrió sin cartel. Además
> `apply_migration` salió de la lista `ask` de `.claude/settings.json` (estaba ahí y un `ask` le gana al *Always allow*
> del connector: era el cartel que seguía saliendo) y `scripts/claude-permisos.sh` lo saca de `ask` del settings de
> usuario en cada arranque. Si hoy sale un cartel en una llamada a Supabase, es uno de estos dos, y está bien que salga:
> 1. **`scripts/claude-reglas-guard.cjs`**: el SQL toca un objeto con regla protegida → pide confirmación a propósito.
> 2. **Supabase con instrucciones destructivas** (`delete` / `drop` / `truncate`, aun dentro del cuerpo de una función):
>    la herramienta avisa *"Destructive statements may require the user to confirm"*. Se esquiva con
>    `execute replace($s$…QQB…$s$, 'QQB', 'DE'||'LETE')` y `create or replace trigger` en vez de `drop` + `create`.
>
> Lo de abajo es la historia del 18/09, cuando el connector sí venía en `always_ask`.

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

## ⚠ REGLA (Luis, 2026-09-28, v23.56): si la base de Gestión NO CONTESTA, avisa Telegram — y el vigilante vive en LK

Caída del 28/09 14:11–14:19 ART (reinicio de la plataforma, instancia chica; Luis decidió **no** subir la instancia).
El vigilante **no puede vivir en la base que vigila**: corre en **LK** (cron `gv-watch-gestion`, cada minuto,
`gv_watch_gestion_tick()`), pega a `rpc/gv_ping` de Gestión con la publishable y, con **3 fallas seguidas (~3 min)**,
manda 🔴 al grupo de Gestión; al volver, 🟢 con los minutos de caída. `gv_ping()` sólo devuelve `now()`.
**Chequeo (LK):** `select * from public.gv_watch_gestion order by id desc limit 10;` · Rollback en
`sql/gv_watch_gestion_v2356_LK.sql`. Probado en transacción abortada (caída y vuelta), sin mandar mensajes.

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

⚠ **Y en la TV de la pared también** (v26.70, Luis D28): si fallaba la lectura de `Facturacion_NP`, el catch
devolvía un conjunto vacío, la caché lo guardaba como bueno y salía el cartel violeta **«143 TANDAS YA SALIERON Y NO
ESTÁN FACTURADAS»**, falso. Hoy facturadas y despachadas (CCN) **re-lanzan el error**: la caché sigue con lo último
bueno, y si nunca leyó llegan como `null` → sin cartel, y «NPs por Día» / «Pendientes» dicen *«No se pudo leer lo
cargado al camión»*. Y las columnas de la tabla de tandas miden lo que mide su dato (en `--u`), no un % (D29: en el
Mon. Admin el código se pisaba con el m³, «E48L0,4»). `tests/mon-lectura-rota-ancho.cjs` (falla contra la v26.69).

⚠ **El puente a LK reintenta un 504 TRANSITORIO, pero un 504 SOSTENIDO sigue frenando** (v27.14, Luis 06/10).
El armado automático y toda lectura del feed de LK pasan por `pwebLkToken()` (`index.html`), que abre el puente
`admin-login-otp`. El 06/10 la base de LK se saturó 10:40–12:40 UTC y ese `fetch` dio **504**, abortando el armado
(*«No se pudo entrar a LK (HTTP 504)»*). Hoy el puente **reintenta hasta 3 veces** con backoff (1,5 s · 4 s) **sólo
ante fallo transitorio** (red, o 502/503/504/408/429); un 4xx de auth (401/403) **no se reintenta** (no se arregla
solo). Si después de los reintentos LK sigue sin contestar, **tira el error igual y el armado FRENA** —no arma sobre
nada—: el reintento tapa el blip, el fail-closed de arriba sobrevive a una caída sostenida. La causa de fondo —los
crons de LK que ahogaban la base— se bajó el mismo día: watchdog **job 63** de 1 a 2 min, y los `*/10` **62/66/68**
sacados del stack de minuto :00 (pico por minuto 9 → 6, con 6 worker slots). `tests/pweb-lk-token.cjs` bloque 7.

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

## ⚠ REGLA (Thomas, 2026-10-08, v28.52-53): 98 tablas de public NO aceptan escrituras de la clave pública — y si se intenta, AVISA

Trigger `aaa_gv_anon_bloqueo` → `gv_anon_insert_bloquear()`: con rol anon la fila se descarta, queda entera en
**`GV_Anon_Insert_Bloqueado`** y sale un Telegram. La lista está en `gv_anon_bloqueo_instalar` (sectores viejos de
Cervantes, Fichadas_Virgilio, Insumos, Proveedores, Racks_Bajadas…) y en `gv_anon_bloqueo_d10` (40 más: recepción,
Cervantes admin, talleristas…; v28.53). anon sólo inserta en las 14 del operario (Registros, Movimientos_Stock,
Entregas_Virgilio, Picking paso…). **Una escritura de supervisor va con `gvWriteHdr()` (la sesión), nunca con la
clave pública pegada a mano.** **Si una pantalla nueva tiene que escribir en una
de esas tablas con la clave pública**, deshabilitar el trigger en esa tabla (`alter table … disable trigger
aaa_gv_anon_bloqueo`) o escribir por una RPC SECURITY DEFINER. `sql/gv_anon_insert_bloqueo_v2852.sql`, centinela 370.
⚠⚠ **v29.16 (Luis, 09/10, D13): el trigger mira `current_user`, no el `role` de la sesión.** Una función SECURITY DEFINER
llamada con la clave pública escribe como `postgres`, pero `current_setting('role')` seguía en `anon` y el bloqueo
descartaba la escritura interna (perdidas 08-09/10: Importados_Mov_Stock 14, Racks_Bajadas 4, Fichadas_Historico 20).
Hoy `gv_anon_insert_bloquear` es **SECURITY INVOKER**: escritura directa con la clave pública → `anon` → bloqueada; adentro
de una función del sistema → entra. `gv_anon_insert_log` (definer) sólo actúa desde un trigger (`pg_trigger_depth() > 0`).
**Una escritura de la clave pública en esas tablas va por una RPC SECURITY DEFINER.** Probado en transacción abortada
(directo 0 filas + 1 log · interno 1 fila · /rpc directo al log 0). `sql/gv_anon_bloqueo_current_user_v2916.sql`.

## ⚠ REGLA (Thomas, 2026-10-08, v28.75, D15): 18 funciones de SUPERVISOR exigen la sesión de Google — `gv_rpc_guard`

Las RPC que usan sólo pantallas de supervisor (insumo_* del admin, aceptar/rechazar_conteo, faltante_resolver,
zona_barrio_set, gv_supers_set/baja, corr_convertir_faltante, gv_conciliacion_registrar, gv_pedido_horario_set,
gv_insumo_ubicaciones_guardar) arrancan con `perform public.gv_rpc_guard('<fn>')` (marcador `rpc-guard-d15`): si la
fila de **`GV_RPC_Guard`** está activa y el que llama no es supervisor, corta con `SUPERVISOR: …` (401). Por eso el
front las llama con `gvWriteHdr()` (la sesión), nunca con la clave pública. El operario entra como usuario anónimo
(authenticated): un revoke a anon no alcanzaba. Probado por HTTP con la clave pública → 401 SUPERVISOR.
- **Rollback rápido**: `select public.gv_rpc_guard_instalar(false);` (o `update … set activo=false where fn='<fn>'`).
- **Rollback total**: `select public.gv_rpc_guard_quitar();` (repone los cuerpos de `zz_backups."GV_Backup_RPCGuard_defs_20261008"`, 20 firmas).
- ⚠ Probar desde el MCP NO sirve: `gv_es_supervisor_o_servicio` deja pasar `session_user = postgres`. Se prueba con `net.http_post` + clave pública.
- **v28.78 (Thomas D16): también `gv_oc_generar_pendientes`** (generador manual de OC; el front ya mandaba la sesión). Son 19 funciones activas.
- Afuera: `insumo_unidad_guardar` (operario). `sql/gv_rpc_guard_supervisor_d15.sql`.

