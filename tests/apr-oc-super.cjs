// v23.34 (Luis, 28/09): el nro de OC del súper (leído del PDF) se ve en A Programar y en Programación.
// LK lo manda como prefijo de la observación: "OC 48074398093 · <obs>".
const fs = require("fs"), vm = require("vm");
const src = fs.readFileSync(__dirname + "/../index.html", "utf8");
function fn(name) {
  const i = src.indexOf("function " + name + "(");
  if (i < 0) throw new Error("falta " + name);
  let d = 0, j = src.indexOf("{", i);
  for (let k = j; k < src.length; k++) { if (src[k] === "{") d++; else if (src[k] === "}" && --d === 0) return src.slice(i, k + 1); }
}
const ctx = { escapeHtml: (s) => String(s).replace(/</g, "&lt;"), _aprOc: {},
  aprHorKey: (e, c) => String(e).toLowerCase() + ":" + c, pppEmpDePedido: (p) => p.empresa };
vm.createContext(ctx);
vm.runInContext([fn("gvOcDeObs"), fn("gvOcChip"), fn("aprOcBadge")].join("\n"), ctx);
let bad = 0; const ok = (c, m) => { if (!c) { bad++; console.error("✗ " + m); } else console.log("✓ " + m); };
ok(ctx.gvOcDeObs("OC 48074398093") === "48074398093", "lee la OC sola");
ok(ctx.gvOcDeObs("OC 23080640 · entregar por la tarde") === "23080640", "lee la OC con observación atrás");
ok(ctx.gvOcDeObs("Urgente, OC 123") === "", "no inventa OC de un comentario libre");
ok(ctx.aprOcBadge({ empresa: "lk", order_id: 1564, obs_pedido: "" }) === "", "sin dato no hay chip");
ctx._aprOc = { "lk:1564": "48074398093" };
ok(/OC 48074398093/.test(ctx.aprOcBadge({ empresa: "lk", order_id: 1564 })), "A Programar muestra la OC del mapa");
ok(/aprOcBadge\(p\)/.test(src) && /gvOcChip\(gvOcDeObs\(_pgaObsDe\(r\)\)\)/.test(src), "el chip está en la tarjeta y en la fila de Programación");
process.exit(bad ? 1 : 0);
