# Primeros días con Gestión — qué necesita cada uno

> Escrito el sábado 2026-09-05 a la noche, a pedido del dueño: *"aplicación de esto de que recién en
> cuatro o cinco días: para que veamos qué cosas van a necesitar los operarios para trabajar desde
> este programa, y qué cosas va a necesitar la administrativa para usarlo de manera eficiente, ya que
> estoy haciendo un cambio sin explicarles el programa"*.
> Versión app: v13.23. Página publicada (para compartir): ver el link en el chat de la sesión.

## La semana

| día | qué pasa |
|---|---|
| **lun 7** | Día del Metalúrgico. No se trabaja (`GV_Dias_No_Habiles`). A las 00:01 el job arma lo web pendiente **para el viernes 11**. |
| **mar 8** | Primer día real con Gestión. Se arma lo que ISIS dejó: 13,45 m³, 7 tandas (D59A, D60A–F, D61A). Nada web. |
| **mié 9** | ISIS: 10,77 m³ (D62A, D66A–F). |
| **jue 10** | ISIS: 5,76 m³ (D67A–K). |
| **vie 11** | ISIS: 3,14 m³ (D68A–F) + **las primeras tandas web, ya programadas el sábado**: E01A (1344), E01B (1345+1347), E01C (1348+1351), E01D (1342+1346), E01E (1343) y F01A (Chef 216) = 3,33 m³. |
| **lun 14** | ISIS: 1,51 (D69A–C) + lo que no entró el viernes (1350 Cuyana, 0,94) y lo que llegue. |

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
| **A Programar** | Pedidos de la página (LK y Chef) que **todavía no tienen tanda**: nada de acá está programado. Cada tarjeta dice qué va a pasar: **"🤖 se arma solo → vie 11/9 · en minutos"** (zona automática) o **"🚚 va al camión del vie 11/9 · en minutos"** (zona manual con camión a la zona), y si no, "retira", "súper: a mano", "sin camión previsto". | **v13.47:** todo lo que tiene día lo programa el automático en la próxima corrida (cada 15 min, todos los días 06:00–20:45): zonas 1/2/3 al primer día con cupo (y lo que no entra, al siguiente), zonas 4/5/6 al día en que ya hay camión a la zona. Acá queda sólo **Retira, Súper, sin zona o sin camión previsto**: "+ Nueva tanda vacía", arrastrar pedidos, arrastrar la tanda a un día. **El arrastre sólo funciona en la compu.** |
| calendario (misma solapa) | Un renglón por día: `m³ usados / cupo`, línea "📋 ISIS: …", **"Muy pronto"** en los días antes del mínimo, "No hábil". | Días completos, no hábiles o muy pronto no reciben. |
| **Programación** | Tablero de 6 días (botón "Ver hoja 2 →"), camiones numerados por día, Súper aparte. Tocar un día → camiones, orden de carga, pedidos y estado (sin empezar / en curso / armado). Cuenta **sólo lo que tiene fecha por delante**. | Los de fecha vencida no están acá (v13.33): son un dato de gerencia y se miran desde **Resumen**. |
| **Resumen** | Cuadro de m³ por día y zona (el "Resumen Prog" de siempre). Arriba, la línea **"⏰ N pedido(s) con fecha de entrega vencida… Ver la lista →"**. | Es la vista de gerencia: ahí se decide qué se hace con los vencidos (reprogramar, cargar o sacar de ISIS). |
| **Facturación** | NP de ISIS: tilde ✓ como siempre. **NP web (`LK 1350`): tildar y bajar el Excel ISIS = facturada**; ese Excel se carga en ISIS. | El cruce de factura ya entiende las NP web. |
| **En Salida** | Lo cargado al camión que todavía no se controló. | Si pasa el plazo sin control, alerta naranja. |
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
  Quedarían dobles.
- **No cargar en ISIS los mails de Chef del viernes (216) ni del sábado (217)**: Gestión los toma de la
  página (216 ya es F01A). El cron de Chef quedó apagado el domingo; no salen más.
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
- [ ] No cargar el mail del sábado en ISIS.
- [ ] Explicarle a la operadora el paso nuevo de Facturación: **NP web → tildar → bajar Excel ISIS**.
- [ ] Los 20 atrasados (v13.46): 12 facturadas y armadas → marcar Controlado; 4 de D57B (98510, 98541,
  98542, 98543) armadas sin facturar → decidir; 4 sin armar (D57C 98553/98554, D57D 98528/98600) → reprogramar.
- [ ] **Viernes 05/09 no llegó ningún evento de Producción** (ni picking, ni armado, ni tics de facturación;
  el jueves sí, hasta 17:12). Mirar en ISIS qué se facturó el viernes y pasármelo: lo cargo por SQL con fecha
  del viernes, con OK explícito antes de escribir.
- [ ] **Armadas sin tildar en Facturación**: 98510, 98541, 98542, 98543 (D57B), 98647 Coto (D59A), 98619
  Carrefour (D61A). Faltante sólo en 98542 Pro Tatiana (566E 3/5, 583E 4/10, 231/232/233 1/1).
- [ ] **44619 Chango Mas (Dorinka, 4,31 m³, vie 11) está en ISIS SIN TANDA** (tipo KRIKOS, "OC 9400146407").
  Gestión no lo cuenta en el cupo del viernes mientras no tenga tanda: el viernes hoy suma 3,14 ISIS + 3,33
  web = 6,47; con esto serían 10,8 m³. Ponerle tanda en ISIS (sale en camión propio, súper) o moverlo.
- [ ] **Stock para las tandas web del viernes** (según `vista_stock_vs_pedidos`, cortado al domingo): sin
  stock hoy 323E (E01A Torres y Liva pide 20), 438E, 232, 233, 951E, 957E, 970E, 971E, 727E (F01A pide 3);
  justo 508 (16 en stock, 18 pedidas en total). Hay 4 días para producir; si no, salen con faltante como
  cualquier tanda.
- [x] ~~Pedidos web que NO se arman solos~~ — **v13.47 (domingo a la tarde)**: el automático los programa
  solo si tienen día: LK 1349 Bazar Mónica → vie 11 (camión zona 5), LK 1350 Cuyana → lun 14, LK 1341 Orfali
  y CH 0217 Gifel → lun 14 (camión zona 6, D69C). Queda a mano sólo **LK 1340 Garbarino (Retira, 0,03)**.
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
