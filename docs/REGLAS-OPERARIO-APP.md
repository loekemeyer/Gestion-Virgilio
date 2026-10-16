# Reglas Operario App — App del operario: login con clave de TV, botonera, toggles, deshacer, legajo de prueba, módulos con Enviar/Anular, ayuda

> Movido de `CLAUDE.md` el 2026-10-13 (poda 3ra tanda, pedido de Luis) **sin cambiar una palabra**.
> **Leerlo ENTERO antes de tocar algo de este tema.** Las reglas siguen valiendo igual que cuando estaban en CLAUDE.md.


## 🟥 REGLA (Luis, 2026-10-16, v31.78): desde el sáb 17/10 00:01 el operario entra por RP3.0 — el código de la TV se apaga

*"el login con ingreso por Código TV quiero que el sábado 17 a las 00:01 deje de aparecer en la landing (quede inusable)
y lo reemplace un botón que sea Login Operario que vincule a la página de RP3.0"*.

- **Front** (`index.html`, `_gvClaveTvApagada`): desde `2026-10-17T00:01:00-03:00` se oculta `#legajoLoginRow` (código,
  nombre, legajo) y aparece **«Login Operario»** → `https://rp.loeke-erp.com/` (misma pestaña). Re-chequea cada 30 s:
  la pantalla abierta cambia sola. `loginConClaveTv` / `loginConLegajoTv` / `loginConNombre` no hacen nada.
- **Servidor**: `gv_tv_clave_validar` devuelve `{ok:false, error:'migrado'}` desde la misma hora, para el celular con el
  index viejo cacheado; el index nuevo, al recibir `migrado`, muestra el botón. RP3.0 valida con su propia función
  (`reg_prod_3_0_virgilio_operarios`): no la toca. Google (supervisores) sigue igual.
- `sql/gv_login_operario_rp3_v3178.sql`, `tests/login-operario-rp3.cjs`. Los tests del flujo viejo corren el corte al
  futuro con `window.GV_CLAVE_TV_CORTE_TS`.

## ⚠⚠ REGLA (Elías, 2026-10-13, v29.84): el CÓDIGO DE LA TV no se entrega a la clave pública — y se prueba de a uno cada 2 s

**Elías:** *"1 hay que cambiar"* · *"no es anon, tiene que ser al enviar con el token que se obtiene de la pantalla"* ·
*"limitar a cada 2 seg. y hacer que sólo sea aceptable el código anterior durante 5 segundos después que desaparece de la
TV … y se le puede hacer que envíen su mac a los 6 intentos"* (Virgilio y Cervantes).

| pieza | qué hace |
|---|---|
| **`gv_clave_chequear`** (no la llama nadie de afuera) | el limitador ÚNICO de los 4 validadores (Gestión, 3.0 Virgilio, 3.0 Cervantes, tablet GP2): un intento fallido frena esa IP/equipo **2 s** (`espera`; serializado con `pg_advisory_xact_lock`, sin eso dos intentos simultáneos no se veían) · el código del minuto anterior vale sólo los **5 s** siguientes (65 s de código activo) · desde la **6.ª falla en 10 min** pide el equipo (`gv_dispositivo` + huella + navegador; la MAC no la da el navegador) y avisa por Telegram · **10 por equipo / 40 por IP** → `bloqueo`. Log `GV_Clave_Intento` |
| **TV de pared** | guarda un SECRETO propio (`localStorage gv_tv_secreto`) y pide el código con él (`gv_tv_clave_actual_tv`). La 1.ª vez muestra a la izquierda un código de 6 dígitos que un supervisor aprueba en **⚙️ Configuración → 📺 Vincular TV** (ahí también se desvincula) |
| **Mon. Admin / Vista TV / header del monitor** | piden el código con la sesión del supervisor |
| un solo helper | `monitor/tv-clave.js` (lo cargan tv.html, admin.html e index.html) |

- `GP2.monitor_clave_validar` ya no se puede llamar con la clave pública.
- ⚠ **PARTE B pendiente** (sacarle `gv_tv_clave_actual` a la clave pública): se aplica cuando Elías confirma que la TV ya
  muestra el código vinculada. Hasta entonces el helper cae a la clave pública si la TV no está vinculada.
- `sql/gv_tv_seguridad_v2974.sql` (parte A aplicada el 13/10, parte B comentada), `tests/tv-clave-segura.cjs`.

## ⚠ REGLA (Luis, 2026-09-29, v23.87): el operario NO vuelve a la pantalla del legajo

- Después de registrar una tarea (`send()`) **se queda en su botonera**; al «Resumen de hoy» se va con la ← de arriba.
- Si ya eligió Virgilio HOY (`localStorage.vir_planta_dia`, se guarda en `chooseVirgilio`), una recarga lo lleva
  **directo a la botonera**, sin selector de planta ni pantalla del legajo. Se borra con «Cambiar planta», Terminar Día
  o cerrar sesión; vale el día calendario. `tests/operario-queda-botonera.cjs`.

## ⚠ REGLA (Luis, 2026-09-29, v23.82): el operario entra con la CLAVE DE LA TV

La TV (`monitor/tv.html`) muestra chiquito **🔑 + 4 dígitos** (`gv_tv_clave_actual`, cambia cada **15 min**, vale
también la anterior). En el celular: clave → **elige su nombre** (los que tienen eventos en Virgilio en los **últimos 15 días**, sin mirar la sede — v23.84, `gv_tv_clave_validar`) o **＋ No estoy en la lista** → legajo. **Desde la v23.83 el legajo entra también SIN clave** (Luis: *"que puedan loguearse con pin o con legajo. No los limitemos"*): botón «Entrar con mi legajo». Google (supervisor) sigue igual.
⚠ **No es un candado**: la TV lee con la clave pública; es para que se entre estando en el depósito. La clave sale de un
md5 del `system_identifier` del cluster (no hay secreto en el repo, que es público).
**Lista = los que trabajaron en Virgilio en 15 días** (v23.84); apodos en la lista: 104 → «J. Colombia», 277 → «Jhonny» (v23.85, en `gv_tv_clave_validar`).
`sql/gv_tv_clave_v2382.sql`, `tests/tv-clave-login.cjs`.
⚠⚠ **v27.56 (Thomas, 06/10): «sacá todo el módulo de registro con legajo» — NO hay entrada tipeando el legajo.** Se
retira el «legajo sin clave» de la v23.83. Se entra con la clave de la TV → nombre de la lista; quien no está toca
«＋ No estoy en la lista» → tipea su nombre y entra con el legajo 600 (v27.37), y un admin lo valida en ⚙️ →
«Validar Operarios». `loginWithLegajo` quedó como alias que abre ese paso. Lo mismo en `Registro-Produccion-3.0` (v30.07).
⚠ **v27.71 (Thomas, 07/10): EXCEPCIÓN CERVANTES hasta que tenga su TV** (*"vamos a implementar una tv en cervantes también …
hasta entonces, habilitá la entrada con legajo en cervantes"*). En la pantalla de la clave hay **«Trabajo en Cervantes · entrar
con legajo»**: valida el legajo contra `Empleados`, guarda la sesión con `soloCervantes`, registra el ingreso como
**`legajo_cervantes`** y va derecho a `./cervantes/`. Con esa sesión **Virgilio no entra** (`chooseVirgilio` pide el código de la
TV y borra la sesión). El monitor y la alarma de Virgilio no cuentan ese ingreso (sólo `clave_tv` / `nombre`, v27.68). Al poner
la TV en Cervantes, sacar este botón. `tests/cervantes-legajo.cjs`.
⚠⚠ **v30.39 (Luis, 14/10): SE SACÓ «Trabajo en Cervantes · entrar con legajo».** Cervantes ya entra con su TV en
Registro Producción 3.0 (`/cervantes-gp2/`). Fuera el botón, el paso `tvCervStep` y `tvMostrarCervantes` /
`loginCervantesLegajo`. **No volver a ponerlo.** Se dejó el ruteo `soloCervantes` (64360/64422) para que una sesión ya
guardada ese día siga yendo a `./cervantes/` hasta vencer. `tests/cervantes-legajo.cjs` ahora controla que NO esté.

## ⚠ REGLA (Luis, 2026-10-13, v29.50): los INSTRUCTIVOS de pared se GENERAN, no se dibujan

Hoja de **40 × 50 cm** con el paso a paso de un módulo, pantalla por pantalla, para colgar en el
depósito. El primero: **recepción de mercadería de un tallerista**
(`docs/instructivos/recepcion-tallerista.pdf`).

> **Las capturas salen de correr la app con Playwright, nunca de un dibujo ni de una foto de
> pantalla.** Si cambia una pantalla, se rehace el instructivo y vuelve a quedar igual a lo que ve
> el operario: `docs/instructivos/caps-recepcion/_generar-capturas*.cjs` →
> `node scripts/instructivo-recepcion.cjs` (imprime cuántas páginas salieron: **tiene que decir 1**).

- Los pasos viven en la lista `PASOS` del generador; el reparto en 5 columnas y el ancho de cada
  columna se calculan solos para que no quede hoja en blanco al pie (regla de espacio del dueño).
- Los datos son de ejemplo (Lucho, remito 40873, códigos 505/518/586 con su OC): salen del mock,
  no de la base.
- ⚠ El `input type=date` de Chromium headless pinta `MM/DD/AAAA` y el celular `DD/MM/AAAA`: el
  script lo reemplaza antes de la captura.
- Al cambiar un módulo del operario se actualizan **el manual** (`ayuda/manual-operario.md`, regla
  v29.19) **y el instructivo del módulo** si existe. `docs/instructivos/LEEME.md`.

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

## ⚠ REGLA (Thomas, 2026-10-06, v27.58): el LEGAJO 1 pregunta antes de registrar y tiene 10 min para deshacer

Para probar el programa de punta a punta. Con el legajo **1**, cada «Enviar» de la botonera (`send()`) pregunta
*«Legajo 1 (prueba): ¿querés que esto se REGISTRE de verdad?»*; «Cancelar» no registra nada. Si se registra, el
Deshacer dura **10 min** (`_undoWindowMs`, ≡ el tope de `gv_deshacer_evento`); el resto de los legajos sigue en 60 s.
Lo que pasa adentro de un módulo abierto con «sí» (cada código del picking, el armado, el guardado) no vuelve a preguntar.
⚠ **v27.63 (Thomas, D13): el legajo 1 CUENTA en el MONITOR** (vista `gv_monitor_horas_operario_dia`, marcador `v27.59-leg1`, TV, Mon. Admin, monitor del index) y Bajar/Ingreso a racks ya manda su tramo. Sigue excluido en la alarma de inactividad, la planilla de horas (`gv_horas_operario_detalle_v2`), productividad y reportes. `sql/gv_monitor_legajo1_v2763.sql`.

⚠ **v27.65 (Thomas, D16: *"si entro por tv pero no marco nada, es tiempo muerto"*): los monitores leen el INGRESO de verdad.** TV, Mon. Admin y el monitor del index leían `Fichadas_Virgilio` (muerta desde el 27/05); hoy leen **`gv_monitor_ingresos(desde, hasta)`** (SECURITY DEFINER, anon; primer ingreso del día por legajo en `GV_Dispositivo_Login`, tipo operario, tope 8 días). El que entró con la clave y no registró nada sale **«entró · sin arrancar (tiempo muerto)»** desde su hora de ingreso. `sql/gv_monitor_ingresos_v2765.sql`.
Va igual en Registro Producción 3.0 (v30.09). `tests/legajo1-confirma.cjs`.

## ⚠ REGLA (06/10/2026, v27.46): el DESHACER (60 s) del operario va por RPC — nunca DELETE

Caso **F46A** (legajo 191, 17:39): el operario tocó «↩ Deshacer» sobre su EP, el celular mandó
`DELETE …Registros_Produccion_Virgilio?client_id=eq.…` con la clave pública y **anon no tiene DELETE**: 401
silencioso, el celular dijo «Mensaje deshecho» y la TV siguió con «Pickeando F46A» y la tanda tomada. Además
borrar libera el `client_id` y la cola offline resucita el evento (regla v18.71).

Hoy `undoLastSent` llama a **`gv_deshacer_evento(client_id, legajo)`** (`_gvDeshacerServidor`, reintenta 4 veces
si el evento todavía no llegó): **EP** → `gv_anular_picking_virgilio` (EPX + suelta la reserva) · **AP** →
`anular_armado_virgilio` · el resto → `<opcion>X`. Sólo el propio legajo y los últimos 10 min.
**Deshacer un TP/TAP es como si nunca hubiera ocurrido** (Thomas, D3, v27.50): TPX/TAPX, la fase vuelve a
`tomada` por ese legajo, el TP sale del caché del puntaje (`GV_Picking_Tanda`) y se reconcilia el stock.
`sql/gv_deshacer_evento_v2746.sql`, `tests/deshacer-evento.cjs`. Mismo arreglo en `Registro-Produccion-3.0`.

## ⚠ REGLA (2026-10-01, v25.95): lo que VOLVIÓ y se recarga arranca el plazo de control DE NUEVO

- Un pedido que salió, volvió (↩ s/salida en RR = **FSS**) y se recargó (CCN nuevo) cuenta las 30 hs de
  Recepción Remitos desde la **primera carga posterior a la vuelta**, no desde la primera de todas.
  Lo resuelven `vista_control_remitos.first_load` (CTE `fss_prev`) y `_pppCargasCiclo` (PPP, alarma CRA).
  Caso: LK 0122 / LK 0177 salían VENCIDOS recién recargados el 01/10.
- Lo que volvió y **no** se recargó **se queda en «Pedidos atrasados»** con el badge **↩ VOLVIÓ** (`_pgaVolvio`,
  mismo cuerpo de tabla que la Programación) y lo vuelve a ofrecer Carga Camión (ya lo hacía, v6.66). Luis, 01/10:
  *"está bien que se quede en atrasados, pero que esté con el badge"* — **no** pasarlo al día de hoy de la Programación.
- `sql/vista_control_remitos_ciclo_v2595.sql`, `tests/rr-volvio-ciclo.cjs`.

## ⚠ REGLA (Luis, 2026-10-15, v31.01): Terminar Día NO PREGUNTA — avisa qué se cierra y cómo

**Luis:** *"Cuando terminan el día con tareas abiertas, tiene que avisar que se van a cerrar y cómo. Cuando cierran un
armado o picking en curso, debería simplemente decirles que queda registrado lo que hicieron hasta ahí y se puede retomar
por ellos (o por otra persona) al día siguiente."*

| abierto al Terminar Día | qué ve | qué pasa |
|---|---|---|
| picking / armado | «⏸ Tanda en curso — queda frenada»: *queda registrado lo que pickeaste/armaste hasta acá. Mañana lo podés retomar vos u otra persona* | sigue «continúa» en el celular (`st.continuar`); el cron 129 la **frena** al fichar salida (regla de frenar, `REGLAS-PICKING-ARMADO.md`). Ya no hay «Finalizar ahora»: no sale TP/TAP desde el FJ |
| CR / RR | en «⛔ Se cierran ahora, con la hora de este momento» | cierre del toggle con su `ts_inicio` |
| tareas de módulo vivas (`racks`, `ir`, `mg`, `tmov`, `tcp`, `trc`, `tins`) | idem | `tdCerrarModulos`, ANTES del FJ, con su cierre de siempre: RKB «sin bajar», IRT «N palet(s)», MDT (texto = código), MG del Historial |
| tarea de módulo vencida (> 12 h) | no se lista | se limpia sin evento (como ya hacían sus cierres) |

Hasta la v31.00 esas tareas de módulo no se cerraban con el FJ: en la base quedaba la apertura sin cierre.
`tests/td-cierra-tareas.cjs`.

## ⚠ REGLA (Luis, 2026-10-05, v26.57): un picking o armado abierto al terminar el día se RETOMA con su avance

**Luis:** *"si uno termina el día con un picking o armado abierto, queda guardado con la data que se llegó a
generar y se puede retomar después? debería ser así"*. En Terminar Día, «Continúa mañana» (el default) deja la
tarea abierta y al otro día sale «▶ Continuar».

| tarea | dónde vive el avance | cuánto dura |
|---|---|---|
| picking | `vir_pk_<legajo>` en el celular **+** los PKC en el servidor (`pkResumeServer` lo reconstruye en otro celular) | mientras el picking siga abierto (v5.91) |
| armado | **sólo** `vir_comp_<tanda>` en el celular (TAL, ENT y Entregas salen recién al Terminar) | 36 h, o **más mientras el armado siga abierto en ese celular** (v26.57) |

⚠ Hasta la v26.56 el avance del armado se borraba a las 36 h aunque siguiera abierto: todo armado del **viernes a
la tarde que se seguía el lunes** (~65 h: D45B, D52C, D67F; F22A al 05/10) arrancaba de cero. `_compSigueAbierta`.
⚠ **Lo que sigue sin cubrirse:** el avance de un armado sin terminar **no está en el servidor**. Retomarlo en
**otro celular** (o con el celular reseteado) arranca de cero; el picking no tiene ese problema.
`tests/tarea-abierta-otro-dia.cjs`. → **Desde la v26.61 el armado SÍ viaja al servidor** (regla de abajo); leerlo para
retomar en otro celular es la parte 2.

## ⚠ REGLA (Luis, 2026-10-05, v26.83): en BAJAR DE RACKS, GUARDADO e INGRESO A RACKS, «Cerrar» MINIMIZA y «Anular» SALE

**Luis:** *"si envía bajada de racks y cierra con el botón de cerrar de arriba, se debería considerar que sigue bajando
de racks por más que no haya elegido nada … agregar un botón abajo de registrar bajada que sea «Anular bajada» para que
pueda salir sin quedar atrapado si entró por error al módulo. Lo mismo con guardado a góndola"* · *"fijate si hay algún
otro módulo donde aplique este problema"* (sí: Ingreso a racks).

| módulo | «Cerrar» de arriba | volver a entrar | botón abajo |
|---|---|---|---|
| BR Bajar de racks | minimiza (`rkbAskClose`): sin RKB, tarea abierta, BR rojo | la MISMA bajada, mismo tramo (sin RKI nuevo) | **⛔ Anular bajada** → RKB `ANULADO` |
| MG Guardado (lo que llegó / excedente) | minimiza (`mgAskClose` / `excAskClose`): sin MGC | `_mgReabrirMinimizado`, mismo tramo (sin MGI nuevo; `st.mg.tramo`) | **⛔ Anular guardado** → MGC `ANULADO` + cierra la tarea |
| IR Ingreso a racks | minimiza (`irMinimizar`): sin IRT | mismo tramo (sin IRI nuevo) | **⛔ Anular ingreso** (sin palets) o **🏁 Terminé de ingresar** |

- **Aunque la app se reinicie** el tramo sigue con su hora de inicio: sale del estado del legajo (`_gvTramoVivo`,
  `_mgTramoAbierto`), con el tope de 12 h de `_gvModVivo`. Caso: Isidro (94) entró 3 veces a BR el 05/10 y cada RKI
  nuevo mandaba el tiempo anterior a tiempo muerto (0:32 de 11:18 a 11:50, más la alarma de 5 min).
- Medido antes del cambio: **0 RKB «sin bajar» y 0 IRT en toda la historia** — nadie apretaba «Cerrar»: los módulos se
  perdían con el reinicio de la app. La app no se recarga sola para actualizarse con uno de estos módulos abierto
  (`_gvAppInactiva`).
- **ANULADO no es movimiento**: la vista ya lo saca de `mov_s` y `fetchMonitorDayStats` también (≡). Son segundos y caen
  en tiempo muerto; la vista no se tocó.
- El cierre de verdad sigue igual: «Registrar bajada» (RKB con cajas), «Guardar» / «Terminé de guardar», cargar palets.
- `tests/modulo-minimizar-anular.cjs` (verificado que falla contra la v26.82).

## ⚠ REGLA (Luis, 2026-10-01, v25.63): todo módulo que abre tarea tiene ⛔ ANULAR — y la anulación QUEDA REGISTRADA

**Luis:** *"RR tampoco tiene botón de anular, así que si entrás al módulo y no hacés nada, no podés salir · que
puedan salir anulando la tarea completamente · que se registre que apretaron para empezar a hacer algo y que la anularon"*.

- **RR, CC (chooser y lista) y CR** tienen **⛔ ANULAR** con la lista cargada (antes sólo había «Cerrar (sigo
  después)», que minimiza y deja el toggle abierto trabando EP/AP). El admin de RR no lo lleva (no tiene toggle).
- **ANULAR = `gvToggleAnular(legajo, code)`**: cierra el toggle con su MISMO código, `ts_inicio` = la apertura y
  **texto `ANULADO`**. En el log quedan la apertura (cuándo apretó) y el cierre anulado; el tramo sale en el horario.
- **RT, RI y EI ya no BORRAN la apertura** (`anular_toggle_virgilio` queda sin llamador): registran igual el cierre ANULADO.
- Picking y armado ya lo registraban (EP→EPX, AP→APX). MG/racks/IR/CP/RC cierran con su X y dejan su marca (MGC, RKB «sin bajar»).
- **v25.64 (Luis, 01/10: *"se cuenta, es tiempo muerto. forward facing"*): el tramo ANULADO de CC/CR/RR/RT/RI/EI va a
  NO PRODUCTIVAS** (`gv_monitor_horas_operario_dia`, marcador `v25.64-anulado` ≡ `fetchMonitorDayStats`,
  `ANULADO_NOPROD_CODES`). El de picking/armado anulado (EPX/APX) sigue sin contar.
- **v25.68 (Luis, 01/10): NO es tiempo muerto.** Queda en no productivas, **discriminada como «❌ Cancelación de tarea»**
  con su tiempo (el pop-up de No productivas del monitor la rotula y suma aparte). El contador «Tiempo muerto» de la
  botonera NO la suma. `tests/noprod-cancelacion.cjs`.
- `tests/toggle-anular.cjs`, `tests/anular-sesion.cjs`.

## ⚠ REGLA (Luis, 2026-10-01, v25.67): la BOTONERA muestra el TIEMPO MUERTO y el HISTORIAL — el operario no vuelve atrás

- **⏱ Tiempo muerto** arriba de la botonera: lo que lleva HOY sin ninguna tarea registrada =
  `hs_total − hs_prod − hs_mov − hs_noprod` de `gv_monitor_horas_operario` (la misma cuenta que la TV). Se relee
  cada 60 s y entre lecturas corre sólo si no hay tarea abierta (picking, armado, toggle, baño/comida). Sin
  lectura dice «—». Rojo desde 30 min. `tmStart` / `tmLeer`.
- **📋 Historial de tareas**: pop-up con el MISMO «Resumen de hoy» (`renderLegajoHistory`); el nodo
  `#legajoHistoryContent` se muda al pop-up y vuelve al cerrar — una sola lista.
- **El Deshacer (60 s) vive en la botonera** (`#undoBanner` dentro de `#optionsScreen`): desde la v23.87 el
  operario se queda ahí después de enviar y el banner en la pantalla del legajo no lo veía nadie.
- La alerta de **un dispositivo con 2+ operarios** ya es por DÍA (`gv_dispositivo_multi_operario` agrupa por
  dispositivo + día AR; el Telegram mira sólo hoy): otro operario mañana en el mismo celular no avisa.
- ⚠⚠ **v25.78 (Luis, 01/10): el contador NO es el acumulado del día** (*"se tiene que reiniciar cuando el operario
  empieza/termina una tarea"*): es el tiempo desde el ÚLTIMO evento del legajo (`enqueueReport` lo sella con
  `tmMarcarEvento`; la base aporta el último `ts_cliente` de hoy), y con una tarea abierta marca 0:00:00. Se retiran
  la cuenta de `gv_monitor_horas_operario` y el acumulado local de la v25.70 (bullet de abajo, histórico).
- **v25.70**: sin fila en la vista (legajo de prueba, que se excluye, u operario sin eventos) el contador acumula EN EL
  CELULAR por legajo y día (`gv_tm_loc::<día>::<legajo>`) — antes volvía a 0 en cada lectura y entre tareas. El 📅
  flotante (`#btnHistDias`) no se muestra en la botonera (tapaba «Terminar Día»): los días anteriores se abren desde
  el pop-up del historial.
- `tests/botonera-tm-historial.cjs`.

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

## ⚠ REGLA (Luis, 2026-09-30, v25.25): cada celular/PC se IDENTIFICA — eventos e ingresos llevan `gv_dispositivo`

**Luis:** *"¿puede el sistema identificar el dispositivo que se está logueando?"* · *"forward facing, no le cagues a
nadie la sesión abierta"*.

- Cada navegador genera UNA vez un UUID (`localStorage.gv_dispositivo`, `gvDispositivoId()`) y lo manda con cada evento
  (`Registros_Produccion_Virgilio.gv_dispositivo`) y con cada ingreso (`GV_Dispositivo_Login`: uno por dispositivo +
  persona + día, con el método google / clave_tv / legajo / sesion_guardada y el user agent).
- **No es el IMEI ni el serie** (el navegador no los da): borrar los datos de la app o reinstalar genera un ID nuevo.
- Forward-facing: lo anterior queda NULL, no se desloguea a nadie; si el envío del ingreso falla, no pasa nada.
- `anon` sólo INSERTA; se lee por el MCP: `select * from public.gv_dispositivos order by ultimo_ingreso desc;`
- **Un mismo dispositivo con 2+ operarios en el día** (v25.26, Luis: *"que quede registrado"*):
  `select * from public.gv_dispositivo_multi_operario order by dia desc;` — cruza ingresos y eventos.
- **Y avisa por Telegram** (v25.29, Luis): cron `gv-alerta-dispositivo-multi` (jobid 118, `5-59/10`) →
  `gv_alerta_dispositivo_multi_operario_telegram()`, un mensaje por cada operario NUEVO en el mismo dispositivo en el
  día (dedup por dispositivo + día + legajos). `sql/gv_dispositivo_multi_telegram_v2529.sql`.
- `sql/gv_dispositivo_v2525.sql`, `tests/dispositivo-id.cjs`.

## ⚠ REGLA (Luis, 2026-10-08, v28.67): LOGIN = clave de la TV → lista · «Soy otro» → legajo · sin legajo → nombre (ENTREVISTA con legajo PROPIO)

- Clave de 4 dígitos de la TV → lista de nombres → **«＋ Soy otro»** → tipea el **legajo** (`loginConLegajoTv`, metodo
  `clave_tv`; 0, 1, 600 y 6001-6999 no entran) → **«No tengo legajo»** → tipea el nombre (`loginConNombre`). Retira el
  «sin campo de legajo» de la v27.56: el legajo vuelve, pero SÓLO después de la clave de la TV.
- **Cada entrevistado tiene SU legajo: 6000 + id de `GV_Operario_Alta` (6001-6999)**, dado de alta en `Empleados` como
  «<nombre> (entrevista)»: el monitor lo muestra por nombre y no mezcla a los entrevistados. Si el nombre tipeado es el de
  un empleado activo, entra con el legajo de ese empleado (caso Kevin Latronico = 504). Lo hace `gv_operario_alta_crear`;
  `es_legajo_entrevista` / `esLegajoEntrevista` aceptan 600 (viejo, de respaldo si la RPC no contesta) y 6001-6999; al
  validarlo, `gv_operario_alta_validar` desactiva el legajo de entrevista. `sql/gv_entrevista_legajo_propio_v2867.sql`,
  `tests/tv-clave-login.cjs` (e).

- **v28.69 (Luis, 08/10): un celular con el 600 compartido y el nombre de un EMPLEADO ACTIVO registra con SU legajo** (trigger `aa_gv_registro_entrevista_a_empleado`). Caso Kevin Latronico (504). `sql/gv_registro_entrevista_a_empleado_v2869.sql`.
  **v28.71**: el evento 600 SIN nombre (PKC…) toma el legajo del ingreso de hoy de ese mismo celular.

## ⚠ REGLA (Luis, 2026-10-09, v29.04): IR, Mover racks, Insumos, Completar Pedido y Pasar a urgente se ENVÍAN como BR/MG

- Primer toque SELECCIONA, «Enviar» EMPIEZA la tarea (evento **MDI**, `texto` = MOV/INS/CP/RC) y abre el módulo; abierta, el botón queda rojo y tocarlo RE-ABRE el mismo módulo (retomar, mismo tramo). Abajo, barra con **⛔ Anular** (MDT `ANULADO` → no productivas) y **🏁 Terminé** (MDT con `ts_inicio`). IR sigue con IRI/IRT y también va por «Enviar».
- `MOD_TAREA` en index.html; tope 12 h (`_gvModVivo`). Vista `gv_monitor_horas_operario_dia` y `gv_horas_operario_detalle_v2` (marcador `v28.93-mdt`): MDT suma a Hs MOV ≡ `fetchMonitorDayStats`; TV / Mon. Admin «En este momento». `sql/gv_modulo_tarea_mdi_mdt_v2893.sql`, `tests/modulo-tarea-enviar.cjs`.

## ⚠ REGLA (Luis, 2026-10-13, v29.81): una BARRA FIJA abajo NO TAPA NADA — se le hace lugar

**Luis, con la captura del celular:** *"la barra de abajo con «Anular» y «Terminé» tapa opciones y botones
(aparece arriba de algo que esté al fondo de la lista). Ajustalo en todos los módulos para que no tape
nada (prioriza visión de smartphone)"*.

> **Una barra `position:fixed` abajo se descuenta del alto de lo que hay detrás; no se dibuja encima.**

- `#modTareaBar` (⛔ Anular · 🏁 Terminé de Mover racks, Completar Pedido, Pasar a urgente e Insumos) mide
  su alto y **`_modTareaColchon(px)`** le hace lugar: cada overlay de `MOD_TAREA[*].ovs` que está en
  pantalla pasa a `bottom: <alto>` (termina arriba de la barra, así su scroll llega hasta el final) y el
  `body` lleva el mismo `padding-bottom` para la botonera de atrás. Al irse la barra, todo vuelve.
- **La lista de overlays sale de `ovs`**, que ya existía: al agregar un módulo a `MOD_TAREA`, sus overlays
  van ahí y el colchón lo hereda solo.
- ⚠ Un overlay **sin scroll** (los de Insumos, con la tarjeta centrada) no se arregla con el colchón: su
  tarjeta tiene que ENTRAR arriba de la barra. Hoy entra en un 390 x 740; si alguna crece, el test se pone
  rojo y ahí hay que darle scroll (`overflow:auto` + la tarjeta con `margin:auto`, nunca
  `align-items:center` con overflow: eso deja el borde de arriba inalcanzable).
- `tests/modbar-no-tapa.cjs` mide **en 390 x 740** con la pantalla corriendo: la barra pegada abajo, el
  overlay terminando justo en ella, el último renglón de una lista larga por encima, el colchón del body y
  que al cerrar vuelva todo (verificado: 12 chequeos en rojo contra la v29.78).

## ⚠ REGLA (Luis, 2026-10-09, v29.17): ❓ AYUDA — el asistente del operario SÓLO sabe el manual

- ⚠ **v29.18 (Luis): SIN BOTÓN en la botonera hasta que esté terminado** (*"nada de esto hasta que esté terminado"*).
  `ayudaAbrir` queda sin puerta; `tests/ayuda-chat.cjs` (d) es candado invertido.
- Chat (`ayuda.js`) → Edge Function **`gv-ayuda`** (verify_jwt off; identifica por la
  sesión o la IP). **Sin herramientas**: no lee ni escribe tablas del negocio; sólo `GV_Ayuda_Log` (service_role, para el
  límite de 20 preguntas/hora por usuario y 400/día). Pregunta ≤ 500 caracteres, historial ≤ 6 mensajes.
- La única fuente es **`ayuda/manual-operario.md`**. Cambiar el manual = editar el .md, `node scripts/ayuda-manual-build.cjs`
  (regenera `manual.ts`) y **redeployar** gv-ayuda. Al cambiar un módulo de la botonera, actualizar el manual en el mismo pedido.
- **Las API keys y el modelo se cargan en ⚙️ Configuración → 🤖 Asistente IA operarios** (v29.18, `openAyudaConfig`):
  la clave va al **Vault** por `gv_ayuda_config_guardar` (supervisor) y **nunca vuelve al navegador** (sólo «termina en
  XXXX», `gv_ayuda_config_leer`). La función la lee con `gv_ayuda_proveedores_server()` (sólo service_role, caché 60 s),
  en el orden de `GV_Ayuda_Config` («Usar este primero»); si uno falla prueba el siguiente. Respaldo: los secretos de
  entorno `GEMINI_API_KEY` / `GROQ_API_KEY` / `OPENROUTER_API_KEY`. **Nunca una clave en el repo**: es público. Sin ninguno, devuelve la sección del manual que coincide por palabras (`buscar.ts`).
- Ningún LLM es inmune al jailbreak: la garantía es que no tiene ninguna capacidad; lo peor es una respuesta fuera de tema.
- Lo que preguntan: `select ts, usuario, fuente, pregunta, respuesta from public."GV_Ayuda_Log" order by id desc;`
- ⚠⚠ **v29.19 (Luis: *"algo que ajuste el manual en base a los cambios"*): EL MANUAL SE MANTIENE AL DÍA EN EL MISMO COMMIT.**
  gv-ayuda lee el manual **publicado** (Pages, `ayuda/manual-operario.md`, caché 10 min; si Pages no contesta usa el
  empaquetado `manual.ts` y el log dice «(manual empaquetado)»): **cambiar el manual = push a main, sin redeploy.**
  `tests/ayuda-manual-al-dia.cjs` (en run.sh) se pone ROJO si un botón de la botonera no está en el manual o si un
  rótulo que el manual cita entre «…» ya no existe en index.html / recepcion.js. **Al renombrar, sacar o agregar un
  botón o un paso de un módulo del operario, se actualiza el manual en ese commit** (y `node scripts/ayuda-manual-build.cjs`).
- ⚠ **Groq retiró `llama-3.3-70b-versatile` (09/10: 404 model_not_found)**: se pasó a `openai/gpt-oss-120b` (con
  `reasoning_effort: low`). Si un proveedor empieza a fallar, mirar `GV_Ayuda_Log.error` y la lista de modelos del proveedor.
- `sql/gv_ayuda_log_v2916.sql`, `sql/gv_ayuda_config_v2918.sql`, `tests/ayuda-chat.cjs`.

## ⚠ REGLA (v29.24, 09/10): el REPLAY de Terminar Día no re-manda los items SÓLO de Historial (`h_*`)

- `bulkSendDayReplay` re-manda el Historial del día con `client_id = item.id`. Las tareas de módulo (guardado MG, bajar/ingreso
  a racks RKB/IRT, Mover racks / Insumos / CP / RC por MDT) dejan un item de Historial con id `h_*` y su evento real sale con
  OTRO id (`rkb_`, `irt_`, `mdt_`…): el replay los DUPLICABA en el servidor (09/10: 104 y 277, con `h_mg` de opcion MG y el
  tramo entero del módulo, y `h_mdt` con opcion INS). Hoy esos items llevan `noReplay: true` y el replay saltea todo `h_*`.
- Al agregar un item de Historial que no es el evento enviado: `noReplay: true`. `tests/historial-no-replay.cjs`.

## ⚠ REGLA (Luis, 2026-10-13, v29.53, D3): el SERVIDOR reconoce un EVENTO DUPLICADO aunque llegue con OTRO client_id

Luis: *"no habría problema con que los mande de vuelta. el punto es que el server debería procesarlo correctamente e
identificar cuando son eventos duplicados"*. Trigger **`ab_gv_evento_duplicado`** (BEFORE INSERT en
`Registros_Produccion_Virgilio`, después de `aa_gv_registro_entrevista_a_empleado`) → `gv_evento_duplicado()`:

- **R1 mismo tramo**: mismo legajo, `ts_inicio` y `ts_cliente` a menos de 2 s de un evento vivo (no termina en X) con otro
  `client_id` → es el mismo cierre de tarea. Medido 60 días: 3 pares entre eventos «buenos» y los 3 eran duplicados.
- **R2 copia del Historial**: `client_id` h_* con un evento vivo del mismo legajo a menos de 2 s (el guardado cierra con
  MGC, sin `ts_inicio`). Sin gemelo ENTRA: es el único dato.
- Lo descartado queda entero en **`GV_Evento_Duplicado`** (motivo + gemelo): `select * from public."GV_Evento_Duplicado" order by id desc;`
- Los 55 h_* del 02/10 al 09/10 se anularon (RKBX/MDTX/INSX/IRTX y **MGXX**: `MGX` ya es «guardado fuera de lista» y lo
  cuenta `generar_reporte_agentes`, así que al anular un MG se usa MGXX). Backups `zz_backups."GV_Backup_RegH_Replay_*"`.
- Probado como anon en transacción abortada: copias h_rkb / h_mg y R1 con otro id descartadas (3 al log), uno legítimo entra.
- Rollback: `alter table public."Registros_Produccion_Virgilio" disable trigger ab_gv_evento_duplicado;`
  El marcador interno dice `v29.25-evdup` (llave). Centinela `gv_evento_duplicado`. `sql/gv_evento_duplicado_v2950.sql`.

