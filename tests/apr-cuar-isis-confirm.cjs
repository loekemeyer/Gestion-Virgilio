/* v22.20 (Luis, 24/09) — programar a mano no saltea la cuarentena por los dos caminos que quedaban:
   (a) una NP de ISIS retenida en aprGenerarTanda -> confirm (Lin Liqin / Iro Iro salieron sin aviso);
   (b) sumar a una tanda existente (aprSoltarPedido) -> freno para web, confirm para ISIS.
   Candado estatico sobre el codigo sin comentarios. */
const fs = require("fs"), path = require("path");
const src = fs.readFileSync(path.join(__dirname, "..", "index.html"), "latin1")
  .replace(/\/\*[\s\S]*?\*\//g, "").replace(/(^|[^:"'\\])\/\/[^\n]*/g, "$1");
const cuerpo = (nombre) => { const i = src.indexOf(nombre); if (i < 0) return ""; const j = src.indexOf("\nfunction ", i + 10), k = src.indexOf("\nasync function ", i + 10);
  const fin = Math.min(j < 0 ? Infinity : j, k < 0 ? Infinity : k); return src.slice(i, fin); };
const gen = cuerpo("async function aprGenerarTanda("), sol = cuerpo("async function aprSoltarPedido(");
const f = [];
if (!/_isisSel\.filter\(function \(p\) \{ return aprEnCuarentena\(p\); \}\)/.test(gen)) f.push("(a) aprGenerarTanda no mira la cuarentena de las NP de ISIS");
if (!/_isisRet\.length && !confirm\(/.test(gen)) f.push("(a) falta el confirm para la NP de ISIS retenida");
if (!/aprEnCuarentena\(p\)/.test(sol)) f.push("(b) aprSoltarPedido no mira la cuarentena");
if (!/if \(!p\._isis\)[\s\S]{0,300}return;/.test(sol)) f.push("(b) aprSoltarPedido no frena el pedido web retenido");
if (f.length) { console.error("apr-cuar-isis-confirm: FALLA\n  " + f.join("\n  ")); process.exit(1); }
console.log("apr-cuar-isis-confirm: OK — NP de ISIS retenida pide confirmación y sumar a tanda respeta la cuarentena");
