# Pedido web → ISIS por API — definición de datos v3 (para validar con ISIS)

**Origen:** mail de Horacio (Sistemas ISIS), 17/09/2026, *"Integración de pedidos y facturación
mediante API"*. Dictamen de programación:

1. **Importación de pedidos por API: viable.** Entra a una tabla transitoria, se valida y se
   procesa con el circuito estándar. Alta del pedido, remito y factura: **un operador, a mano**.
2. **Importación directa de facturas: otro proyecto**, más caro, y el punto crítico es la
   relación pedido ↔ factura.
3. **Antes de presupuestar** hay que *"revisar, definir y validar los datos"*: el body de ejemplo
   que recibieron (el sobre v2.0, `docs/ISIS-API-ESPECIFICACION.md` §6) *"no resulta directamente
   compatible con las estructuras y procesos estándar de ISIS"*.

Este archivo es la respuesta al punto 3.

## Decisión: el JSON es el Excel que ISIS ya importa, columna por columna

Hoy Facturación baja un `.xls` (`_facXlsArmar` → `_facXlsFilasPlanas` → `_facXlsXml`, index.html)
y **ISIS lo levanta con su importador de pedidos estándar**. Ese formato ya está validado en
producción todos los días. Horacio pide *"un esquema similar al importador de pedidos"*: entonces
el JSON **no inventa campos**, repite las 12 columnas del Excel.

Se descarta el sobre v2.0 como cuerpo: tenía campos que ISIS no maneja (`source`, `control`,
`payment_term`, `condicion_pago` en texto, `estado_integracion`) y le faltaban los que el
importador sí usa (`uni`, tramo, leyenda del 2 %).

### Y la facturación directa (punto 2) NO hace falta

El pedido se publica **después del armado**, con las cajas y los códigos **realmente
preparados**. O sea: lo que ISIS da de alta ya es lo que se va a facturar, y entre el pedido y la
factura no queda nada que pueda cambiar. El riesgo que marca Horacio (*"modificaciones en
cantidades, ítems, precios… entre la generación del pedido y la facturación"*) no existe en este
circuito. **Se pide sólo el proyecto 1.**

## Estructura

Un documento por pedido (referencia nuestra). Las líneas llevan el **tramo** (`n_pedido`): ISIS
corta los pedidos de a **18 líneas en Loekemeyer y 15 en Chef**, en orden de código, igual que
hoy en el Excel.

```json
{
  "referencia": "LK 0183",
  "empresa_isis": "LK",
  "fecha": "24/09/2026",
  "cod_cliente": "288",
  "vend": "7",
  "sucursal": "Rivadavia 3663 - Mar Del Plata",
  "cond_pago": "8",
  "pct_dto": "2% Descuento Web",
  "num_oc": "",
  "leyenda2": "LK 0183",
  "lineas": [
    { "n_pedido": 1, "articulo": "321",  "cajas": 6, "uni": 72 },
    { "n_pedido": 1, "articulo": "505L", "cajas": 2, "uni": 48 }
  ]
}
```

| JSON | col. Excel | qué es | de dónde sale hoy |
|---|---|---|---|
| `empresa_isis` | (archivo) | a qué ISIS va: `LK` o `CH` | prefijo de la NP; **Tierra del Fuego LK → `CH`** (v13.77) |
| `fecha` | A | fecha de importación, `dd/mm/aaaa` | día de la publicación |
| `n_pedido` | B | tramo de 18 (LK) / 15 (CH) líneas | `_facXlsTope` |
| `cod_cliente` | C | código de cliente **en el ISIS de destino** | NP; TdF → `GV_Cliente_Isis.cod_isis` |
| `vend` | D | código de vendedor | LK: `clientes_vendedor`; Chef: pedido de Chef (`sheets_payload.vend`) |
| `articulo` | E | código **armado**, 3 dígitos con ceros + letras, **con la L** si la lleva | `Entregas_Virgilio` + `_facXlsPadCod` |
| `cajas` | F | cajas armadas (topeadas a lo pedido) | `Entregas_Virgilio` |
| `uni` | G | `cajas × uxb` | `vista_uxb_articulo` |
| `sucursal` | H | domicilio de entrega, **en texto** | `lk_pedidos_match.sucursal_entrega` |
| `leyenda2` | I | **propuesta:** la referencia nuestra | hoy vacía |
| `cond_pago` | J | **código** de condición de pago | `v_pedidos_web_np.condicion_pago_code` (LK) / RPC Chef |
| `pct_dto` | K | `"2% Descuento Web"` si `cond_pago` ∈ 8–13, 18; si no, vacío | regla v14.57 |
| `num_oc` | L | OC del súper (vacío para clientes) | — |

## Lo que ISIS tiene que validar (las preguntas del mail de respuesta)

1. **Sucursal:** ¿el importador la toma en texto (como el Excel) o necesita el **código de
   sucursal** del cliente en ISIS?
2. **Tramos:** ¿cortamos nosotros de a 18/15 (`n_pedido`) o lo corta el proceso de ISIS al
   importar?
3. **`leyenda2` = referencia:** si ISIS la conserva en el pedido y la factura, el vínculo
   pedido ↔ factura queda directo y dejamos de depender del cruce por fecha y cajas.
4. **`cond_pago`:** confirmar que el código que manda la página es el de su tabla de
   condiciones (hoy entra así en la columna J).
5. **Unidades:** ¿usan `uni` o recalculan desde `cajas` con su UxB?
6. **Mecánica:** ellos consultan (`GET` desde su servidor, el esquema de las 3 URL que ya
   probaron). No hace falta IP pública ni puertos de nuestro lado.

## Lo que falta de nuestro lado (después de que ISIS valide)

La Edge Function `isis-api` y `gv_isis_pedido_json` siguen sirviendo el sobre v2.0, con
`vend` / `condicion_pago` / `sucursal_entrega` en **NULL** (Fase 1). Para servir la v3 hay que
llevar al servidor lo que hoy arma el navegador en `_facXlsArmar`:

| dato | hoy | falta |
|---|---|---|
| `cond_pago` (código) | sólo en LK (`v_pedidos_web_np`) y RPC de Chef | traerlo a Virgilio (FDW o sync, como `lk_pedidos_match`); `lk_pedidos_match.metodo_pago` tiene sólo el **texto** |
| `vend` de Chef | RPC `gv_pedidos_web_np_chef_admin` | mismo sync |
| `sucursal` | `lk_pedidos_match` (ya en Virgilio) | usar `order_id` exacto, no el match por fecha ±3 |
| cola | `isis_export_pedidos`: 226 pendientes, **106 web** (24/09) | sacar clientes de prueba (v21.63) y cambiar el disparador al cierre del armado |

**No se construye antes de la validación:** si ISIS pide código de sucursal o corta los tramos
ellos, cambia la función. Se escribe una vez.
