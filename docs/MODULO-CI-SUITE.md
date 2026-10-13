# CI / suite de tests — disciplina y mecánica

> Movido de `CLAUDE.md` el 2026-10-13 (poda de reglas, pedido de Luis) para que no cargue en cada sesión.
> Es documentación operativa VIVA del módulo, no se resume: leer ENTERA antes de tocar este módulo.

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
a ignorar el rojo. **Y uno que falla según la HORA, lo mismo** (v26.47): `mon-tv`, `mon-admin` y
`monitor-abandonado` armaban sus fixtures con `Date.now() − 1,5 h` y entre las **00:00 y las 03:00 ART** eso cae AYER, así
que la página los descartaba (CI 1700, a las 00:09 ART). Hoy fijan el reloj de la página a las **15:00 ART de hoy** con
`page.clock.setFixedTime(T0)` y arman las fixtures contra ese `T0`. **Un test que simula «hace N horas» fija el reloj**; no
depende de a qué hora corre CI. Se arregla midiendo **la regla** (están los dos atajos fijos; el del miércoles
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
