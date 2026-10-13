# Reglas Importacion — Pedidos Importación, IMPO COMEX, recibir importados, nacionalización, PDF Damián, piezas compartidas

> Movido de `CLAUDE.md` el 2026-10-13 (poda 3ra tanda, pedido de Luis) **sin cambiar una palabra**.
> **Leerlo ENTERO antes de tocar algo de este tema.** Las reglas siguen valiendo igual que cuando estaban en CLAUDE.md.

## ⚠ IMPO COMEX bajo `/impo-comex/` es una COPIA ARMADA (Elías, 2026-09-28, v23.19)

Se abre desde Pedidos Importación → **🛃 IMPO COMEX** (`openImpoComex`). El **fuente vive en el repo
privado `loekemeyer/Impo-Comex`**; acá va sólo el build web (`client/dist-web`). **No se edita acá.**

- Entra sólo un **supervisor**: la web manda la sesión de Google de Gestión a la function
  **`Impo_Comex_web`**, que valida `es_supervisor_virgilio()` (un usuario anónimo no tiene mail →
  no pasa), acepta sólo los orígenes de Gestión (Pages y Vercel) y reenvía a las `Impo_Comex_*` con
  el token del servidor. **El portable sigue igual**, con su token.
- **Este repo es público**: en la copia no van el token ni los datos personales de la DDJJ (los
  entrega la puerta). Lo sostiene `tests/impo-comex-web.cjs`.
- Versión nueva = armar en `Impo-Comex`, reemplazar la carpeta (conservando `LEEME.md`) y subir la
  versión de Gestión.
- **La puerta vive acá**: `supabase/impo-comex-web/index.ts` (deploy `Impo_Comex_web`, verify_jwt). Los datos
  del controlante de la DDJJ NO están en ningún código: tabla cerrada `impo_comex.ddjj_controlante` + RPC
  `gv_impo_comex_ddjj_controlante()` (sólo supervisor). `sql/gv_impo_comex_ddjj_controlante_v2322.sql` (v23.22).

## ⚠ REGLA (Elías, 2026-10-09, v29.19): IMPO COMEX NUEVO vive en `impocomex/` — SIN BUILD, como el resto de Importación

**Elías:** *"migrar completamente a Gestión Virgilio … como está armado el resto de importación, sin perder funcionalidades
(que parseos etc. no funcionen incorrectamente)"*. Botón **🛃 IMPO COMEX nuevo** al lado del viejo (`openImpoComex2`,
`importacion.js`). Está **en prueba**: cuando Elías lo valide se sacan el botón viejo y la copia `impo-comex/`.

| pieza | qué es |
|---|---|
| `impocomex/ic-base.js` | `window.IC`: overlay, inicio con las 10 tarjetas, `IC.api` (la misma puerta `Impo_Comex_web` con la sesión de Gestión), drop zones, visor PDF, lightbox, markdown, editores de cabecera / ítems, corregir relevamiento, avisos |
| `impocomex/ic-<modo>.js` | un archivo por modo (lakout, multidoc, marks, estimar, full, ddjj, cajas, inal + vencimientos, autorizacion, history), script clásico, HTML en strings, se carga al entrar con `?v=APP_VERSION` |
| `impocomex/logica/` | los módulos ORIGINALES de `Impo-Comex/client/src` copiados TAL CUAL (pdfText, cajasFotos, barcodeLocal, lakoutTramos, lib/ddjjCheck…), cargados con `IC.mod(nombre)`. **No se reescribe el parseo**: se copia el archivo nuevo encima |
| `impocomex/vendor/` | xlsx, xlsx-js-style, pdf-lib, fflate (ES modules, `IC.lib`) · `impocomex/plantillas/` el .docx de Autorización |

- Endpoints y acciones idénticos al original (medido: todas las rutas y las 12 acciones de `/editar`). El controlante de la
  DDJJ sigue llegando por la puerta (`/datos-ddjj`): **este repo es público**, nada de token ni datos personales.
- Al cambiar una pantalla en `Impo-Comex`, se porta a mano al `ic-<modo>.js`; un cambio de lógica es copiar el archivo a `logica/`.
- `tests/impo-comex-nuevo.cjs` (abre los 11 modos sin errores y corre la lógica original: PDF, Excel, zip, rar, EAN-13, Word,
  DDJJ) · `tests/impo-comex-web.cjs` (bloque e: sin token, sin datos personales, sin `import.meta.env`).
- **v29.23: PARIDAD con el viejo, flujo por flujo** (subir, verificar, editar, corregir, guardar, descargar): `tests/impo-comex-paridad-{lakout,multidoc,marks,cajas,inal}.cjs`
  comparan pedidos a la puerta, pantalla y descargas contra lo que hizo el viejo (`impo-comex/`), grabado en el test o en
  `tests/tools/`. Mientras exista `impo-comex/` se regraban desde el viejo (ver la cabecera de cada test). **Al borrar el viejo, los tests siguen andando.**
- ⚠ **v30.06 (Elías, 13/10): el botón del IMPO COMEX VIEJO se ocultó** — en Pedidos Importación queda un solo
  **🛃 IMPO COMEX** que abre el nuevo (`openImpoComex2`). `openImpoComex()` y la carpeta `impo-comex/` siguen (los
  tests de paridad graban desde ahí) hasta que se borren.
- ⚠ **r81 (Elías, 13/10) — Cajas marca la OTRA MARCA del frente**: la IA lee TODAS las marcas del frente del cartón
  (`marcas_frente`) y la empresa de referencia es el **prefijo del código de barras** (779558700 LK / 779800543 CH) o,
  sin barras, el **CUIT del comercializador**. Una marca de la otra empresa → fila `marca_frente` **diferencia GRAVE**.
  Vive en `Impo-Comex/supabase/functions/_shared/cajas.ts` (deploy `Impo_Comex_verify-cajas`, v26) y lo comparten el
  viejo y el nuevo; acá sólo cambiaron el rótulo y el formato del campo (`ic-cajas.js`, `logica/cajasEtiquetas.js`).

## ⚠ REGLA (Luis, 2026-09-28, v23.45): la importación se RECIBE desde el panel — 📥 RECIBIR

Pedidos Importación → Acciones → **📥 RECIBIR** (también en 📦 Baches). Guiado: qué bache, empresa (sólo
duales), unidades por caja y a dónde va cada parte: **A guardar · Góndola (sus celdas del Mapa) · Rack ·
Excedente · Insumos (posiciones IN)**. Antes de grabar **simula** (`gv_imp_recibir(..., p_simular=true)`):
góndola que no alcanza (`cajas_max` de sus celdas contra el saldo) o rack ocupado / de otra empresa
(`gv_rack_pos_chequear`) → avisa y la persona elige: partir (lo que entra + resto a A guardar), otro lugar
o «ponerlo igual» (`resolucion='forzar'`, queda en el historial).

| escribe | qué |
|---|---|
| `Movimientos_Stock` | una fila por destino: `recepcion_imp` (a_guardar/terminado/excedente), `ingreso` (racks), `recepcion_insumo` (insumos, en u) |
| `GV_Importados_Baches` | `unidades_llegadas` + estado, y `gv_importados_resync` |
| `GV_Imp_Recepcion` + `_Destino` | historial → solapa **📜 Historial recepción** (`gv_imp_recepcion_historial`) |

⚠ `recepcion_imp` y no `recepcion`: ésta dispara el Telegram de «recepción rara» (mediana de talleristas).
⚠⚠ **Al recibir, el pedido deja de estar en viaje** (Luis, v23.49): `p_cerrar` default true → bache `llegado`
aunque llegue menos (el faltante queda anotado) o más. **v25.69 (Luis, D16, 01/10): al recibir MENOS de lo pedido la casilla viene DESMARCADA** — recepción
parcial, lo que falta sigue pedido (4.464 − 64 = 4.400). Marcarla dice en rojo *«Se CIERRA EL PEDIDO COMPLETO»* y
recién ahí lo que falta pasa a faltante. Si llega todo o más, se cierra solo (`p_cerrar` va true). **Lo de más entra ENTERO al stock y NO descuenta otros
pedidos en viaje del mismo código** (*"no queda extra cancelado"*). Desmarcando «Dar el pedido por recibido»
el resto sigue en viaje. Doble click / reintento: `p_client_id` único → no graba dos veces. **↩ Anular** en el
historial (sólo la última del pedido): movimientos inversos, frena si lo recibido ya se movió.
Centinelas ids 235-239. `sql/gv_imp_recibir_v2349.sql`.
⚠ El viejo «📥 Llegó» NO movía stock (sólo `Importados_Mov_Stock`): su botón ya no está.
⚠ **No recibir el mismo contenedor también por Recepción (recepcion.js)**: se contaría dos veces.
`sql/gv_imp_recibir_v2345.sql`, `tests/imp-recibir.cjs`.
**v24.80 (Luis, 30/09): UN 📦 y UN 📥 por código** — un código que junta varios artículos del maestro (323ES =
323ES suelto + 323E LK + 838E CH, `GV_Importados_Alias`) mostraba un par de botones por artículo. Hoy el 📥
(`impRecibirCodigo`) abre un selector con los pedidos en viaje de todos y de ahí el popup de siempre; el 📦
(`pedImpBachesDe`) elige de cuál. **Cada artículo recibe con SU código** (Luis: *"recibir 323ES es 323ES, no 323E"*).
**La cantidad va en cajas o en UNIDADES**: en unidades se convierte con la UxB a la caja más cercana
(3.000 u ÷ 144 → 21 cajas) y el popup dice la diferencia (+24 u). `tests/imp-recibir-codigo-unidades.cjs`.
**v24.83-84 (Luis, 30/09): un importado que es INSUMO entra como insumo y su stock cuenta para el producto.**
`323ES` (pedido) → insumo **`323ES In`** (`GV_Importados_Insumo_Map`), en su unidad (`Insumos_Factores`; el popup
no pide UxB ni cajas). **`Importados_Stock_Parte`** = «el stock de esta parte cuenta como stock de este producto»,
con **`parte_x_caja`** (u de la parte por caja; NULL = 1 por unidad): 12 u de `323ES In` = 1 caja de 323E **y** de 838E.
Es POSIBILIDAD de armar: sólo apaga el cartel «Sin stock» de `gv_reingresos_feed` (sólo importados). Centinela 255.
`sql/gv_insumo_cuenta_como_producto_v2484.sql`.
**v24.89 (Luis, 30/09):** todo movimiento de **insumos** es empresa **`Mixto`** (lo fuerza `gv_insumo_unidad_base`). Y un
pedido en viaje cuya **fecha de reingreso ya pasó** sin recibirse corre solo a **hoy + 7** (`gv_importados_eta_vencida`,
cron `gv-importados-eta-vencida` 00:07 ART, log `GV_Importados_ETA_Log`): una sola fuente, `GV_Importados_Baches` →
`Importados.reingreso_est` → módulo de Importados y cartel de las páginas.
El cartel de un producto toma la fecha **más temprana** entre su pedido y el de sus partes (v24.91: 323E/838E → la del 323ES).
**v25.12 (Luis, 30/09): el cartel llega a la página al toque.** Tocar «Cartel», la fecha de reingreso o la entrega
global llama a **`sync_reingresos_cartel_virgilio`** de LK (sólo el cartel, ~1,6 s, anon la puede correr) en vez de
esperar el cron 39 (≤ 5 min). La sync entera tarda ~11 s (8,4 s son los ocultos) y anon corta a los 3 s: por eso
el switch «Web» sigue en ≤ 5 min. Si la llamada falla, el cron la rehace igual. `sql/lk_sync_reingresos_cartel_v2512_LK.sql`,
`tests/pedimp-cartel-sync.cjs`.
**v25.2 (Luis, 30/09): 323E y 838E NO se agrupan con 323ES** (*"no debería juntarlos así"*): se borraron sus filas de
`GV_Importados_Alias` (backup `zz_backups."GV_Backup_ImpAlias_20260930"`; queda sólo 865ED→865E) y `gv_imp_recibir_contexto`
ya no usa el alias: los pedidos de 323E/838E se reciben en cajas, sólo el de 323ES entra como insumo `323ES In`.
**v25.12 (Luis, 30/09): el insumo se llama `323ES`, no `323ES In`** (*"323ES nunca fue un código de stock"*): renombrado en
`Insumos`, `Insumos_Factores`, `GV_Importados_Insumo_Map` e `Importados_Stock_Parte` (0 movimientos; backup `zz_backups."GV_Backup_323ESIn_20260930"`).

**v25.66 (Luis, 01/10): se puede RECIBIR un importado SIN PEDIDO registrado.** El 📥 está siempre; sin pedido en viaje,
el pop-up alerta *«No hay pedido registrado… queda como recepción SIN PEDIDO»*. `gv_imp_recibir_sin_pedido(importado, …)`
crea en la MISMA transacción un bache `sin_pedido = true`, `pedido_ref 'SIN PEDIDO'`, con unidades = lo recibido: nada queda
en viaje y **el pedido en curso nunca baja de cero** (Luis: *"si recibo 100 de algo sin pedido no debería bajar el pedido a −100"*).
Simular no deja bache (subtransacción que se revierte). Anular la recepción o el «No» de Cervantes pasan ese bache a `anulado`.
La recepción PARCIAL de un pedido sigue igual: desmarcando «Dar el pedido por recibido» lo que falta queda en viaje (4.464 − 64 = 4.400).
`sql/gv_imp_recibir_sin_pedido_v2566.sql`, `tests/imp-recibir-sin-pedido.cjs`.
**Desglose de la tarjeta del proveedor (Luis, v23.75):** los dos chips de la banda se expanden. Izq: consumo/mes =
Σ proy u/mes × FOB por artículo, y meses = (mínimo − a pedir hoy) ÷ consumo. Der: CIF y cada línea de lo no
recuperable con su fórmula (salen de `_pedImpNacionalizar().detalle[i][2]`, la suma = `noRecup`). El abierto queda en
`_pedImpDesgAb` por proveedor. `tests/impo-nacionalizacion.cjs`.
**Tasas (Luis, v23.77):** derechos **18 % del CIF** en los tres modos (base; cada artículo tiene su arancel) y
estadística **3 % del CIF con tope u$s 180**. Retira el 35 % de derechos de la consolidada del Excel viejo.
**Estadística por tramo de FOB** (v23.79, Luis): hasta 6.000 → 3 % del CIF; 6.001–10.000 → u$s 180 fijos; más de 10.000 → 3 % sin tope (`_nacEstad`). Retira el «tope 180» parejo de la v23.77.
**Recuperable separado** (v23.80, Luis): la tarjeta y el desglose muestran aparte lo que vuelve como crédito fiscal — IVA 21 %, IVA adicional 20 %, Ganancias 6 %, IIBB 0,17 % (v23.81) sobre CIF + derechos + estadística (`_nacRecup`) — y NO lo suman al costo. En avión (courier) el IVA sigue en el no recuperable. **En avión también va la comisión NTL** (v23.81, Luis). La comisión NTL es 5 % del **FOB**, no del CIF (ya lo era; el test lo fija).
**Fujian paga 35 %** (v23.78, Luis: *"solo ponele 35% a fujian / 18% al resto"*): `_DERECHOS_PROV` / `_derechosProv(prov)`, los tres modos.

## ⚠ REGLA (Luis, 2026-10-09, v29.04): el INGRESO A RACKS de importación DESCUENTA el pedido en viaje

**Luis:** *"404E entró por ingreso a racks · ese ingreso fue del pedido de importación"*. El contenedor (Becky,
PI B260601) lo cargan los operarios por **Ingreso a racks → 📦 Importación** (`racks_plani_ingreso`), no por Recepción
ni por 📥 RECIBIR, y el pedido seguía «en viaje». (Los marcadores y centinelas de la base dicen v28.96: llave, no cambiar.)

- `racks_plani_ingreso` llama al final a **`gv_imp_imputar_ingreso_racks(mov_id, legajo)`**: busca el pedido EN CURSO de
  ese código con reingreso más próximo y algo pendiente (dual: misma empresa), suma `cajas × uni por caja` (Importados o,
  sin dato, `Importados_Volumen.uni_inner`) a `unidades_llegadas`, deja la fila en `GV_Imp_Recepcion` (se ve en
  📜 Historial) y en `Importados_Mov_Stock`, y recalcula el pedido en curso. **No mueve stock**: ya entró con el IR.
- Llega todo → `llegado`; llega menos → sigue en viaje con lo que falta; lo de más es sobrante de ESE pedido (v23.49).
- **↩ Anular** en Historial deshace sólo la imputación: no hay fila de destino, así que no saca las cajas del rack.
- Nunca frena el IR. Todo queda en **`GV_Imp_Ingreso_Racks_Log`** (`resultado <> 'imputado'` = mirar: `sin_pedido`,
  `sin_uni_x_caja`, `error`). El modo 🏠 Nacional (`racks_plani_ingreso_nacional`) no imputa.
- ⚠ **Un contenedor que entró por IR NO se recibe además por 📥 RECIBIR** (se contaría dos veces).
- Imputados a mano el 09/10 (pedido de Luis): 404E 928 u, 958E 3.120 (+240), 954E 2.016, 932E 1.728 → llegados;
  957E 2.448 de 4.752 → sigue en viaje. ⚠ El IR de **«606» 10 cajas** (X22, 09:16) no se imputó: no es importado
  (¿606E?, que está en el mismo PI).
- `sql/gv_imp_ingreso_racks_v2896.sql`, `tests/imp-ingreso-racks.cjs`.
- ⚠⚠ **v29.13 (Luis, 09/10: *"que el operario no tenga que elegir el pedido para recepcionar. que eso se resuelva en el
  modulo de importacion"*): el pedido se resuelve en Importación → 📥 Recibido.** Un solo pedido en viaje de ese código →
  se descuenta solo (como antes). **Dos o más → NO se descuenta**: queda `a_elegir` en `GV_Imp_Ingreso_Racks_Log` (con los
  candidatos) y un supervisor lo elige con **↔** (`gv_imp_ir_asignar`, que también cambia o deshace uno ya descontado: le
  devuelve lo llegado al pedido anterior y anula su recepción). **✓ Visto** = `gv_imp_ir_visto`. Badge rojo en el botón
  Importación y en la solapa (`gv_imp_ir_avisos`: renglones sin revisar). Nada de esto mueve stock. El operario no elige
  nada. Centinelas v29.11 (marcador de la base). `sql/gv_imp_ir_resolver_v2913.sql`, `tests/imp-ir-resolver.cjs`.
- ⚠ **v29.17 (Luis, 09/10): lo que entró por Ingreso a racks de importación ANTES de la imputación automática se revisa
  A MANO** en 📥 Recibido: 41 ingresos (22-23/07, 31/08, 25/09) entraron al registro como `a_revisar` («↺ revisar
  (anterior al 09/10)»), sin descontar nada. El admin elige el pedido (↔) o marca ✓ Visto si ya estaba descontado. Los 21
  imputados solos del 09/10 también quedan para que el admin los mire. `sql/gv_imp_ir_retroactivo_v2917.sql`.
- ⚠⚠ **v29.21 (Luis, 09/10: *"NO SE TENDRIA QUE HABER DESCONTADO NADA DE NINGUN PEDIDO QUE NO HAYA SIDO POR MEDIO DEL
  FRONT DEL ADMIN"*): el Ingreso a racks NUNCA descuenta solo.** Con 1 o más pedidos en viaje queda `a_elegir` y lo
  confirma un admin en 📥 Recibido (↔). Retira el «un solo pedido → se descuenta solo» de arriba. Marcador de la base
  `v29.19-ir-solo-admin` (llave), centinela 382 = `v_ncand >= 1`. Una sesión de Claude tampoco imputa por su cuenta:
  la imputación la hace el admin. `sql/gv_imp_ir_solo_admin_v2921.sql`.

## ⚠ REGLA (Luis, 2026-09-29, v23.95): los MESES OBJETIVO se eligen en el encabezado del proveedor

**Luis:** *"el parámetro de meses objetivo ponelo configurable al lado del nombre de cada proveedor
(menú desplegable con los números del 1 al 24, seleccionable y que afecte a todos los códigos de ese
proveedor"* · *"sigue saliendo de importación cuando aprieto y sale el popup de proyección"* ·
*"alineá mejor (tiene que funcionar bien en diferentes resoluciones) y optimizá tamaño horizontal
(cambiá «ver desglose» por una flecha)"*.

| qué | cómo queda |
|---|---|
| meses objetivo | **desplegable en el encabezado de cada proveedor**: «gral (N)» + 1 a 24. Es la MISMA columna que el ⚙ (`GV_Imp_Proveedor.meses_objetivo`), así que vale para **todos** sus códigos |
| el pop-up de proyección | se dibuja en **su propio overlay** (`#impProyOv`), encima: el módulo queda vivo abajo y al cerrar sigue ahí. Ya no hay «← Volver al pedido» — no hace falta |
| la banda | grilla `auto-fit` (dos chips iguales; uno solo por fila en pantalla angosta) y «ver desglose» pasó a ser una **flecha ›** al costado, que no le roba ancho al dato |
| la tabla | **llena el ancho que tiene** (`width:100%`, `min-width:1188px`): el sobrante se lo lleva Descripción, así que no queda hueco a la derecha ni en un monitor ancho |

⚠ **Se manda sólo `{proveedor, meses_objetivo}`**: `gv_imp_proveedor_guardar` deja intacta **toda clave
ausente**, así que mandar el resto pisaría lo que otro esté editando en el ⚙.

⚠ **El refetch posterior sólo reemplaza los datos si trajo items.** Una lectura vacía dejaría la
pantalla en blanco, y *"no pude leer"* no es *"no hay importados"* (misma regla que §«una lectura ROTA
no es un CERO»).

⚠ **`_stkPopShell` ahora DEVUELVE el body**, y en modo overlay ese body **no lleva id**: el de la
pantalla de abajo se llama igual (`stkPopBody`) y `getElementById` devolvía aquél — la proyección se
habría dibujado adentro del módulo.

**Chequeo:** `node tests/pedimp-meses-proveedor.cjs` · `node tests/pedimp-moq-proy.cjs` (el pop-up no
se come la pantalla de importación) · `node tests/imp-tabla.cjs`.

## ⚠ REGLA (Luis, 2026-09-29, v23.93): en Pedidos Importación, lo que se TOCA es el dato

**Luis, sobre las tres pantallas:** *"proy u/mes tiene que ser lo que apretás para ver la proyección…
(sacá el código clickeable)"* · *"stock: sacá el visual de −x (unidades comprometidas), ya que el total
ya lo descuenta"* · *"los datos que importan son los meses y el consumo en lo de la izquierda y el % y $
no recuperable del de la derecha"* · *"como te gusta hacer botones largos horribles eh"*.

| dónde | cómo queda |
|---|---|
| tabla | el **código es texto**; el pop-up de proyección lo abre la celda **Proy u/mes** (`td.pedimp-proy`), que es donde vive el dato — igual que en Stocks. Letra 15px, encabezados 12px, colgroup 1218px |
| columna Stock | **sin el «📋−N»**: el número YA es el disponible (v16.08) y restarlo a la vista era leer dos veces la misma resta. Lo comprometido queda en el `title` |
| banda del proveedor (colapsada) | grande sólo **meses + consumo** (izq) y **% + u$s no recuperable** (der); el resto en 11,5px. La cuenta entera sigue a un click |
| pop-up ⚙ Configurar | botones chicos y letra grande; se fue el párrafo «Se guarda en el maestro Importados…» |

⚠ **Los botones gigantes de un pop-up nuevo casi siempre son el `button{width:100%;padding:16px;
font-size:22px;margin-top:14px}` global de la línea 26**, no el estilo que se le puso. Se neutraliza por
contenedor (`#impCfgOv button{width:auto;margin-top:0}`), y lo mismo con los inputs, que sin
`box-sizing:border-box` se desbordan del panel.

**Chequeo:** `node tests/pedimp-moq-proy.cjs` — el candado (A) verifica que la celda de proyección abre
el pop-up **y que el código no volvió a ser clickeable**.

## ⚠⚠ REGLA (Luis, 2026-09-29, v23.89): la config de IMPORTADOS vive en TABLAS — ⚙ por proveedor

**Luis, textual:** *"me gustaría que la capacidad de editar cosas como meses objetivo de importados
esté editable en cada proveedor de importados (un botón al lado del nombre … «Configurar
parámetros») … así como agregarle/sacarle códigos de los ya existentes"* · *"fijate que no vivan
en el front los datos, sino que modifiquen las tablas pertinentes"*.

Hasta la v23.88 el módulo de importados tenía **la mitad de su configuración escrita en
`index.html`** y la otra mitad en el módulo de **OCs**, que es otro módulo:

| qué | dónde estaba | dónde está |
|---|---|---|
| importador de cada proveedor (Chef / Tierra Nativa) | `_IMPORTADOR_DE` | `GV_Imp_Proveedor.importador` |
| quién factura vía NTL y su comisión | `_NTL_PROVEEDORES` (5 % fijo) | `.usa_ntl` + `.ntl_pct` |
| derechos (35 % Fujian, 18 % el resto) | `_DERECHOS_PROV` | `.derechos_pct` (+ el general) |
| mínimo del pedido y valor del m³ | `_IMPO_MIN_USD_DEFAULT`, `_NAC_DEFAULTS` | `.min_usd`, `.valor_m3` |
| IVA, IVA adicional, Ganancias, IIBB, estadística y sus tramos | dentro de `_nacEstad` / `_nacRecup` | `Importados_Config` |
| **meses objetivo** | `Importados_Config`, pero **uno solo para todos**, y editable en **OCs → ⚙** | `.meses_objetivo` **por proveedor**, con el general de fallback |

> **El botón ⚙ «Configurar parámetros» está en el encabezado de cada proveedor**, en Pedidos
> Importación, con tres pestañas: **Parámetros** (los de ese proveedor) · **Códigos** (agregar y
> sacar, escribe `Importados.proveedor`) · **Generales** (los de todos).

- Lo que se deja **vacío** hereda el general. La vista **`gv_imp_proveedor_cfg`** resuelve el
  `coalesce` y devuelve además el valor crudo (`*_propio`), que es lo que el pop-up necesita para
  saber qué está pisado y qué no. Los generales, en **`gv_imp_nac_config`**.
- Los porcentajes se **muestran en porcentaje** (35) y se **guardan en tanto por uno** (0,35): la
  RPC rechaza cualquier valor > 1, que es el error de carga que se comería un pedido entero.
- Escriben **`gv_imp_proveedor_guardar`**, **`gv_imp_nac_config_guardar`** y
  **`gv_imp_codigo_proveedor`**, las tres SECURITY DEFINER con guard de supervisor. La tabla no
  tiene INSERT/UPDATE para `anon` ni `authenticated`.
- **Sacar un código NO lo borra**: queda sin proveedor, igual que en la pestaña 🏭 Proveedores
  (que sigue existiendo y escribe la misma columna).

⚠ **Los objetos del front quedan de FALLBACK, no de fuente.** `_PROV_IMP_LISTA`,
`_IMPORTADOR_DE`, `_NTL_PROVEEDORES`, `_DERECHOS_PROV` y `_NAC_TASAS` son `let` y los hidrata
`_impCfgCargar()` al abrir el módulo: si el fetch falla, la pantalla calcula **exactamente igual
que la v23.88** (lo mide `tests/impo-nacionalizacion.cjs`, que corre justo sobre ese bloque).
**Al agregar un parámetro nuevo de importados va a la tabla y se hidrata acá: no se vuelve a
escribir un número en `index.html`.**

⚠ **Impacto medido el 29/09: CERO.** La semilla de `GV_Imp_Proveedor` es exactamente lo que decía
el front (Fujian 0,35 · el resto 0,18 · NTL en Frontier, Fujian, Kangli y Zhixin) y ningún
proveedor tiene meses objetivo propio, así que los 156 artículos siguen en 10 meses. Lo que
cambia es **dónde** se edita.

⚠ El parche de `gv_importados_ordenes` y `v_importados_ordenes` se aplicó **sobre
`pg_get_viewdef`**, es idempotente y **falla con un `raise` si el texto no matchea** (varias
sesiones tocan estos objetos). Las dos tienen su fila en `GV_Reglas_Centinela`.

**Chequeo:** `select * from public.gv_reglas_perdidas;` — vacía = todo bien ·
`select proveedor, meses_objetivo, derechos_pct, usa_ntl, codigos from public.gv_imp_proveedor_cfg order by orden;`
· `node tests/pedimp-config-proveedor.cjs`. `sql/gv_imp_proveedor_config_v2389.sql`.

### ⚠ v23.90 (Luis, 29/09): MOQ por proveedor · derechos por ARTÍCULO · el código abre la proyección

| qué | dónde vive | cómo se edita |
|---|---|---|
| **MOQ** (mínimo que la fábrica acepta, en unidades por código) | `GV_Imp_Proveedor.moq`, default **1.000** | ⚙ → Parámetros |
| **tope de cobertura** para estirar el pedido | `.moq_meses_max`, default **12** | ⚙ → Parámetros |
| **derechos del ARTÍCULO** (su partida arancelaria) | `Importados.derechos_pct` → vista `gv_imp_articulo_cfg` | ⚙ → **Códigos**, la casilla «% der.» de cada renglón |

> **Los derechos bajan en cascada: artículo → proveedor → general.** El % del artículo gana,
> porque es su partida arancelaria. Lo resuelve `_derechosArt(cod, prov)`.

⚠ **La tasa del EMBARQUE es el promedio ponderado por FOB de sus artículos**
(`_derechosPedido`). Con todos en la misma tasa devuelve esa tasa, así que **hoy no cambia
ningún número**: al 29/09 hay 153 artículos y **0 con arancel propio**.

⚠ **El indicador de MOQ no pregunta «¿cuántas unidades faltan?» sino «¿cuántos MESES de
cobertura hay que comprar para llegar?»**:

```
meses necesarios = (MOQ + stock + en curso) / proyección mensual
```

| caso | chip |
|---|---|
| entra con el objetivo del proveedor (10 meses) | sin chip |
| entra estirando hasta el tope (12) | **🟡 MOQ N,Nm** — se puede pedir, fuera del target |
| ni con el tope | **🔴 MOQ** — fuera de target: se consolida o se habla el MOQ con la fábrica |
| sin proyección de venta | **MOQ ?** — no se inventa una cobertura |

El chip va en la celda de **Unidades**, no en la del código: es sobre la cantidad que manda el
MOQ. (Y ponerlo en la del código rompe cualquier test que lea esa celda — pasó.)

⚠⚠ **Los meses objetivo pasaron a ser POR ARTÍCULO en `ocgFetchImportados`** (`o.mesesArt`). El
`let meses = 10` global se quedaba con el de la ÚLTIMA fila leída: desde que la v23.89 dejó
pisarlos por proveedor, ese número dejó de existir. El global queda sólo para el encabezado.

⚠ **El código del artículo abre el MISMO pop-up de proyección de la pantalla de Stocks**
(`stkShowProyVentas`), no una copia. Se le agrega **«← Volver al pedido»** porque
`_stkPopShell` pisa la tarjeta y `stkPopClose()` cierra todo. La proyección se le pasa en
**cajas** (`proyUni / uxc`): la pantalla de importados la muestra en unidades.

⚠ **El desglose de «Puesto en Arg» es de DOS columnas** (concepto con su % · importe) y la
fórmula de cada renglón se abre al tocarlo. El % viene YA en el nombre, armado por
`_pedImpNacionalizar` con las tasas de la base: **acá no se escribe ningún número**.

**Chequeo:** `select proveedor, moq, moq_meses_max from public.gv_imp_proveedor_cfg order by orden;`
· `select count(*), count(derechos_pct) from public.gv_imp_articulo_cfg;`
· `node tests/pedimp-moq-proy.cjs`. `sql/gv_imp_moq_derechos_v2390.sql`.

### ⚠ v23.91 (Luis, 29/09): el desglose es un POP-UP · el ⚙ del proveedor son 2 pestañas · «Historial» = pedidos + recepciones

1. **El desglose salió del chip.** Adentro lo hacía crecer y empujaba la tabla; con varios
   proveedores abiertos la pantalla era ilegible. El chip volvió a una línea con «ver desglose»
   → **`pedImpDesgPop(prov, lado)`**. La lógica de expandir **no cambió**: sigue habiendo un
   `<details>` por concepto, ahora dentro del pop-up. Los datos para rearmarlo quedan en
   **`_pedImpDesgData`**, declarado junto a `_pedImpDesgAb` — más abajo quedaba en zona muerta
   para `_pedImpBandaHtml` y el test del bloque puro no lo veía.
2. **El ⚙ del proveedor tiene SÓLO «Parámetros» y «Códigos»** (Luis: *"no entiendo por qué hay
   un general ahí y qué modifica esos"*). Los generales pasaron a **⚙ Generales**, un botón de
   la barra de nacionalización del módulo: es lo que vale para **todos**, así que no puede vivir
   adentro del pop-up de **uno**. Es el mismo `_impCfgRender` con `prov` vacío.
3. **El ✕ de sacar un código es chico y pide confirmación** (`pedImpCfgSacar`): está al lado del
   input de derechos y toca el maestro. El cartel aclara que el artículo **no se borra**.
4. **La solapa «📜 Historial recepción» es «📜 Historial»** y tiene dos vistas: **🚢 Pedidos**
   (`gv_imp_pedidos_historial`: un renglón por pedido y proveedor, con lo pedido, lo llegado, el
   embarque, el reingreso y el estado) y **📥 Recepciones** (lo de siempre). Arranca en
   Recepciones, que es lo que la solapa mostraba antes. La búsqueda vale para las dos.

⚠ **El pedido sin PI se agrupa por su DÍA de carga.** Son los baches viejos, anteriores al
campo; sin eso todos caían en un renglón único. La clave se arma en un subselect: un agregado
no puede ir adentro del `GROUP BY` (42803).

⚠ **Dos tests quedaron viejos con esto y se actualizaron en el mismo commit**, que es la regla:
`impo-nacionalizacion` medía los `<details class="pedimp-desg"` de la banda (ahora mide que la
banda NO los lleve, que los dos chips abran el pop-up y que el contenido siga completo) e
`imp-recibir` buscaba el texto «Historial recepción».

**Chequeo:** `node tests/imp-hist-pedidos.cjs` · `node tests/pedimp-config-proveedor.cjs` ·
`select * from public.gv_imp_pedidos_historial(400);`. `sql/gv_imp_pedidos_historial_v2391.sql`.

## ⚠ REGLA (Luis, 2026-09-30, v24.77): 🖨 IMPRIMIR PDF de Pedidos Importación = reporte por proveedor

Botón arriba a la derecha de la barra (`pedImpRepAbrir`): pop-up con los proveedores a tildar + «Sólo lo que
genera pedido». El PDF (`_pedImpRepHtml`, Arial 15, A4 vertical) tiene una tabla por proveedor con **Cód. ·
Stk. · E.M. (proyección u/mes) · Meses Stk. (⚠ si < 4; = stock REAL disponible ÷ E.M., **sin** lo en camino — Luis v24.78) · m³ · u$s · Pedido en curso** (unidades + dd/mm, o «No»),
ordenada por esos meses (menos primero). **Una sola tabla**: cada proveedor es una fila-rótulo gris con sus totales (v24.79, *«mínima la separación»*), y antes de imprimir sale una **vista previa** (`pedImpRepVista`). **m³ y u$s son sólo de lo que genera pedido**; el total va
arriba de cada columna. `tests/pedimp-reporte-pdf.cjs`.

⚠⚠ **v25.13 (Thomas, 30/09): la SALIDA de ese botón ahora son las hojas del PDF para Damián** (*"misma
funcionalidad de hoy, que te muestre todos, pero con la lógica del PDF de Damián"*). Mismo pop-up y vista previa;
por cada proveedor tildado salen sus hojas (pedido · sin pedir · discontinuos), una tanda atrás de otra; con «Sólo
lo que genera pedido», sólo la hoja del pedido. Las dos puertas usan `_pedImpDamianHojas(prov, opt)` +
`_pedImpDamianDoc`; los discontinuos se leen una sola vez (`_pedImpDamianDisc`). **Se retira el reporte de una
tabla** (`_pedImpRepHtml`, Cód · Stk · E.M. · Meses…): no volver a ponerlo.

⚠⚠ **v26.31 (Luis, 02/10): con VARIOS proveedores tildados, el PDF va POR HOJA, no por proveedor** (*"agrupar en
con pedido (todos los proveedores discriminando), sin pedido (…), discontinuo (…)"*). Salen **3 hojas**: Pedido ·
Sin pedir · Discontinuos, cada una **una sola tabla** con todos los proveedores y un **renglón-rótulo por proveedor**
(`tr.prov`, con sus meses, FOB y m³ en las mismas columnas; el total general va arriba). Con UN proveedor, igual que
antes (el nombre en el título). Lo arma `_pedImpDamianPartes(provs, opt)` → `{ped, sin, disc}`.
**Y «optimización horizontal absoluta»**: 1 px de aire por lado (eran 3), separadores de 2 px (eran 5), Descripción
104 px partida en renglones que entran en el alto de la foto, «Por qué» partido, el aviso del MOQ en 2 renglones,
totales en 14 y rótulo **«Mca»**. Medido con 3 proveedores: la tabla del pedido pasó de **580 a 501 px**.
**v26.34 (Luis, con la foto de la columna Máx): los separadores quedan en 2 px y cada columna lleva 4 px de aire por
lado** (con 1 px «Stock» y «Llegan» se pegaban al borde): 557 px. **Y «Llegan» lleva el FOB u$s de lo que viene**
(unidades en camino × FOB unitario, la misma cuenta de 🚢 En curso), en la celda y sumado arriba y en el rótulo de
cada proveedor, para compararlo con el FOB del pedido. Sólo en la hoja del pedido.
**v26.37 (Luis: *"que guarde el FOB del pedido en curso"*): cada bache GUARDA el FOB con que se pidió**
(`GV_Importados_Baches.fob_uni`, lo pone el trigger `gv_importados_bache_fob` al insertar, con el FOB del maestro de
ese momento). 🚢 En curso, el detalle del PI, 📜 Historial y la columna «Llegan» valorizan con
`coalesce(FOB del bache, FOB del maestro)`; el PDF lo lee por `gv_importados_curso_fob()` (sólo supervisor; sin
lectura, FOB de hoy). Los 89 baches en curso al 02/10 no tienen FOB guardado (backfill pendiente del «sí»). La fecha
de llegada va al **mismo tamaño que las unidades** (PDF `.fl` 14 px y pantalla). `sql/gv_importados_bache_fob_v2637.sql`.
**v26.39 (Luis: *"primero un resumen … después las cinco hojitas de lo que tengo que pedir, después las de lo que no
estoy pidiendo y después las de discontinuos. No que esté por proveedor"*): con 2+ proveedores el PDF arranca con la
HOJA RESUMEN** (`_pedImpResumenHoja`: Proveedor · En curso u$s (la de 🚢 En curso) · A pedir FOB u$s · % nacionalización
no recuperable del pedido · Urgencia, con su total) **y sigue UNA hoja por proveedor en cada tanda**: todos los pedidos,
después todos los sin pedir, después todos los discontinuos, en el orden de urgencia del resumen. Se retira la tabla
única con renglones-rótulo de la v26.31 (`_pedImpDamianPartes` con varios queda sin llamador). Con un proveedor, sin resumen.
**Urgencia** (`_pedImpUrgencia`) = meses que le faltan a la línea para tener **8** meses de stock (stock + en camino),
ponderado por consumo u$s/mes. **Va como PRIORIDAD 1 a 4** (v26.41, Luis: *"prefiero prioridad 1, 2, 3, 4"*):
1 = faltan 3 o más · 2 = 2 a 3 · 3 = 1 a 2 · 4 = menos de 1 (incluye 0 = ningún artículo < 8 m); cortes confirmados
por Luis (D5, 02/10). Al 02/10: Zhixin 2,8 · Kangli 2,8 · Hugo Wong 1,3 · Fujian 1,2 · Becky 1,1 · Ownland 0,9.
**v26.40 (Luis: *"que figure el monto del pedido en usd arriba de en curso"*): en «Llegan» el u$s de lo que viene va
ARRIBA de las unidades** (`.fobl`, 13 px negrita), después las unidades y abajo la fecha; rótulo «u$s · u». ⚠ El
«guarde el FOB» de la v26.37 era «figure» (dictado): el FOB guardado por pedido quedó igual (no cambia ningún número
hoy; valoriza los pedidos nuevos con su precio) y **no se hace el backfill de los 89 pedidos viejos** (Luis, D4).
`tests/pedimp-reporte-pdf.cjs`, `tests/pedimp-prioridad-damian.cjs`.

### ⚠ v26.42 (Luis, 02/10): el mismo PDF sale SOLO por WhatsApp cada quincena — «Reporte quincenal a pedir»

- **n8n ya no existe** (cuenta gratuita vencida, GestOpClientes `docs/ESTADO.md`): el número «N8N Loekemeyer» se
  usa desde las Edge Functions de GestOpClientes (proyecto LK), detrás del corte **wa-guard** (llave
  `wa_envio_automatico`: en `prueba` sólo sale a la lista blanca `wa_envio_contactos`).
- **Quién arma el PDF**: el workflow `.github/workflows/reporte-quincenal-importacion.yml` (días **1 y 16**, 08:41 ART)
  corre la pantalla sin pantalla con `scripts/reporte-quincenal/enviar.cjs` — el MISMO PDF de «🖨 IMPRIMIR PDF» con
  todos los proveedores. **No hay una segunda copia del reporte**: si cambia el PDF en `importacion.js`, cambia el
  que se manda. Las 5 variables del mensaje salen de `datos` de `_pedImpResumenHoja` (fecha · a pedir FOB · proveedores
  con pedido · en curso · más urgentes).
- **Quién lo manda**: `lk_reporte-quincenal` (repo `loekemeyer/gestopclientes`): `subir` (URL firmada al bucket privado
  `gv-reportes`) → `enviar` (plantilla `reporte_quincenal_a_pedir`, PDF en el encabezado). Destinatarios = las filas de
  `wa_envio_contactos` cuyo `label` arranca con `app_settings.reporte_quincenal_destinos` (default «Thomy,Damián», D6).
- **Sin secretos**: la función reconoce al workflow por su token **OIDC** de GitHub (repo + `main` + ese archivo).
  Renombrar el workflow = cambiar `WORKFLOW_GH` en la función.
- Una quincena no sale dos veces (marca `enviado.json` en el bucket); para repetir: Actions → correrlo a mano con
  «forzar». «solo_pdf» lo arma sin mandar (queda como artifact). Si la plantilla no está APPROVED en Meta, no manda y el
  run queda en rojo. `tests/reporte-quincenal-params.cjs`.

## ⚠ REGLA (Luis, 2026-10-05, v26.98 · v26.99 · v27.05): ➕ AGREGAR O MODIFICAR PRODUCTO importado — y que impacte en Stock

Solapa **➕ Agregar / modificar** de Pedidos Importación (`openImpAgregar`, `importacion.js`). **Nuevo** o **Modificar uno
existente** (buscador del maestro; código y empresa no se cambian). Pide: código, empresa (LK/CH/Loke/Mixto), proveedor,
descripción, **tipo de producto** y familia, **secundario de**, medidas MC e inner (cm → m³), uni × inner (0 = suelto),
uni × MC, FOB, MOQ, **INAL** (certificado y vencimiento) y el **primer pedido en MC** (sugerido =
MOQ en MC enteras; editable). Todo en una transacción: **`gv_importado_guardar(jsonb)`** (sin `id` = alta; supervisor).
`gv_importado_alta` (v26.98) quedó como envoltorio. La ficha la lee `gv_importado_ficha(id)`.

| dato | dónde (y quién lo lee) |
|---|---|
| maestro, FOB, uni × inner, MOQ, primer pedido | `Importados` (`moq` y `pedido_manual` son del artículo; el proveedor se cambia en todas las filas del código) |
| uni × MC, medidas MC e inner | `Importados_Volumen` (`inner_*`, `m3_inner` nuevas) |
| **caja de Stocks** | `GV_UxB` por empresa (= inner; suelto = MC), curado |
| **línea en Stocks / OCs** | `OC_Maximos` (cod, línea, sin proveedor: un importado no se compra por OC) |
| **m³ por caja (PPP)** | `GV_Volumen_Articulos`: el inner medido o la MC repartida; en un código con m³ sólo se pisa si se midió el inner |
| tipo / familia | `GV_Producto_Tipo` (agrupa el PDF de Damián) |
| INAL | `GV_Articulo_INAL` (desmarcarlo al modificar BORRA la fila; el front lo avisa) |
| **góndola** | **NO se carga acá** (v27.04, Luis D4: *"se edita y asigna en el mapa eso"*): el form la muestra («sin lugar» si no tiene) con el link al Mapa. El parámetro `gondola_sector` de `gv_importado_guardar` queda sin llamador (si alguien lo manda, exige góndola de la MISMA empresa) |
| secundario de | `Equivalencias_Familia` |
| **aparecer en Stocks antes de que llegue** | en el ALTA, un ajuste de **0 cajas** en `terminado` (`ref 'ALTA IMP <cod>'`, descripción = la del artículo): Stocks arma su lista con lo que tiene movimientos o pedidos. Aparece en ≤ 2 min (refresco) |

- Mixto (insumo) no lleva UxB, tipo, OC ni movimiento. La página LK no se toca (D2, Luis: *"en página está bien que no"*).
- El primer pedido: 📦 Pedidos lo toma como MC pedido (`_pedImpPrimerPedidoMc`, chip «1.er pedido») mientras no haya
  pedido en curso; el trigger `gv_importados_bache_primer_pedido` lo borra al cargar el primer bache.
- **Precio y costo NO van en este form** (Luis D3, 05/10: *"debería editarse en listas de precio eso"*).

Centinelas 332-335. `sql/gv_importado_alta_v2698.sql`, `sql/gv_importado_guardar_v2699.sql`, `tests/imp-agregar-articulo.cjs`.

## ⚠ REGLA (2026-10-01, v25.94): ✏️ EDITAR PI — quién corrige, qué día y a qué hora

En 🚢 En curso, el **✏️ Editar PI** de cada pedido (reemplaza al viejo «✏️ PI», que sólo renombraba) abre
un pop-up de tres pasos: **1) ¿Quién corrige?** (botones de `GV_Imp_PI_Editor` + **Otro**, que deja el
nombre como editor nuevo si se guarda algo) · **2)** cantidad nueva por ítem y N° de PI · **3)** antes →
después **simulado en la base** (`gv_imp_pi_editar(..., p_simular=true)`, no escribe) y recién ahí «Guardar».

- Cada cambio queda en **`GV_Imp_PI_Edicion`**: editor elegido, usuario logueado, `ts`, ítem, antes y después
  (un guardado = un `lote`). Se ve en «📜 Ediciones anteriores» del mismo pop-up (`gv_imp_pi_ediciones`).
- La cantidad no puede quedar por debajo de lo ya llegado; **0 = el ítem sale de la PI** (`estado='anulado'`,
  `unidades` queda como estaba porque la tabla exige > 0; el log dice 0). Después corre `gv_importados_resync`.
- El front manda el `antes` que VIO: si la línea cambió mientras se editaba, la RPC frena y no pisa.
- Las tres RPC son sólo supervisor (`authenticated`) y están en `_PED_IMP_RPC_ESCRITURA`.
- `sql/gv_imp_pi_editar_v2594.sql`, `tests/imp-pi-editar.cjs`. Centinela: 2 filas de `gv_imp_pi_editar`.

## ⚠ REGLA (Luis, 2026-09-29, v24.32): la nacionalización por artículo es de 🚢 EN CURSO — y el proveedor la abre

**Luis, textual:** *"no me estás entendiendo. Es en la pestaña «en curso» que quería lo que te pedí.
Sacá eso que hiciste en el proveedor pestaña «pedidos» y metelo en «en curso»"* · *"apretás sobre el
proveedor y debería expandirse las unidades"*.

Se había leído *"apretás sobre el proveedor"* como **📦 Pedidos Importación** —el encabezado 🏭 de
cada chino— y **no es ahí**: el proveedor que Luis toca es **la columna Proveedor de la tabla de
🚢 En curso**. Ahí ya estaba el detalle, pero se abría **sólo desde el número de PI**.

> **En 🚢 En curso, la celda del PROVEEDOR abre el mismo detalle que el PI** (`impCursoToggle`), con
> 🛃 Nac. u$s (total y por unidad), Puesto u$s/u, el u$s/m³ editable y los tres criterios de reparto.

**Se RETIRA todo lo que la v24.31 había puesto en 📦 Pedidos Importación**: el encabezado del
proveedor vuelve a ser texto, la tabla vuelve a 11 columnas y `pedImpNacToggle` / `pedImpNacCrit` /
`pedImpSetNacM3` / `_pedImpNacBandaHtml` se borraron. **La nacionalización por artículo vive en UN
solo lugar** — dos módulos haciendo lo mismo es el pozo de Matricería.

### Lo que SÍ queda de la v24.31: el hueco muerto de la tabla de Pedidos

`.mva-tbl.wide` iba a `width:100%` dentro de una tarjeta de **1760 px** y el `<colgroup>` daba ancho
a **10 de las 11** columnas. Todo el sobrante —**~700 px** en un monitor ancho— caía en Descripción,
que es exactamente el hueco entre ella y Proy u/mes que reclamó Luis.

> **La tabla mide lo que suman sus columnas, y la TARJETA se achica a eso.** No al revés.

Medido al 29/09 en 1920 px: tabla **1.242 px** en una tarjeta de **1.274** (antes 1.760), Descripción
**232 px**. El ancho lo pone `_cols` en JS y `_anchoMax` fija el `max-width` de la tarjeta después de
dibujar. ⚠ La v23.95 decía lo contrario (*"el sobrante se lo lleva Descripción (col sin width)"*):
**queda retirada**.

**Chequeo:** `node tests/pedimp-ancho-tabla.cjs` — mide el ancho REAL de la celda con la pantalla
corriendo y que no quede ninguna `<col>` sin width; verificado que falla con Descripción en 700 px.
Y `node tests/imp-nac-articulo-pantalla.cjs`, que ahora abre el detalle **clickeando el proveedor**.

## ⚠ REGLA (Luis, 2026-09-29, v24.3): el COSTO DE NACIONALIZACIÓN se ve POR ARTÍCULO — y repartir todo por m³ NO es neutro

**Luis:** *"cada artículo en el listado tenga el coste de nacionalización, calculable por m³ y que
sea variable (se pueda ajustar)"*.

En 🚢 **En curso**, al abrir el PI cada artículo trae **🛃 Nac. u$s** (y u$s por unidad) y **Puesto
u$s/u** = FOB por unidad + lo que le toca de nacionalización. Arriba, la banda dice el costo del
embarque, el % sobre el FOB y **el u$s/m³ editable**.

> **El embarque es el PEDIDO.** El costo se calcula UNA vez con el FOB y los m³ de la fila del
> pedido —los mismos que se ven arriba— y las líneas sólo dicen cómo se REPARTE. Al revés
> (sumando líneas) un detalle incompleto infla el factor y nada avisa.

⚠⚠ **Repartir TODO por m³ le cobra los derechos al VOLUMEN, y por eso el default NO es m³.** De lo
que cuesta el embarque, lo único que se paga por volumen es el **flete**; derechos, estadística,
seguro, libre circulación, despachante y comisión NTL son **% del FOB / CIF**. Por m³ puro, un
artículo voluminoso y barato paga derechos que no generó y uno chico y caro los paga de menos.

| criterio | qué hace |
|---|---|
| **mixto** (default) | cada concepto por SU base: el flete por m³, el resto por FOB |
| **por m³** | todo por volumen — lo que Luis pidió textual, a un click |
| **por FOB** | todo por plata (el factor parejo de siempre) |

- La base de cada concepto viaja en el **4.º elemento de `res.detalle`** (`"m3"` / `"fob"`), puesta
  por `_pedImpNacionalizar`: **no se adivina por el nombre del renglón**. Al agregar un concepto
  nuevo a la nacionalización hay que decir su base, o cae en `fob` por defecto.
- El reparto lo hace **`_impNacReparto(res, items, crit)`** y **la suma da exactamente
  `res.noRecup`** (se escala al final: en **avión** la suma del detalle no coincide con el no
  recuperable, porque el certificado FEDEX entra al CIF y no se suma como costo propio).
- ⚠ **Guards:** si la base elegida suma 0 se cae a la otra; si las dos son 0 reparte por unidades;
  sin nada, parejo. **Nunca divide por cero ni le tira todo al primer renglón** — un pedido sin m³
  cargado es el caso normal, no el raro.
- **El u$s/m³ es del PROVEEDOR** (`GV_Imp_Proveedor.valor_m3`, regla v23.89: la config vive en
  tablas) y vale también para 📦 Pedidos: es la misma fuente. Se manda **sólo `{proveedor,
  valor_m3}`** — la RPC deja intacta toda clave ausente, así que mandar el resto pisaría lo que
  otro esté editando en el ⚙ (regla v23.95).
- El criterio de reparto **no toca ninguna tabla**: es cómo se muestra el mismo u$s. El Excel de la
  pantalla baja el detalle con el criterio elegido.

⚠ **`_derechosPedido` no sirve acá**: lee el FOB con `_pedImpUsdOf`, que es del generador de
pedidos. Las líneas del pedido en curso traen `usd` del backend, y por eso existe
`_impCursoDerechos` — sin ese shim la tasa del embarque salía siempre la general.

⚠ **Probado: `width:99%` en Descripción NO va.** Empuja las numéricas a la derecha y deja un hueco
muerto en el medio (más parte la marca en dos líneas). El reparto natural de la tabla queda más
apretado, que es lo que pide la regla rectora de espacio.

**Chequeo:** `node tests/impo-nac-por-articulo.cjs` (la función pura, los tres criterios y los
guards) · `node tests/imp-nac-articulo-pantalla.cjs` (corre la pantalla: las columnas, que el total
no cambie al cambiar el criterio y que el u$s/m³ guarde sólo su clave).

## ⚠ REGLA (Thomas, 2026-09-29, v24.43): Pedidos Importación va por PRIORIDAD — meses de stock CON lo en camino

- **Meses stock = (stock disponible + en camino) ÷ proyección por mes** (`_pedImpMesesStock`). Cada proveedor se
  ordena por ahí (`_pedImpPrioCmp`): menos meses primero, sin proyección al final. < 4 meses → rojo con ⚠ y badge
  «⚠ N con < 4 meses» en el proveedor y en su ficha del filtro.
- La columna **En camino** muestra las unidades y la fecha **dd/mm** (`Importados.reingreso_est`); sin fecha, «s/f».
- **📄 PDF para Damián** (`pedImpPdfDamian`): Código · Descripción · Foto · Stock · En camino · Máximo (meses arriba) ·
  Pedido en MC · FOB (total arriba) · m³ (total arriba) + el resumen de cómo se compone. Imprime esperando las
  fotos (`_pedImpPrintConFotos`, techo 8 s): `remitoPrintDoc` imprime a los 400 ms y saldrían en blanco.
- **Las fotos son las de la página** (bucket `products-images`, `<cod>.webp`, el mismo que usa `pagina-LK-copia`),
  con sus variantes: con/sin «E» y sin sufijo S/D/C; después el bucket de Chef, que las guarda en **`.jpg`** (paginach), no en `.webp`. Medido 29/09: 106 de 150 en LK.
- **Los INSUMOS (partes, `esParte`) van SIN foto** en el PDF de Damián (Thomas, v24.44: 505C, 523C, 587C, 1000900, 1546903).
- El PDF del chino (🖨 PDF pedido) lleva **Inner Cajas** = unidades ÷ `Importados_Volumen.uni_inner` (v24.40).
`tests/pedimp-prioridad-damian.cjs`, `tests/pedimp-pdf-inner.cjs`.

### ⚠ v24.55 (Thomas, 29/09): el MOQ MUEVE la cantidad — «o llego al 80 % del MOQ o no pido nada»

- Lo calculado ya llega al **80 % del MOQ** → se pide eso. No llega → se **sube al 80 %** (en master cajas) **sólo si**
  la cobertura queda dentro del tope del proveedor (`moq_meses_max`, 12). Ni así, o sin proyección → **no se pide** (0).
- Vive en `_pedImpMoqCalc` y la aplica `_pedImpMcOf`, así que vale en la pantalla, el Excel y los dos PDF. Una
  cantidad puesta **a mano** (`mcOverride`) gana siempre. El 80 % es `Importados_Config.moq_pct` (default 0,8), editable en
  **⚙ Generales → «MOQ: mínimo a llegar (%)»**; llega al front como `_NAC_TASAS.moq_pct` (v24.56).
- **PDF para Damián = 3 hojas**: 1) **Pedido <prov> dd/mmm** (sólo UNIDADES, sin MC ni inner; los totales de FOB,
  m³ —1 decimal— y los meses del máximo en su propia fila arriba del rótulo; «Llegan» sólo si algo viene en camino,
  con la fecha en el rótulo si es una sola; el aviso «↑ 80% MOQ» a la derecha de la tabla; separadores finitos
  Foto|Stock y Pedido|FOB) · 2) **Sin pedir**, por meses de stock, con «Por qué» · 3) **Discontinuos** del proveedor
  (`Importados.activo = false`, con el motivo de `Articulos_Discontinuados`). Sin textos de explicación.
- **v25.3 (Thomas, 30/09): el PDF para Damián va en A4 VERTICAL y lleva la columna Marca** (LK / CH / Loke, de
  `Importados.marca`) en las 3 hojas; reemplaza la chapa de planta pegada al código. Medido: la hoja del pedido
  mide 708 px de 733 útiles con el aviso del MOQ (el renglón más ancho). No volver a ponerla horizontal.
- **v25.13 (Thomas, 30/09): el PDF para Damián va AGRUPADO POR TIPO DE PRODUCTO** (las marcas del mismo producto
  juntas: Colador Ø 8 cm = 026 LK · 824 CH · 110 Loke; el grupo va donde cae su artículo más urgente, adentro LK · CH ·
  Loke, raya gruesa al empezar cada grupo) **y marca «INAL»** debajo del código. Fuentes: `GV_Producto_Tipo` (su Excel
  de equivalencias) y `GV_Articulo_INAL` (certificados), resueltas por la vista `gv_imp_articulo_extra`.
  **La «libre circulación» ahora es «Autorización de Impo»: `Importados_Config.autoriz_impo_pct` (0,007) × FOB de lo
  que lleva INAL** (base «inal» en el reparto por artículo). Sin el dato INAL va sobre todo el FOB (lo conservador).
  **Va en los TRES modos** (consolidada, contenedor y avión; Thomas D7). Loke 111 y 112 llevan INAL (D6, sin
  certificado cargado todavía). Aplicado el 30/09: 321 tipos, 94 INAL, 59 importados con INAL. `sql/gv_imp_tipo_inal_v2513.sql`.
- Los tests de pantalla que no miden el MOQ lo ponen en 0 (`_NAC_TASAS.moq = 0`); la regla la miden
  `tests/pedimp-prioridad-damian.cjs` (D) y `tests/pedimp-moq-proy.cjs` (B).

### ⚠ v24.57 (Thomas, 29/09): la CABECERA de Pedidos Importación es de 3 filas — «ocupa mucho espacio»

Solapas y proveedores en **UNA fila que se desliza** (antes 4 y 6 filas en el celular); la alerta es **⚠N**
(el «N con < 4 meses» va en el `title`); **Excel · Cargar pedido ya hecho · ⓘ Cómo se usa** viven en el menú
**⋯**; la fecha del portal es un chip 📅; totales + nacionalización (desplegable, m³, mín, ⚙) en una barra.
A 390 px la tabla del primer proveedor arranca en y≈635. `tests/pedimp-cabecera-compacta.cjs`.

⚠ **v24.58 (Thomas): el MÍNIMO de 25k ya NO se muestra** — *"es una norma general, no algo que sí o sí hay que
cubrir"*. Se fueron el chip «No llega solo / ⏳ para el mínimo», el input «Mín u$s» y los campos del ⚙. El dato
(`min_usd`) sigue en la base, sin uso en pantalla. No volver a ponerlo como requisito del pedido.
El **consumo por mes** (proy × FOB) quedó en el encabezado de cada proveedor (v24.59, `.pedimp-consumo`) y el total en la barra de arriba (v24.60, `.pedimp-consumo-tot`).
Filas bajas en la tabla (v24.62): 📦 / 📥 como íconos lado a lado, «Cartel» y «Web» al lado bajo la fecha de
reingreso, celdas `.pedimp-tbl` con 4px de relleno. **64 → 45 px por artículo** a 390 px (el test mide ≤ 50).

## ⚠ REGLA (Thomas, 2026-09-30, v25.4): el INSUMO importado no tiene empresa y se pide para 12M

- **Insumo** = parte de `vista_importados_partes` cuyo propio código NO está entre los terminados que la usan
  (1000900, 505C, 523C, 587C, 1546903; **590E no**: se vende). `esInsumo` en `ocgFetchImportados`.
- **Sin empresa**: `_impPlantaVista` y `_pedImpEmpFoto` devuelven vacío. En la base, `Importados.marca` y sus baches
  son **`Mixto`** (v25.9, Luis: *"debería ser Mixto desde el vamos"*), igual que los movimientos de insumos. `Mixto` se lee
  como LK en todo lector (no es CH). Centinela: `select * from public.gv_importados_insumo_con_empresa;` — vacía = todo bien.
  `sql/gv_importados_insumo_mixto_v2509.sql`.
- **Objetivo = (meses del proveedor + 2) × proyección de los productos que lo usan** (`INSUMO_MESES_PRODUCTO`),
  también en el tope del MOQ. Chip **«12M»** al lado del código.
- **Tocar Stock** abre el desglose (`pedImpStockDesglose`): propio · cada insumo (`gv_importados_stock_insumos`) ·
  parte · productos ya armados, y abajo los productos con su proyección. En un insumo, tocar Proy abre lo mismo.
- **GV lee el inventario de GP2** (mismo proyecto, schema `GP2`) por **`gv_gp2_inventario`** (detalle) y
  **`gv_gp2_stock_componente`** (total por componente), sólo lectura. Al 30/09: 1.137 filas, 5 con stock.
  **No hay vínculo** entre el código importado (1000900) y el componente GP2 (D1 «Espiral Sacacorcho»?): no se adivina.
  `sql/gv_gp2_inventario_v2501.sql`, `tests/pedimp-insumo-12m.cjs`.

## ⚠ REGLA (Luis, 2026-10-01, v25.61): el stock de un importado SUMA el stock GP2 de su componente — y puede ser NEGATIVO

**Luis:** *"para elaborar ciertos artículos importamos partes … tenemos que considerar partes que tenemos en stock
(insumo) que se van a registrar en GP2"* · D12: *"si tenemos más unidades comprometidas de lo que hay en stock, stock
negativo para usos prácticos de importación"*.

| importado | componente GP2 | factor |
|---|---|---|
| 587C · 505C · 1546903 · 523C · 1000900 | Z23B · Z23A · C13 · E13 · D1 | 1 |
| 323E / 838E | **un pozo, dueño 838E**: GRJ31 + 323E y 838E terminados de GP2 + parte 323ES — los dos lo ven, **0 % 323E / 100 % 838E** | `GV_Piezas_Reparto.peso_fijo` (v28.44, Luis 07/10) |
| 942E · 943E · 944E · 945E · 948E | Z47 + Z47-M505D + 942E · Z44 + Z44-M505C + 943E · Z48 + Z48-M505 + 944E · Z49 + Z49-M505F + 945E · Z45 + Z45-M505B + 948E | 1 c/u, se suman (v26.00) |
| 522ES | GRJ33 | 1 |
| 702E · 106E | 702 + 702E + 102E · 723 + 106E | 1 c/u (v26.03) |

- Vive en **`GV_Importados_Equiv_GP2`** (agregar uno = un `insert`). Unidad por unidad; cuenta el stock GP2 del
  componente (sector + talleristas + PS, `gv_gp2_stock_componente`) y se SUMA al depósito de insumos de Virgilio.
- ⚠ **v26.05 (Luis, 02/10): sólo la PARTE CERVANTES de GP2** (*"tiene que sumar lo que está en GP2 pero sólo en la
  parte de Cervantes"*). Desde GP2 v1.224.0 GP2 tiene depósitos propios EN Virgilio (`virgilio_sector`, «Virgilio
  (Distribución)», Bolsas Plásticas «en Virgilio»): eso ya está en Virgilio y no se suma. `gv_gp2_inventario.parte`
  = cervantes / terceros / virgilio; `gv_gp2_stock_componente` saca `virgilio` (terceros sigue contando). Impacto al
  02/10: 0. `sql/gv_gp2_stock_solo_cervantes_v2605.sql`.
- ⚠ **`GV_Importados_Equiv_GP2` NO es una equivalencia de códigos** (v29.74): dice qué piezas de Cervantes
  **aportan** stock a un importado, 1→N con factor (942E ← Z47 + Z47-M505 + 942E). La equivalencia de códigos
  vive en **`GP2.insumo_equivalencia`** y es otra pregunta: no se fusionan. Al 02/10 difieren en códigos (599E/599ES→GRJ32, 522E→GRJ33, 590ES→PINCEL590 sólo en la de GP2; 94xP vs
  94xE). Unificarlas queda para después (Luis, 02/10).
- `gv_importados_ordenes` suma dos columnas AL FINAL: **`stock_gp2`** y **`stock_total_neto`** (sin el `greatest(…,0)`
  + GP2). `stock_total` / `stock_actual` / `stock_cajas` **no se tocaron** (los leen otros). El módulo de importación
  lee el neto: la cuenta de «a pedir», los meses y la pantalla muestran el negativo; la celda Stock lleva **🏭+N**.
- Al 01/10: 22 códigos en negativo (583E −210, 969E −204…); 505C +21.605, 587C +20.377, 323E +600 (444 neto).
- ~~**v26.99 (Thomas, 06/10): GRJ31 es un POOL COMPARTIDO.**~~ **RETIRADO en la v28.43 (Luis, 07/10: *"habíamos determinado que 100 % iba para el 838E"*)**: ver la regla «PIEZAS E INSUMOS COMPARTIDOS» más abajo. Texto viejo: Tanto 323E como 838E cuentan **GRJ31 (totalidad) + 323E terminado (totalidad) + 838E terminado (totalidad)**, los tres a factor 1 — así los dos ven el pool neteado por lo ya despachado como cualquiera de los dos (3000 − 600 − 396 = 2.004 para ambos). La leyenda del pop-up los lista a los tres (se arma sola de `GV_Importados_Equiv_GP2`). **El 323ES ya NO ve GRJ31** (*"no va más"*): se borró su fila `(323ES, GRJ31)`. Esto **RETIRA** la regla D13 (Luis, 01/10, 20/80 + 323ES 100%): Thomas la dio vuelta — no volver al 20/80. Que GRJ31 figure entero en 323E y en 838E a la vez es a propósito (cada ítem ve el pool compartido; no se suman entre sí para comprar). Backup de las 3 filas viejas en el chat de la sesión 01RNVK8H (323E/GRJ31/0,2 · 838E/GRJ31/0,8 · 323ES/GRJ31/1).
- **v26.00 (Luis, D19):** un importado puede tener VARIOS componentes y se suman; los que GP2 todavía no tiene (Z47, Z44-M505C, GRJ33…) cuentan solos cuando se creen (cruce por `upper`). El pop-up los lista todos. ⚠ Si el terminado de GP2 (942E…) se manda a Virgilio, tiene que salir del inventario de GP2 o cuenta dos veces.
- **v26.86 (Luis, 05/10): suma TAMBIÉN el componente de GP2 con el MISMO código** (323E en GP2 = el artículo terminado), factor 1, salvo que ya esté en `GV_Importados_Equiv_GP2` o el código sea dual. Bodegas = todo GP2 menos Virgilio (talleristas incluidos). Lateral `e_mismo`, centinela 323. `sql/gv_importados_gp2_mismo_codigo_v2686.sql`.
- **v26.03 (Luis, 01/10, D23): también suma STOCK DE VIRGILIO de otro código que se convierte en el importado**
  (*"si tengo de eso, no tengo que salir corriendo a comprar"*): tabla **`GV_Importados_Equiv_Virgilio`** (importado,
  código, empresa, factor) → CTE `conv` de `gv_importados_ordenes` → columna **`stock_conv`** (dentro de
  `stock_total_neto`). Cuenta el disponible (bruto − pedido, piso 0) × UxB del código de origen. Hoy: 702E ← 102E LK +
  702 LK; 106E ← 723 CH. Celda **🔁+N** y fila «🔁 Se convierte» en el pop-up. Puede contar también en la fila propia del
  origen (102E), a propósito. Y el insumo 522ES cuenta para el importado 522ES (además del 522E). `sql/gv_importados_equiv_virgilio_v2603.sql`.
- Centinelas 269 y 270. `sql/gv_importados_equiv_gp2_v2561.sql`, `tests/pedimp-equiv-gp2.cjs`.

## ⚠⚠ REGLA (Luis, 2026-10-07, v28.43): PIEZAS E INSUMOS COMPARTIDOS — cada artículo toma su % por E.M. del mes

**Luis:** *"633E→942E, 630E→943E, 637E→944E, 636E→945E, 631E→948E tienen que contemplar las mismas piezas … pero
proporcionalmente. Lo que determina la proporcionalidad es la estadística madre del mes (dinámica) · 323E/838E: 100 % para el
838E · 438E y 439E que contemplen los insumos que tenemos en Virgilio, de la misma forma · para determinar si le compramos a los
chinos y para avisar en la página que no tenemos stock"*.

| grupo (dueño de las piezas) | lo comparten | qué se reparte |
|---|---|---|
| 942E · 943E · 944E · 945E · 948E (LK) | 633E · 630E · 637E · 636E · 631E (CH) | piezas GP2 (`GV_Importados_Equiv_GP2` + mismo código) y la parte 94xP de Virgilio |
| 438E · 439E | el mismo código en LK y en CH | el insumo de Virgilio (`gv_importados_stock_insumos`) |
| 838E (dueño) | 323E LK | **peso fijo 0-100** (v28.44): GRJ31 + 323E y 838E terminados de GP2 (netea con el Art Term de Cervantes) + parte 323ES; los dos lo ven, el 838E se lleva el 100 % |

- El miembro usa las piezas del **dueño** de su pozo (`gv_importados_ordenes.piezas_grupo`; el pop-up del 323E lista GRJ31 con 0 %).
- Quién comparte vive en **`GV_Piezas_Reparto`** (grupo, cod_art, empresa, `peso_fijo`); agregar uno = un `insert`.
- El % lo calcula **`gv_piezas_reparto_share`**: E.M. de `gv_proyeccion_articulo` (proy_lk / proy_ch según la empresa) × UxB
  de esa empresa (sin UxB, la del dueño del grupo: 633E y 637E) = unidades/mes; % = las suyas ÷ las del grupo. `peso_fijo`
  pisa la E.M. Sin E.M. en todo el grupo → partes iguales. Es dinámico: cambia solo con la Est. Madre.
- **Importación** (`gv_importados_ordenes`): `stock_gp2`, `stock_insumos`, `stock_total` y `stock_total_neto` ya vienen × su %;
  columnas nuevas `piezas_share`, `piezas_reparto`. `vista_importados_stock_parte` también. El pop-up de stock lo dice
  (fila «🔀 Piezas e insumos compartidos: le toca el N %»).
- **Cartel de la página** (`gv_reingresos_feed`): ahora cuenta como stock las **piezas de Cervantes** y los **insumos de
  Virgilio** de TODO importado (antes sólo la parte de `Importados_Stock_Parte`), cada uno con su %. **El cartel es sólo de
  importados y lo controla Luis con los botones** (v28.44, D4/D5): el que comparte sin ser importado (633E…) NO lleva cartel
  automático, y `GV_Reingreso_Excluido` no se toca.
- **438E, 439E y 944E están en `GV_Reingreso_Excluido`** a propósito (Luis, D4: los carteles los maneja él). No proponer sacarlos.
- Al 07/10: 942E 87 % / 633E 13 % · 943E 94 / 630E 6 · 944E 80 / 637E 20 · 945E 65 / 636E 35 · 948E 82 / 631E 18 ·
  438E LK 52 / CH 48 · 439E LK 32 / CH 68. Medido: el cartel LK bajó de 1,2 s a 0,7 s, CH subió de 0,3 s a 0,5 s.
- Centinelas 362-366. Backups `zz_backups."GV_Backup_Equiv323_838_20261007"` y `"GV_Backup_ReingresosFeed_def_20261007"`.
  `sql/gv_piezas_reparto_em_v2843.sql`, `tests/pedimp-piezas-reparto.cjs`.
- **v25.71 (Luis, 01/10):** el pop-up «📦 Stock — <cód>» es más grande y dice el **código del componente** de Cervantes
  (fila «🏭 Cervantes (GP2) · GRJ31» y chip en el encabezado; con factor ≠ 1, «le toca el 20 % de 4.000 u»). Lee
  `GV_Importados_Equiv_GP2`; si falla, se ve como antes. `tests/pedimp-stock-desg-gp2.cjs`.

## ⚠ REGLA (Luis, 2026-09-30, v25.14): RECIBIR un importado en CERVANTES — no entra al stock de Virgilio, avisa en GP2

- En 📥 RECIBIR el destino **🏭 Cervantes** va **primero** de la lista. Para un insumo va en **unidades**.
- `gv_imp_recibir` con destino `cervantes` **no escribe `Movimientos_Stock`**: inserta en **`"GP2".ingreso_virgilio`**
  (estado `pendiente`), y la portada de GP2 (`GP2_MODULOS.html`) muestra el cartel **«VIRGILIO DICE QUE TE LLEGÓ ESTO…
  CONFIRMALO Y UBICALO»**. Confirmar y ubicar del lado de GP2 **falta implementar** (columnas `confirmado_*`,
  `ubicacion_id`, `componente_id` ya están).
- **↩ Anular** pasa la fila a `anulado`, y **frena si Cervantes ya confirmó**.
- ⚠ No hay vínculo código importado ↔ `GP2.componente`: no se adivina.
- `sql/gv_imp_recibir_cervantes_v2511.sql`, `tests/imp-recibir-cervantes.cjs`.
- **v25.15 (Luis, 30/09): y al revés — lo que Virgilio le ACEPTA a GP2** vive en **`"GP2".aceptado_virgilio`** (la leen
  GP2 y GV): una fila por recepción de insumo que vino de Cervantes (`Movimientos_Stock` `recepcion_insumo`, ref Cervantes),
  con `aceptado` = ya tiene código real (no `TMP-`). La escribe `gv_gp2_aceptado_sync()` (cron `gv-gp2-aceptado-sync`,
  cada 10 min, poda lo que desaparece). Al 30/09: 24 filas, 7 aceptadas, 17 con TMP. **323ES quedó Mixto.**
  `sql/gv_gp2_aceptado_virgilio_v2515.sql`.
- **v29.60 (Luis, 13/10): y VE LAS CATEGORÍAS DE INSUMOS** — cuarta tabla espejo, **`GP2.virgilio_insumo_categoria`**
  (clave, nombre, emoji, orden, activa), bloque 4 de `gv_gp2_espejo_sync`. Con eso GP2 → Stock general → pestaña
  **Virgilio** filtra «Insumos de Virgilio sin asignar» por **las mismas categorías de acá**, con sus nombres
  (`virgilio_insumos_sin_match_bundle` devuelve `categorias` y cada fila su `cat_nombre`). ⚠ **El nombre de una
  categoría no se escribe en el front de GP2**: su mapa a mano (`VINS_RUBRO`) estaba desfasado en **4 de 6** —
  decía «Plásticos» por «Bolsas plásticas», «Flejes» por «Flejes y alambres», y no conocía «Sector Crudo» ni
  «Sector Procesado». Al agregar una categoría en `Insumos_Categorias`, GP2 la ve sola en ≤ 10 min.
  `sql/gv_gp2_espejo_categorias_v2960.sql` · GP2 `db/migracion_virgilio_categorias_20261013.sql`, CONOCIMIENTO 4kn.
- **v25.17 (Luis, 30/09, D5): GP2 ve el stock de insumos y el Mapa de Virgilio**, en tres objetos de **solo lectura** del
  schema GP2 (así no rompe su Regla 0): `virgilio_insumo_stock` (desde la v29.89 una **vista en vivo**, no una copia),
  `virgilio_insumo_ubicacion` y `virgilio_lugar`. Las
  llena `gv_gp2_espejo_sync()` (cron `gv-gp2-espejo-sync`, c/10 min, reescribe sólo si cambió el md5). Luis: *"que los
  dos tengan acceso a los datos y que puedan hablar"*; el vínculo de códigos (D3) va después. `sql/gv_gp2_espejo_v2517.sql`.

