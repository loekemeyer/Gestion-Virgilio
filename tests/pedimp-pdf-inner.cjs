// v24.40 — el PDF del pedido de importación lleva INNER CAJAS (unidades ÷ uni_inner).
// Corre pedImpPdfProv de verdad (extraída del index) con dependencias mockeadas.
const fs = require("fs"), path = require("path"), vm = require("vm");
const src = fs.readFileSync(path.join(__dirname, "..", "index.html"), "utf8");
function fn(name) {
  const i = src.indexOf("function " + name + "(");
  if (i < 0) throw new Error("no está " + name);
  let d = 0, j = src.indexOf("{", i);
  for (let k = j; k < src.length; k++) { if (src[k] === "{") d++; else if (src[k] === "}") { d--; if (!d) return src.slice(i, k + 1); } }
}
let out = "";
const ctx = {
  _stkPop: { data: { items: [
    { cod: "590E", prov: "Kangli", uniMaster: 48, uniInner: 12, mc: 3 },
    { cod: "323E", prov: "Kangli", uniMaster: 24, uniInner: 0, mc: 2 },
    { cod: "890E", prov: "Kangli", uniMaster: 60, uniInner: 0, innerSuelto: true, mc: 1 },
    { cod: "999E", prov: "Otro",   uniMaster: 10, uniInner: 5, mc: 1 },
  ] } },
  _pedImpMcOf: it => it.mc, codCanon: c => c, _impCodVista: it => it.cod, _impPlantaVista: () => "",
  escapeHtml: s => String(s), remitoPrintDoc: h => { out = h; }, alert: () => {}, Number, Math, Date, String, decodeURIComponent,
};
vm.createContext(ctx);
vm.runInContext([fn("_pedImpUniOf"), fn("_pedImpInnerOf"), fn("pedImpPdfProv")].join("\n"), ctx);
ctx.pedImpPdfProv("Kangli");
const txt = out.replace(/<[^>]+>/g, "|").replace(/\|+/g, "|");
const fails = [];
if (!/Inner Cajas/.test(out)) fails.push("falta el encabezado Inner Cajas");
if (!/\|590E\|3\|12\|144\|/.test(txt)) fails.push("590E: 3 MC · 12 inner · 144 u — dio " + txt);
if (!/\|323E\|2\|—\|48\|/.test(txt)) fails.push("323E sin uni_inner tiene que ir con —");
if (!/\|890E\|1\|suelto\|60\|/.test(txt)) fails.push("890E suelto (uni_inner = 0) tiene que decir suelto — dio " + txt);
if (!/\|TOTAL\|6\|12\*\|252\|/.test(txt)) fails.push("TOTAL 6 · 12* · 252 — dio " + txt);
if (!/\* 1 artículo/.test(out)) fails.push("el suelto no cuenta como faltante: la nota tiene que decir 1 artículo");
if (/999E/.test(txt)) fails.push("se coló otro proveedor");
if (fails.length) { console.log("✗ pedimp-pdf-inner\n  " + fails.join("\n  ")); process.exit(1); }
console.log("✓ pedimp-pdf-inner: el PDF lleva Inner Cajas y marca las que faltan");
