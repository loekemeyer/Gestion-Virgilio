# Handoff — Submódulo "Clientes nuevos" (Gestión Virgilio)

**Fecha:** 2026-09-16 (actualizado 2026-09-17, v19.37) · **Pedido de:** Luis · **Estado:** vivo en
`main`, testeado y pusheado.

> ⚠ **v19.37 (Luis, 17/09): NO hay seña del 30%.** El cliente nuevo paga el **TOTAL del pedido con
> IVA** (la factura simulada) **antes del armado y la entrega**. El Speech 1 manda ese monto y la
> columna Monto lo muestra como `c/IVA $…` debajo del neto. Todo lo que este archivo diga sobre
> una seña del 30 % quedó derogado. Detalle en `docs/SUPABASE-GESTION-VIRGILIO.md` §3.iv.
**Repo:** `loekemeyer/Gestion-Virgilio` (GitHub Pages sirve `main`). Rama de trabajo de esa sesión:
`claude/keen-galileo-yb906o` (se mergeó a `main`).
**Supabase:** proyecto `hrxfctzncixxqmpfhskv` (compartido; leer las reglas del `CLAUDE.md` antes de
tocar `public.*`).

## Qué es

Se partió el submódulo **Cuarentena** (dentro de "A Programar" / PPP) en dos secciones **apiladas
y colapsables**:

1. **🚧 Cuarentena** — deuda / suspendido / excede crédito.
2. **🆕 Clientes nuevos** — pedidos cuyo **único** motivo es `cliente_nuevo`. Si además tiene otro
   motivo (ej. deuda) → queda en Cuarentena (caso testigo: Zhang Qikuan).

El corte NO tocó el candado `aprEnCuarentena` (los dos siguen retenidos, no se programan solos).
La marca `cliente_nuevo` es la de la v17.12 (`GV_Clientes_Nuevos`, la calcula LK, cron
`sync-clientes-nuevos-virgilio`).

## Front (`index.html`) — funciones clave

- `aprSoloClienteNuevo(p)` — el corte entre las dos secciones (motivos == solo `cliente_nuevo`).
- `aprColCuarentena()` — filtra `!aprSoloClienteNuevo`; colapsable (`aprCuarColapsar`,
  `localStorage vir_cuar_colapsado`).
- `clinNuevosHtml()` — la sección Clientes nuevos; se arma en `aprRender()`
  (`aprColPedidos()+aprColCuarentena()+clinNuevosHtml()`). Colapsable (`aprCliColapsar`,
  `vir_cli_colapsado`). Las dos arrancan **expandidas** por defecto.
- Columnas: Pedido · Fecha · m³ · Cliente · Zona · **1er contacto** · **Contacto (Speech 1/2)** ·
  **Monto** · **Acción** · **Coment.** (v19.90). El 📖 es el MISMO log que Cuarentena
  (`cuarComBtnHtml` / `cuarComAbrirPed` → `GV_Cuarentena_Comentarios`, clave empresa + order_id),
  así lo que se escribe acá se lee después desde el log de 🚧 Config. Cuarentena. El contador de
  cada 📖 lo pide `cuarComNeed()`, que ahora sirve a los dos submódulos (antes colgaba de la
  lista de Cuarentena: si el único retenido era un cliente nuevo, no se pedía nunca).
- `clinSpeech1` / `clinSpeech2`, `clinContactoBtns`, `clinAccionBtns`,
  `clinTiempoHtml` / `clinFmtElapsed` / `clinTickStart` (timer, refresco 60 s),
  `clinSpeechMsg1` / `clinSpeechMsg2` (mensajes WhatsApp), `clinAbrirWa` (usa `_avpWa`).
- `clinNuevosValorFmt` (monto neto), loaders `clinNuevosValorCargar` / `clinContactoCargar` /
  `clinWppCargar`.
- **Eliminar** reusa `aprAnularAbrir` → `gv_pedido_anular`. **Aprobar** reusa `cuarLiberar` →
  `gv_cuarentena_liberar`; el liberado con motivo `cliente_nuevo` muestra el badge
  "🗓️ Programar dentro de los próximos 7 días" (en `aprColPedidos`, cerca de `cuar-liberado-nota`).
- Fila de ejemplo: `clinDemoPedido` / `clinDemoRowHtml` / `clinDemoToggle` (`_apr.cliDemo`).
- Estado nuevo en `_apr`: `cliValor`, `cliContacto`, `cliWpp` (+ sus `*Loading`). Se resetean en
  `cuarMarcarPedidos()`.

## Backend (Supabase, aplicado)

Archivos: `sql/gv_clientes_nuevos_acciones_v1905.sql` + `sql/gv_clientes_nuevos_valor_lote_v1895.sql`
(el nombre `_v1905`/`_v1895` es de cuando la sesión iba por esos números; el bump final fue v19.08
por colisión con otra sesión — el contenido es el mismo).

- **Tabla** `public."GV_Clientes_Nuevos_Contacto"` (empresa, order_id, primer_contacto_at, por,
  updated_at). RLS on, sin policies (sólo RPC SECURITY DEFINER la tocan; anon SIN acceso).
- `gv_cliente_nuevo_contacto_marcar(empresa, order_id, por)` — sella el 1er contacto (idempotente
  `on conflict do nothing`), devuelve el `timestamptz`.
- `gv_cliente_nuevo_contacto_lote(pedidos jsonb)` — lee los timers de un lote.
- `gv_cliente_nuevo_wpp_lote(pedidos jsonb)` — teléfono del **cliente** desde `whatsapp_clientes`
  (NO el del vendedor, a diferencia de `gv_cuar_contacto_lote`).
- `gv_clientes_nuevos_valor_lote(pedidos jsonb)` →
  `order_id, empresa, valor (neto con descuentos), valor_con_iva (= valor × 1,21)`.
- Todas SECURITY DEFINER, gate `es_supervisor_virgilio() OR gv_es_supervisor_o_servicio()`,
  EXECUTE revocado a `anon`. Rollback documentado al pie de cada `.sql`.

## Tests

`tests/apr-cuarentena.cjs` cubre: el split, el badge en Cuarentena, la sección Clientes nuevos,
las columnas 1er contacto/Acción, Speech 1/2, Aprobar/Eliminar, la fila de ejemplo y el colapso.
`tests/checkhtml.cjs` + `tests/smoke.cjs` verdes. Correr `bash tests/run.sh` para la suite entera.

## Supuestos / limitaciones (VERIFICAR con Luis)

1. **IVA 21 % plano** — `precios_venta` / `precios_venta_chef` no guardan tasa por artículo
   (cols: cod, precio_unit, descripcion, actualizado). Correcto para bazar/menaje; si aparecen
   artículos a 10,5 % hay que traer la tasa por artículo y cambiarlo en `gv_clientes_nuevos_valor_lote`.
2. **Teléfono del cliente:** sólo **184 / 367** clientes nuevos lo tienen en `whatsapp_clientes`
   (medido 2026-09-16). Sin teléfono, Speech 1 igual sella el timer pero no abre WhatsApp; Speech 2
   queda desactivado.
3. **Eliminar / Aprobar** usan los cuadros que ya existían (piden quién lo hace y, en Eliminar, el
   motivo obligatorio). No es un clic seco: queda registrado quién y por qué.

## Pendientes / decisiones abiertas (Luis las dejó sin responder)

1. ¿**Eliminar** dispara además un **reembolso / aviso** de lo ya pagado (desde la v19.37 el
   cliente nuevo paga el **total**, no una seña), o por ahora sólo saca de la PPP y registra? —
   mencionado en el primer pedido, NO implementado.
2. ¿Traer el teléfono del **pedido web** (de la página) para cubrir a los 183 clientes nuevos que
   no están en `whatsapp_clientes`?
3. Monto de un cliente nuevo que entre por **ISIS**: hoy "—" (se valoriza por NP aparte).
4. Fase 2 mencionada antes: **reembolso de lo no entregado** al facturar (no empezado).

## Reglas del repo a respetar

- Bump SIEMPRE con `node scripts/bump-version.cjs <ver>` (mueve los 4 lugares); trabajar y pushear a
  `main`. Otra sesión pushea en paralelo → `git fetch origin main` + merge + re-bump por encima
  (hubo varias colisiones de número el 2026-09-16).
- Cada pedido de trabajo = una tarea en Planify (Luis = employee_id 52, schema `planify`). La tarea
  de esto quedó **cerrada** (`done=true`, id 3567).
- Backend: lógica de negocio en Supabase, **aditivo** sobre objetos compartidos, RLS on en toda
  tabla nueva, backups antes de tocar datos.
- Referencia detallada del cambio: `docs/SUPABASE-GESTION-VIRGILIO.md` §3.im.
