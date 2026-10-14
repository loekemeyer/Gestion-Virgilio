# Reglas Picking Armado — Picking y armado: registro, frenar/pausar, anulaciones, pallet, mesa, métricas por paso

> Movido de `CLAUDE.md` el 2026-10-13 (poda 3ra tanda, pedido de Luis) **sin cambiar una palabra**.
> **Leerlo ENTERO antes de tocar algo de este tema.** Las reglas siguen valiendo igual que cuando estaban en CLAUDE.md.

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

## ⚠⚠ REGLA (Luis, 2026-10-05, v26.61): FRENAR la tanda ≠ PAUSAR — parte 1: estado «frenada» y copia del armado

**Luis:** *"cuando se termina (completo o incompleto) debería capturar la información el servidor para que después
se pueda continuar desde otro dispositivo"* · *"que no se pueda abrir una tanda con la que otra persona ya está
trabajando"* · *"en vez de «Pausar» deberíamos llamar a esto «FRENAR»"*.

| palabra | qué es | estado |
|---|---|---|
| **PAUSAR** | salir un rato (baño, comida): la tanda SIGUE SIENDO del operario. Picking: «Cerrar» arriba a la derecha; armado: «⏸ Pausar» del asistente | ya existe, **no se toca** |
| **FRENAR** | soltarla con todo lo hecho registrado: la retoma él (sin cartel) u OTRO (con cartel «Estás por agarrar una tanda que empezó A ¿Seguro?») | `GV_Tandas_Lock.estado = 'frenada'` |
| **TERMINAR** | se cierra aunque falte algo (lo que falta sale faltante) y no se vuelve a entrar | `completada` |

Decidido por Luis (05/10), no volver a preguntar: una tanda **tomada** (no frenada) no la abre nadie más · con una
frenada el operario **puede agarrar otra** (D9; la frenada no cuenta como «otra tanda abierta») · botón **«Frenar la
tanda»** en picking y armado con pop-up *«Se guardará el registro de todo lo que se pickeó/armó hasta ahora y se podrá
retomar después por vos u otro operario»* · frenar el **picking** pide dónde quedó el carro (D12) · se frena sola al
**fichar salida** y la puede frenar un **supervisor** desde el panel (en armado, sólo con la copia del servidor) · al
día siguiente avisa *«Tenés la tanda X frenada. ¿La retomás?»* **sólo** si sigue frenada y nadie la tomó · al que se
la tomaron **no** se le avisa nada · **crédito**: picking por cajas pickeadas de cada uno, armado por cajas de los
**líos** que cerró cada uno (súper/retira: la NP), en el día en que lo hizo (D6).

**Parte 1 (v26.61) — NO cambia nada de lo que se ve hoy:**

| pieza | qué hace |
|---|---|
| `GV_Tandas_Lock` | acepta `frenada` (check `gv_tandas_lock_estado`) |
| `GV_Tanda_Freno` | historial: de quién era, quién la frenó (`legajo` / `sup:<mail>` / `sistema`), motivo `boton`/`fichaje`/`supervisor`, ubicación, quién la retomó |
| `gv_tanda_frenar(tanda, fase, legajo, motivo, ubic)` | frena una TOMADA. `boton` = sólo el dueño · `supervisor` = `es_supervisor_virgilio()` · `fichaje` = sólo si el dueño tiene un **FJ** posterior a tomarla (lo verifica la base). Idempotente (`ya_frenada`) |
| `gv_tanda_reservar` | frenada + mismo legajo → vuelve a `tomada` sin cartel (`retomada: true`); otro legajo → `ok:false motivo 'frenada'` (un celular viejo muestra el «ya la tiene X» de siempre) |
| `gv_tanda_tomar_frenada(tanda, fase, legajo, nombre)` | otro operario se la lleva (después del cartel); respeta «una por vez» |
| `GV_Armado_Avance` + `gv_armado_avance_guardar` / `_leer` | la ÚLTIMA foto del asistente de armado por tanda, con resumen (NP, NP listas, líos, cajas en líos). La manda el celular al cerrar cada lío (1,5 s), con cualquier cambio (8 s), al pausar, al terminar (`terminado`) y al soltar (`anulado`). Desde el mismo celular no se pisa con una foto más vieja; una terminada sólo la pisa una posterior |
| cada lío | lleva `leg` y `ts` (quién lo cerró y cuándo): no cambia su firma (`_compLioSig`), ni letras ni grupos |

Centinelas v26.61 (3 filas) · `scripts/reglas-protegidas.json` · backup `zz_backups."GV_Backup_TandaFreno_defs_20261005"` ·
rollback y pruebas en `sql/gv_tanda_frenada_v2661.sql` · `tests/arm-avance-servidor.cjs`.

**Parte 2 (v26.64; en la base, los marcadores, la huella y los centinelas dicen v26.62 — llave, no cambiar) — el botón, el cartel y los lectores:**

| pieza | qué hace |
|---|---|
| **✋ Frenar la tanda** | picking (pie del asistente, al lado de Anular) y armado (pie del asistente). Pop-up con el texto de Luis; el picking pide dónde quedó el carro. Antes de frenar manda la cola del celular de ESA tanda (EP/AP/PKC) y, en armado, la foto (`_armAvPost` esperada). Sin señal **no frena** (lo dice): frenar sin que llegue lo hecho perdería el avance |
| evento **PKF / APF** | lo escribe `gv_tanda_frenar` (nueva firma + `p_ts_cliente`; la v26.61 quedó como `gv_tanda_frenar_v2661`): `texto` = tanda, `ts_inicio` = el EP/AP del dueño, `client_id 'frn_<id>'`. Es el **cierre del tramo** del que frenó |
| lista de tandas | la frenada vuelve a **EP** con chip **⏸** y leyenda «frenada por …»; **no** sale en TP (no se termina sin retomarla); en AP se marca, en TAP no sale (`getActivityStatus.pickingFrenadaBy` / `armadoFrenadaBy`) |
| retomar | `send()`: la propia vuelve sin cartel (`retomada`); la de otro → *«Estás por agarrar una tanda que empezó A ¿Seguro?»* → `gv_tanda_tomar_frenada` (devuelve `ubicacion`: «📍 Lo pickeado quedó en: …»). El picking se abre sembrado con las marcas de **todos** (`pkFetchServerMarks(…, todos)`) y re-confirmar un código **pisa la fila PKC original** (`_pk.cid`, mismo `client_id`): el reconciliador suma PKC por tanda+artículo y una segunda fila contaría doble. El armado arranca de la foto del servidor (`gv_armado_avance_leer`) a nombre de quien arma ahora |
| horas | `gv_monitor_horas_operario_dia` (≡ `fetchMonitorDayStats`): PKF/APF **cierran** el EP/AP abierto y su tramo suma a picking/armado de **quien lo hizo**, sin cola. Huella `511b8f5e…` |
| estado y TV | `vista_tanda_status`: PKF/APF = sigue en picking/armando. TV / Mon. Admin / monitor viejo: luz **⏸ frenada** (ámbar) |
| puntaje | una tanda con freno de picking **no entra** en `gv_picking_puntaje_operario` hasta el reparto por operario (parte 3) |

⚠ Desde la **v26.67** (parte 3) el m³ de una tanda frenada se reparte por operario.
Centinelas v26.62 ids 300-306 · `sql/gv_tanda_frenada_v2662.sql` (CREATE completos + rollback) · `tests/tanda-frenar.cjs`.

**Parte 2b (v26.65) — fichaje, supervisor y aviso del día siguiente:**

| pieza | qué hace |
|---|---|
| freno al **fichar salida** | cron **129** `gv-tandas-frenar-fichaje` (`6-59/10`) → `gv_tandas_frenar_fichaje()`: tanda TOMADA cuyo dueño hizo Terminar Día (FJ) después de tomarla, arrancó (EP/AP) y **no volvió a trabajar** desde el FJ → `gv_tanda_frenar(…,'fichaje')`; el PKF/APF queda con la hora del FJ. No toca la que ya tiene TP/TAP. La ventana se mide desde `ts_estado` (al retomarla, el FJ de ayer no la vuelve a frenar) |
| retomar por **«▶ Seguir»** | `pkResume` (abre al instante, offline-first, y consulta después), `pkResumeServer`, «▶ Seguir armado», la ficha de la lista y re-tocar EP/AP de la abierta pasan por `_frenoGuardSeguir`: frenada propia → vuelve a `tomada` y abre un tramo **nuevo** (EP/AP) sembrando de todos; la tomó **otro** → suelta lo del celular y dice *«La tanda X ya la tiene Y.»*; sin señal (techo 4 s) → abre como siempre |
| **aviso del día siguiente** | al entrar a la botonera (`goToOptions`): *«Tenés la tanda X frenada. ¿La retomás?»* sólo si la frenada es de un **día anterior**, sigue a su nombre (`gv_tandas_frenadas_de`) y el celular no la tiene abierta. Una vez por día. «Sí» = EP/AP de esa tanda (la reserva la retoma) |
| **supervisor** | «🔧 Modificar tanda» → **✋ Frenar (soltarla del operario)**: dice quién la tiene (`gv_tanda_lock_estado`); en **armado** sólo si hay copia en el servidor (dice hace cuánto, NP listas y líos), si no le pide al operario que la frene él; motivo `supervisor` |
| «una por vez» | el cartel dice que también se puede **frenar** con «✋ Frenar la tanda» (D9) |

Centinelas 307-310 · `sql/gv_tanda_frenada_v2665.sql` · `tests/tanda-frenar-2b.cjs`.

**Parte 3 (v26.67) — el CRÉDITO por operario y día (D6 · D15 · D16):**

| pieza | qué hace |
|---|---|
| `gv_tanda_credito(text[])` | sólo tandas con freno en esa fase. **Picking**: el ÚLTIMO PKC de cada código × m³/caja (corregir pisa y queda a nombre del que corrigió). **Armado**: las cajas de los líos que cerró cada uno (`lío.leg` / `lío.ts` de `GV_Armado_Avance`); súper / retira: lo que separó (`código.sepLeg` / `sepTs`, que ahora graba `_compSepTap`). Día = el del PKC / lío. anon |
| monitor grande (`fetchMonitorDayStats`) y desglose por día (`showDayBreakdown`) | `gvM3ConCredito`: tandas cerradas (TP/TAP) enteras salvo las frenadas, que dan sólo la parte de ese legajo ese día; más su parte de las que **frenó** ese día. El que sólo frenó también sale. El detalle por tanda dice su parte |
| TV / Mon. Admin | lo mismo (`cargarCredito` ≡ `gvCreditoTandas`) |
| **Productividad / premio** (D15, Luis: *"se reparte el trabajo, se reparte el premio/productividad"*) | `prodCompute` / `_pvOperator`: **PKF / APF son el cierre del tramo del que frenó**, igual que TP / TAP (antes caían en «otros»), y el m³ de una tanda frenada es la parte de cada legajo dentro del período (`gv_tanda_credito`, por día). Sin crédito leído, el tramo frenado va **sin m³** y el TP/TAP se lleva la tanda entera (como antes, sin contar dos veces) |
| súper / retira (D16) | se acredita por **código separado** (quién lo separó y cuándo): ahí no hay líos, y separar es el trabajo |
| cuándo entra | la parte de un operario entra cuando **ÉL cierra su tramo ese día** (TP/TAP/PKF/APF): mismo criterio de siempre, el m³ entra al cerrar. Con el freno al fichar, todo tramo cierra en el día |
| sin respuesta | como antes: la tanda entera al del TP/TAP |

El puntaje 1-10 de picking también reparte por tramos desde la v26.74 (D17, abajo).
⚠ Una corrida que cruza la medianoche sin FJ deja su parte del primer día sin contar (no hay cierre ese día): con el cron 129 no pasa.
Centinelas 313-315 · `sql/gv_tanda_credito_v2667.sql` · `tests/tanda-credito.cjs` (verificado que falla contra la v26.65 y sin el guard de cierre de la TV).

**D17 (v26.74; los marcadores y centinelas de la base dicen v26.68 — llave, no cambiar. Luis: *"que entre la parte de cada uno"*) — el PUNTAJE 1-10 de picking también reparte:**

| pieza | qué hace |
|---|---|
| `gv_picking_tanda_calc_frenada(tanda, legajo)` | cada TRAMO del legajo (EP → PKF del que frenó, EP → TP del que terminó) con la cuenta de siempre (`gv_picking_tanda_calc`: sus líneas, paradas, alturas, tiempo), sumados en UNA fila de `GV_Picking_Tanda` (`cola_tipo = 'frenada'`). El tramo del **freno no lleva cola** (≡ horas) y la espera del último PKC al freno se topea en `cola_tope_min` (30). Cada tramo paga su fijo y su arranque (el que retoma vuelve a buscar el carro) |
| ventana sin solape (`v26.68-ventana`) | la ventana de PKC de un tramo termina donde empieza el vecino (de cualquier legajo): con el ±5 min de siempre, el que retoma a los 2 min contaba sus líneas también en el que frenó. calc_frenada la fija con `set_config('gv.pkc_desde'/'gv.pkc_hasta')` y la limpia después de cada tramo; sin eso `gv_picking_tanda_calc` usa ±5 min como siempre |
| `gv_picking_tanda_refresh` | mira TP **y PKF**; tanda con freno de picking → por tramos; sin freno, igual que antes |
| `gv_picking_puntaje_operario` | el «TP vivo» acepta el PKF del que frenó; el detalle lleva `frenada`. Mon. Admin: **⏸** en la tanda y la nota |

Probado en transacción abortada: F13E partida (retoma a 1 min) → 13 + 12 líneas = las 25 de la original (sin la ventana daba 29).
Centinelas 304 (actualizado) y 316-319 · `sql/gv_picking_puntaje_frenada_v2674.sql` · `tests/puntaje-frenada.cjs`.

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

## ⚠ REGLA (D12, 2026-10-02, v26.25): las MÉTRICAS DEL PICKING POR PASO van aparte — no se mezclan con el PKC

Para el «tiempo estimado de la tanda» (evaluar al operario). El picking anota cada paso en
**`GV_Picking_Paso_Evento`** (`mostrado` · `ok` · `faltan` · `sin_stock` · `adelante` · `atras` · `oculta` · `visible`),
con su propia cola (`gv_pkm_q_v1`, tope 800) y todo en try/catch: **si falla, el picking sigue igual**.

- **No se mezcla con el PKC** (mueve el stock; un evento por tanda+artículo con upsert) **ni con
  `Registros_Produccion_Virgilio`** (lo leen el monitor, el Resumen de hoy, Telegram y el tiempo muerto). Un evento
  nuevo de picking va a esta tabla, no como `opcion` nueva.
- **anon sólo INSERTA.** Sin `ON CONFLICT` (exige SELECT): el duplicado da 409 y la app lo descarta de a uno.
- Lectura: `gv_picking_paso` (un renglón por paso; `medible = false` si se confirmó en ráfaga, < 3 s) y
  `gv_picking_interrupcion`.
- Hallazgos que la motivaron (02/10, 30 días): el 24 a 29 % del tiempo de picking son huecos de más de 5 min sin
  confirmar nada; 5,4 % de los artículos se confirman en ráfaga; 3 % reconfirmados (la 1.ª hora se perdía).
- **Escalera (Luis, 02/10, v26.36 y v26.38 — reemplaza la de la v26.25):** la altura dentro del módulo es
  `((celda − 1) mód alto) + 1`, con la 1 abajo (A y P tienen 5 alturas, el resto 4). Va con escalera **A desde la
  4.ª altura** (A4, A5, A9, A10…) y **todas las demás (B a Ñ) desde la 3.ª** (B3, B4, B7, B8…; D16, Luis 02/10:
  *"de la C a la N llevan escalera desde la tercera altura"* — N no es góndola, es zona de racks: se tomó hasta la Ñ).
  En A *"los múltiplos de cuatro"* no cae en una misma altura (A8 es la 3.ª, A12 la 2.ª): se tomó la 4.ª y la 5.ª. P se
  toma como A. Con esta regla, en 60 días van con escalera 2.610 de 7.795 líneas de góndola (33 %; con la de la
  v26.25 eran 1.261): un solo coeficiente «con escalera» promedia alturas que cuestan distinto, así que se calibra
  por altura.
  Medido en 60 días (segundos entre confirmaciones, mediana): A 23 s en las alturas 2 y 3 · 50 s en la 4.ª · 64 s en
  la 5.ª; B 22 s en la 2.ª y en la 3.ª (73 líneas) · 47 s en la 4.ª (7). **En B la 3.ª no tarda más que la 2.ª**:
  la regla vale igual (es de Luis); el registro por paso lo va a medir sin la caminata.
- Parada: el módulo k de A más el módulo k de B (A1–A5 + B1–B4); los otros pasillos todavía no están confirmados.

`sql/gv_picking_paso_evento_v2625.sql`, `tests/pk-metricas-paso.cjs`.

## ⚠ REGLA (Luis, 2026-10-08, v28.58): el CONTEO DE GÓNDOLA del picking se aprueba o rechaza en la LANDING del admin

- El operario cuenta **DESPUÉS de pickear** (lo que quedó en la celda) un artículo al azar de una sola celda; el evento CG
  ahora es `COD|contado||TANDA` (3er campo vacío = sin snapshot).
- **`gv_conteo_picking_calc(client_id)`** compara contra la góndola (terminado) **al momento de contar**: un movimiento
  `picking` vale con la hora del PKC de su tanda (el cron escribe la fila minutos después) y el de la MISMA tanda del
  conteo cuenta siempre como anterior. `dif = contado − esperado` no cambia con lo posterior; el admin ve
  `contado_hoy = contado + lo movido después` (contó 50, se pickearon 30 → 20). Telegram usa la misma cuenta.
- Landing (`#cgAside`, margen izquierdo; debajo de 1600 px va arriba de los botones): código · góndolas · contó hoy ·
  sistema · dif. **✓** = `gv_conteo_picking_resolver(cid, true)`: ajuste en `terminado`, ref `CONTEO PICKING`,
  «Stock ajustado por conteo durante picking» (nunca deja la góndola en negativo). **✕** = rechazado, no toca stock.
  Los dos quedan en `GV_Conteo_Picking_Resol`. Sin diferencias, el cuadro no se dibuja.
- Forward-facing: `Stock_Config.conteo_picking_desde` (08/10 09:48). Centinela 373. `sql/gv_conteo_picking_v2858.sql`,
  `tests/conteo-picking-admin.cjs`, `tests/pk-conteo-ciclico.cjs`.

## ⚠ REGLA (Luis, 2026-10-14, v30.53): «NO HAY EN GÓNDOLA» del armado deja la góndola en 0 — en los dos sentidos

Caso: C14 (960E) y J26/J27 (591) vacías con la góndola en −1 (F47B pickeó 1 caja de celdas en 0).

- **«Hay de menos» + «No hay en góndola»** (y «No hay más» de Líos, que usa la misma rama) es un **conteo**: la góndola
  se lleva a **0** leyendo el saldo vivo. Antes sólo subía una negativa y topada en `qty`; una positiva quedaba con
  stock fantasma. Ajuste `terminado`, ref `picking_difiere`, `client_id` **`npdg_<tanda>_<np>_<cod>_<qty>`** (un doble
  toque no ajusta dos veces). Separar_pedidos sigue igual (`npd_…`, −qty).
- **No duplica un ajuste a mano**: si alguien ya dejó la góndola en 0, el saldo vivo da 0 y el armado no escribe nada.
- **Dual** (saldo en las dos empresas): no se toca (`_stkGondolaSaldoVivoEmp` devuelve null).
- **«Hay de más»** NO mueve stock y está bien: la pantalla le pide al armador que **vuelva a guardar** las que sobran.
  **«Sí, agarro de góndola»** tampoco (lo descontó el picking).
- `tests/comp-dif-nofantasma.cjs` (casos 2, 6, 7 y 8; falla contra la v30.52). Problema 782.

## ⚠ REGLA (Luis, 2026-10-13, v29.49): el ARMADO cruza Entregas con el picking por el CÓDIGO DE PICKING

Auditoría del módulo de operarios (13/10). `reconciliar_pipeline_stock_etapa2` (el `separado` del TAP) cruzaba
`Entregas_Virgilio` contra el picking sin pelar la **L** ni aplicar `Correcciones_Pedido`: en un pedido de Chef con
artículos de Loeke (031L, 102EL…) o con secundario corregido (809 → 809E) no encontraba lo entregado y mandaba lo
pickeado **de vuelta a góndola** en vez de a «a facturar». Medido: E29G 36 · E18B 43 · F58A 185 · D58A 32 · F13C 5 ·
F48A 3 cajas de góndola de más (ya salieron o están en el pallet), y el facturado no las drenaba.

- La normalización vive en **una vista, `gv_entregas_norm`** (tanda viva, `artn` sin L / sufijo / ceros, corrección
  aplicada, `emp_l = 'LK'` si la línea tiene L). La usan los dos bloques de la etapa 2.
- **El «de menos» del armado no descuenta dos veces**: trigger `aa_gv_npd_tope_picking` → `gv_npd_tope_faltante_picking`
  topa el ajuste `npd_…` de Pickeados con el faltante que el PKC ya registró (F58A/102E quedaba en −5).
- Lo pasado NO se corrige solo (los pares ya separados están balanceados): la corrección de datos pide el «sí».
- Centinelas 394-396. `sql/gv_etapa2_codigo_l_correccion_v2949.sql`, `sql/gv_npd_tope_faltante_picking_v2949.sql`.
- **v29.52: el PKC mueve la góndola EN EL MOMENTO.** `trg_pkc_reconciliar_rt` pasó a SECURITY DEFINER: como invoker,
  con la clave pública daba *permission denied* (tragado) y el picking recién se registraba con el cron 68 (hasta 10 min).
  Probado como `anon` y en vivo (PKC 09:04:28 → picking 09:04:28). `sql/gv_pkc_rt_definer_v2950.sql`.
- **v29.53: CORREGIR una línea pickeada también mueve la góndola en el momento** (trigger `trg_pkc_reconciliar_rt_upd`,
  AFTER UPDATE: el celular corrige con upsert). **No duplica**: el reconciliador escribe con upsert sobre
  `mov_stock_pipeline_dedup` y el cron 68 recalcula el mismo total (probado: PKC, corrección, reenvío y cron → 3 filas, mismo número).
- **Cómo se prueba un módulo de operario**: como `anon` (`set local role anon`) en transacción abortada, con una tanda de
  formato real (`Z98Z`: los guards miran `^[A-Z][0-9]{2}[A-Z]$`) y las Entregas en UN insert (el armado las manda juntas;
  de a una, el trigger separa la tanda con la primera línea sola).

## ⚠ REGLA (Luis, 2026-10-13, v29.90): al EMPEZAR EL ARMADO se pregunta la MESA — evento `AUI`

⚠ **En la base los 4 centinelas y la huella dicen `v29.86`** (la versión con la que se aplicó, antes de que otras sesiones se llevaran la 29.86 a la 29.89): es la etiqueta de cuándo entró, **no se cambia**.

**Luis:** *"d1 si, que pregunte la mesa al empezar armado. fijate que no rompa nada. todo esto
fowardfacing"*.

Cierra el agujero que la v29.74 dejó anotado: el **PUB** dice dónde dejó la tanda el picking y el
**AUB** dónde quedó al TERMINAR el armado, pero **mientras arman no había nada**.

| cuándo | evento | qué dice |
|---|---|---|
| al terminar el picking (TP) | `PUB` | dónde dejó la tanda |
| al frenar el picking | `GV_Tanda_Freno.ubicacion` | dónde quedó el carro |
| **al EMPEZAR el armado (AP)** | **`AUI`** (v29.90) | **la mesa en la que la están armando** |
| al terminar el armado (TAP) | `AUB` | el sector donde quedó el pedido |

- El cuadro (`askArmadoMesa`) ofrece **Mesa 1**, **Mesa 2** y **✏️ Otro lugar…** para escribirlo. Lo emite
  `emitArmadoMesa` con el molde de `emitPickUbic` (encola + manda, id único: si vuelve a tocar AP con otra
  mesa, manda la más reciente). `texto` = tanda, `descripcion` = mesa.
- ⚠⚠ **LA MESA ES OBLIGATORIA: NO hay «Después» ni ningún escape** (Luis, 13/10: *"como que «Despues»? no es
  una opcion eso ni debería serlo"*). El primer intento tenía ese botón y quedó **retirado**: o una mesa, o
  «✏️ Otro lugar…». **No volver a ponerlo.**
- **`ts_inicio` NULL a propósito**: NO abre tarea (el `abre` de las horas es una **lista blanca**:
  EP/AP/MGI/RKI/IRI/MDI/toggles) y no cierra ninguna. Es un evento de **DETALLE**, como PUB / AUB / PKG.
- ⚠⚠ **Obligatoria para el operario, pero NO frena el código, y el cómo importa**: la pregunta va **al final**
  del bloque del AP, **después** de `showCompletarWizard` y **SIN `await`** (`askArmadoMesa(texto).then(…)`),
  así que el cuadro sale **encima** del asistente — que ya está abierto — y `send()` no espera a nadie. En la
  pantalla es obligatoria igual (el overlay tapa todo y no tiene salida), pero si el cuadro **no se dibuja**
  el operario tiene el asistente abierto abajo en vez de quedar trabado. **Con `await` delante del asistente
  quedaba todo colgado de un toque**: tres tests que manejan un AP de verdad (`ap-resume`, `dos-en-curso`,
  `tanda-sin-articulos`) se quedaron esperando el cuadro para siempre, y en el celular un cuadro que no
  resuelve dejaba al operario sin el asistente de Completar. Retomar una tanda frenada emite un AP nuevo →
  vuelve a preguntar (puede ser otra mesa); **reabrir** el asistente («▶ Seguir armado») no pregunta nada.
  ⚠ Al escribir un test que mande un AP por `send()`, stubear `window.askArmadoMesa` (devolver `null`) para
  que el cuadro no quede abierto encima de la pantalla.
- **Forward-facing**: no hay un solo `AUI` en la historia y **no se backfillea**. El 15/09 de
  `tests/tools/vista-15.json` da idéntico (verificado, md5 `f5c7560f…`): sólo se movió la **huella**.

> ⚠⚠ **Un evento de detalle nuevo tiene que entrar en las 5 listas de «automáticos» de la COLA** (v26.43), o
> cortaría la cola de un TP/TAP y bajaría las horas de picking y de armado sin que nada avise:
> `gv_monitor_horas_operario_dia` · `gv_horas_operario_detalle_v2` (x2) · `gv_picking_tanda_calc` ·
> `gv_armado_tanda_calc`, más `COLA_AUTO` de `index.html` y el `AUTO` de `monitor/build-admin.cjs`. Son las
> mismas 5 que ya nombran a PKG / NPD / PKAX.

- `gv_tanda_ubicacion` suma AUI como cuarta fuente, con **`fuente = 'armado_mesa'`**; sigue ganando el `ts`
  **más reciente**, así que la secuencia PUB → AUI → AUB se ordena sola. En la TV y en el Mon. Admin el chip
  dice **📍 Mesa 1** y el `title` **«la están armando acá»**.
- Probado como `anon` en transacción abortada (AP + AUI 2 s después): los dos **entran**, el trigger
  `gv_evento_duplicado` descarta **0** (su R1 exige `ts_inicio` en las dos filas) y la ubicación de F86A pasó
  de **AB7 (armado)** a **Mesa 2 (armado_mesa)**.

**Chequeo:** `select * from public.gv_reglas_perdidas;` y `select * from public.gv_huellas_cambiadas;` (las dos
vacías) · `node tests/arm-mesa-inicio.cjs` (corre la pantalla: el AP con mesa encola AP+AUI, sin contestar no se
encola AUI, el cuadro que explota **no** traba el asistente) · `node tests/mon-tv.cjs`.
`sql/gv_armado_mesa_aui_v2990.sql` (rollback al pie).

## REGLA (Luis, 2026-10-14, v30.29): LIQUIDAR un código viejo dentro del picking de su reemplazo

`PK_LIQUIDAR_EN` (index.html): `"574E" → 574 LK, F50`. Mientras el 574 tenga saldo terminado > 0
(`vista_saldos_stock`), el picking que pida 574E levanta primero las cajas del 574 (paso propio, su
PKC descuenta el 574) y el resto del 574E. Al llegar a 0 se apaga solo; si la consulta falla, picking
normal. El pedido y la factura siguen en 574E. Para liquidar otro código: sumar una fila al mapa.
Test: `tests/pk-liquidar-574.cjs`.

**v30.30 (Luis, 14/10): el 574 queda DISCONTINUADO cuando se fue.** `gv_liquidado_discontinuar()` (cron
160 `gv-liquidado-discontinuar`, 05:13 ART) da de alta el 574 en `Articulos_Discontinuados` cuando hay un
PKC del 574 con real > 0 desde el 14/10, su tanda tiene remito (CRN) y el saldo del 574 es 0 en todos los
depósitos. El alta dispara la liberación de la góndola F50. `select * from gv_liquidado_discontinuar(true);`
simula. `sql/gv_liquidado_discontinuar_v3030.sql`, centinela v30.30 (la app salió en la v30.31).

## 🗄 RETIRADO — sólo revisar si se pregunta por algo ANTIGUO que no está arriba

> Reglas, versiones y hallazgos que **ya no valen**. Se guardan como historia, no como instrucción.
> **No leer esta sección en el trabajo normal**: sólo cuando alguien pregunta por un comportamiento viejo
> y no aparece en las reglas vigentes de arriba. Nada de acá se vuelve a aplicar sin un pedido explícito.

- v26.64: «el m³ de la tanda sigue acreditándose a quien da el TP/TAP final». Retirado en la v26.67.

- v26.67: «el puntaje 1-10 de picking sigue sin las tandas frenadas». Retirado en la v26.74 (D17).

## ⚠ REGLA (Luis, 2026-10-13, v30.24): CUPO DE SUSTITUTO — las próximas 9 cajas de 809E de Chef se pickean del 809 nacional

**Luis:** *"las próximas 9 cajas que entren de pedidos para la 809E de chef manden al que pickea a pickear esas 9 de 809 nacional"*.

- Tabla `GV_Pick_Sustituto_Cupo` (empresa, cod_pedido, cod_pick, cajas_cupo, cajas_usadas, activo) y el uso en
  `GV_Pick_Sustituto_Uso`. Trigger `zz_gv_pick_sustituto_cupo` en `PPP_Web_Base` (insert o cambio de `np_label`):
  línea `809E` de **chef, sin L**, con NP → `Correcciones_Pedido` (np, 809E → 809, `origen = 'cupo'`). El picking
  (`corrArt`) y la etapa 2 del armado (`gv_entregas_norm`) ya aplican esa tabla. La NP y la factura siguen en 809E.
- **Una línea no se parte**: si no entra entera en lo que queda del cupo se saltea y espera la próxima. Al llenarse
  el cupo queda `activo = false`. Sirve para cualquier otro par: es un `insert` en la tabla del cupo.
- Lo que ya estaba cargado al 13/10 no se toca (forward-facing). `sql/gv_pick_sustituto_cupo_809_v3024.sql`.
- Chequeo: `select * from public."GV_Pick_Sustituto_Cupo"; select * from public."GV_Pick_Sustituto_Uso";`
- **Pendientes sin pickear, del más reciente al más viejo (Luis, 13/10, "para liquidarlo")**: cupo bajado a **8**
  (9 en M16 − 1 que ya pide CH 0066 como 809). Asignado **CH 0064 (F48O) 2 cajas → 809**. CH 0063 (F48M, 8 cajas)
  no entra entera en las 6 que quedan; las 6 esperan la próxima línea que entre. Las demás NP con 809E ya están pickeadas.
- **D3 (Luis, 13/10)**: en vez de CH 0064 se asignó **CH 0063 (F48M) 8 cajas → 809**, que liquida el 809 justo. Cupo 8/8, apagado.
- ⚠ **v30.25: el trigger mira sólo pedidos NUEVOS** (`creado_at` ≥ alta del cupo). El sync de la web reescribe NP viejas
  y a las 17:30 le asignó el cupo a **CH 0019** (pickeada y facturada el 02/10); se sacó a los 2 min, sin movimiento de stock.
