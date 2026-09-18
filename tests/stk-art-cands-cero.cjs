/* Regresión v19.79 (problema 425) — Thomas: "071 dice que tengo 1 pedida pero en el detalle no
   hay ninguna. Es porque el detalle busca 71 (sin el 0) y el código es 071? están chocando
   los códigos". Exacto, y al revés de lo que parece:

   - `gv_demanda_pedidos.articulo` guarda el código como lo escribió ISIS o la página → "071".
   - la fila de Stock trae el código SIN ceros → "71" (vista_stock_procesada los pela).
   - el pop-up pedía `articulo=in.(71,71L)` → 0 filas → "Ningún pedido pidió 71 en la base de
     picking", con la columna diciendo 1.

   Es la regla del dueño del 12/09: para MOSTRAR el cero va siempre; para BUSCAR tiene que dar
   igual. `_stkArtCands` devuelve las variantes y los tres lookups las usan. Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }
(async () => {
  const b = await chromium.launch(); const p = await b.newPage();
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  const r = await p.evaluate(() => {
    const out = { fallas: [] };
    if (typeof _stkArtCands !== "function") { out.fallas.push("no existe _stkArtCands"); return out; }
    // el caso de Thomas: la fila trae "71", la base tiene "071" → las dos tienen que estar
    const c71 = _stkArtCands("71");
    out.c71 = c71;
    if (c71.indexOf("71") < 0)  out.fallas.push("_stkArtCands('71') no incluye 71");
    if (c71.indexOf("071") < 0) out.fallas.push("_stkArtCands('71') no incluye 071 — es el que está en la base");
    // y al revés: si la fila viniera con ceros, tiene que buscar igual el pelado
    const c071 = _stkArtCands("071");
    out.c071 = c071;
    if (c071.indexOf("71") < 0 || c071.indexOf("071") < 0) out.fallas.push("_stkArtCands('071') no cubre las dos formas");
    // la "L" de los artículos de Loeke que vende Chef (438E / 438EL) no se perdió
    const c438 = _stkArtCands("438E");
    out.c438 = c438;
    if (c438.indexOf("438E") < 0 || c438.indexOf("438EL") < 0) out.fallas.push("_stkArtCands('438E') perdió la variante con L");
    // no repite
    if (new Set(c071).size !== c071.length) out.fallas.push("_stkArtCands devuelve repetidos");
    return out;
  });
  await b.close();
  if (errs.length) { console.error("pageerror: " + errs.join(" | ")); process.exit(1); }
  if (r.fallas.length) { console.error("FALLA stk-art-cands-cero:\n - " + r.fallas.join("\n - ")); process.exit(1); }
  console.log("OK stk-art-cands-cero: 71 y 071 buscan lo mismo · " + JSON.stringify(r.c71));
})();
