# Log de sesión — 2026-09-15 · Cuarentena, Anular pedidos y Config. Cuarentena

> **Para qué es este archivo:** que otra sesión pueda retomar esto sin releer el chat. Está
> escrito para unificarse con otro log: lo que ya está cerrado va primero y corto; lo que queda
> abierto y las trampas aprendidas están al final, que es lo que de verdad hay que leer.
>
> **Quién pidió:** Luis (Rial Otero, Planify `employee_id = 52`).
> **Sesión:** https://claude.ai/code/session_01UbPBqhtM88KDGZ78Aia293
> **Repo:** `loekemeyer/Gestion-Virgilio` · todo pusheado a `main`.

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

### 5.3 Tres tests que ya fallaban en `main` antes de esta sesión

Comprobado con `git stash` (fallaban igual sin los cambios de acá): `ppp-plan-nueva`,
`ppp-reprog-boton` y —una vez— `ppp-prolijo`, que después pasó. **No son de esta sesión**, pero
están rotos y nadie los está mirando.

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
