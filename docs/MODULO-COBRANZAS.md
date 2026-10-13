# Cobranzas (cobranzas.js) y conciliación bancaria

> Movido de `CLAUDE.md` el 2026-10-13 (poda de reglas, pedido de Luis) para que no cargue en cada sesión.
> Es documentación operativa VIVA del módulo, no se resume: leer ENTERA antes de tocar este módulo.

## ⚠ REGLA (Luis, 2026-09-29, v23.98): el submódulo COBRANZAS vive en `cobranzas.js`, y la deuda se consolida por CUIT

**Luis:** *"submódulo de cobranzas … debería tener pestañas dentro, empezando con la de búsqueda de
clientes … se busca un cliente (lk o ch) y se abre una ficha con esos datos con deuda consolidada"*.

Pantalla propia **`openCobranzas()`** (botón «💳 Cobranzas (nuevo)» del panel supervisor), 4 pestañas;
la primera busca por nombre, código o CUIT y abre la ficha: deuda consolidada, desglose por empresa,
comprobante por comprobante con su pago, cuenta corriente y la escala de descuentos con el escalón que
corresponde a los días marcado. Lee lo que ya existía (`gv_cobranza_clientes`, `gv_cobranza_cliente`,
`gv_cobranza_cuenta`, `cobranzas_escalones`) más **`gv_cobranza_clientes_cuit()`**, que es lo único
nuevo y es lectura.

> ## **La deuda consolidada se arma por CUIT. NUNCA por nombre.**

Un cliente tiene códigos distintos en cada empresa (**LK 4045 / CH 2211**) y la razón social viene con
el sufijo de sucursal que le pega ISIS: *"Bazar Monica S. CAP I SECC IV"* (LK) y *"Bazar Monica SRL"*
(CH) son **el mismo cliente**. Agrupar por nombre lo parte en dos, y dos nombres parecidos de clientes
distintos los fusiona. Es la regla v13.76 (*"el cod cliente no significa nada, sólo el CUIT vale"*)
aplicada a cobranzas. **Sin CUIT el código va solo** y la ficha lo dice con el chip «sin CUIT»: no se
adivina. Medido el 29/09: **69 CUIT tienen código en las dos empresas**.

⚠ **Está en `cobranzas.js`, no en `index.html`**, y se carga con `?v=` atado a `APP_VERSION` (entró a
`SIGUEN_APP_VERSION` de `scripts/bump-version.cjs` y `tests/version-tokens.cjs`). **Al sacar cualquier
módulo nuevo del index, ese es el camino**: el index ya va por 63.000 líneas, 4,4 MB y un byte NUL
adentro.

⚠ **El módulo de Pedidos Importación vive en `importacion.js` (v24.65); al tocar importados, editar ahí.** Mismo patrón (script clásico, todo global, `?v=` atado a `APP_VERSION`); los tests que extraen funciones de importados leen `index.html` + `importacion.js`.

⚠⚠ **`window.sb`**: `const sb = createClient(...)` vive **adentro de la IIFE** del login, así que un `.js`
externo no lo ve (`sb is not defined`, y el módulo cae a DEMO sin decir por qué). Se expone el **mismo**
objeto —no hay segundo cliente ni segunda sesión—. Cualquier módulo que salga del index cuelga de ahí.

⚠ **El `button{width:100%;padding:16px;font-size:22px}` global del index (línea ~26) también muerde acá**:
sin `#cbzOv button{width:auto;margin-top:0;…}` el botón Cerrar sale de una pantalla de ancho. Es el mismo
pozo que el pop-up de Importados (v23.93).

⚠⚠ **v26.04 (02/10): «Deuda a cobrar / Cobranzas» y «Cobranzas (nuevo)» son UNA pantalla, 💳 Cobranzas.**
*"Las dos pestañas de Cobranzas son lo principal, agregale las del otro pero ponelas después"*. Botonera:
**👤 Clientes · 🏦 Conciliación · 📐 Escala │ 📒 Cuenta corriente · 🗂 Facturas ISIS · 💵 Valor por NP · 🔍
Facturación vs ISIS · 📦 Facturable ya · 🕵 Agente · 🏦 Bancos**. Las 7 viejas (`vieja: true` en `_CBZ_TABS`)
las sigue dibujando index.html (`cobrosRenderTab`) adentro de `#cobrosBody`, y **un `cbzRender` posterior no
las rehace** (borraría el filtro tipeado). `openCobros(tab)` abre la unificada en esa pestaña (Facturación →
«🔍 Cruce con ISIS» sigue abriendo `cruce`); sin cobranzas.js cae a la pantalla vieja (`_openCobrosViejo`).
Se fueron las pestañas vacías «A reclamar» (= 🕵 Agente) y «Recibos». Lo que se solapa (📒 Cuenta corriente
vs la ficha del cliente, 🏦 Bancos vs Conciliación) queda a decisión de Luis. `tests/cbz-integra-cobros.cjs`.

⚠ Si la base no contesta, la pantalla muestra datos **DEMO** con un chip rojo que lo dice, en vez de
ceros — regla *"una lectura ROTA no es un CERO"*.

### La ficha se arma con `gv_cobranza_ficha(emp, cod)` — tres fuentes, una llamada (v24.3)

**Luis, 29/09:** *"tenemos la data de la deuda que se sube para la cuarentena, tenés acceso a la
facturación y a la conciliación. tratá de conectar esas fuentes a la ficha"*.

| bloque | fuente | qué aporta |
|---|---|---|
| `deuda` | **`GV_Cobranza_Deuda_Viva`** | el **Excel de deuda de la Cuarentena** (el ancla) + facturas y NC posteriores de ISIS − lo que la **conciliación bancaria** vio cobrado (`pendiente_ancla`, `cancelado_banco`, `recibos_banco`, `origen`) |
| `recibos` | **`GV_Cobranza_Imputacion`** | cada pago del banco contra las facturas que cancela: `dto_tomado` vs `dto_ganado`, retención, `a_reclamar`, `calidad` |
| `entregas` | **`Facturacion_NP`** | lo que Gestión facturó: NP, tanda, m³, día de salida |

⚠ **La empresa de una entrega la da la NP (`gv_emp_de_np`), NUNCA el código de cliente solo.**

⚠ **Los totales de la ficha salen de la RPC, no de la lista** (la lista es el respaldo mientras
carga o si no contesta). La consolidación LK+CH la hace el front: una llamada por código y se suman.

⚠⚠ **PostgREST resuelve una función por el NOMBRE de sus argumentos, no por el orden.** Llamar
`gv_cobranza_cliente({p_empresa, p_cod})` cuando el parámetro se llama **`p_emp`** no da un error de
tipos: da *"Could not find the function … in the schema cache"*, como si la función no existiera.
Antes de escribir la llamada: `select pg_get_function_arguments(oid) from pg_proc where proname = …`.

Medido el 29/09 con INC (LK 1651): **27 ms como `authenticated`** (timeout del rol: 8 s), y los
números coinciden con la pantalla. `sql/gv_cobranza_ficha_v2403.sql`, §3.v2403.

**Chequeo:** `node tests/cbz-ficha-cliente.cjs` · `select count(*) from (select cuit from
public.gv_cobranza_clientes_cuit() group by cuit having count(distinct empresa)=2) z;` — 69 al 29/09.
`sql/gv_cobranza_clientes_cuit_v2398.sql`, §3.v2398.


### ⚠ v24.37: la CONCILIACIÓN se hace subiendo el extracto del banco — el motor cruza y PREGUNTA lo que no cuadra

Cobranzas → 🏦 Conciliación → (desde v24.41: la tarjeta del banco o su botón chico de carga) se sube el .xls **tal como lo baja el
banco** y `gv_conc_motor` lo cruza (regla → CUIT → apareo con la planilla → importe contra facturas
impagas → pista de la sucursal). Estados: ✅ auto · 🟡 propuesto (un click) · ❓ pregunta (candidatos +
teléfono) · 👤 confirmado · ⚪ no identificado. **📋 Copiar para la planilla** da las columnas A–J.

- El motor **nunca inventa el Nº de recibo** (lo genera ISIS) y **nunca escribe un alias** de pagador:
  eso lo hace la persona al tildar «recordar este CUIT».
- El apareo respeta la **línea amarilla** (`gv_conc_linea`): después de la línea, sólo contra lo proyectado.
- El motor se llama **de a 15** desde la pantalla: 60 movimientos tardan 13 s y authenticated corta a los 8 s.
- Medición y tablas: `docs/SUPABASE-GESTION-VIRGILIO.md` §3.v2437, `sql/gv_conc_motor_cruce_v2437.sql`,
  `tests/cbz-conc-extracto.cjs`.

### ⚠ v24.41 (Luis): la ficha abre en RESUMEN y la conciliación son CUATRO botones con pop-up

- **📋 Resumen** = la planilla de cobranza del Excel, por operación (juego de facturas): facturas y NC ·
  pagos con su ponderación (`días × pagado / total pagado`) · días ponderados · escala con el escalón
  marcado · NC de descuento que falta, en neto + IVA · Deuda / A favor / Saldado. La deuda abierta va
  primero. 🖨 imprime sólo la planilla. Fuente: `gv_cobranza_operaciones(emp, cod)`.
- ⚠ **En una cobrada la escala marca lo que decidió el agente (`dto_ganado`), NO la escala pelada**: con
  plazo pactado (Cuyana, 60 días) pagar en 63 no gana nada aunque la escala diga −5 %. La planilla lo dice.
- **Cambiar de pestaña NO cierra el cliente** (`cbzSetTab` no toca `_cbz.sel`).
- **🏦 Conciliación** abre en **Bancos**: 4 tarjetas-botón → pop-up (📒 Planilla centrada en la línea
  amarilla · 🏦 Extracto cargado · ❔ Sin identificar) + 4 botones chicos para cargar el extracto.
  **✍ Completar datos** junta lo que espera de las 4 cuentas (`gv_conc_pendientes_lista`). El **badge rojo**
  (pestaña y tarjeta) = preguntas + propuestos de `gv_conc_tablero`.
- **La planilla la sube la macro del Excel al guardar**: «↻ Actualizar» la RELEE, no la empuja.
- **«Dif.» en Pagos es un residuo**, no una retención cargada: `1 − pagado / esperado`. Positivo = pagó de
  menos; negativo = pagó de más.
- ⚠ Repintar el pop-up conserva el scroll (el extracto llega después de la planilla y lo repinta entero).

`sql/gv_cobranza_resumen_conc_v2441.sql`, §3.v2441 · `tests/cbz-ficha-cliente.cjs` (h, i) ·
`tests/cbz-conciliacion.cjs` · `tests/cbz-conc-extracto.cjs`.

## ⚠ REGLA (Thomas, 2026-09-26, v22.87-93): la CONCILIACIÓN BANCARIA vive en `GV_Conc_*` y el AGENTE de cobranzas en `GV_Cobranza_Imputacion`

Los 4 Excel de conciliación (Credicoop y Santander, LK y Chef) suben a **`GV_Conc_<Banco>_<Emp>`** por la macro
del Excel al guardar (`docs/conciliacion-bancaria/`); se leen juntos por **`gv_conciliacion_bancaria`** (35 mil
filas: **nunca entera desde el navegador**, va por `gv_cobranza_bancos` paginada). El **agente** cruza cada recibo
con el pedido que pagó (`gv_cobranza_imputar`, DP recibos × pedidos × NC) y deja **`GV_Cobranza_Imputacion`**,
que rehace el cron 103 cada hora si cambió algo; **no se llama `gv_cobranza_imputacion_refrescar` desde el front**
(35 s contra 8 s de timeout). Lo que detecta se ve en Cobranzas → 🕵 Agente y sale por Telegram lun-vie 08:45
(cron 104), **una vez por pedido** (`GV_Cobranza_Avisadas`). Reclamar o hacer nota de débito lo decide una persona.
`banco_movimientos` (importador de Interbanking) tiene 0 filas y quedó plegado: el extracto entra por el Excel.
`sql/gv_cobranza_imputar_v2291.sql`, `sql/gv_cobranza_agente_v2293.sql`, `tests/cob-agente.cjs`.
**Coronitas** (plazo de contado por cliente) = `cobranzas_excepciones`, por **CUIT del padrón** (`GV_Clientes_Direcciones`), no de la factura: una factura de ISIS puede traer el CUIT de otra empresa (v23.18). **Lo detectado no se reclama** (Thomas, 28/09): se avisa al cliente para adelante; por eso se dice «descontado de más», no «a reclamar».
