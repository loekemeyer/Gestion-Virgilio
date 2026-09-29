#!/usr/bin/env node
/**
 * tests/fc-acuerdo-desglose-copia.cjs — candado ESTATICO sobre la copia del
 * panel de LK que se sirve desde acá (`admin/`).
 *
 * El "Acuerdo Cliente" de la ficha se toca y abre el desglose (Luis,
 * 29/09/2026). El fuente vive en `pagina-LK-copia` (admin.js + css/admin.css)
 * y acá hay una COPIA: una re-sincronización desde el origen que se olvide de
 * este cambio lo borra sin que nada avise. La prueba que corre la pantalla
 * está en ese repo (tests/fc-acuerdo-desglose.cjs); acá sólo se verifica que
 * la copia lo siga teniendo.
 *
 * Correr:  node tests/fc-acuerdo-desglose-copia.cjs
 */
const fs = require("fs");
const path = require("path");
const raiz = path.join(__dirname, "..");
const js = fs.readFileSync(path.join(raiz, "admin", "admin.js"), "utf8");
const css = fs.readFileSync(path.join(raiz, "admin", "css", "admin.css"), "utf8");
const html = fs.readFileSync(path.join(raiz, "admin", "admin.html"), "utf8");

const fallas = [];
const ok = (c, m) => { if (!c) fallas.push(m); };

// A. la puerta: la celda del panel llama al desglose
ok(/fc-acud-click[^]{0,120}onclick="fcAcuDesglose\(\)"/.test(js),
   "A: la celda Acuerdo Cliente no abre el desglose (falta fc-acud-click + onclick)");
ok(!/'<tr><th>Acuerdo<br>Cliente<\/th><td class="fc-h-big">'/.test(js),
   "A: volvió la celda vieja, sin puerta al desglose");
// B. la cuenta paso por paso
["Índice de lista", "Dto x volumen", "Dto pago contado", "Cotizador", "Flete + comisión"]
  .forEach((p) => ok(js.includes(p), `B: falta el paso "${p}" del desglose`));
ok(js.includes("no encadenados"), "B: falta la aclaración de que flete y comisión no se encadenan");
// C. se muestran los numeros de la RPC, no un recalculo que redondea distinto
ok(/o\.cheque != null/.test(js) && /o\.recibo != null/.test(js) && /o\.factor != null/.test(js),
   "C: el desglose recalcula en vez de usar cheque/recibo/factor de la RPC");
ok(/cheque: a\.cheque, recibo: a\.recibo, factor: a\.factor/.test(js),
   "C: la puerta no le pasa los valores de la RPC");
// D. el CSS del pop-up viaja con la copia, y con SU nombre: .fc-acu-box ya
//    existe y es otra cosa (las tarjetas de la card "Acuerdo").
[".fc-acud-ov", ".fc-acud-box", ".fc-acud-tab", ".fc-acud-click"]
  .forEach((c) => ok(css.includes(c), `D: falta ${c} en admin/css/admin.css`));
ok(/\.fc-acud-box\s*\{[^}]*width:\s*max-content/.test(css),
   "D: el pop-up no se ajusta al ancho del dato (falta width: max-content)");
// E. el cache-busting de la copia acompaña al cambio
const vjs = (html.match(/admin\.js\?v=(\d+)/) || [])[1];
const vcss = (html.match(/css\/admin\.css\?v=(\d+)/) || [])[1];
ok(vjs && Number(vjs) >= 23496, `E: admin.js?v= quedó viejo (${vjs}): el celular sigue con el JS cacheado`);
ok(vcss && Number(vcss) >= 23496, `E: css/admin.css?v= quedó viejo (${vcss})`);

if (fallas.length) {
  console.error("fc-acuerdo-desglose-copia: ROJO\n  - " + fallas.join("\n  - "));
  process.exit(1);
}
console.log("fc-acuerdo-desglose-copia: OK — la copia de admin/ mantiene el desglose del Acuerdo Cliente");
