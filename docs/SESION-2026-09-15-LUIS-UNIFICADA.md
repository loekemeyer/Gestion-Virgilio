# Log del 2026-09-15 — las DOS sesiones de Luis, unificadas

> **Para qué es este archivo:** que otra sesión pueda retomar el día sin releer los chats. Lo que
> está cerrado va primero y corto; lo que queda abierto y las trampas aprendidas están al final,
> que es lo que de verdad hay que leer.
>
> **Quién pidió:** Luis (Rial Otero, Planify `employee_id = 52`), en las dos.
> **Repo:** `loekemeyer/Gestion-Virgilio` · todo pusheado a `main`.
>
> | | Sesión | Qué |
> |---|---|---|
> | **A** | [session_01UbPBqhtM…](https://claude.ai/code/session_01UbPBqhtM88KDGZ78Aia293) | Cuarentena, Anular pedidos, Config. Cuarentena — **§1 a §7** |
> | **B** | [session_015qGyNXfR…](https://claude.ai/code/session_015qGyNXfRbLQeswCrJZaLZK) | Visual de Programación, Imprimir, En Salida — **§8** |
>
> Unificado el 15/09 desde la sesión B, que además **cerró el §5.3 de la A** (los tres tests que
> estaban rojos en `main`) y de paso destapó un bug real por hacerlo.

---

## 1. Lo que se entregó, en orden

| Versión | Commit | Qué |
|---|---|---|
| **v18.01** | `5488461` | Cuarentena (A Programar) pasa de fichas a **lista/tabla**, con la fecha del pedido y comentarios. Y el arreglo del botón "Ya pagó" (**problema 205**). |
| **v18.04** | `49b8359` | Botón **Anular pedido** en Cuarentena y en Pedidos a programar, con log. Y el pedido cancelado que volvía solo (**problema 213**). |
| **v18.05** | `16bcc7a` | La **NP** de un pedido anulado: queda registrada, y ahora se ve. Más el barrido de toda la PPP. |
| **v18.06** | `0ab5341` | **Config. Cuarentena**: el log se ve entero, scrollea la pestaña y no el submódulo. |

Entre medio, `main` se movió por otras sesiones (v18.00, v18.02, v18.03): hubo que rebasar y
**renumerar dos veces**. Si esto se retoma, mirar `git log` antes de elegir número de versión.

---

## 2. Pedidos textuales de Luis y qué se hizo con cada uno

### 2.1 "Que los pedidos A programar en cuarentena se vean más como lista/tabla" → v18.01

*"…parecida a la visualización de los que ya están programados. Que conserven los badges y toda
la info, agregales la fecha del pedido, el botón ya pagó me parece que no hace nada, agregales la
opción de poner comentarios"*.

- `aprColCuarentena()` dibuja `<table class="cuar-tbl">` con **NP · Pedido · m³ · Cliente · Zona ·
  Motivos · Contacto · Enviar a · Coment.** No se perdió nada de la ficha (chip de cliente, m³,
  zona, badge de horario, badges de motivo, la flechita que abre el contenido, los botones).
- **Fecha del pedido**: `fecha_recep` en `dd/mm` + el chip `⏱ hace N días`.
- **Comentarios**: el 📖 abre el MISMO pop-up que los ya programados (misma tabla, misma clave,
  misma identidad obligatoria). Contador por RPC de lote.
- Se borró el CSS de las fichas, que quedó sin uso.

### 2.2 "El botón Ya pagó me parece que no hace nada" → tenía razón (problema 205)

**Nunca escribió una fila.** `gv_cuarentena_pago` abortaba **siempre** con
`42702 column reference "empresa" is ambiguous`: la función declara OUT params llamados `cod` y
`empresa`, y adentro hacía `insert … on conflict (empresa, cod)` — plpgsql no sabe si ese target
es la columna o la variable. Medido recreando la definición vieja con otro nombre y llamándola.
`GV_Cuarentena_Pagados` estaba vacía desde el 2026-09-11.

Arreglado con `on conflict on constraint "GV_Cuarentena_Pagados_pkey"`. Segundo defecto en la
misma función: guardaba el par **crudo** del pedido, pero la deuda se evalúa contra el padrón que
resuelve `gv_cuarentena_ident` (Tierra del Fuego → Chef), así que para esos 9 clientes tampoco
habría matcheado. Ahora guarda **los dos pares**.

**⚠ Ojo:** en la v18.04 Luis pidió **sacar** el botón, así que la RPC quedó **arreglada pero sin
usar** desde la pantalla. Está sana si algún día se la vuelve a colgar de un botón.

### 2.3 "Sacá Ya pagó; agregá un botón para anular el pedido" → v18.04

*"…lo saca de «a programar», a usarse para pedidos que entran erróneos, que quede el log de
pedidos que se anulan y que requiera confirmación y comentario (quién lo hace y por qué)"* y, en
Pedidos a programar, *"visto debajo del detalle de la NP cuando se expande"*.

**Tres cosas parecidas que NO son lo mismo** (quedó escrito en el código y en la doc):

| | para qué | toca stock | la página del cliente |
|---|---|---|---|
| **Anular** | el pedido entró **mal** y no tiene que salir nunca | no | no se toca |
| **Desarmar** (`gv_ppp_np_desarmar`) | ya se pickeó/armó | sí, vuelve a `a_guardar` | no se toca |
| **Borrar** (regla del `CLAUDE.md`) | sacarlo de todos lados | — | **sí**, en los dos proyectos |

- Botón `✕ Anular pedido` en Cuarentena (debajo del verde) y en Pedidos a programar (**sólo con la
  ficha expandida**, debajo del detalle, como pidió Luis).
- El cuadro pide **quién** (obligatorio, como aprobar/devolver) y el **motivo**, que acá **también
  es obligatorio** (≥ 5 caracteres). Después `confirm()` con pedido, motivo y persona.
- Chip `✕ N anulados` en la cabecera de Pedidos a programar → abre el log de los últimos 90 días.
- **Guard:** si la tanda ya se empezó a trabajar, el backend se niega y manda a Desarmar.

### 2.4 Problema 213 — un pedido web CANCELADO volvía solo y el cron lo re-armaba

Apareció mirando lo anterior. `gv_ppp_np_cancelar` (v15.55) escribía en `GV_Web_Cancelados` y
ponía `tanda = null`, y contestaba *"fuera de la PPP; no vuelve a entrar"*. **A esa tabla no la
leía nadie** — ni `gv_pedidos_web_excluidos` (la que decide qué entra a A Programar, y que usan
los crons 71 y 73) ni ninguna vista. Con `tanda = null` el pedido volvía a contar como pendiente.

**Caso vivo:** el pedido web **LK 1375** (Andser Química SRL, cod 3905) se canceló el **11/09**
*"Cancelado por el cliente"* y tenía otra vez **NP LK 0052, tanda E22A, entrega 2026-09-28**.

Arreglado: `gv_pedidos_web_excluidos` suma el motivo **`anulado`**. El lado ISIS nunca tuvo el bug
(`gv_ppp_isis_sin_tanda` ya excluye `NP_Canceladas`).

### 2.5 "¿Qué pasa con el código de NP?" → v18.05

**La respuesta es sí, y ya era así antes:**

- `PPP_Web_NP` (empresa, np, order_id, np_idx) **no se toca** al anular. Ninguna función del
  proyecto borra filas de esa tabla (`prosrc ~ 'delete from … PPP_Web_NP'` → 0).
- El próximo número sale de **`max(np) + 1`**, así que **no se recicla nunca**: queda un hueco a
  propósito. Medido: antes y después de anular el 1375, la próxima NP de LK sigue siendo **86**.
- Si el **mismo** pedido se reprograma, recupera **su misma NP**.
- Los huecos que hay hoy en LK (**65, 79, 80, 81**) son de pedidos **borrados**, no anulados.

**Lo que faltaba era verlo**: el log guardaba `np_label`, la etiqueta de *pantalla*, que para un
pedido web es el número de **pedido** (`web LK 1375`), no la NP (`LK 0052`). Se agregó la columna
`np` a `GV_Pedidos_Anulados`, resuelta en el backend desde `PPP_Web_NP`.

**"Fijate a lo largo de la PPP" — se midió con control positivo**, anulando el 1375 dentro de un
`DO … raise exception` y contando en qué vistas seguía apareciendo `LK 0052`:

| | dónde aparecía |
|---|---|
| **antes** de anular (control) | `gv_np_prog` · `gv_ppp_detalle_dia` · `gv_ppp_web_estado` |
| **después** | **`gv_ppp_web_estado`** ← el único que quedaba mal |

Las demás la sueltan al perder la tanda. Esa decía `sin_programar`; ahora dice **`anulado`** (o
`desarmado` según el motivo). **Segunda asimetría:** `gv_fac_armado_sin_facturar` excluía
`NP_Canceladas` (ISIS) pero no `GV_Web_Cancelados` (web) — corregido; control positivo: marcando
cancelado el pedido lk/1344, el centinela pasó de **8 a 6 filas**.

### 2.6 "Config. Cuarentena: no puede estar así el submódulo" → v18.06

*"…se tiene que ver la tabla sin scrollear en el submódulo, scrolleando en la página en sí si hace
falta"*.

Eran **dos cosas encimadas**: el log tenía scroll propio (`max-height: calc(100vh - 430px)`) **y**
`pppFitPantalla` no tenía excepción para `cuarcfg`, así que le aplicaba el **zoom** y le ponía
`overflow-y: hidden`. Ahora `cuarcfg` va en la misma lista que `prog` y `plan`.

Medido con 18 filas: zoom 1, scrollea la pestaña, sin barra vertical ni horizontal a 1340px; en
430px conserva el scroll horizontal, que ahí sí hace falta.

---

## 3. Objetos de base (proyecto `hrxfctzncixxqmpfhskv`)

### Creados

| Objeto | Qué | Archivo |
|---|---|---|
| `GV_Pedidos_Anulados` (tabla) | el log de anulados, con snapshot completo. **RLS on, sin policies** | `sql/gv_pedido_anular.sql` |
| `gv_pedido_anular(text,text,text,text,text,boolean,jsonb)` | anula: efecto + guard + log | `sql/gv_pedido_anular.sql` |
| `gv_pedidos_anulados(integer)` | lee el log | `sql/gv_pedido_anular.sql` |
| `gv_cuarentena_comentarios_lote(jsonb)` | cuenta comentarios de toda la lista en una vuelta | `sql/gv_cuarentena_comentarios_lote_v1801.sql` |

Grants de las cuatro RPC: `authenticated` + `service_role`, **nada para `anon`**.

### Modificados

| Objeto | Cambio | Archivo (definición viva) |
|---|---|---|
| `gv_cuarentena_pago(text,text)` | `on conflict on constraint` + resuelve identidad | `sql/gv_cuarentena_pago_v1801.sql` |
| `gv_pedidos_web_excluidos(jsonb)` | motivo `anulado` | `sql/gv_pedidos_web_excluidos.sql` |
| `gv_ppp_web_estado` (vista) | estados `anulado` / `desarmado` | `sql/gv_ppp_web_estado_v1805.sql` |
| `gv_fac_armado_sin_facturar` (vista) | excluye también los web cancelados | `sql/gv_fac_armado_sin_facturar_v1805.sql` |

Backups de las definiciones previas: `sql/backups/gv_cuarentena_pago_pre_v1801.sql` y
`sql/backups/gv_pedidos_web_excluidos_pre_v1804.sql`.

**El efecto de anular usa lo que ya existía**, no un mecanismo nuevo: ISIS → `NP_Canceladas` +
`GV_PPP_Prog_Override.oculto`; web → `GV_Web_Cancelados` + sacarle la tanda a
`PPP_Web_Programacion` + borrarlo de `GV_PPP_Web_Retenido`.

---

## 4. Auditoría y Planify — todo cerrado

**Problemas** (`github_repo_problemas`):

- **205** — *"Cuarentena: el botón «Ya pago» nunca funcionó — gv_cuarentena_pago abortaba con
  42702"*. Cerrado en `5488461`.
- **213** — *"Un pedido web CANCELADO vuelve solo a A Programar y el cron lo re-arma (LK 1375 ya
  tiene tanda E22A)"*. Cerrado en `49b8359`.

**Tareas de Planify de Luis (52)**, las cuatro `done = true`:

| id | Tarea |
|---|---|
| 3389 | Cuarentena A programar en tabla + comentarios |
| 3391 | Anular pedidos en A Programar y Cuarentena |
| 3392 | NP de un pedido anulado: que quede registrada |
| 3394 | Config. Cuarentena: el log sin scroll propio |

> ⚠ La 3389 se creó primero por error en el Planify de **Tomás Beviglia (20) con prefijo `Th `**,
> porque la sesión arrancó identificando al usuario por el mail del dueño. Luis avisó *"soy luis"*
> a mitad del turno y se movió a `employee_id = 52`. **Al abrir sesión, preguntar quién habla: el
> mail de la sesión no alcanza.**

---

## 5. ⚠ LO QUE QUEDA ABIERTO

### 5.1 El pedido LK 1375 sigue con tanda E22A para el 28/09

Está cancelado desde el 11/09 y el cron le puso tanda igual (ése fue el problema 213). **El
arreglo evita que vuelva a pasar, pero no saca la tanda que ya tiene.** No se tocó: el protocolo
del `CLAUDE.md` prohíbe modificar datos sin permiso explícito.

Se resuelve solo con el botón nuevo (Cuarentena o A Programar → `✕ Anular pedido`), o a pedido.
Para ver si sigue así:

```sql
select w.empresa, w.order_id, w.np, w.tanda, w.fecha_entrega, w.razon_social
  from public."PPP_Web_Programacion" w where w.empresa='lk' and w.order_id=1375;
```

### 5.2 La página del cliente le dice "sin programar" a un pedido anulado

`gv_pedido_web_estado_pagina` —lo que ve el **cliente** en la página de LK— mapea el estado a un
rango 1..8 y devuelve el nombre por índice; un estado que no conoce cae en el `ELSE 1`. **No se
cambió a propósito: que el cliente vea "anulado" es una decisión comercial del dueño.** Si se
decide que sí, hay que tocar esa vista (no `gv_ppp_web_estado`, que ya devuelve el estado real).

### 5.3 ~~Tres tests que ya fallaban en `main`~~ → **CERRADO** en la v17.98 (sesión B)

El diagnóstico de acá era correcto: `ppp-plan-nueva`, `ppp-reprog-boton` y `ppp-prolijo` fallaban
en `main` sin los cambios de esta sesión. Los arregló la sesión B, y valió la pena mirarlos:

- **`ppp-plan-nueva` y `ppp-prolijo`** medían el tablero de 6 días **sin declarar
  `_pppPlanTabla = false`**, y desde la v17.66 la vista por defecto de Programación es la tabla:
  dibujaban otra pantalla. En `ppp-prolijo` los chequeos **en negativo** pasaban **solos**.
- **`ppp-reprog-boton`** buscaba una frase del cartel de Atrasados que **nunca existió** en el
  código; se reescribió contra la intención, no contra la redacción exacta.
- Y como `run.sh` corre con `set -e`, el corte en el primero **tapaba los otros dos**.

⚠ **Lo que apareció al arreglarlos**: con `ppp-plan-nueva` en verde quedó **un** chequeo rojo que
sí era un bug real (**problema 203**, ya cerrado). La v17.72 mudó el padrón de súper a `gv_supers`
y pasó el fallback "fila vieja de ISIS sin cód" al campo `nota`, pero `pppSupersNeed()` nunca pidió
esa columna en el `select` ni la copió en el `.map()`: **el fallback nació muerto en la misma
versión que lo escribió**. Efecto en pantalla: el camión salía `Camión 5 · Inc Sociedad Anonima`
en vez de `Camión 5 · Carrefour`. Las 19 filas activas de `gv_supers` tienen `nota` y **14 son la
razón social**.

**La moraleja para el próximo:** un test rojo que "no es de esta sesión" igual hay que arreglarlo,
porque mientras esté rojo **tapa todo lo que venga después** en la batería.

---

## 6. ⚠ Trampas encontradas — leer antes de tocar algo parecido

1. **`CREATE OR REPLACE VIEW` sin `WITH (...)` BORRA las `reloptions`** → se come el
   `security_invoker = true`, y una vista sin eso corre como `postgres` y **saltea la RLS**. Pasó
   acá con `gv_ppp_web_estado` y `gv_fac_armado_sin_facturar`; se detectó en el momento y se
   repuso con `alter view … set (security_invoker = true)`. **Ya quedó escrito en el `CLAUDE.md`**
   con el chequeo de que no queda ninguna suelta.
2. **`ON CONFLICT (col)` dentro de plpgsql revienta si la función tiene un OUT param con ese
   nombre** (`42702`, ambiguo). Usar `ON CONFLICT ON CONSTRAINT <pk>`. No se pueden renombrar los
   OUT params: definen el tipo de retorno.
3. **Agregar una columna al retorno de una función obliga a `DROP FUNCTION`** — `create or
   replace` da `cannot change return type of existing function`.
4. **`position:sticky` se ancla al ancestro con `overflow` distinto de `visible`.** Poner
   `overflow-x:auto` en el contenedor de una tabla mata el encabezado fijo.
5. **Los `.sql` del repo pueden estar desactualizados respecto a la base.**
   `sql/gv_pedidos_web_excluidos.sql` no tenía `SECURITY DEFINER` ni el `pg_temp` del
   `search_path`: aplicarlo tal cual habría roto A Programar. **Comparar contra
   `pg_get_functiondef` antes de aplicar un archivo viejo**, y dejar la definición viva en el repo.
6. **Medir con control positivo, siempre.** "No cambió nada" también es el resultado de una
   condición que no hace nada. Todo lo de esta sesión se probó dentro de `DO … raise exception`
   para que se revirtiera, con un caso que **debía** cambiar al lado del que no.
7. **`main` se mueve.** Otras sesiones pushean en paralelo; hubo que rebasar y renumerar dos veces.
   Mirar `git log --oneline -1 origin/main` antes de bumpear.

---

## 7. Archivos tocados

**Front / app:** `index.html`, `sw.js`
**Reglas:** `CLAUDE.md` (regla nueva del `CREATE OR REPLACE VIEW`)
**Doc:** `docs/SUPABASE-GESTION-VIRGILIO.md` → **§3.ge** (v18.01), **§3.gh** (v18.04),
**§3.gi** (v18.05), **§3.gj** (v18.06)
**SQL:** `sql/gv_pedido_anular.sql`, `sql/gv_cuarentena_pago_v1801.sql`,
`sql/gv_cuarentena_comentarios_lote_v1801.sql`, `sql/gv_ppp_web_estado_v1805.sql`,
`sql/gv_fac_armado_sin_facturar_v1805.sql`, `sql/gv_pedidos_web_excluidos.sql`,
`sql/backups/gv_cuarentena_pago_pre_v1801.sql`, `sql/backups/gv_pedidos_web_excluidos_pre_v1804.sql`
**Tests:** `tests/apr-cuarentena.cjs` (sumó ~39 chequeos), `tests/apr-contenido-np.cjs`

Cómo correr lo relevante:

```bash
node tests/apr-cuarentena.cjs      # Cuarentena, anular, log, Config. Cuarentena
node tests/apr-contenido-np.cjs    # el detalle del pedido al expandir
node tests/checkhtml.cjs && node tests/smoke.cjs && node tests/dead-handlers.cjs
```

---

# 8. Sesión B — Programación (visual + imprimir) y En Salida

> **Sesión:** https://claude.ai/code/session_015qGyNXfRbLQeswCrJZaLZK · pedidos de **Luis**.

## 8.1 Lo que se entregó

| Versión | Commit | Qué |
|---|---|---|
| **v17.94–17.96** | `4d66d8a`, `f360387`, `12b774e` | El visual de la tabla de Programación: letra pareja, sangría cero, y el contenido de la NP en las 6 celdas que estaban vacías. |
| **v17.98** | `56dc196` | 🖨 **Imprimir la Programación**. Y los 3 tests rojos de `main` + el **problema 203**. |
| **v18.02** | `d0d5f5d` | La hoja impresa: el cód dentro del cliente, y los anchos salidos del dato. |
| **v18.03** | `033cd4c` | La hoja deja de **adivinar** el ancho del papel. |
| **v18.07** | `e2a5d2e` | **En Salida**: días hábiles, la vista 4× más rápida, y el camionero que ya estaba. |

## 8.2 Imprimir (v17.98 → v18.03) — lo que hay que saber

Botón `🖨 Imprimir` al lado de `🔄 Actualizar`; pop-up con un renglón por día (m³ / tandas / NP),
rango Desde/Hasta, y la hoja sale **abierta hasta la NP y sin el contenido de cada NP**.

Tres decisiones que no son obvias y conviene no deshacer:

1. **No se abre ventana nueva.** Entre el click y el `print()` hay un pop-up, y el navegador la
   bloquea si el click no la disparó directo. La hoja se arma en `<div id="pgaPrint">` y un
   `@media print` esconde todo lo demás.
2. **El pop-up se cierra ANTES del `print()`** (de ahí el `setTimeout` de 60 ms): si no, sale
   impreso encima de la hoja.
3. ⚠ **Nada de anchos en px contra un ancho de papel supuesto.** La v18.02 medía contra
   `718 px` (190 mm a 96 dpi) y elegía el font en px; el útil real del navegador al imprimir es
   más ancho, así que las columnas —calculadas en % sobre ese 718— quedaban más anchas de lo que
   el texto necesitaba: **letra chica Y aire entre columnas, las dos quejas por la misma causa**.
   La v18.03 lo pasa todo a unidades relativas: columnas en **%** y el font en **vw** (el CSS de
   la hoja va en `em` para que escale junto). Medido a cuatro anchos — 600/718/860/1000 px → font
   13,6 / 15,8 / 19,6 / 22,0 px, y **cada columna usa el 100 %** de su ancho, sin cortar nada.

Y la columna del cliente se dimensiona por el **percentil 90**, no por el máximo: un solo
`Coto C.I.C.S.A. Sucursal Lanus Centro (LK 801)` entre 102 NP le fijaba el ancho y achicaba la
letra de toda la hoja por una fila. Ese 10 % largo parte en dos renglones.

`tests/pga-imprimir.cjs` — 50 chequeos, incluido el control directo: viewport a 718 px, `media
print`, y **ninguna celda** con `scrollWidth > clientWidth`.

## 8.3 En Salida (v18.07)

- **`dias_sin_controlar` pasa a días HÁBILES** (`gv_dias_habiles()`, que reusa `gv_es_dia_habil()`
  y ya mira `planify.feriados` + `GV_Dias_No_Habiles`). El chip salta a amarillo a los 2 días: con
  calendario, un pedido cargado el **viernes** salía en amarillo el **lunes** habiendo pasado 1 día
  de trabajo; con el feriado del 07/09 en el medio, 4 en vez de 1.
- **451 ms → 113 ms.** ⚠ El diagnóstico de arranque estaba **mal** y sólo lo salvó medir: se había
  dicho que el costo eran los cuatro escaneos de `Registros_Produccion_Virgilio`; medido pieza por
  pieza son **2,9 ms**. El costo real era `gv_ppp_entregados_meta` — **213 ms de los 410**, y la
  vista la llamaba **dos veces**. Lo caro de esa vista es su CTE `vivo`, con 3 LATERAL por NP con
  remito para resolver cod/rs/tanda/m³, datos que En Salida **no usa**; y `vivo ⊆ crn`, que la
  vista ya excluye. Se lee `GV_PPP_Entregados_Historico` directo, con el mismo filtro.
- **Columna `camionero`**, aditiva. El dato **ya viajaba** en el evento desde la v11.47
  (`texto = NP|TANDA|CAMIONERO`) y la vista leía sólo los dos primeros campos. **25/25** NP de En
  Salida lo tienen. **El front todavía NO lo pinta** — queda listo para cuando se pida.

`sql/gv_en_salida_habiles_y_perf_v1807.sql` · §3.gk · rollback en
`zz_backups."GV_Backup_Funcdefs_20260915"`.

## 8.4 ⚠ LO QUE QUEDA ABIERTO de la sesión B

### 8.4.1 Los pedidos facturados NO pasan a En Salida — **esperando a Thomas**

Pedido de Luis: *"que los pedidos facturados vayan automáticamente a En Salida con el badge
Esperando carga o Esperando retiro según corresponda"*. **No se tocó nada.**

Eso **ya existía** (v13.62) y **Thomas lo apagó** en la v15.85: *"en En Salida no puede haber
ningún pedido sin fecha, ni pedidos que no se hayan cargado a un camión"*. Y en la v16.00 se le
volvió a plantear el caso exacto (la 98530, armada y facturada sin carga) y eligió un **botón
manual por NP** en vez de cambiar la regla. O sea: es el caso (b) del `CLAUDE.md` —dos reglas del
dueño en conflicto— y Luis confirmó: *"no hagas nada, lo confirmo con thomas"*.

**Medido el 15/09:** 30 NP facturadas sin carga en la programación viva — **22 con fecha ≥ hoy**
(21 ISIS + 1 Retira) y **8 vencidas** (11 al 14/09).

**Propuesta para cuando Thomas conteste**, que respeta las dos mitades de su regla: entran sólo
las de **fecha ≥ hoy**; las vencidas siguen cayendo en la lista de vencidos. Y es barato: el chip
**ya está escrito** en `_pppEsChips` (hoy dice *"⚠ Sin registro de carga"*) y el estado
`facturada_sin_cargar` ya existe en la vista. Prenderlo es
`update "PPP_Web_Config" set valor = 0 where clave = 'en_salida_solo_cargadas'` —o mejor, una
llave nueva que además filtre por fecha— más renombrar el chip a *Esperando carga* / *Esperando
retiro* (`zona ~* 'retira'`). **Planify 3366.**

⚠ Y conviene que Thomas mire **las dos juntas**: `armada_sin_carga` (v15.55) se apagó en el mismo
movimiento y probablemente la respuesta sea la misma.

### 8.4.2 Mejoras de En Salida propuestas y NO pedidas

Se ofrecieron cuatro; Luis pidió las dos primeras (hechas, §8.3). Quedan:

- **Aviso proactivo**: el chip *"N días hábiles sin controlar"* sólo se ve si alguien abre la
  solapa. Ya existe el cron de Telegram de las 10:30 al que engancharlo. Hoy hay 0 casos, pero el
  21/08 hubo 8 que estuvieron 3 días.
- **Pintar el camionero** en la pantalla (la columna ya está en la vista, §8.3). Para reclamar un
  remito, saber a quién reclamárselo es la mitad del trabajo.

---

## 9. Estado del día al cerrar

**Tareas de Planify de estas dos sesiones:** todas cerradas **salvo la 3366** (§8.4.1), que espera
a Thomas.

**Lo que sigue abierto y no es de nadie todavía:** §5.1 (el **LK 1375** de Andser Quimica sigue
cancelado **y** con tanda `E22A` para el 28/09 — verificado el 15/09; se resuelve con `✕ Anular
pedido` o a pedido, no se toca por el protocolo de datos) y §5.2 (qué ve el cliente en la página
para un pedido anulado — decisión comercial del dueño).
