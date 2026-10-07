/* v27.62 (Luis, 07/10): «🔗 Vincular» a una razón social que ya es cliente en CUALQUIER etapa abierta del
   pipeline de clientes nuevos. Corre pipeAccionesBtns de verdad con cada etapa y mira que esté el botón
   (y que NO esté en aprobado / cancelado). Sale 1 si falla. */
const fs = require("fs");
const src = fs.readFileSync(__dirname + "/../index.html", "latin1");
const i = src.indexOf("function pipeAccionesBtns(p)");
if (i < 0) { console.log("pipe-vincular-todas-etapas: no está pipeAccionesBtns ✗ FAIL"); process.exit(1); }
let j = src.indexOf("\n}\n", i);
const fn = Buffer.from(src.slice(i, j + 2), "latin1").toString("utf-8");
let etapa = "";
const ctx = {
  pipeEtapa: () => etapa, clinWppTel: () => "1100000000", pipeEst: () => ({}),
  escapeHtml: (x) => String(x),
};
const run = new Function(...Object.keys(ctx), fn + "\nreturn pipeAccionesBtns;")(...Object.values(ctx));
const abiertas = ["ingresado", "analisis", "referenciado", "no_referenciado", "speech1", "speech2", "pagado"];
const fallas = [];
for (const e of abiertas) { etapa = e; if (!/pipeVincAbrir\(/.test(run({ empresa: "lk", order_id: 1 }))) fallas.push(e + " sin Vincular"); }
for (const e of ["aprobado", "cancelado"]) { etapa = e; if (/pipeVincAbrir\(/.test(run({ empresa: "lk", order_id: 1 }))) fallas.push(e + " con Vincular"); }
fallas.forEach((f) => console.log("  ✗ " + f));
console.log("pipe-vincular-todas-etapas: " + (abiertas.length + 2 - fallas.length) + "/" + (abiertas.length + 2) + " · " + (fallas.length ? "✗ FAIL" : "✓ OK"));
process.exit(fallas.length ? 1 : 0);
