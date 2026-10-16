# Reglas Programacion — Programación PPP, armado automático, tandas, camiones, zonas, Retira, súper, A Programar

> Movido de `CLAUDE.md` el 2026-10-13 (poda 3ra tanda, pedido de Luis) **sin cambiar una palabra**.
> **Leerlo ENTERO antes de tocar algo de este tema.** Las reglas siguen valiendo igual que cuando estaban en CLAUDE.md.

## 🟥🟥🟥 REGLA (Luis, 2026-09-23, v21.87): UN GRUPO DE ZONAS POR DÍA — y "mismo cliente, mismo día" NO EXISTE MÁS

> ## **DEROGADA: "nunca +1 pedido de un cliente va separado en la PPP".** No se junta al cliente en un día.
> ## Un cliente con sucursales en dos zonas va en **dos días**, cada pedido con el camión de SU zona.

**Luis, textual:** *"Saca esa regla de que se junta al cliente. Un cliente puede tener sucursales en
2 zonas diferentes y lo más importante es eso. En serio saca esa regla porque por más que lo explico
la seguís refiriendo y no va."* Toda mención de esa regla más abajo en este archivo (Thomas v15.52,
el "mismo día para el cliente" del principio rector, el ancla de cliente v20.27, la alarma
`gv_ppp_cliente_dos_dias`) queda **sin efecto**. No citarla, no proponerla, no "respetarla".

**Cómo elige el día el armado desde la v21.87** (`gv_ppp_web_dia_grupo`, pase **(g)** de
`gv_ppp_web_armar_pendientes`; forward-facing: lo ya programado no se toca):

| paso | qué hace |
|---|---|
| plazo | entrada del pedido + **14 días corridos**; por **expreso + 13**. Hacia atrás al día con reparto |
| fecha mínima | la de siempre: `gv_ppp_web_dia_minimo` (4 hábiles, calculado al mediodía) |
| 1 | si su **grupo** (Capital Sur Z1 · Capital Centro Z2 · Capital Oeste Z3, juntas si cada una < 1 m³ · GBA Sur · GBA Oeste · GBA Norte Z6+Z7) ya sale en uno o más días del plazo → **el MENOS cargado de ésos** (m³ del día entero, web + ISIS; v28.55, Luis 08/10: *"distribuí para que queden equilibrados"*; antes iba al primero sin mirar el cupo y el 15/10 juntó 16,57 m³) |
| 2 | si no, el **último día LIBRE** del plazo (sin ningún grupo de reparto), para que los pedidos del grupo que entren después se sumen |
| 3 | si todos los días del plazo tienen otro grupo → **gana el cliente**: el día con menos grupos (segundo camión / flete) |
| 4 | ya vencido → lo antes posible, aunque mezcle grupos: el rezagado no se traba |

- Súper y Retira no son "grupo de reparto" (camión propio / no usan camión) y no ocupan el día.
- Súper con turno, Retira con día elegido, cliente nuevo aprobado (48 h) y diferidos: **sin cambios**.
- Apagados en modo grupo: (a1), (a2), (b00) ancla de cliente, (b0) ancla por número de zona,
  (b) cascada por cupo, (c) zonas manuales, (d) juntar clientes. El INC (auto_super) sigue con su cascada.
- **Interruptor**: `PPP_Web_Config.grupo_dia_activo` — sin fila = prendido; con `valor = 0` vuelve
  la lógica anterior sin redeploy. `sql/gv_programacion_grupo_dia_v2187.sql` (el marcador interno
  dice `v21.80-grupo`: es la llave de idempotencia, no cambiarlo).

**Probado corriendo el armador** en transacción abortada (23/09): Z3 → 30/09 con Centro-Oeste
(E48G), Z4 → 05/10 con GBA Sur (E73A), Z6 sin camión en el plazo → 07/10 (último día libre), un
expreso vencido Z1 → 01/10 con Capital Sur, y el **mismo cliente** en Z3 y Z6 → **dos días**.

## ⚠ REGLA (Luis, 2026-09-23, v21.97): POP-UP de DÍA OCUPADO al programar a mano

Al soltar un pedido en A Programar sobre un día que YA tiene programación, sale un pop-up (`aprDiaOcupadoAbrir`)
con 3 opciones, cada una con su reporte previo (m³ del día contra el promedio 4,30, más de 2 camiones, pedidos
que pasan a vencer): **1) sumarlo** · **2) reprogramar lo PENDIENTE del día con la lógica automática** ·
**3) correr toda la programación desde ese día, 1 día con reparto**. Día vacío → como siempre, sin pop-up.

Lo resuelve **`gv_ppp_dia_reprogramar(fecha, 'correr'|'automatico', simular, por)`** (`simular = true` no escribe;
ejecutando es atómico). **NO se mueven** (Luis): **súper**, **retira fijos**, lo que **ya salió** y una tanda
**EN PROCESO** (pickeo o armado empezado sin TAP). Armada, facturada o pendiente **se mueve con su MISMO código**
(el papel del pallet sigue valiendo). La tanda nueva se arma DESPUÉS de mover, o se correría también.

⚠ **El trigger `gv_web_cliente_un_solo_dia` quedó APAGADO** (23/09): aplicaba la regla derogada "mismo cliente,
mismo día" — frenaba los movimientos y movía solos los otros pedidos del cliente a su día. Rollback:
`alter table public."PPP_Web_Programacion" enable trigger gv_web_cliente_un_solo_dia;`
`sql/gv_ppp_dia_reprogramar_v2197.sql`, `tests/apr-dia-ocupado.cjs`.

⚠⚠ **v26.85 (Luis, 05/10): la opción 2 se REACOMODA ALREDEDOR DE LO NUEVO** (*"si programo un súper para un día que haría que
se zarpe en m³ y/o camiones … que reprograme automáticamente en base a la programación de ese súper"*). Antes sacaba del día
**todo** lo pendiente. Hoy la resuelve **`gv_ppp_dia_ajustar(fecha, p_nuevo, simular, por, cupo, excluir)`**: lo nuevo
queda fijo, y del resto sale **sólo lo que no entra en los 4,30 m³**, siempre de a **grupo de zonas entero** (principio
rector: Z6+Z7 juntas); sale el grupo que menos apura y va al día de `gv_ppp_web_dia_grupo`, uno por grupo.
- ⚠⚠ **v26.88 (Luis, 05/10): NO mueve lo FIJO** (*"no debería mover los fijos (los programados a mano, supers, retira con
  fecha)"*): además de súper, retira, lo salido, lo en proceso y lo armado, queda fijo lo **programado o movido A MANO**, con
  el MISMO criterio que el cron de las 18:00 (`creado_por <> 'sistema'` o `gv_manual_por`, u override de ISIS con
  `gv_manual_por`). Un grupo con una tanda fija no sale. Medido el 05/10: de 57 tandas programadas, **45 a mano** (41 creadas
  por el sistema y movidas desde el panel): la opción 2 tiene poco para mover.
- ⚠⚠ **v26.88 (Luis, 05/10): «olvidate del 2 camiones por día»**: el pop-up y `gv_ppp_dia_ajustar` miden el día **sólo por
  m³**. Se fueron el corte por camiones, el conteo `_adoCamiones` y el aviso «más de 2 camiones». El armador no se tocó.
- ⚠⚠ **v26.93 (Luis, 05/10, D9): la opción 2 NO hace vencer nada** (*"definición de humano si es manual. automático debería
  priorizar que no venza nada"*): un grupo se mueve sólo si su día nuevo (`gv_ppp_web_dia_grupo`) cae dentro del plazo de
  TODAS sus tandas (entrada + 14, expreso + 13, hacia atrás al día con reparto); una tanda ya vencida no se corre más. Si nada
  se puede mover sin vencer, el día queda pasado de m³ y esas tandas salen fijas con el motivo («pasaría a vencer (vence el
  dd/mm)» o «ya está vencida»). La opción 1 (programarlo así igual) es decisión de la persona: no cambia. **«Movido a mano»
  cuenta como manual** (D10).
- El reporte de la opción 2 **cuenta lo que ya tiene el día destino** (la simulación de 'correr' da la carga de cada día).
- Si sumándolo **se pasa de m³**, la opción 1 se llama **«Programarlo así igual»** y el encabezado lo dice.
- La simulación y la ejecución mandan el MISMO `p_nuevo`. El modo 'automatico' de `gv_ppp_dia_reprogramar` quedó sin puerta.
`sql/gv_ppp_dia_ajustar_v2682.sql` + `sql/gv_ppp_dia_ajustar_fijos_v2688.sql` + `sql/gv_ppp_dia_ajustar_sin_vencer_v2693.sql`
(centinelas 320, 321, 324 y 325), `tests/apr-dia-ocupado.cjs` (e)-(k).

⚠ **El pop-up NO es sólo del arrastre** (Luis, 28/09, v23.35: *"fijate que no quede ninguna feature colgada así
porque no estamos arrastrando"*). Lo abren los cuatro caminos que programan un día a mano: soltar un pedido
(`aprDropDia`), **tildar + día + ✅ Confirmar** (`aprConfirmar`, por donde se programó La Anónima al 30/09 sin
aviso), soltar una tanda sin fecha (`aprProgramarTanda`) y reprogramar una NP de ISIS (`pppReprogElegir`). **Al
agregar otro camino que programe un día, pasarlo por `aprDiaOcupadoAbrir(fecha, null, {peds, label, alVacio,
alSumar})`.** `tests/apr-dia-ocupado-sin-arrastre.cjs`.

⚠ **Y también «📅 Cambiar de día»** (v23.44, Luis 28/09): `pppMovElegir` abre el mismo pop-up antes del paso 2
(la tanda que se mueve no cuenta como ocupación, `opt.excluir`). **Y el cron de las 18:00**
(`gv_ppp_reprogramar_sin_factura`) mueve lo no facturado con **`gv_ppp_web_dia_grupo`** salvo lo fijado A MANO
(`creado_por <> 'sistema'` o `gv_manual_por`, que marca el trigger `gv_marca_manual` cuando el cambio trae mail en el
JWT). **No mueve** lo EN PROCESO, lo DIFERIDO por reingreso ni al CLIENTE NUEVO aprobado (avisa), y respeta
*armar → facturar → salir* (sin empezar: no antes del 2.º hábil). **Y NADA de lo programado o movido A MANO se mueve** (Luis
28/09, v23.50): sale `aviso_manual`; lo manual previo al 28/09 se reconstruyó de los logs del panel. `sql/gv_reprog_sin_factura_grupo_v2344.sql`. **Y sólo mueve a un día que YA tiene camión a su grupo de zonas; nunca abre camión nuevo** (Luis 28/09, v23.54: *"maximizar entregas minimizando camiones"*): `gv_reprog_dia_con_camion`, si no hay → `aviso_sin_camion`. `sql/gv_reprog_sin_factura_camion_v2354.sql`. **Y después el mismo cron OPTIMIZA** (Luis 28/09, v23.55): el armado programa a la mejor fecha al llegar el pedido; a las 18:00 `gv_ppp_optimizar_camiones(true,120)` junta camiones enteros del mismo grupo (nada a mano, diferido, empezado ni súper). `sql/gv_ppp_optimizar_camiones_v2355.sql`. **Y desde la v28.56 no junta si el día destino (entero) pasa de 4,30 m³** (Luis 08/10, `sql/gv_ppp_optimizar_cupo_v2856.sql`, centinela 372). **Lo DIFERIDO se arma lo antes posible y el optimizador lo puede juntar** con otro camión del grupo, nunca antes de su piso (Luis 28/09, v23.59, `sql/gv_ppp_optimizar_diferido_v2359.sql`). La alarma «cliente en días distintos» y los carteles «ya en ISIS LK» ya no se dibujan (reglas derogadas).

⚠ **Picking duplicado al cambiar la EMPRESA de un artículo** (v23.42): el trigger `zz_pipeline_empresa_estable` hace
que una fila de picking/separado/facturado de un código NO dual herede la empresa que la tanda ya tiene.
Centinela: `select * from public.gv_stock_pipeline_dos_empresas;` — vacía = todo bien.

## ⚠⚠ NO REPORTAR (Luis, 23/09): "entran N pedidos y no se programan" en el log del armado

`GV_PPP_Web_Armado_Log` / `GV_Tandas_Auto_Log` muestran en CADA corrida pedidos que entran y no arman tanda.
**Es lo esperado y NO es un bug** cuando son: **súper sin turno** (ej. LK 1504 La Anónima, 2 NP, Zona 5),
**cliente nuevo sin aprobar** o **cuarentena**. Luis ya lo revisó 3 veces el 23/09: *"ESTA BIEN que no se
programen automáticamente"*. Antes de mencionarlo, mirar si el pedido es súper (`gv_es_super`), cliente nuevo
o cuarentena; si es eso, **no se dice nada**. Sólo se reporta un pedido común (no súper, no retenido) que no
se programa.

## 🟩🟩🟩 PRINCIPIO RECTOR DE LA PROGRAMACIÓN (Luis, 2026-09-22)

> ## Agrupar pedidos existe para **ENTREGAR LA MAYOR CANTIDAD DE MERCADERÍA EN LA MENOR CANTIDAD DE CAMIONES.**

**Es el para qué de la tanda.** Toda regla de armado, de movimiento y de reprogramación se mide
contra esto: si una decisión hace salir más camiones para la misma mercadería, está mal, por más
que respete todas las demás reglas.

### La consecuencia que se saca mal todo el tiempo: se agrupa POR PEDIDO, NUNCA por cliente

**Luis, textual:** *"Un cliente puede tener sucursales en lugares diferentes (uno que tenga en
Zona 1 y zona 5 por ejemplo, no van a salir juntas en un mismo camión, van a ir en camiones que
vayan a esas zonas)."*

La unidad de agrupamiento y de movimiento es el **PEDIDO** (todas las NP de ese `order_id` juntas),
**no el cliente**. Juntar por cliente parece prolijo y es lo contrario del principio: manda mercadería
a un camión que no va a esa zona, o parte un camión en dos.

⚠ **Al mover un pedido, NO se arrastran los otros pedidos del mismo cliente.** Medido el 22/09:
hay 5 tandas vivas con 2+ pedidos distintos del mismo cliente (E48D tiene **8** de Jazquel). Moverlos
juntos "porque son del mismo cliente" es justamente lo que esta regla prohíbe.

**O sea: tanda por camión · agrupamiento por pedido.** Juntar al cliente en un día está DEROGADO (v21.87, «UN GRUPO DE ZONAS POR DÍA»).


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

## ⚠ REGLA (Luis, 2026-10-16, v31.89): PEDIDOS ANÓMALOS — cartel en el día de la PPP y contacto por el bot

**Luis:** *"notamos que cada tanto hay un pedido anómalo como el LK0364 que pidió 48 cajas de 525E"* (uxb 24: quiso 2).
Cada línea de una NP que espera en la PPP (fecha de hoy en adelante o todavía sin fecha) se mide con tres reglas:

| regla | cuándo | qué pasa |
|---|---|---|
| **historial** | cliente con **3 o más pedidos** en 12 meses: promedio del artículo **< 5 cj** → tope promedio × 5 · promedio **≥ 5 cj** → tope ×2 de su pedido más grande | pasa el tope → **contacta el bot** |
| **em** | cliente con **menos de 3 pedidos**, o con historial pidiendo un artículo **que nunca compró** | peso del artículo en el pedido / peso en la **Est. Madre** (`proy_cajas_mes`, secundario → su principal, dual por empresa) **≥ ×5** y **≥ 10 cj** → **contacta el bot** |
| **cajas_uxb** | cajas múltiplo del uxb (uxb > 1), el aviso de la página (`cajasHintHtml`), **y el cliente nunca pidió tanto** | **sólo el cartel** en la PPP |

- **Historia** = la de los pedidos disruptivos (v26.20): pedidos web y, antes de la web de esa empresa, facturas ISIS
  (una factura = un pedido). Sin cancelados, anulados ni clientes de prueba.
- **Parámetros en `PPP_Web_Config`** (`anomalo_hist_min_pedidos` 3 · `anomalo_hist_prom_max` 5 · `anomalo_hist_factor` 5 ·
  `anomalo_em_factor` 5 · `anomalo_em_piso_cajas` 10 · `anomalo_uxb_activo` 1): cambiarlos es un `update`, no un deploy.
- **D1-D3 (Luis, 16/10, v31.93)**:
  - **D1** `cajas_uxb` sólo si el cliente **nunca pidió tanto** de ese artículo (su máximo < lo pedido). Bajó de 100 a ~39 NP en 6 semanas.
  - **D2** cliente con historial que pide un artículo que **nunca compró** → regla `em`, proporcional a su pedido.
  - **D3** historial con promedio **≥ 5 cj** → anómalo si pide **más que ×2 de su pedido más grande** de ese artículo
    (`anomalo_hist_max_factor` = 2).
- **Pantalla**: `⚠ PEDIDOS ANÓMALOS: X` (X = NP del día) a la IZQUIERDA de la fila del día, afuera de la tabla
  (`_pgaAnomGutter`); en el celular, sin margen, queda adentro de la fila. Tocarlo abre NP · artículo · cajas · regla ·
  motivo · «Bot: a contactar» / «Sólo aviso». La NP lleva `⚠ anómalo` (`· bot` si contacta).
- **Backend**: `GV_Pedido_Anomalo` (una fila por NP + artículo + regla, RLS sin policies) ← cron **167 `gv-ppp-anomalos`**
  (`8-59/10`, anti-solape) → `gv_ppp_anomalos_detectar()`. Lo pendiente que deja de dar (pedido corregido) pasa a
  `sin_efecto` solo. La PPP lee `gv_ppp_anomalos_lista` (supervisor).
- **Bot** (GestOpClientes, Pablo): `gv_pedido_anomalo_bot_pendientes()` (un renglón por pedido, sólo `contactar`) y
  `gv_pedido_anomalo_bot_marcar(ids, 'contactado'|'confirmado'|'corregido'|'descartado', nota)`. Manda por `wa_outbox`
  de LK: la llave `wa_envio_automatico` decide (vasectomía). Hasta que el bot lo lea, el pedido sólo se ve en la PPP.
- Medido el 16/10 sobre 476 NP (entregas desde el 06/09): historial 18 líneas, em 9, **cajas_uxb 176 líneas en 100 NP (21 %)**.
- No confundir con `detectar_pedidos_anomalos` de LK (cron 20, por monto en $ → `Alertas_Pedidos_Web`): sigue igual.
- `sql/gv_ppp_pedidos_anomalos_v3189.sql` · 3 filas en `GV_Reglas_Centinela` · `tests/ppp-anomalos.cjs`.

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

## ⚠ Regla del dueño (2026-09-07, v13.64): ISIS o web, da lo mismo — salvo en Facturación

*"Que el pedido sea de ISIS o cargado por la web no me interesa para absolutamente nada. Lo que me importa
es para el módulo de Facturación, después de eso no."* → **Ninguna pantalla fuera de Facturación separa,
etiqueta ni cuenta aparte lo de ISIS y lo web** (ni "camiones web / ISIS", ni "m³ web", ni Tipo "WEB"). Por
dentro la distinción sigue (NP web = número de pedido con prefijo, facturada = bajar el Excel de ISIS), pero
no se muestra. Al agregar una pantalla o una columna, mostrar todo junto.

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

## ⚠ REGLA (Luis, 2026-10-01, v25.81): una TANDA no mezcla empresas LK/CH

**Luis, por la tanda F21C** (8 NPs de LK + 2 de Chef, todas Zona 1 - CABA Sur). El armador nunca
mezcla empresas (corre por empresa) y la **fusión automática filtra por empresa**, así que la
mezcla la arma una persona desde el panel (fusión manual de una tanda de Chef dentro de una de LK,
vía renombre). No saltaba ninguna alarma porque **los 4 centinelas de tanda cortan por CAMIÓN, no
por empresa**: como ambas son Zona 1 = camión Capital Sur, la mezcla de empresas pasaba invisible.

| capa | qué hace desde v25.81 |
|---|---|
| guard | **`gv_ppp_tanda_empresa_guard(tanda, empresas[])`** frena cualquier asignación manual que dejaría una tanda con las dos empresas. Llamado desde los 4 RPC de asignación a mano: `gv_ppp_nps_mover_a` (fusión / cambiar de día), `gv_ppp_web_tanda_programar`, `gv_ppp_web_tanda_reusar`, `gv_ppp_tanda_renombrar`. El error `EMPRESA_MEZCLA: …` lo muestra el pop-up (igual que CUARENTENA, vía `aprMsgErr`) |
| centinela | `gv_ppp_tanda_empresa_mezclada` — tandas web que ya mezclan empresas |

⚠ **El armador NO se toca**: nunca produce la mezcla, así que el guard jamás le salta. La fusión
automática (`gv_ppp_web_fusionar_tandas`) corre por `p_empresa` y queda igual.

⚠ **F21C se deja como está** (Luis, 01/10: *"dejala, no la toques"*): ya pickeada y en armado. El
centinela la lista a propósito, para que quede a la vista.

**Chequeo:** `select * from public.gv_ppp_tanda_empresa_mezclada;` (al 01/10 sólo F21C) ·
`select * from public.gv_reglas_perdidas;` (vacía = los 4 guards puestos).
`sql/gv_tanda_empresa_guard_v2574.sql`. Problema 664.

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

⚠⚠ **Y TAMPOCO vuelve si esa tanda es de OTRO CAMIÓN** (v20.94, problema 489). La v20.56 tapó
el ESTADO de la tanda y dejó abierta la ZONA: **LK 1448** (Silvano, Zona 6 - **GBA Norte**) tenía
como tanda previa **D69H** (Zona 2 - CABA Centro, camión **Capital**), y el chip decía *"esa tanda
sale el 23/09 y no se empezó: vuelve ahí"*. Seguir ese consejo parte la tanda en dos camiones y
pone `gv_ppp_tanda_camion_mezclado` en rojo (regla v18.87). Hoy el estado es **`otro camion`** y
el chip nombra los dos: *"esa tanda va en el camión Capital y este pedido en el de GBA Norte"*.

⚠ **Una tanda ya MEZCLADA también sale `otro camion`** (`camion_tanda` queda `Capital + GBA Norte`
y nunca coincide): no se le suma nada a una tanda que ya está mal. Y el corte es la **etiqueta** de
`gv_ppp_web_camion`, no el número de zona — una tanda de CABA mezcla Zona 1+2 a propósito.

⚠ La firma es **`gv_ppp_web_camion(text, text)`**, no `(text, date)`.
`sql/gv_retenido_camion_v2092.sql`, `tests/apr-retenido-camion.cjs`, §3.md.

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

## ⚠ REGLA (Thomas, 2026-09-26, v22.98): lo DIFERIDO se parte POR FECHA de reingreso, y la NP adelantada se reprograma sola

**Thomas:** *"si son pedidos únicamente de importados que llegan en noviembre, reprogramarlo de manera automática. Si
tienen parte de una cosa y parte de la otra, dejarlos ahí y particionar los pedidos en dos."*

| pieza | dónde |
|---|---|
| una NP diferida **por fecha** de reingreso (la congelada en `pedido_diferido`) | LK: `v_pedidos_web_np` y `gv_pedidos_web_np_chef` |
| NP diferida programada ANTES de su reingreso → se desprograma y (b2) la reprograma en la misma corrida | Gestión: `gv_ppp_web_diferido_tarde`, llamada por el armador antes de (a000) |

- Compara contra el reingreso **crudo** (sin los +7): lo que llega el mismo día que sale la tanda se deja ahí.
- **Tanda empezada no se toca**: queda en `gv_ppp_diferido_antes_de_tiempo` (vacía = todo bien) y decide Marianela.
- ⚠ **`PPP_Web_Base` no borra artículos que salen de una NP** (el Edge Function hace upsert): si el corte de una NP ya
  programada cambia, limpiar a mano la foto de picking o el artículo queda en las dos NP (pasó en E37A: 954E y 956E
  pickeados de más). `sql/gv_diferido_por_fecha_v2298.sql`.

## ⚠ REGLA (Luis, 2026-10-13, v30.02): el UMBRAL DEL INTRADÍA no frena lo que tiene DÍA FORZADO

**Luis:** *"lk 1670, por que no se programo solo?"*. Era un **Retira con día pactado** (16/10) que
entró 13:31 y seguía sin tanda.

> El intradía (cron 73, cada 5 min) llama al armador **sólo** si lo pendiente de las **zonas
> automáticas** (1, 2 y 3) llega al umbral, o si hay algo de zona manual con camión a su zona.
> **Retira, Súper y el resto no suman ahí** (`pendienteAutomatico` de la Edge Function lo dice
> textual, y el conteo manual exige zona `^Zona N`), así que un pendiente que un pase programa
> **sí o sí hoy** no llegaba NUNCA al armador: la corrida salía por `intradia_sin_umbral` sin
> llamarlo y el pedido esperaba el job de las 00:01 — hasta **11 h** parado.

Mismo agujero que la regla v19.52 ya marca para `'^\s*Zona\s*[0-9]+'`: **al tocar el armado,
preguntarse si ahí no falta Retira.**

| pieza | qué hace |
|---|---|
| **`gv_ppp_web_forzado_sin_tanda()`** | los pedidos SIN TANDA que un pase programa hoy sí o sí: **(a4)** Retira con día elegido (`gv_web_retiro_pactado`) · **(b2)** diferido con su piso cumplido · **(a0e)** cliente nuevo aprobado. Lee `lk_pedidos_match` (el FDW ya está en la base): no necesita el feed |
| cron **156 `gv-ppp-web-forzado`** | minutos 7,17,37,47, anti-solape: si esa función devuelve algo, llama a la Edge Function en modo **diario** (el de las 00:01, que no mira el umbral) y el armador corre. Si no, no hace nada |

- **No hizo falta redeploy** de `gv-ppp-web-tandas-diarias`. Queda además
  **`gv_ppp_web_pendiente_forzado(text,jsonb)`** —el mismo criterio recibiendo los pendientes por
  jsonb— **sin llamador**: es la mitad del fix para el día que esa función se re-deploye y el
  umbral se arregle adentro (sumar su conteo a `npManual`).
- Sobrar una fila no cuesta nada (decide el armador); faltar una deja el pedido sin programar.
- Probado: con LK 1670 pendiente la función devolvía 1 fila y la corrida lo programó como
  **LK 0414, tanda F89A, Retira, 16/10**.
- Los objetos y el centinela de la base dicen **v29.82** (la versión con que se aplicaron): es la
  llave, no cambiarla. `sql/gv_ppp_web_forzado_sin_tanda_v3002.sql` (rollback en la cabecera).

**Chequeo:** `select * from public.gv_ppp_web_forzado_sin_tanda();` — lo que el armador tiene que
tomar sí o sí · `select * from public.gv_reglas_perdidas;`.

## ⚠ REGLA (Luis, 2026-09-30, v24.76): en lo que sale por EXPRESO se ve la DIRECCIÓN REAL — y la sucursal del Excel ISIS sale del PEDIDO

**Luis:** *"que diga para los que se despachan en expreso la dirección de entrega real también en A
programar y en Programación"*.

> En la ficha de la página, **`direccion_entrega` es el GALPÓN del expreso** (Pergamino 2820, Juan B.
> Justo 7594); la **sucursal real** del cliente es la **ETIQUETA** (`label`: "Chacabuco 228- Mendoza",
> "Río Gall (25 de mayo)") + localidad y provincia. La zona de la PPP es la del galpón.

- **Programación**: chip azul **📍** (`.pga-dreal`) con `gvDirRealTxt(sucursal, localidad, provincia)`.
  Lo trae `gv_np_destino_lista`, que desde la v24.76 devuelve además `localidad_destino`, `sucursal` y
  `es_expreso` (no se tocó `gv_np_destino`, que tiene centinela). Para una NP de ISIS la sucursal sale
  del slot del padrón con esa localidad **sólo si es UNO**: dos sucursales en la misma ciudad (Multibazar
  en Bariloche) no se adivinan.
- **A Programar**: chip **📍** (`aprDirRealChip`) desde el feed (`direccion` = etiqueta, `localidad`).
- **Es expreso** si trae galpón o nombre de expreso, o la NP dice `Exp.`, o la provincia no es CABA ni
  Buenos Aires. Retira nunca.
- ⚠ **El Excel ISIS buscaba la sucursal por cliente + fecha ±3 + ítems**, y con un código que estaba en
  varios pedidos del mismo cliente elegía el primero: **LK 0179** (sólo 607E, Río Gallegos) salió
  **«Brc Onelli»** (Bariloche) el 29/09. Hoy va primero por el **order_id** exacto de la NP web, y si la
  heurística empata con sucursales distintas **deja la celda vacía**. Medido sobre 60 días de Excel: 142
  NP web, 1 con sucursal equivocada y 6 sin sucursal.
- ⚠⚠ **v24.78 (Luis: *"no sé por qué inventa datos si el dato de la sucursal viaja con el pedido"*):
  una NP WEB NUNCA pasa por la heurística.** Orden: la fila exacta de `lk_pedidos_match` (por
  `order_id`) → la etiqueta que viajó con la NP (`PPP_Web_Programacion.direccion`, entre paréntesis)
  → vacío. La heurística queda sólo para NP de ISIS, que no traen pedido. Problema 633.
- `sql/gv_np_destino_dir_real_v2476.sql`, `tests/ppp-dir-real-expreso.cjs`, y el chip 📍 de las dos
  pantallas lo prueba corriéndolas `tests/ppp-misiones.cjs`.

## ⚠ REGLA (Luis, 2026-09-23, v21.63): CLIENTES DE PRUEBA — van a la PPP, el operario no los ve

**Luis:** *"que sus pedidos solo se puedan programar como tanda única (código PruebaX) · si se
programa automáticamente, con las reglas que ya hay · que no se considere cliente nuevo · que NO le
figuren a los operarios (no son pedidos reales, no quiero que rompan la operación)"*.

Primer cliente: **LK 99862 «Luiggy y Luiggy (PRUEBA)»**, copia de Muller y Muller (LK 862) en la
página LK — usuario `prueba123`. La lista vive en **`GV_Clientes_Prueba`** (agregar otro = un `insert`).

| qué | cómo |
|---|---|
| tanda única | `GV_Clientes_Reglas` regla `solo` (ya existía) |
| código `PRUEBAn` | `gv_prueba_tandas_normalizar()`, cron `gv-prueba-tandas` c/5 min, renombra con `gv_ppp_tanda_renombrar`. En MAYÚSCULAS: todo compara con `upper(btrim())` |
| no es cliente nuevo | copia de la excepción de Muller en `gv_excepcion_cuarentena` |
| oculto al operario | front: `gvSinPrueba` (listas de picking/armado, picking, armado, faltantes, monitor), `gvEsTandaPrueba` (Carga Camión, Control Remitos, Recepción Remitos), `monitor/tv.html`, y el **Excel ISIS los saca** |
| eliminar | botón **🗑 Eliminar** en la fila de una tanda PRUEBA = «Cancelar pedido» (`gv_ppp_pedido_cancelar`, todo el pedido) |
| cupo y camión | cuentan como cualquier pedido (*"con las reglas que ya hay"*) |

⚠ **El filtro del front NO toca el mapa cacheado** (`_pppCache`): el supervisor sigue viendo las
tandas PRUEBA en la PPP. **Centinela:** `select * from public.gv_prueba_mezclada;` — vacía = ningún
pedido de prueba quedó adentro de una tanda con pedidos reales (esa no se renombra).
`sql/gv_clientes_prueba_v2163.sql`, `tests/prueba-oculta-operario.cjs`.

## ⚠ REGLA (Marianela, 2026-09-23, v21.76): una tanda EMPEZADA no cambia de CÓDIGO al moverla de día

**Marianela:** *"cuando tengamos una tanda en proceso de picking o armado y la cambio para otro día
… no deje cambiar el nombre porque los operarios trabajan por nombre de tanda, luego no la encuentran"*.

El paso 2 de «📅 Cambiar de día» sólo ofrecía **➕ Tanda nueva** o **meterla en otra**: las dos le
cambiaban el código. Ahora hay **🔒 Mismo código** (`p_tanda_destino = null`, modo `mantiene`) y,
si la tanda tiene eventos de operario reales (legajo ≠ 0/1), `gv_ppp_tanda_mover` frena cualquier
cambio de código con **`TANDA_CANDADO`**. Juntar OTRA tanda adentro de la empezada sigue valiendo:
la empezada no cambia de nombre.

**Chequeo:** `select * from public.gv_reglas_perdidas;` · `node tests/ppp-tanda-candado-codigo.cjs`.
`sql/gv_tanda_candado_codigo_v2176.sql`.

## ⚠ REGLA (Thomas, 2026-09-23, v21.56): UN CAMIÓN = UN GRUPO DE ZONAS — Capital son DOS camiones

**Thomas, textual:** *"no podés programar para un solo día zona 1, zona 2, zona 3, zona 6, zona 7. Es un
desastre"* · *"No puedo ir tantas veces a zona 3 y 4 y 5 y 6"*.

| camión | zonas | sectores |
|---|---|---|
| **Capital Sur** | Z1 | A, B |
| **Capital Centro** | Z2 | (la zona manda, no el sector) |
| **Capital Oeste** | Z3 | (la zona manda, no el sector) |
| GBA Sur | Z4 | J, K, L |
| GBA Oeste | Z5 | M |
| GBA Norte | Z6 + Z7 | N, P |
| súper | cada uno el suyo | — |

⚠⚠⚠ **REGLA VIGENTE (Luis, 23/09, v21.95) — se retiran la v21.91 y la v21.94 como "camiones distintos siempre":**
- **Z2 y Z3 van en el MISMO camión si cada una suma < 1 m³ ese día** (web + ISIS; Retira no cuenta). Apenas una
  llega a 1 m³, esa va sola. Sirve para compensar zonas de poco volumen.
- **Z6 y Z7 van SIEMPRE juntas** (un camión, GBA Norte). Z7 sale sola sólo si en su plazo no hay día con Z6.
- **Prioridad: máxima entrega con la menor cantidad de camiones.**
- **Las TANDAS no se tocan** (Luis: *"no rompas la lógica de tandas"*): `gv_ppp_web_camion` sigue dando una
  etiqueta por zona (Capital Centro / Capital Oeste / GBA Norte / GBA Norte Lejos) y una tanda no mezcla esas
  zonas. La unión es del CAMIÓN: la aplican `gv_ppp_web_dia_grupo` (el armado, al elegir el día) y el Resumen de
  la PPP (al contar camiones). Si una zona pasa de 1 m³ después, cambia la cuenta y ningún pallet se toca.
  `sql/gv_programacion_camion_z2z3_z6z7_v2195.sql`.

Hasta la v21.57 `gv_ppp_web_camion` devolvía **"Capital" para Z1, Z2 y Z3**, así que un día con Z1+Z2+Z3
contaba como un solo camión y nada lo marcaba. Máximo **2 camiones por día**, cada uno a **un** grupo, y
**cada grupo sale una sola vez** mientras entre en un camión (Z4 4,03 m³ → una salida, no cuatro).

⚠ **El súper NO se junta en un día** (*"Matiz es súper, no se juntan"*): `gv_ppp_cliente_dos_dias` no lo marca.

⚠ **Norma de salida (Thomas, 23/09):** *"hoy tiene que facturarse para mañana lo que se armó ayer. Y nada
más que eso"* — armado día 1, factura día 2, sale día 3. Vale también para el súper en el armado.

El 22/09 21:54 una reprogramación a mano niveló los días a 4,30 m³ sin mirar el camión y dejó GBA Sur en
4 salidas, Oeste en 3 y Norte en 3. Se rehizo el 23/09 (25 tandas).

**Chequeo:** `select * from public.gv_ppp_tanda_camion_mezclado;` · `select * from public.gv_reglas_perdidas;`
`sql/gv_camion_un_grupo_zonas_v2156.sql`.

### ⚠⚠ Y NO HAY TOPE DE m³ POR CAMIÓN (v21.75, 23/09): `camion_m3_tope` NO es la capacidad

**Textual:** *"no hay límite para arriba en la cantidad de metros cúbicos por camión. Puedo tener
hasta 40 metros cúbicos en un camión."*

> **`PPP_Web_Config.camion_m3_tope` = 6 es lo que el armador MEZCLA en una TANDA, no lo que entra
> en el camión.** Lo lee `gv_ppp_web_agrupar_geo` / `gv_ancla_simular`, y ahí está bien. Usarlo
> como capacidad del camión es lo que partía un pedido en tres.

**Lo que costó, medido:** el Resumen de la PPP contaba `ceil(m³ / 6)` por ruta, así que el
**28/10** —**12,33 m³ de Matiz sola**, un cliente, una entrega— decía **3 camiones**. Y contaba con
las **dos rutas viejas** (Z1+Z2+Z3+Z4 = un camión), o sea que un día con Z2+Z3+Z4+Z6 decía **2**
cuando salen **3** y el exceso sobre el tope de 2 camiones por día no se veía en la única pantalla
que mira el conjunto.

Hoy el Resumen cuenta **un camión por grupo de zonas** (la tabla de arriba) + **uno por cliente
súper** + **Retira sin camión**, y un grupo **no se parte** hasta los **40 m³** que entran
físicamente, que viven en **`PPP_Web_Config.jornada_camion_m3_cap`** — entra por el fetch
`clave=like.jornada*` que el front ya hacía, y sin la fila usa 40 de default.

⚠ **El armado NO se tocó**: sigue con `camion_m3_tope` y sus reglas. Esto es la cuenta que
**muestra** el Resumen.

⚠ **Y la DEMORA de esa tabla es la MAYOR del día, no el promedio** (mismo pedido): *"en lugar de
figurar los días de demora promedio, el día de mayor demora… y que pueda tocar y ver por camión,
ordenado por mayor demora, la demora real de cada uno"*. El promedio de un día con un pedido de 35
días y otro de 76 daba **55,5**, un número que no le pasa a ninguno de los dos y que escondía al que
estaba parado hace 76. La celda abre el pop-up de camiones ordenado por demora; a partir de **14
días corridos** (los 10 hábiles del punto 4 de la lógica de programación) va en rojo.

**Chequeo:** `node tests/ppp-res-demora-camion.cjs` — corre la pantalla y clickea la celda.
Verificado que falla contra el código anterior con los números del reclamo (3 camiones, 55,5 días).
`sql/gv_resumen_camion_m3_v2175.sql` (la fila de config, **pendiente del sí del dueño**).

## ⚠ REGLA (Luis, 2026-09-22, v21.39): las tandas son de 0,80 m³ — y el armado las FUSIONA

**Luis, textual:** *"¿Por qué las tandas son tan chicas? Tienen que ser de 0,8 en promedio.
Mínimo 0,6, máximo 1. Salvo pedidos más grandes. ¿No tenés esa lógica?"* Y sobre la fusión:
*"tiene que ser 0,80"*.

**Media lógica estaba, media no.** `tanda_m3_max_mezcla` (1,00) sí se usa: es el techo hasta el
que una tanda abierta sigue recibiendo clientes. **`tanda_m3_min` (0,60) NO lo lee ninguna
función** —medido: 0 apariciones en `pg_proc`—; es sólo un cartel del front de A Programar.

**Medido el 22/09** (tandas de los últimos 7 días + futuras), separando lo que no es camión:

| clase | tandas | promedio | < 0,6 | de 1 solo cliente |
|---|---:|---:|---:|---:|
| **Reparto** | 62 | **0,631 m³** | 35 | 41 |
| Retira | 17 | 0,301 | 15 | 17 |
| Súper | 7 | 3,070 | 1 | 7 |

Retira no usa camión (cada uno viene a buscar el suyo) y el súper va solo por regla. El número
que importa es el de reparto.

### La causa: la tanda nace con lo que hay en ese momento y nadie la vuelve a juntar

`ppp_web_armar_tandas` acumula clientes **nuevos** en una tanda abierta del mismo día y camión
(`_open`, v13.67), pero **nunca fusiona dos tandas que ya existen**. Caso testigo, 28/09 GBA
Oeste: **5 tandas para 0,846 m³**, tres del mismo sector M (Ciudadela) — E46A nació el 08/09,
E46B/E46C el 16/09, E49A el 14/09, E50A el 08/09, cada una para OTRO día. Cuando se
reprogramaron todas al 28/09 quedaron 5 tandas en el mismo camión y ninguna regla las miró.

### El pase de fusión: `gv_ppp_web_fusionar_tandas(empresa, desde, simular, por)`

Corre **al final de cada corrida del armador** (pase (e) de `gv_ppp_web_armar_pendientes`) y
junta, por (fecha, camión), las tandas que se pueden juntar, de la más grande a la más chica,
hasta el **objetivo `tanda_m3_fusion` = 0,80** sin pasar nunca el **máximo
`tanda_m3_max_mezcla` = 1,00**. Sólo absorbe una tanda cuyas paradas sean **todas** compatibles
con las de la que recibe (`gv_ppp_web_compat`: mismo camión, sectores vecinos o pares del
dueño). La fusión la hace `gv_ppp_tanda_renombrar`, que ya sabe mover programación, eventos y
stock (v19.69 / v20.88).

**Lo que NO toca, a propósito:** tandas con cualquier evento de operario (PK/PKC/EP/TP/TAP/AP/
CC/CCN, legajo real) o con stock movido —un pallet con papel no se renombra solo, regla
v20.88—, súper, retira, cliente `solo`, tanda de dos camiones, tanda en dos días (problema 338)
y día sin reparto.

⚠ **El interruptor es `PPP_Web_Config.tanda_fusion_activa`** (0 = apagado). Prenderlo es un
`update`, no un deploy. **Prendido el 22/09 con el sí de Luis** (*"prendé la fusión"*): la
primera corrida real hizo E70A→E64A, E18A→E48C y E46C→E49A.

### ⚠ Al reprogramar a mano, el CLIENTE se junta por `cliente_key`, no por `(empresa, cod)`

El 22/09 se reprogramaron 21 tandas a mano para dejar cada día en el cupo (4,30 m³). El plan
agrupó los pedidos de un mismo cliente por **código dentro de cada empresa**, y **Clapera Alicia
Raquel** es **2447 en Chef y 2394 en LK** —misma persona, misma dirección (Rabanal 2866, expreso
a Rosario)—: E65A (LK) fue al 05/10 y E26C/E53B (Chef) quedaron el 30/09. Lo cazó
`gv_ppp_cliente_dos_dias` (5 filas). La regla de Thomas (*"nunca +1 pedido de un cliente va
separado en la PPP"*) cruza empresas: **la clave del cliente para el día es `cliente_key`**, la
misma que usa ese centinela. Y se mira **antes y después** de cualquier movida de tandas.

**Probado corriendo el armador**, no leyéndolo (regla v19.56): en transacción abortada, con el
interruptor en 1, `gv_ppp_web_armar_pendientes('lk', …)` entró al pase y fusionó E70A→E64A,
E18A→E48C y E46C→E49A: **51 → 48 tandas**, los tres códigos viejos sin una sola fila. Y lo que
**no** fusionó lo explica la cercanía, no un bug: E37C (San Cristóbal, A) con E29G (Villa Luro,
C) no son vecinos; E48A (Pompeya, B) no es vecino de H ni F; E61A + E61E = 1,031 > 1,00.

`p_simular = true` (default) no escribe: devuelve lo que HARÍA. Es la forma de mirarlo:

```sql
select * from public.gv_ppp_web_fusionar_tandas('lk');    -- qué juntaría hoy, sin tocar nada
select * from public.gv_reglas_perdidas;                   -- vacía = el pase sigue en el armador
```

`sql/gv_ppp_web_fusionar_tandas_v2139.sql`.

## ⚠ REGLA (Luis, 2026-09-23, v21.41): el día «⏸ Armados en espera» NO EXISTE MÁS

**Luis, con la captura de la Programación:** *"No tiene que existir «Armados en espera»"*.

Historia corta, para no volver a ponerlo: nació en la v19.29 (pedido de Luis: un «día» sin fecha
para tandas armadas a propósito), en la v19.32 pasó a estar **siempre** en la tabla aunque vacío,
en la v21.40 el botón del pop-up pasó a ser un casillero de la grilla, y en la v21.41 Luis lo sacó
entero: **ni la fila en la tabla de Programación ni el destino en «📅 Cambiar de día»**.

- Lo que se sacó son las **puertas**: la fila vacía (`_pgaConEspera` sigue en el archivo sin
  llamador) y el destino del pop-up (`pppTandaEspera` / `pppMovEsperaElegir` siguen sin puerta,
  como `gv_ppp_np_desarmar` en la v18.77). La RPC `gv_ppp_tanda_espera` y la tabla
  `GV_PPP_Armados_Espera` no se tocaron.
- **Lo parado viejo no se esconde.** Si el backend devuelve una tanda con la fecha centinela
  (`9999-12-31`), la tabla la sigue mostrando con su nombre, no como fecha; y el badge
  `armado_espera` de `gv_ppp_avisos` (Thomas, v20.86) sigue vigilando la tabla. Al 23/09 había
  **0** tandas ahí, así que nada quedó a oscuras.

**Chequeo:** `node tests/ppp-armados-espera.cjs` — es el candado invertido: se pone en rojo si
vuelve la fila vacía o el destino del pop-up, y si una tanda parada dejara de verse.

## ⚠ REGLA (Luis, 2026-09-29, v23.93): «📲 Avisar programación» toma TAMBIÉN los pedidos web

**Luis:** *"Que avisar programacion tome pedidos web que actualmente esta roto"*. Medido antes:
`vista_ppp_programacion_pendiente` devolvía **15 filas y 0 web** — leía sólo `gv_ppp_prog_rs`, el
espejo de ISIS, cuando desde la v13.47 casi todo lo programado vive en `PPP_Web_Programacion`.
Hoy es un `UNION ALL` con la rama web: **141 filas, 126 con prefijo, 0 NP duplicadas**, y
`vista_avisar_programacion` no se tocó (ya resuelve empresa, teléfono y vendedor por empresa).

⚠ La NP web se etiqueta con **`gv_ppp_web_np_label(empresa, np, np_idx)`**, nunca con `np` pelado:
el código de cliente es por empresa y sin prefijo el `4181` de LK y el de Chef son dos personas.
⚠ Se saltean las canceladas y las facturadas con cierre. ⚠ `security_invoker = true` se repone con
el `alter view`. `sql/gv_avisar_programacion_web_v2393.sql`, §3.v2393.

**Y el panel supervisor perdió dos puertas** (*"Saca Pedidos sin cargar en ppp y faltantes
facturados sin completar"*): `stkOpenNpFaltan` y `stkOpenFaltFact` **siguen en el archivo**, lo que
no vuelve es el botón. **«Completar datos producto» se mudó a ⚙️ Configuración** con su `#dpBadge`
(si el id no viaja con el botón, `dpLoadBadge()` escribe en la nada). `tests/sup-panel-v2393.cjs`.

## ⚠ REGLA (Luis, 2026-09-30): el pedido con importados sin stock va COMPLETO — ya no se parte

**Luis:** *"que deje de partir el pedido… programá el pedido completo (como antes del cambio)"*.
Se retira la regla del 11/09 (Thomas: `pedido_diferido` corta la NP) y la del 23/09 (Luis: la
página crea 2 pedidos). Lo que no hay sale como faltante.

| capa | qué cambió |
|---|---|
| páginas LK y Chef (`script.js`) | `PARTIR_POR_REINGRESO = false`: un solo pedido y la confirmación dice "listo antes del" |
| base LK | `marcar_pedido_diferido` / `marcar_diferidos_chef_ids` ya no escriben `pedido_diferido`: anotan en **`pedido_sin_stock`** (empresa, pedido, artículo, cliente, cajas, unidades, fecha, reingreso estimado) — también el cliente nuevo |
| Gestión | nada: los pases de diferido quedan sin trabajo nuevo |

⚠ Lo ya diferido antes del cambio (16 pedidos) sigue partido: borrar esas filas cambiaría el corte
de NP ya programadas. `sql/pedido_sin_partir_y_demanda_sin_stock_20260930.sql` (en `pagina-LK-copia`).

## ⚠ REGLA (Luis, 2026-10-05, v27.02): el RESUMEN de la PPP dice el orden del armado y CÓMO llegó cada NP a su día

- Arriba de la tabla, desplegable **Orden de prioridad del armado automático** (`PPP_ARMADO_ORDEN_HTML`): si cambia una
  regla del armado, se cambia ese texto en el mismo pedido. ⚠ **v27.11 (Luis): la lista va en GRILLA compacta
  (`.pauta-ol` con `column-width`), sin emoji por línea, y el `<details>` lleva `ontoggle="pppFitProgramar()"`**: en
  Resumen `pppFitPantalla` deja `overflow:hidden` por el zoom-a-pantalla, así que al abrir el desplegable sin ese
  re-fit la tabla quedaba comprimida y cortada SIN poder scrollear. Ahora, con el desplegable abierto, Resumen se ve a
  tamaño normal y scrollea (igual que el acordeón de Programación).
- Tocar una celda (zona, total, camiones o demora) → columna **«Cómo llegó a este día»**: 🤖 Automático + regla · ✋ A mano
  (quién y cuándo) · ISIS. Fuente **`gv_ppp_np_origen()`** (lectura, anon). ⚠ El armador NO guarda la regla por NP: la
  automática se DEDUCE (retira con día, súper, importado diferido, cron/optimizador de las 18:00 por su log, si no grupo de
  zonas). Lo duro es lo manual (`gv_manual_por` / `creado_por`) y el log del cron. Sin RPC dice «—».
- `sql/gv_ppp_np_origen_v2701.sql`, `tests/ppp-res-origen.cjs`.

## ⚠ REGLA (Luis, 2026-10-05, v27.07): cada NP dice con qué PAUTA (P1..P24) se programó — botón P# en el Resumen

- Catálogo **`GV_PPP_Pautas`** (P1..P24 + P14a-d, el orden del código del armado). El armador pone
  `set_config('gv.pauta', …)` antes de cada pase (marcador `v27.05-pauta`) y el trigger
  **`gv_ppp_np_pauta_registrar`** de `PPP_Web_Programacion` anota en **`GV_PPP_NP_Pauta`** cuando la NP toma tanda o
  cambia de día. En el pase (g), **`gv_ppp_pauta_grupo_clasificar`** dice la rama (P14a/b/c/d) leyendo `_gdg_oc` que
  `gv_ppp_web_dia_grupo` acaba de armar (misma cuenta, no se duplica) y por qué no siguió la siguiente.
- Lectura **`gv_ppp_np_pauta_lista()`** (anon): manual P24 > cron 18:00 P22/P23 > registrada > **deducida** (lo
  programado antes del 05/10: la rama exacta no quedó anotada).
- Front: botoncito **P#** en «Cómo llegó a este día» del Resumen → pop-up (por qué frenó · lo evaluado antes · por qué
  no siguió · la tanda). Al agregar o reordenar un pase del armador, sumar su `set_config` y su fila al catálogo.
- `sql/gv_ppp_np_pauta_v2705.sql`, centinela 336, `tests/ppp-res-origen.cjs`.

## ⚠ REGLA (Luis, 2026-10-07, v28.34): en la PPP un día se escribe «Mié 07/10»

Una sola función, **`gvDiaTxt(x)`** (ISO, AAAAMMDD, dd/mm/aaaa o Date → `Mié 07/10`; `GV_DOW3`). La usan Programación,
Resumen (día y fecha en UNA columna), A Programar (lista, chips, avisos, columna de días), Cambiar de día, Entregados,
Cuarentena (entrega y 📥 pedido), el planificador (tarjetas, cabecera y rango de hojas, v28.37) y Ocupación. **En el celular la Programación sigue la regla v20.01 de Thomas**
(sólo «7/10»: el día y los ceros van en `.pga-sem` / `.pga-m0`, que el CSS esconde). Al agregar una fecha a la PPP, va por `gvDiaTxt`.

## ⚠ REGLA (Luis, 2026-10-07, v28.34, D6): AVISO «MISMO CLIENTE, MISMO LUGAR, DÍAS DISTINTOS» en Programación y Resumen

No revive la regla derogada «mismo cliente, mismo día» (v21.87): la clave es **(empresa, cod, dirección)**
(`gv_dir_key`), no el cliente — un cliente con sucursales en dos zonas son dos viajes y no avisa.
Vista **`gv_ppp_mismo_lugar_dos_dias`** (web + ISIS, de hoy en adelante; sin súper, retira/expo ni lo
salido por CCN/CRN; `security_invoker`, centinela 356). Front: cartel naranja arriba de Programación y del
Resumen (`_pppMismoLugarNota`) y chip **📍 mismo lugar otro día** en la NP (`_pppMismoLugarChip`). Es AVISO:
no mueve nada. Lectura rota → lo dice. Al 07/10: 0 casos (Matiz es súper). `sql/gv_ppp_mismo_lugar_dos_dias_v2834.sql`,
`tests/ppp-mismo-lugar.cjs`.

## ⚠ REGLA (Luis, 2026-10-07, v28.38, D9): LA ZONA DE UN RETIRA ES SIEMPRE «Retira»

*"No le mandamos un Retira a una dirección a un cliente sino que lo vienen a buscar"*. Trigger
**`gv_ppp_web_zona_retira`** (BEFORE INSERT/UPDATE en `PPP_Web_Programacion`): si el pedido dice Retira
(`gv_es_retira_fila`: dirección/barrio exacto «Retira», Virgilio 2788, «Exp. Retira») la zona queda `Retira`,
aunque el feed traiga la de otra dirección de la ficha (la fila «Retira» de la ficha no tiene zona). Caso: pedido
1448 (Silvano) con zona «Zona 6» en E92A, que salió el 25/09 como «Retira cliente». **D8 (Luis): LK 0252 (970E +
971E, importados que llegaron después) queda en E92A, que es su tanda de Retira** — no se le arma tanda nueva.
Centinela 359. `sql/gv_ppp_web_zona_retira_v2838.sql`.

## ⚠ REGLA (Luis, 2026-10-07, v28.40, D10): cambia la DIRECCIÓN de una NP programada → la ZONA se RECALCULA — y tanda fuera de regla = CARTEL

- Trigger **`gv_ppp_web_zona_recalc`** (BEFORE UPDATE OF direccion, barrio en `PPP_Web_Programacion`): si la NP
  tiene tanda y su dirección cambia, la zona se recalcula con `gv_ppp_web_zona(barrio, null, direccion)` (la misma
  cuenta del armado). **Tanda sin empezar** (sin EP/TP/AP/TAP): se aplica. **Empezada**: la zona NO se toca. Todo queda
  en **`GV_PPP_Zona_Recalc`**. Corre antes que `gv_ppp_web_zona_retira` (el Retira pisa después).
- **No mueve la NP de tanda**: si la zona nueva va en otro camión, la tanda queda mezclada y lo dice el cartel.
- **Cartel** en Programación y Resumen (`_pppZonaFueraNota`): vista **`gv_ppp_tanda_zona_fuera_regla`** = tanda (web,
  sin salir) con pedidos de camiones distintos según `gv_ppp_web_camion` (Retira y sin zona cuentan como camión
  propio) + NP de tanda empezada cuya dirección cambió de zona. Es AVISO. Al 07/10: 0 filas.
- ⚠ Medido: `gv_zona_de_barrio('Balvanera')` da **Zona 1** (8 NP de F18B/E97A están en Zona 2 movidas a mano). Si
  cambia su dirección, pasan a Zona 1 y salen en el cartel.
- `sql/gv_ppp_web_zona_recalc_v2840.sql`, `tests/ppp-zona-fuera-regla.cjs`, centinelas v28.40.

## ⚠ REGLA (Luis, 2026-10-08, v28.60): «Corregir códigos de NPs» NO EXISTE MÁS — la corrección es automática

- Sale el botón del panel y el chip «🔀 Corregir códigos» de Facturación (`openCorreccPanel`, `facCorreccOpen`,
  `corrLoadBadge` quedan en el archivo sin puerta). Luis: *"manual no iría más"*.
- `gv_web_np_sec_auto` (cron 119) sigue cambiando el secundario sin stock por el principal en la NP web. Lo que no puede
  cambiar (tanda empezada, cajas que no dan enteras en el principal, familia de otra empresa, sin UxB) **sale como
  faltante**: una NP web se factura desde lo armado, no hay nada que cambiar a mano en ISIS.
- Preparado y SIN usar: `GV_NP_Cambio_Codigo.cajas_resto` + el trigger `gv_ppp_web_base_np_cambio` respetan un resto
  para convertir la parte entera de un pedido impar (631 de a 12 → 631E de a 24). Falta que la Edge Function
  `gv-ppp-web-tandas-diarias` convierta `(cajas − cajas_resto)`; hasta entonces la función nunca deja resto.
- ⚠ Al tocar ese trigger: `select true, max(...)` sin filas devuelve UNA fila y descartaba TODA alta de `PPP_Web_Base`
  (pasó ~2 min el 08/10). Va con `count(*)`. `sql/gv_np_secundario_auto_resto_v2859.sql`, `tests/corr-reparto-sec.cjs`.

## ⚠ REGLA (Luis, 2026-10-08, v28.77): «NPs por Día» y Programación — el NÚMERO grande, el % chiquito, y Facturado = «con FC ISIS / exportadas»

- En la Programación de la PPP (`_pgaPctTd`) y en la TV / Mon. Admin («NPs por Día»), cada celda de estado muestra
  la **cantidad de NP grande** y el **% chico** (en la PPP al lado, en la TV abajo).
- **Facturado = `x/y`**: `y` = NP exportadas al Excel del Facturador (filas de `Facturacion_NP`, neteadas por Salió,
  el número de siempre); `x` = de ésas, cuántas ya tienen la factura de ISIS parseada y asignada
  (`GV_Cruce_FC_Asig.doc_id`, cron 90). Lo lee `gv_np_fc_parseada(text[])` (anon, sólo lectura). Si esa lectura
  falla, la celda muestra sólo `y` (no un 0/…).
- `sql/gv_np_fc_parseada_v2877.sql`, `tests/fc-parseada-x-de-y.cjs`.

## 🗄 RETIRADO — sólo revisar si se pregunta por algo ANTIGUO que no está arriba

> Reglas, versiones y hallazgos que **ya no valen**. Se guardan como historia, no como instrucción.
> **No leer esta sección en el trabajo normal**: sólo cuando alguien pregunta por un comportamiento viejo
> y no aparece en las reglas vigentes de arriba. Nada de acá se vuelve a aplicar sin un pedido explícito.

**Cómo convive con las otras dos reglas de cliente, que siguen valiendo:**

| regla | qué dice | por qué no choca |
|---|---|---|
| ~~Thomas: *"nunca +1 pedido de un cliente va separado en la PPP"*~~ | **DEROGADA (Luis, 23/09, v21.87)** | ver "UN GRUPO DE ZONAS POR DÍA" |
| Luis v18.87: *"la tanda de un cliente se parte por CAMIÓN"* | mismo día, distinta tanda si la zona manda a otro camión | es esta misma regla aplicada al armado |

O sea: **mismo día para el cliente · tanda por camión · agrupamiento por pedido.**

⚠ **Y la alarma de "cliente en días distintos" (`gv_ppp_cliente_dos_dias`) salta SÓLO si esos pedidos
podrían ir en el MISMO camión** (Luis, 23/09, v21.70). Caso Multi Bazar (LK 4042): 4 pedidos a Río
Negro y Santa Cruz por expreso y a San Martín por reparto propio, en 3 camiones distintos — juntarlos
en un día no ahorra un viaje y el 2/10 ya salían los 2 camiones de Capital. El corte es la etiqueta de
`gv_ppp_web_camion` (Capital Sur / Capital Centro-Oeste / GBA Sur / GBA Oeste / GBA Norte). Las tres dicen lo
mismo desde tres lados, y el principio rector es el que las ordena cuando parecen chocar.

⚠⚠ **Z2 y Z3 son camiones DISTINTOS (Luis, 23/09, v21.91)** — *"¿cuál sería la lógica de tener
separadas las zonas Z2 y Z3 si son lo mismo?"*. Se retira el "Capital Centro-Oeste = Z2 + Z3" de la
v21.43. En `gv_ppp_web_camion` la ZONA manda sobre el sector para Z2 y Z3 (los sectores C..H siguen
armando la tanda por cercanía, no deciden el camión). Centinela `Capital Oeste` en `GV_Reglas_Centinela`.
