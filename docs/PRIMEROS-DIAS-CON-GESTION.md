# Primeros días con Gestión — qué necesita cada uno

> Escrito el sábado 2026-09-05 a la noche, a pedido del dueño: *"aplicación de esto de que recién en
> cuatro o cinco días: para que veamos qué cosas van a necesitar los operarios para trabajar desde
> este programa, y qué cosas va a necesitar la administrativa para usarlo de manera eficiente, ya que
> estoy haciendo un cambio sin explicarles el programa"*.
> Versión app: v13.23. Página publicada (para compartir): ver el link en el chat de la sesión.

## La semana

| día | qué pasa |
|---|---|
| **lun 7** | Día del Metalúrgico. No se trabaja (`GV_Dias_No_Habiles`). **Al 07/09 el automático (crons 71 y 73) estuvo apagado hasta que se implementó "acumular hasta 0,80" (v13.67); al prenderse, arma lo web pendiente para el primer día con cupo (hoy: mar 15).** |
| **mar 8** | Primer día real con Gestión. **v13.60 (dom 6 a la noche): el lunes 7 es feriado y nada estaba armado, así que la semana se corrió UN día hábil (salvo súper).** Sale el martes sólo lo ya armado: **D59A Coto y D61A Carrefour** (8,87 m³). Ese día se pickea y arma lo del **mié 9: D60A–F (9 NP, 4,58 m³, GBA Sur/Oeste) + D62A Patagonia** (pickeada el 3/9, falta armar). Después: jue 10 = D66A–F (7,78) · vie 11 = D67A–K (5,76) + E07A Chango Mas · lun 14 = D68A–G + E01A–F (6,58, primer día con web) · mar 15 = D69A–E + E03A–B. Matiz D71A sigue el mié 16. |
| **mié 9** | ISIS: 10,77 m³ (D62A, D66A–F). |
| **jue 10** | ISIS: 5,76 m³ (D67A–K). |
| **vie 11** | **Corregido 07/09 (v13.60 corrió la semana un día hábil):** sale D67A–K (35 NP, 5,76 m³, Capital) + **E07A 44619 Chango Mas (4,31, súper con turno; ISIS sin tanda → override)**. Las tandas web pasaron al lunes 14. |
| **lun 14** | D68A–F (13 NP, 3,14 m³, GBA Sur/Oeste) + D68G (1349 Bazar Mónica, zona 5) + **las primeras tandas web**: E01A (1344), E01B (1345+1347), E01C (1348+1351), E01D (1342+1346), E01E (1343), E01F (Chef 216) = 3,33 m³. Total 6,58 m³. |
| **mar 15** | D69A–C (5 NP, 1,51 m³) + D69D (1341 Orfali) + D69E (Chef 217 Gifel) + E03A (1350 Cuyana, 4 NP, 0,94) + E03B (1352, pedido de prueba: se borra). |
| **lun 14** | ISIS: 1,51 (D69A–C) + E03A (1350 Cuyana, 0,94), E05A (1341 Orfali, 1,18), E06A (CH 0217 Gifel) = 3,77 m³. |

Los 4 días de colchón (`dias_anticipacion_min = 4`) están para esto: ver qué falta antes de que una tanda
web llegue al depósito. Cupo diario = pickers típicos × 3 m³ (hoy 2 → 6), contando ISIS + web.

## Operarios (celular)

**Lo que necesitan sí o sí:**

1. **La URL nueva**: `https://loekemeyer.github.io/Gestion-Virgilio/`. Agregarla a la pantalla de inicio
   ("Agregar a inicio" en Chrome). La app de Play Store sigue apuntando a Producción: **no usarla**.
2. **Antes de cambiar, abrir Producción una vez con señal** para que vacíe su cola offline (los eventos
   sin mandar quedan en el IndexedDB de esa app; en la nueva no están).
3. **Entrar**: con Google (si el mail está en `Empleados`) **o con el número de legajo** — botón
   "Entrar con legajo" en la pantalla inicial. Sólo pide que el legajo exista en `Empleados`; no hace
   falta mail. La sesión por legajo dura el día. **122 Adrian Villalba y 504 Kevin Latronico entran
   con legajo** (corrección del 06/09: antes decía que no podían entrar sin mail).
4. **Nada que aprender en los botones**: son los mismos (EP/TP picking, AP/TAP armado, CC carga de
   camión, RR recepción de remitos, MG, RT, Terminar Día). Mismas pantallas de picking y armado.

**Lo que van a ver distinto (avisarles):**

- **Tandas nuevas `E01A`, `E01B`…** al lado de las de ISIS (`D60A`…). Se pickean y arman igual.
- **NP con letras: `LK 1350`, `LK 1350-2` (bloque 2), `CH 0217`** en vez de 5 dígitos. La etiqueta se
  imprime igual desde la cola de impresión.
- Si una tanda web aparece **sin artículos**, no pickear de memoria: avisar (la foto de artículos la
  arma el job; si falta es un error nuestro).
- **Control de remito = entregado.** En Gestión no hay paso aparte de "entregados": cuando marcan
  Controlado en Recepción Remitos (RR), el pedido pasa a entregado. Si no lo marcan, queda "en salida" y
  salta alerta.
- El **Súper** sale en camión propio; **Retira en fábrica** no es camión.

## Administración (supervisores / operadora)

**Entrar**: misma URL, con uno de los 3 mails de supervisor. Botón 🗓 PPP.

**Solapas de la PPP y para qué sirve cada una:**

| solapa | qué hace | qué mirar |
|---|---|---|
| **A Programar** | Pedidos de la página (**LK y Chef juntos, sin selector de empresa desde v13.58**) que **todavía no tienen tanda**: nada de acá está programado. Cada tarjeta dice qué va a pasar: **"🤖 se arma solo → vie 11/9 · en minutos"** (zona automática) o **"🚚 va al camión del vie 11/9 · en minutos"** (zona manual con camión a la zona), y si no, "retira", "súper: a mano", "sin camión previsto". | **v13.47:** todo lo que tiene día lo programa el automático en la próxima corrida (cada 15 min, todos los días 06:00–20:45): zonas 1/2/3 al primer día con cupo (y lo que no entra, al siguiente), zonas 4/5/6 al día en que ya hay camión a la zona. Acá queda sólo **Retira, Súper, sin zona o sin camión previsto**: **arrastrar el pedido directo al día: la tanda se arma sola (código automático, empresa del pedido) y queda programada ese día** (v13.69; sin botones de tanda LK/Chef; una tanda es de una sola empresa). |
| calendario (misma solapa) | Un renglón por día: `m³ usados / cupo`, línea "📋 ISIS: …", **"Muy pronto"** en los días antes del mínimo, "No hábil". | Días completos, no hábiles o muy pronto no reciben. |
| **Programación** | Tablero de 6 días (botón "Ver hoja 2 →"), camiones numerados por día, Súper aparte. Tocar un día → camiones, orden de carga, pedidos y estado (sin empezar / en curso / armado). Cuenta **sólo lo que tiene fecha por delante**. | Los de fecha vencida no están acá (v13.33): son un dato de gerencia y se miran desde **Resumen**. |
| **Resumen** | Cuadro de m³ por día y zona (el "Resumen Prog" de siempre). Arriba, la línea **"⏰ N pedido(s) con fecha de entrega vencida… Ver la lista →"**. | Es la vista de gerencia: ahí se decide qué se hace con los vencidos (reprogramar, cargar o sacar de ISIS). |
| **Facturación** | NP de ISIS: tilde ✓ como siempre. **NP web (`LK 1350`): tildar y bajar el Excel ISIS = facturada**; ese Excel se carga en ISIS. | El cruce de factura ya entiende las NP web. |
| **En Salida** | Lo cargado al camión (CC) cuyo remito todavía no volvió por **Recepción Remitos (RR)**. El Control de Remitos (CR) de antes de cargar NO lo saca de acá (v13.57). | Si pasa el plazo sin RR, alerta naranja. Hoy: 13 del viernes 4/9. |
| **Entregados** | Lo controlado (CRN). | — |

**Lo automático (no hay que hacer nada, pero conviene saber que existe):**

- **00:01 lun–vie**: job de tandas (cron 71) → arma zonas 1/2/3 pendientes desde el próximo día con cupo
  (hoy + 4 hábiles), en cascada si no entra todo, y zonas 4/5/6 al día en que hay camión a la zona (v13.47).
  Deja constancia en `GV_Tandas_Auto_Log`.
- **Cada 15 min, todos los días 06:00–20:45**: intradía (cron 73), mismo criterio, **apenas hay algo
  pendiente** (umbral 0,001 m³ desde el sábado 05/09; dueño: *"si ya programaste, directo que salgan de A
  Programar"*; v13.47: *"mandá directo a Programación si ya está"*).
- **Cada 10 min**: stock (cron 68 de Producción + cron 74 para tandas web).
- **Telegram**: alertas de picking sin stock, carga sin control, errores de PPP, etc., igual que antes.

**Lo que NO hay que hacer (esta semana):**

- **No cargar en ISIS el mail del sábado 12:30** (pedidos LK 1340…1349): Gestión los programa.
  Quedarían dobles. **⚠ Se cargó igual (visto el domingo en el Excel: 98696–98703 = 1340–1344, y 44620/21 =
  Chef 216).** Gestión los oculta (v13.51); falta anularlos en ISIS y no cargar 1345–1349.
- **No cargar en ISIS los mails de Chef del viernes (216) ni del sábado (217)**: Gestión los toma de la
  página (216 ya es E02A). El cron de Chef quedó apagado el domingo; no salen más.
- No usar Producción para programar ni facturar: lo web no está ahí.

**Interruptores (los toco yo, con pedido del dueño; viven en `PPP_Web_Config`):**

| clave | hoy | qué hace |
|---|---|---|
| `dias_anticipacion_min` | 4 | colchón de días hábiles; 0 = programar para hoy/mañana |
| `cupo_por_dotacion` / `cupo_m3_por_picker` | 1 / 3 | cupo = pickers típicos × 3 m³; 0 = fijo `m3_max_dia` (5) |
| `zonas_automaticas` | 1,2,3 | qué zonas se arman solas |
| `intradia_umbral_m3` / `intradia_corte_hora` | 0,001 / 12:00 | cuándo arma el intradía (0,001 = apenas hay algo; 0,80 = esperar a juntar) |
| `sectores_activos` | 1 | tandas por cercanía real (sectores + vecinos) |

## Lo que hace falta ANTES del martes (dueño)

- [ ] Pasar la URL de Gestión a los operarios y al monitor de pared (`?monitor=tv&key=…` la primera vez).
- [x] ~~Cargar el mail en `Empleados` de 122 y 504~~ — no hace falta: entran con el número de legajo.
- [ ] Que cada uno abra Producción una vez con señal antes de cambiar (cola offline).
- [x] Apagar el cron de Chef de las 12:30 — hecho el domingo 06/09 (jobs 1 y 2 en `active=false`).
- [ ] ~~No cargar el mail del sábado en ISIS~~ → ya se cargó (1340–1344 y Chef 216): **anular en ISIS 98696–98703 y 44620/44621**, y no cargar 1345–1349.
- [ ] Explicarle a la operadora el paso nuevo de Facturación: **NP web → tildar → bajar Excel ISIS**.
- [ ] Los 20 atrasados (v13.46): 12 facturadas y armadas → marcar Controlado; 4 de D57B (98510, 98541,
  98542, 98543) armadas sin facturar → decidir; 4 sin armar (D57C 98553/98554, D57D 98528/98600) → reprogramar.
- [x] ~~Viernes sin eventos de Producción~~ — **falsa alarma mía (06/09): el 4/9 era VIERNES, no jueves.**
  El viernes 4/9 llegó todo (46 eventos de operarios, 581 movimientos de stock, 6 tics de facturación); el
  día sin actividad era el sábado 5/9. No hay nada que reconstruir. Runbook por si pasa de verdad:
  `docs/RUNBOOK-EVENTOS-PERDIDOS.md`.
- [ ] **Armadas sin tildar en Facturación**: 98510, 98541, 98542, 98543 (D57B), 98647 Coto (D59A), 98619
  Carrefour (D61A). Faltante sólo en 98542 Pro Tatiana (566E 3/5, 583E 4/10, 231/232/233 1/1).
- [x] ~~44619 Chango Mas sin tanda en ISIS~~ — **v13.50: programado como E07A (vie 11)** vía `GV_PPP_Prog_Override`
  (ISIS/Producción siguen viéndolo sin tanda; Gestión lo ve en E07A). El viernes queda en 10,9 m³ (súper en camión propio).
- [ ] **Stock para las tandas web del viernes** (según `vista_stock_vs_pedidos`, cortado al domingo): sin
  stock hoy 323E (E01A Torres y Liva pide 20), 438E, 232, 233, 951E, 957E, 970E, 971E, 727E (F01A pide 3);
  justo 508 (16 en stock, 18 pedidas en total). Hay 4 días para producir; si no, salen con faltante como
  cualquier tanda.
- [x] ~~Pedidos web que NO se arman solos~~ — **v13.47 (domingo a la tarde)**: el automático los programa
  solo si tienen día: LK 1349 Bazar Mónica → lun 14 **D68G** (camión D68, zona 5; era E04A vie 11), LK 1350 Cuyana → mar 15 E03A, LK 1341
  Orfali **D69D** y CH 0217 Gifel **D69E** → mar 15 (camión D69, zona 6; eran E05A/E06A lun 14). Renombres y corrimiento: v13.60. Queda a mano sólo **LK 1340 Garbarino (Retira, 0,03)**.
  Chef 215 Dorinka quedó excluido porque ya es el 44619 de ISIS.
- [ ] Chef: password de `ch_ppp_reader` + correr `paginach/sql/gv_estado_mis_pedidos_chef.sql` (para que el cliente vea el estado).
- [ ] Decisiones abiertas: orden de carga por cod cliente (1/2/3); zonas manuales ¿se suman solas a un camión
  existente del día?

## Lo que voy a mirar yo

- **Martes 08:30**: corrida del job (lunes y martes), tandas web con fecha ≥ 11, foto de artículos, calendario,
  intradía, eventos de operarios en Gestión, alertas, cron 74. Resumen al dueño.
- **Martes 15:00**: control de pedidos muertos (página vs Gestión vs Producción), dobles, Chef.
- Cualquier cambio de interruptor: pedírmelo por chat; queda anotado en `docs/SUPABASE-GESTION-VIRGILIO.md`.

## Lo que todavía no está (estacionado, no bloquea)

Krikos, pedidos duales LK+Chef el mismo día (`empresa_de_np`), módulo Chef completo, tracking a la
página, orden de carga por cod cliente, cupo con tope de armado.
