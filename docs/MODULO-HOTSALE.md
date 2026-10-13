# Hot Sale — rentabilidad ponderada (hotsale.js)

> Movido de `CLAUDE.md` el 2026-10-13 (poda de reglas, pedido de Luis) para que no cargue en cada sesión.
> Es documentación operativa VIVA del módulo, no se resume: leer ENTERA antes de tocar este módulo.

## ⚠ REGLA (Thomas, 2026-10-01, v25.91 · v25.93 · v25.98): HOT SALE — la rentabilidad ponderada vive en `hotsale.js`

Los súper piden un **aporte de hot sale** (un % sobre el precio) dos o tres veces al año. El módulo
**🏷️ Hot Sale — rent. ponderada** (botones secundarios del panel supervisor, `openHotSale()`) pide los
datos de arriba de la planilla de Thomas —**HotSale %**, **Semanas HotSale**, **Rent c/AP** (nacionales),
**Rent Pta Pta** (importados, sin hot sale), **Semanas a Ponderar** y **cuánto más se vende** en hot
sale— y devuelve el % que queda en el período, **por separado para importados y nacionales**.

- **Las dos rentabilidades las carga él**; Gestión no las calcula (*"en función de mi markup sé cuál es
  mi costo: 100 % punta a punta = recibo 1.000, me cuesta 500"*). **Pueden ser negativas** (ítem real:
  recibo 922, costo 986 = −6,49 %).
- **Se pondera por unidades, no por semanas**: rent. en hot sale = (1 + rent) × (1 − aporte) − 1 y
  ponderada = (N·rent + H·k·rentHS) ÷ (N + H·k). El costo unitario se cancela, por eso no se pide.
  Verificado contra su planilla: 100 % / 20 % / 4 sem / 2 HS / ×2 → **73,33 %**; el ítem real a 12
  semanas → **−11,83 %** (él redondea −12 %).
- **Los porcentajes van SIN decimales** (Thomas, 01/10: *"no quiero decimales en los porcentuales"*): 73 %, −12 %.
- **v25.93 — segundo modo, POR SÚPER, ÍTEM POR ÍTEM** (Thomas: *"dejame cargar rent promedio … o item por item que le
  vendo a cada super … ordenado por la última fecha de compra (dd/mm/yy) … ver la rent promedio por fam y por rubro"*).
  Elige el súper (`GV_Supers` por `super_key`: Carrefour es UNO aunque tenga código en LK y en Chef), la pantalla trae
  lo que ese súper compró en **12 meses** (facturas de ISIS, `isis_lk` + `isis_ch`) ordenado por última compra, él
  tipea la rent. de cada ítem y sale el **promedio por familia** (importado = está en `Importados`; el resto nacional)
  **y por rubro** (`GV_Producto_Tipo.familia`; sin fila = «Sin rubro»), cada uno con su rent. en hot sale y su
  ponderada. **El promedio va ponderado por cajas vendidas** en esos 12 meses (si ningún ítem cargado tiene cajas,
  simple); los ítems sin rent. cargada no entran y la fila dice «cargados / total». Las rent. quedan en `localStorage`
  por súper. RPC nuevas, sólo lectura, SECURITY DEFINER con guard de supervisor: `gv_hotsale_supers()` y
  `gv_hotsale_items_super(p_super_key, p_meses)` (`sql/gv_hotsale_super_items_v2593.sql`). ⚠ Sin sesión de supervisor
  devuelven **0 filas, no error**: la pantalla lo dice (*"hace falta la sesión de supervisor"*), no dibuja una lista vacía.
- El bloque de datos va **al ancho del dato** (máx. 470 px, dos filas de tres): Thomas, *"está muy ancho lo de arriba"*.
- No escribe la base: los datos quedan en `localStorage` del navegador. `hotsale.js` está en
  `SIGUEN_APP_VERSION` (bump y `tests/version-tokens.cjs`). Candado: `tests/hotsale-rent.cjs`.
- **v25.98 (Thomas): lo importado por TIERRA NATIVA o CHEF no puede quedar a pérdida en LK.** Se registra UNA
  vez el **u$s por unidad** que el importador le cobra a LK (`GV_Importado_Precio_LK`, por código base, vale para
  todos los súpers; `gv_hotsale_precio_lk_guardar`) y el **dólar** (`GV_HotSale_Param` clave `dolar`,
  `gv_hotsale_param_guardar`; se lee con `gv_hotsale_params()`). **Rent. LK hoy = (lo que LK le factura al súper,
  $/u de la última factura de ISIS) ÷ (u$s × dólar) − 1**, y con eso la rent. LK en las semanas de hot sale y la
  ponderada, por ítem (⚠ en lo que queda a pérdida) y por importador en el resumen (ponderado por cajas, con cuántos
  ítems quedan a pérdida hoy / en HS / pond.). Para lo de **Chef** hay referencia: la última factura Chef → LK
  (`isis_ch`, cliente 1434 = Loekemeyer Hnos; el parser la marca «Pesos» pero el precio unitario es u$s) viene como
  `ref_chef_usd` y el botón «usar» la carga; para **Tierra Nativa** no hay fuente parseada: se tipea. El u$s y el
  dólar viven en la **base** (son de todos); las rent. tipeadas siguen en `localStorage`. `gv_hotsale_items_super`
  suma 8 columnas al final (`importador`, `precio_usd_lk`, `precio_usd_nota`, `venta_unit`, `venta_fecha`, `uxb`,
  `ref_chef_usd`, `ref_chef_fecha`). ⚠ **El `drop function` se cuelga en el MCP** (3 veces, 60 s, sin lock ni
  timeout de Postgres): la función nueva se creó con otro nombre y se **renombró**; la vieja quedó como
  `gv_hotsale_items_super_v2593` (rollback). [Probable] No es la base: el mismo cuelgue le pasó a un `UPDATE` de
  primer nivel sobre `planify.tasks` y **el mismo `UPDATE` envuelto en `with u as (update … returning …) select * from u`
  entró en el acto** — es la capa de permisos de la sesión (Auto) frenando la sentencia de escritura de primer nivel y
  esperando un «sí» que nadie contesta, no Postgres (ni `lock_timeout` ni `statement_timeout` saltan porque la sentencia
  nunca llega). `sql/gv_hotsale_precio_lk_v2598.sql`. El importador sale de
  `Importados.proveedor → GV_Imp_Proveedor.importador`; un importado sin importador no lleva las columnas de LK.
