# Reglas Monitor Horas — Monitor / TV / Mon. Admin, horas, tiempo muerto, alarma de inactividad, ritmo, plantel, análisis productivo

> Movido de `CLAUDE.md` el 2026-10-13 (poda 3ra tanda, pedido de Luis) **sin cambiar una palabra**.
> **Leerlo ENTERO antes de tocar algo de este tema.** Las reglas siguen valiendo igual que cuando estaban en CLAUDE.md.

## ⚠ REGLA (Luis, 2026-09-29, v23.86): se arma POR CAMIÓN — y a las 15:00 la TV dice si llegan

- **Orden de armado = `gv_monitor_tanda_camion.orden_camion`**: por día, 1° el camión con más m³, Retira al final.
  La botonera del celular (`populateTandasList`) ordena las tandas de cada día así, con rótulo «🚚 N° · camión» si el
  día tiene más de uno. Sin el dato, orden alfabético. Objetivo: si no llegan, se patea UN camión entero, no dos a medias.
- **TV → tarjeta «¿Llegan?»**: meta = hoy + 2 hábiles (norma armar → facturar → salir). Trabajo = m³ × (½ picking + ½
  armado); ritmo = lo terminado hoy ÷ horas desde las 8; capacidad = ritmo × horas hasta las 17. Lo atrasado va primero.
  Si no alcanza, se marcan «✗ no» los ÚLTIMOS camiones del orden hasta que el resto entre. **Desde las 15:00** sale el
  cartel rojo de CORTE con los camiones a pasar de día en la PPP. Es aviso: no mueve nada.
- `sql/gv_monitor_tanda_camion_orden_v2386.sql`, `tests/tv-meta-camion.cjs`, `tests/tandas-orden-camion.cjs`.

## ⚠⚠ REGLA (Luis, 2026-10-13, v29.96): EN EL MONITOR SÓLO VAN LOS LEGAJOS QUE SE LOGUEARON

**Luis, textual:** *"se habrá hecho como una prueba para ver visuales desde el admin, no deberían
aparecer esas cosas en el monitor. solo legajos que se hayan logueado (trabajadores o entrevistas)"*.

> **Un evento suelto no hace a un operario.** Para figurar en el monitor hay que haber ENTRADO a la
> app ese día (`GV_Dispositivo_Login`, `tipo = 'operario'`), **con cualquier método**.

| pieza | qué hace |
|---|---|
| `gv_monitor_horas_operario_dia` (CTE **`login_dia`**) | la fuente: TV, 📺 Vista TV y Mon. Admin lo heredan por `gv_monitor_horas_operario` |
| **`gv_monitor_logueados(desde, hasta)`** | la misma pregunta para el front (lectura, anon, ventana ≤ 8 días) |
| `index.html` `fetchMonitorDayStats` | la lee y filtra igual, así el monitor del index y la vista siguen ≡ |

- **CUALQUIER método de login, no el de llegada.** `gv_monitor_ingresos` (v27.68) corta por
  `clave_tv` / `nombre` porque contesta *"¿a qué hora llegó?"*; acá la pregunta es *"¿entró?"*.
  Medido: con el criterio de llegada se caían **7 días-operario reales** que entraron con
  `sesion_guardada` (30/09 leg 104/8/94 · 02/10 leg 277 · 06/10 leg 191/237 · 08/10 leg 277).
- **FAIL-OPEN, y por eso no hay fecha de corte**: si ese día no hay NINGÚN login registrado, no se
  filtra a nadie. `GV_Dispositivo_Login` empezó el **30/09**, así que sin esa cláusula todos los
  días anteriores quedaban vacíos (y el fixture del 15/09 roto). Sirve igual el día que la
  registración de ingresos se caiga: se ve de más, nunca de menos.
- **El filtro es la salida de un legajo de prueba, no su anulación.** El caso que lo originó: el
  legajo **1** apareció «en jornada» el 13/10 por **un** `RI` suelto hecho desde el admin. Se anuló
  (`RI` → `RIX`, backup `zz_backups."GV_Backup_RegLeg1_20261013"`) **y el monitor lo seguía
  mostrando**: el CTE `base` de la vista filtra `''`, `'0'` y `sup:*`, pero **NO saca las opciones
  terminadas en `X`**. Lo que lo saca es esta regla.
- ⚠ **El legajo 1 sigue contando en el monitor** cuando SÍ se loguea (v27.63, Thomas D13): esto no
  lo excluye, le pide haber entrado.
- ⚠ **El patrón del centinela es `login_dia`, no el marcador `v29.90-login`**: ése vive en un
  comentario y el centinela los saca antes de buscar (regla v21.82) — probado, daba «LA REGLA SE
  PERDIÓ» con la regla puesta. `GV_Dispositivo_Login` tampoco sirve: aparece 2 veces y la otra es
  la regla v27.54. Centinela 422, huella re-congelada.
- ⚠ **Los marcadores de la base, el centinela y los comentarios del front dicen `v29.90`**: es la
  versión con la que se aplicó, antes de que otra sesión se llevara ese número. **Es la llave, no
  se cambia.**

**Chequeo:** `select * from public.gv_monitor_horas_operario;` · `select * from public.gv_reglas_perdidas;` ·
`select * from public.gv_huellas_cambiadas;` · `node tests/mon-solo-logueados.cjs` (corre la pantalla:
el que no se logueó no sale, el que sí sale, y el fail-open; verificado que falla contra la v29.92) ·
`node tests/mon-vs-vista.cjs`. `sql/gv_monitor_solo_logueados_v2996.sql`.

## ⚠ REGLA (Luis, 2026-10-13, v29.90): en el MONITOR, el día dice CUÁNDO DEBIÓ ARMARSE

**Luis, textual:** *"quiero que en el monitor, en el día figure así: «Mié 14/10 (debió armarse Vie 9)»
o «Vie 16/10 (debe armarse Mié 14/10)»"*.

> **El dato es el VERBO.** «debió» = esa fecha de armado YA PASÓ, o sea que ese día de reparto
> viene atrasado. «debe» = todavía hay tiempo.

| pieza | qué hace |
|---|---|
| **`restarHabiles(key, n)`** (`monitor/tv.html`) | el espejo de `sumarHabiles`: mismo criterio de día hábil (finde + `GV_Feriados`, con la lista de respaldo si el fetch falla) |
| **`diaArmado(key)`** | armado = **salida − 2 hábiles** (norma de Thomas del 23/09, v21.56: se arma el día 1, se factura el 2 y sale el 3 — es la misma cuenta que ya hacía `calcularMeta` con `sumarHabiles(hoy, 2)`). Devuelve `{fecha, txt, vencido}` |
| cuadro **«NPs por Día»** | el texto va en el `<small>` de la celda del día (que `.rd td small` ya dibuja en bloque): **no ensancha la columna** — regla de espacio del 28/09 |
| rojo (`.rd-arm.tarde`) | sólo si la fecha de armado **ya pasó Y** ese día todavía tiene NP sin armar (pendiente + proceso neto). Una fecha vieja de un día que ya salió entero no es un atraso. **El color no va solo**: el verbo lo dice igual |

⚠ **Es la TV y lo hereda Mon. Admin** (`monitor/build-admin.cjs` se arma de `tv.html`). El monitor
de `index.html` no tiene este cuadro. `monitor/tv.html` queda **afuera del sistema GV-UI** a
propósito (regla v29.83): acá manda su escala en `--u`.

⚠ **El caso difícil es el feriado, y es justo el ejemplo de Luis:** dos hábiles antes del
**miércoles 14/10** son el **viernes 9**, no el lunes 12, porque el 12/10 es feriado. Contar días
corridos da el número equivocado tres veces por mes.

**Chequeo:** `node tests/mon-dia-armado.cjs` — corre la TV con el reloj fijo en el martes 13/10 y
mide los dos ejemplos textuales de Luis, el caso «debe armarse hoy» y que la columna no se
ensanche. Verificado que falla al sacar la etiqueta, al ignorar los feriados y al correr el límite
del verbo.

### ⚠⚠ Y el LEGAJO DE PRUEBA entraba al monitor por el cierre de insumos

Lo que destapó el pedido: el 13/10 el monitor mostraba al **legajo 1 «en jornada»** con un cierre
de Recepción de Insumos (12:32→12:33) **sin su apertura**. `insEmitCierre` era la **única**
escritura de un evento de operario que llamaba a **`_enqueueReportRaw` DIRECTO**, salteándose el
gate que `enqueueReport` (`esOperadorPrueba`) y `enqueueAutoClose` (`esLegajoPrueba`) sí tienen:
la apertura la descartó el gate y el cierre salió igual.

> **Un cierre huérfano no se distingue de una tarea abierta**, así que
> `gv_monitor_horas_operario_dia` lo lee como jornada viva — y el legajo 1 cuenta en el monitor
> desde la v27.63 (Thomas, D13), así que queda ahí con el tiempo muerto corriendo.

**Al escribir un evento de operario se llama a `enqueueReport`.** `_enqueueReportRaw` es la lógica
interna y **no tiene candado**: quien la use directo se lo pone él. Hoy son tres llamadores y los
tres filtran el legajo de prueba. Lo sostiene el bloque **(d)** de `tests/legajo1-confirma.cjs`,
que lo mide sobre la cola de verdad (verificado que falla sin el guard).

## ⚠ REGLA (Luis, 2026-10-13, v29.68): ANÁLISIS PRODUCTIVO por tanda — y el s/caja del PKC NO es un detector

**Abre en el DÍA DE LA FECHA** (Luis, 13/10, v30.20; supervisor y Juan igual): lista las tandas de hoy, y el
botón **«Días anteriores»** pasa a los 30 días previos **sin** el de hoy (pide 31 y saca las de `hasta`, el
hoy del servidor). **Sólo esos dos botones** («Hoy» / «Días anteriores»), sin chips de 7/14/30/60 (Luis, v30.21). Lo sostiene el bloque (j) de `tests/analisis-productivo.cjs`.

Botón **📈 Análisis Productivo** en el panel del supervisor y en la botonera del operario (ahí **sólo** para
los legajos de `GV_Analisis_Acceso`; hoy **Juan, legajo 8**). El monitor ya evalúa por OPERARIO y por DÍA
(Monitor → Ritmo, v29.47-48): esto es la misma cuenta abierta **por TANDA**, con el detalle código por código.

| pieza | qué hace |
|---|---|
| `gv_analisis_lista(dias, legajo, buscar)` | las tandas del período con el rendimiento de picking y de armado, su dificultad y **cuántos avisos DUROS** tiene cada una (se calculan para todo el período de una, 1,4 s a 60 días) |
| `gv_analisis_tanda(tanda, legajo)` | el detalle: esperado por dificultad vs real, composición del tiempo (bruto · pausas · huecos · cola), m³/h, cajas/h, el promedio de ese operario y el del depósito en esa dificultad, la tabla línea por línea y los avisos (260 ms) |
| `gv_analisis_cod_base(dias)` | cuánto tarda **normalmente** una línea de cada código: mediana de 120 días, y la misma mediana descontando el término por caja del D17 (3,74 s). 194 de 289 códigos tienen 8+ líneas medidas y cubren el 96 % |
| `GV_Analisis_Acceso` | quién lo ve desde el celular. Agregar a alguien es un `insert`, no un deploy |

> ## **El `ts` del PKC dice cuándo se TOCÓ OK, no cuándo se levantó la caja.**
> Medido el 13/10 sobre 120 días: marcar «menos de 1 s por caja con 5+ cajas» salta en **148 de 560 tandas
> (26 %)**, y agrupando las ráfagas en **283 de 588 (48 %)**. Eso no es fraude: es que se confirma en bloque.
> Por eso el s/caja del PKC va como **dato** en la tabla, con lo normal del código al lado, y **no dispara
> una alarma por sí solo**. No volver a proponerlo como detector.

**Los tres avisos que SÍ tienen señal, y por qué:**

1. **El picking dio completo y el armado declaró faltante** de ese código. No depende del reloj.
   Medido: **14 casos en 13 de 486 tandas (2,7 %), 44 cajas**.
2. **Paso confirmado sin tiempo frente a la góndola**: del registro por paso (`GV_Picking_Paso_Evento`,
   v26.25, **desde el 05/10**), de que la pantalla MOSTRÓ el código a que se confirmó. Mediana **29 s**,
   p10 7,1 s; **36 de 1.081 pasos (3,3 %)** bajan de 2 s. Con el filtro de 3+ cajas quedan **6 pasos en 6
   tandas**, más 10 con menos de 1 s por caja en 5+ cajas. Una tanda anterior al 05/10 no tiene este dato y
   la pantalla lo dice: **no se inventa el aviso**.
3. **El conteo cíclico de góndola de ese picking** (CG, v28.58) que no coincide con el sistema.

El resto (línea lenta, huecos de +5 min, celular bloqueado, reconfirmaciones, sin stock en góndola,
ritmo alto o bajo contra su dificultad) va como **media/baja**: son para mirar, no para acusar.

⚠ **El tiempo «frente a la góndola» es desde el ÚLTIMO `mostrado` anterior a la confirmación**, no desde el
primero: `gv_picking_paso.primera_vez` es el primero y da negativos cuando la cola manda el `mostrado`
después del `ok`. Con el primero el aviso saltaba en el 46 % de las tandas; con el último, en el 13 %.

⚠ **No es un candado**: el legajo lo manda el celular y no se puede verificar (el operario entra con el
código de la TV, no con una sesión). Frena a quien lo lee, como el semáforo de repos. El supervisor entra
por su sesión de Google.

⚠ El marcador de la regla va en **código** (`v_regla constant text := 'v29.64-acceso'`), no en un comentario
de línea: el centinela saca los comentarios antes de buscar (regla v21.82) y el patrón quedaba en rojo.

**Chequeo:** `select public.gv_analisis_lista(14, '8');` · `select public.gv_analisis_tanda('<TANDA>', '8');` ·
`select * from public.gv_reglas_perdidas;` · `node tests/analisis-productivo.cjs`.
`sql/gv_analisis_productivo_v2964.sql`, `analisis.js`. ⚠ Los objetos de la base y los centinelas dicen
**v29.64** (la versión con que se aplicaron): es la llave, no cambiarla.

## ⚠ REGLA (Thomas, 2026-10-06, v27.53): la alarma de 5 MIN de tiempo muerto también la decide el SERVIDOR

Caso Franco Ortiz (237): entró a la app 08:29 y su primera tarea fue 10:37 — 2:08 sin que sonara nada, porque la
alarma (`_tmAlertaAbrir`, v25.82) la disparaba sólo el celular con la botonera en pantalla. Thomas (D8): *"tiene que
andar a pesar de que pase en la app"*.

- **`gv_alerta_inactivo_servidor(p_simular, p_ahora)`** (security definer, sólo postgres) — cron **136**
  `gv-alerta-inactivo-servidor`, `1-59/2 10-21 * * *` (07:00–18:58 ART), con anti-solape.
- En jornada = ingresó hoy (`GV_Dispositivo_Login`) o registró algo hoy, sin FJ después. Última actividad =
  max(primer ingreso, último evento no `X`). **No avisa**: tarea abierta (EP/AP/MGI/RKI/IRI/toggles sin cierre, < 12 h),
  fuera de 7–18 h o día no hábil, < 5 min, o ya avisado desde la última actividad.
- Abre en `GV_Alerta_Inactivo` con `dispositivo = 'servidor'` (la misma tabla que lee la TV) y cierra la viva cuando
  vuelve la actividad. **El celular sigue avisando igual**: los dos escriben la misma tabla.
- Probar sin escribir: `select * from public.gv_alerta_inactivo_servidor(true, '2026-10-06 08:40-03');` → 237 ABRE ALERTA.
- La v1 de un argumento `(boolean)` queda en la base sin llamador (el DROP se cuelga en el MCP).
- `sql/gv_alerta_inactivo_servidor_v2751.sql` (rollback en la cabecera).
- **v27.54 (Thomas, D5): la JORNADA arranca al FICHAR** (*"deben fichar por el programa con el código de TV y después arrancar la producción"*): `hs_total` de `gv_monitor_horas_operario_dia` (y `gv_horas_operario_detalle_v2`) cuenta desde el primer ingreso del día en `GV_Dispositivo_Login`, no desde el primer evento. Lo que va del ingreso a la primera tarea es tiempo muerto (Franco 06/10: 2:08). Centinela 337, huella re-congelada. `sql/gv_monitor_jornada_fichaje_v2754.sql`.

## ⚠ REGLA (Thomas, 2026-10-06, v27.57): el GUARDADO (MG) cuenta lo suyo — no el tiempo que se pisa con otra tarea

Thomas (D6): *"puede guardarse por mucho tiempo, siempre y cuando se esté guardando o que en el medio se pise con otra
tarea"*. Caso Isidro (94) 06/10: un MG 10:48 → 16:49 con 4:22 de limpieza y un IR adentro, más un MG 09:30 → 10:48 que
repetía los tres anteriores (con un RT adentro). La vista sumaba mov 4,97 h + no prod 5,65 h en una jornada de 8,82 h.

- Los MG cerrados del día cuentan como la **UNIÓN de sus tramos** (un MG que repite a otros no suma dos veces) **MENOS
  lo que se pisa** con cualquier otra tarea del legajo: tiempo muerto, tramos cerrados de otras tareas (RT, CC, TP…),
  racks inferidos y lo abierto. Isidro 06/10: mov 4,97 → 3,14 h (MG 2,48 + RT 0,53 + racks 0,13).
- Un **IR adentro de un MG** ya no queda tapado por el MG: cuenta como racks y se le saca al MG.
- El MG que cruza el día sigue como antes. **D7 (Thomas): lo anulado (EPX/APX) es tiempo muerto** — ya caía ahí: no se cuenta en ningún balde.
- `gv_monitor_horas_operario_dia` y `gv_horas_operario_detalle_v2` (CTEs `mg_raw` / `mg_isla` / `mg_oc` / `mg_ag`,
  marcador `v27.55-mgpisa`) ≡ `fetchMonitorDayStats` (bloque `v27.55-mgpisa`). Huella re-congelada (`e32bc4a5…`), el
  15/09 de `vista-15.json` no cambia. Centinelas 96 (actualizado), 338 y 339.
  `sql/gv_monitor_horas_mg_pisa_v2757.sql`, `tests/mg-pisa-tarea.cjs`.

## ⚠ REGLA (Thomas, 2026-10-07, v27.68): DOS RELOJES — la LLEGADA es con el código de la TV; el SUELDO arranca en la 1.ª tarea

| para qué | desde cuándo cuenta la jornada | dónde |
|---|---|---|
| **monitor, TV, Mon. Admin y alarma de inactivo** | el primer ingreso **con el código de la TV** (`GV_Dispositivo_Login.metodo in ('clave_tv','nombre')`; `nombre` = «No estoy en la lista», que también pasa por el código) | `gv_monitor_horas_operario_dia`, `gv_monitor_ingresos`, `gv_alerta_inactivo_servidor` (marcador `v27.68-clavetv`) |
| **liquidación de sueldos** (xlsx de horas) | el **primer registro productivo** (primer evento que no es automático, anulado `X` ni Terminar Día) — **no** la llegada | `gv_horas_operario_detalle_v2` (marcador `v27.68-sueldo1er`) |

- Un **legajo tipeado** (celulares con versión vieja, previa a la v27.56) o una sesión guardada **no es llegada**: no
  dispara la alarma ni marca «entró · sin arrancar». Caso 277 el 07/10 (08:27, sin tareas) y 237 el 06/10.
- La única forma de ingresar es el código de la TV desde la v27.56; los celulares viejos se actualizan solos.
- Huella del monitor re-congelada (`74a2aeae…`), 4 centinelas v27.68. `sql/gv_llegada_clave_tv_sueldos_v2768.sql`.
- ⚠ **v27.69 (Thomas, 07/10): la app es UNA para las dos plantas y el ingreso no dice a cuál fue.** Caso 277: ingresó
  08:27, registró en **Cervantes** 08:28 y el monitor de Virgilio lo marcó «sin arrancar» + alarma 08:33. Hoy: si
  después del ingreso hay un registro en `Registros Produccion Cervantes`, la alarma dice `en Cervantes` (no avisa),
  la TV no lo muestra como «entró» y el ingreso no adelanta la jornada de Virgilio (marcador `v27.69-cerv`, 3
  centinelas). `sql/gv_llegada_cervantes_v2769.sql`.

## ⚠ REGLA (Luis, 2026-10-01, v25.82): 5 MIN DE TIEMPO MUERTO → CARTEL CON ALARMA EN LOS MONITORES — y Bajar de racks es una tarea abierta

> ## ✅ **v25.90 (Luis, 01/10: *"activa la alarma, ahora sí"*): VOLVIÓ, sólo en el monitor del DEPÓSITO y sólo por operarios reales.**
> La cargan `monitor/tv.html` (abierto suelto) y el kiosko `/monitor` (`index.html?monitor=tv`); **NO** Mon. Admin (`build-admin.cjs`
> saca el `<script>`) ni la 📺 Vista TV del admin (no corre dentro de un iframe). **No avisan** el legajo de prueba (0/1) ni el
> supervisor en la vista de operario: lo frenan el celular (`_tmAlertaAbrir`) y la base (`gv_alerta_inactivo_abrir` devuelve null;
> `gv_alertas_inactivo_vivas` saca 0/1). Retira lo de la v25.83/25.87 (prueba avisa, alarma en Mon. Admin) y el apagado de la v25.88.
> `sql/gv_alerta_inactivo_solo_operarios_v2590.sql`.

- **El celular** del operario, al llegar a **5 min** de tiempo muerto en la botonera, llama `gv_alerta_inactivo_abrir(legajo)`
  (una sola alerta viva por legajo; la marca queda en `localStorage gv_tm_alerta::<legajo>`). Al registrar la próxima tarea
  (`tmMarcarEvento`, desde `enqueueReport`) llama `gv_alerta_inactivo_cerrar`. Tabla `GV_Alerta_Inactivo` (RLS cerrada, sólo RPC).
- **v25.87 (Luis, D10): la alarma está en la TV de pared, «Vista TV» y «Mon. Admin»** — el `<script>` va en `tv.html` y
  `admin.html` lo hereda del build. El legajo de prueba (0/1) también avisa (sale «PRUEBA (legajo 1)»).
- **El monitor** (`monitor/alerta-inactivo.js`)
  leen `gv_alertas_inactivo_vivas()` cada 4 s: cartel centrado del **70 %**, rojo titilando, *«[Nombre] lleva más de 5 minutos
  inactivo»*, con **sirena** Web Audio. **Suena 15 s y el cartel queda 60 s** (v27.67, Thomas 07/10; antes se iba a los 15 s), o se va
  apenas la alerta se cierra. Un iframe escondido no suena.
- ⚠ **El navegador no deja sonar sin un toque previo**: si el kiosko no arranca con `--autoplay-policy=no-user-gesture-required`,
  el cartel dice «🔇 tocá la pantalla una vez» y desde ese toque suena.
- ⚠ **Sólo avisa con la botonera ABIERTA** en el celular: si el operario cerró la app, el contador no corre y no hay aviso. El
  legajo de prueba no avisa.
- ⚠⚠ **v25.86 (Luis: *"se tiene que seleccionar bajar de racks y que ahí tengas que apretar enviar para que lleve el
  tracking. lo mismo guardado a góndola"*): MG y BR funcionan como RR.** El primer toque SELECCIONA (área con «Enviar»),
  «Enviar» EMPIEZA la tarea (`gvModTareaAbrir` / RKI) y abre el módulo; abierta, el botón queda rojo y tocarlo RE-ABRE el
  módulo; salir del módulo la TERMINA (`gvModTareaFin` → Historial con duración). En MG la tarea cierra recién cuando no
  queda abierta ninguna de sus pantallas (chooser, qué bajar primero, lo que llegó, excedente). Las horas siguen saliendo
  de los MG por código y del RKI→RKB: no se agregó ningún evento. `tests/mg-reentrada.cjs`, `tests/alerta-inactivo.cjs`.
- **Bajar / Ingreso a racks = tarea abierta** en el celular (`st.racks` / `st.ir`, desde `gvRacksTramo`): BR en rojo, tiempo muerto
  en 0, y al terminar va al Historial de tareas con su duración (además del tramo RKI→RKB de siempre). Tope 12 h por si el celular
  murió adentro.
- `sql/gv_alerta_inactivo_v2579.sql`, `tests/alerta-inactivo.cjs`.
- ⚠ **v26.56 (Luis, 05/10): una tarea de módulo (MG) que quedó «activa» de OTRO día no es la de hoy.** Isidro (94)
  dejó el guardado abierto el 02/10 (MGI 15:23 + Terminar Día); el 05/10 «Enviar» la vio activa y no renovó la hora,
  `_tmLibre` la dio por vencida (> 12 h) y contó tiempo muerto con él adentro del módulo: alarma a las 08:41 y 08:50,
  justo 5 min después de cada MGI. Hoy `_gvModVivo` (el mismo tope de 12 h) decide en `gvModTareaAbrir` (vencida →
  arranca con la hora de ahora), en el rojo del botón MG y en `gvModTareaFin` (vencida → no entra al Historial).
  **Una alarma que salta exactamente 5:00 después de un evento del operario = el celular lo cree libre: mirar su
  `st.*` de días anteriores.** `tests/mg-tarea-vencida.cjs`.

## ⚠⚠ REGLA GENERAL (Luis, 2026-10-01, v25.89): PROD es SÓLO picking y armado — todo lo demás es NO PROD

**Luis:** *"prod es SOLAMENTE armado y pickeo, todo lo demas es no prod (incluye tiempo muerto) esto es regla general de
como se considera el tiempo"*. Se retira el «Prod incluye movimiento/racks, carga y remitos» de la v23.70.

- **TV y Mon. Admin**: Prod = `hs_pick + hs_arm`; No prod = `hs_total − Prod` (movimiento, carga, remitos, baño, comida,
  cancelaciones y tiempo muerto). Se resuelve en el front: la vista `gv_monitor_horas_operario_dia` NO se tocó (sus
  baldes siguen igual, con su huella).
- **Mon. Admin → clic en Prod / No prod**: pop-up de DOS columnas (Prod: picking · armado | No prod: movimiento · carga
  y remitos · declaradas · tiempo muerto), con sus totales.
- **«En este momento» se mudó a Operarios**: la columna Total se fue y en su lugar va **«Ahora»** (qué hace y hace cuánto).
  El que fichó sin cerrar nada sale igual, con «—» en las horas. Pendientes de salir hoy toma el alto que dejó.
- **Monitor viejo de `index.html` (Mts3 x Hora, v25.90, D11)**: filas nuevas **Prod** (picking + armado + en curso) y **No prod**
  (CC/CR/RR + movimiento + pausas); la fila «No prod.» se llama **Pausas**. `prodH` interno no se tocó (≡ vista, `mon-vs-vista`).
- **Bajar de Racks ordena por urgencia**: `(góndola + A guardar − pedido) ÷ capacidad`, de menor a mayor; sin capacidad
  al final (≡ Guardado a Góndola, que ya ordenaba por `(góndola − pedido) ÷ capacidad`).
- **v25.92 (Luis): el pop-up de m³/h picking / armado** (Mon. Admin) es una tabla angosta **Tanda · m³ · Min trab · Ritmo m³/h** + fila Total. Min trab = de punta a punta (apertura → cierre TP/TAP); las pausas adentro (baño, comida, limpieza, conteo, timbre, permiso) van «60 (-2)» y el Ritmo es el real, de punta a punta (v26.01). Arriba va sólo el nombre, centrado (v25.96).
- `tests/mon-tv.cjs`, `tests/mon-admin.cjs`, `tests/rkb-orden-urgencia.cjs`.

## ⚠ REGLA (Luis, 2026-09-28, v23.64-65): MONITOR — el camión es el GRUPO DE ZONAS, la bajada de racks es actividad

- **«Total por día» (admin y TV) cuenta camiones con `gv_monitor_tanda_camion`** (Capital Sur/Centro/Oeste —Z2+Z3
  juntas si cada una < 1 m³—, GBA Sur/Oeste/Norte, un camión por súper, Retira sin camión), ≡ `PPP_RES_CAMIONES`.
  Antes era la letra+número del código (`tandaCamion`): el 30/09 decía 11 camiones y salen 5. `tandaCamion` queda de fallback.
- **La bajada de racks y el guardado viven en `Movimientos_Stock`, no en los eventos**: entran como eventos `GST`
  sólo para «sin marcar» y «En este momento» (📥 Guardando, vivo 45 min). No tocan las horas.
- **La TV cambió «A facturar» por el RESUMEN DE 3 DÍAS de la PPP** (`gv_ppp_prog_arbol`, % Salió/Fact/Arm/Proc/Pend,
  netos por Salió = CCN). El admin tiene la pestaña **📺 Vista TV** (la misma `monitor/tv.html` en iframe).
- Horas: `hs_total` es la jornada y los baldes sólo lo CERRADO — la tarea abierta y la bajada de racks no suman.
  Pendiente de Luis. `sql/gv_monitor_tanda_camion_v2364.sql`, `tests/mon-guardado-camion.cjs`.

## ⚠ REGLA (Luis, 2026-09-28, v23.66): las HORAS cuentan la tarea ABIERTA y el TRABAJO EN RACKS

- **Hoy, la tarea abierta suma hasta ahora** (`gv_monitor_horas_operario_dia`, CTEs `abre`/`abierta`/`ab_*`): la más reciente
  sin su cierre (EP sin TP, AP sin TAP, toggle, MGI, RKI, IRI), sin FJ posterior y de < 12 h, **menos los tiempos
  muertos adentro — también el baño abierto** (misma lógica que las cerradas). El muerto abierto y el permiso van a no
  productivas. Días pasados: sin cambios (el 15/09 del test da idéntico).
- **Trabajo en racks = Hs MOV**: Bajar de racks (RKI al abrir → RKB con `ts_inicio` al confirmar o cerrar) e Ingreso a
  racks (IRI → IRT al cerrar). El tiempo en el módulo cuenta aunque no se registren cajas. `gvRacksTramo` en index.html.
- **Lo abierto lo suman la vista (TV) y la tabla Mts3 x Hora del admin (v23.67)**: fila «En curso (h)» para picking/armado abierto; lo demás a su fila. **No entra al m³/h** (la tanda no cerró).
- Huella re-congelada (md5 `fcab722b…`), centinela 96 actualizado y fila nueva `ab_ag`. `sql/gv_monitor_horas_abiertas_v2366.sql`.

## ⚠ REGLA (Luis, 2026-09-28, v23.68): el trabajo en racks sin tramo se INFIERE — y el admin abre en la Vista TV

- Bajadas de racks (`Movimientos_Stock` baja_racks) e ingresos (IR) **sin tramo RKB/IRT** (celular viejo o anteriores a
  la v23.66): tramo = desde la actividad anterior del legajo hasta el movimiento, **tope 60 min**, menos tiempo muerto;
  suma a Hs MOV. Si el movimiento cae adentro de otra tarea cerrada, no suma. **Es estimación.** Vista (`rk_pts`/`rk_seg`/
  `rk_ag`) ≡ `fetchMonitorDayStats` (`RK_TOPE`); fixture `tests/tools/rk-15.json` + `vista-15.json` re-congelada (94 → 6,33).
- El monitor del admin abre directo en **📺 Vista TV** (kiosko de pared sigue en el monitor viejo).
- ⚠ «Guardando» en vivo desde que abre el módulo (MGI) exige el celular en **v23.63+**; con uno más viejo sólo se ve al confirmar cada guardado.
- **v23.69**: el **FJ CIERRA la tarea abierta** (cuenta hasta el FJ; antes la borraba) y sin FJ no pasa del fin de jornada
  (vista `abierta.fin` ≡ admin `fin`). La TV: fuentes más grandes, Tandas a todo el alto, Operarios + «En este momento» en
  el medio (≤ 4 operarios a la vez). `sql/gv_monitor_horas_cierre_dia_v2369.sql`.

## ⚠ REGLA (Luis, 2026-09-28, v23.70): MONITOR — Ritmo y Horas, todo en H:MM, sin tope de tramo

- **La tabla de operarios (TV y 📺 Vista TV) se divide en RITMO y HORAS.** Ritmo = **m³/h picking** y **m³/h armado**
  (decimal: m³ de las tandas cerradas hoy con TP/TAP ÷ `hs_pick` / `hs_arm`). Horas = **Prod** (incluye el movimiento/racks),
  **No prod** y **Total** (jornada). **Toda hora va en H:MM**, todo índice en decimal. El «h/tanda» se sacó: la tanda es volátil.
- **Trabajo en racks inferido SIN TOPE**: el tramo va desde la actividad anterior (o la entrada) hasta la bajada/ingreso.
  `sql/gv_monitor_horas_sintope_v2370.sql`; el admin (`fetchMonitorDayStats`) replica lo mismo (`tests/mon-vs-vista.cjs`).
- **Los celulares se actualizan solos**: `sw.js` recarga una vez las ventanas abiertas al activar (`forzado-v2370`) y
  `checkForUpdate` recarga sola la app si hay versión nueva y el operario no tocó nada hace un rato (`_gvAppInactiva`).
  No hace falta pedirle al operario que actualice.
- En el iframe de 📺 Vista TV se ve el cursor (`html.embebido`); en la TV de pared sigue oculto.

## ⚠ REGLA (Luis, 2026-09-28, v23.71): el TIEMPO de las tareas se captura bien — tres fallas cerradas

Medido sobre Jhonny (104), 22–28/09, con su planilla del 25/09:
- **RT cerraba con las cajas del DÍA**: `recepcionCajasServerTotal` sumaba desde las 00:00 → una RT vacía decía «67»
  (35 + 32 de antes). Ahora suma desde la **apertura de esa RT**; sin RT abierta devuelve null (vale el contador local).
- **Recepción enviada con RT cerrado no tenía tiempo** (la 2.ª carga con «Cargar otra» después del cierre automático):
  27 cargas en 7 días. Ahora `autoCloseRT(legajo, {inicioMs, cajas})` registra su **propio tramo RT** desde que empezó
  esa carga en el Modo OP (`opState.t0`, lo pone `opResetState`).
- **EP / AP sin tanda** quedaban como tarea abierta que ningún TP/TAP cierra: ahora `send()` no los registra.
- ⚠ Lo que NO es de código: el **guardado cargado después de hacerlo** (35 cajas en 17 s) es la carga a destiempo;
  desde la v23.63 el tramo arranca al ABRIR el módulo (MGI), y los celulares pasan a esa versión solos (v23.70).
`tests/tiempos-captura.cjs`.

## ⚠ REGLA (Luis, 2026-09-28, v23.76): lo abierto al terminar el día SUMA — y el Guardado se marca por código

- **Lo que queda abierto en un día pasado suma a SU día** (antes sólo hoy): hasta el FJ, o el fin de jornada sin FJ. En
  el cruce de día, el día del cierre cuenta sólo desde la entrada (`open_s = 0`): nada se cuenta dos veces.
- **Una tarea abierta termina donde EMPIEZA la siguiente del legajo** (`v23.72-sig`): no se superpone con lo que hizo
  después (104 el 15/09: EI abierto 13:08 con el RT de 13:49 → 0,68 h, no 4 h). Vista ≡ `fetchMonitorDayStats`;
  fixture `tests/tools/ev-15.json` ahora trae las aperturas. `sql/gv_monitor_horas_cruce_dia_v2372.sql`.
- **Guardado a Góndola por código**: «✓ Guardé este código» (MG con su tramo, el módulo sigue abierto con MGI) y
  «Ya estaba en góndola» (mueve stock, emite **MGR** instantáneo: sin tiempo). «🏁 Terminé de guardar» cierra.
- **Celular muerto**: al abrir el legajo en otro celular, `gvRecuperarTogglesServidor` repone los toggles abiertos del
  servidor (hoy, < 12 h, sin FJ después). Lo que el celular muerto nunca mandó se pierde.
`tests/mg-por-codigo.cjs`.

## ⚠ REGLA (Luis, 2026-09-29, v24.38): el CÓDIGO DE INGRESO va centrado y grande — y la banda de «Días» no lleva texto

**Luis:** *"quiero que ese codigo este mas grande, centrado y que sea «CÓDIGO DE INGRESO: XXXX» con
el timer y toda la bola"* · *"en la landing que diga «CODIGO DE INGRESO (EN LA TV)»"* · *"saca todo
ese texto que es al pedo y pone otro dia mas en ese cuadro"*.

| dónde | cómo queda |
|---|---|
| header del monitor del admin (`index.html`, `.mon-clave`) | rueda + **«CÓDIGO DE INGRESO: 4145»** en UNA línea, centrado en el header y al doble de tamaño |
| TV de pared (`monitor/tv.html`) | lo mismo; el header pasó a **grid de 3 columnas** (vacía · código · reloj+estado) |
| landing del celular | el rótulo dice **«🔑 Código de ingreso (en la TV)»** |
| banda de «Días» de la TV | quedan **sólo** el veredicto y «Pasar de día»; el resumen muestra **4 días** |

⚠ **Centrar sacando del flujo tiene su contra:** en el admin el código va `position:absolute`, así
que el reloj hereda su hueco y se le monta encima — por eso el `margin-left:auto` pasó a ser del
`#monitorClock`. Abajo de 1150 px el código vuelve al flujo, o se monta arriba de las pestañas.

⚠ **En la TV NO se usó `absolute`**: el alto del header lo da la rueda, y sacarla del flujo dejaba
el header de la altura del reloj y el código cortado al medio. Va en grid, que centra en la
PANTALLA (no en el hueco entre los vecinos) y conserva el alto.

⚠ **Lo que se sacó de la banda es el DETALLE de la misma cuenta que el veredicto resume** (barra de
avance, la meta, el ritmo, «Hoy … pickeado · … armado»). El ritmo sigue entrando en el veredicto y
en el cartel de CORTE de las 15:00 — lo prueba `tests/tv-meta-camion.cjs`, que no se tocó.

**Chequeo:** `node tests/mon-header-codigo.cjs` (bloque **f**: el rótulo, la misma línea, el tamaño
y el centrado medidos sobre la pantalla; verificado que falla contra el index anterior) ·
`node tests/mon-tv.cjs` (candado invertido: si vuelve una de las líneas sacadas, se pone rojo).

### ⚠ v24.39 (Luis): la TV es una PARED — un día = UNA fila, y el veredicto vive arriba a la izquierda

**Luis, con la captura del 4.º día cortado:** *"esto esta pensado para estar en un monitor (tv
samsung) … CLARIDAD VISUAL Y SIMPLEZA … la tabla asi es horriblemente ineficiente"*.

| qué | cómo queda |
|---|---|
| tabla de «Días» | **una fila por día**: el día a la izquierda y sus 5 porcentajes al lado. Antes eran **dos** filas (el día a `colspan=5` y los números abajo), o sea el doble de alto para lo mismo — por eso el viernes quedaba cortado |
| el subtexto `· hoy · 5,9 m³ · 5 tandas · 13 NP` | **se fue** (*"es al pedo eso"*) |
| encabezados | **todos centrados**: `.card-t` va `text-align:center` y la clase `.izq-t` queda por si alguno tiene que volver a la izquierda |
| el veredicto (`⛔ Terminó la jornada…` + `Pasar de día`) y los **carteles de aviso** | encabezan la **columna izquierda**, arriba de la tabla de tandas (*"usá ese realstate para poner los carteles de aviso"*) |
| «En este momento» | pasa a `grow`: se queda el alto que dejaron los avisos al mudarse |

⚠ **El alto de la pared es lo escaso, no el ancho.** Toda fila que se agregue al cuadro de Días
le come un día al resumen: si hace falta un dato por día, va como **columna**, no como segunda
fila ni como subtexto.

⚠ `pintarMeta` sigue escribiendo en `#metaBox` y devolviendo el cartel de CORTE para `#avisos`:
lo que cambió es **dónde están esos dos divs**, no la lógica. `tests/tv-meta-camion.cjs` no se tocó.

## ⚠ REGLA (Luis, 2026-10-07, v27.80): el SUPERVISOR (`sup:<mail>`) no es operario en ningún monitor

Caso: «Leg S. · libre 1:17» en el Mon. Admin = `loekemeyer.n8n@` marcando 6 «↩ s/salida» desde el panel (firma
`sup:<mail>`, v21.42). Hoy lo sacan la vista `gv_monitor_horas_operario_dia` (marcador `v27.80-sup`, centinela 348),
tv.html / admin.html (`actividadActual`, fichadas, `popFaseCiclos` en `build-admin.cjs`) y el monitor del index
(`fetchMonitorDayStats`, `showDayBreakdown`, `_monActividadActual`, `_monEnSilencio`, `fetchMonitorEvents`). Todo
filtro de «legajo de prueba» en un monitor lleva también `/^sup:/`. `tests/mon-sup-no-operario.cjs`.

## ⚠ REGLA (2026-10-12, v29.46): PPP → «Plantel» — horas de picking, armado y tareas fijas → personas de la semana

Solapa **Plantel** de la PPP (`plantel.js`, `plantelHtml` / `plantelCalc`). Todo lo calcula **`gv_ppp_plantel(semana, semanas_hist, meta, dias_antes)`** (anon, ~1,4 s):

| pieza | de dónde |
|---|---|
| m³ de la semana | el MAYOR entre **no vencer** (programado sin pickear / sin armar cuyo límite de armado = fecha del pedido + meta hábiles − 2 hábiles cae antes del viernes; para una semana futura se descuenta lo que se hace antes al ritmo de hoy) y **no acumular** (m³ que entra por semana, por fecha del pedido) |
| m³/h | medido: m³ de las tandas con su 1.er TP / TAP ÷ horas reales de picking / armado (`gv_monitor_horas_operario_dia`) de las últimas N semanas |
| tareas fijas | promedio por día hábil de **carga + remitos** (hs_prod − pick − arm = CC/CR/RR) y **movimiento** (guardado, recepción, racks, insumos) × hábiles de la semana |
| personas | horas ÷ (horas útiles por persona por día × hábiles), para ARRIBA. Útiles = medido (pick+arm+carga+mov por persona-día, 6:58 al 12/10, jornada 8:25); se puede pisar en pantalla (por navegador) |

- La historia vive en **`GV_Plantel_Dia`** (caché por día: 28 días de la vista tardan 3,3 s); la llena `gv_plantel_dia_refrescar` con el cron **154 `gv-plantel-dia`** (04:50 ART, últimos 3 días, anti-solape).
- Feriados: `gv_es_dia_habil` (planify.feriados + GV_Dias_No_Habiles). La meta por defecto es **10 hábiles** del pedido a la salida (editable en pantalla).
- **No cuenta** lo que está en A Programar ni en Cuarentena (no tiene tanda ni fecha).
- Medido 12/10: entra 32,2 m³/sem y se procesan 5,0 m³/día (≈ 25/sem) con 3,5 personas/día; 13 NP ya pasaron los 10 hábiles. Próxima semana: 143:10 h → 5 personas.
- `sql/gv_ppp_plantel_v2946.sql` (rollback en la cabecera), `tests/ppp-plantel.cjs`.

## ⚠ REGLA (Thomas, 2026-10-12, v29.47, D4): RITMO DE PICKING — estimado por DIFICULTAD antes de pickear vs real

**Thomas:** *"si es un metro cúbico de un picking ultra difícil, el ritmo va a ser peor … que figure cuántas son las horas y qué rendimiento tuvieron en horas reales, acorde al esperado que habíamos estimado de manera inicial. Todo en el back."*

| pieza | qué hace |
|---|---|
| **`gv_picking_estimar(tandas[])`** | el tamaño D17 (min) de una tanda SIN pickear: líneas del pedido (`PPP_Web_Base` / `gv_ppp_base_pedidos`), góndola del Mapa y stock de ahora (`stocks_carga_rapida`) para la altura. Misma fórmula y coeficientes que `gv_picking_tanda_calc` (`GV_Picking_Esquema`). Validado sobre 98 tandas ya pickeadas: correlación 0,98 con el D17 post-picking, +5 % (cuenta líneas que después salen en 0) |
| **`GV_Picking_Estimado`** | la foto por tanda: `tamano_inicial` (la PRIMERA estimación, no se pisa) y `tamano` (la última antes del TP). Cron **155 `gv-picking-estimar`** (`8-58/10 9-23`). Las 182 tandas pickeadas antes del 12/10 están `reconstruido = true` (estimadas después, con el stock de hoy) |
| **`GV_Plantel_Operario_Dia`** | horas del monitor por operario y día (la llena `gv_plantel_dia_refrescar`, cron 154; `GV_Plantel_Dia` sale de esa foto) |
| **`gv_ritmo_picking(desde, hasta)`** | **sólo supervisor**. Por día, por operario y total: estimado inicial, esperado (D17 con lo pickeado), real neto (sin pausas ni huecos > 5 min, cola ≤ 30), horas del monitor (hoy en vivo), rendimiento = esperado ÷ real (≥ 100 % llegó), pérdida = monitor − real |
| Monitor → pestaña **Ritmo** | `ritmoCargar` / `ritmoRender` en `plantel.js`. Dentro de `monTabSwitch`: el kiosko de pared no la muestra |
| **Plantel** | la hora de picking sale de la base (`semana.horas_pick`): lo que vence = minutos estimados de SUS tandas × F (F = horas reales del monitor ÷ estimado de las tandas pickeadas en la historia, 1,22 al 12/10); lo que entra, al promedio; el mayor |

- Desde la **v29.48** la caja por encima de 30 suma `caja_extra` (E85A 6 → 18 min, E84A 6 → 30 contra 32 reales).
- Al 12/10, 28 días: 144 tandas, esperado 62:44 h, real 56:35 h (111 %), monitor 80:32 h (la diferencia son pausas, huecos y cola).
- Armado tiene modelo de dificultad desde la **v29.48** (regla de abajo).
- `sql/gv_ritmo_picking_v2947.sql`, `tests/monitor-ritmo.cjs`, `tests/ppp-plantel.cjs` (f).

## ⚠ REGLA (Thomas, 2026-10-12, v29.48, D5 · D6 · D7): ARMADO por dificultad, Plantel con A Programar/Cuarentena y pallets en el picking

- **Armado (D5)**: tamaño esperado en min = **5,06 × NP + 0,607 × línea + 0,352 × caja (hasta 30 por línea) + 0,076 × caja de 30 a 330 por línea + 30,4 si es súper** (`gv_armado_tamano`; coeficientes `arm_*` en `GV_Picking_Esquema`, NNLS sobre 426 tandas: corr 0,85, error medio 17,5 min sobre una mediana de 50). Real = AP→TAP − pausas + cola ≤ 30 min (`gv_armado_tanda_calc`, caché **`GV_Armado_Tanda`**). Una tanda **frenada en armado (APF) no se mide** (la armaron dos personas). No hay huecos medibles: TAL y ENT llegan al terminar.
  - Antes de armar: **`gv_armado_estimar`** con las líneas del pedido (corr 0,85 con el real, ×1,02) → foto **`GV_Armado_Estimado`** (`tamano_inicial` no se pisa; `reconstruido = true` lo armado antes del 12/10). Lo refresca el cron **155** junto con el picking.
  - Monitor → **Ritmo** tiene **Picking | Armado** (`gv_ritmo_armado`, la misma cuenta que `gv_ritmo_picking` sobre las tablas de armado; sólo supervisor).
  - **Plantel**: `semana.horas_arm` = lo que vence (estimado × F, F = horas de armado del monitor ÷ estimado de las tandas con su 1.er TAP en la historia, 1,14 al 12/10) o lo que entra al promedio, el mayor.
- **Plantel (D6)**: cuenta también lo que espera en **A Programar y Cuarentena** (`gv_ppp_sin_programar()`: el universo de A Programar sin lo que `gv_pedidos_web_excluidos` saca, m³ por `items_string` × `vista_volumen_articulo_resuelto`). Su plazo corre desde la fecha del pedido. Al 12/10: 11 pedidos, 6,80 m³, 7 ya vencidos.
- **Picking (D7)**: la caja por encima de 30 por línea suma **`caja_extra` = 0,0061 min** (pallet entero; E84A 6 → 30 min contra 32 reales). El caché se ajustó una vez (llave `GV_Picking_Esquema.caja_extra_aplicado`): no volver a sumar.
- Centinelas v29.48 (5 filas). `sql/gv_armado_dificultad_v2948.sql`, `sql/gv_plantel_ritmo_v2948_defs.sql` (definiciones vivas), `docs/armado-dificultad/fit_armado.py`, `tests/ppp-plantel.cjs` (g, h), `tests/monitor-ritmo.cjs` (g).

## ⚠ REGLA (Luis, 2026-10-13, v29.74): el MONITOR dice DÓNDE QUEDÓ FÍSICAMENTE una tanda pickeada

**Luis:** *"cuando muestra una tanda en la pantalla que está pickeada, que muestre dónde quedó físicamente
(último dato entre lo que indicó quien la pickeó sobre dónde la dejó o la mesa de armado en la que la están
armando)"*.

El dato **ya se registraba en tres lugares y no lo mostraba ninguna pantalla**:

| cuándo | dónde vive | qué dice |
|---|---|---|
| al TERMINAR el picking (TP) | evento **`PUB`** (`texto` = tanda, `descripcion` = lugar) | Mesa 1 · Mesa 2 · Carro · AA9… |
| al FRENAR el picking | **`GV_Tanda_Freno.ubicacion`** (v26.61) | dónde quedó el carro |
| al TERMINAR el armado (TAP) | evento **`AUB`** | AA1..AD8, el sector de armado |

- Lo resuelve **`gv_tanda_ubicacion(text[])`** (lectura, anon, ~17 ms para 57 tandas): UNA fila por tanda con
  la ubicación del **`ts` más reciente** entre las tres fuentes, más `fuente`, `legajo` y **`otras`** (lo que esa
  misma fuente dejó en otro lado, p. ej. NP repartidas en dos sectores).
- Se ve en **la TV de pared, la 📺 Vista TV y el Mon. Admin** (`monitor/tv.html` → `admin.html` por el build):
  chip **📍 Mesa 2** dentro de la celda del código, en la tabla de tandas y en «🚚 Pendientes de salir hoy».
  **Va abajo del código y no en una columna propia**: en la pared lo escaso es el ANCHO, y el que busca el
  pallet lee primero la tanda. El `title` dice de dónde salió el dato, quién lo cargó y a qué hora.
- **Es SECURITY DEFINER a propósito**: cruza `PPP_Web_Programacion`, que `anon` no ve por RLS, y una función
  INVOKER devolvería MENOS filas sin dar error (la trampa de la v20.45). Verificado con `set local role anon`:
  55 de 57 tandas (las 2 que faltan no tienen ninguna ubicación registrada).
- **Una lectura rota no borra el chip**: si la RPC falla, la tanda se dibuja como antes.

⚠ **Desde la v29.90 la mesa SÍ se registra mientras arman** (`AUI` al dar AP, regla al final del archivo). El **AUB** sale al TERMINAR (TAP): entre AP y TAP el dato vivo es el del AUI.

⚠ **El AUB hoy viene por TANDA, no por NP.** Medido el 13/10: 130 filas por tanda (la última, de hoy) contra 408
por NP cuya última es del 30/09 — o sea que `_stkFetchNpsByTanda` no le trae las NP a la tanda web y
`askArmadoUbicaciones` cae a su fallback de «una ubicación para toda la tanda». La RPC cubre **las dos formas**,
así que no cambia nada mostrar una u otra; el fallback en sí es otro tema.

⚠ **No se agregó al monitor viejo de `index.html`** (el que abre el supervisor desde la app): la pared y el Mon.
Admin son los que se miran, y acá no hay riesgo de «dos verdades» porque es un dato que se muestra, no un número
que se calcula. Si se quiere ahí también, se agrega.

**Chequeo:** `select tanda, ubicacion, fuente from public.gv_tanda_ubicacion(array['F58B','F86A']);` ·
`select * from public.gv_reglas_perdidas;` · `node tests/mon-tv.cjs` (4 chequeos nuevos, verificado que fallan
contra el tv.html anterior) · `node tests/mon-admin.cjs`. `sql/gv_tanda_ubicacion_v2974.sql`.

## 🗄 RETIRADO — sólo revisar si se pregunta por algo ANTIGUO que no está arriba

> Reglas, versiones y hallazgos que **ya no valen**. Se guardan como historia, no como instrucción.
> **No leer esta sección en el trabajo normal**: sólo cuando alguien pregunta por un comportamiento viejo
> y no aparece en las reglas vigentes de arriba. Nada de acá se vuelve a aplicar sin un pedido explícito.

- v29.47: «el modelo de picking topea cada línea en 30 cajas». Retirado en la v29.48 (`caja_extra`).

- v29.47: «armado no tiene modelo de dificultad todavía». Hecho en la v29.48.

⚠ **RETIRADA la nota de que la mesa no se registra mientras arman** (decía que el AUB se emite al TERMINAR y
que preguntarla al dar AP lo decidía Luis): desde la **v29.90 SÍ se registra** — el AP la pregunta y emite un
**`AUI`** (regla al final de este archivo). Lo que sigue valiendo es que el **AUB** sale al TERMINAR (TAP), así
que entre el AP y el TAP el dato vivo es el del AUI.
