// v25.43 (Luis) — la hoja de armado (cola de impresión NP) trae el detalle del PICKING:
// inicio/fin del TP y, por código de ESTA NP, pedido · pickeado · faltante · hora (PKC).
const fs = require("fs");
const s = fs.readFileSync(__dirname + "/../index.html", "utf8");
const grab = n => { const i = s.indexOf("function " + n + "("); if (i < 0) throw new Error("falta " + n); let d = 0; for (let k = s.indexOf("{", i); ; k++) { if (s[k] == "{") d++; if (s[k] == "}" && !--d) return s.slice(i, k + 1); } };
global.TZ_AR = "America/Argentina/Buenos_Aires"; global.escapeHtml = x => String(x);
eval(["_remitoCodKey", "_remitoPkKey", "_remitoPickingDe", "_remitoHm", "_remitoPickingHtml"].map(grab).join("\n") + ";global.F=_remitoPickingDe;global.G=_remitoPickingHtml;");
let bad = 0; const ok = (c, m) => { if (!c) { bad++; console.log("✗", m); } else console.log("✓", m); };
const d = { arts: [{ cod: "026L" }, { cod: "809E" }], faltantes: [{ cod: "948EL", cajas: 1 }] };
const pk = F(d, { "26": { cod: "26", esp: 3, real: 3, ts: "2026-10-01T12:05:00Z" }, "809E LK": { cod: "809E LK", esp: 1, real: 1 }, "948E": { cod: "948E", esp: 2, real: 1 }, "555": { cod: "555", esp: 1, real: 1 } }, { ini: "2026-10-01T11:11:00Z", fin: "2026-10-01T12:28:00Z" });
ok(pk.lineas.map(x => x.cod).join() === "26,809E LK,948E", "sólo los códigos de la NP (L y sufijo de empresa pelados)");
const h = G(pk);
ok(/08:11/.test(h) && /09:28/.test(h) && /1:17 h/.test(h), "inicio, fin y duración");
ok(/<td>2<\/td><td>1<\/td><td>1<\/td>/.test(h), "faltante = pedido − pickeado");
ok(/09:05/.test(h), "hora del PKC");
ok(/fuera del flujo guiado/.test(G(F(d, null, { ini: null, fin: null }))), "sin PKC lo dice");
ok(s.indexOf("_remitoPickingHtml(d.picking)") > 0 && s.indexOf("opcion=eq.PKC&or=(") > 0, "la hoja lo dibuja y la cola lo pide");
process.exit(bad ? 1 : 0);
