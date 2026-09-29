/* v23.93 (Luis, 29/09) — el panel supervisor pierde DOS puertas y le muda una a Configuracion.

   Textual: *"Saca Pedidos sin cargar en ppp y faltantes facturados sin completar / Completar
   datos de producto mandalo a configuracion"*.

   Candado ESTATICO, como tests/ppp-sin-a-programar.cjs: lo que se saca es la PUERTA, no la
   funcion — stkOpenNpFaltan y stkOpenFaltFact siguen en el archivo a proposito (mismo criterio
   que gv_ppp_np_desarmar en la v18.77). Por eso el test no busca la funcion: busca el onclick.

   Y la mudanza tiene DOS mitades que hay que medir juntas, o se pierde el modulo:
     1. el boton ya NO esta en el panel supervisor (no queda un onclick="openDatosProducto()")
     2. el boton SI esta en Configuracion, via cfgGo(openDatosProducto), CON su #dpBadge
        (dpLoadBadge() sigue corriendo al entrar y escribe sobre ese id: sin el id, el badge
        se dibuja en la nada y nadie se entera de los articulos sin m3).

   Sale 1 si falla. */
const fs = require("fs"), path = require("path");
const HTML = path.join(__dirname, "..", "index.html");
// latin1: index.html tiene un byte NUL adentro y leerlo como utf8 lo rompe (CLAUDE.md).
const s = fs.readFileSync(HTML, "latin1");
const fallas = [];
const cuenta = (aguja) => { let n = 0, i = 0; while ((i = s.indexOf(aguja, i)) >= 0) { n++; i += aguja.length; } return n; };

// A) las dos puertas que se fueron
for (const [fn, nombre] of [["stkOpenNpFaltan", "Pedidos sin cargar en PPP"],
                            ["stkOpenFaltFact", "Faltantes facturados sin completar"]]) {
  const n = cuenta('onclick="' + fn + '()"');
  if (n) fallas.push("volvio el boton de «" + nombre + "» al panel (" + n + " onclick)");
  else console.log("ok   sin puerta a «" + nombre + "»");
}

// B) «Completar datos producto» salio del panel...
const enPanel = cuenta('onclick="openDatosProducto()"');
if (enPanel) fallas.push("«Completar datos producto» sigue en el panel supervisor (" + enPanel + " onclick)");
else console.log("ok   «Completar datos producto» ya no esta en el panel");

// ...y esta en Configuracion, adentro del overlay, con su badge
const iCfg = s.indexOf('id="configOverlay"');
const iFin = s.indexOf("</div>\n  </div>", iCfg);
const cfg = iCfg >= 0 ? s.slice(iCfg, iFin > iCfg ? iFin : iCfg + 20000) : "";
if (!iCfg) fallas.push("no se encontro el overlay de Configuracion");
if (cfg.indexOf("cfgGo(openDatosProducto)") < 0)
  fallas.push("«Completar datos producto» no quedo en Configuracion (falta cfgGo(openDatosProducto))");
else console.log("ok   «Completar datos producto» esta en Configuracion");
if (cfg.indexOf('id="dpBadge"') < 0)
  fallas.push("el boton de Configuracion se quedo sin #dpBadge: dpLoadBadge() escribe en la nada");
else console.log("ok   #dpBadge viaja con el boton");
if (cuenta('id="dpBadge"') !== 1)
  fallas.push("#dpBadge aparece " + cuenta('id="dpBadge"') + " veces: tiene que ser una sola");

// C) el badge de «Pedidos sin cargar en PPP» ya no se pide al entrar (su boton no existe)
if (s.indexOf("  try { npFaltanLoadBadge(); } catch (_e) {}\n  try { qbpLoadBadge(); }") >= 0)
  fallas.push("showSupervisor sigue pidiendo npFaltanLoadBadge(): son 3 fetch para un boton que no esta");
else console.log("ok   showSupervisor ya no pide el badge del boton que se fue");

// D) las funciones SIGUEN en el archivo (se saca la puerta, no el modulo)
for (const fn of ["stkOpenNpFaltan", "stkOpenFaltFact", "npFaltanLoadBadge"]) {
  if (s.indexOf("function " + fn + "(") < 0) fallas.push("se borro la funcion " + fn + "(): solo iba la puerta");
}

for (const f of fallas) console.log("FALLA " + f);
if (fallas.length) { console.error("\nsup-panel-v2393: " + fallas.length + " falla(s)."); process.exit(1); }
console.log("\nsup-panel-v2393 OK — dos puertas menos y «Completar datos producto» en Configuracion.");
