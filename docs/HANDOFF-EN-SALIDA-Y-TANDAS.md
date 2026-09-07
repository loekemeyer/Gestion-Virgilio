# Traspaso — pendientes de la sesión de En Salida (2026-09-07)

> Reescrito el 07/09 al mediodía. La versión anterior de este archivo quedó vieja en
> horas: decía que los crons estaban apagados y que faltaba la acumulación, y las dos
> cosas ya están resueltas por la otra sesión.
>
> ⚠ **Dos sesiones trabajando sobre `main` a la vez.** Esta sesión venía de la v13.65
> y al volver main estaba en la v13.88. Antes de tocar nada: `git pull --rebase origin main`.
>
> **Estado al 07/09 13:20 — `main` va por `v13.92`** (commit `7361d86`). La v13.90 y la v13.91 las
> tomó esta sesión; la v13.92 la sesión de "Pipeline Gestión Virgilio pendientes" (hoja de ruta
> imprimible del camión). **El próximo bump arranca en `v13.93`.** Único cambio de esa sesión que
> toca algo compartido: se agregó `observaciones` al `select` de `gv_ppp_programacion_diaria` en
> `pppLoadProgFromSupabase` y al row de `_pppRowFromSupa` — campo nuevo, nada de lo que ya había
> cambió. Esa sesión **no toca `ppp_web_armar_tandas`**: el punto 1 de acá es todo tuyo.

---

## 1. PENDIENTE (para quien esté en `ppp_web_armar_tandas`) — enganchar el pedido al camión que YA va al cliente

**El caso, medido el 07/09.** Osa Distribuidora (cod **2533**, Villa Lugano, Zona 1) tenía
camión el **miércoles 9/09** — tanda `D66B`, NP 98650 (2,710 m³) y 98667 (1,331 m³). Entró un
pedido web del mismo cliente (0,026 m³) y el automático lo programó para el **martes 15/09**,
en un camión aparte. 26 litros, seis días después, al mismo cliente y al mismo barrio.

**Por qué pasó — dos causas independientes:**

1. **El colchón lo tapaba.** Con `dias_anticipacion_min = 4`, un lunes 7 el mínimo era el 11:
   los días 8, 9 y 10 no eran candidatos. (Ojo: la v13.84 ya habilitó "programar para antes",
   así que esta mitad puede estar resuelta — verificar.)
2. **El automático nunca mira si el cliente ya tiene camión ese día.** Sólo mira cupo por día y
   cercanía entre las tandas que arma en esa misma corrida. La `D66B` es de ISIS y queda
   íntegramente fuera de su universo.

El cupo tampoco lo hubiera dejado entrar: el 9 estaba en **7,03 m³ de ISIS contra un cupo de 6**.

**Pero acá el cupo no debería mandar.** El cupo mide capacidad de *picking*; sumarle 26 litros a
un cliente que ya tiene 4 m³ armándose para ese día es casi gratis y ahorra un camión entero.

**Lo que decidió el dueño (07/09):**

- **La regla pisa el colchón Y el cupo.** Fue explícito: es el único modo que resuelve el caso,
  porque el 9 estaba a la vez dentro del colchón y pasado de cupo.
- **Se busca HACIA ATRÁS, no hacia adelante.** Textual: *"tiene que buscar para atrás, no para
  adelante"*. O sea: entre hoy y el día que el automático asignaría por su cuenta, tomar el día
  en que el cliente ya tiene entrega. **La regla adelanta el pedido, nunca lo demora.**

Ya existe media pieza: la v13.47 manda las zonas manuales al día en que hay camión a esa **zona**
(`gv_ppp_web_armar_pendientes`, §3.ao). Falta la versión **por cliente** y para todas las zonas.

**Va en el backend** (decidido con el dueño, dos veces, y es lo que pide el protocolo del repo).

---

## 2. PENDIENTE — 20 filas de `CLIENTE SIMULACIÓN` en `Facturacion_NP`

`cod_cliente = 99999`, razón social `CLIENTE SIMULACIÓN`, tandas `SIM######`, **m³ = 1,000
clavado en las 20**. Alguien probó la pantalla de Facturación el **lunes 31/08** y los tics
quedaron: entraron de a una, con segundos de diferencia, en dos tandas (11:09–11:10 y
11:39–11:40). Las 20 tienen `cierre_id` en null; las reales llevan cierre.

**Verificado que no son reales:** 0 filas en `PPP_Programacion_Diaria`, `PPP_Base_Pedidos` y
`PPP_Web_Programacion`; 0 eventos en `Registros_Produccion_Virgilio`; 0 coincidencias en el
código de Gestión y de Producción (commit e15b682) — no las genera ninguna app.

**Se ven desde la v13.62**, que cambió el universo de `gv_ppp_en_salida` de "tiene CCN" a
"facturada sin CRN". Inflan el módulo: de las 54 NP que muestra, **20 son éstas**, y **20 de los
24,65 m³ son ficticios**. El universo real es **34 NP y 4,65 m³**.

**El dueño dio el OK para borrarlas** (eligió esa opción sobre filtrarlas en la vista), pero
frenó antes de que se escribiera el backup, así que **no se borró nada**. Siguen ahí.

⚠ `Facturacion_NP` es tabla **compartida** con Producción y la regla del dueño es que ahí se
agrega y no se borra. Rehacer el backup antes (`sql/backups/`), y usar un `WHERE` real
(`supautils` bloquea `DELETE` sin `WHERE`).

```sql
select np, tanda, m3, facturado_at from public."Facturacion_NP" where cod_cliente = '99999';
```

---

## 3. PENDIENTE — artículo 578 y el pedido 1354 de Osa

El pedido **1354** (cliente 2533, 5 cajas del **578 Descarozador De Aceitunas**) es **real** —
lo confirmó el dueño. Pero el artículo está **dado de baja**: `active = false`, `list_price = 0`,
`uxb = 1`. Última venta real: **26/11/2021**. Nunca se pidió por la web.

Consecuencia: **el pedido está valorizado en $0** y así va a llegar a Facturación.

Falta que el dueño pase **precio de lista** y **unidades por caja** del 578, y decida si se
reactiva en el catálogo (ojo: activarlo lo publica para **todos** los clientes del portal, no
sólo para Osa). Dijo *"lo veo mañana"* (08/09).

---

## 4. HECHO — no rehacer

- **En Salida (v13.62)**: universo "facturada sin CRN" (de 13 a 54 NP, 0 perdidas), fecha y hora
  reales de carga, chips de estado por NP, y Recepción de Remitos embebida sólo para
  supervisores (CRN y FSS, reusando `crSendDetail` / `crSendSinSalida`). El módulo RR de arriba
  quedó intacto. Doc: `docs/SUPABASE-GESTION-VIRGILIO.md` §3.au. Test:
  `tests/ppp-ensalida-estado.cjs` (17 chequeos).
- **El 1354 de Osa se movió a mano** de `E03A`/15-09 a **`D66G` / 09-09**, camión 66, el mismo
  día que las otras dos NP de Osa (`D66B`). Tanda propia, como lo pidió el dueño.
  Rollback: `update public."PPP_Web_Programacion" set tanda='E03A', fecha_entrega='2026-09-15' where order_id=1354;`
- **`CCR sin CCN`: AUDITADO Y CERRADO — no hay nada que arreglar.** Se había reportado como
  "el circuito se está usando mal"; **eso estaba mal dicho** y queda corregido acá.

  Los números: de **866 NP con CCR, 841 también tienen CCN**. Sólo **25 (2,9%)** tienen CCR sin
  CCN, repartidas en 8 tandas de tilde entre el 29/07 y el 04/09. O sea que el 97,1% del
  circuito se usa bien; esto es la excepción.

  Y las excepciones **se cierran solas**: de esas 25, las **17 más viejas** ya no están en En
  Salida, y las 17 figuran en la **hoja de entregados** (`gv_ppp_entregados_meta`), ninguna con
  CRN. Salieron, se entregaron, y el Excel de ISIS las absorbió. Las **8 que se ven hoy**
  (98474 del 03/09, y 98509 + 98585–98590 del 04/09) son sólo la cola reciente que el Excel
  todavía no alcanzó.

  El patrón del tilde también quedó claro: las seis de la D56D las armó **Franco Ortiz (237)**
  el 03/09 a las 14:08:49 —el mismo segundo, una tanda— y **Farias Juan Hilario (8)** les puso
  el CCR el 04/09 a las 09:54:32, las siete dentro de una décima de segundo. Eso es el botón
  **"✓ Controlar TODA la tanda"**, no gente controlando remito por remito.

  **Conclusión: es un retraso de registro, no un circuito roto.** No hace falta cambiar nada;
  a lo sumo, si molesta verlas, se les puede bajar el ruido en pantalla. El chip `CCR sin CCN`
  sigue siendo útil para detectarlas.

## 4.b Dato suelto sobre el recordatorio de faltantes

`FAC_OPERADORA_EMAIL = "loekemeyer.n8n@gmail.com"` — el mismo mail con el que entra el dueño
como supervisor. Por eso el recordatorio "⏰ Es hora de completar los faltantes" **le llega a
él** (camino 2 de `cpRecordCheck`), no sólo a la operadora.

El dueño reportó que le disparó **un lunes ~10:20**, y eso el código no lo explica: el filtro
`if (!t.habil || t.min < CP_RECORD_MIN) return;` es lo primero que corre y el piso es 15:30.
La función de hora se probó en V8 barriendo las 24 h y devuelve bien; el `alert` existe en un
solo lugar. Queda sin explicar — la hipótesis viva es un `index.html` viejo cacheado en el
navegador, o el reloj del dispositivo corrido. **No se tocó nada** (el dueño pidió sólo
diagnosticar).

Lo que sí está confirmado del recordatorio, y conviene arreglar cuando se encare:
- **no tiene tope superior**: dispara de 15:30 a 23:59;
- **el dedup vive en `localStorage`**, o sea una vez por dispositivo/navegador, no por persona;
- **el mismo recordatorio está en Producción y en Gestión**, dominios distintos → avisa dos veces;
- **no sabe de feriados** (sólo mira lunes a viernes, no `GV_Dias_No_Habiles`);
- marca "ya avisé" **antes** de abrir el modal: si `showCPModal` falla, el error se traga y no
  reintenta en todo el día.

## 5. Correcciones a la versión anterior de este archivo

Lo que decía y ya no vale:

- ~~"Los crons 71 y 73 están apagados"~~ → **prendidos** desde la v13.67, después de que
  `ppp_web_armar_tandas` v7 hiciera que la tanda acumule entre corridas.
- ~~"Falta implementar que la tanda acumule hasta 0,80"~~ → **hecho** (v13.67), y el tope pasó
  de 0,80 a **1,00** en la v13.86.
- ~~"El pedido 1352 de Muller sigue vivo"~~ → **borrado**, en LK y en Virgilio.
- ~~"Basura en `bot_customer_whatsapps`"~~ → la tabla se **vació** (commit 55bb0a0): las 5 filas
  eran WhatsApp de prueba.
- ~~"La NP web debería ser el número de pedido (v12.92)"~~ → **la v13.70 lo revirtió a propósito**:
  la NP web es un contador propio, un número por bloque, sin sufijo (`LK 0001`…). `LK 0024` para
  el pedido 1354 es lo correcto.
