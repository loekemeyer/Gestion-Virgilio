// v23.23 (Luis): el Excel de Pedidos Importación baja lo mismo que se ve en pantalla.
// Parado en un proveedor se ven todos sus ítems (aunque no pidan nada, ej. 440E) y el Excel
// los filtraba por "a pedir > 0" y de todos los proveedores; las MC tocadas a mano no llegaban.
const fs = require("fs"), vm = require("vm");
const src = (fs.readFileSync(__dirname + "/../index.html", "latin1") + "\n" + fs.readFileSync(__dirname + "/../importacion.js", "latin1"));
function fn(name) {
  const i = src.indexOf("function " + name + "(");
  if (i < 0) throw new Error("no encuentro " + name);
  let d = 0, j = src.indexOf("{", i);
  for (let k = j; k < src.length; k++) { const c = src[k]; if (c === "{") d++; else if (c === "}") { d--; if (!d) return src.slice(i, k + 1); } }
}
let html = "";
const ctx = {
  _stkPop: null, _IMPORTADOR_DE: {}, console,
  // v24.55 — _pedImpMcOf aplica la regla del 80 % del MOQ: acá el MOQ va en 0 (no toca las cantidades del test).
  _NAC_TASAS: { moq: 0, moq_meses_max: 12, moq_pct: 0.8 }, _impProvNum: (p, k, d) => d,
  codCanon: (c) => c, artNombre: (c, d) => d || c, pedImpQTerms: () => [], pedImpMatch: () => true,
  alert: () => {}, Blob: function (p) { html = p.join(""); }, URL: { createObjectURL: () => "u", revokeObjectURL: () => {} },
  document: { createElement: () => ({ click() {} }), body: { appendChild() {}, removeChild() {} } }, setTimeout: () => {},
};
vm.createContext(ctx);
// v23.45: el Excel usa _impCodVista/_impPlantaVista desde la v23.28 → se cargan también.
["_impLRuteo", "_impCodVista", "_impPlantaVista", "_pedImpMoqCalc", "_pedImpMcOf", "_pedImpUniOf", "_pedImpUsdOf", "_pedImpM3Of", "_pedImpMesesStock", "_pedImpPrioCmp", "_pedImpMesesFmt", "_pedImpDdmm", "pedImpExportExcel"].forEach((n) => vm.runInContext(fn(n), ctx));
const items = [
  { cod: "440E", key: "440E", prov: "Ningbo", aPedirUni: 0, aPedirCajas: 0, uniMaster: 24, fobUni: 3.95 },
  { cod: "590E", key: "590E", prov: "Ningbo", aPedirUni: 240, aPedirCajas: 10, uniMaster: 24, fobUni: 1, m3Master: 0.1 },
  { cod: "999E", key: "999E", prov: "Otro", aPedirUni: 48, aPedirCajas: 2, uniMaster: 24 },
];
let fallas = 0;
const ok = (c, m) => { if (!c) { fallas++; console.error("FALLA: " + m); } };
// 1) parado en un proveedor: todos sus ítems, ninguno de otro
ctx._stkPop = { kind: "pedImp", data: { items }, soloPedir: true, provFiltro: "Ningbo", mcOverride: {} };
vm.runInContext("pedImpExportExcel()", ctx);
ok(html.includes(">440E<"), "parado en Ningbo, el 440E (a pedir 0) tiene que salir en el Excel");
ok(!html.includes(">999E<"), "parado en Ningbo, no puede salir un ítem de otro proveedor");
// 2) vista Todos + Solo Pedido: sólo lo que pide, y la MC tocada a mano manda
html = "";
ctx._stkPop = { kind: "pedImp", data: { items }, soloPedir: true, provFiltro: "", mcOverride: { "440E": 5 } };
vm.runInContext("pedImpExportExcel()", ctx);
ok(html.includes(">440E<"), "con MC a mano = 5, el 440E tiene que salir");
ok(html.includes("<td>5</td>"), "la MC a mano (5) tiene que llegar a la columna Master cjs");
ok(html.includes(">999E<"), "vista Todos: el de otro proveedor que pide tiene que salir");
if (fallas) process.exit(1);
console.log("imp-excel-igual-pantalla: OK");
