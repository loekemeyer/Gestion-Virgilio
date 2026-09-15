# Post-mortem del 2026-09-15 — qué se rompió, por qué, y qué lo tiene que frenar

Pedido de Luis, al final del día: *"quiero un análisis de lo que se rompió hoy y por qué (no
puede volver a pasar)"*.

Todo lo de acá está **medido contra la base y contra el repo**, no reconstruido de memoria. Las
consultas quedan escritas para poder repetirlas.

---

## 0. Lo primero: separar dos cosas que hoy se mezclaron

La auditoría (`github_repo_problemas`) tiene **~100 entradas con fecha de hoy**. Eso NO significa
que se rompieran cien cosas hoy. Son dos poblaciones distintas y conviene no confundirlas:

| | |
|---|---|
| **Hallazgos** | Bugs viejos que las auditorías del día encontraron (Planify sin validar contraseñas, RLS abierta, liquidación, talleristas…). Estaban ahí desde antes. Que aparezcan es *bueno*. |
| **Roturas** | Cosas que **dejaron de funcionar hoy, en la cara del operario**. Son las de este documento. |

Este post-mortem es sólo sobre las **roturas**, que son tres clases con causas distintas.

---

## 1. Clase A — bombas de tiempo: nadie las rompió hoy, vencieron hoy

### A1. El picking dejó de ver los artículos (problema 268, crítico)

**El síntoma:** JC no podía arrancar el picking de `E25A` — *"no hay cajas disponibles"* cuando
tenía que haber 20 cajas de 607E. `D71A` aparecía sin códigos. Y `E01G` se armó mostrando
códigos que durante el picking nunca se habían visto, así que hubo que desarmarla entera y
devolver el stock.

**La causa:** PostgREST corta toda respuesta en **1000 filas** (`db-max-rows`). La lectura de
`PPP_Web_Base` no paginaba. La tabla venía creciendo desde que el pipeline arrancó:

```sql
select (creado_at at time zone 'America/Argentina/Buenos_Aires')::date dia, count(*),
       sum(count(*)) over (order by (creado_at at time zone 'America/Argentina/Buenos_Aires')::date) acum
from public."PPP_Web_Base" group by 1 order by 1;
```

```
06/09   313    313
08/09   174    535
10/09   192    899
12/09    13    976     ← todavía entraba
14/09   121   1097     ← CRUZÓ el corte
15/09   211   1308
```

**El 14/09 la tabla pasó las 1000 filas.** El 15/09 el picking empezó a fallar. No es casualidad:
es el día siguiente.

**Por qué nadie lo vio venir, y esto es lo importante:** el corte **no da error**. PostgREST
contesta **HTTP 200** con 1000 filas y se queda tan tranquilo. No hay excepción, no hay log, no
hay nada que mirar. Y como las filas vienen ordenadas, **lo que se pierde es lo más nuevo**: los
pedidos recién cargados. Por eso pegó justo en las tandas del día.

### A2. Facturación trabada (problema 299, crítico)

`gv_ppp_np_valor` tardaba **28,3 s** contra un `statement_timeout` de 8 s → HTTP 500. Misma
familia: una subconsulta correlacionada que escaneaba `GV_UxB` (984 filas) **una vez por cada
línea de pedido** — 10.969 veces. Funcionó durante meses porque había menos pedidos.

**Las dos son el mismo problema de fondo: código que anda bien con pocos datos y se rompe solo
cuando los datos crecen, sin avisar.**

---

## 2. Clase B — regresiones: éstas sí las metimos hoy

| Problema | Qué rompió | Lo introdujo |
|---|---|---|
| **272** (alto) | Franco no podía agarrar **su propia** tanda `E11B`: el candado se la marcaba como tomada por otro | el candado de la **v18.31**, de hoy |
| **287** (alto) | El chip «seguir» abría la tanda **sin lo ya pickeado** | la **v18.46**, de hoy |
| **301** (crítico) | Facturación moría con `_facGuardadoHoy.has is not a function` | la **v18.29** metió una lectura en el medio del `Promise.all` y no corrió los índices de abajo |
| **298** (alto) | El picking guardado en el celular seguía mostrando la lista recortada **después** del fix | el snapshot local sobrevivía al arreglo |
| **269** (medio) | La suite quedó en rojo | el stub del test no devolvía `headers` |

Las tres primeras son **fixes que rompieron otra cosa**. No es mala suerte: es la consecuencia
directa del punto 3.

---

## 3. Clase C — el multiplicador, que es el problema de verdad

### 58 versiones en 8 horas

```bash
git log --since="2026-09-15 00:00" --pretty=format:"%s" | grep -o "^v18\.[0-9]*" | sort -u | wc -l
# 58   (75 commits en total)
```

Por hora, el pico fue a la tarde: **15 commits entre las 13 y las 14 ART, 13 más entre las 14 y
las 15**. Una versión cada ocho minutos, con varias sesiones de Claude trabajando en paralelo
sobre el mismo `main`.

### Y con ese ritmo, el CI dejó de existir

60 corridas hoy:

| | |
|---|---|
| ✅ success | **23** |
| ⏹ cancelled | **21** |
| ❌ failure | **16** |

**21 canceladas.** El workflow tiene `concurrency: cancel-in-progress: true`, así que **cada push
mata la corrida del anterior**. Con un push cada ocho minutos y una suite que tarda cinco o seis,
la red de seguridad casi nunca llegó a terminar. Y de las que sí terminaron, **16 quedaron en
rojo** — entre ellas la **v18.43**, que era justamente el fix del corte de 1000 filas.

(Ese rojo en particular era del *stub del test*, no de la app — problema 269. Pero eso se supo
después: en el momento, nadie lo miró.)

⚠ Y ya había precedente escrito en el propio `ci.yml`: *"el nombre decía DESHABILITADO pero el
workflow SEGUÍA corriendo, y fallaba siempre, así que main quedaba en rojo permanente y **el rojo
dejaba de significar algo**"*. Hoy volvió a pasar por otra vía.

### Encima, los fixes no llegaban al celular

**`version.json` estuvo congelado en v12.77** (problema 241) — cinco versiones mayores. Ése es el
archivo que dispara el aviso «🔄 Actualizar» de la app abierta. O sea: mientras se pusheaban 58
versiones, **el operario no se enteraba de ninguna** y seguía con el `index.html` viejo cacheado.

### Y la versión fue para atrás tres veces

Problemas **255** y **290**: `main` con commits hasta v18.35 y el badge diciendo v18.30. Sesiones
en paralelo tomando el mismo número y pisándose.

---

## 4. El hilo que une todo: **fallan en silencio**

Si hay una sola conclusión de hoy, es ésta. Mirá el patrón:

| Lo que falló | Qué avisó |
|---|---|
| Corte de 1000 filas de PostgREST | **nada** — HTTP 200 |
| CI cancelado por el push siguiente | **nada** |
| `version.json` congelado 5 versiones | **nada** |
| El lock de tanda que vence a las 10 h | **nada** |
| `GV_Tanda_Anulada` con RLS y sin policies | **nada** — devuelve 0 filas |
| `gv_ppp_np_valor` degradándose hacia los 8 s | **nada**, hasta pasarlos |

**En los seis casos el sistema siguió "andando" y el primero en enterarse fue el operario con el
celular en la mano.** No fue un problema de nadie por distraído: el que tenía que avisar era el
sistema, y no avisó.

---

## 5. Qué lo frena — por orden de lo que más duele

### 5.1 Un centinela del corte de 1000 (es el que faltaba, y hoy ya hay tres pasadas)

Medido ahora mismo:

| Relación | Filas | |
|---|---|---|
| `gv_ppp_base_pedidos` | **9.664** | ya corta |
| `PPP_Web_Base` | **1.308** | ya corta |
| `Facturacion_NP` | **1.265** | ya corta |
| `gv_ppp_programacion_diaria` | 123 | ok |

Las tres primeras ya están del otro lado del corte. Hoy se arreglaron **las lecturas que sabemos
que muerden** (268 y 288), pero eso es ir apagando incendios de a uno. Lo que hace falta es una
vista que compare cada relación que la app lee contra el umbral y avise **antes**, no después —
el mismo patrón que ya usa `gv_endpoints_rotos`, que ya cazó dos veces un DROP CASCADE.

Y como regla de código: **toda lectura de tabla que crece va por `supaFetchAll` con `order=`
explícito.** Hoy hay 45 lecturas paginadas y varias decenas de `fetch` directo; no todas son
peligrosas (muchas filtran por tanda o traen una fila), pero ninguna está clasificada. Eso hay que
barrerlo una vez y dejarlo anotado.

### 5.2 Que el rojo del CI vuelva a significar algo

Hoy no sirvió por dos motivos distintos, y hay que arreglar los dos:

- **Se cancela.** Con `cancel-in-progress` y un push cada 8 minutos, no llega a correr. O se saca
  la cancelación para `main`, o se agrupan los pushes.
- **Nadie lo mira.** Un push con la suite en rojo hoy llega igual a GitHub Pages, o sea al
  celular del operario.

### 5.3 Bajar el ritmo — es la causa raíz de toda la clase B

**58 versiones en 8 horas es insostenible y se nota en los números**: las tres regresiones de hoy
(272, 287, 301) son fixes apurados que rompieron otra cosa. Un cambio validado y pusheado cada
media hora hubiera arreglado lo mismo con menos daño. El propio `CLAUDE.md` ya lo dice para los
pushes especulativos: *"una validada le gana a tres especulativas"*.

Agravante propio de cómo trabajamos: **varias sesiones de Claude en paralelo sobre el mismo
`main`**, tomando el mismo número de versión y pisándose (problemas 255 y 290).

### 5.4 Lo que ya quedó hecho hoy

- `version.json` se mueve con el script de bump (v18.28) → el aviso «Actualizar» volvió a salir.
- `tests/version-sync.cjs` falla si los cuatro lugares se desalinean.
- El monitor ya no acusa a nadie por una tanda desarmada a propósito (v18.58).

### 5.5 Lo que quedó pendiente y conviene no perder

- **`anular_picking_virgilio`**: la ventana de 24 h es un amortiguador, no un guard. El
  `delta = 0` no filtra por legajo ni por fecha, así que puede poner en cero el picking bueno de
  otro. Hay que rechazar si la tanda ya tiene TP o TAP y acotar el `delta = 0`. Recién ahí
  ampliar la ventana.
- **El lock de tanda vence solo a las 10 h** (`tanda_reservar`), así que una tanda con el picking
  abierto queda libre para que cualquiera la reabra. De ahí salen los EP fantasma (6 en 120 días).
- **Problema 262**, abierto: un picking abandonado no le avisa a nadie.

---

## 6. Resumen en cinco líneas

1. **Dos bombas de tiempo vencieron el mismo día** (el corte de 1000 filas y una query que no
   escala) y las dos fallan en **silencio**, con HTTP 200 y con timeout.
2. **Tres de los fixes de hoy rompieron otra cosa**, porque se empujaron a un ritmo de una
   versión cada ocho minutos.
3. **El CI no protegió nada**: 21 de 60 corridas canceladas por el push siguiente, 16 en rojo.
4. **Los fixes no llegaban** al celular del operario: el aviso de actualizar estaba roto desde
   hacía cinco versiones mayores.
5. Todo lo anterior comparte una sola cosa: **el sistema no avisa cuando se rompe**. Ésa es la
   deuda a pagar, no los bugs de a uno.
