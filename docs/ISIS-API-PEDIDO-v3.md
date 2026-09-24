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

## El circuito que se busca (Luis, 24/09)

| | hoy | con la API |
|---|---|---|
| 1 | en Gestión, módulo Facturación, se genera y se descarga el Excel | se aprieta **Facturar** en Gestión y el pedido sale solo |
| 2 | en ISIS se importa ese Excel (importación de pedidos) | el pedido entra solo a ISIS |
| 3 | se factura en ISIS | se factura en ISIS |

⚠ **El dictamen de ISIS no da el paso 2 entero:** dice que *"la generación del pedido … será
responsabilidad de un operador y mediante acción manual"*. Tal como lo ofrecen, el pedido llega
solo a una tabla transitoria de ISIS, pero alguien tiene que darlo de alta ahí. Se elimina la
descarga y el importado del archivo; el alta queda como un paso manual dentro de ISIS. Si se
quiere que entre dado de alta sin intervención, hay que pedirlo explícito en la Orden de
Magnitud.

Del lado de Gestión el disparador **ya existe**: `trg_isis_encolar_facturado` (INSERT en
`Facturacion_NP` → encola en `isis_export_pedidos`; DELETE → anula). Está activo.

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

## Lo único que hay que definir con ISIS: DOS bases (Luis, 24/09)

El formato **no se valida**: es el del importador que ya usan (el reporte que mandaban por mail
las páginas LK y Chef, y que hoy arma nuestro circuito de facturación). Lo que queda abierto es
el **ruteo**: unos pedidos se procesan en la base de **Loekemeyer** y otros en la de **Chef**.
Cada pedido lleva `empresa_isis` y el código de cliente **de esa base** — incluido el caso de
un pedido tomado en la página LK que se factura en Chef (Tierra del Fuego) con el código de
Chef. Con ISIS se define si toman un proceso por base (`GET /pedidos?empresa=LK|CH`, ya
soportado) o uno solo que enrute.

La facturación directa (punto 2 del mail) **no se descarta ni se pide** en la respuesta.

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

**No se construye antes de que ISIS defina el ruteo LK/CH.**
