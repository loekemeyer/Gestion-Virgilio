# Impresión de notas (picking/armado/facturado): helper local y cola

> Movido de `CLAUDE.md` el 2026-10-13 (poda de reglas, pedido de Luis) para que no cargue en cada sesión.
> Es documentación operativa VIVA del módulo, no se resume: leer ENTERA antes de tocar este módulo.

## ⛔ RETIRADO (Luis, 2026-10-02, v26.26): el PROGRAMA de impresión de la v26.12 ya NO existe

**Luis:** *"me quedo con mi helper, sacá lo otro"*. Se sacaron del front la cola en la base (`gv_imp_encolar`), la
pantalla 🧩 Impresoras (PC + impresora + automático por hoja), `tools/impresion/` (GV-Impresion.ps1) y sus tests
(`imp-programa`, `imp-agente-ps`). **La impresión sin cuadro es SÓLO el helper local de abajo.** No volver a poner
una cola de impresión en la base ni un programa que lea de ella. Los objetos de la base (`GV_Impresion_*`, `gv_imp_*`
de impresión) **ya no existen**: Luis dijo «sí» al drop (D4, 02/10); desde la sesión no entró (`execute_sql` y
`apply_migration` se colgaron a los 60 s sin llegar a Postgres) y **lo corrió él en el SQL Editor** el 02/10
(`sql/gv_impresion_programa_drop_v2628.sql`; verificado: 0 funciones, 0 tablas, la clave en
`zz_backups."GV_Backup_Impresion_Clave_20261002"` con RLS). Tenían 0 PC, 0 reglas y 0 hojas.

## ⚠ REGLA (Luis, 2026-10-02, v26.24): el HELPER LOCAL de impresión (127.0.0.1:17777) — por dispositivo, en PDF

Luis tiene un helper en la PC del depósito (servidor HTTP en `127.0.0.1:17777`, imprime PDF con SumatraPDF, reglas
tipo → impresora configuradas EN EL HELPER). Contrato: `GET /` → «Impresion Virgilio OK»; `POST /print?tipo=<picking|
armado|facturado>` con el PDF crudo → `{ ok, tipo, impreso, errores, motivo }`.

- Se conecta en **⚙️ Configuración → botón «🖨️ Helper de impresión»** (v26.28, Luis: *"lo único que tiene que haber
  en Gestión es un botón en configuración «Helper de impresión» que permita conectar con el helper"*): pop-up con el
  estado, el puerto y **Conectar / Desconectar**; Conectar **sólo prende si el helper contesta**. **No va nada más del
  helper en la página**: ni tarjeta, ni hojas de prueba, ni log, ni cartel en la Cola de impresión (`openHelperImpresion`).
  Es **por dispositivo** (`localStorage gv_helper_imp_v1`): desconectado, el navegador NUNCA le pega a 127.0.0.1 (en un
  celular Chrome pediría permiso de red local para nada).
- Entra por **`remitoPrintDoc(inner, tipo, ref)`**: al agregar un camino que imprima una de esas hojas, pasarle el
  `tipo`, o sale por el cuadro aunque el helper esté prendido. Sin tipo = navegador (`_remitoPrintNavegador`).
- El PDF lo arma el navegador: la hoja en un iframe (mismo CSS y `_rmtAutofit`) → `vendor/html2canvas.min.js` (a
  demanda) → jsPDF A4, márgenes 12 mm, varias páginas si hace falta. En FILA, una hoja por vez.
- **A MANO** (botón Imprimir de la Cola, Programación, la estación): helper que no contesta o que no imprimió nada →
  la hoja sale por el navegador. **Más de 60 s sin respuesta → NO se repite** (puede haber salido).
  ⚠⚠ **LO AUTOMÁTICO NUNCA abre el cuadro** (v26.66, ver la regla de abajo): sale sólo por el helper o queda en la Cola.
- **Orden: helper > navegador.** (El programa de la v26.12 se sacó en la v26.26.) Qué sale SOLO lo siguen decidiendo los
  switches de 🖨️ Cola de impresión (auto-imprimir remitos = armado y picking; FACTURADO global).
- Con el helper conectado + el auto de la estación prendidos, la estación arranca sola al abrir GV (`gvHelperVigilar`).
- **Conectar = ESTA PC imprime sola** (v26.30, Luis: *"en la compu que lo tenga abierto … las 3 hojas cuando se
  generan"*): «Conectar» prende la estación (`psSetAuto(true)`: picking al **TP**, armado al terminar cada NP = **TAL**)
  y «Desconectar» la apaga. Un helper conectado antes, sin el switch tocado nunca, la prende solo al abrir GV.
- **El FACTURADO lo imprime la PC del helper, NO la que factura** (v26.32, Luis D3: *"el excel de facturación no se va
  a bajar en la pc que corre el helper"*): la estación lee `Facturacion_NP.facturado_at` (lo pone la base al tildar o
  bajar el Excel en cualquier PC) y lo manda al helper. Sólo lo de HOY; la primera vez arranca desde ahora
  (`ps_lastseen_fac_virgilio`); una vez por NP y día. `facMaybePrintFacturado` (la PC que factura) **ya no imprime ni abre
  el cuadro**. Respeta el switch global FACTURADO de 🖨️ Cola de impresión. Sin la PC del helper abierta no sale; al
  abrirla, sale lo facturado ese día mientras estuvo cerrada.
- **Señal de prueba `IMPT`** (v26.30): un evento en `Registros_Produccion_Virgilio` con `opcion = 'IMPT'`,
  `texto` = picking | armado | facturado y `descripcion` = lo que dice la hoja llega por el MISMO sondeo de la estación
  (cada 12 s) y sale por `remitoPrintDoc` → helper con ese tipo. Sólo en una PC con el helper conectado (una estación
  sin helper no abre el cuadro por una prueba). Ningún lector mira `IMPT` ni dispara triggers; con legajo `0`
  (prueba) no entra en ningún reporte. Para probar una PC nueva:
  ```sql
  insert into public."Registros_Produccion_Virgilio" (legajo, opcion, texto, descripcion, ts_cliente, client_id, gv_app)
  values ('0','IMPT','picking','test picking', now(), 'impt-'||gen_random_uuid(), 'gestion');   -- lo escribe quien tenga el «sí»
  delete from public."Registros_Produccion_Virgilio" where opcion = 'IMPT';                        -- después de imprimir
  ```

- **El FUENTE del helper vive en `tools/helper-impresion/`** (v26.29): C# WinForms, un `.exe` sin instalar ni admin
  (`TcpListener` en loopback), v1.0.0. `compilar.bat` lo compila con el `csc.exe` de .NET Framework 4 que trae
  Windows; `README.md` es el de desarrollo y `LEEME.txt` el de quien lo instala. **No se versionan**: `SumatraPDF.exe`
  (3.6.1 portable 64-bit, ~20 MB, se baja aparte), el `.exe` compilado, la config de cada PC
  (`virgilio-impresion-<PC>.json`: nombres reales de impresoras y PC, el repo es público) ni el log. Cambiar el helper
  = editar ahí, compilar y reemplazar el `.exe` en la PC (la config queda). Las reglas tipo → impresora son de cada PC:
  una PC sin regla para un tipo contesta `ok:false` y esa hoja sale por el cuadro.

- **v26.58 (Luis, 05/10): el helper v1.2.0 NO cambia el contrato** (sólo su ventana: hoja global `papel` en el .json,
  «Opciones avanzadas», minimizar al cerrar). El ping ahora dice `Impresion Virgilio OK v1.2.0`: el front da vivo por el
  **HTTP 200, nunca por el texto** (candado en `tests/helper-impresion-fuente.cjs`; el helper falso del test contesta lo
  mismo que el real). **v26.59: el fuente del repo es el v1.2.0** (lo pasó la sesión local que lo escribe, que no toca
  el repo: cada versión nueva del helper llega por el chat y se sube acá). Contra el v1.0.0 sólo cambian la ventana y el
  aviso de puerto ocupado; `ServidorImpresion` es idéntico. El test exige que la versión del `.cs` y la del README coincidan.

`tests/imp-helper-local.cjs` (helper falso en 127.0.0.1: mide el PDF que le llega, el orden, el fallback y el timeout).

## ⚠⚠ REGLA (Luis, 2026-10-05, v26.66): LO AUTOMÁTICO SALE SÓLO POR EL HELPER — lo que no salió queda en la COLA DE IMPRESIÓN NP

**Luis:** *"solo cuando se conecta el helper salen automaticas. si no esta conectado el helper o si estuvo conectado pero no
responde, no manda a imprimir automaticamente la app sino que figuran en el modulo [Cola de impresión NP]. Que ahi figuren
todas las NPs pasadas y presentes (en buena vista) con los comprobantes que se les puede imprimir porque esta la data (nota de
picking, armado o facturado). En caso de que sea de la tanda, es de la tanda, si es de la NP, es de la NP"*. Caso: al cerrar
el helper, las PC con la estación prendida empezaron a abrir el cuadro de impresión por cada hoja.

| qué | cómo queda |
|---|---|
| puerta única de lo automático | **`gvImprimirAuto(tipo, inner, ref, marca)`**: sin helper conectado no hace nada; con el helper que contesta `ok:false` o no contesta, **no abre el cuadro** (`gvHelperEncolar(..., {auto:true})`). Marca en `Impresion_NP` **sólo si salió** |
| estación (`psPoll`) | antes de todo hace ping al helper; sin helper o sin respuesta **no imprime nada** y corre los cursores a ahora (`_psCorrerCursores`): cuando vuelve no vuelca lo de atrás, queda en la Cola |
| TAL / TP / IMPT / facturado | `psPrintBatch`, `pkHojaImprimir(..., "estacion")`, la señal de prueba y `facPrintFacturado(np, tanda, true)` van por `gvImprimirAuto` |
| marcas en `Impresion_NP` | armado = la **NP** · picking = **`PK <tanda>`** · facturado = **`FAC <np>`** (nuevo) |
| Cola de impresión NP | ⚠ **v27.61 (Luis, 07/10): VOLVIÓ a la de antes** — NP armadas sin imprimir (`gv_vista_cola_impresion`) + hojas de picking pendientes, «Imprimir todas», badge de `vista_cola_impresion` (`openColaImpresion`). Lo de abajo es el **submódulo «📅 Por día · todas las hojas»** (`openColaImpHistorial`, badge propio `colaImpHistBadge` sin puerta) |
| └ submódulo por día | **`gv_cola_impresion_lista(desde, hasta)`** (lectura, anon, ~70 ms 28 días): por **día** (entrega) → **tanda** (la tanda y su 📋 Picking en UNA celda para todas sus NP) → **NP** (📦 Armado, 🧾 Facturado). ✓ hora en lo impreso · rojo pendiente (⚠ +24 h) · azul disponible sin marca · — sin datos. Tocar abre la hoja (`gvHojaPreview`) con Imprimir (a mano: helper o cuadro) y la marca. «🖨️ Imprimir pendientes» del día más viejo al más nuevo |
| pendiente = tiene la data y no tiene marca | picking con TP desde 01/10 · armado con TAL desde 25/08 · facturado con TAL + `facturado_at` desde 05/10 13:00 (antes la marca no existía) |
| badge del panel | pendientes de −21 a +14 días; rojo si alguno hace +24 h; una lectura rota no lo apaga |

- **D5 (Luis, 05/10): lo facturado ANTES del 05/10 13:00 NO es pendiente** (*"dejalos afuera. se buscan y se imprimen
  de forma manual si hace falta"*): antes de esa hora la marca del facturado no se guardaba. No volver a proponer marcarlos.
- **La disponibilidad sale de la base, no de la estación**: picking = TP de la tanda; armado = TAL con resumen o
  `Entregas_Virgilio` vivas (sin `-X`); facturado = `Facturacion_NP.facturado_at` + el resumen del TAL (lo pide la hoja).
- ⚠ **Sin un solo texto del helper en la Cola ni en la estación** (regla v26.28: lo único del helper es el botón de ⚙️).
- ⚠ El `_ci_ev` de la RPC va **`as materialized`**: sin eso el plan lo re-agregaba una vez por fila (**2,4 s → 68 ms**).
- `vista_cola_impresion` / `gv_vista_cola_impresion` quedan en la base sin lector del front.
- Centinelas 311 y 312. `sql/gv_cola_impresion_lista_v2666.sql`, `tests/cola-impresion-np.cjs`, `tests/print-station.cjs`,
  bloque **O** de `tests/imp-helper-local.cjs` (verificado que los tres fallan con la regla rota).
