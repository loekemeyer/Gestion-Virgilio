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

### 3.cb ✅ Si esa tanda todavía no se tocó, el pedido va ADENTRO (v14.05) — 2026-09-07

**La corrección del dueño, textual:**

> *"Por el único motivo que pedí que el agregado de Osa se programe en una tanda nueva y no se
> incorpore a una actual, es porque la primera de Osa es pedido de ISIS y el agregado, del nuevo
> formato. Sólo en caso que ya se haya pickeado (o pasos posteriores), esa norma se mantiene en
> el futuro; si todavía ni se pickeó, el agregado se agrega a la tanda actual del cliente."*

**O sea: el corte es "¿ya se tocó?", no "¿es de ISIS o es web?".** La v13.93 (§3.ca) ya llevaba
el pedido al **día** en que el cliente tenía camión, pero siempre abriendo una tanda **nueva** —
así nació la `D66G` al lado de la `D66B` de Osa. Con esta versión, si la tanda que el cliente ya
tiene ese día está **intacta**, el pedido entra a **esa** tanda; si ya la empezaron, recién ahí se
abre la tanda nueva (el comportamiento v13.93, que queda como fallback).

**Qué cuenta como "tocada":** que exista en `Registros_Produccion_Virgilio` un evento **EP · TP ·
AP · TAP** con esa tanda. Verificado sobre los últimos 20 días: esos cuatro códigos guardan **el
código de tanda pelado** en `texto` (89 AP, 91 EP, 90 TP, 132 TAP, ninguno con `|`), así que el
match es directo; igual se miran los tres primeros segmentos del `|` por las dudas. CC/CCN no hace
falta mirarlos: no hay carga sin armado previo.

**Objeto nuevo:** `gv_ppp_web_tanda_abierta_cliente(p_empresa, p_cod, p_fecha)` → devuelve la tanda
del cliente ese día (mira las **dos** programaciones, web e ISIS, porque el caso que lo motivó es
justo una tanda de ISIS) que ningún operario tocó, o `null`. Revocada de `public`/`anon`.

**Dónde se engancha:** bloque **(a1)** de `gv_ppp_web_armar_pendientes`, antes del (a2). Escribe
**directo** en `PPP_Web_Programacion` con esa tanda; `ppp_web_armar_tandas` no servía porque su
`_open` sólo mira tandas **web** del día y la del caso es de ISIS. Lo que queda con tanda ahí,
(a2), (b) y (c) lo saltean solos por su filtro de "no programado".

**Medido (todo dentro de `begin … rollback`, 0 filas escritas):**

| caso | resultado |
|---|---|
| Osa 2533, `D66B` intacta | entra a **`D66B` · 09/09** (antes: tanda nueva) |
| `D66B` tocada (EP), `D66G` abierta | **`D66G` · 09/09** — no toca la pickeada |
| `D66B` y `D66G` tocadas | **`D66H` · 09/09** — tanda nueva, mismo camión 66 |
| cliente sin camión en la ventana | **`E03C` · 15/09** — cascada normal, intacta |

`gv_ppp_web_tanda_abierta_cliente('lk','2533','2026-09-09')` → `D66B`;
`('lk','4274','2026-09-04')` → `null` (la `D56D` ya está pickeada); `('lk','9999',…)` → `null`.

**Grep 0 en el repo de Producción** para `gv_ppp_web_tanda_abierta_cliente` y para
`gv_ppp_web_armar_pendientes`.

**Rollback:** `sql/backups/gv_ppp_web_armar_pendientes_20260907_pre_a1.sql` devuelve el armador a
la v13.93; después `drop function public.gv_ppp_web_tanda_abierta_cliente(text,text,date);` (no la
llama nadie más). Definición completa y comentada: `sql/gv_ppp_web_tanda_abierta_cliente.sql`.

**Aplicado al 1354 de Osa (mismo día).** El dueño, preguntado si juntarlas: *"me da igual"* → se
aplicó la regla. La `D66B` seguía con **0 eventos** de operario, así que el 1354 pasó de `D66G` a
**`D66B`**. La tanda del miércoles 9 queda con las tres NP del cliente: 98650 (2,710) + 98667
(1,331) de ISIS + `LK 0024` (0,026) de la web = **4,067 m³, un solo camión y un solo picking**.
`D66G` quedó vacía. **Ojo con el orden de los hechos:** más tarde la v14.09 de la otra sesión
renombró las tandas para que ningún camión quedara en dos días (`D66B` → `E09A`, `D66G` → `E09B`)
y ese renombre volvió a **separar** el 1354, que quedó solo en `E09B`. Se reaplicó la regla —la
`E09A` sigue con 0 eventos— y hoy las tres NP están en **`E09A`**. Verificado después del cambio:
**ningún número de camión en dos días** de hoy en adelante, así que lo de la v14.09 sigue en pie.
Rollback: `sql/backups/ppp_web_programacion_20260907_1354_pre_merge_d66b.sql` (incluye la adenda).

### 3.ca ✅ El pedido web se engancha al camión que YA va al cliente (v13.93) — 2026-09-07

**El caso.** Osa Distribuidora (cod 2533, Villa Lugano, Zona 1) tenía camión el miércoles 9 —
tanda `D66B`, 4,04 m³ en dos NP. Un pedido web del mismo cliente, de 0,026 m³, se programó solo
para el martes **15**, en camión aparte: 26 litros, seis días después, mismo cliente y mismo barrio.

**Dos causas, las dos de diseño.** (1) El colchón de 4 días hábiles tapaba el 9: un lunes 7 el
mínimo era el 11. (2) El automático **nunca miraba si el cliente ya tenía camión ese día** — sólo
cupo por día y cercanía entre las tandas de esa misma corrida, y la `D66B` es de ISIS. El cupo
tampoco lo dejaba: el 9 estaba en 7,03 m³ contra un cupo de 6.

**Las dos definiciones del dueño, textuales:** *pisa el colchón Y el cupo* (único modo que
resuelve el caso; el cupo mide picking y sumarle 26 litros a un cliente que ya tiene 4 m³
armándose ese día es casi gratis y ahorra un camión), y *"tiene que buscar para atrás, no para
adelante"* — la regla **adelanta** el pedido, nunca lo demora.

**Cómo quedó.** Función nueva `gv_ppp_web_dia_cliente(empresa, cod, desde, hasta)`: el día más
temprano en que ese cliente ya tiene entrega, mirando lo web y el espejo de ISIS, sólo días con
camión de reparto (exige `Zona N`, saltea `KRIKOS`) y separando por empresa (el cod es por
empresa: LK 2533 ≠ Chef 2533). Se engancha en el **bloque (a2)** de
`gv_ppp_web_armar_pendientes`, con ventana `[mañana … v_techo - 1]`, donde `v_techo` es el día
que elegiría la cascada — por eso sólo puede adelantar.

**No hizo falta código para pisar nada**: el colchón lo aplica el llamador, así que una fecha
explícita ya lo saltea; y pasar el cod en `p_forzar_cods` lo marca `prioritario`, que es la rama
del filtro de cupo que entra siempre. Con `p_incluir_manuales = true` vale para todas las zonas.
La v13.47 (§3.ao) ya hacía esto pero **por zona**; ésta es **por cliente**. El (a2) va **antes**
de la cascada (b) a propósito: lo que se programa ahí queda con tanda y (b) lo saltea solo.

**Probado en transacción revertida** (3 casos):

| cod | situación | resultado |
|---|---|---|
| 2533 Osa | camión el 09 | **D66G · 09/09** — adelantado |
| 3872 A L S.A | entrega el 14 | **E01A · 14/09** — adelantado del 15 al 14 |
| 4999 (inexistente) | sin entrega | **E03A · 15/09** — camino normal, sin tocar |

Rollback verificado: 0 filas de prueba, `PPP_Web_Programacion` quedó en 28.

**ROLLBACK**: `sql/backups/gv_ppp_web_armar_pendientes_20260907_pre_a2.sql`.
Fuente: `sql/gv_ppp_web_dia_cliente.sql`.

### 3.bz ✅ Borradas 20 filas de `CLIENTE SIMULACIÓN` de `Facturacion_NP` — 2026-09-07

Dueño: *"Elimina las 20 de cliente simulación"*, después de que se le explicara que
`Facturacion_NP` es tabla compartida con Producción y de ofrecerle la alternativa de sólo
filtrarlas en la vista.

**Qué eran.** `cod_cliente = 99999`, razón social `CLIENTE SIMULACIÓN`, tandas `SIM######`,
**m³ = 1,000 clavado en las 20**. Alguien probó la pantalla de Facturación el **lunes 31/08**
y los tics quedaron: entraron **de a una, con segundos de diferencia**, en dos tandas
(11:09–11:10, 8 filas; 11:39–11:40, 12 filas) — una persona tildando NP a mano, no un insert
masivo. Las 20 con `cierre_id` en NULL; las reales llevan cierre.

**Verificado que no eran reales** (no supuesto): 0 filas en `PPP_Programacion_Diaria`,
`PPP_Base_Pedidos` y `PPP_Web_Programacion`; 0 eventos en `Registros_Produccion_Virgilio`
(ni EP/TP/AP/TAP/CCN/CRN); 0 coincidencias en el código de Gestión **y de Producción**
(commit e15b682) — no las genera ninguna app; 0 con cierre.

**Por qué se vieron recién ahora.** La v13.62 (§3.au) cambió el universo de
`gv_ppp_en_salida` de "tiene CCN" a "facturada sin CRN". Estas 20 cumplían, y aparecían como
un renglón "Lun 31/8/2026 · 20 ped · 20,00 m³" — 20 m³ de ficción.

**Impacto medido:**

| | antes | después |
|---|---|---|
| `Facturacion_NP` | 1.187 | **1.167** |
| `gv_ppp_en_salida` — NP | 54 | **34** |
| `gv_ppp_en_salida` — m³ | 24,646 | **4,646** |
| filas de simulación visibles | 20 | **0** |

Controles después del borrado: `gv_ppp_entregados` 376, `gv_ppp_programacion_diaria` 182,
`gv_ppp_web_estado` 28 — sin cambios; 0 filas con `cod_cliente='99999'`, tanda `SIM%` o NP `9990%`.

Sentencia: `delete from public."Facturacion_NP" where cod_cliente = '99999';` (con `WHERE`
real: `supautils` bloquea `DELETE` sin `WHERE` para roles no superusuario).

**ROLLBACK**: `sql/backups/facturacion_np_20260907_simulacion_99999.sql` (los 20 INSERT).

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

### 3.bi ✅ `gv_ppp_tanda_mover`: mover una tanda de día desde la app (v13.87) — 2026-09-07 lunes

**Qué dijo el dueño.** Después de que la reprogramación del 2533 (§3.bh) hubiera que hacerla por SQL: *"esa
solicitud la tengo que poder hacer desde la app"*.

**El agujero.** La solapa Programación ya tenía "📅 Fecha de toda la tanda → Aplicar", pero `pppTandaFecha`
escribía en `pppLoadEdits`/`pppSaveEdits` = **localStorage**. El cambio no salía de ese navegador: el operario
seguía viendo la tanda el día viejo. Por eso mover una tanda de verdad era una tarea de SQL.

**Migración `gv_ppp_tanda_mover_v1387`.** `gv_ppp_tanda_mover(p_tanda text, p_fecha date, p_por text)` →
`(movidas, np_web, np_isis, m3, aviso)`. SECURITY DEFINER, execute a anon/authenticated, gate
`gv_es_supervisor_o_servicio`.
- **Tanda web** → `update PPP_Web_Programacion.fecha_entrega` + `PPP_Web_Tandas.fecha_entrega`.
- **Tanda de ISIS** → `insert … on conflict (np) do update` en `GV_PPP_Prog_Override`, con nota fechada y el
  legajo. **No toca `PPP_Programacion_Diaria`**, que es compartida. Se saltean las NP que ya resolvió la rama web.
- **Bloquea si la tanda está empezada**: `count(*)` de `Registros_Produccion_Virgilio` con
  `split_part(texto,'|',1) = tanda` > 0 → excepción con la cantidad de eventos. Es el chequeo que en §3.bh hubo
  que hacer a mano.
- Avisos del día destino (cupo por `gv_ppp_web_cupo` + `gv_ppp_web_m3_isis`, y día no hábil): se devuelven, no
  bloquean.

**Probado (`SET ROLE` no hizo falta: la lógica se probó con la función real).** D62A (súper, ya empezada) →
*"ya está empezada (23 evento(s) de operarios): no se puede mover de día"*. `ZZZZ` → *"No encontré la tanda"*.
D66F (NP 44605, Chef, 0,213 m³) jue 10 → vie 11 (aviso: el 11/09 queda con 10,288 m³ sobre el cupo de 6) y de
vuelta al jue 10; verificado en `gv_ppp_programacion_diaria` en cada paso.

**Front.** `pppTandaFecha` pasa a async: pregunta con la tanda, el día, cuántos pedidos y —si corresponde— el
aviso del segundo camión (`gv_ppp_web_camion_nuevo`), aclarando que "lo ven todos, también el operario en su
celular"; llama la RPC, muestra el aviso que vuelva y recarga con `pppLoadProgFromSupabase()`. Ya **no** escribe
en localStorage, ni siquiera si el backend rechaza. Test `tests/ppp-mover-tanda.cjs` (12 chequeos).

**Rollback.** `drop function public.gv_ppp_tanda_mover(text, date, text);` — el botón vuelve a fallar con el
error de la RPC inexistente (y no se pierde nada: no escribía en la base antes).

### 3.bh ✅ Datos: la tanda del 2533 se adelantó al miércoles — 2026-09-07 lunes

**Qué pidió el dueño.** *"La tanda del cliente 2533 adelantala para el miércoles y posterga lo del miércoles que
necesites al jueves."*

**Qué se movió** (todo por `GV_PPP_Prog_Override`, sin tocar `PPP_Programacion_Diaria`, que es compartida):
- **D66B** (Osa Distribuidora SRL "Chemelo", cod 2533, Zona 1 - CABA Sur, NP 98650 + 98667, 4,041 m³):
  jue 10/09 → **mié 09/09**. Vuelve a la fecha que tenía antes de la reprogramación del 06/09.
- Para hacerle lugar, el **camión de GBA Sur del miércoles entero** pasa al jueves (4,368 m³): D60F (98603),
  D60B (98534/98535), D60A (98494/95/96), D60C (98530). Se movió el camión completo y no sólo la tanda más
  grande para no partir un camión entre dos días.
- **No se tocó** D62A (súper La Anónima, 2,992 m³): es súper y además **ya está empezada** (EP/PKC/PSP/PUB/TP
  desde el 03/09). Tampoco D60E (Zona 5 - GBA Oeste, 0,214), que no hacía falta mover.

**Verificado antes de mover:** ninguna de las 4 tandas movidas tiene eventos en `Registros_Produccion_Virgilio`.

**Resultado.** mié 09: 7,574 → **7,247 m³** (súper 2,992 + GBA Oeste 0,214 + Capital 4,041, o sea D66B sola).
jue 10: 7,776 → **8,103 m³** (Capital 3,735 + GBA Sur 4,368). Los dos días ya venían por encima del cupo de
6,00 m³, así que no se pudo dejar ninguno en cupo moviendo entre ellos; sí quedaron parejos.

**Coletazo: D60E quedaba suelta.** El dueño lo vio enseguida (*"el de D60E, ¿no queda suelto? ¿cuánta distancia
hay entre D66B y D60E?"*). Con GBA Sur mudado al jueves, el miércoles le quedaba **D60E sola**: Betbeze Gimenez
Nahuel, Av. Luro 6099, **Gregorio de Laferrere** (La Matanza), 0,214 m³ — un camión de GBA Oeste entero para una
parada. Medido: **~13 km** en línea recta hasta D66B (Zuviría 5352, **Villa Lugano**); aproximado, porque hay geo
exacta de Betbeze (`GV_Geo_Cliente`, −34.749634 / −58.585982) pero no de Zuviría, así que se midió contra dos
puntos de Lugano que sí están (12,8 y 13,5 km). Sectores **B** (Capital Sur) y **M** (GBA Oeste): **no son
vecinos** (B linda con A, C, D, J; M con C, E, N), o sea que el armado nunca los junta. Dueño: *"pasala al
viernes 11"*, que ya tenía camión de GBA Oeste (E07A, 4,313 m³). Hecho con la RPC nueva `gv_ppp_tanda_mover`
—la misma que usa el botón de la app— : 2 NP, 0,214 m³. Quedó vie 11 GBA Oeste = **4,527 m³** (D60E + E07A) y el
mié 09 con Capital (D66B) + súper, sin camiones sueltos. Backup:
`sql/backups/reprogramacion_20260907_d60e_al_viernes.sql`.

**Rollback.** `sql/backups/reprogramacion_20260907_2533_al_miercoles.sql` (9 updates, deja todo como estaba
tras la reprogramación del 06/09).

### 3.bg ✅ `bot_customer_whatsapps` de LK vaciada: eran todos números de prueba — 2026-09-07 lunes

**Qué dijo el dueño.** Sobre el pendiente 6 (basura en la columna `empresa`): *"fueron wpp de prueba"*, *"209 y 217
también son de prueba"*, *"borralos"*.

**Qué había.** Las 5 filas de `public.bot_customer_whatsapps` (proyecto **LK**, `kwkclwhmoygunqmlegrg`), de mayo y
junio: 209 Pro Tatiana (4234), 217 Torres Y Liva (288), 218 Urriza Mariela (4197, con "Urriza Mariela" en la
columna `empresa`), 220 Lin Xiuhui (4260, ídem), 222 el 2º número de Lin Xiuhui (`cod_cliente` null). Ninguna era
de un cliente real.

**Por qué se borró y no se corrigió.** El trigger `orders_notify_whatsapp` de LK le manda un WhatsApp al cliente
cuando carga un pedido, usando esta tabla: con esas filas, un pedido real de cualquiera de esos 4 clientes le
habría mandado el aviso a un número de prueba.

**Hecho.** `delete … where id in (209, 217, 218, 220, 222)` → 5 filas, tabla en **0**. Backup completo (los 5
inserts, con `customer_id`, fechas y flags) en `sql/backups/bot_customer_whatsapps_20260907_pre_borrado.sql`; para
restaurar, ejecutarlo en LK y después poner al día la secuencia de `id` (la consulta está en el archivo).

### 3.bf ✅ Tanda hasta 1 m³ y aviso de segundo camión (v13.86) — 2026-09-08 martes

**Qué dijo el dueño.** *"Mínimo 0.6, máximo 1 m3, salvo pedidos de 1 solo cliente superiores a 1m3."* Y: *"si se
programa algo para un segundo camión para un mismo día (salvo que sea súper), debe pedirle confirmación: ¿seguro
que vas a usar un segundo camión?"*. Confirmado con él: vale para **todas** las tandas (no una zona), y por debajo
de 0,60 la tanda **sigue abierta** acumulando.

**(a) m³ — sólo config, sin código nuevo.** `PPP_Web_Config.tanda_m3_max_mezcla` **0,80 → 1,00**. La mecánica ya
estaba: `ppp_web_armar_tandas` v7 (v13.67) deja abiertas las tandas con `m3 < tope`, les suma clientes entre
corridas y las cierra al cruzarlo; un cliente cuyo pedido solo llega al tope (`m3_cli >= v_tope`) va solo con todo
lo suyo. Con el tope en 1,00 eso da exactamente lo pedido. `tanda_m3_min` (0,60) sigue siendo el piso deseable: la
tanda no se cierra por debajo, y a mano `aprConfirmar` pregunta (v13.84). Rollback: `update "PPP_Web_Config" set
valor = 0.80 where clave = 'tanda_m3_max_mezcla'`.

**(b) Segundo camión — migración `gv_ppp_web_camion_nuevo_v1386`.** RPC nueva
`gv_ppp_web_camion_nuevo(p_fecha date, p_filas jsonb)` → `(camion, ya_va, paradas, camiones_dia, es_super)`.
Resuelve el camión de cada parada con `gv_ppp_web_camion(zona, gv_ppp_web_sector(...))` —la misma etiqueta que usa
el armado para reusar camión (v13.60)— y lo cruza con los camiones que ya van ese día (`PPP_Web_Programacion` +
`gv_ppp_programacion_diaria`, sin súper/retira/expo ni KRIKOS). SECURITY DEFINER, sólo lee, execute a
anon/authenticated. Probada con `SET ROLE anon` sobre el 15/09 (3 camiones ese día): zona 1 → Capital `ya_va=true`;
zona 6 → GBA Norte `ya_va=true`; súper → `es_super=true`; día vacío (20/10) → `camiones_dia=0`.

**Front.** `aprConfirmar` la llama y agrega el aviso cuando hay alguna fila con `ya_va=false`, `es_super=false` y
`camiones_dia > 0`. No pregunta por el súper ni por el primer camión del día. Si la RPC falla, no traba.

**Efecto medido del tope nuevo** sobre las tandas ya programadas de hoy en adelante: con 1,00 quedan como "puede
recibir más" E01A del 14/09 (0,985 m³) y E03A del 15/09 (0,938) —con 0,80 estaban cerradas—; D69D (1,184, un solo
cliente) sigue cerrada; el resto (E01B 0,483 · E01C 0,577 · E01D 0,468 · E01E 0,267 · E01F 0,547 · D68G 0,105 ·
D69E 0,136) sigue abierto por debajo de 0,60, esperando más carga. Nada se reprogramó ni se movió: el tope sólo
decide cuándo una tanda deja de recibir.

**Rollback.** `drop function public.gv_ppp_web_camion_nuevo(date, jsonb);` — el front ignora el error y programa.

### 3.be ✅ La anticipación mínima avisa en vez de bloquear (v13.84) — 2026-09-08 martes

**Qué dijo el dueño** (sobre el paso 2 de A Programar): *"dejame programar si quiero para antes"*.

**El problema.** `gv_ppp_web_tanda_programar` cortaba con `raise exception 'El % es muy pronto…'` cuando la fecha era
anterior a `gv_ppp_web_dia_minimo()` (anticipación mínima de 4 días hábiles, `PPP_Web_Config.dias_anticipacion_min`,
v13.22). O sea: el supervisor no podía programar a mano para el martes aunque quisiera.

**Qué se hizo** (migración `gv_ppp_web_tanda_programar_anticipacion_avisa_v1384`). Ese `raise exception` pasa a
**aviso** (`aviso_dia`, que el front ya muestra), igual que el cupo excedido y el día no hábil, que nunca
bloquearon. Nada más cambia en la función.

**El armado automático NO se adelanta.** No usa esta validación para elegir el día: la fecha sale de
`gv_ppp_web_dia_minimo()` (job de las 00:01) y `gv_ppp_web_proximo_dia_entrega()` (intradía), que siguen intactas.
La anticipación mínima sigue siendo la regla para lo automático; ahora es sólo una advertencia para lo manual.

**Front (v13.84).** En A Programar sólo el día **no hábil** queda cerrado; "completo" y "muy pronto" se pueden
elegir y `aprConfirmar` pregunta antes de mandar (día antes del mínimo · día completo · tanda de menos de
`tanda_m3_min`). Si se dice que no, no se llama a ninguna RPC.

**Rollback.** Volver a la definición anterior (el `raise exception` en lugar del aviso).

### 3.bd ✅ La Anónima por LK (override por CUIT) y Cencosud en el checklist de ISIS (v13.79) — 2026-09-07 lunes (feriado)

**Qué dijo el dueño.** *"La Anónima se le vende por LK, no por CH. Cencosud desde CH se le venden artículos de LK creo,
ojo ahí, es similar a los de Tierra del Fuego."*

**LK (migración `gv_isis_override_la_anonima_v1379`).** Tabla **`gv_isis_override`** (`cuit` pk, `isis_empresa`
'lk'|'chef', `motivo`; RLS, select `authenticated`/`service_role`) con la fila `30506730038 → lk` (S.A. Imp. y Exp.
de la Patagonia, LK 771 / Chef 1804: tiene sucursal en Ushuaia, slot 6). `v_pedidos_web` reescrita con un CTE `base`
(mismas columnas y orden): `isis_empresa = coalesce(override, case provincia Tierra del Fuego → 'chef' else 'lk')`;
la L y el `cod_isis` salen de `isis_empresa`, no de la provincia. Medido: 1.483 NP, 4 TdF (384, 385, 1228 — las
mismas), pedidos de La Anónima (1293, 1077, 969) → `lk`, artículos sin L.

**Virgilio (migración `gv_fac_ajustes_isis_v2_cencosud_v1379`).** Cencosud (Chef 2444) no compra por la web: sus NP
de Chef entran por ISIS con artículos de Loeke **sin L** — 44609–44612 (03/09): 031, 501, 504, 513, 523, 546, 931E,
951E, 953E… (`sales_lines`: 931E → LK 13 líneas / 11 clientes, Chef 3 / 1; 505 → LK 10.065, Chef 71). El stock en
GV es correcto (código único → misma góndola; los duales 438E/439E ISIS ya los tipea con L). **`gv_fac_ajustes_isis`
v2**: entra además toda NP de Chef (`gv_empresa_de_np_texto = 'chef'`) con artículo en `precios_venta` y no en
`precios_venta_chef`; `articulos[].sin_l = true`, `art_ch = art_lk`. Ventana 60 días (con 90 eran 28, con NP de julio de Aimetta y South Naz —clientes de TdF— ya resueltas).
Medido (`SET ROLE anon`): 20 NP en el panel — 15 de Cencosud 2444 (16/07–06/08) y 5 de Dorinka 2686 (06/08–02/09);
las 44609–44612 del 03/09 entran cuando tengan armado en `Entregas_Virgilio`. Front: el
artículo sin L se muestra solo (`505 ×2`), la ayuda aclara "Cencosud va sin L".

**Datos (dueño 07/09, "tildalas todas como histórico").** Las 20 NP que mostraba el panel (15 Cencosud 16/07–06/08,
5 Dorinka 06/08–02/09, todas facturadas en Producción) se marcaron con los dos pasos en `GV_Fac_Ajustes_ISIS`,
`legajo = 'histórico (dueño 07/09)'` (40 filas, `on conflict do nothing`). El panel arranca vacío el martes. Para
deshacer: `delete from "GV_Fac_Ajustes_ISIS" where legajo = 'histórico (dueño 07/09)'`.

**Rollback.** LK: `delete from gv_isis_override where cuit = '30506730038'` (o `drop table` + vista v13.77).
Virgilio: vista v1 del bloque v13.78 de `sql/gv_fac_ajustes_isis.sql`.

### 3.bc ✅ Checklist manual de ISIS (ajuste − LK / + CH por NP con artículos L) (v13.78) — 2026-09-07 lunes (feriado)

**Qué dijo el dueño.** *"Cuando se va a facturar por Chef hay que: hacer ajuste negativo de stock de LK en ISIS
LK, y hacer ajuste positivo en CH, para que al facturar quede neteado. Y para vos en GV, descontá directo stock de
LK."* Es manual en ISIS; Gestión lleva el checklist.

**Migración `gv_fac_ajustes_isis_v1378`** (objetos nuevos, `sql/gv_fac_ajustes_isis.sql`):
- **`GV_Fac_Ajustes_ISIS`** (np, paso `lk_neg`|`ch_pos`, hecho_at, legajo; pk np+paso). RLS: select anon +
  authenticated; insert/delete authenticated (el front escribe con la sesión Google, `facAuthWriteHeaders`).
- **`gv_fac_ajustes_isis`** (security_invoker, select anon + authenticated): NP armadas con artículos `^[0-9]+E?L$` en
  `Entregas_Virgilio` (últimos 90 días, última fila por np+cod como el Excel), `articulos` = [{art_lk, art_ch,
  cajas}], `Facturacion_NP.facturado_at`, los dos pasos y `completo`.

**Impacto medido** (`SET ROLE anon`): 3 NP hoy — 44483 (C66A, 439EL ×15, facturada 07/07), 44600 (D58A, 439EL
×16, 02/09), 44601 (D58A, 438EL ×16, 02/09), todas de Dorinka 2686, ninguna completa. Sólo lectura de tablas
compartidas; nada de Producción tocado.

**Front (v13.78).** Panel `#facAjustesIsis` arriba de la lista de Facturación (`facAjustesIsisCargar`, cache 30 s,
llamado desde `facRender`; `facAjustesIsisToggle` hace POST `on_conflict=np,paso` / DELETE). **Stock en GV:**
`stockSalidaFacturadoNP` no drenaba de "a facturar" los artículos con L — el TAL dice `438EL` y la góndola
`438E LK` (medido: D58A|44601 drenó 097…922 y no 438EL/439EL) — ahora prueba `pkResolveArt` / `pkStripL` y
manda `empresa = LK` para la L. Es lógica del front porque los movimientos de stock los genera el front
(`stockMove`), como todo el módulo; el trigger `zz_normalizar_empresa` de Producción respeta la empresa explícita.

**Rollback.** `drop view gv_fac_ajustes_isis; drop table "GV_Fac_Ajustes_ISIS";` y el front oculta el panel si la
vista no responde.

### 3.bb ✅ Tierra del Fuego: pedido LK con L, Excel a ISIS Chef; regla `cliente_fc_lk` apagada (v13.77) — 2026-09-07 lunes (feriado)

**Qué dijo el dueño.** *"Buscá los clientes de Loeke que se entreguen en la provincia de Tierra del Fuego. Esos
son los que hay que lograr cruzar con cod de cliente de Chef."* Y sobre "no van": *"esos son los que el pedido se
arma como Loeke (con una L al final) y después va a ISIS de CH, no de LK"*. O sea: **"FC E" = Factura E** (área
aduanera especial). La emite Chef (`isis_ch.documentos`: 256 `FC Electr. E`; LK: 0 con letra E). La regla
v13.75/76 ("cliente con FC en LK → no se programa", 154 clientes) era otra cosa → **apagada**:
`update "PPP_Web_Config" set valor = 0 where clave = 'doble_lk_dias'` (dueño: "apagala"). El código v4 queda.

**Los clientes.** `customer_delivery_addresses.provincia = 'Tierra del Fuego'` (13 sucursales, 10 clientes LK):
490 Aimetta → Chef 2460 · 687 Domingo Granja → 2461 · 771 S.A. Imp. y Exp. de la Patagonia → 1804 · 1941 Alesso
Vilarino → 2600 · 2293 Il Cheff → 2465 · 2322 La Victoria → 2458 · 2528 Caticha → 2508 · 3831 El Martillo → 2643 ·
4207 South Naz → 2714 · 4245 Ferreyra → 2691. **Los 10 cruzan por CUIT** (`gv_clientes_lk_ch`). Chef les factura
FC E (2460: 70; 2465: 33; 2643: 26…); `sales_lines` de Chef muestra que compran artículos 5xx (de Loeke).

**LK (migración `gv_pedidos_web_tierra_del_fuego_v1377`).** `v_pedidos_web`: `art` lleva `L` al final cuando la
sucursal de entrega es de Tierra del Fuego (y no termina ya en L); columnas nuevas al final `isis_empresa`
('chef' / 'lk') y `cod_isis` (código del mismo CUIT en `chef_padron`; si no, el `cod_cliente`).
`v_pedidos_web_np`: propaga `min(isis_empresa)`, `min(cod_isis)` y pasa a **`security_invoker = true`** (no lo
tenía, aunque `sql/pedidos_web_lk.sql` lo documentaba: corría como dueño). `gv_pedidos_web_np_lk`: drop + create
con las dos columnas al final; grants iguales (`service_role`, `gv_reader`; sin anon/authenticated).

**Impacto medido.** 1.483 NP en la vista; **4 con `isis_empresa = chef`** (1228 Alesso Vilarino → 2600, 385
Domingo Granja → 2461, 384 Aimetta → 2460, todas con L: `026L,066L,…,438EL,502L,505L…`); 0 TdF sin `cod_isis`;
0 no-TdF con L; 0 no-TdF con `cod_isis ≠ cod`. Las 4 son anteriores a `gestion_desde`: hoy no cambia nada
programado. RLS: `set role anon` → permission denied; `set role authenticated` sin JWT → 0 filas. `virgilio_volumen_map`
tiene los `NNNL` (505L = 0,0024) → m³ bien. `gv_ppp_np_valor` ya valúa la L con la lista LK para cualquier NP.

**Gestión (front).** NP sigue **LK**, picking a la góndola Loeke (`pkEmpresaArt`: L → LK), PPP_Web_Base con `505L`,
Entregas_Virgilio crudo `505L`. Facturación: `_facXlsArmar` consulta `v_pedidos_web_np` (`isis_empresa=eq.chef`,
por `order_id`) y la NP va al **Excel de ISIS CHEF** con `cod_isis` y tope 15; `facXlsBajar` parte por `isisEmp` y
avisa "Tierra del Fuego: N NP … (1941 → Chef 2600)". Sin respuesta de LK, como antes. Edge Function: sin cambios
(las columnas nuevas viajan y se ignoran; la L llega en `items`). Test `tests/fac-tdf.cjs`.

**Rollback.** Bloque v13.77 de `sql/pedidos_web_lk.sql` (volver a las vistas sin las dos columnas y recrear
`gv_pedidos_web_np_lk`); el front ignora columnas que no vienen.

### 3.ba ✅ `cliente_fc_lk` por CUIT, no por código (v13.76) — 2026-09-07 lunes (feriado)

**Qué dijo el dueño** (sobre §3.az): *"el cod cliente no significa nada. Sólo el CUIT es lo que vale."*

**LK (migración `gv_cuits_de_chef_y_cuits_con_fc_lk_v1376`).** `gv_cuits_de_chef(p_cods_ch)` → CUIT (dígitos)
de cada código de Chef desde `chef_padron` (todos los clientes). `gv_cuits_con_fc_lk(p_cuits, p_dias)` →
`(cuit, ultima_fc, fcs, cods_lk)` desde `sales_lines` → `customers` (`cod_cliente` bigint → `::text`), sin
`sales_excluded_items`. Las dos SECURITY DEFINER, execute a `authenticated`/`service_role`/`gv_reader`, sin
`anon`. **Se dropeó `gv_clientes_lk_con_fc`** (v13.75, por código; la creamos nosotros ese mismo día, nadie más
la llamaba). Datos: en LK no hay CUIT con más de un código (`customers`), 9 clientes sin CUIT; en
`isis_lk.documentos` (180 días) ningún CUIT nulo ni con más de un código. `sql/gv_cuits_con_fc_lk.sql`.

**Virgilio (migración `gv_excluidos_cliente_fc_lk_por_cuit_v1376`).** `gv_pedidos_web_excluidos` v4: lee `cuit`
(dígitos) de cada pedido; `cliente_fc_lk` = pedido de Chef con CUIT y (`fc_lk ≥ fecha − doble_lk_dias` o
`isis_lk.documentos` `factura_venta` con `regexp_replace(contraparte_cuit,'\D','')` = CUIT y `fecha ≥ fecha −
doble_lk_dias`). `cod_alt` ya no interviene en este motivo; sigue en `en_produccion_lk`. Grants iguales.

**Impacto medido** (`SET ROLE anon`, fecha 04/09): 201 CUIT 30708108479 con `fc_lk` 22/08 → `cliente_fc_lk`;
206 (20115279751) y 208 (30717393240) sin `fc_lk`, FC 02–03/09 en `documentos` → `cliente_fc_lk`; pedido con
`cod_alt` 4044 pero sin CUIT → nada (antes sí); CUIT sin FC → nada; pedido LK → nada. `gv_cuits_de_chef` con
`SET ROLE gv_reader`: 2701 → 30717393240, 2715 → 30715209833, 2686, 2466 OK. `gv_cuits_con_fc_lk`: los 4 CUIT
del cartel con su última FC de `sales_lines` (22/08, 24/08, 23/03, 16/04) y su código LK.

**Front / Edge.** A Programar llama `gv_cuits_de_chef` + `gv_cuits_con_fc_lk` y manda `cuit` y `fc_lk`; el
cartel 🧾 muestra "CUIT …, LK …, FC dd/mm". Edge Function **v19**: lo mismo en `soloPendientes`, en un `try`
aparte del mapeo de códigos (si falla el CUIT, el backend decide con lo que tiene).

**Rollback.** `doble_lk_dias = 0` apaga la regla. Volver a v3 (bloque v13.75) y recrear
`gv_clientes_lk_con_fc` desde el bloque v13.75 de `sql/gv_cuits_con_fc_lk.sql` (git).

### 3.az ✅ "Los que le hacemos FC en LK no van": motivo `cliente_fc_lk` (v13.75) — 2026-09-07 lunes (feriado)

**Qué dijo el dueño** (sobre el cartel de 4 dobles de v13.72): *"no es problema que sean clientes de Loeke y de
Chef. Pero los que le hacemos FC E que le vendemos art de Loeke (buscá en sales_lines) son los que no van."*
"FC E" = FC Electrónica (así se llama el tipo en `isis_lk.documentos`: `FC Electr. A` 20.442). Decisiones
(AskUserQuestion): ventana **180 días**; regla en el **backend con dos fuentes**.

**LK (migración `gv_clientes_lk_con_fc_v1375`).** RPC **`gv_clientes_lk_con_fc(p_cods_lk text[], p_dias int)`**
→ `(cod_lk, ultima_fc, fcs)` desde `sales_lines` (`empresa = 'lk'`, sin `sales_excluded_items`). SECURITY
DEFINER, execute a `authenticated`, `service_role`, `gv_reader` (como `gv_cods_lk_de_chef`); sin `anon`.
`sales_lines` llega por **lote mensual** (`ago-26`, hasta el 31/08, importado el 02/09): las FC de esta semana
no están ahí todavía. Probado con `SET ROLE gv_reader`: 2517 → 22/08 (3 FC), 2183 → 24/08 (4), 1816 →
23/03, 4044 → 16/04. `sql/gv_clientes_lk_con_fc.sql`.

**Virgilio (migración `gv_excluidos_cliente_fc_lk_v1375`).** (1) `PPP_Web_Config.doble_lk_dias = 180`
(`insert … on conflict do nothing`; 0 = apagar). (2) **`gv_pedidos_web_excluidos` v3**: lee `fc_lk` de cada
pedido y agrega el motivo **`cliente_fc_lk`** para un pedido de Chef con `cod_alt` cuando `fc_lk ≥ fecha −
180` **o** hay `isis_lk.documentos` `factura_venta` del `cod_alt` con `fecha ≥ fecha − 180`. Pasa a
**SECURITY DEFINER** (`search_path = public, pg_temp`) porque `anon` no tiene select en `isis_lk` (sólo
`service_role`); los grants de execute quedaron iguales (anon, authenticated, service_role, PUBLIC). Los otros
cuatro motivos no cambian. `sql/gv_pedidos_web_excluidos.sql`.

**Impacto medido.** `SET ROLE anon` + los 4 del cartel con fecha 04/09: 201 (2517, `fc_lk` 22/08), 202
(2183, sin `fc_lk`), 206 (1816) y 208 (4044) → `cliente_fc_lk` (los dos últimos sólo por `documentos`: FC
02–03/09). Chef con `cod_alt` sin FC → nada; Chef sin `cod_alt` con `fc_lk` → nada; pedido LK → nada.
Alcance: **154 de los 357** pares `gv_clientes_lk_ch` tienen FC de LK en 180 días en `sales_lines`; 489 clientes
LK con FC en `documentos`. Nada de Producción tocado (`gv_pedidos_web_excluidos` es de Gestión; grep en el
repo de Producción: 0).

**Corrida en seco de la Edge Function v18** (pg_net, `{"dry":true,"forzar":true}`, req 16047, 200 OK): Chef 24
pedidos crudos → excluidos `cliente_fc_lk` 5, `en_produccion_lk` 4, `en_produccion` 19, `anterior_al_cambio` 21
(un pedido puede traer varios motivos); quedan 3 NP (215 Dorinka, 216 Elbantonio, 217 Gifel, sin código LK).
LK: 196 crudos → 23 NP, sin cambios.

**Front / Edge.** A Programar manda `fc_lk` (llama `gv_clientes_lk_con_fc` con `p_dias = 400`, la ventana la
decide el backend) y muestra dos carteles: ⚠ "ya está en ISIS LK (mismo día)" y 🧾 "clientes a los que LK
les factura artículos de Loeke … los tipea compras", con código LK y fecha de la última FC. Edge Function
**v18** hace lo mismo en `soloPendientes` (`fc_lk`); el log de la corrida cuenta `cliente_fc_lk` como motivo.

**Rollback.** `update "PPP_Web_Config" set valor = 0 where clave = 'doble_lk_dias'` apaga la regla sin
tocar código. Para volver del todo: v2 de la función (bloque v13.72 del SQL) y `drop function
public.gv_clientes_lk_con_fc(text[], int)` en LK.

### 3.ay ✅ Cruce Facturación vs ISIS: artículo `505L` valuado + pantalla desde Facturación (v13.73) — 2026-09-07 lunes (feriado)

**Qué.** Pendiente 10 del dueño ("cruce factura ISIS ↔ app como pantalla"; *"11 porque no? … ahí algo de eso
hicimos"*). El cruce ya existía (§3.aa, v13.10): `gv_vista_cruce_facturacion` compara el neto calculado con las
cajas entregadas contra el PDF de la factura que ISIS carga en `isis_lk.documentos` / `isis_ch.documentos`
(21.937 + 6.178 facturas de venta, todas con PDF, hasta el 04/09), buscada por cliente + fecha de salida ±3 días
+ cajas. Lo que faltaba era llegar desde Facturación y ver cajas / PDF. GestOpClientes no cruza importes: es el
aviso por WhatsApp (`lk_factura-check`, trigger `wa_factura_notificar`) que se dispara cuando `Facturacion_NP`
se marca facturada.

**Backend (migración `gv_cruce_facturacion_articulo_L_v1373`).** `gv_vista_facturacion_neto_items` (objeto
nuestro, `gv_`) valúa el artículo con "L" final de una NP de Chef (`505L`, `438EL`) con la lista LK por el código
pelado (regla v13.71). Antes buscaba `505L` en `precios_venta` → `sin_precio` → neto corto → "diff" falso.
Mismas columnas; `gv_vista_facturacion_neto` y `gv_vista_cruce_facturacion` no cambian. Sin grant nuevo (las
RPC `gv_cruce_facturacion_resumen` / `_totales` siguen SECURITY DEFINER con execute a anon/authenticated).

**Impacto medido.** Antes/después sobre toda la vista: conteo por estado **idéntico** (ok 460 · diff 157 ·
ambiguo 124 · sin_factura 80 · sin_neto 366). Sólo cambiaron las 3 NP con artículos L (`Entregas_Virgilio`
tiene 3 filas `438EL`/`439EL`, NP 44483, 44600, 44601): 44483 diff 1.873.710 → 365.760 (2 s/precio en vez de 3),
44600 1.444.912 → −163.567, 44601 2.040.131 → −770.748. Nada en `public.*` de Producción tocado (grep
`gv_vista_facturacion|gv_cruce_facturacion` en el repo de Producción: 0).

**Front.** Botón **🔍 Cruce con ISIS** en la barra de Facturación (`openCobros('cruce')`, que ahora acepta
cualquier pestaña), rango de fechas (default 30 días), totales del rango con `gv_cruce_facturacion_totales`,
columna cajas ent / fact, "n s/precio", 📄 abre el PDF con `createSignedUrl` (bucket `isis-lk` / `isis-ch`).
**Bug preexistente arreglado:** `_deudaState`, `_cruceState`, `_antState`, `_bancoState` eran `var` dentro del
closure `initAuth`, así que los `oninput`/`onchange` inline de las 4 pestañas tiraban `not defined` (buscar,
empresa, tramo, estado no hacían nada). Expuestos en `window`. Test `tests/fac-cruce.cjs`.

**Rollback.** Volver a la definición anterior de `gv_vista_facturacion_neto_items` (join por `cod_canon`,
`sql/gv_cruce_facturacion.sql` arriba del bloque v13.73).

### 3.ax ✅ Chef: vendedor propio, Excel partido, doble contra ISIS LK, RPC buena; alerta sin eventos (v13.72) — 2026-09-07 lunes (feriado, 04:30)

**Decisiones del dueño (07/09, por pregunta):** vendedor del padrón Chef · dos archivos ISIS LK / ISIS CH · detectar el doble
por CUIT y fecha · el cron de Chef sigue apagado.

**LK (`kwkclwhmoygunqmlegrg`), migración `gv_chef_admin_y_cods_lk_de_chef_v1372`:**
- `gv_pedidos_web_np_chef_admin(p_dias)`: `security definer`, candado `public.admins` por `auth.uid()` (igual que
  `get_pedidos_web_np_chef`), devuelve `gv_pedidos_web_np_chef` (con `direccion_expreso`, `np_total`, `v`). Grant a
  `authenticated`, `service_role`, `gv_reader`. El front (A Programar y `pppTraerPedidosWeb`) la usa en vez de la vieja.
- `gv_cods_lk_de_chef(p_cods_ch text[])` → `(cod_ch, cod_lk, cuit)` desde `gv_clientes_lk_ch`. Probado: 2701→4044,
  2393→2317, 271→288.

**Virgilio, migración `gv_excluidos_doble_lk_y_alerta_sin_eventos_v1372`:**
- `gv_pedidos_web_excluidos` v2: lee `cod_alt` de cada pedido y agrega el motivo **`en_produccion_lk`**: pedido `chef` con
  `cod_alt` no nulo y una NP `^9` en `np_prod` con `cod = cod_alt` y `PPP_Base_Pedidos.fecha = fecha_recep`. Medición:
  `{chef, 208, cod 2701, cod_alt 4044, fecha 2026-08-24}` → `anterior_al_cambio` + `en_produccion_lk` (el caso real de
  P&M Bazar, ISIS LK 98544/98545). Lo mandan la Edge Function v17 (`soloPendientes`, mapeo vía `gv_cods_lk_de_chef`) y A
  Programar (`aprTraerPedidos`), que además lista los dobles en un cartel rojo. Sin mapeo no se detecta, no se rompe.
- `gv_alerta_sin_eventos_telegram()` + **cron 76 `gv-alerta-sin-eventos`** (`30 13 * * 1-5` UTC = 10:30 ART): si el día es
  hábil (`gv_es_dia_habil`) y no hay eventos de operarios (legajo ∉ {0,1}) en `Registros_Produccion_Virgilio` hoy →
  `tg_enqueue` (dedup `gv_sin_eventos_<fecha>`) + `tg_outbox_flush`. Probado hoy (feriado): no encola. Apagar:
  `select cron.alter_job(76, active := false)`.

**Front (v13.72):** Excel ISIS → `_facXlsArmar` trae el `vend` de Chef por `order_id` (`gv_pedidos_web_np_chef_admin(60)`)
y `facXlsBajar` baja un archivo por empresa (`PEDIDOS_WEB_ISIS_LK_…` / `PEDIDOS_WEB_ISIS_CH_…`, xlsx y xls). Tests:
`fac-excel-isis`, `pweb-en-ppp`, `pweb-pendiente`, `apr-programar`.

**Rollback:** LK `drop function gv_pedidos_web_np_chef_admin, gv_cods_lk_de_chef` (y volver el front a
`get_pedidos_web_np_chef`); Virgilio reaplicar `sql/gv_pedidos_web_excluidos.sql` (v1) y `cron.unschedule('gv-alerta-sin-eventos')`.

### 3.aw ✅ NP web = contador propio, un número por bloque, sin sufijo (v13.70) — 2026-09-07 lunes (feriado, 03:00)

**Dueño:** *"el pedido tiene que ser único. No puede haber cuatro variantes de un pedido cuando se separa en cuatro.
Guardá el ID del pedido de la página, pero que sea un número de pedido diferente. No 1540-1, 1540-2, 1540-3."* → *"LK y
4 dígitos. No importa que no tenga relación con el ID de página."* Retroactivo sobre los 7 pedidos partidos (nada pickeado).

**Migración `gv_np_contador_sin_sufijo_v1370`** (repo `sql/gv_np_contador_v1370.sql`):
- `gv_ppp_web_np_label(p_empresa, p_np, p_np_idx)`: ignora `p_np_idx` → "LK 0001" / "CH 0003" (crece pasado 9999). Misma
  firma, así que `gv_ppp_web_estado`, `gv_ppp_web_entregados`, `gv_np_web_dobles`, `gv_ppp_np_valor`, `gv_ppp_web_prog_sin_base`,
  `gv_ppp_en_salida`, `gv_pedido_web_estado_pagina`, `gv_ppp_entregados`, `gv_ppp_web_tanda_programar`, `ppp_web_resync` y
  `gv_reconciliar_facturado_web` siguen sin tocar.
- `gv_ppp_web_np_asignar(p_empresa, p_pares)`: contador. `pg_advisory_xact_lock` por empresa; próximo =
  `greatest(PPP_Web_NP_Seed.desde, max(np)+1)`; inserta sólo los pares nuevos en orden (order_id, np_idx); devuelve todos.
  Idempotente (probado: `asignar('lk', [1351/1, 1350/4])` → 23 y 22, sin insertar).
- Índice único `ppp_web_np_empresa_np_uk (empresa, np)`.

**Datos (backup `sql/backups/np_web_20260907_pre_contador_v1370.sql`, 78 updates):** `PPP_Web_NP` 26 filas renumeradas por
`row_number() over (partition by empresa order by order_id, np_idx)`; `PPP_Web_Programacion.np` 25 filas; `PPP_Web_Base.np_label`
313 filas. Guardas: 0 NP web en `Facturacion_NP` y en `Entregas_Virgilio`; 0 eventos de operarios con texto `LK …`/`CH …`.
Resultado: LK 0001 (1340) … LK 0019–0022 (1350, 4 bloques), LK 0023 (1351); CH 0001–0002 (216), CH 0003 (217).
`gv_ppp_web_estado` y `PPP_Web_Base` coinciden (`prog_desync = 0`).

**Edge Function `gv-ppp-web-tandas-diarias` v16:** `npLabel` sin sufijo (copia del backend para la foto de artículos).
**Front:** `pwebNpLabel(e, np)` sin sufijo; `pwebPedidoLabel(e, order_id)` = "web LK 1350" para lo que no tiene NP (A
Programar: chip en la tarjeta, "Pedido web LK 1350 · sale en 4 NP", "bloque 2/4"; tandas sin fecha; filas de la PPP con `np`
null).

**Rollback:** ejecutar el backup, `drop index ppp_web_np_empresa_np_uk`, reaplicar `sql/gv_np_es_pedido.sql` §2–3 y redeployar
la Edge Function v15.

### 3.av ✅ La tanda ACUMULA hasta 0,80 entre corridas; crons 71/73 prendidos; 1352 borrado (v13.67) — 2026-09-07 lunes (feriado, 01:30)

**Pendientes unificados del otro chat (`docs/HANDOFF-EN-SALIDA-Y-TANDAS.md`), resueltos acá:**

1. **Acumular hasta 0,80** — `ppp_web_armar_tandas` **v7** (migraciones `ppp_web_armar_tandas_v7_acumula_v1367` y
   `_v7b_acumula_fix_v1367`; repo `sql/ppp_web_armar_tandas_v7_acumula.sql`). `_open` se siembra con las tandas web del
   mismo día y empresa que sigan abiertas (m³ < tope), de reparto, sin cliente 'solo' y sin ningún evento de operario
   (PK/PKC/EP/TP/TAP/AP/CC/CCN en `Registros_Produccion_Virgilio`); sus paradas van a `_open_stops`. Una tanda abierta
   recibe al cliente aunque cruce el tope, y ahí se cierra. Sin timeout. **Dueño 07/09: zonas automáticas quedan en
   `1,2,3`** (no sólo 1). **Medición** (`gv_ppp_web_armar_pendientes_simular('lk','2026-09-14', 3 pedidos zona 1,
   forzados al 14)`): Pompeya 0,30 → **E01C** (0,58 → 0,88, se cerró); Soldati 0,20 + Barracas 0,15 → **E01B** (0,48 →
   0,83). Cero tandas nuevas, cero filas escritas. Antes (v6) cada uno abría tanda propia.
   **Crons 71 (00:01) y 73 (intradía) vueltos a `active = true`** el 07/09 01:30 con el OK del dueño. Apagar:
   `select cron.alter_job(71, active := false); select cron.alter_job(73, active := false);`
2. **"Botón regenerar rearma todo"** — no existe tal botón (grep `regenerar|rearmar` en index.html: nada). El
   `actualizado_at = 2026-09-06 20:40:59` de las 26 filas fue la reprogramación por SQL de v13.60 (§3.at). Cerrado.
3. **8 NP con CCR sin CCN** (98474, 98509, 98585–98590) — dueño 07/09: *"el orden real es Control Remitos → Carga
   Camión → Recepción Remitos; se puede saltear el control si no llegan"*. No es anomalía: paso 1 hecho (03–04/09),
   paso 2 sin marcar. Chip v13.68 "✔ controlada · falta cargar". Lo ve el martes con los operarios.
4. **Pedido de prueba 1352 borrado** (dueño: *"sí, borralo"*). Backup restore-ready
   `sql/backups/pedido_prueba_1352_20260907_pre_borrado.sql`. Borrado en Virgilio (`PPP_Web_Programacion`,
   `PPP_Web_Base`, `PPP_Web_NP`: 1 fila cada una) y en LK (`orders` 1352, `order_items` 18876). `lk_pedidos_match`
   se limpia sola (cron ventana 14 días). E03B dejó de existir.
5. **Instructivo** `docs/PRIMEROS-DIAS-CON-GESTION.md` corregido a lo que dice la base (vie 11 = D67 + E07A; lun 14 =
   D68A–G + E01A–F; mar 15 = D69A–E + E03A).
6. **Basura en LK `bot_customer_whatsapps`** (columna `empresa` con razones sociales; `cod_cliente` null en el 2º
   número de Lin Xiuhui) — sin tocar, es del proyecto LK; a pedido.

### 3.au ✅ En Salida: fecha de carga, estado por NP y Recepción de Remitos embebida (v13.62) — 2026-09-07 (madrugada)

Dueño: *"El módulo En Salida tiene una estética completamente fea y le faltan datos. Quiero que
figure la fecha en la que se cargó el camión y el estado de cada nota de pedido, porque si no es
un módulo feo e inútil. El 2 del 9 veo que hay 0,04 m³ de una nota de pedido que hasta que no esté
confirmado tiene que quedar en salida. Lo mismo los del 3 del 9: el 98502 y el 98569 tendrían que
estar allá para que desde ahí se pueda manejar. Deberíamos integrar toda la lógica de recepción de
remitos para que la operadora administrativa lo labure desde el módulo de En Salida de la PPP, no
del módulo superior — el módulo superior dejarlo funcionando como ahora."*

#### 1) El universo estaba mal: exigía CCN

La vista v13.02 arrancaba de los eventos **CCN** (carga al camión). Las tres NP que nombró el dueño
están facturadas y armadas pero **nunca tuvieron CCN**, así que la vista no las podía ver: quedaban
fuera de Programación (fecha vencida), fuera de En Salida y fuera de Entregados.

| NP | cliente | tanda | m³ | entrega | eventos |
|---|---|---|---|---|---|
| 98665 | Merajver Marcelo Fabián | D50E | 0,042 | 02/09 | TAL (sin CCN) |
| 98502 | Clapera Alicia Raquel | D55B | 0,011 | 03/09 | TAL, AUB (sin CCN) |
| 98569 | Distribuidora Pezzali S.A. | D55A | 0,005 | 03/09 | TAL, FCO (sin CCN) |

**Regla nueva (elegida por el dueño): entra toda NP facturada sin CRN, con CCN o sin CCN.**
Implementada en el **backend**, `sql/gv_ppp_en_salida.sql`. `base` = CCN ∪ facturadas, o sea
estrictamente aditivo: nada de lo que se veía puede desaparecer (medido: **0 perdidas**).

**El filtro que no puede faltar**: `gv_ppp_entregados_meta` (la hoja de entregados). `Facturacion_NP`
es el histórico completo y el CRN existe recién desde el 05/09 (§3.r), así que sin ese filtro entraban
**356 NP** —todo lo facturado de siempre, entregado hace meses—. Excluyendo lo que la hoja ya da por
cerrado quedan **54**. Es el mismo criterio que ya usaba el front en `_pppConfirmadas()` (CRN ∪ hoja).

Medido al aplicarla: **54 filas** (antes 13) · 13 `cargada` + 41 `facturada_sin_cargar` ·
34 armadas · 24,6 m³ · 33 de septiembre, 20 de agosto, 1 del 29/07 · **0 perdidas vs v13.02**.

Columnas nuevas (al final, `create or replace view` no deja reordenar): `armada`, `armado_at`,
`cargada`, `control_previo`, `facturada_el`, `estado`, `dias_sin_controlar`.
Además se corrigió el FSS: si nunca hubo carga, `fss_at < ultima_carga_at` daba NULL y filtraba de
más; ahora un FSS sin carga saca la NP siempre.

**No toca Producción**: verificado contra `loekemeyer/produccion-virgilio` (commit e15b682),
**0 referencias** a `gv_ppp_en_salida`. Sigue con `security_invoker = true`.

#### 2) La pantalla: tabla propia en vez del render de Entregados

`_pppEnViajeHtml` reusaba `_pppEntGroupedHtml` (una línea de texto por NP, sin fecha de carga ni
estado) — de ahí lo de "fea e inútil". Ahora tiene tabla propia agrupada por día
(**NP · Cliente · Tanda · m³ · Cargado · Estado**), con la fecha y hora reales del CCN, `— sin carga`
cuando no lo hubo, y chips de estado: *Cargado al camión* / *Sin registro de carga*, *Armada* /
*Sin armar*, *Facturada*, *CCR sin CCN*, y *N días sin controlar* (ámbar a los 2, rojo a los 5).

#### 3) Recepción de Remitos embebida — SÓLO supervisores

Columnas **Controlado** (tildar → confirmar → emite **CRN** por NP → pasa a Pedidos Entregados) y
**↩** (**FSS**, el cliente no recibió y volvió al depósito). Reusa los mismos emisores del módulo de
arriba (`crSendDetail`, `crSendSinSalida`) con legajo `"0"`, igual que `openRemitosAdmin()`, así los
dos caminos escriben idéntico. **El módulo RR de arriba quedó intacto.** Gate: `window.__isSupervisor`;
el operario ve los datos pero no las acciones.

#### 4) Anomalía que destapó (de datos, no la arregla la vista)

**8 NP tienen CCR (control de remito antes de cargar) pero no CCN (carga al camión)**: 98474, 98509,
98585, 98586, 98587, 98588, 98589, 98590. O el operario saltea el CCN, o se está usando CCR en su
lugar. Se muestran con el chip `CCR sin CCN`. **Queda para revisar con el dueño.**

#### Verificación

`tests/ppp-ensalida-estado.cjs` (nuevo, 17 chequeos, verde): fecha de carga visible, `— sin carga`,
los cuatro chips, la NP sin CCN listada, el gate de supervisor en los dos sentidos, el botón que
cuenta lo tildado, y que el módulo RR de arriba siga existiendo. Más `checkhtml` y `smoke` verdes
(las 11 funciones nuevas agregadas a la lista del smoke).

**ROLLBACK**: `git show HEAD~1:sql/gv_ppp_en_salida.sql` y correrlo; front a v13.61.

### 3.as ⏸ Automático APAGADO: la tanda tiene que ACUMULAR hasta 0,80 (v13.59) — 2026-09-06 domingo (20:40)

Dueño: *"No se tiene que programar nada de manera automática, salvo que logremos que se vaya
programando y que hasta que se llegue a 0,80 o un poquito más —no hay problema que se zarpe un
poquito— ya se cierra la tanda y ahí sí no se agreguen nuevos pedidos a esa tanda"*.

**Hecho hoy (sólo esto):**

```sql
select cron.alter_job(71, active := false);   -- job de las 00:01
select cron.alter_job(73, active := false);   -- intradía cada 15 min
```

Para volver a prenderlos: los mismos dos con `active := true`. **No se tocó código todavía.**

#### El hallazgo que lo motivó — `_open` nace vacía en cada corrida

Verificado sobre la función **desplegada** (`pg_proc.prosrc`), no sobre el archivo del repo.
En `ppp_web_armar_tandas`, `_open` —la lista de tandas que pueden recibir un cliente más— es
una `temp table` que se crea vacía y sólo se llena dentro del mismo bucle:

```
create temp table _open (code text primary key, camion text, m3 numeric, cerrada boolean, seq int) on commit drop;
...
if v_code is null then ... insert into _open ... end if;
```

`PPP_Web_Programacion` se lee en dos lugares y en **ninguno** siembra `_open`: en el `where not
exists` que saca lo ya programado, y desde `gv_ppp_web_letra_y_camion()` para seguir la
numeración. O sea: **una tanda escrita en una corrida anterior nunca es candidata a recibir un
pedido nuevo.** Con el intradía cada 15 min y `intradia_umbral_m3 = 0,001`, cada pedido que entra
solo se lleva su propio camión.

Medido sobre las tandas web de hoy:

| corrida | tandas | clientes por tanda |
|---|---|---|
| 00:20 (varios pedidos juntos) | E01B, E01C, E01D | **2** |
| 16:15 y 20:30 (de a 1 pedido) | E03A, E04A, E05A, E06A, E08A | **1** |

#### Lo que NO era el problema

El caso que lo destapó fue Muller y Muller (Pompeya) yéndose a tanda propia teniendo
Distribuidora Cuyana (Soldati) el mismo día en la misma zona. **No fue la cercanía**: Pompeya y
Soldati están los dos en el sector `B` (`GV_Barrios_Sector`), y de hecho ya comparten tanda en
E01C. Fue la regla del dueño del 2026-09-04: Cuyana sola suma **0,938 m³ ≥ `tanda_m3_max_mezcla`
(0,80)** → `v_cierra := ... or r_cli.m3_cli >= v_tope` → **E03A nació cerrada** y no admite a
nadie. Eso funciona como está pedido; lo que falta es lo otro.

#### El botón de "regenerar" de la pantalla REARMA TODO

A las **20:40:59** el dueño lo tocó y las 26 filas de `PPP_Web_Programacion` quedaron con ese
`actualizado_at`. No agrega: recalcula el tablero entero, **renombra tandas y mueve fechas de
entrega** ya comunicadas. Los renombres de hoy: E02A→E01F, E04A→D68G, E05A→D69D, E06A→D69E,
E08A→E03B.

Y las fechas se corrieron del **vie 11 al lun 14 / mar 15**, con motivo: el 11 quedó en
`gv_ppp_web_m3_isis('2026-09-11')` = **10,075 m³ contra un cupo de 6**, porque el override de
Chango Mas (E07A, 4,31 m³, §3.ap) se cargó hoy a la tarde. La cascada de cupo hizo lo que tiene
que hacer. **⚠ El instructivo de `docs/PRIMEROS-DIAS-CON-GESTION.md` dice E01A–E01E el viernes 11;
hoy dicen lunes 14.** Sin resolver.

#### Pedido de prueba 1352 (Muller y Muller) — sigue vivo

Cargado a mano en LK para ver el circuito de punta a punta: 100 cajas de 505, 0,24 m³, entrega
"De L Americas 4384- Parana" → expreso Fontana, Pompeya → Zona 1. Hoy es la tanda **E03B**, 15/09.

Precauciones que se tomaron y conviene repetir si se hace otro:
- `sheets_sent = true` a mano, porque el cron `retry-sheets` de LK (jobid 1, cada 5 min) levanta
  todo lo que tenga `sheets_sent = false` y lo empuja al Google Sheet → ERP.
- Cliente sin fila en `bot_customer_whatsapps`, si no el trigger `orders_notify_whatsapp` le manda
  un "✅ Pedido recibido" real. Sólo 4 clientes de 1273 tienen teléfono cargado: 288, 4197, 4234, 4260.
- `detectar_pedidos_anomalos` saltea los cod_cliente 1 y 3878 (los de prueba); 862 no está en esa
  lista pero sacó score 0, así que no alertó.

Para borrarlo: `PPP_Web_Programacion`, `PPP_Web_Base`, `PPP_Web_NP` en Virgilio; `order_items` y
`orders` en LK. Backup de la fila de programación en
`sql/backups/ppp_web_programacion_20260906_deshacer_tandas_sub080.sql`.

#### Pendiente (decisión del dueño, ninguno hecho)

1. **Acumular hasta 0,80 y ahí cerrar** — backend, en `ppp_web_armar_tandas`: sembrar `_open` con
   las tandas ya programadas del mismo día que sigan abiertas, y marcar `cerrada` la que cruza el
   tope. Sin timeout: dueño dijo que en zona 1 siempre se llena, y las otras zonas se programan a
   mano por ahora.
2. Que el botón **sólo agregue lo pendiente** en vez de rearmar todo.
3. Qué se hace con las E01x: ¿quedan el lun 14 o se fuerzan al vie 11 aunque el día quede en ~13,5 m³?

### 3.ap ✅ Override de Gestión sobre una NP de ISIS: 44619 Chango Mas → E07A (v13.50) — 2026-09-06 domingo (16:45)

Dueño: *"Chango Mas, programalo"*. La 44619 (Dorinka / Chango Mas, súper, 4,31 m³, vie 11) estaba en
`PPP_Programacion_Diaria` con `tanda = ''`: ISIS la dejó sin tanda, el tablero no la mostraba en ningún camión
y el cupo no la contaba. La tabla es COMPARTIDA con Producción (no se modifica), así que se aplicó el patrón
de CLAUDE.md: **tabla `GV_PPP_Prog_Override`** (np pk, tanda, fecha_entrega, nota) + la vista que Gestión ya
lee, **`gv_ppp_programacion_diaria`**, la superpone (`coalesce(override.tanda, p.tanda)`, ídem fecha; mismas
columnas y tipos, `security_invoker`). `gv_ppp_web_letra_y_camion()` también cuenta los códigos del override.
RLS: select anon/authenticated; escribe sólo postgres/service_role por SQL. `sql/gv_ppp_prog_override.sql`.

**Medido:** la vista devuelve 44619 → E07A vie 11 · `letra_y_camion` = (4, 7) → próxima E08A · calendario
vie 11 = 10,88 m³ (7,45 ISIS + 3,43 web: pasado a propósito, el súper va en camión propio) · base 12 líneas /
589 cajas. Producción sigue viendo la fila cruda (tanda vacía). **Rollback:** `delete from "GV_PPP_Prog_Override"
where np = '44619'` (la vista queda; sin filas es passthrough).

### 3.at ✅ Un camión por día y zona + semana corrida un día hábil (v13.60) — 2026-09-06 domingo (22:30)

> Nombrada v13.60 porque la v13.59 la tomó el otro chat (§3.as: crons 71 y 73 apagados). Las migraciones quedaron
> con sufijo `_v1359` (ya aplicadas, no se renombran). Con los crons apagados, la regla de camión rige para el
> armado manual/simulado y para cuando se vuelvan a prender.

**Pedido del dueño:** *"el viernes 11 hay cinco camiones, no puede ser. El 14 veo cuatro. No tiene sentido que se
parta así los días de programación"* y *"si todos los del 8 todavía no fueron ni empezados a armar, pasemos los
del 8 al 9 y así vamos avanzando"*. Confirmó por pregunta: sólo D60 del martes (Coto y Carrefour ya armadas), todo
un día hábil salvo súper, los súper quedan.

**Causa de los camiones de más:** `ppp_web_armar_tandas` numeraba cada corrida con un camión NUEVO
(`_cam` arrancaba en `v_zn0 + 1`), así que el intradía abría E02, E04, E05, E06, E08 para pedidos de 0,1–0,5 m³
que tenían camión ese día. Camión = LETRA+NN (tablero `_pppTandaNum`, Producción, cuadro "Total por día").

**Cambio (migración `gv_ppp_web_camion_del_dia_v1359`, repo `sql/gv_ppp_web_camion_del_dia.sql`):**
- `ppp_web_armar_tandas` v6: con `sectores_activos = 1` y sin prefijo, antes del bucle carga en `_cam` los
  camiones que ya van a `v_fecha` (web `PPP_Web_Programacion` + ISIS `gv_ppp_programacion_diaria`, sin
  `tipo = KRIKOS` ni zona súper/retira/expo), con su letra (`base`), número y la próxima letra de tanda libre
  (`max(ti)+1`), agrupados por etiqueta `gv_ppp_web_camion(zona, sector)`; si una etiqueta tiene más de un
  camión, gana el que más paradas lleva. Una tanda nueva para esa etiqueta sale como `base||NN||letra`
  (E01F, D68G). Camión nuevo sólo si no hay: `greatest(max NN de la letra vigente en _cam, v_zn0) + 1`.
  Cada código pasa por `gv_ppp_web_codigo_tomado` en un loop (nunca repite).
- `gv_ppp_web_codigo_tomado` y `gv_ppp_web_letra_y_camion` miran también `GV_PPP_Prog_Override.tanda`
  (E07A vive sólo ahí; sin esto el próximo camión nuevo podía salir E07 otra vez).
- Bucle viejo por grupo (`sectores_activos = 0`) sin cambios.
- `gv_ppp_web_dia_camion` (migración `gv_ppp_web_dia_camion_sin_super_v1359`): un súper `tipo = KRIKOS` con zona
  numérica (E07A Chango Mas quedó como "Zona 5") ya no cuenta como camión a esa zona — la simulación mandaba un
  pedido de Morón al vie 11 como E08A por culpa de eso.

**Datos (backup restore-ready `sql/backups/reprogramacion_20260906_pre_v1360.sql`, 11 filas de override + 26 NP
web):** override `fecha_entrega` para 81 NP de ISIS (D60→09-09, D66→09-10, D67→09-11, D68→09-14, D69→09-15,
nota `v13.60 …`); `PPP_Web_Programacion.fecha_entrega` 19 NP 11→14 y 7 NP 14→15; renombres E02A→E01F,
E04A→D68G, E05A→D69D, E06A→D69E, E08A→E03B (ninguna tenía evento ni fila en `PPP_Web_Tandas`/`Tanda_Items`).
Súper sin tocar: D59A, D61A (mar 8, armadas), D62A (mié 9), E07A (vie 11). Matiz D71A (mié 16) sin tocar.

**Medición (misma consulta antes/después, camiones = `left(tanda,3)` por día, web + ISIS):**

| día | antes | después |
|---|---|---|
| mar 8 | D59 D60 D61 (3) · 13,45 | D59 D61 (2) · 8,87 |
| mié 9 | D62 D66 (2) · 10,77 | D60 D62 (2) · 7,57 |
| jue 10 | D67 (1) · 5,76 | D66 (1) · 7,78 |
| vie 11 | D68 E01 E02 E04 E07 (5) · 10,88 | D67 E07 (2) · 10,07 |
| lun 14 | D69 E03 E05 E06 E08 (5) · 3,77 | D68 E01 (2) · 6,58 |
| mar 15 | — | D69 E03 (2) · 4,01 |

**Rollback:** ejecutar el backup (deja fechas y códigos como estaban; las 81 filas nuevas del override se borran
con `delete from public."GV_PPP_Prog_Override" where nota like 'v13.60%'`) y reaplicar
`sql/gv_ppp_web_armar_pendientes.sql` §3 y §4 (funciones v5).

### 3.ar ✅ Sólo Recepción de Remitos (CRN) = entregado; vuelve atrás v13.27 (v13.57) — 2026-09-06 domingo (20:30)

Dueño: *"Todos los de recepción de remitos deberían estar en 'En salida'"*. El modelo de siempre (GUIA v3.69):
**CR = Control Remitos (`CCR`) es el control del remito ANTES de cargar**, **CC = carga (`CCN`)**, **RR =
Recepción Remitos (`CRN`) = el remito volvió firmado = entregado**. En v13.27 (§3.aj) había hecho contar `CCR`
como controlado y con eso En Salida quedó en 0 y 448 NP pasaron a "entregados" sin que el remito hubiera
vuelto. Migración `gv_ppp_en_salida_solo_crn_v1357`: `gv_ppp_en_salida` y `gv_ppp_entregados` vuelven a
`opcion = 'CRN'` (parche `replace()` sobre `pg_get_viewdef`, `security_invoker = true` conservado); el
fallback del front (`pppRefreshControlado`) también (`opcion=eq.CRN`).
**Medido:** En Salida **0 → 13** (los cargados el viernes 4/9 por legajo 8: D55D ×4, D56B ×5, D56E ×2, D54B
98551, D53F 98602 — los mismos 13 del agente `carga_sin_control`); entregados 824 → 376; vencidos en Resumen
20 → 51 (13 en salida + el resto con CCR/CCN sin CRN, o sin nada). Rollback: volver a `ANY(ARRAY['CRN','CCR'])`
(§3.aj).

### 3.aq ✅ Canilla ABIERTA + dobles del mail del sábado ocultos (v13.51) — 2026-09-06 domingo (17:30)

El dueño mandó el Excel PPP vigente (`AAA_PPP_Vigente.xlsm`). Cruzado contra Supabase:
- **Facturación**: las 59 `Fecha Fc` del Excel (02/09, 03/09, 04/09) coinciden una por una con los tics de
  `Facturacion_NP` (mismo día). Las 6 FC del viernes 04/09 en ISIS (400035804–809: 98484 Vargas, 98461 Sun
  Yung Hung, 98464/98465 MRG, 98646 Zhu Leo, 98513 Fang Chiao Wen) están tildadas el viernes 16:01–16:12 (+44594).
  En el Excel 5 de esas 6 todavía no tienen `Fecha Fc` (la app va adelante). Ninguna `Fecha Fc` ni tic del
  sábado 05/09 (normal). "11:00HS" / "12:00hs" en `Fecha Fc` de 98685 y 98647 son horarios de entrega mal
  puestos, no facturas.
  **⚠ Falsa alarma del domingo 06/09, mía:** durante todo el día etiqueté el 4/9 como "jueves" y el 5/9 como
  "viernes" y le dije al dueño que "el viernes no llegó ningún evento de Producción". El 4/9 era **viernes**
  (46 eventos de operarios, 581 movimientos, 6 tics) y el 5/9 **sábado**. No se perdió nada; §3.ai y las
  notas de v13.46 sobre "el viernes" se refieren en realidad al jueves 3/9 y viernes 4/9. La FC PYME
  500000906 (Carrefour, 03/09) es la 98115 de julio, no la 98619. Runbook para cuando pase de verdad:
  `docs/RUNBOOK-EVENTOS-PERDIDOS.md`.
- **NP por encima del corte de la canilla (98694 / 44619)**: 98696–98703 y 44620/44621 = **el mail del sábado
  12:30 cargado en ISIS** (1343 Chen Li Yu ×3, 1344 Torres y Liva ×2, 1340 Garbarino, 1341 Orfali, 1342 Di Leo;
  Chef 216 Elbantonio ×2) — sin tanda ni fecha; dobles de E01E/E01A/E05A/E01D/E02A y de Garbarino (a mano). Y
  **98704 Salvetti Angel Hernan, D60G, mar 8** = pedido nuevo de ISIS que Gestión NO veía por la canilla.

**Hecho (migración `gv_ppp_prog_override_oculto_canilla_abierta_v1351`, `sql/gv_ppp_prog_override.sql`):**
canilla **abierta** (`espejo_np_corte_lk/_chef = null`; Gestión ve todo lo que ISIS numere) + columna
`oculto` en `GV_PPP_Prog_Override`, filtrada en las tres vistas del espejo y en `gv_pedidos_web_excluidos`
(una NP oculta no cuenta como "en producción"). 10 filas ocultas (las de arriba). Medido: corte (null, null),
10 ocultas, `gv_pedidos_web_excluidos` para 1340/1343/216 → nada (siguen siendo de Gestión), 215 →
en_produccion (44619, correcto). El espejo de Supabase todavía no tiene las 98696+ (la hoja de Google va
atrás del Excel): cuando lleguen quedan ocultas solas y Salvetti aparece en D60G.
**Pendiente del dueño**: qué hacer en ISIS con las 10 NP dobles (anular) y que la operadora no cargue
1345–1349. Rollback: `update "GV_PPP_Prog_Override" set oculto = false where oculto` y volver el corte a
98704/44621.

### 3.ao ✅ "Mandá directo a Programación si ya está. No más en A Programar" (v13.47) — 2026-09-06 domingo (tarde)

Dueño, viendo A Programar con 4 pedidos que decían *"🤖 se arma solo → lun 14/9"* y *"🚚 hay camión el
lun 14/9 · programalo"*: *"Mandá directo a Programación si ya está. No más en A Programar."*

**Antes:** el job (00:01) y el intradía armaban UNA fecha por corrida (`ppp_web_armar_tandas(p_fecha)`):
lo que no entraba por cupo quedaba en A Programar con pronóstico hasta la corrida que cayera en ese día
(Cuyana 1350 esperaba al lunes 07 para el lunes 14). Y las zonas manuales (4/5/6/7) nunca se armaban
solas aunque hubiera camión a la zona ese día: esperaban a una persona.

**Ahora (migración `gv_ppp_web_armar_pendientes_v1347`, `sql/gv_ppp_web_armar_pendientes.sql`):** en cada
corrida se programa TODO lo que tiene día previsible.
- `gv_ppp_web_armar_pendientes(p_empresa, p_fecha, p_filas, p_forzar jsonb)` — la cascada. (a) forzados con
  fecha (`[{cod, fecha}]`: Chef al día en que entró la misma razón social por LK); (b) zonas automáticas:
  `gv_ppp_web_proximo_dia_con_cupo(desde)` → `ppp_web_armar_tandas` → lo que quedó, al siguiente día con
  cupo, hasta 8 días por corrida; (c) zonas manuales "Zona N": `gv_ppp_web_dia_camion(zona, dia_minimo)` =
  primer día ≥ día mínimo con una tanda (web o ISIS) de esa zona → `ppp_web_armar_tandas(…, p_incluir_manuales
  = true)` con esos clientes como prioritarios (el camión ya va: no esperan cupo). Retira, Súper y sin zona
  siguen a mano. Devuelve `(r_fecha, r_tanda, r_zona, r_np_count, r_m3, r_clientes, r_cods)`.
  `gv_ppp_web_armar_pendientes_simular(...)` = lo mismo sin escribir.
- `ppp_web_armar_tandas` pasa a 5 args (`p_incluir_manuales boolean default false`; la de 4 se dropeó,
  backup en `sql/backups/ppp_web_armar_tandas_20260906_pre_v1347.sql`). **Numeración como Producción**:
  `gv_ppp_web_letra_y_camion()` da la letra vigente y el último nº de camión, y la función sigue esa cuenta
  (E01A → E02A → …, pasa de letra en el camión 99) en vez de tomar una letra nueva por llamada (antes cada
  corrida quemaba una letra; con varias fechas por corrida se acababa el abecedario en un mes). Como el
  domingo ya existía F01A (Chef, letra nueva de la regla vieja), las próximas salen **F02A, F03A…**
- `gv_ppp_web_proximo_dia_entrega(ahora)` = `gv_ppp_web_proximo_dia_con_cupo(gv_ppp_web_dia_minimo(ahora))`
  (misma regla, una sola implementación).
- Edge Function `gv-ppp-web-tandas-diarias` **v15**: llama a `gv_ppp_web_armar_pendientes`; encadena Chef
  con `forzarChefDe(codFecha)` (cod_ch → la fecha en que entró el cod_lk, no la de la corrida); el intradía
  arma también si hay algo de zona manual con camión aunque el pendiente automático no llegue al umbral.
- **Cron 73 (intradía) corre TODOS los días 06:00–20:45 ART** (`*/15 9-23 * * *`; antes lun–vie
  07:00–18:45): el dueño programa un domingo a la tarde y quiere ver los pedidos irse de A Programar. La
  fecha objetivo la elige el backend (siempre hábil).
- Front: chips de A Programar *"🤖 se arma solo → lun 14/9 · en minutos"* / *"🚚 va al camión del vie 11/9
  · en minutos"*; la línea de motivos dice *"N los programa solo el automático en minutos"*.

**Medido (simulador, domingo 16:10, antes de la corrida real):** LK 1349 Bazar Mónica (zona 5, 0,105) →
vie 11 F03A (camión D68E/F a la zona 5; el viernes ya está en 6,47/6, entra como prioritario); 1350 Cuyana
(zona 1, 0,938) → lun 14 F02A; 1341 Orfali (zona 6, 1,184) → lun 14 F04A (D69C a la zona 6); 1340 Garbarino
(Retira) queda en A Programar. Chef 217 Gifel (zona 6, 0,136) → lun 14. `gv_ppp_web_letra_y_camion()` =
(5, 1) = F01.
**Corrida real: la hizo sola el cron 73 a las 16:15:00** (recién ampliado a domingos, con la Edge Fn v15
deployada 16:12): `PPP_Web_Programacion` +7 filas a las 16:15:11 — F03A 1349 Bazar Mónica vie 11 ·
F02A 1350 Cuyana (4 NP) lun 14 · F04A 1341 Orfali lun 14 · F05A CH 0217 Gifel lun 14 — todas con
la foto en `PPP_Web_Base` (16 + 60 + 15 + 1 líneas). Calendario: vie 11 = 6,57 m³ (3,14 ISIS + 3,43 web,
pasado por el forzado de zona 5, a propósito), lun 14 = 3,77 (1,51 + 2,26). En A Programar queda sólo 1340
Garbarino (Retira).
**Bug encontrado de paso (v13.47b):** ninguna corrida intradía dejaba renglón en `GV_Tandas_Auto_Log`: la
Edge Fn escribe `estado = 'intradia_ok' / 'intradia_sin_umbral'` y el check de la tabla sólo admitía
ok/salteada/error → 400 en el insert (visto en edge_logs; el `try/catch` del log lo tapaba). Nunca había
corrido un intradía real (cron lun–vie, creado el sábado). Migración `gv_tandas_auto_log_estados_intradia_v1347b`
amplía el check. El cartel verde de A Programar ("Último armado automático") lee ese log.
**v13.49 (16:35, dueño: *"las letras no se cambian por día. E tiene que llegar hasta E99 para pasar después
a F"*):** la regla nueva ya seguía la cuenta, pero el F01A de Chef (creado a las 00:20 con la regla vieja)
había abierto la letra F y todo siguió en F. **Renombradas en `PPP_Web_Programacion` (9 filas, sin eventos ni
items ni ISIS que las nombren): F01A → E02A (Chef 216, vie 11), F02A → E03A (Cuyana), F03A → E04A (Bazar
Mónica, vie 11), F04A → E05A (Orfali), F05A → E06A (Gifel).** `gv_ppp_web_letra_y_camion()` = (4, 6) → la
próxima es **E07A**. Y `gv_ppp_web_tanda_codigo_nuevo()` ("Nueva tanda vacía") también tomaba letra nueva:
migración `gv_ppp_web_tanda_codigo_nuevo_misma_letra_v1349`, ahora sigue la misma cuenta (próximo camión
de la letra vigente). Rollback del rename: el `update … case` inverso.

**Rollback:** al final de `sql/gv_ppp_web_armar_pendientes.sql` (cron 73 a `*/15 10-21 * * 1-5`, drop de las
funciones nuevas, restaurar la de 4 args desde el backup, redeployar la Edge Function v14).

### 3.añ ✅ Correcciones de dirección para geocodificar, sin tocar ISIS (v13.41) — 2026-09-06 domingo

Dueño: *"sí, dale. Ambas"* — que se corrija en ISIS **y** que Gestión tenga su propia corrección para
no depender de eso. De las 64 direcciones programadas quedaron 16 sin ubicar y **todas** eran cómo las
escribe ISIS: `PEGAMINO 3751` (Pergamino), `Chilavet M Cnel.` (Coronel Martiniano Chilavert),
`Ohiggins` (O'Higgins), `Pacifico Rodrigrez` (Pacífico Rodríguez), `B DE ASTRADA` (Berón de Astrada),
`AV. INT. RAVANAL` (Rabanal)… El geocodificador no adivina, y no debe: una dirección inventada manda el
camión a otro lado. Por eso la corrección es un **dato cargado y revisable**, no una heurística.

**`GV_Geo_Correccion`** (`sql/gv_geo_correccion.sql`, migración `gv_geo_correccion_v1341b`): por
`dir_key` de la dirección **mal escrita**, cuál es la buena (`direccion_ok`) y, si hace falta, el
barrio (`barrio_ok`). `gv_geo_faltantes` la aplica y entrega `dir_query` y `barrio_geo` ya corregidos,
más `corregida` para poder auditarlo; la Edge Function no sabe nada de correcciones.

⚠ **Se usa SÓLO para preguntarle al geocodificador.** La dirección que ve el operario, la que se
imprime en la etiqueta y la que viaja a ISIS siguen siendo las de ISIS: ni una fila de
`PPP_Programacion_Diaria` se toca.

Cargadas las **11 aprobadas por el dueño** (10 de la lista + `CHUTRO 2735` del cód 1562, el mismo caso
que 2336). Resultado: **de 16 sin ubicar quedaron 6**, y las 11 correcciones ubicaron. La de Carrefour
necesitó una vuelta más: `Otto Krause 5108, Tortuguitas` no aparece, pero sí con el **partido**
(`Malvinas Argentinas`) — vale como regla para el GBA cuando la localidad chica no la conoce el mapa.
Las 6 que siguen son direcciones que nadie sabe
resolver todavía y están esperando al dueño: 732 Bertola *"Trole 163"*, 771 La Anónima *"Km 10, Au
Camino del Buen Ayre"* (sin altura), 888 Pezzali *"La Salle 2174"* y 1821 Sendra *"Av. La Salle 1923"*
(los dos en Flores), 4114 Extralimp *"J. M. Pérez 977"* (Luján) y 2466 Elbantonio *"I. Catolica 6"*
(Río Cuarto, Córdoba — es de Chef).

Para agregar una corrección nueva, la receta está al pie de `sql/gv_geo_correccion.sql`.

**v13.42 — quinto intento: la calle sola.** El dueño mostró en Google Maps que *"Trole 163"* existe
(Parque Patricios, C1437DKC); es OpenStreetMap el que no tiene esa altura. Cuando los cuatro intentos
fallan y la dirección termina en número, se pregunta por la **calle sin el número** con el barrio
(`street=Trole&city=Parque Patricios`), y si sale queda con **`GV_Geo_Cliente.precision = 'calle'`**
(migración `gv_geo_cliente_precision_v1342`; valores `exacta` / `calle` / `manual`). El log lo cuenta
aparte (*"N por la calle (sin altura en OSM)"*, detalle `por_calle`). Sin barrio no se intenta: una
calle sola sin barrio es cualquier lado. Auditarlas:
`select cod, razon_social, direccion, barrio from public."GV_Geo_Cliente" where precision = 'calle';`

**⚠ Y la verificación de barrio que hizo falta el mismo día.** La primera corrida con el quinto
intento ubicó *"J. M. Pérez, Luján"* en **"José María Pérez de Urdininea", Ezeiza — a 50 km**. El
`viewbox` de Nominatim es un sesgo, no un límite. Un pedido ubicado **mal** es peor que sin ubicar
(el camión lo ordena en un lugar que no es), así que: (1) borré esa fila de `GV_Geo_Cliente` y la de
`PPP_Geo` — las dos eran **mías, de un minuto antes**, no datos de Producción; (2) los intentos 3, 4
y 5 (los que preguntan con menos contexto) ahora **exigen que el resultado caiga cerca del barrio
pedido**. La primera verificación fue por nombre (¿algún componente de la respuesta dice "Luján"?) y
**también falló**: en Laferrere hay un barrio *"Villa Luján"* y con eso pasó. La que quedó es
**geográfica**: se ubica el barrio pedido una vez por corrida (`centroBarrio`, con cache, por
búsqueda **estructurada** `city=` + `state=Buenos Aires` — la búsqueda libre "Luján, Buenos Aires"
devolvía algo a 24 km de la ciudad: un río o un barrio que se llama así) y el resultado tiene que estar a **≤ 20 km**
de ese centro (`RADIO_KM`; un partido grande del GBA cabe). Si el barrio no se puede ubicar, no hay
contra qué verificar y el intento se descarta: **falla cerrado**. Motivo en el log: *"cayó a N km de
…"*. Los intentos 1 y 2 llevan barrio + "Buenos Aires" y ubicaron bien 47 de 47, así que quedan como
estaban. Las 10 correcciones del dueño cayeron todas donde deben (verificado una por una: Jufré en
Villa Crespo, Chilavert en Lugano, Otto Krause en Tortuguitas, O'Higgins en Pilar…).

*"Trole 163"* no está en OSM ni como "Trole" ni como "Pasaje Trole": para ésa hace falta la
coordenada a mano (`precision = 'manual'`), que se le pidió al dueño desde Google Maps.

**v13.43 — Chef: la dirección de entrega, no la sucursal del cliente.** Dueño: *"los de Chef
probablemente estés poniendo la dirección de su sucursal en lugar de la dirección de entrega
nuestra"*. Exacto: `gv_pedidos_web_np_chef` (proyecto **LK**, `kwkclwhmoygunqmlegrg`) devolvía
`direccion` = `sheets_payload.sucursal_entrega` (*"I. Catolica 6- Rio Cuarto"*) y `direccion_expreso`
= `null::text`, siempre — así que la Edge Function no armaba el *"Exp. — …"* y Gestión geocodificaba
Río Cuarto. Chef **sí** guarda adónde va nuestro camión: `chef_customer_delivery_addresses.
direccion_entrega` (*"Pergamino 3751"* para Elbantonio = el expreso en Soldati; *"Hilarion De La
Quintana 2150"* para Gifel = entrega local en San Martín). Migración
`gv_pedidos_web_np_chef_direccion_entrega_v1343` (LK), SQL en `sql/gv_pedidos_web_np_chef_v1343.sql`:
con **intermediario** (hay `nombre_expreso`, o la provincia no es Buenos Aires/CABA) `direccion` =
sucursal del cliente y `direccion_expreso` = `direccion_entrega` — la Edge Function arma
*"Exp. — Pergamino 3751 (I. Catolica 6- Rio Cuarto)"* y `gv_dir_geo_query` se queda con *"Pergamino
3751"*; **entrega local** → `direccion` = `direccion_entrega` (la limpia) y `direccion_expreso` = null.
Verificado sobre 60 días: 74 filas, 0 sin dirección, 44 con expreso. Para el pedido 216 ya programado
(dirección vieja en `PPP_Web_Programacion`) se cargó una corrección → *"Pergamino 3751", Villa
Soldati*. Y el chequeo de distancia del geocodificador pasa a **todos** los intentos: una dirección
lejos del barrio nunca es punto de entrega, no importa cómo se preguntó.

**v13.44 — `ppp_web_resync` no actualizaba la dirección.** El dueño volvió sobre lo mismo (*"nosotros
no entregamos en Río Cuarto"*) porque en la app seguía viendo la sucursal en el 216 ya programado.
Causa: `actualizadas` sólo disparaba si cambiaba m³ / líneas / cajas / `m3_parcial` — el SET ya traía
`direccion` y `barrio`, pero un cambio de dirección solo no entraba. Migración
`ppp_web_resync_actualiza_direccion_v1344`: la dirección y el barrio también disparan (sólo si el feed
los trae; null no pisa, igual que el `coalesce`). Producción no usa `ppp_web_resync` (grep: 0 hits).
El 216 se refrescó a mano llamando al resync con las dos filas del feed nuevo (m³, líneas y cajas
reales, para no tocarlos): dirección *"Exp. — Pergamino 3751 (I. Catolica 6- Rio Cuarto)"*, barrio
Soldati; la clave nueva la geocodifica el cron (la limpia → *"Pergamino 3751"*, Villa Soldati). Espejo
en `sql/gv_np_es_pedido.sql` (condición) y nota en `sql/gv_v1330_resync_bloque_dobles.sql`.

**v13.45 — cierre.** El dueño mandó desde Google Maps (pin → Compartir, en grados) las tres calles que
OSM no tiene: **732 Trole 163** (-34.64181, -58.41944), **4114 J. M. Pérez 977, Luján** (-34.56350,
-59.13658) y **888 La Salle 2174** (-34.65450, -58.47567 — cae en Mataderos, ISIS dice Flores). Van en
`GV_Geo_Cliente` con `precision = 'manual'`, `manual = true`, `fuente = 'google_maps_dueño'`, y la misma
fila **agregada** a `PPP_Geo`; el cron nunca las pisa porque `gv_geo_faltantes` las excluye por
`(cod, dir_key)`. **1821 Sendra** se resolvió por corrección con el nombre completo (*Avenida San Juan
Bautista de La Salle 1923*, barrio **Parque Avellaneda** — con "Flores" OSM no la daba: el buscador se
queda dentro del barrio pedido). **771 La Anónima** queda sin ubicar a propósito (*"es súper y va
separado"*): camión propio, una parada, el front saltea el orden de carga para `ruta = "sup"`. Por eso
**Súper sale de `gv_geo_faltantes`** (migración `gv_geo_faltantes_sin_super_v1345`), igual que Retira:
`gv_geo_faltantes` = **0**. Receta para cargar una manual al pie de `sql/gv_geo_correccion.sql`.

### 3.an ✅ Las ubicaciones se llenan solas y se guardan por cód de cliente (v13.40) — 2026-09-06 domingo

Dueño: *"todo tenés que tener todas las ubicaciones"*, y antes *"dale, 1 y 2"* a las dos cosas que le
propuse. Estado al abrir: **43 de 54 direcciones programadas sin ubicar**; `PPP_Geo` con 118 filas y
la última geocodificación del **21/08**, porque sólo corría cuando un supervisor abría 📍 Mapa de
zonas y tocaba el botón. Sin ubicación, el orden de carga manda ese pedido al final del reparto.

**Lo nuevo** (`sql/gv_geo_cliente.sql`, migraciones `gv_geo_cliente_y_faltantes_v1340`,
`gv_geo_cliente_clave_cod_mas_dir_v1340b`, `gv_dir_geo_query_espacios_y_retira_v1340c`):

| objeto | qué es |
|---|---|
| `gv_dir_geo_query(dir)` | la dirección lista para preguntar: saca `"Exp. Arnes — "` y el `"(domicilio final)"` de los pedidos por expreso, colapsa los espacios de más que escribe ISIS (`"Jufre   339"`) y devuelve `null` si la dirección dice "Retira" |
| `gv_dir_key(dir, barrio)` | la MISMA clave que arma el front (`_rtDirKey`) |
| `GV_Geo_Cliente` | **fuente canónica de Gestión**. Clave `(cod, dir_key)` — no sólo el cód, porque hay clientes con varias direcciones (1792 Dapelo entrega en Villa Crespo, Almagro y Colegiales). RLS: lectura anon/authenticated, escritura authenticated. `manual = true` la congela: el cron no la pisa |
| `gv_geo_de_cliente(cod)` | la ubicación "mejor" de un cliente (más usada, y a igualdad la última) |
| `gv_geo_faltantes` | vista `security_invoker`: lo programado (ISIS + web, desde 7 días atrás) sin ubicación ni por (cód, dirección) ni por dirección |
| `GV_Geo_Log` | una fila por corrida: `ok` / `sin_faltantes` / `error`, cuántas pidió, ubicó y fallaron |
| Edge Function `gv-geocodificar` | lee `gv_geo_faltantes`, pregunta a Nominatim **1 por segundo**, escribe `GV_Geo_Cliente` y **agrega** a `PPP_Geo`. Tope de 40 por corrida (~45 s); lo que sobra queda para la siguiente |
| cron **jobid 75** | `20 */6 * * *` — cada 6 horas |

**⚠ `PPP_Geo` es compartida con Producción** (la usa su `index.html`): la Edge Function sólo le
**agrega** filas (`Prefer: resolution=ignore-duplicates`). Medido: 118 → 120 filas en la primera
corrida, ninguna fila existente modificada.

**Cascada de intentos** (la primera versión dejaba 19 de 64 sin ubicar, todas "sin resultado"):
1. dirección + barrio + Buenos Aires; 2. lo mismo con el barrio corregido (`"P.Patricios"` →
`"Parque Patricios"`, `"Soldati"` → `"Villa Soldati"`, `"Tortuguita"` → `"Tortuguitas"`);
3. dirección + Argentina, **sin** Buenos Aires ni viewbox — un pedido de Chef entrega en Río Cuarto
(Córdoba) y el `", Buenos Aires"` lo mandaba a ningún lado; 4. búsqueda estructurada `street`/`city`.
Cada intento cuesta 1 s y sólo se hace si el anterior falló.

**En el front** (v13.40): `pppRefreshGeo` carga también `GV_Geo_Cliente`, y `_pppGeoDe(p)` decide la
ubicación en este orden: (1) `(cód, dirección)` exacta, (2) `PPP_Geo` por dirección, (3) **cualquier**
ubicación de ese cód — el paracaídas: si ISIS le cambia el tipeo a la dirección, antes el pedido caía
a "sin ubicación". Test: `tests/geo-por-cod.cjs`.

**Rollback**: `select cron.unschedule(75);` y los `drop` que están al pie de `sql/gv_geo_cliente.sql`.
`PPP_Geo` queda como está — sólo se le agregaron filas.

### 3.am ✅ El calendario tardaba 1,4 s: el cupo se calculaba 21 veces (v13.34) — 2026-09-06 domingo

Dueño: *"tarda 5 seg en cargarse los datos, ¿por qué?"*. Midiendo con `explain analyze`, el grueso
estaba en **`gv_ppp_web_calendario(hoy, hoy+20)` = 1.357 ms**. No era ninguna tabla grande: llamaba a
`gv_ppp_web_cupo(dia)` **una vez por día** (21 llamadas) y cada llamada evaluaba
`gv_ppp_web_pickers_tipicos()` **dos veces** (una en la condición del `case`, otra en el resultado) →
42 escaneos de 60 días de `Registros_Produccion_Virgilio`.

Arreglo, sin duplicar la regla: la fórmula del cupo pasa a vivir en **`gv_ppp_web_cupo_dias(desde,
hasta)`** (nueva, `security definer`, grants a `authenticated`/`service_role`), que resuelve pickers y
config **una sola vez** para todo el rango y aplica la fórmula por día; **`gv_ppp_web_cupo(fecha)`**
queda como envoltorio de un día, así el job, el intradía, `gv_ppp_web_dia_salida` y
`gv_ppp_web_proximo_dia_entrega` siguen llamando lo mismo. Los CTE van `materialized` a propósito: sin
eso Postgres inlinea la subconsulta y vuelve a contar los pickers por fila, que es el bug.

**Medido**: calendario 1.357 ms → **22,8 ms** (60×); `gv_ppp_web_dia_salida` (4 pedidos) 99 ms → 60 ms.
**Impacto verificado**: foto de `gv_ppp_web_calendario(hoy, hoy+40)` antes del cambio en una tabla
temporal y `except` en los dos sentidos después → **0 y 0** sobre 41 filas; tabla temporal borrada.
Producción no usa ninguna de las tres funciones (grep en el repo: 0 hits).
SQL: `sql/gv_ppp_web_cupo_dias.sql`. Migración `gv_ppp_web_cupo_dias_calendario_rapido_v1334`.
**Rollback**: reaplicar `sql/gv_ppp_web_cupo_dotacion.sql` + `sql/gv_ppp_web_calendario.sql` y
`drop function public.gv_ppp_web_cupo_dias(date, date);`.

Del lado del front, en la misma versión: (a) `openPPP()` preguntaba por `_pppTab === "apr"` y la solapa
se llama **`"prog"`**, así que el precalentamiento del puente a LK (Edge Function + login, la cadena
más larga) **nunca corría** — arrancaba recién dentro de `aprCargar`; (b) `aprCargar` esperaba a
`gv_ppp_web_dia_salida` antes de dibujar nada: ahora dibuja la lista y completa los chips cuando llega.

### 3.al ✅ Cron de Chef apagado (v13.31) — 2026-09-06 domingo

Dueño: *"llegó el mail automático de Chef"* → *"mandame SQL para que frene el mandado de mails"*. En el
proyecto Chef (`nkhzocgdpwtgrmwleihr`, sin acceso desde acá) había dos crons, calcados de LK: **jobid 1
`procesar-pedidos-web`** (`30 15 * * *` = 12:30 ART, `enviar_pedidos_main()`) y **jobid 2
`retry-procesar-pedidos`** (`2-59/6 15,16 * * *`, `retry_procesar_pedidos()`). El dueño corrió
`cron.alter_job(1, active := false)` y `(2, …)`; verificado `active = false` en los dos.
Mails que alcanzaron a salir: viernes 04/09 (pedido 216 Elbantonio, cod 2466) y sábado 05/09 (217).
Cruce en Virgilio: cod 2466 sin filas en `PPP_Programacion_Diaria` ni `Facturacion_NP` desde el 1/9 →
no se cargó en ISIS, no hay doble. 216 ya está programado por Gestión (F01A, vie 11); 217 pendiente en
A Programar (lun 14). Rollback: `cron.alter_job(1, active := true)` y `(2, …)` en Chef.

### 3.ak ✅ Noche de mejoras: 13 ideas de 3 agentes, todas hechas (v13.28–v13.30) — 2026-09-06 madrugada

Dueño: *"lanzá agentes que piensen mejoras… aprovechá la noche"* y a la mañana *"arrancá a hacerlas"*.
Front (v13.28/v13.29): 7828, 2048, 4528, 7999, 5162, 2510, 7394, 3254, 6900, 3007 (ver notas de la GUIA).
Backend (v13.30, migración `gv_resync_por_bloque_prox_dia_120_dobles_v1330`):
- **2485** `ppp_web_resync`: CTE `facturadas (order_id, np_idx)`; `pedidos` ya no excluye el order_id
  con un bloque facturado; `borradas` y `actualizadas` saltean los bloques facturados. NP facturada =
  congelada, por NP. Medido: 3 menciones en la función viva; `resync('lk','[]')` = 0 filas.
- **6908** `gv_ppp_web_proximo_dia_entrega`: hasta 120 días. `('lun 07 00:01')` = lun 14 (vie 11 lleno).
- **6194** vista `gv_np_web_dobles` (security_invoker, authenticated/service_role): 0 filas hoy.
- **4528** (v13.28) vistas `gv_ppp_web_prog_sin_base` + `gv_np_prog_sin_base` (`sql/gv_np_prog_sin_base.sql`).
Además los `.sql` del repo llevan al pie los parches vigentes (hallazgo del agente de lógica: el repo no
reproducía la base). Rollback por idea en `sql/gv_v1330_resync_bloque_dobles.sql`.

### 3.aj ✅ CCR cuenta como controlado = entregado (v13.27) — 2026-09-05 sábado (noche)

Dueño, mirando los 38 atrasados: *"¿no deberían estar en En Salida? Si ya fueron controlados, van
directo a Entregados"*. Cruce de los 76 NP con fecha vencida del espejo: la mayoría tiene **CCR** (Control
Remitos, botón CR) del 03/04-09 y muchos también CCN, pero no **CRN** (Recepción Remitos), que era lo
único que las vistas tomaban como "controlado". Cambio (migración
`gv_ppp_entregados_ccr_cuenta_como_controlado_v1327`, parche `replace()` sobre `pg_get_viewdef`,
`security_invoker = true` conservado): en `gv_ppp_entregados` y `gv_ppp_en_salida` el CTE `crn` toma
`opcion in ('CRN','CCR')`. El fallback del front (`pppRefreshControlado`) también.
Medido: atrasados **38 → 20**, En Salida **13 → 0**, entregados 824. Los 20 que quedan (98665, 98502,
98569, 44594, 98461, 98464, 98465, 98480, 98481, 98484, 98510, 98518, 98528, 98541, 98542, 98543, 98553,
98554, 98600, 98646) no tienen CCN, CRN ni CCR: nadie los cargó ni controló en la app (4 ni siquiera
armados: D57C, D57D). Son los que la operadora tiene que revisar. Rollback: volver el `ANY(ARRAY['CRN','CCR'])`
a `= 'CRN'` en las dos vistas.

### 3.ai ✅ El job real fallaba (pg_safeupdate) + intradía sin umbral + primera corrida (v13.25) — 2026-09-05 sábado (noche)

Dueño: *"si ya programaste, directo que salgan de A Programar"*. Se puso `intradia_umbral_m3 = 0,001` (el
cron 73 arma apenas hay algo pendiente; la Edge Function trata 0 como "sin valor", por eso 0,001) y se
disparó el job a mano (mismo `net.http_post` que el cron 71, `{"fecha": gv_ppp_web_proximo_dia_entrega()}`).
**Falló** (`GV_Tandas_Auto_Log` id 3): `ppp_web_armar_tandas: HTTP 400 21000 "UPDATE requires a WHERE
clause"`. Causa: `update _sin_tanda set camion = gv_ppp_web_camion(zona, sector);` sin `where` (v4,
sectores, v13.07); `pg_safeupdate` está activo para las conexiones que entran por PostgREST (service_role
de la Edge Function), no para el SQL editor ni el simulador → **desde v13.07 ninguna corrida real hubiera
armado tandas** y no nos habíamos enterado porque todo se probó por SQL. Parche
`ppp_web_armar_tandas_safeupdate_where_true_v1325` (`where true`, con chequeo de que no quede otro
update/delete sin where; los otros `gv_*` con update/delete multilínea sí llevan where).
Segunda corrida (log id 4): **ok**, 26 NP leídas, 18 programadas, 6 tandas para el **viernes 11**:
E01A 1344 Torres y Liva (0,985) · E01B 1345 + 1347 (0,483) · E01C 1348 + 1351 (0,577) · E01D 1342 + 1346
(0,468, zona 3 + 2 vecinas) · E01E 1343 (0,267) · **F01A Chef 216 Elbantonio (0,547, forzado por CUIT de
LK 271)**. `PPP_Web_Base` 221 líneas. **1350 Cuyana (0,938) no entró** por cupo (6 − 3,14 ISIS = 2,86; LK
armó 2,78) → la toma el intradía del lunes para el lunes 14. Excluidos: 181 en_produccion + 190
anterior_al_cambio (LK), 20 + 22 (Chef).
Front v13.25: sin carteles en el tablero (dueño: *"no entiendo ni qué significa"*): tarjeta Atrasados
tocable con tooltip, línea chica para "cargados sin controlar" → En Salida, la vista Atrasados explica qué
son y las 3 acciones; valor corto en celular; la grilla saltea `GV_Dias_No_Habiles` (lunes 07). Rollback:
`intradia_umbral_m3 = 0.80`; el `where true` no se revierte (es correcto).

### 3.ah ✅ Cupo por dotación: pickers × 3 m³, contando ISIS + web (idea 6220, v13.23) — 2026-09-05 sábado (noche)

Dueño: *"depende cuánta gente trabaje"* → *"por los mensajes de prod ya lo tenés"* (la dotación sale de
`Registros_Produccion_Virgilio`) y *"lo que esté, esté"* (lo de ISIS cuenta). Del análisis de 3 agentes
(90 días): 1 picker ≈ 3,9 m³/día, 2 ≈ 6,2 → **K = 3 m³ por picker**; correlación gente-total ↔ m³ nula
(r 0,19), manda el picking; armado 0,55 m³/h-hombre es el cuello (no se tapó todavía).
- `gv_ppp_web_pickers_tipicos()` = mediana de legajos distintos con EP/TP/PKC (≠ 0/1) por día, últimos
  `cupo_dias_muestra` (10) días con actividad. Hoy: **2**.
- `gv_ppp_web_cupo(fecha)` = pickers × `cupo_m3_por_picker` (3) si `cupo_por_dotacion = 1`, si no
  `m3_max_dia` (5). Hoy: **6 m³**.
- `gv_ppp_web_m3_isis(fecha)` = ISIS del día (canilla cerrada). **usado = web + ISIS.**
- Aplicado en `gv_ppp_web_proximo_dia_entrega` (job + intradía), `gv_ppp_web_calendario` (drop + create:
  `m3` = web + ISIS, `cupo` por día, nueva `m3_web`), y por parche `replace()` sobre `pg_get_functiondef`
  en `ppp_web_armar_tandas` v4 y `gv_ppp_web_tanda_programar` (aborta si no encuentra el punto).
Medido: calendario 07..14 → 08: 13,45/6 resta 0 · 09: 10,77/6 resta 0 · 10: 5,76/6 resta 0,24 ·
**11: 3,14/6 resta 2,86** · 14: 1,51/6 resta 4,49. `proximo_dia_entrega('lun 07 00:01')` = 11. Los 3,72 m³
web pendientes se reparten vie 11 / lun 14. SQL: `sql/gv_ppp_web_cupo_dotacion.sql`. Rollback:
`cupo_por_dotacion = 0` (vuelve 5 fijo; ISIS sigue contando).

### 3.ag ✅ Lunes 07/09 no hábil (Día del Metalúrgico): `GV_Dias_No_Habiles` (v13.23) — 2026-09-05 sábado (noche)

Dueño: *"el lunes no es feriado pero es el Día del Metalúrgico, no van a ir a trabajar; por eso no hay
pedidos en la PPP para el lunes"*. Tabla nueva **`GV_Dias_No_Habiles`** (fecha, motivo; RLS: todos leen,
supervisores/service escriben) con el 2026-09-07, y `gv_es_dia_habil()` (nuestra) la mira además de
`planify.feriados`. No se tocó `planify.feriados`: la pisa el sync `planify_sync-feriados` (cron 33) y la
usan `planify_is_dia_laboral` y `notificar_pasaje_papeles_48h`. Medido: `gv_es_dia_habil('2026-09-07')`
= false; `dia_minimo('lun 07 00:01')` sigue siendo vie 11 (el lunes es la base, no cuenta). El job y el
intradía del lunes corren igual (miran la fecha objetivo). Recordatorios de esta sesión movidos al
martes 08 (08:30 y 15:00). SQL: `sql/gv_dias_no_habiles.sql`.

### 3.af ✅ Anticipación mínima: Gestión programa a partir de hoy + 4 hábiles (v13.22) — 2026-09-05 sábado (noche)

Dueño: *"el lunes los operarios no van a tener que aplicar nada de la PPP para ese mismo día, salvo el
armado. Lo que haga Gestión va recién de acá a cuatro, cinco días en adelante."* Revisado el circuito:
**el job de las 00:01 programaba para HOY** (`hoyArgentina()` en la Edge Function cuando no le pasan
fecha) y el intradía para hoy/mañana (`gv_ppp_web_proximo_dia_entrega`). El lunes 07 a las 00:01 hubiera
armado E01A…E01F para el mismo lunes.

Nuevo interruptor **`PPP_Web_Config.dias_anticipacion_min = 4`** (0 = como antes) y una función que lo
aplica en todos lados, `gv_ppp_web_dia_minimo(ahora)` = hoy (mañana si pasó el corte) + N hábiles:
- `gv_ppp_web_proximo_dia_entrega` arranca en el día mínimo y de ahí busca cupo (job e intradía).
- **Cron 71** (`cron.alter_job`, es nuestro) manda `{"fecha": gv_ppp_web_proximo_dia_entrega()}` a la
  Edge Function en vez de `{}`: sin redeploy, la función v14 ya acepta `fecha` en el body.
- `gv_ppp_web_dia_salida`: zonas manuales sólo camiones ≥ día mínimo (§3.ae).
- `gv_ppp_web_calendario`: columnas `muy_pronto`, `dia_minimo` (drop + create otra vez); el front cierra
  esos días ("Muy pronto · desde el 11/09") y no acepta arrastres.
- `gv_ppp_web_tanda_programar`: `raise 'El 08/09 es muy pronto: Gestión programa desde el 11/09.'` si
  `p_fecha < gv_ppp_web_dia_minimo()`. Insertado con `replace()` sobre `pg_get_functiondef` (la migración
  aborta si no encuentra el punto); no se retipeó la función.
Medido (sábado 22:30): `dia_minimo(now())` = jue 10 · `dia_minimo('lun 07 00:01')` = **vie 11** ·
`('lun 07 13:00')` = lun 14 · `proximo_dia_entrega('lun 07 00:01')` = vie 11 · calendario 07/08/09
`muy_pronto = true` · `dia_salida` lunes 09:00: zona 1 → 11, zona 4 → 11, zona 6 → 14 · cron 71 con el
body nuevo · `gv_ppp_web_tanda_programar` contiene `gv_ppp_web_dia_minimo`.
**Consecuencia para el lunes:** el job arma lo pendiente (1340…1351) para el **viernes 11**; el martes 8 y
miércoles 9 se arman con lo que ISIS dejó. SQL: `sql/gv_ppp_web_anticipacion.sql`.
Rollback: `update "PPP_Web_Config" set valor = 0 where clave = 'dias_anticipacion_min'` (todo vuelve a
hoy/mañana) y, si se quiere, el cron con `body := '{}'`.

### 3.ae ✅ "A Programar" dice qué día va a salir cada pedido (v13.21) — 2026-09-05 sábado (noche)

Dueño: *"en A Programar debe aparecer para qué día va a poder salir el pedido, no la primera (sin
sentido)"* — el chip mostraba la fecha de recepción. Nueva RPC **`gv_ppp_web_dia_salida(p_filas jsonb,
p_ahora)`** (SECURITY DEFINER, `authenticated` + `service_role`, sin anon; `sql/gv_ppp_web_dia_salida.sql`),
recibe `[{zona, m3}]` de la lista y devuelve por índice `r_dia`, `r_motivo`, `r_detalle`:
- **Retira** → sin día (`retira`). **Súper** → sin día (`super`, camión propio).
- **Zona automática** (`zonas_automaticas`): antes del corte y con lo pendiente ≥ umbral →
  `gv_ppp_web_proximo_dia_entrega(ahora)` (`intradia`, puede ser hoy); si no →
  `proximo_dia_entrega(mañana 00:01)` (`job`). Es la misma regla que ejecutan el cron 71 y el 73.
- **Zona manual** → el primer día ≥ hoy (o ≥ mañana después del corte) con un camión a esa zona,
  web (`PPP_Web_Programacion`) o ISIS (`gv_ppp_programacion_diaria`) (`camion`, detalle con las
  tandas); si no hay → `sin_camion`. Sin zona → `sin_zona`.
Medido (lunes 07/09 09:00 simulado): zona 1 → 07/09 `intradia`; zona 4 → 08/09 (D60A·B·C·F); zona 5 →
08/09 (D60E); zona 6 → 14/09 (D69C); Retira/Súper/"" → null. A las 13:00 la zona 1 pasa a 08/09 `job`.
Front: `aprCargarSalida()` la llama al cargar la lista; `aprSalidaChip()` dibuja "🚚 sale mar 8/9"
(verde; fondo verde oscuro si es hoy), "🏭 retira", "🛒 súper: a mano", "⏳ sin camión previsto",
"❓ sin zona"; la fecha de recepción queda en el `title`. Rollback: `drop function` (el front muestra "🚚 …").

### 3.ad ✅ El calendario de "A Programar" muestra lo que ISIS ya tiene (v13.18) — 2026-09-05 sábado (noche)

Dueño (captura del martes 8 con `0,00 / 5,00 m³`): *"acá sigue figurando cero pero sí hay en la PPP"*.
`gv_ppp_web_calendario` sólo sumaba `PPP_Web_Programacion`; el martes ya tiene **13,45 m³ / 7 tandas
/ 11 NP** de ISIS (D59A, D60A–F, D61A). Ahora la RPC devuelve 3 columnas más — `m3_isis`,
`tandas_isis`, `np_isis` — leídas de `gv_ppp_programacion_diaria` (la vista con la canilla cerrada,
lo mismo que ve la solapa Programación). Drop + create porque cambia el tipo de retorno; grants como
estaban (execute anon/authenticated/service_role; sólo lee y la vista lleva `security_invoker`).
`fecha_entrega` del espejo es texto y puede venir `""` → se filtra por forma `^\d{4}-\d{2}-\d{2}`
antes de castear (la primera versión rompió con `invalid input syntax for type date: ""`).
El front (`aprRender`) agrega la línea violeta "📋 ISIS: 13,45 m³ · 7 tanda(s) · 11 NP" abajo de la
barra. **El cupo (`cupo`/`resta`/`pasado`) y el "completo" siguen siendo sobre lo web**: sumar ISIS
al cupo de 5 m³ cerraría todos los días (ISIS solo ya pasa los 5) y el job del lunes no tendría dónde
armar. Qué cupo corresponde lo decide el dueño con el análisis de dotación (idea **6220**: *"depende
cuánta gente trabaje"*; agentes corriendo sobre `Registros_Produccion_Virgilio`). Mismo pendiente
para `gv_ppp_web_proximo_dia_entrega`, `gv_ppp_web_tanda_programar` y `ppp_web_armar_tandas`.
Medido: `gv_ppp_web_calendario('2026-09-07','2026-09-11')` → 08: 13,451 / 7 / 11 · 09: 10,768 / 7 / 20
· 10: 5,762 / 11 / 35 · 11: 3,138 / 6 / 13; `m3` web 0 en todos. SQL: `sql/gv_ppp_web_calendario.sql`.
Migraciones `gv_ppp_web_calendario_con_isis_v1318` y `…_fix_fecha_v1318`.

### 3.ac ✅ Revisión con 5 agentes: gate de supervisor, drenaje web del stock, revokes (v13.16) — 2026-09-05 sábado (noche)

Pedido del dueño: *"Lanzá agentes de revisión del programa en sonnet 5"*. Corrieron `revisor-logica`,
`auditor-supabase`, `guardian-stock`, `auditor-consistencia` y `revisor-render`. Lo que era bug real
se arregló acá; lo que es decisión del dueño quedó en `agente_propuestas`. SQL en
`sql/gv_seguridad_v1316.sql` y `sql/gv_reconciliar_facturado_web.sql`. Migraciones:
`gv_seguridad_rpc_gate_supervisor_v1316`, `gv_gate_supervisor_y_facturado_web_v1316`.
**Nada toca objetos de Producción**: todo es `gv_*` / `ppp_web_*` / `GV_*`.

**A. Gate de supervisor (auditor-supabase #1).** `ppp_web_np_asignar` y `gv_ppp_web_tanda_programar`
son SECURITY DEFINER y hasta v13.15 aceptaban **cualquier** `auth.uid()`: en `auth.users` hay 413
sesiones anónimas (las que abre la app para los operarios), así que cualquier celular con la app
podía numerar NP y programar tandas salteando la RLS de supervisores. Nueva
`gv_es_supervisor_o_servicio()`: pasa `session_user` `postgres`/`supabase_admin` (SQL editor, cron),
JWT `service_role` (Edge Function) o un JWT con uno de los 3 mails de supervisor. Las dos funciones
la chequean al entrar y levantan `Sólo supervisores pueden …`.
⚠ **La primera versión tenía un agujero**: usaba `current_user`, y adentro de una SECURITY DEFINER
`current_user` es el dueño (`postgres`), así que el gate dejaba pasar a cualquiera. Lo detectó la
prueba (`set role authenticated` + JWT de un anónimo → `ppp_web_np_asignar` PASÓ). Corregido la misma
noche con `session_user` (migración `gv_es_supervisor_session_user_v1316`): no cambia con SET ROLE ni
con SECURITY DEFINER; es `authenticator` para todo lo que entra por la API.
Medido (copia del cuerpo con `session_user = 'authenticator'`, como lo ve la API): JWT anónimo de
la app → false · anon key → false · mail de supervisor → true · service_role → true · SQL editor
(`session_user = postgres`) → true. El job de las 00:01 (service_role) no cambia.

**B. Drenaje de `a_facturar` para tandas web (guardian-stock #1).** `reconciliar_pipeline_stock()`
(cron 68 de Producción) sólo drena tandas que existan en las tablas de ISIS: una tanda `E01A` nunca
está ahí, y el movimiento `facturado` dependía sólo del navegador al bajar el Excel. Nueva
`gv_reconciliar_facturado_web()` + cron **jobid 74** `gv-reconciliar-facturado-web`
(`5-55/10 * * * *`, desfasado 5 min del 68): misma lógica, `tandanp` desde `PPP_Web_Programacion`
+ `gv_ppp_web_np_label`, drena sólo cuando todas las NP de la tanda están en `Facturacion_NP`,
mismo índice `mov_stock_pipeline_dedup`. Medido: `select public.gv_reconciliar_facturado_web()`
→ `ok facturado_web=0` (no hay tandas web facturadas todavía); `cron.job` jobid 74 `active = true`.

**C. Revokes (auditor-supabase #2–#4).** `anon` sin `execute` en `gv_cruce_facturacion_resumen`,
`gv_cruce_facturacion_totales` (datos de facturación), `gv_ppp_web_armar_simular`,
`ppp_web_armar_tandas`, `gv_ppp_web_tanda_avisos`. En `GV_Sectores*` `anon` sólo lee;
`authenticated` conserva insert/update/delete (la policy de supervisores lo necesita) pero pierde
truncate/references/trigger. Medido: `has_function_privilege('anon', …, 'execute')` = false en las 5.

**D. `search_path` fijo** en todas las `gv_*` / `ppp_web_*` que no lo tenían (advisor
`function_search_path_mutable`). Medido: 0 funciones con `proconfig is null` con esos prefijos.

**E. Front (revisor-logica, auditor-consistencia, revisor-render)**, todo en v13.16 de `index.html`:
- `_pppTandaNum` devuelve **letra+número** (`E01`): antes sólo el número, así E01A y F01A caían en el
  mismo "camión". El orden pone "Sin tanda" al final de su ruta (con `localeCompare`, la `~` que
  se usaba de centinela ordenaba ANTES de las letras).
- `aprCargar()` sólo redibuja si el supervisor sigue en "A Programar" (la carga tarda ~3 s; si
  cambiaba de solapa, la pantalla volvía sola a A Programar).
- `pwebNpLabel` acepta `chef`/`ch` en cualquier caja; `_pppFmtM3` muestra 2 decimales bajo 0,1 m³
  (0,04 salía "0,0"); casillas del Excel ISIS al 140 % para tocarlas desde el celular; CSS muerto
  (`.ppp-errpanel.ok`, `.pn-kpis` duplicado en el media query) afuera.

**F. Lo que quedó como propuesta (decisión del dueño):**
| Cód. | Qué | Por qué no se hizo solo |
|---|---|---|
| 7802 | `en_produccion` debería comparar cod + fecha, no sólo cod | cambia qué pedidos se consideran "ya en ISIS" |
| 4779 | mismo cliente en dos sectores incompatibles el mismo día | regla de negocio |
| 2859 | formato de m³ unificado en todo el tablero | estético, varios lugares |
| 5313 | trigger sobre `Facturacion_NP` para drenar al facturar | **tabla compartida**: nunca trigger sin OK del dueño |

**Rollback:** grants de vuelta (comentados al pie de `sql/gv_seguridad_v1316.sql`),
`cron.unschedule('gv-reconciliar-facturado-web')` + `drop function gv_reconciliar_facturado_web()`.

### 3.ab ✅ "El lunes todos en GV": el mail del sábado ya no excluye (v13.15) — 2026-09-05 sábado (noche)

**Qué dijo el dueño.** *"El lunes van a empezar a usar GV, no más PV."* Con nadie en Producción,
los pedidos **1340…1349** (salieron a ISIS por el mail del sábado 12:30, el último) quedaban
**huérfanos**: la regla de pendientes los excluía (`enviado_a_isis` = "son de Producción") y nadie
los iba a programar. Decisión (AskUserQuestion): **el mail del sábado se ignora y GV los programa
desde la página**, como cualquier otro; se facturan después con el Excel ISIS como todo lo web.

**Qué se hizo** (migración `gv_pedidos_web_excluidos_sin_enviado_a_isis_v1315`,
`sql/gv_pedidos_web_excluidos.sql`): fila nueva `PPP_Web_Config.excluir_enviados_a_isis = 0` y
`gv_pedidos_web_excluidos` la lee: el motivo `enviado_a_isis` sólo aplica con `= 1`. Los otros dos
motivos (`anterior_al_cambio`, `en_produccion`) siguen igual. La Edge Function y "A Programar" no
cambian (llaman la misma RPC).

**Impacto medido** (simulación con los 12 pedidos reales de LK, `gv_ppp_web_armar_simular`, sin
escribir): 0 excluidos. El lunes 00:01 el job arma **6 tandas, 3,718 m³** (cupo 5):

| tanda | pedidos | barrio | m³ |
|---|---|---|---|
| E01A | 1344 Torres y Liva (2 bloques) | Barracas | 0,985 (sola, > tope) |
| E01B | 1345 Emilio Martinez + 1347 Guerreiro | Barracas | 0,483 |
| E01C | 1350 Distribuidora Cuyana (4 bloques) | Soldati | 0,938 (sola) |
| E01D | 1348 A L S.A + 1351 Astorga | Soldati + Pompeya | 0,577 |
| E01E | 1342 Di Leo (Mataderos) + 1346 BP Import (Villa Devoto) | zona 3 + zona 2 (C–E vecinos) | 0,468 |
| E01F | 1343 Chen Li Yu (3 bloques) | Belgrano | 0,267 |

A mano en "A Programar": **1340** (Retira), **1341** (Martínez, zona 6), **1349** (Padua, zona 5).
Producción: nada cambia (función `gv_`, tabla nuestra).

**⚠ Para el dueño:** si alguien carga igual el mail del sábado en ISIS, esos 10 pedidos van a
existir dos veces (ISIS y GV). No cargarlo. **Y lo mismo con Chef:** el interruptor es uno solo
para las dos empresas, así que lo que el cron de Chef siga mandando por mail (12:30, hasta que se
apague en su Dashboard) también lo programa GV → ese mail se ignora. Apagar el cron de Chef pasa a
ser urgente. Si se quisiera volver a la regla vieja sólo para Chef, habría que desdoblar el
interruptor por empresa (no está hecho).

**Rollback.** `update public."PPP_Web_Config" set valor = 1 where clave = 'excluir_enviados_a_isis';`

### 3.aa ✅ Cruce de factura que entiende las NP web (idea 8033) — 2026-09-05 sábado (v13.10)

**El agujero.** `vista_facturacion_neto_items` y `vista_cruce_facturacion` (objetos de **Producción**,
`sql/cruce_facturacion.sql` de ese repo) resuelven la empresa con `np ~ '^9' → lk, si no chef`. Una NP
web de LK es `LK 1350`: no empieza con 9 → Chef → busca la factura en `isis_ch.documentos` y el
descuento en `clientes_dto` de chef → **nunca cruza**. Lo mismo `empresa_de_np('LK 1350')` = `CH`
(mira sólo los dígitos). Las de Chef (`CH 0217`) caían bien de casualidad.

**Qué se hizo** (`sql/gv_cruce_facturacion.sql`, migración `gv_cruce_facturacion_np_web_v1310`). Sin
tocar nada de Producción: `gv_empresa_de_np_texto(np)` (`LK …` → lk, `CH …` → chef, 9xxxx → lk, resto
→ chef) + copias **`gv_vista_facturacion_neto_items`**, **`gv_vista_facturacion_neto`**,
**`gv_vista_cruce_facturacion`** (`security_invoker`, sin grant a anon/authenticated, como la original)
y las RPC **`gv_cruce_facturacion_resumen`** / **`gv_cruce_facturacion_totales`** (SECURITY DEFINER,
execute anon/authenticated). El front (pestaña "Facturación vs ISIS") llama a `gv_cruce_facturacion_resumen`.

**Impacto medido.** Últimos 60 días: Producción 789 filas, gv 789 filas, **789 idénticas** (estado,
empresa y diff), 0 sólo en una. O sea, para las NP numéricas es lo mismo; la diferencia aparece recién
con la primera NP web facturada. `gv_empresa_de_np_texto`: `LK 1350` → lk, `CH 0217` → chef, `98702`
→ lk, `44620` → chef. Hoy no hay NP web en `Facturacion_NP` ni en `Entregas_Virgilio` (0 filas no
numéricas). Tests `fac-excel-isis`, `fac-npc`, `pweb-facturacion` OK.

**Queda (Producción, decisión del dueño).** `empresa_de_np` es de Producción y la usa el trigger
`zz_normalizar_empresa` de `Movimientos_Stock` para los 4 códigos duales: con una NP web sigue dando
`CH`. Arreglo propuesto, reversible, compatible con lo numérico:
```sql
create or replace function public.empresa_de_np(p_np text) returns text language sql immutable as $$
  select case when p_np ~* '^\s*LK' then 'LK' when p_np ~* '^\s*CH' then 'CH'
              when regexp_replace(coalesce(p_np,''),'\D','','g') = '' then null
              when (regexp_replace(p_np,'\D','','g'))::bigint > 90000 then 'LK' else 'CH' end $$;
```
No se aplica sin permiso explícito: es `create or replace` de una función que corre para Producción.

**Rollback.** El bloque de rollback del SQL; el front vuelve a `cruce_facturacion_resumen`.

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

## 3.bj Se cortó la planilla de Google de "Pedidos Entregados" — 2026-09-07

**Cómo salió.** El dueño miró la hoja de entregados y saltó: *"¿cómo 8/9? eso es mañana"*. Era un
tipeo: **NP 97719** (Merajver Marcelo Fabián, cód 2193, tanda `C39A`, 0,031 m³) figuraba entregado
el **2026-09-08**. La facturación dice `facturado_at = 2026-06-08 16:45` y `fecha_salida =
2026-06-09`: le dieron vuelta día y mes. Lo real es el **9 de junio**.

**No era sistemático — se verificó.** Cruzando las **1.072 NP** que están a la vez en
`PPP_Entregados_Meta` y en `Facturacion_NP`: 241 con la misma fecha, **567 a −1 día**, 226 entre −2
y −4, 17 hasta −13 (normal: la hoja lleva la entrega y la facturación el día de salida). **Una sola
fila cae fuera de escala, +91 días: ésta.** Cero casos de día/mes invertidos en serie.

**Lo importante no era el tipeo, era de dónde venía.** La tabla no se cargaba a mano: la pisaba
entera el **cron 27 `sync-ppp-entregados-meta`** (`7,37 * * * *`), que hace `http_get` del CSV de la
hoja *"PPP Pedidos Entregados 2026"* (gid `2146771217`), **`truncate` de `PPP_Entregados_Meta`** y la
vuelve a llenar. Corregir la fila sin apagar el cron no servía: a los minutos volvía el 08/09.

**Decisión del dueño:** ***"la planilla de Google no se tiene que usar para nada"***.

**Qué se hizo, en orden** (`sql/backups/entregados_meta_20260907_corte_google_sheet.sql`):

1. Backup completo a `public."GV_Backup_Entregados_Meta_20260907"` — **2.783 filas originales**,
   con la fila mala incluida.
2. `select cron.alter_job(27, active := false)` — **primero apagar**, si no la corrección se pierde.
3. `update … set fecha_entrega = '2026-06-09' where np = '97719'`.
4. Verificado: última entrega en la hoja **02/09/2026**, **0 fechas futuras**, 2.783 filas intactas.

**La tabla queda CONGELADA** como foto histórica (02/01 → 02/09/2026). No se borró nada y no entra
más nada desde la planilla.

**⚠ Esto también lo toma Producción** (base compartida). En su repo leen `PPP_Entregados_Meta`:
`vista_tanda_m3`, `vista_productividad_semanal`, `picking_sin_base_telegram` y su `index.html`. Con
el cron apagado esas vistas dejan de incorporar entregas nuevas desde la hoja; las viejas siguen. En
**Gestión no hace falta**: desde el 07/09 el estado "entregado" sale de **Recepción Remitos**
(`gv_ppp_entregados`, evento `CRN`).

**Efecto de rebote en el análisis del "CCR sin CCN":** con la fila mala, la hoja parecía llegar al
08/09. Corregida, **termina el 02/09** — o sea que del **3 y 4 de septiembre no hay ninguna entrega
cargada**, ni de los 8 pedidos observados ni de sus compañeros de camión. Eso refuerza que lo del
3–4/09 es un corte de registro de esos dos días, no algo propio de esas 8 NP.

**Rollback:** `truncate` + `insert … select * from "GV_Backup_Entregados_Meta_20260907"` +
`cron.alter_job(27, active := true)`.

---

## 3.bk El reporte de la página ve el depósito de Gestión (v14.14) — 2026-09-07

**El pedido.** *"Hicimos un reporte diario/semanal/mensual para la página. Quiero que incluya lo
que pasa en Gestión Virgilio (armado de pedidos y despacho de los mismos)."* Al revisar qué había,
resultó que el reporte —que vive en el proyecto **LK**, funciones `rep_*`, sale por Telegram con
los crons 29 (diario, lun–sáb 08:00 ART), 30 (semanal, lun) y 31 (mensual, días 3/5/8/12)— **ya
traía** dos bloques de depósito: lo despachado por día y lo pendiente de facturar. Los dos estaban
mal, por tres motivos distintos.

**1. No veía nada de lo que arma Gestión desde la página.** El espejo de LK copia
`virgilio.programacion_diaria`, que es la tabla **cruda** `PPP_Programacion_Diaria`. Las NP web
viven en `PPP_Web_Programacion` (29 al 07/09, las 29 con tanda) y no aparecían en ningún número.
Y como copia la tabla cruda, también se traía las **10 filas que `GV_PPP_Prog_Override.oculto`
esconde** (las NP de ISIS que duplican un pedido web ya programado acá).

**2. El filtro de empresa era `left(np,1) = '9'`.** Desde la v13.70 la NP web es un contador propio
con etiqueta `LK 0001` / `CH 0002`. La primera NP web que se facturara iba a caer del reporte **sin
error y sin aviso** — ni en el despacho ni en el backlog. Todavía no pasó (`Facturacion_NP` no tiene
ninguna NP no numérica), así que se arregló antes de que pasara.

**3. LK reconstruía la plata y le daba de más.** Valorizaba sobre lo **pedido** y después corregía
con un ratio global de cajas entregadas/pedidas. Contra el neto que Gestión ya calcula en
`gv_vista_facturacion_neto` —cajas **entregadas** × uxb × precio × (1−dto_vol) × factor web/súper,
con lista propia de supermercado y la L de Chef resuelta— la diferencia iba de **+0,5% a +14,5%**
según el día:

| Fecha | LK reconstruía | Neto real (Gestión) | Dif |
|---|---|---|---|
| 04/09 | $14,19 M | $13,96 M | +2% |
| 03/09 | $28,30 M | $28,16 M | +1% |
| 02/09 | $0,93 M | $1,15 M | −19% |
| 01/09 | $15,26 M | $14,61 M | +4% |
| 31/08 | $25,34 M | $21,74 M | +17% |
| 27/08 | $19,21 M | $16,78 M | +15% |

El 31/08 además la foto vieja había guardado **25 NP pero valorizado sólo 5** y nunca se rehizo: el
`on conflict` sólo pisaba si venían **más** NP valorizadas que la vez anterior, y no volvieron.

**Qué se hizo de este lado** (`sql/gv_lk_np_feed.sql`): una vista **nueva**, `gv_lk_np_feed`, con
una fila por NP —ISIS y web juntas— que expone lo que el reporte necesita: cliente, tanda, zona,
fecha de entrega, m³, si está facturada y cuándo, el **neto facturado**, cajas pedidas/entregadas, y
el **valor de lista** de lo pendiente. Lee `gv_ppp_programacion_diaria` (la vista, no la tabla), así
que el override manda. `security_invoker = true`, `revoke` de `anon`/`authenticated`, `grant select`
sólo a `lk_ppp_reader` y a `service_role`.

Para que la vista funcione con los permisos de quien la llama hicieron falta **15 grants de SELECT y
9 policies** `lk_ppp_reader_sel` — `Entregas_Virgilio`, `PPP_Web_Base`, `PPP_Web_Config` (la lee
`gv_espejo_corte()`), `GV_PPP_Prog_Override`, `clientes_dto`, `precios_venta`, `precios_venta_chef`,
`cobranzas_cliente_cadena`, `cobranzas_super_cadena` y las vistas `gv_*` intermedias. Todo lectura,
todo aditivo: ni un `update`, ni un trigger, ni un `drop`.

**Del lado LK** (repo `pagina-LK-copia`, `sql/reporte_deposito_gestion.sql`): foreign table sobre el
feed, espejo local `ppp_np_feed` refrescado dentro de `sincronizar_ppp()` (bloque propio con su
`EXCEPTION`, antes de `rep_snapshot_despacho`), y las cuatro funciones del reporte reescritas.
**La plata vieja no se pisó**: el neto entra en columnas nuevas (`rep_despacho_diario.plata_neto`,
`np_neto`) y los textos leen `coalesce(plata_neto, plata)`, así que los días viejos sin neto siguen
mostrando el número de antes en vez de un hueco. El **mensual**, que no tenía nada de depósito, suma
un bloque 🚚 DEPÓSITO con lo despachado del mes cerrado y lo pendiente de hoy.

**Medición.** Pendiente de facturar: **antes 102 NP · 60,4 m³ · $192,0 M → ahora 127 NP · 65,8 m³ ·
$221,1 M**. La diferencia son exactamente las **25 NP web de LK = $29,0 M** que no se veían (0 líneas
sin precio), y **ninguna NP** de las que salían antes se perdió. Coherencia contra el ERP: agosto
despachado $510,6 M contra $522,4 M facturados = **98%**. Los m³ del feed dan idénticos a
`Facturacion_NP` día por día. Costo: 634 ms + 311 ms, corre 1×/día.

**Lo que queda cojo, a propósito:** el **pendiente** de un supermercado con lista propia se valoriza
a lista general si la NP no tiene líneas en el espejo de LK (lo **facturado** no: ese ya sale bien);
15 de los 20 días de agosto tienen neto y los otros 5 caen al número viejo; y el espejo corre una
sola vez por día (cron 19, 07:00 ART), no hay nada intradía.

**Nada de esto separa lo de ISIS de lo web en pantalla** (regla del dueño, v13.64): `rep_ppp()`
devuelve `nps_web` pero el texto no lo imprime.

**Rollback:** `drop view public.gv_lk_np_feed;` + las 9 `drop policy` y los 15 `revoke` que lista
`sql/gv_lk_np_feed.sql`; del lado LK, el rollback de `sql/reporte_deposito_gestion.sql` y restaurar
las funciones desde `sql/backups/rep_funciones_20260907_pre_np_feed.sql`.

---

## 3.bl ✅ Ahora se ubica TODO el padrón, no sólo lo programado (v14.16) — 2026-09-07

**El pedido, textual:** *"tenés que tener a todo ubicado. sin falta de ninguno, inclusive aunque
no hayan mandado pedido"*.

**Qué estaba mal.** `gv-geocodificar` (cron 75) sólo miraba `gv_geo_faltantes`, que sale de la
**programación** de los últimos 7 días para adelante. Un cliente que no pidió esta semana no tenía
lat/lng. El día que entra su pedido, el orden de carga del camión lo manda al final y el reparto se
arma a ciegas. Al abrir el día había **64 direcciones ubicadas en total** sobre un padrón de más de
dos mil.

**Lo que se agregó** (todo nuevo, con prefijo nuestro; nada compartido se modificó):

| Objeto | Qué es |
|---|---|
| `GV_Clientes_Direcciones` (tabla, RLS on) | espejo del padrón de direcciones de entrega de LK y Chef |
| `gv-sync-padron-direcciones` (Edge Fn, verify_jwt off) | la llena; cron **79**, `40 8 * * *` (05:40 ART) |
| `gv_geo_faltantes_padron` (vista, `security_invoker`) | lo del padrón sin ubicar, **AMBA primero** |
| `gv_geo_cobertura` (vista, `security_invoker`) | cuánto falta, por ámbito y empresa |

**`gv-geocodificar` v9.** Primero drena lo programado (es lo que sale esta semana) y, si sobra
lote, sigue con el padrón. Dos diferencias con lo programado:

1. **Las del padrón NO se escriben en `PPP_Geo`.** Esa tabla es compartida con Producción y sólo
   tiene sentido que crezca con lo que de verdad se programó; el padrón vive en `GV_Geo_Cliente`.
2. **El interior usa su provincia real.** La cascada vieja forzaba `viewbox` del AMBA y
   `state=Buenos Aires`; con eso, un cliente de Río Cuarto o de Trelew queda sin ubicar o —peor—
   cae en una calle homónima del conurbano. Ahora hay una rama aparte: búsqueda estructurada
   `street`+`city`+`state`, sin viewbox, verificada contra el centro de esa localidad **de esa
   provincia** con radio 40 km (el AMBA sigue con 20). El cache de centros lleva la provincia en
   la clave: hay un "San Martín" en Buenos Aires, otro en Mendoza y otro en Corrientes.

**Medido el mismo día.**

- `GV_Clientes_Direcciones` → **2.307** direcciones: LK 918 AMBA + 684 interior, Chef 337 AMBA +
  368 interior.
- `gv_geo_faltantes_padron` → **2.066** por ubicar (1.025 AMBA + 1.041 interior). Las 241 de
  diferencia son Retira o dirección que `gv_dir_geo_query` descarta.
- Corrida de prueba `{"max": 8}` → 4 ubicadas, 4 fallaron (`GV_Geo_Log` id 19).
- Cron 75 acelerado de `20 */6 * * *` a `*/10 * * * *`: 40 por corrida × 6 corridas/h ≈ **9 h**
  para drenarlo. Aun así el promedio queda muy por debajo del límite de Nominatim (1 llamada por
  segundo), porque cada corrida usa ~45 s de los 600 disponibles. **Volver a `20 */6 * * *`
  cuando `gv_geo_cobertura` esté en verde.**

**Y el depósito, que no estaba.** `PPP_Geo` no tenía la fila `__deposito_virgilio_2788__`, así que
el front caía al fallback "centro de CABA" (`-34.6037, -58.4`), a **11 km** del depósito real.
Quedó cargado: **Virgilio 2788, Villa Real, CABA → -34.6157998, -58.5252267**. Sin esto no se puede
calcular ningún tiempo de viaje depósito → destino.

**Ojo con Chef.** No se lee por el espejo de LK: `chef_customers` y
`chef_customer_delivery_addresses` son tablas FOREIGN (postgres_fdw contra Chef) y el
`service_role` de LK no tiene user mapping —devuelven `42704 user mapping not found for user
"service_role", server "chef_db"`—. La Edge Function va directo al proyecto de Chef con
`CHEF_SERVICE_KEY`, igual que `sync-clientes-dto`. Si esa clave falta, Chef se saltea y LK sigue.

**Rollback:** en `sql/gv_padron_direcciones_v1416.sql`.

## 3.bm ✅ La cola de geocodificación se tapaba (v14.19) — 2026-09-07

**Defecto de la v14.16, encontrado el mismo día.** `gv_geo_faltantes_padron` devuelve lo que
falta **siempre en el mismo orden** (`amba desc, empresa, cod`) y el geocodificador toma los
primeros 40. Los fallos no se guardaban en ningún lado, así que una dirección que no resuelve
**volvía a salir primera en la corrida siguiente**. Alcanza con 40 seguidas que fallen para que
la cola quede tapada: el cron sigue corriendo, gasta sus 40 llamadas cada 10 minutos, y **lo que
está detrás no se intenta nunca**.

**Medido:** de 16:22 a 17:53 el log da seis corridas seguidas con `pedidas 40, ubicadas 0,
fallaron 40` y el mismo *"1731 sin ubicar todavía"*. La cobertura se quedó clavada en **368 de
2.307 durante 90 minutos**.

**No era Nominatim.** Antes de tocar nada se probó una consulta directa desde la base
(`net.http_get` a `/search?street=Rivadavia 5000&city=Flores`) y contestó **200 con resultado**.
El problema era nuestro.

**Lo que se agregó** (`sql/gv_geo_fallidas_v1419.sql`):

| Objeto | Qué hace |
|---|---|
| `GV_Geo_Fallidas` (tabla, RLS on) | intentos, último error y última fecha por `(cod, dir_key)` |
| `gv_geo_marcar_fallo(cod, dir_key, error)` | la llama la Edge Function en cada fallo; incrementa |
| `gv_geo_reintentar(cod)` | devuelve a la cola lo dado por perdido, después de corregir a mano |
| `gv_geo_faltantes_padron` v2 | ahora excluye lo que ya falló **3 veces** — eso destapa la cola |
| `gv_geo_no_resueltas` (vista) | las descartadas con su último error: la lista para arreglar |

**Tres intentos y no uno**: Nominatim tiene picos y la cascada del geocodificador prueba varias
formas de preguntar, así que un fallo pasajero no puede condenar una dirección para siempre.

**Cómo se destapó lo que ya estaba trabado.** Antes del redeploy se sembró `GV_Geo_Fallidas`
desde el historial de `GV_Geo_Log` (que ya venía guardando `detalle->errores`), cruzando por
`gv_dir_geo_query(direccion)` contra el padrón: **46 anotadas, 39 descartadas**, y la cola pasó
de 1.727 a 1.689 al instante.

**Verificado después del deploy (v10 de la función):** los fallos se anotan solos (46 → 53) y la
cobertura volvió a moverse (368 → 371 → 373).

**Rollback:** en la cabecera de `sql/gv_geo_fallidas_v1419.sql`.

## 3.bo ✅ Las direcciones no fallaban por la calle, fallaban por cómo están escritas (v14.26) — 2026-09-07

**El síntoma.** Con la cola destapada (§3.bm) y el padrón acotado a los clientes habituales de
CABA/AMBA (v14.21/v14.22), el geocodificador venía resolviendo alrededor de la mitad de lo que
pedía, corrida tras corrida: `pedidas 40, ubicadas 17..22`. La cobertura subía, pero lento, y las
mismas direcciones se iban acumulando en `GV_Geo_Fallidas`.

**El diagnóstico.** Al mirar las 29 direcciones de clientes habituales que ya se habían dado por
perdidas, no había 29 problemas distintos: había **tres patrones**.

| Patrón | Ejemplos |
|---|---|
| Punto pegado a la letra siguiente | `Av.Fco.Beiro 5425` · `Int.Rabanal 2876` · `J.A.Roca 1814` |
| Cola del depósito del expreso | `Pinedo 50 Galpon 3` · `Pinedo 50 G 4 Pta 5` · `Av.Pinedo 50 Galpon 3 Est.Sola` |
| Abreviatura de tratamiento | `Int Perez Quintana` · `Gral Madariaga` · `Pte Peron` · `Bme Mitre` |

El galpón del expreso en Estación Sola (Pinedo y Av. Suárez, Barracas) aparece en el padrón
escrito de **nueve formas distintas**, y ninguna de las nueve es una dirección que Nominatim
pueda entender.

**La solución.** `gv_dir_geo_normalizar(dir)` — limpia el texto **antes** de consultar, y se metió
en el `dir_query` de las dos vistas de faltantes (`gv_geo_faltantes` y `gv_geo_faltantes_padron`),
después de `gv_dir_geo_query` (que saca el prefijo `Exp. … —` y el paréntesis final) y **antes** de
`GV_Geo_Correccion`, para que una corrección a mano siempre gane.

⚠ **No toca `dir_key`.** El `dir_key` se sigue armando con la dirección cruda + el barrio de
entrega, así que nada de lo ya geocodificado se despega. Cambiar el `dir_key` fue el error del
07/09 a la mañana: desenganchó ~300 filas ya ubicadas y hubo que copiarlas de la clave vieja a la
nueva.

Los tres cuidados que costaron una iteración cada uno:

- La **"G" suelta de galpón** sólo se saca si viene *después de la altura y al final*. Sin esa
  condición, `Artigas Jose G. 4927` quedaba en `Artigas Jose` — la "G." era una inicial y el 4927
  la altura. Con la condición, queda entero.
- El **punto pegado** se reemplaza en **dos pasadas**: `regexp_replace` no solapa, y `J.A.Roca`
  necesita la segunda para llegar a `J. A. Roca`.
- Al final se limpia la **puntuación colgada**, si no `Av. Suarez Y Pinedo - Galpon 3` terminaba
  en `Av. Suarez Y Pinedo -`.

**Medición, antes de aplicar** (se revisaron las 85 a ojo, una por una):

```sql
select distinct gv_dir_geo_query(direccion),
       gv_dir_geo_normalizar(gv_dir_geo_query(direccion))
  from public."GV_Clientes_Direcciones"
 where gv_dir_geo_normalizar(gv_dir_geo_query(direccion))
       is distinct from gv_dir_geo_query(direccion);
-- 160 filas / 85 direcciones distintas
select count(*) from public.gv_geo_faltantes;   -- 0 antes y 0 después (no se rompió lo programado)
```

**Lo que el normalizador no puede arreglar** se cargó a mano en `GV_Geo_Correccion` (13 filas,
cada una con su motivo escrito):

- `A.Cafarena 36` → **Caffarena** 36 (dos efes), La Boca.
- `Sta.Domingo 3930` → **Santo** Domingo (acá `Sta.` no es Santa), Pompeya.
- `Juan D Peron 2323` → la calle de CABA es **Perón** (ex Cangallo), Balvanera.
- `Av Jujuy 1240` / `1481`, barrio "Constitucion" → **caía a 640 km**: es la Constitución del
  interior. Se le puso barrio **San Cristóbal**.
- `A Circunvalacio 550` → **Av. Circunvalación**, y el Mercado Central está en **Tapiales**.
- `Av. Suarez Esq Pinedo,Galpon 5` → **Pinedo 50** (es el mismo hub del expreso).
- `San Juan B De La Salle 1926`, `Av J B Justo 8587`, `Av Lacroze 2433` (= Federico Lacroze, y la
  altura 2433 cae en **Colegiales**, no Belgrano), `Virgilio 2788, Retira, CABA`, `Arenales 2000`
  (altura 2000 = **Recoleta**, no San Nicolás), `Constitucion 2587` (se aclara "Calle" para que no
  lo tome como el barrio).

⚠ El insert sale de un `select` contra `GV_Clientes_Direcciones`, **no** de constantes: el
`dir_key` se arma con la dirección **completa**, y escribirlo a mano con la ya limpia fue el error
del cód 45 esa misma mañana.

Después, `gv_geo_reintentar()` devolvió **70** fallidas a la cola con la consulta nueva.

**Verificado después de aplicar** (dos corridas del cron, ~11 minutos):

```sql
select * from public.gv_geo_cobertura;
--            antes                    después
--  chef   36/43 · faltan  2       38/43 · faltan  0
--  lk    255/446 · faltan 132    290/446 · faltan 97
--  total 291                     328        (+37 en 11 minutos)
```

De las 13 correcciones a mano, **11 ya quedaron ubicadas** en la primera pasada; faltan
`Calle Constitucion 2587` y `Avenida Juan B. Justo 8587`, que todavía no salieron en la cola.

**Y al rato la cola llegó a CERO** (`gv_geo_faltantes_padron` = 0, el log da `pedidas 0`):
cobertura **376 de 489**, chef 38/43 con **0 faltantes**. El cron 75 volvió a su horario normal,
`20 */6 * * *`.

## 3.bq ✅ La Estadística Madre venía calculando sin agosto (v14.28) — 2026-09-08

⚠ **Esto es del proyecto LK** (`kwkclwhmoygunqmlegrg`), no de Virgilio. Se anota acá porque el
repo de LK no está adjunto; el SQL está en `sql/lk_refresh_mvs_v1428.sql` y **hay que copiarlo
al repo de LK**.

El reporte de salud del 08/09 avisaba *"🔴 cron refresh-mvs-daily · falla desde hace 56 días"*.
El error, que nadie había leído:

```
ERROR:  permission denied for table sales_line
CONTEXT: remote SQL command: SELECT customer_code, item_code, invoice_date, boxes
         FROM public.sales_lines WHERE ((invoice_date IS NOT NULL))
```

`remote SQL command` = va por `postgres_fdw` contra **Chef**. El usuario mapeado es `loke_reader`
y no tiene `SELECT` sobre `public.sales_line` del lado de Chef. Sobre `customers` sí:
`mv_chef_customers_resolved` refrescaba bien.

**Pero lo caro no era eso.** El cron corría los tres REFRESH **en un solo comando**, o sea una
sola transacción: cuando el segundo fallaba, **se revertían los tres**. `mv_loke_sales_agg`, que
es 100% local y no tiene nada que ver con Chef, quedó congelada:

| | filas | hasta |
|---|---|---|
| `mv_loke_sales_agg` | 183.740 | **2026-07** |
| `sales_lines` (viva) | 233.898 | **2026-08-31** |

Y `refresh_estadistica_madre_cache` corre todos los días leyendo esa MV: el cron 13 "andaba
bien", sólo que **sobre datos que se cortaban en julio**.

**Arreglo:** `lk_refresh_mvs()` — cada MV en su propio bloque con `EXCEPTION`, y el resultado
anotado en `lk_refresh_mvs_log`. Medido al aplicarlo:

```
mv_loke_sales_agg           ok=true    9.696 ms   183.740 → 187.779 filas, jul → ago
mv_chef_sales_loke          ok=false   6.065 ms   permission denied for table sales_line
mv_chef_customers_resolved  ok=true   26.187 ms   757 → 762 filas
refresh_estadistica_madre_cache() → 537           (ya con agosto adentro)
```

⚠ **El efecto secundario que hubo que compensar.** Con el arreglo el cron **termina OK aunque
una MV falle**, así que el chequeo 1 de `rep_salud` (crons cuya última corrida falló) dejaría de
verlo y el problema de Chef se volvería **invisible**. Por eso va también la **rama 1b** de
`rep_salud`, que además dice *cuál* MV y *por qué* — mejor que el "cron falla desde hace 56 días"
de antes. Se inyectó sobre la definición viva con un `DO` que aborta si no encuentra el ancla, en
vez de retipear la función: `rep_salud` tiene siete chequeos que hoy funcionan y un error de
transcripción se llevaría alguno puesto **sin que se note** (devuelve filas, no falla).

Resultado en el reporte:

```
antes:  🔴 cron refresh-mvs-daily · falla desde hace 56 días
ahora:  🔴 materialized view mv_chef_sales_loke · falló al refrescar
           → permission denied for table sales_line
```

**Lo que faltaba, y se hizo el mismo día.** En el proyecto de Chef (`nkhzocgdpwtgrmwleihr`, que
esta sesión **no puede tocar** — está en otra organización de Supabase), lo corrió el dueño:

```sql
grant usage on schema public to loke_reader;
grant select on public.sales_line  to loke_reader;
grant select on public.sales_lines to loke_reader;
```

Verificado desde LK: las tres MV en `ok = true`, y `mv_chef_sales_loke` pasó de fallar en 6 s
(*permission denied*) a **17,5 s de trabajo real**. Mientras corría se vio en `pg_stat_activity`
esperando en `PostgresFdwGetResult`, o sea trayendo filas de verdad.

### ⚠ Pero el número no se movió, y eso destapó otra cosa

`mv_chef_sales_loke` quedó igual: **2.227 filas, hasta 2026-02-23**. No es que la MV siga rota
—ahora lee bien—; es que **no hay dato nuevo del otro lado**. Mirando el crudo por el FDW:

```sql
select count(*), min(invoice_date), max(invoice_date)
  from public.chef_sales_lines where invoice_date is not null;
-- 36.770 filas · 2020-01-02 → 2026-02-23
```

**Las ventas de Chef no se cargan desde el 23 de febrero**: seis meses y medio. Es el lote
mensual del ERP, el que se sube a mano entre el 2 y el 14 de cada mes — para LK se viene
subiendo, para Chef se dejó de hacer.

Y pasó desapercibido porque **el chequeo 4 de `rep_salud` mira sólo `empresa='lk'`**
(`from sales_lines where empresa='lk'`). Queda propuesto al dueño: sumarle la pata de Chef, o
—si esa data ya no le importa a nadie— sacar la MV en vez de arrastrarla.

## 3.bp ✅ Segunda tanda de correcciones: Av. Jujuy caía a 640 km (v14.27) — 2026-09-07

Las 49 que quedaron después de vaciar la cola **tampoco eran 49 problemas**: volvían a agruparse.

**Seis clientes en Av. Jujuy con barrio "Constitucion"**, todos con el mismo error: *"cayó a 640
km de Constitucion"*. La primera hipótesis —que `centroBarrio` estuviera resolviendo la
Constitución del interior— **se descartó midiendo**: desde la base, `city=Constitucion&state=Buenos
Aires` devuelve la Constitución correcta, la de CABA (-34.6242, -58.3836), igual que con
`state=Ciudad Autónoma`. Lo que fallaba era la consulta de la **dirección**: `"Av Jujuy 1240,
Constitucion, Buenos Aires"` le pegaba a la **provincia de Jujuy**, y el verificador geográfico
—bien— lo descartaba. O sea que el guard de la v13.42 hizo exactamente lo que tiene que hacer:
no ubicó nada mal, sólo no ubicó. Arreglo: `Avenida Jujuy NNNN` + barrio San Cristóbal, el mismo
que ya había funcionado con los cód 1284 y 1917.

Los otros grupos:

- **Cinco direcciones en "Donofrio", Ciudadela** → la calle se escribe **D'Onofrio**.
- **Dos del Mercado Central escritas como esquina sin altura** (`Circunv s/n y calle De la Pala`)
  → el mismo predio que el cód 1916, que sí ubicó: Av. Circunvalación 550, Tapiales.
- **Abreviaturas de nombre propio**, que el normalizador no puede adivinar porque no son un
  patrón sino un nombre: `Cjal` = Concejal · `Chilavet M Cnel.` = Coronel Chilavert ·
  `Av Raul Scalabr` = Raúl Scalabrini Ortiz · `Av. Int. Ravanal` = Intendente **Rabanal** (con b)
  · `Int P Quintana` = Intendente Pérez Quintana.
- **Dos barrios mal escritos o mal asignados**: `Adolfo Sordeaux` → **Sourdeaux**, y
  `Virgilio 2788`, que está en Villa Real y no en Villa Devoto.

**25 correcciones**, y `gv_geo_reintentar()` devolvió 47 a la cola.

**Lo que se dejó afuera a propósito**, porque adivinar una calle es peor que no ubicarla:
`Ortiz Carlos 1291` (¿invertido?), `Humberto Pino 3352`, `S Ortiz Y Aguirre 0` (esquina con
altura 0), `Panamericana 54,5` (es un kilómetro, no una altura), `Junin, Buenos Aires` (sin
altura), `AV. 22 DE OCTUBRE 235, CHIVILCOY` (interior: no se entrega) y Osa (retira en fábrica).
Las que no resuelvan vuelven solas a `GV_Geo_Fallidas` a los 3 intentos.

**Archivo:** `sql/gv_geo_normalizar_v1426.sql` (la segunda tanda está al final del mismo archivo).

### Dónde quedó (medido al cierre del 07/09, 22:20 ART)

```sql
select * from public.gv_geo_cobertura;
--  chef    43 direcciones · 38 ubicadas · 5 retira · faltan  0
--  lk     446 direcciones · 363 ubicadas · 59 retira · faltan 24
--  total  489            · 401          · 64        · faltan 24
```

**401 de 425 direcciones geocodificables** (las 64 de "retira" no van al reparto): **94%**.
Arrancó el día en 368 sobre un padrón de 2.307 sin acotar. El cron 75 quedó en `20 */6 * * *`.

**Las 24 que faltan son 24 clientes distintos, una dirección cada uno**, así que el costo real
es: esas paradas van últimas en el reparto hasta que se arreglen (el `?` de la hoja de ruta).
Ninguna es del interior salvo Chivilcoy, que no se entrega, y Osa, que retira en fábrica.

Un tercio son direcciones **que parecen normales** y Nominatim igual no encuentra
(`Av Entre Rios 637`, `Espinoza 2321`, `Av Nazca 1866`, `Av. Italia 2550`, `Av Belgrano 3180`,
`America 4175`, `Moises Lebenson 24`, `Julio Godoy 4656`, `John W. Cooke 3255`). Ahí ya no hay
patrón que exprimir: es el límite de Nominatim con direcciones argentinas abreviadas.

⚠ **Decisión del dueño, pendiente:** para ese último tramo el camino es un geocodificador pago
(Google Geocoding API tolera abreviaturas, acentos y typos mucho mejor). Serían **~US$2 por
única vez** para las 425 del padrón a US$5/1.000, más los clientes nuevos. No se contrató nada:
hace falta que él decida y que consiga la API key.

**Archivo:** `sql/gv_geo_normalizar_v1426.sql` (incluye el rollback en la cabecera: sacar el
`gv_dir_geo_normalizar(...)` del `dir_query` de las dos vistas y dropear la función; no escribe
nada, no hay datos que restaurar).

## 3.bn ✅ No se entrega en el interior: el padrón estaba mal leído (v14.20) — 2026-09-07

**La corrección del dueño, textual:** *"no entrego en ninguno del interior"* y, cuando le mostré
lo que tenía, *"quién del interior tenés? está mal, no entrego en esa dirección"*.

**Tenía razón.** En `customer_delivery_addresses` (LK), **`localidad` y `provincia` son del
CLIENTE, no de la dirección de entrega**. Caso real, cliente 15 (Bazar Tifni):

| campo | valor |
|---|---|
| `direccion_entrega` | `Las Casas 3553` |
| `localidad` / `provincia` | `Rosario` / `Santa Fe` ← **del cliente** |
| `direccion_expreso` | `LAS CASAS 3553, Boedo` ← **donde se entrega**, CABA |
| `zona_expreso` | `Boedo` |

Misma calle y altura, en Boedo. La entrega es en el **depósito del expreso**, en Buenos Aires.
La v14.16 pegaba la calle con la localidad del cliente y le preguntaba a Nominatim por
*"Las Casas 3553, Rosario, Santa Fe"*, que no existe. **Ése era el motivo de que fallaran todas
las del interior**, y de paso el que tapaba la cola (§3.bm).

**Medido** sobre las 573 filas de "interior" con dato de expreso: **533 (93,0 %)** tienen la
misma calle y altura en `direccion_entrega` y `direccion_expreso`, y **573 (100 %)** tienen
barrio de CABA y `zona_expreso` cargada.

**Conclusión: no existe una entrega en el interior.** Las 2.307 direcciones son de AMBA.

**Qué cambió**

- `GV_Clientes_Direcciones` suma `barrio_entrega`, `dir_expreso` y `nombre_expreso`.
  `barrio_entrega` = `zona_expreso` → barrio de `direccion_expreso` → `localidad`.
- El **`dir_key` pasa a armarse con el barrio DE ENTREGA**, no con la localidad del cliente.
- `amba` queda en `true` para las 2.307; la columna se deja por compatibilidad.
- `gv_geo_faltantes_padron` usa `barrio_entrega` y **manda `provincia` en null**: mandar la del
  cliente hacía buscar a 800 km.
- `gv_geo_cobertura` se parte por si el **cliente** es del interior (el corte que importa), no
  por `amba`, que ahora es siempre true.
- Edge Function `gv-sync-padron-direcciones` **v3**: pide `direccion_expreso` y, si el proyecto
  no la tiene (Chef puede no tenerla), reintenta sin ella en vez de perder ese padrón entero.

**Resultado medido, corridas consecutivas:**

| corrida | ubicadas de 40 |
|---|---|
| 19:03 (antes) | **7** |
| 19:11 (después) | **30** |

**Dos cosas que hubo que arreglar de paso**

1. Los fallos de `GV_Geo_Fallidas` estaban anotados contra la clave vieja → se borraron, esas
   direcciones merecían otra oportunidad con el barrio correcto.
2. Al cambiar el `dir_key`, las ~300 ya ubicadas dejaron de matchear (Chef AMBA cayó de 303 a 23
   en la vista). Las coordenadas no se habían perdido: se **copiaron a la clave nueva** con un
   `insert … select` en vez de volver a pedírselas a Nominatim. Verificado: Chef AMBA volvió a
   303 (89,9 %).

**Rollback y SQL completo:** `sql/gv_geo_barrio_entrega_v1420.sql`.

## 3.br ✅ Las OCs mostraban cada artículo DOS veces (v14.69) — 2026-09-10

**Síntoma (dueño, con captura):** en la pantalla de Órdenes de Compra cada línea aparecía
repetida (058 Cierra Bolsa dos veces, 229 Ñoquera dos veces, …) *"y pasa esto en todas las OCs"*.

**No era la pantalla, eran los datos.** El generador (`ocgGenerar`) hacía un **POST crudo** a
`Ordenes_Compra` sin ninguna guarda. Se corrió **dos veces el 2026-09-09** (`created_at` 14:25:25 y
15:40:38) → insertó TODAS las líneas de nuevo. La pantalla (`x.rows.forEach`) simplemente mostraba
lo que había: dos filas idénticas por artículo, y el pedido/impreso al tallerista salía al doble.

Confirmación:
```sql
-- 224 filas el 09-09, exactamente el doble de los 112 códigos distintos; 15:40 = 2da corrida
select fecha,proveedor,count(*)-count(distinct codigo) dup from "Ordenes_Compra"
where fecha='2026-09-09' group by 1,2 having count(*)>count(distinct codigo);
```

**Fix (backend, decisión del dueño).**
1. **Limpieza:** backup a `GV_Backup_OC_dup_20260909` (224 filas) → borrado de **109 duplicados**
   (se dejó el id más chico por `fecha+proveedor+codigo`; ninguno con recepción). Quedó en 115
   filas, 0 grupos duplicados en toda la tabla.
2. **Guarda:** RPC `gv_oc_generar_pendientes(jsonb)` (SECURITY DEFINER, grant sólo `authenticated`).
   El front la llama en vez del POST. Es **idempotente por día**: por `(fecha,proveedor,codigo)`
   borra la línea pendiente sin recepción y recién inserta → volver a generar refresca, no duplica;
   nunca toca ni re-inserta sobre una recibida/cerrada.

**Impacto medido:** antes 224 filas / 109 dup; después 115 filas / 0 dup. Correr el generador dos
veces ahora deja el mismo resultado (probado: la RPC devuelve las mismas líneas, sin sumar filas).

**SQL / rollback:** `sql/gv_oc_generar_pendientes_v1469.sql` y `docs/ROLLBACK-PRODUCCION.md`
(tabla compartida `Ordenes_Compra`).

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

---

## §3.bc — v14.13 (2026-09-07): el cruce Facturación ↔ ISIS asigna cada factura a UNA sola NP

**Qué estaba mal.** `gv_vista_cruce_facturacion` elegía, para cada NP, la factura de ISIS
más parecida en cajas. Nada impedía que dos NP del mismo cliente y el mismo día eligieran
**la misma factura**; cuando pasaba, las dos quedaban en estado `ambiguo` y no se cruzaban.
Medido el 07/09 sobre los últimos 30 días: **52 NP en `ambiguo`, las 52 con más de una
candidata** — o sea, el 100% de ese estado era este problema, no un dato dudoso.

**Qué se hizo.** `gv_cruce_fc_asignacion()` (plpgsql, nueva) recorre todos los pares
(NP, factura) elegibles ordenados por diferencia de cajas y después por diferencia de fecha,
y toma el par si ni la NP ni la factura fueron ya tomadas. Greedy, determinístico (desempata
por `np` y `doc_id`). La vista se apoya en eso. **La elegibilidad no cambió**: mismo cliente
(`canon_cod`), misma empresa, factura dentro de ±3 días de la fecha de salida y diferencia
de cajas dentro del 15% de lo entregado con piso de 1 caja.

El estado `ambiguo` **desaparece**. Una NP que se quedó sin factura porque otra se la llevó
cae en `sin_factura`, que es la verdad. `candidatos_cercanos` se conserva y ahora significa
"cuántas facturas eran elegibles para esta NP" — es la pista para revisarla a mano.

**Columnas: las mismas 22, en el mismo orden.** Por eso NO se tocaron
`gv_cruce_facturacion_resumen` ni `_totales` (hacen `select v.*`) ni la pantalla del cruce.
Hubo que castear `factura_total` / `factura_neto` / `factura_cajas` a `numeric` pelado: la
vista vieja los devolvía así (por el `CASE ... ELSE NULL::numeric`) y `create or replace view`
no deja cambiar el tipo de una columna.

**Medición (últimos 30 días, antes → después):**

| Estado | Antes | Después |
|---|---:|---:|
| ok | 221 | **257** |
| diff | 69 | **85** |
| ambiguo | 52 | **0** |
| sin factura | 60 | 60 |
| **total** | 402 | 402 |

Los 52 `ambiguo` se repartieron en 36 `ok` y 16 `diff`. `sin_factura` **no creció**: ninguna
NP perdió su factura contra otra. Invariante verificado: `0` facturas asignadas a dos NP, y
la vista devuelve 1.167 filas para 1.167 NP de `Facturacion_NP` (no multiplica).

**Costo:** `gv_cruce_facturacion_resumen` pasó a **1.215 ms** (la función es `volatile`, así
que la vista se calcula entera). Contra el `statement_timeout` de ~8 s, sobra. La pantalla
hace dos RPC en paralelo.

**Lo que el cruce dice hoy, y es el hallazgo que importa.** De las 85 con diferencia, las que
tienen **las mismas cajas** en la factura y en lo entregado suman apenas −$441.900 con un
promedio de **+0,5%** (ruido en los dos sentidos). Las que tienen **cajas distintas** se
llevan **−$3,88 M**. O sea: el problema no es de precios, es que **ISIS facturó menos cajas
de las que Gestión dice que se entregaron**. Hay que decidir si se facturó de menos o si
`cajas_ent` está inflada. Excepción aparte: Dorinka (chef 2686) NP 44601 y 44602 tienen cajas
idénticas y **−9,00% exacto** las dos — eso es un descuento, no ruido: tenemos `dto_vol = 0.165`
y la factura salió como si fuera ~0,235. Son $1,33 M entre las dos.

**Objetos nuevos**

- `gv_cruce_fc_asignacion()` — la asignación. `EXECUTE` revocado a `public`/`anon`/`authenticated`.
- `gv_cruce_facturacion_nps(text[])` — cruce acotado a una lista de NP, para el bloque
  "Ya tildados hoy" de la pantalla Facturación. `authenticated` (la operadora entra con Google);
  revocado a `anon`.
- `GV_Cruce_Avisadas(np, avisado_at, diff, estado)` — qué NP ya salieron por Telegram. RLS
  prendida, sin policies (la escribe sólo la función, que es SECURITY DEFINER).
- `gv_alerta_cruce_facturacion_telegram()` — digest diario. Sólo días hábiles
  (`gv_es_dia_habil`), excluye súper (su diferencia es esperable), ventana de 45 días, top 15
  por monto y "y N más". **Cada NP se avisa una sola vez.**
- **Cron 77 `gv-alerta-cruce-facturacion`**, `30 21 * * 1-5` (18:30 ART, después de la ventana
  en que entran los PDF, que es 14–17 h).

⚠ **La primera corrida arrastra el backlog: 145 NP y −$10.675.643** (45 días, sin súper), 42 de
ellas por cajas. Para arrancar limpio y que sólo avise lo nuevo:
`insert into public."GV_Cruce_Avisadas"(np, diff, estado) select np, diff, 'diff' from public.gv_vista_cruce_facturacion where estado='diff' and fecha_salida >= current_date - 45 and not es_super on conflict do nothing;`

**Rollback:** `sql/backups/gv_cruce_facturacion_20260907_pre_asignacion.sql` restaura la vista y
las dos RPC. Para la alerta: `select cron.unschedule('gv-alerta-cruce-facturacion');`

**Front (v14.13).** En "✓ Ya tildados hoy" cada NP lleva una pastilla con el importe de la
factura y el delta: 🟢 coincide · 🔴 diferencia (con el % y las cajas en el tooltip) · ⏳ sin FC
todavía · 🛒 súper. Se llena con `gv_cruce_facturacion_nps` y hay un botón "↻ Revisar contra
ISIS". **La lista de arriba son NP pendientes: todavía no tienen factura, ahí no hay nada que
cruzar** — por eso el cruce vive en las tildadas, que son las que la operadora acaba de
facturar (el agente que sube los PDF corre cada ~1 min). Además el botón "🔍 Cruce con ISIS"
lleva un número rojo con las NP en diferencia de los últimos 30 días.

---

## §3.bd — v14.15 (2026-09-07): watchdog de la ingesta de PDF de ISIS

**El agujero.** Los PDF de factura que emite ISIS **no los levanta nada de Supabase**: los
sube un agente Python que corre en una PC de la oficina, mira las carpetas `PDF_ISIS` /
`PDF_ISISCHEF`, parsea con `pypdf` y escribe en los buckets `isis-lk` / `isis-ch` y en
`isis_lk.documentos` / `isis_ch.documentos`. Si esa máquina se apaga o la tarea programada no
arranca, **no entra ninguna factura y no se entera nadie**: el trigger `wa_factura_notificar`
nunca corre (cero avisos de WhatsApp) y el cruce de Facturación se queda sin comprobantes.
Todo falla en silencio.

Al 07/09 la ingesta llevaba **52,6 h parada** — último PDF de Loeke el 05/09 08:31, de Chef el
04/09 16:08 — y nada en el sistema lo decía.

**El watchdog.** `gv_alerta_ingesta_isis_telegram(p_horas integer default 2)` mira el
`max(procesado_at)` de los dos `ingesta_log`; si pasaron más de 2 h avisa por Telegram con el
último horario de cada empresa y qué queda roto mientras tanto. Sólo días hábiles
(`gv_es_dia_habil`) y **un aviso por día** (dedup `gv_ingesta_parada_<fecha>`): mientras siga
caída no repite. Umbral parametrizado, así que subirlo o bajarlo no toca código.

**Cron 78 `gv-alerta-ingesta-isis`**, `*/30 13-22 * * 1-5` = 10:00–19:00 ART, que es la ventana
en la que la ingesta tiene actividad real (medido sobre 60 días: Loeke 14–17 h concentra el
99%, Chef pico a las 16).

El lunes 07/09 es feriado (Día del Metalúrgico, cargado en `GV_Dias_No_Habiles`), así que el
watchdog calla ese día y, si la ingesta sigue caída, el primer aviso sale el **martes 08 a las
10:00**.

**Rollback:** `select cron.unschedule('gv-alerta-ingesta-isis');`
**SQL:** `sql/gv_alerta_ingesta_isis.sql` (y `sql/gv_alerta_cruce_facturacion.sql` para el §3.bc).

⚠ **Pendiente que este watchdog NO resuelve: el script del agente no está versionado en ningún
repo**, sólo existe en esa PC. Su hermano de las notas de crédito sí está
(`agente-local/nc_ingest.py`) y sirve de patrón, pero el parser de facturas se perdería con la
máquina. Hay que traerlo y commitearlo.

## §3.be — v14.30 (2026-09-08): Conciliación forward-looking (pestaña de Facturación)

**Qué pidió Luis.** Partir el módulo de Facturación en dos solapas: **Facturador** (lo de
siempre) y **Conciliación**. Conciliación NO es el cruce retrospectivo de 30 días (ese sigue
existiendo en "🔍 Cruce con ISIS" → Deuda/Cobranzas, §ver `gv_cruce_facturacion`). Es un
**registro forward-looking**: *"a partir de hoy, siempre que se manda algo a facturar desde
Gestión, ponelo en una tabla y en otra columna el monto de la factura parseada que le
corresponde"*, más recientes arriba. Y *"este módulo debería ser un SNAPSHOT de lo que se
mandó vs lo que se facturó realmente; el resto del pipeline siempre en vivo"*.

**El disparador (orden del dueño, confirmado en el código).** Las dos formas de facturar
pasan por el MISMO choke point del front, `facMarcarFacturada`:
- **NP web (LK/CH):** se marca la casilla y se baja el **Excel ISIS** (`facXlsBajar`) →
  *bajar el Excel ES la facturación* (no hay tilde adicional); después una persona lo importa
  a mano en ISIS.
- **NP de ISIS:** botón **✓** (tilde, `facTickNP`).
Ahí mismo, con la NP ya escrita en `Facturacion_NP`, el front dispara la RPC de registro.

**Objetos nuevos (todo `GV_`/`gv_`, no toca nada de Producción). SQL: `sql/gv_conciliacion_facturacion.sql`.**
- **`GV_Conciliacion_Facturacion`** — tabla nuestra, RLS prendida, policy `select` a
  anon/authenticated, **sin** insert/update/delete a la anon key. PK = `np` (un envío por NP;
  si se re-factura, no se repisa el snapshot original). Columnas: `empresa, tanda, cod_cliente,
  razon_social, fecha_salida, cajas_ent, neto_gestion` (SNAPSHOT del neto que Gestión calculó),
  `items_sin_precio, origen ('web'|'isis'), registrado_at`.
- **`gv_conciliacion_registrar(p_np text)`** — SECURITY DEFINER. Congela el neto de Gestión
  desde `gv_vista_facturacion_neto` (= cajas ENTREGADAS × lista × descuento, web ×0,98) + los
  datos de la NP de `Facturacion_NP`. `ON CONFLICT (np) DO NOTHING`.
- **`gv_conciliacion_lista(p_limit,p_offset,p_q,p_empresa)`** — SECURITY DEFINER. Snapshot ⋈
  factura parseada **en vivo** (`left join gv_vista_cruce_facturacion` por np: neto real, cajas,
  comprobante, PDF, es_super). La diferencia y el estado (`ok`/`diff`/`sin_factura`/`sin_neto`)
  se recalculan CONTRA el neto congelado. Orden `registrado_at desc` (más recientes arriba).
- **`gv_conciliacion_totales(p_empresa)`** — SECURITY DEFINER, resumen por estado.

**Front (`index.html`).** Barra de 2 solapas en `#facturacionModal` (`facSetTab`), el contenido
viejo envuelto en `#facPanelFact`, el nuevo en `#facPanelConcil` (`_concil`, `concilRefresh`,
`concilRender`, `concilAbrirFactura` reusa `deudaAbrirFactura` para el PDF). El registro del
snapshot se hace por **`fetch` directo** a `/rest/v1/rpc/gv_conciliacion_registrar` con los
`headers` que ya tiene `facMarcarFacturada` — NO por `sb.rpc`, porque `facMarcarFacturada` vive
en el primer `<script>` y `const sb` en el segundo (no comparten scope; el bloque A habla con
Supabase por `fetch`). El botón "🔍 Cruce con ISIS" queda como estaba (decisión de Luis).

**Medición al crear (08/09).** Tabla arranca **vacía** (se llena desde la próxima facturación).
Probado con la NP real 98619 (facturada hoy 09:01): `gv_conciliacion_registrar('98619')` congeló
`neto_gestion = 16.136.550`; `gv_conciliacion_lista` la cruzó con la factura ISIS
`FC-A-0005-00000908` (`factura_neto = 16.136.550`) → diff 0, estado `ok`. Fila de prueba borrada
después. Advisors de seguridad: la tabla queda limpia (RLS + policy, `search_path` fijo); los 2
WARN `*_security_definer_function_executable` son el mismo patrón que ya usan las RPC del cruce
(exponer un cálculo a la anon key sin dar acceso directo a las vistas/FDW), intencional.

**Smoke:** `tests/fac-conciliacion.cjs` (2 solapas, snapshot Gestión vs ISIS, estados, 📄, y que
el snapshot se registre al facturar). En `tests/run.sh`.

**Rollback:**
```sql
drop function if exists public.gv_conciliacion_totales(text);
drop function if exists public.gv_conciliacion_lista(int,int,text,text);
drop function if exists public.gv_conciliacion_registrar(text);
drop table if exists public."GV_Conciliacion_Facturacion";
```
y en el front sacar la barra de solapas / `facSetTab` / `concil*` y el `fetch` del registrar.

**Backfill (08/09, pedido de Luis).** Se cargaron a mano las NP facturadas desde el viernes
04/09 (`facturado_at >= 2026-09-04 -03`), mismo cálculo que el registrar (neto de
`gv_vista_facturacion_neto`, `registrado_at = facturado_at`, `on conflict do nothing`): **8 NP**
→ 7 `ok` + 1 `diff` (−$85.264,12). De ahí en adelante se llena sola desde `facMarcarFacturada`.
Rollback del backfill: `delete from public."GV_Conciliacion_Facturacion" where registrado_at < now();`
(o el `drop table` del rollback general).

**v14.31 (08/09) — 📋 detalle "a facturar" por NP.** Pedido de Luis: *"además del PDF de la
factura, mostrame el listado a facturar que aparecía en la página, para visualizar el error"*.
Botón 📋 en cada fila de Conciliación → modal con las líneas que Gestión mandó a facturar
(cód, artículo, cajas entregadas, U×B, precio de lista, importe) + los totales Gestión/ISIS/diff
y el 📄 al lado, para comparar renglón por renglón. Backend: `gv_conciliacion_detalle(p_np)`
(SECURITY DEFINER, lee `gv_vista_facturacion_neto_items`). Front: `concilDetalle`/`concilDetRender`
(modal `#concilDetOverlay`). Smoke ampliado en `tests/fac-conciliacion.cjs`.
Rollback: `drop function if exists public.gv_conciliacion_detalle(text);`

**v14.32 (08/09) — la factura abre en POPUP, no en pestaña nueva.** Pedido de Luis: *"que la
factura la abra en un popup y no que la mande a una pestaña diferente, para facilitar
visualización/comparación"*. `concilAbrirFactura` ya no delega en `deudaAbrirFactura`
(`window.open(_blank)`): abre un modal in-page (`#concilPdfOverlay`) con la firma temporal
(`_concilSignedUrl`, `sb.storage.createSignedUrl` 600 s) embebida en un `<iframe>`. Y el modal
📋 de detalle pasó a DOS paneles: izquierda el listado a facturar de Gestión, derecha el PDF de
la factura de ISIS embebido — para comparar renglón por renglón sin salir de la pantalla; el
botón del header quedó como "⤢ Ver la factura en grande" (abre el popup grande). Sólo front.

**v14.33 (08/09) — un solo botón "🔍 Comparar": PDF + detalle en paralelo.** Pedido de Luis:
para los casos con diferencia, ver la factura de ISIS y el detalle a facturar de Gestión juntos.
Se sacó el botón 📄 suelto de la fila; ahora hay UN botón por fila ("🔍 Comparar") que abre el
modal grande (≈1400px) con dos paneles lado a lado: izquierda el listado a facturar de Gestión,
derecha el PDF de la factura embebido (iframe, 76vh). Dentro sigue el "⤢ Ver la factura en grande"
para el visor a pantalla casi completa. Nada abre pestaña nueva. Sólo front.

---

## §3.bf — v14.35 (2026-09-08): las NP de ISIS **sin tanda** entran a "A Programar"

**El pedido del dueño (08/09):** *"necesito que aparezcan en A Programar así lo programo"*, con la
lista de NP 98686-98694 (LK), 44618 (Chef) y 44609-44617 (Cencosud).

### Qué estaba pasando

Esas NP estaban en `PPP_Programacion_Diaria` con **fecha de entrega puesta y `tanda = ''`**. Tierra
de nadie:

- **En "A Programar" no salían** porque esa solapa lista **pedidos de la página** (`order_id`, vista
  `v_pedidos_web_np` de LK y RPC `gv_pedidos_web_np_chef_admin`) y `gv_pedidos_web_excluidos` las saca
  con dos motivos a la vez: `anterior_al_cambio` (`fecha_recep = 02/09` < `gestion_desde = 03/09`) y
  `en_produccion` (ISIS ya les dio NP). Los `orders` de LK eran 1330/1331/1332/1335/1337/1338/1339 y el
  de Chef el 214. Las de Cencosud **ni siquiera son pedidos web**: entraron por el Excel de Krikos, no
  hay `order_id` que mostrar.
- **En la solapa Programación sí estaban** (bajo su día, en el grupo "sin tanda"), pero nadie las podía
  pickear y el cupo del día no las contaba.

### Por qué NO se arregló desexcluyéndolas

Si entraran por la vía web, `gv_ppp_web_tanda_agregar` les asignaría una **NP web nueva** (`LK 00xx`) y
al facturar el Excel de ISIS las cargaría **otra vez**: dobles. Estas NP ya existen en ISIS; hay que
programarlas **con su número**.

### Lo que se hizo

- **`gv_ppp_isis_sin_tanda`** (vista, `security_invoker`): NP de ISIS **viva** (no facturada, no
  entregada, no cancelada) que está en `gv_ppp_programacion_diaria` sin tanda, con cliente, zona, m³ y
  las líneas/cajas de `PPP_Base_Pedidos`. `es_super` usa la MISMA expresión que `gv_ppp_super_mezclado`
  (`zona ~* 'super|coto|carrefour|chango|krikos'`).
- **`gv_ppp_isis_programar(p_nps, p_fecha, p_por)`** (SECURITY DEFINER): arma UNA tanda con esas NP y la
  escribe en **`GV_PPP_Prog_Override`** (np, tanda, fecha_entrega, nota). **No toca
  `PPP_Programacion_Diaria`**, que es compartida con Producción. Es el mismo mecanismo de
  `gv_ppp_tanda_mover` (§3.bb, v13.87) y del override manual de 44619 → E07A (§3.ap, v13.50). El código
  sale de `gv_ppp_web_tanda_codigo_nuevo()`, que ya cuenta el override, así que no repite.
  - Gate de supervisor (`gv_es_supervisor_o_servicio`).
  - Corta si alguna NP dejó de estar sin tanda (otro la programó mientras tanto) y dice cuál.
  - **Regla del dueño v14.23**: mezclar un súper con clientes en la misma tanda es **error**, no aviso.
    Como el código es de camión nuevo, un súper nunca cae en el camión de un cliente.
  - Avisos que **no** bloquean (los muestra el front): cupo del día pasado, día no hábil.
- **Front (`A Programar`)**: `aprTraerIsis()` las trae y se suman a `_apr.pedidos` disfrazadas de pedido
  (`order_id = "np" + np`, `_isis: true`) para reusar tal cual el tildado, el paso 2, los avisos del día
  y la botonera. La tarjeta muestra la **NP real** (`aprPedLabel`) y un chip **"🧾 de ISIS · la programás
  vos"** (el armado automático no las toca). **No se pueden juntar** con un pedido de la página en la
  misma tanda: son dos escrituras distintas (`aprPasoDia` y `aprGenerarTanda` lo bloquean).

### Medido (08/09)

`select * from gv_ppp_isis_sin_tanda` → **10 filas**: 98686-98694 (LK, cliente 1792 Dapelo ×7, 1618
Oriental Party, 1964 Veronesi) y 44618 (Chef, 1544 Perez), todas con entrega 14/09 y su zona. Las 9 de
Cencosud (44609-44617) **ya no están**: el espejo del Excel les trajo tanda (D72A/D72B/D72C, 10 y 11/09),
así que la vista las deja fuera sola — que es lo que tiene que pasar.

Test: `tests/apr-isis-sin-tanda.cjs` (14 chequeos, en `tests/run.sh`). SQL:
`sql/gv_ppp_isis_sin_tanda_v1435.sql`.

**ROLLBACK:**
```sql
drop function public.gv_ppp_isis_programar(text[], date, text);
drop view public.gv_ppp_isis_sin_tanda;
-- y para deshacer lo ya programado por acá:
delete from public."GV_PPP_Prog_Override" where nota like 'v14.35%';
```
(el front tolera que la vista no exista: `aprTraerIsis` devuelve `[]` y la solapa sigue mostrando los
pedidos de la página).

## 3.bo ✅ Descuento de cliente casi en vivo: sync cada 15 min + upsert condicional (v14.36) — 2026-09-08

**Contexto.** El `dto_vol` que usa Facturación (`facturacion_neto`, `gv_lk_np_feed`) sale de la tabla
local `clientes_dto`, que refresca la Edge Function `sync-clientes-dto` desde `customers.dto_vol` de
**LK** (`kwkclwhmoygunqmlegrg`) y **Chef** (`nkhzocgdpwtgrmwleihr`). El cron 61 sólo disparaba si el
snapshot tenía **>14 días** → un cambio de descuento hecho desde loekemeyer.com / chefsrl.com podía
tardar hasta 14 días en llegar al facturador. Pedido del dueño: que llegue solo, más seguido.

**Qué se hizo.**
1. **Edge Function `sync-clientes-dto` v2 (deploy v9, `verify_jwt=false`).** Ahora hace **upsert
   condicional**: primero lee `clientes_dto` (`fetchActual`), arma el diff contra LK+Chef y **escribe
   sólo las filas nuevas o cuyo `dto_vol` cambió**. Antes reescribía las ~2034 filas en cada corrida.
   Devuelve `{ok, cambios, evaluados, lk, chef}`. Con esto puede correr seguido sin churn ni dead tuples.
   Fuente: `supabase/functions/sync-clientes-dto/index.ts`.
2. **Cron 61 (`sync-clientes-dto-14d`, el nombre quedó, no se pudo renombrar por permisos):**
   `0 8 * * *` con guard de 14 días → **`*/15 * * * *`** sin guard. El `http_post` va sin auth
   (por eso la función tiene que quedar `verify_jwt=false`).

**Medido (08/09).**
- Editado `dto_vol` de LK 4091 (Swing Bazar) 0 → 0,05 y LK 4254 (Vargas) 0 → 0,06 desde el front:
  ambos aparecieron en `customers` al toque.
- Corrida vía el path del cron (sin Authorization) → `200 {ok:true, cambios:1, evaluados:2034}`:
  detectó la única fila cambiada (4254) y escribió esa nada más. Verificado que `clientes_dto` 4091
  y 4254 quedaron en 0,05 y 0,06.
- Sin cambios pendientes ⇒ `cambios:0`, cero escrituras.

**⚠ Tropiezo (resuelto):** el primer deploy por MCP dejó `verify_jwt=true` por default → el cron
recibía `401 UNAUTHORIZED_NO_AUTH_HEADER`. Se redeployó con `verify_jwt=false`. **Al redeployar
esta función, pasar SIEMPRE `verify_jwt=false`.**

**Backup:** `clientes_dto_bkp_20260908` (2035 filas), borrable cuando se confirme todo OK.

**Rollback:**
```sql
select cron.alter_job(61,
  schedule := '0 8 * * *',
  command  := $cmd$
    SELECT CASE
      WHEN (SELECT COALESCE(max(actualizado), 'epoch'::timestamptz) FROM public.clientes_dto)
           < now() - interval '14 days'
      THEN net.http_post(
             url := 'https://hrxfctzncixxqmpfhskv.supabase.co/functions/v1/sync-clientes-dto',
             body := '{}'::jsonb, headers := '{"Content-Type":"application/json"}'::jsonb)
      ELSE NULL END;
  $cmd$);
```
(y redeployar la v1 de la función si se quisiera volver al upsert total; la v2 es un superset, no hace falta).
**v14.37 (08/09) — Conciliación: toggle, diagnóstico de la diferencia y "ya corregido".** Pedido
de Luis. (1) El **"↻ Refrescar"** sí funciona (re-consulta; como el match con ISIS es en vivo,
actualiza la columna ISIS/dif a medida que ISIS sube facturas) — ahora con feedback "Actualizando…".
(2) Switch **"Sólo diferencias"** al lado de Refrescar: filtra en memoria a las NP con diferencia
(o que la tuvieron y ya se corrigieron). (3) **Diagnóstico**: `gv_conciliacion_comparar(np)` compara
línea a línea el cálculo ACTUAL de Gestión vs los `documento_items` de la factura de ISIS matcheada
(precio, dto_1+dto_2, cajas, importe), con un `motivo` por renglón; el modal 🔍 Comparar arma un
bloque "🩺 Diagnóstico" (descuento distinto, diferencia pareja de X% → lista/descuento/factor,
precio puntual, artículos sin precio, faltantes de un lado) + la tabla Gestión‑vs‑ISIS resaltando
los renglones con diferencia, al lado del PDF. (4) **Corregido**: `gv_conciliacion_lista` suma
`neto_actual` (recálculo en vivo) y `corregido` (tenía diff en el snapshot pero hoy el cálculo ya
coincide con ISIS) → la fila muestra **✔ Corregido** y el modal una leyenda con el error original
(cuánto era) y que ya está corregido. Caso testigo Vargas (98484): el 6% de descuento ya se
corrigió; queda ~2% del factor web ×0,98 + un precio puntual (809E $3.005 vs $4.060). Backend:
migración `gv_conciliacion_diag_corregido_v1434` (`sql/gv_conciliacion_facturacion.sql`). Smoke:
`tests/fac-conciliacion.cjs` ampliado. Sólo lectura, todo `gv_`.

## §3.bg — v14.38 (2026-09-08): 358 teléfonos de WhatsApp cargados, y la tabla vieja no distingue empresa

**Qué pasó.** El dueño devolvió el listado de clientes sin WhatsApp
(`clientes_whatsapp_completadoNuevo.xlsx`) con la columna I completada: **358 teléfonos**
(**235 de Loekemeyer + 123 de Chef**), todos en formato `+549XXXXXXXXXX`.

**Dónde se escribió y por qué.** La fuente de verdad de los teléfonos es
**`public.whatsapp_clientes` de VIRGILIO**, no la tabla de LK: `sincronizar_ppp()` (LK, cron **19**,
`0 10 * * *` UTC = 07:00 ART) hace `DELETE ALL + INSERT` de `public.wa_clientes_telefono` leyendo
`virgilio.whatsapp_clientes` por FDW. Escribir en LK se habría perdido en la corrida siguiente.

**El problema de fondo (queda abierto).** `whatsapp_clientes` tiene **PK `(cod_cliente)` y no guarda
empresa**, y hay **314 códigos que existen a la vez en LK y en Chef con clientes distintos**
(LK 1104 = Ramirez Miguel; CH 1104 = Monica Gerbaudo). `vista_avisar_programacion` resuelve el
teléfono con `LEFT JOIN LATERAL … WHERE trim(whatsapp_clientes.cod_cliente) = g.cod`, o sea **por
código solo**. Por eso se creó la tabla canónica:

```sql
public."GV_Clientes_Whatsapp" (empresa, cod_cliente, telefono, razon_social, origen, actualizado)
  primary key (empresa, cod_cliente)   -- RLS on: select anon+authenticated, all authenticated
```

**Qué se cargó.**

| Tabla | Filas | Nota |
|---|---|---|
| `GV_Clientes_Whatsapp` | **358** (LK 235 · CH 123) | canónica, con empresa. Nada se pierde |
| `whatsapp_clientes` | **+332** (610 → **942**) | espejo de compatibilidad, `on conflict do nothing` |
| `GV_Backup_whatsapp_clientes_20260908` | 610 | backup previo (protocolo) |

**Los 13 que NO se espejaron.** Códigos que están en LK y en Chef con **teléfonos distintos** —
`94, 820, 984, 1941, 2152, 2207, 2256, 2340, 2358, 2383, 2400, 2473, 2516`. La tabla vieja sólo
puede guardar uno; mandarle el aviso al cliente equivocado es peor que no mandarlo. Están completos
en `GV_Clientes_Whatsapp`. **Para destrabarlos hay que hacer que la vista resuelva por
(empresa, cod)**, no por cod.

**Medición (post-carga).**

```sql
-- 0 filas viejas alteradas, 610 → 942
select (select count(*) from public.whatsapp_clientes w
          join public."GV_Backup_whatsapp_clientes_20260908" b using (cod_cliente)
         where w.telefono is distinct from b.telefono) as alteradas,
       (select count(*) from public.whatsapp_clientes) as ahora;
-- 26 = los 13 códigos x 2 empresas, sin espejar a propósito
select count(*) from public."GV_Clientes_Whatsapp" g
 where not exists (select 1 from public.whatsapp_clientes w where w.cod_cliente = g.cod_cliente);
```

**Cuándo lo ve el bot de LK.** En la próxima corrida del cron 19 (07:00 ART). Para adelantarlo:
`select public.sincronizar_ppp();` en el proyecto LK.

**A revisar por el dueño.** `LK 311 Schell Venancio Raul` quedó con `+5215615697005` — prefijo **+52
(México)**, único no argentino de los 358. Se cargó tal cual vino; si es error, corregirlo en las dos
tablas.

**Rollback.** `truncate public.whatsapp_clientes; insert into public.whatsapp_clientes select * from
public."GV_Backup_whatsapp_clientes_20260908"; drop table public."GV_Clientes_Whatsapp";`
SQL completo: `sql/gv_clientes_whatsapp_carga_20260908.sql`.
**v14.40 (08/09) — Conciliación: "corregido" = IDÉNTICO + columna "¿Por qué?".** Luis marcó que
la 98484 aparecía "✔ Corregido" con −5,28% en pantalla. Dos cosas: (a) el badge usaba la
tolerancia del 1% → el cálculo actual estaba a 0,76% de ISIS ($11.663 sobre $1,53 M) y lo daba
por corregido. Ahora **'ok' y 'corregido' exigen |dif| ≤ $100** (idéntico salvo redondeo); 98484
vuelve a "Diferencia". (b) La columna Diferencia mostraba el diff del snapshot (−5,28%) al lado de
"Corregido" → contradictorio; ahora en filas corregidas muestra el estado ACTUAL ("✔ igual hoy",
verde) con el diff original en el tooltip. Además, nueva **columna "¿Por qué?"** con la causa
(`gv_conciliacion_motivo` a partir de la comparación línea a línea): dif. pareja %, descuento,
precio: <cods>, N sin precio, N sólo factura/Gestión. Backend: `gv_conciliacion_estricto_motivo_v1438`.
98484 hoy: estado "Diferencia", motivo "dif. pareja −2,0% (lista/descuento/factor) · precio: 809E ·
1 sólo en factura". Smoke `fac-conciliacion` actualizado.

---

## §3.bh — v14.42 (2026-09-08): Facturación — fecha de descarga, condición de pago, historial y el nombre del cliente de la NP web

Cuatro pedidos del dueño en el mismo mensaje.

### (a) Columna A del Excel = el día en que se baja el reporte

Antes la col A era `r.fechaTxt` = la **fecha de recepción** de la NP (de `PPP_Base_Pedidos.fecha`
para las de ISIS, de `PPP_Web_Programacion.fecha_recep` para las web). Ahora es la fecha de **hoy**
(`_facXlsHoyTxt()`, zona AR).

> ⚠ **Consecuencia, dicha antes de hacerlo:** ISIS toma esa fecha como fecha del pedido al importar.
> Una NP de la semana pasada que se baje hoy entra a ISIS con la fecha de hoy. La fecha de recepción
> real **no se pierde**: sigue en `PPP_Web_Programacion.fecha_recep` / `PPP_Base_Pedidos.fecha`, y
> ahora también viaja en el detalle guardado de cada descarga (`fechaRecep`).

De paso se unificó el armado: `_facXlsDescargar` (.xls XML 2003) ya no rearma las filas por su
cuenta — usa `_facXlsFilasPlanas`, la misma que el `.xlsx`. Antes la fecha y la condición de pago
había que tocarlas en **dos** lugares y era cuestión de tiempo que se desincronizaran.

### (b) Columna J = la condición de pago que eligió el cliente

Estaba **hardcodeada en `""`** con el comentario *"el código de condición no está espejado en
Virgilio"*. Sí está, del lado de LK: `v_pedidos_web_np.condicion_pago_code` (LK) y
`gv_pedidos_web_np_chef_admin` (Chef) lo devuelven los dos. `_facXlsArmar` arma `condByOrder`
(clave `empresa:order_id` — la condición es del **pedido**, no del bloque) con una vuelta más a LK,
y cada fila sale con `cond`. Si la lectura falla, la columna va vacía como antes.

**Una NP de ISIS no tiene condición de pago acá** (nunca pasó por la página): queda vacía. Es lo
correcto — el dato no existe de nuestro lado.

En el `.xlsx` las columnas I y J estaban escritas como `""` literales en el array de la fila; ahora
llevan `leyenda2` y `condPago`. El `.xls` XML ya las tomaba del item.

### (c) Solapa **📥 Descargas**: historial de Excel + los PDF de factura

Dueño: *"una vez que descargo el excel no puedo ver el detalle más… hacé una ventana dentro del
módulo de Facturación que tenga los pdf descargados y que ahí aparezcan los que se fueron
descargando a lo largo del tiempo"*. Eligió **las dos cosas**.

- **`GV_Fac_Export`** (tabla nueva, prefijo `GV_`, RLS sin policy para `anon`): una fila por
  descarga con `archivo`, `empresa`, `formato`, `nps[]`, `n_filas`, `creado_por` y **`detalle`
  (jsonb)** = las mismas líneas que se escribieron en el Excel.
- **RPC con gate de supervisor** (`gv_es_supervisor_o_servicio`): `gv_fac_export_registrar`,
  `gv_fac_export_lista` (liviana, sin el detalle) y `gv_fac_export_detalle(id)`. `anon` no escribe
  ni lee la tabla directo (`docs/RIESGO-ESTRUCTURAL-CANON.md`).
- **Front**: `facSetTab` pasó a tres paneles. La solapa tiene dos sub-solapas —
  **Excel a ISIS** (🔎 Detalle en pantalla, ⬇ Bajar de nuevo) y **Facturas de ISIS (PDF)** (los
  mismos de Conciliación, filtrados por `storage_path`, abiertos con `concilAbrirFactura`).
- **Volver a bajar** regenera el archivo con `_facXlsXml` desde el `detalle` guardado: **no**
  recalcula contra la base, porque `PPP_Base_Pedidos` es amnésica y las líneas de una NP vieja ya
  no están. Sale idéntico al original.
- El registro es **best-effort** dentro de `facXlsBajar`: si la RPC falla, el Excel ya se bajó.

Sólo guarda **de la v14.42 en adelante**; lo bajado antes no existe en ningún lado.

### (d) La NP cargada por la página no mostraba el nombre del cliente

En **Consulta de Notas de Pedido — Composición a líos** (`npcLoad`). La cabecera (cod + razón
social) salía de `gv_ppp_entregados_meta` y `gv_ppp_programacion_diaria`, que son el **espejo de
ISIS** y no contienen las NP de la página (`LK 0011`, `CH 0003`): por eso salían en blanco. Se sumó
`gv_ppp_web_estado` (que ya expone `np_label`, `cod_cliente`, `razon_social`, `tanda`,
`fecha_entrega`) como tercera fuente, con la misma forma que `ppMap`.

### Medido / test

`tests/fac-descargas.cjs` (17 chequeos, en `tests/run.sh`): col A = hoy y `fechaRecep` conservada,
col J con el code, el XML sigue con 12 columnas, la solapa abre y lista, 🔎 Detalle pide el detalle,
la sub-solapa de PDF lista y abre con el visor de siempre, registrar manda archivo + NP + detalle, y
las dos NP (web e ISIS) muestran razón social en Consulta de NP.

SQL: `sql/gv_fac_export_v1436.sql`.

**ROLLBACK:**
```sql
drop function public.gv_fac_export_detalle(bigint);
drop function public.gv_fac_export_lista(integer);
drop function public.gv_fac_export_registrar(text, text, text, text, text[], integer, jsonb, text);
drop table public."GV_Fac_Export";
```
(el front tolera que no estén: la solapa muestra el error y el resto de Facturación no se toca. Para
volver la col A a la fecha del pedido: en `_facXlsFilasPlanas`, `fecha: hoyTxt` → `fecha: r.fechaTxt`.)

**v14.43 (08/09) — Conciliación: prorrateo del descuento global de ISIS (neto vs neto).** Luis vio
que LK 0011 daba diff $0 al neto pero cada renglón marcaba 2% en rojo. Causa: la página LK mete el
2% web en el BRUTO de cada ítem y ISIS lo aplica como UN renglón global ("2% Descuento Web", que el
parser detecta pero con importe null). `gv_conciliacion_comparar` ahora excluye las líneas sin código
y multiplica cada renglón de ISIS por el factor = `subt_gravado` (neto) / suma de renglones brutos →
compara neto contra neto. El neto es el dato confiable del parser (medido: neto = renglones × 0,98 en
5/5 facturas web). LK 0011 cierra a $0 en todos los renglones; Vargas 98484 queda con la única
diferencia REAL (809E, $3.005 vs $4.060 = todo el desvío de $11.662). Backend:
`gv_conciliacion_comparar_prorrateo_v1441`. Front: nota en el modal. Sólo lectura, todo `gv_`.

## §3.bi — v14.44 (2026-09-08): dos listas de precios separadas por empresa (raíz del defasaje 809E)

**El bug.** El diff de Vargas (98484) no era de descuentos: era de **precio de lista**. El 809E vale
**$4.060 en LK** y **$3.005 en Chef**, y una NP de LK estaba tomando el de Chef. Raíz: la Edge Function
`sync-precios-venta` (cron 66, 09:00) traía `products` de LK y de Chef y los **mergeaba en una sola
tabla `precios_venta` con "si el código coincide, Chef gana"**. Los 3 códigos compartidos quedaban con
el precio de Chef para todos: 809E 3005 (LK real 4060), 437E 5180 (LK 4655), 438E 7320 (LK 6615).
`precios_venta_chef` existía pero se cargaba **a mano** (última vez 17/08) y sólo la leían
`gv_ppp_np_valor` y `cobranzas_precios`, que ya enrutaban por empresa; el resto de la valuación leía la
lista mezclada.

**El fix (dos partes).**
1. **`sync-precios-venta` v14.44** (Edge Function, redeploy): `precios_venta` = **sólo LK**,
   `precios_venta_chef` = **sólo Chef** (ahora automático, ya no a mano). Cada lista es de su empresa.
2. **`gv_vista_facturacion_neto_items`** (migración `gv_vista_facturacion_neto_items_ruta_empresa_v1444`):
   el join se enruta por empresa, igual que `gv_ppp_np_valor`:
   - NP de LK → `precios_venta` (`pv`)
   - NP de Chef → `precios_venta_chef` (`pc`)
   - artículo **"L"** en NP de Chef (505L, 438EL) → `pv` por el código pelado (regla v13.71/73).
   Se fundió también la migración del sufijo L (antes vivía como nota al pie).

`gv_ppp_np_valor` y `cobranzas_precios` (base = `precios_venta` como 'lk' ∪ `precios_venta_chef` como
'ch') quedaron correctos **solos** al ser `precios_venta` sólo LK. `gv_fac_ajustes_isis` no cambia:
usa `precios_venta EXCEPT precios_venta_chef`, que da lo mismo con la lista mezclada (LK∪Chef \ Chef =
LK\Chef) que con LK sola (LK \ Chef).

**Medido (08/09).** Enrutamiento en las líneas reales: 809E → LK 4060 (29 NP) / Chef 3005 (42 NP);
437E → 4655/5180; 438E → 6615/7320; 438EL → 6615 (LK pelado). **NP 98484 (Vargas): neto calculado
1.530.177,68 = factura ISIS 1.530.177,68, diff $0, estado `ok`** (era `diff`). Chef **sin cambios**
(sus precios compartidos ya eran los de Chef). Corte por estado (30 días): LK ok 257 / diff 41 /
sin_factura 49; Chef ok 31 / diff 16 / sin_factura 11.

**Producción.** Sus vistas sin `gv_` (`vista_facturacion_neto_items`, `vista_facturable_anticipado`,
`vista_plata_perdida`) siguen leyendo `precios_venta` sin enrutar → valúan Chef contra la lista de LK.
Es aceptado: Producción ya no se usa (todo migró a Gestión). No se tocaron esas vistas (regla de lo
compartido). Si algún día hiciera falta, se les agrega la misma rama por empresa.

**Backup / rollback.** Snapshot: `public.gv_bkp_precios_venta_20260908` (337 filas) y
`gv_bkp_precios_venta_chef_20260908` (101). Rollback: volver el join de la vista a
`left join precios_venta pv on canon_cod(pv.cod)=b.cod_precio` y re-mergear Chef en `precios_venta` en
la Edge Function. Archivos: `supabase/functions/sync-precios-venta/index.ts`, `sql/gv_cruce_facturacion.sql`.

**v14.45 (08/09) — refresco cada 15 min.** El sync de precios pasó de diario (06:00 ART, con guarda de
24 h) a **cada 15 min** (`cron.alter_job(66, schedule := '*/15 * * * *')`, guarda sacada). Motivo: que un
cambio de precio en LK/Chef se refleje casi en vivo (lag ≤ 15 min) **sin poner un trigger en los
proyectos de las páginas** (evaluado: trigger en `products` de LK/Chef corre para la app de esas páginas
y es cross-project → descartado). La función es idempotente y liviana (~330 LK + ~100 Chef), correrla
seguido no molesta. Watchdog: subir el umbral del job 66 a ~120 min. `sql/sync_precios_venta.sql`.
Rollback: `cron.alter_job(66, schedule := '0 9 * * *', command := <bloque con guarda de 24 h>)`.

## §3.bj — v14.46 (2026-09-08): `gv_articulo_empresa`, la identidad de empresa por artículo (Fase 1)

Fase 1 del modelo pedido por el dueño: *"la empresa del código determinada por una columna de
identidad (cod: 505, empresa: LK), que aparezca en todo el pipeline"*. Vista nueva
`public.gv_articulo_empresa (cod_canon, empresa, es_dual)` = fuente única de a qué empresa/góndola
pertenece cada artículo, para dejar de derivarla de los dígitos de la NP (`empresa_de_np`) o de
codificarla en el string (` LK`/` CH`).

Reglas: LK = artículo de Loekemeyer (catálogo `precios_venta ∪ cob_uxb_lk`, incluye los ~96 que
Chef **revende** → góndola Loeke con L, **no** son dual); CH = artículo propio de Chef; **dual** =
mismo código, producto distinto en cada empresa (`437E/438E/439E/809E`, `codigos_duales`) → 2
filas, la NP decide. Sólo lectura, `security_invoker`, se re-deriva sola (catálogos frescos por
cron 66 c/15 min). **No toca Producción** (objeto nuevo `gv_`).

Medido (mirrors reconciliados, ver §3.bk): **282 LK no-dual + 98 propios de Chef + 4 duales (LK y
CH) = 388 filas**. `sql/gv_articulo_empresa.sql`. Rollback: `drop view public.gv_articulo_empresa;`.
Sigue Fase 2 (persistir `empresa` como columna en el pipeline web) — ver `docs/MAPA-CONVERSIONES-PIPELINE.md`.

> ⚠ **Corrección (misma sesión):** la primera versión reportó "0 artículos propios de Chef", falso.
> `precios_venta` arrastraba 115 filas viejas de Chef (del merge previo al split v14.44) que la vista
> contaba como LK. Se arregló con la reconciliación del sync (§3.bk); el número real es 98 propios de Chef.

## §3.bk — v14.47 (2026-09-08): el sync RECONCILIA (los mirrors = catálogo exacto)

`sync-precios-venta` hacía `upsert` **sin borrar**: una fila que salía del catálogo de origen
quedaba para siempre. Tras el split v14.44 eso dejó **115 filas viejas de Chef** en `precios_venta`
(valores del viejo "Chef gana"), que ensuciaban `gv_articulo_empresa` (las tomaba como LK → "0
propios de Chef", mal; p.ej. **613** aparecía LK cuando es de Chef). Las NP no se veían afectadas
(una NP de LK no pide un código que no es de LK), pero la identidad por artículo sí.

Fix: la función ahora **reconcilia** cada mirror — después del upsert, `DELETE … where actualizado
< nowIso` (lo que no se refrescó en esta corrida = ya no está en el catálogo). **Guarda**: sólo
borra si el pull trajo filas (si LK o Chef fallan, no vacía la tabla). Medido: `precios_venta`
337 → **222** (LK exacto), `precios_venta_chef` 101 (sin viejas). `gv_articulo_empresa`: 613 → CH,
98 propios de Chef. Backup previo: `gv_bkp_precios_venta_20260908_pre_reconcile` (337) /
`_chef_..._pre_reconcile` (101). Anotado en `docs/ROLLBACK-PRODUCCION.md`. `supabase/functions/sync-precios-venta/index.ts`.

---

## 3.bl `gv_app` — de qué app salió cada evento de operario — 2026-09-08 (v14.51)

**El problema.** Desde el lunes 07/09 los operarios tienen que usar Gestión. No había forma de
verificarlo: `Registros_Produccion_Virgilio` es la **misma tabla** para las dos apps y no guarda
nada que las distinga — ni URL, ni user_agent, ni versión. `Auditoria_Produccion_Virgilio` sí tiene
`user_agent`, pero sólo se llena en reintentos y errores (**0 filas** el 08/09); `errores_cliente`
sólo cuando algo se rompe.

El martes 08/09 lo único que se pudo probar fue por rebote: el legajo **277** pickeó (11:47) y armó
(13:49) la tanda **E01D**, que existe únicamente en `PPP_Web_Programacion` — **0 filas** en la
`PPP_Programacion_Diaria` de Producción. Ese día hubo **una sola** tanda de Gestión, así que de 104,
237 y 8 no se pudo afirmar nada: trabajaron tandas de ISIS, visibles desde las dos apps.

**La columna.** Gestión manda `gv_app = 'gestion@' + APP_VERSION` en **los dos** caminos de
escritura de `index.html` — `trySendOneReport` (el envío de a uno) y `bulkSendDayReplay` (el replay
del día al Terminar Día). Producción **no la manda y no hay que tocarla**: su payload nombra las
columnas una por una, así que sigue insertando igual y su `gv_app` queda NULL.

```
gv_app IS NULL            → lo mandó Producción Virgilio
gv_app LIKE 'gestion@%'   → lo mandó Gestión, y dice con qué versión
```

La versión va de yapa y responde otra pregunta abierta: si al celular le bajó la build nueva o
quedó con una vieja cacheada en el Service Worker.

**Por qué se puede sobre una tabla compartida.** El protocolo permite agregar una columna nullable,
sin default que reescriba, sin backfill y con prefijo `gv_`. Es exactamente eso: sin trigger
(prohibido acá), sin tocar ninguna fila existente y sin modificar ningún objeto de Producción.
Verificado **antes** de correrlo, no después:

- Producción **no hace `select *`** sobre la tabla — sus referencias en `index.html`,
  `productividad.html`, `recepcion.js` y `sw.js` nombran columnas. El único `SELECT *` del repo
  está **comentado**, en un SQL de rollback del 2026-08-13.
- Los **grants son a nivel tabla** (`anon`/`authenticated` con INSERT sobre la tabla, sin ACL por
  columna) → la columna nueva queda cubierta sola, no hace falta ningún grant.
- La policy de INSERT es `insert_all` con **`with_check = true`** — no enumera columnas, así que no
  rechaza el payload nuevo.

**Cómo se lee (el control diario):**

```sql
select coalesce(gv_app, 'PRODUCCIÓN (sin sello)') as app, legajo, count(*)
  from public."Registros_Produccion_Virgilio"
 where created_at >= current_date and legajo not in ('0','1')
 group by 1, 2 order by 3 desc;
```

**⚠ Ojo al leerlo los primeros días.** Un celular que quedó con la build **vieja de Gestión**
cacheada tampoco manda el sello, así que NULL es "Producción **o** Gestión desactualizada". Se
despeja solo: en cuanto ese celu tome la v14.51 empieza a sellar. Por eso el tag lleva la versión.

**Regresión:** `tests/gv-app-tag.cjs` — cubre los dos caminos de escritura (el bulk es fácil de
olvidar) y que el tag se arme con `APP_VERSION`, no con un literal suelto. Si Gestión dejara de
mandarlo, sus eventos pasarían a contarse como de Producción y el control mentiría en silencio.

**Rollback:** `alter table public."Registros_Produccion_Virgilio" drop column gv_app;` + sacar
`gv_app` de los dos payloads de `index.html`. SQL: `sql/gv_app_sello_eventos_v1451.sql`.

---

## §3.bp — v14.52 (2026-09-08): API ISIS v2.0 (Fase 1) — el endpoint sirve el pedido por REFERENCIA

Reunión 04/09 con ISIS (ticket **TkT115966**): reemplazar el Excel por un **JSON** que ISIS
**baja** (pull). Contrato en `docs/ISIS-API-ESPECIFICACION.md` §6. Hasta hoy el servicio
desplegado era **v1.0** (por NP numérica, con acuse) y no podía servir pedidos web ("LK 0011" →
`np::bigint` = 11). Esta Fase 1 lo lleva a v2.0 **del lado Virgilio**, sin tocar nada compartido.

**Objetos nuevos (todos `gv_`, EXECUTE sólo `service_role`), en `sql/gv_isis_api_v2.sql`:**
- `gv_isis_pedido_json(p_ref)` — el sobre §6 por referencia: `referencia`, `empresa`,
  `estado_integracion`, `terminado_en`, `fecha_entrega`, `pedido{source, cod_cliente,
  razon_social, items[{cod_art, cajas, uxb}], …}`, `control{items, cajas, neto_estimado,
  moneda}`. `cajas` = lo ARMADO (sale de `Entregas_Virgilio`); `neto_estimado` de
  `vista_facturacion_neto`. Los campos comerciales de LK (`vend`, `condicion_pago[_code]`,
  `payment_term`, `sucursal_entrega`) van **NULL** en Fase 1.
- `gv_isis_pedidos_lista(p_estado, p_empresa, p_desde, p_limit)` — cabeceras por estado, **sólo
  referencias web** (`np ILIKE 'LK %'/'CH %'`): los NP numéricos ya están en ISIS y no se le ofrecen
  (evita doble carga).
- `gv_isis_pedido_marcar_entregado(p_ref)` — `pendiente → entregado` al bajarlo.

**Edge Function `isis-api` → v2.0 (deploy v3, `verify_jwt=false`):** rutas `GET /ping`,
`GET /pedidos`, `GET /pedidos/{referencia}` (acepta "LK 0011" url-encoded, lo pasa a entregado).
**Se sacaron las rutas de acuse** (`POST …/acuse`). Llama a las 3 RPCs `gv_`. La v1.0
(`isis_pedido_json`, `isis_api_pendientes`, `isis_api_pedido`, `isis_api_acuse`) **queda intacta**
en la base por si hay que volver.

**Token para la prueba de Horacio:** alta de `isis_api_tokens` id 3 ("ISIS Horacio - prueba
conexion v2.0"). El texto en claro se entregó al dueño por chat (en la base sólo vive el sha256).

**Medido (08/09):** `gv_isis_pedidos_lista('pendiente')` = 1 pedido web (`LK 0011`, CH, 4 items, 40
cajas). `gv_isis_pedido_json('LK 0011')` = sobre §6 completo, `neto_estimado` 751111.20. La lista
NO devuelve los ~19 NP numéricos que hay en la cola. No se pudo hacer el smoke HTTP desde el sandbox
(el proxy de egress bloquea `*.supabase.co` por política) — lo valida Horacio, que es el paso 2 del plan.

**Rollback:** `drop function public.gv_isis_pedido_json(text), public.gv_isis_pedidos_lista(text,text,timestamptz,int), public.gv_isis_pedido_marcar_entregado(text);`
y redeploy de la Edge Function con el `index.ts` v1.0 (está en git, commit anterior). Baja del token:
`update public.isis_api_tokens set activo=false where id=3;`.

**Falta (Fase 2, NO en esta entrega):** (a) el **disparador** pasa del tilde de facturación al
**cierre del armado** (hoy la cola se llena por el trigger sobre `Facturacion_NP`, que además mete
NP numéricas — por eso la lista filtra web); (b) **campos comerciales** de LK (guardarlos al tomar
el pedido); (c) **sufijo L / cod de cliente Chef** para TdF (hoy `canon_cod` devuelve "504", no "504L").
Es el cambio que reemplaza al Excel de verdad; se hace cuando la conexión de Horacio dé OK.

## §3.bq — 2026-09-09: objetos `wa_*` del dashboard LK (GestOpClientes) en este proyecto

**Qué es.** El dashboard **"Pipeline de facturas"** de LK/GestOpClientes (repo
`loekemeyer/GestOpClientes`, bot de WhatsApp) vive en el proyecto LK
(`kwkclwhmoygunqmlegrg`) pero **lee la producción de ESTE proyecto** para 3 de sus
columnas. La fuente de verdad y el SQL están en `GestOpClientes/sql/isis_wa_dashboard.sql`;
esto queda acá sólo para que Gestión sepa qué objetos `wa_*` y qué cron corren en su base.

**Objetos creados acá por GestOpClientes** (todos prefijo `wa_`, **sólo leen** datos de
Gestión — no tocan ningún objeto `gv_*`/`PPP_*`/`Registros_*`):

- **`wa_prog_snapshot(dia date pk, programados int, tomado_at timestamptz)`** — foto diaria del
  contador "programados". RLS **prendida**, sin policies (sólo `service_role`/definer).
- **`wa_snapshot_programados(p_dia date)`** — `SECURITY DEFINER`, `EXECUTE` revocado a
  `public`/`anon`/`authenticated`. Cuenta *distinct NP* programados para el día y congela el
  número (`greatest`: nunca baja). Los DOS universos de NP: ISIS remanentes `9xxxx/4xxxx`
  (`gv_ppp_programacion_diaria`) + web-nativas `LK/CH` (`PPP_Web_Programacion`, clave `empresa,np`).
- **cron `wa-prog-snapshot-diario`** — `30 3 * * *` (03:30 UTC = **00:30 ART**, después del job de
  programación 00:01). Corre `select public.wa_snapshot_programados();`.
- **`wa_dashboard_rango(desde,hasta)`** (ya existía; reapuntado el 09/09) — lee:
  · *programados* = foto `wa_prog_snapshot` (fallback en vivo = mismo conteo);
  · *armados* = evento **`TAL`** (armado de la NP) en `Registros_Produccion_Virgilio` por `ts_cliente`
    (cuenta ISIS y web: el TAL trae la etiqueta completa `98667` / `LK 0011`);
  · *facturados* = `Facturacion_NP` por `facturado_at`.

**Por qué "foto".** La programación viva (`gv_ppp_programacion_diaria`) drena cuando el pedido
avanza (se arma y sale), así que como métrica del día se encogía. El dueño de LK pidió que
"programados" muestre lo que **hubo** programado para el día y no baje → foto al inicio del día.

**Dependencia nueva (2026-09-09): el aviso de facturación de LK LEE `gv_cruce_facturacion_nps`.**
La función `wa_grupos_dia_cuit` (arma el mensaje de WhatsApp consolidado por cliente) pasó a
linkear NP↔factura con **el cruce de Gestión** (`gv_cruce_facturacion_nps`) en vez de la vieja
`vista_np_factura` de LK — porque el cruce asigna 1:1 por cajas aunque el neto discrepe (NP con
neto=0, ej. 98650) y reconcilia el neto web (ej. `LK 0011`). **Sólo lo lee** (no lo modifica). Si
algún día cambia la firma/salida de `gv_cruce_facturacion_nps` (hoy devuelve `np, comprobante_id,
storage_path, factura_total, empresa, estado, cajas…`), avisar: rompería el aviso de LK.

**Impacto en Gestión: ninguno.** Sólo lectura; el cron es un `select` a las 00:30. No modifica
tablas ni vistas de Gestión/Producción. No hay trigger sobre tablas compartidas.

**Rollback (si molestara):**
```sql
select cron.unschedule('wa-prog-snapshot-diario');
drop function if exists public.wa_snapshot_programados(date);
drop table if exists public.wa_prog_snapshot;
-- wa_dashboard_rango es de GestOpClientes; su definición previa está en el git de ese repo.
```

_(Sin bump de APP_VERSION/SW_VERSION: no cambia la app ni el pipeline de Virgilio; son objetos
`wa_*` de otro proyecto que sólo leen esta base. Anotado a pedido del dueño para dejarlo fichado.)_

## §3.bl — Excel ISIS: "2% Descuento Web" (col K) por CÓDIGO de condición de pago (v14.57, 2026-09-09)

**Regla del dueño (2026-09-09, corregida):** en el Excel que Facturación baja para ISIS, la
columna **K** con la leyenda `"2% Descuento Web"` va según el **código de condición de pago
de la col J**: los códigos **8, 9, 10, 11, 12, 13 y 18** (los que en ISIS llevan el 2% web)
→ `"2% Descuento Web"`; **1** (Sin Cotizador) y **2-6 / 14** (FF de Krikos) → **col K vacía**.
Vale para **LK y Chef**.

En la práctica: los pedidos web del cliente **y** los de Cargar Cotizadores usan 8-13/18 →
llevan el 2%; Excel Fmto Cltes y Pedidos sin cot (código 1) y PDF Krikos (2-6/14) no.

**Antes (bug):** `_facXlsFilasPlanas` ponía `pctDto: "2% Descuento Web"` **hardcodeado en
todas las filas** (se agregó el 07/09 con el export, sin condicionar). Los módulos de admin
que facturan por el mismo export arrastraban la leyenda sin corresponder.

**Implementación (solo front, sin backend nuevo):** `_facXlsFilasPlanas` mira `r.cond` (el
código de la col J, que ya viene de `v_pedidos_web_np` para LK y de la RPC de Chef) y pone
`pctDto = ['8','9','10','11','12','13','18'].includes(String(r.cond)) ? "2% Descuento Web" : ""`.

**Nota:** un enfoque previo (mismo día) resolvía esto por `sheets_payload.source` con una RPC
`gv_web_np_source`; al corregirse la regla a "por código" se **descartó y se dropeó** la RPC
(no quedó ningún objeto nuevo en la base). La regla por código no necesita el `source`.

## §3.br — v14.62 (2026-09-10): Legajo **600** = ENTREVISTAS / PRUEBA con nombre

**Qué pidió el dueño.** *"Todos los legajos seiscientos [que] sean legajos de prueba… que cada uno
pueda poner legajo 600, que cuando ponga ese número pueda registrar su nombre y que en función de eso
pueda hacer la prueba. Que descuente stocks y todo. Que todos los de entrevistas usen el 600."*

**Diseño (confirmado con el dueño).** El **600** es un legajo **compartido** de entrevistas. No es como
el `0`/`1` (`es_legajo_test`, que **no** persisten ni descuentan): el 600 hace la prueba **real** →
**persiste eventos y descuenta stock igual que un operario, y entra en los reportes**. Como es compartido,
cada candidato **registra su nombre** al entrar, y **cada evento se sella con ese nombre** para poder
distinguir quién hizo cada prueba.

**Backend (fuente de verdad).**
- Columna nueva `gv_nombre_prueba text` en `Registros_Produccion_Virgilio` (nullable, sin default, sin
  backfill, prefijo `gv_` → mismo patrón seguro y verificado que `gv_app`, §3.bl). Ver `ROLLBACK-PRODUCCION.md`.
- Función `es_legajo_entrevista(text)` → `btrim = '600'` (inmutable, parallel safe, sin `search_path`).
  Es la fuente de verdad de "cuál es el legajo de entrevista". `sql/gv_nombre_prueba_entrevistas_v1462.sql`.
- Vista supervisor `gv_pruebas_entrevistas` (security_invoker): candidatos del 600 por día — nombre,
  cantidad de eventos, ventana y acciones. `sql/gv_pruebas_entrevistas_v1462.sql`.

**Front (`index.html`, espejo de UX).** `esLegajoEntrevista()` + `INTERVIEW_LEGAJO="600"`. `loginWithLegajo`:
si se tipea 600 **no** busca en `Empleados` (no existe a propósito), abre `promptNombreEntrevista()` (modal
propio, no `window.prompt` — poco confiable en el TWA) y arma la sesión con `{legajo:"600", nombre}`.
`_enqueueReportRaw` sella `payload.gv_nombre_prueba` con el nombre de la sesión (leído de `localStorage
vir_legajo_auth`), y los dos caminos de escritura (`trySendOneReport` y `bulkSendDayReplay`) lo mandan sólo
para el 600. `_gvNombrePrueba()` lee `localStorage` directo porque la sesión la escribe el módulo de auth,
cuyo scope no ve el script clásico.

**Medición.** `select * from public.gv_pruebas_entrevistas;` lista los candidatos y sus eventos por día.
Regresión: `tests/entrevista-legajo600.cjs` (clasifica 600 vs operario vs 0/1; verifica que el 600 persiste,
que `_enqueueReportRaw` sella, y que envío individual y bulk mandan el nombre).

## §3.bn — v14.59 (2026-09-09): descontar la OC al recibir mercadería

**Problema.** Al recibir, el módulo escribía en `Entregas Tallerista Virgilio` / `Entregas Prov AT` /
`Movimientos_Stock` / `Control_Modo_OP`, pero **nunca** tocaba `Ordenes_Compra.cantidad_recibida`.
`oc_vigentes_por_proveedor` calcula `pend = cantidad - cantidad_recibida`, así que las cantidades a
recibir no bajaban nunca (medido: **0 de 729 OCs con `cantidad_recibida > 0`, 0 en estado `recibida`**)
y la operadora seguía imprimiendo las OCs.

**Fix.** Función `gv_oc_aplicar_recepcion(nombre_ent text, items jsonb)` (SECURITY DEFINER, grant a
anon/authenticated), que el front (`recepcion.js`) llama best-effort tras cada recepción exitosa.
Descuenta en **cascada** sobre las filas de la fecha más nueva del proveedor+código (igual a como
`oc_vigentes_por_proveedor` agrega lo que ve el operario), llenando cada fila hasta su `cantidad`
(nunca la pasa: si la pasara, la fila se cae de la vista por el filtro `(cantidad-recibida)>0` y el
total queda mal), marcando `estado='recibida'` la que se completa y seteando `fecha_entrega_real`.
El **excedente** (lo recibido por encima de lo pedido) **no** entra a la OC: se avisa aparte al dueño
(botón a Tomás, pendiente del nº de WhatsApp). Match idéntico a `oc_vigentes_por_proveedor`
(`norm_nombre` + alias Pettofrezza→Rafael + split del proveedor; `norm_cod`). SQL: `sql/gv_oc_aplicar_recepcion.sql`.

**Prueba (en transacción con `rollback`, datos intactos).** Garcia/505 tenía a la fecha nueva
(09-09) dos OCs: 287 + 293 = 580 pend. Recibiendo 600 → llenó ambas (→ `recibida`), sobraron 20
(al aviso), y `oc_vigentes_por_proveedor('Garcia')` para 505 pasó a mostrar la OC más vieja
(234, del 02-09) como nueva vigente. Correcto: descuenta lo nuevo y saca la OP completada.

**Backup + rollback:** `public."GV_Backup_Ordenes_Compra_20260909"` (729 filas) y bloque en
`docs/ROLLBACK-PRODUCCION.md` §1 (v14.59).

**Nota de idempotencia.** La RPC es best-effort y no dedupe: si el operario RE-envía a mano el mismo
remito (lo confirma en el aviso de duplicado v14.58), se descuenta dos veces. Igual que el stock, el
control queda en el aviso de duplicado.

## §3.bo — v14.60 (2026-09-09): "la nueva pisa la vieja" (OC vigente = la de fecha más nueva)

**Regla del dueño.** Para un mismo proveedor+código, la OC de fecha MÁS NUEVA es la única viva; las
más viejas quedan muertas y NO reaparecen. Antes (v14.59), al completar la OC nueva al recibir, la
vista caía a mostrar una OC vieja pendiente (caso Garcia/505: quedaba la del 02-09 con 234).

**Cambio (dos funciones, mismo criterio).**
- `oc_vigentes_por_proveedor(text)` — `max_fecha` se calcula sobre las OCs no cerradas/anuladas
  INCLUYENDO las 'recibida' (para que una OC nueva ya recibida tape a las viejas). Se sacó el filtro
  por fila `(cantidad-recibida)>0` y la exclusión de 'recibida' del pre-filtro; el `HAVING sum(pend)>0`
  saca los códigos con la OC nueva completa, y las viejas nunca están en `max_fecha`.
- `gv_oc_aplicar_recepcion(text,jsonb)` — fija `max_fecha` igual (incluyendo 'recibida') y descuenta
  SOLO esa fecha. Si la OC nueva ya no tiene lugar, lo recibido es excedente (aviso a Tomás), nunca
  descuenta una OC vieja.

**Prueba (transacción con `rollback`).** Garcia/505 (dos OCs del 09-09 = 580 pend, más viejas del
02/08 sin usar). Recibiendo 600 → 505 desaparece de `oc_vigentes_por_proveedor('Garcia')` (0 filas):
la vieja de 234 ya NO reaparece. Recibiendo 100 → queda ped=580, rec=100, pend=480. Correcto.

**Efecto lateral (menor).** Una OC en estado 'cerrada' ya no figura como vigente (antes la vista sólo
excluía 'recibida'). Hoy hay 1 'cerrada'.

**Rollback:** `docs/ROLLBACK-PRODUCCION.md` §1 (v14.60). SQL vigente: `sql/oc_nueva_pisa_vieja_v1460.sql`.

## §3.bs — v14.82 (2026-09-10): CUARENTENA — fuente de datos por .xls (idea usuario 8877)

Submódulo **🚧 Cuarentena** en "A Programar" (PPP). Objetivo: retener pedidos de clientes con
**deuda**, **suspendidos** o que **superan su límite de crédito** — no salen a Programación.
Esos datos NO viven en Gestión: se cargan a mano subiendo planillas del ERP desde **4 botones**
del sector Cuarentena.

### Objetos (todos NUEVOS y dedicados — pedido del dueño: "creá una tabla nueva, nada preexistente")

- **`public."GV_Cuarentena_Fuente"`** — una fila por cliente por `(empresa, tipo)`.
  `empresa ∈ {lk,chef}`, `tipo ∈ {busqueda,deuda}`. Columnas: `cod`, `cuit` (dígitos),
  `razon_social`, `limite_credito`, `suspendido`, `deuda`, `raw jsonb`, `lote`, `cargado_por`,
  `cargado_at`. **RLS on, SIN policies**, y `revoke all … from anon, authenticated, public`
  (los default privileges del schema abren INSERT/UPDATE/DELETE a anon; hay que revocarlos).
  → sólo la tocan las funciones SECURITY DEFINER. **No cuelga de `deudores`/ISIS.**
- **`gv_cuarentena_cargar(p_empresa, p_tipo, p_rows jsonb, p_lote default null)`** → integer.
  Gate `es_supervisor_virgilio()`. **Reemplazo TOTAL** de `(empresa, tipo)` (delete + insert).
  Normaliza `cuit` a dígitos, trimea `cod`, descarta filas sin `cod` ni `cuit`. Devuelve cuántas
  quedaron. `revoke anon`, `grant authenticated, service_role`.
- **`gv_cuarentena_fuente_resumen()`** → conteos por `(empresa, tipo)` (filas, con_cuit,
  suspendidos, con_deuda, con_limite, lote, cargado_por, cargado_at) para pintar debajo de cada
  botón. `where es_supervisor_virgilio()` (si no, 0 filas). `revoke anon`.

SQL: `sql/gv_cuarentena.sql`. Migración aplicada: `gv_cuarentena_fuente`.

### Front (index.html, v14.82, sólo lectura del .xls en el navegador)

4 botones en el sector Cuarentena (`aprCuarToolsHtml`): **Importar Búsqueda CL LK/CH** (tipo
`busqueda` → límite + suspendido) e **Importar Deuda LK/CH** (tipo `deuda` → saldo). Cada uno abre
un pop-up (`cuarImport*`, modal colgado de `<body>`, fuera del zoom de la PPP) que lee el .xls con
el SheetJS ya vendorizado (`pppLoadXlsx`), **auto-detecta las columnas por encabezado** y deja
**mapearlas a mano** (no asume layout), muestra preview y al Guardar llama `gv_cuarentena_cargar`.
Debajo de cada botón, `gv_cuarentena_fuente_resumen` muestra qué se cargó.

### Medido / prueba

- End-to-end con `set_config('request.jwt.claims', …)` simulando supervisor: cargó 2 de 3 filas
  (descartó la sin cod ni cuit), `cuit` normalizado (`30-12345678-9` → `30123456789`), `cod`
  trimeado, `suspendido` boolean, `limite_credito` numérico, `lote`/`cargado_por` sellados. Luego
  se borraron las filas de prueba (tabla queda en 0).
- Advisor de seguridad: la tabla sale **sólo** con `rls_enabled_no_policy` (INFO) — es el diseño
  buscado (acceso únicamente por las RPC gateadas). Sin `rls_disabled` ni warnings.
- Smoke: `tests/apr-cuarentena.cjs` (4 botones + etiquetas, resumen, auto-map, parseo AR/estado).

### Rollback

Todo nuevo, nada compartido → NO va a `ROLLBACK-PRODUCCION.md`.
`drop function public.gv_cuarentena_cargar(text,text,jsonb,text); drop function public.gv_cuarentena_fuente_resumen(); drop table public."GV_Cuarentena_Fuente";`

### PENDIENTE (próximo paso)

Esta tabla es la **fuente del filtro**, todavía no marca los pedidos. Falta la lógica que, con
estos datos, decida qué pedido va a cuarentena (`cuarentena_motivos` en el feed de A Programar) y
que el armado automático (crons 71/73) la respete. A definir con el dueño (matcheo por `cod`/`cuit`,
y el límite de crédito contra el monto del pedido).

### Addendum v14.83 (2026-09-10) — layout REAL de "Búsqueda CL" y columna `estado`

El dueño mandó los dos archivos **Búsqueda CL LK/CH** (idénticos en formato, 86 columnas):
`A Código` · `C Razón Social` · `D Estado` (Activo / Suspendido / **Sin Cta.Cte.**) · `H CUIT` ·
`AN Cód.Vendedor` · `AP Cód.Cobrador` · `AV Límite de Crédito`. El auto-detector por encabezado
mapea clavado (cod→A, cuit→H, razón→C, estado→D, límite→AV; probado contra los 86 headers).

- Se agregó la columna **`GV_Cuarentena_Fuente.estado`** (texto crudo del Estado) y el front deriva
  **`suspendido = (Estado ∈ {Suspendido, Sin Cta.Cte.})`** (`cuarEstadoSuspende`). El `raw` guarda
  igual la fila mapeada.
- **Regla de negocio que el dueño fijó** (para el marcado, fase próxima):
  1. Estado **Suspendido** o **Sin Cta.Cte.** → el cliente va a **cuarentena** (todos sus pedidos).
  2. **Límite de crédito**: si el total de los pedidos del cliente **en Programación**, con
     descuentos y **sin IVA**, es **MAYOR** al `limite_credito` → cuarentena. **`limite_credito = 0`
     = infinito** (sin tope).
  3. **Deuda** (reportes Deuda LK/CH, formato aún no recibido): saldo adeudado → cuarentena.
- Prueba backend (supervisor simulado): 3 filas con estados Suspendido / Sin Cta.Cte. / Activo →
  `estado` + `suspendido` + `limite_credito` (0 se guarda como 0) correctos; luego borradas.

### Addendum v14.84 (2026-09-10) — reportes "Deuda" (Crystal agrupado) + reglas de marcado

El dueño mandó los **Deuda LK/CH** (export **Crystal Reports "Ficha Vto."**, `.xls` BIFF real, no
tabla plana): fila 1 encabezados (`L = Pendiente`), y por cliente una **cabecera** (`A` código texto,
`B` razón social, sin comprobante) + filas de **detalle** (`E` = comprobante FCA…, `L` = pendiente) +
una fila **subtotal** (sólo `L`). **Total del cliente = suma de la col L de sus comprobantes** (puede
ser negativo = saldo a favor). El front lo parsea con `cuarParseDeudaCrystal` (SheetJS ya lee `.xls`),
descartando la fila de encabezado (código debe ser dígitos). Medido: LK 183 clientes (45 negativos,
85 multi-doc), CH 41; Ramírez (1104) = 516.747,92 (coincide con la col L del subtotal).

**Reglas de marcado que fijó el dueño (las tres son OR; con una alcanza para ir a cuarentena):**
1. **Estado** Suspendido o Sin Cta.Cte. → todos los pedidos del cliente.
2. **Deuda** total **> $1.000** → todos los pedidos del cliente.
3. **Límite de crédito**: la cuarentena es **por pedido de la página** (todas sus NP van juntas). Se
   lleva el **acumulado** de los pedidos del cliente **no facturados y NO en cuarentena** (con
   descuentos, sin IVA), en orden de llegada. Cuando entra un pedido nuevo, si `acumulado + total > límite`
   → ese pedido (todas sus NP) a cuarentena y **no** suma al acumulado (no consume crédito hasta
   liberarse). `límite = 0` = infinito.

Estado (v14.84): las **4 importaciones** llenan `GV_Cuarentena_Fuente` (búsqueda: cod/estado/suspendido/
límite; deuda: cod/deuda). **Falta el MARCADO** (aplicar estas 3 reglas al feed de A Programar y que el
automático 71/73 lo respete) — próxima fase.

### Addendum v14.85 (2026-09-10) — MARCADO (Estado + Deuda) + pedido de ejemplo

- **`gv_cuarentena_marcar(p_pedidos jsonb)`** (SECURITY DEFINER, sólo supervisor): recibe
  `[{order_id, empresa, cod}]` y devuelve los que van a cuarentena con su(s) `motivos[]`. Reglas de
  esta versión: **Estado** (Suspendido → `suspendido`, Sin Cta.Cte. → `sin_cta_cte`) y **Deuda > $1.000**
  (→ `deuda`). Matchea por **empresa + cod** (sirve LK y Chef). Probado: cod suspendido → `sin_cta_cte`,
  cod con deuda 50.000 → `deuda`, deuda 800 y cod inexistente → no caen.
- **Front**: `cuarMarcarPedidos()` corre después de cargar A Programar (LK+Chef+ISIS), etiqueta cada
  pedido (`cuarentena_motivos`) → `aprEnCuarentena` lo saca de la lista normal y lo pone en 🚧 Cuarentena.
  Se refresca en cada carga (si el cliente se libera, se destilda).
- **Pedido de EJEMPLO** (`cuarDemoPedido` + botón "👁 Ver ejemplo"): inyecta una tarjeta de prueba
  (front-only, tag EJEMPLO) para ver el sector sin datos reales. No toca la base.
- **PENDIENTE — regla de LÍMITE**: falta. Necesita el **monto del pedido valorizado** (con dtos, sin IVA,
  a nivel order antes de romperse en NP) — vive del lado **LK** — y el **acumulado** de los pedidos del
  cliente no facturados y no en cuarentena (A Programar + Programación). Y que el armado automático
  (crons 71/73) respete la cuarentena (hoy el marcado es sólo de pantalla; el cron todavía no lo mira).

### Addendum v14.86 (2026-09-10) — regla de LÍMITE: valorización propia + greedy

Dueño: *"Gestión puede sacar el dato, Facturación ya calcula el monto de los pedidos armados; calculá el
del pedido antes de Programación de la misma forma."* → **no hace falta traer nada de LK**: el pedido
pendiente tiene sus ítems (art × cajas) en el feed, y se valoriza igual que Facturación.

- **`gv_ppp_web_valor_items(p_empresa, p_cod, p_items, p_cond)`** → neto sin IVA, replicando
  `gv_vista_facturacion_neto_items`: `cajas × uxb × precio_lista × (1-dto_vol) × factor_web`. Precios de
  `precios_venta`/`precios_venta_chef`/listas súper (`cobranzas_precios_super`); `dto_vol` de
  `clientes_dto`. **factor_web = 1.0** para súper (lista especial) **y el 2% web (0.98) es CONDICIONAL por
  condición de pago** (dueño 2026-09-10): sólo códigos **8,9,10,11,12,13,18** (contado, 3 crédito, 2 e-cheq,
  "prefiero no decidir"); el resto (1 "Sin Cotizador", etc.) → 1.0. Mismo criterio que el Excel ISIS.
  **Verificado**: dif 0,00 contra `neto_original` de la vista en 3 NP reales (incluye súper).
- **`gv_cuarentena_limite(p_pendientes jsonb)`** → greedy. Entra `[{order_id,empresa,cod,fecha_recep,items,cond}]`
  (los pendientes de A Programar), valoriza cada uno, y por cliente con límite (>0) acumula en orden de
  llegada; el que haría superar el límite va a cuarentena y **no consume crédito** (no suma). límite 0/null = ∞.
  Verificado: 3 pedidos iguales, límite = 1,5× → el 1º entra, 2º y 3º a cuarentena.
- **Front**: se agregó `condicion_pago_code` al feed y `cond` al pedido; `cuarMarcarPedidos` corre en paralelo
  `gv_cuarentena_marcar` (estado+deuda) y `gv_cuarentena_limite` (límite, web) y fusiona los motivos.

**PENDIENTE del límite**: (a) **base = crédito ya comprometido por lo YA programado** (hoy el greedy arranca
en 0; falta sumar el neto de los pedidos programados no facturados del cliente — web + ISIS temporal);
(b) que el **automático (crons 71/73) respete** la cuarentena. Estado/Deuda ya se pueden hacer respetar sin
monto; el límite necesita esta valorización en el cron.

### Addendum v14.87 (2026-09-10) — base del límite + el AUTOMÁTICO respeta la cuarentena

- **Base (crédito ya comprometido)**: `gv_cuarentena_limite` ahora arranca el greedy con el neto de los
  pedidos del cliente **YA ARMADOS y NO facturados** (base), no en 0. Sale de `PPP_Base_Pedidos` (ítems),
  np→cod por `PPP_Web_Programacion` (web) + `PPP_Programacion_Diaria` (ISIS → incluye los dos canales),
  excluyendo lo que está en `Facturacion_NP` (facturado). Se valoriza con `gv_ppp_web_valor_items` (criterio
  Facturación). Verificado: cliente con $14,3M comprometido y límite $10M → el pendiente cae aunque sea chico.
- **Importación NO aditiva** (dueño): cada import **borra y recarga** su fuente. Ya lo hace `gv_cuarentena_cargar`
  (`delete where empresa+tipo` + insert). Re-importar Búsqueda CL LK reemplaza TODO lo de (lk, busqueda).
- **El automático (crons 71/73) respeta la cuarentena**: la Edge Function `gv-ppp-web-tandas-diarias`
  (`soloPendientes`) ahora, después del filtro de excluidos, saca los pedidos en cuarentena
  (`pedidosEnCuarentena` → `gv_cuarentena_marcar` + `gv_cuarentena_limite`) antes de armar. Si las RPC fallan,
  no filtra (no frena el armado). Los pedidos **siguen visibles en A Programar** (sector Cuarentena): sólo no
  se auto-programan. Para que el cron (service_role) pueda llamar las RPC, el gate de `gv_cuarentena_marcar`
  y `gv_cuarentena_limite` pasó a `es_supervisor_virgilio() OR gv_es_supervisor_o_servicio()`.
- **Nota valorización de la base**: al registro armado no le queda guardada la condición de pago, así que la
  base usa el 2% web flat (criterio Facturación); los pendientes sí aplican el 2% condicional por su `cond`.

### §3.bs.2 — v14.88 (2026-09-10): liberar de cuarentena + carga inicial + Config. Cuarentena

- **Liberar un pedido**: `GV_Cuarentena_Liberados` (tabla, RLS on, gate supervisor) +
  `gv_cuarentena_liberar(p_empresa, p_order_id, p_motivos)` (inserta on conflict) +
  `gv_cuarentena_liberados()` (lista). Un pedido liberado **sale del sector** y va a "Pedidos a
  programar" **manteniendo el badge** (se auto-programa si es zona automática, o se agrega a
  tandas a mano). `gv_cuarentena_marcar` y `gv_cuarentena_limite` **excluyen** los liberados
  (LEFT JOIN … IS NULL), así que el cron tampoco los retiene. Front: `aprEnCuarentena` mira
  `p._cuarLiberado`; `cuarMarcarPedidos` trae los liberados en paralelo y los etiqueta para la
  lista normal con `🚧 Liberado de cuarentena` + badges. Deshacer: `delete from public."GV_Cuarentena_Liberados";`
- **Carga inicial** (lote `inicial_20260910`, vía `gv_cuarentena_cargar`): lk/busqueda **1283**
  (202 susp · 817 c/límite), chef/busqueda **763** (211 · 216), lk/deuda **183** (138 > 0),
  chef/deuda **40** (27 > 0). Layout confirmado A/C/D/H/AV (búsqueda) y Crystal agrupado (deuda).
  Chequeo: `select * from public.gv_cuarentena_fuente_resumen();` (como supervisor).
- **Front — pestaña "Config. Cuarentena"** (nueva, a la derecha de Ocupación en la PPP,
  `_pppTab === "cuarcfg"` → `cuarConfigHtml`): los **4 botones** de importación se movieron acá
  (ya no en el sector), cada uno con su **timer "última vez cargada DdHhMmSs"** (rojo + `!!!` a
  los 7 días, `cuarStatHtml`/`cuarTickStart`). El sector 🚧 Cuarentena de A Programar sólo deja
  el botón "Ver ejemplo". **Ficha de pedido rediseñada**: NP grande (LK/CH/ISIS) + zona + m³ +
  razón social, **3 badges separados** (⛔ suspendido / 💰 deuda / 📈 excede crédito, `aprCuarBadgesHtml`)
  y el botón verde **"➡ Enviar a Pedidos a programar"** (`cuarLiberar`).
- Backend aplicado por migración; volcar con `pg_get_functiondef` si se recrea. Smoke:
  `tests/apr-cuarentena.cjs`.

### §3.bs.3 — v14.89/90 (2026-09-10, Luis): botones WhatsApp en la ficha de Cuarentena

- **v14.89 — "💬 A cobranzas"**: abre WhatsApp al número **fijo** de cobranzas (`5491165574113`,
  `CUAR_WPP_COBRANZAS` en `index.html`) con un mensaje ya armado (NP, cliente, motivo, m³). Sin backend.
- **v14.90 — "💬 Vendedor/Cliente" (idea 8833)**: RPC **`gv_cuar_contacto_lote(p_pedidos jsonb)`**
  (SECURITY DEFINER, gate `es_supervisor_virgilio()`, sólo `authenticated`/`service_role`) resuelve por
  `(empresa, cod)` reusando las tablas del módulo **Avisar programación**: `clientes_vendedor` (cod→vend),
  `whatsapp_vendedores` (vend→tel/nombre), `whatsapp_clientes` (cod→tel). Devuelve `tipo`
  (`vendedor`/`cliente`/`ninguno`), `nombre`, `telefono`. Regla: **vendedor** si el cliente tiene vend y no es
  fábrica(`'7'`)/súper(`'20'`) con tel cargado; si no, **cliente**; si no hay tel, `ninguno`. Front:
  `cuarContactoCargar` cachea el lote en `_apr.cuarContacto` (se resetea en `cuarMarcarPedidos`), y
  `cuarWppContacto` abre `wa.me` con el helper `_avpTel`/`_avpWa` (normaliza el tel argentino) del módulo
  Avisar. **Nota**: `clientes_vendedor`/`whatsapp_clientes` están keadas por cod **LK**; un pedido de Chef
  cae en "Sin tel." salvo que su cod exista ahí. Rollback: `drop function public.gv_cuar_contacto_lote(jsonb);`.

### §3.bs.4 — idea 6064 (2026-09-10): la deuda de Cuarentena avisa en los PORTALES (LK/Chef)

El mismo saldo que la Cuarentena sube ~1x/semana a `GV_Cuarentena_Fuente` (tipo `deuda`) ahora le
figura al cliente **en el portal, antes de confirmar el pedido**. Decisión del dueño: **sólo avisar,
no bloquear**; umbral **$1.000**; mostrar **total + fecha de carga**; **LK y Chef**.

- **Feed en Virgilio**: vista **`public.gv_deuda_feed`** (`empresa, cod, deuda, cargado_at`) sobre
  `GV_Cuarentena_Fuente where tipo='deuda' and deuda is not null`. `revoke all` de public/anon/authenticated;
  `grant select` a `lk_ppp_reader` (y a `chef_gv_reader` cuando se corra el setup de Chef). Hoy: 40 filas
  chef ($131,5M), y las de lk.
- **LK (HECHO, en producción)**: foreign table `virgilio.gv_deuda_feed` (server `virgilio_db`, rol
  `lk_ppp_reader`) + RPC **`public.get_mi_deuda()`** en el proyecto LK (SECURITY DEFINER, resuelve el
  cliente por `auth.uid()` vía `user_customer_links`/`customers`, filtra `empresa='lk'`; revocada de anon,
  sólo `authenticated`). Front `pagina-LK-copia`: `cargarDeudaCliente()` la llama 1x por sesión al cargar
  el perfil, cachea en `_deudaCliente`, y `renderDeudaAviso()` pinta el aviso `#deudaAviso` en el carrito
  (no lo muestra a admin/vendedor). Best-effort: si la RPC/FDW falla, no molesta.
- **Chef (HECHO, 2026-09-11)**: front `paginach` espejo del de LK (`get_mi_deuda`, filtra `empresa='chef'`).
  Backend: Chef **ya tenía** FDW a Virgilio (server `virgilio_db`, user mapping para `postgres` que conecta
  como el rol **`ch_ppp_reader`**), así que NO hizo falta rol ni mapping nuevo — sólo `grant select on
  gv_deuda_feed to ch_ppp_reader` en Virgilio + foreign table `virgilio.gv_deuda_feed` y RPC `get_mi_deuda`
  en Chef (`sql/gv_deuda_feed_chef_setup.sql`). Verificado: el FDW trae las 40 filas chef. **Trampa que costó
  el rato**: mi setup creaba un rol nuevo `chef_gv_reader`, pero el user mapping preexistente apuntaba a
  `ch_ppp_reader`; el `create user mapping if not exists` respetó el viejo y el SELECT se denegaba. Se borró
  `chef_gv_reader` y se le dio el grant al rol que Chef ya usa.

### §3.bs.5 — v14.94 (2026-09-11): los SÚPER no se analizan por deuda + Pérez Zárate fuera de PPP

**Regla del dueño (11/09):** *"Coto es súper. Los súper no se analiza si tiene o no tiene deuda."*

- **`gv_cuarentena_marcar`** (backend, así el cron 71/73 también la respeta): la regla de **deuda** se
  saltea cuando `(empresa, cod)` figura en **`cobranzas_cliente_cadena`** (la tabla de cadenas de súper:
  12 lk + 2 ch; la misma que usa `gv_vista_cruce_facturacion.es_super`). **Trampa:** ahí Chef está como
  `'ch'` y en `GV_Cuarentena_Fuente` como `'chef'` → el join normaliza. Estado (suspendido / sin cta.
  cte.) y límite **no cambian**. Verificado con payload directo: Coto (lk 801, $132k) y Cencosud (chef
  2444, $17,8M) **no caen**; Villar (4103) sí. Definición en `sql/gv_cuarentena.sql` (bloque v14.94);
  rollback en `sql/backups/cuarentena_20260911_np56_perez_zarate_y_marcar_pre_super.sql`.
- **Pérez Zárate S.R.L. (lk 4036, pedido 1380, NP 56) sacado de Programación** por pedido del dueño: se
  había programado el 09/09 18:00 (tanda E12D, entrega 17/09), **antes** de que existiera el dato de
  deuda (10/09 17:27), así que la regla no lo pudo frenar. Mecanismo = el del resync: se borró **sólo** la
  fila de `PPP_Web_Programacion`, con guarda "tanda sin arrancar" (E12D: 0 eventos EP/TP/AP/TAP/CC; las
  otras 5 NP de la tanda —46, 47, 54, 60, 61— quedan). La NP 56 y sus 14 ítems (`PPP_Web_Base`,
  `LK 0056`) se dejan para reprogramar. Ahora figura **retenido en Cuarentena** (deuda $291.923) junto
  con Villar. Los otros dos que se colaron antes de la carga: **Coto (NP 49, E16A)** ya no aplica (súper) y
  **El Gran Bazar (NP 43, E12A, deuda $2.519)** quedó como estaba hasta que el dueño lo mandó a Cuarentena
  (§3.bs.6, v15.01).
- **Auditoría del mismo día:** las 4 importaciones siguen siendo la carga inicial del 10/09 (lote
  `inicial_20260910`, `cargado_por` n8n) — Luis todavía no importó nada. Liberados: 0.

### §3.bs.6 — v15.01 (2026-09-11): El Gran Bazar (NP 43) fuera de PPP → Cuarentena

**Dueño (11/09):** *"El gran bazar, pasalo a cuarentena."* Mismo mecanismo que Pérez Zárate (§3.bs.5):

- **El Gran Bazar S.R.L (lk 2375, pedido 1369, NP 43)** se había programado el 08/09 16:30 en **E12A**
  (entrega 18/09, Soldati / Exp. Tradelog), **antes** de que existiera el dato de deuda (10/09 17:27).
  Deuda en `GV_Cuarentena_Fuente`: **$2.519,21**. Liberados: 0.
- Se borró **sólo** la fila de `PPP_Web_Programacion`, con guarda "tanda sin arrancar" en la misma
  sentencia (E12A: 0 eventos EP/TP/AP/TAP/CC). La tanda queda con **7 NP**. La NP 43 (`PPP_Web_NP`) y
  sus 7 ítems (`PPP_Web_Base`, `LK 0043`: 031x3, 034x2, 395x1, 544x4, 585Ex2, 587x2, 591x1) se dejan
  para reprogramar. `PPP_Web_Tanda_Items`: 0 filas.
- **Verificado después:** `PPP_Web_Programacion` sin 1369 · `gv_cuarentena_marcar` (como supervisor)
  devuelve `motivos = {deuda}` para 1369 → figura **retenido en Cuarentena** junto con Villar y Pérez
  Zárate · `gv_ppp_super_mezclado` vacía.
- **Rollback** (fila exacta): `sql/backups/cuarentena_20260911_np43_el_gran_bazar.sql`.

### §3.bs.7 — v15.02-15.04 (2026-09-11): ficha de Cuarentena angosta y con el monto del motivo

**Dueño (11/09):** *"la visual es espantosa"* → *"VERSIÓN ANGOSTA"* → *"que diga ahí el motivo de la
cuarentena: ej deuda $10000, límite de crédito superado x $100000, suspendido x pago"*.

**Front (`index.html`)**
- **v15.02:** la ficha pasó a dos zonas (datos a la izquierda en `.cuar-info`, acciones a la derecha).
  Los 3 botones dejaron de ser franjas verdes a ancho completo: ahora son compactos, con UNA sola
  acción sólida (Enviar a programar) y las dos de WhatsApp de contorno. El m³ va pegado a la NP.
- **v15.03:** **las fichas van ANGOSTAS**. `.apr-col-cuar .apr-scroll` es una grilla de tarjetas de
  ~340px (`repeat(auto-fill, minmax(min(100%,300px), 340px))`): entran varias por fila y ninguna se
  estira. Estirada quedaba con los datos a la izquierda, un mar de blanco en el medio y los botones
  contra el borde derecho. El `min(100%, 300px)` evita que desborde dentro de una columna angosta.
- **v15.04:** los badges muestran el monto: `💰 Deuda $291.923`, `📈 Excede crédito x $100.000`,
  `⛔ Suspendido` (el texto del estado tal cual lo trae el reporte). El detalle viaja en
  `p.cuarentena_detalle` y el tooltip largo repite los números. Si el monto no viene, el badge cae al
  texto pelado de antes.

**Backend (la lógica de negocio manda acá, el front sólo muestra)** — `sql/gv_cuarentena.sql`:
- `gv_cuarentena_marcar` → ahora devuelve `(order_id, empresa, motivos[], **deuda**, **estado**)`.
- `gv_cuarentena_limite` → ahora devuelve `(order_id, empresa, **exceso**, **limite**)`; el exceso sale
  del mismo greedy que ya decidía la retención (`usado + monto - limite`).
- **Quién cae en cuarentena NO cambió**: misma exención de súper de la v14.94, mismo greedy. Sólo se
  expone el número que ya se calculaba. Medido: El Gran Bazar (lk 2375) $2.519,21 · Pérez Zárate
  (4036) $291.923,09 · Villar (4103) $229.343,40 · Coto (801) sigue sin caer.
- ⚠ **Cambian el tipo de retorno → van con DROP + CREATE.** Y ahí está la trampa: al recrearlas
  Supabase le devuelve `EXECUTE` a **`anon`** (event trigger del proyecto). Las dos son
  `SECURITY DEFINER`, así que hay que **revocárselo a mano**; si no, quedan ejecutables con la anon key
  pública. Estado correcto y verificado después del cambio: `postgres`, `authenticated`, `service_role`.
- La Edge Function `gv-ppp-web-tandas-diarias` sólo lee `r.order_id` de las dos, así que las columnas
  nuevas no la tocan.
- **Rollback:** `sql/backups/cuarentena_20260911_marcar_limite_pre_v1504.sql`.

**De paso, verificado (11/09):** el armado automático **sí** respeta Cuarentena, aunque ninguna función
`gv_ppp_web_*` la mencione — el filtro vive en la Edge Function (`pedidosEnCuarentena` dentro de
`soloPendientes`, v14.86), que saca los retenidos antes de programar. O sea que una NP sacada de
Programación por deuda no vuelve sola en la corrida siguiente.

## §3.bl — Baches de pedidos de importación (v14.94, 2026-09-11)

**Qué:** el módulo "Pedidos Importación" ahora maneja **varios pedidos en curso por artículo, cada
uno con su propia fecha de reingreso** (antes había 1 sola: la segunda pisaba la primera).

**Fuente de verdad:** tabla nueva `GV_Importados_Baches` (RLS on, sin policies anon; acceso sólo por
RPCs `SECURITY DEFINER`). `Importados.pedido_curso` y `reingreso_est` quedan como **mirror derivado**
que recalcula `gv_importados_resync(importado_id)`:
- `pedido_curso` (por fila) = suma pendiente de baches en curso de esa fila.
- `reingreso_est` (por cod `gv_cod_stock`) = fecha pendiente **más cercana** (o NULL) → uniforme por
  cod, así `lk_reingresos_feed()` (usa `max(reingreso_est)`) manda la más cercana a la página LK.

**RPCs:** `gv_importado_bache_add / _llego (total o parcial) / _editar / _borrar (anula)` y
`gv_importado_baches(importado_id)` (listar). La llegada escribe en `Importados_Mov_Stock` (ingreso),
igual que la vieja `importados_marcar_llegada`.

**Front (index.html v14.94):** botón **📦 Baches** por fila (reemplaza ✏️/📥); "Cargar pedido ya hecho"
inserta un bache por artículo (ya no pisa curso/fecha). Las viejas `pedImpSetCurso`/`pedImpLlego` y las
RPCs `importados_set_curso`/`importados_marcar_llegada` quedaron **sin uso** (no borradas).

**Backfill:** el "en curso" existente (69 filas, 360.952 u, 19 con fecha) pasó a 1 bache por fila.
**Backup:** `GV_Importados_curso_bkp_20260911`. **SQL:** `sql/gv_importados_baches_v1494.sql`.
**Prueba:** 934E con 2 baches (200@20/09 + 5760@29/09) → mirror curso 5960, reingreso 20/09 (la más
cercana); anular el de prueba restauró 5760 / 29/09.

## §3.bm — 437EL / 438EL (LK) separados de 437E / 438E (CH) en Pedidos Importación (v15.01, 2026-09-11)

**Dueño:** *"se piden por separado, LK y CH. 438EL es para LK (para la impo, después se vende como
438E y descuenta el de LK) y 438E para CH. No en conjunto."*

**Qué había:** `Importados` tenía dos filas por código (marca LK y CH). La vista `v_importados_ordenes`
ya calculaba proyección y stock por fila, pero el front agrupa por `cod_art` y los sumaba en una sola
línea; el reingreso (por `cod_art`) quedaba compartido.

**Qué se hizo:**
1. `Importados`: fila LK de 437E/438E → `cod_art = 437EL / 438EL` (ids 69 y 65). CH queda `437E/438E`.
   `Importados_Volumen` copiado para los `…EL`. Baches re-etiquetados.
2. `v_importados_ordenes`: normaliza con **`gv_cod_stock()`** (pela la L) en movimientos, entregas y
   proyección → `438EL` hereda la proy LK y el stock góndola LK de `438E`. La proyección toma **sólo
   códigos base** de `proyeccion_madre` (una fila `574EL = 0` pisaba el seed de 574E con `max()`).
3. `lk_reingresos_feed()`: sólo filas **no CH** (antes mezclaba y tomaba la fecha mayor).

**Impacto medido:** proyección cambia sólo en 437EL (null→2388 live) y 438EL (null→2788 live); el
resto idéntico (query de diff vieja-vs-nueva normalización: 0 filas más). Stock: las entregas cargadas
como `…EL` ahora descuentan LK — **438EL 4512→4128 (16 cajas × 24)** y **439E 420→234 (31 cajas × 6)**;
ningún otro código tiene entregas con L. `Importados_Mov_Stock` no tiene códigos con L. Feed LK: 23 filas.

**Backups:** `GV_Importados_bkp_437_438_20260911`, `GV_Importados_Volumen_bkp_437_438_20260911`.
**SQL + rollback:** `sql/gv_importados_lk_ch_separados_v1501.sql`.

**Pendiente (reportado, no tocado):** filas **duplicadas con la misma marca** en `Importados`:
360E/361E/366E (LK·Kangli ×2), 585E/811E/812E/813E/816E/817E/819E (LK·Ownland ×2), 809E ×3 —
suman doble el en curso y el backfill de baches les creó 2–3 baches.

### §3.bm.1 — Limpieza `Importados`: 809E corta queso → CH; 11 copias exactas borradas (v15.05, 2026-09-11)

- **809E**: id 129 "CORTA QUESO x 12" estaba como LK con `principal=false` (invisible) y **4.032 u en curso**.
  Dueño: *"809E es corta pizza para Loeke (la próxima impo viene con código nuevo, 820E) y 809E es corta
  queso para Chef"* → id 129 pasa a **marca CH, principal=true**. **820E todavía no se da de alta.**
  Backup `GV_Importados_bkp_809E_20260911`. Ojo: 809E·LK queda con stock **−2.004** (entregas > ingresos), sin
  resolver.
- **Copias exactas** (`principal=false` con una fila principal idéntica en cod/marca/prov/desc/FOB/seed):
  360E, 361E, 366E, 585E, 809E#128, 811E, 812E, 813E, 816E, 817E, 819E — **11 filas borradas** + 2 baches
  huérfanos (361E, 366E). No se veían (el módulo carga sólo `principal=true`), así que **cero efecto en
  pantalla**. Backups `GV_Importados_bkp_copias_20260911` y `GV_Importados_Baches_bkp_copias_20260911`.
  Rollback: `insert into "Importados" select <cols> from "GV_Importados_bkp_copias_20260911";` (idem baches).

### §3.bm.2 — PI Fujian HT26-06-600-R1 cargado como pedido en curso; 439EL·LK / 439E·CH separados (v15.06, 2026-09-11)

- **Qué**: la proforma `PI_26066002` de Fujian (106.488 u, u$s 32.388, entrega "30-45 días después del
  depósito", Ningbo) queda cargada como baches `en_curso` en `GV_Importados_Baches` con
  `fecha_reingreso = 2026-11-01` (la misma que ya tenían las 5 líneas que Becky cargó el 10/09 desde
  "Cargar pedido ya hecho": 026·LK 49.536, 027·LK 27.792, 110·Loke 3.312, 824·CH 7.200, 825·CH 7.344).
  Se agregaron las 6 que faltaban, `creado_por = 'PI HT26-06-600-R1'`: 438E·CH 1.224, 438EL·LK 6.912,
  439E·CH 48, 439EL·LK 720, 440E·LK 1.200, 035E·LK 1.200. 436/437 vienen en 0 en el PI: nada.
  **Chequeo**: `select sum(unidades) from "GV_Importados_Baches" where proveedor='Fujian' and estado='en_curso'`
  → **106.488 = total del PI**.
- **439E**: el PI trae 439E (48) y 439EL (720). Misma regla del dueño que 437/438 (§3.bm): **EL = LK, E = CH**.
  La fila 439E·LK (id 68) pasa a **`439EL`** (+ `Importados_Volumen` 439EL copiado de 439E) y se da de alta
  **439E·CH** (id 164, FOB 2,30, 6 u/caja, "Colador de Pastas ac. inox."). `gv_cod_stock` pela la L, así que
  439EL hereda proy/stock LK de 439E (proy live 122, stock 234). Backups `GV_Importados_bkp_439_20260911`,
  `GV_Importados_Volumen_bkp_439_20260911`. No hay mapa de partes para 439E (`Importados_Partes_Map` es
  parte→terminado; no aplica).
- **Efecto en la página LK**: `lk_reingresos_feed()` ya devuelve 01/11 para 26, 27, 110, 35E, 438E, 439E y
  440E; hoy todos con `sin_stock=false` (el stock físico cubre lo pedido), así que la leyenda "Reingreso Est"
  no se ve hasta que alguno se quede sin stock. El cron 39 de LK lo espeja cada 30 min.
- **FOB corregido según el PI (v15.07, dueño: *"corregí FOB considerando lo de ese Excel"*)**: se cruzó
  `fob_uni` de las 13 filas Fujian contra el PI; la única diferencia era **825·CH 0,50 → 0,25** (id 76, backup
  `GV_Importados_bkp_fob825_20260911`). El resto ya coincidía. 111/112/113 (Loke) no vienen en el PI: sin tocar.
- **uni × master corregido según el PI (v15.09, dueño: *"corregí uni x master"*)**: `Importados_Volumen` de las
  13 filas Fujian pasa al **cartón real del embarque** (inner, master, medidas y m³ del "out carton" del PI; el CBM
  total del PI, 32,52 m³, cierra con esos cartones). Se alinea todo el packing y no sólo el número porque el m³ va
  atado al master. Cambios de master: 026/110/824/027/825 **96 → 144**, 440E **12 → 24**; el resto (437, 438, 439,
  035E) mantiene el master pero cambia medidas/m³ (438: 0,0685 → 0,0464; 439: 0,0561 → 0,0715; 035E: 0,0645 →
  0,0770; 437: 0,0518 → 0,0616). `fuente = 'PI HT26-06-600-R1'` (antes "QUIEBRE Todos 11-08"). `uni_x_caja` de
  `Importados` (caja de venta) no se toca. Backup `GV_Importados_Volumen_bkp_pi_fujian_20260911`; rollback =
  `update "Importados_Volumen" v set (uni_inner,uni_master,largo_cm,ancho_cm,alto_cm,m3_master,fuente) =
  (b.uni_inner,b.uni_master,b.largo_cm,b.ancho_cm,b.alto_cm,b.m3_master,b.fuente) from
  "GV_Importados_Volumen_bkp_pi_fujian_20260911" b where b.cod = v.cod`.
- **Rollback**: `delete from "GV_Importados_Baches" where creado_por = 'PI HT26-06-600-R1'` (6 filas) +
  `select gv_importados_resync(id)` para 63, 65, 66, 67, 68, 164; `delete from "Importados" where id = 164`;
  `update "Importados" set cod_art='439E' where id=68`; `delete from "Importados_Volumen" where cod='439EL'`.
  SQL: `sql/gv_importados_pi_fujian_v1506.sql`.

### §3.bm.3 — Barrido de datos de Pedidos Importación: ventas por empresa + stock sincronizado con el depósito (v15.11, 2026-09-11)

Dueño: *"todos los datos que tengas que corregir, dale"*. Barrido sobre `v_importados_ordenes` (153 filas
`principal` + `activo`): **28 con stock negativo**, 91 distintas al depósito, ~36 sin uni×caja, ~25 sin m³/master,
6 sin FOB.

- **Causa raíz del stock**: `Importados_Mov_Stock` sólo tenía el seed `inicial` del 16/07 (Excel QUIEBRE, 149 filas)
  y **ninguna llegada** desde entonces (los baches de v14.94 recién existen desde el 10/09), así que el módulo restaba
  dos meses de entregas a un stock de julio. Encima la vista restaba **todas** las `Entregas_Virgilio` a la fila LK
  (`plant = 'Loeke'` fijo) y a la fila CH sólo "Entregas Tallerista Cervantes", que es producción y aporta **0** a los
  códigos CH importados. Caso testigo 809E·LK = −2.004: le restaban 191 cajas de corta queso de Chef + 70 de LK.
- **Vista** (`create or replace view v_importados_ordenes`, sin `security_invoker`, como estaba): el CTE `arm` toma
  `Entregas_Virgilio` con `plant` por **`gv_empresa`** (`chef` → Chef, resto → Loeke; desde el 16/07: 7.608 filas lk /
  1.047 chef, 0 nulas) y se saca la unión con Cervantes. El resto de la vista es idéntico a v15.01.
- **Sincronización con el depósito**: por cada fila (menos las 5 **partes** —`Importados_Partes_Map`— y las que no
  tienen uni×caja) se insertó UN movimiento en `Importados_Mov_Stock` con `ref = 'sync stock depósito 2026-09-11
  (vista_saldos_stock)'`: `tipo='ajuste'` si la fila ya tenía seed, `tipo='inicial'` (ts = ahora) si no (439E·CH,
  599E…), así las entregas futuras le restan. Objetivo = `vista_saldos_stock` por `empresa` (LK / CH) en cajas ×
  `uni_x_caja`; el bucket **`Mixto`** va a la fila única del código, o a la LK si hay LK y CH (en los 4 compartidos
  —437E/438E/439E/809E— Mixto es 0). **98 movimientos, delta neto +122.177 u; 0 filas negativas** (antes 28).
  Verificación: las 8 filas compartidas quedan iguales al depósito (809E·LK 336 = 28 cajas; 809E·CH 5.868 = 489).
  Lo que sigue "distinto" son las partes (stock en `vista_importados_stock_parte`) y 36 filas sin uni×caja, todas con
  0 en módulo y 0 en depósito: no hay nada que ajustar. Backup `GV_Importados_Mov_Stock_bkp_20260911` (tabla entera).
- **uni×caja**: 3 filas difería del maestro (`vista_uni_x_caja`, fuente `maestro`), que es lo que usa el depósito para
  convertir cajas: **838E·CH 12 → 24, 877E·CH 12 → 24, 590ES 12 → 50**. Backup `GV_Importados_bkp_uxc_20260911`. Las
  36 sin uni×caja tampoco están en el maestro (artículos nuevos de Becky 6xxE/9xxE, Kangli 36xE, Ownland…): no hay
  de dónde sacarlo. Idem **FOB** (603E/604E/605E/608E/930E/939E) y **m³/master** de ~25 filas: son datos del
  proveedor / comerciales, no se inventan.
- **Rollback**: `delete from "Importados_Mov_Stock" where ref like 'sync stock depósito 2026-09-11%'` (98 filas; o
  restaurar desde el backup); vista anterior en `sql/gv_importados_lk_ch_separados_v1501.sql`; uni×caja desde
  `GV_Importados_bkp_uxc_20260911`. SQL: `sql/gv_importados_stock_sync_v1511.sql`.

### §3.bm.4 — Fechas de las impos en curso: Becky 2.ª 15/11; Kangli ya llegó (v15.12, 2026-09-11)

- Dueño: *"la segunda de Becky llega 15/11"* → los 26 baches de Becky sin fecha (backfill de v14.94: 198E, 602E, 798E,
  941E–999E) pasan a `fecha_reingreso = 2026-11-15`. La primera (19 líneas, 29/09) no cambia.
- Dueño: *"Kangli no tiene pedido en curso, ¿no es el que llegó hace poco?"* → sí: `Movimientos_Stock` tiene la
  **Recepción Remitos del 31/08** con las cajas exactas de cada bache (328E 168 cajas = 2.016 u, 361E 300 = 3.600,
  363E 168, 366E 100, 367E 336, 368E 244, 810E 204, 870E 702). Los 8 baches pasan a `estado = 'llegado'` con
  `unidades_llegadas = unidades` **sin insertar en `Importados_Mov_Stock`**: el stock del módulo ya quedó
  sincronizado con el depósito en la v15.11 y ese depósito ya incluye la llegada; usar `gv_importado_bache_llego`
  la habría contado dos veces. `gv_importados_resync` sobre los 34 importados → Kangli con 0 filas en curso.
- Backup `GV_Importados_Baches_bkp_fechas_20260911` (34 filas). Rollback: `update "GV_Importados_Baches" b set
  fecha_reingreso = k.fecha_reingreso, estado = k.estado, unidades_llegadas = k.unidades_llegadas from
  "GV_Importados_Baches_bkp_fechas_20260911" k where k.id = b.id` + resync.
- Quedan **sin fecha**: Hugo Wong (7 líneas, 132.336 u), Ownland (7, 81.072 u). Con fecha: Becky 29/09 y 15/11,
  Fujian 01/11, Frontier 04/11.

### §3.bm.5 — PI Ownland OL-10139 cargado; el embarque de julio cerrado como llegado (v15.13, 2026-09-11)

- **PI OL-10139** (02/09/2026, FOB Shenzhen, 1×20', 98.376 u, u$s 13.988, *lead time 60 días desde el depósito*):
  13 baches `en_curso` con `creado_por = 'PI OL-10139'` y **sin fecha** (el PI no trae la fecha del depósito; cuando
  el dueño la dé se carga). Líneas: 729E·CH 2.160, 525E 12.096, 585E 6.840, 809E·LK 1.632 (corta pizza, "original
  809ENS"; irá como 820E cuando el dueño lo dé de alta), 119E·Loke 1.872, 809E·CH 7.200, 819E 2.448, 702E·CH 6.192,
  817E 1.440, 816E 6.144, 725E·CH 1.728, 877E·CH 1.536, **1000903 47.088 → cargado sobre 1546903** (id 153: es la
  misma parte "cheese cutter without handle", mismo packing 48/144 y 28,5×14,5×29,5; el PI la renombra).
  Chequeo: `sum(unidades - unidades_llegadas)` de Ownland `en_curso` = **98.376**.
- **Los 7 baches de Ownland del backfill** (1546903 42.768, 503E 2.448, 525E 3.168, 574E 17.136, 702E 6.624, 725E
  4.896, 809E·CH 4.032) eran el **embarque que entró el 22–23/07** (`Movimientos_Stock` tipo `ingreso`: 503E 204
  cajas = 2.448 u, 525E 132 = 3.168, 574E 1.428 = 17.136, 702E 552 = 6.624, 725E 204 = 4.896, 809E 336 = 4.032).
  Pasan a `llegado` **sin movimiento de stock** (el módulo ya está sincronizado con el depósito, v15.11).
- **119E** (Corta queso Loke x12, Ownland, FOB 0,47, 12 u/caja) dado de alta: `Importados` id 165 + `Importados_Volumen`
  (12/144, 44×26×28, 0,032032) + un `inicial` de 0 en `Importados_Mov_Stock` para que las entregas futuras resten.
- **Datos corregidos según el PI**: FOB 809E·CH **0,70 → 0,47** (id 129); packing 729E (72/ctn, 42,5×27×36,
  0,04131) y 877E (96/ctn, 51,5×31×37, 0,05907). **No tocado**: `Importados_Volumen` de 809E es UNA fila compartida
  por 809E·LK (corta pizza, en el PI 96/ctn 54×33,5×32) y 809E·CH (corta queso, 144/ctn 44×26×28): queda la de CH,
  que es la línea grande; el corta pizza tendrá su packing cuando exista 820E.
- Backups `GV_Importados_Baches_bkp_ownland_20260911`, `GV_Importados_bkp_ownland_20260911`,
  `GV_Importados_Volumen_bkp_ownland_20260911`. Rollback: `delete from "GV_Importados_Baches" where creado_por =
  'PI OL-10139'`; restaurar estado/unidades_llegadas de los 7 viejos desde el backup; `delete from "Importados" where
  id = 165` (+ su volumen y su `inicial`); FOB y volumen desde los backups; `gv_importados_resync` de cada importado.
- **Impos en curso ahora**: Becky 29/09 y 15/11, Fujian 01/11, Frontier 04/11, Ownland sin fecha, Hugo Wong sin fecha.

### §3.bm.6 — Fecha del PI Ownland: depósito 9/9 + lead time del PI + 40 días de viaje (v15.14, 2026-09-11)

- Dueño: *"buscá el delay estipulado por el PI, y desde el 9/9 agregá el delay más 40 días de viaje a Argentina"*.
  PI OL-10139: *"The lead time: 60 days when deposit received"* → **9/9 + 60 + 40 = 18/12/2026** en los 13 baches
  (`creado_por = 'PI OL-10139'`) + `gv_importados_resync` → 13 filas de `Importados` con `reingreso_est = 2026-12-18`.
- Regla útil para los próximos PI: **fecha = depósito + lead time del PI + 40 días de viaje**. (Fujian decía "30-45
  días después del depósito"; sus baches tienen 01/11 cargado por Becky, no se recalculó.)
- Rollback: `update "GV_Importados_Baches" set fecha_reingreso = null where creado_por = 'PI OL-10139'` + resync.

### §3.bm.7 — PI Hugo Wong NY26-031438 cargado; el embarque de julio cerrado como llegado (v15.15, 2026-09-11)

- El dueño subió el PDF como "el de Ownland", pero es de **Hugo Wong** (Yangjiang Nanyuan, Ref NY26-031438, 01/08/2026,
  FOB Shenzhen, 88.832 u, u$s 38.640, depósito 30 % = u$s 11.592, **producción 55 días**). Ownland ya estaba cargado
  (§3.bm.5). 11 baches `en_curso`, `creado_por = 'PI NY26-031438'`, **sin fecha**: regla del dueño *"plazo del PI +
  40"* → `fecha = depósito + 55 + 40`; avisa cuándo pagó el 30 %. Líneas: 838E·CH 1.008, 323E 4.464, 102E·Loke 24.048,
  522E 6.000, 529E 14.400, 727E·CH 2.448, 540E 1.296, 539E 1.296, 536E 1.872, 1000900 20.000 (parte), 523C 12.000
  (parte). Chequeo: `sum(unidades - unidades_llegadas)` Hugo Wong `en_curso` = **88.832**.
- **Los 7 baches del backfill** (1000900 80.000, 102E 9.360, 323E 2.000, 522E 4.040, 523C 14.400, 529E 20.736,
  599ES 1.800) eran el **embarque del 23/07** (`Movimientos_Stock` ingreso 23/07: 102E 780 cajas = 9.360 u exacto,
  523C 240 cajas = 14.400, 522E 170, 529E 1.620; 323E recepciones 24–28/07; 1000900 y 599ES sin registro por ser
  parte / suelto). Pasan a `llegado` sin movimiento de stock (módulo sincronizado con el depósito en v15.11).
- **Datos corregidos según el PI**: FOB 522E **1,40 → 1,29** (id 81), 727E **0,59 → 0,465** (id 123); `Importados_Volumen`
  727E `uni_master 192 → 144` e inner 12 (el PI no trae medidas de cartón: el m³ 0,0398 queda **sin verificar**,
  `fuente` lo dice); 539E/540E `uni_inner` null → 12. El resto (FOB, master) ya coincidía.
- Backups `GV_Importados_Baches_bkp_hugowong_20260911`, `GV_Importados_bkp_hugowong_20260911`,
  `GV_Importados_Volumen_bkp_hugowong_20260911`. Rollback: `delete from "GV_Importados_Baches" where creado_por =
  'PI NY26-031438'`; estado/unidades_llegadas de los 7 viejos desde el backup; FOB y volumen desde los backups;
  `gv_importados_resync` por importado.
- **Impos en curso**: Becky 29/09 y 15/11 · Fujian 01/11 · Frontier 04/11 · Ownland 18/12 · Hugo Wong sin fecha
  (falta la fecha del depósito).

### §3.bm.8 — Fecha del PI Hugo Wong: 19/09 + 45 días (v15.16, 2026-09-11)

- Dueño: *"19 de septiembre + 45 d llega Hugo"* → **03/11/2026** en los 11 baches `creado_por = 'PI NY26-031438'`
  (+ `gv_importados_resync`: 11 filas de `Importados` con `reingreso_est = 2026-11-03`). Es el dato del dueño, no la
  fórmula depósito + 55 + 40 de §3.bm.7.
- Rollback: `update "GV_Importados_Baches" set fecha_reingreso = null where creado_por = 'PI NY26-031438'` + resync.
- **Impos en curso, todas con fecha**: Becky 29/09 · Fujian 01/11 · Hugo Wong 03/11 · Frontier 04/11 · Becky 2.ª 15/11 ·
  Ownland 18/12.

### §3.bm.9 — PI Zhixin BX260722D cargado; FOB y packing al PI (v15.17, 2026-09-11)

- **PI BX260722D** (Ningbo Zhixin, 04/09/2026, FOB Lianyungang, u$s 10.272,95, 18,5 CBM, *"delivery 30 days around
  after payment"*). Dueño: *"40 d + 45 d desde 5/9"* → **29/11/2026**. 5 baches `creado_por = 'PI BX260722D'`:
  566E 3.600, 590E 9.000, 584E 3.600, 583E 8.010, 582E 18.048 = **42.258 u** (chequeo: `sum(unidades -
  unidades_llegadas)` = 42.258). 5 filas de `Importados` con `reingreso_est = 2026-11-29`. Zhixin no tenía ningún bache
  (ni del backfill): es la primera impo cargada del proveedor.
- **FOB según PI** (los 5 cambiaron): 566E 0,33 → **0,462**; 582E 0,1519 → **0,161**; 583E 0,258 → **0,282**; 584E
  0,638 → **0,752**; 590E 0,0446 → **0,082**. 590ES (suelto, 0,446) y 890E (Chef, 0,045) no vienen en el PI: sin tocar.
- **Packing según PI** (`Importados_Volumen`, `fuente = 'PI BX260722D'`): 566E 48/ctn 51×36×21,5 (0,0395); 582E 192/ctn
  37×27×44 (0,0440); 583E **120 → 90**/ctn 33×27×38 (0,0339); 584E 48/ctn 58×40×44,5 (0,1032); 590E 600/ctn
  38,5×31,5×21 (0,0255). Cierra con el CBM del PI (3 + 4,2 + 3,1 + 7,8 + 0,4 = 18,5).
- Backups `GV_Importados_bkp_zhixin_20260911`, `GV_Importados_Volumen_bkp_zhixin_20260911`. Rollback: `delete from
  "GV_Importados_Baches" where creado_por = 'PI BX260722D'` + resync; FOB y volumen desde los backups.
- **Impos en curso, todas con fecha**: Becky 29/09 · Fujian 01/11 · Hugo Wong 03/11 · Frontier 04/11 · Becky 2.ª 15/11 ·
  Zhixin 29/11 · Ownland 18/12. Kangli: sin pedido (llegó el 31/08).

### §3.bm.10 — Fechas del módulo de importación en dd/mm/aa (v15.18, 2026-09-11, sólo front)

- Dueño: *"en el módulo para cargar pedidos poné formato dd/mm/yy, no mm/dd/yyyy"*. Los tres `<input type="date">`
  del módulo (Fecha de entrega en "Cargar pedido ya hecho", Fecha estimada de entrega global y Reingreso por fila)
  los pintaba el navegador según su idioma (en-US → mm/dd/yyyy). Pasan a **texto dd/mm/aa** con un helper común
  (`_pedImpFechaInputHtml` / `_pedImpFechaTxt` / `_isoToDdMmAa`): se valida con `_pedImpParseFechaISO` (acepta
  dd/mm/aa, dd/mm/aaaa, dd/mm y yyyy-mm-dd), se normaliza lo que se ve y se manda el ISO al mismo setter de antes
  (`pedHechoSetFecha`, `pedImpSetEntregaGlobal`, `pedImpSetReingreso`). Fecha inválida → aviso y vuelve al valor
  anterior. El gestor de baches muestra y pide dd/mm/aa. Sin cambios en la base: se sigue guardando `YYYY-MM-DD`.

### §3.bm.11 — Baja de 580E y 123E en Importados; 601E y 360E revisados (v15.19, 2026-09-11)

- Dueño: *"580E no se compra más"* → id 125 `activo = false`. *"123E está mal codificado, es 589E el que se le compra
  a Ownland"* → id 147 (123E·Loke, proy seed 480) `activo = false`; 589E (id 138, proy live 860, 9.768 u) queda como
  la fila válida. Nota en `notas` con el motivo. Backup `GV_Importados_bkp_baja_580E_123E_20260911`; rollback
  `update "Importados" set activo = true where id in (125,147)`.
- **601E** (Becky): 348 u = 29 cajas en depósito, 3 NP pendientes, **172 cajas facturadas desde julio** (~86/mes ≈
  1.030 u/mes, más que la proyección de 576) y **no está en ninguno de los dos PI de Becky** (29/09 ni 15/11).
  Reportado, sin acción.
- **360E** (Kangli): **no vino en la llegada del 31/08** — `Movimientos_Stock` no tiene ningún `ingreso` de 360E desde
  junio (sólo el seed inicial de 42 cajas, 45 facturadas y ajustes chicos); depósito 0, 1 NP pendiente. Los 8 códigos
  que sí entraron el 31/08 son 328E/361E/363E/366E/367E/368E/810E/870E.

### §3.bm.12 — Becky: el 2.º pedido (CI B260601) separado del 1.º (v15.20, 2026-09-11)

- El dueño subió el Excel del *"2nd order"* de Becky: **CI B260601** (Yangjiang Jiaheng, 12/08/2026, Shenzhen, 19 líneas,
  **41.944 u**, u$s 23.622). Son exactamente los 19 códigos del bache "Becky 1.ª" (29/09) y el backfill de v14.94 tenía
  **el doble** de cada cantidad (931E 5.184 = 2 × 2.592 … 957E 9.504 = 2 × 4.752; 404E 2.752 = 1.824 + 928): el
  `pedido_curso` viejo sumaba los dos pedidos.
- **Partición** (total sin cambios, 84.784 u): cada bache del backfill se editó a `backfill − CI` con fecha **29/09**
  (1.º pedido, 42.840 u) y se agregó un bache nuevo con la cantidad del CI, fecha **15/11**, `creado_por = 'CI
  B260601'` (2.º pedido, 41.944 u). Hecho con `gv_importado_bache_editar` + `gv_importado_bache_add` + resync.
- **FOB según el CI** (backup `GV_Importados_bkp_becky_fob_20260911`): 931E–936E 0,53 → 0,52; 951E–956E 0,49 → 0,48;
  957E 0,31 → 0,30; 958E 0,42 → 0,40; 606E 0,56 → 0,55; 404E 5,20 → 5,10. 937E/938E/607E ya coincidían.
- **Pendiente del dueño**: las otras **26 líneas** con fecha 15/11 (198E, 602E, 798E, 941E–999E, 36.912 u, del backfill)
  NO están en este CI. Se les puso 15/11 por su *"la segunda de Becky llega 15/11"* de esta misma noche, pero el 2.º
  pedido resultó ser el CI de arriba; falta saber si son un 3.º pedido (y su fecha) o si sobran.
- Backup `GV_Importados_Baches_bkp_becky_20260911` (todos los baches de Becky antes de partir). Rollback: `delete from
  "GV_Importados_Baches" where creado_por = 'CI B260601'`; restaurar `unidades` de los 19 baches del backfill desde el
  backup por `id`; FOB desde el backup; resync.

### §3.bm.13 — Becky: los dos pedidos quedan como sus PI (B260601 y B260601-2); se deshace la partición de v15.20 (v15.21, 2026-09-11)

- El dueño subió los dos PI de Becky (Yangjiang Jiaheng): **PI B260601** (04/07/2026, 19 líneas, **41.944 u**, u$s 23.622,
  depósito 6.920,86, "35-40 días después del depósito") y **PI B260601-2** (14/07/2026, 26 líneas, **48.056 u**,
  u$s 31.614, depósito 7.358,90, "90 días después del depósito"). El CI B260601 del 12/08 (v15.20) es el **mismo**
  pedido que el PI B260601, no un segundo pedido: el backfill de v14.94 tenía esas 19 líneas **duplicadas** (84.784 u) por
  un error de carga de julio, no por dos pedidos. La partición de v15.20 se deshace.
- **1.º pedido (29/09, `creado_por = 'PI B260601'`)**: los 19 baches del backfill quedan con las cantidades del PI (sólo
  cambió 404E: 1.824 → 928); los 19 baches `'CI B260601'` de v15.20 se **anularon** (`gv_importado_bache_borrar`).
- **2.º pedido (15/11, `creado_por = 'PI B260601-2'`; fecha del dueño, el PI daría ~21/11)**: los 26 baches del backfill
  se ajustaron al PI (198E 1.800 → 4.320, 798E 1.200 → 6.336, 948E 1.440 → 2.304, 960E 1.872 → 2.736, 970E 1.008 → 1.872,
  993E 576 → 1.152); se **anularon** 945E, 994E y 999E (no están en el PI); se agregaron **404E 896, 601E 3.600** (el que
  preocupaba al dueño: sí está pedido) y **989E 576** (alta: Rallador cítricos acacia, FOB 0,56, 12/144, id nuevo con un
  `inicial` de 0 en `Importados_Mov_Stock`).
- **FOB según PI-2**: 941E/942E/943E/946E/948E 0,66 → 0,65; 944E 0,66 → 0,63; 982E 0,98 → 0,90; 981E 1,30 → 1,25; 601E
  0,735 → 0,66. `uni_x_caja` = 12 (inner del PI) en 602E, 990E, 992E, 993E, 996E, 997E, 998E que estaban en null.
- Chequeo: `sum(unidades - unidades_llegadas)` por `creado_por` = 41.944 y 48.056, iguales a los PI.
- Backups `GV_Importados_Baches_bkp_becky2_20260911`, `GV_Importados_bkp_becky2_20260911`. Rollback: restaurar
  `unidades / fecha_reingreso / estado / creado_por` de los baches de Becky desde el backup por `id`, borrar los baches
  nuevos (404E 896, 601E 3.600, 989E 576) y la fila 989E de `Importados` (+ volumen + `inicial`), FOB y `uni_x_caja` desde el
  backup, `gv_importados_resync` por importado.
- **Impos en curso**: Becky 29/09 (41.944) y 15/11 (48.056) · Fujian 01/11 · Hugo Wong 03/11 · Frontier 04/11 · Zhixin
  29/11 · Ownland 18/12.

### §3.bm.14 — 587C: parte de 587, stock en Cervantes (GP2), lo pasa Alan (v15.22, 2026-09-11)

- Dueño: *"587C es una parte que se usa para 587. Guardá que falta que te pase el stock. Pedíselo a Alan. Eso se guarda
  en Cervantes (para GP2)"*. `Importados_Partes_Map` ya tiene 587C → 587. El stock de la parte **no está en Virgilio**
  (el módulo lo muestra en 0): vive en Cervantes / GP2. Tarea en el Planify de **Alan Gonzalez (employee_id 5)** para que
  lo pase; nota en `Importados.notas` de 587C (id 163). Cuando llegue el dato, cargarlo como `inicial` en
  `Importados_Mov_Stock` (marca LK) o vía `vista_importados_stock_parte` según cómo se resuelva el stock de partes.
- Idea a evaluar: leer el stock de las partes de Cervantes directo desde GP2 (mismo proyecto Supabase) en vez de cargarlo
  a mano. Sin implementar.

### §3.bm.15 — Pedidos Importación: proyección POR EMPRESA (LK ≠ Chef) (v15.23, 2026-09-11)

- **Problema** (dueño: *"la proyección no va a ser igual en Loeke y Chef, tenés errores ahí"*): la fila LK usaba
  `proyeccion_madre`, que en LK suma ventas **LK + Chef** (`_fn_proy_window`), y la fila CH un seed a mano. Casos:
  437EL·LK 99,5 caj/mes cuando LK vende ~20 (la diferencia era Chef, sobre todo una factura del 20/03 al cliente Chef
  1434: 453 cajas de 437E y 366 de 438E); 438EL·LK 116 vs ~38 reales; 809E·LK 113 (corta pizza, LK real ~15) porque
  el corta queso de Chef pesa ahí; 438E·CH seed 150 caj/mes contra 4–50 reales.
- **LK** (`kwkclwhmoygunqmlegrg`): `_fn_proy_window_emp(p_meses, p_emp)` (misma regla: promedio 6 meses, meses sin
  venta = 0, piso 4.º mejor mes; fallback 12 meses) filtrando `sales_lines.empresa`; `fn_proyeccion_importados_emp()`
  devuelve (cod, empresa, proy_cajas_mes) para lk y chef; `sync_proyeccion_emp_virgilio()` empuja por el FDW
  `virgilio_db` (foreign table `virgilio."GV_Proyeccion_Emp"`) con reemplazo total y abort si el motor devuelve 0;
  cron **`sync-proyeccion-emp-virgilio`** miércoles 09:25 UTC (5 min después del de `proyeccion_madre`). Primera corrida:
  **614 filas**. `fn_ventas_mensuales_virgilio` pasó a 3 argumentos (`p_empresa` opcional, null = LK+Chef como antes;
  se dropeó la firma de 2 para que PostgREST no tenga ambigüedad). Las funciones nuevas revocadas a anon/authenticated.
  **`proyeccion_madre` NO cambia**: sigue siendo LK+Chef para las OC de producción (regla del 2/9, "una sola
  estadística madre"); esto es otra proyección, sólo para importados.
- **Virgilio**: tabla **`GV_Proyeccion_Emp`** (cod, empresa, proy_cajas_mes, actualizado; PK cod+empresa; RLS con
  lectura anon/authenticated y `gv_proy_emp_writer` para `lk_ppp_reader`, calcada de `proyeccion_madre`).
  `v_importados_ordenes`: `est_madre_live` = proy de la empresa de la fila (LK/Loke → `lk`, CH → `chef`) **en cajas ×
  `uni_x_caja` de la fila**; `est_madre_eff = coalesce(override, live, seed, 0)`; ya no lee `proyeccion_madre`.
  `ventas_mensuales_cod(p_cod, p_meses, p_empresa)` (una sola firma) pasa la empresa al feed de LK; el popup
  📈 Proyección del front manda `chef`/`lk` según el sufijo de la fila (sin sufijo = LK+Chef).
- **Resultado** (proy caj/mes antes → ahora): 437EL 99,5 → **20,2** (a pedir 16.800 → 0); 438EL 116 → **38,5** (17.920
  → 0); 437E·CH 7 → 79,3; 438E·CH 150 → 77,7; 809E·CH 140 → 70; 824·CH 160 → 66; 825·CH 194 → 29.
- **Lo que sigue torcido es dato, no motor**: en LK las ventas de Chef terminan el 30/06 y julio/agosto se cargaron
  como LK (anomalía grupo A, documentada en el CLAUDE.md de LK). Mientras no se re-marquen: la fila LK de los códigos
  compartidos queda alta (809E·LK 57,7 caj/mes) y la CH baja (809E·CH 70 con dos meses en 0). Se corrige sola en el
  siguiente sync cuando LK arregle `sales_lines.empresa`. La factura Chef 1434 del 20/03 sigue inflando 437E/438E·CH.
- Pendiente aparte: `vista_stock_procesada` (pantalla Stock) sigue con `proyeccion_madre` y para las filas con sufijo
  (`809E CH`, `809E LK`) da 0; podría usar `GV_Proyeccion_Emp`. No se tocó.
- Rollback: vista anterior en `sql/gv_importados_stock_sync_v1511.sql` (§3.bm.3); recrear `ventas_mensuales_cod` de
  2 args (idéntica sin `p_empresa`); en LK `cron.unschedule('sync-proyeccion-emp-virgilio')`, drop de las 3 funciones +
  foreign table, y recrear `fn_ventas_mensuales_virgilio(text,integer)`; `drop table "GV_Proyeccion_Emp"`.
  SQL: `sql/gv_proyeccion_emp_v1523.sql`.

### §3.bm.16 — Proyección: variantes L se SUMAN, familias nacional→importado y pantalla Stock por empresa (v15.24, 2026-09-11)

- Dueño: *"por las dudas 580/580E, 574E/574; revisá si hay más"*. Revisión de los ~150 códigos de Importados contra
  `sales_lines` de LK (6 meses), `sales_item_remap` de LK y `Equivalencias_Familia` de Virgilio:
  1. **Variantes `…L` / `…EL`** (artículo LK vendido por la página de Chef): `GV_Proyeccion_Emp` las trae como ítems
     separados (102EL, 106EL, 439EL, 960EL, 404EL…). El CTE `pe` de `v_importados_ordenes` tomaba `max()` al colapsarlas
     con `gv_cod_stock` → perdía la variante. Ahora **suma**: 106E 5,7 → **32,8** caj/mes, 102E 151,5 → 183,3, 404E 49 → 52,5,
     437EL 20,2 → 33,2, 960E 41 → 54,7.
  2. **Familias nacional → importado** (`Equivalencias_Familia`, las mismas que usa el generador de OC): la proyección
     del secundario suma al principal por empresa. 574 → 574E (LK además remapea 574E → 574 en `sales_item_remap`, así
     que 574E caía a seed): 574E seed 54 → **live 88,7**. 565 → 607E: 31 → 75,2. 323 → 323E: 25 → 34,5. 33x → 94xE:
     941E 7 → 12,5, 943E 12 → 19, 945E 7 → 12,8, 948E 9 → 11,3. 548 → 590E: 99 → 100,7. 580E → **580** (principal el
     nacional): coherente con la baja de 580E de §3.bm.11 (580 vende ~58 caj/mes, 580E 4).
  3. **`vista_stock_procesada`** (materializada, cron 55 cada 2 min, `Stock_Saldos` depende de ella): el CTE `proy`
     ahora une `proyeccion_madre` (filas sin sufijo, LK+Chef) con `GV_Proyeccion_Emp` para las filas con sufijo
     (`"809E CH"`, `"809E LK"`, `"437E LK"`…), que antes daban 0 (y el popup mostraba 1,3). Se recreó con
     `drop … cascade` + misma definición + índice único `cod` + `grant all` a anon/authenticated/service_role (relacl
     idéntico al anterior, guardado en `GV_bkp_relacl_vista_stock_procesada_20260911` junto con las dos definiciones)
     + `Stock_Saldos` recreada igual. Muestra: 437E LK 20,17 · 438E LK 38,50 · 809E CH 70 · 809E LK 57,67.
- **Sin familia, a decisión del dueño** (no se tocó): **512 → 512E** (512 nacional vende 136 caj/mes; 512E Ownland sin
  ventas ni familia: si 512E reemplaza al 512, falta la fila en `Equivalencias_Familia`); **816/817** (Chef vende
  "816"/"817" sin E: 23 y 55 caj/mes; ¿son los mismos que 816E/817E de Ownland?); **56x** (560–569 son artículos
  distintos, no familia de 056E).
- Rollback: vista `v_importados_ordenes` de §3.bm.15 (CTE `pe` con `max` y sin `fam`); `vista_stock_procesada` y
  `Stock_Saldos` desde `GV_bkp_relacl_vista_stock_procesada_20260911.def` (drop cascade + create + índice + grants).

### §3.bm.17 — Override de proyección en 437E·CH y 438E·CH (v15.25, 2026-09-11)

- La proyección "live" de Chef para 437E/438E (79 y 78 caj/mes) sigue inflada por la factura del 20/03 al cliente Chef
  1434 (453 y 366 cajas); sin ese mes Chef vende ~5–7 y ~20–30 caj/mes, y las entregas del depósito (Chef, jun–sep:
  437E 3/1/10, 438E 23/18/23) lo confirman. Con eso el módulo pedía 18.656 y 17.368 u.
- `Importados.est_madre_override`: **437E·CH (id 71) = 144 u/mes (6 caj)**, **438E·CH (id 63) = 528 u/mes (22 caj)**,
  con la nota del motivo. Resultado: a pedir 1.056 y 4.008 u. Backup `GV_Importados_bkp_override_437_438CH_20260911`.
- Es un parche hasta que LK re-marque Chef julio/agosto; cuando la proyección por empresa quede limpia, sacar el
  override (`update "Importados" set est_madre_override = null where id in (71,63)`) y vuelve a "live".

### §3.bm.18 — Partes: el stock de los terminados cuenta como stock de la parte (v15.26, 2026-09-11)

- Dueño: *"no se está considerando el stock del artículo terminado… en los insumos hay que considerar el stock de las
  partes"*. El módulo pedía 1546903 (parte corta queso) por 29.952 u / u$s 12.580 mirando sólo la parte (stock 0), cuando
  el 546 tiene **1.627 cajas** terminadas en Virgilio (terminado 349 + a facturar 13 + a guardar 655 + racks 587 + …).
- `vista_importados_partes` (`sql/gv_importados_partes_stock_terminados_v1526.sql`): nueva columna **`stock_term_uni`** =
  Σ por terminado de (todos los estadios de `vista_saldos_stock`, todas las empresas, menos `insumos`) × `uni_x_caja`
  de `vista_uni_x_caja`; el `detalle` suma `stock_cajas`/`uxc`/`stock_uni` por terminado. Supuesto: **1 parte por
  unidad** (el mapa no tiene cantidad). Mismas columnas viejas → el front anterior sigue andando. `create or replace`
  **perdió `security_invoker`**: se volvió a poner con `alter view`.
- Mapa: **505C → 114** agregado (dueño: "cuchillas del 505 → 586, 713, 186, 123, 114"). Backup
  `GV_Importados_Partes_Map_bkp_20260911`. Los demás ya estaban (espirales 1000900 → 520/521/530/531/581/730/731/735
  + 104/067; 523C → 523/723; 587C → 587).
- Front (`ocgFetchImportados`, index.html): `stockTot = stock propio + stock de parte (94xP) + stock de terminados`;
  badge 🧩+N en la columna Stock con el detalle por terminado.
- Medido: 1546903 stock terminados **19.524 u** → a pedir 10.512 u (u$s 4.415, antes 12.580); 505C 61.122 u;
  1000900 25.560; 523C 3.420 (Hugo Wong 523C 4.320 → 720 u); 587C 5.400 (Frontier 24.000 → 20.000 u).
  Ownland total u$s 25.125 → **13.735**; lo que queda grande ahí son seeds sin ventas ni stock (733E·CH 792 u/mes,
  692E·CH 240, 814E 36: sin fila en `GV_Proyeccion_Emp` ni en `vista_saldos_stock` → u$s 6.036 de pedido fantasma).
- Rollback: en el `.sql`.

### §3.bm.19 — El depósito INSUMOS cuenta como stock del módulo de importados (v15.27, 2026-09-11)

- Dueño: *"ojo con lo que está en insumos de importados; revisá uno por uno"*. Hasta acá el módulo **nunca** miraba el
  depósito `insumos`: el sync v15.11 lo excluyó y las partes quedaron con el **seed del Excel QUIEBRE del 16/07**
  (505C 262.400, 1000900 68.000, 523C/1546903 0). Además `vista_saldos_stock.insumos` **suma crudo** unidades
  distintas (MC + Uni): 505C decía 141.997 y son 142.000 Uni − 3 MC×4.000 = **130.000**; 590E decía 2.396 y es **0**
  (2.400 Uni − 4 MC×600, ya fueron a Cervantes).
- Reglas cerradas con el dueño (una por una): **1000900** = insumos `H201Part` "Espiral TN" (104.000 u) + `007`
  "Espiral (Chef)" (3.500) — *"ambos son espirales, todo el stock cuenta para repedir a Hugo Wong"*; **546P** bastidor
  = parte 1546903; **522ES** suelto = 522E sin caja; `H201Lever` y `CB01` = partes **sin uso todavía** (fuera);
  `Mgo Pelador 505` / `Ergonómico` = **inyectadas nacionales** (fuera); `337P` arma el **337** (no está en
  `Importados`: falta proveedor/FOB → decisión del dueño); **733E / 692E / 814E** se empezaron a vender ahora →
  se piden con el seed, no se tocan.
- Objetos (`sql/gv_importados_stock_insumos_v1527.sql`): tabla **`GV_Importados_Insumo_Map`** (insumo → importado,
  sólo los renombrados; los códigos iguales se enlazan solos), vista **`gv_importados_stock_insumos`** (saldo por
  unidad de `vista_saldos_insumos_x_unidad` × `Insumos_Factores`; sin factor cae a `Importados_Volumen.uni_master`;
  `sin_factor` avisa), y **`v_importados_ordenes`** con `stock_insumos`, `es_parte` y **`stock_total`** (parte con
  insumo → el insumo REEMPLAZA al seed; resto → `stock_actual + stock_insumos`). El insumo va a la fila **CH** si el
  código tiene una (Paquete A: en Chef el 437E/439E arranca como insumo) y si no a la LK. `stock_actual` no cambia
  (la pantalla de stock sigue igual). Def anterior en `GV_bkp_def_v_importados_ordenes_20260911`.
- Front: `ocgFetchImportados` usa `stock_total` (cae a `stock_actual` si no viene) y muestra 🧰N en Stock.
- Medido: 505C 130.000 · 1000900 107.500 · 1546903 16.848 · 523C 6.000 · 437E·CH 2.976 · 439E·CH 480 · 522E 4.604 ·
  584E 1.314 · 035E 1.128. Pedido: 1546903 10.512 → **0**, 523C 720 → **0**, 437E·CH 1.080 → **0**, 439E·CH 456 → 72,
  035E 1.056 → 528, 584E 1.584 → 384. Total ≈ u$s 53.500 → **≈ 46.300** (Ownland 13.735 → 9.320, Hugo Wong 7.190 →
  6.778, Fujian 9.437 → 7.673, Zhixin 6.844 → 5.942, Frontier 1.000 → 1.280 por 1 MC de 505C).
- Rollback: en el `.sql`.

### §3.bm.20 — 323ES suelto: 3.000 u llegan el 22/09 (v15.28, 2026-09-11)

- Dueño: *"el 22/9 ingresa 323ES (suelto, después se envasan) 3.000 uni"*. No existe fila 323ES en `Importados`: se cargó
  como bache **en curso del 323E (id 79, Hugo Wong)** con `gv_importado_bache_add(79, 3000, '2026-09-22', …)`; el 323E
  queda con 7.464 u en curso (3.000 el 22/09 + 4.464 el 03/11 de la PI NY26-031438). Además `GV_Importados_Insumo_Map`
  **323ES → 323E**: cuando se reciba como insumo suelto, cuenta como stock del 323E (mismo patrón que 522ES).
- Rollback: `delete from "GV_Importados_Baches" where importado_id = 79 and creado_por like 'dueño 11/09: 323ES%'; select
  gv_importados_resync(79); delete from "GV_Importados_Insumo_Map" where insumo_cod = '323ES';`

### §3.bm.21 — 323ES es el pool de 323E (LK) y 838E (CH); alias en la base (v15.29, 2026-09-11)

- Dueño: *"323ES sirve para 323E y 838E"*. El rallador 4 lados mini se compra **suelto** (323ES, Hugo Wong) y se envasa
  acá como 323E (LK, ×12) o 838E (CH, ×24). Deshace el mapa 323ES → 323E de §3.bm.20.
- `Importados`: alta **323ES (id 167)**, LK, Hugo Wong, FOB 0,225, sin uni×caja; `Importados_Volumen` 323ES copiado
  de 323E (144/master). El bache de 3.000 u del 22/09 se **movió** del 323E (id 79) al 323ES (backup
  `GV_Importados_Baches_bkp_323ES_20260911`, resync de los dos). El insumo 323ES ahora enlaza por código igual.
- Tabla nueva **`GV_Importados_Alias`** (`cod → canon`): 865ED → 865E (antes hardcodeado en `IMP_ALIAS`), **323E → 323ES**,
  **838E → 323ES**. `ocgFetchImportados` la carga y suma bajo el canónico proyección, stock y en curso; la fila
  canónica manda la descripción. Resultado: un ítem 323ES con 1.106 u/mes (414 + 692), stock 0, en curso 8.472
  (3.000 el 22/09 + 4.464 y 1.008 el 03/11) → a pedir 2.588 u. Las filas 323E/838E siguen existiendo para stock.
- Rollback: `delete from "GV_Importados_Alias" where canon = '323ES'; update "GV_Importados_Baches" set importado_id = 79
  where importado_id = 167; select gv_importados_resync(79), gv_importados_resync(167); delete from "Importados" where
  id = 167; delete from "Importados_Volumen" where cod = '323ES';` (y volver a cargar el mapa 323ES → 323E si se quiere).

### §3.bm.22 — Reporte de faltantes de importados para contingencia; 727E → 106E (v15.30, 2026-09-11)

- Dueño: *"727E se puede rellenar con 106E. Preparamos un reporte de todos los faltantes para ver si alguno lo puedo
  fabricar acá hasta que lleguen los importados"*. Reporte publicado como artefacto
  (https://claude.ai/code/artifact/95e62327-bc21-4e96-9206-8a1f434ac60e) y copia en
  `docs/INFORME-FALTANTES-IMPORTADOS-20260911.html`. Criterio: artículo con pedido en curso cuyo stock (módulo +
  insumos + terminados) no llega a la fecha de llegada, más los sin pedido en curso; faltante = consumo × meses hasta la
  llegada − stock. 48 artículos, 25 ya en cero, ≈ 26.400 u faltantes hasta la llegada; los más pesados 026 (5.231 u),
  583E (4.637), 590E (2.527), 525E (2.287), 582E (1.776), 566E (1.562).
- **727E·CH → 106E** como sustituto de contingencia (106E tiene 14.280 u = 36 meses): anotado en `Importados.notas` de la fila
  727E·CH. Sin lógica nueva en el módulo: es una decisión comercial puntual, no una familia.
- Las marcas "fabricable acá" del reporte viven en el navegador del que lo mira (localStorage), no en la base.

### §3.bm.23 — Reporte de faltantes: quién compra cada uno + fabricables acá (v15.31, 2026-09-11)

- Dueño: *"colador 16 y colador 20 se pueden fabricar nacionalmente, sacacorcho de madera 525E también; agregá quiénes
  compran los importados esos para racionar a los que compran mucha cantidad y estirar el stock"*.
- Reporte (mismo artefacto, versión 2; copia en `docs/INFORME-FALTANTES-IMPORTADOS-20260911.html`): columna **"Quién lo
  compra (6 meses)"** = cajas facturadas en `sales_lines` de LK (LK + Chef, `invoice_date` ≥ 6 meses, `boxes > 0`,
  variantes L incluidas), clientes distintos, % del top 3 (≥ 50 % en naranja = candidato a racionar) y los 3 mayores
  con caj/mes. Tile nuevo con la cuenta de concentrados. Trampas anotadas: 1434 Loekemeyer Hnos [CH] es la factura
  intercompañía; 2686 Dorinka sale doble por julio/agosto cargados como LK; 2444 es Cencosud en Chef y Relca en LK.
- **Fabricables acá** en `Importados.notas` (437E·CH, 438E·CH, 113, 525E: "Fabricable nacional (dueño 11/09)") y
  marcados en el reporte. Sin lógica nueva en el módulo.
- Concentraciones que más pesan: 582E salero Coto 63 % · 198E La Anónima 100 % · 601E La Anónima 47 % · 960E Relca 41 % ·
  026 La Anónima + Coto 44 % · 970E/971E Cencosud + Relca ~70 % · 727E Dorinka 52 %.

### §3.bm.24 — Reporte de faltantes: entregas de septiembre en "quién lo compra" (v15.32, 2026-09-11)

- Dueño: *"solo consideraste sales_lines; desde el 1 de septiembre hay entregas que no están"*. Cierto: `sales_lines` de LK
  llega al 31/08 (Chef al 30/06). Se sumó un segundo bloque por artículo con las **entregas de Gestión del 01 al
  10/09** (`Entregas_Virgilio`: `cod_cliente`, `cod_art`, `cajas_entregadas`, `gv_empresa`; razón social por
  `gv_ppp_programacion_diaria` / `gv_ppp_entregados_meta`), y el pill **"nuevo"** cuando el cliente de septiembre no
  estaba entre los 3 mayores de lo facturado. Caso que lo justifica: **198E** — facturado mar–ago era 100 % La Anónima,
  pero en 10 días de septiembre Osa se llevó 138 cajas (66 %). Otros: 583E Sauer 80 caj (51 %), 582E Coto 70 caj (88 %),
  601E La Anónima 40 caj (83 %), 584E Osa 20 caj.
- Mismo artefacto (versión 3) y copia en `docs/INFORME-FALTANTES-IMPORTADOS-20260911.html`. Sin cambios en la base.

### §3.bn — Recepción: dar de alta un artículo nuevo avisa a Thomas por WhatsApp (v15.36, 2026-09-11)

> ⚠ **Leer también §3.bn.1 (v15.39): el bloqueo que describe esta sección se SACÓ el mismo día.** Lo que
> sigue vigente es la tabla, la Edge Function, el WhatsApp y el asiento; lo que ya NO es cierto es que
> "no puedan cerrar la recepción".

Pedido del dueño: *"si en la recepción están por recibir un artículo nuevo que no figuraba en la
planimetría, me mandan un mensaje directo a WhatsApp, a mi teléfono, para que antes de dejarlos
cargar me tengan que decir 'hola Thomy, estoy creando un artículo nuevo, que es el tanto, ¿me
confirmás que está bien?', y que no puedan terminar de cerrar la recepción sin que yo dé ese ok"*.

**Por qué.** Remito **38087** (02/09, Log/Fabr, legajo 277): el operario cargó **599, 943 y 948** con
el botón **"+"** de la pantalla de recepción. Esos códigos no existen — los reales son 599E (J44),
943E (I08) y 948E (I11). El "+" (`arAddCode`) abría un `prompt` y daba de alta **cualquier cosa**:
no validaba contra nada, no pedía autorización y no avisaba a nadie. No hubo operadora en el medio;
en ese flujo no existe ningún paso de aprobación.

**Qué se agregó (todo NUEVO, no toca nada compartido):**

- **Tabla `GV_Alta_Articulo_Aprobacion`** (`token` único, `cod`, `remito`, `legajo`, `tallerista`,
  `linea`, `estado` ∈ pendiente/ok/rechazado, `wa_ok`, `wa_error`, `pedido_at`, `resuelto_at`,
  `resuelto_por`). RLS **ON** con **una sola policy: `gvaa_sel` (SELECT para anon/authenticated)**.
  Sin policy de insert/update ⇒ con la anon key **sólo se puede leer**: desde el celular no se puede
  auto-aprobar. Índice único parcial `(cod) where estado='pendiente'` → un solo pedido abierto por
  código, aunque dos dispositivos lo intenten a la vez.
- **Edge Function `gv-alta-articulo`** (`verify_jwt=false`, fuente en
  `supabase/functions/gv-alta-articulo/index.ts`). `POST {cod, remito, legajo, tall, linea}` crea o
  reusa el pedido y manda el WhatsApp a **5491162521635** (Thomas, `planify.employees` id 3) usando la
  Edge Function `send-whatsapp` que ya existía, con `plantilla:"_texto_libre"`. `GET ?token=…&r=ok|no`
  muestra una página con un botón y **`&c=1` recién ahí resuelve** — el doble paso es a propósito:
  WhatsApp pega un GET para el preview del link y, si el primer GET resolviera, **el preview aprobaría
  solo**. Escribe con `service_role`.
- **Respaldo por Telegram** (`tg_enqueue`): WhatsApp por API sólo deja mandar texto libre dentro de la
  ventana de 24 h de Meta. Si Meta rechaza, el pedido igual llega por Telegram con los mismos dos
  links, y la fila queda con `wa_ok=false` y el error en `wa_error`.
- **Front (`recepcion.js`, `?v=15.36`)**: `arAddCode` mira `window.GONDOLA`; si el código **no está en
  la planimetría** pide el OK antes de dejar cargar. El artículo **no** se guarda fijo en
  `Articulos Virgilio X Tallerista` mientras está pendiente (así un alta rechazada no ensucia la lista
  para siempre): `arSaveCodeRemote` se llama recién cuando el estado pasa a `ok`. El botón del código
  muestra ⏳ / ⛔, se repregunta cada 8 s, y `opEnviar` **relee el backend** y no manda nada si hay un
  alta sin `ok`. El estado vive en el borrador (`opState.altaNuevos`), así que sobrevive a un refresh.

**La fuente de verdad es la tabla, no el front** (protocolo de lógica en el backend): el front sólo
obedece lo que ella dice, y no puede escribirla.

**Medición.** `select cod, estado, wa_ok, wa_error, pedido_at, resuelto_at from public."GV_Alta_Articulo_Aprobacion" order by pedido_at desc;`
— vacía al desplegar. Regresión: `tests/rcp-alta-ok.cjs` (16 chequeos, en `tests/run.sh`).
⚠ La prueba de punta a punta (que el WhatsApp **llegue** y que el link destrabe) **no se pudo correr
desde acá**: el entorno no tiene salida a `*.supabase.co`. Queda como tarea Planify **3107**.

**Rollback.** Nada que revertir en objetos compartidos. Para apagarlo:

```sql
-- 1) volver al comportamiento viejo: que nada quede pendiente
update public."GV_Alta_Articulo_Aprobacion" set estado = 'ok', nota = 'apagado manual'
 where estado = 'pendiente';
-- 2) si se quiere borrar del todo
drop table public."GV_Alta_Articulo_Aprobacion";
```
y en el front revertir `arAddCode` / el guard de `opEnviar` (commit de la v15.36). La Edge Function se
puede dejar: sin llamadas no hace nada.

### §3.bn.1 — El aviso de alta de artículo NO traba la recepción (v15.39, 2026-09-11)

Corrección del dueño el mismo día, sobre la v15.36: *"no quiero que quede bloqueado a que yo les
conteste, pero yo capaz les contesto una hora después. Sí quiero que quede asentado el mensaje y que
una vez que mandan el mensaje ellos sí puedan seguir dando la recepción, pero no que queden esperando
mi respuesta"*.

**Qué se sacó** (v15.36 → v15.39):

- El guard de `opEnviar` que frenaba el envío si había un alta sin `ok`. **Eliminado**: el envío no
  mira más el estado del alta.
- `altaBloqueados()` pasó a llamarse **`altaSinRespuesta()`** y ya no decide nada — alimenta el badge
  del botón y una línea en el resumen ("🆕 Artículo nuevo avisado a Thomy: 599 — podés enviar igual").
- `arAddCode` ya no corta: ni con la respuesta `rechazado`, ni cuando **no hay red**. Sin conexión
  avisa *"no se pudo avisarle a Thomy, seguí igual"* y el código entra. El aviso no se pierde del
  todo: al enviar sale igual el evento **RSP**, que ya tenía su propio Telegram.
- El artículo **vuelve a guardarse fijo en el acto** en `Articulos Virgilio X Tallerista` (en la v15.36
  esperaba el `ok`). Como la recepción sigue de largo, el código tiene que existir igual.
- Badge: ⏳/⛔ pasó a **🆕** (pendiente), **🆕 ✅** (aprobado) y **🆕 ⛔** (rechazado). Informativo.

**Qué quedó igual:** la tabla `GV_Alta_Articulo_Aprobacion` (mismo esquema y misma RLS: anon sólo
SELECT), la Edge Function `gv-alta-articulo`, el WhatsApp a 5491162521635, el doble paso del link
(`&c=1`) y el respaldo por Telegram. Sólo cambiaron los textos: el WhatsApp cierra con *"No te apures:
siguen con la recepción igual. Tu respuesta queda asentada"* en vez de *"hasta que contestes no pueden
cerrar la recepción"*, y la página del ❌ aclara que la recepción no se frena sola.

**Consecuencia asumida:** si Thomas contesta que **no** cuando la recepción ya se cerró, **el sistema
no revierte nada**. Queda el asiento, y la próxima vez que alguien escriba ese código el "+" avisa
*"Thomy ya había dicho que NO"*. Revertir es decisión suya, a mano.

**Sin cambios en la base.** Nada que migrar ni que revertir en Supabase respecto de §3.bn; el rollback
de ahí sigue valiendo. Regresión actualizada: `tests/rcp-alta-ok.cjs` (16 chequeos, ahora verifica que
**no** trabe: `noTraba`, `envia`, `rechazadoIgualEnvia`, `offlineEntraIgual`).

---

## §3.cc — Completar desde "a guardar" en el picking (idea 4259, v15.38, 2026-09-11)

**Problema.** El picking descuenta SIEMPRE de góndola (reconciliación de PKC: separar_pedidos +N /
terminado −N). Si el operario agarra una caja que físicamente está en "a guardar" (recepción no
bajada a góndola), el sistema igual descuenta góndola → góndola negativa y a_guardar inflado.
Caso testigo: art **395**, NP **98613**, tanda **D68F** (2026-09-10): pickeó 1 con góndola 0 → −1,
mientras los 67 recibidos ese día estaban en a_guardar.

**Modelo (pedido del dueño).** Fase 1 (picking item por item): excedente primero, después góndola;
el operario carga cantidad. Fase 2 (al terminar de agarrar todo, ANTES de "Terminé el picking"): si
un faltante (pedido > puesto) tiene saldo **SOLO en "a guardar"** (racks NO), un paso lo manda a
buscarlo y le deja marcar cuántas agarró. Movimiento:

```
a_guardar        −N
separar_pedidos  +N   (Pickeados → sigue el pipeline normal: armado TAP → a_facturar → facturado)
```
Góndola **no se toca**.

**Backend (nuevo, sin tocar la reconciliación de picking):**
- Evento `opcion='PKA'`, `texto='TANDA|ART|N'` (N = total absoluto agarrado de a_guardar).
- `public.gv_reconciliar_aguardar()` (SECURITY DEFINER, revocada anon/authenticated): lee el último
  PKA por tanda|art, hace UPSERT `a_guardar −q / separar_pedidos +q` con `tipo='aguardar'`, clamp por
  art al a_guardar disponible (excluyendo sus propias filas) con ventana por tanda → nunca deja
  a_guardar negativo. Idempotente (DO UPDATE). `sql/gv_reconciliar_aguardar.sql`.
- Índice `mov_stock_aguardar_dedup` (parcial `WHERE tipo='aguardar'`). Cron `gv-reconciliar-aguardar`
  (jobid **81**, `*/2 * * * *`).
- `tipo='aguardar'` (no `'picking'`) a propósito: la rama B.3 de `reconciliar_pipeline_stock_etapa1`
  recalcula `terminado` mirando SOLO `tipo='picking'`, así que estas filas NO vuelven a descontar
  góndola.

**Front (`index.html` v15.38):** `pkFetchAGuardar` (saldo a_guardar), `pkPrepAGuardar` +
`pkAGuardarCardHtml` + `pkAGuardarConfirm`/`pkAGuardarSkip` (paso en el cierre del picking),
`pkEmitAGuardar` (evento PKA; el legajo de PRUEBA no persiste). `faltantesDeTanda` ahora **resta**
lo completado por PKA → el armado (FAL) y facturación ven el faltante NETO. Se **reemplazó** el
pop-up RAG viejo (racks+a_guardar, sólo aviso): en `stockBajaPicking` el bloque quedó en
`if (false && enDeposito.length)`.

**Prueba (2026-09-11, con rollback).** PKA `ZZTEST2|321|3` → `gv_reconciliar_aguardar()` bajó
321 de a_guardar 50→47 y separar_pedidos 0→3. Re-correr = idempotente (47/3). Clamp probado con
395 (a_guardar 0 → q=0, no negativo). Todo el rastro de prueba borrado; 321 volvió a 50/0.

**Rollback:** `docs/ROLLBACK-PRODUCCION.md` §1.x. SQL: `sql/gv_reconciliar_aguardar.sql`.

## §3.cd — RR y Cola de Impresión: las NP web del formato nuevo salían sin cliente (v15.42, 2026-09-11)

**Síntoma (dueño, 11/09):** en **Recepción Remitos (RR)** las filas `LK 0003` y `LK 0001`
mostraban `—` en **Cod Cliente** y **Razón Social**; los líos (17 y 1) sí salían.

**Causa.** Los eventos de operario guardan la NP como la etiqueta web (`texto = 'LK 0003|E01D|'`),
pero `vista_control_remitos` busca el cliente sólo en `PPP_Programacion_Diaria` y
`PPP_Entregados_Meta`, las **dos de ISIS**. Las NP web viven en `PPP_Web_Programacion`
(`empresa` + `np` + `np_idx`), y la etiqueta la arma `gv_ppp_web_np_label(empresa, np, np_idx)`.
Sin ese join, el `COALESCE` cae a `''`.

**Arreglo (aditivo, las vistas viejas no se tocan).** `sql/gv_vistas_np_web_v1542.sql`:

| Vista nueva (`security_invoker = true`) | Encima de | Completa |
|---|---|---|
| `gv_vista_control_remitos` | `vista_control_remitos` | `cod_cliente`, `rs` |
| `gv_vista_cola_impresion` | `vista_cola_impresion` | `razon_social` |

Las dos hacen `left join lateral` contra `PPP_Web_Programacion` por
`gv_ppp_web_np_label(...) = btrim(np)` y sólo rellenan **cuando el valor viejo viene vacío**: para
las NP de ISIS el resultado es idéntico. Front (`index.html` v15.42): `fetchCRData` y el badge de
RR pasan a `gv_vista_control_remitos`; la cola de impresión, a `gv_vista_cola_impresion`.

**Medición.**

| NP | cod_cliente antes | cod_cliente después | rs después |
|---|---|---|---|
| LK 0001 | (vacío) | 4210 | Garbarino Franco Tomas |
| LK 0003 | (vacío) | 4109 | Di Leo Rossi Echarri Pedro SH |
| 98633 … 98683 (16 NP de ISIS) | igual | igual | igual |

**Lo que NO estaba roto:** Carga Camión (`fetchCCData`) y Control Remitos (`fetchCCRData`) sacan la
razón social de `Facturacion_NP`, que sí tiene las NP web (`LK 0001`, `LK 0003`, `LK 0011`).

### §3.cd.1 — 98665: las NP de ISIS que ya salieron de la Programación también se completan (v15.44, 2026-09-11)

Thomas pidió revisar la única fila que seguía vacía. **No era un dato perdido:** `98665` es
**Merajver Marcelo Fabian (cod 2193)**, tanda **D50E**, facturada el **02/09** y con salida el 02/09
— pero el operario le hizo CCR el 08/09 y CCN el **10/09**, así que volvió a caer en RR. Para
entonces ISIS ya la había sacado de `PPP_Programacion_Diaria` (hay hueco entre 98664 y 98666) y
nunca llegó a `PPP_Entregados_Meta`, así que las dos fuentes de la vista vieja estaban vacías.

El dato sí existe en otras dos tablas: **`Facturacion_NP`** (razón social) y **`Entregas_Virgilio`**
(`cod_cliente`). `gv_vista_control_remitos` suma las dos como último fallback, después del valor
original y de `PPP_Web_Programacion`:

| Fuente, en orden | Completa | Para qué NP |
|---|---|---|
| `vista_control_remitos` (ISIS) | cod + rs | las normales |
| `PPP_Web_Programacion` | cod + rs | web (`LK 0003`) |
| `Facturacion_NP` | rs | ISIS ya facturada y fuera de Programación |
| `Entregas_Virgilio` | cod | ídem |

**Medición:** las **18** filas de RR quedan con cliente; `98665` → `2193 · Merajver Marcelo Fabian`.
Las 16 NP de ISIS normales, sin cambio (el fallback sólo entra cuando el valor viejo viene vacío).

**Rollback:** apuntar el front a `vista_control_remitos` / `vista_cola_impresion` y
`drop view public.gv_vista_control_remitos, public.gv_vista_cola_impresion;`

---

## §3.«PKC-DEP» — El PKC dice DE DÓNDE salió cada caja (v15.41, 2026-09-11, pedido de Luis)

> ⚠ **La letra de esta sección se asigna AL MERGEAR, no antes.** `main` se mueve muy rápido
> (32 commits y 19 versiones en una hora el 11/09) y cada sesión que escribe acá toma la
> letra siguiente: esta sección nació como §3.cd, tuvo que pasar a §3.ce, y para cuando se
> mergee `main` ya va por §3.ci. Mientras viva en una rama se llama **`§3.«PKC-DEP»`**, que
> es único y no choca con nadie. Al mergear: reemplazar por la letra libre que siga y
> buscar `«PKC-DEP»` en el repo para actualizar las referencias de una sola pasada.

**El problema.** El picking le dice al operario dónde ir: parte el artículo en **dos pasos**
cuando hay excedente — uno de góndola con su sector y otro `art·EXC` con la ubicación del
excedente (`index.html`, bloque `excSteps`) — y después **tiraba ese dato**. El evento era
`TANDA|ART|esp|real`, sin depósito, y el backend **re-derivaba** el reparto al reconciliar,
con los saldos vivos de ese momento:

```
from_exc = least(picked, excedente_disponible − lo_ya_tomado_por_otras_tandas)
```

O sea, adivinaba a las 09:17 algo que el operario tenía en la mano a las 09:15.

**Y encima se perdían cajas.** Los dos pasos comparten `client_id`
(`pkc_<legajo>_<tanda>_<ART>_<día>`) y el POST va con `on_conflict=client_id` +
`resolution=merge-duplicates`. Los pasos de excedente se encolan **al final**
(`allItems = items.concat(excSteps)`), así que **el PKC del excedente pisaba al de góndola**
y las cajas de góndola desaparecían del registro. Huella medida: de **815** pickings con
excedente en 60 días, **802 (98,4 %)** figuraban como 100 % excedente y 0 de góndola.

**Cómo quedó.** Un **único** evento por `(tanda, artículo)` con los **totales de los dos
pasos** y un 5.º campo:

```
TANDA|ART|esp|real|excedente     ← "de las `real` cajas, tantas salieron del excedente"
```

Un solo evento **a propósito**: hay **12 objetos** en la base que leen PKC asumiendo una fila
por `(tanda, artículo)` — `vista_faltante_real`, `vista_faltantes_sin_completar`,
`notificar_faltante_telegram`, `reporte_agentes_faltante_articulo`, `anular_picking_virgilio`,
`generar_reporte_agentes`, `gv_ppp_tanda_mover`, `gv_ppp_web_pickers_tipicos`,
`ppp_web_armar_tandas`, `trg_pkc_reconciliar_rt` y las dos de abajo. Partirlo en dos filas los
rompía a todos en silencio. Con una sola, ninguno se entera: sólo ven que `esp`/`real` ahora
traen el total correcto en vez del pedazo del excedente.

**Front** (`index.html`): `pkTotalesArt(rec)` suma los pasos del mismo código —salteando el
`esp` del paso de excedente marcado **a mano** (`manualExc`), que repite el del de góndola—;
`pkSendDetail` arma el texto con esos totales. `_pk.excOk` marca si la consulta de excedente
**anduvo**: si falló (sin red), el 5.º campo **no se manda** y el backend vuelve a repartir por
saldos — un fetch caído no se confunde con "no hay excedente".

**Backend**: `reconciliar_pipeline_stock_etapa1()` (cron 68) y `reconciliar_stock_articulo_rt()`
(trigger `trg_pkc_reconciliar_rt`). Las **dos**, si no el trigger escribe la adivinanza en cada
PKC y el cron la corrige 10 min después (flip-flop). En la rama B, `want_exc` = lo declarado si
el evento lo trae, si no `picked` (la adivinanza vieja). El **clamp** contra el excedente
disponible y la **ventana por tanda** se mantienen → el excedente nunca queda negativo (fix
v11.73 intacto). La rama A (histórico) no se toca: esos eventos son todos viejos.

**Compatibilidad.** PKC de 4 campos → `tiene_dep = false` → idéntico a antes.

**Interruptor:** `Stock_Config.pkc_deposito_activo = '0'` → vuelve a adivinar, sin tocar
código. Sin la fila = prendido.

**Prueba (2026-09-11).** (1) Con el código nuevo y sólo PKC viejos, la función no movió
ninguna de las 23.311 filas `tipo='picking'` (los 30 renglones nuevos eran la tanda D67E,
que se estaba pickeando en vivo). (2) Tanda falsa `ZZDEP1|207|10|10|3` (art 207, excedente
27) → **excedente −3 / góndola −7 / separar_pedidos +10**; la lógica vieja daba **−10 / 0**.
(3) Con el interruptor en `'0'` volvió a −10/0. (4) Rastro de prueba borrado; art 207 volvió
a excedente 27 / góndola 133. (5) Suite completa: 119 bloques, 0 fallas, con el test nuevo
`tests/pk-deposito-pkc.cjs`.

**Orden del recorrido: el EXCEDENTE va PRIMERO** (dueño vía Luis, 2026-09-11). Antes los
pasos `art·EXC` se encolaban al final (`items.concat(excSteps)`); ahora al principio
(`excSteps.concat(items)`). **No cambia de dónde se descuenta**: el reparto `excUsed` /
`gondNeeded` ya quedó decidido al abrir la tanda, antes de que el operario dé un paso. Lo que
cambia es la **recuperación del error**: si el excedente miente (el saldo dice 10 y hay 6),
yendo primero se entera al principio y levanta las 4 que faltan de góndola **en la misma
pasada**; al final se enteraba con el paso de góndola ya cerrado pidiendo sólo el resto, y
tenía que volver. El excedente marcado **a mano** (`pkMarkExcedente`) sigue yendo al final: se
descubre parado en la góndola, cuando la zona del excedente ya quedó atrás.

**Lo que NO se hizo, y por qué.** Se evaluó partir el PKC en **una fila por paso** (góndola y
excedente por separado). Se descartó: no arregla nada que la fila única no arregle ya —las
cajas perdidas las arregla el total, el depósito lo arregla el 5.º campo, y del lado del stock
la separación **ya existe** (el picking escribe `terminado` / `excedente` / `separar_pedidos`,
con `deposito` en la clave única). Lo único que sumaba era trazabilidad por paso, y costaba
arreglar `vista_faltante_real` (usa `row_number() … rn = 1`, se quedaría con una sola fila),
`faltantesDeTanda` y `pkFetchServerMarks` en el front, más dos renglones duplicados en
`notificar_faltante_telegram` y `generar_reporte_agentes`. Si algún día hace falta la traza por
paso, va **otro campo en el texto**, no otra fila.

**Nota sobre `Movimientos_Stock.empresa`:** el picking **no la escribe** (no está en el `INSERT`),
la llenan el `DEFAULT 'Mixto'` y el trigger `zz_normalizar_empresa`. Sí se **lee**: es parte de la
clave del UPSERT. Pero informa poco — `codigos_duales` tiene 4 códigos (`437E, 438E, 439E, 809E`) y
el trigger fuerza `'Mixto'` para todo el resto: de las 23.341 filas de picking, **22.867 son
`'Mixto'`** (309 artículos), 344 `LK` y 130 `CH` (4 artículos cada uno).

**Rollback:** `docs/ROLLBACK-PRODUCCION.md` (entrada v15.41) y
`sql/backups/reconciliar_pkc_pre_v1541_20260911.sql`. SQL nuevo: `sql/gv_pkc_deposito_v1541.sql`.

---

## §3.«LUGAR-EMP» — La empresa es un atributo del LUGAR, y viaja de la recepción a la góndola (v15.71, 2026-09-11, pedido de Luis)

> ⚠ **La letra se asigna AL MERGEAR, no antes** (misma regla que `§3.«PKC-DEP»`, y por el
> mismo motivo: `main` se mueve a 19 versiones por hora y cada sesión toma la letra siguiente).
> Mientras viva en rama se llama **`§3.«LUGAR-EMP»`**. Al mergear: reemplazar por la letra
> libre que siga y buscar `«LUGAR-EMP»` en el repo.

**El problema.** El sistema no tenía dónde guardar *de qué empresa es esta mercadería*, así
que la gente lo metió adentro del **nombre del código**, y cada módulo eligió su propia
grafía: `437E LK` (`Planimetria`), `437E-` (`planimetria.js`), `437EL` (Importados) y la
columna `empresa` (`Movimientos_Stock`). Cuatro convenciones para un solo dato.

El costo real lo pagó el **809E**, que es **dos productos distintos** (CH = Corta Queso,
LK = Corta Pizza) y **nunca recibió sufijo en ninguna de las cuatro**: siempre caía al
fallback, que mandaba al pickeador de LK a **M13** —la góndola de Chef— a buscar un Corta
Pizza y encontrar un Corta Queso.

**La observación que lo cierra.** La empresa no es un atributo del código: es un atributo del
**lugar**. **684 de los 685 sectores** tienen una sola empresa. Con eso, `809E` vive en
J13/J14 (LK) y M13/M14/M15 (CH) **sin sufijo ninguno**.

### Las tablas nuevas (objetos NUEVOS, prefijo `GV_`; no pisan nada)

| Objeto | Qué es | Filas |
|---|---|---|
| `GV_Lugar` | un lugar físico. PK `sector` (canónico `LETRAS+2 dígitos`, `J1`→`J01`), `tipo` (góndola/rack), `empresa` (`LK`/`CH`/`IN`), `orden` del recorrido, `uso` | 872 |
| `GV_Lugar_Item` | qué hay en cada lugar. PK **`(sector, cod, clase)`** | 786 |
| `GV_Lugar_Pendiente` | los insumos, estacionados hasta que se los trabaje aparte | 148 |
| `gv_ocupacion_lugar` | vista derivada de `Movimientos_Stock`; **nunca se escribe** | — |

**`clase` va en la PK y no es cosmético:** hay **9 códigos que existen como artículo y como
insumo a la vez** y son cosas distintas. Con PK `(sector, cod)` el mismo lugar no podía tener
el artículo 437E y el insumo 437E — justo el caso que motivó la tabla.

**La `clase` sale del CONTEXTO del relevamiento, no del padrón `Insumos`.** 437E y 438E
figuran en `Insumos` y son artículos: clasificar por el padrón los mandaba a la tabla
equivocada.

### La empresa viaja: recepción → A Guardar → góndola

`Movimientos_Stock.empresa` tiene `DEFAULT 'Mixto'` y el trigger de recepción lo forzaba
**incondicionalmente** para todo lo que no fuera dual — o sea que la empresa que el operario
elegía del remito se **perdía** en el mismo INSERT. El cambio es una línea
(`sql/gv_empresa_recepcion_mg.sql`): si vino explícita `LK`/`CH`, se respeta.

El código sigue **pelado** (`438E`, nunca `438E LK`) y la empresa viaja en **su columna**.
Vista nueva `gv_saldos_stock_emp` = saldos por (código pelado, empresa).

**Backfill de A Guardar** (2026-09-11): empresa derivada del lugar (`GV_Lugar`) con fallback a
`OC_Maximos.linea`, sólo cuando es inequívoca, excluyendo los duales; 582 y 583 a `LK` por
decisión de Luis. Resultado: **0 filas en `Mixto`** — 1.118 `LK` (2.500 cajas) + 283 `CH`
(72 cajas) = 2.572 ✓. Backup: `GV_Backup_aguardar_empresa_20260911` (1.389 filas).

### ⚠ Lo que esto rompía en el front, y por qué se arregló acá

`vista_saldos_stock` **ya agrupaba por `(código, empresa)`**, pero emite el código **con
sufijo sólo para los duales**: para todo el resto emite el **código pelado, una vez por
empresa**. Mientras la recepción marcaba todo `Mixto` había una sola fila por código y nadie
lo notó. Desde que la recepción guarda `LK`/`CH`, el mismo `505` vuelve en **dos filas** (la
góndola en `LK`, el descuento del picking en `Mixto`, porque las funciones de reconciliación
insertan sin `empresa` y toman el default).

Tres lugares del front tomaban **una** de esas filas en vez de sumarlas, y los tres se
corrigieron en la v15.71:

| Función | Qué hacía | Qué muestra mal |
|---|---|---|
| `stockFetchSaldos` | `m[k] = {…}` pisaba | MG, Bajar de racks, Insumos y CP: saldo de la última fila, no el total |
| `pkFetchExcedente` | `out[k] = {cajas}` pisaba | desde la v15.41 el picking va **primero al excedente**: un número corto manda al operario a buscar de menos |
| `_stkGondolaSaldoVivo` | `a[0].terminado` | la regla de "picking difiere" devolvía a góndola con un saldo parcial |

`_pkConteoSistema` y `_pppChkBuildMaps` ya acumulaban: quedaron como estaban.

**Chequeo:** `select cod_art, count(*) from vista_saldos_stock group by 1 having count(*) > 1;`
— cada código que aparezca ahí tiene que estar sumado en el front, no pisado.

### ⚠ PENDIENTE al implementar esta rama — no perder el arreglo del saldo

El arreglo de las cuatro funciones **ya salió a `main` solo** (v15.71, commit `49c0fc6`,
11/09): el backfill de A Guardar rompió el MG **en vivo** y no podía esperar a la rama.
O sea que **la forma que hay hoy en `main` es la que tiene que quedar** cuando esta rama
se implemente. Al mergear:

1. **No revertir** `stockFetchSaldos`, `pkFetchExcedente` ni `_stkGondolaSaldoVivo` a la
   forma vieja (`m[k] = …`, `out[k] = …`, `a[0].terminado`). Si el merge los deja como
   estaban, el MG vuelve a mostrar góndola 0 o A Guardar 0.
2. **`recepcion.js`** (aviso de exceso de góndola) lleva el mismo arreglo y **sólo está en
   `main`**: esta rama no toca ese archivo, así que viene solo al traer `main`. Verificarlo
   igual.
3. **Re-bumpear la versión.** `main` se llevó la v15.71, así que esta rama pasó a **v15.72**;
   al mergear hay que subirla otra vez a lo que siga de `main`.
4. **`gv_saldos_stock_emp` todavía NO está aplicada** en la base: `stockFetchSaldos` la
   consulta best-effort y sin ella el front se comporta como siempre (sin `_emp`).

**Chequeo de que el arreglo sigue puesto:**
`grep -c 'v15.71 — ACUMULA\|v15.71 — SUMAR' index.html` → tiene que dar **3**.

**Rollback:** `docs/ROLLBACK-PRODUCCION.md` (entrada v15.71). SQL:
`sql/gv_lugar_fuente_unica.sql`, `sql/gv_lugar_carga_inicial.sql`,
`sql/gv_empresa_recepcion_mg.sql`.
