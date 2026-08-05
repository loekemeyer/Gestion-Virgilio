# Cruce de Órdenes de Compra: Producción Virgilio ↔ ISIS

Snapshot: **2026-08-05**. Idea del usuario **5795**. Estado: **diseño / bloqueado**
esperando definir cómo exporta ISIS sus OCs.

> ⚠ No confundir con `docs/integracion-isis.md`, que es el circuito de **facturación**
> (ventas → ISIS). Este documento es el de **compras** (Órdenes de Compra a
> proveedores/talleristas).

## Objetivo del usuario

Poder **cruzar** las OCs generadas en Producción Virgilio con las generadas por ISIS.
El usuario marcó **los tres** objetivos:

1. **Auditar diferencias** — detectar dónde no coinciden (cantidades, OCs que están en
   un sistema y no en el otro).
2. **Evitar doble pedido** — que no se pida dos veces lo mismo.
3. **Validar el generador automático** — chequear que lo que Virgilio sugiere comprar
   coincide con lo que efectivamente se pidió/cargó en ISIS.

**Norte (dirección a futuro):** que la OC **nazca en Producción Virgilio** y ISIS la
**refleje** — no que cada sistema genere la suya por separado. En la transición hay que
convivir con las dos fuentes, y ahí el cruce sirve para auditar.

## Lo que hay hoy (estado real, para no inventar)

- **Virgilio** — OCs en la tabla `Ordenes_Compra`. Se identifican sólo por `id` interno
  (bigint) + `proveedor` + `codigo` + `fecha` + `cantidad`. **No hay número de OC propio
  ni ningún campo que enganche con ISIS.** Para imprimir se agrupan por `proveedor`+`fecha`
  (`ocGroups`). El origen queda en `notas` (`auto <fecha>` = generador automático de los
  miércoles; vacío/otro = carga manual). Columnas del impreso ya guardadas al generar:
  `oc_max`, `oc_pedidos`, `oc_stock`, `oc_uni_caja`, `oc_ncaja` (v7.39–v7.42).
- **ISIS** — on-premise: ni el sandbox ni la app cloud lo ven directo. El puente probado
  es el **`agente-local`** (corre en el desktop del dueño): vigila carpetas donde ISIS
  deja PDFs (`PDF_ISIS` / `PDF_ISISCHEF`), **ya parsea comprobantes de tipo `compra`**
  (proveedor, número, fecha, ítems código+cajas+importe, normaliza códigos) y los sube a
  Supabase con dedup por `huella` (`division|tipo|numero`). Ver `agente-local/README.md` y
  `sql/nc_devoluciones.sql`.
- La API de ISIS documentada (`/api/ISISPedido`) es de **pedidos de venta**, no de
  compras. Para OCs no hay API conocida → el canal realista es **export de archivo/PDF →
  agente local → Supabase** (mismo patrón que las NC).

## El nudo real: no hay clave común

Ni Virgilio ni ISIS comparten un identificador de OC. Hay que **elegir la clave de
cruce**. Tres caminos:

- **A — Clave natural difusa** (no se toca ISIS): cruzar por `proveedor` (normalizado) +
  `código` (ya existe `_ocgNorm` = upper + trim + sin ceros a la izquierda) + `fecha`
  (dentro de una ventana ±N días) + `cantidad`. Rápido, no depende de ISIS más allá de un
  export. **Contra:** frágil si los nombres de proveedor no mapean 1-a-1, las fechas
  difieren o las cantidades se ajustan.
- **B — Guardar el nº de OC de ISIS en Virgilio** (campo nuevo `nro_isis` en
  `Ordenes_Compra`): cruce exacto 1-a-1. Requiere **capturar** ese número (del export o
  vinculando a mano en la pantalla de conciliación).
- **C — Empujar la OC de Virgilio a ISIS** (que ISIS lleve una referencia de Virgilio):
  requiere que ISIS **acepte** el dato en compras → hoy **no documentado**.

**Recomendación: B apoyado en A.** El cruce difuso (A) arma los candidatos; al confirmar
un match se fija `nro_isis` (B) → de ahí en más es exacto y deja de depender de la
heurística. Coherente con el norte "la OC nace en Virgilio": cuando se dé ese paso, el
`nro_isis` es simplemente el número que ISIS le asigna al reflejarla.

## Arquitectura propuesta

1. **Ingesta de las OCs de ISIS a Supabase** reusando el patrón del agente local:
   ISIS exporta sus OCs (idealmente CSV/Excel; si sólo hay PDF, se parsea como las NC) a
   una carpeta vigilada → agente → tabla staging **`ISIS_Ordenes_Compra`** (cabecera) +
   **`ISIS_Ordenes_Compra_Items`** (líneas), dedup por el nº de OC de ISIS.
2. **Vista de conciliación** (`vista_cruce_oc_isis`) que cruza `Ordenes_Compra` con el
   staging y devuelve 3 baldes: **sólo-Virgilio**, **sólo-ISIS**, **en-ambas** (con delta
   de cantidad).
3. **Pantalla en "📑 Compras (OCs)"** (tab ya existente): sub-tab **"Conciliación ISIS"**
   con los 3 baldes + botón **"vincular"** que, al confirmar un match, escribe `nro_isis`
   en la OC de Virgilio.

## Qué se puede construir YA vs qué está bloqueado

- **Bloqueado hasta saber el export de ISIS:** la ingesta (paso 1) — no sabemos si es
  CSV, Excel, PDF o API, y eso define el agente. Sin datos de ISIS en Supabase no hay
  contra qué cruzar ni cómo testear la vista.
- **Se puede adelantar sin ISIS (bajo switch, sin romper nada):** el campo `nro_isis` en
  `Ordenes_Compra` (nullable) y el esqueleto del sub-tab de conciliación. Pero conviene
  **no** hacerlo hasta cerrar el export, para diseñar la vista contra la estructura real
  y no a ciegas.

**Decisión: esperar la respuesta del proveedor de ISIS antes de codear.** (El proyecto ya
tiene el hábito de mandarle preguntas estructuradas al proveedor — ver
`integracion-isis.md`.)

## Preguntas para el proveedor de Sistemas ISIS

1. ¿ISIS puede **exportar sus Órdenes de Compra a archivo** (CSV / Excel / TXT)? ¿Qué
   estructura de campos (nº de OC, fecha, proveedor —código y nombre—, artículo, cantidad,
   unidad, importe)?
2. Si no hay export de datos, ¿el **impreso PDF** de la OC tiene un layout estable que se
   pueda parsear (como ya hacemos con las Notas de Crédito)?
3. ¿Hay **API / web service** para **consultar** las OCs de compra (no sólo pedidos de
   venta)? URL, auth, payload.
4. ¿Cada OC tiene un **número único estable** que sirva como clave de cruce, y se mantiene
   si la OC se edita?
5. Los **códigos de artículo** y los **nombres/códigos de proveedor**, ¿son los mismos que
   usa Virgilio o hay que mapear?

## Próximo paso

Conseguir del proveedor **cómo salen las OCs de ISIS** (pregunta 1–3). Con eso se define
el agente de ingesta y recién ahí se construye la vista + la pantalla de conciliación.
Idea registrada como **5795** (`agente_propuestas` + `docs/IDEAS-USUARIO.md`).
