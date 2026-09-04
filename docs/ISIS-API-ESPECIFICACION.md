# API Producción Virgilio → ISIS — Pedidos armados

**Cliente:** Loekemeyer Hnos. SRL · **Ticket ISIS:** 1159666
**Documento:** respuesta al Punto 18 ("Próximos pasos Cliente") del informe consolidado
**Versión de la API:** 2.0 · **Fecha:** 2026-09-04

Este documento es el que se le manda a Sistemas ISIS. Contiene todo lo que pide el
Punto 18 **menos el token**, que va por canal aparte (ver §3).

> **⚠ Cambio respecto de la v1.0 (interno).** La v1.0 planteaba que ISIS bajara
> "pedidos terminados" identificados por la NP que ISIS ya tenía cargada, con las
> cantidades pedidas y las entregadas en paralelo. Eso quedó sin efecto. El circuito
> es el de la §0: el pedido se arma primero en Virgilio y **entra a ISIS como un
> pedido nuevo, sin NP**, con el mismo formato con el que entran hoy los pedidos de
> las páginas web. Lo que no cambió: la infraestructura (§1), la URL (§2), el token
> (§3) y la forma de las rutas (§4).

---

## 0. El circuito: ISIS recibe el pedido ya armado, como si fuera un pedido nuevo

El pedido se construye **entero** del lado de Virgilio: se toma, se planifica, se
arma en el depósito (picking y control) y recién cuando está terminado se lo pasamos
a ISIS. Lo que ISIS recibe no es un pedido a medio armar: son los códigos y las
cantidades **definitivos**, listos para facturar.

Para ISIS eso **no es un tipo de documento nuevo**. Entra por donde entran hoy los
pedidos que exportan las páginas web de Loekemeyer y de Chef, con la misma estructura
y los mismos campos. No hace falta desarrollar un consumidor especial ni un formato
nuevo.

De ahí salen tres reglas que gobiernan todo el resto de este documento:

1. **El pedido va sin número de nota de pedido.** La NP la asigna ISIS al darlo de
   alta, igual que con un pedido web. No mandamos NP nuestra dentro del pedido.
2. **Cada línea trae un código y una cantidad: los realmente preparados.** No hay
   "pedido vs. entregado". Si el depósito preparó menos, o preparó un artículo
   equivalente, el pedido ya sale corregido. Lo que ISIS recibe es lo que se factura.
3. **Lo único que necesitamos de vuelta es la NP que ISIS le asignó** (§5). Con eso
   se cierra el circuito y queda el pedido armado enlazado con su factura.

Lo que sigue igual que en la v1.0 es el **transporte**: ISIS consulta una API nuestra
(la Alternativa B del §11 del informe), porque es la que evita tener que montar
infraestructura del lado del depósito. Sólo cambió *qué* viaja, no *cómo*.

---

## 1. Infraestructura — no hace falta Windows Server, IIS, IP pública ni abrir puertos

El Punto 18 pide confirmar la infraestructura para "operar mediante API" y consultar
la configuración de Windows Server / IIS / IP pública / puertos. Eso corresponde al
escenario en el que **nosotros llamamos a la API del ISIS on-premise** (el mensaje de
Horacio Barbieri del 25/08).

Se resuelve por el otro camino, que es el que el propio informe plantea en su §11 y
el que ya está construido y andando:

> **ISIS consulta una API nuestra.** El servicio corre en la nube (Supabase, la misma
> plataforma donde ya vive Producción Virgilio), con HTTPS y certificado válido.
> ISIS hace requests **salientes** desde su red, con la frecuencia que quiera.

Consecuencias:

| Requisito del Punto 18 | Estado |
|---|---|
| Windows Server | **No se necesita.** El servicio es cloud. |
| IIS | **No se necesita.** |
| IP pública fija del depósito | **No se necesita.** |
| Abrir puertos / firewall expuesto | **No se necesita.** No se expone nada de la red del depósito. |
| Disponibilidad 24/7 | La da la plataforma cloud, no un servidor del depósito. |

Del lado de ISIS sólo hace falta **salida HTTPS (443)** hacia el dominio del servicio.

---

## 2. URL del servicio

```
https://hrxfctzncixxqmpfhskv.supabase.co/functions/v1/isis-api
```

De acá en más, `{BASE}` = esa URL. Todos los endpoints aceptan además el prefijo
opcional `/v1` (`{BASE}/v1/pedidos` es lo mismo que `{BASE}/pedidos`).

Healthcheck para probar la conectividad y el token:

```bash
curl -H "X-API-Key: <TOKEN>" https://hrxfctzncixxqmpfhskv.supabase.co/functions/v1/isis-api/ping
```

```json
{ "ok": true, "servicio": "Producción Virgilio — API pedidos armados",
  "version": "2.0", "cliente": "Sistemas ISIS - producción",
  "hora": "2026-09-04T14:07:21.137Z" }
```

---

## 3. Credenciales

Autenticación por **token fijo** en el header:

```
X-API-Key: <TOKEN>
```

También se acepta `Authorization: Bearer <TOKEN>` para clientes que no permiten
headers arbitrarios.

- El token se entrega **por canal aparte** (no va en este documento).
- Es un token de producción, de un solo consumidor (Sistemas ISIS).
- Se puede revocar y reemplazar en cualquier momento sin tocar el servicio.
- Del lado de Virgilio se guarda **sólo el hash SHA-256** del token: si se pierde,
  no se recupera — se emite uno nuevo.

Sin token o con token inválido, cualquier endpoint responde **401**.

---

## 4. Endpoints

Los pedidos se identifican con una **referencia nuestra** (`referencia`), del estilo
`LK 1344` o `CH 812`. Es sólo la clave para bajar y acusar un pedido: **no es una NP
de ISIS ni pretende serlo**, y no viaja dentro del cuerpo del pedido. La NP la pone
ISIS.

### 4.1 `GET {BASE}/pedidos` — listado de pedidos armados

Devuelve las **cabeceras** de los pedidos en un estado dado. Es el endpoint para el
polling: ISIS lo llama cada N minutos y se lleva los que están en `pendiente`.

Parámetros (query string, todos opcionales):

| Parámetro | Default | Valores |
|---|---|---|
| `estado` | `pendiente` | `pendiente`, `entregado`, `procesado`, `error`, `anulado` |
| `empresa` | (todas) | `LK` (Loekemeyer) o `CH` (Chef) |
| `desde` | (sin filtro) | fecha/hora ISO-8601; devuelve lo terminado desde ese momento |
| `limit` | `100` | 1 a 500 |

```bash
curl -H "X-API-Key: <TOKEN>" "{BASE}/pedidos?estado=pendiente&limit=50"
```

```json
{
  "ok": true,
  "estado": "pendiente",
  "total": 1,
  "pedidos": [
    {
      "referencia": "LK 1344",
      "empresa": "LK",
      "estado": "pendiente",
      "cod_cliente": "288",
      "razon_social": "MEGA BAZAR S.A.",
      "fecha_entrega": "2026-09-04",
      "terminado_en": "2026-09-03T16:35:20-03:00",
      "items": 14,
      "cajas": 25
    }
  ]
}
```

### 4.2 `GET {BASE}/pedidos/{referencia}` — el pedido completo

Devuelve el pedido en el formato de la §5, listo para darlo de alta. **Al responder,
el pedido pasa de `pendiente` a `entregado`** (queda registrado que ISIS lo bajó).
Para consultarlo sin cambiar el estado: `?marcar=false`.

```bash
curl -H "X-API-Key: <TOKEN>" "{BASE}/pedidos/LK%201344"
```

### 4.3 `POST {BASE}/pedidos/{referencia}/acuse` — confirmación de ISIS

ISIS avisa qué hizo con el pedido. Es lo que cierra el circuito, lo que **evita darlo
de alta dos veces**, y lo que nos devuelve el número de NP (§5).

```bash
curl -X POST "{BASE}/pedidos/LK%201344/acuse" \
     -H "X-API-Key: <TOKEN>" -H "Content-Type: application/json" \
     -d '{"resultado":"ok","np":"98213","nro_comprobante":"0004-00012345","cae":"75123456789012"}'
```

Cuerpo:

| Campo | Tipo | Obligatorio | Descripción |
|---|---|---|---|
| `resultado` | `"ok"` \| `"error"` | sí | Si el pedido se dio de alta / facturó, o si falló |
| `np` | string \| entero | **sí cuando `resultado = "ok"`** | Número de nota de pedido que ISIS le asignó |
| `nro_comprobante` | string | no | Nº de comprobante emitido (ej. `0004-00012345`) |
| `cae` | string | no | CAE de AFIP |
| `error_detalle` | string | no | Motivo, cuando `resultado = "error"` |

Respuesta:

```json
{ "referencia": "LK 1344", "np": "98213", "ok": true,
  "estado": "procesado", "duplicado": false }
```

Si esa referencia **ya tenía un acuse OK**, no se pisa nada y se devuelve la NP y el
comprobante ya registrados (`"duplicado": true`). El acuse es idempotente:
reintentarlo es seguro.

Variante con la referencia en el cuerpo, para clientes que no arman URLs dinámicas:
`POST {BASE}/acuse` con `{"referencia": "LK 1344", "resultado": "ok", "np": "98213", ...}`.

### 4.4 Errores

Todos los errores vienen con el mismo formato:

```json
{ "ok": false, "codigo": "token_invalido", "error": "Token inválido o dado de baja." }
```

| HTTP | `codigo` | Cuándo |
|---|---|---|
| 401 | `sin_token` / `token_invalido` | Falta el header o el token no sirve |
| 400 | `referencia_invalida`, `estado_invalido`, `resultado_invalido`, `json_invalido`, `falta_np` | Parámetros mal |
| 404 | `no_encontrado` | La referencia no está publicada |
| 404 | `ruta_desconocida` | URL mal escrita |
| 500/503 | `error_interno` / `backend` | Error del servicio — reintentar |

---

## 5. Estructura del pedido

Es la misma estructura con la que entran hoy los pedidos de las páginas web, más un
sobre con la referencia y la empresa. **El pedido en sí (`pedido`) no lleva NP.**

```json
{
  "referencia": "LK 1344",
  "empresa": "LK",
  "estado_integracion": "entregado",
  "terminado_en": "2026-09-03T16:35:20-03:00",
  "fecha_entrega": "2026-09-04",
  "pedido": {
    "source": "Virgilio",
    "cod_cliente": "288",
    "sucursal_entrega": "Rivadavia 3663 - Mar Del Plata",
    "vend": "7",
    "condicion_pago": "Pago Contado: 25% Dto",
    "condicion_pago_code": 8,
    "payment_term": 2,
    "observaciones": "",
    "items": [
      { "cod_art": "321", "cajas": 6, "uxb": 12 }
    ]
  },
  "control": {
    "items": 14,
    "cajas": 25,
    "m3": 0.142,
    "neto_estimado": 775560.24,
    "moneda": "ARS",
    "nota": "Informativo, sólo para control. El importe a facturar lo determina ISIS con su lista de precios."
  }
}
```

### Diccionario de campos

**Sobre** (uso de la integración, no del pedido)

| Campo | Tipo | Descripción |
|---|---|---|
| `referencia` | string | Clave del pedido en esta API (`LK 1344`). Se usa en la URL y en el acuse. **No es una NP.** |
| `empresa` | `"LK"` \| `"CH"` | Razón social a la que corresponde el pedido — las dos que contempla el §14 del informe. |
| `estado_integracion` | string | `pendiente`, `entregado`, `procesado`, `error`, `anulado`. |
| `terminado_en` | ISO-8601 `-03:00` | Momento en que el pedido quedó armado y cerrado. |
| `fecha_entrega` | `YYYY-MM-DD` | Fecha de salida prevista del camión. |
| `anulado` | booleano | Aparece **sólo** si el pedido se dio de baja después de publicarse (§6). |

**`pedido`** — el pedido propiamente dicho, en formato de pedido web

| Campo | Tipo | Descripción |
|---|---|---|
| `source` | string | Origen del pedido. Siempre `"Virgilio"`. |
| `cod_cliente` | string | Código de cliente en ISIS. |
| `sucursal_entrega` | string | Domicilio de entrega elegido. |
| `vend` | string | Código de vendedor. |
| `condicion_pago` | string | Condición de pago, en texto, tal como la muestran las páginas. |
| `condicion_pago_code` | entero | Código de la condición de pago. |
| `payment_term` | entero | Plazo de pago. |
| `observaciones` | string | Observaciones del pedido (puede ir vacío). |
| `items[]` | array | Las líneas. Ver abajo. |

**`pedido.items[]`**

| Campo | Tipo | Descripción |
|---|---|---|
| `cod_art` | string | Código de artículo **realmente preparado**. Es el que se factura. |
| `cajas` | entero | Cajas **realmente preparadas**. Es lo que se factura. |
| `uxb` | entero | Unidades por caja del artículo. |

**`control`** — dato **informativo**, no forma parte del pedido. `neto_estimado` es el
neto que calcula Virgilio con su lista de precios; sirve sólo para cotejar contra lo
que emite ISIS. `m3` son los metros cúbicos, para logística.

### Tres reglas importantes de lectura

1. **El pedido no trae NP y no hay que buscarle una.** Se da de alta como un pedido
   nuevo y la NP la asigna ISIS. Esa NP vuelve por el acuse (§4.3).
2. **`cajas` y `cod_art` son lo preparado, y es lo único que viaja.** No hay campos de
   "pedido original": si se preparó menos o se preparó un equivalente, la corrección
   ya vino hecha. No hay nada que conciliar del lado de ISIS.
3. **Un pedido aparece en la API recién cuando está armado y cerrado.** No hay pedidos
   a medio armar en esta API.

---

## 6. Ciclo de vida de un pedido

```
        el pedido queda armado y cerrado en Virgilio
                 │
                 ▼
          ┌─────────────┐  GET /pedidos/{ref}   ┌────────────┐
          │  pendiente  │ ────────────────────► │ entregado  │
          └─────────────┘                       └────────────┘
                 │                                     │
                 │ se da de baja en Virgilio           │ POST .../acuse  (trae la NP)
                 ▼                                     ▼
          ┌─────────────┐                     ┌───────────────────┐
          │   anulado   │                     │ procesado | error │
          └─────────────┘                     └───────────────────┘
```

- **`pendiente`** — listo para que ISIS lo baje.
- **`entregado`** — ISIS ya lo bajó, todavía sin acusar.
- **`procesado`** — ISIS lo dio de alta y facturó; quedó registrada la NP asignada.
- **`error`** — ISIS no pudo procesarlo; queda registrado el motivo.
- **`anulado`** — el pedido se dio de baja en Virgilio. Si eso pasa **después** de que
  ISIS lo bajó, el pedido conserva su estado pero aparece con `"anulado": true` y se
  puede listar con `GET /pedidos?estado=anulado`. **Se recomienda consultar ese
  listado en cada ciclo de polling**, para no facturar algo que se dio de baja.

### Polling sugerido

1. `GET /pedidos?estado=pendiente` cada 5–15 minutos.
2. Por cada referencia de la lista: `GET /pedidos/{referencia}`, dar de alta el pedido
   y facturarlo.
3. `POST /pedidos/{referencia}/acuse` con el resultado y **con la NP asignada**
   (siempre, también en error).
4. `GET /pedidos?estado=anulado` para detectar bajas.

Reintentos: todos los endpoints son seguros de reintentar. El acuse no duplica.

---

## 7. Trazabilidad

Del lado de Virgilio queda registrado, por referencia: cuándo se terminó de armar,
cuándo lo bajó ISIS y cuántas veces, el JSON exacto que se entregó, y el acuse (NP
asignada, resultado, número de comprobante, CAE o error). Además se loguea cada
request de la API (método, ruta, referencia, código HTTP, tiempo de respuesta). Es lo
que pide el §18 del informe.

---

## 8. Lo que falta confirmar del lado de ISIS

1. **La estructura exacta de un pedido web.** Como el pedido tiene que entrar igual
   que uno de las páginas, necesitamos que ISIS confirme el formato que recibe hoy:
   qué campos son obligatorios, cuáles opcionales, y el dominio de la condición de
   pago. El de la §5 es el que tenemos relevado; si falta algo, lo agregamos.
2. **Un pedido de Virgilio, ¿es un pedido de ISIS?** Si un pedido armado se factura
   siempre en un solo comprobante, la referencia mapea 1 a 1 contra la NP. Si ISIS
   puede partirlo, el acuse tiene que poder traer más de una NP.
3. **P4 — Recepción de mercadería (remitos de compra).** Requiere definir el mapeo de
   códigos de proveedor/artículo entre los dos sistemas.
4. **Cutover de la emisión.** Hoy Producción Virgilio emite Factura A por punto de
   venta 11. Cuando ISIS empiece a facturar estos pedidos, hay que **apagar la emisión
   propia el mismo día** para no pedir dos CAE por la misma venta. Definir fecha y si
   el PV 11 queda de respaldo.

> **P3 queda resuelto.** El informe lo dejaba abierto ("cómo devuelve ISIS el número
> de NP cuando el pedido nace del otro lado"). Con este esquema no necesita desarrollo
> aparte: la NP viaja en el campo `np` del acuse.

---

## Anexo técnico (interno, no se envía a ISIS)

- Edge Function: `supabase/functions/isis-api/index.ts` (proyecto `hrxfctzncixxqmpfhskv`,
  `verify_jwt = off` — la función valida su propio token).
- DDL, RPCs y triggers: `sql/isis_api.sql`.
- Tablas: `isis_export_pedidos` (cola), `isis_api_tokens` (hashes), `isis_api_log` (traza).
  Las tres con RLS activa y sin policies → la anon key **no** las ve. Las RPC son
  `SECURITY DEFINER` con `EXECUTE` sólo para `service_role`.
- Alta de un token nuevo:
  ```sql
  -- token en claro generado afuera; en la base va sólo el sha256
  INSERT INTO public.isis_api_tokens (nombre, token_hash, nota)
  VALUES ('Sistemas ISIS - producción', '<sha256 hex>', 'Ticket 1159666');
  ```
  Baja: `UPDATE public.isis_api_tokens SET activo = false WHERE nombre = '...';`

### ⚠ Estado del código respecto de esta v2.0

**El servicio desplegado todavía implementa la v1.0.** Este documento es el contrato
acordado; el código va detrás. Falta, concretamente:

1. **`isis_pedido_json(np)` → `isis_pedido_json(referencia)`.** Hoy arma el JSON desde
   `Facturacion_NP` + `Entregas_Virgilio` y emite `np`, `cajas_pedidas`/`cajas`,
   `articulo`/`articulo_pedido`. Tiene que emitir el sobre + `pedido` de la §5: una
   sola cantidad y un solo código por línea, y nada de NP.
2. **Los campos comerciales** (`vend`, `condicion_pago`, `condicion_pago_code`,
   `payment_term`, `sucursal_entrega`) hoy no están del lado de Virgilio: vienen del
   `sheets_payload` de la página, que vive en el proyecto de LK. Hay que traerlos
   (mismo camino FDW que ya usa el pipeline PPP) o guardarlos al tomar el pedido.
3. **La clave de `isis_export_pedidos` pasa a ser la referencia**, no la NP, y se
   agrega la columna para la **NP que devuelve ISIS** en el acuse. Es una tabla
   nuestra, así que se puede rehacer sin tocar nada compartido.
4. **El disparador.** Hoy es un trigger sobre `Facturacion_NP` (INSERT → encola). Con
   el pipeline nuevo el disparador es el cierre del armado, no el tilde de
   facturación. Se define junto con el resto del pipeline de ventas.
- Las NP facturadas **antes** de encender la integración no están en la cola (la tabla
  arrancó vacía a propósito) — ISIS no las va a ver.
