# API Producción Virgilio → ISIS — Pedidos terminados

**Cliente:** Loekemeyer Hnos. SRL · **Ticket ISIS:** 1159666
**Documento:** respuesta al Punto 18 ("Próximos pasos Cliente") del informe consolidado
**Versión de la API:** 1.0 · **Fecha:** 2026-09-04

Este documento es el que se le manda a Sistemas ISIS. Contiene todo lo que pide el
Punto 18 **menos el token**, que va por canal aparte (ver §3).

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
{ "ok": true, "servicio": "Producción Virgilio — API pedidos terminados",
  "version": "1.0", "cliente": "Sistemas ISIS - producción",
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

### 4.1 `GET {BASE}/pedidos` — listado de pedidos terminados

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
      "np": 44604,
      "empresa": "CH",
      "estado": "pendiente",
      "cod_cliente": "2477",
      "razon_social": "MEGA BAZAR S.A.",
      "tanda": "D56E",
      "fecha_entrega": "2026-09-04",
      "terminado_en": "2026-09-03T16:35:20-03:00",
      "m3": 0.142
    }
  ]
}
```

### 4.2 `GET {BASE}/pedidos/{np}` — el pedido completo

Devuelve el JSON con el detalle de artículos. **Al responder, el pedido pasa de
`pendiente` a `entregado`** (queda registrado que ISIS lo bajó). Para consultarlo sin
cambiar el estado: `?marcar=false`.

```bash
curl -H "X-API-Key: <TOKEN>" "{BASE}/pedidos/44604"
```

La estructura está en la §5.

### 4.3 `POST {BASE}/pedidos/{np}/acuse` — confirmación de ISIS

ISIS avisa qué hizo con el pedido. Es lo que cierra el circuito y **evita facturar dos
veces la misma NP**.

```bash
curl -X POST "{BASE}/pedidos/44604/acuse" \
     -H "X-API-Key: <TOKEN>" -H "Content-Type: application/json" \
     -d '{"resultado":"ok","nro_comprobante":"0004-00012345","cae":"75123456789012"}'
```

Cuerpo:

| Campo | Tipo | Obligatorio | Descripción |
|---|---|---|---|
| `resultado` | `"ok"` \| `"error"` | sí | Si se facturó o si falló |
| `nro_comprobante` | string | no | Nº de comprobante emitido (ej. `0004-00012345`) |
| `cae` | string | no | CAE de AFIP |
| `error_detalle` | string | no | Motivo, cuando `resultado = "error"` |

Respuesta:

```json
{ "np": "44604", "ok": true, "estado": "procesado", "duplicado": false }
```

Si esa NP **ya tenía un acuse OK**, no se pisa nada y se devuelve el comprobante ya
registrado (`"duplicado": true`). El acuse es idempotente: reintentarlo es seguro.

Variante con la NP en el cuerpo, para clientes que no arman URLs dinámicas:
`POST {BASE}/acuse` con `{"np": 44604, "resultado": "ok", ...}`.

### 4.4 Errores

Todos los errores vienen con el mismo formato:

```json
{ "ok": false, "codigo": "token_invalido", "error": "Token inválido o dado de baja." }
```

| HTTP | `codigo` | Cuándo |
|---|---|---|
| 401 | `sin_token` / `token_invalido` | Falta el header o el token no sirve |
| 400 | `np_invalida`, `estado_invalido`, `resultado_invalido`, `json_invalido` | Parámetros mal |
| 404 | `no_encontrado` | La NP no está publicada como pedido terminado |
| 404 | `ruta_desconocida` | URL mal escrita |
| 500/503 | `error_interno` / `backend` | Error del servicio — reintentar |

---

## 5. Estructura JSON del pedido

```json
{
  "np": 44604,
  "empresa": "CH",
  "cod_cliente": "2477",
  "razon_social": "MEGA BAZAR S.A.",
  "tanda": "D56E",
  "fecha_entrega": "2026-09-04",
  "terminado_en": "2026-09-03T16:35:20-03:00",
  "m3": 0.142,
  "estado": "terminado",
  "estado_integracion": "entregado",
  "completo": true,
  "totales": {
    "items": 14,
    "cajas_pedidas": 25,
    "cajas_a_facturar": 25,
    "cajas_falto": 0
  },
  "items": [
    {
      "articulo": "437E",
      "articulo_pedido": "437E",
      "descripcion": "Colador Ø 16cm",
      "unidades_x_caja": 24,
      "cajas_pedidas": 1,
      "cajas": 1,
      "cajas_falto": 0,
      "unidades": 24,
      "completo": true
    }
  ],
  "faltantes": [],
  "control": {
    "neto_estimado": 775560.24,
    "moneda": "ARS",
    "nota": "Informativo, solo para control. El importe a facturar lo determina ISIS con su lista de precios."
  }
}
```

### Diccionario de campos

**Cabecera**

| Campo | Tipo | Descripción |
|---|---|---|
| `np` | entero | Número de pedido (NP). Es la clave con la que ISIS identifica el pedido que ya tiene cargado. |
| `empresa` | `"LK"` \| `"CH"` | Empresa del pedido. Se deriva de la NP: 9xxxx = Loekemeyer, 4xxxx = Chef. |
| `cod_cliente` | string | Código de cliente. |
| `razon_social` | string | Razón social del cliente. |
| `tanda` | string | Tanda de preparación en el depósito (uso interno, informativo). |
| `fecha_entrega` | fecha `YYYY-MM-DD` | Fecha de salida prevista. |
| `terminado_en` | ISO-8601 con offset `-03:00` | Momento en que el pedido quedó terminado. |
| `m3` | decimal | Metros cúbicos del pedido (informativo, para logística). |
| `estado` | `"terminado"` | Estado del pedido en producción. |
| `estado_integracion` | string | Estado en esta API: `pendiente`, `entregado`, `procesado`, `error`, `anulado`. |
| `completo` | booleano | `true` si se armó todo lo pedido; `false` si hubo faltantes. |
| `anulado` | booleano | Aparece **sólo** si el pedido fue dado de baja después de publicarse (ver §6). |

**`totales`**

| Campo | Descripción |
|---|---|
| `items` | Cantidad de artículos distintos. |
| `cajas_pedidas` | Cajas del pedido original. |
| `cajas_a_facturar` | Cajas realmente preparadas → **es lo que se factura**. |
| `cajas_falto` | Cajas que no se pudieron preparar. |

**`items[]`**

| Campo | Descripción |
|---|---|
| `articulo` | ⚠ **Código realmente preparado en el depósito.** Es el que hay que facturar. |
| `articulo_pedido` | Código con el que venía la línea del pedido. Casi siempre igual a `articulo`; difiere cuando se preparó un artículo equivalente (ej. pedido `029`, preparado `437E`). |
| `descripcion` | Descripción del artículo. |
| `unidades_x_caja` | Unidades por caja (`null` si el artículo no la tiene cargada). |
| `cajas_pedidas` | Cajas de la línea del pedido. |
| `cajas` | **Cajas a facturar** (lo preparado). |
| `cajas_falto` | Cajas de esa línea que no se prepararon. |
| `unidades` | `cajas × unidades_x_caja` (`null` si no hay `unidades_x_caja`). |
| `completo` | `false` si la línea salió incompleta. |

**`faltantes[]`** — sólo los artículos con `cajas_falto > 0`, resumidos
(`articulo`, `cajas_falto`). Es la misma información de `items[]`, junta y aparte.

**`control`** — dato **informativo**, no es la factura. `neto_estimado` es el neto que
calcula Virgilio con su lista de precios; sirve para cotejar contra lo que emite ISIS.

### Tres reglas importantes de lectura

1. **Se factura `cajas`, no `cajas_pedidas`.** Si el depósito preparó menos, se
   factura lo preparado (factura parcial). El resto no se entrega.
2. **Se factura el `articulo`, no el `articulo_pedido`.** Cuando el depósito prepara
   un artículo equivalente, la factura tiene que ir con el código realmente preparado.
3. **Un pedido aparece en la API recién cuando está terminado**, es decir cuando la
   operadora administrativa lo dio por cerrado en Producción Virgilio. No hay pedidos
   "a medio armar" en esta API.

---

## 6. Ciclo de vida de un pedido

```
   la operadora cierra el pedido en Virgilio
                 │
                 ▼
          ┌─────────────┐   GET /pedidos/{np}   ┌────────────┐
          │  pendiente  │ ────────────────────► │ entregado  │
          └─────────────┘                       └────────────┘
                 │                                     │
                 │ se destilda en Virgilio             │ POST .../acuse
                 ▼                                     ▼
          ┌─────────────┐                     ┌───────────────────┐
          │   anulado   │                     │ procesado | error │
          └─────────────┘                     └───────────────────┘
```

- **`pendiente`** — listo para que ISIS lo baje.
- **`entregado`** — ISIS ya lo bajó, todavía sin acusar.
- **`procesado`** — ISIS facturó (con `nro_comprobante` / `cae`).
- **`error`** — ISIS no pudo procesarlo; queda registrado el motivo.
- **`anulado`** — el pedido se dio de baja en Virgilio (la operadora destildó).
  Si eso pasa **después** de que ISIS lo bajó, el pedido conserva su estado pero
  aparece con `"anulado": true` y se puede listar con `GET /pedidos?estado=anulado`.
  **Se recomienda consultar ese listado en cada ciclo de polling**, para no facturar
  algo que se dio de baja.

### Polling sugerido

1. `GET /pedidos?estado=pendiente` cada 5–15 minutos.
2. Por cada NP de la lista: `GET /pedidos/{np}` y facturar.
3. `POST /pedidos/{np}/acuse` con el resultado (siempre, también en error).
4. `GET /pedidos?estado=anulado` para detectar bajas.

Reintentos: todos los endpoints son seguros de reintentar. El acuse no duplica.

---

## 7. Trazabilidad

Del lado de Virgilio queda registrado, por NP: cuándo se terminó, cuándo lo bajó
ISIS y cuántas veces, el JSON exacto que se entregó, y el acuse (resultado, número de
comprobante, CAE o error). Además se loguea cada request de la API (método, ruta,
NP, código HTTP, tiempo de respuesta). Es lo que pide el §18 del informe.

---

## 8. Lo que sigue faltando definir del lado de ISIS

Estos puntos están en el informe pero todavía no tienen respuesta, y **no bloquean**
el circuito de facturación de arriba:

1. **P3 — NP de ISIS → Virgilio.** Cómo devuelve ISIS el número de NP cuando el
   pedido nace del otro lado.
2. **P4 — Recepción de mercadería (remitos de compra).** Requiere definir el mapeo de
   códigos de proveedor/artículo entre los dos sistemas.
3. **Cutover de la emisión.** Hoy Producción Virgilio emite Factura A por punto de
   venta 11. Cuando ISIS empiece a facturar estos pedidos, hay que **apagar la emisión
   propia el mismo día** para no pedir dos CAE por la misma venta. Definir fecha y
   si el PV 11 queda de respaldo.

---

## Anexo técnico (interno, no se envía a ISIS)

- Edge Function: `supabase/functions/isis-api/index.ts` (proyecto `hrxfctzncixxqmpfhskv`,
  `verify_jwt = off` — la función valida su propio token).
- DDL, RPCs y triggers: `sql/isis_api.sql`.
- Tablas: `isis_export_pedidos` (cola), `isis_api_tokens` (hashes), `isis_api_log` (traza).
  Las tres con RLS activa y sin policies → la anon key **no** las ve. Las RPC son
  `SECURITY DEFINER` con `EXECUTE` sólo para `service_role`.
- Disparador: trigger `trg_isis_encolar_facturado` (AFTER INSERT en `Facturacion_NP`).
  El de baja es `trg_isis_anular_facturado` (AFTER DELETE). Los dos son a prueba de
  fallas: si la integración se rompe, **no** rompen el tick de facturación.
- Alta de un token nuevo:
  ```sql
  -- token en claro generado afuera; en la base va sólo el sha256
  INSERT INTO public.isis_api_tokens (nombre, token_hash, nota)
  VALUES ('Sistemas ISIS - producción', '<sha256 hex>', 'Ticket 1159666');
  ```
  Baja: `UPDATE public.isis_api_tokens SET activo = false WHERE nombre = '...';`
- Las NP facturadas **antes** de encender la integración no están en la cola (la tabla
  arrancó vacía a propósito) — ISIS no las va a ver.
