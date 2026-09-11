# HANDOFF — Artículos sin planimetría · línea Acacia · aviso de alta en recepción

> **Para la sesión que siga esto.** Escrito el **2026-09-11** (viernes) por Claude, sesión
> `https://claude.ai/code/session_01APFvJScy9GAzAR6xUTYe8t`, hablando con **Thomas**.
> App en **v15.39** al cerrar.
>
> Antes de tocar nada leé `CLAUDE.md` y `GUIA-PROYECTO.md` (notas **v15.34**, **v15.35** y
> **v15.39**) y `docs/SUPABASE-GESTION-VIRGILIO.md` **§3.bn** y **§3.bn.1**.

---

## 1. Lo que hay que decidir (lo único abierto)

**Thomas todavía no contestó esto:**

> ¿**991E** (Espátula Corta Torta Mgo Acacia) se baja o se queda?
>
> - **Se baja** → Acacia queda en **7** activos y esos 7 necesitan sector. La tarea Planify
>   **3105** (Luis) sigue como está, con los 4 códigos.
> - **Se queda** → son **8** los Acacia que necesitan sector, y hay que sacar 991E de la 3105
>   (quedarían sólo 994E, 995E, 999E).

Lo último que dijo fue *"en paginalk [son] 8 ahora"*, confirmando que en la web ve 8 Acacia
activos (los 7 + 991E). No dijo si lo baja.

**Lo otro sin resolver:** la **NP LK 0024 / tanda E09B** (Osa Distribuidora 2533, 5 cajas de 578,
entrega 09/09) está **colgada**: la tanda se abrió 4 veces y nunca se pickeó. Se lo reporté, no
dijo qué hacer.

---

## 2. Artículos ACTIVOS del catálogo LK sin sector en planimetría

Verificado el 11/09. `Planimetria` tiene **360 códigos** sobre **685 sectores** de
`Capacidad_Sector`, así que lugar sobra.

La consulta cruda devuelve **15**. Thomas sacó dos a mano:

- **517** (Pinza Acero Inox 25cm) — lo sacó él, sin explicar por qué. **No insistir.**
- **991E** — sale por su regla de la Acacia (§4), pero **sigue activo en la web**. Es la
  decisión abierta de §1.

**Quedan 13:**

| Cód | Artículo | ¿Se pickeó? |
|---|---|---|
| 231 | Palo de Amasar 30cm | sí (10/09) |
| 232 | Palo de Amasar 40cm | sí (10/09) |
| 233 | Palo de Amasar 50cm | sí (10/09) |
| 368E | Rallador Hexagonal Inox 25cm | no, sólo pedido web 10/09 |
| 537 | Pela y Pica ajo | sí (10/09) |
| 567 | Corta Palta | sí (11/09) |
| 989E | Rallador de Limón Mgo Acacia | sí (10/09) |
| 990E | Corta Ravioles Mgo Acacia | no, sólo pedido web 06/09 |
| 992E | Batidor Pera Mgo Acacia | sí (01/09) |
| 993E | Pelador V Mgo Acacia | sí (02/09) |
| 996E | Corta Pizza 9cm Mgo Acacia | sí (02/09) |
| 997E | Rallador 3 En 1 Mgo Acacia | sí (10/09) |
| 998E | Abrelatas Doble Engranaje Mgo Acacia | sí (01/09) |

**7 de los 13 son la línea Acacia entera** → si se les carga sector, conviene que vayan juntos.

**Aparte: `578` (Descarozador de Aceitunas).** NO está activo en la web, pero se pickeó — o mejor
dicho, **NO se pickeó**: ver §5. Tampoco tiene sector.

Ninguno de los 13 tiene saldo en `Movimientos_Stock deposito='gondola'`.

### Cómo regenerar la lista

`Planimetria` está en Gestión (`hrxfctzncixxqmpfhskv`) y `products` en LK
(`kwkclwhmoygunqmlegrg`) — **son dos proyectos distintos y NO hay `postgres_fdw` entre ellos**, así
que no se puede hacer un join. Hay que sacar la lista de códigos de uno y pegarla en el otro:

```sql
-- (1) en GESTIÓN — sacar los códigos que YA tienen sector
select string_agg(distinct ''''||norm_cod(cod)||'''', ',') from public."Planimetria";

-- (2) en LK — pegar esa lista en el VALUES y correr
with p as (select regexp_replace(upper(trim(cod)),'^0+(.)','\1') n, cod, description, category
             from public.products where active),
     plani(c) as (values ('101'),('102E') /* …pegar acá lo del paso 1… */)
select p.cod, p.description, p.category
  from p where p.n not in (select c from plani) order by p.cod;
```

⚠ El cruce va **normalizado** (mayúsculas, sin ceros a la izquierda): `norm_cod` en Gestión,
`regexp_replace(...,'^0+(.)','\1')` en LK. Sin eso `027` no cruza con `27`.

---

## 3. Alertas de planimetría que NO son huecos reales

Las tres reglas que dio Thomas el 11/09. Están en `GUIA-PROYECTO.md` nota **v15.34**.

### (a) Códigos de 5 dígitos → nunca llevan planimetría

Dueño: *"los de 5 dígitos es sólo para un cliente y no se stockea en góndola; cuando llega se
guarda en racks nomás"*. Son de **un único cliente**, no pasan por góndola, entran a **racks**.
**Si aparece un PSP/RSP con un código de 5 dígitos, se ignora.** Los que ya saltaron: `55215`
(Palo de Amasar 40cm), `55219` (Prensa Matambre), `55289` (Colador de Mano Verde).

### (b) `599`, `943`, `948` → recepciones mal tipeadas

Dueño: *"están mal recibidos, sólo existe con la E al final"*. Los reales son **599E** (J44),
**943E** (I08) y **948E** (I11), los tres **con** sector. Mismo patrón que 029→437E de la v5.08.

### (c) PSP se dispara al ABRIR la tanda, no al pickear

`pkNotifySinPlanim` corre cuando el picking arma la lista. Un PSP repetido = "la tanda se abrió
N veces", **no** "se pickeó N veces". Para saber si algo se levantó de verdad hay que mirar
**PKC** (`texto = TANDA|COD|pedido|pickeado`).

---

## 4. Línea Acacia: lo que no se pide en la 2da Becky no debería existir

Regla del dueño (11/09): *"todos los 99xE que no se pidan en la 2da Becky son artículos que no
deberían estar en todo Gestión Virgilio ni en `pagina-LK-copia`"*, y **989E entra en la misma
lógica** (misma familia, aunque el código no arranque con 99).

**La familia es 989E + 990E…999E.** Referencia: el **2.º pedido de importación de Becky**
(`GV_Importados_Baches.creado_por = 'PI B260601-2'`, reingreso **2026-11-15**, 26 líneas /
48.056 uni). El 1.º es `PI B260601`, reingreso 29/09.

- **Se piden → quedan (7):** `989E` (576) · `990E` (576) · `992E` (576) · `993E` (1.152) ·
  `996E` (576) · `997E` (576) · `998E` (576).
- **NO se piden → no deberían existir (4):** `991E` · `994E` · `995E` · `999E`.
  - `994E` y `999E` **tenían** línea en la 2da Becky, pero quedó **`anulado`** (`backfill_20260911`).
  - `991E` y `995E` **ni siquiera tienen ficha** en `Importados`.

### Dónde siguen apareciendo los 4 (barrido completo de los dos proyectos, 11/09)

| | 991E | 994E | 995E | 999E |
|---|---|---|---|---|
| GV `Importados` (ficha) | — | 1 | — | 1 |
| GV `GV_Importados_Baches` | — | 1 anulado | — | 1 anulado |
| GV `Importados_Mov_Stock` | — | 1 | — | 1 |
| GV `Importados_Volumen` | — | 1 | — | 1 |
| GV `PPP_Web_Base` | 1 (NP LK 0013, pedido 1347) | — | — | — |
| GV `Volumen_Articulos` · `cob_uxb_lk` · `precios_venta` | 1+1+1 | 1+1+1 | 1+1+1 | 1+1+1 |
| LK `products` · `product_m3` · `item_precio_cache` | sí | sí | sí | sí |
| LK `order_items` | 6 líneas | 8 | 7 | 12 |

**Ninguno de los 4 tiene sector en `Planimetria`** — y está bien así, no hay que cargárselo.

🔴 **991E sigue `active = true` en el catálogo LK y se está vendiendo.** Último pedido web
**10/09** (pedido 1389, cliente 4198), antes el **04/09** (pedido 1347, cliente 2363 → NP LK 0013).
994E, 995E y 999E ya están inactivos desde mayo; sus 27 líneas de `order_items` son pedidos
históricos de marzo–mayo, todos `status='pendiente'`.

**NO SE BORRÓ NADA.** Por el protocolo de "NUNCA modificar datos sin permiso explícito", la baja
quedó esperando. Está en la tarea Planify **3105** (Luis). Cuando se ejecute: **backup antes de
cada borrado**, y **los `order_items` viejos NO se tocan** (son historia de pedidos; borrarlos
rompe los totales).

### Cómo regenerar el barrido

`query_to_xml` sobre `information_schema` permite buscar el código en **todas** las columnas
`cod*` / `articulo` / `codigo` de un proyecto sin escribir la consulta a mano:

```sql
with cols as (
  select c.table_name, c.column_name
  from information_schema.columns c
  join information_schema.tables t
    on t.table_schema = c.table_schema and t.table_name = c.table_name and t.table_type = 'BASE TABLE'
  where c.table_schema = 'public'
    and c.data_type in ('text','character varying','character')
    and (c.column_name ilike 'cod%' or c.column_name in ('articulo','codigo','cod_art','cod_isis'))
    and c.column_name not ilike '%cliente%' and c.column_name not ilike '%prov%'
    and c.table_name not ilike '%bkp%' and c.table_name not ilike '%backup%' and c.table_name not ilike 'zzz%'
), r as (
  select table_name, column_name,
    (xpath('/row/c/text()', query_to_xml(
      format('select count(*) c from public.%I where upper(btrim(%I::text)) in (''991E'',''994E'',''995E'',''999E'')',
             table_name, column_name), false, true, '')))[1]::text::int n
  from cols
)
select * from r where n > 0 order by table_name, column_name;
```

---

## 5. Por qué se cargaron 599/943/948 mal (y qué se hizo al respecto)

Thomas preguntó si lo había agregado la operadora o el operario solo. **Fue el operario, solo.
En ese flujo no existe ningún paso de operadora.**

- Remito **38087**, 02/09 16:29, tallerista **Log/ Fabr** (0001), línea LK, **legajo 277**.
- `Control_Modo_OP` guardó el detalle tal cual: **"599 → 16 · 943 → 3 · 948 → 16"**.
- La lista de Log/Fabr LK tiene 32 códigos y **no está ninguno de los tres** → los agregó con el
  botón **"+"**, que abría un `prompt` y daba de alta **cualquier cosa**: sin validar, sin
  autorización, sin avisarle a nadie.
- Fue error de tipeo, no desconocimiento: en los remitos anteriores del mismo tallerista está
  bien escrito (38060 07/08 `943E`+`599E`, 38062 13/08 `599E`, 38085 31/08 `599E`).
- **Rareza sin explicar:** el stock quedó **bien** (599E/943E/948E en `Movimientos_Stock`, mismo
  remito y mismo segundo). El trigger `fn_canon_cod_art` **no** hace esa conversión
  (`canon_cod_art_val('599')` = `'599'`), así que **alguien lo corrigió después a mano**.
  `Movimientos_Stock` no tiene `updated_at` → no se puede decir quién ni cuándo.

### Caso 578 / tanda E09B — ojo con esto

**578 NUNCA se pickeó.** Tiene 4 eventos PSP (08/09, 09/09 ×2, 10/09) y **cero PKC**. Es la tanda
**E09B** = NP **LK 0024**, Osa Distribuidora (2533), 5 cajas, entrega **09/09**: se abrió cuatro
veces y quedó **sin EP, sin TP, sin TAP y sin carga camión**. Es el `E09B` de la regla v14.12 (web
separado del ISIS `E09A`, que sí cerró completo). **Sigue colgada.**

---

## 6. Lo que se construyó (v15.36 → v15.39) — ya está en producción

Pedido del dueño: *"si en la recepción están por recibir un artículo nuevo que no figuraba en la
planimetría, me mandan un mensaje directo a WhatsApp, a mi teléfono, 'hola Thomy, estoy creando un
artículo nuevo, que es el tanto, ¿me confirmás que está bien?'"*.

⚠ **Corrección del mismo día, y es la regla que manda:** *"no quiero que quede bloqueado a que yo
les conteste, porque capaz les contesto una hora después. Quiero que quede asentado el mensaje y
que una vez que lo mandan, ellos sí puedan seguir dando la recepción"*. La **v15.36 trababa** el
`Enviar`; la **v15.39 lo sacó**. Hoy **no traba nada**.

- Tabla **`GV_Alta_Articulo_Aprobacion`** (RLS ON, única policy `gvaa_sel` = SELECT para anon).
  Con la anon key **sólo se lee** → desde el celular no se puede auto-aprobar.
- Edge Function **`gv-alta-articulo`** (`verify_jwt=false`, v4, fuente en
  `supabase/functions/gv-alta-articulo/index.ts`). Manda el WhatsApp a **5491162521635**
  (Thomas, `planify.employees` id 3) vía `send-whatsapp` con `plantilla:"_texto_libre"`.
- El link de respuesta **necesita dos toques** (`&c=1`): el preview de WhatsApp pega un GET y, si
  el primero resolviera, **contestaría solo**.
- **Respaldo por Telegram** si Meta rechaza (ventana de 24 h cerrada).
- Front `recepcion.js` (`?v=15.39`): badge 🆕 / 🆕 ✅ / 🆕 ⛔, línea informativa en el resumen,
  y **sin conexión tampoco traba**.
- Regresión **`tests/rcp-alta-ok.cjs`** (16 chequeos) en `tests/run.sh`.

⚠ **NO se probó de punta a punta**: el entorno de Claude no tiene salida a `*.supabase.co`, así
que nunca se disparó un WhatsApp real. **Hay que probarlo desde el celular** → tarea Planify
**3107**.

⚠ Si Thomas contesta **que no** con la recepción ya cerrada, **el sistema no revierte nada**.
Queda el asiento y la próxima vez que alguien escriba ese código el "+" avisa *"Thomy ya había
dicho que NO"*. Revertir es a mano.

---

## 7. Tareas de Planify abiertas de esta charla

| id | Nombre | Asignada a | Estado |
|---|---|---|---|
| **3105** | Bajar Acacia 991E/994E/995E/999E de GV y web LK | **Luis Rial Otero (52)** | abierta — espera el OK de Thomas |
| **3107** | Th Recepcion: alta de articulo nuevo pide OK por WhatsApp | Tomás Beviglia (20) | abierta — falta probar desde el celular |

```sql
select id, name, employee_id, done, note from planify.tasks where id in (3105, 3107);
```

---

## 8. Cosas del entorno que conviene saber

- **No hay salida de red a `*.supabase.co` desde el sandbox de Claude** (el proxy devuelve 403 en
  el CONNECT). Se puede usar el MCP de Supabase para SQL y para deployar Edge Functions, pero
  **no** se puede pegarle por `curl` a una función ni probar un webhook.
- **`get_edge_function` falla** ("Failed to retrieve function bundle") para algunas funciones
  (`planify_send-wa`, por ejemplo). `send-whatsapp` sí se pudo leer.
- **No hay acceso al proyecto Supabase de Chef** (`nkhzocgdpwtgrmwleihr`): devuelve "You do not
  have permission". Por eso el cruce de planimetría se hizo sólo contra el catálogo de LK; lo de
  Chef se verificó nada más por lo que ya se pidió (`PPP_Web_Base` empresa='chef').
- **El `main` local del contenedor estaba podrido** (59 commits adelante / 52 atrás de
  `origin/main`, versión v14.33 contra v15.33). No se usó: los push se hicieron con
  `git push origin <rama>:main`. Si aparece de nuevo, **no mergear el `main` local**.
- **Otra sesión estuvo pusheando a `main` en paralelo** (idea 4259, "completar desde a guardar") y
  usó el **mismo número de versión**. Por eso esta rama terminó en v15.39. Antes de pushear:
  `git fetch origin main` y mirar si hubo choque de número.
- **`tests/ap-resume.cjs` viene fallando de antes** y no es de este trabajo (verificado con
  `git stash`). El resto de `tests/run.sh` pasa.
