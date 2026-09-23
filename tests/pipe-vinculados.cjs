/* v21.60 (Luis, 23/09) — "que se vea para el chequeo de clientes nuevos en la PPP".
   El pipeline de clientes nuevos muestra los OTROS codigos del cliente real (tabla canonica
   clientes_vinculados de LK, espejada en GV_Clientes_Vinculados), por la RPC
   gv_clientes_vinculados_lote. Se corre el chip de verdad. Sale 1 si falla. */
const fs = require("fs"), path = require("path"), vm = require("vm");
const html = fs.readFileSync(path.join(__dirname, "..", "index.html"), "utf8");
function fn(name) {
  const i = html.indexOf("function " + name + "(");
  if (i < 0) throw new Error("no está " + name);
  let d = 0; for (let k = html.indexOf("{", i); k < html.length; k++) {
    if (html[k] === "{") d++; else if (html[k] === "}" && !--d) return html.slice(i, k + 1);
  }
}
const fallos = [];
const ctx = { _apr: { pipe: {}, cliVinc: {} }, escapeHtml: s => String(s), cuarFechaHora: s => s,
  pipeClave: o => String(o).replace(/^np/i, ""), cuarEmpCod: e => e === "chef" ? "CH" : "LK" };
vm.createContext(ctx);
["pipeEst", "pipeVincOtrosHtml", "pipeMemoriaHtml"].forEach(n => vm.runInContext(fn(n), ctx));
const p = { empresa: "lk", order_id: "1", cod: "4223" };
if (ctx.pipeMemoriaHtml(p) !== "") fallos.push("sin vinculos no tiene que dibujar nada");
ctx._apr.cliVinc = { "lk:4223": { otros: [{ empresa: "lk", cod: "4070", razon_social: "Higa Maria Valeria", ultima_compra: "2025-09-16" }] } };
const h = ctx.pipeMemoriaHtml(p);
if (!/🔗 1 código más/.test(h)) fallos.push("falta el chip 🔗 con el vinculo: " + h);
if (!/LK 4070 Higa/.test(h)) fallos.push("el chip no nombra el otro codigo");
if (!/pipeVincCargar\(lista\)/.test(html)) fallos.push("pipeCargar no pide los vinculos");
if (!/gv_clientes_vinculados_lote/.test(html)) fallos.push("no usa la RPC gv_clientes_vinculados_lote");
if (fallos.length) { console.error("✗ pipe-vinculados:\n  " + fallos.join("\n  ")); process.exit(1); }
console.log("✓ pipe-vinculados: el pipeline muestra los otros códigos del cliente real");
