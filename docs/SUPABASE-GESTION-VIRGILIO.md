# Gestión Virgilio ↔ Supabase — registro de cambios y reglas

> **Qué es esto.** El historial de todo lo que Gestión Virgilio crea, lee y escribe en
> Supabase, en orden cronológico. Existe para que no se pierda entre sesiones: si abrís
> una sesión nueva, **este archivo y no la memoria** es lo que dice en qué estado está el
> pipeline propio.
>
> Cada entrada dice **qué se hizo, por qué, qué impacto se midió y cómo se revierte**.
> Se escribe en el momento del cambio, no después.

---

## 0. El hecho que condiciona todo

**Las dos apps comparten el MISMO proyecto Supabase y la MISMA anon key.**

| | |
|---|---|
| Proyecto | `hrxfctzncixxqmpfhskv` ("Control Partes Talleristas") |
| anon key | `sb_publishable_BqpAgZH6ty-9wft10_YMhw_0rcIPuWT` |
| App **en producción hoy** | repo `loekemeyer/Produccion-Virgilio` |
| App **en construcción** | repo `loekemeyer/Gestion-Virgilio` (este) |

Verificado el 2026-09-04 leyendo `supabase-config.js` de los dos repos: misma URL, misma key.

Consecuencia: **"no romper Producción" no se resuelve evitando una tabla.** Cualquier
cosa que se toque en `public.*` —una fila, una función, un trigger, un cron, un grant—
la ve la app que los operarios están usando en este momento.

---

## 1. LA REGLA (fijada por el dueño, 2026-09-04)

> *"Todo lo que hagamos tiene que ser un insert sobre lo que ya hay. Cuando no se pueda
> hacer un insert, se tiene que crear una tabla nueva, hacer todas las conexiones
> necesarias para que haga lo que Gestión Virgilio quiere hacer, y que sea la fuente
> canónica para Gestión Virgilio."*

**El criterio, en una línea: sobre una tabla compartida se AGREGA, nunca se MODIFICA lo
que ya está.** Traducido a cada caso que aparece en la práctica:

| Querés… | Se puede | Cómo |
|---|---|---|
| Agregar **filas** a una tabla compartida | ✅ | `insert … on conflict do nothing`. **Nunca `do update`** — eso modifica una fila existente y está prohibido. |
| Agregar una **columna** a una tabla compartida | ✅ con cuidado | Es "agregar cosas", así que entra. Pero: **nullable, sin `default` que reescriba filas, sin backfill**, y con prefijo `gv_` en el nombre para que se sepa de quién es. Producción no la selecciona, así que no la ve. |
| Cambiar **filas existentes** (`update`, `delete`, `truncate`) | ❌ | Tabla `GV_*` de override + una vista que la superpone. La `GV_*` es la fuente canónica **para Gestión**; Producción sigue leyendo la original, intacta. |
| Cambiar o borrar una **columna existente** | ❌ | idem: override. |
| Objeto nuevo (tabla, vista, función) | ✅ | Prefijo propio: `PPP_Web_*`, `GV_*`, `gv_*`, `ppp_web_*`. |
| Cambiar una función o vista que Producción usa | ❌ | Crear `gv_<nombre>` nueva. `create or replace` sobre una compartida está prohibido aunque el resultado parezca idéntico. |
| Trigger sobre una tabla compartida | ❌ **nunca** | Un trigger corre para Producción también. No hay forma de acotarlo. |
| Dropear algo | ❌ salvo que lo hayamos creado nosotros | Y aun así: `grep` en los **dos** repos antes. |

### Chequeo obligatorio antes de tocar cualquier objeto de `public.*`

El repo de Producción está clonado en `/home/user/loekemeyer/produccion-virgilio`
(lectura anónima, ver `add_repo`). Antes de tocar algo:

```bash
grep -rn "NOMBRE_DEL_OBJETO" --include=*.js --include=*.html --include=*.sql \
  /home/user/loekemeyer/produccion-virgilio
```

Cuesta cinco segundos y el 2026-09-04 habría evitado los cuatro cambios de §3 que
violaron la regla.

### Reglas que no están en la frase del dueño pero hacen falta

1. **Toda vista nueva va con `security_invoker = true`.** Sin eso corre como `postgres`
   y saltea la RLS de las tablas de abajo. El 2026-09-04 esto costó una filtración real
   (§4, `vista_pedidos_web_feed`).
2. **RLS prendida por defecto** en cada tabla `GV_*`/`PPP_Web_*` nueva, con policy
   explícita. La anon key es la misma para las dos apps.
3. **Backup antes de cualquier escritura sobre tabla compartida**, a `sql/backups/`
   con nombre `backup_<tabla>_<AAAAMMDD>.sql`. Ya está en el CLAUDE.md; acá se fija el
   destino.
4. **Crons y Edge Functions son globales al proyecto.** Un cron de Gestión lleva prefijo
   `gv_`/`ppp_web_` y no puede tocar los de Producción.
5. **Cada cambio se anota acá el mismo día**, con el impacto medido — no "no debería
   afectar", sino la consulta que lo prueba.

---

## 2. Inventario

### 2.a Objetos que Gestión Virgilio POSEE (los creamos nosotros)

| Objeto | Qué es | Archivo |
|---|---|---|
| `PPP_Web_NP` | Numeración propia `LK 1343` / `CH 7` | `sql/ppp_web_programacion.sql` |
| `PPP_Web_NP_Seed` | Desde qué número arranca cada empresa | idem |
| `PPP_Web_Programacion` | Tanda, zona y fecha de entrega de cada NP web | idem |
| `PPP_Web_Config` | Parámetros del armado de tandas | `sql/ppp_web_tandas.sql` |
| `ppp_web_np_asignar()` | Reparte números, con lock por empresa | `sql/ppp_web_programacion.sql` |
| `ppp_web_prog_touch()` | Auditoría de quién programó y cuándo | idem |
| `ppp_web_resync()` | Reacomoda la programación cuando el pedido cambia | idem §3 |
| `ppp_web_armar_tandas()` | Arma las tandas solo | `sql/ppp_web_tandas.sql` |
| `ppp_web_letra()` · `ppp_web_letra_idx()` · `ppp_web_proxima_letra()` | Código de tanda | idem |
| `GV_Volumen_Articulos` | **Override de m³ de Gestión.** Pisa a `Volumen_Articulos` sólo para nosotros | `sql/gv_overrides.sql` |
| `GV_Zonas_Barrios` | **Override de zona de Gestión** (hoy vacía: el único caso se resolvió corrigiendo la compartida). Queda como mecanismo | idem |
| `gv_zona_de_barrio()` | Resuelve zona: override primero, después la compartida | idem |
| `vista_volumen_articulo_resuelto` | m³ con la "L" resuelta desde el artículo base, superponiendo el override | `sql/volumen_articulo_resuelto.sql` |
| `vista_facturacion_estado` | Corte "esperando confirmación" / "facturado" | `sql/facturacion_estado.sql` |

En el proyecto **LK** (`kwkclwhmoygunqmlegrg`), que Producción **no** usa para esto:
`v_pedidos_web`, `v_pedidos_web_np`, `get_pedidos_web_np_chef()`,
`virgilio_volumen_map()`, foreign table `virgilio.volumen_articulo`.
Ver `sql/pedidos_web_lk.sql`.

### 2.b Objetos de Producción que Gestión SOLO LEE

`PPP_Programacion_Diaria` (sólo para no repetir un código de tanda) ·
`PPP_Base_Pedidos` · `Volumen_Articulos` · `Zonas_Barrios` · `Articulos_Cajas` ·
`Entregas_Virgilio` · `Facturacion_NP` · `isis_export_pedidos` ·
`vista_cruce_facturacion` · `empresa_de_np()` · `_norm_barrio()`.

**Ninguna de estas se escribe.** Si Gestión necesita un valor distinto al de Producción,
va tabla `GV_*` de override (§1).

---

## 3. Changelog

### 2026-09-04 · Sesión "merge del handoff + pipeline de ventas"

Todo lo de este día está en `main`, commits `1d55e01` … `c9973e2`.

#### ✅ Aditivo o propio — cumple la regla

| # | Cambio | Impacto medido |
|---|---|---|
| 1 | `vista_volumen_articulo_resuelto` (nueva) | 0 referencias en Producción |
| 2 | `vista_facturacion_estado` (nueva) | 0 referencias en Producción |
| 3 | `ppp_web_resync()` (nueva) | escribe sólo en `PPP_Web_Programacion` |
| 4 | `ppp_web_armar_tandas()`, `PPP_Web_Config`, helpers (nuevos) | idem |
| 5 | `Zonas_Barrios` **+28 filas** (`insert … do nothing`) | 4 NP de Producción tocadas, y en las 4 la zona nueva (`Super`) **coincide con la que ya traía el Excel** → cero cambio de comportamiento |
| 6 | Revoke de `anon` sobre `vista_pedidos_web_feed`, y después su drop | 0 referencias en Producción |
| 7 | Drop de los esquemas `pipeline` y `fuentes`, servers FDW `lk_feed`/`chef_feed`, y en LK el rol `virgilio_reader` + su vista | 0 referencias en Producción (los hits de "pipeline."/"fuentes." son comentarios y la palabra española) |
| 8 | En LK: split balanceado por m³ y columnas `m3`/`m3_parcial` en `v_pedidos_web_np` y en la RPC de Chef | 0 referencias en Producción |

#### ✅ CORREGIDOS el mismo día — violaban la regla, se hicieron antes de fijarla

Los updates sobre tablas compartidas se **revirtieron** y el criterio de Gestión pasó a
tablas de override propias (`sql/gv_overrides.sql`). Producción quedó exactamente como
estaba; Gestión tiene su fuente canónica.

| # | Qué era | Cómo quedó |
|---|---|---|
| A | `UPDATE` de 54 filas de `Volumen_Articulos` | Revertido. `GV_Volumen_Articulos` (157 filas: 156 códigos con "L" con el m³ de su base + `727E` estimado) y `vista_volumen_articulo_resuelto` superpone override sobre compartida. |
| A' | `UPDATE` de `727E` (0 → 0,0023) — **se me había pasado**, es el mismo caso | Revertido a 0. El 0,0023 vive en el override, marcado como estimado por similitud y no medido. |
| B | `UPDATE` de `v.devoto` en `Zonas_Barrios` | **Resuelto de otra forma, por decisión del dueño: Devoto es Centro para las DOS apps.** No es un override — es corregir una inconsistencia de la tabla compartida, donde las 3 grafías (`devoto`, `villa devoto`, `v.devoto`) se cargaron juntas y sólo la tercera quedó en Oeste. Ahora las tres dicen `Zona 2 - CABA Centro`. El override se borró: ya no hace falta. 0 NP afectadas. |

**Verificado:** en el m³ las dos apps ven cosas distintas a propósito — Gestión ve
`439EL` = 0,0185 y Producción su valor original 0,0561. En la zona **ven lo mismo**,
porque el dueño decidió que Devoto es Centro para las dos. La vista sigue
con 1.482 filas, 0 duplicados y 0 códigos con L que no sigan a su base, y LK las lee por
el FDW: 355 NP con 0 m³ incompleto.

Las **28 filas agregadas a `Zonas_Barrios`** se mantienen: son un `insert`, que la regla
permite, y su impacto medido es cero (las 4 NP que tocan ya traían `Super` del Excel).

#### ✅ C — revertido, y el pipeline nuevo no lo necesita

| # | Cambio | Por qué viola | Impacto medido | Rollback |
|---|---|---|---|---|
| C | `empresa_de_np()`: **create or replace** de una función compartida | Producción la usa (9 referencias) | **0 filas** cambian de clasificación: 0 de 51.395 en `Movimientos_Stock` y 0 de 1.181 en `Facturacion_NP` tienen prefijo web | `sql/empresa_de_np.sql` tiene las dos versiones |

**Resuelto: se revirtió `empresa_de_np` a la regla original de Producción, y NO se creó
`gv_empresa_de_np` porque no tendría uso.**

El dueño lo señaló y tiene razón: la función existe para **adivinar** la empresa de una NP
de ISIS, que no la lleva escrita (9xxxx Loekemeyer / 4xxxx Chef). **Las NP que genera
Gestión ya dicen la empresa en el prefijo** (`LK 1343` / `CH 7`), así que no hay nada que
deducir — cuando Gestión exporte a ISIS, manda la empresa que ya tiene.

Queda una sola punta suelta, a resolver aparte: `trg_normalizar_empresa_stock`, el trigger
de `Movimientos_Stock`, sí la usa para completar la empresa de un movimiento a partir de la
NP referenciada. Se enchufa cuando el stock de los pedidos web entre al circuito. Hoy: 0 de
51.395 filas de `Movimientos_Stock` tienen una NP con prefijo web.

#### Cambios de datos en el proyecto **LK** (padrón de clientes)

| Cambio | Detalle |
|---|---|
| `customer_delivery_addresses.zona_expreso` cargado a 5 clientes | 4114 → `Lujan` · 4274 → `Soldati` · 4275 → `Villa Soldati` · 4278 → `Soldati` · 4279 → `Belgrano`. Salieron de la PPP histórica, no inventados. Producción-Virgilio no usa esa tabla. |

---

## 3.b La salida a ISIS — el formato, que ya estaba decidido

**ISIS es un facturador glorificado.** Gestión arma el pedido —lo parte en NP, lo programa,
lo pickea, lo arma— y **recién después** se lo manda. Lo que viaja es el pedido **ya armado
y listo para facturar**.

Pero por cómo funciona ISIS, **tiene que entrar como si fuera un pedido nuevo, con el mismo
formato que exportan las páginas hoy**. No es un informe de pedido terminado: es un pedido.

### Lo que mandan las páginas hoy (`orders.sheets_payload`, real, 2026-09-04)

```json
{ "mode": "new", "source": "Web", "order_number": "1344",
  "cod_cliente": "288", "sucursal_entrega": "Rivadavia 3663- Mar Del Plata",
  "vend": "7", "condicion_pago": "Pago Contado: 25% Dto", "condicion_pago_code": 8,
  "payment_term": 2, "observaciones": "", "is_promo": false, "extra_discount": 0,
  "order_total": 2532920.54, "credit_limit": 90000000, "deuda": 24921781.21,
  "cliente_nuevo": "", "lc": "OK", "d": "X", "pp": "2",
  "items": [ { "cod_art": "321", "cajas": 6, "uxb": 12, "cod_original": null } ] }
```

**No hay NP en ningún lado.** `order_number` es el id del pedido de la página, no una NP.
La NP la pone ISIS al facturar — ese es todo su trabajo en el régimen nuevo.

### Entonces, la exportación de Gestión

| eje | qué va |
|---|---|
| **Formato** | el de arriba, tal cual. Lo que ISIS ya sabe recibir. |
| **Contenido** | las **cajas ARMADAS**, no las pedidas. El pedido ya pasó por picking y armado; si salió corto, viaja lo que salió. |
| **NP** | **ninguna.** Ni la nuestra ni un placeholder. |

⚠ **`isis_pedido_json` NO sirve para esto y no hay que reusarla.** Esa función arma un
*informe* del pedido terminado (np, tanda, m³, cajas pedidas vs entregadas vs faltantes,
control de neto) con una forma completamente distinta, y además hace `np::bigint` sacando
los no-dígitos — una NP `LK 1343` viajaría como `1343`. La salida de Gestión es un objeto
nuevo, `gv_*`.

### Lo que queda por resolver al construirla

1. **Una NP nuestra = un pedido para ISIS.** Un pedido web partido en 3 NP entra a ISIS
   como 3 pedidos, porque la NP es la unidad que se pickea, se arma y se factura. Confirmar.
2. **Qué va en `order_number`.** El de la página es el id del pedido; con NP partidas hay
   varias por id. Hay que definir qué mandar para que ISIS no las confunda.
3. **Los campos de contexto comercial** (`deuda`, `credit_limit`, `lc`, `order_total`,
   `extra_discount`): la página los calcula al momento de la venta. Hay que ver cuáles
   ISIS realmente usa y cuáles se pueden mandar vacíos.

### El contrato con ISIS quedó escrito — 2026-09-04

`docs/ISIS-API-ESPECIFICACION.md` pasó a **v2.0**. La v1.0 decía lo contrario (ISIS bajaba
"pedidos terminados" identificados por su NP, con `cajas_pedidas` vs `cajas` y `articulo`
vs `articulo_pedido`) y quedó sin efecto. Lo único que se conservó es el **transporte**,
que ya estaba acordado con Sistemas ISIS y es lo que ellos pidieron: ISIS consulta una API
nuestra (Alternativa B del §11 de su informe), que evita montar Windows Server / IIS / IP
pública del lado del depósito. Cambió *qué* viaja, no *cómo*.

Los tres puntos del contrato:

- **El pedido no lleva NP.** El cuerpo es
  `{referencia, empresa, …, pedido:{…}, control:{…}}`, donde `referencia` (`LK 1344`) es la
  clave de la integración —va en la URL y en el listado, **no dentro del pedido**— y no es
  una NP. Cada línea trae un solo `cod_art` y una sola cantidad `cajas`: lo armado.
- **El formato es el del mail de las 12:30, no un canal existente.** Hoy los pedidos web
  llegan a ISIS por un mail que alguien **carga a mano**; no hay entrada automática. Lo que
  se repite es el formato y los campos. Lo que cambia: cuándo se manda (al cerrarse el
  armado, no a las 12:30), por dónde llega (esta API, no un mail) y que las cantidades ya
  vienen firmes.
- **No vuelve nada de ISIS.** Sin acuse, sin NP, sin comprobante, sin CAE. El vínculo
  factura ↔ pedido lo resuelve nuestro parseo (`vista_cruce_facturacion`), que hoy explica
  **735 de 735** NP facturadas con 0 acuses. Eso deja el punto **P3** del informe sin
  objeto. Del lado de ISIS quedan **dos GET de lectura** y nada más.

Artefactos: `docs/API-Virgilio-ISIS-v2.0.pdf` (lo que se le manda a Horacio) y su fuente
`docs/API-Virgilio-ISIS-v2.0.fuente.html` — se regenera con
`chromium --headless --print-to-pdf --no-pdf-header-footer`. El kit de envío (mail + PDF +
WhatsApp con el token) está publicado como artifact y también se actualizó.

⚠ **El código desplegado sigue en la v1.0.** El contrato va adelante; falta reescribir
`isis_pedido_json`, traer los campos comerciales del `sheets_payload` de LK, cambiar la
clave de `isis_export_pedidos` de NP a referencia, **sacar las rutas de acuse y la RPC
`isis_api_acuse`**, y reemplazar el disparador `Facturacion_NP` por el cierre del armado.
Detalle en el anexo técnico de `docs/ISIS-API-ESPECIFICACION.md`.

---

## 3.c Armado automático de tandas — 2026-09-04

`ppp_web_armar_tandas` existía y estaba probada desde antes, pero **no la llamaba
nadie**: 0 referencias en `index.html`, 0 crons. Por eso `PPP_Web_Programacion` tenía
**0 filas con 350 NP ya numeradas** — la cadena se cortaba justo ahí y todo lo de abajo
(picking, armado, facturación, ISIS) estaba en cero por arrastre.

Pedido del dueño: *"para el comienzo de cada día (lunes a viernes no feriado) tiene que
elegir las tandas a armar a ese día"*.

### Lo que se creó (todo NUEVO y con prefijo)

| objeto | qué es |
|---|---|
| `gv_es_dia_habil(date)` | lunes a viernes y no feriado. Lee `planify.feriados` (35 filas, hasta 2027, cron diario ajeno). `SECURITY DEFINER` porque `planify` no está abierto; devuelve un booleano y nada más |
| `gv_ppp_web_barrio_de(text)` | corte del barrio por el último guión. Espejo backend de `pwebBarrioDe()` |
| `gv_ppp_web_zona(ze, loc, dir)` | la cascada `zona_expreso → localidad → dirección` + diccionario. Espejo de `pwebZonaSugerida()` |
| `gv_ppp_web_zona_lote(jsonb)` | la misma cuenta para N filas en una llamada |
| `GV_Tandas_Auto_Log` | bitácora de cada corrida, incluidas las que no hacen nada. RLS: lectura sólo para los tres mails de supervisor |
| `PPP_Web_Config.ventana_dias` | fila nueva (`insert … do nothing`), 30 días |
| Edge Fn `gv-ppp-web-tandas-diarias` | el disparador. `verify_jwt = true` |
| cron `gv-ppp-web-tandas-diarias` | `1 3 * * 1-5` = 00:01 de Argentina. jobid 71. **Apagado el mismo día — ver §3.e** |

### Que no jode a Producción

Grep obligatorio contra `loekemeyer/produccion-virgilio` (HEAD `a7b3368`) **antes** de
tocar nada: `ppp_web_armar_tandas` 0 · `PPP_Web_Programacion` 0 · `PPP_Web_Config` 0 ·
`ppp_web_proxima_letra` 0 · `gv_zona_de_barrio` 0. De lo compartido sólo se **lee**
(`Zonas_Barrios` 18 hits, `planify.feriados` 1). Ni un `create or replace` sobre nada
ajeno, ni un trigger sobre tabla compartida, ni un INSERT contra
`PPP_Programacion_Diaria`.

**`ppp_web_armar_tandas` no se modificó**, aunque es nuestra y el grep da 0: se pensó
agregarle el salto de feriados a la fecha de entrega y no hace falta (el job sólo corre
en día hábil y `dias_hasta_entrega = 0`). Un `create or replace` que no hace falta es
riesgo gratis.

### Dos cosas que aparecieron al construirlo

1. **`ppp_web_armar_tandas` no escribe `PPP_Web_Base`**, que es la foto de artículos que
   después pickea el operario. El front las escribe juntas en `pwebGuardarProg`; el job
   automático la habría dejado afuera y **el operario habría abierto la tanda vacía** —
   el propio front tiene ese error escrito a mano. La escribe ahora la Edge Function.
2. **El barrio se cortaba mal en dos bordes.** La primera versión de
   `gv_ppp_web_barrio_de` usaba `rpos > 1` y no replicaba al front cuando el guión está
   al principio o al final de la cadena. Corregido y probado contra 13 casos.

### Medido, no supuesto

- **Zona:** 340 de 355 NP reales de LK de 30 días (**95,8%**). Las 15 restantes son del
  interior sin `zona_expreso` en el padrón (Santa Cruz, Aguilares, Concepción del
  Uruguay, Río Cuarto) más una fila basura. Es el padrón de LK, no el diccionario.
- **Armado:** 32 NP reales (pedidos 1312-1344) por toda la cadena, en transacción
  revertida. 31 programadas en 13 tandas. Súper solo (4,560 m³), un cliente que pasa el
  tope no se parte (1,375 m³ en 2 NP juntas), 4 clientes chicos en una tanda (0,643 m³),
  Retira junta 2 clientes, ninguna tanda mezcla zonas, la que no tenía zona quedó afuera.
- Después de la prueba: `PPP_Web_Programacion` de vuelta en 0, `PPP_Programacion_Diaria`
  en 182 y sin una sola NP web.

### ⚠ Falta un secreto para que arranque

`GV_LK_SERVICE_KEY` = service_role del proyecto **LK** (`kwkclwhmoygunqmlegrg`), en Edge
Functions → Secrets del proyecto Virgilio. Hace falta porque `v_pedidos_web_np` y
`get_pedidos_web_np_chef` piden `authenticated` — con la anon key dan 401, y así tiene
que seguir: traen razón social, dirección y detalle de pedidos. Hasta que se cargue, el
cron corre y deja una fila `estado='error'` con ese motivo en `GV_Tandas_Auto_Log`.

Detalle completo en `sql/gv_tandas_diarias.sql`.

---

## 3.d La credencial contra LK — 2026-09-04

El armado automático corre en Virgilio y los pedidos viven en **otro proyecto**
(LK, `kwkclwhmoygunqmlegrg`). La `SUPABASE_SERVICE_ROLE_KEY` que la Edge Function
ya tiene abre Virgilio y nada más. Y el camino del front no sirve: entra a LK
canjeando el JWT de la sesión del supervisor por el bridge de `admin-login-otp`
(`pwebLkToken`), y a las 00:01 no hay nadie logueado.

⚠ **Sí, esto lo habíamos cerrado el mismo día.** El rol `virgilio_reader` de LK
se borró junto con su vista `v_virgilio_pedidos_feed` y el FDW. Los motivos eran
buenos (su password había quedado expuesta en un chat, la vista no tenía el corte
en NP ni el m³, y el FDW se midió más lento: 3,16 s contra 2,90 s), pero **era el
único camino de credencial server-side contra LK** y eso no quedó anotado. Lo que
sigue lo reconstruye, apuntando a las vistas correctas.

### El rol `gv_reader` (en LK)

Sólo puede **ejecutar tres funciones**. No tiene `SELECT` sobre ninguna tabla ni
vista. Van por función y no por grant sobre las vistas a propósito:
`v_pedidos_web_np` y `gv_clientes_lk_ch` son `security_invoker`, así que un rol
nuevo chocaría contra la RLS de las tablas de abajo y no vería nada; envueltas en
`SECURITY DEFINER` el permiso pasa a ser el GRANT, que es lo auditable.

| | `gv_reader` | anon key (pública, está en el front) | service key |
|---|---|---|---|
| tablas/vistas que lee | **0** | 192 | todo |
| funciones `SECURITY DEFINER` que alcanza y anon no | **3** (las nuestras) | — | todas |
| superusuario / bypassrls | no | no | sí |
| login con password | no | no | — |

Medido el 2026-09-04, no supuesto. El resto de funciones que alcanza son las que
`anon` ya alcanza con la key pública: no agrega superficie.

Objetos creados en LK: `gv_pedidos_web_np_lk(date)`, `gv_cods_chef_de_lk(text[])`,
`gv_clientes_lk_ch` (vista, 357 pares por CUIT), rol `gv_reader` + grant a
`authenticator`. Más `gv_pedidos_web_np_chef(integer)`, que ya existía.

### Cómo se carga la credencial (sólo panel, sin terminal)

**1.** LK → **Project Settings** → **API Keys** → *Create new secret key*:
nombre `gv_tandas_virgilio`. **El diálogo NO deja elegir rol de Postgres**
(verificado el 2026-09-04): toda secret key bypasea la RLS. Aun así se prefiere
sobre la `service_role` legacy, que tiene el mismo poder pero **no se puede
revocar sola**: para invalidarla hay que rotar el JWT Secret del proyecto, y eso
tumba la anon key y todas las sesiones abiertas del sitio de LK. La
`sb_secret_…` se borra sola y no rompe nada más.

**2.** Virgilio → **Edge Functions** → **Secrets** → *Add new secret*:
`GV_LK_SERVICE_KEY` = la llave del paso 1.

La Edge Function acepta los dos formatos sin recompilar: `authLk()` detecta si
es `sb_secret_…` (va en el header `apikey`) o un JWT (va en `Authorization`, con
la anon key en `apikey`). Pasar al token acotado de `gv_reader` más adelante es
cambiar el valor del secreto, sin tocar código.

> Alternativa sin panel, por si alguna vez hace falta: `tools/gv-token-lk.js`
> firma el token de `gv_reader` con el JWT Secret de LK, que entra por variable
> de entorno y no se guarda en ningún lado. No se puede hacer desde el SQL Editor
> porque Supabase ya **no** expone `app.settings.jwt_secret` a Postgres en este
> proyecto (verificado el 2026-09-04; `pgcrypto` sí está, `pgjwt` no).

La Edge Function acepta **cualquiera de las dos** credenciales sin recompilar (el
token de `gv_reader` o la service key de LK), porque todo va por RPC. El header
`apikey` va siempre con la anon key de LK, que es pública y ya está en el front;
quien decide permisos es el JWT del `Authorization`.

### Para revocarlo

```sql
-- en LK. Corta el acceso al instante, sin tocar nada mas.
revoke gv_reader from authenticator;
```

---

## 3.e Numeración propia de las tandas + cron apagado — 2026-09-04

### ⚠⚠⚠ CUANDO GESTIÓN TOMA CONTROL Y SE VUELVE LA VERSIÓN QUE USAMOS, SEGUIR CON LA NUMERACIÓN QUE DEJÓ VIRGILIO

**Es una sola línea, el día del cambio:**

```sql
-- en VIRGILIO (hrxfctzncixxqmpfhskv)
update public."PPP_Web_Config" set valor_texto = '' where clave = 'tanda_prefijo';
```

Con el prefijo vacío `ppp_web_armar_tandas` vuelve sola a la codificación histórica
`LETRA + NN + LETRA` (`D19J`) y `ppp_web_proxima_letra()` **retoma desde la última letra
que dejó Producción**, porque mira las dos tablas (`PPP_Programacion_Diaria` y
`PPP_Web_Programacion`). No hay nada más que tocar: ni código, ni deploy, ni migración.

**Mientras tanto (hoy, mientras conviven las dos apps):** las tandas que arma Gestión son
**de prueba** y llevan prefijo propio **`GV-`** → `GV-01A`, `GV-02B`. No se confunden con
las de Producción ni le pisan el contador: el prefijo rompe el patrón
`^[A-Z]+[0-9]+[A-Z]+$` que usa `ppp_web_proxima_letra()` para leer la letra, así que las
de prueba quedan fuera de esa cuenta.

Lo que se agregó, todo por la regla del §1 (agregar, no modificar):

| objeto | qué |
|---|---|
| `PPP_Web_Config.valor_texto` | columna **nueva** (`add column if not exists`), nullable, sin default, sin backfill. La tabla es nuestra, igual se respetó la regla |
| `PPP_Web_Config` fila `tanda_prefijo` | `insert … do nothing`, valor `GV-` |
| `ppp_web_armar_tandas` v4 | lee ese parámetro y arma el código con o sin prefijo. Función nuestra, 0 referencias en Producción (grep verificado) |

Probado el 2026-09-04 en transacción revertida, los dos modos:

| modo | códigos | chequeo |
|---|---|---|
| HOY (prueba) | `GV-01A · GV-02A · GV-03A` | ninguno matchea `^[A-Z]+[0-9]+[A-Z]+$` |
| FUTURO (Virgilio) | `E01A · E02A · E03A` | todos matchean; sigue después de la `D` de Producción |

Config intacta después del rollback (`tanda_prefijo` = `GV-`).

### El cron quedó APAGADO a pedido del dueño

```sql
select cron.alter_job(71, active := false);   -- para prenderlo: active := true
```

`jobid 71`, definición **conservada** (no se borró), 0 corridas ejecutadas. Se apaga
porque hasta que Gestión reemplace a Producción las tandas que arma son de prueba y no
tiene sentido que se generen solas todas las madrugadas.

### Auditoría de independencia (lo que pidió el dueño: "chequeá eso")

Medido el 2026-09-04, no supuesto:

- **26 objetos nuestros → 0 referencias** en el repo de Producción (grep sobre `.js`,
  `.html`, `.sql` de `loekemeyer/produccion-virgilio`).
- **0 triggers nuestros** sobre tablas compartidas.
- **1 solo cron** nuestro, con prefijo, y apagado.
- `PPP_Programacion_Diaria` intacta: **182 filas, 0 NP web**.
- La PPP del front de Producción lee `PPP_Programacion_Diaria`; la de Gestión lee
  `PPP_Web_Programacion`. Son tablas distintas: cada app ve su propia programación y por
  eso las tandas de prueba de Gestión **no aparecen** en la pantalla de los operarios.
- Exposición a `anon`: `PPP_Programacion_Diaria`, `PPP_Base_Pedidos`, `Entregas_Virgilio`
  y `Facturacion_NP` ya tenían `SELECT / true` para `anon` desde antes — igual que las
  nuestras. Se deja como está (decisión del dueño). ⚠ Al pasar: `Facturacion_NP` además
  tiene `INSERT`/`UPDATE`/`DELETE` para `anon` con `true`. No es nuestro y no se tocó,
  pero queda anotado.

---

## 3.f El job no podía numerar las NP — 2026-09-04

Salió de **correr el disparador de verdad**, no de leer el código:

```
GV_Tandas_Auto_Log id 2 · estado 'error'
lk:   ppp_web_np_asignar: HTTP 400 "Se necesita sesión para asignar números de NP."
chef: ppp_web_np_asignar: HTTP 400 (idem)
```

`ppp_web_np_asignar` arranca con `if auth.uid() is null then raise`. Ese candado está
bien para el **front** (un supervisor logueado), pero el job entra con la service key y
ahí `auth.uid()` es NULL — **y el cron usa exactamente esa credencial** (jobid 71 va con
la `SUPABASE_SERVICE_ROLE_KEY`). O sea: habría fallado todas las noches, sin numerar una
sola NP y por lo tanto sin armar una sola tanda. Mismo bicho que ya nos había comido con
la RPC de Chef.

Chequeadas las otras cuatro funciones de la cadena (`ppp_web_resync`,
`ppp_web_armar_tandas`, `ppp_web_proxima_letra`, `gv_ppp_web_zona_lote`): ninguna tiene
el gate. Era una sola.

### El arreglo

| objeto | qué |
|---|---|
| `gv_ppp_web_np_asignar(text,jsonb)` | **nuevo**. Tiene la lógica. El candado es el GRANT, no la sesión — que además es lo auditable |
| `ppp_web_np_asignar(text,jsonb)` | queda como la **puerta del front**: mismo gate de sesión de siempre, pero **delega**. Así la numeración vive en un solo lugar y no puede driftear |
| Edge Fn v8 | llama a `gv_ppp_web_np_asignar` |

El front no cambia en nada. Grep previo contra Producción: `ppp_web_np_asignar` **0
referencias**, es nuestra.

| rol | `gv_ppp_web_np_asignar` | `ppp_web_np_asignar` |
|---|---|---|
| `anon` | ❌ | ❌ |
| `authenticated` | ❌ | ✅ (el front, con sesión) |
| `service_role` | ✅ (el job) | ✅ |

### La lógica de numeración, medida

- Un número por `(empresa, order_id, np_idx)` — un pedido web se puede partir en varias NP.
- Correlativo **por empresa** desde `PPP_Web_NP_Seed`: LK `1343` (donde quedó la
  numeración a mano), Chef `1`.
- Idempotente (`on conflict do nothing`) y serializado con advisory lock por empresa.
- La NP viaja etiquetada `LK 1343`: `empresaDeNp` resuelve la empresa por el número
  (>90000 = LK) y una NP web de 4 dígitos caería en Chef.

Medido el 2026-09-04: LK **357 asignadas, 1343→1699, 0 duplicados, 0 huecos**; Chef 0.
Sin choque con Producción (sus NP numéricas arrancan en 44361; en el rango 1..2000 hay 0).
Llamada como el job (`set local role service_role`, `auth.uid()` NULL) sobre pares que ya
tenían número: devolvió `1343,1344,1345` y **no escribió una fila**.

### ⚠ Un flag de seguridad que se ignoraba en silencio

La prueba se lanzó con `{"dry":true}` en el **body**, pero la Edge Function leía los flags
**sólo del query string** (`?dry=1`). No dio error: los ignoró y corrió por el camino
**real** creyendo uno que era una prueba. No llegó a escribir nada porque murió en la
numeración, pero el próximo caso podía no tener esa suerte.

Arreglado en v8: `flag()` mira query **y** body. Verificado sin escribir nada — se mandó
`{"dry":true,"fecha":"2026-09-06"}` (sábado): contestó por el camino síncrono
(`salteada`, no `encolada`) y `GV_Tandas_Auto_Log` quedó en 2 filas, porque el log de
'salteada' está detrás de `if (!dry)`.

### ⚠⚠⚠ Y después: la numeración se APAGÓ. Arranca el día del cambio, no antes

Regla del dueño, el mismo día: *"actualmente Producción Virgilio usa las NP que manda
ISIS a la hoja de cálculos. Cuando Gestión Virgilio tome control, va a asignarle la
numeración nuestra a los pedidos que estén pendientes y a los que vayan cayendo. Recién
ahí que empiece"*.

Había 357 NP de LK (1343→1699). **No eran pedidos de Producción**: 0 en
`PPP_Programacion_Diaria`, 0 en `Facturacion_NP`, 0 en `Registros_Produccion_Virgilio`.
Se habían creado los días **3 y 4 de septiembre**, en estas sesiones, porque la pantalla
de la PPP Web llama a `pwebNumerar()` al abrirse y **numera todo lo que muestra, sola**.

Por eso no alcanzaba con borrarlas: volvían la próxima vez que alguien abriera la
pantalla. Va con interruptor:

| objeto | qué |
|---|---|
| `PPP_Web_Config.numeracion_activa` | fila nueva (`insert … do nothing`), valor **0** |
| gate en `gv_ppp_web_np_asignar` | corta con un mensaje explícito. Como la del front **delega** en ésta, el interruptor apaga las dos de una sola vez |
| `PPP_Web_NP` | **vaciada** (357 → 0). Backup: `sql/backups/backup_PPP_Web_NP_20260904.sql` |

Probado, las dos puertas: la del job cortó por el interruptor, y la del front cortó por
el interruptor **también con sesión viva** (`set local request.jwt.claims`) — o sea el
candado nuevo no queda tapado por el viejo gate de sesión.

**El día del cambio son DOS líneas, no una** (la otra es la de las tandas, §3.e):

```sql
update public."PPP_Web_Config" set valor_texto = '' where clave = 'tanda_prefijo';
update public."PPP_Web_Config" set valor       = 1  where clave = 'numeracion_activa';
```

### De qué número arranca: 00001, las dos empresas

Decidido por el dueño el mismo día. `PPP_Web_NP_Seed` quedó en **lk 1 · chef 1**, así que
el primer pedido que numere Gestión va a ser **`LK 00001`** / **`CH 00001`**. El `1343`
que tenía LK era arbitrario (se había elegido para parecerse al número de pedido de la
página) y se descartó. Sin choque con Producción: sus NP son de 5 dígitos desde 44361.

### La etiqueta: `LK 00001` — prefijo + espacio + 5 dígitos

Fuente de verdad en el backend, **`gv_ppp_web_np_label(empresa, np)`**. El front
(`pwebNpLabel`) y la Edge Function (`npLabel`) la duplican **sólo como optimización de
UX**; si cambia el formato, se cambia primero en Supabase. Verificado que las tres dan lo
mismo en 6 casos.

El prefijo no es cosmético: `empresaDeNp` resuelve la empresa por el número (>90000 = LK)
y una NP web de pocos dígitos caería en Chef, mandando a buscar un pedido de Loekemeyer al
sector equivocado.

⚠ **`lpad` trunca.** `lpad('100000',5,'0')` devuelve `'10000'` — que es la etiqueta de la
NP 10000. Sin guarda, las NP 10000, 100000 y 100001 compartirían etiqueta, y como la
etiqueta *es* la NP que viaja por picking, armado y facturación (`PPP_Web_Base` está
indexada por `np_label`), el operario abriría una tanda con los artículos de tres pedidos
mezclados, en silencio. Con la guarda, pasado 99999 la etiqueta crece (`LK 100000`).
A 4.300 NP al año son unos 23 años; no es un incendio, es una mina enterrada, y la guarda
sale gratis.

### Estado después de esto

`PPP_Web_NP` **0** · `PPP_Web_Programacion` **0** · `PPP_Web_Base` **0** ·
`PPP_Programacion_Diaria` **182** (Producción intacta). Nada corrió de punta a punta, y
ahora tampoco puede hasta que se prenda la numeración.

Detalle y SQL en `sql/gv_tandas_diarias.sql`.

---

## 3.g El freno de "facturado = congelado" no frenaba nada — 2026-09-04

`ppp_web_resync` vuelve a mirar el pedido y actualiza la foto (m³, líneas, cajas) cuando
el cliente lo edita en la página después de que lo programamos. No toca la tanda, la zona
ni la fecha: eso lo decidió una persona. Y **no debe tocar un pedido ya facturado**.

Ese último freno estaba roto:

```sql
join public."Facturacion_NP" f on f.np::text = g2.np::text   -- ❌
```

| lado | qué tiene |
|---|---|
| `PPP_Web_Programacion.np` | **integer** → `1`, `2`, `3` |
| `Facturacion_NP.np` | **text** → `'97500'`, `'44537'` |
| la NP web cuando llegue ahí | **`'LK 00001'`** — la etiqueta, que es lo que viaja por el circuito |

Comparaba `'1'` contra `'LK 00001'`: **no coincidía nunca**. No era inerte por falta de
datos —así lo decía el comentario del repo, y estaba mal— sino **por construcción**: el
día que se conectara la facturación de NP web habría seguido sin frenar.

Y el bug espejo: `g2.np::text` de la NP 44537 da `'44537'`, que **es una NP real de
Producción**. Medido: las **1.187 filas** de `Facturacion_NP` son dígitos pelados, o sea
las 1.187 eran falsos positivos posibles. Al llegar nuestro contador ahí, el freno se
dispararía al revés y saltearía un pedido nuestro creyéndolo facturado.

**Arreglado apareando por la etiqueta**, que lleva prefijo y por eso no se puede confundir
con una NP de ISIS:

```sql
join public."Facturacion_NP" f on f.np = public.gv_ppp_web_np_label(p_empresa, g2.np)
```

Verificado **sin tocar `Facturacion_NP`** (es compartida, sólo se lee): 0 de sus 1.187
filas tienen prefijo `LK `/`CH ` → el choque es imposible por construcción; y
`gv_ppp_web_np_label('lk', 44537)` ≠ `'44537'`. `ppp_web_resync` es nuestra (0 referencias
en Producción).

⚠ **Queda enganchado con el pendiente #4:** cuando se construya la facturación de NP web,
tiene que escribir en `Facturacion_NP` con la **etiqueta** (`LK 00001`), no con el número
pelado. Si escribe el número pelado, el freno vuelve a no frenar.

⚠ **Y del lado del cliente el hueco sigue abierto:** la página lo deja editar un pedido ya
facturado y el cambio se pierde en silencio, sin avisarle. Anotado como idea **8743**.

---

## 3.h La cañería de los AGREGADOS al pedido — 2026-09-04

Pedido del dueño: en **loekemeyer.com** y **chefsrl.com** el cliente va a poder modificar
un pedido ya mandado — **sólo agregar productos, nunca sacar**. El front de esas páginas se
hace después; esto es la cañería del lado nuestro.

> *"Máxima flexibilidad para el cliente es el objetivo. Si el pedido del cliente ya se
> encuentra en picking, armado o está armado pendiente de facturar y el cliente agrega
> algo, el sistema debería reconocerlo y ponerlo primero en la lista de prioridades para
> ser pickeado y armado, con una alerta en el monitor: ESTO ES UN AGREGADO AL PEDIDO XXX Y
> SALEN JUNTOS, ARMENLO YA. Sería una NP aparte obviamente."*

### Lo que se construyó

| objeto | qué |
|---|---|
| `PPP_Web_Programacion` + 4 columnas | `es_agregado`, `agregado_a_np` (el "XXX" del cartel), `agregado_en`, `prioridad`. Tabla nuestra, estaba en 0 filas |
| vista **`gv_ppp_web_estado`** | en qué punto del circuito está cada NP web. `security_invoker = true` |
| `ppp_web_resync` | clasifica el agregado y lo prioriza |
| front v12.79 | el cartel rojo en el monitor **y en cada paso del picking** |

**El estado no es una columna que haya que mantener**: sale de los eventos que los
operarios ya emiten (`EP`/`TP`/`AP`/`TAP`, por tanda) más `Facturacion_NP` (por NP). Así no
hace falta ningún trigger sobre tabla compartida, que además está prohibido.

```
sin_programar → programado → en_picking → pickeado → en_armado → armado → facturado
```

Y tres columnas que son las que va a leer la página del cliente:

| | |
|---|---|
| `puede_agregar` | true **hasta que se factura** → máxima flexibilidad |
| `puede_quitar` | **siempre false** → la página sólo suma |
| `agregado_seria_urgente` | true si la tanda ya arrancó → el agregado va urgente |

⚠ `agregado_seria_urgente` mira **cualquier** evento, no sólo el `EP`: hay tandas reales
con `AP` y `TAP` y **sin `EP` registrado** (`C33C`). Atándolo al EP, un agregado sobre una
tanda que ya se está armando no se marcaba urgente. Salió de la prueba, no de leer.

### Cómo se comporta resync ahora

La NP nueva entra a la **misma tanda** que sus hermanas — tienen que **salir juntos**. Si
esa tanda ya está en marcha, además se marca `es_agregado`, se guarda a qué NP se le
agregó y se le pone `prioridad = 100`.

⚠ **Y ya no borra si la tanda está en marcha.** La página sólo deja agregar, así que un
pedido que se achica ahí es una edición desde otro lado; borrar una NP que el operario ya
tiene pickeada en la mesa desincroniza el sistema con la realidad física, en silencio.

### Probado contra tandas REALES de Producción

Se metieron filas de mentira en `PPP_Web_Programacion` (nuestra, estaba vacía) apuntando a
tandas reales, así el estado sale de eventos reales. **No se tocó ninguna tabla
compartida.** Borradas después; verificado: 0 filas, Producción en 182, ni un evento
inventado.

| caso | resultado |
|---|---|
| `GV-99Z` sin eventos | `programado` · urgente **false** |
| `C62A` (EP) | `en_picking` · urgente **true** |
| `C34B` (EP+TP) | `pickeado` · urgente **true** |
| `C33C` (AP+TAP) | `armado` · urgente **true** |
| agrega, tanda en marcha | **`agregado_urgente`** — prio 100, `agregado_a_np=2` → cartel "LK 00002" |
| agrega, tanda sin empezar | `agregada_a_tanda` — normal, prio 0 |
| achica, tanda en marcha | **no borra nada** |
| achica, tanda sin empezar | `borrada` |

El branch `facturado` de la vista **no se pudo probar con datos**: haría falta una fila en
`Facturacion_NP`, que es compartida y no se toca. Queda verificado por construcción (mismo
apareo por etiqueta del §3.g, medido ahí).

### Lo que FALTA para que esto sirva de verdad

1. **El front de las páginas** (`PaginaLK` y el de Chef): dejar agregar, mostrar el estado
   y bloquear cuando `puede_agregar` es false. Es la idea **8743**.
   → **LK hecho el 2026-09-04** (repo `pagina-LK-copia` v2.3.300): el módulo ya existía
   pero **borraba y reinsertaba** los ítems, o sea que `puede_quitar = false` era una
   declaración que nadie hacía cumplir. Ahora el candado vive en la RPC
   `edit_order_fast` del **proyecto LK** (no en éste): para cada producto que el pedido
   ya tenía, lo que llega tiene que traer al menos las mismas cajas. Detalle, pruebas y
   rollback en `docs/PENDIENTES-PIPELINE-GESTION.md` §4990.
   ⚠ **Chef NO es el mismo caso.** Revisado el repo `paginach` (HEAD `67870b9`): **no
   tiene el módulo "Editar pedidos"** — 0 apariciones de `editOrder` / `edit_order_fast`,
   y el historial sólo ofrece "Descargar" y "Repetir". El agujero que se tapó en LK no
   existe ahí; lo que falta es **construir** el módulo, RPC incluida, y su proyecto
   (`nkhzocgdpwtgrmwleihr`) es de otra organización, sin acceso desde acá.
   ⚠ **Mostrar el estado sigue abierto**: la página habla con LK y `gv_ppp_web_estado`
   vive acá. Decisión del dueño: espejo **Virgilio → LK por FDW**, el mismo patrón que
   `lk_pedidos_match` pero al revés. Sin construir.
   💡 Pero **el aterrizaje ya existe en las dos páginas**: la tabla `order_tracking`
   (`np_number`, `status`, `fecha_entrega`) con un stepper de 3 pasos
   *Recibido → Programado → Entregado* ya dibujado en el historial del cliente. El
   espejo puede alimentar eso en vez de inventar tabla y UI nuevas.
2. ~~**Que la facturación de NP web escriba en `Facturacion_NP` con la etiqueta**~~ **HECHO —
   v12.86.** Ya lo hacía: el tilde toma `np` del mapa de tandas, que para las web es la
   etiqueta. Lo que faltaba era que la NP **apareciera**: `facFetchArmadosEventos`
   descartaba toda NP no numérica (`/^\d+$/`), así que el TAP de una `LK 01344` no
   contaba como armada y `facRender` no la dibujaba. Arreglado, más `pkNpEsLoeke` y
   `_facXlsEmpresa` (miraban dígitos: la web de Chef caía en LK), y
   `stockSalidaFacturadoNP` ahora manda `empresa` explícita para las web — porque el
   trigger `zz_normalizar_empresa`, sin ella, deriva de los dígitos del NP en el `ref`
   y `empresa_de_np('01344')` = **`CH`** (medido). Las de ISIS no cambian.
   ⚠ **Queda un hueco del lado servidor, a propósito sin tocar:** el `picking` y el
   `separado` de stock los escribe el backend (trigger de `Entregas_Virgilio` + cron), y
   ahí la empresa sale de `empresa_de_np`, que no entiende la etiqueta. Sólo pesa en
   los 4 códigos duales (`437E/438E/439E/809E`). Arreglarlo es un `create or replace`
   de una función de Producción → decisión del dueño. Test: `tests/pweb-facturacion.cjs`.
3. ~~**El picking todavía no ordena por `prioridad`.**~~ **HECHO — v12.85, ver abajo.**
4. Nada de esto corrió con datos reales, porque la numeración está apagada.

### El picking ya ordena por `prioridad` — v12.85 (idea 4990, punto 2)

La columna se llenaba desde v12.79 y el cartel rojo se veía, pero **la lista de tandas del
celular seguía ordenada por fecha de entrega y después alfabético**. Una tanda con un
agregado urgente para el jueves quedaba debajo de todas las del martes y el miércoles: en
la práctica, invisible — lo contrario de *"ARMENLO YA"*.

| dónde | qué cambió |
|---|---|
| `mergeMonitorPppWeb` | la tanda hereda la prioridad **más alta** de sus NP (una sola NP en 100 sube la tanda entera) |
| `getPppTandasForOperator` | arrastra `prioridad` y `agregados` hasta la lista (antes tiraba todo menos código y fecha) |
| `populateTandasList` | las de `prioridad > 0` salen del agrupado por fecha y se dibujan en un bloque rojo **arriba de todo**, con a qué pedido se agregó cada una |

**Se saltea el orden por fecha a propósito**, no queda primera dentro de su día: el día de
esa tanda puede estar tres grupos más abajo. Es lo que pidió el dueño —*"ponerlo primero en
la lista de prioridades para ser pickeado y armado […] ARMENLO YA"*—.

**Es aditivo:** las tandas de ISIS no tienen la columna, quedan en `prioridad = 0` y en el
orden de siempre. Sin ninguna fila priorizada la lista se dibuja **exactamente** como antes,
sin bloque rojo. Regresión: `tests/pk-prioridad-agregado.cjs` (14 chequeos, carga el
`index.html` real; incluye el caso "sin prioridad no cambia nada").

⚠ Sigue sin correr con datos reales: `PPP_Web_Programacion` está vacía y la numeración
apagada.

---

## 3.i Sólo zona 1 y zona 2 se programan solas — 2026-09-04

> **Actualización 2026-09-05 (v13.07, §3.y):** `zonas_automaticas = '1,2,3'` — la zona 3 también
> se programa sola (dueño: *"sí, 1, 2 y 3 automáticas"*). Y las tandas ya no se arman por grupo de
> zona sino por sector + vecinos (`GV_Sectores*`), con interruptor `sectores_activos`.

Regla del dueño: *"para el armado de tandas y programación, que sólo los pedidos de zona 1
y zona 2 sean automáticamente programados, el resto tienen que ser programados
manualmente"*.

| objeto | qué |
|---|---|
| `PPP_Web_Config.zonas_automaticas` | fila nueva (`insert … do nothing`), `valor_texto = '1,2'` |
| `gv_ppp_web_zona_automatica(text)` | el helper, separado para poder probarlo suelto y para que el front pueda pintar distinto lo que va a mano |
| `ppp_web_armar_tandas` | un `delete` más sobre la tabla temporal, antes de repartir tandas |

Va por config y no hardcodeado: sumar una zona es un `update`, sin tocar código ni
redeployar.

```sql
update public."PPP_Web_Config" set valor_texto = '1,2,3' where clave = 'zonas_automaticas';
```

**Lo que queda afuera no se pierde ni se marca:** simplemente no recibe tanda, o sea ni
siquiera entra a `PPP_Web_Programacion`. Es exactamente como ya se ve un pedido pendiente
en la pantalla de la PPP Web. Y cada corrida los vuelve a mirar, así que el día que se
agregue la zona entran solos.

### Probado

El helper, contra los valores de zona que existen de verdad:

| entra solo | va a mano |
|---|---|
| `Zona 1` · `Zona 2` · `Zona1` (sin espacio) | `Zona 3` · `Zona 6` · `Zona 7` · **`Zona 10`** · `Retira` · `Super` · `Expo` · `(sin zona)` · `''` · `null` |

⚠ `Zona 10` da **no**, no se confunde con la 1: el capture group toma `'10'` entero.

El armado completo, con 8 pedidos de todas las zonas (filas de mentira, borradas después —
`PPP_Web_Programacion` volvió a 0 y Producción quedó en 182):

| | |
|---|---|
| Zona 1, 2 clientes | → `GV-01A` (0,550 m³) |
| Zona 2, 1 cliente | → `GV-02A` (0,400 m³) |
| Zona 3 · 6 · 10 · Retira · Súper | → **sin fila en `PPP_Web_Programacion`** |

Los 5 que van a mano no quedaron a medias ni con una tanda vacía: no existen en la
programación. Y las zonas 1 y 2 fueron a tandas **separadas**, que es la regla de siempre
(sólo se juntan los pares definidos: 2+3 y 6+7).

⚠ Detalle cosmético: la zona 2 se agrupa como `'Zonas 2+3'` y esa regla no cambió, así que
con la 3 fuera del automático ese grupo queda con zona 2 sola y el resumen igual dice
"Zonas 2+3". Es sólo la etiqueta del resumen; la columna `zona` de cada NP guarda la zona
real.

### ⚠ Falta definir: cómo se programan a mano

Hoy la pantalla de la PPP Web ya los muestra sin tanda y un supervisor los puede programar
ahí, pero **no hay nada que los destaque** como "estos van a mano" — se mezclan con los que
todavía no llegaron a su turno. Lo dijo el dueño: *"ahora vemos bien cómo"*.

---

## 3.j Solapa "A Programar": armado manual de tandas — 2026-09-04

Rediseño de la solapa **A Programar** de la PPP (las 6 solapas ya existían). El dueño
pasó el boceto del front y pidió que el backend se definiera acá.

```
┌─ NPs ──────┐   ┌─ Tanda ────┐   ┌─ Calendario ──────────┐
│ tarjeta ▾  │   │  F57A  ⚠2  │   │  ◀  Sep 2026  ▶       │
│ tarjeta ▾  │ → │            │ → │  Do Lu Ma Mi Ju Vi Sá │
│ tarjeta ▾  │   │  m³: 0,55  │   │   ○  ○  ○  ○  ○  ○  ○ │
└────────────┘   └────────────┘   └───────────────────────┘
```

Decisiones del dueño: trabaja sobre las **NP web de LK y Chef**; **varias tandas en
paralelo** con un botón "+"; y las reglas de negocio **no bloquean** — ponen un **badge**
al lado del código de la tanda.

### El problema de fondo

Hoy una tanda **sólo existe** cuando ya está escrita en `PPP_Web_Programacion` con su
código. Ese front necesita una tanda que exista **mientras se arma**: sin fecha y sin que
la vea nadie del depósito. Ese estado no existía.

⚠ **Por qué tablas propias y no `fecha_entrega = null`:** `mergeMonitorPppWeb` lee
`PPP_Web_Programacion` filtrando **sólo** `tanda=not.is.null`. Un borrador guardado ahí
caería en el celular del operario apenas se arrastra la primera NP.

| objeto | qué |
|---|---|
| `PPP_Web_Tandas` | cabecera: `codigo`, `estado` (borrador/programada/descartada), `fecha_entrega`, quién y cuándo |
| `PPP_Web_Tanda_Items` | qué NP tiene adentro + foto de `np · np_total · zona · cliente · m³ · fecha_recep` |
| `gv_ppp_web_tandas_abiertas` | la vista que dibuja las cajas del medio, con `n_avisos` para el badge |
| `gv_ppp_web_tanda_avisos` | los 6 avisos |
| `gv_ppp_web_pedido_bloques` | dónde está cada bloque de un pedido |
| `gv_ppp_web_tanda_nueva/_agregar/_sacar/_descartar/_programar` | las acciones |
| `gv_ppp_web_calendario` | lo que va adentro de cada circulito |
| `gv_ppp_web_codigo_tomado` · `gv_ppp_web_tanda_codigo_nuevo` | los códigos |

⚠ Una NP **no puede estar en dos tandas**: unique sobre `(empresa, order_id, np_idx)`. Dos
supervisores armando al mismo tiempo no se pisan el mismo pedido.

### La unidad de arrastre es el PEDIDO, no la NP

La columna izquierda lista **pedidos** (un `order_id` por tarjeta). Se arrastra el pedido
entero, la NP se numera al programar, y el corte en bloques ya viene hecho de arriba.

Queda escrito porque en el camino se discutió al revés y la conclusión del dueño es la que
vale: *"si me arrastro el pedido entero de un cliente a la tanda, ahí se le asigna nota de
pedido y ahí se parte; de todas formas un pedido de un mismo cliente no se puede partir en
diferentes tandas"*.

**El corte en 18/15 ya existía**, río arriba, en la vista `v_pedidos_web_np` de LK: 18
líneas para LK, 15 para Chef, `n_tramos = ceil(líneas/cap)`, repartidas en **serpentina**
(ordenadas por m³, yendo y viniendo) para que los bloques queden parejos en volumen. **No
se tocó**: es de LK.

**Lo que sí faltaba:** la vista calculaba `n_tramos` y **no lo devolvía**. Sin ese dato la
tarjeta del pedido no puede decir *"esto va a salir en 3 NP"*, que es información que el
supervisor necesita para decidir. Ahora `gv_pedidos_web_np_lk` y `gv_pedidos_web_np_chef`
devuelven `np_total` (agregar una columna al `RETURNS TABLE` obliga a DROP + CREATE; son
nuestras y el cron está apagado), viaja hasta `PPP_Web_Tanda_Items` y
`PPP_Web_Programacion`, y `_agregar` acepta el pedido entero como array.

Cuánto pesa, medido sobre 30 días reales:

| | NP de pedidos partidos | pedidos partidos | máx bloques |
|---|---|---|---|
| LK | **242 de 364 (66%)** | 99 de 221 | 6 |
| Chef | **23 de 38 (60%)** | 11 | — |

El pedido partido es la norma, no la excepción.

**El aviso `pedido_partido` queda como red de seguridad.** Con la unidad de arrastre en el
pedido no debería poder pasar; salta si una tanda igual termina con menos bloques de los
que tiene el pedido, y dice dónde están los otros (`gv_ppp_web_pedido_bloques`). Cuesta
nada y cubre el día que el front mande un pedido a medias, o que aparezca un bloque nuevo
después (ver los agregados, §3.h).

### Los 6 avisos (badge, no bloqueo)

`pedido_partido` · `zonas_mezcladas` · `sin_zona` · `cliente_va_solo` · `super_mezclado` ·
`pasa_tope_mezcla`.

La mezcla de **empresas** no está en la lista a propósito: `empresa` es parte de la clave
de la tanda, así que LK y CH no se pueden mezclar ni queriendo. Esa regla la garantiza la
estructura, no un chequeo.

### ⚠⚠ La NP se numera al PROGRAMAR, y recién ahí

Salió de la prueba: `PPP_Web_Base.np_label` es `NOT NULL` y la etiqueta se arma con el
número, así que **sin numerar el operario no puede ni abrir la tanda**.

Y es el momento correcto: una NP se numera cuando la tanda se programa, que es cuando el
pedido se vuelve real para el depósito — no al abrir una pantalla, que es lo que hacía
`pwebNumerar()` y por lo que aparecieron 357 NP de prueba (§3.f).

Como llama a `gv_ppp_web_np_asignar`, hereda su interruptor: **hoy, con la numeración
apagada, programar corta** con el mensaje correcto. O sea este módulo no se puede usar de
verdad hasta que se prenda la numeración. Es una decisión, no un bug.

### ⚠ Bug que esto destapó y arregla

`ppp_web_proxima_letra()` sólo miraba las dos tablas de programación. Un código reservado
en un borrador era **invisible**, así que el job automático podía emitir **el mismo
código**. Ahora mira los borradores, y las dos vías consultan `gv_ppp_web_codigo_tomado`
antes de emitir.

### Probado de punta a punta

| paso | resultado |
|---|---|
| "+" dos veces | `GV-01A` y `GV-01B` en paralelo |
| 2 NP del mismo cliente, zona 3 | 0,500 m³ · **0 avisos** |
| + 1 NP de otro cliente, zona 6 | 1,400 m³ · **2 avisos** (mezcla zonas + pasa el tope) |
| la misma NP a la otra tanda | *"Esa NP ya está en otra tanda en armado"* |
| la red: sólo el bloque 1 del pedido real 1117 (3 bloques) | *"entran 1 de 3 bloques. Los otros siguen sin programar"* |
| el bloque 2 en la otra tanda | **las dos** se marcan y se nombran entre sí |
| **el pedido 1117 entero de una** (el uso normal) | 3 NP · 0,367 m³ · **0 avisos** |
| programar `GV-01A` al 09/09 | 2 NP · 0,500 m³ · 3 líneas. NP `LK 00001`/`LK 00002`. El art 027 venía 8 + 2 → quedó en **10 cajas** |
| calendario del 09/09 | 1 tanda · 2 NP · 0,500 m³ · restan 4,500 |
| con la numeración apagada | corta con el mensaje de la numeración |

El camino feliz se probó prendiendo y apagando la numeración **dentro de una sola
transacción**, para no dejar el interruptor abierto ni un segundo. Todo borrado después:
las 5 tablas en 0 y `PPP_Programacion_Diaria` en 182.

### El front — v12.80

Ya está. Tres columnas, arrastrar y soltar, el "+" y el badge.

- **Se intercepta arriba de todo** en `pppRenderProg`: el módulo trabaja sobre pedidos web
  y no puede depender de que se haya importado una PPP de ISIS — más abajo hay un
  `if (!all.length) return` que lo dejaría afuera para siempre. Por eso la barra de solapas
  se extrajo a `pppTabsHtml()`.
- **La izquierda lista pedidos**, no NP: se agrupan por `order_id` en el front y `np_total`
  se cuenta ahí mismo (la vista de LK no lo devuelve; sí lo hacen nuestras RPC, que usa el
  job). La tarjeta dice *"sale en 3 NP"* y se expande a los bloques y sus artículos.
- **No llama a `pwebNumerar()`.** Ésa es la que numeraba todo con sólo abrir una pantalla
  y está apagada a propósito; acá el número se asigna al programar.
- **Al soltar un pedido viajan todos sus bloques** en una sola llamada.
- Selector **Loekemeyer / Chef**: una tanda pertenece a una empresa.
- Antes de programar una tanda con avisos, pide confirmación mostrándolos.

**v12.84 — el calendario pasó a ser una LISTA de días.** Pedido del dueño. Arranca **hoy**
y va para adelante (no hay navegación hacia atrás: siempre se programa a futuro), con
"Ver más días" para estirar el horizonte. Cada día muestra los m³ ya programados contra el
cupo, con barra de progreso y cuántas tandas tiene. **Un día que llegó al límite, o que no
es hábil, se pinta gris y NO acepta que le suelten una tanda** — no ofrece algo que el
backend después va a rechazar.

También v12.84: el arrastre da feedback. Mientras dura el gesto el `<body>` lleva una
clase y el CSS **ilumina sólo los destinos que sirven** (las tandas cuando se arrastra un
pedido, los días cuando se arrastra una tanda) y apaga el resto; la tarjeta que se arrastra
se atenúa, el destino bajo el cursor se resalta, y al soltar hay un pulso. El arrastre **no
re-dibuja**: prende y apaga clases sobre el DOM que ya está, porque re-renderizar en
`dragover` le saca al navegador el elemento que está arrastrando y corta el gesto. Además
se conserva el scroll al re-dibujar: sacar un pedido ya no te manda al principio de una
lista de 218.

⚠ **La app tiene un `button { width:100% }` global.** Sin pisarlo, el "↩" de sacar un
pedido medía **293px** y aplastaba el nombre del cliente a 107px ("Messina Herma…" con
380px libres al lado). Se resetea para todo el módulo. El test lo **mide**, no lo mira:
en el HTML eso no se ve.

Regresión: `tests/apr-programar.cjs` (26 chequeos, carga el `index.html` real). Cubre el
badge, el pedido a medias, la lista de días (que el cerrado no acepte drop y el abierto
sí), el error en rojo, los anchos reales, y que un pedido sin razón social ni m³ no rompa
el dibujo. Más `tests/pweb-lk-token.cjs`. Verdes junto con `smoke`, `ppp-errores`,
`pweb-barrio-zona`, `pweb-en-ppp`, `ppp-chk-gondola` y `checkhtml`.

### Lo que falta

1. **Programar no funciona hasta que se prenda la numeración.** A propósito: corta con el
   mensaje correcto. Es lo único que separa a este módulo de estar operativo.
2. La lista de la izquierda sale en vivo de LK/Chef con el bridge del supervisor; sin
   sesión no carga.

---

## 3.k Controlado → Pedidos Entregados, también para las NP web — 2026-09-04

Regla del dueño: *"si el pedido ya fue controlado, automáticamente tendría que ir a Pedidos
Entregados. No tiene que haber más complejidad que eso."*

**Ya pasaba para las NP de ISIS.** Un pedido está *confirmado* si tiene `CRN` (Control
Remitos, texto `NP|TANDA`, mirado 60 días para atrás) **o** figura en `PPP_Entregados_Meta`
(el espejo del Sheet de ISIS, la fuente durable). `_pppConfirmadas()` junta las dos y parte
`vista_ppp_pedidos_entregados` en *entregados* / *en viaje*.

**Lo que fallaba para las web:** `PPP_Entregados_Meta` se **trunca cada 30 min** con lo que
baja del Sheet (`sync_ppp_entregados_meta`, truncate + insert). Una NP web no existe ahí ni
va a existir → a los 60 días del CRN dejaba de estar confirmada y pasaba a *en viaje* para
siempre.

**La solución, la más chica:** no hace falta tabla nueva. El CRN de una NP web **ya se
emite con la etiqueta** (`"LK 01344|GV-02A"`, `crSendDetail`) y `Registros_Produccion_Virgilio`
conserva todo (CRN desde el 2026-06-24, 821 filas, sin poda).

| objeto | qué |
|---|---|
| vista **`gv_ppp_web_entregados`** | los CRN cuyo NP es una etiqueta (`~* '^\s*(LK\|CH)\s+\d+'`, sin legajos de prueba), cruzados con `PPP_Web_Programacion` → `empresa, np, np_label, tanda, cod_cliente, razon_social, m3, fecha_entrega, controlado_at, n_crn`. `security_invoker = true`. `sql/gv_ppp_web_entregados.sql` |
| front v12.87 | `pppRefreshMetaEntSet` y `pppRefreshEntregadosFull` la suman a lo de ISIS, en `try/catch`: si falla, ISIS queda igual |

`vista_ppp_pedidos_entregados` **ya traía las web**: sale de `Facturacion_NP` + `Facturacion_Cierres`
con joins por texto, sin ningún cast numérico. No se tocó.

**Medido:** grep en Producción = 0 usos · vista creada con `security_invoker=true` · **0 filas
hoy** (no hay NP web con CRN: numeración apagada) · `Registros` intacto (29.228 filas) · `anon`
sólo `SELECT`. Regresión: `tests/pweb-entregados.cjs` (13 chequeos, incluido "si la vista
falla, ISIS sigue igual").

**Rollback:** `drop view public.gv_ppp_web_entregados;` y sacar las dos lecturas del front.

---

## 3.l Pendiente = NO enviado a compras, y el checklist del día del cambio — 2026-09-04

Pedido del dueño: *"fijate la lógica de lo que había antes de lo de la numeración, a ver si
ya la dejamos andando todo entero"*. Se revisó pieza por pieza, **midiendo**, y apareció una
cosa que había que arreglar antes de prender nada.

### Lo que se verificó

| pieza | estado medido |
|---|---|
| `numeracion_activa` | `0` · `tanda_prefijo` = `GV-` · `zonas_automaticas` = `1,2` · seed lk 1 / chef 1 |
| `PPP_Web_NP` / `_Programacion` / `_Base` | 0 / 0 / 0 |
| `PPP_Web_Tandas` | **3 borradores de prueba** (`GV-01A/B/C`, 17:22, 7 bloques de pedidos reales) — hay que descartarlos antes del cambio: un pedido no puede estar en dos tandas y esos quedarían **trabados** |
| cron `gv-ppp-web-tandas-diarias` (jobid 71) | apagado, definición intacta |
| `pwebNumerar()` (la que numeraba todo al abrir una pantalla) | **inalcanzable**: su único caller (`pppTraerPedidosWeb`) no lo llama nadie desde v12.82 |
| credencial `GV_LK_SERVICE_KEY` | ✅ **cargada** — corrida en seco por el camino del cron (`net.http_post` con la service key de `app_secrets`, `?dry=1&fecha=2026-09-07`, `timeout_milliseconds := 90000`): leyó LK y Chef (FDW) y resolvió zonas sin escribir nada |

### ⚠ Lo que estaba mal: el job iba a programar 30 días de pedidos ya entregados

La corrida en seco leyó **365 NP de LK y 39 de Chef** en 30 días. Pero en LK, de los
**213 pedidos** de esos 30 días, **208 ya habían salido a ISIS** por el mail de las 12:30
(`enviado_a_compras_at`) y Producción ya los había entregado. **Ni el job ni "A Programar"
filtraban por eso.** Prendido tal cual, el lunes 00:01 programaba ~226 NP de zona 1 y 2 que
ISIS ya había despachado.

La regla, en palabras del dueño (§3.f): *"va a asignarle la numeración nuestra a los pedidos
que estén **pendientes** y a los que vayan cayendo"*. Pendiente = todavía no se fue a ISIS.

> ⚠ **Esta definición duró unas horas.** A la noche el dueño la corrigió (*"salvo los pedidos
> que estén en la página LK que falten en programación diaria / A Programar"*) y la regla pasó
> a ser **desde el día del cambio, lo que Producción no tenga** — ver **"La regla definitiva"**
> más abajo (v12.89). Las tres filas de LK de la tabla que sigue **se revirtieron** esa misma
> noche; se dejan como historia.

| objeto | qué |
|---|---|
| `gv_pedidos_web_np_lk` (**LK**) | `and not coalesce(p.enviado_a_compras, false)` |
| foreign table `chef_orders` (**LK**) | `+ enviado_a_compras_at timestamptz` (aditivo). Chef la tiene: verificado con `IMPORT FOREIGN SCHEMA` a un schema temporal, borrado después |
| `gv_pedidos_web_np_chef` (**LK**) | `and o.enviado_a_compras_at is null`; `enviado_a_compras` pasa de `null` a `false` |
| front v12.88 `aprTraerPedidos` | pide la columna y filtra `!enviado_a_compras` — duplicado como UX, la regla vive en las RPC |

Las dos funciones **no estaban en ningún repo** (creadas directo en la base). Desde hoy:
`sql/gv_pedidos_web_np_feeds.sql` (vigente) y
`sql/backups/gv_pedidos_web_np_feeds_20260904_pre_filtro_enviado.sql` (rollback textual).

**Medido después:** LK **365 → 10 NP (5 pedidos)** · Chef **39 → 1**. Segunda corrida en seco
por el camino real: `lk: 10 (Zona 1: 8, Zona 2: 1, Zona 5: 1) · chef: 1 (Zona 6)`. Regresión:
`tests/pweb-pendiente.cjs`.

### El interruptor de verdad está en LK, no en Virgilio

Mientras corra el cron de LK **`procesar-pedidos-web`** (`30 15 * * *` UTC = 12:30 ART,
`enviar_pedidos_main()` → `postear_envio_pedidos`) más su `retry-procesar-pedidos`, cada
pedido web sigue yéndose a ISIS al mediodía. Con el filtro de arriba las dos apps **no se
pisan** (Gestión ve sólo lo que ISIS todavía no vio), pero un pedido que Gestión numeró a la
mañana se lo lleva ISIS a las 12:30 y lo entregan dos veces. **Prender la numeración y
apagar ese cron van juntos.** Chef tiene el suyo en su propio proyecto (sin acceso desde acá).

### Checklist del día del cambio — en este orden

0. **Los operarios pasan a la app de Gestión.** Producción no muestra tandas web.
1. **LK** — apagar el mail de las 12:30 (dueño):
   ```sql
   select cron.alter_job(jobid, active := false) from cron.job where jobname in ('procesar-pedidos-web','retry-procesar-pedidos');
   ```
   Y lo mismo del lado Chef, en su proyecto.
2. **Virgilio** — descartar los 3 borradores de prueba (`GV-01A/B/C`): `gv_ppp_web_tanda_descartar` por cada uno, o `delete` en `PPP_Web_Tanda_Items` + `PPP_Web_Tandas` (tablas nuestras).
3. **Virgilio** — las dos líneas de siempre + el cron:
   ```sql
   update public."PPP_Web_Config" set valor       = 1  where clave = 'numeracion_activa';
   update public."PPP_Web_Config" set valor_texto = '' where clave = 'tanda_prefijo';   -- o dejar 'GV-' si se quiere seguir distinguiendo
   select cron.alter_job(71, active := true);
   ```
4. **Verificar:** el primer pedido programado numera `LK 00001` / `CH 00001`; el lunes 00:01 el job arma tandas de zona 1 y 2 (hoy: 9 NP); zona 5 y Chef zona 6 van a mano por "A Programar".

**Rollback** (todo reversible el mismo día): `numeracion_activa = 0`, cron 71 `active := false`,
`tanda_prefijo = 'GV-'`, backup + borrado de `PPP_Web_NP` / `PPP_Web_Programacion` /
`PPP_Web_Base` de ese día, y volver a prender el cron de LK.

### ✅ Lo que se PRENDIÓ — 2026-09-04, viernes a la noche

El dueño frenó el checklist con una condición: **que los cambios toquen sólo Gestión
Virgilio, no Producción**. Los que ya llegaron a Producción por ISIS se quedan ahí; lo que
falte se le suma después. Se midió primero qué escribe cada pieza:

- Las **25 funciones** `ppp_web_*` / `gv_ppp_web_*`: **ninguna escribe** en una tabla
  compartida. Tres sólo leen (`ppp_web_proxima_letra` y `gv_ppp_web_codigo_tomado` →
  `PPP_Programacion_Diaria`; `ppp_web_resync` → `Facturacion_NP`, `Registros`).
- La Edge Function escribe únicamente `PPP_Web_Programacion`, `PPP_Web_Base`,
  `GV_Tandas_Auto_Log` y `PPP_Web_Config`.

Con eso, decisión del dueño: **sólo Virgilio, LK intacto, prefijo `GV-`**.

| paso | hecho | medido después |
|---|---|---|
| borrar los 3 borradores de prueba | ✅ `PPP_Web_Tandas` / `_Items` (backup restore-ready en `sql/backups/backup_PPP_Web_Tandas_borradores_20260904.sql`) | 0 / 0 |
| `numeracion_activa = 1` | ✅ | `1` |
| cron 71 `active := true` | ✅ | `active=true · 1 3 * * 1-5` |
| `tanda_prefijo` | **se deja `GV-`** (convivencia) | `GV-` |
| mail de las 12:30 en LK | **NO se tocó** (decisión del dueño) | `procesar-pedidos-web` activo |
| prueba de numeración en transacción revertida | `gv_ppp_web_np_asignar('lk', …)` asignó **`LK 00001` y `LK 00002`** y no dejó nada | `PPP_Web_NP` = 0 · seeds lk 1 / chef 1 |
| Producción | — | `PPP_Programacion_Diaria` = 182, intacta |

**¿Falta cargar algo en Gestión de lo que ya tiene Producción? No.** Se pidió y se midió
antes de tocar: la PPP de Gestión baja **la misma** `PPP_Programacion_Diaria`
(`pppLoadProgFromSupabase`), así que los 182 NP de Producción ya se ven en Gestión. De esos,
158 NP son 93 pedidos web que ISIS ya numeró (9xxxx): 33 facturados, 53 con tanda, 7 sin
tanda. Cargarlos como `LK 000xx` los duplicaría en la misma pantalla. Sí hay un **limbo** de
**5 pedidos** (3 del 03/09 + 2 del 04/09) que se fueron a ISIS y que Producción todavía no
tiene en su PPP: los trae ISIS el lunes, como siempre. Decisión del dueño: **no cargar nada**.

**Qué pasa a partir de acá.** El lunes 00:01 el job programa las NP web **pendientes** de
zona 1 y 2 (hoy 9 de LK) con tandas `GV-…` y las numera desde `LK 00001`; el resto (zona 5,
Chef zona 6) espera en "A Programar". Como el mail de las 12:30 sigue andando, **lo que
Gestión programe a la mañana también se lo lleva ISIS al mediodía**: mientras convivan,
esos pedidos van a existir en las dos apps. Lo aceptó el dueño; se resuelve el día que se
apague ese cron en LK (paso 1 del checklist).

### ✅ La regla definitiva de "pendiente" — 2026-09-04, más tarde esa noche (v12.89)

Después de prender, el dueño precisó: *"[Gestión] no tiene que leer más de ahora en más,
salvo los pedidos que estén en la página LK que falten en programación diaria / A
Programar"*. El filtro "no enviado a compras" (v12.88) **no cumplía eso**: dejaba afuera el
**limbo** —pedidos que ya salieron a ISIS por el mail de las 12:30 pero que Producción
todavía no tiene— y el dueño quiere que eso sea de Gestión.

Se midieron tres formas y eligió **"desde el día del cambio, lo que Producción no tenga"**:
"lo que Producción no tenga" a secas marcaba 19 pedidos de LK, 9 de ellos de hace tres
semanas que Producción sí entregó pero con otro código (clientes nuevos que ISIS dio de alta
con `cod` 4284…4312, un `cod` "1" placeholder, fechas corridas un día por la carga en ISIS).
Con fecha de corte quedan **10** (los 5 sin enviar + los 5 en limbo). Chef: **2**.

| objeto | proyecto | qué |
|---|---|---|
| `PPP_Web_Config` | Virgilio | + fila `gestion_desde = '2026-09-03'` (`valor_texto`) |
| **`gv_pedidos_web_excluidos(p_pedidos jsonb)`** | Virgilio | **nueva**, `security invoker`, sólo lectura. Recibe `(empresa, order_id, cod, fecha_recep)` por pedido y devuelve los **excluidos** con motivo: `anterior_al_cambio` (`fecha_recep < gestion_desde`) y `en_produccion` (hay una NP de ISIS de ese `cod` con esa fecha de pedido en `PPP_Programacion_Diaria` ∪ `Facturacion_NP` ∪ `PPP_Entregados_Meta` ∪ `Entregas_Virgilio`, fecha por `PPP_Base_Pedidos`; `9xxxx` = LK, `4xxxx` = Chef). **Falla cerrado**: sin config, excluye todo. `sql/gv_pedidos_web_excluidos.sql` |
| `gv_pedidos_web_np_lk` / `_chef` | LK | **vuelven a ser feeds crudos**: se sacó el `and not enviado…`. Chef ahora devuelve `enviado_a_compras` real (informativo). `sql/gv_pedidos_web_np_feeds.sql` reescrito |
| Edge Fn `gv-ppp-web-tandas-diarias` | Virgilio | **v10**: `soloPendientes(emp, filas)` llama a la RPC después de cada feed, en el camino real y en el `dry`; el log guarda `excluidos: {motivo: n}`. Si la RPC falla, esa empresa falla y no se programa nada |
| front v12.89 `aprTraerPedidos` | — | llama a la misma RPC (un registro por pedido) y saca lo que devuelve; si falla, la pantalla falla en vez de mostrar todo. `tests/pweb-pendiente.cjs` (9 chequeos) |

Nada de esto escribe: la RPC sólo lee tablas que `anon` ya leía. Producción no cambia.

**Medido después** (corrida en seco por el camino del cron, `?dry=1&fecha=2026-09-07`):

| | crudo | `anterior_al_cambio` | `en_produccion` | **pendiente** |
|---|---|---|---|---|
| LK | 352 NP · 212 pedidos | 202 | 193 | **18 NP** (Zona 1: 10 · Zona 2: 4 · Zona 3: 1 · Zona 5: 1 · Zona 6: 1 · Retira: 1) |
| Chef | 38 NP · 26 pedidos | 23 | 21 | **3 NP** (Zona 1: 2 · Zona 6: 1) |

(Los motivos se solapan: un pedido viejo que Producción tiene cuenta en los dos.) El lunes
00:01 el job arma zona 1 y 2: **14 NP de LK + 2 de Chef**. Cuando ISIS le traiga a Producción
los del limbo, la RPC los va a marcar `en_produccion` sola y dejan de aparecer.

**Rollback:** `drop function public.gv_pedidos_web_excluidos(jsonb)` + borrar la fila
`gestion_desde`; redeployar la Edge Fn v9 (no llama a la RPC); front v12.88. Los feeds de LK
tal como estaban antes de todo el día: `sql/backups/gv_pedidos_web_np_feeds_20260904_pre_filtro_enviado.sql`.

### 3.m ✅ La canilla del espejo de ISIS, cerrada para Gestión — 2026-09-05 (v12.90)

Pedido del dueño: *"una vez que ya esté todo en Gestión Virgilio, cerrá la canilla para que
no lleguen más desde el espejo del Excel"*. Eligió **cerrarla ya, con corte por NP, en el
backend**.

**Qué es la canilla.** El Apps Script de Google (`handleCargaPPPSync_` en "Carga PPP.gs",
fuera del repo; el espejo es `apps-script/sync-ppp-supabase.gs`) pisa `PPP_Programacion_Diaria`
y `PPP_Base_Pedidos` con la **service key** cada vez que ISIS actualiza el Sheet
(`DELETE ?id=gte.0` + INSERT; 114 k inserts acumulados en Prog, 4,5 M en Base), y el cron
`sync-ppp-entregados-meta` (jobid 27) baja "Pedidos Entregados" a `PPP_Entregados_Meta`. El
pull server-side de `sql/sync_ppp_pull_server_side.sql` **nunca se desplegó** (0 funciones
en la base). **Producción lee esas mismas tres tablas** y sigue viva, así que no se toca ni
Google ni las tablas: se cierra **en lo que Gestión lee**.

**Cómo.** ISIS numera en orden (LK `9xxxx`, Chef `4xxxx`). Se anotó la última NP que había y
Gestión pasa a leer tres vistas que sólo devuelven `np <= corte`:

| objeto | qué |
|---|---|
| `PPP_Web_Config` | + `espejo_np_corte_lk = 98694`, `espejo_np_corte_chef = 44619` (el máximo del espejo al cerrar). **`null` = canilla abierta** (passthrough). Backup previo: `sql/backups/backup_PPP_Web_Config_20260905_pre_espejo_corte.sql` |
| `gv_espejo_corte()` | el corte vigente, una vez por consulta |
| `gv_espejo_np_pasa(np, lk, chef)` | `immutable`: NP numérica de ISIS por encima del corte de su empresa → `false`; etiquetas web, vacíos y cualquier otra cosa → `true` |
| **`gv_ppp_programacion_diaria`**, **`gv_ppp_base_pedidos`**, **`gv_ppp_entregados_meta`** | vistas `security_invoker`, `select` para anon/authenticated y **nada más** (son "simple views" y Postgres las dejaría escribibles), `cross join gv_espejo_corte()` + `where gv_espejo_np_pasa(...)` |
| front v12.90 | los tres endpoints constantes y las 13 URLs literales pasan a las vistas: **0 lecturas REST de las tablas crudas** en `index.html`. Queda `pppSubir` (importar un Excel a mano, supervisor, con confirm), que escribe a las tablas reales: es lo de siempre, no se tocó |
| `gv_pedidos_web_excluidos` | `en_produccion` sólo cuenta NP que pasan la canilla. Sin esto, un pedido nuevo de la página que ISIS cargue mañana quedaba **invisible** en Gestión: excluido de A Programar por estar en Producción, y ausente de la PPP por ser posterior al corte |
| tests | `tests/gv-espejo-corte.cjs` (8 chequeos: 0 lecturas crudas, endpoints, PPP / base de picking / entregados cargan de las vistas). Nueve tests viejos ajustaron el stub de URL (case) |

Todo en `sql/gv_espejo_corte.sql`. Nada escribe; Producción no cambia.

**Medido al cerrar** (corte = máximo → las vistas devuelven exactamente lo que había):

| | tabla | vista |
|---|---|---|
| Programación | 182 | 182 |
| Base | 9.667 | 9.667 |
| Entregados_Meta | 2.783 | 2.783 |

Simulación en transacción revertida: con corte LK `98600` la vista de programación baja a
**94** (= filas reales `<= 98600`, máx. `98600`); la NP `98694` (cod 1964, 02/09) es
`en_produccion` con el corte en `98694`, **no excluida** con el corte en `98693`, y vuelve a
`en_produccion` con la canilla abierta (`null`). La corrida en seco del job da lo mismo que
en §3.l (LK 10 pedidos / Chef 2): hoy el corte no cambia nada, sólo frena lo que venga.

**Qué pasa a partir de acá.** Cada NP que ISIS numere de ahora en más (LK > 98694, Chef >
44619) la ve Producción y **no** Gestión; ese pedido entra a Gestión desde la página. Las 182
abiertas siguen vivas en las dos apps y se purgan solas cuando Producción las saca del Excel.
⚠ Mientras siga el mail de las 12:30 en LK, un pedido nuevo va a existir en las dos apps
(ISIS en Producción, web en Gestión): es lo que el dueño aceptó en §3.l.

**Rollback (abrir la canilla, un update):**
```sql
update public."PPP_Web_Config" set valor = null where clave like 'espejo_np_corte_%';
```
Rollback total: `drop view` de las tres vistas, `drop function` de las dos, borrar las dos
filas de config, front v12.89 (vuelve a las tablas) y la RPC de `sql/gv_pedidos_web_excluidos.sql`.

### 3.n ✅ Etiqueta de NP web a 4 dígitos — 2026-09-05 (v12.91)

Dueño: *"que tengan 4 dígitos los de página"*. `gv_ppp_web_np_label` pasa de `lpad 5` a
`lpad 4`: **`LK 0001` / `CH 0001`** (pasado 9999 crece, `LK 10000`, no se recorta). Se cambió
**antes de numerar el primero**: `PPP_Web_NP` 0 filas, `PPP_Web_Base` 0, `PPP_Web_Programacion`
0, 0 eventos con etiqueta en `Registros_Produccion_Virgilio`, ningún índice sobre la función.
`create or replace` de una función nuestra (`gv_`); la usan `ppp_web_resync`,
`gv_ppp_web_tanda_programar` y las vistas `gv_ppp_web_entregados` / `gv_ppp_web_estado`, que
la toman en vivo. Copias de UX: `pwebNpLabel` (front v12.91) y `npLabel` (Edge Fn **v11**).
Fuente en `sql/gv_tandas_diarias.sql`. Probado: `lk/1 → LK 0001 · chef/1 → CH 0001 ·
lk/357 → LK 0357 · lk/12345 → LK 12345`. Rollback: volver a `5` en los tres lugares (sólo
mientras no haya nada numerado; después habría que reetiquetar).

### 3.o ✅ La NP web es el número de pedido de la página — 2026-09-05 (v12.92)

Dueño: *"tiene que ser automático: ya cuando llegan a página LK y a Gestión Virgilio, ya
vienen con numeración. En página LK ya tienen numeración. En Gestión, con la lógica de los
18 ítems para LK y 15 para CH"*. Se descarta el contador propio ("desde 0001", §3.f) sin
haber numerado nada.

| objeto | qué |
|---|---|
| `PPP_Web_NP` | PK `(empresa, np)` → **`(empresa, order_id, np_idx)`** (+ índice `(empresa, np)`). `np` = `order_id`: dos bloques del mismo pedido comparten número |
| `gv_ppp_web_np_label(empresa, np, np_idx default 1)` | **nueva firma**: `LK 1350` · `LK 1350-2` · `CH 0217`; pasado 9999 crece. La de dos parámetros se **dropeó** (ambigüedad con el default) |
| `gv_ppp_web_np_asignar` | ya no cuenta: registra `np = order_id` por bloque, idempotente. Conserva firma, candado `numeracion_activa` y grants (sólo `service_role`; el front sigue entrando por `ppp_web_np_asignar`) |
| `gv_ppp_web_estado`, `gv_ppp_web_entregados` | recreadas (dependían de la función): etiqueta con bloque. `security_invoker`, sólo `select` |
| `ppp_web_resync`, `gv_ppp_web_tanda_programar` | pasan `np_idx` a la etiqueta; el bloque agregado hereda `order_id` si no está en `PPP_Web_NP` |
| `PPP_Web_NP_Seed` | queda sin uso. No se borra |
| front v12.92 | `pwebNpLabel(emp, np, np_idx)`; PPP y monitor etiquetan con bloque; **A Programar muestra la NP apenas llega** (tarjeta y bloques); Facturación acepta `LK 1350-2` |
| Edge Fn | **v12**: `npLabel(emp, num, idx)` en la foto de artículos |

Todo en `sql/gv_np_es_pedido.sql`. Producción no cambia (objetos `PPP_Web_*` / `gv_*`).
Backup previo: `sql/backups/gv_np_es_pedido_20260905_pre.sql`.

**Medido:** antes, `PPP_Web_NP` / `_Programacion` / `_Base` en 0 y 0 eventos con etiqueta.
Después, `gv_ppp_web_np_label('lk',1350) = LK 1350 · ('lk',1350,2) = LK 1350-2 · ('chef',217) =
CH 0217 · ('lk',12345) = LK 12345`; PK y `security_invoker` verificados. Página hoy: LK va por el
pedido **1349**, Chef por el **217**. Test `tests/pweb-np-es-pedido.cjs`.

**Rollback:** el backup (volver a la etiqueta de dos parámetros, el contador y las vistas) +
PK original de `PPP_Web_NP`; front v12.91; Edge Fn v11. Sólo mientras no haya nada numerado.

### 3.p ✅ Corte real: mail de las 12:30 de LK APAGADO, bloques como ISIS — 2026-09-05 sábado 13:50 ART (v12.94)

Un cruce de sólo lectura sobre los repos `pagina-lk-copia`, `paginach`, la base de LK y
Gestión (17 agentes, 4 desvíos verificados por tres escépticos cada uno) confirmó:
**el número coincide** (`LK 1350` = "Pedido N° 1350" de la página = `orders.id`; `CH 0217` =
`chef_orders.id` 217), **los bloques no** (ISIS/el mail cortan de a 18/15 SEGUIDOS en el orden
del carrito, que en LK ya viene por código ascendente; Gestión repartía por serpentina de m³:
misma cantidad, otras líneas — pedido 1345: mail 18+4, Gestión 11+11), y **el riesgo alto**: el
mail seguía prendido, ese mismo sábado a las 12:30 mandó a ISIS los pedidos 1340..1349, y
Gestión los tenía como pendientes para el lunes → doble armado.

Decisiones del dueño: **bloques igual que ISIS** y **corte al lunes + apagar el mail**.

| objeto | proyecto | qué |
|---|---|---|
| cron 7 `procesar-pedidos-web` (`30 15 * * *`) y cron 10 `retry-procesar-pedidos` (`2-59/6 15,16 * * *`) | **LK** | `cron.alter_job(…, active := false)` a las 13:50 ART del sábado. Último envío: sábado 12:30, pedidos 1340..1349. **Chef tiene su propio cron en su proyecto (nkhzocgdpwtgrmwleihr): lo apaga el dueño desde el Dashboard.** |
| `v_pedidos_web_np` | LK | bloques seguidos: `rk = row_number() over (partition by empresa, order_id order by linea_rn)`, `np_idx = ceil(rk / cap_lineas)`. Únicos consumidores: `gv_pedidos_web_np_lk` / `_chef` (medido con `pg_depend` + `pg_proc`). `sql/pedidos_web_lk.sql` |
| `gv_pedidos_web_np_chef` | LK | idem, de a 15 por `linea_rn`. `sql/gv_pedidos_web_np_feeds.sql` |
| `gv_pedidos_web_excluidos` | Virgilio | **vuelve `enviado_a_compras` como primer motivo (`enviado_a_isis`)**: lo que ya salió por mail es de Producción. `gestion_desde` se queda en 2026-09-03 como piso. `sql/gv_pedidos_web_excluidos.sql` |
| Edge Fn v13 · front v12.94 | Virgilio | pasan `enviado_a_compras` en `p_pedidos` (`soloPendientes`, `aprTraerPedidos`) |

**Por qué no se movió `gestion_desde` al lunes** (lo que el dueño eligió literalmente): con el
mail apagado el sábado a la tarde, el pedido 1350 (sábado 12:49) y los del domingo no salen por
mail nunca; excluidos por fecha, no los tomaría nadie. Con `enviado_a_compras` el corte es
exacto —el último mail— y no hay ni dobles ni huérfanos. Es lo que el dueño pidió ("cero
dobles"), implementado por la bandera y no por la fecha.

**Medido:** `v_pedidos_web_np` 1345 → `1: 18 líneas (315…551)` + `2: 4 líneas`, y las 18 son
exactamente las primeras 18 de `v_pedidos_web` por `linea_rn`; en 60 días los bloques no
finales tienen siempre 18. Chef 205 → `1: 15` + `2: 12`, primeras 15 en orden de carrito.
RPC: `1349 (enviado) → enviado_a_isis`, `1350 (no enviado, 05/09) → pendiente`, `1300 (20/08)
→ anterior_al_cambio`. Corrida en seco del job (Edge Fn v13, `?dry=1&fecha=2026-09-07`):
LK 213 pedidos → `enviado_a_isis` 212 · pendiente **1 pedido (el 1350, 4 NP, Zona 1)**; Chef 26 →
`enviado_a_isis` 26 · pendiente **0**. El lunes 00:01 arranca con lo que caiga desde el sábado 12:30.

**Rollback:** LK `select cron.alter_job(7, active := true); select cron.alter_job(10, active := true);`;
la vista y la función con serpentina están en git (commit 0469989, `sql/pedidos_web_lk.sql` y
`sql/gv_pedidos_web_np_feeds.sql`); la RPC v12.89 en el commit 473cf7f; Edge Fn v12; front v12.93.

Quedaron anotados, sin tocar: `order_tracking` de LK cruza por id pelado y mezcla LK/Chef (id 217
es de Chef y pisa al LK 217): cuando Gestión alimente el tracking, escribir el id pelado por
una función `gv_*` y pedir columna `empresa` en PaginaLK. Y el Excel ISIS de Facturación manda
`N_Pedido` contador (no el id), como el mail: ISIS numera 98xxx por su cuenta.

### 3.z ✅ Rol `ch_ppp_reader`: Chef lee su estado en Gestión por FDW (ideas 8743 + 4990) — 2026-09-05 sábado (v13.09)

**Qué.** La página de Chef (`paginach`) va a mostrar en "Mis pedidos" el estado real del pedido
en Gestión (programado / en preparación / facturado / entregado) y a bloquear la edición cuando
está facturado, igual que LK desde la v2.3.301. LK lo hace con `postgres_fdw` contra Virgilio con
el rol `lk_ppp_reader`; para Chef se creó el rol gemelo **`ch_ppp_reader`** (migración
`ch_ppp_reader_rol_lectura_para_chef_v1309`): `login`, `connection limit 5`, sin `bypassrls`, sin
escritura, `usage` en `public` y **SELECT** en las mismas 13 tablas/vistas que `lk_ppp_reader`
menos las de LK (`lk_pedidos_match`, `proyeccion_madre`, `whatsapp_clientes`):
`Facturacion_NP`, `GV_Volumen_Articulos`, `PPP_Base_Pedidos`, `PPP_Entregados_Meta`,
`PPP_Programacion_Diaria`, `PPP_Web_Programacion`, `Registros_Produccion_Virgilio`,
`Volumen_Articulos`, `gv_pedido_web_estado_pagina`, `gv_ppp_web_estado`, `ppp_etapa_tanda`,
`vista_ppp_pedidos_entregados`, `vista_volumen_articulo_resuelto`. La contraseña se generó al azar
y **no se imprimió**: el dueño la reemplaza con `alter role ch_ppp_reader password '…'` y usa la
misma en el user mapping del lado Chef (`paginach/sql/gv_estado_mis_pedidos_chef.sql`, que además
crea la RPC `gv_estado_mis_pedidos` y suma el candado "facturado" a `edit_order_fast`).

Además, como las 8 tablas base tienen RLS, el grant solo no alcanza: `lk_ppp_reader` tiene una
policy de SELECT por tabla (`lk_ppp_reader_sel`), así que se creó la gemela **`ch_ppp_reader_sel`**
(`for select to ch_ppp_reader using (true)`) en `Facturacion_NP`, `GV_Volumen_Articulos`,
`PPP_Base_Pedidos`, `PPP_Entregados_Meta`, `PPP_Programacion_Diaria`, `PPP_Web_Programacion`,
`Registros_Produccion_Virgilio` y `Volumen_Articulos` (migración `ch_ppp_reader_policies_select_v1309`).
`ppp_etapa_tanda` no tiene RLS. Es AGREGAR una policy para un rol nuevo: las de anon/authenticated
(Producción) no se tocan — mismo precedente que `lk_ppp_reader`.

**Impacto medido.** Nada cambia para Producción ni para la app (rol nuevo + policies sólo para él).
Hoy la vista está vacía de verdad: `PPP_Web_Programacion` tiene 0 filas (la primera corrida real es
el lunes 07/09 00:01), así que `gv_pedido_web_estado_pagina` da 0 y el FDW de LK también da 0 —
coherente, no es RLS. No se pudo hacer `set role ch_ppp_reader` desde el MCP (no es miembro); la
prueba real es del lado Chef, después del lunes:
`select * from virgilio.gv_pedido_web_estado_pagina where empresa = 'chef' limit 5;`

**Rollback.** `drop owned by ch_ppp_reader; drop role ch_ppp_reader;` (borra también sus policies;
y en Chef el bloque de rollback del SQL).

### 3.y ✅ Tandas por cercanía real: sectores + vecinos, zona 3 automática (idea 7317) — 2026-09-05 sábado (v13.07)

**Qué pidió el dueño.** *"Zonas pueden ir agrupadas también zona 1 y 2. Hay más zonas juntas… pero
hay cosas que no son parejas: Núñez con Villa Lugano estaría dentro de 1 y 2 y no debe ir junto."*
Análisis previo con 10 agentes sobre 2.454 NP con tanda (ene–sep): `docs/ANALISIS-TANDAS-CERCANIA-20260905.md`.
Decisiones (AskUserQuestion): **sectores + vecinos en tablas, backend**; **Boedo con Once/Almagro**
(Centro); **Capital Sur puede compartir con Avellaneda/Lanús/V. Alsina**; **zona 3 automática**.

**Qué se hizo** (`sql/gv_sectores.sql` + `sql/ppp_web_tandas.sql`, migraciones
`gv_sectores_tandas_por_cercania_v1307` y `ppp_web_armar_tandas_v4_sectores_v1307`):
- Tablas nuevas (RLS: todos leen, escriben los tres mails de supervisor; grants como `PPP_Web_Base`):
  **`GV_Sectores`** (14 sectores A…P, sin I/O; `camion` = Capital / GBA Sur / GBA Oeste / GBA Norte),
  **`GV_Barrios_Sector`** (109 barrios = TODOS los `Zonas_Barrios` de zona 1–7, clave `_norm_barrio`),
  **`GV_Sectores_Vecinos`** (27 pares que pueden compartir tanda), **`GV_Barrios_Pares`** (23
  excepciones: 18 NO Núñez/Belgrano/Colegiales × Lugano/Soldati/Pompeya; 5 SÍ Boedo × Pompeya/P. Patricios).
- Funciones nuevas: `gv_ppp_web_barrio_norm(barrio, direccion)` (prueba el texto crudo, el barrio
  parseado de ese texto y el de la dirección — la Edge Function manda la dirección entera como
  barrio cuando no hay otra cosa), `gv_ppp_web_sector(zona, barrio, direccion)` (`'~<grupo>'` si no
  hay sector: Retira, Súper, barrio desconocido), `gv_ppp_web_camion(zona, sector)`,
  **`gv_ppp_web_compat(...)`** (el núcleo: interruptor → par explícito → mismo sector → pseudo-sector
  cae en la regla vieja de grupo → vecinos), `gv_ppp_web_pueden_compartir(...)` (cómoda) y
  **`gv_ppp_web_armar_simular(empresa, fecha, filas, forzar)`**: corre el armado y lo deshace
  (excepción propia `GVS01`), devuelve `{tandas, detalle}` — para probar sin escribir.
- **`ppp_web_armar_tandas` v4**: con `PPP_Web_Config.sectores_activos = 1` (fila nueva) recorre los
  clientes por camión → sector → m³ y los mete en la primera tanda abierta que no pase el tope y sea
  compatible con TODAS sus paradas (clique); si no hay, abre tanda nueva. El NÚMERO de la tanda es
  por camión (E01A = Capital), la letra por tanda. Súper, `solo` y ≥ tope siguen solos. Con `= 0`
  corre el bucle viejo línea por línea. `r_zona` pasa a listar las zonas reales de la tanda.
  Backup del cuerpo anterior: `sql/backups/ppp_web_armar_tandas_20260905_pre_sectores.sql`
  (md5 `3b7ae2a5…`).
- `zonas_automaticas` = `'1,2,3'` (antes `'1,2'`): la zona 3 entra al job de las 00:01 y al intradía.

**Impacto medido.** Simulación con 14 filas sintéticas (`gv_ppp_web_armar_simular`, fecha 07/09):
Núñez → E01D y Villa Lugano → E01A (**nunca juntos**); Barracas + Constitución + Lugano → E01A
(0,75); Pompeya + Mataderos → E01B (0,65); Boedo + Flores + barrio desconocido → E01C (0,75: el
desconocido cae en la regla vieja "mismo grupo Zonas 2+3" y va al final, `collate "C"`); Once +
Núñez + Belgrano → E01D (0,80 justo); Avellaneda (zona 4), Retira y Súper quedan sin tanda (no
automáticos). Los 109
barrios de zona 1–7 tienen sector (0 sin). `gv_ppp_web_pueden_compartir`: Núñez–Lugano false,
Barracas–Constitución true, Boedo–Pompeya true, Once–Pompeya false, Flores–Mataderos true,
Barracas–Avellaneda true, desconocido(z2)–Once true, desconocido(z2)–Barracas false, Retira–Barracas
false. Producción: cero referencias a `ppp_web_armar_tandas`/`GV_Sectores*`/`sectores_activos` en su
repo (grep del 05/09); nada de lo nuevo escribe en tabla compartida. Nada se escribió en
`PPP_Web_Programacion` (la simulación deshace). Primera corrida real: lunes 07/09 00:01 (cron 71) y
07:00 (cron 73).

**Front (v13.07).** Tablero: un camión = un NÚMERO de tanda (E01A + E01B = Camión 1, como el cuadro
"Total por día"); si la tanda mezcla zonas vecinas la etiqueta las lista ("Camión 1 · Zona 1 +
Zona 2"); sin tanda → "Sin tanda · Zona 4"; Retira y Súper aparte. Test `ppp-plan-nueva` +1 chequeo.

**Rollback.** `update public."PPP_Web_Config" set valor = 0 where clave = 'sectores_activos';`
(vuelve el bucle viejo sin redeploy) y `set valor_texto = '1,2' where clave = 'zonas_automaticas'`.
Para sacar todo, el bloque final de `sql/gv_sectores.sql`.

**Advisors (v13.08).** Security advisor tras la migración: sobre lo nuevo sólo (a)
`auth_allow_anonymous_sign_ins` en las 4 tablas — es el patrón de todas las `PPP_Web_*`/`GV_*`
(la app entra con la anon key; escribe sólo el supervisor por mail) y (b)
`function_search_path_mutable` en las 6 funciones nuevas y en `ppp_web_armar_tandas` → migración
`gv_sectores_search_path_v1308`: `set search_path = public, pg_temp` en las 7 (todas califican
`public.`; `pg_temp` por las tablas temporales del armado). Simulación re-corrida después: mismo
resultado. Sin filas de la simulación en `PPP_Web_Programacion` (0), una sola sobrecarga de
`ppp_web_armar_tandas`.

### 3.x ✅ Armado intradía de zona 1 y 2 al llegar a 0,80 m³ (idea 7317) — 2026-09-05 sábado (v13.04)

**Qué pidió el dueño.** *"Los pedidos que se entregan en zona 1 y 2 deben programarse
inmediatamente, apenas llegan, porque a esa zona voy todos los días."* Aclarado: *"cuando se llega
a 0,80 para zona 1 y 2, para el próximo día que se pueda entregar según PPP; excepciones son las de
súper"*; lo que no llega a 0,80 lo arma igual el job de las 00:01; "hoy" cuenta si es antes de las
12:00 y hay cupo. Decisión: backend.

**Qué había.** El armado (`ppp_web_armar_tandas`) ya era idempotente, ya se limitaba a
`zonas_automaticas = '1,2'` y Súper nunca es automático. Lo único que lo frenaba era el cron 71:
una corrida por día, 00:01.

**Qué se hizo** (`sql/gv_ppp_web_intradia.sql`, migración `gv_ppp_web_intradia`, Edge Function
`gv-ppp-web-tandas-diarias` **v14**):
- `PPP_Web_Config`: filas nuevas `intradia_umbral_m3 = 0.80` y `intradia_corte_hora = '12:00'`
  (`insert … on conflict do nothing`).
- Función nueva `gv_ppp_web_proximo_dia_entrega(p_ahora)`: hoy si es antes del corte, hábil y con
  m³ programados < `m3_max_dia`; si no, el primer hábil siguiente con cupo. Probado: sáb 05/09 →
  lun 07; lun 10:00 → lun; lun 12:00 → mar; vie 13:00 → lun 14.
- Edge Function, flag `intradia` (query `?intradia=1` o body `{"intradia": true}`): la fecha la
  elige la función de arriba; lee LK y Chef UNA vez, suma lo pendiente **sin tanda** de las zonas
  automáticas (`pendienteAutomatico`: `gv_ppp_web_zona_automatica` por zona) y si es
  `< intradia_umbral_m3` sólo loguea `intradia_sin_umbral` (nada se escribe); si llega, corre el
  armado normal (mismo `procesarEmpresa`) y loguea `intradia_ok`. Sin el flag la función es
  idéntica a v13 (el job de las 00:01 no cambia). `?dry=1&intradia=1` devuelve `armaria`,
  `m3_pendiente_automatico` y el detalle por empresa.
- Cron NUEVO **jobid 73** `gv-ppp-web-tandas-intradia`: `*/15 10-21 * * 1-5` UTC = cada 15 min,
  lun–vie 07:00–18:45 ART, body `{"intradia": true}`.

**Impacto medido.** Dry run sáb 05/09 18:31 ART: fecha elegida 2026-09-07, pendiente automático
**1,129 m³ / 5 NP** (LK, todas Zona 1), Chef 0 → `armaria: true`. O sea el lunes a las 07:00 el
intradía arma lo mismo que el job de las 00:01 ya habrá armado (idempotente: no duplica). Producción
no se toca (escribe sólo en `PPP_Web_Programacion`, `PPP_Web_Base`, `GV_Tandas_Auto_Log`).

**Rollback.** `select cron.unschedule('gv-ppp-web-tandas-intradia');` (la función v14 sin el flag
es v13). Y `drop function public.gv_ppp_web_proximo_dia_entrega(timestamptz); delete from
public."PPP_Web_Config" where clave in ('intradia_umbral_m3','intradia_corte_hora');`

### 3.w ✅ Cargado al camión = En Salida (idea 4459) + valor a lista por NP — 2026-09-05 sábado (v13.02)

**Qué pidió el dueño.** *"Si hay pedidos que ya se cargaron a un camión, tienen que salir de la
Programación y pasar a En Salida, y no verse más en Programación."* Decisión (AskUserQuestion):
backend, y también el **$ por pedido** del resumen por día de la Programación nueva en backend.

**Vistas nuevas** (sólo lectura, `security_invoker`, grant select a anon/authenticated):
- **`gv_ppp_en_salida`** (`sql/gv_ppp_en_salida.sql`, migraciones `gv_ppp_en_salida` y
  `gv_ppp_en_salida_fss`): NP con CCN de legajo real, sin CRN, sin FSS posterior a la última
  carga; enriquecida como `gv_ppp_entregados` (web por `PPP_Web_Programacion`, ISIS por las vistas
  gv_ con canilla + `Facturacion_NP` + meta). Columnas: np, empresa, es_web, tanda, cod_cliente,
  razon_social, m3, fecha_entrega, zona, barrio, direccion, fecha_carga, cargado_at, n_ccn, facturada.
- **`gv_ppp_np_valor`** (`sql/gv_ppp_np_valor.sql`): valor_lista por NP = Σ cajas × uxb × precio_unit
  (ISIS: `gv_ppp_base_pedidos` × `precios_venta`/`precios_venta_chef` según prefijo 4xxxx=Chef; web:
  `PPP_Web_Base` × precios por empresa), más lineas y lineas_sin_precio. Sin descuentos.

**Impacto medido** (como `anon`): `gv_ppp_en_salida` 23 NP (todas facturadas, cargas del 14/08 al
04/09; 14 todavía en `gv_ppp_programacion_diaria` → esas dejan de verse en Programación y pasan a
En Salida). `gv_ppp_np_valor` 822 NP (181 de las 182 programadas), 46 con alguna línea sin precio,
total programado ≈ $334 M. Producción no lee ninguna de las dos. Sin escritura, sin trigger.

**Rollback.** `drop view public.gv_ppp_en_salida; drop view public.gv_ppp_np_valor;` y front v13.01.

### 3.v ✅ Alerta `picking_sin_terminar` (idea 1471) — 2026-09-05 sábado (v13.00)

**Qué.** Espejo de `armado_sin_terminar` para el picking: EP abierto > 24 h sin TP (últimos 7 días,
sin legajos 0/1), severidad `media`, hasta 20 filas.

**Cómo, sin tocar lo compartido.** `generar_reporte_agentes()` la usa Producción (cron jobid 14,
`0 11,15,19 * * *` UTC) y **borra `reporte_agentes` entera al arrancar**, así que no se la editó:
función NUEVA `public.gv_reporte_agentes_picking_sin_terminar()` (SECURITY DEFINER, sin execute
para anon/authenticated; sólo borra su propia categoría y agrega filas) + cron NUEVO **jobid 72**
`gv-reporte-agentes-picking-sin-terminar`, `2 11,15,19 * * *` UTC (2 min después del 14). SQL en
`sql/gv_reporte_agentes_picking_sin_terminar.sql`.

**Impacto medido.** Corrida a mano el 05/09 → 0 filas (no hay pickings abiertos > 24 h). Producción:
su panel Agentes itera una lista fija de categorías y no conoce esta clave → no la muestra; el
resumen Telegram de las 22:00 (`reporte_agentes_resumen_telegram`) cae en el `else` y la nombra
por su clave como "media". Gestión la renderiza en 🤖 Agentes y la suma al briefing "Hoy".

**Rollback.** `select cron.unschedule('gv-reporte-agentes-picking-sin-terminar');`
`drop function public.gv_reporte_agentes_picking_sin_terminar();`
`delete from public.reporte_agentes where categoria = 'picking_sin_terminar';`

### 3.u ✅ RLS en las 11 tablas que no la tenían (idea 6309) — 2026-09-05 sábado (v13.00)

**Qué había.** Las 4 tablas de la idea (`alertas_recepcion_log`, `*_backup_20260807`) ya estaban con
RLS. Pero `pg_class.relrowsecurity = false` daba **11 tablas más**, todas de Gestión (creadas
02/09–04/09): `Partes_Plasticas_bkp_codisis_20260904`, `Partes_Plasticas_bkp_proveedor_20260904`,
`clientes_dto_backup_20260902`, `cobranzas_super_cadena_backup_20260902`,
`precios_super_lk_backup_20260902`, `snap_costo_nombres_0903` (backups/snapshots, con grant ALL a
anon y sin ninguna referencia en código), y las vivas `codigos_duales`, `cobranzas_escalones`,
`deudores_condiciones`, `wa_grupo_listo`, `wa_np_snapshot`.

**Qué se hizo** (migración `gv_rls_tablas_sin_rls_20260905`). RLS prendida en las 11. Backups: sin
policy → la anon key ya no las ve. Vivas: policy `gv_select_all` (`for select to anon, authenticated
using (true)`) → lo que se leía se sigue leyendo; escrituras sólo por funciones SECURITY DEFINER
(`wa_*`, triggers), que no pasan por RLS. **Grants sin tocar.** Las vistas que las usan
(`vista_saldos_stock` → `codigos_duales`; `vista_np_factura` → `wa_np_snapshot`;
`vista_deudores_documentos` → `cobranzas_escalones`, `deudores_condiciones`) corren como owner (no
tienen `security_invoker`), así que la RLS de la base no las afecta.

**Impacto medido** (`set local role anon`): `vista_saldos_stock` 483 filas, `vista_np_factura` 92,
`codigos_duales` 4, `cobranzas_escalones` 6, `wa_np_snapshot` 254, `wa_grupo_listo` 62 (igual que
antes); los backups devuelven 0. `vista_deudores_documentos` da "permission denied" para anon **y
para authenticated, igual que antes de la migración** (nunca tuvo grant; se lee por RPC/service_role).
Después: **0 tablas de `public.*` sin RLS.**

**Rollback.** `sql/backups/backup_rls_tablas_sin_rls_20260905_pre.sql` (11 `disable row level
security` + 5 `drop policy`).

### 3.t ✅ El estado del pedido en la página LK (idea 8743) — 2026-09-05 sábado

Dueño: *"cuando un pedido queda facturado debería mostrarlo en la página y decir que ya no
se puede modificar"*.

| objeto | proyecto | qué |
|---|---|---|
| **`gv_pedido_web_estado_pagina`** (vista, `security_invoker`) | Virgilio | un estado por `(empresa, order_id)`: el del bloque **menos** avanzado — `sin_programar / programado / en_picking / pickeado / en_armado / armado / facturado / entregado` — con `fecha_entrega`, `tanda`, `facturado`, `entregado`, `entregado_at` (CRN). Sale de `gv_ppp_web_estado` + CRN. `sql/gv_pedido_web_estado_pagina.sql` |
| rol `lk_ppp_reader` (el del FDW de LK) | Virgilio | + `select` sobre `PPP_Web_Programacion` (policy `ppp_web_prog_lk_reader_sel`), `gv_ppp_web_estado` y la vista nueva; + `execute` sobre `gv_ppp_web_np_label`. Todo aditivo |
| foreign table `virgilio.gv_pedido_web_estado_pagina` | LK | `import foreign schema … limit to` |
| RPC `gv_estado_mis_pedidos(p_ids)` | LK | `security definer`, sólo `authenticated`; devuelve el estado de los pedidos del usuario (dueño / link / admin, como `orders_select_own`). `sql/gv_estado_mis_pedidos.sql` del repo LK |
| `edit_order_fast` | LK | + candado: facturado o entregado en Gestión → `Pedido ya facturado: no se puede modificar` (backup en el repo LK) |
| front LK | LK | "Mis pedidos" lee la RPC; stepper de **4** pasos (Recibido · Programado/En preparación · Facturado · Entregado); facturado/entregado esconde Editar y lo dice. `isOrderEditable` pierde el corte de las 12:30 (mail apagado). Test `tests/estado-gestion.cjs` (16) |

Producción no cambia. Chef queda afuera (sin acceso a su proyecto; su página no edita).
**Rollback:** `drop view gv_pedido_web_estado_pagina` + revocar los grants a `lk_ppp_reader`;
en LK `drop function gv_estado_mis_pedidos`, `drop foreign table`, y `edit_order_fast` de
`sql/edit_order_solo_agregar.sql`; front LK commit anterior.

### 3.s ✅ Tandas sin prefijo `GV-` — 2026-09-05 sábado (config, sin bump)

Dueño: *"sacá el prefijo GV- de las tandas"*. `update "PPP_Web_Config" set valor_texto = ''
where clave = 'tanda_prefijo'`. Medido antes: `PPP_Web_Tandas` 0, `PPP_Web_Programacion` con
tanda 0 (nada que renombrar). Después: `ppp_web_proxima_letra()` = 4 (A=0 → **E**), última
de Producción `D71A` → la primera tanda de Gestión será **`E01A`**, codificación histórica
`LETRA+NN+LETRA`. Producción no cambia. Rollback: `valor_texto = 'GV-'`.

### 3.r ✅ Control de remito = entregado, solo — 2026-09-05 sábado (v12.95)

Dueño: *"cuando ya el pedido se controla el remito, tiene que pasar directamente a Pedidos
Entregados, sin que nadie toque nada. En Producción requiere corregir el Excel; en Gestión
automático."* Eligió **backend**.

| objeto | qué |
|---|---|
| **`gv_ppp_entregados`** (vista, `security_invoker`, sólo `select` anon/authenticated) | toda NP con evento `CRN` (`Registros_Produccion_Virgilio`, sin legajos de prueba): `np` (etiqueta para las web), `empresa`, `es_web`, `tanda`, `cod_cliente`, `razon_social`, `m3`, `fecha_entrega`, `fecha_carga` (último `CCN`), `controlado_at` (primer CRN), `n_crn`, cajas de `Entregas_Virgilio`, `facturada`. Datos de `PPP_Web_Programacion` (web) o `gv_ppp_programacion_diaria` → `Facturacion_NP` → `gv_ppp_entregados_meta` (ISIS, en ese orden). Sólo NP que Gestión conoce. `sql/gv_ppp_entregados.sql` |
| front v12.95 | Programación (sólo lectura) esconde las controladas en vez del badge «🚮 SACAR»; Pedidos Entregados suma las de la vista aunque no estén facturadas/cerradas; el set de controladas viene de la vista (60 días de CRN sólo como fallback) |

Nada escribe. Producción no cambia: sigue con su Excel.

**Medido:** 821 CRN históricos → **376** NP resueltas (0 web todavía), **32** todavía en la
programación de ISIS (desde hoy no se ven en Programación de Gestión), 0 sin facturar; 445 CRN
de NP que ya no están en ninguna tabla (más viejas que el espejo) quedan afuera, como corresponde.

**Rollback:** `drop view public.gv_ppp_entregados;` + front v12.94.

### 3.q 🔍 Control "ningún pedido muerto en el medio" — 2026-09-05 sábado (sólo lectura)

Pedido del dueño: los últimos 50 clientes que pidieron por cada página, y ver si están en la PPP
de Gestión. Se tomó el último pedido de cada uno de los 50 clientes más recientes (LK 50 · Chef 49,
desde 26/08 y 01/07) y se lo buscó en las cuatro tablas que Gestión lee (programación,
facturación, entregados, entregas, por `cod` + fecha de `PPP_Base_Pedidos`) y en la RPC de
pendientes.

| veredicto | LK | Chef |
|---|---|---|
| En Producción (NP de ISIS, programada/facturada/entregada) | 39 | 44 |
| Enviado a ISIS el jue/vie/sáb, Producción todavía no lo cargó (⏳ normal: entra el lunes) | 10 (1340..1349) | 2 (216, 217) |
| Pendiente en Gestión ("A Programar") | 1 (1350) | 0 |
| Con fecha corrida (ISIS lo cargó con otra fecha), igual en Producción | 0 | 1 (164) |
| Cargado por ISIS **como pedido de la otra empresa** | — | 1: Chef 208 (P & M Bazar, 24/08) está como **LK 98544/98545, cod 4044**, facturado 02/09 |
| **⚠ MUERTO** | 0 | **1: Chef 200 — El Martillo Srl (cod Chef 2643 / LK 3831, CUIT 30714523585), 13/08, 33 líneas, salió por mail 13/08 15:30 UTC y no está en ninguna tabla de Producción, ni por cod, ni por nombre, ni por artículos (mejor candidato coincide 7 de 20), ni facturado en `isis_ch`/`isis_lk.documentos` desde el 10/08** |

Receta (dos consultas, `sql/` no hace falta): en LK, `distinct on (cod)` sobre `v_pedidos_web_np`
(np_idx = 1) y `gv_pedidos_web_np_chef(90)` ordenado por `order_id desc`; en Virgilio, cruzar
`(empresa, order_id, cod, fecha, enviado)` contra `gv_ppp_programacion_diaria ∪ Facturacion_NP ∪
gv_ppp_entregados_meta ∪ Entregas_Virgilio` por `cod` + fecha de `gv_ppp_base_pedidos` (±3 días
para "corrida") y contra `gv_pedidos_web_excluidos`. Regla: enviado y sin NP con fecha ≥ 03/09 =
⏳; enviado y sin NP más viejo = muerto; no enviado y excluido = muerto; no enviado y no excluido =
Gestión. **Repetir el lunes a la tarde: los 12 ⏳ tienen que haber pasado a Producción.**

---

## 4. Incidente de seguridad — 2026-09-04 (cerrado)

`public.vista_pedidos_web_feed` tenía `select` para `anon`. Los esquemas `fuentes` y
`pipeline` sí estaban revocados, **pero la vista no llevaba `security_invoker`**: al vivir
en `public` la publica PostgREST, corre como `postgres` y pasa por arriba de ese candado.

Con la anon key —que es pública y está en los dos repos— se leían los **1.358 pedidos web
de LK y Chef** enteros: razón social, código de cliente, sucursal de entrega, ítems y
condición de pago.

Verificado antes: `set role anon` + count → 1.358 filas. Después del revoke:
*permission denied*. La vista se dropeó ese mismo día junto con el resto del build parado.

**Lección, ya incorporada a §1:** una vista en `public` sobre datos con RLS o sobre
foreign tables necesita `security_invoker = true`. El revoke del esquema de abajo **no la
cubre**.

---

## 4.b Integración Krikos — contexto que llega de LK, 2026-09-04

Nota de la sesión de LK, anotada acá porque **toca este proyecto Supabase** y porque es
justo el pendiente **9357** (la fecha de entrega de los súperes).

Del lado LK está construido —rama `claude/krikos-lk-integration-064xyz` de
`pagina-LK-copia`, pusheada y **sin mergear**— un ingest por IMAP que lee las
notificaciones de OC de Planexware, baja el PDF y guarda la **fecha de entrega** en
`krikos_oc_inbox`; de ahí viaja en `orders.sheets_payload.fecha_entrega` (+
`fecha_entrega_origen`). Antes sólo se parseaba `due_date`, que es vencimiento de cobro.

### ✅ La columna ya está — hecho el 2026-09-04

Se agregaron **`fecha_entrega date`** y **`fecha_entrega_txt text`** a
`public.lk_pedidos_match`, con el DDL en `sql/lk_pedidos_match.sql` del repo
`Produccion-Virgilio` (commit `e15b682`) — base y repo dicen lo mismo. Dos columnas y no
una porque el `date` sirve para filtrar y ordenar, y el texto conserva el crudo
`dd/mm/yyyy hh:mm` cuando la cadena da franja horaria.

⚠ **Sin prefijo `gv_`, a propósito**: esa tabla no es de Gestión — la escribe **LK** por
el FDW y la lee **Producción**. El prefijo diría lo contrario.

**Verificado después de aplicar** (no supuesto): las dos columnas nullable, sin `default`
y sin backfill · **1.085 filas intactas**, 0 con fecha · `vista_np_sucursal` sigue en
**149** filas · `PPP_Programacion_Diaria` en **182** · los dos únicos consumidores
(`vista_np_sucursal` y el fetch de `index.html`) piden las columnas **por nombre**, así que
no se enteran · `lk_ppp_reader` ya tenía `UPDATE` sobre la tabla **y sobre las columnas
nuevas**, o sea que no hizo falta ningún grant.

**Medido antes, en LK:** `krikos_oc_inbox` existe (24 col) · `sync_pedidos_match_virgilio()`
existe · **0 de 1.025** pedidos con payload tienen `fecha_entrega`.

**Lo que falta, y es todo del lado LK:** mergear la rama, cargar `KRIKOS_IMAP_PASS` en el
Vault, exponer el campo en `v_pedidos_match` y copiarlo en `sync_pedidos_match_virgilio()`.
Hasta entonces las columnas quedan vacías. Después: consumirla en la PPP de Producción, y
en Gestión mostrarla en la tarjeta de "A Programar".

Detalle completo, con los pasos en orden, en `docs/PENDIENTES-PIPELINE-GESTION.md` §9357.

---

## 5. Pendientes

> 📌 La lista **de negocio** de lo que falta para cerrar el pipeline —la nota que dejó el
> dueño el 2026-09-04, cruzada con el estado real de cada pieza— está en
> **`docs/PENDIENTES-PIPELINE-GESTION.md`** (códigos 4990 · 9357 · 8808 · 9871 · 1439 ·
> 8033 · 1946). Lo de acá abajo son los pendientes **técnicos** de Supabase, y varios
> están referenciados desde ahí.

1. **Stock de los pedidos web.** `trg_normalizar_empresa_stock` (trigger de
   `Movimientos_Stock`, tabla compartida) completa la empresa de un movimiento con
   `empresa_de_np`, que no entiende las NP web. Hay que definir cómo entra el stock de un
   pedido web sin poner un trigger en una tabla compartida.
2. ⚠ **La exportación a ISIS de Gestión es un objeto NUEVO, no `isis_pedido_json`.** Esa
   función arma un informe del pedido TERMINADO (cajas pedidas vs entregadas vs faltantes,
   leído de `Facturacion_NP` + `Entregas_Virgilio` + `PPP_Base_Pedidos`) para que ISIS
   facture lo que realmente salió. Además hace `np::bigint` sacando los no-dígitos, así que
   una NP `LK 1343` viajaría como `1343`, sin prefijo. Al construir la de Gestión hay que
   decidir explícitamente si se manda **lo pedido** (formato de las páginas, más simple) o
   **lo entregado** (lo que hace hoy, y lo que evita facturar de más cuando hubo faltante).
2. Disparador de las 00:01 para `ppp_web_armar_tandas`: la función recibe las NP vivas
   por parámetro porque viven en LK y Virgilio no tiene FDW contra LK. Hace falta una
   Edge Function que lea LK y la llame, agendada por cron con prefijo `gv_`.
3. UI de las tres sublistas del módulo Facturación (el backend está: `vista_facturacion_estado`).
4. Conectar las NP web a `Facturacion_NP`. Nada lo bloquea —las columnas `np` son `text`
   y `validar_np_armada` sólo exige ítems armados— pero todavía no pasó ninguna.
5. En Chef (`nkhzocgdpwtgrmwleihr`, otra organización, sin acceso desde acá): borrar el
   rol `virgilio_reader` y su vista `v_virgilio_pedidos_feed`.
6. Padrón de LK: 20 clientes sin `zona_expreso` que no resuelven por localidad. Falta el
   dato de en qué barrio de CABA/GBA descarga el camión de cada uno.
7. Decidir si a futuro Gestión se muda a su propio proyecto Supabase. Da aislamiento real,
   pero obliga a resolver stock, planimetría y padrón, que hoy son compartidos.
