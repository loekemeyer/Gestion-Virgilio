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
3. **Entrar con Google**: el mail del operario tiene que estar cargado en `Empleados`. Hoy hay 21 de 69
   con mail. De los que registraron eventos el último mes: 104 Jhonny Moncayo, 237 Franco Ortiz,
   277 Jhonny Cartaya, 8 Farias Juan Hilario y 94 Isidro Tevez **sí**; **122 y 504 no tienen mail**
   → no van a poder entrar hasta que se les cargue.
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
| **A Programar** | Pedidos de la página (LK y Chef) que **todavía no tienen tanda**: nada de acá está programado. Cada tarjeta dice qué va a pasar: **"🤖 se arma solo → vie 11/9"** (zona automática) o **"🚚 hay camión el vie 11/9 · programalo"** (zona manual), y si no, "retira", "súper: a mano", "sin camión previsto". | Zonas 1/2/3 se arman solas (00:01 y cada 15 min si juntan 0,80 m³). Zonas 4/5/6, Súper y Retira **a mano**: "+ Nueva tanda vacía", arrastrar pedidos, arrastrar la tanda a un día. **El arrastre sólo funciona en la compu.** |
| calendario (misma solapa) | Un renglón por día: `m³ usados / cupo`, línea "📋 ISIS: …", **"Muy pronto"** en los días antes del mínimo, "No hábil". | Días completos, no hábiles o muy pronto no reciben. |
| **Programación** | Tablero de 6 días (botón "Ver hoja 2 →"), camiones numerados por día, Súper aparte. Tocar un día → camiones, orden de carga, pedidos y estado (sin empezar / en curso / armado). Cuenta **sólo lo que tiene fecha por delante**. | Los de fecha vencida no están acá (v13.33): son un dato de gerencia y se miran desde **Resumen**. |
| **Resumen** | Cuadro de m³ por día y zona (el "Resumen Prog" de siempre). Arriba, la línea **"⏰ N pedido(s) con fecha de entrega vencida… Ver la lista →"**. | Es la vista de gerencia: ahí se decide qué se hace con los vencidos (reprogramar, cargar o sacar de ISIS). |
| **Facturación** | NP de ISIS: tilde ✓ como siempre. **NP web (`LK 1350`): tildar y bajar el Excel ISIS = facturada**; ese Excel se carga en ISIS. | El cruce de factura ya entiende las NP web. |
| **En Salida** | Lo cargado al camión que todavía no se controló. | Si pasa el plazo sin control, alerta naranja. |
| **Entregados** | Lo controlado (CRN). | — |

**Lo automático (no hay que hacer nada, pero conviene saber que existe):**

- **00:01 lun–vie**: job de tandas (cron 71) → arma zonas 1/2/3 pendientes para el próximo día con cupo
  desde hoy + 4 hábiles. Deja constancia en `GV_Tandas_Auto_Log`.
- **Cada 15 min 07:00–18:45**: intradía (cron 73), mismo criterio, sólo si lo pendiente suma ≥ 0,80 m³.
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
| `intradia_umbral_m3` / `intradia_corte_hora` | 0,80 / 12:00 | cuándo arma el intradía |
| `sectores_activos` | 1 | tandas por cercanía real (sectores + vecinos) |

## Lo que hace falta ANTES del martes (dueño)

- [ ] Pasar la URL de Gestión a los operarios y al monitor de pared (`?monitor=tv&key=…` la primera vez).
- [ ] Cargar el mail en `Empleados` de los que faltan (al menos **122** y **504**; activos).
- [ ] Que cada uno abra Producción una vez con señal antes de cambiar (cola offline).
- [x] Apagar el cron de Chef de las 12:30 — hecho el domingo 06/09 (jobs 1 y 2 en `active=false`).
- [ ] No cargar el mail del sábado en ISIS.
- [ ] Explicarle a la operadora el paso nuevo de Facturación: **NP web → tildar → bajar Excel ISIS**.
- [ ] Decidir los 38 atrasados de ISIS (reprogramar en ISIS o cargar).
- [ ] Chef: password de `ch_ppp_reader` + correr `paginach/sql/gv_estado_mis_pedidos_chef.sql` (para que el cliente vea el estado).
- [ ] Decisiones abiertas: orden de carga por cod cliente (1/2/3); carteles del tablero.

## Lo que voy a mirar yo

- **Martes 08:30**: corrida del job (lunes y martes), tandas web con fecha ≥ 11, foto de artículos, calendario,
  intradía, eventos de operarios en Gestión, alertas, cron 74. Resumen al dueño.
- **Martes 15:00**: control de pedidos muertos (página vs Gestión vs Producción), dobles, Chef.
- Cualquier cambio de interruptor: pedírmelo por chat; queda anotado en `docs/SUPABASE-GESTION-VIRGILIO.md`.

## Lo que todavía no está (estacionado, no bloquea)

Krikos, pedidos duales LK+Chef el mismo día (`empresa_de_np`), módulo Chef completo, tracking a la
página, orden de carga por cod cliente, cupo con tope de armado.
