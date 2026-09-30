/* v24.76 (Luis, 30/09) — "que diga para los que se despachan en expreso la dirección de entrega
   real también en A programar y en Programación". Y el bug que apareció al mirarlo: el Excel ISIS
   ponía la sucursal adivinando por cliente + fecha + ítems, y LK 0179 (sólo 607E, pedido 1506,
   Río Gallegos) salió «Brc Onelli» (Bariloche) porque el 607E estaba en los 4 pedidos del cliente.
   Mide:
     (a) gvDirRealTxt arma "etiqueta · localidad, provincia" sin repetir lo que la etiqueta ya dice;
     (b) los dos chips existen (Programación y A Programar) y usan es_expreso;
     (c) _facXlsArmar busca la sucursal por el ORDER_ID de la NP antes que por la heurística,
         y si la heurística empata con sucursales distintas no adivina.
   Sale 1 si falla. */
const fs = require("fs"), path = require("path");
const src = fs.readFileSync(path.join(__dirname, "..", "index.html"), "latin1");
const utf = Buffer.from(src, "latin1").toString("utf8");
function fn(name) {
  const i = utf.indexOf("function " + name + "(");
  if (i < 0) throw new Error("no está " + name);
  let j = utf.indexOf("{", i), d = 0, k = j;
  for (; k < utf.length; k++) { const c = utf[k]; if (c === "{") d++; else if (c === "}") { d--; if (!d) break; } }
  return utf.slice(i, k + 1);
}
const fails = [];
const ctx = {}; new Function("ctx", fn("_gvNorm") + "\n" + fn("gvDirRealTxt") + "\nctx.f = gvDirRealTxt;")(ctx);
const f = ctx.f;
const casos = [
  [["Río Gall (25 de mayo)", "Rio Gallegos", "Santa Cruz"], "Río Gall (25 de mayo) · Rio Gallegos, Santa Cruz"],
  [["Chacabuco 228- Mendoza", "Mendoza", "Mendoza"], "Chacabuco 228- Mendoza"],
  [["Multi Bazar S.R.L — Brc Moreno", "Bariloche", "Río Negro"], "Brc Moreno · Bariloche, Río Negro"],
  [["", "Bariloche", "Río Negro"], "Bariloche, Río Negro"],
  [["Retira", "", ""], ""],
  [["", "", ""], ""]
];
for (const [a, esp] of casos) { const r = f(...a); if (r !== esp) fails.push("(a) " + JSON.stringify(a) + " → " + JSON.stringify(r) + " (esperado " + JSON.stringify(esp) + ")"); }
if (!/class="pga-dreal"/.test(utf) || !/_dst\.es_expreso/.test(utf)) fails.push("(b) falta el chip de Programación");
if (!/function aprDirRealChip/.test(utf) || !/aprDestinoChip\(p\) \+ aprDirRealChip\(p\)/.test(utf)) fails.push("(b) falta el chip de A Programar");
const fx = fn("_facXlsArmar");
const iOb = fx.indexOf("String(m.order_id) === String(_ob.order_id)"), iCands = fx.indexOf("const cands = suc ? [] :");
if (iOb < 0 || iCands < 0 || iOb > iCands) fails.push("(c) la sucursal del Excel ISIS no busca primero por order_id");
if (!/sucsTop\.size > 1 \? ""/.test(fx)) fails.push("(c) el empate de la heurística sigue adivinando");
if (fails.length) { console.error("FALLA ppp-dir-real-expreso:\n  " + fails.join("\n  ")); process.exit(1); }
console.log("OK ppp-dir-real-expreso");
