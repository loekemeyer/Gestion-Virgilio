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
2. **Que la facturación de NP web escriba en `Facturacion_NP` con la etiqueta** (`LK 00001`).
   Pendiente #4.
3. **El picking todavía no ordena por `prioridad`.** La columna se llena y el cartel se ve,
   pero la lista del operario sigue en su orden de siempre. Falta engancharlo donde se arma
   esa lista.
4. Nada de esto corrió con datos reales, porque la numeración está apagada.

---

## 3.i Sólo zona 1 y zona 2 se programan solas — 2026-09-04

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

### Lo que falta

1. **El front**: las tres columnas, el arrastre, el "+" y el badge. Esto es sólo la lógica
   de atrás, que es lo que se pidió primero.
2. La lista de la izquierda la arma el front (las NP viven en LK/Chef); de acá sólo
   necesita saber cuáles están tomadas.
3. Programar no funciona hasta que se prenda la numeración. A propósito.

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

## 5. Pendientes

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
