// v28.32 (Luis, 07/10): «que figure en ese módulo la fecha en la que el cliente mandó el pedido»
// — Cuarentena → «Ya programados» y Programación muestran «📥 dd/mm» (gvFechaPedChip).
const fs = require("fs"), vm = require("vm");
const src = fs.readFileSync(__dirname + "/../index.html", "latin1");
function fn(name) {
  const i = src.indexOf("function " + name + "(");
  if (i < 0) throw new Error("falta " + name);
  let d = 0, j = src.indexOf("{", i);
  for (let k = j; k < src.length; k++) { if (src[k] === "{") d++; else if (src[k] === "}" && --d === 0) return src.slice(i, k + 1); }
}
let ok = true; const fail = (m) => { ok = false; console.log("✗ " + m); };
const ctx = { escapeHtml: (s) => String(s), _mapa: new Map() };
vm.createContext(ctx);
vm.runInContext('var GV_DOW3 = ["Dom", "Lun", "Mar", "Mié", "Jue", "Vie", "Sáb"];\nfunction _pppFechaPedOf(np){ return _mapa.get(np) || null; }\n' + [fn("gvDiaDate"), fn("gvDiaTxt"), fn("gvFechaPedChip")].map(x => Buffer.from(x, "latin1").toString("utf8")).join("\n"), ctx);
let h = ctx.gvFechaPedChip("LK 0298", "2026-09-30", "2026-10-15", "x");
if (!/📥 Mié 30\/09/.test(h)) fail("chip con la fecha de la fila: " + h);
if (!/15 días corridos hasta la entrega/.test(h)) fail("días hasta la entrega: " + h);
ctx._mapa.set("LK 0298", { f: "2026-09-30", h: "09:50" });
h = ctx.gvFechaPedChip("LK 0298", "", "2026-10-15");
if (!/a las 09:50/.test(h) || !/📥 Mié 30\/09/.test(h)) fail("cae al mapa GV_NP_Fecha_Pedido con hora: " + h);
if (ctx.gvFechaPedChip("98000", "", "") !== "") fail("sin dato no inventa");
const yp = fn("cuarYaProgHtml");
if (!/Pidi/.test(yp) || !/gvFechaPedChip\(r\.np/.test(yp)) fail("Cuarentena ya programados sin columna Pedido");
if (!/gvFechaPedChip\(r\.np, r\.fecha_pedido, r\.fecha, "pga-ped"\)/.test(src)) fail("Programación sin el chip");
if (ctx.gvDiaTxt("2026-10-07") !== "Mié 07/10") fail("gvDiaTxt: " + ctx.gvDiaTxt("2026-10-07"));
console.log(ok ? "✓ fecha del pedido en Cuarentena y Programación" : "FALLÓ");
process.exit(ok ? 0 : 1);
