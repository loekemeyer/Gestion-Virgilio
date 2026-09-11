# Plan de acción — Badge "Cliente NUEVO" en Facturación (idea 9793)

> Estado: **PLAN, no implementado.** Pedido del dueño (2026-09-10): dejar el plan y no
> tocar nada hasta OK. El badge de arranque es **sólo estético**, pero la lógica de
> "¿es nuevo?" va a servir para más cosas después, así que se define bien de una vez.
>
> ⚠ Protocolo del repo: la determinación "¿el cliente es NUEVO?" es **lógica de negocio**
> → va en el **backend** (RPC de Supabase), el front sólo pinta. Antes de implementar hay
> que confirmar con el dueño la fuente de "pagado" (ver Hueco A).

## 1. La regla (textual del dueño)

Un cliente es **NUEVO** si cumple **las dos** condiciones:

- **(a) Código alto:** `cod_cliente >= 3800` en **LK**  **o**  `cod_cliente >= 2300` en **CH**.
- **(b) Poca historia:** tiene **menos de 3 pedidos pagados y entregados** en toda su historia.

Y la parte difícil: **(b) se cuenta sobre el CLIENTE REAL, no sobre el código**. Hay que unir:

- **Cambió de razón social** (mismo cliente, otro código, misma empresa) → sumar la historia de los dos.
- **Cambió de empresa** (le compraba a LK y ahora a CH, o al revés) → sumar la historia cruzada.

Si sumando todo ya tiene ≥ 3 pedidos pagados+entregados, **NO es nuevo**, aunque el código sea alto.

## 2. Dónde vive cada dato (verificado 2026-09-10)

| Dato | Dónde | Notas |
|---|---|---|
| NP → empresa (lk/chef) | Gestión (`_facXlsEmpresa(np)` en `index.html`, prefijo de la etiqueta `LK`/`CH`) | La NP web ya nace con empresa; las de ISIS por rango. |
| Cód. de cliente de la NP | Gestión, en la fila de `facRender` (`f.cod`) | Es el código del ERP de esa empresa. |
| Identidad cruzada (mismo cliente, distinto código / distinta empresa) | **LK** (`kwkclwhmoygunqmlegrg`): `customer_grupos` (misma empresa, por razón social), `clientes_lk_ch_links` (cruce LK↔CH a mano), y el cruce **por CUIT** (`chef_padron`, `customers.cuit`, `Wpp_Clientes`) | Es exactamente el motor de "Clientes vinculados / agrupados" que ya existe en el admin LK. **No reinventarlo**: reusarlo. |
| Pedidos **entregados** | Gestión: control de remito (CRN / `gv_ppp_en_salida` → entregado) y el histórico `PPP_Entregados_Meta`; ERP: `sales_lines` (facturado) | "Entregado" en Gestión = remito controlado. |
| Pedidos **pagados** | ⚠ **NO está en Gestión.** En LK está la **deuda** (cobranzas / `deudores`) pero no un "este pedido está pagado" pedido-por-pedido. | Ver **Hueco A**. |

## 3. Huecos a resolver con el dueño ANTES de implementar

- **Hueco A — "pagado":** no existe hoy una marca por pedido de "pagado". Opciones a confirmar:
  1. **Aproximar** "pagado y entregado" por "**facturado** (existe en `sales_lines` / ISIS) **y entregado** (remito controlado)", ignorando si la cobranza entró. Es lo más simple y probablemente suficiente para un badge estético.
  2. Contar **facturas cobradas** desde cobranzas del ERP (más fiel, pero hay que traer ese dato; hoy sólo tenemos *saldo* de deuda, no el detalle cobrado por comprobante).
  → **Recomendado para v1:** opción 1 (facturado + entregado), y dejar anotado que "pagado" es una aproximación.
- **Hueco B — "pedido":** ¿un "pedido" = una NP? ¿o un pedido de la página que puede abrir varias NP (bloques)? Para contar "menos de 3", conviene contar **NP facturadas+entregadas** (es lo que se ve y lo que hay). Confirmar.
- **Hueco C — umbral de código:** confirmar que 3800 (LK) / 2300 (CH) es sobre el código **crudo** de esa empresa (no el vigente del grupo). El dueño lo dio así; se respeta.

## 4. Arquitectura propuesta (backend manda, front pinta)

### 4.1 Motor de identidad + conteo — en LK (donde ya viven los vínculos)

Crear en **LK** una RPC nueva (prefijo propio), p. ej. `gv_cliente_nuevo_lote(p_pedidos jsonb)`:

- Entrada: lista de `{empresa, cod}` (los de la pantalla de Facturación, ~25-50 por hoja).
- Para cada `(empresa, cod)`:
  1. **Resolver el cliente real**: expandir por `customer_grupos` (misma empresa) + `clientes_lk_ch_links` + **CUIT** (LK `customers.cuit` / `Wpp_Clientes`, CH `chef_padron.cuit`) → conjunto de `(empresa, cod)` que son la misma persona.
  2. **Contar** NP **facturadas + entregadas** de TODO ese conjunto (Hueco A/B) en las dos empresas.
  3. Devolver `{empresa, cod, es_nuevo: (cod_alto AND conteo < 3), cod_alto, conteo}`.
- Reusa el patrón de `get_clientes_lk_ch` / `datos_cliente_empresa` (ya expanden grupos de los dos lados). **No** llamar al FDW de Chef en el camino caliente (usar `chef_padron`).
- `SECURITY DEFINER` + chequeo de admin adentro, o revocar `anon` (mismo criterio que el resto del admin LK).

### 4.2 Cómo lo consume Gestión (Virgilio)

Virgilio **ya tiene FDW a LK** (rol `lk_ppp_reader`, esquema `virgilio`/`ppp_*`, ver §pipeline). Dos caminos:

- **(preferido) Empuje/espejo**: un cron en LK calcula `es_nuevo` por código y lo espeja a una tabla `gv_clientes_nuevos` en Virgilio (mismo patrón que `lk_pedidos_match` / `sync_pedidos_match_virgilio`). Gestión lee una tabla local (cero FDW caliente). Se refresca 1×/día — alcanza para un badge.
- **(alternativa) On-demand**: Gestión llama por FDW a la RPC de LK al abrir Facturación. Más simple de arrancar, pero mete al FDW en el camino de render (evitar si son muchas filas).

### 4.3 Front (Gestión, `index.html`, módulo `fac*`)

- En `facRender`, al armar las filas, cruzar cada `np` contra el resultado del backend (`_facEsNuevo(empresa, cod)`), cacheado por lote (como `_facNeto` / `_facLios`).
- Pintar un **badge claro y notorio** en la celda de razón social (`.fac-rs-cell`), p. ej. `🆕 CLIENTE NUEVO`, con color fuerte (verde/naranja) y `title` que explique el criterio (código alto + < 3 pedidos pagados/entregados).
- Espejar el cambio a `Gestion-Virgilio/admin/` **no** aplica (esto es Gestión, no el admin LK).
- **Sólo estético por ahora**: el badge no cambia ningún flujo. La lógica queda lista para reusar (alertas, prioridad de atención, etc.).

## 5. Pasos concretos cuando el dueño dé OK

1. Confirmar Huecos A/B/C.
2. LK: escribir `gv_cliente_nuevo_lote` (identidad + conteo), verificar contra casos testigo (un cliente que cambió de razón social y ya superó 3; uno que pasó de LK a CH; un código 3800+ realmente nuevo).
3. Elegir espejo vs on-demand (recomendado espejo + cron).
4. Virgilio: tabla/lectura local + `_facEsNuevo` + badge en `facRender`.
5. Bump de versión, smoke test, doc en `docs/SUPABASE-GESTION-VIRGILIO.md`.

## 6. Casos testigo para validar (del propio padrón)

- Código **alto + poca historia** → NUEVO (ej. un `4xxx` LK reciente con 1-2 NP).
- Código alto pero **mismo CUIT** que un código viejo con mucha historia → **NO** nuevo (la unión por CUIT lo saca).
- Cliente que **cambió de razón social** (dos códigos LK, mismo grupo en `customer_grupos`) y juntos ya tienen ≥ 3 → **NO** nuevo.
- Cliente que pasó de **LK a CH** (vínculo en `clientes_lk_ch_links` o mismo CUIT) con ≥ 3 entre las dos → **NO** nuevo.
