/* v21.48 — CLIENTE NUEVO RECURRENTE (Luis, 23/09).

   "ese cliente nuevo esta en su segundo pedido... no hace falta volver a hacer el analisis.
    Para clientes nuevos recurrentes (que todavia no tienen 3 pedidos completados) deberia
    directamente abrir el 'que sigue' en speech 1, speech 2 y agregar la opcion de marcarlo
    como referido"

   Se corre la botonera de verdad (pipeAccionesBtns) y se mira:
     1. en no_referenciado / speech1 / speech2 hay botón 🤝 Referenciado;
     2. un pedido en «ingresado» sigue ofreciendo 🔎 Análisis Cred. (el nuevo de verdad);
     3. el chip 🔁 recurrente sale cuando el backend dice recurrente;
     4. el SQL deriva no_referenciado de GV_Clientes_Nuevos.pedidos >= 1.
   Sale 1 si falla. */
const fs = require("fs"), path = require("path"), vm = require("vm");
const root = path.join(__dirname, "..");
const html = fs.readFileSync(path.join(root, "index.html"), "utf8");
const sql = fs.readFileSync(path.join(root, "sql", "gv_clin_recurrente_v2148.sql"), "utf8");
const fallos = [];
function fn(name) {
  const i = html.indexOf("function " + name + "(");
  if (i < 0) throw new Error("no está " + name);
  let d = 0, j = html.indexOf("{", i);
  for (let k = j; k < html.length; k++) {
    if (html[k] === "{") d++; else if (html[k] === "}") { d--; if (!d) return html.slice(i, k + 1); }
  }
}
const ctx = { _apr: { pipe: {} }, escapeHtml: s => String(s), clinWppTel: () => "1",
  cuarFechaHora: s => s, pipeClave: o => String(o).replace(/^np/i, ""),
  pipeRelojHtml: () => "", cuarEmpCod: e => e === "chef" ? "CH" : "LK" };
vm.createContext(ctx);
["pipeEst", "pipeEtapa", "pipeVincOtrosHtml", "pipeMemoriaHtml", "pipeAccionesBtns"].forEach(n => vm.runInContext(fn(n), ctx));
const p = { empresa: "lk", order_id: "1448", cod: "4282" };
function btns(etapa, extra) { ctx._apr.pipe = { "lk:1448": Object.assign({ etapa }, extra || {}) }; return ctx.pipeAccionesBtns(p); }

["no_referenciado", "speech1", "speech2"].forEach(et => {
  if (!/'referenciado','Marcar REFERENCIADO'/.test(btns(et))) fallos.push(et + ": falta el botón Referenciado");
});
if (!/pipeAnalisis/.test(btns("ingresado"))) fallos.push("ingresado: perdió el Análisis Cred.");
if (/Análisis Cred/.test(btns("no_referenciado", { recurrente: true }))) fallos.push("recurrente ofrece Análisis");
ctx._apr.pipe = { "lk:1448": { etapa: "no_referenciado", recurrente: true, pedidos_previos: 1 } };
if (!/recurrente/.test(ctx.pipeMemoriaHtml(p))) fallos.push("falta el chip 🔁 recurrente");
if (!/ped_prev >= 1 then 'no_referenciado'/.test(sql)) fallos.push("SQL: no deriva no_referenciado del recurrente");

if (fallos.length) { console.error("✗ pipe-recurrente:\n  " + fallos.join("\n  ")); process.exit(1); }
console.log("✓ pipe-recurrente: recurrente arranca en Speech y se puede marcar Referenciado");
